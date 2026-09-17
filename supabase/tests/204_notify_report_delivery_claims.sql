-- 204_notify_report_delivery_claims.sql — pgTAP for migration 139 (G22).
-- Negative control: on the stack WITHOUT 139 the whole shape section fails at A1 and
-- every C assertion errors on the missing function — i.e. the suite cannot pass by shape.
-- Per-kind negative control (the "double send" this migration exists to stop) is C.2 / C.5 /
-- C.8: the SECOND claim of the same key must answer false. The mutant that kills them is
-- `on conflict (kind, claim_key) do nothing` → `do update set claimed_at = now()`, which makes
-- ROW_COUNT 1 forever and every one of those three flip to true.
BEGIN;
SELECT plan(41);
SELECT tap.seed_core();

CREATE FUNCTION tap._try204(stmt text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ' ' || SQLERRM; END $$;
CREATE FUNCTION tap._claim204(k text, v text) RETURNS boolean LANGUAGE sql AS $$ SELECT notify.claim_report_delivery(k, v) $$;
CREATE FUNCTION tap._rel204(k text, v text) RETURNS boolean LANGUAGE sql AS $$ SELECT notify.release_report_delivery(k, v) $$;

-- ── A. shape, RLS and the grant wall ────────────────────────────────────────
SELECT has_table('notify', 'report_delivery_claim', 'A1: the claim table exists in notify');
SELECT has_column('notify', 'report_delivery_claim', 'kind',       'A2: kind');
SELECT has_column('notify', 'report_delivery_claim', 'claim_key',  'A3: claim_key');
SELECT has_column('notify', 'report_delivery_claim', 'claimed_at', 'A4: claimed_at');
SELECT col_is_pk('notify', 'report_delivery_claim', ARRAY['kind','claim_key'],
  'A5: the primary key is (kind, claim_key) — the arbiter the claim relies on');
SELECT is((SELECT relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'notify' AND c.relname = 'report_delivery_claim'), true,
  'A6: RLS is enabled (157 B13 counts every notify table)');
SELECT is((SELECT count(*)::int FROM information_schema.role_table_grants
            WHERE table_schema = 'notify' AND table_name = 'report_delivery_claim'
              AND grantee IN ('anon','authenticated','service_role','PUBLIC')), 0,
  'A7: ZERO table grants — not even service_role (157 B9: the grant wall is service_role''s wall)');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'notify'
                   AND tablename = 'report_delivery_claim' AND indexname = 'report_delivery_claim_claimed_at_idx'),
  'A8: claimed_at is indexed so a later sweep has something to work with');

-- ── B. the verb ─────────────────────────────────────────────────────────────
SELECT has_function('notify', 'claim_report_delivery', ARRAY['text','text'], 'B1: notify.claim_report_delivery(text,text)');
SELECT is((SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'notify.claim_report_delivery(text,text)'::regprocedure), true,
  'B2: SECURITY DEFINER');
SELECT ok((SELECT 'search_path=""' = ANY(p.proconfig) FROM pg_proc p
            WHERE p.oid = 'notify.claim_report_delivery(text,text)'::regprocedure),
  'B3: search_path = '''' (067 discipline)');
SELECT is((SELECT r.rolname FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
            WHERE p.oid = 'notify.claim_report_delivery(text,text)'::regprocedure), 'postgres',
  'B4: owned by postgres');
SELECT ok(has_function_privilege('service_role', 'notify.claim_report_delivery(text,text)', 'EXECUTE'),
  'B5: service_role may execute it — the edge''s only way in');
SELECT ok(NOT has_function_privilege('authenticated', 'notify.claim_report_delivery(text,text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'notify.claim_report_delivery(text,text)', 'EXECUTE'),
  'B6: no client may execute it');

-- ── C. the behaviour: exactly one true per (kind, key) ──────────────────────
SELECT is(tap._claim204('report_created', 'r-1'), true,  'C1: the first claim of a report wins');
SELECT is(tap._claim204('report_created', 'r-1'), false, 'C2: the SECOND claim of the same report is refused — the duplicate send this migration exists to stop');
SELECT is(tap._claim204('report_created', 'r-2'), true,  'C3: a different report is its own claim');

SELECT is(tap._claim204('dispute_opened', 't-1'), true,  'C4: the first claim of a dispute wins');
SELECT is(tap._claim204('dispute_opened', 't-1'), false, 'C5: the second is refused');
SELECT is(tap._claim204('dispute_opened', 'r-1'), true,
  'C6: kind NAMESPACES the key — a dispute whose id equals a report id is a separate claim');

-- The signing alert: keyed on the RUN, never the alert text. Two different days
-- must BOTH send, or an unresolved compromise is announced once and then silenced.
SELECT is(tap._claim204('signing_invariant_alert', '2026-09-17'), true,  'C7: today''s monitor run announces');
SELECT is(tap._claim204('signing_invariant_alert', '2026-09-17'), false, 'C8: a double delivery of the SAME run collapses');
SELECT is(tap._claim204('signing_invariant_alert', '2026-09-18'), true,
  'C9: TOMORROW''S run announces again — the alarm is not silenced while the trust root stays wrong');
-- D's control, stated as D asked for it: leave the invariant violated for THREE
-- consecutive runs and assert THREE notices. A recurring alarm that dedupes is
-- not deduped, it is silenced — and it is silent exactly while the compromise lasts.
SELECT is(tap._claim204('signing_invariant_alert', '2026-09-19'), true,
  'C10: a third consecutive run with the SAME violation announces a third time');

-- ── R. the release (D's review of bcece84) ──────────────────────────────────
-- A claim taken before the send and never given back turns "at most once" into
-- "sometimes zero": notify-report swallows every delivery error and answers 200,
-- so a claimed event whose sends ALL failed stays claimed and is suppressed for
-- good. The signing alert self-heals through its run key; report_created and
-- dispute_opened have no next run.
SELECT has_function('notify', 'release_report_delivery', ARRAY['text','text'], 'R1: notify.release_report_delivery(text,text)');
SELECT is((SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'notify.release_report_delivery(text,text)'::regprocedure), true, 'R2: SECURITY DEFINER');
SELECT ok((SELECT 'search_path=""' = ANY(p.proconfig) FROM pg_proc p WHERE p.oid = 'notify.release_report_delivery(text,text)'::regprocedure), 'R3: search_path = ''''');
SELECT ok(has_function_privilege('service_role', 'notify.release_report_delivery(text,text)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'notify.release_report_delivery(text,text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'notify.release_report_delivery(text,text)', 'EXECUTE'),
  'R4: service_role only');
SELECT is(tap._rel204('report_created', 'r-1'), true, 'R5: releasing a held claim gives it back');
SELECT is(tap._claim204('report_created', 'r-1'), true,
  'R6: and the delivery can then be RETRIED — this is the difference between "at most once" and "sometimes zero"');
SELECT is(tap._rel204('report_created', 'never-claimed'), false, 'R7: releasing something never claimed reports false and changes nothing');
SELECT matches(tap._try204($$SELECT notify.release_report_delivery('report_created', NULL)$$), '^P0001', 'R8: a null key is refused');

-- ── D. arguments and storage ────────────────────────────────────────────────
SELECT matches(tap._try204($$SELECT notify.claim_report_delivery(NULL, 'k')$$), '^P0001', 'D1: a null kind is refused');
SELECT matches(tap._try204($$SELECT notify.claim_report_delivery('report_created', NULL)$$), '^P0001', 'D2: a null key is refused');
SELECT matches(tap._try204($$SELECT notify.claim_report_delivery('report_created', '')$$), '^P0001', 'D3: an empty key is refused');
SELECT is((SELECT count(*)::int FROM notify.report_delivery_claim), 7, 'D4: exactly seven claims were stored — no row per refused call');
-- D: truncate-then-dedupe is the wrong failure direction for a device whose job is
-- not silencing things — two different deliveries must never collapse into one claim.
SELECT matches(tap._try204($$SELECT notify.claim_report_delivery(repeat('k', 65), 'x')$$), '^P0001', 'D6: an over-length kind is REFUSED, not silently truncated');
SELECT matches(tap._try204($$SELECT notify.claim_report_delivery('report_created', repeat('k', 201))$$), '^P0001', 'D7: an over-length key is REFUSED, not silently truncated');
SELECT ok((SELECT claimed_at IS NOT NULL FROM notify.report_delivery_claim WHERE kind = 'report_created' AND claim_key = 'r-1'),
  'D5: the claim records when it was taken');

-- ── E. neighbours untouched ─────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'notify' AND c.relkind = 'r'), 9,
  'E1: notify holds nine tables — the eight before 139 plus this one (157 A7 pins the same number)');
SELECT is((SELECT count(*)::int FROM pg_proc WHERE pronamespace = 'notify'::regnamespace), 23,
  'E2: notify holds 23 routines — 20 before 139 plus claim_report_delivery and release_report_delivery, plus 141''s retire_account_deletion_pending (F-NOTICE-1, 2026-09-17) (157 A14)');

SELECT * FROM finish();
ROLLBACK;
