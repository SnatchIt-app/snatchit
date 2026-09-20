-- ============================================================================
-- 213_ops_alert_delivery_and_ack.sql — migration 146: an alert can be sent, confirmed and acknowledged.
--   Section O: the switch — seeded false, and nothing is posted or changed while it is off.
--   Section Q: queuing is not delivery — a queued post sets queued_at and a request id and NOT delivered_at; a 2xx
--     recorded against that id confirms it; a 401 does not, and makes the alert eligible again; an unanswered
--     request goes stale; the attempt cap stops a broken endpoint looping.
--   Section L: the outbound body carries an allow-list only — an alert payload holding an email and a phone posts
--     neither (the one that matters: ops.alert.payload is free-form).
--   Section A: acknowledgement — an operator records that a person saw it, it is audited, it does not recover the
--     alert, a non-operator is refused, and a recovered alert cannot be acknowledged.
-- net.http_post is replaced inside this transaction by a recorder, and net._http_response is created here: the local
-- shim has neither a response table nor a real sender, and nothing may leave the database from a test.
-- ============================================================================
BEGIN;
SELECT plan(25);
SELECT tap.seed_core();

CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- the recorder: every post lands in tap.posted instead of going anywhere
CREATE TABLE tap.posted (id bigserial primary key, url text, headers jsonb, body jsonb);
CREATE TABLE tap.net_fail (on_off boolean);
CREATE OR REPLACE FUNCTION net.http_post(url text, headers jsonb DEFAULT '{}'::jsonb, body jsonb DEFAULT '{}'::jsonb)
RETURNS bigint LANGUAGE plpgsql AS $f$
declare v_id bigint;
begin
  if exists (select 1 from tap.net_fail where on_off) then
    raise exception 'connection refused by the test';
  end if;
  insert into tap.posted (url, headers, body) values (url, headers, body) returning id into v_id;
  return v_id;
end $f$;
CREATE TABLE net._http_response (id bigint primary key, status_code integer, content text);
INSERT INTO vault.decrypted_secrets (name, decrypted_secret) VALUES ('project_url', 'https://example.test')
  ON CONFLICT DO NOTHING;

CREATE FUNCTION tap._fire(p_key text, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS void LANGUAGE sql AS $f$
  insert into ops.alert (alert_key, kind, state, payload, first_fired_at, last_fired_at)
  values (p_key, 'p1_case', 'firing', p_payload, now() - interval '5 minutes', now())
  on conflict (alert_key) do update set state = 'firing', payload = excluded.payload $f$;
CREATE FUNCTION tap._a(p_key text) RETURNS ops.alert LANGUAGE sql AS $f$ select * from ops.alert where alert_key = p_key $f$;
-- dispatch_alerts is owner-only EXECUTE: nothing calls it today, and a future scheduled job would run as the job's
-- owner (postgres). So the test calls it as postgres, which is what that caller will be.
CREATE FUNCTION tap._dispatch(p_limit integer DEFAULT 20) RETURNS jsonb LANGUAGE sql AS $f$
  select ops.dispatch_alerts(p_limit) $f$;

-- ── Section O — the switch ──────────────────────────────────────────────────
SELECT is((SELECT value FROM ops.setting WHERE key = 'alert_delivery_enabled'), 'false'::jsonb,
  'O1: delivery is seeded OFF (a boolean, so an audited setting_set can flip it)');
SELECT tap._fire('t213:off');
SELECT is(tap._dispatch() ->> 'skipped', 'alert_delivery_disabled',
  'O2: while off, dispatch does nothing and says why');
SELECT ok((SELECT count(*)::int FROM tap.posted) = 0 AND (tap._a('t213:off')).queued_at IS NULL
          AND (tap._a('t213:off')).notify_attempts = 0,
  'O3: …nothing was posted and the alert is untouched');
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'alert_delivery_enabled';

-- ── Section Q — queued is not delivered ─────────────────────────────────────
SELECT ok((SELECT r ->> 'queued' = '1' AND r ->> 'confirmed' = '0' FROM (SELECT tap._dispatch() AS r) x),
  'Q1: with the switch on, one eligible alert is QUEUED, and nothing is confirmed');
SELECT ok((tap._a('t213:off')).queued_at IS NOT NULL AND (tap._a('t213:off')).notify_request_id IS NOT NULL
          AND (tap._a('t213:off')).delivered_at IS NULL AND (tap._a('t213:off')).notify_attempts = 1,
  'Q2: the row says queued with a request id, and delivered_at stays NULL — a queue is not a delivery');
SELECT is((SELECT count(*)::int FROM tap.posted), 1, 'Q3: exactly one post, to the recorder');
SELECT ok((SELECT body ->> 'event' = 'ops_alert' AND url LIKE 'https://example.test/functions/v1/notify-report'
             FROM tap.posted ORDER BY id DESC LIMIT 1),
  'Q4: it is the new ops_alert event, posted to notify-report');
SELECT is(tap._dispatch() ->> 'queued', '0', 'Q5: a second call does not re-queue what is already in flight');
-- confirmation needs the edge's own accounting, not just a status
INSERT INTO net._http_response (id, status_code, content)
  SELECT (tap._a('t213:off')).notify_request_id, 200, '{"ok":true,"event":"ops_alert","attempted":2,"delivered":2}';
SELECT ok((SELECT r ->> 'confirmed' = '1' FROM (SELECT tap._dispatch() AS r) x)
          AND (tap._a('t213:off')).delivered_at IS NOT NULL AND (tap._a('t213:off')).delivery_status = 200,
  'Q6: a 2xx recorded against the request id is what sets delivered_at');
SELECT is(tap._dispatch() ->> 'queued', '0', 'Q7: a delivered alert is never posted again');

-- notify-report answers 200 for an event it does not know — which is exactly what happens before the ops_alert
-- branch is deployed. A status alone would call that delivered.
SELECT tap._fire('t213:200nodeliver');
SELECT tap._dispatch();
INSERT INTO net._http_response (id, status_code, content)
  SELECT (tap._a('t213:200nodeliver')).notify_request_id, 200, '{"ok":true,"event":"ops_alert"}';
UPDATE ops.alert SET notify_attempts = 5 WHERE alert_key = 't213:200nodeliver';
SELECT ok((tap._dispatch() ->> 'failed')::int >= 1
          AND (tap._a('t213:200nodeliver')).delivered_at IS NULL
          AND (tap._a('t213:200nodeliver')).last_notify_error LIKE '%reported no delivery%',
  'Q7b: a 200 with no delivery count is NOT a delivery — the pre-deploy answer cannot masquerade as one');

-- a 401 is a perfectly successful QUEUE and must not count as delivery
SELECT tap._fire('t213:401');
SELECT tap._dispatch();
INSERT INTO net._http_response (id, status_code) SELECT (tap._a('t213:401')).notify_request_id, 401;
-- hold it at the cap so this call only reconciles: otherwise the same call re-posts and overwrites what is asserted
UPDATE ops.alert SET notify_attempts = 5 WHERE alert_key = 't213:401';
SELECT ok((SELECT r ->> 'failed' = '1' FROM (SELECT tap._dispatch() AS r) x)
          AND (tap._a('t213:401')).delivered_at IS NULL AND (tap._a('t213:401')).delivery_status = 401
          AND (tap._a('t213:401')).last_notify_error LIKE 'HTTP 401%',
  'Q8: a 401 leaves the alert undelivered, with the status recorded — the failure that used to look like success');
SELECT ok((tap._a('t213:401')).notify_request_id IS NULL AND (tap._a('t213:401')).queued_at IS NULL,
  'Q9: …and it is eligible again rather than stuck in flight');

-- an unanswered request goes stale and becomes eligible again
SELECT tap._fire('t213:stale');
SELECT tap._dispatch();
UPDATE ops.alert SET queued_at = now() - interval '20 minutes', notify_attempts = 5 WHERE alert_key = 't213:stale';
SELECT ok((SELECT r ->> 'failed' = '1' FROM (SELECT tap._dispatch() AS r) x)
          AND (tap._a('t213:stale')).notify_request_id IS NULL
          AND (tap._a('t213:stale')).last_notify_error LIKE 'no response recorded%',
  'Q10: a request with no response after 15 minutes is unconfirmed, not delivered');

-- the attempt cap
SELECT tap._fire('t213:cap');
UPDATE ops.alert SET notify_attempts = 5 WHERE alert_key = 't213:cap';
SELECT ok((SELECT (r ->> 'given_up')::int >= 1 FROM (SELECT tap._dispatch() AS r) x)
          AND (tap._a('t213:cap')).queued_at IS NULL,
  'Q11: after 5 attempts an alert is skipped and counted — a broken endpoint cannot loop');
-- a sender that raises is recorded, and dispatch still returns
INSERT INTO tap.net_fail VALUES (true);
SELECT tap._fire('t213:raise');
SELECT ok((SELECT r ->> 'failed' = '1' AND r ->> 'queued' = '0' FROM (SELECT tap._dispatch() AS r) x)
          AND (tap._a('t213:raise')).last_notify_error LIKE '%connection refused%'
          AND (tap._a('t213:raise')).delivered_at IS NULL,
  'Q12: a sender that raises is recorded on the row, and dispatch returns rather than failing its caller');
DELETE FROM tap.net_fail;

-- ── Section L — the outbound body carries an allow-list only ────────────────
SELECT tap._fire('t213:leak', jsonb_build_object(
  'case_id', '11111111-2222-3333-4444-555555555555', 'case_type', 'refund_resolution',
  'subject_ref', 'buyer@example.test', 'title', 'Refund for buyer@example.test',
  'buyer_email', 'buyer@example.test', 'buyer_phone', '+13055550001', 'note', 'call +13055550001'));
SELECT tap._dispatch();
SELECT ok((SELECT body::text NOT LIKE '%@example.test%' AND body::text NOT LIKE '%13055550001%'
             FROM tap.posted WHERE body ->> 'alert_key' = 't213:leak' ORDER BY id DESC LIMIT 1),
  'L1: an alert payload holding an email and a phone posts NEITHER — the payload is never passed through');
SELECT ok((SELECT body ->> 'case_id' = '11111111-2222-3333-4444-555555555555' AND body ->> 'case_type' = 'refund_resolution'
             AND (body ? 'fire_count') AND (body ? 'first_fired_at')
             FROM tap.posted WHERE body ->> 'alert_key' = 't213:leak' ORDER BY id DESC LIMIT 1),
  'L2 (witness): the allow-listed fields ARE posted, so L1 is not passing on an empty body');
SELECT ok((SELECT NOT (body ? 'payload') AND NOT (body ? 'subject_ref') AND NOT (body ? 'title')
             FROM tap.posted WHERE body ->> 'alert_key' = 't213:leak' ORDER BY id DESC LIMIT 1),
  'L3: the free-form payload, the subject reference and the title are not in the body at all');

-- ── Section A — acknowledgement ─────────────────────────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT ok((SELECT r ->> 'acknowledged_at' IS NOT NULL AND r ->> 'state' = 'firing'
             FROM (SELECT ops.alert_ack('t213:leak', 'seen in the console') AS r) x),
  'A1: an operator can acknowledge a firing alert, and it stays firing — acknowledging is not fixing');
SELECT tap.logout();
SELECT ok((tap._a('t213:leak')).acknowledged_by = tap.admin_user()
          AND (SELECT count(*)::int FROM ops.audit WHERE action = 'alert.acknowledged' AND subject_ref = 't213:leak') = 1,
  'A2: who acknowledged it is recorded, and an audit row is written');
SELECT is(tap._dispatch() ->> 'queued', '0', 'A3: an acknowledged alert is not posted again');
SELECT tap.login(tap.seller()); SELECT tap._aal2();
SELECT throws_ok($$SELECT ops.alert_ack('t213:401', 'me')$$, '42501',
  NULL, 'A4: a non-operator cannot acknowledge');
SELECT tap.logout();
UPDATE ops.alert SET state = 'recovered', recovered_at = now() WHERE alert_key = 't213:stale';
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT throws_like($$SELECT ops.alert_ack('t213:stale', 'late')$$, '%nothing to acknowledge%',
  'A5: a recovered alert cannot be acknowledged');
SELECT throws_like($$SELECT ops.alert_ack('t213:nope', 'x')$$, '%no alert%',
  'A6: an unknown alert key is refused');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
