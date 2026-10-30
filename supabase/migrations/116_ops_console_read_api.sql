-- ============================================================================
-- 116_ops_console_read_api.sql — Operating Console package, part 2 of 3.
--
-- WHAT THIS MIGRATION IS. Additive only. The console's READ API: every function
-- lives in schema `ops`, is SECURITY DEFINER with an empty search_path, starts
-- with `perform ops.assert_reader()` (operator role via kernel.is_platform() +
-- an aal2/MFA session — the 085/096/106 step-up idiom) and returns jsonb. The
-- console is inherently cross-context, so these are the ONLY place where
-- payments, transfers, listings, profiles, auth.users, disputes, reports, risk
-- scores, webhook events, notify.* and cron.* are read together; the app never
-- joins them itself and holds no service-role key.
--
-- CONTRACT (design §3.3):
--   * Lists return {"items":[…],"next_cursor":text|null,"count_hint":int|null}
--     with keyset pagination on (created_at desc, id desc); the cursor is
--     base64(created_at_iso|id) via ops.cursor_encode/ops.cursor_decode.
--     p_limit is clamped to 1..200. count_hint is computed on the first page
--     only (p_cursor is null) and null afterwards.
--   * PII: email and phone are ALWAYS passed through ops.mask_email /
--     ops.mask_phone (auth.users.email, profiles.phone/phone_number,
--     transfers.delivery_email/delivery_phone). payments.stripe_client_secret
--     is stripped. profiles.stripe_connect_id / stripe_customer_id are never
--     returned — only their presence as a boolean.
--   * Money vocabulary (design §2.10): a captured payment ≠ a refund ≠ a
--     dispute ≠ a Stripe Transfer to the seller's connected account
--     (transfers.stripe_transfer_id). Bank payouts are NOT tracked and are
--     labelled as such. Nothing here is ever called a "payout" to a bank.
--   * Schema drift tolerance: production carries a few columns the migration
--     chain does not (profiles.stripe_payouts_enabled/stripe_charges_enabled/
--     stripe_connect_status, transfers.transfer_screenshot_path,
--     auth.users.last_sign_in_at). They are read through to_jsonb(row) ->> key
--     so the function compiles and runs on both shapes (null where absent).
--   * cron.job_run_details does not exist in the local rehearsal database; it
--     is read through dynamic SQL guarded by to_regclass(), and job_health()
--     reports "available": false when it is missing.
--
-- ZERO changes to public.* objects (Gate-2 parity untouched). No new indexes
-- on public tables; the queries lean on the indexes that already exist
-- (payments(status), payments(stripe_payment_intent_id), transfers(status),
-- transfers(expires_at) where pending, transfers(payout_review_status),
-- transfers(auto_release_at) where seller_sent, reports(created_at) where
-- pending, disputes(created_at) partial open, stripe_webhook_events(received_at)
-- where processed_at is null, notifications(user_id, created_at)).
--
-- DEPLOYMENT POSTURE: LOCAL / REHEARSAL. Depends on 115 only.
--
-- Rollback: supabase/rollbacks/116_ops_console_read_api_rollback.sql
-- Verification: select count(*) from pg_proc where pronamespace = 'ops'::regnamespace;  -- 115's 22 + 116's 38 = 60
--               select ops.today();  -- as an operator with aal2
-- Locks/runtime: CREATE FUNCTION only; no table is touched.
-- ============================================================================
begin;

-- ----------------------------------------------------------------------------
-- PART 1 — pagination + parsing helpers (internal: no grant to authenticated)
-- ----------------------------------------------------------------------------
create or replace function ops.clamp_limit(p_limit integer)
returns integer language sql immutable
as $ops$
  select greatest(1, least(200, coalesce(p_limit, 50)));
$ops$;
revoke all on function ops.clamp_limit(integer) from public, anon, authenticated;

-- base64("YYYY-MM-DDTHH24:MI:SS.USZ|<uuid>"), newline-free.
create or replace function ops.cursor_encode(p_ts timestamptz, p_id uuid)
returns text language sql immutable
as $ops$
  select case when p_ts is null or p_id is null then null
         else replace(encode(convert_to(
                to_char(p_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || p_id::text,
                'UTF8'), 'base64'), E'\n', '') end;
$ops$;
revoke all on function ops.cursor_encode(timestamptz, uuid) from public, anon, authenticated;

create or replace function ops.cursor_decode(p_cursor text, out ts timestamptz, out id uuid)
returns record language plpgsql immutable
as $ops$
declare v text; v_parts text[];
begin
  ts := null; id := null;
  if p_cursor is null or p_cursor = '' then return; end if;
  begin
    v := convert_from(decode(p_cursor, 'base64'), 'UTF8');
    v_parts := string_to_array(v, '|');
    if array_length(v_parts, 1) <> 2 then
      raise exception 'invalid_input: malformed cursor';
    end if;
    ts := (v_parts[1])::timestamptz;
    id := (v_parts[2])::uuid;
  exception when others then
    raise exception 'invalid_input: malformed cursor' using errcode = '22023';
  end;
end;
$ops$;
revoke all on function ops.cursor_decode(text) from public, anon, authenticated;

-- A uuid prefix (≥ 8 hex chars, hyphens optional) becomes an index-friendly
-- [lo, hi] range: pad with 0s / fs to 32 hex digits. Returns nulls otherwise.
create or replace function ops.uuid_prefix_range(p_q text, out lo uuid, out hi uuid)
returns record language plpgsql immutable
as $ops$
declare h text;
begin
  lo := null; hi := null;
  if p_q is null or p_q !~ '^[0-9a-fA-F-]{8,36}$' then return; end if;
  h := lower(replace(p_q, '-', ''));
  if length(h) < 8 or length(h) > 32 then return; end if;
  lo := rpad(h, 32, '0')::uuid;
  hi := rpad(h, 32, 'f')::uuid;
end;
$ops$;
revoke all on function ops.uuid_prefix_range(text) from public, anon, authenticated;

create or replace function ops.jsonb_text_array(p jsonb)
returns text[] language sql immutable
as $ops$
  select case when p is null or jsonb_typeof(p) <> 'array' then null
         else array(select jsonb_array_elements_text(p)) end;
$ops$;
revoke all on function ops.jsonb_text_array(jsonb) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- PART 2 — summaries + derived states (internal)
-- ----------------------------------------------------------------------------
-- Operator-facing label for a user id: admin label, display name, or masked email.
create or replace function ops.actor_label(p_user uuid)
returns text language sql stable security definer set search_path = ''
as $ops$
  select coalesce(
    (select a.label from public.admin_users a where a.user_id = p_user),
    (select nullif(p.display_name, '') from public.profiles p where p.id = p_user),
    (select ops.mask_email(u.email) from auth.users u where u.id = p_user));
$ops$;
revoke all on function ops.actor_label(uuid) from public, anon, authenticated;

-- Masked user card. Never the raw email / phone / stripe ids.
create or replace function ops.user_summary(p_user uuid)
returns jsonb language sql stable security definer set search_path = ''
as $ops$
  select jsonb_build_object(
           'id',                         p.id,
           'display_name',               p.display_name,
           'email_masked',               ops.mask_email(u.email),
           'phone_masked',               ops.mask_phone(coalesce(p.phone_number, p.phone)),
           'is_verified_seller',         p.is_verified_seller,
           'stripe_onboarding_complete', p.stripe_onboarding_complete,
           'stripe_payouts_enabled',     (to_jsonb(p) ->> 'stripe_payouts_enabled')::boolean,
           'created_at',                 p.created_at)
    from public.profiles p
    left join auth.users u on u.id = p.id
   where p.id = p_user;
$ops$;
revoke all on function ops.user_summary(uuid) from public, anon, authenticated;

create or replace function ops.listing_summary(p_listing uuid)
returns jsonb language sql stable security definer set search_path = ''
as $ops$
  select jsonb_build_object(
           'id', l.id, 'event_name', l.event_name, 'venue', l.venue, 'neighborhood', l.neighborhood,
           'event_date', l.event_date, 'event_time', l.event_time, 'ticket_type', l.ticket_type,
           'quantity', l.quantity, 'category', l.category, 'ticket_platform', l.ticket_platform,
           'status', l.status, 'auction_status', l.auction_status, 'proof_status', l.proof_status,
           'seller_id', l.seller_id, 'buy_now_enabled', l.buy_now_enabled, 'buy_now_price', l.buy_now_price,
           'starting_bid', l.starting_bid, 'current_bid', l.current_bid, 'bid_count', l.bid_count,
           'winner_user_id', l.winner_user_id, 'winning_bid_amount', l.winning_bid_amount,
           'ends_at', l.ends_at, 'sold_at', l.sold_at, 'created_at', l.created_at)
    from public.listings l where l.id = p_listing;
$ops$;
revoke all on function ops.listing_summary(uuid) from public, anon, authenticated;

-- payment row as jsonb minus the Stripe client secret (never useful to an operator).
create or replace function ops.payment_json(p public.payments)
returns jsonb language sql immutable
as $ops$
  select to_jsonb(p) - 'stripe_client_secret';
$ops$;
revoke all on function ops.payment_json(public.payments) from public, anon, authenticated;

-- transfer row as jsonb with the buyer's delivery contact masked.
create or replace function ops.transfer_json(t public.transfers)
returns jsonb language sql immutable
as $ops$
  select case when t.id is null then null
         else to_jsonb(t) || jsonb_build_object(
                'delivery_email', ops.mask_email(t.delivery_email),
                'delivery_phone', ops.mask_phone(t.delivery_phone)) end;
$ops$;
revoke all on function ops.transfer_json(public.transfers) from public, anon, authenticated;

-- SELLER FUNDS STATE — where the seller's share of a captured payment sits.
-- Derived from the transfer (seller obligation) + payment, evaluated top-down:
--   not_applicable                 payment absent / pending / processing / failed,
--                                  or a succeeded payment that has no transfer
--                                  row yet (no seller obligation exists)
--   refunded                       payment.status = refunded (buyer made whole)
--   reversed                       transfer.status = reversed (connected-account
--                                  transfer was reversed after a lost dispute)
--   expired                        transfer.status = expired (seller never sent;
--                                  the expiry job refunds the buyer)
--   released_to_connected_account  transfers.stripe_transfer_id IS NOT NULL —
--                                  the ONLY state that means money moved to the
--                                  seller's Stripe connected account. This is
--                                  not a bank payout (bank payouts are not
--                                  tracked).
--   frozen_dispute                 transfer disputed and not yet resolved
--   awaiting_delivery              transfer.status = pending (seller has not sent)
--   manual_review                  payout_review_status = manual_review
--   held                           payout_review_status = held, or a risk hold
--                                  (payout_hold_until) still in the future
--   release_scheduled              buyer confirmed / auto-released / marked
--                                  released (payout_released_at) but the
--                                  payout worker has not yet created the Stripe
--                                  Transfer (stripe_transfer_id still null)
--   awaiting_confirmation          seller_sent, waiting on the buyer / auto-release
create or replace function ops.funds_state(t public.transfers, p public.payments)
returns text language sql stable
as $ops$
  select case
    when p.id is null or p.status in ('pending','processing','failed') then 'not_applicable'
    when p.status = 'refunded'                                          then 'refunded'
    when t.id is null                                                   then 'not_applicable'
    when t.status = 'reversed'                                          then 'reversed'
    when t.status = 'expired'                                           then 'expired'
    when t.stripe_transfer_id is not null                               then 'released_to_connected_account'
    -- dispute decided for the buyer: money is owed back but no refund has landed
    when t.dispute_resolution in ('resolved_buyer_refunded','resolved_partial_refund')
      and p.status <> 'refunded'                                        then 'refund_pending'
    when t.status = 'disputed'
      or (t.disputed_at is not null and t.dispute_resolved_at is null)  then 'frozen_dispute'
    when t.status = 'pending'                                           then 'awaiting_delivery'
    when t.payout_review_status = 'manual_review'                       then 'manual_review'
    when t.payout_review_status = 'held'
      or (t.payout_hold_until is not null and t.payout_hold_until > now()) then 'held'
    when t.status in ('buyer_confirmed','auto_released')
      or t.payout_released_at is not null                               then 'release_scheduled'
    else 'awaiting_confirmation' end;
$ops$;
revoke all on function ops.funds_state(public.transfers, public.payments) from public, anon, authenticated;

-- Compact order row (payment + its transfer) used by every list and by subjects.
create or replace function ops.order_row(p public.payments, t public.transfers)
returns jsonb language sql stable security definer set search_path = ''
as $ops$
  select jsonb_build_object(
    'payment_id',               p.id,
    'created_at',               p.created_at,
    'payment_status',           p.status,
    'mode',                     p.mode,
    'amount',                   p.amount,
    'buyer_fee',                p.buyer_fee,
    'seller_fee',               p.seller_fee,
    'total',                    p.total,
    'stripe_payment_intent_id', p.stripe_payment_intent_id,
    'stripe_livemode',          p.stripe_livemode,
    'paid_at',                  p.paid_at,
    'failed_at',                p.failed_at,
    'refunded_at',              p.refunded_at,
    'stripe_refund_id',         p.stripe_refund_id,
    'listing_id',               p.listing_id,
    'event_name',               (select l.event_name from public.listings l where l.id = p.listing_id),
    'event_date',               (select l.event_date from public.listings l where l.id = p.listing_id),
    'buyer',                    jsonb_build_object('id', p.buyer_id,
                                  'display_name', (select pr.display_name from public.profiles pr where pr.id = p.buyer_id)),
    'seller',                   jsonb_build_object('id', p.seller_id,
                                  'display_name', (select pr.display_name from public.profiles pr where pr.id = p.seller_id)),
    'transfer_id',              t.id,
    'transfer_status',          t.status,
    'transfer_method',          t.transfer_method,
    'transfer_expires_at',      t.expires_at,
    'seller_sent_at',           t.seller_sent_at,
    'buyer_confirmed_at',       t.buyer_confirmed_at,
    'auto_release_at',          t.auto_release_at,
    'disputed_at',              t.disputed_at,
    'dispute_resolved_at',      t.dispute_resolved_at,
    'payout_review_status',     t.payout_review_status,
    'payout_risk_tier',         t.payout_risk_tier,
    'payout_hold_until',        t.payout_hold_until,
    'payout_released_at',       t.payout_released_at,
    'stripe_transfer_id',       t.stripe_transfer_id,
    'seller_funds_state',       ops.funds_state(t, p),
    'open_cases',               (select count(*) from ops."case" c
                                  where c.status not in ('resolved','dismissed')
                                    and ((c.subject_kind = 'payment'  and c.subject_id = p.id)
                                      or (c.subject_kind = 'transfer' and c.subject_id = t.id)
                                      or (c.subject_kind = 'listing'  and c.subject_id = p.listing_id))));
$ops$;
revoke all on function ops.order_row(public.payments, public.transfers) from public, anon, authenticated;

-- Human label for a case/action subject.
create or replace function ops.subject_label(p_kind text, p_id uuid, p_ref text)
returns text language sql stable security definer set search_path = ''
as $ops$
  select case p_kind
    when 'payment'  then (select coalesce(l.event_name, 'payment ' || left(p.id::text, 8)) || ' · $' || (p.total / 100.0)::numeric(12,2)::text
                            from public.payments p left join public.listings l on l.id = p.listing_id where p.id = p_id)
    when 'transfer' then (select coalesce(l.event_name, 'transfer ' || left(t.id::text, 8)) || ' · ' || t.status
                            from public.transfers t left join public.listings l on l.id = t.listing_id where t.id = p_id)
    when 'listing'  then (select l.event_name || ' · ' || coalesce(l.auction_status, l.status) from public.listings l where l.id = p_id)
    when 'user'     then (select coalesce(pr.display_name, 'user ' || left(pr.id::text, 8)) from public.profiles pr where pr.id = p_id)
    when 'report'   then (select r.target_type || ' report · ' || r.reason from public.reports r where r.id = p_id)
    when 'dispute'  then (select 'stripe dispute ' || d.stripe_dispute_id || ' · ' || d.status from public.disputes d where d.id = p_id)
    when 'case'     then (select c.title from ops."case" c where c.id = p_id)
    when 'job'      then 'job ' || coalesce(p_ref, '?')
    when 'webhook_event' then 'webhook ' || coalesce(p_ref, '?')
    when 'setting'  then 'setting ' || coalesce(p_ref, '?')
    else coalesce(p_ref, p_id::text) end;
$ops$;
revoke all on function ops.subject_label(text, uuid, text) from public, anon, authenticated;

-- Compact subject record for case_detail / action_detail.
create or replace function ops.subject_summary(p_kind text, p_id uuid, p_ref text)
returns jsonb language sql stable security definer set search_path = ''
as $ops$
  select case p_kind
    when 'payment'  then (select ops.order_row(p, t) from public.payments p
                            left join public.transfers t on t.payment_id = p.id where p.id = p_id)
    when 'transfer' then (select ops.order_row(p, t) from public.transfers t
                            left join public.payments p on p.id = t.payment_id where t.id = p_id)
    when 'listing'  then ops.listing_summary(p_id)
    when 'user'     then ops.user_summary(p_id)
    when 'report'   then (select to_jsonb(r) from public.reports r where r.id = p_id)
    when 'dispute'  then (select to_jsonb(d) from public.disputes d where d.id = p_id)
    when 'job'      then (select to_jsonb(j) from ops.job_state j where j.job_name = p_ref)
    when 'webhook_event' then (select to_jsonb(w) from public.stripe_webhook_events w where w.event_id = p_ref)
    when 'case'     then (select to_jsonb(c) from ops."case" c where c.id = p_id)
    when 'setting'  then (select to_jsonb(s) from ops.setting s where s.key = p_ref)
    else null end;
$ops$;
revoke all on function ops.subject_summary(text, uuid, text) from public, anon, authenticated;

create or replace function ops.case_row(c ops."case")
returns jsonb language sql stable security definer set search_path = ''
as $ops$
  select to_jsonb(c) || jsonb_build_object(
           'subject_label',  ops.subject_label(c.subject_kind, c.subject_id, c.subject_ref),
           'assignee_label', ops.actor_label(c.assignee),
           'note_count',     (select count(*) from ops.case_note n where n.case_id = c.id));
$ops$;
revoke all on function ops.case_row(ops."case") from public, anon, authenticated;

create or replace function ops.action_row(a ops.action)
returns jsonb language sql stable security definer set search_path = ''
as $ops$
  select to_jsonb(a) || jsonb_build_object(
           'requested_by_label', ops.actor_label(a.requested_by),
           'subject_label',      ops.subject_label(a.subject_kind, a.subject_id, a.subject_ref));
$ops$;
revoke all on function ops.action_row(ops.action) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- PART 3 — search
-- ----------------------------------------------------------------------------
-- Hits {kind, id, label, sub, status}. Exact matches for Stripe ids (pi_ / tr_
-- / re_ / dp_), an index-friendly uuid-prefix range (≥ 8 hex chars) across
-- payments / transfers / listings / users / disputes, exact email (auth.users)
-- and exact phone, and ilike on listing event_name / user display_name.
create or replace function ops.search(p_q text, p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  q      text := trim(coalesce(p_q, ''));
  lim    integer := greatest(1, least(100, coalesce(p_limit, 20)));
  r      record;
  v_hits jsonb;
begin
  perform ops.assert_reader();
  if length(q) < 2 then
    return jsonb_build_object('q', q, 'hits', '[]'::jsonb);
  end if;
  select * into r from ops.uuid_prefix_range(q);

  with hits as (
    -- Stripe ids
    select 'payment' as kind, p.id, coalesce(l.event_name, 'payment') as label, p.stripe_payment_intent_id as sub, p.status, p.created_at
      from public.payments p left join public.listings l on l.id = p.listing_id
     where q like 'pi\_%' and p.stripe_payment_intent_id = q
    union all
    select 'payment', p.id, coalesce(l.event_name, 'payment'), 'refund ' || p.stripe_refund_id, p.status, p.created_at
      from public.payments p left join public.listings l on l.id = p.listing_id
     where q like 're\_%' and p.stripe_refund_id = q
    union all
    select 'transfer', t.id, coalesce(l.event_name, 'transfer'), 'stripe transfer ' || t.stripe_transfer_id, t.status, t.created_at
      from public.transfers t left join public.listings l on l.id = t.listing_id
     where q like 'tr\_%' and t.stripe_transfer_id = q
    union all
    select 'dispute', d.id, 'stripe dispute ' || d.stripe_dispute_id, coalesce(d.reason, ''), d.status, d.created_at
      from public.disputes d
     where q like 'dp\_%' and d.stripe_dispute_id = q
    -- uuid prefix ranges (btree pkey scans)
    union all
    select 'payment', p.id, coalesce(l.event_name, 'payment'), p.stripe_payment_intent_id, p.status, p.created_at
      from public.payments p left join public.listings l on l.id = p.listing_id
     where r.lo is not null and p.id between r.lo and r.hi
    union all
    select 'transfer', t.id, coalesce(l.event_name, 'transfer'), t.transfer_method, t.status, t.created_at
      from public.transfers t left join public.listings l on l.id = t.listing_id
     where r.lo is not null and t.id between r.lo and r.hi
    union all
    select 'listing', l.id, l.event_name, l.venue, coalesce(l.auction_status, l.status), l.created_at
      from public.listings l
     where r.lo is not null and l.id between r.lo and r.hi
    union all
    select 'user', pr.id, coalesce(pr.display_name, ''), ops.mask_email(u.email), null::text, pr.created_at
      from public.profiles pr left join auth.users u on u.id = pr.id
     where r.lo is not null and pr.id between r.lo and r.hi
    union all
    select 'dispute', d.id, 'stripe dispute ' || d.stripe_dispute_id, coalesce(d.reason, ''), d.status, d.created_at
      from public.disputes d
     where r.lo is not null and d.id between r.lo and r.hi
    -- exact email / phone
    union all
    select 'user', pr.id, coalesce(pr.display_name, ''), ops.mask_email(u.email), null::text, pr.created_at
      from auth.users u join public.profiles pr on pr.id = u.id
     where position('@' in q) > 1 and lower(u.email) = lower(q)
    union all
    select 'user', pr.id, coalesce(pr.display_name, ''), ops.mask_phone(coalesce(pr.phone_number, pr.phone)), null::text, pr.created_at
      from public.profiles pr
     where q ~ '^\+?[0-9][0-9 ()-]{6,}$' and (pr.phone_number = q or pr.phone = q)
    -- text
    union all
    select 'listing', l.id, l.event_name, l.venue, coalesce(l.auction_status, l.status), l.created_at
      from public.listings l
     where r.lo is null and position('@' in q) = 0 and l.event_name ilike '%' || q || '%'
    union all
    select 'user', pr.id, coalesce(pr.display_name, ''), null::text, null::text, pr.created_at
      from public.profiles pr
     where r.lo is null and position('@' in q) = 0 and pr.display_name ilike '%' || q || '%'
  ),
  ranked as (
    select distinct on (kind, id) kind, id, label, sub, status, created_at
      from hits order by kind, id, created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'id', id, 'label', label, 'sub', sub, 'status', status)
                            order by created_at desc), '[]'::jsonb)
    into v_hits
    from (select * from ranked order by created_at desc limit lim) s;

  return jsonb_build_object('q', q, 'hits', v_hits);
end;
$ops$;
revoke all on function ops.search(text, integer) from public, anon, authenticated;
grant execute on function ops.search(text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 4 — orders
-- ----------------------------------------------------------------------------
-- filters: payment_status text[], transfer_status text[], payout_state
-- (released|pending_release|held|manual_review|none), has_open_case bool,
-- from/to timestamptz, q (uuid prefix ≥ 8 on payment/transfer/listing id,
-- exact pi_/tr_/re_ id, or event_name ilike).
create or replace function ops.list_orders(p_filters jsonb default '{}'::jsonb, p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  f          jsonb := coalesce(p_filters, '{}'::jsonb);
  lim        integer := ops.clamp_limit(p_limit);
  c          record;
  r          record;
  v_pstat    text[] := ops.jsonb_text_array(f -> 'payment_status');
  v_tstat    text[] := ops.jsonb_text_array(f -> 'transfer_status');
  v_pay      text   := nullif(f ->> 'payout_state', '');
  v_case     boolean := (f ->> 'has_open_case')::boolean;
  v_from     timestamptz := nullif(f ->> 'from', '')::timestamptz;
  v_to       timestamptz := nullif(f ->> 'to', '')::timestamptz;
  v_q        text := nullif(trim(coalesce(f ->> 'q', '')), '');
  v_items    jsonb;
  v_last_ts  timestamptz;
  v_last_id  uuid;
  v_n        integer;
  v_count    integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  select * into r from ops.uuid_prefix_range(v_q);
  if v_pay is not null and v_pay not in ('released','pending_release','held','manual_review','none') then
    raise exception 'invalid_input: payout_state must be released|pending_release|held|manual_review|none';
  end if;

  with page as (
    select p.created_at as created_at, p.id as id, ops.order_row(p, t) as item
    from public.payments p
    left join public.transfers t on t.payment_id = p.id
   where (v_pstat is null or p.status = any(v_pstat))
     and (v_tstat is null or t.status = any(v_tstat))
     and (v_from is null or p.created_at >= v_from)
     and (v_to   is null or p.created_at <  v_to)
     and (v_pay is null or case v_pay
            when 'released'        then t.stripe_transfer_id is not null
            when 'held'            then t.stripe_transfer_id is null and t.payout_review_status = 'held'
            when 'manual_review'   then t.stripe_transfer_id is null and t.payout_review_status = 'manual_review'
            when 'pending_release' then t.stripe_transfer_id is null and t.payout_review_status is null
                                        and t.status in ('seller_sent','buyer_confirmed','auto_released')
            else t.stripe_transfer_id is null and t.payout_review_status is null
                 and (t.id is null or t.status not in ('seller_sent','buyer_confirmed','auto_released')) end)
     and (v_case is null or v_case = exists (
            select 1 from ops."case" oc
             where oc.status not in ('resolved','dismissed')
               and ((oc.subject_kind = 'payment'  and oc.subject_id = p.id)
                 or (oc.subject_kind = 'transfer' and oc.subject_id = t.id)
                 or (oc.subject_kind = 'listing'  and oc.subject_id = p.listing_id))))
     and (v_q is null
          or (r.lo is not null and (p.id between r.lo and r.hi or t.id between r.lo and r.hi or p.listing_id between r.lo and r.hi))
          or (v_q like 'pi\_%' and p.stripe_payment_intent_id = v_q)
          or (v_q like 're\_%' and p.stripe_refund_id = v_q)
          or (v_q like 'tr\_%' and t.stripe_transfer_id = v_q)
          or (r.lo is null and v_q not like 'pi\_%' and v_q not like 're\_%' and v_q not like 'tr\_%'
              and exists (select 1 from public.listings l where l.id = p.listing_id and l.event_name ilike '%' || v_q || '%')))
     and (c.ts is null or (p.created_at, p.id) < (c.ts, c.id))
   order by p.created_at desc, p.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null then
    select count(*) into v_count
      from public.payments p
      left join public.transfers t on t.payment_id = p.id
     where (v_pstat is null or p.status = any(v_pstat))
       and (v_tstat is null or t.status = any(v_tstat))
       and (v_from is null or p.created_at >= v_from)
       and (v_to   is null or p.created_at <  v_to)
       and v_pay is null and v_case is null and v_q is null;
    -- count_hint is only cheap for status/date filters; null for the rest
    if v_pay is not null or v_case is not null or v_q is not null then v_count := null; end if;
  end if;

  return jsonb_build_object(
    'items', v_items,
    'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
    'count_hint', v_count);
end;
$ops$;
revoke all on function ops.list_orders(jsonb, text, integer) from public, anon, authenticated;
grant execute on function ops.list_orders(jsonb, text, integer) to authenticated;

-- Everything about one order. Evidence is returned as storage PATHS only; the
-- app signs them (storage.createSignedUrl) with the operator's own session:
--   transfer_evidence_path      bucket proof-docs   (private; seller's sent proof)
--   transfer_screenshot_path    bucket proof-docs   (legacy column, production only)
--   dispute_evidence_path       bucket proof-docs   (private; buyer's dispute proof)
--   proof_of_ownership_path     bucket proof-docs   (private; listing proof)
--   cover_image_path            bucket auction-media (public) — in listing summary
create or replace function ops.order_detail(p_payment_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  p public.payments%rowtype;
  t public.transfers%rowtype;
  v_listing_id uuid;
begin
  perform ops.assert_reader();
  select * into p from public.payments where id = p_payment_id;
  if not found then
    raise exception 'not_found: payment % does not exist', p_payment_id using errcode = 'P0002';
  end if;
  select * into t from public.transfers where payment_id = p.id;
  v_listing_id := p.listing_id;

  return jsonb_build_object(
    'payment',  ops.payment_json(p),
    'transfer', ops.transfer_json(t),
    'listing',  ops.listing_summary(v_listing_id),
    'buyer',    ops.user_summary(p.buyer_id),
    'seller',   ops.user_summary(p.seller_id),
    'disputes', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from public.disputes d
                           where d.payment_id = p.id or (t.id is not null and d.transfer_id = t.id)), '[]'::jsonb),
    'dispute_resolutions', coalesce((select jsonb_agg(to_jsonb(dr) || jsonb_build_object('actor_label', ops.actor_label(dr.actor_id)) order by dr.created_at)
                                       from public.dispute_resolutions dr where dr.transfer_id = t.id), '[]'::jsonb),
    'payout_decisions', coalesce((select jsonb_agg(to_jsonb(pd) order by pd.decided_at) from public.payout_decisions pd
                                   where pd.payment_id = p.id or pd.transfer_id = t.id), '[]'::jsonb),
    'refund', jsonb_build_object(
                'payment_status',   p.status,
                'refunded_at',      p.refunded_at,
                'stripe_refund_id', p.stripe_refund_id,
                'refund_actions',   coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from ops.action a
                                               where a.action_type = 'refund_execute' and a.subject_kind = 'payment' and a.subject_id = p.id), '[]'::jsonb)),
    'seller_funds_state', ops.funds_state(t, p),
    'cases', coalesce((select jsonb_agg(ops.case_row(c) order by c.created_at desc) from ops."case" c
                        where (c.subject_kind = 'payment'  and c.subject_id = p.id)
                           or (c.subject_kind = 'transfer' and c.subject_id = t.id)
                           or (c.subject_kind = 'listing'  and c.subject_id = v_listing_id)), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from (
                          select * from ops.action a
                           where (a.subject_kind = 'payment'  and a.subject_id = p.id)
                              or (a.subject_kind = 'transfer' and a.subject_id = t.id)
                              or (a.subject_kind = 'listing'  and a.subject_id = v_listing_id)
                           order by a.requested_at desc limit 50) a), '[]'::jsonb),
    'evidence', jsonb_build_object(
                  'transfer_evidence_path',   jsonb_build_object('bucket', 'proof-docs', 'path', t.transfer_evidence_path),
                  'transfer_screenshot_path', jsonb_build_object('bucket', 'proof-docs', 'path', to_jsonb(t) ->> 'transfer_screenshot_path'),
                  'dispute_evidence_path',    jsonb_build_object('bucket', 'proof-docs', 'path', t.dispute_evidence_path),
                  'proof_of_ownership_path',  jsonb_build_object('bucket', 'proof-docs',
                                                'path', (select l.proof_of_ownership_path from public.listings l where l.id = v_listing_id))),
    'bank_payout', jsonb_build_object('tracked', false, 'note', 'Bank payouts from the connected account are not tracked (payout.paid webhook only logged).'));
end;
$ops$;
revoke all on function ops.order_detail(uuid) from public, anon, authenticated;
grant execute on function ops.order_detail(uuid) to authenticated;

-- {"events":[{at, source, kind, label, ref}]} ordered by at. Sources:
-- payment, transfer, payout_decision, dispute, dispute_resolution,
-- notification (best effort: rows for buyer/seller whose metadata or link
-- references the listing / transfer / payment), ops_action, ops_case.
-- stripe_webhook_events carries no payment linkage (event_id/type only), so
-- webhook receipts cannot be placed on an order timeline — by design.
create or replace function ops.order_timeline(p_payment_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  p public.payments%rowtype;
  t public.transfers%rowtype;
  v_events jsonb;
begin
  perform ops.assert_reader();
  select * into p from public.payments where id = p_payment_id;
  if not found then
    raise exception 'not_found: payment % does not exist', p_payment_id using errcode = 'P0002';
  end if;
  select * into t from public.transfers where payment_id = p.id;

  with ev(at, source, kind, label, ref) as (
    select p.created_at,  'payment', 'created',  'Payment created (' || p.mode || ')', p.id::text
    union all select p.paid_at,     'payment', 'paid',     'Payment captured $' || (p.total / 100.0)::numeric(12,2)::text, p.stripe_payment_intent_id
    union all select p.failed_at,   'payment', 'failed',   'Payment failed', p.stripe_payment_intent_id
    union all select p.refunded_at, 'payment', 'refunded', 'Payment refunded', p.stripe_refund_id
    union all select t.created_at,          'transfer', 'created',          'Transfer obligation created', t.id::text
    union all select t.seller_sent_at,      'transfer', 'seller_sent',      'Seller marked tickets sent', t.transfer_evidence_path
    union all select t.buyer_viewed_at,     'transfer', 'buyer_viewed',     'Buyer viewed the transfer', null
    union all select t.buyer_confirmed_at,  'transfer', 'buyer_confirmed',  'Buyer confirmed receipt', null
    union all select t.disputed_at,         'transfer', 'disputed',         'Buyer opened a dispute (' || coalesce(t.dispute_reason, '?') || ')', t.dispute_evidence_path
    union all select t.dispute_resolved_at, 'transfer', 'dispute_resolved', 'Dispute resolved: ' || coalesce(t.dispute_resolution, '?'), t.dispute_resolved_by::text
    union all select t.expired_at,          'transfer', 'expired',          'Transfer expired (seller did not send)', null
    union all select t.payout_released_at,  'transfer', 'payout_released',  case when t.stripe_transfer_id is not null
                                                                                 then 'Seller funds released to connected account'
                                                                                 else 'Release recorded; connected-account transfer pending' end, t.stripe_transfer_id
    union all select pd.decided_at, 'payout_decision', pd.decision, 'Payout decision: ' || pd.decision || ' (' || pd.risk_tier || ')', pd.id::text
                from public.payout_decisions pd where pd.payment_id = p.id or (t.id is not null and pd.transfer_id = t.id)
    union all select d.created_at, 'dispute', 'created', 'Stripe dispute opened: ' || coalesce(d.reason, '?'), d.stripe_dispute_id
                from public.disputes d where d.payment_id = p.id or (t.id is not null and d.transfer_id = t.id)
    union all select d.evidence_due_by, 'dispute', 'evidence_due', 'Stripe dispute evidence due', d.stripe_dispute_id
                from public.disputes d where d.payment_id = p.id or (t.id is not null and d.transfer_id = t.id)
    union all select dr.created_at, 'dispute_resolution', dr.outcome, 'Resolution recorded: ' || dr.outcome
                                      || case when dr.refund_required then ' (refund required)' else '' end, dr.id::text
                from public.dispute_resolutions dr where t.id is not null and dr.transfer_id = t.id
    union all select n.created_at, 'notification', n.type, coalesce(n.title, n.type) || ' → ' || coalesce(ops.actor_label(n.user_id), ''), n.id::text
                from public.notifications n
               where n.user_id in (p.buyer_id, p.seller_id)
                 and (n.metadata ->> 'listing_id'  = p.listing_id::text
                   or n.metadata ->> 'payment_id'  = p.id::text
                   or (t.id is not null and n.metadata ->> 'transfer_id' = t.id::text)
                   or (p.listing_id is not null and n.link like '%' || p.listing_id::text || '%')
                   or (t.id is not null and n.link like '%' || t.id::text || '%'))
    union all select a.requested_at, 'ops_action', 'requested', a.action_type || ' requested by ' || coalesce(ops.actor_label(a.requested_by), '?'), a.id::text
                from ops.action a
               where (a.subject_kind = 'payment' and a.subject_id = p.id)
                  or (a.subject_kind = 'transfer' and a.subject_id = t.id)
                  or (a.subject_kind = 'listing' and a.subject_id = p.listing_id)
    union all select a.completed_at, 'ops_action', a.state, a.action_type || ' ' || a.state, a.id::text
                from ops.action a
               where a.completed_at is not null
                 and ((a.subject_kind = 'payment' and a.subject_id = p.id)
                   or (a.subject_kind = 'transfer' and a.subject_id = t.id)
                   or (a.subject_kind = 'listing' and a.subject_id = p.listing_id))
    union all select c.detected_at, 'ops_case', 'detected', 'Case opened: ' || c.title, c.id::text
                from ops."case" c
               where (c.subject_kind = 'payment' and c.subject_id = p.id)
                  or (c.subject_kind = 'transfer' and c.subject_id = t.id)
                  or (c.subject_kind = 'listing' and c.subject_id = p.listing_id)
    union all select c.resolved_at, 'ops_case', c.status, 'Case ' || c.status || ': ' || c.title, c.id::text
                from ops."case" c
               where c.resolved_at is not null
                 and ((c.subject_kind = 'payment' and c.subject_id = p.id)
                   or (c.subject_kind = 'transfer' and c.subject_id = t.id)
                   or (c.subject_kind = 'listing' and c.subject_id = p.listing_id))
  )
  select coalesce(jsonb_agg(jsonb_build_object('at', at, 'source', source, 'kind', kind, 'label', label, 'ref', ref)
                            order by at, source, kind), '[]'::jsonb)
    into v_events
    from ev where at is not null;

  return jsonb_build_object('payment_id', p.id, 'events', v_events,
           'note', 'Stripe webhook receipts are not linkable to an order (stripe_webhook_events has no payment reference).');
end;
$ops$;
revoke all on function ops.order_timeline(uuid) from public, anon, authenticated;
grant execute on function ops.order_timeline(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 5 — cases
-- ----------------------------------------------------------------------------
-- filters: status text[], case_type text[], priority text[], assignee
-- (uuid | 'me' | 'unassigned'), subject_kind, subject_id.
create or replace function ops.list_cases(p_filters jsonb default '{}'::jsonb, p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  v_status text[] := ops.jsonb_text_array(f -> 'status');
  v_type   text[] := ops.jsonb_text_array(f -> 'case_type');
  v_prio   text[] := ops.jsonb_text_array(f -> 'priority');
  v_assg   text   := nullif(f ->> 'assignee', '');
  v_assg_id uuid;
  v_unassigned boolean := false;
  v_skind  text := nullif(f ->> 'subject_kind', '');
  v_sid    uuid := nullif(f ->> 'subject_id', '')::uuid;
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  if v_assg = 'me' then v_assg_id := auth.uid();
  elsif v_assg = 'unassigned' then v_unassigned := true;
  elsif v_assg is not null then v_assg_id := v_assg::uuid; end if;

  with page as (
    select k.created_at as created_at, k.id as id, ops.case_row(k) as item
    from ops."case" k
   where (v_status is null or k.status = any(v_status))
     and (v_type   is null or k.case_type = any(v_type))
     and (v_prio   is null or k.priority = any(v_prio))
     and (v_assg_id is null or k.assignee = v_assg_id)
     and (not v_unassigned or k.assignee is null)
     and (v_skind is null or k.subject_kind = v_skind)
     and (v_sid   is null or k.subject_id = v_sid)
     and (c.ts is null or (k.created_at, k.id) < (c.ts, c.id))
   order by k.created_at desc, k.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null then
    select count(*) into v_count from ops."case" k
     where (v_status is null or k.status = any(v_status))
       and (v_type   is null or k.case_type = any(v_type))
       and (v_prio   is null or k.priority = any(v_prio))
       and (v_assg_id is null or k.assignee = v_assg_id)
       and (not v_unassigned or k.assignee is null)
       and (v_skind is null or k.subject_kind = v_skind)
       and (v_sid   is null or k.subject_id = v_sid);
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$ops$;
revoke all on function ops.list_cases(jsonb, text, integer) from public, anon, authenticated;
grant execute on function ops.list_cases(jsonb, text, integer) to authenticated;

create or replace function ops.case_detail(p_case_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare k ops."case"%rowtype;
begin
  perform ops.assert_reader();
  select * into k from ops."case" where id = p_case_id;
  if not found then
    raise exception 'not_found: case % does not exist', p_case_id using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'case',    ops.case_row(k),
    'notes',   coalesce((select jsonb_agg(to_jsonb(n) || jsonb_build_object('author_label', ops.actor_label(n.author)) order by n.created_at)
                           from ops.case_note n where n.case_id = k.id), '[]'::jsonb),
    'events',  coalesce((select jsonb_agg(to_jsonb(e) || jsonb_build_object('actor_label', ops.actor_label(e.actor)) order by e.created_at)
                           from ops.case_event e where e.case_id = k.id), '[]'::jsonb),
    'subject', ops.subject_summary(k.subject_kind, k.subject_id, k.subject_ref),
    'actions', coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from (
                          select * from ops.action a
                           where (a.subject_kind = 'case' and a.subject_id = k.id)
                              or (k.subject_id is not null and a.subject_kind = k.subject_kind and a.subject_id = k.subject_id)
                              or (k.subject_id is null and k.subject_ref is not null and a.subject_kind = k.subject_kind and a.subject_ref = k.subject_ref)
                           order by a.requested_at desc limit 100) a), '[]'::jsonb),
    'operators', ops.operators());
end;
$ops$;
revoke all on function ops.case_detail(uuid) from public, anon, authenticated;
grant execute on function ops.case_detail(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 6 — users
-- ----------------------------------------------------------------------------
-- filters: q (display_name ilike, exact email via auth.users, exact phone),
-- is_seller bool (has a listing or Stripe onboarding), blocked bool
-- (seller_risk_scores.is_listing_blocked).
create or replace function ops.list_users(p_filters jsonb default '{}'::jsonb, p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  r        record;
  v_q      text := nullif(trim(coalesce(f ->> 'q', '')), '');
  v_seller boolean := (f ->> 'is_seller')::boolean;
  v_blocked boolean := (f ->> 'blocked')::boolean;
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  select * into r from ops.uuid_prefix_range(v_q);

  with page as (
    select pr.created_at as created_at, pr.id as id,
         ops.user_summary(pr.id) || jsonb_build_object(
           'is_listing_blocked', coalesce(rs.is_listing_blocked, false),
           'risk_tier',          rs.risk_tier,
           'listing_count',      (select count(*) from public.listings l where l.seller_id = pr.id),
           'open_cases',         (select count(*) from ops."case" oc where oc.subject_kind = 'user' and oc.subject_id = pr.id
                                                                       and oc.status not in ('resolved','dismissed'))) as item
    from public.profiles pr
    left join public.seller_risk_scores rs on rs.seller_id = pr.id
   where (v_q is null
          or (r.lo is not null and pr.id between r.lo and r.hi)
          or (position('@' in v_q) > 1 and exists (select 1 from auth.users u where u.id = pr.id and lower(u.email) = lower(v_q)))
          or (pr.phone_number = v_q or pr.phone = v_q)
          or (r.lo is null and position('@' in v_q) = 0 and pr.display_name ilike '%' || v_q || '%'))
     and (v_seller is null or v_seller = (pr.stripe_onboarding_complete
                                          or exists (select 1 from public.listings l where l.seller_id = pr.id)))
     and (v_blocked is null or v_blocked = coalesce(rs.is_listing_blocked, false))
     and (c.ts is null or (pr.created_at, pr.id) < (c.ts, c.id))
   order by pr.created_at desc, pr.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null and v_q is null and v_seller is null then
    select count(*) into v_count from public.profiles pr
      left join public.seller_risk_scores rs on rs.seller_id = pr.id
     where (v_blocked is null or v_blocked = coalesce(rs.is_listing_blocked, false));
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$ops$;
revoke all on function ops.list_users(jsonb, text, integer) from public, anon, authenticated;
grant execute on function ops.list_users(jsonb, text, integer) to authenticated;

create or replace function ops.user_detail(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  pr   public.profiles%rowtype;
  v_pj jsonb;
  v_u  jsonb;
begin
  perform ops.assert_reader();
  select * into pr from public.profiles where id = p_user_id;
  if not found then
    raise exception 'not_found: user % does not exist', p_user_id using errcode = 'P0002';
  end if;
  v_pj := to_jsonb(pr);
  select to_jsonb(u) into v_u from auth.users u where u.id = pr.id;

  return jsonb_build_object(
    -- profile with raw contact + Stripe ids removed, masked contact added
    'profile', (v_pj - 'phone' - 'phone_number' - 'stripe_connect_id' - 'stripe_customer_id' - 'wallet_balance')
               || jsonb_build_object('phone_masked', ops.mask_phone(coalesce(pr.phone_number, pr.phone)),
                                     'email_masked', ops.mask_email(v_u ->> 'email')),
    'auth', jsonb_build_object(
              'created_at',         v_u ->> 'created_at',
              'last_sign_in_at',    v_u ->> 'last_sign_in_at',     -- production only; null locally
              'email_confirmed_at', v_u ->> 'email_confirmed_at',
              'phone_confirmed_at', v_u ->> 'phone_confirmed_at'),
    'onboarding', jsonb_build_object(
              'stripe_connect_id_present',  pr.stripe_connect_id is not null,
              'stripe_connect_status',      v_pj ->> 'stripe_connect_status',
              'stripe_onboarding_complete', pr.stripe_onboarding_complete,
              'stripe_payouts_enabled',     (v_pj ->> 'stripe_payouts_enabled')::boolean,
              'stripe_charges_enabled',     (v_pj ->> 'stripe_charges_enabled')::boolean,
              'stripe_customer_id_present', pr.stripe_customer_id is not null),
    'listings', coalesce((select jsonb_agg(ops.listing_summary(l.id) order by l.created_at desc) from (
                            select id, created_at from public.listings where seller_id = pr.id order by created_at desc limit 50) l), '[]'::jsonb),
    'orders_as_buyer', coalesce((select jsonb_agg(ops.order_row(p, t) order by p.created_at desc) from (
                            select * from public.payments where buyer_id = pr.id order by created_at desc limit 50) p
                            left join public.transfers t on t.payment_id = p.id), '[]'::jsonb),
    'orders_as_seller', coalesce((select jsonb_agg(ops.order_row(p, t) order by p.created_at desc) from (
                            select * from public.payments where seller_id = pr.id order by created_at desc limit 50) p
                            left join public.transfers t on t.payment_id = p.id), '[]'::jsonb),
    'reports_made', coalesce((select jsonb_agg(to_jsonb(rp) order by rp.created_at desc) from (
                            select * from public.reports where reporter_id = pr.id order by created_at desc limit 50) rp), '[]'::jsonb),
    'reports_received', coalesce((select jsonb_agg(to_jsonb(rp) order by rp.created_at desc) from (
                            select * from public.reports where target_type = 'user' and target_id = pr.id order by created_at desc limit 50) rp), '[]'::jsonb),
    'seller_flags', coalesce((select jsonb_agg(to_jsonb(sf) order by sf.created_at desc) from (
                            select * from public.seller_flags where seller_id = pr.id order by created_at desc limit 50) sf), '[]'::jsonb),
    'seller_risk_score', (select to_jsonb(rs) from public.seller_risk_scores rs where rs.seller_id = pr.id),
    'restrictions', coalesce((select jsonb_agg(to_jsonb(ur) || jsonb_build_object('actor_label', ops.actor_label(ur.actor)) order by ur.created_at desc)
                                from ops.user_restriction ur where ur.user_id = pr.id), '[]'::jsonb),
    'cases', coalesce((select jsonb_agg(ops.case_row(k) order by k.created_at desc) from ops."case" k
                        where k.subject_kind = 'user' and k.subject_id = pr.id), '[]'::jsonb),
    'is_operator', exists (select 1 from public.admin_users a where a.user_id = pr.id)
                   or exists (select 1 from kernel.platform_role r where r.identity_id = pr.id));
end;
$ops$;
revoke all on function ops.user_detail(uuid) from public, anon, authenticated;
grant execute on function ops.user_detail(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 7 — listings + reports
-- ----------------------------------------------------------------------------
-- filters: status, auction_status, seller_id, q (uuid prefix or event_name ilike), has_reports bool.
create or replace function ops.list_listings(p_filters jsonb default '{}'::jsonb, p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  r        record;
  v_status text := nullif(f ->> 'status', '');
  v_astat  text := nullif(f ->> 'auction_status', '');
  v_seller uuid := nullif(f ->> 'seller_id', '')::uuid;
  v_q      text := nullif(trim(coalesce(f ->> 'q', '')), '');
  v_rep    boolean := (f ->> 'has_reports')::boolean;
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  select * into r from ops.uuid_prefix_range(v_q);

  with page as (
    select l.created_at as created_at, l.id as id,
         ops.listing_summary(l.id) || jsonb_build_object(
           'seller_display_name', (select pr.display_name from public.profiles pr where pr.id = l.seller_id),
           'report_count',  (select count(*) from public.reports rp where rp.target_type = 'listing' and rp.target_id = l.id),
           'payment_status',(select p.status from public.payments p where p.listing_id = l.id order by p.created_at desc limit 1),
           'open_cases',    (select count(*) from ops."case" oc where oc.subject_kind = 'listing' and oc.subject_id = l.id
                                                                  and oc.status not in ('resolved','dismissed'))) as item
    from public.listings l
   where (v_status is null or l.status = v_status)
     and (v_astat  is null or l.auction_status = v_astat)
     and (v_seller is null or l.seller_id = v_seller)
     and (v_q is null
          or (r.lo is not null and l.id between r.lo and r.hi)
          or (r.lo is null and l.event_name ilike '%' || v_q || '%'))
     and (v_rep is null or v_rep = exists (select 1 from public.reports rp where rp.target_type = 'listing' and rp.target_id = l.id))
     and (c.ts is null or (l.created_at, l.id) < (c.ts, c.id))
   order by l.created_at desc, l.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null and v_q is null and v_rep is null then
    select count(*) into v_count from public.listings l
     where (v_status is null or l.status = v_status)
       and (v_astat  is null or l.auction_status = v_astat)
       and (v_seller is null or l.seller_id = v_seller);
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$ops$;
revoke all on function ops.list_listings(jsonb, text, integer) from public, anon, authenticated;
grant execute on function ops.list_listings(jsonb, text, integer) to authenticated;

create or replace function ops.listing_detail(p_listing_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare l public.listings%rowtype;
begin
  perform ops.assert_reader();
  select * into l from public.listings where id = p_listing_id;
  if not found then
    raise exception 'not_found: listing % does not exist', p_listing_id using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'listing',  to_jsonb(l),
    'seller',   ops.user_summary(l.seller_id),
    'payments', coalesce((select jsonb_agg(ops.order_row(p, t) order by p.created_at desc)
                            from public.payments p left join public.transfers t on t.payment_id = p.id
                           where p.listing_id = l.id), '[]'::jsonb),
    'transfer', (select ops.transfer_json(t) from public.transfers t where t.listing_id = l.id),
    'bids', jsonb_build_object(
              'count',   (select count(*) from public.bids b where b.listing_id = l.id),
              'highest', (select max(b.amount) from public.bids b where b.listing_id = l.id),
              'highest_bidder_id', l.highest_bidder_id,
              'recent',  coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'amount', b.amount, 'bidder_id', b.bidder_id,
                                                                        'bidder_display_name', ops.actor_label(b.bidder_id), 'created_at', b.created_at)
                                                    order by b.created_at desc)
                                     from (select * from public.bids where listing_id = l.id order by created_at desc limit 20) b), '[]'::jsonb)),
    'reports', coalesce((select jsonb_agg(to_jsonb(rp) || jsonb_build_object('reporter_label', ops.actor_label(rp.reporter_id)) order by rp.created_at desc)
                           from public.reports rp where rp.target_type = 'listing' and rp.target_id = l.id), '[]'::jsonb),
    'seller_flags', coalesce((select jsonb_agg(to_jsonb(sf) order by sf.created_at desc) from public.seller_flags sf where sf.listing_id = l.id), '[]'::jsonb),
    'cases', coalesce((select jsonb_agg(ops.case_row(k) order by k.created_at desc) from ops."case" k
                        where k.subject_kind = 'listing' and k.subject_id = l.id), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from (
                          select * from ops.action a where a.subject_kind = 'listing' and a.subject_id = l.id
                           order by a.requested_at desc limit 50) a), '[]'::jsonb),
    'evidence', jsonb_build_object(
                  'proof_of_ownership_path', jsonb_build_object('bucket', 'proof-docs', 'path', l.proof_of_ownership_path),
                  'cover_image_path',        jsonb_build_object('bucket', 'auction-media', 'path', l.cover_image_path)));
end;
$ops$;
revoke all on function ops.listing_detail(uuid) from public, anon, authenticated;
grant execute on function ops.listing_detail(uuid) to authenticated;

-- filters: status text[], target_type.
create or replace function ops.list_reports(p_filters jsonb default '{}'::jsonb, p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  v_status text[] := ops.jsonb_text_array(f -> 'status');
  v_ttype  text := nullif(f ->> 'target_type', '');
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);

  with page as (
    select rp.created_at as created_at, rp.id as id,
         to_jsonb(rp) || jsonb_build_object(
           'reporter_label', ops.actor_label(rp.reporter_id),
           'target_label',   ops.subject_label(rp.target_type, rp.target_id, null),
           'open_cases',     (select count(*) from ops."case" oc where oc.subject_kind = 'report' and oc.subject_id = rp.id
                                                                   and oc.status not in ('resolved','dismissed'))) as item
    from public.reports rp
   where (v_status is null or rp.status = any(v_status))
     and (v_ttype  is null or rp.target_type = v_ttype)
     and (c.ts is null or (rp.created_at, rp.id) < (c.ts, c.id))
   order by rp.created_at desc, rp.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null then
    select count(*) into v_count from public.reports rp
     where (v_status is null or rp.status = any(v_status))
       and (v_ttype  is null or rp.target_type = v_ttype);
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$ops$;
revoke all on function ops.list_reports(jsonb, text, integer) from public, anon, authenticated;
grant execute on function ops.list_reports(jsonb, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 8 — money
-- ----------------------------------------------------------------------------
-- Design §5, verbatim. Every metric carries its own definition, source and
-- basis so the UI never has to explain a number. Dates are UTC calendar days,
-- inclusive; default = the last 30 days. USD only (single-currency data).
create or replace function ops.money_overview(p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  v_to    date := coalesce(p_to,   (now() at time zone 'UTC')::date);
  v_from  date := coalesce(p_from, v_to - 30);
  lo      timestamptz;
  hi      timestamptz;
  m       jsonb;
  v_val   bigint; v_cnt bigint;
begin
  perform ops.assert_reader();
  if v_from > v_to then
    raise exception 'invalid_input: from must not be after to';
  end if;
  if v_to - v_from > 400 then
    raise exception 'invalid_input: range must be 400 days or fewer';
  end if;
  lo := (v_from::timestamp) at time zone 'UTC';
  hi := ((v_to + 1)::timestamp) at time zone 'UTC';
  m := '{}'::jsonb;

  -- Gross captured volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status in ('succeeded','refunded') and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('gross_captured_volume', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.total where status in (succeeded, refunded). Captured card volume including buyer fees; refunds are NOT netted out — see refunded_volume.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Refunded volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'refunded' and p.refunded_at >= lo and p.refunded_at < hi;
  m := m || jsonb_build_object('refunded_volume', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.total where status = refunded (full refunds recorded by the charge.refunded webhook).',
         'source', 'public.payments', 'basis', 'refunded_at, UTC calendar day'));

  -- Platform fees (gross, pre-refund)
  select coalesce(sum(p.buyer_fee + coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'succeeded' and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('platform_fees_gross', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of buyer_fee + seller_fee on succeeded payments. Gross and pre-refund; not revenue.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Seller funds released to connected account
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.stripe_transfer_id is not null and t.payout_released_at >= lo and t.payout_released_at < hi;
  m := m || jsonb_build_object('seller_funds_released', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.amount - seller_fee for transfers whose stripe_transfer_id is set (a Stripe Transfer to the seller''s connected account exists). Not a bank payout.',
         'source', 'public.transfers + public.payments', 'basis', 'payout_released_at, UTC calendar day'));

  -- Seller funds pending (point in time)
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status in ('seller_sent','buyer_confirmed','auto_released') and t.stripe_transfer_id is null
     and p.status = 'succeeded';
  m := m || jsonb_build_object('seller_funds_pending', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Seller share (amount - seller_fee) of transfers in seller_sent / buyer_confirmed / auto_released with no Stripe Transfer yet. Point-in-time, not a date range.',
         'source', 'public.transfers + public.payments', 'basis', 'now()'));

  -- Bank payouts — not tracked
  m := m || jsonb_build_object('bank_payouts', jsonb_build_object(
         'value_cents', null, 'count', null, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Not tracked. Payouts from connected accounts to sellers'' banks are Stripe-side; the payout.paid webhook is only logged.',
         'source', null, 'basis', 'not_tracked'));

  return jsonb_build_object(
    'from', v_from, 'to', v_to, 'currency', 'USD', 'computed_at', now(),
    'metrics', m,
    'snapshot', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value, 'computed_at', s.computed_at) order by s.key)
                            from ops.metric_snapshot s), '[]'::jsonb),
    'snapshot_computed_at', (select max(computed_at) from ops.metric_snapshot));
end;
$ops$;
revoke all on function ops.money_overview(date, date) from public, anon, authenticated;
grant execute on function ops.money_overview(date, date) to authenticated;

-- Transfers with their seller-funds state. filters: state (payout_state vocabulary).
create or replace function ops.list_payouts(p_filters jsonb default '{}'::jsonb, p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  v_state  text := nullif(f ->> 'state', '');
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  if v_state is not null and v_state not in ('released','pending_release','held','manual_review','none') then
    raise exception 'invalid_input: state must be released|pending_release|held|manual_review|none';
  end if;

  with page as (
    select t.created_at as created_at, t.id as id,
         ops.transfer_json(t) || jsonb_build_object(
           'seller_funds_state', ops.funds_state(t, p),
           'seller',             ops.user_summary(t.seller_id),
           'event_name',         (select l.event_name from public.listings l where l.id = t.listing_id),
           'payment_status',     p.status,
           'amount',             p.amount,
           'seller_fee',         p.seller_fee,
           'seller_share_cents', p.amount - coalesce(p.seller_fee, 0),
           'payout_decision',    (select to_jsonb(pd) from public.payout_decisions pd where pd.transfer_id = t.id
                                    order by pd.decided_at desc limit 1)) as item
    from public.transfers t
    left join public.payments p on p.id = t.payment_id
   where (v_state is null or case v_state
            when 'released'        then t.stripe_transfer_id is not null
            when 'held'            then t.stripe_transfer_id is null and t.payout_review_status = 'held'
            when 'manual_review'   then t.stripe_transfer_id is null and t.payout_review_status = 'manual_review'
            when 'pending_release' then t.stripe_transfer_id is null and t.payout_review_status is null
                                        and t.status in ('seller_sent','buyer_confirmed','auto_released')
            else t.stripe_transfer_id is null and t.payout_review_status is null
                 and t.status not in ('seller_sent','buyer_confirmed','auto_released') end)
     and (c.ts is null or (t.created_at, t.id) < (c.ts, c.id))
   order by t.created_at desc, t.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null and v_state is null then
    select count(*) into v_count from public.transfers;
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$ops$;
revoke all on function ops.list_payouts(jsonb, text, integer) from public, anon, authenticated;
grant execute on function ops.list_payouts(jsonb, text, integer) to authenticated;

-- Live money-state mismatches (read-only; the console never repairs money).
--   refunded_but_released       payment refunded, transfer has a Stripe Transfer and is not reversed
--   total_mismatch              payments.total <> amount + buyer_fee
--   release_unconfirmed         payout_released_at set, no stripe_transfer_id after 30 min (outcome unknown)
--   expired_without_refund      transfer expired, payment still succeeded
--   buyer_win_without_refund    dispute resolved buyer_win / partial_refund, payment still succeeded
--   action_outcome_unknown      ops.action in state unknown, or succeeded_at_provider for > 1 h
-- Items {kind, subject_kind, subject_id, detail, since}; keyset on (since desc, subject_id desc).
create or replace function ops.reconciliation_queue(p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  lim     integer := ops.clamp_limit(p_limit);
  c       record;
  v_items jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);

  with recon (kind, subject_kind, subject_id, detail, since) as (
  select 'refunded_but_released', 'transfer', t.id,
         jsonb_build_object('payment_id', p.id, 'stripe_transfer_id', t.stripe_transfer_id, 'transfer_status', t.status, 'refunded_at', p.refunded_at),
         coalesce(p.refunded_at, t.payout_released_at, now())
    from public.payments p join public.transfers t on t.payment_id = p.id
   where p.status = 'refunded' and t.stripe_transfer_id is not null and t.status <> 'reversed'
  union all
  select 'total_mismatch', 'payment', p.id,
         jsonb_build_object('amount', p.amount, 'buyer_fee', p.buyer_fee, 'total', p.total, 'expected_total', p.amount + p.buyer_fee, 'status', p.status),
         p.created_at
    from public.payments p
   where p.total <> p.amount + p.buyer_fee
  union all
  select 'release_unconfirmed', 'transfer', t.id,
         jsonb_build_object('payout_released_at', t.payout_released_at, 'transfer_status', t.status, 'payment_id', t.payment_id),
         t.payout_released_at
    from public.transfers t
   where t.payout_released_at is not null and t.stripe_transfer_id is null
     and t.payout_released_at < now() - interval '30 minutes'
     and t.status not in ('reversed','expired')
  union all
  select 'expired_without_refund', 'payment', p.id,
         jsonb_build_object('transfer_id', t.id, 'expired_at', t.expired_at, 'payment_status', p.status),
         coalesce(t.expired_at, t.expires_at, now())
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status = 'expired' and p.status = 'succeeded'
  union all
  select 'buyer_win_without_refund', 'payment', p.id,
         jsonb_build_object('transfer_id', t.id, 'dispute_resolution', t.dispute_resolution, 'dispute_resolved_at', t.dispute_resolved_at, 'payment_status', p.status),
         coalesce(t.dispute_resolved_at, now())
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.dispute_resolution in ('resolved_buyer_refunded','resolved_partial_refund') and p.status = 'succeeded'
  union all
  select 'action_outcome_unknown', 'action', a.id,
         jsonb_build_object('action_type', a.action_type, 'state', a.state, 'subject_kind', a.subject_kind, 'subject_id', a.subject_id,
                            'provider_ref', a.provider_ref, 'error', a.error),
         coalesce(a.completed_at, a.updated_at)
    from ops.action a
   where a.state = 'unknown'
      or (a.state = 'succeeded_at_provider' and a.updated_at < now() - interval '1 hour')
  ),
  page as (
    select x.* from recon x
     where c.ts is null or (x.since, x.subject_id) < (c.ts, c.id)
     order by x.since desc, x.subject_id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by since desc, subject_id desc) as rn from page)
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'subject_kind', subject_kind, 'subject_id', subject_id,
                                               'detail', detail, 'since', since,
                                               'subject_label', ops.subject_label(subject_kind, subject_id, null))
                            order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(since) filter (where rn = lim),
         (max(subject_id::text) filter (where rn = lim))::uuid,
         count(*),
         (select count(*) from recon)
    into v_items, v_last_ts, v_last_id, v_n, v_count
    from numbered;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', case when p_cursor is null then v_count end,
           'generated_at', now());
end;
$ops$;
revoke all on function ops.reconciliation_queue(text, integer) from public, anon, authenticated;
grant execute on function ops.reconciliation_queue(text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 9 — system
-- ----------------------------------------------------------------------------
create or replace function ops.job_health()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  v_cron   jsonb;
  v_avail  boolean := to_regclass('cron.job_run_details') is not null;
begin
  perform ops.assert_reader();

  if v_avail then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object(
               'jobid', j.jobid, 'jobname', j.jobname, 'schedule', j.schedule, 'active', j.active,
               'last_status', lr.status, 'last_end', lr.end_time, 'last_message', left(lr.return_message, 300),
               'runs_24h', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - interval '24 hours'),
               'failures_24h', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - interval '24 hours' and d.status = 'failed'))
               order by j.jobname), '[]'::jsonb)
        from cron.job j
        left join lateral (select d.status, d.end_time, d.return_message from cron.job_run_details d
                            where d.jobid = j.jobid order by d.start_time desc limit 1) lr on true
    $q$ into v_cron;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'jobid', j.jobid, 'jobname', j.jobname, 'schedule', j.schedule, 'active', j.active,
             'last_status', null, 'last_end', null, 'last_message', null, 'runs_24h', null, 'failures_24h', null)
             order by j.jobname), '[]'::jsonb)
      into v_cron
      from cron.job j;
  end if;

  return jsonb_build_object(
    'generated_at', now(),
    'cron_jobs', jsonb_build_object('available', v_avail, 'items', v_cron,
                   'note', case when v_avail then null else 'cron.job_run_details is not present on this database; run history unavailable' end),
    'ops_jobs', coalesce((select jsonb_agg(to_jsonb(js) || jsonb_build_object(
                             'recent_runs', coalesce((select jsonb_agg(to_jsonb(jr) order by jr.started_at desc) from (
                                               select * from ops.job_run where job_name = js.job_name order by started_at desc limit 5) jr), '[]'::jsonb))
                             order by js.job_name)
                            from ops.job_state js), '[]'::jsonb),
    'webhook_backlog', (select jsonb_build_object(
                           'unprocessed', count(*) filter (where w.failed_at is null),
                           'failed',      count(*) filter (where w.failed_at is not null),
                           'oldest_unprocessed_at', min(w.received_at) filter (where w.failed_at is null),
                           'oldest_unprocessed_event_id', (select w2.event_id from public.stripe_webhook_events w2
                                                            where w2.processed_at is null and w2.failed_at is null
                                                            order by w2.received_at asc limit 1))
                          from public.stripe_webhook_events w where w.processed_at is null),
    'notify', jsonb_build_object(
                'delivery', coalesce((select jsonb_object_agg(d.state, d.n) from (
                               select state, count(*) n from notify.delivery group by state) d), '{}'::jsonb),
                'outbox',   coalesce((select jsonb_object_agg(o.state, o.n) from (
                               select state, count(*) n from notify.outbox group by state) o), '{}'::jsonb),
                'note', 'notify.* has no dispatch adapter yet (parked); counts are informational'),
    'alerts', coalesce((select jsonb_agg(to_jsonb(al) order by al.last_fired_at desc) from ops.alert al where al.state = 'firing'), '[]'::jsonb));
end;
$ops$;
revoke all on function ops.job_health() from public, anon, authenticated;
grant execute on function ops.job_health() to authenticated;

create or replace function ops.audit_log(p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  lim     integer := ops.clamp_limit(p_limit);
  c       record;
  v_items jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);

  with page as (
    select au.occurred_at as occurred_at, au.id as id,
         to_jsonb(au) || jsonb_build_object('actor_label', ops.actor_label(au.actor),
                                            'subject_label', ops.subject_label(au.subject_kind, au.subject_id, au.subject_ref)) as item
    from ops.audit au
   where (c.ts is null or (au.occurred_at, au.id) < (c.ts, c.id))
   order by au.occurred_at desc, au.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by occurred_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(occurred_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null then select count(*) into v_count from ops.audit; end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$ops$;
revoke all on function ops.audit_log(text, integer) from public, anon, authenticated;
grant execute on function ops.audit_log(text, integer) to authenticated;

-- filters: state text[], action_type text[], subject_kind, subject_id, requested_by (uuid | 'me').
create or replace function ops.list_actions(p_filters jsonb default '{}'::jsonb, p_cursor text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  v_state  text[] := ops.jsonb_text_array(f -> 'state');
  v_type   text[] := ops.jsonb_text_array(f -> 'action_type');
  v_skind  text := nullif(f ->> 'subject_kind', '');
  v_sid    uuid := nullif(f ->> 'subject_id', '')::uuid;
  v_req    text := nullif(f ->> 'requested_by', '');
  v_req_id uuid;
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  if v_req = 'me' then v_req_id := auth.uid(); elsif v_req is not null then v_req_id := v_req::uuid; end if;

  with page as (
    select a.created_at as created_at, a.id as id, ops.action_row(a) as item
    from ops.action a
   where (v_state is null or a.state = any(v_state))
     and (v_type  is null or a.action_type = any(v_type))
     and (v_skind is null or a.subject_kind = v_skind)
     and (v_sid   is null or a.subject_id = v_sid)
     and (v_req_id is null or a.requested_by = v_req_id)
     and (c.ts is null or (a.created_at, a.id) < (c.ts, c.id))
   order by a.created_at desc, a.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null then
    select count(*) into v_count from ops.action a
     where (v_state is null or a.state = any(v_state))
       and (v_type  is null or a.action_type = any(v_type))
       and (v_skind is null or a.subject_kind = v_skind)
       and (v_sid   is null or a.subject_id = v_sid)
       and (v_req_id is null or a.requested_by = v_req_id);
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$ops$;
revoke all on function ops.list_actions(jsonb, text, integer) from public, anon, authenticated;
grant execute on function ops.list_actions(jsonb, text, integer) to authenticated;

create or replace function ops.action_detail(p_action_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare a ops.action%rowtype;
begin
  perform ops.assert_reader();
  select * into a from ops.action where id = p_action_id;
  if not found then
    raise exception 'not_found: action % does not exist', p_action_id using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'action',    ops.action_row(a),
    'approvals', coalesce((select jsonb_agg(to_jsonb(ap) || jsonb_build_object(
                              'requested_by_label', ops.actor_label(ap.requested_by),
                              'decided_by_label',   ops.actor_label(ap.decided_by),
                              'can_decide',         ap.state = 'pending' and ap.requested_by <> auth.uid()
                                                    and ap.expires_at > now() and ops.actor_role() = 'platform_admin')
                              order by ap.created_at desc)
                             from ops.approval ap where ap.action_id = a.id), '[]'::jsonb),
    'audit',     coalesce((select jsonb_agg(to_jsonb(au) || jsonb_build_object('actor_label', ops.actor_label(au.actor)) order by au.occurred_at)
                             from ops.audit au where au.action_id = a.id), '[]'::jsonb),
    'subject',   ops.subject_summary(a.subject_kind, a.subject_id, a.subject_ref),
    'related_cases', coalesce((select jsonb_agg(ops.case_row(k) order by k.created_at desc) from ops."case" k
                                where (a.subject_kind = 'case' and k.id = a.subject_id)
                                   or (a.subject_id is not null and k.subject_kind = a.subject_kind and k.subject_id = a.subject_id)), '[]'::jsonb));
end;
$ops$;
revoke all on function ops.action_detail(uuid) from public, anon, authenticated;
grant execute on function ops.action_detail(uuid) to authenticated;

-- Approvals by state (default pending), newest first; not paginated (the
-- pending set is tiny by construction). 'all' returns every state.
create or replace function ops.list_approvals(p_state text default 'pending')
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare v_state text := coalesce(nullif(p_state, ''), 'pending'); v_items jsonb;
begin
  perform ops.assert_reader();
  if v_state not in ('pending','approved','denied','expired','stale','cancelled','all') then
    raise exception 'invalid_input: state must be pending|approved|denied|expired|stale|cancelled|all';
  end if;
  select coalesce(jsonb_agg(
           to_jsonb(ap) || jsonb_build_object(
             'requested_by_label', ops.actor_label(ap.requested_by),
             'decided_by_label',   ops.actor_label(ap.decided_by),
             'can_decide',         ap.state = 'pending' and ap.requested_by <> auth.uid()
                                   and ap.expires_at > now() and ops.actor_role() = 'platform_admin',
             'hash_current',       ap.action_hash = ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params),
             'action',             ops.action_row(a))
           order by ap.created_at desc), '[]'::jsonb)
    into v_items
    from (select * from ops.approval where (v_state = 'all' or state = v_state) order by created_at desc limit 200) ap
    join ops.action a on a.id = ap.action_id;
  return jsonb_build_object('items', v_items, 'next_cursor', null, 'count_hint', jsonb_array_length(v_items), 'state', v_state);
end;
$ops$;
revoke all on function ops.list_approvals(text) from public, anon, authenticated;
grant execute on function ops.list_approvals(text) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 10 — Today, summaries, settings
-- ----------------------------------------------------------------------------
-- Attention queue (open cases by priority / due) + live counts from the small
-- partial-index scans + freshness read from ops tables.
create or replace function ops.today()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  v_grace   integer := coalesce((select (value #>> '{}')::integer from ops.setting where key = 'paid_unsettled_grace_minutes'), 10);
  v_soon    integer := coalesce((select (value #>> '{}')::integer from ops.setting where key = 'transfer_deadline_soon_hours'), 6);
  v_wh      integer := coalesce((select (value #>> '{}')::integer from ops.setting where key = 'webhook_stuck_minutes'), 15);
begin
  perform ops.assert_reader();
  return jsonb_build_object(
    'attention', coalesce((select jsonb_agg(ops.case_row(k) order by k.priority, k.due_at nulls last, k.detected_at) from (
                             select * from ops."case"
                              where status not in ('resolved','dismissed')
                              order by priority, due_at nulls last, detected_at
                              limit 200) k), '[]'::jsonb),
    'metrics', jsonb_build_object(
      'open_cases_by_type', coalesce((select jsonb_object_agg(x.case_type, x.n) from (
                               select case_type, count(*) n from ops."case" where status not in ('resolved','dismissed') group by case_type) x), '{}'::jsonb),
      'open_cases',        (select count(*) from ops."case" where status not in ('resolved','dismissed')),
      'paid_unsettled',    (select count(*) from public.payments p
                             where p.status = 'succeeded' and p.paid_at < now() - make_interval(mins => v_grace)
                               and p.mode in ('buy_now','auction')
                               and not exists (select 1 from public.transfers t where t.payment_id = p.id)),
      'transfers_due_6h',  (select count(*) from public.transfers t
                             where t.status = 'pending' and t.expires_at >= now() and t.expires_at < now() + make_interval(hours => v_soon)),
      'transfers_overdue', (select count(*) from public.transfers t where t.status = 'pending' and t.expires_at < now()),
      'refunds_pending',   (select count(*) from public.transfers t join public.payments p on p.id = t.payment_id
                             where p.status = 'succeeded'
                               and (t.status = 'expired' or t.dispute_resolution in ('resolved_buyer_refunded','resolved_partial_refund'))),
      'disputes_open',     (select count(*) from public.transfers t where t.status = 'disputed'),
      'stripe_disputes_open', (select count(*) from public.disputes d where d.status not in ('won','lost','warning_closed','charge_refunded')),
      'evidence_due_72h',  (select count(*) from public.disputes d
                             where d.status not in ('won','lost','warning_closed','charge_refunded')
                               and d.evidence_due_by is not null and d.evidence_due_by < now() + interval '72 hours'),
      'payout_review',     (select count(*) from public.transfers t where t.payout_review_status is not null and t.stripe_transfer_id is null),
      'reports_pending',   (select count(*) from public.reports r where r.status = 'pending'),
      'jobs_failing',      (select count(*) from ops.job_state js where js.enabled and js.consecutive_failures >= 2),
      'webhook_backlog',   (select count(*) from public.stripe_webhook_events w
                             where w.processed_at is null and w.received_at < now() - make_interval(mins => v_wh)),
      'approvals_pending', (select count(*) from ops.approval ap where ap.state = 'pending' and ap.expires_at > now()),
      'alerts_firing',     (select count(*) from ops.alert where state = 'firing')),
    'freshness', jsonb_build_object(
      'snapshot_computed_at',      (select max(computed_at) from ops.metric_snapshot),
      'last_detector_success_at',  (select max(last_success_at) from ops.job_state),
      'last_detector_run_at',      (select max(last_run_at) from ops.job_state),
      'detectors_enabled',         coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'detectors_enabled'), false),
      'generated_at',              now()));
end;
$ops$;
revoke all on function ops.today() from public, anon, authenticated;
grant execute on function ops.today() to authenticated;

create or replace function ops.latest_summary()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  return (select to_jsonb(s) from ops.daily_summary s order by s.summary_date desc limit 1);
end;
$ops$;
revoke all on function ops.latest_summary() from public, anon, authenticated;
grant execute on function ops.latest_summary() to authenticated;

-- platform_admin only: console settings with who changed them last.
create or replace function ops.settings()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_role(array['platform_admin']);
  return coalesce((select jsonb_agg(to_jsonb(s) || jsonb_build_object('updated_by_label', ops.actor_label(s.updated_by)) order by s.key)
                     from ops.setting s), '[]'::jsonb);
end;
$ops$;
revoke all on function ops.settings() from public, anon, authenticated;
grant execute on function ops.settings() to authenticated;

commit;
