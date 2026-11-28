--219 full-schema atomic archive controls; no production row content.
begin;
select plan(7);
insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values
(tap.seller(),'catalog-seller@test.local','{"provider":"email"}','{}'),(tap.buyer(),'catalog-buyer@test.local','{"provider":"email"}','{}'),(tap.admin_user(),'catalog-admin@test.local','{"provider":"email"}','{}'),(tap.other_user(),'catalog-support@test.local','{"provider":"email"}','{}')on conflict(id)do nothing;
insert into public.admin_users(user_id,label)values(tap.admin_user(),'TEST ADMIN')on conflict do nothing;
insert into kernel.platform_role(identity_id,role,granted_by)values(tap.other_user(),'platform_support',tap.admin_user());
insert into public.listings(id,seller_id,event_name,venue,neighborhood,event_date,event_time,ticket_type,quantity,transfer_method,starting_bid,buy_now_enabled,buy_now_price,duration_hours,starts_at,ends_at,current_bid,cover_image_path,auction_status,created_at)
select id,tap.seller(),'Archived fixture','Test Hall','wynwood',current_date+30,'21:00','GA',1,'mobile_transfer',100,true,200,24,now(),now()+interval '24 hours',100,'fixtures/catalog.jpg','active','2026-09-01'
from unnest(ops.prelaunch_listing_ids()||array['e4bdc0a7-b7b1-4b2a-a791-677b8c48739d','1add482e-5ffa-41e5-8b9a-592284ec3a17','5bf59649-2a9f-462d-8f48-9f5d3212361f','6ad86aa9-343b-4c54-826f-20dc10c0cc9c','49bd4a3b-20b6-4f60-8f59-c07288ea27df']::uuid[])id;
insert into public.bids(listing_id,bidder_id,amount)values((ops.prelaunch_listing_ids())[1],tap.buyer(),200);
select set_config('app.bypass_listing_guard','on',true);
update public.listings set auction_status='cancelled' where id=any(ops.prelaunch_listing_ids());
insert into public.listing_visibility(listing_id,hidden_reason,hidden_by)select id,'Synthetic archive fixture','test'from unnest(ops.prelaunch_listing_ids())id;
create temp table catalog_proof as select ops.prelaunch_listing_prepare()digest,null::jsonb receipt,
(select jsonb_agg(to_jsonb(l)order by id)from public.listings l where not(id=any(ops.prelaunch_listing_ids())))keep;
grant select,update on catalog_proof to authenticated;
update ops.prelaunch_listing_archive set backup_sha256=snapshot_sha256;
create temp table safeupdate_executor as select pg_get_functiondef('ops.prelaunch_listing_execute(text,text,text)'::regprocedure)src;
LOAD 'safeupdate';
SET LOCAL safeupdate.enabled = true;
select throws_ok($$update ops.prelaunch_listing_archive set backup_sha256=backup_sha256$$,'21000','UPDATE requires a WHERE clause','actual API safeupdate guard is loaded and rejects unbounded updates');
select tap.login(tap.admin_user());
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}')::text,true);
select is(ops.prelaunch_listing_diagnose()->>'status','checked_no_changes','full archive passes with API guard enabled, then rolls back');
select tap.logout();
select is((select count(*)::int from public.listings),118,'all listings survive safety check');
select ok((select archived_at is null from ops.prelaunch_listing_archive),'batch remains unexecuted');
DO $negative$declare d text;begin
 select src into d from safeupdate_executor;
 execute replace(d,$new$update ops.prelaunch_listing_archive set archived_at=now(),archived_by=auth.uid(),reason=trim(p_reason),receipt=r where singleton=true and archived_at is null and snapshot_sha256=p_digest and backup_sha256=p_digest;
 get diagnostics n=row_count;if n<>1 then raise exception 'catalog_archive_refused: batch completion changed';end if;$new$,$old$update ops.prelaunch_listing_archive set archived_at=now(),archived_by=auth.uid(),reason=trim(p_reason),receipt=r;$old$);
end $negative$;
select tap.login(tap.admin_user());
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}')::text,true);
select is(ops.prelaunch_listing_diagnose()->>'code','21000','old executor reproduces real API error with same fixture');
select is(ops.prelaunch_listing_diagnose()->>'message','UPDATE requires a WHERE clause','negative control reproduces exact production failure');
select tap.logout();
DO $restore$begin execute(select src from safeupdate_executor);end $restore$;
select is((select count(*)::int from ops.audit where action='prelaunch_listings.archived'),0,'no archive audit or data move survived either diagnostic');
select *from finish();
rollback;
