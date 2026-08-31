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
-- IT REMOVES ONLY 078-OWNED CONTENT. Packages 076 and 077 are untouched.
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
begin
  -- Partial-apply tolerant: to_regclass returns NULL for a table that never
  -- got created, so a half-applied 078 still rolls back.
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
-- PART 1 — the seed rows this package inserted
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
