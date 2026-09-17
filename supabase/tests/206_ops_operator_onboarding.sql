-- 206_ops_operator_onboarding.sql — migration 138: the console can SEE
-- organisations, venues, members and staff, and can ACT on them only through the
-- audited action framework. Runs as postgres inside BEGIN … ROLLBACK like every
-- suite here. Contract: docs/venue-dashboard/OPERATOR_ONBOARDING_CONTRACT_D_20260917.md
BEGIN;
SELECT plan(118);
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

-- ── D. the guard that makes the routine/elevating split a control ────────────
SELECT is(tap._pc206('{"action_type":"org_member_role_change","params":{"new_role":"org_admin"}}'), 'precondition',
  'D1: a routine role-change carrying org_admin is REFUSED (use org_member_elevate)');
SELECT is(tap._pc206('{"action_type":"org_member_role_change","params":{"new_role":"org_member"}}'), 'allowed',
  'D2: ...and a genuinely routine role-change passes');
SELECT is(tap._pc206('{"action_type":"org_member_elevate","params":{"new_role":"org_finance"}}'), 'precondition',
  'D3: the ELEVATING type carrying a non-elevating role is REFUSED — without this the caller picks whether approval applies');
SELECT is(tap._pc206('{"action_type":"org_member_elevate","params":{"new_role":"org_owner"}}'), 'allowed',
  'D4: ...and a genuine elevation passes');
SELECT is(tap._pc206('{"action_type":"org_member_invite","params":{"role":"org_owner"}}'), 'precondition',
  'D5: inviting at org_owner through the routine type is REFUSED');
SELECT is(tap._pc206('{"action_type":"org_member_invite_admin","params":{"role":"org_member"}}'), 'precondition',
  'D6: org_member_invite_admin carrying a routine role is REFUSED');
SELECT is(tap._pc206('{"action_type":"org_member_invite_admin","params":{"role":"org_admin"}}'), 'allowed',
  'D7: ...and a genuine admin invite passes');
SELECT is(tap._pc206('{"action_type":"payout_release"}'), 'precondition',
  'D8: 118''s own payout_release arm still runs — 138 redefined from 118''s body, not 115''s');

-- ── E. approval set and role gating ──────────────────────────────────────────
SELECT ok(ops.action_requires_approval('venue_approve') AND ops.action_requires_approval('platform_role_grant')
          AND ops.action_requires_approval('org_member_elevate') AND ops.action_requires_approval('org_member_invite_admin'),
  'E1: the owner''s three all require two-person approval');
SELECT ok(ops.action_requires_approval('payout_release') AND ops.action_requires_approval('refund_execute'),
  'E2: 115''s two money approvals are preserved');
SELECT ok(NOT ops.action_requires_approval('org_member_role_change') AND NOT ops.action_requires_approval('org_member_invite')
          AND NOT ops.action_requires_approval('venue_create') AND NOT ops.action_requires_approval('org_create'),
  'E3: routine onboarding actions are NOT behind approval');
SELECT is(ops.action_allowed_roles('platform_role_grant'), ARRAY['platform_admin'],
  'E4: granting a platform role is platform_admin only');
SELECT is(ops.action_allowed_roles('venue_staff_grant'), ARRAY['platform_admin','platform_support'],
  'E5: venue staff grants are the support-reachable day-to-day');
SELECT is(ops.action_allowed_roles('org_member_elevate'), ARRAY['platform_admin'],
  'E6: elevation is platform_admin only, on top of the approval');
SELECT is(ops.action_allowed_roles('payout_release'), ARRAY['platform_admin'],
  'E7: 115''s money role gating is preserved');

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

-- ── I. THROUGH THE FRONT DOOR (F-138-2 / F-138-5 / F-138-6) ──────────────────
-- Everything above this line calls a component directly. That is how 138's first cut
-- passed forty-five assertions while being inert: ops.execute_action is the only door
-- and validates against hardcoded lists, so all fourteen types answered 'unknown
-- action_type' and no test noticed. Then the routine-type guard sat only in precheck,
-- which runs only for approval-gated types. Then the guard read coalesce(new_role, role)
-- while the invite arm read role, so a decoy key walked an org_owner invite past it.
-- Nothing below calls a component. Every action goes through ops.execute_action and every
-- decision through ops.approve_action as an authenticated operator at aal2 — the console's
-- path — and every outcome is read back from ops.action AND from the domain table it
-- should (or must not) have changed. A status alone is not evidence of an effect.
--
-- Cast (all written as postgres; kernel.platform_role and org tables carry no grant to authenticated):
--   A  tap.admin_user()  platform_admin (admin_users bootstrap); org_owner of org X
--   B  5555…             platform_admin (kernel.platform_role);  org_owner of org X — the second approver
--   C  6666…             platform_admin; a member of NOTHING    — domain controls under the framework
--   S  7777…             platform_support
--   8888… 9999… abab…    org_member of org X (remove / elevate targets);  cdcd… a platform-role grantee
CREATE FUNCTION tap._A206() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT tap.admin_user() $f$;
CREATE FUNCTION tap._B206() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '55555555-5555-5555-5555-555555555555'::uuid $f$;
CREATE FUNCTION tap._C206() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '66666666-6666-6666-6666-666666666666'::uuid $f$;
CREATE FUNCTION tap._S206() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '77777777-7777-7777-7777-777777777777'::uuid $f$;
CREATE FUNCTION tap._orgX()  RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'dddddddd-0000-0000-0000-00000000a206'::uuid $f$;
CREATE FUNCTION tap._venX()  RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'eeeeeeee-0000-0000-0000-00000000a206'::uuid $f$;
CREATE FUNCTION tap._invX()  RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'ffffffff-0000-0000-0000-00000000a206'::uuid $f$;

SELECT tap.logout();
INSERT INTO auth.users (id, email, aud, role, created_at)
SELECT u.id, u.id::text || '@test.local', 'authenticated', 'authenticated', now()
  FROM (VALUES (tap._B206()), (tap._C206()), (tap._S206()),
               ('88888888-8888-8888-8888-888888888888'::uuid), ('99999999-9999-9999-9999-999999999999'::uuid),
               ('abababab-abab-abab-abab-abababababab'::uuid), ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd'::uuid)) AS u(id)
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role)
VALUES (tap._B206(), 'platform_admin'), (tap._C206(), 'platform_admin'), (tap._S206(), 'platform_support');
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES (tap._orgX(), 'Org X Holdings LLC', 'Org X', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  (tap._orgX(), tap._A206(), 'org_owner'), (tap._orgX(), tap._B206(), 'org_owner'),
  (tap._orgX(), tap.seller(), 'org_member'), (tap._orgX(), '88888888-8888-8888-8888-888888888888', 'org_member'),
  (tap._orgX(), '99999999-9999-9999-9999-999999999999', 'org_member'), (tap._orgX(), 'abababab-abab-abab-abab-abababababab', 'org_member');
INSERT INTO kernel.org_invite (invite_id, org_id, invitee_ref, role, status, invited_by, expires_at, command_idempotency_key)
VALUES (tap._invX(), tap._orgX(), 'revoke.me@example.com', 'org_member', 'pending', tap._A206(), now() + interval '7 days', 'k206-invX');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, address, approval_status)
VALUES (tap._venX(), tap._orgX(), 'Venue X', 'brickell', '1 X St', 'pending');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES (tap._venX(), tap.other_user(), 'venue_box_office');

CREATE FUNCTION tap._ea206(k text, t text, sk text, sid uuid, prm jsonb, rsn text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  v := ops.execute_action(k, t, sk, sid, coalesce(prm,'{}'::jsonb), rsn);
  RETURN coalesce(v ->> 'status', '(null)');
EXCEPTION WHEN OTHERS THEN RETURN 'RAISED: ' || SQLERRM;
END $f$;
-- an approver names the action by id; ops.action is not readable by authenticated, so only the lookup is postgres
CREATE FUNCTION tap._aid206(k text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $f$ SELECT id FROM ops.action WHERE idempotency_key = k $f$;
CREATE FUNCTION tap._apr206(k text, decision text, rsn text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  v := ops.approve_action(tap._aid206(k), decision, rsn);
  RETURN coalesce(v ->> 'status', '(null)') || coalesce(':' || (v ->> 'reject_reason'), '');
EXCEPTION WHEN OTHERS THEN RETURN 'RAISED: ' || SQLERRM;
END $f$;
-- read as postgres: the final state of an action, by key
CREATE FUNCTION tap._st206(k text) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT coalesce((SELECT state || coalesce(':' || reject_reason, '') FROM ops.action WHERE idempotency_key = k), '(no row)') $f$;
CREATE FUNCTION tap._role206(o uuid, i uuid) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT coalesce((SELECT role FROM kernel.org_member WHERE org_id = o AND identity_id = i), '(not a member)') $f$;

-- ── I.1 routine versus elevating: refused AT THE DOOR, before any row exists ──
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT matches(tap._ea206('k206-g-rc-admin','org_member_role_change','organization',tap._orgX(),
  jsonb_build_object('identity_id', tap.seller(), 'new_role', 'org_admin')), 'requires two-person approval: request org_member_elevate',
  'I1: a ROUTINE role change to org_admin is refused at the door (precheck never runs for this type)');
SELECT matches(tap._ea206('k206-g-rc-owner','org_member_role_change','organization',tap._orgX(),
  jsonb_build_object('identity_id', tap.seller(), 'new_role', 'org_owner')), 'requires two-person approval: request org_member_elevate',
  'I2: ...and to org_owner');
SELECT matches(tap._ea206('k206-g-inv-admin','org_member_invite','organization',tap._orgX(),
  '{"invitee_ref":"g.admin@example.com","role":"org_admin"}'), 'requires two-person approval: request org_member_invite_admin',
  'I3: a ROUTINE invite at org_admin is refused at the door');
SELECT matches(tap._ea206('k206-g-inv-owner','org_member_invite','organization',tap._orgX(),
  '{"invitee_ref":"g.owner@example.com","role":"org_owner"}'), 'requires two-person approval: request org_member_invite_admin',
  'I4: ...and at org_owner');
SELECT matches(tap._ea206('k206-g-inv-decoy','org_member_invite','organization',tap._orgX(),
  '{"invitee_ref":"g.decoy@example.com","new_role":"org_member","role":"org_owner"}'), 'org_member_invite takes params.role only',
  'I5 (F-138-6): a routine invite with a decoy new_role beside role=org_owner is refused — the arm reads role, so the guard must too; this walked past a coalesce and wrote an org_owner invite with no approver');
SELECT matches(tap._ea206('k206-g-rc-decoy','org_member_role_change','organization',tap._orgX(),
  jsonb_build_object('identity_id', tap.seller(), 'new_role', 'org_member', 'role', 'org_owner')), 'org_member_role_change takes params.new_role only',
  'I6 (F-138-6): a role change carrying the other key is refused, so guard and arm can never read different values');
SELECT matches(tap._ea206('k206-g-el-routine','org_member_elevate','organization',tap._orgX(),
  jsonb_build_object('identity_id', tap.seller(), 'new_role', 'org_finance'), 'x'), 'org_member_elevate is only for org_owner or org_admin',
  'I7: the ELEVATING type carrying a routine role is refused — the approval slot cannot launder a routine change');
SELECT matches(tap._ea206('k206-g-el-none','org_member_elevate','organization',tap._orgX(),
  jsonb_build_object('identity_id', tap.seller()), 'x'), 'org_member_elevate is only for org_owner or org_admin',
  'I8: ...nor carrying no role at all');
SELECT matches(tap._ea206('k206-g-ia-routine','org_member_invite_admin','organization',tap._orgX(),
  '{"invitee_ref":"g.ia@example.com","role":"org_member"}', 'x'), 'org_member_invite_admin is only for org_owner or org_admin',
  'I9: org_member_invite_admin carrying a routine role is refused');
SELECT matches(tap._ea206('k206-g-ia-decoy','org_member_invite_admin','organization',tap._orgX(),
  '{"invitee_ref":"g.iadecoy@example.com","new_role":"org_admin","role":"org_member"}', 'x'), 'org_member_invite_admin takes params.role only',
  'I10 (F-138-6): ...including with a decoy new_role — refused at the door, not left to the second-layer precheck');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key LIKE 'k206-g-%'), 0,
  'I11: none of I1–I10 created an ops.action row — they were refused before the insert, on the path every action takes');
SELECT is((SELECT count(*)::int FROM kernel.org_invite WHERE invitee_ref LIKE 'g.%@example.com')
        + (SELECT count(*)::int FROM kernel.org_member WHERE org_id = tap._orgX() AND role IN ('org_owner','org_admin')), 2,
  'I12: ...and nothing reached the domain: no invite, and org X still has exactly its two fixture owners');

-- ── I.2 required reasons: exactly the owner's six, at the door ───────────────
CREATE FUNCTION tap._reasonset206() RETURNS text[] LANGUAGE plpgsql AS $f$
DECLARE r record; v text[] := '{}';
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('org_create','none',NULL::uuid,'{}'::jsonb), ('org_update','organization',tap._orgX(),'{}'),
      ('org_status_set','organization',tap._orgX(),'{}'), ('org_member_invite','organization',tap._orgX(),'{}'),
      ('org_member_invite_admin','organization',tap._orgX(),'{"role":"org_admin"}'),
      ('org_member_role_change','organization',tap._orgX(),'{}'), ('org_member_elevate','organization',tap._orgX(),'{"new_role":"org_admin"}'),
      ('org_member_remove','organization',tap._orgX(),'{}'), ('org_invite_revoke','org_invite','ffffffff-0000-0000-0000-00000000e206','{}'),
      ('platform_role_grant','none',NULL,'{}'), ('venue_create','organization',tap._orgX(),'{}'),
      ('venue_approve','venue',tap._venX(),'{}'), ('venue_staff_grant','venue',tap._venX(),'{}'),
      ('venue_staff_revoke','venue',tap._venX(),'{}')) t(typ, sk, sid, prm)
  LOOP
    BEGIN
      PERFORM ops.execute_action('k206-rs-' || r.typ, r.typ, r.sk, r.sid, r.prm, NULL);
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'invalid_input: a reason is required for %' THEN v := v || r.typ; END IF;
    END;
  END LOOP;
  RETURN (SELECT array_agg(x ORDER BY x) FROM unnest(v) x);
END $f$;
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._reasonset206(),
  ARRAY['org_member_elevate','org_member_invite_admin','org_member_remove','org_status_set','platform_role_grant','venue_approve'],
  'I13: across all fourteen types sent WITHOUT a reason, exactly the six the owner named are refused — no more, no fewer');
SELECT matches(tap._ea206('k206-rs-blank','org_status_set','organization',tap._orgX(),
  '{"target_status":"suspended","reason_code":"x"}', '   '), 'a reason is required for org_status_set',
  'I14: a whitespace-only reason is no reason');

-- ── I.3 role gating at the door, and the domain's own check behind it ───────
SELECT tap.logout();
CREATE FUNCTION tap._roleset206() RETURNS text[] LANGUAGE plpgsql AS $f$
DECLARE r record; v text[] := '{}';
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('org_create','none',NULL::uuid,'{}'::jsonb), ('org_update','organization',tap._orgX(),'{}'),
      ('org_status_set','organization',tap._orgX(),'{}'), ('org_member_invite','organization',tap._orgX(),'{}'),
      ('org_member_invite_admin','organization',tap._orgX(),'{"role":"org_admin"}'),
      ('org_member_role_change','organization',tap._orgX(),'{}'), ('org_member_elevate','organization',tap._orgX(),'{"new_role":"org_admin"}'),
      ('org_member_remove','organization',tap._orgX(),'{}'), ('org_invite_revoke','org_invite','ffffffff-0000-0000-0000-00000000e206','{}'),
      ('platform_role_grant','none',NULL,'{}'), ('venue_create','organization',tap._orgX(),'{}'),
      ('venue_approve','venue',tap._venX(),'{}'), ('venue_staff_grant','venue',tap._venX(),'{}'),
      ('venue_staff_revoke','venue',tap._venX(),'{}')) t(typ, sk, sid, prm)
  LOOP
    BEGIN
      PERFORM ops.execute_action('k206-rg-' || r.typ, r.typ, r.sk, r.sid, r.prm, 'role gating probe');
    EXCEPTION WHEN OTHERS THEN
      IF SQLSTATE = '42501' AND SQLERRM LIKE 'insufficient_privilege: platform_support may not perform %' THEN v := v || r.typ; END IF;
    END;
  END LOOP;
  RETURN (SELECT array_agg(x ORDER BY x) FROM unnest(v) x);
END $f$;
SELECT tap.logout(); SELECT tap.login(tap._S206()); SELECT tap._aal2();
SELECT is(tap._roleset206(),
  ARRAY['org_create','org_member_elevate','org_member_invite_admin','org_member_remove','org_member_role_change',
        'org_status_set','org_update','platform_role_grant','venue_approve','venue_create'],
  'I15: platform_support is refused AT THE DOOR for exactly the ten platform_admin-only types');
-- support passes the door for its four; each verb's own check still decides (contract §3.2)
SELECT is(tap._ea206('k206-sp-invite','org_member_invite','organization',tap._orgX(),'{"invitee_ref":"s.inv@example.com","role":"org_member"}'), 'failed',
  'I16: support''s invite reaches dispatch and the DOMAIN refuses it (support holds no org role)');
SELECT is(tap._ea206('k206-sp-revoke','org_invite_revoke','org_invite',tap._invX(),'{}'), 'failed',
  'I17: support''s invite revoke: the domain refuses');
SELECT is(tap._ea206('k206-sp-grant','venue_staff_grant','venue',tap._venX(),jsonb_build_object('identity_id', tap.seller(), 'role', 'venue_finance')), 'failed',
  'I18: support''s staff grant: the domain refuses');
SELECT is(tap._ea206('k206-sp-revokestaff','venue_staff_revoke','venue',tap._venX(),jsonb_build_object('identity_id', tap.other_user(), 'role', 'venue_box_office')), 'failed',
  'I19: support''s staff revoke: the domain refuses');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key LIKE 'k206-sp-%' AND state = 'failed' AND error LIKE 'insufficient_privilege:%'), 4,
  'I20: all four failed on the verb''s insufficient_privilege — the framework ADDS gates, it never replaces a domain check (§3.2). OPEN FOR THE OWNER: support''s four framework permissions do nothing without an org or venue role');
SELECT is((SELECT count(*)::int FROM kernel.org_invite WHERE invitee_ref = 's.inv@example.com')
        + (SELECT count(*)::int FROM kernel.org_invite WHERE invite_id = tap._invX() AND status = 'pending')
        + (SELECT count(*)::int FROM venue.staff_role WHERE venue_id = tap._venX() AND identity_id = tap.seller())
        + (SELECT count(*)::int FROM venue.staff_role WHERE venue_id = tap._venX() AND identity_id = tap.other_user() AND role = 'venue_box_office'), 2,
  'I21: ...and nothing changed: no new invite, invite X still pending, no staff grant, the box-office row still there');

-- ── I.4 every routine type is REACHABLE and DOES what it names ──────────────
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-r-orgcreate','org_create','none',NULL,'{"legal_name":"Created 206 LLC","display_name":"Created 206"}'), 'succeeded', 'I22: org_create succeeds through the door');
SELECT is(tap._ea206('k206-r-orgupdate','org_update','organization',tap._orgX(),'{"patch":{"display_name":"Renamed X"}}'), 'succeeded', 'I23: org_update succeeds');
SELECT is(tap._ea206('k206-r-orgstatus','org_status_set','organization',tap._org206(),'{"target_status":"suspended","reason_code":"test_suspend"}','compliance hold'), 'succeeded', 'I24: org_status_set succeeds (with a reason)');
SELECT is(tap._ea206('k206-r-invite','org_member_invite','organization',tap._orgX(),'{"invitee_ref":"staff.x@example.com","role":"org_member"}'), 'succeeded', 'I25: org_member_invite succeeds');
SELECT is(tap._ea206('k206-r-rolechange','org_member_role_change','organization',tap._orgX(),jsonb_build_object('identity_id', tap.seller(), 'new_role', 'org_finance')), 'succeeded', 'I26: org_member_role_change succeeds');
SELECT is(tap._ea206('k206-r-remove','org_member_remove','organization',tap._orgX(),'{"identity_id":"88888888-8888-8888-8888-888888888888"}','left the company'), 'succeeded', 'I27: org_member_remove succeeds (with a reason)');
SELECT is(tap._ea206('k206-r-invrevoke','org_invite_revoke','org_invite',tap._invX(),'{}'), 'succeeded', 'I28: org_invite_revoke succeeds');
SELECT is(tap._ea206('k206-r-venuecreate','venue_create','organization',tap._orgX(),'{"name":"Created Room","neighborhood":"brickell","address":"2 X St"}'), 'succeeded', 'I29: venue_create succeeds');
SELECT is(tap._ea206('k206-r-staffgrant','venue_staff_grant','venue',tap._venX(),jsonb_build_object('identity_id', tap.seller(), 'role', 'venue_scanner')), 'succeeded', 'I30: venue_staff_grant succeeds');
SELECT is(tap._ea206('k206-r-staffrevoke','venue_staff_revoke','venue',tap._venX(),jsonb_build_object('identity_id', tap.other_user(), 'role', 'venue_box_office')), 'succeeded', 'I31: venue_staff_revoke succeeds');
-- a platform_admin who holds no org role in org 206: the verb refuses (§3.2)
SELECT is(tap._ea206('k206-r-nonmember','org_member_invite','organization',tap._org206(),'{"invitee_ref":"nonmember@example.com","role":"org_member"}'), 'failed',
  'I32: a platform_admin with no org role in the organisation reaches dispatch and the DOMAIN refuses the invite (§3.2). OPEN FOR THE OWNER: operators can manage members only of organisations they belong to');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.organization WHERE display_name = 'Created 206' AND status = 'applied'), 1, 'I33: ...the organisation exists, at applied');
SELECT is((SELECT m.role FROM kernel.org_member m JOIN kernel.organization o USING (org_id) WHERE o.display_name = 'Created 206' AND m.identity_id = tap._A206()), 'org_owner',
  'I34: FACT PINNED for the owner: 077''s create_organization makes the CREATING OPERATOR org_owner of the new organisation');
SELECT is((SELECT display_name FROM kernel.organization WHERE org_id = tap._orgX()), 'Renamed X', 'I35: org_update changed the name');
SELECT is((SELECT status FROM kernel.organization WHERE org_id = tap._org206()), 'suspended', 'I36: org_status_set changed the status');
SELECT is((SELECT role || '/' || status FROM kernel.org_invite WHERE invitee_ref = 'staff.x@example.com'), 'org_member/pending', 'I37: org_member_invite wrote the invite at the routine role');
SELECT is(tap._role206(tap._orgX(), tap.seller()), 'org_finance', 'I38: org_member_role_change changed the role');
SELECT is(tap._role206(tap._orgX(), '88888888-8888-8888-8888-888888888888'), '(not a member)', 'I39: org_member_remove removed the member');
SELECT is((SELECT status FROM kernel.org_invite WHERE invite_id = tap._invX()), 'revoked', 'I40: org_invite_revoke revoked the invite');
SELECT is((SELECT approval_status FROM catalog.venue WHERE org_id = tap._orgX() AND name = 'Created Room'), 'draft',
  'I41: venue_create made the venue — at DRAFT (078''s verb). OPEN FOR THE OWNER: list_venues(status => pending), the approval queue, does not show a venue the console just created');
SELECT is((SELECT count(*)::int FROM venue.staff_role WHERE venue_id = tap._venX() AND identity_id = tap.seller() AND role = 'venue_scanner'), 1, 'I42: venue_staff_grant granted the role');
SELECT is((SELECT count(*)::int FROM venue.staff_role WHERE venue_id = tap._venX() AND identity_id = tap.other_user()), 0, 'I43: venue_staff_revoke revoked the role');
SELECT is((SELECT error FROM ops.action WHERE idempotency_key = 'k206-r-nonmember') || ' | invites=' || (SELECT count(*) FROM kernel.org_invite WHERE invitee_ref = 'nonmember@example.com'),
  'insufficient_privilege: org_owner or org_admin required | invites=0', 'I44: ...the refusal is the verb''s own, and no invite was written');
SELECT is((SELECT count(*)::int FROM ops.action x JOIN ops.audit u ON u.action_id = x.id AND u.action = 'action.' || x.action_type AND u.outcome = x.state
            WHERE x.idempotency_key IN ('k206-r-orgcreate','k206-r-orgupdate','k206-r-orgstatus','k206-r-invite','k206-r-rolechange',
                                        'k206-r-remove','k206-r-invrevoke','k206-r-venuecreate','k206-r-staffgrant','k206-r-staffrevoke')), 10,
  'I45: each of the ten dispatched actions wrote its ops.audit row with the outcome');

-- ── I.5 two-person approval: held, never self-approved, applied only by a second operator ──
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-h-venue','venue_approve','venue',tap._venX(),'{"decision":"approved","reason_code":"site_visit"}','site visit done'), 'awaiting_approval', 'I46: venue_approve is HELD');
SELECT is(tap._ea206('k206-h-prole','platform_role_grant','none',NULL,'{"identity_id":"cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd","role":"platform_support","reason_code":"new_hire"}','new hire'), 'awaiting_approval', 'I47: platform_role_grant is HELD');
SELECT is(tap._ea206('k206-h-elevate','org_member_elevate','organization',tap._orgX(),'{"identity_id":"99999999-9999-9999-9999-999999999999","new_role":"org_admin"}','promoting the manager'), 'awaiting_approval', 'I48: org_member_elevate is HELD — although A, as org_owner, could perform it alone');
SELECT is(tap._ea206('k206-h-invadmin','org_member_invite_admin','organization',tap._orgX(),'{"invitee_ref":"founder.x@example.com","role":"org_owner"}','co-founder joining'), 'awaiting_approval', 'I49: org_member_invite_admin is HELD — although A could invite alone');
SELECT is(tap._ea206('k206-h-invadmin2','org_member_invite_admin','organization',tap._orgX(),'{"invitee_ref":"denied.x@example.com","role":"org_admin"}','to be denied'), 'awaiting_approval', 'I50: an org_admin invite is held the same way');
SELECT matches(tap._apr206('k206-h-venue','approve','mine'), 'self_approval', 'I51: the requester cannot approve their own venue approval');
SELECT matches(tap._apr206('k206-h-prole','approve','mine'), 'self_approval', 'I52: ...nor their own platform-role grant');
SELECT matches(tap._apr206('k206-h-elevate','approve','mine'), 'self_approval', 'I53: ...nor their own elevation');
SELECT matches(tap._apr206('k206-h-invadmin','approve','mine'), 'self_approval', 'I54: ...nor their own admin invite');
SELECT tap.logout();
SELECT is((SELECT approval_status FROM catalog.venue WHERE venue_id = tap._venX()), 'pending', 'I55: NO SECOND APPROVER, NO EFFECT: venue X is still pending');
SELECT is((SELECT count(*)::int FROM kernel.platform_role WHERE identity_id = 'cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd'), 0, 'I56: NO SECOND APPROVER, NO EFFECT: no platform role granted');
SELECT is(tap._role206(tap._orgX(), '99999999-9999-9999-9999-999999999999'), 'org_member', 'I57: NO SECOND APPROVER, NO EFFECT: the member is still org_member');
SELECT is((SELECT count(*)::int FROM kernel.org_invite WHERE invitee_ref = 'founder.x@example.com'), 0, 'I58: NO SECOND APPROVER, NO EFFECT: no org_owner invite exists');
SELECT is((SELECT count(*)::int FROM ops.approval p JOIN ops.action x ON x.approval_id = p.id
            WHERE x.idempotency_key IN ('k206-h-venue','k206-h-prole','k206-h-elevate','k206-h-invadmin','k206-h-invadmin2')
              AND p.state = 'pending' AND p.requested_by = tap._A206() AND x.requested_by = tap._A206()), 5,
  'I59: each held action has a pending approval, and both rows record the requester (owner ruling 2026-09-17)');
SELECT tap.login(tap._B206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-h-venue','approve','second founder agrees'), 'succeeded', 'I60: a second platform_admin approves venue_approve and it runs');
SELECT is(tap._apr206('k206-h-prole','approve','second founder agrees'), 'rejected:precondition', 'I61: approving platform_role_grant runs the verb, which is FAIL-CLOSED pending PFA-4');
SELECT is(tap._apr206('k206-h-elevate','approve','second founder agrees'), 'succeeded', 'I62: a second operator who is org_owner approves the elevation and it runs');
SELECT is(tap._apr206('k206-h-invadmin','approve','second founder agrees'), 'succeeded', 'I63: ...and the org_owner invite');
SELECT is(tap._apr206('k206-h-invadmin2','deny','not this person'), 'rejected:denied', 'I64: a denial ends it');
SELECT tap.logout();
SELECT is((SELECT approval_status FROM catalog.venue WHERE venue_id = tap._venX()), 'approved', 'I65: venue X is approved');
SELECT is((SELECT count(*)::int FROM kernel.platform_role WHERE identity_id = 'cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd')::text || ' | ' || (SELECT result ->> 'message' FROM ops.action WHERE idempotency_key = 'k206-h-prole'),
  '0 | precondition_failed: dual_control_unavailable — platform-role grants are fail-closed pending owner signature on PFA-4 (see docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md)',
  'I66: FACT PINNED for the owner: no platform role can be granted through the console until PFA-4 is signed');
SELECT is(tap._role206(tap._orgX(), '99999999-9999-9999-9999-999999999999'), 'org_admin', 'I67: the member is org_admin');
SELECT is((SELECT role || '/' || status FROM kernel.org_invite WHERE invitee_ref = 'founder.x@example.com'), 'org_owner/pending', 'I68: the org_owner invite exists');
SELECT is((SELECT count(*)::int FROM kernel.org_invite WHERE invitee_ref = 'denied.x@example.com'), 0, 'I69: the denied invite does not');
SELECT is((SELECT p.requested_by::text || '>' || p.decided_by::text || ':' || p.state FROM ops.approval p JOIN ops.action x ON x.approval_id = p.id WHERE x.idempotency_key = 'k206-h-venue'),
  tap._A206()::text || '>' || tap._B206()::text || ':approved', 'I70: the approval row names requester AND approver');
-- the domain's check under the framework: an approver with no org role cannot complete an elevation (§3.2)
SELECT tap.login(tap._A206()); SELECT tap._aal2();
SELECT is(tap._ea206('k206-h-elevate-c','org_member_elevate','organization',tap._orgX(),'{"identity_id":"abababab-abab-abab-abab-abababababab","new_role":"org_admin"}','x'), 'awaiting_approval', 'I71: a second elevation is held');
SELECT tap.logout(); SELECT tap.login(tap._C206()); SELECT tap._aal2();
SELECT is(tap._apr206('k206-h-elevate-c','approve','ok by me'), 'failed', 'I72: a platform_admin with no org role approves it, and the VERB refuses to run it (§3.2)');
SELECT tap.logout();
SELECT is(tap._role206(tap._orgX(), 'abababab-abab-abab-abab-abababababab') || ' | ' || (SELECT error FROM ops.action WHERE idempotency_key = 'k206-h-elevate-c'),
  'org_member | insufficient_privilege: org_owner or org_admin required',
  'I73: ...so the member is unchanged. OPEN FOR THE OWNER: an elevation completes only when the APPROVER is org_owner or org_admin of that organisation');

SELECT * FROM finish();
ROLLBACK;
