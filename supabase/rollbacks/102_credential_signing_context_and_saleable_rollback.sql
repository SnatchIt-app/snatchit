-- ============================================================================
-- 102_credential_signing_context_and_saleable_rollback.sql
--   REVERSES supabase/migrations/102_credential_signing_context_and_saleable.sql
-- ----------------------------------------------------------------------------
-- POSTURE: BREAK-GLASS / FORWARD-FIX GUARD. This restores catalog.publish_event
-- to its 081:899-964 body and catalog.set_platform_config to its 093:6544-6927
-- body — REMOVING the A8a' SALEABLE gate ladder from on_sale and REMOVING
-- signing.% trust-root dual control — and drops
-- kernel.get_ticket_signing_context entirely. Nothing in this migration was
-- ever applied to production (093-102 are all unapplied; production sits at
-- ledger 107 / 092). Run this only if 102 itself is found wrong; otherwise
-- forward-fix with a new migration, per this repo's convention (096/097's own
-- rollback headers state the same posture).
--
-- WHAT THIS DOES:
--   1. drop kernel.get_ticket_signing_context(uuid) — the ONLY new object 102
--      created. Nothing else references it (the credential-sign edge that
--      calls it is DARK/undeployed and authored separately), so the drop is
--      clean.
--   2. catalog.publish_event — CREATE OR REPLACE back to 081:899-964,
--      verbatim. The on_sale transition loses the four SALEABLE gates
--      (org_not_saleable/connect_not_ready/signing_not_ready/fee_policy_unset)
--      and reverts to ONLY the pre-102 empty_inventory check.
--   3. catalog.set_platform_config — CREATE OR REPLACE back to 093:6544-6927,
--      verbatim. signing.expected_key_fingerprint and
--      signing.expected_max_not_after DROP OUT of the v_dual prefix test and
--      revert to single-admin, un-parked writes — the SAME exposure 102's
--      header describes for the pre-102 state. signing.monitor_enabled is
--      untouched either way (102 never added it to v_dual).
--
-- ============================================================================

begin;

drop function if exists kernel.get_ticket_signing_context(uuid);


-- ---- restore catalog.publish_event to 081:899-964, verbatim ----------------
create or replace function catalog.publish_event(
  p_event_id uuid, p_target_status text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_org_id  uuid;
  v_venue   uuid;
  v_status  text;
  v_ok      boolean;
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


-- ---- restore catalog.set_platform_config to 093:6544-6927, verbatim -------
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
  v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like 'authn.%'
         or p_key like 'comp.%'   or p_key like 'wallet.%' or p_key like 'credential.%'
         or p_key like 'door.session\_%' or p_key like 'fee.%'
         or p_key like 'deletion.%' or p_key like 'ticket.%';

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
