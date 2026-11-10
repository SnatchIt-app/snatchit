-- Close the pilot with issuance off and checkout writers drained before rollback.
begin;
set local lock_timeout = '3s';
lock table venue."order", venue.inventory_hold, venue.primary_checkout_pilot in access exclusive mode;
do $pilot$
begin
  if exists (select 1 from venue.primary_checkout_pilot) then
    raise exception 'precondition_failed: close the checkout pilot before rollback' using errcode = 'P0001';
  end if;
end;
$pilot$;
drop trigger tg_primary_checkout_pilot_hold on venue.inventory_hold;
drop trigger tg_primary_checkout_pilot_order on venue."order";
drop function venue.guard_primary_checkout_pilot();
drop table venue.primary_checkout_pilot;
commit;
