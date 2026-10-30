-- =============================================================================
-- 140_proof_upload_repair.sql — F-IMG-1 outcomes 1 and 2 (A's contract, 2026-09-17)
--
-- WHY. Two defects, both locally reproduced on the rehearsal DB before this was
-- written:
--
--   (1) LOST RESPONSE READS AS FAILURE. mark_transfer_sent raises unless status
--       is exactly 'pending'. When the RPC commits and the HTTP response is lost,
--       the transfer IS sent with its proof — and the seller's retry gets
--       'Transfer cannot be marked as sent from current status: seller_sent.'
--       A success presented as a failure, plus an orphaned second upload.
--
--   (2) PROOF STRANDED FOREVER. transfer_evidence_path is written only on the
--       pending -> seller_sent transition, and mark_transfer_sent is its only
--       writer. A transfer marked sent WITHOUT a path could never be given one:
--       every later call raises on the status check. The buyer's
--       'transfer party read' policy matches on that path, so the proof was not
--       merely missing — it was unreachable, permanently.
--
-- CORRECTION TO B'S OWN EARLIER WRITE-UP, recorded because the mechanism matters
-- for the fix below: B reported that the append-only trigger blocked any later
-- change. It does not. guard_transfer_state_columns raises only when OLD is
-- NOT NULL and NEW differs (065:257-259), so a null -> value write passes the
-- guard with NO bypass. Measured here before relying on it: null -> value ok;
-- value -> different value raises 'transfer_evidence_path is append-only.';
-- value -> same value is a no-op and passes. The permanence came from the VERB's
-- status check, not from the guard. §2 below depends on that distinction.
--
-- WHAT THIS DOES NOT DO: no backfill, no batch, no weakening of the append-only
-- rule, no new client requirement. Accepted proof is never replaced.
--
-- Census: public functions 107 -> 108 (attach_transfer_evidence is new; the two
-- mark_transfer_sent signatures are dropped and recreated, net zero). Tables,
-- policies and triggers unchanged. expected_grants.txt untouched — no new table.
-- Manifest gains one authenticated-execute row. pgTAP 207.
-- =============================================================================
begin;

-- ── 1. mark_transfer_sent — idempotent, and it now answers rather than raises ──
-- A create-or-replace cannot change a return type, so both signatures are
-- dropped and recreated, with their grants re-issued exactly as 0553 had them.
drop function if exists public.mark_transfer_sent(uuid, uuid, text);
drop function if exists public.mark_transfer_sent(uuid, uuid);

create function public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid, p_transfer_evidence_path text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid; v_status text; v_seller uuid; v_path text; v_sent timestamptz;
begin
  v_caller := auth.uid();
  if v_caller is null and public.request_is_service_role() then v_caller := p_user_id; end if;
  if v_caller is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  select t.status, t.seller_id, t.transfer_evidence_path, t.seller_sent_at
    into v_status, v_seller, v_path, v_sent
    from public.transfers t
   where t.id = p_transfer_id
     for update;                                   -- two concurrent retries serialize here
  if not found then raise exception 'Transfer not found.'; end if;
  if v_seller is distinct from v_caller then
    raise exception 'Only the seller can mark a transfer as sent.';
  end if;

  -- ALREADY SENT: answer with what is recorded, write nothing. This is the
  -- lost-response retry — with no path, the same path, or a DIFFERENT path.
  -- Accepted proof is never replaced, so a second upload stays an orphan the
  -- seller may delete under the owner-delete policy. Because no UPDATE happens,
  -- the transfer-sent notification triggers do not fire a second time.
  if v_status = 'seller_sent' then
    if v_path is null and p_transfer_evidence_path is not null then
      -- Do NOT let mark-sent become a silent backfill route; §2 is the explicit one.
      raise exception 'precondition_failed: transfer already sent without evidence — use attach_transfer_evidence'
        using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'outcome', 'already_sent', 'status', v_status, 'seller_sent_at', v_sent,
      'transfer_evidence_path', v_path, 'evidence_replaced', false);
  end if;

  -- Any other status is a genuine conflict and still raises, message unchanged.
  if v_status <> 'pending' then
    raise exception 'Transfer cannot be marked as sent from current status: %.', v_status;
  end if;

  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers t
     set status = 'seller_sent',
         seller_sent_at = pg_catalog.now(),
         auto_release_at = pg_catalog.now() + interval '72 hours',
         transfer_evidence_path = coalesce(p_transfer_evidence_path, t.transfer_evidence_path)
   where t.id = p_transfer_id
   returning t.seller_sent_at, t.transfer_evidence_path into v_sent, v_path;

  return jsonb_build_object(
    'outcome', 'transitioned', 'status', 'seller_sent', 'seller_sent_at', v_sent,
    'transfer_evidence_path', v_path, 'evidence_replaced', false);
end;
$$;

-- The 2-arg overload (the payload shipped build 13 sends) delegates, so the two
-- can never drift apart.
create function public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.mark_transfer_sent(p_transfer_id, p_user_id, null::text);
end;
$$;

comment on function public.mark_transfer_sent(uuid, uuid, text) is
  '140: marks a pending transfer sent and returns {outcome, status, seller_sent_at, transfer_evidence_path, evidence_replaced}. IDEMPOTENT: a retry on an already-sent transfer returns outcome=already_sent and writes nothing, so a lost response is no longer reported to the seller as a failure and no notification fires twice. Accepted proof is never replaced. A sent transfer with no proof refuses here and must use attach_transfer_evidence. Every other status still raises.';
comment on function public.mark_transfer_sent(uuid, uuid) is
  '140: 2-argument overload (shipped build 13 payload) — delegates to the 3-argument form with a null evidence path.';

revoke execute on function public.mark_transfer_sent(uuid, uuid, text) from public, anon;
revoke execute on function public.mark_transfer_sent(uuid, uuid)       from public, anon;
grant  execute on function public.mark_transfer_sent(uuid, uuid, text) to authenticated, service_role;
grant  execute on function public.mark_transfer_sent(uuid, uuid)       to authenticated, service_role;

-- ── 2. attach_transfer_evidence — the explicit recovery, never a backfill ─────
create or replace function public.attach_transfer_evidence(p_transfer_id uuid, p_transfer_evidence_path text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid; v_status text; v_seller uuid; v_path text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_transfer_evidence_path is null or p_transfer_evidence_path = '' then
    raise exception 'precondition_failed: evidence path is required' using errcode = 'P0001';
  end if;

  select t.status, t.seller_id, t.transfer_evidence_path
    into v_status, v_seller, v_path
    from public.transfers t
   where t.id = p_transfer_id
     for update;
  if not found then raise exception 'Transfer not found.'; end if;
  if v_seller is distinct from v_caller then
    raise exception 'insufficient_privilege: only the seller can attach evidence' using errcode = '42501';
  end if;
  if v_status <> 'seller_sent' then
    raise exception 'precondition_failed: evidence can only be attached to a sent transfer (status: %)', v_status
      using errcode = 'P0001';
  end if;

  -- The path must be the caller's own object, in the evidence folder, and REAL:
  -- a dangling path would record proof that cannot be fetched.
  if pg_catalog.split_part(p_transfer_evidence_path, '/', 1) <> v_caller::text then
    raise exception 'precondition_failed: evidence path must be inside the caller''s own folder' using errcode = 'P0001';
  end if;
  if p_transfer_evidence_path not like '%/transfer-evidence/%' then
    raise exception 'precondition_failed: evidence path must be under transfer-evidence/' using errcode = 'P0001';
  end if;
  if not exists (select 1 from storage.objects o
                  where o.bucket_id = 'proof-docs' and o.name = p_transfer_evidence_path) then
    raise exception 'precondition_failed: no such object in proof-docs' using errcode = 'P0001';
  end if;

  -- Same path twice is the retry of a successful attach: answer, write nothing.
  if v_path is not null and v_path = p_transfer_evidence_path then
    return jsonb_build_object('outcome', 'already_attached', 'status', v_status,
                              'transfer_evidence_path', v_path, 'evidence_replaced', false);
  end if;

  -- NO BYPASS. The guard is left armed on purpose: null -> value passes it, and a
  -- second attach with a DIFFERENT path is refused by the guard itself
  -- ('transfer_evidence_path is append-only.'). The append-only rule is not
  -- weakened anywhere in this migration.
  update public.transfers t
     set transfer_evidence_path = p_transfer_evidence_path
   where t.id = p_transfer_id;

  return jsonb_build_object('outcome', 'attached', 'status', v_status,
                            'transfer_evidence_path', p_transfer_evidence_path, 'evidence_replaced', false);
end;
$$;

comment on function public.attach_transfer_evidence(uuid, text) is
  '140: the seller''s explicit recovery for a transfer marked sent with no proof — the one case mark_transfer_sent refuses. Requires seller, status seller_sent, a currently null path, the caller''s own folder, under transfer-evidence/, and an object that actually exists in proof-docs. Writes WITHOUT the guard bypass, so the append-only rule still refuses any replacement. One seller, one row, one explicit action: no backfill, no batch, no service_role fallback in v1.';

revoke execute on function public.attach_transfer_evidence(uuid, text) from public, anon, service_role;
grant  execute on function public.attach_transfer_evidence(uuid, text) to authenticated;

commit;
