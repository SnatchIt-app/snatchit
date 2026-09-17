-- 206_ops_operator_onboarding.sql — migration 138: the console can SEE
-- organisations, venues, members and staff, and can ACT on them only through the
-- audited action framework. Runs as postgres inside BEGIN … ROLLBACK like every
-- suite here. Contract: docs/venue-dashboard/OPERATOR_ONBOARDING_CONTRACT_D_20260917.md
BEGIN;
SELECT plan(44);
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
SELECT is((SELECT invitee_label FROM ops.list_org_invites(tap._org206())), 'h***@example.com',
  'G4: a PENDING invite shows the approved mask — it has no identity UUID yet, and invitee_ref IS the address');
SELECT is((SELECT invite_id FROM ops.list_org_invites(tap._org206())), tap._inv206(),
  'G5: ...always beside the stable invite_id, so two identical masks stay distinguishable (owner ruling)');
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

SELECT * FROM finish();
ROLLBACK;
