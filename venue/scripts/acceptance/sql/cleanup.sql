-- MUTATION (acceptance window only). Removes exactly the synthetic venue fixture rows listed in
-- docs/venue-dashboard/SANDBOX_WINDOW_MANIFEST_VENUE.md, by exact id, in reverse dependency order —
-- including the precedence grants and the pending Venue C grant. Grants are removed by fixture venue/org id
-- (only these synthetic venues/orgs exist under the 5a4d0b0e- prefix). Auth users are removed separately by
-- accept.mjs (Auth admin API on the sandbox, harness tables locally). None of these tables carries an
-- append-only trigger; if any delete is refused the transaction aborts and nothing is removed.
begin;
delete from venue.inventory_batch  where batch_id in ('5a4d0b0e-0000-4000-8000-000000000021', '5a4d0b0e-0000-4000-8000-000000000022', '5a4d0b0e-0000-4000-8000-000000000023');
delete from venue.ticket_type      where ticket_type_id in ('5a4d0b0e-0000-4000-8000-000000000011', '5a4d0b0e-0000-4000-8000-000000000012', '5a4d0b0e-0000-4000-8000-000000000013');
delete from catalog.event_session  where session_id in ('5a4d0b0e-0000-4000-8000-0000000000f1', '5a4d0b0e-0000-4000-8000-0000000000f2', '5a4d0b0e-0000-4000-8000-0000000000f3', '5a4d0b0e-0000-4000-8000-0000000000f4');
delete from catalog.event          where event_id in ('5a4d0b0e-0000-4000-8000-0000000000e1', '5a4d0b0e-0000-4000-8000-0000000000e2', '5a4d0b0e-0000-4000-8000-0000000000e3', '5a4d0b0e-0000-4000-8000-0000000000e4');
delete from venue.staff_role       where venue_id in ('5a4d0b0e-0000-4000-8000-0000000000aa', '5a4d0b0e-0000-4000-8000-0000000000bb', '5a4d0b0e-0000-4000-8000-0000000000cc');
delete from kernel.org_member      where org_id in ('5a4d0b0e-0000-4000-8000-00000000000a', '5a4d0b0e-0000-4000-8000-00000000000b');
delete from catalog.venue          where venue_id in ('5a4d0b0e-0000-4000-8000-0000000000aa', '5a4d0b0e-0000-4000-8000-0000000000bb', '5a4d0b0e-0000-4000-8000-0000000000cc');
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
