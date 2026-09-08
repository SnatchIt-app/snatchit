-- 078_catalog_reference_data_and_flags_rollback.sql
-- =============================================================================
-- ROLLBACK for Phase-2 package 078. Posture: CLEAN-WHILE-EMPTY (plan §8/078:
-- "Drop resale_policy, platform_config, event_session, event, venue").
--
-- VALID ONLY IN THE EMPTY / FLAG-OFF WINDOW. Once catalog.venue/event/
-- event_session/resale_policy hold real reference data, or catalog.platform_config
-- holds any version this package did not seed, this file REFUSES and the posture
-- becomes forward-fix-only: dropping a config version that a
-- kernel.approval_request pins, or a resale_policy version a live listing
-- snapshots, destroys the interpretability those versions exist to provide.
--
-- IT REMOVES ONLY 078-OWNED CONTENT. Packages 076 and 077 are untouched, with ONE
-- deliberate exception stated in Part 0: this file restores the PRE-HARDENING-1
-- body of kernel.sweep_deletion_pending, verbatim from migration 077, because 078
-- replaced that body. Migration 077 itself is never modified.
--
-- Self-transactional: begin/commit are in this file.
-- =============================================================================

begin;

-- =============================================================================
-- PART 0 — REFUSAL GUARD
-- =============================================================================

do $guard$
declare
  v_seeded  constant text[] := array[
    'feature.native_issuance_enabled','feature.native_scanning_enabled',
    'feature.native_resale_enabled','wallet.apple.enabled','notify.announcements_enabled',
    'credential.wallet_exp_skew','credential.wallet_default_span','credential.app_ttl_interval',
    'wallet.apple.push_retry_max','wallet.apple.cert_expiry_warn_interval',
    'door.implicit_freeze_offset_interval','door.manifest_ttl_interval',
    'door.manifest_early_open_window','door.max_override_interval',
    'door.session_ttl_interval','door.session_absolute_max_interval',
    'door.session_post_session_grace',
    'refund.org_auto_execute_max_minor','refund.org_dual_control_max_minor',
    'refund.request_ttl_hours','refund.scanned_atom_policy',
    'refund.buyer_self_service_window_hours','refund.buyer_self_service_max_minor',
    'refund.buyer_fee_refundable','refund.platform_support_max_minor',
    'payout.destination_cooldown_hours','payout.destination_probation_days',
    'payout.request_auto_max_minor','payout.dual_control_min_minor',
    'authn.money_action_max_age_seconds','authn.money_action_required_aal',
    'authn.money_role_maturity_hours',
    'comp.per_staff_step_up_max_units','comp.per_staff_step_up_window_hours',
    'notify.announcement_hold_seconds','notify.announcement_dual_control_threshold',
    'notify.announcement_max_per_session','notify.announcement_min_interval_seconds',
    'crm_export.constraint_set_version','resale.buy_now_reservation_ttl_minutes',
    'retention.backup_window_days'];
  v_n   bigint := 0;
  v_cfg bigint := 0;
  v_ref bigint := 0;
  v_appr bigint := 0;
begin
  -- Partial-apply tolerant: to_regclass returns NULL for a table that never
  -- got created, so a half-applied 078 still rolls back.
  -- ROLLBACK_GUARD_ROW_SECURITY (obligation opened by 091's E-151, CLOSED at the 2026-09-02
  -- release-readiness pass): the guard counts RLS-enabled zero-policy tables; run by a
  -- non-owner, non-BYPASSRLS role it would read 0 rows and FAIL OPEN. Count with row
  -- security off — same house pattern as the 091/092 rollbacks.
  set local row_security = off;
  if to_regclass('catalog.venue')          is not null then
    execute 'select count(*) from catalog.venue'          into v_n; end if;
  if to_regclass('catalog.event')          is not null then
    execute 'select count(*) + $1 from catalog.event'          into v_n using v_n; end if;
  if to_regclass('catalog.event_session')  is not null then
    execute 'select count(*) + $1 from catalog.event_session'  into v_n using v_n; end if;
  if to_regclass('catalog.resale_policy')  is not null then
    execute 'select count(*) + $1 from catalog.resale_policy'  into v_n using v_n; end if;
  if v_n > 0 then
    raise exception 'REFUSED: package 078 reference tables hold % row(s). CLEAN-WHILE-EMPTY has expired; this rollback is forward-fix-only.', v_n;
  end if;

  -- platform_config: the 41 seed rows at version 1 are this package's own and are
  -- expected. ANY other row is a config CHANGE somebody made through
  -- catalog.set_platform_config, and dropping the table would destroy the version
  -- history that a kernel.approval_request's config_versions pins.
  if to_regclass('catalog.platform_config') is not null then
    execute 'select count(*) from catalog.platform_config where version <> 1 or not (key = any($1))'
      into v_cfg using v_seeded;
    if v_cfg > 0 then
      raise exception 'REFUSED: catalog.platform_config holds % row(s) this package did not seed. Config history is append-only and pinned by kernel.approval_request; roll forward instead.', v_cfg;
    end if;
  end if;

  -- A PARKED config change writes NO platform_config row at all — it writes a
  -- kernel.approval_request whose config_versions pins (key, version). Between
  -- this package and 085 (which owns the approve verb) parking is the ONLY
  -- outcome a money-namespace write can have, so the row-count arm above is
  -- blind to 100% of the config activity this package permits. Dropping
  -- platform_config under a pending request strands it: it pins a version of a
  -- relation that no longer exists, and 085's approve verb would later insert
  -- against it.
  if to_regclass('kernel.approval_request') is not null then
    execute $q$select count(*) from kernel.approval_request
                where subject_kind = 'config_key'
                  and state = 'pending'$q$
      into v_appr;
    if v_appr > 0 then
      raise exception 'REFUSED: % pending config approval request(s) pin a catalog.platform_config version. Resolve or cancel them first; config history is append-only and this rollback would strand the pin.', v_appr;
    end if;
  end if;

  -- The MB-5 sentinels are custody objects the moment 079+ writes a log row
  -- against them. Refuse rather than let an ON DELETE RESTRICT decide.
  if to_regclass('kernel.ticket_ownership_log') is not null then
    execute $q$select count(*) from kernel.ticket_ownership_log
                 where to_identity in ('00000000-0000-0000-0000-0000000000f0',
                                       '00000000-0000-0000-0000-0000000000f1')
                    or actor_identity in ('00000000-0000-0000-0000-0000000000f0',
                                          '00000000-0000-0000-0000-0000000000f1')$q$
      into v_ref;
    if v_ref > 0 then
      raise exception 'REFUSED: the MB-5 sentinels appear in % custody-ledger row(s). They are permanent once used.', v_ref;
    end if;
  end if;
end
$guard$;

-- =============================================================================
-- PART 1 — HARDENING-1 REVERSAL: restore migration 077's body VERBATIM.
-- Migration 077 is not modified; this is the same CREATE OR REPLACE mechanism
-- 078 used, run in the opposite direction. Every byte below is 077's.
-- =============================================================================

create or replace function kernel.sweep_deletion_pending(p_limit int default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row        record;
  v_reason     text;
  v_swept      integer := 0;
  v_blocked    integer := 0;
  v_tombstoned integer := 0;
begin
  for v_row in
    select e.identity_id, e.deletion_requested_at
      from kernel.identity_ext e
     where e.deletion_state = 'DELETION_PENDING'
     limit p_limit
     for update skip locked   -- SKIP LOCKED over the pending partial index;
                              -- FOR UPDATE is the F-11 terminal-entry lock
  loop
    begin
      v_swept := v_swept + 1;

      -- BP-1..BP-12 in order (dsm §2; routing per §20.17.4 + hooks §20.17.5).
      -- First true predicate is recorded; the pass moves on.
      v_reason := coalesce(
        -- BP-1 live custody (hook; kernel.tickets is 079)
        kernel.deletion_blockers_custody(v_row.identity_id),
        -- BP-2 live wallet pass (hook; 083)
        kernel.deletion_blockers_wallet(v_row.identity_id),
        -- BP-3/BP-4 (+ BP-7/BP-8 native twins from 088) (hook)
        kernel.deletion_blockers_market(v_row.identity_id),
        -- BP-5 (+ BP-6 kernel arm, BP-12 refund/window arm from 085) (hook)
        kernel.deletion_blockers_money(v_row.identity_id),
        -- BP-6 live arm: unresolved payout hold/probation on the live rail
        (select 'BP-6: unresolved payout hold/probation on a live transfer — resolves via review resolution or hold lapse'
          where exists (select 1 from public.transfers t
                         where t.seller_id = v_row.identity_id
                           and (t.payout_review_status in ('held','manual_review')
                                or t.payout_hold_until > now()))),
        -- BP-7 live arm: open or disputed transfer (incl. expired-in-dispute)
        (select 'BP-7: an open or disputed live transfer must reach a terminal state first'
          where exists (select 1 from public.transfers t
                         where (t.seller_id = v_row.identity_id or t.buyer_id = v_row.identity_id)
                           and (t.status in ('pending','seller_sent','disputed')
                                or (t.status = 'expired'
                                    and exists (select 1 from public.disputes d
                                                 where d.transfer_id = t.id
                                                   and d.status not in ('won','lost','warning_closed','charge_refunded')))))),
        -- BP-8 live arm: in-flight buy-now reservation
        (select 'BP-8: a live buy-now reservation is in flight — it must land or be released'
          where exists (select 1 from public.listings l
                         where l.reserved_by = v_row.identity_id)),
        -- BP-9 live arm: won-unsettled auction, plus live-auction high bidder
        (select 'BP-9: a won auction has not settled (or a live auction carries this account as high bidder)'
          where exists (select 1 from public.listings l
                         where l.winner_user_id = v_row.identity_id
                           and not exists (select 1 from public.transfers t
                                            where t.listing_id = l.id
                                              and t.status in ('buyer_confirmed','auto_released')))
             or exists (select 1 from public.listings l
                         where l.highest_bidder_id = v_row.identity_id
                           and l.auction_status = 'active')),
        -- BP-10 negative settlement obligation (hook predicate, OR-21)
        (select 'BP-10: an outstanding settlement obligation must be recovered or written off'
          where kernel.has_outstanding_obligations(v_row.identity_id)),
        -- BP-11 sole org_owner (direct — 077 tables)
        (select 'BP-11: sole org_owner of organization ' || m.org_id::text
                || ' — transfer ownership or close the org first'
           from kernel.org_member m
          where m.identity_id = v_row.identity_id and m.role = 'org_owner'
            and not exists (select 1 from kernel.org_member m2
                             where m2.org_id = m.org_id and m2.role = 'org_owner'
                               and m2.identity_id <> m.identity_id)
          limit 1),
        -- BP-12 pending-order arm (hook; venue.order is 082)
        kernel.deletion_blockers_orders(v_row.identity_id)
      );

      if v_reason is not null then
        v_blocked := v_blocked + 1;
        update kernel.identity_ext
           set deletion_block_reason = v_reason
         where identity_id = v_row.identity_id;
        continue;
      end if;

      -- ===== TERMINAL ENTRY (idempotent; dsm §4) ============================
      -- (a0) close the BP-11 write-skew (red-team C blocker 1): the RPC-side
      --     last-owner re-counts serialize on the ORGANIZATION row, so the
      --     terminal member-delete must too — lock every org the identity
      --     belongs to (ascending org_id; identity_ext -> organization is the
      --     existing accept_org_invite direction, no new deadlock class) and
      --     RE-VERIFY BP-11 under those locks. The unlocked coalesce pass
      --     above is the cheap early-out; THIS is the enforcement.
      perform 1
        from (select o.org_id
                from kernel.organization o
               where o.org_id in (select m.org_id from kernel.org_member m
                                   where m.identity_id = v_row.identity_id)
               order by o.org_id
                 for update) locked_orgs;
      if exists (select 1
                   from kernel.org_member m
                  where m.identity_id = v_row.identity_id and m.role = 'org_owner'
                    and not exists (select 1 from kernel.org_member m2
                                     where m2.org_id = m.org_id
                                       and m2.role = 'org_owner'
                                       and m2.identity_id <> m.identity_id)) then
        v_blocked := v_blocked + 1;
        update kernel.identity_ext
           set deletion_block_reason =
               'BP-11: sole org_owner (re-verified under the org locks) — transfer ownership first'
         where identity_id = v_row.identity_id;
        continue;
      end if;

      -- (a) the erased marker write — PFA-3: deletion_state := 'ERASED';
      --     deletion_requested_at is RETAINED (the durable record).
      update kernel.identity_ext
         set deletion_state        = 'ERASED',
             deletion_block_reason = null
       where identity_id = v_row.identity_id;

      -- (b) 077-plane role/invite clears (dsm §4.5 class 1; INV #1/#4-#8).
      --     BP-11 just proved no sole-ownership under this transaction's lock.
      --     No admin_audit rows: the sweep has no human actor and the
      --     SN-SYSTEM sentinel is a 078 seed (forward reference — E-5).
      delete from kernel.org_member    where identity_id = v_row.identity_id;
      delete from kernel.platform_role where identity_id = v_row.identity_id;
      update kernel.org_invite
         set status = 'revoked'
       where status = 'pending'
         and (invitee_identity_id = v_row.identity_id
              or invited_by = v_row.identity_id);

      -- (c) live public.* clears: the PR#28/020 cleanup semantics MINUS every
      --     sentinel repointing (dsm §4.5/§5; §20.15 write set transcribed —
      --     the own-live-auction cancel arm; CUSTODY-DEL-1 untouched; storage
      --     is the edge layer's step; auth.admin.deleteUser called by NOTHING).
      perform set_config('app.bypass_listing_guard', 'on', true);
      update public.listings
         set auction_status = 'cancelled',
             status         = 'active',
             reserved_by    = null,
             reserved_until = null,
             ended_at       = now()
       where seller_id = v_row.identity_id
         and auction_status in ('active','ended');
      perform set_config('app.bypass_listing_guard', 'off', true);

      -- (d) the four terminal cleanup hooks (no-ops until their packages)
      perform kernel.on_identity_erased_staff(v_row.identity_id);
      perform kernel.on_identity_erased_door(v_row.identity_id);
      perform kernel.on_identity_erased_market(v_row.identity_id);
      perform kernel.on_identity_erased_promoter(v_row.identity_id);

      -- (e) OPEN-6a: whether ERASED entry hard-deletes the demographic row is
      --     unruled — recorded here, deliberately NOT implemented.

      -- (f) BE-emit account_deletion_completed (R2 row 32) — last write. A
      --     failed PASS (quarantined exception above) re-runs terminal entry
      --     next tick and re-emits, collapsed by the once-ever key. A
      --     SWALLOWED emit beneath a committed tombstone is the accepted
      --     BEST-EFFORT loss (OR-14: the notice never gates the machine) —
      --     warning-visible; recorded in the 077 errata.
      begin
        perform notify.emit_event(
          'account_deletion_completed', 'identity', v_row.identity_id,
          'account_deletion_completed:' || v_row.identity_id::text,
          jsonb_build_object('deletion_requested_at', v_row.deletion_requested_at));
      exception when others then
        raise warning 'sweep_deletion_pending: best-effort completion emit failed for %: %',
          v_row.identity_id, sqlerrm;
      end;

      v_tombstoned := v_tombstoned + 1;
    exception when others then
      -- half-completion is re-detected next pass (the sweep is the detector);
      -- one poison identity never stops the tick
      raise warning 'sweep_deletion_pending: identity % failed: %', v_row.identity_id, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('swept', v_swept, 'blocked', v_blocked,
                            'tombstoned', v_tombstoned);
end;
$$;

-- =============================================================================
-- PART 2 — the seed rows this package inserted
-- =============================================================================

delete from kernel.identity_ext
 where identity_id in ('00000000-0000-0000-0000-0000000000f0',
                       '00000000-0000-0000-0000-0000000000f1');
delete from public.profiles
 where id in ('00000000-0000-0000-0000-0000000000f0',
              '00000000-0000-0000-0000-0000000000f1');
delete from auth.users
 where id in ('00000000-0000-0000-0000-0000000000f0',
              '00000000-0000-0000-0000-0000000000f1');

-- =============================================================================
-- PART 3 — functions (dropped before their tables so no body outlives its reads)
-- =============================================================================

drop function if exists kernel.money_role_grant_matured(uuid);
drop function if exists catalog.set_resale_policy(text,uuid,jsonb,text);
drop function if exists catalog.set_platform_config(text,jsonb,text,text);
drop function if exists catalog.update_event(uuid,jsonb,text);
drop function if exists catalog.create_event(uuid,text,jsonb,text);
drop function if exists catalog.create_event_session(uuid,jsonb,text);
drop function if exists catalog.update_venue(uuid,jsonb,text);
drop function if exists catalog.approve_venue(uuid,text,text,text);
drop function if exists catalog.create_venue(uuid,text,text,text,text);
drop function if exists catalog.effective_freeze_at(uuid);

-- =============================================================================
-- PART 4 — tables, in the frozen reverse order (plan §8/078 Rollback row)
-- Policies, indexes, grants and triggers fall with their tables.
-- =============================================================================

drop table if exists catalog.resale_policy;
drop table if exists catalog.platform_config;
drop table if exists catalog.event_session;
drop table if exists catalog.event;
drop table if exists catalog.venue;

commit;
