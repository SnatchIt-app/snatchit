# THE DELETION STATE MACHINE — `ODR-16` implementation specification (design-only)

**Drafted 2026-08-29 (Agent B, read-only pass) against `/Users/josetascon/snatchit-consol` @ the OR-13
signature.** Basis: ratification record **OR-13** (`_governance/PHASE_2_RATIFICATION_RECORD.md:584`) — the
complete `ODR-16` family ruling: **16a tombstone-terminal · 16b Option B (PENDING DELETION) · the six 16c
money answers · the ten-plus 16d answers.** The ruled model is the reframed brief's model B
(`_governance/ODR16_FINAL_REFRAMED_OWNER_BRIEF.md:29–114`), grounded predicate-by-predicate in the 57-row
inventory (`_governance/ODR16_TRANSITIVE_DELETION_INVENTORY.md`).

**This document contains NO implementation SQL.** Every test below is a specification of a condition over
named tables and columns, in the corpus's own concepts-not-DDL convention (schema spec header,
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3–5`). Where the corpus does not pin a physical operand, the gap
is named **OPEN** — nothing is filled by invention.

**Citation key.** `INV` = `_governance/ODR16_TRANSITIVE_DELETION_INVENTORY.md` · `BRIEF-B` =
`_governance/ODR16_FINAL_REFRAMED_OWNER_BRIEF.md` · `BRIEF-A` = `_governance/ODR16_FINAL_OWNER_BRIEF.md` ·
`PACKET` = `_governance/ODR16_RULING_PACKET.md` · `RATREC` = `_governance/PHASE_2_RATIFICATION_RECORD.md` ·
`SCHEMA` = `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` · `RPC` = `PHASE_2_RPC_FUNCTION_CONTRACTS.md` ·
`WALLET` = `PHASE_2_APPLE_WALLET_SPEC.md` · `PLAN` = `PHASE_2_SUPABASE_MIGRATION_PLAN.md` · `DEMOG` =
`PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` · `MAP4` = `_governance/ODR4_SPLIT_CONSEQUENCE_MAP.md` · `PR28` =
`/Users/josetascon/snatchit-fix/supabase/functions/delete-account/index.ts` · `MIG` = live
`supabase/migrations/`. All doc paths relative to `docs/architecture/`.

---

## 0. The substrate (ruled with 16b; restated once)

The state lives in **three columns on `kernel.identity_ext`** — `deletion_state`,
`deletion_requested_at`, `deletion_block_reason` — plus a partial index over open requests and **one sweep
on the existing 2-minute production heartbeat** (BRIEF-B B3 :58–66; BRIEF-A §5 :130–141). Not a new table:
a queue table must choose RESTRICT (a third cliff blocking the deletion it schedules) or CASCADE (deleting
the record of the request in the statement that completes it) (BRIEF-A :134). The sweep is idempotent and
re-evaluates the full predicate set from scratch on every pass (BRIEF-B B4 :71–72); it is also **the only
object in the design that can detect a half-completed deletion** (BRIEF-B B3 :65–66, B5 :78–81) — the
non-transactional-deletion defect is a standing OR-2 blocker (MAP4 :1086; RATREC :573) and the sweep is
its detector, not its fix.

`kernel.identity_ext` is **lazily created per-identity on first write** (PLAN :264–266, :559). A deletion
request from an identity with no `identity_ext` row **is** such a first write: accepting the request
creates the row. (Whether `identity_ext` ever becomes total is a separate, still-unrecorded ride-along —
§6 OPEN-8.)

**State values.** OR-13 names `DELETION_PENDING` verbatim (RATREC :584). The three machine states are
ACTIVE · DELETION_PENDING · ERASED/TOMBSTONED; the exact stored literals of `deletion_state` are an
engineering cell (§4.3 — the corpus pins the states, not the strings).

---

## 1. THE STATES

### 1.1 ACTIVE

- **ENTRY CONDITION.** Default at account creation (`deletion_state` absent-or-default; an identity with
  no `identity_ext` row is ACTIVE by definition — PLAN :264). Re-entered from DELETION_PENDING when the
  user **withdraws** the request (BRIEF-B B4 :73 — "the user may withdraw while pending").
- **ALLOWED ACTIONS.** Everything the role model allows. No deletion-related restriction exists.
- **FORBIDDEN ACTIONS.** None beyond the ordinary permission model.
- **TICKET SCANNING.** Normal (`venue.record_scan`, RPC :1359).
- **NEW PURCHASE/CUSTODY.** Normal.
- **PAYOUT PROCESSING.** Normal.
- **DISPUTE PROCESSING.** Normal.
- **EXIT CONDITION.** The identity submits a deletion request and it is **ACCEPTED — always.** 16b:
  *"deletion requests are ACCEPTED into `DELETION_PENDING`"* (RATREC :584). There is **no request-time
  refusal in the ruled machine**: PR #28's request-time 409s (active transfers, PR28 :188–192; resolved
  disputes, PR28 :212–216) are replaced by pending-state blocking predicates (§2) and by the 16d lift of
  the `dispute_resolutions.actor_id` refusal (RATREC :584; PACKET :37–38). Acceptance is the transition;
  its side effects are §3.

### 1.2 DELETION_PENDING

- **ENTRY CONDITION.** A deletion request accepted from ACTIVE. Entry writes
  `deletion_state := DELETION_PENDING`, `deletion_requested_at := now()`, and the operator-legible
  `deletion_block_reason` from the first failing predicate of §2 (BRIEF-B B3 :60–62; SCHEMA §5.1 form (b)
  :3612 — refusal-with-named-reason is the ancestor of this field). Entry side effects: §3.
- **ALLOWED ACTIONS.**
  - **Sign-in and full account use.** *"The account must remain usable while pending — a user blocked by
    a ticket four months out must not be locked out of that ticket"* (BRIEF-B B4 :74–76).
  - **Everything that DISPOSES of custody or resolves an obligation** (the freeze is on acquisition, not
    disposal — the acquisition-freeze/disposal distinction is what makes the wait bounded, BRIEF-A :169):
    transferring out (`kernel.transfer_ticket_ownership` RPC :1067 via sale; `market.create_p2p_transfer`
    RPC :1225 as sender), listing for sale (`market.list*` — `listing_native.seller_id` is disposal-side;
    live-rail listing creation likewise), accepting an offer as seller (`market.respond_offer`, SCHEMA
    :3428), cancelling own listings/offers/transfers, requesting a refund of an own order
    (`kernel.request_order_refund`, RPC :2286 — money processing is preserved, RATREC :584), withdrawing
    contact consents (`kernel.withdraw_org_contact_consent`, RPC :3420), clearing demographics
    (`kernel.clear_my_demographics`, RPC :3265), transferring org ownership out (§2 BP-11's clearing
    path: `kernel.change_org_role` / `remove_org_member`, RPC :746/:763).
  - **Withdrawing the deletion request** (BRIEF-B B4 :73). The cancel path must be reachable and
    authenticated (BRIEF-A :140–141).
- **FORBIDDEN ACTIONS.** The acquisition-freeze surface, enumerated in §3.2. Summary: no new custody in,
  no new purchase obligations, no new role/commercial obligations.
- **TICKET SCANNING.** **Existing tickets STILL SCAN** — ruled verbatim (RATREC :584; BRIEF-B B7 :111
  flagged it for explicit ruling and OR-13 gave it). `venue.record_scan` and the offline reconciliation
  path treat a pending-deletion holder identically to any holder. Scanning is also a *clearing event*
  (it moves the atom to terminal `scanned`, draining BP-1).
- **NEW PURCHASE/CUSTODY.** **FROZEN** (RATREC :584: *"acquisition of new custody/obligations FROZEN"*).
  See §3.2 for the per-RPC refusal list. Without the freeze the wait is unbounded by the user's own
  action (BRIEF-A :169).
- **PAYOUT PROCESSING.** **Preserved.** Payable payouts to the identity are processed and PAID (16c Q6:
  *"PAY if payable else HOLD — never silent forfeiture"*, RATREC :584). Held/probation payouts follow the
  normal `hold_state` machine (`kernel.hold_payout`/`release_payout`, RPC :1748–:1779) — resolution is a
  platform act, and completion blocks on it (BP-6). Nothing is forfeited because the payee asked to
  leave.
- **DISPUTE PROCESSING.** **Preserved** (RATREC :584: *"money/dispute processing preserved"*). Open
  disputes proceed normally; the identity can submit evidence, be found for or against, be refunded or
  reversed. An open dispute blocks completion (BP-7), it does not block the pending state.
- **EXIT CONDITION.** Two exits:
  1. **→ ACTIVE**: user withdrawal (above).
  2. **→ ERASED/TOMBSTONED**: the heartbeat sweep finds **every predicate in §2 false** and executes the
     terminal entry effects (§4). Resolution is *"event, scan, or settlement — never the user"*
     (BRIEF-B B2 :51–56): ticket consumed/expired · pass superseded or expired · marketplace sale settled
     or cancelled · payout paid or reversed · refund window closed · transfer terminal · dispute closed ·
     org ownership transferred. **Nothing is silently discarded on the way** (RATREC :584).

### 1.3 ERASED / TOMBSTONED (terminal)

- **ENTRY CONDITION.** From DELETION_PENDING only, when the closed-world predicate set (§2) is entirely
  false at a sweep evaluation. Entry effects: §4. 16a: *"`auth.users` is NOT physically deleted in
  Phase 2 — retained and marked erased; physical destruction is Gate-L"* (RATREC :584; SCHEMA §5.1 form
  (a) :3607–3610). The `auth.users` DELETE is **never executed** — which is also why the two
  append-only-CASCADE aborts (INV :41–58) and the RESTRICT walls (BRIEF-B B6 :83–104) are never reached:
  the terminal step under the ruling is an UPDATE-class act, not a DELETE.
- **ALLOWED ACTIONS (by the platform / by the world — the person can no longer act).**
  - **Later chargebacks land against the tombstone** — 16c Q2: *"ALLOW later chargebacks against the
    tombstone (no waiting window)"* (RATREC :584; PACKET :24–25). The retained `public.payments` /
    `public.transfers` / `kernel` money rows resolve chargeback processing exactly as for a live account.
  - Dispute adjudication over retained rows; audit reads; settlement and financial-retention reads;
    CRM-export exclusion logic (tombstoned identities are excluded the way sentinels are — S-20 class,
    SCHEMA :2030–2034; exact exclusion rule OPEN-6).
- **FORBIDDEN ACTIONS.** Sign-in and every authenticated act (credential revocation: §4.2 — mechanism
  OPEN). All acquisition. **Un-erasing:** the state is terminal; there is no exit to ACTIVE. Any
  repointing of custody columns — permanently, `CUSTODY-DEL-1` (SCHEMA :3601–3611).
- **TICKET SCANNING.** **Vacuous by construction.** At entry BP-1 guarantees the identity owns zero
  non-terminal atoms and BP-2 guarantees zero `issued` wallet passes; a terminal atom can be neither
  transferred, listed, locked nor scanned (SCHEMA :1957–1959). The BRIEF-A Q8 hazard (a deleted account
  keeping a working `.pkpass` door credential, :80) is closed by ordering, not by revocation: the pass
  predicates cleared before entry.
- **NEW PURCHASE/CUSTODY.** None — the identity cannot authenticate and every acquisition RPC refuses.
- **PAYOUT PROCESSING.** **None outstanding at entry** (BP-5/BP-6 cleared: every identity payout reached
  `paid`/`failed`/`reversed` with `hold_state='none'`). Q6 guarantees the terminal ledger contains no
  forfeiture. Retained payout rows are immutable ledger (SCHEMA :869–871).
- **DISPUTE PROCESSING.** Q2 chargebacks (above). `dispute_resolutions.actor_id` rows RETAINED (16d,
  RATREC :584); `venue.attribution_review.decided_by` retained-tombstoned (INV #38 :203). The append-only
  adjudication ledgers keep the erased uuid as a dereferenceable-but-meaningless identifier — the honest
  description is *"we keep an opaque identifier, and nothing else"* (SCHEMA :3610).
- **EXIT CONDITION.** **None in Phase 2.** Physical destruction of the `auth.users` row and the
  crypto-shred (C34/C15) are **Gate-L** (RATREC :584; DEMOG §8.5 :869–875). The tombstone reaper for
  `kernel.identity_demographic_erasure` and the `ODR-4a` class amendment it needs are likewise Gate-L
  residuals (PACKET :46–47; MAP4 :1085).

---

## 2. THE CLOSED-WORLD BLOCKING PREDICATE SET

**This list is CLOSED.** DELETION_PENDING terminates into the tombstone **when and only when every
predicate below is false** (16b, RATREC :584: *"the enumerated closed-world blocking predicates"*). The
sweep evaluates them in order and records the first true one in `deletion_block_reason`. Derivation
discipline: every predicate traces to the inventory's disposition column (BRIEF-B B1 :32–35 — *"derived
from the inventory's disposition column, not invented"*) plus the 16c/16d rulings; §2.1 proves closure
against all 57 rows.

Notation: `:id` is the deleting identity. Tests are conditions, not SQL.

| # | Name | Exact table/column test | Clearing event | Ruling authority |
|---|---|---|---|---|
| **BP-1** | **LIVE CUSTODY** | any `kernel.tickets` row with `current_owner_id = :id` **and** `state ∈ {issued, active}` (the non-terminal half of the enum `issued·active·scanned·voided·expired`, SCHEMA :462, :512) | atom scanned (`kernel.mark_ticket_scanned`, RPC :1164) · voided to `SN-VOID` (`kernel.void_ticket_atom`, RPC :1106; SCHEMA §1.16 :1997–2002) · expired (`kernel.sweep_expired_ticket_atoms`, RPC :1992) · transferred out (`kernel.transfer_ticket_ownership`, RPC :1067 / `market.accept_p2p_transfer`, RPC :1237) | 16b (RATREC :584) · INV #13 :178 (BLOCK; `CUSTODY-DEL-1` forbids repointing, SCHEMA :3601) · BRIEF-B B1 :40 |
| **BP-2** | **LIVE WALLET PASS** | any `kernel.wallet_pass` row with `holder_identity_id = :id` **and** `status = 'issued'` (the partial-unique live generation, SCHEMA :4162; WALLET :1296) | superseded on transfer (`kernel.supersede_wallet_passes_for_atom`, WALLET :1297, :738) · reconciled to `consumed`/`invalidated`/`expired` by `kernel.sweep_wallet_pass_lifecycle` (WALLET :1306) | INV #19 :184 (BLOCK — *"the 'which artifact on which device when' evidence"*) · BRIEF-B B1 :41, B7 :110 |
| **BP-3** | **OPEN MARKET SALE** | any `market.market_sale` row with (`buyer_id = :id` or `seller_id = :id`) **and** `terminal_state = 'pending'` (enum `pending·completed·compensated`, SCHEMA :3479; compensate-XOR-complete C26, SCHEMA :651–654) | sale completes (custody transfer appends, `terminal_state := 'completed'`) or compensates (`market.sweep_paid_pending_sales` C25, RPC :1858; `terminal_state := 'compensated'`) | INV #41/#42 :206–207 (BLOCK) · BRIEF-B B1 :42, B2 :55 |
| **BP-4** | **OPEN P2P TRANSFER** | any `market.p2p_transfer` row with (`from_identity = :id` or `to_identity = :id`) **and** `status ∈ {initiated, accepted}` (non-terminal half of `initiated·accepted·completed·declined·expired·cancelled`, SCHEMA :3515) | accept-to-completion (RPC :1237) · decline/cancel (RPC :1253) · TTL expiry (`market.sweep_expired_p2p_transfers`, RPC :1845) | INV #43/#44 :208–209 (BLOCK) · BRIEF-B B1 :43, B7 :112 |
| **BP-5** | **UNSETTLED IDENTITY PAYOUT** | any `kernel.payout` row with `payee_identity_id = :id` **and** `status ∈ {pending, submitted}` (lifecycle enum SCHEMA :846–848; forward-only, :872–874) | payout reaches `paid` / `failed` / `reversed` via `kernel.mark_payout_transfer_state` (SCHEMA :863–864, §1.9.2). Q6 direction: **payable ⇒ PAY** — the clearing event is payment, never forfeiture | 16c Q6 (RATREC :584; PACKET :27–28) · INV #20 :185 (BLOCK — *"money paid to a natural person"*) · BRIEF-B B1 :43 |
| **BP-6** | **PAYOUT HOLD / PROBATION** | any `kernel.payout` row with `payee_identity_id = :id` **and** `hold_state ∈ {held, probation_hold}` (orthogonal risk gate, SCHEMA :849–855). **Live-DB analog:** any `public.transfers` row with `seller_id = :id` and (`payout_review_status ∈ {held, manual_review}` or `payout_hold_until > now()`) (MIG `039_risk_based_payouts.sql:33–49`; the discipline `hold_state` reproduces, SCHEMA :852–855) | `kernel.release_payout` restores `hold_state='none'` (RPC :1767–:1779; platform_risk/platform_admin only) · live: review resolution / hold lapse | 16c Q3 (RATREC :584: *"BLOCK on unresolved payout hold/probation"*; PACKET :25–26) |
| **BP-7** | **OPEN OR DISPUTED TRANSFER (live rail)** | any `public.transfers` row `t` with (`t.seller_id = :id` or `t.buyer_id = :id`) **and** ( `t.status ∈ {pending, seller_sent, disputed}` **or** (`t.status = 'expired'` and an open `public.disputes` row exists with `transfer_id = t.id` and `status ∉ {won, lost, warning_closed, charge_refunded}` — the live open-dispute set, MIG `024_disputes.sql:34–35`) ). Status enum: MIG `002_transfers.sql:55–62` extended by `024_disputes.sql:59–70` | buyer confirms / auto-release / clean expiry / reversal (terminal statuses `buyer_confirmed·auto_released·expired·reversed`); dispute closes into the terminal Stripe set | 16c Q1 (RATREC :584: *"BLOCK on open/expired-in-dispute transfers"*) + 16d rider *"expired/disputed transfers join the completion blockers"* (RATREC :584). Supersedes the deliberate live gap — `disputed`/`expired` are NOT in PR #28's block list (PR28 :181; BRIEF-B B7 :112; BRIEF-A :189) — and absorbs PR #28's `pending`/`seller_sent` request-time 409 (PR28 :177–192) as a pending-state predicate |
| **BP-8** | **IN-FLIGHT RESERVATION (live rail)** | any `public.listings` row with `reserved_by = :id` (a live buy-now reservation racing a webhook); NATIVE TWIN (R-37/`OR-22`): any `market.market_sale` row with `buyer_id = :id AND sale_state IN ('initiated','paid_pending_transfer')` | payment lands (`mark_listing_sold`) or the reservation is released/expires | INV A#4 :78 + §A.3 :106–111 (*"refusing deletion while a live reservation is held … belongs to 16b"*) · BRIEF-B B1 :44–45 |
| **BP-9** | **WON-UNSETTLED AUCTION (live rail)** | any `public.listings` row with `winner_user_id = :id` whose sale has not settled (no completed payment/transfer for the win); **and, transitively,** any live auction on which `highest_bidder_id = :id` — which self-resolves at auction end into either this predicate or nothing, and cannot be re-entered because bidding is frozen (§3.2) | the won sale settles (payment + transfer complete → BP-7 machinery) or the auction resolves away from `:id` | INV #6 :80 + §A.4 :113–115 (*"a deleted user's won-but-unsettled auction … belongs to 16b"*) · the no-silent-discard clause of 16b (RATREC :584) forbids resolving it by deleting the win |
| **BP-10** | **NEGATIVE SETTLEMENT OBLIGATION** | **Ruled BLOCK — operand PINNED (`OR-21`, F-P2-1/F-P2-2, 2026-08-29):** any `kernel.identity_obligation` row with `debtor_identity_id = :id` **and** `status = 'outstanding'` (schema §1.10a; read via `kernel.has_outstanding_obligations(:id)` — SEAM-2 stub `false` until `085`, which is true-not-inert: no origin object exists earlier). The former candidate enumeration — (a) lost dispute, (b) negative org settlement, (c) additive record — is resolved: the owner ruled the additive record; the org-settlement arm stays excluded (org debt is BP-11's org's, C31 Gate-M); the lost-dispute fact becomes an `origin_kind='chargeback'` obligation row, not a separate probe | obligation resolved: `kernel.resolve_identity_obligation` → `recovered` or `written_off` (a platform act — the BP-6 shape) · 16c Q4 (RATREC :584: *"BLOCK on negative settlement obligation"*; PACKET :26) · `OR-21` |
| **BP-11** | **SOLE `org_owner`** | any `kernel.org_member` row `m` with `m.identity_id = :id` and `m.role = 'org_owner'` for which **no other** `org_member` row of the same `org_id` carries `role = 'org_owner'` (the ≥1-`org_owner` invariant, SCHEMA :313; enforced in the role RPCs, RPC :751, :765, :4496, :4565) | ownership transferred: another member promoted to `org_owner` (`kernel.change_org_role`, RPC :746) and/or `:id` demoted/removed (`kernel.remove_org_member`, RPC :763) | 16d (RATREC :584: *"sole `org_owner` REFUSE COMPLETION until transfer"*; PACKET :30–31) · INV #3 :168 |
| **BP-12** | **OPEN ORDER / LIVE REFUND PATH** | any `venue.order` row with `buyer_id = :id` **and** ( `status = 'pending'` (unpaid checkout — enum `pending·paid·partially_refunded·refunded·cancelled`, SCHEMA :2538) **or** an in-flight refund against it: a `kernel.refund` row for the order with `status ∈ {pending, submitted}` (SCHEMA :1050) **or** `status = 'paid'` still inside the refund window (config-keyed, `refund.*` namespace — MONEY §7.2, `PHASE_2_MONEY_AUTHORITY_SPEC.md:241`; exact key: §6 OPEN-2) ) | order reaches terminal; refunds reach `succeeded`/`failed`; the refund window closes (BRIEF-B B2 :55: *"refund window closed"*) | INV #27 :192 (BLOCK — *"the refund path resolves through it"*) · BRIEF-B B1 :43, B7 :114 |

**What is deliberately NOT a predicate.**

- **Pending `kernel.approval_request` rows naming the deleter** — handled at DELETION_PENDING **entry**
  by Q5 auto-expiry (§3.1), never by blocking (16c Q5, RATREC :584).
- **The append-only ledgers** — `kernel.ticket_ownership_log.{from,to,actor}_identity` (INV #14–16
  :179–181), `kernel.admin_audit.actor_identity` (INV #9 :174), `venue.scan.actor_identity_id` (INV #28
  :193), `venue.inventory_movement.actor_identity` (INV #25 :190), `venue.door_manifest.{opened,closed}_by`
  (INV #32/#33 :197–198), `kernel.door_freeze_override.{granted,revoked}_by` (INV #17/#18 :182–183),
  `kernel.payout.held_by` (INV #21 :186), `venue.attribution_review.decided_by` (INV #38 :203), and the
  live `public.dispute_resolutions.actor_id` (INV A#2 :76). Their inventory disposition is
  BLOCK-or-TOMBSTONE **against a physical DELETE**; under the ratified tombstone terminal no DELETE is
  ever issued, so their RESTRICT/AO walls are never evaluated. They are **retention classes** (§4.6), not
  predicates. This is the load-bearing consequence of 16a: it converts the un-clearable half of the
  57-row wall from "deletion never completes" into "rows are retained against the tombstone" (PACKET
  :13–16; MAP4 :369–375).
- **The two AO-CASCADE aborts** (`kernel.identity_contact_pref_event` / `org_contact_consent_event`, INV
  :41–58) — same reason: no cascade ever fires (MAP4 :371); the ledgers are 16d-RETAINED (§4.6). The
  documentary reconciliation of the CASCADE-vs-AO contradiction remains a pre-`077` authoring residual
  (PACKET :44–45) but no longer gates this machine.

### 2.1 Closure proof-sketch against the 57-row inventory

Every one of the 57 blocking columns (13 live, INV :73–87; 44 designed, INV :164–209) maps to exactly one
of four classes, with no remainder:

1. **Predicate** (blocks tombstone entry): INV #13→BP-1 · #19→BP-2 · #20→BP-5/BP-6 · #27→BP-12 ·
   #41/#42→BP-3 · #43/#44→BP-4 · #3→BP-11 · live A#1(bids, transitively)/A#4/A#6 →BP-9/BP-8 · live
   transfers→BP-7. Q4's ruled predicate BP-10 is pinned to `kernel.identity_obligation` (OPEN-1 CLOSED — `OR-21`).
2. **Entry side effect** (§3.1): INV #10/#11 (`approval_request.{requested_by,approved_by}` :175–176) →
   Q5 auto-expiry · INV #5/#6 (`org_invite` :170–171) → pending invites naming/authored-by the deleter
   lapse or are cleaned.
3. **Retention class** (§4.6): every AO/audit/adjudication column above, plus the 16d-retained set —
   `organization.payout_destination_set_by` (INV #2 :167) · consent/pref event ledgers (INV #12/#22
   :177/:187) · `export_job.requested_by` normal lifecycle (INV #34 :199) · `venue.promoter.identity_id`
   row survives (INV #35 :200) · `promoter_code.created_by` (INV #37 :202) · sold `listing_native`/
   accepted `offer` rows (INV #39/#40 :204–205) · live `dispute_resolutions.actor_id` (INV A#2 :76) ·
   `seller_flags`/`seller_risk_scores` (INV A′.1 :133–138) · `user_blocks` (INV A′.1 :139–141). All per
   RATREC :584.
4. **Mechanical cleanup at terminal** (§4.5): the inventory's CLEANED rows — role grants, `SET NULL`
   links, TTL-bounded holds, never-sold listings/offers, live `public.*` clears (INV dispositions
   "CLEANED", :166–209 passim; :75–87).

The predicate set is therefore **closed over the inventory**: adding a predicate requires adding an
inventory row first.

---

## 3. DELETION_PENDING — the entry side-effect list

Executed at the ACTIVE → DELETION_PENDING transition. Each effect must be idempotent (the transition may
be retried; BRIEF-B B4 :71–72).

### 3.1 State + Q5 auto-expiry + invite lapse

1. **Write the pending state**: `kernel.identity_ext.deletion_state := DELETION_PENDING`,
   `deletion_requested_at := now()`, initial `deletion_block_reason` (§0; create the lazy `identity_ext`
   row if absent, PLAN :264). This is the **dated, durable record that the person asked** (BRIEF-A :138).
2. **Q5 — auto-expire pending approvals naming the deleter**: every `kernel.approval_request` row with
   `requested_by = :id` **and** `state = 'pending'` moves to `state := 'expired'` (a legal transition of
   the ratified machine `pending → approved|denied|cancelled|expired|stale`, SCHEMA :1389; the
   pending-only partial index exists, SCHEMA :1392). **Decided rows are immutable** — `approved`/`denied`
   rows are never touched (16c Q5, RATREC :584; PACKET :26–27). *Derivation note:* "naming the deleter"
   resolves to `requested_by` only — a pending row has `approved_by` NULL by CHECK (SCHEMA :1340), and
   `required_approver_class` names a class, not a person (SCHEMA :1291), so no other column can name an
   individual. Expiring a refund request is a user-visible reversion of a `refund_hold`; whether the
   buyer is notified is the standing N3-9th queue item (`_governance/OWNER_DECISION_QUEUE_2026_08_29.md`
   NEW QUEUE table) — §6 OPEN-5.
3. **Pending org invites**: invites **to** the identity (`org_invite.invitee_identity_id = :id`,
   `status='pending'`) become unacceptable under the freeze (§3.2 item F-6) and lapse by `expires_at`
   (enum `pending·accepted·declined·expired·revoked`, SCHEMA :408). Invites **sent by** the identity
   (`invited_by = :id`) follow their inventory disposition — pending ones are cleanable (INV #6 :171);
   whether they are revoked at entry or at terminal is an engineering ordering choice, not a ruling.
4. **Notification**: the user is told the request is pending **and why** (the current
   `deletion_block_reason`), and later told when it completes — a **mandatory notification type**,
   dependent on ODR-3's reduced Gate-P build / `OR-5` (BRIEF-B B4 :72–74). **Type key: `account_deletion_pending` (F-P1-2/`OR-17`, 2026-08-29); emitted by `kernel.request_account_deletion`, BEST-EFFORT per `OR-14` — the transition never aborts for the notice.**
5. **No suspension. No credential change. No data destruction.** Entry destroys nothing (16b:
   *"nothing is silently discarded"*, RATREC :584). PR #28's irreversible pre-terminal steps (cleanup
   RPC, storage wipe) do NOT run at entry — they have terminal-time analogues only (§4.5, §5).

### 3.2 The acquisition-freeze surface — which RPCs must refuse a pending-deletion caller

**The principle (ruled):** freeze the **acquisition of new custody and new obligations**; keep every
**disposal** path open, because disposal is what clears the predicates (RATREC :584; BRIEF-A :169:
*"nothing currently stops a pending-deletion user buying another ticket and resetting their own clock"*).
Each row below is derived from that principle against the RPC catalog; the refusal is a precondition
failure on `deletion_state = DELETION_PENDING` of the **caller** (error taxonomy per RPC §0.5).

**MUST REFUSE (acquisition):**

| # | Surface | RPC(s) | Why it is acquisition |
|---|---|---|---|
| F-1 | Primary checkout | `venue.reserve_primary_inventory` (RPC :885) · `venue.create_primary_checkout` (RPC :938) · `venue.finalize_primary_order` (RPC :990) | creates a `venue.order` with `buyer_id = :id` (new BP-12 matter) terminating in `kernel.issue_ticket_atoms` custody (new BP-1 matter) |
| F-2 | Resale purchase, native rail | the buyer-side purchase path that creates a `market.market_sale` with `buyer_id = :id` (§4.4 machine, SCHEMA :3462) | new BP-3 matter and, on completion, new custody |
| F-3 | Offers to buy | `market.make_offer` (SCHEMA :3428; `offer.buyer_id`, INV #40 :205) | a pending offer is a purchase obligation the seller can accept |
| F-4 | Custody in by gift/sale | `market.accept_p2p_transfer` **when `to_identity = :id`** (RPC :1237) | the accept IS the custody move in. (Refusing at accept is sufficient for the principle; additionally refusing `market.create_p2p_transfer` when the resolved recipient is pending-deletion is a kindness the corpus does not mandate — engineering choice) |
| F-5 | Live rail acquisition | bid placement (`public.bids.bidder_id`, INV A#1 :75) · buy-now reservation/purchase (`public.listings.reserved_by`, INV A#4 :78) · accepting/confirming an inbound transfer **initiated after** `deletion_requested_at` | resets BP-7/BP-8/BP-9 clocks; the exact live surface is the RN/edge purchase path (pre-cutover this machine does not run — §5) |
| F-6 | Role acquisition | `kernel.accept_org_invite` (RPC :731) · `kernel.create_organization` (RPC :670) | an accepted invite creates `org_member` obligations and can mint a new BP-11; `create_organization` makes the caller a **sole `org_owner` by construction** — an instant self-inflicted completion blocker |
| F-7 | Commercial enrollment | creating/binding a **new** `venue.promoter` row for `:id` (promoter onboarding, SCHEMA §3.17 :3160–3200) | the promoter row is a commission-entitlement key (INV #35 :200) — a new standing money obligation |

**MUST STAY ALLOWED (disposal / resolution)** — the §1.2 ALLOWED list, restated as the freeze's negative
space: transfer-out and send (`create_p2p_transfer` as sender; `transfer_ticket_ownership` via sale) ·
listing for sale and accepting offers as seller (`listing_native.seller_id` / `respond_offer` — selling
clears BP-1) · cancel/decline verbs everywhere · own-order refund requests (RPC :2286) · consent
withdrawal, demographics clearing, notification-pref writes · org ownership transfer (BP-11's clearing
path) · scanning (a venue-side act on the holder's ticket — the ruled still-scans property).

**Derived judgment call, flagged rather than silently decided:** `kernel.mint_wallet_pass` (WALLET :1296)
on an atom already owned. It creates a new BP-2-class row, but it is a credential **for existing custody**
— the instrument of the ruled still-scans property — and it self-clears with the atom's lifecycle.
Reading the freeze as custody/obligation acquisition, minting is **ALLOWED**; the stricter reading
(refuse: it extends the blocking surface) is defensible. Not determined by the rulings → recorded as a
named engineering cell, default ALLOW (§6 OPEN-4).

---

## 4. ERASED/TOMBSTONED — the entry effects

Executed by the sweep in the pass that finds all of §2 false. Idempotent; re-runnable; the sweep is the
half-completion detector (§0).

### 4.1 The terminal state write
`kernel.identity_ext.deletion_state := <terminal value>`. The pending metadata
(`deletion_requested_at`) is retained — the durable record that the person asked (BRIEF-A :138).

### 4.2 What "marked erased" physically is — candidates, not an invention
The 16a text: *"retained and marked erased"* (RATREC :584); schema §5.1 form (a): *"a
`kernel.identity_ext` erasure marker"* (SCHEMA :3607–3608). The corpus **pins the location
(`kernel.identity_ext`) and does not pin the column**: BRIEF-A §3 :96–97 verifies the marker *"has no
column"* — `identity_ext`'s complete list is `identity_id, residency_region, kyc_ref, locale, created_at,
updated_at` (PLAN :534). Candidates the corpus supports:
- **(i)** the ruled B3 `deletion_state` column itself reaching a terminal `erased` value — the natural
  reading, since 16b was ruled on model B whose substrate is exactly these three columns (BRIEF-B B3);
- **(ii)** a separate `erased_at timestamptz` on `identity_ext` alongside `deletion_state`, mirroring the
  demographic tombstone's shape (`erased_at`, DEMOG :893).
**The choice of representation (i)/(i+ii) and the stored literals are the one remaining engineering cell
of the marker** (§6 OPEN-3). What is NOT open: the marker lives on `kernel.identity_ext`, the `auth.users`
row survives, and no column of any custody or ledger table changes (CUSTODY-DEL-1, SCHEMA :3601).

### 4.3 Credential revocation — OPEN mechanism
16a's ancestor text requires *"credentials are revoked … the person cannot sign in"* (SCHEMA :3608–3609),
and **no package writes `auth.users`** (BRIEF-A :98). The revocation mechanism (session/refresh-token
invalidation, sign-in ban keyed on the erased marker, or an `auth.users` write by an edge actor) is
**undetermined by the corpus** — as is the re-registration fork (*keep the email = a permanent silent ban
on that address; scramble it = freeing the only cross-account human key*, BRIEF-A :101). §6 OPEN-7. Note
the Wallet caveat is already closed by ordering, not by this mechanism (§1.3 TICKET SCANNING).

### 4.4 The demographic row and its tombstone trigger
**The trigger does NOT fire on this path by itself.** `tg_identity_demographic_erasure` is `BEFORE DELETE
FOR EACH ROW` on `kernel.identity_demographic` (RPC §17.20a :3385–:3419); under tombstone-terminal no
`auth.users` DELETE occurs, so no cascade reaches the table — *"it is `BEFORE DELETE` on a row that is
not deleted"* (MAP4 :386; BRIEF-A Q9 :82: under retention *"the gender answer"* survives). The corpus
provides the mechanism for removal — a **definer DELETE** of the row, which fires the trigger and writes
the value-free append-many erasure tombstone (RPC :3408: fires on *"any future definer delete"*; DEMOG
§8.2 :776–790) — but **the OR-13 ruling does not say whether tombstone entry performs that delete**. The
16d list retains the consent/pref **event ledgers** and is silent on the demographic **answer**. →
**OPEN-6a**: does ERASED entry hard-delete `kernel.identity_demographic` for `:id` (mechanism ready,
DEMOG-aligned) or retain it? Any later resolution inherits: the erasure-tombstone row
(`kernel.identity_demographic_erasure`) is FK-free by design and survives the account (DEMOG :783–787;
INV :211–216), governed by the unfilled D-6 `{N}` window (COUNSEL — PACKET :45–46).

### 4.5 Mechanical cleanup + the 16d hard-delete allowance
Per the inventory's CLEANED dispositions, executed at terminal (never at entry — §3.1.5):
- **Phase-2 kernel/venue role + ops clears**: role grants removed, `SET NULL`-class links cut, pending
  invites removed, TTL holds released (INV #1, #4–#8, #23/#24, #26, #29–#31, #36 dispositions :166–201).
- **Never-sold listings/offers hard-deleted; sold/completed RETAINED** (16d, RATREC :584; INV #39/#40
  :204–205 — *"cancelled is cleanable, sold is not"*). At entry time no `active` listing of `:id` can
  exist (BP-1 held while any owned atom was listed — `resale_state='listed'` keeps the atom live,
  SCHEMA :464), so the deletable set is exactly `status ∈ {draft, cancelled}` listings (SCHEMA :3378) and
  non-accepted offers (`status ∈ {declined, expired, withdrawn}`, SCHEMA :3421).
- **Live `public.*` clears** per the PR #28 cleanup semantics **minus every repointing the tombstone makes
  unnecessary**: under 16a the FK walls never fire, so sentinel-repointing (`delete_account_cleanup`'s
  whole purpose, SCHEMA :3569, :3576–3599) is no longer structurally required — what remains of it at
  cutover is a policy question folded into §5, with `CUSTODY-DEL-1` untouched either way.
- **Storage**: the PR #28 proof-document posture is **preserved** verbatim (RATREC :584) — transfer
  evidence referenced by a retained transfer row is kept for the life of that row; the deleter's other
  media (avatars, listing media, unreferenced proofs) is removed, recursively and verified (PR28 :218–271,
  :303–414). The ruling pins the *posture*; the tombstone-flow's exact storage step is engineering.

### 4.6 The retention classes, verbatim (16d — RATREC :584)
Retained against the tombstone, unmodified: `kernel.organization.payout_destination_set_by` (the SoD-1
operand — *"never nulled"*, PACKET :30–31) · the consent/pref **event ledgers**
(`kernel.identity_contact_pref_event`, `kernel.org_contact_consent_event`) · `venue.export_job.requested_by`
under its normal artifact lifecycle · the **`venue.promoter` row** (the commission-entitlement key;
accrued commissions per Q6/BP-5) · `venue.promoter_code.created_by` (*"codes outlive their issuer"*,
PACKET :34–35) · sold/completed listings and accepted offers · `public.dispute_resolutions.actor_id`
(RETAIN — **and the PR #28 "contact support" refusal lifts when this architecture ships**) ·
**`public.seller_flags` / `public.seller_risk_scores`** (*"deletion must not erase fraud history"* —
today's CASCADE erasure, INV A′.1 :133–138, becomes automatic retention under the tombstone; **interim
exposure until cutover**) · **`public.user_blocks`** (*"no block evasion by deletion"* — same mechanism,
same interim exposure, INV A′.1 :139–141) · every AO audit/adjudication ledger of §2's non-predicate
list. Terminal action beyond retained+erased: **NONE** (RATREC :584).

### 4.7 Completion notice
The user is told the deletion completed (BRIEF-B B4 :72–73; same OR-5/Gate-P dependency as §3.1.4). **Type key: `account_deletion_completed` (F-P1-2/`OR-17`); emitted by `kernel.sweep_deletion_pending`, BEST-EFFORT — a failed pass re-emits next tick, collapsed by dedupe.** Copy
constraint: Phase 2 **must not** say "permanently deleted"/"all associated data" — the erasure-language
prohibition pre-C34 binds this surface exactly as it binds DEMOG §8.5 (DEMOG :869–880; PR28 header
:23–34; BRIEF-A Q12 :88).

---

## 5. Interplay with the LIVE production path (PR #28) — the transition boundary

**PR #28's physical-delete flow remains the live behavior until this architecture ships.** Its shape:
request-time 409 on active transfers (`status ∈ {pending, seller_sent}`, PR28 :177–192) · request-time
409 on `dispute_resolutions.actor_id` (PR28 :202–216) · `delete_account_cleanup` sentinel repointing
(PR28 :281–292; migrations 019/020, SCHEMA :3576–3599) · verified storage deletion (PR28 :303–414) ·
`auth.admin.deleteUser` (PR28 :416–438).

**The hard boundary is package `077`.** From `077` the physical path's terminal step aborts for
effectively everyone — first at the AO-CASCADE trigger wall (`P0001` inside the referential cascade, INV
:39–58) and, past it, at the `identity_ext`/RESTRICT walls (INV :248–269; BRIEF-B B6 :83–104). Therefore:

1. **Pre-`077` (today):** PR #28 runs unchanged. The three 16d interim exposures stand and are accepted
   on the record: fraud-history CASCADE erasure, block removal by deletion, and deletable
   `disputed`/`expired` transfers (RATREC :584 — *"interim exposure until 16b ships"*; BRIEF-B B7 :112).
2. **Cutover — no later than the `077` apply, as part of the same release train:** the deletion request
   surface (edge + RN) switches from *execute-physical-delete* to *accept-into-DELETION_PENDING*. The
   PR #28 request-time refusals are retired: the transfer 409 becomes BP-7; the `dispute_resolutions`
   409 **lifts** (16d, RATREC :584) because the tombstone terminal never needs that column cleared.
   `auth.admin.deleteUser` is called by nothing. `delete_account_cleanup` is never extended to any
   `kernel.*` relation regardless (CUSTODY-DEL-1, SCHEMA :3601–3611; S-19, SCHEMA :4374).
3. **Consequence for `ODR-4b`:** with 16a ratified, the `auth.users` CASCADE posture is INERT and `4b`
   collapses to a documentation choice (OR-13 disposition column, RATREC :584; MAP4 :369–375). The
   pre-`077` documentary reconciliation of the CASCADE-vs-AO contradiction is half-done and re-blocks
   only a *physical-delete* ruling (PACKET :44–45).
4. **What does NOT ride the cutover:** Gate-L items (crypto-shred/C34, physical destruction, the
   `identity_demographic_erasure` reaper and its `ODR-4a` class amendment — PACKET :46–47), and the D-6
   `{N}` window (COUNSEL).

---

## 6. OPEN — determined by no ruling (do not implement by guess)

| # | Open item | Where it surfaced |
|---|---|---|
| ~~OPEN-1~~ | **CLOSED 2026-08-29 (`OR-21`)** — BP-10's operand is `kernel.identity_obligation.status='outstanding'` (schema §1.10a; F-P2-2 pinning applied; read predicate `kernel.has_outstanding_obligations`, SEAM-2 stub in `077` per `OR-17`, body `085`) | 16c Q4 |
| **OPEN-2** | **BP-12's refund-window key** — the window is config-keyed in the `refund.*` namespace (MONEY §7.2); the exact key/operand for "window closed" is not named | INV #27 · BRIEF-B B2 |
| **OPEN-3** | **The erased-marker representation** — location pinned (`kernel.identity_ext`), column/literals not (§4.2). The one remaining engineering cell of "marked erased" | 16a · BRIEF-A §3 |
| **OPEN-4** | **`mint_wallet_pass` under the freeze** — ALLOW (derived default) vs refuse (§3.2) | freeze principle |
| **OPEN-5** | **Notification for Q5 auto-expiry** — the N3-9th queue item (`cancel_refund_request` names no emitter) extends to entry-time auto-expiry | 16c Q5 · owner queue |
| **OPEN-6** | **Tombstone-side data-subject rows**: **(a)** whether ERASED entry hard-deletes `kernel.identity_demographic` (mechanism exists — definer delete fires §17.20a; ruling silent, §4.4); **(b)** whether entry auto-withdraws live org contact consents / flips the master pref (appending ledger events — ledger retention is ruled, current-state disposition is not); **(c)** the exact tombstone-exclusion rule for CRM export / fan-out / attendee projections (the S-20 sentinel-exclusion analog, SCHEMA :2030) | 16a/16d boundary |
| **OPEN-7** | **Credential-revocation mechanism + the re-registration fork** (keep vs scramble email) — no `auth.users` writer exists in any package (§4.3) | BRIEF-A §3 :98–101 |
| **OPEN-8** | **The two packet ride-alongs are NOT in the recorded OR-13 row**: `identity_ext` totality, and `SN-VOID`/`SN-SYSTEM` intended undeletability (PACKET :16–17 proposed them; RATREC :584 does not carry them). Treat as OPEN unless the record is amended | PACKET vs RATREC |
| **OPEN-9** | **Step-up re-authentication on the deletion request** — flagged live (no re-auth on an irreversible action, BRIEF-A :190) and doubly relevant now that the request writes a durable state; not ruled | BRIEF-A §9.5 |
| **OPEN-10** | **D-6 `{N}`** — the erasure-tombstone retention window; blocks fan-facing copy, not this machine (COUNSEL) | PACKET :45 |

---

*End of specification. No file under `docs/architecture/**` was modified; no SQL is contained or implied
as authored. The ratified content above is OR-13's; the derivations are labeled as derivations; the gaps
are labeled OPEN.*
