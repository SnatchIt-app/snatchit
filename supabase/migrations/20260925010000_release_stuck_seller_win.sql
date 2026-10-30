-- ============================================================================
-- 20260925010000_release_stuck_seller_win.sql — registry 151 (A; finding b2,
-- D's, verified by A). pgTAP: 218. Redefines ONE function, ops.detect_release_stuck
-- (117:276, never redefined since); no new objects, grants unchanged.
--
-- A seller-win decision (065 resolve_transfer_dispute) leaves the transfer
-- 'buyer_confirmed' with buyer_confirmed_at NULL. 117 dated such a row by
-- coalesce(buyer_confirmed_at, auto_release_at), so:
--   * a Stripe dispute frozen before the seller sent (freeze_transfer_for_dispute,
--     0561) has no auto_release_at either: a stuck seller-win payout was NEVER
--     flagged;
--   * a buyer report (buyer_dispute_transfer: seller_sent only, 0550) carries the
--     send-time auto_release_at: the row was flagged at once when resolved late,
--     inside the payout sweep's own 15-minute quiet period, or up to 72 hours
--     late when resolved early.
-- 151 dates a seller-win row from when it became payable,
-- greatest(dispute_resolved_at, payout_hold_until): the anchor the sweep's (d)
-- selection uses (enforce-transfer-expiry Phase 2b) and the hold rule
-- claim_payout_attempt enforces for seller-wins (20260924000000). A live hold
-- therefore defers the case until 30 minutes after it ends. A seller-win that
-- automation will never pay (manual_review, or 'held' with no end date) is still
-- flagged, and its summary says why: ops.detect_payout_review covers only
-- seller_sent rows, so nothing else would surface it.
-- Every other row is dated exactly as in 117.
--
-- Rollback: supabase/rollbacks/20260925010000_release_stuck_seller_win_rollback.sql
-- (guarded; restores 117's body verbatim). Owner-gated: applied only by the
-- owner's instruction, never by a merge (AUTODEPLOY-1).
-- ============================================================================

create or replace function ops.detect_release_stuck()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_mins    integer := ops.setting_int('release_stuck_minutes', 30);
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select t.id, t.status, t.payout_released_at, t.auto_release_at, t.buyer_confirmed_at, l.event_name, p.amount, p.seller_fee,
           t.dispute_resolved_at, t.payout_review_status, t.payout_hold_until,
           case when t.payout_released_at is null
                then case when t.status = 'buyer_confirmed' and t.buyer_confirmed_at is null
                               and t.dispute_resolution = 'resolved_seller_paid'
                          -- 151: a seller-win is payable from the decision, or from the end of
                          -- a hold that outlasts it (greatest ignores a NULL hold)
                          then greatest(t.dispute_resolved_at, t.payout_hold_until)
                          when t.status = 'auto_released' then coalesce(t.auto_release_at, t.buyer_confirmed_at)
                          else coalesce(t.buyer_confirmed_at, t.auto_release_at) end
                else t.payout_released_at end as since,
           (t.payout_released_at is not null) as released_locally,
           (t.payout_released_at is null and t.status = 'buyer_confirmed' and t.buyer_confirmed_at is null
            and t.dispute_resolution = 'resolved_seller_paid') as seller_win
      from public.transfers t
      left join public.listings l on l.id = t.listing_id
      left join public.payments p on p.id = t.payment_id
     where t.stripe_transfer_id is null
       and ((t.status in ('auto_released', 'buyer_confirmed') and t.payout_released_at is null)
            or t.payout_released_at is not null)
       and (t.disputed_at is null or t.dispute_resolved_at is not null)
       and t.status <> 'reversed'
  loop
    if r.since is null or r.since >= now() - make_interval(mins => v_mins) then continue; end if;
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('release_stuck', 'transfer', r.id, null,
               'Seller funds release stuck',
               case when r.seller_win
                    then format('Transfer for "%s" was decided for the seller (dispute resolved %s) and has not been paid: no stripe_transfer_id; seller net $%s%s.',
                                coalesce(r.event_name, '?'), to_char(r.dispute_resolved_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                                to_char((coalesce(r.amount, 0) - coalesce(r.seller_fee, 0)) / 100.0, 'FM999999990.00'),
                                case when r.payout_review_status = 'manual_review'
                                     then '. The payout is in manual_review: automation will not pay it, so release needs an operator'
                                     when r.payout_review_status = 'held' and r.payout_hold_until is null
                                     then '. The payout is held with no end date: automation will not pay it, so release needs an operator'
                                     else format(' more than %s minutes after it became payable', v_mins) end)
                    when r.released_locally
                    then format('Transfer for "%s" was released locally at %s but has no provider transfer id (stripe_transfer_id null); seller net $%s has not moved to the connected account.',
                                coalesce(r.event_name, '?'), to_char(r.since at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                                to_char((coalesce(r.amount, 0) - coalesce(r.seller_fee, 0)) / 100.0, 'FM999999990.00'))
                    else format('Transfer for "%s" is %s since %s with payout_released_at null and no stripe_transfer_id; seller net $%s awaiting release for more than %s minutes.',
                                coalesce(r.event_name, '?'), r.status, to_char(r.since at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                                to_char((coalesce(r.amount, 0) - coalesce(r.seller_fee, 0)) / 100.0, 'FM999999990.00'), v_mins) end,
               'p2', null, 'release_stuck');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('release_stuck', v_keys));
end;
$ops$;
revoke all on function ops.detect_release_stuck() from public, anon, authenticated, service_role;
