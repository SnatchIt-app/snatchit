#!/usr/bin/env python3
"""LOCAL ONLY: supported API transactions prove cross-rail payment fencing.
Pass a disposable a212_* database containing212(+214 for green). No network.
Negative controls: run on212; native->payout and native->console must fail.
"""
import os,subprocess,sys,time
DB=sys.argv[1]
if not DB.startswith('a212_') or os.environ.get('PGHOST','/tmp') not in ['/tmp','localhost','127.0.0.1'] or any(os.environ.get(k) for k in ['PGHOSTADDR','PGSERVICE']):raise SystemExit('Local disposable a212_* databases only')
cmd=['psql','-X','-U','postgres','-d',DB,'-Atq','-v','ON_ERROR_STOP=1']
def query(sql):return subprocess.check_output(cmd+['-c',sql],text=True).strip()
login="SELECT tap.login(tap.admin_user()); SELECT set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb || '{\"aal\":\"aal2\"}')::text,true);"
logout="SELECT tap.logout();"
seed="SELECT tap.seed_core(); UPDATE ops.setting SET value='true'::jsonb WHERE key='refund_execute_enabled'; INSERT INTO public.admin_users(user_id,label) VALUES(tap.other_user(),'214 other founder') ON CONFLICT DO NOTHING; UPDATE public.payments SET stripe_livemode=true WHERE id=tap.payment_b(); UPDATE public.profiles SET stripe_connect_id='acct_local214' WHERE id=tap.seller();"
prepare="BEGIN;"+login+"SELECT ops.execute_action('concurrency214-console','refund_execute','payment',tap.payment_a(),'{}','reviewed fixture');"+login.replace('tap.admin_user()','tap.other_user()')+"SELECT ops.approve_action((SELECT id FROM ops.action WHERE idempotency_key='concurrency214-console'),'approve','reviewed fixture');COMMIT;"
# Each case uses a fresh template, so intent/action states come from real APIs.
cases=[
 ('native_to_payout','b','payout','NATIVE_REFUND_IN_FLIGHT'),
 ('native_to_console','a','console','native_refund_in_flight'),
 ('payout_to_native','b','native','payout_exposure'),
 ('console_to_native','a','native','console_refund_exposure'),
]
failed=[]
for label,which,kind,expected in cases:
    caseDB=DB+'_'+label+'_'+str(os.getpid())
    subprocess.run(['createdb','-U','postgres','-T',DB,caseDB],check=True)
    oldcmd=cmd;cmd=['psql','-X','-U','postgres','-d',caseDB,'-Atq','-v','ON_ERROR_STOP=1']
    query(seed)
    action=None
    if which=='a':
        query('BEGIN;'+login+"SELECT ops.execute_action('concurrency214-console','refund_execute','payment',tap.payment_a(),'{}','reviewed fixture');COMMIT;")
        action=query("SELECT id FROM ops.action WHERE idempotency_key='concurrency214-console'")
        query('BEGIN;'+login.replace('tap.admin_user()','tap.other_user()')+"SELECT ops.approve_action('%s','approve','reviewed fixture');COMMIT;"%action)
    payment=f'tap.payment_{which}()'
    native=login+f"SELECT set_config('local214.refund_id',(kernel.admin_refund({payment},ARRAY[]::uuid[],100,'admin_action','concurrency214-native')->>'refund_id'),true);"+logout
    if label.startswith('native_'):holder_sql=native
    elif label.startswith('payout_'):holder_sql="SELECT public.apply_auto_release(tap.transfer_b());SELECT * FROM public.claim_payout_attempt(tap.transfer_b(),'local214');"
    else:holder_sql="SELECT tap.login_service();SELECT ops.executor_claim('%s');"%action
    env=dict(os.environ,PGAPPNAME='holder214_'+label)
    holder=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
    holder.stdin.write('BEGIN;'+holder_sql+"SELECT 'ready214';\n");holder.stdin.flush()
    while holder.stdout.readline().strip()!='ready214':
        if holder.poll() is not None:raise RuntimeError(holder.stderr.read())
    if kind=='payout':worker_sql="SELECT public.apply_auto_release(tap.transfer_b());SELECT * FROM public.claim_payout_attempt(tap.transfer_b(),'local214');"
    elif kind=='console':worker_sql="SELECT tap.login_service();SELECT ops.executor_claim('%s');"%action
    else:worker_sql=native+"SELECT tap.login_service();SELECT kernel.authorize_fresh_refund(current_setting('local214.refund_id')::uuid);"
    env=dict(os.environ,PGAPPNAME='worker214_'+label)
    worker=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
    worker.stdin.write("BEGIN;SET LOCAL statement_timeout='5s';"+worker_sql+'COMMIT;\n\\q\n');worker.stdin.flush()
    blocked=False
    for _ in range(25):
        if query("SELECT coalesce(bool_or(wait_event_type='Lock'),false) FROM pg_stat_activity WHERE application_name='worker214_%s'"%label)=='t':blocked=True;break
        if worker.poll() is not None:break
        time.sleep(.05)
    # A disjoint payment must remain usable while this payment's anchor waits.
    other='a' if which=='b' else 'b'
    disjoint=query("BEGIN;SET LOCAL statement_timeout='500ms';SELECT id FROM public.payments WHERE id=tap.payment_%s() FOR UPDATE;ROLLBACK;"%other)
    holder.stdin.write('COMMIT;\n\\q\n');holder.stdin.flush();holder.communicate(timeout=5)
    out,err=worker.communicate(timeout=6)
    ok=blocked and expected in out+err and bool(disjoint)
    print(label+': '+('PASS payment wait, committed conflict observed, disjoint payment free' if ok else 'FAIL')+'; expected='+expected,flush=True)
    if not ok:print(out,err);failed.append(label)
    cmd=oldcmd
print('214 concurrency failures:',','.join(failed) or 'none')
sys.exit(bool(failed))
