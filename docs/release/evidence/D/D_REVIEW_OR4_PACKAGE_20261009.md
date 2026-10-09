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
