#!/bin/bash
set -u; export PGHOST=127.0.0.1 PGUSER=postgres LC_ALL=C
F="$1"; name="$2"; url="${3:-}"
DB=d133_b_$name
dropdb --if-exists $DB >/dev/null 2>&1; createdb -T d133_base_rehears $DB
# a recording pg_net stub + the queue table the real extension has
psql -X -q -d $DB -v ON_ERROR_STOP=1 >/dev/null <<SQL
create table net.calls(id serial primary key, url text, at timestamptz default now());
create or replace function net.http_post(url text, headers jsonb default '{}', body jsonb default '{}')
  returns bigint language sql as \$\$ insert into net.calls(url) values (url) returning id::bigint \$\$;
create table net.http_request_queue(id bigserial primary key, url text);
insert into net.http_request_queue(url) values
  ('https://hqycwntpfoztoinemqns.supabase.co/functions/v1/enforce-transfer-expiry'),
  ('https://ofaidukbieeekqaboscm.supabase.co/functions/v1/notify-transfer');
insert into vault.decrypted_secrets(name, decrypted_secret) values ('service_role_key','k');
SQL
[ -n "$url" ] && psql -X -q -d $DB -c "insert into vault.decrypted_secrets(name, decrypted_secret) values ('project_url','$url')" >/dev/null
psql -X -q -d $DB -v ON_ERROR_STOP=1 -f "$F" >/dev/null 2>&1 || { echo "$name: APPLY REFUSED"; dropdb $DB; exit 0; }
# run each http cron's command exactly as pg_cron would
psql -X -q -d $DB -c "delete from net.calls" >/dev/null
for job in enforce-transfer-expiry crm-export-build-tick crm-export-purge-tick refund-execute-tick payout-execute-tick; do
  cmd=$(psql -X -Atd $DB -c "select command from cron.job where jobname='$job'")
  [ -n "$cmd" ] && psql -X -q -d $DB -c "$cmd" >/dev/null 2>&1
done
calls=$(psql -X -Atd $DB -c "select coalesce(string_agg(distinct split_part(url,'/functions/',1)||' x'||1,','),'<none>')||' ('||count(*)||' calls)' from net.calls")
queue=$(psql -X -Atd $DB -c "select coalesce(string_agg(split_part(url,'/functions/',1), ','),'<empty>') from net.http_request_queue")
echo "$name (project_url=${url:-<none>}) -> cron posts: $calls | queue after: $queue"
dropdb $DB >/dev/null
