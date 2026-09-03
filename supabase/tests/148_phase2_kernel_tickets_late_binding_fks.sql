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
              AND c.relkind IN ('r','p','v','m','S','f')), 76,
  -- 2026-09-02 (package 093): 75 -> 75. RATIFIED CONTRACT CHANGE (no-op here) —
  -- 093 creates NO relation in any phase-2 schema; its two new objects are the
  -- partial unique indexes on venue.settlement_line (indexes are not relkind
  -- 'r'/'p'/'v'/'m'/'S'/'f'), so the guard is unmoved and stays exact.
  -- 2026-09-02 (package 092): 69 -> 75 (+6 notify reduced-plane tables).
  -- 2026-09-02 (package 091): 68 -> 69 (+1 kernel.reserve stub).
  -- 2026-09-02 (package 090): 62 -> 68 (+6 venue promoter-engine tables).
  -- 2026-09-02 (package 088): 55 -> 61 (+5 market rail tables, +1 kernel.dispute_native).
  -- 2026-09-02 (package 089): 61 -> 62 (+1 VIEW market.listing_unified — the ADOPT step's bridge).
  -- 2026-09-01 (package 086): 40 -> 52 (+12 venue door/scan tables).
  -- 2026-09-01 (package 087): 52 -> 55 (+3 venue: settlement, settlement_line, export_job).
  'B1: the five phase-2 schemas hold exactly 76 relations of ANY kind (69 post-091 + 092''s six notify tables + 094''s kernel.organization_obligation)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 270,
  -- 2026-09-03 (package 095, payout state machine): 259 -> 266. SEVEN added, zero removed
  -- (get_payout_execution_context was RE-CREATED body-only by 095 E-6, not added). The seven:
  -- guard_payout_org_payable and guard_settlement_forward_only (the two new trigger functions —
  -- no grant to any principal, 077 F1 sweep still zero), rearm_failed_payout and
  -- retry_held_payout (authenticated, +2 at F2), settlement_maturity_hold_codes
  -- (definer-internal constant, no grant), hold_payout_transfer_reversed and
  -- settlement_unbooked_refund_exposure (service_role, +2 at F3). Re-derived from the LIVE
  -- CATALOG, never by accepting a delta.
  -- 2026-09-02 (package 093, second money pass): 246 -> 250. RATIFIED CONTRACT CHANGE — four more
  -- kernel routines, from the two red-team P0 fixes and the refund executor:
  --   kernel.stage_org_connect_ref         ruling A7/A9 (RT-A-3) — the service_role-only provenance
  --                                        writer; binding an acct_ now requires the platform to have
  --                                        staged it, which is the whole of the two-key control.
  --   kernel.get_org_connect_ref           its read half.
  --   kernel.get_refund_execution_context  ruling D3 — the refund executor's server-side context.
  --   kernel.is_order_buyer                ruling F — the buyer predicate behind the column-scoped
  --                                        venue."order" surface.
  -- Still kernel-only: venue/catalog/market/notify stay at 79/16/22/17.
  -- 2026-09-02 (package 093): 243 -> 246. RATIFIED CONTRACT CHANGE —
  -- PRIMARY_TICKETING_OWNER_RATIFICATION.md ruling A6 (Stripe Connect ownership) adds
  -- kernel.sync_org_connect_state + kernel.get_org_connect_state; ruling A3 (durable venue
  -- obligation / settlement) adds kernel.settlement_primary_lines. THREE kernel routines and
  -- nothing else: venue/catalog/market/notify are unmoved (79/16/22/17), and every other
  -- 093 change to these schemas is a CREATE OR REPLACE at the frozen signature. The guard is
  -- as tight as before — a fourth routine dumped anywhere still trips it.
  -- 2026-09-02 (package 092): 228 -> 243 (+15 notify: the reduced 16 minus 076's emit_event; no hook replaced).
  -- 2026-09-02 (package 090): 207 -> 228 (+2 kernel, +19 venue; the three body-only hook replacements add no routine).
  -- 2026-09-02 (package 088): 183 -> 207 (+19 market, +4 kernel, +1 catalog; the seven body-only
  -- hook/PFA-13 replacements add no routine).
  -- 2026-09-01 (package 086): 126 -> 165 (+5 kernel, +28 venue, +4 catalog, +2 market).
  -- 2026-09-01 (package 087): 165 -> 183 (+4 kernel, +14 venue).
  -- 2026-09-03: 251 -> 253. 093 slice 30 §9/§10 (H6/F-3, F-4) adds kernel.authorize_org_payout_dashboard and kernel.guard_connect_id_not_org_bound.
  -- 2026-09-03 (package 093, payout-executor slice): 253 -> 259. SIX added, zero removed,
  -- re-derived from the LIVE CATALOG by diffing two rehearsal databases (one stopped at 092 via
  -- REHEARSAL_UPTO, one with 093) name-by-name, never by accepting a delta: kernel.settlement_payout_maturity
  -- and kernel.settlement_covered_payments (G2 — the maturity conjunction and its covered set, extracted
  -- from close_settlement's inline gate so the mint, the advance and the transfer share ONE definition;
  -- this is the D-1 closure) plus the payout executor's four (H8): claim_payouts_for_execution,
  -- get_payout_execution_context, hold_payout_destination_changed, record_payout_execution_note.
  -- All six are service_role-only definers. 141 A14a names all SIXTEEN of 093's kernel additions with
  -- their grant class, and 141 F3 moves 39 -> 45 by exactly these six.
  'B2: the five phase-2 schemas hold exactly 270 routines (136+79+16+22+17 — 093''s sixteen, 094''s four obligation routines and 095''s seven, all kernel)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 72,
  -- 2026-09-02 (package 092): 67 -> 72 (+5 notify owner policies: notification sel/upd, preference sel/ins/upd — RLS §16.9).
  -- 2026-09-02 (package 090): 57 -> 67 (+10 venue read policies: promoter 3, promoter_link 3, promoter_code 3,
  -- promoter_code_scope 1; attribution / attribution_review are deny-all zero-policy — AUTHZ-M9).
  -- 2026-09-02 (package 088): 52 -> 57 (+5 market read policies; market_sale and dispute_native
  -- are deny-all zero-policy).
  -- 2026-09-01 (package 086): 39 -> 48 (+9 venue door/scan policies; the 3 deny-all
  -- door/holder-mix tables carry none).
  -- 2026-09-01 (package 087): 48 -> 52 (+4 venue settlement read policies; export_job is
  -- deny-all zero-policy, OR-1).
  'B3: the five-schema policy register (12 kernel + 38 venue + 12 catalog + 5 market + 5 notify) — 092 added its five owner policies');
SELECT ok((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relkind='r') = 29
       AND (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel') = 136,
  -- 2026-09-03 (package 094, ORG OBLIGATION — 094_organization_obligation.sql): kernel TABLES
  -- 28 -> 29 and kernel functions 132 -> 136. Re-derived from the LIVE CATALOG by replaying the
  -- chain twice, once with this file removed. The table is kernel.organization_obligation, the
  -- org-side twin of kernel.identity_obligation (J3 §5.1) — the FIRST kernel relation added
  -- since 091's reserve stub. The four functions: organization_obligation_guard (the append-only
  -- trigger function — no grant to any principal, so 077 F1's sweep is still zero),
  -- record_organization_obligation + resolve_organization_obligation (the E-150 definer pair) and
  -- org_outstanding_obligation_minor (the read-only projection); the last three are service_role
  -- and move 141 F3 from 47 to 50. kernel.close_settlement was REPLACED body-only (093:640-854
  -- verbatim plus one `elsif v_net < 0` branch), not added.
  -- 2026-09-03 (package 095, payout state machine): 125 -> 132. SEVEN added, zero removed
  -- (get_payout_execution_context was RE-CREATED body-only by 095 E-6, not added). The seven:
  -- guard_payout_org_payable and guard_settlement_forward_only (the two new trigger functions —
  -- no grant to any principal, 077 F1 sweep still zero), rearm_failed_payout and
  -- retry_held_payout (authenticated, +2 at F2), settlement_maturity_hold_codes
  -- (definer-internal constant, no grant), hold_payout_transfer_reversed and
  -- settlement_unbooked_refund_exposure (service_role, +2 at F3). Re-derived from the LIVE
  -- CATALOG, never by accepting a delta.
  -- 2026-09-02 (package 093): kernel functions 109 -> 116. SEVEN new kernel routines, each named:
  -- settlement_primary_lines (A3) · sync_org_connect_state + get_org_connect_state (A6) ·
  -- stage_org_connect_ref + get_org_connect_ref (A7/A9, RT-A-3) · get_refund_execution_context (D3)
  -- · is_order_buyer (F). kernel TABLES are unmoved at 28 — 093 creates no table, so the relation
  -- half of this guard is untouched, and the two new objects it does create are partial indexes.
  -- 2026-09-03: 117 -> 119. 093 slice 30 §9/§10 (H6/F-3, F-4) adds kernel.authorize_org_payout_dashboard and kernel.guard_connect_id_not_org_bound.
  -- 2026-09-03 (package 093, payout-executor slice): 119 -> 125. SIX added, zero removed,
  -- re-derived from the LIVE CATALOG by diffing two rehearsal databases (one stopped at 092 via
  -- REHEARSAL_UPTO, one with 093) name-by-name, never by accepting a delta: kernel.settlement_payout_maturity
  -- and kernel.settlement_covered_payments (G2 — the maturity conjunction and its covered set, extracted
  -- from close_settlement's inline gate so the mint, the advance and the transfer share ONE definition;
  -- this is the D-1 closure) plus the payout executor's four (H8): claim_payouts_for_execution,
  -- get_payout_execution_context, hold_payout_destination_changed, record_payout_execution_note.
  -- All six are service_role-only definers. 141 A14a names all SIXTEEN of 093's kernel additions with
  -- their grant class, and 141 F3 moves 39 -> 45 by exactly these six.
  'B4: kernel per-schema census (29 tables post-094, 136 functions post-095)');
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
