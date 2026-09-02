-- ============================================================================
-- 151_phase2_venue_settlement_and_export.sql — Phase-2 package 087 suite.
-- Frozen sources: plan §8/087 · schema §3.13/§3.14/§3.18 · RPC §10.1-10.3/
-- §17.22/§20.7.8/§20.11 · RLS §9.13/§9.14/§11.6/§16.6 · CRM §4-§8/§12 · ODR16 #34
-- (owner-ruled) · OR-1/OR-10/OR-19 · PFA-9 · PFA-28 (owner-signed: the three
-- customer_ref readers are PARKED FAIL-CLOSED; no pgcrypto, no weak fallback).
-- Native issuance stays DARK — the settlement money engine is exercised over
-- directly seeded lines, the export LIFECYCLE over directly staged job rows.
-- BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(213);

SELECT tap.seed_core();

CREATE TABLE tap.memo_151 (k text PRIMARY KEY, v text);
-- RETURNS void (the 150 lesson): a bare `SELECT tap._store151(...)` must print NOTHING.
CREATE FUNCTION tap._store151(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_151 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch151(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_151 WHERE k=$1 $m$;
-- definer reads of deny-all tables under superuser context
CREATE FUNCTION tap._job151(p_job uuid) RETURNS venue.export_job LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT j FROM venue.export_job j WHERE j.job_id = p_job $m$;
CREATE FUNCTION tap._audit151(p_subject uuid, p_action text, p_reason text DEFAULT NULL) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.admin_audit a WHERE a.subject_id = p_subject AND a.action = p_action AND (p_reason IS NULL OR a.reason_code = p_reason) $m$;
CREATE FUNCTION tap._auditcount151() RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.admin_audit $m$;
-- step-up: the money verbs (AUTHZ-M4) demand an aal2 claim on the session
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._aal1() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal1"}'::jsonb)::text, true); end $f$;
-- a fifth persona with NO role anywhere (the plain fan)
CREATE FUNCTION tap.fan151() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '55555555-5555-5555-5555-555555555555'::uuid $$;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES (tap.fan151(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan151@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- SECTION A — THE 087 CLOSED WORLD
-- ============================================================================
SELECT has_table('venue'::name,'settlement'::name, 'A1: venue.settlement');
SELECT has_table('venue'::name,'settlement_line'::name, 'A2: venue.settlement_line (AO)');
SELECT has_table('venue'::name,'export_job'::name, 'A3: venue.export_job (deny-all lifecycle + purge substrate)');
SELECT ok(to_regtype('kernel.settlement_line_candidate') IS NOT NULL,
  'A4: T-SCHEMA-SEAM-01 — kernel.settlement_line_candidate exists after replay (C116/S2-A)');
SELECT ok((SELECT bool_and(p.prorettype = 'kernel.settlement_line_candidate'::regtype AND p.proretset
                           AND p.proargnames = ARRAY['p_settlement_id'])
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('settlement_royalty_lines','settlement_commission_lines')),
  'A5: T-SCHEMA-SEAM-02 — both hooks RETURN SETOF the composite and carry exactly {p_settlement_id} (SEAM-2a)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname IN ('settlement_royalty_lines','settlement_commission_lines')), 2,
  'A6: exactly ONE overload of each hook (no accidental second signature)');
SELECT is((SELECT count(*)::int FROM kernel.settlement_royalty_lines(gen_random_uuid()))
        + (SELECT count(*)::int FROM kernel.settlement_commission_lines(gen_random_uuid())), 0,
  'A7: both hook stubs return ZERO rows at 087 (bodies land in 088/090)');
SELECT has_function('kernel'::name,'close_settlement'::name, ARRAY['uuid','text']::name[], 'A8: kernel.close_settlement (SSCAS #4)');
SELECT has_function('kernel'::name,'request_org_payout'::name, ARRAY['uuid','uuid','text']::name[], 'A9: kernel.request_org_payout');
SELECT has_function('venue'::name,'open_settlement'::name, ARRAY['uuid','uuid','uuid','jsonb','text']::name[], 'A10: venue.open_settlement');
SELECT ok((SELECT p.proargnames = ARRAY['p_actor','p_scope_kind','p_scope_id','p_template_id','p_raise'] AND p.pronargdefaults = 1
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='assert_may_request'),
  'A11: venue.assert_may_request(p_actor, p_scope_kind, p_scope_id, p_template_id, p_raise DEFAULT true) — the R1-4/C108 shape');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue' AND p.proname IN ('request_export','build_export_rows','finalize_export','authorize_export_download',
              'revoke_export','claim_artifacts_for_purge','confirm_artifact_purged','reconcile_export_orphans','list_export_jobs',
              'sweep_expired_exports','list_attendees','lookup_attendee','assert_may_request')), 13,
  'A12: the THIRTEEN CRM entry points exist (RPC §17.22 ×12 + §20.7.8)');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname IN ('sweep-expired-exports','crm-export-build-tick','crm-export-purge-tick')), 3,
  'A13: three 087 cron entries (CRON_SCHEDULE_REGISTER rows 087 ×3)');
SELECT ok((SELECT command LIKE '%crm-export-worker/build%' AND command LIKE '%X-Crm-Export-Worker%' AND command NOT LIKE '%/functions/v1/crm-export/%'
             FROM cron.job WHERE jobname='crm-export-build-tick')
       AND (SELECT command LIKE '%crm-export-worker/purge%' AND command LIKE '%X-Crm-Export-Worker%' FROM cron.job WHERE jobname='crm-export-purge-tick'),
  'A14: both pg_net ticks target the WORKER deployment and send the dedicated second-factor header (EDGE-2/EDGE-3)');
SELECT ok((SELECT public=false AND file_size_limit=33554432 AND allowed_mime_types=ARRAY['text/csv'] FROM storage.buckets WHERE id='crm-exports'),
  'A15: crm-exports bucket holds EXACTLY private / 32MB / text-csv (asserted as VALUES — the 073 lesson; §12 29)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='storage' AND c.relname='objects' AND pg_get_expr(p.polqual, p.polrelid) LIKE '%crm-exports%'), 0,
  'A16: ZERO storage.objects policies name crm-exports (§12 30)');
SELECT ok((SELECT pg_get_constraintdef(c.oid) NOT LIKE '%''all''%' FROM pg_constraint c
            WHERE c.conrelid='venue.export_job'::regclass AND c.contype='c' AND pg_get_constraintdef(c.oid) LIKE '%scope_kind%'),
  'A17: export_job.scope_kind CHECK has NO ''all'' member (EX-1; §12 20)');
SELECT is((SELECT c.confdeltype FROM pg_constraint c WHERE c.conrelid='venue.export_job'::regclass AND c.contype='f'
            AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='venue.export_job'::regclass AND attname='requested_by')]), 'r',
  'A18: ODR16 #34 (OWNER-RULED) — export_job.requested_by is ON DELETE RESTRICT, not CASCADE; the job row outlives its requester through the ordinary purge_after lifecycle');
SELECT ok((SELECT btrim(p.prosrc) <> 'select' AND p.prosrc LIKE '%cause%settlement%' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue' AND p.proname='on_payout_settled'),
  'A19: venue.on_payout_settled carries its REAL body (the 085 no-op stub is replaced — MB-2b)');
SELECT ok((SELECT NOT (p.proargnames @> ARRAY['p_cells_emitted']) AND NOT (p.proargnames @> ARRAY['p_cells_suppressed'])
             AND NOT (p.proargnames @> ARRAY['p_gate_evaluations'])
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='finalize_export'),
  'A20: T-RPC-CRM-08 — finalize_export has NO worker-supplied gate-counter parameter (AUTHZ-CRM2(1))');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname IN ('venue','kernel') AND p.prosrc ~* 'delete\s+from\s+storage\.objects'), 0,
  'A21: §12 31d — no venue/kernel routine performs the metadata-only DELETE FROM storage.objects');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relkind='r'), 23,
  'A22: venue holds 23 tables — 20 post-086 + settlement, settlement_line, export_job');

-- ============================================================================
-- SECTION B — GRANTS, RLS, AO
-- ============================================================================
SELECT ok(NOT has_table_privilege('authenticated','venue.export_job','SELECT') AND NOT has_table_privilege('anon','venue.export_job','SELECT'),
  'B1: export_job carries an EMPTY client grant set (§16.6)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relname='export_job'), 0,
  'B2: export_job carries ZERO policies (OR-1: no crm_export_builder role gate)');
SELECT ok((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            JOIN pg_proc p ON p.oid=t.tgfoid WHERE n.nspname='venue' AND c.relname='settlement_line'
              AND p.proname='raise_append_only' AND NOT t.tgisinternal)=1,
  'B3: settlement_line is append-only (raise_append_only)');
SELECT ok(NOT has_table_privilege('service_role','venue.settlement_line','UPDATE') AND NOT has_table_privilege('service_role','venue.settlement_line','DELETE'),
  'B4: settlement_line: no UPDATE/DELETE for service_role either (AO by grant)');
SELECT ok((SELECT bool_and(has_function_privilege('service_role', f, 'EXECUTE') AND NOT has_function_privilege('authenticated', f, 'EXECUTE') AND NOT has_function_privilege('anon', f, 'EXECUTE'))
  FROM unnest(ARRAY['venue.assert_may_request(uuid,text,uuid,text,boolean)','venue.build_export_rows(uuid,text,integer)',
    'venue.finalize_export(uuid,integer,integer,text,text)','venue.claim_artifacts_for_purge(integer)','venue.confirm_artifact_purged(uuid,text)',
    'venue.reconcile_export_orphans(uuid,text[])','venue.sweep_expired_exports()']) f),
  'B5: the seven EXEC-DEF CRM definers are service_role-ONLY (assert_may_request per OR-10; §16.6 service_role row)');
SELECT ok((SELECT bool_and(has_function_privilege('authenticated', f, 'EXECUTE') AND NOT has_function_privilege('anon', f, 'EXECUTE') AND NOT has_function_privilege('service_role', f, 'EXECUTE'))
  FROM unnest(ARRAY['venue.request_export(text,uuid,text,jsonb,text)','venue.authorize_export_download(uuid)','venue.revoke_export(uuid,text)',
    'venue.list_export_jobs(text,uuid,text)','venue.list_attendees(uuid,jsonb,text,text)','venue.lookup_attendee(uuid,text,text)',
    'venue.open_settlement(uuid,uuid,uuid,jsonb,text)','kernel.close_settlement(uuid,text)','kernel.request_org_payout(uuid,uuid,text)']) f),
  'B6: the nine caller-authorized verbs are authenticated-only (in-body authz), never anon, never service_role');
SELECT ok((SELECT bool_and(NOT has_function_privilege('authenticated', f, 'EXECUTE') AND NOT has_function_privilege('anon', f, 'EXECUTE') AND NOT has_function_privilege('service_role', f, 'EXECUTE'))
  FROM unnest(ARRAY['kernel.settlement_royalty_lines(uuid)','kernel.settlement_commission_lines(uuid)']) f),
  'B7: the two settlement seams are definer-internal — no client or machine grant');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            WHERE a.privilege_type='EXECUTE' AND n.nspname IN ('venue','kernel')
              AND p.proname IN ('open_settlement','close_settlement','request_org_payout','settlement_royalty_lines','settlement_commission_lines',
                'assert_may_request','request_export','build_export_rows','finalize_export','authorize_export_download','revoke_export',
                'sweep_expired_exports','claim_artifacts_for_purge','confirm_artifact_purged','reconcile_export_orphans','list_export_jobs',
                'list_attendees','lookup_attendee')
              AND (a.grantee = 0 OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname='anon'))), 0,
  'B8: PFA-1 sweep — zero PUBLIC/anon EXECUTE on any of the eighteen 087 functions');
SELECT ok((SELECT pg_get_functiondef(p.oid) ~ 'venue\.assert_may_request\(v_uid, p_scope_kind, p_scope_id, p_template_id\)'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='request_export')
       AND (SELECT pg_get_functiondef(p.oid) ~ 'venue\.assert_may_request\(v_uid, v_j\.scope_kind, v_j\.scope_id, v_j\.template_id\)'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='authorize_export_download'),
  'B9: T-RLS-CRM-05 / T-RPC-CRM-10 — request and download resolve to the SAME predicate in RAISING mode (an equality between call sites)');
SELECT is((SELECT string_agg(p.proname, ',' ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue' AND p.proname <> 'assert_may_request'
              AND p.prokind = 'f' AND p.prosrc ~ 'assert_may_request\([^;]*,\s*false\)'), 'list_export_jobs',
  'B10: T-RPC-CRM-06 — the non-raising opt-out (p_raise := false) has EXACTLY ONE caller, list_export_jobs (a false renders a disabled control, never gates a byte)');
SELECT ok(has_table_privilege('authenticated','venue.settlement','SELECT') AND has_table_privilege('authenticated','venue.settlement_line','SELECT'),
  'B11: settlement/settlement_line are policy-gated reads for authenticated (RLS §9.13/§9.14)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relname IN ('settlement','settlement_line')), 4,
  'B12: four settlement read policies (org finance/platform + venue finance, ×2 tables); writes are RPC-only');

-- ============================================================================
-- FIXTURE — org1 (seller owner) → venue1 → event1 → session1; org2 (other owner)
--   → venue2 → event2 → session2. other_user is ALSO org1's org_finance (matured);
--   buyer is venue_marketing at venue1; admin_user is platform_admin (bootstrap)
--   + platform_support (platform_role).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store151('org1', (kernel.create_organization('Settle Co','Settle Co','ck87-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch151('org1')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store151('venue1', (catalog.create_venue(tap._fetch151('org1')::uuid,'Settle Hall','wynwood',NULL,'ck87-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch151('venue1')::uuid,'approved','miami_gate','ck87-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store151('event1', (catalog.create_event(tap._fetch151('venue1')::uuid,'Settle Night',
  jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 5 hours')::text),'ck87-e1') ->> 'event_id'));
SELECT tap._store151('session1', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch151('event1')::uuid));
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._store151('org2', (kernel.create_organization('Other Co','Other Co','ck87-o2') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch151('org2')::uuid;
SELECT tap.login(tap.other_user());
SELECT tap._store151('venue2', (catalog.create_venue(tap._fetch151('org2')::uuid,'Other Hall','brickell',NULL,'ck87-v2') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch151('venue2')::uuid,'approved','miami_gate','ck87-a2');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._store151('event2', (catalog.create_event(tap._fetch151('venue2')::uuid,'Other Night',
  jsonb_build_object('starts_at',(now()+interval '12 days')::text,'ends_at',(now()+interval '12 days 4 hours')::text),'ck87-e2') ->> 'event_id'));
SELECT tap._store151('session2', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch151('event2')::uuid));
SELECT tap.logout();
-- roles (direct fixture writes as table owner)
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._fetch151('org1')::uuid, tap.other_user(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days' WHERE org_id = tap._fetch151('org1')::uuid AND identity_id = tap.seller();   -- the owner's money grant matured too
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch151('venue1')::uuid, tap.buyer(), 'venue_marketing', tap.seller());
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.admin_user(), 'platform_support', tap.admin_user());
-- the maturity window (PFA-9 D-3 key, owner-set here as the owner will; MD-14 admits 24-72h)
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'authn.money_role_maturity_hours', coalesce(max(version),0)+1, '24'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='authn.money_role_maturity_hours';

-- ============================================================================
-- SECTION C — THE SETTLEMENT MONEY ENGINE (SSCAS #4; schema §3.13/§3.14)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.open_settlement(%L,%L,%L,'{}','ck87-s-x')$$, tap._fetch151('org1'), tap._fetch151('venue1'), tap._fetch151('event1')),
  '42501', NULL, 'C1: a marketing role cannot open a settlement (venue_finance / org_finance / org_owner only)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store151('s1', (venue.open_settlement(tap._fetch151('org1')::uuid, tap._fetch151('venue1')::uuid, tap._fetch151('event1')::uuid,
  jsonb_build_object('period_start', now()::text, 'period_end', (now()+interval '1 day')::text), 'ck87-s1') ->> 'settlement_id'));
SELECT ok(tap._fetch151('s1') IS NOT NULL, 'C2: org_owner opens a settlement header');
SELECT is((venue.open_settlement(tap._fetch151('org1')::uuid, tap._fetch151('venue1')::uuid, tap._fetch151('event1')::uuid, '{}'::jsonb, 'ck87-s1') ->> 'settlement_id'), tap._fetch151('s1'),
  'C2a: §10.1 idempotency — the same (actor, command_key) returns the ORIGINAL header, no second row');
SELECT throws_ok(format($$SELECT venue.open_settlement(%L,%L,%L,'{}','ck87-s-ev2')$$, tap._fetch151('org1'), tap._fetch151('venue1'), tap._fetch151('event2')),
  'P0002', NULL, 'C2b: AUTHZ-C1C — an event of another venue/org does not bind to the scope (not_found, never insufficient_privilege)');
SELECT tap.logout();
SELECT tap.login(tap.other_user());   -- org2''s OWNER (passes the org-role check for org2)
SELECT throws_ok(format($$SELECT venue.open_settlement(%L,%L,NULL,'{}','ck87-s-steal')$$, tap._fetch151('org2'), tap._fetch151('venue1')),
  'P0002', NULL, 'C2c: AUTHZ-C1C — org2''s owner cannot open a settlement over org1''s venue (the payee would otherwise be caller-chosen)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT kernel.close_settlement(%L,'ck87-c-x')$$, tap._fetch151('s1')),
  '42501', NULL, 'C3: org_owner may NOT close — close is venue_finance / org_finance / platform_admin (RPC §10.2)');
SELECT tap.logout();
SELECT ok((SELECT status='open' AND gross_minor IS NULL AND fees_minor IS NULL AND refunds_minor IS NULL AND net_minor IS NULL
             FROM venue.settlement WHERE settlement_id = tap._fetch151('s1')::uuid),
  'C4: an open header carries NULL money columns (write-once at close)');
SELECT tap.login(tap.other_user());
SELECT tap._store151('c1', kernel.close_settlement(tap._fetch151('s1')::uuid, 'ck87-c1')::text);
SELECT is((tap._fetch151('c1')::jsonb ->> 'status'), 'ok', 'C5: org_finance closes');
SELECT is((tap._fetch151('c1')::jsonb ->> 'net_minor'), '0', 'C6: with no lines (both seams return zero rows) the close is arithmetically complete at net=0');
SELECT is((tap._fetch151('c1')::jsonb -> 'payout_ids'), '[]'::jsonb, 'C7: a zero-net close generates NO payout (kernel.payout amount_minor > 0)');
SELECT is((kernel.close_settlement(tap._fetch151('s1')::uuid, 'ck87-c1b') ->> 'status'), 'noop_replay', 'C8: a re-close is an idempotent replay');
SELECT tap.logout();
SELECT ok((SELECT status='closed' AND gross_minor=0 AND fees_minor=0 AND refunds_minor=0 AND net_minor=0
             FROM venue.settlement WHERE settlement_id = tap._fetch151('s1')::uuid),
  'C9: closed header: four money columns written exactly once, waterfall holds');
SELECT throws_ok(format($$UPDATE venue.settlement SET net_minor = 5 WHERE settlement_id = %L$$, tap._fetch151('s1')),
  '23514', NULL, 'C10: the §3.13.1 waterfall CHECK rejects net <> gross - fees - refunds on a closed header');
SELECT throws_ok(format($$UPDATE venue.settlement SET status='open', gross_minor=NULL, fees_minor=NULL, refunds_minor=NULL, net_minor=NULL WHERE settlement_id=%L; UPDATE venue.settlement SET status='paid' WHERE settlement_id=%L$$, tap._fetch151('s1'), tap._fetch151('s1')),
  '23514', NULL, 'C11: ''paid'' with NULL money columns is unstorable (the CHECK binds paid too)');
-- AO + uniqueness on the line ledger
INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (tap._fetch151('s1')::uuid, 'import', '00000000-0000-0000-0000-00000000aaaa', 100);
SELECT throws_ok(format($$UPDATE venue.settlement_line SET amount_minor = 200 WHERE settlement_id = %L$$, tap._fetch151('s1')),
  NULL, NULL, 'C12: settlement_line rejects UPDATE (append-only)');
SELECT throws_ok(format($$DELETE FROM venue.settlement_line WHERE settlement_id = %L$$, tap._fetch151('s1')),
  NULL, NULL, 'C13: settlement_line rejects DELETE (append-only)');
SELECT throws_ok(format($$INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (%L, 'import', '00000000-0000-0000-0000-00000000aaaa', 100)$$, tap._fetch151('s1')),
  '23505', NULL, 'C14: UNIQUE(settlement_id, cause, cause_ref) — one line per cause per settlement');
SELECT throws_ok(format($$INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (%L, 'bogus', gen_random_uuid(), 1)$$, tap._fetch151('s1')),
  '23514', NULL, 'C15: cause is the closed D3 set');
-- a settlement with seeded money lines → the waterfall → a pending payout
SELECT tap.login(tap.seller());
SELECT tap._store151('s2', (venue.open_settlement(tap._fetch151('org1')::uuid, tap._fetch151('venue1')::uuid, NULL, '{}'::jsonb, 'ck87-s2') ->> 'settlement_id'));
SELECT tap.logout();
INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES
  (tap._fetch151('s2')::uuid, 'primary_sale', gen_random_uuid(), 10000),
  (tap._fetch151('s2')::uuid, 'promoter_commission', gen_random_uuid(), -1000),
  (tap._fetch151('s2')::uuid, 'refund_void', gen_random_uuid(), -500);
SELECT tap.login(tap.other_user());
SELECT tap._store151('c2', kernel.close_settlement(tap._fetch151('s2')::uuid, 'ck87-c2')::text);
SELECT tap.logout();
SELECT ok((SELECT status='closed' AND gross_minor=10000 AND fees_minor=1000 AND refunds_minor=500 AND net_minor=8500
             FROM venue.settlement WHERE settlement_id = tap._fetch151('s2')::uuid),
  'C16: the waterfall from signed lines — gross 10000, fees 1000, refunds 500, net 8500 = gross - fees - refunds');
SELECT ok((SELECT s.gross_minor   = (SELECT coalesce(sum(l.amount_minor),0)  FROM venue.settlement_line l WHERE l.settlement_id=s.settlement_id AND l.amount_minor > 0 AND l.cause NOT IN ('refund_void','chargeback'))
              AND s.fees_minor    = (SELECT coalesce(sum(-l.amount_minor),0) FROM venue.settlement_line l WHERE l.settlement_id=s.settlement_id AND l.amount_minor < 0 AND l.cause NOT IN ('refund_void','chargeback'))
              AND s.refunds_minor = (SELECT coalesce(sum(-l.amount_minor),0) FROM venue.settlement_line l WHERE l.settlement_id=s.settlement_id AND l.cause IN ('refund_void','chargeback'))
              AND s.net_minor     = (SELECT coalesce(sum(l.amount_minor),0)  FROM venue.settlement_line l WHERE l.settlement_id=s.settlement_id)
             FROM venue.settlement s WHERE s.settlement_id = tap._fetch151('s2')::uuid),
  'C16a: T-SCHEMA-SETTLE-04 — the stored header equals the SUM OF ITS OWN LINES by the frozen sign convention (E-73), net = Σ all lines exactly');
SELECT is((tap._fetch151('c2')::jsonb ->> 'net_minor'), '8500', 'C16b: the returned net_minor is a read-back of the column (§10.2 R1-2)');
SELECT is(jsonb_array_length(tap._fetch151('c2')::jsonb -> 'payout_ids'), 1, 'C17: a positive net generates exactly one pending payout');
SELECT tap._store151('p2', ((tap._fetch151('c2')::jsonb -> 'payout_ids') ->> 0));
SELECT ok((SELECT p.amount_minor=8500 AND p.status='pending' AND p.cause='settlement' AND p.cause_ref=tap._fetch151('s2')::uuid
              AND p.payee_kind='organization' AND p.payee_org_id=tap._fetch151('org1')::uuid AND p.idempotency_key='settlement:'||tap._fetch151('s2')
             FROM kernel.payout p WHERE p.payout_id = tap._fetch151('p2')::uuid),
  'C18: the payout: net amount, pending, cause=settlement/cause_ref=settlement, org payee, deterministic idempotency key');
SELECT tap.login(tap.other_user());
SELECT is((kernel.close_settlement(tap._fetch151('s2')::uuid, 'ck87-c2b') ->> 'status'), 'noop_replay', 'C19: replaying the close returns noop_replay …');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.payout WHERE cause='settlement' AND cause_ref=tap._fetch151('s2')::uuid), 1, 'C20: … and mints NO second payout');
-- request_org_payout: authority, SoD-1, maturity, the NULL threshold parks
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT kernel.request_org_payout(%L,%L,'ck87-r-x')$$, tap._fetch151('org1'), tap._fetch151('s2')),
  '42501', NULL, 'C21: request_org_payout is org_owner / org_finance only');
SELECT tap.logout();
UPDATE kernel.organization SET payout_destination_set_by = tap.other_user() WHERE org_id = tap._fetch151('org1')::uuid;
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck87-r-sod')$$, tap._fetch151('org1'), tap._fetch151('s2')),
  '%sod_violation%', 'C22: SoD-1 — the payout-destination SETTER may never request');
SELECT tap.logout();
UPDATE kernel.organization SET payout_destination_set_by = NULL WHERE org_id = tap._fetch151('org1')::uuid;
UPDATE kernel.org_member SET granted_at = now() WHERE org_id = tap._fetch151('org1')::uuid AND identity_id = tap.other_user();
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck87-r-imm')$$, tap._fetch151('org1'), tap._fetch151('s2')),
  '%not yet matured%', 'C23: an immature money-role grant may not request (X-11)');
SELECT tap.logout();
UPDATE kernel.org_member SET granted_at = now() - interval '40 days' WHERE org_id = tap._fetch151('org1')::uuid AND identity_id = tap.other_user();
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck87-r-noaal')$$, tap._fetch151('org1'), tap._fetch151('s2')),
  '%step_up_unavailable%', 'C23a: AUTHZ-M4 — a session with NO aal claim is step_up_unavailable (never a pass, never a fail)');
SELECT tap._aal1();
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck87-r-aal1')$$, tap._fetch151('org1'), tap._fetch151('s2')),
  '%step_up_required%', 'C23b: aal1 is step_up_required');
SELECT tap._aal2();
SELECT throws_ok(format($$SELECT kernel.request_org_payout(%L,%L,'ck87-r-xorg')$$, tap._fetch151('org2'), tap._fetch151('s2')),
  'P0002', NULL, 'C23c: T-RPC-AUTHZ-20 — org2''s owner passing p_org_id=org2 with org1''s settlement gets not_found (the scope binds to the subject under the lock)');
SELECT tap._store151('r1', kernel.request_org_payout(tap._fetch151('org1')::uuid, tap._fetch151('s2')::uuid, 'ck87-r1')::text);
SELECT is((tap._fetch151('r1')::jsonb ->> 'status'), 'pending_approval', 'C24: payout.dual_control_min_minor is NULL-seeded (PFA-9) ⇒ X-12 restrictive ⇒ the request PARKS for dual control');
SELECT is((kernel.request_org_payout(tap._fetch151('org1')::uuid, tap._fetch151('s2')::uuid, 'ck87-r1-again') ->> 'request_id'), (tap._fetch151('r1')::jsonb ->> 'request_id'),
  'C24a: a second request while one is parked returns the SAME pending approval (never a duplicate park)');
SELECT tap.logout();
SELECT ok((SELECT a.action='payout.request' AND a.required_approver_class='org' AND a.subject_kind='settlement' AND a.state='pending'
              AND a.org_id=tap._fetch151('org1')::uuid AND a.amount_minor=8500 AND a.requested_by=tap.other_user()
             FROM kernel.approval_request a WHERE a.request_id = (tap._fetch151('r1')::jsonb ->> 'request_id')::uuid),
  'C25: the parked approval row: payout.request / org class / settlement subject / the payout amount');
SELECT is((SELECT status FROM kernel.payout WHERE payout_id = tap._fetch151('p2')::uuid), 'pending', 'C26: a parked request leaves the payout pending');
SELECT is((SELECT a.config_versions ? 'payout.dual_control_min_minor' FROM kernel.approval_request a WHERE a.request_id = (tap._fetch151('r1')::jsonb ->> 'request_id')::uuid), true,
  'C26a: the parked row PINS the threshold key version in config_versions (never a parameter)');
SELECT is(tap._audit151(tap._fetch151('p2')::uuid, 'payout.request', 'pending_approval'), 1, 'C26b: the parked arm writes its payout.request audit row');
-- the dual-control loop CLOSES: a second money role approves (085 verb) and the requester's re-request advances (E-74)
SELECT tap.login(tap.seller());
SELECT tap._aal2();
SELECT is((kernel.approve_refund_request((tap._fetch151('r1')::jsonb ->> 'request_id')::uuid, 'approve', 'looks_right', 'ck87-ap1') ->> 'status'), 'approved',
  'C26c: the org_owner (a second, matured money role; not the requester, not the setter) approves the parked payout request');
SELECT tap.logout();
SELECT is((SELECT status FROM kernel.payout WHERE payout_id = tap._fetch151('p2')::uuid), 'pending', 'C26d: 085''s approve arm records the approval and moves no money (the payout is still pending)');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT tap._store151('r1b', kernel.request_org_payout(tap._fetch151('org1')::uuid, tap._fetch151('s2')::uuid, 'ck87-r1b')::text);
SELECT is((tap._fetch151('r1b')::jsonb ->> 'status'), 'submitted', 'C26e: E-74 — the contracted writer of pending→submitted advances an APPROVED request (the loop has an exit)');
SELECT is((tap._fetch151('r1b')::jsonb ->> 'request_id'), (tap._fetch151('r1')::jsonb ->> 'request_id'), 'C26f: … citing the approval it consumed');
SELECT is((kernel.request_org_payout(tap._fetch151('org1')::uuid, tap._fetch151('s2')::uuid, 'ck87-r2') ->> 'status'), 'noop_replay',
  'C27: a request on an already-submitted payout is noop_replay');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'payout.dual_control_min_minor', coalesce(max(version),0)+1, '1000000'::jsonb, 'restricted'
  FROM catalog.platform_config WHERE key='payout.dual_control_min_minor';
-- the fifth seam: closed → paid rides mark_payout_transfer_state
SELECT is((kernel.mark_payout_transfer_state(tap._fetch151('p2')::uuid, 'paid', 'tr_87_1', NULL, 'ck87-m1') ->> 'status'), 'ok',
  'C28: the Stripe state-sync marks the payout paid');
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fetch151('s2')::uuid), 'paid',
  'C29: … and venue.on_payout_settled advanced the settlement closed → paid (its SOLE writer)');
-- T-SCHEMA-SETTLE-01: two payouts, one still submitted ⇒ NOT paid
SELECT tap.login(tap.seller());
SELECT tap._store151('s3', (venue.open_settlement(tap._fetch151('org1')::uuid, tap._fetch151('venue1')::uuid, NULL, '{}'::jsonb, 'ck87-s3') ->> 'settlement_id'));
SELECT tap.logout();
INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (tap._fetch151('s3')::uuid, 'primary_sale', gen_random_uuid(), 5000);
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT tap._store151('p3', ((kernel.close_settlement(tap._fetch151('s3')::uuid, 'ck87-c3')::jsonb -> 'payout_ids') ->> 0));
SELECT is((kernel.request_org_payout(tap._fetch151('org1')::uuid, tap._fetch151('s3')::uuid, 'ck87-r3') ->> 'status'), 'submitted',
  'C29a: below an OWNER-SET dual-control threshold the payout advances pending → submitted directly (the edge executes Stripe)');
SELECT tap.logout();
WITH sib AS (INSERT INTO kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, status, idempotency_key)
  VALUES ('organization', tap._fetch151('org1')::uuid, 'settlement', tap._fetch151('s3')::uuid, 100, 'submitted', 'sib:'||tap._fetch151('s3')) RETURNING payout_id)
SELECT tap._store151('p3b', (SELECT payout_id::text FROM sib));
SELECT kernel.mark_payout_transfer_state(tap._fetch151('p3')::uuid, 'paid', 'tr_87_3', NULL, 'ck87-m3');
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fetch151('s3')::uuid), 'closed',
  'C30: T-SCHEMA-SETTLE-01 — with a sibling settlement payout still submitted the header stays closed (a hook that fires on the FIRST payout is the bug)');
SELECT kernel.mark_payout_transfer_state(tap._fetch151('p3b')::uuid, 'paid', 'tr_87_3b', NULL, 'ck87-m3b');
SELECT is((SELECT status FROM venue.settlement WHERE settlement_id = tap._fetch151('s3')::uuid), 'paid',
  'C31: … and reaches paid only when EVERY settlement-caused payout is paid');
-- DESTINATION PROBATION (§10.3 third arm; T-RPC-MONEY-31/32): the org_owner changes the
-- destination (085 verb, aal2, matured); the FIRST payout after it is held, not advanced.
SELECT tap.login(tap.seller());
SELECT tap._aal2();
SELECT is((kernel.set_org_payout_destination(tap._fetch151('org1')::uuid, 'acct_PROB87', 'new_bank', 'ck87-dest') ->> 'status'), 'ok',
  'C31a: the org_owner sets a new payout destination (writes the org.payout_destination.change audit row)');
SELECT tap._store151('s5', (venue.open_settlement(tap._fetch151('org1')::uuid, tap._fetch151('venue1')::uuid, NULL, '{}'::jsonb, 'ck87-s5') ->> 'settlement_id'));
SELECT tap.logout();
INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (tap._fetch151('s5')::uuid, 'primary_sale', gen_random_uuid(), 7000);
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT tap._store151('p5', ((kernel.close_settlement(tap._fetch151('s5')::uuid, 'ck87-c5')::jsonb -> 'payout_ids') ->> 0));
SELECT tap._store151('r5', kernel.request_org_payout(tap._fetch151('org1')::uuid, tap._fetch151('s5')::uuid, 'ck87-r5')::text);
SELECT is((tap._fetch151('r5')::jsonb ->> 'status'), 'probation_held', 'C31b: T-RPC-MONEY-31 — the first payout after a destination change returns probation_held, distinctly');
SELECT tap.logout();
SELECT ok((SELECT p.status = 'pending' AND p.hold_state = 'probation_hold' AND p.hold_reason_code = 'destination_probation' AND p.held_at IS NOT NULL AND p.held_by IS NULL
             FROM kernel.payout p WHERE p.payout_id = tap._fetch151('p5')::uuid),
  'C31c: status stays pending (asserted as an equality), exactly the three hold columns set, held_by NULL (a probation hold, not a risk hold)');
SELECT is(tap._audit151(tap._fetch151('p5')::uuid, 'payout.probation_hold', 'destination_probation'), 1, 'C31d: payout.probation_hold audited');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT is((kernel.request_org_payout(tap._fetch151('org1')::uuid, tap._fetch151('s5')::uuid, 'ck87-r5b') ->> 'status'), 'probation_held',
  'C31e: a re-request while held is still probation_held — nothing advances');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT is((kernel.release_payout(tap._fetch151('p5')::uuid, 'ck87-rel5') ->> 'status'), 'ok', 'C31f: only platform_risk/platform_admin release (kernel.release_payout, the sole release path)');
SELECT tap.logout();
SELECT ok((SELECT p.status = 'pending' AND p.hold_state = 'none' FROM kernel.payout p WHERE p.payout_id = tap._fetch151('p5')::uuid),
  'C31g: T-RPC-MONEY-32 — release restores hold_state=none and status is STILL pending (it was never overwritten)');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT is((kernel.request_org_payout(tap._fetch151('org1')::uuid, tap._fetch151('s5')::uuid, 'ck87-r5c') ->> 'status'), 'submitted',
  'C31h: … and a second request then advances it normally');
SELECT tap.logout();
-- on_payout_settled refusals / no-ops (called directly under the owning context)
SELECT tap.login(tap.seller());
SELECT tap._store151('s4', (venue.open_settlement(tap._fetch151('org1')::uuid, tap._fetch151('venue1')::uuid, NULL, '{}'::jsonb, 'ck87-s4') ->> 'settlement_id'));
SELECT tap.logout();
WITH po AS (INSERT INTO kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, status, idempotency_key)
  VALUES ('organization', tap._fetch151('org1')::uuid, 'settlement', tap._fetch151('s4')::uuid, 100, 'submitted', 'open:'||tap._fetch151('s4')) RETURNING payout_id)
SELECT tap._store151('p4', (SELECT payout_id::text FROM po));
SELECT throws_like(format($$SELECT venue.on_payout_settled(%L)$$, tap._fetch151('p4')),
  '%is open, not closed%', 'C32: on_payout_settled REFUSES to mark an OPEN settlement paid');
WITH po AS (INSERT INTO kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, status, idempotency_key)
  VALUES ('organization', tap._fetch151('org1')::uuid, 'refund_void', gen_random_uuid(), 100, 'paid', 'rv:'||gen_random_uuid()::text) RETURNING payout_id)
SELECT tap._store151('p5', (SELECT payout_id::text FROM po));
SELECT lives_ok(format($$SELECT venue.on_payout_settled(%L)$$, tap._fetch151('p5')), 'C33: a non-settlement payout is a silent no-op for the hook');
SELECT lives_ok($$SELECT venue.on_payout_settled(gen_random_uuid())$$, 'C34: an unknown payout is a silent no-op');
SELECT tap.login(tap.other_user());
SELECT tap._aal2();
SELECT throws_like(format($$SELECT kernel.request_org_payout(%L,%L,'ck87-r4')$$, tap._fetch151('org1'), tap._fetch151('s4')),
  '%settlement not closed%', 'C35: request_org_payout refuses an open settlement');
-- RLS: org finance reads, marketing does not
SELECT is((SELECT count(*)::int FROM venue.settlement WHERE org_id = tap._fetch151('org1')::uuid), 5, 'C36: org_finance reads its org''s five settlement headers (RLS §9.13)');
SELECT is((SELECT count(*)::int FROM venue.settlement_line l JOIN venue.settlement s ON s.settlement_id=l.settlement_id WHERE s.org_id = tap._fetch151('org1')::uuid), 6,
  'C37: … and their six lines (RLS §9.14)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM venue.settlement), 0, 'C38: venue_marketing reads ZERO settlements');
SELECT is((SELECT count(*)::int FROM venue.settlement_line), 0, 'C39: … and ZERO lines');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue.settlement WHERE status='paid'), 2, 'C40: PFA-28 (H) — the settlement subsystem is unaffected by the CRM park: two settlements reached paid');
-- the venue-role arm binds to the venue's CURRENT operator (E-76): re-operate venue1 to org2
UPDATE catalog.venue SET org_id = tap._fetch151('org2')::uuid WHERE venue_id = tap._fetch151('venue1')::uuid;
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by) VALUES (tap._fetch151('venue1')::uuid, tap.fan151(), 'venue_manager', tap.other_user());
SELECT tap.login(tap.fan151());
SELECT throws_ok(format($$SELECT venue.request_export('event',%L,'operations_v1','{}','ck87-reop-1')$$, tap._fetch151('event1')),
  '42501', NULL, 'C41: E-76 — the NEW operator''s venue_manager cannot export the PRIOR operator''s event (venue as a place ≠ venue as an operator)');
SELECT throws_ok(format($$SELECT venue.list_attendees(%L,'{}',NULL,NULL)$$, tap._fetch151('session1')),
  '42501', NULL, 'C42: … nor read its roster');
SELECT throws_ok(format($$SELECT venue.list_export_jobs('event',%L,NULL)$$, tap._fetch151('event1')),
  '42501', NULL, 'C43: … nor list its export history');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','ck87-reop-2')$$, tap._fetch151('session1')),
  '42501', NULL, 'C44: … and the prior operator''s venue_marketing is bound out too (the venue role no longer sits under org1)');
SELECT tap.logout();
DELETE FROM venue.staff_role WHERE venue_id = tap._fetch151('venue1')::uuid AND identity_id = tap.fan151();
UPDATE catalog.venue SET org_id = tap._fetch151('org1')::uuid WHERE venue_id = tap._fetch151('venue1')::uuid;

-- ============================================================================
-- SECTION D — THE EXPORT LIFECYCLE (request → build[PARKED] → finalize →
--   download → revoke → sweep → purge → reconcile)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT venue.request_export('all',%L,'audience_v1','{}','ck87-x-all')$$, tap._fetch151('session1')),
  '%not a member of the closed set (EX-1)%', 'D1: scope_kind=''all'' is rejected (§12 20)');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','ck87-x-fin')$$, tap._fetch151('session1')),
  '42501', NULL, 'D2: org_finance is DENIED the export (finance sees money and no contact — §12 19)');
SELECT tap.logout();
SELECT tap.login(tap.fan151());
SELECT throws_ok(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','ck87-x-fan')$$, tap._fetch151('session1')),
  '42501', NULL, 'D3: a plain fan is denied');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT throws_ok(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','ck87-x-plat')$$, tap._fetch151('session1')),
  '42501', NULL, 'D4: T-RLS-CRM-01 — NO platform role may request a venue CRM export (MD-8)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT tap._store151('j1r', venue.request_export('session', tap._fetch151('session1')::uuid, 'audience_v1', '{}'::jsonb, 'ck87-j1')::text);
SELECT is((tap._fetch151('j1r')::jsonb ->> 'state'), 'queued', 'D5: venue_marketing requests an audience_v1 session export → queued');
SELECT tap._store151('j1', (tap._fetch151('j1r')::jsonb ->> 'job_id'));
SELECT throws_ok(format($$SELECT venue.request_export('session',%L,'operations_v1','{}','ck87-j1-ops')$$, tap._fetch151('session1')),
  '42501', NULL, 'D6: venue_marketing is DENIED operations_v1 (the narrowest allow-list)');
SELECT is(((venue.request_export('session', tap._fetch151('session1')::uuid, 'audience_v1', '{}'::jsonb, 'ck87-j1')::jsonb) ->> 'job_id'), tap._fetch151('j1'),
  'D7: C16 — the same (actor, command_key) replays the ORIGINAL job');
SELECT throws_like(format($$SELECT venue.request_export('session',%L,'audience_v1','{"gender_identity":["x"]}','ck87-f1')$$, tap._fetch151('session1')),
  '%not a member of the closed grammar%', 'D8: a demographic filter NAME raises (X-2; §12 21)');
SELECT throws_like(format($$SELECT venue.request_export('session',%L,'audience_v1','{"source":{"or":["app"]}}','ck87-f2')$$, tap._fetch151('session1')),
  '%non-empty membership array%', 'D9: a nested/OR filter raises (conjunctive memberships only)');
SELECT throws_like(format($$SELECT venue.request_export('session',%L,'audience_v1','{"order_status":["bogus"]}','ck87-f3')$$, tap._fetch151('session1')),
  '%outside the closed set%', 'D10: a value outside a filter''s enum raises');
SELECT throws_like(format($$SELECT venue.request_export('session',%L,'audience_v1','{"promoter":["x"]}','ck87-f4')$$, tap._fetch151('session1')),
  '%gated on package 090%', 'D11: the promoter filter is gated on 090');
SELECT throws_like(format($$SELECT venue.request_export('session',%L,'audience_v1','{"refund_state":["alice@example.com"]}','ck87-f4b')$$, tap._fetch151('session1')),
  '%bounded identifiers%', 'D11a: §8.3 — free text (an address) can never reach the job row or the immutable audit through a filter value');
SELECT throws_like(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','bad key with spaces @')$$, tap._fetch151('session1')),
  '%command_key must be%', 'D11b: … nor through the command key');
SELECT throws_like(format($$SELECT venue.request_export('venue',%L,'audience_v1','{}','ck87-f5')$$, tap._fetch151('venue1')),
  '%date_window%', 'D12: a venue-grain export must be anchored on a bounded window (EX-1)');
SELECT throws_like(format($$SELECT venue.request_export('venue',%L,'audience_v1',%L,'ck87-f6')$$, tap._fetch151('venue1'),
    jsonb_build_object('date_window', jsonb_build_object('from', now()::text, 'to', (now()+interval '200 days')::text))::text),
  '%exceeds 180 days%', 'D13: the 180-day venue-grain window cap (§7.3)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store151('j2', ((venue.request_export('event', tap._fetch151('event1')::uuid, 'operations_v1', '{"source":["web","app"]}'::jsonb, 'ck87-j2')::jsonb) ->> 'job_id'));
SELECT tap._store151('j3', ((venue.request_export('org', tap._fetch151('org1')::uuid, 'audience_v1',
    jsonb_build_object('date_window', jsonb_build_object('from', now()::text, 'to', (now()+interval '200 days')::text)), 'ck87-j3')::jsonb) ->> 'job_id'));
SELECT ok(tap._fetch151('j2') IS NOT NULL AND tap._fetch151('j3') IS NOT NULL, 'D14: org_owner requests operations_v1 at event grain and audience_v1 at org grain (365-day cap)');
SELECT tap.logout();
SELECT ok((SELECT (j).org_id = tap._fetch151('org1')::uuid AND (j).as_of IS NOT NULL AND (j).gate_as_of IS NULL AND (j).template_version = 1
              AND (j).filters = '{"source": ["app", "web"]}'::jsonb AND (j).purge_after > now() + interval '12 months' AND (j).artifact_state = 'absent'
             FROM tap._job151(tap._fetch151('j2')::uuid) j),
  'D15: the job row: org FROZEN at request (XO-1a), as_of stamped, gate_as_of NOT yet (claim-time), filters normalized+sorted, 13-month row retention');
SELECT is(tap._audit151(tap._fetch151('j1')::uuid, 'crm_export.request'), 1, 'D16: crm_export.request written in the same txn (EX-5)');
SELECT is((SELECT a.after->>'constraint_set_version' FROM kernel.admin_audit a WHERE a.subject_id = tap._fetch151('j1')::uuid AND a.action='crm_export.request'),
  'demographics-constraints/X1-X9@v1', 'D17: X-9 — the request audit row carries the constraint-set identifier in force (the 078 seed)');
SELECT is((SELECT count(*)::int FROM kernel.org_customer_key), 0,
  'D18: PFA-28 — NO kernel.org_customer_key row is minted (the OR-19 lazy mint is deferred with the crypto mechanism; no key material exists to leak)');
-- history panel
SELECT tap.login(tap.buyer());
SELECT tap._store151('lj', venue.list_export_jobs('venue', tap._fetch151('venue1')::uuid, NULL)::text);
SELECT is(jsonb_array_length(tap._fetch151('lj')::jsonb -> 'jobs'), 2, 'D19: X10 — venue_marketing lists the venue''s history (session + event jobs; the org-grain job is not under the venue)');
SELECT ok((SELECT bool_and(NOT (e ? 'object_path') AND (e ->> 'downloadable') = 'false' AND (e ? 'template_id'))
             FROM jsonb_array_elements(tap._fetch151('lj')::jsonb -> 'jobs') e),
  'D20: metadata only — never an object path; downloadable=false while nothing is ready; template_id present (the operations job is VISIBLE to marketing: transparency, not download)');
SELECT throws_ok(format($$SELECT venue.list_export_jobs('org',%L,NULL)$$, tap._fetch151('org1')),
  '42501', NULL, 'D21: venue_marketing holds no org-grain history read');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT venue.list_export_jobs('venue',%L,NULL)$$, tap._fetch151('venue1')),
  '42501', NULL, 'D22: org_finance holds no X10');
SELECT tap.logout();
-- the BUILD (service path): claim → PFA-28 park → failed/build_error, zero rows
SELECT is((SELECT count(*)::int FROM venue.build_export_rows(tap._fetch151('j1')::uuid, NULL, 100)), 0,
  'D23: PFA-28 (A) — build_export_rows returns ZERO customer rows (fail closed)');
SELECT ok((SELECT (j).state='failed' AND (j).failure_code='build_error' AND (j).gate_as_of IS NOT NULL AND (j).lease_until IS NULL
              AND (j).row_count = 0 AND (j).contact_cells_emitted = 0 AND (j).name_cells_emitted = 0
             FROM tap._job151(tap._fetch151('j1')::uuid) j),
  'D24: PFA-28 (F) — the job is recorded in the frozen failure state (failed / build_error) with gate_as_of stamped at claim and no fabricated counters');
SELECT is(tap._audit151(tap._fetch151('j1')::uuid, 'crm_export.fail', 'customer_ref_crypto_unavailable'), 1,
  'D25: the failure is audited: crm_export.fail / customer_ref_crypto_unavailable');
SELECT is(tap._audit151(tap._fetch151('j1')::uuid, 'crm_export.claim'), 1, 'D25a: E-77 — the claim (queued→running) left its own audit row (EX-5), carrying gate_as_of');
SELECT throws_like(format($$SELECT venue.finalize_export(%L, 0, 10, repeat('a',64), %L)$$, tap._fetch151('j1'), tap._fetch151('org1')||'/'||tap._fetch151('j1')||'.csv'),
  '%only a running build finalizes%', 'D26: PFA-28 (F) — a parked build can NEVER finalize; no artifact can exist');
SELECT tap.login(tap.buyer());
SELECT throws_like(format($$SELECT venue.authorize_export_download(%L)$$, tap._fetch151('j1')),
  '%only a ready export downloads%', 'D27: … and nothing downloads');
-- a requester who lost the role between request and build ⇒ scope_unreachable
SELECT tap._store151('j4', ((venue.request_export('session', tap._fetch151('session1')::uuid, 'audience_v1', '{}'::jsonb, 'ck87-j4')::jsonb) ->> 'job_id'));
SELECT tap.logout();
DELETE FROM venue.staff_role WHERE venue_id = tap._fetch151('venue1')::uuid AND identity_id = tap.buyer();
SELECT is((SELECT count(*)::int FROM venue.build_export_rows(tap._fetch151('j4')::uuid, NULL, 100)), 0, 'D28: authority is re-derived from the JOB ROW at build …');
SELECT ok((SELECT (j).state='failed' AND (j).failure_code='scope_unreachable' FROM tap._job151(tap._fetch151('j4')::uuid) j)
       AND tap._audit151(tap._fetch151('j4')::uuid, 'crm_export.fail', 'scope_unreachable') = 1,
  'D29: … a requester who lost the role fails the job as scope_unreachable (never the caller''s authority)');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by) VALUES (tap._fetch151('venue1')::uuid, tap.buyer(), 'venue_marketing', tap.seller());
SELECT throws_like(format($$SELECT * FROM venue.build_export_rows(%L, NULL, 100)$$, tap._fetch151('j4')),
  '%not buildable%', 'D30: a failed job cannot be re-claimed');
-- READY jobs, staged directly (the builder is parked): j2 = seller's operations job; j5 = buyer's audience job
SELECT tap.login(tap.buyer());
SELECT tap._store151('j5', ((venue.request_export('session', tap._fetch151('session1')::uuid, 'audience_v1', '{}'::jsonb, 'ck87-j5')::jsonb) ->> 'job_id'));
SELECT tap.logout();
UPDATE venue.export_job SET state='ready', artifact_state='present', ready_at=now(), expires_at=now()+interval '1 hour', row_count=0,
       object_path = org_id::text||'/'||job_id::text||'.csv', lease_until=NULL
 WHERE job_id IN (tap._fetch151('j2')::uuid, tap._fetch151('j5')::uuid);
SELECT tap.login(tap.buyer());
SELECT tap._store151('dl', venue.authorize_export_download(tap._fetch151('j5')::uuid)::text);
SELECT ok((tap._fetch151('dl')::jsonb ->> 'object_path') = tap._fetch151('org1')||'/'||tap._fetch151('j5')||'.csv' AND (tap._fetch151('dl')::jsonb ->> 'ttl_seconds') = '300',
  'D31: the requester downloads their audience job: {org_id}/{job_id}.csv + a 300 s TTL for the edge to sign');
SELECT is(tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.download'), 1, 'D32: crm_export.download written BEFORE the path is returned (§12 24)');
SELECT ok(kernel.has_venue_role(tap._fetch151('venue1')::uuid, ARRAY['venue_marketing']), 'D33: fixture sanity — buyer PASSES the old role-set check over the scope …');
SELECT throws_ok(format($$SELECT venue.authorize_export_download(%L)$$, tap._fetch151('j2')),
  '42501', NULL, 'D34: T-RLS-CRM-06 / §12 24a — … and is REFUSED the colleague''s operations_v1 download (the re-check reads the TEMPLATE)');
SELECT lives_ok(format($$SELECT venue.authorize_export_download(%L)$$, tap._fetch151('j5')), 'D35: download #2 within the per-job budget');
SELECT lives_ok(format($$SELECT venue.authorize_export_download(%L)$$, tap._fetch151('j5')), 'D36: download #3 within the per-job budget');
SELECT throws_like(format($$SELECT venue.authorize_export_download(%L)$$, tap._fetch151('j5')),
  '%rate_limited%', 'D37: the 4th download of one job is refused (3 per actor per job, fail-closed limiter)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT lives_ok(format($$SELECT venue.authorize_export_download(%L)$$, tap._fetch151('j2')), 'D38: org_owner downloads the operations job');
SELECT tap.logout();
-- revoke
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($$SELECT venue.revoke_export(%L,'oops')$$, tap._fetch151('j5')), '42501', NULL, 'D39: org_finance cannot revoke');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT tap._store151('rv', venue.revoke_export(tap._fetch151('j5')::uuid, 'requester_regret')::text);
SELECT ok((tap._fetch151('rv')::jsonb ->> 'state')='revoked' AND (tap._fetch151('rv')::jsonb ->> 'artifact_state')='delete_pending',
  'D40: §12 31a — revoke: ready → revoked AND present → delete_pending in ONE transaction; the object is NOT deleted here');
SELECT throws_like(format($$SELECT venue.authorize_export_download(%L)$$, tap._fetch151('j5')),
  '%only a ready export downloads%', 'D41: no further download is authorized from that instant');
SELECT is((venue.revoke_export(tap._fetch151('j5')::uuid, 'again') ->> 'status'), 'noop_replay', 'D42: revoke is idempotent');
SELECT throws_ok(format($$SELECT venue.revoke_export(%L,'x')$$, tap._fetch151('j3')),
  '42501', NULL, 'D43a: venue_marketing may not revoke the org-grain job it could not have requested (authz precedes the state check)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT throws_like(format($$SELECT venue.revoke_export(%L,'x')$$, tap._fetch151('j3')),
  '%only a ready export is revoked%', 'D43: only ready → revoked (the §3.18 machine) — the requester of a queued job cannot revoke it');
SELECT tap.logout();
SELECT is(tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.revoke', 'requester_regret'), 1, 'D44: crm_export.revoke audited with the reason');
-- purge claim / confirm (the only delete agent's DB half)
SELECT is((SELECT count(*)::int FROM venue.claim_artifacts_for_purge(10)), 1, 'D45: claim_artifacts_for_purge returns the ONE delete_pending job');
SELECT ok((SELECT (j).purge_lease_until > now() AND (j).purge_attempts = 1 AND (j).lease_until IS NULL FROM tap._job151(tap._fetch151('j5')::uuid) j),
  'D46: the purge lease (purge_lease_until, DISTINCT from the build lease) is taken and the attempt counted');
SELECT is((SELECT count(*)::int FROM venue.claim_artifacts_for_purge(10)), 0, 'D47: T-SCHEMA-PURGE-01 — a second claim under a live lease gets NOTHING (disjoint sets)');
SELECT ok((SELECT array_to_string(array(SELECT t.n FROM unnest(p.proargnames, p.proargmodes) AS t(n, m) WHERE t.m = 't'), ',') = 'job_id,object_path'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue' AND p.proname='claim_artifacts_for_purge'),
  'D48: the claim returns (job_id, object_path) and NOTHING else — no scope, no counts, no actor');
SELECT tap._store151('cf', venue.confirm_artifact_purged(tap._fetch151('j5')::uuid, 'not_found')::text);
SELECT ok((tap._fetch151('cf')::jsonb ->> 'artifact_state')='deleted' AND (tap._fetch151('cf')::jsonb ->> 'state')='revoked',
  'D49: T-SCHEMA-PURGE-02 / §12 31b — a 404 (not_found) is SUCCESS: artifact_state=deleted; the revoked job waits for its row retention');
SELECT is((venue.confirm_artifact_purged(tap._fetch151('j5')::uuid, 'deleted') ->> 'status'), 'noop_replay', 'D50: a second confirm is a no-op');
SELECT is(tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.purge', 'not_found'), 1, 'D51: crm_export.purge audited with the outcome');
SELECT throws_like($$SELECT venue.confirm_artifact_purged(gen_random_uuid(), 'exploded')$$, '%deleted or not_found%', 'D52: outcome is the closed pair');
-- sweep: expiry marks, never deletes
UPDATE venue.export_job SET expires_at = now() - interval '1 hour' WHERE job_id = tap._fetch151('j2')::uuid;
SELECT tap._store151('sw', venue.sweep_expired_exports()::text);
SELECT is((tap._fetch151('sw')::jsonb ->> 'expired'), '1', 'D53: the hourly sweep expires the one job past expires_at');
SELECT ok((SELECT (j).state='expired' AND (j).artifact_state='delete_pending' FROM tap._job151(tap._fetch151('j2')::uuid) j)
       AND tap._audit151(tap._fetch151('j2')::uuid, 'crm_export.expire') = 1,
  'D54: T-SCHEMA-PURGE-05 — ready → expired and present → delete_pending; the sweep moved NO bytes (it is the purge queue''s producer)');
-- the stalled-purge alarm
UPDATE venue.export_job SET purge_attempts = 3, purge_lease_until = NULL WHERE job_id = tap._fetch151('j2')::uuid;
SELECT is((SELECT count(*)::int FROM venue.claim_artifacts_for_purge(10)), 1, 'D55: the expired job is claimed for purge');
SELECT is(tap._audit151(tap._fetch151('j2')::uuid, 'crm_export.signal', 'purge_stalled'), 1,
  'D56: T-SCHEMA-PURGE-03 — past three attempts a platform_risk signal is raised (a delete that never succeeds is an alarm)');
-- the daily orphan pass, BOTH directions
SELECT tap.login(tap.buyer());
SELECT tap._store151('j6', ((venue.request_export('session', tap._fetch151('session1')::uuid, 'audience_v1', '{}'::jsonb, 'ck87-j6')::jsonb) ->> 'job_id'));
SELECT tap.logout();
UPDATE venue.export_job SET state='ready', artifact_state='present', ready_at=now(), expires_at=now()+interval '1 hour', row_count=0,
       object_path = org_id::text||'/'||job_id::text||'.csv' WHERE job_id = tap._fetch151('j6')::uuid;
CREATE TABLE tap.orph151 AS SELECT * FROM venue.reconcile_export_orphans(tap._fetch151('org1')::uuid,
  ARRAY[tap._fetch151('org1')||'/junk.csv', tap._fetch151('org1')||'/'||tap._fetch151('j5')||'.csv', tap._fetch151('org1')||'/'||tap._fetch151('j2')||'.csv']);
SELECT is((SELECT reason_code FROM tap.orph151 WHERE object_path = tap._fetch151('org1')||'/junk.csv'), 'orphan_no_job',
  'D57: T-SCHEMA-PURGE-04 (→) an object with no job row is returned for deletion as orphan_no_job');
SELECT is((SELECT reason_code FROM tap.orph151 WHERE object_path = tap._fetch151('org1')||'/'||tap._fetch151('j5')||'.csv'), 'orphan_state_mismatch',
  'D58: (→) an object whose job says artifact_state=deleted is returned as orphan_state_mismatch');
SELECT is((SELECT count(*)::int FROM tap.orph151 WHERE object_path = tap._fetch151('org1')||'/'||tap._fetch151('j2')||'.csv'), 0,
  'D59: (→) an object whose job is honestly delete_pending is LEFT to the purge queue');
SELECT ok((SELECT (j).artifact_state='deleted' AND (j).state='expired' FROM tap._job151(tap._fetch151('j6')::uuid) j)
       AND tap._audit151(tap._fetch151('j6')::uuid, 'crm_export.signal', 'ready_without_object') = 1,
  'D60: (←) a READY job whose object is absent is set deleted, moved to expired, and ALARMED');
SELECT is(tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.purge', 'orphan_state_mismatch') + tap._audit151(tap._fetch151('j6')::uuid, 'crm_export.purge', 'object_absent'), 2,
  'D61: both orphan directions are audited as crm_export.purge');
SELECT throws_like(format($$SELECT * FROM venue.reconcile_export_orphans(%L, ARRAY['other-org/x.csv'])$$, tap._fetch151('org1')),
  '%outside the % prefix%', 'D62: a path outside the {org_id}/ prefix is rejected');
-- finalize (staged running jobs): count_mismatch, the generate row, the canary, lease expiry, the path rule
SELECT tap.login(tap.buyer());
SELECT tap._store151('j7', ((venue.request_export('session', tap._fetch151('session1')::uuid, 'audience_v1', '{}'::jsonb, 'ck87-j7')::jsonb) ->> 'job_id'));
-- the buyer has now requested j1, j4, j5, j6, j7 — the frozen §7.1 per-actor cap (5 / 24 h) bites on the sixth
SELECT throws_like(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','ck87-j8-over')$$, tap._fetch151('session1')),
  '%rate_limited: crm_export_request per actor%', 'D62a: §7.1 — the sixth request in 24 h by one actor is refused (fail-closed limiter)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store151('j8', ((venue.request_export('session', tap._fetch151('session1')::uuid, 'audience_v1', '{}'::jsonb, 'ck87-j8')::jsonb) ->> 'job_id'));
SELECT tap._store151('j9', ((venue.request_export('session', tap._fetch151('session1')::uuid, 'audience_v1', '{}'::jsonb, 'ck87-j9')::jsonb) ->> 'job_id'));
SELECT tap.logout();
UPDATE venue.export_job SET state='running', lease_until=now()+interval '10 minutes', gate_as_of=now(), row_count=0 WHERE job_id = tap._fetch151('j7')::uuid;
UPDATE venue.export_job SET state='running', lease_until=now()+interval '10 minutes', gate_as_of=now(), row_count=3,
       contact_cells_suppressed=3, name_cells_suppressed=3 WHERE job_id = tap._fetch151('j8')::uuid;
UPDATE venue.export_job SET state='running', lease_until=now()-interval '1 minute', gate_as_of=now(), row_count=0 WHERE job_id = tap._fetch151('j9')::uuid;
SELECT throws_like(format($$SELECT venue.finalize_export(%L, 5, 10, repeat('a',64), %L)$$, tap._fetch151('j7'), tap._fetch151('org1')||'/'||tap._fetch151('j7')||'.csv'),
  '%count_mismatch%', 'D63: T-RPC-CRM-08 — a worker row_count disagreeing with the DB-accumulated count raises count_mismatch …');
SELECT ok((SELECT (j).state='running' FROM tap._job151(tap._fetch151('j7')::uuid) j), 'D64: … and leaves the job reclaimable (still running)');
SELECT throws_like(format($$SELECT venue.finalize_export(%L, 0, 10, repeat('a',64), 'somewhere/else.csv')$$, tap._fetch151('j7')),
  '%object_path must be%', 'D65: the object path is deterministic ({org_id}/{job_id}.csv, §6.6) and asserted');
SELECT tap._store151('fz', venue.finalize_export(tap._fetch151('j7')::uuid, 0, 10, repeat('a',64), tap._fetch151('org1')||'/'||tap._fetch151('j7')||'.csv')::text);
SELECT is((tap._fetch151('fz')::jsonb ->> 'state'), 'ready', 'D66: with agreeing counts the job becomes ready');
SELECT ok((SELECT (j).artifact_state='present' AND (j).expires_at BETWEEN now()+interval '23 hours' AND now()+interval '25 hours' AND (j).artifact_sha256=repeat('a',64) AND (j).lease_until IS NULL
             FROM tap._job151(tap._fetch151('j7')::uuid) j),
  'D67: artifact present, 24-hour artifact retention stamped, sha recorded, lease released');
SELECT ok((SELECT a.after->>'constraint_set_version' = 'demographics-constraints/X1-X9@v1' AND (a.after ? 'gate_as_of') AND (a.after ? 'as_of')
              AND (a.after->>'contact_cells_emitted') = '0' AND (a.after ? 'name_cells_suppressed')
             FROM kernel.admin_audit a WHERE a.subject_id = tap._fetch151('j7')::uuid AND a.action='crm_export.generate'),
  'D68: §12 24 / §8.3 — crm_export.generate carries constraint_set_version, as_of AND gate_as_of, and the four DB-accumulated counters');
SELECT is((venue.finalize_export(tap._fetch151('j7')::uuid, 0, 10, repeat('a',64), tap._fetch151('org1')||'/'||tap._fetch151('j7')||'.csv') ->> 'status'), 'noop_replay',
  'D69: finalize is idempotent');
SELECT lives_ok(format($$SELECT venue.finalize_export(%L, 3, 30, repeat('b',64), %L)$$, tap._fetch151('j8'), tap._fetch151('org1')||'/'||tap._fetch151('j8')||'.csv'),
  'D70: a balanced (0 emitted, 3 suppressed = 3 rows) finalize succeeds …');
SELECT is(tap._audit151(tap._fetch151('j8')::uuid, 'crm_export.signal', 'blank_column_canary'), 1,
  'D71: §12 34f — … and the blank-column canary raises a platform_risk signal ("zero rows" and "nobody consented" are indistinguishable in the file)');
SELECT throws_like(format($$SELECT venue.finalize_export(%L, 0, 10, repeat('c',64), %L)$$, tap._fetch151('j9'), tap._fetch151('org1')||'/'||tap._fetch151('j9')||'.csv'),
  '%lease_expired%', 'D72: a finalize after lease expiry is refused — the build must re-claim and rebuild from page 1');
SELECT throws_like(format($$SELECT * FROM venue.build_export_rows(%L, 'page-2', 100)$$, tap._fetch151('j7')),
  '%not buildable%', 'D73: a ready job is not buildable');
-- row retention: {expired, revoked} + deleted + purge_after passed ⇒ purged
UPDATE venue.export_job SET purge_after = now() - interval '1 day' WHERE job_id = tap._fetch151('j5')::uuid;
SELECT is((venue.sweep_expired_exports() ->> 'purged'), '1', 'D74: the sweep purges the ONE revoked+deleted job past its 13-month row retention');
SELECT ok((SELECT (j).state='purged' FROM tap._job151(tap._fetch151('j5')::uuid) j) AND tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.purge', 'job_row_retention') = 1,
  'D75: … terminal `purged`, audited');
UPDATE venue.export_job SET purge_after = now() - interval '1 day' WHERE job_id = tap._fetch151('j1')::uuid;
SELECT is((venue.sweep_expired_exports() ->> 'purged'), '1', 'D75a: E-78 — a FAILED job (never held bytes) also purges at its row retention, so parked builds do not accumulate forever');
-- audit hygiene: §12 33 content scan + EX-5 every transition audited
SELECT is((SELECT count(*)::int FROM kernel.admin_audit a WHERE a.action LIKE 'crm_export.%'
            AND ((a.after - 'constraint_set_version')::text ~ '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+'   -- the X-9 id is "…@v1", not an address
                 OR a.after::text ILIKE '%org_customer_key%' OR a.after::text ILIKE '%customer_ref%')), 0,
  'D76: §12 33 — no crm_export audit payload contains an email, an org_customer_key, or a customer_ref value');
SELECT ok(tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.request') = 1 AND tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.download') = 3
       AND tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.revoke') = 1 AND tap._audit151(tap._fetch151('j5')::uuid, 'crm_export.purge') = 3,
  'D77: §12 32 / EX-5 — every transition of one job''s life left its audit row (request, 3 downloads, revoke, 3 purge rows)');

-- ============================================================================
-- SECTION E — PFA-28: THE THREE customer_ref READERS ARE PARKED FAIL-CLOSED
-- ============================================================================
SELECT tap._store151('ac0', tap._auditcount151()::text);
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.list_attendees(%L,'{}',NULL,NULL)$$, tap._fetch151('session1')),
  'P0001', NULL, 'E1: PFA-28 (A) — list_attendees FAILS CLOSED for a fully authorized org_owner');
SELECT throws_like(format($$SELECT venue.list_attendees(%L,'{}',NULL,NULL)$$, tap._fetch151('session1')),
  '%customer_ref_crypto_unavailable%PFA-28%', 'E2: … naming the ruling, not a substitute identifier');
SELECT throws_like(format($$SELECT venue.list_attendees(%L,'{"gender_identity":["x"]}',NULL,NULL)$$, tap._fetch151('session1')),
  '%not a member of the closed grammar%', 'E3: the closed filter grammar is enforced BEFORE the park (a demographic filter name raises)');
SELECT tap.logout();
SELECT tap.login(tap.fan151());
SELECT throws_ok(format($$SELECT venue.list_attendees(%L,'{}',NULL,NULL)$$, tap._fetch151('session1')),
  '42501', NULL, 'E4: authz is preserved: a plain fan is denied BEFORE the park (42501, not the park)');
SELECT throws_ok($$SELECT venue.list_attendees(gen_random_uuid(),'{}',NULL,NULL)$$,
  '42501', NULL, 'E4a: CRM §4.2(5) — an UNKNOWN session fails identically to an unauthorized one (no existence oracle)');
SELECT throws_ok($$SELECT venue.lookup_attendee(gen_random_uuid(),'order_ref','X')$$,
  '42501', NULL, 'E4b: … likewise the lookup');
SELECT throws_ok($$SELECT venue.list_export_jobs('session',gen_random_uuid(),NULL)$$,
  '42501', NULL, 'E4c: … likewise the history read');
SELECT throws_ok(format($$SELECT venue.lookup_attendee(%L,'email_exact','x@y.z')$$, tap._fetch151('session1')),
  '42501', NULL, 'E5: … likewise for lookup_attendee');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT throws_like(format($$SELECT venue.list_attendees(%L,'{}',NULL,NULL)$$, tap._fetch151('session1')),
  '%reason_code is required on the platform arm%', 'E6: T-RLS-CRM-03 / AUTHZ-M12 — the platform arm without a reason code is refused (before the park)');
SELECT throws_like(format($$SELECT venue.list_attendees(%L,'{}',NULL,'because')$$, tap._fetch151('session1')),
  '%reason_code is required on the platform arm%', 'E7: free text is not a reason (closed enum)');
SELECT throws_like(format($$SELECT venue.list_attendees(%L,'{}',NULL,'support_ticket:T-42')$$, tap._fetch151('session1')),
  '%customer_ref_crypto_unavailable%', 'E8: with a closed-enum reason the platform arm reaches the park (authz + reason accepted, no data)');
SELECT throws_like(format($$SELECT venue.lookup_attendee(%L,'name_prefix','ab')$$, tap._fetch151('session1')),
  '%prefix_too_short%', 'E9: T-RPC-CRM-13 — a 2-char name_prefix raises prefix_too_short BEFORE any data');
SELECT throws_like(format($$SELECT venue.lookup_attendee(%L,'name_prefix','abc')$$, tap._fetch151('session1')),
  '%customer_ref_crypto_unavailable%', 'E10: PFA-28 — lookup_attendee (platform_support) fails closed');
SELECT throws_like(format($$SELECT venue.lookup_attendee(%L,'phone','555')$$, tap._fetch151('session1')),
  '%query_kind must be%', 'E11: the query kind is the closed triple (no phone lookup exists)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.lookup_attendee(%L,'order_ref','ORD-1')$$, tap._fetch151('session1')),
  '42501', NULL, 'E12: both marketing labels are DENIED the lookup (§7.2)');
SELECT tap.logout();
SELECT is(tap._auditcount151() - tap._fetch151('ac0')::int, 0,
  'E13: PFA-28 zero mutation — none of the parked reads left an audit row');
-- a raise rolls writes back, so E13 alone cannot distinguish "wrote then raised" from "never wrote":
-- the two on-screen readers must contain NO write at all, and the park must precede any limiter call.
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue' AND p.proname IN ('list_attendees','lookup_attendee')
              AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* '\m(insert|update|delete)\M'), 0,
  'E13a: structurally — list_attendees and lookup_attendee contain no INSERT/UPDATE/DELETE at all (zero mutation by construction)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue' AND p.proname IN ('list_attendees','lookup_attendee')
              AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'check_rate_limit'), 0,
  'E14: … and neither reaches the limiter before the park (no rate budget is consumed by a parked read)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue' AND p.proname IN ('build_export_rows','list_attendees','lookup_attendee')
              AND (regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'md5\s*\(' OR regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'sha256\s*\('
                   OR regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'digest\s*\(' OR regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'hmac\s*\('
                   OR regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'identity_id::text' OR regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'left\s*\(\s*[a-z_.]*identity_id'
                   OR regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'gen_random_uuid\s*\(\)\s*as\s*customer_ref')), 0,
  'E15: PFA-28 (B/C/D) — no reader body computes a weak, unkeyed, truncated-uuid or random substitute for customer_ref');
-- The Supabase platform pre-installs pgcrypto as a default extension, so "absent from the
-- cluster" is not the ruling's condition; "087 installs no extension and no 087 routine
-- uses a pgcrypto symbol" is (the byte-level half — no `create extension` in 087 — is
-- asserted by scripts/ci/x6_gate.sh on every PR).
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname IN ('venue','kernel')
              AND p.proname IN ('open_settlement','close_settlement','request_org_payout','settlement_royalty_lines','settlement_commission_lines',
                'on_payout_settled','assert_may_request','request_export','build_export_rows','finalize_export','authorize_export_download','revoke_export',
                'sweep_expired_exports','claim_artifacts_for_purge','confirm_artifact_purged','reconcile_export_orphans','list_export_jobs',
                'list_attendees','lookup_attendee')
              AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* '\m(hmac|digest|gen_random_bytes|crypt|gen_salt|pgp_[a-z_]+|encrypt|decrypt)\s*\('), 0,
  'E16: PFA-28 — no 087 routine references a pgcrypto symbol (the crypto mechanism is a separate ratification; 087 creates no extension — gate-asserted)');
SELECT ok((SELECT bool_and(p.prosrc ILIKE '%PFA-28%') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue' AND p.proname IN ('build_export_rows','list_attendees','lookup_attendee')),
  'E17: each of the three readers cites the ruling at its park (greppable un-park point)');

-- ============================================================================
-- SECTION G — CROSS-ORG ISOLATION (T-RPC-CRM-03 / T-RLS-CRM-02 / §12 15-17)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','ck87-g1')$$, tap._fetch151('session2')),
  '42501', NULL, 'G1: venue_marketing at V1 is denied at another org''s venue');
SELECT throws_ok(format($$SELECT venue.list_attendees(%L,'{}',NULL,NULL)$$, tap._fetch151('session2')),
  '42501', NULL, 'G2: … and its roster');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT lives_ok(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','ck87-g3')$$, tap._fetch151('session2')),
  'G3: org2''s owner reaches org2''s session');
SELECT throws_ok(format($$SELECT venue.request_export('session',%L,'audience_v1','{}','ck87-g4')$$, tap._fetch151('session1')),
  '42501', NULL, 'G4: … and, holding only org_finance at org1, not org1''s');
SELECT tap.logout();   -- the predicate is service_role-only (OR-10): evaluated here under the owning context
SELECT ok(venue.assert_may_request(tap.seller(), 'venue', tap._fetch151('venue2')::uuid, 'audience_v1', false) = false
       AND venue.assert_may_request(tap.seller(), 'venue', tap._fetch151('venue1')::uuid, 'audience_v1', false) = true,
  'G5: the predicate evaluates an ARBITRARY actor over the scope''s org (org1''s owner: V1 yes, V2 no)');
SELECT ok(venue.assert_may_request(tap.buyer(), 'org', tap._fetch151('org1')::uuid, 'audience_v1', false) = false,
  'G6: org grain: a venue role does NOT reach an org-wide export (the plane of the grant is the scope)');
SELECT ok(venue.assert_may_request(tap.admin_user(), 'session', tap._fetch151('session1')::uuid, 'audience_v1', false) = false
       AND venue.assert_may_request(tap.admin_user(), 'session', tap._fetch151('session1')::uuid, 'operations_v1', false) = false,
  'G7: platform is denied on EVERY arm of the predicate');

SELECT * FROM finish();
ROLLBACK;
