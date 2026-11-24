#!/usr/bin/env python3
"""Fresh CI stack only: prove the cron API cannot lose a concurrent update.

The READ COMMITTED control must lose the update. The same two-connection
interleaving under SERIALIZABLE must fail with40001 and preserve the writer.
No request is executed; the existing CI job is disabled during the test and
its exact command/activation are restored in finally. Never targets hosted DBs.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_URL = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
OLD = 'd8fd165ade2345bafb4e26a44f2bbdc8'
NEW = '95e15a08418aeedb7876cb0a95f6560c'
COMMENT = '\n-- isolated215-concurrent-writer'
source = (ROOT / 'supabase/migrations/133_functions_base_url_from_config.sql').read_text()
old = re.search(r"select cron.schedule\(\n  'enforce-transfer-expiry',[\s\S]*?\$cron\$([\s\S]*?)\$cron\$", source).group(1)
command = old.replace("    body    := '{}'::jsonb\n  )", "    body    := '{}'::jsonb,\n    timeout_milliseconds := 20000\n  )")
digest = lambda value: hashlib.md5(value.encode()).hexdigest()
assert digest(old) == OLD and digest(command) == NEW

def literal(value):
    # These are repository-owned SQL commands containing vault references,
    # never resolved secrets. Pass SQL on stdin, never process arguments.
    return "'" + value.replace("'", "''") + "'"

def main():
    if sys.argv[1:] == ['--verify-inputs']:
        print('PASS: exact215 command pins and isolated localhost target; no database connection')
        return
    assert not sys.argv[1:]
    assert os.environ.get('CI') == 'true', 'This mutating fixture is for isolated CI only'
    assert os.environ.get('DB_URL') == EXPECTED_URL, 'Refusing non-CI database target'
    assert not any(key.startswith('PG') for key in os.environ), 'Inherited PostgreSQL overrides refused'
    env = {key: os.environ[key] for key in ['PATH', 'HOME'] if key in os.environ}
    env['LC_ALL'] = 'C'
    args = ['psql', '--dbname', EXPECTED_URL, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']

    def sql(query):
        result = subprocess.run(args, input=query, text=True, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        assert result.returncode == 0, 'Isolated cron fixture SQL failed (no command/credentials printed)'
        return result.stdout.strip()

    def state():
        return json.loads(sql("SELECT to_jsonb(j)::text FROM cron.job j WHERE jobname='enforce-transfer-expiry';"))

    baseline = state()
    assert digest(baseline['command']) == NEW, '215 must already be installed'
    job = int(baseline['jobid'])
    assert baseline['database'] == 'postgres' and baseline['username'] == 'postgres'
    assert baseline['schedule'] == '*/2 * * * *'
    active = 'true' if baseline['active'] else 'false'

    def set_command(value):
        sql(f'SELECT cron.alter_job(job_id:={job},command:={literal(value)});')

    try:
        sql(f'SELECT cron.alter_job(job_id:={job},active:=false);')
        for isolation in ['READ COMMITTED', 'SERIALIZABLE']:
            set_command(command)
            process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True, bufsize=1)
            try:
                process.stdin.write(f'BEGIN ISOLATION LEVEL {isolation};\nCREATE TEMP TABLE snapshot215 ON COMMIT DROP AS SELECT jobid,command FROM cron.job WHERE jobid={job};\n\\echo SNAPSHOT_READY\n')
                process.stdin.flush()
                selector = selectors.DefaultSelector()
                selector.register(process.stdout, selectors.EVENT_READ)
                deadline = time.monotonic() + 15
                observed = False
                while time.monotonic() < deadline:
                    if selector.select(max(0, deadline-time.monotonic())):
                        line = process.stdout.readline()
                        if line.strip() == 'SNAPSHOT_READY':
                            observed = True
                            break
                        if not line:
                            break
                selector.close()
                assert observed, 'Snapshot barrier not reached; interleaving was not exercised'
                set_command(command + COMMENT)
                process.stdin.write('SELECT cron.alter_job(job_id:=jobid,command:=command) FROM snapshot215;\nCOMMIT;\n')
                process.stdin.close()
                process.stdin = None
                _, stderr = process.communicate(timeout=20)
                after = state()
                if isolation == 'READ COMMITTED':
                    assert process.returncode == 0 and after['command'] == command, 'Lost-update negative control did not reproduce'
                    print('PASS negative control: READ COMMITTED overwrites concurrent command')
                else:
                    assert process.returncode != 0 and '40001' in stderr, 'Expected serialization refusal did not occur'
                    assert after['command'] == command + COMMENT, 'Concurrent writer was overwritten'
                    print('PASS: SERIALIZABLE refuses40001 and preserves concurrent command')
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
    finally:
        set_command(command)
        sql(f'SELECT cron.alter_job(job_id:={job},active:={active});')
        assert state() == baseline, 'CI job not restored exactly; no success receipt'
    print('PASS: existing job restored byte-for-byte; no HTTP request, schedule or money switch changed')

if __name__ == '__main__':
    main()
