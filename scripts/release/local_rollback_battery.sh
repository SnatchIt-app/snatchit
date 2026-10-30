#!/bin/zsh
# Persisted from the 2026-09-02 release-readiness pass. Local-only; requires the
# scripts/local PG17 harness env (PGHOST/PGPORT/PGUSER) and the catalog-identity
# query at $RG_OUT/c089/catalog_identity.sql (see scripts/local/README notes).
mkdir -p "${RG_OUT:-/tmp/phase2-release}"
# Full Phase-2 rollback battery: for each N in 076..092, build a NUMBERED-prefix
# DB (shim + 000..N, no timestamped files), run rollback N, diff catalog identity
# against the prefix through N-1. All 17 must be diff=0.
set -u
export LC_ALL=C PGHOST=/tmp/pg150s PGPORT=5433 PGUSER=postgres
cd "$(git rev-parse --show-toplevel)"
S=${RG_OUT:-/tmp/phase2-release}
ID=$S/c089/catalog_identity.sql
build_prefix() { # $1=db $2=max numbered version (inclusive)
  dropdb --if-exists $1 2>/dev/null; createdb $1
  psql -q -d $1 -v ON_ERROR_STOP=1 -f scripts/local/replay_shim.sql >/dev/null 2>>$S/rg/rb_apply.err || { echo "SHIM FAIL $1"; return 1; }
  for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do
    base=$(basename $f); v=${base%%_*}
    [[ ${#v} -gt 4 ]] && continue
    [[ "$v" > "$2" ]] && continue
    if [ "$base" = "014_frequent_cron_schedules.sql" ]; then
      grep -v '^create extension if not exists pg_' $f | psql -q -d $1 -v ON_ERROR_STOP=1 -f - >/dev/null 2>>$S/rg/rb_apply.err || { echo "APPLY FAIL $1 $base"; return 1; }
    else
      psql -q -d $1 -v ON_ERROR_STOP=1 -f $f >/dev/null 2>>$S/rg/rb_apply.err || { echo "APPLY FAIL $1 $base"; return 1; }
    fi
  done
}
snap() { psql -d $1 -tA -f $ID | grep -v "tap\.\|pg_temp\|pg_toast_temp" > $S/rg/id_$1.txt; }
prev=075; prevdb=rbbase
build_prefix rbbase 075 || exit 1
snap rbbase
for n in 076 077 078 079 080 081 082 083 084 085 086 087 088 089 090 091 092; do
  build_prefix rb_$n $n || exit 1
  rb=$(ls supabase/rollbacks/${n}*_rollback.sql)
  if ! psql -q -d rb_$n -v ON_ERROR_STOP=1 -f $rb > $S/rg/rb_run_$n.out 2>&1; then
    echo "RB $n: ROLLBACK APPLY FAILED"; sed -n 1,3p $S/rg/rb_run_$n.out
  else
    snap rb_$n
    d=$(diff $S/rg/id_$prevdb.txt $S/rg/id_rb_$n.txt 2>/dev/null | wc -l | tr -d ' ')
    echo "RB $n: applied; identity diff vs prefix($prev) = ${d}"
  fi
  prev=$n; prevdb=rb_$n
  # rebuild the clean prefix for the NEXT comparison base
  build_prefix rbp_$n $n || exit 1
  snap rbp_$n; prevdb=rbp_$n
done
echo BATTERY-DONE
