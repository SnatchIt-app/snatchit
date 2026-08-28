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
        rows.append(dict(id=cid, subject=sid, res=res, winner=winner,
                         sites=[s.strip() for s in sites.split(";") if s.strip()], line=n))
    return rows

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
        if c["subject"] not in ids:
            err(f"B: contradiction {c['id']} names subject {c['subject']} which is not in the owner map")

def check_C(rows, err):
    for r in rows:
        if r["owner"] in r["derived"]:
            err(f"C: subject {r['id']}: {r['owner']} is listed as BOTH normative owner and restatement")

def check_D(cons, rows, err):
    fb = {r["id"]: r["fallback"] for r in rows}
    for c in cons:
        if c["res"] == "FALLBACK" and fb.get(c["subject"]) != "YES":
            err(f"D: contradiction {c['id']} resolves by ratified-correction FALLBACK, but the owner map "
                f"says subject {c['subject']} has an owner (CORRECTION_FALLBACK=NO). OR-6 rule 2: a "
                f"correction may not override an assigned owner.")

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
        elif c["res"] == "OWNER" and c["subject"] in amb:
            err(f"F: contradiction {c['id']} claims OWNER resolution but subject {c['subject']} is "
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
    amb = [r["id"] for r in rows if r["owner"] == "AMBIGUOUS"]
    print(f"subjects registered : {len(rows)}")
    print(f"ambiguous subjects  : {len(amb)}" + (f"  ({', '.join(amb)})" if amb else ""))
    print(f"contradiction rows  : {len(cons)}")
    if errors:
        print(f"\nPRECEDENCE GATE FAILED — {len(errors)} violation(s) of owner ruling OR-6:")
        for e in errors: print(f"::error::{e}")
        sys.exit(1)
    print("\nprecedence gate OK — A/B/C/D/E/F/G all hold")
    sys.exit(0)

if __name__ == "__main__":
    main()
