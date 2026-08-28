# Snatch It — Canonical Data Model

**The permanent data constitution.** Conceptual and technology-agnostic. This document sits between the business domain and any physical schema:

> **Business Domain** (`docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md`) → **Canonical Data Model** (this document) → **Physical PostgreSQL Schema** (future implementation)

It defines **what data exists and why**, never **how a database stores it**. It is subordinate to and fully consistent with the frozen domain architecture and its corrections C1–C11; where this document would conflict, the domain architecture governs and the conflict is flagged, not invented around. No SQL, no schemas, no code.

**Anchors inherited (non-negotiable):** the additive modular monolith with contexts **`kernel` · `catalog` · `venue` · `market` · `social` · `analytics` · `notify`** (the C7 split of the former `core`); the four invariants (ticket-atom, ownership-log-as-truth, payments-never-determine-ownership, everything-auditable); the two-rail marketplace (native issued ticket vs. external claim); asymmetric credential (C1, key lifecycle per C33); owner-authorized single transfer engine (C2/C35); per-ticket idempotency `UNIQUE(cause, cause_ref, ticket_id)` + the per-sale terminal machine on the ownership log (C3 as corrected by C26); the frozen money core.

The final-audit corrections **C26–C50 / O6 / D1–D3** (ratified 2026-08-24 by the pre-implementation consolidation session) are integrated throughout this document and summarized as ratified text in §15; the **Correction Index appendix** maps every ID to its section, and `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` is the per-correction ratification record. Gate labels used below (P = pre-native-issuance · M = pre-money-rail · L = pre-legal-scale) follow `docs/architecture/_governance/CTO_DECISION_MEMO.md`; Gate-M/L items are **modeled-only** here — the constitution reserves the extension point, and MVP builds none of them.

---

## Section 0 — Design Principles

These are permanent. Every object, relationship, and future amendment is judged against them.

1. **Single source of truth.** Each fact has exactly one canonical home. Every other place the fact appears is a *derivation* of that home, never a second master. The ticket is the atom; its ownership log is the sole truth of custody.
2. **Immutable identity.** Every canonical object carries an opaque, globally-unique, permanent identifier assigned at creation. An identifier is never reused, never re-pointed to a different object, and never encodes meaning (no business data inside the ID).
3. **Ledger-first design.** State that carries money, custody, or trust is recorded as an **append-only ledger of causes**, and the "current" value is a *derived head* of that ledger. We record *what happened* (an event with a cause), and compute *what is true now* from history — not the reverse.
4. **Append-only history.** Ledgers are insert-only: no update, no delete. Corrections are new compensating entries, never edits. History is permanent and complete enough to reconstruct any past state ("who owned ticket X at time T, and why").
5. **Derived read models.** Everything a screen shows is a projection computed from canonical objects. Projections are disposable and rebuildable from the ledgers and operational state; losing a projection is never data loss.
6. **Canonical IDs vs. external IDs.** The canonical ID is the internal truth. Any identifier from an external system (a provider, a payment processor, a chain) is an *attribute recorded in a mapping*, never the canonical identity of the object.
7. **Auditability by construction.** Every state transition that moves money, custody, permission, or trust records who caused it, when, why (a reason/cause code), and — where practical — the before/after. Audit is not a feature bolted on; it is the shape of the ledgers.
8. **Additive architecture / no destructive evolution.** The model grows by adding objects, attributes, and derivations. It never renames, repurposes, or deletes canonical concepts. Deprecation replaces removal; new supersedes old while old remains readable.
9. **Backward compatibility.** A change is legal only if every prior consumer of the data continues to read a coherent world. New optional concepts default to a value that preserves old behavior.
10. **Event consistency (bounded).** Within one aggregate, state is transactionally consistent. Across aggregates, state is eventually consistent via an ordered event log — except for a **small, closed, enumerated set of sanctioned synchronous cross-aggregate transactions** (the SSCAS — see C12), each held to the full C8 discipline (one choke-point function, defined lock order, idempotency key, bounded dwell + alarm, a named future saga). The set is closed: adding a member requires an amendment.
11. **No hidden state, no orphans, no polymorphism of ownership.** Every reference resolves to a real canonical object. Nothing is owned "by a type discriminator + id"; ownership is always to a named aggregate. No state exists only in application memory, a cache, or a client.
12. **Fail-closed and least-authority.** Absence of a fact denies rather than permits. Every object is readable/writable by the fewest principals necessary; capability derives from relationships, never from a self-asserted attribute.
13. **Technology-agnostic longevity.** The model assumes only: durable ordered storage, transactions within an aggregate, and an append log across them. It does not assume Postgres, a specific cloud, or a specific chain — so it can outlive all of them.

---

## Section 1 — Canonical Objects

For each object: **Purpose · Lifecycle · Ownership · Mutability · Key relationships · Invariants · Canonical identity.** Objects are grouped by context. Mutability classes: **Ledger** (append-only) · **Operational** (mutable, guarded) · **Reference** (kernel-written, world-read) · **Config** · **Derived** · **Blob** · **Secret**.

### 1.1 Identity & money kernel (`kernel`)

**Identity** — *the one account.*
- Purpose: a single principal representing a human. All capability (fan, seller, promoter, staff, admin) derives from *relationships to* this identity, never from a type on it.
- Lifecycle: `provisional → active → suspended → anonymized`. Never hard-deleted (would orphan ledger references); deletion is anonymization to a retained sentinel.
- Ownership: self-owned; platform admin may suspend/anonymize (audited).
- Mutability: Operational (profile), with an append-only **Identity Event** sub-ledger for security-relevant changes.
- Relationships: root referenced by org-membership, staff-role, ownership-log, orders, listings, payouts, wallet.
- Invariants: exactly one canonical `IdentityID`; capability is never an attribute; anonymization preserves referential integrity.
- Identity: `IdentityID`.

**Wallet** — *the fan's money-adjacent state.*
- Purpose: the identity's balance of platform credit/holds (distinct from external bank/card). A derived + ledgered value, not a free-floating number.
- Lifecycle: created with identity; lives for its life.
- Mutability: **Derived head** of a **Wallet Ledger** (append-only credits/debits with cause). Balance is never written directly.
- Invariants: balance = sum of wallet-ledger entries; no negative balance except explicitly modeled overdraft causes.
- Identity: `WalletID` (1:1 with `IdentityID`).

**Payment Method** — *a reference to an external funding instrument.*
- Purpose: a tokenized handle to a card/bank held by the payment processor; Snatch It stores only the token + display metadata, never raw instrument data.
- Mutability: Operational; soft-deactivated, never deleted (payments reference it).
- Invariants: no PAN/secret stored; belongs to exactly one identity.
- Identity: `PaymentMethodID` (maps to a processor token).

**Organization** — *the business that operates venues / promotes / gets paid for primary sales.*
- Purpose: payee and contracting party for primary ticketing; the tenant boundary.
- Lifecycle: `applied → approved → active → suspended → closed`.
- Ownership: its owner-members; platform approves/suspends.
- Mutability: Operational + append-only **Org Membership Ledger**.
- Invariants: an org has ≥1 owner at all times; payout destination changes are audited and cool-down-gated (dual-control seam).
- Identity: `OrganizationID`.

**Ticket Atom** — *THE single source of truth for an admission credential.*
- Purpose: one row of custody truth per admission right. Everything (listings, transfers, scans, sales) references the atom; the atom references nothing downstream.
- Lifecycle (state): `issued → active → scanned` (terminal) | `voided` (terminal, includes refund-void per C-A5) | `expired` (terminal). Plus a resale sub-state `none | listed | locked`.
- Ownership: `current_owner` is a **derived head** of the Ownership Log; the venue is the *issuer*, never the owner; entry is controlled by the current owner's valid credential alone.
- Mutability: Operational **state** + immutable **identity** (id, event_session, type, issuer, serial). Only the issuance and transfer engines mutate custody.
- Relationships: belongs to an `EventSession` (catalog, toward-reference); has one Ownership Log; has one Credential; has many Scans; may have one active Listing.
- Invariants: exactly one live owner at any instant; `listed`/`locked` tickets cannot be transferred or scanned except through their sanctioned path (a pending-p2p `locked` overlay auto-unlocks on hard TTL — C43); native only — external claims are NOT ticket atoms. **No re-entry in MVP (C41):** one admitted scan consumes the session's admission; re-entry is a named future change whose extension point is the Scan Event's `direction` attribute, never a resurrection of `scanned`. **Seat hedge (C42):** the atom carries optional-nullable seat/unit-row references (NULL for GA/table MVP) so reserved seating is storage-additive later.
- Identity: `TicketAtomID` + `(EventSessionID, serial_no)` unique.

**Ownership Log** — *the append-only custody ledger.*
- Purpose: the complete, ordered history of who held a ticket and why. The atom's `current_owner` is its head.
- Mutability: **Ledger** (insert-only). Written only by the transfer engine.
- Invariants: **per-ticket idempotency `UNIQUE(cause, cause_ref, ticket_id)`** for money-causing causes (C26 — one cause legally fans out to N tickets: an issuance mints K atoms and a refund-void voids K tickets under one `cause_ref`, one row per atom, each triple appendable exactly once; the original two-column C3 key was provably wrong for exactly these flows). Cross-object re-void is blocked one level up by the per-`market_sale` terminal machine (C26 — see §1.4). Every entry names from/to/cause/cause_ref/actor/timestamp; first entry is the issuance (`from = ∅`).
- Identity: `OwnershipLogID` (per entry).

**Issued Credential** — *the asymmetric, verifiable admission proof.*
- Purpose: the thing a door verifies. A signature over `(TicketAtomID ‖ credential_version ‖ EventSessionID ‖ time_bucket)` produced by the **kernel private signing key**; doors hold only the **public** key (C1).
- Mutability: Operational **version counter** on the atom; the signing secret is **Secret** storage (a vault key, never a row attribute, never in a manifest).
- Lifecycle: valid at `credential_version = N`; a transfer bumps to `N+1` inside the transfer transaction, instantly invalidating all prior signatures.
- Invariants: verifiable offline with the public key; never forgeable by a verifier; old versions fail closed online (the online door performs a live per-scan authoritative read at the decision point — C37); the offline window is an explicit reconcile/fraud state, not a guarantee (C6). `credential_version` is **pinned to the Ownership Log** (C27-adjacent): it advances only inside the transfer transaction that appends the log row and is verified against the log head like `current_owner` — never an independent second custody truth.
- Key lifecycle (C33 — Gate P; the hardest-to-reverse decision): signing keys are **per-event scope by default** (per-venue allowed; global discouraged — an existential single point); private key material lives **only in a KMS/HSM** (the model stores a public key + opaque handle, never material; signing is performed by the signer service calling the KMS); rotation is a first-class audited operation with exactly one active signer per scope; a per-scope **compromise runbook** exists (revoke, re-issue the affected scope, redistribute public keys); the **signer** is engineered for HA/throughput on the credential hot path; every atom pins the key that signed it, and doors receive **public keys only**.
- Identity: `CredentialID` is `(TicketAtomID, credential_version)`.

**Payment** — *frozen money-core charge record* (existing; referenced, not redesigned).
- Purpose: the authoritative record of a Stripe charge. Belongs to the frozen core.
- Mutability: append-only-ish state machine (existing).
- Invariants: unchanged from the frozen core; the data model treats it as an external-to-this-design ledger it *references*, never mutates.
- Identity: `PaymentID`.

**Payout** — *unified outbound money record.*
- Purpose: money leaving the platform to a payee (organization for primary/settlement; identity for resale-seller or promoter commission).
- Mutability: **Ledger** (append-only state entries).
- Invariants: idempotent by a deterministic key (existing discipline); every payout references its cause (settlement line, market sale, commission).
- **Authority (O-3):** the org payout ledger is **readable** by `org_owner` and `org_finance` for their own org and by no other org role (`org_admin` is denied the whole money plane); a venue-plane finance grant reads **settlement-caused** payouts for its own venue only, because a payout is **org-grain — it has no venue** — and its venue is derivable solely through a settlement line. Both money roles may **request** a payout. The **payout destination** is changeable by `org_owner` **alone**, under strictly stronger controls than a request, and — because O-3 collapses the separation of duties that previously held by construction — **the identity that set the current destination may never request a payout to it** (permanently, per destination; DA §7.4). Any surface implying "same authority, both actions" is wrong.
- Identity: `PayoutID`.

**Refund** — *first-class money reversal.*
- Purpose: full or partial reversal of a payment; downstream voids tickets (`cause = refund_void`).
- Mutability: **Ledger**.
- Invariants: references a payment; sum of refunds ≤ payment; a refund that voids tickets appends to the Ownership Log via the transfer engine.
- **Authority (O-1):** organization authority over a refund is authority to **request**, never to execute. `org_owner` and `org_finance` may request a refund on their own org's orders and read the org refund ledger; the request is resolved **server-side** into one of three tiers from configured thresholds — execute immediately · in-org dual control with a **different** approving identity · platform review — and the caller never chooses the tier. `org_admin` holds none of it. Whatever the tier, the Refund row is written by **exactly one** function, so R7 money-single-path is preserved and no request object ever writes a money row. Refund of a ticket that was already scanned reverses **money only**: the atom stays `scanned`, no inventory returns, and there is no terminal re-animation (D2/C41 stand).
- Identity: `RefundID`.

**Money-plane extension objects (C29/C30/C31 — Gate M; modeled, NOT built in the Phase-2 foundation).** Three named objects complete the money-reversal envelope beside the frozen payment core; native resale + instant payout may not ship before they exist:
- **Reserve / Clawback (C29)** — *the funding source for reversals.* A first-class reserve/receivable object per payee plus the **payout-timing policy that gates instant payout**; funds cancellation refunds, C25 auto-compensations, and post-payout clawback. Instant payout with no reserve is an unrecoverable-loss design. Mutability: Ledger.
- **Fan Liability (C30)** — *the ledger home for a fan-side debt.* A withdrawn fan-seller's chargeback/clawback is representable — a receivable object or Wallet-ledger negative-balance causes (the physical form is fixed by the Gate-M amendment) — never an unbookable silent loss. Mutability: Ledger.
- **Money Ledger, double-entry (C31)** — *the balancing structure and the recommended home for C29/C30.* An additive double-entry schema beside the frozen Stripe core: every platform money movement (splits, royalty — today a one-sided credit — rounding residuals, reserve funding, compensations) posts balanced entries, so an unbalanced movement is a constraint violation, not a leak. The custody Ownership Log stays separate — custody is not a balance problem. Mutability: Ledger.

The frozen `Payment` core is untouched by all three; their canonical IDs join the §4 registry via the Gate-M amendment that builds them (the Reserve is already a placed class in the global lock order — C28).

**Admin Audit Entry** — *the privileged-action ledger.*
- Purpose: immutable record of every privileged mutation (approvals, refunds, overrides, config changes).
- Mutability: **Ledger**.
- Invariants: written in the same transaction as the action it records; actor, reason code, before/after where practical.
- Identity: `AuditID`.

### 1.2 Reference & configuration (`catalog`)

**Venue** — *a physical place; public and followable; anchors discovery.*
- Purpose: the room. Reference data written via kernel/catalog functions, read by all contexts.
- Lifecycle: `draft → active → archived`.
- Ownership: operated by an Organization; platform curates approval.
- Mutability: **Reference** (operational fields like hours/media are high-churn but still catalog-written).
- Invariants: belongs to exactly one operating organization at a time (operatorship changes are logged, not overwritten).
- Identity: `VenueID`.

**Event** — *the canonical event (replaces free-text names).*
- Purpose: groups one or more sessions at a venue by an organizer.
- Lifecycle: `draft → announced → on_sale → live → completed | cancelled`.
- Mutability: **Reference**.
- Invariants: has ≥1 `EventSession`; cancellation cascades to session/inventory/refund workflows via events, never destructive edits.
- Identity: `EventID`.

**Event Session** — *the admission occurrence; the grain scans and capacity bind to* (C7/A1).
- Purpose: a single admittable occurrence (one night of a residency, one day of a festival, one show of a double-header). Single-night events auto-create one implicit session.
- Mutability: **Reference**.
- Invariants: every ticket atom binds to exactly one session; capacity, door count, and scans are session-scoped; `tickets.event_session_id → catalog` is a legal toward-reference.
- **Door-freeze boundary (O-5).** The session carries the custody-freeze boundary `door_open_at`, and it is **not a mutable flag**: it is the **cached monotone head of an append-only door-episode ledger** (`MIN(opened_at)` over the session's manifest opens) — the same head-of-ledger pattern C27 ratified for `current_owner_id`/`credential_version`. Written only by the authorized open action (`org_owner`/`org_admin`/`venue_manager` — O-4), never by a client, never cleared by a close, never moved backwards; a re-open starts a new episode without moving it, so monotonicity is arithmetic rather than a remembered rule. The **effective** boundary is total and fail-closed — the earlier of the explicit head and an implicit backstop derived from the session's own door/start time — so a NULL `door_open_at` can never mean "never frozen"; before O-5 the column was read in four places and written by nothing, which made the C6/C23/C43 freeze false in practice. Overrides are explicit, platform-elevated, TTL-bounded, reason-coded, audited, and never move the boundary.
- Identity: `EventSessionID`.

**Platform Config** / **Resale Policy** — *tunable values, not code constants* (C-A8).
- Purpose: fee/window/policy **values** (platform-wide config; per-venue/per-event resale policy with modes `off | transfers_only | fixed_cap | face_value_queue | buy_now | auction | offer` per A10). The frozen fee-*application* logic is untouched.
- Mutability: **Config**, versioned (a policy in force at a moment is snapshot-referenced by the objects it governed — see O3 open item).
- Identity: `PlatformConfigID`, `ResalePolicyID` (+ version).

### 1.3 Venue operations (`venue`)

**Ticket Type** — *a sellable definition per event* (admission, table, bundle, add-on).
- Purpose: the priced, capacity-bearing product a fan buys; issuing it mints ticket atoms.
- Mutability: **Operational** (price/visibility change guarded; on-sale edits confirmed).
- Invariants: belongs to one event; capacity reconciles with its inventory batches.
- Identity: `TicketTypeID`.

**Inventory (Batch + Hold)** — *the capacity accounting of a ticket type* (scalar counter today, C42-hedged: unit-rows ≡ future seats).
- Purpose: account for how many admissions exist and their disposition. A **Batch** is a release/allocation (`public_sale | promoter_hold | comp | door | presale`); a **Hold** is a time-boxed reservation (server-max duration).
- Mutability: **Operational, authoritative counters (C27):** the locked counter is the single operational truth for `remaining`, guarded by `remaining ≥ 0` + locked/sharded decrement (C4/C22); the **Inventory Movement Ledger** (draws/releases with cause) is the append-only **audit stream**, and a reconciliation job asserts counter↔ledger equality. (This is the one deliberate inversion of the ledger→head pattern — an on-sale's hot path cannot serialize on ledger folds.)
- Invariants: `sold + held + reserved + remaining = capacity` is the *reconciliation check*, not the oversell guard; oversell is prevented by the non-negativity constraint on the locked authoritative counter; holds expire deterministically.
- Identity: `InventoryBatchID`, `InventoryHoldID`. **Seat/unit hedge (C42 — Gate P):** the unit-row form of the C4/C22 counter **is** the future seat atom (unit-rows ≡ seats); ticket atoms and inventory carry optional-nullable seat/unit-row references (NULL for GA/table MVP), so reserved seating is additive at the storage level and only the seat-map/selection UX remains a deferred program.

**Guest List Entry / Comp Allocation** — *governed non-sale capacity.*
- Purpose: named guest-list and complimentary admissions that still draw real capacity.
- Mutability: Operational.
- Invariants: draw from a batch like any issuance; never bypass capacity accounting.
- Identity: `GuestEntryID`, `CompAllocationID`.

**Order + Order Item** — *the primary-purchase transaction.*
- Purpose: the container that, when paid, issues ticket atoms atomically.
- Lifecycle: `pending → paid → partially_refunded | refunded | cancelled`.
- Mutability: order Operational; **order item is immutable after issuance** (snapshots price, type, quantity).
- Invariants: paid order → issuance in one transaction; source tagged (`app | web | door | promoter_link`); idempotent by key.
- Identity: `OrderID`, `OrderItemID`.

**Staff Role / Door PIN / Scan Device** — *venue access principals.*
- Purpose: staff-role = a user's scoped capability at a venue/event; door-PIN = a loginless, expiring, labeled device principal; scan-device = the hardware identity.
- Mutability: Operational (revocable).
- Invariants: capability derives from the relationship row; scope-qualified **with structurally disjoint per-plane label sets** (three separate scope-typed enums — org/venue/platform share no label, so cross-scope conflation is a type error; `has_venue_role`, never bare — C-A9/C36); PINs are device identities, not users — and a door PIN can never authorize a refund (C46: refund-at-door requires an authenticated staff principal with refund authority).
- **Label sets finalized (O-2 — closed; adding a label is an amendment).** org: `org_owner` · `org_admin` · `org_finance` · `org_marketing` · `org_promoter_manager` · `org_member`. venue: `venue_manager` · `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `venue_scanner`. platform: `platform_admin` · `platform_support` · `platform_risk`. Fifteen labels, three prefixes, none a prefix of another — a label's plane is decidable from its first token alone (**RM-1**: every label MUST begin with its plane token). Two changes are substantive: `venue_door` → **`venue_scanner`**, and **`venue_promoter` is removed** — a promoter holds no row in any grant table, so promoter escalation is impossible by construction rather than by policy. **Display names are a separate namespace** (DA §7.2's catalogue) and are never legal in a predicate.
- **The door session is not a role (O-2/O-4).** The default door principal is a **device-bound session** (registered scan device + door PIN + session), not an authenticated user: it satisfies **no** role predicate, and the role helper reads staff-grant rows and nothing else. A separate authenticated scanner grant exists for a named human who must be individually attributable. Neither may open, close or re-open a door manifest, move `door_open_at`, or change event security configuration.
- Identity: `StaffRoleID`, `DoorPinID`, `ScanDeviceID`.

**Scan Event** — *the append-only admission attempt ledger.*
- Purpose: every attempt to admit, online or reconciled-offline.
- Mutability: **Ledger**.
- Invariants: unique *admitted* scan per ticket is enforced online and *reconciled* offline (first-admit-wins + fraud queue — C6); records device, gate, result, **direction (`in`/`out`, default `in` — the C41 re-entry hedge; MVP is `in`-only, no re-entry)**, offline-batch.
- Identity: `ScanID`.

**Settlement** — *per-event/period money rollup for an organization.*
- Purpose: aggregate gross/fees/refunds/chargebacks/royalties/adjustments → net; generates payouts.
- Lifecycle: `open → closed → paid`.
- Mutability: Operational header + immutable **Settlement Line** entries referencing their source rows.
- Invariants: never modifies ticket history; every line references a canonical cause; royalty lines arrive from `market` via a named channel, never a cross-context join (C8).
- Identity: `SettlementID`, `SettlementLineID`.

**Promoter / Promoter Link / Attribution** — *the commissioned-selling engine.*
- Purpose: promoter = an identity attached to an org/event with commission terms; link = a tracked slug; attribution = an append-only record of a sale credited to a link.
- Mutability: link immutable; **attribution is Ledger**; terms Operational (versioned).
- Invariants: commission flows through Payout (`promoter_commission` cause); attribution is immutable once recorded.
- **Write timing is part of the invariant, not an implementation detail (D7).** The attribution row is written **in the same transaction that marks the order `paid` — never at order creation.** Attribution is an immutable Ledger carrying a commission claim: an order created and never paid is ordinary (abandoned checkout, expired hold, declined card), and a credit written at creation cannot be deleted when that happens, only superseded — leaving a permanent phantom credit in the promoter's ledger and in every settlement projection that reads it. Order creation is not a commercial fact; payment is. An implementation contract that records attribution inside order creation is the side that must move.
- **Commission terms the model requires (D8).** The promoter's terms must express **flat-per-ticket _or_ percentage** (flat-per-ticket is the dominant nightlife term, not a later refinement), a promoter **`tier`** distinguishing an invited professional from a public ambassador, and the **`party_kind`** discriminator (`promoter | affiliate`) that lets one attribution ledger serve both party kinds. A percentage-only representation silently drops two of the three and is not sufficient; the columns are additive and owed by the physical schema.
- **A promoter is a relationship, never a role (O-2).** Promoter authority is link/attribution row ownership; no promoter label exists in any of the three role enums, and an ambassador is a derived predicate that likewise enters none.
- Identity: `PromoterID`, `PromoterLinkID`, `AttributionID`.

**Gated venue-ops extensions (C39/C44/C45/C46 — modeled as extension points, NOT built in MVP).** Four venue capabilities are constitutionally reserved with explicit gates, so their absence is a decision, not an oversight: **comp/guest-list step-up** — above a per-staff threshold, comp issuance requires step-up + a live-grant re-check (C39, Gate L; comps are money-adjacent inventory); a **virtual-queue / waiting-room + bot-defense primitive** before competitive high-demand on-sales (C44, Gate L — the locked counter makes sellouts correct, not fair); the **table minimum-spend balance + at-the-room settlement** before any bottle-service system-of-record claim — until it lands, that revenue settles off-platform, an *explicit concession* (C45, Gate L, pulled to the 2A-tables gate if bottle-service scope ships); and **fire-code occupancy as a distinct attribute from sold capacity + cash box-office and auto-gratuity/tip-out settlement causes + door-refund authorization reconciled to authenticated staff** (C46, Gate L / 2B).

### 1.4 Marketplace (`market`)

**Listing** — *a marketplace offer* (external claim or native ticket).
- Purpose: expose inventory for resale. `inventory_kind = external | external_verified | native` (C10 adds the verified-external middle state); native listings *lock* their ticket atom.
- Lifecycle: `draft → active → sold | cancelled | expired`.
- Mutability: Operational.
- Invariants: native listing references exactly one ticket atom (or a lot); external listing references no atom (a claim); a native listing sets the atom `resale_state = listed`.
- Identity: `ListingID`.

**Auction / Bid / Offer** — *price-discovery children of a listing.*
- Purpose: auction = time-boxed competitive pricing (reserve, min-increment, anti-snipe, deposit mode); bid = an immutable, validated, possibly card-authorized offer; offer = a buyer-initiated price on a buy-now/negotiable listing.
- Mutability: auction Operational; **bid is Ledger** (immutable, append); `current_highest_bid` is a **derived head**.
- Invariants: buy-now cannot clear below current bid (structural, via the auction head); bids are binding when card-authorized.
- Identity: `AuctionID`, `BidID`, `OfferID`.

**Market Sale** — *one consummated resale transaction.*
- Purpose: the immutable fact of a resale (auction win or buy-now/offer accept): buyer, seller, price, fees, venue royalty, payment, settlement linkage.
- Mutability: **Ledger** (append; `paid_pending_transfer` is an explicit, bounded, alarmed intermediate that **auto-compensates at hard max-age** — C6/C-A6/C25), plus the **per-sale terminal state machine** `pending → completed XOR compensated` (C26), advanced only under the sale-row lock.
- Invariants: written by `market`, then calls the kernel transfer engine in the *same transaction* (C8); **the kernel authorizes the buyer principal itself at this seam (C35)** — a market-supplied buyer id is never trusted; the buyer is derived from the authenticated context and re-verified against the payment. The sale is the `cause_ref` for its ownership-log entries, and double-transfer is impossible via **`UNIQUE(cause, cause_ref, ticket_id)`** (one entry per atom of the sale/lot, each triple append-once) **plus compensate-XOR-complete on the terminal state** — a sale ends `completed` (transfer appended) or `compensated` (refund-void appended), never both, never twice, even across two refund objects (C26 — supersedes the two-column C3 key).
- Identity: `MarketSaleID`.

**Transfer (external rail) / P2P Transfer (native)** — *movement records.*
- Purpose: external = today's evidence-gated off-platform coordination (unchanged); native P2P = a request/accept wrapper over the kernel transfer engine (send to a handle/phone; free or price-capped by policy).
- Mutability: Operational state machine.
- Invariants: native P2P results in a kernel ownership-log entry + credential bump; external transfer never asserts kernel ownership.
- States (conceptual → physical, C43): the conceptual `requested` is physically named **`initiated`**; the physical set is `initiated → accepted → completed | declined | cancelled | expired` (+ `reason_code`; there is **no `failed` state** — a failure is `cancelled` + reason). `expired` is a hard-TTL terminal: on expiry the atom's `locked` overlay **auto-unlocks** (C25-style bound — never an unbounded lock, and never a deadlock with the C6 freeze); cancel-back-to-self is exempt from the offline freeze, and the freeze binds per open-manifest ticket, not session-wide (C43 — Gate M).
- Identity: `TransferID`, `P2PTransferID`.

**Dispute** — *chargeback/adjudication record* (existing).
- Identity: `DisputeID`.

### 1.5 External integration (`adapter`, conceptual — deferred build)

**Adapter Mapping** — *the canonical↔external bridge.*
- Purpose: map a canonical object to an external provider's identity/state; land external inventory as *claims*, never as kernel-issued atoms unless the provider delegates issuance.
- Mutability: Operational mapping + append-only **Sync Ledger**.
- Invariants: adapter has zero authority to write kernel custody (a hard capability denial, not a convention — C10); external IDs are attributes, never canonical identity; provider data is a claim, not truth.
- Identity: `AdapterID`, `AdapterMappingID`.

### 1.6 Social, notification, analytics, media (`social` · `notify` · `analytics` · blob)

**Follow / Venue Follower / Group / Friend Attendance** (`social`) — the read-only-over-the-graph social layer; privacy-gated (`attendance_visibility` default `only_me`, k≥3 aggregates — C10). Writes ownership never; group-buy enters inventory only via the one named hold function (A11). Identity: `FollowID`, `GroupID`, `FriendAttendanceID`.

**Referral / Promotion** (`social`/`venue`) — referral = an identity-to-identity acquisition record with a reward state; promotion = a discount/offer definition applied at order time. Mutability: referral **Ledger**; promotion Config. Identity: `ReferralID`, `PromotionID`.

**Notification** (`notify`) — an outbound message record + delivery state; push tokens are owner-scoped. Derived from events; never a source of truth. Identity: `NotificationID`.

> **C52 / O8 — OPEN: `notify` is Gate-P here and do-not-build in every implementation spec.** `notify` is one of the seven contexts named by **C7**, which is **RATIFIED · Gate P · MVP**, and this object has a canonical identity in the registry. All four Phase-2 implementation specs place `notify` at **Gate L / DO-NOT-BUILD** (deferred-schema list, out-of-RLS-scope, Gate-L extension list, "documented extension points, NOT scheduled"). Consequence either way, and **neither is chosen here**: if C7 is right, a `notify` schema is Gate-P work missing from the migration plan and the four specs' deferral text is wrong; if the specs are right, C7's Gate/MVP columns are wrong for this context, MVP notification continues to run on the pre-existing operational notifications table plus the existing push/notify edge functions, and **every Phase-2 design that names a `notify` consumer must say which carrier it actually means**. **C7 is not amended by this pass** and keeps its ratified status until the decision is made. Recorded as row **C52**, status `OPEN-GATED(O8)`.

**Analytics Snapshot / Event Stream** (`analytics`) — append-only behavioral stream + periodic rollup snapshots; read-only, venue-scoped; no PII beyond identity references. Identity: `SnapshotID`, stream entries keyed by `(stream, sequence)`.

**Search Index Entry** (derived) — a denormalized, rebuildable projection for discovery; never authoritative. Identity: mirrors its source's canonical ID.

**Media Asset** (blob) — an image/document stored in object storage; the canonical object is the *metadata + storage key + moderation state*, not the bytes. Private assets (proof docs, IDs) are access-gated; public assets are CDN-served. Identity: `MediaID`.

---

## Section 2 — Aggregate Roots

An **aggregate** is a consistency + transaction boundary: everything inside commits together; everything across boundaries coordinates by event, or by a member of the **closed Sanctioned Synchronous Cross-Aggregate Set (SSCAS)** enumerated in C12. The rule: **a transaction spans multiple aggregates only if it is a named member of the SSCAS** — and every SSCAS member carries the full C8 discipline. (An honest accounting: issuance, refund-void, and several native-rail flows are all SSCAS members — the set is enumerated, closed by C12, and completed by C28 at fifteen members.)

| Aggregate root | Contains (child objects) | Why it is the boundary | Consistency / transaction rule |
|---|---|---|---|
| **Identity** | profile, wallet (+ wallet ledger), payment methods, identity-event ledger | one human's self-owned state | all self-service edits commit within; capability rows live in the *granting* aggregate, not here |
| **Organization** | org membership ledger, connect payee ref, settlement config | the tenant + payee boundary | membership/payee changes commit within; audited |
| **Venue** | venue profile, staff roles, door pins, resale-policy defaults | the operational room + its access principals | staff/PIN grants commit within the venue |
| **Event** | event, event sessions, ticket types, inventory batches, holds, guest lists, comps | **capacity & admission are only consistent per event/session** | all inventory draws for a session serialize within this aggregate |
| **Ticket Atom** | the atom, its ownership log, its credential (version), its scans | **custody must be atomic for exactly one ticket** | the tightest boundary; the transfer engine locks the atom, appends the log, bumps the credential — one transaction |
| **Order** | order, order items | the purchase unit | payment→issuance commits within; issuance reaches the Ticket aggregate through the kernel issuance function |
| **Listing** | listing, auction, bids, offers | one resale offer's price discovery | bid validation + head update commit within |
| **Market Sale** | the sale fact (+ paid_pending_transfer state, + C26 terminal machine) | the consummation record | **an SSCAS member (#2 — C12/D1):** write sale + call kernel transfer engine together (C8), under the global lock order |
| **Settlement** | settlement header, settlement lines | period money rollup | lines aggregate references; generating payouts commits within |
| **Payout** | payout + its ledger states | outbound money | idempotent; references its cause aggregate |
| **Promoter** | promoter, links, attributions, terms | commissioned selling | attribution appended within |
| **Adapter** | adapter config, mappings, sync ledger | external bridge | sync commits within; never writes kernel custody |
| **Social graph** | follows, groups, friend-attendance, referrals | the read-only relationship layer | commits within; only *reads* event/ticket projections |

> **C51 / O7 — OPEN: channel (1) below has no scheduled implementation.** The outbox and its drainer are the default cross-aggregate channel here, the carrier for C12's event envelope (per-aggregate monotonic `sequence`, `causation_id`, `correlation_id`, at-least-once + idempotent consumers), and the mechanism DA §6.3 promises as *"one outbox table and a drainer on the cron that already runs"* — yet **no Phase-2 implementation spec schedules an outbox table, envelope columns or a drainer**; the only occurrence in the physical schema spec sits inside the Gate-L list. Either this constitution is right and an outbox package is Gate-P/MVP work missing from the plan, or the implementation specs are right and channel (1) has no carrier at MVP — in which case every design emitting an envelope message (door manifest, promoter attribution, notifications) needs a stated alternative transport. Recorded as row **C51**, status `OPEN-GATED(O7)`; **not resolved here**, and the text below is left standing rather than softened.

**Cross-aggregate communication.** Three legal channels only: (1) an **ordered event** on the outbox consumed asynchronously (the default); (2) a **published projection/view** for cross-aggregate reads; (3) a **member of the SSCAS** (C12) — a synchronous multi-aggregate transaction routed through a single choke-point kernel function, each bounded and alarmed. No aggregate reaches into another's tables ad hoc; the SSCAS is the *only* sanctioned synchronous write coupling, and it is closed and enumerated.

**No circular ownership.** The dependency direction is strictly: `Identity` ← (referenced by) everything; `catalog` (Venue/Event/Session) ← referenced by Ticket and Order but itself references only Identity/Org; `Ticket` ← referenced by Listing/Sale/Scan but references only catalog + Identity; `market`/`venue`/`social` reference `kernel`/`catalog`, never the reverse. The kernel depends on nothing downstream. Any proposed reference that points "up the stack" (kernel → market/venue) is illegal by construction.

---

## Section 3 — Canonical Relationships

Relationship kinds: **1:1 · 1:N · M:N · Derived · Materialized · Immutable · Append-only · Referenced (toward-reference to reference data) · Inherited (capability via relationship).**

| Relationship | Kind | Why it exists |
|---|---|---|
| Identity → Wallet | 1:1 | every principal has exactly one money-adjacent balance, itself derived from a ledger |
| Identity → Payment Method | 1:N | a fan funds from many tokenized instruments |
| Identity ↔ Organization | M:N (via Org Membership, append-only) | a person can belong to several orgs with roles; membership history is preserved |
| Organization → Venue | 1:N | an org operates many rooms; operatorship is time-scoped, not overwritten |
| Venue → Event | 1:N | a room hosts many events (an event references its venue as reference data) |
| Event → Event Session | 1:N | the residency/festival/double-header grain; **admission binds to session, not event** |
| Event Session → Ticket Type | 1:N (via Event) | sellable definitions per occurrence |
| Ticket Type → Inventory Batch | 1:N | capacity is released in accountable tranches |
| Inventory Batch → Inventory Movement | 1:N append-only | the counter is the derived head of these movements |
| Order → Order Item | 1:N, item Immutable-after-issue | the purchase snapshot |
| Order Item → Ticket Atom | 1:N Immutable | a paid item issues one or more atoms (its `cause_ref` in the ownership log) |
| Ticket Atom → Ownership Log | 1:N **append-only** | the atom's custody history; head = current owner |
| Ticket Atom → Credential | 1:1 by version (Derived/Secret) | the current admission proof; prior versions invalid |
| Ticket Atom → Scan Event | 1:N **append-only** | admission attempts; one *admitted* per atom |
| Ticket Atom ↔ Listing | 1:0..1 (native) | a native atom may be listed once at a time; listing locks it |
| Listing → Auction → Bid | 1:0..1 → 1:N (bid append-only) | price discovery; head = highest bid |
| Listing → Market Sale | 1:0..1 | the consummation |
| Market Sale → Ownership Log entry | 1:1..N **immutable, `UNIQUE(cause, cause_ref, ticket_id)`** | a sale causes exactly one transfer **per atom** — one entry per ticket of the sale/lot, each triple append-once; the sale's terminal machine enforces complete-XOR-compensate across the whole set (C26, superseding the C3-era 1:1 two-column form) |
| Market Sale → Payout | 1:N | seller proceeds + venue royalty split |
| Settlement → Settlement Line → (Order/Sale/Refund/Attribution) | 1:N Referenced | every money line traces to a cause |
| Settlement → Payout | 1:N | net paid to the organization |
| Promoter Link → Attribution → Order | 1:N append-only | tracked, credited sales |
| Adapter → Adapter Mapping → (any canonical object) | 1:N Referenced | canonical↔external identity bridge |
| Identity ↔ Ticket Atom (as current_owner) | Derived (head of ownership log) | ownership is never a stored FK column that anyone writes; it is computed |
| Social: Identity ↔ Event Session (attendance) | M:N Derived, privacy-gated | "who's going" is a consented projection, never a source of truth |

Every relationship points **down or sideways-with-a-published-contract**, never up into the kernel. Derived and materialized relationships are rebuildable; append-only relationships are permanent; referenced relationships are to reference data or ledgers, never mutable operational state of another aggregate.

---

## Section 4 — Identity Strategy

**Canonical identifiers.** Every object has an opaque, globally-unique, immutable ID assigned at creation, meaningless in content (no embedded business data, no sequential inference). Conceptually a 128-bit opaque token; the physical form (UUID/ULID/etc.) is an implementation choice this document does not fix. The canonical ID list is frozen by the Naming Constitution (§11): `IdentityID, OrganizationID, VenueID, EventID, EventSessionID, TicketTypeID, InventoryBatchID, InventoryHoldID, TicketAtomID, OwnershipLogID, CredentialID, OrderID, OrderItemID, ListingID, AuctionID, BidID, OfferID, MarketSaleID, TransferID, P2PTransferID, SettlementID, SettlementLineID, PayoutID, RefundID, PaymentID, WalletID, PaymentMethodID, PromoterID, PromoterLinkID, AttributionID, ReferralID, PromotionID, ScanID, StaffRoleID, DoorPinID, ScanDeviceID, AdapterID, AdapterMappingID, MediaID, NotificationID, DisputeID, AuditID, ResalePolicyID, PlatformConfigID`.

**Rules for identity.**
- **Immutable & non-reused.** An ID, once assigned, never changes and is never reissued to a different object — even after that object is archived or anonymized. This is what makes the ledgers eternally dereferenceable.
- **Assigned by the canonical system.** IDs are minted by Snatch It, never accepted from a client or an external provider as the canonical identity.
- **External identities are attributes, not identity.** A Ticketmaster/DICE/AXS id, a Stripe id, a chain address are recorded in an Adapter Mapping (or a typed attribute) keyed by the canonical ID. The canonical ID is the join key everywhere internal; external IDs are join keys only at the adapter boundary.
- **Identity evolution (people).** Profile facts change freely; the `IdentityID` never does. Security-relevant changes append to the identity-event ledger.
- **Merged identities.** When two identities are proven the same human (dedupe, account recovery), one is designated the **survivor**; the other becomes a permanent **alias** recorded in an append-only Merge Ledger pointing to the survivor. Neither ID is deleted; all historical references remain valid and resolve (directly or via the alias) to the survivor. Ownership/ledger rows are never rewritten; resolution is at read time through the alias. **Grant reconciliation is defined, not implicit (C38 — Gate L):** the survivor's capability set follows explicit per-grant-class union rules (org memberships, staff roles, platform roles, seller onboarding) that can never manufacture an escalation neither identity held — conflicts resolve to the *narrower* capability pending review (fail closed) — and the merge **decision itself is dual-controlled** (the "same human" trigger is attacker-influenceable), on top of C15's irreversible, append-only, custody-neutral execution.
- **Deleted identities.** No hard delete. Deletion is **anonymization**: PII is stripped/tombstoned, the `IdentityID` is retained (or repointed to a shared sentinel per the existing account-deletion pattern) so no ledger reference is orphaned. Money/custody history is preserved by law and by invariant. **Erasure is a designed, provable system (C34 — Gate L), not a slogan:** a per-identity DEK lifecycle whose key destruction reaches every backup generation; an enumerated PII-sink inventory + purge (search indexes, notification payloads, name-on-ticket attributes, ID-verification media, processor-side records); retained-event-graph re-identification mitigation; and reconciliation with the 7-year financial-retention obligation (ledger *structure* retained, PII *content* unreadable). No GDPR/CCPA erasure claim is made before C34 is implemented.
- **Object deletion generally.** Canonical objects are archived or voided (state), never physically removed while any ledger references them. Reference data is deprecated, not deleted.

---

## Section 5 — Storage Categories

Every object belongs to exactly one category. This drives durability, retention, backup, and access policy — **without mapping to any specific storage engine.**

| Category | Meaning & handling | Objects |
|---|---|---|
| **Immutable Ledger** | append-only, never updated/deleted; permanent retention; the audit backbone | Ownership Log, Payment, Payout, Refund, Market Sale, Bid, Attribution, Scan Event, Wallet Ledger, Inventory Movement, Admin Audit Entry, Identity-Event, Merge Ledger, Adapter Sync Ledger |
| **Mutable Operational** | current-state rows, guarded by single-writer functions + constraints; changes are frequent and legitimate | Ticket Atom (state), Order, Listing, Auction, Settlement (header), Ticket Type, Inventory Batch/Hold counters, Staff Role, Transfer state, Dispute |
| **Configuration** | tunable values, versioned, snapshot-referenced by what they governed | Platform Config, Resale Policy, Promoter terms, Promotion |
| **Reference Data** | kernel/catalog-written, world-readable, high-value-low-secrecy | Venue, Event, Event Session |
| **Derived Projection** | computed from canonical objects; disposable & rebuildable; never authoritative | current_owner, current_highest_bid, *displayed* inventory availability (the locked counter itself is Operational and authoritative — C27), all read models, Search Index, friend-attendance |
| **Analytics** | append behavioral stream + periodic snapshots; read-mostly; PII-minimized | Event Stream, Analytics Snapshot |
| **Search** | denormalized discovery projection; rebuildable | Search Index Entry |
| **Blob Storage** | large binary in object storage; canonical object is the metadata+key+moderation state | Media Asset |
| **Credential / Secret Storage** | signing keys, tokens — in a KMS/HSM vault, never on a readable row, never shipped to a device; managed under the C33 lifecycle (per-event scope default, audited rotation, compromise runbook, signer HA) | kernel signing keys (C1/C33), payment-method tokens (processor-held), internal secrets |
| **Audit Storage** | tamper-evident, long-retention subset of the ledgers surfaced for compliance | Admin Audit Entry, and audit views over the money/custody ledgers |
| **Temporary State** | short-lived, expiring, reconstructable; never a source of truth | Inventory Hold, `paid_pending_transfer` window, offline-scan queue, outbox rows pending drain |

Retention principle: **Ledger, Audit, and Blob-proof categories are permanent (subject to legal anonymization of PII); Derived/Search/Temporary are freely rebuildable and may be dropped and recomputed at will.**

**Recoverability is designed, not asserted (C47 — Gate L).** "Replayable from the ledgers" is *intra-database* integrity; recovery from substrate loss is a **designed system**: stated RPO/RTO targets, PITR/standby, periodically-drilled restores, and snapshot-based projection-rebuild budgets (a 500M-row full-history replay blows any real RTO). The ledgers and their derived heads are never treated as one indivisible failure domain, and projection-replay is distinguished from substrate DR. Until C47 is implemented, the system is not called "recoverable."

---

## Section 6 — Read Models

A read model is a **projection assembled for a specific surface.** It owns no truth; it is rebuildable from canonical objects. For each: purpose · primary (source-of-truth) objects · derived objects · refresh model · consistency expectation.

| Read model | Purpose | Primary objects | Derived objects | Refresh | Consistency |
|---|---|---|---|---|---|
| **Marketplace Home** | browse/discover live listings | Listing, Event Session, Ticket Type | search index, price-vs-face, watch counts | near-real-time (event-driven) | eventual (seconds) |
| **Event Page** | one event's on-sale + resale | Event, Sessions, Ticket Types, Inventory (remaining), Listings | remaining, "friends going" (gated), resale board | near-real-time | eventual for social/resale; **strong for remaining at checkout** |
| **Venue Dashboard ("Tonight")** | live ops for the next session | Event Session, Orders, Scans, Settlement (open) | sold/cap, door count, gross, alerts, resale royalty | live | eventual (seconds); door count reconciled |
| **Organizer Dashboard** | portfolio across venues/events | Events, Settlements, Payouts | pace vs comparable, net, next payout | periodic + live headline | eventual |
| **Seller Dashboard** | a fan's listings & sales | Listing, Market Sale, Payout | proceeds, status | near-real-time | eventual |
| **Buyer Dashboard / Wallet** | tickets owned, orders, credit | Ticket Atom (owned), Order, Wallet Ledger | current credential, balance, upcoming | live for owned tickets | **strong for ownership/credential** |
| **Admin Dashboard** | moderation, approvals, money ops | Org, Venue, Dispute, Refund, Payout, Audit | risk flags, queues, held payouts | live | strong for money actions |
| **Door Scanner** | admit at the gate | Ticket Atom, Credential (public-key verify), Scan Event | offline manifest (no secret), in-count | shift-start manifest + live when online | **reconcile-after-the-fact offline (C6)**; strong online = a live per-scan authoritative kernel read at the decision point (C37) |
| **Transfer View** | custody chain / troubleshoot | Ownership Log, Ticket Atom, Transfer | timeline, pending claims | near-real-time | strong (from ledger) |
| **Settlement View** | reconcile money per event | Settlement, Settlement Line, Payout, Refund | net waterfall, statement | on close + periodic | strong (ledger-derived) |
| **Social Feed** | venues/friends activity | Follow, Friend Attendance, Event | recommendations | periodic/event-driven | eventual; privacy-gated |
| **Referral Dashboard** | referral progress & rewards | Referral, Attribution, Payout | earned/pending | near-real-time | eventual |
| **Analytics** | who/when/where/driven-by-whom | Analytics Snapshot, Event Stream | cohorts, curves, heat maps | batch + streaming | eventual (minutes) |

**Rule:** the two places that require *strong* consistency at the moment of action are **ownership/credential** (a fan must see the ticket they actually own; a door must fail an invalidated credential when online) and **inventory-remaining at checkout** (no oversell). Everything else tolerates eventual consistency, and its read model is a projection that may lag.

---

## Section 7 — Projection Model

A **projection** consumes canonical objects (and the event log) and produces a derived structure for reads. Projections are rebuildable, own no truth, and never write back into their inputs. Inputs → outputs only.

| Projection | Inputs (canonical sources) | Outputs (derived) |
|---|---|---|
| **Ownership Projection** | Ownership Log (append-only), Ticket Atom identity | `current_owner` per atom; full custody timeline; "tickets owned by identity X" |
| **Credential Projection** | Ticket Atom (id, version, session), kernel signing key (secret) | the current signed credential for the owner; the public-key verification manifest for doors (**secret never included** — C1) |
| **Inventory Projection** | Authoritative batch counters (C27), Holds, Batches, Comps/Guest entries; Movement Ledger (audit cross-check) | *displayed* `remaining/sold/held/reserved` per batch·type·session; the checkout **decision** reads the authoritative locked counter itself, never this projection |
| **Settlement Projection** | Orders, Market Sales, Refunds, Attributions, venue royalties | settlement lines, net waterfall, per-event/period statement |
| **Search Projection** | Listings, Events, Sessions, Venues, price/face signals | discovery index (browse, filter, rank) |
| **Social Projection** | Follows, consented Friend-Attendance, Events | "who's going" (k≥3, opt-in), venue feeds, recommendations |
| **Analytics Projection** | Event Stream + canonical references | cohorts, sales curves, audience/geo/heat, promoter ROI |
| **Notification Projection** | Domain events (outbox), notification preferences | queued/deliverable notifications + delivery state |
| **Venue Projection** | Events/Sessions, Orders, Scans, Settlement (open) | the "Tonight"/dashboard read models |
| **Referral Projection** | Referral Ledger, Attributions, Payouts | referral progress, earned/pending rewards |

**Projection contract:** every projection declares its inputs, is fully rebuildable from them, tolerates being dropped and recomputed, and states its consistency lag. The two projections that must be *strongly* consistent at decision time — **Ownership/Credential** (online door + "what I own") and **Inventory-remaining** (checkout) — read through the authoritative aggregate at the decision point, not a lagging cache. **Rebuildability floor (C48 — Gate L):** a projection whose only inputs are ephemeral events (risk, notify, social) is either guaranteed rebuildable by an input-**retention floor that outbox compaction respects**, or explicitly **marked non-rebuildable** and excluded from the "disposable" claim — "rebuildable" is a checked property, not a default assumption.

---

## Section 8 — Multi-Tenant Architecture

**Tenant = Organization** (and the Venues it operates). Fans/buyers/sellers are **platform-level identities**, not tenants — they exist above and across tenants. This split is the heart of the model: the *supply* side (orgs/venues) is tenant-partitioned; the *demand* side (identities, the marketplace, discovery) is cross-tenant.

**Principals & scope**

| Principal | Scope | Sees |
|---|---|---|
| Global/Platform Admin | platform | everything, audited; never acts as a person-key |
| Support | platform (read-mostly + scoped actions) | cross-tenant for support, audited |
| Organization Owner/Admin/Finance/Marketing/Promoter-Manager | one organization | that org's venues, events, orders, settlements, its customers — **except the money plane, which `org_admin`, `org_marketing` and `org_promoter_manager` never see** (O-1/O-3) |
| Venue Manager / Finance / Box Office / Marketing / Promoter-Manager / Scanner | one venue (or event) | that venue's operations at its label's grain; the scanner grant and the loginless **door session** see only the scan-scope verification projection, never a bulk attendee list |
| Promoter | event/org via link | own links, own attributed sales, own commission — not the back office |
| Seller (fan) | own listings/tickets | own resale activity |
| Buyer (fan) | own orders/tickets/wallet | own purchases and owned tickets |

**Isolation rules.**
- **Supply isolation:** an org/venue reads only its own operational and financial data, and only the *customers who transacted with it* (its CRM slice) — never another tenant's data, and never a customer's activity at other venues.
- **Demand cross-tenancy:** an identity, its wallet, its owned tickets, and the marketplace span all tenants. A fan buys at many venues from one account; the platform retains the cross-venue discovery/identity graph as its own asset.
- **The ticket atom** is visible to its **current owner** (full), the **issuing venue** (for operations/scan), and the **platform** (audit). Never to other tenants.
- **Reference data** (venues, events, live listings) is world-visible by design (discovery).

**Inheritance.** Org-level roles inherit down to the org's venues (an org owner manages all its venues); venue/event roles do not inherit up. Capability is always the *most specific* relationship, scope-qualified (`has_org_role` vs `has_venue_role`, never bare — C-A9). **Inheritance is expressed inside the authorization predicate, never by widening a venue-scoped grant to org labels** — and it is **not a money mechanism at all (O-1)**: the org grant row is **single-valued**, so no `org_owner` row can ever satisfy a test for `org_finance`. Every money authority a role holds is granted to *its own* label explicitly; an inheritance sentence has never been able to grant one, and must not be read as if it could.

**Cross-tenant rules.** The only sanctioned cross-tenant flows are: (a) an identity transacting/holding tickets across tenants; (b) the marketplace matching a seller (any tenant's customer) to a buyer; (c) platform-level discovery/analytics over public data. A venue-scoped principal can never enumerate another tenant's customers, tickets, or finances — enforced at the access layer, fail-closed.

---

## Section 9 — External Provider Model

**Philosophy:** a provider is an **adapter**, never a special case. The canonical model is the truth; the outside world is mapped into it, never the reverse. This is the two-rail model generalized.

**Canonical ID vs External ID.** Internal joins use only canonical IDs. A provider's identifier (Ticketmaster/DICE/AXS/Eventbrite/Universe/Posh order or barcode id, a Stripe id, a chain address) is stored in an **Adapter Mapping** keyed by the canonical object. External IDs are join keys *only at the adapter boundary*; they never become canonical identity and never leak upward into kernel logic.

**Mapping philosophy.** One adapter per provider, each declaring which of five conceptual capabilities it implements: **inventory-sync** (import availability as claims), **issuance-delegation** (mint native atoms under delegated authority), **transfer/delivery** (move a credential on the provider's side), **validation-callback** (ask the provider if a claim is valid — egress-allowlisted, SSRF-guarded, C10), **settlement** (reconcile money). An adapter mapping row bridges exactly one canonical object to one external identity + sync state.

**Synchronization philosophy.** External inventory lands on the **external rail** as *claims* (no ticket atom, no asserted ownership) unless the provider explicitly delegates issuance — in which case native atoms are minted, but the adapter still has **zero authority to write the ownership log directly** (a hard capability denial, not a convention — C10); issuance/transfer go through the same kernel engines with the same owner-authorization. Sync is append-only into an Adapter Sync Ledger; the canonical state is derived, and drift is a reconciliation event, not a silent overwrite.

**Conflict resolution.** For **native** tickets the canonical Ownership Log is authoritative, period. For **external** claims the *provider* is authoritative for validity/delivery; Snatch It holds a claim and adjudicates disputes by evidence (today's external-rail flow). When a sync reports a state that contradicts a canonical claim, the system records both in the sync ledger and raises a reconciliation task — it never blindly mutates canonical state to match an external feed.

**Future blockchain integrations.** A chain is treated as *another adapter/projection*, not a new source of truth. The canonical Ownership Log remains authoritative; a chain may be a **mirror projection** of it, or a chain-native ticket may enter as an **external claim** via an adapter — but per Invariant 3 and the identity rules, an external ledger (chain included) **never determines canonical ownership** unless issuance is explicitly delegated through the same capability-bounded engine. This keeps a decade of provider and chain churn additive: new provider = new adapter + resale-policy mapping, touching no canonical object or invariant.

---

## Section 10 — Data Evolution Rules (permanent)

These are constitutional. Any future migration, API, or feature is illegal if it violates one.

1. **Never delete ledger history.** Ledgers are permanent (PII may be anonymized in place; the entries and their causal structure remain).
2. **Never mutate ownership.** Custody changes only by appending to the Ownership Log through the transfer engine.
3. **Append instead of overwrite.** Correct with a new compensating entry; never edit a historical fact.
4. **Deprecate instead of rename or delete.** Introduce the new concept alongside the old; migrate readers forward; retire the old only when no reader remains — and even then, tombstone, don't erase.
5. **Never reuse an ID.** Retired/anonymized IDs are never reissued.
6. **Never duplicate canonical state.** One fact, one home. A value that appears in two authoritative places is a bug; the second must become a derivation.
7. **No polymorphic ownership.** Ownership references a named aggregate, never a `(type, id)` pair. (Reports may reference a polymorphic *target* for moderation, but that is a report subject, not ownership.)
8. **No hidden state.** Nothing authoritative lives only in a cache, a client, an in-memory value, or an un-ledgered side effect.
9. **No orphan references.** Every reference resolves to a live-or-tombstoned canonical object. Deletion is archive/anonymize, never a dangling pointer.
10. **Additive-only evolution.** New attributes/objects are optional and default to backward-compatible behavior; no change alters the meaning of existing data.
11. **Config is versioned and snapshot-referenced.** An object governed by a policy records which policy *version* governed it, so history is interpretable after the policy changes.
12. **Projections are rebuildable and never the only copy.** A derived structure may always be dropped and recomputed from canonical inputs.
13. **Backward-compatible reads.** A schema change must leave every prior consumer reading a coherent world.

---

## Section 11 — Naming Constitution

These names are **permanent and canonical.** They are the only sanctioned terms in schemas, APIs, services, events, and docs. Synonyms are prohibited to prevent semantic drift.

**Contexts:** `kernel` (identity·money·custody) · `catalog` (reference data) · `venue` (primary ops) · `market` (resale) · `social` · `analytics` · `notify`.

**Core nouns (canonical — do not substitute):**
- **Identity** — the one account (never "user account type"; "user" is acceptable UI shorthand only).
- **Organization**, **Venue**, **Event**, **Event Session** (the admission grain).
- **Ticket Atom** — the single custody truth (never "the ticket record"/"seat").
- **Issued Credential** — the asymmetric admission proof (never "QR"/"barcode"; those are renderings).
- **Ownership Log** — the append-only custody ledger. **Derived Head** — a computed current value of a ledger.
- **Inventory Batch**, **Inventory Hold**, **Comp Allocation**, **Guest List Entry**.
- **Order**, **Order Item**. **Ticket Type**.
- **Listing**, **Auction**, **Bid**, **Offer**, **Market Sale**.
- **Transfer** (external rail), **P2P Transfer** (native).
- **Settlement**, **Settlement Line**, **Payout**, **Refund**, **Payment** (frozen core), **Wallet**, **Payment Method**.
- **Promoter**, **Promoter Link**, **Attribution**, **Affiliate**. **Referral**, **Promotion**.
- **Scan Event**, **Staff Role**, **Door PIN**, **Scan Device**.
- **Adapter**, **Adapter Mapping**. **Resale Policy**, **Platform Config**.
- **Media Asset**, **Notification**, **Analytics Snapshot**, **Search Index**, **Admin Audit Entry**.

**Structural terms:** **Aggregate Root**, **Read Model**, **Projection**, **Ledger**, **Two-Rail** (native / external), **Rail** (`native | external | external_verified`), **Cause** / **Cause Code**.

**Cause-code vocabulary (ownership log & money ledgers):** `issue · primary_sale · comp · door_sale · p2p_transfer · market_sale · auction_sale · admin_action · refund_void · import · promoter_commission · settlement · chargeback`. New causes are added by amendment, never by overloading an existing one. **(D3: this is THE one canonical cause-code registry — the Domain Architecture §5.2.1 vocabulary is this same list, verbatim; any other cause list is a tagged subset of it.)**

**Gate-M money-plane nouns (modeled, built at Gate M — C29/C30/C31):** **Reserve**, **Fan Liability**, **Money Ledger (double-entry) entry** — see §1.1; their canonical IDs join §4 via the Gate-M amendment that builds them.

---

## Section 12 — Scalability Strategy (conceptual)

Deliberately technology-agnostic; states *philosophy and seams*, not mechanisms.

- **Partitioning philosophy.** Ledgers partition by **time** (Ownership Log, Scans, Event Stream, Payments/Payouts) — old partitions are cold, recent partitions are hot. Operational state partitions by **tenant/event** (an org's/event's rows cluster together). The Ticket Atom partitions naturally by **event/session**.
- **Read/write separation.** Authoritative writes go to aggregates under their consistency rules; reads come from projections. The two scale independently — projections can fan out to replicas/materializations without touching the write path.
- **Projection scaling.** Because projections are rebuildable and own no truth, they scale horizontally and can be re-sharded, cached, or moved freely; a lost projection is a rebuild, never an incident.
- **Caching philosophy.** Cache only derived/projection data, invalidated by the source event. **Never** cache authoritative ownership or a credential's validity for a *write/admit decision* while online — verify at the source (C37: the online door's live per-scan kernel read is this rule at the door); offline is the explicit exception with its reconcile/fraud window (C6).
- **Analytics pipeline.** Append event stream → asynchronous rollups → periodic snapshots, fully isolated from the transactional path; analytics load never contends with checkout, transfer, or scan.
- **Cold storage & archive.** Completed events' operational data ages to cold storage; ledgers remain queryable but tiered; PII anonymizes on a retention schedule while causal structure persists.
- **Search indexing.** An asynchronous, rebuildable projection; eventual consistency is acceptable for discovery.
- **Future sharding.** The **aggregate boundaries are the shard seams** — shard by Identity, by Ticket/Event, by Organization/tenant. Per-ticket custody consistency means the atom shards cleanly. The seams that resist sharding are exactly the **SSCAS members (C12, closed by C28)** — every enumerated synchronous cross-aggregate transaction, of which the native sale (C8) is only the canonical example — which is why each member carries a *named future saga* and why the set is closed: an unadmitted synchronous flow would become an unplanned distributed transaction the day these seams shard (C28 — this supersedes the earlier one-seam framing, which undercounted the set). The native sale's cross-region saga/escrow form is the O6 open decision (C50); the single-region MVP builds none of it.
- **Hot-path scaling.** The **inventory counter is the hottest contended row** (C4): shard it into sub-counters or materialize unit-rows for guaranteed sellouts. **Scanning** scales via offline manifests + asynchronous reconciliation (no live DB dependency at the door). **Auction heads** are per-auction and thus naturally distributed. The **ownership-log append** is per-ticket and never a global hotspot.

---

## Section 13 — Architectural Review

Five principal engineers reviewed the model above independently, each instructed to break it and to propose **additive** corrections only. All five returned **YES-IF**: the foundation (ticket-atom, ledger-first custody, derived heads, two-rail, additive evolution) is sound; the gaps are additive fills, surfaced here and ratified in §15.

### 13.1 Database Architect
- **Strength:** the Ledger / Derived-Head / single-writer split is correct and complete for the money and custody objects; storage categories (§5) are clean.
- **Gap — projection rebuild at scale.** "Projections are rebuildable" is true but unbounded: rebuilding a head from a decade-long append log is not free. The model must add **projection checkpoints/snapshots** so rebuild is bounded, not full-history. → **C21**.
- **Gap — money is a scalar.** Inheriting "integer cents" bakes in a single currency. Every money value must be an `(amount, currency, minor_unit)` triple from day one (USD-only now), or multi-currency is a destructive retrofit. → **C13**.
- **Gap — the inventory counter is named as one hot row.** The model should elevate C4's sharded/unit-row counter from an implementation note to a first-class "counter = aggregate of sub-counters" concept so oversell-safety and throughput are both model-level guarantees. → **C22**.
- **Verdict: YES-IF** the derived heads get bounded rebuild and money becomes currency-typed.

### 13.2 Distributed Systems Engineer
- **Strength (with a correction):** the model is unusually self-honest — it pre-flags its own hardest holes (cross-rail seat identity, offline consensus, clawback funding) and correctly keeps the money path *off* the outbox (money rides in-transaction, never eventual).
- **Load-bearing false claim — that the native sale was the *only* synchronous cross-aggregate transaction.** The transactional spine actually contains **~nine** same-transaction multi-aggregate flows (issuance = Order + Inventory/Event + Ticket + Payment; refund-void = Refund + K× Ticket + Listing; settlement→payout; attribution→commission; native listing-create; native transfer-start; native p2p-accept; dispute→freeze; native sale = C8). Routing eight of them through "a kernel function call" does not make them one aggregate — each is a synchronous, multi-aggregate, lock-taking transaction with C8's exact sharding-resistance and deadlock exposure. The instant the aggregate boundaries become the shard seams §12 promises, every unadmitted flow becomes an unplanned distributed transaction with no saga earmarked. → **C12 rewritten as the closed, enumerated SSCAS + a global lock-ordering constitution.** *(This critique caught an internal contradiction between §0.10/§2 and the original C12; both are now reconciled to the SSCAS.)*
- **Gap — event log & command idempotency.** The envelope needs `sequence`/`causation_id`/`correlation_id` and consumers must be dedup-keyed or set-based (no naked increments) so a future outbox→bus migration can't double-count; inbound commands need idempotency keys beyond the ownership-log cause-key constraint (now the C26 three-column key). → **C12, C16.**
- **Gap — an async projection gating a money decision.** A `RiskFlagRaised` that gates a listing/payout/checkout while delivered asynchronously is a correctness/fraud window. → **C24.**
- **Gap — offline first-admit-wins has no comparator, and the freeze omits refund-voids.** → **C23.**
- **Verdict: YES-IF** the SSCAS is enumerated and disciplined (C12/C13-lock-order), the event/command idempotency contract is stated, and offline ordering + void-freeze land (C23).

### 13.3 Staff Backend Engineer
- **Strength:** the model is internally coherent and did not inherit the domain doc's earlier body-vs-amendments drift; §0 anchors, C1–C11, and the object list agree.
- **Gap — grain ambiguity.** Lot/bundle and multi-session-pass ticket grain (A3 = one ticket per session) is stated but the *transfer of a lot* (N atoms, lock order to avoid deadlock) is not modeled at the data level. → note under **C12** (mandate ascending-`TicketAtomID` lock order for multi-atom operations).
- **Right call — deferral.** Wallet, Analytics, Search, Adapter, Social, and the blockchain framing are correctly *constitution-level* (named, categorized) while the roadmap defers their *build*. This is the right separation; the model is guardrails, not a backlog.
- **Watch — operational simplicity.** For two engineers, the number of ledgers is real work; the model should mark which ledgers are MVP (ownership, payment, payout, refund, scan, audit) vs later (wallet, attribution, adapter-sync, identity-event). → clarified in §15 preamble.
- **Verdict: YES-IF** grain/lock-order is pinned and MVP-vs-later ledgers are labeled.

### 13.4 Security Architect
- **Strength:** credential is asymmetric (C1), adapter has zero kernel-custody authority (C10), audit is same-transaction (§0.7).
- **Gap — GDPR erasure vs never-delete-ledger.** "Never delete ledger" (§10.1) and "right to erasure" collide. Resolve with **crypto-shredding**: PII lives in a separable PII vault keyed by `IdentityID`; ledgers reference only the ID; erasure destroys the vault entry / shreds its key, leaving ledger *structure* intact and *content* unreadable. → **C15**.
- **Gap — merge as an attack.** Identity merge (§4) must be **irreversible, dual-controlled, and append-only**, and must never re-attach anonymized PII or move custody — otherwise merge is an account-takeover / de-anonymization primitive. → **C15** clause.
- **Gap — fraud signal home.** Sybil/promoter/wash-trade defense at scale needs a **device/session fingerprint object + an append-only risk-signal ledger** on Identity; today's risk_score has no structured inputs. → **C20**.
- **Must-fix (reaffirm):** no projection (Buyer Dashboard, Credential Projection, adapter mapping) may ever expose the signing secret or a payment token — extend the Phase-0 column discipline to every new sensitive-field object (C9). Confirmed present; flagged as the standing gate.
- **Verdict: YES-IF** erasure is reconciled (crypto-shred) and merge is hardened.

### 13.5 Platform Architect
- **Strength:** additive-evolution rules (§10) and the naming constitution (§11) are strong drift-preventers; the adapter model makes new providers additive.
- **Gap — data residency.** 50 countries + never-delete ledger + erasure needs a **home-region attribute** on Identity and Ticket from day one (all `us` now), with a single authoritative region per ticket — otherwise multi-region is a latent redesign and "two regions own a ticket" is possible. → **C14**.
- **Gap — tax is not modeled.** Future VAT/sales-tax must be a first-class **settlement-line cause + tax context** (zero tax lines today), or it is a destructive retrofit into the money math. → **C19**.
- **Gap — governance of the vocabularies.** Cause codes and event types must be **versioned and registry-governed** (§11 freezes names but not their evolution). → **C18**.
- **Hardest capability to add (honest answer):** **reserved/assigned seating** — it requires a seat atom between Ticket Type and Ticket, which changes the scalar-capacity accounting. Originally judged **non-additive** (H6); **C42 corrects the verdict:** with the now-reserved optional-nullable seat/unit-row hedge (unit-rows ≡ seats, reconciled with C4/C22), the *storage model* is additive — the remaining future cost is the seat-map/selection **UX program**, and "non-additive" holds only if the hedge is skipped. Still out of scope for Miami GA+tables. Multi-currency, tax, residency, and providers are all additive with C13/C14/C18/C19.
- **Verdict: YES-IF** residency, tax, and vocabulary-governance are added now (cheap as attributes/causes) so they never become redesigns.

---

## Section 14 — Red Team (100M users · 50 countries · every provider · fraud · offline · real-time bidding · enterprise)

The board assumed hostile scale and tried to break the foundation. It holds **with additive corrections**; three items must be decided now while cheap.

**Top weaknesses at scale (ranked):**
1. **Instant on-sale thundering herd.** 100k buyers in seconds against one ticket type serialize on the inventory counter. The scalar counter *cannot* hold it. → sharded/unit-row counter is **mandatory, not optional** at scale (**C22**), and holds must expire without a global lock.
2. **Offline-door double-spend as a systemic surface.** Thousands of venues each with an offline manifest window turn C6's per-venue fraud window into a fleet-wide attack: a resold credential can admit at a stale door across many rooms. → the **offline-transfer freeze (C6)** must be per-session-mandatory, and offline admits must carry a signed device+manifest-version so reconciliation can prove which window admitted a clone (**C20** fingerprint + **C12** event ordering).
3. **Cross-rail same-seat double-sell at provider scale.** Multiple providers syncing the same physical seat, plus external→native migration, with **no dedup key (O5)** = systematic double-sell. → a canonical **external-seat-reference** attribute across rails, checked at listing/issuance (**C17**). This is the single most important structural gap the red team confirmed.
4. **Sybil + merge abuse for promoter/referral/wash-trade fraud.** 100M identities with a merge primitive and commission payouts invite farmed accounts and self-dealing auctions. → fingerprint + risk-signal ledger + merge hardening (**C20**, **C15**).
5. **GDPR erasure vs immutable ledgers across 50 jurisdictions.** Non-negotiable legally; unsolvable by "never delete" alone. → crypto-shredding (**C15**).
6. **Multi-region ownership consistency.** Two regions must never both believe they own a ticket. → single authoritative **home region per ticket** (**C14**); cross-region transfer is an explicit hand-off, never concurrent.
7. **Multi-currency + FX at settlement.** Cross-border resale and payout need currency-typed money + FX-rate snapshots. → **C13**.
8. **Projection rebuild + event-log volume.** At 100M, un-checkpointed rebuild and an unbounded outbox are operational failures. → checkpoints/snapshots (**C21**) + event retention/compaction policy (**C18/C21**).

**Latent redesigns (decide now while cheap — not additively fixable later):**
- **Reserved/assigned seating** (the seat atom) — **decided (C42):** the optional seat/unit-row layer is designed *now* as a nullable hedge (unit-rows ≡ seats), keeping the storage model additive; the seat-map/selection UX remains the deferred program. "Non-additive" holds only if the hedge is skipped.
- **Money as scalar vs `(amount,currency)`** — trivially additive *today*, a destructive migration *later*. Do it now (**C13**).
- **Ticket home-region** — a cheap attribute now, a data-migration-across-borders nightmare later. Do it now (**C14**).

**Verdict: YES-IF** — the foundation survives 100M/50-country/fraud scale with additive corrections C12–C22. The one structural bet that must hold is the **ticket-atom + append-only ownership-log as the sole source of custody truth**; every scale problem above is solved *around* that invariant, never by weakening it.

---

## Section 15 — Ratified Corrections (C12–C50, additive & backward-compatible)

Every correction below is **additive** (new attributes/objects/contracts), preserves backward compatibility, and defaults to prior behavior. They extend — never contradict — C1–C11 and §0–§12. C12–C25 came from this document's own five-engineer review (§13); **C26–C50** were ratified 2026-08-24 by the six-reviewer final architecture audit and are written here as ratified constitution text with their implementation gates. *Implementation note for the two-engineer team: only the ledgers marked **MVP** (ownership, payment, payout, refund, scan, audit) are built in the roadmap's Phase 2A–2B; wallet, attribution, adapter-sync, identity-event, risk-signal ledgers are later-phase and are modeled now only so they slot in additively.*

- **C12 — The Sanctioned Synchronous Cross-Aggregate Set (SSCAS), the lock-ordering constitution, and the event envelope.** An honest accounting corrects the earlier single-transaction framing: the money/custody path contains a **closed, enumerated set of synchronous multi-aggregate transactions**, each routed through one choke-point kernel function and each carrying the full C8 discipline (defined lock order, idempotency key, bounded dwell + max-age alarm, a named future saga for eventual extraction/sharding):
  1. **Issuance** — Order → Inventory draw (Event) → Ticket + Ownership-log (+ Payment ref).
  2. **Native sale (C8)** — Market Sale + Listing delist + Ticket + Ownership-log (+ Payout request).
  3. **Refund-void** — Refund + K× Ticket void + Ownership-log + Listing cascade-delist.
  4. **Settlement close → payout** — Settlement + Payout.
  5. **Attribution → commission** — Order + Attribution + Payout request.
  6. **Native listing create** — Listing + Ticket (`resale_state = listed`).
  7. **Native transfer start** — Transfer + Ticket (`resale_state = locked`).
  8. **Native P2P accept** — Transfer + Ticket + Ownership-log + credential bump.
  9. **Dispute open → freeze** — Dispute + Payout freeze.
  10. **Event-cancellation cascade** *(added by C28)* — Event/Sessions + K× Ticket void + Ownership-log + Listing/Auction unwind + Refund initiation.
  11. **Dispute-resolution reversal** *(added by C28)* — Dispute + Payment/Refund effect + Payout release-or-clawback (+ Ticket where custody is affected).
  12. **C25 auto-compensation** *(added by C28)* — Market Sale (`terminal_state='compensated'`) + Refund + Ticket unlock.
  13. **Auction deposit-release** *(added by C28)* — Auction close + bid-deposit hold release (payment-auth void).
  14. **Group-buy claim** *(added by C28)* — the A11 one-legal-door hold: group intent → `venue` inventory hold.
  15. **Wallet checkout** *(added by C28; modeled — wallet is later-phase)* — Wallet-ledger debit + Order.

  The set is **closed at fifteen** (members 10–15 added by C28's closure audit); no sixteenth is added without an amendment. **Lock-ordering constitution (deadlock prevention, completed by C28):** all SSCAS members acquire locks in one global order — `Event/Session → Inventory (ascending batch id, then sub-counter/shard ascending) → Order → Listing → Ticket Atom (ascending TicketAtomID for multi-atom lots/passes) → money-plane rows (Payment / Payout / Reserve / Settlement)` — and **every locked class is placed** (settlement, attribution, dispute, refund, reserve/wallet, auction, and inventory sub-counters included), so deadlock-freedom is provable over the whole set, not asserted for a subset. **Event log guarantees:** every event envelope carries a per-aggregate monotonic `sequence`, plus `causation_id` and `correlation_id`; delivery is at-least-once; every consumer is idempotent by a persisted dedup key OR expresses its effect as an upsert/set-operation (never a naked increment) so replay and reorder — including after a future single-table-outbox → partitioned-bus migration — cannot double-count; poison messages quarantine rather than block the stream, the drainer is partitioned per-aggregate (no head-of-line blocking), and any region hand-off of a stream is a specified protocol, never an implicit 2PC (C49 — Gate L).
- **C13 — Money is currency-typed.** Every monetary value is `(amount_minor, currency, minor_unit)`, not a scalar; cross-currency settlement records an FX-rate snapshot. USD-only today; multi-currency becomes additive.
- **C14 — Ticket & Identity carry a home region.** A single authoritative region per ticket (an immutable issuance attribute where its ownership-log single-writer lives) and a residency region per identity, defaulting to the sole current region. Cross-region ticket movement is an explicit hand-off (one authoritative region at a time — never concurrent ownership). *Consistency honesty:* "tickets owned by identity X" is therefore an explicitly **eventual** cross-shard scatter-gather across regions; the one strong path is the owner's own Wallet/ticket read, which fetches each atom on demand from its home region (cross-region latency accepted and documented — §6/§7 labels corrected accordingly). Enables multi-region + data-residency without redesign and forecloses two-region double-ownership.
- **C15 — Erasure via crypto-shredding + hardened merge.** PII lives in a separable PII vault keyed by `IdentityID`; ledgers reference only the ID. Right-to-erasure destroys / crypto-shreds the vault entry (deleting the key that decrypts it), leaving ledger structure intact and content unreadable — reconciling "never delete ledger" (§10.1) with GDPR. Identity merge is irreversible, dual-controlled, append-only (Merge Ledger), never re-attaches erased PII and never moves custody. Merges are serialized through a **single authority** (a global merge coordinator, or the human's home region) with a monotonic merge sequence, so two regions can never produce divergent alias graphs for the same identity.
- **C16 — First-class command idempotency.** Every money/custody-causing command (checkout, reserve, bid, list, transfer, payout, refund) carries an idempotency key; a repeated key returns the original outcome and never creates a second cause. Complements the ownership-log cause key `UNIQUE(cause, cause_ref, ticket_id)` (C26) at the command boundary.
- **C17 — Cross-rail seat-identity dedup key (resolves O5).** External claims and native tickets may carry a canonical **external-seat-reference** (provider + provider-seat/barcode identity, normalized). Listing and issuance check it to detect the same physical seat across rails, closing the cross-rail double-sell gap. Optional attribute (null for purely native GA), so fully backward-compatible.
- **C18 — Versioned, registry-governed vocabularies.** Cause codes and event types are versioned; new values are added via a governed registry (never by overloading), and event payloads are versioned so consumers evolve safely. Extends §11's name-freeze with an evolution rule.
- **C19 — Tax as a first-class settlement concept.** Tax/VAT is modeled as its own settlement-line cause within a per-jurisdiction tax context; zero tax lines today, so no behavior changes, but future tax is additive rather than a money-math retrofit.
- **C20 — Fraud/risk substrate.** A device/session fingerprint object and an append-only risk-signal ledger on Identity feed `risk_score` (§1.1) with structured inputs (velocity, shared-device, chargeback, scan-anomaly, wash-trade heuristics). Supports Sybil/promoter/wash-trade defense at scale; additive to the existing risk object.
- **C21 — Bounded projection rebuild.** Every derived head/projection supports periodic snapshots + a resume checkpoint so rebuild is bounded (from last snapshot), never a full-history replay. Event log has a retention/compaction policy consistent with the permanent ledgers (the *ledger* is permanent; the *outbox* is compactable once consumed).
- **C22 — Counter as a shardable aggregate.** The inventory counter is model-level defined as an aggregate of sub-counters (or materialized unit-rows) reconciled to `remaining ≥ 0`; oversell-safety and burst-throughput are both first-class guarantees, not implementation afterthoughts (elevates C4).
- **C23 — Offline reconciliation is totally ordered, and the offline freeze covers refund-voids.** Each Scan Event carries a per-device monotonic `scan_sequence` + `device_boot_id`; first-admit-wins is defined as `order by (server_receipt_at, then device_boot_id+scan_sequence for the same device); genuinely-concurrent cross-device admits → fraud queue`. The offline manifest window has an explicit `offline_window_max` bound. Critically, the C6 offline-transfer **freeze is extended to refund-voids**: a ticket cannot be refund-voided (or the venue holds a cash reserve against it) while it sits inside an open offline manifest window — closing the "refunded-at-22:00, admitted-at-a-stale-door-at-22:05" money-loss that the transfer-only freeze left open.
- **C24 — Risk gates read authoritative and fail closed.** Risk/fraud *propagation* is asynchronous, but any write/admit/payout decision that *consults* risk state reads the authoritative risk aggregate synchronously and fails closed on absence (Principle 12) — a lagging projection may never gate money. Prevents the flagged-actor-completes-the-action-before-the-flag-lands window.
- **C25 — `paid_pending_transfer` is bounded, not merely alarmed.** After a hard max-age the window auto-compensates (refund + unlock the ticket) rather than only raising an alarm, so a partition or a stuck sweep can never hold a buyer's funds and a seller's ticket hostage indefinitely.

**Final-audit corrections (C26–C50 — ratified 2026-08-24, six-reviewer board; written here as ratified constitution text).** Gates per `docs/architecture/_governance/CTO_DECISION_MEMO.md`: **Gate P** = pre-native-issuance · **Gate M** = pre-money-rail (native resale + instant payout) · **Gate L** = pre-legal-scale (international / erasure claims / enterprise). Gate-M/L entries are **modeled-only** in the Phase-2 foundation — the constitution reserves the extension point; MVP builds none of them.

- **C26 — Per-ticket idempotency key + per-sale terminal machine (Gate P).** The ownership-log idempotency key is **`UNIQUE(cause, cause_ref, ticket_id)`**: the two-column C3 key was provably wrong for one-cause→many-ticket flows (issuance mints K atoms and refund-void voids K tickets under one `cause_ref`), and per-ticket scoping alone would not block re-void across two refund objects. The second half of the proof is the **per-`market_sale` terminal state machine** `pending → completed XOR compensated`, advanced only under the sale-row lock: a sale either completes (transfer appended) or compensates (refund-void appended) — never both, never twice. Together they restore the "double-transfer physically impossible" guarantee. Integrated: §1.1 Ownership Log, §1.4 Market Sale, §3.
- **C27 — The inventory counter is authoritative; the movement ledger is audit (Gate P).** `remaining` has exactly one definition: the **locked counter** (guarded `remaining ≥ 0`, sharded/unit-row per C4/C22) is the operational truth; the Inventory Movement Ledger is the append-only audit stream; a reconciliation job asserts equality. The one deliberate inversion of the ledger→head pattern. Adjacent pin: **`credential_version` is derived from the ownership log** (advances only inside the transfer transaction, verified against the log head) — never an independent second custody truth. Integrated: §1.1, §1.3.
- **C28 — The SSCAS is genuinely closed and the lock order is complete (Gate P).** C12's set is completed with members 10–15 (event-cancellation cascade, dispute-resolution reversal, C25 auto-compensation, auction deposit-release, group-buy claim, wallet checkout); the global lock order is extended to **every** locked class, including ascending-batch-id inventory acquisition and the money-plane rows, so deadlock-freedom is provable over the whole set; and §12's sharding prose states the many-member truth (the earlier one-seam undercount is gone). Integrated: C12 (above, as amended), §2, §12.
- **C29 — Reserve/Clawback object + payout-timing policy (Gate M; modeled-only).** A first-class reserve/receivable object and a payout-timing policy **gate instant payout**; they fund cancellation refunds, C25 auto-compensations, and post-payout clawback. Instant payout with no reserve is an unrecoverable-loss design and may not ship. (This is what the old open question O1 actually was — a missing object, now named.) Integrated: §1.1 money-plane extension block.
- **C30 — Fan-side liability is representable (Gate M; modeled-only).** A withdrawn fan-seller's chargeback/clawback has a ledger home — a receivable object or Wallet-ledger negative-balance causes; the physical form is fixed by the Gate-M amendment — never an unbookable silent loss. Integrated: §1.1 money-plane extension block.
- **C31 — Double-entry money-ledger schema beside the frozen core (Gate M; modeled-only).** An additive double-entry schema is the recommended home for C29/C30 and makes splits, royalty (today a one-sided credit), rounding residuals, and compensations **balance structurally** — an unbalanced movement becomes a constraint violation, not a leak. The frozen Stripe core is untouched; the custody Ownership Log stays separate (custody is not a balance problem). Integrated: §1.1 money-plane extension block.
- **C32 — Multi-currency is first-class at the frozen money-in boundary (Gate L; modeled-only).** C13's currency triple is extended with the boundary items: FX capture-vs-payout timing, per-country payout currency, and a **named rounding bearer** — specified as additive attributes beside the frozen USD-integer-cents core before any non-US market, never by reopening the frozen bodies. Integrated: C13 (above), §1.1.
- **C33 — Signing-key lifecycle + signer HA (Gate P; the hardest-to-reverse decision in the system).** Per-event key scope by default (per-venue allowed; global discouraged — existential single point); KMS/HSM custody (public key + opaque handle only ever stored); audited rotation with exactly one active signer per scope; a per-scope compromise runbook (revoke, re-issue the affected scope, redistribute public keys); a signer engineered for HA/throughput on the credential hot path; public-key-only distribution to doors; every atom pins its signing key. Integrated: §1.1 Issued Credential, §5.
- **C34 — Provable erasure (Gate L; specified before any erasure claim).** Per-identity DEK lifecycle whose key destruction reaches every backup generation + enumerated PII-sink inventory/purge (search, notifications, name-on-ticket, ID media, processor-side) + retained-event-graph re-identification mitigation + reconciliation with 7-year financial retention. Replaces the bare "crypto-shred solves GDPR" reading of C15. Integrated: §4, C15.
- **C35 — The kernel authorizes the buyer principal itself (Gate P).** At the market→kernel seam the transfer engine derives the acting buyer from the authenticated context and re-verifies it against the payment; a market-supplied buyer id is **never trusted** — the `p_user_id`-trust anti-pattern is banned at the context boundary as it is everywhere else. Integrated: §1.4 Market Sale.
- **C36 — Scope-qualified roles are structural (Gate P).** Org/venue/platform role labels are **disjoint per-plane sets** (three scope-typed enums; no shared label strings), so cross-scope conflation is a type error, not a lint convention. **Label sets finalized by O-2** — the closed fifteen are enumerated at §1.3 Staff Role, with rule RM-1 and the display-name-vs-stored-label distinction stated explicitly at DA §7.1/§7.2; the pre-C36 bare-label lists that survived inside the constitutions themselves are purged (D5). Integrated: §1.3 Staff Role, §8.
- **C37 — The online door reads live; no unqualified "dispute-free by construction" (Gate L; claim corrected now).** An online door performs a live, authoritative per-scan kernel read at the decision point (owner + version + state); the offline window is honestly *shrunk, not closed* (C6/C23). The design's claim is "delivery-dispute-free online, shrunk-and-reconciled offline." Integrated: §1.1 Issued Credential, §6, §12.
- **C38 — Identity-merge grant reconciliation + dual-controlled trigger (Gate L; modeled-only).** The survivor's grants follow explicit per-class union rules that can never manufacture escalation (conflicts fail closed to the narrower capability), and the merge **decision** is dual-controlled (the trigger is attacker-influenceable). Extends C15's hardened-merge clause. Integrated: §4.
- **C39 — Comp/guest-list issuance is stepped-up (Gate L; modeled-only).** Above a per-staff threshold, comp/guest-list issuance requires step-up + a live-table grant re-check — C9's discipline extended to the money-adjacent inventory grant. Integrated: §1.3 (gated venue extensions).
- **C40 — Static platform-controlled callback allowlist (Gate L; modeled-only).** `validation_callback` egress goes only to a platform-shipped static allowlist (never provider- or venue-supplied at runtime — SSRF), and CI asserts the adapter's kernel REVOKE (zero EXECUTE on issue/transfer) on every build. Integrated: §9.
- **C41 — No re-entry in MVP; terminal `scanned` stands; `direction` is the hedge (Gate P decision).** One admitted scan consumes the session's admission; re-entry/pass-outs are a **named future change** whose reserved extension point is the Scan Event's `direction` (`in`/`out`) attribute — a scan-model extension, never a resurrection of the terminal. Integrated: §1.1 Ticket Atom, §1.3 Scan Event.
- **C42 — The seat/unit-row hedge is reserved now (Gate P).** Ticket atoms and inventory carry optional-nullable seat/unit-row references (NULL for GA/table MVP); the C4/C22 unit-rows **are** the future seat atoms (unit-rows ≡ seats). Reserved seating becomes storage-additive; the seat-map/selection UX is the remaining deferred program; H6's "non-additive" verdict holds only if this hedge is skipped. Integrated: §1.1, §1.3, §13.5, §14.
- **C43 — p2p `locked` hard-expires; the freeze is per-ticket (Gate M; state set already spec-canon).** A pending P2P Transfer expires on a hard TTL (physical `expired` terminal; conceptual `requested` ≡ physical `initiated`; no `failed` state) and the atom's `locked` overlay **auto-unlocks** (C25-style bound — the `locked`-meets-C6-freeze deadlock is structurally impossible); cancel-back-to-self is exempt from the offline freeze; the freeze binds per open-manifest ticket, not session-wide. Integrated: §1.4 P2P Transfer.
- **C44 — Virtual queue / bot defense before competitive on-sales (Gate L; modeled-only).** A waiting-room + bot-defense primitive is the named extension gating competitive high-demand on-sales; C4/C22 make sellouts *correct*, not *fair*. Integrated: §1.3 (gated venue extensions).
- **C45 — Table minimum-spend balance + at-the-room settlement (Gate L, pulled to the 2A-tables gate if bottle-service ships; modeled-only).** MVP records the deposit + minimum-spend commitment; the balance and its at-the-room settlement are **explicitly conceded off-platform** until the extension lands — no bottle-service system-of-record claim before it. Integrated: §1.3 (gated venue extensions).
- **C46 — Occupancy, cash, gratuity, door-refund authz (Gate L / 2B; modeled-only).** Fire-code occupancy is a distinct attribute from sold capacity (with a door count that includes non-ticket entries); cash box-office and auto-gratuity/tip-out are named settlement causes; refund-at-door requires an authenticated staff principal — never a loginless door PIN. Integrated: §1.3 (gated venue extensions + Staff Role/Door PIN).
- **C47 — DR is a designed system (Gate L; modeled-only).** "Replayable" ≠ "recoverable": stated RPO/RTO targets, PITR/standby, drilled restores, snapshot-based projection-rebuild budgets (a 500M-row full-history replay blows any real RTO); ledgers and derived heads are never one indivisible failure domain; projection-replay is distinguished from substrate DR. No "recoverable" claim before C47. Integrated: §5.
- **C48 — Projection-rebuild retention floors (Gate L; modeled-only).** Outbox compaction respects a retention floor for canonical inputs; projections fed only by ephemeral events are rebuildable from retained inputs or explicitly **marked non-rebuildable** and excluded from the "disposable" claim. Extends C21. Integrated: §7.
- **C49 — Outbox hardening + region hand-off protocol (Gate L; modeled-only).** Poison-quarantine; a partitioned / multi-drainer outbox (no per-aggregate head-of-line blocking); any region hand-off of an aggregate's stream is a specified protocol, never an implicit 2PC. Extends C12's envelope guarantees. Integrated: C12 (above, as amended).
- **C50 / O6 — Cross-region native resale is a gated open decision (Gate M / pre-multi-region).** C8's single-transaction pin and C14's home-region rule leave cross-region native resale undefined. The two admissible forms are a **saga/escrow** over the same `paid_pending_transfer` money-safety window, or an **explicit intra-region-only scoping** of native resale; the choice is **O6**, a joint commercial + technical decision that must be made before multi-region resale. The Miami single-region MVP builds neither. Integrated: §12, §14.

- **O-1 — Refund authority is a request, not an execution (Gate P; owner ruling, 2026-08-27).** `org_owner` and `org_finance` may **request** a refund on their own org's orders and read the org refund ledger; the server resolves the request into one of three tiers from configured thresholds (immediate execute · in-org dual control with `approver ≠ requester` · platform review), and the caller never chooses. `org_admin` holds no refund authority at all. The Refund row is written by exactly one function whatever the tier (R7 preserved), and a refund covering an already-scanned atom reverses money only — the atom stays `scanned`, inventory does not return, no terminal is re-animated. The org-role inheritance sentence that appeared to grant this is **deleted as a mechanism**: the org grant row is single-valued (C36). Integrated: §1.1 Refund, §8 · DA §7.2/§7.4/§7.5/§7.6.
- **O-2 — Canonical role model (Gate P; owner ruling, 2026-08-27).** The ruling's role list is a list of **display names**; C36 governs **stored labels**; the two-namespace reading DA §7.1 already carried is confirmed. The stored set is the **fifteen** plane-prefixed labels enumerated at §1.3 Staff Role — closed, with rule **RM-1** (every label begins with its plane token). `venue_door` → `venue_scanner`; **`venue_promoter` removed** (a promoter holds no grant row, so escalation is impossible by construction); five labels added for box office, marketing and promoter management at both grains; ambassadors and door sessions enter no enum. Integrated: §1.3 Staff Role, §8, §15 C36 · DA §7.1/§7.2/§7.6.
- **O-3 — Payout visibility and requests, and the SoD trade-off they carry (Gate P; owner ruling, 2026-08-27).** `org_owner` and `org_finance` read the org payout ledger and request payouts; `org_admin` is denied the money plane; a venue finance grant reads settlement-caused payouts for its own venue only (a payout is org-grain and has no venue). **Payout destination change is `org_owner`-only.** This ruling **collapses a separation-of-duties primitive that previously held by construction**, and is ratified **with** its compensating control rather than as an unqualified grant: a **permanent** requester-vs-setter identity split (explicitly not a cool-down, which an attacker waits out), destination probation before the first payout to a new destination, out-of-band notification to every org money principal, step-up, and audited denials. The pre-existing cool-down is retained and demoted to a detection window. Cost, stated: a single-money-principal org is blocked after a destination change and must escalate to the platform. Integrated: §1.1 Payout, §8 · DA §7.2/§7.4/§7.5/§7.6.
- **O-4 — Door-manifest authority (Gate P; owner ruling, 2026-08-27).** Opening/closing the door manifest, moving `door_open_at`, and changing event security configuration belong to `org_owner`, `org_admin`, `venue_manager` only. The scanner grant and the loginless door session may sync an already-open manifest, scan, admit and queue offline scans — and may never create, move or clear the boundary. Box office does not inherit manifest administration. Disabling a transfer freeze is platform-elevated under step-up. **Admission is never gated on manifest state**: the manifest gates *offline* scanning only, and gating admission on it would fail closed against paying fans at the door. Integrated: §1.3 Staff Role/Door PIN · DA §1.8/§7.2/§7.6.
- **O-5 — `door_open_at` lifecycle (Gate P; owner ruling, 2026-08-27).** The boundary is the cached monotone head of an append-only door-episode ledger, written by one authorized action, never cleared, never moved backwards; the effective boundary is total and fail-closed, so a NULL can no longer mean "never frozen". Before this ruling the column was read in four places and written by nothing, which made the C6/C23/C43 transfer freeze — and the stale-pass safety property resting on it — false. Overrides are explicit, platform-elevated, TTL-bounded, reason-coded, audited, and never move the boundary. Integrated: §1.2 Event Session, §1.3 Scan Event · DA §1.8/§3.7/§7.6.
- **C51 / O7 — The event outbox is promised and unscheduled (OPEN).** §2's default cross-aggregate channel, C12's envelope guarantees and DA §6.2/§6.3's "one outbox table and a drainer" have **no scheduled implementation** in any Phase-2 spec; the only mention in the physical schema spec is inside its Gate-L list. Either an outbox package is Gate-P/MVP work missing from the plan, or channel (1) has no MVP carrier and every envelope-emitting design needs a stated alternative transport. **Not resolved.** Integrated: §2, §7, §15 C12 (as a flag, not an amendment).
- **C52 / O8 — The `notify` schema is Gate-P by C7 and do-not-build in every implementation spec (OPEN).** C7 (RATIFIED · Gate P · MVP) names `notify` as one of the seven contexts and §1.6 gives Notification a canonical identity; all four implementation specs defer it to Gate L. **C7 is not amended by this pass.** Either the constitution is right and a `notify` schema is missing Gate-P work, or the specs are right and C7's gate is wrong for this context and MVP notification runs on the pre-existing operational table plus existing edge functions. **Not resolved.** Integrated: §1.6 Notification, §15 C7 (as a flag).

**Net:** with C12–C50, the canonical data model is a sound foundation for native issuance, external providers, venues, promoters, referrals, auctions, buy-now, transfers, settlements, royalties, social, analytics, adapters, multi-currency, multi-region, tax, and future blockchain integration — **without redesign**. Reserved/assigned seating — once the sole acknowledged non-additive future — is now storage-hedged by C42 (nullable seat/unit-row layer; unit-rows ≡ seats): the remaining deferred cost is the seat-map/selection UX program, out of scope for Miami GA+tables and flagged so the decision stays deliberate, not accidental.

---

## Appendix — Correction Index (C1–C52, D1–D8, O-1…O-5)

Every ratified correction, mapped to where this document (and its companion) now states it. Gates: **P** pre-native-issuance · **M** pre-money-rail · **L** pre-legal-scale · **—** doc/ongoing; per-correction ratification detail in `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`. "CDM" = this document; "DA" = `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md`. Statuses: **Ratified·MVP** (Gate-P; implemented before the first native ticket) · **Ratified·gated-ext** (modeled here; built at its gate, not in MVP) · **Doc-fix applied** · **Open-gated**.

| ID | Correction (one line) | Integrated at | Gate | Status |
|---|---|---|---|---|
| C1 | Asymmetric credential; no secret on rows/manifests | CDM §1.1 Issued Credential · DA §10.4 | P | Ratified·MVP |
| C2 | Engine verifies the authenticated acting principal | CDM header · DA §9.4 | P | Ratified·MVP |
| C3 | Double-transfer physically impossible — key as corrected by C26 | CDM §1.1/§1.4 · DA §0.5 C3 | P | Ratified·MVP (corrected by C26) |
| C4 | Oversell = `remaining ≥ 0` on locked (sharded/unit-row) counter | CDM §1.3 · DA §0.5/§5 ¶1.5 | P | Ratified·MVP |
| C5 | Caps via SERIALIZABLE / advisory lock / locked counter | DA §0.5 | P | Ratified·MVP |
| C6 | Offline door = reconcile-after-the-fact + transfer freeze | CDM §1.1, C23 · DA §10.4/§10.6 | P (model) | Ratified·MVP (scope refined by C43) |
| C7 | `core` split into `kernel` + `catalog` | CDM header/§11 · DA §0.5 | P | Ratified·MVP |
| C8 | Native-sale txn boundary pinned (kernel never writes `market`) | CDM §1.4/§2 (SSCAS #2) · DA §0.5/§6.2 | P | Ratified·MVP (region form → C50/O6) |
| C9 | Column-grant / live-recheck discipline everywhere money-adjacent | CDM §13.4 note · DA §7 | P | Ratified·MVP |
| C10 | Adapter zero-custody REVOKE; SSRF allowlist; privacy defaults | CDM §1.5/§9 · DA §13 | P/L | Ratified (allowlist sharpened by C40) |
| C11 | Scope corrections (seat hedge per C42; dual-control seams) | CDM §1.3 · DA §0.5 | P | Ratified·MVP |
| C12 | SSCAS + lock-order constitution + event envelope | CDM §15 C12 (as completed by C28), §2 | P | Ratified·MVP |
| C13 | Money is currency-typed `(amount, currency, minor_unit)` | CDM §15 C13 (extended by C32) | P (attribute) | Ratified·MVP |
| C14 | Home region on Ticket & Identity; one authoritative region | CDM §15 C14 | P (attribute) | Ratified·MVP |
| C15 | Crypto-shred erasure + hardened merge | CDM §15 C15, §4 (extended by C34/C38) | L (claim) | Ratified (superseded-in-part by C34) |
| C16 | First-class command idempotency keys | CDM §15 C16 | P | Ratified·MVP |
| C17 | Cross-rail external-seat-reference dedup key (resolves O5) | CDM §15 C17 | P (confirm) | Ratified·MVP |
| C18 | Versioned, registry-governed vocabularies | CDM §15 C18, §11 | P (governance) | Ratified·MVP |
| C19 | Tax as first-class settlement concept | CDM §15 C19 | L (build) | Ratified·gated-ext |
| C20 | Fingerprint + risk-signal ledger substrate | CDM §15 C20 | M/L | Ratified·gated-ext |
| C21 | Bounded projection rebuild (snapshots + checkpoints) | CDM §15 C21 (floors → C48) | P (model) | Ratified·MVP |
| C22 | Counter as shardable aggregate (sub-counters / unit-rows) | CDM §15 C22, §1.3 | P | Ratified·MVP |
| C23 | Ordered offline reconciliation; freeze covers refund-voids | CDM §15 C23 | P (model) | Ratified·MVP |
| C24 | Risk gates read authoritative, fail closed | CDM §15 C24 | P | Ratified·MVP |
| C25 | `paid_pending_transfer` auto-compensates at max-age | CDM §15 C25, §1.4 | P (model) | Ratified·MVP |
| **C26** | Key `UNIQUE(cause, cause_ref, ticket_id)` + per-sale complete-XOR-compensate machine | CDM §1.1, §1.4, §3, §15 · DA §0.5/§9.4 | **P** | Ratified·MVP |
| **C27** | Counter authoritative, ledger audit, reconciliation job; `credential_version` pinned to the log | CDM §1.1, §1.3, §15 · DA §4/§2 | **P** | Ratified·MVP |
| **C28** | SSCAS closed at fifteen; lock order places every locked class (ascending-batch-id incl.); §12 reconciled | CDM §15 C12/C28, §2, §12 · DA §6.2 | **P** | Ratified·MVP |
| **C29** | Reserve/Clawback object + payout-timing policy gating instant payout | CDM §1.1 money-plane block, §15 · DA §10.5 | **M** | Ratified·gated-ext (modeled only) |
| **C30** | Fan-side chargeback/clawback liability has a ledger home | CDM §1.1 money-plane block, §15 · DA §10.5 | **M** | Ratified·gated-ext (modeled only) |
| **C31** | Additive double-entry money-ledger schema beside the frozen core | CDM §1.1 money-plane block, §15 · DA §10.5 | **M** | Ratified·gated-ext (modeled only) |
| **C32** | First-class currency at the frozen money-in boundary | CDM §15 C32/C13 · DA §10.5 | **L** | Ratified·gated-ext (modeled only) |
| **C33** | Signing-key lifecycle (scope/KMS/rotation/runbook) + signer HA | CDM §1.1 Issued Credential, §5, §15 · DA §10.4 | **P** | Ratified·MVP |
| **C34** | Provable erasure: DEK+backups, PII-sink inventory, retained-graph, retention reconciliation | CDM §4, §15 · DA §8.7 | **L** (spec at P) | Ratified·gated-ext (spec ratified) |
| **C35** | Kernel authorizes the buyer principal itself at the C8 seam | CDM §1.4, §15 · DA §9.4/§5.2.3 | **P** | Ratified·MVP |
| **C36** | Disjoint per-plane role label sets (structural scope) | CDM §1.3, §8, §15 · DA A9/§7.1 | **P** | Ratified·MVP |
| **C37** | Online door = live authoritative per-scan read; honest offline claim | CDM §1.1, §6, §12, §15 · DA §10.4 | **L** | Ratified·gated-ext (claim fixed now) |
| **C38** | Merge grant-reconciliation rules + dual-controlled trigger | CDM §4, §15 · DA §8.7 | **L** | Ratified·gated-ext |
| **C39** | Comp/guest-list issuance step-up + live re-check | CDM §1.3 (gated ext.), §15 · DA §7.5 | **L** | Ratified·gated-ext |
| **C40** | Static platform-controlled callback allowlist + CI-asserted REVOKE | CDM §9, §15 · DA §13.2 | **L** | Ratified·gated-ext |
| **C41** | MVP = no re-entry; `scanned` terminal stands; scan `direction` hedge | CDM §1.1, §1.3, §15 · DA §3.1 | **P** (decision) | Ratified·MVP (decision + hedge) |
| **C42** | Nullable seat/unit-row hedge now; unit-rows ≡ seats; seat-map UX deferred | CDM §1.1, §1.3, §13.5, §14, §15 · DA §5 ¶1.4 | **P** | Ratified·MVP (hedge) |
| **C43** | p2p `locked` hard TTL auto-unlock; cancel-to-self exempt; per-ticket freeze | CDM §1.4, §15 · DA §3.7 | **M** | Ratified·gated-ext (states already spec-canon) |
| **C44** | Virtual queue / bot-defense primitive before competitive on-sales | CDM §1.3 (gated ext.), §15 · DA §5 ¶1.5 | **L** | Ratified·gated-ext |
| **C45** | Table minimum-spend balance + at-the-room settlement, or explicit concession | CDM §1.3 (gated ext.), §15 · DA §5 ¶1.4 | **L** (2A-tables if tables ship) | Ratified·gated-ext (concession explicit) |
| **C46** | Occupancy attribute; cash/gratuity causes; door-refund authz to staff | CDM §1.3 (gated ext.), §15 · DA §5 | **L** (2B) | Ratified·gated-ext |
| **C47** | DR designed: RPO/RTO, PITR/standby, drills, snapshot budgets | CDM §5, §15 · DA Principle 17 | **L** | Ratified·gated-ext |
| **C48** | Projection-rebuild retention floors; non-rebuildable marked | CDM §7, §15 · DA §6.3 | **L** | Ratified·gated-ext |
| **C49** | Outbox poison-quarantine, partitioned drainer, region hand-off protocol | CDM §15 C12/C49 · DA §6.3 | **L** | Ratified·gated-ext |
| **C50** | Cross-region native resale: saga/escrow vs intra-region-only (the O6 decision) | CDM §12, §15 · DA §0.5 C8/§6.2 | **M**/region | Open-gated (O6) |
| **D1** | §2's line-262 single-transaction wording → "an SSCAS member (#2)"; no one-seam/single-exception phrasing survives as current design | CDM §2 Market-Sale row + §0.10/§2/§12/§13 sweeps | — | Doc-fix applied |
| **D2** | No `refunded` ticket terminal — `voided (refund_void)` only | DA §3.1 (diagram + tables); CDM §1.1 already correct | — | Doc-fix applied |
| **D3** | One canonical cause-code registry | CDM §11 ≡ DA §5.2.1 (verbatim) | — | Doc-fix applied |
| **O6** | Cross-region native-resale form — the open decision C50 gates | CDM §15 C50 · DA §0.4 open questions | **M**/region | Open-gated decision (with C50) |
| **O-1** | Refund authority is a **request**, resolved into three server-decided tiers; `org_admin` none; money "inheritance" deleted as a mechanism | CDM §1.1 Refund, §8 · DA §7.2/§7.4/§7.5/§7.6 | **P** | Ratified·MVP (owner ruling) |
| **O-2** | The closed fifteen plane-prefixed stored labels; display names are a separate namespace; `venue_scanner` rename; `venue_promoter` removed | CDM §1.3 Staff Role, §8, §15 C36 · DA §7.1/§7.2/§7.6 | **P** | Ratified·MVP (owner ruling) |
| **O-3** | Payout read + request for `org_owner`/`org_finance`; destination change `org_owner`-only; **collapses SoD-1** — ratified with a permanent requester-vs-setter split, probation and out-of-band notice | CDM §1.1 Payout, §8 · DA §7.2/§7.4/§7.5/§7.6 | **P** | Ratified·MVP (owner ruling) |
| **O-4** | Door-manifest authority = `org_owner`/`org_admin`/`venue_manager`; scanner and door session may sync/scan/admit only; admission never gated on the manifest | CDM §1.3 Staff Role/Door PIN · DA §1.8/§7.2/§7.6 | **P** | Ratified·MVP (owner ruling) |
| **O-5** | `door_open_at` = monotone head of an append-only episode ledger; total fail-closed effective boundary; elevated TTL-bounded overrides | CDM §1.2 Event Session, §1.3 · DA §1.8/§3.7/§7.6 | **P** | Ratified·MVP (owner ruling) |
| **C51** | The event outbox is promised by §2/C12/DA §6.3 and scheduled by no implementation spec — decision **O7** | CDM §2, §7, §15 · DA §6.2/§6.3 | **P** (if the constitution is right) | **Open-gated (O7)** |
| **C52** | `notify` is Gate-P/MVP under C7 and do-not-build in all four implementation specs — decision **O8** | CDM §1.6, §15 C7 · DA §6.2/§6.3 | P per C7 / L per the specs | **Open-gated (O8)** |
| **D4** | The two `O` namespaces disambiguated; neither renumbered | DA §0.4 · ratification record · ARCHITECTURE_FREEZE.md | — | Doc-fix applied |
| **D5** | Pre-C36 bare-label role lists purged from both constitutions; stored labels stated beside display names | CDM §1.3, §15 C36 · DA §1/§1.8/§7.1/§7.2 | — | Doc-fix applied |
| **D6** | DA §7.6 collision resolved — money matrix applied in place, delete-and-point rejected, precedence stated | DA §7.6 | — | Doc-fix applied |
| **D7** | Attribution is written **when the order is paid**, never at order creation | CDM §1.3 Promoter/Attribution · DA §1.7 | — | Doc-fix applied (RPC/RLS correction owed) |
| **D8** | The ratified promoter terms (flat-per-ticket, `tier`, `party_kind`) are not expressible; requirement restated, gap named | CDM §1.3 Promoter · DA §1.7 | — | Doc-fix applied (schema columns owed) |
