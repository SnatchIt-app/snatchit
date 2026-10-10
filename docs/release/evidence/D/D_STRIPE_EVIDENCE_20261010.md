# D — independent Stripe + production reads: the blocker is cleared

2026-10-10. Owner authorised read-only Stripe and production queries; A leads collection, D checks
independently. **D collected blind — before reading A's results — so the comparison is a check, not a
confirmation.** Reads only. No writes, refunds, payouts, settings or deployments.

## 0. Account identity, established before trusting any field

`list_available_accounts_or_orgs` → **`acct_1T6FarGdOzCmGbHw`, `livemode: true`, "SNATCH IT"**.
It carries the `GdOzCmGbHw` core shared by both PaymentIntents and the webhook endpoint. D's earlier
CLI was bound to `acct_1T6Fb1GlD5aqtxIw` (sandbox) — a different account. This matters because a clean
"no such object" from the wrong account is indistinguishable from a genuine absence.

## 1. The refund objects — the hard blocker is cleared

`GET /v1/refunds?payment_intent=…&limit=100`, both returning **`count: 1`, `has_more: false`**.

| field | record #6 | record #7 |
|---|---|---|
| **refund id** | **`re_3U0XuwGdOzCmGbHw0bL9UYzT`** | **`re_3U0YzcGdOzCmGbHw0Av5k7ZH`** |
| **status** | **`succeeded`** | **`succeeded`** |
| amount / currency | **1100** / `usd` | **220** / `usd` |
| created | 1785864002 → **2026-08-04 17:20:02Z** | 1785864018 → **2026-08-04 17:20:18Z** |
| `reason` | `null` | `null` |
| `failure_reason` | **absent** | **absent** |
| `metadata` | **`{}`** | **`{}`** |
| ARN (`destination_details.card.reference`) | `87021306217500064533475` | `87021306217500065910060` |
| `reference_status` | `available` | `available` |
| charge | `ch_3U0XuwGdOzCmGbHw0jHL2NZu` | `ch_3U0YzcGdOzCmGbHw0WOgATJm` |

**Both ARNs match the owner's screenshots exactly.** That is an independent confirmation of identity
that does not depend on the truncated PaymentIntent prefixes — the screenshots were of these refunds.

### Refund count: now CONCLUSIVE, upgraded from "strong, not conclusive"

`count: 1` with `has_more: false` on the authoritative list, per payment. The earlier determination
rested on indirect evidence (one `charge.refunded` each, one activity row, full-amount refund). Stripe's
own refund list settles it. **One refund per payment.**

### Status: `succeeded`, read from the refund object

Not from the payment's "Refunded" badge. This is the distinction migration 150 exists to preserve, and
it now rests on the right field. **Branch O1 applies**; no revised script is needed.

## 2. Live mode — externally validated

Both PaymentIntents return **`livemode: true`** from Stripe, as does charge `ch_3U0Xuw…`. Our
`stripe_livemode` column is now confirmed against the source rather than trusted. The five excluded
test-mode rows remain excluded and untouched.

## 3. The charge, completing the picture (#6)

`amount 1100`, `amount_captured 1100`, **`amount_refunded 1100`**, **`refunded: true`**,
**`disputed: false`**, `dispute: null`, `status succeeded`, card `mastercard` ending **9507** — matching
the screenshots. No dispute, so the chargeback exclusion does not apply.

## 4. Origin — partial, and the unknown left explicit

**`metadata: {}` on both refunds, `reason: null`.** The refund-creating path D has read
(`enforce-transfer-expiry`) always sets metadata — `metadata[reason]=transfer_expired`,
`metadata[source]=enforce-transfer-expiry-selfheal`. **Empty metadata is inconsistent with that path
having created these refunds**, which points to manual creation in the Dashboard.

**D stops short of calling it.** That is one code path, not all of them; A is comparing against every
refund-creating path and owns that conclusion. Stripe's events API retains 30 days, so the August
request source is gone. **`p_source` remains the owner's decision**, now better informed but not
determined by evidence.

**Relevant to the decision:** both PaymentIntents carry `metadata.buyer_id =
2b117757-f4e3-41c1-b7df-68a4502d0fba` — **the owner's own user id**, the same account that signed in
and flipped the O-R2 setting. The buyer on both refunded payments was the owner. No third party is owed
anything by these two records.

## 5. The full webhook event list — closes a precondition that was logged OPEN

`GET /v1/webhook_endpoints` returns **one** endpoint, `has_more: false`:
`we_1TCqy5GdOzCmGbHwxBkCHKL2`, **status `enabled`**, `livemode: true`, api_version `2026-02-25.clover`,
url `https://hqycwntpfoztoinemqns.supabase.co/functions/v1/stripe-webhook`.

**All 13 enabled events, read directly:** `payment_intent.succeeded`, `payment_intent.payment_failed`,
`charge.dispute.created`, `charge.dispute.closed`, `account.updated`, `charge.refunded`,
**`transfer.created`**, **`transfer.reversed`**, `payout.paid`, `payout.failed`, `refund.created`,
`refund.failed`, `refund.updated`.

The owner's screenshot showed 11 of 13; **the two below the cut were the two transfer events.** The
three refund events are confirmed subscribed. **O-R2 precondition (b) — the complete event list — is
now satisfied by direct read**, having stood open since it was raised.

## 6. The ledger gap — resolved, and it is benign

**Finding: the ledger did not stop working. There has been nothing to record.**

- `GET /v1/events` (Stripe retains ~30 days) returns **an empty list**. No events exist in the window.
- Live PaymentIntents created **after the ledger's last entry (2026-08-05 23:39:41Z)**: **exactly 2** —
  `pi_3U1PqtGdOzCmGbHw0Z8gQwFa` (2026-08-06 11:52:47Z, 220) and
  `pi_3UBboOGdOzCmGbHw0His3fPh` (2026-09-03 14:40:20Z, 33000). **Both `requires_payment_method` with
  `amount_received: 0`** — abandoned before payment, so neither generated a `payment_intent.succeeded`.
- Our DB returns **the same 2 payments** for that window, both `stripe_livemode true`, both `pending`.
  **Stripe and the database agree exactly.**
- The last PaymentIntent to succeed was `pi_3U1EKkGdOzCmGbHw1J1qCMnB` at **2026-08-05 23:34:50Z**, and
  the ledger's final two rows carry that same `3U1EKk` core (`payment_intent.succeeded` 23:35:53,
  `transfer.created` 23:39:41). **The ledger's last entry is the last successful payment's own event.**

So **H2 — "live events were refused for two months" — is refuted.** The owner's caution was right: a
later live payment does not prove rejection, and here the later live payments never completed. Three
sources agree: Stripe's event list, Stripe's PaymentIntent states, and our own ledger boundary.
**F-WEBHOOK-LEDGER-GAP-1 should be downgraded to "explained — no qualifying activity".**

**Limit:** `/v1/events` only covers ~30 days, so 2026-08-05 → ~2026-09-10 is not covered by that read.
What covers it is the PaymentIntent evidence: the only two live PIs in that period never completed.

**Method correction:** D's Stripe query used epoch `1785879581`, which is **2026-08-04 21:39:41Z** —
26 hours earlier than the intended cutoff. Harmless (it returned more context, not less), but it means
the raw result held 4 PIs, of which only the 2 above are actually after the ledger boundary. Corrected
by arithmetic before reporting, and recorded because an unlabelled window is how a 4 becomes a 2.

## 7. Seller fee

**Unpaid live payments missing a stored seller fee: 0.**
**Controls:** 8 live payments total, and **8** of them have a non-null `seller_fee`. So the zero is a
real zero over a populated column, not an empty scan. No details to report, as none exist.

## 8. What this unblocks, and what it does not

**Now available for the correction scripts — all five markers:**

| marker | value |
|---|---|
| `__R1_REFUND_ID__` | `re_3U0XuwGdOzCmGbHw0bL9UYzT` / `re_3U0YzcGdOzCmGbHw0Av5k7ZH` |
| `__R1_REFUND_STATUS__` | `succeeded` (both) |
| `__R1_REFUND_COUNT__` | `1` (both) |
| `__R1_EVIDENCE__` | this record and its reads |
| `__OWNER_SOURCE__` | **still the owner's decision** |

**Four of five are now evidenced. The fifth is a judgement the owner must make.** Until it is made the
files stay unfilled, and per the rule A and D agreed, all five markers fill in one step or none do.

D has executed nothing. Correction writes remain separately gated.
