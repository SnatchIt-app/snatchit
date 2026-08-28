# `ODR-2` — BUILD Consequence Map (owner ruling `OR-4`, corpus option `[A]`)

**2026-08-28.** Analysis and mapping only. No architecture contract was edited to create this.

> ## THE DERIVED COUNT IS **15**, NOT 21.
>
> ```
> STRICT OUTBOX FACTS: 15
> ENUMERATION CHECK:   PASS   (12 numbered + 3 unnumbered = 15)
> ```
>
> The predicted 21 was computed **before** the strict test was ruled, and admitted eight rows on a
> context tick alone. Applying `OR-4`'s ruled methodology uniformly:
>
> **21 − 8 + 2 = 15.**
> **Removed (8):** `#3` · `#4` · `#37` · `#38` · `#39` · `#41` · `#42` · `#43`
> **Added (2):** the session time/venue/status-change fact and the pass-type-certificate-rotation
> fact — two unnumbered Wallet-driven facts prior passes folded away or recorded as "not counted".
>
> `OR-4` ratifies exactly this discipline: *"a context reference is not a handler; the count is
> always derived from the enumeration."* **The predicted 21 is the number that rule was written to
> correct.** It is not preserved.

## 1. The strict enumeration — 15 facts

**The test, as ruled:** an event requires a carrier ONLY when a **named** Phase-2 post-commit
consumer/handler exists, or a **ratified contract** requires the post-commit effect.

**What counts as a named handler:** an edge function or RPC named as an outbox consumer
(`wallet-pass-push`, `kernel.supersede_wallet_passes_for_atom`); or a **notification type row** —
type key + channels + class + dedupe key + target + params + recipient derivation + authority to
emit. That is a fully specified handler, and the owner's own ruling confirms it: `#31` (class `OFF`,
channel `I` only) was ruled KEEP on nothing else.

**What does not count:** `✓ venue`, `✓ market`, `risk`, `analytics`, `scanner push-to-sync`,
`reconciliation monitor` — a context or a role with no named object behind it.

| # | fact | producer · pkg | the NAMED handler | notify-only? |
|:--|---|---|---|:--:|
| 1 | `#9 PaymentCaptured` | `venue.finalize_primary_order` · `085` | `purchase_confirmed` MANDATORY | notify-only |
| 2 | `#10 TicketIssued` | `kernel.issue_ticket_atoms` · `083` | `ticket_ready` MANDATORY | notify-only |
| 3 | `#17 OwnershipTransferred` | `kernel.transfer_ticket_ownership` · `088` | **`wallet-pass-push`** → `supersede_wallet_passes_for_atom`, *always, unconditionally*; + `ownership_changed` MANDATORY | **independent** |
| 4 | `#22 ScanAdmitted` | `venue.record_scan` · `086` | **`wallet-pass-push`** — atom → `scanned` | **independent** |
| 5 | `#25 PayoutReleased` | `kernel.release_payout` · `085` | `payout_released` MANDATORY | notify-only |
| 6 | `#26 PayoutFailed` | `kernel.mark_payout_transfer_state` · `085` | **two** MANDATORY types: `payout_failed` + `staff_payout_failed` | notify-only |
| 7 | `#27 RefundIssued` | `kernel.refund_primary_order` · `085` | `refund_completed` MANDATORY | notify-only |
| 8 | `#28 TicketVoided` | `kernel.void_ticket_atom` · `085` | **`wallet-pass-push`** — bump on the void arm, *always* | **independent** |
| 9 | `#31 AttributionRecorded` | `venue.resolve_order_attribution` · `085`→`090` | **`OR-3` KEEP**; `promoter_attribution_recorded` (`OFF`) | notify-only |
| 10 | `#32 PromoterCommissionAccrued` | `kernel.pay_promoter_commission` · `090` | **`OR-3` KEEP**; `promoter_commission_accrued` (`ON`) | notify-only |
| 11 | `#40 DoorManifestDrained` | `market.on_door_freeze_engaged` · `086`→`088` | **`wallet-pass-push`**, best-effort *(see §7 conflict)* | **independent** |
| 12 | `#44 DoorManifestInvalidated` | force-close · `cancel_event` · **`revoke_signing_key`** · `086` | **clause 2** — EDGE is normative: `revoke_signing_key` **MUST** emit it, and the `DL-4` grant rests on it | **independent** |
| 13 | **U1** event cancellation *(unnumbered)* | `catalog.cancel_event` · `088` | `wallet-pass-push` **always** + `event_cancelled` MANDATORY | **independent** |
| 14 | **U2** session time/venue/status change *(unnumbered)* | `catalog.update_event_session` · **`079`** | `wallet-pass-push` **always** + **three** MANDATORY types | **independent** |
| 15 | **U3** pass-type cert rotation *(unnumbered)* | `kernel.rotate_pass_type_cert` · `083` | `wallet-pass-push`, batch | **independent** |

**Sub-tallies, each with its enumeration.** notify-only **7** (`#9 #10 #25 #26 #27 #31 #32`) ·
notify-independent **8** (`#17 #22 #28 #40 #44 U1 U2 U3`). **7 + 8 = 15** ✔
Of the twelve numbered: **seven are `Sync`-classified and still need a post-commit row**
(`#9 #10 #17 #22 #27 #28 #31`) · two are door events (`#40 #44`) · three are `C11`-sense outbox
events (`#25 #26 #32`).

## 2. Excluded under the strict test — and why

`#3 VenueApproved` and `#4 EventPublished` offer only `✓ venue` / `✓ market` context ticks. **No
document anywhere names what `venue` DOES when a venue is approved**; no notification type exists
for either. A producer is not a consumer. These are the exact shape the test names inadmissible —
the same evidence used to REMOVE `#2` and `#5`.

`#37 · #38 · #39 · #41 · #42 · #43` — the six door events whose consumer cells name `risk`
(no table in any package), `analytics` (deferred by `C11`), `notify` (**no such type exists** — the
nearest, `event_door_open`, is fired by a *scheduler*), `scanner push-to-sync` (**names no handler
anywhere** — the only scanner mechanism in any package is a device-initiated **poll**), or
`reconciliation monitor` (**exists nowhere in the corpus** — the string occurs twice, both times in
this event's own cell and its restatement).

`#43` additionally: **the ratified requirement is already satisfied without the envelope.** `C113`
makes the `revoke`/`add` delta row mandatory and in-transaction; the envelope is only *"so online
devices re-sync promptly"*, and the door spec states outright that a device that has never synced
deltas *"is exactly as safe as it was before this section existed."* **Promptness is not a
post-commit effect a contract requires.**

`#21 CredentialInvalidated` — its consumer is bound **in-transaction**, not post-commit.

> **THE STRONGEST COUNTER-ARGUMENT, STATED RATHER THAN BURIED.** The door spec's step 11 writes the
> `#37`/`#39` envelopes inside a transaction whose steps *"either all commit or none do."* **That
> text requires the envelope WRITE; the strict test asks for a post-commit EFFECT.** No consumer
> exists for either envelope, so under the test as ruled they fail. **If the owner reads clause 2 as
> covering a contract-mandated write with no consumer, `#37` and `#39` return and the count is 17**
> — and `#38`, `#41`, `#42`, `#43` still do not. That is the one place this enumeration is
> sensitive to a reading, and it is shown rather than resolved.

## 3. The Gate-L floor: **8**

`#17 · #22 · #28 · #40 · #44 · U1 · U2 · U3`. **Seven of the eight are one handler** —
`wallet-pass-push` (`084`) is the entire non-notify Gate-P consumer surface; `#44` is the only
non-Wallet member and its consumer is a device, not a server object.

Even had `ODR-3` gone the other way, **8 of 15 facts still require the carrier**, because *"Wallet
can never block or roll back a transfer"* is a preserved invariant and the outbox is what preserves
it. `OR-5 = [C]` keeps all 15 live.

## 4. Package placement — there is no three-way contradiction

Two documents speak to the drainer's package and **agree verbatim**; the registry never assigns the
drainer a package at all. **The defect is latent, not actual — and it is the more dangerous kind**,
because the registry is the canonical numbering authority and its item label (`"event outbox +
drainer"`) with a single scalar `package_if_ratified` gives a machine reading `conditionals[0]`
**one number for two objects**.

| object | package | why |
|---|:--:|---|
| the outbox **table** (`notify.outbox`, since `OR-5` puts `notify` at Gate P) | **`076`** | zero FK dependencies — polymorphic aggregate keys — so **no producer package gains a dependency edge** |
| the **drainer** (`notify.drain_outbox`) | **`092`** | `SEAM-1` `max()` over what the body reaches, including `venue.promoter_link` (`090`); `091` is a droppable writer-less stub |

> **THE STRUCTURAL CONSEQUENCE.** `092` makes the band **`076`–`092`, 17 packages**, falsifying
> registry §2's *"16 packages … no gaps, no duplicates"*. The corpus itself calls this *"a structural
> change requiring re-ratification"*. **This directly falsifies the `ODR-1` signature** — a bare
> "ratify the current registry" is now the wrong signature, and `ODR-1` must be re-put with the
> 17-package band.

**One placement the corpus does not settle:** under `OR-5`'s **reduced** scope, whether the drainer
still reads `venue.promoter_link` depends on whether `#31`'s notification path is built. If not, the
floor drops and `092` may not be forced. See `ODR3_GATE_P_REDUCED_SCOPE.md` §5, which resolves it
the other way — the floor holds at `090` because `#32`'s notice is IN.

## 5. Documents needing a prose change — 32 sites

Mapped, not edited. The largest groups: six sites assert *"no implementation spec schedules one"* —
**all six now false**. `COND-A` and `COND-B` move out of "Conditionals — NOT counted in the 16" into
the counted set. `CONFLICT-1`, `CONFLICT-2`, `MD-10`, `MD-11`, `O-N1`, `O-N2`, `G-1`, `G-2`, `G-19`
and hard gate `HG-2` all close. `C51`/`O7` and `C52`/`O8` go from `OPEN-GATED` to CLOSED. The schema
spec's *"schema home depends on the notify ruling"* resolves to **`notify.outbox`**. The registry's
§2 count assertion requires re-ratification rather than an edit.

## 6. The `#31`/`#32` prose defect — the exact false lines

**Four sites, quoted, with the correction:**

| # | site | today | verdict |
|:--|---|---|---|
| 1 | registry §7 | *"**Unaffected:** CRM export …, demographics, **promoter codes**, and money authority"* | **FALSE** — strike `promoter codes` |
| 2 | registry JSON | `"unaffected": [… "promoter_codes" …]` | **FALSE** — remove the element |
| 3 | schema spec §13.3 | *"**promoter codes (no async at all)**"* | **FALSE** — the sharpest error in the corpus on this point: **two** promoter events are carrier-relevant |
| 4 | scope amendment row 7 | *"`AttributionRecorded` … Named in `REGISTRY` §7 as **unaffected**"* | **FALSE** — `#31` is ruled KEEP |

**The self-contradiction, located exactly.** Registry §7 line `:761` states that *"DA §6.1 classifies
every notification, rollup, **commission accrual** and transfer-expiry as Async/outbox."* Line
`:777`, **sixteen lines below**, states that promoter codes are **`Unaffected`** by that very ruling.
Commission accrual **is** promoter work. **§7 asserts and denies the same fact within one section.**
`:761`'s half survives; `:777`'s half dies.

**What must NOT be over-corrected.** `#31`'s **money** path stays same-transaction — ratified `D7`
pins the attribution row in the transaction that marks the order paid, and the commission line is
written inside `close_settlement` via a SEAM-2 hook. **`OR-3` changes the carrier status of the
notice, not the transactionality of the money.** Any correction that moves promoter money onto the
outbox contradicts `D7`.

## 7. The producer side is unspecified — verified two ways

**The string `outbox` occurs exactly 8 times in the 638 KB RPC contracts document, and not one is a
producer's write clause.** The string `Emits` occurs exactly once, and it says *"Emits
**notifications**"*, not an envelope. **`notify.emit_event(...)` is fully contracted and has NO
caller anywhere in the corpus.** Every one of the fifteen facts is produced by a function whose
contract does not know the outbox exists.

**Nineteen call sites across six packages (`079`, `083`, `085`, `086`, `088`, `090`) and two live
edge functions** must gain an emit clause. **Five are `G-7`-uncontracted today** —
`kernel.admin_refund`, `kernel.pay_promoter_commission`, and the
`provision`/`rotate`/`revoke_signing_key` + `pass_type_cert` families. **`G-7` was an `S1` before
`OR-4`; it is now a build blocker**, because an uncontracted producer cannot be given an emit clause
it has no contract to hold.

**Placement is free:** the table's zero FK dependencies mean no producer package gains an edge, the
45-edge DAG is untouched, and the lock order is already settled — the outbox row is written **last
within its transaction**, so *"no new lock and no new deadlock class."*

**Two further gaps this enumeration exposes.** (a) **Three of the fifteen facts have no `event_key`.**
`notify.outbox` enforces `UNIQUE (event_type, event_key)` where `event_key` is *"the §6.1 idempotency
key of the business event"* — and `U1`, `U2`, `U3` are not in §6.1. **`076` cannot be authored until
DA §6.1 numbers and keys them.** (b) Which of three objects emits `#32` is unstated, and getting it
wrong puts the envelope in a package that cannot see `venue.promoter_link`.

## 8. The emit-semantics contradiction — and it is wider than the door

**Side A:** `notify.emit_event` is contracted **non-raising** — *"a producer that cannot emit its
envelope logs a warning and commits its money/custody work regardless"* — asserted by `N-A29` and
`T-RPC-NOTIFY-04`, deriving from `NOTIF §0.3` rule 1: *"a notification may never abort the
transaction that caused it."*
**Side B:** the door spec requires its envelopes inside a transaction whose *"steps 5–11 either all
commit or none do."*

**They are incompatible: `emit_event` swallows exactly the failure the door says must roll back.**

> **THE PART NO PRIOR PASS STATED. Non-raising emit silently breaks the Wallet invariant.** `#17` and
> `#28` are the `credential_version`-bump triggers, whose consumer runs *outside* the custody
> transaction precisely so Wallet can never block a transfer. **If the emit is swallowed, the
> transfer commits, no envelope exists, no consumer ever runs, and the previous owner's pass stays
> `issued`** — the exact non-negotiable the partial unique index exists to prevent. **A non-raising
> emit reproduces, silently and at runtime, the failure the corpus prohibits as a design choice.** It
> converts a prohibited design into an intermittent bug, which is strictly worse, because the design
> was at least visible.
>
> **The asymmetry that produced the defect:** `§0.3` rule 1 is a rule about **notifications**, where
> it is correct. It was extended to `emit_event`, which writes an **envelope** — a carrier for
> effects that are not cosmetic. **The rule was generalised past its justification.**

**Five resolution options, stated and NOT chosen:** R1 emit raises universally (one change; retires
two assertions) · R2 two functions, raising and non-raising (the only option that lets `#40`
best-effort and `#17` *always* differ correctly; costs a new classification obligation per fact) ·
R3 raise iff `mandatory`, registry-driven (uses machinery that already exists, but `#17`/`#22`/`#28`/
`#40`/`U3` have **Wallet** consumers with no notification class, so a third value must be invented) ·
R4 keep non-raising + a detective assertion (**rejected on the corpus's own precedent** — this repo
has twice shipped *"a correct thing that nothing called"*, and a detective control on a **fail-open**
path is the shape the door spec explicitly refuses) · R5 amend the door's all-or-nothing clause
(legitimate only because `#37`/`#39` have no admitted consumer — **but it does not touch Wallet**, so
it resolves nothing alone).

## 9. What the corpus still cannot settle

1. **`ODR-3 = [C]`'s scope** determines whether all seven notify-only facts survive. Six map cleanly
   onto `OR-5`'s inclusion list; **`#31` does not** — its only consumer is `OFF`, in-app-only, and
   `OR-5` names `#32`'s notice explicitly while not naming `#31`'s. **If the reduction drops it,
   `#31` becomes a carrier row with no consumer and the count is 14.** `OR-3`'s own reasoning ties
   `#31` and `#32` together, so dropping it would need to be a deliberate act, not a scoping
   side-effect.
2. **`WALLET §6.3` contradicts `WALLET §7.1` on `#40`** — §6.3 lists it as a push trigger; §7.1 says
   the drain *"requires no special handling — recorded so an implementer does not 'helpfully'
   supersede a pass on a drain."* Both in the same document, neither marked superseded. **If §7.1 is
   the surviving text, `#40` leaves and the count is 14.**
3. **`WALLET`'s *"status change"* is ambiguous and it is the hinge for `#4`.** Read as
   `event_session` status, `#4` is out. Read as any catalog status change, `#4` is in and the count
   is 16. No document disambiguates it.
4. **`OR-3` calls `#4` "retained" and that must not be misread as a carrier ruling.** An event can be
   retained in the catalog and require no carrier — that is exactly the distinction `OR-4` draws. If
   the owner intended `#4` to carry, that is a sixth ruling and it has not been made.
5. The extended-scope figure, **recorded not adopted**: applying the same test to the sixteen
   unnumbered notification types yields **26**. **The cost is identical either way** — one table, one
   unique, one drainer, one advisory lock; nothing in that construction scales with the number of
   `event_type` values.
6. `G-20`'s two-names-per-function divergence still blocks two producers, though it no longer blocks
   the carrier.
7. An unfiled `EDGE ↔ SCHEMA` divergence surfaced by `OR-3` (the Connect capability columns that do
   not exist) has **no defect id yet**.
