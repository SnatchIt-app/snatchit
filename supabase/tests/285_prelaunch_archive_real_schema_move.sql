-- Real Supabase tables/triggers/roles; all synthetic data and function configuration roll back.
-- The ONLY production-code substitution is the approved-ID digest for this synthetic manifest.
BEGIN;
SELECT plan(18);
SELECT tap.seed_core();
DELETE FROM public.transfers WHERE id IN(tap.transfer_a(),tap.transfer_b());
INSERT INTO public.payments(id,listing_id,buyer_id,seller_id,amount,buyer_fee,seller_fee,total,mode,status,created_at,failed_at,stripe_livemode)
SELECT ('28500000-0000-4000-8000-'||lpad(g::text,12,'0'))::uuid,tap.listing_a(),tap.buyer(),tap.seller(),100,10,10,110,'buy_now','failed','2026-01-01','2026-01-01',false
FROM generate_series(1,57-(SELECT count(*)::int FROM public.payments)) g;
UPDATE public.payments SET created_at='2026-01-01';
CREATE TEMP TABLE archive285 AS SELECT array_agg(id ORDER BY id) ids FROM public.payments;
ALTER TABLE archive285 ADD COLUMN batch uuid,ADD COLUMN digest text,ADD COLUMN receipt jsonb,ADD COLUMN keep_before jsonb;
GRANT ALL ON archive285 TO authenticated;
INSERT INTO public.payments(id,listing_id,buyer_id,seller_id,amount,buyer_fee,seller_fee,total,mode,status,created_at,paid_at,stripe_livemode)
VALUES('d0508a55-84de-40d8-b696-9e0ea4396bb3',tap.listing_d(),tap.buyer(),tap.seller(),200,20,20,220,'buy_now','succeeded','2026-11-03T21:26:45.213Z','2026-11-03T21:27:22Z',false),
('d44d0d3d-90e0-4e3b-a6bd-2769275ec741',null,tap.buyer(),null,100,10,0,110,'native_primary','succeeded','2026-11-25','2026-11-25',false);
INSERT INTO public.transfers(id,listing_id,payment_id,seller_id,buyer_id,transfer_method,status,payout_released_at,stripe_transfer_id)
VALUES('abd8257e-07ee-4718-99d0-d9c8e6dc5c1e',tap.listing_d(),'d0508a55-84de-40d8-b696-9e0ea4396bb3',tap.seller(),tap.buyer(),'mobile_transfer','auto_released',null,null),
(tap.transfer_b(),tap.listing_b(),tap.payment_b(),tap.seller(),tap.buyer(),'mobile_transfer','buyer_confirmed',now(),'tr_fixture_285');
-- Snapshot protected money facts before any cleanup. The native fixture deliberately has
-- no issuance link, so it remains an actionable native settlement failure after the move.
UPDATE archive285 SET keep_before=(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.payments p WHERE p.id NOT IN(SELECT unnest(ids) FROM archive285));
SELECT ops.detect_case('refund_pending','payment',tap.payment_b(),null,'Fixture refund test','Pre-launch synthetic case','p1',null,'refunds');
SELECT ops.detect_case('dispute_open','transfer',tap.transfer_b(),null,'Fixture dispute test','Pre-launch synthetic case','p1',null,'disputes');
SELECT ops.detect_case('release_stuck','transfer','abd8257e-07ee-4718-99d0-d9c8e6dc5c1e',null,'Protected unpaid seller','Do not remove this obligation','p1',null,'release_stuck');
INSERT INTO public.webhook_retries(payment_id,listing_id,rpc_name,error_message) VALUES(tap.payment_b(),tap.listing_b(),'fixture_only','pre-launch test retry');
DO $fixture$
DECLARE d text; old_digest text; def text;
BEGIN
 SELECT encode(sha256(convert_to(string_agg(x::text,',' ORDER BY x),'UTF8')),'hex') INTO d FROM unnest((SELECT ids FROM archive285)) x;
 SELECT pg_get_functiondef('ops.prelaunch_archive_assert_manifest(uuid[])'::regprocedure) INTO def;
 old_digest:=substring(def FROM $regex$v_digest is distinct from '([0-9a-f]{64})'$regex$);
 IF old_digest IS NULL OR length(old_digest)<>64 THEN RAISE EXCEPTION 'fixture digest substitution failed'; END IF;
 EXECUTE replace(def,old_digest,d);
END $fixture$;
SELECT is((SELECT count(*)::int FROM public.payments),59,'fixture has the exact reviewed inventory size');
UPDATE archive285 SET batch=ops.prelaunch_archive_prepare(ids);
UPDATE archive285 SET digest=(SELECT snapshot_sha256 FROM ops.prelaunch_archive_batch);
SELECT ok((SELECT snapshot_sha256=encode(sha256(convert_to(snapshot::text,'UTF8')),'hex') FROM ops.prelaunch_archive_batch),'full real-schema snapshot content hash matches');
SELECT is((SELECT jsonb_array_length(snapshot->'public.payments') FROM ops.prelaunch_archive_batch),57,'private snapshot holds all 57 reviewed synthetic payments');
SELECT tap.login(tap.admin_user());
SELECT set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb || '{"aal":"aal2"}'::jsonb)::text,true);
SELECT throws_ok($$SELECT ops.prelaunch_archive_execute(batch,digest,'Owner approved synthetic archive rehearsal','ARCHIVE 57 TEST ORDERS') FROM archive285$$,'P0001','archive_refused: expired batch or unverified backup','real-role executor refuses until backup is verified');
SELECT tap.logout();
UPDATE ops.prelaunch_archive_batch SET backup_sha256=snapshot_sha256;
SELECT tap.login(tap.admin_user());
SELECT set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb || '{"aal":"aal2"}'::jsonb)::text,true);
UPDATE archive285 SET receipt=ops.prelaunch_archive_execute(batch,digest,'Owner approved synthetic archive rehearsal','ARCHIVE 57 TEST ORDERS');
SELECT is((SELECT receipt->>'status' FROM archive285),'archived','real platform-admin/MFA session completes the reviewed move');
SELECT is(ops.prelaunch_archive_read()->>'state','archived','admin history reader reports the completed archive');
SELECT is(jsonb_array_length(ops.prelaunch_archive_read()->'payments'),57,'limited history retains all 57 records');
SELECT ok(NOT(ops.prelaunch_archive_read() ? 'snapshot'),'history reader does not expose the private full-row payload');
SELECT is((SELECT ops.prelaunch_archive_execute(batch,digest,'Owner approved synthetic archive rehearsal','ARCHIVE 57 TEST ORDERS') FROM archive285),(SELECT receipt FROM archive285),'repeat returns the same exact receipt');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.payments),2,'active payment table contains only the two protected purchases');
SELECT is((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.payments p),(SELECT keep_before FROM archive285),'both protected payment records remain byte-equivalent JSON');
SELECT ok(EXISTS(SELECT FROM public.transfers WHERE id='abd8257e-07ee-4718-99d0-d9c8e6dc5c1e' AND payment_id='d0508a55-84de-40d8-b696-9e0ea4396bb3' AND payout_released_at IS NULL AND stripe_transfer_id IS NULL),'real unpaid seller obligation stays active and unpaid');
SELECT is((SELECT count(*)::int FROM public.webhook_retries WHERE payment_id=ANY((SELECT ids FROM archive285)::uuid[])),0,'archived test retries leave active processing');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE subject_id=ANY((SELECT ids FROM archive285)::uuid[]) OR subject_id=tap.transfer_b()),0,'test cases leave active queues');
SELECT is((SELECT count(*)::int FROM ops.alert WHERE alert_key IN('case:refund_pending:'||tap.payment_b()::text,'case:dispute_open:'||tap.transfer_b()::text)),0,'old refund/dispute alerts leave active operations immediately');
SELECT ok(EXISTS(SELECT FROM ops.alert WHERE alert_key='case:release_stuck:abd8257e-07ee-4718-99d0-d9c8e6dc5c1e' AND state='firing'),'unrelated real alert remains firing');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action='prelaunch_tests.archived'),1,'exactly one archive audit entry survives replay');
SELECT is((SELECT count(*)::int FROM pg_trigger WHERE tgname IN('tg_case_note_append_only','tg_case_event_append_only','trg_payment_refunds_append_only','trg_payment_refund_state_log_append_only') AND tgenabled='O'),4,'all four deletion guards are enabled after the real-schema move');
SELECT * FROM finish();
ROLLBACK;
