#!/usr/bin/env python3
"""pkg.py — frozen 150/151 deployment package runner (A, 2026-10-05).

NEW CODE. It follows the design documented in PR93_PRODUCTION_EXECUTION_PACKAGE_20260924.md §4-§10
(prestate STOP keys, one request per migration = file + ledger row, POST assertion, guarded rollback
with a conditional ledger delete, LOCALDB rehearsal of the identical request). The executed 147-149
scripts were not committed and are not recoverable; this is not a reconstruction of them.

Modes (env MODE):
  DRY      build the request, print its sha256 and size, write it under rehearsal/out/; no DB, no network.
  LOCALDB  run against a local rehearsal DB (env LOCALDB_NAME must contain 'rehears'), via psql -c:
           one simple-query message, i.e. one implicit transaction, like the Management API.
  PROD     production. Requires CONFIRM_REF=hqycwntpfoztoinemqns. Transport (env TRANSPORT):
             cli  (default) `supabase db query --project-ref REF --file F --output-format json`
             http POST https://api.supabase.com/v1/projects/REF/database/query, token from env
                  SUPABASE_ACCESS_TOKEN (never printed). This is the transport the 147-149 records prove.
           NOT AUTHORISED until the owner says so for the specific step.

Subcommands:
  state                          print the state.sql key=value lines
  check <expected-file>          compare state to an expected file; exit 3 on mismatch
  probe                          PROD transport proof: a read-only two-statement query (no writes)
  apply <150|151>                prestate check -> one request -> post check
  rollback <150|151> [--ledger-only]
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
MIG = {
    "150": dict(version="20260925000000", name="refund_lifecycle_state",
                file=HERE / "frozen/migrations/20260925000000_refund_lifecycle_state.sql",
                rollback=HERE / "frozen/rollbacks/20260925000000_refund_lifecycle_state_rollback.sql",
                pre=HERE / "expected/pre150.txt", post=HERE / "expected/post150.txt",
                # the ledger row may be deleted only once 150's objects are gone
                gone="to_regprocedure('public.record_refund_state(text,text,text,integer,text,text,text)') IS NULL "
                     "AND to_regclass('public.payment_refund_state') IS NULL "
                     "AND to_regclass('public.payment_refund_state_log') IS NULL"),
    "151": dict(version="20260925010000", name="release_stuck_seller_win",
                file=HERE / "frozen/migrations/20260925010000_release_stuck_seller_win.sql",
                rollback=HERE / "frozen/rollbacks/20260925010000_release_stuck_seller_win_rollback.sql",
                pre=HERE / "expected/pre151.txt", post=HERE / "expected/post151.txt",
                gone="(SELECT md5(prosrc) FROM pg_proc WHERE oid = 'ops.detect_release_stuck()'::regprocedure) "
                     "= '12ed7fc21fb4eccc3fac6e5865d75ee0'"),
}
FUNCS = {  # deploy facts from the execution records (SS:1416; P92:473)
    "stripe-webhook": dict(before_version=42, verify_jwt=False, prev_commit="5b255838"),
    "enforce-transfer-expiry": dict(before_version=41, verify_jwt=True, prev_commit="e73553d2"),
}

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
    tr = os.environ.get("TRANSPORT", "cli")
    if tr == "cli":
        with tempfile.TemporaryDirectory() as td:
            f = Path(td) / "request.sql"; f.write_text(sql)
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
    return sorted(run_sql((HERE / "sql/state.sql").read_text(), True))

def compare(expected_path, actual):
    exp = [l for l in Path(expected_path).read_text().split("\n") if l and not l.startswith("#")]
    ek = dict(l.split("=", 1) for l in exp); ak = dict(l.split("=", 1) for l in actual)
    bad = [(k, ek[k], ak.get(k, "<missing>")) for k in ek if ak.get(k) != ek[k]]
    extra = [k for k in ak if k not in ek]
    for k, e, a in bad: print(f"  MISMATCH {k}: expected {e} | actual {a}")
    for k in extra: print(f"  UNEXPECTED KEY {k}={ak[k]}")
    return not bad and not extra

def apply_request(n):
    m = MIG[n]; body = m["file"].read_text(); tag = "$pkg" + n + "$"
    if tag in body: die(2, "dollar tag collision")
    created_by = f"claude-a/owner-authorised-{n}"
    return (body.rstrip("\n") + "\n;\n"
            f"INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)\n"
            f"VALUES ('{m['version']}', '{m['name']}', ARRAY[{tag}{body}{tag}], '{created_by}');\n")

def rollback_request(n, ledger_only):
    m = MIG[n]
    delete = (f"DELETE FROM supabase_migrations.schema_migrations WHERE version = '{m['version']}' AND {m['gone']};\n")
    return delete if ledger_only else m["rollback"].read_text().rstrip("\n") + "\n" + delete

def emit_dry(label, sql):
    out = HERE / "rehearsal/out"; out.mkdir(parents=True, exist_ok=True)
    (out / f"{label}.sql").write_text(sql)
    print(f"[pkg] {label}: {len(sql.encode())} bytes sha256 {sha256_bytes(sql.encode())}")

def cmd_apply(n):
    m = MIG[n]; sql = apply_request(n)
    if mode() == "DRY": return emit_dry(f"apply_{n}", sql)
    print(f"[pkg] prestate {n} vs {m['pre'].name}")
    if not compare(m["pre"], state()): die(3, f"prestate STOP for {n}; nothing sent")
    print(f"[pkg] request sha256 {sha256_bytes(sql.encode())} ({len(sql.encode())} bytes)")
    run_sql(sql, False)
    print(f"[pkg] post assertion {n} vs {m['post'].name}")
    if not compare(m["post"], state()): die(4, f"POST assertion FAIL for {n}")
    print(f"[pkg] {n} APPLIED and verified")

def cmd_rollback(n, ledger_only):
    m = MIG[n]; sql = rollback_request(n, ledger_only)
    if mode() == "DRY": return emit_dry(f"rollback_{n}{'_ledger_only' if ledger_only else ''}", sql)
    st = state()
    if ledger_only:
        # resume case: objects already restored, ledger row still present
        ek = dict(l.split("=", 1) for l in Path(m["pre"]).read_text().split("\n") if l and not l.startswith("#"))
        ak = dict(l.split("=", 1) for l in st)
        ledger_keys = {"ledger_count", "ledger_max", "ledger_150", "ledger_151"}
        if any(ak.get(k) != v for k, v in ek.items() if k not in ledger_keys):
            die(3, "ledger-only STOP: objects are not in the pre-state")
    else:
        print(f"[pkg] rollback guard {n}: state must equal {m['post'].name}")
        if not compare(m["post"], st): die(3, f"rollback STOP for {n}; nothing sent")
    print(f"[pkg] rollback request sha256 {sha256_bytes(sql.encode())}")
    run_sql(sql, False)
    print(f"[pkg] post-rollback {n} vs {m['pre'].name}")
    if not compare(m["pre"], state()): die(4, f"post-rollback FAIL for {n}")
    print(f"[pkg] {n} ROLLED BACK and verified")

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
    elif c == "probe": print(run_sql("select 'probe=1' as line; select 'probe=2' as line;", True))
    elif c == "apply" and len(a) == 2 and a[1] in MIG: cmd_apply(a[1])
    elif c == "rollback" and len(a) >= 2 and a[1] in MIG: cmd_rollback(a[1], "--ledger-only" in a)
    elif c == "fnmanifest" and len(a) == 3: print(json.dumps(fn_manifest(a[1], a[2], os.environ.get("REPO", ".")), indent=1))
    elif c == "deploy" and len(a) >= 2: cmd_deploy(a[1], "--live" in a)
    else: die(2, __doc__)

if __name__ == "__main__":
    main(sys.argv[1:])
