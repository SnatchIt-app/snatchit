-- =============================================================================
-- 141 — withdrawing an account deletion retires that user's pending deletion notice
-- =============================================================================
-- F-NOTICE-1 (A, 2026-09-17). Observed on Build 19: the DV buyer is ACTIVE, has no
-- pending deletion and no `public.account_deletions` row, yet still sees
-- "Account deletion requested".
--
-- ROOT CAUSE, reproduced on a replay before this was written: `request_account_deletion`
-- (077) emits `account_deletion_pending`; `notify.drain_outbox` (092) materialises it;
-- `withdraw_account_deletion` (077) clears deletion_state, deletion_requested_at and
-- deletion_block_reason — and does nothing about the notice already delivered. It emits
-- no withdrawal event and retires nothing, so the notice stays live for ever.
--
-- WHAT THIS CHANGES: one new INTERNAL notify function, and one added call inside
-- kernel.withdraw_account_deletion whose body is otherwise 077's, verbatim. No new
-- notify type, no template, no job, nothing outbound, no public-schema object — so the
-- Gate-2 public census and the grant-decision manifest are unchanged, and
-- `create or replace` keeps withdraw_account_deletion's existing grants.
-- The five-schema routine census in 157 A46 moves 305 -> 306 by exactly this function.
--
-- WHY THE RETIRE LIVES IN notify: 157 A48 asserts that no routine in kernel, venue,
-- catalog or market references notify's tables. The first draft of this fix updated
-- notify.notification directly from kernel and A48 failed it — correctly. The seam holds.
--
-- WHAT IT DELIBERATELY DOES NOT DO (the owner's "smallest safe fix", 2026-09-17):
--   * it does not tell the user their withdrawal succeeded — that needs a new in-app
--     notify type and templates, which is a catalog change, not the smallest fix;
--   * it does not cancel undelivered push/email rows for the retired notice;
--   * it does not touch any notice belonging to anyone else, including the DV buyer's
--     current stale row on the sandbox, which is a separate scoped plan.
--
-- FORWARD-ONLY, deliberately (B's review of c70a9a6): the retire sits AFTER the
-- noop_replay early return, so an identity that is ALREADY ACTIVE with a stale notice —
-- exactly the DV buyer's case — is never healed by calling withdraw again. Healing an
-- existing row is a data change on someone's inbox, and that belongs in the owner's
-- scoped plan, not in a migration that runs everywhere.
--
-- ROLLBACK: supabase/rollbacks/141_withdraw_retires_deletion_notice_rollback.sql
-- restores 077's body verbatim and drops the notify function. Code, not data: notices
-- retired while 141 was applied stay retired, which is correct for them anyway.
-- TESTS: supabase/tests/208_withdraw_retires_deletion_notice.sql (19, with the negative
-- controls by type and by user), plus 157 A46's updated census.
-- =============================================================================

begin;

-- ── the retire, inside notify, where the notification tables live ────────────
-- Internal: no API role may execute it (principle 4 — service_role included). Its only
-- caller is kernel.withdraw_account_deletion, a definer owned by postgres.
create or replace function notify.retire_account_deletion_pending(p_recipient uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  if p_recipient is null then
    raise exception 'precondition_failed: recipient required' using errcode = 'P0001';
  end if;
  -- Narrow by construction: this identity, this one type, and only rows still live, so a
  -- second withdrawal is a no-op and a notice the user already read or dismissed keeps
  -- its own timestamps (coalesce, never an overwrite).
  update notify.notification n
     set read_at      = coalesce(n.read_at, now()),
         dismissed_at = coalesce(n.dismissed_at, now())
   where n.recipient_id = p_recipient
     and n.type_key     = 'account_deletion_pending'
     and (n.read_at is null or n.dismissed_at is null);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
comment on function notify.retire_account_deletion_pending(uuid) is
  '141 (F-NOTICE-1): retire a withdrawing identity''s live account_deletion_pending notices. The type is hardcoded, the recipient is the only parameter, and rows already read or dismissed keep their own timestamps. Internal: kernel.withdraw_account_deletion is the only caller.';
revoke all on function notify.retire_account_deletion_pending(uuid) from public, anon, authenticated, service_role;

create or replace function kernel.withdraw_account_deletion(p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid;
  v_state text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;

  select e.deletion_state into v_state
    from kernel.identity_ext e where e.identity_id = v_uid for update;

  if not found or v_state = 'ACTIVE' then
    return jsonb_build_object('status', 'noop_replay', 'deletion_state', 'ACTIVE');
  end if;
  if v_state = 'ERASED' then
    -- ERASED is terminal: no exit to ACTIVE exists in Phase 2 (dsm §1.3).
    raise exception 'precondition_failed: identity is erased — no resurrection path exists';
  end if;

  update kernel.identity_ext
     set deletion_state        = 'ACTIVE',
         deletion_requested_at = null,
         deletion_block_reason = null
   where identity_id = v_uid;

  -- 141 (F-NOTICE-1): retire the notice the request raised, THROUGH notify's own API.
  -- The seam (157 A48) forbids a kernel routine from touching notify's tables, and it is
  -- right: the first draft of this fix did exactly that and A48 caught it. The retire
  -- lives in notify.retire_account_deletion_pending, which hardcodes the type so it
  -- cannot be repurposed to clear anything else.
  -- NOT best-effort, unlike the emit in request_account_deletion: that one wraps a
  -- possible lock wait on a concurrent outbox insert (PFA-2), whereas this is a local
  -- update of this identity's own rows in the same transaction. An ACTIVE account
  -- carrying a live deletion notice is the exact state this migration exists to prevent,
  -- so if the retire cannot be done the withdrawal must not claim to have happened.
  perform notify.retire_account_deletion_pending(v_uid);

  -- Expired Q5 approvals are NOT resurrected (§3.1.2: expiry is a release).
  return jsonb_build_object('status', 'ok', 'deletion_state', 'ACTIVE');
end;
$$;

commit;
