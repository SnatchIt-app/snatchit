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
             FROM pg_constraint c
            WHERE c.conrelid='kernel.tickets'::regclass AND c.conname='fk_tickets_ticket_type'),
  'A1: fk_tickets_ticket_type — FK -> venue.ticket_type, VALIDATED, ON DELETE RESTRICT');
SELECT ok((SELECT c.contype='f' AND c.confrelid='kernel.signing_key'::regclass
              AND c.convalidated AND c.confdeltype='r'
             FROM pg_constraint c
            WHERE c.conrelid='kernel.tickets'::regclass AND c.conname='fk_tickets_signing_key'),
  'A2: fk_tickets_signing_key — FK -> kernel.signing_key, VALIDATED, ON DELETE RESTRICT');
SELECT is((SELECT count(*)::int FROM pg_constraint
            WHERE conrelid='kernel.tickets'::regclass AND contype='f'), 5,
  'A3: tickets now carries FIVE outgoing FKs — the three 079 birth FKs + the two 084 adopts, no more');
-- C42: unit_row_id stays a BARE uuid — its EXT target was never built; a later
-- seating rollout adds that FK as ANOTHER adopt step, not an edit to 084.
SELECT is((SELECT count(*)::int FROM pg_constraint c
            WHERE c.conrelid='kernel.tickets'::regclass AND c.contype='f'
              AND (SELECT attname FROM pg_attribute
                    WHERE attrelid=c.conrelid AND attnum = c.conkey[1]) = 'unit_row_id'), 0,
  'A4: unit_row_id carries NO FK (C42 — EXT target, future adopt step)');

-- ============================================================================
-- SECTION B — THE DUMPING-GROUND GUARD (plan §8/084: "assert the package
-- creates zero relations and zero routines"; registry purity invariant)
-- ============================================================================
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relkind='r'), 22,
  'B1: kernel still holds exactly 22 tables — 084 created ZERO relations');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel'), 75,
  'B2: kernel still holds exactly 75 functions — 084 created ZERO routines');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue'), 15,
  'B3: venue still holds exactly 15 functions');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='market' AND c.relkind='r'), 0,
  'B4: market still holds NO table');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='kernel'), 12,
  'B5: the kernel policy register is untouched (still 12) — no RLS rode along');

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
-- a coherent row still inserts (the FKs constrain, they do not block the mint's shape)
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
