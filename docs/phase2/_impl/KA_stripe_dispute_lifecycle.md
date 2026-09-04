# KA — Stripe dispute / reversal lifecycle: external facts the webhook wiring must honour

Investigator A · 2026-09-03 · repo `/Users/josetascon/snatchit-consol` @ `609e0f4` (`feature/venue-native-and-product-v2`) · read-only; no Stripe API calls; one local rehearsal DB (`snatchit_rehears_a`, 110/110 migrations, GATE-2 27/70/37/26).

Scope discipline: this is a FACT report. It does not design the DB model. Where a Stripe behaviour could not be pinned from an official page it is marked **unverified**.

---

## 1. What I inspected

| Source | Lines / anchor | Why |
|---|---|---|
| `supabase/functions/stripe-webhook/index.ts` | 240-300 (claim/lease helpers) · 307-366 (`markProcessed`, `finish`, `finishDecision`) · 951-1046 (`charge.dispute.created`) · 1048-1088 (`charge.dispute.closed`) · 1090-1120 (`charge.refunded`) · 1122-1131 (`transfer.created`) · 1133-1155 (`transfer.reversed`) · 1157-1178 (`payout.paid` / `payout.failed`) · 1347-1350 (default ACK) | current event routing |
| `supabase/functions/stripe-webhook/native.ts` | 35-36, 84-152 (`resolveRail`, `dispositionForRoute`) | rail dispatch is metadata-driven; a Dispute carries no metadata |
| `supabase/functions/_shared/stripe.ts` | 34 (`STRIPE_API_VERSION = '2024-09-30.acacia'`) | outbound pin; NOT the webhook endpoint version |
| `supabase/functions/_shared/payouts.ts` | 224-314 (`TransferReversal`, `detectTransferReversal`) | current partial-reversal detection (reads `amount_reversed`) |
| `supabase/functions/payout-execute/index.ts` | 79, 153-210, 394-405, 423 | reversal → `kernel.hold_payout_transfer_reversed` |
| `supabase/functions/refund-execute/executor.ts` | 55-90 (`disputed_minor` = Σ lost/charge_refunded `dispute_native`) | dispute rows feed refund headroom |
| `supabase/migrations/024_disputes.sql` | 12-35 (`public.disputes`, no status CHECK; partial index excludes won/lost/warning_closed/charge_refunded) · 57-69 (`transfers_status_check` + `'reversed'`) | legacy dispute store |
| `supabase/migrations/009_dispute.sql` | 1-50 (`buyer_dispute_transfer`: app-level "dispute", not Stripe) | name collision only |
| `supabase/migrations/065_dispute_resolution.sql` | 1-35, 78-160 (`resolve_transfer_dispute`) | resale-rail resolution; not Stripe-driven |
| `supabase/migrations/0561_transfer_writer_rpcs.sql` | 105-137 (`freeze_transfer_for_dispute`, `mark_transfer_reversed`) | all-or-nothing, no amount |
| `supabase/migrations/064_webhook_event_claim_lease.sql` | 80-118 (`claim_stripe_webhook_event` keyed on `event_id` only) | dedup scope |
| `supabase/migrations/088_market_native_rail.sql` | 185-215 (`kernel.dispute_native` + CHECK set) · 305-318 (chargeback-arm comment) · 758-873 (`record_dispute_native`) · 875-911 (`mark_dispute_state`) · 913-935 (`resolve_dispute_native`, PARKED) | native dispute surface |
| `supabase/migrations/093_primary_ticketing.sql` | 1136-1215 (`settlement_royalty_lines` chargeback arm: `d.status in ('lost','charge_refunded')`, cap at face − refunds − prior_cb) | where a lost dispute becomes a venue debit |
| `supabase/migrations/085_kernel_money_native.sql` | 133 (`stripe_transfer_ref` write-once) · 1668-1720 (`mark_payout_transfer_state`: submitted→paid\|failed; paid→reversed) | payout terminal edges |
| `supabase/migrations/095_payout_state_machine_recovery.sql` | 676-760 (`hold_payout_transfer_reversed(uuid,text,int,int,jsonb,text)`; requires `^tr_`; full vs partial decided against `payout.amount_minor`) | reversal hold verb |
| `docs/phase2/_impl/J2_stripe_reversal_mechanics.md` | §4.1-4.4, §7.3-7.4 | prior evidence; §7.4(a) is now FIXED (payouts.ts:287-314 reads `amount_reversed`) |
| `supabase/tests/160_organization_obligation.sql` | 43-68, 150-190 | fixture pattern reused |

Stripe pages read (all `docs.stripe.com` unless noted), each cited inline below:
Dispute object · How disputes work · Types of events · Webhooks (Event delivery behaviors / Best practices) · Event object · Transfer object · Transfer Reversal object · Create a transfer reversal · Separate charges and transfers (PaymentIntents variant) · Connect charges · Connect webhooks · Connect account balances · Handle refunds and disputes (Connect marketplace) · Refunds · Respond to disputes · Dispute evidence best practices · Dispute withdrawals · Dispute prevention · Webhook versioning · Changelog 2014-08-20 · Changelog 2025-08-27 (basil) · support.stripe.com June-2025 dispute pricing · support.stripe.com "disputes on a refunded transaction FAQ" · support.stripe.com "dispute for full charge amount after a partial refund" · support.stripe.com "transfer is already fully reversed".

## 2. What I executed and results

`scripts/rehearsal_reset.sh snatchit_rehears_a` → `REPLAY OK: 110/110`. Then `supabase/tests/000_helpers.sql` + a BEGIN…ROLLBACK probe (scratchpad `probe_KA2.sql`; fixture = 160's pattern: org → approved venue → past event/session → `public.payments` 19,000 face + 4,000 buyer fee = 23,000 total, `mode='native_primary'`, `kernel.payment_native` link).

| # | Probe | Result (verbatim) |
|---|---|---|
| A | `record_dispute_native('du_A',…,status='lost')` — closed-before-created / unchallengeable-at-open | `{"status":"ok","atoms_held":0,"payouts_held":0,"linked":true}` — recorded at terminal, **zero freeze legs** (088:820 `v_open=false`) |
| A2 | then `mark_dispute_state('du_A','needs_response')` — the late `created` | `RAISE [P0001] state_conflict: … is terminal (lost) — needs_response refused` |
| A3 | then `record_dispute_native('du_A',…,'needs_response')` (a `created` replayed through record) | `{"status":"noop_replay"}` — status stays `lost` (correct: record never overwrites) |
| B | needs_response → under_review → won | all `ok`; then `won → lost` = `state_conflict` |
| B5 | `lost` then `won` (Stripe **late win**) | `RAISE state_conflict: … terminal (lost) — won refused` — **the documented lost→won transition is unrepresentable in kernel** |
| C | status `prevented` via record and via mark | `RAISE invalid_input: prevented is not a dispute status` (both) |
| D | dispute with `payment_intent = NULL` | `RAISE [P0002] not_found: no payment for payment intent <null>` |
| E | amount 30,000 on a 23,000 payment | accepted (`ok`) — no cap at record time |
| E2 | second dispute `du_E2` on the same `ch_E` | accepted; two rows `du_E 30000 / du_E2 5000` coexist |
| F | legacy: `UPDATE public.disputes … WHERE stripe_dispute_id='du_F'` (index.ts:1058 shape) with no row, then the :1017 upsert with `needs_response` | UPDATE hit 0 rows; final row `du_F \| needs_response` — **terminal fact lost, row open forever** |
| F2 | legacy insert with `status='prevented'` | accepted (`public.disputes` has no CHECK) |
| F3 | legacy row at `lost`, then the :1017 upsert with `needs_response` | final `du_F3 \| needs_response` — **upsert regresses terminal→open** |
| G | `mark_dispute_state('du_E','charge_refunded')` then `'won'` | ok, then `state_conflict` — kernel treats `charge_refunded` as absorbing |
| H | `hold_payout_transfer_reversed(…,'trr_x',…)` | `RAISE invalid_input: a Stripe transfer ref (tr_…) is mandatory` — verb wants the transfer id, not the reversal id |

Audit trail written by the probes: `dispute.record` ×5, `dispute.state_sync` ×3 (kernel.admin_audit), all rolled back.

## 3. Stripe facts (external) — with citations

### 3.1 Status set and terminality

Current Dispute object enum (`https://docs.stripe.com/api/disputes/object`): `warning_needs_response, warning_under_review, warning_closed, needs_response, under_review, won, lost, prevented`.
Historic/still-emittable: `charge_refunded` (added 2014-08-20, `https://docs.stripe.com/changelog/2014-08-20/disputes-provide-several-new-statuses`; not listed on the current object page, never announced as removed). `prevented` added in `2025-08-27.basil` with `payment_method_details.card.case_type ∈ {block, resolution}` (`https://docs.stripe.com/changelog/basil/2025-08-27/add-preventions-to-dispute`) and only arises when enrolled in Dispute prevention (`https://docs.stripe.com/disputes/prevention-preview`).

| status | class | terminal | funds | notes |
|---|---|---|---|---|
| `warning_needs_response` | inquiry | no | **none withdrawn** | "inquiries … don't have any financial impact" (withdrawing) |
| `warning_under_review` | inquiry | no | none | evidence submitted |
| `warning_closed` | inquiry | yes | none | "open for 120 days without escalation … the card network won't escalate it" (how-disputes-work §Inquiries) |
| `needs_response` | chargeback | no | **withdrawn + fee** | "You can't issue a refund outside the dispute process while the dispute is open" |
| `under_review` | chargeback | no | withdrawn | after evidence |
| `won` | chargeback | yes (see late-win) | reinstated | countered fee returned |
| `lost` | chargeback | yes (see late-win) | stays withdrawn | includes "partially won" after partial refund (best-practices §partial refund: status is `lost`) |
| `charge_refunded` | either | yes | n/a | not on current enum page; kernel/024 treat it terminal |
| `prevented` | pre-chargeback | yes (**unverified**) | resolution = auto-refund; block = nothing | basil-only; "Resolved disputes don't count towards your dispute rate and don't incur a dispute received fee" |

Terminal→non-terminal: **yes, documented**: "in rare cases the status can change from `lost` to `won`. When this occurs, Stripe labels the dispute as a `late win` and returns the funds" (`https://docs.stripe.com/disputes/how-disputes-work#after-the-decision`). Late withdrawal after loss can take "weeks or months" (`https://docs.stripe.com/disputes/withdrawing`). `won → lost` is not documented. Which event carries a late win is **unverified** (a second `charge.dispute.closed`, and/or `charge.dispute.funds_reinstated`, is the only plausible carrier given the event descriptions).

Inquiry → chargeback escalation: "If an inquiry escalates to a chargeback, you must submit another response for the dispute" (responding) — the docs speak of the same dispute; whether it is the same `du_` id or a new object is **unverified**.

First-terminal on create: "Unchallengeable disputes … Stripe immediately closes them as lost as soon as we notify you about them" (how-disputes-work). So a `charge.dispute.created` can carry `status=lost`, and its `closed` twin can land first.

### 3.2 Event catalogue (`https://docs.stripe.com/api/events/types`, `https://docs.stripe.com/webhooks#event-delivery-behaviors`, `https://docs.stripe.com/connect/webhooks`)

Global delivery facts (apply to every row): "Stripe doesn't guarantee the delivery of events in the order that they're generated"; "Don't use `created` to determine event order"; "Webhook endpoints might occasionally receive the same event more than once … In some cases, two separate Event objects are generated and sent. To identify these duplicates, use the ID of the object in `data.object` along with the `event.type`"; retries "for up to three days with an exponential back off in live mode"; manual resend up to 15 days (Dashboard) / 30 days (CLI) and "doesn't dismiss Stripe's automatic retry behavior"; `data.previous_attributes` is "only included in events of type `*.updated`" (Event object). Scope: for separate charges and transfers the charge, dispute and transfer are **platform** resources → "Your account" endpoint (`events_from=["@self"]`); connected-account payouts arrive on the "Connected accounts" endpoint with top-level `event.account`.

| event | `data.object` | status values seen | terminal? | can duplicate | can arrive out of order | can arrive first-terminal | endpoint |
|---|---|---|---|---|---|---|---|
| `charge.dispute.created` | dispute | any of the set incl. `warning_*`, and `lost` (unchallengeable) | per status | yes (redelivery; also 2nd Event object) | yes — may follow `closed`/`updated`/`funds_withdrawn` | **yes** (`lost` at open) | platform |
| `charge.dispute.updated` | dispute (+`previous_attributes`) | any transition: `warning_*→needs_response` (escalation), `needs_response→under_review`, evidence edits, amount corrections | no (usually) | yes | yes | n/a | platform |
| `charge.dispute.closed` | dispute | doc: "changes to `lost`, `warning_closed`, or `won`" — `charge_refunded`/`prevented` **not listed** (carrier **unverified**) | yes | yes; a late win may produce a second `closed` (**unverified**) | **yes, before `created`** | n/a | platform |
| `charge.dispute.funds_withdrawn` | dispute | non-terminal chargeback statuses; never for `warning_*` | no | yes | yes (before `created`) | n/a | platform |
| `charge.dispute.funds_reinstated` | dispute | `won`, and `lost`-after-partial-refund ("includes partially refunded payments") | yes | yes | yes | n/a | platform |
| `charge.refunded` | **charge** | `charge.refunded=true` only when fully refunded; fires for partial too | n/a | yes | yes | n/a | platform |
| `refund.created/updated/failed` | refund | `failed.failure_reason='charge_for_pending_refund_disputed'` when a dispute lands on a pending refund | — | yes | yes | — | platform |
| `transfer.created` | transfer | — | — | yes | yes | — | platform |
| `transfer.reversed` | **transfer** (not the `trr_`) | "including partial reversals" → **one event per reversal**; `reversed=true` only when fully reversed; `amount_reversed` cumulative; `amount` unchanged | full when `amount_reversed == amount` | yes | yes (two partials may swap) | n/a | platform |
| `transfer.updated` | transfer | "description or metadata is updated" — **does NOT signal a reversal** | — | yes | yes | — | platform |
| `payout.paid` / `payout.failed` | payout | `paid` then possibly `failed` "at a later time" | no (paid can be followed by failed) | yes | yes | — | connected (`event.account`) |

### 3.3 Amounts

- "Disputed amount. Usually the amount of the charge, but it can differ (usually because of currency fluctuation or because only part of the order is disputed)" (Dispute object). "A disputed amount might be lower **or higher** than the amount of the original charge" — currency conversion, recurring aggregation onto one charge, partial disputes, and full dispute after partial refund (how-disputes-work §Disputed amount).
- Multiple disputes per charge: "In extremely rare cases, you might receive more than one dispute per payment" — new reason code, new line item, issuer re-files; "Handle each dispute the same way" (how-disputes-work §Receive multiple disputes). They are separate `du_` objects.
- The dispute is against the **charge**; Stripe knows nothing of face vs fee. A full dispute of the brief's 23,000 charge is `amount = 23000`, i.e. face 19,000 + buyer fee 4,000. The 093 chargeback arm caps the org-side debit at face minus refunds minus prior chargebacks (093:1176-1200), so the 4,000 fee leg and the $15 fee are platform-borne and, per J1:224, **unrepresented** in any ledger object (no `dispute_fee` cause anywhere: grep of migrations/functions returned only prose).

### 3.4 Fees, balance, refund/dispute overlap

- US fees since 2025-06-17: dispute **received** $15 (non-refundable outside Mexico), dispute **countered** $15 (returned on win) (`https://support.stripe.com/questions/june-2025-pricing-updates-for-disputes`). Visa/Mastercard compliance disputes add $500 refundable on win (responding).
- Separate charges and transfers: "Your account balance is debited for the cost of the Stripe fees, refunds, and chargebacks" (SCT); "your platform balance is automatically debited for the disputed amount and fee. When this happens, your platform can attempt to recover funds from the connected account by reversing the transfer" (`https://docs.stripe.com/connect/charges#disputes-and-chargebacks`).
- Refund while disputed: "You can't issue a refund outside the dispute process while the dispute is open"; "can't issue a refund on a disputed charge until your customer's card issuer decides in your favor" (withdrawing). `is_charge_refundable`: "If true, it's still possible to refund the disputed payment. After the payment has been fully refunded, no further funds are withdrawn from your Stripe account as a result of this dispute" (object). A pending refund overtaken by a dispute fails with `charge_for_pending_refund_disputed` (refunds §failed refunds).
- Dispute after full refund: "Cardholders can still initiate a dispute … even if a refund has been processed" (support FAQ). Inquiries "on partially refunded charges can still escalate"; a full refund resolves an inquiry without a fee (how-disputes-work §Inquiries). Partial refund then full-amount dispute: issuer "cancels the original dispute and then creates a separate one for the corrected amount. On Stripe, we use the existing dispute … If it's not [won], you only receive the partially refunded amount. In this case, the dispute's `status` is set to `lost`" (best-practices §partial refund) → `funds_reinstated` on a `lost` dispute is real.
- `charge_refunded` semantics: the 2014 changelog adds it without definition; the only current prose is `is_charge_refundable` above. Treat as "dispute closed because the charge was refunded (typically an inquiry)". Carrier event **unverified** (`closed` doc lists only won/lost/warning_closed).

### 3.5 Transfer reversal

- Create: "you can optionally reverse part of the transfer … as many times as you wish until the entire transfer has been reversed. Once entirely reversed, a transfer can't be reversed again. This method will return an error when called on an already-reversed transfer, or when trying to reverse more money than is left" (`https://docs.stripe.com/api/transfer_reversals/create`). `amount` "Can only reverse up to the unreversed amount remaining"; `refund_application_fee` proportional (N/A: SCT here carries no application fee). Object `trr_…` with `balance_transaction`, `destination_payment_refund` (`pyr_`), `source_refund` (set when a refund with `reverse_transfer` caused it).
- Transfer object: `amount_reversed` "can be less than the amount attribute … if a partial reversal was issued"; `reversed` "Whether the transfer has been fully reversed. If the transfer is only partially reversed, this attribute will still be false" (`https://docs.stripe.com/api/transfers/object`).
- Balance precondition: "It's only possible to reverse a transfer if the connected account's available balance is greater than the reversal amount or has connected reserves enabled" (SCT §Reverse transfers) — vs J2 §4.1's contradicting risk-management page; still contradictory today. Negative connected balance → Stripe reserves platform funds (`reserve_transaction`), debits the external account only if `debit_negative_balances=true`, and after **180 days** sweeps the platform reserve as a `connect_collection_transfer` (`https://docs.stripe.com/connect/account-balances`).
- Automatic reversals: SCT guide says "Unlike destination charges, Stripe doesn't automatically reverse a transfer if the associated async payment fails … You must then manually reverse"; support page says accounts "created on or after January 1, 2025" get automatic reversal when "asynchronous payment methods fail" and it "no longer requires custom handling" (`https://support.stripe.com/questions/getting-the-transfer-is-already-fully-reversed-errors-after-handling-charge-failed-webhook`). Whether Snatch It's platform account predates 2025-01-01 is **unverified** (J2 §4.3 open). Not applicable to card disputes; Stripe never auto-reverses on a chargeback.
- `transfer.reversed` fires per reversal ("including partial reversals"); `transfer.updated` does not fire for reversals.

## 4. Findings — what the repo currently mishandles (ranked)

**P0-1 `charge.dispute.closed` before `created` silently drops the terminal fact (both rails).** index.ts:1058-1069: UPDATE by `stripe_dispute_id` → `!ourDispute` → `console.warn` + `markProcessed()` = 200/terminal. The later `created` upsert (:1017-1029) writes the payload's open status. Probe F reproduces: final row `needs_response`, open forever; on the resale rail the transfer stays frozen (`freeze_transfer_for_dispute`), on the native rail nothing is even recorded. Stripe explicitly permits this order (§3.2).

**P0-2 `charge.dispute.updated` is not handled (ACK'd at :1347-1350).** Every mid-life transition — inquiry→chargeback escalation (`warning_needs_response→needs_response`, the moment funds are actually withdrawn), `needs_response→under_review`, amount corrections — never reaches `public.disputes` or `kernel.dispute_native`. `kernel.mark_dispute_state` (088:875) has **no caller**; `record_dispute_native` (088:758) has **no caller**. Native-rail disputes today land only in `public.disputes` with `transfer_id=null` (no `public.transfers` row for a native payment), so no `kernel.payout` dispute hold ever fires.

**P0-3 The upsert on `created` regresses a terminal row (probe F3)** — any redelivered/duplicate `created` (Stripe: possible, incl. a second Event object) after a `closed` rewrites `lost/won → needs_response`. `record_dispute_native` is immune (noop_replay, probe A3); `public.disputes` is not.

**P1-1 `charge.dispute.funds_withdrawn` / `funds_reinstated` ignored.** These are the only events that state a balance movement; `created` with `warning_*` withdraws nothing, yet :987-1007 freezes the resale transfer on every `created` regardless of status (inquiry ≠ chargeback). Conversely `funds_reinstated` on a `lost` dispute after a partial refund is the only signal that the loss was partial.

**P1-2 Late win (`lost→won`) is unrepresentable in kernel** (probe B5 `state_conflict`) and in 024's index semantics; 093's chargeback arm has already lined the loss (`d.status in ('lost','charge_refunded')`), and `settlement_line` is append-only — a late win needs a new positive fact, which nothing emits. Stripe documents the transition (§3.1).

**P1-3 `prevented` (basil enum) is rejected by kernel (probe C) and accepted blindly by `public.disputes` (probe F2).** Exposure depends on the **webhook endpoint's** API version (not `STRIPE_API_VERSION` at stripe.ts:34, which governs outbound calls only — webhooks/versioning) and on Dispute-prevention enrolment; both **unverified** (no Stripe read allowed). `charge_refunded` is the mirror risk: kernel/024 hard-code it, current enum omits it.

**P1-4 Dispute with `payment_intent=null`**: legacy stores it unlinked (:974 guard); kernel raises `not_found` (probe D) → a native handler that maps that to retry would spin for 3 days then drop. Also **every** dispute rides `payment_intent` lookup; `charge` is never used as a fallback key.

**P1-5 `closed`+`lost` marks the whole payment `refunded` (:1075-1080)** regardless of `dispute.amount` (partial dispute, over-dispute, second dispute on the same charge — all documented). `public.disputes` never stores whether the loss was partial. Kernel records amount uncapped (probe E: 30,000 on a 23,000 payment) and multiple rows per charge (probe E2); refund-execute's `disputed_minor` sums them (executor.ts:69), so an over-dispute can push refund headroom negative silently.

**P1-6 `transfer.reversed` on the resale rail treats any reversal as full** (`mark_transfer_reversed`, 0561:114-131, no amount) — J2 §4.2 still open there. On the native rail the webhook does nothing with `transfer.reversed`; the only reversal observer is payout-execute's reconcile read (payouts.ts:287-314, now amount-aware — J2 §7.4(a) is fixed), so a reversal is noticed only when the executor next touches that payout. Per-reversal events (two partials) are idempotent by `status<>'reversed'` only.

**P2-1 Dedup is `event_id`-only (064:80-118).** Stripe's "two separate Event objects" duplicate needs `(data.object.id, type)`; the dispute handlers happen to be idempotent except P0-3.

**P2-2 No ledger object for the dispute fee ($15/$15) or the 4,000 buyer-fee leg of a 23,000 dispute** (J1:224 confirmed; grep finds prose only). Platform loss is invisible.

**P2-3 Endpoint scope**: `payout.paid/failed` handlers read `event.account` (:1164, :1176), implying a Connected-accounts endpoint exists alongside the platform one; the enabled-events list of either is **unverified** (cannot read Stripe). If `charge.dispute.updated/funds_*` are not subscribed, P0-2/P1-1 need a Stripe-side change too.

## 5. Options (enumerated, not decided)

Fact-constraints any option must satisfy: events arrive in any order, at least once, sometimes as distinct Event ids; `created` may already be terminal; `closed` may precede `created`; `lost` may later become `won`; amount may exceed the charge and there may be several disputes per charge; `warning_*` moves no money; `transfer.reversed` is per-reversal with `amount_reversed` as the only truth.

| Option | Shape | Honest? | Cost / trade-off |
|---|---|---|---|
| O1 — status-monotone upsert on `public.disputes` | route `created/updated/closed/funds_*` through one writer that never lowers rank (open < terminal), records at terminal on first sight, stores `amount` per event | fixes P0-1/P0-3 on legacy rail only | leaves native rail unrecorded; late-win still unrepresentable unless rank allows `lost→won` |
| O2 — call the existing kernel pair from the webhook | `created/updated/closed/funds_*` → `record_dispute_native` (unknown ref) else `mark_dispute_state`; ACK `state_conflict` as noop, retry only on infra errors; gate on `payments.mode='native_primary'` (PI lookup, since Dispute has no metadata) | fixes P0-1/P0-2/P0-3 for native; zero schema change | needs a NEW migration if `prevented` must be accepted or `lost→won` allowed (088 is immutable); P1-4 mapping policy required |
| O3 — O2 + event-fact table | append-only `kernel.dispute_event(stripe_event_id, dispute_ref, type, status, amount, previous_attributes, received_at)` written first, state derived | the only shape that survives late win, partial loss, over-dispute and duplicate Event objects with no data loss | new migration + new table; more surface |
| O4 — do nothing until activation | keep ACK-ing | dishonest: production is already on 092 and P0-1/P0-3 hit the live resale rail today | — |

**Smallest honest design** (for the orchestrator to weigh): O2 with (a) `closed`/`funds_*`/`updated` on an unknown ref → `record_dispute_native` at the event's status (zero freeze legs by construction — probe A), (b) `state_conflict` → ACK+alert (a redelivery can never fix it), (c) `not_found` payment → ACK+alert (P1-4), (d) `prevented`/unknown status → ACK+alert, never retry, and (e) leave P1-2 (late win) as an explicit owner item because it needs a new positive settlement fact. **What would be dishonest:** treating `created` as "funds withdrawn"; treating `closed:lost` as "full amount lost"; treating `transfer.reversed` as full; assuming `charge_refunded`/`prevented` cannot arrive; or claiming the endpoint subscribes to `updated`/`funds_*` without reading it.

## 6. Open questions for the orchestrator / owner

1. Which API version is pinned on the **live webhook endpoint(s)**, and which events are enabled? (Decides whether `prevented` can appear and whether P0-2/P1-1 need a Stripe-side change.) Read-only Stripe check required; out of this investigator's remit.
2. Is Snatch It enrolled in Dispute prevention (Verifi/Ethoca)? If yes, `prevented`+`resolution` = an automatic refund Stripe issued with no `kernel.refund` row.
3. Platform account creation date vs 2025-01-01 (J2 §4.3): only matters for async payment methods; irrelevant to card chargebacks.
4. Policy for a late win after 093 has lined the chargeback: new positive `settlement_line` cause, or org-obligation credit (094)? Append-only rules out mutation.
5. Policy for `dispute.amount > payment.total` and for a second dispute on the same charge: cap at record time (kernel) or at settlement (093 already caps at face)? refund-execute's headroom sums raw rows.
6. Should `warning_*` (inquiry, no funds moved) hold payouts at all, or only `funds_withdrawn`/`needs_response`?
