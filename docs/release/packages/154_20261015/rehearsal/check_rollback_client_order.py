#!/usr/bin/env python3
"""check_rollback_client_order.py — the 155/156 rollbacks state the client order they need (A, 2026-10-15).

Written for the compat-release review finding (third re-freeze): the 156 rollback header undersold what it breaks on
the web (web #108 selects proof_waived_at on every listing read), and 155 had no client order for the 72 h option.
Read-only: it reads files and git objects, never a database.

  H  each rollback header (supabase/ copy and frozen/ copy) carries its CLIENT ORDER steps in this order, names the
     client surfaces it breaks, and the superseded text is gone; the two copies are byte-identical.
  B  the SQL body (every line that is not a `--` comment) equals the one at BASE_REF: the fix is text only.
  R  README: the Rollbacks rows for 156/155 state the same order; the frozen-file table (blob, md5, bytes), the
     Requests table (rollback bytes and sha256 prefixes), frozen.sha256 and the Runner line (pkg.py sha256) match the
     files; every request hash in the
     LOCALDB rehearsal log is a DRY hash, and the three rollback requests were sent.
  C  the client facts the header text relies on still hold at the pinned commits: web #108 068f054e, RC9 4f7ad2b4,
     RC9 N1 7fc72a08.

usage: python3 -I check_rollback_client_order.py [ROOT]
  ROOT defaults to this repo's root. A negative control passes a mutated copy of supabase/rollbacks/ and the package
  (same relative layout); git objects are always read from this repo.
Exit 0 = every check passes; 1 = at least one failure (each printed).
"""
import hashlib, os, re, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[5]
ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else REPO
PKG_REL = "docs/release/packages/154_20261015"
BASE_REF = "a8e713d2"  # the second re-freeze: rollback bodies as rehearsed there
# Pinned client commits; the CHK_*_REF overrides exist only for negative controls (point them at a commit where the
# fact does not hold and the C checks must fail).
WEB108 = os.environ.get("CHK_WEB_REF", "068f054e")
RC9 = os.environ.get("CHK_RC9_REF", "4f7ad2b4")
N1 = os.environ.get("CHK_N1_REF", "7fc72a08")
RB = {
    "156": "rollbacks/20261015000200_listing_proof_owner_waiver_rollback.sql",
    "155": "rollbacks/20261015000100_listing_duration_72h_rollback.sql",
    "154": "rollbacks/20261015000000_listing_public_visibility_rollback.sql",
}
MIGS = [
    "migrations/20261015000000_listing_public_visibility.sql",
    "migrations/20261015000100_listing_duration_72h.sql",
    "migrations/20261015000200_listing_proof_owner_waiver.sql",
]
HEADER = {
    "156": {
        "order": ["1. Clear every recorded waiver",
                  "2. Deploy web WITHOUT #108's proof_waived_at selects",
                  "3. Only then run this rollback"],
        "names": ["068f054e", "LISTING_COLUMNS", "42703", "/browse", "/listing/[id]", "/checkout/[id]",
                  "saved listings", "/api/public/events", "sitemap", "SELLER_LISTING_COLUMNS does not",
                  "RC9", "listingSummary.ts", "PlaceBidScreen", "cannot bid or pay"],
        "gone": ["(F must ship the matching revert)"],
    },
    "155": {
        "order": ["1. Deploy web WITHOUT the 72 h option",
                  "2. End or migrate every 72 h listing",
                  "3. Only then run this rollback"],
        "names": ["#107", "a2540576", "#108", "LISTING_DURATION_HOURS", "23514", "RC9", "DURATION_OPTIONS",
                  "still send ends_at"],
        "gone": ["get a check violation on create until they drop the option"],
    },
}
README_ROW = {
    "156": ["**Client order:** (1) clear every recorded waiver",
            "(2) deploy web without #108's `proof_waived_at` selects",
            "(3) only then run this rollback"],
    "155": ["**Client order:** (1) deploy web without the 72 h option",
            "(2) end or migrate every 72 h listing",
            "(3) only then run this rollback"],
}

fails = []
def check(ok, label):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok: fails.append(label)

def git_show(ref, path):
    r = subprocess.run(["git", "-C", str(REPO), "show", f"{ref}:{path}"], capture_output=True)
    if r.returncode != 0:
        fails.append(f"git show {ref}:{path}"); print(f"FAIL git show {ref}:{path}"); return ""
    return r.stdout.decode()

def in_order(text, steps):
    pos = [text.find(s) for s in steps]
    return all(p >= 0 for p in pos) and pos == sorted(pos)

def body(text):
    return [l for l in text.splitlines() if not l.lstrip().startswith("--")]

def blob(b):
    return hashlib.sha1(b"blob %d\0" % len(b) + b).hexdigest()

# ---- H + B: headers and bodies
for n in ("156", "155"):
    sup = (ROOT / "supabase" / RB[n]).read_bytes()
    frz = (ROOT / PKG_REL / "frozen" / RB[n]).read_bytes()
    check(sup == frz, f"H{n} supabase/ and frozen/ copies are byte-identical")
    t = sup.decode()
    head = "\n".join(l for l in t.splitlines() if l.startswith("--"))
    check(in_order(head, HEADER[n]["order"]), f"H{n} header carries the CLIENT ORDER steps 1-2-3 in order")
    for s in HEADER[n]["names"]:
        check(s in head, f"H{n} header names {s!r}")
    for s in HEADER[n]["gone"]:
        check(s not in t, f"H{n} superseded text gone: {s!r}")
    check(body(t) == body(git_show(BASE_REF, "supabase/" + RB[n])), f"B{n} SQL body unchanged from {BASE_REF} (text-only fix)")

# ---- R: README, frozen table, requests, frozen.sha256, rehearsal log
pkg = ROOT / PKG_REL
readme = (pkg / "README.md").read_text()
sect = readme.split("## Rollbacks", 1)[1].split("\n## ", 1)[0] if "## Rollbacks" in readme else ""
for n in ("156", "155"):
    row = next((l for l in sect.splitlines() if l.startswith(f"| {n} |")), "")
    check(in_order(row, README_ROW[n]), f"R{n} README Rollbacks row states the client order (1)-(2)-(3)")
for rel in MIGS + list(RB.values()):
    b = (pkg / "frozen" / rel).read_bytes()
    short = rel.split("/")[0] + "/" + rel.split("/")[1][:15]
    row = next((l for l in readme.splitlines() if l.startswith("| `" + short)), "")
    want = f"`{blob(b)[:8]}` | `{hashlib.md5(b).hexdigest()}` | {len(b):,} |"
    check(want in row, f"R frozen table row for {rel} = blob/md5/bytes {want}")
sums = {}
for l in (pkg / "frozen.sha256").read_text().splitlines():
    h, p = l.split(None, 1); sums[p.strip()] = h
for rel in MIGS + list(RB.values()):
    check(sums.get(rel) == hashlib.sha256((pkg / "frozen" / rel).read_bytes()).hexdigest(), f"R frozen.sha256 {rel}")
check(sorted(sums) == sorted(MIGS + list(RB.values())), "R frozen.sha256 lists exactly the six frozen files")
pkg_sha = hashlib.sha256((pkg / "pkg.py").read_bytes()).hexdigest()
check(f"**Runner:** `pkg.py`, sha256 `{pkg_sha}`" in readme, f"R README Runner line = pkg.py sha256 {pkg_sha[:8]}")
out = {p.stem: p.read_bytes() for p in (pkg / "rehearsal" / "out").glob("*.sql")}
dry = {k: hashlib.sha256(v).hexdigest() for k, v in out.items()}
rrow = next((l for l in readme.splitlines() if l.startswith("| rollback 156 / 155 / 154 |")), "")
want = (f"| {len(out['rollback_156']):,} / {len(out['rollback_155']):,} / {len(out['rollback_154']):,} | "
        f"`{dry['rollback_156'][:8]}…` / `{dry['rollback_155'][:8]}…` / `{dry['rollback_154'][:8]}…` |")
check(want in rrow, f"R README Requests rollback row = DRY bytes/sha256 {want}")
for k in ("rollback_156", "rollback_155", "rollback_154"):
    frozen_rb = (pkg / "frozen" / RB[k[-3:]]).read_bytes()
    check(frozen_rb in out[k], f"R DRY {k} carries the frozen rollback bytes")
log = (pkg / "rehearsal" / "run_local_20261015.log").read_text()
sent = re.findall(r"request sha256 ([0-9a-f]{64})", log)
check(bool(sent) and all(h in dry.values() for h in sent), f"R every request hash in the rehearsal log ({len(sent)}) is a DRY hash")
for k in ("rollback_156", "rollback_155", "rollback_154"):
    check(dry[k] in sent, f"R the rehearsal sent the current {k} request")
check("== DONE: 0 unexpected exit code(s)" in log, "R rehearsal log: 0 unexpected exit codes")

# ---- C: the client facts the text relies on
def const(src, name):
    m = re.search(name + r"\s*=\s*(?:\n\s*)?(?://[^\n]*\n\s*)*[\"'\[]([^\"'\]]*)", src)
    return m.group(1) if m else None
lst = git_show(WEB108, "web/src/lib/listings.ts")
cols = const(lst, "export const LISTING_COLUMNS")
check(cols is not None and "proof_waived_at" in cols.split(", "), "C web #108 LISTING_COLUMNS selects proof_waived_at")
check("throw new Error(`listings query failed" in lst and "throw new Error(`listing query failed" in lst,
      "C web #108 getActiveListings and getListing throw on a query error")
sel = const(git_show(WEB108, "web/src/lib/seller-listings.ts"), "export const SELLER_LISTING_COLUMNS")
# Not vacuous: the capture must be the whole list (it starts at id and ends at created_at, with proof_status inside).
check(sel is not None and sel.startswith("id, seller_id") and sel.endswith(", created_at") and "proof_status" in sel
      and "proof_waived_at" not in sel, "C web #108 SELLER_LISTING_COLUMNS (whole list captured) does not select proof_waived_at")
check("listing:listings(${LISTING_COLUMNS})" in git_show(WEB108, "web/src/lib/favorites.ts"), "C web #108 saved listings embed LISTING_COLUMNS")
sm = git_show(WEB108, "web/src/app/sitemap.ts")
check("getActiveListings" in sm and "} catch {" in sm, "C web #108 sitemap catches the listings error (degrades to static)")
ev = git_show(WEB108, "web/src/app/api/public/events/route.ts")
check("getActiveListings" in ev and "status: 500" in ev, "C web #108 /api/public/events answers 500 on the error")
cl = git_show(WEB108, "web/src/lib/create-listing.ts")
check("return !error && data === true;" in cl, "C web #108 admin check fails closed (current_user_is_admin missing -> not admin)")
check("...waiver," in cl and "let waiver:" in cl and "ends_at: endsAt.toISOString()," in cl,
      "C web #108 create spreads waiver keys only when waiving, and sends ends_at itself")
dur = const(git_show(WEB108, "web/src/lib/listing-durations.ts"), "export const LISTING_DURATION_HOURS")
check(dur is not None and "72" in [x.strip() for x in dur.split(",")], "C web #107/#108 LISTING_DURATION_HOURS offers 72")
for ref in (RC9, N1):
    d = const(git_show(ref, "src/lib/sell/durations.ts"), "export const DURATION_OPTIONS: readonly DurationHours\\[\\]")
    check(d is not None and "72" in [x.strip() for x in d.split(",")], f"C {ref} DURATION_OPTIONS offers 72")
    s = const(git_show(ref, "src/lib/checkout/listingSummary.ts"), "export const LISTING_SUMMARY_COLUMNS")
    check(s is not None and "proof_waived_at" in s, f"C {ref} checkout LISTING_SUMMARY_COLUMNS selects proof_waived_at")
    pb = git_show(ref, "src/screens/PlaceBidScreen.tsx")
    check(re.search(r"\.select\('[^']*\bproof_waived_at\b[^']*'\)", pb) is not None, f"C {ref} PlaceBidScreen selects proof_waived_at")
    cs = git_show(ref, "src/screens/CreateListingScreen.tsx")
    check("ends_at:" in cs and "endsAt.toISOString()" in cs, f"C {ref} CreateListingScreen sends ends_at itself")

print(f"== {len(fails)} failure(s)")
sys.exit(1 if fails else 0)
