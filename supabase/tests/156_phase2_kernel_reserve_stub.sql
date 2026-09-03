-- ============================================================================
-- 156_phase2_kernel_reserve_stub.sql — Phase-2 package 091 suite.
-- Frozen sources: plan §8/091 (Tables/Functions/RLS/Triggers/Grants/Rollback/
-- Tests rows) · schema §1.11 (EXT — Gate-M stub only) · RLS §7.11 (money-custody-
-- RPC-only, DENY-ALL) · writer registry kernel.reserve = NONE-wired-in-MVP ·
-- parity 091|kernel.reserve|table · E-149/E-150. "Stub" is asserted as a CHECKED
-- property: empty, deny-all, no writer, no routine references it, nothing else
-- created. BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(39);

SELECT tap.seed_core();

-- ============================================================================
-- SECTION A — THE 091 CLOSED WORLD (one table; nothing else)
-- ============================================================================
SELECT has_table('kernel'::name,'reserve'::name, 'A1: kernel.reserve exists (the Gate-M extension point)');
SELECT has_column('kernel'::name,'reserve'::name,'reserve_id'::name, 'A2: reserve_id');
SELECT col_is_pk('kernel'::name,'reserve'::name,'reserve_id'::name, 'A3: reserve_id is the PK');
SELECT col_type_is('kernel'::name,'reserve'::name,'reserve_id'::name,'uuid', 'A4: reserve_id uuid');
SELECT col_type_is('kernel'::name,'reserve'::name,'org_id'::name,'uuid', 'A5: org_id uuid');
SELECT col_not_null('kernel'::name,'reserve'::name,'org_id'::name, 'A6: org_id NOT NULL (E-149 — an ownerless reserve row has no meaning)');
SELECT ok((SELECT c.confrelid = 'kernel.organization'::regclass AND c.confdeltype = 'r' FROM pg_constraint c
            WHERE c.conrelid = 'kernel.reserve'::regclass AND c.contype = 'f'), 'A7: org_id → kernel.organization ON DELETE RESTRICT');
SELECT col_type_is('kernel'::name,'reserve'::name,'balance_minor'::name,'integer', 'A8: balance_minor integer (minor units)');
SELECT col_default_is('kernel'::name,'reserve'::name,'balance_minor'::name, 0, 'A9: balance_minor default 0');
SELECT col_type_is('kernel'::name,'reserve'::name,'currency'::name,'text', 'A10: currency text');
SELECT col_default_is('kernel'::name,'reserve'::name,'currency'::name, 'USD', 'A11: currency default ''USD''');
SELECT col_has_default('kernel'::name,'reserve'::name,'created_at'::name, 'A12: created_at defaulted');
SELECT col_has_default('kernel'::name,'reserve'::name,'updated_at'::name, 'A13: updated_at defaulted');
SELECT is((SELECT count(*)::int FROM pg_attribute a WHERE a.attrelid = 'kernel.reserve'::regclass AND a.attnum > 0 AND NOT a.attisdropped), 6,
  'A14: EXACTLY six columns (reserve_id, org_id, balance_minor, currency, created_at, updated_at) — the minimal shape, nothing added');
SELECT is((SELECT count(*)::int FROM pg_constraint c WHERE c.conrelid = 'kernel.reserve'::regclass AND c.contype = 'c'), 0,
  'A15: NO CHECK constraint (none is stated; a Gate-M receivable posture is not pre-empted — E-149)');
SELECT is((SELECT count(*)::int FROM pg_indexes WHERE schemaname = 'kernel' AND tablename = 'reserve'), 1, 'A16: PK only — one index');
SELECT is((SELECT count(*)::int FROM pg_trigger t WHERE t.tgrelid = 'kernel.reserve'::regclass AND NOT t.tgisinternal), 1, 'A17: exactly one trigger…');
SELECT ok((SELECT p.proname = 'set_updated_at' AND n.nspname = 'kernel' FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE t.tgrelid = 'kernel.reserve'::regclass AND NOT t.tgisinternal), 'A18: …the 076 kernel.set_updated_at (plan Triggers row)');
-- nothing else was created
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'kernel' AND c.relkind = 'r'), 28,
  'A19: kernel holds 28 tables — 27 post-090 + the reserve stub');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 259,
  -- 2026-09-02 (package 092): 228 -> 243 (+15 notify routines).
  -- 2026-09-02 (package 093): 243 -> 246. RATIFIED CONTRACT CHANGE —
  -- PRIMARY_TICKETING_OWNER_RATIFICATION.md ruling A6 (kernel.sync_org_connect_state,
  -- kernel.get_org_connect_state) and ruling A3 (kernel.settlement_primary_lines). All three
  -- land in kernel; 091's own schemas are untouched, so the "091 creates NO function" claim
  -- this row exists to defend is unweakened — it is still an absolute five-schema census.
  -- 2026-09-02 (package 093, second money pass): 246 -> 250 (+stage_org_connect_ref,
  -- +get_org_connect_ref, +get_refund_execution_context, +is_order_buyer — all kernel).
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
  'A20: 091 creates NO function (five-schema routines 259 post-093)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 72,
  -- 2026-09-02 (package 092): 67 -> 72 (+5 notify owner policies).
  'A21: 091 creates NO policy (register 72 post-092)');
SELECT is((SELECT count(*)::int FROM cron.job), 19, 'A22 (092: 19 with notify-drain-outbox): 091 schedules NO cron row (18 post-090 — an absolute census, not a name filter)');
-- 2026-09-02 (package 093): 43 -> 47. RATIFIED CONTRACT CHANGE — four keys, each ONE row at
-- version 1 and each seeded OWNER-UNSET (jsonb null, PFA-9 shape), so the census stays absolute:
--   inventory.per_user_active_hold_max, inventory.hold_ttl_interval  (093_FINAL_PROPOSED_SCOPE item 3)
--   ticket.expiry_grace                                             (RATIFICATION ruling D2)
--   fee.buyer_service_bps                                           (RATIFICATION ruling A5 — the value is
--                                                                    OWNER POLICY and is never hardcoded)
--   payout.settlement_maturity_interval                             (093's money passes — the settlement-maturity
--                                                                    gate. UNSET is the SAFE state: every settlement
--                                                                    payout is minted HELD until an owner rules the
--                                                                    window, so SETTING this key is the dangerous
--                                                                    act — and the payout.% prefix puts it under
--                                                                    dual control, 078:1145-1147. Pass 3 RENAMED it
--                                                                    from settlement.refund_window_interval, which
--                                                                    named refund eligibility, a different policy
--                                                                    that already exists under refund.%; the count
--                                                                    is unchanged because nothing was added)
--   deletion.post_event_hold_hours                                  (093 / H2 — BP-12 arm 2's operand, RE-ANCHORED
--                                                                    from venue."order".created_at (the PAYMENT
--                                                                    clock) to max(coalesce(session.ends_at,
--                                                                    session.starts_at)) over the identity's own
--                                                                    candidate orders. This one is an ADDED key, so
--                                                                    the census moves 48 -> 49: unlike G2's rename,
--                                                                    the old row lives in IMMUTABLE 085 and cannot
--                                                                    be withdrawn — it survives as an unread orphan
--                                                                    and the new row is the only one with a reader.
--                                                                    UNSET is the SAFE state (arm 2 blocks whenever
--                                                                    a paid/partially_refunded order exists), so
--                                                                    SETTING it is the dangerous act — and 093 adds
--                                                                    `deletion.%` to the dual-control prefix list,
--                                                                    which G7 P1-4 proved was missing)
-- 091 still fabricates none of them; a seventh row appearing here would still trip this test.
-- 2026-09-02 (093 / H2): 48 -> 49. RATIFIED CONTRACT CHANGE — ONE key, ONE row at version 1,
-- seeded OWNER-UNSET ('null'::jsonb, PFA-9 shape), enumerated from the slice-40 seed block.
-- The census stays ABSOLUTE: nothing here is relaxed to a name filter.
SELECT is((SELECT count(*)::int FROM catalog.platform_config), 49, 'A23 (093: 49 with the six owner-unset primary-ticketing keys): PFA-9 — 091 fabricates NO config key (an absolute census)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname IN ('kernel','venue','catalog','market','notify','public') AND p.prosrc ~ '(kernel|"kernel")\s*\.\s*"?reserve"?\M'), 0,
  'A24: plan §8/091 Tests row — NO routine in the database references kernel.reserve ("stub" is a checked property)');
SELECT is((SELECT count(*)::int FROM pg_depend d WHERE d.refobjid = 'kernel.reserve'::regclass AND d.deptype = 'n' AND d.classid <> 'pg_class'::regclass), 0,
  'A25: nothing outside the table''s own auto/internal objects depends on it — the precondition for "always droppable" (plan Rollback row)');
SELECT is((SELECT count(*)::int FROM pg_constraint c WHERE c.conrelid = 'kernel.reserve'::regclass AND c.contype = 'f' AND c.confrelid = 'auth.users'::regclass), 0,
  'A26: ODR-16 — no identity FK on the stub (nothing for the deletion machine to carry)');

-- ============================================================================
-- SECTION B — DENY-ALL POSTURE (RLS §7.11; plan RLS/Grants rows)
-- ============================================================================
SELECT ok((SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = 'kernel.reserve'::regclass), 'B1: RLS is ENABLED');
SELECT ok((SELECT NOT c.relforcerowsecurity FROM pg_class c WHERE c.oid = 'kernel.reserve'::regclass), 'B2: FORCE not set (INV-NOFORCE corpus posture — every kernel table is force=false; the stub has no definer consumer yet)');
SELECT is((SELECT count(*)::int FROM pg_policy p WHERE p.polrelid = 'kernel.reserve'::regclass), 0, 'B3: ZERO policies, by design');
SELECT ok((SELECT bool_and(NOT has_table_privilege(r, 'kernel.reserve', priv))
             FROM unnest(ARRAY['anon','authenticated','service_role']) r, unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) priv),
  'B4: anon / authenticated / service_role hold NO privilege of any kind (E-150: no dormant machine grant on a money table)');
SELECT is((SELECT relacl::text FROM pg_class WHERE oid = 'kernel.reserve'::regclass), '{postgres=arwdDxtm/postgres}', 'B4a: the ACL is MATERIALIZED and owner-only — the REVOKE ran (a never-revoked table carries a NULL relacl); byte-identical to kernel.payout''s');
SELECT is((SELECT count(*)::int FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
            WHERE c.oid = 'kernel.reserve'::regclass AND (a.grantee = 0 OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role')))), 0,
  'B5: the exploded ACL carries no entry for PUBLIC, anon, authenticated or service_role (catalog form — not a permission-filtered view)');
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT * FROM kernel.reserve$$, '42501', NULL, 'B6: a fan cannot read the stub');
SELECT throws_ok(format($$INSERT INTO kernel.reserve (org_id) VALUES (%L)$$, gen_random_uuid()), '42501', NULL, 'B7: …nor write it');
SELECT tap.logout();
SELECT tap.login_service();
SELECT throws_ok($$SELECT * FROM kernel.reserve$$, '42501', NULL, 'B8: service_role cannot read it either (no writer is wired; Gate-M only)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT * FROM kernel.reserve$$, '42501', NULL, 'B9: anon holds nothing');
SELECT tap.logout();

-- ============================================================================
-- SECTION C — ALWAYS EMPTY; NOTHING ELSE MOVED
-- ============================================================================
SELECT is((SELECT count(*)::int FROM kernel.reserve), 0, 'C1: the stub is EMPTY after a fresh replay (no seed, no writer)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.proname IN ('deletion_blockers_custody','deletion_blockers_orders','deletion_blockers_wallet','deletion_blockers_money',
              'deletion_blockers_market','on_identity_erased_staff','on_identity_erased_door','on_identity_erased_market','on_identity_erased_promoter',
              'has_outstanding_obligations','on_deletion_q5_release','settlement_royalty_lines','settlement_commission_lines'))
          + (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE (n.nspname,p.proname) IN (('venue','resolve_order_attribution'),('venue','on_payout_settled'),('market','on_atom_voided'),
              ('market','on_door_freeze_engaged'),('market','door_freeze_drain_preview'),('venue','append_door_manifest_delta'))), 19,
  'C2: the SEAM register is untouched (19 hooks; 091 adds no seam and replaces no body)');
SELECT ok((SELECT p.prosrc LIKE '%''held'', ''unfunded_settlement''%' FROM pg_proc p WHERE p.oid = 'kernel.pay_promoter_commission(uuid,uuid[],text)'::regprocedure)
       AND (SELECT p.prosrc LIKE '%payout_held%' FROM pg_proc p WHERE p.oid = 'kernel.mark_payout_transfer_state(uuid,text,text,text,text)'::regprocedure),
  'C3: money darkness — 090''s hold mint (unfunded_settlement) and 085''s held-payout refusal are byte-present after 091: no funding leg, no release path was added (155 G12–G12e carries the behavioural proof)');

SELECT * FROM finish();
ROLLBACK;
