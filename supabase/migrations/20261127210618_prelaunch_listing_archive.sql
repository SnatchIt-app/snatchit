--219: owner-approved one-time catalog archive. Does not touch identities, money or storage.
begin;
create table ops.prelaunch_listing_archive (
 singleton boolean primary key default true check(singleton),
 listing_ids uuid[] not null check(cardinality(listing_ids)=113),
 snapshot jsonb not null,
 snapshot_sha256 text not null check(snapshot_sha256 ~ '^[a-f0-9]{64}$'),
 backup_sha256 text check(backup_sha256 ~ '^[a-f0-9]{64}$'),
 prepared_at timestamptz not null default now(),
 archived_at timestamptz,archived_by uuid references auth.users(id),
 reason text,receipt jsonb,
 check((archived_at is null and archived_by is null and receipt is null) or
       (archived_at is not null and archived_by is not null and receipt is not null and backup_sha256=snapshot_sha256 and length(trim(reason)) between 15 and 2000))
);
alter table ops.prelaunch_listing_archive enable row level security;
revoke all on ops.prelaunch_listing_archive from public,anon,authenticated,service_role;
create function ops.prelaunch_listing_archive_guard() returns trigger
language plpgsql set search_path='' as $guard$
begin
 if tg_op='DELETE' or old.archived_at is not null then raise exception 'catalog archive history is immutable';end if;
 if new.listing_ids is distinct from old.listing_ids or new.snapshot is distinct from old.snapshot or new.snapshot_sha256 is distinct from old.snapshot_sha256 or new.prepared_at is distinct from old.prepared_at then raise exception 'catalog archive snapshot is immutable';end if;
 return new;
end $guard$;
revoke all on function ops.prelaunch_listing_archive_guard() from public,anon,authenticated,service_role;
create trigger catalog_archive_immutable before update or delete on ops.prelaunch_listing_archive for each row execute function ops.prelaunch_listing_archive_guard();
create function ops.prelaunch_listing_ids() returns uuid[]
language sql immutable set search_path='' as $ids$
 select array['035b040f-49fd-45ef-886f-2ddddc8ccade',
'04fac1f6-dbad-483e-bfcf-5615240da832',
'0523bbd4-ce06-40b9-a3dd-b6fea5027488',
'057a7c8b-310f-47d5-b7ad-ff163c08dff7',
'05ce24ba-9dfc-4ba0-9c49-37cbfcaef644',
'0631d9eb-8120-40e6-943e-af286a5bc9bd',
'084457ec-0aef-4422-ace0-7fe6a90b720b',
'0bd246a2-8c65-4f71-b05a-625c8791ddde',
'0cb432b6-d1f4-4574-8cd8-d0709f39f7ec',
'0fcbff24-7027-467f-a8f3-e7c7b016330b',
'14600b3b-780d-4287-bb17-755fd988b2f5',
'15df03a6-4ca0-4e0a-966a-de072087fbea',
'1862dfdc-a219-4b60-87c2-af082d7c32ff',
'1af1295d-abe0-4409-906d-ae42073a4121',
'20226336-44c6-403f-b0ee-ff12fda1ff9b',
'21bfa877-7be2-4890-af5f-78e48ea9cfaa',
'21c56dae-3777-4e64-902f-61276f3409ca',
'231b326c-5b7e-47f6-94aa-9f9d6457cf5d',
'281f74df-998c-4267-a3e8-f30af8f469cf',
'28aaca8b-72cc-405c-9de8-ceb42fc56d4d',
'292eac43-7ac8-4e41-88ae-98fbfc275079',
'2b106ee7-9b48-4692-8993-0f867ba11732',
'320bd057-bd0b-45c9-a953-8814599fbc28',
'382cf09b-a4ab-4309-abfb-a9b67b2ba100',
'3b2aae8d-6777-4564-89c5-08f45863da99',
'3d53d09c-c5f9-41a4-9b71-183a597e9957',
'3e59ff34-882a-402d-b27c-c92730eb3a93',
'409ac9ba-d9f4-4b01-b61a-c9a7323202a2',
'439428c9-34d0-4aff-b135-9cf6eb93c406',
'46420114-65a6-4201-9919-1f550a9e5728',
'46c8f81c-14ec-4a17-8c4a-cdb6614c0849',
'49fe8b8b-d212-4a06-8afd-8f4c18edbcba',
'4afe3557-9c34-4e89-8cac-df69223b551c',
'4b0138b2-cfc8-4e30-85fe-72fa9defb776',
'4c21515d-58ae-460f-ad97-5757ecc106d4',
'4cb27aab-86f1-4ae2-9ec0-b6c9ecfee8cb',
'4f408dd4-e390-4185-8a9e-882e3661cd4c',
'54c2565c-1c3c-4939-9952-ff51fad82581',
'59eb2da4-2a27-49d1-bae2-8cefef159b0c',
'5c0accf4-d150-42fe-90fe-291c08bc0638',
'5c15374a-ffdb-4450-ab5d-3348eb35bf4c',
'5cc38c82-2bbe-43a6-9180-aa1ab61d4248',
'5f363729-0cda-43f1-9bb0-cf3908dabfb4',
'6352c199-ab34-4bf9-b3ff-bea8376d5a37',
'656ad895-e463-4a3f-bb55-7e63a96513a9',
'669a7e3a-5de6-4a77-93c1-3c871a4fbbaa',
'684e7c9e-e87e-42e5-bb47-2c68d51eb256',
'68cee968-b08e-49f5-8222-77768ee79070',
'68f8f7d0-7c33-4826-b41d-9c08115d014e',
'6a88612d-794c-44ba-835a-b0cd3dfda6d3',
'6c49cfd1-7671-41a8-bfa3-1ad82ba793fd',
'70672ee2-0f7e-4a80-b11b-4c6633fe1e3b',
'7c6b99e2-89e8-480e-9cc4-9cab1efa5580',
'7cc333be-9e98-42d5-826b-73529d2a613b',
'7d0bffc8-45a4-4c8b-bf66-9c67270cd706',
'7e541382-fb4c-447c-aa38-b5032bc84f82',
'7e9a0d42-3151-4bd6-b5bb-64b1990d7b35',
'7f4326b6-31d4-4445-b270-0dd33f832652',
'7fa38871-48da-4b83-848f-754dcce1d0d3',
'80e2d98c-4463-4ddb-9e08-f12564a8b12a',
'8207e14a-542d-4a0d-9519-2f4a2835c6c0',
'8270ee0c-3035-4c8d-a669-2f250cdb9531',
'828b49e2-4712-48bd-b4ee-8454208706af',
'846d3438-5168-4fb1-aeae-3407f4440b1c',
'849913d4-b613-41ae-b3a5-518fc3f69fdd',
'88712654-6b5a-410f-b628-36a7fddaa12b',
'8a36849d-9055-4b1f-8e12-c205c32d42fe',
'8a95f533-49ff-4e54-bd96-f41126922884',
'96d64fb2-f33c-458c-80c0-7fc5daf847d4',
'99f50909-f1d1-440f-ba16-4107e5e9267d',
'a401e54c-36d3-460e-92ce-4e435a2da935',
'a47493fe-c130-491e-9590-65c4932f1d17',
'a7bccd97-33a4-4ecf-ac39-9e822cb52222',
'a7f76db5-32ea-4c3e-9dff-012631add83a',
'a81785bf-3994-4140-9ed6-581699bedae2',
'a8234617-a641-4e0d-be99-263b9248eb32',
'a834c7bc-8f36-425f-8d22-00a0308e4519',
'accff86d-4037-4a65-a6bd-c4c1f1a8315b',
'aed72a34-0422-48be-a8ab-3e71c691d192',
'b0a01d80-c966-4a66-99d7-eea5d55113a3',
'b32c22f3-2d67-46c8-bb16-e3337cd8f18c',
'b5abfae1-404c-4beb-9c2a-cdf1cd311f14',
'b7f2d819-96c4-43ef-848f-73bdd32eb73f',
'b8aa9715-75b4-4985-bb5a-2baf77330597',
'b9411576-c632-4c66-8659-53d17f9acbbd',
'bb859197-d6e3-43b0-bf1d-03b4c3e77d13',
'bf4ad345-0109-40c5-98b9-e620ce313a64',
'c118d2aa-b716-4744-97ba-07130b83db44',
'c1347d4b-00f8-4be3-a4d9-bdd1edade645',
'c15a8b87-7e0e-4f1e-ae4f-a07dd5b33438',
'c22a8bf8-2433-4968-a5ef-dba57133be28',
'c302a9ba-87df-4a2e-94e1-2cd74c38078a',
'c3e98d22-bd19-46c4-95ba-a9fdff92f4d6',
'c50390b3-19ef-40bb-af1d-b7b31b377788',
'c69b7b27-c9a6-4469-8c26-37a86d724b59',
'c79cd0df-fe5c-402d-9b6a-f5154f6dea4d',
'c8d04339-bb33-4bf3-945d-d23d7dd269ca',
'c93f5fc1-e590-4e24-ac9b-a4013b755c6a',
'd4bbe6f4-22ad-447f-b180-760344ed6c4d',
'd8c3e45a-57f8-440b-ab97-8e8c11a772d5',
'dac58ca2-6238-4b04-afb4-da2bb734bc0a',
'db991503-77fc-4713-8d03-be705ea2199a',
'e4a8251d-50d9-4e07-ae23-68f69390d2e3',
'e88343b6-2713-40bf-b224-57f08c303df3',
'ebb0e7d6-264b-4551-a219-19bbb4239578',
'ef82af56-be0e-4028-9ae6-00b455fcf0f0',
'f0e78820-8ea6-4672-bab9-97a624b26aa7',
'f127c2ee-ad8b-4aae-9294-213d763a35c7',
'f265d24d-4cd7-46c5-ae90-f44aee40a101',
'f499dc79-bd50-49ca-a725-1f614be72558',
'f531a192-31d7-4384-b35d-91ab22e6537a',
'fa4b5e91-c870-4cfb-8cbf-e2892bf8440b',
'fbb1334d-d63e-432f-9916-36d1b27e482d']::uuid[]
$ids$;
revoke all on function ops.prelaunch_listing_ids() from public,anon,authenticated,service_role;

create function ops.prelaunch_listing_collect() returns jsonb
language sql stable security definer set search_path='' as $collect$
 select jsonb_build_object(
 'public.listings',coalesce((select jsonb_agg(to_jsonb(l) order by l.id)from public.listings l where id=any(ops.prelaunch_listing_ids())),'[]'::jsonb),
 'public.bids',coalesce((select jsonb_agg(to_jsonb(b) order by b.id)from public.bids b where listing_id=any(ops.prelaunch_listing_ids())),'[]'::jsonb),
 'public.listing_visibility',coalesce((select jsonb_agg(to_jsonb(v) order by v.listing_id)from public.listing_visibility v where listing_id=any(ops.prelaunch_listing_ids())),'[]'::jsonb),
 'public.saved_listings',coalesce((select jsonb_agg(to_jsonb(s) order by to_jsonb(s)::text)from public.saved_listings s where listing_id=any(ops.prelaunch_listing_ids())),'[]'::jsonb))
$collect$;
revoke all on function ops.prelaunch_listing_collect() from public,anon,authenticated,service_role;

create function ops.prelaunch_listing_assert_scope() returns void
language plpgsql security definer set search_path='' as $scope$
declare ids uuid[]:=ops.prelaunch_listing_ids();
 kept uuid[]:=array['e4bdc0a7-b7b1-4b2a-a791-677b8c48739d','1add482e-5ffa-41e5-8b9a-592284ec3a17','5bf59649-2a9f-462d-8f48-9f5d3212361f','6ad86aa9-343b-4c54-826f-20dc10c0cc9c','49bd4a3b-20b6-4f60-8f59-c07288ea27df']::uuid[];
begin
 if (select count(*) from public.listings where id=any(ids))<>113 or
    (select count(*) from public.listings where id=any(kept))<>5 or
    exists(select from public.listings where not(id=any(ids||kept))) or
    exists(select from public.listings where id=any(ids) and (created_at>='2026-10-01T00:00:00Z'::timestamptz or status='reserved' or reserved_by is not null or reserved_until>now()))
 then raise exception 'catalog_archive_refused: exact old-listing scope changed';end if;
 if exists(select from public.payments where listing_id=any(ids)) or exists(select from public.transfers where listing_id=any(ids)) or
    exists(select from public.webhook_retries where listing_id=any(ids)) or exists(select from public.seller_flags where listing_id=any(ids)) or
    exists(select from public.checkout_group_claim where listing_id=any(ids)) or exists(select from market.listing_native where listing_id=any(ids)) or
    exists(select from market.auction where listing_id=any(ids)) or exists(select from market.offer where listing_id=any(ids)) or exists(select from market.market_sale where listing_id=any(ids)) or
    exists(select from ops."case" where subject_id=any(ids) and status not in('resolved','dismissed')) or
    exists(select from public.reports where target_id=any(ids) and status not in('dismissed','actioned')) or
    exists(select from ops.action where subject_id=any(ids) and state in('requested','awaiting_approval','processing','unknown','succeeded_at_provider'))
 then raise exception 'catalog_archive_refused: a listing has a financial, native or unresolved dependency';end if;
 if exists(select from pg_catalog.pg_constraint where contype='f' and confrelid='public.listings'::regclass and conrelid not in(
 'public.bids'::regclass,'public.payments'::regclass,'public.webhook_retries'::regclass,'public.transfers'::regclass,'public.seller_flags'::regclass,'public.saved_listings'::regclass,'public.listing_visibility'::regclass)) or
 exists(select from pg_catalog.pg_trigger where tgrelid in('public.listings'::regclass,'public.bids'::regclass,'public.saved_listings'::regclass,'public.listing_visibility'::regclass) and not tgisinternal and (tgtype::int & 8)<>0)
 then raise exception 'catalog_archive_refused: unknown dependency or delete hook';end if;
end $scope$;
revoke all on function ops.prelaunch_listing_assert_scope() from public,anon,authenticated,service_role;

create function ops.prelaunch_listing_prepare() returns text
language plpgsql security definer set search_path='' as $prepare$
declare s jsonb;d text;
begin
 perform pg_catalog.pg_advisory_xact_lock(21920261127);
 if exists(select from ops.prelaunch_listing_archive) then raise exception 'catalog_archive_refused: batch already prepared';end if;
 perform ops.prelaunch_listing_assert_scope();
 s:=ops.prelaunch_listing_collect();d:=encode(sha256(convert_to(s::text,'UTF8')),'hex');
 insert into ops.prelaunch_listing_archive(listing_ids,snapshot,snapshot_sha256) values(ops.prelaunch_listing_ids(),s,d);
 return d;
end $prepare$;
revoke all on function ops.prelaunch_listing_prepare() from public,anon,authenticated,service_role;

create function ops.prelaunch_listing_read() returns jsonb
language plpgsql stable security definer set search_path='' as $read$
declare b ops.prelaunch_listing_archive%rowtype;
begin
 perform ops.assert_role(array['platform_admin']);
 select * into b from ops.prelaunch_listing_archive;
 if not found then return jsonb_build_object('state','not_prepared');end if;
 return jsonb_build_object('state',case when b.archived_at is null then 'prepared' else 'archived' end,
 'digest',b.snapshot_sha256,'ready',b.backup_sha256=b.snapshot_sha256,'archived_at',b.archived_at,
 'counts',(select jsonb_object_agg(key,jsonb_array_length(value))from jsonb_each(b.snapshot)),
 'listings',(select jsonb_agg(jsonb_build_object('id',j->>'id','event_name',j->>'event_name')order by j->>'id')from jsonb_array_elements(b.snapshot->'public.listings')j));
end $read$;
revoke all on function ops.prelaunch_listing_read() from public,anon,authenticated,service_role;
grant execute on function ops.prelaunch_listing_read() to authenticated;

create function ops.prelaunch_listing_execute(p_digest text,p_reason text,p_confirmation text) returns jsonb
language plpgsql security definer set search_path='' as $execute$
declare b ops.prelaunch_listing_archive%rowtype;r jsonb;n int;
begin
 perform ops.assert_role(array['platform_admin']);
 if p_confirmation is distinct from 'ARCHIVE 113 OLD LISTINGS' or length(trim(coalesce(p_reason,''))) not between 15 and 2000 then
 raise exception 'catalog_archive_refused: exact confirmation and reason required';end if;
 perform pg_catalog.pg_advisory_xact_lock(21920261127);
 select * into b from ops.prelaunch_listing_archive for update;
 if not found or p_digest is distinct from b.snapshot_sha256 or b.backup_sha256 is distinct from b.snapshot_sha256 then
 raise exception 'catalog_archive_refused: verified backup required';end if;
 if b.archived_at is not null then return b.receipt;end if;
 if (select count(distinct key) from catalog.platform_config where key in('feature.native_issuance_enabled','refund.executor_enabled','payout.executor_enabled'))<>3 or exists(select from catalog.platform_config c where c.key in('feature.native_issuance_enabled','refund.executor_enabled','payout.executor_enabled') and c.version=(select max(c2.version)from catalog.platform_config c2 where c2.key=c.key) and c.value is distinct from 'false'::jsonb) or
 (select value from ops.setting where key='refund_execute_enabled') is distinct from 'false'::jsonb
 then raise exception 'catalog_archive_refused: execution switches must be off';end if;
 perform set_config('lock_timeout','5s',true);
 lock table public.listings,public.bids,public.listing_visibility,public.saved_listings,public.payments,public.transfers,public.webhook_retries,public.seller_flags,public.checkout_group_claim,market.listing_native,market.auction,market.offer,market.market_sale,public.reports,ops."case",ops.action in share row exclusive mode;
 perform ops.prelaunch_listing_assert_scope();
 if b.listing_ids is distinct from ops.prelaunch_listing_ids() or ops.prelaunch_listing_collect() is distinct from b.snapshot or
 encode(sha256(convert_to(b.snapshot::text,'UTF8')),'hex') is distinct from b.snapshot_sha256 then raise exception 'catalog_archive_refused: source changed since backup';end if;
 delete from public.saved_listings where listing_id=any(b.listing_ids);
 get diagnostics n=row_count;if n<>jsonb_array_length(b.snapshot->'public.saved_listings') then raise exception 'catalog_archive_refused: saved count changed';end if;
 delete from public.bids where listing_id=any(b.listing_ids);
 get diagnostics n=row_count;if n<>jsonb_array_length(b.snapshot->'public.bids') then raise exception 'catalog_archive_refused: bid count changed';end if;
 delete from public.listing_visibility where listing_id=any(b.listing_ids);
 get diagnostics n=row_count;if n<>jsonb_array_length(b.snapshot->'public.listing_visibility') then raise exception 'catalog_archive_refused: visibility count changed';end if;
 delete from public.listings where id=any(b.listing_ids);
 get diagnostics n=row_count;if n<>113 then raise exception 'catalog_archive_refused: listing count changed';end if;
 r:=jsonb_build_object('status','archived','digest',b.snapshot_sha256,'listings',113,'kept',5);
 update ops.prelaunch_listing_archive set archived_at=now(),archived_by=auth.uid(),reason=trim(p_reason),receipt=r;
 insert into ops.audit(actor,actor_role,action,subject_kind,reason,after) values(auth.uid(),ops.actor_role(),'prelaunch_listings.archived','none',trim(p_reason),r);
 return r;
end $execute$;
revoke all on function ops.prelaunch_listing_execute(text,text,text) from public,anon,authenticated,service_role;
grant execute on function ops.prelaunch_listing_execute(text,text,text) to authenticated;

-- Preserve the normal listing-detail contract for closed reports/audit links.
-- Live listings retain the byte-identical reader; archived listings have read-only history.
DO $patch$
declare d text;
begin
 select pg_get_functiondef('ops.listing_detail(uuid)'::regprocedure) into d;
 if position($needle$raise exception 'not_found: listing % does not exist'$needle$ in d)=0 then raise exception 'listing reader predecessor drift';end if;
 d:=replace(d,'declare l public.listings%rowtype;','declare l public.listings%rowtype; v_j jsonb; v_b ops.prelaunch_listing_archive%rowtype;');
 d:=replace(d,$needle$  if not found then
    raise exception 'not_found: listing % does not exist'$needle$,$replacement$  if not found then
    select * into v_b from ops.prelaunch_listing_archive where archived_at is not null and p_listing_id=any(listing_ids);
    select j into v_j from jsonb_array_elements(v_b.snapshot->'public.listings')j where j->>'id'=p_listing_id::text;
    if v_j is not null then
     return jsonb_build_object('listing',v_j||jsonb_build_object('status','archived','recorded_status',v_j->>'status','archived_at',v_b.archived_at),
      'seller',ops.user_summary((v_j->>'seller_id')::uuid),'payments','[]'::jsonb,'transfer',null,
      'bids',jsonb_build_object('count',(select count(*)from jsonb_array_elements(v_b.snapshot->'public.bids')j where j->>'listing_id'=p_listing_id::text),
       'highest',(select max((j->>'amount')::numeric)from jsonb_array_elements(v_b.snapshot->'public.bids')j where j->>'listing_id'=p_listing_id::text),
       'highest_bidder_id',v_j->>'highest_bidder_id','recent',coalesce((select jsonb_agg(j order by j->>'created_at' desc)from jsonb_array_elements(v_b.snapshot->'public.bids')j where j->>'listing_id'=p_listing_id::text),'[]'::jsonb)),
      'reports',coalesce((select jsonb_agg(to_jsonb(r))from public.reports r where r.target_type='listing' and r.target_id=p_listing_id),'[]'::jsonb),
      'seller_flags','[]'::jsonb,'cases','[]'::jsonb,'actions',coalesce((select jsonb_agg(ops.action_row(a))from ops.action a where a.subject_kind='listing' and a.subject_id=p_listing_id),'[]'::jsonb),
      'evidence',jsonb_build_object('proof_of_ownership_path',jsonb_build_object('bucket','proof-docs','path',v_j->>'proof_of_ownership_path'),'cover_image_path',jsonb_build_object('bucket','auction-media','path',v_j->>'cover_image_path')));
    end if;
    raise exception 'not_found: listing % does not exist'$replacement$);
 execute d;
end $patch$;
commit;
