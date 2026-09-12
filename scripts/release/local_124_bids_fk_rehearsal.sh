#!/bin/zsh
set -u
export LC_ALL=C
cd "$(git rev-parse --show-toplevel)"
if [ -S /tmp/pg150s/.s.PGSQL.5433 ]; then export PGHOST=/tmp/pg150s PGPORT=5433 PGUSER=postgres; fi
DB=snatchit_124_rehears
echo "== P6 absent + clean =="
psql -q -d $DB -c "delete from public.bids where bidder_id = 'cccccccc-0000-0000-0000-000000000009'" >/dev/null
psql -d $DB -v ON_ERROR_STOP=1 -f supabase/migrations/124_bids_profiles_fk_parity.sql 2>&1 | grep -E "NOTICE|ERROR" | head -2
echo -n "P6 definition: "; psql -d $DB -tA -c "select coalesce((select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'),'ABSENT')"
dropdb --if-exists $DB 2>/dev/null; createdb $DB || exit 1
psql -q -d $DB -v ON_ERROR_STOP=1 -f scripts/local/replay_shim.sql || { echo "SHIM FAIL"; exit 1; }
apply() {
  base=$(basename $1)
  if [ "$base" = "014_frequent_cron_schedules.sql" ]; then
    grep -v '^create extension if not exists pg_' $1 | psql -q -d $DB -v ON_ERROR_STOP=1 -f - || { echo "FAIL $base"; exit 1; }
  else
    psql -q -d $DB -v ON_ERROR_STOP=1 -f $1 >/dev/null || { echo "FAIL $base"; exit 1; }
  fi
}
n=0
for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do
  case "$(basename $f)" in 124_*) continue;; esac
  apply $f; n=$((n+1))
done
echo "CHAIN REPLAYED: $n files (124 withheld)"
echo -n "P1 chain state: "; psql -d $DB -tA -c "select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'"
BEFORE=$(psql -d $DB -tA -c "select oid||'/'||xmin from pg_constraint where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'")
psql -q -d $DB -v ON_ERROR_STOP=1 -f supabase/migrations/124_bids_profiles_fk_parity.sql 2>&1 | grep -E "NOTICE|ERROR" | head -2
echo -n "P2 after 124: "; psql -d $DB -tA -c "select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'"
AFTER1=$(psql -d $DB -tA -c "select oid||'/'||xmin from pg_constraint where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'")
psql -q -d $DB -v ON_ERROR_STOP=1 -f supabase/migrations/124_bids_profiles_fk_parity.sql 2>&1 | grep -E "NOTICE|ERROR" | head -2
AFTER2=$(psql -d $DB -tA -c "select oid||'/'||xmin from pg_constraint where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'")
echo "P3 no-op proof: before=$BEFORE after1=$AFTER1 after2=$AFTER2"
[ "$AFTER1" = "$AFTER2" ] && echo "P3 PASS: second run changed no catalog row" || echo "P3 FAIL"
echo "== P4 pgTAP 192 =="
psql -q -d $DB -c "create extension if not exists pgtap" >/dev/null 2>&1
psql -d $DB -tA -f supabase/tests/192_bids_profiles_fk_parity.sql 2>&1 | tail -14
echo "== P5 orphan guard =="
psql -q -d $DB -v ON_ERROR_STOP=1 <<'SQL' >/dev/null 2>&1
set session_replication_role = replica;
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('bbbbbbbb-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','orphan@test.local','{"provider":"email"}','{}',now(),now()) on conflict do nothing;
insert into public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
select 'bbbbbbbb-0000-0000-0000-000000000001','Orphan Test','Hall','wynwood',(now()+interval '30 days')::date,'20:00','GA',1,'mobile_transfer',100,100,24,now()+interval '2 days','covers/x.jpg';
alter table public.bids drop constraint bids_bidder_id_fkey;
insert into public.bids (listing_id, bidder_id, amount)
select id, 'cccccccc-0000-0000-0000-000000000009', 200 from public.listings where event_name='Orphan Test' limit 1;
SQL
psql -d $DB -v ON_ERROR_STOP=1 -f supabase/migrations/124_bids_profiles_fk_parity.sql 2>&1 | grep -E "124 REFUSED|ERROR|NOTICE" | head -2
echo -n "P5 constraint still absent (guard did not recreate): "; psql -d $DB -tA -c "select count(*) from pg_constraint where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'"
echo "== P6 absent + clean =="
psql -q -d $DB -c "delete from public.bids where bidder_id = 'cccccccc-0000-0000-0000-000000000009'" >/dev/null
psql -d $DB -v ON_ERROR_STOP=1 -f supabase/migrations/124_bids_profiles_fk_parity.sql 2>&1 | grep -E "NOTICE|ERROR" | head -2
echo -n "P6 definition: "; psql -d $DB -tA -c "select coalesce((select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'),'ABSENT')"
dropdb --if-exists $DB
