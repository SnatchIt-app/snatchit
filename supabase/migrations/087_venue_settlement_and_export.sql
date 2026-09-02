-- ============================================================================
-- 087_venue_settlement_and_export.sql — Phase-2 package 087 (family I).
-- Frozen sources: plan §8/087 · schema §3.13/§3.14/§3.18 · RPC §10.1-10.3/§17.22/
--   §20.11 · RLS §9.13/§9.14/§16.6/§16.11a · CRM export spec · DEMOGRAPHICS X-6 ·
--   ODR16 #34 · O17/MD-2/OR-1 (postgres-owned builder, NO crm_export_builder role) ·
--   PFA-9 (CRM limit/cap/retention keys have NO frozen spelling → NOT seeded here;
--   the rate limits are the frozen CRM §7.1 numbers, in-RPC) · SEAM-2a.
-- Settlement money rollup (SSCAS #4) + the CRM attendee-export lifecycle. Native
-- issuance/sale stay DARK, so the roster/lines are empty until activation — the
-- machinery is authored and replay-tested regardless.
-- Deps: 077, 081, 085, 086. Rollback posture: CLEAN-WHILE-EMPTY then forward-fix.
-- ============================================================================

begin;

-- ============================================================================
-- PART 1 — kernel.settlement_line_candidate (RPC §20.11.1; C116/S2-A).
--   Created BEFORE the two hook stubs that RETURN SETOF it (else 42704). The
--   composite's amount_minor is bigint (registry authoritative) though the
--   settlement_line column is integer — the seams return ZERO rows at 087, so the
--   width divergence is inert until 088/090 fill them (noted forward).
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace
                  where n.nspname='kernel' and t.typname='settlement_line_candidate') then
    create type kernel.settlement_line_candidate as (
      cause        text,
      cause_ref    uuid,
      amount_minor bigint,
      currency     text,
      payee_kind   text,
      payee_id     uuid
    );
  end if;
end $$;

-- ============================================================================
-- PART 2 — venue.settlement (schema §3.13; the money rollup header).
--   Four money columns are NULL while open, written EXACTLY ONCE by
--   kernel.close_settlement in the txn that moves open→closed. status='paid' is
--   written ONLY by venue.on_payout_settled. The waterfall is a table CHECK.
-- ============================================================================
create table if not exists venue.settlement (
  settlement_id uuid primary key default gen_random_uuid(),
  org_id        uuid not null references kernel.organization(org_id) on delete restrict,
  venue_id      uuid not null references catalog.venue(venue_id) on delete restrict,
  event_id      uuid references catalog.event(event_id) on delete restrict,   -- nullable (period settlement)
  period_start  timestamptz,
  period_end    timestamptz,
  status        text not null default 'open' check (status in ('open','closed','paid')),
  gross_minor   integer,
  fees_minor    integer,
  refunds_minor integer,
  net_minor     integer,
  currency      text not null default 'USD',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- §3.13.1 waterfall identity: a closed/paid header must carry all four money
  -- columns and net_minor must equal its own waterfall. Unstorable otherwise.
  constraint settlement_waterfall_ck check (
    status = 'open'
    or (gross_minor is not null and fees_minor is not null
        and refunds_minor is not null and net_minor is not null
        and net_minor = gross_minor - fees_minor - refunds_minor)
  )
);
create index if not exists settlement_org_status_idx on venue.settlement (org_id, status);
create index if not exists settlement_event_idx on venue.settlement (event_id);
drop trigger if exists tg_settlement_set_updated_at on venue.settlement;
create trigger tg_settlement_set_updated_at before update on venue.settlement
  for each row execute function kernel.set_updated_at();
alter table venue.settlement enable row level security;
revoke all on venue.settlement from anon, authenticated;
grant select on venue.settlement to authenticated;   -- reads via org/venue finance policy; writes RPC-only
-- org-scoped read: org finance (owner/admin/finance) over the settlement's org,
-- OR venue finance/manager over the settlement's venue, OR platform.
drop policy if exists venue_settlement_sel_org on venue.settlement;
create policy venue_settlement_sel_org on venue.settlement for select to authenticated
  using (kernel.has_org_role(org_id, array['org_owner','org_admin','org_finance'])
         or kernel.is_platform(array['platform_admin','platform_support','platform_risk']));
drop policy if exists venue_settlement_sel_venue on venue.settlement;
create policy venue_settlement_sel_venue on venue.settlement for select to authenticated
  using (kernel.has_venue_role(venue_id, array['venue_manager','venue_finance']));

-- ============================================================================
-- PART 3 — venue.settlement_line (schema §3.14; AO immutable money lines).
--   amount_minor is SIGNED (credits +, debits −). UNIQUE(settlement_id,cause,
--   cause_ref): a cause contributes one line PER settlement. The cross-settlement
--   promoter_commission unique is 090's, NOT here (087 must not know promoters).
-- ============================================================================
create table if not exists venue.settlement_line (
  id                 uuid primary key default gen_random_uuid(),
  settlement_id      uuid not null references venue.settlement(settlement_id) on delete restrict,
  cause              text not null check (cause in (
                       'issue','primary_sale','comp','door_sale','p2p_transfer','market_sale',
                       'auction_sale','admin_action','refund_void','import','promoter_commission',
                       'settlement','chargeback')),   -- D3 closed set (schema §0.5)
  cause_ref          uuid not null,
  amount_minor       integer not null,               -- signed
  currency           text not null default 'USD',
  is_rounding_bearer boolean not null default false,  -- C31: absorbs the 3-way-split residual
  occurred_at        timestamptz,
  created_at         timestamptz not null default now(),
  constraint settlement_line_cause_uq unique (settlement_id, cause, cause_ref)
);
create index if not exists settlement_line_settlement_idx on venue.settlement_line (settlement_id);
create index if not exists settlement_line_cause_ref_idx on venue.settlement_line (cause_ref);
-- AO: INSERT-only (the close engine writes; nobody updates/deletes).
drop trigger if exists tg_settlement_line_append_only on venue.settlement_line;
create trigger tg_settlement_line_append_only before update or delete on venue.settlement_line
  for each row execute function kernel.raise_append_only();
alter table venue.settlement_line enable row level security;
revoke all on venue.settlement_line from anon, authenticated;
revoke update, delete on venue.settlement_line from service_role;   -- AO
grant select on venue.settlement_line to authenticated;
drop policy if exists venue_settlement_line_sel_org on venue.settlement_line;
create policy venue_settlement_line_sel_org on venue.settlement_line for select to authenticated
  using (exists (select 1 from venue.settlement s where s.settlement_id = venue.settlement_line.settlement_id
                  and (kernel.has_org_role(s.org_id, array['org_owner','org_admin','org_finance'])
                       or kernel.is_platform(array['platform_admin','platform_support','platform_risk']))));
drop policy if exists venue_settlement_line_sel_venue on venue.settlement_line;
create policy venue_settlement_line_sel_venue on venue.settlement_line for select to authenticated
  using (exists (select 1 from venue.settlement s where s.settlement_id = venue.settlement_line.settlement_id
                  and kernel.has_venue_role(s.venue_id, array['venue_manager','venue_finance'])));

-- ============================================================================
-- PART 4 — venue.export_job (schema §3.18; the CRM export lifecycle + purge
--   substrate — K-3). Contains NO customer rows. DENY-ALL, zero client policies
--   (OR-1: no crm_export_builder role; build_export_rows is postgres-owned and
--   reads its own row as table owner). TWO independent state machines on one row:
--   state (job) and artifact_state (the bytes). as_of frozen at REQUEST;
--   gate_as_of stamped at CLAIM (re-stamped on re-claim) — consent is not
--   membership (CRM §5.3/K-19). requested_by RESTRICT (ODR16 #34, not CASCADE).
-- ============================================================================
create table if not exists venue.export_job (
  job_id            uuid primary key default gen_random_uuid(),
  scope_kind        text not null check (scope_kind in ('session','event','venue','org')),   -- EX-1: no 'all'
  scope_id          uuid not null,
  org_id            uuid not null references kernel.organization(org_id) on delete restrict,  -- frozen at request
  template_id       text,
  template_version  integer,
  filters           jsonb,                            -- normalized + sorted at write
  as_of             timestamptz not null,             -- frozen at REQUEST (roster membership)
  gate_as_of        timestamptz,                      -- stamped at CLAIM, re-stamped on re-claim (consent gate)
  state             text not null check (state in ('queued','running','ready','failed','revoked','expired','purged')),
  requested_by      uuid not null references auth.users(id) on delete restrict,   -- ODR16 #34: untouched on erasure
  command_key       text not null,
  lease_until       timestamptz,                      -- 064 BUILD claim lease
  row_count         integer,
  byte_count        integer,
  artifact_sha256   text,
  object_path       text,
  contact_cells_emitted    integer not null default 0,   -- accumulated in-definer by build_export_rows;
  contact_cells_suppressed integer not null default 0,   -- NOT NULL: null ≡ a gate that ran and emitted nothing
  name_cells_emitted       integer not null default 0,
  name_cells_suppressed    integer not null default 0,
  failure_code      text check (failure_code is null or failure_code in ('too_large','scope_unreachable','build_error','limit_exceeded')),
  requested_at      timestamptz not null default now(),
  ready_at          timestamptz,
  expires_at        timestamptz,
  purge_after       timestamptz,
  -- the K-3 purge substrate (the artifact's own lifecycle, separate from the job's):
  artifact_state    text not null default 'absent' check (artifact_state in ('absent','present','delete_pending','deleted')),
  purge_lease_until timestamptz,                      -- 064 PURGE claim lease, distinct from lease_until
  purge_attempts    integer not null default 0,       -- >3 delete_pending cycles ⇒ platform_risk signal
  constraint export_job_command_uq unique (requested_by, command_key)   -- C16 idempotency
);
create index if not exists export_job_state_requested_idx on venue.export_job (state, requested_at);   -- /build drain (1 min)
create index if not exists export_job_artifact_expires_idx on venue.export_job (artifact_state, expires_at);  -- purge claim (15 min)
create index if not exists export_job_org_requested_idx on venue.export_job (org_id, requested_at);     -- history panel
alter table venue.export_job enable row level security;
revoke all on venue.export_job from anon, authenticated;   -- deny-all, EMPTY grant set, ZERO client policies (OR-1)

-- ============================================================================
-- PART 5 — the crm-exports private storage bucket (CRM §11; the 073 lesson:
--   create WITH constraints in one statement + a raising self-verify block, never
--   `on conflict do nothing`). public=false, 32MB, text/csv only. ZERO
--   storage.objects policies of any verb for anon/authenticated — the only
--   principal that touches the bytes is service_role inside the crm-export-worker
--   edge. Path is {org_id}/{job_id}.csv (org-owned; carries no venue/event/date).
-- ============================================================================
do $$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('crm-exports', 'crm-exports', false, 33554432, array['text/csv'])
  on conflict (id) do update
    set public = false, file_size_limit = 33554432, allowed_mime_types = array['text/csv'];
  -- fail-closed self-verify: the row MUST hold exactly the intended values.
  if not exists (select 1 from storage.buckets
                  where id='crm-exports' and public=false
                    and file_size_limit=33554432 and allowed_mime_types=array['text/csv']) then
    raise exception 'crm-exports bucket did not materialize with the intended private/32MB/text-csv constraints';
  end if;
end $$;

-- ============================================================================
-- PART 6 — settlement / payout engine.
-- ============================================================================

-- 6a — the two SEAM-2 hook stubs (RPC §20.11.1/2). Created HERE returning ZERO
--   rows; real bodies land in 088 (royalty ← market_sale) and 090 (commission ←
--   attribution). Signatures frozen (SEAM-2a). STABLE, pure, MUST NOT raise (a
--   raise would roll back close_settlement). At 087 they yield no candidate.
create or replace function kernel.settlement_royalty_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language sql stable security definer set search_path = ''
as $$ select * from (values (null::text, null::uuid, null::bigint, null::text, null::text, null::uuid)) v
      where false $$;   -- zero rows; real body 088 (market_sale royalty)

create or replace function kernel.settlement_commission_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language sql stable security definer set search_path = ''
as $$ select * from (values (null::text, null::uuid, null::bigint, null::text, null::text, null::uuid)) v
      where false $$;   -- zero rows; real body 090 (venue.attribution commission)

-- 6b — venue.open_settlement (RPC §10.1). INSERT an `open` header, money cols NULL.
--   SCOPE BINDING (AUTHZ-C1C — "a scope that does not bind to the subject is the
--   same defect"): the venue MUST belong to p_org_id and the event (if any) to that
--   venue and org, re-resolved here — otherwise org B's finance could open (and
--   later close, and be PAID for) a settlement over org A's venue. Unbound scopes
--   raise not_found (never insufficient_privilege: the caller must not learn the
--   venue exists). IDEMPOTENCY on (auth.uid(), p_command_key) rides the
--   settlement.open audit row this txn writes (schema §3.13 carries no key column
--   and 087 adds none): a replay returns the ORIGINAL header; a transaction-scoped
--   advisory lock serializes concurrent replays of one key.
create or replace function venue.open_settlement(
  p_org_id uuid, p_venue_id uuid, p_event_id uuid, p_period jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
  end if;
  if not (kernel.has_venue_role(p_venue_id, array['venue_finance'])
          or kernel.has_org_role(p_org_id, array['org_finance','org_owner'])) then
    raise exception 'insufficient_privilege: venue_finance or org_finance/org_owner required' using errcode = '42501';
  end if;
  -- C16 replay: the same actor + key returns the header it already opened.
  perform pg_advisory_xact_lock(hashtext('settlement.open:' || v_uid::text || ':' || p_command_key));
  select a.subject_id into v_id from kernel.admin_audit a
   where a.action = 'settlement.open' and a.actor_identity = v_uid and a.reason_code = p_command_key
   order by a.occurred_at limit 1;
  if v_id is not null then
    if not exists (select 1 from venue.settlement s where s.settlement_id = v_id and s.org_id = p_org_id
                     and s.venue_id = p_venue_id and s.event_id is not distinct from p_event_id) then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','idempotency_replay','settlement_id', v_id);
  end if;
  -- the scope binds to the subject: venue ∈ org; event ∈ venue ∧ org.
  if not exists (select 1 from catalog.venue v where v.venue_id = p_venue_id and v.org_id = p_org_id) then
    raise exception 'not_found: venue % for org %', p_venue_id, p_org_id using errcode = 'P0002';
  end if;
  if p_event_id is not null and not exists (select 1 from catalog.event e
       where e.event_id = p_event_id and e.venue_id = p_venue_id and e.org_id = p_org_id) then
    raise exception 'not_found: event % for venue % / org %', p_event_id, p_venue_id, p_org_id using errcode = 'P0002';
  end if;
  insert into venue.settlement (org_id, venue_id, event_id, period_start, period_end, status)
  values (p_org_id, p_venue_id, p_event_id,
          (p_period ->> 'period_start')::timestamptz, (p_period ->> 'period_end')::timestamptz, 'open')
  returning settlement_id into v_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (v_uid, 'settlement.open', 'settlement', v_id, p_command_key);
  return jsonb_build_object('status','ok','settlement_id', v_id);
end;
$$;

-- 6c — kernel.close_settlement (RPC §10.2; SSCAS #4). Rolls the immutable lines
--   into the four write-once money columns under the header's own FOR UPDATE and
--   generates the pending payout. At 087 the two seams return zero rows and the
--   R-40 chargeback arm's source (kernel.dispute_native) does not exist until 088,
--   so a settlement with no seeded lines closes at net=0 with NO payout (payout
--   requires amount_minor>0). Forward: 088 CREATE OR REPLACEs this with the
--   chargeback arm (+ the fee/royalty split and the C31 rounding-bearer
--   assignment, which need the first seam that produces a split) once
--   kernel.dispute_native lands (SEAM-1; recorded E-67).
--   BUCKETS ARE DERIVED FROM THE FROZEN SIGN CONVENTION, NOT FROM AN INVENTED
--   cause→bucket table (E-73): schema §3.14 lines are signed (credits +, debits −);
--   §3.13.1 gross = Σ positive revenue lines, fees = Σ the fee/royalty (debit)
--   lines, refunds = Σ the refund lines (D3 refund causes: refund_void,
--   chargeback). So: gross = Σ(amount>0, non-refund) · fees = −Σ(amount<0,
--   non-refund) · refunds = −Σ(refund-cause amounts) ⇒ net = Σ ALL lines exactly
--   (the header equals the sum of its lines, T-SCHEMA-SETTLE-04). Seams therefore
--   emit debits NEGATIVE (the §3.14 convention binds candidates too); a
--   candidate in a foreign currency is refused (one header, one currency).
create or replace function kernel.close_settlement(p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_s venue.settlement%rowtype; v_c kernel.settlement_line_candidate;
  v_gross bigint; v_fees bigint; v_refunds bigint; v_net bigint;
  v_payout_id uuid; v_ids uuid[] := '{}';
begin
  select * into v_s from venue.settlement where settlement_id = p_settlement_id for update;   -- SSCAS #4 rank-6
  if not found then raise exception 'not_found: settlement %', p_settlement_id using errcode = 'P0002'; end if;
  if not ((kernel.has_venue_role(v_s.venue_id, array['venue_finance'])
           and (select v.org_id from catalog.venue v where v.venue_id = v_s.venue_id) = v_s.org_id)   -- E-76: current operator
          or kernel.has_org_role(v_s.org_id, array['org_finance'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: venue_finance / org_finance / platform only' using errcode = '42501';
  end if;
  if v_s.status <> 'open' then   -- forward-only: a re-close is an idempotent replay
    return jsonb_build_object('status','noop_replay','net_minor', v_s.net_minor,
      'payout_ids', (select coalesce(array_agg(payout_id),'{}') from kernel.payout
                      where cause='settlement' and cause_ref=p_settlement_id));
  end if;
  -- generate the money lines from the two frozen seams (zero rows at 087).
  for v_c in select * from kernel.settlement_royalty_lines(p_settlement_id)
             union all select * from kernel.settlement_commission_lines(p_settlement_id) loop
    if v_c.cause is not null then
      if v_c.currency is not null and v_c.currency <> v_s.currency then
        raise exception 'precondition_failed: candidate currency % differs from the settlement currency %', v_c.currency, v_s.currency
          using errcode = 'P0001';
      end if;
      insert into venue.settlement_line (settlement_id, cause, cause_ref, amount_minor, currency)
      values (p_settlement_id, v_c.cause, v_c.cause_ref, v_c.amount_minor::integer, v_s.currency)
      on conflict (settlement_id, cause, cause_ref) do nothing;
    end if;
  end loop;
  if exists (select 1 from venue.settlement_line l where l.settlement_id = p_settlement_id and l.currency <> v_s.currency) then
    raise exception 'precondition_failed: settlement lines carry a currency other than the header''s' using errcode = 'P0001';
  end if;
  -- one derivation from the lines this settlement holds, by the frozen SIGN
  -- convention (E-73): credits + / debits −; refund causes are the refund bucket.
  -- net = gross − fees − refunds = Σ all lines, exactly.
  select coalesce(sum(amount_minor)  filter (where amount_minor > 0 and cause not in ('refund_void','chargeback')), 0),
         coalesce(sum(-amount_minor) filter (where amount_minor < 0 and cause not in ('refund_void','chargeback')), 0),
         coalesce(sum(-amount_minor) filter (where cause in ('refund_void','chargeback')), 0)
    into v_gross, v_fees, v_refunds from venue.settlement_line where settlement_id = p_settlement_id;
  v_net := v_gross - v_fees - v_refunds;
  update venue.settlement
     set status='closed', gross_minor=v_gross::integer, fees_minor=v_fees::integer,
         refunds_minor=v_refunds::integer, net_minor=v_net::integer, updated_at=now()
   where settlement_id = p_settlement_id;
  -- generate the pending payout only when there is positive net (kernel.payout
  -- amount_minor > 0). Deterministic idempotency on (cause, cause_ref, payee).
  if v_net > 0 then
    insert into kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, currency, status, idempotency_key)
    values ('organization', v_s.org_id, 'settlement', p_settlement_id, v_net::integer, v_s.currency, 'pending',
            'settlement:' || p_settlement_id::text)
    on conflict (idempotency_key) do nothing
    returning payout_id into v_payout_id;
    if v_payout_id is not null then v_ids := array[v_payout_id]; end if;
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'settlement.close', 'settlement', p_settlement_id, coalesce(p_command_key,'close'));
  -- net_minor is a READ-BACK of the column this function wrote (§10.2 R1-2), never a local.
  return jsonb_build_object('status','ok','payout_ids', v_ids,
           'net_minor', (select net_minor from venue.settlement where settlement_id = p_settlement_id));
end;
$$;

-- 6d — venue.on_payout_settled (RPC §20.11.5). CREATE OR REPLACE of the 085
--   SEAM-2 stub. The SOLE writer of venue.settlement.status='paid'. DEF,
--   service_role only; called only by kernel.mark_payout_transfer_state in the
--   same txn as the payout → paid write. Signature frozen (SEAM-2a).
create or replace function venue.on_payout_settled(p_payout_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_po kernel.payout%rowtype; v_sid uuid;
begin
  select * into v_po from kernel.payout where payout_id = p_payout_id;
  if not found then return; end if;
  if v_po.cause <> 'settlement' then return; end if;   -- silent no-op for non-settlement payouts
  v_sid := v_po.cause_ref;
  perform 1 from venue.settlement where settlement_id = v_sid for update;   -- after the caller's payout lock
  if not found then return; end if;
  if exists (select 1 from venue.settlement where settlement_id = v_sid and status = 'open') then
    raise exception 'precondition_failed: settlement % is open, not closed', v_sid using errcode = 'P0001';
  end if;
  -- advance closed → paid iff NO cause='settlement' payout of this settlement is
  -- in a non-paid state (the negative completeness predicate). Already-paid: no-op.
  if not exists (select 1 from kernel.payout where cause='settlement' and cause_ref=v_sid and status <> 'paid') then
    update venue.settlement set status='paid', updated_at=now() where settlement_id=v_sid and status='closed';
    if found then
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
      values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'settlement.paid', 'settlement', v_sid, 'payout_settled');
    end if;
  end if;
end;
$$;

-- 6e — kernel.request_org_payout (RPC §10.3; MONEY §6.7/§8/§9.2). EDGE-FRONTED:
--   records the request intent; the DB never moves money. Preconditions (frozen):
--   settlement closed · payout pending · destination not locked
--   (payout_destination_locked_until) · settlement.org_id = p_org_id re-resolved
--   under the settlement's lock (AUTHZ-C1C → not_found). The FOUR controls:
--   SoD-1 destination-setter exclusion (permanent) · money-role maturity
--   (sod_violation) · step-up (AUTHZ-M4: no aal claim → step_up_unavailable,
--   not aal2 → step_up_required) · destination PROBATION (§17.7 control 2: the
--   first payout after a destination change within payout.destination_probation_days
--   is NOT advanced — hold_state := 'probation_hold', hold_reason_code, held_at,
--   held_by := NULL, status untouched; released only by kernel.release_payout;
--   NULL key ⇒ X-12 ⇒ any change counts). Then the tier: above (or NULL — X-12)
--   payout.dual_control_min_minor it PARKS kernel.approval_request
--   (action='payout.request', class 'org', amount + pinned config_versions) and
--   returns pending_approval; an already-parked pending request is returned, not
--   duplicated; an APPROVED request for this payout advances it (E-74: 085's
--   approve arm records the approval, the contracted writer of pending→submitted
--   performs the advance); below the threshold it advances directly. Every arm
--   writes payout.request / payout.probation_hold audit (§10.3 Writes); a payout
--   already submitted replays as noop_replay. Locks: Settlement → Organization →
--   Payout FOR UPDATE → Approval INSERT (SSCAS #4 continuation). The R-40
--   open-dispute gate lands with kernel.dispute_native (088; E-67).
create or replace function kernel.request_org_payout(p_org_id uuid, p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_s venue.settlement%rowtype; v_po kernel.payout%rowtype; v_org kernel.organization%rowtype;
  v_threshold bigint; v_threshold_ver integer; v_req uuid; v_aal text;
  v_prob_days integer; v_changed_at timestamptz; v_ar kernel.approval_request%rowtype;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_finance']) then
    raise exception 'insufficient_privilege: org_owner or org_finance required' using errcode = '42501';
  end if;
  select * into v_s from venue.settlement where settlement_id = p_settlement_id for update;   -- SSCAS #4 rank-6
  if not found or v_s.org_id <> p_org_id then   -- AUTHZ-C1C: the scope binds to the subject, under the lock
    raise exception 'not_found: settlement % for org %', p_settlement_id, p_org_id using errcode = 'P0002';
  end if;
  if v_s.status = 'open' then
    raise exception 'precondition_failed: settlement not closed' using errcode = 'P0001';
  end if;
  -- the org row under lock: SoD-1 setter, cool-down, the probation operand.
  select * into v_org from kernel.organization o where o.org_id = p_org_id for update;
  if v_org.payout_destination_set_by is not null and v_org.payout_destination_set_by = v_uid then
    raise exception 'sod_violation: the payout-destination setter cannot request a payout';
  end if;
  if not kernel.money_role_grant_matured(p_org_id) then
    raise exception 'sod_violation: org money grant not yet matured';
  end if;
  -- AUTHZ-M4 step-up: an absent claim is never a pass or a fail.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to request a payout';
  end if;
  if v_org.payout_destination_locked_until is not null and v_org.payout_destination_locked_until > now() then
    raise exception 'precondition_failed: destination cool-down until %', v_org.payout_destination_locked_until using errcode = 'P0001';
  end if;
  if v_org.stripe_connect_account_ref is null then   -- a disbursement needs a destination; a NULL one strands the money at the edge   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
    raise exception 'precondition_failed: no_payout_destination — the org has no Stripe Connect destination bound' using errcode = 'P0001';
  end if;
  select * into v_po from kernel.payout
   where cause = 'settlement' and cause_ref = p_settlement_id and status in ('pending','submitted')
   order by (status = 'pending') desc, created_at limit 1 for update;   -- a pending sibling is never shadowed by a submitted one
  if not found then
    raise exception 'precondition_failed: no pending payout for this settlement' using errcode = 'P0001';
  end if;
  if v_po.status = 'submitted' then
    return jsonb_build_object('status','noop_replay','payout_id', v_po.payout_id);
  end if;
  if v_po.hold_state = 'probation_hold' then   -- still held: the request is recorded and declined again
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'probation_held', jsonb_build_object('settlement_id', p_settlement_id));
    return jsonb_build_object('status','probation_held','payout_id', v_po.payout_id);
  elsif v_po.hold_state <> 'none' then   -- a platform RISK hold is not a request outcome (§10.3 result set): fail closed
    raise exception 'precondition_failed: payout_held — a platform risk hold must be released before a request' using errcode = 'P0001';
  end if;
  -- DESTINATION PROBATION (§10.3 third arm). Operand: the last destination change
  -- (the org.payout_destination.change audit row 085 writes) inside the window;
  -- "first payout" = no payout of this org reached `paid` since that change.
  select (c.value #>> '{}')::integer into v_prob_days from catalog.platform_config c
   where c.key = 'payout.destination_probation_days' order by c.version desc limit 1;
  -- the change instant: the 085 destination-change audit OR the 077 first bind (a fresh destination
  -- is the archetypal fresh destination — the restrictive reading, E-86).
  select max(a.occurred_at) into v_changed_at from kernel.admin_audit a
   where a.action in ('org.payout_destination.change','org.connect_ref.bind')
     and a.subject_kind = 'organization' and a.subject_id = p_org_id;
  if v_changed_at is not null
     and (v_prob_days is null or v_changed_at > now() - make_interval(days => v_prob_days))   -- NULL ⇒ X-12 restrictive
     -- "the FIRST payout": no payout of this org was SYNCED to paid since the change (the 085
     -- payout.state_sync audit row — never updated_at, which a later overlay may bump).
     and not exists (select 1 from kernel.admin_audit a2 join kernel.payout p on p.payout_id = a2.subject_id
                      where p.payee_org_id = p_org_id and a2.subject_kind = 'payout' and a2.action = 'payout.state_sync'
                        and a2.after ->> 'status' = 'paid' and a2.occurred_at > v_changed_at)
     -- a platform_risk/platform_admin RELEASE OF THIS PROBATION (kernel.release_payout, the sole release
     -- path, reason = the probation hold's own reason) is the human decision the arm exists to obtain:
     -- it is not re-imposed (T-RPC-MONEY-32). A risk-hold release does not count.
     and not exists (select 1 from kernel.admin_audit a where a.subject_kind = 'payout' and a.subject_id = v_po.payout_id
                       and a.action = 'payout.release' and a.reason_code = 'destination_probation'
                       and a.occurred_at >= v_changed_at) then   -- >=: same-transaction instants
    update kernel.payout
       set hold_state = 'probation_hold', hold_reason_code = 'destination_probation', held_at = now(), held_by = null, updated_at = now()
     where payout_id = v_po.payout_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.probation_hold', 'payout', v_po.payout_id, 'destination_probation',
            jsonb_build_object('settlement_id', p_settlement_id, 'destination_changed_at', v_changed_at));
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)   -- §10.3 Writes: payout.request on every arm
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'probation_held', jsonb_build_object('settlement_id', p_settlement_id));
    return jsonb_build_object('status','probation_held','payout_id', v_po.payout_id);
  end if;
  -- an APPROVED, unexpired dual-control request for THIS payout advances it (E-74) — but ONLY the
  -- destination it was approved against (E-85): an approval that predates the last destination
  -- change, or names another destination, is STALE and is never honoured.
  select * into v_ar from kernel.approval_request a
   where a.action = 'payout.request' and a.subject_kind = 'settlement' and a.subject_id = p_settlement_id
     and a.state = 'approved' and a.expires_at > now() and (a.payload ->> 'payout_id')::uuid = v_po.payout_id
   order by a.updated_at desc limit 1;
  if found then
    if (v_ar.payload ->> 'destination_ref') is distinct from v_org.stripe_connect_account_ref   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
       or (v_changed_at is not null and v_ar.updated_at <= v_changed_at) then
      update kernel.approval_request set state = 'stale', updated_at = now() where request_id = v_ar.request_id;
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_uid, 'payout.request_stale', 'approval_request', v_ar.request_id, 'destination_changed',
              jsonb_build_object('payout_id', v_po.payout_id, 'settlement_id', p_settlement_id));
      -- fall through: a fresh park against the CURRENT destination
    else
      update kernel.payout set status = 'submitted', updated_at = now() where payout_id = v_po.payout_id;
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'approved_request',
              jsonb_build_object('settlement_id', p_settlement_id, 'request_id', v_ar.request_id, 'approved_by', v_ar.approved_by));
      return jsonb_build_object('status','submitted','payout_id', v_po.payout_id, 'request_id', v_ar.request_id);
    end if;
  end if;
  -- dual-control threshold: absent (NULL) ⇒ X-12 restrictive ⇒ always park.
  select (c.value #>> '{}')::bigint, c.version into v_threshold, v_threshold_ver from catalog.platform_config c
   where c.key = 'payout.dual_control_min_minor' order by c.version desc limit 1;
  if v_threshold is null or v_po.amount_minor >= v_threshold then
    -- a request already parked for this payout is returned, never duplicated.
    select * into v_ar from kernel.approval_request a
     where a.action = 'payout.request' and a.subject_kind = 'settlement' and a.subject_id = p_settlement_id
       and a.state = 'pending' and a.expires_at > now() and (a.payload ->> 'payout_id')::uuid = v_po.payout_id
     order by a.created_at limit 1;
    if found and (v_ar.payload ->> 'destination_ref') is not distinct from v_org.stripe_connect_account_ref then   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
      return jsonb_build_object('status','pending_approval','request_id', v_ar.request_id, 'payout_id', v_po.payout_id,
                                'required_approver_class', v_ar.required_approver_class);
    elsif found then   -- parked against a destination that has since changed: stale, park anew
      update kernel.approval_request set state = 'stale', updated_at = now() where request_id = v_ar.request_id;
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_uid, 'payout.request_stale', 'approval_request', v_ar.request_id, 'destination_changed',
              jsonb_build_object('payout_id', v_po.payout_id, 'settlement_id', p_settlement_id));
    end if;
    -- PARK: a second org money role must approve (kernel.approve verb, 085).
    insert into kernel.approval_request (action, required_approver_class, subject_kind, subject_id, org_id,
             payload, amount_minor, config_versions, requested_by, expires_at, command_idempotency_key)
    values ('payout.request', 'org', 'settlement', p_settlement_id, p_org_id,
            jsonb_build_object('payout_id', v_po.payout_id, 'tier', 'parked',
                               'destination_ref', v_org.stripe_connect_account_ref),   -- E-85: the approval binds to THIS destination   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
            v_po.amount_minor,
            jsonb_build_object('payout.dual_control_min_minor', v_threshold_ver),   -- pinned, never a parameter
            v_uid, now() + interval '72 hours',
            coalesce(p_command_key, 'req:' || p_settlement_id::text))
    on conflict do nothing
    returning request_id into v_req;
    if v_req is null then   -- same (actor, command key): the original request
      select a.request_id into v_req from kernel.approval_request a
       where a.requested_by = v_uid and a.command_idempotency_key = coalesce(p_command_key, 'req:' || p_settlement_id::text);
    end if;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'pending_approval',
            jsonb_build_object('settlement_id', p_settlement_id, 'request_id', v_req, 'required_approver_class', 'org'));
    -- best-effort notice (BE; dual control is enforced by the Approval row, not the notice).
    begin
      perform notify.emit_event('payout_request_pending_approval', 'settlement', p_settlement_id,   -- R2 row 20 (snake_case IN type)
              'payout_request:' || p_settlement_id::text,
              jsonb_build_object('org_id', p_org_id, 'amount_minor', v_po.amount_minor));
    exception when others then null; end;
    return jsonb_build_object('status','pending_approval','request_id', v_req, 'payout_id', v_po.payout_id,
                              'required_approver_class', 'org');
  else
    -- below an owner-set threshold: advance directly to submitted (the edge executes Stripe).
    update kernel.payout set status = 'submitted', updated_at = now() where payout_id = v_po.payout_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'submitted',
            jsonb_build_object('settlement_id', p_settlement_id));
    return jsonb_build_object('status','submitted','payout_id', v_po.payout_id);
  end if;
end;
$$;

-- ============================================================================
-- PART 7 — the CRM attendee-read + export surface (RPC §17.22/§20.7.8; CRM §4-§8/
--   §11.4; RLS §11.6/§16.6; X-1..X-9; OR-1/OR-10/OR-19; PFA-28).
--   THIRTEEN postgres-owned SECURITY DEFINER functions (OR-1: no crm_export_builder
--   role; the builder reads its own job row as table owner).
--   PFA-28 (OWNER-SIGNED 2026-09-01): the frozen customer_ref =
--   base32(HMAC-SHA256(org_customer_key, identity_id)[0..9]) has NO ratified in-DB
--   mechanism (pgcrypto is deliberately absent — PFA-20 class — and md5 is not an
--   HMAC). The THREE readers that must emit customer_ref (build_export_rows,
--   list_attendees, lookup_attendee) therefore FAIL CLOSED before returning any
--   customer data: no identity_id, no unkeyed hash, no truncated uuid, no NULL, no
--   random substitute. Authz, org scoping, filter grammar, gate_as_of stamping and
--   X-6 are all preserved so the un-park is a body-only change. The OR-19 lazy
--   key mint is deferred with it: "server-generated random 32 B" has no ratified
--   generator without pgcrypto (gen_random_bytes) and key custody is item 3/4 of
--   the CRM_CUSTOMER_REF_CRYPTO obligation — so NO kernel.org_customer_key row is
--   ever written at 087 (no key material exists to leak). Everything else — the
--   request/admission point, the job lifecycle, download re-authorization, revoke,
--   the sweep, the three purge definers and the orphan pass — is complete and live.
-- ============================================================================

-- 7a — venue.assert_may_request (RPC §20.7.8; OR-10 EXEC DEF; AUTHZ-CRM2/M13).
--   THE ONE shared export-authorization predicate: request, download and the
--   lister's `downloadable` all evaluate this body. It takes an ARBITRARY actor
--   (build_export_rows re-derives authority from job.requested_by, not from the
--   caller), so it reads the grant tables directly instead of through the
--   auth.uid()-bound helpers — same semantics as has_org_role/has_venue_role
--   (row existence, role membership), different actor binding.
--   XO-1a: the scope's org is resolved HERE from the scope object (session/event
--   → catalog.event.org_id, stamped at create; venue → catalog.venue.org_id, the
--   current operator; org → itself). Org grain: venue roles do NOT reach ("the
--   plane of the grant is the export scope"); venue/event/session grain: org roles
--   over the scope's org OR venue roles over the scope's venue. PLATFORM roles are
--   DENIED on every arm (CRM K-3 / MD-8: platform roles read the roster and never
--   use the venue CRM export). Raising by default (42501); p_raise := false is the
--   ONE greppable opt-out, used by list_export_jobs alone (T-RPC-CRM-06).
create or replace function venue.assert_may_request(
  p_actor uuid, p_scope_kind text, p_scope_id uuid, p_template_id text, p_raise boolean default true)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare
  v_org uuid; v_venue uuid; v_org_roles text[]; v_venue_roles text[]; v_ok boolean := false;
begin
  if p_actor is null or p_scope_id is null or p_scope_kind is null then
    if p_raise then raise exception 'insufficient_privilege: no actor or scope' using errcode = '42501'; end if;
    return false;
  end if;
  -- the two closed template allow-lists (CRM §6.4 / RLS §11.6). operations_v1 adds
  -- MONEY columns and is the narrowest allow-list in the corpus.
  if p_template_id = 'audience_v1' then
    v_org_roles   := array['org_owner','org_admin','org_marketing'];
    v_venue_roles := array['venue_manager','venue_marketing'];
  elsif p_template_id = 'operations_v1' then
    v_org_roles   := array['org_owner','org_admin'];
    v_venue_roles := array['venue_manager'];
  else
    if p_raise then raise exception 'invalid_input: unknown export template %', coalesce(p_template_id,'<null>'); end if;
    return false;
  end if;
  -- resolve the scope object → (org, venue). An unresolvable scope is a denial.
  if p_scope_kind = 'session' then
    select e.org_id, e.venue_id into v_org, v_venue
      from catalog.event_session s join catalog.event e on e.event_id = s.event_id
     where s.session_id = p_scope_id;
  elsif p_scope_kind = 'event' then
    select e.org_id, e.venue_id into v_org, v_venue from catalog.event e where e.event_id = p_scope_id;
  elsif p_scope_kind = 'venue' then
    select v.org_id, v.venue_id into v_org, v_venue from catalog.venue v where v.venue_id = p_scope_id;
  elsif p_scope_kind = 'org' then
    select o.org_id into v_org from kernel.organization o where o.org_id = p_scope_id;
    v_venue := null;   -- org grain: no venue role reaches an org-wide export
  end if;
  if v_org is not null then
    -- OPERATORSHIP BINDING (E-76): venue roles are keyed on the venue as a PLACE while
    -- catalog.venue.org_id is mutable. A venue role reaches a session/event scope only
    -- while the venue's CURRENT operator is the scope's org — otherwise the new
    -- operator's staff would reach the prior operator's exports and rosters (CRM §4.1).
    v_ok := exists (select 1 from kernel.org_member m
                     where m.org_id = v_org and m.identity_id = p_actor and m.role = any(v_org_roles))
         or (v_venue is not null
             and (select v.org_id from catalog.venue v where v.venue_id = v_venue) = v_org
             and exists (select 1 from venue.staff_role s
                     where s.venue_id = v_venue and s.identity_id = p_actor and s.role = any(v_venue_roles)));
  end if;
  if not v_ok and p_raise then
    raise exception 'insufficient_privilege: actor may not request or download a % export at this scope', p_template_id
      using errcode = '42501';
  end if;
  return v_ok;
end;
$$;

-- 7b — venue.request_export (RPC §17.22 / CRM §6.2 "request" / §11.4). The
--   authorization + admission point; BUILDS NO DATA. In one transaction: authorize
--   (raising mode), validate the closed conjunctive filter grammar (§6.5 — no OR/
--   NOT/nesting, no demographic member), enforce the §7.3 caps AT REQUEST (a too-
--   large job fails immediately as `failed/too_large` and never truncates — EX-7),
--   rate-limit fail-closed (the frozen §7.1 numbers IN-RPC — PFA-9: no frozen
--   config spelling — through the 005 limiter, per actor AND per org), FREEZE
--   as_of := now() and org_id := the scope's org (XO-1a), write the job row
--   `queued` and the crm_export.request audit row carrying constraint_set_version
--   (X-9; the 078 seed, read LIVE, NULL ⇒ refuse per X-12). Idempotent on
--   (auth.uid(), p_command_key). OR-19 lazy key mint: DEFERRED under PFA-28 (see
--   the Part-7 banner) — the table's only contracted writer writes nothing yet.
create or replace function venue.request_export(
  p_scope_kind text, p_scope_id uuid, p_template_id text, p_filters jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_org uuid; v_venue uuid; v_job uuid;
  v_existing venue.export_job%rowtype; v_csv text; v_filters jsonb; v_k text; v_v jsonb;
  v_from timestamptz; v_to timestamptz; v_sessions integer; v_rows bigint;
  v_state text := 'queued'; v_fail text; v_max_days integer;
begin
  if v_uid is null then
    raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501';
  end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
  end if;
  -- C16 idempotency: same actor + same command key ⇒ the ORIGINAL job, no second row.
  select * into v_existing from venue.export_job where requested_by = v_uid and command_key = p_command_key;
  if found then
    return jsonb_build_object('status','idempotency_replay','job_id', v_existing.job_id,
                              'state', v_existing.state, 'as_of', v_existing.as_of);
  end if;
  if p_scope_kind is null or p_scope_kind not in ('session','event','venue','org') then   -- EX-1: no 'all'
    raise exception 'invalid_input: scope_kind % is not a member of the closed set (EX-1)', coalesce(p_scope_kind,'<null>');
  end if;
  if p_template_id is null or p_template_id not in ('audience_v1','operations_v1') then
    raise exception 'invalid_input: unknown export template %', coalesce(p_template_id,'<null>');
  end if;
  -- AUTHORIZE — the one shared predicate, RAISING mode (AUTHZ-CRM2).
  perform venue.assert_may_request(v_uid, p_scope_kind, p_scope_id, p_template_id);
  -- XO-1a: resolve + FREEZE the job's org from the scope object, in THIS txn.
  if p_scope_kind = 'session' then
    select e.org_id, e.venue_id into v_org, v_venue
      from catalog.event_session s join catalog.event e on e.event_id = s.event_id where s.session_id = p_scope_id;
  elsif p_scope_kind = 'event' then
    select e.org_id, e.venue_id into v_org, v_venue from catalog.event e where e.event_id = p_scope_id;
  elsif p_scope_kind = 'venue' then
    select v.org_id, v.venue_id into v_org, v_venue from catalog.venue v where v.venue_id = p_scope_id;
  else
    v_org := p_scope_id;
  end if;
  if v_org is null then raise exception 'not_found: export scope % %', p_scope_kind, p_scope_id using errcode = 'P0002'; end if;
  -- FILTERS — the closed conjunctive grammar (CRM §6.5). An object of
  -- (field ∈ values) memberships ANDed; anything else raises. `promoter` is a
  -- member of the grammar but gated on 090 (absent-not-blank until then).
  v_filters := coalesce(p_filters, '{}'::jsonb);
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'invalid_input: filters must be a conjunctive object of memberships (EX-3)';
  end if;
  for v_k, v_v in select key, value from jsonb_each(v_filters) loop
    if v_k not in ('session','ticket_type','order_status','check_in_status','source','promoter',
                   'refund_state','acquired_via','email_present','date_window') then
      raise exception 'invalid_input: filter % is not a member of the closed grammar (X-2/EX-3)', v_k;
    end if;
    if v_k = 'promoter' then
      raise exception 'precondition_failed: the promoter filter is gated on package 090';
    elsif v_k = 'date_window' then
      if jsonb_typeof(v_v) <> 'object' or (v_v ->> 'from') is null or (v_v ->> 'to') is null then
        raise exception 'invalid_input: date_window must be a bounded {from,to}';
      end if;
      v_from := (v_v ->> 'from')::timestamptz; v_to := (v_v ->> 'to')::timestamptz;
      if v_to <= v_from then raise exception 'invalid_input: date_window must be bounded and ordered'; end if;
    elsif v_k = 'email_present' then
      if v_v not in ('true'::jsonb, 'false'::jsonb) then raise exception 'invalid_input: email_present must be true or false'; end if;
    else
      if jsonb_typeof(v_v) <> 'array' or jsonb_array_length(v_v) = 0
         or exists (select 1 from jsonb_array_elements(v_v) x where jsonb_typeof(x) <> 'string') then
        raise exception 'invalid_input: filter % must be a non-empty membership array of values (no nesting)', v_k;
      end if;
      -- every membership value is a bounded identifier: filters are persisted into the
      -- job row AND the immutable audit payload, so free text (an address, a name) must
      -- never be accepted (CRM §8.3 "never in an audit row"). refund_state's derived enum
      -- has no frozen spelling (PFA-9 class) — bounded identifiers, never free text.
      if exists (select 1 from jsonb_array_elements_text(v_v) x where x !~ '^[A-Za-z0-9_.:-]{1,64}$') then
        raise exception 'invalid_input: filter % values must be bounded identifiers (1-64 chars of [A-Za-z0-9_.:-])', v_k;
      end if;
      if v_k = 'order_status' and exists (select 1 from jsonb_array_elements_text(v_v) x
           where x not in ('pending','paid','partially_refunded','refunded','cancelled')) then
        raise exception 'invalid_input: order_status value outside the closed set';
      elsif v_k = 'check_in_status' and exists (select 1 from jsonb_array_elements_text(v_v) x
           where x not in ('not_scanned','admitted','already_used','other_non_admit')) then
        raise exception 'invalid_input: check_in_status value outside the closed set';
      elsif v_k = 'source' and exists (select 1 from jsonb_array_elements_text(v_v) x
           where x not in ('app','web','door','promoter_link')) then
        raise exception 'invalid_input: source value outside the closed set';
      elsif v_k = 'acquired_via' and exists (select 1 from jsonb_array_elements_text(v_v) x
           where x not in ('purchase','comp','transfer','resale','adjustment','import')) then
        raise exception 'invalid_input: acquired_via value outside the closed set';
      elsif v_k in ('session','ticket_type') and exists (select 1 from jsonb_array_elements_text(v_v) x
           where x !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
        raise exception 'invalid_input: % filter values must be ids within the scope', v_k;
      end if;
    end if;
  end loop;
  -- normalize + sort (§8.3): membership arrays sorted; jsonb already orders keys.
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_filters
    from (select key as k,
                 case when jsonb_typeof(value) = 'array'
                      then (select jsonb_agg(x order by x #>> '{}') from jsonb_array_elements(value) x)
                      else value end as v
            from jsonb_each(v_filters)) s;
  -- CAPS (§7.3) at request. Venue/org grain are anchored on scope+WINDOW (EX-1).
  if p_scope_kind in ('venue','org') then
    if v_from is null then
      raise exception 'invalid_input: a % -grain export must carry a bounded date_window (EX-1)', p_scope_kind;
    end if;
    v_max_days := case when p_scope_kind = 'venue' then 180 else 365 end;
    if v_to - v_from > make_interval(days => v_max_days) then
      raise exception 'precondition_failed: date_window exceeds % days for % grain — name a narrower scope', v_max_days, p_scope_kind;
    end if;
    select count(*) into v_sessions
      from catalog.event_session s join catalog.event e on e.event_id = s.event_id
     where s.starts_at >= v_from and s.starts_at < v_to
       and e.org_id = v_org
       and (p_scope_kind = 'org' or e.venue_id = p_scope_id);
    if v_sessions > 60 then
      raise exception 'precondition_failed: % sessions in window exceeds the cap of 60 — name a narrower scope', v_sessions;
    end if;
  end if;
  -- X-9: the constraint-set identifier in force, read LIVE. Absent ⇒ refuse (X-12).
  select c.value #>> '{}' into v_csv from catalog.platform_config c
   where c.key = 'crm_export.constraint_set_version' order by c.version desc limit 1;
  if v_csv is null then
    raise exception 'precondition_failed: crm_export.constraint_set_version is unset — no export may be audited without it (X-9)';
  end if;
  -- RATE LIMITS (§7.1) — fail-closed: a FALSE (over-limit OR limiter error) denies.
  if not public.check_rate_limit(v_uid, 'crm_export_request', 5, 86400) then
    raise exception 'rate_limited: crm_export_request per actor (5 / 24h)';
  end if;
  if not public.check_rate_limit(v_org, 'crm_export_request_org', 25, 86400) then
    raise exception 'rate_limited: crm_export_request per org (25 / 24h)';
  end if;
  -- ROW CAP (§7.3 / EX-7): the holder roster at as_of over the frozen org (XO-1a).
  -- Over 50 000 ⇒ the job is recorded `failed/too_large` and NEVER truncated.
  select count(*) into v_rows from kernel.tickets t
    join catalog.event_session s on s.session_id = t.event_session_id
    join catalog.event e on e.event_id = s.event_id
   where t.org_id = v_org and t.state <> 'voided'
     and case p_scope_kind
           when 'session' then t.event_session_id = p_scope_id
           when 'event'   then e.event_id = p_scope_id
           when 'venue'   then e.venue_id = p_scope_id and s.starts_at >= v_from and s.starts_at < v_to
           else s.starts_at >= v_from and s.starts_at < v_to end;
  if v_rows > 50000 then v_state := 'failed'; v_fail := 'too_large'; end if;
  insert into venue.export_job (scope_kind, scope_id, org_id, template_id, template_version, filters, as_of, state,
                                requested_by, command_key, failure_code, requested_at, purge_after)
  values (p_scope_kind, p_scope_id, v_org, p_template_id, 1, v_filters, now(), v_state,
          v_uid, p_command_key, v_fail, now(), now() + interval '13 months')   -- job-row retention §6.6
  returning job_id into v_job;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'crm_export.request', 'crm_export', v_job, 'request',
          jsonb_build_object('scope_kind', p_scope_kind, 'scope_id', p_scope_id, 'template_id', p_template_id,
                             'template_version', 1, 'filters', v_filters, 'as_of', now(),
                             'constraint_set_version', v_csv));
  if v_fail is not null then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'crm_export.fail', 'crm_export', v_job, v_fail,
            jsonb_build_object('row_estimate', v_rows, 'cap', 50000, 'narrower_scope',
              case p_scope_kind when 'org' then 'venue' when 'venue' then 'event' else 'session' end));
  end if;
  return jsonb_build_object('status','ok','job_id', v_job, 'state', v_state, 'as_of',
           (select as_of from venue.export_job where job_id = v_job), 'failure_code', v_fail);
end;
$$;

-- 7c — venue.build_export_rows (RPC §17.22; CRM §6.2 "build"; schema §3.18 A4:
--   the CLAIM writer). EXEC DEF, no human path. The worker's ONLY build entry, so
--   the claim lives here: page 1 (p_cursor NULL) takes the 064 lease
--   (queued→running, lease_until), STAMPS gate_as_of, zeroes the counters — and a
--   RE-claim after lease expiry re-stamps and rebuilds from page 1 (CRM §5.1 (1)/
--   (3): carrying the old instant across a retry is the fail-OPEN direction).
--   Authority is re-derived from the JOB ROW's actor + scope, never the caller;
--   a requester who lost the role ⇒ `failed/scope_unreachable`. §7.3 org
--   concurrency (2 running) is enforced at claim.
--   PFA-28: this is "the entire SQL surface that touches customer data" and it
--   cannot emit customer_ref, so after the claim it records the frozen failure
--   state (`failed`, failure_code='build_error', crm_export.fail with reason
--   customer_ref_crypto_unavailable) and returns ZERO rows. finalize_export then
--   refuses (state<>running) — no artifact can ever be produced for a job that
--   emitted no rows. The frozen return shape (row cursor + column names + cells,
--   deterministic order) is fixed here so the un-park is body-only. No dynamic
--   SQL (T-RPC-CRM-02). Never logs a row.
create or replace function venue.build_export_rows(p_job_id uuid, p_cursor text, p_limit integer)
returns table (row_cursor text, columns text[], cells text[])
language plpgsql security definer set search_path = ''
as $$
declare
  v_j venue.export_job%rowtype; v_running integer;
  v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';   -- SN-SYSTEM (078)
begin
  select * into v_j from venue.export_job where job_id = p_job_id for update;
  if not found then raise exception 'not_found: export job %', p_job_id using errcode = 'P0002'; end if;
  if v_j.state = 'queued' or (v_j.state = 'running' and (v_j.lease_until is null or v_j.lease_until < now())) then
    -- CLAIM (or RE-claim). §7.3: at most two live builds per org; a third waits.
    select count(*) into v_running from venue.export_job
     where org_id = v_j.org_id and state = 'running' and lease_until >= now() and job_id <> p_job_id;
    if v_running >= 2 then
      raise exception 'precondition_failed: org_concurrency — two builds already running for this org (CRM §7.3); queued behind'
        using errcode = 'P0001';
    end if;
    update venue.export_job
       set state = 'running', lease_until = now() + interval '10 minutes', gate_as_of = now(),
           row_count = 0, contact_cells_emitted = 0, contact_cells_suppressed = 0,
           name_cells_emitted = 0, name_cells_suppressed = 0
     where job_id = p_job_id
     returning * into v_j;
    -- EX-5: the claim is a state transition (queued→running) and leaves its row (E-77).
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_sys, 'crm_export.claim', 'crm_export', p_job_id, 'claim',
            jsonb_build_object('gate_as_of', v_j.gate_as_of, 'lease_until', v_j.lease_until));
  elsif v_j.state = 'running' then
    if p_cursor is null then
      raise exception 'precondition_failed: job is leased by a live build; a second claim may not restart it' using errcode = 'P0001';
    end if;
    update venue.export_job set lease_until = now() + interval '10 minutes' where job_id = p_job_id;
  else
    raise exception 'precondition_failed: export job % is % — not buildable', p_job_id, v_j.state using errcode = 'P0001';
  end if;
  -- authority re-derived from the JOB ROW (recorded actor + scope + template), through the
  -- ONE predicate in its RAISING mode (T-RPC-CRM-06: the opt-out has exactly one caller);
  -- a denial becomes the frozen failure state, not a raise out of the worker.
  begin
    perform venue.assert_may_request(v_j.requested_by, v_j.scope_kind, v_j.scope_id, v_j.template_id);
  exception when insufficient_privilege then
    update venue.export_job set state = 'failed', failure_code = 'scope_unreachable', lease_until = null where job_id = p_job_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
    values (v_sys, 'crm_export.fail', 'crm_export', p_job_id, 'scope_unreachable');
    return;
  end;
  -- ── PFA-28 FAIL-CLOSED PARK ─────────────────────────────────────────────────
  -- customer_ref (CRM §4.3) = base32(HMAC-SHA256(org_customer_key, identity_id)
  -- [0..9]) has no ratified mechanism in this database. Emitting any substitute
  -- is forbidden by owner ruling. The job is recorded in the frozen failure state
  -- and NO customer row is returned. Un-park = replace this block with the
  -- ratified builder (CRM_CUSTOMER_REF_CRYPTO); signature and return shape frozen.
  update venue.export_job set state = 'failed', failure_code = 'build_error', lease_until = null where job_id = p_job_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_sys, 'crm_export.fail', 'crm_export', p_job_id, 'customer_ref_crypto_unavailable',
          jsonb_build_object('pfa', 'PFA-28', 'gate_as_of', v_j.gate_as_of));
  return;
end;
$$;

-- 7d — venue.finalize_export (RPC §17.22; AUTHZ-CRM2(1)). EXEC DEF. running→ready
--   under a LIVE lease. The gate counters are NOT parameters — they are read from
--   the job row where build_export_rows accumulated them (evidence the caller
--   hands you is not evidence about the caller); p_row_count is cross-checked
--   against the DB-side count and raises count_mismatch, leaving the job
--   reclaimable. Writes crm_export.generate with as_of + gate_as_of + the four
--   counters + constraint_set_version (X-9, live read, NULL ⇒ refuse). The blank-
--   column canary (emitted=0 ∧ suppressed=row_count on a non-empty file) raises a
--   platform_risk signal (a crm_export.signal audit row — §1.12 open vocabulary).
--   The object path is deterministic ({org_id}/{job_id}.csv, §6.6) and asserted.
create or replace function venue.finalize_export(
  p_job_id uuid, p_row_count integer, p_byte_count integer, p_sha256 text, p_object_path text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_j venue.export_job%rowtype; v_csv text;
  v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  select * into v_j from venue.export_job where job_id = p_job_id for update;
  if not found then raise exception 'not_found: export job %', p_job_id using errcode = 'P0002'; end if;
  if v_j.state = 'ready' then
    return jsonb_build_object('status','noop_replay','job_id', p_job_id,'state','ready','expires_at', v_j.expires_at);
  end if;
  if v_j.state <> 'running' then
    raise exception 'precondition_failed: export job % is % — only a running build finalizes', p_job_id, v_j.state
      using errcode = 'P0001';
  end if;
  if v_j.lease_until is null or v_j.lease_until < now() then
    raise exception 'precondition_failed: lease_expired — the build must re-claim and rebuild from page 1' using errcode = 'P0001';
  end if;
  if p_row_count is null or p_row_count <> coalesce(v_j.row_count, -1) then
    raise exception 'count_mismatch: worker row_count % disagrees with the accumulated count % — job left reclaimable',
      p_row_count, v_j.row_count;
  end if;
  if v_j.contact_cells_emitted + v_j.contact_cells_suppressed <> v_j.row_count
     or v_j.name_cells_emitted + v_j.name_cells_suppressed <> v_j.row_count then
    raise exception 'count_mismatch: gate counters do not balance the row count — the gate did not run on every row';
  end if;
  if p_byte_count is null or p_byte_count < 0 or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_input: byte_count and a hex sha256 are required';
  end if;
  if p_object_path is distinct from (v_j.org_id::text || '/' || p_job_id::text || '.csv') then
    raise exception 'invalid_input: object_path must be {org_id}/{job_id}.csv (§6.6)';
  end if;
  select c.value #>> '{}' into v_csv from catalog.platform_config c
   where c.key = 'crm_export.constraint_set_version' order by c.version desc limit 1;
  if v_csv is null then
    raise exception 'precondition_failed: crm_export.constraint_set_version is unset (X-9)';
  end if;
  update venue.export_job
     set state = 'ready', ready_at = now(), expires_at = now() + interval '24 hours',   -- artifact retention §6.6
         artifact_state = 'present', byte_count = p_byte_count, artifact_sha256 = p_sha256,
         object_path = p_object_path, lease_until = null
   where job_id = p_job_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_sys, 'crm_export.generate', 'crm_export', p_job_id, 'generate',
          jsonb_build_object('scope_kind', v_j.scope_kind, 'scope_id', v_j.scope_id,
            'template_id', v_j.template_id, 'template_version', v_j.template_version, 'filters', v_j.filters,
            'as_of', v_j.as_of, 'gate_as_of', v_j.gate_as_of, 'row_count', v_j.row_count, 'byte_count', p_byte_count,
            'artifact_sha256', p_sha256,
            'contact_cells_emitted', v_j.contact_cells_emitted, 'contact_cells_suppressed', v_j.contact_cells_suppressed,
            'name_cells_emitted', v_j.name_cells_emitted, 'name_cells_suppressed', v_j.name_cells_suppressed,
            'constraint_set_version', v_csv));
  -- the blank-column canary: "zero rows" and "nobody consented" look alike in the file.
  if v_j.row_count > 0 and v_j.contact_cells_emitted = 0 and v_j.contact_cells_suppressed = v_j.row_count then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_sys, 'crm_export.signal', 'crm_export', p_job_id, 'blank_column_canary',
            jsonb_build_object('row_count', v_j.row_count, 'audience', 'platform_risk'));
  end if;
  return jsonb_build_object('status','ok','job_id', p_job_id,'state','ready',
                            'expires_at', (select expires_at from venue.export_job where job_id = p_job_id));
end;
$$;

-- 7e — venue.authorize_export_download (RPC §17.22; EX-4; AUTHZ-M13). Re-checks
--   the caller LIVE against the grant tables through the SAME predicate a fresh
--   request for (scope, template) would face — the template limb is the whole
--   H-12 fix (org_marketing must never download a colleague's operations file).
--   Raises on any state but `ready`. Rate-limited fail-closed (§7.1: 3 per actor
--   per job over the job's life; 10 per actor / 24 h). Writes crm_export.download
--   IN-TXN BEFORE returning the path (the honest over-report: the audit says a URL
--   was issued, not that bytes arrived). Returns {object_path, ttl_seconds: 300}
--   for the crm-export edge to sign; the DB never mints a URL.
--   NOTE (E-68): §12 24a asks for `raise 42501` AND a crm_export.denied row in one
--   call — impossible in one transaction (the raise rolls the row back). The
--   corpus's own answer to that shape is the R-28 client-recorded denial witness
--   (kernel.record_money_denial), whose action vocabulary is money-only and lives
--   in immutable 085. Denial here RAISES (fail closed); the CRM denial witness is
--   a recorded forward obligation, not a silently invented object.
create or replace function venue.authorize_export_download(p_job_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_j venue.export_job%rowtype;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  select * into v_j from venue.export_job where job_id = p_job_id;
  if not found then raise exception 'not_found: export job %', p_job_id using errcode = 'P0002'; end if;
  -- EX-4: live re-authorization over (scope, template) — raising mode.
  perform venue.assert_may_request(v_uid, v_j.scope_kind, v_j.scope_id, v_j.template_id);
  if v_j.state <> 'ready' then
    raise exception 'precondition_failed: export job % is % — only a ready export downloads', p_job_id, v_j.state
      using errcode = 'P0001';
  end if;
  if v_j.artifact_state <> 'present' or v_j.object_path is null then
    raise exception 'precondition_failed: artifact not present for job %', p_job_id using errcode = 'P0001';
  end if;
  if not public.check_rate_limit(v_uid, 'crm_export_download:' || p_job_id::text, 3, 172800) then
    raise exception 'rate_limited: crm_export_download per actor per job (3 / job lifetime)';
  end if;
  if not public.check_rate_limit(v_uid, 'crm_export_download', 10, 86400) then
    raise exception 'rate_limited: crm_export_download per actor (10 / 24h)';
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'crm_export.download', 'crm_export', p_job_id, 'download',
          jsonb_build_object('scope_kind', v_j.scope_kind, 'scope_id', v_j.scope_id,
                             'template_id', v_j.template_id, 'ttl_seconds', 300));
  return jsonb_build_object('status','ok','object_path', v_j.object_path, 'ttl_seconds', 300);
end;
$$;

-- 7f — venue.revoke_export (RPC §17.22 / CRM §6.2 "revoke"). Authority: the
--   requester · venue_manager / org owner-admin over the job's scope · platform_
--   admin (the ONE export-lifecycle write a platform role holds — revoking is not
--   extraction) · both marketing labels TEMPLATE-SCOPED (AUTHZ-M13 ◐) — the last
--   three arms are exactly assert_may_request in non-raising mode. ready→revoked
--   and artifact_state present→delete_pending IN THE SAME TRANSACTION, so no
--   further download is authorized from this instant. It deletes NO bytes — the
--   purge route does, within one cycle (the honest bound is min(300 s, time-to-
--   purge)). Idempotent. Audited.
create or replace function venue.revoke_export(p_job_id uuid, p_reason_code text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_j venue.export_job%rowtype;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_reason_code is null or p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
  end if;
  select * into v_j from venue.export_job where job_id = p_job_id for update;
  if not found then raise exception 'not_found: export job %', p_job_id using errcode = 'P0002'; end if;
  -- the requester and platform_admin revoke unconditionally; every other arm (venue_manager /
  -- org owner-admin over the scope, the marketing labels template-scoped) IS the one shared
  -- predicate in its RAISING mode — a denial raises 42501 here (T-RPC-CRM-06: no opt-out).
  if v_j.requested_by <> v_uid and not kernel.is_platform(array['platform_admin']) then
    perform venue.assert_may_request(v_uid, v_j.scope_kind, v_j.scope_id, v_j.template_id);
  end if;
  if v_j.state = 'revoked' then
    return jsonb_build_object('status','noop_replay','job_id', p_job_id,'state','revoked','artifact_state', v_j.artifact_state);
  end if;
  if v_j.state <> 'ready' then
    raise exception 'precondition_failed: export job % is % — only a ready export is revoked (§3.18 machine)', p_job_id, v_j.state
      using errcode = 'P0001';
  end if;
  update venue.export_job
     set state = 'revoked',
         artifact_state = case when artifact_state = 'present' then 'delete_pending' else artifact_state end
   where job_id = p_job_id
   returning * into v_j;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'crm_export.revoke', 'crm_export', p_job_id, p_reason_code,
          jsonb_build_object('scope_kind', v_j.scope_kind, 'scope_id', v_j.scope_id,
                             'template_id', v_j.template_id, 'artifact_state', v_j.artifact_state));
  return jsonb_build_object('status','ok','job_id', p_job_id,'state','revoked','artifact_state', v_j.artifact_state);
end;
$$;

-- 7g — venue.sweep_expired_exports (RPC §17.22; CRM §6.2 "expire / purge"). EXEC
--   DEF, pg_cron hourly. STATE-TRANSITION-ONLY — the PRODUCER of the purge queue,
--   never its consumer; it moves no bytes. (1) ready past expires_at → expired,
--   present → delete_pending; (2) {expired, revoked} whose artifact is CONFIRMED
--   deleted and whose purge_after has passed → purged. One audit row per
--   transition (EX-5). Bounded, SKIP LOCKED, re-entrant.
create or replace function venue.sweep_expired_exports()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_r record; v_expired integer := 0; v_purged integer := 0;
  v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  for v_r in select job_id, artifact_state from venue.export_job
              where state = 'ready' and expires_at < now()
              order by expires_at limit 500 for update skip locked loop
    update venue.export_job
       set state = 'expired',
           artifact_state = case when artifact_state = 'present' then 'delete_pending' else artifact_state end
     where job_id = v_r.job_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
    values (v_sys, 'crm_export.expire', 'crm_export', v_r.job_id, 'artifact_retention');
    v_expired := v_expired + 1;
  end loop;
  for v_r in select job_id from venue.export_job
              where ((state in ('expired','revoked') and artifact_state = 'deleted')
                     or (state = 'failed' and artifact_state in ('absent','deleted')))   -- E-78: a failed job never held bytes
                and purge_after < now()
              order by purge_after limit 500 for update skip locked loop
    update venue.export_job set state = 'purged' where job_id = v_r.job_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
    values (v_sys, 'crm_export.purge', 'crm_export', v_r.job_id, 'job_row_retention');
    v_purged := v_purged + 1;
  end loop;
  return jsonb_build_object('status','ok','expired', v_expired, 'purged', v_purged);
end;
$$;

-- 7h — venue.claim_artifacts_for_purge (RPC §17.22; schema §3.18.1; K-3). EXEC
--   DEF, service_role only (the crm-export-worker /purge route). Takes the 064
--   claim lease (purge_lease_until — DISTINCT from the build's lease_until) over a
--   bounded page of delete_pending rows through the (artifact_state, expires_at)
--   index, FOR UPDATE SKIP LOCKED, so two overlapping 15-minute runs claim
--   DISJOINT sets. Returns (job_id, object_path) and NOTHING else. A claim is an
--   attempt: purge_attempts increments here, and a row past three attempts raises
--   the platform_risk signal (a delete that never succeeds is an alarm).
create or replace function venue.claim_artifacts_for_purge(p_limit integer)
returns table (job_id uuid, object_path text)
language plpgsql security definer set search_path = ''
as $$
declare v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'invalid_input: p_limit must be between 1 and 500';
  end if;
  return query
    with c as (
      select j.job_id from venue.export_job j
       where j.artifact_state = 'delete_pending'
         and (j.purge_lease_until is null or j.purge_lease_until < now())
       order by j.expires_at nulls first, j.job_id
       limit p_limit
       for update skip locked
    ), u as (
      update venue.export_job j
         set purge_lease_until = now() + interval '10 minutes', purge_attempts = j.purge_attempts + 1
        from c where j.job_id = c.job_id
       returning j.job_id, j.object_path, j.purge_attempts
    ), s as (
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      select v_sys, 'crm_export.signal', 'crm_export', u.job_id, 'purge_stalled',
             jsonb_build_object('purge_attempts', u.purge_attempts, 'audience', 'platform_risk')
        from u where u.purge_attempts > 3
    )
    select u.job_id, u.object_path from u;
end;
$$;

-- 7i — venue.confirm_artifact_purged (RPC §17.22; schema §3.18.1). EXEC DEF,
--   service_role only. p_outcome ∈ {deleted, not_found} — BOTH are success (a 404
--   from Storage means the bytes are gone, which is the goal). artifact_state →
--   deleted (terminal; the only state that asserts the bytes are gone); advances
--   ready → expired (a ready job with no bytes cannot serve a download) and
--   {expired, revoked} → purged where purge_after allows. Writes crm_export.purge
--   in the same transaction. Idempotent: a second call is a no-op.
create or replace function venue.confirm_artifact_purged(p_job_id uuid, p_outcome text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_j venue.export_job%rowtype; v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  if p_outcome is null or p_outcome not in ('deleted','not_found') then
    raise exception 'invalid_input: outcome must be deleted or not_found';
  end if;
  select * into v_j from venue.export_job where job_id = p_job_id for update;
  if not found then raise exception 'not_found: export job %', p_job_id using errcode = 'P0002'; end if;
  if v_j.artifact_state = 'deleted' then
    return jsonb_build_object('status','noop_replay','job_id', p_job_id,'artifact_state','deleted','state', v_j.state);
  end if;
  update venue.export_job
     set artifact_state = 'deleted', purge_lease_until = null,
         state = case when state = 'ready' then 'expired'
                      when state in ('expired','revoked') and purge_after < now() then 'purged'
                      else state end
   where job_id = p_job_id
   returning * into v_j;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_sys, 'crm_export.purge', 'crm_export', p_job_id, p_outcome,
          jsonb_build_object('state', v_j.state, 'purge_attempts', v_j.purge_attempts));
  return jsonb_build_object('status','ok','job_id', p_job_id,'artifact_state','deleted','state', v_j.state);
end;
$$;

-- 7j — venue.reconcile_export_orphans (RPC §17.22; CRM §6.6; AUTHZ-M14). EXEC DEF,
--   service_role only, daily, BOTH directions. Given the object paths the purge
--   route listed under ONE {org_id}/ prefix: (→) returns the paths the route must
--   delete — no job row (`orphan_no_job`) or a job already claiming the artifact
--   is absent/deleted (`orphan_state_mismatch`) — each audited as crm_export.purge;
--   (←) every job of the org whose accounting says bytes exist but whose object is
--   NOT in the listing is set artifact_state='deleted' (audited), and if the job
--   was still `ready` it is moved to `expired` and a platform_risk signal is raised
--   (a ready job with no bytes fails at download). This pass is the only reason
--   the 24-hour bound is a statement about the BUCKET rather than the job table.
create or replace function venue.reconcile_export_orphans(p_org_id uuid, p_object_paths text[])
returns table (object_path text, reason_code text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_p text; v_jid uuid; v_j venue.export_job%rowtype; v_r record;
  v_prefix text; v_paths text[] := coalesce(p_object_paths, '{}');
  v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  if p_org_id is null then raise exception 'invalid_input: org_id required'; end if;
  v_prefix := p_org_id::text || '/';
  -- (→) objects present in the bucket with no honest job behind them.
  foreach v_p in array v_paths loop
    if v_p is null or left(v_p, length(v_prefix)) <> v_prefix then
      raise exception 'invalid_input: object path outside the % prefix', v_prefix;
    end if;
    v_jid := null;
    if v_p ~ ('^' || v_prefix || '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.csv$') then
      v_jid := substring(v_p from length(v_prefix) + 1 for 36)::uuid;
    end if;
    select * into v_j from venue.export_job j where j.job_id = v_jid and j.org_id = p_org_id;
    if v_jid is null or not found then
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'crm_export.purge', 'crm_export', coalesce(v_jid, '00000000-0000-0000-0000-000000000000'),
              'orphan_no_job', jsonb_build_object('org_id', p_org_id));
      object_path := v_p; reason_code := 'orphan_no_job'; return next;
    elsif v_j.artifact_state in ('absent','deleted') then
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'crm_export.purge', 'crm_export', v_jid, 'orphan_state_mismatch',
              jsonb_build_object('artifact_state', v_j.artifact_state, 'state', v_j.state));
      object_path := v_p; reason_code := 'orphan_state_mismatch'; return next;
    end if;
    -- present / delete_pending with a live job: the normal case (or the purge queue's) — left alone.
  end loop;
  -- (←) jobs whose accounting says bytes exist, with no object in the listing.
  for v_r in select j.job_id, j.state, j.object_path from venue.export_job j
              where j.org_id = p_org_id and j.artifact_state in ('present','delete_pending')
                and j.object_path is not null and not (j.object_path = any(v_paths))
              for update skip locked loop
    update venue.export_job
       set artifact_state = 'deleted', purge_lease_until = null,
           state = case when state = 'ready' then 'expired' else state end
     where venue.export_job.job_id = v_r.job_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_sys, 'crm_export.purge', 'crm_export', v_r.job_id, 'object_absent',
            jsonb_build_object('prior_state', v_r.state));
    if v_r.state = 'ready' then
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'crm_export.signal', 'crm_export', v_r.job_id, 'ready_without_object',
              jsonb_build_object('audience', 'platform_risk'));
    end if;
  end loop;
  return;
end;
$$;

-- 7k — venue.list_export_jobs (RPC §17.22; X10). Scope-checked, ROLE-scoped (not
--   template-scoped: seeing THAT an operations export happened is export-history
--   transparency; downloading it is not). Job METADATA ONLY — never a row, never
--   an object path, never a signed URL — plus template_id and `downloadable`,
--   computed with assert_may_request in NON-raising mode: the ONLY caller in the
--   corpus that passes p_raise := false (T-RPC-CRM-06), safe here because a false
--   renders a disabled control and never gates a byte. Cursor = requested_at.
create or replace function venue.list_export_jobs(p_scope_kind text, p_scope_id uuid, p_cursor text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_org uuid; v_venue uuid; v_event uuid; v_cursor timestamptz; v_cursor_id uuid; v_rows jsonb; v_next text;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_scope_kind is null or p_scope_kind not in ('session','event','venue','org') then
    raise exception 'invalid_input: scope_kind % is not a member of the closed set (EX-1)', coalesce(p_scope_kind,'<null>');
  end if;
  if p_scope_kind = 'session' then
    select e.org_id, e.venue_id, e.event_id into v_org, v_venue, v_event
      from catalog.event_session s join catalog.event e on e.event_id = s.event_id where s.session_id = p_scope_id;
  elsif p_scope_kind = 'event' then
    select e.org_id, e.venue_id, e.event_id into v_org, v_venue, v_event from catalog.event e where e.event_id = p_scope_id;
  elsif p_scope_kind = 'venue' then
    select v.org_id, v.venue_id into v_org, v_venue from catalog.venue v where v.venue_id = p_scope_id;
  else
    select o.org_id into v_org from kernel.organization o where o.org_id = p_scope_id;
  end if;
  -- an unresolvable scope fails IDENTICALLY to an unauthorized one (CRM §4.2(5): no existence oracle).
  if v_org is null
     or not (kernel.has_org_role(v_org, array['org_owner','org_admin','org_marketing'])
             or (v_venue is not null
                 and (select v.org_id from catalog.venue v where v.venue_id = v_venue) = v_org   -- E-76 operator binding
                 and kernel.has_venue_role(v_venue, array['venue_manager','venue_marketing']))
             or kernel.is_platform(array['platform_support','platform_risk','platform_admin'])) then
    raise exception 'insufficient_privilege: no export-history read at this scope (X10)' using errcode = '42501';
  end if;
  -- cursor = '<requested_at>|<job_id>' — a total order, so boundary ties never skip a row.
  v_cursor := case when p_cursor is null or p_cursor = '' then null else split_part(p_cursor, '|', 1)::timestamptz end;
  v_cursor_id := case when p_cursor is null or p_cursor = '' or split_part(p_cursor, '|', 2) = '' then null else split_part(p_cursor, '|', 2)::uuid end;
  with page as (
    select j.* from venue.export_job j
     where j.org_id = v_org
       and (   (p_scope_kind = 'org')
            or (p_scope_kind = 'venue' and (
                   (j.scope_kind = 'venue' and j.scope_id = p_scope_id)
                or (j.scope_kind = 'event' and j.scope_id in (select e.event_id from catalog.event e where e.venue_id = p_scope_id))
                or (j.scope_kind = 'session' and j.scope_id in (select s.session_id from catalog.event_session s
                                                                  join catalog.event e on e.event_id = s.event_id where e.venue_id = p_scope_id))))
            or (p_scope_kind = 'event' and (
                   (j.scope_kind = 'event' and j.scope_id = p_scope_id)
                or (j.scope_kind = 'session' and j.scope_id in (select s.session_id from catalog.event_session s where s.event_id = p_scope_id))))
            or (p_scope_kind = 'session' and j.scope_kind = 'session' and j.scope_id = p_scope_id))
       and (v_cursor is null or j.requested_at < v_cursor or (j.requested_at = v_cursor and v_cursor_id is not null and j.job_id < v_cursor_id))
     order by j.requested_at desc, j.job_id desc
     limit 50)
  select coalesce(jsonb_agg(jsonb_build_object(
           'job_id', p.job_id, 'scope_kind', p.scope_kind, 'scope_id', p.scope_id,
           'template_id', p.template_id, 'template_version', p.template_version,
           'state', p.state, 'artifact_state', p.artifact_state, 'failure_code', p.failure_code,
           'requested_by', p.requested_by, 'requested_at', p.requested_at, 'as_of', p.as_of,
           'ready_at', p.ready_at, 'expires_at', p.expires_at, 'row_count', p.row_count,
           'contact_cells_emitted', p.contact_cells_emitted, 'contact_cells_suppressed', p.contact_cells_suppressed,
           'name_cells_emitted', p.name_cells_emitted, 'name_cells_suppressed', p.name_cells_suppressed,
           'artifact_sha256', p.artifact_sha256,
           'downloadable', (p.state = 'ready' and p.artifact_state = 'present'
                            and venue.assert_may_request(v_uid, p.scope_kind, p.scope_id, p.template_id, false))
         ) order by p.requested_at desc, p.job_id desc), '[]'::jsonb),
         (select p2.requested_at::text || '|' || p2.job_id::text from page p2 order by p2.requested_at, p2.job_id limit 1)
    into v_rows, v_next from page p;
  return jsonb_build_object('status','ok','jobs', v_rows, 'next_cursor',
           case when jsonb_array_length(v_rows) = 50 then v_next else null end);
end;
$$;

-- 7l — venue.list_attendees (RPC §17.22 / CRM §11.4; dashboard Δ3; AUTHZ-M12).
--   The holder-grain roster read. Four authority branches — venue/org OPERATIONS
--   (venue_manager · org owner/admin: the union), venue/org MARKETING (contact, no
--   money), venue/org FINANCE (money-only projection), PLATFORM (support/risk/
--   admin; reason-coded, separately limited) — column-scoped by role with denied
--   classes ABSENT from the shape. XO-1a: the org is resolved ONCE here from the
--   session's event (org stamped at create) and would be the operand of the atom
--   filter, the customer_ref key and the consent gate together. Filters use the
--   same closed grammar. p_reason_code is REQUIRED on the platform arm only — a
--   closed enum + optional ticket ref, never free text.
--   PFA-28: every projection carries customer_ref (field 1, IDENT, "every role
--   that may read the roster"), so after authz + input validation this reader
--   FAILS CLOSED with ZERO mutation and NO rate budget consumed (the call reached
--   no data). Un-park is body-only; the frozen limits (§7.1: 240/h venue-org,
--   40/h + 200/24h + 20 distinct sessions platform), the per-page audit
--   (crm_lookup.attendee / crm_lookup.platform_roster) and the 50-row page are
--   documented here for it.
create or replace function venue.list_attendees(p_session_id uuid, p_filters jsonb, p_cursor text, p_reason_code text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_org uuid; v_venue uuid; v_event uuid; v_venue_bound boolean;
  v_ops boolean; v_mkt boolean; v_fin boolean; v_plat boolean; v_k text; v_v jsonb;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  select e.org_id, e.venue_id, e.event_id into v_org, v_venue, v_event
    from catalog.event_session s join catalog.event e on e.event_id = s.event_id where s.session_id = p_session_id;
  -- E-76: a venue role reaches this session only while the venue's CURRENT operator is the event's org.
  v_venue_bound := v_venue is not null and (select v.org_id from catalog.venue v where v.venue_id = v_venue) = v_org;
  v_ops  := (v_venue_bound and kernel.has_venue_role(v_venue, array['venue_manager'])) or kernel.has_org_role(v_org, array['org_owner','org_admin']);
  v_mkt  := (v_venue_bound and kernel.has_venue_role(v_venue, array['venue_marketing'])) or kernel.has_org_role(v_org, array['org_marketing']);
  v_fin  := (v_venue_bound and kernel.has_venue_role(v_venue, array['venue_finance'])) or kernel.has_org_role(v_org, array['org_finance']);
  v_plat := kernel.is_platform(array['platform_support','platform_risk','platform_admin']);
  -- an unknown session fails IDENTICALLY to an unauthorized one (no existence oracle, CRM §4.2(5)).
  if v_org is null or not (v_ops or v_mkt or v_fin or v_plat) then
    raise exception 'insufficient_privilege: no roster read at this session' using errcode = '42501';
  end if;
  -- AUTHZ-M12: the platform arm (and ONLY it) must carry a closed-enum reason code.
  if not (v_ops or v_mkt or v_fin) then
    if p_reason_code is null
       or p_reason_code !~ '^(support_ticket|risk_investigation|incident|data_subject_request)(:[A-Za-z0-9._-]{1,64})?$' then
      raise exception 'invalid_input: reason_code is required on the platform arm — support_ticket | risk_investigation | incident | data_subject_request, plus an optional ticket reference';
    end if;
  end if;
  -- filters: the closed conjunctive grammar (CRM §6.5) — session-anchored, so no
  -- date_window; the promoter member is gated on 090.
  for v_k, v_v in select key, value from jsonb_each(coalesce(p_filters, '{}'::jsonb)) loop
    if v_k not in ('ticket_type','order_status','check_in_status','source','promoter','refund_state','acquired_via','email_present') then
      raise exception 'invalid_input: filter % is not a member of the closed grammar (X-2/EX-3)', v_k;
    end if;
    if v_k = 'promoter' then raise exception 'precondition_failed: the promoter filter is gated on package 090'; end if;
    if v_k = 'email_present' then
      if v_v not in ('true'::jsonb, 'false'::jsonb) then raise exception 'invalid_input: email_present must be true or false'; end if;
    elsif jsonb_typeof(v_v) <> 'array' or jsonb_array_length(v_v) = 0
          or exists (select 1 from jsonb_array_elements(v_v) x where jsonb_typeof(x) <> 'string') then
      raise exception 'invalid_input: filter % must be a non-empty membership array of values (no nesting)', v_k;
    end if;
  end loop;
  -- ── PFA-28 FAIL-CLOSED PARK (zero mutation, no rate budget consumed) ────────
  raise exception 'precondition_failed: customer_ref_crypto_unavailable — the roster projection carries customer_ref (CRM §4.3 HMAC-SHA256) and no ratified in-DB mechanism exists (PFA-28); reader parked fail-closed, no customer data emitted'
    using errcode = 'P0001';
end;
$$;

-- 7m — venue.lookup_attendee (RPC §17.22 / CRM §7.2/§7.2a). ONE record, service
--   context. p_query_kind ∈ {email_exact, order_ref, name_prefix}. Authority:
--   venue_manager · venue_box_office · org owner/admin over the venue ·
--   platform_support — DENIED to both marketing labels. name_prefix < 3 chars is
--   `prefix_too_short`, raised BEFORE the lookup and without consuming budget.
--   Frozen for the un-park: per-actor AND per-org limits for EVERY kind (§7.1:
--   email 40/120, name_prefix 20/60, order_ref 200/600 per 24 h — a kind with no
--   limit RAISES), multi-match ⇒ `ambiguous_query` with NO rows and NO count,
--   audit crm_lookup.attendee with (kind, outcome) and NEVER the value.
--   PFA-28: the minimal service projection carries customer_ref, so after authz
--   + input validation this reader FAILS CLOSED with zero mutation.
create or replace function venue.lookup_attendee(p_session_id uuid, p_query_kind text, p_query_value text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_org uuid; v_venue uuid;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  select e.org_id, e.venue_id into v_org, v_venue
    from catalog.event_session s join catalog.event e on e.event_id = s.event_id where s.session_id = p_session_id;
  -- unknown session ⇒ identical refusal (no oracle); venue arm bound to the current operator (E-76).
  if v_org is null
     or not ((v_venue is not null and (select v.org_id from catalog.venue v where v.venue_id = v_venue) = v_org
              and kernel.has_venue_role(v_venue, array['venue_manager','venue_box_office']))
             or kernel.has_org_role(v_org, array['org_owner','org_admin'])
             or kernel.is_platform(array['platform_support'])) then
    raise exception 'insufficient_privilege: no attendee lookup at this session (marketing labels are denied)' using errcode = '42501';
  end if;
  if p_query_kind is null or p_query_kind not in ('email_exact','order_ref','name_prefix') then
    raise exception 'invalid_input: query_kind must be email_exact | order_ref | name_prefix';
  end if;
  if p_query_kind = 'name_prefix' and length(trim(coalesce(p_query_value,''))) < 3 then
    raise exception 'prefix_too_short: name_prefix needs at least 3 characters';   -- before any data, no budget consumed
  end if;
  -- ── PFA-28 FAIL-CLOSED PARK (zero mutation) ─────────────────────────────────
  raise exception 'precondition_failed: customer_ref_crypto_unavailable — the lookup projection carries customer_ref (CRM §4.3 HMAC-SHA256) and no ratified in-DB mechanism exists (PFA-28); reader parked fail-closed, no customer data emitted'
    using errcode = 'P0001';
end;
$$;

-- ============================================================================
-- PART 8 — grants (076 discipline: revoke default PUBLIC EXECUTE on every new
--   function; targeted grants only). on_payout_settled keeps its 085 ACL (CREATE
--   OR REPLACE preserves it). The two settlement seams are definer-internal.
-- ============================================================================
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'kernel.settlement_royalty_lines(uuid)',
    'kernel.settlement_commission_lines(uuid)',
    'venue.open_settlement(uuid, uuid, uuid, jsonb, text)',
    'kernel.close_settlement(uuid, text)',
    'kernel.request_org_payout(uuid, uuid, text)',
    'venue.assert_may_request(uuid, text, uuid, text, boolean)',
    'venue.request_export(text, uuid, text, jsonb, text)',
    'venue.build_export_rows(uuid, text, integer)',
    'venue.finalize_export(uuid, integer, integer, text, text)',
    'venue.authorize_export_download(uuid)',
    'venue.revoke_export(uuid, text)',
    'venue.sweep_expired_exports()',
    'venue.claim_artifacts_for_purge(integer)',
    'venue.confirm_artifact_purged(uuid, text)',
    'venue.reconcile_export_orphans(uuid, text[])',
    'venue.list_export_jobs(text, uuid, text)',
    'venue.list_attendees(uuid, jsonb, text, text)',
    'venue.lookup_attendee(uuid, text, text)'
  ];
  -- caller-authorized (in-body has_org_role/has_venue_role/is_platform).
  v_auth constant text[] := array[
    'venue.open_settlement(uuid, uuid, uuid, jsonb, text)',
    'kernel.close_settlement(uuid, text)',
    'kernel.request_org_payout(uuid, uuid, text)',
    'venue.request_export(text, uuid, text, jsonb, text)',
    'venue.authorize_export_download(uuid)',
    'venue.revoke_export(uuid, text)',
    'venue.list_export_jobs(text, uuid, text)',
    'venue.list_attendees(uuid, jsonb, text, text)',
    'venue.lookup_attendee(uuid, text, text)'
  ];
  -- EXEC DEF (§0.1a): service_role only — the crm-export-worker routes, the cron
  -- sweep (edge-triggerable), and assert_may_request (OR-10: true definer-only;
  -- its three callers reach it as owner).
  v_svc constant text[] := array[
    'venue.assert_may_request(uuid, text, uuid, text, boolean)',
    'venue.build_export_rows(uuid, text, integer)',
    'venue.finalize_export(uuid, integer, integer, text, text)',
    'venue.sweep_expired_exports()',
    'venue.claim_artifacts_for_purge(integer)',
    'venue.confirm_artifact_purged(uuid, text)',
    'venue.reconcile_export_orphans(uuid, text[])'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
  end loop;
  foreach v_fn in array v_auth loop
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
  foreach v_fn in array v_svc loop
    execute format('grant execute on function %s to service_role', v_fn);
  end loop;
end $$;

-- ============================================================================
-- PART 9 — cron (plan §8/087; CRON_SCHEDULE_REGISTER rows 087 ×3). The sweep is a
--   pure-DB tick. The build and purge ticks are the 014/032 pg_cron + pg_net
--   pattern, targeting the crm-export-worker deployment (EDGE-2) and sending the
--   dedicated X-Crm-Export-Worker second factor (EDGE-3: never the service-role
--   key). Both secrets are read from Vault at fire time; an absent worker secret
--   sends an empty header and the worker refuses (403) — fail closed. The project
--   URL is public and inlined exactly as 032 does.
-- ============================================================================
select cron.schedule('sweep-expired-exports', '7 * * * *', $$select venue.sweep_expired_exports();$$);
select cron.schedule('crm-export-build-tick', '* * * * *', $cron$
  select net.http_post(
    url     := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/crm-export-worker/build',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                               where name = 'service_role_key' order by created_at desc limit 1), ''),
      'X-Crm-Export-Worker', coalesce((select decrypted_secret from vault.decrypted_secrets
                                        where name = 'crm_export_worker_secret' order by created_at desc limit 1), ''),
      'Content-Type', 'application/json'),
    body    := '{}'::jsonb)
   where exists (select 1 from vault.decrypted_secrets where name = 'crm_export_worker_secret');   -- no secret ⇒ no post (fail closed, E-79)
$cron$);
select cron.schedule('crm-export-purge-tick', '*/15 * * * *', $cron$
  select net.http_post(
    url     := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/crm-export-worker/purge',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                               where name = 'service_role_key' order by created_at desc limit 1), ''),
      'X-Crm-Export-Worker', coalesce((select decrypted_secret from vault.decrypted_secrets
                                        where name = 'crm_export_worker_secret' order by created_at desc limit 1), ''),
      'Content-Type', 'application/json'),
    body    := '{}'::jsonb)
   where exists (select 1 from vault.decrypted_secrets where name = 'crm_export_worker_secret');   -- no secret ⇒ no post (fail closed, E-79)
$cron$);

commit;
