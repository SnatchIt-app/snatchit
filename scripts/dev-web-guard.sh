#!/usr/bin/env bash
# scripts/dev-web-guard.sh — pre-launch gate for the LOCAL web rendering workflow.
#
# WHY THIS EXISTS: on 2026-09-24 the Expo dev server was started twice from
# /Users/josetascon/snatchit, the main checkout, whose .env and .env.development
# name the PRODUCTION Supabase project. No completed bundle and no successful
# page load were observed, but "not observed" is not "could not happen" — the
# only honest fix is to make the wrong directory and the wrong configuration
# impossible to launch, rather than to argue about impact afterwards.
#
# Complements src/config/envGuard.ts, which fails CLOSED at runtime inside the
# app. This one fails FAST, before Metro starts, so nothing is ever compiled
# against production in the first place.
#
# It only ever READS configuration. It never writes or modifies any env file.
#
# Exit 0 = safe to launch. Any non-zero = do not launch.
set -euo pipefail

WORKTREE='/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-refund'
SANDBOX_REF='ofaidukbieeekqaboscm'
SANDBOX_HOST="https://${SANDBOX_REF}.supabase.co"
PROD_REF='hqycwntpfoztoinemqns'
SANDBOX_ACCT_FRAGMENT='51T6Fb1'   # matches src/config/envGuard.ts
WANT_APP_ENV='sandbox'

fail() { printf '\n  REFUSED — %s\n\n' "$1" >&2; exit 1; }

# 1. The actual process working directory, not the configured one.
[ "$PWD" = "$WORKTREE" ] || fail "working directory is $PWD, not $WORKTREE"
top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ "$top" = "$WORKTREE" ] || fail "git toplevel is '${top:-none}', not $WORKTREE"

# 2. Expo loads .env and .env.<mode> as well as .env.local. The near-miss came
#    from exactly those files in another checkout, so only .env.local may exist.
for stray in .env .env.development .env.production .env.development.local .env.production.local; do
  [ -e "$stray" ] && fail "$stray exists here; only .env.local is allowed for local rendering"
done
[ -f .env.local ] || fail ".env.local is missing — nothing would configure the sandbox"

# 3. An already-exported variable WINS over .env.local (dotenv does not
#    override), so an inherited production value would silently take effect.
for v in EXPO_PUBLIC_SUPABASE_URL EXPO_PUBLIC_SUPABASE_ANON_KEY \
         EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY EXPO_PUBLIC_APP_ENV \
         SUPABASE_URL NEXT_PUBLIC_SUPABASE_URL; do
  if [ -n "${!v:-}" ]; then
    fail "$v is already exported in this environment and would override .env.local"
  fi
done

# 4. Read the effective values from .env.local WITHOUT sourcing it.
val() { sed -n "s/^[[:space:]]*$1=//p" .env.local | tail -1 | tr -d '"'"'"'\r'; }
url="$(val EXPO_PUBLIC_SUPABASE_URL)"
anon="$(val EXPO_PUBLIC_SUPABASE_ANON_KEY)"
pk="$(val EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY)"
appenv="$(val EXPO_PUBLIC_APP_ENV)"

grep -q "$PROD_REF" .env.local && fail ".env.local mentions the production project ref"
[ "$url" = "$SANDBOX_HOST" ] || fail "Supabase URL is '${url:-unset}', not $SANDBOX_HOST"
[ "$appenv" = "$WANT_APP_ENV" ] || fail "EXPO_PUBLIC_APP_ENV is '${appenv:-unset}', not $WANT_APP_ENV"
case "$pk" in
  pk_test_*) : ;;
  *) fail "Stripe publishable key is not a pk_test_ key" ;;
esac
case "$pk" in
  *"$SANDBOX_ACCT_FRAGMENT"*) : ;;
  *) fail "Stripe test key does not belong to the sandbox Stripe account" ;;
esac

# 5. The anon key carries its own project ref; a mismatched key must not pass.
ref="$(printf %s "$anon" | cut -d. -f2 \
      | tr '_-' '/+' | base64 -D 2>/dev/null || true)"
case "$ref" in
  *"\"ref\":\"$SANDBOX_REF\""*) : ;;
  *"$PROD_REF"*) fail "the anon key belongs to the PRODUCTION project" ;;
  *) fail "could not confirm the anon key belongs to $SANDBOX_REF" ;;
esac

printf '  dev-web-guard OK  dir=%s  host=%s  app_env=%s  stripe=%s…\n' \
  "$PWD" "$url" "$appenv" "${pk:0:11}"
