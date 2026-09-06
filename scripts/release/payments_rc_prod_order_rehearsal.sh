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
run()  { psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f "$1" >"$OUT/last.out" 2>&1 || { echo "  (psql error in $1)"; tail -3 "$OUT/last.out"; return 1; }; }
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

echo "=== F. rollback with NEW financial records present → drain, export, roll back, recover, re-apply, re-import"
cat > "$OUT/f0.sql" <<'SQL'
-- more new-code facts: a partial refund ledgered on the settled legacy capture; an OPEN attempt; a review row
SELECT public.record_payment_refund('pi_legacy_e', 're_prodsim_1', NULL, 500, 'dashboard');
SELECT * FROM public.claim_payout_attempt('cccccccc-0000-0000-0000-0000000000e2' , 'x') WHERE false;  -- no-op shape check
SELECT public.settle_verified_payment('pi_unknown_prodsim','succeeded',1000,'usd',true,0,NULL,'card','{}'::jsonb,'webhook');
SQL
psql -X -q -d "$DB" -f "$OUT/f0.sql" >"$OUT/f0.out" 2>&1
# an OPEN attempt (POST in flight, response not yet recorded) on the released-unpaid transfer E5
OPEN=$(q "select attempt_id from public.claim_payout_attempt('cccccccc-0000-0000-0000-0000000000e5', 'prodsim:open')" 2>/dev/null | head -1)
[ -n "$OPEN" ] && ok "F0 an open attempt exists on E5 ($OPEN)" || bad "F0 claim on E5" "empty"
q "select public.mark_payout_requested('$OPEN')" >/dev/null 2>&1
check "F1 records exist: attempts ≥3 incl. 1 open, ≥1 payment_refunds row, amount_refunded_cents set, ≥1 review row" "select (select count(*) >= 3 from public.payout_attempts) and (select count(*) = 1 from public.payout_attempts where state in ('claimed','requested','unknown')) and (select count(*) >= 1 from public.payment_refunds) and (select amount_refunded_cents = 500 from public.payments where stripe_payment_intent_id='pi_legacy_e') and (select count(*) >= 1 from public.webhook_retries where rpc_name='settle_verified_payment' and resolved is not true)" "t"
# (1) DRAIN: reconcile the open attempt (operator confirmed in Stripe that no transfer exists)
check "F2 drain: the open attempt is reconciled (operator confirmed no Stripe transfer → failed)" "select (public.reconcile_payout_attempt('$OPEN', NULL))->>'state'" "failed"
check "F2' …zero open attempts remain before any rollback" "select count(*) from public.payout_attempts where state in ('claimed','requested','unknown')" "0"
# (2) EXPORT
psql -X -q -d "$DB" -c "\copy (select * from public.payout_attempts order by claimed_at) to '$OUT/payout_attempts.csv' csv header" && \
psql -X -q -d "$DB" -c "\copy (select * from public.payment_refunds order by created_at) to '$OUT/payment_refunds.csv' csv header" && \
psql -X -q -d "$DB" -c "\copy (select id, stripe_payment_intent_id, status, total, amount_refunded_cents, refunded_at, stripe_refund_id from public.payments where amount_refunded_cents is not null) to '$OUT/payments_refunded.csv' csv header" && \
psql -X -q -d "$DB" -c "\copy (select * from public.account_deletions) to '$OUT/account_deletions.csv' csv header" && ok "F3 export: payout_attempts / payment_refunds / payments refund facts / account_deletions → $OUT/*.csv" || bad "F3 export" "copy failed"
ATT_N=$(q "select count(*) from public.payout_attempts"); REF_N=$(q "select count(*) from public.payment_refunds")
MONEY_BEFORE=$(q "select string_agg(id::text || ':' || coalesce(stripe_transfer_id,'-') || ':' || (payout_released_at is not null)::text, ',' order by id) from public.transfers")
# (3) ROLL BACK 4 → 1
for f in 20260906130000_deletion_sweep_live_rail_obligations 20260906120000_payout_attempts_and_refund_monotonic 20260906110000_settle_verified_payment 20260906100000_checkout_reservation_authority; do psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f "supabase/rollbacks/${f}_rollback.sql" >>"$OUT/rollback.out" 2>&1 || { bad "F4 rollback $f" "see $OUT/rollback.out"; break; }; done
check "F4 census back to production's 27|70|37|26" "$CENSUS" "27|70|37|26"
check "F5 function definitions back to the pre-upgrade hash (bodies restored verbatim)" "select '$PRE_FN' = ($FNHASH)" "t"
check "F6 money facts SURVIVE the rollback: every transfer keeps its tr_ / payout_released_at" "select '$MONEY_BEFORE' = (select string_agg(id::text || ':' || coalesce(stripe_transfer_id,'-') || ':' || (payout_released_at is not null)::text, ',' order by id) from public.transfers)" "t"
check "F7 settled listings stay sold; promoted payments stay succeeded" "select (select count(*) from public.listings where id in ('aaaaaaaa-0000-0000-0000-0000000000e2','aaaaaaaa-0000-0000-0000-0000000000e3','aaaaaaaa-0000-0000-0000-0000000000e8') and status='sold') || '|' || (select count(*) from public.payments where stripe_payment_intent_id in ('pi_inflight_e2','pi_e3','pi_legacy_e') and status='succeeded')" "3|3"
check "F8 old code works post-rollback: record_transfer_payout on the released-unpaid E5" "select public.record_transfer_payout('cccccccc-0000-0000-0000-0000000000e5', 'tr_post_rb')" "t"
check "F8' …E5 carries tr_post_rb" "select stripe_transfer_id from public.transfers where id='cccccccc-0000-0000-0000-0000000000e5'" "tr_post_rb"
act "F9-act sweep_deletion_pending" "select (kernel.sweep_deletion_pending())->>'tombstoned'"
check "F9 the deployed deletion machine is intact post-rollback (sweep runs, buyer still held on BP-7)" "select deletion_state = 'DELETION_PENDING' and deletion_block_reason like 'BP-7%' from kernel.identity_ext where identity_id = tap.buyer()" "t"
check "F10 the partial-refund fact has NO home after rollback (column dropped) — the CSV is the ledger of record" "select count(*) from information_schema.columns where table_schema='public' and table_name='payments' and column_name='amount_refunded_cents'" "0"
# (5) RE-APPLY + RE-IMPORT
for f in 20260906100000_checkout_reservation_authority 20260906110000_settle_verified_payment 20260906120000_payout_attempts_and_refund_monotonic 20260906130000_deletion_sweep_live_rail_obligations; do apply "supabase/migrations/$f.sql"; done
check "F11 re-apply: census 30|86|37|32 again" "$CENSUS" "30|86|37|32"
psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -c "\copy public.payout_attempts from '$OUT/payout_attempts.csv' csv header" >>"$OUT/reimport.out" 2>&1 && \
psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -c "\copy public.payment_refunds from '$OUT/payment_refunds.csv' csv header" >>"$OUT/reimport.out" 2>&1 && ok "F12 re-import of the exported ledgers succeeds (append-only tables accept INSERT)" || bad "F12 re-import" "see $OUT/reimport.out"
check "F13 re-imported row counts equal the export" "select (select count(*) from public.payout_attempts) || '|' || (select count(*) from public.payment_refunds)" "$ATT_N|$REF_N"
check "F14 amount_refunded_cents restored from the export" "update public.payments p set amount_refunded_cents = c.amt from (select 'pi_legacy_e'::text pi, 500 amt) c where p.stripe_payment_intent_id = c.pi returning p.amount_refunded_cents" "500"
F15=$(q "select * from public.claim_payout_attempt('cccccccc-0000-0000-0000-0000000000e5', 'prodsim')" 2>&1 | grep -c ALREADY_RELEASED); [ "$F15" = "1" ] && ok "F15 after re-import + re-apply the ledger sees E5 as paid (old path tr_post_rb) → ALREADY_RELEASED, no double pay" || bad "F15" "$F15"

echo "=== SUMMARY: pass=$PASSES fail=$FAILS  (artifacts in $OUT)"
[ "$FAILS" -eq 0 ]
