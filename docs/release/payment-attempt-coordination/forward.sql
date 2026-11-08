-- OC-PAYMENT-ATOMIC-COORDINATION-1 — LOCAL DRAFT ONLY. DO NOT APPLY.
-- Register/review as a migration only after Codex review and a fresh replay.
--
-- INVARIANT: before every native PaymentIntent POST, a venue.payment_attempt row
-- exists under the same venue."order" FOR UPDATE lock used by
-- venue.cancel_pending_order (082:478-525). Cancellation is refused while any
-- attempt for the order is not independently confirmed Stripe-canceled.
--
-- This draft does not change 082, 198/201 bodies or their md5 pins. It adds a
-- trigger on venue."order"; the existing cancel function's UPDATE fires it
-- while the order row is locked. The four public-grant census files do not move
-- because every object here is in venue. See INTEGRATION-CHECKLIST.md.

begin;

-- Keep concurrent writers out between the drain check and trigger installation.
set local lock_timeout = '3s';
lock table venue."order", venue.inventory_hold in share row exclusive mode;

-- Cutover preflight: refuse to install over an ambiguous legacy state. No row is
-- backfilled and no missing PI is assumed canceled.
do $preflight$
begin
  if exists (select 1 from venue."order" where status = 'pending') then
    raise exception 'precondition_failed: payment-attempt preflight requires zero pending venue orders; nothing changed'
      using errcode = 'P0001';
  end if;
  if exists (select 1 from venue.inventory_hold where status = 'active') then
    raise exception 'precondition_failed: payment-attempt preflight requires zero active inventory holds; nothing changed'
      using errcode = 'P0001';
  end if;
end
$preflight$;

create table venue.payment_attempt (
  attempt_id    uuid primary key default gen_random_uuid(),
  order_id      uuid not null references venue."order"(order_id) on delete restrict,
  attempt_key   text not null,
  buyer_id      uuid not null,
  session_id    uuid null,
  face_minor    integer not null check (face_minor >= 0),
  buyer_fee_minor integer not null check (buyer_fee_minor >= 0),
  amount_minor  integer not null check (amount_minor >= 0),
  currency      text not null check (currency = upper(currency) and length(currency) = 3),
  pi_id         text null,
  state         text not null default 'creating'
                check (state in ('creating','open','processing','succeeded','failed','canceled','unknown')),
  create_request jsonb null,
  last_stripe_status text null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  attached_at   timestamptz null,
  terminal_at   timestamptz null,
  constraint payment_attempt_order_key_uq unique (order_id, attempt_key),
  constraint payment_attempt_pi_uq unique (pi_id)
);

create index payment_attempt_order_state_idx
  on venue.payment_attempt (order_id, state);

create table venue.payment_attempt_event (
  event_id    bigint generated always as identity primary key,
  attempt_id  uuid not null references venue.payment_attempt(attempt_id) on delete restrict,
  event_kind  text not null check (event_kind in ('begin','attach','mark')),
  from_state  text null,
  to_state    text not null,
  stripe_status text null,
  occurred_at timestamptz not null default now()
);

create index payment_attempt_event_attempt_idx
  on venue.payment_attempt_event (attempt_id, occurred_at);

alter table venue.payment_attempt enable row level security;
alter table venue.payment_attempt_event enable row level security;
revoke all on table venue.payment_attempt, venue.payment_attempt_event
  from public, anon, authenticated, service_role;

-- Append-only evidence table. No update/delete path exists.
create function venue.payment_attempt_event_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  raise exception 'invalid_input: venue.payment_attempt_event is append-only';
end;
$fn$;
revoke all on function venue.payment_attempt_event_append_only() from public, anon, authenticated, service_role;

create trigger payment_attempt_event_append_only
  before update or delete on venue.payment_attempt_event
  for each row execute function venue.payment_attempt_event_append_only();

-- BEGIN: lock the order first; then reuse a live attempt under the same logical
-- key or insert a new creating row. A retry after a lost Stripe response gets
-- the same attempt/key back. A canceled attempt is returned as-is; the caller
-- must choose a new, persisted remint key (never a random retry key).
create function venue.begin_payment_attempt(
  p_order_id uuid,
  p_attempt_key text,
  p_buyer_id uuid,
  p_session_id uuid,
  p_face_minor integer,
  p_buyer_fee_minor integer,
  p_charge_minor integer,
  p_currency text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_status text;
  v_order_buyer uuid;
  v_order_session uuid;
  v_order_total integer;
  v_order_currency text;
  v_attempt venue.payment_attempt%rowtype;
begin
  if p_order_id is null or p_buyer_id is null or p_session_id is null then
    raise exception 'invalid_input: order, buyer and session required';
  end if;
  if p_attempt_key is null or length(trim(p_attempt_key)) = 0 or length(p_attempt_key) > 200 then
    raise exception 'invalid_input: attempt key required (<= 200 chars)';
  end if;
  if p_face_minor is null or p_face_minor < 0 or p_buyer_fee_minor is null or p_buyer_fee_minor < 0
     or p_charge_minor is null or p_charge_minor <> p_face_minor + p_buyer_fee_minor then
    raise exception 'invalid_input: invalid face/fee/charge amounts';
  end if;
  if p_currency is null or p_currency <> upper(p_currency) or length(p_currency) <> 3 then
    raise exception 'invalid_input: currency must be a 3-letter uppercase code';
  end if;

  select status, buyer_id, event_session_id, total_minor, currency
    into v_status, v_order_buyer, v_order_session, v_order_total, v_order_currency
    from venue."order" where order_id = p_order_id for update;
  if v_status is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0002';
  end if;
  if v_status <> 'pending' then
    raise exception 'precondition_failed: order_not_pending (status=%)', v_status using errcode = 'P0001';
  end if;
  if v_order_buyer is distinct from p_buyer_id
     or v_order_session is distinct from p_session_id
     or v_order_total is distinct from p_face_minor
     or v_order_currency is distinct from p_currency then
    raise exception 'precondition_failed: attempt does not match authoritative order identity' using errcode = 'P0001';
  end if;

  select * into v_attempt
    from venue.payment_attempt
   where order_id = p_order_id and attempt_key = p_attempt_key
   for update;
  if found then
    if v_attempt.buyer_id <> p_buyer_id
       or v_attempt.session_id is distinct from p_session_id
       or v_attempt.face_minor <> p_face_minor
       or v_attempt.buyer_fee_minor <> p_buyer_fee_minor
       or v_attempt.amount_minor <> p_charge_minor
       or v_attempt.currency <> p_currency then
      raise exception 'precondition_failed: attempt identity mismatch for key %', p_attempt_key using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'attempt_id', v_attempt.attempt_id, 'attempt_key', v_attempt.attempt_key,
      'state', v_attempt.state, 'pi_id', v_attempt.pi_id
    );
  end if;

  insert into venue.payment_attempt
    (order_id, attempt_key, buyer_id, session_id, face_minor, buyer_fee_minor, amount_minor, currency, state)
  values
    (p_order_id, p_attempt_key, p_buyer_id, p_session_id, p_face_minor, p_buyer_fee_minor, p_charge_minor, upper(p_currency), 'creating')
  returning * into v_attempt;

  insert into venue.payment_attempt_event (attempt_id, event_kind, from_state, to_state)
  values (v_attempt.attempt_id, 'begin', null, 'creating');

  return jsonb_build_object(
    'attempt_id', v_attempt.attempt_id, 'attempt_key', v_attempt.attempt_key,
    'state', v_attempt.state, 'pi_id', v_attempt.pi_id
  );
end;
$fn$;

-- STORE CREATE REQUEST: persist the exact Stripe POST body once, under order lock,
-- before a future POST. No client secret or extra field is accepted. Exact retry
-- succeeds; any changed body/customer/amount refuses.
create function venue.store_payment_attempt_request(
  p_attempt_id uuid, p_order_id uuid, p_buyer_id uuid, p_session_id uuid, p_create_request jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_status text;
  v_order_buyer uuid;
  v_order_session uuid;
  v_order_org uuid;
  v_order_total integer;
  v_order_currency text;
  v_a venue.payment_attempt%rowtype;
  v_n integer;
  v_bad text;
begin
  if p_attempt_id is null or p_order_id is null or p_buyer_id is null or p_session_id is null
     or p_create_request is null or jsonb_typeof(p_create_request) <> 'object' then
    raise exception 'invalid_input: attempt/order/buyer/session and object request required';
  end if;
  select status, buyer_id, event_session_id, org_id, total_minor, currency
    into v_status, v_order_buyer, v_order_session, v_order_org, v_order_total, v_order_currency
    from venue."order" where order_id = p_order_id for update;
  if v_status is null then raise exception 'not_found: order %', p_order_id using errcode = 'P0002'; end if;
  if v_status <> 'pending' then raise exception 'precondition_failed: order_not_pending' using errcode = 'P0001'; end if;
  if v_order_buyer <> p_buyer_id or v_order_session is distinct from p_session_id then
    raise exception 'precondition_failed: create-request order identity mismatch' using errcode = 'P0001';
  end if;
  select * into v_a from venue.payment_attempt
   where attempt_id = p_attempt_id and order_id = p_order_id
     and buyer_id = p_buyer_id and session_id = p_session_id for update;
  if not found then raise exception 'precondition_failed: create-request attempt mismatch' using errcode = 'P0001'; end if;
  if v_a.state not in ('creating','open') then
    raise exception 'precondition_failed: attempt state % cannot store a create request', v_a.state using errcode = 'P0001';
  end if;
  if v_a.amount_minor <> v_order_total + v_a.buyer_fee_minor or v_a.face_minor <> v_order_total
     or v_a.currency <> 'USD' or v_order_currency <> 'USD' then
    raise exception 'precondition_failed: persisted quote differs from order' using errcode = 'P0001';
  end if;
  select count(*) into v_n from jsonb_object_keys(p_create_request);
  if v_n <> 11 then raise exception 'invalid_input: create request must have exactly 11 fields' using errcode = 'P0001'; end if;
  if exists (select 1 from jsonb_each(p_create_request) e where jsonb_typeof(e.value) <> 'string') then
    raise exception 'invalid_input: create request values must be strings' using errcode = 'P0001';
  end if;
  if (p_create_request - array['amount','currency','payment_method_types[0]','customer','setup_future_usage','metadata[rail]','metadata[mode]','metadata[order_id]','metadata[buyer_id]','metadata[org_id]','metadata[session_id]']) <> '{}'::jsonb
     or (select count(*) from jsonb_object_keys(p_create_request) k where k not in ('amount','currency','payment_method_types[0]','customer','setup_future_usage','metadata[rail]','metadata[mode]','metadata[order_id]','metadata[buyer_id]','metadata[org_id]','metadata[session_id]')) <> 0 then
    raise exception 'invalid_input: unsupported/extra create-request field' using errcode = 'P0001';
  end if;
  if (p_create_request->>'amount')::integer <> v_a.amount_minor
     or (p_create_request->>'currency') <> 'usd'
     or btrim(coalesce(p_create_request->>'customer','')) = ''
     or (p_create_request->>'payment_method_types[0]') <> 'card'
     or (p_create_request->>'setup_future_usage') <> 'on_session'
     or (p_create_request->>'metadata[rail]') <> 'native_primary'
     or (p_create_request->>'metadata[mode]') <> 'native_primary'
     or (p_create_request->>'metadata[order_id]')::uuid <> p_order_id
     or (p_create_request->>'metadata[buyer_id]')::uuid <> p_buyer_id
     or (p_create_request->>'metadata[session_id]')::uuid <> p_session_id
     or (p_create_request->>'metadata[org_id]')::uuid <> v_order_org then
    raise exception 'invalid_input: create-request identity/amount/org mismatch' using errcode = 'P0001';
  end if;
  if v_a.create_request is not null and v_a.create_request <> p_create_request then
    raise exception 'precondition_failed: create request already persisted differently' using errcode = 'P0001';
  end if;
  update venue.payment_attempt set create_request = p_create_request, updated_at = now()
   where attempt_id = p_attempt_id and create_request is null;
  return jsonb_build_object(
    'attempt_id', v_a.attempt_id, 'order_id', v_a.order_id, 'buyer_id', v_a.buyer_id,
    'session_id', v_a.session_id, 'pi_id', v_a.pi_id, 'state', v_a.state,
    'face_minor', v_a.face_minor, 'buyer_fee_minor', v_a.buyer_fee_minor,
    'amount_minor', v_a.amount_minor, 'currency', v_a.currency,
    'create_request', coalesce(v_a.create_request, p_create_request)
  );
end;
$fn$;
revoke all on function venue.store_payment_attempt_request(uuid, uuid, uuid, uuid, jsonb) from public, anon, authenticated, service_role;
grant execute on function venue.store_payment_attempt_request(uuid, uuid, uuid, uuid, jsonb) to service_role;

-- ATTACH: only a creating attempt; the PI id is immutable. The caller checks the
-- Stripe object's metadata/amount/currency before calling; these arguments must
-- equal the persisted attempt identity. No secret is stored.
create function venue.attach_payment_attempt(
  p_attempt_id uuid,
  p_pi_id text,
  p_order_id uuid,
  p_buyer_id uuid,
  p_session_id uuid,
  p_face_minor integer,
  p_buyer_fee_minor integer,
  p_charge_minor integer,
  p_currency text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_attempt venue.payment_attempt%rowtype;
  v_order_id uuid;
begin
  if p_attempt_id is null or p_pi_id is null or length(trim(p_pi_id)) = 0
     or p_order_id is null or p_buyer_id is null or p_session_id is null
     or p_face_minor is null or p_buyer_fee_minor is null or p_charge_minor is null
     or p_currency is null then
    raise exception 'invalid_input: attach identity parameters required';
  end if;
  -- LOCK ORDER FIRST. The attempt id is read without a lock only to learn the
  -- order; order -> attempt is the one lock order for every mutation.
  select order_id into v_order_id from venue.payment_attempt where attempt_id = p_attempt_id;
  if v_order_id is null then raise exception 'not_found: payment attempt %', p_attempt_id using errcode = 'P0002'; end if;
  perform 1 from venue."order" where order_id = v_order_id for update;
  select * into v_attempt from venue.payment_attempt where attempt_id = p_attempt_id for update;
  if not found then raise exception 'not_found: payment attempt %', p_attempt_id using errcode = 'P0002'; end if;
  if v_attempt.order_id <> p_order_id
     or v_attempt.buyer_id <> p_buyer_id
     or v_attempt.session_id is distinct from p_session_id
     or v_attempt.face_minor <> p_face_minor
     or v_attempt.buyer_fee_minor <> p_buyer_fee_minor
     or v_attempt.amount_minor <> p_charge_minor
     or v_attempt.currency <> upper(p_currency) then
    raise exception 'precondition_failed: attach identity mismatch' using errcode = 'P0001';
  end if;
  if v_attempt.pi_id = p_pi_id and v_attempt.state in ('open','processing','succeeded','canceled') then
    return jsonb_build_object('attempt_id', p_attempt_id, 'state', v_attempt.state, 'pi_id', p_pi_id, 'replay', true);
  end if;
  if v_attempt.pi_id is not null and v_attempt.pi_id <> p_pi_id then
    raise exception 'precondition_failed: attempt already bound to another PI' using errcode = 'P0001';
  end if;
  if v_attempt.state <> 'creating' then
    raise exception 'precondition_failed: attempt is not creating (state=%)', v_attempt.state using errcode = 'P0001';
  end if;

  update venue.payment_attempt
     set pi_id = p_pi_id, state = 'open', attached_at = now(), updated_at = now()
   where attempt_id = p_attempt_id;
  insert into venue.payment_attempt_event (attempt_id, event_kind, from_state, to_state, stripe_status)
  values (p_attempt_id, 'attach', 'creating', 'open', null);
  return jsonb_build_object('attempt_id', p_attempt_id, 'state', 'open', 'pi_id', p_pi_id, 'replay', false);
end;
$fn$;

-- MARK: service-only state advance. Terminal states never downgrade. `canceled`
-- requires an independently observed Stripe `canceled`; a local payment failure is
-- NOT accepted as terminal cancellation. Failed/unknown remain blocking.
create function venue.mark_payment_attempt(
  p_attempt_id uuid,
  p_state text,
  p_stripe_status text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_attempt venue.payment_attempt%rowtype;
  v_order_id uuid;
begin
  if p_attempt_id is null or p_state is null then
    raise exception 'invalid_input: attempt and state required';
  end if;
  if p_state not in ('processing','succeeded','failed','canceled','unknown') then
    raise exception 'invalid_input: unsupported attempt state %', p_state;
  end if;
  if p_state = 'canceled' and p_stripe_status is distinct from 'canceled' then
    raise exception 'precondition_failed: canceled requires Stripe status canceled' using errcode = 'P0001';
  end if;
  if p_state = 'succeeded' and p_stripe_status is distinct from 'succeeded' then
    raise exception 'precondition_failed: succeeded requires Stripe status succeeded' using errcode = 'P0001';
  end if;
  if p_state = 'processing' and p_stripe_status is distinct from 'processing' then
    raise exception 'precondition_failed: processing requires Stripe status processing' using errcode = 'P0001';
  end if;

  select order_id into v_order_id from venue.payment_attempt where attempt_id = p_attempt_id;
  if v_order_id is null then raise exception 'not_found: payment attempt %', p_attempt_id using errcode = 'P0002'; end if;
  perform 1 from venue."order" where order_id = v_order_id for update;
  select * into v_attempt from venue.payment_attempt where attempt_id = p_attempt_id for update;
  if not found then raise exception 'not_found: payment attempt %', p_attempt_id using errcode = 'P0002'; end if;
  if v_attempt.state = 'creating' then
    raise exception 'precondition_failed: attempt is still creating; attach first' using errcode = 'P0001';
  end if;
  if v_attempt.state in ('succeeded','canceled') and p_state <> v_attempt.state then
    raise exception 'precondition_failed: terminal attempt cannot change from % to %', v_attempt.state, p_state using errcode = 'P0001';
  end if;
  if v_attempt.state = 'processing' and p_state in ('failed','unknown') then
    raise exception 'precondition_failed: processing cannot downgrade to %', p_state using errcode = 'P0001';
  end if;
  if v_attempt.state = 'failed' and p_state = 'unknown' then
    raise exception 'precondition_failed: failed cannot downgrade to unknown' using errcode = 'P0001';
  end if;

  update venue.payment_attempt
     set state = p_state, last_stripe_status = p_stripe_status, updated_at = now(),
         terminal_at = case when p_state in ('succeeded','canceled') then now() else terminal_at end
   where attempt_id = p_attempt_id;
  insert into venue.payment_attempt_event (attempt_id, event_kind, from_state, to_state, stripe_status)
  values (p_attempt_id, 'mark', v_attempt.state, p_state, p_stripe_status);
  return jsonb_build_object('attempt_id', p_attempt_id, 'state', p_state, 'pi_id', v_attempt.pi_id);
end;
$fn$;

create function venue.mark_payment_attempt_by_pi(
  p_pi_id text,
  p_state text,
  p_stripe_status text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_attempt venue.payment_attempt%rowtype;
  v_order_id uuid;
begin
  if p_pi_id is null or p_state is null then
    raise exception 'invalid_input: PI and state required';
  end if;
  -- Immutable order identity is read without an attempt lock; then lock order
  -- first and re-read/revalidate the attempt. Never attempt -> order.
  select order_id into v_order_id from venue.payment_attempt where pi_id = p_pi_id;
  if v_order_id is null then
    raise exception 'precondition_failed: no payment attempt for PI %', p_pi_id using errcode = 'PNA01';
  end if;
  perform 1 from venue."order" where order_id = v_order_id for update;
  select * into v_attempt from venue.payment_attempt where pi_id = p_pi_id for update;
  if not found or v_attempt.order_id is distinct from v_order_id then
    raise exception 'precondition_failed: attempt/PI identity changed while locking' using errcode = 'P0001';
  end if;
  return venue.mark_payment_attempt(v_attempt.attempt_id, p_state, p_stripe_status) || jsonb_build_object(
    'order_id', v_attempt.order_id, 'buyer_id', v_attempt.buyer_id, 'session_id', v_attempt.session_id,
    'face_minor', v_attempt.face_minor, 'amount_minor', v_attempt.amount_minor, 'currency', v_attempt.currency
  );
end;
$fn$;

-- READ RECOVERY: service-only, exact one unresolved (creating/open) attempt
-- for this order/buyer/session. Never guesses among multiple; never adopts a
-- legacy/untracked attempt; no secret is returned. The stored create request is
-- the original Stripe POST body and must already exist.
create function venue.read_payment_attempt_recovery(
  p_order_id uuid, p_buyer_id uuid, p_session_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_status text;
  v_order_buyer uuid;
  v_order_session uuid;
  v_order_org uuid;
  v_order_total integer;
  v_order_currency text;
  v_count integer;
  v_a venue.payment_attempt%rowtype;
begin
  if p_order_id is null or p_buyer_id is null or p_session_id is null then
    raise exception 'invalid_input: recovery identity required';
  end if;
  -- Order lock first. It does not span any network call.
  select status, buyer_id, event_session_id, org_id, total_minor, currency
    into v_status, v_order_buyer, v_order_session, v_order_org, v_order_total, v_order_currency
    from venue."order" where order_id = p_order_id for update;
  if v_status is null then raise exception 'not_found: order %', p_order_id using errcode = 'P0002'; end if;
  if v_status <> 'pending' then raise exception 'precondition_failed: order_not_pending' using errcode = 'P0001'; end if;
  if v_order_buyer <> p_buyer_id or v_order_session is distinct from p_session_id then
    raise exception 'precondition_failed: recovery order identity mismatch' using errcode = 'P0001';
  end if;
  -- Count ALL non-canceled attempts, not only eligible states. Ambiguity and
  -- non-recoverable states must be refused, never "pick the newest".
  select count(*) into v_count from venue.payment_attempt
   where order_id = p_order_id and state <> 'canceled';
  if v_count <> 1 then
    raise exception 'precondition_failed: recovery needs exactly one non-canceled attempt (found %)', v_count using errcode = 'P0001';
  end if;
  select * into v_a from venue.payment_attempt
   where order_id = p_order_id and buyer_id = p_buyer_id and session_id = p_session_id
     and state <> 'canceled' for update;
  if v_a.state not in ('creating','open') then
    raise exception 'precondition_failed: recovery state % is not recoverable', v_a.state using errcode = 'P0001';
  end if;
  if v_a.state = 'creating' and v_a.pi_id is not null then
    raise exception 'precondition_failed: creating recovery attempt has a PI' using errcode = 'P0001';
  end if;
  if v_a.state = 'open' and (v_a.pi_id is null or btrim(v_a.pi_id) = '') then
    raise exception 'precondition_failed: open recovery attempt has no PI' using errcode = 'P0001';
  end if;
  if v_a.attempt_key is null or btrim(v_a.attempt_key) = '' or length(v_a.attempt_key) > 200 then
    raise exception 'precondition_failed: recovery attempt key invalid' using errcode = 'P0001';
  end if;
  if v_a.face_minor <> v_order_total or v_a.amount_minor <> v_a.face_minor + v_a.buyer_fee_minor
     or v_a.currency <> 'USD' or v_order_currency <> 'USD'
     or v_a.create_request is null or jsonb_typeof(v_a.create_request) <> 'object' then
    raise exception 'precondition_failed: recovery quote/request mismatch' using errcode = 'P0001';
  end if;
  if (select count(*) from jsonb_object_keys(v_a.create_request)) <> 11
     or exists (select 1 from jsonb_each(v_a.create_request) e where jsonb_typeof(e.value) <> 'string')
     or (select count(*) from jsonb_object_keys(v_a.create_request) k where k not in ('amount','currency','payment_method_types[0]','customer','setup_future_usage','metadata[rail]','metadata[mode]','metadata[order_id]','metadata[buyer_id]','metadata[org_id]','metadata[session_id]')) <> 0
     or (v_a.create_request->>'amount')::integer <> v_a.amount_minor
     or (v_a.create_request->>'currency') <> 'usd'
     or (v_a.create_request->>'payment_method_types[0]') <> 'card'
     or (v_a.create_request->>'setup_future_usage') <> 'on_session'
     or (v_a.create_request->>'metadata[rail]') <> 'native_primary'
     or (v_a.create_request->>'metadata[mode]') <> 'native_primary'
     or coalesce((v_a.create_request->>'customer'),'') !~ '\S'
     or coalesce((v_a.create_request->>'metadata[org_id]'),'') !~ '\S'
     or (v_a.create_request->>'metadata[order_id]')::uuid <> v_a.order_id
     or (v_a.create_request->>'metadata[buyer_id]')::uuid <> v_a.buyer_id
     or (v_a.create_request->>'metadata[session_id]')::uuid <> v_a.session_id
     or (v_a.create_request->>'metadata[org_id]')::uuid <> v_order_org then
    raise exception 'precondition_failed: recovery create request invalid' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'attempt_id', v_a.attempt_id, 'attempt_key', v_a.attempt_key,
    'order_id', v_a.order_id, 'buyer_id', v_a.buyer_id, 'session_id', v_a.session_id,
    'pi_id', v_a.pi_id, 'state', v_a.state,
    'face_minor', v_a.face_minor, 'buyer_fee_minor', v_a.buyer_fee_minor,
    'amount_minor', v_a.amount_minor, 'currency', v_a.currency,
    'create_request', v_a.create_request
  );
end;
$fn$;
revoke all on function venue.read_payment_attempt_recovery(uuid, uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function venue.read_payment_attempt_recovery(uuid, uuid, uuid) to service_role;

-- ORDER LOCK COORDINATION: cancel_pending_order already does
-- SELECT ... FROM venue."order" ... FOR UPDATE, then UPDATE status='cancelled'.
-- This trigger runs inside that transaction while the order lock is held. It
-- reads attempts in the same transaction; begin/attach/mark take the same order
-- lock before changing attempt identity.
revoke all on function venue.begin_payment_attempt(uuid, text, uuid, uuid, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function venue.attach_payment_attempt(uuid, text, uuid, uuid, uuid, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function venue.mark_payment_attempt(uuid, text, text) from public, anon, authenticated, service_role;
revoke all on function venue.mark_payment_attempt_by_pi(text, text, text) from public, anon, authenticated, service_role;
grant execute on function venue.begin_payment_attempt(uuid, text, uuid, uuid, integer, integer, integer, text) to service_role;
grant execute on function venue.attach_payment_attempt(uuid, text, uuid, uuid, uuid, integer, integer, integer, text) to service_role;
grant execute on function venue.mark_payment_attempt(uuid, text, text) to service_role;
grant execute on function venue.mark_payment_attempt_by_pi(text, text, text) to service_role;

-- READ ATTEMPT BINDING: service-only, no lock, no secret, no row fallback.
-- Exact order+buyer+session and order+PI+identity with authoritative quote.
-- Edge callers enforce operation-specific states: failed may be cancelled
-- after a Stripe read, but cannot expose a replay secret.
create function venue.read_payment_attempt_binding(
  p_order_id uuid, p_pi_id text, p_buyer_id uuid, p_session_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_order_buyer uuid;
  v_order_session uuid;
  v_order_total integer;
  v_order_currency text;
  v_count integer;
  v_a venue.payment_attempt%rowtype;
begin
  if p_order_id is null or p_pi_id is null or length(trim(p_pi_id)) = 0
     or p_buyer_id is null or p_session_id is null then
    raise exception 'invalid_input: binding identity required';
  end if;
  select buyer_id, event_session_id, total_minor, currency
    into v_order_buyer, v_order_session, v_order_total, v_order_currency
    from venue."order" where order_id = p_order_id;
  if v_order_buyer is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0002';
  end if;
  if v_order_buyer <> p_buyer_id or v_order_session is distinct from p_session_id then
    raise exception 'precondition_failed: binding order identity mismatch' using errcode = 'P0001';
  end if;
  select count(*) into v_count from venue.payment_attempt
   where order_id = p_order_id and pi_id = p_pi_id and buyer_id = p_buyer_id
     and session_id = p_session_id;
  if v_count <> 1 then
    raise exception 'precondition_failed: binding is missing or ambiguous (%)', v_count using errcode = 'P0001';
  end if;
  select * into v_a from venue.payment_attempt
   where order_id = p_order_id and pi_id = p_pi_id and buyer_id = p_buyer_id
     and session_id = p_session_id;
  if v_a.state not in ('open','processing','succeeded','failed') then
    raise exception 'precondition_failed: binding state % is unavailable', v_a.state using errcode = 'P0001';
  end if;
  if v_a.face_minor <> v_order_total or v_a.currency <> v_order_currency
     or v_a.amount_minor <> v_a.face_minor + v_a.buyer_fee_minor then
    raise exception 'precondition_failed: binding quote/identity mismatch' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'attempt_id', v_a.attempt_id, 'order_id', v_a.order_id, 'buyer_id', v_a.buyer_id,
    'session_id', v_a.session_id, 'pi_id', v_a.pi_id, 'state', v_a.state,
    'face_minor', v_a.face_minor, 'buyer_fee_minor', v_a.buyer_fee_minor,
    'amount_minor', v_a.amount_minor, 'currency', v_a.currency
  );
end;
$fn$;
revoke all on function venue.read_payment_attempt_binding(uuid, text, uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function venue.read_payment_attempt_binding(uuid, text, uuid, uuid) to service_role;

-- Read every tracked attempt for the scheduler's exact order. No create
-- request, customer data, or secret is returned. The cancel trigger remains
-- the final check for concurrent writers after this read.
create function venue.read_lapse_payment_attempts(p_order_id uuid, p_buyer_id uuid, p_session_id uuid)
returns jsonb
language plpgsql stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
begin
  perform 1 from venue."order" o
   where o.order_id = p_order_id and o.buyer_id = p_buyer_id
     and o.event_session_id = p_session_id and o.status = 'pending';
  if not found then
    raise exception 'precondition_failed: lapse order identity or state mismatch' using errcode = 'P0001';
  end if;
  select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) into v_result
    from (
      select order_id, buyer_id, session_id, pi_id, state, face_minor, buyer_fee_minor, amount_minor, currency
        from venue.payment_attempt where order_id = p_order_id
       order by attempt_id limit 101
    ) a;
  if jsonb_array_length(v_result) > 100 then
    raise exception 'precondition_failed: lapse attempt limit exceeded' using errcode = 'P0001';
  end if;
  return v_result;
end;
$fn$;
revoke all on function venue.read_lapse_payment_attempts(uuid, uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function venue.read_lapse_payment_attempts(uuid, uuid, uuid) to service_role;

-- A signed success delivery for a pre-cutover payment may be acknowledged
-- only if the immutable native ledger already links this exact settled order.
-- This read cannot finalize an order or write to the attempt ledger.
create function venue.is_settled_native_payment_replay(
  p_order_id uuid, p_buyer_id uuid, p_session_id uuid, p_pi_id text,
  p_payment_id uuid, p_amount_minor integer, p_currency text, p_livemode boolean
) returns boolean
language sql stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1 from kernel.payment_native n
    join venue."order" o on o.order_id = n.order_id
    join public.payments p on p.id = n.payment_id
    where n.order_id = p_order_id and n.payment_id = p_payment_id
      and n.amount_minor = o.total_minor and n.currency = p_currency
      and o.status in ('paid', 'partially_refunded', 'refunded')
      and o.buyer_id = p_buyer_id and o.event_session_id = p_session_id
      and o.currency = p_currency
      and p.mode = 'native_primary' and p.buyer_id = p_buyer_id
      and p.status in ('succeeded', 'refunded')
      and p.stripe_payment_intent_id = p_pi_id and p.stripe_livemode = p_livemode
      and p.total = p_amount_minor and p.total >= o.total_minor
      and not exists (select 1 from venue.payment_attempt a where a.pi_id = p_pi_id)
  );
$fn$;
revoke all on function venue.is_settled_native_payment_replay(uuid, uuid, uuid, text, uuid, integer, text, boolean) from public, anon, authenticated, service_role;
grant execute on function venue.is_settled_native_payment_replay(uuid, uuid, uuid, text, uuid, integer, text, boolean) to service_role;

create function venue.guard_order_cancel_attempts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    if exists (
      select 1 from venue.payment_attempt
       where order_id = new.order_id and state <> 'canceled'
    ) then
      raise exception 'precondition_failed: order has an unresolved payment attempt' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$fn$;
revoke all on function venue.guard_order_cancel_attempts() from public, anon, authenticated, service_role;

create trigger guard_order_cancel_attempts
  before update of status on venue."order"
  for each row execute function venue.guard_order_cancel_attempts();

commit;
