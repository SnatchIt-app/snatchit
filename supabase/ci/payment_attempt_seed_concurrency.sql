-- Concurrency scenario orders (real 198 insert columns). The negative-control DB
-- only exercises ORDER_NEGATIVE; the other two are inert there.
insert into venue."order"
  (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
values
  ('aaaaaaaa-0000-4000-8000-000000000001','bbbbbbbb-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000001','pending','web',2500,'USD','ci-begin-first'),
  ('aaaaaaaa-0000-4000-8000-000000000002','bbbbbbbb-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000001','pending','web',2500,'USD','ci-cancel-first'),
  ('aaaaaaaa-0000-4000-8000-000000000003','bbbbbbbb-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000001','pending','web',2500,'USD','ci-negative')
on conflict (order_id) do nothing;
