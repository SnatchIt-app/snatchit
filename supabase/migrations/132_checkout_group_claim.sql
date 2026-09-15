-- ============================================================================
-- 132_checkout_group_claim.sql — pre-mint checkout group record.
--
-- DEFECT (D's disposition, OPEN MONEY DEFECT; owner ruling 2026-09-15: required
-- before production). 130 serializes a checkout only once a PENDING PAYMENT ROW
-- exists, because its claim lives on that row. Two concurrent requests by one
-- buyer that both find NO pending row each mint at Stripe. Their idempotency
-- key normally matches, so Stripe replays one intent, but it diverges three
-- ways: the canceled-replay retry (`_u<uuid>`), a seller re-price between the
-- two reads, and a failedAttempts flip between the two reads. Each divergence
-- yields two intents, two secrets and two captured charges; the second capture
-- collides with idx_payments_one_success_per_listing, is recorded unfulfillable
-- and is refunded only by a later sweep. The owner does not accept that path.
--
-- FIX. A durable record of the checkout group (listing, buyer, mode) that the
-- create-payment-intent edge takes BEFORE it reads prior payments and BEFORE
-- any mint, and holds through every secret hand-out:
--   public.checkout_group_claim            one row per claimed group
--   public.claim_checkout_group(l, b, m)   -> {claimed, claim_token, reason}
--   public.release_checkout_group(l, b, m, token) -> {released, reason}
-- A second concurrent request of the same group is refused (claim_held) and
-- answered 409 without a mint or a secret. Once the holder has committed its
-- pending row, the next request takes 130's reuse or supersede path.
--
-- MECHANISM CHOICE (recorded in MIGRATION_132_CHECKOUT_GROUP_CLAIM_DESIGN.md).
-- A payments row without an intent id would also satisfy "a record before the
-- intent", but readers of pending payments assume an intent id (the Phase 0
-- sweep's Stripe retrieve, account-deletion blockers, 127's live-sibling rule);
-- this table touches none of them.
--
-- ATOMICITY AND LOCKS. The claim is one statement: INSERT ... ON CONFLICT
-- (primary key) DO UPDATE ... WHERE the existing claim is older than 120 s.
-- A concurrent insert of the same key waits for the first to commit, then
-- evaluates the WHERE against the committed row and returns no row. The
-- statement takes no payments or listings lock and has no foreign keys, so it
-- adds no lock-order interaction with settlement (payments -> listings) or with
-- 130's claim. 120 s governs reclaim only; the holder is bounded by the edge's
-- E-1 budget (90 s default) and re-reads this token before each hand-out.
--
-- ORPHANS. A crashed holder's row lapses at 120 s and is overwritten by the
-- next claim; it holds only ids. The deletion cascade is not needed for
-- correctness and is deliberately absent (no FK, no lock interaction).
--
-- 130 IS UNCHANGED. Its RPCs and columns stay; the edge still takes the row
-- claim on reuse and supersede, so a mixed-version deploy stays serialized.
-- DEPLOY ORDER: 132 before the edge (the edge fails closed, 503, without it).
-- Rollback: supabase/rollbacks/132_checkout_group_claim_rollback.sql.
-- ============================================================================
begin;

create table if not exists public.checkout_group_claim (
  listing_id  uuid        not null,
  buyer_id    uuid        not null,
  mode        text        not null constraint checkout_group_claim_mode_ck check (mode in ('buy_now', 'auction')),
  claim_token uuid        not null,
  claimed_at  timestamptz not null default now(),
  constraint checkout_group_claim_pkey primary key (listing_id, buyer_id, mode)
);
comment on table public.checkout_group_claim is
  '132: durable pre-mint record of the checkout group (listing, buyer, mode). A row means one create-payment-intent request holds the right to read prior payments, mint and hand out a secret for that group; older than 120 s it is abandoned and reclaimable. Written only by claim_checkout_group / release_checkout_group. service_role only.';

alter table public.checkout_group_claim enable row level security;
revoke all on public.checkout_group_claim from public, anon, authenticated;

create or replace function public.claim_checkout_group(
  p_listing_id uuid,
  p_buyer_id   uuid,
  p_mode       text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token uuid;
begin
  if p_listing_id is null or p_buyer_id is null or p_mode is null then
    return jsonb_build_object('claimed', false, 'claim_token', null, 'reason', 'missing_argument');
  end if;
  if p_mode not in ('buy_now', 'auction') then
    return jsonb_build_object('claimed', false, 'claim_token', null, 'reason', 'invalid_mode');
  end if;

  insert into public.checkout_group_claim as g (listing_id, buyer_id, mode, claim_token, claimed_at)
  values (p_listing_id, p_buyer_id, p_mode, gen_random_uuid(), now())
  on conflict on constraint checkout_group_claim_pkey do update
     set claim_token = excluded.claim_token,
         claimed_at  = excluded.claimed_at
   where g.claimed_at < now() - interval '120 seconds'
  returning g.claim_token into v_token;

  if v_token is null then
    return jsonb_build_object('claimed', false, 'claim_token', null, 'reason', 'claim_held');
  end if;
  return jsonb_build_object('claimed', true, 'claim_token', v_token, 'reason', 'claimed');
end;
$$;
comment on function public.claim_checkout_group(uuid, uuid, text) is
  '132: take the pre-mint checkout group record for (listing, buyer, mode) unless a claim younger than 120 s holds it. One atomic statement on the primary key; no payments or listings lock. Returns {claimed, claim_token, reason} with reason claimed | claim_held | missing_argument | invalid_mode; never raises on those. service_role only.';
revoke execute on function public.claim_checkout_group(uuid, uuid, text) from public, anon, authenticated;
grant  execute on function public.claim_checkout_group(uuid, uuid, text) to service_role;

create or replace function public.release_checkout_group(
  p_listing_id  uuid,
  p_buyer_id    uuid,
  p_mode        text,
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
  if p_listing_id is null or p_buyer_id is null or p_mode is null or p_claim_token is null then
    return jsonb_build_object('released', false, 'reason', 'missing_argument');
  end if;
  delete from public.checkout_group_claim g
   where g.listing_id = p_listing_id and g.buyer_id = p_buyer_id and g.mode = p_mode
     and g.claim_token = p_claim_token
  returning g.claim_token into v_token;
  if v_token is not null then
    return jsonb_build_object('released', true, 'reason', 'released');
  end if;
  if exists (select 1 from public.checkout_group_claim g
              where g.listing_id = p_listing_id and g.buyer_id = p_buyer_id and g.mode = p_mode) then
    return jsonb_build_object('released', false, 'reason', 'token_mismatch');
  end if;
  return jsonb_build_object('released', false, 'reason', 'not_claimed');
end;
$$;
comment on function public.release_checkout_group(uuid, uuid, text, uuid) is
  '132: delete the checkout group record only when the token matches, so a late release by an abandoned holder never frees a reclaim. Returns {released, reason} with reason released | token_mismatch | not_claimed | missing_argument; never raises on those. service_role only.';
revoke execute on function public.release_checkout_group(uuid, uuid, text, uuid) from public, anon, authenticated;
grant  execute on function public.release_checkout_group(uuid, uuid, text, uuid) to service_role;

commit;
