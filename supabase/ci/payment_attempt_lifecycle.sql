-- Exercise the actual Edge-to-database contract as service_role.
-- The Stripe identifiers and request are synthetic. No Stripe calls are made.
begin;
set local role service_role;
do $$
declare
  order_key constant uuid := 'aaaaaaaa-0000-4000-8000-000000000005';
  buyer_key constant uuid := 'bbbbbbbb-0000-4000-8000-000000000001';
  session_key constant uuid := 'cccccccc-0000-4000-8000-000000000001';
  request_key constant text := 'ci-attempt-lifecycle';
  pi_key constant text := 'pi_ci_attempt_lifecycle';
  attempt_key uuid;
  result jsonb;
  request_body jsonb := jsonb_build_object(
    'amount', '2750', 'currency', 'usd', 'payment_method_types[0]', 'card',
    'customer', 'cus_ci_attempt_lifecycle', 'setup_future_usage', 'on_session',
    'metadata[rail]', 'native_primary', 'metadata[mode]', 'native_primary',
    'metadata[order_id]', order_key::text, 'metadata[buyer_id]', buyer_key::text,
    'metadata[session_id]', session_key::text,
    'metadata[org_id]', 'dddddddd-0000-4000-8000-000000000001'
  );
begin
  result := venue.begin_payment_attempt(order_key, request_key, buyer_key, session_key, 2500, 250, 2750, 'USD');
  attempt_key := (result->>'attempt_id')::uuid;
  if attempt_key is null or result->>'state' is distinct from 'creating' then
    raise exception 'begin did not create an attempt';
  end if;

  perform venue.store_payment_attempt_request(attempt_key, order_key, buyer_key, session_key, request_body);
  result := venue.read_payment_attempt_recovery(order_key, buyer_key, session_key);
  if result->>'attempt_id' is distinct from attempt_key::text
     or result->>'attempt_key' is distinct from request_key
     or result->>'state' is distinct from 'creating'
     or result->'pi_id' is distinct from 'null'::jsonb
     or result->'create_request' is distinct from request_body then
    raise exception 'lost-response recovery changed the stored attempt or request';
  end if;

  result := venue.attach_payment_attempt(attempt_key, pi_key, order_key, buyer_key, session_key, 2500, 250, 2750, 'USD');
  if result->>'pi_id' is distinct from pi_key or result->>'state' is distinct from 'open' then
    raise exception 'attach did not bind the payment';
  end if;

  result := venue.read_payment_attempt_binding(order_key, pi_key, buyer_key, session_key);
  if result->>'attempt_id' is distinct from attempt_key::text
     or result->>'pi_id' is distinct from pi_key
     or result->>'amount_minor' is distinct from '2750'
     or result->>'state' is distinct from 'open' then
    raise exception 'attached attempt binding disagrees with the stored quote';
  end if;

  begin
    perform venue.mark_payment_attempt_by_pi(pi_key, 'canceled', 'processing');
    raise exception 'mark accepted cancellation without a canceled Stripe status';
  exception when raise_exception then
    if sqlerrm <> 'precondition_failed: canceled requires Stripe status canceled' then raise; end if;
  end;

  result := venue.mark_payment_attempt_by_pi(pi_key, 'canceled', 'canceled');
  if result->>'state' is distinct from 'canceled' then
    raise exception 'confirmed cancellation did not reach terminal state';
  end if;
  perform venue.cancel_pending_order(order_key, 'payment_failed', 'ci-lifecycle-cancel');
end
$$;
reset role;
do $$
begin
  if (select status from venue."order" where order_id = 'aaaaaaaa-0000-4000-8000-000000000005')
       is distinct from 'cancelled' then
    raise exception 'terminal attempt did not allow the order to cancel';
  end if;
end
$$;
rollback;
