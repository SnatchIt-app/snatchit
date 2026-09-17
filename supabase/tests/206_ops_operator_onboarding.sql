-- 206_ops_operator_onboarding.sql — migration 138: the console can SEE
-- organisations, venues, members and staff, and can ACT on them only through the
-- audited action framework. Runs as postgres inside BEGIN … ROLLBACK like every
-- suite here. Contract: docs/venue-dashboard/OPERATOR_ONBOARDING_CONTRACT_D_20260917.md
BEGIN;
SELECT plan(140);
-- No tap.seed_core(): it builds listings, and 185's insert guard refuses the
-- server-controlled columns it writes. This suite needs three identities and
-- nothing else, so it makes them itself and stays independent of the fixture
-- builder's own breakage.
INSERT INTO auth.users (id, email, aud, role, created_at)
SELECT u.id, u.id::text || '@test.local', 'authenticated', 'authenticated', now()
  FROM (VALUES (tap.admin_user()), (tap.seller()), (tap.buyer()), (tap.other_user())) AS u(id)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id, display_name)
VALUES (tap.seller(), 'Sella Seller'), (tap.buyer(), 'Bee Buyer')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._aal1() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal1"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._try206(stmt text) RETURNS text LANGUAGE plpgsql AS $f$
BEGIN EXECUTE stmt; RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ' ' || SQLERRM; END $f$;
CREATE FUNCTION tap._pc206(j jsonb) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce(ops.action_precheck(jsonb_populate_record(null::ops.action, j)) ->> 'reject_reason', 'allowed') $f$;

INSERT INTO public.admin_users (user_id, label) VALUES (tap.admin_user(), 'TEST ADMIN') ON CONFLICT (user_id) DO NOTHING;

-- ── fixtures: one org, one member, one pending invite, one venue, one staff row ─
CREATE FUNCTION tap._org206()   RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'dddddddd-0000-0000-0000-000000000206'::uuid $f$;
CREATE FUNCTION tap._venue206() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'eeeeeeee-0000-0000-0000-000000000206'::uuid $f$;
CREATE FUNCTION tap._inv206()   RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'ffffffff-0000-0000-0000-000000000206'::uuid $f$;

INSERT INTO kernel.organization (org_id, legal_name, display_name, status)
VALUES (tap._org206(), 'Two Oh Six Holdings LLC', 'Club 206', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES (tap._org206(), tap.seller(), 'org_owner');
-- other_user has NO profiles row on purpose: ops.actor_label would fall back to
-- ops.mask_email(auth.users.email) for exactly this member, so G2 only means
-- something with such a member present.
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES (tap._org206(), tap.other_user(), 'org_member');
INSERT INTO kernel.org_invite (invite_id, org_id, invitee_ref, role, status, invited_by, expires_at, command_idempotency_key)
VALUES (tap._inv206(), tap._org206(), 'hopeful.person@example.com', 'org_member', 'pending', tap.admin_user(), now() + interval '7 days', 'k206-invite');
-- an ACCEPTED invite whose identity has NO profiles row: the case where a coalesce on the
-- display name would fall through to the masked address on a row the owner ruled shows the UUID.
INSERT INTO kernel.org_invite (invite_id, org_id, invitee_ref, invitee_identity_id, role, status, invited_by, expires_at, command_idempotency_key)
VALUES ('ffffffff-0000-0000-0000-000000000299', tap._org206(), 'accepted.person@example.com', tap.other_user(), 'org_member', 'accepted', tap.admin_user(), now() + interval '7 days', 'k206-accepted');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, address, approval_status)
VALUES (tap._venue206(), tap._org206(), 'The 206 Room', 'wynwood', '206 NW 2nd Ave', 'pending');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES (tap._venue206(), tap.buyer(), 'venue_manager');

-- ── A. shape and grants ──────────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='ops' AND p.proname IN ('list_organizations','get_organization','list_venues',
              'list_org_members','list_org_invites','list_venue_staff','get_org_contact_email')), 7,
  'A1: all seven reachable read verbs exist in ops');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='ops' AND p.proname IN ('list_organizations','get_organization','list_venues',
              'list_org_members','list_org_invites','list_venue_staff','get_org_contact_email')
              AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']), 7,
  'A2: every one is SECURITY DEFINER with search_path pinned (066 invariant)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='ops' AND p.proname IN ('list_organizations','get_organization','list_venues',
              'list_org_members','list_org_invites','list_venue_staff','get_org_contact_email')
              AND has_function_privilege('anon', p.oid, 'EXECUTE')), 0,
  'A3: anon can execute none of them');
SELECT ok((SELECT bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')) FROM pg_proc p
            JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='ops'
            AND p.proname IN ('list_organizations','get_organization','list_venues','list_org_members',
              'list_org_invites','list_venue_staff','get_org_contact_email')),
  'A4: authenticated may execute them — the boundary is ops.assert_reader(), not the grant');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='ops' AND p.proname IN ('identity_display_name','org_connect_readiness')
              AND has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0,
  'A5: the two internal helpers are granted to nobody');

-- ── B. the ops-wide invariant nothing pinned before 138 ──────────────────────
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='ops' AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
              AND NOT (p.prosecdef AND coalesce(p.proconfig @> ARRAY['search_path=""'], false))), 0,
  'B1: EVERY ops function reachable by authenticated is definer + search_path-pinned');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='ops' AND has_function_privilege('anon', p.oid, 'EXECUTE')), 0,
  'B2: anon can execute NOTHING in ops');

-- ── C. the CHECK widening, proved by insert in BOTH directions ───────────────
SELECT is(tap._try206($$INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, params, requested_by)
  VALUES ('k206-newtype', 'venue_approve', 'venue', '$$ || tap._venue206() || $$', '{"decision":"approved"}', '$$ || tap.admin_user() || $$')$$), 'ok',
  'C1: a NEW action_type and subject_kind are admitted (the drop+re-add really widened it)');
SELECT matches(tap._try206($$INSERT INTO ops.action (idempotency_key, action_type, subject_kind, requested_by)
  VALUES ('k206-bogus', 'org_take_over_the_world', 'none', '$$ || tap.admin_user() || $$')$$), '^23514',
  'C2: a bogus action_type is still REJECTED — the widening did not become permissive');
SELECT matches(tap._try206($$INSERT INTO ops.action (idempotency_key, action_type, subject_kind, requested_by)
  VALUES ('k206-old', 'payout_release', 'transfer', '$$ || tap.admin_user() || $$')$$), '^ok',
  'C3: an EXISTING action_type still admitted — the re-add did not lose the old list');

-- ── D. precheck, the second layer, called directly ───────────────────────────
-- (Everything a caller can do is proved through the front door in section I.)
INSERT INTO kernel.organization (org_id, legal_name, display_name, status)
VALUES ('dddddddd-0000-0000-0000-00000000d206', 'Ownerless 206 LLC', 'Ownerless 206', 'approved');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, address, approval_status)
VALUES ('eeeeeeee-0000-0000-0000-00000000d206', tap._org206(), 'Draft 206', 'wynwood', '1 D St', 'draft');
SELECT is(tap._pc206('{"action_type":"payout_release"}'), 'precondition',
  'D1: 118''s own payout_release arm still runs — 138 redefined from 118''s body, not 115''s');
SELECT is(tap._pc206(jsonb_build_object('action_type','org_owner_bootstrap_invite','subject_id',tap._org206())), 'precondition',
  'D2: a bootstrap owner invite for an organisation that HAS an owner is refused before any approval is parked');
SELECT is(tap._pc206('{"action_type":"org_owner_bootstrap_invite","subject_id":"dddddddd-0000-0000-0000-00000000d206"}'), 'allowed',
  'D3: ...and allowed for one with no owner and no pending owner invite');
SELECT is(tap._pc206('{"action_type":"venue_approve","subject_id":"eeeeeeee-0000-0000-0000-00000000d206","params":{"decision":"approved"}}'), 'precondition',
  'D4: approving a DRAFT venue is refused before any approval is parked');
SELECT is(tap._pc206(jsonb_build_object('action_type','venue_approve','subject_id',tap._venue206(),'params',jsonb_build_object('decision','approved'))), 'allowed',
  'D5: ...and allowed for a pending one');

-- ── E. approval set and role gating ──────────────────────────────────────────
SELECT is((SELECT array_agg(t ORDER BY t) FROM unnest(array['case_create','dispute_resolve','payout_release','listing_relist','report_resolve',
            'user_restrict','user_unrestrict','refund_execute','job_retry','setting_set','org_bootstrap','org_status_set',
            'org_owner_bootstrap_invite','org_invite_revoke','platform_role_grant','venue_create','venue_submit','venue_approve',
            'venue_staff_grant','venue_staff_revoke']) t WHERE ops.action_requires_approval(t)),
  ARRAY['org_owner_bootstrap_invite','payout_release','platform_role_grant','refund_execute','venue_approve'],
  'E1: two-person approval is EXACTLY the owner''s three plus 115''s two money actions');
SELECT is((SELECT count(*)::int FROM unnest(array['org_bootstrap','org_status_set','org_owner_bootstrap_invite','org_invite_revoke',
            'platform_role_grant','venue_create','venue_submit','venue_approve','venue_staff_grant','venue_staff_revoke']) t
            WHERE ops.action_allowed_roles(t) = ARRAY['platform_admin']), 10,
  'E2: every onboarding write is platform_admin only — support holds none (ruling 2)');
SELECT is(ops.action_allowed_roles('payout_release'), ARRAY['platform_admin'], 'E3: 115''s money role gating is preserved');

-- ── F. the reads: operator at aal2 only ──────────────────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT is((SELECT count(*)::int FROM ops.list_organizations() WHERE org_id = tap._org206()), 1,
  'F1: an operator at aal2 sees the organisation');
SELECT is((SELECT display_name FROM ops.get_organization(tap._org206())), 'Club 206',
  'F2: get_organization returns the display name');
SELECT is((SELECT connect_readiness FROM ops.get_organization(tap._org206())), 'not_started',
  'F3: Connect is a readiness WORD, never the account reference');
SELECT is((SELECT count(*)::int FROM ops.list_venues(tap._org206(), 'pending')), 1,
  'F4: list_venues(status => pending) IS the approval queue');
SELECT is((SELECT count(*)::int FROM ops.list_venue_staff(tap._venue206())), 1,
  'F5: venue staff are listed');
SELECT tap.logout(); SELECT tap.login(tap.seller()); SELECT tap._aal2();
SELECT throws_ok($$ SELECT * FROM ops.list_organizations() $$, '42501', NULL,
  'F6: a non-operator with aal2 is refused');
SELECT tap.logout(); SELECT tap.login(tap.admin_user()); SELECT tap._aal1();
SELECT matches(tap._try206($$ SELECT * FROM ops.list_organizations() $$), 'step_up_required',
  'F7: an operator WITHOUT aal2 is refused — MFA is part of the boundary');

-- ── G. the owner's field rules, enforced not merely intended ─────────────────
SELECT tap.logout(); SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT is((SELECT identity_id FROM ops.list_org_members(tap._org206()) WHERE role = 'org_owner'), tap.seller(),
  'G1: the account identifier IS the identity UUID (owner ruling 2026-09-17)');
SELECT ok((SELECT bool_and(coalesce(display_name, '') NOT LIKE '%@%') FROM ops.list_org_members(tap._org206())),
  'G2: no address reaches ANY accepted member row, including one with no profile display name — ops.identity_display_name never falls back to a masked email');
SELECT ok((SELECT bool_and(coalesce(display_name, '') NOT LIKE '%@%') FROM ops.list_venue_staff(tap._venue206())),
  'G3: ...nor a venue staff row');
SELECT is((SELECT invitee_label FROM ops.list_org_invites(tap._org206()) WHERE status = 'pending'), 'h***@example.com',
  'G4: a PENDING invite shows the approved mask — it has no identity UUID yet, and invitee_ref IS the address');
SELECT is((SELECT invite_id FROM ops.list_org_invites(tap._org206()) WHERE status = 'pending'), tap._inv206(),
  'G5: ...always beside the stable invite_id, so two identical masks stay distinguishable (owner ruling)');
SELECT ok((SELECT bool_and(coalesce(invitee_label, '') NOT LIKE '%@%') FROM ops.list_org_invites(tap._org206())
            WHERE invitee_identity_id IS NOT NULL),
  'G5b (A review): an ACCEPTED invite never shows an address, even when its identity has no display name — the mask is conditioned on invitee_identity_id, not on the name being null');
SELECT is((SELECT count(*)::int FROM information_schema.parameters
            WHERE specific_schema='ops' AND specific_name LIKE 'list_org_invites%'
              AND parameter_mode = 'IN' AND parameter_name <> 'p_org_id'), 0,
  'G6: no parameter takes the mask — it is displayable, never searchable');
SELECT is((SELECT array_agg(a.attname::text ORDER BY a.attname) FROM pg_proc p
             JOIN pg_namespace n ON n.oid=p.pronamespace
             CROSS JOIN LATERAL unnest(p.proargnames) WITH ORDINALITY AS u(nm, i)
             JOIN LATERAL (SELECT u.nm AS attname) a ON true
            WHERE n.nspname='ops' AND p.proname='list_org_members' AND u.i > p.pronargs),
          ARRAY['display_name','granted_at','identity_id','role'],
  'G7: list_org_members returns EXACTLY the allowlisted columns — add an excluded one and this fails');

-- ── H. contact email: the restriction is the verb and its audit row ──────────
SELECT matches(tap._try206($$ SELECT ops.get_org_contact_email('$$ || tap._org206() || $$', 'because_i_felt_like_it') $$),
  'reason_code must be', 'H1: the reason code is a closed set');
-- ops.audit carries no grant to `authenticated` (115): read it as postgres.
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action = 'org_contact_email_read'), 0,
  'H2: ...and a refused read writes no audit row');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT ok(ops.get_org_contact_email(tap._org206(), 'onboarding_contact') IS NOT NULL,
  'H3: a purpose-limited read returns the org owner''s address');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action = 'org_contact_email_read' AND subject_id = tap._org206()), 1,
  'H4: ...and EVERY call writes an audit row — the restriction is the verb, not a convention');
SELECT is((SELECT reason FROM ops.audit WHERE action = 'org_contact_email_read' AND subject_id = tap._org206()), 'onboarding_contact',
  'H5: ...carrying the reason code, so the audit is queryable rather than free text');

-- ── I. THROUGH THE FRONT DOOR — the owner's rulings on the permission proposal (2026-09-17) ──
-- Nothing below calls a component. Every action goes through ops.execute_action and every decision
-- through ops.approve_action, as an authenticated operator at aal2; acceptance goes through
-- kernel.accept_org_invite as the accepting account. Every outcome is read back from ops.action AND from
-- the domain table it should (or must not) have changed.
--
-- Cast (written as postgres):
--   A     tap.admin_user()  platform_admin through the public.admin_users bootstrap
--   B, C  5555…, 6666…      platform_admin through kernel.platform_role
--   S     7777…             platform_support
--   ADM2  adad…             in public.admin_users ONLY (the bootstrap path, no kernel.platform_role row)
--   CUST1 8888…  cust.one@example.com   a customer (no platform authority)
--   CUST2 9999…  cust.two@example.com   a customer
CREATE FUNCTION tap._A206()    RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT tap.admin_user() $f$;
CREATE FUNCTION tap._B206()    RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '55555555-5555-5555-5555-555555555555'::uuid $f$;
CREATE FUNCTION tap._C206()    RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '66666666-6666-6666-6666-666666666666'::uuid $f$;
CREATE FUNCTION tap._S206()    RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '77777777-7777-7777-7777-777777777777'::uuid $f$;
CREATE FUNCTION tap._ADM2()    RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'adadadad-adad-adad-adad-adadadadadad'::uuid $f$;
CREATE FUNCTION tap._CUST1()   RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '88888888-8888-8888-8888-888888888888'::uuid $f$;
CREATE FUNCTION tap._CUST2()   RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '99999999-9999-9999-9999-999999999999'::uuid $f$;

SELECT tap.logout();
INSERT INTO auth.users (id, email, aud, role, created_at) VALUES
  (tap._B206(),  'b.operator@test.local', 'authenticated', 'authenticated', now()),
  (tap._C206(),  'c.operator@test.local', 'authenticated', 'authenticated', now()),
  (tap._S206(),  's.operator@test.local', 'authenticated', 'authenticated', now()),
  (tap._ADM2(),  'adm2.operator@test.local', 'authenticated', 'authenticated', now()),
  (tap._CUST1(), 'cust.one@example.com', 'authenticated', 'authenticated', now()),
  (tap._CUST2(), 'cust.two@example.com', 'authenticated', 'authenticated', now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role)
VALUES (tap._B206(), 'platform_admin'), (tap._C206(), 'platform_admin'), (tap._S206(), 'platform_support');
INSERT INTO public.admin_users (user_id, label) VALUES (tap._ADM2(), 'ADM2 bootstrap only') ON CONFLICT (user_id) DO NOTHING;

CREATE FUNCTION tap._ea206(k text, t text, sk text, sid uuid, prm jsonb, rsn text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  v := ops.execute_action(k, t, sk, sid, coalesce(prm,'{}'::jsonb), rsn);
  RETURN coalesce(v ->> 'status', '(null)');
EXCEPTION WHEN OTHERS THEN RETURN 'RAISED: ' || SQLERRM;
END $f$;
-- lookups an authenticated caller cannot make (ops.action, kernel tables, auth.users are not granted to it)
CREATE FUNCTION tap._aid206(k text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $f$ SELECT id FROM ops.action WHERE idempotency_key = k $f$;
-- parameters are p_-prefixed: in a SQL function a same-named COLUMN wins, so `WHERE name = name` is always true
CREATE FUNCTION tap._org(p_display_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $f$ SELECT org_id FROM kernel.organization WHERE display_name = p_display_name $f$;
CREATE FUNCTION tap._venue(p_name text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $f$ SELECT venue_id FROM catalog.venue WHERE name = p_name $f$;
-- by address AND organisation: created_at ties inside one transaction, so "the latest" would be arbitrary
CREATE FUNCTION tap._inviteid(p_ref text, p_org uuid) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $f$ SELECT invite_id FROM kernel.org_invite WHERE invitee_ref = p_ref AND org_id = p_org $f$;
CREATE FUNCTION tap._email206(u uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $f$ SELECT email FROM auth.users WHERE id = u $f$;
CREATE FUNCTION tap._apr206(k text, decision text, rsn text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  v := ops.approve_action(tap._aid206(k), decision, rsn);
  RETURN coalesce(v ->> 'status', '(null)') || coalesce(':' || (v ->> 'reject_reason'), '');
EXCEPTION WHEN OTHERS THEN RETURN 'RAISED: ' || SQLERRM;
END $f$;
CREATE FUNCTION tap._accept206(ref text, org uuid, k text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  v := kernel.accept_org_invite(tap._inviteid(ref, org), k);
  RETURN coalesce(v ->> 'status', '(null)');
EXCEPTION WHEN OTHERS THEN RETURN 'RAISED: ' || SQLERRM;
END $f$;
CREATE FUNCTION tap._inv206(k text, rc text) RETURNS text LANGUAGE plpgsql AS $f$
BEGIN RETURN coalesce(ops.get_action_invitee(tap._aid206(k), rc), '(null)');
EXCEPTION WHEN OTHERS THEN RETURN 'RAISED: ' || SQLERRM; END $f$;
-- read as postgres
CREATE FUNCTION tap._st206(k text) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT coalesce((SELECT state || coalesce(':' || reject_reason, '') FROM ops.action WHERE idempotency_key = k), '(no row)') $f$;
CREATE FUNCTION tap._members(org uuid) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT coalesce(string_agg(identity_id::text || '=' || role, ',' ORDER BY identity_id::text), '(none)') FROM kernel.org_member WHERE org_id = org $f$;
CREATE FUNCTION tap._platform_members() RETURNS integer LANGUAGE sql STABLE AS $f$
  SELECT (SELECT count(*) FROM kernel.org_member m WHERE ops.identity_holds_platform_authority(m.identity_id))::int
       + (SELECT count(*) FROM venue.staff_role s WHERE ops.identity_holds_platform_authority(s.identity_id))::int $f$;

CREATE FUNCTION tap._set206(p_mode text) RETURNS text[] LANGUAGE plpgsql AS $f$
DECLARE r record; v text[] := '{}';
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('org_bootstrap','none',NULL::uuid,'{}'::jsonb), ('org_status_set','organization',tap._org206(),'{}'),
      ('org_owner_bootstrap_invite','organization',tap._org206(),'{}'),
      ('org_invite_revoke','org_invite','ffffffff-0000-0000-0000-00000000e206','{}'), ('platform_role_grant','none',NULL,'{}'),
      ('venue_create','organization',tap._org206(),'{}'), ('venue_submit','venue',tap._venue206(),'{}'),
      ('venue_approve','venue',tap._venue206(),'{}'), ('venue_staff_grant','venue',tap._venue206(),'{}'),
      ('venue_staff_revoke','venue',tap._venue206(),'{}'),
      ('org_create','none',NULL,'{}'), ('org_update','organization',tap._org206(),'{}'),
      ('org_member_invite','organization',tap._org206(),'{}'), ('org_member_invite_admin','organization',tap._org206(),'{}'),
      ('org_member_role_change','organization',tap._org206(),'{}'), ('org_member_elevate','organization',tap._org206(),'{}'),
      ('org_member_remove','organization',tap._org206(),'{}')) t(typ, sk, sid, prm)
  LOOP
    BEGIN
      -- in 'unknown' mode a bogus subject kind stops every KNOWN type right after the type check, so the
      -- probe itself writes nothing and only a genuinely unknown type answers 'unknown action_type'
      PERFORM ops.execute_action('k206-set-' || p_mode || '-' || r.typ, r.typ,
                                 CASE WHEN p_mode = 'unknown' THEN 'zz_not_a_kind' ELSE r.sk END, r.sid, r.prm,
                                 CASE WHEN p_mode = 'reason' THEN NULL ELSE 'set probe' END);
    EXCEPTION WHEN OTHERS THEN
      IF (p_mode = 'reason'  AND SQLERRM LIKE 'invalid_input: a reason is required for %')
      OR (p_mode = 'unknown' AND SQLERRM LIKE 'invalid_input: unknown action_type %')
      OR (p_mode = 'support' AND SQLSTATE = '42501' AND SQLERRM LIKE 'insufficient_privilege: platform_support may not perform %') THEN
        v := v || r.typ;
      END IF;
    END;
  END LOOP;
  RETURN (SELECT array_agg(x ORDER BY x) FROM unnest(v) x);
END $f$;

-- ── I.1 the console has no organisation-roster action, and support has no write (rulings 2, 3) ──
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._set206('unknown'),
  ARRAY['org_create','org_member_elevate','org_member_invite','org_member_invite_admin','org_member_remove','org_member_role_change','org_update'],
  'I1: the seven organisation-management types are UNKNOWN at the door — no console path changes a customer roster');
SELECT is(tap._set206('reason'),
  ARRAY['org_owner_bootstrap_invite','org_status_set','platform_role_grant','venue_approve'],
  'I2: a reason is required for exactly the three two-person types and organisation status');
SELECT tap.logout(); SELECT tap.login(tap._S206()); SELECT tap._aal2();
SELECT is(tap._set206('support'),
  ARRAY['org_bootstrap','org_invite_revoke','org_owner_bootstrap_invite','org_status_set','platform_role_grant',
        'venue_approve','venue_create','venue_staff_grant','venue_staff_revoke','venue_submit'],
  'I3: platform_support is refused at the door for EVERY onboarding write (ruling 2)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key LIKE 'k206-set-unknown-%' OR idempotency_key LIKE 'k206-set-support-%'
            OR (idempotency_key LIKE 'k206-set-reason-%' AND action_type IN ('org_owner_bootstrap_invite','org_status_set','platform_role_grant','venue_approve'))), 0,
  'I4: none of those refusals wrote an action (the unknown-type probe stops every type before the insert)');

-- ── I.2 A1: an operator creates an organisation WITHOUT becoming a member ──
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-b-org1','org_bootstrap','none',NULL,'{"legal_name":"Boot One LLC","display_name":"Boot One"}'), 'succeeded', 'I5: org_bootstrap succeeds');
SELECT is(tap._ea206('k206-b-org2','org_bootstrap','none',NULL,'{"legal_name":"Boot Two LLC","display_name":"Boot Two"}'), 'succeeded', 'I6: a second organisation');
SELECT is(tap._ea206('k206-b-org3','org_bootstrap','none',NULL,'{"legal_name":"Boot Three LLC","display_name":"Boot Three"}'), 'succeeded', 'I7: a third, left at applied');
SELECT is(tap._ea206('k206-b-appr1','org_status_set','organization',tap._org('Boot One'),'{"target_status":"approved"}','reviewed'), 'succeeded', 'I8: Boot One approved');
SELECT is(tap._ea206('k206-b-appr2','org_status_set','organization',tap._org('Boot Two'),'{"target_status":"approved"}','reviewed'), 'succeeded', 'I9: Boot Two approved');
SELECT tap.logout();
SELECT is((SELECT string_agg(o.display_name || '=' || o.status || '/' || tap._members(o.org_id), ',' ORDER BY o.display_name) FROM kernel.organization o WHERE o.display_name LIKE 'Boot %'),
  'Boot One=approved/(none),Boot Three=applied/(none),Boot Two=approved/(none)',
  'I10: PRINCIPLE 1 — each organisation exists with NO member; the creating operator is not its owner (ruling 1)');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'org.create' AND reason_code = 'platform_bootstrap' AND actor_identity = tap._A206()), 3,
  'I11: each creation is in the domain audit as a platform bootstrap by the operator');

-- ── I.3 the bootstrap owner invite: refused at the door for the wrong invitee ──
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT matches(tap._ea206('k206-bd-self-mail','org_owner_bootstrap_invite','organization',tap._org('Boot One'),jsonb_build_object('invitee_ref', upper(tap._email206(tap._A206()))),'x'),
  'cannot invite the requester', 'I12: the requester''s own address, in any case, is refused');
SELECT matches(tap._ea206('k206-bd-self-id','org_owner_bootstrap_invite','organization',tap._org('Boot One'),jsonb_build_object('invitee_ref', tap._A206()::text),'x'),
  'cannot invite the requester', 'I13: ...and the requester''s identity');
SELECT matches(tap._ea206('k206-bd-platform','org_owner_bootstrap_invite','organization',tap._org('Boot One'),jsonb_build_object('invitee_ref', tap._email206(tap._B206())),'x'),
  'holding platform authority', 'I14: an address belonging to a platform_role holder is refused');
SELECT matches(tap._ea206('k206-bd-adm2','org_owner_bootstrap_invite','organization',tap._org('Boot One'),jsonb_build_object('invitee_ref', tap._ADM2()::text),'x'),
  'holding platform authority', 'I15: ...and an identity that is platform_admin only through the admin_users bootstrap');
SELECT matches(tap._ea206('k206-bd-role','org_owner_bootstrap_invite','organization',tap._org('Boot One'),'{"invitee_ref":"cust.one@example.com","role":"org_admin"}','x'),
  'always invites at org_owner', 'I16: a role parameter is refused — the invite is always and only org_owner');
SELECT matches(tap._ea206('k206-bd-noref','org_owner_bootstrap_invite','organization',tap._org('Boot One'),'{}','x'),
  'invitee_ref required', 'I17: an invitee is required');
SELECT is(tap._ea206('k206-bd-owned','org_owner_bootstrap_invite','organization',tap._org206(),'{"invitee_ref":"cust.two@example.com"}','x'), 'rejected',
  'I18: an organisation that already has an owner is refused when requested — its roster is the customer''s (ruling 4)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key LIKE 'k206-bd-%' AND idempotency_key <> 'k206-bd-owned')
        + (SELECT count(*)::int FROM ops.approval p JOIN ops.action x ON x.approval_id = p.id WHERE x.idempotency_key = 'k206-bd-owned'), 0,
  'I19: I12–I17 wrote no action and I18 parked no approval');

-- ── I.4 two-person: requested, never self-approved, granted by a second operator ──
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-b-inv1','org_owner_bootstrap_invite','organization',tap._org('Boot One'),'{"invitee_ref":"cust.one@example.com"}','customer founder verified by phone'), 'awaiting_approval',
  'I20: the bootstrap owner invite is HELD for a second operator');
SELECT is(tap._ea206('k206-b-inv1b','org_owner_bootstrap_invite','organization',tap._org('Boot One'),'{"invitee_ref":"cust.two@example.com"}','a second founder'), 'awaiting_approval',
  'I21: a second request for the same organisation is also held (no owner invite exists yet)');
SELECT is(tap._ea206('k206-b-inv1c','org_owner_bootstrap_invite','organization',tap._org('Boot One'),'{"invitee_ref":"late.owner@example.com"}','a late request'), 'awaiting_approval',
  'I91: a third request, still waiting when the customer accepts (below)');
SELECT matches(tap._apr206('k206-b-inv1','approve','mine'), 'self_approval', 'I22: the requester cannot approve it');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.org_invite WHERE org_id = tap._org('Boot One')), 0, 'I23: NO SECOND APPROVER, NO INVITE');
SELECT tap.login(tap._S206()); SELECT tap._aal2();
SELECT is(tap._inv206('k206-b-inv1','approval_review'), 'cust.one@example.com', 'I24: the approver-side reveal shows the exact address, audited');
SELECT tap.logout(); SELECT tap.login(tap._B206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-b-inv1','approve','verified against the application contact'), 'succeeded', 'I25: a second platform_admin approves and the invite is written');
SELECT is(tap._apr206('k206-b-inv1b','approve','ok'), 'rejected:precondition', 'I26: the second request cannot run: an owner invite is already pending');
SELECT tap.logout();
SELECT is((SELECT string_agg(role || '/' || status || '/' || invitee_ref || '/' || (invited_by = tap._B206())::text, ',') FROM kernel.org_invite WHERE org_id = tap._org('Boot One')),
  'org_owner/pending/cust.one@example.com/true', 'I27: exactly one pending org_owner invite, with the real address for delivery, invited by the approver');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'org.invite' AND reason_code = 'platform_bootstrap_owner' AND actor_identity = tap._B206()), 1,
  'I28: in the domain audit as a platform bootstrap owner invite');
SELECT is((SELECT p.requested_by::text || '>' || p.decided_by::text FROM ops.approval p JOIN ops.action x ON x.approval_id = p.id WHERE x.idempotency_key = 'k206-b-inv1'),
  tap._A206()::text || '>' || tap._B206()::text, 'I29: requester and approver are both recorded');

-- ── I.5 the customer becomes the owner by ACCEPTING; platform authority cannot accept (A4) ──
SELECT tap.login(tap._CUST1());
SELECT is(tap._accept206('cust.one@example.com',tap._org('Boot One'),'k206-accept-cust1'), 'ok', 'I30: the customer accepts');
SELECT tap.logout();
SELECT is((SELECT role || '/' || (granted_at IS NOT NULL)::text FROM kernel.org_member WHERE org_id = tap._org('Boot One') AND identity_id = tap._CUST1()),
  'org_owner/true', 'I31: the customer is org_owner, with the maturity clock started at acceptance (AUTHZ-C1B)');
SELECT is(tap._members(tap._org('Boot One')), tap._CUST1()::text || '=org_owner', 'I32: ...and the only member');
SELECT tap.login(tap._B206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-b-inv1c','approve','ok'), 'rejected:precondition',
  'I92: a request approved AFTER the customer became owner does not run — the verb re-checks ownership when the approval executes');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.org_invite WHERE invitee_ref = 'late.owner@example.com'), 0, 'I93: ...and no second owner invite exists');
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-b-owned-after','org_owner_bootstrap_invite','organization',tap._org('Boot One'),'{"invitee_ref":"cust.two@example.com"}','x'), 'rejected',
  'I33: once the customer owns it, the console can no longer invite an owner');
-- F-138-11, the sequence A and D reproduced: a request passes every request-time check, and the address changes hands
SELECT is(tap._ea206('k206-b-inv2','org_owner_bootstrap_invite','organization',tap._org('Boot Two'),'{"invitee_ref":"later.c@example.com"}','x'), 'awaiting_approval', 'I34: an owner invite for an address nobody holds yet');
SELECT tap.logout(); SELECT tap.login(tap._B206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-b-inv2','approve','ok'), 'succeeded', 'I35: approved and written');
SELECT tap.logout();
UPDATE auth.users SET email = 'later.c@example.com' WHERE id = tap._C206();   -- platform_admin C takes the address
SELECT tap.login(tap._C206());
SELECT matches(tap._accept206('later.c@example.com',tap._org('Boot Two'),'k206-accept-c'), 'platform_authority',
  'I36: A4 — a platform_admin whose email became the invited address CANNOT accept (F-138-11 closed where membership is created)');
SELECT tap.logout();
INSERT INTO kernel.org_invite (org_id, invitee_ref, role, status, invited_by, expires_at, command_idempotency_key) VALUES
  (tap._org206(), 's.operator@test.local', 'org_member', 'pending', tap.seller(), now() + interval '7 days', 'k206-fx-s'),
  (tap._org206(), 'adm2.operator@test.local', 'org_member', 'pending', tap.seller(), now() + interval '7 days', 'k206-fx-adm2'),
  (tap._org206(), 'cust.two@example.com', 'org_member', 'pending', tap.seller(), now() + interval '7 days', 'k206-fx-cust2');
SELECT tap.login(tap._S206());
SELECT matches(tap._accept206('s.operator@test.local',tap._org206(),'k206-accept-s'), 'platform_authority', 'I37: platform_support cannot accept any customer invite (ruling 3)');
SELECT tap.logout(); SELECT tap.login(tap._ADM2());
SELECT matches(tap._accept206('adm2.operator@test.local',tap._org206(),'k206-accept-adm2'), 'platform_authority', 'I38: ...nor an admin_users-bootstrap identity (ruling 7)');
SELECT tap.logout(); SELECT tap.login(tap._CUST2());
SELECT is(tap._accept206('cust.two@example.com',tap._org206(),'k206-accept-cust2'), 'ok', 'I39: a customer''s own org-plane invite is unaffected by A4');
SELECT tap.logout();
SELECT is(tap._members(tap._org('Boot Two')), '(none)', 'I40: Boot Two still has no member — C did not become one');
-- the verb's own checks, reachable when an address changes hands between request and approval
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-b-inv3a','org_owner_bootstrap_invite','organization',tap._org('Boot Three'),'{"invitee_ref":"later.b@example.com"}','x'), 'awaiting_approval', 'I41: requested for an address nobody holds yet');
SELECT tap.logout();
UPDATE auth.users SET email = 'later.b@example.com' WHERE id = tap._B206();
SELECT tap.login(tap._B206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-b-inv3a','approve','ok'), 'rejected:precondition', 'I42: the APPROVER now holds the address, and the verb refuses (beneficiary ≠ approver)');
SELECT tap.logout(); SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-b-inv3b','org_owner_bootstrap_invite','organization',tap._org('Boot Three'),'{"invitee_ref":"later.s@example.com"}','x'), 'awaiting_approval', 'I43: requested again');
SELECT tap.logout();
UPDATE auth.users SET email = 'later.s@example.com' WHERE id = tap._S206();
SELECT tap.login(tap._C206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-b-inv3b','approve','ok'), 'rejected:precondition', 'I44: a platform_support identity now holds it, and the verb refuses');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.org_invite WHERE org_id = tap._org('Boot Three')), 0, 'I45: Boot Three has no invite');
-- recovery: an organisation that has lost its only owner
DELETE FROM kernel.org_member WHERE org_id = tap._org('Boot One') AND identity_id = tap._CUST1();
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-b-recover','org_owner_bootstrap_invite','organization',tap._org('Boot One'),'{"invitee_ref":"new.owner@example.com"}','owner account deleted'), 'awaiting_approval',
  'I46: recovery — with no owner left, a new bootstrap invite may be requested (still two-person)');

-- ── I.6 A3 and the venue lifecycle ──
SELECT is(tap._ea206('k206-v-create','venue_create','organization',tap._org('Boot Two'),'{"name":"Boot Room","neighborhood":"brickell","address":"3 B St"}'), 'succeeded', 'I47: venue_create for an organisation the operator does not belong to');
SELECT is(tap._ea206('k206-v-create-applied','venue_create','organization',tap._org('Boot Three'),'{"name":"Too Early","neighborhood":"brickell"}'), 'rejected', 'I48: ...not for an organisation still at applied');
SELECT is(tap._ea206('k206-v-approve-draft','venue_approve','venue',tap._venue('Boot Room'),'{"decision":"approved","reason_code":"x"}','x'), 'rejected', 'I49: a draft venue cannot be approved');
SELECT matches(tap._ea206('k206-v-approve-pending','venue_approve','venue',tap._venue('Boot Room'),'{"decision":"pending","reason_code":"x"}','x'), 'decides approved or archived', 'I50: venue_approve cannot move a venue to pending');
SELECT is(tap._ea206('k206-v-submit','venue_submit','venue',tap._venue('Boot Room'),'{}'), 'succeeded', 'I51: venue_submit moves the draft to the queue');
SELECT is((SELECT count(*)::int FROM ops.list_venues(tap._org('Boot Two'), 'pending') WHERE name = 'Boot Room'), 1, 'I52: ...and it is in the approval queue');
SELECT is(tap._ea206('k206-v-resubmit','venue_submit','venue',tap._venue('Boot Room'),'{}'), 'rejected', 'I53: a pending venue cannot be submitted again');
SELECT is(tap._ea206('k206-v-approve','venue_approve','venue',tap._venue('Boot Room'),'{"decision":"approved","reason_code":"site_visit"}','visited'), 'awaiting_approval', 'I54: approval is held for a second operator');
SELECT tap.logout(); SELECT tap.login(tap._C206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-v-approve','approve','agree'), 'succeeded', 'I55: a second operator approves');
SELECT tap.logout();
SELECT is((SELECT approval_status FROM catalog.venue WHERE venue_id = tap._venue('Boot Room'))
          || '/' || (SELECT count(*) FROM kernel.admin_audit WHERE action = 'venue.create' AND reason_code = 'platform_bootstrap' AND subject_id = tap._venue('Boot Room'))
          || '/' || (SELECT count(*) FROM venue.staff_role WHERE venue_id = tap._venue('Boot Room')),
  'approved/1/0', 'I56: approved; created as a platform bootstrap; and nobody became its staff');
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-v-create2','venue_create','organization',tap._org('Boot Two'),'{"name":"Boot Room Two","neighborhood":"midtown"}'), 'succeeded', 'I94: a second venue');
SELECT is(tap._ea206('k206-v-submit2','venue_submit','venue',tap._venue('Boot Room Two'),'{}'), 'succeeded', 'I95: submitted');
SELECT is(tap._ea206('k206-v-approve2','venue_approve','venue',tap._venue('Boot Room Two'),'{"decision":"approved","reason_code":"site_visit"}','visited'), 'awaiting_approval', 'I96: approval requested');
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'draft' WHERE venue_id = tap._venue('Boot Room Two');   -- it leaves the queue before approval
SELECT tap.login(tap._C206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-v-approve2','approve','agree'), 'rejected:precondition', 'I97: a venue that left the queue after the request is not approved when the approval runs');
SELECT tap.logout();
SELECT is((SELECT approval_status FROM catalog.venue WHERE venue_id = tap._venue('Boot Room Two')), 'draft', 'I98: ...and stays draft');

-- ── I.7 venue staff: an operator cannot make another operator staff at a customer venue (ruling 7, path (c)) ──
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT matches(tap._ea206('k206-s-c','venue_staff_grant','venue',tap._venue206(),jsonb_build_object('identity_id', tap._C206(), 'role', 'venue_scanner')), 'holding platform authority', 'I57: not a platform_role holder');
SELECT matches(tap._ea206('k206-s-adm2','venue_staff_grant','venue',tap._venue206(),jsonb_build_object('identity_id', tap._ADM2(), 'role', 'venue_scanner')), 'holding platform authority', 'I58: not an admin_users-bootstrap identity');
SELECT matches(tap._ea206('k206-s-s','venue_staff_grant','venue',tap._venue206(),jsonb_build_object('identity_id', tap._S206(), 'role', 'venue_scanner')), 'holding platform authority', 'I59: not support — membership is not a workaround for support access');
SELECT is(tap._ea206('k206-s-cust2','venue_staff_grant','venue',tap._venue206(),jsonb_build_object('identity_id', tap._CUST2(), 'role', 'venue_scanner')), 'succeeded', 'I60: a customer identity can be granted');
SELECT is(tap._ea206('k206-s-cust2-revoke','venue_staff_revoke','venue',tap._venue206(),jsonb_build_object('identity_id', tap._CUST2(), 'role', 'venue_scanner')), 'succeeded', 'I61: ...and revoked');
SELECT is(tap._ea206('k206-r-invrevoke','org_invite_revoke','org_invite',tap._inv206(),'{}'), 'succeeded', 'I62: org_invite_revoke still works for a platform_admin');

-- ── I.8 platform-role grants stay fail-closed (PFA-4) ──
SELECT is(tap._ea206('k206-p-grant','platform_role_grant','none',NULL,jsonb_build_object('identity_id', tap._CUST2(), 'role', 'platform_support', 'reason_code', 'hire'),'hire'), 'awaiting_approval', 'I63: held');
SELECT tap.logout(); SELECT tap.login(tap._C206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-p-grant','approve','ok'), 'rejected:precondition', 'I64: approving runs the verb, which is fail-closed');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.platform_role WHERE identity_id = tap._CUST2()), 0, 'I65: PFA-4 PRESERVED — no platform role was minted');

-- ── I.9 held invitee references: never readable, released at every terminal state (ruling 6) ──
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-h-deny','org_owner_bootstrap_invite','organization',tap._org('Boot Three'),'{"invitee_ref":"deny.me@example.com"}','x'), 'awaiting_approval', 'I66: a request to deny');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action_invitee i JOIN ops.action x ON x.id = i.action_id WHERE x.idempotency_key = 'k206-h-deny'), 1, 'I67: its reference is held while it waits');
SELECT tap.login(tap._C206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-h-deny','deny','not verified'), 'rejected:denied', 'I68: denied');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action_invitee i JOIN ops.action x ON x.id = i.action_id WHERE x.idempotency_key = 'k206-h-deny'), 0, 'I69: a DENIAL releases the reference (terminal-state trigger)');
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-h-expire','org_owner_bootstrap_invite','organization',tap._org('Boot Three'),'{"invitee_ref":"expire.me@example.com"}','x'), 'awaiting_approval', 'I70: a request that will expire');
SELECT tap.logout();
UPDATE ops.approval SET expires_at = now() - interval '1 hour' WHERE action_id = tap._aid206('k206-h-expire');
SELECT is((SELECT count(*)::int FROM ops.action_invitee WHERE action_id = tap._aid206('k206-h-expire')), 1,
  'I71: LAZY EXPIRY, DOCUMENTED — an expired request nobody has touched still holds its reference (no job is added)');
SELECT tap.login(tap._C206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-h-expire','approve','late'), 'rejected:approval_expired', 'I72: touching it records the expiry');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action_invitee WHERE action_id = tap._aid206('k206-h-expire')), 0, 'I73: ...and that terminal state releases the reference');
SELECT is((SELECT array_agg(x.idempotency_key ORDER BY x.idempotency_key) FROM ops.action_invitee i JOIN ops.action x ON x.id = i.action_id),
  ARRAY['k206-b-recover'], 'I74: the only reference still held is the recovery request that is genuinely waiting');

-- ── I.10 no operator can read an invitee's address through the logs (owner item 1) ──
CREATE FUNCTION tap._readall206() RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v text := ''; j jsonb; cur text; it jsonb;
BEGIN
  cur := NULL;
  LOOP
    j := ops.list_actions('{}'::jsonb, cur, 200);
    v := v || (j -> 'items')::text;
    FOR it IN SELECT * FROM jsonb_array_elements(j -> 'items') LOOP
      IF it ->> 'action_type' = 'org_owner_bootstrap_invite' THEN v := v || ops.action_detail((it ->> 'id')::uuid)::text; END IF;
    END LOOP;
    cur := j ->> 'next_cursor'; EXIT WHEN cur IS NULL;
  END LOOP;
  cur := NULL;
  LOOP
    j := ops.audit_log(cur, 200);
    v := v || (j -> 'items')::text;
    cur := j ->> 'next_cursor'; EXIT WHEN cur IS NULL;
  END LOOP;
  RETURN v || ops.list_approvals('all')::text;
END $f$;
SELECT tap.login(tap._S206()); SELECT tap._aal2();
SELECT is(tap._inv206('k206-b-inv2','invite_delivery_support'), 'later.c@example.com', 'I75: after dispatch the reveal reads the domain invite (delivery support)');
SELECT matches(tap._inv206('k206-b-inv2','curiosity'), 'reason_code must be', 'I76: the reveal''s reason is a closed set');
SELECT ok(tap._readall206() !~* '(cust\.one|cust\.two|later\.[bcs]|late\.owner|new\.owner|deny\.me|expire\.me)@example\.com',
  'I77: a SUPPORT operator paging through every action, approval and audit page finds no invitee address');
SELECT ok(tap._readall206() ~ 'c\*\*\*@example\.com' AND tap._readall206() ~ 'l\*\*\*@example\.com',
  'I78: ...while the masked labels are there');
SELECT tap.logout(); SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT ok(tap._readall206() !~* '(cust\.one|cust\.two|later\.[bcs]|late\.owner|new\.owner|deny\.me|expire\.me)@example\.com', 'I79: ...nor does a platform_admin');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action x WHERE x::text ~* '(cust\.one|cust\.two|later\.[bcs]|late\.owner|new\.owner|deny\.me|expire\.me)@example\.com')
        + (SELECT count(*)::int FROM ops.audit u WHERE u::text ~* '(cust\.one|cust\.two|later\.[bcs]|late\.owner|new\.owner|deny\.me|expire\.me)@example\.com'), 0,
  'I80: no row of ops.action or ops.audit holds one, in any column');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action = 'action_invitee_read' AND (after ->> 'found')::boolean), 2, 'I81: each successful reveal wrote its audit row');
SELECT ok(NOT has_table_privilege('anon','ops.action_invitee','SELECT') AND NOT has_table_privilege('authenticated','ops.action_invitee','SELECT')
          AND NOT has_table_privilege('service_role','ops.action_invitee','SELECT'), 'I82: no API role can read held references');
-- its own held row, so the refusal is exercised whatever the flow above left held
INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, params, requested_by, state)
VALUES ('k206-fx-held', 'org_owner_bootstrap_invite', 'organization', tap._org206(), '{"invitee_label":"f***@example.com"}', tap._A206(), 'awaiting_approval');
INSERT INTO ops.action_invitee (action_id, invitee_ref) VALUES (tap._aid206('k206-fx-held'), 'fixture.held@example.com');
SELECT matches(tap._try206($$ UPDATE ops.action_invitee SET invitee_ref = 'someone.else@example.com' WHERE action_id = tap._aid206('k206-fx-held') $$), 'append_only', 'I83: a held reference cannot be changed');

-- ── I.11 console-only verbs, and the frozen functions they must not disturb (principle 4; PFA-1 gaps) ──
SELECT is((SELECT string_agg(f || ':' || r, ',') FROM unnest(array['kernel.bootstrap_organization(text,text,text)','kernel.invite_bootstrap_owner(uuid,text,text)',
            'catalog.bootstrap_venue(uuid,text,text,text,text)','ops.identity_holds_platform_authority(uuid)','ops.action_invitee_release_on_terminal()']) f
            CROSS JOIN unnest(array['public','anon','authenticated','service_role']) r WHERE has_function_privilege(r, f::regprocedure, 'EXECUTE')), NULL,
  'I84: A1–A3 and the two helpers are executable by none of public, anon, authenticated or service_role (the service_role gap closed PER FUNCTION)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            WHERE n.nspname = 'catalog' AND a.privilege_type = 'EXECUTE'
              AND (a.grantee = 0 OR a.grantee = (SELECT oid FROM pg_roles WHERE rolname = 'anon'))), 0,
  'I85: the CATALOG gap — zero PUBLIC or anon EXECUTE on any catalog function (suite 140''s sweep does not cover catalog)');
SELECT is((SELECT md5(prosrc) || ' ' || proacl::text FROM pg_proc WHERE oid = 'catalog.create_venue(uuid,text,text,text,text)'::regprocedure),
  '2aa29fe42d13160d12a2f0022565f743 {postgres=X/postgres,authenticated=X/postgres}',
  'I86: A3 did not touch catalog.create_venue — body and grants are 078''s');
SELECT is((SELECT proacl::text FROM pg_proc WHERE oid = 'kernel.accept_org_invite(uuid,text)'::regprocedure),
  '{postgres=X/postgres,authenticated=X/postgres}', 'I87: A4 kept accept_org_invite''s grants exactly');

-- ── I.12 the membership paths the acceptance guard does NOT close (ruling 7) — facts, not decisions ──
SELECT is(tap._platform_members(), 0,
  'I88: after everything above, no identity holding platform authority is an organisation member or venue staff anywhere in this suite''s world');
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is((kernel.create_organization('Direct Path LLC', 'Direct Path', 'k206-direct')) ->> 'status', 'ok',
  'I89: OPEN (A5 proposed) — a platform identity can still call the frozen self-service kernel.create_organization directly over RPC');
SELECT tap.logout();
SELECT is(tap._platform_members(), 1,
  'I90: ...and becomes org_owner of that organisation: "operators are never members" is NOT established by A4 alone');

-- ── I.13 a failing verb's outcome never carries the address, however the verb spells it (A's review of 8ecc929, point c) ──
-- The outcome is written to ops.action and ops.audit, which every operator reads. An exact-string mask misses a
-- message that quotes the reference lower-cased or trimmed, so dispatch records fixed text instead.
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-c-mask','org_owner_bootstrap_invite','organization',tap._org('Boot Three'),'{"invitee_ref":"  Pad.Case@Example.COM "}','x'), 'awaiting_approval',
  'I99: requested for a padded, mixed-case address nobody holds yet');
SELECT tap.logout();
UPDATE auth.users SET email = 'pad.case@example.com' WHERE id = tap._B206();
SELECT tap.login(tap._B206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-c-mask','approve','ok'), 'rejected:precondition', 'I100: the approver now holds it, lower-cased, and the verb refuses');
SELECT tap.logout();
SELECT is((SELECT result ->> 'message' FROM ops.action WHERE idempotency_key = 'k206-c-mask'), 'precondition_failed: self_invite',
  'I101: the recorded outcome is fixed text for the refusal, not the verb''s own message');
SELECT is((SELECT count(*)::int FROM ops.action x WHERE x::text ~* 'pad\.case@example\.com')
        + (SELECT count(*)::int FROM ops.audit u WHERE u::text ~* 'pad\.case@example\.com'), 0,
  'I102: no row of ops.action or ops.audit holds that address, in any spelling');

SELECT * FROM finish();
ROLLBACK;
