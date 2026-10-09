# D — witness: test-mode exclusion approved, and review of the owner's live Stripe screenshots

2026-10-09. Owner authorised the exclusion and supplied two screenshots. **No writes, no deletions, no
relabelling, no settings changes.** D executed nothing.

## 1. The exclusion — witnessed

The owner approves excluding **five** payments from the live historical reconciliation, preserving the
records. The five, from D's own R0 read (`D_WITNESS_PRESENT_STATE_AND_R0_20261008.md` §4, not re-audited):

| # | payment | PaymentIntent | `stripe_livemode` | total | refunded_at (UTC) |
|---|---|---|---|---|---|
| 1 | `50f9a2e3` | `pi_3TFPZiGdOzCmGbHw1JOFjc65` | false | 15750 | 2026-03-29 22:01:25 |
| 2 | `d15dd918` | `pi_3TFRdxGdOzCmGbHw1sfT7nF6` | false | 7875 | 2026-04-01 20:25:53 |
| 3 | `4460d80f` | `pi_3THufwGdOzCmGbHw1ehCiZqd` | false | 3150 | 2026-04-02 23:35:02 |
| 4 | `49304db7` | `pi_3THuOyGdOzCmGbHw1nGe4nXM` | false | 2625 | 2026-04-03 23:15:02 |
| 5 | `e52c98e3` | `pi_3TpCE5GdOzCmGbHw1OWqPwF3` | false | 33000 | 2026-07-04 18:56:02 |

**Basis for the classification, and it is not the owner's say-so:** `payments.stripe_livemode` is
written from **Stripe's own `livemode` field**, never inferred — provenance traced in
`D_WITNESS_PRESENT_STATE_AND_R0_20261008.md` §8 (`create-payment-intent:1143-1147`,
`confirm-payment:274`), with the only later write gated on Stripe's own cross-mode error.

**What the exclusion means and does not mean:**
- It means: no `record_refund_state` call is made for these five; no row is written to
  `payment_refund_state`, `payment_refund_state_log` or `payment_refunds` for them.
- It does **not** mean deletion, relabelling, or any change to `stripe_livemode`. The rows stay exactly
  as they are. D has changed nothing.
- Their test-mode Stripe reads are withdrawn from this reconciliation's scope.
- Consequence to keep visible: these five continue to show as a legacy "refund recorded" with no
  refund-state row. If that display is ever a problem, the reversible fix is a `stripe_livemode` filter
  in the web/console reads — D's lane, not a money write.

## 2. The two live payments — owner-supplied screenshots, reviewed as such

**Status of this evidence:** owner-supplied screenshots of the live Stripe Dashboard. **Not D's own
Stripe read.** D has no access to that account (`captures_20261008/stripe_r1_wrong_account.*`).

### What the images show

| | image 1 | image 2 |
|---|---|---|
| amount | **$11.00 USD** | **$2.20 USD** |
| badge | Refunded | Refunded |
| charged to | gnvprod@gmail.com | gnvprod@gmail.com |
| refund activity | Aug 4, 5:20 PM | Aug 4, 5:20 PM |
| payment created | Aug 4, 2:17 AM | Aug 4, 3:26 AM |
| Payment ID (truncated) | `pi_3U0XuwGdOzCmGbHw0WVJ…` | `pi_3U0YzcGdOzCmGbHw0Z6l7b…` |
| refunded amount line | −$11.00, ARN `70000000000000000000001` | −$2.20, ARN `70000000000000000000001` |
| processing fees | −$0.62 | −$0.36 |
| note | "test" | "test 2" |

### Independent cross-check against D's own R0 read

The identity rests on more than the truncated prefix. D's R0 independently holds:

| our record | our `total` | our `refunded_at` (UTC) |
|---|---|---|
| `pi_3U0XuwGdOzCmGbHw0WVJfW3y` | **1100** | 2026-08-04 **17:20:05** |
| `pi_3U0YzcGdOzCmGbHw0Z6l7bf7` | **220** | 2026-08-04 **17:20:19** |

- Amounts agree: $11.00 ↔ 1100, $2.20 ↔ 220, and the **pairing** agrees — the larger amount sits on the
  `…0WVJ…` intent in both sources. Two differing amounts matching the right two intents is a real
  cross-check, not a prefix coincidence.
- Times agree at minute resolution: 17:20 UTC **is** 5:20 PM, so the displayed clock equals our recorded
  UTC minute for both.
- Both are `stripe_livemode = true` in D's own read — so **live mode is established independently of the
  screenshots, of the owner's statement, and of the notes.**

**The notes "test" / "test 2" are disregarded**, as the owner directed. They are free-text annotations
authored in the Dashboard; they carry no mode or provenance meaning, and the authoring account is not
evidence of origin either.

### What these images do NOT establish

Agreeing with the owner's own list, and adding one:

1. **The `re_` refund IDs.** The displayed **ARN is an Acquirer Reference Number** — a card-network
   reference for the money's path through the banking system. It is **not** a Stripe refund object id
   and must never be substituted for one.
2. **The refund object's status.** See §3 — this is the sharpest point.
3. **Full timestamp, year and timezone** of the refund object's own `created`. Our `refunded_at` is when
   *we* marked the payment refunded; it is not Stripe's refund `created`, and the two may differ.
4. **`failure_reason`**, if any.
5. **How many refund objects exist per payment** — *D's addition.* Each breakdown shows a single
   aggregate "Refunded amount" line. One line cannot exclude two partial refunds summing to the total.
   If a payment carries two refunds, R3 needs **one call per refund object**, each with its own `re_` id
   and amount. The activity feed shows one refund event each, which is suggestive but not conclusive.
6. **Provenance** — nothing in Stripe maps to our `source` taxonomy. Owner decision, per the package.

Also not established, and not to be claimed: that the customer's bank actually received the funds. The
dashboard text says it "may take a few days", which is a statement about intent, not receipt.

## 3. The badge is not the status — and this is the trap worth naming

`public.record_refund_state` (150:125-162) takes seven parameters and validates five:

| param | validation | established? |
|---|---|---|
| `p_payment_intent_id` | looked up; unknown → `recorded:false` | **yes** |
| `p_stripe_refund_id` | **`REFUND_REFERENCE_REQUIRED`** if null/empty (:148-150) | **NO — hard blocker** |
| `p_status` | must be `pending\|requires_action\|succeeded\|failed\|canceled` (:151) | **NO** |
| `p_amount_cents` | not null, ≥ 0 (:160) | **yes** — 1100 / 220, from the *Refunded amount* line |
| `p_failure_reason` | unvalidated, nullable | only matters if `failed` |
| `p_source` | `expiry\|dashboard\|admin\|unfulfillable` (:157) | **owner decision** |
| `p_observed_via` | `create_response\|webhook\|reconcile` (:154) | `reconcile` |

**The Dashboard's "Refunded" badge is the *payment's* status. It is not a member of the refund-object
enum at all.** A payment can display "Refunded" while the underlying refund object is still `pending`,
or has since `failed`. Distinguishing exactly that is **the entire purpose of migration 150**. So
mapping the badge onto `p_status` would write the very claim 150 exists to prevent, into two money
tables and an append-only log. The refund object's own status must come from the refund object.

The ARN's existence shows a reference was assigned for the network leg; D makes **no** inference from it
about refund-object status, and it is not a substitute for reading the status.

## 4. Genuinely missing evidence — routed to A, not issued as a second list

Per the owner's instruction, D does **not** send a checklist. D has sent A the five items in §2 plus the
`source` decision, for A's single consolidated request. All five are on the refund's **"View details"**
entry, which is where the owner suggested looking.

## 5. D's position on the correction package

When A's package arrives, D reviews it independently. Pre-stated so the review is falsifiable — D will
reject a package that:

- supplies an ARN where a `re_` id belongs;
- derives `p_status` from the payment badge rather than the refund object;
- assumes one refund per payment without evidence;
- carries a `source` that is a script default rather than the owner's recorded decision;
- writes anything for the five excluded payments.

Both live rows have no payout and no dispute (R0 §4b), so the after-payout branch cannot fire and the
chargeback exclusion does not apply. Hazard 1 has no member (ledger empty). Detection is **on**, so a
reconciled `failed`/`canceled` refund opens a p1 case within ~5 minutes — intended, and the owner works it.

Correction writes remain owner-gated. D has executed nothing.
