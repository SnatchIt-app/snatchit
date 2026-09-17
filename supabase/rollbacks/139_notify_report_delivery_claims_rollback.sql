-- Rollback for 139_notify_report_delivery_claims.sql
--
-- ROLL THE EDGE BACK FIRST. notify-report calls notify.claim_report_delivery;
-- with the function gone the call errors, and the edge treats a claim failure as
-- "send" (it fails toward delivering), so the only consequence of the wrong order
-- is duplicate notifications — never a silent one. Still: edge first.
--
-- Restores the census exactly: notify tables 9 → 8, notify routines 22 → 20,
-- five-schema relations 81 → 80, routines 305 → 303.
begin;

drop function if exists notify.release_report_delivery(text, text);
drop function if exists notify.claim_report_delivery(text, text);
drop table if exists notify.report_delivery_claim;

commit;
