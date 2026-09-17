-- Rollback for 141 — restores kernel.withdraw_account_deletion to 077's body, verbatim,
-- and drops the notify function 141 added. Removes the F-NOTICE-1 retire and nothing else.
-- Code, not data: rows retired while 141 was applied keep their read_at/dismissed_at,
-- which is the state a withdrawn request should leave behind in any case.
-- Rollbacks live OUTSIDE supabase/migrations/ — the CLI parses a file there as a duplicate version.

begin;

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

  -- Expired Q5 approvals are NOT resurrected (§3.1.2: expiry is a release).
  return jsonb_build_object('status', 'ok', 'deletion_state', 'ACTIVE');
end;
$$;

drop function if exists notify.retire_account_deletion_pending(uuid);

commit;
