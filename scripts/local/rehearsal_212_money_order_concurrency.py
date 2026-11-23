#!/usr/bin/env python3
"""Local PostgreSQL only. Uses a fresh disposable replay DB supplied by the caller.
Proves six real entrypoints wait for the shared key before row locks. --negative
requires the caller to install predecessor/no-lock definitions, and must fail.
No hosted URL, credential or external provider is accepted.
"""
import os, subprocess, sys, time
DB = sys.argv[1]
if not DB.startswith('a212_') or any(os.environ.get(k) for k in ['PGHOSTADDR','PGSERVICE']):
    raise SystemExit('Only a212_* local rehearsal databases are accepted')
if os.environ.get('PGHOST', '/tmp') not in ['/tmp', 'localhost', '127.0.0.1']:
    raise SystemExit('Local PostgreSQL only')
cmd=['psql','-X','-U','postgres','-d',DB,'-Atq','-v','ON_ERROR_STOP=1']
def query(sql):
    return subprocess.check_output(cmd+['-c',sql],text=True).strip()
def open_sql(sql,app):
    env=dict(os.environ,PGAPPNAME=app)
    p=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
    p.stdin.write(sql+'\n');p.stdin.flush();return p
query("SELECT tap.seed_core(); UPDATE ops.setting SET value='true'::jsonb WHERE key='refund_execute_enabled'; INSERT INTO public.admin_users(user_id,label) VALUES(tap.other_user(),'212 founder B') ON CONFLICT DO NOTHING;")
login="SELECT tap.login(tap.admin_user()); SELECT set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb || '{\"aal\":\"aal2\"}')::text,true);"
second=login.replace('tap.admin_user()', 'tap.other_user()')
# Seed a reachable pending approval through the actual console RPC.
query('BEGIN;'+login+" SELECT ops.execute_action('concurrency212-first','refund_execute','payment',tap.payment_b(),'{}','reviewed local fixture'); COMMIT;")
action=query("SELECT id FROM ops.action WHERE idempotency_key='concurrency212-first'")
payment=query('SELECT tap.payment_b()')
key="pg_catalog.hashtextextended('ops_money_order:' || '%s',0)"%payment
cases={
 'execute':login+" SELECT ops.execute_action('concurrency212-first','refund_execute','payment',tap.payment_b(),'{}','reviewed local fixture');",
 'approve':second+" SELECT ops.approve_action('%s','approve','reviewed local fixture');"%action,
 'run':"SELECT ops.action_run('%s');"%action,
 'dispatch':"SELECT ops.action_dispatch(a) FROM ops.action a WHERE id='%s';"%action,
 'executor':"SELECT tap.login_service(); SELECT ops.executor_claim('%s');"%action,
 'payout':"SELECT * FROM public.claim_payout_attempt(tap.transfer_b(),'local212');",
}
failed=[]
for label,call in cases.items():
    holder=open_sql("BEGIN; SELECT pg_advisory_xact_lock(%s); SELECT 'ready212';"%key,'holder212')
    while holder.stdout.readline().strip()!='ready212':
        if holder.poll() is not None: raise RuntimeError(holder.stderr.read())
    worker=open_sql('BEGIN; SET LOCAL statement_timeout=\'4s\'; '+call+' ROLLBACK;','worker212_'+label)
    blocked=False
    for _ in range(30):
        if query("SELECT coalesce(bool_or(wait_event='advisory'),false) FROM pg_stat_activity WHERE application_name='worker212_%s'"%label)=='t':
            blocked=True;break
        if worker.poll() is not None:break
        time.sleep(.05)
    # If the worker grabbed the action row first, this NOWAIT lock fails, proving
    # a row->advisory inversion despite the worker waiting on the right key.
    row_available=True
    try: query("BEGIN; SELECT id FROM ops.action WHERE id='%s' FOR UPDATE NOWAIT; SELECT id FROM public.transfers WHERE id=tap.transfer_b() FOR UPDATE NOWAIT; SELECT id FROM public.payments WHERE id=tap.payment_b() FOR UPDATE NOWAIT; ROLLBACK;"%action)
    except subprocess.CalledProcessError:row_available=False
    holder.stdin.write('ROLLBACK;\n\\q\n');holder.stdin.flush();holder.wait(timeout=5)
    if worker.poll() is None:
        worker.stdin.write('\\q\n');worker.stdin.flush()
    out,err=worker.communicate(timeout=6)
    ok=blocked and row_available and 'deadlock detected' not in err
    print(('%s: '%label)+('PASS shared key before action/transfer/payment rows' if ok else 'FAIL missing shared key or inverted lock order'),flush=True)
    if not ok:failed.append(label)
print('212 concurrency failures:',','.join(failed) or 'none')
sys.exit(bool(failed))
