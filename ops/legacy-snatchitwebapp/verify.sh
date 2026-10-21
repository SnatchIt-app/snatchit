#!/usr/bin/env bash
# verify.sh: curl matrix for the snatchitwebapp.vercel.app redirect package.
#
# GET requests only, to public URLs. It changes nothing, so it is safe to run
# against the live host at any time: before the deploy, after it, and after a
# rollback.
#
# Usage:
#   ./verify.sh                    expect the redirect package (after the deploy)
#   ./verify.sh --expect current   expect today's legacy Expo app: every row 200,
#                                  no Location (before the deploy, after a rollback)
#   ./verify.sh --no-dest          skip the app-host destination checks
#
# VERIFY_LEGACY_ORIGIN=http://127.0.0.1:<port> replaces the legacy origin.
# It exists only to exercise this script against a local emulator; leave it
# unset for the real check.
#
# Exit status: 0 when every check matches, 1 on any mismatch, 2 on bad usage.
#
# The MATRIX below is also read by redirects.test.mjs, which runs every row
# through Vercel's own rule compiler. If you change vercel.json, change the
# matrix too, or the test fails.
set -u

LEGACY="${VERIFY_LEGACY_ORIGIN:-https://snatchitwebapp.vercel.app}"
APP="https://app.snatchitapp.com"
MODE="redirect"
DEST_CHECKS=1
MAX_HOPS=3

while [ $# -gt 0 ]; do
  case "$1" in
    --expect)
      [ $# -ge 2 ] || { echo "usage: $0 [--expect redirect|current] [--no-dest]" >&2; exit 2; }
      MODE="$2"; shift 2 ;;
    --no-dest) DEST_CHECKS=0; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$MODE" in
  redirect|current) ;;
  *) echo "--expect must be redirect or current" >&2; exit 2 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 2; }

# Rows: <legacy path and query>  <final URL path and query on the app host>
#       <hops: 308 responses until the request leaves the legacy host>
#       <dest: ok = the app host answers 200, or a 30x to its /login gate;
#              any = status is only reported (fake ids, unknown paths)>
matrix() {
  cat <<'MATRIX'
# root
/                                          /                                          1 ok
/?utm_source=legacy&x=1                    /?utm_source=legacy&x=1                    1 ok
# legacy-only routes, mapped to their app-host equivalents
/home                                      /                                          1 ok
/explore                                   /browse                                    1 ok
/explore?q=jazz                            /browse?q=jazz                             1 ok
/create                                    /sell                                      1 ok
/bids                                      /account                                   1 ok
/profile                                   /account                                   1 ok
/my-listings                               /account/listings                          1 ok
/bid/abc-123?x=1                           /listing/abc-123?x=1                       1 any
/settings                                  /account/settings                          1 ok
/settings/edit-profile                     /account/profile                           1 ok
/settings/notifications                    /account/notifications                     1 ok
/settings/payout-setup                     /account/settings                          1 ok
/settings/preferences                      /account/settings                          1 ok
/settings/legal                            /account/settings                          1 ok
/settings/privacy                          /account/settings                          1 ok
/settings/support                          /account/settings                          1 ok
# shared routes, same path, query kept, nothing added
/login                                     /login                                     1 ok
/login?next=%2Faccount%2Fsettings          /login?next=%2Faccount%2Fsettings          1 ok
/signup                                    /signup                                    1 ok
/reset-password                            /reset-password                            1 ok
/payout-return                             /payout-return                             1 ok
/payout-return?client=app&x=1              /payout-return?client=app&x=1              1 ok
/payout-refresh                            /payout-refresh                            1 ok
/listing/abc-123?ref=t                     /listing/abc-123?ref=t                     1 any
/checkout/abc-123                          /checkout/abc-123                          1 any
/transfer/send/abc-123                     /transfer/send/abc-123                     1 any
/transfer/receive/abc-123                  /transfer/receive/abc-123                  1 any
# catch-all, same path
/browse?q=x&sort=new                       /browse?q=x&sort=new                       1 ok
/browse?q=a%20b&next=%2Faccount&a=1&a=2    /browse?q=a%20b&next=%2Faccount&a=1&a=2    1 ok
/robots.txt                                /robots.txt                                1 any
/zz-legacy-check/a/b?x=1                   /zz-legacy-check/a/b?x=1                   1 any
# trailing slash: one 308 on the legacy host strips it, then the rule above
/my-listings/?x=1                          /account/listings?x=1                      2 ok
/settings/legal/                           /account/settings                          2 ok
/login/                                    /login                                     2 ok
/zz-legacy-check/                          /zz-legacy-check                           2 any
MATRIX
}

# Hostnames of this project that must stay behind Vercel Deployment
# Protection (302 to vercel.com/sso-api) before and after the deploy. The
# last three are the immutable URLs of the three May 2026 deployments,
# including dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ (86cv71xrz).
sso_hosts() {
  cat <<'SSO'
https://snatchitwebapp-gnvprod-5449s-projects.vercel.app/payout-return
https://snatchitwebapp-gnvprod-5449-gnvprod-5449s-projects.vercel.app/payout-return
https://snatchitwebapp-86cv71xrz-gnvprod-5449s-projects.vercel.app/settings/legal
https://snatchitwebapp-nlltsidc5-gnvprod-5449s-projects.vercel.app/settings/legal
https://snatchitwebapp-c7n1l4vfc-gnvprod-5449s-projects.vercel.app/settings/legal
SSO
}

HDR="$(mktemp -t legacy-verify.XXXXXX)" || exit 2
trap 'rm -f "$HDR"' EXIT

STATUS=""
LOCATION=""
# fetch URL: one GET, no redirect following. Sets STATUS and LOCATION
# (the raw Location header, made absolute when it is relative).
fetch() {
  : > "$HDR"
  STATUS="$(curl -sS -o /dev/null -D "$HDR" -w '%{http_code}' --max-time 20 "$1" 2>/dev/null)" || STATUS="000"
  LOCATION="$(grep -i '^location:' "$HDR" | tail -n 1 | sed -e 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//' | tr -d '\r')"
  case "$LOCATION" in
    /*) LOCATION="$(printf '%s' "$1" | sed -E 's#^(https?://[^/]+).*#\1#')$LOCATION" ;;
  esac
}

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }

echo "legacy host: $LEGACY   mode: $MODE   destination checks: $([ "$DEST_CHECKS" = 1 ] && echo on || echo off)"
echo

echo "== legacy host"
ROWS=0
while read -r path final hops dest extra; do
  case "$path" in ''|'#'*) continue ;; esac
  ROWS=$((ROWS + 1))
  if [ -n "${extra:-}" ] || [ -z "${dest:-}" ]; then fail "matrix row malformed: $path"; continue; fi
  want="$APP$final"
  if [ "$MODE" = "current" ]; then
    fetch "$LEGACY$path"
    if [ "$STATUS" = "200" ] && [ -z "$LOCATION" ]; then
      pass "$path -> 200 (legacy app still served)"
    else
      fail "$path -> $STATUS ${LOCATION:-no Location} (want 200, no Location)"
    fi
    continue
  fi
  url="$LEGACY$path"
  n=0
  ok=1
  while :; do
    fetch "$url"
    n=$((n + 1))
    if [ "$STATUS" != "308" ]; then ok=0; break; fi
    case "$LOCATION" in
      "$LEGACY"/*) if [ "$n" -lt "$MAX_HOPS" ]; then url="$LOCATION"; continue; fi ;;
    esac
    break
  done
  if [ "$ok" = 1 ] && [ "$LOCATION" = "$want" ] && [ "$n" = "$hops" ]; then
    pass "$path -> 308 x$n $LOCATION"
  else
    fail "$path -> $STATUS x$n ${LOCATION:-no Location} (want 308 x$hops $want)"
  fi
done <<EOF
$(matrix)
EOF

if [ "$DEST_CHECKS" = 1 ]; then
  echo
  echo "== app host destinations (independent of the legacy deploy)"
  # Each distinct destination once.
  matrix | awk '$0 !~ /^#/ && NF >= 4 { print $2, $4 }' | sort -u | while read -r final dest; do
    fetch "$APP$final"
    if [ "$dest" = "any" ]; then
      printf 'INFO  %s -> %s %s\n' "$final" "$STATUS" "$LOCATION"
      continue
    fi
    case "$STATUS" in
      200) printf 'PASS  %s -> 200\n' "$final" ;;
      301|302|303|307|308)
        case "$LOCATION" in
          "$APP"/login|"$APP"/login\?*) printf 'PASS  %s -> %s %s (sign-in gate)\n' "$final" "$STATUS" "$LOCATION" ;;
          *) printf 'FAIL  %s -> %s %s (want 200 or a redirect to %s/login)\n' "$final" "$STATUS" "$LOCATION" "$APP" ;;
        esac ;;
      *) printf 'FAIL  %s -> %s (want 200 or a redirect to %s/login)\n' "$final" "$STATUS" "$APP" ;;
    esac
  done > "$HDR.dest"
  cat "$HDR.dest"
  PASS=$((PASS + $(grep -c '^PASS' "$HDR.dest")))
  FAIL=$((FAIL + $(grep -c '^FAIL' "$HDR.dest")))
  rm -f "$HDR.dest"
fi

echo
echo "== deployment protection on the other hostnames (must stay 302 to vercel.com/sso-api)"
while read -r url; do
  [ -n "$url" ] || continue
  fetch "$url"
  case "$STATUS $LOCATION" in
    "302 https://vercel.com/sso-api?"*) pass "$url -> 302 https://vercel.com/sso-api?..." ;;
    *) fail "$url -> $STATUS ${LOCATION%%\?*} (want 302 https://vercel.com/sso-api)" ;;
  esac
done <<EOF
$(sso_hosts)
EOF

echo
echo "rows: $ROWS   pass: $PASS   fail: $FAIL"
[ "$FAIL" = 0 ] || exit 1
exit 0
