#!/bin/bash
# D: does 20260910120000_venue_api_read_views converge whether it is applied in LC_ALL=C REPLAY position
# (between 20260909000000 and 20260916000000) or LAST, as the sandbox would apply it today?
# Two databases, two orders, one catalog-identity diff. Local loopback only; drops its own databases.
set -u; export PGHOST=127.0.0.1 PGUSER=postgres LC_ALL=C
TREE=${1:?tree}; VENUE=${2:?venue migration file}; OUT=${3:-/tmp/d_venue_order}
ID=/Users/josetascon/snatchit-d-review/scripts/review/catalog_identity.sql
mkdir -p "$OUT"; : > "$OUT/apply.err"
setup(){ dropdb --if-exists "$1" 2>/dev/null; createdb "$1" || exit 1
  psql -X -q -d "$1" -v ON_ERROR_STOP=1 -f "$TREE/scripts/local/replay_shim.sql" >/dev/null 2>&1
  [ -f "$TREE/scripts/local/replay_shim_supplements.sql" ] && psql -X -q -d "$1" -v ON_ERROR_STOP=1 -f "$TREE/scripts/local/replay_shim_supplements.sql" >/dev/null 2>&1; }
ap(){ local b; b=$(basename "$2")
  if [ "$b" = "014_frequent_cron_schedules.sql" ]; then grep -v '^create extension if not exists pg_' "$2" | psql -X -q -d "$1" -v ON_ERROR_STOP=1 -f - >/dev/null 2>>"$OUT/apply.err"
  else psql -X -q -d "$1" -v ON_ERROR_STOP=1 -f "$2" >/dev/null 2>>"$OUT/apply.err"; fi || { echo "APPLY FAIL $b on $1"; tail -3 "$OUT/apply.err"; exit 1; }; }

# the tree's files in canonical order, with the venue file spliced into its sorted position
FILES=$(ls "$TREE"/supabase/migrations/*.sql | LC_ALL=C sort)
A=d_venue_replay; B=d_venue_last
echo "== A: full LC_ALL=C replay WITH the venue migration in its sorted position =="
setup $A; n=0
for f in $FILES; do
  b=$(basename "$f")
  # 20260910120000 sorts after 20260909000000 and before 20260916000000
  if [ -z "${SPLICED:-}" ] && [[ "$b" > "20260910120000" ]]; then echo "   splicing venue immediately BEFORE $b"; ap $A "$VENUE"; SPLICED=1; fi
  ap $A "$f"; n=$((n+1))
done
[ -z "${SPLICED:-}" ] && { ap $A "$VENUE"; echo "   venue appended (no later file)"; }
echo "   applied $n tree files + venue"
echo "== B: same tree, venue applied LAST (the sandbox's order today) =="
setup $B; for f in $FILES; do ap $B "$f"; done; ap $B "$VENUE"
echo "   applied $n tree files, then venue"
psql -X -qtA -d $A -v ON_ERROR_STOP=1 -f "$ID" > "$OUT/a.txt"; psql -X -qtA -d $B -v ON_ERROR_STOP=1 -f "$ID" > "$OUT/b.txt"
[ -s "$OUT/a.txt" ] && [ -s "$OUT/b.txt" ] || { echo "IDENT EMPTY"; exit 1; }
d=$(diff "$OUT/a.txt" "$OUT/b.txt" | grep -c '^[<>]')
echo "catalog identity lines differing between the two orders: $d"
[ "$d" = "0" ] && echo "PASS the two orders converge" || { echo "FAIL they do not converge"; diff "$OUT/a.txt" "$OUT/b.txt" | head -20; }
for db in $A $B; do echo "  $db venue_api views: $(psql -X -qtA -d $db -c "select count(*) from pg_views where schemaname='venue_api'")  census: $(psql -X -qtA -d $db -c "select (select count(*) from pg_tables where schemaname='public')||'|'||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')||'|'||(select count(*) from pg_policies where schemaname='public')||'|'||(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)")"; done
dropdb --if-exists $A; dropdb --if-exists $B
