# `G-25` — the four unresolved events, and the final `ODR-2` carrier requirement

**Status:** OWNER BRIEF. **Presents; does not rule.** `ODR-2`, `ODR-3` and all four events stay OPEN.
**Branch:** `docs/g25-four-events` off `phase2/consolidation` @ `c0d442f`.
**Reads from:** `_governance/G25_CANONICAL_EVENT_CATALOG.md` (the per-event authority), which this document
carries forward and does not overturn. Three places it is extended on cited evidence are marked
**`DELTA vs G-25`** and shown with the authority that forces them.
**Creates nothing, changes nothing.** No existing document is modified.

**Two rules, inherited from `G-25` and binding here.** No count appears without its enumeration. Every claim is
`VERIFIED` (read at the cited file and line on this branch) or `INFERENCE`. **`~N` appears nowhere.**

---

## PART 1 — the four events

### `#2 ConnectOnboardingCompleted`

**Row (DA §6.1 `:1185`).** Producer `core`; payload *"org/user id, connect id, capability flags"*; consumers
`venue`, `market`, `analytics`; **Async**; key `connect_account_id + capabilities_hash`. `VERIFIED`

**KEEP / REMOVE options.**
**KEEP** — as an outbox event, on the ground that two of its three named consumers (`venue`, `market`) are
built contexts, so `C11`'s criterion **(R2)** (*drop consumer matrices for unbuilt contexts*) does not catch
the row whole. **REMOVE** — on the ground that a named context is not a consumer until something in it reacts.

**What actually consumes it.**
**Nothing, in any package or any prose.** `VERIFIED:` the string `ConnectOnboardingCompleted` occurs in
exactly two files on this branch — `SNATCH_IT_DOMAIN_ARCHITECTURE.md` `:1185` and
`PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `:239`, `:684`, `:723`. The matrix's `:723` `✓ venue, market`
is a **context** tick, not a handler; its own §8 preamble sets the test — *"A consumer in a context that is not
built is not a consumer"* (`:717`) — and does not apply the converse test, that a built context with no handler
is not a consumer either.
**The fact it would carry is delivered by something else, synchronously.** `VERIFIED:`
`PHASE_2_EDGE_FUNCTION_SPEC.md` `:428`–`:429` — *"Capability flags (`charges_enabled`/`payouts_enabled`/
`details_submitted`) are synced by the **extended webhook** `account.updated` branch (§4), matched by
`connect_account_id` → org"*, and `:1160` gives that branch its own writer RPC. The flags land on
`kernel.organization` by a direct webhook write.
**Every reader reads the column, not a message.** `VERIFIED:` `PHASE_2_MONEY_AUTHORITY_SPEC.md` `:1212`
(*"`kernel.organization.stripe_connect_account_ref` is an opaque Stripe Connect account id"*);
`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` `:323`, `:1183`, `:1194` (the Connect ref is a column-scoped read,
rendered masked). No surface subscribes.

**Whether a handler exists.** **No named function, edge route or job can be found** in `venue` or `market` that
runs on this event. `VERIFIED` by exhaustive grep of the event name and of every capability-flag identifier
(`charges_enabled`, `payouts_enabled`, `capabilities_hash`, `connect_ready`) across `docs/architecture/`.

**Is an outbox row required for any existing Phase-2 feature? — NO, not for this event.**
**But its producer does need one, for a different and unnumbered fact.** `VERIFIED:`
`PHASE_2_NOTIFICATIONS_SPEC.md` §2.2 Group S defines **two MANDATORY** types on the Connect path —
`security_payout_destination_changed`, authority *"`connect-onboarding` + the `account.updated` webhook
branch"*, and `security_payout_method_added`, authority *"`connect-onboarding`"* — and NOTIF §4's pipeline is
`RPC / trigger / sweep → notify.outbox → notify.notification → notify.delivery` (`:678`). Neither type cites a
§6.1 event number; neither is `#2`. **So the carrier requirement on this code path is real and attaches to the
RPC, not to the catalogued event.** Keeping `#2` does not satisfy it; removing `#2` does not remove it.

**What breaks if removed.** Nothing that exists. The register keeps `G-3` — `kernel.set_org_connect_ref` is
contracted nowhere (`PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `:69`, `S1`; contract drafted at
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §20.1.1 `:4228`) — and `G-3` closes on its own merits either way. `VERIFIED`

**What complexity exists if kept.** One outbox `event_type` with **no consumer to write**, which is the exact
defect `G-19` names elsewhere in the corpus (*preference toggles "that gate nothing"*). It also promotes `G-3`
from an RPC gap to an outbox-blocking defect, because a kept event with no producer is a second open item
rather than one. `INFERENCE` on the promotion; `VERIFIED` that `#2` has no producer (TRACE `:723`).

**Engineering recommendation: REMOVE.** The fact is already durable via `account.updated`, every reader reads
the column on demand, and no handler exists to be written against. If a `venue` or `market` handler is ever
specified, the row returns unchanged — DA §6.3 `:1174` guarantees names and keys do not change.

---

### `#5 TicketTypeOpened / TierUnlocked`

**Row (DA §6.1 `:1188`).** Producer `venue`; payload *"ticket_type id, tier rank, price, capacity"*; consumers
`market (eligibility)`, `analytics`; **Async**; key `ticket_type_id + tier_rank`. `VERIFIED`

**KEEP / REMOVE options.**
The `TierUnlocked` arm is **REMOVE, settled** — *"no tier concept exists in `venue.ticket_type` in any
package, so the `TierUnlocked` arm has no producer"* (TRACE `:726`). `VERIFIED` The row must at minimum be
**renamed to `TicketTypeOpened`** under any ruling. For the surviving arm: **KEEP** as a Gate-P outbox event
because `market` is a built context; **REMOVE until Gate M** because the eligibility `market` computes is
native-rail resale eligibility.

**What actually consumes it.**
**`market (eligibility)` — and market's eligibility is computed live, not delivered.** `VERIFIED:`
`market.listing_unified` is a **VIEW**, `security_invoker`, a UNION of `public.listings` and
`market.listing_native` (`PHASE_2_SUPABASE_MIGRATION_PLAN.md` `:1009`, `:1484`;
`PHASE_2_RLS_PERMISSION_SPEC.md` `:1724`; `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §4.6 `:3516`). A view has
no handler and holds no cache.
**The one surface that reads ticket-type availability reads it live.** `VERIFIED:`
`PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` `:169` — *"`venue.inventory_batch.remaining` (C27 counter, **live read
for availability**)"*.
**A cached-eligibility notion does exist in the corpus, and it is not fed by this event.** `VERIFIED:`
`PHASE_2_DOOR_LIFECYCLE_SPEC.md` §12.2 `:1579` gives event `#39 TransferFreezeEngaged` the consumer
*"market (invalidate cached eligibility)"*. That is the only place a `market` eligibility cache is named, and
its invalidator is `#39`, not `#5`. `INFERENCE` that the two would share a cache if one were built; `VERIFIED`
that only `#39` names it. Both arms of that cache are inert while `feature.native_resale_enabled` is OFF.
**No Phase-2-package consumer exists.** The `market` tick in TRACE `:726` is a context tick, as for `#2`.

**Whether a handler exists.** **None can be found.** No function, edge route or job in any spec runs on
ticket-type opening. `VERIFIED` by grep of `TicketTypeOpened` (three files: DA, TRACE, `G-25`) and by reading
all forty notification types in `PHASE_2_NOTIFICATIONS_SPEC.md` §2.2 — **there is no on-sale, tickets-available
or ticket-type-opened notification in the catalogue**, in any of Groups P/T/R/E/F/S/M/V.

**Is an outbox row required for any existing Phase-2 feature? — NO.** No Wallet trigger (`PHASE_2_APPLE_WALLET_SPEC.md`
§6.3 `:685`–`:700`), no door envelope (DOOR §12.2), no notification type, no dashboard counter fires from it.
`VERIFIED` This is the only one of the four for which the answer is unqualified.

**What breaks if removed.** Nothing that exists, and — unlike `#2` and `#11` — not even a sibling fact on the
same producer. `VERIFIED`

**What complexity exists if kept.** A Gate-P outbox `event_type` whose only consumer is a Gate-M feature; and
the row keeps a two-name shape whose second name has no producer, which is the defect the rename exists to
close.

**Engineering recommendation: RENAME to `TicketTypeOpened`, then REMOVE until Gate M.** Do the rename in DA
§6.1 regardless of the KEEP/REMOVE ruling — a catalogued name with no producer anywhere is a standing
correctness claim the schema cannot honour. Restore the renamed row at Gate M with `market.create_listing`,
where its consumer becomes real.

---

### `#11 TicketReserved`

**Row (DA §6.1 `:1194`).** Producer `venue`; payload *"ticket_type, hold id, buyer, expires_at"*; consumers
`venue`, `analytics`; **Async**; key `hold_id`. `VERIFIED`

**KEEP / REMOVE options.** **KEEP** — TRACE `:732` records the consumer as `✓ venue`, present, and nothing in
the corpus says an event needs a foreign consumer. **REMOVE** — its only surviving consumer is its own
producing context, and its one cross-context consumer, `analytics`, is deferred by `C11`.

**What actually consumes it.**
**Its own producing statement.** `VERIFIED:` `venue.reserve_primary_inventory` (`PHASE_2_RPC_FUNCTION_CONTRACTS.md`
§5.3 `:879`) writes `venue.inventory_hold` and takes `FOR UPDATE` on the inventory counter in the same
transaction (`:2130`, `C27`). The `venue (counters)` consumer named in §6.1 **is that same transaction's own
write** — `venue` reading a row `venue` has just written.
**The corpus never states whether the outbox carries intra-context events.** `VERIFIED:` DA §6.0/§6.3 and
`SNATCH_IT_CANONICAL_DATA_MODEL.md` §2 `:294` describe events as the cross-aggregate channel; **neither
declares an intra-context event inadmissible.** This is why the row is open and not classified.

**Whether a handler exists.** **None can be found** that runs on `TicketReserved`. The nearest scheduled work
on the same table is `venue.sweep_expired_inventory_holds(p_limit)` — and it is a **scheduler**, not a
consumer: *"it needs a **scheduler**, not the outbox **carrier**, so it is **NOT** blocked on the `COND-A`
ruling"*, `LOAD-BEARING` (`PHASE_2_SUPABASE_MIGRATION_PLAN.md` `:1353`). `VERIFIED`

**Is an outbox row required for any existing Phase-2 feature? — NO, not for this event.**
**But its producer does need one, for a different and unnumbered fact — the same shape as `#2`.** `VERIFIED:`
`PHASE_2_NOTIFICATIONS_SPEC.md` §2.2 Group V defines `staff_low_inventory`, trigger
*"`venue.inventory_batch.remaining` crosses a configured threshold"*, authority ***"`venue` reserve/issue RPCs,
post-commit"***, dedupe `low_inventory:<batch_id>:<threshold>`. It cites no §6.1 number, and the fact it
carries is a **threshold crossing**, not a reservation. **The reserve RPC therefore writes a post-commit outbox
row under `ODR-3 = Gate P` whether or not `#11` survives.**

**What breaks if removed.** Nothing that exists. The `held` counter is restored by the sweep, in its own
transaction, on the 2-minute heartbeat that already runs. `VERIFIED` (plan `:1353`)

**What complexity exists if kept.** It makes the outbox the carrier for a fact that never leaves one schema,
and it does so without a written rule — so the next intra-context candidate has no precedent to follow except
this one. Whichever way the owner rules, **the ruling is worth writing down as a general rule**, because it is
the rule the corpus is missing, not the row.

**Engineering recommendation: REMOVE, and record the general rule that the outbox carries cross-context facts
only.** The rule is the deliverable; the row is the occasion. `#6 InventoryHeldExpired` has the same shape and
is already removed on independent authority (plan `:1353`), so the rule is consistent with a decision the
corpus has already made once.

---

### `#32 PromoterCommissionAccrued`

**Row (DA §6.1 `:1215`).** Producer `core`; payload *"payout id (type=commission), promoter, amount"*;
consumers `venue`, `notifications`, `analytics`; **Async**; key `attribution_id`. `VERIFIED`

**KEEP / REMOVE options.** **KEEP** as an outbox event; **REMOVE** and let the promoter engine keep its
settlement-close path, dropping or re-sourcing the notification.

**The contradiction, re-scored. `DELTA vs G-25`.** `G-25` §6.4 scores this two ratified surfaces against one.
**It is four against two, and the two are true about a different thing.** `VERIFIED`, each read directly:

| Side | Statement | Where |
|---|---|---|
| **carrier needed** | *"**Eventual (outbox) set:** every notification, every analytics rollup, every social feed update, **promoter-commission accrual**, payout release …"* — **the constitution's own prose, naming this fact explicitly** | `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.2 `:1248` |
| **carrier needed** | §6.1 row `#32` is **Async** with no `Sync` arm | DA `:1215` |
| **carrier needed** | *"DA §6.1 classifies every notification, rollup, **commission accrual** and transfer-expiry as Async/outbox"* — **inside the `COND-A` row itself** | `PHASE_2_PACKAGE_REGISTRY.md` §7 `:761` |
| **carrier needed** | notification type `promoter_commission_accrued`, channel `I p E`, class `ON`, dedupe `commission:<attribution_id>`, **trigger `#32 PromoterCommissionAccrued`** | `PHASE_2_NOTIFICATIONS_SPEC.md` §2.2 Group M `:445` |
| **no carrier** | *"**Unaffected:** CRM export …, demographics, **promoter codes**, and money authority — each carries its own scheduler"* | `PHASE_2_PACKAGE_REGISTRY.md` §7 `:777` |
| **no carrier** | *"promoter codes (**no async at all**)"* | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.3 `:4146` |

**`PHASE_2_PACKAGE_REGISTRY.md` §7 contradicts itself sixteen lines apart** — `:761` puts commission accrual on
the outbox, `:777` lists promoter codes as unaffected by the outbox ruling. `VERIFIED`, both lines read on this
branch. `G-25` cited only the second.

**What actually consumes it — and the resolution the money path supplies.**
**The money path consumes nothing asynchronously, and the corpus is right about that.** `VERIFIED:`
- the **accrual** is `venue.attribution.credited_amount_minor`, *"the accrual at freeze"*, frozen in the same
  transaction that marks the order paid (`PHASE_2_PROMOTER_CODES_SPEC.md` `:282`, `:800`; ratified `D7`);
- the **commission line** is produced inside `kernel.close_settlement` through the
  `kernel.settlement_commission_lines` SEAM-2 hook, stubbed `087` and replaced `090`
  (TRACE `:371`; plan `:1501`);
- the **payout row** is INSERTed `pending` by `kernel.pay_promoter_commission`, reached by `close_settlement`
  through that hook, in the same transaction (plan `:1176`; `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` `:863`).

**The only consumer that needs a carrier is the notification** — `promoter_commission_accrued`, and it is
class **`ON`** (opt-out-able), not MANDATORY (NOTIF §2.3 `:474`). `VERIFIED` It is the **weakest carrier claim
of any event in Part 2's enumerations**, and that is worth saying plainly.

**Whether a handler exists.** **Producer:** `kernel.pay_promoter_commission`, **authored in `090`** (plan
`:1501`), **uncontracted** — `G-7`, `S1` (TRACE `:73`). **Consumer:** `notify.drain_outbox` →
`promoter_commission_accrued`, which exists only if `ODR-3` puts `notify` at Gate P. No `venue`-side handler
can be found; the `✓ venue` at TRACE `:753` is a context tick.

**Is an outbox row required for any existing Phase-2 feature? — YES, for exactly one, and only under
`ODR-3 = Gate P`.** The feature is the `promoter_commission_accrued` notification. **Under `ODR-3 = Gate L`
the answer is NO** and registry `:777` / schema `:4146` are correct as written. `VERIFIED`

**What breaks if removed.** One `ON`-class notification type must be deleted from `PHASE_2_NOTIFICATIONS_SPEC.md`
§2.2 Group M or re-sourced, and DA §6.2 `:1248`'s *"promoter-commission accrual"* clause must be struck from the
constitution's Eventual set. **Nothing in the money path breaks** — it never depended on delivery. `VERIFIED`

**What complexity exists if kept.** The registry's `:777` `unaffected` line must be corrected to say
*"no async **in the money path**"* — which is the sentence both sides are actually agreeing on. `INFERENCE`
that this correction dissolves the contradiction; `VERIFIED` that it is the only claim `:761` and `:777` make
about different objects.

**Engineering recommendation: KEEP as an outbox event, conditional on `ODR-3`, and correct
`PHASE_2_PACKAGE_REGISTRY.md` §7 `:777` either way.** Rationale: the constitution names the fact in its own
Eventual set; the marginal cost of the row is zero once the table exists for nineteen other events; and the
correction to `:777` is required under **both** rulings, because as written it is falsified by `:761` sixteen
lines above it, independently of `ODR-2` and `ODR-3`.
**Rider, stated so the ruling is not overstated:** if `ODR-3 = Gate L`, `#32` has no consumer and collapses to
REMOVE with no further work. `COND-D` already requires `ODR-2` then `ODR-3` in one sitting; **this row should
be re-read at the end of that sitting**, and it is the only one of the four whose answer the second ruling can
change.

---

### Part 1 summary

| # | Event | Outbox row required for an existing Phase-2 feature? | Recommendation |
|---|---|---|---|
| 2 | `ConnectOnboardingCompleted` | **No** — but the producer needs one for two MANDATORY `security_*` types that are not this event | **REMOVE** |
| 5 | `TicketTypeOpened` *(`/ TierUnlocked` struck)* | **No** — unqualified | **RENAME, then REMOVE until Gate M** |
| 11 | `TicketReserved` | **No** — but the producer needs one for `staff_low_inventory`, which is not this event | **REMOVE** + write the cross-context rule |
| 32 | `PromoterCommissionAccrued` | **Yes, one**, class `ON`, only under `ODR-3 = Gate P` | **KEEP**, conditional on `ODR-3`; correct registry `:777` either way |

**The pattern across three of the four.** For `#2` and `#11`, a Gate-P carrier requirement **does** exist on the
producing RPC — and it is for a fact `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1 does not number. Removing the
catalogued row does not reduce the carrier load by one; keeping it does not increase it by one. **The catalog
row and the carrier requirement are, for these events, not the same object** — which is the same discovery
`G-25` made from the other direction when it found `Sync` events writing outbox rows.

---

## PART 2 — the final `ODR-2` carrier requirement

### 2.0 The base — nineteen numbered events plus one unnumbered fact, common to all three scenarios

**Independent of all four open events.** Every row below is required by a **named** consumer in a ratified
spec. Gate-M events are excluded, so this is the **Gate-P** load. Package column = the package that creates the
**producer**.

| # | Canonical name | Producer | Consumer | Why it needs a carrier | Producer's package |
|---|---|---|---|---|---|
| 3 | `VenueApproved` | `catalog.approve_venue` *(alias `set_venue_approval`, `G-20`)* | `venue` | Async, no `Sync` arm; built cross-context consumer (TRACE `:256`, `:724`) | **`078`** |
| 4 | `EventPublished` | `catalog.publish_event` | `venue`, `market` | Async, no `Sync` arm; built cross-context consumers (TRACE `:256`) | **`081`** |
| 9 | `PaymentCaptured` | `stripe-webhook` → `venue.finalize_primary_order` | `notify` — `purchase_confirmed` (**MANDATORY**) | **`Sync` event, post-commit row.** DA §6.2 `:1242` enqueues it inside the custody txn; NOTIF §2.2 Group P fires from it | **`085`** (`C111`) |
| 10 | `TicketIssued` | `kernel.issue_ticket_atoms` | `notify` — `ticket_ready` (**MANDATORY**) | **`Sync` event, post-commit row** | **`083`** (`C114`) |
| 17 | `OwnershipTransferred` | `kernel.transfer_ticket_ownership` | `wallet-pass-push` (`credential_version` bump, **always**); `notify` — `ownership_changed` (**MANDATORY**) | **`Sync` event, post-commit row.** Wallet supersession runs *"in the **outbox consumer**, deliberately **not** inside the custody transaction"*; WALLET §16 `:1740` makes *"Wallet can never block or roll back a transfer"* a preserved invariant | **`088`** (`FR-3`) |
| 22 | `ScanAdmitted` | `venue.record_scan` | `wallet-pass-push` (atom → `scanned`, best-effort); offline reconciliation | **`Sync` online, `outbox-reconciled` offline — §6.1's own words** (DA `:1205`; TRACE `:744`) | **`086`** |
| 25 | `PayoutReleased` | `payout-execute` → `kernel.release_payout` | `venue`, `market`; `notify` — `payout_released` (**MANDATORY**) | *"Async (**deferred by design**)"* — the only row whose asynchrony is itself ratified | **`085`** |
| 26 | `PayoutFailed` | `payout-execute` → `kernel.mark_payout_transfer_state` | `venue`/`market`; `notify` — `payout_failed` (**MANDATORY**) **and** `staff_payout_failed` (**MANDATORY**, `CONFLICT-5`) | Async, no `Sync` arm; two mandatory fan-outs | **`085`** (`MB-2`) |
| 27 | `RefundIssued` | `kernel.refund_primary_order` | `notify` — `refund_completed` (**MANDATORY**) | **`Sync` event, post-commit row** | **`085`** |
| 28 | `TicketVoided` | `kernel.void_ticket_atom` | `wallet-pass-push` (`credential_version` bump, **always**) | **`Sync` event, post-commit row.** The void path is the second driver of `supersede_wallet_passes_for_atom`, which is definer-only and *"called from the **outbox consumer, not inside the custody transaction**"* (WALLET `:1297`) | **`085`** |
| 31 | `AttributionRecorded` | `venue.resolve_order_attribution` | `notify` — `promoter_attribution_recorded` (`OFF`) | **`Sync` event, post-commit row.** The money write is same-tx by ratified `D7`; only the notice is eventual | stub **`085`** → body **`090`** |
| 37 | `DoorManifestOpened` | `venue.open_door_manifest` | `notify` (fan *"transfers closed"*), **scanner push-to-sync**, analytics, risk | **Envelope INSERTed inside the all-or-nothing open txn** — DOOR §6 step 11 `:492`; steps 5–11 are all-or-nothing | **`086`** |
| 38 | `DoorManifestClosed` | `venue.close_door_manifest` | `notify`, reconciliation monitor | Same open/close transaction discipline (DOOR §12.2 `:1578`) | **`086`** |
| 39 | `TransferFreezeEngaged` | `catalog.engage_door_freeze` (explicit open) · `catalog.sweep_implicit_door_freezes` (implicit) | `notify` (pre-freeze warning + freeze notice), `market` (invalidate cached eligibility) | `Sync` for `explicit_open`, Async for `implicit_doors_time`; at most once per session, ever (DOOR `:1579`) | **`086`** |
| 40 | `DoorManifestDrained` | `market.on_door_freeze_engaged` (SEAM-2 hook, same txn as the drain) | `notify` (per affected party); `wallet-pass-push` (best-effort) | **`Sync` (same txn as the drain)**; and it is one of Wallet §6.3's six named triggers | stub **`086`** → body **`088`** (`C110`) |
| 41 | `DoorFreezeOverrideGranted` | `kernel.grant_door_freeze_override` | `risk`, `notify` (platform ops) | Envelope written in the granting txn (DOOR `:1581`) | **`086`** |
| 42 | `DoorFreezeOverrideEnded` | `kernel.revoke_door_freeze_override` · `kernel.sweep_expired_door_overrides` | `risk` | Async (DOOR `:1582`) | **`086`** |
| 43 | `DoorManifestSupplemented` | `venue.append_door_manifest_delta` (§7.7) | **scanner push-to-sync** | *"`Sync` (same txn as §7.7)"*; DOOR `:826` — emitted *"so online devices re-sync promptly"* | stub **`083`** → body **`086`** (`C113`) |
| 44 | `DoorManifestInvalidated` | `venue` force-close paths (§7.2.1) | **scanner (drop M2, disarm)**, dashboard alert, risk | DOOR `:604` — *"so online devices disarm immediately"*; `:907` — cached M2 dropped on receipt | **`086`** |
| — | **event-cancellation** *(unnumbered — §6.1 names no cancellation or session-change event)* | `catalog.cancel_event` | `notify` — `event_cancelled` (**MANDATORY**), sourced *"SSCAS #10 event-cancellation cascade"*; `wallet-pass-push` — *"session time / venue / status change, `catalog.cancel_event`"*, **always** priority, source *"catalog outbox"*; DOOR §7.2.1 → `#44` | **Three ratified surfaces consume a fact the catalog does not name.** `A-SSCAS` member **#10** (CDM `:611`) is the only NOTIF trigger citing an SSCAS member instead of an event number, *because there is no number to cite* | **`088`** (Δ `catalog.cancel_event`) |

**Nineteen numbered, enumerated: `#3 · #4 · #9 · #10 · #17 · #22 · #25 · #26 · #27 · #28 · #31 · #37 · #38 ·
#39 · #40 · #41 · #42 · #43 · #44`. Plus one unnumbered fact. Base = 20 facts.**

**Of the nineteen: eight (`#37`–`#44`) postdate `C11` entirely** — DOOR §12.2 `:1586` states *"Numbering
continues the domain-architecture §6.1 catalog (which ends at 36)"*, and its closing note is decisive for
`ODR-2`: *"none of these are money or custody events; none ride the transactional spine … **except as outbox
rows written inside their own transaction**"*. `VERIFIED`

**Of the nineteen: seven are `Sync` events that still need a post-commit outbox row** — enumerated
**`#9 · #10 · #17 · #22 · #27 · #28 · #31`**. This is the category the corpus has consistently miscounted, and
it is where Wallet supersession (`#17`, `#28`) and the door-manifest drain (`#40`, itself `Sync`) live.
`VERIFIED`

**Only four of the nineteen are "real outbox events" in `C11`'s sense** — `#3 · #4 · #25 · #26`.

---

### 2.1 A twenty-first numbered candidate, flagged and **not counted**. `DELTA vs G-25`

**`#21 CredentialInvalidated`.** `G-25` §1.4 and §7.1 both cite DA §6.2's diagram as enqueuing it —
`VERIFIED`, `SNATCH_IT_DOMAIN_ARCHITECTURE.md` `:1242`: *"`CORE->>OUT: enqueue OwnershipTransferred,
PaymentCaptured, CredentialInvalidated`"* — and §7.2 then **omits it from the carrier union**. Both moves are
defensible and the corpus supports the omission:

- **For counting it.** The constitution's own sequence diagram writes it to the outbox inside the custody
  transaction, alongside `#17` and `#9`, which §7.2 does count. `VERIFIED`
- **For not counting it.** Its named consumer is `venue.append_door_manifest_delta`, and RPC §12.4c binds every
  voiding path to write the `revoke` delta **in-transaction** — *"Omitting it re-opens the offline-revocation
  leak the exemptions were granted around"* (plan `:1411`). The diagram's own drain arrow
  (`OUT-->>MKT: (async) notify · analytics · delist`) sends the enqueued row to `notify` (`ODR-3`-conditional),
  `analytics` (deferred by `C11`), and `delist` (`market`, Gate M) — **no Gate-P consumer.** `VERIFIED`

**It is recorded, not counted, in all three scenarios.** If the owner rules that the constitution's diagram is
itself a carrier requirement, every total below rises by exactly one. Stated here so the number is checkable
rather than assumed.

---

### 2.2 Unnumbered facts beyond the event-cancellation one — recorded, **not counted**

The mandated third inclusion is the event-cancellation fact, and it is counted above. **It is not the only
unnumbered fact NOTIF §4's pipeline carries.** `VERIFIED:` `notify.outbox` keys on *"`event_key` = the §6.1
idempotency key of the business event … **plus** `event_type`"* (`:700`), and these Gate-P-reachable types cite
**no** §6.1 number:

`wallet_pass_available` (first successful `credential-sign`) · `purchase_failed`
(`payment_intent.payment_failed`) · `event_time_changed` · `event_venue_changed` · `event_postponed` (all three
`catalog.update_event_session`) · `organizer_announcement` (`notify.approve_announcement`) ·
`refund_requested` · `refund_approved` · `refund_failed` · `security_password_changed` ·
`security_payout_destination_changed` · `security_org_role_granted` · `security_org_role_revoked` ·
`security_payout_method_added` · `staff_low_inventory` · `staff_door_anomaly` — **sixteen.**
*(`event_reminder_24h`, `event_door_open` and `staff_sales_digest` are excluded: their trigger is
`notify.sweep_scheduled()`, a scheduler.)*

**Every total below is therefore a floor, not a ceiling** — and the sixteen are `ODR-3`-conditional in full, so
they change nothing about `ODR-2`'s table. They are enumerated so no reader mistakes the three totals for the
whole carrier surface.

---

### 2.3 Scenario 1 — **all four unresolved events REMOVED**

**Carrier set = the base of §2.0, unchanged.** `#2`, `#5`, `#11` and `#32` contribute nothing.

**Enumeration — nineteen numbered:**
`#3 VenueApproved` · `#4 EventPublished` · `#9 PaymentCaptured` · `#10 TicketIssued` ·
`#17 OwnershipTransferred` · `#22 ScanAdmitted` · `#25 PayoutReleased` · `#26 PayoutFailed` ·
`#27 RefundIssued` · `#28 TicketVoided` · `#31 AttributionRecorded` · `#37 DoorManifestOpened` ·
`#38 DoorManifestClosed` · `#39 TransferFreezeEngaged` · `#40 DoorManifestDrained` ·
`#41 DoorFreezeOverrideGranted` · `#42 DoorFreezeOverrideEnded` · `#43 DoorManifestSupplemented` ·
`#44 DoorManifestInvalidated`.
**Plus one unnumbered:** the **event-cancellation** fact (`catalog.cancel_event`).

Producer, consumer, reason and package for each: **§2.0's table**, row for row, with no additions.

> **TOTAL — Scenario 1: 19 numbered events + 1 unnumbered fact = 20 facts.**
> Of these: **8** postdate `C11` (`#37`–`#44`) · **7** are `Sync` events needing a post-commit row
> (`#9 · #10 · #17 · #22 · #27 · #28 · #31`) · **4** are `C11`-sense outbox events (`#3 · #4 · #25 · #26`).
> **This is the floor. It is not zero, and it is not `~6`.**

---

### 2.4 Scenario 2 — **engineering-recommended choices applied**

**Applied:** `#2` REMOVE · `#5` RENAME then REMOVE-until-Gate-M · `#11` REMOVE · **`#32` KEEP**.

**Enumeration — the nineteen of §2.3, plus one:**

| # | Canonical name | Producer | Consumer | Why it needs a carrier | Producer's package |
|---|---|---|---|---|---|
| 32 | `PromoterCommissionAccrued` | `kernel.pay_promoter_commission` *(uncontracted — `G-7`)*, reached by `kernel.close_settlement` via the `kernel.settlement_commission_lines` SEAM-2 hook | `notify` — `promoter_commission_accrued`, channel `I p E`, class **`ON`**, dedupe `commission:<attribution_id>` | Named in the constitution's own **Eventual (outbox) set** (DA §6.2 `:1248`) and in registry §7 `:761`; NOTIF §2.2 Group M `:445` fires from it. **The money path needs no carrier** — accrual is frozen same-tx (`D7`), the commission line and payout row are written inside `close_settlement` | **`090`** |

**Plus one unnumbered:** the **event-cancellation** fact, as §2.0.

> **TOTAL — Scenario 2: 20 numbered events + 1 unnumbered fact = 21 facts.**
> Of these: **8** postdate `C11` · **7** are `Sync` events needing a post-commit row · **5** are `C11`-sense
> outbox events (`#3 · #4 · #25 · #26 · #32`).
> **This reproduces `G25_CANONICAL_EVENT_CATALOG.md` §7.2's twenty-plus-one exactly** — which is the check that
> the recommendations in Part 1 are the set `G-25`'s own pricing already assumed.
> **`#32` is the single row `ODR-3` can delete from this total; deleting it yields Scenario 1's twenty.**

---

### 2.5 Scenario 3 — **all four unresolved events KEPT**

**Enumeration — the twenty of §2.4, plus three:**

| # | Canonical name | Producer | Consumer | Why it needs a carrier | Producer's package |
|---|---|---|---|---|---|
| 2 | `ConnectOnboardingCompleted` | `kernel.set_org_connect_ref` — **uncontracted, `G-3` (`S1`)**; contract drafted at RPC §20.1.1 `:4228`; edge-fronted by `connect-onboarding` (edge §3.3) | `venue`, `market` — **named contexts, no handler found in either** | **None that can be found.** Kept only on the reading that a built context is a consumer. The capability flags it would carry are already written synchronously by the `account.updated` webhook branch (edge `:429`, `:1160`) | **`077`** |
| 5 | `TicketTypeOpened` *(`/ TierUnlocked` struck — that arm has no producer in any package)* | `venue.create_ticket_type` / `set_ticket_type_price` | `market (eligibility)` — **a `security_invoker` VIEW, `market.listing_unified`; no handler, no cache** | **None that can be found at Gate P.** The only named eligibility cache in the corpus is invalidated by `#39`, not by this event, and is inert while `feature.native_resale_enabled` is OFF | **`081`** |
| 11 | `TicketReserved` | `venue.reserve_primary_inventory` | `venue` — **its own producing context**, the same transaction's write of `venue.inventory_hold` | **None cross-context.** Kept only on the reading that the outbox carries intra-context events, which the corpus neither permits nor forbids | **`081`** |

**Plus one unnumbered:** the **event-cancellation** fact, as §2.0.

**Full enumeration — twenty-three numbered:**
`#2 · #3 · #4 · #5 · #9 · #10 · #11 · #17 · #22 · #25 · #26 · #27 · #28 · #31 · #32 · #37 · #38 · #39 · #40 ·
#41 · #42 · #43 · #44`.

> **TOTAL — Scenario 3: 23 numbered events + 1 unnumbered fact = 24 facts.**
> Of these: **8** postdate `C11` · **7** are `Sync` events needing a post-commit row · **8** are `C11`-sense
> outbox events (`#2 · #3 · #4 · #5 · #11 · #25 · #26 · #32`) — which is `G-25` §5.3's upper bracket, reached.
> **Three of the four rows added here have no named consumer that can be found** (`#2`, `#5`, `#11`); they add
> `event_type` values, not consumers.

---

### 2.6 The answer, plainly

**How many events must the outbox carry?**

| Scenario | Numbered events | Unnumbered facts | **Total facts** |
|---|:---:|:---:|:---:|
| **1 — all four REMOVED** | **19** | 1 | **20** |
| **2 — engineering recommendation** | **20** | 1 | **21** |
| **3 — all four KEPT** | **23** | 1 | **24** |

**The spread is four facts — 20 to 24 — and every number in it is more than three times `C11`'s `~6`.**
Neither `36` nor `~6` is the number that prices `ODR-2`.

**Which of these numbers changes the cost of building it: none of them.**

It is **the same table and the same drainer either way.** `VERIFIED`, from the corpus's own `(a)`-side pricing:
package **`076`**, *"the table has zero FK dependencies, so **no producer package gains an edge**"*
(`PHASE_2_PACKAGE_REGISTRY.md` §7 `:761`); the drainer is *"one table plus one RPC on a cron that already
runs — the constitution's own anti-over-engineering budget"* (`PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N2`
`:1505`); `notify.drain_outbox(p_limit int)` is a single `service_role` RPC on the existing 2-minute
`pg_cron` heartbeat, holding one advisory lock (`:756`–`:762`). **Nothing in that construction scales with the
number of `event_type` values.** Twenty facts and twenty-four facts cost the same table, the same
`UNIQUE (event_type, event_key)`, the same drainer, the same advisory lock, the same retention policy.

**What the count does change is the `(b)` side.** Under `ODR-2 = (b)` — *withdraw the promise* — every fact in
the enumeration needs a stated alternative transport, and the register already prices four capability families
as *"unimplementable **as designed**, not merely degraded"*, with the Wallet push path carrying *"**no
admissible alternative design**"*. **The enumerations above show that list is not `~6` notification rows: it is
eight door-lifecycle events written inside an all-or-nothing transaction, seven `Sync` events whose post-commit
effects include Wallet supersession, and one unnumbered cancellation fact three ratified surfaces consume.**
The volume argument for `(b)` is therefore weaker than `C11`'s `~6` makes it look, and the volume argument for
`(a)` is not a cost argument at all — because the cost is flat.

**Two consequences for the ruling, stated and not taken.**

1. **The four events do not price `ODR-2`.** Their entire spread is four facts on a carrier whose cost does not
   vary with facts. **They can be ruled after `ODR-2` without changing it** — which is the opposite of what
   `DF-23` assumed when it made `G-25` a prerequisite. `G-25` was still necessary: it is what makes this
   statement checkable rather than a guess.
2. **`ODR-3` moves exactly one row of the twenty-one.** `#32`, and only `#32`. `#3`, `#4`, `#37`–`#44` and the
   scanner paths have `venue`, `market` and device consumers that survive `notify = Gate L` untouched.
   `COND-D`'s ordering rule — `ODR-2` first, then `ODR-3`, one sitting — is unaffected, and Part 1 recommends
   `#32` be re-read at the close of that sitting.

---

## What could not be verified

1. **Nothing was verified against the database or the running system.** Every `VERIFIED` means *read at the
   cited file and line on `c0d442f`*. No migration was applied, no query was run.
2. **`#40 DoorManifestDrained` under `feature.native_resale_enabled = OFF`.** DOOR §12.2 marks it *"`Sync`
   (same txn as the drain)"* and §7.3 runs the drain on every open; whether an envelope is written with empty
   `cancelled_transfer_ids[]` / `cancelled_listing_ids[]` when there is nothing to drain **is not stated in any
   spec**. `INFERENCE` that it is; if it is not, Scenario 1/2/3 numbered totals each fall by one at Gate P and
   recover at Gate M.
3. **`#42 DoorFreezeOverrideEnded`'s producer is named by two paths and contracted as one.** DOOR §12.2 gives
   `ended_by ∈ {revoke, expiry}`; plan `:1429` names `kernel.revoke_door_freeze_override` and
   `sweep_expired_door_overrides` in `086`, and marks the latter as *not* load-bearing. Which of the two writes
   the envelope is not stated. `INFERENCE` that both do.
4. **`G-20`'s name divergences are carried, not resolved** — `catalog.approve_venue` / `set_venue_approval`
   (`#3`) and `catalog.publish_event` / `set_event_status` (`#4`). `PHASE_2_RPC_FUNCTION_CONTRACTS.md` is the
   canonical namer and has not ruled.
5. **`#2`'s producer package is `077` by the plan's Functions row (`:1282`), not by a contract.** `G-3` leaves
   `kernel.set_org_connect_ref` uncontracted; the package attribution is the plan's, and RPC §20.1.1 is a
   proposal.
6. **The sixteen unnumbered notification facts of §2.2 were enumerated but not individually traced to a
   producer package.** They are `ODR-3`-conditional in full and are excluded from every total, so no total
   depends on that trace.
7. **`#21 CredentialInvalidated` is left flagged rather than decided** (§2.1). The evidence on both sides is
   `VERIFIED`; the choice between them is a reading of whether the constitution's sequence diagram is itself a
   carrier requirement, and that is not this document's to make.

---

*Owner brief. Presents four open events and three priced enumerations; rules on none of them. `ODR-2`, `ODR-3`
and events `#2`, `#5`, `#11`, `#32` remain OPEN. `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1 still carries all 36
rows unmarked and is unmodified by this document, as is every other file in the corpus.*
