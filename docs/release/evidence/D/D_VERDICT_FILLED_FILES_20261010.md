# D — verdict on the filled correction files

2026-10-10. A filled the two scripts and asked D to verify against D's pre-registered §6 checklist
before presenting the hashes to the owner. **D executed nothing.**

## VERDICT: the files are correct and ready to be put to the owner

Every §6 check passes. One presentation point the owner must be told plainly — §5 below.

## 1. Two-party agreement on the Stripe facts

A's refund values match D's **blind** reads on every field: ids, `succeeded`, 1100/220 `usd`, created
`1785864002`/`1785864018`, `reason null`, no `failure_reason`, `metadata {}`, `count 1`,
`has_more false`, livemode true, `amount_refunded = amount`, `refunded true`, no dispute. Collected
independently before either saw the other's numbers.

## 2. §6 checklist, item by item

| check | result |
|---|---|
| only the five markers changed | **PASS** — exactly 10 diff lines each (5 removed, 5 added) |
| recomputed sha256 #6 | **PASS** — `d7f31cf1…0d88`, D's own hash, matches A |
| recomputed sha256 #7 | **PASS** — `dca8cb00…2996`, matches A |
| `c_status` is `succeeded` | **PASS**, from the refund object |
| `c_amount` = `c_total` = the R1 refund amount | **PASS** — 1100/1100 and 220/220, both equal to Stripe's refund `amount` |
| refund count established as 1 | **PASS** — `c_refund_count = '1'`, and Stripe's list gives `count 1, has_more false` |
| evidence names where it was read | **PASS** — names the account, the read date, count/`has_more`, status, amount, created time, the source basis, and D's `78d9572a` |
| `payment_refund_state` empty at execution time | **PASS** — re-read 2026-10-10, see §4 |

**Guards re-evaluated against the actual filled values**, not assumed:
`re_3U0XuwGdOzCmGbHw0bL9UYzT` and `re_3U0YzcGdOzCmGbHw0Av5k7ZH` match `^re_[A-Za-z0-9]{10,64}$` and are
not all-digit (C11 passes); `'succeeded'` passes C3; `'dashboard'` is in the four values (C4);
`'1'` passes C10; the evidence strings far exceed 20 characters and do not begin `__` (C12);
`c_amount = c_total` passes C5.

## 3. D's own test of A's origin determination — it holds, and for a better reason than stated

D had left `p_source` open. A closed it. D tested both limbs against the source.

**(a) Verified at gate `abef9506`, `stripe-webhook/index.ts:25-28`:**
```ts
function refundSource(r: StripeRefund): 'expiry' | 'unfulfillable' | 'dashboard' {
  if (!(r.metadata?.source ?? '').startsWith('enforce-transfer-expiry')) return 'dashboard';
  return r.metadata?.reason === 'unfulfillable' ? 'unfulfillable' : 'expiry';
}
```
With `metadata: {}` this returns **`'dashboard'`**, and the function feeds `p_source` at `:785` and
`:990`.

**(b) Verified at `083ee172`:** the only non-test code referencing `/refunds` is
`enforce-transfer-expiry/index.ts`, which sets `metadata[source]`. The other hit is
`007_transfer_expiry.sql`, a migration, which cannot call Stripe. No other refund creator existed.

**The argument is stronger than "someone probably used the Dashboard".** `'dashboard'` is the value
**our own production code assigns to exactly this input**. Reconciling with it **reproduces what the
system would have recorded** had the current handler seen these refunds. It is not a claim about an
unobserved human action, which is what D was worried about when leaving the field open.

**And it is robust to the residual.** `refundSource()` returns `'dashboard'` for anything not created
by the expiry path — including a direct API call, not only a click in the Dashboard UI. That does not
weaken the conclusion: under our four-value taxonomy both map to `'dashboard'`, so the answer does not
depend on distinguishing them. The label means "not created by our expiry path", and limb (b)
establishes that at that date this set contained only manual Stripe actions.

**D withdraws its "leave it unknown" position.** The field is determined.

## 4. Live prestate, re-read immediately before the verdict

| | #6 `32913315` | #7 `700d469b` |
|---|---|---|
| livemode / status | true / `refunded` | true / `refunded` |
| total | 1100 | 220 |
| `amount_refunded_cents` | **NULL** | **NULL** |
| `stripe_refund_id` | **NULL** | **NULL** |
| requested/succeeded/failed cents | **0/0/0** | **0/0/0** |
| `refunded_at` | 2026-08-04 17:20:05Z | 2026-08-04 17:20:19Z |

Globally: `payment_refund_state` **0**, `payment_refund_state_log` **0**, `payment_refunds` **0**,
payouts on either transfer **0**. Identical to R0. **Every prestate guard will pass**, and the
`stripe_refund_id is NULL` state means the set-once field is free for the real id.

## 5. The one thing the owner must be told plainly

The in-file comment on `c_source` still reads *"the owner's recorded decision for this row"*. **The
value was derived from evidence, not chosen by the owner.** A is right that fixing the comment would
break the five-line rule and invalidate the verified hashes, so the comment should stay — but the
owner must not approve the hash believing they are ratifying their own earlier choice.

**The accurate framing for the approval request:** *"`source = 'dashboard'` was derived from your own
code's classification rule, which assigns that value to any refund your expiry path did not create.
Approving the hash ratifies that derivation."* With that said, the comment is satisfied, because the
owner's approval **is** the recorded decision. Without it, the file misdescribes how the value arose.

## 6. Scope of this verdict

D verifies that **the files are correct, the inputs are evidenced, and the live prestate matches**.
D does **not** authorise execution: the owner's separate execution approval governs that, and the
files must not be run before it. If any production state changes between now and execution, the
prestate guards will refuse — which is the designed behaviour, not a failure.
