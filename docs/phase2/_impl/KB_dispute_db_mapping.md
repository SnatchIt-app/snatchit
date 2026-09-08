# KB — Native payment/dispute DB mapping and writer authority

Investigator B · 2026-09-03 · repo `/Users/josetascon/snatchit-consol` @ 609e0f4 · rehearsal DB `snatchit_rehears_b` (fresh replay of 000–095 + 5 timestamped, then my own committed fixture; every scenario ran inside `BEGIN … ROLLBACK`). Nothing outside this file was written. No Stripe API, no Supabase MCP, no remote.

Scratch scripts (not in repo): `scratchpad/fixture_b.sql`, `scen1_lifecycle.sql`, `scen2_authority.sql`, `scen3_redo.sql`, `scen4_retry.sql`.

---

## 1. What I inspected (file:line)

| Subject | Where |
|---|---|
| `kernel.dispute_native` table, CHECKs, resolution quadruple, no-DELETE | 088:189-219, 088:229 (`revoke delete … from service_role`) |
| `kernel.record_dispute_native` | 088:758-873 — input checks 088:769-782, replay 088:784-787, PI lookup 088:789-792, open-set 088:804, atom leg 088:806-833, payout leg 088:834-853, no-link arm 088:854-859 |
| `kernel.mark_dispute_state` | 088:875-903 |
| `kernel.resolve_dispute_native` (PARKED) | 088:913-931 |
| EXECUTE grants | 088:1850 (resolve → authenticated), 088:1859-1860 (record/mark → service_role) |
| `kernel.unlock_ticket` R-40 re-arm | 088:560-588 |
| `kernel.deletion_blockers_market` BP-7 | 088:483-490 |
| `kernel.payment_native` | 085:40-66 (append-only trigger 085:64-66; `payment_native_subject_xor_ck`) |
| `venue.finalize_primary_order` — payment checks + payment_native insert | 085:1919-1938 (status/buyer/total/refund probe; NO mode check, NO dispute check), 085:2059-2061 (link insert) |
| `kernel.payout`, `hold_payout`, `release_payout`, `mark_payout_transfer_state` | 085:111-147, 085:769, 085:807-840, 085:1668-1735 (`payout_held` refusal 085:1690-1692) |
| `venue."order"` columns (no venue_id) | 082:74-94 |
| `catalog.event.venue_id` / `event_session.event_id` | 078:136, 078:175 |
| `venue.settlement_line` (cause set, cause_ref) | 087:92-106 |
| `kernel.settlement_primary_lines` (credit arm cause_ref = **order_id**) | 093:435-560, specifically 093:483 |
| `kernel.settlement_royalty_lines` chargeback arm (093 re-create) | 093:1136-1215 (arm 093:1185-1189, face cap 093:1191-1202, currency filter 093:1188) |
| `kernel.close_settlement` (093) | 093:640-…, payout mint + G2 gate 093:724-… |
| `kernel.settlement_payout_maturity` open-dispute predicate | 093:2126-2130 |
| `kernel.settlement_covered_payments` | 093:1989-2020 |
| `kernel.deletion_blockers_money` (BP-5/6/12; no dispute predicate) | 093:1529-1616 |
| payments contract PART 20 (mode CHECK widened, rail-pairing CK) | 093:2780-3281 (mode CK 093:3005, pairing 093:3067-3088) |
| `public.payments` base shape | 000:971-1002; `stripe_livemode` 045:15 |
| `kernel.organization_obligation` + `settlement_shortfall` producer | 094:186-201, 094:117-127 (`unlined_reversal` INERT) |
| 095 `retry_held_payout` + maturity code list + executor gate | 095:485-560 (`not_a_maturity_hold` 095:546), 095:459-483, 095:1070-1090 |
| `kernel.settlement_unbooked_refund_exposure` (refunds only) | 095 (function body: `kernel.refund` only) |
| door admissibility | 086:1123-1126 (`admissible = state='active' and resale_state='none' and not is_transfer_frozen`) |
| Webhook routing | `stripe-webhook/native.ts:115-132` (resolveRail), `index.ts:951-1046` (dispute.created → LEGACY only), `index.ts:1048-1082` (dispute.closed; `lost` ⇒ `payments.status='refunded'` at 1078), `index.ts:429-430,502` (payment succeeded write then finalize) |
| `primary-checkout/index.ts:1197-1207` | payments row born `pending`, `mode='native_primary'`, listing/seller NULL |
| Stripe Dispute object (docs.stripe.com/api/disputes/object, fetched 2026-09-03) | `status` enum = `warning_needs_response, warning_under_review, warning_closed, needs_response, under_review, won, lost, prevented`; `payment_intent` nullable |
| Prior tests reused as fixture pattern | tests/153:209-300, tests/161:60-105 |

---

## 2. What I executed and results

### 2.1 Fixture (committed in `snatchit_rehears_b`)
org1 (seller = org_owner+venue_manager; other_user = org_finance, matured) → venue1 (event1/session1, tt1 5000, batch1) and venue2 (event2/session2, tt2 5000, batch2). Signing keys per_event. Payments `mode='native_primary'`, listing/seller NULL, `stripe_livemode=false`, total = face + 10% fee:

| PI | buyer | face | total | order | finalized |
|---|---|---|---|---|---|
| pi_kb_1 | buyer | 15000 | 16500 | order1 (3 atoms, session1/venue1) | yes |
| pi_kb_3 | buyer | 5000 | 5500 | order3 (1 atom, session1/venue1) | yes |
| pi_kb_2 | other_user | 5000 | 5500 | order2 (1 atom, session2/venue2) | yes |
| pi_kb_4 | fan | 5000 | 5500 | order4 (session1) | **no** — succeeded, never finalized (no payment_native) |
| pi_kb_5 | fan | 5000 | 5500 | — | payment `status='pending'` |
| pi_fixture_a | buyer | legacy `buy_now` (tap.payment_a, listing A) | | — | legacy |

Config: `payout.settlement_maturity_interval="7 days"`, `authn.money_role_maturity_hours=24`, `feature.native_issuance_enabled=true`. Sessions moved 30 days into the past for each close, restored after. st1 = event1 → lines `primary_sale/order1 +15000`, `primary_sale/order3 +5000`, net 20000 → **po1** (pending, unheld). st2 = event2 → `primary_sale/order2 +5000` → **po2** (pending, unheld).

### 2.2 Resolution chain (item 1) — executed
```
pi_kb_1 → payments 7f0572ff mode=native_primary livemode=f status=succeeded
        → payment_native.order_id=38a99813 (sale_id NULL)
        → venue.order.org_id=2f56ae14, event_session_id=72106ffd
        → catalog.event_session.event_id=cea4b722 → catalog.event.venue_id=4e2f7f59 (venue1)
```
`venue."order"` has **no venue_id** (082:74-94); venue is derivable only via `order.event_session_id → event_session.event_id → event.venue_id`. pi_kb_4 and pi_kb_5 resolve to a payment but to NO order (no payment_native row).

### 2.3 Lifecycle matrix (item 2) — all executed as `service_role`

| # | Call | Result |
|---|---|---|
| S1 | record `needs_response` 15000 usd on pi_kb_1 | `{"status":"ok","linked":true,"atoms_held":3,"payouts_held":1,"atoms_skipped":0}`; 3 atoms `active/dispute_hold`; **po1 held** (`status=pending hold=held reason=dispute held_by=NULL`); **po2 untouched**; 1 `payout_on_hold` outbox row; audit `dispute.record`; order3's atom (same buyer, same session) untouched |
| S2 | same ref again | `noop_replay` (amount/charge/PI on the replay are ignored — A5) |
| S3 | mark `under_review`, then record again | mark `ok`; record `noop_replay`; status stays `under_review` |
| S9 | open↔open (`under_review→needs_response→warning_needs_response`) | all `ok` (no ordering enforced among the 5 open states) |
| S7 | `→lost` ; `lost→won` ; `lost→lost` ; `lost→needs_response` ; `lost→charge_refunded` | `ok` ; `P0001 state_conflict … terminal (lost) — won refused` ; `noop_replay` ; `state_conflict` ; `state_conflict` |
| after lost | atoms still `active/dispute_hold`; po1 still `held/dispute`; `order1.status=paid`; `payments.status=succeeded`, `refunded_at=NULL`; `kernel.refund` rows = 0; `deletion_blockers_market(buyer)=NULL` (BP-7 clears at terminal); `deletion_blockers_money(buyer)='BP-12: post-event deletion hold unset…'`; `unlock_ticket` → `noop_replay/dispute_hold` |
| next close (venue1 period, after lost) | st3: line `chargeback/-15000` (cause_ref = dispute_id), gross 0, net **-15000**, `payout_ids=[]` |
| S8 | mark unknown ref | `P0002 not_found: dispute dp_unknown` |
| S4 | record **lost first** on pi_kb_3 | `ok, linked=true, atoms_held=0, payouts_held=0` — **no freeze at all**; po1 stays `pending/none`; `deletion_blockers_market(buyer)=NULL` |
| S4b | record first as `won` / `charge_refunded` / `warning_closed` | all `ok`, zero legs |
| S5 | amount 9,999,999 > face on pi_kb_3, lost | accepted; next close books `chargeback/-5000` (capped at face, 093:1191-1202) |
| S6 | amount 16500 = face+fee on pi_kb_1, lost | accepted; next close books `chargeback/-15000` (fee never charged to venue — A5 holds) |
| S6b | amount 0, open, on pi_kb_2 | accepted; **freezes** 1 atom + po2 (`payouts_held=1`) — a zero-amount inquiry freezes money; a zero-amount `lost` is never lined (`amount_minor > 0`, 093:1185) |
| combined negative close | st3 with dp_big+dp_fee: lines -15000, -5000, net **-20000**, no payout; `kernel.organization_obligation` row `settlement_shortfall/…/outstanding` minted (094) |

### 2.4 Writer authority / adversarial inputs (item 3) — role tests via a SECURITY INVOKER wrapper (`tap._tryi`) so grants bind

| # | Input | Result |
|---|---|---|
| R1 | `authenticated` record / mark | `42501 permission denied for function` (both) |
| R2 | `authenticated` resolve | reaches body → `42501 insufficient_privilege: platform_risk / platform_support (propose) or platform_admin (execute) only` |
| R3 | `anon` record | `42501 permission denied for schema kernel` (076 wall) |
| R4 | `service_role` record / mark | `ok` |
| R5 | `service_role` resolve | `42501 permission denied for function resolve_dispute_native` (grant is authenticated-only, 088:1850) |
| R6 | `service_role` SELECT/INSERT/UPDATE/DELETE `kernel.dispute_native`, UPDATE `kernel.tickets.resale_state`, UPDATE `kernel.payout.hold_state` | all `42501 permission denied for table` — service_role has schema USAGE only (PFA-21); the two functions are the ONLY writers |
| R7 | table owner (`postgres`) direct `UPDATE status lost→needs_response` | **succeeds** — no forward-only trigger on `dispute_native` (only `tg_dispute_native_set_updated_at`); forward-only is enforced solely inside `mark_dispute_state` |
| R8 | owner writes half of the resolution quadruple | `23514 dispute_native_resolution_pairing_ck`; all four → succeeds |
| EXECUTE ACLs (catalog) | record = `postgres,service_role`; mark = `postgres,service_role`; resolve = `postgres,authenticated` |
| A1 | PI `pi_nope` | `P0002 not_found: no payment for payment intent pi_nope` |
| A11 | PI **NULL** (Stripe `payment_intent` is nullable) | `P0002 not_found … <null>` — unrecordable; the charge ref is never consulted |
| **A2** | PI of a **LEGACY `buy_now`** payment (`pi_fixture_a`) | **ACCEPTED**: `ok, linked=false` — a `kernel.dispute_native` row now points at a legacy payment; `deletion_blockers_market(buyer)='BP-7: open native dispute'`; legacy `public.disputes`=0 rows, legacy transfer untouched. No `payments.mode` check anywhere in 088:789-792 |
| A3 | PI of a `status='pending'` native payment (pi_kb_5) | accepted (`linked=false`) — no `payments.status` check |
| A4 | currency `eur` lost on a USD payment (pi_kb_2) | accepted, stored `EUR`; next venue2 close books **nothing** for it (093:1188 `d.currency = s.currency`), no alert; stays unlined forever. `uSd` normalises to USD and books |
| A5 | duplicate ref, different charge/PI/amount/currency/status | `noop_replay`; first row wins silently |
| A6 | two different dispute refs on the same payment (7000 + 8000) | 2nd: `atoms_held=0, atoms_skipped=3` (audited `overlay_occupied`), `payouts_held=0` (already held); Σ 15000 = face; chargeback arm caps cumulatively per order |
| A7 | amount -1 / NULL | `invalid_input: amount_minor must be >= 0` |
| A8 | record `p_command_key` NULL / '' / 'a b' / 65 chars / Cyrillic | all refused (`invalid_input …`) |
| A8b | **mark** `p_command_key` NULL / 209-char junk with spaces | **accepted**; NULL → audit reason_code `state_sync`; the 209-char string lands verbatim in `kernel.admin_audit.reason_code` (record's E-80 bound is not applied to mark) |
| A12 | `stripe_dispute_ref=''`, `stripe_charge_ref=''`, `reason=''` | **accepted** (`ok`, froze 1 atom) — only NULL is refused |
| A13 | `evidence_due_at` on replay | ignored (`noop_replay`) |

### 2.5 Freeze legs for a PRIMARY order (item 4)
- 093:483 writes `primary_sale.cause_ref = order_id`; 088:844 looks up `sl.cause_ref = coalesce(order_id, sale_id)` → **matches** (S1: `payouts_held=1`, po1 = settlement-cause payout with `cause_ref = st1`). Scope isolation holds by construction: only settlements whose lines name that order are reached; venue2's po2 untouched. The lookup is not filtered by `sl.cause`, so a `refund_void`/`chargeback` line whose cause_ref happened to equal an order_id would also match — impossible today (those cause_refs are refund_id/dispute_id).
- Promoter commission payouts carry `cause_ref = attribution.id` (090:1483-1485), NOT a settlement_id, so the payout leg never reaches them ("settlement AND commission payouts alike" in 088:750 is not what the predicate does). Dark today.
- F1 payout already `submitted` → held (`status=submitted hold=held`). F2b: `mark_payout_transfer_state(...,'paid',…)` on it → `precondition_failed: payout_held` (085:1690-1692): a transfer already sent to Stripe can no longer be recorded; row strands at submitted/held until `release_payout`.
- F3 `probation_hold` → upgraded to `held/dispute`.
- F4 payout already `paid` → nothing held, no obligation row; only the next close's negative net produces a `settlement_shortfall` (094).
- F5 atom `state='scanned'` → skipped, audited `overlay_occupied` although `resale_state='none'` (reason_code mislabels a state skip).
- **F6** `kernel.release_payout` by `platform_risk` on a `dispute` hold **while the dispute is still open** → `ok`, hold cleared. 085:827 "releases 'held' AND 'probation_hold'" — no reason scoping; 088:836-838's claim that the release path "never releases a 'dispute' hold" is not in the bytes.
- X: `retry_held_payout` on a `dispute` hold → `not_a_maturity_hold` (095:546) — correct; after `won` still refused (only `release_payout` exits it).

### 2.6 No-link arm / dispute before finalize (item 5)
- A native_primary payment has a `payment_native` row ONLY after `finalize_primary_order` (085:2059-2061); `primary-checkout` mints the payments row `pending` (index.ts:1197-1207) and the webhook flips it to `succeeded` (index.ts:429-430) and then finalizes (index.ts:502). Any dispute arriving in that window (or on a payment whose finalize failed: no signing key, oversell, erased buyer) hits the no-link arm.
- N1: record open on pi_kb_4 → `linked=false`, audit `dispute.alert/no_link`. Then `finalize_primary_order(order4, pay4)` → **`ok`**, atom minted `active/none` (085:1936-1938 probes `kernel.refund` only — an open dispute does not block finalize). The atom is transferable/listable; only `unlock_ticket` re-arms (`ok → dispute_hold`) if it is ever locked and released. Venue1 period close → `primary_sale/order4 +5000`, payout minted **held `dispute_open`** (10m does catch the open dispute).
- Then `mark lost`; with a Connect destination bound: `retry_held_payout(org1, st5)` → **`pending_approval`, hold cleared** (10m's predicate is the four open states only, 093:2130); `get_payout_execution_context` → `dispute_open:false`, `unbooked_refund_exposure_minor:0` (095 counts refunds only). Next close st6 → `chargeback/-5000`, net -5000, `organization_obligation settlement_shortfall 5000 outstanding`. **po5 (5000, the very order charged back) remains payable while a 5000 debt is booked against the same org.**

### 2.7 Terminal set, resolution, 'lost' effects, deletion (item 6)
- CHECK (088:199-201) = Stripe set minus `prevented` plus `charge_refunded`. Stripe's live enum (fetched): `…, won, lost, prevented`. A `prevented` dispute → `invalid_input: prevented is not a dispute status` from BOTH writers; `charge_refunded` is a dead value no current Stripe object emits (unverified whether legacy API versions still emit it; the platform's pinned API version was not inspected).
- Resolution quadruple: writable only by table owner; `resolve_dispute_native` raises `dual_control_unavailable` before any write (verified as `platform_admin` after `won`). No verb, trigger or seam writes `resolution_*` today.
- `lost` / `won` (S7, W): status only. Atoms stay `dispute_hold` (door `admissible=false`, `transfer_ticket_ownership` → `conflict_locked (resale_state=dispute_hold)`, `unlock_ticket` noop). No atom is voided, no `kernel.refund` is created, `venue.order` stays `paid`, `payments.status` stays `succeeded`. **A WON dispute leaves the buyer's tickets inadmissible forever** with no release path (resolve parked, unlock noop).
- Deletion: BP-7 (088:483-490) blocks only while OPEN; `deletion_blockers_money` (093:1529-1616) has no dispute predicate. After `lost` the buyer is blocked only by BP-12 (post-event hold) → an account that lost a chargeback with tickets still `dispute_hold` can be tombstoned once BP-12 elapses (atoms then hang off an erased identity; not executed further).
- Legacy webhook today (`index.ts:1069-1080`): `charge.dispute.closed lost` sets `payments.status='refunded'` by `public.disputes.payment_id` — and `dispute.created` finds a native PI in `public.payments` (`index.ts:969-975`) and upserts `public.disputes` for it. So in production a native dispute is recorded on the LEGACY table and, on loss, flips the native payment to `refunded` with no `kernel.refund`, no chargeback line, no freeze. (Routing is KH's remit; noted here because it is the current writer of record.)

---

## 3. Findings (ranked)

**P0-1 — Lost dispute never nets against the pending payout of the same order; venue gets paid AND owes.** Evidence §2.6 (po5 `hold=none`, st6 `chargeback/-5000`, obligation 5000) and §2.3 S4 (lost-first: po1 20000 stays `pending/none` while st3 books -15000). Cause: (a) record freezes only when `v_open` (088:804-806); (b) 10m's predicate is open-only (093:2130); (c) the chargeback arm has no scope predicate and lands in the NEXT close (088:311-316, 093:1185); (d) 095's `settlement_unbooked_refund_exposure` reads `kernel.refund` only. G5 says obligation is the durable record of post-payout debt — here the debt is manufactured pre-payout from a fact the gate already holds.

**P0-2 — `prevented` is unrecordable; `charge_refunded` is dead.** 088:199-201 vs Stripe enum. Once the webhook is wired, a `prevented` event → `invalid_input` → retry loop / dead-letter. The CHECK is in an immutable migration; only a new migration can widen it.

**P1-1 — Legacy→native leak at the writer.** `record_dispute_native` accepts any `payments` row by PI (088:789-792): `buy_now`/`auction` (A2) and `pending` (A3) rows. Consequences: a `dispute_native` row on a legacy payment, BP-7 blocking a legacy buyer, and `refund-execute`'s `disputed_minor` (093:1061) counting it. Rail dispatch exists only in TS (`native.ts:115-132`), not in the DB.

**P1-2 — WON leaves tickets inadmissible forever; `release_payout` is the only money exit and it is not dispute-aware.** §2.7 W and §2.5 F6. `unlock_ticket` re-arms on any open dispute and noops on `dispute_hold`; nothing consumes `won`/`warning_closed`. Conversely `platform_risk` can release a `dispute` hold while the dispute is still open (085:827).

**P1-3 — Dispute before finalize: atoms minted unfrozen.** §2.6 N1. `finalize_primary_order` probes refunds only (085:1936-1938); the R-40 overlay is applied only at record time. A buyer can dispute, receive tickets, list/transfer them; only a later lock/unlock re-arms.

**P1-4 — Freeze on a `submitted` payout strands Stripe's outcome.** F1/F2b: `mark_payout_transfer_state('paid')` refuses `payout_held` (085:1690-1692) for a transfer that has already left. 095's `hold_payout_transfer_reversed` handles reversal, not the paid-while-held case (unverified whether payout-execute retries or dead-letters this).

**P2-1 — Currency mismatch is silently unbooked forever** (A4; 093:1188), no alert, no `unlined_reversal` obligation (094's `unlined_reversal` origin is INERT, 094:120-127).

**P2-2 — `mark_dispute_state.p_command_key` unbounded** (A8b): NULL accepted, 209-char junk lands in immutable `admin_audit.reason_code`; record enforces `^[A-Za-z0-9._:-]{1,64}$` (088:772-774).

**P2-3 — Empty-string refs/reason accepted** (A12); `stripe_charge_ref` is stored but never used for lookup, so a NULL-PI dispute (Stripe allows) is unrecordable (A11).

**P2-4 — Payout leg predicate mismatch with its comment**: promoter commission payouts (`cause_ref = attribution.id`, 090:1485) are unreachable (dark today). `atoms_skipped` reason `overlay_occupied` is emitted for state skips (F5).

**P2-5 — No forward-only guard on `dispute_native` at the table level** (R7): owner/definer code can regress a terminal status; today only `mark_dispute_state` enforces it. Acceptable under PFA-21 (service_role has no DML), recorded for completeness.

**P2-6 — Replay ignores drift** (A5): a second `created` with a different amount/charge is `noop_replay` with no audit of the discrepancy.

**OK / verified working:** payout leg for primary orders fires (cause_ref = order_id matches); cross-venue isolation of the freeze holds; face-value cap on chargebacks (incl. fee-inclusive and over-face amounts) holds; cumulative cap across multiple disputes per order holds; terminal absorbing state machine holds; role gates match 088:1859-1860 and PFA-21; service_role cannot touch tables; resolution quadruple is unwritable by any verb; BP-7 works while open.

---

## 4. Options (enumerated; the orchestrator decides)

### For P0-1 (lost dispute vs pending payout of the same order)
- **O1 (smallest honest):** new migration re-creating `kernel.settlement_payout_maturity` (10m) so the covered-payment predicate also holds on `lost`/`charge_refunded` disputes whose `dispute_id` has NO `chargeback` line in a closed settlement with `net_minor >= 0` — i.e. "adverse and unabsorbed" — emitting a new maturity code (e.g. `dispute_unabsorbed`) added to `kernel.settlement_maturity_hold_codes()` (095:459-483) and its pgTAP source-pin. Mirrors what 095 already does for refunds. Trade-off: the payout stays held until an org settlement that nets ≥ 0 absorbs the line — for a single-order venue that may be never, so it needs a release story (O3) or it is an honest permanent hold.
- **O2:** extend `kernel.settlement_unbooked_refund_exposure` (095) to add lost-dispute exposure (face-capped) → `refund_exposure_stale` refusal at execution (10n) and `pending_approval` still granted. Trade-off: gate fires only at execution, later than O1.
- **O3:** make `record_dispute_native` freeze on terminal-first too (drop `v_open` from the payout leg only; keep atom leg open-only). Trade-off: changes an 088 body (new migration, body-only); still leaves the P0-1 case where the hold was `dispute_open` and cleared by retry — O1 is still needed.
- **Dishonest:** netting the chargeback into the same order's pending payout by mutating `kernel.payout.amount_minor` (violates append-only settlement facts and 093 C7); cross-venue netting inside the org (G5 forbids).

### For P0-2 (status set)
- **O4 (smallest honest):** new migration: `alter table kernel.dispute_native drop constraint …status_check; add check (… 'prevented')` keeping `charge_refunded` for history; update both writers' inline lists (body-only re-create), 10m's open list (093:2130 — `prevented` is terminal, favourable), BP-7 (088:487), `unlock_ticket` (088:576), `dispute_native_open_idx` predicate (088:215-216). Treat `prevented` like `warning_closed`. Trade-off: touches six sites; the partial index must be re-created.
- **O5:** map `prevented` → `warning_closed` in the webhook. Dishonest: the ledger would record a status Stripe did not send.

### For P1-1 (legacy leak)
- **O6 (smallest honest):** body-only re-create of `record_dispute_native` adding `if v_pay.mode <> 'native_primary' then raise exception 'precondition_failed: not_native_rail'` (and optionally `status = 'succeeded'`). Trade-off: a native-resale (`market_sale`) payment would also be refused — today those are legacy-shaped `buy_now` rows (153 fixture), so the sale arm must be exempted by `exists payment_native.sale_id` or the rail decided per KH. Needs KH's routing answer first.
- **O7:** leave DB permissive, rely on TS `resolveRail`. Dishonest under "shipped bytes beat prose": the DB is the writer of record.

### For P1-2 (WON release)
- **O8 (smallest honest):** a new service_role verb `kernel.release_dispute_native(p_stripe_dispute_ref, p_command_key)` callable only when status ∈ {won, warning_closed, prevented}: atoms `dispute_hold → none` (only where no other open dispute binds — reuse 088:576-588 predicate), payouts `held/dispute → none` via the existing hold semantics, audited. Does NOT write the resolution quadruple (PFA-31 park untouched). Trade-off: bypasses the dual-control design for the favourable outcome only; owner must accept that "Stripe said won" is sufficient authority for release. Alternative **O9:** wait for DISPUTE_DUAL_CONTROL un-park — honest but leaves winners' tickets dead indefinitely.
- Also: scope `release_payout` so a `dispute` hold with an OPEN dispute cannot be released by `platform_risk` alone (or record it as intended). Cheap body-only change.

### For P1-3 (dispute before finalize)
- **O10 (smallest honest):** in a body-only re-create of `finalize_primary_order`, after the mint, apply `dispute_hold` to the freshly minted atoms when an open `dispute_native` row references `p_payment_id` (same predicate as the record atom leg). Trade-off: touches the money path; alternative is refusing finalize (worse — money already taken, tickets owed).

### For P1-4
- **O11:** allow `mark_payout_transfer_state('paid'|'failed')` when `hold_reason_code='dispute'` and `status='submitted'` (the hold then survives on a `paid` row as a flag, and 094 obligation is the recovery). Or **O12:** have the payout leg skip `submitted` payouts and instead record an obligation candidate. Both change 085 bodies; needs H8/J5 executor owner input.

### For P2s
- Bound `mark_dispute_state.p_command_key` with record's regex; refuse `''` refs/reason; alert (admin_audit `dispute.alert/currency_mismatch`) when `v_ccy <> v_pay.currency`-equivalent (payments has no currency column — compare against `venue.order.currency` via payment_native); audit amount drift on replay. All body-only.

---

## 5. Open questions for orchestrator / owner
1. Is "Stripe reported `won`" sufficient authority to release atoms and payouts (O8), or must every release wait for DISPUTE_DUAL_CONTROL? Today a winning venue's buyer cannot enter the door.
2. For P0-1, is a permanent hold on a settlement payout until an absorbing close acceptable, or does the owner prefer an explicit venue-scoped obligation minted at `lost` time (would make 094's `unlined_reversal` origin live) with the payout released? The latter moves money out and books debt — G5 says no default cross-venue netting, but this is same-venue.
3. Which Stripe API version is pinned in the edge functions (determines whether `charge_refunded` can still arrive; `prevented` exists in current versions)? Unverified here.
4. KH: when the webhook is wired, will native-resale (`market_sale`) payments carry `mode='native_primary'`-style rail metadata, or stay `buy_now`-shaped? O6's mode guard depends on it.
5. Should `record_dispute_native` accept a NULL PI by resolving `stripe_charge_ref` (needs a charge ref on `public.payments` — none exists today)?
6. Executor behaviour on `payout_held` for an already-sent transfer (P1-4): retry, dead-letter, or manual? Not executed here (TS).
