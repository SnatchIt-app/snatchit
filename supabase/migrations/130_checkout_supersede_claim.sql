-- ============================================================================
-- 130_checkout_supersede_claim.sql — serialize PaymentIntent secret hand-out
-- per (listing, buyer, mode): the L1 concurrency residual (PR #64 finding).
--
-- AUTHOR: Claude B (release sprint, 2026-09-15). Number 130 / pgTAP 197 per the
-- migration registry (A). Contract agreed with A by session message: group
-- claim covering reuse as well as supersede, payments -> listings lock order,
-- token-bound release, 120 s stale window.
--
-- THE DEFECT. create-payment-intent (PR #64) supersedes a pending intent P1
-- whose price changed: mint P2, insert P2's pending row, cancel P1, retire P1;
-- on a refused cancel (P1 already processing) it withdraws P2 and answers 409.
-- Two concurrent requests by the same buyer can interleave so that request 2
-- reuses P2 — it matches the new price — and receives P2's secret before
-- request 1 learns that P1's cancel was refused. If P1 then succeeds and the
-- buyer confirms P2, the buyer is charged twice. The same holds for two
-- concurrent supersedes of P1. Nothing in the database serialized them.
--
-- THE FIX. Two service_role RPCs and two nullable columns on public.payments.
--   claim_checkout_supersede(listing, buyer, payment)
--       -> {claimed, claim_token, holder_payment_id, reason}
--     Succeeds only when the payment is a pending attempt of that listing and
--     buyer AND no row of the same (listing, buyer, mode) group — in ANY status
--     — holds a claim younger than 120 s. The edge calls it before superseding AND before
--     reusing a pending intent's secret, so every hand-out is serialized.
--   release_checkout_supersede(payment, claim_token) -> {released, reason}
--     Clears the claim only when the token matches, so the late release of a
--     request whose claim went stale can never free a newer reclaim.
-- A claim older than 120 s is reclaimable: a crashed edge cannot wedge the
-- buyer for longer than that.
--
-- THE 120 s WINDOW IS NOT A GUARANTEE BY ITSELF. The RPC only decides when a
-- claim may be RECLAIMED; nothing here stops the request that HOLDS a claim
-- from continuing past 120 s. That bound is enforced on the holder by the edge
-- (create-payment-intent, D-5 finding E-1): every Stripe call in the claimed
-- section is timed out, the section has a 90 s budget, and the holder re-reads
-- its claim token before inserting a replacement, cancelling the superseded
-- intent, or handing out any secret. A caller that does not do the same gets
-- no protection from this window.
--
-- ANY-STATUS SIBLING CHECK (amended in place 2026-09-15, D-5 Q3; 130 was
-- merged into the candidate but applied nowhere). The first version counted
-- only PENDING rows' claims. Mid-supersede the holder's claimed P1 can settle
-- (the buyer confirmed it just before) while its replacement P2 is pending; P1
-- then left 'pending', its fresh claim stopped blocking, and a second request
-- could claim P2 and receive its secret before the holder saw P1's cancel
-- refused and withdrew P2 — racing that client's confirmation of P2. Settlement
-- does NOT neutralize the second success: settle_verified_payment's promotion
-- collides with idx_payments_one_success_per_listing and records outcome
-- 'unfulfillable' (20260906110000:72-75), which reconciliation refunds — the
-- buyer is charged and then refunded. A fresh claim now blocks its group
-- whatever the claimed row's status; the claimed row itself must still be
-- pending. A holder always resolves its replacement (hand-out or withdrawal)
-- before its release, and a crashed holder still lapses at 120 s.
--
-- LOCKING (the part that makes it atomic). One RPC call is one transaction:
--   1. the claimed payments row FOR UPDATE;
--   2. its listings row FOR UPDATE — the per-listing serialization point;
--   3. the sibling check, a NEW statement, whose READ COMMITTED snapshot is
--      taken after the lock wait and therefore sees a claim just committed;
--   4. the claim write.
-- payments -> listings is the repo-wide order (20260906100000:114,
-- settle_verified_payment 20260906110000:154), so a claim cannot deadlock
-- against settlement; reserve_buy_now locks the listing only, and
-- release_reservation_for_payment reads payments unlocked before locking the
-- listing. Two claims on different rows of one listing serialize on the
-- listing; two on the same row serialize on the payment. Proven with two live
-- sessions in scripts/rehearsal_130_concurrency.sh (pgTAP is one transaction).
--
-- NOT CHANGED: payment status, money or identity columns (the claim columns are
-- outside guard_payment_transitions' frozen set); every existing function.
-- Clients: payments carries SELECT-only RLS policies, so the columns are
-- readable by the buyer/seller of the row and writable by no client.
-- CI: Gate-2 functions +2 (93 -> 95); tables, policies, triggers unchanged;
-- two manifest rows (no-client-execute); expected_grants is table-level and
-- unchanged. Rollback drops both functions, then both columns.
-- Applied nowhere by this file.
-- ============================================================================
begin;

alter table public.payments
  add column if not exists supersede_claim_token uuid,
  add column if not exists supersede_claimed_at  timestamptz;

comment on column public.payments.supersede_claim_token is
  '130: token of the checkout request currently allowed to hand out or supersede this (listing, buyer, mode) group''s PaymentIntent secret. Written only by claim_checkout_supersede / release_checkout_supersede.';
comment on column public.payments.supersede_claimed_at is
  '130: when the claim was taken; a claim older than 120 seconds is abandoned and reclaimable.';

create or replace function public.claim_checkout_supersede(
  p_listing_id uuid,
  p_buyer_id   uuid,
  p_payment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stale   constant interval := interval '120 seconds';
  v_pay     public.payments%rowtype;
  v_holder  uuid;
  v_token   uuid;
begin
  if p_listing_id is null or p_buyer_id is null or p_payment_id is null then
    return jsonb_build_object('claimed', false, 'claim_token', null, 'holder_payment_id', null, 'reason', 'missing_argument');
  end if;

  -- 1. the claimed payment (lock order payments -> listings)
  select * into v_pay from public.payments p where p.id = p_payment_id for update;
  if not found then
    return jsonb_build_object('claimed', false, 'claim_token', null, 'holder_payment_id', null, 'reason', 'unknown_payment');
  end if;
  if v_pay.listing_id is distinct from p_listing_id or v_pay.buyer_id is distinct from p_buyer_id then
    return jsonb_build_object('claimed', false, 'claim_token', null, 'holder_payment_id', null, 'reason', 'payment_not_for_listing_buyer');
  end if;
  if v_pay.status <> 'pending' then
    return jsonb_build_object('claimed', false, 'claim_token', null, 'holder_payment_id', null, 'reason', 'not_pending');
  end if;

  -- 2. the listing: serializes every claim on this listing
  perform 1 from public.listings l where l.id = p_listing_id for update;

  -- 3. a fresh claim anywhere in the group, on a row in ANY status, refuses
  --    this one (new statement, so its snapshot sees a claim committed while
  --    we waited; a claimed row that settled or failed mid-supersede still
  --    counts — see ANY-STATUS SIBLING CHECK in the header)
  select p.id into v_holder
    from public.payments p
   where p.listing_id = p_listing_id
     and p.buyer_id   = p_buyer_id
     and p.mode       = v_pay.mode
     and p.supersede_claimed_at is not null
     and p.supersede_claimed_at > now() - v_stale
   order by p.supersede_claimed_at desc
   limit 1;
  if v_holder is not null then
    return jsonb_build_object('claimed', false, 'claim_token', null, 'holder_payment_id', v_holder, 'reason', 'claim_held');
  end if;

  -- 4. the claim
  v_token := gen_random_uuid();
  update public.payments
     set supersede_claim_token = v_token,
         supersede_claimed_at  = now()
   where id = p_payment_id;

  return jsonb_build_object('claimed', true, 'claim_token', v_token, 'holder_payment_id', p_payment_id, 'reason', 'claimed');
end;
$$;

comment on function public.claim_checkout_supersede(uuid, uuid, uuid) is
  '130: serialize PaymentIntent secret hand-out per (listing, buyer, mode). Claims a pending attempt of that listing and buyer unless any row of the same group, in any status, holds a claim younger than 120 s. Locks payments then listings (repo order). The 120 s window only governs reclaim; the holder is bounded by the edge (E-1). Returns {claimed, claim_token, holder_payment_id, reason}; never raises. service_role only.';

revoke execute on function public.claim_checkout_supersede(uuid, uuid, uuid) from public, anon, authenticated;
grant  execute on function public.claim_checkout_supersede(uuid, uuid, uuid) to service_role;

create or replace function public.release_checkout_supersede(
  p_payment_id  uuid,
  p_claim_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token uuid;
begin
  if p_payment_id is null or p_claim_token is null then
    return jsonb_build_object('released', false, 'reason', 'missing_argument');
  end if;
  select p.supersede_claim_token into v_token from public.payments p where p.id = p_payment_id for update;
  if not found then
    return jsonb_build_object('released', false, 'reason', 'unknown_payment');
  end if;
  if v_token is null then
    return jsonb_build_object('released', false, 'reason', 'not_claimed');
  end if;
  if v_token <> p_claim_token then
    return jsonb_build_object('released', false, 'reason', 'token_mismatch');
  end if;
  update public.payments
     set supersede_claim_token = null,
         supersede_claimed_at  = null
   where id = p_payment_id;
  return jsonb_build_object('released', true, 'reason', 'released');
end;
$$;

comment on function public.release_checkout_supersede(uuid, uuid) is
  '130: clear a checkout claim taken by claim_checkout_supersede, only when the token matches (a late release never frees a reclaim). Returns {released, reason}; never raises. service_role only.';

revoke execute on function public.release_checkout_supersede(uuid, uuid) from public, anon, authenticated;
grant  execute on function public.release_checkout_supersede(uuid, uuid) to service_role;

commit;
