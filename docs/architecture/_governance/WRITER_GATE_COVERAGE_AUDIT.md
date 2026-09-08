# Writer Gate — Coverage / Vacuity Audit (Phase E of the convergence pass, 2026-08-29)

**Question audited:** for every canonical writer, do at least two independent witnesses exist, and can a
writer vanish from every compared column and still pass?

## The witness model, after this pass

| witness | field | catches |
|---|---|---|
| 1 — identity | `WRITERS` | absence vs the derived docs (via PARITY, maintained by re-derivation) |
| 2 — kind | `KINDS` | a trigger/cron/webhook writer dropped from ONE column (count parity) |
| 3 — provenance | `RPC_SECTION` | a writer dropped from BOTH writers and kinds — the section left behind trips the count check (**the check the triage added; this pass adds fixtures proving it for trigger and cron flavors specifically**) |
| 4 — build | `BUILT` *(NEW)* | a contracted writer no package builds (`RC-5`) — count-parity per writer, vocabulary-checked, any `n` is an error |
| 5 — enumeration closure | check **H2** *(NEW)* | a true-scope table absent from the fence entirely — the `RC-1` failure shape (`kernel.tickets`, `kernel.payment_native`) can no longer happen silently |
| 6 — duplicate guard *(NEW)* | in-row | a renamed writer left beside its old name, inflating the set |

**Can a writer dropped from writers AND kinds AND sections AND built pass?** Within a single row — yes,
structurally: four synchronized deletions are indistinguishable from a smaller row. That residual is
covered by (a) the PARITY column, which is re-derived against the derived documents whose lists must agree
exactly or point, and (b) `H2`'s closed table set. This limit is stated rather than papered over.

## Fixtures: 16 → 25, nothing weakened

All 16 pre-existing fixtures preserved verbatim (one new fixture's first draft was itself vacuous — a
single BUILT flag legally covers all writers — caught by the selftest and corrected to a true mismatch).
The 9 added:

1. trigger writer dropped from writers+kinds, section left behind
2. sweep/cron writer dropped from writers+kinds, section left behind
3. canonical contract section missing entirely
4. writer missing from BOTH compared columns (second witness, dedicated)
5. BUILT flag count mismatch
6. unknown BUILT flag
7. contracted writer built by NO package (`BUILT=n`)
8. renamed writer beside its old name (duplicate)
9. true-scope table absent from the enumeration (`H2`)

*(The requested "extra derived writer" fixture is the pre-existing `DIVERGENT`-parity fixture — an extra
writer in a derived doc IS a divergence; the duplicate guard covers the in-registry variant.)*

## Proven on the real corpus

`kernel.tickets` (row 6, eleven writers, `OK`) and `kernel.payment_native` (row 7, `MISSING_CONTRACT` —
**a live error the gate could not previously see**) are fence rows; deleting either now fails `H2`
(fixture 9). Selftest: **25/25**. Real corpus: **20 errors — 16 missing-contract + 4 not-built, 0
divergent** — RED for real reasons.
