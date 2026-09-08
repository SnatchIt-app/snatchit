#!/bin/bash
# =============================================================================
# scripts/sandbox/40_device_flows.sh — DB-side assertions for the simulator run.
#
# The UI is driven separately (simulator automation); this script records the
# database truth for each flow so a pass is never inferred from a screenshot.
# Sandbox-only: refuses any non-sandbox project.
#   ./scripts/sandbox/40_device_flows.sh <check> [args]
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; cd "$ROOT"
set -a; . "$HERE/sandbox.env"; set +a
[ "${TEST_REF:-}" = "ofaidukbieeekqaboscm" ] || { echo "REFUSING: not the sandbox project"; exit 3; }
q(){ psql "$TEST_DB_URL" -X -qtA -c "$1" 2>&1; }
case "${1:-}" in
  listing)   # $2 = event_name
    q "select 'listing ' || event_name || ': status=' || status || ' reserved_by=' || coalesce(reserved_by::text,'-') || ' price=' || buy_now_price from public.listings where event_name='$2' order by created_at desc limit 1";;
  payments)  # $2 = event_name — every payment row for that listing (duplicate detection)
    q "select 'rows=' || count(*) || ' distinct_pi=' || count(distinct stripe_payment_intent_id) || ' statuses=' || coalesce(string_agg(distinct status, ','),'-') || ' totals=' || coalesce(string_agg(distinct total::text, ','),'-') from public.payments p join public.listings l on l.id=p.listing_id where l.event_name='$2'";;
  fees)      # $2 = event_name — the 10/10 model as recorded server-side
    q "select 'amount=' || amount || ' buyer_fee=' || buyer_fee || ' seller_fee=' || seller_fee || ' total=' || total || ' ok=' || ((buyer_fee = amount/10) and (seller_fee = amount/10) and (total = amount + buyer_fee))::text from public.payments p join public.listings l on l.id=p.listing_id where l.event_name='$2' order by p.created_at desc limit 1";;
  transfers) # $2 = event_name
    q "select 'transfers=' || count(*) || ' statuses=' || coalesce(string_agg(t.status, ','),'-') from public.transfers t join public.listings l on l.id=t.listing_id where l.event_name='$2'";;
  deletion)  # $2 = email
    q "select 'state=' || e.deletion_state || ' reason=' || coalesce(e.deletion_block_reason,'-') from kernel.identity_ext e join auth.users u on u.id=e.identity_id where u.email='$2'";;
  obligations) # $2 = email
    q "select coalesce(string_agg(kind || ':' || ref_id, ', '), '<none>') from public.account_deletion_blockers((select id from auth.users where email='$2'))";;
  audit)     # global sanity: no live-mode row ever, no duplicate PI per listing
    q "select 'live_rows=' || (select count(*) from public.payments where stripe_livemode is true) || ' listings_with_multiple_succeeded=' || (select count(*) from (select listing_id from public.payments where status='succeeded' group by listing_id having count(*) > 1) x)";;
  *) echo "usage: $0 {listing|payments|fees|transfers|deletion|obligations|audit} [arg]"; exit 2;;
esac
