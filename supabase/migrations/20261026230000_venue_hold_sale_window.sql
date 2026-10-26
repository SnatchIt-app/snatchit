-- ============================================================================
-- 20261026230000_venue_hold_sale_window.sql — registry 185 / pgTAP 255 (A writes; D reviews the 162 interplay).
--
-- WHAT THIS MIGRATION IS. DRAFT / unapplied / undeployed. Body-only CREATE OR REPLACE of ONE function,
-- venue.reserve_primary_inventory(uuid, integer, text) — the BUYER hold — at its exact signature. The new
-- body = its APPLIED predecessor (081 PART 10; no migration on the stacked tree 159 -> 176 -> 160 -> 161 ->
-- 162 replaces it — measured with pg_get_functiondef on a clone) + ONE marked block. No new function, no
-- signature change, no grant change, no table, no public-schema object; Gate-2 census, grant-decision
-- manifest and expected_grants.txt unchanged (+0). Replay-safe: CREATE OR REPLACE behind an md5
-- pre-flight that accepts only the predecessor or this file's own body. ORDER: after 162
-- (20261026100000), whose predicate it calls; the pre-flight refuses any other body.
--
-- ── THE RULING (A, 2026-10-26; planning CONTRACTS.md §2 C2 "Sale windows") ───────────────────
-- A tier's sale window (162: venue.ticket_type.sale_starts_at / sale_ends_at, read through
-- venue.ticket_type_on_sale) is enforced when a BUYER hold is created; outside it the hold is refused.
-- SCOPE (A's decision on the first draft, 2026-10-26): buyer path only. venue.create_inventory_hold
-- (staff) is an organizer override and keeps 081's behaviour exactly — no window, hidden or
-- event-status check; this file does not touch it (md5(pg_get_functiondef) stays f177b73fadaa60234a6d416fed558d11,
-- pinned by 255). Checkout (venue.create_primary_checkout) does not re-check — it requires covering
-- holds, and a hold obtained in-window may be paid within its TTL. Comps (allocate_comp / issue_comp,
-- 086) are not changed.
--
-- ── WHAT CHANGES (the one spot marked `185 BLOCK W`) ──────────────────────────────────────────
--   reserve_primary_inventory — after the idempotency replay (a replay of a hold that succeeded
--     in-window still returns idempotency_replay + the original hold_id + expiry after the window
--     closes) and after the dark-flag / event / session gates (feature_disabled, not_on_sale,
--     session_terminal keep answering first); BEFORE the per-user cap lock, the TTL read and every
--     inventory/hold write: NOT venue.ticket_type_on_sale(<the batch's tier>, now()) ->
--     'precondition_failed: tier_not_on_sale' (162 defines no refusal code; this is the new one).
-- Semantics are 162's predicate verbatim, intended for buyers: starts inclusive, ends exclusive,
-- NULL = open on that side; a hidden tier is never on sale (a buyer can no longer hold a HIDDEN
-- tier's batch, which 081 allowed); the event must be on_sale/live (already 081's not_on_sale gate,
-- which answers first). The read takes no lock on the tier row (the setter locks it FOR UPDATE): a
-- hold is judged at its own transaction's now(), the instant semantics of every other gate here.
--
-- ── SOURCES READ, NOT ASSUMED ─────────────────────────────────────────────────────────────────
-- 081:527-664 (the body; this file carries its pg_get_functiondef text from the stacked clone,
-- byte-equal), 081:157 (inventory_hold_command_uq), 162 PART 8 (ticket_type_on_sale: STABLE
-- SECURITY DEFINER, search_path=''; EXECUTE authenticated only — this definer body calls it as the
-- owner, as 162's GRANT DECISIONS anticipate), 086 PART 18 (comps), CONTRACTS.md §2 C2.
--
-- ── GRANTS / FOUR-FILE RULE ──────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE keeps owner, proacl, prosecdef and proconfig; nothing is restated. The CI grant
-- gates read `public` only: no manifest row, no expected_grants line, Gate-2 census +0. The
-- post-apply self-check asserts definer, search_path and the exact ACL captured by the pre-flight.
--
-- ── MD5 — md5(pg_get_functiondef(...)) ──────────────────────────────────────────────────────
--   reserve_primary_inventory  predecessor 3538344c0418c7b322accafdee76f0f6   185 d30669daef75abe15725aa0b04a107b0
--   create_inventory_hold      NOT touched             f177b73fadaa60234a6d416fed558d11 (081)
-- Strip rule: delete every line from '-- ── 185 BLOCK W …' through '-- ── 185 BLOCK W END' (both
-- markers included) and the predecessor is reproduced byte for byte (255 A11).
--
-- ROLLBACK: supabase/rollbacks/20261026230000_venue_hold_sale_window_rollback.sql restores the
-- predecessor body verbatim (inverse guard + post-restore self-check).
-- ORDER: a later rollback of 162 must run after 185's rollback (162's drops venue.ticket_type_on_sale,
-- which this body calls; plpgsql records no dependency). D is extending 162's G2 guard to refuse it.
-- VERIFICATION (after apply):
--   select md5(pg_get_functiondef('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure));   -- d30669daef75abe15725aa0b04a107b0
--   select md5(pg_get_functiondef('venue.create_inventory_hold(uuid, integer, text, text)'::regprocedure));  -- f177b73fadaa60234a6d416fed558d11 (unchanged)
-- LOCKS / RUNTIME: CREATE OR REPLACE FUNCTION only; no data read or written; lock_timeout 3s.
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT (stacking guard): the body being replaced must be EXACTLY its applied predecessor (first
-- apply) or EXACTLY this migration's body (idempotent re-apply). Anything else is a later change (or a
-- hotfix) that CREATE OR REPLACE would silently overwrite — refuse; the single transaction then changes
-- nothing. The ACL is captured (transaction-local) for the post-apply self-check.
do $pf$
declare
  v_r text := md5(pg_get_functiondef(to_regprocedure('venue.reserve_primary_inventory(uuid, integer, text)')));
begin
  if v_r is null or v_r not in ('3538344c0418c7b322accafdee76f0f6',   -- 081 body (predecessor on the stacked tree)
                                'd30669daef75abe15725aa0b04a107b0') then -- this migration's body (re-apply)
    raise exception 'precondition_failed: 185 refuses to overwrite an unexpected venue.reserve_primary_inventory body (md5 %) — re-examine the migration order; nothing changed', coalesce(v_r, '<missing>');
  end if;
  perform set_config('a185.acl_r', (select coalesce(proacl::text, '<default>') from pg_proc where oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure), true);
end $pf$;

-- ── venue.reserve_primary_inventory: the 081 body + 185 BLOCK W
CREATE OR REPLACE FUNCTION venue.reserve_primary_inventory(p_batch_id uuid, p_quantity integer, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid;
  v_flag     boolean;
  v_held     integer;
  v_cap      integer;
  v_sold     integer;
  v_s_status   text;
  v_sess_status text;
  v_ttl      interval;
  v_cap_max  integer;
  v_active   integer;
  v_hold_id  uuid;
  v_expires  timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'precondition_failed: bad_quantity';
  end if;

  -- OR-17 F-1: a pending-deletion caller may not ACQUIRE new inventory.
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending';
  end if;

  -- Idempotency short-circuit (§5.3): a replay of a SUCCEEDED reserve returns
  -- the original hold, not oversell_rejected (the caller's own committed hold
  -- fills the batch, so the oversell gate below would misreport it).
  declare v_ex_hold uuid; v_ex_exp timestamptz;
  begin
    select hold_id, expires_at into v_ex_hold, v_ex_exp
      from venue.inventory_hold
     where identity_id = v_uid and command_idempotency_key = p_command_key;
    if v_ex_hold is not null then
      return jsonb_build_object('status','idempotency_replay','hold_id',v_ex_hold,
                                'expires_at',v_ex_exp);
    end if;
  end;

  -- NATIVE ISSUANCE GATE (§4): real draws are gated behind the flag, false for
  -- the entire life of 081. The flag is checked BEFORE any counter mutation, so
  -- the substrate provably cannot draw while native issuance is dark.
  select (c.value #>> '{}')::boolean into v_flag
    from catalog.platform_config c
   where c.key = 'feature.native_issuance_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;

  -- the batch's EVENT must be on_sale/live AND its SESSION must not be terminal
  -- (§5.3: "batch's session/event on_sale/live"; a session carries its own
  -- cancelled/completed state, 078).
  select e.status, s.status into v_s_status, v_sess_status
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
    join catalog.event_session s on s.session_id = b.event_session_id
   where b.batch_id = p_batch_id;
  if v_s_status is null then
    raise exception 'not_found: batch %', p_batch_id using errcode = 'P0002';
  end if;
  if v_s_status not in ('on_sale','live') then
    raise exception 'precondition_failed: not_on_sale';
  end if;
  if v_sess_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;
  -- ── 185 BLOCK W — tier sale window (A's ruling 2026-10-26, CONTRACTS C2): refuse when the batch's
  -- tier is not on sale at now() by D's 162 predicate venue.ticket_type_on_sale (starts inclusive,
  -- ends exclusive, NULL = open; hidden tiers and events not on_sale/live are never on sale).
  -- After the idempotency replay above (an in-window hold replays unchanged after the window
  -- closes) and the flag/event/session gates; before the cap lock, the TTL and every write below.
  if not venue.ticket_type_on_sale(
           (select b.ticket_type_id from venue.inventory_batch b where b.batch_id = p_batch_id), now()) then
    raise exception 'precondition_failed: tier_not_on_sale';
  end if;
  -- ── 185 BLOCK W END

  -- Per-user active-hold cap (C5) via an advisory xact lock on the identity —
  -- NEVER a COUNT(*)<limit trigger (write-skew). The cap key is a PFA-9 CLASS A
  -- key with NO frozen spelling (erratum E-28): unseeded => fail-to-ZERO
  -- (AUTHZ-M8 precedent), so a missing seed refuses every reserve loudly rather
  -- than admitting unbounded holds silently. Unreachable while the flag is off.
  perform pg_advisory_xact_lock(hashtext('inv_hold_cap:'||v_uid::text));
  begin
    select (c.value #>> '{}')::integer into v_cap_max
      from catalog.platform_config c
     where c.key = 'inventory.per_user_active_hold_max'
     order by c.version desc limit 1;
  exception when others then v_cap_max := null;
  end;
  v_cap_max := coalesce(v_cap_max, 0);
  select count(*) into v_active from venue.inventory_hold h
   where h.identity_id = v_uid and h.status = 'active';
  if v_active + 1 > v_cap_max then
    raise exception 'precondition_failed: hold_cap_exceeded';
  end if;

  -- Hold TTL is a PFA-9 CLASS A key with NO frozen spelling (E-28): unseeded =>
  -- REFUSE rather than invent a business policy (a TTL is policy, not a default).
  begin
    select (c.value #>> '{}')::interval into v_ttl
      from catalog.platform_config c
     where c.key = 'inventory.hold_ttl_interval'
     order by c.version desc limit 1;
  exception when others then v_ttl := null;
  end;
  if v_ttl is null then
    raise exception 'precondition_failed: hold_ttl_unset';
  end if;
  v_expires := now() + v_ttl;

  -- THE OVERSELL CHOKE-POINT: FOR UPDATE on the counter row, then the CHECK.
  select b.held, b.capacity, b.sold into v_held, v_cap, v_sold
    from venue.inventory_batch b where b.batch_id = p_batch_id for update;
  if v_held + v_sold + p_quantity > v_cap then
    raise exception 'precondition_failed: oversell_rejected';
  end if;

  update venue.inventory_batch set held = held + p_quantity, updated_at = now()
   where batch_id = p_batch_id;

  insert into venue.inventory_hold
         (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  values (p_batch_id, v_uid, p_quantity, 'active', v_expires, p_command_key)
  returning hold_id into v_hold_id;

  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (p_batch_id, 'hold', p_quantity, 0, 'primary_sale', v_hold_id, v_uid);

  return jsonb_build_object('status','ok','hold_id',v_hold_id,'expires_at',v_expires,
                            'remaining',v_cap - (v_held + p_quantity) - v_sold);
exception when unique_violation then
  raise exception 'precondition_failed: idempotency_replay';
end;
$function$;

-- ── POST-APPLY SELF-CHECK: the body just written must be EXACTLY this migration's (a modified copy of
-- this file would pass the pre-flight as a "re-apply" and overwrite; this makes it fail its own
-- transaction), and SECURITY DEFINER, search_path='' and the EXECUTE ACL captured by the pre-flight must be
-- unchanged. Outside the function, so its md5 does not move.
do $pc$
begin
  if md5(pg_get_functiondef('venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure)) <> 'd30669daef75abe15725aa0b04a107b0' then
    raise exception 'precondition_failed: 185 post-apply self-check — the written venue.reserve_primary_inventory body is not this migration''s; this file was modified';
  end if;
  if exists (select 1 from pg_proc
              where oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure
                and (not prosecdef or proconfig is distinct from array['search_path=""']))
  or (select coalesce(proacl::text, '<default>') from pg_proc where oid = 'venue.reserve_primary_inventory(uuid, integer, text)'::regprocedure) <> current_setting('a185.acl_r') then
    raise exception 'precondition_failed: 185 post-apply self-check — SECURITY DEFINER, search_path or the EXECUTE ACL moved';
  end if;
end $pc$;

commit;
