-- ============================================================================
-- 144_phase2_venue_staff_authz.sql — Phase-2 package 080 test suite.
--
-- Frozen sources: plan §8/080 (MN-2 six-label set; AUTHZ-PKG1 verification
-- demands) · schema §3.9 · ROLE_MODEL §3.4 · RLS §2.2 (R-8/R-9), §9.9, §11.1
-- (AUTHZ-M7/MD-15), §16.10, §16.10a (the four USING clauses; R3-3a; OPEN-1;
-- GP-3 NOTE; I-4/E-24), §16.11 (T-RLS-FORCE-02, T-RLS-POL-03, T-RLS-ROLE-04,
-- T-RLS-ROLE-07) · RPC §1.1a, §20.4.1/§20.4.2 (T-RPC-STAFF-01/-02,
-- T-RPC-AUTHZ-14) · ODR-16 INV #23/#24 (the OR-17 rider) · PFA-10 activation
-- (the 078/079 deferred venue arms go LIVE with this package — §15 re-test).
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK (no committed state).
-- ============================================================================
BEGIN;
SELECT plan(114);

SELECT tap.seed_core();

CREATE TABLE tap.memo_144 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store144(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_144 VALUES (k, v)
    ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch144(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_144 WHERE k = $1 $m$;

-- ============================================================================
-- SECTION A — THE 080 CLOSED WORLD
-- ============================================================================

SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'venue' AND c.relkind = 'r'), 23,
  -- 2026-08-31 (package 081): 1 -> 6; (package 082): 6 -> 8 (order + order_item).
  -- 2026-09-01 (package 086): 8 -> 20 (+12 door/scan tables).
  -- 2026-09-01 (package 087): 20 -> 23 (settlement, settlement_line, export_job).
  'A1: venue holds TWENTY-THREE tables — 20 post-086 + 087''s three settlement/export');
SELECT is((SELECT count(*)::int FROM information_schema.columns
            WHERE table_schema='venue' AND table_name='staff_role'), 5,
  'A2: the five §3.9 columns');
SELECT col_is_pk('venue','staff_role', ARRAY['venue_id','identity_id','role'],
  'A3: composite PK (venue_id, identity_id, role) — a person may hold several venue roles');
SELECT col_is_null('venue','staff_role','granted_by',
  'A4: granted_by NULLABLE — INV #24''s SET NULL cleanup needs it');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='venue' AND c.relname='staff_role' AND c.relrowsecurity), 1,
  'A5: RLS is ON');
SELECT is((SELECT c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='venue' AND c.relname='staff_role'), false,
  'A6: T-RLS-FORCE-02 — relforcerowsecurity = false, POSITIVELY (INV-NOFORCE: owner-bypass terminates the helper recursion)');
SELECT is((SELECT string_agg(p.polname, ',' ORDER BY p.polname)
            FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
           WHERE c.relname = 'staff_role'),
  'venue_staff_role_sel_org,venue_staff_role_sel_platform,venue_staff_role_sel_venue',
  'A7: exactly the three §16.10 register names');

-- the four AUTHZ-PKG1 policies exist BY NAME (existence half of T-RLS-POL-03)
SELECT is((SELECT string_agg(p.polname, ',' ORDER BY p.polname)
            FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
           WHERE c.relname = 'venue' AND c.relnamespace = 'catalog'::regnamespace),
  'catalog_venue_sel_anon,catalog_venue_sel_org,catalog_venue_sel_venue',
  'A8: catalog.venue carries its three policies incl. the deferred _sel_venue');
SELECT is((SELECT string_agg(p.polname, ',' ORDER BY p.polname)
            FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
           WHERE c.relname = 'event' AND c.relnamespace = 'catalog'::regnamespace),
  'catalog_event_sel_anon,catalog_event_sel_org,catalog_event_sel_venue',
  'A9: catalog.event likewise');
SELECT is((SELECT string_agg(p.polname, ',' ORDER BY p.polname)
            FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
           WHERE c.relname = 'event_session'),
  'catalog_event_session_sel_anon,catalog_event_session_sel_org,catalog_event_session_sel_venue',
  'A10: catalog.event_session likewise');
SELECT is((SELECT string_agg(p.polname, ',' ORDER BY p.polname)
            FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
           WHERE c.relname = 'tickets'),
  'kernel_tickets_sel_owner,kernel_tickets_sel_platform,kernel_tickets_sel_venue',
  'A11: kernel.tickets carries THREE policies — the 079-deferred _sel_venue arrived (AUTHZ-PKG1; the org arm rides it, GP-3 NOTE)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname IN ('kernel','catalog','venue')
             AND coalesce(btrim(pg_get_expr(p.polqual, p.polrelid)),'') = 'true'), 0,
  'A12: still no USING(true) anywhere (I-2 / T-RLS-POL-02)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname IN ('kernel','catalog','venue') AND p.polcmd::text <> 'r'), 0,
  'A13: no INSERT/UPDATE/DELETE policy exists (T-RLS-POL-05)');

-- function closed world
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'kernel'), 107,
  -- 2026-09-02 (package 088): 103 -> 107 (the engine + three dispute verbs).
  -- 2026-09-01 (package 086): 94 -> 99 (the five door/scan kernel fns; 141 F2/F3).
  -- 2026-09-01 (package 087): 99 -> 103. Four kernel settlement fns: the two SEAM-2
  -- seam stubs (royalty/commission lines), close_settlement, request_org_payout.
  'A14: kernel holds EXACTLY 107 functions (103 post-087 + 088''s engine and three dispute verbs)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'venue'), 60,
  -- 2026-09-01 (package 087): +14 venue fns — open_settlement, assert_may_request and the
  -- twelve CRM export/read RPCs (on_payout_settled is a SEAM-2 body-replace, already counted).
  -- 2026-09-01 (package 085): 15 -> 18 (finalize_primary_order + the two SEAM-2 stubs, R2B/C111).
  -- 2026-09-01 (package 086): 18 -> 46 (+28: 27 door/scan/comp/guest/manifest/holder-mix
  -- RPCs + the guard_door_manifest_transition trigger fn; append_door_manifest_delta
  -- is a SEAM-2 body-replace, already counted).
  'A15: venue holds EXACTLY sixty functions — 46 post-086 + 087''s fourteen');
SELECT has_function('kernel'::name,'has_venue_role'::name, ARRAY['uuid','text[]']::name[],
  'A16: has_venue_role(uuid, text[]) exists — the PFA-10 deferred name RESOLVES from this package on');
SELECT has_function('kernel'::name,'has_event_role'::name, ARRAY['uuid','text[]']::name[], 'A17: has_event_role');
SELECT has_function('kernel'::name,'has_org_role_over_venue'::name, ARRAY['uuid','text[]']::name[], 'A18: has_org_role_over_venue (R-9)');
SELECT has_function('kernel'::name,'has_org_role_over_event'::name, ARRAY['uuid','text[]']::name[], 'A19: has_org_role_over_event (R-9)');
SELECT hasnt_function('kernel'::name,'is_promoter_for_event'::name, 'A20: is_promoter_for_event is 090''s — not here');
SELECT has_function('kernel'::name,'assert_door_session'::name, ARRAY['uuid','uuid','uuid','text']::name[], 'A21: assert_door_session authored by 086 (tokenized door session)');
SELECT has_function('venue'::name,'register_scan_device'::name, ARRAY['uuid','text','text']::name[], 'A22: the scan-device verb exists — 086');
SELECT has_function('venue'::name,'open_door_manifest'::name, ARRAY['uuid','text','text']::name[], 'A23: the door-manifest verb exists — 086');

-- T-RLS-ROLE-07 per name: definer, postgres-owned, STABLE, pinned, no anon EXEC
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='kernel'
             AND p.proname in ('has_venue_role','has_event_role',
                               'has_org_role_over_venue','has_org_role_over_event')
             AND p.prosecdef AND p.provolatile = 's'
             AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname='postgres')
             AND array_to_string(p.proconfig,',') LIKE '%search_path=%'
             AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
             AND has_function_privilege('authenticated', p.oid, 'EXECUTE')), 4,
  'A24: T-RLS-ROLE-07 — all four predicates are definer, postgres-owned, STABLE, search_path-pinned, authenticated-only');
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='has_venue_role')) NOT LIKE '%door_pin%',
  'A25: T-RLS-ROLE-04 — has_venue_role does NOT reference venue.door_pin (R-8: the door-PIN branch is dead)');
SELECT ok(has_function_privilege('authenticated','venue.grant_staff_role(uuid, uuid, text, text)','EXECUTE')
       AND has_function_privilege('authenticated','venue.revoke_staff_role(uuid, uuid, text, text)','EXECUTE')
       AND NOT has_function_privilege('anon','venue.grant_staff_role(uuid, uuid, text, text)','EXECUTE'),
  'A26: the two staff RPCs are authenticated-only (authority lives in their bodies, AUTHZ-M7)');

-- SEAM-2 tally after 080: TWO real bodies, NINE neutral
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='on_identity_erased_staff')) LIKE '%venue.staff_role%',
  'A27: the 080-owned SEAM-2 slot carries its REAL body — the stub is no longer live (§0.4b)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='kernel'
             AND ((p.proname in ('deletion_blockers_orders','deletion_blockers_wallet',
                                 'deletion_blockers_money','deletion_blockers_market')
                   AND btrim(p.prosrc)='select null::text')
               OR (p.proname in ('on_identity_erased_door','on_identity_erased_market',
                                 'on_identity_erased_promoter','on_deletion_q5_release')
                   AND btrim(p.prosrc)='select')
               OR (p.proname='has_outstanding_obligations' AND btrim(p.prosrc)='select false'))), 1,
  -- 2026-09-01 (package 086): on_identity_erased_door filled — byte-neutral 4 -> 3
  -- (deletion_blockers_market + on_identity_erased market/promoter remain).
  -- 2026-09-02 (package 088): deletion_blockers_market + on_identity_erased_market filled — 3 -> 1.
  'A28: ONE hook remains byte-neutral — 088 filled both market hooks (promoter pending → 090)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='kernel' AND p.proname='on_identity_erased_staff'), 1,
  'A29: SEAM-2a — exactly one overload');
SELECT ok(has_function_privilege('service_role','kernel.on_identity_erased_staff(uuid)','EXECUTE')
       AND NOT has_function_privilege('authenticated','kernel.on_identity_erased_staff(uuid)','EXECUTE'),
  'A30: …and it keeps 077''s DEF ACL through CREATE OR REPLACE');

-- E-24: the I-4 column narrowing on kernel.tickets
SELECT ok(NOT has_column_privilege('authenticated','kernel.tickets','current_owner_id','SELECT'),
  'A31: E-24/I-4 — current_owner_id (owner PII, §7.5 fn8) is NOT among authenticated''s granted columns');
SELECT ok(has_column_privilege('authenticated','kernel.tickets','state','SELECT')
       AND has_column_privilege('authenticated','kernel.tickets','ticket_atom_id','SELECT'),
  'A32: …while the sixteen non-PII columns remain granted');

-- regressions pinned structurally
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='sweep_deletion_pending')) LIKE '%transaction_isolation%',
  'A33: HARDENING-1 survives 080');
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='deletion_blockers_custody')) LIKE '%kernel.tickets%',
  'A34: the 079 BP-1 real body survives 080');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'tickets' AND t.tgname = 'tg_custody_head_is_ledger_tail'
             AND t.tgdeferrable AND t.tginitdeferred), 1,
  'A35: the MB-4 trigger survives 080');

-- ============================================================================
-- SECTION B — fixtures + grant/revoke semantics (§20.4.1/.2)
-- ============================================================================

SELECT tap.login(tap.seller());
SELECT tap._store144('org',
  (kernel.create_organization('Staff Co','Staff Co','ck-o-1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch144('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store144('venue',
  (catalog.create_venue(tap._fetch144('org')::uuid,'Main Room','wynwood',NULL,'ck-v-1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch144('venue')::uuid,'approved','miami_gate','ck-a-1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store144('venue2',
  (catalog.create_venue(tap._fetch144('org')::uuid,'Annex','brickell',NULL,'ck-v-2') ->> 'venue_id'));
SELECT tap._store144('event',
  (catalog.create_event(tap._fetch144('venue')::uuid,'Staff Night',
     jsonb_build_object('starts_at',(now()+interval '21 days')::text,
                        'ends_at',(now()+interval '21 days 5 hours')::text),'ck-e-1') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._store144('session',
  (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch144('event')::uuid));

-- staff principals
INSERT INTO auth.users (id,email,role,instance_id,aud,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-00000000e001','m@t.local' ,'authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-00000000e002','f@t.local' ,'authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-00000000e003','bo@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-00000000e004','mk@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-00000000e005','pm@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-00000000e006','sc@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-00000000e007','m2@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-00000000e008','st@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now())
ON CONFLICT DO NOTHING;

-- an ordinary fan cannot self-serve authority
SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e002','venue_manager','ck-g-0')$$,
  tap._fetch144('venue')), '42501', NULL,
  'B1: an unaffiliated authenticated user cannot grant anything');
SELECT tap.logout();

-- the org arm mints the first venue_manager (MD-15: the org tier CREATES managers)
SELECT tap.login(tap.seller());
SELECT is((venue.grant_staff_role(tap._fetch144('venue')::uuid,
  '00000000-0000-0000-0000-00000000e001','venue_manager','ck-g-1') ->> 'status'), 'ok',
  'B2: org_owner grants venue_manager THROUGH the §1.1a inheritance helper');
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,%L,'venue_manager','ck-g-2')$$,
  tap._fetch144('venue'), tap.seller()), NULL, NULL,
  'B3: T-RPC-STAFF-01 — self-grant raises');
SELECT tap.logout();

-- the venue_manager mints the five non-manager labels (T-RPC-AUTHZ-14: a narrowing, not a lockout)
SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT is((venue.grant_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e002','venue_finance','ck-g-3') ->> 'status'),'ok','B4: manager grants venue_finance');
SELECT is((venue.grant_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e003','venue_box_office','ck-g-4') ->> 'status'),'ok','B5: …venue_box_office');
SELECT is((venue.grant_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e004','venue_marketing','ck-g-5') ->> 'status'),'ok','B6: …venue_marketing');
SELECT is((venue.grant_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e005','venue_promoter_manager','ck-g-6') ->> 'status'),'ok','B7: …venue_promoter_manager');
SELECT is((venue.grant_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e006','venue_scanner','ck-g-7') ->> 'status'),'ok','B8: …venue_scanner');
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e007','venue_manager','ck-g-8')$$,
  tap._fetch144('venue')), NULL, NULL,
  'B9: T-RPC-AUTHZ-14 — a venue_manager granting venue_manager raises tier_guard (AUTHZ-M7: minting a custody-boundary principal is an org-plane act)');
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e007','venue_door','ck-g-9')$$,
  tap._fetch144('venue')), NULL, NULL, 'B10: the superseded label venue_door raises (MN-2)');
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e007','venue_promoter','ck-g-10')$$,
  tap._fetch144('venue')), NULL, NULL, 'B11: the superseded label venue_promoter raises (a promoter is a relationship, not a staff grant)');
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e007','org_owner','ck-g-11')$$,
  tap._fetch144('venue')), NULL, NULL, 'B12: a cross-scope org_* label raises (C36 disjointness)');
SELECT is((venue.grant_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e002','venue_finance','ck-g-12') ->> 'status'),
  'noop_replay', 'B13: a re-grant is noop_replay (PK idempotency)');
SELECT tap.logout();

-- a non-manager staff label cannot grant
SELECT tap.login('00000000-0000-0000-0000-00000000e003');
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e007','venue_scanner','ck-g-13')$$,
  tap._fetch144('venue')), '42501', NULL,
  'B14: T-RPC-STAFF-01 — a venue_box_office caller raises (box office is not roster authority)');
SELECT tap.logout();

-- wrong-venue manager: m2 manages venue2, cannot touch venue1
SELECT tap.login(tap.seller());
SELECT venue.grant_staff_role(tap._fetch144('venue2')::uuid,'00000000-0000-0000-0000-00000000e007','venue_manager','ck-g-14');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e007');
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e008','venue_scanner','ck-g-15')$$,
  tap._fetch144('venue')), '42501', NULL,
  'B15: a manager of ANOTHER venue holds no authority here (scope is one venue per grant row)');
SELECT tap.logout();

-- ============================================================================
-- SECTION C — the four AUTHZ-PKG1 policies, behaviourally (T-RLS-POL-03's
-- positive half: existence alone would pass against a wrong predicate)
-- ============================================================================

-- a DRAFT venue of the same org isolates the venue arm from the anon policy
SELECT tap.login(tap.seller());
SELECT tap._store144('venue3',
  (catalog.create_venue(tap._fetch144('org')::uuid,'Backroom','wynwood',NULL,'ck-v-3') ->> 'venue_id'));
SELECT venue.grant_staff_role(tap._fetch144('venue3')::uuid,'00000000-0000-0000-0000-00000000e001','venue_manager','ck-g-16');
SELECT venue.grant_staff_role(tap._fetch144('venue3')::uuid,'00000000-0000-0000-0000-00000000e002','venue_finance','ck-g-17');
SELECT tap.logout();

SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT is((SELECT count(*)::int FROM catalog.venue WHERE venue_id = tap._fetch144('venue3')::uuid), 1,
  'C1: §8.1 — venue_manager reads their own venue INCLUDING draft (the anon policy cannot see it)');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e002');
SELECT is((SELECT count(*)::int FROM catalog.venue WHERE venue_id = tap._fetch144('venue3')::uuid), 1,
  'C2: every other venue label also reads its own venue (the §16.10a clause carries no status term)');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e007');
SELECT is((SELECT count(*)::int FROM catalog.venue WHERE venue_id = tap._fetch144('venue3')::uuid), 0,
  'C3: T-RLS-POL-03 — a manager of a DIFFERENT venue reads ZERO rows of this one');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e008');
SELECT is((SELECT count(*)::int FROM catalog.venue WHERE venue_id = tap._fetch144('venue3')::uuid), 0,
  'C4: an unaffiliated fan reads zero draft-venue rows');
SELECT tap.logout();

-- catalog.event: the two tiers, per label (R3-3a)
UPDATE catalog.event SET status = 'draft' WHERE event_id = tap._fetch144('event')::uuid;
SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT is((SELECT count(*)::int FROM catalog.event WHERE event_id = tap._fetch144('event')::uuid), 1,
  'C5: ONLY venue_manager sees a DRAFT event of their venue');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e002');
SELECT is((SELECT count(*)::int FROM catalog.event WHERE event_id = tap._fetch144('event')::uuid), 0,
  'C6: R3-3a per label — venue_finance reads ZERO draft-event rows');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e003');
SELECT is((SELECT count(*)::int FROM catalog.event WHERE event_id = tap._fetch144('event')::uuid), 0,
  'C7: …venue_box_office zero');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e004');
SELECT is((SELECT count(*)::int FROM catalog.event WHERE event_id = tap._fetch144('event')::uuid), 0,
  'C8: …venue_marketing zero');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e005');
SELECT is((SELECT count(*)::int FROM catalog.event WHERE event_id = tap._fetch144('event')::uuid), 0,
  'C9: …venue_promoter_manager zero');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e006');
SELECT is((SELECT count(*)::int FROM catalog.event WHERE event_id = tap._fetch144('event')::uuid), 0,
  'C10: …venue_scanner zero — five labels asserted, because a single-label test passes while five leak');
SELECT tap.logout();
UPDATE catalog.event SET status = 'announced' WHERE event_id = tap._fetch144('event')::uuid;
SELECT tap.login('00000000-0000-0000-0000-00000000e006');
SELECT is((SELECT count(*)::int FROM catalog.event WHERE event_id = tap._fetch144('event')::uuid), 1,
  'C11: once announced, the second tier reads it');
-- event_session: the scanner arm is deliberately ABSENT (OPEN-1)
SELECT is((SELECT count(*)::int FROM catalog.event_session WHERE session_id = tap._fetch144('session')::uuid), 1,
  'C12: …and the scanner reads the session ONLY through the anon arm of a visible event — ');
SELECT tap.logout();

-- prove OPEN-1 with a draft event: anon arm dark, scanner arm absent => zero
UPDATE catalog.event SET status = 'draft' WHERE event_id = tap._fetch144('event')::uuid;
SELECT tap.login('00000000-0000-0000-0000-00000000e006');
SELECT is((SELECT count(*)::int FROM catalog.event_session WHERE session_id = tap._fetch144('session')::uuid), 0,
  'C13: OPEN-1 — venue_scanner has NO arm on event_session (fail-closed; the manifest read is 086''s get_door_manifest)');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e002');
SELECT is((SELECT count(*)::int FROM catalog.event_session WHERE session_id = tap._fetch144('session')::uuid), 1,
  'C14: venue_finance DOES hold the event-grain session read');
SELECT tap.logout();
UPDATE catalog.event SET status = 'announced' WHERE event_id = tap._fetch144('event')::uuid;

-- 084 adopt: the fixture's fixed ticket_type/signing_key ids must now be REAL
-- rows — kernel.tickets carries fk_tickets_ticket_type/fk_tickets_signing_key.
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility)
VALUES ('00000000-0000-0000-0000-00000000d0d0', tap._fetch144('event')::uuid, 'admission', 'FIX-84', 5000, 'public');
INSERT INTO kernel.signing_key (key_id, scope, event_id, public_key, kms_handle_ref, status, not_before)
VALUES ('00000000-0000-0000-0000-00000000c0c0', 'per_event', tap._fetch144('event')::uuid, 'PUBKEY-FIX', 'kms-fix', 'active', now());

-- kernel.tickets: the session-grain clause, both arms
CREATE FUNCTION tap._mint144(p_atom uuid, p_owner uuid, p_serial int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $m$
begin
  insert into kernel.tickets (ticket_atom_id, event_session_id, org_id, ticket_type_id,
                              serial_no, current_owner_id, state, signing_key_id)
  values (p_atom, (select v from tap.memo_144 where k='session')::uuid,
          (select v from tap.memo_144 where k='org')::uuid,
          '00000000-0000-0000-0000-00000000d0d0', p_serial, p_owner, 'active',
          '00000000-0000-0000-0000-00000000c0c0');
  insert into kernel.ticket_ownership_log
         (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
          actor_identity, command_idempotency_key, credential_version_after, state_transition)
  values (p_atom, 1, null, p_owner, 'issue', gen_random_uuid(), p_owner,
          'ck-i-'||p_serial::text, 0, '{}'::jsonb);
end $m$;
SELECT tap._mint144('00000000-0000-0000-0000-00000000f001', tap.buyer(), 1);
SELECT tap._mint144('00000000-0000-0000-0000-00000000f002', tap.buyer(), 2);

SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT is((SELECT count(*)::int FROM kernel.tickets), 2,
  'C15: venue_manager reads the session''s atoms (the event-grain arm)');
SELECT throws_ok('SELECT current_owner_id FROM kernel.tickets LIMIT 1', '42501', NULL,
  'C16: E-24/I-4 — the venue plane CANNOT select the owner PII column');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e006');
SELECT is((SELECT count(*)::int FROM kernel.tickets), 2,
  'C17: venue_scanner reads them too (§7.5: the scan plane sees its session''s atoms)');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e004');
SELECT is((SELECT count(*)::int FROM kernel.tickets), 0,
  'C18: venue_marketing has NO atom read — the clause names manager/finance/scanner only');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e003');
SELECT is((SELECT count(*)::int FROM kernel.tickets), 0,
  'C19: venue_box_office has NO atom read (box office is not manifest authority)');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e007');
SELECT is((SELECT count(*)::int FROM kernel.tickets), 0,
  'C20: the wrong-venue manager reads zero atoms');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is((SELECT count(*)::int FROM kernel.tickets), 2,
  'C21: the issuer-org arm (org_owner) rides the same policy (GP-3 NOTE)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM kernel.tickets WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000f001'), 1,
  'C22: the OWNER still reads their own atom (sel_owner''s predicate is outside the column ACL)');
SELECT throws_ok('SELECT current_owner_id FROM kernel.tickets LIMIT 1', '42501', NULL,
  'C23: E-24 — the column is gone for the owner too (one role, one grant; it is by definition their own uid)');
SELECT tap.logout();

-- staff_role roster reads (§9.9)
SELECT tap.login('00000000-0000-0000-0000-00000000e006');
SELECT is((SELECT count(*)::int FROM venue.staff_role WHERE venue_id = tap._fetch144('venue')::uuid), 6,
  'C24: every staff label reads its own venue''s roster (scanner sees all six grants)');
SELECT is((SELECT count(*)::int FROM venue.staff_role WHERE venue_id = tap._fetch144('venue2')::uuid), 0,
  'C25: …and zero of another venue''s');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT ok((SELECT count(*) FROM venue.staff_role) >= 8,
  'C26: org_owner reads the rosters of every venue of the org (the §1.1a org arm)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM venue.staff_role), 0, 'C27: a fan reads zero roster rows');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT ok((SELECT count(*) FROM venue.staff_role) >= 8, 'C28: platform reads all (audit)');
SELECT tap.logout();

-- ============================================================================
-- SECTION D — revocation is LIVE (T-RPC-STAFF-02''s property) + recovery
-- ============================================================================

SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT is((venue.revoke_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e006','venue_scanner','ck-r-1') ->> 'status'),
  'ok', 'D1: the manager revokes the scanner');
SELECT is((venue.revoke_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e006','venue_scanner','ck-r-2') ->> 'status'),
  'noop_replay', 'D2: a re-revoke is noop_replay');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e006');
SELECT is((SELECT count(*)::int FROM venue.staff_role WHERE venue_id = tap._fetch144('venue')::uuid), 0,
  'D3: the revoked scanner''s NEXT read fails on the SAME JWT — live-table recheck, no TTL (I-5)');
SELECT is((SELECT count(*)::int FROM kernel.tickets), 0,
  'D4: …and the atom read died with it');
SELECT tap.logout();

-- self-revoke permitted; zero-manager venue is recoverable from the org tier
SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT is((venue.revoke_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e001','venue_manager','ck-r-3') ->> 'status'),
  'ok', 'D5: SELF-REVOKE is permitted — dropping authority is not escalation, and there is no last-manager floor');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is((venue.grant_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e001','venue_manager','ck-g-18') ->> 'status'),
  'ok', 'D6: …because the org tier RESTORES a manager (the recovery §20.4.2 names, closing the MD-15 symmetry)');
SELECT tap.logout();

-- archived venue refuses new grants
SELECT tap.logout();
UPDATE catalog.venue SET approval_status='archived' WHERE venue_id = tap._fetch144('venue3')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e008','venue_scanner','ck-g-19')$$,
  tap._fetch144('venue3')), NULL, NULL, 'D7: venue_archived refuses new grants');
SELECT tap.logout();

-- ============================================================================
-- SECTION E — THE ACTIVATION BOUNDARY (§15): the PFA-10 deferred arms are LIVE
-- ============================================================================

SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT is((catalog.update_event_session(tap._fetch144('session')::uuid,
  '{"session_label":"managed"}'::jsonb,'ck-s-1') ->> 'status'), 'ok',
  'E1: THE ARM IS LIVE — a venue_manager edits a session through the previously dead has_venue_role branch');
SELECT is((catalog.update_event_session(tap._fetch144('session')::uuid,
  jsonb_build_object('starts_at',(now()+interval '20 days')::text,
                     'ends_at',(now()+interval '20 days 5 hours')::text,
                     'reason_code','venue_request'),'ck-s-2') ->> 'status'), 'ok',
  'E2: …including a reason-coded EARLIER time move (atoms exist; the §20.2.4 guard is unchanged)');
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,
  jsonb_build_object('starts_at',(now() + interval '22 days')::text,
                     'ends_at',(now() + interval '22 days 5 hours')::text,
                     'reason_code','x'),'ck-s-3')$$, tap._fetch144('session')),
  NULL, NULL,
  'E3: a LATER move still refuses (move_exceeds_grace; the PFA-9 fail-to-safe posture did not loosen with activation)');
SELECT is((catalog.update_event(tap._fetch144('event')::uuid,
  '{"description":"by the venue"}'::jsonb,'ck-e-2') ->> 'status'), 'ok',
  'E4: 078''s update_event venue arm is live too');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e004');
SELECT is((catalog.update_event_session(tap._fetch144('session')::uuid,
  '{"session_label":"marketed"}'::jsonb,'ck-s-4') ->> 'status'), 'ok',
  'E5: venue_marketing edits the MARKETING-ONLY column (D3 extension, exactly as 079 encoded it)');
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,
  jsonb_build_object('starts_at',(now()+interval '19 days')::text, 'reason_code','x'),'ck-s-5')$$,
  tap._fetch144('session')), '42501', NULL,
  'E6: venue_marketing may NOT touch a time column — freeze inputs are never marketing');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e006');
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,'{"session_label":"scanned"}'::jsonb,'ck-s-6')$$,
  tap._fetch144('session')), '42501', NULL, 'E7: a scanner is DENIED every session edit');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e003');
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,'{"session_label":"boxed"}'::jsonb,'ck-s-7')$$,
  tap._fetch144('session')), '42501', NULL, 'E8: box_office is DENIED (not an operational-edit role)');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e007');
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,'{"session_label":"foreign"}'::jsonb,'ck-s-8')$$,
  tap._fetch144('session')), '42501', NULL, 'E9: the wrong-venue manager is DENIED');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT is((catalog.create_event_session(tap._fetch144('event')::uuid,
  jsonb_build_object('starts_at',(now()+interval '25 days')::text,
                     'session_label','night two'),'ck-cs-1') ->> 'status'), 'ok',
  'E10: 078''s create_event_session venue arm is live');
SELECT is((catalog.update_venue(tap._fetch144('venue')::uuid,
  '{"name":"Main Room East"}'::jsonb,'ck-uv-1') ->> 'status'), 'ok',
  'E11: 078''s update_venue venue arm is live');
SELECT tap.logout();

-- ============================================================================
-- SECTION F — the OR-17 rider: INV #23/#24 through the REAL sweep
-- ============================================================================

SELECT tap.login(tap.seller());
SELECT venue.grant_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e008','venue_scanner','ck-g-20');
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e001');
-- a grant MADE BY the deletion candidate (tests INV #24''s SET NULL half):
-- e001 granted several rows above; e008''s own row was granted by seller.
SELECT tap.logout();
SELECT tap.login('00000000-0000-0000-0000-00000000e008');
SELECT kernel.request_account_deletion('ck-del-1');
SELECT tap.logout();
SELECT kernel.sweep_deletion_pending();
SELECT is((SELECT deletion_state FROM kernel.identity_ext
            WHERE identity_id='00000000-0000-0000-0000-00000000e008'), 'ERASED',
  'F1: a staff grant is NOT a deletion blocker — the identity tombstones');
SELECT is((SELECT count(*)::int FROM venue.staff_role
            WHERE identity_id='00000000-0000-0000-0000-00000000e008'), 0,
  'F2: INV #23 — the erased identity''s staff rows are REMOVED (a tombstone holds no authority)');

-- now erase a GRANTOR: e001 granted f/bo/mk/pm rows
SELECT tap.login('00000000-0000-0000-0000-00000000e001');
SELECT venue.revoke_staff_role(tap._fetch144('venue')::uuid,'00000000-0000-0000-0000-00000000e001','venue_manager','ck-r-4');
SELECT kernel.request_account_deletion('ck-del-2');
SELECT tap.logout();
SELECT kernel.sweep_deletion_pending();
SELECT is((SELECT deletion_state FROM kernel.identity_ext
            WHERE identity_id='00000000-0000-0000-0000-00000000e001'), 'ERASED',
  'F3: the ex-manager tombstones');
SELECT is((SELECT count(*)::int FROM venue.staff_role
            WHERE granted_by='00000000-0000-0000-0000-00000000e001'), 0,
  'F4: INV #24 — no surviving row points at the tombstone as grantor');
SELECT ok((SELECT count(*) FROM venue.staff_role
            WHERE venue_id = tap._fetch144('venue')::uuid
              AND granted_by IS NULL) >= 4,
  'F5: …the grants THEMSELVES survive with granted_by SET NULL (the grantee''s authority is a fact of the venue, not of the grantor)');
SELECT tap.login('00000000-0000-0000-0000-00000000e002');
SELECT is((SELECT count(*)::int FROM catalog.event_session WHERE session_id = tap._fetch144('session')::uuid), 1,
  'F6: …and a surviving grantee''s authority still works');
SELECT tap.logout();

-- E-26: the cleanup is TERMINAL — no writer can resurrect a tombstone's authority
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.grant_staff_role(%L,'00000000-0000-0000-0000-00000000e008','venue_scanner','ck-g-21')$$,
  tap._fetch144('venue')), NULL, NULL,
  'F7: E-26 — granting to an ERASED identity refuses (identity_erased): INV #23''s disposition cannot be undone by a manager');
SELECT tap.logout();

-- ============================================================================
-- SECTION G — deny-by-default degenerate inputs (§21)
-- ============================================================================

SELECT tap.login(tap.buyer());
SELECT ok(NOT kernel.has_venue_role('00000000-0000-0000-0000-00000000dead', array['venue_manager']),
  'G1: unknown venue => false');
SELECT ok(NOT kernel.has_venue_role(NULL, array['venue_manager']), 'G2: NULL venue => false');
SELECT ok(NOT kernel.has_venue_role(tap._fetch144('venue')::uuid, array[]::text[]),
  'G3: empty requested-role set => false');
SELECT ok(NOT coalesce(kernel.has_venue_role(tap._fetch144('venue')::uuid, NULL), false),
  'G4: NULL role array never becomes allow');
SELECT ok(NOT kernel.has_event_role('00000000-0000-0000-0000-00000000dead', array['venue_manager']),
  'G5: unknown event => false (the venue resolves NULL, the probe finds nothing)');
SELECT ok(NOT kernel.has_org_role_over_venue('00000000-0000-0000-0000-00000000dead', array['org_owner']),
  'G6: unknown venue on the inheritance path => false');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok(format($$SELECT kernel.has_venue_role(%L, array['venue_manager'])$$, tap._fetch144('venue')),
  '42501', NULL, 'G7: anon cannot even ask');
SELECT tap.logout();

-- ============================================================================
-- SECTION H — regression anchors
-- ============================================================================

SELECT is((SELECT value::text FROM catalog.platform_config
            WHERE key='wallet.apple.enabled' ORDER BY version DESC LIMIT 1), 'false',
  'H1: Wallet stays dark');
SELECT is((SELECT value::text FROM catalog.platform_config
            WHERE key='feature.native_resale_enabled' ORDER BY version DESC LIMIT 1), 'false',
  'H2: Buy Now stays dark');
SELECT is((SELECT jsonb_typeof(value) FROM catalog.platform_config
            WHERE key='retention.backup_window_days'), 'null',
  'H3: the retention failsafe is untouched');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname IN ('kernel','catalog','venue') AND p.prokind='f'
             AND pg_get_functiondef(p.oid) ~* 'insert into kernel\.platform_role'), 0,
  'H4: still ZERO platform-role minting paths (PFA-4 fail-closed)');

SELECT * FROM finish();
ROLLBACK;
