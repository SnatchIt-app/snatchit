--219 full-schema atomic archive controls; no production row content.
begin;
select plan(24);
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
select ok(not has_table_privilege('authenticated','ops.prelaunch_listing_archive','SELECT'),'snapshot is private');
select ok(not has_function_privilege('anon','ops.prelaunch_listing_execute(text,text,text)','EXECUTE'),'anonymous cannot execute');
select ok(not has_function_privilege('service_role','ops.prelaunch_listing_execute(text,text,text)','EXECUTE'),'service role has no bypass');
select tap.login(tap.admin_user());
select throws_ok($$select ops.prelaunch_listing_execute(digest,'Owner approved listing cleanup','ARCHIVE 113 OLD LISTINGS')from catalog_proof$$,'P0001','step_up_unavailable: the session carries no aal claim','MFA required');
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}')::text,true);
select throws_ok($$select ops.prelaunch_listing_execute(digest,'Owner approved listing cleanup','wrong')from catalog_proof$$,'P0001','catalog_archive_refused: exact confirmation and reason required','exact confirmation required');
select throws_ok($$select ops.prelaunch_listing_execute(digest,'Owner approved listing cleanup','ARCHIVE 113 OLD LISTINGS')from catalog_proof$$,'P0001','catalog_archive_refused: verified backup required','unverified backup blocks execution');
select tap.logout();
update ops.prelaunch_listing_archive set backup_sha256=snapshot_sha256;
select set_config('app.bypass_listing_guard','on',true);
update public.listings set current_bid=current_bid+1 where id=(ops.prelaunch_listing_ids())[1];
select tap.login(tap.admin_user());
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}')::text,true);
select throws_ok($$select ops.prelaunch_listing_execute(digest,'Owner approved listing cleanup','ARCHIVE 113 OLD LISTINGS')from catalog_proof$$,'P0001','catalog_archive_refused: source changed since backup','source drift fails closed');
select tap.logout();
update public.listings set current_bid=current_bid-1 where id=(ops.prelaunch_listing_ids())[1];
-- updated_at is part of the exact snapshot; restore it for the unchanged positive fixture.
update public.listings l set updated_at=(j->>'updated_at')::timestamptz from ops.prelaunch_listing_archive b,jsonb_array_elements(b.snapshot->'public.listings')j where l.id=(j->>'id')::uuid;
-- The timestamp trigger deliberately changes updated_at, so make a new valid reviewed snapshot only inside this rollback-only test.
alter table ops.prelaunch_listing_archive disable trigger catalog_archive_immutable;
update ops.prelaunch_listing_archive set snapshot=ops.prelaunch_listing_collect(),snapshot_sha256=encode(sha256(convert_to(ops.prelaunch_listing_collect()::text,'UTF8')),'hex'),backup_sha256=encode(sha256(convert_to(ops.prelaunch_listing_collect()::text,'UTF8')),'hex');
alter table ops.prelaunch_listing_archive enable trigger catalog_archive_immutable;
update catalog_proof set digest=(select snapshot_sha256 from ops.prelaunch_listing_archive);
create table public.catalog_archive_child_test(id uuid primary key,bid_id uuid references public.bids(id) on delete cascade);
select throws_ok($$select ops.prelaunch_listing_assert_scope()$$,'P0001','catalog_archive_refused: unknown dependency or delete hook','new cascading dependency of a bid refuses before any move');
drop table public.catalog_archive_child_test;
select ops.case_upsert('manual','listing',(ops.prelaunch_listing_ids())[1],null,'Closed archive fixture','Retain historical case','p3',null,'manual');
update ops."case" set status='dismissed',resolved_at=now(),resolved_by=tap.admin_user() where subject_kind='listing' and subject_id=(ops.prelaunch_listing_ids())[1];
select tap.login(tap.other_user());
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}')::text,true);
select throws_ok($$select ops.prelaunch_listing_execute(digest,'Owner approved listing cleanup','ARCHIVE 113 OLD LISTINGS')from catalog_proof$$,'42501','insufficient_privilege: requires one of {platform_admin} (you are platform_support)','support cannot execute');
select tap.logout();
-- Negative control: dropping only the snapshot comparison makes the same drifted fixture executable, then rollback to the savepoint.
create temp table catalog_executor as select pg_get_functiondef('ops.prelaunch_listing_execute(text,text,text)'::regprocedure)src;
create temp table negative_result(passed boolean);
DO $negative$ declare d text;passed boolean:=false;begin
 begin
  update public.listings set current_bid=current_bid+1 where id=(ops.prelaunch_listing_ids())[1];
  select src into d from catalog_executor;
  if position('ops.prelaunch_listing_collect() is distinct from b.snapshot' in d)=0 then raise exception 'negative control target absent';end if;
  execute replace(d,'ops.prelaunch_listing_collect() is distinct from b.snapshot','false');
  perform tap.login(tap.admin_user());
  perform set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}')::text,true);
  passed:=(select ops.prelaunch_listing_execute(digest,'Synthetic negative control only','ARCHIVE 113 OLD LISTINGS')->>'status'='archived'from catalog_proof);
  raise exception using errcode='PZ001',message='rollback negative control';
 exception when sqlstate 'PZ001' then null;end;
 insert into negative_result values(passed);
end $negative$;
select ok((select passed from negative_result),'negative control proves comparison detects real drift');
select tap.login(tap.admin_user());
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}')::text,true);
update catalog_proof set receipt=ops.prelaunch_listing_execute(digest,'Owner approved listing cleanup','ARCHIVE 113 OLD LISTINGS');
select is((select receipt->>'status'from catalog_proof),'archived','authorized archive completes');
select is(ops.prelaunch_listing_read()->>'state','archived','archive reader confirms completion');
select is(jsonb_array_length(ops.prelaunch_listing_read()->'listings'),113,'history lists all archived IDs');
select ok(not(ops.prelaunch_listing_read() ? 'snapshot'),'reader never returns private snapshot');
select is((select ops.prelaunch_listing_execute(digest,'Owner approved listing cleanup','ARCHIVE 113 OLD LISTINGS')from catalog_proof),(select receipt from catalog_proof),'replay is exact no-op');
select is(ops.listing_detail((ops.prelaunch_listing_read()->'listings'->0->>'id')::uuid)->'listing'->>'status','archived','old report listing link resolves to read-only archive');
select is(jsonb_array_length(ops.listing_detail((ops.prelaunch_listing_read()->'listings'->0->>'id')::uuid)->'cases'),1,'retained closed case stays visible on archived detail');
select tap.logout();
select is((select count(*)::int from public.listings),5,'only five kept listings remain operational');
select is((select jsonb_agg(to_jsonb(l)order by id)from public.listings l),(select keep from catalog_proof),'all kept listing rows unchanged');
select is((select count(*)::int from public.bids),0,'archived bids leave active auctions');
select is(jsonb_array_length((select snapshot->'public.bids'from ops.prelaunch_listing_archive)),1,'bid history remains in recovery snapshot');
select is((select count(*)::int from ops.audit where action='prelaunch_listings.archived'),1,'one audit entry despite replay');
select throws_ok($$update ops.prelaunch_listing_archive set reason='change history'$$,'P0001','catalog archive history is immutable','archive cannot be mutated');
select ok((select backup_sha256=snapshot_sha256 and snapshot_sha256=encode(sha256(convert_to(snapshot::text,'UTF8')),'hex')from ops.prelaunch_listing_archive),'recovery snapshot hash remains verified');
select *from finish();
rollback;
