# D — independent review of A's O-R4 reconciliation package

Commits reviewed: **`77778156`** and **`d4accc39`** (docs + one rehearsal on top; SQL unchanged).
Date 2026-10-09. **No production writes. D executed nothing.**

## VERDICT: CONDITIONAL PASS

**All five of D's pre-registered rejection criteria are met.** Three residuals below, none a rejection;
one I would press for.

**Final approval is reserved and cannot be given now**, for a reason intrinsic to the artifact: both
proposed files carry three unfilled markers, so **the files reviewed are not the files that would run.**
Approval attaches to the completed files and their sha256s.

## 0. Correction to D's own earlier conclusion (owner-directed, and A reached it too)

D wrote: *"17:20 UTC is 5:20 PM, so the displayed clock equals our recorded UTC minute."* **Withdrawn.**
That holds **only if the Dashboard renders UTC**, which is not established — and the reasoning was
circular: the match was used to infer UTC, then UTC used to assert the match. A notes this Mac is UTC−4.

Sharper still: the two refunds are **14 seconds apart**, so under *any* fixed offset they fall in the
same displayed minute. "Both show 5:20 PM" therefore carries **zero** timezone information and cannot
corroborate anything.

**What survives:** identity rests on the **amounts and the pairing** — $11.00↔1100 on `…0WVJ…` and
$2.20↔220 on `…0Z6l7b…`, two different values landing on the right two intents. That is independent of
timezone. The timestamp corroboration is withdrawn entirely.

Also confirmed: `record_refund_state` takes **no timestamp parameter** (signature 150:125-132), so the
missing refund `created` does not block the write — it is provenance for the record only.

## 1. D's five criteria, each against the actual code

| # | criterion | verdict | basis |
|---|---|---|---|
| 1 | ARN substituted for a `re_` id | **MET** | `:34` `^re_[A-Za-z0-9]{10,64}$`; control C2 |
| 2 | `p_status` from the payment badge | **MET so far as code can** | `:37` accepts only `succeeded`; see §3 |
| 3 | one refund assumed without evidence | **MET conditionally** | `:43` `c_amount = c_total`; see §3 |
| 4 | `source` a script default | **MET** | `:24` marker + `:40` four-value check; a marker cannot default |
| 5 | writes touching the excluded five | **MET** | `:56` livemode guard; ids pinned `:17`,`:53`; mutant M1 |

## 2. Verified by D directly (not taken from A)

1. **sha256 of all three SQL files at both commits**: tmpl `97f1d0a1`, #6 `74cfe59a`, #7 `41372b17` —
   match A's claims. The **git blob OIDs are identical across the two commits** (`8a883288`, `0abf2411`,
   `2eeac212`), which is stronger than hash equality: the SQL is provably unchanged by `d4accc39`.
2. `d4accc39` touches only docs, SPRINT_STATUS and the new rehearsal — **no SQL change**.
3. The two generated files differ **only** in the header line and five record constants.
4. Those constants match **D's own R0** exactly: ids, PaymentIntents, totals 1100/220, `refunded_at`
   17:20:05 / 17:20:19 to the second.
5. Both files carry **3 unfilled markers** → neither runs as committed.
6. **Counted scan with positive controls**: no excluded-payment id (`3TFPZi`,`3TFRdx`,`3THufw`,`3THuOy`,
   `3TpCE5`) and **neither real ARN** appears in any of the three SQL files — all 0, while controls
   `record_refund_state`=3 and `pi_3U0Xuw`=2 prove the scan finds things.
7. **No phantom assertions.** `record_refund_state` returns `recorded, payment_id, refund_status,
   counted, stale_ignored, requested_cents, succeeded_cents, failed_cents` (150:243-252). Every key
   A asserts at `:111-115` exists.
8. **The asserted payment fields are really written.** `record_payment_refund` (`…120000`:517-522) sets
   `amount_refunded_cents`, `stripe_refund_id = coalesce(stripe_refund_id, …)`, `status` and
   `refunded_at = coalesce(refunded_at, now())`. So A's "`refunded_at` unchanged" assertion is
   **structurally guaranteed by the coalesce**, not merely observed in a rehearsal.
9. **Detector effects, derived from the predicates, not reported.** Loop 4 (150:357) fires on
   `failed|canceled`; loop 5 (150:382) on `pending|requires_action` **and** `first_observed_at` older
   than 120 h. A `succeeded` row matches **neither** → no case.
10. **`first_observed_at` is absent from the INSERT column list** (150:204-206), so it takes its default
    at reconciliation time. **The 120 h pending clock therefore starts at reconciliation, not at
    Stripe's `created`** — a refund pending since August would wait another five days. D reached this
    structurally; A reached it by rehearsal (O2t). Two independent routes, same conclusion.
11. **R4's case predicate is correct.** Refund cases are opened with `subject_id` NULL and
    `subject_ref` = the refund id (150:364, :389); R4's third clause matches `subject_ref` against the
    refund ids in `payment_refund_state`. Before R3 there are no state rows, so no refund case can be
    missed.
12. **Fixture fidelity.** `R2_fixtures.sql` seeds #6/#7 with their **real** ids, PaymentIntents, totals,
    `refunded_at`, `stripe_livemode = true`, `amount_refunded_cents` NULL, `stripe_refund_id` NULL, and
    one **reversed, unpaid** transfer each — matching D's R0 on **every field the script reads or
    asserts**. Detection is switched on to mirror production.

## 3. Three residuals — recommendations, not rejections

**(a) The refund-id regex validates shape, not origin.** `re_` followed by the ARN's 23 digits would
satisfy `^re_[A-Za-z0-9]{10,64}$`. The literal ARN is refused (C2), a hand-built `re_<ARN>` is not. Low
severity; the real control is that the owner copies the id from **View details**.

**(b) No guard can catch a badge-derived `succeeded` — this is irreducibly a process control.** The
script refuses every status except `succeeded`, but it cannot tell a `succeeded` read from the refund
object apart from one inferred from the payment's "Refunded" badge. They are the same four characters.
*Recommendation:* have the filled file record, in a comment, **where** the status was read from, so
approval-by-sha256 covers that provenance claim rather than leaving it in the request thread.

**(c) The single-refund fact lives outside the approved artifact — the one D would press for.**
`c_amount = c_total` refuses a *partial-sized* entry, but if two refunds exist and the filler enters the
total against one id, every guard passes. Evidence of "exactly one refund" sits only in the R1 request
and the README. *Recommendation:* add `c_refund_count constant integer := …;` with a guard refusing
anything but 1. Then the single-refund claim is **inside the sha256 the owner approves**, which is where
a load-bearing fact belongs. Cheap, and it closes criterion 3 completely rather than conditionally.

## 4. Taken from A, NOT verified by D — stated as the owner required

D did **not** run any rehearsal. D reviewed the **predictions and script logic**, not the execution.
Unverified by D and resting on A's reporting:

- R2 run 4 passing 24/24; the outcomes of mutants M1, M2, M3; the raw hazard-1 control; the
  failed-state positive control.
- R2b runs 1-2 and every cell of the O1-O7 outcome matrix, including the O2t backdating.
- That the rehearsal database is a faithful structural clone of production.
- A's harness-error accounts, including the statement-snapshot finding.

**Fixture limit D can state:** `amount` and `buyer_fee` in the fixtures are invented (1000/100 and
200/20). D's R0 never read those columns, so they are unverified against production — but no guard or
assertion in the R3 script reads them, so this does not affect the rehearsal's bearing on the write.
Seeding uses `session_replication_role = replica`; the calls under test run with triggers on, which A
documents and D confirms from the file.

## 5. Are the stated effects conditional on the missing details? Yes

The README's §R3 matrix is now per-branch (O1-O7), and the **script refuses every branch but O1**:
non-`succeeded` status raises "out of scope; stop and re-plan" (`:37`), and any amount ≠ total raises
(`:43`). So nothing about the production outcome is asserted unconditionally, and no revised script can
be run without its own rehearsal. This satisfies the owner's requirement.

**D adds one consequence the matrix should carry, and it corrects a likely expectation:** after a
*successful* R3 (branch O1), `ops.detect_refunds` still scans **2** and opens **0** — because a
`succeeded` row is selected by neither gated loop (§2.9). **So completing O-R4 will not demonstrate that
refund detection works.** The first such evidence still requires a genuinely pending or failed refund.
Anyone reading "reconciliation complete, detector clean" as validation of detection would be repeating
the vacuity recorded in `D_AUDIT_POST_O-R2_20261009.md` §1.

## 6. What D will check before final approval

On the completed files: that only the three markers changed; recomputed sha256s; that `c_status` is
`succeeded` and `c_amount` equals `c_total` and equals the R1 refund amount; that the `source` matches
the owner's recorded words; that the refund count is established as 1 (ideally in-file, per §3c); and
that `payment_refund_state` is still empty at execution time.

Correction writes remain owner-gated. D has executed nothing.

---

## 7. Re-check at `f7595be9` — all three residuals closed

A adopted all three §3 recommendations. D re-checked them against the code, not the description.

**Hashes, D's own:** tmpl `7740700b`, #6 `0d689587`, #7 `d976eacb` — match A's claims. Five distinct
markers now present in each proposed file (`__R1_REFUND_ID__`, `__R1_REFUND_STATUS__`,
`__R1_REFUND_COUNT__`, `__R1_EVIDENCE__`, `__OWNER_SOURCE__`), so the files still cannot run as
committed.

**Placement:** all three new guards sit in section 1, at lines 38-45, **before the first database read**
(`select * into v_pay` at :59). Correct — an unfilled or out-of-scope input stops the block before it
touches a row.

**Behaviour, probed case by case:**

| guard | input | result |
|---|---|---|
| C11 | `__R1_REFUND_ID__` | REFUSED |
| C11 | bare ARN `70000000000000000000001` | REFUSED |
| C11 | `re_70000000000000000000001` (ARN with prefix) | **REFUSED** ← the gap D raised |
| C11 | `re_3Q7xK2GdOzCmGbHw0abcdef` (realistic id) | accepted |
| C10 | `__R1_REFUND_COUNT__`, `2`, `01`, `` ` 1` `` | REFUSED (strict text equality) |
| C10 | `1` | accepted |
| C12 | `__R1_EVIDENCE__`, `short` | REFUSED |
| C12 | a real provenance sentence | accepted |

The C12 marker check is `c_evidence like '\_\_%'`, which under PostgreSQL's default backslash escape
matches a literal leading `__`. Correct.

**(c) is fully closed.** `c_refund_count` is inside the file, so the single-refund claim is now covered
by the sha256 the owner approves. D's criterion 3 moves from *conditional* to **met**.
**Stated precisely, because this matters:** the guard puts the claim *inside the approved artifact*. It
does **not** verify the count against Stripe. It is a recorded assertion under signature, not a
measurement — which is exactly what D asked for, and should be described that way and no stronger.

**Two residuals remain, both minor, neither a blocker, and D is not pressing further:**
- **C11 is still shape-only.** `re_a70000000000000000000001` — one letter prepended — is accepted.
  A acknowledges origin is not guard-checkable; C12 is the compensating control. Noted and accepted.
- **C12 accepts 20 spaces.** `length >= 20` and "not marker-prefixed" are satisfied by whitespace.
  Optional polish (require a non-whitespace character); D does not ask for it. The evidence string is
  echoed in the `R3_OK` notice and falls under the approved sha256, so a blank one would be visible.

**Not checkable here:** A reports "W6/W7 differ from the committed files in exactly 5 lines". Those
filled rehearsal variants are not committed, so D cannot verify that claim. Separately, D measured the
committed #6 as differing from `d4accc39` by **15 changed lines** (net +11) — a *different* comparison,
not a contradiction of A's statement.

**Still A's, unverified by D:** R2 run 5 passing 27/27, and that M1-M3 still kill.

## 8. D accepts A's narrower timezone wording

A kept "conditional" where D said "zero". **A is right and D over-generalised.** Two distinct
propositions:

- **The shared minute carries no timezone information.** Both refunds are 14 s apart, so under *any*
  fixed offset they display in the same minute. This remains **zero** — and it is all D's original
  sentence was entitled to say.
- **The displayed value against our record is conditionally consistent.** "5:20 PM" equals 17:20 **if**
  the Dashboard renders UTC and our `refunded_at` is close to Stripe's `created`. That is a real, if
  unverified, conditional — not nothing.

D's error was applying the first proposition's "zero" to the second. A's wording stands; D's is
withdrawn to the narrower claim.

## 9. Verdict at `f7595be9`

**CONDITIONAL PASS, unchanged in kind — all five criteria now met outright**, criterion 3 having moved
from conditional to met. Final approval still reserved for the filled files and their sha256s, which D
will check per §6.
