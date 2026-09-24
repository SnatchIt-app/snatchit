# B — independent review of A's R0-wide result (#92), under package `df5300eb`

**Scope, as authorised:** review A's **captured** R0-wide result against the frozen reference. **No
production query was run by me, and none is requested here.** This is not a re-audit of the #92 package.

**Artefacts reviewed:** A's result and re-pin at `7159d10c` (§12 of the package), the package as frozen at
`df5300eb`, and D's review at `b93fc7ff`.

---

## 1 · The three classes of difference, kept apart

| Class | Result | Basis |
|---|---|---|
| **Signature** | **0 of 12 differ** | All 12 functions present at their exact signature; ordered argument types and result type identical to the reference (prediction P-b, held) |
| **Attribute** | **0 of 12 differ** | `SECURITY DEFINER`, `config`/`search_path`, owner and volatility identical for all 12 (P-b) |
| **Body** | **12 of 12 differ** | P-d held: the difference is confined to `prosrc`/`defn`. **11 are non-semantic** — comments, and keyword case on three. **1 is a real logic difference** |

A's earlier decomposition had proposed nine attribute-level explanations for the drift. **None of them could
have matched**, because the cause is body storage formatting — D states this and I agree; it is the correct
reading of a 0-attribute, 12-body result.

## 2 · Does #92's production premise hold? **Yes.**

The premise is that 148 keys on the row shape `resolve_transfer_dispute` writes on seller-win — status
`buyer_confirmed`, `buyer_confirmed_at` left NULL, `dispute_resolution 'resolved_seller_paid'`.

Four independent strands support it, and I find them sufficient:

1. **Textual:** both writers differ from the reference in comments only, so the logic is identical. The
   normalisation is sound for these bodies — the only `"` occurs inside a comment and the only `$` inside a
   string literal, so neither quoted identifiers nor dollar-quoting can be corrupted by comment-stripping.
2. **Unchanged since capture:** P-c held 12/12 — every production `defn` md5 carries its 2026-09-23 capture
   prefix, so nothing moved between the capture and the read.
3. **Behavioural, and this is the strongest:** rehearsal 6 installed **production's own bodies** into a
   fresh database, and the resulting local `defn` md5s **equal production's**. The code exercised was
   therefore byte-identical to production's, not a reconstruction — and pgTAP 215, which calls
   `resolve_transfer_dispute` directly for seller-win, buyer-win and partial outcomes, passed **43/43** on it.
4. **Discriminating:** the negative control — a copy carrying the repo's commented bodies — now STOPS at P3,
   so the check can fail.

D reached the same classification independently, including reading the production seller-win branch and
confirming `disputed_at` is cleared. **Agreement is not itself proof**, which is why I rest the verdict on
strand 3: a behavioural result on byte-identical code is evidence of a different kind from a text diff.

**`handle_new_user` is the one real logic difference and it does not bear on #92.** It is an
`auth.users → profiles` trigger, unrelated to the dispute row shape. Production is the **richer** side. D's
added point is correct and worth keeping visible: a rebuild or restore **from this repository** would ship a
`handle_new_user` that silently stops populating `full_name`, `display_name` and `avatar_url`, and no repo
test would fail because the tests only know the repo's version. That is a **restore/DR and repo-baseline**
matter, not a #92 blocker.

## 3 · Verdict

### On the premise — **PASS.** #92's production premise holds.

### On proceeding to (A) — **STOP**, for one specific reason.

**The artefact that would execute (A) is not the artefact that was reviewed.** R0 showed that P3 as frozen
at `df5300eb` pinned the repo's *commented* prosrc, which production has never carried — so the frozen
package **would have stopped at P3**. A corrected this properly: re-pinned P3 to production's
`b7f11225…` / `c5ab888d…`, disclosed the change, and recorded the new script hash
**`8cbd950d40842e6eb9df383dd4e463bac8917729e30022b6db4e0a641a245b15`**.

The package's own contract is that any change to a frozen file means disclosure **and D review**. D's PASS
covers the **R0 result only** and says so explicitly:

> "Not yet reviewed by D: the P3 re-pin (`8cbd950d…`) and rehearsal 6. That review is requested, and
> execution of (A) waits for it."

So the STOP is **not** on the premise, **not** on R0's findings, and **not** on A's handling — all three are
sound, and the R0-first rule is vindicated, since it caught a P3 that would otherwise have failed opaquely.
It is a single open gate the package itself requires.

**Clearing it needs exactly one thing: D's review of the P3 re-pin and rehearsal 6.** On that review
passing, I have no further objection to (A) from this result.

## 4 · One observation, not a STOP reason

Neither A nor D establishes **why** production's two writer bodies carry no comments while 147's production
prosrc retains its own. A uses that asymmetry correctly to show 148's post values stay reachable, but the
provenance of the two comment-free bodies is unexplained. The behavioural evidence in strand 3 bounds the
risk, so this does not change the verdict — it is worth recording because the two functions concerned are
precisely the ones #92 depends on.
