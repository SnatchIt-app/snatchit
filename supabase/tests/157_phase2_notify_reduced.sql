-- ============================================================================
-- 157_phase2_notify_reduced.sql — Phase-2 package 092 suite (THE FINAL PACKAGE).
-- Frozen sources: registry §2 row 092 · ODR1_AMENDMENT §6.2 · OR-5 [C] · OR-14
-- (R2) · OR-15/OR-17 (31 IN types) · NOTIF §2–§6/§8/§9 (N-A1…N-A44 minus the
-- H/announcement and N-A12/13 schedule rows, which are OUT) · RPC §17.24/§17.25
-- · RLS §16.9/§11 · DSM §3.1.4/§4.7 · E-152…E-160. Every path runs under
-- ROLLBACK. BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(294);

SELECT tap.seed_core();

CREATE TABLE tap.memo_157 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store157(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_157 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._u157(k text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::uuid FROM tap.memo_157 WHERE k=$1 $m$;
CREATE FUNCTION tap._t157(k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_157 WHERE k=$1 $m$;
CREATE FUNCTION tap._cfg157(p_key text, p_val jsonb, p_vis text DEFAULT 'restricted') RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO catalog.platform_config (key, version, value, visibility)
    SELECT p_key, coalesce(max(version),0)+1, p_val, p_vis FROM catalog.platform_config WHERE key = p_key $m$;
CREATE FUNCTION tap._newpayment157(p_buyer uuid, p_seller uuid, p_total int, p_pi text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
$m$ WITH l AS (INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
                 starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
               VALUES (p_seller, 'Notify Night ' || gen_random_uuid()::text, 'Notify Hall', 'wynwood', (now()+interval '15 days')::date, '20:00', 'GA', 2,
                 'mobile_transfer', 5000, 5000, 24, now()+interval '1 day', 'covers/fixture.jpg') RETURNING id)
    INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, status, mode, stripe_payment_intent_id)
    SELECT id, p_buyer, p_seller, (p_total * 9) / 10, p_total - (p_total * 9) / 10, p_total, 'succeeded', 'buy_now', p_pi FROM l RETURNING id $m$;
CREATE FUNCTION tap._neworder157(p_key text, p_buyer uuid, p_session uuid, p_org uuid, p_tt uuid, p_batch uuid, p_qty int, p_unit int) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $m$
declare v_o uuid;
begin
  insert into venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key)
  values (p_buyer, p_session, p_org, 'pending', 'web', p_qty * p_unit, 'ck92-ord-' || p_key) returning order_id into v_o;
  insert into venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor) values (v_o, p_tt, p_qty, p_unit);
  insert into venue.inventory_hold (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  values (p_batch, p_buyer, p_qty, 'active', now() + interval '1 hour', 'ck92-h-' || p_key);
  update venue.inventory_batch set held = held + p_qty where batch_id = p_batch;
  perform tap._store157(p_key, v_o::text);
  return v_o;
end $m$;
-- definer readers over the deny-all tables (RLS hides them from every client role)
CREATE FUNCTION tap._n157(p_recipient uuid, p_type text) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM notify.notification n WHERE n.recipient_id = p_recipient AND (p_type IS NULL OR n.type_key = p_type) $m$;
CREATE FUNCTION tap._nrow157(p_recipient uuid, p_type text) RETURNS notify.notification LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT n FROM notify.notification n WHERE n.recipient_id = p_recipient AND n.type_key = p_type ORDER BY n.created_at DESC, n.notification_id DESC LIMIT 1 $m$;
CREATE FUNCTION tap._nbykey157(p_key text) RETURNS notify.notification LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT n FROM notify.notification n WHERE n.dedupe_key = p_key $m$;
CREATE FUNCTION tap._d157(p_notification uuid, p_channel text) RETURNS notify.delivery LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT d FROM notify.delivery d WHERE d.notification_id = p_notification AND d.channel = p_channel $m$;
CREATE FUNCTION tap._dcount157(p_notification uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM notify.delivery d WHERE d.notification_id = p_notification $m$;
CREATE FUNCTION tap._ob157(p_type text, p_key text) RETURNS notify.outbox LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT o FROM notify.outbox o WHERE o.event_type = p_type AND (p_key IS NULL OR o.event_key = p_key) ORDER BY o.created_at DESC LIMIT 1 $m$;
CREATE FUNCTION tap._obcount157(p_type text, p_state text) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM notify.outbox o WHERE o.event_type = p_type AND (p_state IS NULL OR o.state = p_state) $m$;
CREATE FUNCTION tap._emit157(p_type text, p_kind text, p_agg uuid, p_key text, p_payload jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT notify.emit_event(p_type, p_kind, p_agg, p_key, p_payload, NULL, NULL) $m$;
CREATE FUNCTION tap._tok157(p_token text) RETURNS public.push_tokens LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT t FROM public.push_tokens t WHERE t.token = p_token $m$;
CREATE FUNCTION tap._ics157(p_identity uuid, p_channel text) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT s.state FROM notify.identity_channel_state s WHERE s.identity_id = p_identity AND s.channel = p_channel $m$;
-- personas: fin157 (org_finance of org1), fan157 (nothing held — the deletion-lifecycle subject)
CREATE FUNCTION tap.fin157() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '77777777-7777-7777-7777-777777777772'::uuid $$;
CREATE FUNCTION tap.fan157() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '77777777-7777-7777-7777-777777777771'::uuid $$;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES (tap.fin157(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin157@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
       (tap.fan157(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan157@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;
UPDATE public.profiles SET display_name = 'Finn Ledger' WHERE id = tap.fin157();

-- ============================================================================
-- FIXTURE — org1 (seller owner; fin157 org_finance) → venue1 → event1/session1
--   (tt1 5000, batch1); order o1 (buyer, qty 3) finalized → three atoms to buyer.
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store157('org1', (kernel.create_organization('Notify Co','Notify Co','ck92-o1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._u157('org1');
SELECT tap.login(tap.seller());
SELECT tap._store157('venue1', (catalog.create_venue(tap._u157('org1'),'Notify Hall','wynwood',NULL,'ck92-v1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._u157('venue1'),'approved','miami_gate','ck92-a1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store157('event1', (catalog.create_event(tap._u157('venue1'),'Notify Night',
  jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 5 hours')::text),'ck92-e1') ->> 'event_id'));
SELECT tap._store157('session1', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._u157('event1')));
SELECT tap._store157('tt1', (venue.create_ticket_type(tap._u157('event1'),'admission','GA',5000,'public','ck92-tt1') ->> 'ticket_type_id'));
SELECT tap._store157('batch1', (venue.create_inventory_batch(tap._u157('tt1'), tap._u157('session1'), 'public_sale', 100, 0, 'ck92-b1') ->> 'batch_id'));
SELECT tap.logout();
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
VALUES (tap._u157('org1'), tap.fin157(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days' WHERE org_id = tap._u157('org1');
SELECT tap._cfg157('authn.money_role_maturity_hours', '24'::jsonb);
SELECT tap._cfg157('feature.native_issuance_enabled', 'true'::jsonb);
INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
VALUES ('per_event', tap._u157('event1'), 'PUBKEY-92-1', 'kms-92-1', 'active', now());
SELECT tap._neworder157('o1', tap.buyer(), tap._u157('session1'), tap._u157('org1'), tap._u157('tt1'), tap._u157('batch1'), 3, 5000);
SELECT tap._store157('pay1', tap._newpayment157(tap.buyer(), tap.seller(), 15000, 'pi_92_1')::text);
SELECT is((venue.finalize_primary_order(tap._u157('o1'), tap._u157('pay1'), 'ck92-f1', NULL) ->> 'status'), 'ok', 'FIX-1: o1 finalized (3 atoms minted to buyer; EXEC DEF — called as the owner, the 153/155 precedent)');
SELECT tap._store157('a1', (SELECT ticket_atom_id::text FROM kernel.tickets WHERE event_session_id = tap._u157('session1') AND current_owner_id = tap.buyer() ORDER BY serial_no LIMIT 1));
SELECT tap._store157('cv1', (SELECT credential_version::text FROM kernel.tickets WHERE ticket_atom_id = tap._u157('a1')));
SELECT is((SELECT count(*)::int FROM kernel.tickets WHERE current_owner_id = tap.buyer() AND event_session_id = tap._u157('session1')), 3, 'FIX-2: buyer holds three atoms');

-- ============================================================================
-- SECTION A — THE CLOSED WORLD (registry row 092; PARITY_SPEC 092 rows)
-- ============================================================================
SELECT has_table('notify','notification_type','A1: notify.notification_type (C18 registry)');
SELECT has_table('notify','notification','A2: notify.notification');
SELECT has_table('notify','delivery','A3: notify.delivery');
SELECT has_table('notify','preference','A4: notify.preference');
SELECT has_table('notify','template','A5: notify.template');
SELECT has_table('notify','identity_channel_state','A6: notify.identity_channel_state');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='notify' AND c.relkind='r'), 7,
  'A7: notify holds exactly 7 tables — 076''s outbox + the six (NO schedule, NO announcement: OR-5 [C])');
SELECT has_column('notify','outbox','expand_cursor','A8: outbox.expand_cursor (RPC §17.24 (i))');
SELECT has_column('notify','outbox','expanded_count','A9: outbox.expanded_count');
SELECT has_column('public','push_tokens','revoked_at','A10: push_tokens.revoked_at (schema §13.4)');
SELECT has_column('public','push_tokens','revoked_reason','A11: push_tokens.revoked_reason');
SELECT has_column('public','push_tokens','provider_receipt_checked_at','A12: push_tokens.provider_receipt_checked_at');
SELECT has_column('public','push_tokens','last_provider_error','A13: push_tokens.last_provider_error');
SELECT is((SELECT count(*)::int FROM pg_proc WHERE pronamespace='notify'::regnamespace), 17,
  'A14: notify holds 17 routines — 076''s emit pair + 092''s fifteen (the reduced 16 minus emit_event; no announcement RPC, no sweep_scheduled)');
SELECT is((SELECT string_agg(p.oid::regprocedure::text, E'\n' ORDER BY p.oid::regprocedure::text COLLATE "C")
             FROM pg_proc p WHERE p.pronamespace='notify'::regnamespace AND p.proname NOT LIKE 'emit_event%'),
  E'notify.channel_enabled(uuid,text,text)\nnotify.claim_deliveries(text,integer)\nnotify.dismiss(uuid[])\nnotify.drain_outbox(integer)\nnotify.enqueue(uuid,text,text,uuid,jsonb,text)\nnotify.get_inbox(timestamp with time zone,integer)\nnotify.get_preference_matrix()\nnotify.get_unread_count()\nnotify.mark_all_read()\nnotify.mark_read(uuid[])\nnotify.record_delivery_result(uuid,text,text,text,text,text,text)\nnotify.register_push_token(text,text,text,text)\nnotify.resolve_web_link(text,uuid)\nnotify.revoke_push_token(text)\nnotify.set_preference(text,text,boolean)',
  'A15: the fifteen 092 routines by exact signature — OBJECTS EXTRA 0, MISSING 0');
SELECT is((SELECT count(*)::int FROM pg_proc p WHERE p.pronamespace='notify'::regnamespace AND p.proname NOT LIKE 'emit_event%'
             AND p.prosecdef AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname='postgres')
             AND 'search_path=""' = ANY(p.proconfig)), 15,
  'A16: all fifteen are SECURITY DEFINER, owned by postgres, search_path = '''' (067 discipline)');
SELECT is((SELECT count(*)::int FROM cron.job), 19, 'A17: cron census 19 — 18 post-091 + notify-drain-outbox (an absolute census)');
SELECT is((SELECT schedule || ' | ' || command FROM cron.job WHERE jobname='notify-drain-outbox'), '*/2 * * * * | select notify.drain_outbox(200);',
  'A18: the drainer tick is the register''s 2-minute row; the two edge ticks are PARKED deploy artifacts (E-158) — not scheduled here');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname IN ('notify-dispatch','notify-receipts') OR command ILIKE '%net.http_post%notify%'), 0,
  'A19: no pg_net edge tick for notify (their header/Vault names are unnamed by any frozen byte — E-158)');
-- 2026-09-02 (package 093): 43 -> 47. RATIFIED CONTRACT CHANGE — inventory.per_user_active_hold_max
-- and inventory.hold_ttl_interval (093_FINAL_PROPOSED_SCOPE item 3), ticket.expiry_grace
-- (RATIFICATION ruling D2), fee.buyer_service_bps (ruling A5) and payout.settlement_maturity_interval
-- (the settlement-maturity gate — UNSET is the safe state: every settlement payout is minted HELD
-- until an owner rules the window; the payout.% prefix is load-bearing, since 078:1145-1147 puts
-- every payout.% key under dual control), each seeded OWNER-UNSET. The key count is unchanged at
-- 48: pass 3 RENAMED this key from settlement.refund_window_interval, it did not add one.
-- 092 still contributes exactly one key; the census stays absolute and distinct-keyed.
-- 2026-09-02 (093 / H2): 48 -> 49. deletion.post_event_hold_hours is BP-12 arm 2's
-- RE-ANCHORED operand (event clock, not payment clock). It is an ADD rather than a
-- rename because its predecessor is seeded by IMMUTABLE 085 and cannot be withdrawn.
-- 092 still contributes exactly one key; the census stays absolute and distinct-keyed.
SELECT is((SELECT count(DISTINCT key)::int FROM catalog.platform_config), 49, 'A20: config census 49 keys — 42 post-091 + notify.delivery_lease_interval + 093''s six (distinct keys: the fixture bumps two versions)');
SELECT is((SELECT c.visibility || ':' || coalesce(c.value #>> '{}', '<null>') FROM catalog.platform_config c WHERE c.key='notify.delivery_lease_interval' ORDER BY c.version DESC LIMIT 1),
  'restricted:<null>', 'A21: the lease key is seeded OWNER-UNSET (PFA-22 shape, E-154) — no value invented');
SELECT is((SELECT count(*)::int FROM notify.notification_type), 31, 'A22: registry seeds exactly the 31 reduced IN types (ODR-3 §1 + OR-15 + OR-17)');
SELECT is((SELECT count(*)::int FROM notify.notification_type WHERE delivery_class='mandatory'), 29, 'A23: 29 MANDATORY (21 ODR-3 + 6 N3 refund/approval + the OR-15 ninth + the OR-17 pair)');
SELECT is((SELECT string_agg(type_key, ',' ORDER BY type_key COLLATE "C") FROM notify.notification_type WHERE delivery_class <> 'mandatory'),
  'promoter_commission_accrued,wallet_pass_available', 'A24: exactly the two ON types; zero default_off');
SELECT is((SELECT count(*)::int FROM notify.notification_type WHERE legacy OR NOT active OR registry_version <> 1), 0, 'A25: no legacy row (ODR-114 silence), all active, registry_version 1');
SELECT is((SELECT string_agg(type_key, ',' ORDER BY type_key COLLATE "C") FROM notify.notification_type),
  'account_deletion_completed,account_deletion_pending,event_cancelled,event_postponed,event_time_changed,event_venue_changed,ownership_changed,payout_failed,payout_on_hold,payout_released,payout_request_pending_approval,promoter_commission_accrued,purchase_confirmed,purchase_failed,refund_completed,refund_failed,refund_request_approved,refund_request_cancelled,refund_request_denied,refund_request_expired,refund_request_parked,refund_requested,refund_submitted,security_org_role_granted,security_org_role_revoked,security_password_changed,security_payout_destination_changed,security_payout_method_added,staff_payout_failed,ticket_ready,wallet_pass_available',
  'A26: the type-key set equals the R2 classification''s 31 IN keys — catalogue/registry parity');
SELECT is((SELECT count(*)::int FROM notify.notification_type WHERE type_key LIKE 'announcement%' OR type_key IN ('transfer_received','transfer_accepted','listing_sold','attribution_recorded')), 0,
  'A27: no OUT type crossed the gate (announcements, resale/transfer rails, attribution_recorded)');
SELECT is((SELECT count(*)::int FROM notify.template), 61, 'A28: 61 template rows — 31 in_app + 30 push (account_deletion_completed is E-only) + ZERO email (N1)');
SELECT is((SELECT count(*)::int FROM notify.template WHERE channel='email'), 0, 'A29: no email template exists — email is owner-gated (N1); nothing is invented');
SELECT is((SELECT count(*)::int FROM notify.notification_type t WHERE NOT EXISTS (SELECT 1 FROM notify.template x WHERE x.template_key=t.template_key AND x.channel='in_app' AND x.locale='en-US')), 0,
  'A30: every registry row has an en-US in_app template (the centre can always render)');
SELECT is((SELECT count(*)::int FROM notify.notification_type t WHERE 'push' = ANY(t.allowed_channels) AND NOT EXISTS (SELECT 1 FROM notify.template x WHERE x.template_key=t.template_key AND x.channel='push')), 0,
  'A31: every push-capable type has a push template; account_deletion_completed has none (E-only)');
SELECT is((SELECT count(*)::int FROM notify.template WHERE coalesce(subject,'') || ' ' || body ~* '(kernel|catalog|\mrail\M|ticket atom|SSCAS|credential_version|market_sale|ownership log|\mbatch\M|\mshard\M|resale_state|cause-code)'), 0,
  'A32 (N-A18): no forbidden vocabulary in any template');
SELECT is((SELECT count(*)::int FROM notify.notification_type WHERE display_label || ' ' || coalesce(description,'') ~* '(kernel|catalog|\mrail\M|ticket atom|SSCAS|credential_version|market_sale|ownership log|\mbatch\M|\mshard\M|resale_state|cause-code)'), 0,
  'A33: no forbidden vocabulary in registry labels/descriptions');
SELECT is((SELECT count(*)::int FROM notify.template WHERE channel='push' AND (body ~ '\{\{amount' OR body ~ '\{\{(subject_label|actor|counterparty)' OR coalesce(subject,'') ~ '\{\{amount')), 0,
  'A34 (§8.4 N-P1): push copy carries no amount and no counterparty-name placeholder');
SELECT is((SELECT count(*)::int FROM notify.template WHERE template_key IN ('payout_on_hold','promoter_commission_accrued','refund_request_expired','refund_request_cancelled','refund_request_parked','payout_request_pending_approval') AND body ~* '\m(paid|sent)\M'), 0,
  'A35 (money truthfulness): held/pending/accrued copy never says paid or sent');
SELECT is((SELECT body FROM notify.template WHERE template_key='account_deletion_completed' AND channel='in_app'), 'Your account deletion was completed. This account can no longer be used to sign in.',
  'A36 (DSM §4.7): the terminal copy never says "permanently deleted" / "all associated data"');
SELECT has_index('notify','notification','notification_dedupe_key_uq','A37: hop-3 key — partial UNIQUE on dedupe_key (057 pattern)');
SELECT ok((SELECT indpred IS NOT NULL FROM pg_index WHERE indexrelid='notify.notification_dedupe_key_uq'::regclass), 'A38: …and it is partial (NULL dedupe keys never collide)');
SELECT col_is_unique('notify','delivery',ARRAY['notification_id','channel'],'A39: hop-4 key — UNIQUE(notification_id, channel)');
SELECT col_is_unique('notify','notification_type',ARRAY['type_key','delivery_class'],'A40: UNIQUE(type_key, delivery_class) — the composite the preference FK targets');
SELECT ok((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='preference_type_class_fk') ~ 'ON UPDATE CASCADE', 'A41: preference (type_key, delivery_class) FK ON UPDATE CASCADE');
SELECT is((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='preference_not_mandatory_ck'), 'CHECK ((delivery_class <> ''mandatory''::text))', 'A42: the mandatory guard is DDL (§3.3)');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='kernel' AND c.relkind='r'), 28, 'A43: kernel tables unchanged at 28');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='venue' AND c.relkind='r'), 29, 'A44: venue tables unchanged at 29');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('kernel','venue','catalog','market','notify') AND c.relkind IN ('r','p','v','m','S','f')), 75, 'A45: five-schema relations 75 (69 post-091 + 6)');
-- 2026-09-02 (package 093): 243 -> 250. RATIFIED CONTRACT CHANGE — SEVEN kernel routines:
-- settlement_primary_lines (A3) · sync_org_connect_state + get_org_connect_state (A6) ·
-- stage_org_connect_ref + get_org_connect_ref (A7/A9, RT-A-3) · get_refund_execution_context (D3) ·
-- is_order_buyer (F). notify itself is unmoved at 17, which is what this row guards.
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 259,
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
  'A46: five-schema routines 259 (228 + 092''s 15 + 093''s 16 kernel)');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 72, 'A47: policy register 72 (67 + 5 notify owner policies)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('kernel','venue','catalog','market')
             AND p.prosrc ~ '(notify|"notify")\s*\.\s*"?(notification_type|notification|delivery|preference|template|identity_channel_state)"?\M'), 0,
  'A48: 092 replaced NO seam and touched NO routine outside notify — the 19 hooks stand (SEAM final census unchanged)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname, p.proname) IN
  (('kernel','settlement_commission_lines'),('kernel','settlement_royalty_lines'),('market','on_atom_voided'),('market','on_door_freeze_engaged'),('market','door_freeze_drain_preview'),
   ('kernel','deletion_blockers_market'),('kernel','on_identity_erased_market'),('kernel','deletion_blockers_custody'),('kernel','deletion_blockers_wallet'),('kernel','deletion_blockers_money'),
   ('kernel','on_identity_erased_promoter'),('kernel','is_promoter_for_event'))), 12,
  'A49: the SEAM hooks named by 090/091 still exist with one overload each (spot census)');

-- ============================================================================
-- SECTION B — POSTURE (RLS §16.9 / §11; GP-1/GP-2; 076 wall)
-- ============================================================================
SELECT is(has_schema_privilege('authenticated','notify','USAGE'), true, 'B1 (E-152): authenticated has USAGE on notify — the client surface''s precondition');
SELECT is(has_schema_privilege('anon','notify','USAGE'), false, 'B2: anon stays walled out of notify');
SELECT is(has_schema_privilege('service_role','notify','USAGE'), true, 'B3: service_role keeps USAGE (076)');
SELECT is(has_table_privilege('authenticated','notify.notification','SELECT'), true, 'B4: notification — authenticated SELECT (040 posture)');
SELECT is(has_table_privilege('authenticated','notify.notification','UPDATE'), false, 'B5: notification — no table-level UPDATE');
SELECT is(has_column_privilege('authenticated','notify.notification','read_at','UPDATE'), true, 'B6: notification — UPDATE(read_at) only');
SELECT is(has_column_privilege('authenticated','notify.notification','params','UPDATE') OR has_column_privilege('authenticated','notify.notification','recipient_id','UPDATE'), false, 'B7: …no other column is updatable');
SELECT is(has_table_privilege('authenticated','notify.notification','INSERT') OR has_table_privilege('authenticated','notify.notification','DELETE'), false, 'B8: notification — no INSERT, no DELETE for clients (GP-2)');
SELECT is((SELECT count(*)::int FROM information_schema.role_table_grants WHERE table_schema='notify' AND grantee IN ('anon','service_role')), 0, 'B9: anon and service_role hold ZERO notify table grants (service_role is BYPASSRLS — its wall is the grant wall)');
SELECT is(has_table_privilege('authenticated','notify.preference','SELECT') AND has_table_privilege('authenticated','notify.preference','INSERT') AND has_table_privilege('authenticated','notify.preference','UPDATE'), true, 'B10: preference — owner CRUD minus delete');
SELECT is(has_table_privilege('authenticated','notify.preference','DELETE'), false, 'B11: preference — no DELETE');
SELECT is((SELECT count(*)::int FROM information_schema.role_table_grants WHERE table_schema='notify' AND table_name IN ('notification_type','template','delivery','identity_channel_state','outbox') AND grantee <> 'postgres'), 0,
  'B12: notification_type · template · delivery · identity_channel_state · outbox — deny-all, no client grant');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='notify' AND c.relkind='r' AND c.relrowsecurity), 7, 'B13: RLS enabled on all seven notify tables');
SELECT is((SELECT string_agg(policyname, ',' ORDER BY policyname COLLATE "C") FROM pg_policies WHERE schemaname='notify'),
  'notify_notification_sel_owner,notify_notification_upd_owner,notify_preference_ins_owner,notify_preference_sel_owner,notify_preference_upd_owner',
  'B14: exactly the five §16.9 owner policies, by name; zero on the deny-all tables');
SELECT is((SELECT count(*)::int FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            WHERE p.pronamespace='notify'::regnamespace AND a.privilege_type='EXECUTE'
              AND p.proname IN ('drain_outbox','enqueue','channel_enabled','claim_deliveries','record_delivery_result','resolve_web_link')
              AND (a.grantee = 0 OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated')))), 0,
  'B15: the six internal definers — zero PUBLIC/anon/authenticated EXECUTE');
SELECT is((SELECT count(DISTINCT p.proname)::int FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
            WHERE p.pronamespace='notify'::regnamespace AND a.privilege_type='EXECUTE'
              AND p.proname IN ('drain_outbox','enqueue','channel_enabled','claim_deliveries','record_delivery_result','resolve_web_link')
              AND a.grantee = (SELECT oid FROM pg_roles WHERE rolname='service_role')), 6,
  'B16: …and every one of the six is EXECUTE: service_role (RLS §11)');
SELECT is((SELECT count(DISTINCT p.proname)::int FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
            WHERE p.pronamespace='notify'::regnamespace AND a.privilege_type='EXECUTE'
              AND p.proname IN ('get_inbox','get_unread_count','mark_read','mark_all_read','dismiss','get_preference_matrix','set_preference','register_push_token','revoke_push_token')
              AND a.grantee = (SELECT oid FROM pg_roles WHERE rolname='authenticated')), 9,
  'B17: the nine consumer RPCs — EXECUTE: authenticated');
SELECT is((SELECT count(*)::int FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            WHERE p.pronamespace='notify'::regnamespace AND a.privilege_type='EXECUTE'
              AND (a.grantee = 0 OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname='anon'))), 0,
  'B18: zero PUBLIC/anon EXECUTE anywhere in notify (PFA-1 sweep, this package''s own schema)');
-- direct-table posture as a client
SELECT tap.login(tap.buyer());
SELECT throws_like($$SELECT count(*) FROM notify.notification_type$$, '%permission denied%', 'B19: a client cannot read the registry table (served by RPC only)');
SELECT throws_like($$SELECT count(*) FROM notify.template$$, '%permission denied%', 'B20: …nor templates');
SELECT throws_like($$SELECT count(*) FROM notify.delivery$$, '%permission denied%', 'B21: …nor delivery rows');
SELECT throws_like($$SELECT count(*) FROM notify.identity_channel_state$$, '%permission denied%', 'B22: …nor transport facts');
SELECT throws_like($$SELECT count(*) FROM notify.outbox$$, '%permission denied%', 'B23: …nor the outbox (076 wall untouched for clients)');
SELECT throws_like($$INSERT INTO notify.notification (recipient_id, type_key, template_key, target_kind) VALUES (auth.uid(), 'payout_released', 'payout_released', 'payout')$$, '%permission denied%', 'B24: a client cannot mint a notification');
SELECT throws_like($$DELETE FROM notify.notification$$, '%permission denied%', 'B25: a client cannot delete (GP-2)');
SELECT throws_like($$UPDATE notify.notification SET params = '{}'::jsonb$$, '%permission denied%', 'B26: a client cannot rewrite params (column grant is read_at only)');
SELECT throws_like($$INSERT INTO notify.preference (identity_id, type_key, channel, enabled, delivery_class) VALUES (tap.other_user(), 'wallet_pass_available', 'push', true, 'default_on')$$, '%row-level security%', 'B27: a client cannot write another identity''s preference (RLS)');
SELECT tap.logout();

-- ============================================================================
-- SECTION C — REGISTRY SEMANTICS (§3.2 resolver, §3.3 guard, §3.7 matrix)
-- ============================================================================
SELECT is(notify.channel_enabled(tap.buyer(), 'payout_released', 'push'), true, 'C1: mandatory → push on, always');
SELECT is(notify.channel_enabled(tap.buyer(), 'payout_released', 'email'), true, 'C2: mandatory → email on, always (the row is born suppressed by N1, not by preference)');
SELECT is(notify.channel_enabled(tap.buyer(), 'wallet_pass_available', 'push'), false, 'C3: ON type with push default OFF (catalogue "I p") → off without an override');
SELECT is(notify.channel_enabled(tap.buyer(), 'promoter_commission_accrued', 'push'), false, 'C4: promoter_commission_accrued push default off');
SELECT is(notify.channel_enabled(tap.buyer(), 'promoter_commission_accrued', 'email'), true, 'C5: …email default on');
SELECT is(notify.channel_enabled(tap.buyer(), 'no_such_type', 'push'), false, 'C6: unknown type → false');
SELECT is(notify.channel_enabled(tap.buyer(), 'ticket_ready', 'email'), false, 'C7: a channel the registry does not allow → false even for a mandatory type');
UPDATE notify.notification_type SET active = false WHERE type_key = 'wallet_pass_available';
SELECT is(notify.channel_enabled(tap.buyer(), 'wallet_pass_available', 'push'), false, 'C8: inactive registry row → false');
UPDATE notify.notification_type SET active = true WHERE type_key = 'wallet_pass_available';
SELECT tap._store157('matrix_expected', (SELECT sum(cardinality(allowed_channels))::text FROM notify.notification_type WHERE active AND NOT legacy));
SELECT tap.login(tap.buyer());
SELECT throws_ok($$SELECT notify.set_preference('payout_released', 'push', false)$$, '40003', 'mandatory_type_not_configurable', 'C9 (N-A3): a mandatory type raises 40003 mandatory_type_not_configurable');
SELECT throws_ok($$SELECT notify.set_preference('no_such_type', 'push', false)$$, 'P0002', NULL, 'C10: unknown type → not_found');
SELECT throws_ok($$SELECT notify.set_preference('wallet_pass_available', 'sms', false)$$, 'P0001', NULL, 'C11: sms is not a channel');
SELECT throws_ok($$SELECT notify.set_preference('wallet_pass_available', 'email', true)$$, 'P0001', NULL, 'C12: a channel the type does not offer → precondition_failed');
SELECT is((notify.set_preference('wallet_pass_available', 'push', true) ->> 'enabled'), 'true', 'C13: an ON type''s push can be switched on');
SELECT is((SELECT count(*)::int FROM notify.get_preference_matrix()), 53, 'C14: the matrix is every active type × its allowed channels = 53 rows');
SELECT is((SELECT count(*)::int FROM notify.get_preference_matrix()), tap._t157('matrix_expected')::int, 'C15: …computed from the registry, not hard-coded');
SELECT is((SELECT count(*)::int FROM notify.get_preference_matrix() WHERE delivery_class='mandatory' AND NOT effective_enabled), 0, 'C16: every mandatory row renders effective ON (locked)');
SELECT is((SELECT effective_enabled FROM notify.get_preference_matrix() WHERE type_key='wallet_pass_available' AND channel='push'), true, 'C17: the override is reflected');
SELECT is((notify.set_preference('wallet_pass_available', 'push', false) ->> 'enabled'), 'false', 'C18: …and toggled back off');
SELECT is((SELECT effective_enabled FROM notify.get_preference_matrix() WHERE type_key='wallet_pass_available' AND channel='push'), false, 'C19: the matrix follows');
SELECT tap.logout();
SELECT is(notify.channel_enabled(tap.buyer(), 'wallet_pass_available', 'push'), false, 'C20: the resolver reads the sparse override (explicit off)');
SELECT tap.login_anon();
SELECT throws_like($$SELECT count(*) FROM notify.get_preference_matrix()$$, '%permission denied for schema notify%', 'C21: anon cannot even reach the schema (076 wall; E-152 opens it to authenticated only)');
SELECT throws_ok($$SELECT notify.set_preference('wallet_pass_available', 'push', true)$$, '42501', NULL, 'C22: anon cannot set a preference');
SELECT tap.logout();
SELECT throws_like($$INSERT INTO notify.preference (identity_id, type_key, channel, enabled, delivery_class) VALUES (tap.buyer(), 'payout_released', 'push', false, 'mandatory')$$, '%preference_not_mandatory_ck%', 'C23 (N-A2): the DDL guard refuses a mandatory-class override even for the table owner');
SELECT throws_like($$INSERT INTO notify.preference (identity_id, type_key, channel, enabled, delivery_class) VALUES (tap.buyer(), 'payout_released', 'push', false, 'default_on')$$, '%preference_type_class_fk%', 'C24: …and a mis-declared class fails the composite FK — there is no path to silence a mandatory type');

-- ============================================================================
-- SECTION D — ENQUEUE (hop 3) + THE THREE IDEMPOTENCY KEYS (§4.2)
-- ============================================================================
SELECT tap._store157('pay_id', gen_random_uuid()::text);
SELECT tap._store157('n1', notify.enqueue(tap.buyer(), 'payout_released', 'payout', tap._u157('pay_id'), jsonb_build_object('amount_minor', 1234, 'currency', 'USD', 'target_id', tap._u157('pay_id')), 'k-d1')::text);
SELECT ok(tap._u157('n1') IS NOT NULL, 'D1: enqueue returns the notification id');
SELECT is((tap._nbykey157('k-d1')).type_key, 'payout_released', 'D2: type');
SELECT is((tap._nbykey157('k-d1')).target_kind || ':' || (tap._nbykey157('k-d1')).target_id::text, 'payout:' || tap._t157('pay_id'), 'D3: target kind from the registry, target id from params');
SELECT is(((tap._nbykey157('k-d1')).params ? 'target_id'), false, 'D4: target_id is stripped from the stored params');
SELECT is((tap._nbykey157('k-d1')).locale_resolved, 'en-US', 'D5: locale resolved to en-US (no stated preference)');
SELECT is((tap._nbykey157('k-d1')).title, NULL, 'D6 (N-A36): a 092 producer never writes the legacy title/body/link columns');
SELECT is(tap._dcount157(tap._u157('n1')), 2, 'D7: one delivery row per allowed channel (push + email)');
SELECT is((tap._d157(tap._u157('n1'),'push')).state, 'pending', 'D8: push is pending');
SELECT is((tap._d157(tap._u157('n1'),'email')).state || ':' || (tap._d157(tap._u157('n1'),'email')).suppress_reason, 'suppressed:channel_unavailable', 'D9 (NOTIF §2.1, N1): the E row is born suppressed / channel_unavailable');
SELECT is(notify.enqueue(tap.buyer(), 'payout_released', 'payout', tap._u157('pay_id'), '{"amount_minor": 9999}'::jsonb, 'k-d1')::text, tap._t157('n1'), 'D10 (hop-3 replay): the same dedupe_key returns the SAME id');
SELECT is(tap._n157(tap.buyer(), 'payout_released'), 1, 'D11: …and writes no second notification');
SELECT is(tap._dcount157(tap._u157('n1')), 2, 'D12: …and no second delivery row');
SELECT is((tap._nbykey157('k-d1')).params ->> 'amount_minor', '1234', 'D13: a replay never rewrites the first write (params frozen)');
SELECT is(notify.enqueue(tap.buyer(), 'no_such_type', 'x', gen_random_uuid(), '{}', 'k-d2'), NULL, 'D14: unknown type → NULL, never raises');
SELECT is(notify.enqueue('99999999-9999-9999-9999-999999999999', 'payout_released', 'payout', gen_random_uuid(), '{}', 'k-d3'), NULL, 'D15: a recipient that is not an auth.users row → NULL (FK; §8.8), never raises');
SELECT is((SELECT count(*)::int FROM notify.notification WHERE dedupe_key IN ('k-d2','k-d3')), 0, 'D16: …and nothing was written');
SELECT throws_like($$INSERT INTO notify.delivery (notification_id, channel) VALUES (tap._u157('n1'), 'push')$$, '%delivery_notification_channel_uq%', 'D17 (hop-4 key): a second push row for one notification is impossible');
SELECT lives_ok($$INSERT INTO notify.notification (recipient_id, type_key, template_key, target_kind) VALUES (tap.buyer(), 'ticket_ready', 'ticket_ready', 'order'), (tap.buyer(), 'ticket_ready', 'ticket_ready', 'order')$$, 'D18: NULL dedupe keys never collide (partial unique)');
DELETE FROM notify.notification WHERE recipient_id = tap.buyer() AND type_key = 'ticket_ready' AND dedupe_key IS NULL;
-- erasure + transport facts
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES (tap.other_user(), 'ERASED') ON CONFLICT (identity_id) DO UPDATE SET deletion_state = 'ERASED';
SELECT tap._store157('n_er', notify.enqueue(tap.other_user(), 'payout_released', 'payout', gen_random_uuid(), '{}', 'k-erased')::text);
SELECT is((tap._d157(tap._u157('n_er'),'push')).state || ':' || (tap._d157(tap._u157('n_er'),'push')).suppress_reason, 'suppressed:identity_erased', 'D19 (E-23 class): push to an ERASED identity is suppressed');
UPDATE kernel.identity_ext SET deletion_state = 'ACTIVE' WHERE identity_id = tap.other_user();
INSERT INTO notify.identity_channel_state (identity_id, channel, state, reason) VALUES (tap.other_user(), 'push', 'unreachable', 'fixture');
SELECT tap._store157('n_un', notify.enqueue(tap.other_user(), 'payout_released', 'payout', gen_random_uuid(), '{}', 'k-unreach')::text);
SELECT is((tap._d157(tap._u157('n_un'),'push')).suppress_reason, 'undelivered_mandatory', 'D20 (§3.5): a mandatory type with no push transport is recorded undelivered_mandatory');
INSERT INTO notify.preference (identity_id, type_key, channel, enabled, delivery_class) VALUES (tap.other_user(), 'wallet_pass_available', 'push', true, 'default_on');
SELECT tap._store157('n_un2', notify.enqueue(tap.other_user(), 'wallet_pass_available', 'ticket_pass', gen_random_uuid(), '{}', 'k-unreach2')::text);
SELECT is((tap._d157(tap._u157('n_un2'),'push')).suppress_reason, 'no_transport', 'D21: …an ON type is plain no_transport');
DELETE FROM notify.identity_channel_state WHERE identity_id = tap.other_user();
SELECT tap._store157('n_off', notify.enqueue(tap.buyer(), 'wallet_pass_available', 'ticket_pass', gen_random_uuid(), '{}', 'k-off')::text);
SELECT is((tap._d157(tap._u157('n_off'),'push')).suppress_reason, 'preference_off', 'D22: an explicit off override suppresses push as preference_off');
SELECT is(tap._n157(tap.buyer(), 'wallet_pass_available'), 1, 'D23: …but the in-app row is always written (I is never suppressible)');

-- ============================================================================
-- SECTION E — THE DRAINER (hop 2 → hop 3): producer parity over the SHIPPED
--   envelope shapes (077/085/087/088/090), recipient forms §2.4, poison
--   quarantine, batch isolation, and the cursor-bounded custody expansion.
-- ============================================================================
-- E1 ownership_changed (088 shape: aggregate ticket_atom, payload to/cause/credential_version)
SELECT tap._emit157('ownership_changed', 'ticket_atom', tap._u157('a1'), 'ownership:' || tap._t157('a1') || ':' || tap._t157('cv1'),
  jsonb_build_object('to_identity', tap.buyer(), 'cause', 'issue', 'credential_version', tap._t157('cv1')::int));
SELECT tap._store157('r1', notify.drain_outbox(50)::text);
SELECT is((tap._t157('r1')::jsonb ->> 'done') || '/' || (tap._t157('r1')::jsonb ->> 'resolved'), '1/1', 'E1: one envelope drained → one notification');
SELECT is((tap._nrow157(tap.buyer(), 'ownership_changed')).dedupe_key, 'ownership_changed:' || tap._t157('a1') || ':1:acquired', 'E2: keyed on the ownership-log entry (atom, sequence) + role (§2.2 precedent)');
SELECT is((tap._nrow157(tap.buyer(), 'ownership_changed')).params ->> 'cause_label', 'Issued to you', 'E3 (§5.5): a plain-verb label, never a cause-code');
SELECT is((tap._nrow157(tap.buyer(), 'ownership_changed')).params ->> 'event_title', 'Notify Night', 'E4: event title resolved through the atom');
SELECT is((tap._nrow157(tap.buyer(), 'ownership_changed')).target_kind || ':' || (tap._nrow157(tap.buyer(), 'ownership_changed')).target_id::text, 'ticket:' || tap._t157('a1'), 'E5: target = the ticket');
SELECT is((SELECT count(*)::int FROM notify.notification WHERE dedupe_key LIKE 'ownership_changed:%:released'), 0, 'E6: an issuance has no losing owner → no released row');
SELECT is((tap._ob157('ownership_changed', NULL)).state, 'done', 'E7: the envelope is done');
SELECT is((notify.drain_outbox(50) ->> 'done'), '0', 'E8 (at-least-once, hop 2): a second tick finds nothing');
SELECT tap._emit157('ownership_changed', 'ticket_atom', tap._u157('a1'), 'ownership:' || tap._t157('a1') || ':' || tap._t157('cv1'), '{}'::jsonb);
SELECT is(tap._obcount157('ownership_changed', NULL), 1, 'E9 (hop-2 key): a producer replay of the same event_key writes no second envelope');
UPDATE notify.outbox SET state = 'pending' WHERE event_type = 'ownership_changed';
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '1', 'E10 (hop-3 key): re-draining a redelivered envelope RESOLVES to the existing notification (a replay, not a write)');
SELECT is(tap._n157(tap.buyer(), 'ownership_changed'), 1, 'E11: …count still 1');
-- E12 poison quarantine + batch isolation
SELECT tap._emit157('purchase_confirmed', 'market_sale', '00000000-0000-0000-0000-0000000000ee', 'purchase_confirmed:poison', '{}'::jsonb);
SELECT tap._emit157('account_deletion_pending', 'identity', tap.buyer(), 'account_deletion_pending:' || tap.buyer()::text || ':t1', jsonb_build_object('deletion_requested_at', now()::text));
SELECT tap._emit157('attribution_recorded', 'order', gen_random_uuid(), 'attribution_recorded:x', '{}'::jsonb);
SELECT tap._store157('r2', notify.drain_outbox(50)::text);
SELECT is((tap._t157('r2')::jsonb ->> 'done') || '/' || (tap._t157('r2')::jsonb ->> 'dead') || '/' || (tap._t157('r2')::jsonb ->> 'unmapped') || '/' || (tap._t157('r2')::jsonb ->> 'resolved'), '2/1/1/1',
  'E12 (failure isolation): one poison envelope goes dead, the good one and the unmapped one complete in the same batch');
SELECT is((tap._ob157('purchase_confirmed', 'purchase_confirmed:poison')).state, 'dead', 'E13: the malformed envelope is quarantined dead — never retried forever');
SELECT alike((tap._ob157('purchase_confirmed', 'purchase_confirmed:poison')).last_error, 'unresolvable aggregate market_sale%', 'E14: …with the reason recorded');
SELECT is((tap._ob157('attribution_recorded', NULL)).state, 'done', 'E15 (E-159): an OUT-type envelope is a fact with no consumer — done with zero rows');
SELECT is(tap._n157(tap.buyer(), 'account_deletion_pending'), 1, 'E16: account_deletion_pending → self (form 4)');
SELECT is((tap._d157((tap._nrow157(tap.buyer(),'account_deletion_pending')).notification_id,'push')).state, 'pending', 'E17: …push pending');
-- E18 payout_on_hold (088/090 shape) — identity payee, then org payee (approver set)
INSERT INTO kernel.payout (payout_id, payee_kind, payee_identity_id, cause, cause_ref, amount_minor, currency, status, hold_state, hold_reason_code, held_at, idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b1', 'identity', tap.other_user(), 'market_sale', gen_random_uuid(), 500, 'USD', 'pending', 'held', 'dispute', now(), 'ck92-po1');
SELECT tap._emit157('payout_on_hold', 'payout', '00000000-0000-0000-0000-0000000000b1', 'payout_on_hold:b1:dispute', '{"dispute_id":"x","reason":"dispute","amount_minor":500}'::jsonb);
INSERT INTO kernel.payout (payout_id, payee_kind, payee_org_id, cause, cause_ref, amount_minor, currency, status, hold_state, hold_reason_code, held_at, idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000b2', 'organization', tap._u157('org1'), 'settlement', gen_random_uuid(), 8000, 'USD', 'pending', 'held', 'unfunded_settlement', now(), 'ck92-po2');
SELECT tap._emit157('payout_on_hold', 'payout', '00000000-0000-0000-0000-0000000000b2', 'payout_on_hold:b2:unfunded_settlement', '{"reason":"unfunded_settlement","amount_minor":8000}'::jsonb);
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '3', 'E18: identity payee → 1 row; org payee → the org_owner ∪ org_finance union (seller, fin157) → 2 rows');
SELECT is((tap._nrow157(tap.other_user(), 'payout_on_hold')).params ->> 'reason_label', 'a dispute is open', 'E19: the hold reason is a label, not a code');
SELECT is(tap._n157(tap.seller(), 'payout_on_hold') + tap._n157(tap.fin157(), 'payout_on_hold'), 2, 'E20 (§2.4 form 3, CONFLICT-5): explicit array union, no inheritance');
SELECT is((tap._nrow157(tap.fin157(), 'payout_on_hold')).params ->> 'reason_label', 'funding not yet confirmed', 'E21 (090 hold arm): unfunded_settlement is rendered truthfully as a hold');
-- E22 payout_request_pending_approval (087 shape: aggregate settlement)
INSERT INTO venue.settlement (settlement_id, org_id, venue_id, event_id, status, currency)
VALUES ('00000000-0000-0000-0000-0000000000c1', tap._u157('org1'), tap._u157('venue1'), tap._u157('event1'), 'open', 'USD');
SELECT tap._emit157('payout_request_pending_approval', 'settlement', '00000000-0000-0000-0000-0000000000c1', 'payout_request:c1', jsonb_build_object('org_id', tap._u157('org1'), 'amount_minor', 9000));
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '2', 'E22: the parked payout reaches the approver set (owner + finance)');
SELECT is((tap._nrow157(tap.seller(), 'payout_request_pending_approval')).params ->> 'org_name', 'Notify Co', 'E23: org display name in params');
-- E24 refund_requested (088 shape: aggregate refund → payer via public.payments)
SELECT tap._store157('pay2', tap._newpayment157(tap.buyer(), tap.seller(), 7000, 'pi_92_2')::text);
INSERT INTO kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency, status, idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000d1', tap._u157('pay2'), 'buyer_request', 700, 'USD', 'pending', 'ck92-rf1');
SELECT tap._emit157('refund_requested', 'refund', '00000000-0000-0000-0000-0000000000d1', 'refund_requested:d1', '{"amount_minor":700,"reason":"buyer_request"}'::jsonb);
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '1', 'E24: refund_requested → the payer');
SELECT is((tap._nrow157(tap.buyer(), 'refund_requested')).params ->> 'amount_minor', '700', 'E25: amount travels raw (minor + currency; §5.4)');
SELECT is((tap._nrow157(tap.buyer(), 'refund_requested')).params ->> 'reason_label', 'your request', 'E26: reason as a label');
-- E27 refund_request_expired / cancelled (085 shape: aggregate approval_request)
INSERT INTO kernel.approval_request (request_id, action, required_approver_class, subject_kind, subject_id, org_id, payload, amount_minor, config_versions, requested_by, state, expires_at, command_idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000e1', 'refund.issue', 'org', 'order', tap._u157('o1'), tap._u157('org1'), '{}', 5000, '{}', tap.buyer(), 'expired', now() + interval '1 hour', 'ck92-ar1');
SELECT tap._emit157('refund_request_expired', 'approval_request', '00000000-0000-0000-0000-0000000000e1', 'expire:e1', '{"action":"refund.issue"}'::jsonb);
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '3', 'E27: "both parties" = the payer + the org approver set → 3 rows');
SELECT is((tap._nrow157(tap.buyer(), 'refund_request_expired')).params ->> 'reason_label', 'no decision', 'E28: expiry label');
SELECT tap._emit157('refund_request_cancelled', 'approval_request', '00000000-0000-0000-0000-0000000000e1', 'cancel:e1', '{"by":"buyer"}'::jsonb);
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '1', 'E29 (OR-15): cancelled → the buyer only');
-- E30 promoter_commission_accrued (090 shape)
INSERT INTO venue.promoter (promoter_id, identity_id, org_id, terms_version, status, tier, party_kind, commission_kind, commission_bps, currency)
VALUES ('00000000-0000-0000-0000-0000000000f1', tap.other_user(), tap._u157('org1'), 1, 'active', 'professional_invited', 'promoter', 'bps', 1000, 'USD');
SELECT tap._emit157('promoter_commission_accrued', 'attribution', '00000000-0000-0000-0000-0000000000f2', 'commission:f2',
  jsonb_build_object('settlement_id', '00000000-0000-0000-0000-0000000000c1', 'payout_id', '00000000-0000-0000-0000-0000000000b1', 'amount_minor', 300, 'promoter_id', '00000000-0000-0000-0000-0000000000f1'));
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '1', 'E30: commission accrual → the promoter''s identity');
SELECT is((tap._nrow157(tap.other_user(), 'promoter_commission_accrued')).target_kind || ':' || (tap._nrow157(tap.other_user(), 'promoter_commission_accrued')).target_id::text, 'payout:00000000-0000-0000-0000-0000000000b1', 'E31: target = the HELD payout');
SELECT is((tap._d157((tap._nrow157(tap.other_user(),'promoter_commission_accrued')).notification_id,'push')).suppress_reason, 'preference_off', 'E32: push default off for the ON type → suppressed preference_off; the in-app row exists');
-- E33 security_org_role_granted (077 shape: aggregate = the subject; payload org_id/role_label/actor_identity)
SELECT tap._emit157('security_org_role_granted', 'identity', tap.fin157(), 'security_role_grant:' || gen_random_uuid()::text,
  jsonb_build_object('org_id', tap._u157('org1'), 'role_label', 'org_finance', 'actor_identity', tap.seller()));
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '2', 'E33: the subject + [org_owner] → 2 rows');
SELECT is((tap._nrow157(tap.fin157(), 'security_org_role_granted')).params ->> 'subject_label', 'you', 'E34: the subject reads "you"');
SELECT is((tap._nrow157(tap.seller(), 'security_org_role_granted')).params ->> 'subject_label', 'Finn Ledger', 'E35: the owner reads the subject''s display name (in-app only; push copy names nobody — A34)');
SELECT is((tap._nrow157(tap.seller(), 'security_org_role_granted')).params ->> 'role_label', 'org finance', 'E36: role label humanised');
SELECT is((SELECT count(*)::int FROM notify.notification WHERE params ? 'actor_identity'), 0, 'E37 (§8.5): the actor''s identity never reaches a notification');
-- E38 event_cancelled: the REAL 088 producer + cursor-bounded custody expansion
SELECT tap.login(tap.seller());
SELECT lives_ok($$SELECT catalog.cancel_event(tap._u157('event1'), 'weather', 'ck92-cancel')$$, 'E38: catalog.cancel_event (REQUIRED emitter, R2 row 3) runs');
SELECT tap.logout();
SELECT is(tap._obcount157('event_cancelled', 'pending'), 1, 'E39: the event_cancelled envelope is pending (aggregate event)');
SELECT is((SELECT count(*)::int FROM kernel.tickets WHERE event_session_id = tap._u157('session1') AND state = 'voided'), 3, 'E40: the cascade voided the three atoms');
-- clone 600 more voided atoms for the buyer (the atom row first for the ledger FK; the deferred custody invariant sees both at COMMIT)
INSERT INTO kernel.tickets (ticket_atom_id, event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, state, resale_state, credential_version, signing_key_id, home_region, issued_at)
SELECT ('00000000-0000-0000-00aa-' || lpad(g::text, 12, '0'))::uuid, tap._u157('session1'), tap._u157('org1'), tap._u157('tt1'), 1000 + g, tap.buyer(), 'voided', 'none', 0,
       (SELECT signing_key_id FROM kernel.tickets WHERE ticket_atom_id = tap._u157('a1')), (SELECT home_region FROM kernel.tickets WHERE ticket_atom_id = tap._u157('a1')), now()
  FROM generate_series(1, 600) g;
INSERT INTO kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref, actor_identity, command_idempotency_key, occurred_at, credential_version_after, state_transition)
SELECT ('00000000-0000-0000-00aa-' || lpad(g::text, 12, '0'))::uuid, 1, NULL, tap.buyer(), 'issue', tap._u157('o1'), tap.seller(), 'ck92-clone-' || g, now(), 0, '{}'::jsonb FROM generate_series(1, 600) g;
SELECT tap._store157('r3', notify.drain_outbox(50)::text);
SELECT is((tap._t157('r3')::jsonb ->> 'deferred'), '1', 'E41 (§17.24 (i)): a 603-atom expansion is NOT finished in one tick — the envelope is deferred');
SELECT is((tap._ob157('event_cancelled', NULL)).state || ':' || (tap._ob157('event_cancelled', NULL)).expanded_count::text, 'pending:500', 'E42: state pending, 500 expanded, cursor persisted');
SELECT ok((tap._ob157('event_cancelled', NULL)).expand_cursor IS NOT NULL, 'E43: the cursor is on the envelope');
SELECT is(tap._n157(tap.buyer(), 'event_cancelled'), 500, 'E44: 500 per-ticket rows so far');
SELECT tap._store157('r4', notify.drain_outbox(50)::text);
SELECT is((tap._ob157('event_cancelled', NULL)).state || ':' || (tap._ob157('event_cancelled', NULL)).expanded_count::text, 'done:603', 'E45: the second tick finishes: done, 603 expanded');
SELECT is(tap._n157(tap.buyer(), 'event_cancelled'), 603, 'E46: one row per voided ticket (catalogue key event_cancelled:<session>:<ticket>)');
SELECT is((SELECT count(DISTINCT dedupe_key)::int FROM notify.notification WHERE type_key='event_cancelled'), 603, 'E47: …all distinct');
SELECT is((notify.drain_outbox(50) ->> 'done'), '0', 'E48: a third tick has nothing');
SELECT is(tap._obcount157('refund_requested', 'dead'), 0, 'E49: no refund_requested envelope from the cascade died (whatever the cascade emitted resolved)');
SELECT is((SELECT count(*)::int FROM notify.outbox WHERE state = 'claimed'), 0, 'E50: the drainer never leaves an envelope claimed (single-transaction tick)');

-- ============================================================================
-- SECTION F — CLAIM (hop 4) / RECORD (hop 5) — RPC §17.25
-- ============================================================================
SELECT throws_ok($$SELECT * FROM notify.claim_deliveries('push', 10)$$, 'P0001', NULL, 'F1 (fail-closed): claim refuses while notify.delivery_lease_interval is owner-unset');
SELECT tap._cfg157('notify.delivery_lease_interval', '"5 minutes"'::jsonb);
SELECT throws_ok($$SELECT * FROM notify.claim_deliveries('sms', 10)$$, 'P0001', NULL, 'F2: sms is not a channel');
SELECT is((SELECT count(*)::int FROM notify.claim_deliveries('email', 100)), 0, 'F3 (N1): no email delivery is ever pending — claim(email) is empty');
SELECT tap._store157('pending_push', (SELECT count(*)::text FROM notify.delivery WHERE channel='push' AND state='pending' AND next_attempt_at <= now()));
SELECT is((SELECT count(*)::int FROM notify.claim_deliveries('push', 5)), 5, 'F4: p_limit bounds the claim');
SELECT is((SELECT count(*)::int FROM notify.delivery WHERE state='claimed' AND claimed_until > now() AND attempt = 1), 5, 'F5: claimed rows carry a future lease and attempt 1');
SELECT is((SELECT count(*)::int FROM notify.delivery WHERE state='claimed' AND (rendered_body IS NULL OR rendered_subject IS NULL)), 0, 'F6 (§5.3): copy is rendered at claim time and frozen on the row');
SELECT is((SELECT count(*)::int FROM notify.claim_deliveries('push', 10000)), 500, 'F7: p_limit is capped at 500 per call (§17.25 "capped")');
SELECT is((SELECT count(*)::int FROM notify.claim_deliveries('push', 10000)), tap._t157('pending_push')::int - 505, 'F7b: the rest are claimed; nothing is claimed twice');
SELECT is((SELECT count(*)::int FROM notify.claim_deliveries('push', 10000)), 0, 'F8: a live lease is not re-claimable');
SELECT is((SELECT rendered_body FROM notify.delivery WHERE notification_id = (tap._nrow157(tap.other_user(),'payout_on_hold')).notification_id AND channel='push'), 'A payout is being held. Open the app for details.',
  'F9 (§8.4): the push wire copy for a money type carries no amount');
SELECT is((SELECT count(*)::int FROM notify.delivery WHERE channel='push' AND rendered_body ~ '[0-9]+\.[0-9]{2} [A-Z]{3}'), 0, 'F10: no push copy anywhere contains a formatted amount');
SELECT is((SELECT rendered_subject FROM notify.delivery WHERE delivery_id = (tap._d157(tap._u157('n1'),'push')).delivery_id), 'Payout sent', 'F11: rendered subject from the push template');
-- record: sent / noop / transient / dead / device_not_registered / permanent / no_transport
SELECT is((notify.record_delivery_result((tap._d157(tap._u157('n1'),'push')).delivery_id, 'sent', 'msg-1', 'rcpt-1', NULL, NULL, NULL) ->> 'state'), 'sent', 'F12: sent');
SELECT ok((tap._d157(tap._u157('n1'),'push')).sent_at IS NOT NULL AND (tap._d157(tap._u157('n1'),'push')).claimed_until IS NULL AND (tap._d157(tap._u157('n1'),'push')).provider_receipt_state = 'pending', 'F13: sent_at set, lease cleared, receipt pending');
SELECT is((notify.record_delivery_result((tap._d157(tap._u157('n1'),'push')).delivery_id, 'transient', NULL, NULL, NULL, 'late', NULL) ->> 'noop'), 'true', 'F14 (terminal guard): a result after sent is a no-op');
SELECT tap._store157('d_tr', (tap._d157((tap._nrow157(tap.buyer(),'refund_requested')).notification_id,'push')).delivery_id::text);
SELECT is((notify.record_delivery_result(tap._u157('d_tr'), 'transient', NULL, NULL, NULL, 'ETIMEDOUT', NULL) ->> 'state'), 'pending', 'F15: transient → back to pending');
SELECT ok((SELECT next_attempt_at BETWEEN now() + interval '50 seconds' AND now() + interval '70 seconds' FROM notify.delivery WHERE delivery_id = tap._u157('d_tr')), 'F16: …with the +1m first backoff');
SELECT is((SELECT last_error FROM notify.delivery WHERE delivery_id = tap._u157('d_tr')), 'ETIMEDOUT', 'F17: …and the error recorded');
UPDATE notify.delivery SET attempt = 5, state = 'claimed' WHERE delivery_id = tap._u157('d_tr');
SELECT is((notify.record_delivery_result(tap._u157('d_tr'), 'transient', NULL, NULL, NULL, 'again', NULL) ->> 'state'), 'dead', 'F18: the fifth transient failure is dead (dead-letter = the row)');
SELECT tap._store157('d_perm', (tap._d157((tap._nrow157(tap.buyer(),'refund_request_expired')).notification_id,'push')).delivery_id::text);
SELECT is((notify.record_delivery_result(tap._u157('d_perm'), 'permanent', NULL, NULL, NULL, 'InvalidCredentials', NULL) ->> 'state'), 'dead', 'F19: permanent → dead');
SELECT tap._store157('d_nt', (tap._d157((tap._nrow157(tap.buyer(),'account_deletion_pending')).notification_id,'push')).delivery_id::text);
SELECT is((notify.record_delivery_result(tap._u157('d_nt'), 'no_transport', NULL, NULL, NULL, NULL, NULL) ->> 'state'), 'suppressed', 'F20: no_transport → suppressed');
SELECT is((SELECT suppress_reason FROM notify.delivery WHERE delivery_id = tap._u157('d_nt')), 'undelivered_mandatory', 'F21 (§3.5): …recorded undelivered_mandatory for the mandatory class');
SELECT is((notify.record_delivery_result(tap._u157('d_nt'), 'sent', NULL, NULL, NULL, NULL, NULL) ->> 'noop'), 'true', 'F22b: a suppressed row is terminal (no-op)');
SELECT throws_ok($$SELECT notify.record_delivery_result(tap._u157('d_nt'), 'bogus', NULL, NULL, NULL, NULL, NULL)$$, 'P0001', NULL, 'F23: an unknown outcome is refused');
SELECT throws_ok($$SELECT notify.record_delivery_result('00000000-0000-0000-0000-0000000000ff', 'sent', NULL, NULL, NULL, NULL, NULL)$$, 'P0002', NULL, 'F24: an unknown delivery is not_found');
-- device_not_registered → token revoked → identity unreachable → re-registration heals
SELECT tap.login(tap.other_user());
SELECT lives_ok($$SELECT notify.register_push_token('ExponentPushToken[other-1]', 'ios', 'iPhone', 'en-US')$$, 'F25: other_user registers a device');
SELECT tap.logout();
SELECT tap._store157('d_dnr', (tap._d157((tap._nrow157(tap.other_user(),'payout_on_hold')).notification_id,'push')).delivery_id::text);
SELECT is((notify.record_delivery_result(tap._u157('d_dnr'), 'device_not_registered', NULL, NULL, NULL, 'DeviceNotRegistered', 'ExponentPushToken[other-1]') ->> 'state'), 'failed', 'F26: device_not_registered → failed');
SELECT is((tap._tok157('ExponentPushToken[other-1]')).revoked_reason, 'device_not_registered', 'F27: the named token is revoked with the reason');
SELECT is(tap._ics157(tap.other_user(), 'push'), 'unreachable', 'F28: no live token remains → the identity is push-unreachable');
SELECT tap.login(tap.other_user());
SELECT lives_ok($$SELECT notify.register_push_token('ExponentPushToken[other-1]', 'ios', 'iPhone', NULL)$$, 'F29: the device re-registers');
SELECT tap.logout();
SELECT is(tap._ics157(tap.other_user(), 'push'), 'ok', 'F30 (§17.24): re-registration resets unreachable → ok');
SELECT ok((tap._tok157('ExponentPushToken[other-1]')).revoked_at IS NULL AND (tap._tok157('ExponentPushToken[other-1]')).is_active, 'F31: …and revives the token');
-- lease expiry → re-claim (at-least-once on the wire, stated plainly)
SELECT tap._store157('d_lease', (SELECT delivery_id::text FROM notify.delivery WHERE state='claimed' ORDER BY delivery_id LIMIT 1));
UPDATE notify.delivery SET claimed_until = now() - interval '1 second' WHERE delivery_id = tap._u157('d_lease');
SELECT is((SELECT count(*)::int FROM notify.claim_deliveries('push', 100)), 1, 'F32: an EXPIRED lease is re-claimable — a crashed sender''s row is never stranded');
SELECT is((SELECT attempt FROM notify.delivery WHERE delivery_id = tap._u157('d_lease')), 2, 'F33: …attempt 2 (the honest at-least-once boundary; exactly-once is NOT claimed)');
UPDATE notify.delivery SET claimed_until = now() - interval '1 second', attempt = 5 WHERE delivery_id = tap._u157('d_lease');
SELECT is((SELECT count(*)::int FROM notify.claim_deliveries('push', 100)), 0, 'F34: a lease that has expired five times is NOT re-claimable forever');
SELECT is((SELECT state || ':' || last_error FROM notify.delivery WHERE delivery_id = tap._u157('d_lease')), 'dead:lease expired: attempts exhausted', 'F35: …it is dead-lettered on the row with the reason');
DELETE FROM notify.template WHERE template_key = 'security_org_role_revoked' AND channel = 'push';
SELECT tap._store157('n_tm', notify.enqueue(tap.buyer(), 'security_org_role_revoked', 'identity', tap.buyer(), '{"role_label":"x","org_name":"y"}', 'k-tm')::text);
SELECT is((SELECT count(*)::int FROM notify.claim_deliveries('push', 100)), 0, 'F36: a delivery with NO template for its channel is never handed to the edge');
SELECT is((tap._d157(tap._u157('n_tm'),'push')).state || ':' || (tap._d157(tap._u157('n_tm'),'push')).last_error, 'dead:template_missing:security_org_role_revoked:push', 'F37: …it is dead-lettered with template_missing');

-- ============================================================================
-- SECTION G — THE CONSUMER SURFACE (auth.uid()-scoped; IDOR; keyset)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM notify.get_inbox(NULL, 50)), 50, 'G1: the inbox is keyset-paginated and capped at 50');
SELECT is((SELECT count(*)::int FROM notify.get_inbox(NULL, 500)), 50, 'G2: p_limit is capped at 50 (never .limit(50) client-side)');
SELECT ok((SELECT bool_and(created_at <= lag_c) FROM (SELECT created_at, lag(created_at) OVER (ORDER BY created_at DESC, notification_id DESC) AS lag_c FROM notify.get_inbox(NULL, 50)) x WHERE lag_c IS NOT NULL), 'G3: newest first');
SELECT tap._store157('cursor', (SELECT min(created_at)::text FROM notify.get_inbox(NULL, 50)));
SELECT is((SELECT count(*)::int FROM notify.get_inbox(tap._t157('cursor')::timestamptz, 50) WHERE created_at >= tap._t157('cursor')::timestamptz), 0, 'G4: the cursor page holds only older rows');
SELECT ok((SELECT count(*) FROM notify.get_inbox(tap._t157('cursor')::timestamptz, 50)) > 0, 'G4b (E-160): the second page is non-empty — rows written by one drain tick do not collapse into a keyset tie (clock_timestamp default)');
SELECT is((SELECT count(DISTINCT created_at)::int FROM notify.notification WHERE recipient_id = tap.buyer() AND type_key = 'event_cancelled'), tap._n157(tap.buyer(), 'event_cancelled'), 'G4c (E-160): every row of the 603-row expansion carries a distinct created_at');
SELECT tap._store157('ec_min', (SELECT min(created_at)::text FROM notify.notification WHERE recipient_id = tap.buyer() AND type_key = 'event_cancelled'));
SELECT is((SELECT rendered_title || ' | ' || rendered_body FROM notify.get_inbox(tap._t157('ec_min')::timestamptz, 50) WHERE notification_id = tap._u157('n1')), 'Payout sent | A payout of 12.34 USD was sent to your destination.',
  'G5 (§5.3): the centre renders at read time from template + params — the amount appears in-app only');
SELECT is((SELECT group_label || ':' || target_kind FROM notify.get_inbox(tap._t157('ec_min')::timestamptz, 50) WHERE notification_id = tap._u157('n1')), 'Payouts:payout', 'G6: group label + target kind (never a URL)');
SELECT is(notify.get_unread_count(), (SELECT count(*)::int FROM notify.notification WHERE recipient_id = tap.buyer() AND read_at IS NULL AND dismissed_at IS NULL), 'G7: unread count = own unread, undismissed');
SELECT is((notify.mark_read(ARRAY[tap._u157('n1')]) ->> 'updated'), '1', 'G8: mark_read writes read_at');
SELECT is((notify.mark_read(ARRAY[tap._u157('n1')]) ->> 'updated'), '0', 'G9: …idempotent');
SELECT is((SELECT count(*)::int FROM notify.notification WHERE recipient_id = tap.buyer()), tap._n157(tap.buyer(), NULL), 'G10: direct SELECT sees own rows only (RLS) — and all of them');
SELECT is((SELECT count(*)::int FROM notify.notification WHERE recipient_id <> tap.buyer()), 0, 'G11: …and none of anyone else''s');
SELECT lives_ok($$UPDATE notify.notification SET read_at = now() WHERE notification_id = tap._u157('n1')$$, 'G12: a direct read_at write on an own row is allowed (040 posture)');
SELECT is((SELECT count(*)::int FROM notify.notification WHERE recipient_id = tap.buyer() AND type_key='ownership_changed' AND read_at IS NULL), 1, 'G13 (pre): one unread ownership row');
SELECT is((notify.dismiss(ARRAY[(tap._nrow157(tap.buyer(),'ownership_changed')).notification_id]) ->> 'updated'), '1', 'G14: dismiss');
SELECT is((SELECT count(*)::int FROM notify.get_inbox(NULL, 50) WHERE type_key = 'ownership_changed'), 0, 'G15: a dismissed row leaves the inbox (never deleted)');
SELECT is(tap._n157(tap.buyer(), 'ownership_changed'), 1, 'G16: …the row still exists (GP-2)');
SELECT is((notify.mark_all_read() ->> 'updated'), (SELECT count(*)::text FROM notify.notification WHERE recipient_id = tap.buyer() AND read_at IS NULL AND dismissed_at IS NULL), 'G17: mark_all_read touches exactly the unread rows');
SELECT is(notify.get_unread_count(), 0, 'G18: …unread is now 0');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT is((SELECT count(*)::int FROM notify.get_inbox(NULL, 50) WHERE notification_id = tap._u157('n1')), 0, 'G19 (IDOR): another identity never sees the row');
SELECT is((notify.mark_read(ARRAY[tap._u157('n1')]) ->> 'updated'), '0', 'G20 (IDOR): …cannot mark it');
SELECT is((notify.dismiss(ARRAY[tap._u157('n1')]) ->> 'updated'), '0', 'G21 (IDOR): …cannot dismiss it');
SELECT is((SELECT count(*)::int FROM notify.get_inbox(NULL, 50) WHERE type_key='payout_on_hold'), 1, 'G22: other_user sees their own hold notice');
SELECT alike((SELECT rendered_body FROM notify.get_inbox(NULL, 50) WHERE type_key='payout_on_hold'), 'A payout of 5.00 USD is being held (a dispute is open). No money has moved.', 'G23: in-app copy states the hold truthfully');
SELECT alike((SELECT rendered_body FROM notify.get_inbox(NULL, 50) WHERE type_key='promoter_commission_accrued'), 'A commission of 3.00 USD was recorded%held until funding is confirmed.', 'G24 (money truthfulness): accrued ≠ paid — the copy says held');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_like($$SELECT count(*) FROM notify.get_inbox(NULL, 50)$$, '%permission denied for schema notify%', 'G25: anon cannot reach the inbox (schema wall)');
SELECT throws_like($$SELECT notify.get_unread_count()$$, '%permission denied for schema notify%', 'G26: anon cannot reach the counter (the never-raises rule is for signed-in readers; the wall is upstream)');
SELECT throws_ok($$SELECT notify.mark_all_read()$$, '42501', NULL, 'G27: anon cannot write');
SELECT tap.logout();
-- legacy-shaped row + locale fallback
INSERT INTO notify.notification (recipient_id, type_key, template_key, target_kind, title, body, dedupe_key) VALUES (tap.buyer(), 'ticket_ready', 'ticket_ready', 'order', 'Legacy title', 'Legacy body', 'k-legacy');
INSERT INTO kernel.identity_ext (identity_id, locale) VALUES (tap.buyer(), 'es-US') ON CONFLICT (identity_id) DO UPDATE SET locale = 'es-US';
SELECT tap.login(tap.buyer());
SELECT is((SELECT rendered_title || ' | ' || rendered_body FROM notify.get_inbox(NULL, 50) WHERE notification_id = (tap._nbykey157('k-legacy')).notification_id), 'Legacy title | Legacy body', 'G28 (N-A21): a legacy-shaped row renders its stored copy');
SELECT is((SELECT rendered_title FROM notify.get_inbox(tap._t157('ec_min')::timestamptz, 50) WHERE notification_id = tap._u157('n1')), 'Payout sent', 'G29 (§5.4): an es-US reader with no es-US template falls back to en-US copy');
SELECT tap.logout();
UPDATE kernel.identity_ext SET locale = NULL WHERE identity_id = tap.buyer();

-- ============================================================================
-- SECTION H — PUSH TOKENS (D-4/D-5/D-6; IDOR)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT lives_ok($$SELECT notify.register_push_token('ExponentPushToken[shared-1]', 'android', 'Pixel', 'en-US')$$, 'H1: buyer registers');
SELECT is((tap._tok157('ExponentPushToken[shared-1]')).user_id, tap.buyer(), 'H2: the row belongs to auth.uid()');
SELECT ok((tap._tok157('ExponentPushToken[shared-1]')).last_used IS NOT NULL AND (tap._tok157('ExponentPushToken[shared-1]')).is_active, 'H3 (D-5): last_used set on first insert');
SELECT throws_ok($$SELECT notify.register_push_token('ExponentPushToken[shared-1]', 'web', NULL, NULL)$$, 'P0001', NULL, 'H4: platform must be ios|android');
SELECT throws_ok($$SELECT notify.register_push_token('short', 'ios', NULL, NULL)$$, 'P0001', NULL, 'H5: token length is validated');
SELECT throws_ok($$SELECT notify.register_push_token('ExponentPushToken[shared-1]', 'ios', NULL, 'not a locale!')$$, 'P0001', NULL, 'H6: locale tag is validated (and otherwise not persisted — E-157)');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT lives_ok($$SELECT notify.register_push_token('ExponentPushToken[shared-1]', 'android', 'Pixel', NULL)$$, 'H7: the device changes hands');
SELECT is((tap._tok157('ExponentPushToken[shared-1]')).user_id, tap.other_user(), 'H8 (D-4): …and user_id ALWAYS follows auth.uid()');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((notify.revoke_push_token('ExponentPushToken[shared-1]') ->> 'revoked'), '0', 'H9 (IDOR): the previous owner cannot revoke it');
SELECT ok((tap._tok157('ExponentPushToken[shared-1]')).revoked_at IS NULL, 'H10: …still live');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT is((notify.revoke_push_token('ExponentPushToken[shared-1]') ->> 'revoked'), '1', 'H11 (D-6): the owner revokes on sign-out');
SELECT is((tap._tok157('ExponentPushToken[shared-1]')).revoked_reason, 'signed_out', 'H12: reason signed_out');
SELECT is((notify.revoke_push_token('ExponentPushToken[shared-1]') ->> 'revoked'), '0', 'H13: idempotent');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT notify.register_push_token('ExponentPushToken[anon-1]', 'ios', NULL, NULL)$$, '42501', NULL, 'H14: anon cannot register');
SELECT throws_ok($$SELECT notify.revoke_push_token('ExponentPushToken[shared-1]')$$, '42501', NULL, 'H15: anon cannot revoke');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.push_tokens WHERE user_id = tap.other_user() AND revoked_at IS NULL), 1, 'H16: other_user keeps exactly one live token (other-1)');

-- ============================================================================
-- SECTION I — PRIVACY / PAYLOAD MINIMISATION (§8.5, N-P1)
-- ============================================================================
SELECT is((SELECT count(*)::int FROM notify.notification n, jsonb_object_keys(n.params) k WHERE k IN ('email','phone','address','pan','card','password','token','actor_identity','prior_owner','from_identity','recipients','recipient_list')), 0,
  'I1: no notification params key names a contact detail, credential, prior owner or recipient list');
SELECT is((SELECT count(*)::int FROM notify.notification n, jsonb_each_text(n.params) e WHERE e.value ~ '@' OR e.value ~ '^\+?[0-9]{10,}$'), 0, 'I2: no params value looks like an email or a phone number');
SELECT is((SELECT count(*)::int FROM notify.delivery d JOIN notify.notification n ON n.notification_id = d.notification_id JOIN notify.notification_type t ON t.type_key = n.type_key
            WHERE d.channel='push' AND t.target_kind IN ('payout','refund','order','ticket') AND d.rendered_body ~ '(Finn Ledger|Jordy|USD|\$)'), 0,
  'I3 (N-P1): no money/custody push copy carries a counterparty name or an amount');
SELECT is((SELECT count(*)::int FROM notify.outbox o WHERE o.payload::text ~ '@' ), 0, 'I4: no envelope payload carries an email address');
SELECT is((SELECT count(*)::int FROM notify.notification WHERE link IS NOT NULL OR params::text ~* 'https?://'), 0, 'I5 (§4.4): never a URL in a row — targets are kinds');
SELECT is(notify.resolve_web_link('payout', NULL), '/account/sales', 'I6: web link composition maps a target kind onto an existing route (E-156)');
SELECT is(notify.resolve_web_link('no_such_kind', NULL), NULL, 'I7: outside the closed set → NULL');

-- ============================================================================
-- SECTION J — THE DELETION LIFECYCLE (DSM §3.1.4 / §4.7; OR-13 boundaries)
-- ============================================================================
SELECT tap.login(tap.fan157());
SELECT lives_ok($$SELECT kernel.request_account_deletion('ck92-del-1')$$, 'J1: fan157 requests deletion (077 producer)');
SELECT tap.logout();
SELECT is(tap._obcount157('account_deletion_pending', 'pending'), 1, 'J2: exactly one pending envelope from the real producer (BE class)');
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '1', 'J3: → one notice to self');
SELECT is(tap._n157(tap.fan157(), 'account_deletion_pending'), 1, 'J4: the row exists for the deleting identity only');
SELECT is((tap._d157((tap._nrow157(tap.fan157(),'account_deletion_pending')).notification_id,'email')).suppress_reason, 'channel_unavailable', 'J5: E suppressed (N1); push row pending');
SELECT is((SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys((tap._nrow157(tap.fan157(),'account_deletion_pending')).params) k), 'deletion_requested_at', 'J6 (frozen payload): only the timestamp travels');
SELECT tap.login(tap.fan157());
SELECT lives_ok($$SELECT kernel.withdraw_account_deletion('ck92-wd-1')$$, 'J7: withdraw');
SELECT lives_ok($$SELECT kernel.request_account_deletion('ck92-del-2')$$, 'J8: re-request');
SELECT tap.logout();
SELECT is(tap._obcount157('account_deletion_pending', NULL), 2, 'J9: the re-request''s key carries the NEW deletion_requested_at — inside one transaction it equals the first (same now()), so hop-2 dedupes it: two requests in one instant are one envelope, never a duplicate notice');
SELECT is((notify.drain_outbox(50) ->> 'resolved') || '/' || tap._n157(tap.fan157(), 'account_deletion_pending')::text, '0/1', 'J10: …and no second notice is written (replay-safe at both hops)');
UPDATE kernel.identity_ext SET deletion_requested_at = now() - interval '400 days' WHERE identity_id = tap.fan157();
SELECT lives_ok($$SELECT kernel.sweep_deletion_pending(10)$$, 'J11: the terminal sweep runs');
SELECT is((SELECT deletion_state FROM kernel.identity_ext WHERE identity_id = tap.fan157()), 'ERASED', 'J12: fan157 is ERASED (nothing held, no blocker)');
SELECT is(tap._obcount157('account_deletion_completed', NULL), 1, 'J13: the terminal envelope is emitted ONCE, by the sweep, after the committed state (never before)');
SELECT is((notify.drain_outbox(50) ->> 'resolved'), '1', 'J14: → the completion notice');
SELECT is(tap._dcount157((tap._nrow157(tap.fan157(),'account_deletion_completed')).notification_id), 1, 'J15: E-only — exactly one delivery row');
SELECT is((tap._d157((tap._nrow157(tap.fan157(),'account_deletion_completed')).notification_id,'email')).suppress_reason, 'channel_unavailable', 'J16: …the email row, suppressed until N1; no push row for an account that cannot sign in');
SELECT is((SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys((tap._nrow157(tap.fan157(),'account_deletion_completed')).params) k), 'deletion_requested_at', 'J17 (no rehydration): the tombstone notice carries only the timestamp');
SELECT lives_ok($$SELECT kernel.sweep_deletion_pending(10)$$, 'J18: the sweep re-runs');
SELECT is(tap._obcount157('account_deletion_completed', NULL) || '/' || tap._n157(tap.fan157(), 'account_deletion_completed')::text, '1/1', 'J19: replay writes neither a second envelope nor a second notice');
SELECT tap._store157('n_post', notify.enqueue(tap.fan157(), 'security_password_changed', 'identity', tap.fan157(), '{}', 'k-post-erase')::text);
SELECT is((tap._d157(tap._u157('n_post'),'push')).suppress_reason, 'identity_erased', 'J20: after erasure, push is suppressed identity_erased — retries never mutate deletion state');
SELECT is((SELECT deletion_state FROM kernel.identity_ext WHERE identity_id = tap.fan157()), 'ERASED', 'J21: …state untouched by the notification plane');
SELECT is((SELECT count(*)::int FROM notify.notification WHERE recipient_id = tap.fan157() AND (title IS NOT NULL OR params::text ~* 'permanently')), 0, 'J22: no invented retention or "permanently deleted" language on any row');

-- ============================================================================
-- SECTION K — DARK RAIL / PARKED SURFACES (nothing activated)
-- ============================================================================
SELECT is((SELECT c.value #>> '{}' FROM catalog.platform_config c WHERE c.key='notify.announcements_enabled' ORDER BY c.version DESC LIMIT 1), 'false', 'K1: announcements stay off (OR-5 [C]; no announcement object exists)');
SELECT is((SELECT count(*)::int FROM pg_proc WHERE pronamespace='notify'::regnamespace AND proname ~ 'announcement|sweep_scheduled|schedule'), 0, 'K2: no announcement / schedule routine');
SELECT is((SELECT count(*)::int FROM notify.template WHERE channel NOT IN ('in_app','push')), 0, 'K3: no SMS, no email copy — no channel invented');
SELECT is((SELECT count(*)::int FROM kernel.payout WHERE hold_state <> 'held'), 0, 'K4: no held payout was released by anything in this package');
SELECT is((SELECT count(*)::int FROM notify.delivery WHERE channel='email' AND state <> 'suppressed'), 0, 'K5: no email delivery ever leaves suppressed (N1 owner gate intact)');

SELECT * FROM finish();
ROLLBACK;
