-- ============================================================================
-- 143_phase2_ticket_custody_kernel.sql — Phase-2 package 079 test suite.
--
-- Frozen sources: plan §8/079 Tests row · schema §1.5/§1.5.1/§1.6/§1.6.1 (C26
-- rig a–d)/§1.6.2 (T-SCHEMA-CUSTODY-01..-05)/§7.6 · DOOR §8.1 · RPC §7.4/§7.5
-- (T-RPC-DOOR-01 structural)/§12.4a-c/§12.5 (T-SCHEMA-EXPIRY-01)/§20.2.4
-- (T-RPC-CAT-02) · RLS §7.5/§7.6/§11/§16.10 · dsm §2 BP-1 · §20.17.5 SEAM-2a ·
-- CRON register row 079 · E-15 discharge (the REAL T-SCHEMA-SENTINEL-05) ·
-- E-18 witness (ticket.expiry_grace fail-inert) · PFA-13 witness (unlock
-- resolves to 'none'; the R-40 dispute arm is 088's body-only replacement).
--
-- T-SCHEMA-CUSTODY-06 (void sentinel equality) is OWED BY 085: its subject,
-- kernel.void_ticket_atom, does not exist here — asserted absent below.
-- The deferred-vs-order-dependent half of -02 (head-first statement order
-- committing) needs a real COMMIT and lives in the out-of-suite concurrency
-- battery; in-suite, SET CONSTRAINTS IMMEDIATE pins every clause.
-- Convention: BEGIN … plan(N) … finish() … ROLLBACK (no committed state).
-- ============================================================================
BEGIN;
SELECT plan(154);

SELECT tap.seed_core();

CREATE TABLE tap.memo_143 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store143(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_143 VALUES (k, v)
    ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch143(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_143 WHERE k = $1 $m$;

-- definer bridges: the real callers of the §7.4/§7.5 primitives are definer
-- RPCs in later packages; these stand in for them so the primitives' own
-- auth.uid()-based preconditions are exercised against real personas.
CREATE FUNCTION tap._lock(p uuid, r text, k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT kernel.lock_ticket(p, r, k) $m$;
CREATE FUNCTION tap._unlock(p uuid, k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT kernel.unlock_ticket(p, k) $m$;
CREATE FUNCTION tap._scan(p uuid, s uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT kernel.mark_ticket_scanned(p, s, '{}'::jsonb) $m$;
GRANT EXECUTE ON FUNCTION tap._lock(uuid,text,text), tap._unlock(uuid,text),
  tap._scan(uuid,uuid) TO authenticated;

-- ============================================================================
-- SECTION A — THE 079 CLOSED WORLD (parity: EXTRA = 0, MISSING = 0)
-- ============================================================================

SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'kernel' AND c.relkind = 'r'), 22,
  'A1: kernel holds EXACTLY twenty-two tables (17 post-082 + five 083 credential/wallet)');
SELECT has_table('kernel'::name, 'tickets'::name, 'A2: kernel.tickets exists');
SELECT has_table('kernel'::name, 'ticket_ownership_log'::name, 'A3: the custody ledger exists');
SELECT has_table('kernel'::name, 'door_freeze_override'::name,
  'A4: door_freeze_override lives in kernel (custody authority, §13.5-B), at 079 (FR-7)');

SELECT is((SELECT count(*)::int FROM information_schema.columns
            WHERE table_schema = 'kernel' AND table_name = 'tickets'), 17,
  'A5: kernel.tickets carries exactly the seventeen §1.5 columns');
SELECT is((SELECT count(*)::int FROM information_schema.columns
            WHERE table_schema = 'kernel' AND table_name = 'ticket_ownership_log'), 12,
  'A6: the ledger carries exactly the twelve §1.6 columns');
SELECT col_type_is('kernel','ticket_ownership_log','state_transition','jsonb',
  'A7: state_transition is jsonb');
SELECT col_is_null('kernel','tickets','seat_ref', 'A8: seat_ref nullable (C42 hedge)');
SELECT col_is_null('kernel','tickets','unit_row_id', 'A9: unit_row_id nullable, bare uuid (EXT target)');
SELECT is((SELECT count(*)::int FROM information_schema.table_constraints
            WHERE table_schema='kernel' AND table_name='tickets'
              AND constraint_type='FOREIGN KEY'), 3,
  'A10: tickets carries THREE FKs — ticket_type_id/signing_key_id FKs are 084''s (adopt), not here');
SELECT col_not_null('kernel','tickets','ticket_type_id',
  'A11: ticket_type_id NOT NULL now (no row can exist before the mint engine)');
SELECT col_not_null('kernel','tickets','signing_key_id', 'A12: signing_key_id NOT NULL now');

-- the C26 keys, by name (the fixed three-column form)
SELECT has_index('kernel','ticket_ownership_log','ownership_log_cause_uq',
  'A13: UNIQUE(cause, cause_ref, ticket_atom_id) exists — THE C26 key');
SELECT has_index('kernel','ticket_ownership_log','ownership_log_command_uq',
  'A14: UNIQUE(ticket_atom_id, command_idempotency_key) exists (C16)');
SELECT col_is_pk('kernel','ticket_ownership_log', ARRAY['ticket_atom_id','sequence'],
  'A15: composite PK (ticket_atom_id, sequence)');
SELECT has_index('kernel','tickets','tickets_session_serial_uq',
  'A16: UNIQUE(event_session_id, serial_no)');
SELECT has_index('kernel','tickets','tickets_session_external_seat_uq',
  'A17: external_seat_ref unique per session where not null (C17)');
SELECT has_index('kernel','tickets','tickets_resale_partial_idx',
  'A18: partial index on resale_state <> ''none''');
SELECT has_index('kernel','door_freeze_override','door_freeze_override_live_idx',
  'A19: the live-override partial index exists (revocation predicate; E-19: now() cannot sit in an index predicate)');

-- RLS posture
SELECT ok((SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relname='tickets'), 'A20: RLS ON kernel.tickets');
SELECT ok((SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relname='ticket_ownership_log'), 'A21: RLS ON the ledger');
SELECT ok((SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relname='door_freeze_override'), 'A22: RLS ON the override table');
SELECT is((SELECT string_agg(p.polname, ',' ORDER BY p.polname)
            FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
           WHERE c.relname = 'tickets'),
  -- 2026-08-31 (package 080): the deferred venue read landed (suite 144 owns it).
  'kernel_tickets_sel_owner,kernel_tickets_sel_platform,kernel_tickets_sel_venue',
  'A23: EXACTLY three policies on kernel.tickets — the 080-deferred venue read arrived (AUTHZ-PKG1)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
           WHERE c.relname = 'ticket_ownership_log'), 0,
  'A24: ZERO policies on the ledger — money-custody-RPC-only, deny-all (RLS §7.6)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
           WHERE c.relname = 'door_freeze_override'), 0,
  'A25: ZERO policies on door_freeze_override — audit-only (DOOR §8.1)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname IN ('kernel','catalog')
             AND coalesce(btrim(pg_get_expr(p.polqual, p.polrelid)),'') = 'true'), 0,
  'A26: I-2 — still no USING(true) anywhere in kernel or catalog');

-- table grants (I-7)
-- 2026-08-31 (package 080/E-24): the grant is COLUMN-scoped — current_owner_id
-- (owner PII, §7.5 fn8) is excluded; any granted column satisfies this probe.
SELECT ok(has_column_privilege('authenticated','kernel.tickets','ticket_atom_id','SELECT'),
  'A27: authenticated holds column-scoped SELECT on tickets (rows scoped by the policies)');
SELECT ok(NOT has_table_privilege('authenticated','kernel.tickets','INSERT')
       AND NOT has_table_privilege('authenticated','kernel.tickets','UPDATE')
       AND NOT has_table_privilege('authenticated','kernel.tickets','DELETE'),
  'A28: authenticated holds NO DML on tickets — writes are RPC-only');
SELECT ok(NOT has_table_privilege('anon','kernel.tickets','SELECT'),
  'A29: anon holds nothing on tickets');
SELECT ok(NOT has_table_privilege('authenticated','kernel.ticket_ownership_log','SELECT'),
  'A30: the ledger is deny-all to authenticated (redacted RPC read arrives in 088)');
SELECT ok(NOT has_table_privilege('authenticated','kernel.door_freeze_override','SELECT'),
  'A31: the override table is deny-all to authenticated');

-- function closed world + EXEC classes
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'kernel'), 75,
  -- 2026-08-31 (package 082): 52 -> 55; (package 083): 55 -> 75 (twenty credential/wallet/mint fns).
  'A32: kernel holds EXACTLY 75 functions (55 post-082 + the twenty 083 fns)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'catalog'), 11,
  -- 2026-08-31 (package 081): 10 -> 11 (publish_event, SEAM-1).
  'A33: catalog holds EXACTLY 11 functions (10 post-079 + publish_event, SEAM-1)');
SELECT ok(has_function_privilege('authenticated','kernel.is_transfer_frozen(uuid)','EXECUTE'),
  'A34: is_transfer_frozen EXEC authenticated — the RN eligibility boolean (RLS §11.4)');
SELECT ok(has_function_privilege('authenticated','catalog.update_event_session(uuid, jsonb, text)','EXECUTE'),
  'A35: update_event_session EXEC authenticated (caller-authorized, RLS §11.1)');
SELECT ok(NOT has_function_privilege('authenticated','kernel.lock_ticket(uuid, text, text)','EXECUTE')
       AND NOT has_function_privilege('anon','kernel.lock_ticket(uuid, text, text)','EXECUTE'),
  'A36: lock_ticket is DEF — no client EXECUTE');
SELECT ok(NOT has_function_privilege('authenticated','kernel.unlock_ticket(uuid, text)','EXECUTE'),
  'A37: unlock_ticket is DEF');
SELECT ok(NOT has_function_privilege('authenticated','kernel.mark_ticket_scanned(uuid, uuid, jsonb)','EXECUTE'),
  'A38: mark_ticket_scanned is DEF — never client-callable (an admission-state write)');
SELECT ok(NOT has_function_privilege('authenticated','kernel.sweep_expired_ticket_atoms(int)','EXECUTE')
       AND NOT has_function_privilege('anon','kernel.sweep_expired_ticket_atoms(int)','EXECUTE'),
  'A39: the expiry sweep refuses every client class (§12.5)');
SELECT ok(has_function_privilege('service_role','kernel.sweep_expired_ticket_atoms(int)','EXECUTE'),
  'A40: the expiry sweep EXEC service_role — the FIFTEENTH DEF-closure name (S-22; 141 F3 re-scoped)');
SELECT ok(has_function_privilege('service_role','kernel.deletion_blockers_custody(uuid)','EXECUTE')
       AND NOT has_function_privilege('authenticated','kernel.deletion_blockers_custody(uuid)','EXECUTE'),
  'A41: the BP-1 hook keeps 077''s ACL through CREATE OR REPLACE (service_role, never a client)');

-- SEAM-2 discipline
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'kernel' AND p.proname = 'deletion_blockers_custody'), 1,
  'A42: SEAM-2a — exactly ONE overload of deletion_blockers_custody');
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='deletion_blockers_custody')) LIKE '%kernel.tickets%',
  'A43: the stub body is NO LONGER LIVE — the real BP-1 body reads kernel.tickets (§0.4b assertion)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='kernel'
             AND p.proname in ('deletion_blockers_orders','deletion_blockers_wallet',
                               'deletion_blockers_money','deletion_blockers_market')
             AND btrim(p.prosrc) = 'select null::text'), 2,
  'A44: two LATER blocker stubs remain byte-neutral (082 filled orders, 083 filled wallet; money/market pending)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='kernel'
             AND p.proname in ('on_identity_erased_door',
                               'on_identity_erased_market','on_identity_erased_promoter',
                               'on_deletion_q5_release')
             AND btrim(p.prosrc) = 'select'), 4,
  -- 2026-08-31 (package 080): on_identity_erased_staff carries its REAL body
  -- now (the 080-owned OR-17 slot; 144 A27-A30 own it). FOUR remain neutral.
  'A45: the four LATER erased/release hooks remain byte-neutral');
SELECT ok(btrim((SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='kernel' AND p.proname='has_outstanding_obligations')) = 'select false',
  'A46: has_outstanding_obligations remains the 077 neutral stub (085''s slot)');

-- the MB-4 trigger, structurally (T-SCHEMA-CUSTODY-05: a dropped trigger and a
-- trigger that never fires are indistinguishable to every value-based test)
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'tickets' AND t.tgname = 'tg_custody_head_is_ledger_tail'
             AND t.tgdeferrable AND t.tginitdeferred), 1,
  'A47: T-SCHEMA-CUSTODY-05 — the verify trigger exists on kernel.tickets, tgdeferrable AND tginitdeferred both true');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'ticket_ownership_log' AND t.tgname = 'tg_ownership_log_append_only'), 1,
  'A48: the AO guard sits on the ledger');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'door_freeze_override' AND t.tgname = 'tg_door_freeze_override_forward_only'), 1,
  'A49: the forward-only guard sits on the override table');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relname = 'tickets' AND t.tgname = 'tg_tickets_set_updated_at'), 1,
  'A50: set_updated_at maintains kernel.tickets (R-35)');

-- the two structural prosrc pins
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='mark_ticket_scanned'))
          NOT LIKE '%is_transfer_frozen%',
  'A51: T-RPC-DOOR-01 — mark_ticket_scanned references is_transfer_frozen NOWHERE (the nobody-gets-in defect, pinned structurally)');
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='lock_ticket')) LIKE '%is_transfer_frozen%',
  'A52: lock_ticket DOES recheck the freeze — a §12.4c enforcement point');

-- HARDENING-1 regression: 079 replaced a deletion-plane function; the sweep
-- body must still carry the 078 isolation guard (the full battery is 142 §L).
SELECT ok(pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='sweep_deletion_pending'))
          LIKE '%transaction_isolation%',
  'A53: HARDENING-1 survives 079 — the isolation guard is still in the sweep body');

-- cron register row 079
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname = 'sweep-expired-ticket-atoms'), 1,
  'A54: the per-package cron entry exists (P0-1; register row 079, 2 min)');

-- 085''s subjects are absent (T-SCHEMA-CUSTODY-06 owed there, not silently dropped)
SELECT hasnt_function('kernel'::name, 'void_ticket_atom'::name,
  'A55: void_ticket_atom does not exist yet — T-SCHEMA-CUSTODY-06 is 085''s obligation');
SELECT hasnt_function('kernel'::name, 'transfer_ticket_ownership'::name,
  'A56: the transfer engine does not exist yet (088; FR-3)');
SELECT has_function('kernel'::name, 'issue_ticket_atoms'::name, ARRAY['jsonb','text']::name[],
  'A57: the mint engine EXISTS now — issue_ticket_atoms(jsonb, text) landed in 083 (C114)');
SELECT has_function('kernel'::name, 'has_venue_role'::name, ARRAY['uuid','text[]']::name[],
  'A58: has_venue_role exists from 080 on — the PFA-10 deferred arms are live (suite 144 owns their behaviour)');

-- ============================================================================
-- SECTION B — fixtures + THE C26 PROOF RIG (schema §1.6.1 a/b/c/d)
-- ============================================================================

SELECT tap.login(tap.seller());
SELECT tap._store143('org',
  (kernel.create_organization('Custody Co','Custody Co','ck-org-1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status = 'approved'
 WHERE org_id = tap._fetch143('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store143('venue',
  (catalog.create_venue(tap._fetch143('org')::uuid,'Custody Room','wynwood',NULL,'ck-v-1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch143('venue')::uuid,'approved','miami_gate','ck-a-1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store143('event',
  (catalog.create_event(tap._fetch143('venue')::uuid,'Custody Night',
     jsonb_build_object('starts_at',(now()+interval '30 days')::text,
                        'ends_at',(now()+interval '30 days 6 hours')::text,
                        'doors_at',(now()+interval '29 days 22 hours')::text),
     'ck-e-1') ->> 'event_id'));
SELECT tap.logout();
SELECT tap._store143('session',
  (SELECT session_id::text FROM catalog.event_session
    WHERE event_id = tap._fetch143('event')::uuid));
UPDATE catalog.event SET status = 'announced' WHERE event_id = tap._fetch143('event')::uuid;

-- a second identity for cross-identity assertions
INSERT INTO auth.users (id,email,role,instance_id,aud,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-000000000c01','x1@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-000000000c02','d1@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-000000000c03','d2@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-000000000c04','d3@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now()),
  ('00000000-0000-0000-0000-000000000c05','m1@t.local','authenticated','00000000-0000-0000-0000-000000000000','authenticated',now(),now())
ON CONFLICT DO NOTHING;
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by)
VALUES (tap._fetch143('org')::uuid,'00000000-0000-0000-0000-000000000c05','org_marketing', tap.seller());

-- paired custody facts (atom + its issuance ledger row, same transaction —
-- exactly the shape the deferred verify trigger accepts)
CREATE FUNCTION tap._mint(p_atom uuid, p_session uuid, p_serial int, p_owner uuid, p_ref uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $m$
begin
  insert into kernel.tickets (ticket_atom_id, event_session_id, org_id, ticket_type_id,
                              serial_no, current_owner_id, state, signing_key_id)
  values (p_atom, p_session, (select v from tap.memo_143 where k='org')::uuid,
          '00000000-0000-0000-0000-00000000d0d0'::uuid, p_serial, p_owner, 'active',
          '00000000-0000-0000-0000-00000000c0c0'::uuid);
  insert into kernel.ticket_ownership_log
         (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
          actor_identity, command_idempotency_key, credential_version_after, state_transition)
  values (p_atom, 1, null, p_owner, 'issue', p_ref, p_owner,
          'ck-issue-'||p_serial::text, 0,
          jsonb_build_object('from_state', null, 'to_state', 'active',
                             'from_resale_state', null, 'to_resale_state', 'none'));
end $m$;

SELECT tap._mint('00000000-0000-0000-0000-00000000aa01', tap._fetch143('session')::uuid, 1, tap.buyer(),   '00000000-0000-0000-0000-00000000ee01');
SELECT tap._mint('00000000-0000-0000-0000-00000000aa02', tap._fetch143('session')::uuid, 2, tap.buyer(),   '00000000-0000-0000-0000-00000000ee01');
SELECT tap._mint('00000000-0000-0000-0000-00000000aa03', tap._fetch143('session')::uuid, 3, '00000000-0000-0000-0000-000000000c01', '00000000-0000-0000-0000-00000000ee01');

-- (b) one issuance CAN mint N atoms under one cause_ref — the three issue rows
-- above share cause_ref ee01 and all succeeded (the old broken UNIQUE(cause,
-- cause_ref) would have rejected atoms 2..N).
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log
            WHERE cause='issue' AND cause_ref='00000000-0000-0000-0000-00000000ee01'), 3,
  'B1: C26(b) — N (issue, order, atom_k) rows under ONE cause_ref all succeed');

-- (a) one sale cannot transfer the same atom twice
INSERT INTO kernel.ticket_ownership_log
       (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
        actor_identity, command_idempotency_key, credential_version_after, state_transition)
VALUES ('00000000-0000-0000-0000-00000000aa03', 2, '00000000-0000-0000-0000-000000000c01',
        tap.buyer(), 'market_sale', '00000000-0000-0000-0000-00000000ee02',
        tap.buyer(), 'ck-sale-1', 1,
        '{"from_state":"active","to_state":"active","from_resale_state":"listed","to_resale_state":"none"}');
UPDATE kernel.tickets SET current_owner_id = tap.buyer(), credential_version = 1
 WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03';
SELECT throws_ok($$
  INSERT INTO kernel.ticket_ownership_log
         (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
          actor_identity, command_idempotency_key, credential_version_after, state_transition)
  VALUES ('00000000-0000-0000-0000-00000000aa03', 3, '00000000-0000-0000-0000-000000000c01',
          tap.buyer(), 'market_sale', '00000000-0000-0000-0000-00000000ee02',
          tap.buyer(), 'ck-sale-1-retry', 2, '{}'::jsonb)
  $$, '23505', NULL,
  'B2: C26(a) — a second (market_sale, sale, atom) triple is rejected 23505: double-transfer within one sale is physically impossible');

-- (c) one refund CAN void N atoms under one refund_id
INSERT INTO kernel.ticket_ownership_log
       (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
        actor_identity, command_idempotency_key, credential_version_after, state_transition)
VALUES ('00000000-0000-0000-0000-00000000aa01', 2, tap.buyer(),
        '00000000-0000-0000-0000-0000000000f0', 'refund_void', '00000000-0000-0000-0000-00000000ee03',
        tap.admin_user(), 'ck-rv-1', 1,
        '{"from_state":"active","to_state":"voided","from_resale_state":"none","to_resale_state":"none"}'),
       ('00000000-0000-0000-0000-00000000aa02', 2, tap.buyer(),
        '00000000-0000-0000-0000-0000000000f0', 'refund_void', '00000000-0000-0000-0000-00000000ee03',
        tap.admin_user(), 'ck-rv-2', 1,
        '{"from_state":"active","to_state":"voided","from_resale_state":"none","to_resale_state":"none"}');
UPDATE kernel.tickets
   SET current_owner_id = '00000000-0000-0000-0000-0000000000f0', credential_version = 1, state = 'voided'
 WHERE ticket_atom_id IN ('00000000-0000-0000-0000-00000000aa01','00000000-0000-0000-0000-00000000aa02');
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log
            WHERE cause='refund_void' AND cause_ref='00000000-0000-0000-0000-00000000ee03'), 2,
  'B3: C26(c) — K (refund_void, refund, atom_k) rows under ONE refund all succeed; atoms voided to SN-VOID');

-- (d) a replayed command key is rejected before the cause key is even reached
SELECT throws_ok($$
  INSERT INTO kernel.ticket_ownership_log
         (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
          actor_identity, command_idempotency_key, credential_version_after, state_transition)
  VALUES ('00000000-0000-0000-0000-00000000aa03', 3, tap.buyer(), tap.buyer(),
          'p2p_transfer', '00000000-0000-0000-0000-00000000ee04',
          tap.buyer(), 'ck-sale-1', 2, '{}'::jsonb)
  $$, '23505', NULL,
  'B4: C26(d) — a replayed command_idempotency_key on the same atom is rejected 23505');

-- the D3 closed set and the minted-from-nothing CHECK
SELECT throws_ok($$
  INSERT INTO kernel.ticket_ownership_log
         (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
          actor_identity, command_idempotency_key, credential_version_after, state_transition)
  VALUES ('00000000-0000-0000-0000-00000000aa03', 3, tap.buyer(), tap.buyer(),
          'gifted', '00000000-0000-0000-0000-00000000ee05', tap.buyer(), 'ck-bad-1', 2, '{}'::jsonb)
  $$, '23514', NULL, 'B5: a cause outside the D3 closed set is rejected');
SELECT throws_ok($$
  INSERT INTO kernel.ticket_ownership_log
         (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
          actor_identity, command_idempotency_key, credential_version_after, state_transition)
  VALUES ('00000000-0000-0000-0000-00000000aa03', 3, NULL, tap.buyer(),
          'p2p_transfer', '00000000-0000-0000-0000-00000000ee06', tap.buyer(), 'ck-bad-2', 2, '{}'::jsonb)
  $$, '23514', NULL,
  'B6: from_identity NULL is legal ONLY at (issue, sequence 1) — minted from nothing, exactly once');

-- ============================================================================
-- SECTION C — T-SCHEMA-CUSTODY-01..-04 (the MB-4 verify trigger, behaviourally)
-- ============================================================================
SET CONSTRAINTS ALL IMMEDIATE;

SELECT throws_ok($$
  UPDATE kernel.tickets SET current_owner_id = '00000000-0000-0000-0000-000000000c01'
   WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03'
  $$, NULL, NULL,
  'C1: T-SCHEMA-CUSTODY-01 — a head write with NO matching log append RAISES (as postgres: no privilege level bypasses it)');

CREATE FUNCTION tap._naked_head_write() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ UPDATE kernel.tickets SET current_owner_id = '00000000-0000-0000-0000-000000000c01'
     WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03' $m$;
SELECT throws_ok('SELECT tap._naked_head_write()', NULL, NULL,
  'C2: T-SCHEMA-CUSTODY-01 — the same naked write from inside a SECURITY DEFINER function also raises');

-- correct transfer commits (log append, then head write)
INSERT INTO kernel.ticket_ownership_log
       (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
        actor_identity, command_idempotency_key, credential_version_after, state_transition)
VALUES ('00000000-0000-0000-0000-00000000aa03', 3, tap.buyer(),
        '00000000-0000-0000-0000-000000000c01', 'p2p_transfer', '00000000-0000-0000-0000-00000000ee07',
        tap.buyer(), 'ck-p2p-1', 2,
        '{"from_state":"active","to_state":"active","from_resale_state":"locked","to_resale_state":"none"}');
SELECT lives_ok($$
  UPDATE kernel.tickets SET current_owner_id = '00000000-0000-0000-0000-000000000c01', credential_version = 2
   WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03'
  $$,
  'C3: T-SCHEMA-CUSTODY-02 — the same head write INSIDE a correct transfer (log appended) commits');

SELECT throws_ok($$
  UPDATE kernel.tickets SET credential_version = 9
   WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03'
  $$, NULL, NULL,
  'C4: T-SCHEMA-CUSTODY-03 — a credential_version advance with no log append raises');
SELECT throws_ok($$
  WITH ins AS (
    INSERT INTO kernel.ticket_ownership_log
           (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
            actor_identity, command_idempotency_key, credential_version_after, state_transition)
    VALUES ('00000000-0000-0000-0000-00000000aa03', 4, '00000000-0000-0000-0000-000000000c01',
            tap.buyer(), 'admin_action', '00000000-0000-0000-0000-00000000ee08',
            tap.admin_user(), 'ck-adm-1', 7, '{}'::jsonb))
  UPDATE kernel.tickets SET current_owner_id = tap.buyer(), credential_version = 3
   WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03'
  $$, NULL, NULL,
  'C5: T-SCHEMA-CUSTODY-03 — a log append whose credential_version_after disagrees with the head raises');

SELECT lives_ok($$
  UPDATE kernel.tickets SET resale_state = 'listed'
   WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03'
  $$, 'C6: T-SCHEMA-CUSTODY-04 — a resale_state-only write commits with NO log row (non-vacuity)');
SELECT lives_ok($$
  UPDATE kernel.tickets SET resale_state = 'none'
   WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03'
  $$, 'C7: … and back');
SELECT lives_ok($$
  UPDATE kernel.tickets SET signing_key_id = '00000000-0000-0000-0000-00000000c0c1'
   WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03'
  $$, 'C8: T-SCHEMA-CUSTODY-04 — a signing_key_id-only write commits with no log row');

-- hand the atom back to its fan through a CORRECT paired transfer, so the
-- later sections exercise the owner path against tap.buyer()
INSERT INTO kernel.ticket_ownership_log
       (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
        actor_identity, command_idempotency_key, credential_version_after, state_transition)
VALUES ('00000000-0000-0000-0000-00000000aa03', 4, '00000000-0000-0000-0000-000000000c01',
        tap.buyer(), 'p2p_transfer', '00000000-0000-0000-0000-00000000ee14',
        tap.buyer(), 'ck-p2p-back', 3,
        '{"from_state":"active","to_state":"active","from_resale_state":"locked","to_resale_state":"none"}');
UPDATE kernel.tickets SET current_owner_id = tap.buyer(), credential_version = 3
 WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03';

SET CONSTRAINTS ALL DEFERRED;

-- ============================================================================
-- SECTION D — T-SCHEMA-EXPIRY-01 (+ the E-18 fail-inert witness)
-- ============================================================================

-- an ended session on the same event, with atoms
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, ends_at, doors_at)
VALUES ('00000000-0000-0000-0000-00000000e5e5', tap._fetch143('event')::uuid, 'ended',
        now() - interval '1 day', now() - interval '18 hours', now() - interval '26 hours');
SELECT tap._mint('00000000-0000-0000-0000-00000000aa04', '00000000-0000-0000-0000-00000000e5e5', 1, tap.buyer(), '00000000-0000-0000-0000-00000000ee09');
SELECT tap._mint('00000000-0000-0000-0000-00000000aa05', '00000000-0000-0000-0000-00000000e5e5', 2, tap.buyer(), '00000000-0000-0000-0000-00000000ee09');
UPDATE kernel.tickets SET state = 'scanned' WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa05';

-- E-18: ticket.expiry_grace is a PFA-9 CLASS A key — NOT seeded; the sweep is
-- fail-INERT against the absent value (expiry is a terminal label; stamping it
-- without an owner-ruled grace is the harmful direction).
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key = 'ticket.expiry_grace'), 0,
  'D1: E-18 — ticket.expiry_grace is NOT seeded (PFA-9 CLASS A discipline)');
SELECT is((kernel.sweep_expired_ticket_atoms() ->> 'swept_count')::int, 0,
  'D2: E-18 — with the key absent the sweep is INERT (no atom is terminal-ized on a guessed grace)');
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa04'),
  'active', 'D3: … and the ended-session atom is still active');

INSERT INTO catalog.platform_config (key, version, value, visibility)
VALUES ('ticket.expiry_grace', 1, '"1 hour"'::jsonb, 'restricted');
SELECT is((kernel.sweep_expired_ticket_atoms() ->> 'swept_count')::int, 1,
  'D4: T-SCHEMA-EXPIRY-01 — with a grace value, the active atom of the ended session expires');
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa04'),
  'expired', 'D5: active -> expired');
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log
            WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa04'), 1,
  'D6: T-SCHEMA-EXPIRY-01 — NO ownership-log row was appended (expiry is a lifecycle fact, not a custody move)');
SELECT is((SELECT credential_version FROM kernel.tickets
            WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa04'), 0,
  'D7: … and credential_version is unchanged (both halves, because half passes even via the wrong construction)');
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa05'),
  'scanned', 'D8: a scanned atom of the same ended session is LEFT ALONE (terminal, §7.6)');
SELECT is((kernel.sweep_expired_ticket_atoms() ->> 'swept_count')::int, 0,
  'D9: re-entrant — a second run in the same window is a no-op and does not raise on an empty batch');
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa01'),
  'voided', 'D10: a voided atom is never re-labeled by the sweep');

-- a session with NULL ends_at has not verifiably ended: fail-inert
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, ends_at)
VALUES ('00000000-0000-0000-0000-00000000e6e6', tap._fetch143('event')::uuid, 'open-ended',
        now() - interval '2 days', NULL);
SELECT tap._mint('00000000-0000-0000-0000-00000000aa06', '00000000-0000-0000-0000-00000000e6e6', 1, tap.buyer(), '00000000-0000-0000-0000-00000000ee10');
SELECT is((kernel.sweep_expired_ticket_atoms() ->> 'swept_count')::int, 0,
  'D11: a NULL-ends_at session expires nothing — the sweep never guesses an end');

-- ============================================================================
-- SECTION E — kernel.is_transfer_frozen (§12.4a/b: total, fail-closed,
-- session-wide; the override is the only subtraction)
-- ============================================================================

SELECT ok(kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000dead'),
  'E1: an UNKNOWN atom id is TRUE — the fail-open escape hatch is asserted absent (FR-7)');
SELECT ok(NOT kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa03'),
  'E2: a future-session atom is not frozen');
SELECT ok(kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa06'),
  'E3: the implicit backstop — a past COALESCE(doors_at, starts_at) + offset freezes with door_open_at NULL (total: no input produces "never frozen")');

UPDATE catalog.event_session SET door_open_at = now() - interval '1 hour'
 WHERE session_id = tap._fetch143('session')::uuid;
SELECT ok(kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa03'),
  'E4: once the boundary engages, the atom is frozen');
SELECT tap._mint('00000000-0000-0000-0000-00000000aa07', tap._fetch143('session')::uuid, 7, tap.buyer(), '00000000-0000-0000-0000-00000000ee11');
SELECT ok(kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa07'),
  'E5: SESSION-WIDE — a second atom of the same session is frozen too, manifest membership irrelevant (§12.4b)');

INSERT INTO kernel.door_freeze_override
       (override_id, session_id, granted_by, reason_code, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-00000000cc01', tap._fetch143('session')::uuid,
        tap.admin_user(), 'ticket_stranded_at_door', now() + interval '1 hour', 'ck-ovr-1');
SELECT ok(NOT kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa03')
       AND NOT kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa07'),
  'E6: an active session-wide override unfreezes every atom of the session');
UPDATE kernel.door_freeze_override
   SET revoked_at = now(), revoked_by = tap.admin_user()
 WHERE override_id = '00000000-0000-0000-0000-00000000cc01';
SELECT ok(kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa03'),
  'E7: a REVOKED override subtracts nothing');
INSERT INTO kernel.door_freeze_override
       (override_id, session_id, granted_by, reason_code, granted_at, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-00000000cc02', tap._fetch143('session')::uuid,
        tap.admin_user(), 'operator_error_reopen', now() - interval '2 hours',
        now() - interval '1 hour', 'ck-ovr-2');
SELECT ok(kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa03'),
  'E8: an EXPIRED override subtracts nothing (TTL-bounded, never unbounded)');
INSERT INTO kernel.door_freeze_override
       (override_id, session_id, ticket_atom_id, granted_by, reason_code, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-00000000cc03', tap._fetch143('session')::uuid,
        '00000000-0000-0000-0000-00000000aa03',
        tap.admin_user(), 'ticket_stranded_at_door', now() + interval '1 hour', 'ck-ovr-3');
SELECT ok(NOT kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa03'),
  'E9: an ATOM-SCOPED override unfreezes exactly that atom (the narrower grant, preferred)');
SELECT ok(kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa07'),
  'E10: … and no other atom of the session');
UPDATE kernel.door_freeze_override
   SET revoked_at = now(), revoked_by = tap.admin_user()
 WHERE override_id = '00000000-0000-0000-0000-00000000cc03';

-- the boundary comes back off for section F
UPDATE catalog.event_session SET door_open_at = NULL
 WHERE session_id = tap._fetch143('session')::uuid;

SELECT tap.login(tap.buyer());
SELECT ok(NOT kernel.is_transfer_frozen('00000000-0000-0000-0000-00000000aa03'),
  'E11: authenticated CAN read the eligibility boolean (RLS §11.4; the RN Transfer/Sell gate)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok('SELECT kernel.is_transfer_frozen(''00000000-0000-0000-0000-00000000aa03'')',
  '42501', NULL, 'E12: anon cannot');
SELECT tap.logout();

-- ============================================================================
-- SECTION F — lock_ticket / unlock_ticket / mark_ticket_scanned (§7.4/§7.5)
-- ============================================================================

-- atom aa03 is owned by buyer (post C-section custody facts); session is free.
SELECT tap.login(tap.buyer());
SELECT is((tap._lock('00000000-0000-0000-0000-00000000aa03','listed','ck-l-1') ->> 'resale_state'),
  'listed', 'F1: the owner lists — none -> listed');
SELECT is((tap._lock('00000000-0000-0000-0000-00000000aa03','listed','ck-l-2') ->> 'status'),
  'noop_replay', 'F2: re-set of the SAME overlay is a state-guarded no-op');
SELECT throws_ok($$SELECT tap._lock('00000000-0000-0000-0000-00000000aa03','locked','ck-l-3')$$,
  NULL, NULL, 'F3: a DIFFERENT overlay over listed is conflict_locked — the double-sell guard');
SELECT is((tap._unlock('00000000-0000-0000-0000-00000000aa03','ck-u-1') ->> 'resale_state'),
  'none', 'F4: unlock releases to NONE — the R-40 dispute arm is 088''s body replacement (PFA-13), and no dispute can exist in this world');
SELECT is((tap._unlock('00000000-0000-0000-0000-00000000aa03','ck-u-2') ->> 'status'),
  'noop_replay', 'F5: unlock of an unlocked atom is a no-op');
SELECT is((tap._lock('00000000-0000-0000-0000-00000000aa03','refund_hold','ck-l-4') ->> 'resale_state'),
  'refund_hold', 'F6: the §17.1 parked-refund overlay locks through the same primitive');
SELECT throws_ok($$SELECT tap._lock('00000000-0000-0000-0000-00000000aa03','listed','ck-l-5')$$,
  NULL, NULL, 'F7: a refund_hold atom cannot be listed (MONEY §12 ADDITIVE-2)');
SELECT throws_ok($$SELECT tap._scan('00000000-0000-0000-0000-00000000aa03', tap._fetch143('session')::uuid)$$,
  NULL, NULL, 'F8: a refund_hold atom cannot be scanned out from under the approver');
SELECT is((tap._unlock('00000000-0000-0000-0000-00000000aa03','ck-u-3') ->> 'resale_state'),
  'none', 'F9: the hold releases');
SELECT tap.logout();

SELECT tap.login('00000000-0000-0000-0000-000000000c01');
SELECT throws_ok($$SELECT tap._lock('00000000-0000-0000-0000-00000000aa03','listed','ck-l-6')$$,
  '42501', NULL, 'F10: a NON-OWNER cannot lock — current owner = the acting seller/sender (§7.4)');
SELECT tap.logout();

-- freeze interactions
UPDATE catalog.event_session SET door_open_at = now() - interval '1 hour'
 WHERE session_id = tap._fetch143('session')::uuid;
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT tap._lock('00000000-0000-0000-0000-00000000aa03','listed','ck-l-7')$$,
  NULL, NULL, 'F11: lock rejects FROZEN — the §12.4c enforcement point holds');
SELECT tap.logout();
-- stage a locked atom, then prove the drain direction works while frozen
UPDATE kernel.tickets SET resale_state = 'locked' WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa07';
SELECT is((tap._unlock('00000000-0000-0000-0000-00000000aa07','ck-u-4') ->> 'resale_state'),
  'none', 'F12: unlock WORKS while frozen — the door-open drain releases in-flight overlays (§12.4c)');
SELECT is((tap._scan('00000000-0000-0000-0000-00000000aa07', tap._fetch143('session')::uuid) ->> 'atom_state'),
  'scanned', 'F13: THE CRITICAL PROPERTY — a scan SUCCEEDS while the freeze is engaged (the freeze stops transfers, not admissions)');
SELECT throws_ok($$SELECT tap._scan('00000000-0000-0000-0000-00000000aa07', tap._fetch143('session')::uuid)$$,
  NULL, NULL, 'F14: a second scan is not_active — the atom stays scanned (record_scan maps this to duplicate)');
SELECT throws_ok($$SELECT tap._scan('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-00000000e5e5')$$,
  NULL, NULL, 'F15: wrong_session — the atom does not belong to that session');
UPDATE kernel.tickets SET resale_state = 'listed' WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03';
SELECT throws_ok($$SELECT tap._scan('00000000-0000-0000-0000-00000000aa03', tap._fetch143('session')::uuid)$$,
  NULL, NULL, 'F16: listed_locked — delist first (the rule that already covers what the freeze check was reaching for)');
UPDATE kernel.tickets SET resale_state = 'none' WHERE ticket_atom_id = '00000000-0000-0000-0000-00000000aa03';
UPDATE catalog.event_session SET door_open_at = NULL
 WHERE session_id = tap._fetch143('session')::uuid;

-- ============================================================================
-- SECTION G — catalog.update_event_session (§20.2.4; T-RPC-CAT-02)
-- ============================================================================

-- a fresh, atom-free session
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, ends_at)
VALUES ('00000000-0000-0000-0000-00000000e7e7', tap._fetch143('event')::uuid, 'free',
        now() + interval '40 days', now() + interval '40 days 5 hours');

SELECT tap.login(tap.seller());
SELECT throws_ok($$SELECT catalog.update_event_session('00000000-0000-0000-0000-00000000e7e7',
  '{"door_open_at":"2027-01-01T00:00:00Z"}'::jsonb,'ck-s-1')$$,
  NULL, NULL, 'G1: T-RPC-CAT-02 — a patch naming door_open_at raises invalid_input (sole writer: engage_door_freeze, O-5)');
SELECT throws_ok($$SELECT catalog.update_event_session('00000000-0000-0000-0000-00000000e7e7',
  '{"session_version":9}'::jsonb,'ck-s-2')$$,
  NULL, NULL, 'G2: session_version is never a patch key');
SELECT throws_ok($$SELECT catalog.update_event_session('00000000-0000-0000-0000-00000000e7e7',
  '{"event_id":"00000000-0000-0000-0000-000000000001"}'::jsonb,'ck-s-3')$$,
  NULL, NULL, 'G3: re-parenting a session is unwritable — it would move its atoms'' event scope');

SELECT is((catalog.update_event_session('00000000-0000-0000-0000-00000000e7e7',
  jsonb_build_object('starts_at',(now() + interval '45 days')::text,
                     'ends_at',(now() + interval '45 days 5 hours')::text),'ck-s-4') ->> 'status'),
  'ok', 'G4: with NO atom issued and no boundary, the schedule moves freely — even later');
SELECT is((SELECT session_version FROM catalog.event_session
            WHERE session_id='00000000-0000-0000-0000-00000000e7e7'), 2,
  'G5: Δ-N1 — the time change bumped session_version IN THIS TRANSACTION');
SELECT ok((catalog.update_event_session('00000000-0000-0000-0000-00000000e7e7',
  '{"session_label":"renamed"}'::jsonb,'ck-s-5') ->> 'effective_freeze_at') IS NOT NULL,
  'G6: the recomputed boundary is returned in the same round trip');
SELECT is((SELECT session_version FROM catalog.event_session
            WHERE session_id='00000000-0000-0000-0000-00000000e7e7'), 2,
  'G7: a label-only change bumps NOTHING — session_version moves only on starts/doors/ends');

-- the atom-bearing session: the time guard becomes a custody property
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,
  jsonb_build_object('starts_at',(now() + interval '31 days')::text, 'reason_code','venue_request'),'ck-s-6')$$,
  tap._fetch143('session')),
  NULL, NULL,
  'G8: T-RPC-CAT-02 — once ANY atom exists, a LATER starts_at is move_exceeds_grace (grace key absent => NO later move, PFA-9 fail-to-safe)');
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,
  jsonb_build_object('starts_at',(now() + interval '29 days')::text),'ck-s-7')$$,
  tap._fetch143('session')),
  NULL, NULL, 'G9: an earlier move with atoms but NO reason code is reason_required (audited moves only)');
SELECT is((catalog.update_event_session(tap._fetch143('session')::uuid,
  jsonb_build_object('starts_at',(now() + interval '29 days')::text, 'reason_code','venue_request'),'ck-s-8') ->> 'status'),
  'ok', 'G10: an earlier, reason-coded move is permitted — earlier only tightens the freeze');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.admin_audit
            WHERE action='session.update' AND subject_id = tap._fetch143('session')::uuid
              AND reason_code='venue_request'), 1,
  'G11: … and audited with the mandatory reason');

UPDATE catalog.event_session SET door_open_at = now() - interval '1 minute'
 WHERE session_id = tap._fetch143('session')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,
  jsonb_build_object('starts_at',(now() + interval '28 days')::text, 'reason_code','x'),'ck-s-9')$$,
  tap._fetch143('session')),
  NULL, NULL, 'G12: T-RPC-CAT-02 — ANY starts/doors move after door_open_at is boundary_engaged (the boundary is evidence)');
SELECT is((catalog.update_event_session(tap._fetch143('session')::uuid,
  '{"session_label":"night one"}'::jsonb,'ck-s-10') ->> 'status'),
  'ok', 'G13: the label is not the boundary — it still edits');
SELECT tap.logout();
UPDATE catalog.event_session SET door_open_at = NULL
 WHERE session_id = tap._fetch143('session')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT catalog.update_event_session(%L,
  jsonb_build_object('ends_at',(now() - interval '50 days')::text),'ck-s-11')$$,
  '00000000-0000-0000-0000-00000000e7e7'),
  NULL, NULL, 'G14: ends_at must stay after starts_at');
SELECT tap.logout();

-- authority arms
SELECT tap.login('00000000-0000-0000-0000-000000000c05');   -- org_marketing
SELECT is((catalog.update_event_session('00000000-0000-0000-0000-00000000e7e7',
  '{"session_label":"marketing label"}'::jsonb,'ck-s-12') ->> 'status'),
  'ok', 'G15: org_marketing may edit the MARKETING-ONLY column (D3 extension, RLS §11.1)');
SELECT throws_ok($$SELECT catalog.update_event_session('00000000-0000-0000-0000-00000000e7e7',
  jsonb_build_object('starts_at',(now() + interval '46 days')::text),'ck-s-13')$$,
  NULL, NULL, 'G16: org_marketing may NOT touch a time column — freeze inputs are never marketing');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT catalog.update_event_session('00000000-0000-0000-0000-00000000e7e7',
  '{"session_label":"fan"}'::jsonb,'ck-s-14')$$,
  NULL, NULL, 'G17: a plain fan is refused (org arm false; the venue arm is the PFA-10 deferred name and fails CLOSED)');
SELECT tap.logout();

-- ============================================================================
-- SECTION H — BP-1 through the REAL routing (dsm §2; the sweep consumes the
-- hook, the hook supplies the operand — no duplicated logic)
-- ============================================================================

SELECT is(kernel.deletion_blockers_custody(tap.buyer()),
  'BP-1: live custody — issued/active atom(s) held; clears via scan, void, expiry or transfer-out',
  'H1: the hook returns the BP-1 reason for an identity with issued/active atoms');
SELECT is(kernel.deletion_blockers_custody('00000000-0000-0000-0000-000000000c02'), NULL,
  'H2: … and NULL for an identity with none — FALSE means this predicate alone does not block');

-- d1: pending with live custody -> blocked with the reason RECORDED; then drained -> tombstoned
SELECT tap._mint('00000000-0000-0000-0000-00000000aa08', tap._fetch143('session')::uuid, 8,
                 '00000000-0000-0000-0000-000000000c02', '00000000-0000-0000-0000-00000000ee12');
SELECT tap.login('00000000-0000-0000-0000-000000000c02');
SELECT kernel.request_account_deletion('ck-del-1');
SELECT tap.logout();
SELECT kernel.sweep_deletion_pending();
SELECT is((SELECT deletion_state FROM kernel.identity_ext
            WHERE identity_id='00000000-0000-0000-0000-000000000c02'), 'DELETION_PENDING',
  'H3: TRUE means deletion completion stays blocked — the sweep did not tombstone');
SELECT ok((SELECT deletion_block_reason FROM kernel.identity_ext
            WHERE identity_id='00000000-0000-0000-0000-000000000c02') LIKE 'BP-1%',
  'H4: … and the FIRST failing predicate is recorded as BP-1 (closed-world routing through the hook)');
UPDATE kernel.tickets SET state='scanned'
 WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa08';
SELECT kernel.sweep_deletion_pending();
SELECT is((SELECT deletion_state FROM kernel.identity_ext
            WHERE identity_id='00000000-0000-0000-0000-000000000c02'), 'ERASED',
  'H5: the atom scanned out — BP-1 drained, the next pass tombstones (half-completion re-detection)');

-- d2: a LISTED atom still blocks (the overlay keeps state=active)
SELECT tap._mint('00000000-0000-0000-0000-00000000aa09', tap._fetch143('session')::uuid, 9,
                 '00000000-0000-0000-0000-000000000c03', '00000000-0000-0000-0000-00000000ee13');
UPDATE kernel.tickets SET resale_state='listed'
 WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa09';
SELECT tap.login('00000000-0000-0000-0000-000000000c03');
SELECT kernel.request_account_deletion('ck-del-2');
SELECT tap.logout();
SELECT kernel.sweep_deletion_pending();
SELECT ok((SELECT deletion_block_reason FROM kernel.identity_ext
            WHERE identity_id='00000000-0000-0000-0000-000000000c03') LIKE 'BP-1%',
  'H6: a LISTED atom still blocks — resale_state=''listed'' keeps the atom live (dsm :346)');

-- d3: no custody at all -> the predicate does not block, cross-identity rows do not poison
SELECT tap.login('00000000-0000-0000-0000-000000000c04');
SELECT kernel.request_account_deletion('ck-del-3');
SELECT tap.logout();
SELECT kernel.sweep_deletion_pending();
SELECT is((SELECT deletion_state FROM kernel.identity_ext
            WHERE identity_id='00000000-0000-0000-0000-000000000c04'), 'ERASED',
  'H7: an identity with ZERO custody tombstones while OTHER identities'' live atoms exist — cross-identity rows cannot poison an unrelated deletion');
SELECT is((SELECT count(*)::int FROM kernel.tickets
            WHERE current_owner_id = tap.buyer()
              AND state IN ('issued','active')), 2,
  'H8: … and the unrelated fan''s live custody (aa03, aa06) is untouched by that tombstone');

-- ============================================================================
-- SECTION I — the REAL T-SCHEMA-SENTINEL-05 (E-15 discharge) + AO guards + RLS
-- ============================================================================

SELECT is((SELECT count(*)::int FROM kernel.tickets
            WHERE current_owner_id = '00000000-0000-0000-0000-000000000000'), 0,
  'I1: T-SCHEMA-SENTINEL-05 — the 019 anonymization sentinel appears in ZERO rows of kernel.tickets.current_owner_id');
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log
            WHERE from_identity  = '00000000-0000-0000-0000-000000000000'
               OR to_identity    = '00000000-0000-0000-0000-000000000000'
               OR actor_identity = '00000000-0000-0000-0000-000000000000'), 0,
  'I2: … and in ZERO rows of EVERY ticket_ownership_log identity column (the anti-shortcut assertion, at last assertable)');

SELECT throws_ok($$UPDATE kernel.ticket_ownership_log SET cause_ref = gen_random_uuid()
  WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa03' AND sequence=1$$,
  NULL, NULL, 'I3: AO — the ledger rejects UPDATE');
SELECT throws_ok($$DELETE FROM kernel.ticket_ownership_log
  WHERE ticket_atom_id='00000000-0000-0000-0000-00000000aa03'$$,
  NULL, NULL, 'I4: AO — the ledger rejects DELETE (corrections are compensating entries, never edits)');
SELECT throws_ok($$UPDATE kernel.door_freeze_override SET reason_code='fraud_investigation'
  WHERE override_id='00000000-0000-0000-0000-00000000cc02'$$,
  NULL, NULL, 'I5: the override''s grant columns are immutable');
SELECT lives_ok($$UPDATE kernel.door_freeze_override
  SET revoked_at=now(), revoked_by=tap.admin_user()
  WHERE override_id='00000000-0000-0000-0000-00000000cc02'$$,
  'I6-pre: (stage) the forward transition itself is exercised below');
SELECT throws_ok($$UPDATE kernel.door_freeze_override SET revoked_at=now()
  WHERE override_id='00000000-0000-0000-0000-00000000cc01'$$,
  NULL, NULL, 'I6: an already-revoked override admits NO further transition');
SELECT throws_ok($$DELETE FROM kernel.door_freeze_override
  WHERE override_id='00000000-0000-0000-0000-00000000cc02'$$,
  NULL, NULL, 'I7: the override table rejects DELETE — revocation is forward, never removal');
SELECT throws_ok($$
  INSERT INTO kernel.door_freeze_override
         (session_id, granted_by, reason_code, expires_at, command_idempotency_key)
  VALUES ((SELECT v FROM tap.memo_143 WHERE k='session')::uuid,
          '00000000-0000-0000-0000-000000000c01', 'because', now()+interval '1 hour', 'ck-ovr-9')
  $$, '23514', NULL, 'I8: reason_code outside the DOOR §8.1 closed set is rejected');

-- adversarial RLS, live personas
SELECT tap.login('00000000-0000-0000-0000-000000000c01');
SELECT is((SELECT count(*)::int FROM kernel.tickets), 0,
  'I9: a NON-OWNER reads ZERO atoms — not the buyer''s, not anyone''s (x1 owns none live: aa03 moved back to buyer in C)');
SELECT throws_ok('SELECT count(*) FROM kernel.ticket_ownership_log', '42501', NULL,
  'I10: no client reads the raw custody chain (redacted RPC arrives in 088)');
SELECT throws_ok('SELECT count(*) FROM kernel.door_freeze_override', '42501', NULL,
  'I11: no client reads the override audit surface');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT ok((SELECT count(*) FROM kernel.tickets) >= 5,
  'I12: the owner reads their own atoms (all sixteen granted columns; current_owner_id is E-24-excluded from the grant since 080)');
-- E-24 (080): a client cannot reference current_owner_id, so foreign-row
-- absence is asserted against KNOWN foreign atom ids instead of the column.
SELECT ok(NOT EXISTS (SELECT 1 FROM kernel.tickets
            WHERE ticket_atom_id IN ('00000000-0000-0000-0000-00000000aa08',
                                     '00000000-0000-0000-0000-00000000aa09')),
  'I13: … and NO row of another owner is visible through the owner policy');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT ok((SELECT count(*) FROM kernel.tickets) >= 8,
  'I14: platform reads the full surface (audit; kernel_tickets_sel_platform)');
SELECT tap.logout();

-- ============================================================================
-- SECTION J — regression anchors (the production-OFF world is unmoved)
-- ============================================================================

SELECT is((SELECT value::text FROM catalog.platform_config
            WHERE key='feature.native_issuance_enabled' ORDER BY version DESC LIMIT 1),
  'false', 'J1: the issuance rail is DARK — 079 built the substrate, not the switch');
SELECT is((SELECT value::text FROM catalog.platform_config
            WHERE key='wallet.apple.enabled' ORDER BY version DESC LIMIT 1),
  'false', 'J2: Wallet stays dark');
SELECT is((SELECT jsonb_typeof(value) FROM catalog.platform_config
            WHERE key='retention.backup_window_days'), 'null',
  'J3: the retention failsafe is untouched');

SELECT * FROM finish();
ROLLBACK;
