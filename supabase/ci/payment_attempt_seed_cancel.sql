-- Cancellation-refusal scenario orders (real 198 insert columns).
--   ci-cancel-guard    -> gets an unresolved attempt, cancel must refuse (P0001).
--   ci-cancel-positive -> no attempt, cancel must succeed (positive control).
insert into venue."order"
  (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
values
  ('aaaaaaaa-0000-4000-8000-000000000005','bbbbbbbb-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000001','pending','web',2500,'USD','ci-cancel-guard'),
  ('aaaaaaaa-0000-4000-8000-000000000006','bbbbbbbb-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-000000000001','pending','web',2500,'USD','ci-cancel-positive')
on conflict (order_id) do nothing;
