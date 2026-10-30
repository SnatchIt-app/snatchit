# J2 — Stripe transfer-reversal mechanics under separate charges and transfers

**Train:** Agent B (backend, research). **Branch:** `feature/venue-native-and-product-v2`.
**Scope:** what Stripe mechanically offers for recovering money already transferred to a
connected account. **No Stripe API call was made. No code, migration or test was modified.**

Every claim carries a URL. Findings are sorted into three buckets that are never blurred:

| Bucket | Meaning |
| --- | --- |
| **STRIPE CAN DO** | Mechanically available per current official docs, cited. |
| **SNATCH IT CURRENTLY DOES** | Read from the repository at this tip. |
| **SNATCH IT POLICY** | A choice. **Not decided here.** Named and stopped at. |

> **Stripe behaviour is not business-policy authority.** Nothing in the STRIPE CAN DO bucket
> is a recommendation. Section 8 lists the decisions this document deliberately refuses to make.

---

## 1. Verdict, stated first

**Transfer reversal does not solve the recovery problem. It relocates it, and it succeeds
mainly in the cases where recovery was never hard.**

The governing sentence is one line of Stripe documentation:

> "It's only possible to reverse a transfer if the connected account's available balance is
> greater than the reversal amount or has connected reserves enabled."
> — <https://docs.stripe.com/connect/separate-charges-and-transfers#reverse-transfers>

Reversal is not a clawback against the venue's bank. It is a **balance-to-balance move that
requires the money still to be sitting in the connected account's Stripe available balance**.
The scenario the platform actually fears — the venue was paid, the venue's payout ran to their
bank, then the chargeback lands — is precisely the scenario in which the balance is gone.
Reversal is strongest exactly when the platform needed it least.

Stripe's own wording concedes this. On the disputes path it says the platform can
"**attempt** to recover funds" (emphasis added), not recover them:

> "your platform balance is automatically debited for the disputed amount and fee. When this
> happens, your platform can attempt to recover funds from the connected account by reversing
> the transfer" — <https://docs.stripe.com/connect/charges#disputes-and-chargebacks>

Reversal is a **collection instrument, not a guarantee**. The instrument that actually
determines recovery is **whether the money was still holdable when the claim arrived** —
i.e. timing and reserve, not the reversal API. Sections 5 and 6 cover those.

Two qualifications, so the verdict is not overstated:

- **The "connected reserves" escape hatch in that sentence is real but gated.** A genuine
  platform-controlled reserve product exists (Radar for Platforms, §6.1) — but it is **private
  preview**, capped at 180 days, and requires the platform to own negative-balance liability and
  to disclose the policy in its Terms of Service. It is not something this codebase can simply
  switch on.
- **Stripe's second recovery instrument, Account Debits, shares the same fatal constraint** —
  it "can't make the connected account balance become negative" (§6.3). **There is no Stripe
  mechanism that extracts money from an empty connected-account balance.** The only thing that
  reaches a venue's *bank* is `debit_negative_balances` (§5), and that fires only after a
  reversal has already succeeded in creating the negative balance — which is the step in
  question. Recovery therefore rests on **timing**, not on any API.

---

## 2. STRIPE CAN DO — separate charges and transfers: who holds funds, who is liable

| Fact | Citation |
| --- | --- |
| The charge lands on the **platform** balance; a separate transfer moves funds out of the platform balance to the connected account. | <https://docs.stripe.com/connect/charges#separate-charges-transfers> |
| **"Your account balance is debited for the cost of the Stripe fees, refunds, and chargebacks."** | same |
| Negative transactions are assigned to the account the charge was made on: **"When charging on your platform, a refund or chargeback comes from your platform account."** | <https://docs.stripe.com/connect/account-balances#accounting-for-negative-balances> |
| Refund does **not** touch the transfer: "refunding a charge has no impact on any associated transfers. It's up to your platform to reconcile any amount owed back to it by reducing subsequent transfer amounts or by reversing transfers." | <https://docs.stripe.com/connect/separate-charges-and-transfers#issue-refunds> |
| There is **no `reverse_transfer` parameter** on a separate-charges refund. That parameter is destination-charges-only. Reversal must be a separate, explicit API call. | <https://docs.stripe.com/connect/marketplace/tasks/refunds-disputes> |
| **Legacy Express/Custom accounts: "your platform is responsible for disputes and fraud."** | <https://docs.stripe.com/connect/charges#disputes-and-chargebacks> |

**Exposure, stated plainly:** under this model the platform is the payer of first resort for
every refund, dispute fee and chargeback, automatically and without any action by the venue.
The venue is not debited. The platform must then go and get the money back.

## 3. STRIPE CAN DO — chargebacks after a transfer: which balance, when

> "For disputes where payments were created on your platform using destination charges or
> separate charges and transfers, **with or without `on_behalf_of`**, your platform balance is
> automatically debited for the disputed amount and fee."
> — <https://docs.stripe.com/connect/charges#disputes-and-chargebacks>

Mechanically it is **the platform's problem**, immediately and unconditionally. `on_behalf_of`
does not shift it. Stripe performs no automatic clawback from the connected account for a
platform-account charge. The transfer that already went out is untouched by the dispute.

## 4. STRIPE CAN DO — transfer reversal, precisely

`POST /v1/transfers/{id}/reversals` — <https://docs.stripe.com/api/transfer_reversals/create>

| Question asked | Answer | Citation |
| --- | --- | --- |
| **Partial supported?** | Yes. "you can optionally reverse part of the transfer. You can do so as many times as you wish until the entire transfer has been reversed." | create |
| **Repeatable?** | Yes, up to the transfer amount. "Once entirely reversed, a transfer can't be reversed again." Error when reversing "more money than is left on a transfer." | create |
| **Partial restriction** | "Partial transfer reversals are only allowed for transfers to Stripe Accounts." (Both Snatch It rails target Stripe accounts — satisfied.) | create |
| **Depends on connected account balance?** | **Yes — this is the binding constraint.** See §1 quote. | separate-charges#reverse-transfers |
| **Direction of funds** | "Transfer reversals add the specified (or entire) amount back to the platform's available balance, reducing the connected account's available balance accordingly." | same |
| **Currency-conversion failure mode** | "If the transfer reversal requires a currency conversion, and the reversal amount would result in a zero balance after the conversion, it returns an error." | same |
| **Refund-disabled account** | "Disabling refunds for a connected account won't block the ability to process transfer reversals." | same |
| **Insufficient-funds error** | `balance_insufficient` — "The transfer or payout couldn't be completed because the associated account doesn't have a sufficient balance available." | <https://docs.stripe.com/error-codes> |
| **Time limit / expiry** | **NOT DOCUMENTED — unverified.** No transfer-reversal page states a window. The 90-day limit found in search belongs to **payout** reversals, a different object; do not conflate. | <https://docs.stripe.com/connect/payout-reversals> |
| **Is a reversal itself reversible?** | **No undo endpoint.** Update "only accepts metadata and description as arguments"; there is no delete/void. The documented undo is a **new forward transfer**, which needs platform balance and is "subject to cross-border transfer restrictions, meaning you might have no means to repay your connected account." | <https://docs.stripe.com/api/transfer_reversals/update>, <https://docs.stripe.com/connect/marketplace/tasks/refunds-disputes> |
| **Auditability** | `transfer_reversal` object (`trr_…`) with `balance_transaction` (platform side), `destination_payment_refund` (`pyr_…`, connected side), `source_refund`, `transfer`. On the Transfer: `amount_reversed`, `reversals[]`, `reversed`. | <https://docs.stripe.com/api/transfer_reversals/object>, <https://docs.stripe.com/api/transfers/object> |

### 4.1 ⚠️ Documented contradiction — do not architect around it

Two official pages disagree on whether a reversal may push a connected account negative:

- **Blocks:** "only possible to reverse a transfer if the connected account's available balance
  is greater than the reversal amount or has connected reserves enabled" —
  <https://docs.stripe.com/connect/separate-charges-and-transfers#reverse-transfers>
- **Allows negative:** "If their balance can't cover the refund, you can reverse the transfer
  without issuing the refund, **which results in a negative balance on the account.**" —
  <https://docs.stripe.com/connect/risk-management/best-practices>

Behaviour plausibly varies with reserve and loss-liability configuration. **Any Snatch It design
must treat "reversal against a drained account" as an outcome that may fail, and must have a
defined path for the failure.** It must not assume success.

### 4.2 ⚠️ `reversed` is false on a partial reversal — a reconciliation trap

> "`reversed` — Whether the transfer has been fully reversed. **If the transfer is only
> partially reversed, this attribute will still be false.**"
> — <https://docs.stripe.com/api/transfers/object>

`amount_reversed` is the only honest signal. See §7.2 — the repository currently reads `reversed`
alone.

### 4.3 ⚠️ Stripe may reverse transfers on its own

For platforms created **on or after 2025-01-01**, Stripe automatically reverses transfers when
an asynchronous payment method later fails, producing "The transfer tr_xxxxxx is already fully
reversed" on a platform's own subsequent attempt —
<https://support.stripe.com/questions/getting-the-transfer-is-already-fully-reversed-errors-after-handling-charge-failed-webhook>.
The older guide text still asserts the opposite for non-async-aware integrations. **Snatch It's
platform creation date must be established before any reversal caller is written**, or the
caller will race Stripe and mis-handle a benign error as a failure.

### 4.4 THE SETTLED QUESTION — `source_transaction` and reversal

**No documented behavioural difference.** No Stripe page states that a transfer created with
`source_transaction` reverses differently from one funded from the platform available balance:
not in balance rules, not in partial support, not in the failure set. The reversal constraint is
stated purely in terms of the **connected account's** available balance
(<https://docs.stripe.com/connect/separate-charges-and-transfers#reverse-transfers>), a quantity
in which `source_transaction` plays no part. `source_transaction` is described only as a
**funding/timing** attribute — "ID of the charge that was used to fund the transfer. **If null,
the transfer was funded from the available balance**" (<https://docs.stripe.com/api/transfers/object>).

**This is a negative finding: confirmed absent from the docs, not confirmed safe by test.**

Consequences for Snatch It's two rails:

- **The H3 ruling is not weakened by reversal.** The settlement rail's decision to omit
  `source_transaction` (H3 §3) carries **no documented reversal penalty**. Both rails face the
  identical constraint — the venue's available balance.
- **One asymmetry does exist, and it runs the other way.** For a `source_transaction` transfer
  whose source charge later *fails*, reversal is Stripe's **documented recovery path**: "When a
  payment used as a `source_transaction` fails, funds from your platform's account balance are
  transferred to the connected account to cover the payment. To recover these funds, reverse the
  transfer associated with the failed `source_transaction`."
  (<https://docs.stripe.com/connect/separate-charges-and-transfers#transfer-availability>) The
  settlement rail, having no `source_transaction`, is not exposed to that particular failure —
  it never transfers against an unsettled charge, because maturity already holds it.
- **Unconfirmed:** whether a transfer still `pending` (source charge unsettled) can be reversed
  at all. Docs are silent. Only the resale rail can be in that state.

## 5. STRIPE CAN DO — negative connected-account balances

| Fact | Citation |
| --- | --- |
| "If a connected account balance is negative, Stripe debits their external account on file up to the maximum number of attempts allowed. If all attempts fail, Stripe pauses payouts to and debits from the external account until the external account on file is updated." | <https://docs.stripe.com/connect/account-balances#accounting-for-negative-balances> |
| That external-account debit happens **only if `debit_negative_balances` is `true`**. | <https://docs.stripe.com/connect/charges#disputes-and-chargebacks> |
| Countries supporting auto-debit: **Australia, Canada, Europe (SEPA, incl. UK), New Zealand, United States.** Snatch It is US → **supported**. | account-balances |
| "Stripe can't correct a negative Stripe account balance using a **debit card**." | account-balances |
| Enabling it "triggers debits as needed, **even when the connected account is on manual payouts**." | account-balances |
| Who bears an uncollected loss is read from `controller.losses.payments` (Accounts v1) — `stripe` or `application`. | account-balances |
| While negative, the account cannot receive payouts. | account-balances |

**Field path — get this right.** On Accounts v1 the flag is **`settings.payouts.debit_negative_balances`**
(`POST /v1/accounts/{id}`). It is **not** under `settings.payments`, which on v1 holds only statement
descriptors. On Accounts v2 / Balance Settings the equivalent is `payments.debit_negative_balances`
via `POST /v1/balance_settings` with a `Stripe-Account` header
(<https://docs.stripe.com/connect/manage-payout-schedule>, <https://docs.stripe.com/api/balance-settings/object>).

**Default value: only half documented.** Stripe states automatic debiting "is set to false for
connected accounts where the platform is responsible" for requirement collection, "(including
Custom accounts)" (<https://docs.stripe.com/connect/risk-management/best-practices>). **A default
of `true` for Standard/Express is NOT documented** — it is only an inference from that negation.
**Read the live value from the account before assuming either way.**

US auto-debit specifics (<https://support.stripe.com/questions/auto-debit-faq>): debits post the
**next business day**; Standard accounts are debited only when the negative balance exceeds
**10 units of local currency**, while Express and Custom are debited for any amount.

**The 180-day rule — the platform pays:**

> "When a connected account holds a negative balance amount for 180 days, Stripe transfers a
> portion of your balance to zero out that account's balance by creating a balance transaction
> with the type `connect_collection_transfer`."
> — <https://docs.stripe.com/connect/account-balances#understanding-connected-reserve-balances>

Stripe also advises rejecting the account afterwards ("we recommend that you reject the account
to prevent future losses", same URL). **`connect_collection_transfer` is the platform absorbing
the loss, with a Stripe-generated audit row. It is the terminal state of failed recovery.**

## 6. STRIPE CAN DO — reserves and holding funds

**"Connected reserves" are Stripe's, not the platform's.** The escape hatch named in the
reversal constraint is *not* a platform-configured reserve over a venue:

> "To protect against negative connected account `available` balances that your platform is
> responsible for, Stripe holds a reserve **on your platform account's `available` balance**."
> — <https://docs.stripe.com/connect/account-balances#understanding-connected-reserve-balances>

That reserve is Stripe ring-fencing *the platform's own money* to cover a venue's negative
balance. It improves Stripe's position, not Snatch It's recovery odds. It applies **only where
the platform is responsible** for negative balances; where Stripe is responsible, "Stripe doesn't
hold reserves on your platform account" (<https://docs.stripe.com/connect/risk-management>).

### 6.1 A real reserve API exists — but it is private preview

**Correcting a natural assumption: Stripe does have a platform-controlled reserve product.**

> "Reserves allow Connect platforms who own liability for negative balances to hold a portion"
> of a connected account's funds. — <https://docs.stripe.com/api/reserves>

It is "part of the **Radar for Platforms** product which is currently in **private preview**"
(same URL) — early access must be requested; it is not generally available.

Shape (<https://docs.stripe.com/connect/connected-account-reserves>, api-version
`2025-08-27.preview`): objects `ReserveHold`, `ReservePlan`, `ReserveRelease`; **fixed** reserves
(release on a date) and **rolling** reserves (release N days after each charge, holding a
percentage). Held funds appear in the connected account's `risk_reserved` balance.

Constraints that matter:

- **"You can't reserve funds for longer than 180 days"**, and a hold "can never be more than 180
  days after its creation date."
- **⚠️ A refund or dispute *smaller* than the hold does not release it** — "The dispute or
  refunded amount is taken from the connected account's balance, which can cause it to become
  negative." Reserving does not automatically pay the claim.
- Disabling a plan **immediately releases all its holds**; there is no pause.
- **"your Terms of Service must clearly explain your reserve policy."**

A separate lever, generally available: **`payments.payouts.minimum_balance_by_currency`** on
Balance Settings — a per-currency floor the platform can set per connected account to keep funds
in the balance after **automatic** payouts, specifically to absorb refunds, disputes and fees
(<https://docs.stripe.com/payouts/minimum-balances-for-automatic-payouts>). Not supported in
Brazil, India, Thailand. **Unconfirmed:** whether it constrains a *manual* payout.

### 6.2 Timing levers — what Stripe names

What a platform otherwise controls is **timing**, and Stripe names exactly two levers:

> "- Hold funds in the platform balance before transferring them to a connected account balance
>  - Hold funds in a connected account's balance before paying them out"
> — <https://docs.stripe.com/connect/account-balances#holding-funds>

Lever 1 is **the only one that keeps money on the platform side of the reversal constraint**,
and it is the lever Snatch It already pulls (settlement maturity, §7.1). Lever 2 keeps money in
the venue's Stripe balance — which is precisely the balance a reversal can reach, so it
materially improves reversal odds without the platform ever holding the funds.

Lever 2 specifics (<https://docs.stripe.com/connect/manage-payout-schedule>):

- **`delay_days` maximum is 31** (`delay_days_override` "to a number up to 31"). It "can't be less
  than your own payout schedule or less than the default payout schedule for the account."
- Editable **per connected account**, and only "on accounts where you own fraud and dispute
  liability." The v1 path `settings.payouts.schedule.delay_days` still works.
- **`interval: manual` is not indefinite.** Funds are held "until you specify otherwise", but
  "You must pay out the funds within the time period specified below" — **United States: 2 years**;
  Thailand 10 days; all other countries 90 days. And explicitly: **"Stripe doesn't provide escrow
  services or support escrow accounts."** (<https://docs.stripe.com/connect/manual-payouts>)

### 6.3 A second recovery instrument: Account Debits

Distinct from reversal, and worth knowing because it has the **same fatal constraint**:

> "Debiting an account can't make the connected account balance become negative."
> — <https://docs.stripe.com/connect/account-debits>

Account Debits pull funds from a connected account's Stripe balance to the platform. They require
platform-owned negative-balance liability, **"legally binding consent from your connected
accounts"**, same-region (or listed corridors), a max of **100,000 USD**, and carry an additional
Connect cost. **It is a collection tool for a positive balance, not a cure for a drained one** —
so it does not change §1's verdict.

**Stripe attaches an explicit caution to holding funds:**

> "We recommend that platforms hold funds only when there's a clear purpose and a commitment to
> transfer them or pay them out when an event occurs or a precondition is satisfied. … We advise
> against platforms holding funds arbitrarily … If you aren't sure about holding funds, speak
> with your legal advisor." — same URL

Compliance-driven maximum holding period, **United States: 2 years** (same URL).

## 7. SNATCH IT CURRENTLY DOES — read from the repository

### 7.1 The two rails and their funding

| | Resale rail | Settlement (venue) rail |
| --- | --- | --- |
| Caller | `supabase/functions/_shared/payouts.ts` | `supabase/functions/payout-execute/` |
| `source_transaction` | **Set** (`payouts.ts:139`) | **Not set** (H3 §3) |
| Idempotency key space | `_src` | `_v1` (`executor.ts:262`) |
| Funding | The specific charge | Platform available balance, with a mandatory balance preflight (`executor.ts:528` `evaluateBalance`) |

Both create exactly one Stripe Transfer per payout row.

### 7.2 **There is no transfer-reversal call anywhere in the repository — VERIFIED**

A repo-wide search (excluding `node_modules`) for `/reversals`, `createReversal`,
`transferReversal` and `transfers/…/reversal` across `*.ts`, `*.tsx`, `*.sql`, `*.js` returns
**zero hits**. The Stripe endpoints the edge functions call are `/accounts`, `/balance`,
`/payment_intents`, `/refunds`, `/transfers`, `/payouts`, `/customers`. **`/reversals` is absent.**

What exists is **bookkeeping for reversals initiated elsewhere (i.e. by a human in the Stripe
Dashboard):**

- `supabase/functions/stripe-webhook/index.ts:1133` handles `transfer.reversed` and calls
  `mark_transfer_reversed` — it *records* a reversal, never causes one.
- `public.mark_transfer_reversed(text)` — `supabase/migrations/0561_transfer_writer_rpcs.sql:114`,
  `service_role` only.
- `kernel.mark_payout_transfer_state` permits exactly one terminal-to-terminal edge,
  `paid → reversed` (`supabase/migrations/085_kernel_money_native.sql:1699-1701`). **Nothing in
  the codebase drives it.**
- `public.transfers.status` has allowed `'reversed'` since
  `supabase/migrations/024_disputes.sql:69`, whose comment already anticipated
  `debit_negative_balances` — **which nothing in the repository sets.**

**Therefore: reversal is today a manual, out-of-band human action in the Stripe Dashboard. The
system observes it. The system cannot perform it.**

### 7.3 Dispute handling today

`stripe-webhook/index.ts`:

- `charge.dispute.created` (`:951`) — freezes the transfer via `freeze_transfer_for_dispute`
  **only if `payout_released_at IS NULL`**. Once paid out, the code's own comment states: "at
  that point we can only attempt a transfer reversal when the dispute is lost" (`:986`).
- `charge.dispute.closed` (`:1048`) — on `lost`, marks the payment `refunded` and **deliberately
  makes no money move**: "Don't make autonomous money moves here. Just sync state." (`:1074`).
  The comment names the open choice: "ops decides between transfer-reversal (if already paid
  out) or simply mark the payment refunded."

`refund-execute/index.ts` calls only `POST /v1/refunds`. It has no recovery leg.

**Net: money out the door before a claim arrives is, today, recovered only if a human opens the
Stripe Dashboard.** That is a deliberate, documented posture — not an oversight — but it is
unbounded and unmeasured.

### 7.4 Two defects observed (reported, not fixed — this train writes no code)

**(a) Partial reversal is invisible to reconciliation.**
`supabase/functions/payout-execute/executor.ts:785-798` (`planPayoutStateSync`) declares its
parameter as `{ id?: unknown; reversed?: unknown; amount_reversed?: unknown }` but **reads only
`reversed === true`**. Per §4.2, a partially reversed transfer reports `reversed: false`. Such a
transfer would be marked `paid` **at its full face amount**, asserting money the venue does not
have — the exact condition the guard's own message says it exists to prevent
("`'paid'` would assert money the venue does not have"). `amount_reversed` is accepted and
ignored. The same blind spot applies to `mark_transfer_reversed`, which is all-or-nothing.

**(b) No `debit_negative_balances`, no payout-schedule control.**
`create-connect-account/index.ts:203` creates `type: 'express'` accounts and sets **no**
`settings.payouts.debit_negative_balances`, **no** `settings.payouts.schedule`, and no
`delay_days` or `minimum_balance_by_currency`. A repo-wide search for `debit_negative_balances`,
`delay_days`, `minimum_balance` and payout-schedule keys finds **only a comment** in
`supabase/migrations/024_disputes.sql:57` — no code sets any of them. Combined with §2's "if
you're using Express or Custom legacy account types, your platform is responsible for disputes
and fraud", every one of Stripe's recovery aids — external-account debit (§5), payout-timing
holds and minimum balances (§6.2) — is currently **left at default and unexercised**. Whether to
change that is §8. Note that the default value of `debit_negative_balances` for Express is **not
documented** (§5): it must be read from a live account, not assumed.

---

## 8. SNATCH IT POLICY — decisions this document does not make

Each of these is a genuine choice with real trade-offs. **Named and stopped at.**

1. **Whether to build an automated transfer-reversal caller at all**, or keep reversal as a
   deliberate human Dashboard action. The current posture is explicit and defensible; §7.3's
   code comment shows it was chosen, not forgotten. Automating a money move out of a venue's
   balance is a commercial and legal decision.
2. **Whether to set `debit_negative_balances = true` on venue accounts.** Mechanically available
   in the US (§5). It authorises Stripe to debit a venue's bank account. That is a merchant-terms
   question before it is an engineering one.
3. **Whether to hold venue funds in the venue's Stripe balance via a manual or delayed payout
   schedule** (§6.2) to keep money within reversal's reach. Stripe explicitly cautions against
   holding "arbitrarily" and says to consult a legal advisor. Note the US 2-year cap and the
   "no escrow" statement.
3b. **Whether to pursue Radar for Platforms reserves** (§6.1, private preview — requires
   requesting access) or the generally-available `minimum_balance_by_currency` floor. Both change
   what venues receive and when; the reserves product **requires a Terms of Service disclosure**.
3c. **Whether Snatch It or Stripe should own negative-balance liability.** Stripe's own guidance
   pulls two ways: <https://docs.stripe.com/connect/risk-management> says indirect-charge
   marketplaces should "assign negative balance responsibility to your platform, not to Stripe",
   while <https://docs.stripe.com/connect/risk-management/best-practices> says "We advise that new
   platforms have Stripe take responsibility for negative balances… Only consider taking
   responsibility as the platform if you're confident in your ability to manage merchant risk."
   **Neither page reconciles the other.** This choice gates §6.1 and §6.3 entirely — both require
   platform-owned liability — and it is not an engineering call.
4. **What happens when reversal fails** — the drained-account case of §4.1. Absorb as platform
   loss (the `connect_collection_transfer` terminus, §5), pursue the venue off-Stripe, or net
   against future settlements ("reducing subsequent transfer amounts", §2). Stripe supports all
   three; it endorses none.
5. **Whether the settlement rail's maturity hold is the intended risk control.** It is currently
   the platform's entire protection, and §6 shows it is Stripe's lever 1 — the strong one. If it
   *is* the control, that should be stated as such and its window justified against dispute
   timelines rather than left implicit.
6. **Whether defect 7.4(a) is in scope for this train.** It is a correctness bug independent of
   any policy choice above.

---

## 9. Constraints that bind any Snatch It design

1. Recovery from a venue is **gated on the venue's Stripe available balance at the moment of the
   reversal call**, not on the platform's rights (§1). Design for failure as a normal outcome.
2. **The platform is debited first, automatically, always** — refunds, disputes, dispute fees
   (§2, §3). There is no configuration that changes this under separate charges and transfers.
3. **A refund never touches a transfer.** Recovery is a separate, explicit call, or it does not
   happen (§2).
4. **A reversal cannot be undone.** The only reversal is a new forward transfer, needing platform
   balance and subject to cross-border restriction (§4).
5. **`reversed` is not a reversal detector.** Only `amount_reversed` is (§4.2). Binds §7.4(a).
6. **Stripe may reverse first** for post-2025-01-01 platforms; "already fully reversed" must be
   treated as benign, not as failure (§4.3).
7. **No reversal time limit is documented.** Do not rely on there being none, and do not import
   the 90-day payout-reversal window (§4).
8. **`source_transaction` presence changes nothing about reversal** (§4.4). H3 stands. Both rails
   share one constraint: the venue's available balance.
9. **Platform-imposed reserves exist but are private preview** (Radar for Platforms, §6.1) and are
    capped at 180 days. Generally available today: `delay_days` ≤ 31, manual payout interval
    (US cap 2 years, no escrow), and `minimum_balance_by_currency` (§6.2). All require
    platform-owned liability.
10. **180 days of negative balance ends with the platform paying**, via
    `connect_collection_transfer` (§5).
11. **Express accounts make the platform responsible for disputes and fraud** (§2).
12. **Account Debits share reversal's fatal constraint** — they "can't make the connected account
    balance become negative" (§6.3), and additionally require legally binding venue consent. There
    is no Stripe instrument that recovers money from an empty balance.
13. **Dispute liability is identical between destination charges and separate charges and
    transfers** (both "reduce your platform's balance", §2). The model choice buys transfer
    timing and one-to-many splitting, **not** a different liability position — so switching models
    is not a recovery fix.

---

## 10. Sources

- <https://docs.stripe.com/connect/charges> — charge-type comparison, refunds table, disputes and chargebacks
- <https://docs.stripe.com/connect/separate-charges-and-transfers> — reverse transfers, issue refunds, transfer availability
- <https://docs.stripe.com/connect/account-balances> — negative balances, `debit_negative_balances`, connected reserves, 180-day `connect_collection_transfer`, holding funds
- <https://docs.stripe.com/api/transfer_reversals> · <https://docs.stripe.com/api/transfer_reversals/create> · <https://docs.stripe.com/api/transfer_reversals/object> · <https://docs.stripe.com/api/transfer_reversals/update>
- <https://docs.stripe.com/api/transfers/object> · <https://docs.stripe.com/api/transfers/create>
- <https://docs.stripe.com/connect/marketplace/tasks/refunds-disputes> — `reverse_transfer` scope, re-transfer caveat
- <https://docs.stripe.com/connect/risk-management/best-practices> — negative-balance reversal statement (conflicts with the above, §4.1)
- <https://docs.stripe.com/error-codes> — `balance_insufficient`
- <https://docs.stripe.com/connect/payout-reversals> — 90-day window (payouts, NOT transfers)
- <https://support.stripe.com/questions/getting-the-transfer-is-already-fully-reversed-errors-after-handling-charge-failed-webhook> — automatic reversal for post-2025-01-01 platforms
- <https://docs.stripe.com/connect/disputes> — dispute debiting per charge type
- <https://docs.stripe.com/api/reserves> · <https://docs.stripe.com/connect/connected-account-reserves> — Radar for Platforms reserves (private preview)
- <https://docs.stripe.com/connect/manage-payout-schedule> — `delay_days` ≤ 31, Balance Settings paths
- <https://docs.stripe.com/connect/manual-payouts> — manual interval, holding-period caps, no escrow
- <https://docs.stripe.com/payouts/minimum-balances-for-automatic-payouts> · <https://docs.stripe.com/api/balance-settings/object> — `minimum_balance_by_currency`
- <https://docs.stripe.com/connect/account-debits> — pulling funds from a connected account
- <https://docs.stripe.com/connect/risk-management> · <https://docs.stripe.com/connect/risk-management/best-practices> — negative-balance liability assignment (conflicting guidance, §8.3c)
- <https://support.stripe.com/questions/auto-debit-faq> — per-country × account-type auto-debit matrix
- <https://docs.stripe.com/reports/balance-transaction-types> — `connect_collection_transfer`, `reserve_transaction`

**Confirmed non-existent:** `https://docs.stripe.com/connect/negative-balances` returns HTTP 404;
negative-balance handling lives in `/connect/account-balances` and `/connect/risk-management`.

**Could not confirm from official docs (do not treat as settled):** any reversal time limit;
whether a reversal can push an account negative (§4.1 conflict); whether a `pending`
(`source_transaction`-gated) transfer is reversible; a documented `true` default for
`debit_negative_balances` on Standard/Express; whether `minimum_balance_by_currency` constrains
manual payouts.

**Repository evidence:** `supabase/functions/_shared/payouts.ts` ·
`supabase/functions/payout-execute/index.ts` · `supabase/functions/payout-execute/executor.ts` ·
`supabase/functions/stripe-webhook/index.ts` · `supabase/functions/refund-execute/index.ts` ·
`supabase/functions/create-connect-account/index.ts` ·
`supabase/migrations/085_kernel_money_native.sql` ·
`supabase/migrations/0561_transfer_writer_rpcs.sql` · `supabase/migrations/024_disputes.sql` ·
`docs/phase2/_impl/H3_transfer_cardinality.md`
