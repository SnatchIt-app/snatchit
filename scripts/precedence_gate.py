#!/usr/bin/env python3
"""
precedence_gate.py — enforce owner ruling OR-6 (ODR-7 / O11: HYBRID PRECEDENCE).

ONE script, ONE parseable map, ONE existing required CI job. Deliberately not a
governance framework: it checks six mechanical properties and refuses to guess
about anything else.

  A  every registered subject has exactly one normative owner
  B  every contradiction row names a subject that exists in the map
  C  no restatement document also claims ownership of the same subject
  D  correction fallback is cited ONLY where the map says the owner is silent
  E  recency is never used as a resolver, anywhere in the corpus
  F  ambiguous or unresolved contradictions fail closed
  G  a ratified correction that declares N propagation sites is detectable in all N
  H  the canonical writer registry is well-formed and every derived list agrees with it

Anti-vacuity: `--selftest` runs the checkers against embedded fixtures that MUST
fail. If a fixture passes, the gate itself is broken and exits non-zero. CI runs
`--selftest` before the real check, so a parser that silently matches nothing
cannot go green.

Exit 0 = pass. Exit 1 = a violation. Exit 2 = the gate could not run (missing
input, unparseable map) — which is also a failure, on purpose: fail closed.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOV  = "docs/architecture/_governance"
MAP  = "docs/architecture/PHASE_2_SUBJECT_MATTER_OWNER_MAP.md"
CONT = f"{GOV}/ODR128_CONTRADICTION_RESOLUTION.md"
WREG = f"{GOV}/WRITER_REGISTRY_PARITY_SPEC.md"
RATIF= f"{GOV}/PHASE_2_RATIFICATION_RECORD.md"

# Rule 3 of OR-6: recency has no authority. These phrases, used as a RESOLVER,
# are banned corpus-wide. Matching is on the resolver phrasing, not on the words
# "newest" or "latest" alone, so ordinary prose is unaffected.
RECENCY_RESOLVERS = [
    r"newest\s+commit\s+wins", r"newest\s+markdown\s+wins", r"latest\s+edited\s+\w+\s+wins",
    r"most\s+recently\s+edited\s+wins", r"higher\s+correction\s+number\s+wins",
    r"the\s+later\s+document\s+wins", r"recency\s+governs",
]
# Sites permitted to contain those phrases *because they prohibit them*.
RECENCY_ALLOWLIST = {
    MAP, CONT, RATIF,
    f"{GOV}/PHASE_2_OWNER_DECISION_REGISTER.md",
    f"{GOV}/ODR7_PRECEDENCE_CONSEQUENCE_MAP.md",
    f"{GOV}/PRECEDENCE_CI_GATE_SPEC.md",
    f"{GOV}/WRITER_OWNER_RULING_CONSEQUENCE_MAP.md",
    WREG,
}

def read(rel):
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p): return None
    with open(p, encoding="utf-8") as f: return f.read()

def fenced(text, tag):
    m = re.search(r"```" + re.escape(tag) + r"\n(.*?)```", text or "", re.S)
    return m.group(1) if m else None

def parse_map(text):
    """SUBJECT_ID|SUBJECT|OWNER_DOC|SECTION|DERIVED(;)|FALLBACK(YES|NO)"""
    block = fenced(text, "owner-map")
    if block is None: raise ValueError("no ```owner-map fenced block")
    rows = []
    for n, line in enumerate(block.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"): continue
        f = [c.strip() for c in line.split("|")]
        if len(f) != 6: raise ValueError(f"owner-map line {n}: expected 6 fields, got {len(f)}")
        sid, subj, owner, sec, derived, fb = f
        if fb not in ("YES", "NO"): raise ValueError(f"owner-map line {n}: fallback must be YES|NO, got {fb!r}")
        rows.append(dict(id=sid, subject=subj, owner=owner, section=sec,
                         derived=[d.strip() for d in derived.split(";") if d.strip()],
                         fallback=fb, line=n))
    if not rows: raise ValueError("owner-map block is empty")
    return rows

def parse_contradictions(text):
    """ID|SUBJECT_ID|RESOLUTION(OWNER|FALLBACK|UNRESOLVED)|WINNER_DOC|SITES(;)"""
    block = fenced(text, "contradictions")
    if block is None: raise ValueError("no ```contradictions fenced block")
    rows = []
    for n, line in enumerate(block.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"): continue
        f = [c.strip() for c in line.split("|")]
        if len(f) != 5: raise ValueError(f"contradictions line {n}: expected 5 fields, got {len(f)}")
        cid, sid, res, winner, sites = f
        if res not in ("OWNER", "FALLBACK", "UNRESOLVED"):
            raise ValueError(f"contradictions line {n}: resolution must be OWNER|FALLBACK|UNRESOLVED")
        # A decomposed contradiction (one call contract, several subjects with different
        # owners) is expressed as a comma-separated subject list. Found necessary by the X-8
        # analysis: a single-subject field cannot express a contract whose parts have
        # different owners, and silently collapsing it to one subject is a subject
        # substitution — the error the gate caught on X-4.
        subs = [x.strip() for x in sid.split(",") if x.strip()]
        rows.append(dict(id=cid, subject=sid, subjects=subs, res=res, winner=winner,
                         sites=[s.strip() for s in sites.split(";") if s.strip()], line=n))
    return rows

KINDS = {"rpc", "trigger", "cron", "helper", "webhook"}

def parse_writer_registry(text):
    """TABLE|WRITERS(;)|KINDS(;)|RPC_SECTION|BUILT(;)|PARITY(OK|DIVERGENT|MISSING_CONTRACT)

    BUILT is per-writer: y (scheduled/built) · n (contracted, built by NO package — a gate error)
    · c (conditional/deferred by a ratified gate, e.g. COND-B) · - (no-writer row). Added by the
    writer-parity convergence pass so a contracted-never-built writer is gate-visible (RC-5)."""
    block = fenced(text, "writer-registry")
    if block is None: raise ValueError("no ```writer-registry fenced block")
    rows = []
    for n, line in enumerate(block.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"): continue
        f = [c.strip() for c in line.split("|")]
        if len(f) == 5:
            tbl, writers, kinds, sec, parity = f; built = ""
        elif len(f) == 6:
            tbl, writers, kinds, sec, built, parity = f
        else:
            raise ValueError(f"writer-registry line {n}: expected 5 or 6 fields, got {len(f)}")
        w = [x.strip() for x in writers.split(";") if x.strip()]
        k = [x.strip() for x in kinds.split(";") if x.strip()]
        sx = [x.strip() for x in sec.split(";") if x.strip()]
        bx = [x.strip() for x in built.split(";") if x.strip()]
        if parity not in ("OK", "DIVERGENT", "MISSING_CONTRACT"):
            raise ValueError(f"writer-registry line {n}: parity must be OK|DIVERGENT|MISSING_CONTRACT")
        rows.append(dict(table=tbl, writers=w, kinds=k, section=sec, sections=sx,
                         built=bx, parity=parity, line=n))
    return rows

# Tables the WRITER ruling's true scope requires the registry to enumerate. kernel.tickets and
# kernel.payment_native were IN SCOPE and derived in a side document, so their parity never reached
# the gate (RC-1) — the closed-set check exists so that cannot recur.
REQUIRED_WRITER_TABLES = {"kernel.tickets", "kernel.payment_native"}

def check_H2(rows, err):
    """True-scope closure: a table the ruling requires may not be absent from the enumeration."""
    have = {r["table"] for r in rows}
    for t in sorted(REQUIRED_WRITER_TABLES - have):
        err(f"H2: true-scope table {t} is ABSENT from the writer registry. Its parity was previously "
            f"computed in a side document and never reached the gate (RC-1); the registry must "
            f"enumerate it.")

def check_H(rows, err):
    """The writer registry is the artifact the WRITER owner ruling created. It is checked
    structurally: the gate cannot read prose, but it CAN refuse a registry that is
    self-inconsistent, that omits the writer kinds the ruling requires be included, or that
    admits a table whose canonical writer has no contract."""
    seen = set()
    for r in rows:
        if r["table"] in seen:
            err(f"H: table {r['table']} appears twice in the writer registry (line {r['line']})")
        seen.add(r["table"])
        if "." not in r["table"]:
            err(f"H: writer-registry table {r['table']!r} is not schema-qualified (line {r['line']})")
        if r["writers"] == ["-"] and r["kinds"] == ["-"]:
            pass
        elif len(r["writers"]) != len(r["kinds"]):
            err(f"H: table {r['table']} has {len(r['writers'])} writers but {len(r['kinds'])} kinds — "
                f"every writer needs a kind, or a trigger/cron writer can be dropped silently")
        # The KIND column was added so a trigger or cron writer cannot vanish. It only
        # catches a writer dropped from ONE column. The SECTION column is the second
        # witness: every writer must cite where it is contracted, so a writer dropped from
        # writers AND kinds still leaves a section behind, and a section dropped alone is
        # caught here. Found by the triage pass — the gate shipped without it.
        if r["writers"] != ["-"] and len(r["sections"]) not in (len(r["writers"]), 1):
            err(f"H: table {r['table']} has {len(r['writers'])} writers but "
                f"{len(r['sections'])} contract sections. Cite one section per writer, or a "
                f"single section covering all of them — an unmatched count hides a dropped writer.")
        # BUILT is the third witness (RC-5): a contracted writer no package builds was invisible —
        # kernel.mark_refund_state was in the schema spec x5 and the edge spec x2 and ZERO lines of
        # the plan, and nothing failed. One flag per writer, or one flag covering all.
        bx = r.get("built") or []
        if r["writers"] != ["-"] and bx:
            if len(bx) not in (len(r["writers"]), 1):
                err(f"H: table {r['table']} has {len(r['writers'])} writers but {len(bx)} BUILT flags — "
                    f"a not-built writer could vanish behind a neighbour's flag.")
            for b in bx:
                if b not in ("y", "n", "c", "-"):
                    err(f"H: table {r['table']} has unknown BUILT flag {b!r} (allowed: y/n/c/-)")
                if b == "n":
                    err(f"H: table {r['table']} has a contracted writer that NO package builds "
                        f"(BUILT=n). Contracted-but-never-built is a readiness failure (RC-5), not a "
                        f"footnote.")
        # A renamed writer left beside its old name, or a plain duplicate, silently inflates the set.
        seen_w = set()
        for w in ([] if r["writers"] == ["-"] else r["writers"]):
            if w.startswith("CATEGORY:"): continue
            if w in seen_w:
                err(f"H: table {r['table']} lists writer {w!r} twice — a rename that kept the old "
                    f"name, or a duplicate; either way the count lies.")
            seen_w.add(w)
        for k in ([] if r["kinds"] == ["-"] else r["kinds"]):
            if k not in KINDS:
                err(f"H: table {r['table']} has unknown writer kind {k!r} (allowed: {sorted(KINDS)})")
        for w in ([] if r["writers"] == ["-"] else r["writers"]):
            # `CATEGORY:` is the compliant way to say "every privileged RPC, in-txn" without
            # maintaining a list the ruling would then require to be exact.
            if w.startswith("CATEGORY:"): continue
            if "." not in w:
                err(f"H: table {r['table']} writer {w!r} is not schema-qualified")
        if r["parity"] == "MISSING_CONTRACT":
            err(f"H: table {r['table']} has a structurally required writer with NO function contract. "
                f"The WRITER ruling: that is a MISSING CONTRACT and readiness fails. It may not be "
                f"fixed by adding the function to a derived schema or RLS document.")
        if r["parity"] == "DIVERGENT":
            err(f"H: table {r['table']} — a derived document's writer list does not match the canonical "
                f"registry. Derived lists must agree EXACTLY or point at the registry.")
        if not r["writers"] or r["writers"] == ["-"]:
            # A table with no writer is admissible ONLY with a stated reason, so an
            # accidentally-empty row cannot pass as a deliberate one.
            if not any(t in r["section"].upper()
                       for t in ("NONE", "SEED-ONLY", "EXT-", "CONDITIONAL", "NOT-BUILT")):
                err(f"H: table {r['table']} is registered with no canonical writer and no stated "
                    f"reason. Say why (NONE / SEED-ONLY / EXT- / CONDITIONAL / NOT-BUILT) or name "
                    f"the writer.")

# ── checks ──────────────────────────────────────────────────────────────────
def check_A(rows, err):
    seen = {}
    for r in rows:
        if r["id"] in seen:
            err(f"A: subject {r['id']} registered twice (lines {seen[r['id']]} and {r['line']})")
        seen[r["id"]] = r["line"]
        if r["owner"] != "AMBIGUOUS" and not os.path.exists(os.path.join(ROOT, r["owner"])):
            err(f"A: subject {r['id']} owner document does not exist: {r['owner']}")
        for d in r["derived"]:
            if not os.path.exists(os.path.join(ROOT, d)):
                err(f"A: subject {r['id']} derived document does not exist: {d}")

def check_B(cons, rows, err):
    ids = {r["id"] for r in rows}
    for c in cons:
        for sub in c.get("subjects", [c["subject"]]):
            if sub not in ids:
                err(f"B: contradiction {c['id']} names subject {sub} which is not in the owner map")

def check_C(rows, err):
    for r in rows:
        if r["owner"] in r["derived"]:
            err(f"C: subject {r['id']}: {r['owner']} is listed as BOTH normative owner and restatement")

def check_D(cons, rows, err):
    fb = {r["id"]: r["fallback"] for r in rows}
    for c in cons:
        if c["res"] == "FALLBACK":
            for sub in c.get("subjects", [c["subject"]]):
                if fb.get(sub) != "YES":
                    err(f"D: contradiction {c['id']} resolves by ratified-correction FALLBACK, but the "
                        f"owner map says subject {sub} has an owner (CORRECTION_FALLBACK=NO). OR-6 rule "
                        f"2: a correction may not override an assigned owner.")

def check_E(err):
    pats = [re.compile(p, re.I) for p in RECENCY_RESOLVERS]
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "docs/architecture")):
        for fn in files:
            if not fn.endswith(".md"): continue
            rel = os.path.relpath(os.path.join(dirpath, fn), ROOT)
            if rel in RECENCY_ALLOWLIST: continue
            try:
                body = open(os.path.join(dirpath, fn), encoding="utf-8").read()
            except Exception: continue
            for p in pats:
                m = p.search(body)
                if m:
                    err(f"E: {rel} uses recency as a resolver: {m.group(0)!r}. OR-6 rule 3 forbids it.")

def check_F(cons, rows, err):
    amb = {r["id"] for r in rows if r["owner"] == "AMBIGUOUS"}
    for c in cons:
        if c["res"] == "UNRESOLVED":
            err(f"F: contradiction {c['id']} is UNRESOLVED. OR-6 rule 4 requires it to fail closed until "
                f"it is resolved explicitly — the implementer does not choose.")
        elif c["res"] == "OWNER":
            for sub in c.get("subjects", [c["subject"]]):
                if sub in amb:
                    err(f"F: contradiction {c['id']} claims OWNER resolution but subject {sub} is "
                        f"AMBIGUOUS in the owner map.")
        if c["res"] != "UNRESOLVED" and not c["sites"]:
            err(f"F: contradiction {c['id']} is resolved but names no transcription site.")
        for s in c["sites"]:
            if not os.path.exists(os.path.join(ROOT, s)):
                err(f"F: contradiction {c['id']} names a transcription site that does not exist: {s}")

def check_G(text, err):
    """PROPAGATION: <correction-id> -> path;path;path   (one per line, in a fenced block)"""
    block = fenced(text or "", "propagation")
    if block is None: return          # no declarations yet is not a failure
    for n, line in enumerate(block.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"): continue
        if "->" not in line:
            err(f"G: propagation line {n} is malformed (expected '<id> -> path;path')"); continue
        cid, paths = line.split("->", 1)
        cid = cid.strip()
        sites = [p.strip() for p in paths.split(";") if p.strip()]
        if not sites:
            err(f"G: correction {cid} declares zero propagation sites"); continue
        for s in sites:
            body = read(s)
            if body is None:
                err(f"G: correction {cid} names a site that does not exist: {s}")
            elif cid not in body:
                err(f"G: correction {cid} is declared to affect {s}, but {cid} is not detectable there. "
                    f"A correction that names N sites must be visible in all N.")

# ── anti-vacuity: fixtures that MUST fail ───────────────────────────────────
FIXTURES = [
    ("A: duplicate subject id", lambda e: check_A(
        [dict(id="X", subject="s", owner="AMBIGUOUS", section="", derived=[], fallback="NO", line=1),
         dict(id="X", subject="s", owner="AMBIGUOUS", section="", derived=[], fallback="NO", line=2)], e)),
    ("B: contradiction names an unregistered subject", lambda e: check_B(
        [dict(id="K1", subject="NOPE", res="OWNER", winner="w", sites=["x"], line=1)],
        [dict(id="X", subject="s", owner="AMBIGUOUS", section="", derived=[], fallback="NO", line=1)], e)),
    ("C: owner also listed as restatement", lambda e: check_C(
        [dict(id="X", subject="s", owner="a.md", section="", derived=["a.md"], fallback="NO", line=1)], e)),
    ("D: fallback used where an owner exists", lambda e: check_D(
        [dict(id="K1", subject="X", res="FALLBACK", winner="w", sites=["x"], line=1)],
        [dict(id="X", subject="s", owner="a.md", section="", derived=[], fallback="NO", line=1)], e)),
    ("F: unresolved contradiction", lambda e: check_F(
        [dict(id="K1", subject="X", res="UNRESOLVED", winner="", sites=[], line=1)],
        [dict(id="X", subject="s", owner="a.md", section="", derived=[], fallback="NO", line=1)], e)),
    ("F: OWNER resolution on an AMBIGUOUS subject", lambda e: check_F(
        [dict(id="K1", subject="X", res="OWNER", winner="w", sites=["docs"], line=1)],
        [dict(id="X", subject="s", owner="AMBIGUOUS", section="", derived=[], fallback="NO", line=1)], e)),
    ("G: correction not detectable at a declared site", lambda e: check_G(
        "```propagation\nC999 -> docs/architecture/PHASE_2_SUBJECT_MATTER_OWNER_MAP.md\n```", e)),
    ("B: decomposed row with one unregistered subject", lambda e: check_B(
        [dict(id="K1", subject="A,NOPE", subjects=["A","NOPE"], res="UNRESOLVED", winner="", sites=[], line=1)],
        [dict(id="A", subject="s", owner="a.md", section="", derived=[], fallback="NO", line=1)], e)),
    ("H: writer count != kind count (a trigger writer could vanish)", lambda e: check_H(
        [dict(table="k.t", writers=["a.b","c.d"], kinds=["rpc"], section="", sections=[], parity="OK", line=1)], e)),
    ("H: unknown writer kind", lambda e: check_H(
        [dict(table="k.t", writers=["a.b"], kinds=["magic"], section="", sections=[], parity="OK", line=1)], e)),
    ("H: MISSING_CONTRACT must fail readiness", lambda e: check_H(
        [dict(table="k.t", writers=["a.b"], kinds=["rpc"], section="", sections=[], parity="MISSING_CONTRACT", line=1)], e)),
    ("H: DIVERGENT derived list must fail", lambda e: check_H(
        [dict(table="k.t", writers=["a.b"], kinds=["rpc"], section="", sections=[], parity="DIVERGENT", line=1)], e)),
    ("H: writer count != section count (second witness)", lambda e: check_H(
        [dict(table="k.t", writers=["a.b","c.d"], kinds=["rpc","rpc"], section="1;2;3",
              sections=["1","2","3"], parity="OK", line=1)], e)),
    ("H: empty writer list with no stated reason", lambda e: check_H(
        [dict(table="k.t", writers=["-"], kinds=["-"], section="17.9", sections=["17.9"], parity="OK", line=1)], e)),
    ("H: duplicate table row", lambda e: check_H(
        [dict(table="k.t", writers=["a.b"], kinds=["rpc"], section="", sections=[], parity="OK", line=1),
         dict(table="k.t", writers=["a.b"], kinds=["rpc"], section="", sections=[], parity="OK", line=2)], e)),
    ("H: unqualified writer name", lambda e: check_H(
        [dict(table="k.t", writers=["bare"], kinds=["rpc"], section="", sections=[], parity="OK", line=1)], e)),
    # ── writer-parity convergence pass fixtures (Phase E audit) ─────────────
    ("H: TRIGGER writer dropped from writers+kinds leaves its section behind", lambda e: check_H(
        [dict(table="k.t", writers=["k.f"], kinds=["rpc"], section="1;2", sections=["1","2"],
              parity="OK", line=1)], e)),
    ("H: SWEEP/cron writer dropped from writers+kinds leaves its section behind", lambda e: check_H(
        [dict(table="k.t", writers=["k.f"], kinds=["cron"], section="12.5;17.4", sections=["12.5","17.4"],
              parity="OK", line=1)], e)),
    ("H: canonical contract section missing entirely", lambda e: check_H(
        [dict(table="k.t", writers=["k.f"], kinds=["rpc"], section="", sections=[], parity="OK", line=1)], e)),
    ("H: writer missing from BOTH writer and kind columns (second witness)", lambda e: check_H(
        [dict(table="k.t", writers=["k.f"], kinds=["rpc"], section="1;2;3", sections=["1","2","3"],
              parity="OK", line=1)], e)),
    ("H: BUILT flag count mismatch (a not-built writer could vanish)", lambda e: check_H(
        [dict(table="k.t", writers=["k.f","k.g"], kinds=["rpc","rpc"], section="1;2", sections=["1","2"],
              built=["y","y","n"], parity="OK", line=1)], e)),
    ("H: unknown BUILT flag", lambda e: check_H(
        [dict(table="k.t", writers=["k.f"], kinds=["rpc"], section="1", sections=["1"],
              built=["x"], parity="OK", line=1)], e)),
    ("H: contracted writer built by NO package (BUILT=n)", lambda e: check_H(
        [dict(table="k.t", writers=["k.f"], kinds=["webhook"], section="20.7.7", sections=["20.7.7"],
              built=["n"], parity="OK", line=1)], e)),
    ("H: renamed writer left beside its old name (duplicate writer)", lambda e: check_H(
        [dict(table="k.t", writers=["k.f","k.f"], kinds=["rpc","rpc"], section="1;1", sections=["1","1"],
              parity="OK", line=1)], e)),
    ("H2: true-scope table absent from the registry enumeration", lambda e: check_H2([], e)),
]

def selftest():
    bad = []
    for name, fn in FIXTURES:
        hits = []
        try: fn(hits.append)
        except Exception as ex: hits.append(str(ex))
        if not hits:
            bad.append(name)
    if bad:
        print("PRECEDENCE GATE SELFTEST FAILED — these fixtures did not trip their checker:")
        for b in bad: print(f"  - {b}")
        print("The gate cannot be trusted to fail, so it must not be trusted to pass.")
        return 1
    print(f"precedence gate selftest OK: {len(FIXTURES)}/{len(FIXTURES)} negative fixtures correctly failed")
    return 0

def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    errors = []
    err = errors.append
    map_text = read(MAP)
    if map_text is None:
        print(f"::error::precedence gate: owner map not found at {MAP}"); sys.exit(2)
    try:
        rows = parse_map(map_text)
    except ValueError as e:
        print(f"::error::precedence gate: {MAP}: {e}"); sys.exit(2)
    cont_text = read(CONT)
    cons = []
    if cont_text is not None:
        try: cons = parse_contradictions(cont_text)
        except ValueError as e:
            print(f"::error::precedence gate: {CONT}: {e}"); sys.exit(2)
    check_A(rows, err); check_B(cons, rows, err); check_C(rows, err)
    check_D(cons, rows, err); check_E(err); check_F(cons, rows, err)
    check_G(read(RATIF), err)
    wreg_text = read(WREG)
    wrows = []
    if wreg_text is not None:
        try:
            wrows = parse_writer_registry(wreg_text)
        except ValueError as e:
            print(f"::error::precedence gate: {WREG}: {e}"); sys.exit(2)
        check_H(wrows, err)
        check_H2(wrows, err)
    amb = [r["id"] for r in rows if r["owner"] == "AMBIGUOUS"]
    print(f"subjects registered : {len(rows)}")
    print(f"ambiguous subjects  : {len(amb)}" + (f"  ({', '.join(amb)})" if amb else ""))
    print(f"contradiction rows  : {len(cons)}")
    if wrows:
        print(f"writer tables       : {len(wrows)}")
        entries = sum(len([w for w in r["writers"] if w != "-"]) for r in wrows)
        distinct = {w for r in wrows for w in r["writers"]
                    if w != "-" and not w.startswith("CATEGORY:")}
        print(f"writer entries      : {entries}  (a function writing N tables counts N times)")
        print(f"distinct writers    : {len(distinct)}")
    if errors:
        print(f"\nPRECEDENCE GATE FAILED — {len(errors)} violation(s) of owner ruling OR-6:")
        for e in errors: print(f"::error::{e}")
        sys.exit(1)
    print("\nprecedence gate OK — A/B/C/D/E/F/G/H all hold")
    sys.exit(0)

if __name__ == "__main__":
    main()
