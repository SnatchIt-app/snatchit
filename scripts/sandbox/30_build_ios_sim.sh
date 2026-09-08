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
# CocoaPods (invoked directly below AND again inside `expo run:ios`) aborts with
# "Unicode Normalization not appropriate for ASCII-8BIT" unless the whole process
# tree has a UTF-8 locale.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
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

# Preflight: Xcode must actually be able to target a simulator. Xcode 26.x ships
# the iOS SDK but NOT a simulator runtime; if the matching runtime is missing,
# `xcodebuild` reports "Found no destinations for the scheme" and no amount of
# -destination tinkering helps. Detect it here with a precise remedy.
if ! xcodebuild -workspace ios/SnatchIt.xcworkspace -scheme SnatchIt -showdestinations 2>/dev/null | grep -q "platform:iOS Simulator"; then
  if [ -d ios ]; then
    echo "BLOCKED: Xcode cannot target any iOS Simulator."
    echo "  Installed simulator runtimes: $(xcrun simctl list runtimes 2>/dev/null | grep -ci ios) (simctl can boot them, xcodebuild cannot build for them)"
    echo "  Xcode SDK: $(xcodebuild -showsdks 2>/dev/null | grep -m1 'iphonesimulator' | tr -s ' ')"
    echo "  Remedy (free, ~9 GB, needs ~20 GB free disk):"
    echo "    xcodebuild -downloadPlatform iOS      # or Xcode > Settings > Components > iOS Simulator runtime"
    echo "  Current free disk: $(df -h / | tail -1 | awk '{print $4}')"
    exit 4
  fi
fi

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
  ( cd ios && pod install >/dev/null )
fi
echo "building (this takes several minutes on a cold cache)…"
npx expo run:ios --device "$UDID" --no-bundler 2>&1 | tail -20
