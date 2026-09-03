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
-- 2026-09-02 (package 093): 188 -> 198. Ten new assertions, no removals and no
-- relaxations: L0a-L0e cover the four gates rulings A7/A9 added to
-- kernel.set_org_connect_ref; L0f-L0h + L1a cover the connect-STAGING provenance
-- control (ruling A7) that closed the acct_ORPHANATTACKER P0; A14a names the seven
-- kernel functions 093 adds, with their grant class.
SELECT plan(198);

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
  -- 2026-08-31 (package 079): 12 -> 15. kernel.tickets, ticket_ownership_log
  -- and door_freeze_override are 079's three tables (plan §8/079; §13.5-B).
  -- 2026-09-02 (package 088): 26 -> 27. kernel.dispute_native (R-40).
  -- 2026-09-02 (package 091): 27 -> 28 (kernel.reserve stub).
  28, '077 A13: exactly TWENTY-EIGHT kernel tables (27 post-088 + 091''s reserve stub)');

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel'),
  -- 2026-08-31 (package 078): 40 -> 41. kernel.money_role_grant_matured is
  -- authored in 078, not 077, by SEAM-1 max(077,078)=078 — it reads
  -- kernel.org_member (077) AND catalog.platform_config plus its
  -- authn.money_role_maturity_hours seed (078). The count is raised by exactly
  -- one and the two EXECUTE closures below still name every member, so this
  -- stays exact-by-name and cannot pass vacuously.
  -- 2026-08-31 (package 079): 41 -> 48. The seven of 079: is_transfer_frozen,
  -- lock_ticket, unlock_ticket, mark_ticket_scanned, sweep_expired_ticket_atoms,
  -- tg_custody_head_is_ledger_tail and raise_override_forward_only.
  -- 2026-08-31 (package 080): 48 -> 52 — the four §1.1a/§2.2 predicates
  -- (has_venue_role, has_event_role, has_org_role_over_venue,
  -- has_org_role_over_event), named in 144 A16-A19.
  -- 2026-09-01 (package 086): 94 -> 99. Five kernel door/scan fns:
  -- assert_door_session, grant/revoke_door_freeze_override,
  -- sweep_expired_door_overrides, revoke_signing_key (PFA-17). Named in F2/F3.
  -- 2026-09-01 (package 087): 99 -> 103. Four kernel settlement fns: the two SEAM-2
  -- seam stubs (royalty/commission lines), close_settlement, request_org_payout.
  -- 2026-09-02 (package 088): 103 -> 107. transfer_ticket_ownership (the engine),
  -- record_dispute_native, mark_dispute_state, resolve_dispute_native (PFA-31 parked).
  -- 2026-09-02 (package 090): 107 -> 109. is_promoter_for_event (§1.1c) + pay_promoter_commission (§20.7.2).
  -- 2026-09-02 (package 093): 109 -> 116. RATIFIED CONTRACT CHANGE. SEVEN added,
  -- zero removed — measured pre/post on two rehearsal databases built from the same
  -- chain, one stopped at 092 and one with 093. Both this query and
  -- information_schema.routines return 109 pre-093 and 116 post-093, so the two
  -- catalogs agree exactly and none of the seven is invisible to this assertion.
  -- kernel.settlement_royalty_lines was REPLACED, not added, and moves nothing.
  -- The seven are enumerated by NAME in A14a below — never accepted as a bare
  -- delta — and each is pinned by grant class in F2/F3.
  116, '077 A14: exactly 116 kernel functions (109 post-090 + 093''s seven; settlement_royalty_lines was replaced, not added)');
-- A14a: the seven BY NAME with their grant class and definer flag, so that moving
-- this census forces the mover to say WHICH function they added rather than bumping
-- an integer. Grant class is included because a re-classification (say, exposing
-- stage_org_connect_ref or get_org_connect_ref to `authenticated`) is a security
-- change that a name-only list would not catch.
SELECT bag_eq(
  $$SELECT p.proname || ' secdef=' || p.prosecdef::text
         || ' auth='   || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
         || ' svc='    || has_function_privilege('service_role',  p.oid, 'EXECUTE')::text
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'kernel'
       AND p.proname IN ('get_org_connect_ref','get_org_connect_state',
                         'get_refund_execution_context','is_order_buyer',
                         'settlement_primary_lines','stage_org_connect_ref',
                         'sync_org_connect_state')$$,
  $$VALUES
      -- ruling A6 — the Connect trio. The MASKED read is the only caller-facing one;
      -- the unmasked read and the privileged write are server-side by construction.
      ('get_org_connect_state secdef=true auth=true svc=false'),
      ('get_org_connect_ref secdef=true auth=false svc=true'),
      ('sync_org_connect_state secdef=true auth=false svc=true'),
      -- ruling A7 — the staging verb that closed the acct_ORPHANATTACKER P0.
      -- service_role ONLY: if this ever became authenticated the whole provenance
      -- control collapses, because a caller could stage what it then binds.
      ('stage_org_connect_ref secdef=true auth=false svc=true'),
      -- ruling A3 — the primary twin of 087's SEAM-2 line stubs: NO grant at all.
      ('settlement_primary_lines secdef=true auth=false svc=false'),
      -- ruling D3 — the refund executor's context read.
      ('get_refund_execution_context secdef=true auth=false svc=true'),
      -- ruling F — the definer predicate venue_order_item_sel_owner calls once
      -- buyer_id is column-revoked. It lives in `kernel` on the has_venue_role
      -- precedent and is deliberately NOT relocated to dodge this census.
      ('is_order_buyer secdef=true auth=true svc=false')$$,
  '077 A14a [093]: the seven functions 093 adds to kernel, BY NAME, with definer flag and grant class');

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
  -- 2026-08-31 (package 079): all three custody tables are born with RLS on.
  -- 2026-09-02 (package 091): 27 -> 28 (kernel.reserve — the Gate-M stub, empty, no writer).
  28, '077 C1: RLS is ENABLED on all twenty-eight tables (deny-by-default at birth)');
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
  || 'kernel_organization_sel_platform,kernel_platform_role_sel_platform,'
  -- 2026-08-31 (package 083): kernel_signing_key_sel_public — the single new
  -- policy, the world-readable public-key projection (PFA-16; I-2-safe qual,
  -- kms_handle_ref withheld by column grant). The other four 083 credential/wallet
  -- tables are deny-all zero-policy and add NO name.
  || 'kernel_signing_key_sel_public,'
  -- 2026-08-31 (package 079): the §16.10 register's two kernel.tickets read
  -- policies (kernel_tickets_sel_venue stays 080's, AUTHZ-PKG1). The ledger and
  -- the override table are deny-all by design and add NO name.
  || 'kernel_tickets_sel_owner,kernel_tickets_sel_platform,'
  -- 2026-08-31 (package 080): the 079-deferred venue read policy landed
  -- (AUTHZ-PKG1); it carries the org arm too (GP-3 NOTE — deliberately unsplit).
  || 'kernel_tickets_sel_venue',
  '077 D1 [T-RLS-POL-01]: exactly the TWELVE registered policy names — nothing else');
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
  'accept_org_invite,admin_refund,admin_set_identity_ext,approve_refund_request,'
  || 'cancel_refund_request,change_org_role,clear_my_demographics,'
  -- 2026-09-01 (package 087): +2 authenticated — close_settlement (venue_finance/
  -- org_finance/platform_admin in-body) and request_org_payout (org_owner/org_finance
  -- in-body). The two settlement seams are definer-internal. Named, not counted.
  || 'close_settlement,'
  || 'create_organization,force_void_ticket,get_my_contact_prefs,get_my_demographics,'
  -- 2026-09-02 (package 093): +2 authenticated — get_org_connect_state, the MASKED read
  -- half of RATIFIED ruling A6 (Stripe Connect ownership), and is_order_buyer, the
  -- ruling-F definer predicate venue_order_item_sel_owner now calls in place of the
  -- buyer_id subquery the column revoke made unreadable. Both are caller-facing, so both
  -- belong to the authenticated class. The other four 093 kernel functions are NOT here
  -- and must never be: get_org_connect_ref and sync_org_connect_state (the unmasked read
  -- and the privileged write of the Connect facts) and get_refund_execution_context are
  -- EXEC DEF service_role (F3), and settlement_primary_lines (ruling A3) carries NO grant
  -- at all. Named, not counted.
  || 'get_org_connect_state,'
  || 'grant_door_freeze_override,grant_org_contact_consent,grant_platform_role,'
  || 'has_event_role,has_org_role,has_org_role_over_event,has_org_role_over_venue,'
  || 'has_venue_role,hold_payout,invite_org_member,is_order_buyer,is_org_affiliate,is_platform,is_promoter_for_event,is_transfer_frozen,'
  -- 2026-09-01 (package 085): +14 money verbs/reads — the EDGE-FRONTED authority
  -- set (request/approve/cancel, the three lists, the denial witness, the
  -- destination change, the platform executors, the payout hold pair, resolve).
  -- Named, not counted.
  || 'list_approval_requests,list_my_org_contact_consents,list_org_payouts,list_org_refunds,'
  || 'mint_wallet_pass,money_role_grant_matured,'
  -- 2026-08-31 (package 083): +7 credential/wallet client RPCs — mint_wallet_pass
  -- + the two-of-two-parked lifecycle five (provision/rotate signing_key,
  -- provision/rotate/revoke pass_type_cert) + revoke_wallet_pass. All EXEC
  -- authenticated at the edge; parked bodies fail closed regardless. Named, not counted.
  || 'provision_pass_type_cert,provision_signing_key,record_money_denial,'
  -- refund_primary_order moved to service_role (EXEC DEF) by PFA-23.
  || 'release_payout,remove_org_member,'
  || 'request_account_deletion,request_order_refund,request_org_payout,'
  -- 2026-09-02 (package 088): +1 authenticated — resolve_dispute_native (EDGE-FRONTED;
  -- PFA-31 parks its body fail-closed). Named, not counted.
  || 'resolve_dispute_native,resolve_identity_obligation,'
  || 'revoke_door_freeze_override,revoke_org_invite,revoke_pass_type_cert,revoke_platform_role,'
  -- 2026-09-01 (package 086): +3 authenticated — the two door-freeze override
  -- verbs (AUTHZ) and revoke_signing_key (PFA-17). Named, not counted.
  || 'revoke_signing_key,revoke_wallet_pass,rotate_pass_type_cert,rotate_signing_key,set_my_contact_prefs,'
  || 'set_my_demographics,set_org_connect_ref,set_org_payout_destination,set_org_status,update_organization,'
  || 'upsert_identity_ext,withdraw_account_deletion,withdraw_org_contact_consent',
  -- money_role_grant_matured added 2026-08-31 by package 078: RLS §11.2 gives it
  -- an explicit `EXEC: authenticated` row (REVOKE FROM public, anon; GRANT TO
  -- authenticated). Named, not counted.
  -- 2026-08-31 (package 079): is_transfer_frozen joins (RLS §11.4 — the RN
  -- eligibility boolean). lock/unlock/mark_ticket_scanned/the expiry sweep are
  -- DEF and deliberately ABSENT. Named, not counted.
  -- 2026-08-31 (package 080): +4 — the §2.2 predicate helpers are EXEC
  -- authenticated by the plan §8/080 Grants row. Named, not counted.
    -- 2026-09-02 (package 090): +1 — is_promoter_for_event (RPC §1.1c EXEC: authenticated). pay_promoter_commission is EXEC DEF (no grant). Named, not counted.
  '077 F2 [RLS §11]: authenticated EXECUTE = exactly the 61 caller-authorized functions (59 post-090 + 093''s get_org_connect_state per A6 and is_order_buyer per F; refund_primary_order is EXEC DEF per PFA-23)');
-- the DEF class: service_role EXECUTE = the two sweeps + the predicate + 11 stubs
SELECT is(
  (SELECT string_agg(p.proname, ',' ORDER BY p.proname COLLATE "C")
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel'
      AND has_function_privilege('service_role', p.oid, 'EXECUTE')),
  'assert_door_session,deletion_blockers_custody,deletion_blockers_market,deletion_blockers_money,'
  || 'deletion_blockers_orders,deletion_blockers_wallet,'
  -- 2026-09-02 (package 093): +2 DEF service_role — get_refund_execution_context, the
  -- read PFA-23's refund-execute edge makes as service_role (RATIFIED ruling D3: the
  -- executor is "server-side, authenticated and authorized appropriately"), and
  -- get_org_connect_ref (ruling A6), the UNMASKED Connect-id read reserved to the server.
  -- Both are deliberately NOT authenticated: one resolves payment/order linkage, the
  -- other returns the raw acct_ id that kernel.get_org_connect_state masks for humans.
  -- Named, not counted.
  || 'get_org_connect_ref,get_refund_execution_context,get_wallet_pass_build_context,'
  -- 2026-08-31 (package 083): +9 DEF — the mint engine (issue_ticket_atoms; moved
  -- here by C114) and the eight service_role wallet-substrate RPCs (build_context,
  -- list_updated, register/unregister device, supersede, touch, sweep, record_push).
  -- REVOKE FROM anon+authenticated; service_role only. Named, not counted.
  || 'has_outstanding_obligations,'
  || 'is_deletion_pending,issue_ticket_atoms,list_updated_wallet_passes,'
  -- 2026-09-01 (package 085): +5 DEF — the Stripe state-sync pair, the
  -- obligation recorder, the refund-TTL sweep (PFA-21 delivers kernel USAGE).
  -- 2026-09-02 (package 088): +3 DEF service_role — mark_dispute_state, record_dispute_native
  -- (the stripe-webhook native dispute branch) and transfer_ticket_ownership (the engine,
  -- reached by the market definers and the sweep). Named, not counted.
  || 'mark_dispute_state,mark_payout_transfer_state,mark_refund_state,'
  || 'on_deletion_q5_release,on_identity_erased_door,'
  || 'on_identity_erased_market,on_identity_erased_promoter,on_identity_erased_staff,'
  || 'record_dispute_native,record_identity_obligation,'
  -- refund_primary_order joins the DEF class (PFA-23: EXEC DEF, service_role).
  -- 2026-09-02 (package 093): +1 DEF service_role — stage_org_connect_ref (ruling A7).
  -- service_role ONLY is the whole control: a caller that could stage would be able to
  -- authorise its own bind, which is the acct_ORPHANATTACKER P0 restated. Named, not counted.
  || 'record_wallet_push_result,refund_primary_order,register_wallet_pass_device,stage_org_connect_ref,supersede_wallet_passes_for_atom,'
  -- 2026-09-01 (package 086): +2 DEF service_role — assert_door_session (the door
  -- edge) and sweep_expired_door_overrides (CRON). Named, not counted.
  || 'sweep_deletion_pending,sweep_expired_door_overrides,sweep_expired_org_invites,sweep_expired_refund_requests,sweep_expired_ticket_atoms,'
  -- 2026-09-02 (package 093): +1 DEF service_role — sync_org_connect_state, the privileged
  -- write half of RATIFIED ruling A6/A9: only the server may bind or refresh an organization's
  -- Connect account facts, so it is service_role-only and never authenticated. Named, not counted.
  || 'sweep_wallet_pass_lifecycle,sync_org_connect_state,touch_wallet_pass,transfer_ticket_ownership,unregister_wallet_pass_device',
  -- 2026-08-31 (package 079): sweep_expired_ticket_atoms is the FIFTEENTH name —
  -- its frozen EXEC row (RPC §12.5 / S-22 / CRON register) is DEF,
  -- service_role/pg_cron only, REVOKE FROM anon+authenticated. The other four
  -- 079 DEF primitives (lock/unlock/mark/tg_*) carry NO grant at all: their
  -- callers are definer functions reached by ownership.
  '077 F3 [RLS §11 DEF / D-F2]: service_role EXECUTE = exactly the 38 DEF functions (34 post-088 + 093''s sync_org_connect_state/get_org_connect_ref per A6/A9, stage_org_connect_ref per A7, get_refund_execution_context per D3)');
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
-- 2026-09-02 (package 093) — RATIFIED CONTRACT CHANGE.
-- PRIMARY_TICKETING_OWNER_RATIFICATION.md rulings A7 (venue Stripe onboarding —
-- "a caller must never be permitted to supply or bind an arbitrary acct_
-- identifier"; "cross-plane reuse of an ordinary seller's existing connected
-- account must be prevented") and A9 (connect account security — the attachment
-- is "a privileged, audited operation") harden kernel.set_org_connect_ref with
-- four gates it did not previously carry:
--   (i)   org_owner ONLY — org_finance may initiate onboarding but may not bind;
--   (ii)  an aal2 step-up session, fail-closed when the claim is ABSENT;
--   (iii) organization status in (approved, active) — approval precedes the
--         payee, where `applied` was previously admitted;
--   (iv)  refusal of any acct_ that already lives on the individual seller plane.
-- L1-L5 below are UNCHANGED. The fixture is stepped up and the org approved so
-- they remain reachable, and each new gate is asserted FIRST so the added setup
-- cannot silently conceal a regression in the gate it satisfies.
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM set_config('request.jwt.claims',
    (coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true);
END $f$;

SELECT tap.login(tap.admin_user());
-- (ii) AUTHZ-M4 fail-closed arm — an absent claim can never evaluate as satisfied
SELECT throws_like(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl0a')$$,
  '%step_up_unavailable%',
  '077 L0a [093/A9, AUTHZ-M4]: a session carrying NO aal claim is step_up_unavailable — never a pass');
SELECT set_config('request.jwt.claims',
  (current_setting('request.jwt.claims', true)::jsonb || '{"aal":"aal1"}'::jsonb)::text, true);
SELECT throws_like(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl0b')$$,
  '%step_up_required%',
  '077 L0b [093/A9]: aal1 is step_up_required — binding a payee is a money-destination act');
SELECT tap._aal2();
-- (iii) G-6 — org1 is still `applied` (K3); approval precedes the payee
SELECT throws_like(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl0c')$$,
  '%org_not_bindable%',
  '077 L0c [093/A9, G-6]: an APPLIED org may not bind a payee — approval precedes the payee');
SELECT is((kernel.set_org_status(tap._fetch('org1')::uuid, 'approved', 'review_passed', 'ck-l0d'))->>'org_status',
  'approved', '077 L0d: platform approval moves org1 applied -> approved — the 093 precondition for any bind');
-- (iv) G-1 — the cross-plane refusal, asserted on a real individual-plane id
SELECT tap.logout();
UPDATE public.profiles SET stripe_connect_id = 'acct_PERSONAL1' WHERE id = tap.seller();
SELECT tap.login(tap.admin_user());
SELECT tap._aal2();
SELECT throws_like(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_PERSONAL1', 'cl0e')$$,
  '%account_not_platform_minted_for_org%',
  '077 L0e [093/A7, G-1]: an acct_ held on public.profiles is refused — the personal-seller-account attack');
SELECT tap.logout();
UPDATE public.profiles SET stripe_connect_id = NULL WHERE id = tap.seller();

-- ── (v) 093: PROVENANCE — the account must have been STAGED by the server ──
-- RATIFIED ruling A7: "A caller must never be permitted to supply or bind an
-- arbitrary acct_ identifier." The cross-plane refusal at L0e is a BLOCKLIST — it
-- enumerates accounts known to belong to the individual plane — and a red team
-- walked straight past it by binding acct_ORPHANATTACKER, an account it had freshly
-- created that appeared in neither public.profiles nor public.stripe_connect_archive,
-- as `authenticated`, on both the first bind and a live re-point. A blocklist cannot
-- satisfy an absolute prohibition, so the fix is structural: kernel.organization
-- gains connect_pending_ref, written ONLY by kernel.stage_org_connect_ref
-- (service_role only), and the bind must match it and CONSUMES it.
-- These three assertions are that P0's proof and had no coverage before.
SELECT tap.login(tap.admin_user());
SELECT tap._aal2();
SELECT throws_like(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl0f')$$,
  '%no_pending_connect_ref%',
  '077 L0f [093/A7]: with NOTHING staged, a bind is refused — an arbitrary acct_ can no longer enter through the RPC (the acct_ORPHANATTACKER P0)');
SELECT tap.logout();
-- staging is service_role-only (pinned by F3); exercised here in the DEFINER
-- context, as G2-style machine paths are throughout this suite.
SELECT is((kernel.stage_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl0g'))->>'status', 'ok',
  '077 L0g [093/A7]: the server stages the account it minted — the only writer of connect_pending_ref');
SELECT tap.login(tap.admin_user());
SELECT tap._aal2();
SELECT throws_like(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_OTHER999', 'cl0h')$$,
  '%connect_ref_not_platform_minted%',
  '077 L0h [093/A7]: a bind of a DIFFERENT id than the staged one is refused — staging is a match, not a mere flag');
SELECT is((kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl1'))->>'newly_bound', 'true',
  '077 L1 [T-RPC-CONNECT-01]: the first bind succeeds');
SELECT tap.logout();
SELECT is(
  (SELECT connect_pending_ref FROM kernel.organization WHERE org_id = tap._fetch('org1')::uuid),
  NULL, '077 L1a [093/A7]: the successful bind CONSUMED connect_pending_ref — one staging authorises exactly one bind, never a later re-point');
SELECT is(
  (SELECT payout_destination_set_by FROM kernel.organization WHERE org_id = tap._fetch('org1')::uuid),
  tap.admin_user(), '077 L2 [T-RPC-CONNECT-01/SoD-1]: the bind stamps payout_destination_set_by');
SELECT tap.login(tap.admin_user());
SELECT tap._aal2();
SELECT is((kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_TESTABC123', 'cl2'))->>'status', 'noop_replay',
  '077 L3 [T-RPC-CONNECT-03]: re-binding the same id is noop_replay (the re-onboarding retry path)');
SELECT throws_like(
  $$SELECT kernel.set_org_connect_ref(tap._fetch('org1')::uuid, 'acct_OTHER999', 'cl3')$$,
  '%destination_already_set%',
  -- 093 / ruling A9 narrowed the admitted control set here to org_owner alone; the
  -- assertion is unchanged — a re-point of a non-NULL ref still raises at this door.
  -- Note the arm order 093 fixes deliberately: noop_replay (L3) and this bind-once
  -- arm both sit BEFORE the provenance check, so consuming connect_pending_ref at L1a
  -- cannot break the idempotent onboarding retry L3 asserts.
  '077 L4 [T-RPC-CONNECT-02]: an org_owner re-point of a non-NULL ref raises — §17.7''s control set defended at the second door');
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
