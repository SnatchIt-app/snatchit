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
# Every Location the package's rules emit is absolute on
# https://app.snatchitapp.com/. A matrix row whose first Location is anything
# else (relative, "//host", "/\host", another host) fails, even if following
# it would end in the right place. Relative Locations are resolved with
# python3's urllib.parse.urljoin (RFC 3986) to follow and report them; pass
# and fail always compare the raw header, because a browser also reads "\" as
# "/" and urljoin does not.
#
# VERIFY_LEGACY_ORIGIN=http://127.0.0.1:<port> replaces the legacy origin.
# It exists only to exercise this script against a local emulator; leave it
# unset for the real check.
#
# Exit status: 0 when every check matches, 1 on any mismatch, 2 on bad usage
# or a missing tool.
#
# The MATRIX and HOSTILE lists below are also read by redirects.test.mjs,
# which runs every entry through Vercel's own rule compiler. If you change
# vercel.json, change the matrix too, or the test fails.
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
    -h|--help) awk 'NR > 1 && /^set -u$/ { exit } NR > 1 { print }' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$MODE" in
  redirect|current) ;;
  *) echo "--expect must be redirect or current" >&2; exit 2 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found (resolves relative Locations)" >&2; exit 2; }

# Rows: <legacy path and query>  <final URL path and query on the app host>
#       <hops: 308 responses until the request leaves the legacy host; always
#              1, because every rule's Location is absolute>
#       <dest: ok = the app host answers 200, or a 30x to its /login gate;
#              any = status is only reported (fake ids, unknown paths)>
# No row contains "//": Vercel merges those itself first (see HOSTILE).
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
# trailing slash. Legacy-only rules take one optional "/" ({/}?) and map it
# away. Shared routes and everything else fall to the catch-all with the slash
# kept; the app host then answers 308 to the same path without it, which the
# destination check follows.
/my-listings/?x=1                          /account/listings?x=1                      1 ok
/settings/                                 /account/settings                          1 ok
/settings/legal/                           /account/settings                          1 ok
/bid/abc-123/                              /listing/abc-123                           1 any
/login/                                    /login/                                    1 ok
/payout-return/?client=app                 /payout-return/?client=app                 1 ok
/zz-legacy-check/                          /zz-legacy-check/                          1 any
MATRIX
}

# Request paths that would turn a relative Location into another host
# ("//evil.example" is a scheme-relative URL). No hop may name a host other
# than the legacy host or the app host. The one relative Location allowed is
# Vercel's own duplicate-slash merge, which runs before any rule ("//x/"
# answers 308 "/x/", seen on the live legacy host 2026-10-21) and stays on the
# legacy host. No query on these rows: the merge re-encodes it.
hostile() {
  cat <<'HOSTILE'
//evil.example/
//evil.example
/%2F%2Fevil.example
/\evil.example
///evil.example/
/%2F%2Fevil.example/
/\evil.example/
/%5Cevil.example/
/.//evil.example/
HOSTILE
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
trap 'rm -f "$HDR" "$HDR.dest"' EXIT

STATUS=""
LOCATION_RAW=""
LOCATION=""
# fetch URL: one GET, no redirect following, path sent exactly as given.
# Sets STATUS, LOCATION_RAW (the Location header as sent) and LOCATION (that
# header resolved against URL with urllib.parse.urljoin; empty without one).
fetch() {
  : > "$HDR"
  STATUS="$(curl -sS --path-as-is -o /dev/null -D "$HDR" -w '%{http_code}' --max-time 20 "$1" 2>/dev/null)" || STATUS="000"
  LOCATION_RAW="$(grep -i '^location:' "$HDR" | tail -n 1 | sed -e 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//' | tr -d '\r')"
  LOCATION=""
  if [ -n "$LOCATION_RAW" ]; then
    LOCATION="$(python3 -I -c 'import sys
from urllib.parse import urljoin
sys.stdout.write(urljoin(sys.argv[1], sys.argv[2]))' "$1" "$LOCATION_RAW")" || LOCATION=""
  fi
}

# on_app VALUE: true when VALUE is an absolute URL on the app host.
on_app() {
  case "$1" in
    "$APP"/*) return 0 ;;
  esac
  return 1
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
    if [ "$STATUS" = "200" ] && [ -z "$LOCATION_RAW" ]; then
      pass "$path -> 200 (legacy app still served)"
    else
      fail "$path -> $STATUS ${LOCATION_RAW:-no Location} (want 200, no Location)"
    fi
    continue
  fi
  url="$LEGACY$path"
  n=0
  first=""
  while :; do
    fetch "$url"
    n=$((n + 1))
    [ "$n" = 1 ] && first="$LOCATION_RAW"
    [ "$STATUS" = "308" ] || break
    case "$LOCATION" in
      "$LEGACY"/*) if [ "$n" -lt "$MAX_HOPS" ]; then url="$LOCATION"; continue; fi ;;
    esac
    break
  done
  if ! on_app "$first"; then
    fail "$path -> first Location ${first:-none} is not absolute on $APP/ (chain: $STATUS x$n ${LOCATION:-no Location})"
  elif [ "$STATUS" = "308" ] && [ "$LOCATION_RAW" = "$want" ] && [ "$n" = "$hops" ]; then
    pass "$path -> 308 x$n $LOCATION_RAW"
  else
    fail "$path -> $STATUS x$n ${LOCATION_RAW:-no Location} (want 308 x$hops $want)"
  fi
done <<EOF
$(matrix)
EOF

echo
echo "== hostile paths (no hop may name a host other than the legacy host or $APP)"
HROWS=0
while read -r path; do
  case "$path" in ''|'#'*) continue ;; esac
  HROWS=$((HROWS + 1))
  url="$LEGACY$path"
  n=0
  bad=""
  chain=""
  while :; do
    fetch "$url"
    n=$((n + 1))
    chain="$chain $STATUS${LOCATION_RAW:+ $LOCATION_RAW}"
    case "$STATUS" in
      301|302|303|307|308) ;;
      *) break ;;
    esac
    if on_app "$LOCATION_RAW"; then break; fi
    # Anything else must be Vercel's slash merge of this request's path.
    reqpath="${url#"$LEGACY"}"
    merged="$(printf '%s' "$reqpath" | sed -e 's#//*#/#g')"
    if [ "$merged" = "$reqpath" ] || [ "$LOCATION_RAW" != "$merged" ]; then
      bad="Location ${LOCATION_RAW:-none} is neither absolute on $APP/ nor the slash merge of $reqpath"
      break
    fi
    if [ "$n" -ge "$MAX_HOPS" ]; then bad="more than $MAX_HOPS hops"; break; fi
    url="$LOCATION"
  done
  if [ -n "$bad" ]; then
    fail "$path ->$chain ($bad)"
  elif [ "$MODE" = "current" ]; then
    if [ "$STATUS" = "200" ] && [ -z "$LOCATION_RAW" ]; then
      pass "$path ->$chain (legacy app, never left the legacy host)"
    else
      fail "$path ->$chain (want 200 on the legacy host)"
    fi
  elif [ "$STATUS" = "308" ] && on_app "$LOCATION_RAW"; then
    pass "$path ->$chain"
  else
    fail "$path ->$chain (want 308 to $APP/...)"
  fi
done <<EOF
$(hostile)
EOF

if [ "$DEST_CHECKS" = 1 ]; then
  echo
  echo "== app host destinations (independent of the legacy deploy)"
  # Each distinct destination once. A destination with a trailing slash
  # (shared route or catch-all) must first be answered by a 308 to the same
  # URL without it; that one hop is followed and reported.
  matrix | awk '$0 !~ /^#/ && NF >= 4 { print $2, $4 }' | sort -u | while read -r final dest; do
    note=""
    fetch "$APP$final"
    p="${final%%\?*}"
    q="${final#"$p"}"
    bare="$p"
    case "$p" in /?*/) bare="${p%/}" ;; esac
    bare="$bare$q"
    if [ "$bare" != "$final" ]; then
      if [ "$STATUS" = "308" ] && [ "$LOCATION" = "$APP$bare" ]; then
        note=" (after 308 $LOCATION_RAW: the app host strips the slash)"
        fetch "$APP$bare"
      elif [ "$dest" != "any" ]; then
        printf 'FAIL  %s -> %s %s (want 308 to %s)\n' "$final" "$STATUS" "$LOCATION_RAW" "$APP$bare"
        continue
      fi
    fi
    if [ "$dest" = "any" ]; then
      printf 'INFO  %s -> %s %s%s\n' "$final" "$STATUS" "$LOCATION" "$note"
      continue
    fi
    case "$STATUS" in
      200) printf 'PASS  %s -> 200%s\n' "$final" "$note" ;;
      301|302|303|307|308)
        case "$LOCATION" in
          "$APP"/login|"$APP"/login\?*) printf 'PASS  %s -> %s %s (sign-in gate)%s\n' "$final" "$STATUS" "$LOCATION" "$note" ;;
          *) printf 'FAIL  %s -> %s %s (want 200 or a redirect to %s/login)%s\n' "$final" "$STATUS" "$LOCATION" "$APP" "$note" ;;
        esac ;;
      *) printf 'FAIL  %s -> %s (want 200 or a redirect to %s/login)%s\n' "$final" "$STATUS" "$APP" "$note" ;;
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
  case "$STATUS $LOCATION_RAW" in
    "302 https://vercel.com/sso-api?"*) pass "$url -> 302 https://vercel.com/sso-api?..." ;;
    *) fail "$url -> $STATUS ${LOCATION_RAW%%\?*} (want 302 https://vercel.com/sso-api)" ;;
  esac
done <<EOF
$(sso_hosts)
EOF

echo
echo "matrix rows: $ROWS   hostile rows: $HROWS   pass: $PASS   fail: $FAIL"
[ "$FAIL" = 0 ] || exit 1
exit 0
