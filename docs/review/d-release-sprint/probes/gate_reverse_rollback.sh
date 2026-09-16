#!/bin/bash
# D: production-gate stack — the three release migrations roll back in REVERSE order (133 → 132 → 131)
# to the candidate catalog. Local loopback only; drops its own databases.
set -u; export PGHOST=127.0.0.1 PGUSER=postgres LC_ALL=C
TREE=${1:?tree}; DB=${2:-d_gate_rb_rehears}; OUT=${3:-/tmp/d_gate_rb}
ID=$(cd "$(dirname "$0")/../../../.." && pwd)/scripts/review/catalog_identity.sql
[ -f "$ID" ] || ID=/Users/josetascon/snatchit-d-review/scripts/review/catalog_identity.sql
mkdir -p "$OUT"
dropdb --if-exists $DB 2>/dev/null; createdb $DB || exit 1
psql -X -q -d $DB -v ON_ERROR_STOP=1 -f "$TREE/scripts/local/replay_shim.sql" >/dev/null 2>&1
[ -f "$TREE/scripts/local/replay_shim_supplements.sql" ] && psql -X -q -d $DB -v ON_ERROR_STOP=1 -f "$TREE/scripts/local/replay_shim_supplements.sql" >/dev/null 2>&1
ap(){ b=$(basename "$1"); if [ "$b" = "014_frequent_cron_schedules.sql" ]; then grep -v '^create extension if not exists pg_' "$1" | psql -X -q -d $DB -v ON_ERROR_STOP=1 -f - >/dev/null 2>>$OUT/apply.err; else psql -X -q -d $DB -v ON_ERROR_STOP=1 -f "$1" >/dev/null 2>>$OUT/apply.err; fi; }
ident(){ psql -X -qtA -d $DB -v ON_ERROR_STOP=1 -f "$ID" > "$1" 2>"$1.err"; [ -s "$1" ] || { echo "IDENT EMPTY $1"; exit 1; }; }
: > $OUT/apply.err; n=0
for f in $(ls "$TREE"/supabase/migrations/*.sql | LC_ALL=C sort); do
  case "$(basename $f)" in 131_*|132_*|133_*) continue;; esac
  ap "$f" || { echo "APPLY FAIL $(basename $f)"; exit 1; }; n=$((n+1))
done
echo "candidate chain applied: $n files"
ident $OUT/id_candidate.txt
for v in 131 132 133; do f=$(ls "$TREE"/supabase/migrations/${v}_*.sql); ap "$f" && echo "applied $v" || { echo "APPLY FAIL $v"; exit 1; }; done
ident $OUT/id_stack.txt
echo "stack adds $(diff $OUT/id_candidate.txt $OUT/id_stack.txt | grep -c '^>') identity lines"
psql -X -Atd $DB -c "select 'census after stack: '||(select count(*) from pg_tables where schemaname='public')||'|'||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')||'|'||(select count(*) from pg_policies where schemaname='public')||'|'||(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)"
for v in 133 132 131; do f=$(ls "$TREE"/supabase/rollbacks/${v}_*_rollback.sql); psql -X -q -d $DB -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>>$OUT/rb.err && echo "rolled back $v" || { echo "ROLLBACK FAIL $v"; tail -3 $OUT/rb.err; exit 1; }; done
ident $OUT/id_after.txt
d=$(diff $OUT/id_candidate.txt $OUT/id_after.txt | grep -c '^[<>]')
echo "identity lines differing from the candidate after the reverse rollback: $d"
[ "$d" = "0" ] && echo "PASS reverse rollback restores the candidate catalog exactly" || { echo "DIFF:"; diff $OUT/id_candidate.txt $OUT/id_after.txt | head -20; }
psql -X -Atd $DB -c "select 'census after rollback: '||(select count(*) from pg_tables where schemaname='public')||'|'||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')||'|'||(select count(*) from pg_policies where schemaname='public')||'|'||(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)"
dropdb $DB
