begin;
DO $rollback$
begin
 if to_regclass('ops.prelaunch_archive_batch') is null then
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('ops.detect_paid_unsettled()'))='b658f11e3350a30338186d9b2a242743' then return;end if;
  raise exception 'rollback_refused: archive absent but detector differs';
 end if;
 if exists(select 1 from ops.prelaunch_archive_batch) then raise exception 'rollback_refused: retain archive data; reviewed restoration required';end if;
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('ops.detect_paid_unsettled()')) is distinct from '157189091779cf6ba5f3541ab0110edc' then raise exception 'rollback_refused: detector changed';end if;
 execute 'drop function ops.prelaunch_archive_execute(uuid,text,text,text)';
 execute 'drop function ops.prelaunch_archive_read()';
 execute 'drop function ops.prelaunch_archive_prepare(uuid[])';
 execute 'drop function ops.prelaunch_archive_assert_manifest(uuid[])';
 execute 'drop function ops.prelaunch_archive_collect(uuid[])';
 execute 'drop table ops.prelaunch_archive_batch';
 execute $restore_native$-- Restore the exact predecessor detector, without touching any records.
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
$ops$;$restore_native$;
end $rollback$;
commit;
