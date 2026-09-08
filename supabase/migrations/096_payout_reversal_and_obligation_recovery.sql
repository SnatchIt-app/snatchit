-- ============================================================================
-- 096_payout_reversal_and_obligation_recovery.sql — the money that came BACK.
--
-- WHAT THIS MIGRATION IS. Three closures on the post-payout half of the ledger
-- that 085/087/093/094/095 left open, every one of them ADDITIVE: two new
-- append-only fact tables on the money layer, one missing uniqueness invariant,
-- seven new verbs/reads, and two body-only re-creations. No status CHECK is
-- widened, no grant on a frozen object is broadened, no 085/093/095 verb body
-- is replaced, nothing here activates a rail. Design of record:
-- docs/phase2/_impl/KE_payout_reversal.md (§4.1 model A, §4.2, §4.3, §4.4) and
-- docs/phase2/_impl/KD_obligation_recovery.md (§4.1 model A, §4.2), as fixed by
-- the orchestrator's DESIGN_096 memo §1. Where this file and a report disagree,
-- the memo won and the implementation note (docs/phase2/_impl/KM1_096_
-- implementation.md) says so.
--
-- THE THREE DEFECTS, EACH PROVED BY EXECUTION BEFORE IT WAS CLOSED.
--
--   1. A REVERSAL HAS NOWHERE TO LIVE (KE F-2/F-3/F-12). kernel.payout has ONE
--      amount column and it is the minted obligation (095:209-214). A full
--      reversal after 'paid' moves status to 'reversed' through the one legal
--      terminal edge (085:1699-1703) and records nothing else: no amount, no
--      trr_, no link to the debt it may have recovered. A PARTIAL reversal
--      cannot be stored at all — 095 E-4 refuses a paid row by design
--      (095:718-724) — so the only "representations" available were mutating
--      the obligation column or mis-labelling the reversal as a settlement fee
--      and double-booking a receivable (KE §2.5). And the webhook that could
--      have observed any of this completes the event and never replays it
--      (KE F-1). Closed by R-1/R-3: kernel.payout_reversal, one row per Stripe
--      transfer_reversal object, trr_ UNIQUE as the at-least-once key, Σ-capped
--      at the payout's own amount by a trigger, and a service_role writer that
--      moves status ONLY through kernel.mark_payout_transfer_state when Σ
--      reaches the amount. No second door onto status.
--
--   2. A DEBT CAN ONLY BE ALL-OR-NOTHING (KD P1-1/P1-4). kernel.resolve_
--      organization_obligation takes no amount; 2 000 of a 6 000 debt is
--      unstorable; a receipt after write-off has nowhere to live; a reversal on
--      the wrong org's payout is undetectable because nothing names an
--      obligation; and the verb itself was unreachable by ANY real principal —
--      service_role-only grant with an auth.uid()-based authority test (KD §2.2,
--      executed: service client 42501, forwarded platform JWT 42501). Closed by
--      R-4/R-5/R-6: kernel.organization_obligation_recovery, one row per
--      receipt, Σ-capped at the debt, org-checked against the reversal it cites,
--      refused after write-off; status becomes 'recovered' as a CONSEQUENCE of
--      Σ = amount (an AFTER trigger), never as an act; the resolve verb is
--      granted to `authenticated` like its identity twin and refuses
--      'recovered' without facts.
--
--   3. THE REF-BEARING FAILED PAYOUT IS FULLY STRANDED (KE F-5, 095:254-261).
--      Twelve verbs, twelve refusals, and the executor cannot even claim it
--      (093 slice 10p requires 'submitted'), so the one place that holds the
--      Stripe-observed facts never looks. Closed by R-7: a service_role claim
--      over exactly that population and a reconcile verb that writes the ONE
--      new legal edge failed→paid from Stripe-observed facts only, with the
--      amount/currency/destination/group equalities mandatory and the caller's
--      numbers compared, never stored. kernel.mark_payout_transfer_state and
--      kernel.rearm_failed_payout are NOT modified; the status CHECK is NOT
--      widened; this verb is the sole writer of that edge.
--
-- WHAT IT IS NOT. It does not decide whether a reversal that is not a recovery
-- re-owes the venue (KE Q1 — owner item); it does not consume recoveries into
-- 095 E-6's exposure guard (a payout-operand decision, recorded not made); it
-- adds no 'offset_settlement' or 'writeoff' source (no producer — 094:198-200's
-- own rule); it does not touch kernel.request_org_payout (KE F-10 recorded),
-- kernel.hold_payout_transfer_reversed, kernel.settlement_royalty_lines,
-- kernel.close_settlement, kernel.record_organization_obligation or
-- kernel.get_payout_execution_context (those seams belong to 097). venue.
-- settlement stays 'paid' after a reversal: 095 E-5 makes the header
-- forward-only and the economic consequence lives on the obligation side.
-- NOTHING HERE PAYS A COMMISSION PAYEE: no verb body below names one, and the
-- pgTAP suite greps the bodies the way 160/F5 does.
--
-- ── M1 CLAIM BLOCK (096 — implementer M1's sections) ──────────────────────
--   R-1  kernel.payout_reversal                     + kernel.payout_reversal_guard()
--        kernel.payout_reversed_minor(uuid)
--   R-2  payout_stripe_transfer_ref_uq              (unique partial index, KE F-6)
--   R-3  kernel.record_payout_reversal(uuid, text, text, integer, jsonb, text)
--   R-4  kernel.organization_obligation_recovery    + kernel.organization_obligation_recovery_guard()
--                                                   + kernel.organization_obligation_recovery_settle()
--        kernel.obligation_outstanding_minor(uuid)
--        kernel.org_outstanding_obligation_minor(uuid)   ← 094 J7-3b RE-CREATED, body only
--   R-5  kernel.record_obligation_recovery(uuid, integer, text, text, text, text)
--   R-6  kernel.resolve_organization_obligation(uuid, text, text, text)  ← 094 J7-3 RE-CREATED
--        + GRANT to authenticated (KD P1-1), REVOKE from service_role
--   R-7  kernel.claim_failed_payouts_for_reconcile(integer, integer)
--        kernel.reconcile_payout_transfer(uuid, text, jsonb, text)
--   R-8  grants
--   Nothing else in the chain is modified. Replay-safe throughout (create table
--   if not exists / drop trigger if exists / create or replace / create index if
--   not exists). One transaction.
--
-- Sources read, not assumed: 085 PART 3 (kernel.payout) and PART 11
--   (mark_payout_transfer_state, 085:1668-1735) · 087:360 (venue.on_payout_
--   settled) · 093 slices 10n/10p · 094 J7-1..J7-5 · 095 E-2/E-4/E-5/E-6 ·
--   077:236-263 (kernel.admin_audit) · 077:468 (kernel.is_platform) ·
--   supabase/functions/payout-execute/executor.ts (transfer_group + metadata).
-- ============================================================================
begin;

set local lock_timeout = '3s';

-- ============================================================================
-- R-1 — kernel.payout_reversal: ONE ROW PER STRIPE transfer_reversal OBJECT.
--
--   THE SHAPE, AND WHY EACH COLUMN IS THERE.
--     stripe_transfer_ref   the tr_ the reversal belongs to. Carried on the fact
--                           (not only on the payout) because in the KE §4.3 race
--                           the payout's own ref is still NULL when the
--                           transfer.reversed webhook arrives; the trigger
--                           refuses only a DIFFERENT stored ref.
--     stripe_reversal_ref   the trr_. UNIQUE — THE at-least-once key. Stripe
--                           retries transfer.reversed; 069 retries locally on
--                           top; the second delivery must land on this
--                           constraint and be answered noop_replay, exactly the
--                           mechanism 094:26-40 gives for the obligation.
--     amount_minor          POSITIVE MAGNITUDE. Direction is the object's
--                           identity (a reversal is money coming BACK); no sign.
--     source                which observer wrote it. Evidence for the audit
--                           trail, never a predicate.
--     observed              the Stripe object as seen, verbatim. EVIDENCE ONLY.
--                           Nothing reads it to decide anything — full-versus-
--                           partial is decided against the payout's own
--                           amount_minor, as 095 E-4 decides it.
--     command_key           the caller's idempotency handle, for the audit.
--
--   WHAT THE TRIGGER GUARANTEES, against every writer including the owner:
--     · append-only (UPDATE/DELETE raise);
--     · the payout is an ORGANIZATION SETTLEMENT payout (the only cause this
--       rail reverses — a commission or identity payout has no transfer here);
--     · the fact's tr_ equals the payout's stored tr_ when one is stored;
--     · the payout is in a state a transfer can exist for: 'paid', 'reversed',
--       or 'submitted' — the last ONLY for the ref-not-yet-stored race (KE
--       §4.3), where the executor's callback has not written the ref yet.
--       'pending' (never executed) and 'failed' (the reconcile pass owns it,
--       R-7) are refused;
--     · currency equals the payout's;
--     · Σ(amount_minor) over the payout never exceeds the payout's amount_minor.
--       A reversal can return at most what was sent.
--   The payout row is locked FOR UPDATE inside the trigger so two facts for
--   the same payout serialise on the Σ check.
--
--   WHAT STATUS DOES. NOTHING HERE. status moves to 'reversed' only in R-3,
--   only when Σ = amount_minor, and only through kernel.mark_payout_transfer_
--   state — the edge 085 already has. While Σ < amount_minor the row stays
--   'paid' and "how much is still with the venue" is the derived read
--   amount_minor − kernel.payout_reversed_minor(payout_id). Never a column.
-- ============================================================================
create table if not exists kernel.payout_reversal (
  reversal_id          uuid primary key default gen_random_uuid(),
  payout_id            uuid not null references kernel.payout(payout_id) on delete restrict,
  stripe_transfer_ref  text not null check (stripe_transfer_ref ~ '^tr_[A-Za-z0-9]+$'),
  stripe_reversal_ref  text not null check (stripe_reversal_ref ~ '^trr_[A-Za-z0-9]+$'),
  amount_minor         integer not null check (amount_minor > 0),
  currency             text not null default 'USD',
  source               text not null check (source in ('stripe_webhook','reconcile','executor')),
  observed             jsonb not null default '{}'::jsonb,
  command_key          text not null,
  created_at           timestamptz not null default now(),
  constraint payout_reversal_stripe_ref_uq unique (stripe_reversal_ref)
);
create index if not exists payout_reversal_payout_idx
  on kernel.payout_reversal (payout_id);

comment on table kernel.payout_reversal is
  'One row per Stripe transfer_reversal (trr_) observed against an organization settlement payout. Append-only; trr_ UNIQUE is the at-least-once key; a trigger caps the running sum at the payout''s amount_minor. Records the fact — it moves no status itself (R-3 does, through kernel.mark_payout_transfer_state) and names no obligation (linking is a human act, R-5).';

create or replace function kernel.payout_reversal_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_po   kernel.payout%rowtype;
  v_sum  bigint;
begin
  if tg_op in ('UPDATE','DELETE') then
    raise exception 'append_only: kernel.payout_reversal rows are never updated or deleted — a reversal observed is a reversal observed' using errcode = 'P0001';
  end if;

  select * into v_po from kernel.payout where payout_id = new.payout_id for update;
  if not found then
    raise exception 'not_found: payout %', new.payout_id using errcode = 'P0002';
  end if;
  if v_po.cause <> 'settlement' or v_po.payee_kind <> 'organization' then
    raise exception 'precondition_failed: not an organization settlement payout — cause=% payee_kind=%', v_po.cause, v_po.payee_kind
      using errcode = 'P0001';
  end if;
  if v_po.stripe_transfer_ref is not null and v_po.stripe_transfer_ref <> new.stripe_transfer_ref then
    raise exception 'conflict_locked: transfer_ref_mismatch — payout % carries %, the reversal names %', new.payout_id, v_po.stripe_transfer_ref, new.stripe_transfer_ref
      using errcode = 'P0001';
  end if;
  if v_po.status not in ('paid','reversed','submitted') then
    raise exception 'precondition_failed: payout_state_not_reversible — payout % is % (a transfer can exist only for paid, reversed, or the submitted ref-not-yet-stored race)', new.payout_id, v_po.status
      using errcode = 'P0001';
  end if;
  if upper(coalesce(new.currency,'')) <> upper(coalesce(v_po.currency,'')) then
    raise exception 'precondition_failed: currency_mismatch — reversal % vs payout %', new.currency, v_po.currency
      using errcode = 'P0001';
  end if;
  select coalesce(sum(r.amount_minor), 0)::bigint into v_sum
    from kernel.payout_reversal r where r.payout_id = new.payout_id;
  if v_sum + new.amount_minor > v_po.amount_minor then
    raise exception 'precondition_failed: reversal_exceeds_transfer — % already reversed + % would exceed the payout''s %', v_sum, new.amount_minor, v_po.amount_minor
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

comment on function kernel.payout_reversal_guard() is
  'BEFORE INSERT/UPDATE/DELETE on kernel.payout_reversal: append-only; the payout must be an organization settlement payout in paid|reversed|submitted whose stored tr_ (if any) equals the fact''s; currency must match; the running sum can never exceed the payout''s amount_minor.';

revoke all on function kernel.payout_reversal_guard() from public, anon, authenticated;

drop trigger if exists tg_payout_reversal_guard on kernel.payout_reversal;
create trigger tg_payout_reversal_guard
  before insert or update or delete on kernel.payout_reversal
  for each row execute function kernel.payout_reversal_guard();

-- RLS §7.11 money-custody-RPC-only, DENY-ALL — the 094 J7-1 posture verbatim.
alter table kernel.payout_reversal enable row level security;
revoke all on kernel.payout_reversal from public, anon, authenticated, service_role;
revoke delete on kernel.payout_reversal from service_role;

-- The projection. "How much of payout X came back" — a READ, computed in
-- bigint by the aggregate discipline (087:29, 093:645).
create or replace function kernel.payout_reversed_minor(p_payout_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(r.amount_minor), 0)::bigint
    from kernel.payout_reversal r
   where r.payout_id = p_payout_id;
$$;

comment on function kernel.payout_reversed_minor(uuid) is
  'Σ kernel.payout_reversal.amount_minor for one payout. The venue still holds amount_minor minus this; no column stores it.';


-- ============================================================================
-- R-2 — ONE STRIPE TRANSFER, ONE PAYOUT (KE F-6).
--
--   Executed on a fresh replay: kernel.mark_payout_transfer_state(p4,'paid',
--   'tr_KE1') succeeded while tr_KE1 was already the ref of p1 — two
--   settlements discharged off one Stripe transfer, and any lookup "which
--   payout does transfer.reversed tr_KE1 belong to" ambiguous. The column
--   is contracted write-once (085:133) but nothing made it unique. A partial
--   unique index is the smallest honest closure: it is safe on an empty rail
--   (the native payout rail is DARK — no production row carries a ref), it
--   binds every writer including a future one, and it does not touch 085's
--   verb. A BEFORE UPDATE trigger on kernel.payout is deliberately NOT added:
--   085/095 own that surface.
-- ============================================================================
create unique index if not exists payout_stripe_transfer_ref_uq
  on kernel.payout (stripe_transfer_ref) where stripe_transfer_ref is not null;


-- ============================================================================
-- R-3 — kernel.record_payout_reversal: THE ONE WRITER OF THE REVERSAL FACT.
--
--   Called by the stripe-webhook (transfer.reversed, per reversals[] entry) and
--   by R-7's reconcile pass. service_role only: it records a MACHINE
--   observation of a Stripe fact; it authorizes nothing and it can only ever
--   make the ledger say LESS money is with the venue.
--
--   FIRST FAILING PREDICATE WINS; every WRITING branch is audited
--   ('payout.reversal_record', before/after). A noop_replay is NOT audited —
--   the producer is an at-least-once webhook and the audit table is not the
--   place to count its retries.
--
--     shapes            tr_ / trr_ regexes, amount > 0, command_key
--                       ^[A-Za-z0-9._:-]{1,64}$, source ∈ the CHECK set.
--     payout not found  P0002.
--     wrong cause/payee precondition_failed.
--     REPLAY FIRST      a fact with this trr_ already exists ⇒ noop_replay —
--                       unless it belongs to ANOTHER payout ⇒ conflict_locked:
--                       reversal_ref_bound_elsewhere (never re-attach a trr_).
--     'failed'          precondition_failed: payout_failed_reconcile_required.
--                       The reconcile pass (R-7) owns failed rows; the edge
--                       ACKs and alerts. Writing a fact here would race the
--                       failed→paid edge.
--     'pending'         if 095 E-4 already holds it (transfer_reversed /
--                       transfer_partially_reversed) ⇒ noop_replay; else
--                       precondition_failed: payout_not_executed.
--     'submitted'       THE RACE (KE §4.3): the transfer exists, its ref is not
--                       stored yet. The fact is written (the trigger permits
--                       'submitted'), then 095 E-4 de-authorizes the row to
--                       pending + held with the amounts in ITS audit. Returns
--                       'held'. The stored ref is still NOT written (085:133).
--     'paid'/'reversed' the fact is written; if status='paid' and Σ =
--                       amount_minor the row moves to 'reversed' THROUGH
--                       kernel.mark_payout_transfer_state(...,'reversed',
--                       stored ref, null, key) — the existing edge, same-ref
--                       equality, no held row possible on a terminal. If the
--                       row was already 'reversed' (the 085 edge was used
--                       directly, before facts existed) a late fact is still
--                       recorded and the audit says 'reversal_after_terminal'.
--
--   IT NEVER writes stripe_transfer_ref, never touches amount_minor, never
--   names an obligation (linking is R-5, a human act), never rewinds
--   venue.settlement (095 E-5 forbids it; the header records that the
--   instruction was executed). The caller's p_observed is stored as evidence
--   and read for exactly two optional hints: 'source' and, on the race path,
--   'transfer_amount_minor' for E-4's evidence column.
-- ============================================================================
create or replace function kernel.record_payout_reversal(
  p_payout_id uuid, p_stripe_transfer_ref text, p_stripe_reversal_ref text,
  p_amount_minor integer, p_observed jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_po        kernel.payout%rowtype;
  v_existing  kernel.payout_reversal%rowtype;
  v_obs       jsonb := coalesce(p_observed, '{}'::jsonb);
  v_source    text;
  v_sum       bigint;
  v_id        uuid;
  v_hold      jsonb;
  v_status    text;
  v_reason    text;
  v_sys       constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  if p_stripe_transfer_ref is null or p_stripe_transfer_ref !~ '^tr_[A-Za-z0-9]+$' then
    raise exception 'invalid_input: a Stripe transfer ref (tr_…) is mandatory' using errcode = 'P0001';
  end if;
  if p_stripe_reversal_ref is null or p_stripe_reversal_ref !~ '^trr_[A-Za-z0-9]+$' then
    raise exception 'invalid_input: a Stripe transfer_reversal ref (trr_…) is mandatory' using errcode = 'P0001';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_input: amount_minor must be positive — this verb records a reversal' using errcode = 'P0001';
  end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must match ^[A-Za-z0-9._:-]{1,64}$' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_obs) <> 'object' then
    raise exception 'invalid_input: observed must be a JSON object' using errcode = 'P0001';
  end if;
  v_source := coalesce(v_obs ->> 'source', 'stripe_webhook');
  if v_source not in ('stripe_webhook','reconcile','executor') then
    raise exception 'invalid_input: observed.source must be stripe_webhook|reconcile|executor' using errcode = 'P0001';
  end if;

  select * into v_po from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  if v_po.cause <> 'settlement' or v_po.payee_kind <> 'organization' then
    raise exception 'precondition_failed: not an organization settlement payout' using errcode = 'P0001';
  end if;

  -- REPLAY FIRST, BEFORE THE STATE GATE: the trr_ is the at-least-once key.
  select * into v_existing from kernel.payout_reversal where stripe_reversal_ref = p_stripe_reversal_ref;
  if found then
    if v_existing.payout_id <> p_payout_id then
      raise exception 'conflict_locked: reversal_ref_bound_elsewhere — % is already recorded against payout %', p_stripe_reversal_ref, v_existing.payout_id
        using errcode = 'P0001';
    end if;
    v_sum := kernel.payout_reversed_minor(p_payout_id);
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id,
                              'reversal_id', v_existing.reversal_id,
                              'payout_status', v_po.status,
                              'total_reversed_minor', v_sum,
                              'fully_reversed', v_sum >= v_po.amount_minor,
                              'obligation_linked', false);
  end if;

  if v_po.status = 'failed' then
    raise exception 'precondition_failed: payout_failed_reconcile_required — payout % is failed and carries %; the reconcile pass (kernel.reconcile_payout_transfer) owns it', p_payout_id, coalesce(v_po.stripe_transfer_ref,'<no ref>')
      using errcode = 'P0001';
  end if;
  if v_po.status = 'pending' then
    if v_po.hold_state <> 'none'
       and v_po.hold_reason_code in ('transfer_reversed','transfer_partially_reversed') then
      return jsonb_build_object('status','noop_replay','payout_id', p_payout_id,
                                'payout_status', v_po.status,
                                'hold_reason_code', v_po.hold_reason_code,
                                'total_reversed_minor', kernel.payout_reversed_minor(p_payout_id),
                                'fully_reversed', false,
                                'obligation_linked', false);
    end if;
    raise exception 'precondition_failed: payout_not_executed — payout % is pending; no transfer can have been reversed', p_payout_id
      using errcode = 'P0001';
  end if;

  -- The fact. The trigger re-checks cause, ref equality, state, currency, Σ.
  insert into kernel.payout_reversal
         (payout_id, stripe_transfer_ref, stripe_reversal_ref, amount_minor, currency, source, observed, command_key)
  values (p_payout_id, p_stripe_transfer_ref, p_stripe_reversal_ref, p_amount_minor, v_po.currency, v_source, v_obs, p_command_key)
  returning reversal_id into v_id;
  v_sum := kernel.payout_reversed_minor(p_payout_id);

  if v_po.status = 'submitted' then
    -- THE RACE. 095 E-4 de-authorizes; this verb records. E-4's own replay
    -- rule answers a second look with noop_replay, and a human hold already on
    -- the row is left in place (E-4 returns its reason).
    v_hold := kernel.hold_payout_transfer_reversed(
                p_payout_id, p_stripe_transfer_ref,
                coalesce(nullif(v_obs ->> 'transfer_amount_minor','')::integer, v_po.amount_minor),
                v_sum::integer, v_obs, p_command_key);
    v_status := 'pending';
    v_reason := 'held';
  elsif v_po.status = 'paid' and v_sum >= v_po.amount_minor then
    -- THE EXISTING EDGE, and only it. Same-ref equality holds by the trigger;
    -- a terminal row cannot be held, so payout_held cannot fire.
    perform kernel.mark_payout_transfer_state(p_payout_id, 'reversed', v_po.stripe_transfer_ref, null, p_command_key);
    v_status := 'reversed';
    v_reason := 'reversed';
  elsif v_po.status = 'reversed' then
    v_status := 'reversed';
    v_reason := 'reversal_after_terminal';
  else
    v_status := 'paid';
    v_reason := 'partial';
  end if;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(), v_sys), 'payout.reversal_record', 'payout', p_payout_id, v_reason,
          jsonb_build_object('status', v_po.status, 'hold_state', v_po.hold_state,
                             'amount_minor', v_po.amount_minor,
                             'stripe_transfer_ref', v_po.stripe_transfer_ref,
                             'total_reversed_minor', v_sum - p_amount_minor),
          jsonb_build_object('status', v_status,
                             'reversal_id', v_id,
                             'stripe_transfer_ref', p_stripe_transfer_ref,
                             'stripe_reversal_ref', p_stripe_reversal_ref,
                             'reversal_amount_minor', p_amount_minor,
                             'total_reversed_minor', v_sum,
                             'fully_reversed', v_sum >= v_po.amount_minor,
                             'source', v_source,
                             'hold', v_hold,
                             'command_key', p_command_key));

  return jsonb_build_object('status', case when v_reason = 'held' then 'held' else 'ok' end,
                            'payout_id', p_payout_id,
                            'reversal_id', v_id,
                            'payout_status', v_status,
                            'total_reversed_minor', v_sum,
                            'fully_reversed', v_sum >= v_po.amount_minor,
                            'obligation_linked', false,
                            'hold', v_hold);
end;
$$;

comment on function kernel.record_payout_reversal(uuid, text, text, integer, jsonb, text) is
  'The one writer of kernel.payout_reversal. Records a Stripe transfer_reversal against an organization settlement payout; replays on trr_; refuses failed (reconcile owns it) and never-executed rows; on the submitted ref-not-yet-stored race records the fact then hands the row to kernel.hold_payout_transfer_reversed; on paid moves to reversed ONLY via kernel.mark_payout_transfer_state when the running sum reaches amount_minor. Writes no ref, no amount, no obligation. service_role only.';


-- ============================================================================
-- R-4 — kernel.organization_obligation_recovery: ONE ROW PER RECEIPT.
--
--   WHY A TABLE AND NOT A COLUMN OR THE AUDIT LOG (KD §4.1). A mutable
--   `recovered_minor` is 094:26-40's rejected balance with a different name;
--   the audit log has no CHECK on the amount, no UNIQUE on the source, no FK
--   to the debt and an actor column that a machine cannot satisfy. A per-
--   receipt row has all four for free, and "what does this org still owe" is
--   `amount − Σ` — derivable, never stored.
--
--   THE CLOSED source_kind SET, AND WHAT IS DELIBERATELY ABSENT:
--     transfer_reversal — the receipt is a trr_ that MUST exist in
--                         kernel.payout_reversal, on a payout of THIS org, and
--                         the recovery can cite at most that reversal's amount.
--                         A trr_ links at most once (source UNIQUE).
--     manual            — an off-platform receipt; source_ref is the operator's
--                         receipt/ticket reference (1-128 chars).
--     NO 'writeoff'     — a write-off recovers nothing; it is the 094 status
--                         act, and the remaining amount is derivable.
--     NO 'offset_settlement' — no producer exists; adding a member without one
--                         is 094:198-200's own prohibition (owner Q3/Q1).
--
--   THE GUARD (BEFORE INSERT/UPDATE/DELETE), against every writer:
--     · append-only;
--     · the obligation is locked FOR UPDATE, so two receipts serialise on Σ;
--     · written_off ⇒ refused (obligation_written_off). A late receipt after a
--       write-off is an OWNER ITEM (KD §5 Q4): recorded here as a refusal, not
--       invented as a reopen;
--     · currency must equal the obligation's;
--     · Σ(existing) + new ≤ amount_minor (recovery_exceeds_debt) — over-
--       recovery is unstorable, and on a 'recovered' row Σ = amount already, so
--       this is also what makes 'recovered' terminal for receipts;
--     · transfer_reversal: the trr_ exists (reversal_not_found), its payout's
--       payee_org_id = obligation.org_id (reversal_org_mismatch) — Venue A's
--       debt cannot be settled with Venue B's org's money — and new.amount ≤
--       the reversal's amount (recovery_exceeds_reversal).
--
--   THE CONSEQUENCE (AFTER INSERT): when Σ reaches amount_minor the obligation
--   becomes 'recovered' with resolution_reason_code 'recovered:<source_kind>',
--   resolved_by the recorder, resolved_at now(). 094's guard permits
--   outstanding→recovered and its resolution_ck requires reason + resolved_at
--   together — both satisfied in the one UPDATE. Status is a CONSEQUENCE of
--   facts, never an act: nothing can say "recovered" without the receipts
--   that sum to the debt (R-6 refuses the act).
-- ============================================================================
create table if not exists kernel.organization_obligation_recovery (
  recovery_id    uuid primary key default gen_random_uuid(),
  obligation_id  uuid not null references kernel.organization_obligation(obligation_id) on delete restrict,
  amount_minor   integer not null check (amount_minor > 0),
  currency       text not null,
  source_kind    text not null check (source_kind in ('transfer_reversal','manual')),
  source_ref     text not null,
  recorded_by    uuid references auth.users(id) on delete restrict,
  command_key    text not null,
  created_at     timestamptz not null default now(),
  constraint obligation_recovery_source_uq  unique (source_kind, source_ref),
  constraint obligation_recovery_command_uq unique (command_key)
);
create index if not exists organization_obligation_recovery_obligation_idx
  on kernel.organization_obligation_recovery (obligation_id);

comment on table kernel.organization_obligation_recovery is
  'One row per receipt against a kernel.organization_obligation: a Stripe transfer reversal (trr_, which must exist in kernel.payout_reversal on a payout of the same org) or a manual off-platform receipt. Append-only; Σ can never exceed the debt; refused after write-off; when Σ = amount the obligation becomes recovered by trigger. No writeoff or offset source exists (no producer).';

create or replace function kernel.organization_obligation_recovery_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ob   kernel.organization_obligation%rowtype;
  v_sum  bigint;
  v_rev  record;
begin
  if tg_op in ('UPDATE','DELETE') then
    raise exception 'append_only: kernel.organization_obligation_recovery rows are never updated or deleted — a receipt recorded is a receipt recorded' using errcode = 'P0001';
  end if;

  select * into v_ob from kernel.organization_obligation where obligation_id = new.obligation_id for update;
  if not found then
    raise exception 'not_found: obligation %', new.obligation_id using errcode = 'P0002';
  end if;
  if v_ob.status = 'written_off' then
    raise exception 'precondition_failed: obligation_written_off — obligation % was written off; a receipt after write-off is an owner item and is not recorded here', new.obligation_id
      using errcode = 'P0001';
  end if;
  if upper(coalesce(new.currency,'')) <> upper(coalesce(v_ob.currency,'')) then
    raise exception 'precondition_failed: currency_mismatch — recovery % vs obligation %', new.currency, v_ob.currency
      using errcode = 'P0001';
  end if;
  select coalesce(sum(r.amount_minor), 0)::bigint into v_sum
    from kernel.organization_obligation_recovery r where r.obligation_id = new.obligation_id;
  if v_sum + new.amount_minor > v_ob.amount_minor then
    raise exception 'precondition_failed: recovery_exceeds_debt — % already recovered + % would exceed the obligation''s %', v_sum, new.amount_minor, v_ob.amount_minor
      using errcode = 'P0001';
  end if;

  if new.source_kind = 'transfer_reversal' then
    if new.source_ref !~ '^trr_[A-Za-z0-9]+$' then
      raise exception 'invalid_input: a transfer_reversal recovery must cite a trr_… reference' using errcode = 'P0001';
    end if;
    select r.amount_minor, p.payee_org_id, p.payout_id
      into v_rev
      from kernel.payout_reversal r
      join kernel.payout p on p.payout_id = r.payout_id
     where r.stripe_reversal_ref = new.source_ref;
    if not found then
      raise exception 'not_found: reversal_not_found — no kernel.payout_reversal row carries %', new.source_ref using errcode = 'P0002';
    end if;
    if v_rev.payee_org_id is distinct from v_ob.org_id then
      raise exception 'precondition_failed: reversal_org_mismatch — % reversed a payout of organization %, the obligation belongs to %', new.source_ref, v_rev.payee_org_id, v_ob.org_id
        using errcode = 'P0001';
    end if;
    if new.amount_minor > v_rev.amount_minor then
      raise exception 'precondition_failed: recovery_exceeds_reversal — % returned %, a recovery cannot cite more', new.source_ref, v_rev.amount_minor
        using errcode = 'P0001';
    end if;
  else
    if new.source_ref is null or length(trim(new.source_ref)) < 1 or length(new.source_ref) > 128 then
      raise exception 'invalid_input: a manual recovery must cite a receipt/ticket reference of 1-128 characters' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

comment on function kernel.organization_obligation_recovery_guard() is
  'BEFORE INSERT/UPDATE/DELETE on kernel.organization_obligation_recovery: append-only; obligation locked; refused after write-off; currency must match; Σ never exceeds the debt; a transfer_reversal must cite an existing trr_ on a payout of the same organization and at most that reversal''s amount.';

revoke all on function kernel.organization_obligation_recovery_guard() from public, anon, authenticated;

drop trigger if exists tg_organization_obligation_recovery_guard on kernel.organization_obligation_recovery;
create trigger tg_organization_obligation_recovery_guard
  before insert or update or delete on kernel.organization_obligation_recovery
  for each row execute function kernel.organization_obligation_recovery_guard();

create or replace function kernel.organization_obligation_recovery_settle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ob   kernel.organization_obligation%rowtype;
  v_sum  bigint;
begin
  select * into v_ob from kernel.organization_obligation where obligation_id = new.obligation_id for update;
  select coalesce(sum(r.amount_minor), 0)::bigint into v_sum
    from kernel.organization_obligation_recovery r where r.obligation_id = new.obligation_id;
  if v_ob.status = 'outstanding' and v_sum >= v_ob.amount_minor then
    update kernel.organization_obligation
       set status                 = 'recovered',
           resolution_reason_code = 'recovered:' || new.source_kind,
           resolved_by            = coalesce(new.recorded_by, auth.uid()),
           resolved_at            = now(),
           updated_at             = now()
     where obligation_id = new.obligation_id;
  end if;
  return null;
end;
$$;

comment on function kernel.organization_obligation_recovery_settle() is
  'AFTER INSERT on kernel.organization_obligation_recovery: when the receipts sum to the debt the obligation becomes recovered (reason recovered:<source_kind>, resolved_by the recorder, resolved_at now). Status is a consequence of facts, never an act.';

revoke all on function kernel.organization_obligation_recovery_settle() from public, anon, authenticated;

drop trigger if exists tg_organization_obligation_recovery_settle on kernel.organization_obligation_recovery;
create trigger tg_organization_obligation_recovery_settle
  after insert on kernel.organization_obligation_recovery
  for each row execute function kernel.organization_obligation_recovery_settle();

alter table kernel.organization_obligation_recovery enable row level security;
revoke all on kernel.organization_obligation_recovery from public, anon, authenticated, service_role;
revoke delete on kernel.organization_obligation_recovery from service_role;

-- The per-obligation projection: amount − Σ receipts while outstanding; 0
-- once recovered or written off (a write-off owes nothing to THIS read — the
-- remaining amount at write-off lives in the resolve audit row, R-6).
create or replace function kernel.obligation_outstanding_minor(p_obligation_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case when o.status = 'outstanding'
              then o.amount_minor::bigint
                   - coalesce((select sum(r.amount_minor) from kernel.organization_obligation_recovery r
                                where r.obligation_id = o.obligation_id), 0)::bigint
              else 0::bigint end
    from kernel.organization_obligation o
   where o.obligation_id = p_obligation_id;
$$;

comment on function kernel.obligation_outstanding_minor(uuid) is
  'amount_minor minus Σ recorded receipts for one obligation while it is outstanding; 0 for a recovered or written-off obligation.';

-- 094 J7-3b RE-CREATED, BODY ONLY. Same signature, STABLE SECURITY DEFINER
-- search_path='', same grant (create or replace preserves the ACL; R-8 does
-- not touch it). The only change: each outstanding obligation contributes
-- amount − Σ receipts instead of amount, so a partial recovery is netted.
create or replace function kernel.org_outstanding_obligation_minor(p_org_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(o.amount_minor::bigint
                      - coalesce((select sum(r.amount_minor) from kernel.organization_obligation_recovery r
                                   where r.obligation_id = o.obligation_id), 0)::bigint), 0)::bigint
    from kernel.organization_obligation o
   where o.org_id = p_org_id and o.status = 'outstanding';
$$;


-- ============================================================================
-- R-5 — kernel.record_obligation_recovery: A HUMAN DECLARES A RECEIPT.
--
--   Granted to `authenticated` ONLY and EXPLICITLY REVOKED from service_role —
--   the 095 E-2 / 085 record_money_denial hard edge: a machine cannot declare
--   a debt recovered. Authority kernel.is_platform(platform_risk|platform_
--   admin) on an aal2 session (the 095 E-2 idiom, verbatim: an absent claim is
--   unevaluable and fails closed).
--
--   Replay on command_key ⇒ noop_replay (a key bound to a different receipt
--   is a conflict, never a silent no-op — KD P2-1). The row is written; the
--   R-4 guard and settle triggers do the rest. One kernel.admin_audit row,
--   action 'org_obligation.recovery', with THE NUMBER in `after` (KD P2-2).
-- ============================================================================
create or replace function kernel.record_obligation_recovery(
  p_obligation_id uuid, p_amount_minor integer, p_source_kind text, p_source_ref text,
  p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_aal    text;
  v_ob     kernel.organization_obligation%rowtype;
  v_prev   kernel.organization_obligation_recovery%rowtype;
  v_id     uuid;
  v_sum    bigint;
  v_before bigint;
  v_after  kernel.organization_obligation%rowtype;
begin
  if v_uid is null then
    raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to record a recovery against an organization obligation';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_input: bad_amount' using errcode = 'P0001';
  end if;
  if p_source_kind is null or p_source_kind not in ('transfer_reversal','manual') then
    raise exception 'invalid_input: source_kind must be transfer_reversal|manual' using errcode = 'P0001';
  end if;
  if p_source_ref is null or length(trim(p_source_ref)) = 0 or length(p_source_ref) > 128 then
    raise exception 'invalid_input: source_ref is mandatory (1-128 characters: the trr_ or the receipt reference)' using errcode = 'P0001';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: bad_reason_code (mandatory)' using errcode = 'P0001';
  end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must match ^[A-Za-z0-9._:-]{1,64}$' using errcode = 'P0001';
  end if;

  select * into v_ob from kernel.organization_obligation where obligation_id = p_obligation_id for update;
  if not found then
    raise exception 'not_found: obligation %', p_obligation_id using errcode = 'P0002';
  end if;

  -- REPLAY on the command key, before anything is written.
  select * into v_prev from kernel.organization_obligation_recovery where command_key = p_command_key;
  if found then
    if v_prev.obligation_id <> p_obligation_id or v_prev.amount_minor <> p_amount_minor
       or v_prev.source_kind <> p_source_kind or v_prev.source_ref <> p_source_ref then
      raise exception 'conflict_locked: command_key_bound_elsewhere — % already names a different receipt', p_command_key
        using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','noop_replay','recovery_id', v_prev.recovery_id,
                              'obligation_id', p_obligation_id,
                              'obligation_status', v_ob.status,
                              'total_recovered_minor', v_ob.amount_minor - kernel.obligation_outstanding_minor(p_obligation_id),
                              'outstanding_minor', kernel.obligation_outstanding_minor(p_obligation_id));
  end if;
  -- A source links at most once; say so by name rather than as a bare 23505.
  if exists (select 1 from kernel.organization_obligation_recovery r
              where r.source_kind = p_source_kind and r.source_ref = p_source_ref) then
    raise exception 'conflict_locked: recovery_source_already_linked — % % is already recorded against an obligation', p_source_kind, p_source_ref
      using errcode = 'P0001';
  end if;

  v_before := kernel.obligation_outstanding_minor(p_obligation_id);

  insert into kernel.organization_obligation_recovery
         (obligation_id, amount_minor, currency, source_kind, source_ref, recorded_by, command_key)
  values (p_obligation_id, p_amount_minor, v_ob.currency, p_source_kind, p_source_ref, v_uid, p_command_key)
  returning recovery_id into v_id;

  select * into v_after from kernel.organization_obligation where obligation_id = p_obligation_id;
  select coalesce(sum(r.amount_minor), 0)::bigint into v_sum
    from kernel.organization_obligation_recovery r where r.obligation_id = p_obligation_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org_obligation.recovery', 'org_obligation', p_obligation_id, left(trim(p_reason_code), 120),
          jsonb_build_object('status', v_ob.status, 'outstanding_minor', v_before,
                             'amount_minor', v_ob.amount_minor),
          jsonb_build_object('status', v_after.status,
                             'recovery_id', v_id,
                             'amount_minor', p_amount_minor,
                             'currency', v_ob.currency,
                             'source_kind', p_source_kind,
                             'source_ref', left(p_source_ref, 128),
                             'total_recovered_minor', v_sum,
                             'outstanding_minor', kernel.obligation_outstanding_minor(p_obligation_id),
                             'command_key', p_command_key));

  return jsonb_build_object('status','ok','recovery_id', v_id,
                            'obligation_id', p_obligation_id,
                            'obligation_status', v_after.status,
                            'recovered_minor', p_amount_minor,
                            'total_recovered_minor', v_sum,
                            'outstanding_minor', kernel.obligation_outstanding_minor(p_obligation_id));
end;
$$;

comment on function kernel.record_obligation_recovery(uuid, integer, text, text, text, text) is
  'A platform human (platform_risk/platform_admin, aal2) records a receipt against an organization obligation: a Stripe transfer reversal (trr_) or a manual off-platform receipt. Replays on command_key; the storage triggers cap the sum at the debt, check the reversal''s org, refuse after write-off, and flip the obligation to recovered when the receipts sum to the debt. Audited with the amount. authenticated only; explicitly not service_role.';


-- ============================================================================
-- R-6 — kernel.resolve_organization_obligation: 094 J7-3 RE-CREATED.
--
--   THE REACHABILITY DEFECT (KD P1-1), fixed by grant: 094 granted the verb to
--   service_role only while its authority test reads auth.uid(). A service
--   client has no uid (42501 insufficient_privilege); a forwarded platform JWT
--   arrives as role `authenticated` (42501 permission denied). No real
--   principal could ever move an obligation out of 'outstanding'. The fix is
--   the identity twin's own shape (085:1838-1878 is granted to authenticated)
--   and the shape of 45 of the 47 is_platform-gated verbs: GRANT to
--   authenticated. The dead service_role grant is REVOKED — a machine cannot
--   write off a debt any more than it can declare one recovered (R-5), and a
--   grant no principal can exercise is exactly the dormant-machine-grant class
--   094's own header refuses.
--
--   THE HONESTY CHANGE (KD P1-4). 'recovered' is no longer an ACT. It is the
--   consequence of receipts summing to the debt (R-4's AFTER trigger), so this
--   verb REFUSES p_resolution='recovered' with precondition_failed:
--   recovery_facts_required unless Σ already equals the amount (then
--   noop_replay — structurally that row is already 'recovered'). 'written_off'
--   stays an explicit platform act, allowed only while outstanding, and its
--   audit `after` now carries the REMAINING amount (amount − Σ receipts) so an
--   operator reading the log sees what was given up, not only that something
--   was. A step-up (aal2) session is now required: a write-off is a money act.
--
--   Everything else — the is_platform authority, the input set, the lock, the
--   same-terminal replay, the exclusive-terminals conflict, the audit action —
--   is 094's, and its pgTAP file (160) still pins them.
-- ============================================================================
create or replace function kernel.resolve_organization_obligation(
  p_obligation_id uuid, p_resolution text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.organization_obligation%rowtype;
  v_aal text;
  v_sum bigint;
begin
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to resolve an organization obligation';
  end if;
  if p_resolution not in ('recovered','written_off') then
    raise exception 'invalid_input: resolution must be recovered|written_off' using errcode = 'P0001';
  end if;
  select * into v_row from kernel.organization_obligation
   where obligation_id = p_obligation_id for update;
  if not found then
    raise exception 'not_found: obligation %', p_obligation_id using errcode = 'P0002';
  end if;
  if v_row.status = p_resolution then
    return jsonb_build_object('status','noop_replay','obligation_id', p_obligation_id);
  end if;
  if v_row.status <> 'outstanding' then
    raise exception 'state_conflict: obligation % already % — terminals are exclusive', p_obligation_id, v_row.status
      using errcode = 'P0001';
  end if;
  select coalesce(sum(r.amount_minor), 0)::bigint into v_sum
    from kernel.organization_obligation_recovery r where r.obligation_id = p_obligation_id;
  if p_resolution = 'recovered' then
    if v_sum >= v_row.amount_minor then
      return jsonb_build_object('status','noop_replay','obligation_id', p_obligation_id);
    end if;
    raise exception 'precondition_failed: recovery_facts_required — record recoveries via kernel.record_obligation_recovery; status becomes recovered when Σ = amount (% of % recorded)', v_sum, v_row.amount_minor
      using errcode = 'P0001';
  end if;
  update kernel.organization_obligation
     set status = 'written_off',
         resolution_reason_code = coalesce(p_reason_code, 'written_off'),
         resolved_by = auth.uid(), resolved_at = now(), updated_at = now()
   where obligation_id = p_obligation_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (auth.uid(), 'org_obligation.resolve', 'org_obligation', p_obligation_id,
          coalesce(p_reason_code, 'written_off'),
          jsonb_build_object('status','outstanding', 'recovered_minor', v_sum,
                             'remaining_minor', v_row.amount_minor - v_sum),
          jsonb_build_object('status','written_off', 'recovered_minor', v_sum,
                             'remaining_minor', v_row.amount_minor - v_sum,
                             'amount_minor', v_row.amount_minor,
                             'command_key', left(coalesce(p_command_key,''), 64)));
  -- This verb moves NO money. It records that the platform gave up on the
  -- remainder; it credits no settlement and advances nothing.
  return jsonb_build_object('status','ok','obligation_id', p_obligation_id, 'status_now', 'written_off',
                            'recovered_minor', v_sum, 'remaining_minor', v_row.amount_minor - v_sum);
end;
$$;

comment on function kernel.resolve_organization_obligation(uuid, text, text, text) is
  'Write-off is the only ACT left on an organization obligation: platform_risk/platform_admin on aal2, outstanding only, audited with the remaining amount. ''recovered'' is refused without receipts (kernel.record_obligation_recovery) — status becomes recovered when the receipts sum to the debt. Granted to authenticated (096 R-6; it was unreachable by any real principal under 094''s service_role-only grant).';


-- ============================================================================
-- R-7 — THE REF-BEARING FAILED PAYOUT: CLAIM + RECONCILE (KE §4.2).
--
--   kernel.claim_failed_payouts_for_reconcile — the WORK LIST, the exact twin
--   of 093 slice 10p over a different population: status='failed' AND
--   stripe_transfer_ref IS NOT NULL AND cause='settlement' AND payee_kind=
--   'organization', not already claimed inside the lease ('payout.reconcile_
--   claim' audit rows), FOR UPDATE SKIP LOCKED, oldest first, operands clamped
--   1..100 / 60..3600 exactly as 10i/10p clamp them. No caller-nameable
--   subject: a machine reconciles what the ledger hands it. A ref-LESS failed
--   row is NOT in this population — that is 095 E-2's re-arm, a human act.
--
--   kernel.reconcile_payout_transfer — THE SINGLE-WRITER EDGE failed→paid.
--   095:11-19 verified that kernel.mark_payout_transfer_state refuses failed→
--   paid and that stays true (the verb is untouched; 161 B3/B4 still pin it).
--   Routing the row back through 'submitted' is impossible: 10p's claim needs
--   stripe_transfer_ref IS NULL and 10n refuses transfer_already_recorded. So
--   the edge is written HERE, by THIS verb only, from Stripe-OBSERVED facts
--   only, and it is honest exactly because:
--     (a) the caller's numbers are COMPARED, never stored — the only amount
--         this verb stores is a reversal amount, and that goes through R-3's
--         Σ-capped trigger, taken from Stripe's reversals[] (never from
--         p_observed.amount);
--     (b) the equalities are MANDATORY: caller ref = stored ref, stored ref
--         well-formed, observed amount = amount_minor, observed currency =
--         payout currency, observed destination = pinned destination_ref,
--         observed transfer_group = payout_<id>, exactly one transfer in the
--         group; any miss leaves the row 'failed', writes an audit, returns a
--         refusal the edge pages on;
--     (c) a 404 (found=false) stays 'failed' too. A terminal row cannot be
--         held (085:790), so the "operator hold" IS the audit + the page. The
--         only recovery of a stored ref Stripe does not know is KE Q3, an
--         owner item, deliberately not invented here;
--     (d) replays converge: a row already paid/reversed with the same ref is
--         noop_replay; reversal facts dedupe on trr_ (R-3);
--     (e) Stripe's reversals[] is paginated — the EDGE pages; the verb refuses
--         a list whose Σ is short of amount_reversed (reversals_incomplete),
--         so a short list can never under-record.
--   After the edge: 'payout.reconcile' audit before/after, venue.on_payout_
--   settled (087:360 — closed→paid iff no sibling is non-paid), then each
--   reversal through R-3 with source 'reconcile' (Σ = amount ⇒ 'reversed'
--   through the 085 edge, inside R-3). kernel.payout.status CHECK is NOT
--   widened; kernel.rearm_failed_payout is NOT modified.
--
--   p_observed shape: {found bool, id, amount, currency, destination,
--   transfer_group, reversed, amount_reversed, reversals:[{id, amount}],
--   group_count int}. Absent operands fail CLOSED (a missing amount is a
--   mismatch, a missing group count is ambiguous).
-- ============================================================================
create or replace function kernel.claim_failed_payouts_for_reconcile(
  p_limit integer default 25, p_lease_seconds integer default 900)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit   integer  := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_lease   integer  := least(greatest(coalesce(p_lease_seconds, 900), 60), 3600);
  v_sys     constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_rows    jsonb := '[]'::jsonb;
  v_r       record;
  v_tries   integer;
begin
  for v_r in
    select p.payout_id, p.created_at, p.status, p.stripe_transfer_ref,
           p.amount_minor, p.currency, p.destination_ref
      from kernel.payout p
     where p.cause = 'settlement'
       and p.payee_kind = 'organization'
       and p.status = 'failed'
       and p.stripe_transfer_ref is not null     -- a ref-less failure is E-2's (a human re-arm)
       and not exists (
             select 1 from kernel.admin_audit a
              where a.subject_kind = 'payout'
                and a.subject_id   = p.payout_id
                and a.action       = 'payout.reconcile_claim'
                and a.occurred_at  > now() - make_interval(secs => v_lease))
     order by p.created_at, p.payout_id
     limit v_limit
     for update skip locked
  loop
    select count(*)::integer into v_tries
      from kernel.admin_audit a
     where a.subject_kind = 'payout' and a.subject_id = v_r.payout_id
       and a.action = 'payout.reconcile_claim';

    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_sys, 'payout.reconcile_claim', 'payout', v_r.payout_id, 'reconcile',
            jsonb_build_object('status', v_r.status,
                               'stripe_transfer_ref', v_r.stripe_transfer_ref),
            jsonb_build_object('attempt', v_tries + 1,
                               'lease_seconds', v_lease));

    v_rows := v_rows || jsonb_build_object(
      'payout_id',           v_r.payout_id,
      'stripe_transfer_ref', v_r.stripe_transfer_ref,
      'transfer_group',      'payout_' || v_r.payout_id::text,
      'amount_minor',        v_r.amount_minor,
      'currency',            v_r.currency,
      'destination_ref',     v_r.destination_ref,
      'attempt',             v_tries + 1,
      'command_key',         'payout.reconcile:' || v_r.payout_id::text);
  end loop;

  return jsonb_build_object('payouts', v_rows,
                            'limit', v_limit,
                            'lease_seconds', v_lease,
                            'claimed_at', now());
end;
$$;

comment on function kernel.claim_failed_payouts_for_reconcile(integer, integer) is
  'The reconcile pass''s leased work list: failed organization settlement payouts that CARRY a Stripe transfer ref (the population 095 E-2 refuses). Clamped limit/lease, FOR UPDATE SKIP LOCKED, one ''payout.reconcile_claim'' audit per claim. service_role only; no caller-nameable subject.';

create or replace function kernel.reconcile_payout_transfer(
  p_payout_id uuid, p_stripe_transfer_ref text, p_observed jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_po        kernel.payout%rowtype;
  v_obs       jsonb := coalesce(p_observed, '{}'::jsonb);
  v_sys       constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_code      text;
  v_found     boolean;
  v_amount    bigint;
  v_currency  text;
  v_dest      text;
  v_group     text;
  v_gcount    integer;
  v_amt_rev   bigint;
  v_revs      jsonb;
  v_rev       jsonb;
  v_rev_sum   bigint := 0;
  v_rev_n     integer := 0;
  v_key       text;
  v_after     kernel.payout%rowtype;
  v_sum       bigint;
begin
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must match ^[A-Za-z0-9._:-]{1,64}$' using errcode = 'P0001';
  end if;
  if p_stripe_transfer_ref is null or length(trim(p_stripe_transfer_ref)) = 0 then
    raise exception 'invalid_input: the stored transfer ref being reconciled is mandatory' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_obs) <> 'object' then
    raise exception 'invalid_input: observed must be a JSON object' using errcode = 'P0001';
  end if;

  select * into v_po from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  if v_po.cause <> 'settlement' or v_po.payee_kind <> 'organization' then
    raise exception 'precondition_failed: not an organization settlement payout' using errcode = 'P0001';
  end if;
  if v_po.stripe_transfer_ref is null then
    raise exception 'precondition_failed: no_transfer_recorded — payout % carries no Stripe transfer ref; a ref-less failure is kernel.rearm_failed_payout''s (a human act), not this verb''s', p_payout_id
      using errcode = 'P0001';
  end if;
  if v_po.status <> 'failed' then
    if v_po.status in ('paid','reversed') and v_po.stripe_transfer_ref = p_stripe_transfer_ref then
      return jsonb_build_object('status','noop_replay','payout_id', p_payout_id,
                                'payout_status', v_po.status,
                                'total_reversed_minor', kernel.payout_reversed_minor(p_payout_id));
    end if;
    raise exception 'precondition_failed: payout_not_failed — payout % is %; this verb reconciles the ref-bearing failed row and nothing else', p_payout_id, v_po.status
      using errcode = 'P0001';
  end if;
  if v_po.hold_state <> 'none' then
    -- Structurally unreachable (a terminal row cannot be held, 085:790).
    raise exception 'precondition_failed: payout_held — a failed payout carrying hold_state=% was not produced by any contracted writer', v_po.hold_state
      using errcode = 'P0001';
  end if;

  -- ── THE OBSERVATION, read once, every operand failing CLOSED when absent ──
  v_found    := coalesce((v_obs ->> 'found')::boolean, false);
  v_amount   := nullif(v_obs ->> 'amount', '')::bigint;
  v_currency := v_obs ->> 'currency';
  v_dest     := v_obs ->> 'destination';
  v_group    := v_obs ->> 'transfer_group';
  v_gcount   := nullif(v_obs ->> 'group_count', '')::integer;
  v_amt_rev  := coalesce(nullif(v_obs ->> 'amount_reversed', '')::bigint, 0);
  v_revs     := coalesce(v_obs -> 'reversals', '[]'::jsonb);
  if jsonb_typeof(v_revs) <> 'array' then
    v_revs := '[]'::jsonb;  -- treated as "no list": reversals_incomplete below if money came back
  end if;
  for v_rev in select * from jsonb_array_elements(v_revs) loop
    if jsonb_typeof(v_rev) <> 'object'
       or coalesce(v_rev ->> 'id', '') !~ '^trr_[A-Za-z0-9]+$'
       or coalesce(nullif(v_rev ->> 'amount', '')::bigint, 0) <= 0 then
      v_code := coalesce(v_code, 'reversal_malformed');
    else
      v_rev_sum := v_rev_sum + (v_rev ->> 'amount')::bigint;
      v_rev_n   := v_rev_n + 1;
    end if;
  end loop;

  -- FIRST FAILING PREDICATE WINS, in causal order: the ref before the object,
  -- the object before its money, its money before its reversals.
  v_code := case
    when v_po.stripe_transfer_ref !~ '^tr_[A-Za-z0-9]+$'          then 'ref_unresolvable'
    when p_stripe_transfer_ref <> v_po.stripe_transfer_ref          then 'ref_mismatch'
    when not v_found                                                then 'transfer_unresolvable'
    when (v_obs ->> 'id') is not null
     and (v_obs ->> 'id') <> v_po.stripe_transfer_ref               then 'ref_mismatch'
    when v_amount is null or v_amount <> v_po.amount_minor          then 'amount_ledger_mismatch'
    when v_currency is null
      or lower(v_currency) <> lower(coalesce(v_po.currency,''))     then 'currency_mismatch'
    when v_dest is not null
     and v_dest is distinct from v_po.destination_ref                then 'destination_mismatch'
    when v_group is not null
     and v_group <> 'payout_' || p_payout_id::text                   then 'transfer_group_mismatch'
    when coalesce(v_gcount, 0) <> 1                                  then 'reconcile_ambiguous'
    when v_code is not null                                          then v_code   -- reversal_malformed
    when v_amt_rev > v_rev_sum                                       then 'reversals_incomplete'
    when v_rev_sum > v_amt_rev                                       then 'reversals_inconsistent'
    when v_rev_sum > v_po.amount_minor                               then 'reversal_exceeds_transfer'
    else null
  end;

  if v_code is not null then
    -- STAYS FAILED. Audited once per command key (the edge re-observes on
    -- every tick; the ledger records each distinct observation, not each tick).
    if not exists (select 1 from kernel.admin_audit a
                    where a.subject_kind = 'payout' and a.subject_id = p_payout_id
                      and a.action = 'payout.reconcile_refused'
                      and a.after ->> 'command_key' = p_command_key
                      and a.reason_code = v_code) then
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
      values (coalesce(auth.uid(), v_sys), 'payout.reconcile_refused', 'payout', p_payout_id, v_code,
              jsonb_build_object('status', v_po.status,
                                 'stripe_transfer_ref', v_po.stripe_transfer_ref,
                                 'amount_minor', v_po.amount_minor,
                                 'destination_ref', v_po.destination_ref),
              jsonb_build_object('status', v_po.status,
                                 'refusal_code', v_code,
                                 'observed', v_obs,
                                 'command_key', p_command_key));
    end if;
    return jsonb_build_object('status','refused','refusal_code', v_code,
                              'payout_id', p_payout_id, 'payout_status', v_po.status,
                              'stripe_transfer_ref', v_po.stripe_transfer_ref);
  end if;

  -- ── THE SINGLE-WRITER EDGE: failed → paid. Two columns, enumerated. ───────
  update kernel.payout
     set status     = 'paid',
         updated_at = now()
   where payout_id = p_payout_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(), v_sys), 'payout.reconcile', 'payout', p_payout_id, 'failed_to_paid',
          jsonb_build_object('status', 'failed',
                             'stripe_transfer_ref', v_po.stripe_transfer_ref,
                             'amount_minor', v_po.amount_minor,
                             'destination_ref', v_po.destination_ref),
          jsonb_build_object('status', 'paid',
                             'observed', v_obs,
                             'amount_reversed_minor', v_amt_rev,
                             'reversal_count', v_rev_n,
                             'command_key', p_command_key));

  -- the FIFTH seam, exactly as 085:1729-1732 fires it on 'paid'.
  perform venue.on_payout_settled(p_payout_id);

  -- Then the money that came back, one fact per trr_, through R-3. Σ = amount
  -- ⇒ 'reversed' through the 085 edge, inside R-3. The command key is derived
  -- so it stays inside R-3's 64-char shape whatever the caller's key length.
  for v_rev in select * from jsonb_array_elements(v_revs) loop
    v_key := left('rc:' || p_command_key, 30) || ':' || left(v_rev ->> 'id', 33);
    perform kernel.record_payout_reversal(
      p_payout_id, v_po.stripe_transfer_ref, v_rev ->> 'id', (v_rev ->> 'amount')::integer,
      v_obs || jsonb_build_object('source', 'reconcile', 'transfer_amount_minor', v_amount),
      v_key);
  end loop;

  select * into v_after from kernel.payout where payout_id = p_payout_id;
  v_sum := kernel.payout_reversed_minor(p_payout_id);
  return jsonb_build_object('status','ok','payout_id', p_payout_id,
                            'payout_status', v_after.status,
                            'total_reversed_minor', v_sum,
                            'fully_reversed', v_sum >= v_after.amount_minor,
                            'settlement_id', v_after.cause_ref);
end;
$$;

comment on function kernel.reconcile_payout_transfer(uuid, text, jsonb, text) is
  'The SOLE writer of the failed -> paid edge, from Stripe-observed facts only: the stored tr_ must be well-formed and equal the caller''s, the observed transfer must exist with amount/currency/destination/transfer_group equal to the ledger''s and be alone in its group, and the reversal list must cover amount_reversed. Any miss leaves the row failed, audited, returned as a refusal. On success: paid, audit, venue.on_payout_settled, then each reversal via kernel.record_payout_reversal (source reconcile). service_role only.';


-- ============================================================================
-- R-8 — GRANTS (076/085 PART 14 discipline; the 094 J7-5 shape)
--   Trigger functions are callable by NOBODY. The machine class is service_role
--   only. The human class is authenticated only AND explicitly revoked from
--   service_role (the 095 E-2 hard edge). kernel.org_outstanding_obligation_
--   minor's ACL is preserved by create or replace and NOT restated (094:801-806).
-- ============================================================================
do $$
declare
  v_fn text;
  v_defs constant text[] := array[
    'kernel.payout_reversal_guard()',
    'kernel.payout_reversed_minor(uuid)',
    'kernel.record_payout_reversal(uuid, text, text, integer, jsonb, text)',
    'kernel.organization_obligation_recovery_guard()',
    'kernel.organization_obligation_recovery_settle()',
    'kernel.obligation_outstanding_minor(uuid)',
    'kernel.record_obligation_recovery(uuid, integer, text, text, text, text)',
    'kernel.resolve_organization_obligation(uuid, text, text, text)',
    'kernel.claim_failed_payouts_for_reconcile(integer, integer)',
    'kernel.reconcile_payout_transfer(uuid, text, jsonb, text)'
  ];
  v_svc constant text[] := array[
    'kernel.payout_reversed_minor(uuid)',
    'kernel.record_payout_reversal(uuid, text, text, integer, jsonb, text)',
    'kernel.obligation_outstanding_minor(uuid)',
    'kernel.claim_failed_payouts_for_reconcile(integer, integer)',
    'kernel.reconcile_payout_transfer(uuid, text, jsonb, text)'
  ];
  v_auth constant text[] := array[
    'kernel.record_obligation_recovery(uuid, integer, text, text, text, text)',
    'kernel.resolve_organization_obligation(uuid, text, text, text)'
  ];
  v_nobody constant text[] := array[
    'kernel.payout_reversal_guard()',
    'kernel.organization_obligation_recovery_guard()',
    'kernel.organization_obligation_recovery_settle()'
  ];
begin
  foreach v_fn in array v_defs loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
  end loop;
  foreach v_fn in array v_svc loop
    execute format('grant execute on function %s to service_role', v_fn);
  end loop;
  foreach v_fn in array v_auth loop
    execute format('grant execute on function %s to authenticated', v_fn);
    -- THE HARD EDGE: a machine identity must never declare or forgive a debt.
    execute format('revoke execute on function %s from service_role', v_fn);
  end loop;
  foreach v_fn in array v_nobody loop
    execute format('revoke all on function %s from service_role', v_fn);
  end loop;
end $$;

commit;
