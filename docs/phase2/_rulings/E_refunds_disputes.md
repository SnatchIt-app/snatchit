# E — Refunds, Disputes and Refund Liquidity: who fronts the money and how Snatch It gets it back

**Agent E · primary-money architecture pass · 2026-09-02**
**Repo** `/Users/josetascon/snatchit-consol` · **branch** `feature/venue-native-and-product-v2`
**Scope** read-only audit + Stripe ground truth. No migration authored, nothing deployed, no Stripe object created.

---

## 0. The three findings that matter before anything else

**F-1. No refund path in this repository returns money to a primary-ticketing buyer's card.**
Every Phase-2 refund function records intent into `kernel.refund` and stops. The single edge function that
calls Stripe `/refunds` is the *legacy resale expiry sweep*
(`supabase/functions/enforce-transfer-expiry/index.ts:264` and `:387`). The `refund-execute` edge function
that the spec designates as the executor **does not exist** (§6). Under every charge model, scenarios 1, 2, 3
and 9 currently end with a `pending` row and a buyer who has not been paid.

**F-2. There is no mechanism anywhere that reverses a Stripe transfer.**
Repo-wide there is not one call to `/transfers/:id/reversals`. `supabase/functions/stripe-webhook/index.ts:756`
*observes* `transfer.reversed` and marks a row; it never causes one. Recovery from a paid venue is therefore
manual-Dashboard-only under **every** model, and under DIRECT it is not available at all.

**F-3. A primary order produces no positive settlement line, so the one documented recovery mechanism —
netting — has nothing to net against.**
`venue.settlement_line` is only ever written with three causes: `market_sale` (+, resale royalty,
`088:346-360`), `chargeback` (−, `088:362-372`) and `promoter_commission` (−, `090:1541-1546`). The
`refund_void` cause is admitted by the CHECK (`087:97`) and **has zero writers**. Primary ticket revenue never
becomes a settlement line at all. `kernel.close_settlement` mints a payout only `if v_net > 0`
(`087:340-348`) — so for a primary-only org the settlement net is structurally ≤ 0, no payout is minted, and
the negative `chargeback` line sits in a settlement that will never be paid. **"Recovery by netting" recovers
nothing because there is no positive side of the ledger.** This is the single most important liquidity fact
in this document.

---

## 1. What Snatch It runs today (the baseline the models are alternatives to)

Snatch It is **already** on separate charges and transfers, by construction rather than by decision:

| Fact | Evidence |
|---|---|
| PaymentIntent carries no `transfer_data`, no `on_behalf_of`, no `application_fee_amount` | `supabase/functions/create-payment-intent/index.ts` (PI creation block ~`:281-296`); repo-wide grep for `application_fee` in `supabase/functions/` = 0 hits |
| No `Stripe-Account` header is ever sent — a bare platform `Bearer` key only | `supabase/functions/_shared/stripe.ts:65`, `:96` |
| Funds land in the **platform** balance; disbursement is a later, separate `/transfers` with `source_transaction` | `supabase/functions/_shared/payouts.ts:133-145` |
| Venue orgs have no Stripe account at all: `kernel.organization.stripe_connect_account_ref` has **no writer** outside the DB function `kernel.set_org_payout_destination` (`085:1601`), and that function has zero callers in `supabase/functions/`, `web/`, `app/`, `src/`, `packages/` | corroborated at `docs/phase2/ADVERSARIAL_ARCHITECTURE_REVIEW.md:24` |

So today: **Snatch It fronts 100% of every refund and every chargeback**, and holds 100% of the money, because
no venue has ever been paid. The models below are choices about the *future* state where venues do get paid.

---

## 2. Stripe ground truth (current official docs, cited)

Everything in this section is quoted or closely paraphrased from Stripe's live documentation, fetched
2026-09-02. Where I could not establish behaviour with confidence I say so in §2.5 rather than guess.

### 2.1 Whose balance is debited

| | DIRECT | DESTINATION / `on_behalf_of` | SEPARATE CHARGES + TRANSFERS |
|---|---|---|---|
| Charge lands in | connected account balance | platform balance, portion immediately transferred out | platform balance |
| **Refund debits** | **connected account** | **platform** | **platform** |
| **Chargeback debits** | **connected account** | **platform** | **platform** |
| Dispute fee | platform or account, per `fees_collector` / `controller.fees.payer` | platform | platform |

Sources: <https://docs.stripe.com/connect/charges> ("Refunds and chargebacks reduce the connected account's
balance" for direct; "Refunds and chargebacks reduce your platform's balance" for destination; "Your account
balance is debited for the cost of the Stripe fees, refunds, and chargebacks" for SCT) and
<https://docs.stripe.com/connect/disputes>.

### 2.2 Insufficient balance at the moment of refund

- **DIRECT** — "If the connected account's balance is insufficient, we set the refund status to `pending`.
  When the connected account's balance has enough funds, Stripe automatically processes pending refunds in
  the order they were created." (<https://docs.stripe.com/connect/charges>)
- **DESTINATION** — platform balance short ⇒ refund goes `pending` and auto-processes later. **But**: "If the
  refund request also attempts a transfer reversal, but the connected account has an insufficient balance, the
  refund request returns an error instead of creating a refund with `pending` status." (ibid.) That is a
  material trap: `reverse_transfer=true` turns a survivable "pending refund" into a **hard API error and no
  refund at all**.
- **SCT** — platform balance short ⇒ `pending`, auto-processes later. (ibid.)

### 2.3 Recovering from the venue

- **DESTINATION**: `refunds.create(charge, reverse_transfer=true)`. "If the refund results in the entire
  charge being refunded, the entire transfer is reversed. Otherwise, a proportional amount of the transfer is
  reversed." Application fee is **not** returned unless `refund_application_fee=true`.
  (<https://docs.stripe.com/connect/destination-charges>)
- **SCT**: "refunding a charge has **no impact** on any associated transfers. It's up to your platform to
  reconcile any amount owed back to it by reducing subsequent transfer amounts or by reversing transfers."
  (<https://docs.stripe.com/connect/separate-charges-and-transfers>)
- **The hard ceiling on reversal, both indirect models**: "It's only possible to reverse a transfer if the
  connected account's available balance is greater than the reversal amount **or** has connected reserves
  enabled." (ibid.) A venue that has already paid out to its bank cannot be reversed against.
- **DIRECT**: there is nothing to reverse — the money never came to the platform. Recovery is Stripe's own
  automatic offsetting of the connected account's negative balance against future volume, plus
  `debit_negative_balances` against the venue's bank account, plus (after 180 days) a
  `connect_collection_transfer` that takes the loss **out of the platform's balance**.
  (<https://docs.stripe.com/connect/account-balances>)

### 2.4 Negative balances and who ultimately eats it

From <https://docs.stripe.com/connect/account-balances>:

- "Stripe first assigns negative transactions to the account the associated charge was made on."
- Ultimate responsibility is set by `controller.losses.payments` (v1) / `defaults.responsibilities.losses_collector`
  (v2): `stripe` or `application`. **If it is `application`, Snatch It is the loss-bearer for its venues'
  negative balances — under DIRECT as well.**
- Stripe holds a `connect_reserved` balance on the platform to pre-fund that exposure.
- "When a connected account holds a negative balance amount for 180 days, Stripe transfers a portion of your
  balance to zero out that account's balance" (`connect_collection_transfer`). After that Stripe recommends
  rejecting the account.
- `debit_negative_balances` defaults to **false** for accounts where the platform collects requirements
  (Custom-style), and works only in AU / CA / SEPA+UK / NZ / US, and never against a debit card.
  (<https://docs.stripe.com/connect/risk-management/best-practices>)

Also load-bearing, from the same risk page: *"If their balance can't cover the refund, you can reverse the
transfer without issuing the refund, which results in a negative balance on the account."* — i.e. under the
indirect models the platform can deliberately convert its own loss into a venue debt, which is a real
mechanism the current code does not use.

### 2.5 Where I could NOT establish Stripe behaviour with confidence

State these as open questions, do not build on them:

1. **Deauthorized / disconnected Standard account, DIRECT model.** Stripe documents that a direct-charge
   refund is created "using your platform's secret key while authenticated as the connected account" via the
   `Stripe-Account` header (<https://docs.stripe.com/connect/saas/tasks/refunds-disputes>). I could not find
   an explicit Stripe statement about refund capability after OAuth deauthorization. The inference — losing
   authorization means losing the ability to create the refund — is strong but **is an inference**. Verify
   with Stripe support before choosing DIRECT.
2. **Whether a `pending` refund ever times out.** Stripe says pending refunds process "when the balance has
   enough funds." No stated deadline, no stated failure mode for a balance that never recovers. Unknown.
3. **Whether Snatch It's platform has connected reserves enabled**, and what `controller.losses.payments` is
   set to on the live account. Not determinable from this repo. **Both are decisive** — check the Dashboard.
4. **Transfer reversal against a `rejected` or closed connected account.** Docs cover the negative-balance
   path and the 180-day collection transfer, but not reversal against a closed account specifically.

---

## 3. SCENARIO × MODEL MATRIX

Cells read: **who fronts the buyer's money** → **how Snatch It recovers** → **verdict**.
✅ recoverable · ⚠️ recoverable only under conditions · ❌ unrecoverable — Snatch It eats it.

| # | Scenario | DIRECT (charge on venue) | DESTINATION / `on_behalf_of` | SEPARATE CHARGES + TRANSFERS |
|---|---|---|---|---|
| 1 | **Full refund, venue not yet paid out** | Venue's Stripe balance fronts it. Nothing to recover — Snatch It never held the money. Application fee is lost unless `refund_application_fee` handled. ✅ | Platform fronts; `reverse_transfer=true` pulls the whole transfer back from the venue's *pending/available* balance. ✅ | Platform fronts; funds still in platform balance (no transfer made yet — this is exactly today's shape). Nothing to recover. ✅ **Cleanest cell in the table.** |
| 2 | **Partial refund** (`venue."order".partially_refunded`, `082:80`) | Venue balance debited pro rata; app fee refunded proportionally. ✅ | Platform fronts; "a proportional amount of the transfer is reversed." ✅ | Platform fronts; **transfer is untouched** — platform must itself net the difference off a future transfer. ⚠️ *No code does this netting.* |
| 3 | **Event cancellation, N tickets at once** | N refunds hit one venue balance simultaneously → venue almost certainly goes negative → §2.4 chain. ⚠️→❌ if `losses=application` | Platform fronts N × face immediately; N transfer reversals, each capped by the venue's *current* balance. Partial recovery at best. ⚠️ | Platform fronts N × face. If cancellation precedes the payout run, nothing was transferred and recovery is free. **The strongest cell for the worst scenario.** ✅ if timing holds, ⚠️ if not |
| 4 | **Chargeback BEFORE venue paid** | Venue balance debited by Stripe automatically. Snatch It exposed only via `losses_collector`. ✅ | Platform debited; reverse the (already-made) transfer. Venue's balance usually still holds it. ⚠️ | Platform debited; **money never left**, so simply do not transfer it. `_shared/payouts.ts:100-128` already refuses to pay out against a refunded charge. ✅ |
| 5 | **Chargeback AFTER venue paid** | Venue debited; if the venue has spent it, negative balance → `debit_negative_balances` → 180-day `connect_collection_transfer` **out of Snatch It's balance**. ⚠️→❌ | Platform debited. Reversal only works "if the connected account's available balance is greater than the reversal amount." A venue that banked the money **cannot be reversed**. ❌ | Identical to destination, plus: refunding the charge has *no* effect on the transfer, so recovery is 100% a separate deliberate act. ❌ |
| 6 | **Venue connected account negative** | Refunds/chargebacks queue as `pending` until the venue earns again. Buyer waits indefinitely. ❌ *(buyer-facing)* | Reversal **refused** (balance ceiling). Platform is out of pocket with no rail. ❌ | Reversal refused. Same. ❌ |
| 7 | **Venue disconnected / closed / restricted** | Platform likely cannot authenticate as the account to issue the refund at all (§2.5.1). **Buyer cannot be refunded by any code path.** ❌❌ | Charge is on the platform, so the **refund still works**. Only *recovery* dies. ⚠️ | Same as destination: refund works, recovery dies. ⚠️ **This scenario is the strongest argument against DIRECT.** |
| 8 | **Insufficient platform balance at refund time** | N/A — platform balance is not the funding source. ✅ | Refund → `pending`, auto-processes. **But with `reverse_transfer=true` and a short venue balance it is a hard error and no refund is created.** ⚠️ | Refund → `pending`, auto-processes when the balance recovers. Top up via `/v1/topups`. ⚠️ |
| 9 | **Refund owed to a tombstoned (erased) buyer** | Stripe refunds to the *card*, not the account — the erasure does not block the money. The problem is entirely internal: does Snatch It still know which PI to refund? | same | same |

Scenario 9 detail is in §7; it is model-independent and is a **deletion-ordering** problem, not a Stripe one.

---

## 4. Scenario traces — the instants where someone is out of pocket

### Scenario 3, the one that can kill the company

A 2,000-ticket show at £40 is £80,000. Cancellation calls `catalog.cancel_event` (`088:1612`), which walks
every session and inserts `kernel.refund` rows (`088:1666-1676`) — **and does nothing else**. Instant-by-instant
under each model, assuming the executor existed:

- **DIRECT** — t₀: 2,000 refunds debit the venue's balance. The venue almost certainly does not hold £80k
  (Stripe pays out on a 2-day rolling schedule by default). Balance goes deeply negative. Refunds beyond the
  balance sit `pending`. **Buyers are not refunded** and Snatch It has no lever: it cannot fund the venue's
  balance except by `/transfers` into it, i.e. by voluntarily giving the venue £80k of platform money.
  If `losses_collector = application`, Snatch It's `connect_reserved` is frozen against it and after 180 days
  it becomes a collection transfer out of the platform balance. **Worst cell in the matrix.**
- **DESTINATION** — t₀: platform is debited £80,000 the instant the refunds go through, before any recovery.
  Snatch It needs £80k of *liquid* Stripe balance or the refunds go `pending` (or hard-error, if
  `reverse_transfer=true` is set and the venue is short — §2.2). Recovery = 2,000 reversals, each capped by the
  venue's balance at that moment.
- **SCT** — t₀: platform is debited £80,000, *but* the money is still in the platform balance because the
  transfer is deferred to settlement close. Net position ≈ zero. **This is the only model where mass
  cancellation is liquidity-neutral**, and it is liquidity-neutral *only because payouts are settlement-cadenced*
  — exactly the property money spec §9.4 already commits to (§5).

### Scenario 5 vs "No reserve. No clawback."

Under DESTINATION and SCT, scenario 5 is a **platform loss with a recovery rail that Stripe caps at the venue's
current balance**. Under DIRECT it is a **venue loss that becomes a platform loss** if `losses_collector =
application` or after 180 days. There is no configuration in which scenario 5 is free. See §5.

---

## 5. Verification of the "No reserve. No clawback." claim

**The quote is real and correctly attributed.** `docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md:1486-1493`,
section heading **"### 9.4 What is deliberately NOT built"** (`:1486`), first line (`:1488`):

> **No reserve. No clawback. No instant payout.** (C29/C30/C31, Gate M; schema §1.11; dashboard §14.5.)

And the justification, `:1489-1491`:

> Nothing in O-1/O-3 requires them: refunds are funded from the Stripe balance via `refunds.create` on the
> original charge, and payouts remain settlement-cadenced.

**What that sentence actually assumes, and why it is only true under one model.** "Funded from the Stripe
balance" is only a coherent statement when the balance in question is the *platform's* — i.e. under
DESTINATION or SCT. Under DIRECT the funding balance is the venue's, and the platform has no ability to make
it solvent. §9.4's own reasoning therefore **presupposes an indirect charge model**. Choosing DIRECT
invalidates the premise of the ruling that says a reserve is unnecessary.

**And the second clause carries the real load: "payouts remain settlement-cadenced."** That is the *only*
thing standing between Snatch It and scenario-5 exposure. It is a timing hedge, not a recovery mechanism. It
protects scenarios 1–4 (money not yet gone) and does nothing for 5, 6 or 7.

**Implication for scenario 5, stated plainly.** Under DESTINATION/SCT, a chargeback after payout debits the
platform. §9.4 forbids building a clawback. The only recovery contemplated in the corpus is netting via the
`chargeback` settlement line (`088:362-372`) — and per **F-3** that line lands in a settlement whose net is
structurally ≤ 0 for a primary-only org, so it produces no payout to net against and no collection. Under
DIRECT the exposure is transformed rather than removed: it becomes the venue's negative balance, which returns
to Snatch It via `connect_collection_transfer` if `losses_collector = application`.

**Verdict: scenario 5 is unrecoverable under all three models as the system is currently specified and built.**
The spec's own §9.4 companion, `kernel.identity_obligation` (`085:161-186`, writer at `085:1793`), is
explicitly identity-scoped and — by its own text at `:1491-1494` — "funds nothing, nets nothing, gates no
payout." Org-scoped debt has no ledger home at all; `docs/phase2/_decisions/A_venue_money.md:188` reaches the
same conclusion independently.

---

## 6. `refund-execute` — confirmed absent, and exactly what is missing

**Confirmed.** `ls supabase/functions/` returns twelve directories, none of them `refund-execute`:
`_shared`, `auto-finalize-auctions`, `confirm-and-release`, `confirm-payment`, `create-connect-account`,
`create-payment-intent`, `delete-account`, `enforce-transfer-expiry`, `notify-report`, `notify-transfer`,
`send-push`, `stripe-webhook`.

It is fully specified at `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md:528-576` (and listed as a required
new edge at `:193`, `:303`, `:339`). The spec is unusually precise about its own history — `:543-547` records
that an earlier version named no callback function at all, and that `submitted`/`succeeded`/`failed` were
literally unreachable states.

**What is missing between a recorded refund and money on a card — the complete list:**

1. **The Stripe call.** `stripe.refunds.create({ payment_intent, amount })` under the deterministic
   idempotency key `refund_${refund_id}` (spec `:559-560`). No code in the repo issues it for a primary order.
2. **The state callback.** `kernel.mark_refund_state(refund_id, 'submitted', re_…, null, key)`
   (`085:1737-1789`). It exists, is correct, is `service_role`-only — **and has zero callers repo-wide.**
   Grep for `mark_refund_state` across `*.ts` / `*.tsx` = 0 hits.
3. **The webhook reconciliation legs.** The spec requires `charge.refunded` / `refund.updated` →
   `mark_refund_state(…, 'succeeded', …)` (spec `:1215`) and `refund.failed` → `'failed'` with a cause
   (`:1216`). The live webhook's `charge.refunded` branch (`supabase/functions/stripe-webhook/index.ts:705-734`)
   only updates legacy `public.payments`; it never touches `kernel.refund`. The webhook's full RPC surface is
   `claim_stripe_webhook_event`, `fail_stripe_webhook_event`, `complete_stripe_webhook_event`,
   `release_reservation`, `freeze_transfer_for_dispute`, `mark_transfer_reversed` — **no kernel money RPC at all.**
4. **The model-specific parameters that do not appear anywhere in the spec.** For DESTINATION the call needs
   `reverse_transfer` and `refund_application_fee`; for DIRECT it needs the `Stripe-Account` header, which
   `_shared/stripe.ts` cannot currently send (`:65`, `:96` set only `Authorization`). **The executor spec was
   written against the SCT shape and will not port to the other two models unchanged.**

**Net effect today:** every `kernel.refund` row is born `pending` (`085:597`, `085:705`, `088:1668`) and no
transition out of `pending` is reachable. `venue."order"` is nevertheless moved to `refunded` /
`partially_refunded` in the same transaction (`085:604-607`, `085:717-722`) and the tickets are **voided**
(`085:580` via `kernel.void_ticket_atom`). **The buyer loses the ticket and does not get the money.** That is
the most dangerous single property in the current build, and it is model-independent.

---

## 7. Full refund-path inventory — which call Stripe, which only record intent

| Path | Location | Calls Stripe? | What it actually does |
|---|---|---|---|
| `kernel.refund_primary_order` | `085:457-620` | **No** | Voids covered atoms (`:580`), INSERTs `kernel.refund` at `pending` (`:597`), moves the order to `refunded`/`partially_refunded` (`:604-607`). Direct-partial voids **nothing** (`:571-573`). |
| `kernel.admin_refund` | `085:629-733` | **No** | Break-glass, `platform_risk`/`platform_admin`. Voids named atoms, INSERTs `kernel.refund` (`:705`). |
| `kernel.request_order_refund` | `085:850-1088` | **No** | Buyer/org entry point. Parks a `kernel.approval_request` or delegates. Never money. |
| `kernel.approve_refund_request` | `085:1089-1347` | **No** | Second approver. On approve it delegates to `refund_primary_order` with a `req:<uuid>` command key (`085:497-513`) — which still only records. |
| `kernel.cancel_refund_request` | `085:1348-1395` | **No** | — |
| `kernel.sweep_expired_refund_requests` | `085:1396-1438` | **No** | — |
| `kernel.mark_refund_state` | `085:1737-1789` | **No** — by design | The executor's callback. Comment at `:1776`: *"touches NO atom, NO public.\* table."* **Zero callers.** |
| `catalog.cancel_event` | `088:1612-1780+` | **No** | Mass cancellation. INSERTs one `kernel.refund` per paid sale (`088:1668-1676`), emits notices, voids atoms. |
| **`enforce-transfer-expiry`** | `supabase/functions/enforce-transfer-expiry/index.ts:264-274` and `:387` | **YES** | The **only** real Stripe refund in the repository. `POST /v1/refunds` with `payment_intent` (full refund, no `amount`), idempotency key `refund_expiry_${transfer_id}`, then updates `public.payments` (`:277-284`). Legacy P2P-resale rail only. No `reverse_transfer` — correct, because under SCT no transfer exists until the buyer confirms. |

---

## 8. Full dispute-path inventory

| Path | Location | Behaviour |
|---|---|---|
| `kernel.record_dispute_native` | `088:758-865` | Records the dispute, applies `resale_state='dispute_hold'` to the buyer's atoms (`:822-826`), and sets `hold_state='held'`, `hold_reason_code='dispute'` on every reachable `pending`/`submitted` payout (`:843-847`). **Moves no money.** Skips and alerts where custody has moved (`:828-836`). |
| `kernel.mark_dispute_state` | `088:875-911` | State sync only, forward-only, terminal-absorbing. Header comment `:876-880`: *"A Stripe-reported terminal is a fact, not a release: holds persist until resolution."* |
| `kernel.resolve_dispute_native` | `088:913-947` | **Always raises.** After authority and outcome validation it unconditionally raises `dual_control_unavailable` with zero mutation (`:944-946`), because 077's immutable `approval_request` CHECK admits no dispute action. **There is no dispute resolution path in this system.** A dispute freezes tickets and payouts permanently. |
| Webhook `charge.dispute.created` | `stripe-webhook/index.ts:~595-662` | Upserts legacy `public.disputes`; calls `freeze_transfer_for_dispute` (`:609`). |
| Webhook `charge.dispute.closed` | `stripe-webhook/index.ts:663-704` | Syncs status; on `lost` marks `public.payments.status='refunded'` (`:691-696`). Explicit comment at `:687-690`: *"Don't make autonomous money moves here. Just sync state."* |
| Webhook `transfer.reversed` | `stripe-webhook/index.ts:747-760` | **Observer only.** Marks `transfers` reversed when a human reverses in the Dashboard. |

**Two structural gaps.** (a) The live webhook never calls `record_dispute_native` or `mark_dispute_state` —
the Phase-2 dispute ledger has no producer. (b) `resolve_dispute_native` is a fail-closed park, so a lost
dispute leaves the venue's payout `held` forever and the atoms in `dispute_hold` forever. That is *safe* for
Snatch It's money and *catastrophic* for a venue's operations, and it means **scenario 4's "hold the payout"
recovery has no exit** — the money is neither recovered nor released.

---

## 9. Promoter commission reversal — the prior finding, verified with a correction

**Claim under test:** *"a refund before settlement close could make a sale vanish from the ledger while a
negative commission line remains."*

**Verdict: the claim is directionally right but the mechanism is different, and the real defect is worse.**

What the code actually does:

- `kernel.settlement_commission_lines` (`090:1511-1548`) excludes attributions whose order is
  `refunded` or `cancelled` (`090:1537`). So a **full** refund landing before close correctly suppresses the
  commission line. The stated mechanism does not fire for full refunds.
- `kernel.pay_promoter_commission` (`090:1401-1506`) independently skips `basis_zero` for a `refunded` order
  (`090:1465-1468`) and computes the payable from **surviving, non-voided atoms** (`090:1470-1476`).

**The actual defects, both real:**

1. **`partially_refunded` is not in the exclusion set** (`090:1537`) — and by design a direct-partial
   `refund_primary_order` **voids no atoms at all** (`085:571-573`, comment: *"Direct-partial: money only
   (voids nothing)"*). So a partial refund leaves every atom surviving, the basis is unchanged, and the
   promoter is paid full commission on revenue that was partly returned to the buyer. **Commission is paid on
   refunded money.** Snatch It eats the difference.
2. **Nothing reverses a commission line once written.** `venue.settlement_line` is append-only —
   `revoke update, delete … from service_role` (`087:115`) plus a before-update/delete trigger (`087:110-112`).
   A refund arriving *after* the commission was lined has no reversal path whatsoever. The commission payout
   is minted `held`/`unfunded_settlement` (`090:1487-1491`), so no money leaves *today* — but the liability is
   permanently recorded against an order that was refunded, and `kernel.release_payout` (`085:807`) would pay
   it out with no re-check of the order's refund state.
3. **The vanishing-sale half of the claim is confirmed, and is broader than commissions (F-3).** The primary
   sale never enters the settlement ledger as a positive line at all. So the settlement carries the negative
   commission line and the negative chargeback line and no offsetting revenue — the sale does not "vanish on
   refund," it **was never there**.

---

## 10. Scenario 9 — refund owed to a tombstoned buyer

Model-independent. Stripe refunds to the **card**, not to a Snatch It account, so erasure does not block the
money. The exposure is internal and is already partly defended:

- `kernel.deletion_blockers_money` (`085:229-288`) blocks erasure on an in-flight refund or a pending
  `refund.issue` approval (BP-12 arm 1, `:246-259`), and on a "refund-possible window" over
  `paid`/`partially_refunded` candidate orders (BP-12 arm 2, `:262-283`), keyed on
  `deletion.refund_possible_window_hours` — which **fails closed** if unset while candidates exist (`:277-279`).
- `kernel.on_deletion_q5_release` (`085:304-337`) expires the deleter's own pending requests and releases the
  `refund_hold` overlays.
- `kernel.record_identity_obligation` (`085:1793-1834`) deliberately has **no debtor-state precondition** —
  comment at `:1817-1818`: *"recording against ERASED is the Q2 path working as designed."*

**The residual hole:** the window guards *orders*, not *chargebacks*. A card network dispute can arrive
months after erasure — long past any plausible `refund_possible_window_hours`. At that point the atoms are
gone, the buyer identity is tombstoned, and the only representable outcome is
`kernel.identity_obligation` against an erased debtor, resolvable only as `written_off`
(`085:1836-1878`). **That is an eaten loss by construction — but it is correctly *booked*, which is more
than can be said for the org-side equivalent.**

---

## 11. RISK RANKING

### Ranked by recovery risk, best to worst

**1. SEPARATE CHARGES AND TRANSFERS — lowest recovery risk.**
Snatch It holds the money until it chooses not to. Scenarios 1, 3 and 4 are all recoverable *for free* purely
because the transfer has not happened yet — and money spec §9.4's "payouts remain settlement-cadenced"
guarantees exactly that timing. It is also what the code already does, so it costs no migration. Its
weaknesses are honest ones: the platform must carry refund liquidity (§2.2), and post-payout recovery
(scenarios 5–7) requires a deliberate reversal that Stripe caps at the venue's balance.

**2. DESTINATION / `on_behalf_of` — moderate.**
Same platform-fronts-everything liability as SCT, with a *better* pre-payout recovery ergonomic
(`reverse_transfer=true` does refund and reversal atomically and proportionally) and `on_behalf_of` gives the
venue the statement descriptor, which materially reduces "I don't recognise this charge" chargebacks. But it
carries a specific trap SCT does not: with `reverse_transfer=true` and a short venue balance, **the refund
hard-errors instead of going pending** (§2.2) — meaning the buyer is not refunded at the exact moment the
venue is in trouble. And because the transfer happens at charge time, the venue is "already paid" much
earlier, which pushes more real-world cases from scenario 4 into scenario 5.

**3. DIRECT — highest recovery risk. I recommend against it.**
It looks safest (refunds and chargebacks debit the venue) and is the most dangerous, for four independent
reasons: (a) **scenario 7 is a buyer-facing catastrophe** — a disconnected or closed account plausibly leaves
Snatch It unable to refund a buyer *at all* (§2.5.1); (b) **scenario 3 breaks it** — a venue's balance cannot
absorb a mass cancellation and refunds silently queue as `pending` with no deadline (§2.5.2); (c) the loss
lands back on the platform anyway if `losses_collector = application`, or after 180 days via
`connect_collection_transfer`, so the apparent protection is partly illusory; (d) it **invalidates the premise
of money spec §9.4** (§5), and would require a reserve to be built — precisely the Gate-M work the corpus
defers. It also requires `_shared/stripe.ts` to learn the `Stripe-Account` header (`:65`, `:96`) and
requires the whole Phase-2 refund set to be re-specified.

### UNRECOVERABLE per model — scenarios where Snatch It eats the loss with no mechanism

| Model | Unrecoverable |
|---|---|
| **DIRECT** | **7** (cannot refund at all — worst outcome in the document) · **6** (buyer waits indefinitely) · **3** at scale · **5** whenever `losses_collector = application` or past 180 days |
| **DESTINATION** | **5** (venue banked it; reversal refused) · **6** (reversal refused) · **7** (refund works, recovery dead) |
| **SCT** | **5** (identical) · **6** · **7** · **2** in part (partial refund does not touch the transfer, and no code nets it) |

**Common to all three, and true today regardless of which model is chosen:**

- **Scenario 5 is unrecoverable under every model** as specified, because §9.4 forbids a clawback and the only
  named alternative — netting via the `chargeback` settlement line — has no positive line to net against (F-3).
- **A lost dispute never resolves**: `resolve_dispute_native` always raises (`088:944-946`). The venue's payout
  stays held forever, the buyer's atoms stay frozen forever.
- **Commission is paid on partially refunded revenue** (§9, defect 1), and no lined commission is ever
  reversed (§9, defect 2).
- **Every primary refund today voids the ticket and returns no money** (§6). Until `refund-execute` exists,
  the charge-model question is downstream of a live consumer-harm defect.

---

## 12. What I would check before this decision is signed

1. `controller.losses.payments` / `defaults.responsibilities.losses_collector` on the live platform account.
   If it is `application`, DIRECT's central selling point disappears and the ranking above hardens.
2. Whether connected reserves are enabled for the platform — it is the sole documented escape from the
   transfer-reversal balance ceiling (§2.3).
3. Confirm with Stripe support what a deauthorized Standard account does to refund capability (§2.5.1).
4. Decide the funding source for `COMMISSION_FUNDING_SOURCE` — currently every commission payout is minted
   `held`/`unfunded_settlement` (`090:1487-1491`) and can never be paid.
