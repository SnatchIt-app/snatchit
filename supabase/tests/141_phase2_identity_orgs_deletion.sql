-- ============================================================================
-- 141_phase2_identity_orgs_deletion.sql — Phase-2 package 077 test suite.
--
-- Frozen sources: plan §8/077 Tests row · schema-spec §1.1-§1.15 · RLS spec
-- (8-policy register, zero-policy register, §11 EXEC classes, I-12) · RPC
-- contracts §2/§20.1/§17.20-21/§20.17 · dsm-spec (OR-13) · R2 rows 22/31/32 ·
-- CRON_SCHEDULE_REGISTER. PFA-3/PFA-4/PFA-5 witnesses included; T-RPC-ROLE-07
-- is BLOCKED by PFA-4 (owner signature) and deliberately absent.
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK (no committed state).
-- ============================================================================
BEGIN;
SELECT plan(188);

SELECT tap.seed_core();

-- per-file memo helpers (rolled back with this transaction; definer so every
-- persona can store/fetch fixture ids)
CREATE TABLE tap.memo_141 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_141 VALUES (k, v)
    ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_141 WHERE k = $1 $m$;
GRANT EXECUTE ON FUNCTION tap._store(text, text), tap._fetch(text) TO PUBLIC;

-- extra clean fixture identities (mirror tap.seed_core's user shape)
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, phone, phone_confirmed_at, created_at, updated_at)
VALUES
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'edith@test.local', '{"provider":"email","providers":["email"]}', '{}', NULL, NULL, now(), now()),
  ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'frank@test.local', '{"provider":"email","providers":["email"]}', '{}', NULL, NULL, now(), now()),
  ('77777777-7777-7777-7777-777777777777', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'grace@test.local', '{"provider":"email","providers":["email"]}', '{}', NULL, NULL, now(), now())
ON CONFLICT (id) DO NOTHING;

-- ── A. OBJECTS — the closed world ───────────────────────────────────────────

SELECT ok(to_regclass('kernel.identity_ext')                is not null, '077 A1: kernel.identity_ext exists');
SELECT ok(to_regclass('kernel.organization')                is not null, '077 A2: kernel.organization exists');
SELECT ok(to_regclass('kernel.org_member')                  is not null, '077 A3: kernel.org_member exists');
SELECT ok(to_regclass('kernel.org_invite')                  is not null, '077 A4: kernel.org_invite exists');
SELECT ok(to_regclass('kernel.platform_role')               is not null, '077 A5: kernel.platform_role exists');
SELECT ok(to_regclass('kernel.admin_audit')                 is not null, '077 A6: kernel.admin_audit exists');
SELECT ok(to_regclass('kernel.approval_request')            is not null, '077 A7: kernel.approval_request exists');
SELECT ok(to_regclass('kernel.identity_demographic')        is not null, '077 A8: kernel.identity_demographic exists');
SELECT ok(to_regclass('kernel.identity_demographic_erasure')is not null, '077 A9: kernel.identity_demographic_erasure exists');
SELECT ok(to_regclass('kernel.identity_contact_pref')       is not null, '077 A10: kernel.identity_contact_pref exists');
-- T-SCHEMA-CRM-01 (K-2): by to_regclass, never by grepping a migration.
SELECT ok(to_regclass('kernel.identity_contact_pref_event') is not null, '077 A11 [T-SCHEMA-CRM-01]: kernel.identity_contact_pref_event EXISTS after replay');
SELECT ok(to_regclass('kernel.org_customer_key')            is not null, '077 A12: kernel.org_customer_key exists');

SELECT is(
  (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'kernel' AND c.relkind = 'r'),
  12, '077 A13: exactly TWELVE kernel tables (plan §8/077 — no extra, no missing)');

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel'),
  40, '077 A14: exactly 40 kernel functions (the two 076 helpers + 077''s 23 caller-authorized + 14 DEF + 1 trigger writer)');

SELECT is(
  (SELECT count(*)::int FROM cron.job WHERE jobname IN ('sweep-deletion-pending','sweep-expired-org-invites')),
  2, '077 A15: both 077 cron jobs are scheduled (register: per-job cron.schedule by the owning package)');
SELECT is(
  (SELECT string_agg(schedule, ',' ORDER BY jobname COLLATE "C")
     FROM cron.job WHERE jobname IN ('sweep-deletion-pending','sweep-expired-org-invites')),
  '*/2 * * * *,*/2 * * * *', '077 A16: both jobs run at the frozen 2-minute cadence');

-- ── B. ROLE LABELS (T-RLS-ROLE-01 / T-SCHEMA-ROLE-02 / M-5) ────────────────

-- the three role columns enumerate exactly 6 + 6(invite) + 3 = 15 CHECK labels
SELECT is(
  (SELECT string_agg(m[1], ',' ORDER BY m[1] COLLATE "C")
     FROM pg_constraint c,
          regexp_matches(pg_get_constraintdef(c.oid), '''(\w+)''', 'g') m
    WHERE c.conrelid = 'kernel.org_member'::regclass AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) like '%role%'),
  'org_admin,org_finance,org_marketing,org_member,org_owner,org_promoter_manager',
  '077 B1 [T-RLS-ROLE-01/M-5]: org_member.role CHECK admits exactly the canonical SIX org labels');
SELECT is(
  (SELECT string_agg(m[1], ',' ORDER BY m[1] COLLATE "C")
     FROM pg_constraint c,
          regexp_matches(pg_get_constraintdef(c.oid), '''(\w+)''', 'g') m
    WHERE c.conrelid = 'kernel.org_invite'::regclass AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) like '%role%' AND pg_get_constraintdef(c.oid) not like '%status%'),
  'org_admin,org_finance,org_marketing,org_member,org_owner,org_promoter_manager',
  '077 B2 [T-RLS-ROLE-01/M-5]: org_invite.role CHECK admits exactly the canonical SIX org labels');
SELECT is(
  (SELECT string_agg(m[1], ',' ORDER BY m[1] COLLATE "C")
     FROM pg_constraint c,
          regexp_matches(pg_get_constraintdef(c.oid), '''(\w+)''', 'g') m
    WHERE c.conrelid = 'kernel.platform_role'::regclass AND c.contype = 'c'),
  'platform_admin,platform_risk,platform_support',
  '077 B3 [T-RLS-ROLE-01]: platform_role.role CHECK admits exactly the THREE platform labels');

-- OR-18: 'declined' is STRUCK from the invite status enum
SELECT is(
  (SELECT string_agg(m[1], ',' ORDER BY m[1] COLLATE "C")
     FROM pg_constraint c,
          regexp_matches(pg_get_constraintdef(c.oid), '''(\w+)''', 'g') m
    WHERE c.conrelid = 'kernel.org_invite'::regclass AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) like '%status%'),
  'accepted,expired,pending,revoked',
  '077 B4 [OR-18]: org_invite.status is the FOUR-label enum — declined is struck');

-- cross-plane disjointness rejects at write time (23514)
SELECT throws_ok(
  $$INSERT INTO kernel.org_member (org_id, identity_id, role)
    VALUES (gen_random_uuid(), tap.seller(), 'venue_scanner')$$,
  '23514', NULL, '077 B5 [T-RLS-ROLE-01]: a venue_* label on org_member.role raises 23514');
SELECT throws_ok(
  $$INSERT INTO kernel.platform_role (identity_id, role) VALUES (tap.seller(), 'org_owner')$$,
  '23514', NULL, '077 B6 [T-RLS-ROLE-01]: an org_* label on platform_role.role raises 23514');

-- T-SCHEMA-ROLE-02 / OD-6: no native enum anywhere in the four Phase-2 schemas
SELECT is(
  (SELECT count(*)::int FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typtype = 'e' AND n.nspname IN ('kernel','catalog','venue','market')),
  0, '077 B7 [T-SCHEMA-ROLE-02]: zero native enums across kernel/catalog/venue/market');

-- ── C. RLS POSTURE + I-12 INV-NOFORCE ──────────────────────────────────────

SELECT is(
  (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'kernel' AND c.relkind = 'r' AND c.relrowsecurity),
  12, '077 C1: RLS is ENABLED on all twelve tables (deny-by-default at birth)');
SELECT is(
  (SELECT relforcerowsecurity FROM pg_class WHERE oid = 'kernel.org_member'::regclass),
  false, '077 C2 [I-12/INV-NOFORCE]: kernel.org_member does NOT force RLS (owner-bypass terminates the helpers)');
SELECT is(
  (SELECT relforcerowsecurity FROM pg_class WHERE oid = 'kernel.platform_role'::regclass),
  false, '077 C3 [I-12/INV-NOFORCE]: kernel.platform_role does NOT force RLS');

-- ── D. POLICY REGISTER (GP-3: the 8 frozen names, zero elsewhere) ──────────

SELECT is(
  (SELECT string_agg(polname, ',' ORDER BY polname COLLATE "C")
     FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'kernel'),
  'kernel_identity_ext_sel_owner,kernel_org_invite_sel_invitee,kernel_org_invite_sel_org,'
  || 'kernel_org_member_sel_org,kernel_org_member_sel_platform,kernel_organization_sel_org,'
  || 'kernel_organization_sel_platform,kernel_platform_role_sel_platform',
  '077 D1 [T-RLS-POL-01]: exactly the EIGHT registered policy names — nothing else');
SELECT is(
  (SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
    WHERE c.oid IN ('kernel.admin_audit'::regclass, 'kernel.approval_request'::regclass,
                    'kernel.identity_demographic'::regclass,
                    'kernel.identity_demographic_erasure'::regclass,
                    'kernel.identity_contact_pref'::regclass,
                    'kernel.identity_contact_pref_event'::regclass,
                    'kernel.org_customer_key'::regclass)),
  0, '077 D2 [§16.10 register]: ZERO policies on the seven deny-all tables (no USING(false) either)');
-- §12 scan continuity, structural half: no RLS policy anywhere conditions on
-- deletion state — pending deletion freezes NEW acquisition only.
SELECT is(
  (SELECT count(*)::int FROM pg_policy p
    WHERE pg_get_expr(p.polqual, p.polrelid) ilike '%deletion%'),
  0, '077 D3 [scan continuity]: no policy in the database references deletion state');
-- the freeze predicate's 077 caller set is exactly the two F-6 hosts
SELECT is(
  (SELECT string_agg(k.proname, ',' ORDER BY k.proname COLLATE "C")
     FROM (SELECT p.oid, p.proname FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.prokind = 'f'
              AND p.proname <> 'is_deletion_pending' OFFSET 0) k
    WHERE pg_get_functiondef(k.oid) like '%is_deletion_pending%'),
  'accept_org_invite,create_organization',
  '077 D4 [F-6 closure]: is_deletion_pending is called by exactly the two F-6 hosts');

-- ── E. HOSTILE GRANTS (GP-1/GP-2; EMPTY grant sets; column scoping) ────────

SELECT tap.login(tap.other_user());
SELECT throws_ok($$INSERT INTO kernel.identity_ext (identity_id) VALUES (tap.other_user())$$,
  '42501', NULL, '077 E1: authenticated cannot INSERT identity_ext directly (writes are RPC-only)');
SELECT throws_ok($$UPDATE kernel.identity_ext SET deletion_state = 'ERASED'$$,
  '42501', NULL, '077 E2: authenticated cannot UPDATE identity_ext (deletion columns are RPC-only)');
SELECT throws_ok($$DELETE FROM kernel.org_member$$,
  '42501', NULL, '077 E3 [GP-2]: authenticated holds no DELETE on org_member');
SELECT throws_ok($$SELECT * FROM kernel.identity_demographic$$,
  '42501', NULL, '077 E4 [DEMOG §10.3]: identity_demographic grant set is EMPTY — SELECT denied');
SELECT throws_ok($$SELECT * FROM kernel.identity_contact_pref_event$$,
  '42501', NULL, '077 E5 [RLS §16.6]: the pref event log is deny-all — the subject cannot read their own history');
SELECT throws_ok($$SELECT * FROM kernel.org_customer_key$$,
  '42501', NULL, '077 E6 [CRM §11.3]: org_customer_key is definer-only — no human role');
SELECT throws_ok($$SELECT legal_name FROM kernel.organization$$,
  '42501', NULL, '077 E7 [RLS §7.2 col-scope]: legal_name is not client-readable');
SELECT throws_ok($$SELECT stripe_connect_account_ref FROM kernel.organization$$,
  '42501', NULL, '077 E8 [RLS §7.2 col-scope]: the connect ref is not client-readable');
SELECT throws_ok($$INSERT INTO kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  VALUES (tap.other_user(), 'x', 'y', gen_random_uuid(), 'z')$$,
  '42501', NULL, '077 E9 [AO §7.12]: no direct client INSERT into admin_audit');
SELECT throws_ok($$SELECT * FROM kernel.approval_request$$,
  '42501', NULL, '077 E10: approval_request is money-custody-RPC-only — direct SELECT denied');
SELECT tap.login_anon();
SELECT throws_ok($$SELECT * FROM kernel.identity_ext$$,
  '42501', NULL, '077 E11: anon holds nothing on identity_ext');
SELECT tap.logout();

-- ── F. FUNCTION ACL TOPOLOGY (PFA-1 standing sweep; 066/067; PFA-5) ────────

-- the PFA-1 compensating control, applied to this package's own functions:
-- zero EXECUTE for PUBLIC and anon on ANY function in the walled schemas.
SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
          lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    WHERE n.nspname IN ('kernel','venue','market','notify')
      AND a.privilege_type = 'EXECUTE'
      AND (a.grantee = 0 OR a.grantee = 'anon'::regrole)),
  0, '077 F1 [PFA-1 sweep]: zero PUBLIC/anon EXECUTE on any walled-schema function');
-- authenticated EXECUTE lands on exactly the 23 caller-authorized functions
SELECT is(
  (SELECT string_agg(p.proname, ',' ORDER BY p.proname COLLATE "C")
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel'
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  'accept_org_invite,admin_set_identity_ext,change_org_role,clear_my_demographics,'
  || 'create_organization,get_my_contact_prefs,get_my_demographics,grant_platform_role,'
  || 'has_org_role,invite_org_member,is_org_affiliate,is_platform,remove_org_member,'
  || 'request_account_deletion,revoke_org_invite,revoke_platform_role,set_my_contact_prefs,'
  || 'set_my_demographics,set_org_connect_ref,set_org_status,update_organization,'
  || 'upsert_identity_ext,withdraw_account_deletion',
  '077 F2 [RLS §11]: authenticated EXECUTE = exactly the 23 caller-authorized functions');
-- the DEF class: service_role EXECUTE = the two sweeps + the predicate + 11 stubs
SELECT is(
  (SELECT string_agg(p.proname, ',' ORDER BY p.proname COLLATE "C")
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel'
      AND has_function_privilege('service_role', p.oid, 'EXECUTE')),
  'deletion_blockers_custody,deletion_blockers_market,deletion_blockers_money,'
  || 'deletion_blockers_orders,deletion_blockers_wallet,has_outstanding_obligations,'
  || 'is_deletion_pending,on_deletion_q5_release,on_identity_erased_door,'
  || 'on_identity_erased_market,on_identity_erased_promoter,on_identity_erased_staff,'
  || 'sweep_deletion_pending,sweep_expired_org_invites',
  '077 F3 [RLS §11 DEF / D-F2]: service_role EXECUTE = exactly the 14 DEF functions');
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND NOT p.prosecdef),
  0, '077 F4 [066]: every kernel function is SECURITY DEFINER');
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proowner <> 'postgres'::regrole),
  0, '077 F5 [066]: every kernel function is owned by postgres');
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel'
      AND NOT exists (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c
                       WHERE c = 'search_path=""')),
  0, '077 F6 [066]: every kernel function pins search_path to EMPTY');
-- PFA-5 witness: the freeze predicate is VOLATILE (FOR SHARE forbids STABLE)
SELECT is(
  (SELECT p.provolatile FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'is_deletion_pending'),
  'v', '077 F7 [PFA-5]: is_deletion_pending is VOLATILE — the F-11 FOR SHARE lock is kept');
SELECT is(
  (SELECT string_agg(p.proname || ':' || p.provolatile::text, ',' ORDER BY p.proname COLLATE "C")
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname IN ('has_org_role','is_platform','is_org_affiliate')),
  'has_org_role:s,is_org_affiliate:s,is_platform:s',
  '077 F8 [§1.1]: the three 077 role predicates are STABLE');

-- ── G. APPROVAL_REQUEST CHECKS (T-SCHEMA-APPR-01/02/05/08 + SoD + C16) ─────

SELECT throws_ok(
  $$INSERT INTO kernel.approval_request
      (action, required_approver_class, subject_kind, subject_id, org_id, payload,
       amount_minor, config_versions, requested_by, expires_at, command_idempotency_key)
    VALUES ('refund.issue', 'org_finance', 'order', gen_random_uuid(), gen_random_uuid(),
            '{}', 100, '{}', tap.seller(), now() + interval '1 day', 'g1')$$,
  '23514', NULL, '077 G1 [T-SCHEMA-APPR-01]: a fourth approver-class label raises 23514');
SELECT throws_ok(
  $$INSERT INTO kernel.approval_request
      (action, required_approver_class, subject_kind, subject_id, payload,
       amount_minor, config_versions, requested_by, state, expires_at, command_idempotency_key)
    VALUES ('config.set_money_key', 'platform_admin', 'config_key', gen_random_uuid(),
            '{}', NULL, '{}', tap.seller(), 'approved', now() + interval '1 day', 'g2')$$,
  '23514', NULL, '077 G2 [T-SCHEMA-APPR-02]: approved with approved_by NULL raises — SoD is not vacuously satisfiable');
SELECT throws_ok(
  $$INSERT INTO kernel.approval_request
      (action, required_approver_class, subject_kind, subject_id, org_id, payload,
       amount_minor, config_versions, requested_by, expires_at, command_idempotency_key)
    VALUES ('refund.issue', 'org', 'config_key', gen_random_uuid(), gen_random_uuid(),
            '{}', 100, '{}', tap.seller(), now() + interval '1 day', 'g3')$$,
  '23514', NULL, '077 G3 [T-SCHEMA-APPR-05]: an action/subject_kind pair outside the three legal combinations raises');
SELECT throws_ok(
  $$INSERT INTO kernel.approval_request
      (action, required_approver_class, subject_kind, subject_id, payload,
       amount_minor, config_versions, requested_by, approved_by, state, expires_at, command_idempotency_key)
    VALUES ('config.set_money_key', 'platform_admin', 'config_key', gen_random_uuid(),
            '{}', NULL, '{}', tap.seller(), tap.seller(), 'approved', now() + interval '1 day', 'g4')$$,
  '23514', NULL, '077 G4 [SoD]: approved_by = requested_by raises');
SELECT throws_ok(
  $$INSERT INTO kernel.approval_request
      (action, required_approver_class, subject_kind, subject_id, org_id, payload,
       amount_minor, config_versions, requested_by, expires_at, command_idempotency_key)
    VALUES ('refund.issue', 'org', 'order', gen_random_uuid(), gen_random_uuid(),
            '{}', NULL, '{}', tap.seller(), now() + interval '1 day', 'g5')$$,
  '23514', NULL, '077 G5 [T-SCHEMA-APPR-08]: a refund.issue row with NULL amount_minor raises (silent-zero defect)');
SELECT throws_ok(
  $$INSERT INTO kernel.approval_request
      (action, required_approver_class, subject_kind, subject_id, org_id, payload,
       amount_minor, config_versions, requested_by, expires_at, command_idempotency_key)
    VALUES ('refund.issue', 'org', 'order', gen_random_uuid(), gen_random_uuid(),
            '{}', -5, '{}', tap.seller(), now() + interval '1 day', 'g6')$$,
  '23514', NULL, '077 G6 [T-SCHEMA-APPR-08]: a non-positive amount_minor raises (negative-headroom defect)');
-- C16: same (requested_by, command key) rejects a replay at the index
SELECT lives_ok(
  $$INSERT INTO kernel.approval_request
      (action, required_approver_class, subject_kind, subject_id, payload,
       amount_minor, config_versions, requested_by, expires_at, command_idempotency_key)
    VALUES ('config.set_money_key', 'platform_admin', 'config_key', gen_random_uuid(),
            '{}', NULL, '{}', tap.seller(), now() + interval '1 day', 'c16')$$,
  '077 G7a: a well-formed request row inserts');
SELECT throws_ok(
  $$INSERT INTO kernel.approval_request
      (action, required_approver_class, subject_kind, subject_id, payload,
       amount_minor, config_versions, requested_by, expires_at, command_idempotency_key)
    VALUES ('config.set_money_key', 'platform_admin', 'config_key', gen_random_uuid(),
            '{}', NULL, '{}', tap.seller(), now() + interval '1 day', 'c16')$$,
  '23505', NULL, '077 G7b [C16]: the (requested_by, command_idempotency_key) unique rejects a replay');

-- ── H. APPEND-ONLY GUARDS (schema §0.8; the three AO tables) ───────────────

INSERT INTO kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
VALUES (tap.seller(), 'test.seed', 'identity', tap.seller(), 'fixture');
SELECT throws_ok($$UPDATE kernel.admin_audit SET reason_code = 'tamper'$$,
  'P0001', NULL, '077 H1: admin_audit UPDATE raises (append-only guard)');
SELECT throws_ok($$DELETE FROM kernel.admin_audit$$,
  'P0001', NULL, '077 H2: admin_audit DELETE raises');
INSERT INTO kernel.identity_demographic_erasure (identity_id, erased_at) VALUES (tap.seller(), now());
SELECT throws_ok($$UPDATE kernel.identity_demographic_erasure SET erased_at = now()$$,
  'P0001', NULL, '077 H3: erasure tombstone UPDATE raises');
SELECT throws_ok($$DELETE FROM kernel.identity_demographic_erasure$$,
  'P0001', NULL, '077 H4: erasure tombstone DELETE raises (the OR-16 reaper class is NOT implemented — nothing may delete)');
INSERT INTO kernel.identity_contact_pref_event (identity_id, venue_email_contact) VALUES (tap.seller(), 'allow');
SELECT throws_ok($$UPDATE kernel.identity_contact_pref_event SET venue_email_contact = 'block'$$,
  'P0001', NULL, '077 H5: pref event log UPDATE raises');
SELECT throws_ok($$DELETE FROM kernel.identity_contact_pref_event$$,
  'P0001', NULL, '077 H6: pref event log DELETE raises');

-- ── I. DEMOGRAPHICS (DEMOG §10.4, §8, §13 assertions 25/29/30) ─────────────

SELECT tap.login(tap.buyer());
SELECT is((kernel.set_my_demographics('woman', 'v1'))->>'status', 'ok',
  '077 I1: set_my_demographics accepts a valid answer');
SELECT results_eq(
  $$SELECT gender_identity FROM kernel.get_my_demographics()$$,
  $$VALUES ('woman'::text)$$,
  '077 I2: get_my_demographics returns own row (and only a parameterless read exists)');
SELECT throws_ok($$SELECT kernel.set_my_demographics('female', 'v1')$$,
  'P0001', NULL, '077 I3: a label outside the five-value CHECK set is refused in-body');
SELECT is((kernel.clear_my_demographics())->>'status', 'ok',
  '077 I4 [MD-9]: clear_my_demographics hard-deletes own row inside the definer');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.identity_demographic WHERE identity_id = tap.buyer()),
  0, '077 I5: the demographic row is gone — not tombstoned in place');
SELECT tap.login(tap.buyer());
SELECT is((kernel.clear_my_demographics())->>'status', 'noop_replay',
  '077 I6: clearing with no row present is noop_replay, not an error');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM kernel.identity_demographic_erasure WHERE identity_id = tap.buyer()),
  1, '077 I7 [§8.5]: the BEFORE DELETE trigger appended exactly one value-free tombstone');
SELECT is(
  (SELECT purge_after IS NULL FROM kernel.identity_demographic_erasure WHERE identity_id = tap.buyer()),
  true, '077 I8 [OR-16/F-8]: purge_after is NULL when retention.backup_window_days is absent — never-purgeable failsafe');
-- DEMOG 29: clear -> re-answer -> clear yields TWO tombstones (append-many)
SELECT tap.login(tap.buyer());
SELECT is((kernel.set_my_demographics('man', 'v1'))->>'status', 'ok', '077 I9a: re-answer after clear');
SELECT is((kernel.clear_my_demographics())->>'status', 'ok', '077 I9b: second clear');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM kernel.identity_demographic_erasure WHERE identity_id = tap.buyer()),
  2, '077 I9 [DEMOG 29]: two erasures leave TWO tombstone rows — append-many, never an upsert');
-- DEMOG 25 (structural): the trigger body references no gender column
SELECT ok(
  (SELECT pg_get_functiondef(k.oid) NOT ILIKE '%gender%'
     FROM (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.proname = 'write_demographic_erasure_tombstone'
            OFFSET 0) k),
  '077 I10 [DEMOG 25]: the tombstone writer references no gender column — value-free by construction');
-- reader-enumeration (077-visible slice): exactly the three RPCs + the trigger
SELECT is(
  (SELECT string_agg(k.proname, ',' ORDER BY k.proname COLLATE "C")
     FROM (SELECT p.oid, p.proname FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.prokind = 'f' OFFSET 0) k
    WHERE pg_get_functiondef(k.oid) ~ 'kernel\.identity_demographic(?!_)'),
  'clear_my_demographics,get_my_demographics,set_my_demographics',
  '077 I11 [T-RPC-DEMO-01]: exactly the three own-row RPCs reach identity_demographic (the tombstone writer touches only the erasure table)');
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'get_my_demographics' AND p.pronargs = 0),
  1, '077 I12 [§10.4]: get_my_demographics has arity 0 — reading someone else''s row is unexpressible');

-- ── J. CONTACT PREFERENCES (§17.21; GATE-DEFAULT-1; AUTHZ-CRM1) ────────────

SELECT tap.login(tap.other_user());
SELECT results_eq(
  $$SELECT venue_email_contact FROM kernel.get_my_contact_prefs()$$,
  $$VALUES ('allow'::text)$$,
  '077 J1 [GATE-DEFAULT-1/T-SCHEMA-CRM-04]: no row resolves to allow — a kill switch, not a consent');
SELECT is((kernel.set_my_contact_prefs('block'))->>'status', 'ok',
  '077 J2: the master switch flips');
SELECT tap.logout();
SELECT is(
  (SELECT string_agg(venue_email_contact, ',') FROM kernel.identity_contact_pref_event
    WHERE identity_id = tap.other_user()),
  'block', '077 J3 [AUTHZ-CRM1/T-SCHEMA-CRM-03]: the flip appended exactly one event row carrying the resulting value');
SELECT tap.login(tap.other_user());
SELECT is((kernel.set_my_contact_prefs('block'))->>'status', 'noop_replay',
  '077 J4: setting the value it already holds is a no-op');
SELECT throws_ok($$SELECT kernel.set_my_contact_prefs('maybe')$$,
  'P0001', NULL, '077 J6: a value outside the two-label set is refused in-body');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM kernel.identity_contact_pref_event WHERE identity_id = tap.other_user()),
  1, '077 J5 [§17.21]: a no-op appends NO event — the log records decisions, not retries');
SELECT is(
  (SELECT count(*)::int FROM kernel.admin_audit
    WHERE action = 'crm_contact.pref_changed' AND actor_identity = tap.other_user()),
  1, '077 J7 [§17.21]: the effective change is audited (crm_contact.pref_changed)');

-- ── K. ORG LIFECYCLE (RPC §2; F-6; AUTHZ-C1B; OR-18) ───────────────────────

SELECT tap.login(tap.admin_user());
SELECT lives_ok($$SELECT tap._store('org1', (kernel.create_organization('Fixture Org LLC','Fixture Org','ck1'))->>'org_id')$$,
  '077 K1: create_organization succeeds for an ACTIVE caller');
SELECT is(
  (SELECT role FROM kernel.org_member
    WHERE org_id = tap._fetch('org1')::uuid AND identity_id = tap.admin_user()),
  'org_owner', '077 K2: the creator becomes the first org_owner');
SELECT is(
  (SELECT status FROM kernel.organization WHERE org_id = tap._fetch('org1')::uuid),
  'applied', '077 K3: a new org is born applied — platform approval is a separate act');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM kernel.admin_audit
    WHERE action = 'org.create' AND subject_id = tap._fetch('org1')::uuid),
  1, '077 K4 [§0.3]: the privileged mutation wrote its audit row in-txn');
SELECT tap.login(tap.admin_user());
-- invite at org_marketing — the M-5 pair is storable end-to-end
SELECT lives_ok($$SELECT tap._store('inv_mkt', (kernel.invite_org_member(tap._fetch('org1')::uuid,
  '55555555-5555-5555-5555-555555555555', 'org_marketing', 'ck2'))->>'invite_id')$$,
  '077 K5 [M-5]: an org_marketing invite is storable (the pre-fix 077 raised 23514 here)');
SELECT tap.login('55555555-5555-5555-5555-555555555555'::uuid);
SELECT is((kernel.accept_org_invite(tap._fetch('inv_mkt')::uuid, 'ck3'))->>'status', 'ok',
  '077 K6: the addressed invitee accepts');
SELECT tap.login(tap.admin_user());
-- promote 55 into org_admin, then test the tier guard from 55's side
SELECT is((kernel.change_org_role(tap._fetch('org1')::uuid,
  '55555555-5555-5555-5555-555555555555', 'org_admin', 'ck4'))->>'status', 'ok',
  '077 K7: an org_owner can change a member''s role');
SELECT tap.login('55555555-5555-5555-5555-555555555555'::uuid);
SELECT throws_ok(
  $$SELECT kernel.invite_org_member(tap._fetch('org1')::uuid, '66666666-6666-6666-6666-666666666666', 'org_owner', 'ck5')$$,
  'P0001', NULL, '077 K8 [§2.2 tier]: an org_admin cannot invite at org_owner');
SELECT throws_ok(
  $$SELECT kernel.change_org_role(tap._fetch('org1')::uuid, '55555555-5555-5555-5555-555555555555', 'org_owner', 'ck6')$$,
  'P0001', NULL, '077 K9 [§2.4]: an org_admin cannot grant org_owner (and self-promotion is refused)');
SELECT tap.login(tap.admin_user());
-- last-owner invariant
SELECT throws_ok(
  $$SELECT kernel.change_org_role(tap._fetch('org1')::uuid, tap.admin_user(), 'org_member', 'ck7')$$,
  'P0001', NULL, '077 K10 [>=1 owner]: demoting the last org_owner is refused');
SELECT throws_ok(
  $$SELECT kernel.remove_org_member(tap._fetch('org1')::uuid, tap.admin_user(), 'ck8')$$,
  'P0001', NULL, '077 K11 [>=1 owner]: removing the last org_owner is refused');
-- AUTHZ-C1B: the maturity clock resets on promotion INTO a money role only
SELECT tap.logout();
UPDATE kernel.org_member SET granted_at = now() - interval '10 days'
 WHERE org_id = tap._fetch('org1')::uuid AND identity_id = '55555555-5555-5555-5555-555555555555';
SELECT tap.login(tap.admin_user());
SELECT is((kernel.change_org_role(tap._fetch('org1')::uuid,
  '55555555-5555-5555-5555-555555555555', 'org_finance', 'ck9'))->>'status', 'ok',
  '077 K12a: promotion into a money role succeeds');
SELECT tap.logout();
SELECT is(
  (SELECT granted_at = now() FROM kernel.org_member
    WHERE org_id = tap._fetch('org1')::uuid AND identity_id = '55555555-5555-5555-5555-555555555555'),
  true, '077 K12 [T-SCHEMA-APPR-07/X-11]: granted_at ADVANCES on promotion into a money role');
UPDATE kernel.org_member SET granted_at = now() - interval '10 days'
 WHERE org_id = tap._fetch('org1')::uuid AND identity_id = '55555555-5555-5555-5555-555555555555';
SELECT tap.login(tap.admin_user());
SELECT is((kernel.change_org_role(tap._fetch('org1')::uuid,
  '55555555-5555-5555-5555-555555555555', 'org_member', 'ck10'))->>'status', 'ok',
  '077 K13a: demotion out of the money role succeeds');
SELECT tap.logout();
SELECT is(
  (SELECT granted_at < now() - interval '9 days' FROM kernel.org_member
    WHERE org_id = tap._fetch('org1')::uuid AND identity_id = '55555555-5555-5555-5555-555555555555'),
  true, '077 K13 [AUTHZ-C1B]: a demotion does NOT reset the clock — nothing is being acquired');
SELECT tap.login(tap.admin_user());
-- revoke_org_invite releases the pending partial unique (T-RPC-ORG-04)
SELECT lives_ok($$SELECT tap._store('inv_g', (kernel.invite_org_member(tap._fetch('org1')::uuid,
  'grace@test.local', 'org_member', 'ck11'))->>'invite_id')$$, '077 K14a: invite by email ref');
SELECT throws_ok(
  $$SELECT kernel.invite_org_member(tap._fetch('org1')::uuid, 'grace@test.local', 'org_member', 'ck12')$$,
  'P0001', NULL, '077 K14b [§1.3b]: a second open invite for the same invitee_ref is refused (partial unique)');
SELECT is((kernel.revoke_org_invite(tap._fetch('inv_g')::uuid, 'ck13'))->>'status', 'ok',
  '077 K14c: the inviter tier revokes the pending invite');
SELECT lives_ok(
  $$SELECT kernel.invite_org_member(tap._fetch('org1')::uuid, 'grace@test.local', 'org_member', 'ck14')$$,
  '077 K14 [T-RPC-ORG-04]: after revoke the same invitee_ref can be re-invited — the release is the load-bearing half');
-- accept of a revoked invite writes no roster row (T-RPC-ORG-05 half)
SELECT tap.login('77777777-7777-7777-7777-777777777777'::uuid);
SELECT throws_ok(
  $$SELECT kernel.accept_org_invite(tap._fetch('inv_g')::uuid, 'ck15')$$,
  'P0001', NULL, '077 K15a: accepting a revoked invite raises');
SELECT is(
  (SELECT count(*)::int FROM kernel.org_member
    WHERE org_id = tap._fetch('org1')::uuid AND identity_id = '77777777-7777-7777-7777-777777777777'),
  0, '077 K15 [T-RPC-ORG-05]: no kernel.org_member row was written — asserted on the roster, not the error');
-- sweep_expired_org_invites (T-RPC-ORG-06): tick disabled -> accept refuses on
-- the arithmetic; the tick releases the partial unique
SELECT tap.logout();
UPDATE kernel.org_invite SET expires_at = now() - interval '1 hour', created_at = now() - interval '2 hours'
 WHERE org_id = tap._fetch('org1')::uuid AND invitee_ref = 'grace@test.local' AND status = 'pending';
SELECT tap.login('77777777-7777-7777-7777-777777777777'::uuid);
SELECT throws_ok(
  $$SELECT kernel.accept_org_invite((SELECT invite_id FROM kernel.org_invite
      WHERE invitee_ref = 'grace@test.local' AND status = 'pending'), 'ck16')$$,
  'P0001', NULL, '077 K16a [T-RPC-ORG-06]: with the tick disabled, accepting a past-expires_at pending invite raises');
SELECT tap.logout();
SELECT is((kernel.sweep_expired_org_invites())->>'swept', '1',
  '077 K16b: one tick flips the lapsed invite to expired');
SELECT tap.login(tap.admin_user());
SELECT lives_ok(
  $$SELECT kernel.invite_org_member(tap._fetch('org1')::uuid, 'grace@test.local', 'org_member', 'ck17')$$,
  '077 K16 [T-RPC-ORG-06]: after the tick the same invitee_ref can be re-invited — the unique-release half');
SELECT tap.logout();

-- ── L. CONNECT ONBOARDING (§20.1.1, T-RPC-CONNECT-01..04) ──────────────────

SELECT tap.login(tap.admin_user());
SELECT is((kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl1'))->>'newly_bound', 'true',
  '077 L1 [T-RPC-CONNECT-01]: the first bind succeeds');
SELECT tap.logout();
SELECT is(
  (SELECT payout_destination_set_by FROM kernel.organization WHERE org_id = tap._fetch('org1')::uuid),
  tap.admin_user(), '077 L2 [T-RPC-CONNECT-01/SoD-1]: the bind stamps payout_destination_set_by');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl2'))->>'status', 'noop_replay',
  '077 L3 [T-RPC-CONNECT-03]: re-binding the same id is noop_replay (the re-onboarding retry path)');
SELECT throws_like(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_OTHER999', 'cl3')$$,
  '%destination_already_set%',
  '077 L4 [T-RPC-CONNECT-02]: an org_owner/org_finance re-point of a non-NULL ref raises — §17.7''s control set defended at the second door');
SELECT tap.logout();
SELECT throws_ok(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_NOJWT', 'cl4')$$,
  '42501', NULL, '077 L5 [T-RPC-CONNECT-04]: on a claims-less (service-path) connection auth.uid() is NULL and the function RAISES rather than binding');

-- ── M. IDENTITY_EXT WRITERS (§20.1.3, T-RPC-ORG-02) ────────────────────────

SELECT tap.login(tap.buyer());
SELECT is((kernel.upsert_identity_ext('{"locale":"en-US"}'::jsonb, 'cm1'))->>'status', 'ok',
  '077 M1: the self branch writes locale on its own (lazily created) row');
SELECT throws_like(
  $$SELECT kernel.upsert_identity_ext('{"kyc_ref":"sneak"}'::jsonb, 'cm2')$$,
  '%unwritable_key%', '077 M2 [§20.1.3]: region/kyc through the self branch raises — never silently ignored');
SELECT throws_like(
  $$SELECT kernel.upsert_identity_ext('{"locale":"not a locale!!"}'::jsonb, 'cm3')$$,
  '%bad_locale%', '077 M3: a malformed BCP-47 tag is refused');
SELECT throws_ok(
  $$SELECT kernel.admin_set_identity_ext(tap.seller(), '{"residency_region":"us-east"}'::jsonb, 'r', 'cm4')$$,
  '42501', NULL, '077 M4 [T-RPC-ORG-02]: a non-platform caller is refused on the platform branch');
SELECT tap.logout();
-- the self-branch signature carries no uuid parameter (structural)
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'upsert_identity_ext'
      AND 'uuid'::regtype::oid = ANY (p.proargtypes::oid[])),
  0, '077 M5 [T-RPC-ORG-02]: upsert_identity_ext has NO uuid parameter — editing another row is unexpressible');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.admin_set_identity_ext(tap.buyer(), '{"kyc_ref":"kyc-handle-1"}'::jsonb, 'kyc_review', 'cm5'))->>'status', 'ok',
  '077 M6: the platform branch (platform_admin via bootstrap) writes kyc_ref');
SELECT tap.logout();
SELECT is(
  (SELECT (a.before::text || a.after::text) NOT LIKE '%kyc-handle-1%'
     FROM kernel.admin_audit a
    WHERE a.action = 'identity_ext.update' AND a.subject_id = tap.buyer()
    ORDER BY a.occurred_at DESC LIMIT 1),
  true, '077 M7 [T-RPC-ORG-02]: the kyc audit row records THAT it changed, never its value');

-- ── N. PLATFORM ROLES (§20.1.4; PFA-4 posture) ─────────────────────────────

SELECT tap.login(tap.admin_user());
SELECT throws_ok(
  $$SELECT kernel.grant_platform_role(tap.buyer(), 'venue_manager', 'r', 'cn1')$$,
  'P0001', NULL, '077 N1 [T-RPC-ROLE-09]: a venue_*/org_* label passed as p_role raises — disjoint enums (C36)');
SELECT throws_like(
  $$SELECT kernel.grant_platform_role(tap.admin_user(), 'platform_admin', 'r', 'cn2')$$,
  '%self_grant%', '077 N2 [I-11]: a self-grant raises before anything else can happen');
SELECT throws_like(
  $$SELECT kernel.grant_platform_role(tap.buyer(), 'platform_support', 'r', 'cn3')$$,
  '%PFA-4%', '077 N3 [PFA-4]: the grant arm FAILS CLOSED naming the unsigned amendment');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM kernel.platform_role),
  0, '077 N4 [T-RPC-ROLE-06]: no platform_role row exists after grant attempts — nothing minted platform authority');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.revoke_platform_role(tap.buyer(), 'platform_support', 'cleanup', 'cn4'))->>'status', 'noop_replay',
  '077 N5: revoking an absent grant is noop_replay (revocation is terminal-idempotent)');
-- direct-seed a row (as postgres) to exercise the revoke arm + last-admin guard
SELECT tap.logout();
INSERT INTO kernel.platform_role (identity_id, role, granted_by)
VALUES (tap.seller(), 'platform_risk', tap.admin_user());
SELECT tap.login(tap.admin_user());
SELECT is((kernel.revoke_platform_role(tap.seller(), 'platform_risk', 'offboard', 'cn5'))->>'status', 'ok',
  '077 N6 [§20.1.4]: revocation executes directly — only a grant needs the second approver');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'platform_role.revoke'),
  1, '077 N7: the revoke wrote its audit row (GP-2: the audit row carries the removed grant)');
SELECT tap.logout();
INSERT INTO kernel.platform_role (identity_id, role, granted_by)
VALUES (tap.admin_user(), 'platform_admin', tap.admin_user());
SELECT tap.login(tap.admin_user());
SELECT throws_like(
  $$SELECT kernel.revoke_platform_role(tap.admin_user(), 'platform_admin', 'r', 'cn6')$$,
  '%last_platform_admin%',
  '077 N8 [T-RPC-ROLE-08]: revoking the last platform_admin raises, counting public.admin_users in the total');
SELECT tap.logout();
DELETE FROM kernel.platform_role WHERE identity_id = tap.admin_user();

-- ── O. THE DELETION MACHINE (§20.17; dsm OR-13; T-RPC-DEL-01..05) ──────────

-- O-a: request accepts, records, emits (T-RPC-DEL-01 + R2 row 31)
SELECT tap.login('66666666-6666-6666-6666-666666666666'::uuid);
SELECT is((kernel.request_account_deletion('co1'))->>'status', 'ok',
  '077 O1 [T-RPC-DEL-01]: the request ALWAYS accepts — no request-time refusal exists');
SELECT is(
  (SELECT deletion_state FROM kernel.identity_ext WHERE identity_id = '66666666-6666-6666-6666-666666666666'),
  'DELETION_PENDING', '077 O2: ACTIVE -> DELETION_PENDING (lazy identity_ext create)');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM notify.outbox
    WHERE event_type = 'account_deletion_pending'
      AND aggregate_id = '66666666-6666-6666-6666-666666666666'),
  1, '077 O3 [R2 row 31]: the pending notice envelope is in the 076 outbox (BEST-EFFORT emit)');
SELECT tap.login('66666666-6666-6666-6666-666666666666'::uuid);
SELECT is((kernel.request_account_deletion('co2'))->>'status', 'noop_replay',
  '077 O4 [T-RPC-DEL-01]: re-request while pending is noop_replay — the timestamp is NOT rewritten');
SELECT is((kernel.withdraw_account_deletion('co3'))->>'status', 'ok',
  '077 O5 [T-RPC-DEL-03]: DELETION_PENDING -> ACTIVE');
SELECT is(
  (SELECT deletion_requested_at IS NULL AND deletion_block_reason IS NULL
     FROM kernel.identity_ext WHERE identity_id = '66666666-6666-6666-6666-666666666666'),
  true, '077 O6: withdrawal clears deletion_requested_at and deletion_block_reason');
SELECT is((kernel.withdraw_account_deletion('co4'))->>'status', 'noop_replay',
  '077 O7: withdraw while ACTIVE is noop_replay');
-- O-b: Q5 auto-expiry (T-RPC-DEL-02) — pending expires, decided is immutable
SELECT tap.logout();
INSERT INTO kernel.approval_request
  (action, required_approver_class, subject_kind, subject_id, org_id, payload,
   amount_minor, config_versions, requested_by, approved_by, state, expires_at, command_idempotency_key)
VALUES
  ('refund.issue', 'org', 'order', gen_random_uuid(), tap._fetch('org1')::uuid, '{}',
   500, '{}', '66666666-6666-6666-6666-666666666666', NULL, 'pending', now() + interval '1 day', 'q5a'),
  ('refund.issue', 'org', 'order', gen_random_uuid(), tap._fetch('org1')::uuid, '{}',
   700, '{}', '66666666-6666-6666-6666-666666666666', tap.admin_user(), 'approved', now() + interval '1 day', 'q5b');
SELECT tap.login('66666666-6666-6666-6666-666666666666'::uuid);
SELECT is((kernel.request_account_deletion('co5'))->>'status', 'ok', '077 O8a: re-entry after withdrawal accepts again');
SELECT tap.logout();
SELECT is(
  (SELECT state FROM kernel.approval_request WHERE command_idempotency_key = 'q5a'),
  'expired', '077 O9 [T-RPC-DEL-02/Q5]: the pending approval naming the deleter flips to expired at entry');
SELECT is(
  (SELECT state FROM kernel.approval_request WHERE command_idempotency_key = 'q5b'),
  'approved', '077 O10 [T-RPC-DEL-02/Q5]: decided rows are immutable — approved is untouched');
SELECT is(
  (SELECT count(*)::int FROM notify.outbox
    WHERE event_type = 'account_deletion_pending'
      AND aggregate_id = '66666666-6666-6666-6666-666666666666'),
  1, '077 O11a [Group D dedupe]: a same-instant re-entry collapses into ONE envelope (the txn-stable timestamp key meets UNIQUE(event_type, event_key))');
SELECT lives_ok(
  $$SELECT notify.emit_event('account_deletion_pending', 'identity',
      '66666666-6666-6666-6666-666666666666',
      'account_deletion_pending:66666666-6666-6666-6666-666666666666:LATER-INSTANT', '{}'::jsonb)$$,
  '077 O11b: a later-instant entry carries a different timestamp in the key');
SELECT is(
  (SELECT count(*)::int FROM notify.outbox
    WHERE event_type = 'account_deletion_pending'
      AND aggregate_id = '66666666-6666-6666-6666-666666666666'),
  2, '077 O11 [Group D dedupe]: re-request after withdrawal re-notifies — the timestamp in the dedupe key is rewritten at each ENTRY');

-- O-c: the sweep — blockers in order, legible reasons, terminal entry
-- BP-11 via a real sole ownership (66 creates nothing; give it one)
SELECT tap.login('66666666-6666-6666-6666-666666666666'::uuid);
SELECT is((kernel.withdraw_account_deletion('co6'))->>'status', 'ok', '077 O12a: withdraw to build the org fixture');
SELECT lives_ok($$SELECT tap._store('org2', (kernel.create_organization('Solo LLC','Solo','co7'))->>'org_id')$$,
  '077 O12b: the fixture org (66 is sole owner)');
SELECT is((kernel.request_account_deletion('co8'))->>'status', 'ok', '077 O12c: request again');
SELECT tap.logout();
SELECT is(((kernel.sweep_deletion_pending())->>'tombstoned'), '0',
  '077 O12 [T-RPC-DEL-04]: the sweep tombstones NOTHING while a predicate holds');
SELECT is(
  (SELECT deletion_block_reason LIKE 'BP-11%' FROM kernel.identity_ext
    WHERE identity_id = '66666666-6666-6666-6666-666666666666'),
  true, '077 O13 [BP-11/16d]: the sole-org_owner blocker is recorded, operator-legible, with the org named');
SELECT is(
  (SELECT state FROM kernel.approval_request WHERE command_idempotency_key = 'q5a'),
  'expired', '077 O13b [§3.1.2/red-team A]: the interposed withdrawal did NOT resurrect the Q5-expired approval — expiry is a release, not a suspension');
-- clear BP-11 by transferring ownership (the ruled clearing path)
SELECT tap.login('66666666-6666-6666-6666-666666666666'::uuid);
SELECT lives_ok($$SELECT tap._store('inv_own', (kernel.invite_org_member(tap._fetch('org2')::uuid,
  '77777777-7777-7777-7777-777777777777', 'org_owner', 'co9'))->>'invite_id')$$,
  '077 O14a: invite a successor owner');
SELECT tap.login('77777777-7777-7777-7777-777777777777'::uuid);
SELECT is((kernel.accept_org_invite(tap._fetch('inv_own')::uuid, 'co10'))->>'status', 'ok',
  '077 O14b: the successor accepts (a DELETION_PENDING inviter does not freeze the ACTIVE acceptor)');
-- leave a pending invite AUTHORED BY 66 to prove the terminal invite clear
SELECT tap.login('66666666-6666-6666-6666-666666666666'::uuid);
SELECT lives_ok($$SELECT kernel.invite_org_member(tap._fetch('org2')::uuid, 'edith@test.local', 'org_member', 'co11')$$,
  '077 O14c: a pending invite authored by the deleter (terminal-clear fixture)');
SELECT tap.logout();
SELECT is(((kernel.sweep_deletion_pending())->>'tombstoned'), '1',
  '077 O15 [T-RPC-DEL-04]: with every predicate false the sweep executes terminal entry');
SELECT is(
  (SELECT deletion_state FROM kernel.identity_ext WHERE identity_id = '66666666-6666-6666-6666-666666666666'),
  'ERASED', '077 O16 [PFA-3/OPEN-3]: the terminal marker is deletion_state = ERASED on kernel.identity_ext');
SELECT is(
  (SELECT deletion_requested_at IS NOT NULL AND deletion_block_reason IS NULL
     FROM kernel.identity_ext WHERE identity_id = '66666666-6666-6666-6666-666666666666'),
  true, '077 O17 [dsm §4.1]: deletion_requested_at is RETAINED at terminal — the durable record that the person asked');
SELECT is(
  (SELECT count(*)::int FROM kernel.org_member WHERE identity_id = '66666666-6666-6666-6666-666666666666'),
  0, '077 O18 [dsm §4.5]: the 077-plane role grants are cleared at terminal');
SELECT is(
  (SELECT count(*)::int FROM kernel.org_invite
    WHERE invited_by = '66666666-6666-6666-6666-666666666666' AND status = 'pending'),
  0, '077 O19 [dsm §4.5/INV #6]: the deleter''s pending invites are cleared (revoked) at terminal');
SELECT is(
  (SELECT count(*)::int FROM notify.outbox
    WHERE event_type = 'account_deletion_completed'
      AND event_key = 'account_deletion_completed:66666666-6666-6666-6666-666666666666'),
  1, '077 O20 [R2 row 32]: the completion notice envelope is emitted with the once-ever dedupe key');
SELECT is(((kernel.sweep_deletion_pending())->>'swept'), '0',
  '077 O21 [idempotent terminal]: a second pass finds nothing pending — terminal entry is once');
-- ERASED is terminal (no resurrection, no re-request)
SELECT tap.login('66666666-6666-6666-6666-666666666666'::uuid);
SELECT throws_like($$SELECT kernel.request_account_deletion('co12')$$, '%erased%',
  '077 O22 [E-8]: a request against an ERASED identity fails closed');
SELECT throws_like($$SELECT kernel.withdraw_account_deletion('co13')$$, '%erased%',
  '077 O23 [dsm §1.3]: ERASED never returns to ACTIVE — no resurrection path exists');
SELECT throws_like($$SELECT kernel.create_organization('Ghost LLC', 'Ghost', 'co13b')$$, '%erased%',
  '077 O23b [dsm §1.3/red-team C]: an ERASED session cannot create an organization — acquisition refuses');
SELECT throws_like($$SELECT kernel.accept_org_invite(gen_random_uuid(), 'co13c')$$, '%erased%',
  '077 O23c [dsm §1.3/red-team C]: an ERASED session cannot accept an invite (refusal precedes not_found)');
SELECT tap.logout();

-- O-d: the live-rail blocker arms (BP-6/7/8/9) with real public.* fixtures
SELECT tap.login(tap.buyer());
SELECT is((kernel.request_account_deletion('co14'))->>'status', 'ok', '077 O24a: buyer requests deletion');
SELECT tap.logout();
SELECT lives_ok($$SELECT kernel.sweep_deletion_pending()$$, '077 O24b: sweep runs over the live fixtures');
SELECT is(
  (SELECT deletion_block_reason LIKE 'BP-7%' FROM kernel.identity_ext WHERE identity_id = tap.buyer()),
  true, '077 O24 [BP-7 live]: the seed pending transfer blocks the buyer — first-true-in-order wins');
SELECT set_config('app.bypass_transfer_guard', 'on', true), set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.transfers SET payout_review_status = 'held' WHERE id = tap.transfer_a();
SELECT tap.reset_guards();
SELECT lives_ok($$SELECT kernel.sweep_deletion_pending()$$, '077 O25a: sweep re-evaluates every pass');
SELECT tap.login(tap.seller());
SELECT is((kernel.request_account_deletion('co15'))->>'status', 'ok', '077 O25b: seller requests too');
SELECT tap.logout();
SELECT lives_ok($$SELECT kernel.sweep_deletion_pending()$$, '077 O25c: sweep sees the held transfer');
SELECT is(
  (SELECT deletion_block_reason LIKE 'BP-6%' FROM kernel.identity_ext WHERE identity_id = tap.seller()),
  true, '077 O25 [BP-6 live]: an unresolved payout hold blocks the seller BEFORE BP-7 (order held)');
SELECT set_config('app.bypass_transfer_guard', 'on', true), set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET reserved_by = '77777777-7777-7777-7777-777777777777' WHERE id = tap.listing_d();
SELECT tap.reset_guards();
SELECT tap.login('77777777-7777-7777-7777-777777777777'::uuid);
SELECT is((kernel.request_account_deletion('co16'))->>'status', 'ok', '077 O26a: reserver requests');
SELECT tap.logout();
SELECT lives_ok($$SELECT kernel.sweep_deletion_pending()$$, '077 O26b: sweep');
SELECT is(
  (SELECT deletion_block_reason LIKE 'BP-8%' FROM kernel.identity_ext
    WHERE identity_id = '77777777-7777-7777-7777-777777777777'),
  true, '077 O26 [BP-8 live]: an in-flight buy-now reservation blocks');
SELECT set_config('app.bypass_transfer_guard', 'on', true), set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET reserved_by = NULL WHERE id = tap.listing_d();
UPDATE public.listings SET winner_user_id = '77777777-7777-7777-7777-777777777777' WHERE id = tap.listing_c();
SELECT tap.reset_guards();
SELECT lives_ok($$SELECT kernel.sweep_deletion_pending()$$, '077 O27a: sweep');
SELECT is(
  (SELECT deletion_block_reason LIKE 'BP-9%' FROM kernel.identity_ext
    WHERE identity_id = '77777777-7777-7777-7777-777777777777'),
  true, '077 O27 [BP-9 live]: a won-unsettled auction blocks (no silent discard of the win)');
SELECT set_config('app.bypass_transfer_guard', 'on', true), set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET winner_user_id = NULL WHERE id = tap.listing_c();
SELECT tap.reset_guards();
SELECT tap.login('77777777-7777-7777-7777-777777777777'::uuid);
SELECT is((kernel.withdraw_account_deletion('co17'))->>'status', 'ok', '077 O28: withdrawal mid-machine restores ACTIVE');
SELECT tap.logout();

-- O-e: T-RPC-NOTIFY-10 — an injected emit failure never aborts the transition
ALTER FUNCTION notify.emit_event(text, text, uuid, text, jsonb, uuid, uuid)
  RENAME TO emit_event_disabled_for_test;
SELECT tap.login('55555555-5555-5555-5555-555555555555'::uuid);
SELECT is((kernel.request_account_deletion('co18'))->>'status', 'ok',
  '077 O29 [T-RPC-NOTIFY-10]: with the emitter broken (42883 inside the wrap) the request STILL accepts');
SELECT is(
  (SELECT deletion_state FROM kernel.identity_ext
    WHERE identity_id = '55555555-5555-5555-5555-555555555555'),
  'DELETION_PENDING', '077 O30 [OR-14/BE]: the state write committed — the notice is best-effort, the machine is not');
SELECT tap.logout();
ALTER FUNCTION notify.emit_event_disabled_for_test(text, text, uuid, text, jsonb, uuid, uuid)
  RENAME TO emit_event;
SELECT tap.login('55555555-5555-5555-5555-555555555555'::uuid);
SELECT is((kernel.withdraw_account_deletion('co19'))->>'status', 'ok', '077 O31: cleanup withdraw');
SELECT tap.logout();

-- ── P. SECURITY ROLE-CHANGE EMITS (R2 row 22 — change_org_role only) ───────
-- delta-based: the K-section role changes already emitted (proving the
-- producer); these assert exactly one more per sensitive change.

SELECT tap._store('g_pre', (SELECT count(*)::text FROM notify.outbox
  WHERE event_type = 'security_org_role_granted'
    AND aggregate_id = '55555555-5555-5555-5555-555555555555'));
SELECT tap._store('r_pre', (SELECT count(*)::text FROM notify.outbox
  WHERE event_type = 'security_org_role_revoked'
    AND aggregate_id = '55555555-5555-5555-5555-555555555555'));
SELECT tap.login(tap.admin_user());
SELECT is((kernel.change_org_role(tap._fetch('org1')::uuid,
  '55555555-5555-5555-5555-555555555555', 'org_finance', 'cp1'))->>'status', 'ok',
  '077 P1a: promotion into a SENSITIVE role');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM notify.outbox
    WHERE event_type = 'security_org_role_granted'
      AND aggregate_id = '55555555-5555-5555-5555-555555555555'
      AND event_key LIKE 'security_role_grant:%'),
  tap._fetch('g_pre')::int + 1,
  '077 P1 [R2 row 22]: the sensitive grant BE-emits ONE security_org_role_granted keyed on its own audit row');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.change_org_role(tap._fetch('org1')::uuid,
  '55555555-5555-5555-5555-555555555555', 'org_member', 'cp2'))->>'status', 'ok',
  '077 P2a: demotion out of the sensitive role');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM notify.outbox
    WHERE event_type = 'security_org_role_revoked'
      AND aggregate_id = '55555555-5555-5555-5555-555555555555'),
  tap._fetch('r_pre')::int + 1,
  '077 P2 [R2 row 22]: the sensitive revoke BE-emits ONE security_org_role_revoked');
SELECT tap._store('t_pre', (SELECT count(*)::text FROM notify.outbox
  WHERE event_type IN ('security_org_role_granted','security_org_role_revoked')
    AND aggregate_id = '55555555-5555-5555-5555-555555555555'));
SELECT tap.login(tap.admin_user());
SELECT is((kernel.change_org_role(tap._fetch('org1')::uuid,
  '55555555-5555-5555-5555-555555555555', 'org_marketing', 'cp3'))->>'status', 'ok',
  '077 P3a: a non-sensitive lateral change');
SELECT tap.logout();
SELECT is(
  (SELECT count(*)::int FROM notify.outbox
    WHERE event_type IN ('security_org_role_granted','security_org_role_revoked')
      AND aggregate_id = '55555555-5555-5555-5555-555555555555'),
  tap._fetch('t_pre')::int,
  '077 P3 [NOTIF Group S]: only SENSITIVE role changes notify — the lateral change emitted nothing');

-- ── Q. THE ELEVEN SEAM-2 STUBS (§20.17.5; SEAM-2a identity) ────────────────

SELECT is(
  (SELECT string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')->'
                     || pg_get_function_result(p.oid), ';' ORDER BY p.proname COLLATE "C")
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel'
      AND (p.proname LIKE 'deletion_blockers_%' OR p.proname LIKE 'on_identity_erased_%'
           OR p.proname IN ('has_outstanding_obligations','on_deletion_q5_release'))),
  'deletion_blockers_custody(p_identity uuid)->text;'
  || 'deletion_blockers_market(p_identity uuid)->text;'
  || 'deletion_blockers_money(p_identity uuid)->text;'
  || 'deletion_blockers_orders(p_identity uuid)->text;'
  || 'deletion_blockers_wallet(p_identity uuid)->text;'
  || 'has_outstanding_obligations(p_identity_id uuid)->boolean;'
  || 'on_deletion_q5_release(p_identity uuid)->void;'
  || 'on_identity_erased_door(p_identity uuid)->void;'
  || 'on_identity_erased_market(p_identity uuid)->void;'
  || 'on_identity_erased_promoter(p_identity uuid)->void;'
  || 'on_identity_erased_staff(p_identity uuid)->void',
  '077 Q1 [SEAM-2a]: EXPECTED 11 = ACTUAL 11 stubs, signatures (incl. parameter NAMES) byte-exact to §20.17.5');
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'kernel'
        AND (p.proname LIKE 'deletion_blockers_%' OR p.proname LIKE 'on_identity_erased_%'
             OR p.proname IN ('has_outstanding_obligations','on_deletion_q5_release'))
      GROUP BY p.proname HAVING count(*) > 1) s),
  0, '077 Q2 [SEAM-2a]: COUNT(*)=1 per hook name — no silent overload leaves a stub live');
SELECT is(
  (SELECT coalesce(kernel.deletion_blockers_custody(tap.seller()), 'NULL')
        || coalesce(kernel.deletion_blockers_orders(tap.seller()), 'NULL')
        || coalesce(kernel.deletion_blockers_wallet(tap.seller()), 'NULL')
        || coalesce(kernel.deletion_blockers_money(tap.seller()), 'NULL')
        || coalesce(kernel.deletion_blockers_market(tap.seller()), 'NULL')),
  'NULLNULLNULLNULLNULL',
  '077 Q3 [C113]: every blocker stub returns NULL — the TRUE value over an empty world, not an approximation');
SELECT is(kernel.has_outstanding_obligations(tap.seller()), false,
  '077 Q4 [OR-21]: the BP-10 stub returns false — true-not-inert (no origin object exists before 085)');
SELECT lives_ok(
  $$SELECT kernel.on_identity_erased_staff(tap.seller()),
           kernel.on_identity_erased_door(tap.seller()),
           kernel.on_identity_erased_market(tap.seller()),
           kernel.on_identity_erased_promoter(tap.seller()),
           kernel.on_deletion_q5_release(tap.seller())$$,
  '077 Q5: the five void hooks are callable no-ops');

SELECT * FROM finish();
ROLLBACK;
