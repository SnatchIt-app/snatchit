#!/usr/bin/env python3
"""Offline release invariants only. Actual31-case SQL behavior is tested by pgTAP283 in CI."""
from pathlib import Path
import re,hashlib,copy,json
ROOT=Path(__file__).resolve().parents[1]
name='20261124170453_expiry_cron_response_timeout'
f=(ROOT/'supabase/migrations'/f'{name}.sql').read_text()
r=(ROOT/'supabase/rollbacks'/f'{name}_rollback.sql').read_text()
t=(ROOT/'supabase/tests/283_expiry_cron_response_timeout.sql').read_text()
def block(s):return s.split('DO $expiry215$\n',1)[1].rsplit('$expiry215$;',1)[0]
assert t.split('$apply215$\n',1)[1].split('$apply215$;',1)[0]==block(f)
assert t.split('$rollback215$\n',1)[1].split('$rollback215$;',1)[0]==block(r)
old=re.search(r"select cron.schedule\(\n  'enforce-transfer-expiry',[\s\S]*?\$cron\$([\s\S]*?)\$cron\$",(ROOT/'supabase/migrations/133_functions_base_url_from_config.sql').read_text()).group(1)
def digest(s):return hashlib.md5(s.encode()).hexdigest()
def operands(s):return re.search(r'v_command:=replace\(v_job.command,\$before215\$([\s\S]*?)\$before215\$,\$after215\$([\s\S]*?)\$after215\$\);',s).groups()
before,after=operands(f);reverse_before,reverse_after=operands(r)
assert (before,after)==(reverse_after,reverse_before)
assert old.count(before)==1 and 'timeout_milliseconds' not in old
new=old.replace(before,after)
assert digest(old)=='d8fd165ade2345bafb4e26a44f2bbdc8'
assert digest(new)=='95e15a08418aeedb7876cb0a95f6560c'
assert new.replace(after,before)==old
assert new.count('timeout_milliseconds := 20000')==1
assert new.replace('jsonb,\n    timeout_milliseconds := 20000','jsonb')==old
assert new.count('net.http_post(')==old.count('net.http_post(')==1
for source in [f,r]:
 assert 'cron.schedule(' not in source and 'cron.unschedule(' not in source and 'UPDATE cron.job' not in source
 assert source.count('PERFORM cron.alter_job(job_id:=v_job.jobid,command:=v_command);')==1
 assert "WHERE jobname='enforce-transfer-expiry' FOR UPDATE" in source
 assert 'v_count<>1' in source and 'IS DISTINCT FROM' in source
 assert 'catalog.platform_config' not in source and 'ops.setting' not in source
 assert 'execute net.http_post' not in source.lower()
 assert 'RETURN; -- Exact target already installed' in source
 assert 'active IS NOT DISTINCT FROM v_job.active' in source
 assert 'database IS NOT DISTINCT FROM v_job.database' in source
 assert 'username IS NOT DISTINCT FROM v_job.username' in source
 # No credential values, URL change or literal new request body.
 assert not re.search(r'(?:sk_live_|sb_secret_|eyJhbGci)',source)
 # Both hashes occur as source/target gates, not only comments.
 assert "IF md5(v_job.command)='" in source
 assert 'IF md5(v_job.command) IS DISTINCT FROM' in source
assert "SELECT plan(31)" in t
assert len(re.findall(r'^SELECT (?:is|matches|has_function|lives_ok|throws_ok)\(',t,re.M))==31
assert t.rstrip().endswith('ROLLBACK;')
# Non-vacuous old→fixed control: the exact old/default5s command cannot satisfy
# the expected target fingerprint. A20000ms patch plus URL/body drift also fails.
for label,mutant in [('old-no-op',old),('wrong-timeout',new.replace('20000','1000')),('url-drift',new.replace('/enforce-transfer-expiry','/refund-execute')),('body-drift',new.replace("body    := '{}'", "body    := '{\"sweep\":true}'"))]:
 assert digest(mutant)!=digest(new),label
 print('PASS negative control:',label)
print('PASS exact live133 baseline, forward/rollback inversion, only timeout delta, no reschedule/switch/credential change, embedded SQL identity,31-case TAP plan')
print('UNRUN: actual pgTAP/cron.alter_job behavior awaits isolated CI; no database connection made')
