-- Rollback scenario order (real 198 insert columns). rollback-safety-test.sh
-- seeds its own canceled history; this provides the order the fixture asserts.
insert into venue."order"
  (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
values
  ('aaaaaaaa-0000-4000-8000-000000000008','bbbbbbbb-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000001','cancelled','web',2500,'USD','ci-rollback')
on conflict (order_id) do nothing;
