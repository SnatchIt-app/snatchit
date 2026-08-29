#!/usr/bin/env python3
"""
registry_plan_parity.py — PROPOSED (AGENT F) — close the S-25 object-set blind spot.

The precedence gate's four-surface parity covers dependency EDGES only. S-25 proved
the object-set hole: a function scheduled in plan §8's `085` row but absent from the
registry's `085` scope (or vice versa) trips nothing. This checker gives OBJECT-SET
parity a mechanical witness, in the gate's own style: one new parseable fenced block,
fail-closed exits, embedded negative fixtures, and positive controls so a vacuous
parser cannot pass.

THE DATA-SOURCE DECISION (and why heuristics alone were rejected): plan §8 cells and
registry scope strings are free prose. A parser that "extracts what it can" and
compares the two extractions is vacuous — both sides under-extract identically and
everything passes. Instead, a NEW machine-readable fenced block is the closed world:

    ```package-objects            (in docs/architecture/_governance/PACKAGE_OBJECT_PARITY_SPEC.md)
    # PKG|OBJECT|KIND             package PKG creates OBJECT of KIND
    # PKG|NONE|-                  package PKG creates no parity-tracked objects (084/089-style)
    # ALIAS|physical|contract     a ratified §20.13 name pair — either form witnesses the other
    # MENTION-OK|token            token appears in prose but is NOT a Phase-2 object (stoplist)
    085|kernel.mark_refund_state|function
    ...
    ```

Both prose surfaces are then checked AGAINST the block, never against each other:

  O0  the block is well-formed and closed-world: every package 076–091 appears
      (objects or an explicit NONE row), no duplicate object, schema-qualified names,
      known kinds, well-formed ALIAS/MENTION-OK rows
  O1  declared → plan: every declared object is detectable in ITS package's §8 slice
      (alias-aware, bare-name-aware, slash-compression-aware). Catches: an object the
      registry family ratified that no plan row schedules (the S-24 shape), and a
      wrong-package declaration whose true package slice never mentions it
  O2  declared → registry: every declared TABLE/VIEW is detectable in its package's
      registry JSON entry (scope + *_added + name). In STRONG mode (every registry
      entry carries an "objects" array) the check upgrades to exact per-package set
      equality over tables AND functions — the full S-25 shape
  O3  plan extraction, closed world: every object-shaped token extracted from §8
      Tables/Functions/Triggers cells must be declared SOMEWHERE in the block, or be
      an ALIAS form or MENTION-OK. Catches: a phantom object invented in the plan
      (the Mutation-A shape) — it is declared nowhere and fails immediately
  O4  registry extraction, closed world: every schema-qualified token in a registry
      entry's scope/*_added fields must be declared somewhere or MENTION-OK.
      Catches: a registry object no package's closed world admits (the "dispute
      table that exists in no package" shape)
  O5  positive controls (anti-vacuity, run on the REAL corpus every run, not only in
      --selftest): the extractor must find at least MIN_PLAN_FUNCS function tokens in
      §8 and MIN_REG_QUALIFIED qualified tokens in the registry JSON, and the named
      SENTINELS (kernel.mark_refund_state in plan-085 and registry-085,
      venue.finalize_primary_order in plan-085 NOT plan-082's Functions cell,
      kernel.issue_ticket_atoms in plan-083) must be individually extracted. Any
      miss is exit 2: the parser has gone vacuous and the gate MUST NOT be trusted
      to pass.

Deliberately NOT claimed (honest residuals — see FINDINGS):
  - substring detection cannot read negation: a slice saying "X is NO LONGER
    authored here" still *mentions* X, so a wrong-package declaration into that
    slice passes O1. STRONG mode closes this for the registry side; the plan side
    keeps it as a stated blind spot
  - O3's closed world is only as strict as the MENTION-OK stoplist is short; every
    MENTION-OK row is a hole a reviewer must be able to defend
  - grants, RLS policies, seeds and pg_cron schedules are out of scope for v1

Exit 0 = parity holds. Exit 1 = a violation. Exit 2 = the checker could not run or
its own extractor failed a positive control — fail closed, same as the gate.
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOV  = "docs/architecture/_governance"
SPEC = f"{GOV}/PACKAGE_OBJECT_PARITY_SPEC.md"          # the closed world (NEW doc)
PLAN = "docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md"
PREG = "docs/architecture/PHASE_2_PACKAGE_REGISTRY.md"

PACKAGES = [f"{n:03d}" for n in range(76, 92)]          # 076–091, the ratified band
SCHEMAS  = ("kernel", "catalog", "venue", "market", "notify", "public", "storage")
KINDS    = {"table", "function", "view", "type", "trigger", "bucket", "role", "seed"}
QUAL_RE  = re.compile(r"\b(?:%s)\.[a-z][a-z0-9_]*\b" % "|".join(SCHEMAS))
# bare object-shaped tokens inside backticks in Functions cells: verb_noun shapes.
BARE_RE  = re.compile(r"`([a-z][a-z0-9_]*_[a-z0-9_]+)(?:\([^)]*\))?`")
# slash-compressed families: provision_/rotate_/revoke_signing_key
SLASH_RE = re.compile(r"\b((?:[a-z]+_/)+)([a-z][a-z0-9_]*)\b")
# tokens the CODE refuses to treat as objects (structural, not corpus): SQL/param noise
CODE_STOP = re.compile(r"^(p|v)_|^(search_path|security_definer|not_valid|on_conflict"
                       r"|if_not_exists|row_level|for_each_row)$")

MIN_PLAN_FUNCS    = 100   # §8 really schedules ~150 routines; below 100 = parser broke
MIN_REG_QUALIFIED = 40    # registry JSON names ~90 qualified objects; below 40 = broke
SENTINELS = [  # (surface, package, object) — each must be EXTRACTED, or exit 2
    ("plan", "085", "kernel.mark_refund_state"),        # the S-24/S-25 pair itself
    ("plan", "085", "venue.finalize_primary_order"),    # the C111 move
    ("plan", "083", "kernel.issue_ticket_atoms"),       # the C114 move
    ("reg",  "085", "kernel.mark_refund_state"),        # S-25's registry half
    ("reg",  "085", "kernel.payment_native"),
]

def read(rel):
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p): return None
    with open(p, encoding="utf-8") as f: return f.read()

def fenced(text, tag):
    m = re.search(r"```" + re.escape(tag) + r"\n(.*?)```", text or "", re.S)
    return m.group(1) if m else None

def expand_slashes(text):
    """provision_/rotate_/revoke_signing_key -> the three full names, appended so a
    plain substring/word search sees them."""
    out = []
    for m in SLASH_RE.finditer(text):
        prefixes = [p for p in m.group(1).split("/") if p]
        last = m.group(2)
        stem = last.split("_", 1)[1] if "_" in last else last
        out.append(last)
        out.extend(p + stem for p in prefixes)
    return text + ("\n<<expanded: " + " ".join(out) + ">>" if out else "")

# ── the closed world ────────────────────────────────────────────────────────
def parse_spec(text):
    """PKG|OBJECT|KIND  ·  PKG|NONE|-  ·  ALIAS|a|b  ·  MENTION-OK|token"""
    block = fenced(text, "package-objects")
    if block is None: raise ValueError("no ```package-objects fenced block")
    rows, aliases, mention_ok = [], [], set()
    for n, line in enumerate(block.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"): continue
        f = [c.strip() for c in line.split("|")]
        if f[0] == "ALIAS":
            if len(f) != 3 or not all(f[1:]):
                raise ValueError(f"package-objects line {n}: ALIAS needs exactly ALIAS|name|name")
            aliases.append((f[1], f[2])); continue
        if f[0] == "MENTION-OK":
            if len(f) != 2 or not f[1]:
                raise ValueError(f"package-objects line {n}: MENTION-OK needs exactly MENTION-OK|token")
            mention_ok.add(f[1]); continue
        if len(f) != 3:
            raise ValueError(f"package-objects line {n}: expected 3 fields PKG|OBJECT|KIND, got {len(f)}")
        pkg, obj, kind = f
        rows.append(dict(pkg=pkg, obj=obj, kind=kind, line=n))
    if not rows: raise ValueError("package-objects block declares nothing")
    return rows, aliases, mention_ok

def check_O0(rows, aliases, err):
    seen = set()
    declared_pkgs = set()
    for r in rows:
        declared_pkgs.add(r["pkg"])
        if r["pkg"] not in PACKAGES:
            err(f"O0: line {r['line']}: package {r['pkg']!r} is outside the ratified band 076–091. "
                f"A new package is a registry amendment first, a parity row second.")
        if r["obj"] == "NONE":
            if r["kind"] != "-":
                err(f"O0: line {r['line']}: a NONE row's kind must be '-'")
            continue
        key = (r["pkg"], r["obj"])
        if key in seen:
            err(f"O0: package {r['pkg']} declares {r['obj']} twice (line {r['line']}) — a duplicate "
                f"row hides a rename that kept the old name. Delete one, or map it as ALIAS.")
        seen.add(key)
        if r["kind"] not in KINDS:
            err(f"O0: line {r['line']}: unknown kind {r['kind']!r} (allowed: {sorted(KINDS)})")
        if "." not in r["obj"] and r["kind"] not in ("role", "bucket", "seed"):
            err(f"O0: line {r['line']}: object {r['obj']!r} is not schema-qualified. Qualify it, "
                f"or the same bare name in two schemas becomes one witness for both.")
        others = [q for (q, o) in seen if o == r["obj"] and q != r["pkg"]]
        if others:
            err(f"O0: {r['obj']} is declared in package {r['pkg']} AND {','.join(others)} — one "
                f"object, one creating package. If a later package replaces a stub, that is a "
                f"dependency edge (C110/C118), not a second declaration.")
    for p in PACKAGES:
        if p not in declared_pkgs:
            err(f"O0: package {p} is ABSENT from the closed world. Every package in the band gets "
                f"rows or an explicit '{p}|NONE|-' — an absent package is where the next S-25 hides.")
    for a, b in aliases:
        if "." not in a or "." not in b:
            err(f"O0: ALIAS pair {a!r}/{b!r} must be schema-qualified on both sides (RPC §20.13).")

def alias_forms(name, aliases):
    forms = {name}
    for a, b in aliases:
        if name == a: forms.add(b)
        if name == b: forms.add(a)
    return forms

def detectable(name, text, aliases):
    for form in alias_forms(name, aliases):
        if re.search(r"\b" + re.escape(form) + r"\b", text): return True
        bare = form.split(".", 1)[1] if "." in form else form
        if re.search(r"\b" + re.escape(bare) + r"\b", text): return True
    return False

# ── surface slicing ─────────────────────────────────────────────────────────
def plan_slices(plan_text):
    """{pkg: (full §8 section text, extraction text = Tables/Functions/Triggers cells)}."""
    i = plan_text.find("## 8.")
    if i < 0: raise ValueError(f"{PLAN}: no '## 8.' heading — §8 is the surface this check exists for")
    s8 = plan_text[i:]
    parts = re.split(r"^### `(\d{3})_", s8, flags=re.M)
    out = {}
    for j in range(1, len(parts) - 1, 2):
        pkg, body = parts[j], parts[j + 1]
        # §8 field labels VARY: "**Functions**", "**Functions — the money kernel**",
        # "**Functions (`R2B`/`C111`, defect `V2`)**". Anchoring on the exact label
        # under-extracts silently — the O5 sentinel control caught exactly that on the
        # real corpus (kernel.mark_refund_state lives in a variant-labelled row).
        cells = "\n".join(m.group(2) for m in re.finditer(
            r"^\| \*\*(Tables|Functions|Triggers)[^|]*\|(.*)\|\s*$", body, re.M))
        out[pkg] = (expand_slashes(body), expand_slashes(cells))
    return out

def registry_entries(reg_text):
    """{pkg: (detection text, extraction text)} from the ```json fence. Detection text is
    the entry's scope/*_added/name; *_note fields are commentary and excluded from BOTH
    (a note saying 'MOVED OUT to 083' must witness nothing)."""
    block = fenced(reg_text, "json")
    if block is None: raise ValueError(f"{PREG}: no ```json fence")
    data = json.loads(block)
    out, objects_arrays = {}, {}
    for e in data.get("packages", []):
        pkg = e.get("new")
        keep = []
        for k, v in e.items():
            if k.endswith("_note") or k in ("purpose",): continue
            keep.append(json.dumps(v) if not isinstance(v, str) else v)
        text = expand_slashes("\n".join(keep))
        out[pkg] = (text, text)
        if "objects" in e: objects_arrays[pkg] = e["objects"]
    return out, objects_arrays

def extract(text, mention_ok, functions_only_bare=True):
    found = set(QUAL_RE.findall(text))
    for m in BARE_RE.finditer(text):
        tok = m.group(1)
        if CODE_STOP.search(tok): continue
        found.add(tok)
    return {t for t in found if t not in mention_ok}

# ── checks ──────────────────────────────────────────────────────────────────
def check_O1(rows, plan_by_pkg, aliases, err):
    for r in rows:
        if r["obj"] == "NONE": continue
        sect = plan_by_pkg.get(r["pkg"])
        if sect is None:
            err(f"O1: package {r['pkg']} has no §8 section in the plan, but the closed world "
                f"declares {r['obj']} there. A declared package must have a plan row."); continue
        if not detectable(r["obj"], sect[0], aliases):
            err(f"O1: {r['obj']} is declared as a {r['kind']} of package {r['pkg']} but is NOT "
                f"detectable in plan §8's `{r['pkg']}` section. Either the plan does not schedule "
                f"it (the S-24 shape — schedule it or strike the declaration) or it is declared "
                f"in the wrong package (fix the PKG field), or it appears under an unmapped name "
                f"(add the §20.13 pair as an ALIAS row).")

def check_O2(rows, reg_by_pkg, objects_arrays, aliases, err):
    strong = set(objects_arrays) >= {r["pkg"] for r in rows if r["obj"] != "NONE"}
    for r in rows:
        if r["obj"] == "NONE": continue
        entry = reg_by_pkg.get(r["pkg"])
        if entry is None:
            err(f"O2: package {r['pkg']} has no registry JSON entry but declares {r['obj']}."); continue
        if strong:
            if r["obj"] not in set(objects_arrays.get(r["pkg"], [])):
                err(f"O2(strong): {r['obj']} is declared for {r['pkg']} but absent from the registry "
                    f"entry's objects array — the exact S-25 shape. Add it to the registry (a "
                    f"registry amendment), or strike the declaration.")
        elif r["kind"] in ("table", "view"):
            if not detectable(r["obj"], entry[0], aliases):
                err(f"O2: {r['kind']} {r['obj']} is declared for {r['pkg']} but not detectable in "
                    f"that package's registry entry (scope/*_added). The registry scope line must "
                    f"name every table its package creates.")
    if strong:
        for pkg, objs in objects_arrays.items():
            declared = {r["obj"] for r in rows if r["pkg"] == pkg and r["obj"] != "NONE"}
            for extra in sorted(set(objs) - declared):
                err(f"O2(strong): registry {pkg} objects array lists {extra} which the closed "
                    f"world does not declare for {pkg} — an extra registry object. Declare it "
                    f"(with its kind) or remove it from the registry entry.")
    return strong

def check_O3(rows, plan_by_pkg, aliases, mention_ok, err):
    declared_all = {r["obj"] for r in rows if r["obj"] != "NONE"}
    for a, b in aliases: declared_all |= {a, b}
    bare_ok = {o.split(".", 1)[1] for o in declared_all if "." in o} | declared_all
    hits = 0
    for pkg, (_full, cells) in sorted(plan_by_pkg.items()):
        for tok in sorted(extract(cells, mention_ok)):
            hits += 1
            key = tok if "." in tok else tok
            if key in declared_all or key in bare_ok: continue
            err(f"O3: plan §8 `{pkg}` schedules an object-shaped token `{tok}` that the closed "
                f"world declares NOWHERE. If it is a real Phase-2 object, ratify it into "
                f"package-objects (and the registry); if it is prose noise, add "
                f"`MENTION-OK|{tok}`. An implementer must never meet an object here first.")
    return hits

def check_O4(rows, reg_by_pkg, mention_ok, err):
    declared_all = {r["obj"] for r in rows if r["obj"] != "NONE"}
    hits = 0
    for pkg, (_det, ext) in sorted(reg_by_pkg.items()):
        for tok in sorted(set(QUAL_RE.findall(ext)) - mention_ok):
            hits += 1
            if tok in declared_all: continue
            err(f"O4: registry entry {pkg} names `{tok}` which the closed world declares in NO "
                f"package — the 'table that exists in no package' shape. Declare it or "
                f"MENTION-OK it, with a reason a reviewer can defend.")
    return hits

def check_O5(plan_by_pkg, reg_by_pkg, mention_ok, fatal):
    plan_fn = sum(len(extract(c, set())) for _p, (_f, c) in plan_by_pkg.items())
    reg_q   = len({t for _p, (_d, e) in reg_by_pkg.items() for t in QUAL_RE.findall(e)})
    if plan_fn < MIN_PLAN_FUNCS:
        fatal(f"O5: POSITIVE CONTROL FAILED — only {plan_fn} object tokens extracted from plan §8 "
              f"(need ≥ {MIN_PLAN_FUNCS}). The extractor has gone vacuous; a vacuous parser must "
              f"not be allowed to pass the corpus.")
    if reg_q < MIN_REG_QUALIFIED:
        fatal(f"O5: POSITIVE CONTROL FAILED — only {reg_q} qualified tokens extracted from the "
              f"registry JSON (need ≥ {MIN_REG_QUALIFIED}).")
    for surface, pkg, obj in SENTINELS:
        src = plan_by_pkg if surface == "plan" else reg_by_pkg
        text = src.get(pkg, ("", ""))[1 if surface == "plan" else 0]
        if obj not in extract(text, set()) and obj not in set(QUAL_RE.findall(text)):
            fatal(f"O5: POSITIVE CONTROL FAILED — sentinel {obj} was not extracted from "
                  f"{surface} {pkg}. Either the corpus moved it (update SENTINELS deliberately) "
                  f"or the parser broke. Fail closed either way.")
    return plan_fn, reg_q

# ── anti-vacuity fixtures: every one MUST produce an error ──────────────────
_P = {p: ("`x`", "`x`") for p in PACKAGES}   # minimal plan slices for fixtures
def _plan(pkg, cells):
    d = dict(_P); x = expand_slashes(cells); d[pkg] = (x, x); return d
FIXTURES = [
    ("O1: declared object missing from its plan package slice", lambda e: check_O1(
        [dict(pkg="085", obj="kernel.mark_refund_state", kind="function", line=1)],
        _plan("085", "| **Functions** | `refund_primary_order` |"), [], e)),
    ("O1: wrong-package declaration (object lives only in another slice)", lambda e: check_O1(
        [dict(pkg="082", obj="venue.finalize_primary_order", kind="function", line=1)],
        _plan("085", "| **Functions** | `venue.finalize_primary_order` |"), [], e)),
    ("O2: declared table absent from its registry entry", lambda e: check_O2(
        [dict(pkg="085", obj="kernel.refund", kind="table", line=1)],
        {"085": ("kernel.payment_native, kernel.payout", "")}, {}, [], e)),
    ("O2(strong): declared function absent from registry objects array (S-25)", lambda e: check_O2(
        [dict(pkg="085", obj="kernel.mark_refund_state", kind="function", line=1)],
        {"085": ("x", "x")}, {"085": ["kernel.refund"]}, [], e)),
    ("O2(strong): extra registry object the closed world never declared", lambda e: check_O2(
        [dict(pkg="085", obj="kernel.refund", kind="table", line=1)],
        {"085": ("kernel.refund", "")}, {"085": ["kernel.refund", "kernel.dispute_native"]}, [], e)),
    ("O3: phantom plan function declared nowhere (Mutation A)", lambda e: check_O3(
        [dict(pkg="085", obj="kernel.refund", kind="table", line=1)],
        _plan("085", "| **Functions** | `kernel.phantom_refund_probe` |"), [], set(), e)),
    ("O4: registry names an object no package declares (dispute-table shape)", lambda e: check_O4(
        [dict(pkg="085", obj="kernel.refund", kind="table", line=1)],
        {"085": ("kernel.refund plus kernel.dispute_native", "kernel.refund plus kernel.dispute_native")},
        set(), e)),
    ("O0: duplicate object row", lambda e: check_O0(
        [dict(pkg=p, obj="NONE", kind="-", line=0) for p in PACKAGES] +
        [dict(pkg="085", obj="kernel.refund", kind="table", line=90),
         dict(pkg="085", obj="kernel.refund", kind="table", line=91)], [], e)),
    ("O0: one object declared as created by two packages", lambda e: check_O0(
        [dict(pkg=p, obj="NONE", kind="-", line=0) for p in PACKAGES] +
        [dict(pkg="082", obj="venue.finalize_primary_order", kind="function", line=90),
         dict(pkg="085", obj="venue.finalize_primary_order", kind="function", line=91)], [], e)),
    ("O0: package absent from the closed world", lambda e: check_O0(
        [dict(pkg="076", obj="kernel.set_updated_at", kind="function", line=1)], [], e)),
    ("O0: unqualified object name", lambda e: check_O0(
        [dict(pkg=p, obj="NONE", kind="-", line=0) for p in PACKAGES] +
        [dict(pkg="085", obj="mark_refund_state", kind="function", line=90)], [], e)),
    ("O0: unknown kind", lambda e: check_O0(
        [dict(pkg=p, obj="NONE", kind="-", line=0) for p in PACKAGES] +
        [dict(pkg="085", obj="kernel.refund", kind="relation", line=90)], [], e)),
    ("O0: package outside the ratified band", lambda e: check_O0(
        [dict(pkg=p, obj="NONE", kind="-", line=0) for p in PACKAGES] +
        [dict(pkg="095", obj="kernel.ledger_entry", kind="table", line=90)], [], e)),
    ("O0: half-qualified ALIAS pair", lambda e: check_O0(
        [dict(pkg=p, obj="NONE", kind="-", line=0) for p in PACKAGES],
        [("catalog.set_venue_approval", "approve_venue")], e)),
]
# positive controls for the selftest: these must NOT error, or the matcher is broken
POSITIVE_CONTROLS = [
    ("alias form witnesses the declared name", lambda e: check_O1(
        [dict(pkg="086", obj="venue.create_door_pin", kind="function", line=1)],
        _plan("086", "| **Functions** | `venue.issue_door_pin` |"),
        [("venue.issue_door_pin", "venue.create_door_pin")], e)),
    ("slash-compressed family witnesses each member", lambda e: check_O1(
        [dict(pkg="083", obj="kernel.rotate_signing_key", kind="function", line=1)],
        _plan("083", "| **Functions** | `provision_/rotate_/revoke_signing_key` |"), [], e)),
    ("bare-name mention witnesses a qualified declaration", lambda e: check_O1(
        [dict(pkg="078", obj="catalog.set_resale_policy", kind="function", line=1)],
        _plan("078", "| **Functions** | `set_resale_policy` |"), [], e)),
    ("extractor finds qualified and bare tokens", lambda e: (None if len(extract(
        "| `kernel.mark_refund_state` and `set_resale_policy` |", set())) == 2
        else e("extractor missed a token it must find"))),
]

def selftest():
    bad = []
    for name, fn in FIXTURES:
        hits = []
        try: fn(hits.append)
        except Exception as ex: hits.append(str(ex))
        if not hits: bad.append("NEGATIVE did not trip: " + name)
    for name, fn in POSITIVE_CONTROLS:
        hits = []
        try: fn(hits.append)
        except Exception as ex: hits.append(str(ex))
        if hits: bad.append(f"POSITIVE control errored ({hits[0][:80]}...): " + name)
    if bad:
        print("REGISTRY↔PLAN PARITY SELFTEST FAILED:")
        for b in bad: print(f"  - {b}")
        print("The checker cannot be trusted to fail, so it must not be trusted to pass.")
        return 1
    print(f"registry↔plan parity selftest OK: {len(FIXTURES)} negative fixtures failed, "
          f"{len(POSITIVE_CONTROLS)} positive controls passed")
    return 0

def propose_seed():
    """Emit a DRAFT package-objects block from the real corpus. The draft REQUIRES human
    ratification — extraction noise becomes closed-world law only through review."""
    plan_by_pkg = plan_slices(read(PLAN))
    print("```package-objects")
    print("# DRAFT — extracted, NOT ratified. Review every row; prune noise; set kinds.")
    for pkg in PACKAGES:
        sect = plan_by_pkg.get(pkg)
        if sect is None: continue
        body, _cells = sect
        tables = "\n".join(m.group(1) for m in re.finditer(
            r"^\| \*\*Tables[^|]*\|(.*)\|\s*$", body, re.M))
        funcs  = "\n".join(m.group(1) for m in re.finditer(
            r"^\| \*\*(?:Functions|Triggers)[^|]*\|(.*)\|\s*$", body, re.M))
        t = set(extract(expand_slashes(tables), set()))
        fset = set(extract(expand_slashes(funcs), set()))
        # drop a bare token when its qualified twin was also extracted
        quals = {o for o in (t | fset) if "." in o}
        bares = {q.split(".", 1)[1] for q in quals}
        t = {o for o in t if "." in o or o not in bares}
        fset = {o for o in fset if "." in o or o not in bares}
        rows = [(o, "table") for o in sorted(t)] + \
               [(o, "function") for o in sorted(fset) if o not in t]
        if not rows: print(f"{pkg}|NONE|-")
        for o, k in rows: print(f"{pkg}|{o}|{k}")
    print("```")

def main():
    if "--selftest" in sys.argv: sys.exit(selftest())
    if "--propose-seed" in sys.argv: propose_seed(); sys.exit(0)
    errors, fatals = [], []
    err = errors.append
    spec_text = read(SPEC)
    if spec_text is None:
        print(f"::error::object parity: closed world not found at {SPEC}"); sys.exit(2)
    try:
        rows, aliases, mention_ok = parse_spec(spec_text)
        plan_by_pkg = plan_slices(read(PLAN) or "")
        reg_by_pkg, objects_arrays = registry_entries(read(PREG) or "")
    except (ValueError, json.JSONDecodeError) as e:
        print(f"::error::object parity: {e}"); sys.exit(2)
    plan_fn, reg_q = check_O5(plan_by_pkg, reg_by_pkg, mention_ok, fatals.append)
    if fatals:
        for f in fatals: print(f"::error::{f}")
        sys.exit(2)
    check_O0(rows, aliases, err)
    check_O1(rows, plan_by_pkg, aliases, err)
    strong = check_O2(rows, reg_by_pkg, objects_arrays, aliases, err)
    check_O3(rows, plan_by_pkg, aliases, mention_ok, err)
    check_O4(rows, reg_by_pkg, mention_ok, err)
    n_obj = sum(1 for r in rows if r["obj"] != "NONE")
    print(f"declared objects    : {n_obj}  (packages: {len({r['pkg'] for r in rows})}, "
          f"aliases: {len(aliases)}, mention-ok: {len(mention_ok)})")
    print(f"mode                : {'STRONG (registry objects arrays present)' if strong else 'BOOTSTRAP (function-level registry parity NOT yet enforced)'}")
    print(f"extraction controls : plan §8 tokens={plan_fn}  registry qualified={reg_q}  sentinels OK")
    if errors:
        print(f"\nOBJECT-SET PARITY FAILED — {len(errors)} violation(s):")
        for e in errors: print(f"::error::{e}")
        sys.exit(1)
    print("\nobject-set parity OK — O0/O1/O2/O3/O4/O5 hold" +
          ("" if strong else " (bootstrap scope)"))
    sys.exit(0)

if __name__ == "__main__":
    main()
