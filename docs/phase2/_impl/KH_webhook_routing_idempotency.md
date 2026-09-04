# KH — stripe-webhook: idempotency, ordering and LEGACY/NATIVE routing for the dispute / reversal train

Investigator H. Repo `snatchit-consol` @ `609e0f4`. Read-only; executed only against a private local
rehearsal DB (`snatchit_rehears_h`, full 110-migration replay, GATE-2 27/70/37/26 matched CI baseline).
No remote, no Stripe, no edits outside this file.

---

## 1. What I inspected (file:line)

**Webhook shell** — `supabase/functions/stripe-webhook/index.ts`
- :237-241 top-level `paymentIntent = event.data.object; piId = paymentIntent.id; metadata = paymentIntent.metadata ?? {}` — evaluated for EVERY event type before dispatch.
- :260-302 lease (`claim_stripe_webhook_event` → `claimed | already_processed→200 | in_flight→409`; claim error → 500).
- :307-319 `markProcessed({error?})` — `error` ⇒ `fail_stripe_webhook_event` (lease released) and **returns void; it does not set the HTTP status**.
- :326-339 `finish(ok, …)` — the only helper that maps `ok:false → 500`. :353-366 `finishDecision(Decision)` — `ack:false → 500`, `alert → captureException`.
- :383-537 `payment_intent.succeeded` native arm; :547-780 legacy arm (byte-for-byte).
- :781-937 `payment_intent.payment_failed | canceled` (native :801-872; legacy canceled :874-882; legacy failed :893-937 — DB error at :902-908 **returns 200**).
- :951-1046 `charge.dispute.created` (legacy only): :969-975 `payments` by `dispute.payment_intent`; :977-982 `transfers` by `payment_id`; :988-1008 `freeze_transfer_for_dispute`; :1016-1027 `public.disputes` upsert; **:1028-1038 upsert error → `markProcessed({error})` then falls through to :1354 → HTTP 200**.
- :1048-1088 `charge.dispute.closed` (legacy only): :1058-1063 status UPDATE; :1064-1067 error → `markProcessed({error})` → **200**; :1068-1070 unknown dispute → ack; :1075-1082 `lost` → `payments.status='refunded'`.
- :1090-1120 `charge.refunded` (legacy only): :1101-1110 `payments.status='refunded'` + first `refunds.data[0].id`; error → **200** (:1112).
- :1122-1131 `transfer.created` log-only. :1133-1155 `transfer.reversed` → `mark_transfer_reversed(tr.id)`; error → **200** (:1144). :1157-1178 `payout.paid|failed` log-only. :1180-1344 `account.updated`. :1346-1352 **else → ack-only** (this is where `charge.dispute.updated`, `charge.dispute.funds_withdrawn|funds_reinstated`, `refund.*`, `charge.refund.updated`, `transfer.updated` land today).
- :1358-1385 catch → `fail_stripe_webhook_event` + 500.

**Decision logic** — `stripe-webhook/native.ts` :13-28 (the ack/retry rule), :56-63 `Decision`, :115-133 `resolveRail` (metadata-only), :147-156 `dispositionForRoute`, :377-388 transient/privilege classes. `tests/stripe-webhook-native.test.ts` :84-576 — 81 cases, **all on PI / account.updated; zero on dispute, refund or transfer events**.

**Lease + retries** — `025_stripe_webhook_events.sql`; `064_webhook_event_claim_lease.sql` :82-120 claim, :122-139 complete, :141-160 fail (clears `claimed_at`, keeps `processed_at`), :164-193 `get_incomplete_webhook_events`; `069_webhook_retries_table.sql` :12-22 (table only).

**Legacy dispute/transfer substrate** — `024_disputes.sql` :12-35 (`status` free text, open-set partial index), :59-70; `0561_transfer_writer_rpcs.sql` :98-112 `freeze_transfer_for_dispute`, :114-133 `mark_transfer_reversed` (WHERE `stripe_transfer_id = $1`, no unique index — verified `pg_indexes`: none); `0564` :58-66 payout refuses disputed; `065_dispute_resolution.sql` :78-170; `009_dispute.sql`.

**Native dispute substrate** — `088_market_native_rail.sql` :189-213 `kernel.dispute_native` (`dispute_native_stripe_ref_uq`, status CHECK of 8 labels), :758-867 `record_dispute_native` (:784-787 replay-by-ref, :789-792 `not_found` P0002 on PI, :799-803 concurrent-insert → `noop_replay`, :804 open-set predicate, :854-859 no-link arm), :875-902 `mark_dispute_state` (:886 P0002, :887-892 terminal absorbing, :893-895 same-open noop, :896 open↔open free), :913-931 `resolve_dispute_native` PARKED, :319-362 `settlement_royalty_lines` chargeback arm (`status in ('lost','charge_refunded')`, dedupe on `settlement_line(cause='chargeback', cause_ref=dispute_id)`), :540-590 `unlock_ticket` dispute re-arm.

**Money verbs the reversal/loss arms would call** — `085_kernel_money_native.sql` :111-145 `kernel.payout` (`stripe_transfer_ref` write-once, no index), :1668-1735 `mark_payout_transfer_state` (:1682-1684 **raises `payout_held` if `hold_state<>'none'`**; :1691-1699 forward-only `submitted→paid|failed`, `paid→reversed`; :1704 ref mandatory), :1737-1790 `mark_refund_state`, :1793-1834 `record_identity_obligation`, :1936-1938 finalize refund probe (reads `kernel.refund`, not `payments.status`). `094_organization_obligation.sql` :99-128 (chargeback arm over-collects, `unlined_reversal` INERT), :201-206, :240-242 `organization_obligation_dispute_uq`, :320-419 `record_organization_obligation` (:392-401 anti-double-count guard is ONE-directional). `095_payout_state_machine_recovery.sql` :676-757 `hold_payout_transfer_reversed` (submitted-only; `paid` → raises pointing at `mark_payout_transfer_state('reversed')`).

**Discriminators** — `093_primary_ticketing.sql` PART 20 :2780-3281; `payments_mode_check` :2995-3006 = `{buy_now, auction, native_primary}`; `payments_rail_pairing_ck` :3059-3081; :1040-1066 `get_refund_execution_context` (`payment_status`, `stripe_livemode`, `disputed_minor`); :648-662 / :1836-1848 / :1968-1980 / :2032-2044 ("a dispute first observed already lost … freeze is INVERTED relative to risk"). `045_payments_stripe_livemode.sql`. `_shared/payout-logic.ts` :116-118 `rowIsLiveActionable = stripe_livemode === true`. `primary-checkout/index.ts` :204-278 metadata contract, :1208-1210 writes `stripe_livemode` from Stripe. `_shared/payouts.ts` :80-143 legacy `createSellerPayout` — **metadata `{transfer_id, payment_id, seller_id}`, `source_transaction`, NO `transfer_group`**. `payout-execute/executor.ts` :364-366 `buildTransferGroup = payout_<payout_id>`, :772-780 metadata `{payout_id, settlement_id, org_id, source:'payout-execute'}`, :286-318 `classifyTransferReversal`; `payout-execute/index.ts` :153-210 `holdReversedTransfer`. `refund-execute/executor.ts` :250-251 (accepts `payments.status ∈ {succeeded, refunded}`), :262-263 livemode refusal, :299-305 refund metadata `{refund_id, payment_id, reason, source:'refund-execute', order_id|sale_id}`.

**Prose** — `PHASE_2_EDGE_FUNCTION_SPEC.md` §4 :1196-1262 (dispute row :1217; refund rows :1214-1216; transfer rows :1219-1221; `payout.*` = NONE :1222). `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §20.7.13-14 :6359-6420. `PHASE_2_MONEY_AUTHORITY_SPEC.md` :1494-1502. `E3_webhook_native_branch.md`. `E4_refund_executor.md` :207-216, :431-432. `_rulings/E_refunds_disputes.md` :284-300, :396-410. `G5_POST_PAYOUT_EXPOSURE_RULING.md` :18, :48-51, :142-144. `J2_stripe_reversal_mechanics.md` :123-140. `docs/release/PHASE2_PRODUCTION_RUNBOOK.md` :26, :98 (`kernel` added to PostgREST exposed schemas). pgTAP: `153` :693-727 (H3-H18c), `151` :694, `160` :83-95, `090_webhooks.sql`.

---

## 2. What I executed and results

`scripts/rehearsal_reset.sh snatchit_rehears_h` → exit 0, no file skipped. Then `scratchpad/kh_experiments.sql` (6 `native_primary` payments rows for one `auth.users` row, `stripe_livemode=true`; all in one ROLLBACKed txn; every call wrapped to capture SQLSTATE).

| # | Call sequence | Result |
|---|---|---|
| A1 | `record_dispute_native(dp_A, …, 'needs_response')` | `ok`, `linked:false`, 0 atoms, 0 payouts, 1 `dispute.alert/no_link` audit |
| A2 | `mark_dispute_state(dp_A,'under_review')` | `ok` |
| A3 | same again | `noop_replay` |
| A4 | `mark(dp_A,'lost')` | `ok` |
| A5 | late `created` → `record(dp_A,…,'needs_response')` | `noop_replay` (status stays `lost`) |
| A6 | `mark(dp_A,'lost')` replay | `noop_replay` |
| A7 | `mark(dp_A,'won')` | **P0001 `state_conflict: … terminal (lost) — won refused`** |
| A8 | stale `updated` → `mark(dp_A,'needs_response')` | **P0001 `state_conflict`** |
| — | audit rows for A | `dispute.alert/no_link, dispute.record/<key>, dispute.state_sync ×2` |
| B1 | `updated` before `created`: `mark(dp_B,'under_review')` | **P0002 `not_found`** |
| B2 | fallback `record(dp_B,…,'under_review')` | `ok` |
| B3 | late `created` → `record(…,'needs_response')` | `noop_replay`, status stays `under_review` ✔ |
| B4 | late `created` → `mark(dp_B,'needs_response')` (if a handler used mark for created) | **`ok` — status REGRESSES to `needs_response`** (open↔open is unordered) |
| C1 | `closed` before `created`: `mark(dp_C,'lost')` | P0002 `not_found` |
| C2 | fallback `record(dp_C,…,'lost')` | `ok`, zero freeze legs, **no `no_link` alert** (alert arm is open-only, 088:854) |
| C3 | late `created` → `record(…,'needs_response', due_by)` | `noop_replay`; `evidence_due_at` stays NULL |
| C4 | late `updated` → `mark(dp_C,'under_review')` | P0001 `state_conflict` |
| C5 | `closed` replay → `mark(dp_C,'lost')` | `noop_replay` |
| C6 | `mark(dp_C,'charge_refunded')` | P0001 `state_conflict` |
| D1-D5 | inquiry: `warning_needs_response → warning_under_review → needs_response → warning_closed` | all `ok`; then `needs_response` → `state_conflict` |
| D6 | `record` with `p_stripe_pi_ref = NULL` | P0002 `not_found: no payment for payment intent <null>` |
| D7 | `record` unknown PI | P0002 |
| D8 | 65-char command key | P0001 `invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]` |
| D9 | `mark` with NULL command key | accepted (`noop_replay`) — no regex on mark's key |
| D10 | `record` with `amount_minor = 0` | accepted |
| D11 | `mark` bogus status | P0001 `invalid_input` |
| D12 | `record` NULL reason | P0001 `invalid_input` |
| F | legacy `.closed(lost)` write on a native row: `payments.status='refunded'` | accepted (no trigger on `public.payments`); `public.transfers` rows for the native payment = 0 |
| G | discriminator query `payments ⋈ payment_native` by PI | `{"mode":"native_primary","status":"succeeded","stripe_livemode":true,"linked":false}` |
| H | `pg_proc.prosrc` of `record_dispute_native` mentions `mode` / `livemode`? | **false / false** — the RPC enforces NO rail and NO livemode gate |
| I | grants: `service_role` EXECUTE on `record_dispute_native`, `mark_dispute_state`, `record_organization_obligation`, `record_identity_obligation`, `hold_payout_transfer_reversed`, `mark_payout_transfer_state` | all **true** |
| I | `service_role` SELECT on `public.payments` / `kernel.payment_native` / `kernel.payout` / `kernel.dispute_native` | **true / false / false / false** |
| I | index on `public.transfers.stripe_transfer_id` / `kernel.payout.stripe_transfer_ref` | none / none |
| I | any `kernel.*payout*by*transfer*` reader | none (`grep` over 093/095) |
| I | consumers of `public.webhook_retries` in `supabase/functions`, `scripts`, `supabase/tests` | **none** (docs only); consumers of `get_incomplete_webhook_events` | **none** |
| I | `livemode` read anywhere in `index.ts` | none |

Not executed (no fixture in reach without the 153 harness): the atom/payout freeze legs (proved by 153 H5-H12), `settlement_royalty_lines` chargeback emission (153 H49-H56, 160), concurrent `created`/`updated` deliveries (a property of two isolates).

---

## 3. Findings

### P0

**P0-1 — Native disputes have no native writer; every native chargeback is invisible to the kernel.** `charge.dispute.created/closed` write only `public.disputes` / `public.transfers` / `public.payments` (:951-1088). For a `native_primary` payment the transfer lookup finds nothing (F: 0 rows) so **no freeze of any kind happens**; `kernel.dispute_native` stays empty, the 088:351-362 chargeback line never fires, `settlement_payout_maturity`'s `dispute_open` predicate (093:2126-2131) never trips, and `.closed(lost)` records the loss only as `payments.status='refunded'`. This is the gap G5:48-51 and 094:120-128 name; it is the reason this train exists.

### P1

**P1-1 — The P1-02 branches ACK their own failures, so a lost dispute record is never retried and nothing re-drives it.** `markProcessed({error})` (:307-315) releases the lease but returns void; the dispute/refund/transfer branches then fall through to :1354 and answer **200** (:1028-1038, :1064-1067, :1112, :1144, :1233). Stripe retries only on non-2xx. `069.webhook_retries` has **zero writers and zero readers** in the codebase (094:29's "069 retries locally on top" is false), and `get_incomplete_webhook_events` (064:164) has **no consumer**. Net: a failed `public.disputes` upsert is recorded as `failed_at` + `last_error` and then forgotten. The native branch MUST end with `finishDecision(...)`, never `markProcessed({error})`.

**P1-2 — The rail discriminator for dispute/charge/refund/transfer objects cannot come from `metadata` and must be DB-derived.** :241 reads the object's own metadata; a Dispute's `metadata` is the dispute's (empty), a Transfer's is the executor's, a Refund's is `refund-execute`'s. `resolveRail` (native.ts:115) returns `legacy_resale` for every one of them. `public.payments.mode` is an exact discriminator: CHECK = `{buy_now, auction, native_primary}` with the pairing CHECK (093:2995-3006, :3059-3081), every legacy row is `buy_now|auction` (000:995 was the whole vocabulary), `service_role` can SELECT it (I). **But** `record_dispute_native` itself checks neither `mode` nor `stripe_livemode` (H): the edge is the only rail/livemode guard, so the guard must be in the handler and must fail closed.

**P1-3 — Out-of-order deliveries produce `state_conflict` and `not_found`, and both must be ACKed, never retried.** A7/A8/C4/C6/D5 raise P0001 `state_conflict`; B1/C1 raise P0002. A redelivery carries identical bytes, so retrying either is a three-day retry storm (native.ts:13-23). The `not_found` fallback to `record` at the payload's status is correct (B2/C2) and idempotent against the late `created` (B3/C3 → `noop_replay`). Record-at-terminal (C2) runs **zero freeze legs and raises no alert** — the "freeze inverted relative to risk" case (093:655-657) — so the handler must alert on it itself.

**P1-4 — `created` must go through `record_dispute_native`, never `mark_dispute_state`.** B4 shows `mark` accepts any open→open move, so a late `created` via `mark` regresses `under_review → needs_response`. `record` is replay-safe by `stripe_dispute_ref` (A5/B3/C3); `mark` is not ordered within the open set.

**P1-5 — `transfer.reversed` native routing has no DB reader and a partial-after-paid hole.** Native transfers carry `transfer_group = payout_<uuid>` + `metadata.payout_id/source='payout-execute'` (executor.ts:364-366, :772-780); legacy transfers carry `metadata.transfer_id/payment_id/seller_id` and no group (payouts.ts:135-143). `service_role` cannot SELECT `kernel.payout` (I) and no `kernel` reader resolves `tr_ → payout` (I), so status must be learned by calling a verb and classifying its raise. `mark_payout_transfer_state('reversed')` requires `paid` and `hold_state='none'` (085:1682-1699); `hold_payout_transfer_reversed` requires `submitted` (095:729-733) and refuses `paid` with a pointer at the other verb. A **partial** reversal after `paid` is unrepresentable (J5 §8; 095:721-728) → ack+alert only. The legacy `mark_transfer_reversed` returns `false` for a native `tr_` (no `public.transfers` row) and ACKs — harmless.

**P1-6 — `.closed(lost)` cannot honestly book an org obligation synchronously.** 094's `unlined_reversal` guard is one-directional (:392-401: refuses an obligation if a `chargeback` line exists; the 088 line arm does NOT check `organization_obligation`), so booking at webhook time and lining at the next close **double-counts**. G5 §6 and 094:120-128 say the chargeback origin stays inert until a separate decision. `record_identity_obligation` (spec §20.7.14) applies to identity-held proceeds — the resale sale arm, DARK.

### P2

- **P2-1** `mark_dispute_state(text,text,text)` carries no `evidence_due_at` / `amount` — spec §4:1217 "evidence-clock sync" on `.updated` is not implementable with the shipped signature (C3: `evidence_due_at` stays NULL after record-at-terminal + late created). New migration if wanted.
- **P2-2** Legacy `.closed(lost)` and `charge.refunded` set `payments.status='refunded'` on native rows, including partial refunds/partial disputes; `stripe_refund_id` = first refund only. Readers tolerate it (refund-execute :250; 085:664; finalize reads `kernel.refund`), so it is a semantic overload, not a defect. Keep for non-regression; `kernel.refund`/`kernel.dispute_native` are the authorities.
- **P2-3** `event.livemode` is never read; `payments.stripe_livemode` gates only refund/payout executors (payout-logic.ts:116). Native dispute writes should require `event.livemode === true && payments.stripe_livemode === true` (mirror `rowIsLiveActionable`), else ack+alert.
- **P2-4** `charge.dispute.updated`, `charge.dispute.funds_withdrawn|funds_reinstated`, `refund.*`, `charge.refund.updated`, `transfer.updated` all hit the else (:1346) → ack. Whether the Stripe endpoint even subscribes to `.updated` is a Dashboard fact — **unverified**.
- **P2-5** `record_dispute_native` P0002 on `payment_intent = null` (D6). On the native rail a PI always exists (primary-checkout); a null-PI dispute is legacy by construction → route legacy.
- **P2-6** `charge_refunded` is in the 088 status CHECK; current Stripe API versions may no longer emit it — **unverified**. Accept it, do not depend on it.
- **P2-7** Two distinct event ids (`created`, `updated`) for one dispute can run concurrently under the 064 lease (lease is per event id). `record` handles the insert race (`unique_violation → noop_replay`, 088:799-803); `mark`'s `not_found → record → noop_replay` fallback must then re-issue `mark` once.
- **P2-8** `mark_dispute_state` accepts a NULL/unbounded command key (D9); `record` bounds it to 64 chars (D8). Use `wh_dispute_<created|updated|closed>:<event.id>` (≤ 50 chars).
- **P2-9** `tests/stripe-webhook-native.test.ts` has no dispute/refund/transfer coverage; the classifier for `state_conflict`/`not_found`/`payout_held`/`payout_state_backwards` does not exist yet.

---

## 4. Tables

### 4.1 Event inventory — what the handler does TODAY

| Event | Lines | Legacy write | Native write | Idempotency | Failure → HTTP | Dup / OoO / first-terminal |
|---|---|---|---|---|---|---|
| `payment_intent.succeeded` | :383-780 | claim `payments` `.neq(succeeded)`, `mark_listing_sold`/`complete_auction_payment`, `transfers` insert (23505 benign), push | claim `.neq(succeeded).neq(refunded)`, `venue.finalize_primary_order` (E3 L1-L4) | 064 + claim UPDATE + `payment_native_payment_uq` + ownership-log key | native: `finishDecision`; legacy: `finish(false)` → 500 | dup: replay noop; OoO refund-before-success: ack+alert; n/a |
| `payment_intent.payment_failed` | :781-937 | `payments→failed` `.neq(succeeded,refunded)`, `release_reservation` (buy_now); DB error → **200** (:904-908) | same claim, `cancel_pending_order` only if PI `canceled` | claim guards | native: Decision; legacy: 200 always | per-attempt; late failed after success is a no-op |
| `payment_intent.canceled` | :874-882 | ack-only | `venue.cancel_pending_order` (`noop_replay`) | RPC | Decision | idempotent |
| `charge.dispute.created` | :951-1046 | `payments` lookup, `transfers` lookup → `freeze_transfer_for_dispute`, `disputes` upsert on `stripe_dispute_id` | **none** | upsert; 0561 predicate | upsert error → `markProcessed({error})` → **200** (P1-1) | dup: upsert overwrites status with the (same) payload; OoO: a late `created` after `closed` **overwrites status back to open** in `public.disputes` (upsert :1016-1027 has no forward-only guard); first-terminal: n/a |
| `charge.dispute.updated` | :1346 else | ack-only | none | — | 200 | — |
| `charge.dispute.closed` | :1048-1088 | `disputes.status=payload`, `lost` → `payments→refunded` `.neq(refunded)` | none | `.neq(refunded)` only | DB error → **200**; unknown dispute → 200 | closed-before-created: `!ourDispute` → ack, **dispute never recorded**; then late `created` records it as open forever |
| `charge.dispute.funds_withdrawn/reinstated` | else | ack-only | none | — | 200 | — |
| `charge.refunded` | :1090-1120 | `payments→refunded` + `stripe_refund_id` (first) | none (E4 §5.1: executor writes `succeeded` itself) | `.neq(refunded)` | error → **200** | partial refunds flip status to `refunded` (P2-2) |
| `refund.updated/failed`, `charge.refund.updated` | else | ack-only | none | — | 200 | — |
| `transfer.created` | :1122-1131 | log | none (executor already wrote `paid`; a webhook `mark('paid')` would be `noop_replay` or race the executor) | — | 200 | — |
| `transfer.updated` | else | ack-only | none | — | 200 | — |
| `transfer.reversed` | :1133-1155 | `mark_transfer_reversed(tr.id)` (`false` = no row / already reversed → ack) | **none** | 0561 `status<>'reversed'` | RPC error → **200** | native `tr_` → `false` → ack silently |
| `payout.paid` / `payout.failed` | :1157-1178 | log | none (spec :1222 — must stay NONE) | — | 200 | — |
| `account.updated` | :1180-1344 | profiles 4 cols | `kernel.sync_org_connect_state` | `connect_state_synced_at` | profile error → **200**; org sync retryable → 500 | handled (E3) |
| other | :1346-1352 | ack | — | — | 200 | — |

### 4.2 Discriminator per object type — recommendation: DB-derived, never metadata

| Object (event) | Join key on the object | Lookup (service_role-reachable?) | Discriminator | Ambiguity → response |
|---|---|---|---|---|
| Dispute (`charge.dispute.*`) | `dispute.payment_intent` (string\|null) | `public.payments.stripe_payment_intent_id` UNIQUE (000:988) — **yes** | `payments.mode = 'native_primary'` ⇒ NATIVE; `buy_now|auction` ⇒ LEGACY; no row / null PI ⇒ LEGACY (legacy already tolerates `paymentId=null`) | `mode` outside the CHECK set is impossible (093); `stripe_livemode !== true` or `event.livemode !== true` on a native row ⇒ ack+alert, no native write |
| Charge (`charge.refunded`) | `charge.payment_intent` | same | same | same |
| Refund (`refund.*`) | `refund.payment_intent` / `refund.metadata.refund_id` (refund-execute :299) | same; `kernel.refund` NOT readable by service_role | `payments.mode`; native reconciliation joins on `re_…`/`metadata.refund_id` via `mark_refund_state` (spec :1214) | out of this train; executor already converges |
| Transfer (`transfer.*`) | `transfer.transfer_group`, `transfer.metadata` | `public.transfers.stripe_transfer_id` (no index, service_role yes); `kernel.payout` **not readable** | `transfer_group ~ '^payout_<uuid>$'` **or** `metadata.source='payout-execute' && metadata.payout_id` ⇒ NATIVE (payout_id from the object, no DB read); `metadata.transfer_id` present & no group ⇒ LEGACY | neither ⇒ **ack + alert, never guess**; both ⇒ ack + alert (cross-rail reuse) |
| PaymentIntent | `metadata.rail` (native.ts) | — | as shipped | as shipped |

Option (b) "fetch the PI/charge from Stripe" adds a network hop and trusts nothing the DB does not already say — rejected. Option (c) charge metadata: `dispute.charge` is an id string; a PI's metadata is not copied onto the Charge by Stripe — rejected.

### 4.3 Routing matrix — owner per event × rail

| Event | LEGACY / RESALE (`mode ∈ {buy_now, auction}`) | NATIVE PRIMARY (`mode = 'native_primary'`) |
|---|---|---|
| `charge.dispute.created` | as today (:951-1046) | `record_dispute_native(dispute.id, dispute.charge, dispute.payment_intent, amount, currency, reason, status, due_by, key)`; **plus** the legacy `disputes` upsert with `transfer_id=null` (keeps DAY8 ops view; harmless) |
| `charge.dispute.updated` | `disputes` upsert (today: nothing) — optional | `mark_dispute_state(dispute.id, status, key)`; `not_found` → `record` at payload status |
| `charge.dispute.closed` | as today | `mark_dispute_state`; `not_found` → `record` at terminal (zero legs) + alert; `lost|charge_refunded` → alert (loss booking: see P1-6) |
| `charge.refunded` | as today | keep legacy `payments` write (shared table, tolerated); native reconciliation deferred (E4 §5.1) |
| `refund.updated/failed` | ack | deferred (spec :1214-1216; `mark_refund_state` by `metadata.refund_id`) |
| `transfer.created` | log | log (executor is the `paid` writer — O16 form (a)); do NOT `mark('paid')` from here |
| `transfer.reversed` | `mark_transfer_reversed` | `payout_id` from `transfer_group`; full ⇒ `mark_payout_transfer_state(payout_id,'reversed',tr,null,key)`; `payout_state_backwards (submitted → reversed)` ⇒ `hold_payout_transfer_reversed`; partial after paid ⇒ ack+alert; `payout_held` ⇒ ack+alert |
| `transfer.updated` | ack | ack |
| `payment_intent.*` | as shipped | as shipped |
| `payout.*` | log | log — NEVER derive a payout id from `po_…` (spec :1222) |

### 4.4 Idempotency layers for the native dispute branch

1. **L1 event lease (064)** — per `event.id`; `in_flight → 409`; failure releases; abandoned lease recovered after 300 s. Does NOT serialize two different event ids about one dispute (P2-7).
2. **L2 business uniqueness** — `dispute_native_stripe_ref_uq` (088:208): `record` replays to `noop_replay` (A5/B3/C3), and the concurrent-insert race collapses to `noop_replay` (088:799-803). `mark` is forward-only + terminal-absorbing (A3/A6/C5 `noop_replay`; A7/A8/C4/C6/D5 `state_conflict`).
3. **L3 downstream** — chargeback line dedupe on `(cause='chargeback', cause_ref=dispute_id)` (088:359-360); `organization_obligation_dispute_uq` (094:240-242); freeze legs run only on the FIRST open record (088:804-806 — never on replay, never at terminal).

Crash between `record` OK and `complete_stripe_webhook_event`: retry → `record` → `noop_replay` → ack. Crash between `mark` OK and complete: retry → `mark` → `noop_replay` → ack. Both fine. Crash between the native arm and the legacy arm: retry re-runs the (idempotent) legacy upsert. `record` on `.closed` needs amount/reason/charge/currency — the Dispute object on every `charge.dispute.*` event is the full object (Stripe: `data.object` is the Dispute), so record-at-terminal from `.closed` is well-formed (C2 executed with exactly those fields).

### 4.5 DECISION TABLE — native dispute branch (event × prior `kernel.dispute_native` state → verb → response)

Pre-steps for every `charge.dispute.*`: (0) `dispute.payment_intent` null ⇒ LEGACY only. (1) `payments` by PI ⇒ absent ⇒ LEGACY only. (2) `mode ≠ 'native_primary'` ⇒ LEGACY only. (3) `stripe_livemode !== true || event.livemode !== true` ⇒ **ack + alert `native_dispute_not_livemode`**, no native write, legacy still runs. (4) `status` not in the 8-label set ⇒ **ack + alert `native_dispute_unknown_status`** (redelivery cannot fix it).

| Event | Prior state | Verb | RPC result | Response |
|---|---|---|---|---|
| created | none | `record(status=payload)` | `ok`, `linked:true` | ack; log atoms/payouts held |
| created | none | `record` | `ok`, `linked:false` (no-link arm) | ack + **alert** `native_dispute_no_link` (RPC audits, edge must page) |
| created | none, payload status terminal | `record` | `ok`, zero legs | ack + alert `native_dispute_recorded_terminal` |
| created | exists (any status) | `record` | `noop_replay` | ack (do NOT `mark` — P1-4) |
| updated | none | `mark` → P0002 → `record(status=payload)` | `ok` | ack (+ alert if `linked:false` or terminal) |
| updated | none, but `record` → `noop_replay` (race with `created`) | re-issue `mark` once | `ok`/`noop_replay` | ack; second P0002 ⇒ ack + alert `native_dispute_race_unresolved` (retryable? no — the row exists now; alert) |
| updated | open | `mark(open')` | `ok` / `noop_replay` | ack |
| updated | open | `mark(terminal)` | `ok` | ack; if `lost|charge_refunded` → alert `native_dispute_lost` (loss visible; no booking — P1-6) |
| updated | terminal, same | `mark` | `noop_replay` | ack |
| updated | terminal, different | `mark` | P0001 `state_conflict` | **ack + alert** `native_dispute_stale_update` (never retry) |
| closed | none | `mark` → P0002 → `record(terminal)` | `ok`, zero legs | ack + **alert** `native_dispute_closed_before_created` (freeze inverted; G5 exposure) |
| closed | open | `mark(terminal)` | `ok` | ack; `lost|charge_refunded` → alert; `won|warning_closed` → log (holds persist — PFA-31; `won` does NOT release) |
| closed | terminal, same | `mark` | `noop_replay` | ack |
| closed | terminal, different | `mark` | `state_conflict` | ack + alert `native_dispute_terminal_conflict` |
| any | — | `invalid_input` (P0001) | — | ack + alert (event defect or our argument bug) |
| any | — | `not_found` from `record` (payment vanished between step 1 and the RPC) | — | ack + alert |
| any | — | 42501 / PGRST202 (kernel not exposed) | — | **retry** + alert (ops-fixable) |
| any | — | transient PG (08\*, 40001, 40P01, 53\*, 55P03, 57\*, 58\*, XX000) | — | retry (+alert) |
| any | — | unclassified | — | retry + alert (fail toward not losing the money event) |

Command keys: `wh_dispute_created:<event.id>` / `wh_dispute_updated:<event.id>` / `wh_dispute_closed:<event.id>` (audit-only for both verbs; ≤ 64 chars, regex-safe). Ordering inside the handler: **native arm first, then legacy arm**; a native `ack:false` returns 500 before the legacy arm runs (the retry re-runs both; legacy is idempotent).

### 4.6 Decision table — `transfer.reversed` native

| Discriminator | Verb | Result | Response |
|---|---|---|---|
| no `transfer_group`/`metadata.payout_id`, has `metadata.transfer_id` | legacy `mark_transfer_reversed` | as today | as today |
| neither / both | none | — | ack + alert `transfer_rail_ambiguous` |
| `payout_<uuid>`, `amount_reversed ≥ transfer.amount` (or `reversed:true`) | `mark_payout_transfer_state(id,'reversed',tr,null,key)` | `ok` / `noop_replay` | ack |
| same | raises `payout_state_backwards (submitted → reversed)` | → `hold_payout_transfer_reversed(id,tr,amount,amount_reversed,{origin:'webhook'},key)` | `held`/`noop_replay` → ack |
| same | raises `payout_state_backwards (pending|failed|reversed → …)` | — | ack + alert |
| same | raises `payout_held` | — | ack + alert (a held payout is a human's) |
| `payout_<uuid>`, partial (`0 < amount_reversed < amount`) and payout `paid` | none | — | ack + alert `partial_reversal_unrepresentable` (J5 §8) |
| `payout_<uuid>`, partial and payout `submitted` | `hold_payout_transfer_reversed` | `held` (`transfer_partially_reversed`) | ack + alert |
| P0002 (unknown payout) | — | — | ack + alert |
| `conflict_locked` (write-once ref mismatch) | — | — | ack + alert |
| 42501/transient | — | — | retry |

### 4.7 Legacy non-regression for native rows

MUST keep: `charge.refunded` → `payments.status='refunded'` (the native `succeeded` claim's `.neq('refunded')` and `finalize_primary_order`'s protection lean on `kernel.refund`, but `request_order_refund` (085:664) and refund-execute (:250) read `payments.status` and tolerate `refunded`); `.closed(lost)` → `payments.status='refunded'` (same readers; keeps the DAY8 pack coherent). Harmless: `disputes` upsert with `payment_id` set, `transfer_id=null`; `transfers` lookup → 0 rows → `freeze_transfer_for_dispute` never called. Must NOT: nothing in the legacy arms writes anything a native row can be harmed by. One legacy defect that ALSO affects native rows: the `disputes` upsert has no forward-only guard, so a late `created` after `closed` rewinds `public.disputes.status` (4.1) — cosmetic (ops view), not money.

---

## 5. Options, trade-offs, smallest honest design

**Option A — native arm inside the existing branches + a new `charge.dispute.updated` branch; DB-derived discriminator; `record`/`mark` only; loss = alert, no booking.** No migration. Closes P0-1 (freeze legs fire when the dispute is seen open; chargeback line arm becomes live), P1-2/3/4, P2-3. Leaves P1-6 (org obligation) and P2-1 (evidence clock) open by design. Honest as long as the report says the record-at-terminal path holds nothing and that a lost dispute still has no resolution path (PFA-31). **This is the smallest honest design.**

**Option B — A + book `record_organization_obligation('unlined_reversal', dispute_id)` on `.closed(lost)`.** No migration, but **double-counts** against the 088 chargeback arm at the next close (094's guard is one-directional) — dishonest without a new migration adding the reverse guard to `settlement_royalty_lines`. Rejected for this train.

**Option C — A + `transfer.reversed` native routing via do-then-classify (`mark('reversed')` → on `payout_state_backwards` → `hold_payout_transfer_reversed`).** No migration; closes G5:51. Costs: two RPC round-trips on the rare path; error-string classification (the strings are quoted above from 085:1698 / 095:729). Alternative C′: a new DEF reader `kernel.get_payout_by_transfer_ref(text)` in 096 — cleaner, adds a migration + an index on `stripe_transfer_ref`. Either is honest; C′ is the right long-term shape.

**Option D — log-only native arms (no writes).** Dishonest: leaves P0-1 exactly where it is while looking wired.

**Option E — a second webhook endpoint.** Rejected by spec §4:1198-1200 (one signed surface).

What would be dishonest in any option: (i) returning 200 after a failed `record` (P1-1 pattern); (ii) retrying `state_conflict`/`not_found`; (iii) using `mark` for `created`; (iv) treating `won` as a release; (v) deriving a payout from `payout.paid`; (vi) writing a freeze at terminal by hand.

Minimum tests for A/C: extend `tests/stripe-webhook-native.test.ts` with a `classifyDisputeError` (strings above), a `resolveDisputeRail(paymentRow, event)` (mode/livemode/absent), a `resolveTransferRail(transfer)` (group/metadata/ambiguous), and the 4.5/4.6 tables as `it` cases; pgTAP (new `162_*`, none of 151/153/160 touched) for B/C sequences exactly as executed in §2.

---

## 6. Open questions for the orchestrator / owner

1. **Loss booking on `.closed(lost)` for a primary order** — accept "alert only, chargeback line arm at next close, operator books `unlined_reversal` for a dormant org" for this train, or fund a 096 that makes 094's guard bidirectional so the webhook can book synchronously (G5 direction: "obligation is THE durable record")?
2. **`transfer.reversed`** — Option C (do-then-classify, no migration) or C′ (new reader + index, 096)? Or log+alert only?
3. **Is the Stripe endpoint subscribed to `charge.dispute.updated`** (and `funds_withdrawn`)? Dashboard fact, unverified; without it the open↔open sync never arrives.
4. **`evidence_due_at` / `amount` sync on `.updated`** (P2-1) — worth a `mark_dispute_state` overload in 096, or accept `record`-time values?
5. **Livemode gate for native dispute writes** — confirm `event.livemode && payments.stripe_livemode` (ack+alert otherwise), mirroring `rowIsLiveActionable`.
6. **Legacy `disputes` upsert forward-only guard** (4.1) — fix in this train (edge-only change) or leave?
7. **P1-1 for the legacy branches** — should the P1-02 branches be moved to `finish(false)` (Stripe retry) in this train, or is that a separate non-regression risk the owner wants isolated?
8. **`won` semantics** — confirm holds persist on `won` (PFA-31) and that a seller-win release stays parked; the handler will log `won` and release nothing.
