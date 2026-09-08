#!/bin/bash
# =============================================================================
# scripts/release/reconcile_pending_intents.sh — one-shot / daily reconciliation
# of `payments` rows still PENDING older than 2 h against Stripe (dry-run by
# default). Prints settle_verified_payment(...) statements; executes them only
# with --apply. Needs: psql access to the target DB (PG* env), `stripe` CLI
# logged in (owner), `jq`.
#   ./reconcile_pending_intents.sh <dbname> [--apply] [--older-than '2 hours']
# Refuses --apply against a database whose name does not contain 'rehears' or
# 'sandbox' unless RECONCILE_ALLOW_PROD=1 (owner decision, never the default).
# =============================================================================
set -euo pipefail
DB="${1:?usage: $0 <dbname> [--apply] [--older-than '2 hours']}"; shift || true
APPLY=0; OLDER="2 hours"
while [ $# -gt 0 ]; do case "$1" in --apply) APPLY=1;; --older-than) OLDER="$2"; shift;; *) echo "unknown arg $1"; exit 2;; esac; shift; done
if [ "$APPLY" = 1 ]; then case "$DB" in *rehears*|*sandbox*) ;; *) [ "${RECONCILE_ALLOW_PROD:-0}" = 1 ] || { echo "refusing --apply on '$DB' (set RECONCILE_ALLOW_PROD=1 to override — owner only)"; exit 3; };; esac; fi
command -v stripe >/dev/null || { echo "stripe CLI not installed"; exit 4; }
command -v jq >/dev/null || { echo "jq not installed"; exit 4; }
ROWS=$(psql -X -qtA -d "$DB" -v ON_ERROR_STOP=1 -c "select id || '|' || stripe_payment_intent_id || '|' || total || '|' || coalesce(stripe_livemode::text,'null') from public.payments where status = 'pending' and stripe_payment_intent_id is not null and created_at < now() - interval '$OLDER' order by created_at")
[ -z "$ROWS" ] && { echo "no pending rows older than $OLDER"; exit 0; }
OUT="$(mktemp -t reconcile_pending).sql"; : > "$OUT"; n=0; c=0; s=0; o=0
while IFS='|' read -r pid pi total live; do
  n=$((n+1))
  json=$(stripe payment_intents retrieve "$pi" --expand latest_charge --expand latest_charge.refunds 2>/dev/null || echo '{}')
  st=$(printf '%s' "$json" | jq -r '.status // "unknown"'); amt=$(printf '%s' "$json" | jq -r '.amount_received // .amount // 0'); cur=$(printf '%s' "$json" | jq -r '.currency // "usd"'); lm=$(printf '%s' "$json" | jq -r '.livemode // false'); ref=$(printf '%s' "$json" | jq -r '.latest_charge.amount_refunded // 0'); rid=$(printf '%s' "$json" | jq -r '.latest_charge.refunds.data[0].id // empty'); pm=$(printf '%s' "$json" | jq -r '.payment_method_types[0] // "card"'); md=$(printf '%s' "$json" | jq -c '.metadata // {}')
  case "$st" in
    canceled)  c=$((c+1)); printf "select outcome from public.settle_verified_payment('%s','canceled',%s,'%s',%s,%s,%s,'%s','%s'::jsonb,'reconcile'); -- payment %s\n" "$pi" "$amt" "$cur" "$lm" "$ref" "${rid:+'$rid'}${rid:-NULL}" "$pm" "$md" "$pid" >> "$OUT";;
    succeeded) s=$((s+1)); printf "select outcome from public.settle_verified_payment('%s','succeeded',%s,'%s',%s,%s,%s,'%s','%s'::jsonb,'reconcile'); -- payment %s  ** LOST SUCCESS EVENT **\n" "$pi" "$amt" "$cur" "$lm" "$ref" "${rid:+'$rid'}${rid:-NULL}" "$pm" "$md" "$pid" >> "$OUT";;
    *)         o=$((o+1)); echo "-- $pi status=$st (left pending)" >> "$OUT";;
  esac
done <<< "$ROWS"
echo "pending rows: $n  canceled: $c  succeeded(lost event): $s  other: $o"; echo "statements: $OUT"; cat "$OUT"
if [ "$APPLY" = 1 ]; then psql -X -d "$DB" -v ON_ERROR_STOP=1 -f "$OUT"; echo "applied"; else echo "(dry run — pass --apply to execute)"; fi
