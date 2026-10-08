-- ============================================================================
-- Operating console — acceptance evidence queries (READ-ONLY).
-- Run in the Supabase SQL editor after the release steps. Prints no personal
-- data beyond masked emails. Modifies nothing.
-- ============================================================================

-- G0 — release state
select 'ledger_tip' as check, max(version) as value from supabase_migrations.schema_migrations where version ~ '^[0-9]{3}$'
union all select 'ledger_115_120 (expect 115,116,117,118,119,120)', coalesce(string_agg(version, ',' order by version), '') from supabase_migrations.schema_migrations where version in ('115','116','117','118','119','120')
union all select 'ledger_110_114 (expect empty)', coalesce(string_agg(version, ','), '') from supabase_migrations.schema_migrations where version in ('110','111','112','113','114')
union all select 'ops_tables (expect 13)', count(*)::text from information_schema.tables where table_schema = 'ops'
union all select 'ops_cron_jobs (expect 2)', count(*)::text from cron.job where jobname like 'ops-%'
union all select 'listing_guard_trigger (expect 1)', count(*)::text from pg_trigger where tgname = 'trg_guard_listing_seller_not_blocked'
union all select 'storage_policies (expect 12)', count(*)::text from pg_policy where polrelid = 'storage.objects'::regclass
union all select 'refund_execute_enabled (expect false)', value::text from ops.setting where key = 'refund_execute_enabled'
union all select 'actions_enabled (expect true)', value::text from ops.setting where key = 'actions_enabled';

-- G1 — founders: membership + MFA readiness (masked)
select a.label, left(u.email, 1) || '***@' || split_part(u.email, '@', 2) as email_masked,
       (select count(*) from auth.mfa_factors f where f.user_id = u.id and f.status = 'verified') as verified_totp_factors,
       u.last_sign_in_at
  from public.admin_users a join auth.users u on u.id = a.user_id order by a.created_at;

-- G4/G5 — evidence access audit trail (after a founder opens an evidence file)
select occurred_at, actor_role, subject_kind, subject_id, after ->> 'slot' as slot
  from ops.audit where action = 'evidence.viewed' order by occurred_at desc limit 5;

-- G7 — pause/containment audit trail
select occurred_at, actor_role, subject_ref, after ->> 'after' as new_value
  from ops.audit where action = 'action.setting_set' and subject_ref = 'actions_enabled' order by occurred_at desc limit 5;

-- G8 — no refund can execute: every refund_execute action is rejected as disabled
select state, reject_reason, count(*) from ops.action where action_type = 'refund_execute' group by 1, 2;

-- Detectors ran and are healthy; queue populated
select job_name, last_success_at, consecutive_failures, backoff_until from ops.job_state order by job_name;
select case_type, priority, count(*) from ops."case" where status not in ('resolved','dismissed') group by 1, 2 order by 1, 2;
