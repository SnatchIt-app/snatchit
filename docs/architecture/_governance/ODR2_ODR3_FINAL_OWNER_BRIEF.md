# `ODR-2` / `ODR-3` — Final Owner Brief

**Status:** OWNER BRIEF. **Presents; decides nothing.** `ODR-2` and `ODR-3` remain OPEN, as do events
`#2`, `#5`, `#11`, `#32` and the flagged `#21`.
**Branch:** `docs/odr2-odr3-brief` off `phase2/consolidation` @ `c89fcb4`.
**Supersedes as framing:** `_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` **Decision 2**, which asked
`ODR-2` and `ODR-3` as one lettered choice. That file is **not modified** by this one and remains the record of
Decisions 1 and 3–6.
**Reads from and does not overturn:** `_governance/G25_CANONICAL_EVENT_CATALOG.md` (per-event authority) and
`_governance/G25_FOUR_EVENT_OWNER_BRIEF.md` (the four open events and the three carrier totals). Five places
where evidence read at head extends or corrects them are marked **`DELTA`** and shown with the authority that
forces them.
**Creates nothing, changes nothing.** No existing document is modified. No `OFFLINE-VERIFY-v1` block is touched.

**Two rules, inherited and binding here.** No count appears without its enumeration beside it. Every claim is
**`VERIFIED`** (read at the cited file and line on this branch, or read in `supabase/migrations/`) or
**`INFERENCE`**. **No approximation is authored by this document.** The only `~` characters below appear in
verbatim quotations of corpus text that cannot be discussed without being quoted — `C11`'s own
*"~10 … + ~6"* (three occurrences) and the notifications spec's *"~200 ms window"* (one). **Every count this
brief asserts carries its enumeration beside it.**

### Reference — the objects the two decisions name, enumerated once

**`ODR-2`'s object — one table.** `notify.outbox` / `kernel.event_outbox`: `outbox_id · event_type ·
aggregate_kind · aggregate_id · sequence · causation_id · correlation_id · event_key · payload · occurred_at ·
state · claimed_until · attempt · last_error · created_at`, with `UNIQUE (event_type, event_key)`,
`UNIQUE (aggregate_kind, aggregate_id, sequence)` and one partial index. Plus **one** RPC,
`notify.drain_outbox(p_limit int)`, and **one** cron entry. `VERIFIED` (NOTIF `:733`–`:738`, `:756`–`:760`).

**`ODR-3`'s object — nine tables, twenty-three RPCs, two edge functions, three cron entries, two client
surfaces.** Enumerated so no count below is bare:

- **Nine tables** (NOTIF §6.1 `:1002`–`:1012`): `notify.notification_type` · `notify.notification` ·
  `notify.delivery` · `notify.preference` · `notify.identity_channel_state` · `notify.outbox` ·
  `notify.schedule` · `notify.announcement` · `notify.template`. `VERIFIED`
- **Twenty-three RPCs** (Appendix B `:1557`; §6.3 contracts only the first twenty-two — see `DELTA-4`):
  *internal, `service_role`* — `emit_event` · `enqueue` · `channel_enabled` · `drain_outbox` ·
  `sweep_scheduled` · `claim_deliveries` · `record_delivery_result`; *consumer-facing, `authenticated`* —
  `get_inbox` · `get_unread_count` · `mark_read` · `mark_all_read` · `dismiss` · `get_preference_matrix` ·
  `set_preference` · `register_push_token` · `revoke_push_token` · `report_announcement`; *staff-facing,
  role-gated* — `draft_announcement` · `preview_announcement_audience` · `approve_announcement` ·
  `cancel_announcement` · `revoke_announcement`; *indexed but uncontracted* — `resolve_web_link`. `VERIFIED`
- **Two edge functions:** `notify-dispatch` · `notify-receipts` (plus shared modules `_shared/notify-auth.ts`,
  `_shared/email.ts`). `VERIFIED`
- **Three cron entries:** `notify-dispatch` `* * * * *` · `notify-receipts` `*/15 * * * *` ·
  `notify.sweep_scheduled()` `*/5 * * * *`. `VERIFIED` — see `DELTA-4`.
- **Two client surfaces:** the mobile notification centre (`NEW RN SURFACE`) · the venue-staff surface
  (`NEW DASHBOARD SURFACE`, dashboard §16.5 + the announcement composer). `VERIFIED`
- **Sixty-seven registry rows** = **40** new Phase-2 type keys + **12** legacy inbox types + **15** legacy push
  `data.type` values. `VERIFIED` (NOTIF §2.3 `:477`).

**The twenty-four MANDATORY types, enumerated** (NOTIF §2.3 `:472`), because `O-N3` turns on nineteen of them
naming `E`: `purchase_confirmed` · `ticket_ready` · `purchase_failed` · `transfer_received` ·
`transfer_accepted` · `listing_sold` · `ownership_changed` · `payout_released` · `payout_failed` ·
`payout_on_hold` · `event_time_changed` · `event_venue_changed` · `event_cancelled` · `event_postponed` ·
the four Group-F refund types (`refund_requested` · `refund_approved` · `refund_completed` · `refund_failed`) ·
the five Group-S security types (`security_password_changed` · `security_payout_destination_changed` ·
`security_org_role_granted` · `security_org_role_revoked` · `security_payout_method_added`) ·
`staff_payout_failed`. `VERIFIED` — count and membership, read at §2.2 Groups P/T/R/E/F/S/V and §2.3 `:472`.
**`security_email_changed` is not among them and is deliberately not specified**, NOTIF §2.2 `:435`–`:438`
inheriting `0600:9-20` verbatim — *"a false 'your email was changed' security alert is worse than none."*
`VERIFIED` It is `O-N13`, recorded and not designed.

**The four capability families the register prices as *"unimplementable as designed, not merely degraded"*
under `ODR-2 = [B]`, enumerated:** the Apple Wallet push path (carrying *"no admissible alternative design"*) ·
the door-manifest open transaction as specified · scanner push-to-sync · every notification. `VERIFIED`

---

## 0 — READ THIS FIRST: these are two objects, not one

The single most important thing this brief does is stop one implication.

> *"Notifications need an outbox"* is true.
> *"An outbox means we must build the notification platform"* **does not follow, and is false.**

They are different objects, with different costs, different failure modes and different owners of the
consequence.

| | **The outbox** (`ODR-2`) | **The `notify` platform** (`ODR-3`) |
|---|---|---|
| **What it physically is** | **one table** + **one `service_role` RPC** + **one cron entry** | **nine tables** + **23 RPCs** + **2 edge functions** + **3 cron entries** (see `DELTA-4`) + **2 client surfaces** |
| **Package** | **`076`** — zero FK dependencies, no producer package gains an edge | **`092`** — floored there by `SEAM-1`; makes the band `076`–`092` and seventeen |
| **What it buys** | transactional hand-off, at-least-once with per-aggregate ordering, retry, post-commit sequencing | preference enforcement, a delivery ledger, dedupe on the push rail, a mobile inbox, templates, announcements, email/SMS readiness |
| **Who consumes it** | `wallet-pass-push`, the scanner, `venue`, `market`, `risk`, the dashboard — **and** `notify` | end users and venue staff |
| **What breaks without it** | Apple Wallet push (**no admissible alternative design**), the door-manifest open transaction as specified, scanner push-to-sync | the notification *product*: preferences stay inert, no mobile inbox, no delivery visibility |
| **Failure mode if built** | a drainer that stops silently | complexity — nine tables, three crons, two uncontracted RPCs, on a path with zero Sentry |
| **Cost of retrofitting later** | **high** — reopens every money and custody producer | **low** — purely additive; the outbox is already there to read |

**The implication runs one way and one way only.** `notify` cannot be built without an outbox, because
`PHASE_2_NOTIFICATIONS_SPEC.md` §4.1's five hops route through `notify.outbox` — hop 2 *is* the outbox.
`VERIFIED` (`:674`–`:694`). **The outbox can be built without `notify`, and fourteen of the twenty-one facts it
would carry have consumers that have nothing to do with notifications.** That asymmetry is `COND-D`, and it is
the whole reason these are two decisions in one sitting rather than one decision.

**Order.** `ODR-2` first, then `ODR-3`, same sitting. `COND-D` fixes the order; it does not merge the questions.

---
---

# `ODR-2` — Build the transactional event outbox in Phase 2?

## A. The decision, in plain English

When something important happens — a ticket changes hands, a payout fails, a door manifest opens — the
database writes one small row that says *"this happened"*, **in the same transaction as the thing itself**. A
background job picks that row up a couple of minutes later and does the follow-on work: refresh the Apple
Wallet pass, tell the scanner to re-sync, send the notice.

You are deciding whether that one row exists.

**You are not deciding** whether Snatch It sends notifications (it already does, in production). You are not
deciding the schema name, the package number, or whether push tokens get their own table — those are
mechanical and are removed from your set below.

## B. Why it is the owner's

Three reasons, each on the record.

1. **The constitution promises it and no implementation spec schedules it.** `SNATCH_IT_DOMAIN_ARCHITECTURE.md`
   `:1263`: *"the only new infrastructure Phase 2 introduces is **one outbox table and a drainer on the cron
   that already runs**."* `VERIFIED` Registry `COND-A` `:761`: *"**No implementation spec schedules one.**"*
   `VERIFIED` Closing that gap means either building it or amending the constitution. Amending a ratified
   constitution is an owner act.
2. **The corpus refuses to decide it, in writing.** `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`: *"**This is a
   conditional package element and this integration does NOT decide it.**"* `VERIFIED` (quoted in the register's
   `ODR-2` entry and in `_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` `:117`).
3. **Silence is UNSAFE and it ships a security defect, not a smaller product.** Register, `ODR-2`, *"Which way
   silence falls"*: no outbox is built, four capabilities become *"unimplementable **as designed**, not merely
   degraded"*, and the Wallet push path has *"**no admissible alternative design**"*. `VERIFIED`

**Mechanical — remove from your set.** The schema name (`notify.outbox` vs `kernel.event_outbox`); the package
number (`076`, fixed by zero FK dependencies); the drainer's batch limit; the retention window. **See §I's
condition 1** — a naming discipline makes the schema home genuinely mechanical rather than a hostage to
`ODR-3`.

## C. The options

- **`[A]` BUILD** — `kernel.event_outbox`/`notify.outbox` at package `076`, one `service_role` drainer RPC on
  the two-minute cadence. The constitution is right; the implementation specs are incomplete.
- **`[B]` WITHDRAW** — amend `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.2/§6.3 and `C12` to stop claiming an outbox
  exists in Phase 2, and give every design that emits an envelope a **stated alternative transport**. The
  implementation specs are right; the constitution over-promised.

There is no third option. Schema spec, quoted in the register: *"**There is no third option in which DA:1253
stands and nothing implements it.**"* `VERIFIED`

## D. What each option means

| Dimension | **`[A]` BUILD** | **`[B]` WITHDRAW** |
|---|---|---|
| **Product** | Wallet passes update when custody moves; scanners re-sync on manifest change; notices fire from facts, not from polls | Apple Wallet ships without a working push path or not at all; the door-manifest open transaction *"cannot be authored as specified"* |
| **Venue / operator** | door open, close, freeze, drain, supplement and invalidate all carry an envelope written inside their own transaction; scanners disarm on `#44` *"immediately"* (DOOR `:604`) | door staff hold devices whose manifest can go stale with no push path; `#43`'s *"so online devices re-sync promptly"* (DOOR `:826`) has no transport |
| **Security** | Wallet supersession runs post-commit, where two ratified invariants require it (§E-bis 1) | **a previous owner keeps a live pass.** That is a door-fraud primitive on a custody platform |
| **Privacy** | `notify.outbox.payload` *"never contains a recipient list"* and never contains rendered copy — only ids and scalars (NOTIF `:747`). `VERIFIED` One more deny-all table (`REVOKE ALL FROM anon, authenticated`, RLS on, zero policies — the `0600:91-92` posture) | no new store, so no new privacy surface. This is the only dimension on which `[B]` is genuinely cheaper |
| **Complexity** | **one table, two unique constraints, one partial index, one RPC, one advisory lock, one cron entry.** Nothing in that construction scales with the number of event types | every emitting design needs a *stated alternative transport*, designed and written, one at a time — and the register already records that four capability families have none |
| **Future flexibility** | the catalog is the durable artifact and *"the transport is replaceable underneath it"* (DA `:1263`). Adding an event later is one `INSERT` | **retrofitting an outbox later reopens every money and custody producer.** This is the asymmetry that decides the timing |
| **Migration / package** | `076`. Zero FK dependencies, *"so no producer package gains an edge"* (registry `:761`). Rollback is a `DROP TABLE` on a table nothing references | a constitutional amendment plus edits to DA §6.1, §6.2, §6.3, `CDM` `C12`, `PHASE_2_APPLE_WALLET_SPEC.md` §6.3/§16, `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §6/§12.2 and `PHASE_2_NOTIFICATIONS_SPEC.md` §4 — and a new design for each |

## E. Failure mode, per option

**`[A]` BUILD — the drainer stops and nobody notices.** This is the real risk and it is not hypothetical here:
**this codebase has lost a cron job twice** (§E-bis 7). Wallet passes stop refreshing, scanners stop
re-syncing, and there is no error, no log line and no failing test. The mitigation is cheap and is condition 2
in §I.

**`[B]` WITHDRAW — a superseded Apple Wallet pass stays live in a previous owner's phone.** Registry §7
`:770`–`:774`, `VERIFIED`: the two alternatives to the outbox consumer — *"moving it into the custody
transaction or leaving a superseded pass live"* — are ***both prohibited by ratified invariants***. `[B]` does
not choose between them. It leaves the second one in place by default.

---

## E-bis. The record, item by item

*Placed between the failure modes and the recommendations so that both recommendations below are checkable
against the same evidence. Every row is `VERIFIED` unless marked.*

### 1. Apple Wallet — the security-grounded forcing argument, stated precisely

`kernel.supersede_wallet_passes_for_atom(p_atom_id, p_reason_code)` is **`service_role`/definer only** and is
*"Called from the **outbox consumer, not inside the custody transaction** — a Wallet failure must never be able
to roll back or block a transfer."* — `PHASE_2_APPLE_WALLET_SPEC.md` §11.6 `:1297`. `VERIFIED`

§16's invariant table preserves it as a property, not a preference: *"the pass registry is entirely outside the
custody path; supersession runs in the **outbox consumer**, so Wallet can never block or roll back a
transfer"*, verdict **✔ preserved**. — Wallet `:1741`. `VERIFIED`

**The forcing argument has three places and only three.** Given that a pass must be superseded when custody
moves, the supersession call can run in exactly one of:

1. **inside the custody transaction** — **prohibited.** It makes a Wallet failure able to roll back a transfer,
   which the invariant above forbids by name;
2. **outside the custody transaction, driven by a durable post-commit record** — this is the outbox consumer,
   and it is what the spec specifies;
3. **nowhere** — **prohibited.** A superseded pass stays live in the previous owner's phone.

Registry §7 `:770`–`:774` states 1 and 3 together: *"the two alternatives, moving it into the custody
transaction or leaving a superseded pass live, are **both prohibited by ratified invariants**."* `VERIFIED`

**So `ODR-2 = [B]` does not shrink Wallet's scope. It selects option 3.** A live pass in a previous owner's
hand is a **door-fraud primitive**: it is a credential that admits a person who no longer holds the ticket, at
a door that is by ratified design (`C6`) a reconcile-after-the-fact window rather than a real-time check. This
is why `ODR-2` is a **security** decision before it is a scope decision.

Wallet §6.3 `:686`–`:700` names **six** triggers, drained by `wallet-pass-push` (package `084`), *"Driven by
the existing outbox"* — **two of them unconditional**: `credential_version` bump (custody move, void) →
**always, unconditionally**; and session time / venue / status change + `catalog.cancel_event` → **always**.
The other four are best-effort: atom → `scanned`; `resale_state` change; `#40 DoorManifestDrained`; pass-type
certificate rotation. `VERIFIED`

### 2. Door lifecycle — the eight events that postdate the `C11` trim, plus the drain

`C11`'s trim text, read in full at `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §0.5 `:93`: *"The 36-event catalog is
trimmed to the ~10 invariant-bearing sync calls + ~6 real outbox events."* `VERIFIED` It reaches events `#1`–`#36`
and nothing else.

`PHASE_2_DOOR_LIFECYCLE_SPEC.md` §12.2 `:1586`: *"Numbering continues the domain-architecture §6.1 catalog
(which ends at 36)."* `VERIFIED` **Eight events postdate the trim entirely, enumerated:**

| # | Event | Sync/Async, in DOOR's own words | Consumers that are not `notify` |
|---|---|---|---|
| **37** | `DoorManifestOpened` | **Sync** — *"written to the outbox inside the open txn"* (`:1577`) | **scanner push-to-sync**, analytics, risk |
| **38** | `DoorManifestClosed` | **Sync** (`:1578`) | reconciliation monitor, analytics |
| **39** | `TransferFreezeEngaged` | **Sync** for `explicit_open`; **Async (sweep)** for `implicit_doors_time`; *"at most once per session, ever"* (`:1579`) | `market` (invalidate cached eligibility), analytics |
| **40** | `DoorManifestDrained` | **Sync** *(same txn as the drain)* (`:1580`) | `wallet-pass-push` (best-effort; one of Wallet §6.3's six triggers), analytics |
| **41** | `DoorFreezeOverrideGranted` | **Sync** (`:1581`) | `risk`, analytics |
| **42** | `DoorFreezeOverrideEnded` | Async (`:1582`) | `risk`, analytics |
| **43** | `DoorManifestSupplemented` | **Sync** *(same txn as §7.7)* (`:1583`) | **scanner push-to-sync**, analytics |
| **44** | `DoorManifestInvalidated` | **Sync** (`:1584`) | **scanner (drop M2, disarm)**, dashboard alert, risk |

§12.2's closing note is the decisive sentence for `ODR-2`, and it is decisive in the direction of building:

> *"None of these are money or custody events; none ride the transactional spine (§6.2 of that document)
> **except as outbox rows written inside their own transaction**."* — DOOR `:1586`–`:1588`. `VERIFIED`

**The all-or-nothing constraint is explicit.** `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §6 step 11 `:492` — *"INSERT
outbox envelopes `DoorManifestOpened` (+ `TransferFreezeEngaged` on first open only)"* — followed at `:494` by
*"Commit. **Steps 5–11 either all commit or none do.**"* `VERIFIED` There is no version of the door-manifest
open transaction as specified in which step 11 is absent.

**The door-manifest drain, specifically.** `#40` is produced by `market.on_door_freeze_engaged`, a `SEAM-2`
hook running in the same transaction as the drain, stub `086` → body `088` (`C110`). Its payload is
`session_id, manifest_id, cancelled_transfer_ids[], cancelled_listing_ids[]` and its consumers are `notify`
(per affected party) **and** `wallet-pass-push`. `VERIFIED` It is simultaneously a door event, a `Sync` event
and a Wallet trigger — which is why it appears in all three of §E-bis 1, 2 and 4.

**Two scanner behaviours depend on an envelope arriving and on nothing else.** DOOR `:826` — `#43` is emitted
*"so online devices re-sync promptly"*; DOOR `:604` — `#44` is emitted *"so online devices disarm
immediately"*, and `:907` records that a cached M2 is dropped on receipt. `VERIFIED`

### 3. Payout events — what actually needs a post-commit carrier on the money plane

**Six numbered facts touch the outbox on the money plane, enumerated:** `#9 PaymentCaptured` ·
`#25 PayoutReleased` · `#26 PayoutFailed` · `#27 RefundIssued` · `#31 AttributionRecorded` ·
`#32 PromoterCommissionAccrued` *(the sixth is conditional on `ODR-3`)*.

**Of those six, exactly two are `Async` in `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1 with no `Sync` arm, and are
therefore the only two whose *only* transport is a post-commit carrier:**

- **`#25 PayoutReleased`** — DA `:1208`, producer `payout-execute` → `kernel.release_payout`, consumers
  *venue, market, notifications, analytics*, key `payout_id`, classified ***"Async (deferred by design)"***.
  **It is the only row in the whole 44-row catalog whose asynchrony is itself ratified rather than incidental.**
  `VERIFIED`
- **`#26 PayoutFailed`** — DA `:1209`, producer `payout-execute` → `kernel.mark_payout_transfer_state`,
  consumers *venue/market, notifications, risk*, key `payout_id + attempt`, **Async, no `Sync` arm.** It is the
  only row carrying **two** MANDATORY notification fan-outs: `payout_failed` (to the payee) and
  `staff_payout_failed` (to venue staff, `CONFLICT-5`). `VERIFIED`

**The other four write their money in-transaction and put only the notice on the carrier.** `#9`'s capture is
`Sync` with issuance (DA `:1192`); `#27`'s refund is `Sync` with the ticket void (DA `:1210`); `#31`'s accrual
is frozen in the same transaction that marks the order paid, by ratified `D7` (`PHASE_2_PROMOTER_CODES_SPEC.md`
`:282`, `:800`); `#32`'s commission line and payout row are both written inside `kernel.close_settlement`
through the `kernel.settlement_commission_lines` `SEAM-2` hook (plan `:1176`, `:1501`). `VERIFIED`

> **The money-plane finding, stated plainly: the outbox never carries money. It carries the fact that money
> moved.** Every money write in the enumeration above is same-transaction under the `SSCAS` and the global lock
> order, and stays so under both options. `ODR-2 = [B]` does not make the money plane less safe; it makes the
> *notice* that money moved undeliverable. The two rows for which that is the whole story are `#25` and `#26`,
> and `#26`'s two fan-outs are both MANDATORY.

Registry `:777` records the money plane as **unaffected** by `COND-A`: *"**Unaffected:** CRM export …,
demographics, promoter codes, and money authority — each carries its own scheduler."* `VERIFIED` **That line is
correct about the money *writes* and is contradicted sixteen lines above it, at `:761`, about the
commission-accrual *notice*.** `G25_FOUR_EVENT_OWNER_BRIEF.md` §6.4 sets out that contradiction in full and
recommends the correction — *"no async **in the money path**"* — under **both** rulings. This brief carries that
forward and does not re-argue it.

### 4. Post-commit effects from `Sync` transactions — the category the corpus has repeatedly miscounted

> **"Sync" means the transaction is synchronous. It does not mean there is no outbox row.**

`SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.2's own sequence diagram settles this at `:1242`, inside the
all-or-nothing custody transaction:

> `CORE->>OUT: enqueue OwnershipTransferred, PaymentCaptured, CredentialInvalidated`
> …
> `Note over CORE,OUT: commit → all-or-nothing. Outbox drained later on cron.` — DA `:1242`, `:1244`. `VERIFIED`

All three of those are classified **`Sync`** in §6.1. The transaction is synchronous; the downstream reaction is
not. **Seven `Sync` events in the §6.1 catalog still need a post-commit outbox row. All seven, enumerated:**

| # | Event | `Sync` classification, DA §6.1 | Producer | Why a post-commit row is still required |
|---|---|---|---|---|
| **9** | `PaymentCaptured` | *"**Sync** with issuance/transfer"* (`:1192`) | `stripe-webhook` → `venue.finalize_primary_order` (`085`, `C111`) | DA §6.2's diagram enqueues it inside the custody txn; `purchase_confirmed` is **MANDATORY** |
| **10** | `TicketIssued` | *"**Sync** (same tx as capture on primary)"* (`:1193`) | `kernel.issue_ticket_atoms` (`083`, `C114`) | `ticket_ready` is **MANDATORY** |
| **17** | `OwnershipTransferred` | *"**Sync** (the transfer itself)"* (`:1200`) | `kernel.transfer_ticket_ownership` (`088`, `FR-3`) | **Wallet `credential_version` bump — always, unconditionally**, and it must run outside the transaction (§E-bis 1); `ownership_changed` is **MANDATORY** |
| **22** | `ScanAdmitted` | *"**Sync** online; **outbox-reconciled** offline"* — §6.1's own words (`:1205`) | `venue.record_scan` (`086`) | the offline arm names the outbox in the classification itself; atom → `scanned` is a Wallet trigger |
| **27** | `RefundIssued` | *"**Sync** with ticket void (if full)"* (`:1210`) | `kernel.refund_primary_order` (`085`) | `refund_completed` is **MANDATORY** |
| **28** | `TicketVoided` | *"**Sync** with refund"* (`:1211`) | `kernel.void_ticket_atom` (`085`) | **the void path is the second driver of `supersede_wallet_passes_for_atom`**, definer-only, *"called from the outbox consumer, not inside the custody transaction"* (Wallet `:1297`) |
| **31** | `AttributionRecorded` | *"Sync (same tx as OrderPaid)"* (`:1214`) | `venue.resolve_order_attribution` (stub `085` → body `090`) | the money write is same-tx by ratified `D7`; **only the notice is eventual** |

**Where Wallet supersession and the door-manifest drain live in this table.** Wallet supersession is driven by
**`#17`** and **`#28`** — the two rows above whose Wallet trigger is *"always, unconditionally"*. The
door-manifest drain is **`#40`**, itself marked ***"Sync (same txn as the drain)"*** in DOOR §12.2 `:1580`, and
is counted among the eight door events of §E-bis 2 rather than among these seven, because DOOR §12.2 and not
DA §6.1 classifies it. Six further door events — `#37`, `#38`, `#39` (`explicit_open` arm), `#41`, `#43`,
`#44` — are likewise `Sync` **in their own transaction** and write an outbox row there. `VERIFIED`

**So the `Sync`-with-a-post-commit-row population is seven under DA §6.1 and fifteen once the door plane is
included.** Enumerated: **`#9 · #10 · #17 · #22 · #27 · #28 · #31`** (DA §6.1) **+ `#37 · #38 · #39 · #40 ·
#41 · #43 · #44`** (DOOR §12.2; `#42` is Async). Every count of *"real outbox events"* that reads only the
`Async` column misses all fifteen.

### 5. The exact event count, under all three scenarios, each fully enumerated

Carried from `G25_FOUR_EVENT_OWNER_BRIEF.md` §2.3–§2.6, re-read at head. **Gate-M events are excluded; this is
the Gate-P load.**

#### Scenario 1 — all four unresolved events REMOVED — **19 numbered + 1 unnumbered = 20 facts**

`#3 VenueApproved` · `#4 EventPublished` · `#9 PaymentCaptured` · `#10 TicketIssued` ·
`#17 OwnershipTransferred` · `#22 ScanAdmitted` · `#25 PayoutReleased` · `#26 PayoutFailed` ·
`#27 RefundIssued` · `#28 TicketVoided` · `#31 AttributionRecorded` · `#37 DoorManifestOpened` ·
`#38 DoorManifestClosed` · `#39 TransferFreezeEngaged` · `#40 DoorManifestDrained` ·
`#41 DoorFreezeOverrideGranted` · `#42 DoorFreezeOverrideEnded` · `#43 DoorManifestSupplemented` ·
`#44 DoorManifestInvalidated` — **nineteen**
**plus one unnumbered:** the **event-cancellation** fact (`catalog.cancel_event`), consumed by three ratified
surfaces — `event_cancelled` (**MANDATORY**, sourced *"SSCAS #10 event-cancellation cascade"*), Wallet §6.3's
*"session time / venue / status change, `catalog.cancel_event`"* trigger (**always**, source *"catalog
outbox"*), and DOOR §7.2.1 → `#44`. `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1 numbers no cancellation event, which
is why the notification trigger cites an `A-SSCAS` member instead of an event number.

> Of the twenty: **8** postdate `C11` (`#37`–`#44`) · **7** are DA §6.1 `Sync` events needing a post-commit row
> (`#9 · #10 · #17 · #22 · #27 · #28 · #31`) · **4** are `C11`-sense outbox events (`#3 · #4 · #25 · #26`).
> **This is the floor. It is not zero.**

#### Scenario 2 — engineering-recommended choices applied — **20 numbered + 1 unnumbered = 21 facts**

*(`#2` REMOVE · `#5` RENAME then REMOVE-until-Gate-M · `#11` REMOVE · **`#32` KEEP**.)*

Scenario 1's nineteen, **plus `#32 PromoterCommissionAccrued`** — producer `kernel.pay_promoter_commission`
(uncontracted, `G-7`), reached by `kernel.close_settlement` via the `kernel.settlement_commission_lines`
`SEAM-2` hook; consumer `notify` → `promoter_commission_accrued`, channel `I p E`, class **`ON`**, dedupe
`commission:<attribution_id>`; package **`090`** — plus the same one unnumbered fact.

> Of the twenty-one: **8** postdate `C11` · **7** are `Sync` with a post-commit row · **5** are `C11`-sense
> outbox events (`#3 · #4 · #25 · #26 · #32`).
> **This reproduces `G25_CANONICAL_EVENT_CATALOG.md` §7.2's twenty-plus-one exactly.**

#### Scenario 3 — all four unresolved events KEPT — **23 numbered + 1 unnumbered = 24 facts**

Scenario 2's twenty, **plus three**:

| # | Event | Producer | Named consumer that can be found |
|---|---|---|---|
| **2** | `ConnectOnboardingCompleted` | `kernel.set_org_connect_ref` — uncontracted, `G-3`; package `077` | **none.** `venue`, `market` are named contexts with no handler; the capability flags are already written synchronously by the `account.updated` webhook branch |
| **5** | `TicketTypeOpened` *(`/ TierUnlocked` struck — no producer in any package)* | `venue.create_ticket_type` / `set_ticket_type_price`; package `081` | **none at Gate P.** `market.listing_unified` is a `security_invoker` VIEW — no handler, no cache |
| **11** | `TicketReserved` | `venue.reserve_primary_inventory`; package `081` | **none cross-context.** Its only consumer is its own producing transaction's write |

**Full enumeration — twenty-three numbered:**
`#2 · #3 · #4 · #5 · #9 · #10 · #11 · #17 · #22 · #25 · #26 · #27 · #28 · #31 · #32 · #37 · #38 · #39 · #40 ·
#41 · #42 · #43 · #44`, plus the one unnumbered event-cancellation fact.

> Of the twenty-four: **8** postdate `C11` · **7** are `Sync` with a post-commit row · **8** are `C11`-sense
> outbox events (`#2 · #3 · #4 · #5 · #11 · #25 · #26 · #32`).
> **Three of the four rows added here have no named consumer that can be found.** They add `event_type` values,
> not consumers.

#### The three totals, and what is deliberately outside them

| Scenario | Numbered | Unnumbered | **Total facts** |
|---|:---:|:---:|:---:|
| **1 — all four REMOVED** | **19** | 1 | **20** |
| **2 — engineering recommendation** | **20** | 1 | **21** |
| **3 — all four KEPT** | **23** | 1 | **24** |

**The spread is four facts — 20 to 24. Every number in it is more than three times the figure `C11` states —
*"~6 real outbox events"* — and none of them is 36.** Neither of the two numbers an owner has been handed
before now is the number that prices this decision.

**Recorded and deliberately not counted, so the numbers stay checkable:**

- **`#21 CredentialInvalidated`** — a twenty-first numbered candidate. DA §6.2's diagram enqueues it inside the
  custody transaction alongside `#17` and `#9` (`:1242`), and its named consumer,
  `venue.append_door_manifest_delta`, is bound by RPC §12.4c to write the `revoke` delta **in-transaction**.
  Its drain arrow reaches `notify` (`ODR-3`-conditional), `analytics` (deferred by `C11`) and `delist`
  (`market`, Gate M) — **no Gate-P consumer.** `VERIFIED` **If the owner rules that the constitution's own
  diagram is itself a carrier requirement, every total above rises by exactly one** (21 / 22 / 25).
- **Sixteen unnumbered `notify` facts**, `ODR-3`-conditional in full, enumerated so no reader mistakes the three
  totals for the whole surface: `wallet_pass_available` · `purchase_failed` · `event_time_changed` ·
  `event_venue_changed` · `event_postponed` · `organizer_announcement` · `refund_requested` ·
  `refund_approved` · `refund_failed` · `security_password_changed` · `security_payout_destination_changed` ·
  `security_org_role_granted` · `security_org_role_revoked` · `security_payout_method_added` ·
  `staff_low_inventory` · `staff_door_anomaly`. `VERIFIED`
  *(`event_reminder_24h`, `event_door_open` and `staff_sales_digest` are excluded — their trigger is
  `notify.sweep_scheduled()`, a scheduler, not an event.)*

### 6. The cost finding that should decide it

**The same table, the same drainer, the same uniqueness constraint and the same retention serve 20 facts or
24.** Read directly, at head:

- **Package `076`, and no edge is created by it.** Registry `COND-A` `:761`: *"Package **`076`** — **the table
  has zero FK dependencies, so no producer package gains an edge.**"* `VERIFIED` No producer package's position
  in the sixteen-package chain moves whether the table carries nineteen event types or twenty-three.
- **One table.** `notify.outbox` — `outbox_id · event_type · aggregate_kind · aggregate_id · sequence ·
  causation_id · correlation_id · event_key · payload · occurred_at · state · claimed_until · attempt ·
  last_error · created_at`, with `UNIQUE (event_type, event_key)`, `UNIQUE (aggregate_kind, aggregate_id,
  sequence)` and one partial index `(state, occurred_at) WHERE state IN ('pending','claimed')`. NOTIF §4.3
  `:733`–`:738`. `VERIFIED` **`event_type` is a `text` column. Adding a twenty-fourth value is an `INSERT`.**
- **One drainer.** `notify.drain_outbox(p_limit int)` — *"`NEW RPC`, `service_role`, invoked by pg_cron"*, one
  `pg_try_advisory_xact_lock(hashtext('notify_drain_outbox'))` (the `0600:115` pattern). NOTIF `:756`–`:760`.
  `VERIFIED`
- **No new lock class.** *"`sequence` is allocated per `(aggregate_kind, aggregate_id)` under the aggregate's
  existing row lock, which every `SSCAS` member already holds in the global lock order … **so no new lock and no
  new deadlock class is introduced.** The outbox row is written last within its transaction."* NOTIF `:741`–`:745`.
  `VERIFIED`
- **The corpus's own pricing of the whole thing.** NOTIF §10 `O-N2`: *"one table plus one RPC on a cron that
  already runs — the constitution's own anti-over-engineering budget."* `VERIFIED`

**Nothing in that construction scales with the number of `event_type` values.** Twenty facts and twenty-four
facts cost the same table, the same two unique constraints, the same partial index, the same drainer, the same
advisory lock and the same retention policy.

> **Therefore: the four unresolved events do not price `ODR-2`, and can be ruled *after* it.** Their entire
> spread is four facts on a carrier whose cost does not vary with facts. `G-25` was still necessary — it is what
> makes this statement checkable rather than a guess — but `DF-23`'s assumption that `G-25` had to close
> *before* `ODR-2` was ruled is not borne out by the pricing.

**`DELTA-1` — one correction to "the cron that already runs", `VERIFIED` and load-bearing for the
conditions.** *"The cron that already runs"* is a **cadence**, not a job with a spare slot. Production's cron
inventory, enumerated from the migrations: `auto-finalize-auctions` `*/2` running
`select public.auto_finalize_expired_auctions();` (`014:15-19`); `enforce-transfer-expiry` `*/2` running a
`net.http_post` to the edge function with a Vault bearer (`032:97-117`, superseding `014:26-38`);
`sweep-auth-password-changes` `*/5` running `select public.sweep_auth_password_changes();` (converged by
`075:355-389`). **None of those three commands can host a `drain_outbox` call without being rewritten.** So
`ODR-2 = [A]` costs one table + one RPC + **one new `cron.job` row**, at the existing two-minute cadence. That
is still small — and it is exactly the artefact this codebase has twice failed to keep (§E-bis 7), which is why
condition 2 in §I is not optional.

### 7. The production precedent — migration `054`

This is the strongest available evidence for why side effects belong outside the money transaction, and it is
from this codebase, on production data. `supabase/migrations/054_fix_notify_outbid_aborts_bids.sql`, header,
applied 2026-08-05:

> *"The function had **NO exception handler**, so that error propagated out of the AFTER trigger and **aborted
> the parent transaction — the bid INSERT itself.**"* — `054:17-18`
>
> *"The blast radius was hidden by the function's own guard … The raising line only runs when a DIFFERENT user
> outbids the current leader. **So a first bid succeeded, and the same bidder raising their own bid succeeded,
> but a genuine competitive bid — the core auction mechanic — failed.**"* — `054:20-24`
>
> *"Consistent with the data: **every listing that ever attracted two distinct bidders did so in Feb 2026; no
> second-distinct-bidder bid has succeeded since.**"* — `054:26-27`

`VERIFIED`, read in the migration file. **Competitive bidding was silently dead from February to August 2026 —
roughly six months — because one notification side effect had no exception handler and ran inside the parent
transaction.** There was no error surfaced to a user, no alert and no failing test; the outage was found by
reading the data.

**Why this argues for `[A]` and not against it.** The lesson is not *"don't build notification
infrastructure."* It is *"a side effect must not share a transaction with the fact."* An outbox is the
structural form of that lesson: the row is written in the transaction; **the effect is not.** The three
disciplines `054`, `057` and `058` bought the hard way — non-raising enqueue, a second `EXCEPTION WHEN OTHERS`
in every producer, and outbound HTTP after commit — are exactly what NOTIF §0.3 rule 1 and §4.3's
`notify.emit_event` carry forward. `VERIFIED` (NOTIF `:48`–`:51`, `:750`–`:752`.)

**`DELTA-2` — and one place where carrying it forward is currently wrong.** `notify.emit_event` is specified
**non-raising**: *"A producer that cannot emit its envelope logs a warning and commits its money/custody work
regardless."* NOTIF `:750`–`:752`. `VERIFIED` That is right for a notification and **wrong for a door
envelope**: DOOR §6 `:492`/`:494` requires step 11's envelope to be inside an **all-or-nothing** transaction, so
a swallowed emit would commit an open manifest with no envelope and leave every online scanner unsynced, with
no error. **Two ratified-tier specs give contradictory instructions about the same write.** This is exactly the
class `O11`/`ODR-7` exists to rank, and it is a design condition on `[A]` (§I condition 3), **not** a reason to
choose `[B]`. `VERIFIED` on both sites; `INFERENCE` that no document reconciles them — none could be found.

---

## F. `CORPUS RECOMMENDATION` — `ODR-2`

> **The corpus is split, the split is on the record, and one side declines on principle. Cited exactly.**

**FOR building it — one document, unambiguously:**

> **`PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N2`:** *"**Build it.** It is one table plus one RPC on a cron that
> already runs — the constitution's own anti-over-engineering budget."* `VERIFIED`

**FOR building it — the constitution, by promise rather than by recommendation:**

> **`SNATCH_IT_DOMAIN_ARCHITECTURE.md` `:1263`:** *"the only new infrastructure Phase 2 introduces is **one
> outbox table and a drainer on the cron that already runs**."* `VERIFIED`

**DECLINING to recommend — two documents, explicitly:**

> **`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`:** *"**This is a conditional package element and this
> integration does NOT decide it.** It is specified here so that a YES ruling is an apply, not a design
> exercise."* `VERIFIED`
> **`PHASE_2_SCOPE_AMENDMENT_2026_08.md`, recording rather than resolving:** *"`NOTIF` §10 recommends **build
> it** … **`REGISTRY` and `SCHEMA` decline to recommend.** Not decided here."* `VERIFIED`

**CLOSING the option space — the same schema spec:**

> *"**There is no third option in which DA:1253 stands and nothing implements it.**"* `VERIFIED`

**The disagreement, stated without softening.** No document in the corpus argues **against** the outbox. The
split is between one document that says *build it* and two that say *not our call*. That is a split about
**authority**, not about **merit** — and it is why this is on your desk.

**And one internal contradiction inside a single section, carried forward from `G25_FOUR_EVENT_OWNER_BRIEF.md`
§6.4:** `PHASE_2_PACKAGE_REGISTRY.md` §7 `:761` puts *"commission accrual"* on the outbox and `:777` lists
promoter codes among the **unaffected**, sixteen lines apart. `VERIFIED`, both lines read at head. The
recommended correction — narrowing `:777` to *"no async **in the money path**"* — **is required under both
rulings**, because as written `:777` is falsified by `:761` independently of `ODR-2` and `ODR-3`.

## G. `ENGINEERING RECOMMENDATION` — `ODR-2`

> **Kept deliberately separate from §F. This is an engineering judgement about this codebase, not a reading of
> the corpus.**

### **`[A]` — BUILD IT.** Four reasons, in order of weight.

**1. It is a security decision that has already been made, twice, by ratified invariant.** The Wallet
supersession call has three possible homes and two of them are prohibited by name (§E-bis 1). `[B]` does not
open a fourth home; it silently selects the prohibited one in which a previous owner keeps a live pass. On a
custody platform whose door is by design (`C6`) a reconcile-after-the-fact window, that is a door-fraud
primitive, not a reduced feature set.

**2. The asymmetry in retrofit cost is decisive and runs entirely one way.** Adding the outbox later means
reopening every money and custody producer — `venue.finalize_primary_order`, `kernel.issue_ticket_atoms`,
`kernel.transfer_ticket_ownership`, `kernel.void_ticket_atom`, `kernel.refund_primary_order`,
`venue.record_scan`, `venue.resolve_order_attribution`, `venue.open_door_manifest`,
`venue.close_door_manifest`, `catalog.engage_door_freeze`, `venue.append_door_manifest_delta` — **eleven
functions, several of them `SSCAS` members under the global lock order.** Adding events to an existing outbox is
an `INSERT`. Build the expensive-to-retrofit thing at `076`; defer everything that is cheap to add later.

**3. The cost does not vary with the thing the owner was told to price.** §E-bis 6. Twenty facts and
twenty-four facts are the same table. The four open events are therefore **not** a prerequisite to this ruling,
and the ruling should not wait on them.

**4. The money-safety property `[B]` would nominally protect is already in production, and you bought it the
hard way.** `054` (§E-bis 7). The discipline that came out of that outage — non-raising enqueue, a second
exception layer in every producer, HTTP after commit — is the house pattern and is unchanged by either option.
**`ODR-2` does not buy that property; it institutionalises it.**

### The counter-argument, stated at its strongest

`[B]` is not irrational. It is one table fewer, one cron entry fewer, and one fewer thing to observe on a solo
founder's plate — and the money plane is genuinely unaffected either way (`:777` is right about that). **The
reason to reject it is not cost. It is that `[B]` requires you to design an alternative transport for twenty to
twenty-four facts, one at a time, and the register already records that four capability families have none —
with Wallet carrying *"no admissible alternative design"* at all.** `[B]` is more work, not less, and the extra
work is design work rather than a `CREATE TABLE`.

## H. `OWNER CHOICE` — `ODR-2`

```
[A] BUILD  — event outbox table + service_role drainer RPC at package 076,
             drainer scheduled BY MIGRATION on the existing 2-minute cadence

[B] WITHDRAW — amend the constitution (DA §6.2/§6.3, CDM C12) to stop promising an
             outbox in Phase 2, and design a stated alternative transport for each
             of the 20-24 facts enumerated in E-bis 5

RECOMMENDED: A
```

## I. Conditions attached to `[A]` — engineering, not owner decisions

Recorded here so a YES is an apply rather than a design exercise. None of these changes the ruling.

1. **Every producer emits through the RPC, never by direct `INSERT`.** This makes the schema home
   (`kernel.event_outbox` vs `notify.outbox`) a one-line `ALTER TABLE … SET SCHEMA` that touches no producer —
   which is what makes the register's *"the schema home of `ODR-2`'s table is decided by `ODR-3`"* and the prior
   brief's *"the schema name is mechanical"* both true at once, instead of in conflict.
2. **Schedule the drainer in the migration, with `075`'s four-way exact guard** (`jobname` AND `schedule` AND
   `command` AND `active`), and put **Sentry `captureException`** on the drainer on day one. `_shared/sentry.ts`
   exists and is imported by seven edge functions — `confirm-and-release`, `confirm-payment`,
   `create-connect-account`, `create-payment-intent`, `delete-account`, `enforce-transfer-expiry`,
   `stripe-webhook` — **and by none of `notify-transfer`, `notify-report`, `send-push`.** `VERIFIED` by reading
   `supabase/functions/`. A drainer scheduled by hand reproduces `075` D-5 exactly.
3. **Resolve `DELTA-2` before `086`.** Either give the outbox two emit paths — non-raising for notification
   facts, raising for correctness-bearing envelopes — or have the door write its envelope with a plain
   in-transaction `INSERT`. As currently specified, a non-raising `emit_event` in the door-open transaction
   violates DOOR `:494`'s all-or-nothing rule.
4. **A `done`-row purge in the drainer,** and the retention window fixed at ruling time
   (`O-N9` proposes 30 days for drained rows).

---
---

# `ODR-3` — Build the `notify` platform, and at what gate?

## A. The decision, in plain English

Whether to build a notification **platform**: nine new tables, 23 RPCs, two edge functions, three cron entries
and two client surfaces — a mobile notification centre and a venue-staff surface — replacing today's two
disjoint rails with one record, real preferences, a delivery ledger and templates.

**You are not deciding whether Snatch It sends notifications.** It already does, in production, on two rails,
today. You are deciding whether to replace those rails with a platform, and whether that happens in Phase 2
(**Gate P**) or later (**Gate L**).

## B. Why it is the owner's

1. **Two ratified sources say opposite things and neither outranks the other.** Ratified row `C7` is
   `Gate P / MVP` and names `notify`; **all four** implementation specs place it at Gate L / do-not-build.
   `PHASE_2_PACKAGE_REGISTRY.md` `COND-B` `:762`. `VERIFIED` Ranking them is the `O11`/`ODR-7` question, which
   is itself an owner decision.
2. **The corpus refuses.** `PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 `MD-10`: *"**Not resolved here** — it is a
   stop-and-ask. §16.9's matrices are conditional."* `VERIFIED`
3. **It is a programme-sized scope call.** Nine tables, three crons and two client surfaces is the largest
   single package in Phase 2, and it re-bands the registry.
4. **Silence is UNSAFE.** Register, `ODR-3`: *"The four implementation specs win by weight of numbers, `notify`
   is never scheduled, **and the dashboard surface ships against nothing.**"* `VERIFIED`

**Mechanical — remove from your set.** Whether push tokens extend `public.push_tokens` or get a new table (two
documents already answer identically: *"a second token table creates a split-brain"*, `O-N11`); the schema
name; the package number.

## C. The options

- **`[A]` GATE P** — build `notify` in Phase 2, at package `092`. Requires `ODR-2 = [A]`.
- **`[B]` GATE L** — `notify` is not built in Phase 2. Notifications continue on the production path. Requires
  a re-scope of `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §16.5. **Compatible with either `ODR-2` ruling.**
- **`[C]` GATE P, REDUCED** — build only the parts that close a verified production defect, defer the rest.
  *(Not a combination the corpus offers; constructed here so the option space is honest. See §G.)*

## D. What each option means

| Dimension | **`[A]` GATE P** | **`[B]` GATE L** | **`[C]` GATE P, REDUCED** |
|---|---|---|---|
| **Product** | mobile notification centre; preferences that actually work; 24 undisableable money/security notices; venue announcement composer; email/SMS-ready | notifications keep working exactly as today, on both rails; **a push a mobile user swipes away is still gone permanently** (D-12) | closes D-1 (inert toggles), D-2/D-10 (no receipts, no retry) and D-12 (no mobile inbox); defers announcements, templates, locale, email |
| **Venue / operator** | dashboard §16.5 built as specified: global staff toggle, digest cadence, always-on payout-failure row, on-duty door-anomaly row, **plus** the announcement composer with blast-radius count and hold window | **§16.5 must be re-scoped.** RLS `MD-10` rules that no Gate-L object may carry a binding dependency, and §16.5's is binding | §16.5's four preference rows land; the composer does not |
| **Security** | `security_*` types become MANDATORY and structurally undisableable (composite FK + `CHECK` makes the preference row *unrepresentable*); announcements get abuse controls, dual control above 500 recipients, a hold window | `security_password_changed` continues to work (`0600`); the other four `security_*` types are unbuilt. Preference toggles that *"gate nothing"* remain — `G-19` — which **replicates a named live production defect** | same as `[A]` for the mandatory class; announcements deferred, so their threat model is deferred with them |
| **Privacy** | §8 is the most developed privacy analysis in the corpus: the account-existence oracle, lock-screen rule `N-P1` (no counterparty name and no amount in any custody/money push body), `N-DL-4` (a notification link may never carry a secret, token or one-time action), and a payload that never contains a recipient list | today's push bodies carry no such rule. `034`/`035` payloads carry ids only, so no live leak — but nothing prevents the next producer from adding one | the payload and lock-screen rules are cheap and land with the dispatcher |
| **Complexity** | **the complexity is the risk.** 9 tables · 23 RPCs · 2 edge functions · **3 cron entries** · 2 client surfaces · 40 new type keys · 67 registry rows | zero new complexity; five verified gaps carried forward knowingly | roughly a third of `[A]`'s surface |
| **Future flexibility** | additive later work is genuinely additive: the registry is a table, the mandatory class is a column, locale is a column | **`notify` is cheap to add later** — the expensive thing to retrofit is the outbox, and that is `ODR-2`, not this | preserves the option in both directions |
| **Migration / package** | package **`092`**; band becomes `076`–`092`; count becomes **seventeen**; **`ODR-1`'s "sixteen packages, no gaps" assertion is falsified** and `ODR-1` must be re-signed conditionally | band stays `076`–`091`, sixteen packages. **`ODR-1` is untouched** | still a new package and still re-bands; the `ODR-1` coupling holds for `[C]` as for `[A]` |

## E. Failure mode, per option

**`[A]` GATE P — a cron stops and nobody notices, on a path with zero instrumentation.** The notify design adds
**three** cron entries (`DELTA-4`) to a path with **zero Sentry coverage** (`VERIFIED` independently at
§I condition 2 above), and **this codebase has silently lost a cron job twice** (§E-bis 7 of `ODR-2`, restated
in §F-bis 4 below). The two RPCs at the centre of the retry machinery — `notify.claim_deliveries` and
`notify.record_delivery_result` — carry **no contract body at all** (§F-bis 3).

**`[B]` GATE L — buyers get a ticket and silence, and inert toggles stay inert.** Native purchase confirmations
have no producer on the production path and must be scheduled explicitly; `notification_preferences`' six
booleans continue to change nothing, which is `G-19` — *"preference toggles that gate nothing"* — a defect the
corpus names because it already exists.

**`[C]` GATE P, REDUCED — scope creep back to `[A]`.** A reduced `notify` still creates the schema, still
re-bands the registry, and every deferred piece has an advocate. The discipline has to be written into the
package, not assumed.

---

## F-bis. The record, item by item

### 1. The two infrastructures, side by side — what each actually gives you

> **This table is the point of the whole brief. Read it before ruling.**

| Property | **Outbox alone** (`ODR-2 = A`, `ODR-3 = B`) | **`notify` platform** (`ODR-3 = A`) |
|---|---|---|
| Transactional hand-off — the row is written in the same transaction as the state change | **yes** — this is what it is for | yes, *via* the outbox; hop 1→2 |
| At-least-once with per-aggregate ordering (`sequence`, `causation_id`, `correlation_id` as columns, not conventions) | **yes** — NOTIF `:740`–`:743` | yes, same object |
| Retry with a claim lease, `attempt` counter and dead-letter state | **yes** at the envelope (`state ∈ pending/claimed/done/dead`, `claimed_until`, `attempt`) | yes, **and again per delivery attempt** |
| Post-commit ordering — the effect provably runs after the fact commits | **yes** | yes, same object |
| Replay safety on the producer side | **yes** — `UNIQUE (event_type, event_key)`: *"a replayed producer writes no second envelope"* | yes, same constraint |
| **Preference enforcement** | **no** | **yes** — resolver inside the dispatcher; DDL-enforced mandatory class (composite FK `(type_key, delivery_class)` + `CHECK (delivery_class <> 'mandatory')` makes the row *unrepresentable*, binding superusers and `service_role` alike) |
| **Delivery ledger** — did it actually arrive | **no** | **yes** — `notify.delivery`, one row per `(notification, channel)`, `UNIQUE`, plus `notify-receipts` polling Expo and reaping `DeviceNotRegistered` tokens |
| **Dedupe on the push rail** | **no** | **yes** — hop 3, `dedupe_key`, partial `UNIQUE`, `ON CONFLICT DO NOTHING`; *"the exact `057:50-52` pattern, reused"* |
| **Mobile inbox** | **no** | **yes** — `NEW RN SURFACE`: notification centre, unread badge, `shouldSetBadge: true`, foreground receipt listener, `target_kind` router **with an `else` branch**, cold-start pending-target replay |
| **Templates / locale** | **no** | **yes** — `notify.template` per `(key, locale, channel, version)`; `kernel.identity_ext.locale` |
| **Organizer announcements** | **no** | **yes** — with the §7 abuse controls |
| **Email / SMS readiness** | **no** | **yes** — `_shared/email.ts`, conditional on `O-N3` |
| **Money-safety (a notification cannot abort the money transaction)** | **already in production** — `057`/`058` | **already in production.** `notify` does not buy this; it inherits it |

**The last row is the one that most often gets conflated.** The property everyone reaches for when they say
*"we need this for safety"* was bought in August 2026 by migrations `057` and `058` and is live now. `notify`
buys **product** value — preferences, a mobile inbox, delivery visibility — priced as a feature. `VERIFIED`

### 2. What production already has — verified from the migrations, not from the spec

Read directly in `supabase/migrations/`, not from `PHASE_2_NOTIFICATIONS_SPEC.md` §1's account of them.

**HAS — six things, each load-bearing:**

1. **An idempotent, non-raising, `service_role`-only, in-transaction enqueue.**
   `public.enqueue_notification(uuid,text,text,text,text,text,jsonb)` — `SECURITY DEFINER`,
   `SET search_path TO 'public'`, `ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING` against a
   partial unique index, whole body wrapped in `EXCEPTION WHEN OTHERS → RAISE WARNING`, then
   `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated` and `GRANT EXECUTE … TO service_role`.
   `057:44-91`. `VERIFIED` Its own header states the design rule: *"**NEVER RAISES.** … the `EXCEPTION` block
   opens a plpgsql subtransaction and a failure rolls back only the `INSERT`, never the parent marketplace
   transaction."*
2. **Producer triggers with their own second exception layer.** `058` adds **four** trigger functions —
   `notify_bid_inbox`, `notify_auction_won_inbox`, `notify_transfer_created_inbox`,
   `notify_transfer_state_inbox` — each wrapping its entire body in `EXCEPTION WHEN OTHERS`, *"a second layer
   beneath the non-raising helper"*. Between them they emit **eleven** typed inbox events: `bid_received` ·
   `outbid` · `auction_won` · `listing_sold` · `buyer_info_needed` · `buyer_confirmation_needed` ·
   `transfer_viewed` · `transfer_confirmed` · `transfer_disputed` · `payout_released` · `order_complete`.
   `VERIFIED` `058`'s header records the live verification: *"replaying `seller_sent` / `buyer_confirmed` /
   `payout_released` / `disputed` produced ZERO duplicates (every `dup_count` = 1)."*
3. **Outbound HTTP after commit, via `pg_net`.** `034`'s `notify_transfer_event()` on
   `AFTER INSERT ON public.transfers` and `AFTER UPDATE OF status` (→ `seller_sent`), and `035`'s
   `notify_bid_placed()` on `AFTER INSERT ON public.bids` — both read the bearer from
   `vault.decrypted_secrets WHERE name = 'service_role_key'`, both `PERFORM net.http_post(...)`, both wrapped in
   `EXCEPTION WHEN OTHERS` with the comment *"Never block the buyer/seller action because a notification
   failed."* `VERIFIED`
4. **A watermark-sweep pattern whose correctness does not depend on its lock.**
   `public.sweep_auth_password_changes()` (`0600`, fixed by `0601`), `*/5`, with a `floor_at` no-backfill
   barrier seeded to `now()` in the same statement that creates the row, a deliberate 60-minute overlap window
   because the source `created_at` is an application clock, a `pg_try_advisory_xact_lock` early return, a
   watermark that advances **only on success**, and dedupe on the immutable source-row uuid so the overlap is
   absorbed by the unique index rather than by the lock. `VERIFIED`
5. **An idempotency ledger for the external transfer rail.** `public.transfer_notifications`, `PRIMARY KEY
   (transfer_id, event_type)`, six-value `CHECK`, RLS enabled, `REVOKE ALL FROM PUBLIC, anon, authenticated`.
   `034:25-41`. `VERIFIED`
6. **A production-proven RLS/grant posture on the inbox.** `040:88-108` — `REVOKE ALL FROM PUBLIC, anon,
   authenticated` → `GRANT SELECT` + `GRANT UPDATE (read_at)` to `authenticated`; owner-select and
   owner-update-read-state policies; **no `INSERT` policy at all, for any client role.** NOTIF §6.2 reuses this
   verbatim and calls it *"the single most valuable piece of reuse in the spec"*. `VERIFIED`

**GAPS — the five the owner needs to weigh, each verified rather than asserted:**

| Gap | Evidence |
|---|---|
| **Inert preference toggles** | `public.notification_preferences` — six booleans, PK `user_id`, auto-created by trigger (`000_baseline_schema.sql:920-964`). **No sender reads it.** `send-push` selects only from `push_tokens`. The six toggles in `app/settings/notifications.tsx` change nothing. D-1, `VERIFIED` repo-wide |
| **No delivery ledger** | `send-push` never checks `pushRes.ok`, echoes Expo's body verbatim as a 200, and no code anywhere calls `getReceipts`. D-2, `VERIFIED` |
| **No retry** | no chunking at Expo's 100-message limit, no `Retry-After` handling, no backoff. D-10, `VERIFIED` |
| **No dedupe on the push rail** | the `dedupe_key` + partial `UNIQUE` added by `057` lives on `public.notifications` — the **inbox** rail. The push rail's only ledger is `transfer_notifications`, which covers the external transfer path and nothing else; `notify-report` has **no idempotency table at all** (D-8). `VERIFIED` |
| **No mobile inbox** | no mobile file reads `public.notifications`; `shouldSetBadge: false`; no `addNotificationReceivedListener`; no unread count; no mark-as-read. **A push a mobile user swipes away is gone permanently.** D-12, `VERIFIED` |

**And the structural fact underneath all five:** production runs **two independent notification systems with two
disjoint address spaces** — a push rail addressed by `data.type` + `listingId`/`transferId` that leaves **no
durable row anywhere**, and an inbox rail addressed by a **web-relative path** that only `web/` renders.
*"Push and inbox are separate channels with separate address spaces."* — `058:6`, repeated at `:56`. `VERIFIED`
Nothing maps between them.

### 3. `COND-D`'s coherence rule — what it constrains, and what it does not

**The rule.** `PHASE_2_PACKAGE_REGISTRY.md` §7 `:765`–`:768`, `VERIFIED`:

> *"**COND-A and COND-B are coupled and must be ruled on together.** Outbox-in with `notify`-out is coherent —
> Apple Wallet push and the door-manifest events get their carrier, notifications do not. **`notify`-in with
> outbox-out is not coherent: the notifications design *is* the outbox pipeline.**"*

**Why the incoherence is real and not a formality.** NOTIF §4.1's pipeline is
`RPC / trigger / sweep → notify.outbox → notify.notification → notify.delivery → Expo / Resend`, and hop 2 is
`notify.outbox` itself. `VERIFIED` (`:674`–`:694`). A `notify` built without an outbox would have to invent one
under a different name.

**The four combinations, three of which are coherent:**

| `ODR-2` | `ODR-3` | Coherent? | What it is |
|---|---|:---:|---|
| BUILD | Gate P | ✔ | the full design |
| **BUILD** | **Gate L** | **✔** | **the outbox serves Wallet, the door and the scanner; notifications stay on the production path** |
| WITHDRAW | Gate L | ✔ | withdraw the promise; re-scope four capability families |
| WITHDRAW | Gate P | ✘ | `notify` would have to build an outbox it was just told not to build |

> **`COND-D` removes one of four combinations and fixes the order. It does not collapse two decisions into
> one.** Three combinations remain, and **two of the three contain "outbox = yes"**. A YES on `ODR-2` is
> therefore compatible with either answer on `ODR-3`, and carries no implication about it. **That is the whole
> content of `COND-D`, and it is the opposite of the reading that these must be answered the same way.**

**`DELTA-3` — a filing defect in `COND-D`, recorded because it changes where a reader looks, not what the rule
says.** Register `DF-31`, `VERIFIED`: registry §7 opens *"**Three** items … Each requires an owner ruling"* and
defines **`COND-A`, `COND-B`, `COND-C` only**. The coupling rule above exists in that file **as prose with no
id**; the id `COND-D` is minted in `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `:135`. *"A reader who greps
registry §7 for four `COND-*` rows finds three and concludes one was lost."* **The rule itself is sound and is
quoted correctly everywhere it is used.** Only its home is misattributed.

### 4. The `ODR-3` blast radius on the carrier count — verified, and it is not exactly one

**What the two basis documents say, and they disagree with each other:**

| Source | Claim |
|---|---|
| `G25_CANONICAL_EVENT_CATALOG.md` §7.3 | *"`ODR-3` interacts with **exactly four rows** and no others: **#25 · #26 · #31 · #32** (`notify` fan-out)."* `VERIFIED` |
| `G25_FOUR_EVENT_OWNER_BRIEF.md` §2.6 | *"**`ODR-3` moves exactly one row of the twenty-one.** `#32`, and only `#32`."* `VERIFIED` |

**`DELTA-5` — what a row-by-row re-read of Scenario 2's twenty-one facts finds.** Three tiers, each fully
enumerated.

**Tier 1 — untouched by any `ODR-3` ruling: fifteen numbered + one unnumbered = SIXTEEN facts.** Each retains at
least one named non-`notify` consumer:

| Fact | Surviving consumer under `notify = Gate L` |
|---|---|
| `#3 VenueApproved` | `venue` |
| `#4 EventPublished` | `venue`, `market` |
| `#17 OwnershipTransferred` | **`wallet-pass-push`** — `credential_version` bump, *always, unconditionally* |
| `#22 ScanAdmitted` | `wallet-pass-push` (atom → `scanned`); offline reconciliation |
| `#25 PayoutReleased` | `venue`, `market` |
| `#26 PayoutFailed` | `venue`/`market`, `risk` |
| `#28 TicketVoided` | **`wallet-pass-push`** — supersession on void, *always* |
| `#37 DoorManifestOpened` | **scanner push-to-sync**, `risk` |
| `#38 DoorManifestClosed` | reconciliation monitor `¹` |
| `#39 TransferFreezeEngaged` | `market` (invalidate cached eligibility) `²` |
| `#40 DoorManifestDrained` | `wallet-pass-push` (best-effort) |
| `#41 DoorFreezeOverrideGranted` | `risk` `¹` |
| `#42 DoorFreezeOverrideEnded` | `risk` `¹` |
| `#43 DoorManifestSupplemented` | **scanner push-to-sync** |
| `#44 DoorManifestInvalidated` | **scanner (drop M2, disarm)**, dashboard alert, `risk` |
| *unnumbered* event-cancellation | **`wallet-pass-push`** (*always*); DOOR §7.2.1 → `#44` |

`¹` `INFERENCE` — the *"reconciliation monitor"* and the `risk` context are named as consumers in DOOR §12.2 but
no Gate-P handler for either could be found; if they are not built at Gate P, `#38`, `#41` and `#42` fall to
Tier 3.
`²` `VERIFIED` that `#39`'s `market` consumer is *"inert while `feature.native_resale_enabled` is OFF"*
(`G25_FOUR_EVENT_OWNER_BRIEF.md` §1, `#5`). It survives as a named consumer; it does nothing yet.

**Tier 2 — collapses under `notify = Gate L`: TWO facts, `#31` and `#32`.**

**`PHASE_2_NOTIFICATIONS_SPEC.md` §2.2 Group M is a two-row table and both rows are here.** `:444`–`:445`,
`VERIFIED`, read in full:

| Key | Trigger event | Ch. | Class | Dedupe key |
|---|---|---|---|---|
| `promoter_attribution_recorded` | **`#31 AttributionRecorded`** | `I` | **`OFF`** | `attribution:<order_id>:<promoter_link_id>` |
| `promoter_commission_accrued` | **`#32 PromoterCommissionAccrued`** | `I p E` | **`ON`** | `commission:<attribution_id>` |

- **`#32 PromoterCommissionAccrued`** — sole Gate-P consumer is `promoter_commission_accrued`, class **`ON`**.
  Already identified in both basis documents. `VERIFIED`
- **`#31 AttributionRecorded`** — **`DELTA`.** Its sole named consumer is `promoter_attribution_recorded`,
  class **`OFF`**, inbox-only (`I`) — **weaker on every axis than `#32`'s `ON` / `I p E`** — and its money write
  is same-transaction by ratified `D7`. DA §6.1 `:1214` gives its consumers as *"core (commission payout),
  analytics"*: the first **is** the same-transaction write, the second is deferred by `C11`. **Under `notify =
  Gate L`, `#31` has no Gate-P consumer, on exactly the reasoning that collapses `#32` — and a weaker claim than
  `#32`'s.** `VERIFIED` at the Group M table above. Neither basis document applies that reasoning to it:
  `G-25` §7.3 counts it among four *interacting* rows without saying it collapses; the four-event brief counts
  only `#32` and calls `#32` *"the weakest carrier claim of any event in Part 2's enumerations"* — **which
  `#31` is weaker than.**

**Tier 3 — contested, and it is the `#21` question again: THREE facts, `#9`, `#10`, `#27`.** Each has only
`notify` MANDATORY types in the carrier table's consumer column (`purchase_confirmed`, `ticket_ready`,
`refund_completed`), and each has **built-context ticks** in DA §6.1 (`#9` → *venue, market, analytics*;
`#10` → *venue, market (eligibility), social, analytics*; `#27` → *venue/market, risk, analytics*) with **no
handler found in any of them**. `VERIFIED` `#9` additionally has the constitution's own diagram enqueuing it
unconditionally inside the custody transaction (`:1242`). **This is the same reading `G-25` §2.1 flagged and
deliberately left open for `#21 CredentialInvalidated`, and the same test `G-25` applied strictly to `#2`,
`#5` and `#11`.** Applying it uniformly is a choice; applying it to some rows and not others is not.

**The blast radius, stated three ways so the owner can pick the reading:**

| Reading | Facts a Gate-L ruling removes | Gate-P carrier load remaining |
|---|:---:|:---:|
| Strictest — a context tick is not a consumer (G-25's own test for `#2`/`#5`/`#11`) | **5** — `#9 · #10 · #27 · #31 · #32` | **16** |
| Middle — `#31`/`#32` collapse; `#9`/`#10`/`#27` survive on the constitution's enqueue and their built-context ticks | **2** — `#31 · #32` | **19** |
| As the four-event brief states it | **1** — `#32` | **20** |

> **What survives every reading — and this is the load-bearing conclusion, which the "exactly one" claim was
> reaching for and understated:** the **door plane** (`#37`–`#44`), the **Wallet plane** (`#17`, `#22`, `#28`,
> `#40`, event-cancellation) and the **scanner paths** (`#37`, `#43`, `#44`) are **wholly untouched** by
> `ODR-3`. **A `notify = Gate L` ruling does not empty the outbox. The floor under every reading is sixteen
> facts.** And because the outbox's cost is flat in the number of facts (§E-bis 6 of `ODR-2`), **none of the
> three readings changes what `ODR-2` costs.**

**`DELTA-5b` — a package consequence of `#31`/`#32` nobody has stated.** `COND-B` floors `notify` at package
**`092`** *"because `notify.drain_outbox` reads `venue.promoter_link` (`090`) and `SEAM-1` floors it there."*
`VERIFIED` `venue.promoter_link` is read by the drainer to serve **exactly the two Group-M types**,
`promoter_commission_accrued` and `promoter_attribution_recorded` — i.e. `#32` and `#31`. **`INFERENCE:` if both
Group-M types are dropped, the cited reason for the `SEAM-1` floor at `092` no longer holds, and `notify` could
be placed earlier in the band.** Not ruled here; flagged because it couples the four-event ruling to the package
band, which no document currently states.

### 5. Package and band consequences — the `ODR-1` coupling

**Gate P re-bands the registry and couples this decision to `ODR-1`. Gate L does not.**

- `PHASE_2_PACKAGE_REGISTRY.md` §2 `:409`: *"**Count: 16 packages, `076`–`091` inclusive, no gaps, no
  duplicates** — subject to §7 `COND-B`."* `VERIFIED`
- `COND-B` `:762`: *"Package **`092`** — not `091` (a droppable stub, rule §6.7) and not earlier, because
  `notify.drain_outbox` reads `venue.promoter_link` (`090`) and `SEAM-1` floors it there. **Count becomes 17,
  range `076`–`092`, and §2's 'no gaps, no duplicates' assertion is falsified.**"* `VERIFIED`
- Registry JSON `:627` repeats it verbatim in the machine-readable surface. `VERIFIED`
- Register, `ODR-1`: *"**What is not mechanical** is the signature: `ODR-3` can falsify the count (a Gate-P
  `notify` makes the band `076`–`092` and seventeen) … **A bare 'ratify the current registry' is the wrong
  signature; a conditional one is not.**"* `VERIFIED`

**One precision, so the coupling is not overstated.** `:409` already carries its own escape clause — *"subject
to §7 `COND-B`"* — so a Gate-P ruling **resolves** a conditional assertion rather than falsifying an
unconditional one; `COND-B` `:762` and the JSON `:627` both use the stronger word *"falsified"*. `VERIFIED`,
all three read at head. The practical consequence is identical either way and is the one the register already
draws: **`ODR-1` must be signed conditionally, and `ODR-3` must be ruled before `ODR-1` is signed.**

**What is genuinely mechanical and should not consume owner attention:** the registry's structural integrity is
already independently verified at head — *"16 packages, `076`–`091`, 0 gaps, 0 duplicates; 45 edges, set-equal
across four declared surfaces; every dependency strictly precedes its dependent; DAG acyclic; package set
identical across seven surfaces; all 8 `SEAM-2` stub→replacement edges declared."* `VERIFIED` **Do not reopen
package numbering.** Only the count and the band move, and only under Gate P.

### 6. The two uncontracted RPCs, and the crons

**The two RPCs with no contract body at all.** `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `:460`,
`VERIFIED`:

> *"23 `notify.*` RPCs (§17.24). **`claim_deliveries` and `record_delivery_result` (§17.25) are wholly
> AUTHORED, not transcribed — their source names them and supplies no contract body at all;** the claim
> predicate, lease semantics, batch bound, outcome mapping, return shapes and idempotency rule are derived.
> `INFERENCE:` flagged in RPC §19 item 1."*

**These two are not peripheral.** `notify.claim_deliveries` is the lease that stops two dispatchers from sending
the same push, and `notify.record_delivery_result` is the write that turns an Expo response into a terminal
state. Together they **are** the retry machinery whose absence today is D-2 and D-10. The one honest limit the
spec itself states — *"a dispatcher that dies in the ~200 ms window between Expo's 200 and the `sent_at` write
will re-post after the lease expires"* — is a property of exactly these two undefined functions. `VERIFIED`

**`DELTA-4` — a third uncontracted RPC, and a third cron. Both `VERIFIED` at head.**

- **A third RPC.** NOTIF §6.3's contract tables name **twenty-two** `notify.*` RPCs. Appendix B's `NEW RPC`
  index (`:1557`) lists **twenty-three**, the extra one being **`notify.resolve_web_link`** — which appears at
  §4.4 `:793` (*"composes the web path from the closed set"*) and in the pgTAP list as `N-A37` `:1477`, and has
  **no row in §6.3 at all**. So the figure "23 RPCs" is reachable two ways and the two surfaces disagree about
  *which* 23. `VERIFIED`
- **A third cron.** The prior brief and Appendix B `:1558` both count **two** new `pg_cron` jobs — the two edge
  functions, `notify-dispatch` at `* * * * *` and `notify-receipts` at `*/15 * * * *` (§6.4). **`notify.sweep_scheduled()`
  is a third**, specified *"on pg_cron `*/5 * * * *`"* at §4.5 `:831`. `notify.drain_outbox` is a fourth cron
  entry, but it belongs to `ODR-2`, not to this decision. **So `ODR-3 = Gate P` adds three cron entries of its
  own, not two.** `VERIFIED`

**And the path they land on has zero Sentry coverage.** NOTIF §4.7 `:911`–`:913`: *"**The notification path has
no Sentry coverage at all today** — none of `notify-transfer`, `notify-report`, `send-push` imports it (D-9)."*
Independently `VERIFIED` here by reading `supabase/functions/`: `_shared/sentry.ts` exists and is imported by
**seven** edge functions — `confirm-and-release`, `confirm-payment`, `create-connect-account`,
`create-payment-intent`, `delete-account`, `enforce-transfer-expiry`, `stripe-webhook` — **and by none of the
three notification functions.**

**This codebase has silently lost a cron job twice. Both instances, `VERIFIED` in the migrations:**

1. **`014`'s `enforce-transfer-expiry` ran and did nothing.** Its scheduled command built a URL and a bearer
   from `current_setting('app.settings.supabase_url')` and `current_setting('app.settings.service_role_key')`
   — GUCs that `054`'s header verifies were **never set**: *"Verified live: both `app.settings.supabase_url`
   and `app.settings.service_role_key` are unset, and `pg_db_role_setting` contains no `app.settings.*` entry
   for any role or for the database."* The job existed, fired every two minutes, and accomplished nothing until
   `032` replaced it with a Vault-bearer form.
2. **`sweep-auth-password-changes` runs in production and is scheduled by no migration.** `075`'s D-5 block:
   *"Production runs jobid 10 … **No migration in the chain schedules it.** `0600` line 55 only MENTIONS it,
   in a comment … **It was scheduled by hand and never written down as SQL.** … So a rebuilt stack silently
   loses password-change security notifications ENTIRELY. The function is present and correct; nothing ever
   calls it. … **There is no error, no log line, and no failing test — the feature is simply absent. That is
   the worst shape a reproducibility gap can take.**"*

Both are the same failure shape, and it is the shape three new crons on an unobserved path would inherit.

## G. `CORPUS RECOMMENDATION` — `ODR-3`

> **Split, and the split is on the record. Cited exactly.**

**FOR Gate P — one document, with a two-limb argument:**

> **`PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N1`:** *"Ratify the reading that `C7`'s **eviction** is satisfied
> vacuously (the leaves were never in the kernel), **and separately** authorise `notify` at Gate P on its own
> merits — because the venue dashboard already has a binding dependency on it (`§16.5`), which no Gate-L object
> may have."* `VERIFIED`

**REFUSING to recommend — one document, explicitly:**

> **`PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 `MD-10`:** *"**Not resolved here** — it is a stop-and-ask. §16.9's
> matrices are conditional."* `VERIFIED`

**The structural disagreement underneath, stated without softening:**

> **`PHASE_2_PACKAGE_REGISTRY.md` `COND-B` `:762`:** *"Ratified row **`C7` is `Gate P / MVP`** and names
> `notify`; **all four** implementation specs place it at Gate L / do-not-build."* `VERIFIED`

**So: one ratified row against four implementation specs, with the one document that recommends Gate P being
the notifications spec itself, and the RLS spec refusing on principle.** Note that the Gate-P argument in
`O-N1` is *circular in one limb and sound in the other*: the *"venue dashboard already has a binding
dependency"* limb is sound only because `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §16.5 was written assuming
`notify` — a dependency the same corpus created. The `C7` limb is the one that does not depend on a choice
already made. `INFERENCE`.

**Which way silence falls:** register, `ODR-3` — *"The four implementation specs win by weight of numbers,
`notify` is never scheduled, and the dashboard surface ships against nothing. **UNSAFE.**"* `VERIFIED`

## H. `ENGINEERING RECOMMENDATION` — `ODR-3`

> **Kept deliberately separate from §G. This is an engineering judgement about this codebase, not a reading of
> the corpus.**

### **`[B]` — GATE L.** Four reasons, in order of weight.

**1. The property this decision is usually justified by is not what it buys.** The money-safety property —
*a notification must never abort the transaction that caused it* — is **already in production** and was bought
by `054`, `057` and `058` (§F-bis 1, last row, and §F-bis 2). `notify` buys preference enforcement, delivery
observability, retry and a mobile inbox. Those are real product value. **They should be priced as a feature,
not as a safety requirement.**

**2. The retrofit asymmetry runs the opposite way from `ODR-2`.** Adding the outbox later reopens eleven money
and custody producers. **Adding `notify` later is purely additive** — the outbox is already there to read, the
registry is a table, the mandatory class is a column, locale is a column. There is no reason to pay for it in
the same quarter as the thing that is genuinely expensive to defer.

**3. The complexity lands on the least-observed path in the system.** Three cron entries (`DELTA-4`), zero
Sentry (`VERIFIED`), two RPCs at the centre of the retry machinery with **no contract body at all**, plus a
third RPC named in the classification index and contracted nowhere. Against a codebase that has lost a cron job
twice, both silently, this is the highest-variance item in Phase 2.

**4. Gate L keeps `ODR-1` clean.** The band stays `076`–`091` and sixteen, the *"no gaps, no duplicates"*
assertion stands as written, and `ODR-1` can be signed on its own merits rather than conditionally. Gate P
couples three decisions where two would do.

### What `[B]` costs, stated honestly and not minimised

- **`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §16.5 must be re-scoped**, and its copy is already written.
- **Preference toggles stay inert** — `G-19`, carried forward *knowingly*, which is different from carrying it
  forward by accident. That distinction has to be written into the ruling or it will be forgotten.
- **Native purchase confirmations need explicit producers** on the production path, or buyers get a ticket and
  silence.
- **The mobile inbox stays absent** (D-12) — the largest single product gap in the notification surface, and
  the one a user actually experiences.
- **`#31` and `#32` collapse** and should be re-read at the close of the sitting (§F-bis 4, Tier 2).

### If the owner wants the product value now: `[C]`, and what belongs in it

Offered because `[A]` vs `[B]` is not actually a binary, and the corpus never constructed the middle. A reduced
Gate-P `notify` that closes only what is a **verified production defect** would be, enumerated: the preference
resolver consulted inside the dispatcher (closes D-1) · `notify.delivery` with receipt polling and token
reaping (closes D-2, D-3, D-10) · the mobile notification centre with a `target_kind` router that has an `else`
branch (closes D-12, D-13, D-15) · `notify.register_push_token` / `revoke_push_token` (closes D-4, D-5, D-6).
**Deferred: announcements and their entire §7 abuse-control surface, `notify.template` and locale, email/SMS,
`notify.schedule` and its `*/5` sweep.** That is four of the nine tables and one of the three crons. `INFERENCE`
that this is coherent — **no document proposes it**, and it would need its own package-placement pass. **It is
recorded as an option, not recommended**, because a reduced `notify` still creates the schema, still re-bands
the registry, and still couples to `ODR-1`.

## I. `OWNER CHOICE` — `ODR-3`

```
[A] GATE P — build the notify platform in Phase 2 at package 092
             (9 tables, 23 RPCs, 2 edge functions, 3 cron entries, 2 client surfaces).
             Band becomes 076-092, seventeen packages. Requires ODR-2 = A.
             ODR-1 must then be signed conditionally.

[B] GATE L — notify is not built in Phase 2. Notifications continue on the
             production path (057/058/0600). Band stays 076-091, sixteen packages.
             ODR-1 untouched. Compatible with either ODR-2 ruling.
             Requires: re-scope dashboard §16.5; schedule native purchase-confirmation
             producers; record that inert preference toggles are carried forward knowingly.

[C] GATE P, REDUCED — build only the defect-closing subset (preference resolver,
             delivery ledger + receipts, mobile inbox, token register/revoke);
             defer announcements, templates, locale, email, notify.schedule.
             Still re-bands the registry and still couples to ODR-1.
             No document proposes this; it would need its own placement pass.

RECOMMENDED: B
```

**Conditions attached to `[A]`, if ruled that way:** Sentry `captureException` on both edge functions and all
three crons, day one · contract `notify.claim_deliveries`, `notify.record_delivery_result` and
`notify.resolve_web_link` **before** `092` is authored, not during · all three crons scheduled **by migration**
with `075`'s four-way exact guard · `O-N3` (does transactional email exist?) ruled first, because **19 of the
24 MANDATORY types name `E` as a channel** and a mandatory money notice with push as its only channel is one
revoked permission away from unreachable.

---
---

# What ruling `ODR-2` alone unblocks, and what still waits on `ODR-3`

## Unblocked by `ODR-2 = [A]`, on its own

1. **The `HG-2` hard gate lifts for three of its four limbs.** `HG-2`: *"No Wallet push path, no door-manifest
   open transaction as specified, no scanner push-to-sync **and no notification** may ship before the outbox
   ruling is made."* `VERIFIED` The Wallet, door and scanner limbs are released by `ODR-2` alone. **The
   notification limb is released by `ODR-3`.**
2. **Package `076` can be authored** — subject to condition 1 of `ODR-2` §I, which makes the schema home a
   `SET SCHEMA` rather than a dependency on `ODR-3`. *(Note the standing disagreement: the register says the
   schema home *"is decided here"* under `ODR-3`; the prior brief lists the schema **name** as mechanical. The
   naming discipline makes both true.)*
3. **Sixteen facts get their carrier, and none of them waits on `ODR-3`** — enumerated at §F-bis 4, Tier 1:
   `#3 · #4 · #17 · #22 · #25 · #26 · #28 · #37 · #38 · #39 · #40 · #41 · #42 · #43 · #44` plus the unnumbered
   event-cancellation fact.
4. **The door packages stop being blocked.** `086` (`#37`, `#38`, `#39`, `#41`, `#42`, `#44`) and the two
   stub→body pairs — `083` → `086` for `#43`, `086` → `088` for `#40` — no longer wait on a carrier ruling. The
   register's deadline is *"Neither ruling can be deferred past `083`."* `VERIFIED`
5. **The four open events, and `#21`, become rulable afterwards rather than beforehand.** Their whole spread is
   four facts on a carrier whose cost is flat (§E-bis 6). `DF-23` made `G-25` a prerequisite to `ODR-2`; the
   pricing shows it is not. **`G-25` was still necessary — it is what makes that checkable.**
6. **`ODR-1` is untouched by `ODR-2`.** The outbox lands at `076`, inside the existing band. Only `ODR-3` moves
   the count.

## Still waiting on `ODR-3`, whichever way `ODR-2` goes

1. **Every notification type** — all 40 Phase-2 types, the 24 MANDATORY class, the preference model, the
   registry and the templates. Under Gate L, notifications continue on `057`/`058`/`0600` with the five verified
   gaps of §F-bis 2.
2. **`#31 AttributionRecorded` and `#32 PromoterCommissionAccrued`** — Tier 2 of §F-bis 4. Both collapse under
   Gate L. Both should be re-read at the **close** of the sitting, and they are the only rows the second ruling
   can change.
3. **`#9`, `#10`, `#27`** — Tier 3, contested, and the same open question as `#21 CredentialInvalidated`. Whether
   a built context with no handler is a consumer is a reading the owner has not yet made, and it should be made
   **once**, for all of `#2`, `#5`, `#9`, `#10`, `#11`, `#21` and `#27`, rather than row by row.
4. **`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §16.5** — binding under Gate P, must be re-scoped under Gate L,
   because RLS `MD-10` rules that no Gate-L object may carry a binding dependency.
5. **The package band and `ODR-1`'s signature** — sixteen and `076`–`091` under Gate L; seventeen and
   `076`–`092` under Gate P, with `ODR-1` re-signed conditionally.
6. **The mobile inbox (D-12), the delivery ledger (D-2), retry (D-10), push-rail dedupe (D-8) and preference
   enforcement (D-1)** — five verified production gaps, all of them `ODR-3`'s to close and none of them the
   outbox's.
7. **`O-N3` — does transactional email exist in Phase 2.** Not a sub-question of `ODR-3` but unanswerable
   before it, and 19 of the 24 MANDATORY types name `E`.

## The one sentence

> **`ODR-2` is a security decision about a single table whose cost does not vary with what it carries.
> `ODR-3` is a scope decision about a nine-table product platform. `COND-D` requires them in one sitting and in
> that order — it does not require them to have the same answer, and two of the three coherent combinations say
> yes to the first.**

---

## What could not be verified

Stated so no reader takes silence for confirmation.

1. **Nothing was verified against the database or the running system.** Every `VERIFIED` means *read at the
   cited file and line on `c89fcb4`*, or read in `supabase/migrations/` / `supabase/functions/` at that commit.
   No migration was applied, no query was run, no production surface was touched.
2. **The `risk` context and the *"reconciliation monitor"*** are named as consumers of `#38`, `#41` and `#42` in
   `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §12.2, and **no Gate-P handler for either could be found.** Marked `¹` in
   §F-bis 4, Tier 1. If neither is built at Gate P, those three rows move to Tier 3 and the Gate-L floor falls
   from sixteen to thirteen. It does not change any `ODR-2` total, because `ODR-2`'s totals do not depend on
   `ODR-3`.
3. **`#40 DoorManifestDrained` under `feature.native_resale_enabled = OFF`.** DOOR §12.2 marks it *"Sync (same
   txn as the drain)"* and §7.3 runs the drain on every open; **whether an envelope is written with empty
   `cancelled_transfer_ids[]` / `cancelled_listing_ids[]` when there is nothing to drain is stated in no spec.**
   `INFERENCE` that it is. If it is not, each of the three totals falls by one at Gate P and recovers at Gate M.
   *(Carried unchanged from `G25_FOUR_EVENT_OWNER_BRIEF.md`.)*
4. **`#42`'s producer is named by two paths and contracted as one** — `kernel.revoke_door_freeze_override` and
   `kernel.sweep_expired_door_overrides`. Which writes the envelope is not stated. `INFERENCE` that both do.
   *(Carried unchanged.)*
5. **`G-20`'s name divergences are carried, not resolved** — `catalog.approve_venue` / `set_venue_approval`
   (`#3`) and `catalog.publish_event` / `set_event_status` (`#4`). `PHASE_2_RPC_FUNCTION_CONTRACTS.md` is the
   canonical namer and has not ruled. *"Two names for one function produces two functions or none."*
6. **Citation drift on the line every `ODR-2` argument hangs from.** Registry `COND-A` `:761`, NOTIF `O-N2`,
   NOTIF §4.1 and the register's `ODR-2` entry all cite **`SNATCH_IT_DOMAIN_ARCHITECTURE.md:1253`** for the
   *"one outbox table and a drainer"* promise. At head that promise is at **`:1263`** and `:1253` is a blank
   line; DA §6.2's *"Eventual (outbox) set"*, cited as `:1248` in `G25_FOUR_EVENT_OWNER_BRIEF.md`, is at
   **`:1250`**. `VERIFIED` The **text** is intact and says what every citing document says it says; only the
   line numbers have drifted, presumably across edits to §6.2. Recorded because a reader checking the citation
   at head finds nothing there.
7. **The `[C]` option in `ODR-3` §I is constructed by this brief and proposed by no document.** Its package
   placement, its `SEAM-1` floor and its `ODR-1` consequence have not been worked. It is offered so the option
   space is honest, and it is **not** recommended.
8. **`DELTA-5b`'s package inference was not traced through `SEAM-1`.** That `venue.promoter_link` is read by
   `notify.drain_outbox` **only** for the two Group-M types is an `INFERENCE` from the type catalogue, not a
   statement any document makes. If the drainer reads it for another reason, the `092` floor stands regardless.

---

*Owner brief. Presents `ODR-2` and `ODR-3` as two separable decisions with three coherent combinations between
them; rules on neither. `ODR-2`, `ODR-3`, events `#2`, `#5`, `#11`, `#32` and the flagged `#21` all remain OPEN.
No file in the corpus is modified by this document, and no `OFFLINE-VERIFY-v1` block is touched.*
