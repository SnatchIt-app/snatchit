-- ============================================================================
-- 127_release_reservation_guards.sql — L1 + L2: a reservation release must not
-- free a hold that belongs to a NEWER attempt, and must never free a hold on a
-- listing that already holds a succeeded payment.
--
-- WHY. Two independent gaps, both recorded in PRODUCTION_RELEASE_PACKAGE.md.
--
-- L2 — `release_reservation` has no succeeded-payment guard. Both sweeps skip a
-- listing holding a succeeded payment (the N1 guard in
-- 20260906110000_settle_verified_payment.sql), but the LIVE path checks only
-- `sold` and hold ownership. Between a payment succeeding and the listing
-- reading `sold`, leaving the listing screen (path 2) or the webhook's release
-- could free a PAID order's hold.
--
-- L1 — a stale cancellation releases a newer hold. `create-payment-intent`'s
-- amount-mismatch branch cancels the buyer's OWN pending PaymentIntent and then
-- retires the row to `failed`. The webhook's claim predicate
-- (`status NOT IN (succeeded, refunded)`) still matches that `failed` row, so
-- the late `payment_intent.canceled` claims it and calls
-- `release_reservation(listing, same buyer)`. If the buyer has since reserved
-- again, that releases their LIVE hold. Same-buyer ownership is not enough to
-- tell "this payment's hold" from "a hold taken afterwards".
--
-- TWO QUESTIONS, because one of them is unanswerable. An independent review of
-- the first draft of this migration showed the timestamp test alone does NOT
-- close L1, and the correction matters enough to record here.
--
--   Timestamps can only answer "did this hold exist when that payment row was
--   created?". In the retire-and-remint case they answer YES for BOTH rows:
--   `reserve_buy_now` returns early when the holder re-reserves its own live
--   hold ("keeps the EXISTING window", 20260906100000), and
--   create-payment-intent mints a buy-now row only while the caller IS the live
--   holder. So P1 (retired to `failed`) and P2 (live) sit under ONE unchanged
--   hold, `reserved_until <= created_at + TTL` holds for both, and a
--   timestamp-only guard releases a hold P2 is still using. The hold genuinely
--   belongs to both rows: that is an identity problem, not a resolution
--   problem, and no TTL or tolerance fixes it.
--
-- So the guard asks the ANSWERABLE question first:
--   1. LIVE SIBLING — is another attempt by this buyer on this listing still in
--      flight (`pending`/`processing`)? If so the hold is still needed, whoever
--      it "belongs" to. This is what closes the retire-and-remint case.
--   2. HOLD NEWER THAN THE PAYMENT — `reserved_until <= created_at + TTL`. Still
--      needed, and complementary: it catches a hold RE-TAKEN after this payment
--      when no new payment row exists yet (abandon, lapse, reserve again).
-- Both timestamps come from the same clock, so (2) is exact where it applies.
--
-- TTL COUPLING — READ BEFORE CHANGING `reserve_buy_now`. `v_hold_ttl` below
-- mirrors `reserve_buy_now`'s `v_minutes := 10`. If that window changes, this
-- constant MUST change with it, or a legitimate release will be refused (safe
-- direction) or a newer hold released (unsafe direction). pgTAP 194 pins the
-- coupling so the suite fails if they drift apart.
--
-- SHAPE. `release_reservation` keeps its signature, SECURITY DEFINER, search_path
-- and grants. Its body is the APPLIED (0590) body plus the L2 guard -- NOT the
-- 000_baseline body. An earlier revision of this migration rebuilt it from the
-- baseline and so silently reverted 0590's identity hardening; 194 now pins it. `release_reservation_for_payment`
-- is NEW and service_role-only: it is the webhook's path, never a client's.
-- Census +1 function. Applied nowhere by this file.
--
-- L1 IS NARROWED, NOT CLOSED, AT THE DATABASE LEVEL. Re-review found a producer
-- race the guard cannot see: `create-payment-intent` cancels P1 at Stripe (which
-- emits `payment_intent.canceled`), then marks P1 failed, then does a Stripe
-- round-trip, and only THEN inserts P2. If the webhook lands inside that window
-- there is no sibling row yet, and the timestamp test does not refuse because the
-- hold genuinely predates P1. No database state distinguishes "no newer attempt"
-- from "the newer attempt is not recorded yet". Closing it belongs in the same
-- edge deploy that switches to this function: insert P2 BEFORE cancelling P1, or
-- have the retire stamp a marker this guard refuses on.
--
-- DELIVERY CAVEAT — read before recording "127 applied" as "L1 closed". The
-- webhook still calls `release_reservation`; nothing calls
-- `release_reservation_for_payment` until stripe-webhook is redeployed to use
-- it. On apply, ONLY the L2 guard takes effect. That edge change is a separate,
-- separately-authorized deploy.
--
-- MERGE ORDER. 121 -> 123 -> 124 -> 125 -> then this. 125 must land while the
-- base's highest integer migration is still 124 (the merge guard is
-- base-relative on added migrations), so this file must NOT reach the
-- integrated base before Claude B's 125.
-- ============================================================================
begin;

-- ── 1. L2 guard on the client-facing release (body-only replace) ────────────
create or replace function public.release_reservation(
  p_listing_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id   uuid;
  v_status      text;
  v_reserved_by uuid;
begin
  -- SECURITY (0590): auth.uid() is authoritative. p_user_id is honoured ONLY for a
  -- verified service-role caller. 0590 removed the last
  -- identity-fallback coalesces precisely so a future re-GRANT
  -- could not silently reopen that hole. Do not reintroduce one.
  v_caller_id := auth.uid();
  if v_caller_id is null and public.request_is_service_role() then
    v_caller_id := p_user_id;
  end if;

  select status, reserved_by
    into v_status, v_reserved_by
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    return;
  end if;

  if v_status = 'sold' then
    return;
  end if;

  -- L2: never free a hold on a listing that already holds a succeeded payment.
  -- Mirrors the N1 guard the sweeps already apply. NOTE, precisely: locking the
  -- listing does NOT serialise against an uncommitted `payments` write that has
  -- not yet reached this row, so a settlement committing in the same instant can
  -- still slip past. This closes the reported window — a COMMITTED succeeded
  -- payment on a not-yet-sold listing — not a millisecond-wide race.
  if exists (
    select 1 from public.payments p
     where p.listing_id = p_listing_id
       and p.status     = 'succeeded'
  ) then
    return;
  end if;

  if v_status = 'reserved' and v_reserved_by = v_caller_id then
    perform set_config('app.bypass_listing_guard', 'on', true);
    update public.listings
       set status         = 'active',
           reserved_by    = null,
           reserved_until = null
     where id = p_listing_id;
  end if;
end;
$$;

comment on function public.release_reservation(uuid, uuid) is
  '127: releases the caller''s Buy Now hold. No-op when the listing is sold, when it holds a succeeded payment (L2 — mirrors the sweeps'' N1 guard), or when the hold is not the caller''s.';

-- ── 2. L1: payment-scoped release, for the webhook only ─────────────────────
create or replace function public.release_reservation_for_payment(
  p_listing_id uuid,
  p_user_id    uuid,
  p_payment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Mirrors reserve_buy_now's v_minutes := 10. See TTL COUPLING in the header.
  v_hold_ttl        constant interval := interval '10 minutes';
  v_status          text;
  v_reserved_by     uuid;
  v_reserved_until  timestamptz;
  v_pay_listing     uuid;
  v_pay_buyer       uuid;
  v_pay_created     timestamptz;
  v_pay_mode        text;
begin
  if p_listing_id is null or p_user_id is null or p_payment_id is null then
    return jsonb_build_object('released', false, 'reason', 'missing_argument');
  end if;

  -- The payment this event is about. Bound to the listing AND the buyer, so a
  -- mismatched or unknown payment can never drive a release.
  select listing_id, buyer_id, created_at, mode
    into v_pay_listing, v_pay_buyer, v_pay_created, v_pay_mode
    from public.payments
   where id = p_payment_id;

  if not found then
    return jsonb_build_object('released', false, 'reason', 'unknown_payment');
  end if;
  if v_pay_listing is distinct from p_listing_id or v_pay_buyer is distinct from p_user_id then
    return jsonb_build_object('released', false, 'reason', 'payment_not_for_listing_buyer');
  end if;
  -- The whole reserve-then-pay ordering this guard reasons about exists only for
  -- Buy Now. An auction checkout takes no reservation, so the hold window means
  -- nothing for it and it must never drive a release. Not left to the caller's
  -- `if (metadata.mode === 'buy_now')`.
  if v_pay_mode is distinct from 'buy_now' then
    return jsonb_build_object('released', false, 'reason', 'payment_not_buy_now');
  end if;

  select status, reserved_by, reserved_until
    into v_status, v_reserved_by, v_reserved_until
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    return jsonb_build_object('released', false, 'reason', 'listing_not_found');
  end if;
  if v_status = 'sold' then
    return jsonb_build_object('released', false, 'reason', 'listing_sold');
  end if;

  -- L2, again: a paid listing's hold is never freed, whoever asks.
  if exists (
    select 1 from public.payments p
     where p.listing_id = p_listing_id
       and p.status     = 'succeeded'
  ) then
    return jsonb_build_object('released', false, 'reason', 'listing_has_succeeded_payment');
  end if;

  if v_status <> 'reserved' or v_reserved_by is distinct from p_user_id then
    return jsonb_build_object('released', false, 'reason', 'not_held_by_buyer');
  end if;

  -- L1 (1) LIVE SIBLING — the question that actually closes the retire-and-remint
  -- case. If another BUY NOW attempt by this buyer on this listing is still in
  -- flight, the hold is still needed and this terminal event must not free it.
  -- Mode-scoped to match the subject payment: a listing can be both auction and
  -- buy-now enabled, and an auction attempt holds no reservation, so counting it
  -- as a sibling would refuse a legitimate release for something that never
  -- needed the hold.
  if exists (
    select 1 from public.payments p2
     where p2.listing_id = p_listing_id
       and p2.buyer_id   = p_user_id
       and p2.id        <> p_payment_id
       and p2.mode      = 'buy_now'
       and p2.status in ('pending', 'processing')
  ) then
    return jsonb_build_object('released', false, 'reason', 'live_sibling_attempt');
  end if;

  -- A reserved row with no window is representable and nothing here can reason
  -- about it. Refuse, but say so accurately rather than blaming the timestamps.
  if v_reserved_until is null then
    return jsonb_build_object('released', false, 'reason', 'hold_window_unknown');
  end if;

  -- L1 (2) HOLD NEWER THAN THE PAYMENT — catches a hold re-taken after this
  -- payment when no new payment row exists yet. Safe direction on any doubt: an
  -- unreleased hold still expires on its own TTL, whereas a wrongly released one
  -- costs a live buyer their inventory.
  if v_reserved_until > v_pay_created + v_hold_ttl then
    return jsonb_build_object('released', false, 'reason', 'hold_newer_than_payment');
  end if;

  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set status         = 'active',
         reserved_by    = null,
         reserved_until = null
   where id = p_listing_id;

  return jsonb_build_object('released', true, 'reason', 'released');
end;
$$;

comment on function public.release_reservation_for_payment(uuid, uuid, uuid) is
  '127 (L1): refuses to release a Buy Now hold that another attempt is still using, or that was taken after the given payment — payment bound to listing+buyer, listing not sold, no succeeded payment on the listing (L2), hold owned by the buyer, and reserved_until no later than the payment''s created_at + the 10-minute hold TTL. Returns {released, reason}; never raises. service_role only: this is the webhook''s path, not a client''s.';

-- ── 3. Grants (SEC-2: explicit REVOKE, then only the intended GRANT) ────────
revoke execute on function public.release_reservation_for_payment(uuid, uuid, uuid) from public, anon, authenticated;
grant  execute on function public.release_reservation_for_payment(uuid, uuid, uuid) to service_role;

commit;
