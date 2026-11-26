-- LOCAL DRAFT. No migration registration/apply or owner data mutation yet.
-- Owner one-time pre-launch exception approved November 26, 2026.
-- Full row snapshots are retained privately; no provider API is reachable here.
begin;
set local lock_timeout='3s';
create table ops.prelaunch_archive_batch (
 id uuid primary key default gen_random_uuid(),
 singleton boolean not null default true unique check(singleton),
 payment_ids uuid[] not null,
 snapshot jsonb not null,
 snapshot_sha256 text not null check(snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 backup_sha256 text check(backup_sha256 ~ '^[0-9a-f]{64}$'),
 prepared_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '7 days',
 archived_at timestamptz,
 archived_by uuid,
 reason text,
 receipt jsonb,
 check(cardinality(payment_ids)=57),
 check(snapshot_sha256=encode(sha256(convert_to(snapshot::text,'UTF8')),'hex'))
);
alter table ops.prelaunch_archive_batch enable row level security;
revoke all on ops.prelaunch_archive_batch from public,anon,authenticated,service_role;

create function ops.prelaunch_archive_collect(p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $archive$
declare v_transfers uuid[]; v_cases uuid[];
begin
 select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_transfers
 from public.transfers where payment_id=any(p_ids);
 select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_cases
 from ops."case" where (subject_kind='payment' and subject_id=any(p_ids))
 or (subject_kind='transfer' and subject_id=any(v_transfers));
 return jsonb_build_object(
  'public.payments', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.payments r where r.id = any(p_ids)),
  'public.transfers', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.transfers r where r.payment_id = any(p_ids)),
  'public.webhook_retries', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.webhook_retries r where r.payment_id = any(p_ids)),
  'public.disputes', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.disputes r where r.payment_id = any(p_ids) or r.transfer_id = any(v_transfers)),
  'public.dispute_resolutions', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.dispute_resolutions r where r.transfer_id = any(v_transfers)),
  'public.payout_decisions', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.payout_decisions r where r.payment_id = any(p_ids) or r.transfer_id = any(v_transfers)),
  'public.seller_flags', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.seller_flags r where r.transfer_id = any(v_transfers)),
  'public.transfer_notifications', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.transfer_notifications r where r.transfer_id = any(v_transfers)),
  'public.payment_refunds', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.payment_refunds r where r.payment_id = any(p_ids)),
  'public.payment_refund_state', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.payment_refund_state r where r.payment_id = any(p_ids)),
  'public.payment_refund_state_log', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.payment_refund_state_log r where r.payment_id = any(p_ids)),
  'public.notifications', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from public.notifications r where r.metadata->>'transfer_id' = any(v_transfers::text[])),
  'ops.alert', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from ops.alert r where r.payload->>'case_id'=any(v_cases::text[])),
  'ops.case', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from ops."case" r where r.id = any(v_cases)),
  'ops.case_note', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from ops.case_note r where r.case_id = any(v_cases)),
  'ops.case_event', (select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),'[]'::jsonb) from ops.case_event r where r.case_id = any(v_cases)));
end $archive$;
revoke all on function ops.prelaunch_archive_collect(uuid[]) from public,anon,authenticated,service_role;

create function ops.prelaunch_archive_assert_manifest(p_ids uuid[])
returns void language plpgsql security definer set search_path='' set timezone='UTC'
as $archive$
declare v_digest text; v_transfers uuid[]; v_cases uuid[];
begin
 select encode(sha256(convert_to(string_agg(x::text,',' order by x),'UTF8')),'hex') into v_digest from unnest(p_ids) x;
 if (select count(*) from public.payments)<>59 then raise exception 'archive_refused: live payment inventory changed';end if;
 if cardinality(p_ids) is distinct from 57 or v_digest is distinct from '04c1eca751a00bf3a81cb5b3559e026d3ddc1e1fbe073a2d7867388f65a006ad' then
 raise exception 'archive_refused: exact approved manifest required'; end if;
 if (select count(*) from public.payments where id in(
 'd0508a55-84de-40d8-b696-9e0ea4396bb3','d44d0d3d-90e0-4e3b-a6bd-2769275ec741'))<>2
 or not exists(select 1 from public.transfers where id='abd8257e-07ee-4718-99d0-d9c8e6dc5c1e'
 and payment_id='d0508a55-84de-40d8-b696-9e0ea4396bb3') then
 raise exception 'archive_refused: protected sale graph missing'; end if;
 if exists(select 1 from unnest(p_ids) x where x is null or x in(
 'd0508a55-84de-40d8-b696-9e0ea4396bb3'::uuid,'d44d0d3d-90e0-4e3b-a6bd-2769275ec741'::uuid))
 or (select count(*) from public.payments where id=any(p_ids))<>57 then
 raise exception 'archive_refused: protected or missing payment'; end if;
 if exists(select 1 from public.payments where id=any(p_ids) and
 (created_at>='2026-11-03T21:26:45.213Z'::timestamptz or mode='native_primary')) then
 raise exception 'archive_refused: not a legacy pre-launch test'; end if;
 if exists(select 1 from kernel.payment_native where payment_id=any(p_ids))
 or exists(select 1 from kernel.refund where payment_id=any(p_ids))
 or exists(select 1 from kernel.dispute_native where payment_id=any(p_ids))
 or exists(select 1 from market.market_sale where payment_id=any(p_ids)) then
 raise exception 'archive_refused: native money or custody reference'; end if;
 select coalesce(array_agg(id),'{}'::uuid[]) into v_transfers from public.transfers where payment_id=any(p_ids);
 select coalesce(array_agg(id),'{}'::uuid[]) into v_cases from ops."case"
 where (subject_kind='payment' and subject_id=any(p_ids)) or(subject_kind='transfer' and subject_id=any(v_transfers));
 if exists(select 1 from ops.alert where payload->>'case_id'=any(v_cases::text[]) and notify_request_id is not null and delivered_at is null) then raise exception 'archive_refused: alert delivery still in flight';end if;
 if exists(select 1 from public.payout_attempts where payment_id=any(p_ids) or transfer_id=any(v_transfers)) then
 raise exception 'archive_refused: provider payout attempt exists'; end if;
 if exists(select 1 from public.transfers where id=any(v_transfers) and
 (status in('pending','seller_sent') or (status in('auto_released','buyer_confirmed') and
 (payout_released_at is null or stripe_transfer_id is null)))) then
 raise exception 'archive_refused: actionable seller obligation'; end if;
 if exists(select 1 from ops.action where
 (subject_kind='payment' and subject_id=any(p_ids)) or(subject_kind='transfer' and subject_id=any(v_transfers))
 or(subject_kind='case' and subject_id=any(v_cases))) then
 raise exception 'archive_refused: privileged action history needs separate review'; end if;
 if exists(select 1 from public.disputes where
 (payment_id=any(p_ids) or transfer_id=any(v_transfers)) and
 ((payment_id is not null and not(payment_id=any(p_ids))) or
 (transfer_id is not null and not(transfer_id=any(v_transfers)))))
 or exists(select 1 from public.payout_decisions where
 (payment_id=any(p_ids) or transfer_id=any(v_transfers)) and
 ((payment_id is not null and not(payment_id=any(p_ids))) or
 (transfer_id is not null and not(transfer_id=any(v_transfers))))) then
 raise exception 'archive_refused: cross-scope reference'; end if;
end $archive$;
revoke all on function ops.prelaunch_archive_assert_manifest(uuid[]) from public,anon,authenticated,service_role;

-- Private preparation only. No authenticated/service-role execution grant.
create function ops.prelaunch_archive_prepare(p_ids uuid[])
returns uuid language plpgsql security definer set search_path='' set timezone='UTC'
as $archive$
declare v_snapshot jsonb; v_id uuid;
begin
 perform ops.prelaunch_archive_assert_manifest(p_ids);
 v_snapshot:=ops.prelaunch_archive_collect(p_ids);
 insert into ops.prelaunch_archive_batch(payment_ids,snapshot,snapshot_sha256)
 values(p_ids,v_snapshot,encode(sha256(convert_to(v_snapshot::text,'UTF8')),'hex')) returning id into v_id;
 return v_id;
end $archive$;
revoke all on function ops.prelaunch_archive_prepare(uuid[]) from public,anon,authenticated,service_role;

create function ops.prelaunch_archive_read()
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $archive$
declare b ops.prelaunch_archive_batch; v_counts jsonb;
begin
 perform ops.assert_role(array['platform_admin']);
 select * into b from ops.prelaunch_archive_batch limit 1;
 if not found then return jsonb_build_object('state','not_prepared','payments','[]'::jsonb); end if;
 select jsonb_object_agg(key,jsonb_array_length(value)) into v_counts from jsonb_each(b.snapshot);
 return jsonb_build_object('id',b.id,'state',case when b.archived_at is null then 'prepared' else 'archived' end,
 'snapshot_sha256',b.snapshot_sha256,'backup_verified',b.backup_sha256=b.snapshot_sha256,
 'execution_ready',coalesce(b.archived_at is null and b.expires_at>now() and b.backup_sha256=b.snapshot_sha256,false),
 'prepared_at',b.prepared_at,'expires_at',b.expires_at,'archived_at',b.archived_at,'counts',v_counts,'receipt',b.receipt,
 'payments',(select coalesce(jsonb_agg(jsonb_build_object('id',p->>'id','created_at',p->>'created_at',
 'amount',(p->>'amount')::integer,'total',(p->>'total')::integer,'status',p->>'status','mode',p->>'mode') order by p->>'created_at'),'[]'::jsonb)
 from jsonb_array_elements(b.snapshot->'public.payments') p));
end $archive$;
revoke all on function ops.prelaunch_archive_read() from public,anon,authenticated,service_role;
grant execute on function ops.prelaunch_archive_read() to authenticated;

create function ops.prelaunch_archive_execute(p_batch uuid,p_snapshot_sha256 text,p_reason text,p_confirmation text)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $archive$
declare b ops.prelaunch_archive_batch; v_current jsonb; v_transfers uuid[]; v_cases uuid[];
 v_keep jsonb; v_kept_after jsonb; v_counts jsonb;
begin
 perform ops.assert_role(array['platform_admin']);
 perform set_config('lock_timeout','3s',true);
 if p_confirmation is distinct from 'ARCHIVE 57 TEST ORDERS' or char_length(btrim(coalesce(p_reason,''))) not between 15 and 2000 then
 raise exception 'archive_refused: confirmation and written reason required'; end if;
 perform pg_advisory_xact_lock(hashtext('ops.prelaunch_archive_once'));
 select * into b from ops.prelaunch_archive_batch where id=p_batch for update;
 if not found or b.snapshot_sha256 is distinct from p_snapshot_sha256 then
 raise exception 'archive_refused: batch or preview mismatch'; end if;
 if b.archived_at is not null then return b.receipt; end if;
 if encode(sha256(convert_to(b.snapshot::text,'UTF8')),'hex') is distinct from b.snapshot_sha256 then raise exception 'archive_refused: snapshot integrity mismatch';end if;
 if b.expires_at<now() or b.backup_sha256 is distinct from b.snapshot_sha256 then
 raise exception 'archive_refused: expired batch or unverified backup'; end if;
 -- These locks also fence detector/queue writes while the exact before-image is checked.
 lock table public.payments,public.transfers,public.webhook_retries,public.disputes,
 public.dispute_resolutions,public.payout_decisions,public.seller_flags,public.transfer_notifications,
 public.payment_refunds,public.payment_refund_state,public.payment_refund_state_log,public.payout_attempts,
 public.notifications,ops."case",ops.case_note,ops.case_event,ops.alert,ops.action in share row exclusive mode nowait;
 perform ops.prelaunch_archive_assert_manifest(b.payment_ids);
 -- Unknown cascading dependencies or delete hooks must never be silently lost.
 if exists(select 1 from pg_constraint c where c.contype='f' and c.confrelid in(
 'public.payments'::regclass,'public.transfers'::regclass,'ops.case'::regclass,
 'ops.case_note'::regclass,'ops.case_event'::regclass,'public.webhook_retries'::regclass,
 'public.disputes'::regclass,'public.dispute_resolutions'::regclass,'public.payout_decisions'::regclass,
 'public.seller_flags'::regclass,'public.transfer_notifications'::regclass,
 'public.payment_refunds'::regclass,'public.payment_refund_state'::regclass,
 'public.payment_refund_state_log'::regclass,'public.notifications'::regclass,'ops.alert'::regclass)
 and c.conname not in('dispute_resolutions_transfer_id_fkey','webhook_retries_payment_id_fkey',
 'transfers_payment_id_fkey','transfer_notifications_transfer_id_fkey','seller_flags_transfer_id_fkey',
 'disputes_payment_id_fkey','disputes_transfer_id_fkey','payout_decisions_transfer_id_fkey',
 'payout_decisions_payment_id_fkey','payment_native_payment_id_fkey','refund_payment_id_fkey',
 'market_sale_payment_id_fkey','dispute_native_payment_id_fkey','case_note_case_id_fkey',
 'case_event_case_id_fkey','payment_refund_state_payment_id_fkey','payment_refund_state_log_payment_id_fkey',
 'payout_attempts_transfer_id_fkey','payout_attempts_payment_id_fkey','payment_refunds_payment_id_fkey')) then
 raise exception 'archive_refused: unreviewed dependent foreign key'; end if;
 if exists(select 1 from pg_trigger g where not g.tgisinternal and (g.tgtype::int & 8)=8
 and g.tgrelid in('public.payments'::regclass,'public.transfers'::regclass,'ops.case'::regclass,
 'ops.case_note'::regclass,'ops.case_event'::regclass,'public.webhook_retries'::regclass,
 'public.disputes'::regclass,'public.dispute_resolutions'::regclass,'public.payout_decisions'::regclass,
 'public.seller_flags'::regclass,'public.transfer_notifications'::regclass,
 'public.payment_refunds'::regclass,'public.payment_refund_state'::regclass,
 'public.payment_refund_state_log'::regclass,'public.notifications'::regclass,'ops.alert'::regclass)
 and g.tgname not in('tg_case_note_append_only','tg_case_event_append_only',
 'trg_payment_refunds_append_only','trg_payment_refund_state_log_append_only')) then
 raise exception 'archive_refused: unreviewed delete trigger'; end if;
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('ops.detect_paid_unsettled()')) is distinct from '157189091779cf6ba5f3541ab0110edc' then raise exception 'archive_refused: reviewed native detector required';end if;
 v_current:=ops.prelaunch_archive_collect(b.payment_ids);
 if v_current is distinct from b.snapshot then raise exception 'archive_refused: source changed since backup'; end if;
 select jsonb_build_object('payments',(select jsonb_agg(to_jsonb(p) order by p.id) from public.payments p
 where id in('d0508a55-84de-40d8-b696-9e0ea4396bb3','d44d0d3d-90e0-4e3b-a6bd-2769275ec741')),
 'transfer',(select to_jsonb(t) from public.transfers t where id='abd8257e-07ee-4718-99d0-d9c8e6dc5c1e')) into v_keep;
 select coalesce(array_agg((p->>'id')::uuid),'{}'::uuid[]) into v_transfers from jsonb_array_elements(b.snapshot->'public.transfers') p;
 select coalesce(array_agg((p->>'id')::uuid),'{}'::uuid[]) into v_cases from jsonb_array_elements(b.snapshot->'ops.case') p;
 -- Temporary, transaction-local maintenance under table locks, solely for the approved
 -- backed-up rows. Every trigger is re-enabled before returning; exceptions roll back DDL.
 alter table ops.case_note disable trigger tg_case_note_append_only;
 alter table ops.case_event disable trigger tg_case_event_append_only;
 alter table public.payment_refunds disable trigger trg_payment_refunds_append_only;
 alter table public.payment_refund_state_log disable trigger trg_payment_refund_state_log_append_only;
 delete from ops.alert where alert_key in(select p->>'alert_key' from jsonb_array_elements(b.snapshot->'ops.alert') p);
 delete from ops.case_note where case_id=any(v_cases);
 delete from ops.case_event where case_id=any(v_cases);
 delete from ops."case" where id=any(v_cases);
 delete from public.notifications where id in(select (p->>'id')::uuid from jsonb_array_elements(b.snapshot->'public.notifications') p);
 delete from public.webhook_retries where payment_id=any(b.payment_ids);
 delete from public.disputes where payment_id=any(b.payment_ids) or transfer_id=any(v_transfers);
 delete from public.dispute_resolutions where transfer_id=any(v_transfers);
 delete from public.payout_decisions where payment_id=any(b.payment_ids) or transfer_id=any(v_transfers);
 delete from public.seller_flags where transfer_id=any(v_transfers);
 delete from public.transfer_notifications where transfer_id=any(v_transfers);
 delete from public.payment_refunds where payment_id=any(b.payment_ids);
 delete from public.payment_refund_state_log where payment_id=any(b.payment_ids);
 delete from public.payment_refund_state where payment_id=any(b.payment_ids);
 delete from public.transfers where id=any(v_transfers);
 delete from public.payments where id=any(b.payment_ids);
 alter table ops.case_note enable trigger tg_case_note_append_only;
 alter table ops.case_event enable trigger tg_case_event_append_only;
 alter table public.payment_refunds enable trigger trg_payment_refunds_append_only;
 alter table public.payment_refund_state_log enable trigger trg_payment_refund_state_log_append_only;
 perform ops.detect_paid_unsettled();
 perform ops.refresh_metrics();
 select jsonb_build_object('payments',(select jsonb_agg(to_jsonb(p) order by p.id) from public.payments p
 where id in('d0508a55-84de-40d8-b696-9e0ea4396bb3','d44d0d3d-90e0-4e3b-a6bd-2769275ec741')),
 'transfer',(select to_jsonb(t) from public.transfers t where id='abd8257e-07ee-4718-99d0-d9c8e6dc5c1e')) into v_kept_after;
 if v_keep is distinct from v_kept_after or (select count(*) from public.payments where id=any(b.payment_ids))<>0 then
 raise exception 'archive_refused: postcondition mismatch'; end if;
 select jsonb_object_agg(key,jsonb_array_length(value)) into v_counts from jsonb_each(b.snapshot);
 update ops.prelaunch_archive_batch set archived_at=now(),archived_by=auth.uid(),reason=btrim(p_reason),
 receipt=jsonb_build_object('status','archived','batch_id',b.id,'counts',v_counts,'snapshot_sha256',b.snapshot_sha256)
 where id=b.id returning receipt into b.receipt;
 insert into ops.audit(actor,actor_role,action,subject_kind,subject_id,reason,after)
 values(auth.uid(),ops.actor_role(),'prelaunch_tests.archived','prelaunch_archive',b.id,btrim(p_reason),b.receipt);
 return b.receipt;
end $archive$;
revoke all on function ops.prelaunch_archive_execute(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function ops.prelaunch_archive_execute(uuid,text,text,text) to authenticated;
commit;
