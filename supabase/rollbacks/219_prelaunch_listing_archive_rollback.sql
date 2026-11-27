begin;
DO $guard$ begin
 perform pg_catalog.pg_advisory_xact_lock(21920261127);
 if exists(select from ops.prelaunch_listing_archive) then raise exception 'rollback_refused: catalog archive backup/history must be retained';end if;
end $guard$;
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
drop function ops.prelaunch_listing_execute(text,text,text);
drop function ops.prelaunch_listing_read();
drop function ops.prelaunch_listing_prepare();
drop function ops.prelaunch_listing_assert_scope();
drop function ops.prelaunch_listing_collect();
drop function ops.prelaunch_listing_ids();
drop table ops.prelaunch_listing_archive;
drop function ops.prelaunch_listing_archive_guard();
commit;
