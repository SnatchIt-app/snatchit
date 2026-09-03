-- ============================================================================
-- 093 PART 30 — STRIPE CONNECT / ORGANIZATION slice.
--
-- FRAGMENT, not a migration. No `begin;`/`commit;` here — the assembled 093
-- owns the transaction. 076-092 are IMMUTABLE: this part only ADDs columns and
-- CREATE-OR-REPLACEs function bodies. No new table, no new enum member, no
-- policy, no grant change to an existing verb (create-or-replace preserves the
-- ACL — the two replaced verbs keep their frozen `authenticated` grants, which
-- is precisely why every control below has to live in SQL).
--
-- OWNER RULINGS IMPLEMENTED (PRIMARY_TICKETING_OWNER_RATIFICATION.md):
--   §1  two mirror columns on kernel.organization ......... A6  (scope item 5)
--   §2  kernel.sync_org_connect_state, service_role only .. A6  (scope item 6)
--   §2b kernel.stage_org_connect_ref, service_role only ... A7/A9 (RT-A-3)
--   §3  checkout readiness gates, UNCONDITIONAL ........... A8  (scope item 7)
--         G2  connect readiness — can the VENUE be paid?
--         G2b signing-key readiness — can the BUYER be delivered to?
--       + the buyer-side service fee, fail-closed ......... A5  (part 40's
--         `fee.buyer_service_bps`, whose only possible reader this is)
--   §4  kernel.set_org_connect_ref — hardened ............. A7/A9 (item 8)
--   §5  kernel.set_org_payout_destination — hardened ...... A7/A9 (item 9)
--   §6  kernel.get_org_connect_state — read, HUMANS ........ A7  (F §3.5 G5)
--   §7  kernel.get_org_connect_ref — read, MACHINES ........ A7  (F §3.4)
--   §8  kernel.issue_ticket_atoms — resolve, not accept .... T1  (binds G2b)
--
-- §6 and §7 are the two objects here that are NOT in the 093 scope list. Both
-- were added because the onboarding edge cannot function without them: the
-- column they read is unreachable by BOTH candidate roles (`authenticated` is
-- revoked at 077:133-138; service_role holds kernel USAGE only, 085:2092-2095).
-- They are a DELIBERATE PAIR SPLIT ON THE TRUST BOUNDARY — §6 is granted to
-- `authenticated` and returns last4; §7 is granted to service_role and returns
-- the full identifier. Rulings F §3.5 (G5) and F §3.4 prescribe both; neither
-- was ever authored. DO NOT MERGE THEM.
--
-- Supporting rulings: docs/phase2/_rulings/F_org_onboarding.md §3.3/§3.5/§3.6
-- (what may be mirrored, and where the gates go) and
-- docs/phase2/_rulings/G_onboarding_security.md §2 (threats G-1/G-2/G-4/G-6),
-- §5.1 (attach vs replace) and §6.1/§6.2 (audit + notification wiring).
--
-- ORDERING: §1, §2 and §3 are ONE UNIT. §3 reads a column created by §1 and
-- written only by §2. Applied apart, the buyer-facing checkout raises an
-- undefined-column error instead of cleanly refusing the sale.
-- ============================================================================


-- ============================================================================
-- §1 — kernel.organization: the Connect state mirror. EXACTLY TWO COLUMNS.
--   Ruling A6 · F §3.3 · 093 scope item 5.
--
-- OWNER CONSTRAINT, VERBATIM: "Do NOT copy Stripe's entire account object into
-- Postgres." Stripe stays authoritative for verification state. Postgres holds
-- only what a SQL gate must evaluate with no network call — which is one
-- boolean — plus the freshness stamp that says whether that boolean can still
-- be believed.
--
-- WHY ONLY TWO. Four further candidates were CUT because no reader exists in
-- the ruled design, and a column with no reader sits at its default forever:
--   · payouts_enabled          — F §3.5 rules it explicitly NOT a sale gate
--                                (transfers active + payouts disabled still
--                                sells and still receives transfers), so no
--                                SQL predicate reads it. Dashboard-only.
--   · requirements.disabled_reason  — support triage copy. No predicate.
--   · requirements.current_deadline — warning copy. No predicate.
--   · requirements-due flag         — banner copy. No predicate; F §3.6(2)
--                                     rules that requirements due must warn
--                                     and gate NOTHING.
-- Two of them would also duplicate columns already carried on the individual
-- plane (public.profiles.stripe_payouts_enabled / stripe_connect_status).
-- They become justified when an operator console exists to render them; until
-- then they are exactly the `stripe_charges_enabled` failure — a column
-- written by nothing, read by nothing, believed by everyone.
--
-- CLIENT VISIBILITY: kernel.organization carries a COLUMN-SCOPED grant
-- (077:120-123 — authenticated may SELECT only org_id/display_name/status).
-- A column added to a table with column-level grants inherits NO grant, so
-- both columns below are unreadable by `authenticated` by construction. That
-- is intended: the gate reads them inside SECURITY DEFINER functions, and the
-- dashboard reads them through a scoped RPC, never through PostgREST.
-- ============================================================================

-- The product gate operand. `capabilities.transfers = 'active'` is the ONLY
-- readiness predicate this money model needs, and the shipped payout probe
-- already uses exactly it (supabase/functions/_shared/payouts.ts:96-98) — this
-- mirrors that predicate rather than inventing a second one.
--
-- NON-MONOTONIC, DELIBERATELY — DO NOT "FIX" THIS INTO A RATCHET.
-- public.profiles.stripe_onboarding_complete is monotonic on purpose
-- (supabase/functions/create-connect-account/index.ts:281 only ever sets it
-- true), because flipping an individual seller's flag false on one transient
-- read would bar an onboarded seller from listing. The organization flag is
-- the OPPOSITE by requirement: when Stripe disables an account, `transfers`
-- leaves 'active' and the organization MUST stop selling. A monotonic mirror
-- here means an account Stripe has disabled stays sellable forever, with the
-- platform as merchant of record and no destination to settle to. §2 is the
-- only writer and it writes both directions.
alter table kernel.organization
  add column if not exists connect_transfers_active boolean not null default false;

-- Freshness, not truth. A row whose stamp is old renders "checking…" and
-- triggers a re-read rather than asserting a stale green. It is also the
-- out-of-order guard in §2: a webhook redelivery carrying an OLDER observation
-- cannot overwrite a newer one.
alter table kernel.organization
  add column if not exists connect_state_synced_at timestamptz;

-- THE THIRD COLUMN — added under protest against the two-column target, and
-- the reason is worth stating plainly because it overrides §1's own rule.
--
-- RT-A-3: the red team bound `acct_ORPHANATTACKER` as `authenticated`, on both
-- the first bind AND a re-point of a LIVE destination. It is present in neither
-- public.profiles.stripe_connect_id nor public.stripe_connect_archive, so the
-- cross-plane refusal below never fired. That refusal is a BLOCKLIST of known
-- individual-plane accounts, and a blocklist cannot satisfy ruling A7's
-- absolute form: "A caller must never be permitted to supply or bind an
-- arbitrary acct_ identifier." An attacker's own freshly created Stripe
-- account is in no list anyone can enumerate.
--
-- The "server mints, caller never names" property was real but ADVISORY: it
-- lived in the onboarding edge, and both binders are granted to `authenticated`
-- and reachable through PostgREST in one call. An attacker simply does not use
-- the edge.
--
-- This column converts that property from advisory to STRUCTURAL. It is the
-- platform's own record of the account IT minted for THIS organization, written
-- only by kernel.stage_org_connect_ref (§2b, service_role only). §4 and §5 then
-- require the caller-supplied identifier to EQUAL it. The caller still passes a
-- value — CREATE OR REPLACE cannot drop a parameter — but can no longer pass a
-- value the platform did not mint for that org. Provenance, not enumeration.
--
-- It is deliberately NOT part of the §1 Stripe mirror: it mirrors nothing from
-- Stripe. It is a Snatch It fact, like payout_destination_set_by. It carries no
-- client grant (a column added to a table with column-scoped grants inherits
-- none), and no read verb in this slice returns it.
alter table kernel.organization
  add column if not exists connect_pending_ref text;


-- ============================================================================
-- §2 — kernel.sync_org_connect_state: the service_role-only sync writer.
--   Ruling A6 · F §3.3 ("Writer") · 093 scope item 6.
--
-- WHY IT EXISTS AT ALL: service_role holds USAGE ONLY on the kernel schema
-- (085:2092-2095, PFA-21) — no table DML grant — so the account.updated
-- webhook physically CANNOT `update kernel.organization`. A definer function
-- is the only door, and this is it.
--
-- WHY NOT set_org_connect_ref: that verb RAISES when auth.uid() is NULL
-- (077:962-966, T-RPC-CONNECT-04) because it must stamp the SoD-1 operand with
-- a real human. A webhook has no human. The two are different acts.
--
-- SHAPE: modelled on kernel.mark_payout_transfer_state (085:1668) — DEF,
-- service_role EXEC only, NO HUMAN PATH AND NONE MAY EVER BE ADDED. Same
-- five-argument shape: subject, the fact(s), and the command/idempotency key.
--
-- SIGNATURE, derived from how the webhook actually calls it (F §3.6(1)): the
-- handler matches kernel.organization.stripe_connect_account_ref = account.id
-- and FALLS BACK to metadata.org_id, so both selectors are accepted and at
-- least one is required. The ref wins when both are supplied.
-- ============================================================================
create or replace function kernel.sync_org_connect_state(
  p_org_id uuid, p_connect_account_ref text, p_transfers_active boolean,
  p_observed_at timestamptz, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org      kernel.organization%rowtype;
  v_observed timestamptz;
begin
  if p_transfers_active is null then
    raise exception 'invalid_input: transfers_active is the fact being synced and may not be null';
  end if;
  -- RT-A-5: A NULL REF IS NOT A WILDCARD. The first draft made the cross-org
  -- guard below conditional on `p_connect_account_ref is not null`, so a caller
  -- holding only service_role could omit the ref entirely and write capability
  -- state onto ANY organization by id — the red team set
  -- connect_transfers_active = true on an unbound org that way. That widened a
  -- leaked-key blast radius onto the org plane, which ruling G (threat G-12)
  -- asserts is closed precisely because no kernel table DML grant exists. The
  -- ref is now MANDATORY and is always compared.
  if p_connect_account_ref is null then
    raise exception 'invalid_input: connect_account_ref is required — a null ref must never be read as "match any organization" (RT-A-5)';
  end if;
  if p_connect_account_ref !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: malformed_account_ref';
  end if;
  -- The observation instant is the webhook's RETRIEVE time, not now(): Stripe
  -- redelivers, and a redelivery must not be able to present itself as fresher
  -- than a later observation already recorded. A caller that has no instant
  -- passes null and gets now().
  v_observed := coalesce(p_observed_at, now());

  -- Resolve by the bound ref first (the webhook's primary join), then by the
  -- metadata org id (its documented fallback). The fallback survives only to
  -- produce the precise refusal below instead of a bare not_found.
  select * into v_org from kernel.organization o
    where o.stripe_connect_account_ref = p_connect_account_ref for update;
  if v_org.org_id is null and p_org_id is not null then
    select * into v_org from kernel.organization o
      where o.org_id = p_org_id for update;
  end if;
  if v_org.org_id is null then
    raise exception 'not_found: organization for %', coalesce(p_connect_account_ref, p_org_id::text)
      using errcode = 'P0002';
  end if;

  -- RT-A-5: AN UNBOUND ORGANIZATION MAY NOT RECEIVE CAPABILITY STATE AT ALL.
  -- Until §4 binds a destination the org is not the payee of anything, so a
  -- `transfers active` fact about it has nowhere legitimate to live — and
  -- writing one would arm the §3 checkout gate for an organization with no
  -- destination to settle to. An account.updated that arrives for a minted-but-
  -- never-bound account is refused here and lands again after the bind.
  if v_org.stripe_connect_account_ref is null then
    raise exception 'precondition_failed: org_not_bound — capability state may not be written for an organization with no bound payout destination';
  end if;

  -- G-4 / A9 (stale onboarding callback binding): an account.updated for an
  -- account that is NOT this organization's currently bound destination must
  -- never write its state. A rebind that raced the event, or an event for a
  -- superseded account, is refused — never silently applied to the live row.
  -- UNCONDITIONAL NOW: see the RT-A-5 note on the mandatory ref above.
  if v_org.stripe_connect_account_ref is distinct from p_connect_account_ref then
    raise exception 'conflict_locked: % is not the bound destination of org %',
      p_connect_account_ref, v_org.org_id;
  end if;

  -- Out-of-order redelivery: an observation no newer than the one already
  -- recorded changes nothing. Never a raise — a raising webhook is retried
  -- forever (the 082 cancel_pending_order lesson).
  if v_org.connect_state_synced_at is not null
     and v_observed <= v_org.connect_state_synced_at then
    return jsonb_build_object('status','noop_replay','org_id', v_org.org_id,
                              'connect_transfers_active', v_org.connect_transfers_active,
                              'connect_state_synced_at', v_org.connect_state_synced_at);
  end if;

  -- HEARTBEAT vs TRANSITION. Both writes stamp freshness; only a transition is
  -- an auditable fact. F §3.3's refresh discipline gives this verb two callers
  -- — the webhook AND every dashboard status read — so auditing an unchanged
  -- poll would bury the capability losses that matter under heartbeat noise.
  if v_org.connect_transfers_active = p_transfers_active then
    update kernel.organization
       set connect_state_synced_at = v_observed
     where org_id = v_org.org_id;
    return jsonb_build_object('status','noop_replay','org_id', v_org.org_id,
                              'connect_transfers_active', p_transfers_active,
                              'connect_state_synced_at', v_observed);
  end if;

  update kernel.organization
     set connect_transfers_active = p_transfers_active,
         connect_state_synced_at  = v_observed
   where org_id = v_org.org_id;

  -- G §6.1: `org.connect_ref.capability_lost` is the named audit action for the
  -- org account.updated branch; its twin records the recovery. Actor is the
  -- SN-SYSTEM sentinel (078 §1.16, uuid ...f1) — the same coalesce idiom
  -- mark_payout_transfer_state uses (085:1724) — because a webhook has no human
  -- and admin_audit.actor_identity is NOT NULL.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'),
          case when p_transfers_active then 'org.connect_ref.capability_gained'
                                       else 'org.connect_ref.capability_lost' end,
          'organization', v_org.org_id,
          case when p_transfers_active then 'transfers_active' else 'transfers_inactive' end,
          jsonb_build_object('connect_transfers_active', v_org.connect_transfers_active,
                             'connect_state_synced_at', v_org.connect_state_synced_at),
          jsonb_build_object('connect_transfers_active', p_transfers_active,
                             'connect_state_synced_at', v_observed));

  return jsonb_build_object('status','ok','org_id', v_org.org_id,
                            'connect_transfers_active', p_transfers_active,
                            'connect_state_synced_at', v_observed);
end;
$$;

-- 076 grant discipline: the default PUBLIC EXECUTE is revoked explicitly, then
-- ONE targeted grant. service_role ONLY — never `authenticated`, never anon.
-- This verb asserts Stripe's own state; a human principal that could call it
-- could declare itself ready to sell and walk straight through §3. There is no
-- human path here and none may ever be added (R-31, the mark_* pair's rule).
revoke all on function kernel.sync_org_connect_state(uuid, text, boolean, timestamptz, text)
  from public, anon, authenticated;
grant execute on function kernel.sync_org_connect_state(uuid, text, boolean, timestamptz, text)
  to service_role;


-- ============================================================================
-- §2b — kernel.stage_org_connect_ref: the PROVENANCE WRITER.
--   Ruling A7 ("The server creates/resolves the connected account. A caller
--   must never be permitted to supply or bind an arbitrary acct_ identifier")
--   and A9 (personal-account injection; caller-supplied acct_ replacement).
--   Closes RT-A-3.
--
-- WHAT IT IS: the platform's record that IT minted this account for THIS
-- organization. The onboarding edge calls it immediately after Stripe returns
-- the account, BEFORE sending the human to §4. §4 and §5 then refuse any
-- identifier that does not equal what is staged here.
--
-- WHY A VERB AND NOT A DIRECT WRITE: service_role holds USAGE ONLY on the
-- kernel schema (085:2092-2095, PFA-21), so the edge cannot UPDATE
-- kernel.organization. Same reason §2 exists, same treatment.
--
-- WHY `authenticated` CAN NEVER REACH IT: if a browser session could stage a
-- ref, it could stage its own account and then bind it, and the provenance
-- requirement would be theatre — the attacker would simply write the answer
-- before taking the test. THE ENTIRE VALUE OF RT-A-3's FIX IS THIS GRANT.
--
-- THE TWO-KEY PROPERTY THIS CREATES, stated so it is not weakened by accident:
-- staging needs service_role (a machine credential); binding needs a human
-- org_owner with an aal2 session and REFUSES a service_role connection
-- outright (077:962-966). Neither credential alone can bind an account. A
-- leaked service_role key can stage a ref it likes and get no further; a
-- compromised org_owner can bind only what the platform already minted for
-- that org. That separation is the control — do not merge these two verbs, and
-- do not add a human path here.
--
-- NO ORG-STATUS GATE, DELIBERATELY. §4 already refuses to bind for an org that
-- is not approved/active, so a status gate here would add nothing except a way
-- to strand a freshly minted live Stripe account: the edge would have already
-- created it at Stripe and would then be unable to record it. The edge reads
-- org_status from §6 and refuses BEFORE minting; this verb is downstream of
-- that decision, and the authoritative refusal stays at the bind.
--
-- Staging is idempotent and overwrite-safe: re-staging the same ref is a
-- noop_replay, and staging a different one replaces the pending value. It
-- never touches stripe_connect_account_ref — only §4 and §5 write that.
-- ============================================================================
create or replace function kernel.stage_org_connect_ref(
  p_org_id uuid, p_connect_account_ref text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org kernel.organization%rowtype;
begin
  if p_org_id is null then
    raise exception 'invalid_input: org_id is required';
  end if;
  if p_connect_account_ref is null or p_connect_account_ref !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: malformed_account_ref';
  end if;

  -- Cross-plane refusal applies HERE TOO, and earliest of all: an individual
  -- seller's account must never even become stageable, so the refusal lands
  -- before a human is sent to Stripe rather than after (G-1).
  if exists (select 1 from public.profiles pf
              where pf.stripe_connect_id = p_connect_account_ref)
     or exists (select 1 from public.stripe_connect_archive ar
                 where ar.stripe_connect_id = p_connect_account_ref) then
    raise exception 'precondition_failed: account_not_platform_minted_for_org — this account belongs to the individual seller plane';
  end if;

  select * into v_org from kernel.organization where org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id using errcode = 'P0002';
  end if;

  -- One account per org across the whole platform (077:124-126 says so for the
  -- bound column; this says it for the pending one, so the collision surfaces
  -- at staging rather than as a unique_violation after Stripe has minted).
  if exists (select 1 from kernel.organization o
              where o.stripe_connect_account_ref = p_connect_account_ref
                and o.org_id <> p_org_id) then
    raise exception 'conflict_locked: connect account already bound to another org';
  end if;

  -- Already the org's LIVE destination: nothing to stage, and staging it would
  -- arm a pointless re-point. The §4 replay path already handles this caller.
  if v_org.stripe_connect_account_ref = p_connect_account_ref then
    return jsonb_build_object('status','noop_replay','org_id', p_org_id,
                              'already_bound', true);
  end if;
  if v_org.connect_pending_ref = p_connect_account_ref then
    return jsonb_build_object('status','noop_replay','org_id', p_org_id,
                              'already_bound', false);
  end if;

  update kernel.organization
     set connect_pending_ref = p_connect_account_ref
   where org_id = p_org_id;

  -- Auditable per A7 ("Initial onboarding and account replacement must be
  -- auditable") — and this is the row that proves WHEN the platform minted the
  -- account, which is the fact the bind's provenance check rests on. Actor is
  -- the SN-SYSTEM sentinel (078 §1.16): the mint has no human principal, and
  -- the human is recorded separately by §4/§5's own audit row.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'),
          'org.connect_ref.stage', 'organization', p_org_id, 'onboarding_mint',
          jsonb_build_object('pending_ref_last4',
                             case when v_org.connect_pending_ref is null then null
                                  else right(v_org.connect_pending_ref, 4) end),
          jsonb_build_object('pending_ref_last4', right(p_connect_account_ref, 4)));

  return jsonb_build_object('status','ok','org_id', p_org_id, 'staged', true);
end;
$$;

-- service_role ONLY, and this grant IS the control (see the header). The
-- `revoke ... from public` is load-bearing: CREATE FUNCTION grants EXECUTE to
-- PUBLIC by default and `authenticated` inherits PUBLIC, which would hand a
-- browser session the ability to stage its own account and defeat RT-A-3's fix
-- entirely.
revoke all on function kernel.stage_org_connect_ref(uuid, text, text)
  from public, anon, authenticated;
grant execute on function kernel.stage_org_connect_ref(uuid, text, text) to service_role;


-- ============================================================================
-- §3 — venue.create_primary_checkout: the checkout readiness gate.
--   Ruling A8 ("Checkout must fail closed if the venue organization is not
--   eligible for primary-sale collection") · F §3.5 gate G2 · scope item 7.
--
-- REPLACEMENT SCOPE: the ONLY change to this body is the payout-readiness
-- precondition marked A8/G2 below, placed beside the existing `not_on_sale`
-- check where v_org_id is already server-derived from the session's event.
-- Every other check, the hold/inventory coverage logic, the C16 idempotency
-- short-circuit and race handler, the single-price-snapshot rule, the insert
-- pair and the return shape are reproduced unchanged.
--
-- UNCONDITIONAL — THERE IS NO CONFIGURATION KEY FOR THIS GATE, DELIBERATELY.
-- F §3.5 proposed `venue.require_connect_for_on_sale`; the owner declined it
-- outright (093 scope, OUT). A configuration key whose only function is
-- switching off the gate that protects money is not minimality, it is a second
-- way to be wrong: a fail-open flip with no migration, no review and no audit
-- row. If this gate is ever wrong, the fix is code.
--
-- THERE IS NO EDGE-SIDE RE-CHECK, AND ONE MUST NOT BE RESTORED. F §3.5 gate G3
-- specified the primary-checkout edge re-asserting this predicate before
-- minting the PaymentIntent. THAT RE-CHECK HAS BEEN REMOVED, NOT RELOCATED,
-- and its removal is correct on two independent grounds:
--
--   1. IT WAS STRICTLY WEAKER THAN THIS ONE. The read below happens in the SAME
--      TRANSACTION as the price snapshot and the hold-coverage proof, under the
--      same row-visibility, so the readiness fact and the price the buyer is
--      quoted are decided against one consistent state. An edge re-read happens
--      moments later against a state that may have moved — it can only ever
--      disagree with a decision already taken, never improve on it. The
--      IN-TRANSACTION READ IS THE CONTROL.
--   2. IT WAS UNREACHABLE IN BOTH DIRECTIONS ANYWAY. kernel.get_org_connect_state
--      (§6) is granted to `authenticated` and deliberately never to
--      service_role, and its body demands org_owner/org_finance — which a BUYER
--      is not. There is no credential the checkout edge could present that
--      would let it ask, and the direct table reads it was attempting were
--      illegal for the same reason (076:76 grants `catalog` USAGE to anon and
--      authenticated only; 085:2088 gives service_role `venue` USAGE ONLY and
--      085:2092 gives it `kernel` USAGE ONLY, both saying so verbatim; no
--      migration grants service_role any table privilege in
--      venue/kernel/catalog/market).
--
-- SO DO NOT "FIX" A MISSING EDGE CHECK BY WIDENING A GRANT. Widening §6 to
-- service_role, or granting the edge SELECT on kernel.organization, buys a
-- strictly worse duplicate of the check below and hands the machine plane the
-- payout state of every organization. This function is granted to
-- `authenticated` and reachable through PostgREST in one call, so an edge-side
-- check would be bypassed by not using the edge in any case. The authoritative
-- gate is here and only here.
--
-- SELF-HEALING BY CONSTRUCTION: no sweep, no scheduled job, no backward event
-- transition. The moment Stripe disables the account, §2 writes false and the
-- next checkout attempt refuses; the moment it recovers, sales resume with no
-- operator action. F §3.6(4) forbids consuming the operator's forward-only
-- publish state machine on a transient Stripe state, and this gate is correct
-- precisely because it is reversible for free.
--
-- ---------------------------------------------------------------------------
-- SECOND CHANGE IN THIS BODY — THE BUYER-SIDE SERVICE FEE (ruling A5).
--
-- Part 40 of this migration mints `fee.buyer_service_bps` (restricted, seeded
-- null) and names its reader in advance: "The real reader is the buyer-side
-- pricing path — venue.create_primary_checkout and the primary-checkout edge",
-- which "must fail closed (refuse to price) rather than default to zero while
-- the value is null." THIS BODY IS THAT READER. Part 40 created the key ahead
-- of its reader deliberately; this closes the gap inside the same migration.
--
-- THE DEFECT THIS FIXES — MEASURED ON THE REHEARSAL DB, NOT ASSUMED. The
-- checkout edge can read the rate under NEITHER credential it could present:
--   · service_role — 076:76 grants `catalog` USAGE to `anon, authenticated`
--     ONLY. has_schema_privilege('service_role','catalog','USAGE') is FALSE.
--     The edge key cannot reach the schema at all, let alone the table.
--   · authenticated — 078:234 revokes the table and grants back a
--     column-scoped SELECT, then RLS splits it in two (AUTHZ-CFG1,
--     078:353-361): catalog_platform_config_sel_public exposes
--     visibility='public' rows, while a `restricted` row rides
--     catalog_platform_config_sel_restricted, which demands
--     is_platform(['platform_admin','platform_risk']). A BUYER IS NEITHER.
-- So setting the rate would NOT have been enough to activate primary selling:
-- the feature would have stayed dead with no obvious cause — the
-- `stripe_charges_enabled` failure mode in a new place.
--
-- WHY HERE AND NOWHERE ELSE — both alternatives are worse:
--   · Granting service_role USAGE on `catalog` widens a boundary 076 drew
--     deliberately, and hands the machine plane EVERY configuration row —
--     including every money threshold — in order to read one rate.
--   · A separate kernel reader function puts pricing authority in a SECOND
--     place when this RPC is already the price authority: it is what snapshots
--     ticket_type.price_minor and computes total_minor, and §6.1's whole point
--     is that price is decided ONCE, server-side. Two pricing readers is two
--     prices.
-- This function is SECURITY DEFINER, so it reaches the row past both the
-- schema grant and the visibility restriction, and THE RATE NEVER LEAVES THE
-- DATABASE — only the derived amount does.
--
-- ORDERING, AND IT IS DELIBERATE: the A8 readiness gate runs BEFORE any fee
-- work. An organization that cannot be paid is refused without the rate ever
-- being read, so an unset rate can never mask an ineligible org (or the
-- reverse) in the error the buyer sees. The rate is then resolved and
-- validated BEFORE the item/hold loop, so an unset rate fails closed without
-- doing inventory work; only the arithmetic waits for v_total.
-- ---------------------------------------------------------------------------
-- ============================================================================
create or replace function venue.create_primary_checkout(
  p_session_id uuid, p_items jsonb, p_hold_ids uuid[], p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_sess_status text;
  v_evt_status  text;
  v_org_id    uuid;
  v_order_id  uuid;
  v_total     integer := 0;
  v_ex_id     uuid;
  v_ex_total  integer;
  v_ex_curr   text;
  v_item      jsonb;
  v_tt_id     uuid;
  v_qty       integer;
  v_price     integer;
  v_held      integer;
  v_snapshot  jsonb := '[]'::jsonb;
  -- A8/G2: the readiness operands, read once from the selling organization.
  v_org_ref   text;
  v_org_ready boolean;
  -- A8/G2b: the deliverability operands — the event's scope keys for the
  -- signing-key resolution, and the key that resolution finds.
  v_event_id    uuid;
  v_venue_id    uuid;
  v_signing_key uuid;
  -- A5: the buyer-side service fee. v_fee_bps is NUMERIC on purpose — the cast
  -- happens once, and an owner typo is caught by an explicit range check with a
  -- greppable message instead of a raw 22P02 out of an ::integer cast.
  v_fee_bps      numeric;
  v_fee_minor    integer;
  v_charge_total integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- OR-17 F-1 + E-23 gate FIRST — an acquisition refusal fires before ANY work
  -- (as 081's reserve does), so a non-ACTIVE buyer is turned away regardless of
  -- what else is in the request. F-1 (dsm §3.2, tests the caller; buyer_id =
  -- auth.uid()): refuse DELETION_PENDING. E-23: is_deletion_pending returns FALSE
  -- for ERASED, so the checkout buyer must be proven ACTIVE, not merely
  -- not-pending — the 077 F-6 / E-8 defensive-twin idiom. (Defensive: an ERASED
  -- identity cannot authenticate, but E-23 mandates the refusal be present and
  -- NOT dischargeable by is_deletion_pending alone.)
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending';
  end if;
  if exists (select 1 from kernel.identity_ext e
              where e.identity_id = v_uid and e.deletion_state = 'ERASED') then
    raise exception 'precondition_failed: identity_erased';
  end if;

  -- Idempotency short-circuit (C16): a replay of a succeeded checkout returns the
  -- original order, not a second one. DELIBERATELY AHEAD OF THE A8/G2 GATE: an
  -- order that already exists is a settled fact, and re-refusing it would turn a
  -- harmless client retry into a phantom failure after the money decision was
  -- already taken.
  -- IT ALSO CARRIES NO FEE FIELDS, DELIBERATELY. A replay is not a fresh quote:
  -- the buyer-side charge for this order was quoted on the ORIGINAL call and
  -- the edge already minted a PaymentIntent from it. Re-deriving the fee here
  -- from the CURRENT rate would silently move the price under an already-minted
  -- PI if the owner had changed fee.buyer_service_bps in between. The fee is
  -- not stored on venue."order" (see the A5 block below — total_minor is face
  -- value and nothing else on the row may carry it), so this function cannot
  -- reproduce the original quote and must not guess at one. `idempotency_replay`
  -- means "you already have this order — reuse the quote you already made."
  -- Recorded as R30-4 in the footer.
  select order_id, total_minor, currency into v_ex_id, v_ex_total, v_ex_curr
    from venue."order"
   where buyer_id = v_uid and command_idempotency_key = p_command_key;
  if v_ex_id is not null then
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr);
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'precondition_failed: no items';
  end if;

  -- Session must be sellable (event on_sale/live) and not terminal (§6.1). org_id
  -- is server-derived from the session's event; never client-trusted.
  select e.status, s.status, e.org_id, e.event_id, e.venue_id
    into v_evt_status, v_sess_status, v_org_id, v_event_id, v_venue_id
    from catalog.event_session s
    join catalog.event e on e.event_id = s.event_id
   where s.session_id = p_session_id;
  if v_sess_status is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;
  if v_evt_status not in ('on_sale','live') then
    raise exception 'precondition_failed: not_on_sale';
  end if;
  if v_sess_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- ---- A8 / F §3.5 gate G2 — PAYOUT READINESS, FAIL CLOSED -----------------
  -- The organization whose event this is must have a BOUND destination AND a
  -- live `transfers` capability. Under Ruling A1/A2 the platform is merchant of
  -- record and the organization is paid later by POST /v1/transfers, so
  -- `transfers` active is what makes that transfer legal — F §3.5 rules that
  -- payouts_enabled is explicitly NOT part of this predicate (an organization
  -- that can be transferred to but cannot yet reach its bank keeps selling; the
  -- money rests in their Stripe balance and no ticket is harmed).
  -- Both operands are required: a bound ref with a dead capability is not
  -- ready, and a live-looking flag with no ref has nowhere to send money. The
  -- org row is read WITHOUT a lock on purpose — checkout moves no money, and
  -- 085's finalize is the authoritative money moment; taking a row lock on the
  -- organization here would serialize every buyer in the venue behind one row.
  --
  -- THIS READ IS LEGAL AND NEEDS NO GRANT — DO NOT "FIX" IT BY WIDENING ONE.
  -- kernel.organization revokes everything from `authenticated` and grants back
  -- only (org_id, display_name, status) (077:133-138), so a BUYER cannot read
  -- stripe_connect_account_ref or the §1 columns. This function is SECURITY
  -- DEFINER: it executes as the function owner, not as the caller, so the
  -- client-side revoke does not apply to it and the select below succeeds for
  -- every buyer without any column ever becoming client-readable. That is the
  -- whole design — the gate reads privileged state, the caller cannot. Anyone
  -- who "fixes" a permission error here by granting `authenticated` SELECT on
  -- these columns has published the payout destination of every organization
  -- on the platform to every signed-in user. The read path for humans is
  -- kernel.get_org_connect_state (§6), which masks the account id.
  select o.stripe_connect_account_ref, o.connect_transfers_active
    into v_org_ref, v_org_ready
    from kernel.organization o
   where o.org_id = v_org_id;
  if v_org_ref is null or coalesce(v_org_ready, false) is not true then
    -- X-12 restrictive reading: absent or unknown state authorizes NOTHING.
    raise exception 'precondition_failed: payout_not_ready';
  end if;
  -- ---- end A8 / G2 ---------------------------------------------------------

  -- ---- A8 / G2b — SIGNING-KEY DELIVERABILITY, FAIL CLOSED -----------------
  -- THE DEFECT THIS CLOSES: with ZERO signing keys in the database an order was
  -- created, the buyer paid, the webhook called venue.finalize_primary_order,
  -- and the mint raised `no_active_signing_key` (083:513-530) — AFTER the
  -- PaymentIntent was confirmed. The buyer is charged and holds no ticket, and
  -- with the refund executor undeployed and kernel.mark_refund_state without a
  -- caller, nothing gives the money back automatically. G2 asks whether the
  -- VENUE can be paid; this asks whether the BUYER can be delivered to. The
  -- owner's SALEABLE rule covers both: do not sell what Snatch It cannot
  -- honour, and a sale that provably cannot mint a ticket is the clearest case.
  --
  -- THE PREDICATE IS COPIED FROM THE MINT, NOT APPROXIMATED. A gate looser than
  -- the mint's would pass here and fail there, which is the bug being closed —
  -- so this is venue.finalize_primary_order's own resolution (085:1948-1960)
  -- character for character: active status, inside [not_before, not_after), and
  -- a scope that GOVERNS this event, ordered MOST SPECIFIC FIRST — per_event
  -- outranks per_venue outranks global. 083:517-527 then re-validates the
  -- pinned key with the identical conditions, so a key this finds is a key the
  -- mint accepts.
  --
  -- The `order by … limit 1` is retained even though a bare EXISTS would be
  -- logically equivalent for a yes/no gate: the ordering is what makes this
  -- visibly the SAME query as finalize's, so a future change to the precedence
  -- there is an obvious mismatch here rather than a silent divergence.
  --
  -- FAILS CLOSED ON EVERY AMBIGUITY: no key at all, a key that is inactive, one
  -- not yet in force, one already expired, or one whose scope does not govern
  -- this event all resolve to NULL and refuse. This gate is ON from the moment
  -- 093 applies and stays on until the ruling-B bootstrap key row exists — the
  -- owner ceremony (093 scope item 2) — which is the correct resting state:
  -- until that row exists, no ticket can be minted by anything.
  --
  -- NOTHING HERE PROVISIONS A KEY. Ruling B parks kernel.provision_signing_key
  -- and rotate_signing_key as unconditional raises, and this slice neither
  -- un-parks them nor inserts a signing_key row. A gate that could mint its own
  -- key would defeat the two-person KMS ceremony it exists to wait for.
  select k.key_id into v_signing_key
    from kernel.signing_key k
   where k.status = 'active'
     and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     and (   (k.scope = 'per_event' and k.event_id = v_event_id)
          or (k.scope = 'per_venue' and k.venue_id = v_venue_id)
          or (k.scope = 'global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
   limit 1;
  if v_signing_key is null then
    raise exception 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before a ticket can be sold';
  end if;
  -- The key is NOT pinned onto the order. Resolution happens again at finalize
  -- under the rank-1 session lock (085:1943-1960), which is the correct place
  -- for it: a key legitimately rotated between checkout and payment must not be
  -- frozen by a value captured here, and venue."order" has no column for one.
  -- This gate proves DELIVERABILITY AT QUOTE TIME; finalize decides WHICH key.
  -- ---- end A8 / G2b --------------------------------------------------------

  -- ---- A5 — BUYER SERVICE FEE RATE, FAIL CLOSED ---------------------------
  -- STRICTLY AFTER the gate above: an organization that cannot be paid is
  -- refused before the rate is read at all. STRICTLY BEFORE the item loop: an
  -- unset rate refuses without doing hold/inventory work.
  -- Same platform_config idiom as the money code (085:1646-1647) — highest
  -- version wins, and `#>> '{}'` turns the seeded jsonb `null` into a SQL NULL.
  select (c.value #>> '{}')::numeric into v_fee_bps
    from catalog.platform_config c
   where c.key = 'fee.buyer_service_bps'
   order by c.version desc limit 1;
  -- THE OWNER STOP (A5): "No service-fee percentage is hardcoded in migration
  -- 093. No percentage is invented anywhere." An unset rate must REFUSE TO
  -- QUOTE. It must never fall back to zero: that would sell the ticket at face
  -- value with no platform revenue, and settlement lines are append-only with a
  -- write-once header, so revenue not recognised at the sale can never be
  -- restated afterwards. A missing KEY reads the same as a null VALUE and is
  -- refused identically — X-12 restrictive: absent state authorizes NOTHING.
  -- Distinct and greppable on purpose; this is the error that will be seen at
  -- activation if the rate was never set, and it must name its own cause.
  if v_fee_bps is null then
    raise exception 'precondition_failed: service_fee_unset — fee.buyer_service_bps has no value; selling cannot be activated until the owner sets it';
  end if;
  -- Bare integer basis points, 0..10000 — the shape of catalog.resale_policy
  -- .price_cap_bps / .royalty_bps (078:258-261). A fractional or out-of-band
  -- value is an owner typo, and a typo in a money rate fails closed.
  if v_fee_bps < 0 or v_fee_bps > 10000 or v_fee_bps <> trunc(v_fee_bps) then
    raise exception 'precondition_failed: service_fee_out_of_range — fee.buyer_service_bps must be an integer 0..10000, got %', v_fee_bps;
  end if;
  -- ---- end A5 rate resolution ----------------------------------------------

  -- Validate items and snapshot the server-authoritative price ONCE per item
  -- (§6.1: a SINGLE server snapshot — the same value backs total_minor AND the
  -- line item, so a concurrent set_ticket_type_price cannot make them diverge),
  -- then prove the buyer's ACTIVE holds cover each item's quantity for THIS
  -- session (holds belong to the buyer, are active, not expired — §6.1). Money
  -- never moves; the authoritative held→sold conversion + oversell backstop
  -- (C27) is 085/finalize, which MUST re-read hold status + re-derive capacity
  -- under the batch FOR UPDATE (forward obligation — see governance E-40).
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_tt_id := (v_item->>'ticket_type_id')::uuid;
    v_qty   := (v_item->>'quantity')::integer;
    if v_tt_id is null or v_qty is null or v_qty <= 0 then
      raise exception 'precondition_failed: bad_item';
    end if;

    select tt.price_minor into v_price
      from venue.ticket_type tt
     where tt.ticket_type_id = v_tt_id;
    if v_price is null then
      raise exception 'not_found: ticket type %', v_tt_id using errcode = 'P0002';
    end if;

    -- coverage: sum of the buyer's active, unexpired holds for batches of this
    -- ticket_type in this session must be >= the requested quantity.
    select coalesce(sum(h.quantity), 0) into v_held
      from venue.inventory_hold h
      join venue.inventory_batch b on b.batch_id = h.batch_id
     where h.hold_id = any(p_hold_ids)
       and h.identity_id = v_uid
       and h.status = 'active'
       and h.expires_at > now()
       and b.ticket_type_id = v_tt_id
       and b.event_session_id = p_session_id;
    if v_held < v_qty then
      raise exception 'precondition_failed: holds do not cover item (type %, need %, held %)', v_tt_id, v_qty, v_held;
    end if;

    v_total := v_total + (v_price * v_qty);
    -- carry the ONE snapshotted price forward; the line item is written from
    -- this, never re-read, so order.total_minor = Σ(order_item.unit_price × qty).
    v_snapshot := v_snapshot || jsonb_build_array(
      jsonb_build_object('tt', v_tt_id, 'qty', v_qty, 'price', v_price));
  end loop;

  -- ---- A5 — THE FEE AMOUNT, AND WHAT IT IS *NOT* --------------------------
  -- Derived "from the base in integer cents, half-up"
  -- (docs/phase2/_decisions/A_venue_money.md:115). round() on numeric is
  -- half-away-from-zero and v_total is non-negative, so that IS half-up here.
  v_fee_minor    := round(v_total::numeric * v_fee_bps / 10000)::integer;
  v_charge_total := v_total + v_fee_minor;
  --
  -- *** READ THIS BEFORE CHANGING ANYTHING BELOW — THE SINGLE MOST
  -- *** MISREADABLE LINE IN THIS MIGRATION:
  -- venue."order".total_minor STAYS FACE VALUE. THE FEE IS NEVER ADDED TO IT.
  -- Ruling A5 fixes the venue's entitlement at the configured ticket face
  -- value and subtracts no platform fee from it, because Snatch It's revenue
  -- is BUYER-FUNDED and collected at checkout, not deducted at settlement. The
  -- settlement revenue seam (093 scope item 11) reads total_minor as the
  -- venue's gross, so folding the buyer fee into that column would pay the
  -- venue the platform's own revenue — silently, in an append-only ledger with
  -- no delete and a write-once header. The fee exists ONLY on the buyer's
  -- charge: it rides out in the return below, the edge mints a PaymentIntent
  -- for charge_total_minor, and no column on venue."order" ever carries it.
  -- The insert below is therefore UNCHANGED and must stay unchanged.
  -- ---- end A5 fee amount ---------------------------------------------------

  -- Create the pending order + items in one inner block. source is server-tagged;
  -- the frozen §6.1 signature carries no source hint and the rail is dark, so 'web'
  -- is the inert placeholder (owner-owed-forward, E-39). Candidate columns stay
  -- NULL (R2B/C112 — no promoter tables until 090). A concurrent C16 replay (both
  -- submits pass the short-circuit above, the loser trips order_buyer_command_uq)
  -- returns idempotency_replay, not a raw 23505 — the 081 reserve idiom. Scoped to
  -- the INSERTs so the gate's FOR SHARE lock on identity_ext (taken above via
  -- is_deletion_pending, F-11) is held to commit, outside this savepoint.
  begin
    insert into venue."order" (buyer_id, event_session_id, org_id, status, source,
                               total_minor, currency, command_idempotency_key)
    values (v_uid, p_session_id, v_org_id, 'pending', 'web', v_total, 'USD', p_command_key)
    returning order_id into v_order_id;

    for v_item in select * from jsonb_array_elements(v_snapshot) loop
      insert into venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor, currency)
      values (v_order_id, (v_item->>'tt')::uuid, (v_item->>'qty')::integer,
              (v_item->>'price')::integer, 'USD');
    end loop;
  exception when unique_violation then
    -- the C16 (buyer, command_key) race: the other txn committed the order first.
    select order_id, total_minor, currency into v_ex_id, v_ex_total, v_ex_curr
      from venue."order"
     where buyer_id = v_uid and command_idempotency_key = p_command_key;
    if not found then raise; end if;   -- a different unique violation (e.g. a dup item)
    -- No fee fields here either, for the same reason as the C16 short-circuit
    -- above: the winning transaction produced the quote, and this loser must
    -- not mint a second, possibly different one (R30-4).
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr);
  end;

  -- total_minor is FACE VALUE (the venue's entitlement and the settlement
  -- seam's gross); buyer_fee_minor is the platform's buyer-funded revenue; and
  -- charge_total_minor is the ONLY figure the PaymentIntent may be minted for.
  -- `buyer_fee` is the corpus noun for exactly this money (public.payments,
  -- 000:982-985; and the config namespace already carries
  -- refund.buyer_fee_refundable, 078:1550) — not an invented name.
  -- org_id rides out on the SUCCESS return ONLY. Its single consumer is
  -- metadata[org_id] on the PaymentIntent, which the webhook's organization arm
  -- joins on (F §3.6(1)) — and the edge cannot derive it any other way: reading
  -- venue."order" or kernel.organization with the service_role client is 42501
  -- (no table privilege exists in either schema for that role). It is
  -- DELIBERATELY ABSENT from both idempotency_replay returns: that path reuses
  -- an existing PaymentIntent and mints no new metadata, so it has no use for
  -- the value, and supplying one would invite exactly the re-derivation the fee
  -- fields were kept off those returns to prevent (R30-4).
  return jsonb_build_object('status','ok','order_id',v_order_id,
                            'org_id',v_org_id,
                            'total_minor',v_total,'currency','USD',
                            'buyer_fee_minor', v_fee_minor,
                            'charge_total_minor', v_charge_total);
end;
$$;


-- ============================================================================
-- §4 — kernel.set_org_connect_ref: the FIRST BIND, hardened.
--   Rulings A7 ("A caller must never be permitted to supply or bind an
--   arbitrary acct_ identifier"; "cross-plane reuse of an ordinary seller's
--   existing connected account must be prevented") and A9 (attachment is a
--   privileged, audited operation) · G §2 threats G-1/G-6, §5.1 · scope item 8.
--
-- SIGNATURE IS UNCHANGED AND MUST STAY UNCHANGED. `create or replace function`
-- CANNOT drop a parameter — dropping p_connect_account_id would be a DROP and
-- CREATE, which is a new object with a new ACL and is out of scope for an
-- additive migration. THE CALLER-SUPPLIED IDENTIFIER THEREFORE STAYS IN THE
-- SIGNATURE ON PURPOSE. What eliminates the attack is the REFUSAL IN THE BODY,
-- not the shape of the argument list. Do not "tidy" this parameter away, and
-- do not read its presence as permission for a caller to choose an account:
-- the edge function mints the account server-side with metadata[org_id] and
-- passes back only the id IT minted (F §3.2), and everything below exists to
-- make any other value unusable.
--
-- WHAT CHANGED vs 077:948-1013 — four additions and one narrowing:
--   (a) CROSS-PLANE REFUSAL (G-1, the highest-value line in this migration).
--   (b) org_owner ONLY — org_finance dropped from the role set.
--   (c) status narrowed to ('approved','active') — 'applied' no longer binds.
--   (d) aal2 step-up required, in the 085:1624-1631 shape.
--   (e) best-effort security notification (G-2).
-- Everything else — the caller-JWT requirement, the regex, the row lock, the
-- noop_replay path, BIND-ONCE, the SoD-1 stamp, the unique_violation mapping,
-- the audit row and the return shape — is preserved verbatim.
--
-- WHAT DELIBERATELY DID NOT CHANGE: no money-role maturity requirement on the
-- FIRST bind. G §5.1 recommends one; the owner declined it for this verb and
-- the reasoning is decisive — maturity here forces a waiting period before
-- onboarding can even BEGIN, at a moment when the organization holds no money
-- and none is at risk. Maturity stays where it belongs, on the re-point (§5),
-- where a live destination is being taken away.
-- ============================================================================
create or replace function kernel.set_org_connect_ref(
  p_org_id uuid, p_connect_account_id text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_ref       text;
  v_status    text;
  v_pending   text;
  v_aal       text;
  v_audit_id  uuid;
  v_recipient uuid;
begin
  -- §20.1.1 / §0.1a: EDGE-CALLER-JWT bound — a service-role invocation has
  -- auth.uid() NULL and must RAISE rather than bind (T-RPC-CONNECT-04).
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: caller JWT required — connect-onboarding must use the caller''s Authorization header'
      using errcode = '42501';
  end if;
  -- A9 / G §5.1 — NARROWED from ('org_owner','org_finance'). Attaching the
  -- payee IS replacing it when the prior value was nothing, and SoD-1 already
  -- reserves the destination to org_owner on the re-point (085:1618-1620).
  -- org_finance retains initiate-the-Stripe-flow and view; it no longer binds.
  -- Roles are single-valued with NO inheritance (077:150) — an org_owner row
  -- can never satisfy has_org_role(['org_finance']) and vice versa, so this is
  -- a real narrowing, not a notational one.
  if not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'insufficient_privilege: org_owner required (SoD-1; org_finance may initiate onboarding but may not bind the payee)'
      using errcode = '42501';
  end if;
  -- AUTHZ-M4: step-up demanded, fail closed — an absent claim can never be
  -- evaluated as satisfied. Same shape as 085:1624-1631. Binding the payee is
  -- a money-destination act and carries the money-destination step-up.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to bind a payout destination';
  end if;
  if p_connect_account_id is null or p_connect_account_id !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: malformed_account_ref';
  end if;

  -- ---- A7 / A9 / G-1 — THE CROSS-PLANE REFUSAL ----------------------------
  -- THIS IS THE LINE THAT CLOSES THE PERSONAL-SELLER-ACCOUNT ATTACK.
  -- 077:124-126 is UNIQUE(stripe_connect_account_ref) WHERE NOT NULL on
  -- kernel.organization — it is PER-PLANE and cannot see the individual plane
  -- at all. A staff member who has onboarded as an ordinary Snatch It seller
  -- already HOLDS a valid acct_ id (create-connect-account/index.ts:212); with
  -- nothing but a regex in the way, binding it here points every settlement
  -- payout for that organization at a personal account, indefinitely and
  -- silently. Total impact, most likely attack, one `exists` clause.
  -- The archive is included as well (044): an id that was archived off a
  -- profile is still an account the platform minted for an INDIVIDUAL, and
  -- re-minting on the individual plane must never hand the org plane a
  -- laundering route.
  -- Placed BEFORE the row read, so a replay carrying a poisoned id is refused
  -- rather than short-circuiting through the noop path below. Fail closed.
  if exists (select 1 from public.profiles pf
              where pf.stripe_connect_id = p_connect_account_id)
     or exists (select 1 from public.stripe_connect_archive ar
                 where ar.stripe_connect_id = p_connect_account_id) then
    -- errcode: this is a refusal of the SUPPLIED VALUE, not of the caller, so it
    -- is a precondition (P0001), matching every other precondition_failed here.
    raise exception 'precondition_failed: account_not_platform_minted_for_org — this account belongs to the individual seller plane';
  end if;
  -- ---- end cross-plane refusal --------------------------------------------

  select o.stripe_connect_account_ref, o.status, o.connect_pending_ref
    into v_ref, v_status, v_pending
    from kernel.organization o where o.org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id;
  end if;
  -- G-6 — NARROWED from ('applied','approved','active'). A payee is bound
  -- AFTER platform review, never before. This also SUBSUMES the probation-clock
  -- defect: the probation operand is max(occurred_at) over the bind/change
  -- audit actions (087:472-476), so a bind that could precede approval let a
  -- fraudster age the probation window out before the org was ever reviewed.
  -- A bind can no longer precede approval, so the clock can no longer be
  -- started early — no change to 087 is required.
  if v_status not in ('approved','active') then
    raise exception 'precondition_failed: org_not_bindable — a % org may not bind a payee (approval precedes the payee)', v_status;
  end if;

  if v_ref is not null and v_ref = p_connect_account_id then
    -- the "reuse existing connect ids" re-onboarding retry path
    return jsonb_build_object('status', 'noop_replay', 'org_id', p_org_id,
                              'connect_account_id', v_ref, 'newly_bound', false);
  end if;
  if v_ref is not null then
    -- BIND-ONCE: a re-point is never an onboarding event; the only path is
    -- kernel.set_org_payout_destination (§17.7, a later package).
    raise exception 'precondition_failed: destination_already_set — re-pointing rides kernel.set_org_payout_destination only';
  end if;

  -- ---- A7 / RT-A-3 — THE PROVENANCE REQUIREMENT ---------------------------
  -- THIS IS THE CHECK THAT MAKES "the caller may not supply an arbitrary acct_"
  -- TRUE RATHER THAN ADVISORY. The identifier must equal the one the platform
  -- itself minted for THIS organization and recorded via §2b, which only
  -- service_role can call. The cross-plane refusal above is a blocklist and
  -- cannot catch an attacker's own fresh Stripe account — the red team bound
  -- `acct_ORPHANATTACKER` straight through it. This is an allowlist of exactly
  -- one value, and it is written by a credential a browser session never holds.
  --
  -- PLACED AFTER THE REPLAY AND BIND-ONCE ARMS ON PURPOSE. A successful bind
  -- CLEARS connect_pending_ref (below), so a replay of the same call arrives
  -- with nothing staged; checking provenance first would turn the idempotent
  -- retry that G-8 depends on — and that tests/141:638-641 asserts — into a
  -- hard failure. Order: replay → bind-once → provenance → write.
  if v_pending is null then
    raise exception 'precondition_failed: no_pending_connect_ref — no account has been minted for this organization; onboarding must run through the connect-onboarding edge function';
  end if;
  if v_pending <> p_connect_account_id then
    raise exception 'precondition_failed: connect_ref_not_platform_minted — this identifier was not minted by the platform for this organization';
  end if;
  -- ---- end provenance ------------------------------------------------------

  begin
    update kernel.organization
       set stripe_connect_account_ref = p_connect_account_id,
           -- SoD-1 applies from the very first destination
           payout_destination_set_by  = v_uid,
           -- SINGLE USE: consumed at the bind so it cannot be replayed into a
           -- later re-point. A new destination requires a new mint and a new
           -- staging call, which is exactly the property A9 wants — "a live
           -- payout destination is never silently replaced".
           connect_pending_ref        = null
     where org_id = p_org_id;
  exception when unique_violation then
    raise exception 'conflict_locked: connect account already bound to another org';
  end;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.connect_ref.bind', 'organization', p_org_id, 'onboarding',
          null, jsonb_build_object('connect_account_id', p_connect_account_id))
  returning id into v_audit_id;

  -- ---- A9 / G-2 — the human tripwire, BEST-EFFORT --------------------------
  -- security_payout_destination_changed has existed in the deployed catalogue
  -- since 092:269 with templates at 092:336-337 and has had ZERO producers
  -- anywhere in the repo. The destination could change and nobody was told.
  -- Pattern is change_org_role's verbatim (077:1263-1279): wrapped in
  -- begin…exception when others then raise warning, keyed on the admin_audit
  -- row id (the PFA-2 per-occurrence collision rule), so a failed emit warns
  -- and the bind still commits — N-A30. The bind does not read the envelope.
  -- Recipients: every org_owner AND org_finance. The brief names owners; G §6.2
  -- names "every org_owner and org_finance of the org, plus the actor", and the
  -- superset is used because under-notifying the finance role is precisely the
  -- G-2 defect. The actor is included when they hold either role, which after
  -- the (b) narrowing above they always do.
  -- Payload carries the LAST 4 ONLY, never the acct_ id: the templates ask only
  -- for {{destination_last4}} (092:336), and Connect ids may not leave the
  -- trust boundary (G §6.1).
  begin
    for v_recipient in
      select m.identity_id from kernel.org_member m
       where m.org_id = p_org_id and m.role in ('org_owner','org_finance')
    loop
      perform notify.emit_event(
        'security_payout_destination_changed', 'identity', v_recipient,
        'security_payout_destination:' || v_audit_id::text || ':' || v_recipient::text,
        jsonb_build_object('org_id', p_org_id,
                           'destination_last4', right(p_connect_account_id, 4),
                           'origin', 'connect_ref_bind',
                           'actor_identity', v_uid));
    end loop;
  exception when others then
    raise warning 'set_org_connect_ref: best-effort security notice emit failed: %', sqlerrm;
  end;

  return jsonb_build_object('status', 'ok', 'org_id', p_org_id,
                            'connect_account_id', p_connect_account_id, 'newly_bound', true);
end;
$$;


-- ============================================================================
-- §5 — kernel.set_org_payout_destination: the RE-POINT, hardened.
--   Rulings A7 (both binding surfaces must reject caller-selected account ids)
--   and A9 ("Replacement of an existing organization Stripe account is treated
--   as higher risk than first-time onboarding") · G §2 threats G-1/G-3/G-6,
--   §5.1 · scope item 9.
--
-- WHY THIS VERB IS NOT OPTIONAL WORK. It is granted to `authenticated`
-- (085:2137) and reachable through PostgREST in one call. Hardening only the
-- first bind would leave settlement money re-pointable to a personal seller
-- account, invisible to 077:124-126 because that index is per-plane. A first
-- bind risks no money; a re-point risks all of it.
--
-- WHAT CHANGED vs 085:1601-1662 — three additions, nothing removed:
--   (a) the SAME cross-plane refusal as §4 (G-1).
--   (b) an ORGANIZATION-STATUS gate — today a SUSPENDED org can re-point
--       (G-6 / G §5.1: "suspension must freeze the payee").
--   (c) the same best-effort security notification (G-2).
-- Every existing control is kept exactly: org_owner only (SoD-1), money-role
-- grant maturity, aal2 step-up with the fail-closed absent-claim arm, the row
-- lock, the cool-down refusal, the cool-down write from platform_config, the
-- SoD-1 setter stamp and the audit row.
--
-- DELIBERATELY NOT CHANGED HERE: the cool-down key still fails OPEN when its
-- value is null (085:1650, seeded null at 078:1553) — the owner ruled that
-- setting `payout.destination_cooldown_hours` is CONFIGURATION, not migration
-- work (093 scope, OUT), and it must be set before activation. And the missing
-- unique_violation → conflict_locked mapping (G-4a) stays missing: the owner
-- ruled it cosmetic and out of 093. Neither is fixed here; both are recorded.
-- ============================================================================
create or replace function kernel.set_org_payout_destination(
  p_org_id uuid, p_connect_account_ref text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org       kernel.organization%rowtype;
  v_aal       text;
  v_cool      numeric;
  v_audit_id  uuid;
  v_recipient uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: no principal' using errcode = '42501';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'insufficient_privilege: org_owner only (SoD-1)' using errcode = '42501';
  end if;
  if not kernel.money_role_grant_matured(p_org_id) then
    raise exception 'sod_violation: org money grant not yet matured';
  end if;
  -- AUTHZ-M4: step-up demanded (the key's NULL seed DEMANDS it — fail closed);
  -- an absent claim can never be evaluated as satisfied.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required for money-destination changes';
  end if;
  if p_connect_account_ref is null or p_connect_account_ref !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: bad connect account ref';
  end if;

  -- ---- A7 / A9 / G-1 — THE CROSS-PLANE REFUSAL, TWIN OF §4 ----------------
  -- Same rule, same reason, and MORE consequential here: this verb re-points a
  -- LIVE destination. As in §4 the caller-supplied parameter cannot be dropped
  -- by create-or-replace, so the refusal in the body is the control. The
  -- account must be one the platform minted FOR AN ORGANIZATION; anything that
  -- has ever sat on the individual plane (live in profiles, or archived by the
  -- 044 self-heal) is refused outright.
  if exists (select 1 from public.profiles pf
              where pf.stripe_connect_id = p_connect_account_ref)
     or exists (select 1 from public.stripe_connect_archive ar
                 where ar.stripe_connect_id = p_connect_account_ref) then
    -- errcode: this is a refusal of the SUPPLIED VALUE, not of the caller, so it
    -- is a precondition (P0001), matching every other precondition_failed here.
    raise exception 'precondition_failed: account_not_platform_minted_for_org — this account belongs to the individual seller plane';
  end if;
  -- ---- end cross-plane refusal --------------------------------------------

  select * into v_org from kernel.organization where org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: org %', p_org_id using errcode = 'P0002';
  end if;
  -- G-6 / G §5.1 — NEW. This verb performed NO org-status check at all, so a
  -- SUSPENDED organization's owner could re-point the payee while the platform
  -- believed the org was frozen. Suspension must freeze the payee: the same
  -- ('approved','active') set §4 now requires, so the two surfaces agree.
  if v_org.status not in ('approved','active') then
    raise exception 'precondition_failed: org_not_bindable — a % org may not re-point its payout destination', v_org.status;
  end if;
  -- ---- A7 / A9 / RT-A-3 — PROVENANCE, AND IT MATTERS MORE HERE ------------
  -- The red team re-pointed a LIVE destination to `acct_ORPHANATTACKER`. A9 is
  -- explicit that replacement is HIGHER RISK than first-time onboarding, so the
  -- verb that moves settlement money away from an existing payee cannot have a
  -- weaker provenance rule than the one that sets the first. Identical check,
  -- identical errors: the new destination must be an account the platform
  -- minted for THIS organization and staged through §2b (service_role only).
  -- There is no replay arm on this verb, so this sits with the other
  -- preconditions rather than after them.
  if v_org.connect_pending_ref is null then
    raise exception 'precondition_failed: no_pending_connect_ref — no replacement account has been minted for this organization; a re-point must run through the connect-onboarding edge function';
  end if;
  if v_org.connect_pending_ref <> p_connect_account_ref then
    raise exception 'precondition_failed: connect_ref_not_platform_minted — this identifier was not minted by the platform for this organization';
  end if;
  -- ---- end provenance ------------------------------------------------------
  if v_org.payout_destination_locked_until is not null and v_org.payout_destination_locked_until > now() then
    raise exception 'precondition_failed: destination cool-down until %', v_org.payout_destination_locked_until;
  end if;
  select (c.value #>> '{}')::numeric into v_cool from catalog.platform_config c
   where c.key = 'payout.destination_cooldown_hours' order by c.version desc limit 1;

  update kernel.organization
     set stripe_connect_account_ref = p_connect_account_ref,
         payout_destination_set_by = v_uid,
         payout_destination_locked_until = case when v_cool is null then null
                                                else now() + make_interval(hours => v_cool::int) end,
         -- consumed, exactly as at the first bind: one mint, one re-point
         connect_pending_ref = null,
         updated_at = now()
   where org_id = p_org_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.payout_destination.change', 'organization', p_org_id,
          coalesce(p_reason_code,'destination_change'),
          jsonb_build_object('connect_ref', v_org.stripe_connect_account_ref),
          jsonb_build_object('connect_ref', p_connect_account_ref))
  returning id into v_audit_id;

  -- ---- A9 / G-2 — the human tripwire, BEST-EFFORT (twin of §4) -------------
  -- "A live payout destination is never silently replaced" (A9). Recipients are
  -- every org_owner and org_finance INCLUDING any who did not act — that is the
  -- whole point: the org's other owners learn of a re-point they did not make.
  -- G §5.2 downgraded in-database dual control (unbuildable: kernel.
  -- approval_request closes its action/subject_kind vocabularies at frozen
  -- CHECKs, 077:269-276/299-302, and a destination change has no amount_minor).
  -- THIS NOTIFICATION IS ONE OF THE THREE SUBSTITUTES, alongside the SoD-1
  -- payout exclusion (087:428-431) and destination probation (087:465-495).
  -- Best-effort: a failed emit must never roll back the change.
  begin
    for v_recipient in
      select m.identity_id from kernel.org_member m
       where m.org_id = p_org_id and m.role in ('org_owner','org_finance')
    loop
      perform notify.emit_event(
        'security_payout_destination_changed', 'identity', v_recipient,
        'security_payout_destination:' || v_audit_id::text || ':' || v_recipient::text,
        jsonb_build_object('org_id', p_org_id,
                           'destination_last4', right(p_connect_account_ref, 4),
                           'origin', 'payout_destination_change',
                           'actor_identity', v_uid));
    end loop;
  exception when others then
    raise warning 'set_org_payout_destination: best-effort security notice emit failed: %', sqlerrm;
  end;

  return jsonb_build_object('status','ok','org_id', p_org_id);
end;
$$;

-- ============================================================================
-- §6 — kernel.get_org_connect_state: the READ path.
--   Ruling F §3.5 gate G5 ("Venue dashboard — client display only, never the
--   enforcement point — reads the same state via a read RPC") and F §3.7(6)
--   (the Payments status section). Prescribed there, never authored.
--
-- BELONGS WITH §1 — it reads the two columns §1 adds, and is placed last only
-- to avoid renumbering the sections above.
--
-- WHY IT IS NOT OPTIONAL: without it the resolve-before-create property of the
-- onboarding edge has no way to read the fact it depends on.
-- kernel.organization.stripe_connect_account_ref is readable by NEITHER role
-- that could ask: `authenticated` is revoked down to (org_id, display_name,
-- status) (077:133-138), and service_role holds USAGE ONLY on the kernel
-- schema with no table grant (085:2092-2095, PFA-21). So an edge function that
-- cannot call this verb cannot tell whether an organization already has a
-- Stripe account, and its only safe-looking option — mint one — is exactly the
-- failure this closes: a SECOND connected account for an org that already had
-- one, which 077:124-126 then refuses at bind time, leaving an orphaned live
-- Stripe account with no row pointing at it and no way to reach it.
--
-- CALLER-AUTHORIZED, NOT A MACHINE VERB. Granted to `authenticated` only —
-- never service_role. The onboarding edge already forwards the caller's
-- Authorization header because §4 RAISES without a caller JWT (077:962-966);
-- this read rides the same session, so authority is evaluated against a real
-- human on every call. A service_role grant would also be inert by
-- construction: has_org_role tests auth.uid() (077:453-466), which is NULL on
-- a machine session, so a service_role caller would earn 42501 anyway — but
-- the grant is withheld deliberately rather than left to that accident.
--
-- AUTHORITY: org_owner or org_finance — the same set F §3.4 gives the INITIATE
-- and RECONNECT actions, which are the two things this read serves. NOT
-- widened to venue roles: F §3.4 gives venue_manager/venue_finance a one-
-- sentence gate REASON and explicitly no account reference, and that carve-out
-- is a separate, narrower verb if the dashboard ever needs it. Not widened to
-- platform roles either (list_org_payouts admits them at 085:1452-1454; this
-- verb has no support use case yet, and minimality governs 093).
--
-- NEVER RETURNS THE FULL acct_ ID. Last 4 and a boolean, nothing more —
-- G §6.1 and PHASE_2_CRM_EXPORT_SPEC.md:285 bar Connect ids from leaving the
-- trust boundary, and F §3.7(6) specifies the account is shown MASKED. The
-- edge does not need the id: it re-reads live truth from Stripe by retrieving
-- the account it minted, and Postgres is only telling it whether a binding
-- already exists and what the last observed capability state was.
--
-- SAFE BEFORE ANY BINDING EXISTS — this is the NORMAL FIRST CALL. An unbound
-- org returns connect_bound=false, never not_found. There is no not_found arm
-- at all: has_org_role is a live join on kernel.org_member, so a caller
-- holding a role on a non-existent org is not representable, and a missing org
-- is refused as 42501 before the row is ever read.
-- ============================================================================
create or replace function kernel.get_org_connect_state(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org kernel.organization%rowtype;
begin
  if p_org_id is null then
    raise exception 'invalid_input: an org scope is required (no scope-free form)';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_finance']) then
    raise exception 'insufficient_privilege: org_owner or org_finance required'
      using errcode = '42501';
  end if;

  select * into v_org from kernel.organization where org_id = p_org_id;

  return jsonb_build_object(
    'status', 'ok',
    'org_id', p_org_id,
    -- org_status is ALREADY client-readable (077:120-123 grants it), so it
    -- discloses nothing new — and it has a named reader: §4 now refuses to bind
    -- a payee for an org that is not approved/active, so an edge that minted
    -- first and bound second would strand a live Stripe account on an 'applied'
    -- org. This field is what lets the edge refuse honestly BEFORE it mints.
    'org_status', v_org.status,
    -- The resolve-before-create operand. A boolean, never the id.
    'connect_bound', (v_org.stripe_connect_account_ref is not null),
    -- ANTI-FOOTGUN, added after the red team found the edge reading a key that
    -- did not exist. An edge that does `if (!state.connect_account_ref) mint()`
    -- got `undefined` for a BOUND org, treated it as unbound, and — past
    -- Stripe's 24h idempotency window — would mint an ORPHAN LIVE ACCOUNT on
    -- every attempt. This key therefore EXISTS and is deliberately non-null
    -- whenever the org is bound, so that mistake short-circuits correctly:
    --   unbound -> null   => the edge mints, which is right
    --   bound   -> sentinel (truthy, non-empty) => the edge does NOT mint
    -- and if it then hands the sentinel to Stripe it gets an immediate 400 for
    -- an unknown account. A loud, harmless failure replaces a silent orphan.
    -- THE REAL ANSWER IS §7, kernel.get_org_connect_ref (service_role only) —
    -- the sentinel names it so a reader debugging this lands on the right verb.
    -- Do NOT "fix" this by returning the identifier: §6 is granted to
    -- `authenticated` and is one PostgREST call from any browser session.
    'connect_account_ref', case when v_org.stripe_connect_account_ref is null
                                then null
                                else 'masked:call_kernel.get_org_connect_ref' end,
    -- Masked, per F §3.7(6). NULL when unbound — not an empty string, so the
    -- client cannot render "ending in ____" for an org with no account.
    'connect_account_last4', case when v_org.stripe_connect_account_ref is null
                                  then null
                                  else right(v_org.stripe_connect_account_ref, 4) end,
    -- The §1 mirror. LAST OBSERVED, NOT LIVE TRUTH — pair it with the stamp
    -- below and re-read Stripe rather than asserting a stale green (F §3.3).
    'connect_transfers_active', v_org.connect_transfers_active,
    'connect_state_synced_at', v_org.connect_state_synced_at);
end;
$$;

-- 076 grant discipline: revoke the default PUBLIC EXECUTE, then one targeted
-- grant. `authenticated` ONLY — anon never, service_role never (see the header:
-- this verb is caller-authorized by design, and the machine plane has no
-- business enumerating payout state).
revoke all on function kernel.get_org_connect_state(uuid)
  from public, anon, authenticated;
grant execute on function kernel.get_org_connect_state(uuid) to authenticated;


-- ============================================================================
-- §7 — kernel.get_org_connect_ref: the MACHINE reader. FULL IDENTIFIER.
--   Ruling F §3.4 (the RECONNECT path) and F §3.7(3)/(6) (minting the Account
--   Link, and the Express Dashboard login link).
--
-- ***  THIS IS THE ONE VERB IN THIS SLICE THAT DISCLOSES THE FULL PAYOUT   ***
-- ***  DESTINATION. IT IS service_role ONLY AND MUST STAY THAT WAY.       ***
--
-- WHY §6 CANNOT SERVE THIS, AND WHY THE SPLIT IS THE POINT. §6 deliberately
-- returns connect_account_last4 and never the id, because §6 is granted to
-- `authenticated` and is therefore reachable from a browser session in one
-- PostgREST call. But Stripe's account_links and login_links endpoints BOTH
-- require `account=acct_…`: a connected account cannot be resolved by metadata
-- (the Search API does not cover accounts) and the create-call idempotency key
-- expires after 24h, so there is no way to recover the id from Stripe once the
-- minting call has aged out. Without this verb, an ALREADY-BOUND organization
-- can have its status reported from the §1 mirror but CANNOT be sent to Stripe
-- at all — F §3.4's RECONNECT is unservable, and the onboarding edge is
-- reduced to refusing with 409 reconnect_unavailable.
--
-- THE TRUST BOUNDARY IS WHAT MAKES THIS A SECOND VERB RATHER THAN A WIDENED
-- ONE. The edge function runs inside the boundary; a browser session does not.
-- One verb cannot serve both without handing the id to the weaker caller.
-- STATE-FOR-HUMANS RETURNS last4 (§6); REF-FOR-MACHINES RETURNS THE IDENTIFIER
-- (here). THE TWO MUST NEVER BE MERGED, and §6 must never be "simplified" by
-- having it call this one.
--
-- NO ORG-ROLE CHECK HERE, AND ADDING ONE WOULD BREAK EVERY CALLER. Do not
-- "harden" this by adding has_org_role: that predicate tests auth.uid()
-- (077:453-466), which is NULL on a machine session, so the check could only
-- ever REFUSE — it would not tighten this verb, it would disable it. THE
-- AUTHORITY GATE FOR THIS VERB LIVES IN THE EDGE FUNCTION THAT CALLS IT, which
-- authenticates the human, checks the org role, and only then asks for the id.
-- That is the same division 085's state-sync pair already uses: the machine
-- verb carries no principal, and the principal is proven upstream. The verb's
-- protection is its GRANT, not a predicate — which is why the revoke below is
-- the load-bearing line of this section.
--
-- Returns NULL for an unbound organization rather than raising — the same
-- treatment §6 gives the normal pre-onboarding case, and the answer the edge
-- needs to decide "mint a new account" vs "reconnect the bound one". A
-- non-existent org likewise returns NULL rather than not_found: to a machine
-- caller "no id for this org" and "no such org" are the same instruction.
-- ============================================================================
create or replace function kernel.get_org_connect_ref(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select o.stripe_connect_account_ref
    from kernel.organization o
   where o.org_id = p_org_id;
$$;

-- 076 grant discipline. The `revoke ... from public` is LOAD-BEARING, not
-- ceremonial: CREATE FUNCTION grants EXECUTE to PUBLIC by default and
-- `authenticated` inherits PUBLIC, so without this line every signed-in user
-- could read every organization's payout destination in one PostgREST call.
-- service_role ONLY. This slice contains NO grant loop and NO blanket
-- `grant execute on all functions` — every grant in this file is an explicit
-- single-function statement, so nothing can catch this verb by accident.
revoke all on function kernel.get_org_connect_ref(uuid)
  from public, anon, authenticated;
grant execute on function kernel.get_org_connect_ref(uuid) to service_role;


-- ============================================================================
-- §8 — kernel.issue_ticket_atoms: RESOLVE the signing key, never accept it.
--   Signing review threat T1 · ruling B (activation boundary) · the binding
--   half of §3's G2b gate.
--
-- WHY THIS IS IN THE CONNECT SLICE: it is not connect work. It is here because
-- §3's G2b gate is UNENFORCEABLE WITHOUT IT, and shipping the gate without this
-- would be shipping a control that reads as binding and is not.
--
-- THE DEFECT. The mint took the key from the CALLER: `v_key := (p_ctx->>
-- 'signing_key_id')::uuid` (083:479), then validated it only for scope
-- COHERENCE (083:512-529) — active, in-window, and governing this session. That
-- predicate's `global` arm is UNCONDITIONAL, so a `global` key satisfies it even
-- when a `per_event` key exists for the event. Coherence is not resolution: it
-- asks "may this key govern here?", never "is this the key that governs here?".
-- Consequences, both real:
--   · T1 (a key silently outranking the intended one) is NOT superuser-only. Any
--     service_role caller could pin a global key over a per_event key and mint
--     atoms under it.
--   · MY OWN G2b GATE WAS ADVISORY. I copied finalize's resolution character for
--     character so a precedence change would surface as a visible mismatch — but
--     a mint that accepts whatever it is handed can disagree with the gate with
--     NO MISMATCH TO SEE: the gate resolves the per_event key, the caller pins
--     the global one, and both "succeed".
--
-- THE FIX, AND WHICH OPTION I TOOK. Two were available: ignore the supplied
-- value silently, or resolve internally and REFUSE a disagreement. I took the
-- REFUSAL. Silently ignoring would make a caller that believes it is choosing a
-- key be quietly overruled — the same class of invisible divergence as the bug,
-- just in the other direction — and it would erase the evidence that anyone
-- ever tried. The refusal converts an override into a loud, greppable error and
-- leaves every correct caller untouched: venue.finalize_primary_order supplies
-- the key it resolved at 085:1948-1960 with this exact rule (085:2050), so its
-- supplied value EQUALS the resolved one and it never trips the refusal.
--
-- NOTE ON THE SIGNATURE: unlike §4/§5 there is no parameter to defend here.
-- `signing_key_id` is a KEY INSIDE p_ctx jsonb, not an argument, so the frozen
-- signature (p_ctx jsonb, p_command_key text) is untouched and CREATE OR REPLACE
-- imposes no constraint at all. The value stays readable purely so the refusal
-- can compare against it.
--
-- THE RESOLUTION IS THE SAME QUERY IN ALL THREE PLACES BY CONSTRUCTION:
-- finalize (085:1948-1960), §3's G2b gate, and here. Same predicate, same
-- most-specific-first ordering (per_event → per_venue → global). It keeps 083's
-- original JOIN through event_session/event rather than finalize's two-step
-- derivation, for one reason: with a nonexistent session the join yields no row
-- and this raises `no_active_signing_key` BEFORE the rank-1 session lock,
-- exactly as the old coherence check did. On every reachable input the three
-- agree; the join form only preserves 083's pre-lock refusal ordering.
--
-- I CHECKED WHETHER THEY ALREADY DIFFERED, AS ASKED. They did, and this is the
-- finding: finalize RESOLVES (order by scope, limit 1) while the mint only
-- CHECKED COHERENCE (exists, unordered). Those are different operations, not
-- different spellings of one — which is precisely how the two could disagree.
-- After this replacement they are the same operation in all three sites.
--
-- EVERYTHING ELSE IS BYTE-FOR-BYTE: the ctx unpack, every refusal code, the
-- feature-flag gate, the idempotency anchor, the rank-1 session lock, the batch
-- lock and coherence check, the serial draw, the atom/ownership-log loop, the
-- sold conversion, the movement row, the door-manifest hook, the return shape,
-- and the unique_violation handler that returns the original atom set. NO
-- signing key is provisioned or inserted, and the parked signing RPCs stay
-- parked — a mint that could create its own key would defeat the ceremony this
-- boundary exists to wait for, exactly as §3's comment says of the gate.
-- ============================================================================
create or replace function kernel.issue_ticket_atoms(p_ctx jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor    uuid;
  v_session  uuid;
  v_org      uuid;
  v_tt       uuid;
  v_batch    uuid;
  v_owner    uuid;
  v_qty      integer;
  v_cause    text;
  v_cause_ref uuid;
  v_key      uuid;
  v_key_req  uuid;   -- T1: what the CALLER asked for. Compared, never trusted.
  v_flag     boolean;
  v_serial   integer;
  v_atom     uuid;
  v_atoms    uuid[] := '{}';
  v_ex       uuid[];
  v_b_session uuid;
  v_b_tt     uuid;
  i          integer;
begin
  v_actor := coalesce(auth.uid(), '00000000-0000-0000-0000-0000000000f1');  -- SN-SYSTEM for import/sweep
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  v_session   := (p_ctx->>'session_id')::uuid;
  v_org       := (p_ctx->>'org_id')::uuid;
  v_tt        := (p_ctx->>'ticket_type_id')::uuid;
  v_batch     := (p_ctx->>'batch_id')::uuid;
  v_owner     := (p_ctx->>'owner_id')::uuid;
  v_qty       := (p_ctx->>'quantity')::integer;
  v_cause     := (p_ctx->>'cause');
  v_cause_ref := (p_ctx->>'cause_ref')::uuid;
  -- T1: read as a REQUEST, not as the answer. Resolution happens below.
  v_key_req   := (p_ctx->>'signing_key_id')::uuid;

  if v_cause not in ('issue','comp','door_sale','import') then
    raise exception 'precondition_failed: bad_cause %', v_cause;
  end if;
  if v_qty is null or v_qty <= 0 then
    raise exception 'precondition_failed: bad_quantity';
  end if;
  if v_owner is null or v_batch is null or v_session is null
     or v_tt is null or v_cause_ref is null then
    -- cause_ref is the idempotency anchor and tt is the coherence key: a NULL in
    -- either would silently defeat the replay guard / batch check downstream (E-46).
    raise exception 'precondition_failed: incomplete context';
  end if;

  -- NATIVE ISSUANCE GATE — the mint is inert while the flag is false (dark).
  select (c.value #>> '{}')::boolean into v_flag
    from catalog.platform_config c
   where c.key = 'feature.native_issuance_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;

  -- IDEMPOTENCY: a replay of a succeeded mint returns the original atoms. The mint's
  -- ownership-log entry is ALWAYS cause='issue' (the ownership_log_from_identity_check
  -- requires cause='issue' for the from-NULL sequence-1 row); the business cause lives
  -- in the movement + the state_transition jsonb.
  select array_agg(l.ticket_atom_id order by l.ticket_atom_id) into v_ex
    from kernel.ticket_ownership_log l
   where l.cause = 'issue' and l.cause_ref = v_cause_ref;
  if v_ex is not null and array_length(v_ex, 1) > 0 then
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_ex));
  end if;

  -- ACTIVATION BOUNDARY (§7.1): an ACTIVE signing_key must RESOLVE for the scope.
  -- Fail closed if none resolves — NEVER auto-create one. Most-specific-first:
  -- per_event outranks per_venue outranks global (085:1948-1960), so the key the
  -- door will expect is the key the atom is minted under.
  select k.key_id into v_key
    from kernel.signing_key k
    join catalog.event_session s on s.session_id = v_session
    join catalog.event e on e.event_id = s.event_id
   where k.status = 'active'
     and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     -- scope coherence (E-46): the key must GOVERN this session's scope — an
     -- active-but-wrong-scope key would mint atoms the door cannot verify.
     and (   (k.scope = 'per_event' and k.event_id = s.event_id)
          or (k.scope = 'per_venue' and k.venue_id = e.venue_id)
          or (k.scope = 'global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
   limit 1;
  if v_key is null then
    raise exception 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before any atom is minted';
  end if;
  -- T1: a caller MAY state which key it expects, and a correct caller does
  -- (085:2050 passes the key finalize resolved with this same rule). What it may
  -- not do is CHOOSE one. A disagreement is refused loudly rather than silently
  -- honoured (the old bug) or silently discarded (the other wrong fix).
  if v_key_req is not null and v_key_req <> v_key then
    raise exception 'precondition_failed: signing_key_override_refused — caller supplied % but % resolves for this scope; the mint resolves its own key', v_key_req, v_key;
  end if;

  -- rank-1 Event/Session lock (SPEC_FOUNDATION §5 order; DOOR §818; E-46): the
  -- serial_no counter below is SESSION-scoped while the batch lock is batch-scoped —
  -- without this, same-session/different-batch mints race to the same serial and the
  -- loser aborts on tickets_session_serial_uq. Also mutually excludes
  -- catalog.update_event_session's atoms-issued schedule guard.
  perform 1 from catalog.event_session s where s.session_id = v_session for update;
  if not found then
    raise exception 'not_found: session %', v_session using errcode = 'P0002';
  end if;

  -- lock the batch (C27 choke-point) and verify ctx coherence (E-46): the sold
  -- counter and the atoms must move on the SAME session/ticket_type.
  select b.event_session_id, b.ticket_type_id into v_b_session, v_b_tt
    from venue.inventory_batch b where b.batch_id = v_batch for update;
  if not found then
    raise exception 'not_found: batch %', v_batch using errcode = 'P0002';
  end if;
  if v_b_session <> v_session or v_b_tt <> v_tt then
    raise exception 'precondition_failed: batch_mismatch — batch % does not belong to the ctx session/ticket_type', v_batch;
  end if;

  select coalesce(max(t.serial_no), 0) into v_serial
    from kernel.tickets t where t.event_session_id = v_session;

  for i in 1..v_qty loop
    insert into kernel.tickets (event_session_id, org_id, ticket_type_id, serial_no,
                                current_owner_id, state, credential_version, signing_key_id)
    values (v_session, v_org, v_tt, v_serial + i, v_owner, 'active', 0, v_key)
    returning ticket_atom_id into v_atom;
    v_atoms := v_atoms || v_atom;

    insert into kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity,
                                             cause, cause_ref, actor_identity, command_idempotency_key,
                                             credential_version_after, state_transition)
    values (v_atom, 1, null, v_owner, 'issue', v_cause_ref, v_actor, p_command_key || ':' || v_atom::text,
            0, jsonb_build_object('from', null, 'to', 'active', 'mint_cause', v_cause));
  end loop;

  -- convert to sold. The C27 CHECK (held+sold<=capacity) is the oversell backstop;
  -- 085/finalize releases the matching hold (held -= N) — forward obligation E-40.
  update venue.inventory_batch set sold = sold + v_qty, updated_at = now()
   where batch_id = v_batch;

  insert into venue.inventory_movement (batch_id, movement_kind, delta_held, delta_sold,
                                        cause, cause_ref, actor_identity)
  values (v_batch, 'issue', 0, v_qty, v_cause, v_cause_ref, v_actor);

  -- where an open door episode exists, feed the manifest delta (no-op stub until 086).
  perform venue.append_door_manifest_delta(v_session, v_atoms, 'add', v_cause_ref);

  return jsonb_build_object('status','ok','atom_ids', to_jsonb(v_atoms));
exception when unique_violation then
  -- concurrent identical retry (E-46): the loser's partial work rolled back to the
  -- block savepoint; under a fresh snapshot the winner's committed rows are visible.
  -- Honor the replay contract (the 081 reserve idiom) — any unique_violation NOT
  -- explained by the idempotency anchor re-raises raw.
  select array_agg(l.ticket_atom_id order by l.ticket_atom_id) into v_ex
    from kernel.ticket_ownership_log l
   where l.cause = 'issue' and l.cause_ref = v_cause_ref;
  if v_ex is not null and array_length(v_ex, 1) > 0 then
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_ex));
  end if;
  raise;
end;
$$;
-- No grant statement: CREATE OR REPLACE preserves the frozen 083 ACL for this
-- function, and this slice must not widen or narrow it.


-- ============================================================================
-- END PART 30. Residuals this part creates, recorded so they are not mistaken
-- for oversights (all outside the authored scope of this fragment):
--   R30-1  OPEN — CARRIED AS A NAMED FOLLOW-UP, NOT CLOSED HERE.
--          notify.drain_outbox (092:730) has NO arm for
--          security_payout_destination_changed — its `else` branch counts the
--          envelope `unmapped` and marks it done. §4/§5 close G-2's PRODUCER
--          half; the routing half needs a drainer arm before an owner is
--          actually told, so TODAY A DESTINATION CHANGE STILL REACHES NOBODY.
--          092 is immutable, so the fix is a create-or-replace of
--          notify.drain_outbox in a later part or a follow-up migration.
--          Do not read the emit calls in §4/§5 as evidence that G-2 is closed.
--   R30-2  Nothing calls kernel.sync_org_connect_state yet. Until the
--          account.updated org arm exists (F §3.6(1)), connect_transfers_active
--          is false for every organization and §3 refuses every primary
--          checkout — correct, fail-closed, and total. The webhook arm is a
--          PREREQUISITE OF ACTIVATION, not a follow-up.
--   R30-3  The G-11 out-of-band write trigger (a superuser UPDATE of
--          stripe_connect_account_ref writes no audit row) is not built here.
--   R30-4  The buyer fee is DERIVED, never STORED: no column on venue."order"
--          carries it (A5 forbids folding it into total_minor, and adding a
--          fee column was not in scope). Consequence: the two
--          `idempotency_replay` returns carry no fee fields, because this
--          function cannot reproduce the quote the ORIGINAL call made if
--          fee.buyer_service_bps changed in between. The edge must treat its
--          own PaymentIntent as the record of what it quoted. If a replay ever
--          needs to re-quote, the durable fix is a fee column on venue."order"
--          written at checkout — a schema decision, not a body change.
--   R30-6  RT-A-3's fix requires the onboarding edge to call §2b
--          (kernel.stage_org_connect_ref) between minting the Stripe account
--          and calling §4/§5. AN EDGE THAT SKIPS IT CANNOT BIND AT ALL — it
--          will get `no_pending_connect_ref`. That is the intended failure
--          (fail closed, loudly), but it is a REQUIRED CHANGE to the edge
--          contract, not an optional one, and it must reach the agent building
--          supabase/functions/connect-onboarding/index.ts.
--   R30-7  connect_pending_ref is consumed at the bind and never expires on
--          its own. A staged ref for an org whose onboarding was abandoned sits
--          until the next stage call overwrites it. Harmless — it can only ever
--          authorize binding the account the platform itself minted for that
--          org — but a TTL sweep would be the tidier long-term shape, and it is
--          not in 093.
--   R30-8  G2b refuses EVERY primary checkout until the ruling-B bootstrap
--          signing-key row exists (093 scope item 2, an owner KMS ceremony).
--          That is the intended resting state, not a defect — but it means the
--          ceremony is now a hard blocker on the first sale, visible as
--          `no_active_signing_key` rather than as a post-payment mint failure.
--   R30-5  Nothing in the database stops selling being activated while
--          fee.buyer_service_bps is null; the §3 refusal is per-checkout, so
--          the symptom is "every sale fails closed", not "no sale is
--          mispriced". Part 40 already names setting the rate as a launch
--          precondition on feature.native_issuance_enabled. §3 now makes that
--          precondition self-announcing (`service_fee_unset`) instead of
--          silent, but it does not enforce it at the flag.
-- ============================================================================
