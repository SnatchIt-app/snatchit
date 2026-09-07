#!/bin/bash
# =============================================================================
# scripts/release/payments_rc_prod_order_rehearsal.sh <db-name-containing-rehears>
#
# PRODUCTION-ORDER UPGRADE REHEARSAL for the payments reliability release
# candidate (20260906100000 .. 20260906130000) against an isolated reproduction
# of the DEPLOYED schema — production's ledger in production's real order:
#   000..075 → the four website-form timestamped migrations (2026-07) →
#   076..092 (2026-09-02) → 20260902003623 (2026-09-02) → 093..109 (2026-09-04)
# (124 versions = the production ledger read on 2026-09-06). A fresh LC_ALL=C
# replay applies 20260902003623 AFTER 109, which is NOT what production did;
# this script does what production did.
#
# Then, with legacy live data seeded the way production holds it:
#   D  apply the four RC migrations in order; census + no live-row mutation
#   E  intermediate-state compatibility: old edges / old clients / in-flight
#      payments against the new schema, deploy-window payout races
#   F  rollback with NEW financial records present: drain, export, roll back
#      4→3→2→1, prove money facts survive and old code still works, re-apply,
#      re-import the ledger
# LOCAL ONLY. Never points at a Supabase project. Exit 1 on any FAIL.
# =============================================================================
set -uo pipefail
export LC_ALL=C
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}" PGPORT="${REHEARSAL_PGPORT:-5432}" PGUSER="${REHEARSAL_PGUSER:-postgres}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
DB="${1:?usage: $0 <db-name-containing-rehears>}"
case "$DB" in *rehears*) ;; *) echo "refusing: db name must contain 'rehears'"; exit 2;; esac
case "$PGHOST" in 127.0.0.1|localhost|/*) ;; *) echo "refusing: PGHOST must be loopback"; exit 2;; esac
OUT="${RC_OUT:-${TMPDIR:-/tmp}/payments_rc_prodsim}"; mkdir -p "$OUT"
FAILS=0; PASSES=0
ok()   { PASSES=$((PASSES+1)); echo "PASS  $1"; }
bad()  { FAILS=$((FAILS+1));  echo "FAIL  $1  [$2]"; }
q()    { psql -X -qtA -d "$DB" -v ON_ERROR_STOP=1 -c "$1" 2>&1; }
check(){ local name="$1" sql="$2" want="${3:-t}"; local raw got; raw=$(q "$sql"); got=$(printf '%s' "$raw" | tr -d '[:space:]'); [ "$got" = "$want" ] && ok "$name" || bad "$name" "want=$want raw=$(printf '%s' "$raw" | head -c 240)"; }
run()  { psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f "$1" >"$OUT/last.out" 2>&1; local rc=$?; cp "$OUT/last.out" "$OUT/$(basename "$1").out"; [ $rc -eq 0 ] || { echo "  (psql error in $1)"; grep -E "ERROR|DETAIL" "$OUT/last.out" | head -3 | cut -c1-200; return 1; }; }
act()  { local name="$1" sql="$2"; local raw; raw=$(q "$sql") && ok "$name → $(printf '%s' "$raw" | tr -d '\n' | head -c 120)" || bad "$name" "$(printf '%s' "$raw" | head -c 240)"; }
apply(){ local f="$1" base; base=$(basename "$f")
  if [ "$base" = "014_frequent_cron_schedules.sql" ]; then grep -v '^create extension if not exists pg_' "$f" | psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f - >/dev/null 2>>"$OUT/apply.err" || { echo "APPLY FAIL $base"; tail -3 "$OUT/apply.err"; exit 1; }
  else psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>>"$OUT/apply.err" || { echo "APPLY FAIL $base"; tail -3 "$OUT/apply.err"; exit 1; }; fi; }
CENSUS="select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r')||'|'||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e'))||'|'||(select count(*) from pg_policies where schemaname='public')||'|'||(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)"
FNHASH="select md5(string_agg(pg_get_functiondef(p.oid), chr(10) order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','kernel') and p.prokind='f' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')"
LIVEHASH="select md5(coalesce((select string_agg(md5(row_to_json(x)::text), ',' order by x.id) from (select id,status,total,amount,paid_at,refunded_at,stripe_refund_id,buyer_id,seller_id,listing_id from public.payments) x),'')) || '|' || md5(coalesce((select string_agg(md5(row_to_json(y)::text), ',' order by y.id) from (select id,status,payout_released_at,stripe_transfer_id,disputed_at from public.transfers) y),'')) || '|' || md5(coalesce((select string_agg(md5(row_to_json(z)::text), ',' order by z.id) from (select id,status,reserved_by,winner_user_id from public.listings) z),''))"

echo "=== A. build production's world in production's order → $DB"
dropdb --if-exists "$DB" 2>/dev/null; createdb "$DB" || exit 1
: > "$OUT/apply.err"
psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f scripts/local/replay_shim.sql >/dev/null 2>&1 || { echo "SHIM FAIL"; exit 1; }
n=0
for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do v=$(basename "$f"); v=${v%%_*}; if [ ${#v} -le 4 ] && [[ ! "$v" > "075" ]]; then apply "$f"; n=$((n+1)); fi; done
for f in supabase/migrations/20260714190445_investor_leads_website_form.sql supabase/migrations/20260730212326_ambassador_applications_website_form.sql supabase/migrations/20260730212406_ambassador_applications_fix_search_path.sql supabase/migrations/20260731224653_venue_partnership_inquiries_website_form.sql; do apply "$f"; n=$((n+1)); done
for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do v=$(basename "$f"); v=${v%%_*}; if [ ${#v} -le 4 ] && [[ "$v" > "075" ]] && [[ ! "$v" > "092" ]]; then apply "$f"; n=$((n+1)); fi; done
apply supabase/migrations/20260902003623_admin_relist_listing_rpc.sql; n=$((n+1))
for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do v=$(basename "$f"); v=${v%%_*}; if [ ${#v} -le 4 ] && [[ "$v" > "092" ]] && [[ ! "$v" > "109" ]]; then apply "$f"; n=$((n+1)); fi; done
psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f supabase/ci/parity_grants.sql >/dev/null 2>&1 || { echo "parity grants FAIL"; exit 1; }
check "A1 production ledger reproduced: 124 versions applied in production order" "select $n" "124"
check "A2 pre-upgrade Gate-2 census = 27|70|37|26 (production)" "$CENSUS" "27|70|37|26"
PRE_FN=$(q "$FNHASH"); echo "      pre-upgrade function hash $PRE_FN"

echo "=== B. seed legacy live data (production shapes)"
psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/000_helpers.sql >/dev/null 2>&1 || { echo "helpers FAIL"; exit 1; }
cat > "$OUT/seed.sql" <<'SQL'
BEGIN;
SELECT tap.seed_core();
-- fixture writes to server-controlled listing columns (reservation, sold) use the
-- transaction-local guard bypass exactly as the pgTAP suites do
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.payments SET stripe_livemode = true WHERE stripe_payment_intent_id IN ('pi_fixture_a','pi_fixture_b');
UPDATE public.profiles SET stripe_connect_id = 'acct_A' WHERE id = tap.seller();
-- L1 legacy PAID transfer (old edge path: auto-release then record_transfer_payout)
SELECT public.apply_auto_release(tap.transfer_b());
SELECT public.record_transfer_payout(tap.transfer_b(), 'tr_legacy_b');
-- L2 transfer A stays OPEN (pending) so the buyer is held by the Phase-2 BP-7 arm throughout
-- L4 paid-but-unsettled capture (succeeded 10 min ago, ACTIVE listing E8 not sold, no transfer — the F02 shape)
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES ('aaaaaaaa-0000-0000-0000-0000000000e8', tap.seller(), 'Prodsim E8', 'Club E8', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e8.jpg', 'active');
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode, created_at)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000e8', tap.other_user(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_legacy_e', 'succeeded', 'buy_now', now() - interval '10 minutes', true, now() - interval '11 minutes');
-- E2 fixture: a second Buy-Now listing with a pending payment created BEFORE the upgrade (in-flight checkout)
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES ('aaaaaaaa-0000-0000-0000-0000000000e2', tap.seller(), 'Prodsim E2', 'Club E2', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e2.jpg', 'active'),
       ('aaaaaaaa-0000-0000-0000-0000000000e3', tap.seller(), 'Prodsim E3', 'Club E3', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e3.jpg', 'active'),
       ('aaaaaaaa-0000-0000-0000-0000000000e4', tap.seller(), 'Prodsim E4', 'Club E4', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e4.jpg', 'active'),
       ('aaaaaaaa-0000-0000-0000-0000000000e5', tap.seller(), 'Prodsim E5', 'Club E5', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e5.jpg', 'active'),
       ('aaaaaaaa-0000-0000-0000-0000000000e6', tap.seller(), 'Prodsim E6', 'Club E6', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e6.jpg', 'active'),
       ('aaaaaaaa-0000-0000-0000-0000000000e7', tap.seller(), 'Prodsim E7', 'Club E7', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e7.jpg', 'active');
UPDATE public.listings SET reserved_by = tap.other_user(), reserved_until = now() + interval '8 minutes' WHERE id = 'aaaaaaaa-0000-0000-0000-0000000000e2';
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode)
VALUES ('eeeeeeee-0000-0000-0000-0000000000e2', 'aaaaaaaa-0000-0000-0000-0000000000e2', tap.other_user(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_inflight_e2', 'pending', 'buy_now', true);
-- E6/E7 fixtures: two more paid, released, UNPAID transfers for the deploy-window races
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
VALUES ('eeeeeeee-0000-0000-0000-0000000000e4', 'aaaaaaaa-0000-0000-0000-0000000000e4', tap.other_user(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_e4', 'succeeded', 'buy_now', now() - interval '3 days', true),
       ('eeeeeeee-0000-0000-0000-0000000000e5', 'aaaaaaaa-0000-0000-0000-0000000000e5', tap.other_user(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_e5', 'succeeded', 'buy_now', now() - interval '3 days', true),
       ('eeeeeeee-0000-0000-0000-0000000000e6', 'aaaaaaaa-0000-0000-0000-0000000000e6', tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_e6', 'succeeded', 'buy_now', now() - interval '3 days', true),
       ('eeeeeeee-0000-0000-0000-0000000000e7', 'aaaaaaaa-0000-0000-0000-0000000000e7', tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_e7', 'succeeded', 'buy_now', now() - interval '3 days', true);
UPDATE public.listings SET auction_status = 'sold' WHERE id IN ('aaaaaaaa-0000-0000-0000-0000000000e4','aaaaaaaa-0000-0000-0000-0000000000e5','aaaaaaaa-0000-0000-0000-0000000000e6','aaaaaaaa-0000-0000-0000-0000000000e7');
INSERT INTO public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at, transfer_evidence_path, expires_at)
VALUES ('cccccccc-0000-0000-0000-0000000000e4', 'aaaaaaaa-0000-0000-0000-0000000000e4', 'eeeeeeee-0000-0000-0000-0000000000e4', tap.seller(), tap.other_user(), 'mobile_transfer', 'auto_released', now() - interval '3 days', now() - interval '1 day', NULL, now() + interval '72 hours'),
       ('cccccccc-0000-0000-0000-0000000000e5', 'aaaaaaaa-0000-0000-0000-0000000000e5', 'eeeeeeee-0000-0000-0000-0000000000e5', tap.seller(), tap.other_user(), 'mobile_transfer', 'auto_released', now() - interval '3 days', now() - interval '1 day', NULL, now() + interval '72 hours'),
       ('cccccccc-0000-0000-0000-0000000000e6', 'aaaaaaaa-0000-0000-0000-0000000000e6', 'eeeeeeee-0000-0000-0000-0000000000e6', tap.seller(), tap.buyer(), 'mobile_transfer', 'auto_released', now() - interval '3 days', now() - interval '1 day', NULL, now() + interval '72 hours'),
       ('cccccccc-0000-0000-0000-0000000000e7', 'aaaaaaaa-0000-0000-0000-0000000000e7', 'eeeeeeee-0000-0000-0000-0000000000e7', tap.seller(), tap.buyer(), 'mobile_transfer', 'auto_released', now() - interval '3 days', now() - interval '1 day', NULL, now() + interval '72 hours');
-- L5 kernel: the buyer has requested deletion (OR-17 machine live in production)
SELECT tap.login(tap.buyer());
SELECT kernel.request_account_deletion('prodsim-del-1');
SELECT tap.logout();
COMMIT;
SQL
run "$OUT/seed.sql" || { echo "seed FAIL"; exit 1; }
check "B1 legacy paid transfer B carries tr_legacy_b" "select stripe_transfer_id from public.transfers where id = tap.transfer_b()" "tr_legacy_b"
check "B2 legacy released-unpaid transfer E4 (pre-ledger shape) and open transfer A" "select (select status || '|' || coalesce(stripe_transfer_id,'-') from public.transfers where id = 'cccccccc-0000-0000-0000-0000000000e4') || '|' || (select status from public.transfers where id = tap.transfer_a())" "auto_released|-|pending"
check "B3 buyer is DELETION_PENDING under the deployed machine" "select deletion_state from kernel.identity_ext where identity_id = tap.buyer()" "DELETION_PENDING"
act "B4-act sweep_deletion_pending" "select (kernel.sweep_deletion_pending())->>'tombstoned'"
check "B4 pre-upgrade sweep holds the buyer on a Phase-2 arm (BP-7 live transfer)" "select deletion_state = 'DELETION_PENDING' and deletion_block_reason like 'BP-7%' from kernel.identity_ext where identity_id = tap.buyer()" "t"
PRE_LIVE=$(q "$LIVEHASH"); echo "      pre-upgrade live-row hash $PRE_LIVE"

echo "=== D. apply the four RC migrations in release order"
for f in 20260906100000_checkout_reservation_authority 20260906110000_settle_verified_payment 20260906120000_payout_attempts_and_refund_monotonic 20260906130000_deletion_sweep_live_rail_obligations; do apply "supabase/migrations/$f.sql"; done
check "D1 post-upgrade Gate-2 census = 30|86|37|32" "$CENSUS" "30|86|37|32"
check "D2 the upgrade mutated NO live payments/transfers/listings row" "select '$PRE_LIVE' = ($LIVEHASH)" "t"
RC_FN=$(psql -X -qtA -d snatchit_rc_rehearsal -c "$FNHASH" 2>/dev/null || echo none)
check "D3 function definitions identical to the fresh LC_ALL=C replay (order-independent)" "select '$RC_FN' = ($FNHASH)" "t"
check "D4 legacy rows untouched: B still paid, E4 still released-unpaid" "select (select stripe_transfer_id from public.transfers where id = tap.transfer_b()) || '|' || (select coalesce(stripe_transfer_id,'-') from public.transfers where id = 'cccccccc-0000-0000-0000-0000000000e4')" "tr_legacy_b|-"

echo "=== E. intermediate states: OLD edges / OLD clients / in-flight money on the NEW schema"
# E1 OLD webhook on the in-flight payment: promote, then mark_listing_sold, then its own transfers INSERT
cat > "$OUT/e1.sql" <<'SQL'
UPDATE public.payments SET status = 'succeeded', paid_at = now() WHERE stripe_payment_intent_id = 'pi_inflight_e2' AND status <> 'succeeded';
SELECT public.mark_listing_sold('aaaaaaaa-0000-0000-0000-0000000000e2', tap.other_user());
SQL
run "$OUT/e1.sql" && ok "E1a old webhook sequence (promote → mark_listing_sold) succeeds against P1: the payment is bound and succeeded" || bad "E1a old webhook sequence" "see $OUT/last.out"
check "E1b listing E2 sold and exactly one transfer created by the settlement core" "select (select status from public.listings where id='aaaaaaaa-0000-0000-0000-0000000000e2') || '|' || (select count(*) from public.transfers where payment_id='eeeeeeee-0000-0000-0000-0000000000e2')" "sold|1"
E1C=$(q "insert into public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at) values ('aaaaaaaa-0000-0000-0000-0000000000e2','eeeeeeee-0000-0000-0000-0000000000e2', tap.seller(), tap.other_user(), 'mobile_transfer', 'pending', now() + interval '72 hours')" 2>&1 | grep -oE "duplicate key|23505|unique" | head -1)
[ -n "$E1C" ] && ok "E1c the old webhook's own transfers INSERT collides (unique) — the deployed code treats that as 'already created' and continues" || bad "E1c old webhook duplicate transfer insert should collide" "no unique violation"
# E2 OLD client + OLD confirm-payment: reserve with p_minutes, promote + insert transfer directly, then the NEW webhook settles
cat > "$OUT/e2a.sql" <<'SQL'
BEGIN;
SELECT tap.login(tap.other_user());
SELECT public.reserve_buy_now('aaaaaaaa-0000-0000-0000-0000000000e3', tap.other_user(), 30);
SELECT tap.logout();
COMMIT;
SQL
run "$OUT/e2a.sql" && ok "E2a old client reserve_buy_now(listing, user, p_minutes=30) is still accepted (signature kept)" || bad "E2a old client reserve_buy_now" "see $OUT/last.out"
check "E2a' …but the window is server-fixed to 10 minutes regardless of p_minutes" "select reserved_by = tap.other_user() and reserved_until between now() + interval '9 minutes' and now() + interval '11 minutes' from public.listings where id='aaaaaaaa-0000-0000-0000-0000000000e3'" "t"
cat > "$OUT/e2.sql" <<'SQL'
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode)
VALUES ('eeeeeeee-0000-0000-0000-0000000000e3', 'aaaaaaaa-0000-0000-0000-0000000000e3', tap.other_user(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_e3', 'pending', 'buy_now', true);
-- old confirm-payment: promote and insert the transfer itself (no mark_listing_sold)
UPDATE public.payments SET status = 'succeeded', paid_at = now(), payment_method = 'card' WHERE stripe_payment_intent_id = 'pi_e3' AND buyer_id = tap.other_user();
INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
VALUES ('aaaaaaaa-0000-0000-0000-0000000000e3','eeeeeeee-0000-0000-0000-0000000000e3', tap.seller(), tap.other_user(), 'mobile_transfer', 'pending', now() + interval '72 hours');
SQL
run "$OUT/e2.sql" && ok "E2b old confirm-payment writes (promote + direct transfer insert) are accepted by the new guards" || bad "E2b old confirm-payment writes" "see $OUT/last.out"
check "E2c the NEW webhook then settles the same payment through the contract" "select outcome from public.settle_verified_payment('pi_e3','succeeded',22000,'usd',true,0,NULL,'card', jsonb_build_object('mode','buy_now','listing_id','aaaaaaaa-0000-0000-0000-0000000000e3','buyer_id',tap.other_user()::text,'seller_id',tap.seller()::text),'webhook')" "settled"
check "E2c' …listing E3 sold, still exactly ONE transfer (the old edge's row was adopted, not duplicated)" "select (select status from public.listings where id='aaaaaaaa-0000-0000-0000-0000000000e3') || '|' || (select count(*) from public.transfers where payment_id='eeeeeeee-0000-0000-0000-0000000000e3')" "sold|1"
# E4 OLD confirm-and-release path after P3
check "E4 old confirm-and-release path (record_transfer_payout) still records a legacy payout on E4" "select public.record_transfer_payout('cccccccc-0000-0000-0000-0000000000e4', 'tr_legacy_e4')" "t"
check "E4' …the row carries tr_legacy_e4 and payout_released_at" "select stripe_transfer_id || '|' || (payout_released_at is not null)::text from public.transfers where id='cccccccc-0000-0000-0000-0000000000e4'" "tr_legacy_e4|true"
E4B=$(q "select * from public.claim_payout_attempt('cccccccc-0000-0000-0000-0000000000e4', 'prodsim')" 2>&1 | grep -c ALREADY_RELEASED); [ "$E4B" = "1" ] && ok "E4b new claim on a legacy-paid transfer → ALREADY_RELEASED (no second payout)" || bad "E4b claim should raise ALREADY_RELEASED" "$E4B"
# E5 paid-unsettled legacy capture is found and settled by the new sweep contract
check "E5 legacy paid-unsettled capture (F02 shape) is listed as paid_unsettled work" "select exists (select 1 from public.get_unsettled_payments(50) where stripe_payment_intent_id='pi_legacy_e' and kind='paid_unsettled')" "t"
check "E5' …and settles through the contract" "select outcome from public.settle_verified_payment('pi_legacy_e','succeeded',11000,'usd',true,0,NULL,'card', jsonb_build_object('mode','buy_now','listing_id','aaaaaaaa-0000-0000-0000-0000000000e8','buyer_id',tap.other_user()::text,'seller_id',tap.seller()::text),'sweep')" "settled"
check "E5'' …listing E8 sold, one transfer created" "select (select status from public.listings where id='aaaaaaaa-0000-0000-0000-0000000000e8') || '|' || (select count(*) from public.transfers where payment_id='eeeeeeee-0000-0000-0000-000000000001')" "sold|1"
# E6 deploy window: new attempt in flight while the OLD edge records the same Stripe transfer
cat > "$OUT/e6.sql" <<'SQL'
CREATE TEMP TABLE _e6 AS SELECT * FROM public.claim_payout_attempt('cccccccc-0000-0000-0000-0000000000e6', 'prodsim:new-edge');
SELECT public.mark_payout_requested((SELECT attempt_id FROM _e6));
-- the OLD edge (still deployed during the window) records the transfer Stripe created under the new key
SELECT public.record_transfer_payout('cccccccc-0000-0000-0000-0000000000e6', 'tr_e6');
-- the NEW edge records the same transfer
SELECT (public.record_payout_attempt_result((SELECT attempt_id FROM _e6), 'tr_e6', 'succeeded', NULL))->>'state' AS state \gset
SELECT :'state' = 'succeeded' AS e6_same_id_ok \gset
SELECT public.record_payout_attempt_result((SELECT attempt_id FROM _e6), 'tr_e6', 'succeeded', NULL);
SQL
run "$OUT/e6.sql" && ok "E6a deploy-window race, same Stripe transfer id recorded by old and new code: no error" || bad "E6a" "see $OUT/last.out"
check "E6b …attempt succeeded, no DUPLICATE_TRANSFER review, one tr_ on the row" "select (select state from public.payout_attempts where transfer_id='cccccccc-0000-0000-0000-0000000000e6') || '|' || (select count(*) from public.payout_decisions where transfer_id='cccccccc-0000-0000-0000-0000000000e6' and decision='manual_review') || '|' || (select stripe_transfer_id from public.transfers where id='cccccccc-0000-0000-0000-0000000000e6')" "succeeded|0|tr_e6"
# E7 deploy window: old edge paid tr_e7_old, new attempt (already requested) came back with tr_e7_new → DETECTED
cat > "$OUT/e7.sql" <<'SQL'
CREATE TEMP TABLE _e7 AS SELECT * FROM public.claim_payout_attempt('cccccccc-0000-0000-0000-0000000000e7', 'prodsim:new-edge');
SELECT public.mark_payout_requested((SELECT attempt_id FROM _e7));
SELECT public.record_transfer_payout('cccccccc-0000-0000-0000-0000000000e7', 'tr_e7_old');
SELECT public.record_payout_attempt_result((SELECT attempt_id FROM _e7), 'tr_e7_new', 'succeeded', NULL);
SQL
run "$OUT/e7.sql" && ok "E7a deploy-window double payout (old tr_e7_old, new tr_e7_new) is recorded, never silent" || bad "E7a" "see $OUT/last.out"
check "E7b …attempt reversal_required + DUPLICATE_TRANSFER manual_review; the row keeps the FIRST tr_" "select (select state from public.payout_attempts where transfer_id='cccccccc-0000-0000-0000-0000000000e7') || '|' || (select count(*) from public.payout_decisions where transfer_id='cccccccc-0000-0000-0000-0000000000e7' and 'DUPLICATE_TRANSFER' = any(reason_codes)) || '|' || (select stripe_transfer_id from public.transfers where id='cccccccc-0000-0000-0000-0000000000e7')" "reversal_required|1|tr_e7_old"
# E8 kernel machine after upgrade: the pending buyer is still held; BP order preserved; BP-13 reachable
act "E8a-act sweep_deletion_pending" "select (kernel.sweep_deletion_pending())->>'tombstoned'"
check "E8a post-upgrade sweep still holds the buyer on BP-7 (Phase-2 arm precedes BP-13)" "select deletion_state = 'DELETION_PENDING' and deletion_block_reason like 'BP-7%' from kernel.identity_ext where identity_id = tap.buyer()" "t"
check "E8b BP-13 predicate names the seller's live-rail obligations (open_manual_review from E7, unpaid obligations)" "select public.account_deletion_block_reason(tap.seller()) like 'BP-13:%open_manual_review%'" "t"

echo "=== F. rollback with NEW financial records present -> gates, drain, archive, roll back, window hazards, restore"
RB=supabase/rollbacks
rb()   { local f="$1"; psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f "$RB/${f}_rollback.sql" 2>&1; }   # files carry their own BEGIN/COMMIT
# F0 — new-code facts of every class the gates watch
cat > "$OUT/f0.sql" <<'SQL'
BEGIN;
-- D2: partial refund on the settled legacy capture, whose transfer is then released and unpaid
SELECT public.record_payment_refund('pi_legacy_e', 're_prodsim_1', NULL, 500, 'dashboard');
-- the seller sends the ticket: a seller_sent transfer with a partial refund on its payment is exactly the
-- row old confirm-and-release would pay in full once the buyer confirms (R5 S1)
SELECT tap.login(tap.seller());
SELECT public.mark_transfer_sent((SELECT id FROM public.transfers WHERE payment_id = 'eeeeeeee-0000-0000-0000-000000000001'), tap.seller());
SELECT tap.logout();
-- D3: a review row with no old-code reader
SELECT public.settle_verified_payment('pi_unknown_prodsim','succeeded',1000,'usd',true,0,NULL,'card','{}'::jsonb,'webhook');
-- D6: an identity held ONLY by BP-13 (admin user: paid capture, no transfer, nothing Phase-2)
SELECT set_config('app.bypass_listing_guard', 'on', true);
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES ('aaaaaaaa-0000-0000-0000-0000000000e9', tap.seller(), 'Prodsim E9', 'Club E9', 'wynwood', current_date + 30, '21:00', 'GA', 1, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e9.jpg', 'active');
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode, created_at)
VALUES ('eeeeeeee-0000-0000-0000-0000000000e9', 'aaaaaaaa-0000-0000-0000-0000000000e9', tap.admin_user(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_e9', 'succeeded', 'buy_now', now() - interval '10 minutes', true, now() - interval '11 minutes');
SELECT tap.login(tap.admin_user());
SELECT kernel.request_account_deletion('prodsim-del-admin');
SELECT tap.logout();
SELECT kernel.sweep_deletion_pending();
COMMIT;
SQL
run "$OUT/f0.sql" && ok "F0 facts seeded: partial refund + unpaid seller_sent transfer (D2), review row (D3), BP-13-only identity (D6)" || bad "F0" "see $OUT/last.out"
OPEN=$(q "select attempt_id from public.claim_payout_attempt('cccccccc-0000-0000-0000-0000000000e5', 'prodsim:open')" 2>/dev/null | head -1)
q "select public.mark_payout_requested('$OPEN')" >/dev/null 2>&1
check "F0b open attempt (D1) on E5; E7 reversal_required (D5); admin held on BP-13 (D6)" "select (select count(*) from public.payout_attempts where state in ('claimed','requested','unknown')) || '|' || (select count(*) from public.payout_attempts where state='reversal_required') || '|' || (select deletion_block_reason like 'BP-13%' from kernel.identity_ext where identity_id = tap.admin_user())" "1|1|true"
# F1 — gates refuse (and ordering is enforced)
R=$(rb 20260906130000_deletion_sweep_live_rail_obligations); case "$R" in *"REFUSED"*"D6=1"*) ok "F1 130000 rollback REFUSED while an identity is held only by BP-13 (D6)";; *) bad "F1 130000 gate" "$(printf '%s' "$R" | head -c 200)";; esac
R=$(rb 20260906120000_payout_attempts_and_refund_monotonic); case "$R" in *"REFUSED"*"O2=1"*) ok "F1b 120000 rollback REFUSED out of order (130000 still applied, O2)";; *) bad "F1b 120000 ordering gate" "$(printf '%s' "$R" | head -c 200)";; esac
check "F1c nothing was dropped by the refused attempts (transaction rolled back)" "select (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='account_deletion_block_reason') || '|' || (select count(*) from pg_tables where schemaname='public' and tablename='payout_attempts')" "1|1"
# F2 — drain every detector by the platform act that settles it (never by editing state)
cat > "$OUT/f2.sql" <<'SQL'
BEGIN;
SELECT tap.login(tap.admin_user());
SELECT kernel.withdraw_account_deletion('prodsim-del-admin-withdraw');
SELECT tap.logout();
SELECT public.settle_verified_payment('pi_e9','succeeded',11000,'usd',true,0,NULL,'card', jsonb_build_object('mode','buy_now','listing_id','aaaaaaaa-0000-0000-0000-0000000000e9','buyer_id',tap.admin_user()::text,'seller_id',tap.seller()::text),'sweep');
UPDATE public.webhook_retries SET resolved = true WHERE rpc_name = 'settle_verified_payment' AND resolved IS NOT TRUE;
SELECT public.record_payment_refund('pi_legacy_e', 're_prodsim_2', NULL, 10500, 'dashboard');   -- the remainder refund OBJECT's amount (per-refund, not cumulative)
SELECT public.mark_transfer_reversed('tr_e7_old');
COMMIT;
SQL
run "$OUT/f2.sql" && ok "F2 drain by settlement: withdraw (D6), settle e9 (D4), resolve review (D3), full refund (D2), reversal (D5)" || bad "F2" "see $OUT/last.out"
check "F2b the open attempt is reconciled (operator confirmed no Stripe transfer -> failed) (D1)" "select (public.reconcile_payout_attempt('$OPEN', NULL))->>'state'" "failed"
R=$(rb 20260906130000_deletion_sweep_live_rail_obligations); [ -z "$(printf '%s' "$R" | grep REFUSED)" ] && ok "F3 130000 rollback now passes its gate" || bad "F3 130000" "$(printf '%s' "$R" | head -c 200)"
# F4 — export (belt and braces) and remember the facts
psql -X -q -d "$DB" -c "\copy (select * from public.payout_attempts order by claimed_at) to '$OUT/payout_attempts.csv' csv header" && \
psql -X -q -d "$DB" -c "\copy (select * from public.payment_refunds order by created_at) to '$OUT/payment_refunds.csv' csv header" && ok "F4 CSV export of the ledgers (belt and braces next to the in-transaction archive)" || bad "F4 export" "copy failed"
ATT_N=$(q "select count(*) from public.payout_attempts"); REF_N=$(q "select count(*) from public.payment_refunds"); REFUNDED_E=$(q "select amount_refunded_cents from public.payments where stripe_payment_intent_id='pi_legacy_e'")
MONEY_BEFORE=$(q "select string_agg(id::text || ':' || coalesce(stripe_transfer_id,'-') || ':' || (payout_released_at is not null)::text, ',' order by id) from public.transfers")
R=$(rb 20260906120000_payout_attempts_and_refund_monotonic); [ -z "$(printf '%s' "$R" | grep REFUSED)" ] && ok "F5 120000 rollback passes every D-gate after the drain and ARCHIVES in-transaction" || bad "F5 120000" "$(printf '%s' "$R" | head -c 300)"
check "F5b archive manifest holds the ledgers (attempts=$ATT_N refunds=$REF_N, partial-refund facts>0), not yet restored" "select n_attempts || '|' || n_refunds || '|' || (n_partial_refund_facts > 0)::text || '|' || (restored_at is null)::text from rollback_archive.manifest" "$ATT_N|$REF_N|true|true"
R=$(rb 20260906110000_settle_verified_payment); [ -z "$(printf '%s' "$R" | grep REFUSED)" ] && ok "F5c 110000 rollback passes (D3/D4 drained)" || bad "F5c 110000" "$(printf '%s' "$R" | head -c 300)"
R=$(rb 20260906100000_checkout_reservation_authority); [ -z "$(printf '%s' "$R" | grep REFUSED)" ] && ok "F5d 100000 rollback passes (110000 gone first, O1)" || bad "F5d 100000" "$(printf '%s' "$R" | head -c 300)"
check "F6 census back to production's 27|70|37|26" "$CENSUS" "27|70|37|26"
check "F7 function definitions back to the pre-upgrade hash (bodies restored verbatim)" "select '$PRE_FN' = ($FNHASH)" "t"
check "F8 money facts on transfers SURVIVE: every tr_ / payout_released_at" "select '$MONEY_BEFORE' = (select string_agg(id::text || ':' || coalesce(stripe_transfer_id,'-') || ':' || (payout_released_at is not null)::text, ',' order by id) from public.transfers)" "t"
check "F9 settled listings stay sold; promoted payments keep their status" "select (select count(*) from public.listings where id in ('aaaaaaaa-0000-0000-0000-0000000000e2','aaaaaaaa-0000-0000-0000-0000000000e3','aaaaaaaa-0000-0000-0000-0000000000e8','aaaaaaaa-0000-0000-0000-0000000000e9') and status='sold') || '|' || (select count(*) from public.payments where stripe_payment_intent_id in ('pi_inflight_e2','pi_e3','pi_e9') and status='succeeded') || '|' || (select status from public.payments where stripe_payment_intent_id='pi_legacy_e')" "4|3|refunded"
check "F10 the partial-refund COLUMN is gone from the old schema; the fact lives in the archive" "select (select count(*) from information_schema.columns where table_schema='public' and table_name='payments' and column_name='amount_refunded_cents') || '|' || (select amount_refunded_cents from rollback_archive.payments_refund_facts where stripe_payment_intent_id='pi_legacy_e')" "0|$REFUNDED_E"
act "F11-act sweep_deletion_pending (deployed machine intact)" "select (kernel.sweep_deletion_pending())->>'tombstoned'"
check "F11 the buyer is still held on BP-7 post-rollback" "select deletion_state = 'DELETION_PENDING' and deletion_block_reason like 'BP-7%' from kernel.identity_ext where identity_id = tap.buyer()" "t"
# F12 — the rollback WINDOW: old code runs against old schema
check "F12 old code works: record_transfer_payout pays E5 (a WINDOW payout with no attempt row)" "select public.record_transfer_payout('cccccccc-0000-0000-0000-0000000000e5', 'tr_post_rb')" "t"
q "select public.record_transfer_payout((select id from public.transfers where payment_id='eeeeeeee-0000-0000-0000-000000000001'), 'tr_post_rb')" >/dev/null 2>&1
check "F12b the window also produced a DUPLICATE tr_ (unique index gone): two transfers carry tr_post_rb" "select count(*) from public.transfers where stripe_transfer_id='tr_post_rb'" "2"
# F13 — re-apply: the duplicate aborts 120000 until fixed, then the archive is restored
for f in 20260906100000_checkout_reservation_authority 20260906110000_settle_verified_payment; do apply "supabase/migrations/$f.sql"; done
R=$(psql -X -q -1 -d "$DB" -v ON_ERROR_STOP=1 -f supabase/migrations/20260906120000_payout_attempts_and_refund_monotonic.sql 2>&1); case "$R" in *"duplicates"*) ok "F13 re-apply of 120000 ABORTS on the window duplicate (nothing half-applied)";; *) bad "F13 duplicate abort" "$(printf '%s' "$R" | head -c 200)";; esac
q "select set_config('app.bypass_transfer_guard','on',true); update public.transfers set stripe_transfer_id = null, payout_released_at = null where payment_id='eeeeeeee-0000-0000-0000-000000000001'" >/dev/null 2>&1
R=$(psql -X -q -1 -d "$DB" -v ON_ERROR_STOP=1 -f supabase/migrations/20260906120000_payout_attempts_and_refund_monotonic.sql 2>&1); case "$R" in *"rollback_archive restored"*) ok "F13b after the operator resolves the duplicate, 120000 re-applies and RESTORES the archive";; *) bad "F13b restore" "$(printf '%s' "$R" | grep -vE '^\s*$' | head -c 300)";; esac
case "$R" in *"OLD code during the rollback window"*"tr_post_rb"*) ok "F13c the restore REPORTS the window payout (C4: E5=tr_post_rb has no attempt row)";; *) bad "F13c C4 report" "$(printf '%s' "$R" | head -c 300)";; esac
apply supabase/migrations/20260906130000_deletion_sweep_live_rail_obligations.sql
check "F14 census 30|86|37|32 again" "$CENSUS" "30|86|37|32"
check "F14b C1: ledgers restored row-for-row from the archive (attempts, refunds)" "select (select count(*) from public.payout_attempts) || '|' || (select count(*) from public.payment_refunds)" "$ATT_N|$REF_N"
check "F14c C2: amount_refunded_cents restored from the archive and equals the refund ledger sum" "select amount_refunded_cents || '|' || case when amount_refunded_cents = (select sum(amount_cents) from public.payment_refunds r where r.payment_id = p.id) then 't' else 'f' end from public.payments p where stripe_payment_intent_id='pi_legacy_e'" "$REFUNDED_E|t"
check "F14d manifest stamped restored" "select restored_at is not null from rollback_archive.manifest" "t"
F15=$(q "select * from public.claim_payout_attempt('cccccccc-0000-0000-0000-0000000000e5', 'prodsim')" 2>&1 | grep -c ALREADY_RELEASED); [ "$F15" = "1" ] && ok "F15 the restored ledger sees the window payout on E5 -> ALREADY_RELEASED (no double pay)" || bad "F15" "$F15"
check "F16 the window payout is visible to reconciliation: tr_ on the row, no attempt row (operator matches it in Stripe by metadata.transfer_id)" "select count(*) from public.transfers t where t.stripe_transfer_id='tr_post_rb' and not exists (select 1 from public.payout_attempts a where a.transfer_id=t.id and a.stripe_transfer_id=t.stripe_transfer_id)" "1"

echo "=== SUMMARY: pass=$PASSES fail=$FAILS  (artifacts in $OUT)"
[ "$FAILS" -eq 0 ]
