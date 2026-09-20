-- ROLLBACK for 146_ops_alert_delivery_and_ack.sql.
--
-- Drops ops.dispatch_alerts and ops.alert_ack, deletes the alert_delivery_enabled setting row and drops the eight
-- columns 146 added to ops.alert. The alert ROWS are untouched: firing stays firing, recovered stays recovered, and
-- every detector behaves exactly as before, because nothing else reads these columns.
--
-- What IS discarded, said plainly: the delivery bookkeeping — which alerts had been queued, which were confirmed
-- delivered, what the last error was, and who acknowledged what. That is the record of who was told, so run this only
-- if that record is not wanted. It cannot be reconstructed afterwards. If an operator's acknowledgements matter, copy
-- them out first (ops.audit keeps the 'alert.acknowledged' rows, which this rollback does not touch).
begin;
set local lock_timeout = '3s';

drop function if exists ops.dispatch_alerts(integer);
drop function if exists ops.alert_ack(text,text);
delete from ops.setting where key = 'alert_delivery_enabled';

alter table ops.alert
  drop column if exists queued_at,
  drop column if exists notify_request_id,
  drop column if exists delivered_at,
  drop column if exists delivery_status,
  drop column if exists notify_attempts,
  drop column if exists last_notify_error,
  drop column if exists acknowledged_at,
  drop column if exists acknowledged_by;

commit;
