-- =============================================================================
-- 208 — F-NOTICE-1: withdrawing an account deletion retires that user's pending
--       deletion notice, and nothing else (migration 141)
-- =============================================================================
-- The defect this pins: before 141, kernel.withdraw_account_deletion cleared the
-- deletion state and left the delivered `account_deletion_pending` notice live for
-- ever, so an ACTIVE account kept being told its deletion was requested.
--
-- WHICH ASSERTIONS CARRY WHICH CLAIM (the matrix, not a slogan — B's review of c70a9a6,
-- and the same class as 207's header sentence):
--   * fail on 077's body, i.e. they are the regression: B3, C3, D4. Measured, not asserted:
--     applying the rollback and re-running this file gives not_ok=3 — exactly B3, C3, D4 —
--     plus 4 psql errors, because the rollback DROPS notify.retire_account_deletion_pending
--     and F1-F3 then reference a routine that does not exist. So under the rollback F1-F3
--     do not evaluate at all; among the assertions that can evaluate, exactly three fail;
--   * fail if 141's predicate is WIDENED: C1 (another type, same user), C2 (same type,
--     another user), D3 (a notice already read keeps its own read_at);
--   * fail if the revoke is loosened: F1, F2, F3;
--   * fixtures and unchanged-077-behaviour controls, which pass either way: A1–A7, B1, B2,
--     D1, D2, E1, E2.
-- Runs as postgres inside BEGIN … ROLLBACK like every suite.
-- =============================================================================
BEGIN;
SELECT plan(22);

-- ── fixtures: the withdrawer, and a bystander who also has a deletion notice ──
CREATE FUNCTION tap._w208() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'a8a8a8a8-0208-4208-8208-a8a8a8a8a8a8'::uuid $f$;
CREATE FUNCTION tap._b208() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'b8b8b8b8-0208-4208-8208-b8b8b8b8b8b8'::uuid $f$;
INSERT INTO auth.users (id, email, aud, role, created_at) VALUES
  (tap._w208(), 'w208.withdrawer@test.local', 'authenticated', 'authenticated', now()),
  (tap._b208(), 'b208.bystander@test.local',  'authenticated', 'authenticated', now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id, display_name) VALUES
  (tap._w208(), 'W208'), (tap._b208(), 'B208') ON CONFLICT (id) DO NOTHING;

-- helper: the live/retired shape of one user's notices of one type
CREATE FUNCTION tap._n208(p_user uuid, p_type text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $f$
  SELECT coalesce(string_agg(
           'read=' || (n.read_at IS NOT NULL)::text || ' dismissed=' || (n.dismissed_at IS NOT NULL)::text,
           ' ; ' ORDER BY n.created_at), '(none)')
    FROM notify.notification n WHERE n.recipient_id = p_user AND n.type_key = p_type;
$f$;

-- ── A. both identities request deletion; the drain materialises both notices ──
SELECT tap.login(tap._w208());
SELECT is((kernel.request_account_deletion('w208-req'))->>'status', 'ok', '208 A1: the withdrawer requests deletion');
SELECT tap.logout();
SELECT tap.login(tap._b208());
SELECT is((kernel.request_account_deletion('b208-req'))->>'status', 'ok', '208 A2: the bystander requests deletion too');
SELECT tap.logout();
RESET ROLE;
SELECT ok((notify.drain_outbox(200) ->> 'resolved')::int >= 2, '208 A3: the drain materialises both notices');
SELECT is(tap._n208(tap._w208(), 'account_deletion_pending'), 'read=false dismissed=false',
  '208 A4: the withdrawer''s notice is live before the withdrawal');
SELECT is(tap._n208(tap._b208(), 'account_deletion_pending'), 'read=false dismissed=false',
  '208 A5: so is the bystander''s');

-- an UNRELATED notice for the same user — the type-scope control
SELECT ok(notify.enqueue(tap._w208(), 'purchase_confirmed', 'order', gen_random_uuid(),
          '{"amount_minor":"1000","currency":"USD"}'::jsonb, 'w208-purchase') IS NOT NULL,
  '208 A6: the withdrawer also has an unrelated notice of another type');
SELECT is(tap._n208(tap._w208(), 'purchase_confirmed'), 'read=false dismissed=false',
  '208 A7: ...and it is live');

-- ── B. the withdrawal retires exactly one notice ──────────────────────────────
CREATE TEMP TABLE _retired208 AS
  SELECT count(*)::int AS n FROM notify.notification WHERE read_at IS NOT NULL OR dismissed_at IS NOT NULL;
SELECT tap.login(tap._w208());
SELECT is((kernel.withdraw_account_deletion('w208-wd'))->>'status', 'ok', '208 B1: the withdrawal succeeds');
SELECT tap.logout();
RESET ROLE;
SELECT is((SELECT deletion_state || '/' || coalesce(deletion_requested_at::text, 'null')
             FROM kernel.identity_ext WHERE identity_id = tap._w208()), 'ACTIVE/null',
  '208 B2: the account is ACTIVE again with no requested_at — 077''s behaviour, unchanged');
SELECT is(tap._n208(tap._w208(), 'account_deletion_pending'), 'read=true dismissed=true',
  '208 B3 [F-NOTICE-1]: the withdrawer''s pending-deletion notice is RETIRED — the whole point');

-- ── C. negative controls: nothing else moved ──────────────────────────────────
SELECT is(tap._n208(tap._w208(), 'purchase_confirmed'), 'read=false dismissed=false',
  '208 C1 [control, by TYPE]: the same user''s unrelated notice is untouched');
SELECT is(tap._n208(tap._b208(), 'account_deletion_pending'), 'read=false dismissed=false',
  '208 C2 [control, by USER]: the bystander''s deletion notice is untouched — the predicate is auth.uid(), not the type alone');
SELECT is((SELECT count(*)::int FROM notify.notification
            WHERE (read_at IS NOT NULL OR dismissed_at IS NOT NULL)) - (SELECT n FROM _retired208), 1,
  '208 C3 [blast radius]: the withdrawal retired exactly ONE row in the whole database — a delta against the pre-count, so a database already carrying retired notices cannot fail this spuriously');

-- ── D. an already-read notice keeps its own timestamp (the coalesce) ──────────
-- target_kind comes from the type registry's closed set ('account_security'); 'identity' is the SUBJECT kind
INSERT INTO notify.notification (recipient_id, type_key, template_key, subject_kind, subject_id, target_kind, target_id, read_at, dedupe_key)
VALUES (tap._w208(), 'account_deletion_pending', 'account_deletion_pending', 'identity', tap._w208(),
        'account_security', tap._w208(), timestamptz '2026-09-01 00:00:00+00', 'w208-preread');
SELECT tap.login(tap._w208());
SELECT is((kernel.request_account_deletion('w208-req2'))->>'status', 'ok', '208 D1: the same identity requests again');
SELECT is((kernel.withdraw_account_deletion('w208-wd2'))->>'status', 'ok', '208 D2: and withdraws again');
SELECT tap.logout();
RESET ROLE;
SELECT is((SELECT read_at FROM notify.notification WHERE dedupe_key = 'w208-preread'),
          timestamptz '2026-09-01 00:00:00+00',
  '208 D3: a notice already read keeps its OWN read_at — coalesce, not an overwrite');
SELECT ok((SELECT dismissed_at IS NOT NULL FROM notify.notification WHERE dedupe_key = 'w208-preread'),
  '208 D4: ...and its dismissed_at is filled, so it stops showing');

-- ── E. idempotent, and still nothing outbound ─────────────────────────────────
SELECT tap.login(tap._w208());
SELECT is((kernel.withdraw_account_deletion('w208-wd3'))->>'status', 'noop_replay',
  '208 E1: withdrawing an ACTIVE account is still noop_replay — 077''s behaviour, unchanged');
SELECT tap.logout();
RESET ROLE;
SELECT is((SELECT count(*)::int FROM notify.outbox o
            WHERE o.aggregate_id = tap._w208() AND o.event_type <> 'account_deletion_pending'), 0,
  '208 E2: the withdrawal emits NO event of its own — no new type, nothing outbound');

-- ── F. the new routine's reach — pinned, or a later grant passes unnoticed ────
SELECT ok(NOT has_function_privilege('authenticated', 'notify.retire_account_deletion_pending(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'notify.retire_account_deletion_pending(uuid)', 'EXECUTE'),
  '208 F1: no client role may execute the retire');
SELECT ok(NOT has_function_privilege('service_role', 'notify.retire_account_deletion_pending(uuid)', 'EXECUTE'),
  '208 F2: service_role may not either — principle 4, it has no business retiring a user''s notices');
SELECT is((SELECT p.prosecdef::text || '/' || pg_get_userbyid(p.proowner) || '/' ||
                  (('search_path=""' = ANY(p.proconfig)))::text
             FROM pg_proc p WHERE p.oid = 'notify.retire_account_deletion_pending(uuid)'::regprocedure),
  'true/postgres/true',
  '208 F3: SECURITY DEFINER, owned by postgres, search_path = '''' (067 discipline)');

SELECT * FROM finish();
ROLLBACK;
