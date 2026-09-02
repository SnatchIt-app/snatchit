#!/bin/zsh
# Persisted from the 2026-09-02 release-readiness pass. Local-only; requires the
# scripts/local PG17 harness env (PGHOST/PGPORT/PGUSER) and the catalog-identity
# query at $RG_OUT/c089/catalog_identity.sql (see scripts/local/README notes).
mkdir -p "${RG_OUT:-/tmp/phase2-release}"
# PRODUCTION-ORDER release rehearsal: build the DB in production's real order
# (000..075, the four website-form timestamped migrations, the reconstructed
# admin-relist RPC), snapshot identity, run the preflight analogue, then apply
# 076..092 exactly as the runbook will, run the post-apply verify, the phase-2
# suite battery, and prove no pre-existing row changed except the two sentinels.
set -u
export LC_ALL=C PGHOST=/tmp/pg150s PGPORT=5433 PGUSER=postgres
cd "$(git rev-parse --show-toplevel)"
S=${RG_OUT:-/tmp/phase2-release}
DB=prodsim
dropdb --if-exists $DB 2>/dev/null; createdb $DB
psql -q -d $DB -v ON_ERROR_STOP=1 -f scripts/local/replay_shim.sql || exit 1
apply() {
  base=$(basename $1)
  if [ "$base" = "014_frequent_cron_schedules.sql" ]; then
    grep -v '^create extension if not exists pg_' $1 | psql -q -d $DB -v ON_ERROR_STOP=1 -f - || { echo "FAIL $base"; exit 1; }
  else
    psql -q -d $DB -v ON_ERROR_STOP=1 -f $1 || { echo "FAIL $base"; exit 1; }
  fi
}
# production's pre-apply world
for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do
  v=$(basename $f); v=${v%%_*}
  if [[ ${#v} -le 4 && ! "$v" > "075" ]]; then apply $f; fi
done
for f in supabase/migrations/20260714190445_investor_leads_website_form.sql \
         supabase/migrations/20260730212326_ambassador_applications_website_form.sql \
         supabase/migrations/20260730212406_ambassador_applications_fix_search_path.sql \
         supabase/migrations/20260731224653_venue_partnership_inquiries_website_form.sql \
         supabase/migrations/20260902003623_admin_relist_listing_rpc.sql; do apply $f; done
psql -q -d $DB -v ON_ERROR_STOP=1 -f supabase/ci/parity_grants.sql || exit 1
echo "PREAPPLY WORLD BUILT"
# seed a little legacy-shaped live data so "no live-row mutation" is provable
psql -q -d $DB -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','legacy1@test.local','{"provider":"email"}','{}',now(),now()),
       ('aaaaaaaa-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','legacy2@test.local','{"provider":"email"}','{}',now(),now())
on conflict do nothing;
insert into public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method, starting_bid, current_bid, duration_hours, ends_at, cover_image_path)
values ('aaaaaaaa-0000-0000-0000-000000000001','Legacy Show','Old Hall','wynwood',(now()+interval '30 days')::date,'20:00','GA',2,'mobile_transfer',4000,4000,24,now()+interval '2 days','covers/x.jpg');
insert into public.push_tokens (user_id, token, platform, device_name, is_active)
values ('aaaaaaaa-0000-0000-0000-000000000002','ExponentPushToken[legacy-1]','ios','iPhone',true);
SQL
# frozen snapshot of every pre-existing row (data checksum per table)
psql -d $DB -tA -c "
  select 'listings|'||coalesce(md5(string_agg(t.*::text, E'\n' order by id)), 'empty') from public.listings t
  union all select 'payments|'||coalesce(md5(string_agg(t.*::text, E'\n' order by id)), 'empty') from public.payments t
  union all select 'transfers|'||coalesce(md5(string_agg(t.*::text, E'\n' order by id)), 'empty') from public.transfers t
  union all select 'push_tokens_prewindow|'||coalesce(md5(string_agg((t.user_id, t.token, t.platform, t.is_active)::text, E'\n' order by t.token)), 'empty') from public.push_tokens t
  union all select 'auth_users_nonsentinel|'||coalesce(md5(string_agg(t.id::text, E'\n' order by id)), 'empty') from auth.users t where t.raw_app_meta_data->>'provider' is distinct from 'sentinel'
" > $S/rg/prodsim_pre.txt
# THE APPLY — 076..092 in order, one transaction per file, timed
start=$(date +%s)
for f in $(ls supabase/migrations/0[789]*.sql | LC_ALL=C sort); do
  v=$(basename $f); v=${v%%_*}
  if [[ ${#v} -le 4 && "$v" > "075" ]]; then t0=$(date +%s%3N 2>/dev/null || date +%s); apply $f; fi
done
echo "APPLY 076..092 WALL SECONDS: $(( $(date +%s) - start ))"
psql -d $DB -tA -c "
  select 'listings|'||coalesce(md5(string_agg(t.*::text, E'\n' order by id)), 'empty') from public.listings t
  union all select 'payments|'||coalesce(md5(string_agg(t.*::text, E'\n' order by id)), 'empty') from public.payments t
  union all select 'transfers|'||coalesce(md5(string_agg(t.*::text, E'\n' order by id)), 'empty') from public.transfers t
  union all select 'push_tokens_prewindow|'||coalesce(md5(string_agg((t.user_id, t.token, t.platform, t.is_active)::text, E'\n' order by t.token)), 'empty') from public.push_tokens t
  union all select 'auth_users_nonsentinel|'||coalesce(md5(string_agg(t.id::text, E'\n' order by id)), 'empty') from auth.users t where t.raw_app_meta_data->>'provider' is distinct from 'sentinel'
" > $S/rg/prodsim_post.txt
echo "LIVE-ROW MUTATION CHECK (diff lines): $(diff $S/rg/prodsim_pre.txt $S/rg/prodsim_post.txt | wc -l | tr -d ' ')"
# faux CLI ledger so phase2_postapply_verify.sql V1 runs identically to production
psql -q -d $DB -v ON_ERROR_STOP=1 -c "create schema if not exists supabase_migrations" -c "create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text)"
for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do v=$(basename $f); v=${v%%_*}; psql -q -d $DB -c "insert into supabase_migrations.schema_migrations (version, name) values ('"'"'$v'"'"', '"'"'x'"'"') on conflict do nothing"; done
echo "== post-apply verify:"
psql -d $DB -tA -F' | ' -f scripts/release/phase2_postapply_verify.sql
echo "== phase-2 suite battery on the production-order DB:"
scripts/local/runtests.sh $DB supabase/tests/140_phase2_outbox_foundation.sql supabase/tests/141_phase2_identity_orgs_deletion.sql supabase/tests/142_phase2_catalog_config_and_seeds.sql supabase/tests/143_phase2_ticket_custody_kernel.sql supabase/tests/144_phase2_venue_staff_authz.sql supabase/tests/145_phase2_venue_inventory.sql supabase/tests/146_phase2_venue_orders.sql supabase/tests/147_phase2_kernel_credential_infrastructure.sql supabase/tests/148_phase2_kernel_tickets_late_binding_fks.sql supabase/tests/149_phase2_kernel_money_native.sql supabase/tests/150_phase2_venue_door_and_scan.sql supabase/tests/151_phase2_venue_settlement_and_export.sql supabase/tests/152_crm_export_x6.sql supabase/tests/153_phase2_market_native_rail.sql supabase/tests/154_phase2_market_bridge_view_and_late_fk.sql supabase/tests/155_phase2_venue_promoter_engine.sql supabase/tests/156_phase2_kernel_reserve_stub.sql supabase/tests/157_phase2_notify_reduced.sql 2>&1 | tail -22
echo REHEARSAL-DONE
