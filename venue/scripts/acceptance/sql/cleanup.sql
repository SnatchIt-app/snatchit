-- MUTATION (acceptance window only). Removes exactly the fixed 5a4d0b0e- fixture rows, in reverse
-- dependency order, including the precedence/revocation grants. Auth users are removed separately by
-- accept.mjs (admin API on the sandbox, harness tables locally). None of these tables carries an
-- append-only trigger; if a delete is refused anyway the transaction aborts and nothing is removed.
begin;
delete from venue.inventory_batch  where batch_id::text like '5a4d0b0e-0000-4000-8000-0000000000%';
delete from venue.ticket_type      where ticket_type_id::text like '5a4d0b0e-0000-4000-8000-0000000000%';
delete from catalog.event_session  where session_id::text like '5a4d0b0e-0000-4000-8000-0000000000f%';
delete from catalog.event          where event_id::text like '5a4d0b0e-0000-4000-8000-0000000000e%';
delete from venue.staff_role       where venue_id in ('5a4d0b0e-0000-4000-8000-0000000000aa', '5a4d0b0e-0000-4000-8000-0000000000bb');
delete from kernel.org_member      where org_id in ('5a4d0b0e-0000-4000-8000-00000000000a', '5a4d0b0e-0000-4000-8000-00000000000b');
delete from catalog.venue          where venue_id in ('5a4d0b0e-0000-4000-8000-0000000000aa', '5a4d0b0e-0000-4000-8000-0000000000bb');
delete from kernel.organization    where org_id in ('5a4d0b0e-0000-4000-8000-00000000000a', '5a4d0b0e-0000-4000-8000-00000000000b');
commit;
select json_build_object('leftover',
    (select count(*) from venue.inventory_batch where batch_id::text like '5a4d0b0e-%')
  + (select count(*) from venue.ticket_type where ticket_type_id::text like '5a4d0b0e-%')
  + (select count(*) from catalog.event_session where session_id::text like '5a4d0b0e-%')
  + (select count(*) from catalog.event where event_id::text like '5a4d0b0e-%')
  + (select count(*) from venue.staff_role where venue_id::text like '5a4d0b0e-%')
  + (select count(*) from kernel.org_member where org_id::text like '5a4d0b0e-%')
  + (select count(*) from catalog.venue where venue_id::text like '5a4d0b0e-%')
  + (select count(*) from kernel.organization where org_id::text like '5a4d0b0e-%')) as j;
