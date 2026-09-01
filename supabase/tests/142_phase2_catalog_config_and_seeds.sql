-- ============================================================================
-- 142_phase2_catalog_config_and_seeds.sql — Phase-2 package 078 test suite.
--
-- Frozen sources: plan §8/078 Tests row · schema-spec §1.16 (MB-5), §2.1–§2.5,
-- §2.4.1 (AUTHZ-CFG1) · RLS spec §8.1–§8.5, §11, §16.10/§16.10a · RPC contracts
-- §1.1e, §3.1–§3.3, §4.1, §4.3, §12.4a, §20.2.1–§20.2.3 · DOOR §10.6 ·
-- WALLET §11.5 · NOTIF §7.3/§7.4 · MONEY §7.2 · OR-22 · OR-16/DEMOG §8.5.
-- PFA-7/PFA-8/PFA-9/PFA-10 witnesses included. HARDENING-1's recorded witness is
-- section L, verbatim from the governance record.
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK (no committed state).
-- ============================================================================
BEGIN;
SELECT plan(248);

SELECT tap.seed_core();

-- per-file memo helpers (rolled back with this transaction; definer so every
-- persona can store/fetch fixture ids)
CREATE TABLE tap.memo_142 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store142(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_142 VALUES (k, v)
    ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch142(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_142 WHERE k = $1 $m$;

-- ============================================================================
-- SECTION A — THE 078 CLOSED WORLD (parity: EXTRA = 0, MISSING = 0)
-- ============================================================================

SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'catalog' AND c.relkind = 'r'), 5,
  'A1: catalog holds EXACTLY the five frozen tables');

SELECT bag_eq(
  $$SELECT c.relname::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'catalog' AND c.relkind = 'r'$$,
  $$VALUES ('venue'),('event'),('event_session'),('platform_config'),('resale_policy')$$,
  'A2: the five table names are exactly the frozen set (EXTRA=0, MISSING=0)');

SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog'), 15,
  -- 2026-08-31 (package 081): 10 -> 11. catalog.publish_event is 081's (SEAM-1:
  -- it reads venue.ticket_type + inventory_batch), named in A4 below.
  -- 2026-09-01 (package 086): 11 -> 15. engage_door_freeze (door_open_at sole
  -- writer), set_session_door_schedule, sweep_implicit_door_freezes and the
  -- tg_door_open_at_is_ledger_head trigger fn. Named in A4 below.
  'A3: catalog holds EXACTLY fifteen functions — no helper the closed world does not carry');

SELECT bag_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'catalog'$$,
  $$VALUES ('create_venue'),('approve_venue'),('update_venue'),('create_event'),
           ('create_event_session'),('update_event'),('set_platform_config'),
           ('set_resale_policy'),('effective_freeze_at'),('update_event_session'),('publish_event'),
           ('engage_door_freeze'),('set_session_door_schedule'),('sweep_implicit_door_freezes'),
           ('tg_door_open_at_is_ledger_head')$$,
  'A4: the fifteen catalog function names are exactly the frozen set (publish_event by 081; four door fns by 086)');

SELECT has_function('kernel'::name, 'money_role_grant_matured'::name, ARRAY['uuid']::name[],
  'A5: kernel.money_role_grant_matured is authored HERE (SEAM-1 max(077,078)=078)');

-- FR-2 / FR-2b / FR-7: three functions plan §8/078 names are NOT in this package.
SELECT has_function('catalog'::name, 'publish_event'::name, ARRAY['uuid','text','text']::name[],
  'A6: catalog.publish_event ARRIVED with 081 (FR-2/SEAM-1: it reads venue.ticket_type + inventory_batch)');
SELECT hasnt_function('catalog'::name, 'cancel_event'::name,
  'A7: catalog.cancel_event is NOT here — FR-2b moved it to 088');
-- 2026-08-31: A8's subject ARRIVED with package 079 (SEAM-1), so the deferral
-- assertion inverts to presence, pinned to the authoring package.
SELECT has_function('catalog'::name, 'update_event_session'::name, ARRAY['uuid','jsonb','text']::name[],
  'A8: catalog.update_event_session now exists — authored by 079, exactly as the SEAM-1 note said');
SELECT has_function('catalog'::name, 'engage_door_freeze'::name, ARRAY['uuid','timestamptz']::name[],
  'A9: catalog.engage_door_freeze now exists — authored by 086, the door_open_at sole writer');
SELECT has_function('kernel'::name, 'is_transfer_frozen'::name, ARRAY['uuid']::name[],
  'A10: kernel.is_transfer_frozen now exists — FR-7 resolved it to 079, and 079 delivered it');

SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'catalog'), 12,
  -- 2026-08-31 (package 080): 9 -> 12 — the three AUTHZ-PKG1 venue-plane reads
  -- arrived with their helpers (suite 144 owns their behaviour).
  'A11: catalog carries EXACTLY twelve policies (nine of 078 + 080''s three venue-plane reads)');

-- 078 owns no cron entry (CRON_SCHEDULE_REGISTER has no 078 row) and emits nothing
-- (the R2 catalog writers are update_event_session·079 and cancel_event·088).
SELECT is((SELECT count(*)::int FROM cron.job
            WHERE command ILIKE '%catalog.%' OR jobname ILIKE '%catalog%'), 1,
  -- 2026-09-01 (package 086): the implicit door-freeze sweep
  -- (sweep-implicit-door-freezes, command `select catalog.sweep_implicit_door_freezes(500)`)
  -- is catalog's FIRST cron entry. 078 still schedules none — 086 owns this one.
  'A12: exactly one catalog cron job — 086''s implicit door-freeze sweep (078 schedules none)');
SELECT is((SELECT count(*)::int FROM (
             SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'catalog' OFFSET 0) q
            WHERE pg_get_functiondef(q.oid) ILIKE '%emit_event%'), 0,
  'A13: no 078 function emits — R2 carries no 078 emitter row');

-- ============================================================================
-- SECTION B — TABLE SHAPE AND THE CHECK SETS
-- ============================================================================

SELECT is(
  (SELECT string_agg(x.m[1], ',' ORDER BY x.m[1])
     FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_ ]+)''', 'g') AS x(m)
    WHERE c.conrelid = 'catalog.venue'::regclass AND c.conname LIKE '%approval_status%'),
  'approved,archived,draft,pending',
  'B1: catalog.venue.approval_status carries exactly the four frozen labels');

SELECT is(
  (SELECT string_agg(x.m[1], ',' ORDER BY x.m[1])
     FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_ ]+)''', 'g') AS x(m)
    WHERE c.conrelid = 'catalog.venue'::regclass AND c.conname LIKE '%neighborhood%'),
  'brickell,coconut grove,design district,downtown miami,little havana,miami beach,midtown,south beach,wynwood',
  'B2: the neighborhood set is the frozen public.listings nine, duplicated by decision (CONFLICTS #7)');

SELECT is(
  (SELECT string_agg(x.m[1], ',' ORDER BY x.m[1])
     FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') AS x(m)
    WHERE c.conrelid = 'catalog.event'::regclass AND c.conname LIKE '%status%'),
  'announced,cancelled,completed,draft,live,on_sale',
  'B3: catalog.event.status carries exactly the six frozen labels');

SELECT is(
  (SELECT string_agg(x.m[1], ',' ORDER BY x.m[1])
     FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') AS x(m)
    WHERE c.conrelid = 'catalog.event_session'::regclass AND c.conname LIKE '%status%'),
  'cancelled,completed,live,scheduled',
  'B4: catalog.event_session.status carries exactly the four frozen labels');

SELECT is(
  (SELECT string_agg(x.m[1], ',' ORDER BY x.m[1])
     FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') AS x(m)
    WHERE c.conrelid = 'catalog.resale_policy'::regclass AND c.conname LIKE '%mode%'),
  'auction,buy_now,face_value_queue,fixed_cap,off,offer,transfers_only',
  'B5: resale mode carries exactly the SEVEN frozen labels (schema §2.5 is the storage authority)');

SELECT col_default_is('catalog'::name, 'resale_policy'::name, 'mode'::name, 'off',
  'B6: resale_policy.mode defaults to off (C11)');
SELECT col_default_is('catalog'::name, 'event_session'::name, 'session_version'::name, '1',
  'B7: session_version defaults to 1');
SELECT col_not_null('catalog'::name, 'event_session'::name, 'session_version'::name,
  'B8: session_version is NOT NULL (Δ-N1, correctness-blocking)');
SELECT col_not_null('catalog'::name, 'event_session'::name, 'starts_at'::name,
  'B9: starts_at is NOT NULL — this is what makes effective_freeze_at TOTAL');
SELECT col_is_null('catalog'::name, 'event_session'::name, 'door_open_at'::name,
  'B10: door_open_at is nullable — it is set by 086, not at session creation');
SELECT col_default_is('catalog'::name, 'platform_config'::name, 'visibility'::name, 'restricted',
  'B11: visibility DEFAULTS TO restricted — the default is the design (AUTHZ-CFG1)');
SELECT col_not_null('catalog'::name, 'platform_config'::name, 'value'::name,
  'B12: platform_config.value is NOT NULL — semantic absence is the JSON null literal');
SELECT col_type_is('catalog'::name, 'platform_config'::name, 'value'::name, 'jsonb',
  'B13: platform_config.value is jsonb');
SELECT col_type_is('catalog'::name, 'event'::name, 'genre_tags'::name, 'text[]',
  'B14: genre_tags is an array, not a join table');
SELECT col_is_pk('catalog'::name, 'platform_config'::name, ARRAY['key','version']::name[],
  'B15: platform_config PK is the composite (key, version) — versions are immutable');

-- No native enum exists anywhere in the Phase-2 model (T-SCHEMA-ROLE-02): every
-- label set above is text + CHECK. `>=` on such a column is lexicographic, which
-- is exactly the R3-3a defect.
SELECT is((SELECT count(*)::int FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname = 'catalog' AND t.typtype = 'e'), 0,
  'B16: catalog declares ZERO native enum types (T-SCHEMA-ROLE-02)');

SELECT throws_ok(
  $$INSERT INTO catalog.venue (org_id, name, neighborhood)
    VALUES (gen_random_uuid(), 'x', 'soho')$$,
  NULL, NULL, 'B17: an off-set neighborhood is refused');

SELECT throws_ok(
  $$INSERT INTO catalog.platform_config (key, version, value, visibility)
    VALUES ('probe.key', 1, '1'::jsonb, 'semi_public')$$,
  NULL, NULL, 'B18: an off-set visibility label is refused');

-- ============================================================================
-- SECTION C — RLS POSTURE AND THE POLICY REGISTER
-- ============================================================================

SELECT ok((SELECT bool_and(c.relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'catalog' AND c.relkind = 'r'),
  'C1: RLS is ENABLED on all five catalog tables');

SELECT bag_eq(
  $$SELECT p.polname::text FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'catalog'$$,
  $$VALUES ('catalog_venue_sel_anon'),('catalog_venue_sel_org'),('catalog_venue_sel_venue'),
           ('catalog_event_sel_anon'),('catalog_event_sel_org'),('catalog_event_sel_venue'),
           ('catalog_event_session_sel_anon'),('catalog_event_session_sel_org'),
           ('catalog_event_session_sel_venue'),
           ('catalog_platform_config_sel_public'),('catalog_platform_config_sel_restricted'),
           ('catalog_resale_policy_sel_public')$$,
  'C2: the policy names are exactly the full §16.10 catalog register (the three 080 deferrals landed)');

SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'catalog' AND p.polcmd <> 'r'), 0,
  'C3: every catalog policy is FOR SELECT — GP-1 leaves no client write path');

SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'catalog' AND p.polname LIKE '%_sel_venue'), 3,
  -- 2026-08-31: the SEAM-3/FR-10..12 deferral DISCHARGED on schedule.
  'C4: the three venue-plane read policies ARRIVED with 080 — the deferral discharged, not decorative');

-- The deferral is only correct if the helper genuinely does not exist yet.
SELECT has_function('kernel'::name, 'has_venue_role'::name, ARRAY['uuid','text[]']::name[],
  'C5: kernel.has_venue_role exists from 080 on — the PFA-10 deferred name resolves (suite 144 owns the arm''s behaviour)');

-- RED-B: the §8.1-§8.3 org-plane SEL rows enumerate org_member, org_owner/admin
-- and org_finance ONLY. org_marketing and org_promoter_manager appear in no SEL
-- row on any of the three tables, and absence of a policy is deny-by-default.
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'catalog'
             AND (pg_get_expr(p.polqual, p.polrelid) LIKE '%org_marketing%'
               OR pg_get_expr(p.polqual, p.polrelid) LIKE '%org_promoter_manager%')), 0,
  'C5a: no catalog policy admits org_marketing or org_promoter_manager — the matrices enumerate neither');

-- I-2 / T-RLS-POL-02: asserted UNCONDITIONALLY over the whole schema, because the
-- ban is stated that way and a per-policy spot check would miss the next one.
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'catalog'
             AND coalesce(btrim(pg_get_expr(p.polqual, p.polrelid)), '') = 'true'), 0,
  'C5b: I-2 — NO policy in catalog is USING (true)');

SELECT is((SELECT count(*)::int FROM information_schema.role_table_grants
            WHERE table_schema = 'catalog'
              AND grantee IN ('anon','authenticated','PUBLIC')
              AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE')), 0,
  'C6: no client principal holds INSERT/UPDATE/DELETE on any catalog table (GP-1/GP-2)');

SELECT ok((SELECT count(*) FROM information_schema.column_privileges
            WHERE table_schema = 'catalog' AND grantee = 'anon'
              AND privilege_type = 'SELECT') > 0,
  'C7: anon holds COLUMN-scoped SELECT — the I-7 deny-then-grant shape, not a table grant');

-- ============================================================================
-- SECTION D — THE CONFIG CONTRACT (41 keys; the two-class split)
-- ============================================================================

SELECT is((SELECT count(*)::int FROM catalog.platform_config), 42,
  'D1: exactly 42 config keys are seeded (41 from 078 + PFA-22''s deletion.refund_possible_window_hours at 085)');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE version <> 1), 0,
  'D2: every seed is version 1 — a migration seeds, it never bumps');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE visibility = 'public'), 8,
  'D3: exactly 8 keys are public (PFA-8: the five flags + the three credential client spans)');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE visibility = 'restricted'), 34,
  'D4: the other 34 are restricted (the PFA-22 key is restricted)');

SELECT bag_eq(
  $$SELECT key FROM catalog.platform_config WHERE visibility = 'public'$$,
  $$VALUES ('feature.native_issuance_enabled'),('feature.native_scanning_enabled'),
           ('feature.native_resale_enabled'),('wallet.apple.enabled'),
           ('notify.announcements_enabled'),('credential.wallet_exp_skew'),
           ('credential.wallet_default_span'),('credential.app_ttl_interval')$$,
  'D5: the public class is exactly the frozen §2.4.1 list — asserted by NAME, not by count');

-- T-SCHEMA-CFG-01 / T-RLS-CFG-01, asserted PER NAMESPACE because a single-key
-- test passes while five namespaces leak. `crm%` rather than `crm.%`: the real
-- key is crm_export.*, and `_` is a LIKE wildcard — the property, not the spelling.
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE visibility = 'public' AND key LIKE 'refund.%'), 0, 'D6: no refund.* key is public');
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE visibility = 'public' AND key LIKE 'payout.%'), 0, 'D7: no payout.* key is public');
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE visibility = 'public' AND key LIKE 'authn.%'), 0, 'D8: no authn.* key is public');
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE visibility = 'public' AND key LIKE 'comp.%'), 0, 'D9: no comp.* key is public');
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE visibility = 'public' AND key LIKE 'crm%'), 0, 'D10: no crm* key is public');
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE visibility = 'public' AND key LIKE 'door.%'), 0, 'D11: no door.* key is public');

-- T-SCHEMA-CFG-02: visibility is a property of the KEY, not of the version.
SELECT is((SELECT count(*)::int FROM (
             SELECT key FROM catalog.platform_config
              GROUP BY key HAVING count(DISTINCT visibility) > 1) x), 0,
  'D12: visibility is constant across every version of a key');

-- Exact values, types and units — the money numbers are ABSENT BY DESIGN (PFA-9).
SELECT is((SELECT value FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled'),
  'false'::jsonb, 'D13: feature.native_issuance_enabled = false');
SELECT is((SELECT value FROM catalog.platform_config WHERE key = 'feature.native_scanning_enabled'),
  'false'::jsonb, 'D14: feature.native_scanning_enabled = false');
SELECT is((SELECT value FROM catalog.platform_config WHERE key = 'feature.native_resale_enabled'),
  'false'::jsonb, 'D15: feature.native_resale_enabled = false');
SELECT is((SELECT value FROM catalog.platform_config WHERE key = 'wallet.apple.enabled'),
  'false'::jsonb, 'D16: wallet.apple.enabled = false');
SELECT is((SELECT value FROM catalog.platform_config WHERE key = 'notify.announcements_enabled'),
  'false'::jsonb, 'D17: notify.announcements_enabled = false');

SELECT is((SELECT (value #>> '{}')::interval FROM catalog.platform_config
            WHERE key = 'door.manifest_ttl_interval'), interval '12 hours',
  'D18: door.manifest_ttl_interval = 12 hours, byte-exact from DOOR §10.6');
SELECT is((SELECT (value #>> '{}')::interval FROM catalog.platform_config
            WHERE key = 'door.implicit_freeze_offset_interval'), interval '0 minutes',
  'D19: door.implicit_freeze_offset_interval = 0 minutes');
SELECT is((SELECT (value #>> '{}')::interval FROM catalog.platform_config
            WHERE key = 'door.session_absolute_max_interval'), interval '24 hours',
  'D20: door.session_absolute_max_interval = 24 hours');
SELECT is((SELECT (value #>> '{}')::interval FROM catalog.platform_config
            WHERE key = 'credential.wallet_exp_skew'), interval '6 hours',
  'D21: credential.wallet_exp_skew = 6 hours, byte-exact from WALLET §11.5');
SELECT is((SELECT (value #>> '{}')::interval FROM catalog.platform_config
            WHERE key = 'credential.app_ttl_interval'), interval '4 hours',
  'D22: credential.app_ttl_interval = 4 hours, byte-exact');

-- PFA-7: the cross-config invariant, over the SEEDED values. This is the frozen
-- assertion plan §8/078 names, and it is the reason wallet_default_span is 6h.
SELECT ok(
  (SELECT (value #>> '{}')::interval FROM catalog.platform_config WHERE key = 'credential.wallet_default_span')
  + (SELECT (value #>> '{}')::interval FROM catalog.platform_config WHERE key = 'credential.wallet_exp_skew')
  <= (SELECT (value #>> '{}')::interval FROM catalog.platform_config WHERE key = 'door.manifest_ttl_interval'),
  'D23: CROSS-CONFIG INVARIANT — a Wallet token may never outlive the offline window any manifest could authorise');

SELECT is((SELECT (value #>> '{}')::interval FROM catalog.platform_config
            WHERE key = 'credential.wallet_default_span'), interval '6 hours',
  'D24: wallet_default_span = 6h — the MAXIMUM the invariant admits with the other two frozen (PFA-7)');

-- OR-22: the buy-now reservation TTL. KEY, TYPE, VALUE and UNIT all asserted.
SELECT is((SELECT value FROM catalog.platform_config
            WHERE key = 'resale.buy_now_reservation_ttl_minutes'), '10'::jsonb,
  'D25: resale.buy_now_reservation_ttl_minutes = 10 (OR-22)');
SELECT is((SELECT jsonb_typeof(value) FROM catalog.platform_config
            WHERE key = 'resale.buy_now_reservation_ttl_minutes'), 'number',
  'D26: the TTL is an integer, not a string — the unit lives in the key name (minutes)');
SELECT is((SELECT (value #>> '{}')::int FROM catalog.platform_config
            WHERE key = 'resale.buy_now_reservation_ttl_minutes') * interval '1 minute',
  interval '10 minutes',
  'D27: the TTL means TEN MINUTES when a consumer coerces it (the 088 seam)');

-- OR-16 / DEMOG §8.5 / freeze red-team F-8: ABSENT BY DESIGN, and the row is the
-- auditable carrier of that absence.
SELECT ok(EXISTS (SELECT 1 FROM catalog.platform_config WHERE key = 'retention.backup_window_days'),
  'D28: retention.backup_window_days EXISTS as a row — the auditable carrier');
SELECT is((SELECT jsonb_typeof(value) FROM catalog.platform_config
            WHERE key = 'retention.backup_window_days'), 'null',
  'D29: its value is the JSON null — NO retention window is fabricated');
SELECT is((SELECT (value #>> '{}') FROM catalog.platform_config
            WHERE key = 'retention.backup_window_days'), NULL,
  'D30: a consumer extracting it gets SQL NULL => purge_after = NULL => NEVER PURGEABLE');
SELECT is((SELECT visibility FROM catalog.platform_config
            WHERE key = 'retention.backup_window_days'), 'restricted',
  'D31: it is in the restricted namespace, as DEMOG §8.5 requires');

-- X-12 fail-to-safe: the four keys whose absence must read RESTRICTIVELY.
SELECT is((SELECT jsonb_typeof(value) FROM catalog.platform_config
            WHERE key = 'comp.per_staff_step_up_max_units'), 'null',
  'D32: comp.per_staff_step_up_max_units is absent-by-design => EVERY comp needs step-up');
SELECT is((SELECT jsonb_typeof(value) FROM catalog.platform_config
            WHERE key = 'comp.per_staff_step_up_window_hours'), 'null',
  'D33: comp.per_staff_step_up_window_hours likewise');
SELECT is((SELECT jsonb_typeof(value) FROM catalog.platform_config
            WHERE key = 'refund.platform_support_max_minor'), 'null',
  'D34: refund.platform_support_max_minor is absent-by-design => support may approve NOTHING');
SELECT is((SELECT (value #>> '{}')::int FROM catalog.platform_config
            WHERE key = 'authn.money_role_maturity_hours'), 72,
  'D35: authn.money_role_maturity_hours = 72 — PROVISIONAL, the RESTRICTIVE end of MD-14''s 24-72h');

-- NOTIF §7.4 / ODR-56 silence-defaults.
SELECT is((SELECT (value #>> '{}')::int FROM catalog.platform_config
            WHERE key = 'notify.announcement_max_per_session'), 3, 'D36: announcement_max_per_session = 3');
SELECT is((SELECT (value #>> '{}')::int FROM catalog.platform_config
            WHERE key = 'notify.announcement_min_interval_seconds'), 1800,
  'D37: announcement_min_interval_seconds = 1800');
SELECT is((SELECT (value #>> '{}')::int FROM catalog.platform_config
            WHERE key = 'notify.announcement_hold_seconds'), 300,
  'D38: announcement_hold_seconds = 300 (ODR-56 silence; floor 120)');
SELECT is((SELECT (value #>> '{}')::int FROM catalog.platform_config
            WHERE key = 'notify.announcement_dual_control_threshold'), 500,
  'D39: announcement_dual_control_threshold = 500 (ODR-56 silence)');

-- The fifteen money keys MONEY §7.2 + schema §1.13.4 enumerate.
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE key LIKE 'refund.%' OR key LIKE 'payout.%' OR key LIKE 'authn.%'), 15,
  'D40: exactly 15 money keys (MONEY §7.2''s fourteen + authn.money_role_maturity_hours)');

-- PFA-9: the keys deliberately NOT seeded, asserted as absences so a later
-- package cannot silently assume 078 covered them.
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE key IN ('door.session_touch_interval','door.schedule_move_grace_interval',
                          'notify.delivery_lease_interval')), 0,
  'D41: the three consumed-but-unspecified keys are NOT invented here (PFA-9 CLASS A)');

-- ============================================================================
-- SECTION E — SEED IDEMPOTENCY AND CONFLICT BEHAVIOUR
-- ============================================================================

-- Clean insert of a new key/version pair is possible (the table is not frozen).
SELECT lives_ok(
  $$INSERT INTO catalog.platform_config (key, version, value, visibility)
    VALUES ('probe.seed', 1, '1'::jsonb, 'restricted')$$,
  'E1: a clean first insert succeeds');

-- Identical seed replay: ON CONFLICT DO NOTHING leaves exactly one row.
SELECT lives_ok(
  $$INSERT INTO catalog.platform_config (key, version, value, visibility)
    VALUES ('probe.seed', 1, '1'::jsonb, 'restricted')
    ON CONFLICT (key, version) DO NOTHING$$,
  'E2: an identical replay is a no-op, not an error');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key = 'probe.seed'), 1,
  'E3: the replay left exactly one row');

-- Conflicting existing seed: the replay must NOT overwrite it.
SELECT lives_ok(
  $$INSERT INTO catalog.platform_config (key, version, value, visibility)
    VALUES ('probe.seed', 1, '999'::jsonb, 'public')
    ON CONFLICT (key, version) DO NOTHING$$,
  'E4: a CONFLICTING replay is refused silently by ON CONFLICT DO NOTHING');
SELECT is((SELECT value FROM catalog.platform_config WHERE key = 'probe.seed' AND version = 1),
  '1'::jsonb, 'E5: the conflicting value did NOT overwrite the existing one');
SELECT is((SELECT visibility FROM catalog.platform_config WHERE key = 'probe.seed' AND version = 1),
  'restricted', 'E6: and it did not silently re-publish a restricted key');

-- Missing key behaviour is the writer's problem, and the writer refuses.
SELECT throws_ok(
  $$SELECT catalog.set_platform_config('probe.absent', '1'::jsonb, 'r', 'k1')$$,
  NULL, NULL, 'E7: set_platform_config on an unseeded key raises (it creates no new key)');

-- ============================================================================
-- SECTION F — SECURITY: ACL TOPOLOGY AND HOSTILE CLIENT PROBES
-- ============================================================================

SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog'
              AND (has_function_privilege('public', p.oid, 'EXECUTE')
                OR has_function_privilege('anon',   p.oid, 'EXECUTE'))), 0,
  'F1: NO catalog function holds EXECUTE for PUBLIC or anon');

SELECT ok(NOT has_function_privilege('anon', 'kernel.money_role_grant_matured(uuid)', 'EXECUTE'),
  'F2: anon holds no EXECUTE on the money-maturity predicate (RLS §11.2, explicit REVOKE)');

SELECT bag_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'catalog'
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE')$$,
  $$VALUES ('create_venue'),('approve_venue'),('update_venue'),('create_event'),
           ('create_event_session'),('update_event'),('set_platform_config'),
           ('set_resale_policy'),('effective_freeze_at'),('update_event_session'),('publish_event'),
           ('set_session_door_schedule')$$,
  -- engage_door_freeze/sweep_implicit_door_freezes/tg_* are NOT authenticated
  -- (definer-internal / service_role / trigger). Only the schedule editor is.
  'F3: the authenticated EXECUTE closure is exactly the twelve caller-authorized catalog RPCs (publish_event by 081; set_session_door_schedule by 086)');

-- A migration is not a config change (plan §4); RPC §20.2.1 forbids every
-- service_role path on set_platform_config explicitly.
SELECT ok(NOT has_function_privilege('service_role', 'catalog.set_platform_config(text,jsonb,text,text)', 'EXECUTE'),
  'F4: service_role holds NO EXECUTE on set_platform_config — a migration is not a config change');
SELECT ok(NOT has_function_privilege('service_role', 'catalog.approve_venue(uuid,text,text,text)', 'EXECUTE'),
  'F5: service_role holds no catalog write verb at all');
SELECT ok(NOT has_function_privilege('service_role', 'catalog.effective_freeze_at(uuid)', 'EXECUTE'),
  'F6: service_role holds NO EXECUTE on the freeze helper — RLS §11.4''s class is `authenticated`, and a definer callee is reached by ownership, not by grant');
SELECT ok(NOT has_function_privilege('service_role', 'kernel.money_role_grant_matured(uuid)', 'EXECUTE'),
  'F6a: nor on the money-maturity predicate — RPC §1.1e''s class is `authenticated` only');

SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog' AND NOT p.prosecdef), 0,
  'F7: every catalog function is SECURITY DEFINER');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog'
              AND NOT (coalesce(array_to_string(p.proconfig, ','), '') LIKE '%search_path=%')), 0,
  'F8: every catalog function pins search_path (the 066 discipline)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog' AND pg_get_userbyid(p.proowner) <> 'postgres'), 0,
  'F9: every catalog function is owned by postgres');
SELECT is((SELECT p.provolatile::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog' AND p.proname = 'effective_freeze_at'), 's',
  'F10: effective_freeze_at is STABLE (RPC §12.4a)');
SELECT is((SELECT p.provolatile::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.proname = 'money_role_grant_matured'), 's',
  'F11: money_role_grant_matured is STABLE (RPC §1.1e)');

-- Hostile client probes.
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE key LIKE 'refund.%' OR key LIKE 'payout.%' OR key LIKE 'authn.%'
               OR key LIKE 'comp.%' OR key LIKE 'crm%' OR key LIKE 'door.%'), 0,
  'F12: T-SCHEMA-CFG-01 — anon reads ZERO rows in the six restricted namespaces');
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE key IN ('feature.native_issuance_enabled','feature.native_scanning_enabled',
                          'feature.native_resale_enabled','wallet.apple.enabled',
                          'notify.announcements_enabled')), 5,
  'F13: the NON-VACUITY guard — the same anon read DOES return the five feature flags');
SELECT is((SELECT count(*)::int FROM catalog.platform_config), 8,
  'F14: anon sees exactly the eight public rows and nothing else');

SELECT throws_ok(
  $$INSERT INTO catalog.platform_config (key, version, value) VALUES ('x', 1, '1'::jsonb)$$,
  NULL, NULL, 'F15: anon cannot INSERT a config row');
-- T-RLS-CFG-02 asserts the DEFAULT, not the seed: a key inserted with no
-- visibility at all must be unreadable by anon. col_default_is asserts the
-- declaration; this asserts the read.
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value)
VALUES ('probe.novis', 1, '1'::jsonb);
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key = 'probe.novis'), 0,
  'F14a: T-RLS-CFG-02 — a key seeded with NO visibility value is unreadable by anon');
SELECT throws_ok(
  $$UPDATE catalog.platform_config SET value = '1'::jsonb$$,
  NULL, NULL, 'F16: anon cannot UPDATE a config row');
SELECT throws_ok(
  $$DELETE FROM catalog.platform_config$$,
  NULL, NULL, 'F17: anon cannot DELETE a config row');
SELECT throws_ok(
  $$SELECT catalog.set_platform_config('feature.native_resale_enabled','true'::jsonb,'r','k')$$,
  NULL, NULL, 'F18: anon cannot call set_platform_config');

SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key LIKE 'refund.%'), 0,
  'F19a: a plain authenticated fan reads zero refund.* rows');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key LIKE 'payout.%'), 0,
  'F19b: zero payout.* rows');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key LIKE 'authn.%'), 0,
  'F19c: zero authn.* rows');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key LIKE 'comp.%'), 0,
  'F19d: zero comp.* rows');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key LIKE 'crm%'), 0,
  'F19e: zero crm* rows');
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key LIKE 'door.%'), 0,
  'F19f: zero door.* rows — asserted PER NAMESPACE, because one key passing says nothing about five');
SELECT throws_ok(
  $$SELECT catalog.set_platform_config('feature.native_resale_enabled','true'::jsonb,'r','k')$$,
  NULL, NULL, 'F20: a plain fan cannot change config');

SELECT tap.login_service();
SELECT throws_ok(
  $$UPDATE catalog.platform_config SET value = '1'::jsonb WHERE key = 'wallet.apple.enabled'$$,
  NULL, NULL, 'F21: service_role cannot UPDATE config — T-RPC-CFG-04, the append-only property');
SELECT throws_ok(
  $$DELETE FROM catalog.platform_config WHERE key = 'wallet.apple.enabled'$$,
  NULL, NULL, 'F22: service_role cannot DELETE config');

SELECT tap.logout();
-- Asserted as postgres, because "no UPDATE path" is what makes an old snapshot
-- interpretable and a superuser bypasses every grant and every policy.
SELECT throws_ok(
  $$UPDATE catalog.platform_config SET value = '1'::jsonb WHERE key = 'wallet.apple.enabled'$$,
  NULL, NULL, 'F23: even postgres cannot UPDATE config — the AO trigger holds it');
SELECT throws_ok(
  $$DELETE FROM catalog.platform_config WHERE key = 'wallet.apple.enabled'$$,
  NULL, NULL, 'F24: even postgres cannot DELETE config');

-- ============================================================================
-- SECTION G — RPC BEHAVIOUR
-- ============================================================================

-- Fixtures: an org owned by seller, an approved venue, an event with a session.
SELECT tap.login(tap.seller());
SELECT tap._store142('org',
  (kernel.create_organization('Fixture LLC', 'Fixture', 'ck-org-1') ->> 'org_id'));

SELECT throws_ok(
  format($$SELECT catalog.create_venue(%L::uuid,'V','wynwood',NULL,'ck-v-1')$$, tap._fetch142('org')),
  NULL, NULL, 'G1: create_venue refuses while the org is only `applied` (not approved/active)');

SELECT tap.logout();
UPDATE kernel.organization SET status = 'approved' WHERE org_id = tap._fetch142('org')::uuid;

SELECT tap.login(tap.buyer());
SELECT throws_ok(
  format($$SELECT catalog.create_venue(%L::uuid,'V','wynwood',NULL,'ck-v-x')$$, tap._fetch142('org')),
  NULL, NULL, 'G2: a non-member cannot create a venue in someone else''s org');

SELECT tap.login(tap.seller());
SELECT tap._store142('venue',
  (catalog.create_venue(tap._fetch142('org')::uuid, 'Fixture Room', 'wynwood', NULL, 'ck-v-1')
   ->> 'venue_id'));
SELECT is((SELECT approval_status FROM catalog.venue WHERE venue_id = tap._fetch142('venue')::uuid),
  'draft', 'G3: approval_status is SERVER-DERIVED to draft — it is not a parameter');

SELECT throws_ok(
  format($$SELECT catalog.approve_venue(%L::uuid,'approved','miami_gate','ck-a-1')$$, tap._fetch142('venue')),
  NULL, NULL, 'G4: an org_owner cannot approve their own venue — the Miami gate is platform_admin only');

-- Grant platform_admin to the admin fixture and approve.
SELECT tap.logout();
INSERT INTO kernel.platform_role (identity_id, role, granted_by)
VALUES (tap.admin_user(), 'platform_admin', tap.admin_user());

SELECT tap.login(tap.admin_user());
SELECT throws_ok(
  format($$SELECT catalog.approve_venue(%L::uuid,'approved',NULL,'ck-a-2')$$, tap._fetch142('venue')),
  NULL, NULL, 'G5: approve_venue without a reason code raises reason_required');
SELECT is((catalog.approve_venue(tap._fetch142('venue')::uuid, 'approved', 'miami_gate', 'ck-a-1')
           ->> 'approval_status'), 'approved', 'G6: platform_admin approves the venue');
SELECT is((catalog.approve_venue(tap._fetch142('venue')::uuid, 'approved', 'miami_gate', 'ck-a-1')
           ->> 'status'), 'noop_replay', 'G7: re-approving is a noop_replay, not a second audit row');

SELECT tap.login(tap.seller());
SELECT tap._store142('event',
  (catalog.create_event(tap._fetch142('venue')::uuid, 'Opening Night',
     jsonb_build_object('starts_at', (now() + interval '10 days')::text,
                        'doors_at',  (now() + interval '10 days' - interval '1 hour')::text),
     'ck-e-1') ->> 'event_id'));
SELECT is((SELECT status FROM catalog.event WHERE event_id = tap._fetch142('event')::uuid), 'draft',
  'G8: a new event is draft');
SELECT is((SELECT count(*)::int FROM catalog.event_session
            WHERE event_id = tap._fetch142('event')::uuid), 1,
  'G9: create_event AUTO-CREATED the implicit first session (A1)');
SELECT is((SELECT org_id FROM catalog.event WHERE event_id = tap._fetch142('event')::uuid),
  tap._fetch142('org')::uuid,
  'G10: event.org_id is SERVER-DERIVED from the venue, never a parameter');
SELECT is((SELECT session_version FROM catalog.event_session
            WHERE event_id = tap._fetch142('event')::uuid), 1,
  'G11: the implicit session opens at session_version 1');

SELECT throws_ok(
  format($$SELECT catalog.update_event(%L::uuid,'{"venue_id":"%s"}'::jsonb,'ck-u-1')$$,
         tap._fetch142('event'), tap._fetch142('venue')),
  NULL, NULL, 'G12: T-RPC-CAT-01 — a patch naming venue_id raises invalid_input');
SELECT throws_ok(
  format($$SELECT catalog.update_event(%L::uuid,'{"status":"on_sale"}'::jsonb,'ck-u-2')$$, tap._fetch142('event')),
  NULL, NULL, 'G13: a patch naming status raises — that is publish_event (081), not this');
SELECT throws_ok(
  format($$SELECT catalog.update_event(%L::uuid,'{"org_id":"%s"}'::jsonb,'ck-u-3')$$,
         tap._fetch142('event'), tap._fetch142('org')),
  NULL, NULL, 'G14: a patch naming org_id raises');

SELECT is((catalog.update_event(tap._fetch142('event')::uuid,
             '{"description":"doors at ten","genre_tags":["house","techno"]}'::jsonb, 'ck-u-4')
           ->> 'status'), 'ok', 'G15: the marketing patch set is editable in draft');
SELECT is((SELECT genre_tags FROM catalog.event WHERE event_id = tap._fetch142('event')::uuid),
  ARRAY['house','techno'], 'G16: genre_tags round-trips as a text[]');

SELECT tap.logout();
UPDATE catalog.event SET status = 'on_sale' WHERE event_id = tap._fetch142('event')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(
  format($$SELECT catalog.update_event(%L::uuid,'{"title":"Renamed"}'::jsonb,'ck-u-5')$$, tap._fetch142('event')),
  NULL, NULL, 'G17: a title change after draft without a reason code raises');
SELECT is((catalog.update_event(tap._fetch142('event')::uuid,
             '{"title":"Renamed","reason_code":"promoter_request"}'::jsonb, 'ck-u-6') ->> 'status'),
  'ok', 'G18: with a reason code it succeeds and is audited');

SELECT tap.logout();
UPDATE catalog.event SET status = 'cancelled' WHERE event_id = tap._fetch142('event')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(
  format($$SELECT catalog.update_event(%L::uuid,'{"description":"x"}'::jsonb,'ck-u-7')$$, tap._fetch142('event')),
  NULL, NULL, 'G19: on a cancelled event EVERY patch raises event_terminal');

SELECT tap.logout();
UPDATE catalog.event SET status = 'draft' WHERE event_id = tap._fetch142('event')::uuid;

-- update_venue: the operatorship arm.
SELECT tap.login(tap.seller());
-- RED-B: matched on the MESSAGE, not on "any error". With a bare matcher this
-- passed on `unwritable_key reason_code` — the arm was unreachable and the test
-- could not tell.
SELECT throws_ok(
  format($$SELECT catalog.update_venue(%L::uuid,'{"org_id":"%s","reason_code":"sale"}'::jsonb,'ck-w-1')$$,
         tap._fetch142('venue'), tap._fetch142('org')),
  '42501', 'insufficient_privilege: operatorship change is platform_admin only',
  'G20: an org_owner cannot move operatorship — it is platform_admin only (RLS §11.1a)');
SELECT throws_ok(
  format($$SELECT catalog.update_venue(%L::uuid,'{"capacity_hint":900,"approval_status":"approved"}'::jsonb,'ck-w-2')$$,
         tap._fetch142('venue')),
  NULL, NULL, 'G21: update_venue refuses approval_status — that is approve_venue''s column');
SELECT is((catalog.update_venue(tap._fetch142('venue')::uuid,
             '{"capacity_hint":900}'::jsonb, 'ck-w-3') ->> 'status'), 'ok',
  'G22: a benign profile edit succeeds');

-- set_resale_policy: versioning is the whole contract.
SELECT throws_ok(
  format($$SELECT catalog.set_resale_policy('venue',%L::uuid,'{"mode":"fixed_cap","price_cap_bps":11000}'::jsonb,'ck-p-0')$$,
         tap._fetch142('venue')),
  NULL, NULL, 'G23: price_cap_bps above 10000 is refused');
SELECT throws_ok(
  format($$SELECT catalog.set_resale_policy('venue',%L::uuid,'{"mode":"capped"}'::jsonb,'ck-p-x')$$,
         tap._fetch142('venue')),
  NULL, NULL, 'G24: RPC §20.2.2''s `capped` is not a storable mode — schema §2.5 governs (errata)');
SELECT throws_ok(
  format($$SELECT catalog.set_resale_policy('org',%L::uuid,'{"mode":"off"}'::jsonb,'ck-p-y')$$,
         tap._fetch142('org')),
  NULL, NULL, 'G25: scope_kind `org` has no column to land in and is refused');
SELECT is((SELECT count(*)::int FROM catalog.resale_policy), 0,
  'G26: every refused policy call wrote NOTHING');
SELECT is((catalog.set_resale_policy('venue', tap._fetch142('venue')::uuid,
             '{"mode":"fixed_cap","price_cap_bps":1100}'::jsonb, 'ck-p-1') ->> 'version'), '1',
  'G27: the first accepted policy is version 1');
SELECT is((catalog.set_resale_policy('venue', tap._fetch142('venue')::uuid,
             '{"mode":"fixed_cap","price_cap_bps":1100}'::jsonb, 'ck-p-2') ->> 'status'),
  'noop_replay', 'G28: an identical policy is a noop_replay and issues NO new version');
SELECT is((catalog.set_resale_policy('venue', tap._fetch142('venue')::uuid,
             '{"mode":"fixed_cap","price_cap_bps":1000}'::jsonb, 'ck-p-3') ->> 'version'), '2',
  'G29: a tightening INSERTS version 2 and never mutates version 1');
SELECT is((SELECT price_cap_bps FROM catalog.resale_policy
            WHERE venue_id = tap._fetch142('venue')::uuid AND version = 1), 1100,
  'G30: version 1 is UNCHANGED — a listing that snapshotted it is still governed by it');

-- RED-B: a policy on a DRAFT event / UNAPPROVED venue must not be anon-readable.
-- set_resale_policy gates on org authority only and never on the parent's status,
-- so the policy predicate is the only thing standing between an unannounced
-- event's commercial terms and a signed-out client.
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'draft'
 WHERE venue_id = tap._fetch142('venue')::uuid;
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM catalog.resale_policy), 0,
  'G30a: anon reads ZERO resale policies while the parent venue is unapproved');
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'approved'
 WHERE venue_id = tap._fetch142('venue')::uuid;
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM catalog.resale_policy), 2,
  'G30b: with the venue approved anon reads that venue''s policy versions');
SELECT is((SELECT max(version)::int FROM catalog.resale_policy), 2,
  'G30c: including the current one, so a snapshotted (policy_id, version) always resolves');
SELECT tap.logout();

-- RED-A/RED-B: EVENT-scoped versioning. The lookup used to filter on venue_id,
-- which the coherence CHECK forces NULL on every event-scoped row, so every call
-- re-inserted version 1 and noop_replay was unreachable.
SELECT tap.login(tap.seller());
SELECT is((catalog.set_resale_policy('event', tap._fetch142('event')::uuid,
             '{"mode":"transfers_only"}'::jsonb, 'ck-pe-1') ->> 'version'), '1',
  'G30d: the first EVENT-scoped policy is version 1');
SELECT is((catalog.set_resale_policy('event', tap._fetch142('event')::uuid,
             '{"mode":"transfers_only"}'::jsonb, 'ck-pe-2') ->> 'status'), 'noop_replay',
  'G30e: an identical EVENT-scoped policy is noop_replay — it issues NO new version');
SELECT is((catalog.set_resale_policy('event', tap._fetch142('event')::uuid,
             '{"mode":"off"}'::jsonb, 'ck-pe-3') ->> 'version'), '2',
  'G30f: tightening an EVENT-scoped policy SUPERSEDES it at version 2');
-- as postgres: these are structural facts about the table, and a client read is
-- filtered by the parent-visibility predicate (the event is draft at this point).
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM catalog.resale_policy
            WHERE event_id = tap._fetch142('event')::uuid AND version = 1), 1,
  'G30g: exactly ONE version-1 row exists for the event — no duplicate accumulation');
SELECT throws_ok(
  format($$INSERT INTO catalog.resale_policy (scope_kind, event_id, mode, version)
           VALUES ('event', %L::uuid, 'buy_now', 1)$$, tap._fetch142('event')),
  '23505', NULL,
  'G30h: NULLS NOT DISTINCT — a duplicate (scope, version) is refused 23505, not silently stored');

-- The AO discipline on the version register, asserted as postgres because "no
-- UPDATE path" is what makes a listing's snapshot resolvable forever.
SELECT tap.logout();
SELECT throws_ok(
  $$UPDATE catalog.resale_policy SET mode = 'buy_now' WHERE version = 1$$,
  NULL, NULL, 'G31: resale_policy is append-only per version — a live snapshot cannot be mutated');
SELECT throws_ok(
  $$DELETE FROM catalog.resale_policy WHERE version = 1$$,
  NULL, NULL, 'G32: and it cannot be deleted, so a listing''s snapshot always resolves');

-- ---------------------------------------------------------------------------
-- The frozen anon/fan read tests (plan §8/078 Tests; RLS §16.11 T-RLS-CAT-01's
-- anon half — the venue-label half belongs to 080 with the deferred policies).
-- Asserted over the VISIBLE SET, never over the operator: a suite written
-- against `status >= 'announced'` passes on the broken clause, which is the
-- whole R3-3a defect.
-- ---------------------------------------------------------------------------
SELECT tap.logout();
UPDATE catalog.event SET status = 'draft' WHERE event_id = tap._fetch142('event')::uuid;

SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM catalog.venue
            WHERE venue_id = tap._fetch142('venue')::uuid), 1,
  'G33: anon CAN read an approved venue');
SELECT is((SELECT count(*)::int FROM catalog.event
            WHERE event_id = tap._fetch142('event')::uuid), 0,
  'G34: R3-3a — anon reads ZERO rows for a DRAFT event');
SELECT is((SELECT count(*)::int FROM catalog.event_session
            WHERE event_id = tap._fetch142('event')::uuid), 0,
  'G35: and ZERO sessions of that draft event — the child inherits the parent predicate');
SELECT throws_ok(
  format($$INSERT INTO catalog.event (venue_id, org_id, title) VALUES (%L::uuid, %L::uuid, 'x')$$,
         tap._fetch142('venue'), tap._fetch142('org')),
  NULL, NULL, 'G36: write as anon fails');

SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM catalog.event
            WHERE event_id = tap._fetch142('event')::uuid), 0,
  'G37: a plain authenticated fan also reads ZERO rows for a draft event');
SELECT is((SELECT count(*)::int FROM catalog.venue
            WHERE venue_id = tap._fetch142('venue')::uuid), 1,
  'G38: but CAN read the approved venue');

SELECT tap.logout();
UPDATE catalog.event SET status = 'announced' WHERE event_id = tap._fetch142('event')::uuid;
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM catalog.event
            WHERE event_id = tap._fetch142('event')::uuid), 1,
  'G39: once announced, anon CAN read it');
SELECT is((SELECT count(*)::int FROM catalog.event_session
            WHERE event_id = tap._fetch142('event')::uuid), 1,
  'G40: and its session becomes visible with it');
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'pending'
 WHERE venue_id = tap._fetch142('venue')::uuid;
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM catalog.venue
            WHERE venue_id = tap._fetch142('venue')::uuid), 0,
  'G41: a venue that is not `approved` is invisible to anon — equality, not an ordering');
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'approved'
 WHERE venue_id = tap._fetch142('venue')::uuid;

-- The org arm of the same policies: a member of the owning org DOES see the draft.
SELECT tap.logout();
UPDATE catalog.event SET status = 'draft' WHERE event_id = tap._fetch142('event')::uuid;
SELECT tap.login(tap.seller());
SELECT is((SELECT count(*)::int FROM catalog.event
            WHERE event_id = tap._fetch142('event')::uuid), 1,
  'G42: the owning org_owner DOES read the draft event — the org arm is not vacuous');
SELECT tap.logout();
UPDATE catalog.event SET status = 'announced' WHERE event_id = tap._fetch142('event')::uuid;

-- ============================================================================
-- SECTION H — set_platform_config: the two paths, and what cannot move
-- ============================================================================

SELECT tap.login(tap.admin_user());

SELECT throws_ok(
  $$SELECT catalog.set_platform_config('feature.native_resale_enabled','true'::jsonb,NULL,'ck-c-0')$$,
  NULL, NULL, 'H1: a missing reason code raises for EVERY key, not only the money ones');

-- Non-dual-control key: the direct path.
SELECT is((catalog.set_platform_config('feature.native_scanning_enabled','true'::jsonb,'gate_2b','ck-c-1')
           ->> 'status'), 'ok', 'H2: a non-money key takes the direct path');
SELECT is((SELECT max(version) FROM catalog.platform_config
            WHERE key = 'feature.native_scanning_enabled'), 2,
  'H3: the direct path INSERTED version 2 — config is append-only per version');
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE key = 'feature.native_scanning_enabled'), 2,
  'H4: version 1 still exists — an object governed by it stays interpretable');
SELECT is((SELECT visibility FROM catalog.platform_config
            WHERE key = 'feature.native_scanning_enabled' AND version = 2), 'public',
  'H5: T-SCHEMA-CFG-03 — visibility is COPIED FORWARD; set_platform_config cannot change it');

-- Dual-control key, LOOSENING => park.
SELECT is((catalog.set_platform_config('authn.money_role_maturity_hours','24'::jsonb,'onboarding','ck-c-2')
           ->> 'status'), 'parked',
  'H6: LOWERING the maturity window is a LOOSENING for this key and PARKS');
SELECT is((SELECT max(version) FROM catalog.platform_config
            WHERE key = 'authn.money_role_maturity_hours'), 1,
  'H7: a parked call inserted NO version — the UI must say "waiting for a second approver"');
SELECT tap.logout();   -- kernel.approval_request is a zero-policy deny-all table
SELECT is((SELECT count(*)::int FROM kernel.approval_request
            WHERE action = 'config.set_money_key'), 1,
  'H8: the park created exactly one approval_request');
SELECT is((SELECT required_approver_class FROM kernel.approval_request
            WHERE action = 'config.set_money_key'), 'platform_admin',
  'H9: AUTHZ-C1A2 — required_approver_class is SERVER-SET to platform_admin, never a parameter');
SELECT is((SELECT subject_kind FROM kernel.approval_request WHERE action = 'config.set_money_key'),
  'config_key', 'H10: APPR-SUBJ-1 — subject_kind is written in the same statement');
SELECT is((SELECT org_id FROM kernel.approval_request WHERE action = 'config.set_money_key'), NULL,
  'H11: a config request is org-unscoped');
SELECT is((SELECT payload ->> 'key' FROM kernel.approval_request WHERE action = 'config.set_money_key'),
  'authn.money_role_maturity_hours',
  'H12: the literal key travels in payload — subject_id is uuid and cannot carry it');
SELECT tap.login(tap.admin_user());

-- Dual-control key, TIGHTENING => direct. "A security control that is hard to
-- tighten in an incident is a liability."
SELECT throws_ok(
  $$SELECT catalog.set_platform_config('authn.money_role_maturity_hours','96'::jsonb,'incident','ck-c-3x')$$,
  NULL, NULL,
  'H12a: RPC §20.2.1 — a value outside MD-14''s admissible 24-72 h is refused bad_value');
SELECT throws_ok(
  $$SELECT catalog.set_platform_config('authn.money_role_maturity_hours','"72 hours"'::jsonb,'x','ck-c-3y')$$,
  NULL, NULL,
  'H12b: and a value of the wrong TYPE is refused — a key never changes shape');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('authn.money_role_maturity_hours', 2, '24'::jsonb, 'restricted');
SELECT tap.login(tap.admin_user());
SELECT is((catalog.set_platform_config('authn.money_role_maturity_hours','48'::jsonb,'incident','ck-c-3')
           ->> 'status'), 'ok',
  'H13: RAISING the maturity window inside the admissible range is a TIGHTENING and executes in one transaction');
SELECT is((SELECT max(version) FROM catalog.platform_config
            WHERE key = 'authn.money_role_maturity_hours'), 3,
  'H14: the tightening inserted a new version');

-- The incomparable arm: a non-scalar value on a money key must PARK whichever
-- direction it appears to move (T-RPC-CFG-02).
SELECT is((catalog.set_platform_config('refund.org_auto_execute_max_minor',
             '{"tiers":[1,2]}'::jsonb, 'experiment', 'ck-c-4') ->> 'status'), 'parked',
  'H15: T-RPC-CFG-02 — a jsonb OBJECT on a money key parks; not-comparable fails toward the approver');
SELECT is((catalog.set_platform_config('refund.buyer_fee_refundable','true'::jsonb,'policy','ck-c-5')
           ->> 'status'), 'parked',
  'H16: a boolean money key has no polarity and therefore parks');

-- The cross-config invariant is enforced by the writer, not only by the seed.
SELECT throws_ok(
  $$SELECT catalog.set_platform_config('door.manifest_ttl_interval','"2 hours"'::jsonb,'tighten','ck-c-6')$$,
  NULL, NULL,
  'H17: shrinking the manifest TTL below span+skew is REJECTED — the invariant binds the writer');

-- T-RPC-CFG-01, the frozen contract's own worked example, by name. This key is
-- the amount ABOVE WHICH a payout parks, so RAISING it is a LOOSENING.
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('payout.dual_control_min_minor', 2, '50000'::jsonb, 'restricted');
SELECT tap.login(tap.admin_user());
SELECT is((catalog.set_platform_config('payout.dual_control_min_minor','999999'::jsonb,'ops','ck-c-9')
           ->> 'status'), 'parked',
  'H18a: T-RPC-CFG-01 — RAISING payout.dual_control_min_minor PARKS');
SELECT is((SELECT max(version) FROM catalog.platform_config
            WHERE key = 'payout.dual_control_min_minor'), 2,
  'H18b: T-RPC-CFG-01 — and inserts no version');
SELECT is((catalog.set_platform_config('payout.dual_control_min_minor','100'::jsonb,'incident','ck-c-10')
           ->> 'status'), 'ok',
  'H18c: T-RPC-CFG-01 — LOWERING it executes in one transaction');

-- WALLET §11.5b: "A kill switch that needs a quorum is not a kill switch."
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('wallet.apple.enabled', 2, 'true'::jsonb, 'public');
SELECT tap.login(tap.admin_user());
SELECT is((catalog.set_platform_config('wallet.apple.enabled','false'::jsonb,'incident','ck-c-11')
           ->> 'status'), 'ok',
  'H18d: pulling the Wallet kill switch executes with ONE platform_admin');
SELECT is((catalog.set_platform_config('wallet.apple.enabled','true'::jsonb,'gate_clear','ck-c-12')
           ->> 'status'), 'parked',
  'H18e: turning it back ON is the mandatory-dual-control write and PARKS');

-- RPC §20.2.1 enumerates "a higher required AAL" as restrictive by name.
SELECT is((catalog.set_platform_config('authn.money_action_required_aal','"aal2"'::jsonb,'incident','ck-c-13')
           ->> 'status'), 'ok',
  'H18f: raising the required AAL executes — it is the incident tightening');
SELECT is((catalog.set_platform_config('authn.money_action_required_aal','"aal1"'::jsonb,'convenience','ck-c-14')
           ->> 'status'), 'parked',
  'H18g: lowering it back to aal1 PARKS');

-- comp.per_staff_step_up_window_hours has NO declared polarity: the corpus
-- declares a direction only for its _max_units half, so it takes §20.2.1's third
-- arm and parks in BOTH directions rather than guessing.
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('comp.per_staff_step_up_window_hours', 2, '24'::jsonb, 'restricted');
SELECT tap.login(tap.admin_user());
SELECT is((catalog.set_platform_config('comp.per_staff_step_up_window_hours','1'::jsonb,'ops','ck-c-15')
           ->> 'status'), 'parked',
  'H18h: SHRINKING the C39 comp counting window PARKS — it is a loosening of the insider-fraud gate');
SELECT is((catalog.set_platform_config('comp.per_staff_step_up_window_hours','48'::jsonb,'ops','ck-c-16')
           ->> 'status'), 'parked',
  'H18i: lengthening it parks too — no declared polarity means fail toward the approver');

-- The unknown-key arm, and the forbidden callers.
SELECT throws_ok(
  $$SELECT catalog.set_platform_config('refund.made_up_key','1'::jsonb,'r','ck-c-7')$$,
  NULL, NULL, 'H18: T-RPC-CFG-03 — a key not in the 078 registry raises unknown_key');

SELECT tap.logout();
INSERT INTO kernel.platform_role (identity_id, role, granted_by)
VALUES (tap.other_user(), 'platform_risk', tap.admin_user());
SELECT tap.login(tap.other_user());
SELECT throws_ok(
  $$SELECT catalog.set_platform_config('feature.native_resale_enabled','true'::jsonb,'r','ck-c-8')$$,
  NULL, NULL, 'H19: platform_risk holds hold_payout, NOT the thresholds — it is refused');
SELECT ok((SELECT count(*) FROM catalog.platform_config
            WHERE key LIKE 'refund.%') > 0,
  'H20: platform_risk DOES read both classes — it investigates against the thresholds');

-- ============================================================================
-- SECTION I — effective_freeze_at TOTALITY and money_role_grant_matured
-- ============================================================================

SELECT tap.logout();
SELECT tap._store142('sess',
  (SELECT session_id::text FROM catalog.event_session
    WHERE event_id = tap._fetch142('event')::uuid LIMIT 1));

SELECT isnt(catalog.effective_freeze_at(tap._fetch142('sess')::uuid), NULL,
  'I1: T-RPC-DOOR-08 — effective_freeze_at is NOT NULL with doors_at set and door_open_at NULL');
UPDATE catalog.event_session SET doors_at = NULL WHERE session_id = tap._fetch142('sess')::uuid;
SELECT isnt(catalog.effective_freeze_at(tap._fetch142('sess')::uuid), NULL,
  'I2: still NOT NULL with doors_at NULL — starts_at is the backstop');
SELECT is(catalog.effective_freeze_at(tap._fetch142('sess')::uuid),
  (SELECT starts_at FROM catalog.event_session WHERE session_id = tap._fetch142('sess')::uuid),
  'I3: with a zero offset the implicit boundary IS starts_at');
UPDATE catalog.event_session SET door_open_at = now() - interval '1 day'
 WHERE session_id = tap._fetch142('sess')::uuid;
SELECT ok(catalog.effective_freeze_at(tap._fetch142('sess')::uuid) < now(),
  'I4: an explicit door_open_at takes LEAST and pulls the boundary earlier');
SELECT throws_ok(
  $$SELECT catalog.effective_freeze_at('00000000-0000-0000-0000-00000000dead'::uuid)$$,
  NULL, NULL,
  'I5: an unknown session RAISES — the "tolerates a not-yet-existing id" escape hatch is WITHDRAWN');
-- door_open_at is write-once in prod (086 ledger-head guard); this suite probes
-- effective_freeze_at's read branches, so it resets the fixture behind the guard.
ALTER TABLE catalog.event_session DISABLE TRIGGER tg_door_open_at_is_ledger_head;
UPDATE catalog.event_session SET door_open_at = NULL, doors_at = starts_at - interval '1 hour'
 WHERE session_id = tap._fetch142('sess')::uuid;
ALTER TABLE catalog.event_session ENABLE TRIGGER tg_door_open_at_is_ledger_head;

-- money_role_grant_matured: the fail-to-safe behaviour, all four directions.
SELECT tap.login(tap.seller());
SELECT ok(NOT kernel.money_role_grant_matured(tap._fetch142('org')::uuid),
  'I6: a grant minted seconds ago is NOT mature at a 96-hour window');
SELECT tap.logout();
UPDATE kernel.org_member SET granted_at = now() - interval '365 days'
 WHERE org_id = tap._fetch142('org')::uuid AND identity_id = tap.seller();
SELECT tap.login(tap.seller());
SELECT ok(kernel.money_role_grant_matured(tap._fetch142('org')::uuid),
  'I7: a year-old org_owner grant IS mature');
SELECT ok(NOT kernel.money_role_grant_matured('00000000-0000-0000-0000-0000000000aa'::uuid),
  'I8: an org the caller holds no grant in returns FALSE, never an error');
SELECT tap.login(tap.buyer());
SELECT ok(NOT kernel.money_role_grant_matured(tap._fetch142('org')::uuid),
  'I9: a non-member returns false — the predicate is a conjunct, not the reporter');

-- T-RPC-AUTHZ-18: the config row is DELETED, not set to 0, because a missing seed
-- and a seeded zero behave identically only if the early return is actually there.
SELECT tap.logout();
ALTER TABLE catalog.platform_config DISABLE TRIGGER tg_platform_config_append_only;
DELETE FROM catalog.platform_config WHERE key = 'authn.money_role_maturity_hours';
ALTER TABLE catalog.platform_config ENABLE TRIGGER tg_platform_config_append_only;
SELECT tap.login(tap.seller());
SELECT ok(NOT kernel.money_role_grant_matured(tap._fetch142('org')::uuid),
  'I10: T-RPC-AUTHZ-18 — with the key DELETED, a year-old org_owner grant is NOT mature');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('authn.money_role_maturity_hours', 3, '72'::jsonb, 'restricted');
SELECT tap.login(tap.seller());
SELECT ok(kernel.money_role_grant_matured(tap._fetch142('org')::uuid),
  'I11: restoring the key restores maturity — the early return is the only thing that changed');
SELECT tap.logout();

-- ============================================================================
-- SECTION J — GATE-M STAYS DARK, AND THE SENTINELS (MB-5)
-- ============================================================================

-- 2026-08-31 (package 080): venue gained venue.staff_role — an AUTHORIZATION
-- surface, not a sale surface. The Gate-M anchor narrows to what it actually
-- guards: market stays empty, and venue holds nothing transactable.
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'market' AND c.relkind = 'r'), 0,
  'J1: NATIVE BUY NOW LIVE = NO — market holds no table');
SELECT is((SELECT string_agg(c.relname, ',' ORDER BY c.relname) FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'venue' AND c.relkind = 'r'),
  'comp_allocation,door_manifest,door_manifest_delta,door_manifest_entry,door_pin,door_session,guest_entry,guest_list,holder_mix_bucket,holder_mix_snapshot,inventory_batch,inventory_batch_shard,inventory_hold,inventory_movement,order,order_item,scan,scan_device,staff_role,ticket_type',
  -- 2026-08-31 (package 082): the two order tables arrived (082_venue_orders).
  -- 2026-09-01 (package 086): +12 door/scan tables (pin/session/scan_device/scan,
  -- comp_allocation, guest_list/_entry, manifest/_entry/_delta, holder_mix_*).
  -- market is still empty (native Buy Now dark).
  'J1b: venue holds the 080 staff + 081 inventory + 082 order + 086 door/scan tables — market still empty');
SELECT hasnt_function('market'::name, 'checkout_buy_now'::name,
  'J2: market.checkout_buy_now does not exist — seeding the TTL activated nothing');
SELECT is((SELECT count(*)::int FROM catalog.platform_config
            WHERE key LIKE 'feature.%' AND value = 'false'::jsonb AND version = 1), 3,
  'J3: all three native feature flags are seeded FALSE — the production-OFF anchor');

SELECT ok(EXISTS (SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-0000000000f0'),
  'J4: T-SCHEMA-SENTINEL-01a — SN-VOID exists in auth.users');
SELECT ok(EXISTS (SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-0000000000f1'),
  'J5: T-SCHEMA-SENTINEL-01b — SN-SYSTEM exists in auth.users');
SELECT ok(EXISTS (SELECT 1 FROM public.profiles WHERE id = '00000000-0000-0000-0000-0000000000f0'),
  'J6: T-SCHEMA-SENTINEL-01c — SN-VOID has its profiles row');
SELECT ok(EXISTS (SELECT 1 FROM public.profiles WHERE id = '00000000-0000-0000-0000-0000000000f1'),
  'J7: T-SCHEMA-SENTINEL-01d — SN-SYSTEM has its profiles row');
SELECT ok(EXISTS (SELECT 1 FROM kernel.identity_ext WHERE identity_id = '00000000-0000-0000-0000-0000000000f0'),
  'J8: T-SCHEMA-SENTINEL-01e — SN-VOID has its identity_ext row, so every kernel join is total');
SELECT ok(EXISTS (SELECT 1 FROM kernel.identity_ext WHERE identity_id = '00000000-0000-0000-0000-0000000000f1'),
  'J9: T-SCHEMA-SENTINEL-01f — SN-SYSTEM has its identity_ext row');
SELECT is((SELECT display_name FROM public.profiles WHERE id = '00000000-0000-0000-0000-0000000000f0'),
  'Voided — returned to issuer',
  'J10: the SN-VOID label is the frozen literal — the Transfer View renders it, not a blank');
SELECT is((SELECT display_name FROM public.profiles WHERE id = '00000000-0000-0000-0000-0000000000f1'),
  'Snatch It (automated)', 'J11: the SN-SYSTEM label is the frozen literal');

SELECT is((SELECT count(*)::int FROM auth.users
            WHERE id IN ('00000000-0000-0000-0000-0000000000f0','00000000-0000-0000-0000-0000000000f1')), 2,
  'J12: T-SCHEMA-SENTINEL-02 — the seed is idempotent: exactly two rows after replay');

-- T-SCHEMA-SENTINEL-03, asserted POSITIVELY: an identity that appears in the audit
-- ledger as an actor is exactly the one someone later "fixes" with a role grant.
SELECT is((SELECT count(*)::int FROM kernel.platform_role
            WHERE identity_id IN ('00000000-0000-0000-0000-0000000000f0','00000000-0000-0000-0000-0000000000f1')), 0,
  'J13: neither sentinel holds a kernel.platform_role row');
SELECT is((SELECT count(*)::int FROM kernel.org_member
            WHERE identity_id IN ('00000000-0000-0000-0000-0000000000f0','00000000-0000-0000-0000-0000000000f1')), 0,
  'J14: neither sentinel holds a kernel.org_member row');
SELECT tap.login('00000000-0000-0000-0000-0000000000f1'::uuid);
SELECT ok(NOT kernel.is_platform(ARRAY['platform_admin','platform_support','platform_risk']),
  'J15: is_platform returns FALSE for SN-SYSTEM');
SELECT ok(NOT kernel.has_org_role(tap._fetch142('org')::uuid, ARRAY['org_owner','org_admin']),
  'J16: has_org_role returns FALSE for SN-SYSTEM');
-- BOTH sentinels, because T-SCHEMA-SENTINEL-03 names both and a one-sentinel
-- test is exactly the shape the assertion exists to prevent. The has_venue_role
-- clause of -03 is unassertable until 080 and is filed forward in the errata.
SELECT tap.login('00000000-0000-0000-0000-0000000000f0'::uuid);
SELECT ok(NOT kernel.is_platform(ARRAY['platform_admin','platform_support','platform_risk']),
  'J16a: is_platform returns FALSE for SN-VOID too');
SELECT ok(NOT kernel.has_org_role(tap._fetch142('org')::uuid, ARRAY['org_owner','org_admin']),
  'J16b: has_org_role returns FALSE for SN-VOID too');
SELECT tap.logout();

-- T-SCHEMA-SENTINEL-04: non-authenticable by construction.
SELECT is((SELECT count(*)::int FROM auth.users
            WHERE id IN ('00000000-0000-0000-0000-0000000000f0','00000000-0000-0000-0000-0000000000f1')
              AND encrypted_password IS NULL), 2, 'J17: neither sentinel carries a password hash');
SELECT is((SELECT count(*)::int FROM auth.users
            WHERE id IN ('00000000-0000-0000-0000-0000000000f0','00000000-0000-0000-0000-0000000000f1')
              AND email_confirmed_at IS NULL), 2, 'J18: neither has a confirmed email');
SELECT is((SELECT count(*)::int FROM auth.users
            WHERE id IN ('00000000-0000-0000-0000-0000000000f0','00000000-0000-0000-0000-0000000000f1')
              AND email LIKE '%.internal'), 2, 'J19: both addresses are non-routable .internal');
SELECT is((SELECT count(*)::int FROM auth.users
            WHERE id IN ('00000000-0000-0000-0000-0000000000f0','00000000-0000-0000-0000-0000000000f1')
              AND role = 'authenticated'), 0,
  'J20: neither is person-shaped — role is not `authenticated`');

-- T-SCHEMA-SENTINEL-06: three distinct uuids, because two are supplied by the
-- spec and one is inherited from migration 019.
SELECT is((SELECT count(DISTINCT id)::int FROM auth.users
            WHERE id IN ('00000000-0000-0000-0000-000000000000',
                         '00000000-0000-0000-0000-0000000000f0',
                         '00000000-0000-0000-0000-0000000000f1')), 3,
  'J21: T-SCHEMA-SENTINEL-06 — the anonymization sentinel and the two platform sentinels are distinct');
-- T-SCHEMA-SENTINEL-05, the ANTI-SHORTCUT assertion, written as a standing
-- invariant over the custody tables rather than as a test of one function,
-- because the shortcut is taken at whichever call site the implementer is
-- looking at. kernel.tickets / ticket_ownership_log arrive in 079; until then the
-- invariant is asserted over the tables that DO exist and hold an identity.
SELECT is((SELECT count(*)::int FROM kernel.identity_ext
            WHERE identity_id = '00000000-0000-0000-0000-000000000000'), 0,
  'J22: T-SCHEMA-SENTINEL-05 — the 019 anonymization sentinel was NOT given a kernel identity row');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit
            WHERE actor_identity = '00000000-0000-0000-0000-000000000000'), 0,
  'J23: and it appears as an actor in ZERO kernel.admin_audit rows — SN-SYSTEM is the machine actor');

-- ============================================================================
-- SECTION K — 076 / 077 IMMUTABILITY UNDER 078
-- ============================================================================

SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'kernel' AND c.relkind = 'r'), 26,
  -- 2026-08-31 (package 082): 15 -> 17; (package 083): 17 -> 22 — the five
  -- credential/wallet tables.
  'K1: kernel holds twenty-six tables — 083 added five, 085 added the four money ledgers');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'notify' AND c.relkind = 'r'), 1,
  'K2: notify still holds only 076''s outbox');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel'), 99,
  -- 2026-08-31 (package 082): 52 -> 55; (package 083): 55 -> 75 (the twenty
  -- credential/wallet/mint functions; suite 147 names them).
  -- 2026-09-01 (package 086): 94 -> 99 (the five door/scan kernel fns; 141 F2/F3).
  'K3: kernel holds 99 functions — 94 post-085 plus 086''s five door/scan');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'kernel'), 12,
  -- 2026-08-31 (package 083): 11 -> 12 (kernel_signing_key_sel_public, PFA-16).
  -- 2026-08-31 (package 080): 10 -> 11 (kernel_tickets_sel_venue, AUTHZ-PKG1).
  -- 2026-08-31 (package 079): 8 -> 10 (the two kernel.tickets read policies).
  'K4: the kernel policy register holds twelve names — 11 post-080 plus 083''s signing_key public read');
SELECT is((SELECT count(*)::int FROM cron.job
            WHERE jobname IN ('sweep-deletion-pending','sweep-expired-org-invites')), 2,
  'K5: 077''s two cron entries are untouched');
SELECT throws_ok(
  $$SELECT kernel.grant_platform_role('00000000-0000-0000-0000-00000000beef'::uuid,'platform_admin','r','k')$$,
  NULL, NULL,
  'K6: PFA-4 — the platform-role grant plane is STILL FAIL-CLOSED; 078 did not implement it');

-- ============================================================================
-- SECTION L — HARDENING-1 (owner-approved; carried by this package)
-- ============================================================================

-- The witness, VERBATIM from the governance record.
SELECT ok(
  (SELECT pg_get_functiondef(k.oid) LIKE '%transaction_isolation%'
      AND pg_get_functiondef(k.oid) LIKE '%read committed%'
     FROM (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'
            OFFSET 0) k),
  'HARDENING-1: the deletion sweep carries the isolation guard (BP-11 re-check depends on per-statement snapshots)');

-- The guard is a BODY change only: signature, parameter names and return type are
-- exactly 077's, so no caller anywhere in the chain is re-bound.
SELECT is((SELECT pg_get_function_identity_arguments(p.oid)
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'), 'p_limit integer',
  'L2: the signature AND the parameter NAME are unchanged by the body replacement');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'), 1,
  'L3: exactly one sweep_deletion_pending exists — the replacement did not create an overload');
SELECT ok(
  (SELECT pg_get_functiondef(k.oid) LIKE '%BP-11: sole org_owner (re-verified under the org locks)%'
     FROM (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'
            OFFSET 0) k),
  'L4: the BP-11 re-check-under-org-locks the guard protects is still present, unmodified');

-- Behaviour: READ COMMITTED (the contracted caller's isolation) is unchanged.
SELECT is((SELECT (kernel.sweep_deletion_pending(1) ->> 'swept')::int), 0,
  'L5: under READ COMMITTED the sweep runs normally and finds nothing pending');

SELECT * FROM finish();
ROLLBACK;
