# `G-25` — The Canonical Event Catalog (the reconstruction of `C11`'s trim)

**Status:** RECONSTRUCTION FROM RATIFIED AUTHORITY. **Not an owner decision, not a design exercise.**
**Branch:** `docs/g25-event-catalog` off `phase2/consolidation` @ `269e473`.
**Closes:** `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `G-25` (`S2`) / §8.3 · owner-decision register `DF-23`.
**Blocks it was filed against:** `ODR-2` (*"Is the event outbox in Phase 2?"*) and, through `COND-D`, `ODR-3`.
`DF-23` reads: *"it corrupts the pricing of `ODR-2` … **Fix this before ruling on `ODR-2`.**"*

**This document creates nothing and changes nothing.** It does not amend `SNATCH_IT_DOMAIN_ARCHITECTURE.md`
§6.1, which still carries all 36 rows unmarked. It states, per event, what the ratified corpus already
determines — and, where the corpus determines nothing, says so in §6 rather than guessing.

**Two rules govern every line below.**

1. **No count appears without its enumeration beside it.** This corpus has been bitten by bare counts
   repeatedly — most recently `R3-2` (*"both numbers in the old heading were wrong, and neither was
   checkable"*), the edge-spec `verify_jwt=false` count, and the door-hook count corrected from three to four.
2. **Every classification is tagged `VERIFIED` (the authority was read at a cited location) or `INFERENCE`.
   No classification in §3–§5 rests on `INFERENCE` alone.** Anything that would have to is in §6.

---

## 1. What `C11` actually says

### 1.1 Where `C11` lives — and where it does *not*

**`C11` is not in `_governance/PHASE_2_RATIFICATION_RECORD.md`.** `VERIFIED:` that record's table opens at
`C26` (*"Phase 2 — Ratification Record (C26–C98 · O6–O16 · O-1…O-5 · D1–D21 · RET-1…RET-6)"*), and the only
occurrence of the string `C11` in it is inside the **`C42`** row, as a *pointer*: *"DA §0.5 (`C11` row)"*.
`C1`–`C11` are the **earlier** correction series, ratified by the prior adversarial review and folded into
the domain constitution's §0.5. The ratification record names that review as one of its own authorities.

The three places `C11` exists as text, in authority order:

| Where | What it is | Line |
|---|---|---|
| `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §0.5 | **the binding constitution text** — §0.5 is headed *"Post-review ratified corrections (BINDING — supersede any conflicting body text)"* | `:93` |
| `_superseded/PHASE_2_ARCHITECTURE_REVIEW.md` §17 (disagreement resolutions, item 5) | the **origin** — the resolution that produced `C11`, and the only place the *criterion* for the trim is written | `:73` |
| `SNATCH_IT_DOMAIN_ARCHITECTURE.md` Correction Index · `SNATCH_IT_CANONICAL_DATA_MODEL.md` §15 index | one-line index rows | DA `:2947` · CDM `:689` |

> **Index defect, noted not fixed (out of scope for this document).** DA `:2947` summarises `C11` as
> *"Scope corrections (seat hedge per C42; dual-control seams; **trimmed catalog**)"*. CDM `:689` summarises
> the same row as *"Scope corrections (seat hedge per C42; dual-control seams)"* — **the trim is missing from
> the CDM index row.** A reader auditing `C11` from the data constitution alone would not learn the catalog
> was cut. `VERIFIED:` both lines read directly.

### 1.2 The constitution text, quoted in full

`SNATCH_IT_DOMAIN_ARCHITECTURE.md` §0.5, row `C11` (`:93`), verbatim and complete:

> | **C11** | **Scope corrections:** seated/assigned inventory is out of scope for Miami GA+tables — **but the
> seat atom is hedged now (C42):** ticket atoms carry optional-nullable `seat_ref`/`unit_row` references (NULL
> for GA/tables), and the C4/C22 unit-rows **are** the future seat atoms (unit-rows ≡ seats), so reserved
> seating later is additive at the storage level and only the seat-map/selection **UX program** remains a
> future cost — the prior "known future NON-additive change" verdict (H6) holds *only if this hedge is
> skipped*. The "superset of Ticketmaster/AXS" claim is softened accordingly. Dual-control / step-up are
> **config-gated seams** a single-operator org satisfies via single-approver-with-mandatory-audit — **but the
> dual-control threshold is itself under dual-control** (Security R2). **The 36-event catalog is trimmed to
> the ~10 invariant-bearing sync calls + ~6 real outbox events; `social`/`analytics` ship as **deferred**
> schemas, not Phase-2 build.** | §16.4, §7.4, §6.1, §5 | Architect/Staff/PM over-build findings. |

The catalog clause is **one sentence of a four-clause row**. Its two operative halves:

- **the counts:** *"trimmed to the ~10 invariant-bearing sync calls + ~6 real outbox events"* — two
  categories, `~10` and `~6`, `~16` together;
- **the deferral:** *"`social`/`analytics` ship as **deferred** schemas, not Phase-2 build"* — a ratified
  removal of two of the five contexts, which is itself a removal criterion.

Gate: **P**. Status: **Ratified·MVP** (DA `:2947`). `VERIFIED:`

### 1.3 The criterion — which the constitution row does not carry, and the origin does

The `C11` row states an *outcome* (`~10 + ~6`) and no *test*. The test is in the resolution that produced it.
`_superseded/PHASE_2_ARCHITECTURE_REVIEW.md` `:73`, verbatim:

> 5. **Event-driven catalog (36 events).** Architect/Staff call most of it premature. **Resolution (C11):**
> keep the naming discipline for the ~10 invariant-bearing synchronous calls + ~6 genuinely-async outbox
> events; **drop the speculative Phase-3/4 events and the consumer matrices for unbuilt contexts.** Transport
> stays a single outbox table on the existing cron.

**`C11`'s removal criterion is therefore two-pronged and explicit:**

- **(R1)** drop **speculative Phase-3/4 events**;
- **(R2)** drop **consumer matrices for unbuilt contexts**.

And its retention criterion is the constitution's own rule at DA §6.0 `:1176`, `VERIFIED:`

> **The rule that keeps this from over-engineering:** an event is **transactional only if a money or
> ownership invariant depends on it**; everything else is eventual via the outbox.

**These three tests — (R1), (R2), and the money-or-ownership-invariant rule — are the only criteria `C11`
supplies, and every classification in §3 is decided by one of them plus a ratified Gate assignment.**

### 1.4 What `C11` does **not** say — three things, stated so they are not silently assumed

1. **It does not say the sync set and the outbox set are disjoint over events.** They are classifications of
   an *effect*, not a partition of the *catalog*. DA §6.2's own sequence diagram (`:1242`) enqueues three
   **Sync**-classified events onto the outbox in the same transaction: `VERIFIED:`
   > `CORE->>OUT: enqueue OwnershipTransferred, PaymentCaptured, CredentialInvalidated`

   `OwnershipTransferred` (#17), `PaymentCaptured` (#9) and `CredentialInvalidated` (#21) are all marked
   **Sync** in §6.1. **This is the single most consequential fact in this document for `ODR-2`, and §7
   prices it.**
2. **It does not renumber, rename, or re-key anything.** DA §6.0 `:1174`: *"the drainer's target swaps from
   in-process handlers to a real bus — **the event catalog and idempotency keys do not change**."* Every
   surviving event below keeps its §6.1 number, name and idempotency key verbatim.
3. **It does not reach events that did not exist when it was ratified.** `PHASE_2_DOOR_LIFECYCLE_SPEC.md`
   §12.2 adds **eight** further events, **#37–#44**, `ADDITIVE`, *"Numbering continues the domain-architecture
   §6.1 catalog (which ends at 36)"* (`:1586`). `C11` predates them and says nothing about them. They are
   **out of `G-25`'s scope** (whose owner is DA §6.1) and **in `ODR-2`'s scope**, so §7 carries them.

---

## 2. All 36, enumerated verbatim from `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1

`VERIFIED:` transcribed from `SNATCH_IT_DOMAIN_ARCHITECTURE.md` `:1184`–`:1219`. Columns are §6.1's own.

| # | Event | Producing context | Consuming contexts | Sync / Async | Idempotency key |
|---|---|---|---|---|---|
| 1 | `OrganizationCreated` | core | analytics, (social) | Async | `org_id` |
| 2 | `ConnectOnboardingCompleted` | core | venue, market, analytics | Async | `connect_account_id + capabilities_hash` |
| 3 | `VenueApproved` | core | venue, social, analytics | Async | `venue_id` (state=approved) |
| 4 | `EventPublished` | core | venue, market, social, analytics | Async | `event_id + version` |
| 5 | `TicketTypeOpened / TierUnlocked` | venue | market (eligibility), analytics | Async | `ticket_type_id + tier_rank` |
| 6 | `InventoryHeldExpired` | venue | venue (counters), analytics | Async | `hold_id` |
| 7 | `OrderPlaced (pending)` | venue | core (payment intent), analytics | **Sync** (order+intent same tx) | `order_id` |
| 8 | `PaymentAuthorized` | core | venue/market (the causer) | **Sync** on native paths; webhook-idempotent | `stripe_payment_intent_id` |
| 9 | `PaymentCaptured` | core | venue, market, analytics | **Sync** with issuance/transfer | `stripe_payment_intent_id + 'captured'` |
| 10 | `TicketIssued` | core | venue, market (eligibility), social, analytics | **Sync** (same tx as capture on primary) | `order_item_id + serial_no` |
| 11 | `TicketReserved` | venue | venue, analytics | Async | `hold_id` |
| 12 | `ListingCreated` | market | core (lock, native only), analytics, social | **Sync** for native (locks ticket); Async ext | `listing_id` |
| 13 | `BidPlaced` | market | market (engine), analytics | **Sync** (trigger-validated under lock) | `bid_id` |
| 14 | `OfferMade / OfferAccepted` | market | market, core (on accept), analytics | Sync on accept | `offer_id + state` |
| 15 | `AuctionWon` | market | core (transfer+payout), analytics | **Sync** with settlement tx | `market_sale_id` |
| 16 | `ListingSold (buy-now)` | market | core (transfer+payout), analytics | **Sync** | `market_sale_id` |
| 17 | `OwnershipTransferred` | **core** | venue (credentials), market, social, analytics | **Sync** (the transfer itself) | `ownership_log_id` |
| 18 | `TransferStarted (p2p / external)` | market | core (native lock), notifications, analytics | Sync (native lock); Async notify | `transfer_id` |
| 19 | `TransferAccepted` | market | core (transfer_ownership), analytics | **Sync** (native → ownership) | `transfer_id + 'accepted'` |
| 20 | `TransferExpired` | market (cron) | core (unlock), notifications | Async (swept by cron) | `transfer_id + 'expired'` |
| 21 | `CredentialInvalidated` | core | venue (scan manifests), analytics | **Sync** (rides on OwnershipTransferred) | `ticket_id + credential_version` |
| 22 | `ScanAdmitted` | venue | core (mark_scanned), analytics, risk | **Sync** online; **outbox-reconciled** offline | `ticket_id` (partial-unique on admitted) |
| 23 | `ScanRejected` | venue | risk, analytics | Async | `scan_id` |
| 24 | `SettlementClosed` | venue | core (payout generation), analytics | Sync (close→request payouts, same tx) | `settlement_id` |
| 25 | `PayoutReleased` | core | venue, market, notifications, analytics | Async (deferred by design) | `payout_id` |
| 26 | `PayoutFailed` | core | venue/market, notifications, risk | Async | `payout_id + attempt` |
| 27 | `RefundIssued` | core | venue/market, notifications, risk, analytics | **Sync** with ticket void (if full) | `stripe_refund_id` |
| 28 | `TicketVoided` | core | venue (manifests), market (delist), analytics | **Sync** with refund | `ticket_id + cause_ref` |
| 29 | `DisputeOpened (chargeback)` | market | core (freeze payout), risk, notifications | **Sync** freeze; Async notify | `stripe_dispute_id` |
| 30 | `DisputeResolved` | market | core (release/settle), risk, analytics | Sync on money effect | `stripe_dispute_id + outcome` |
| 31 | `AttributionRecorded` | venue | core (commission payout), analytics | Sync (same tx as OrderPaid) | `order_id + promoter_link_id` |
| 32 | `PromoterCommissionAccrued` | core | venue, notifications, analytics | Async | `attribution_id` |
| 33 | `FriendJoinedEvent` | social/venue | social (feed), notifications | Async | `user_id + event_id` |
| 34 | `ReferralCompleted` | social | venue/core (credit), analytics | Async | `referral_id` |
| 35 | `RiskFlagRaised` | core (risk) | market/venue (gating), admin, notifications | Async | `subject_id + signal + window` |
| 36 | `AdminActionPerformed` | core | analytics, (audit is the source) | Async | `admin_audit_log_id` |

### 2.1 Two arithmetic facts about the "36" that every downstream count has inherited

- **36 rows carry 38 event names.** Rows **#5** (`TicketTypeOpened` / `TierUnlocked`) and **#14** (`OfferMade`
  / `OfferAccepted`) each name **two** events under one number. Enumerated: 34 single-name rows + 2 two-name
  rows = **38 names in 36 rows**. Every "36" in the corpus is a *row* count.
- **20 rows carry a `Sync` arm — not "roughly nineteen".** `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md`
  §8 `:713` says *"Roughly nineteen carry a `Sync` arm"* and prints no enumeration. The enumeration is:
  **#7 · #8 · #9 · #10 · #12 · #13 · #14 · #15 · #16 · #17 · #18 · #19 · #21 · #22 · #24 · #27 · #28 · #29 ·
  #30 · #31 — twenty.** The sixteen with **no** `Sync` arm are **#1 · #2 · #3 · #4 · #5 · #6 · #11 · #20 ·
  #23 · #25 · #26 · #32 · #33 · #34 · #35 · #36**. 20 + 16 = 36. `VERIFIED:` read row by row from §6.1.
  *(This is a count correction to the matrix, not to a constitution; recorded here, applied nowhere.)*

---

## 3. Classification of all 36 — `KEEP` · `REMOVE` · `RENAME/CONSOLIDATE`, with authority

**Admissible authority, per the method:** a ratified `C`/`D`/`O-` row · a Gate assignment (`Gate P`/`M`/`L`)
that puts the event out of MVP scope · a named consumer that still exists in the corpus · a named consumer
deleted by a ratified correction. **Plausibility is not authority.**

**The five authorities this section leans on, established once here so each row can cite them short:**

| Tag | Authority | Where | Read |
|---|---|---|---|
| **`A-DEFER`** | `social` and `analytics` ship as **deferred** schemas, not Phase-2 build | `C11` itself, DA `:93` | `VERIFIED` |
| **`A-RISK`** | The fraud/risk substrate (`C20`) is **Gate M/L · Ratified·gated-ext**; and *"no `risk` table exists in any of the sixteen packages"* | CDM `:626`, `:698` · TRACE §8 `:717` | `VERIFIED` |
| **`A-GATEM`** | *"do not begin native resale until **Gate M**"*; `feature.native_resale_enabled` **stays OFF until Gate-M**; **`C43`** (the whole p2p `locked` overlay) is `RATIFIED-MODELED-ONLY(GATE-M)`, **MVP-must-implement `NO`**; `catalog.resale_policy` default is **`off`** (`C11`) | CTO memo `:13`, `:59` · plan `:453` · ratification record `C43` · SPEC_FOUNDATION `:139` | `VERIFIED` |
| **`A-SSCAS`** | `C12`'s closed, enumerated fifteen-member SSCAS + the global lock order | CDM `:601`–`:618` | `VERIFIED` |
| **`A-SPINE`** | DA §6.2's explicit *"Same-tx (transactional) set"* prose enumeration | DA `:1248` | `VERIFIED` |

> **`A-SPINE` enumerated, because §6.2 states it as prose and nothing in the corpus counts it.** *"OrderPlaced
> →PaymentAuthorized→PaymentCaptured→**TicketIssued** (primary); AuctionWon/ListingSold→**OwnershipTransferred**
> →CredentialInvalidated→market_sale→payout-request (native resale); TransferAccepted→OwnershipTransferred
> (native p2p); RefundIssued→TicketVoided; SettlementClosed→payout generation; DisputeOpened→payout freeze;
> BidPlaced (validated under row lock)."* The distinct §6.1 events named are **#7 · #8 · #9 · #10 · #13 ·
> #15 · #16 · #17 · #19 · #21 · #24 · #27 · #28 · #29 — fourteen.** **`A-SPINE` is therefore narrower than
> §6.1's twenty `Sync` rows**: it omits **#12 · #14 · #18 · #22 · #30 · #31** (six). That six-event gap between
> the constitution's own table and its own prose is where two of §3's judgement calls sit, and both are shown.

### 3.1 The table

`Cat.` = the surviving category: `S` = invariant-bearing sync call · `O` = real outbox event · `—` = removed ·
`?` = §6 owner input.

| # | Event | Class | Cat. | Authority — the ratified thing that determines it | Tag |
|---|---|:---:|:---:|---|:---:|
| 1 | `OrganizationCreated` | **REMOVE** | — | **`A-DEFER`.** Consumers are `analytics, (social)` **only**; both are deferred by `C11`. TRACE §8.2 `:767` names it in the closed enumeration of the **four** events with zero built consumers (#1 · #23 · #33 · #36). Removal criterion **(R2)** exactly. | `VERIFIED` |
| 2 | `ConnectOnboardingCompleted` | **OWNER INPUT** | ? | Consumers `venue`,`market` **exist**; `analytics` deferred (`A-DEFER`). Producer is `G-3` — `kernel.set_org_connect_ref` is *"EDGE-FRONTED … and contracted nowhere until RPC §20.1.1"* (plan `:1282`), an open **`S1`** defect. **No document names an asynchronous handler in `venue` or `market`.** → §6.1 | `INFERENCE` either way |
| 3 | `VenueApproved` | **KEEP** | **O** | **Named consumer that still exists.** TRACE `:256`: consumers `venue`,`market` exist, *"`social` and `analytics` are deferred schemas under `C11`"*. TRACE §8 `:724`: producer **`✓ catalog.approve_venue`**. Async in §6.1, no `Sync` arm → an outbox event by `C11`'s own rule (DA §6.0: no money/ownership invariant depends on it). | `VERIFIED` |
| 4 | `EventPublished` | **KEEP** | **O** | As #3. TRACE `:256` names it beside #3 with the same finding; producer **`✓ catalog.publish_event`** (authored `081`, `FR-2` — plan `:1347`). Async, no `Sync` arm. | `VERIFIED` |
| 5 | `TicketTypeOpened / TierUnlocked` | **RENAME/CONSOLIDATE → OWNER INPUT** | ? | **The `TierUnlocked` arm is `REMOVE`, `VERIFIED`:** TRACE §8 `:726` — *"**no tier concept exists** in `venue.ticket_type` in any package, so the `TierUnlocked` arm has no producer"*. **The `TicketTypeOpened` arm is undetermined:** its one built consumer is `market (eligibility)`, and native-rail eligibility is `A-GATEM`. → §6.2 | arm 1 `VERIFIED`, arm 2 `INFERENCE` |
| 6 | `InventoryHeldExpired` | **REMOVE** | — | **Not a real outbox event — the corpus says so in its own words.** `PHASE_2_SUPABASE_MIGRATION_PLAN.md` `:1353`: `venue.sweep_expired_inventory_holds` runs *"on the **2-minute `pg_cron` heartbeat that already runs** — it needs a **scheduler**, not the outbox **carrier**, so it is **NOT** blocked on the `COND-A` ruling"*, and it is **`LOAD-BEARING`** — it restores the counter **in its own transaction**. Its only non-`analytics` consumer is `venue (counters)`, i.e. the producing context's own row, already written. | `VERIFIED` |
| 7 | `OrderPlaced (pending)` | **KEEP** | **S** | `A-SPINE` (head of the primary chain) · `A-SSCAS` member **#1 Issuance** · Gate **P**. Producer **`✓ venue.create_primary_checkout`** (`082`). Consumer `core (payment intent)` exists. | `VERIFIED` |
| 8 | `PaymentAuthorized` | **KEEP** | **S** | `A-SPINE` · `A-SSCAS` #1 · Gate **P**. Producer **`✓ stripe-webhook`** (live, frozen money core). Consumers `venue`/`market` exist. | `VERIFIED` |
| 9 | `PaymentCaptured` | **KEEP** | **S** | `A-SPINE` · `A-SSCAS` #1 · Gate **P**. Producer **`✓ stripe-webhook`** → `venue.finalize_primary_order` (`085`, `C111`). **Also enqueued to the outbox by DA §6.2's diagram — see §7.** | `VERIFIED` |
| 10 | `TicketIssued` | **KEEP** | **S** | `A-SPINE` (the bolded terminus of the primary chain) · `A-SSCAS` #1 · Gate **P**. Producer **`✓ kernel.issue_ticket_atoms`** (`083` after `C114`/`R2B`). | `VERIFIED` |
| 11 | `TicketReserved` | **OWNER INPUT** | ? | Producer **`✓ venue.reserve_primary_inventory`** (`081`). Consumers are `venue` — **the producing context itself** — and `analytics` (deferred, `A-DEFER`). **No cross-context consumer survives**, and nothing in the corpus says whether a same-context event stays in the catalog. → §6.3 | `INFERENCE` either way |
| 12 | `ListingCreated` | **REMOVE** (Gate M) | — | **`A-GATEM`** — `market.create_listing` is named in the `feature.native_resale_enabled` guard (plan `:453`), and `resale_policy` default is `off` (`C11`). **Additionally `G-5`:** *"NO CONTRACTED PRODUCER"* — RLS §11.1 grants `market.create_listing` EXEC and the RPC contracts contract none of the six `market.*` writers (TRACE `:71`). `A-SSCAS` #6 restores it at Gate M unchanged. | `VERIFIED` |
| 13 | `BidPlaced` | **REMOVE** (Gate M) | — | **`A-GATEM`** (native auction). **`G-5`:** the authority table *"declines to name"* the bid RPC even while granting it (TRACE `:115`). **`ODR-27` is open on where the bid ledger even lives** (register `:80`). `A-SSCAS` #13 (auction deposit-release) restores it at Gate M. | `VERIFIED` |
| 14 | `OfferMade / OfferAccepted` | **REMOVE** (Gate M) | — | **`A-GATEM`** (`offer` is one of the six resale modes, default `off`). **`G-5`:** `make_offer`/`respond_offer` uncontracted. | `VERIFIED` |
| 15 | `AuctionWon` | **REMOVE** (Gate M) | — | **`A-GATEM`**. Producer **PARTIAL**: TRACE §8 `:736` — the existing `auto-finalize-auctions` edge is **external-rail** and edge §8 states it is *"untouched by this spec"*; **no native auction finalizer is contracted.** `A-SSCAS` #2 restores it at Gate M. | `VERIFIED` |
| 16 | `ListingSold (buy-now)` | **REMOVE** (Gate M) | — | **`A-GATEM`** (`buy_now` is a resale mode, default `off`). **`G-5`.** `A-SSCAS` #2 (the `C8` native sale) restores it at Gate M. | `VERIFIED` |
| 17 | `OwnershipTransferred` | **KEEP** | **S** | `A-SPINE` (bolded) · `A-SSCAS` #1/#2/#3/#8 all terminate in it · Gate **P**, because **it fires on issuance and on refund-void, not only on resale**: DA §9.4 makes the transfer engine *"the sole custody writer"*. Producer **`✓ kernel.transfer_ticket_ownership`** (`088`, `FR-3`). Consumer `venue (credentials)` exists. **Also enqueued to the outbox — §7.** | `VERIFIED` |
| 18 | `TransferStarted (p2p / external)` | **REMOVE** (Gate M) | — | **`A-GATEM`** — **`C43`** (the entire p2p `locked` overlay) is `RATIFIED-MODELED-ONLY(GATE-M)`, MVP-must-implement **`NO`**; `transfers_only` is a `resale_policy` mode and the default is `off` (`C11`). `A-SSCAS` #7 restores it at Gate M. *(Producer `market.create_p2p_transfer` **does** exist in `088` — this removal is a gate, not a gap.)* | `VERIFIED` |
| 19 | `TransferAccepted` | **REMOVE** (Gate M) | — | **`A-GATEM`/`C43`**, as #18. `A-SPINE` names it, but `A-SPINE` is the *transactional* classification, not the *gate*. `A-SSCAS` #8 restores it at Gate M. | `VERIFIED` |
| 20 | `TransferExpired` | **REMOVE** | — | **Two independent authorities.** (a) **`A-GATEM`/`C43`** — the hard-TTL auto-unlock **is** `C43`, Gate M. (b) **Not an outbox event even at Gate M:** TRACE §8 `:741` — *"**Cron-swept — survives** (a DB sweep, not an outbox consumer)"*; `market.sweep_expired_p2p_transfers` runs on the `088` heartbeat tick (plan `:1474`). | `VERIFIED` |
| 21 | `CredentialInvalidated` | **KEEP** | **S** | `A-SPINE` (bolded, in the native-resale chain) **and** Gate **P** independently: its consumer `venue (scan manifests)` is **`venue.append_door_manifest_delta`**, which exists — stub `083`, body `086` (`C113`/`R2B`) — and RPC §12.4c **binds every voiding path to write a `revoke` delta**: *"Omitting it re-opens the offline-revocation leak the exemptions were granted around"* (plan `:1411`). **Kept as a distinct event, not folded into #17**, because it has its own key (`ticket_id + credential_version`), its own consumer, and fires on void (#28) where no ownership transfer to a new holder occurs. **Also enqueued to the outbox — §7.** | `VERIFIED` |
| 22 | `ScanAdmitted` | **KEEP** | **S** | Gate **P** (Phase 2B). §6.1 marks it **Sync** online. Producer **`✓ venue.record_scan`** (`086`); consumer **`✓ kernel`** (`mark_ticket_scanned`, `079`) — both built, cross-context. It is invariant-bearing under DA §6.0's rule: the partial-unique `ticket_id` on admitted **is** the double-admit invariant. **Not in `A-SPINE`'s prose** — this is judgement call 1 of 2, shown in §5.2. **Its *offline* arm is `outbox-reconciled` and is a separate matter — §7.** | `VERIFIED` |
| 23 | `ScanRejected` | **REMOVE** | — | **`A-DEFER` + `A-RISK`.** Consumers are `risk, analytics` **only** — neither exists. TRACE §8.2 `:767` lists it among the four with zero built consumers. Criterion **(R2)**. | `VERIFIED` |
| 24 | `SettlementClosed` | **KEEP** | **S** | `A-SPINE` (*"SettlementClosed→payout generation"*) · `A-SSCAS` member **#4** · Gate **P** (venue-gets-paid is in the MVP path). Producer **`✓ kernel.close_settlement`** (`087`); consumer `kernel` payout generation exists. | `VERIFIED` |
| 25 | `PayoutReleased` | **KEEP** | **O** | **The canonical real outbox event.** §6.1: *"Async (**deferred by design**)"* — the only row in the catalog whose asynchrony is itself the ratified design. Producer **`✓ kernel.release_payout`** (`085`); consumers `venue`,`market` exist (cross-context); `notifications` additionally named by `PHASE_2_NOTIFICATIONS_SPEC.md` §5 `:368` as **MANDATORY** `payout_released`. | `VERIFIED` |
| 26 | `PayoutFailed` | **KEEP** | **O** | Async, no `Sync` arm. Producer **`✓ payout-execute`** (live edge) + `kernel.mark_payout_transfer_state` (`085`, `MB-2`). Consumers `venue`/`market` exist; NOTIF `:369` **MANDATORY** `payout_failed` **and** `:457` **MANDATORY** `staff_payout_failed` to the `[org_finance] ∪ [org_owner]` union (`CONFLICT-5`). | `VERIFIED` |
| 27 | `RefundIssued` | **KEEP** | **S** | `A-SPINE` (*"RefundIssued→TicketVoided"*) · `A-SSCAS` member **#3 Refund-void** · Gate **P**. Producer **`✓ kernel.refund_primary_order`** (`085`). | `VERIFIED` |
| 28 | `TicketVoided` | **KEEP** | **S** | `A-SPINE` · `A-SSCAS` #3 · Gate **P**. Producer **`✓ kernel.void_ticket_atom`** (`085`); consumer `venue (manifests)` is the same `append_door_manifest_delta` path as #21. **Also drives Wallet supersession — §7.** | `VERIFIED` |
| 29 | `DisputeOpened (chargeback)` | **REMOVE** (Gate M) | — | **`C30`** — fan-side chargeback/clawback liability is `RATIFIED-MODELED-ONLY(GATE-M)`, MVP `NO` (ratification record). **Producer does not exist:** TRACE §8 `:750` — *"**no dispute or chargeback table exists in any of the sixteen packages**"*. `A-SSCAS` #9 restores it at Gate M. **Note the residual tension in §6.4.** | `VERIFIED` |
| 30 | `DisputeResolved` | **REMOVE** (Gate M) | — | As #29 — `C30` Gate M, no producer. `A-SSCAS` #11 (dispute-resolution reversal) restores it at Gate M. | `VERIFIED` |
| 31 | `AttributionRecorded` | **KEEP** | **S** | **Ratified `D7`**, quoted at TRACE `:403`: *"the attribution row is written **in the same transaction that marks the order paid** — never at order creation … **The constitutions are the side that is right; RPC §6.1 and RLS §9.17 are wrong and must move**."* `A-SSCAS` member **#5**. **Gate P, structurally:** `venue.finalize_primary_order` (`085`) calls `venue.resolve_order_attribution` **inside the paid transaction**, and the `085` stub *"never raises"* because *"a raise here would roll back the money and the tickets"* (plan `:203`) — so the call is on the Gate-P primary-purchase path whether or not a promoter exists. Producer **`✓`** stub `085` / body `090`. **Not in `A-SPINE`'s prose** — judgement call 2 of 2, shown in §5.2. | `VERIFIED` |
| 32 | `PromoterCommissionAccrued` | **OWNER INPUT** | ? | **The corpus contradicts itself.** `PHASE_2_PACKAGE_REGISTRY.md` §7 / schema §13.3 list promoter work as **unaffected by `COND-A`** — *"promoter codes (**no async at all**)"* — while `PHASE_2_NOTIFICATIONS_SPEC.md` §5 `:445` triggers `promoter_commission_accrued` **from this event**. Producer exists (`kernel.pay_promoter_commission`, authored **`090`**, plan `:1501`) though **`G-7`** leaves it **uncontracted**. → §6.4 | conflict is `VERIFIED`; resolution is not determined |
| 33 | `FriendJoinedEvent` | **REMOVE** | — | **`A-DEFER`.** Producer `social` (deferred); consumers `social (feed)`, `notifications`. TRACE §8.2 `:767`: zero built consumers. Criteria **(R1)** *and* **(R2)**. | `VERIFIED` |
| 34 | `ReferralCompleted` | **REMOVE** | — | **`A-DEFER`.** Producer is `social`, deferred — DA §5.2.4 `:1080` makes this event `social`'s *only* money-adjacent emission (*"Referrals that pay out do so by **emitting a `ReferralCompleted` event**"*), so with `social` deferred the event has no emitter. Criterion **(R1)**. | `VERIFIED` |
| 35 | `RiskFlagRaised` | **REMOVE** | — | **`A-RISK`.** `C20` (fingerprint + risk-signal ledger) is **Gate M/L, `Ratified·gated-ext`** (CDM `:698`), and *"no `risk` table exists in any of the sixteen packages"*. **`C24` does not save it:** `C24` is Gate P but requires the opposite — *"any write/admit/payout decision that consults risk state reads the **authoritative** risk aggregate **synchronously** and fails closed"* (CDM `:630`) — i.e. `C24` forbids the async event from being load-bearing. Criterion **(R1)**. | `VERIFIED` |
| 36 | `AdminActionPerformed` | **REMOVE** | — | **`A-DEFER`** + the row's own payload note. TRACE `:667`: *"its own payload note says **'audit is the source'** — the audit table is the system of record and the event is a derived analytics copy."* `kernel.admin_audit` is INSERTed **in the same transaction** as the action (RPC §0.3), so the fact is already durable. Zero built consumers (§8.2's four). Criterion **(R2)**. | `VERIFIED` |

### 3.2 The classification totals — each with its enumeration

| Class | Count | Enumeration |
|---|:---:|---|
| **KEEP — sync (`S`)** | **11** | #7 · #8 · #9 · #10 · #17 · #21 · #22 · #24 · #27 · #28 · #31 |
| **KEEP — outbox (`O`)** | **4** | #3 · #4 · #25 · #26 |
| **REMOVE — Gate M (restored, unchanged, at Gate M)** | **9** | #12 · #13 · #14 · #15 · #16 · #18 · #19 · #29 · #30 |
| **REMOVE — unbuilt context / no carrier needed** | **8** | #1 · #6 · #20 · #23 · #33 · #34 · #35 · #36 |
| **RENAME/CONSOLIDATE** | **1 arm** | #5's `TierUnlocked` arm (the row itself sits in OWNER INPUT) |
| **OWNER INPUT REQUIRED** | **4** | #2 · #5 · #11 · #32 |

**11 + 4 + 9 + 8 + 4 = 36.** ✔ Every row of §2 is classified exactly once.

---

## 4. The canonical surviving catalog

**This is the closed set.** Fifteen events determined by the corpus, split by `C11`'s own two-way test.
Anything not here is in §3 as `REMOVE` or in §6 as owner input. No event below is invented; every name,
producer, consumer and idempotency key is §6.1's own.

### 4.1 Category `S` — invariant-bearing sync calls (in-transaction, must not fail) — **eleven**

*Definition, from DA §6.0 `:1176`: transactional because a money or ownership invariant depends on it. These
are **function calls inside one Postgres transaction**, not messages. They survive `ODR-2 = NO`.*

| # | Canonical name | Producer (RPC / edge) | Package that creates the producer | Consumer(s) that exist at MVP | Kept by | Idempotency key |
|---|---|---|---|---|---|---|
| 7 | `OrderPlaced (pending)` | `venue.create_primary_checkout` | **`082`** | `kernel` (payment intent) | `A-SPINE` · `A-SSCAS` #1 | `order_id` |
| 8 | `PaymentAuthorized` | `stripe-webhook` (live edge) | *frozen money core — no Phase-2 package* | `venue`, `market` | `A-SPINE` · `A-SSCAS` #1 | `stripe_payment_intent_id` |
| 9 | `PaymentCaptured` | `stripe-webhook` → `venue.finalize_primary_order` | **`085`** (`C111`/`R2B`) | `venue`, `market` | `A-SPINE` · `A-SSCAS` #1 | `stripe_payment_intent_id + 'captured'` |
| 10 | `TicketIssued` | `kernel.issue_ticket_atoms` | **`083`** (`C114`/`R2B`) | `venue`, `market` | `A-SPINE` · `A-SSCAS` #1 | `order_item_id + serial_no` |
| 17 | `OwnershipTransferred` | `kernel.transfer_ticket_ownership` | **`088`** (`FR-3`) | `venue` (credentials), `market` | `A-SPINE` · `A-SSCAS` #1/#2/#3/#8 · DA §9.4 sole custody writer | `ownership_log_id` |
| 21 | `CredentialInvalidated` | rides on #17; and on #28 | **`088`** (rider) · consumer path **`083`** stub + **`086`** body | `venue` — `venue.append_door_manifest_delta` | `A-SPINE` · RPC §12.4c binding | `ticket_id + credential_version` |
| 22 | `ScanAdmitted` | `venue.record_scan` | **`086`** | `kernel` (`mark_ticket_scanned`, `079`) | §6.1 **Sync** online · Gate P (Phase 2B) · partial-unique double-admit invariant | `ticket_id` (partial-unique on admitted) |
| 24 | `SettlementClosed` | `kernel.close_settlement` | **`087`** | `kernel` (payout generation) | `A-SPINE` · `A-SSCAS` #4 | `settlement_id` |
| 27 | `RefundIssued` | `kernel.refund_primary_order` | **`085`** | `venue`, `market` | `A-SPINE` · `A-SSCAS` #3 | `stripe_refund_id` |
| 28 | `TicketVoided` | `kernel.void_ticket_atom` | **`085`** | `venue` (manifests), `market` (delist) | `A-SPINE` · `A-SSCAS` #3 | `ticket_id + cause_ref` |
| 31 | `AttributionRecorded` | `venue.resolve_order_attribution` | stub **`085`** (`C111`) → body **`090`** | `kernel` (commission payout) | **`D7`** · `A-SSCAS` #5 | `order_id + promoter_link_id` |

**Eleven. Enumerated: #7 · #8 · #9 · #10 · #17 · #21 · #22 · #24 · #27 · #28 · #31.**

### 4.2 Category `O` — real outbox events (post-commit, retryable, at-least-once) — **four**

*Definition, from `C11`: "genuinely-async". No money or ownership invariant depends on delivery; a delayed or
replayed delivery cannot corrupt anything, because consumers are idempotent on the key (DA §6.2 `:1250`).
**These are the events that do not exist at all under `ODR-2 = NO`.***

| # | Canonical name | Producer (RPC / edge) | Package that creates the producer | Consumer(s) that exist at MVP | Kept by | Idempotency key |
|---|---|---|---|---|---|---|
| 3 | `VenueApproved` | `catalog.approve_venue` *(alias `set_venue_approval`, `G-20`)* | **`078`** | `venue` | named-consumer-exists (TRACE `:256`) | `venue_id` (state=approved) |
| 4 | `EventPublished` | `catalog.publish_event` *(alias `set_event_status`, `G-20`)* | **`081`** (`FR-2`) | `venue`, `market` | named-consumer-exists (TRACE `:256`) | `event_id + version` |
| 25 | `PayoutReleased` | `kernel.release_payout` (via `payout-execute`) | **`085`** | `venue`, `market` (+ `notify`, `ODR-3`) | §6.1 *"Async (deferred by design)"* · NOTIF §5 `:368` MANDATORY | `payout_id` |
| 26 | `PayoutFailed` | `payout-execute` → `kernel.mark_payout_transfer_state` | **`085`** (`MB-2`) | `venue`, `market` (+ `notify`, `ODR-3`) | NOTIF §5 `:369`/`:457` MANDATORY ×2 | `payout_id + attempt` |

**Four. Enumerated: #3 · #4 · #25 · #26.**

> **Note on #3/#4 and `ODR-3`.** Their surviving consumers (`venue`, `market`) are **built contexts, not
> `notify`** — so #3 and #4 stay outbox events under either `ODR-3` ruling. #25 and #26 have built consumers
> **and** mandatory `notify` consumers, so `ODR-3` changes their fan-out, never their existence.

---

## 5. The arithmetic against `C11`'s counts

### 5.1 The comparison, shown rather than asserted

| | `C11` says | This reconstruction determines | Δ | Undetermined (§6) |
|---|:---:|:---:|:---:|:---:|
| invariant-bearing **sync** calls | **~10** | **11** | **+1** | 0 of the 4 |
| real **outbox** events | **~6** | **4** | **−2** | up to **4** of the 4 |
| **total surviving** | **~16** | **15** | **−1** | **4** |

**The bracket, stated so nothing is forced.** Four events are undetermined (§6). If every one resolves
`KEEP`, the catalog is **11 sync + 8 outbox = 19**. If every one resolves `REMOVE`, it is **11 + 4 = 15**.
**`C11`'s ~16 sits inside `[15, 19]`.** The reconstruction is *consistent with* `C11` and does not *equal* it,
and the gap is four named, cited open questions — not rounding.

### 5.2 The `+1` on the sync side, named

`C11` says `~10`; §4.1 lists **11**. The surplus is **not** a padded row — it is the six-event gap between
DA §6.1's twenty `Sync` rows and DA §6.2's fourteen-event prose spine (§3, `A-SPINE` note). Of those six —
**#12 · #14 · #18 · #22 · #30 · #31** — four are removed at Gate M by `A-GATEM`/`C30` (#12, #14, #18, #30) and
**two are kept**:

- **#22 `ScanAdmitted`.** Kept because both its producer (`venue.record_scan`, `086`) and its consumer
  (`kernel.mark_ticket_scanned`, `079`) exist and are cross-context, and §6.1 marks it **Sync** online. It is
  invariant-bearing on DA §6.0's own test: the partial-unique on admitted **is** the no-double-admit
  invariant. **Removing it would leave the door with no catalogued admit fact at the one gate MVP must run.**
- **#31 `AttributionRecorded`.** Kept because `D7` is a **ratified** correction that pins it same-transaction,
  and because `venue.finalize_primary_order` (`085`) calls its producer *inside the paid transaction* on the
  Gate-P primary path.

**If an owner rules either of these out, the sync count is 10 and matches `C11` exactly.** Both are recorded
here as the two places the reconstruction chose, and why, rather than being folded silently into a clean ten.

### 5.3 The `−2` on the outbox side, named

`C11` says `~6`; §4.2 lists **4**. **Three of the four §6 open questions are outbox candidates** — **#2**
`ConnectOnboardingCompleted`, **#5** `TicketTypeOpened`, **#32** `PromoterCommissionAccrued` — and the fourth,
**#11** `TicketReserved`, is one too. **4 + 3 = 7** if the three cleanly-outbox ones are kept; **4 + 4 = 8**
with #11. `C11`'s ~6 is inside that range. The arithmetic reconciles; it reconciles *as a range*, because the
corpus supplies four fewer determinations than `C11` supplies slots.

### 5.4 A count `C11` could not have made, and which changes the total

`C11` was ratified against a 36-row catalog. `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §12.2 has since added **eight**
events — **#37 `DoorManifestOpened` · #38 `DoorManifestClosed` · #39 `TransferFreezeEngaged` · #40
`DoorManifestDrained` · #41 `DoorFreezeOverrideGranted` · #42 `DoorFreezeOverrideEnded` · #43
`DoorManifestSupplemented` · #44 `DoorManifestInvalidated`** — explicitly continuing §6.1's numbering
(`:1586`). **`C11`'s `~16` is a budget against 36 rows; the corpus now has 44.** Whether the door eight are
inside or outside `C11`'s budget is not something `C11` can answer, and this document does not decide it.
It matters for `ODR-2` and is priced in §7.

---

## 6. **OWNER INPUT REQUIRED** — the four the corpus does not determine

**This section is an outcome, not a failure.** Each entry gives the event, both readings, what each implies,
and the evidence that would settle it. **None of these may be closed by a reading of what is plausible.**

### 6.1 `#2 ConnectOnboardingCompleted` — does a built consumer that reacts to nothing keep an event alive?

- **Reading A — KEEP as an outbox event.** Two of its three named consumers (`venue`, `market`) are built
  contexts (only `analytics` is deferred, `A-DEFER`). Under `C11`'s criterion **(R2)** — drop *"the consumer
  matrices for unbuilt contexts"* — this row's matrix is **not** wholly unbuilt, so it is not caught.
  **Implies:** one more outbox event, and `G-3` becomes an outbox-blocking defect, not merely an RPC gap.
- **Reading B — REMOVE.** **No document anywhere names an asynchronous handler in `venue` or `market` for
  it.** `VERIFIED:` the string `ConnectOnboardingCompleted` occurs in exactly two files in the whole corpus —
  `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1 and the traceability matrix's own register. Connect capability is
  read on demand from `kernel.organization`, not delivered. **Implies:** the outbox set drops to the sixteen
  §6.1 rows with no `Sync` arm minus every unbuilt-consumer row, and `G-3` stays a pure `S1` RPC defect.
- **What would settle it.** A named handler — one line in any spec saying what `venue` or `market` *does*
  when an org's Connect capabilities land. If none is ever written, Reading B is correct by construction.
- **Coupling.** `G-3` (`S1`, `PHASE_2_RPC_FUNCTION_CONTRACTS.md` owns it) must close regardless; the two are
  independent.

### 6.2 `#5 TicketTypeOpened / TierUnlocked` — one arm is dead, the other is gated

- **Settled, `VERIFIED`:** the **`TierUnlocked` arm is `REMOVE`** — *"no tier concept exists in
  `venue.ticket_type` in any package"* (TRACE §8 `:726`). The row must at minimum be **renamed** to drop it.
- **Reading A — KEEP `TicketTypeOpened` as an outbox event.** Its consumer `market (eligibility)` is a built
  context and package `088`/`089` ship. **Implies:** one more outbox event at Gate P.
- **Reading B — REMOVE until Gate M.** The eligibility `market` computes is **native-rail resale eligibility**,
  and `A-GATEM` puts that behind `feature.native_resale_enabled` with `resale_policy` default `off` (`C11`).
  Until then nothing consumes it. **Implies:** the row leaves the Gate-P catalog and returns, renamed
  `TicketTypeOpened`, at Gate M.
- **What would settle it.** Whether `market.listing_unified`'s **external** rail (live today) consumes
  ticket-type opening. `VERIFIED:` `PHASE_2_PACKAGE_REGISTRY.md` places `listing_unified` at `089` as
  *"external ∪ native, flag-gated"* — it does not say whether the external arm reacts to this event.
- **Regardless of the ruling, the `/ TierUnlocked` half of the name must go.**

### 6.3 `#11 TicketReserved` — is a same-context event still an event?

- **Reading A — KEEP as an outbox event.** TRACE §8 `:732` records the consumer as **`✓ venue`** — present.
  §6.1 marks it Async. Producer `venue.reserve_primary_inventory` (`081`) exists. Nothing in the corpus says
  an event needs a *foreign* consumer. **Implies:** one more outbox event.
- **Reading B — REMOVE.** Its only surviving consumer **is its own producing context** — `venue` writing and
  `venue` reading the same `venue.inventory_hold` row it just wrote — and its one cross-context consumer,
  `analytics`, is deferred (`A-DEFER`). On that reading criterion **(R2)** does catch it. **Implies:** the
  outbox set is strictly cross-context, which would also be a general rule worth writing down.
- **What would settle it.** A single ratified line stating whether the outbox carries intra-context events.
  `VERIFIED:` DA §6.0/§6.3 and CDM §2's three-legal-channels rule (`:294`) both describe events as the
  *cross-aggregate* channel, but **neither says an intra-context event is inadmissible** — which is exactly
  why this is here and not in §3.
- **The same question decides nothing else.** #6 `InventoryHeldExpired` has the same shape but is removed on
  an independent, verified authority (the plan's own *"needs a scheduler, not the outbox carrier"*), so this
  ruling does not disturb it.

### 6.4 `#32 PromoterCommissionAccrued` — two ratified surfaces say opposite things

**This is not an ambiguity; it is a live contradiction, and both sides are `VERIFIED`.**

- **Side A — it needs no carrier.** `PHASE_2_PACKAGE_REGISTRY.md` §7 and `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`
  §13.3 both list the promoter work among the deltas **NOT dependent on the outbox**, in the schema spec's
  words: *"promoter codes (**no async at all**)"*. `PHASE_2_SCOPE_AMENDMENT_2026_08.md` `:197` says the same
  of the sibling #31: *"Named in `REGISTRY` §7 as **unaffected** by the outbox ruling — commission accrual has
  its own scheduler at settlement close."*
- **Side B — it is an outbox trigger.** `PHASE_2_NOTIFICATIONS_SPEC.md` §5 `:445` defines notification type
  `promoter_commission_accrued`, channel `I p E`, default `ON`, dedup `commission:<attribution_id>`, **fired
  by `#32 PromoterCommissionAccrued`** — and NOTIF §4 *is* the outbox pipeline (its own `CONFLICT-2`).
- **What each implies.** Side A: #32 is `REMOVE`d from the outbox catalog and the promoter engine keeps its
  settlement-close scheduler; the promoter notification is dropped or re-sourced. Side B: #32 is `KEEP` as an
  outbox event and the promoter work **is** `COND-A`-blocked, which **falsifies registry §7's `unaffected`
  list** — a list `ODR-2`'s own blast-radius pricing rests on.
- **What would settle it.** The `ODR-3` ruling. If `notify` is Gate L, Side B has no consumer and Side A
  stands. If `notify` is Gate P, Side B's consumer exists and registry §7's `unaffected` line needs
  correcting. **`COND-D` already requires `ODR-2` then `ODR-3` in one sitting; this row should be re-read
  immediately after that sitting.**
- **Independent of the ruling:** `G-7` leaves `kernel.pay_promoter_commission` **uncontracted** while the plan
  authors it in `090` (`:1501`). That gap closes either way.

### 6.5 A gap that is not one of the four, and is not mine to fill

**Three ratified surfaces consume an event-cancellation fact that DA §6.1 does not name.** `VERIFIED:`

- `A-SSCAS` **member #10** is *"Event-cancellation cascade — Event/Sessions + K× Ticket void + Ownership-log
  + Listing/Auction unwind + Refund initiation"* (CDM `:611`);
- `PHASE_2_NOTIFICATIONS_SPEC.md` §5 `:388` defines notification type `event_cancelled`, sourced **`SSCAS #10`
  event-cancellation cascade** — the only row in its table whose trigger column cites an SSCAS member instead
  of a §6.1 event number, because **there is no number to cite**;
- `PHASE_2_APPLE_WALLET_SPEC.md` §6.3 `:696` makes *"session time / venue / status change,
  `catalog.cancel_event`"* an **always**-priority push driven by *"catalog outbox"*.

§6.1's catalog has `EventPublished` (#4) and **no cancellation or session-change event**. **I am not naming
one** — that would be inventing an event, which this document is forbidden to do. It is recorded so the owner
sees that `ODR-2`'s carrier question covers a fact the catalog does not enumerate.

---

## 7. What this changes for `ODR-2` / `ODR-3` pricing

### 7.1 The headline: the ratified `~6` is **not** the number of events needing a carrier

`DF-23`'s complaint is that an owner pricing `ODR-2` reads 36 where the ratified answer is *"about six."*
**Both numbers are wrong for that question, and in opposite directions.**

**Sync classification does not mean "no outbox row."** DA §6.2's own diagram (`:1242`) writes three **Sync**
events to the outbox inside the custody transaction — `OwnershipTransferred` (#17), `PaymentCaptured` (#9),
`CredentialInvalidated` (#21) — because the *transaction* is synchronous while the *downstream reaction* is
not. `PHASE_2_APPLE_WALLET_SPEC.md` §6.3 makes this explicit and load-bearing: pass supersession runs *"in
the **outbox consumer**, deliberately **not** inside the custody transaction"*, and §16 preserves it as an
invariant — *"Wallet can never block or roll back a transfer."*

**Therefore: the outbox carrier is required by a superset of `C11`'s `~6`.**

### 7.2 The events that need an outbox carrier at MVP — enumerated, from named consumers only

Union of the three specs that name an outbox consumer. **Gate-M events are excluded**, so this is the Gate-P
carrier load.

| Source of the requirement | §6.1 / door events it puts on the outbox |
|---|---|
| **`PHASE_2_APPLE_WALLET_SPEC.md` §6.3** — *"Driven by the existing outbox"*, drained by `wallet-pass-push` (`084`) | **#17** (`credential_version` bump) · **#28** (void) · **#22** (atom → `scanned`) · **#40** (`DoorManifestDrained`) · *the unnumbered catalog session/venue/status + `cancel_event` fact of §6.5* |
| **`PHASE_2_DOOR_LIFECYCLE_SPEC.md` §12.2** — envelopes written **inside** the all-or-nothing open txn | **#37 · #38 · #39 · #40 · #41 · #42 · #43 · #44** (all eight) |
| **`PHASE_2_NOTIFICATIONS_SPEC.md` §5** — Gate-P-reachable triggers only, `ODR-3`-conditional | **#9** · **#10** · **#25** · **#26** · **#27** · **#31** · **#32** |
| **This document §4.2** — real outbox events with built consumers, `ODR-3`-independent | **#3** · **#4** · **#25** · **#26** |

**Distinct events requiring a carrier at Gate P, enumerated:** **#3 · #4 · #9 · #10 · #17 · #22 · #25 · #26 ·
#27 · #28 · #31 · #32 · #37 · #38 · #39 · #40 · #41 · #42 · #43 · #44** — **twenty**, plus the **one unnumbered
catalog-cancellation fact** of §6.5 = **21 facts**.

**Of those twenty, eight (#37–#44) did not exist when `C11` was ratified, and seven (#9, #10, #17, #22, #27,
#28, #31) are classified `Sync`.** Only **five** (#3, #4, #25, #26, #32) are "real outbox events" in `C11`'s
sense — and #32 is §6.4's open contradiction.

### 7.3 What this does to the `ODR-2` decision, stated plainly

- **The list an owner should price is not 36 and not ~6. It is 20 events + 1 unnumbered fact** (§7.2), of
  which **8 are the door events `C11` never saw** and **7 are `Sync` events that still need a post-commit
  row.** The volume argument for `ODR-2 = (b)` (*"withdraw the promise"*) is **weaker** than the ~6 suggests,
  because the carrier serves the door and Wallet paths, not only notifications.
- **`ODR-2 = NO` costs are unchanged and confirmed by this reconstruction**, not enlarged: the four
  capabilities the corpus already names as *"unimplementable **as designed**, not merely degraded"* — Apple
  Wallet push, the door-manifest open transaction, scanner push-to-sync, notifications — are exactly the
  consumers in §7.2's first three rows. **This document adds no new casualty.** It adds the *reason* the
  casualty list is longer than `~6`.
- **`ODR-2 = YES` costs are unchanged:** *"one table plus one RPC on a cron that already runs"*, package
  **`076`**, zero FK dependencies, no producer package gains an edge. **The carrier is one table whether it
  carries 6 events or 21** — which is the substantive point `C11`'s `~6` was obscuring in the owner's favour
  on the wrong side.
- **`ODR-3` interacts with exactly four rows** and no others: **#25 · #26 · #31 · #32** (`notify` fan-out).
  **#3, #4, #37–#44 do not depend on `ODR-3`** — their consumers are `venue`, `market` and the scanner. So a
  `notify = Gate L` ruling **does not** empty the outbox; ten of the twenty carrier-needing events survive it.
  `COND-D`'s ordering rule (`ODR-2` first, then `ODR-3`, one sitting) is unaffected.

### 7.4 The four `Gate-M` events whose carrier cost is deferred, not avoided

Enumerated so the Gate-M bill is not a surprise: **#12 · #13 · #14 · #15 · #16 · #18 · #19 · #20 · #29 · #30**
(ten) return at Gate M with their §6.1 numbers, names and idempotency keys **unchanged** (DA §6.3: *"the event
catalog and idempotency keys do not change"*). `PHASE_2_NOTIFICATIONS_SPEC.md` §5 already defines eight
notification types against them (`transfer_sent`, `transfer_received`, `transfer_accepted`, `transfer_expired`,
`listing_created`, `listing_bid_received`, `listing_outbid`, `listing_sold`, `payout_on_hold`), so the Gate-M
carrier load is **specified and waiting**, not undesigned.

---

## 8. What I could not verify

Stated so no reader takes silence for confirmation.

1. **`C11` has no source text in `_governance/PHASE_2_RATIFICATION_RECORD.md`.** The method assumed it did.
   It does not — the record starts at `C26` (§1.1). The binding text used here is DA §0.5 `:93`, and the
   criterion is from `_superseded/PHASE_2_ARCHITECTURE_REVIEW.md` `:73`, a file in `_superseded/`. **If the
   owner holds that a `_superseded/` file is not admissible authority, then `C11` has an outcome (`~10 + ~6`)
   and no criterion anywhere, and §3's removal reasoning loses its (R1)/(R2) test** — the Gate and
   named-consumer authorities would survive, the *"speculative Phase-3/4"* test would not.
2. **`C11`'s `~` is not defined.** *"~10"* and *"~6"* are approximations in ratified text. Nothing states the
   tolerance. §5's `[15, 19]` bracket is arithmetic over the four open questions, **not** an interpretation
   of `~`.
3. **`#6 InventoryHeldExpired` — the corpus disagrees with itself and I resolved it on recency of substance,
   not on a ratified precedence rule.** TRACE `G-24` (`S1`, `:76`) states the hold-expiry sweep is *"named
   nowhere"*; `PHASE_2_SUPABASE_MIGRATION_PLAN.md` `:1347`/`:1353` **now names, schedules and specifies**
   `venue.sweep_expired_inventory_holds(p_limit)` and marks it `LOAD-BEARING`. I treated the plan as
   correct because it is the more specific and later statement, and the removal rests on the plan's own
   *"needs a scheduler, not the outbox carrier"* — **but I did not find a rule saying the plan outranks the
   matrix**, and both files are at the same commit.
4. **I did not verify anything against the database or the running system.** Every `VERIFIED` in this
   document means *"read at the cited file and line on `269e473`"* and nothing stronger. No migration was
   applied, no query was run, no `psql` was opened.
5. **Producer-package attributions for `#8` and `#26` are edge functions in the live system**
   (`stripe-webhook`, `payout-execute`), not Phase-2 migration packages. I recorded them as such rather than
   forcing a package number.
6. **The `G-20` name divergences are unresolved upstream and I carried both names** — `catalog.approve_venue`
   / `set_venue_approval` (#3) and `catalog.publish_event` / `set_event_status` (#4). `PHASE_2_RPC_FUNCTION_CONTRACTS.md`
   is the canonical namer and has not ruled. **Two names for one function produces two functions or none.**
7. **I did not classify the door events `#37`–`#44`.** They are outside `G-25`'s stated owner (DA §6.1) and
   outside `C11`'s reach (§1.4). §7 prices them for `ODR-2`; §3 does not judge them. **If the owner wants the
   catalog closed at 44 rather than 36, that is a second pass with its own authority review.**
8. **`#29`/`#30` carry a residual tension I removed on gate authority but did not dissolve.** `A-SSCAS`
   member **#9** (dispute → payout freeze) is part of `C12`, which is **Gate P · Ratified·MVP** (CDM `:690`),
   while `C30` (the chargeback liability the dispute plane needs) is **Gate M** and **no dispute table exists
   in any of the sixteen packages**. I classified on the latter two. **A Gate-P SSCAS member with no Gate-P
   substrate is a defect in its own right and is not `G-25`'s to file.**

---

## 9. One-paragraph answer, for the owner about to rule on `ODR-2`

**`C11` cut a 36-row catalog to `~16`, and nothing said which sixteen. The corpus determines fifteen: eleven
invariant-bearing sync calls (`#7 · #8 · #9 · #10 · #17 · #21 · #22 · #24 · #27 · #28 · #31`) and four real
outbox events (`#3 · #4 · #25 · #26`). Nine more are removed only until Gate M and return unchanged
(`#12 · #13 · #14 · #15 · #16 · #18 · #19 · #29 · #30`); eight are removed outright because their contexts
are deferred or they need a scheduler rather than a carrier (`#1 · #6 · #20 · #23 · #33 · #34 · #35 · #36`);
four the corpus genuinely does not decide (`#2 · #5 · #11 · #32`). But the number that prices `ODR-2` is
none of these: it is the twenty events plus one unnumbered fact that need an outbox row at Gate P (§7.2),
because seven `Sync` events still write post-commit rows for Wallet and notifications, and eight door events
`C11` never saw write theirs inside the open transaction. The carrier is one table either way.**

---

*Reconstruction only. No existing document was modified. `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1 still lists
all 36 rows unmarked; marking them is the `G-25` remediation this document makes possible, and is a separate
change against that file's own owner.*
