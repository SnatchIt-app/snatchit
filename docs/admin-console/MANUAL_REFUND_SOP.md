# Manual refund SOP (founders, while console refunds are off)

> **DRAFT — not approved for use.** A (payments) reviews the money wording,
> and the owner approves the SOP for use. Until then, every sentence here
> about money is a proposal. Do not follow it for a real refund. A's part is
> review only: no step below depends on A acting (§10).

| | |
|---|---|
| **Who** | Founders (console role `platform_admin`), each using their own Stripe Dashboard login. Never share a login. |
| **When** | Console refund execution is **off on the server**: **System → Settings** shows `refund_execute_enabled` as `false` (§2 row 1). The setting is seeded `false` [115:144-145]. The order page's **Execute refund** warning *"Disabled until ops-refund-execute is deployed."* is only a prompt to check: the page also shows it when its own settings read fails [ORDER:73-79], [ORDER:432-437]. |
| **Covers** | Marketplace resale orders on **Orders** whose payment `mode` is `buy_now` or `auction`. |
| **Does not cover** | Primary-ticket orders (`mode = native_primary` [093:3005]). They refund on a separate rail; escalate those to the owner. Stripe chargebacks (disputes raised at the buyer's bank) follow the evidence process, not this SOP. |
| **Replaces** | For founders, Part 1 and the "Emergency" section of `docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md` (2026-04-01, private beta). Never run that playbook's SQL. §11 explains why. |
| **Derived from** | Code at `origin/release/production-gate-20260918` @ `6f982f36` (database, edge functions) and `origin/admin/operating-console` @ `07100a35` (console). Each claim cites a source; aliases are resolved in §13. Items marked **Not verified** were not checked against production. |

## The five rules

1. **There is one manual money step:** a full refund of the PaymentIntent in
   the Stripe Dashboard (§4). Everything else either happens automatically
   (§5) or is recorded in the console (§3, §6).
2. **Never write to the database.** That means no SQL editor, no
   `UPDATE`/`INSERT`, and no hand-called functions, whether on payments,
   transfers, listings or `ops` tables. Not even "just to fix the status". §11
   explains why.
3. **Look before you click.** Refund only after every check in §2 passes.
   Never click Refund twice (§4.3).
4. **Some refunds need the owner's decision first:** partial refunds, refunds
   after the seller was paid, and any transfer reversal (§8, §9). This SOP
   does not authorise them.
5. **Do not press "Request refund (will be rejected: disabled)".** While the
   setting is `false` it cannot move money: the server rejects it at request
   time and leaves a rejected `refund_execute` action on the order
   [ORDER:446], [118:251-255], [144:546-555]. The label comes from the same
   settings read as the warning, so when that read has failed the request is
   not rejected: it parks a real refund for the other founder's approval
   [144:556-563].

## At a glance (buyer win, seller not yet paid)

1. Console: **Resolve dispute** → **Buyer win** (§2 row 4).
2. Within 5 minutes a **"Refund owed to buyer"** case opens. Assign it to
   yourself and note your intent (§3).
3. Run every check in §2.
4. Stripe Dashboard: a **full** refund of the PaymentIntent, reason
   *Requested by customer*, no metadata (§4).
5. Note the `re_…` id on the case and set the case to *Waiting* (§6).
6. Verify in the console and in Stripe (§7). The case closes itself.

## 1. When this SOP applies

The normal trigger is a **"Refund owed to buyer"** case (type
`refund_pending`, priority P1). The refunds detector runs every 5 minutes and
opens one for any payment that is not `refunded` and either [150:277-302],
[117:1122-1123]:

- has an in-app dispute resolved **for the buyer** (`resolved_buyer_refunded`)
  or as a **partial refund** (`resolved_partial_refund`), or
- has a transfer that **expired** more than 60 minutes ago while the payment
  is still captured. The case summary then reads "transfer expired at … and
  the payment is still succeeded".

Any other refund is an **owner decision**: a goodwill refund, a cancelled
event, or a refund on an order the buyer confirmed. Record that decision on a
case first (§3), then run every check in §2, especially row 8. On a transfer
that is neither *Disputed* nor *Expired*, the seller can still be paid while
you refund, and no console action holds a payout. That is an owner decision:
do not refund until the payout is settled or held by an owner-approved
action (§2, "Row 8: the seller payout").

## 2. Prerequisites (all read-only, all in the console unless marked)

Open the order: **Orders** → the payment, or **Cases** → the case → its
subject link.

| # | Check | Where | If it fails |
|---|---|---|---|
| 1 | Console refund execution is off **on the server** | **System → Settings** → `refund_execute_enabled` reads **`Current: false (boolean)`**, and the Settings panel shows no failure alert [SYS:231-240], [SYS:428], [116:1593-1601]. The order page's "Disabled…" warning does **not** prove this. The page shows it whenever its own settings read fails, and it treats every value except the boolean `true` as off [ORDER:73-79]. The server also treats the text `"true"` as on [118:252]. | It reads **`Current: true (boolean)`**: use the console refund (`OPERATING_GUIDE.md` → Taking a safe action → Execute refund) instead of this SOP. Never use both on one order. **Any other result:** stop and escalate to the owner. That covers a Settings error, a missing key, and every value that is neither the boolean `false` nor the boolean `true`, for example the text `"true"` or `"false"` (shown as `(string)`). |
| 2 | The order is a resale order | **Payment** panel → `mode` is `buy_now` or `auction`. | `native_primary`: stop and escalate to the owner. |
| 3 | Live mode | The order header shows **no** "stripe test mode" badge, **and** row 10 finds the PaymentIntent in the Stripe Dashboard in **live mode**. Row 10 is your proof of live mode. The console cannot show more yet: the badge appears only when `stripe_livemode` is `false` [ORDER:122], so no badge means `true` **or** unclassified (`NULL`) [045:17]. Unclassified is the remaining gap: every automated money path refuses `NULL` [PL:144-152], [ETE:615-625], [ETE:780-799], [148:125-134], so the expiry job neither refunds such a payment nor records its refunds. Console v2 (PR #121) adds an explicit **"Stripe mode: live / test / unclassified"** field to the order page. | **Interim rule, until the console shows the Stripe mode field:** no "stripe test mode" badge **and** the PaymentIntent found in live mode (row 10): proceed. Anything else: stop and escalate to the owner. **Once the field is shown:** it reads "unclassified" (or "test"): stop and escalate to the owner, even if row 10 finds the PaymentIntent in live mode. |
| 4 | The decision to refund is on record | **Buyer win:** Disputes panel → In-app dispute → `dispute_resolution` reads "Resolved — buyer (refund required)" [FMT:207-211]. If the dispute is still open, record it first: **Resolve dispute** → outcome **Buyer win** (founder or risk role [115:521]). That records the decision, moves no money, and leads to the "Refund owed to buyer" case [MSE:528-546], [065:130-142]. **Expired:** Transfer status reads "Expired (seller did not send)". **Anything else:** the owner's decision, written on a case (§3). | No recorded decision means no refund. |
| 5 | The payment is captured | The header badge reads **"payment: Captured"** (`succeeded`) [FMT:65-73]. The Execute refund panel only renders in this state [ORDER:83]. | "Refund recorded (not confirmed settled)": a refund already exists, so do not refund. Go to §7. Pending, Processing or Failed: the payment is not captured. Stop and escalate to the owner. |
| 6 | No Stripe chargeback **of any status** | Disputes panel → **Stripe disputes (chargebacks)** reads "No Stripe disputes (chargebacks) on this payment." [ORDER:262-265], [ORDER:521]. | **Any row, whatever its status** (still open, won, lost or otherwise closed): do not refund; stop and escalate to the owner. A lost chargeback reaches the payment row only through the `charge.dispute.closed` webhook, as a `dispute_lost` refund record [WH:680-698]; if that webhook was missed, the payment still reads *Captured*. While a chargeback is open, Stripe refuses a refund on the charge (Stripe behaviour, not verified; the console executor treats it as a definite error [ORE:110]). A chargeback has its own process (`OPERATING_GUIDE.md`, "Evidence due"). |
| 7 | No console refund attempt in flight or parked | Refund panel → **Refund execution attempts** is absent or lists only *Rejected* rows [ORDER:295-302]. A row can read *Requested*, *Awaiting approval*, *Processing — …*, *Outcome unknown*, *Succeeded at provider*, *Succeeded*, *Failed* or *Rejected* [FMT:115-124], [FMT:140-149]. | *Awaiting approval*: the request is parked, and it still runs if the setting is later turned on and the other founder approves it [118:217-220]. Before the money step, the founder who did **not** request it opens **System → Approvals** and presses **Deny**, with a reason. The requester cannot decide their own request [SYS:395-396], [SYS:404]. A denied action reads *Rejected* [118:209-214]; re-check this row. If the deny is refused, escalate to the owner. **Any other state except *Rejected***: stop. `RUNBOOK.md` §5.3 forbids a hand refund while a console attempt is in flight [RUNBOOK:129-133]. Escalate to the owner with the action id. |
| 8 | The seller has not been paid, and cannot be paid while you refund | **Transfer** panel status and **Seller funds state** panel [ORDER:178-243]: "Release recorded at" is empty, **and** "Stripe Transfer (connected account)" reads "none — funds not released", **and** the transfer status passes "Row 8: the seller payout" below. **Re-check this row immediately before you click Refund.** | Either release field set: this is a refund after payout (§9), an owner decision. Otherwise do what "Row 8: the seller payout" says for the transfer's status. |
| 9 | Full amount | You will refund exactly the Payment panel's **"Total charged to buyer"**. | Anything less is a partial refund (§8), an owner decision. |
| 10 | *(In Stripe, read-only)* Nothing refunded yet | Stripe Dashboard in **live mode** → the PaymentIntent (`pi_…`, copied from the Payment panel): it is found, the amount equals the console's total, **no refund is listed** and **no dispute is listed**. | The PaymentIntent is not found in live mode: stop and escalate to the owner. Never switch the Dashboard to test mode to look for it or refund it there. A dispute is listed: stop and escalate to the owner, because the console may have missed its webhook (row 6). A refund is already listed, in any status: do not refund again. Escalate to the owner, because the console has not recorded it yet. The amount differs: stop and escalate to the owner. |

**Row 8: the seller payout.** A new payout can be claimed only for a
transfer that is *Buyer confirmed* or *Auto-released*, and only while the
payment is `succeeded` [148:99-101], [148:121-124]. A payout attempt that was
already open is reconciled first, whatever the transfer's status is now
[148:72-89]. Go by the **Transfer** panel, in this order:

1. **Ever confirmed or released.** The status is *Buyer confirmed*,
   *Auto-released*, *Resolved — seller (no buyer confirmation)* or
   *Confirmed status, no confirmation record* [FMT:266-276]. Or
   `buyer_confirmed_at` is set, whatever the status and the "Payout state".
   Or the funds state is "Release scheduled". Stop and escalate to the
   owner, whatever the other fields say. Owner decision: do not refund until
   the payout is settled or held by an owner-approved action (below). The
   payout may already be under way:
   - the payout sweep picks these transfers up [ETE:1292-1308],
     [ETE:1328-1357];
   - after a genuine buyer confirmation, neither manual review nor a hold
     stops the claim [148:102-119], and the funds state then reads "Manual
     payout review" or "Held" instead of "Release scheduled" [116:231-235];
   - an attempt whose outcome is unknown leaves both release fields empty
     while Stripe may already have created the transfer [149:65-75];
   - the console has no payout-attempts view.
2. ***Disputed*** **(a buyer win) or** ***Expired (seller did not send)***,
   never confirmed. The claim refuses a new payout [148:96-101]. Row 8
   passes once both release fields are empty.
3. **Any other status** (*Awaiting seller delivery*, *Seller marked sent*;
   funds "Awaiting buyer confirmation / auto-release", "Held" or "Manual
   payout review"). Only an owner-decided refund reaches here. Stop and
   escalate to the owner. A buyer confirmation releases the payout straight
   away [CAR:4-8], and neither manual review nor a hold stops a genuine
   confirmation [148:102-119], so the seller can be paid at any moment.
   Owner decision: do not refund until the payout is settled or held by an
   owner-approved action (below).

**No console action holds a payout.** The console's only payout action,
**Release held payout** (`payout_release`), releases an unreleased *Seller
marked sent* transfer and never holds one [MSE:548-569], [ORDER:82],
[ORDER:399-404]. Neither the console @ `07100a35` nor console v2 has a hold
or freeze action [TYP:294-310], [TYP2:294-313], and neither does the
server's action set [115:235-238], [144:95-96], [115:515-528],
[MSE:356-719]. A suspension leaves payouts running [MSE:620], and the keys
**Change setting** can edit include no payout switch [115:144-153], [118:37],
[144:155], [145:58], [146:97], [150:259-260]. So for items 1 and 3 the rule
is: **owner decision; do not refund until the payout is settled or held by
an owner-approved action.** If it settles as paid, the refund is a refund
after payout (§9). An owner-approved hold counts only if it stops the claim
even after a genuine buyer confirmation; manual review and
`payout_hold_until` do not [148:102-119]. No step here requires a
hand-written production write, and rule 2 forbids one. Once the owner's
decision is on the case, re-check row 8 immediately before you click Refund.

**Expired orders only.** The expiry job refunds expired orders on its own.
Phase 1 refunds each newly expired order once and skips any payment already
fully refunded [ETE:627-639], [ETE:653-675]. Phase 1b runs on **every** run.
It selects each expired transfer whose payment is still `succeeded`, live, and
has no failed refund [ETE:767-801]. It lists that PaymentIntent's refunds at
Stripe and records them. If none of them is its own, none failed, and
together they cover less than the payment's total, it refunds **the
remaining balance** [ETE:811-866]. The job's refunds carry a metadata
`source` that starts with `enforce-transfer-expiry` and
`reason = transfer_expired` [ETE:669-674], [ETE:860-865].

- If Stripe lists **any** refund for the PaymentIntent, the refund is not
  missing, only unrecorded: escalate to the owner and do not refund.
- If Stripe lists none, tell the owner before you refund by hand. The job should have
  refunded the order itself, so it is failing or skipping this payment (for
  example because `stripe_livemode` is not `true`, row 3).
- **Never make a partial refund on an expired order:** the next run refunds
  the rest (§8).

**Second founder (proposal; owner to confirm).** In the console, a refund
needs the other founder's approval [115:532-536]. Until the owner rules
otherwise, apply the same rule here: before the money step, the second founder
adds a note to the case confirming the §2 checks.

## 3. Before the money step: record your intent on the case

1. Find the case: order page → **Cases on this order** → "Refund owed to
   buyer" [ORDER:312-313]. If there is none (for example, an owner-decided
   refund), use **Open a case on this order** [ORDER:462-464]. Title it
   "Manual refund — <event>", priority P2, and give the owner's decision as
   the reason.
2. **Assign** it to yourself. Assigning an *Open* case moves it to *In
   progress* [MSE:369-377].
3. **Add note** [CASE:115-138]. Notes are append-only and every operator can
   read them [115:201-213]. Use ids, never personal data: no names, emails,
   phone numbers or card details.

```
Manual refund per MANUAL_REFUND_SOP §4 (console refunds are off).
PaymentIntent: pi_…
Amount: $… = Total charged to buyer (full refund)
Why: buyer-win resolution <UTC date> | transfer expired <UTC date> | owner decision <case/note ref>
§2 checks 1–10: pass. Live mode (row 3): no test-mode badge; pi_… found in live mode (row 10). Second founder: <confirmed in note …>
```

Every console action, these notes included, is stored as an `ops.action` and
written to `ops.audit` with your identity [144:527-537], [115:299]. A database
write by hand records nothing.

## 4. The money step: a full refund in the Stripe Dashboard

### 4.1 Steps

These Dashboard labels come from the April playbook [DAY5:37-44]. They have
**not been re-verified** against the current Dashboard.

1. Open the Stripe Dashboard in **live mode** → **Payments** → search for the
   `pi_…` id → open the payment. If live mode does not find it, stop (§2
   row 10).
2. **Refund** → keep the **full** amount, which must equal the console's
   "Total charged to buyer" → reason **Requested by customer** → confirm.
3. Copy the refund id (`re_…`) and the status Stripe shows (for example
   *Pending* or *Succeeded*).

### 4.2 Reason

The webhook does not read Stripe's refund `reason`; it reads only the
refund's metadata [WH:24-28]. Use **Requested by customer** for buyer-win and
expiry refunds. Pick *Fraudulent* or *Duplicate* only on the owner's decision.
Stripe uses those values in its own fraud tooling (Stripe behaviour, not
verified here).

### 4.3 Idempotency: the Dashboard has no key, so you are the guard

- The Dashboard does not let you supply an idempotency key. The April
  playbook says the same of Dashboard transfers [DAY5:185-186]; this is
  **not verified** for refunds. The automated refunders each use a fixed key: `refund_expiry_<transfer>` [ETE:668],
  `refund_unfulfillable_<payment>` [ETE:526] and `ops_action_<action>`
  [ORE:6-12]. A Dashboard refund shares none of them, so nothing on our side
  de-duplicates it before Stripe does.
- Three things stand between an order and a second refund:
  - your checks (§2 row 10, and this step);
  - the expiry job's "already fully refunded" check, which only works once
    the webhook has recorded your refund [ETE:627-639]. Its Phase 1b also
    lists Stripe's refunds first and creates none when they cover the total
    [ETE:811-851];
  - Stripe, which will not refund more than is left on the charge. The code
    relies on this [ORE:91-95], [ETE:653-656], but the two comments describe
    Stripe's answer differently. **Not verified.**
- **If the dialog errors or hangs, do not click again.** Reload the payment.
  If a refund is listed, it went through: record it (§6). If none is listed,
  wait a minute and reload once more before one retry. If it is still unclear,
  escalate (§10).
- Our recording is idempotent per refund id. One row per `re_…`
  [150:49-63], [150:204-212]. A second insert of the same id is ignored
  [P3:503-506]. Duplicate webhook events are dropped [WH:212-252].

### 4.4 Metadata: leave it empty

Leave every metadata field empty. These are the keys our code reads:

- The webhook records a refund as source `dashboard` unless
  `metadata.source` starts with `enforce-transfer-expiry` [WH:24-28]. Only
  that key changes the classification. `reason` is read only after `source`
  matches, to tell an expiry refund from an unfulfillable one [WH:27]. Such
  a `source` would record your refund as the expiry job's, which misleads the
  refund-resolution triage text [144:178-192].
- The expiry job's Phase 1b counts a refund whose `metadata.transfer_id` is
  the order's transfer id as one of its own [ETE:841].
- Never add `metadata.ops_action_id`. The console refund executor adopts any
  Stripe refund whose `ops_action_id` matches one of its actions
  [ORE:128-142].

## 5. What happens automatically (no action needed)

### 5.1 Stripe tells the webhook

- **`charge.refunded`** [WH:733-797]: for every refund on the charge, the
  webhook calls `record_refund_state` with **that refund's own Stripe status**,
  source `dashboard` and channel `webhook` [WH:768-791]. If the write fails,
  it answers 500 so that Stripe redelivers [WH:788-791].
- **`refund.created` / `refund.updated` / `refund.failed`** [WH:963-1000]:
  the webhook re-reads the refund from Stripe and records its current status.
  This happens **only if the production endpoint subscribes to these events**
  [WH:1002-1005]. **Not verified.**
- **Not verified:** which webhook version is deployed. With the version from
  before migration 150, `charge.refunded` calls `record_payment_refund`
  directly with source `dashboard` [WH@037092f0:702-747]. A full refund ends
  in the same payment state (§5.3), but no per-refund status is kept.

### 5.2 Refund lifecycle (migration 150)

- `public.record_refund_state` is the only writer [150:125-253]. It keeps one
  row per Stripe refund in `payment_refund_state` [150:49-63] and an
  append-only change log [150:66-95]. It also keeps three sums on the payment
  (`refund_requested_cents`, `refund_succeeded_cents`, `refund_failed_cents`),
  which only it may change [150:97-122], [150:228-241].
- A refund that is *pending*, *requires_action* or *succeeded* is counted
  toward the payment's refunded total through `record_payment_refund`. A
  refund first seen *failed* or *canceled* is never counted [150:220-226].
- Once a refund is counted, it stays counted even if it later fails, so the
  seller payout stays blocked. The true status lives in the per-refund row
  [150:220-222]. An out-of-date observation of a failed or canceled refund is
  ignored [150:180-197].

### 5.3 The payment row (`record_payment_refund`) [P3:457-554]

- It adds a ledger row (`payment_refunds`, idempotent on `re_…`). It raises
  `amount_refunded_cents` to the larger of its old value and the sum of the
  ledger rows, capped at the payment's total [P3:503-515].
- When the refunded total reaches the payment's total: `status` becomes
  `refunded` and `refunded_at` is set. `stripe_refund_id` keeps the **first**
  refund ever recorded [P3:517-524]. `refunded` is terminal [P3:390-392].
- If the seller was already paid, it flags the payout for reversal (§9)
  [P3:526-546].

### 5.4 Detectors (run every 5 minutes) [117:1122-1123]

| Case (type) | Opens when | Closes when |
|---|---|---|
| "Refund owed to buyer" (`refund_pending`, P1, subject = payment) | §1 conditions [150:277-302] | Automatically at the first tick after the payment shows `refunded`, with the note "auto: condition no longer detected" [150:401], [117:143-153], [115:479-498] |
| "Refund failed at Stripe" (`refund_failed`, P1, keyed by `re_…`) | A refund is *failed*/*canceled* at Stripe and succeeded refunds do not cover the payment's total. **Only when `refund_state_detection_enabled` is true; it is seeded false** [150:259-260], [150:274], [150:351-375] | When the condition clears, or by a person, who records what was done [150:366-368]. A case closed by a person is not reopened for the same refund [150:359-361] |
| "Refund still pending at Stripe" (`refund_pending`, P1, keyed by `re_…`) | Still *pending*/*requires_action* after `refund_state_pending_hours` (120). Same switch [150:377-398] | Same as above [150:384-386] |
| "Reconciliation mismatch" (`reconciliation_mismatch`, P1) | A refunded payment whose transfer has a Stripe transfer id and is not reversed [117:706-749] | When the transfer shows *Reversed* (§9) |
| "Stripe webhook not processed" (`webhook_stuck`, P2) | A received event is still unprocessed after 15 minutes, or failed [117:535-574], [115:150] | When the event is processed |
| Refund resolution (`refund_resolution`, P2) | When its detector is on (seeded off [144:155], [144:349]): every **expired + refunded** order [144:44-48] | Only by a person, after classifying it: close is refused without a classification, and while any obligation the classification raised is not recorded settled [MSE:386-408]. It depends on the console build. **If the case page shows a *Classify* control** (console v2 with the #89 port, on an open case [CW2:168], [CW2:241-331], not merged when this was written), classify there. The *Obligation* control is not there on a new case: it appears only once a classification has raised an obligation, so it never appears while none has been raised [CW2:245-246], [CW2:297-328]. For each obligation, pick *State* yourself: *Settled* only once the money has moved. **If there is no *Classify* control,** escalate to the owner. The console @ `07100a35` has no classify control (none in `admin/src`) |

The two cases keyed by `re_…` have no payment id, so they appear in the
**Cases** queue but not under "Cases on this order" [150:346-349],
[116:583-586]. "Refund execution needs attention" (`refund_failed`, keyed by
payment) is about console refund actions only, so it does not apply here
[150:320-344].

### 5.5 What does **not** happen

- The webhook sends the buyer no push or message for a refund. The
  `charge.refunded` branch has no `sendPush` [WH:733-797]. Telling the buyer
  is on you (§7).
- The transfer keeps its status. A buyer win stays *Disputed*
  [065:130-142], and an expired order stays *Expired*. The listing does not
  change, and nothing relists a transacted listing (`OPERATING_GUIDE.md`,
  Relist listing).
- No transfer reversal happens (§9).
- No `ops.action` row is created, because the refund is not a console action.
  **Your case note is the record.**
- The payout stays shut. Once the payment is no longer `succeeded`, the payout
  claim refuses it [148:123]. A buyer-win transfer stays disputed and is
  refused as well [148:97].

## 6. After the money step: record the outcome

1. **Add note** on the case:

   ```
   Refunded in Stripe: re_…  status shown: Pending|Succeeded  at <UTC time>.
   ```

2. **Set status** → *Waiting*, with the reason "Awaiting charge.refunded
   webhook" [CASE:186-199].
3. **Let the detector close a "Refund owed to buyer" case.** Do not resolve
   or dismiss it while the payment still shows *Captured*. If you do, the next
   tick opens a **new** P1 case for the same payment [115:435-474],
   [150:288-299].
4. **Close a manual case yourself** once §7 passes. Manual cases are never
   closed automatically [115:489], [NCF:5-9]. Resolving needs a reason
   [MSE:381-384].
5. **Follow up on a late failure.** A card refund can still fail up to about
   30 days later [150:7-14]. Until `refund_state_detection_enabled` is true,
   nothing in the console reports that failure (§5.4). Open a manual case on
   the order titled "Refund follow-up re_…", priority P3, due 30 days out
   [NCF:10-72]. When it comes due, re-check the refund in Stripe, note the
   result, then resolve it.

## 7. Verify (read-only)

Allow about 15 minutes for webhook delivery plus one 5-minute detector tick
(this is guidance, not a measured figure). Then check the order page:

- The header reads **"payment: Refund recorded (not confirmed settled)"**
  [FMT:70].
- **Refund** panel: `refunded_at` is set and `stripe_refund_id` shows a
  `re_…`. That is the *first* refund ever recorded for the payment [P3:520],
  [ORDER:280-300].
- **Seller funds state** reads "Refunded to buyer" [FMT:88]. If the seller was
  paid, this label hides that fact (§9).
- **Timeline** shows "Payment refunded" [116:630].
- The "Refund owed to buyer" case is *Resolved* with "auto: condition no longer
  detected".

In Stripe, check that the refund's status is **Succeeded**. *Pending* is not
success: re-check later.

If **System → Settings** lists `refund_state_detection_enabled`, migration 150
is applied. That key is created only by 150 [150:259-260]. The console does not
show the per-refund state.

**Telling the buyer.** Say the refund was *issued*. Do not say the money is
back until Stripe shows *Succeeded*, which matches the console's own warning
[ORDER:289-293]. Even then, the time it takes to reach the buyer's statement
is set by Stripe and the bank (not verified here).

**If nothing has changed after 30 minutes,** go to §10. Do not "fix" the
status by hand.

## 8. Partial refunds (owner decision)

The console cannot do a partial refund even when refunds are on. The server
rejects it as `not_supported` [118:267-271], [MSE:682-685]. A partial
refund done in the Stripe Dashboard has these consequences:

- **On an expired order, the expiry job refunds the rest.** For an expired,
  live transfer, the next expiry run finds a `succeeded` payment whose
  refunds cover less than the total. It then refunds the remaining balance
  by itself [ETE:767-801], [ETE:841-866]. The code comment says so
  [ETE:817-819]. The money then moves beyond the owner's decision. No
  console action stops the job: the action set has none (§2, "Row 8: the
  seller payout"), and ETE reads no `ops.setting` key. So a partial refund
  on an expired order is not possible within this SOP. The rest of this
  section applies only to orders that are **not** expired.
- The payment stays *Captured*, because `status` changes only when the
  refunded total reaches the payment's total [P3:521].
- For a buyer-win or partial-refund dispute, the "Refund owed to buyer" case
  **stays open**. If someone closes it, it **comes back** at the next tick
  [150:288-299], [115:435-474].
- The seller payout is blocked (`PAYMENT_PARTIALLY_REFUNDED` [148:138-145]),
  and nothing in the code releases it ("F-PAYOUT-PARTIAL-1" [144:9],
  [144:247-249]).
- If the seller was already paid, the payout is flagged
  `PARTIAL_REFUND_AFTER_PAYOUT` [P3:540].

If the owner decides on a partial refund:

1. If the transfer reads "Expired (seller did not send)", stop. Nothing in
   the console keeps the expiry job from refunding the rest, so before any
   money step the owner decides on the case: the refund becomes a full one,
   or it waits for an owner-approved change that keeps the job from
   refunding the rest. Never a hand-written production write (rule 2).
2. Before any money step, the owner writes the decision on the case: the
   amount, who bears it, and what happens to the seller's payout.
3. Run §2 (except row 9), refund **that amount** in Stripe, then record it
   (§6, steps 1–2).
4. Leave the case *Waiting* with the note "partial refund per owner
   decision". Do not close it, and tell the owner: the case will not clear
   by itself.

## 9. Refund after the seller was paid (owner decision)

**How to recognise it:** §2 row 8. "Release recorded at" is set, or "Stripe
Transfer (connected account)" shows a `tr_…`.

**If the buyer is refunded anyway, the system:**

- flags the payout. The payout attempt moves to `reversal_required`, and a
  `manual_review` payout decision with `REFUNDED_AFTER_PAYOUT` (or
  `PARTIAL_REFUND_AFTER_PAYOUT`) appears under **Payout decisions**
  [P3:526-546], [149:159-204];
- opens a P1 "Reconciliation mismatch" that stays open until the transfer
  shows *Reversed* [117:706-749];
- shows "Refunded to buyer" as the funds state, which **hides** that the
  seller still holds the transfer. Read the Stripe Transfer field instead
  [116:218-224].

**Transfer reversal is not automated.** No console action creates a reversal,
and no edge function at the gate sends a `POST …/reversals`; the payout
executor only reads reversals. The only thing that marks a transfer *Reversed* is
the `transfer.reversed` webhook through `mark_transfer_reversed` [WH:850-872],
[0561:114-133]. It marks the transfer *Reversed* on **any** reversal, partial
or full, because it does not check the amount [0561:123-127].

**The owner decides:** whether the buyer is refunded at all, how much, whether
to reverse the whole transfer or part of it, in what order, and when the buyer
is told. Founders write that decision on the case **before** any money step,
then note each Stripe id (`re_…`, `trr_…`) afterwards. Do **not** use the April
playbook's "if webhooks are down" SQL calls [DAY5:264-283].

## 10. Escalation

Every escalation goes to the owner. Send ids only: payment id, `pi_…`,
`re_…`, case id and action id. Never send personal data.

A (payments) can help analyse a case when the owner asks. No step in this
SOP waits on A: A has no production write access and is not on call.

| Situation | To | Do meanwhile |
|---|---|---|
| A refund-after-payout, a partial refund, a reversal, a goodwill refund, or any refund not covered by §1 | Owner | Nothing in Stripe until the decision is on the case |
| A partial refund on an **expired** order (§8) | Owner | Nothing in Stripe: the expiry job would refund the rest |
| A transfer that was ever confirmed or released, or an owner-decided refund on a transfer that can still be paid (§2, "Row 8: the seller payout") | Owner | Nothing in Stripe until the payout is settled or held by an owner-approved action, and the owner's decision is on the case. No hand-written database write |
| Stripe shows the refund *Succeeded*, but after 30 minutes the console still shows *Captured* | Owner | Check **System → Webhook backlog** and any "Stripe webhook not processed" case. Do not refund again, and do not edit the database. Webhooks are re-sent from the Stripe Dashboard, never replayed from the console (`OPERATING_GUIDE.md`) |
| Stripe shows the refund *Failed* or *Canceled* | Owner | Stripe asks the platform to arrange another way to refund [150:366-367]. Record it on the case |
| *Pending* for more than 5 days (120 h, the detector's threshold [150:260]) | Owner | Note it on the case |
| A refund already listed in Stripe before you acted (§2 row 10), or the expiry job missed an expired order | Owner | Do not refund |
| A refund-resolution case whose page has no *Classify* control, or one you cannot classify, or cannot close after classifying (§5.4) | Owner | Leave it open |
| `native_primary` order, a "stripe test mode" badge, a Stripe mode field reading "unclassified" (§2 row 3), or a PaymentIntent the live-mode Dashboard cannot find (§2 row 10) | Owner | Nothing in Stripe |
| Any check in §2 is unclear | Owner | Do not refund |

## 11. Why this SOP contains no SQL

The April playbook told operators to run three direct updates after the Stripe
refund [DAY5:46-74]. Each one is wrong today:

- **`UPDATE payments SET status = 'refunded', refunded_at = now()`.** The
  payment guard allows `succeeded → refunded` [P3:393-400], so this
  *succeeds*, and that is the danger. It skips the refund ledger, the
  refunded amount, the 150 per-refund state, the after-payout flag and
  `ops.audit`. Because `refunded` is terminal, a premature or mistaken update
  can never be undone, even if the Stripe refund then fails [P3:390-392]. The
  150 sum columns refuse direct writes outright [150:103-122].
- **`UPDATE transfers SET status = 'expired'`.** `guard_transfer_state_columns`
  refuses it: "Cannot directly modify transfer state columns. Use the
  appropriate RPC." [065:225-266]. When the statements run one at a time, the
  payment update has already gone through by the time this one fails.
- **`UPDATE listings SET status = 'active' …`** puts a sold ticket back on
  sale, which could sell it twice. A refund never relists.
- The Emergency section's "if webhooks are down" calls to
  `mark_transfer_reversed` / `record_payment_refund` [DAY5:264-283] bypass the
  webhook's per-refund state [WH:7-14] and leave no console record.

The console records every operator action with an identity and a reason
[144:527-537]. A hand-written database change records nothing and fights the
guards that keep the money records consistent.

## 12. Not verified

- Which migrations are applied in production (20260906120000, 142, 144, 150).
  The console's own copy still says "Until migration 150 is live"
  [ORDER:292]. The read-only tell for 150 is in §7.
- Which `stripe-webhook` version is deployed, and which events the production
  Stripe endpoint subscribes to (`charge.refunded`, `refund.*`,
  `transfer.reversed`).
- The current Stripe Dashboard labels (§4.1), whether its refund dialog
  exposes an idempotency key or metadata, and Stripe's own behaviour:
  over-refund refusal, refunds on disputed charges, effects of the refund
  reason, refund timing and late failure.
- That the Dashboard refund of a PaymentIntent leaves the seller's
  connected-account transfer untouched. This SOP assumes it does, because
  payouts are separate Stripe Transfers (`DAY5_MANUAL_REFUND_PLAYBOOK.md` Part
  2 at `6f982f36`).
- Each payment's `stripe_livemode`. The console @ `07100a35` shows only
  `false`, so it cannot tell `true` from unclassified (`NULL`). Until console
  v2 (PR #121) shows the Stripe mode field, row 10's live-mode Dashboard
  lookup is the per-order proof (§2 row 3).
- Which console build is deployed: `07100a35`, or console v2 with the #89
  port, whose open refund-resolution cases show a *Classify* control (§5.4),
  and whether it has the Stripe mode field from PR #121 (§2 row 3).
- The current values of `refund_execute_enabled`,
  `refund_state_detection_enabled`, `refund_resolution_detector_enabled` and
  `detectors_enabled` in production. Founders can read them under System →
  Settings.

## 13. Sources

Gate = `origin/release/production-gate-20260918` @ `6f982f36`. Console =
`origin/admin/operating-console` @ `07100a35`.

| Alias | File | At |
|---|---|---|
| 065 | `supabase/migrations/065_dispute_resolution.sql` | gate |
| 0561 | `supabase/migrations/0561_transfer_writer_rpcs.sql` | gate |
| 045 | `supabase/migrations/045_payments_stripe_livemode.sql` | gate |
| 093 | `supabase/migrations/093_primary_ticketing.sql` | gate |
| 115 | `supabase/migrations/115_ops_console_foundation.sql` | gate |
| 116 | `supabase/migrations/116_ops_console_read_api.sql` | gate |
| 117 | `supabase/migrations/117_ops_console_automation.sql` | gate |
| 118 | `supabase/migrations/118_ops_console_corrections.sql` | gate |
| 144 | `supabase/migrations/144_ops_refund_resolution_detector.sql` | gate |
| 145 | `supabase/migrations/145_ops_job_not_running_detection.sql` | gate |
| 146 | `supabase/migrations/146_ops_alert_delivery_and_ack.sql` | gate |
| P3 | `supabase/migrations/20260906120000_payout_attempts_and_refund_monotonic.sql` | gate |
| 148 | `supabase/migrations/20260924000000_seller_win_dispute_payout_and_notice.sql` (latest `claim_payout_attempt`) | gate |
| 149 | `supabase/migrations/20260924120000_payout_decisions_buyer_confirmed_truth.sql` (latest `flag_payout_reversal_required`) | gate |
| 150 | `supabase/migrations/20260925000000_refund_lifecycle_state.sql` (latest `ops.detect_refunds`) | gate |
| MSE | `supabase/migrations/20261013000000_marketplace_safety_enforcement.sql` (latest `ops.action_dispatch`) | gate |
| WH | `supabase/functions/stripe-webhook/index.ts` | gate; `WH@037092f0` = the same file before 150 (parent of `98ccf6da`) |
| ETE | `supabase/functions/enforce-transfer-expiry/index.ts` | gate |
| PL | `supabase/functions/_shared/payout-logic.ts` | gate |
| CAR | `supabase/functions/confirm-and-release/index.ts` | gate |
| ORE | `supabase/functions/ops-refund-execute/README.md` | gate |
| RUNBOOK | `docs/admin-console/RUNBOOK.md` | console |
| DAY5 | `docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md` | gate |
| ORDER | `admin/src/app/(console)/orders/[paymentId]/page.tsx` | console |
| CASE | `admin/src/app/(console)/cases/[id]/page.tsx` | console |
| SYS | `admin/src/app/(console)/system/page.tsx` | console |
| NCF | `admin/src/components/cases/NewCaseForm.tsx` | console |
| FMT | `admin/src/lib/format.ts` | console |
| TYP | `admin/src/lib/types.ts` (`ActionType`) | console |
| CW2 | `admin/src/components/cases/CaseWork.tsx` | `admin/console-v2-integration` @ `d614b0d0` (the #89 port; local, not merged) |
| TYP2 | `admin/src/lib/types.ts` (`ActionType`) | `admin/console-v2-integration` @ `984146c0` (console v2; not merged) |

Latest definitions were checked by `git grep` over the gate's migrations:
`ops.execute_action` = 144:455, `ops.action_precheck` = 118:229,
`ops.action_dispatch` = MSE:315, `ops.detect_refunds` = 150:262,
`guard_transfer_state_columns` = 065:225, `guard_payment_transitions` = P3:350,
`record_payment_refund` = P3:457, `claim_payout_attempt` = 148:35,
`flag_payout_reversal_required` = 149:159, `mark_transfer_reversed` = 0561:114,
`ops.action_allowed_roles` = 115:515.
This document edits none of them.
