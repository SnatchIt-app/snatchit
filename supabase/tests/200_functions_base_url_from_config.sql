-- 200_functions_base_url_from_config.sql — pgTAP for migration 133.
-- Property: no function body and no cron command in this database names the
-- production project host; every former site reads Vault `project_url` and is
-- guarded so that "no configuration ⇒ no request". Structural assertions run
-- identically on the local harness (net.http_post is a stub there) and on the
-- CI stack (real pg_net; the CI egress gate is the behavioural proof: after 133
-- the migrations job shows zero pg_net attempts). Negative control: on the 130
-- chain without 133 the first two assertions fail (4 functions, 5 cron jobs).
BEGIN;
SELECT plan(24);

-- ── A. the property itself
SELECT is((SELECT count(*)::int FROM pg_proc  WHERE prosrc  LIKE '%hqycwntpfoztoinemqns%'), 0,
  'A1: no function body names the production host');
SELECT is((SELECT count(*)::int FROM cron.job WHERE command LIKE '%hqycwntpfoztoinemqns%'), 0,
  'A2: no cron command names the production host');
SELECT is((SELECT count(*)::int FROM pg_proc WHERE prosrc LIKE '%.supabase.co/functions/v1/%'), 0,
  'A3: no function body inlines ANY project functions URL');
SELECT is((SELECT count(*)::int FROM cron.job WHERE command LIKE '%.supabase.co/functions/v1/%'), 0,
  'A4: no cron command inlines ANY project functions URL');

-- ── B. every former site now reads the configuration and is guarded
SELECT matches((SELECT prosrc FROM pg_proc WHERE oid = 'public.notify_bid_placed'::regproc),
  'name = ''project_url''', 'B1: notify_bid_placed reads project_url');
SELECT matches((SELECT prosrc FROM pg_proc WHERE oid = 'public.notify_bid_placed'::regproc),
  'IF v_key IS NOT NULL AND v_url IS NOT NULL THEN', 'B2: notify_bid_placed posts only with key AND url');
SELECT matches((SELECT prosrc FROM pg_proc WHERE oid = 'public.notify_transfer_event'::regproc),
  'name = ''project_url''', 'B3: notify_transfer_event reads project_url');
SELECT matches((SELECT prosrc FROM pg_proc WHERE oid = 'public.notify_transfer_event'::regproc),
  'IF v_key IS NOT NULL AND v_url IS NOT NULL THEN', 'B4: notify_transfer_event posts only with key AND url');
SELECT matches((SELECT prosrc FROM pg_proc WHERE oid = 'public.notify_moderation_event'::regproc),
  'name = ''project_url''', 'B5: notify_moderation_event reads project_url');
SELECT matches((SELECT prosrc FROM pg_proc WHERE oid = 'public.notify_moderation_event'::regproc),
  'IF v_key IS NOT NULL AND v_url IS NOT NULL THEN', 'B6: notify_moderation_event posts only with key AND url');
SELECT matches((SELECT prosrc FROM pg_proc WHERE oid = 'kernel.check_signing_key_invariants'::regproc),
  'if exists \(select 1 from vault\.decrypted_secrets where name = ''project_url''\) then',
  'B7: signing monitor posts only when project_url exists');

-- the five crons: present exactly once, schedule unchanged, guarded, config-driven
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname = 'enforce-transfer-expiry' AND schedule = '*/2 * * * *'), 1, 'B8: enforce-transfer-expiry once, */2');
SELECT matches((SELECT command FROM cron.job WHERE jobname = 'enforce-transfer-expiry'),
  'WHERE EXISTS \(SELECT 1 FROM vault\.decrypted_secrets WHERE name = ''project_url''\)', 'B9: enforce-transfer-expiry guarded (032 was unconditional)');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname = 'crm-export-build-tick' AND schedule = '* * * * *'), 1, 'B10: crm-export-build-tick once, every minute');
SELECT matches((SELECT command FROM cron.job WHERE jobname = 'crm-export-build-tick'),
  'and exists \(select 1 from vault\.decrypted_secrets where name = ''project_url''\)', 'B11: crm-export-build-tick guarded on project_url (and still on the worker secret)');
SELECT matches((SELECT command FROM cron.job WHERE jobname = 'crm-export-build-tick'),
  'name = ''crm_export_worker_secret''\)', 'B12: crm-export-build-tick keeps the E-79 worker-secret guard');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname = 'crm-export-purge-tick' AND schedule = '*/15 * * * *'), 1, 'B13: crm-export-purge-tick once, */15');
SELECT matches((SELECT command FROM cron.job WHERE jobname = 'crm-export-purge-tick'),
  'and exists \(select 1 from vault\.decrypted_secrets where name = ''project_url''\)', 'B14: crm-export-purge-tick guarded on project_url');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname = 'refund-execute-tick' AND schedule = '*/2 * * * *'), 1, 'B15: refund-execute-tick once, */2');
SELECT matches((SELECT command FROM cron.job WHERE jobname = 'refund-execute-tick'),
  'refund\.executor_enabled.*and exists \(select 1 from vault\.decrypted_secrets where name = ''project_url''\) then net\.http_post',
  'B16: refund-execute-tick posts only when armed AND configured');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname = 'payout-execute-tick' AND schedule = '*/10 * * * *'), 1, 'B17: payout-execute-tick once, */10');
SELECT matches((SELECT command FROM cron.job WHERE jobname = 'payout-execute-tick'),
  'payout\.executor_enabled.*and exists \(select 1 from vault\.decrypted_secrets where name = ''project_url''\) then net\.http_post',
  'B18: payout-execute-tick posts only when armed AND configured');

-- ── C. the bodies still run: the monitor completes with the URL absent and present
--       (the harness stubs net.http_post; on CI pg_net enqueues to an unresolvable
--       host, which the egress gate counts as refused, never as answered).
SELECT lives_ok($$SELECT kernel.check_signing_key_invariants()$$, 'C1: signing monitor runs with project_url absent');
DO $seed$
BEGIN
  BEGIN
    PERFORM vault.create_secret('https://example.invalid', 'project_url');
  EXCEPTION WHEN undefined_function THEN
    INSERT INTO vault.decrypted_secrets (name, decrypted_secret) VALUES ('project_url', 'https://example.invalid');
  END;
END $seed$;
SELECT lives_ok($$SELECT kernel.check_signing_key_invariants()$$, 'C2: signing monitor runs with project_url present (rolled back with this transaction)');

SELECT * FROM finish();
ROLLBACK;
