# D's expectations for A's frozen 150/151 deployment package

**Registered 2026-10-05, before the package was delivered.** Nothing in A's package had been read when
this was written: at registration the only 150/151 artefacts D had seen were PR #94 @ `2eebc5bf` and
PR #95 @ `9a66f29d` (reviewed 2026-09-25, D PASS) and the integration plan's §5.2 X1–X4. This file is
committed so the registration cannot later be adjusted to fit what arrives.

The owner named five things to check: **migration/deploy ordering, webhook subscription timing,
rollback boundaries, detection activation, and the handoff for failed refunds.** Operational decisions
stay visibly pending; D does not choose them.

Each expectation is falsifiable: it says what D will look for and what would count as failing it.
A PASS requires every **blocking** expectation met. An unmet **non-blocking** expectation is recorded,
not a stop.

## A. Ordering (blocking)

- **E-1.** 150 is applied **before** the #94 functions are deployed. The new `stripe-webhook` and
  `enforce-transfer-expiry` call `record_refund_state`, which 150 creates. *Fails if* the sequence
  deploys first, or leaves the order to the operator.
- **E-2.** For the source, **#94 merges before #95** — migrations-guard rule 4 (scheme-aware monotonic
  ordering) rejects `20260925000000` added above an existing `20260925010000`. *Fails if* the package
  implies either order is fine.
- **E-3.** The apply is a **targeted per-file apply** — the file, its ledger row, and a read-back —
  never `supabase db push` against production (C7). *Fails if* `db push` appears in any production step.
- **E-4.** The frozen migration blobs equal the reviewed ones: `20260925000000_refund_lifecycle_state.sql`
  as at `2eebc5bf`, `20260925010000_release_stuck_seller_win.sql` as at `9a66f29d`. D compares by blob
  id, not by filename. *Fails if* either differs without a re-review.
- **E-5.** 151's apply is stated as **independent** of 150, and constrained only by "before the first
  seller-win resolution" (C5). *Fails if* the package couples them unnecessarily.

## B. Pre-state and read-back (blocking)

- **E-6.** The apply refuses unless the starting state matches: **no ledger row** for the version, and
  the objects 150 creates **absent**. A guard that only warns is not a guard. *Fails if* the script
  proceeds on a mismatch.
- **E-7.** Expected ledger counts are **recorded before** the apply: 162 → 163 (150) → 164 (151).
  *Fails if* the expected value is written after the read.
- **E-8.** Post-apply read-back covers: the ledger row and its `created_by` tag, the new objects'
  presence, the function body hashes, the grants matrix, the Gate-2 census, and the `ops.setting`
  switches. *Fails if* any is absent.
- **E-9.** Census figures quoted are the **gate's**, 32|108|37|38 at `037092f0` and 34|111|37|40 after
  #94 merges — not the candidate branch's stale 31|96|37|35. *Fails if* the candidate's numbers appear.

## C. Compatibility with what is already deployed (blocking)

- **E-10.** The package shows that **150 does not redefine `record_payment_refund`**, the writer the
  deployed v41/v42 call, with the check rather than the assertion (C2).
- **E-11.** The three new `payments` columns are `NOT NULL DEFAULT 0` behind a writer-only guard, so
  the deployed functions are unaffected between the apply and the deploy.
- **E-12.** The deploy step names **only** the functions whose source changed in #94, with a
  post-deploy download-and-compare against the frozen commit, as was done for v41 and v38. *Fails if*
  an unchanged function is redeployed silently, or no download comparison is recorded.

## D. Webhook subscription timing (blocking that it is *deferred*, not that it is done)

- **E-13.** The Stripe `refund.created` / `refund.updated` / `refund.failed` subscription (O-R1) is
  sequenced **after** the new `stripe-webhook` is live, and is left as a **pending owner action** —
  the package must not perform it or assume it.
- **E-14.** The package states why that order is safe: the deployed v42 acknowledges unknown events and
  discards them, so subscribing early would lose events rather than break anything, and subscribing
  late loses nothing already recorded.
- **E-15.** The package records that **Stripe's webhook configuration has never been read** (G3 open),
  so "charge.refunded is subscribed" remains a source-derived claim, not an observed one. *Fails if*
  the package treats the current subscription list as established.

## E. Detection activation (blocking)

- **E-16.** `refund_state_detection_enabled` is **seeded false by 150**, and no step in the package
  flips it. Turning it on is O-R2, a separate owner decision.
- **E-17.** The package states what happens on activation — which detector branches arm, and what a
  first run would open — so the owner is deciding with that in front of them, not after.
- **E-18.** 151's detector (`ops.detect_release_stuck`) is checked for whether it is **live on apply**
  or behind a switch, and the package says which. 145 is the precedent for a detector that is live on
  apply with no switch of its own.

## F. Rollback boundaries (blocking)

- **E-19.** 150 has a **guarded** rollback: it refuses, rather than silently dropping data, once
  `payment_refund_state` or its log holds rows. If it does drop them, the package says so in those words.
- **E-20.** The rollback restores the **applied** pre-150 `ops.detect_refunds` body — the 118 body as
  it exists in production — with its expected md5 recorded, not an older baseline.
- **E-21.** The package states the **ordering boundary explicitly**: once the new functions are
  deployed and writing through `record_refund_state`, rolling 150 back breaks them, so a rollback after
  the deploy is functions-first, migration-second. *Fails if* the rollback is presented as always
  available.
- **E-22.** 151's rollback restores whatever it redefines, byte-verified, and the package names the
  objects.

## G. Failed-refund handoff (blocking that it stays open)

- **E-23.** **O-R3 — who contacts a buyer whose refund failed — is left visibly undecided.** The
  package must not pick an answer, and must not ship buyer-facing failure copy that presumes one
  (WT §2i: the failure copy waits on O-R3).
- **E-24.** The package says what happens to a failed refund *in the absence of a decision*: the row is
  parked with `refund_failed_cents > 0` and nothing contacts anyone. That is the state the owner is
  being asked to accept for the interim, so it must be stated, not implied.
- **E-25.** No surface is changed in this package to describe a failed refund. The interim wording stays
  at ruling 3's ceiling.

## H. Authorisation and scope (blocking)

- **E-26.** Every production step carries a **separate** owner authorisation point. One approval does
  not cover the sequence.
- **E-27.** A fresh `AUTODEPLOY-VERIFIED-OFF` confirmation is required for the **`main` merge**, and the
  package does not claim it is required for a targeted apply (it is not — the integration fires on a
  push to `main`). *Fails if* the two gates are conflated in either direction.
- **E-28.** O-R1, O-R2, O-R3 and O-R4 each appear as a decision with **no default taken**.

## I. Evidence quality (non-blocking, recorded)

- **E-29.** A negative control for pgTAP 217 and 218: the new tests fail on the pre-fix tree, with the
  failing set named in advance.
- **E-30.** Where the package quotes a count, it says whether it was measured in this round or carried
  from a record.

## What D will compute independently, not read from the package

- The two migration blob ids, against the PR heads.
- The LC_ALL=C position of both files relative to the ledger's last row, and therefore the insertion
  order the apply produces.
- Whether 150 redefines `record_payment_refund` (grep of the migration, not of the summary).
- The census deltas, from the gate's `ci.yml` at the frozen commit.
- The set of functions whose source differs between the frozen commit and the deployed versions.

## Evidence limits that will apply to any verdict

- D makes **no production read** under the current authorisation. Every statement about production
  state rests on recorded read-backs, and D's verdict will say so.
- A PASS covers the package as written and rehearsed. It is not evidence that the refund path has run
  against a real failed refund in production, and D will say that in the verdict.
