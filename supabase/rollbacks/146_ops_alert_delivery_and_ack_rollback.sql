-- ROLLBACK for 146_ops_alert_delivery_and_ack.sql.
--
-- Restores 117's ops.alert_fire, drops ops.dispatch_alerts, ops.alert_ack, ops.alert_post and ops.alert_response,
-- deletes the alert_delivery_enabled setting row and drops the nine columns 146 added to ops.alert. The alert ROWS
-- are untouched: firing stays firing, recovered stays recovered, and every detector behaves exactly as before,
-- because after alert_fire is restored nothing else reads these columns.
--
-- ORDER MATTERS. ops.alert_fire must be put back to 117's body BEFORE the columns are dropped: 146's version writes
-- incident_seq and clears the delivery columns on a recurrence, so dropping them under it would leave a function
-- that fails on the next detector tick. Both happen in this one transaction, so there is no window where either is
-- true on its own.
--
-- What IS discarded, said plainly: the delivery bookkeeping — which alerts had been queued, which were confirmed
-- delivered, what the last error was, and who acknowledged what. That is the record of who was told, so run this only
-- if that record is not wanted. It cannot be reconstructed afterwards. If an operator's acknowledgements matter, copy
-- them out first (ops.audit keeps the 'alert.acknowledged' rows, which this rollback does not touch). The incident
-- counter goes with them: after this, an alert that recovers and fires again is once more indistinguishable from
-- one that never stopped firing.
begin;
set local lock_timeout = '3s';

-- 117's ops.alert_fire, restored verbatim: one row per alert key, no incident concept, nothing reset on a re-fire.
create or replace function ops.alert_fire(p_key text, p_kind text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare v_state text;
begin
  select state into v_state from ops.alert where alert_key = p_key for update;
  if not found then
    insert into ops.alert (alert_key, kind, state, payload)
    values (p_key, p_kind, 'firing', coalesce(p_payload, '{}'::jsonb));
    return jsonb_build_object('alert_key', p_key, 'fired', true, 'was', null);
  end if;
  update ops.alert
     set state = 'firing',
         kind = p_kind,
         payload = coalesce(p_payload, payload),
         last_fired_at = now(),
         fire_count = fire_count + 1,
         first_fired_at = case when v_state = 'recovered' then now() else first_fired_at end,
         recovered_at = null
   where alert_key = p_key;
  return jsonb_build_object('alert_key', p_key, 'fired', v_state = 'recovered', 'was', v_state);
end;
$ops$;
revoke all on function ops.alert_fire(text,text,jsonb) from public, anon, authenticated, service_role;

drop function if exists ops.dispatch_alerts(integer);
drop function if exists ops.alert_ack(text,text);
drop function if exists ops.alert_post(jsonb);
drop function if exists ops.alert_response(bigint);
delete from ops.setting where key = 'alert_delivery_enabled';

alter table ops.alert
  drop column if exists queued_at,
  drop column if exists notify_request_id,
  drop column if exists delivered_at,
  drop column if exists delivery_status,
  drop column if exists notify_attempts,
  drop column if exists last_notify_error,
  drop column if exists acknowledged_at,
  drop column if exists acknowledged_by,
  drop column if exists incident_seq;

commit;
