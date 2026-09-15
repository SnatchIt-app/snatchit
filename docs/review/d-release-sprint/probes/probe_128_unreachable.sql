-- D-R128-P1 (independent probe, local rehearsal DB only, BEGIN…ROLLBACK).
-- Question: after a provider "device not registered" signal, does re-registering through
-- 128's public.register_push_token heal the identity's push channel (§17.24), as the
-- legacy notify.register_push_token did? Every state is produced by the real writers.
-- :verb = 'new' (128 client verb) or 'legacy' (negative control: the verb 128 revokes).
\set ON_ERROR_STOP 1
BEGIN;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ('d1280000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'd128probe@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now());

CREATE TEMP TABLE probe_out (step int, k text, v text) ON COMMIT DROP;
GRANT ALL ON probe_out TO authenticated;

-- 1. The device registers through the client verb.
SELECT tap.login('d1280000-0000-4000-8000-000000000001');
INSERT INTO probe_out SELECT 1, 'register', public.register_push_token('ExponentPushToken[d128-probe]', 'ios', 'probe-secret-0123456789', 'iPhone')::text;
SELECT tap.logout();

-- 2. A mandatory push is enqueued (service path) and the provider reports DeviceNotRegistered.
SELECT notify.enqueue('d1280000-0000-4000-8000-000000000001', 'ticket_ready', 'order',
                      'd1280000-0000-4000-8000-0000000000a1', '{}', 'd128-probe-n1') AS n1 \gset
INSERT INTO probe_out SELECT 2, 'delivery_state_before', d.state
  FROM notify.delivery d WHERE d.notification_id = :'n1' AND d.channel = 'push';
INSERT INTO probe_out SELECT 2, 'record_result', notify.record_delivery_result(
    (SELECT d.delivery_id FROM notify.delivery d JOIN notify.notification n USING (notification_id)
      WHERE n.dedupe_key = 'd128-probe-n1' AND d.channel = 'push'),
    'device_not_registered', NULL, NULL, NULL, 'DeviceNotRegistered', 'ExponentPushToken[d128-probe]')::text;
INSERT INTO probe_out SELECT 2, 'channel_state_after_dnr', s.state FROM notify.identity_channel_state s
 WHERE s.identity_id = 'd1280000-0000-4000-8000-000000000001' AND s.channel = 'push';

-- 3. The same device re-registers.
SELECT tap.login('d1280000-0000-4000-8000-000000000001');
SELECT CASE WHEN :'verb' = 'new' THEN
         (SELECT public.register_push_token('ExponentPushToken[d128-probe]', 'ios', 'probe-secret-0123456789', 'iPhone')::text)
       ELSE '' END AS new_verb \gset
SELECT tap.logout();
-- negative control runs the revoked legacy verb on the trusted path with the same auth.uid()
SELECT tap.set_claims('d1280000-0000-4000-8000-000000000001', 'authenticated');
SELECT CASE WHEN :'verb' = 'legacy' THEN
         (SELECT notify.register_push_token('ExponentPushToken[d128-probe]', 'ios', 'iPhone', NULL)::text)
       ELSE '' END AS legacy_verb \gset
SELECT tap.logout();
INSERT INTO probe_out VALUES (3, 'reregister', coalesce(:'new_verb', '') || coalesce(:'legacy_verb', ''));

INSERT INTO probe_out SELECT 4, 'token_active_revoked_error', concat_ws('|', pt.is_active, pt.revoked_at IS NULL, coalesce(pt.last_provider_error, '<null>'))
  FROM public.push_tokens pt WHERE pt.token = 'ExponentPushToken[d128-probe]';
INSERT INTO probe_out SELECT 4, 'channel_state_after_reregister', s.state FROM notify.identity_channel_state s
 WHERE s.identity_id = 'd1280000-0000-4000-8000-000000000001' AND s.channel = 'push';

-- 5. Consequence: the next mandatory push.
SELECT notify.enqueue('d1280000-0000-4000-8000-000000000001', 'ticket_ready', 'order',
                      'd1280000-0000-4000-8000-0000000000a2', '{}', 'd128-probe-n2') AS n2 \gset
INSERT INTO probe_out SELECT 5, 'next_mandatory_push', concat_ws('|', d.state, coalesce(d.suppress_reason, '<null>'))
  FROM notify.delivery d WHERE d.notification_id = :'n2' AND d.channel = 'push';

SELECT step, k, v FROM probe_out ORDER BY step, k;
ROLLBACK;
