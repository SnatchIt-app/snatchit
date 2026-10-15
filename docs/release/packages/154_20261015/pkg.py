#!/usr/bin/env python3
"""pkg.py — frozen 154/155/156 deployment package runner (A, 2026-10-15).

Copied from docs/release/packages/152_20261013/pkg.py (sha256 02537f62…, executed 2026-10-13). The changes:
  * MIG entries 154, 155, 156 (in order; each one's pre file is the previous one's post file), LEDGER_KEYS;
  * state() = TWO read-only requests: sql/state.sql (catalog, ledger, fixed money/listing hashes) and
    sql/state_anon.sql (counts as anon and as a signed-in non-party, under SET LOCAL ROLE); only lines
    containing '=' are kept (SET/RESET tags and the stash row are dropped);
  * per-MIG rb_post (the expected state AFTER its rollback; 154's rollback keeps listing_visibility, so its
    rb_post is not pre154), rollback_ignore (every rollback ignores the data-step keys, so 156 -> 155 -> 154
    roll back with or without the hidden rows, which 154's rollback keeps) and, for 154 only, alt_pre = rb154
    (a clean re-apply after its own rollback);
  * DATA steps `step hide` / `step unhide` (sql/hide_legacy.sql, sql/unhide_legacy.sql): prestate check ->
    one request -> post check, no ledger row;
  * PKG_EXPECTED (default 'expected') selects the expected-state directory, so the LOCALDB rehearsal runs
    against rehearsal/expected_local/ with the identical code path.

NEW CODE. It follows the design documented in PR93_PRODUCTION_EXECUTION_PACKAGE_20260924.md §4-§10
(prestate STOP keys, one request per migration = file + ledger row, POST assertion, guarded rollback
with a conditional ledger delete, LOCALDB rehearsal of the identical request). The executed 147-149
scripts were not committed and are not recoverable; this is not a reconstruction of them.

Modes (env MODE):
  DRY      build the request, print its sha256 and size, write it under rehearsal/out/; no DB, no network.
  LOCALDB  run against a local rehearsal DB (env LOCALDB_NAME must contain 'rehears'), via psql -c:
           one simple-query message, i.e. one implicit transaction, like the Management API.
  PROD     production. Requires CONFIRM_REF=hqycwntpfoztoinemqns. Transport (env TRANSPORT):
             http (default) POST https://api.supabase.com/v1/projects/REF/database/query, token from env
                  SUPABASE_ACCESS_TOKEN (never printed). The transport the 147-149 records prove (HTTP 201).
             cli  (opt-in) `supabase db query --project-ref REF --file F --output-format json`; never
                  exercised for a multi-statement write (D, F-1).
           NOT AUTHORISED until the owner says so for the specific step.

Subcommands:
  state                          print the state.sql key=value lines
  check <expected-file>          compare state to an expected file; exit 3 on mismatch
  probe                          transport proof: three read-only statements in ONE request; prints
                                 `same_txn=true` only if they ran in one transaction (a transaction-local
                                 setting survives); anything else = STOP (D, F-1)
  apply <154|155|156> [--ledger-only]
                                 prestate check -> one request -> post check. --ledger-only: resume when the
                                 migration's objects are in place but its ledger row is missing (refuses otherwise)
  rollback <154|155|156> [--ledger-only]
  step <hide|unhide>             the data step (no ledger row): prestate check -> one request -> post check
  fnmanifest <git-ref> <function>     sha256 of every file in the function's import closure
  deploy <function> [--live]     default PLAN: verify SRC_DIR against the frozen manifest and print the
                                 exact commands. --live (PROD only): before-version guard, pre-download
                                 compare, deploy, after-version check, post-download compare.
Exit codes: 0 ok, 2 usage/precondition, 3 prestate/guard STOP, 4 post-assertion FAIL, 5 transport error.
"""
import hashlib, json, os, re, subprocess, sys, tempfile, urllib.request, urllib.error
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROD_REF = "hqycwntpfoztoinemqns"
EXP = HERE / os.environ.get("PKG_EXPECTED", "expected")
# Keys the DATA step moves (hide/unhide). Every rollback ignores them: the schema rollbacks never touch
# listing_visibility rows, and 154's rollback KEEPS them (archival), so 156 -> 155 -> 154 can be rolled back
# with or without the data step having run.
DATA_KEYS = {"lv_rows", "anon_listings", "anon_bids", "nonparty_listings", "nonparty_bids"}
MIG = {
    "154": dict(version="20261015000000", name="listing_public_visibility",
                file=HERE / "frozen/migrations/20261015000000_listing_public_visibility.sql",
                rollback=HERE / "frozen/rollbacks/20261015000000_listing_public_visibility_rollback.sql",
                pre=EXP / "pre154.txt", post=EXP / "post154.txt", rb_post=EXP / "rb154.txt",
                # after its own rollback the kept (empty) listing_visibility table means the state is rb154, not
                # pre154; a clean re-apply is allowed from there (rows kept from a hide make it STOP instead)
                alt_pre=EXP / "rb154.txt",
                rollback_ignore=DATA_KEYS,
                # the ledger row may be deleted only once 154's functions are gone, both USING (true) policies
                # are back, and get_profile_trust_stats is 031's body again (production md5, read 2026-10-15)
                gone="to_regprocedure('public.listing_is_public(uuid)') IS NULL "
                     "AND to_regprocedure('public.listing_private_party(uuid)') IS NULL "
                     "AND to_regprocedure('public.guard_hidden_listing_not_live()') IS NULL "
                     "AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'listings' AND policyname = 'listings_select_all' AND qual = 'true') "
                     "AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bids' AND policyname = 'bids_select_all' AND qual = 'true') "
                     "AND md5(pg_get_functiondef('public.get_profile_trust_stats(uuid)'::regprocedure)) = '23719c73db47a2815d5102b11f4771f3'"),
    "155": dict(version="20261015000100", name="listing_duration_72h",
                file=HERE / "frozen/migrations/20261015000100_listing_duration_72h.sql",
                rollback=HERE / "frozen/rollbacks/20261015000100_listing_duration_72h_rollback.sql",
                pre=EXP / "post154.txt", post=EXP / "post155.txt", rb_post=EXP / "post154.txt",
                rollback_ignore=DATA_KEYS,
                gone="(SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'public.listings'::regclass "
                     "AND conname = 'listings_duration_hours_check') = 'CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48])))'"),
    "156": dict(version="20261015000200", name="listing_proof_owner_waiver",
                file=HERE / "frozen/migrations/20261015000200_listing_proof_owner_waiver.sql",
                rollback=HERE / "frozen/rollbacks/20261015000200_listing_proof_owner_waiver_rollback.sql",
                pre=EXP / "post155.txt", post=EXP / "post156.txt", rb_post=EXP / "post155.txt",
                rollback_ignore=DATA_KEYS,
                gone="to_regprocedure('public.guard_listing_proof_waiver()') IS NULL "
                     "AND to_regprocedure('public.current_user_is_admin()') IS NULL "
                     "AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' "
                     "AND table_name = 'listings' AND column_name IN ('proof_waived_at','proof_waived_by','proof_waiver_reason'))"),
}
# The data step: hide the 113 legacy listings (owner cleanup), and its reversal. No ledger row.
STEP = {
    "hide":   dict(file=HERE / "sql/hide_legacy.sql",   pre=EXP / "post156.txt",   post=EXP / "post_hide.txt"),
    "unhide": dict(file=HERE / "sql/unhide_legacy.sql", pre=EXP / "post_hide.txt", post=EXP / "post156.txt"),
}
FUNCS = {}  # 154-156 deploy no edge function

def die(code, msg):
    print(f"[pkg] {msg}", file=sys.stderr); sys.exit(code)

def sha256_bytes(b): return hashlib.sha256(b).hexdigest()

def mode():
    m = os.environ.get("MODE", "")
    if m not in ("DRY", "LOCALDB", "PROD"): die(2, "set MODE=DRY|LOCALDB|PROD")
    if m == "LOCALDB" and "rehears" not in os.environ.get("LOCALDB_NAME", ""):
        die(2, "LOCALDB_NAME must contain 'rehears'")
    if m == "PROD" and os.environ.get("CONFIRM_REF") != PROD_REF:
        die(2, f"PROD requires CONFIRM_REF={PROD_REF}")
    return m

def run_sql(sql, want_rows):
    """Send one request. Returns list of first-column strings when want_rows."""
    m = mode()
    if m == "DRY": die(2, "DRY mode does not touch a database")
    if m == "LOCALDB":
        r = subprocess.run(["psql", "-h", "127.0.0.1", "-U", "postgres", "-d", os.environ["LOCALDB_NAME"],
                            "-v", "ON_ERROR_STOP=1", "-At", "-c", sql], capture_output=True, text=True)
        if r.returncode: die(5, "psql error: " + r.stderr.strip()[-600:])
        return [l for l in r.stdout.split("\n") if l] if want_rows else []
    tr = os.environ.get("TRANSPORT", "http")
    if tr == "cli":
        with tempfile.TemporaryDirectory() as td:
            f = Path(td) / "request.sql"; f.write_text(sql, encoding="utf-8")
            r = subprocess.run(["supabase", "db", "query", "--project-ref", PROD_REF, "--file", str(f),
                                "--output-format", "json"], capture_output=True, text=True, cwd=td)
        if r.returncode: die(5, "cli transport error: " + (r.stdout + r.stderr).strip()[-600:])
        try: data = json.loads(r.stdout[r.stdout.index("{"):])
        except Exception: die(5, "cli transport: unparseable output")
        if data.get("_tag") == "Error": die(5, "cli transport error: " + json.dumps(data.get("error"))[:600])
        rows = data.get("rows", [])
    elif tr == "http":
        tok = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
        if not tok: die(2, "TRANSPORT=http needs SUPABASE_ACCESS_TOKEN in the environment")
        req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{PROD_REF}/database/query",
                                     data=json.dumps({"query": sql}).encode(), method="POST",
                                     headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                print(f"[pkg] http {resp.status}"); rows = json.load(resp)
        except urllib.error.HTTPError as e:
            die(5, f"http {e.code}: " + e.read().decode()[:600])
    else: die(2, "TRANSPORT must be cli or http")
    return [str(next(iter(r.values()))) for r in rows if r] if want_rows else []

def state():
    lines = []
    for f in ("sql/state.sql", "sql/state_anon.sql"):
        lines += [l for l in run_sql((HERE / f).read_text(encoding="utf-8"), True) if "=" in l]
    return sorted(lines)

def compare(expected_path, actual, ignore=frozenset()):
    exp = [l for l in Path(expected_path).read_text(encoding="utf-8").split("\n") if l and not l.startswith("#")]
    ek = dict(l.split("=", 1) for l in exp); ak = dict(l.split("=", 1) for l in actual)
    for k in ignore:
        if k in ek or k in ak: print(f"  (ignored) {k}: expected {ek.get(k, '<none>')} | actual {ak.get(k, '<missing>')}")
        ek.pop(k, None); ak.pop(k, None)
    bad = [(k, ek[k], ak.get(k, "<missing>")) for k in ek if ak.get(k) != ek[k]]
    extra = [k for k in ak if k not in ek]
    for k, e, a in bad: print(f"  MISMATCH {k}: expected {e} | actual {a}")
    for k in extra: print(f"  UNEXPECTED KEY {k}={ak[k]}")
    return not bad and not extra

LEDGER_KEYS = {"ledger_count", "ledger_max", "ledger_154", "ledger_155", "ledger_156"}

def ledger_insert(n):
    m = MIG[n]; body = m["file"].read_text(encoding="utf-8"); tag = "$pkg" + n + "$"
    if tag in body: die(2, "dollar tag collision")
    return (f"INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)\n"
            f"VALUES ('{m['version']}', '{m['name']}', ARRAY[{tag}{body}{tag}], 'claude-a/owner-authorised-{n}');\n")

def apply_request(n):
    return MIG[n]["file"].read_text(encoding="utf-8").rstrip("\n") + "\n;\n" + ledger_insert(n)

def rollback_request(n, ledger_only):
    m = MIG[n]
    delete = (f"DELETE FROM supabase_migrations.schema_migrations WHERE version = '{m['version']}' AND {m['gone']};\n")
    return delete if ledger_only else m["rollback"].read_text(encoding="utf-8").rstrip("\n") + "\n" + delete

def emit_dry(label, sql):
    out = HERE / "rehearsal/out"; out.mkdir(parents=True, exist_ok=True)
    (out / f"{label}.sql").write_text(sql, encoding="utf-8")
    print(f"[pkg] {label}: {len(sql.encode())} bytes sha256 {sha256_bytes(sql.encode())}")

def cmd_apply(n, ledger_only=False):
    m = MIG[n]; sql = ledger_insert(n) if ledger_only else apply_request(n)
    if mode() == "DRY": return emit_dry(f"apply_{n}{'_ledger_only' if ledger_only else ''}", sql)
    if ledger_only:
        ek = dict(l.split("=", 1) for l in Path(m["post"]).read_text(encoding="utf-8").split("\n") if l and not l.startswith("#"))
        ak = dict(l.split("=", 1) for l in state())
        lk = f"ledger_{n}"
        if ak.get(lk) != "absent" or any(ak.get(k) != v for k, v in ek.items() if k not in LEDGER_KEYS):
            die(3, "apply --ledger-only STOP: objects are not in the post-state, or the ledger row already exists")
        print(f"[pkg] ledger-only request sha256 {sha256_bytes(sql.encode())}")
        run_sql(sql, False)
        if not compare(m["post"], state()): die(4, f"POST assertion FAIL for {n} (ledger-only)")
        print(f"[pkg] {n} ledger row restored and verified"); return
    print(f"[pkg] prestate {n} vs {m['pre'].name}")
    st = state()
    if not compare(m["pre"], st):
        if not m.get("alt_pre"): die(3, f"prestate STOP for {n}; nothing sent")
        print(f"[pkg] prestate {n} vs {m['alt_pre'].name} (re-apply after this migration's own rollback)")
        if not compare(m["alt_pre"], st): die(3, f"prestate STOP for {n}; nothing sent")
    print(f"[pkg] request sha256 {sha256_bytes(sql.encode())} ({len(sql.encode())} bytes)")
    run_sql(sql, False)
    print(f"[pkg] post assertion {n} vs {m['post'].name}")
    if not compare(m["post"], state()): die(4, f"POST assertion FAIL for {n}")
    print(f"[pkg] {n} APPLIED and verified")

def cmd_rollback(n, ledger_only):
    m = MIG[n]; sql = rollback_request(n, ledger_only)
    if mode() == "DRY": return emit_dry(f"rollback_{n}{'_ledger_only' if ledger_only else ''}", sql)
    st = state()
    ign = m["rollback_ignore"]
    if ledger_only:
        # resume case: objects already restored, ledger row still present
        ek = dict(l.split("=", 1) for l in Path(m["rb_post"]).read_text(encoding="utf-8").split("\n") if l and not l.startswith("#"))
        ak = dict(l.split("=", 1) for l in st)
        if any(ak.get(k) != v for k, v in ek.items() if k not in LEDGER_KEYS and k not in ign):
            die(3, "ledger-only STOP: objects are not in the post-rollback state")
    else:
        print(f"[pkg] rollback guard {n}: state must equal {m['post'].name}")
        if not compare(m["post"], st, ign): die(3, f"rollback STOP for {n}; nothing sent")
    print(f"[pkg] rollback request sha256 {sha256_bytes(sql.encode())}")
    run_sql(sql, False)
    print(f"[pkg] post-rollback {n} vs {m['rb_post'].name}")
    if not compare(m["rb_post"], state(), ign): die(4, f"post-rollback FAIL for {n}")
    print(f"[pkg] {n} ROLLED BACK and verified")

def cmd_step(name):
    s = STEP[name]; sql = s["file"].read_text(encoding="utf-8")
    if mode() == "DRY": return emit_dry(f"step_{name}", sql)
    print(f"[pkg] prestate step {name} vs {s['pre'].name}")
    if not compare(s["pre"], state()): die(3, f"prestate STOP for step {name}; nothing sent")
    print(f"[pkg] step request sha256 {sha256_bytes(sql.encode())} ({len(sql.encode())} bytes)")
    run_sql(sql, False)
    print(f"[pkg] post assertion step {name} vs {s['post'].name}")
    if not compare(s["post"], state()): die(4, f"POST assertion FAIL for step {name}")
    print(f"[pkg] step {name} DONE and verified")

IMPORT_RE = re.compile(r"""(?:from|import)\s*\(?\s*['"](\.{1,2}/[^'"]+)['"]""")

def fn_manifest(ref, fn, repo):
    """Import closure of supabase/functions/<fn>/index.ts at a git ref -> {relpath: sha256}."""
    seen, todo, out = set(), [f"supabase/functions/{fn}/index.ts"], {}
    while todo:
        p = os.path.normpath(todo.pop())
        if p in seen: continue
        seen.add(p)
        r = subprocess.run(["git", "-C", repo, "show", f"{ref}:{p}"], capture_output=True)
        if r.returncode: die(2, f"missing {p} at {ref}")
        out[p[len("supabase/functions/"):]] = sha256_bytes(r.stdout)
        for imp in IMPORT_RE.findall(r.stdout.decode()):
            todo.append(os.path.join(os.path.dirname(p), imp))
    return dict(sorted(out.items()))

def dir_manifest(root):
    """{relpath under supabase/functions/: sha256} for every file below root."""
    out = {}
    for f in Path(root).rglob("*"):
        if f.is_file():
            s = str(f); i = s.rfind("supabase/functions/")
            if i >= 0: out[s[i + len("supabase/functions/"):]] = sha256_bytes(f.read_bytes())
    return dict(sorted(out.items()))

def diff_manifest(label, want, got):
    bad = [k for k in want if got.get(k) != want[k]] + [k for k in got if k not in want]
    print(f"[pkg] {label}: {len(want)} expected, {len(got)} found, {len(bad)} mismatches")
    for k in bad: print(f"  {k}: expected {want.get(k, '<none>')[:12]} got {got.get(k, '<none>')[:12]}")
    return not bad

def mgmt_fn(slug):
    """Function metadata (version, verify_jwt, ezbr) via the Management API; needs SUPABASE_ACCESS_TOKEN at execution."""
    tok = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
    if not tok: die(2, "--live needs SUPABASE_ACCESS_TOKEN for the version/verify_jwt reads")
    req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{PROD_REF}/functions/{slug}",
                                 headers={"Authorization": "Bearer " + tok})
    with urllib.request.urlopen(req, timeout=60) as r: d = json.load(r)
    return {k: d.get(k) for k in ("version", "verify_jwt", "ezbr_sha256", "status", "updated_at")}

def download(slug, td):
    r = subprocess.run(["supabase", "functions", "download", slug, "--project-ref", PROD_REF, "--use-api",
                        "--workdir", td], capture_output=True, text=True)
    if r.returncode: die(5, "download failed: " + r.stderr.strip()[-400:])
    return dir_manifest(td)

def cmd_deploy(fn, live):
    if fn not in FUNCS: die(2, "function must be one of " + ", ".join(FUNCS))
    frozen = json.loads((HERE / "frozen/functions_manifest.json").read_text())[fn]
    src = os.environ.get("SRC_DIR", "")
    if not src: die(2, "set SRC_DIR to a detached checkout of the frozen source")
    got = {k: v for k, v in dir_manifest(Path(src) / "supabase/functions").items() if k in frozen["files"]}
    if not diff_manifest(f"SRC_DIR vs frozen {fn}", frozen["files"], got): die(3, "source STOP")
    f = FUNCS[fn]
    cmd = ["supabase", "functions", "deploy", fn, "--project-ref", PROD_REF, "--use-api", "--workdir", src]
    if not f["verify_jwt"]: cmd.append("--no-verify-jwt")
    if not live:
        print("[pkg] PLAN (nothing sent). Live sequence:")
        print(f"  1. before: version == {f['before_version']}, verify_jwt == {f['verify_jwt']}")
        print(f"  2. pre-download == previous manifest (source {f['prev_commit']}), {len(frozen['previous_files'])} files")
        print("  3. " + " ".join(cmd))
        print(f"  4. after: version == {f['before_version'] + 1}, verify_jwt == {f['verify_jwt']}")
        print(f"  5. post-download == frozen manifest, {len(frozen['files'])} files")
        return
    if mode() != "PROD": die(2, "--live requires MODE=PROD and CONFIRM_REF")
    b = mgmt_fn(fn); print(f"[pkg] before {b}")
    if b["version"] != f["before_version"] or bool(b["verify_jwt"]) != f["verify_jwt"]: die(3, "before-version STOP")
    with tempfile.TemporaryDirectory() as td:
        if not diff_manifest("pre-download vs previous", frozen["previous_files"], download(fn, td)): die(3, "pre-download STOP")
    r = subprocess.run(cmd, capture_output=True, text=True)
    print(f"[pkg] deploy rc {r.returncode}")
    if r.returncode: die(5, r.stderr.strip()[-600:])
    a = mgmt_fn(fn); print(f"[pkg] after {a}")
    if a["version"] != f["before_version"] + 1 or bool(a["verify_jwt"]) != f["verify_jwt"]: die(4, "after-version FAIL")
    with tempfile.TemporaryDirectory() as td:
        if not diff_manifest("post-download vs frozen", frozen["files"], download(fn, td)): die(4, "post-download FAIL")
    print(f"[pkg] {fn} DEPLOYED and verified")

def main(a):
    if not a: die(2, __doc__)
    c = a[0]
    if c == "state": print("\n".join(state()))
    elif c == "check": sys.exit(0 if compare(a[1], state()) else 3)
    elif c == "probe":
        rows = run_sql("select set_config('pkg.probe', now()::text, true) as line; select pg_sleep(0.05)::text as line; "
                       "select 'same_txn=' || (current_setting('pkg.probe', true) = now()::text)::text as line;", True)
        print(rows)
        if not rows or rows[-1] != "same_txn=true": die(3, "probe STOP: the transport did not run one request as one transaction")
        print("[pkg] probe PASS: one request = one transaction")
    elif c == "apply" and len(a) >= 2 and a[1] in MIG: cmd_apply(a[1], "--ledger-only" in a)
    elif c == "rollback" and len(a) >= 2 and a[1] in MIG: cmd_rollback(a[1], "--ledger-only" in a)
    elif c == "step" and len(a) == 2 and a[1] in STEP: cmd_step(a[1])
    elif c == "fnmanifest" and len(a) == 3: print(json.dumps(fn_manifest(a[1], a[2], os.environ.get("REPO", ".")), indent=1))
    elif c == "deploy" and len(a) >= 2: cmd_deploy(a[1], "--live" in a)
    else: die(2, __doc__)

if __name__ == "__main__":
    main(sys.argv[1:])
