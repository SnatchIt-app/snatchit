#!/bin/bash
# =============================================================================
# scripts/sandbox/30_build_ios_sim.sh — build + install the SANDBOX-ONLY iOS app
# on a booted Simulator, with every EXPO_PUBLIC_* value taken from the
# git-ignored scripts/sandbox/sandbox.env. Client identifiers are therefore
# never committed, and the production build configuration is never touched.
#
#   ./scripts/sandbox/30_build_ios_sim.sh [--device "iPhone 17 Pro"] [--clean]
#
# Refuses to run if the resolved pair is not (sandbox Supabase + sandbox Stripe).
# The app itself carries the same guard (src/config/envGuard.ts) and shows a
# blocking screen if a mismatched bundle ever reaches a device.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; cd "$ROOT"
DEVICE="iPhone 17 Pro"; CLEAN=0
while [ $# -gt 0 ]; do case "$1" in --device) DEVICE="$2"; shift;; --clean) CLEAN=1;; *) echo "unknown arg $1"; exit 2;; esac; shift; done
[ -f "$HERE/sandbox.env" ] || { echo "missing $HERE/sandbox.env"; exit 2; }
set -a; . "$HERE/sandbox.env"; set +a

SANDBOX_REF=ofaidukbieeekqaboscm; PROD_REF=hqycwntpfoztoinemqns
[ "${TEST_REF:-}" = "$SANDBOX_REF" ] || { echo "REFUSING: TEST_REF is not the sandbox project"; exit 3; }
export EXPO_PUBLIC_APP_ENV=sandbox
export EXPO_PUBLIC_SUPABASE_URL="https://$SANDBOX_REF.supabase.co"
export EXPO_PUBLIC_SUPABASE_ANON_KEY="${TEST_ANON_KEY:?TEST_ANON_KEY missing}"
export EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY="${EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY:?sandbox publishable key missing}"
export EXPO_PUBLIC_SENTRY_DSN=""
export SENTRY_DISABLE_AUTO_UPLOAD=true
case "$EXPO_PUBLIC_SUPABASE_URL" in *"$PROD_REF"*) echo "REFUSING: production ref in the Supabase URL"; exit 3;; esac
case "$EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY" in pk_test_51T6Fb1*) ;; *) echo "REFUSING: publishable key is not the sandbox account's test key"; exit 3;; esac
case "$EXPO_PUBLIC_SUPABASE_ANON_KEY" in *"$PROD_REF"*) echo "REFUSING: anon key is not the sandbox project's"; exit 3;; esac
node scripts/ci/assert-env-pairing.mjs >/dev/null || { echo "REFUSING: eas.json pairing check failed"; exit 3; }
echo "sandbox pair verified: $EXPO_PUBLIC_SUPABASE_URL + pk_test (acct 51T6Fb1)"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
name='$DEVICE'
for rt,ds in d.items():
    for x in ds:
        if x['name']==name: print(x['udid']); raise SystemExit
raise SystemExit('device not found: '+name)")
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
echo "simulator: $DEVICE ($UDID)"

[ "$CLEAN" = "1" ] && rm -rf ios
if [ ! -f ios/Podfile ]; then
  echo "prebuilding native iOS project…"
  npx expo prebuild --platform ios --no-install >/dev/null
  ( cd ios && LANG=en_US.UTF-8 pod install >/dev/null )
fi
echo "building (this takes several minutes on a cold cache)…"
npx expo run:ios --device "$UDID" --no-bundler 2>&1 | tail -20
