-- ============================================================================
-- 165_signing_monitor_and_invokers.sql — package 099.
--
-- SUBJECT: kernel.check_signing_key_invariants() (KJ §4.4, amended — dedupe,
--   nobody-executable), the five owner-unset config seeds it and the two
--   dark executor invokers share, and the three cron rows ('monitor-
--   signing-key-invariants', 'refund-execute-tick', 'payout-execute-tick').
--
-- THE PROPERTIES THIS FILE EXISTS TO PIN:
--   1. The monitor writes NOTHING while signing.monitor_enabled is false
--      (dark on apply).
--   2. Each of the seven alert codes fires on a targeted fixture (total_keys,
--      scoped_keys, active_global, rotating_keys, revoked_keys, fingerprint,
--      max_not_after) — demonstrated as KJ's own E8 run demonstrated them:
--      several necessarily co-occur (a second key always moves total_keys),
--      so "isolation" means each code is uniquely attributable to the
--      fixture change that introduced it, not that it fires alone forever.
--   3. An alerts array byte-identical to one already audited in the last 24h
--      writes NO new audit row and NO new egress attempt (dedupe).
--   4. Never a leak: no 'kms', no PEM header, no 64-hex fingerprint in any
--      audit row this function wrote.
--   5. EXECUTE is revoked from every grantable role — a new kernel.*
--      function is PUBLIC-executable by default (KJ E11) and this one must
--      not be.
--   6. The three cron rows exist with the EXACT command text 099 shipped —
--      a no-op while their gating key is false.
--   7. All five config seeds land at version 1, value false/null, restricted.
--
-- pg_net: the rehearsal harness's stand-in (scripts/rehearsal_bootstrap.sql)
--   is assumed present, matching KJ's own execution environment; the
--   checker's egress call is wrapped in `exception when others`, so even a
--   fully absent net.http_post degrades to a caught warning, never a test
--   failure — the assertions below never depend on the egress actually
--   reaching anywhere, only on the audit row and the returned jsonb.
--
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK. Fixtures are written as
--   postgres (house convention — no tap.login needed for this suite: no RLS-
--   scoped role behaviour is under test here, only the function's own logic
--   and the cron/config census).
-- ============================================================================
BEGIN;
SELECT plan(34);

SELECT tap.seed_core();

CREATE TABLE tap.memo_165 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store165(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_165 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch165(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_165 WHERE k = $1 $m$;

-- ============================================================================
-- SECTION A — the five config seeds (099 PART 1 + PART 2)
-- ============================================================================
SELECT is(
  (SELECT value::text || '|' || visibility FROM catalog.platform_config WHERE key = 'signing.monitor_enabled' AND version = 1),
  'false|restricted', 'A1: signing.monitor_enabled seeded v1 false, restricted');
SELECT is(
  (SELECT value::text || '|' || visibility FROM catalog.platform_config WHERE key = 'signing.expected_key_fingerprint' AND version = 1),
  'null|restricted', 'A2: signing.expected_key_fingerprint seeded v1 null, restricted');
SELECT is(
  (SELECT value::text || '|' || visibility FROM catalog.platform_config WHERE key = 'signing.expected_max_not_after' AND version = 1),
  'null|restricted', 'A3: signing.expected_max_not_after seeded v1 null, restricted');
SELECT is(
  (SELECT value::text || '|' || visibility FROM catalog.platform_config WHERE key = 'refund.executor_enabled' AND version = 1),
  'false|restricted', 'A4: refund.executor_enabled seeded v1 false, restricted');
SELECT is(
  (SELECT value::text || '|' || visibility FROM catalog.platform_config WHERE key = 'payout.executor_enabled' AND version = 1),
  'false|restricted', 'A5: payout.executor_enabled seeded v1 false, restricted');

-- ============================================================================
-- SECTION B — the function: exists, nobody may EXECUTE it
-- ============================================================================
SELECT has_function('kernel'::name, 'check_signing_key_invariants'::name, '{}'::name[],
  'B1: kernel.check_signing_key_invariants() exists');
SELECT ok(
  NOT has_function_privilege('anon', 'kernel.check_signing_key_invariants()', 'execute')
  AND NOT has_function_privilege('authenticated', 'kernel.check_signing_key_invariants()', 'execute')
  AND NOT has_function_privilege('service_role', 'kernel.check_signing_key_invariants()', 'execute'),
  'B2: EXECUTE revoked from anon, authenticated AND service_role (KJ E11 — default is PUBLIC-executable)');

-- ============================================================================
-- SECTION C — the three cron rows, exact command text
-- ============================================================================
SELECT is(
  (SELECT schedule || ' | ' || command FROM cron.job WHERE jobname = 'monitor-signing-key-invariants'),
  '23 5 * * * | select kernel.check_signing_key_invariants();',
  'C1: monitor-signing-key-invariants — daily 05:23 UTC, exact command');
SELECT is(
  (SELECT schedule || ' | ' || command FROM cron.job WHERE jobname = 'refund-execute-tick'),
  $exp$*/2 * * * * | select case when coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c where c.key = 'refund.executor_enabled' order by c.version desc limit 1), false) then net.http_post(url := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/refund-execute', headers := jsonb_build_object('Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' order by created_at desc limit 1), ''), 'Content-Type', 'application/json'), body := '{"action":"sweep","limit":25,"lease_seconds":900}'::jsonb) end;$exp$,
  'C2: refund-execute-tick — every 2 minutes, exact no-op-while-false command');
SELECT is(
  (SELECT schedule || ' | ' || command FROM cron.job WHERE jobname = 'payout-execute-tick'),
  $exp$*/10 * * * * | select case when coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c where c.key = 'payout.executor_enabled' order by c.version desc limit 1), false) then net.http_post(url := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/payout-execute', headers := jsonb_build_object('Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' order by created_at desc limit 1), ''), 'Content-Type', 'application/json'), body := '{"limit":25,"lease_seconds":900}'::jsonb) end;$exp$,
  'C3: payout-execute-tick — every 10 minutes, exact no-op-while-false command');

-- ============================================================================
-- SECTION D — dark on apply: disabled monitor writes nothing
-- ============================================================================
SELECT is((kernel.check_signing_key_invariants() ->> 'status'), 'monitor_disabled',
  'D1: disabled monitor returns monitor_disabled (signing.monitor_enabled is false at v1)');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 0,
  'D2: the disabled run wrote NO admin_audit row');

-- ============================================================================
-- SECTION E — arm the monitor (test-only: a new config VERSION, never an
--   UPDATE — catalog.platform_config is append-only even for postgres).
--   kernel.signing_key is empty: 0 rows.
-- ============================================================================
INSERT INTO catalog.platform_config (key, version, value, visibility)
  VALUES ('signing.monitor_enabled', 2, 'true'::jsonb, 'restricted');

-- 2026-09-03 (this reconciliation): E1/E2/E4 now read from ONE captured call instead of each
-- making its OWN fresh invocation. The ORIGINAL form called kernel.check_signing_key_invariants()
-- three separate times (E1, E2, E4) with IDENTICAL alert content each time; since the function
-- dedupes any repeat within 24h, E2's call (the second) already deduped against E1's (the
-- first) — which E3's audit count (1) only happened to prove BY ACCIDENT — and E4's call (the
-- third) was ALSO a repeat, so its actual 'deduped' was 'true', not the 'false' the assertion
-- wanted to prove. A pre-existing fixture bug (never actually run before this reconciliation).
-- Capturing E1's single real call and reading E2/E4 off the SAME jsonb makes every assertion
-- honest, and leaves F1 (below) as the genuinely FIRST repeat — its own dedupe=true assertion
-- is unaffected.
SELECT tap._store165('e1', kernel.check_signing_key_invariants()::text);
SELECT is((tap._fetch165('e1')::jsonb -> 'alerts'),
  '["total_keys=0","active_global=0","fingerprint=unpinned"]'::jsonb,
  'E1: enabled + empty table -> alerts = total_keys, active_global, fingerprint(unpinned) (KJ E8)');
SELECT is((tap._fetch165('e1')::jsonb ->> 'status'), 'alert', 'E2: status=alert while any code fires');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 1,
  'E3: the first alert run wrote exactly one admin_audit row');
SELECT is((tap._fetch165('e1')::jsonb ->> 'deduped'), 'false',
  'E4: a fresh (non-repeat) alert content is NOT marked deduped in its own return');

-- ============================================================================
-- SECTION F — dedupe: an identical alerts array within 24h writes nothing more
-- ============================================================================
SELECT is((kernel.check_signing_key_invariants() ->> 'deduped'), 'true',
  'F1: an immediate re-run with the SAME alerts content is marked deduped');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 1,
  'F2: the deduped re-run wrote NO additional admin_audit row (still exactly one)');

-- ============================================================================
-- SECTION G — the bootstrap global key: fingerprint isolates from the census codes
-- ============================================================================
-- 2026-09-03 (this reconciliation): 'PUBKEY' replaced with 'UFVCS0VZ' (base64 for the literal
-- bytes "PUBKEY") — the monitor recomputes sha256(decode(pem,'base64')) against THIS bootstrap
-- row (099:126-129), and a plain non-base64 placeholder made decode() throw "invalid base64 end
-- sequence" before any assertion could run. A pre-existing fixture bug (never actually run
-- before this reconciliation) — H's own fingerprint-pin literal (below) already derives itself
-- from whatever is stored here, so this swap changes no other assertion's expected value.
INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('00000000-0000-0000-0000-0000000000b0', 'global', NULL, NULL, 'UFVCS0VZ', 'kms-handle-opaque', 'active', now());

SELECT is((kernel.check_signing_key_invariants() -> 'alerts'), '["fingerprint=unpinned"]'::jsonb,
  'G1: one active global (bootstrap) key clears total_keys/active_global — only fingerprint=unpinned remains');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 2,
  'G2: a genuinely different alerts content is NOT deduped (second audit row lands)');

-- ============================================================================
-- SECTION H — fingerprint MATCH: pin the value the checker itself derives
-- ============================================================================
INSERT INTO catalog.platform_config (key, version, value, visibility)
  VALUES ('signing.expected_key_fingerprint', 2,
    to_jsonb(upper((
      SELECT encode(sha256(decode(regexp_replace(public_key,
               '-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]', '', 'g'), 'base64')), 'hex')
        FROM kernel.signing_key WHERE key_id = '00000000-0000-0000-0000-0000000000b0'
    ))), 'restricted');

SELECT is((kernel.check_signing_key_invariants() -> 'alerts'), '[]'::jsonb,
  'H1: the correct fingerprint (pinned UPPERCASE — lower() normalizes) -> zero alerts');
SELECT is((kernel.check_signing_key_invariants() ->> 'status'), 'ok', 'H2: status=ok with zero alerts');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 2,
  'H3: an ok run writes no admin_audit row (still exactly two from before)');

-- ============================================================================
-- SECTION I — fingerprint MISMATCH
-- ============================================================================
INSERT INTO catalog.platform_config (key, version, value, visibility)
  VALUES ('signing.expected_key_fingerprint', 3, to_jsonb(repeat('0', 64)), 'restricted');

SELECT is((kernel.check_signing_key_invariants() -> 'alerts'), '["fingerprint=MISMATCH"]'::jsonb,
  'I1: a wrong-but-well-formed pin -> fingerprint=MISMATCH, isolated');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 3,
  'I2: the MISMATCH content is new -> third audit row');

-- ============================================================================
-- SECTION J — max_not_after
-- ============================================================================
INSERT INTO catalog.platform_config (key, version, value, visibility)
  VALUES ('signing.expected_max_not_after', 2, to_jsonb((now() + interval '400 days')::text), 'restricted');

SELECT is((kernel.check_signing_key_invariants() -> 'alerts'),
  '["fingerprint=MISMATCH","max_not_after=null"]'::jsonb,
  'J1: a pinned not_after with no key not_after set -> max_not_after=null joins fingerprint=MISMATCH');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 4,
  'J2: fourth distinct alerts content -> fourth audit row');

-- ============================================================================
-- SECTION K — scoped_keys (ADV-7 shadow): a per_event key alongside the global one
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store165('org', (kernel.create_organization('Sig Co', 'Sig Co', 'ck-165-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status = 'approved' WHERE org_id = tap._fetch165('org')::uuid;

SELECT tap.login(tap.seller());
SELECT tap._store165('venue', (catalog.create_venue(tap._fetch165('org')::uuid, 'Sig Hall', 'wynwood', NULL, 'ck-165-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch165('venue')::uuid, 'approved', 'sig_gate', 'ck-165-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store165('event', (catalog.create_event(tap._fetch165('venue')::uuid, 'Sig Night',
  jsonb_build_object('starts_at', (now() + interval '30 days')::text, 'ends_at', (now() + interval '30 days 4 hours')::text),
  'ck-165-e1') ->> 'event_id'));
SELECT tap.logout();

INSERT INTO kernel.signing_key (scope, event_id, venue_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch165('event')::uuid, NULL, 'PUBKEY-SHADOW', 'kms-handle-shadow', 'active', now());

SELECT is((kernel.check_signing_key_invariants() -> 'alerts'),
  '["total_keys=2","scoped_keys=1","fingerprint=MISMATCH","max_not_after=null"]'::jsonb,
  'K1: a per_event shadow key moves total_keys AND scoped_keys together (ADV-7), isolating scoped_keys');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 5,
  'K2: fifth distinct alerts content -> fifth audit row');

-- ============================================================================
-- SECTION L — rotating_keys
-- ============================================================================
INSERT INTO kernel.signing_key (scope, event_id, venue_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('global', NULL, NULL, 'PUBKEY-ROT', 'kms-handle-rot', 'rotating', now());

SELECT is((kernel.check_signing_key_invariants() -> 'alerts'),
  '["total_keys=3","scoped_keys=1","rotating_keys=1","fingerprint=MISMATCH","max_not_after=null"]'::jsonb,
  'L1: a rotating global key isolates rotating_keys=1 against the same backdrop');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 6,
  'L2: sixth distinct alerts content -> sixth audit row');

-- ============================================================================
-- SECTION M — revoked_keys
-- ============================================================================
INSERT INTO kernel.signing_key (scope, event_id, venue_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('global', NULL, NULL, 'PUBKEY-REV', 'kms-handle-rev', 'revoked', now());

SELECT is((kernel.check_signing_key_invariants() -> 'alerts'),
  '["total_keys=4","scoped_keys=1","rotating_keys=1","revoked_keys=1","fingerprint=MISMATCH","max_not_after=null"]'::jsonb,
  'M1: a revoked global key isolates revoked_keys=1 against the same backdrop');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'signing_key.invariant_alert'), 7,
  'M2: seventh distinct alerts content -> seventh audit row (all seven alert codes now demonstrated)');

-- ============================================================================
-- SECTION N — leak regex: no key material or fingerprint hex in any audit row
-- ============================================================================
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM kernel.admin_audit
     WHERE action = 'signing_key.invariant_alert'
       AND (after::text ~* 'kms'
         OR after::text ~ '-----BEGIN'
         OR after::text ~ '[0-9a-fA-F]{64}')
  ),
  'N1: no admin_audit row for this action leaks "kms", a PEM header, or a 64-hex fingerprint');

SELECT * FROM finish();
ROLLBACK;
