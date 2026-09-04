-- ============================================================================
-- 095_payout_state_machine_recovery.sql — the payout lifecycle's missing edges.
--
-- WHAT THIS MIGRATION IS. Five closures on the settlement→payout state machine
-- that 085/087/093 left open. Every one of them is ADDITIVE: no object created
-- by 000-093 is dropped, no status CHECK is widened, no grant is broadened, no
-- existing function body is replaced. The migration activates nothing — every
-- verb below either REFUSES something that used to be permitted, or offers a
-- recovery path that ends in the SAME authorization ladder that already exists.
--
-- WHAT IT IS NOT. It does not loosen kernel.payout.status. 'failed' stays
-- absorbing at kernel.mark_payout_transfer_state (085:1668) — verified by
-- execution on a fresh replay, not by reading:
--     submitted → failed    ⇒ ok
--     failed    → paid      ⇒ precondition_failed: payout_state_backwards
--     failed    → reversed  ⇒ precondition_failed: payout_state_backwards
--     failed    → submitted ⇒ invalid_input: takes paid|failed|reversed
-- The recovery below is therefore a NEW VERB with its own authority model, not
-- a widened transition.
--
-- ── AGENT E CLAIM BLOCK (095 — Agent E's sections, renumbered off 094 after kernel.organization_obligation claimed it) ──
--   E-1  kernel.guard_payout_org_payable()      + tg_payout_org_payable_guard
--   E-2  kernel.rearm_failed_payout(uuid, text, text)
--   E-3  kernel.settlement_maturity_hold_codes()
--        kernel.retry_held_payout(uuid, uuid, text)
--   E-4  kernel.hold_payout_transfer_reversed(uuid, text, integer, integer,
--                                             jsonb, text)
--   E-5  kernel.guard_settlement_forward_only() + tg_settlement_forward_only
--   E-6  kernel.settlement_unbooked_refund_exposure(uuid)
--        kernel.get_payout_execution_context(uuid)  ← 093 slice 10n RE-CREATED,
--        body only, ONE changed expression. If another agent also needs 10n,
--        this is the collision to resolve.
--   No other object in this file is Agent E's. Nothing here touches
--   kernel.mark_payout_transfer_state, kernel.request_org_payout,
--   kernel.close_settlement, kernel.settlement_payout_maturity,
--   kernel.release_payout or kernel.hold_payout — all six are read as
--   dependencies and left byte-for-byte as 085/087/093 wrote them.
--
-- Sources read, not assumed: 085 PART 3 (kernel.payout, the four-column hold
--   overlay MB-2a), 085 PART 9 (the hold/release pair, Control-5), 085 PART 11
--   (mark_payout_transfer_state), 087 PART 2/3 (venue.settlement +
--   settlement_line), 087:360 (venue.on_payout_settled), 093 slice 10d/10j/10k/
--   10m/10n/10o/10p/10q, 077:111 (kernel.organization.status CHECK),
--   supabase/functions/payout-execute/executor.ts (the rule that the executor
--   never writes 'failed'), docs/phase2/_impl/J5_payout_state_machine.md.
-- ============================================================================
begin;

set local lock_timeout = '3s';

-- ============================================================================
-- E-1 — kernel.guard_payout_org_payable: A SUSPENDED ORGANIZATION CANNOT HAVE
--   A PAYOUT AUTHORIZED AGAINST IT.
--
--   THE DEFECT. kernel.request_org_payout (093 slice 10k) checks the org's
--   ROLES, the SoD-1 setter exclusion, money-grant maturity, aal2, the
--   destination cool-down and the destination's presence — but never
--   kernel.organization.status. An org that has been SUSPENDED therefore walks
--   the whole ladder and reaches status='submitted' with a pinned destination
--   and, above the dual-control threshold, a consumed approval. Only later does
--   kernel.get_payout_execution_context (10n) refuse it as 'org_not_active',
--   and 10o then de-authorizes it back to pending+held. So the money never
--   moves — but the AUTHORIZATION advanced against an org the platform had
--   suspended, the approval was spent, and a human must now unwind it. The
--   correct state must fail BEFORE authorization advances, not after.
--
--   WHY A TRIGGER AND NOT A LINE IN 10k'S BODY. Three reasons, in order of
--   weight. (1) The invariant is a property of the ROW, not of one caller:
--   pending→submitted is "this payout is now authorized to move money", and
--   there is exactly one place that fact becomes true regardless of which verb
--   makes it true. A body check binds one writer; the trigger binds every
--   writer, including a future one. (2) 093 is a generated artifact assembled
--   from reviewed slices (scripts/assemble_093.sh + the CI integrity gate), so
--   re-creating a 200-line body here to add six lines is a large, unreviewable
--   diff for a small invariant. (3) It cannot be bypassed by any principal that
--   can reach kernel.payout at all — service_role has no DML grant on the table
--   (PFA-21), so the only writers are SECURITY DEFINER functions, and the
--   trigger fires inside every one of them.
--
--   THE PAYABLE SET IS 10n'S, VERBATIM: status in ('approved','active').
--   kernel.organization.status admits exactly five members (077:111):
--     applied    — the org exists but nobody has approved it       ⇒ NOT payable
--     approved   — approved, not yet activated                     ⇒ payable
--     active     — approved and operating                          ⇒ payable
--     suspended  — the platform stopped it (reason mandatory)      ⇒ NOT payable
--     closed     — terminal (077:920 refuses every exit)           ⇒ NOT payable
--   The set is copied from kernel.get_payout_execution_context (10n) and
--   kernel.hold_payout_destination_changed (10o) rather than re-derived, so the
--   three sites cannot disagree about what "payable" means. If that set ever
--   changes it must change in all three, and the pgTAP suite asserts the
--   agreement over ALL FIVE members.
--
--   WHAT IT DOES NOT DO. It does not read the Connect capability, the
--   destination, maturity or the cool-down: those already have their own gates
--   at 10k and 10n, and duplicating them here would create a second definition
--   that can drift. It does not touch a pending payout, a held payout, an
--   identity payout, or any UPDATE that leaves status alone — a hold, a
--   release, a de-authorization and a state sync all pass through untouched.
-- ============================================================================
create or replace function kernel.guard_payout_org_payable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  -- The guarded event is ONE edge: "this payout becomes authorized to move
  -- money". Everything else is somebody else's business.
  if new.status <> 'submitted' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'submitted' then
    return new;   -- already authorized; this UPDATE is a hold/ref/overlay write
  end if;
  if new.payee_kind <> 'organization' or new.payee_org_id is null then
    return new;   -- the identity rail has no organization to be suspended
  end if;

  select o.status into v_status
    from kernel.organization o
   where o.org_id = new.payee_org_id;

  if v_status is null then
    raise exception 'precondition_failed: organization_not_found — payout % names an organization that does not exist', new.payout_id
      using errcode = 'P0001';
  end if;
  -- 10n / 10o vocabulary, deliberately the same code string, so an operator who
  -- has seen this refusal at the executor recognises it at the request.
  if v_status not in ('approved','active') then
    raise exception 'precondition_failed: org_not_active — organization % is %; a payout cannot be authorized against it', new.payee_org_id, v_status
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

comment on function kernel.guard_payout_org_payable() is
  'BEFORE INSERT/UPDATE on kernel.payout: refuses the pending->submitted authorization edge when the payee organization is not in (approved, active). The same payable set kernel.get_payout_execution_context and kernel.hold_payout_destination_changed use, evaluated BEFORE the authorization advances instead of after.';

-- 066/077-F1 discipline: a trigger function is not a callable verb. Strip the
-- default PUBLIC EXECUTE so no principal — including service_role, which
-- inherits through PUBLIC — can invoke it out of band. The trigger itself is
-- unaffected: PostgreSQL checks EXECUTE at CREATE TRIGGER, never at fire time.
revoke all on function kernel.guard_payout_org_payable() from public, anon, authenticated;

drop trigger if exists tg_payout_org_payable_guard on kernel.payout;
create trigger tg_payout_org_payable_guard
  before insert or update on kernel.payout
  for each row execute function kernel.guard_payout_org_payable();


-- ============================================================================
-- E-2 — kernel.rearm_failed_payout: THE ONLY EXIT FROM 'failed'.
--
--   THE DEFECT. kernel.mark_payout_transfer_state permits submitted→paid|failed
--   and paid→reversed and nothing else, kernel.request_org_payout only ever
--   selects a payout in ('pending','submitted'), and kernel.close_settlement is
--   forward-only with `on conflict (idempotency_key) do nothing`, so it can
--   never re-mint. A settlement payout that reaches 'failed' — for ANY reason,
--   including a transient Stripe error — is therefore stranded permanently and
--   the venue's money is destroyed as a ledger fact. The payout executor
--   mitigates this by structurally refusing to write 'failed'
--   (PAYOUT_STATE_SYNC_TARGETS has one member), but a mitigation in one client
--   is not a lifecycle: the verb is granted to service_role and any other
--   caller, present or future, can still write it.
--
--   THE SHAPE OF THE FIX. A re-arm is NOT an authorization. It returns the
--   payout to the state it was in BEFORE anyone authorized it — 'pending' — and
--   engages the hold overlay so that nothing can advance it until a human
--   deliberately releases it. Money then moves only by walking the ENTIRE
--   existing ladder again:
--
--     failed
--       │  kernel.rearm_failed_payout        platform_risk|platform_admin, aal2
--       ▼
--     pending + held/'failed_rearm' (held_by = the re-armer)
--       │  kernel.release_payout (085:807)   platform_risk|platform_admin
--       ▼
--     pending + none
--       │  kernel.request_org_payout (10k)   org_owner|org_finance, aal2,
--       ▼                                    SoD-1, money-grant maturity,
--     submitted                              cool-down, destination probation,
--                                            the G2 maturity conjunction, and
--                                            dual control above the threshold
--
--   THE PROPERTIES, AND WHERE EACH IS PROVED.
--
--   · NO DOUBLE PAYOUT. Two independent stops. (a) This verb REFUSES any payout
--     carrying a stripe_transfer_ref. A ref means a Stripe Transfer object
--     exists for this payout; whether its money moved is a Stripe fact this
--     database cannot establish, and re-arming would offer a second transfer to
--     the same destination. (b) For a ref-less failure — the create call errored,
--     or its response was lost — the executor's `reconcile` mode reads
--     GET /v1/transfers?transfer_group=payout_<id> BEFORE any create and adopts
--     what it finds (executor.ts planReconcile), and kernel.claim_payouts_for_
--     execution (10p) selects the mode from the age of the FIRST
--     payout.execute_claim audit row — which a re-arm does not erase, because
--     kernel.admin_audit is append-only. A re-armed payout is therefore
--     re-executed in reconcile mode, not create mode.
--
--   · NO REPLAY AMBIGUITY. A second re-arm of an already-re-armed payout
--     returns noop_replay (it is recognised by the exact triple
--     pending/held/'failed_rearm'), and a re-arm of anything that is not
--     'failed' raises. There is no input for which the outcome depends on
--     arrival order.
--
--   · NO ARBITRARY AMOUNT MUTATION. The UPDATE writes six columns and they are
--     enumerated in the statement: status, hold_state, hold_reason_code,
--     held_by, held_at, updated_at. amount_minor, currency, cause, cause_ref,
--     payee_kind, payee_org_id, idempotency_key, source_transaction_ref and
--     stripe_transfer_ref are not in the statement at all. The obligation is
--     exactly the one kernel.close_settlement minted.
--
--   · THE ORIGINAL DESTINATION AUTHORIZATION IS PRESERVED. destination_ref
--     (10j, pinned at pending→submitted) is NOT cleared and NOT rewritten here.
--     It keeps naming the account the money was authorized against, so the
--     audit trail of a failed attempt stays readable. Re-pinning is
--     request_org_payout's job and happens only when a human re-authorizes.
--
--   · DESTINATION DIVERGENCE STILL RE-HOLDS. If the org's destination changed
--     while the payout sat failed, the re-request meets the §10.3 probation arm
--     (a destination change inside payout.destination_probation_days with no
--     payout paid since ⇒ probation_hold) and any parked approval naming the old
--     destination is marked 'stale' and never honoured (E-85). After the
--     advance, a divergence between the fresh pin and the org's current ref is
--     still caught by 10n and de-authorized by 10o. None of that machinery is
--     touched here; the re-arm simply cannot bypass it, because it never
--     produces 'submitted'.
--
--   · A SERVICE WORKER CANNOT SELF-AUTHORIZE MONEY. The verb is granted to
--     `authenticated` and EXPLICITLY REVOKED from service_role (the same hard
--     edge 085 puts on kernel.record_money_denial), and its authority test is
--     kernel.is_platform, which reads auth.uid() — a claims-less service session
--     fails it even if a grant were somehow restored. And a re-armed payout is
--     'pending', which kernel.claim_payouts_for_execution does not select
--     (it requires status='submitted' and hold_state='none'), so no worker can
--     see it, let alone execute it.
--
--   · AUDIT TRAIL. One kernel.admin_audit row, action 'payout.rearm', carrying
--     the before/after state, the operator's reason code and the failure the
--     row is being recovered from. admin_audit is append-only and
--     UPDATE/DELETE-revoked (077:261), so the re-arm cannot be erased.
--
--   · aal2 AND MULTI-PARTY CONTROL. The re-armer is platform_risk or
--     platform_admin on a step-up session. That principal cannot move the money
--     alone: only an ORG money-role holder can produce 'submitted', and only
--     from a session that passes SoD-1, money-grant maturity, aal2, the
--     cool-down, probation, the G2 maturity conjunction and — above
--     payout.dual_control_min_minor — a SECOND org approver. Two authority
--     domains and, above the threshold, three humans.
--
--   THE ONE THING IT DOES NOT RECOVER, NAMED. A 'failed' payout that DOES carry
--   a stripe_transfer_ref stays stranded. Recovering it means asserting
--   something about a Stripe Transfer that this database cannot observe, and
--   the honest primitives for it already exist in the ledger's vocabulary
--   (mark_payout_transfer_state 'paid' if the money in fact landed, 'reversed'
--   if it came back). Turning that into a supervised operator flow is an OWNER
--   ITEM, recorded in docs/phase2/_impl/J5_payout_state_machine.md §7; it is
--   deliberately NOT invented here.
-- ============================================================================
create or replace function kernel.rearm_failed_payout(
  p_payout_id uuid, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_po  kernel.payout%rowtype;
  v_st  venue.settlement%rowtype;
  v_aal text;
begin
  if v_uid is null then
    raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  -- AUTHZ-M4 step-up, in the 085/093 shape: an absent claim is never a pass and
  -- never a fail — it is unevaluable, and unevaluable fails closed.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to re-arm a failed payout';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: bad_reason_code (mandatory)';
  end if;

  select * into v_po from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  -- SCOPE. The re-request path this verb hands the payout back to is
  -- kernel.request_org_payout, which is cause='settlement' /
  -- payee_kind='organization' only. A market_sale, promoter_commission or
  -- refund_void payout has no such path, so re-arming one would produce a
  -- 'pending' row nothing can ever advance — a different way to strand money.
  if v_po.cause <> 'settlement' or v_po.payee_kind <> 'organization' then
    raise exception 'precondition_failed: not an organization settlement payout — no re-request path exists for cause=%', v_po.cause
      using errcode = 'P0001';
  end if;

  -- REPLAY, before the state gate: the exact triple this verb writes.
  if v_po.status = 'pending' and v_po.hold_state = 'held'
     and v_po.hold_reason_code = 'failed_rearm' then
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id,
                              'hold_reason_code', v_po.hold_reason_code);
  end if;
  if v_po.status <> 'failed' then
    raise exception 'precondition_failed: payout is %, not failed — re-arm recovers the absorbing state and nothing else', v_po.status
      using errcode = 'P0001';
  end if;
  -- NO DOUBLE PAYOUT (a). A Transfer object exists; its money is a Stripe fact.
  if v_po.stripe_transfer_ref is not null then
    raise exception 'precondition_failed: transfer_already_recorded — payout % carries %, so a Stripe Transfer exists; re-arming would offer a second one. Reconcile it with kernel.mark_payout_transfer_state instead', p_payout_id, v_po.stripe_transfer_ref
      using errcode = 'P0001';
  end if;
  -- Structurally unreachable (kernel.mark_payout_transfer_state refuses a held
  -- row, 085:1687, and kernel.hold_payout refuses a non-pending/submitted one),
  -- so if it is true the row was written by something outside the contract.
  if v_po.hold_state <> 'none' then
    raise exception 'precondition_failed: payout_held — a failed payout carrying hold_state=% was not produced by any contracted writer', v_po.hold_state
      using errcode = 'P0001';
  end if;

  -- The obligation must still be the one that was minted. A settlement that is
  -- not 'closed' either never closed or has been reopened; either way the
  -- amount in hand is not provably the ledger's.
  select * into v_st from venue.settlement where settlement_id = v_po.cause_ref for update;
  if not found then
    raise exception 'not_found: settlement % for payout %', v_po.cause_ref, p_payout_id using errcode = 'P0002';
  end if;
  if v_st.status <> 'closed' then
    raise exception 'precondition_failed: settlement_not_closed — settlement % is %', v_st.settlement_id, v_st.status
      using errcode = 'P0001';
  end if;
  if v_st.net_minor is distinct from v_po.amount_minor then
    raise exception 'precondition_failed: amount_ledger_mismatch — settlement net % vs payout amount %', v_st.net_minor, v_po.amount_minor
      using errcode = 'P0001';
  end if;

  -- SIX COLUMNS, ENUMERATED. No money column, no destination, no ref, no key.
  update kernel.payout
     set status           = 'pending',
         hold_state       = 'held',
         hold_reason_code = 'failed_rearm',
         held_by          = v_uid,      -- a HUMAN hold: kernel.retry_held_payout refuses to clear it
         held_at          = now(),
         updated_at       = now()
   where payout_id = p_payout_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'payout.rearm', 'payout', p_payout_id, left(trim(p_reason_code), 120),
          jsonb_build_object('status', v_po.status, 'hold_state', v_po.hold_state,
                             'stripe_transfer_ref', v_po.stripe_transfer_ref,
                             'destination_ref', v_po.destination_ref,
                             'amount_minor', v_po.amount_minor),
          jsonb_build_object('status', 'pending', 'hold_state', 'held',
                             'hold_reason_code', 'failed_rearm',
                             'destination_ref', v_po.destination_ref,   -- PRESERVED, not rewritten
                             'settlement_id', v_po.cause_ref,
                             'command_key', left(coalesce(p_command_key,''), 64)));

  -- best-effort notice: a human must release this, so a human must hear about it.
  begin
    perform notify.emit_event('payout_on_hold', 'payout', p_payout_id,
            'payout_rearm:' || p_payout_id::text,
            jsonb_build_object('reason', 'failed_rearm', 'amount_minor', v_po.amount_minor));
  exception when others then null; end;

  return jsonb_build_object('status','rearmed','payout_id', p_payout_id,
                            'payout_status', 'pending',
                            'hold_reason_code', 'failed_rearm',
                            'destination_ref', v_po.destination_ref);
end;
$$;

comment on function kernel.rearm_failed_payout(uuid, text, text) is
  'The only exit from the absorbing ''failed'' state. Returns a settlement payout to pending + held/''failed_rearm'' so the EXISTING ladder (kernel.release_payout, then kernel.request_org_payout) re-authorizes it. Never produces ''submitted''; never touches amount, currency, cause, idempotency_key, stripe_transfer_ref or destination_ref; refuses any payout that already carries a Stripe Transfer. platform_risk/platform_admin on aal2; explicitly not service_role.';

revoke all on function kernel.rearm_failed_payout(uuid, text, text)
  from public, anon, authenticated;
grant execute on function kernel.rearm_failed_payout(uuid, text, text) to authenticated;
-- THE HARD EDGE (085's kernel.record_money_denial pattern): a machine identity
-- must never be able to re-arm money it also executes.
revoke execute on function kernel.rearm_failed_payout(uuid, text, text) from service_role;


-- ============================================================================
-- E-3 — kernel.retry_held_payout: HOW A MATURITY HOLD CLEARS.
--
--   THE DEFECT. kernel.settlement_payout_maturity (10m) computes matures_at and
--   holds the payout until it passes. Nothing then clears it. There is no
--   sweeper, and kernel.request_org_payout refuses outright on hold_state<>'none'
--   ('payout_held — a platform risk hold must be released before a request'), so
--   a payout held purely because the event has not finished yet requires a
--   platform_risk/platform_admin human to release it before the org can even
--   ASK again. matures_at looks automatic and is not: the venue's money waits on
--   platform attention for a condition that is not a risk decision at all.
--
--   WHAT THIS IS NOT. It is NOT a sweeper, and it does NOT release money because
--   time passed. There is no cron entry in this migration and this function is
--   unreachable from service_role. Release is always a HUMAN-INITIATED RETRY by
--   the party owed the money, and the retry re-evaluates the whole conjunction.
--
--   WHY THE ORG ACTOR AND NOT THE PLATFORM. A maturity hold is not an accusation.
--   It says "we are not finished proving this money is the venue's". The venue
--   asking again is the correct trigger, and it is the only trigger that scales:
--   platform_risk's queue should contain risk, not clocks.
--
--   EVERY PREDICATE IS RE-EVALUATED AT RELEASE, and the mapping is exact:
--     maturity policy / anchor / elapsed ┐
--     covered-set resolvability          │  kernel.settlement_payout_maturity
--     event or session cancelled         ├─ (10m), called here, then called
--     refund non-terminal                │  AGAIN inside request_org_payout —
--     dispute open                       ┘  one definition, never duplicated
--     organization status ──────────────── E-1's trigger, on the advance edge
--     destination bound + cool-down ────── request_org_payout (10k)
--     destination probation ───────────── request_org_payout (10k) §10.3 arm 3
--     destination pin vs current ──────── get_payout_execution_context (10n)
--     Connect transfers capability ─────── get_payout_execution_context (10n)
--     unbooked refund exposure ─────────── get_payout_execution_context (10n)
--   Nothing in that list is re-implemented here. This function's own logic is
--   exactly two things: prove the hold is a MACHINE MATURITY hold, and delegate.
--
--   WHY IT CANNOT LAUNDER A RISK HOLD. Three independent tests, all of which
--   must pass:
--     (1) hold_state = 'held'   — a 'probation_hold' is a different arm with its
--         own contracted exit (kernel.release_payout after a human decision,
--         T-RPC-MONEY-32) and is refused here;
--     (2) held_by IS NULL       — kernel.hold_payout (085:795) stamps the human
--         who held it, and E-2 stamps the re-armer. A hold with a person's name
--         on it is released by a person, via kernel.release_payout, full stop;
--     (3) hold_reason_code ∈ kernel.settlement_maturity_hold_codes() — the eight
--         codes 10m can emit, and nothing else. 'destination_changed' (10o),
--         'unfunded_settlement' (090:1487), 'failed_rearm' (E-2),
--         'transfer_reversed' / 'transfer_partially_reversed' (E-4) and every
--         operator-typed risk reason are all outside the set and stay outside it.
--
--   AND IF THE CONJUNCTION STILL HOLDS, NOTHING CLEARS. The hold stays, its
--   reason is REFRESHED to whichever predicate is failing NOW (so an operator
--   reading the row sees the current cause, not the one from the close), the
--   refusal is audited, and the caller gets the full predicate vector. No money
--   moves and no approval is parked.
-- ============================================================================

-- The eight hold_reason_code values kernel.settlement_payout_maturity (093
-- slice 10m) can emit, pinned as ONE list so the "is this a maturity hold?"
-- question has a single answer. The pgTAP suite asserts this list against 10m's
-- own source, so a code added there without adding it here is a test failure
-- rather than a silent divergence.
create or replace function kernel.settlement_maturity_hold_codes()
returns text[]
language sql
immutable
security definer
set search_path = ''
as $$
  select array[
    'unbounded_refund_exposure',   -- the policy key is unset / unreadable
    'maturity_policy_invalid',     -- the policy interval is negative
    'covered_set_unresolvable',    -- a money line resolves to no payment/session
    'event_cancelled',             -- a covered session or event is cancelled
    'maturity_instant_unknown',    -- no covered session, or one without ends_at
    'maturity_not_elapsed',        -- anchor + interval is still in the future
    'refund_in_flight',            -- a covered refund is pending/submitted
    'dispute_open'                 -- a covered dispute is non-terminal
  ]::text[];
$$;

comment on function kernel.settlement_maturity_hold_codes() is
  'The closed set of hold_reason_code values kernel.settlement_payout_maturity (093 slice 10m) can emit. The ONLY reasons kernel.retry_held_payout may clear. Every other hold — risk, probation, destination, unfunded commission, failed re-arm, reversed transfer — is released solely by kernel.release_payout.';

-- DEFINER-INTERNAL: read only by kernel.retry_held_payout (SECURITY DEFINER, so
-- it needs no client grant) and by the pgTAP suite as table owner. No principal
-- is granted EXECUTE — it is a constant, not a read model.
revoke all on function kernel.settlement_maturity_hold_codes() from public, anon, authenticated;

create or replace function kernel.retry_held_payout(
  p_org_id uuid, p_settlement_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_aal      text;
  v_s        venue.settlement%rowtype;
  v_po       kernel.payout%rowtype;
  v_verdict  jsonb;
  v_reason   text;
begin
  if v_uid is null then
    raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501';
  end if;
  -- The SAME authority the request itself demands. Checked here as well as in
  -- the delegate, because clearing a hold is itself a decision and must not be
  -- reachable by anyone who could not have asked for the payout.
  if not kernel.has_org_role(p_org_id, array['org_owner','org_finance']) then
    raise exception 'insufficient_privilege: org_owner or org_finance required' using errcode = '42501';
  end if;
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to retry a held payout';
  end if;

  select * into v_s from venue.settlement where settlement_id = p_settlement_id for update;
  if not found or v_s.org_id <> p_org_id then   -- AUTHZ-C1C: the scope binds to the subject, under the lock
    raise exception 'not_found: settlement % for org %', p_settlement_id, p_org_id using errcode = 'P0002';
  end if;

  select * into v_po from kernel.payout
   where cause = 'settlement' and cause_ref = p_settlement_id and status = 'pending'
   order by created_at limit 1 for update;
  if not found then
    raise exception 'precondition_failed: no pending payout for this settlement' using errcode = 'P0001';
  end if;

  -- Nothing to clear: hand straight to the contracted request path. This is not
  -- a shortcut — request_org_payout runs its entire ladder either way.
  if v_po.hold_state = 'none' then
    return kernel.request_org_payout(p_org_id, p_settlement_id, p_command_key);
  end if;

  -- ── THE THREE TESTS THAT SAY "THIS IS A MACHINE MATURITY HOLD" ───────────
  if v_po.hold_state <> 'held' then
    raise exception 'precondition_failed: payout_held — hold_state=% is not a maturity hold; kernel.release_payout is its only exit', v_po.hold_state
      using errcode = 'P0001';
  end if;
  if v_po.held_by is not null then
    raise exception 'precondition_failed: human_hold — this payout was held by a person; only kernel.release_payout (platform_risk/platform_admin) clears it'
      using errcode = 'P0001';
  end if;
  if v_po.hold_reason_code is null
     or not (v_po.hold_reason_code = any (kernel.settlement_maturity_hold_codes())) then
    raise exception 'precondition_failed: not_a_maturity_hold — hold_reason_code=% is released only by kernel.release_payout', coalesce(v_po.hold_reason_code,'<null>')
      using errcode = 'P0001';
  end if;

  -- ── RE-EVALUATE. 10m's verdict, whole. No predicate is re-implemented. ────
  v_verdict := kernel.settlement_payout_maturity(p_settlement_id);
  v_reason  := v_verdict ->> 'hold_reason';

  if v_reason is not null then
    -- STILL HELD. Refresh the reason so the row names the predicate failing NOW
    -- (an operator reading a stale 'maturity_not_elapsed' on a payout that is
    -- actually blocked by an open dispute is being misled), re-stamp held_at,
    -- and audit the refusal. hold_state is NOT written: it is already 'held'.
    update kernel.payout
       set hold_reason_code = v_reason,
           held_at          = now(),
           updated_at       = now()
     where payout_id = v_po.payout_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'payout.maturity_hold', 'payout', v_po.payout_id, v_reason,
            jsonb_build_object('hold_reason_code', v_po.hold_reason_code),
            jsonb_build_object('settlement_id', p_settlement_id,
                               'hold_predicates', v_verdict -> 'detail',
                               'via', 'retry_held_payout'));
    return jsonb_build_object('status','maturity_held','payout_id', v_po.payout_id,
                              'hold_reason_code', v_reason,
                              'payout_hold_detail', v_verdict -> 'detail');
  end if;

  -- ── CLEAR, THEN DELEGATE. The clear is audited under the name of the human
  --    who asked; the ADVANCE is request_org_payout's, under its full ladder,
  --    which re-runs this same conjunction as its own last gate. If anything
  --    turned between these two statements it re-imposes the hold itself.
  update kernel.payout
     set hold_state       = 'none',
         hold_reason_code = null,
         held_by          = null,
         held_at          = null,
         updated_at       = now()
   where payout_id = v_po.payout_id;   -- status NOT written (S-15/C105)

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'payout.maturity_clear', 'payout', v_po.payout_id, v_po.hold_reason_code,
          jsonb_build_object('hold_state', 'held', 'hold_reason_code', v_po.hold_reason_code),
          jsonb_build_object('hold_state', 'none',
                             'settlement_id', p_settlement_id,
                             'maturity_detail', v_verdict -> 'detail',
                             'command_key', left(coalesce(p_command_key,''), 64)));

  return kernel.request_org_payout(p_org_id, p_settlement_id, p_command_key);
end;
$$;

comment on function kernel.retry_held_payout(uuid, uuid, text) is
  'The self-clear path for a MACHINE maturity hold, and only that. Human-initiated by an org money role on aal2; re-evaluates kernel.settlement_payout_maturity in full and clears only on a clean verdict, then delegates the advance to kernel.request_org_payout unchanged. Refuses a probation hold, a hold stamped with a person (held_by), and any hold_reason_code outside kernel.settlement_maturity_hold_codes(). Not a sweeper, no cron, not service_role-reachable.';

revoke all on function kernel.retry_held_payout(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function kernel.retry_held_payout(uuid, uuid, text) to authenticated;
revoke execute on function kernel.retry_held_payout(uuid, uuid, text) from service_role;


-- ============================================================================
-- E-4 — kernel.hold_payout_transfer_reversed: A REVERSED TRANSFER IS NOT A
--   PAYMENT, AND A PARTIALLY REVERSED ONE IS NOT REPRESENTABLE.
--
--   THE DEFECT IT ANSWERS (executor.ts planPayoutStateSync, and planReconcile).
--   The executor decided "did this transfer come back?" by reading the Stripe
--   Transfer's `reversed` boolean. Stripe documents that flag as FULL reversal
--   only — "if the transfer is only partially reversed, this attribute will
--   still be false" — while `amount_reversed` carries the money. A partially
--   reversed transfer therefore read as clean and was synced to 'paid' AT FULL
--   FACE VALUE: the ledger would record the venue as fully paid while part of
--   the money had already been pulled back, kernel.venue.on_payout_settled would
--   advance the settlement header closed→paid on that basis, and nothing
--   downstream re-reads the transfer. The same blind spot sat in the reconcile
--   path, which compares `amount` (unchanged by a reversal) and would ADOPT a
--   reversed transfer as a successful payment.
--
--   WHY NEITHER 'paid' NOR 'reversed' IS THE ANSWER FOR A PARTIAL — SAID
--   EXPLICITLY, BECAUSE THE BRIEF ASKS FOR THE CHOICE AND NOT A HEDGE.
--     · 'paid' is false. It asserts the venue received amount_minor, and it is
--       not an inert label: kernel.mark_payout_transfer_state fires
--       venue.on_payout_settled on 'paid' (085:1729), which flips the settlement
--       header to 'paid' once every sibling is paid. Writing it would make the
--       ledger claim a settlement was discharged that was not.
--     · 'reversed' is also false, twice over. It asserts the WHOLE transfer came
--       back, and it is only reachable THROUGH 'paid' (the state machine's one
--       terminal-to-terminal edge is paid→reversed), so taking it would first
--       write the lie above and then a second one.
--     · Widening the status CHECK to admit a partial is out of scope and would
--       be the wrong fix anyway: kernel.payout has ONE amount column and it is
--       the obligation, not the settled amount. There is nowhere to put "we
--       moved 5000 and 1200 came back".
--   THE CHOICE, THEREFORE: the executor writes NO status transition. It calls
--   this verb, which de-authorizes the payout back to pending + held with the
--   exact amounts in the audit, and a human rules. That is the same posture
--   kernel.hold_payout_destination_changed (10o) already takes for the other
--   "do not pay, do not fail" case, and it keeps the obligation alive as a
--   durable ledger fact instead of destroying it.
--   NAMED FINDING (owner item, J5 §8): kernel.payout cannot represent a
--   partially reversed transfer. This verb makes that unrepresentability LOUD
--   and recoverable rather than silent and wrong. It does not fix it.
--
--   FULL REVERSAL IS BENIGN, NOT AN ERROR. Stripe may reverse a transfer on its
--   OWN initiative — for platforms created on or after 2025-01-01, when an async
--   payment behind the funds fails. "Already fully reversed" arriving at the
--   executor is therefore an expected observation, not a conflict and not a
--   page. It takes the same de-authorizing hold, with its own reason code, and
--   the executor treats it as a completed non-payment rather than a fault.
--
--   IT DOES NOT WRITE stripe_transfer_ref, DELIBERATELY. That column is
--   contracted as "written ONLY by mark_payout_transfer_state, write-once"
--   (085:133), and writing it here would ALSO make the payout permanently
--   un-executable via 10n's 'transfer_already_recorded' — foreclosing an owner
--   decision this verb has no standing to make. The transfer id rides in the
--   audit row instead. Re-execution is prevented by the row's own state
--   (pending + held is invisible to kernel.claim_payouts_for_execution) and, if
--   a human releases and re-requests, by the executor's reconcile path, which
--   now refuses to adopt a transfer with amount_reversed > 0 and lands right
--   back here.
--
--   WHY service_role AND NOT A HUMAN. This is the mirror of 10o: a MACHINE
--   observation of a Stripe fact, on the money execution path, that can only
--   ever move a payout from payable to held. It authorizes nothing — the exit
--   is kernel.release_payout (a human) followed by kernel.request_org_payout
--   (a different human, behind the full ladder). The caller's numbers are
--   EVIDENCE, never predicates: full-versus-partial is decided against the
--   payout's own amount_minor, not against anything the caller supplies.
-- ============================================================================
create or replace function kernel.hold_payout_transfer_reversed(
  p_payout_id uuid, p_stripe_transfer_ref text, p_transfer_amount_minor integer,
  p_amount_reversed_minor integer, p_detail jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_po   kernel.payout%rowtype;
  v_code text;
begin
  if p_stripe_transfer_ref is null or p_stripe_transfer_ref !~ '^tr_[A-Za-z0-9]+$' then
    raise exception 'invalid_input: a Stripe transfer ref (tr_…) is mandatory';
  end if;
  if p_amount_reversed_minor is null or p_amount_reversed_minor <= 0 then
    raise exception 'invalid_input: amount_reversed_minor must be positive — this verb records a reversal, not a clean transfer';
  end if;

  select * into v_po from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  if v_po.cause <> 'settlement' or v_po.payee_kind <> 'organization' then
    raise exception 'precondition_failed: not an organization settlement payout' using errcode = 'P0001';
  end if;
  -- REPLAY FIRST, BEFORE THE STATE GATE. The executor observes the same
  -- reversal on every tick, and this verb has ALREADY moved the row off
  -- 'submitted' — so a status-first ordering would answer the second look with
  -- 'payout is pending, not submitted' instead of the no-op it is. The replay is
  -- recognised by the exact hold THIS verb writes, never by hold_state alone.
  if v_po.hold_state <> 'none'
     and v_po.hold_reason_code in ('transfer_reversed','transfer_partially_reversed') then
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id,
                              'fault', v_po.hold_reason_code,
                              'hold_reason_code', v_po.hold_reason_code);
  end if;
  -- A reversal observed AFTER the ledger already recorded payment is a
  -- different transition with a different verb: full ⇒
  -- kernel.mark_payout_transfer_state(...,'reversed',...). Partial ⇒ the owner
  -- item named above. Neither is this verb's business, and guessing would be a
  -- second door onto a terminal row.
  if v_po.status = 'paid' then
    raise exception 'precondition_failed: payout is paid — a post-payment full reversal is kernel.mark_payout_transfer_state(...,''reversed'',...); a post-payment PARTIAL reversal is unrepresentable (owner item J5 §8)'
      using errcode = 'P0001';
  end if;
  if v_po.status <> 'submitted' then
    raise exception 'precondition_failed: payout is %, not submitted', v_po.status using errcode = 'P0001';
  end if;
  if v_po.hold_state <> 'none' then
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id,
                              'hold_reason_code', v_po.hold_reason_code);
  end if;

  -- THE VERDICT IS DERIVED FROM THE LEDGER'S OWN AMOUNT. The caller's
  -- p_transfer_amount_minor is recorded as evidence and never used as the
  -- denominator; a caller that under-reports the transfer cannot turn a full
  -- reversal into a partial one, or the reverse.
  v_code := case when p_amount_reversed_minor >= v_po.amount_minor
                 then 'transfer_reversed'
                 else 'transfer_partially_reversed' end;

  update kernel.payout
     set status           = 'pending',
         hold_state       = 'held',
         hold_reason_code = v_code,
         held_by          = null,     -- machine-set: a human must still release it
         held_at          = now(),
         updated_at       = now()
   where payout_id = p_payout_id;     -- stripe_transfer_ref NOT written (085:133)

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values ('00000000-0000-0000-0000-0000000000f1', 'payout.transfer_reversed_hold', 'payout',
          p_payout_id, v_code,
          jsonb_build_object('status', v_po.status, 'hold_state', v_po.hold_state,
                             'amount_minor', v_po.amount_minor,
                             'destination_ref', v_po.destination_ref),
          jsonb_build_object('status', 'pending', 'hold_state', 'held',
                             'fault', v_code,
                             'stripe_transfer_ref', left(p_stripe_transfer_ref, 64),
                             'transfer_amount_minor', p_transfer_amount_minor,
                             'amount_reversed_minor', p_amount_reversed_minor,
                             'obligation_minor', v_po.amount_minor,
                             'evidence', coalesce(p_detail, '{}'::jsonb),
                             'command_key', left(coalesce(p_command_key,''), 64)));

  begin
    perform notify.emit_event('payout_on_hold', 'payout', p_payout_id,
            'payout_reversed_hold:' || p_payout_id::text,
            jsonb_build_object('reason', v_code, 'amount_minor', v_po.amount_minor));
  exception when others then null; end;

  return jsonb_build_object('status','held','payout_id', p_payout_id, 'fault', v_code,
                            'amount_reversed_minor', p_amount_reversed_minor,
                            'obligation_minor', v_po.amount_minor);
end;
$$;

comment on function kernel.hold_payout_transfer_reversed(uuid, text, integer, integer, jsonb, text) is
  'The executor''s answer to a Stripe Transfer that came back — fully (benign; Stripe may reverse on its own initiative) or partially (unrepresentable in kernel.payout). Writes NO status transition: de-authorizes submitted -> pending + held with the amounts in the audit, so ''paid'' never asserts money the venue does not have and ''failed'' is never written. service_role only; authorizes nothing.';

revoke all on function kernel.hold_payout_transfer_reversed(uuid, text, integer, integer, jsonb, text)
  from public, anon, authenticated;
grant execute on function kernel.hold_payout_transfer_reversed(uuid, text, integer, integer, jsonb, text) to service_role;


-- ============================================================================
-- E-5 — kernel.guard_settlement_forward_only: THE HEADER GETS THE PROTECTION
--   ITS LINES ALREADY HAVE.
--
--   THE DEFECT, AND ITS HONEST SEVERITY. venue.settlement_line is append-only,
--   enforced by tg_settlement_line_append_only and by revoking UPDATE/DELETE
--   from service_role (087:111-115). venue.settlement — the HEADER those lines
--   roll up into — has nothing: no trigger, no forward-only rule, and four money
--   columns that the schema comment describes as "written EXACTLY ONCE" purely
--   by convention. status='closed' can be set back to 'open' and re-closed.
--
--   WHO CAN ACTUALLY DO IT. On a fresh replay the table's ACL is
--   `postgres=arwdDxtm/postgres, authenticated=r/postgres` — nothing else. anon
--   and authenticated are revoked to SELECT; service_role has NO grant on this
--   table at all (PFA-21: schema USAGE only, no table DML). So the reachable set
--   is exactly (a) a direct superuser / table-owner session and (b) any
--   postgres-owned SECURITY DEFINER function that writes the header — today,
--   kernel.close_settlement and venue.on_payout_settled, and tomorrow whatever
--   is written next. It is NOT reachable from PostgREST, from an edge function,
--   or from any client role.
--
--   WHAT ACTUALLY BREAKS ON A REOPEN + RE-CLOSE, tested rather than assumed.
--   Money does NOT move twice: the payout mint is idempotent on
--   'settlement:<id>' with `on conflict do nothing`, so a second close mints
--   nothing and UPDATES nothing on the existing payout row. What breaks is:
--     · the re-close's payout-maturity verdict is REPORTED (in the return value
--       and in the settlement.close audit row) but NOT APPLIED — the payout row
--       keeps whatever hold state it already had, so an operator reading the
--       close result believes a hold was imposed that was not;
--     · the four money columns are silently rewritten, so net_minor can diverge
--       from the amount an in-flight payout was authorized for. That divergence
--       is CAUGHT — 10n refuses with 'amount_ledger_mismatch' — but the
--       consequence is that the payout becomes permanently un-executable while
--       still reading 'submitted': stranded money, by a different route than
--       'failed';
--     · a header already advanced to 'paid' by venue.on_payout_settled can be
--       walked back to 'open', erasing the record that a settlement was
--       discharged.
--   SEVERITY CALL: this is a LEDGER- AND AUDIT-INTEGRITY defect, not a
--   money-movement one. It cannot cause an overpayment. It can strand a payout,
--   corrupt the reported waterfall, and produce a hold that was reported and
--   never applied.
--
--   IS IT SAFE TO CLOSE HERE — i.e. does forward-only block a legitimate flow?
--   Every writer of venue.settlement in the whole corpus was enumerated before
--   this trigger was written: an INSERT at 'open' (venue.open_settlement, whose
--   idempotency arm RETURNS the existing header and never updates it), the
--   open→closed UPDATE that also writes the four money columns
--   (kernel.close_settlement, 093 slice 10d), and the closed→paid UPDATE
--   (venue.on_payout_settled, 087:377). That is the complete set. All three pass
--   this trigger unchanged, so YES — it is safe to close in 095.
--
--   WHAT IT DOES NOT CLAIM. A superuser can ALTER TABLE ... DISABLE TRIGGER, and
--   this migration does not pretend otherwise. The trigger converts a convention
--   into an invariant against accident, against a future definer function
--   written without this context, and against anything short of a deliberate
--   ownership-level act — which is the same protection venue.settlement_line has
--   had since 087.
-- ============================================================================
create or replace function kernel.guard_settlement_forward_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'open' then
      raise exception 'append_only: settlement % is % — a closed settlement is a money record and is not deletable', old.settlement_id, old.status
        using errcode = 'P0001';
    end if;
    return old;
  end if;

  -- FORWARD-ONLY: open → closed → paid. Nothing else, in either direction.
  if new.status is distinct from old.status
     and not ( (old.status = 'open'   and new.status = 'closed')
            or (old.status = 'closed' and new.status = 'paid') ) then
    raise exception 'precondition_failed: settlement_status_backwards (% → %) — venue.settlement is forward-only open → closed → paid', old.status, new.status
      using errcode = 'P0001';
  end if;

  -- WRITE-ONCE MONEY. The four columns and the currency are written in the ONE
  -- transaction that moves open→closed (schema §3.13, and the waterfall CHECK
  -- depends on them). After that they are the settlement, and the scope columns
  -- that say WHOSE settlement it is are frozen with them.
  if old.status <> 'open'
     and ( new.gross_minor   is distinct from old.gross_minor
        or new.fees_minor    is distinct from old.fees_minor
        or new.refunds_minor is distinct from old.refunds_minor
        or new.net_minor     is distinct from old.net_minor
        or new.currency      is distinct from old.currency
        or new.org_id        is distinct from old.org_id
        or new.venue_id      is distinct from old.venue_id
        or new.event_id      is distinct from old.event_id ) then
    raise exception 'append_only: settlement % is closed — its money columns and scope are written exactly once, in the open → closed transaction', old.settlement_id
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

comment on function kernel.guard_settlement_forward_only() is
  'venue.settlement is forward-only (open -> closed -> paid), its four money columns and its scope are write-once at the close, and a non-open header is not deletable. The header protection matching the append-only rule venue.settlement_line has carried since 087.';

-- 066/077-F1 discipline, as at E-1: a trigger function is not a callable verb.
revoke all on function kernel.guard_settlement_forward_only() from public, anon, authenticated;

drop trigger if exists tg_settlement_forward_only on venue.settlement;
create trigger tg_settlement_forward_only
  before update or delete on venue.settlement
  for each row execute function kernel.guard_settlement_forward_only();


-- ============================================================================
-- E-6 — kernel.settlement_unbooked_refund_exposure: A LINE WRITTEN IS NOT A
--   DEBT RECOVERED.
--
--   THE DEFECT, REPRODUCED END TO END BEFORE IT WAS FIXED.
--   kernel.get_payout_execution_context (093 slice 10n) refuses a payout with
--   'refund_exposure_stale' when a covered payment carries settled refunds that
--   no settlement has debited. Its `lined` term counted every 'refund_void'
--   LINE against the exposure, in ANY settlement, unconditionally. But a
--   settlement whose net is <= 0 MINTS NOTHING (10d guards the mint with
--   `if v_net > 0`) and therefore RECOVERS NOTHING: the debit is written into a
--   header that pays nobody, and this schema has no carry-forward object to
--   collect it. So:
--     1. a settled post-close refund of 10000 leaves stale_exposure = 10000 and
--        the guard correctly holds the venue's 9000 payout;
--     2. close a SECOND settlement that books refund_void -10000. Net is
--        negative, `payout_ids` comes back empty, no money is recovered;
--     3. stale_exposure is now 0 and refusal_code is NULL;
--     4. the executor claims the 9000 and transfers it.
--   The venue is paid in full for revenue that was entirely reversed, and the
--   thing that unlocked it was a bookkeeping line in a settlement that paid
--   nobody. Booking the reversal DEFEATED the guard that exists to notice it.
--
--   THE CORRECTED RULE. A 'refund_void' line discharges its exposure only if
--   the settlement carrying it ACTUALLY ABSORBED the debit — that is, the
--   header is closed or paid AND its net_minor is >= 0. Both halves matter:
--     · net_minor >= 0 (not > 0): a settlement that nets exactly zero because
--       its own revenue exactly cancelled the refund DID absorb it — the venue
--       was paid nothing where it would otherwise have been paid the gross.
--     · net_minor IS NULL (an open header) never discharges. coalesce(...,-1)
--       makes that explicit rather than leaving it to NULL comparison.
--   A NEGATIVE-NET settlement that PARTIALLY absorbs an exposure (gross 4000
--   against a 10000 refund) discharges NOTHING here, not 4000. That is a
--   deliberate over-correction in the direction 093 itself chose at slice 10e:
--   over-holding a venue's money is reversible by an owner act, over-paying it
--   in an append-only ledger is not. The residual it leaves is a HOLD, which is
--   the recoverable failure mode.
--
--   NO DEPENDENCY ON THE OBLIGATION OBJECT. J3 proposes an append-only,
--   org-scoped kernel.organization_obligation booked from close_settlement's
--   currently-empty `v_net <= 0` branch. This fix does NOT reference it, does
--   NOT require it, and imposes NO ordering constraint on 095: without it, an
--   unrecovered exposure simply never discharges and the payout stays held —
--   the safe direction. WHEN it lands, this function is the ONE place to extend:
--   the discharge predicate gains "…or the obligation whose origin_ref is this
--   settlement line is no longer 'outstanding'", so a genuinely-recovered
--   receivable stops holding the payout. That extension is a follow-up, not a
--   prerequisite, and it is deliberately not written blind here.
--
--   WHY 10n IS RE-CREATED BELOW. The derivation was inline in a frozen slice
--   and the executor consumes 10n's verdict directly, so there is no other
--   chokepoint between the verdict and the Stripe call. The body below is 093
--   slice 10n BYTE FOR BYTE except for the six-line block that replaced the
--   inline sub-select with this call — signature, volatility, security, grants,
--   every refusal code, their causal order and the whole return projection are
--   unchanged. `unbooked_refund_exposure_minor` keeps its name and meaning in
--   `maturity_detail`; it now means what the name always claimed.
--
--   THE FACE CAP IS PRESERVED VERBATIM, and it is load-bearing, not decoration.
--   kernel.refund.amount_minor is measured against public.payments.total =
--   amount + buyer_fee (000:978-985), while a 'refund_void' line is capped at
--   the order's face value because the buyer-side service fee is platform money
--   under ruling A5. Comparing raw refund sums against refunds_minor would fire
--   on every ordinary fee-bearing refund and STRAND the venue's money — a false
--   positive here is not conservative, it is the same permanent loss by another
--   route.
-- ============================================================================
create or replace function kernel.settlement_unbooked_refund_exposure(p_settlement_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(x.entitled - x.discharged), 0)::bigint
    from (
      select least(
               coalesce((select sum(r.amount_minor) from kernel.refund r
                          where r.payment_id = c.payment_id and r.status = 'succeeded'), 0),
               coalesce((select o.total_minor from venue."order" o
                          join kernel.payment_native pn on pn.order_id = o.order_id
                         where pn.payment_id = c.payment_id), 0))::bigint as entitled,
             coalesce((select sum(-l.amount_minor)
                         from venue.settlement_line l
                         join kernel.refund r2 on r2.refund_id = l.cause_ref
                         join venue.settlement s on s.settlement_id = l.settlement_id
                        where l.cause = 'refund_void'
                          and r2.payment_id = c.payment_id
                          -- THE FIX. A debit only discharges an exposure if the
                          -- header carrying it actually absorbed it: closed (or
                          -- already paid) AND net >= 0. A negative-net header
                          -- mints nothing and recovers nothing, so its lines
                          -- prove bookkeeping, never recovery. NULL net (an open
                          -- header) is -1 and never discharges.
                          and s.status in ('closed','paid')
                          and coalesce(s.net_minor, -1) >= 0), 0)::bigint as discharged
        from (select distinct cp.payment_id
                from kernel.settlement_covered_payments(p_settlement_id) cp
               where cp.payment_id is not null) c
    ) x
   where x.entitled > x.discharged;
$$;

comment on function kernel.settlement_unbooked_refund_exposure(uuid) is
  'Settled refund money against this settlement''s covered payments that no settlement has ACTUALLY absorbed — capped per order at face value (ruling A5). A refund_void line discharges only when its own header is closed/paid with net_minor >= 0; a negative-net settlement mints nothing, recovers nothing, and therefore discharges nothing. The operand behind get_payout_execution_context''s refund_exposure_stale refusal.';

revoke all on function kernel.settlement_unbooked_refund_exposure(uuid) from public, anon, authenticated;
grant execute on function kernel.settlement_unbooked_refund_exposure(uuid) to service_role;


-- ----------------------------------------------------------------------------
-- kernel.get_payout_execution_context — 093 slice 10n, BODY ONLY, ONE CHANGE.
--   The staleness sub-select becomes a call to the function above. Nothing else
--   is touched: same signature, same STABLE SECURITY DEFINER search_path='',
--   same refusal codes in the same causal order, same return projection. The
--   grants 093 wrote are preserved by CREATE OR REPLACE and re-stated below so
--   a reader does not have to go and check.
-- ----------------------------------------------------------------------------
create or replace function kernel.get_payout_execution_context(p_payout_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_po           kernel.payout%rowtype;
  v_st           venue.settlement%rowtype;
  v_org          kernel.organization%rowtype;
  v_pinned       text;
  v_current      text;
  v_dest_indiv   boolean := false;
  -- The G2 conjunction is NOT re-implemented here; it is 10m's verdict, verbatim.
  v_maturity     jsonb;
  -- The one predicate 10m cannot carry, because it is meaningless at the mint.
  v_stale_minor  bigint := 0;
  v_code         text;
begin
  select * into v_po from kernel.payout where payout_id = p_payout_id;
  if not found then
    return null;                      -- non-enumerable: 404 at the edge
  end if;

  select * into v_st from venue.settlement where settlement_id = v_po.cause_ref;
  if v_po.payee_org_id is not null then
    select * into v_org from kernel.organization o where o.org_id = v_po.payee_org_id;
  end if;
  v_pinned  := v_po.destination_ref;
  v_current := v_org.stripe_connect_account_ref;   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)

  -- CROSS-PLANE: the personal seller Connect plane is not a payout destination
  -- for an organization settlement. Both the live column (002:25) and the 044
  -- archive are consulted, against the PINNED value — the one that would be
  -- sent. A NULL pin trivially matches neither.
  if v_pinned is not null then
    v_dest_indiv := exists (select 1 from public.profiles pr where pr.stripe_connect_id = v_pinned)
                 or exists (select 1 from public.stripe_connect_archive ar where ar.stripe_connect_id = v_pinned);
  end if;

  -- THE G2 CONJUNCTION IS NOT RE-IMPLEMENTED HERE. One definition (10m), three
  -- call sites: the mint (10d), the pending→submitted advance (10k), and this,
  -- the transfer. Re-evaluated against now(), so a refund that succeeded, a
  -- dispute that opened or an event that was cancelled AFTER the close is seen.
  v_maturity := kernel.settlement_payout_maturity(v_po.cause_ref);

  -- THE STALENESS OPERAND (H3 §5 step 4 / §7.1) — the one predicate 10m does
  -- not carry, because at the mint the lines were just written and it can only
  -- read zero. 093 derived it INLINE and subtracted every 'refund_void' LINE,
  -- which made "a debit was written down" indistinguishable from "the money
  -- came back". The derivation now lives in
  -- kernel.settlement_unbooked_refund_exposure (095 E-6), which carries the
  -- defect, its executed reproduction and the corrected discharge rule. THIS IS
  -- THE ONLY CHANGE IN THIS BODY; every other byte is 093 slice 10n verbatim.
  v_stale_minor := kernel.settlement_unbooked_refund_exposure(v_po.cause_ref);

  -- FIRST FAILING PREDICATE WINS, in causal order: identity and binding before
  -- money, money before the payee, the payee before maturity, maturity before
  -- staleness. Everything below REFUSES; nothing here is advisory.
  v_code := case
    -- ── binding: is this even a settlement payout to an organization? ──────
    when v_po.cause <> 'settlement'                        then 'cause_not_settlement'
    when v_po.payee_kind <> 'organization'
      or v_po.payee_org_id is null                         then 'payee_not_organization'
    -- ── the row's own state ───────────────────────────────────────────────
    when v_po.hold_state <> 'none'                         then 'payout_held'
    when v_po.status <> 'submitted'                        then 'payout_not_submitted'
    when v_po.stripe_transfer_ref is not null              then 'transfer_already_recorded'
    when v_po.amount_minor is null
      or v_po.amount_minor <= 0                            then 'amount_not_positive'
    when upper(coalesce(v_po.currency,'')) <> 'USD'        then 'currency_unsupported'
    -- ── the obligation ────────────────────────────────────────────────────
    when v_st.settlement_id is null                        then 'settlement_not_found'
    when v_st.org_id is distinct from v_po.payee_org_id    then 'org_mismatch'
    when v_st.status <> 'closed'                           then 'settlement_not_closed'
    when upper(coalesce(v_st.currency,'')) <> upper(coalesce(v_po.currency,''))
                                                           then 'currency_mismatch'
    when v_st.net_minor is distinct from v_po.amount_minor then 'amount_ledger_mismatch'
    -- ── the payee (H6) ────────────────────────────────────────────────────
    when v_org.org_id is null                              then 'organization_not_found'
    when v_org.status not in ('approved','active')         then 'org_not_active'
    when v_pinned is null                                  then 'destination_not_bound'
    when v_pinned !~ '^acct_[A-Za-z0-9]+$'                 then 'destination_malformed'
    when v_dest_indiv                                      then 'destination_individual_plane'
    when v_current is null                                 then 'no_payout_destination'
    when v_pinned is distinct from v_current               then 'destination_changed'
    when not coalesce(v_org.connect_transfers_active, false) then 'connect_transfers_inactive'
    when v_org.payout_destination_locked_until is not null
     and v_org.payout_destination_locked_until > now()     then 'destination_cooldown'
    -- ── maturity: 10m's verdict, adopted whole. ONE line, so this gate and
    --    the mint gate cannot disagree about what "matured" means. ──────────
    when (v_maturity ->> 'hold_reason') is not null        then v_maturity ->> 'hold_reason'
    -- ── staleness (H3 §5 step 4) ──────────────────────────────────────────
    when v_stale_minor > 0                                 then 'refund_exposure_stale'
    else null
  end;

  return jsonb_build_object(
    'payout_id',              v_po.payout_id,
    'cause',                  v_po.cause,
    'settlement_id',          v_po.cause_ref,
    'payee_kind',             v_po.payee_kind,
    'payee_org_id',           v_po.payee_org_id,
    'amount_minor',           v_po.amount_minor,
    'currency',               v_po.currency,
    'status',                 v_po.status,
    'hold_state',             v_po.hold_state,
    'hold_reason_code',       v_po.hold_reason_code,
    'stripe_transfer_ref',    v_po.stripe_transfer_ref,
    'source_transaction_ref', v_po.source_transaction_ref,   -- H3 §3: NULL on this rail, always
    'created_at',             v_po.created_at,
    -- the obligation, for the executor's own equality assertion and the audit
    'settlement_org_id',        v_st.org_id,
    'settlement_status',        v_st.status,
    'settlement_net_minor',     v_st.net_minor,
    'settlement_refunds_minor', v_st.refunds_minor,
    'settlement_currency',      v_st.currency,
    -- the payee: PINNED is what gets sent; CURRENT is what it is checked against
    'destination',              v_pinned,
    'destination_ref',          v_pinned,
    'org_connect_ref_current',  v_current,
    'org_status',               v_org.status,
    'connect_transfers_active', coalesce(v_org.connect_transfers_active, false),
    'destination_locked_until', v_org.payout_destination_locked_until,
    'destination_individual_plane', v_dest_indiv,
    -- transfer_group: the ONLY durable handle back to a transfer whose response
    -- was lost after the 24h idempotency window (H3 §6).
    'transfer_group',         'payout_' || v_po.payout_id::text,
    -- THE VERDICT. The worker consumes this; it does not re-derive it.
    'execution_eligible',     (v_code is null),
    'refusal_code',           v_code,
    'maturity_detail',        coalesce(v_maturity -> 'detail', '{}'::jsonb)
                                || jsonb_build_object('unbooked_refund_exposure_minor', v_stale_minor));
end;
$$;

revoke all on function kernel.get_payout_execution_context(uuid) from public, anon, authenticated;
grant execute on function kernel.get_payout_execution_context(uuid) to service_role;


commit;
