-- Complete native issuance is not a missing-resale-transfer incident.
begin;
DO $guard$ begin
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('ops.detect_paid_unsettled()')) is distinct from 'b658f11e3350a30338186d9b2a242743' then
 raise exception 'unrecognized paid-unsettled detector';end if;end $guard$;
create or replace function ops.detect_paid_unsettled()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_grace   integer := ops.setting_int('paid_unsettled_grace_minutes', 10);
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
  v_why     text;
begin
  for r in
    select p.id, p.total, p.amount, p.paid_at, p.created_at, p.stripe_payment_intent_id,
           l.status as listing_status, l.event_name,
           exists (select 1 from public.transfers t where t.payment_id = p.id) as has_transfer
      from public.payments p
      left join public.listings l on l.id = p.listing_id
     where p.status = 'succeeded'
       and coalesce(p.paid_at, p.created_at) < now() - make_interval(mins => v_grace)
       -- Native issuance commits its order/payment link atomically. It has no resale listing
       -- or resale transfer. Unlinked/mismatched native payments remain actionable here.
       and not exists (
         select 1 from kernel.payment_native pn join venue."order" o on o.order_id=pn.order_id
          where p.mode='native_primary' and pn.payment_id=p.id and o.status='paid'
            and o.buyer_id=p.buyer_id and pn.amount_minor=o.total_minor and pn.amount_minor=p.amount
       )
       and (l.status is distinct from 'sold'
            or not exists (select 1 from public.transfers t where t.payment_id = p.id))
     order by coalesce(p.paid_at, p.created_at)
  loop
    v_scanned := v_scanned + 1;
    v_why := concat_ws('; ',
               case when r.listing_status is distinct from 'sold'
                    then format('listing.status is %s (expected sold)', coalesce(r.listing_status, 'missing')) end,
               case when not r.has_transfer then 'no transfer row exists for this payment' end);
    v_res := ops.detect_case('paid_unsettled', 'payment', r.id, null,
               'Paid but not settled',
               format('Payment %s captured $%s (%s) at %s for "%s" — %s.',
                      r.stripe_payment_intent_id, to_char(r.total / 100.0, 'FM999999990.00'), 'USD',
                      to_char(coalesce(r.paid_at, r.created_at) at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                      coalesce(r.event_name, '?'), v_why),
               'p1', null, 'paid_unsettled');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('paid_unsettled', v_keys));
end;
$ops$;
commit;
