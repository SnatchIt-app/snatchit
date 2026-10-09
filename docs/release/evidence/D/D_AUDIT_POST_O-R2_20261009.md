# D — independent audit after the console deployment and O-R2, 2026-10-09

All reads below are **D's own**, from the SSD, read-only, under the owner's standing authorisation for
these reads. Where a fact is A's or the owner's, it is labelled.

**Already settled, not re-audited** (per the owner's instruction to avoid duplicate audits): the console
deployment and the superseded-redeploy reconciliation are in `D_WITNESS_PRESENT_STATE_AND_R0_20261008.md`
§1; R0 is in §4; the mode boundary in §9. Nothing below revisits them.

## 1. The headline finding: the detector runs prove nothing about refund-state detection

A characterised the first tick as "it ran over 0 refund-state rows, so it is not detection evidence."
Directionally right. The measured form is **stronger**, and it is the point that matters:

| window | runs | `items_scanned` min | max | `cases_opened` |
|---|---|---|---|---|
| 24 h **before** the flip (detection OFF) | **288** | **2** | **2** | 0 |
| since the flip (detection ON) | **256** | **2** | **2** | 0 |

**The detector's output is identical on both sides of enabling detection** — `items_scanned` is exactly 2
in all **544** runs, and zero cases either side. So the clean runs cannot even establish that the flag
changed the detector's behaviour. The observation is **indistinguishable from the flag being off.**

### Why — structural, read from `ops.detect_refunds()` at gate `abef9506` (blob `b7ef57fa`)

The function has five loops; four increment `v_scanned`:

| loop | lines | scans | gated? |
|---|---|---|---|
| 1 | :277-302 | `public.transfers` | **no** |
| 2 | :306-318 | `ops.action` | no (does not count) |
| 3 | :320-344 | `ops.action` w/o a refunded payment | **no** |
| 4 | :352-375 | `public.payment_refund_state` | **yes — `if v_state_on`** |
| 5 | :377-398 | `public.payment_refund_state` | **yes — `if v_state_on`** |

`v_scanned` counts **loop iterations across four sites**, not rows of one table. The constant 2 comes
from the two **ungated** loops. The two loops the O-R2 flag enables iterate over
`payment_refund_state`, which holds **0 rows** (D's read), so they contribute nothing — and an empty
`FOR` body never increments. Hence the identical before/after figures.

**Compounding this:** `detect_refunds` records nothing about whether the gated branch ran. Contrast the
sibling detector `refund_resolution`, which logs `{"reason": "refund_resolution_disabled"}` on every
skip — a signal that *does* discriminate. So for refund-state detection there is **no observable signal
in `ops.job_run` either way**.

**Conclusion, stated as the owner required:** zero new cases is not evidence that failure detection
catches real refund failures. Here it is not even weak evidence — it is **no** evidence. The new logic has
never executed against a single row. The first genuine evidence can only come from a real refund webhook
delivery or an authorised R3 write.

### Proposed hardening (D's lane, not done)

Have `detect_refunds` include `state_on` (and ideally a row count) in its returned `detail` jsonb, as
`refund_resolution` already does for its skip reason. One small change, and it converts a run log that
proves nothing into one that proves the branch executed. Offered for the register; no code written.

## 2. The execution / detection boundary — verified, and there are TWO refund detectors

All 14 `ops.setting` rows read directly:

| key | value | last changed |
|---|---|---|
| `refund_state_detection_enabled` | **true** | 2026-10-08 23:54:39 ← the authorised flip |
| `refund_execute_enabled` | **false** | 2026-09-08 (untouched) |
| `alert_delivery_enabled` | **false** | 2026-09-23 (untouched) |
| `refund_resolution_detector_enabled` | **false** | 2026-09-23 (untouched) |
| `detectors_enabled` | true | 2026-09-08 |
| `actions_enabled` | true | 2026-09-08 |

The distinction the owner asked to preserve holds on D's own read: **detection on; execution off; alert
delivery off.** Only the one authorised key moved.

**Worth surfacing:** `refund_resolution_detector_enabled` is a **second, separate** refund detector and
it is still **false** — confirmed live by its 256 `skipped` runs with reason
`refund_resolution_disabled`. Enabling O-R2 enabled one of the two. If the owner believed "refund
detection" was now wholly on, it is not.

**Also:** `cron_job_first_seen` lists live cron jobs `refund-execute-tick` and `payout-execute-tick`.
These tick on schedule and are held **only** by their flags — the restraint is a setting, not the absence
of a job.

## 3. Cases and alerts since the flip

| | total | since the flip |
|---|---|---|
| `ops.case` | 21 | **0** |
| `ops.alert` (by `last_fired_at`) | 17 | **0** |

Nothing opened, nothing fired. Consistent with §1 and with `alert_delivery_enabled = false`.

## 4. Owner sign-in — previously A's report plus owner statement, now witnessed by D

Read from `auth` with **non-secret columns only** (no factor secret was selected or exposed):

| object | value |
|---|---|
| `auth.users` for `gnvprod@gmail.com` | id `2b117757…`, `last_sign_in_at` **2026-10-08 23:48:03.098908+00** |
| `auth.mfa_factors` | `e677717c…`, **`verified` / `totp`**, updated 23:48:42.431932+00 |
| `auth.mfa_challenges` | `fdc3ac8a…` on factor `e677717c…`, **`verified_at` 23:48:42.971644+00** |

Matches A's reported timestamps exactly. **And it closes a chain neither A's report nor the owner's
statement established on its own:** the account that performed the money-adjacent setting change
(`ops.action.requested_by = 2b117757…`, 23:54:39) is the same account that signed in at 23:48:03 and
completed a **verified TOTP challenge** at 23:48:42 — six minutes before the change. Actor, MFA and
change are now linked by direct observation rather than by report.

## 5. Remaining evidence gaps

1. **Refund-state detection has never run against data** (§1). No evidence it works. Blocked on a real
   refund or an authorised R3 write — not on anything D can do.
2. **The rendered console UI on the deployed build.** D verified the deployment, commit, build duration
   and alias from Vercel metadata. D has **not** viewed the authenticated console, so "the reviewed
   labels render correctly in production" is unverified.
3. **The rendered web wording on the authenticated pages** (`/account/purchases`, `/account/sales`, one
   transfer screen) — unchanged long-standing gap; needs a signed-in session.
4. **R1, the live Stripe read** on the two live-mode records — owner-only; D's CLI is bound to a
   different account (`captures_20261008/stripe_r1_wrong_account.*`).
5. **Whether any of the five test-mode rows was quarantined** — recorded only via Sentry
   (`legacy_test_record: true`); D cannot read Sentry.

## 6. Evidence limits on this audit

- The before/after comparison in §1 uses `ops.job_run` as the instrument. It discriminates on other
  dimensions in the same data — `refund_resolution` shows `skipped` vs the others' `succeeded`, and
  `items_scanned` varies across detectors (0 / 2 / 3 / 5 / 8 / 14 per run) — so a constant 2 for
  `refunds` is a real constant, not a column that never changes.
- §4 does not establish *which* session performed the console action, only that the same user id signed
  in with verified TOTP six minutes earlier. A distinct unattested session by the same account is not
  excluded by this read.
- No claim is made that the console build serves the reviewed tree beyond Vercel's own commit metadata.
