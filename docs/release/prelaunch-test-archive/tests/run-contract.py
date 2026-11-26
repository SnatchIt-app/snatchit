#!/usr/bin/env python3
"""Starts only a unique local Unix-socket cluster; retains data/evidence; no URLs/credentials."""
import pathlib,subprocess,tempfile,os,hashlib,json,uuid,sys
HERE=pathlib.Path(__file__).resolve().parent
if any(k=='DATABASE_URL' or k.startswith('PG') for k in os.environ): raise SystemExit('refusing inherited database settings')
os.umask(0o077)
root=pathlib.Path(tempfile.mkdtemp(prefix='sn-archive-',dir='/private/tmp'));data=root/'data';sock=root/'s';sock.mkdir()
port='55439';env={**os.environ,'PGHOST':str(sock),'PGPORT':port,'PGUSER':os.environ['USER'],'PGDATABASE':'postgres'}
def run(args,**kw):return subprocess.run(args,env=env,check=True,**kw)
def sql(q):return run(['psql','-X','-v','ON_ERROR_STOP=1','-At'],input=q,text=True,capture_output=True).stdout.strip()
started=False
try:
 run(['initdb','-D',str(data),'--auth-local=trust','--auth-host=reject','--no-instructions'],stdout=(root/'initdb.out').open('w'),stderr=subprocess.STDOUT)
 run(['pg_ctl','-D',str(data),'-l',str(root/'postgres.log'),'-o',f"-k {sock} -p {port} -h ''",'-w','start'],stdout=(root/'start.out').open('w'),stderr=subprocess.STDOUT);started=True
 run(['psql','-X','-v','ON_ERROR_STOP=1','-f',str(HERE/'fixture.sql')],stdout=(root/'fixture.out').open('w'),stderr=subprocess.STDOUT)
 ids=[str(uuid.UUID(int=i)) for i in range(1,58)];csv=','.join(sorted(ids));digest=hashlib.sha256(csv.encode()).hexdigest()
 source=(HERE.parent/'forward.sql').read_text();production=json.loads((HERE.parent/'manifest-contract.json').read_text())['approved_sorted_ids_sha256']
 assert source.count(production)==1
 source=source.replace(production,digest)
 (root/'fixture-forward.sql').write_text(source)
 sql(source)
 arr="array["+','.join("'"+i+"'::uuid" for i in ids)+"]"
 seed="insert into public.payments(id,amount,buyer_fee,seller_fee,total,mode,status,created_at) values "+','.join("('%s',100,10,10,110,'buy_now','succeeded','2026-01-01')"%i for i in ids)+";"
 seed+="insert into public.payments(id,amount,buyer_fee,seller_fee,total,mode,status,created_at) values('d0508a55-84de-40d8-b696-9e0ea4396bb3',200,20,20,220,'buy_now','succeeded','2026-11-03'),('d44d0d3d-90e0-4e3b-a6bd-2769275ec741',100,10,0,110,'native_primary','succeeded','2026-11-25');"
 seed+="insert into public.transfers values('abd8257e-07ee-4718-99d0-d9c8e6dc5c1e','d0508a55-84de-40d8-b696-9e0ea4396bb3','auto_released',null,null),('10000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000001','buyer_confirmed','2026-01-01','tr_synthetic');"
 seed+="insert into ops.\"case\" values('20000000-0000-4000-8000-000000000001','payment','00000000-0000-0000-0000-000000000001','open');insert into ops.case_event values('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001');"
 seed+="insert into public.webhook_retries values('40000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000001');insert into public.payment_refunds values('50000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000001');insert into public.payment_refund_state_log values('60000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000001');"
 seed+="insert into ops.alert(alert_key,state,payload) values('case:refund_pending:fixture','firing','{\"case_id\":\"20000000-0000-4000-8000-000000000001\"}'),('case:release_stuck:protected','firing','{\"case_id\":\"ef6c0d26-1b0b-4641-a7e8-1ba040234fa2\"}');"
 sql(seed)
 sql((HERE/'native-fixture.sql').read_text())
 repo=HERE.parents[3]
 baseline=(repo/'supabase/migrations/117_ops_console_automation.sql').read_text()
 a=baseline.index('create or replace function ops.detect_paid_unsettled()');b=baseline.index('revoke all on function ops.detect_paid_unsettled()',a)
 sql(baseline[a:b])
 native="d44d0d3d-90e0-4e3b-a6bd-2769275ec741"
 def native_alert():
  sql('truncate ops.fixture_alerts;select ops.detect_paid_unsettled();')
  return sql("select count(*) from ops.fixture_alerts where payment='"+native+"';").splitlines()[-1]
 assert native_alert()=='1';print('PASS native detector RED: predecessor falsely flags valid issuance')
 sql((HERE.parent/'native-settlement-forward.sql').read_text())
 assert native_alert()=='0';print('PASS native detector GREEN: complete issuance is not a resale gap')
 for label,change,reset in [
 ('unlinked',"delete from kernel.payment_native where payment_id='"+native+"';", "insert into kernel.payment_native(payment_id,order_id,amount_minor) values('"+native+"','70000000-0000-4000-8000-000000000001',100);"),
 ('wrong-amount',"update kernel.payment_native set amount_minor=99;","update kernel.payment_native set amount_minor=100;"),
 ('wrong-buyer',"update venue.\"order\" set buyer_id=gen_random_uuid();","update venue.\"order\" set buyer_id='2b117757-f4e3-41c1-b7df-68a4502d0fba';"),
 ('not-paid',"update venue.\"order\" set status='pending';","update venue.\"order\" set status='paid';")]:
  sql(change);assert native_alert()=='1';sql(reset);print('PASS native detector refusal',label)
 assert sql("select count(*) from ops.fixture_alerts where payment='00000000-0000-0000-0000-000000000001';").splitlines()[-1]=='1'
 print('PASS real resale gap still detected')
 auth="set request.jwt.claim.sub='2b117757-f4e3-41c1-b7df-68a4502d0fba';set fixture.operator_role='platform_admin';set fixture.aal='aal2';"
 def fails(name,q,expected):
  try:sql(q)
  except subprocess.CalledProcessError as e:
   if expected not in e.stderr:raise AssertionError(name+': '+e.stderr)
   print('PASS',name);return
  raise AssertionError(name+' unexpectedly passed')
 def c(q):return sql(q).splitlines()[-1]
 fails('wrong-manifest','select ops.prelaunch_archive_prepare(array[gen_random_uuid()]);','exact approved manifest')
 fails('native-custody',"begin;insert into kernel.payment_native values('00000000-0000-0000-0000-000000000001');select ops.prelaunch_archive_prepare("+arr+");commit;",'native money or custody')
 fails('alert-in-flight',"begin;update ops.alert set notify_request_id=42 where alert_key='case:refund_pending:fixture';select ops.prelaunch_archive_prepare("+arr+");commit;",'alert delivery still in flight')
 fails('payout-attempt',"begin;insert into public.payout_attempts values(gen_random_uuid(),'00000000-0000-0000-0000-000000000001',null);select ops.prelaunch_archive_prepare("+arr+");commit;",'provider payout attempt')
 fails('actionable-obligation',"begin;update public.transfers set payout_released_at=null where id='10000000-0000-4000-8000-000000000001';select ops.prelaunch_archive_prepare("+arr+");commit;",'actionable seller obligation')
 sql((repo/'supabase/rollbacks/216_prelaunch_test_archive_rollback.sql').read_text())
 sql((repo/'supabase/rollbacks/216_prelaunch_test_archive_rollback.sql').read_text())
 sql((HERE.parent/'native-settlement-forward.sql').read_text());sql(source)
 print('PASS empty schema rollback and repeat restore the exact predecessor')
 batch=c('select ops.prelaunch_archive_prepare('+arr+');');sha=c('select snapshot_sha256 from ops.prelaunch_archive_batch;')
 invoke=f"select ops.prelaunch_archive_execute('{batch}','{sha}','Owner approved pre-launch synthetic contract cleanup','ARCHIVE 57 TEST ORDERS');"
 fails('missing-backup',auth+invoke,'unverified backup')
 sql('update ops.prelaunch_archive_batch set backup_sha256=snapshot_sha256;')
 sql("create table public.fixture_unreviewed_child(id uuid primary key,payment_id uuid references public.payments(id) on delete cascade);")
 fails('unreviewed-cascade',auth+invoke,'unreviewed dependent foreign key')
 sql('drop table public.fixture_unreviewed_child;')
 fails('wrong-role',auth+"set fixture.operator_role='platform_support';"+invoke,'platform admin and MFA')
 fails('wrong-mfa',auth+"set fixture.aal='aal1';"+invoke,'platform admin and MFA')
 fails('preview-drift',auth+"begin;update public.payments set total=999 where id='00000000-0000-0000-0000-000000000001';"+invoke+'commit;','source changed')
 fails('wrong-confirmation',auth+invoke.replace('ARCHIVE 57 TEST ORDERS','ARCHIVE ALL'),'confirmation and written reason')
 # Force a failure AFTER guarded trigger disabling: no source deletion or trigger change may survive.
 sql("create function public.fixture_fail_delete() returns trigger language plpgsql as $$begin raise exception 'forced_post_backup_failure';end$$;create trigger fixture_fail_delete before delete on public.payments for each row execute function public.fixture_fail_delete();")
 fails('unreviewed-delete-hook',auth+invoke,'unreviewed delete trigger')
 sql('drop trigger fixture_fail_delete on public.payments;')
 sql("create or replace function ops.raise_append_only() returns trigger language plpgsql as $$begin if TG_OP='DELETE' and current_setting('fixture.fail',true)='yes' then raise exception 'forced_post_backup_failure';end if;raise exception 'append_only';end$$;")
 # A forced UPDATE failure occurs after source deletion when the receipt is written.
 sql("create trigger fixture_fail_delete before update on ops.prelaunch_archive_batch for each row execute function public.fixture_fail_delete();")
 fails('atomic-failure-rollback',auth+invoke,'forced_post_backup_failure')
 assert c('select count(*) from public.payments;')=='59'
 assert c("select count(*) from pg_trigger where tgname in('tg_case_event_append_only','trg_payment_refunds_append_only','trg_payment_refund_state_log_append_only') and tgenabled='O';")=='3'
 sql('drop trigger fixture_fail_delete on ops.prelaunch_archive_batch;')
 receipt=json.loads(c(auth+invoke));assert receipt['status']=='archived'
 assert c('select count(*) from public.payments;')=='2'
 assert c('select count(*) from public.transfers;')=='1'
 assert c('select count(*) from ops."case";')=='0'
 assert c('select count(*) from public.webhook_retries;')=='0'
 assert c("select count(*) from ops.alert where alert_key='case:refund_pending:fixture';")=='0'
 assert c("select count(*) from ops.alert where alert_key='case:release_stuck:protected' and state='firing';")=='1'
 print('PASS test refund/dispute alert cleanup with unrelated real alert unchanged')
 assert c("select jsonb_array_length(snapshot->'public.payments') from ops.prelaunch_archive_batch;")=='57'
 assert json.loads(c(auth+invoke))==receipt
 assert c('select count(*) from ops.audit;')=='1'
 print('PASS exact move, preserved two sales/real obligation, private full snapshots, idempotent replay, one audit')
 fails('rollback-retains-archive',(repo/'supabase/rollbacks/216_prelaunch_test_archive_rollback.sql').read_text(),'retain archive data')
 fails('guards-restored',"delete from public.payment_refunds where false;insert into public.payment_refunds values(gen_random_uuid(),'d0508a55-84de-40d8-b696-9e0ea4396bb3');delete from public.payment_refunds;",'append_only')
 fails('direct-table-denied',"set role authenticated;select snapshot from ops.prelaunch_archive_batch;",'permission denied')
 print('PASS SQL contract fixture; full Supabase chain and production UNRUN')
 (root/'PASS.json').write_text(json.dumps({'result':'PASS CONTRACT ONLY','receipt':receipt,'production':'UNRUN'}))
finally:
 if started:
  run(['pg_ctl','-D',str(data),'-m','fast','-w','stop'],stdout=(root/'stop.out').open('w'),stderr=subprocess.STDOUT)
 print('Evidence retained:',root)
