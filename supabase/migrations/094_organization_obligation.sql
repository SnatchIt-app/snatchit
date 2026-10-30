-- ============================================================================
-- 094_organization_obligation.sql — the org-side receivable RECORD.
--
-- Design of record: docs/phase2/_impl/J3_receivable_architecture.md (shape A′,
-- §5.1/§5.2/§5.3) · implementation note docs/phase2/_impl/J7_obligation_
-- implementation.md. Structural twin of kernel.identity_obligation (085:165-198
-- + its RPC pair 085:1790-1878; schema §1.10a, F-P2-1/OR-21).
--
-- ── THE STRUCTURAL REASON THIS OBJECT MUST EXIST ────────────────────────────
-- THE PLATFORM CANNOT OPEN A SETTLEMENT. venue.open_settlement's authority gate
-- is `kernel.has_venue_role(...,'venue_finance') OR kernel.has_org_role(...,
-- 'org_finance','org_owner')` (087:237-239), and kernel.has_org_role is PURE
-- MEMBERSHIP — `exists (select 1 from kernel.org_member m where m.org_id = ...
-- and m.identity_id = auth.uid() and m.role = any(p_roles))` (077:453-466). It
-- carries NO kernel.is_platform arm (contrast venue.settlement's SELECT policy,
-- which does — 087:79-81).
--
-- Since venue.settlement_line.settlement_id is NOT NULL to a header that only
-- the DEBTOR'S OWN STAFF (or its venue's finance staff) can create, a debt that
-- lives only in the ledger is A DEBT WHOSE BOOKING DEPENDS ON THE DEBTOR'S
-- COOPERATION. An org that simply stops opening settlements is an org whose
-- chargeback losses can never be entered into the ledger at all. That is
-- precisely why kernel.identity_obligation's writer is a service_role definer
-- path rather than a settlement line, and the org side needs the same property.
--
-- ── WHY APPEND-ONLY RATHER THAN A MUTABLE BALANCE ───────────────────────────
-- This is the load-bearing argument and it is MECHANICAL, not stylistic.
-- THE PRODUCER IS AN AT-LEAST-ONCE WEBHOOK. Stripe retries
-- `charge.dispute.closed`; 069_webhook_retries_table retries locally on top of
-- that. Under at-least-once delivery `balance = balance - X` has NO
-- DATABASE-ENFORCEABLE IDEMPOTENCY — a duplicate delivery double-debits an org
-- and the row itself carries no evidence that it happened — while
-- `INSERT … UNIQUE(origin_kind, origin_ref)` has one the database enforces for
-- free. EVERY idempotent money writer in this codebase is built the second way:
-- payout_idempotency_uq (085:138), refund_idempotency_uq (085:93),
-- identity_obligation_origin_uq (085:180), order_buyer_command_uq (082:93),
-- market_sale_buyer_command_uq (088:131). A mutable balance would be the ONLY
-- member of the money layer without that property. UNIQUE(origin_kind,
-- origin_ref) below IS the idempotency mechanism, not a hygiene constraint.
--
-- Two further consequences, both stated so they are not re-litigated:
--   (a) the projection is DERIVABLE — "what does org X owe us" is
--       `select sum(amount_minor) … where org_id = X and status='outstanding'`,
--       served by the partial index below. No stored balance is materialised,
--       and none should be until an operator surface actually demands one.
--   (b) it dissolves E-149's one-per-org vs one-per-(org,currency) precondition
--       instead of answering it: that question is forced only for a SINGLE-ROW
--       BALANCE, where the row IS the key. A per-origin append-only table is
--       naturally one-obligation-per-origin-fact, in whatever currency that
--       fact occurred, and it carries its own currency column per row.
--
-- ── DIRECTION IS CARRIED BY IDENTITY, NEVER BY A SIGN ───────────────────────
-- amount_minor is `integer CHECK (> 0)` — a POSITIVE MAGNITUDE. A signed amount
-- would invite a negative-payout hack and would encode "we hold their money"
-- and "they owe us money" as the sign of one integer. Every positivity
-- invariant on the money layer stays intact; kernel.payout's
-- `CHECK (amount_minor > 0)` is NOT touched here.
--
-- ── THE ATTESTATION, WHICH IS LITERALLY TRUE OF WHAT IS BUILT HERE ──────────
-- Matching kernel.identity_obligation's ratified posture verbatim
-- (PHASE_2_MONEY_AUTHORITY_SPEC.md:1493-1496): THIS OBJECT RECORDS A DEBT AND
-- RESOLVES IT BY AN AUDITED PLATFORM ACT. IT FUNDS NOTHING, IT NETS NOTHING,
-- AND IT GATES NO PAYOUT. Concretely, and checkably:
--   · NOTHING here reads kernel.organization_obligation to decide whether money
--     moves. It is not an operand of close_settlement's mint, of
--     kernel.settlement_payout_maturity, of kernel.request_org_payout, of
--     kernel.get_payout_execution_context, or of any hold predicate.
--   · NOTHING here writes venue.settlement_line. No new `cause` is added —
--     that was J3's own WITHDRAWN first draft (§5-bis.2): a second netting
--     cause would double-count against the chargeback arm at 088:351-362 /
--     093:1180-1196 which already nets, reproducing the exact defect 093's
--     slice 10h just fixed between `refund_void` and `chargeback`.
--   · kernel.settlement_royalty_lines is NOT touched. The chargeback arm keeps
--     its shipped semantics, including its deliberate absence of a scope
--     predicate (088:310-316; "not 093's to change", 093:1131-1133).
--   · kernel.reserve is NOT touched. It stays EMPTY, sealed and droppable;
--     091's always-empty checked property and its guarded rollback survive
--     this migration intact (E-149/E-151).
--   · kernel.identity_obligation, its origin_kind enum and BP-10 are NOT
--     touched. This is a separate table with its own closed enum, so
--     schema §1.10a:1186's enum-extension trigger is not fired.
--   · NOTHING HERE PAYS A PROMOTER. No promoter_commission payout is released,
--     unheld or advanced by anything in this file; kernel.pay_promoter_
--     commission and kernel.release_payout are not named.
--
-- ── THE MEASURED DEFECT THIS OBJECT REPAIRS ────────────────────────────────
-- The "accidental future offset" earlier reports described IS NOT FUTURE-
-- SETTLEMENT OFFSET AT ALL, and the measurement is the strongest argument for
-- a durable object. Executed on a full replay: a −7,000 residue after a partial
-- recovery DOES NOT CARRY to the next close. The recovered fraction is decided
-- purely by which revenue happens to sit in the SAME kernel.close_settlement
-- call; offset works only INSIDE one call. Across that replay, SEVEN negative
-- headers totalling −99,000 sat permanently closed with NOTHING aggregating,
-- ageing or alerting on them. Each of those seven is exactly one
-- `settlement_shortfall` row under J7-4 below.
--
-- The two debit causes also fail in OPPOSITE directions, which is why ORG is
-- the only correct scope for the record:
--   · `chargeback` (088:311-316) has NO scope predicate and therefore
--     OVER-collects — it can land in any settlement of the org;
--   · `refund_void` joins scoped_order (093:519) and therefore UNDER-collects
--     — it can never drift out of its scope, so when the originating scope has
--     no future close the debit simply STRANDS.
-- A receivable keyed to the settlement or to the venue would repair one half.
-- A receivable keyed to the ORGANIZATION repairs both.
--
-- THE BOUNDARY, stated because it is the thing most likely to be got wrong: a
-- refund BEFORE payout must create NO obligation. 093's refund timing is
-- already correct (succeeded-only debit at 093:526 plus whole-order deferral at
-- 093:477-479), so a pre-payout refund genuinely reduces the CURRENT
-- settlement. This object exists only for the POST-payout case, and it is
-- reached only through a net that has already gone negative.
--
-- ── PRODUCER STATUS: ONE ORIGIN IS LIVE, ONE IS INERT ───────────────────────
-- Stated plainly, because an object that cannot be written is worse than no
-- object if the report implies otherwise:
--   · `settlement_shortfall` HAS A PRODUCER the moment this file lands —
--     kernel.close_settlement's negative branch in J7-4, which this file
--     authors. Nothing else needs to be built or called for it to fire.
--   · `unlined_reversal` IS INERT. It needs the dispute writers to be called,
--     and kernel.record_dispute_native / mark_dispute_state /
--     resolve_dispute_native have ZERO callers in any TypeScript today (the
--     webhook's dispute branches write only the legacy public.disputes /
--     transfers / payments), which is also why the `chargeback` settlement-line
--     arm cannot fire in production and why kernel.record_identity_obligation
--     has no caller outside pgTAP 149. Wiring that path is a SEPARATE TRAIN and
--     it touches the webhook; it is deliberately NOT done here. Until it is,
--     this origin is reachable only by an explicit operator call to
--     kernel.record_organization_obligation.
--
-- ── GOVERNANCE (recorded, not resolved by this file) ────────────────────────
-- J3 §5-bis.4 holds that this object requires its own numbered owner ruling,
-- the way kernel.identity_obligation shipped under OR-21 and
-- kernel.dispute_native under R-40, because schema §1.10a:1186 assigns
-- "org-side negative-settlement carry" to C31/Gate-M. This migration is
-- authored DARK and unapplied; the ratification row is a deploy precondition,
-- not a build one. See J7 §Governance.
--
-- ── WHAT THIS MIGRATION CLAIMS IN 094 (merge coordination) ──────────────────
-- 094 is shared. 094_payout_state_machine_recovery.sql is the payout state
-- machine's file; this one is the obligation object's. They sort
-- `094_organization_obligation` < `094_payout_state_machine_recovery` under the
-- chain's LC_ALL=C filename order, so THIS FILE APPLIES FIRST and
-- kernel.organization_obligation exists before that file runs.
--
-- Claimed here, and nowhere else: ONE table (kernel.organization_obligation),
-- FOUR functions (kernel.organization_obligation_guard,
-- kernel.record_organization_obligation, kernel.resolve_organization_obligation,
-- kernel.org_outstanding_obligation_minor), TWO triggers on the new table, and
-- ONE `create or replace` on kernel.close_settlement whose ONLY delta from the
-- 093 text is the `elsif v_net < 0 then` branch in J7-4 — 093's `if v_net > 0`
-- block, its mint, its maturity gate, its audit row and its return value are
-- byte-identical. No other object in the chain is modified. Verified
-- non-colliding with 094_payout_state_machine_recovery.sql, which touches
-- kernel.payout's authorization edge, venue.settlement's forward-only guard and
-- kernel.get_payout_execution_context — and does NOT replace
-- kernel.close_settlement.
-- ============================================================================
begin;

-- ============================================================================
-- SECTION J7-1 — kernel.organization_obligation (J3 §5.1)
--   Transcribed from kernel.identity_obligation (085:165-198), not invented.
--   Column-for-column divergences, each deliberate:
--     · debtor_identity_id → org_id (FK kernel.organization ON DELETE RESTRICT
--       — the house action for every FK to kernel.organization, 077 / 085:114 /
--       091:31; it buys "a debt blocks org deletion" for free, exactly as the
--       identity twin's FK does for BP-10).
--     · origin_kind's closed set is the ORG-side one (J7-2 below), and it
--       attaches to the SHORTFALL, not to the dispute.
--   Everything else — the positive-magnitude amount, the currency column, the
--   forward-only status triple, the resolution pairing CHECK, the origin
--   UNIQUE, the dispute partial UNIQUE, the outstanding partial index, the
--   updated_at trigger, RLS-on-with-zero-policies and REVOKE DELETE — is the
--   twin's shape unchanged.
-- ============================================================================
create table if not exists kernel.organization_obligation (
  obligation_id          uuid primary key default gen_random_uuid(),
  -- ON DELETE RESTRICT: an outstanding debt makes its org undeletable.
  org_id                 uuid not null references kernel.organization(org_id) on delete restrict,
  -- CLOSED, DERIVED, MINIMAL. Exactly the two origins that have a producer
  -- today (J3 §5.2). Both attach to what NETTING FAILED TO DO, never to the
  -- dispute itself — the dispute is already netted by the shipped chargeback
  -- arm. The two are DISJOINT BY CONSTRUCTION: the first exists only where a
  -- close happened, the second only where no close ever happens.
  --   settlement_shortfall — origin_ref = settlement_id. The residual a close
  --     could not net: close_settlement reached `net_minor < 0`, minted no
  --     payout (kernel.payout CHECK amount_minor > 0), and before this file
  --     DESTROYED the excess ("A negative net is NOT a receivable: this schema
  --     has no carry-forward object", 093:376). This origin is
  --     SNATCH_IT_DOMAIN_ARCHITECTURE.md:411's "implicit stranded value" made
  --     into a first-class fact.
  --   unlined_reversal — origin_ref = dispute_id | refund_id. The DORMANT-ORG
  --     case, where the debit is never even OFFERED because no settlement is
  --     ever opened (see the header's structural reason). Guarded in J7-3
  --     against an origin that already carries a chargeback/refund_void line,
  --     because booking that would double-count against the existing netting.
  -- Extending this enum carries the same ratification requirement schema
  -- §1.10a carries for the identity twin's. Do NOT add a member without a
  -- producer.
  origin_kind            text not null check (origin_kind in ('settlement_shortfall','unlined_reversal')),
  -- SOFT reference — the kernel.payout.cause_ref discipline (points across
  -- schemas/rails without creating an ordering cycle). Existence is verified
  -- by the writer in J7-3, not by an FK.
  origin_ref             uuid not null,
  stripe_dispute_ref     text,
  -- POSITIVE MAGNITUDE ONLY. Direction is the object's identity. integer is
  -- correct and matches the twin (085:171): this is per-origin, one row per
  -- shortfall or reversal, bounded above by the payment it derives from, which
  -- is bounded by venue."order".total_minor integer CHECK > 0 (082:83). The
  -- AGGREGATE (Σ outstanding) must be computed in bigint by its reader, per the
  -- settlement_line_candidate.amount_minor bigint / close_settlement v_gross
  -- bigint discipline (087:29, 093:645). E-149's int8-widening precondition is
  -- a property of an ACCUMULATOR and does not reach a per-origin row.
  amount_minor           integer not null check (amount_minor > 0),
  -- Per-row, per-origin. The rail is effectively USD-only (venue.open_settlement
  -- takes no currency parameter, so venue.settlement.currency is always the
  -- column default; kernel.payout.currency is written from the header). Carrying
  -- currency per row is what makes a USD debt against a non-USD settlement
  -- structurally un-offerable rather than a policy question.
  currency               text not null default 'USD',
  -- FORWARD-ONLY, single transition, terminals mutually exclusive. Resolved
  -- ONLY by an audited platform act (J7-3's resolve verb) — NEVER automatically,
  -- never by a sweep, never by netting.
  status                 text not null default 'outstanding'
                         check (status in ('outstanding','recovered','written_off')),
  resolution_reason_code text,
  resolved_by            uuid references auth.users(id) on delete restrict,
  resolved_at            timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  -- THE IDEMPOTENCY MECHANISM (see the header). Not a hygiene constraint: this
  -- is what makes an at-least-once webhook safe to hand a money writer.
  constraint organization_obligation_origin_uq unique (origin_kind, origin_ref),
  -- §1.9/§1.10 pairing: outstanding XOR a complete resolution triple.
  constraint organization_obligation_resolution_ck check (
    (status = 'outstanding') = (resolution_reason_code is null and resolved_at is null)
  )
);
-- The second idempotency key, for the webhook that carries a dispute ref.
create unique index if not exists organization_obligation_dispute_uq
  on kernel.organization_obligation (stripe_dispute_ref) where stripe_dispute_ref is not null;
-- THIS INDEX IS THE "what does this org owe us" READ (J3 §6.1). Nothing else
-- serves it and nothing materialises it.
create index if not exists organization_obligation_outstanding_idx
  on kernel.organization_obligation (org_id) where status = 'outstanding';

drop trigger if exists tg_organization_obligation_set_updated_at on kernel.organization_obligation;
create trigger tg_organization_obligation_set_updated_at before update on kernel.organization_obligation
  for each row execute function kernel.set_updated_at();

-- ── APPEND-ONLY, ENFORCED IN THE STORAGE LAYER ──────────────────────────────
-- A DELIBERATE STRENGTHENING over the identity twin, which relies on REVOKE
-- DELETE plus the fact that its only UPDATE path is a definer RPC. Here the
-- write-once and forward-only properties are ALSO trigger-enforced, so they
-- hold against the table owner, against a future definer, and against a
-- fixture — i.e. they are properties of the TABLE, not of one function's
-- discipline. "Append-only" is the headline claim of this object; a claim that
-- only one function keeps is not a property.
create or replace function kernel.organization_obligation_guard()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    -- Belt and braces with the REVOKE below: a realized loss is never erased.
    raise exception 'append_only: kernel.organization_obligation rows are never deleted' using errcode = 'P0001';
  end if;
  -- Origin columns are WRITE-ONCE. Rewriting org_id, the origin pair, the
  -- magnitude or the currency would silently restate a booked money fact.
  if new.obligation_id is distinct from old.obligation_id
     or new.org_id      is distinct from old.org_id
     or new.origin_kind is distinct from old.origin_kind
     or new.origin_ref  is distinct from old.origin_ref
     or new.amount_minor is distinct from old.amount_minor
     or new.currency    is distinct from old.currency
     or new.created_at  is distinct from old.created_at then
    raise exception 'append_only: obligation identity, magnitude and currency are write-once' using errcode = 'P0001';
  end if;
  -- FORWARD-ONLY, and terminals are terminal. `outstanding` is the only state
  -- with an exit, and it has exactly two. Over-resolution is unstorable.
  if old.status <> 'outstanding' and new.status is distinct from old.status then
    raise exception 'state_conflict: obligation % is already % — terminals are exclusive', old.obligation_id, old.status
      using errcode = 'P0001';
  end if;
  if new.status = 'outstanding' and old.status <> 'outstanding' then
    raise exception 'state_conflict: an obligation never returns to outstanding' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists tg_organization_obligation_guard on kernel.organization_obligation;
create trigger tg_organization_obligation_guard before update or delete on kernel.organization_obligation
  for each row execute function kernel.organization_obligation_guard();

-- ── RLS §7.11 money-custody-RPC-only, DENY-ALL ──────────────────────────────
-- RLS ON with ZERO POLICIES; no client grant; NO DORMANT MACHINE GRANT ON THE
-- TABLE ITSELF (the E-118/E-106 class — every 085 money ledger carries none).
-- E-150's "a Gate-M writer will be a definer path" is satisfied BY
-- CONSTRUCTION: the definer pair in J7-3 is the only way in.
alter table kernel.organization_obligation enable row level security;
revoke all on kernel.organization_obligation from public, anon, authenticated, service_role;
-- GP-2: no DELETE ever, from anyone reachable by grant. Stated redundantly with
-- the REVOKE ALL above because it is the specific invariant, and because a
-- later grant of table privileges must not silently re-hand DELETE.
revoke delete on kernel.organization_obligation from service_role;

-- ============================================================================
-- SECTION J7-2 — the definer WRITE verb (J3 §5.1; the 085:1790-1836 pattern)
--   kernel.record_organization_obligation — service_role only.
--
--   Signature divergences from kernel.record_identity_obligation, both forced:
--     · p_org_id replaces p_debtor_identity_id;
--     · p_currency is carried, because this object's currency is per-origin
--       (J3 §8) rather than the identity twin's implicit default.
--
--   The caller may NOT choose the amount for a settlement_shortfall: it is
--   re-derived from the closed header and the caller's value must agree. A
--   money writer whose magnitude is a free parameter is a money writer.
-- ============================================================================
create or replace function kernel.record_organization_obligation(
  p_org_id uuid, p_origin_kind text, p_origin_ref uuid, p_stripe_dispute_ref text,
  p_amount_minor integer, p_currency text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id  uuid;
  v_ccy text := coalesce(nullif(p_currency, ''), 'USD');
  v_s   venue.settlement%rowtype;
begin
  if p_origin_kind not in ('settlement_shortfall','unlined_reversal') then
    raise exception 'invalid_input: bad origin_kind %', p_origin_kind using errcode = 'P0001';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_input: bad_amount' using errcode = 'P0001';
  end if;
  if p_org_id is null or p_origin_ref is null then
    raise exception 'invalid_input: org_id and origin_ref are required' using errcode = 'P0001';
  end if;
  if v_ccy !~ '^[A-Z]{3}$' then
    raise exception 'invalid_input: currency % is not an ISO-4217 alpha code', v_ccy using errcode = 'P0001';
  end if;
  -- The soft reference's OWNER is existence-verified (no FK on origin_ref, so
  -- the org FK is the only structural one and it is checked here first for a
  -- named error rather than a raw 23503).
  if not exists (select 1 from kernel.organization o where o.org_id = p_org_id) then
    raise exception 'not_found: organization %', p_org_id using errcode = 'P0002';
  end if;

  if p_origin_kind = 'settlement_shortfall' then
    -- The origin must be a CLOSED header of THIS org that actually nets
    -- negative, and the magnitude must equal the shortfall exactly. This is
    -- what makes the in-close write in J7-4 and an out-of-band operator write
    -- the SAME act rather than two writers with two truths.
    select * into v_s from venue.settlement where settlement_id = p_origin_ref;
    if not found then
      raise exception 'not_found: settlement %', p_origin_ref using errcode = 'P0002';
    end if;
    if v_s.org_id <> p_org_id then
      raise exception 'precondition_failed: settlement % belongs to another org', p_origin_ref using errcode = 'P0001';
    end if;
    if v_s.status = 'open' or v_s.net_minor is null then
      raise exception 'precondition_failed: a shortfall is booked only from a CLOSED settlement' using errcode = 'P0001';
    end if;
    if v_s.net_minor >= 0 then
      raise exception 'precondition_failed: settlement % nets % — there is no shortfall', p_origin_ref, v_s.net_minor
        using errcode = 'P0001';
    end if;
    if p_amount_minor <> -v_s.net_minor then
      raise exception 'precondition_failed: amount % is not the settlement shortfall %', p_amount_minor, -v_s.net_minor
        using errcode = 'P0001';
    end if;
    if v_ccy <> v_s.currency then
      raise exception 'precondition_failed: currency % differs from the settlement currency %', v_ccy, v_s.currency
        using errcode = 'P0001';
    end if;
  else
    -- unlined_reversal — THE ANTI-DOUBLE-COUNT GUARD. If this dispute or refund
    -- already carries a chargeback/refund_void line in ANY settlement, the
    -- shipped netting has already offered to recover it (088:351-362 /
    -- 093:1180-1196 write cause_ref = dispute_id; the refund_void arm writes
    -- cause_ref = refund_id), and booking an obligation on top of it would
    -- double-count the same loss — the exact defect 093's slice 10h fixed
    -- between refund_void and chargeback.
    if exists (select 1 from venue.settlement_line l
                where l.cause in ('chargeback','refund_void') and l.cause_ref = p_origin_ref) then
      raise exception 'precondition_failed: origin % is already lined — netting has it, booking it here would double-count', p_origin_ref
        using errcode = 'P0001';
    end if;
  end if;

  insert into kernel.organization_obligation
         (org_id, origin_kind, origin_ref, stripe_dispute_ref, amount_minor, currency)
  values (p_org_id, p_origin_kind, p_origin_ref, p_stripe_dispute_ref, p_amount_minor, v_ccy)
  -- NAMED, never bare: this tolerates ONLY the origin replay. A duplicate
  -- stripe_dispute_ref across two origins still raises, as it must.
  on conflict on constraint organization_obligation_origin_uq do nothing
  returning obligation_id into v_id;
  if v_id is null then
    -- THE AT-LEAST-ONCE PATH. A redelivered webhook lands here, changes
    -- nothing, and is told which row already carries the fact.
    select o.obligation_id into v_id from kernel.organization_obligation o
     where o.origin_kind = p_origin_kind and o.origin_ref = p_origin_ref;
    return jsonb_build_object('status','noop_replay','obligation_id', v_id);
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'org_obligation.record', 'org_obligation',
          v_id, coalesce(p_reason_code, p_origin_kind));
  return jsonb_build_object('status','ok','obligation_id', v_id, 'amount_minor', p_amount_minor, 'currency', v_ccy);
end;
$$;

-- ============================================================================
-- SECTION J7-3 — the definer RESOLVE verb (the 085:1838-1878 pattern)
--   kernel.resolve_organization_obligation — service_role only.
--
--   AUTHORITY: kernel.is_platform(platform_risk|platform_admin), unchanged from
--   the identity twin. The GRANT diverges deliberately: the twin is also
--   granted to `authenticated` (edge-fronted, caller JWT); this pair is
--   service_role ONLY, so the verb is reachable only through an edge function
--   forwarding a platform principal's JWT. Strictly tighter, and it keeps the
--   pair's grant class uniform (J3 §9 / E-150).
--
--   RESOLUTION IS NEVER AUTOMATIC. There is no sweep, no timer and no netting
--   that moves an obligation out of `outstanding`. Only this verb does, and
--   only for a platform principal, and it writes kernel.admin_audit in the
--   same transaction.
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
begin
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
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
  update kernel.organization_obligation
     set status = p_resolution,
         resolution_reason_code = coalesce(p_reason_code, p_resolution),
         resolved_by = auth.uid(), resolved_at = now(), updated_at = now()
   where obligation_id = p_obligation_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (auth.uid(), 'org_obligation.resolve', 'org_obligation', p_obligation_id,
          coalesce(p_reason_code, p_resolution),
          jsonb_build_object('status','outstanding'), jsonb_build_object('status', p_resolution));
  -- NOTE, deliberately: this verb moves NO money. `recovered` records that an
  -- off-platform payment happened; it does not collect one, does not credit a
  -- settlement, and does not release, unhold or advance any payout of any
  -- cause whatsoever. (The word for the commission payee is deliberately absent
  -- from every 094 verb BODY so that "no verb here can even name one" is a
  -- CHECKABLE property rather than a claim — pgTAP 160/F5 greps for it.)
  return jsonb_build_object('status','ok','obligation_id', p_obligation_id, 'status_now', p_resolution);
end;
$$;

-- ============================================================================
-- SECTION J7-3b — the PROJECTION (J3 §6.1). NOT A GATE.
--   kernel.org_outstanding_obligation_minor(p_org_id) — the cheap, unambiguous
--   answer to "does this organization have outstanding exposure, and how much",
--   computed in BIGINT (the aggregate discipline: settlement_line_candidate.
--   amount_minor bigint, close_settlement v_gross bigint — 087:29, 093:645) and
--   served EXACTLY by organization_obligation_outstanding_idx above. `> 0` is
--   the boolean form of the same read.
--
--   WHY THIS IS A PROJECTION AND NOT A HOLD PREDICATE — stated so the
--   attestation stays literally true. This function READS. It is called by
--   NOTHING in this file, it is not an operand of close_settlement's mint, of
--   kernel.settlement_payout_maturity, of kernel.request_org_payout or of
--   kernel.get_payout_execution_context, and adding it to any of them is J3's
--   Q5 ("should an outstanding org obligation HOLD that org's payouts?") — an
--   OWNER decision, deliberately not designed here, and one that would live in
--   the payout object, not in this one. Exposing a readable balance is not the
--   same act as gating money on it, and this file performs only the first.
--
--   It exists because "the guard counts LINES WRITTEN, not OBLIGATIONS
--   DISCHARGED" is a real defect on the payout rail: an operator who books a
--   post-close debit CORRECTLY drives a stale-exposure operand to zero and
--   turns a transfer gate green for revenue that was entirely refunded. An
--   `outstanding` row here is the durable meaning of "not recovered" that such
--   a guard needs. Whether it consumes it is not this file's decision.
-- ============================================================================
create or replace function kernel.org_outstanding_obligation_minor(p_org_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(o.amount_minor)::bigint, 0::bigint)
    from kernel.organization_obligation o
   where o.org_id = p_org_id and o.status = 'outstanding';
$$;

-- ============================================================================
-- SECTION J7-4 — kernel.close_settlement: THE SHORTFALL BRANCH (J3 §5.3)
--
--   THE BODY BELOW IS 093:640-854 VERBATIM except for ONE addition: the
--   `elsif v_net < 0 then` branch appended to the existing `if v_net > 0`
--   block. Nothing in the mint, the G2 maturity gate, the hold-reason vector,
--   the audit row or the return value is altered by a byte. Diffable: strip
--   this file's added branch and the two texts are identical.
--
--   WHY THE WRITE LIVES HERE AND NOT IN A SWEEP. J3 §5.3, routed by the
--   coordinator as Q10 = yes. `settlement_shortfall`'s natural writer is
--   close_settlement itself: one INSERT in a branch that today has NO
--   STATEMENTS, deterministic, impossible to forget. The alternative — a
--   separate platform-invoked RPC that books shortfalls from already-closed
--   headers — touches nothing and is idempotent on the same key, but it CAN BE
--   NOT RUN, and a debt record that depends on someone remembering to run a
--   sweep reproduces the exact failure mode it exists to fix. (That RPC is
--   still built, in J7-2, because the dormant-org and backfill cases need it;
--   it is simply not the primary path.)
--
--   R7's money-single-path reading is unaffected: close_settlement already
--   writes venue.settlement_line and kernel.payout, and this new table has no
--   other writer.
--
--   THE BRANCH MOVES NO MONEY. It mints no payout, releases no hold, writes no
--   settlement_line, and pays no promoter. It records that the close could not
--   net a residue which, before this file, was destroyed silently.
-- ============================================================================
create or replace function kernel.close_settlement(p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_s venue.settlement%rowtype; v_c kernel.settlement_line_candidate;
  v_gross bigint; v_fees bigint; v_refunds bigint; v_net bigint;
  v_payout_id uuid; v_ids uuid[] := '{}';
  -- G2 payout-maturity operands. THE CONJUNCTION ITSELF NOW LIVES IN
  -- kernel.settlement_payout_maturity (10m) and is called from THREE sites: here
  -- at the mint, in kernel.request_org_payout immediately before the
  -- pending→submitted advance (10k), and in kernel.get_payout_execution_context
  -- immediately before the transfer (10n). It was extracted (D-1) for exactly
  -- one reason: inline, it was a CLOSE-TIME SNAPSHOT that four later state
  -- changes defeat — a refund reaching 'succeeded' after the close;
  -- catalog.cancel_event, which touches kernel.payout NOWHERE; a dispute first
  -- observed already 'lost' (record_dispute_native freezes only on an OPEN
  -- dispute, 088:804, so the freeze is inverted relative to risk); and Connect
  -- capability loss. request_org_payout re-derived NONE of the eight predicates.
  -- One definition, three call sites, so the evaluations cannot drift. The
  -- operands themselves, and their fail-toward-the-hold initialisation, moved
  -- wholesale into 10m — nothing about the gate's meaning changed here.
  v_held boolean := false; v_hold_reason text; v_hold_detail jsonb;
  v_maturity_verdict jsonb;
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
  -- generate the money lines from the THREE seams: primary revenue (093/10b),
  -- royalty + chargeback (088:319), promoter commission (090:1511).
  for v_c in select * from kernel.settlement_primary_lines(p_settlement_id)
             union all select * from kernel.settlement_royalty_lines(p_settlement_id)
             union all select * from kernel.settlement_commission_lines(p_settlement_id) loop
    if v_c.cause is not null then
      if v_c.currency is not null and v_c.currency <> v_s.currency then
        raise exception 'precondition_failed: candidate currency % differs from the settlement currency %', v_c.currency, v_s.currency
          using errcode = 'P0001';
      end if;
      insert into venue.settlement_line (settlement_id, cause, cause_ref, amount_minor, currency)
      values (p_settlement_id, v_c.cause, v_c.cause_ref, v_c.amount_minor::integer, v_s.currency)
      -- NAMED, never bare: this tolerates ONLY a replay of this settlement's own
      -- line. A cross-settlement duplicate (10c) raises and aborts the close.
      on conflict on constraint settlement_line_cause_uq do nothing;
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
  -- (3) INT4 CEILING, NAMED INSTEAD OF OPAQUE. The four money columns are integer
  -- (087:52-55, frozen) while these locals are bigint, so a settlement whose gross
  -- exceeds 2^31-1 minor units (~$21.47M) raised a bare 22003 out of the UPDATE
  -- below. That rolled the whole close back, leaving the header `open` with zero
  -- lines and EVERY retry failing identically — a permanently wedged settlement
  -- whose error names nothing. Refuse first, with the remedy in the message. This
  -- is 090:1471-1473's rule ("never an opaque 22003 out of the close") applied to
  -- the header. The ceiling itself is structural — widening the columns is DDL on
  -- a frozen money table and an owner item, NOT 093.
  if v_gross > 2147483647 or v_fees > 2147483647 or v_refunds > 2147483647
     or v_net > 2147483647 or v_net < -2147483648 then
    raise exception 'precondition_failed: settlement_amount_overflow — gross %, fees %, refunds %, net % exceed the int4 money columns (schema §3.13); settle this scope as narrower periods, or widen the columns (owner item)',
      v_gross, v_fees, v_refunds, v_net using errcode = 'P0001';
  end if;
  update venue.settlement
     set status='closed', gross_minor=v_gross::integer, fees_minor=v_fees::integer,
         refunds_minor=v_refunds::integer, net_minor=v_net::integer, updated_at=now()
   where settlement_id = p_settlement_id;
  -- generate the pending payout only when there is positive net (kernel.payout
  -- amount_minor > 0). Deterministic idempotency on (cause, cause_ref, payee).
  if v_net > 0 then
    -- (2) THE PAYOUT-MATURITY GATE (G2 — docs/phase2/_impl/G2_settlement_maturity.md).
    -- A refund that succeeds AFTER this close cannot be collected: its debit lands
    -- in a settlement nobody opens, or in one that nets negative — and a negative
    -- net mints no payout and creates no receivable, because this schema has no
    -- carry-forward object. The payout is therefore MINTED (so the obligation is a
    -- durable ledger fact — ruling A3: the debt must be knowable without
    -- reconstructing it from Stripe) but minted HELD unless EVERY predicate below
    -- is satisfied, so no money can move on a partial proof.
    --
    -- ── WHAT THIS REPLACES, AND WHY ──────────────────────────────────────────
    -- The first cut of this gate was `v_held := v_refund_window is null` — the
    -- ONLY predicate was "is the config key set". Setting the key to any value
    -- released every payout immediately, with no maturity semantics implemented
    -- anywhere: an owner config value was a hidden feature flag for logic that did
    -- not exist, and the slice's own comment had to warn that SETTING the key was
    -- the dangerous act. That is inverted here. The key is now ONE CONJUNCT of a
    -- gate that also has to prove the event happened, that it happened long enough
    -- ago, and that no money is still in motion against the orders being paid for.
    --
    -- ── THE PREDICATES, ALL OF WHICH MUST HOLD TO RELEASE ────────────────────
    --   1. the maturity policy VALUE is set and non-negative;
    --   2. every money line in this settlement resolves to its payment AND its
    --      session — we must know what this money is about before we can time it;
    --   3. no covered session and no covered event is cancelled;
    --   4. the maturity INSTANT is known: at least one covered session, and every
    --      covered session carries ends_at;
    --   5. that instant plus the policy interval has ELAPSED;
    --   6. no refund against any covered payment is in a non-terminal state;
    --   7. no dispute against any covered payment is open.
    -- Any single failure holds, with its own hold_reason_code. An operand that
    -- cannot be computed is NOT assumed satisfied: all seven locals are declared
    -- pre-set to the value that holds.
    --
    -- ── WHY ends_at OF THE LAST COVERED SESSION IS THE ANCHOR ────────────────
    -- The buyer's own chargeback clock starts THERE, not at payment: Stripe states
    -- it in terms of this exact industry — "when a customer pays for a future
    -- event or service (like a vacation reservation, professional services
    -- appointment, or event ticket), the dispute window starts on the event date,
    -- not the payment date" (https://docs.stripe.com/disputes/how-disputes-work).
    -- Anchoring on payment would make a ticket bought three months early payable
    -- three months before anyone could attend. catalog.event carries NO time
    -- column at all (078:134-154) — the only instants in the schema are on
    -- catalog.event_session — and venue."order".event_session_id is NOT NULL
    -- (082:369-372), so every covered order resolves to exactly one session. That
    -- makes the anchor computable for BOTH settlement grains: event-scoped and
    -- period-scoped headers alike derive it from their OWN LINES rather than from
    -- the header's scope, so a period settlement is timed by the last session it
    -- actually paid for and not by period_end (which is nullable, bounds
    -- starts_at rather than ends_at, and can be open-ended).
    --
    -- ends_at IS NULLABLE (078:170) and catalog.create_event_session requires only
    -- starts_at (078:805-807). The corpus's ticket-expiry sweep meets the same
    -- fact and FAILS OPEN — it skips such sessions (079:490-492), which slice 40
    -- already records as an unfixed schema hole. This gate fails CLOSED on it: a
    -- session with no end has not verifiably ended, so its money does not mature.
    -- Session STATUS is deliberately not used: nothing in 076-092 ever writes
    -- event_session.status = 'completed' (the only writer of that column is
    -- 088:1793, which writes 'cancelled'), so requiring it would hold every payout
    -- forever.
    --
    -- WHY HELD RATHER THAN REFUSING THE CLOSE OR MINTING NOTHING. Refusing the
    -- close would also refuse the LINES, so the ledger would never record what the
    -- venue is owed — the opposite of A3. Minting nothing would strand the payout
    -- permanently, because close_settlement is the only minter of a
    -- cause='settlement' payout and it is forward-only (a re-close returns
    -- noop_replay above), so no later run could ever create it. The hold overlay
    -- is the corpus's own answer to exactly this shape: 090:1487-1491 mints an
    -- unfunded promoter commission 'held'/'unfunded_settlement' for the same
    -- reason. A held payout cannot be requested (087:463-465 refuses
    -- hold_state <> 'none') and cannot be advanced by
    -- kernel.mark_payout_transfer_state; kernel.release_payout (085:807,
    -- platform_risk/platform_admin, Control-5) is the contracted release path once
    -- the owner rules. The hold is therefore recoverable; an overpayment is not.
    --
    -- ── THE KEY WAS RENAMED, BECAUSE THE OLD NAME WAS A LIE ──────────────────
    -- 'settlement.refund_window_interval' named a REFUND ELIGIBILITY window — how
    -- long a buyer may still ask for money back. That policy exists, it is owned
    -- by an entirely different set of keys (refund.buyer_self_service_window_hours
    -- / refund.request_ttl_hours / refund.scanned_atom_policy, 078:1544-1551), and
    -- this value is not it. What this value actually is: HOW LONG AFTER THE EVENT
    -- THE VENUE'S MONEY MUST SIT STILL. It is a payout property, so it is spelled
    -- 'payout.settlement_maturity_interval' — and that prefix is load-bearing, not
    -- cosmetic: 078:1145-1147 puts every 'payout.%' key under DUAL CONTROL, and
    -- the key carries no declared polarity, so EVERY set of it parks for a second
    -- platform_admin (078:1268-1285). Slice 40's own caveat on the old name was
    -- that "there is no second human in the way"; under the new name there is.
    --
    -- READ AS THE HOUSE PATTERN: absent row, JSON null and unparseable value all
    -- collapse to NULL and therefore to the hold (the 081:630-639 idiom).
    -- ONE CALL, AND THE OPERANDS ARE NO LONGER RE-DERIVED HERE. Everything the
    -- commentary above describes — the config read with its absent / JSON-null /
    -- unparseable collapse to NULL, the covered set derived from THIS
    -- settlement's own lines, the causal predicate order, the
    -- first-failing-predicate-wins rule and the full detail vector — is now
    -- kernel.settlement_payout_maturity (10m), verbatim. It never raises (a
    -- raise here would roll back the whole close and the ledger would never
    -- record what the venue is owed) and it fails toward the hold on every
    -- missing operand, exactly as this block did.
    v_maturity_verdict := kernel.settlement_payout_maturity(p_settlement_id);
    v_hold_reason := v_maturity_verdict ->> 'hold_reason';
    v_held        := v_hold_reason is not null;
    v_hold_detail := coalesce(v_maturity_verdict -> 'detail', '{}'::jsonb);
    insert into kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, currency, status, idempotency_key,
                               hold_state, hold_reason_code, held_by, held_at)
    values ('organization', v_s.org_id, 'settlement', p_settlement_id, v_net::integer, v_s.currency, 'pending',
            'settlement:' || p_settlement_id::text,
            case when v_held then 'held' else 'none' end,
            v_hold_reason,
            null,
            case when v_held then now() else null end)
    on conflict (idempotency_key) do nothing
    returning payout_id into v_payout_id;
    if v_payout_id is not null then v_ids := array[v_payout_id]; end if;
  -- ── 094 / J7 — THE SHORTFALL RECORD (the ONLY delta from the 093 text) ────
  -- 093's own header states the defect this closes in the author's words:
  -- "A negative net is NOT a receivable: this schema has no carry-forward
  -- object" (093:376). It does now. The residue that the waterfall proved, that
  -- minted nothing because kernel.payout CHECK (amount_minor > 0) makes a
  -- negative instruction unstorable, and that was then destroyed, becomes a
  -- first-class durable fact keyed to the settlement that produced it.
  --
  -- v_net = 0 books NOTHING: there is no shortfall, and amount_minor CHECK > 0
  -- would refuse a zero anyway. Only v_net < 0 reaches the record.
  elsif v_net < 0 then
    -- The int4 floor, named rather than opaque — 090:1471-1473's rule ("never
    -- an opaque 22003 out of the close") applied to the magnitude. The guard
    -- above admits v_net = -2147483648 exactly; its magnitude 2147483648 does
    -- NOT fit kernel.organization_obligation.amount_minor integer. Refuse with
    -- the remedy in the message rather than raise a bare numeric overflow.
    if -v_net > 2147483647 then
      raise exception 'precondition_failed: settlement_shortfall_overflow — a shortfall of % minor units exceeds the int4 obligation magnitude; settle this scope as narrower periods (owner item)', -v_net
        using errcode = 'P0001';
    end if;
    -- Definer→definer, so the record has ONE writer and every row carries its
    -- kernel.admin_audit act. The verb re-derives the magnitude from the header
    -- this function has already written, so the close cannot book an amount the
    -- ledger does not prove. It CANNOT raise on this path: the header is closed,
    -- belongs to v_s.org_id, nets negative, and the amount and currency are read
    -- back from it. On a re-close the header is not `open` and this function has
    -- already returned noop_replay above; on any other replay the origin UNIQUE
    -- makes the verb a no-op.
    perform kernel.record_organization_obligation(
      v_s.org_id, 'settlement_shortfall', p_settlement_id, null,
      (-v_net)::integer, v_s.currency, 'settlement_shortfall',
      coalesce(p_command_key, 'close') || ':shortfall');
  end if;
  -- the audit row gains `after` — ADDITIVE, and the only durable place an operator
  -- can read the WHOLE predicate vector rather than the one code that won.
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (auth.uid(), 'settlement.close', 'settlement', p_settlement_id, coalesce(p_command_key,'close'),
          jsonb_build_object('payout_hold', v_hold_reason, 'hold_predicates', v_hold_detail));
  -- net_minor is a READ-BACK of the column this function wrote (§10.2 R1-2), never a local.
  -- 'payout_hold' is ADDITIVE — every contracted key (status, payout_ids,
  -- net_minor) keeps its meaning; callers that do not read it are unaffected.
  -- 'payout_hold_detail' is additive in the same way and is NULL when nothing held.
  return jsonb_build_object('status','ok','payout_ids', v_ids,
           'net_minor', (select net_minor from venue.settlement where settlement_id = p_settlement_id),
           'payout_hold', v_hold_reason,
           'payout_hold_detail', case when v_held then v_hold_detail else null end);
end;
$$;

-- ============================================================================
-- SECTION J7-5 — GRANTS (E-150; the 085 PART 14 discipline)
--   THE PAIR IS service_role ONLY. No client principal can name an obligation,
--   record one, resolve one or read the projection — and no role at all holds a
--   privilege on the TABLE (J7-1's REVOKE ALL), so the definer path is the only
--   way in, by construction rather than by policy.
--
--   The trigger guard is granted to NOBODY: it is reachable only as a trigger.
--
--   kernel.close_settlement's ACL is NOT touched. `create or replace function`
--   preserves the existing ACL, so 087 PART 8's classification (v_all revoke +
--   v_auth grant to `authenticated`, the caller-authorized class whose
--   authority gate lives in the body) survives J7-4 unchanged. Re-asserting it
--   here would be a second source of truth for a frozen grant; a pgTAP
--   assertion pins it instead.
-- ============================================================================
do $$
declare
  v_fn text;
  v_defs constant text[] := array[
    'kernel.organization_obligation_guard()',
    'kernel.record_organization_obligation(uuid, text, uuid, text, integer, text, text, text)',
    'kernel.resolve_organization_obligation(uuid, text, text, text)',
    'kernel.org_outstanding_obligation_minor(uuid)'
  ];
  v_svc constant text[] := array[
    'kernel.record_organization_obligation(uuid, text, uuid, text, integer, text, text, text)',
    'kernel.resolve_organization_obligation(uuid, text, text, text)',
    'kernel.org_outstanding_obligation_minor(uuid)'
  ];
begin
  foreach v_fn in array v_defs loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
  end loop;
  foreach v_fn in array v_svc loop
    execute format('grant execute on function %s to service_role', v_fn);
  end loop;
  -- The guard is trigger-only: service_role must not be able to call it either.
  execute 'revoke all on function kernel.organization_obligation_guard() from service_role';
end $$;

commit;
