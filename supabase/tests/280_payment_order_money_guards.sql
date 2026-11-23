-- 212: behavior probe, also runs to completion against the pre-212 bodies.
BEGIN;
SELECT plan(17);
SELECT tap.seed_core();
INSERT INTO public.admin_users(user_id,label) VALUES(tap.other_user(),'280 second founder') ON CONFLICT DO NOTHING;
UPDATE ops.setting SET value='true'::jsonb WHERE key='refund_execute_enabled';
CREATE TEMP TABLE money280(k text primary key,v jsonb);
GRANT ALL ON money280 TO authenticated,service_role;
CREATE FUNCTION tap.login280() RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  PERFORM tap.login(tap.admin_user());
  PERFORM set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb || '{"aal":"aal2"}'::jsonb)::text,true);
END $$;
SELECT tap.login280();
INSERT INTO money280 VALUES ('first',ops.execute_action('test280-refund-first','refund_execute','payment',tap.payment_b(),'{}','reviewed refund'));
SELECT is((SELECT v->>'status' FROM money280 WHERE k='first'),'awaiting_approval','first refund awaits human approval');
INSERT INTO money280 VALUES ('second',ops.execute_action('test280-refund-second','refund_execute','payment',tap.payment_b(),'{}','reviewed refund'));
SELECT is((SELECT v->>'reject_reason' FROM money280 WHERE k='second'),'duplicate_unsettled','same-payment refund duplicates are refused');
INSERT INTO money280 VALUES ('cross',ops.execute_action('test280-payout-cross','payout_release','transfer',tap.transfer_b(),'{}','reviewed payout'));
SELECT is((SELECT v->>'reject_reason' FROM money280 WHERE k='cross'),'duplicate_unsettled','opposite console money direction is refused first');
SELECT is(ops.execute_action('test280-refund-first','refund_execute','payment',tap.payment_b(),'{}','reviewed refund')->>'status','idempotent_replay','existing key retains replay precedence');
SELECT tap.logout();
UPDATE public.payments SET stripe_livemode=true WHERE id=tap.payment_b();
UPDATE public.profiles SET stripe_connect_id='acct_fixture' WHERE id=tap.seller();
SELECT is(public.apply_auto_release(tap.transfer_b()),true,'fixture release decision made by existing writer');
SELECT throws_ok($$SELECT * FROM public.claim_payout_attempt(tap.transfer_b(),'test280')$$,'P0001','REFUND_IN_FLIGHT','fresh payout blocked by unsettled manual refund');
SELECT is((SELECT count(*) FROM public.payout_attempts WHERE transfer_id=tap.transfer_b()),0::bigint,'blocked payout writes no attempt');
-- Refund duplicate precedes the now-released payout guard.
SELECT tap.login280();
INSERT INTO money280 VALUES ('precedence',ops.execute_action('test280-refund-priority','refund_execute','payment',tap.payment_b(),'{}','reviewed refund'));
SELECT is((SELECT v->>'reject_reason' FROM money280 WHERE k='precedence'),'duplicate_unsettled','duplicate_unsettled wins over released-payout refusal');
SELECT tap.logout();
-- Release landed between request and approval: dispatch rechecks under the same key.
SELECT tap.login(tap.other_user());
SELECT set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb || '{"aal":"aal2"}')::text,true);
INSERT INTO money280 VALUES ('approval',ops.approve_action((SELECT (v->>'action_id')::uuid FROM money280 WHERE k='first'),'approve','reviewed local fixture'));
SELECT is((SELECT v->>'status' FROM money280 WHERE k='approval'),'processing','eligible unpaid release decision permits approved refund handoff');
SELECT tap.logout();
UPDATE ops.action SET state='failed' WHERE idempotency_key LIKE 'test280-%';
SELECT tap.login280();
INSERT INTO money280 VALUES ('released',ops.execute_action('test280-refund-released','refund_execute','payment',tap.payment_b(),'{}','reviewed refund'));
SELECT is((SELECT v->>'status' FROM money280 WHERE k='released'),'awaiting_approval','eligible but unpaid transfer permits reviewed refund request');
SELECT tap.login(tap.other_user());
SELECT set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb || '{"aal":"aal2"}'::jsonb)::text,true);
SELECT ops.approve_action((SELECT (v->>'action_id')::uuid FROM money280 WHERE k='released'),'deny','fixture cleanup after positive unpaid control');
SELECT tap.logout();
-- Red-control cleanup: the predecessor may have allocated the refused attempt.
SELECT public.record_payout_attempt_result(id,NULL,'failed_not_created','{}') FROM public.payout_attempts WHERE transfer_id=tap.transfer_b() AND state IN ('claimed','requested','unknown');
CREATE TEMP TABLE attempt280 AS SELECT * FROM public.claim_payout_attempt(tap.transfer_b(),'test280');
CREATE TEMP TABLE count280 AS SELECT count(*) AS n FROM public.payout_attempts WHERE transfer_id=tap.transfer_b();
SELECT is((SELECT needs_reconcile FROM attempt280),false,'terminal failed refund does not block fresh payout');
-- A refund created before installation / by privileged DML must not strand an existing payout.
INSERT INTO ops.action(idempotency_key,action_type,subject_kind,subject_id,requested_by,state)
VALUES ('test280-historical','refund_execute','payment',tap.payment_b(),tap.admin_user(),'unknown');
UPDATE public.payout_attempts SET lease_expires_at=now()-interval '1 minute' WHERE id=(SELECT attempt_id FROM attempt280);
SELECT is((SELECT needs_reconcile FROM public.claim_payout_attempt(tap.transfer_b(),'cron:enforce-transfer-expiry')),true,'open payout reconciliation wins over refund guard');
SELECT is((SELECT count(*) FROM public.payout_attempts WHERE transfer_id=tap.transfer_b()),(SELECT n FROM count280),'reconciliation creates no second payout');
SELECT is(public.record_payout_attempt_result((SELECT attempt_id FROM attempt280),NULL,'failed_not_created','{}')->>'state','failed','confirmed failed-not-created payout remains terminal');
SELECT throws_ok($$SELECT * FROM public.claim_payout_attempt(tap.transfer_b(),'test280')$$,'P0001','REFUND_IN_FLIGHT','after failed payout, unsettled refund blocks next attempt');
-- Historical pre-212 processing row: approval terms still match, no provider POST sent.
UPDATE ops.action SET state='processing', attempt=0, claimed_until=NULL, result='{}'::jsonb
 WHERE id=(SELECT (v->>'action_id')::uuid FROM money280 WHERE k='first');
UPDATE ops.action SET state='failed' WHERE idempotency_key='test280-historical';
SELECT tap.login_service();
SELECT is(ops.executor_claim((SELECT (v->>'action_id')::uuid FROM money280 WHERE k='first'))->>'status','claimed','eligible unpaid transfer permits fresh approved refund executor claim');
SELECT tap.logout();
SELECT throws_ok($$SELECT * FROM public.claim_payout_attempt(tap.transfer_b(),'test280-after-refund')$$,'P0001','REFUND_IN_FLIGHT','approved fresh refund claim fences a later payout');
SELECT tap.logout();
SELECT * FROM finish();
ROLLBACK;
