-- ============================================================================
-- 102_credential_signing_context_and_saleable.sql — the credential-sign
-- authority (kernel.get_ticket_signing_context, NEW), the A8a' SALEABLE gate
-- on catalog.publish_event's on_sale transition (body-only re-create of
-- 081:899), and signing.% trust-root dual-control inside
-- catalog.set_platform_config (body-only re-create of 093:6544).
--
-- WHAT THIS MIGRATION IS. Everything here is DARK / unapplied / undeployed:
-- no KMS, no Stripe, no signing key, no secret. Production is at ledger 107
-- (through 092); 093-102 are authored, NOT applied. 093-101 are immutable —
-- both re-creates below are CREATE OR REPLACE, no DROP, no column/table
-- change to anything either migration owns.
--   1. kernel.get_ticket_signing_context(uuid) — NEW. The server-derived
--      signing authority the (DARK, separately-authored) credential-sign edge
--      calls; the edge never picks facts itself (EDGE_FUNCTION_SPEC §3.2/§5).
--   2. catalog.publish_event — body-only re-create of 081:899. Adds the A8a'
--      (ratified reading B, FINAL_ACTIVATION_BLOCKER_RULINGS ITEM (i)) SALEABLE
--      static gate ladder to the on_sale transition ONLY — the SAME four-gate
--      predicate venue.create_primary_checkout already enforces (org / Connect /
--      signing key / fee), evaluated at transition time. Nothing more: tax and
--      inventory policy are DELIBERATELY not gated here (see PART 2 header).
--   3. catalog.set_platform_config — body-only re-create of 093:6544. Adds
--      signing.expected_key_fingerprint / signing.expected_max_not_after to
--      the v_dual prefix test (owner §21 — trust-root config must not be
--      weaker than money/credential-critical config); signing.monitor_enabled
--      stays single-admin both directions (an emergency detection toggle,
--      not a trust-root change).
--
-- SOURCES READ, NOT ASSUMED: 081:899-964 (catalog.publish_event, reproduced
-- verbatim below except the SALEABLE block); 093:6544-6927
-- (catalog.set_platform_config, reproduced verbatim below except the v_dual
-- addition); 093:3960-4110 (venue.create_primary_checkout's own G2/G2b/A5
-- static gate ladder — org_not_active/payout_not_ready/no_active_signing_key/
-- service_fee_unset — the ladder this migration's on_sale gate mirrors, not
-- duplicates: publish-time is STATIC/per-event, checkout stays the DYNAMIC/
-- quote-time re-check and is UNCHANGED here); 093:4899-4976
-- (kernel.issue_ticket_atoms' signing-key RESOLVER — per_event -> per_venue ->
-- global, most-specific-first — the same query shape used at gate #3 below);
-- 079:32-58 (kernel.tickets DDL — current_owner_id, state, resale_state,
-- credential_version, signing_key_id); 083:47-80 (kernel.signing_key DDL);
-- 078:1530 (credential.app_ttl_interval seeded '"4 hours"', public — the TTL
-- source); 099:75-77 (signing.monitor_enabled / signing.expected_key_
-- fingerprint / signing.expected_max_not_after, seeded restricted, no dual
-- control yet — the gap this migration closes for the trust-root pair only);
-- docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md §3.2 (credential-sign
-- contract: owner-only, atom terminal -> 409, no active key -> 500, a
-- listed/locked atom still signs — the door rejects listed/locked at scan,
-- RPC §9.3) and §5 (C33 full spec: kms_handle_ref is a handle not key
-- material; the signer for an atom is resolved by kernel.tickets.
-- signing_key_id, pinned at issue/transfer, NOT by a fresh scope lookup —
-- §5.2 — which is why part 1 below does a direct key_id lookup and NOT the
-- per_event/per_venue/global resolver part 2 uses at publish time).
--
-- THE FROZEN CREDENTIAL MODEL (do not re-derive; restated because it shapes
-- part 1's every line): the ticket credential is STATELESS. The signature is
-- NEVER stored; credential-sign re-derives it on demand from THIS function's
-- output. kernel.tickets.credential_version is the currency mechanism (bumped
-- on custody move/void by the RPCs this migration does not touch); a version
-- bump invalidates every previously issued token via the door's M2 currency
-- check (OFFLINE-VERIFY-v1, EDGE_FUNCTION_SPEC §5.4.3), not by revoking a
-- stored signature. This migration adds NO signature-storage table and NO
-- async batch signer — that would contradict the frozen model.
-- ============================================================================

begin;

-- ============================================================================
-- PART 1 — kernel.get_ticket_signing_context(uuid): the signing authority.
--
-- The (separately-authored, DARK) credential-sign edge calls THIS function
-- and signs exactly what it returns; the edge does not read kernel.tickets or
-- kernel.signing_key itself and does not choose a key. That is the whole
-- point of the function: every fact in the signed token is DB-derived, in one
-- transaction, under one authority check.
--
-- OWNERSHIP GATE. auth.uid() must equal the atom's CURRENT owner, re-read
-- LIVE (never a client claim, never cached). A non-owner, and an atom that
-- does not resolve at all, both fall through the same `v_owner is distinct
-- from v_uid` comparison to the SAME refusal code (`not_owner`) — a
-- nonexistent-atom-shaped probe is indistinguishable from a wrong-owner probe,
-- which is the more defensive of the two honest readings (EDGE_FUNCTION_SPEC
-- §3.2 does not separately contract a `not_found` code; not_owner already
-- covers "you may not have this token" for both cases without inventing one).
--
-- TERMINAL GATE. `state in ('voided','scanned','expired')` refuses
-- `atom_terminal` (EDGE_FUNCTION_SPEC §3.2: "a revoked/voided/scanned atom ->
-- 409 — no live credential for a dead ticket"). resale_state is DELIBERATELY
-- NOT part of this gate: §3.2 states in the same sentence "a listed/locked
-- atom still signs (the door rejects listed/locked at scan, RPC §9.3)", and
-- §5.4.3's OFFLINE-VERIFY-v1 conjunct 3b.v — resale_state = 'none' — is a
-- DOOR admission check, not a signing precondition; a `refund_hold` or
-- `dispute_hold` atom is `state='active'` exactly like `listed`/`locked` and
-- is refused at the SAME door conjunct, for the same reason. Gating signing
-- on resale_state would refuse a credential the door already refuses to
-- admit, for no protective gain, and would contradict §3.2's explicit
-- example. This function therefore reads `state` alone for admissibility.
--
-- PINNED-KEY RESOLUTION, NOT A FRESH LOOKUP. §5.2: "The signer for an atom is
-- resolved by kernel.tickets.signing_key_id (pinned at issue/transfer), NOT
-- by a fresh lookup — so a mid-event rotation does not orphan already-issued
-- credentials." This function looks up EXACTLY that pinned key_id and
-- verifies it is still status='active' and inside its [not_before, not_after)
-- window. If the pinned key is missing, revoked, or rotating ->
-- `signing_key_unavailable` (§3.2: "no active signing key for scope -> 500 +
-- Sentry — an ops-critical gap"). It does NOT re-resolve to a different
-- active key for the event/venue/global scope — that would silently sign
-- under a key the atom was never minted under, which is precisely what §5.2
-- forbids ("mid-event rotation does not orphan already-issued credentials";
-- the old key stays valid for atoms pinned to it until it is revoked).
--
-- NO PRIVATE MATERIAL, EVER. `kms_handle_ref` is an opaque KMS ARN/handle,
-- never key material (C33; 083:47-80 comment, schema §1.7) — it is safe to
-- return to the owner-gated definer path because possessing it grants no
-- signing ability without the KMS IAM role the edge alone holds
-- (EDGE_FUNCTION_SPEC §5.3). `public_key` is the verify key and is already
-- world-readable to `authenticated` on kernel.signing_key directly (PFA-16);
-- returning it here duplicates no exposure. A client cannot reach this
-- function's kms_handle_ref/public_key output without ALSO being the JWT
-- owner the edge forwards — the edge adds no authority beyond the definer
-- check, it only adds network reachability and rate limiting.
--
-- WRITES NOTHING CUSTODIAL. No kernel.tickets column changes, no
-- credential_version bump, no ownership_log row — signing does not mutate
-- custody (§3.2: "No state write — signing does not mutate custody"). The one
-- write is an OPTIONAL, non-secret kernel.admin_audit observability row
-- (atom_id, credential_version, key_id, outcome — reason_code carries the
-- outcome code so a refusal spike is greppable without touching `after`).
--
-- GRANTS. `authenticated` may EXECUTE — the ownership check inside the body
-- IS the access-control gate (identical shape to every other owner-gated
-- SECURITY DEFINER function in this corpus); `anon`/`public` get nothing. The
-- function reads `kms_handle_ref`, which is column-scoped away from every
-- client grant on kernel.signing_key itself (083:114-116) — SECURITY DEFINER
-- is the controlled door that lets an owner-gated caller reach it without
-- widening the table grant.
-- ============================================================================
create or replace function kernel.get_ticket_signing_context(p_ticket_atom_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid;
  v_owner        uuid;
  v_state        text;
  v_session      uuid;
  v_cred_ver     integer;
  v_pinned_key   uuid;
  v_key_status   text;
  v_not_before   timestamptz;
  v_not_after    timestamptz;
  v_public_key   text;
  v_kms_ref      text;
  v_ttl          interval;
  v_issued_at    timestamptz;
  v_exp          timestamptz;
  v_code         text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;

  select t.current_owner_id, t.state, t.event_session_id,
         t.credential_version, t.signing_key_id
    into v_owner, v_state, v_session, v_cred_ver, v_pinned_key
    from kernel.tickets t
   where t.ticket_atom_id = p_ticket_atom_id;

  -- OWNERSHIP GATE — a nonexistent atom (v_owner null) and a real atom owned
  -- by someone else both refuse `not_owner`; the caller learns nothing about
  -- whether the id exists.
  if v_owner is null or v_owner <> v_uid then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'not_owner',
            null, jsonb_build_object('outcome', 'not_owner'));
    return jsonb_build_object('status', 'refused', 'code', 'not_owner');
  end if;

  -- TERMINAL GATE — voided/scanned/expired are dead; listed/locked/
  -- refund_hold/dispute_hold still sign (the door refuses admission, not this
  -- function — see the header note).
  if v_state in ('voided', 'scanned', 'expired') then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'atom_terminal',
            null, jsonb_build_object('outcome', 'atom_terminal', 'state', v_state));
    return jsonb_build_object('status', 'refused', 'code', 'atom_terminal');
  end if;

  -- PINNED-KEY RESOLUTION — the atom's OWN signing_key_id, not a fresh scope
  -- lookup (§5.2). Missing/inactive/out-of-window all collapse to the same
  -- ops-critical refusal.
  select k.status, k.not_before, k.not_after, k.public_key, k.kms_handle_ref
    into v_key_status, v_not_before, v_not_after, v_public_key, v_kms_ref
    from kernel.signing_key k
   where k.key_id = v_pinned_key;

  if v_key_status is null or v_key_status <> 'active'
     or v_not_before > now() or (v_not_after is not null and v_not_after <= now()) then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'signing_key_unavailable',
            null, jsonb_build_object('outcome', 'signing_key_unavailable', 'key_id', v_pinned_key));
    return jsonb_build_object('status', 'refused', 'code', 'signing_key_unavailable');
  end if;

  -- TTL — credential.app_ttl_interval (078:1530, seeded '"4 hours"', public;
  -- the highest-version-wins idiom used throughout this corpus).
  select (c.value #>> '{}')::interval into v_ttl
    from catalog.platform_config c
   where c.key = 'credential.app_ttl_interval'
   order by c.version desc limit 1;

  v_issued_at := now();
  -- v_ttl is guaranteed non-null: 078 seeds credential.app_ttl_interval with a
  -- real value at version 1 (not an owner-STOP null seed) and
  -- catalog.platform_config is append-only, so no reachable post-078 state
  -- leaves it unset. No fallback default is invented here on that basis.
  v_exp := v_issued_at + v_ttl;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'ok',
          null, jsonb_build_object('outcome', 'ok', 'credential_version', v_cred_ver, 'key_id', v_pinned_key));

  return jsonb_build_object(
    'status', 'ok',
    'ticket_atom_id', p_ticket_atom_id,
    'session_id', v_session,
    'credential_version', v_cred_ver,
    'key_id', v_pinned_key,
    'kms_handle_ref', v_kms_ref,
    'public_key', v_public_key,
    'algorithm', null,
    'not_before', v_not_before,
    'not_after', v_not_after,
    'issued_at', v_issued_at,
    'ttl_seconds', extract(epoch from v_ttl)::integer,
    'exp', v_exp,
    'domain', 'SNATCHIT-TICKET-CRED-V1'
  );
end;
$$;

comment on function kernel.get_ticket_signing_context(uuid) is
  'The credential-sign edge''s ONLY source of signing facts (EDGE_FUNCTION_SPEC §3.2/§5). Owner-gated (current_owner_id=auth.uid(), else refused not_owner — indistinguishable from a nonexistent atom); atom_terminal on voided/scanned/expired (listed/locked/refund_hold/dispute_hold still sign — the door refuses admission, not this function); resolves the atom''s PINNED signing_key_id only (never a fresh scope lookup, §5.2), refusing signing_key_unavailable if that key is missing/inactive/out-of-window. Writes no custody; the one write is an optional non-secret admin_audit observability row. NEVER returns private key material — kms_handle_ref is a KMS handle, not a key.';

revoke all on function kernel.get_ticket_signing_context(uuid) from public, anon;
grant execute on function kernel.get_ticket_signing_context(uuid) to authenticated;


-- ============================================================================
-- PART 2 — catalog.publish_event: the A8a' SALEABLE gate (body-only
-- re-create of 081:899-964; every existing check is preserved verbatim).
--
-- OWNER DIRECTION A8a' (2026-09-03), the RATIFIED reading B of
-- FINAL_ACTIVATION_BLOCKER_RULINGS ITEM (i) ("SALEABLE gates the transition"):
-- the on_sale transition MUST additionally refuse unless the organisation
-- satisfies THE SAME Connect-readiness / SALEABLE predicate
-- venue.create_primary_checkout enforces, evaluated at transition time. That
-- ratified text names exactly the create_primary_checkout SALEABLE set — no
-- more — so this migration adds EXACTLY those four gates, IN ORDER, each a
-- stable machine code, fail-closed, on top of every check publish_event
-- already ran:
--   1. org_not_saleable        — event's org status in ('approved','active')
--   2. connect_not_ready       — org's Connect bound AND transfers active
--   3. signing_not_ready       — an ACTIVE signing key resolves for the event
--                                 scope (per_event -> per_venue -> global)
--   4. fee_policy_unset        — fee.buyer_service_bps is set
--
-- DELIBERATELY NOT GATED HERE — two gates an earlier draft of this migration
-- carried were REMOVED as unratified overreach:
--   * TAX. ITEM (ii) reserves the tax enforcement LOCUS as an owner/legal
--     activation decision ("no rate or model is invented here or anywhere in
--     this corpus, and none should be assumed"); the train constraint is a
--     prohibition ("do NOT solve tax; tax stays fail-closed"), NOT a directive
--     to wire a publish-time tax gate. Injecting `tax.policy_resolved` here
--     would silently DECIDE that undecided locus (publish-time) — exactly the
--     unratified-locus move A8a warns against. The system already fails closed
--     on tax (it computes none; client refuses to quote). Left as an owner
--     item — see PFA-PT-7.
--   * INVENTORY POLICY. Not part of create_primary_checkout's SALEABLE set and
--     so not part of ratified A8a' reading B; the inventory hold cap/TTL are
--     DYNAMIC quote-time config that reserve_primary_inventory re-reads live
--     (and that test 145 deliberately exercises UNSET). Gating publish on them
--     exceeds the ratified predicate. Left dynamic, unchanged.
--
-- THE STATIC / DYNAMIC SPLIT (read this before touching either side).
-- `on_sale` means "this event's OWN configuration supports checkout" — every
-- gate above is either this event's own row state (org status, Connect,
-- fee policy) or a scope-resolved signing key that governs this
-- event NOW. It is emphatically NOT a permanent guarantee: a later config
-- change (an admin unsetting fee.buyer_service_bps, revoking the signing key,
-- suspending the org) can regress an already-published event's readiness,
-- and nothing here re-checks it — a RE-PUBLISH would re-run these checks, but
-- publish_event only runs on a forward transition, and on_sale->live->
-- completed never revisits on_sale. That is by design: this gate is a
-- publish-time admission control, not a live invariant.
-- EXPLICITLY NOT GATED HERE — these stay DYNAMIC / quote-time and are
-- unchanged in venue.create_primary_checkout (093:3960-4110), which this
-- migration does not touch:
--   - live inventory remaining / the per-user active-hold cap at quote time
--   - current session timing
--   - the GLOBAL feature.native_issuance_enabled kill-switch
-- Checkout MUST still re-evaluate all of the above and its own org/Connect/
-- signing/fee gates independently; nothing is removed from that ladder by
-- this migration, and nothing here substitutes for it. A publish-time PASS is
-- evidence, not proof, that a later checkout will also pass — checkout is the
-- one that re-observes state at the moment money moves.
--
-- WHY THIS MIRRORS create_primary_checkout'S LADDER RATHER THAN DUPLICATING
-- ITS SEMANTICS: gates 1-3 below are structurally the SAME predicates
-- create_primary_checkout's G2/G2b already enforce at quote time (org
-- status/Connect/signing-key resolution — 093:3982-4076), moved earlier so a
-- promoter discovers a broken configuration when they try to open sales, not
-- when the first buyer's payment succeeds and the mint then fails
-- (093:3997-4009 documents exactly that defect for the Connect/signing-key
-- case). The predicates are copied character-for-character from their
-- checkout-gate source so a future edit to one ladder is an obvious mismatch
-- against the other, not a silent divergence — the same "copied, not
-- approximated" discipline 093 itself used when it aligned issue_ticket_atoms'
-- resolver against finalize_primary_order's.
--
-- Everything else in this function — the auth check, the command-key check,
-- the target_status membership check, the FOR UPDATE event lock, the role
-- check, the forward-transition ladder, the existing empty_inventory check,
-- the UPDATE, the admin_audit row, the return shape — is byte-identical to
-- 081:899-964. Nothing else changes; no object, no column, no grant.
-- ============================================================================
create or replace function catalog.publish_event(
  p_event_id uuid, p_target_status text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid;
  v_org_id       uuid;
  v_venue        uuid;
  v_status       text;
  v_ok           boolean;
  -- 102 / A8a' SALEABLE gate scratch — declared here, used only inside the
  -- on_sale branch below.
  v_org_status   text;
  v_org_ref      text;
  v_org_ready    boolean;
  v_signing_key  uuid;
  v_fee_bps      numeric;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_target_status not in ('announced','on_sale','live','completed') then
    raise exception 'invalid_input: bad target_status % (cancellation is catalog.cancel_event)', p_target_status;
  end if;

  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_status
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;

  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- legal FORWARD transition only (draft→announced→on_sale→live→completed).
  v_ok := (v_status = 'draft'     and p_target_status = 'announced')
       or (v_status = 'announced' and p_target_status = 'on_sale')
       or (v_status = 'on_sale'   and p_target_status = 'live')
       or (v_status = 'live'      and p_target_status = 'completed');
  if not v_ok then
    raise exception 'precondition_failed: illegal_transition (% -> %)', v_status, p_target_status;
  end if;

  -- on_sale requires >=1 ticket_type WITH a batch — no empty on-sale.
  if p_target_status = 'on_sale' then
    if not exists (
      select 1 from venue.ticket_type tt
       join venue.inventory_batch b on b.ticket_type_id = tt.ticket_type_id
      where tt.event_id = p_event_id) then
      raise exception 'precondition_failed: empty_inventory';
    end if;

    -- ---- 102 / A8a' — SALEABLE STATIC GATE LADDER, IN ORDER ---------------

    -- 1. ORG NOT SUSPENDED/UNAPPROVED. Mirrors create_primary_checkout's G2a
    -- (093:3982-4021) character-for-character: a suspended or not-yet-
    -- approved org must not be able to open sales, for the identical reason
    -- checkout refuses it at quote time. X-12 restrictive: unknown authorizes
    -- NOTHING (null status, from a vanished org row, refuses too).
    select o.status, o.stripe_connect_account_ref, o.connect_transfers_active
      into v_org_status, v_org_ref, v_org_ready
      from kernel.organization o
     where o.org_id = v_org_id;
    if v_org_status is null or v_org_status not in ('approved','active') then
      raise exception 'precondition_failed: org_not_saleable — a % organization may not go on sale', coalesce(v_org_status,'missing');
    end if;

    -- 2. CONNECT NOT READY. Mirrors G2 (093:4023-4026): a bound ref with dead
    -- transfer capability is not ready, and a live-looking flag with no ref
    -- has nowhere to send money. Both operands required.
    if v_org_ref is null or coalesce(v_org_ready, false) is not true then
      raise exception 'precondition_failed: connect_not_ready';
    end if;

    -- 3. SIGNING NOT READY. The same resolver query shape as
    -- kernel.issue_ticket_atoms (093:4952-4966) and create_primary_checkout's
    -- G2b (093:4066-4074): most-specific-first, per_event -> per_venue ->
    -- global, active and in-window. A signer trust root must exist for this
    -- event BEFORE sales open — this does not provision one (the KMS
    -- ceremony is a separate, un-parked act this migration does not touch).
    select k.key_id into v_signing_key
      from kernel.signing_key k
     where k.status = 'active'
       and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
       and (   (k.scope = 'per_event' and k.event_id = p_event_id)
            or (k.scope = 'per_venue' and k.venue_id = v_venue)
            or (k.scope = 'global'))
     order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
     limit 1;
    if v_signing_key is null then
      raise exception 'precondition_failed: signing_not_ready — an active signing key must resolve for the event scope before it can go on sale';
    end if;

    -- 4. FEE POLICY UNSET. Mirrors A5 (093:4093-4105): fee.buyer_service_bps
    -- must never fall back to zero — a missing key reads the same as a null
    -- value and both refuse.
    select (c.value #>> '{}')::numeric into v_fee_bps
      from catalog.platform_config c
     where c.key = 'fee.buyer_service_bps'
     order by c.version desc limit 1;
    if v_fee_bps is null then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it';
    end if;

    -- ---- end 102 / A8a' SALEABLE gate ladder ------------------------------
  end if;

  update catalog.event set status = p_target_status, updated_at = now()
   where event_id = p_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.status', 'event', p_event_id, 'publish',
          jsonb_build_object('status', v_status), jsonb_build_object('status', p_target_status));

  return jsonb_build_object('status','ok','event_status',p_target_status);
end;
$$;


-- ============================================================================
-- PART 3 — catalog.set_platform_config: signing.% trust-root dual-control
-- (body-only re-create of 093:6544-6927; everything except the v_dual
-- addition below is byte-identical, reproduced mechanically, not retyped).
--
-- OWNER §21: signing security config must not be weaker than money/
-- credential-critical config. Today `signing.%` matches NO dual-control
-- prefix (093:6742-6746) — any single platform_admin can rewrite the KMS
-- monitor's trust-root expectations in one statement. Two of the three
-- signing.% keys are the trust root itself and get dual control here;
-- signing.monitor_enabled stays single-admin BOTH directions.
--   - signing.expected_key_fingerprint — the SHA-256 the monitor compares
--     every active signing_key's public_key against (099 runbook D5). A
--     single admin silently changing the EXPECTED fingerprint could hide a
--     genuinely substituted key from the monitor that exists to catch
--     exactly that. Trust-root change -> parks for a second platform_admin.
--   - signing.expected_max_not_after — the monitor's ceiling on how far a
--     key's expiry may extend (099 runbook D6). Same reasoning: silently
--     raising the ceiling weakens the monitor's own alarm threshold.
--   - signing.monitor_enabled — DELIBERATELY NOT added. This is the
--     detection kill switch, not the trust root: WALLET §11.5b's reasoning
--     for wallet.apple.enabled applies unchanged — "a kill switch that needs
--     a quorum is not a kill switch." Turning detection OFF should be rare
--     and audited but must not need a second human if an incident requires
--     it turned off fast; turning it back ON (re-arming detection) is a
--     tightening, and WALLET's own polarity table treats re-arming as safe to
--     execute alone too. Neither direction gets dual control here — the
--     separation from the trust-root pair above is deliberate, not an
--     oversight: an emergency detection toggle and a change to what the
--     monitor treats as ground truth are different classes of danger.
--
-- THE CHANGE IS EXACTLY TWO LINES inside the v_dual assignment (093:6742-
-- 6746) — a straightforward widening of the same `or p_key = '...'` shape
-- 093 itself used when it were-cased individual keys into namespaces it did
-- not want to prefix-match wholesale (see e.g. wallet.apple.enabled's own
-- single-key entries in the polarity map below, unchanged). No polarity is
-- declared for either new key: both are non-scalar in practice (a hex string,
-- a timestamp) with no corpus-declared restrictive direction, so — per
-- §20.2.1's third arm, exercised identically for `ticket.%` and `deletion.%`
-- above — they PARK in BOTH directions. That is the intended, most
-- conservative resting state for a trust-root value: arming or changing it AT
-- ALL is the act that takes two humans, not just one direction of change.
-- ============================================================================
create or replace function catalog.set_platform_config(
  p_key text, p_value jsonb, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_cur_ver    integer;
  v_cur_val    jsonb;
  v_visibility text;
  v_dual       boolean;
  v_polarity   text;
  v_restrictive boolean;
  v_old_num    numeric;
  v_new_num    numeric;
  v_span       interval;
  v_skew       interval;
  v_ttl        interval;
  v_probe      interval;                 -- 093: interval type guard scratch
  v_request_id uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- reason_code is mandatory for EVERY key, not only the money namespaces.
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- platform_support and platform_risk hold NO authority here: risk holds
  -- hold_payout, not the thresholds that decide when a payout needs approval.
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required'
      using errcode = '42501';
  end if;
  if p_value is null then
    raise exception 'precondition_failed: bad_value — use the JSON null literal';
  end if;

  -- APPR-SUBJ-1: resolve the subject under its own lock, in the same transaction
  -- that writes the row. THIS FUNCTION CREATES NO NEW KEY — a key that no code
  -- reads is a config row that lies (078 seeds every key).
  select c.version, c.value, c.visibility
    into v_cur_ver, v_cur_val, v_visibility
    from catalog.platform_config c
   where c.key = p_key
   order by c.version desc
   limit 1
     for update;
  if v_cur_ver is null then
    raise exception 'precondition_failed: unknown_key %', p_key;
  end if;

  if v_cur_val = p_value then
    return jsonb_build_object('status','noop_replay','key',p_key,
                              'version',v_cur_ver,'request_id',null);
  end if;

  -- RPC §20.2.1 precondition: "p_value passes the key's declared TYPE/RANGE".
  -- TYPE: a key never changes shape. The seeded row is the type witness; a key
  -- seeded absent-by-design (JSON null) has no witness yet and accepts the first
  -- typed value, after which the witness exists.
  if jsonb_typeof(v_cur_val) <> 'null'
     and jsonb_typeof(p_value) <> jsonb_typeof(v_cur_val) then
    raise exception 'precondition_failed: bad_value — % is %, not %',
      p_key, jsonb_typeof(v_cur_val), jsonb_typeof(p_value);
  end if;
  -- RANGE: enforced for every key whose admissible range the frozen corpus
  -- actually states. A key with no stated range is not invented one here.
  if p_key = 'authn.money_role_maturity_hours'
     and jsonb_typeof(p_value) = 'number'
     and ((p_value #>> '{}')::numeric < 24 or (p_value #>> '{}')::numeric > 72) then
    -- RLS MD-14 / RPC §1.1e: "the admissible range as 24-72 hours".
    raise exception 'precondition_failed: bad_value — authn.money_role_maturity_hours is outside MD-14''s admissible 24-72 hours';
  end if;
  if p_key = 'notify.announcement_hold_seconds'
     and jsonb_typeof(p_value) = 'number'
     and (p_value #>> '{}')::numeric < 120 then
    -- NOTIF §7.5: "seed 300 s, FLOOR 120 s".
    raise exception 'precondition_failed: bad_value — notify.announcement_hold_seconds is below NOTIF §7.5''s 120 s floor';
  end if;
  if p_key = 'authn.money_action_required_aal'
     and jsonb_typeof(p_value) = 'string'
     and (p_value #>> '{}') not in ('aal1','aal2') then
    raise exception 'precondition_failed: bad_value — authn.money_action_required_aal must be aal1|aal2';
  end if;
  if p_key = 'refund.scanned_atom_policy'
     and jsonb_typeof(p_value) = 'string'
     and (p_value #>> '{}') not in ('refuse','platform_review') then
    raise exception 'precondition_failed: bad_value — refund.scanned_atom_policy must be refuse|platform_review';
  end if;

  -- 093 — INTERVAL TYPE GUARD (the second of this item's two changes).
  -- THE HOLE IT CLOSES: the TYPE witness above is skipped when the current value
  -- is JSON null (078:1111-1114 — "a key seeded absent-by-design has no witness
  -- yet and accepts the first typed value"). Every owner-STOP key in 093 is
  -- seeded null, so each one accepts ANY json type on its first write. For an
  -- interval-consumed key that is silent and severe: set_platform_config(
  -- 'ticket.expiry_grace','24') is accepted, and '24'::interval is TWENTY-FOUR
  -- SECONDS, not 24 hours (verified: select '24'::interval => 00:00:24). The
  -- sweep at 079:475 then terminal-izes every atom on every ended session within
  -- one cron tick, and `expired` is terminal and excluded from cancel_event's
  -- refund cascade. The typo reads as correct to a human, which is what makes it
  -- the dangerous shape.
  -- THE GUARD: for keys the corpus consumes with ::interval, require a jsonb
  -- STRING that actually parses. A bare number can no longer be stored.
  -- MAINTENANCE NOTE: this is a list, in the same explicit per-key style as the
  -- four RANGE checks above, and it must gain any future interval-typed key. The
  -- root cause is the missing type witness on a null seed, not the list.
  if p_key in ('ticket.expiry_grace','inventory.hold_ttl_interval',
               'payout.settlement_maturity_interval','door.schedule_move_grace_interval',
               'notify.delivery_lease_interval',
               'credential.wallet_exp_skew','credential.wallet_default_span',
               'credential.app_ttl_interval','wallet.apple.cert_expiry_warn_interval',
               'door.implicit_freeze_offset_interval','door.manifest_ttl_interval',
               'door.manifest_early_open_window','door.max_override_interval',
               'door.session_ttl_interval','door.session_absolute_max_interval',
               'door.session_post_session_grace')
     and jsonb_typeof(p_value) <> 'null' then
    if jsonb_typeof(p_value) <> 'string' then
      raise exception 'precondition_failed: bad_value — % is interval-typed and needs a JSON STRING such as "24 hours"; a bare number is read as SECONDS', p_key;
    end if;
    begin
      v_probe := (p_value #>> '{}')::interval;
    exception when others then
      v_probe := null;
    end;
    if v_probe is null then
      raise exception 'precondition_failed: bad_value — % must be a parseable interval literal', p_key;
    end if;
  end if;

  -- H2 — THE MIRROR GUARD: a key consumed as a NUMBER OF HOURS must be a JSON
  -- NUMBER. The guard above stops a number reaching an interval-typed key; this
  -- one stops a STRING reaching an hours-typed key, and it exists because the
  -- two failure modes are neighbours on the keyboard. `ticket.expiry_grace`
  -- REQUIRES the string form '"72 hours"', so '"720 hours"' is the natural typo
  -- on its sibling deletion key — and before H2's rewrite of
  -- kernel.deletion_blockers_money that one append would have raised inside the
  -- deletion blocker for EVERY identity, forever (platform_config is append-only,
  -- and 085's read cast the value in an ordered target list, so the LIMIT could
  -- not protect it). 10j is now immune by construction; this refuses the value at
  -- the door as well, so the bad version is never written in the first place.
  if p_key in ('deletion.post_event_hold_hours')
     and jsonb_typeof(p_value) <> 'null'
     and jsonb_typeof(p_value) <> 'number' then
    raise exception 'precondition_failed: bad_value — % is a NUMBER OF HOURS and needs a JSON number such as 720; "720 hours" is the interval spelling and belongs to ticket.expiry_grace', p_key;
  end if;

  -- 093 / ruling A5 — `fee.%` ADDED. This is the ONLY change to this function.
  -- WHY: fee.buyer_service_bps is the final clause of the SALEABLE chain — the
  -- statement that sets it moves the platform from "cannot sell" to "selling",
  -- and a gate audit proved three preconditions behind it are unenforced (no
  -- active signing key is required at checkout, refund executability is checked
  -- nowhere, and no tax model exists at all). A single administrator crossing
  -- that line in one un-parked statement is exactly the shape the owner banned:
  -- a config value acting as a hidden feature flag for incomplete logic.
  -- WHY THE PREFIX AND NOT A RENAME: the settlement maturity key was fixed by
  -- renaming it into `payout.%`; that is REJECTED here because this is not a
  -- payout key and the rename would reintroduce the misleading semantics the
  -- maturity rename removed. The prefix list is a policy statement about which
  -- NAMESPACES are money-critical, and buyer-facing pricing plainly is.
  -- 093 / H2 — `deletion.%` ADDED, for the same reason and by the same test.
  -- deletion.post_event_hold_hours decides when an identity becomes
  -- IRREVERSIBLY tombstoned while money obligations on their orders can still
  -- arise. G7 P1-4 executed the gap: as one platform_admin with an aal2 claim,
  -- `set_platform_config('deletion.refund_possible_window_hours', …)` returned
  -- `{"status":"ok"}` with no second human, and that single statement is what
  -- turned P0-3 from a design flaw into a one-statement act. `deletion.%`
  -- matched none of the prefixes below. It does now.
  -- WHY THE PREFIX AND NOT A RENAME INTO `refund.%`/`payout.%`: the same
  -- argument the `fee.%` note above makes. This is not a refund key and not a
  -- payout key; filing it under either would restore exactly the collapsed
  -- semantics — refund ELIGIBILITY vs payout MATURITY vs DELETION SAFETY — that
  -- G2's rename and H2's re-anchor both exist to take apart.
  -- 093 / H2 — `ticket.%` ADDED. The LAST destructive key family outside this list.
  -- The evidence is G1 §7 and the seed comment at the top of this file, and it is
  -- stronger than the case for several keys already here: setting
  -- `ticket.expiry_grace` wrongly does not DEGRADE, it writes the TERMINAL label
  -- `expired` across every atom on every ended session within one cron tick
  -- (079:456, cron */2 at 079:799-803) — and 088:1682/1735/1783 then EXCLUDE
  -- expired atoms from catalog.cancel_event's refund cascade, so the holder loses
  -- the ticket AND the money. There is no exit: no shipped function writes
  -- kernel.tickets.state back out of `expired`. A single administrator must not be
  -- able to cross that boundary alone, for the same reason `fee.%` (ruling A5) and
  -- `deletion.%` (H2) were added — an irreversible money or identity boundary takes
  -- two humans.
  -- NOTE the two controls are INDEPENDENT and both still apply. The interval TYPE
  -- guard above already refuses a bare number on this key (it is first in that
  -- list), which is what stops the '24' => TWENTY-FOUR SECONDS cast; dual control
  -- is the separate question of who may set a WELL-TYPED but wrong value. Neither
  -- shadows the other: a mistyped value is refused outright and never parks, and a
  -- well-typed one parks.
  -- `ticket.%` has NO entry in the polarity map below, so it takes §20.2.1's third
  -- arm — not comparable => PARK — in BOTH directions. That is intended and is the
  -- correct default here: the corpus declares no restrictive direction for a grace
  -- that is destructive when short and merely slow when long, so failing toward the
  -- approver is the honest reading.
  -- 102 / owner §21 — `signing.expected_key_fingerprint` and
  -- `signing.expected_max_not_after` ADDED (single-key, not a prefix — see the
  -- header note above for why signing.monitor_enabled is deliberately excluded).
  v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like 'authn.%'
         or p_key like 'comp.%'   or p_key like 'wallet.%' or p_key like 'credential.%'
         or p_key like 'door.session\_%' or p_key like 'fee.%'
         or p_key like 'deletion.%' or p_key like 'ticket.%'
         or p_key = 'signing.expected_key_fingerprint' or p_key = 'signing.expected_max_not_after';

  -- The declared polarity map. A key absent from it has NO declared polarity and
  -- therefore parks (when dual-controlled). Booleans, enums and every non-scalar
  -- are incomparable by construction and park for the same reason.
  v_polarity := case
    -- LOWER IS RESTRICTIVE: every one of these is a CEILING or a span whose
    -- reduction narrows what may happen without a second human.
    when p_key in ('refund.org_auto_execute_max_minor',
                   'refund.org_dual_control_max_minor',
                   'refund.buyer_self_service_max_minor',
                   'refund.buyer_self_service_window_hours',
                   'refund.platform_support_max_minor',
                   'payout.request_auto_max_minor',
                   -- payout.dual_control_min_minor is the amount ABOVE WHICH a
                   -- payout parks (MONEY §7.2), so RAISING it REMOVES payouts
                   -- from dual control. T-RPC-CFG-01 names this exact key:
                   -- "raising ... parks and inserts no version; lowering it
                   -- executes". It is a ceiling in disguise, not a floor.
                   'payout.dual_control_min_minor',
                   'comp.per_staff_step_up_max_units',
                   'authn.money_action_max_age_seconds',
                   'door.session_ttl_interval',
                   'door.session_absolute_max_interval',
                   'door.session_post_session_grace',
                   'credential.wallet_exp_skew',
                   'credential.wallet_default_span',
                   'credential.app_ttl_interval')          then 'lower_is_restrictive'
    -- HIGHER IS RESTRICTIVE: a longer cooldown, a longer probation and a longer
    -- maturity floor each narrow what may happen (RPC §20.2.1: "a longer
    -- probation"). comp.per_staff_step_up_window_hours is DELIBERATELY ABSENT:
    -- the window is the COUNTING period of the C39 insider-fraud gate, so
    -- shortening it counts fewer units and fires step-up LESS often — the
    -- corpus declares a direction only for its _max_units half (RLS §11.1
    -- AUTHZ-M8), so this key has NO declared polarity and takes §20.2.1's third
    -- arm: not comparable => PARK. Failing toward the approver is the whole
    -- point of that arm.
    -- H2: deletion.post_event_hold_hours joins this arm, and the direction is
    -- forced by irreversibility, not by taste. A LONGER hold blocks more
    -- tombstones, and a tombstone is TERMINAL — DSM has no exit from ERASED and
    -- the corpus carries no force-tombstone verb to compensate an over-long
    -- hold. Too long costs erasure LATENCY (recoverable, and visible in
    -- deletion_block_reason, which now carries the maturity instant). Too short
    -- destroys a live counterparty. So RAISING it executes in one statement — an
    -- operator must be able to tighten during an incident — and SHORTENING it,
    -- which is what makes advance-purchase buyers erasable sooner, parks for a
    -- second platform_admin. Note the seeded value is JSON null, so the FIRST
    -- set is not number-to-number and parks regardless: arming this key at all
    -- is the dangerous act and it takes two humans.
    when p_key in ('payout.destination_cooldown_hours',
                   'payout.destination_probation_days',
                   'authn.money_role_maturity_hours',
                   'deletion.post_event_hold_hours')       then 'higher_is_restrictive'
    -- FALSE IS RESTRICTIVE: a kill switch. WALLET §11.5b — "Setting
    -- wallet.apple.enabled := false ... needs ONE admin and no approval round.
    -- A kill switch that needs a quorum is not a kill switch."
    when p_key = 'wallet.apple.enabled'                    then 'false_is_restrictive'
    -- HIGHER AAL IS RESTRICTIVE: RPC §20.2.1 enumerates "a higher required AAL"
    -- among the restrictive directions by name, so raising it during a
    -- session-theft incident must execute in one transaction.
    when p_key = 'authn.money_action_required_aal'         then 'aal_higher_is_restrictive'
    -- 102: signing.expected_key_fingerprint / signing.expected_max_not_after
    -- are DELIBERATELY ABSENT from this map. Neither has a corpus-declared
    -- restrictive direction (a fingerprint is not orderable at all; a
    -- ceiling timestamp has no stated policy for which direction is the
    -- tightening one), so both take §20.2.1's third arm and park in BOTH
    -- directions — arming or changing the trust root at all is the act that
    -- needs a second human, same posture as `ticket.%` above.
    else null
  end;

  v_restrictive := false;
  if v_polarity is not null
     and jsonb_typeof(v_cur_val) = 'number' and jsonb_typeof(p_value) = 'number' then
    v_old_num := (v_cur_val #>> '{}')::numeric;
    v_new_num := (p_value  #>> '{}')::numeric;
    v_restrictive := case v_polarity
                       when 'lower_is_restrictive'  then v_new_num < v_old_num
                       when 'higher_is_restrictive' then v_new_num > v_old_num
                     end;
  elsif v_polarity = 'false_is_restrictive'
     and jsonb_typeof(p_value) = 'boolean' then
    -- Pulling the switch is a tightening; flipping it on is the mandatory-
    -- dual-control write WALLET §11.5 describes.
    v_restrictive := (p_value = 'false'::jsonb);
  elsif v_polarity = 'aal_higher_is_restrictive'
     and jsonb_typeof(v_cur_val) in ('string','null') and jsonb_typeof(p_value) = 'string' then
    -- aal1 < aal2. An absent current value is the weakest state, so ANY named
    -- level is a tightening against it.
    v_restrictive := case
      when p_value #>> '{}' not in ('aal1','aal2') then false      -- unknown => park
      when jsonb_typeof(v_cur_val) = 'null'        then true
      else (p_value #>> '{}') > (v_cur_val #>> '{}')
    end;
  elsif v_polarity in ('lower_is_restrictive','higher_is_restrictive')
     and jsonb_typeof(v_cur_val) = 'string' and jsonb_typeof(p_value) = 'string' then
    begin
      v_restrictive := case v_polarity
        when 'lower_is_restrictive'
          then (p_value #>> '{}')::interval < (v_cur_val #>> '{}')::interval
        when 'higher_is_restrictive'
          then (p_value #>> '{}')::interval > (v_cur_val #>> '{}')::interval
      end;
    exception when others then
      v_restrictive := false;                       -- not comparable => park
    end;
  end if;

  -- The cross-config invariant (door §10.6): a Wallet token may never outlive the
  -- offline window any manifest could authorise. Validated whenever EITHER side
  -- changes, and the write is rejected otherwise. Evaluated INLINE rather than in
  -- a helper: a helper would be a catalog object the frozen closed world does not
  -- carry, and package parity is EXTRA = 0.
  if p_key in ('credential.wallet_default_span','credential.wallet_exp_skew',
               'door.manifest_ttl_interval') then
    begin
      select coalesce(
               case when p_key = 'credential.wallet_default_span' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'credential.wallet_default_span'
                 order by c.version desc limit 1)),
             coalesce(
               case when p_key = 'credential.wallet_exp_skew' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'credential.wallet_exp_skew'
                 order by c.version desc limit 1)),
             coalesce(
               case when p_key = 'door.manifest_ttl_interval' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'door.manifest_ttl_interval'
                 order by c.version desc limit 1))
        into v_span, v_skew, v_ttl;
    exception when others then
      v_span := null; v_skew := null; v_ttl := null;    -- unparseable => reject
    end;
    -- An absent operand cannot be shown to satisfy the invariant, so it does not.
    if v_span is null or v_skew is null or v_ttl is null or v_span + v_skew > v_ttl then
      raise exception 'precondition_failed: bad_value — wallet_default_span + wallet_exp_skew must not exceed door.manifest_ttl_interval';
    end if;
  end if;

  if v_dual and not v_restrictive then
    insert into kernel.approval_request
           (action, required_approver_class, subject_kind, subject_id, org_id,
            payload, config_versions, requested_by, state, reason_code,
            expires_at, command_idempotency_key)
    values ('config.set_money_key', 'platform_admin', 'config_key',
            md5(p_key)::uuid, null,
            jsonb_build_object('key', p_key, 'proposed_value', p_value,
                               'current_value', v_cur_val),
            jsonb_build_object(p_key, v_cur_ver),
            v_uid, 'pending', trim(p_reason_code),
            now() + interval '72 hours', p_command_key)
    returning request_id into v_request_id;

    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'config.money_key_proposed', 'config_key', md5(p_key)::uuid,
            trim(p_reason_code),
            jsonb_build_object('key', p_key, 'version', v_cur_ver, 'value', v_cur_val),
            jsonb_build_object('key', p_key, 'value', p_value));

    -- version UNCHANGED: the UI must say "waiting for a second approver",
    -- never "saved".
    return jsonb_build_object('status','parked','key',p_key,
                              'version',v_cur_ver,'request_id',v_request_id);
  end if;

  -- Direct path. visibility is COPIED FORWARD: set_platform_config may not change
  -- it — a function that can flip a key to public is a function that can publish
  -- the ceilings.
  insert into catalog.platform_config (key, version, value, visibility)
  values (p_key, v_cur_ver + 1, p_value, v_visibility);

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'config.change', 'config_key', md5(p_key)::uuid, trim(p_reason_code),
          jsonb_build_object('key', p_key, 'version', v_cur_ver, 'value', v_cur_val),
          jsonb_build_object('key', p_key, 'version', v_cur_ver + 1, 'value', p_value));

  return jsonb_build_object('status','ok','key',p_key,
                            'version',v_cur_ver + 1,'request_id',null);
end;
$$;


commit;
