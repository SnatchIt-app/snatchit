begin;
select plan(16);

insert into auth.users (id, email) values
  ('27700000-0000-0000-0000-000000000001', 'pilot277@example.invalid'),
  ('27700000-0000-0000-0000-000000000002', 'other277@example.invalid');
insert into kernel.organization (org_id, legal_name, display_name)
values ('27700000-0000-0000-0000-000000000003', 'Pilot 277', 'Pilot 277');
insert into catalog.venue (venue_id, org_id, name, neighborhood)
values ('27700000-0000-0000-0000-000000000004', '27700000-0000-0000-0000-000000000003', 'Pilot 277', 'wynwood');
insert into catalog.event (event_id, venue_id, org_id, title)
values ('27700000-0000-0000-0000-000000000005', '27700000-0000-0000-0000-000000000004',
        '27700000-0000-0000-0000-000000000003', 'Pilot 277');
insert into catalog.event_session (session_id, event_id, starts_at)
select ('27700000-0000-0000-0000-00000000000' || n)::uuid,
       '27700000-0000-0000-0000-000000000005', now() + interval '1 day'
from generate_series(6, 7) as n;
insert into venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor)
values ('27700000-0000-0000-0000-000000000008', '27700000-0000-0000-0000-000000000005',
        'admission', 'Pilot 277', 100);
insert into venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity)
values
  ('27700000-0000-0000-0000-000000000009', '27700000-0000-0000-0000-000000000008',
   '27700000-0000-0000-0000-000000000006', 'public_sale', 1),
  ('27700000-0000-0000-0000-000000000010', '27700000-0000-0000-0000-000000000008',
   '27700000-0000-0000-0000-000000000006', 'public_sale', 3);

create function pg_temp.pilot_hold(buyer integer, batch integer, qty integer, command_key text)
returns void language sql as $$
  insert into venue.inventory_hold (batch_id, identity_id, quantity, expires_at, command_idempotency_key)
  values (('27700000-0000-0000-0000-' || lpad(batch::text, 12, '0'))::uuid,
          ('27700000-0000-0000-0000-' || lpad(buyer::text, 12, '0'))::uuid,
          qty, now() + interval '10 minutes', command_key);
$$;
create function pg_temp.pilot_order(buyer integer, session integer, command_key text)
returns void language sql as $$
  insert into venue."order" (buyer_id, event_session_id, org_id, source, total_minor, command_idempotency_key)
  values (('27700000-0000-0000-0000-' || lpad(buyer::text, 12, '0'))::uuid,
          ('27700000-0000-0000-0000-' || lpad(session::text, 12, '0'))::uuid,
          '27700000-0000-0000-0000-000000000003', 'app', 110, command_key);
$$;

select lives_ok($$select pg_temp.pilot_hold(2, 10, 2, '277-idle')$$, 'Unconfigured guard permits ordinary holds');
select lives_ok($$select pg_temp.pilot_order(2, 7, '277-idle')$$, 'Unconfigured guard permits ordinary orders');
select ok((select relrowsecurity from pg_class where oid = 'venue.primary_checkout_pilot'::regclass),
          'Pilot configuration has RLS enabled');
select ok(not exists (
  select from unnest(array['anon', 'authenticated', 'service_role']) as r(role_name)
  where has_table_privilege(r.role_name, 'venue.primary_checkout_pilot', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE')
     or has_function_privilege(r.role_name, 'venue.guard_primary_checkout_pilot()', 'EXECUTE')
), 'Client and service roles cannot read or arm the pilot or invoke the trigger');

insert into venue.primary_checkout_pilot (batch_id, event_session_id, buyer_id, expires_at)
values ('27700000-0000-0000-0000-000000000009', '27700000-0000-0000-0000-000000000006',
        '27700000-0000-0000-0000-000000000001', clock_timestamp() + interval '1 hour');

select throws_ok($$select pg_temp.pilot_hold(2, 9, 1, '277-buyer')$$,
  'P0001', 'precondition_failed: primary_checkout_pilot_restricted', 'Other buyer cannot reserve the pilot batch');
select throws_ok($$select pg_temp.pilot_order(2, 6, '277-buyer')$$,
  'P0001', 'precondition_failed: primary_checkout_pilot_restricted', 'Other buyer cannot create a pilot order');
select throws_ok($$select pg_temp.pilot_hold(1, 10, 1, '277-batch')$$,
  'P0001', 'precondition_failed: primary_checkout_pilot_restricted', 'Allowed buyer cannot reserve another batch in the same session');
select throws_ok($$select pg_temp.pilot_order(1, 7, '277-session')$$,
  'P0001', 'precondition_failed: primary_checkout_pilot_restricted', 'Allowed buyer cannot order another session');
select throws_ok($$select pg_temp.pilot_hold(1, 9, 2, '277-quantity')$$,
  'P0001', 'precondition_failed: primary_checkout_pilot_restricted', 'Pilot hold must be for one ticket');
select lives_ok($$select pg_temp.pilot_hold(1, 9, 1, '277-allowed')$$, 'Allowed buyer can reserve exactly one ticket');
select lives_ok($$select pg_temp.pilot_order(1, 6, '277-allowed')$$, 'Allowed buyer can create an order');
select lives_ok($$update venue.inventory_batch set event_session_id = '27700000-0000-0000-0000-000000000007'
  where batch_id = '27700000-0000-0000-0000-000000000009'$$, 'Fixture moves the pilot batch to a different session');
select throws_ok($$select pg_temp.pilot_order(1, 6, '277-drift')$$,
  'P0001', 'precondition_failed: primary_checkout_pilot_restricted', 'Batch-to-session drift blocks checkout');
update venue.inventory_batch set event_session_id = '27700000-0000-0000-0000-000000000006'
where batch_id = '27700000-0000-0000-0000-000000000009';

update venue.primary_checkout_pilot set expires_at = clock_timestamp() - interval '1 second';
select throws_ok($$select pg_temp.pilot_hold(1, 9, 1, '277-expired')$$,
  'P0001', 'precondition_failed: primary_checkout_pilot_restricted', 'Expired pilot closes reservations');
select throws_ok($$select pg_temp.pilot_order(1, 6, '277-expired')$$,
  'P0001', 'precondition_failed: primary_checkout_pilot_restricted', 'Expired pilot closes checkout');
select lives_ok($$update venue.inventory_hold set status = 'expired' where command_idempotency_key = '277-allowed'$$,
  'Existing hold can expire after the window');

select * from finish();
rollback;
