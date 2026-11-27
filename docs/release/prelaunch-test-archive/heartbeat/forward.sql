begin;
set local lock_timeout='3s';
select pg_advisory_xact_lock(hashtext('ops.prelaunch_archive_once'));
DO $pin$ begin
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('ops.prelaunch_archive_execute(uuid,text,text,text)')) is distinct from '03cc6493983c8e460b40aa1cb5782c81' then raise exception 'unrecognized archive executor';end if;
 if exists(select from ops.prelaunch_archive_batch where archived_at is not null) then raise exception 'archive already completed; retain existing history';end if;
end $pin$;
alter table ops.prelaunch_archive_batch
 add column execution_snapshot jsonb,
 add column execution_snapshot_sha256 text,
 add constraint prelaunch_execution_required_ck check (archived_at is null or execution_snapshot is not null),
 add constraint prelaunch_execution_copy_ck check (
 (execution_snapshot is null and execution_snapshot_sha256 is null)
 or (execution_snapshot is not null and execution_snapshot_sha256 is not null
 and execution_snapshot_sha256=encode(sha256(convert_to(execution_snapshot::text,'UTF8')),'hex')));
-- Only case-monitoring timestamps may advance after review. Every other byte stays exact.
create function ops.prelaunch_archive_same_reviewed_rows(p_reviewed jsonb,p_current jsonb)
returns boolean language plpgsql immutable set search_path='' set timezone='UTC'
as $heartbeat$
declare a jsonb; b jsonb; x jsonb; y jsonb;
begin
 if jsonb_typeof(p_reviewed) is distinct from 'object' or jsonb_typeof(p_current) is distinct from 'object'
 or (p_reviewed-'ops.case') is distinct from (p_current-'ops.case') then return false;end if;
 a:=p_reviewed->'ops.case';b:=p_current->'ops.case';
 if jsonb_typeof(a) is distinct from 'array' or jsonb_typeof(b) is distinct from 'array'
 or jsonb_array_length(a)<>jsonb_array_length(b) then return false;end if;
 if exists(select from jsonb_array_elements(a) z where jsonb_typeof(z)<>'object' or z->>'id' is null)
 or exists(select from jsonb_array_elements(b) z where jsonb_typeof(z)<>'object' or z->>'id' is null)
 or (select count(distinct z->>'id') from jsonb_array_elements(a) z)<>jsonb_array_length(a)
 or (select count(distinct z->>'id') from jsonb_array_elements(b) z)<>jsonb_array_length(b) then return false;end if;
 select coalesce(jsonb_agg(z-'last_seen_at'-'updated_at' order by (z-'last_seen_at'-'updated_at')::text),'[]'::jsonb) into x from jsonb_array_elements(a) z;
 select coalesce(jsonb_agg(z-'last_seen_at'-'updated_at' order by (z-'last_seen_at'-'updated_at')::text),'[]'::jsonb) into y from jsonb_array_elements(b) z;
 if x is distinct from y then return false;end if;
 -- Rewinds, missing or malformed timestamps are never considered a heartbeat.
 if exists(select from jsonb_array_elements(a) o join jsonb_array_elements(b) n on o->>'id'=n->>'id'
 where not coalesce((n->>'last_seen_at')::timestamptz >= (o->>'last_seen_at')::timestamptz
 and (n->>'updated_at')::timestamptz >= (o->>'updated_at')::timestamptz,false)) then return false;end if;
 return true;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then return false;
end $heartbeat$;
revoke all on function ops.prelaunch_archive_same_reviewed_rows(jsonb,jsonb) from public,anon,authenticated,service_role;
create or replace function ops.prelaunch_archive_execute(p_batch uuid,p_snapshot_sha256 text,p_reason text,p_confirmation text)
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
 and not exists(select 1 from(values
   ('public.dispute_resolutions','public.transfers','dispute_resolutions_transfer_id_fkey','transfer_id','a'),
   ('public.webhook_retries','public.payments','webhook_retries_payment_id_fkey','payment_id','a'),
   ('public.transfers','public.payments','transfers_payment_id_fkey','payment_id','a'),
   ('public.transfer_notifications','public.transfers','transfer_notifications_transfer_id_fkey','transfer_id','c'),
   ('public.seller_flags','public.transfers','seller_flags_transfer_id_fkey','transfer_id','n'),
   ('public.disputes','public.payments','disputes_payment_id_fkey','payment_id','a'),
   ('public.disputes','public.transfers','disputes_transfer_id_fkey','transfer_id','a'),
   ('public.payout_decisions','public.transfers','payout_decisions_transfer_id_fkey','transfer_id','c'),
   ('public.payout_decisions','public.payments','payout_decisions_payment_id_fkey','payment_id','n'),
   ('kernel.payment_native','public.payments','payment_native_payment_id_fkey','payment_id','r'),
   ('kernel.refund','public.payments','refund_payment_id_fkey','payment_id','r'),
   ('market.market_sale','public.payments','market_sale_payment_id_fkey','payment_id','r'),
   ('kernel.dispute_native','public.payments','dispute_native_payment_id_fkey','payment_id','r'),
   ('ops.case_note','ops.case','case_note_case_id_fkey','case_id','c'),
   ('ops.case_event','ops.case','case_event_case_id_fkey','case_id','c'),
   ('public.payment_refund_state','public.payments','payment_refund_state_payment_id_fkey','payment_id','a'),
   ('public.payment_refund_state_log','public.payments','payment_refund_state_log_payment_id_fkey','payment_id','a'),
   ('public.payout_attempts','public.transfers','payout_attempts_transfer_id_fkey','transfer_id','a'),
   ('public.payout_attempts','public.payments','payout_attempts_payment_id_fkey','payment_id','a'),
   ('public.payment_refunds','public.payments','payment_refunds_payment_id_fkey','payment_id','a')
 ) a(child,parent,fk,col,del) where c.conrelid=a.child::regclass and c.confrelid=a.parent::regclass
 and c.conname=a.fk and c.confdeltype=a.del::"char"
 and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname=a.col)]::smallint[]
 and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname='id')]::smallint[])) then
 raise exception 'archive_refused: unreviewed dependent foreign key'; end if;
 if exists(select 1 from pg_trigger g where not g.tgisinternal and (g.tgtype::int & 8)=8
 and g.tgrelid in('public.payments'::regclass,'public.transfers'::regclass,'ops.case'::regclass,
 'ops.case_note'::regclass,'ops.case_event'::regclass,'public.webhook_retries'::regclass,
 'public.disputes'::regclass,'public.dispute_resolutions'::regclass,'public.payout_decisions'::regclass,
 'public.seller_flags'::regclass,'public.transfer_notifications'::regclass,
 'public.payment_refunds'::regclass,'public.payment_refund_state'::regclass,
 'public.payment_refund_state_log'::regclass,'public.notifications'::regclass,'ops.alert'::regclass)
 and not(g.tgtype=27 and g.tgenabled='O' and (
 (g.tgrelid='public.dispute_resolutions'::regclass and g.tgname='trg_dispute_resolutions_append_only' and g.tgfoid='public.dispute_resolutions_append_only()'::regprocedure)
 or (g.tgrelid='ops.case_note'::regclass and g.tgname='tg_case_note_append_only' and g.tgfoid='ops.raise_append_only()'::regprocedure)
 or(g.tgrelid='ops.case_event'::regclass and g.tgname='tg_case_event_append_only' and g.tgfoid='ops.raise_append_only()'::regprocedure)
 or(g.tgrelid='public.payment_refunds'::regclass and g.tgname='trg_payment_refunds_append_only' and g.tgfoid='public.payment_refunds_append_only()'::regprocedure)
 or(g.tgrelid='public.payment_refund_state_log'::regclass and g.tgname='trg_payment_refund_state_log_append_only' and g.tgfoid='public.payment_refund_state_log_append_only()'::regprocedure)))) then
 raise exception 'archive_refused: unreviewed delete trigger'; end if;
 if (select md5(prosrc) from pg_proc where oid=to_regprocedure('ops.detect_paid_unsettled()')) is distinct from '157189091779cf6ba5f3541ab0110edc' then raise exception 'archive_refused: reviewed native detector required';end if;
 v_current:=ops.prelaunch_archive_collect(b.payment_ids);
 if not ops.prelaunch_archive_same_reviewed_rows(b.snapshot,v_current) then raise exception 'archive_refused: source changed since backup'; end if;
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
 update ops.prelaunch_archive_batch set execution_snapshot=v_current,
 execution_snapshot_sha256=encode(sha256(convert_to(v_current::text,'UTF8')),'hex'),
 archived_at=now(),archived_by=auth.uid(),reason=btrim(p_reason),
 receipt=jsonb_build_object('status','archived','batch_id',b.id,'counts',v_counts,'snapshot_sha256',b.snapshot_sha256)
 where id=b.id returning receipt into b.receipt;
 insert into ops.audit(actor,actor_role,action,subject_kind,subject_id,reason,after)
 values(auth.uid(),ops.actor_role(),'prelaunch_tests.archived','prelaunch_archive',b.id,btrim(p_reason),b.receipt);
 return b.receipt;
end $archive$;
revoke all on function ops.prelaunch_archive_execute(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function ops.prelaunch_archive_execute(uuid,text,text,text) to authenticated;
commit;
