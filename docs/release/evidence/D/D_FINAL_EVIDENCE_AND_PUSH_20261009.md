# D — final refund evidence, reconciliation status, and the branch push

2026-10-09. Owner supplied final screenshots and authorised the branch push. **No production writes.**

## 1. The "View details" page does not contain what was asked for

The owner's final screenshots show the **Refund details** modal for both refunds. It contains, in full:

- heading "Acquirer Reference Number (ARN)"
- "Share this reference with your customer to help them trace the refund at their bank."
- the ARN value
- "Made available 8/5. It may take 5-10 business days for funds to settle."
- a Dismiss button

**That is the entire modal.** It carries **no** `re_` refund id, **no** refund-object status, **no**
refund count, **no** year or timezone, **no** failure reason.

So the consolidated request A sent — and the five items D supplied for it — rested on an assumption
about what that page contains. **The owner has now demonstrated the assumption was wrong.** The fault is
ours, not a failure by the owner to look properly, and the request must not be repeated.

## 2. What the authorised production read DID establish — new, and material

Before recording anything as unavailable, D searched the authorised source. `public.stripe_webhook_events`
exists (31 rows; a dedupe ledger: `event_id`, `event_type`, `received_at`, `processed` — **no payload**).

**Exactly three `charge.refunded` events exist in all of production history:**

| event id | received (UTC) | processed | matches |
|---|---|---|---|
| `evt_3U0XuwGdOzCmGbHw0QThD7ya` | 2026-08-04 **17:20:05.136** | true | record #6 `pi_3U0Xuw…` |
| `evt_3U0YzcGdOzCmGbHw0fSVw1MJ` | 2026-08-04 **17:20:19.342** | true | record #7 `pi_3U0Yzc…` |
| `evt_3TpCE5GdOzCmGbHw1JQEDVWe` | 2026-07-04 18:56:03.947 | true | an **excluded** test-mode row |

The event ids share the PaymentIntent core (`3U0Xuw`, `3U0Yzc`), tying them unambiguously to our two
records. Their `received_at` matches our `refunded_at` to within **29 ms and 11 ms** — so our
`refunded_at` was set by processing these very webhooks.

**This establishes two things not previously established:**
1. **A refund object exists for each**, created at those timestamps, and Stripe said so — not inferred
   from the "Refunded" badge.
2. **Refund count = 1 each, on substantive evidence.** `charge.refunded` fires per refund, so two
   refunds would produce two events. There is exactly one per payment, and the Dashboard breakdown
   shows the refunded amount equalling the full payment. *Limit:* this ledger records events we
   **received**; an undelivered or unrecorded second event would not appear. Strong, not conclusive.

**And one absence, stated with its limit:** the ledger holds **no `refund.*` event ever**, for any
payment. That is consistent with no refund having failed — but A's G3 could not date when `refund.*`
became subscribed, so the absence is **not** proof. It is not evidence of `succeeded`.

## 3. Reconciliation status: PENDING EVIDENCE

| field | status |
|---|---|
| `p_payment_intent_id` | established |
| `p_amount_cents` | established (1100 / 220) |
| `p_observed_via` | `reconcile` |
| **refund count** | **established as 1 each** (§2) |
| **`p_stripe_refund_id`** | **NOT AVAILABLE — hard blocker** |
| `p_status` (refund object) | NOT established |
| `p_source` | owner decision, outstanding |

`record_refund_state` raises `REFUND_REFERENCE_REQUIRED` without the `re_` id (150:148-150), so
**reconciliation cannot proceed.** Recorded as **pending evidence**; production unchanged; the five
test-mode rows remain excluded and untouched. Per the owner's instruction this is **not** presented as
blocking anything else — it blocks only the O-R4 writes, which were already separately gated.

The `re_` id is not obtainable from any source D can reach: it is absent from `payments`,
`payment_refunds`, `payment_refund_state`, the webhook ledger (no payload), `ops.action.result` (0) and
`notifications.metadata` (0), and D's Stripe CLI is bound to a different account. **No further owner
screenshot would supply it either — it is not on that page.** The only routes that would are a
read-only API key on the correct account, or a Dashboard refund export. Noted as options; **not** a
request, and nothing else waits on it.

## 4. The negative-balance notice — recorded as shown, nothing more

The 5:56 PM `$2.20` screenshot shows a popover: **"Add funds in USD to cover your negative balance."**
That is the whole content. **No amount, no cause, no current balance, and no date is shown.** D asserts
nothing further and no funding action is authorised or implied. It appears on that screenshot only.

## 5. Owner sign-in — the waiver, recorded precisely

The owner waives the repeat sign-in session. Two different things, and they should not be merged:

- **The sign-in event itself is NOT merely owner-reported — D verified it directly** from `auth`
  (`D_AUDIT_POST_O-R2_20261009.md` §4): `last_sign_in_at` 2026-10-08 23:48:03, TOTP factor `e677717c`
  **verified**, challenge verified 23:48:42, and the 23:54:39 setting change made by that same user id.
- **Waived and never verified by anyone:** the authenticated-flow and rendered-wording checks — the
  console labels on the new build, and `/account/purchases`, `/account/sales` and a transfer screen.
  These are **waived, not passed.** No record may later describe the wording as verified.

## 6. Branch push — three of four pushed; one held, with cause

**The check the owner required found a genuine exposure.** `gh repo view` reports
`SnatchIt-app/snatchit` is **PUBLIC** (`isPrivate: false`).

A first scan appeared to show the deltas clean. **That scan was broken** — `git grep` with
`--pathspec-from-file` silently matched nothing, and a positive control proved the ARNs were present in
files it had just called clean. Re-run by intersecting whole-tree hits with the changed-file list, with
a method control. Result:

- every other flagged file (`eas.json`, `admin/.env.local.example-harness`, the test files, the
  governance docs) is **already public with an identical blob** on
  `origin/release/production-gate-20260918`, so the push adds nothing; and the JWT hits are Supabase
  **anon** keys, which CLAUDE.md classes as public;
- **D's two newest records carried the two real ARNs**, which A had deliberately kept out of this public
  repo.

**Redacted** at `bab4060b`: both ARNs replaced with A's synthetic `70000000000000000000001` (the guard
probes keep their meaning, since the property under test is an all-digit suffix), and the sandbox
Stripe account id truncated. Verified 0 real ARNs remain in the worktree, with the synthetic as control.

**But a redaction in a new commit does not remove anything from history.** Three earlier commits —
`fbe41284`, `addd4670`, `8ba6cef7` — still contain the real ARNs, and **those are exactly the shas A
cites in their records.** Pushing the branch would publish them; rewriting history would break A's
citations.

**So:**

| branch | local | remote | state |
|---|---|---|---|
| `web/wording-truth-conditions` | `e7130f046a62` | `e7130f046a62` | **pushed, MATCH** |
| `admin/label-console-release` | `1058c8825b97` | `1058c8825b97` | **pushed, MATCH** |
| `review/d-integ-94-95` | `486c954cd918` | `486c954cd918` | **pushed, MATCH** |
| `review/d-records-20261005` | `bab4060b6a63` | — | **HELD — needs an owner decision** |

Remote heads verified by `ls-remote`, independently of the push output. All three were history-scanned
for both ARNs across their last 40 commits: **0 hits**, with the records branch returning 4 as control.

**The owner's choice on the records branch**, neither option taken unilaterally:
1. **Publish as is** — accepts two real ARNs in public history. They are card-network refund
   references, not credentials; the exposure is real but bounded.
2. **Rewrite the three commits** to remove them, then push — breaks the shas A cites; A would need to
   re-point its references.
3. **Leave it local** — the records stay on the SSD and the retained Mac copy, with no remote backup.
   This is the current state.

D recommends **2** if the records are wanted on GitHub, since the citations are easy for A to re-point
and the ARNs then never reach the public repo at all. D has not done it.

## 7. Trial branch — D's dependency, answering A

`D_WITNESS_W0_S1S2_20261008.md` **does cite `3787d8a2`**. It does not cite `229df83c`.

D does **not** object to deleting the remote branch. A's uniqueness finding matches D's own earlier
replay: the trial's trees (`5b9cca0d`, `2e2c31b4`) equal the gate's, so **no content is unique to it**.
Once the remote branch is gone the sha will not resolve on GitHub; D accepts that, because the record's
claim is about tree equality, which remains checkable against the gate. Nothing of D's needs it
resolvable remotely.

---

## 8. Authorisation basis for D's production reads — stated for the owner's ruling

A cannot confirm which approval D's reads rest on and has referred it to the owner. Correct to ask.
D states it plainly rather than assuming coverage.

**Squarely covered by an explicit instruction:**

| read | basis |
|---|---|
| `payments`, `transfers`, `payment_refunds`, `payment_refund_state`, `payout_attempts/decisions` | "I authorise the two prepared historical reconciliation reads: the database read and the Stripe read" (R0) |
| `ops.setting` (all 14 rows) | "Independently verify the current deployment, setting and audit entries" |
| `ops.action`, `ops.audit` | same — "audit entries" |
| `ops.job_run`, `ops.case`, `ops.alert` | same instruction's "expected detector effects"; counts only |
| `auth.users`, `auth.mfa_factors`, `auth.mfa_challenges` | "Independently verify the remaining unwitnessed points using already-authorised read-only access"; **timestamps and status only — no factor secret was selected** |

**Beyond the R0 query spec, and therefore the item needing a ruling:**

- **`public.stripe_webhook_events`** — not named in the package's R0 list. D read `event_id`,
  `event_type`, `received_at`, `processed`. No payload column exists; no customer data was returned.
- **`ops.action.result` and `public.notifications.metadata`** — probed for the string `re_`; **count
  only**, both returned 0, with a row-count control.
- `information_schema` — schema metadata, not data.

**The basis D relied on** is the owner's instruction in the final-screenshots message: *"Use everything
supplied and **any existing authorised read-only evidence** to establish the refund details."* D read
that as authorising read-only search of the already-authorised production database to establish those
details, rather than only re-using rows already fetched. **That phrase is open to the narrower
reading**, and if the owner intends the narrower one, this read was out of scope and should be recorded
as such. All of it was `SELECT` only; nothing was written, and the findings in §2 came entirely from
`stripe_webhook_events`, so a narrower ruling would also withdraw the refund-count evidence.

## 9. A's deletion and D's pushes, verified by D

- `integration/s1-s2-trial-20261007` on origin: **0 refs**. Control: the gate returns **1**, so the
  check discriminates.
- `3787d8a2` still resolves **locally** (`git cat-file -t` → `commit`), so D's citation in
  `D_WITNESS_W0_S1S2_20261008.md` remains checkable on this machine, as A arranged.
- D's three pushed branches remain at `e7130f046a62`, `1058c8825b97`, `486c954cd918`.

## 10. D agrees with A's decision not to fill `REFUND_COUNT`

Correct, and worth stating as a rule rather than a one-off: filling some markers while others remain
unavailable would produce a half-filled file with a **stable sha256** that could later be mistaken for
an approvable artifact. The markers should move from unfilled to filled in a single step, once all five
values exist. The refund-count *evidence* belongs in the README and in this record; the *file* stays
untouched.
