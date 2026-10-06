-- ============================================================================
-- ROLLBACK of 20260925010000_release_stuck_seller_win.sql (registry 151)
-- Restores ops.detect_release_stuck's APPLIED pre-151 body, 117:276-322,
-- extracted verbatim (not retyped), inside one transaction. It refuses unless
-- the current body is exactly 151's, and raises unless the restored body hashes
-- to 117's. No data is touched: open release_stuck cases stay as they are, and
-- the next detector run re-dates them by 117's rule.
-- Consequence of rolling back: a seller-win on a transfer frozen before sending
-- is again never flagged, and a seller-win on a reported transfer is again dated
-- by its send-time auto_release_at (flagged inside the payout sweep's quiet
-- period, or up to 72 hours late).
--   151 prosrc md5:     6e0a9c5d4364b352b4b8bc321931572b
--   pre-151 prosrc md5: 12ed7fc21fb4eccc3fac6e5865d75ee0
-- ============================================================================
BEGIN;

DO $guard$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'ops.detect_release_stuck()'::regprocedure)
       IS DISTINCT FROM '6e0a9c5d4364b352b4b8bc321931572b' THEN
    RAISE EXCEPTION 'ROLLBACK_REFUSED: ops.detect_release_stuck is not the 151 body; nothing changed.';
  END IF;
END $guard$;

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
           case when t.payout_released_at is null
                then case when t.status = 'auto_released' then coalesce(t.auto_release_at, t.buyer_confirmed_at)
                          else coalesce(t.buyer_confirmed_at, t.auto_release_at) end
                else t.payout_released_at end as since,
           (t.payout_released_at is not null) as released_locally
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
               case when r.released_locally
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

DO $verify$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'ops.detect_release_stuck()'::regprocedure)
       IS DISTINCT FROM '12ed7fc21fb4eccc3fac6e5865d75ee0' THEN
    RAISE EXCEPTION 'ROLLBACK_VERIFY_FAILED: restored body does not hash to 117''s.';
  END IF;
END $verify$;

COMMIT;
