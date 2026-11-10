begin;
select plan(20);

insert into auth.users (id, email) values
  ('27800000-0000-0000-0000-000000000001', 'pilot278@example.invalid'),
  ('27800000-0000-0000-0000-000000000002', 'other278@example.invalid');
insert into kernel.organization (org_id, legal_name, display_name)
values ('27800000-0000-0000-0000-000000000003', 'Pilot 278', 'Pilot 278');
insert into catalog.venue (venue_id, org_id, name, neighborhood, approval_status)
values ('27800000-0000-0000-0000-000000000004', '27800000-0000-0000-0000-000000000003', 'Pilot 278', 'wynwood', 'approved');
insert into catalog.event (event_id, venue_id, org_id, title, status)
values ('27800000-0000-0000-0000-000000000005', '27800000-0000-0000-0000-000000000004',
        '27800000-0000-0000-0000-000000000003', 'Pilot 278', 'on_sale');
insert into catalog.event_session (session_id, event_id, starts_at)
select ('27800000-0000-0000-0000-00000000000' || n)::uuid,
       '27800000-0000-0000-0000-000000000005', now() + interval '1 day'
from generate_series(6, 7) as n;
insert into venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility)
values ('27800000-0000-0000-0000-000000000008', '27800000-0000-0000-0000-000000000005',
        'admission', 'Pilot 278', 100, 'public');
insert into venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity)
values
  ('27800000-0000-0000-0000-000000000009', '27800000-0000-0000-0000-000000000008',
   '27800000-0000-0000-0000-000000000006', 'public_sale', 1),
  ('27800000-0000-0000-0000-000000000010', '27800000-0000-0000-0000-000000000008',
   '27800000-0000-0000-0000-000000000006', 'public_sale', 3);

-- The ordinary event is a positive control before the pilot marker is set.
select tap.login_anon();
select is((select count(*)::int from public.list_primary_sessions_on_sale()
  where event_id = '27800000-0000-0000-0000-000000000005'), 2, 'Ordinary event appears in discovery');
select is((select count(*)::int from public.get_primary_session('27800000-0000-0000-0000-000000000006')),
  1, 'Ordinary event is visible by direct link');
select tap.logout();

-- Keep the pre-migration run executable so it fails the actual privacy checks.
do $fixture$ begin
  if exists (select from pg_attribute where attrelid = 'catalog.event'::regclass
    and attname = 'private_pilot' and not attisdropped) then
    update catalog.event set private_pilot = true
      where event_id = '27800000-0000-0000-0000-000000000005';
  end if;
end $fixture$;
insert into venue.primary_checkout_pilot (batch_id, event_session_id, buyer_id, expires_at)
values ('27800000-0000-0000-0000-000000000009', '27800000-0000-0000-0000-000000000006',
        '27800000-0000-0000-0000-000000000001', clock_timestamp() + interval '1 hour');

select tap.login_anon();
select is((select count(*)::int from public.list_primary_sessions_on_sale()
  where event_id = '27800000-0000-0000-0000-000000000005'), 0, 'Anonymous discovery hides the pilot');
select is((select count(*)::int from public.get_primary_session('27800000-0000-0000-0000-000000000006')),
  0, 'Anonymous direct link reveals nothing');
select is((select count(*)::int from catalog.event where event_id = '27800000-0000-0000-0000-000000000005'),
  0, 'Anonymous catalog cannot see the event');
select is((select count(*)::int from catalog.event_session where session_id = '27800000-0000-0000-0000-000000000006'),
  0, 'Anonymous catalog cannot see the session');
select tap.logout();

select tap.login('27800000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.get_primary_session('27800000-0000-0000-0000-000000000006')),
  0, 'Another signed-in buyer sees no direct result');
select is((select count(*)::int from catalog.event where event_id = '27800000-0000-0000-0000-000000000005'),
  0, 'Another buyer cannot see the catalog event');
select is((select count(*)::int from venue.ticket_type where ticket_type_id = '27800000-0000-0000-0000-000000000008'),
  0, 'Another buyer cannot see the tier');
select throws_ok($$select public.reserve_primary_tier('27800000-0000-0000-0000-000000000006',
  '27800000-0000-0000-0000-000000000008', 1, 'private-278-other')$$, 'P0002',
  'not_found: no public_sale inventory for ticket type 27800000-0000-0000-0000-000000000008 on session 27800000-0000-0000-0000-000000000006',
  'Reservation with both IDs has the same response as missing inventory');
select tap.logout();

-- Fixture-only settings. The transaction rolls them all back.
insert into catalog.platform_config (key, version, value, visibility)
select cfg.key, coalesce(existing.version, 0) + 1, cfg.value, coalesce(existing.visibility, 'restricted')
from (values ('feature.native_issuance_enabled', 'true'::jsonb),
             ('inventory.per_user_active_hold_max', '6'::jsonb),
             ('inventory.hold_ttl_interval', '"10 minutes"'::jsonb)) cfg(key, value)
left join lateral (
  select version, visibility from catalog.platform_config where key = cfg.key order by version desc limit 1
) existing on true;

select tap.login('27800000-0000-0000-0000-000000000002');
select throws_ok($$select venue.create_primary_checkout('27800000-0000-0000-0000-000000000006',
  '[{}]'::jsonb, array[]::uuid[], 'private-278-other-checkout')$$, 'P0002',
  'not_found: session 27800000-0000-0000-0000-000000000006', 'Wrong buyer gets the missing-session checkout response');
select throws_ok($$select venue.create_primary_checkout('27800000-0000-0000-0000-000000000099',
  '[{}]'::jsonb, array[]::uuid[], 'private-278-unknown-checkout')$$, 'P0002',
  'not_found: session 27800000-0000-0000-0000-000000000099', 'An unknown session uses the same checkout refusal');
select tap.logout();

select tap.login('27800000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.list_primary_sessions_on_sale()
  where event_id = '27800000-0000-0000-0000-000000000005'), 0, 'Pilot is unlisted for the designated buyer too');
select is((select (ticket_types->0->>'remaining')::int
  from public.get_primary_session('27800000-0000-0000-0000-000000000006')),
  1, 'Designated buyer sees only the authorized batch quantity');
select is((select count(*)::int from public.get_primary_session('27800000-0000-0000-0000-000000000007')),
  0, 'Designated buyer cannot see another session');
select is(public.reserve_primary_tier('27800000-0000-0000-0000-000000000006',
  '27800000-0000-0000-0000-000000000008', 1, 'private-278-allowed')->>'status',
  'ok', 'The designated buyer can reserve via the normal buyer endpoint');
select tap.logout();
select is((select batch_id from venue.inventory_hold where command_idempotency_key = 'private-278-allowed'),
  '27800000-0000-0000-0000-000000000009'::uuid, 'The reservation binds to the exact approved batch');

insert into kernel.org_member (org_id, identity_id, role)
values ('27800000-0000-0000-0000-000000000003', '27800000-0000-0000-0000-000000000002', 'org_owner');
select tap.login('27800000-0000-0000-0000-000000000002');
select is((select count(*)::int from catalog.event where event_id = '27800000-0000-0000-0000-000000000005'),
  1, 'Existing organization access is preserved');
select tap.logout();

update venue.primary_checkout_pilot set expires_at = statement_timestamp() - interval '1 second';
select tap.login('27800000-0000-0000-0000-000000000001');
select is((select count(*)::int from public.get_primary_session('27800000-0000-0000-0000-000000000006')),
  0, 'Exact buyer link stops working after the deadline');
select tap.logout();

delete from venue.primary_checkout_pilot;
select tap.login_anon();
select is((select count(*)::int from public.get_primary_session('27800000-0000-0000-0000-000000000006')),
  0, 'Closeout never makes a published pilot public');
select tap.logout();
select * from finish();
rollback;
