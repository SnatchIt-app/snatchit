-- SHARED real-schema structural fixture (no orders — orders are scenario-scoped).
-- UNVERIFIED / UNRUN: targets the real 198/201 catalog, NOT the synthetic contract
-- fixture. Fixed UUIDs are non-production test identifiers only; no customer data.
-- Direct INSERTs as the table owner (postgres) satisfy every FK. Applied to each
-- scenario's disposable clone; idempotent (ON CONFLICT DO NOTHING).
--
-- Reference: supabase/tests/000_helpers.sql (auth.users shape),
-- supabase/tests/145_phase2_venue_inventory.sql (inventory chain), and the real
-- 077/078/081/082 table definitions.
--
-- 081 sharding is deferred (E-32 refuses shard_count>0), so venue.inventory_hold
-- .shard_no stays NULL and no inventory_batch_shard row is required.

-- Auth identity (buyer) — venue."order".buyer_id and venue.inventory_hold
-- .identity_id both FK here.
insert into auth.users
  (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
   phone, phone_confirmed_at, created_at, updated_at)
values
  ('bbbbbbbb-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','buyer@ci.local',
   '{"provider":"email","providers":["email"]}','{}',NULL,NULL,now(),now())
on conflict (id) do nothing;

-- Organization -> Venue -> Event -> Session -> TicketType -> Batch -> Hold.
insert into kernel.organization (org_id, legal_name, display_name, status)
values ('dddddddd-0000-4000-8000-000000000001','Inv Co','Inv Co','approved')
on conflict (org_id) do nothing;

insert into catalog.venue (venue_id, org_id, name, neighborhood, approval_status)
values ('ffffffff-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000001',
        'Hall','wynwood','approved')
on conflict (venue_id) do nothing;

insert into catalog.event (event_id, venue_id, org_id, title, status)
values ('00000000-0000-4000-8000-0000000000e1','ffffffff-0000-4000-8000-000000000001',
        'dddddddd-0000-4000-8000-000000000001','Inv Night','on_sale')
on conflict (event_id) do nothing;

insert into catalog.event_session (session_id, event_id, starts_at, ends_at, status)
values ('cccccccc-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000000e1',
        now() + interval '20 days', now() + interval '20 days 5 hours', 'scheduled')
on conflict (session_id) do nothing;

insert into venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility)
values ('00000000-0000-4000-8000-0000000000e2','00000000-0000-4000-8000-0000000000e1',
        'admission','GA',5000,'public')
on conflict (ticket_type_id) do nothing;

insert into venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity)
values ('00000000-0000-4000-8000-0000000000e3','00000000-0000-4000-8000-0000000000e2',
        'cccccccc-0000-4000-8000-000000000001','public_sale',100)
on conflict (batch_id) do nothing;

-- The active-hold rollback fixture. Seeded 'released'; the active-hold rollback
-- mode flips it to 'active' in its own clone, and rollback.sql's preflight must
-- refuse with exactly 'precondition_failed: active inventory holds exist; rollback refused'.
insert into venue.inventory_hold
  (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
values ('eeeeeeee-0000-4000-8000-000000000008','00000000-0000-4000-8000-0000000000e3',
        'bbbbbbbb-0000-4000-8000-000000000001',2,'released',now() + interval '1 hour','ck-h-1')
on conflict (hold_id) do nothing;
