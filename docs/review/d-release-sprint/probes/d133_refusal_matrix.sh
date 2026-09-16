#!/bin/bash
set -u; export PGHOST=127.0.0.1 PGUSER=postgres LC_ALL=C
F="$1"; name="$2"; setup="${3:-}"
DB=d133_$name
dropdb --if-exists $DB >/dev/null 2>&1; createdb -T d133_base_rehears $DB || { echo "$name CREATEDB-FAIL"; exit 1; }
[ -n "$setup" ] && { psql -X -q -d $DB -v ON_ERROR_STOP=1 -c "$setup" >/dev/null || { echo "$name SETUP-FAIL"; exit 1; }; }
out=$(psql -X -q -d $DB -v ON_ERROR_STOP=1 -f "$F" 2>&1)
rc=$?
verdict=$( [ $rc -eq 0 ] && echo APPLIED || echo REFUSED )
msg=$(printf '%s' "$out" | grep -oE '133 REFUSED: [^"]{0,90}' | head -1)
sites=$(psql -X -Atd $DB -c "select (select count(*) from pg_proc where prosrc like '%hqycwntpfoztoinemqns%')||' fn / '||(select count(*) from cron.job where command like '%hqycwntpfoztoinemqns%')||' cron'" 2>&1)
vaulturl=$(psql -X -Atd $DB -c "select coalesce((select decrypted_secret from vault.decrypted_secrets where name='project_url' limit 1),'<none>')")
echo "$name -> $verdict | prod-host sites: $sites | project_url: $vaulturl | ${msg:-}"
dropdb --if-exists $DB >/dev/null 2>&1
