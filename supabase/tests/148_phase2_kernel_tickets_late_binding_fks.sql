-- ============================================================================
-- 148_phase2_kernel_tickets_late_binding_fks.sql — Phase-2 package 084 suite.
--
-- Frozen sources: PACKAGE_REGISTRY §084 · plan §8/084 · schema §1.6 · C42.
-- The ADOPT step and nothing else: the two late-binding FKs kernel.tickets
-- could not carry at birth, each NOT VALID + VALIDATE, ON DELETE RESTRICT.
-- The suite's second job is the plan's mandated DUMPING-GROUND GUARD: assert
-- the package created ZERO relations and ZERO routines (registry purity
-- invariant — the property that keeps 084's rollback unconditionally
-- reversible). Convention: BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(14);

SELECT tap.seed_core();

CREATE TABLE tap.memo_148 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store148(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_148 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch148(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_148 WHERE k = $1 $m$;

-- ============================================================================
-- SECTION A — THE TWO FKs, EXACTLY AS FROZEN (schema §1.6; plan §8/084)
-- ============================================================================
SELECT ok((SELECT c.contype='f' AND c.confrelid='venue.ticket_type'::regclass
              AND c.convalidated AND c.confdeltype='r'
              AND NOT c.condeferrable AND c.confupdtype='a'
             FROM pg_constraint c
            WHERE c.conrelid='kernel.tickets'::regclass AND c.conname='fk_tickets_ticket_type'),
  'A1: fk_tickets_ticket_type — FK -> venue.ticket_type, VALIDATED, RESTRICT, non-deferrable, ON UPDATE NO ACTION');
SELECT ok((SELECT c.contype='f' AND c.confrelid='kernel.signing_key'::regclass
              AND c.convalidated AND c.confdeltype='r'
              AND NOT c.condeferrable AND c.confupdtype='a'
             FROM pg_constraint c
            WHERE c.conrelid='kernel.tickets'::regclass AND c.conname='fk_tickets_signing_key'),
  'A2: fk_tickets_signing_key — FK -> kernel.signing_key, VALIDATED, RESTRICT, non-deferrable, ON UPDATE NO ACTION');
SELECT is((SELECT count(*)::int FROM pg_constraint
            WHERE conrelid='kernel.tickets'::regclass AND contype='f'), 5,
  'A3: tickets now carries FIVE outgoing FKs — the three 079 birth FKs + the two 084 adopts, no more');
-- C42: unit_row_id stays a BARE uuid — its EXT target was never built; a later
-- seating rollout adds that FK as ANOTHER adopt step, not an edit to 084.
SELECT is((SELECT count(*)::int FROM pg_constraint c
            WHERE c.conrelid='kernel.tickets'::regclass AND c.contype='f'
              AND c.conkey @> ARRAY[(SELECT attnum FROM pg_attribute
                    WHERE attrelid='kernel.tickets'::regclass AND attname='unit_row_id')]::int2[]), 0,
  'A4: unit_row_id appears in NO FK at any column position (C42 — EXT target, future adopt step)');

-- ============================================================================
-- SECTION B — THE DUMPING-GROUND GUARD (plan §8/084: "assert the package
-- creates zero relations and zero routines"; registry purity invariant)
-- ============================================================================
-- the FIVE-SCHEMA sweep: any relation or routine dumped into ANY phase-2 schema
-- by a future edit to 084 trips one of these two totals.
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('kernel','venue','catalog','market','notify')
              AND c.relkind IN ('r','p','v','m','S','f')), 68,
  -- 2026-09-02 (package 090): 62 -> 68 (+6 venue promoter-engine tables).
  -- 2026-09-02 (package 088): 55 -> 61 (+5 market rail tables, +1 kernel.dispute_native).
  -- 2026-09-02 (package 089): 61 -> 62 (+1 VIEW market.listing_unified — the ADOPT step's bridge).
  -- 2026-09-01 (package 086): 40 -> 52 (+12 venue door/scan tables).
  -- 2026-09-01 (package 087): 52 -> 55 (+3 venue: settlement, settlement_line, export_job).
  'B1: the five phase-2 schemas hold exactly 68 relations of ANY kind (62 post-089 + 090''s six tables)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 228,
  -- 2026-09-02 (package 090): 207 -> 228 (+2 kernel, +19 venue; the three body-only hook replacements add no routine).
  -- 2026-09-02 (package 088): 183 -> 207 (+19 market, +4 kernel, +1 catalog; the seven body-only
  -- hook/PFA-13 replacements add no routine).
  -- 2026-09-01 (package 086): 126 -> 165 (+5 kernel, +28 venue, +4 catalog, +2 market).
  -- 2026-09-01 (package 087): 165 -> 183 (+4 kernel, +14 venue).
  'B2: the five phase-2 schemas hold exactly 228 routines (109+79+16+22+2 — 090''s twenty-one)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 67,
  -- 2026-09-02 (package 090): 57 -> 67 (+10 venue read policies: promoter 3, promoter_link 3, promoter_code 3,
  -- promoter_code_scope 1; attribution / attribution_review are deny-all zero-policy — AUTHZ-M9).
  -- 2026-09-02 (package 088): 52 -> 57 (+5 market read policies; market_sale and dispute_native
  -- are deny-all zero-policy).
  -- 2026-09-01 (package 086): 39 -> 48 (+9 venue door/scan policies; the 3 deny-all
  -- door/holder-mix tables carry none).
  -- 2026-09-01 (package 087): 48 -> 52 (+4 venue settlement read policies; export_job is
  -- deny-all zero-policy, OR-1).
  'B3: the five-schema policy register (12 kernel + 38 venue + 12 catalog + 5 market) — 090 added its ten promoter-engine read policies');
SELECT ok((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relkind='r') = 27
       AND (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel') = 109,
  'B4: kernel per-schema census (27 tables, 109 functions post-090)');
SELECT ok((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue') = 79
       AND (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='market' AND c.relkind='r') = 5,
  'B5: venue holds 79 functions (60 post-087 + 090''s nineteen), market holds its five 088 rail tables');

-- ============================================================================
-- SECTION C — THE FKs BITE (plan §8/084 staging verification)
-- ============================================================================
-- fixture: org -> venue -> event -> session -> ticket_type + a direct signing key
SELECT tap.login(tap.seller());
SELECT tap._store148('org', (kernel.create_organization('Adopt Co','Adopt Co','ck84-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch148('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store148('venue', (catalog.create_venue(tap._fetch148('org')::uuid,'Adopt Hall','wynwood',NULL,'ck84-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch148('venue')::uuid,'approved','miami_gate','ck84-a');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store148('event', (catalog.create_event(tap._fetch148('venue')::uuid,'Adopt Night',
  jsonb_build_object('starts_at',(now()+interval '25 days')::text,'ends_at',(now()+interval '25 days 5 hours')::text),'ck84-e') ->> 'event_id'));
SELECT tap._store148('session', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch148('event')::uuid));
SELECT tap._store148('tt', (venue.create_ticket_type(tap._fetch148('event')::uuid,'admission','GA',5000,'public','ck84-tt') ->> 'ticket_type_id'));
SELECT tap.logout();
WITH insk AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch148('event')::uuid, 'PUBKEY-84', 'kms-84', 'active', now())
  RETURNING key_id
)
SELECT tap._store148('key', (SELECT key_id::text FROM insk));

-- a bogus ticket_type_id is now REJECTED at the row layer
SELECT throws_ok(format($$INSERT INTO kernel.tickets (event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, signing_key_id)
  VALUES (%L, %L, gen_random_uuid(), 9001, %L, %L)$$,
    tap._fetch148('session'), tap._fetch148('org'), tap.buyer(), tap._fetch148('key')),
  '23503', NULL, 'C1: a ticket with a BOGUS ticket_type_id is rejected (fk_tickets_ticket_type bites)');
-- a bogus signing_key_id is now REJECTED at the row layer
SELECT throws_ok(format($$INSERT INTO kernel.tickets (event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, signing_key_id)
  VALUES (%L, %L, %L, 9002, %L, gen_random_uuid())$$,
    tap._fetch148('session'), tap._fetch148('org'), tap._fetch148('tt'), tap.buyer()),
  '23503', NULL, 'C2: a ticket with a BOGUS signing_key_id is rejected (fk_tickets_signing_key bites)');
-- a coherent row still inserts (the FKs constrain, they do not block the mint's
-- shape). NOTE: this row has no ownership-log pair — legal ONLY because the 079
-- custody verify trigger is INITIALLY DEFERRED and this suite ends in ROLLBACK
-- (COMMIT never happens); a COMMIT-based harness refactor would trip it.
SELECT lives_ok(format($$INSERT INTO kernel.tickets (event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, signing_key_id)
  VALUES (%L, %L, %L, 1, %L, %L)$$,
    tap._fetch148('session'), tap._fetch148('org'), tap._fetch148('tt'), tap.buyer(), tap._fetch148('key')),
  'C3: a coherent ticket row (real ticket_type + real signing_key) inserts cleanly');
-- ON DELETE RESTRICT bites in both directions
SELECT throws_ok(format($$DELETE FROM venue.ticket_type WHERE ticket_type_id=%L$$, tap._fetch148('tt')),
  '23503', NULL, 'C4: a ticket_type referenced by an atom cannot be deleted (RESTRICT)');
SELECT throws_ok(format($$DELETE FROM kernel.signing_key WHERE key_id=%L$$, tap._fetch148('key')),
  '23503', NULL, 'C5: a signing_key referenced by an atom cannot be deleted (RESTRICT — history stays verifiable)');

SELECT finish();
ROLLBACK;
