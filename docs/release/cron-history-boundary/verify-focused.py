#!/usr/bin/env python3
"""Focused verifier. Requires an ALREADY running, owned, private proof database.
No boot/install/hosted access. Pass its socket directory, port and evidence dir.
"""
import hashlib, json, pathlib, re, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[3]
socket,port,out=sys.argv[1:]
assert socket.startswith('/tmp/cron213-') and pathlib.Path(socket).is_dir()
out=pathlib.Path(out);out.mkdir(exist_ok=True)
base=['psql','-X','-h',socket,'-p',port,'-d','cron213_proof','-v','ON_ERROR_STOP=1','-At']
checks=[]
def run(label, *, file=None, sql=None, success=True):
    r=subprocess.run(base+(['-f',str(root/file)] if file else ['-c',sql]),text=True,capture_output=True)
    (out/(label+'.log')).write_text(r.stdout+r.stderr)
    assert (r.returncode==0)==success,(label,r.returncode,r.stdout,r.stderr)
    return r.stdout
forward='supabase/migrations/20261118001000_ops_cron_history_margin.sql'
rollback='supabase/rollbacks/213_ops_cron_history_margin_rollback.sql'
test='supabase/tests/281_ops_cron_history_margin.sql'
a='a315f6713602062ea0aa6958b3dd3fac';b='be7ba9e3c04c26b9c99728900625a333'
def hashcheck(expected):
    actual=run('body-'+expected,sql="select md5(prosrc) from pg_proc where oid='ops.detect_jobs()'::regprocedure").strip()
    assert actual==expected,(actual,expected)
def tap(label,failed):
    s=run(label,file=test)
    assert re.search(r'^1\.\.32$',s,re.M)
    errors=re.findall(r'^not ok (\d+)',s,re.M)
    assert len(errors)==failed,(label,errors)
    assert len(re.findall(r'^(?:not )?ok \d+',s,re.M))==32
    checks.append({'test':label,'assertions':32,'expected_failures':failed,'failed_numbers':errors})
def metadata():
    return run('metadata',sql="select json_build_object('owner',proowner,'acl',proacl,'definer',prosecdef,'config',proconfig,'volatility',provolatile,'oid',oid) from pg_proc where oid='ops.detect_jobs()'::regprocedure").strip()
run('connection-identity',sql="select version(); show data_directory; show listen_addresses; show unix_socket_directories; show unix_socket_permissions; select extversion from pg_extension where extname='pgtap'")
assert run('owned-data-dir',sql='show data_directory').strip() == '/Volumes/DEV-SSD/01_SNATCH_IT/private-evidence/cron213-20261118/pgdata'
assert run('no-tcp',sql='show listen_addresses').strip() == ''
assert run('owned-socket',sql='show unix_socket_directories').strip() == socket
assert run('private-socket',sql='show unix_socket_permissions').strip() == '0700'
run('rollback-preflight',file=rollback);hashcheck(a)
m=metadata()
tap('baseline-final',6)
run('forward-final',file=forward);hashcheck(b);assert metadata()==m
run('forward-rerun',file=forward);hashcheck(b)
tap('candidate-final',0)
# Candidate must also reject accidental broadening of the strict seven-day metrics.
source=(root/forward).read_text()
# Extract just the complete statement rather than the transaction guards.
statement=re.search(r'create or replace function ops.detect_jobs\(\).*?\n\$ops\$;',source,re.S).group()
mutant=statement.replace("count(*) filter (where d.start_time > now() - interval '7 days') over wj as n",'count(*) over wj as n')
assert mutant!=statement
run('mutant-count-install',sql=mutant)
s=run('mutant-count',file=test)
assert re.search(r'^not ok ',s,re.M),'test failed to detect widened count'
checks.append({'test':'mutant-count','expected':'fails','failed_numbers':re.findall(r'^not ok (\d+)',s,re.M)})
# Unknown but syntactically valid third body: both directions must refuse and leave it intact.
unknown=hashlib.md5(re.search(r'as \$ops\$(.*?)\$ops\$;',mutant,re.S).group(1).encode()).hexdigest()
hashcheck(unknown)
for name,file in [('unknown-forward',forward),('unknown-rollback',rollback)]:
    refusal=run(name,file=file,success=False)
    assert '213: unrecognized ops.detect_jobs() body:' in (out/(name+'.log')).read_text()
    # stderr carries the refusal; stored verbatim above. Body must stay unchanged.
    hashcheck(unknown)
run('restore-known-candidate',sql=statement)
mutant_success=statement.replace("where d.status = 'succeeded' and d.start_time > now() - interval '7 days'","where d.status = 'succeeded'")
assert mutant_success != statement
run('mutant-success-install',sql=mutant_success)
s=run('mutant-success',file=test)
assert re.search(r'^not ok ',s,re.M),'test failed to detect widened last_success'
checks.append({'test':'mutant-success','expected':'fails','failed_numbers':re.findall(r'^not ok (\d+)',s,re.M)})
run('restore-known-candidate-after-success',sql=statement)
run('rollback-final',file=rollback);hashcheck(a);assert metadata()==m
run('rollback-rerun',file=rollback);hashcheck(a)
tap('rollback-baseline',6)
run('reapply-final',file=forward);hashcheck(b)
tap('reapply-candidate',0)
(out/'summary.json').write_text(json.dumps({'scope':'actual detector SQL; explicit dependency doubles; not full-chain replay','baseline':a,'candidate':b,'checks':checks,'metadata_preserved':True,'unknown_bodies_rejected_both_directions':True},indent=2)+'\n')
print((out/'summary.json').read_text())
