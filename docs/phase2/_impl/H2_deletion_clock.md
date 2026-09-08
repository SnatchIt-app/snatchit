# H2 — The deletion clock

**Status:** implemented in `docs/phase2/_impl/093_parts/10_money_settlement.sql` (section **10j**) and
`docs/phase2/_impl/093_parts/40_config_privacy_freeze.sql` (the config row, TWO dual-control prefixes —
`deletion.%` and `ticket.%` — the polarity, and the hours-typed guard). 093 re-assembled
(`scripts/assemble_093.sh`); G-4 integrity gate PASS. pgTAP updated in `149`, `142`, `156`, `157`.
**Nothing was deployed. No production mutation. No commit. Migrations 000-092 untouched.**
**Method:** static reading of `076..093` plus execution against `snatchit_rehears_del`
(`scripts/rehearsal_reset.sh`, full 108-migration replay). Every claim marked **[V]** was executed.

---

## 0. THE EXACT CURRENT PREDICATE — verified, not taken on description

`kernel.deletion_blockers_money`, `085:262-284`, verbatim:

```sql
  -- BP-12 arm 2 (PFA-22): the refund-possible window over candidate orders.
  -- ... (measured from created_at — the only stable timestamp on the immutable 082
  -- table; the in-flight arm above covers active requests independently).
  if exists (select 1 from venue."order" o
              where o.buyer_id = p_identity
                and o.status in ('paid','partially_refunded')) then
    select (c.value #>> '{}')::numeric into v_window
      from catalog.platform_config c
     where c.key = 'deletion.refund_possible_window_hours'
     order by c.version desc limit 1;
    if v_window is null then
      return 'BP-12: refund-possible window unset (deletion.refund_possible_window_hours) with candidate orders present';
    end if;
    if exists (select 1 from venue."order" o
                where o.buyer_id = p_identity
                  and o.status in ('paid','partially_refunded')
                  and o.created_at > now() - make_interval(hours => v_window::int)) then
      return 'BP-12: order inside the refund-possible window';
    end if;
  end if;
```

**Engaging with the stated reasoning.** The comment's defence — *"the only stable timestamp on the
immutable 082 table"* — and PFA-22's — *"it expires no later than a paid-time window would"* — are both
**true and both irrelevant**. They compare two *payment-clock* instants to each other; neither considers
the event clock. The anchor does not have to live on 082. `venue."order".event_session_id` is
`uuid not null references catalog.event_session(session_id) on delete restrict` (**082:77**), so the
join is **total** (every order resolves to exactly one session) and **stable** (the referent cannot be
deleted). Same join G2 used. Available and confirmed.

---

## 1. THE FULL DELETION MACHINERY

Driver: `kernel.sweep_deletion_pending` (`077:1865-2050`), cron `*/2`, `coalesce` in order; the first
non-null reason is written to `identity_ext.deletion_block_reason` and the pass moves on. Terminal entry
re-verifies BP-11 under org locks (`077:1963-1981`).

| BP | Blocks on | Body / site | Clock |
|---|---|---|---|
| BP-1 | own atom `state in ('issued','active')` | `079:706-717` | **event** — drains at `ends_at + ticket.expiry_grace` via `079:456` sweep; also scan/void/transfer-out |
| BP-2 | `wallet_pass.status='issued'` | `083:351-359` | follows the atom |
| BP-3 | unsettled native sale (buyer or seller) | `088:473-476` | state |
| BP-4 | open native p2p transfer | `088:478-481` | state |
| BP-5 | identity payout `pending`/`submitted` | `085:237-240` | state |
| BP-6 | identity payout `hold_state<>'none'` | `085:242-245` | state |
| BP-6 live | live-rail `transfers` hold/probation | `077:1900-1905` | state |
| BP-7 | open/disputed live transfer | `077:1906-1914` | state |
| BP-7 native | open `kernel.dispute_native` on a payment bought/sold | `088:483-490` | state |
| BP-8 | live buy-now reservation | `077:1915-1918` | state |
| BP-8 native | in-flight `market_sale` as buyer | `088:492-495` | state |
| BP-9 | won-unsettled auction / live high bidder | `077:1919-1928` | state |
| BP-10 | `identity_obligation.status='outstanding'` (**chargebacks land here**) | `085:289-297`, sweep `077:1929-1931` | state |
| BP-11 | sole `org_owner` | `077:1932-1940` + `077:1963-1981` | state |
| BP-12 arm A | `venue."order".status='pending'` | `082:656-665` | state |
| BP-12 arm 1 | non-terminal `kernel.refund`, or pending `refund.issue` approval | `085:246-261` | state |
| **BP-12 arm 2** | **paid/partially_refunded orders inside a window** | **`085:262-284`** | **PAYMENT — the defect** |

**Nothing else in the machine is a clock.** Every other arm is a *state* predicate that drains when a
real object reaches a terminal state. Arm 2 was the only arm that used elapsed time as a proxy for
"the obligation is over", and it measured that time from the wrong event.

Settlement, transfers, resale and ticket expiry are **not** deletion blockers in their own right — they
reach deletion only through the arms above (a settlement payout via BP-5/BP-6, a resold or transferred
atom by *ceasing* to hold BP-1). That asymmetry is what makes arm 2 load-bearing: after custody leaves,
the **order** — and its refund and chargeback liability — stays with the original buyer, and arm 2 is
the only thing that knows it.

---

## 2. THE DEFECT, EXECUTED

`snatchit_rehears_del`, 22 identities, `deletion.refund_possible_window_hours = 720` (30 days). **[V]**

| Scenario | Old (payment clock) | New (event clock) |
|---|---|---|
| bought 90d out, event **in 10 days** | **ERASABLE** | BLOCKED |
| bought 90d out, **already partially refunded**, event in 10 days | **ERASABLE** | BLOCKED |
| bought 90d out, session **CANCELLED**, event in 10 days | **ERASABLE** | BLOCKED |
| bought 90d out, **multi-session** (days 10 & 11) | **ERASABLE** | BLOCKED @ day 11 |
| bought 90d out, **multi-day** session (days 10-13) | **ERASABLE** | BLOCKED @ day 13 |
| bought 90d out, **postponed** further out | **ERASABLE** | BLOCKED, anchor moved |
| bought 90d out, ticket **transferred out** / **resold**, event in 10 days | **ERASABLE** | BLOCKED |
| bought 90d out, session has **no `ends_at`** | **ERASABLE** | BLOCKED @ `starts_at`+hold |
| bought **today**, event in 10 days | BLOCKED | BLOCKED |

End-to-end, the G7 P0-3 attack: **[V]**

```
old:  request_account_deletion → sweep_deletion_pending(50) → {"swept":2,"blocked":1,"tombstoned":1}
      m1_early → ERASED, 10 days before their event
new:  m1_early → DELETION_PENDING,
      reason "BP-12: inside the post-event deletion hold — erasable after 2026-10-13T06:45:06Z"
      m3_postevent (event 39d ago, 30d hold elapsed) → ERASED   ← the bound still works
```

The only buyer the old clock protected was the one who had bought **recently** — and it protected them
for the wrong reason. Meanwhile `kernel.close_settlement`'s G2 gate was holding the **venue's** money on
`refund_in_flight`/`dispute_open` predicates that, after the tombstone, can no longer identify the
counterparty. The two halves of the train contradicted each other on the same question.

### 2b. A SECOND DEFECT, found by execution — and it is worse

`085:273-276` casts the config value inside an **ordered target list**. Postgres may evaluate the
projection *before* the `LIMIT`, so the `::numeric` cast is applied to **every historical version** of
the key. `catalog.platform_config` is append-only (`tg_platform_config_append_only`), so one bad version
is **permanent**. Executed with versions `[null, 720, "720 hours", 720]`: **[V]**

```
ERROR:  invalid input syntax for type numeric: "720 hours"
```

— raised for **every identity**, not only the one who typed it, and even after a *correct* version 4 was
appended. `sweep_deletion_pending`'s per-identity `exception when others` (`077:2038-2041`) swallows it,
so **the deletion machine silently stops tombstoning anyone, forever**, leaving one `raise warning`.
`"720 hours"` is the single most likely typo, because the sibling key `ticket.expiry_grace` *requires*
exactly that string form — and `deletion.%` had no dual control (G7 P1-4). One admin, one plausible
statement, unrecoverable without a migration.

---

## 3. THE NEW ANCHOR, DERIVED

Candidates evaluated against the schema:

| Candidate | Expressible? | Verdict |
|---|---|---|
| (a) `order.created_at` (payment) | yes | **Rejected** — §2 |
| (b) event end | **no** — `catalog.event` (078:134-154) carries no instant | not expressible; must reduce to sessions |
| (c) **max applicable session end** | yes — `event_session_id` NOT NULL, restrict FK | **CHOSEN** |
| (d) ticket expiry (`ends_at + ticket.expiry_grace`) | yes in principle | **Rejected** — it is (c) plus an unset owner key plus a cron sweep, and it couples erasure to an admissibility label. Also drains on *scan*, which happens mid-event |
| (e) refund eligibility end (`refund.%`) | yes | **Rejected** — different subject (the buyer's *rights*), and overloading it is the collapse this exercise exists to undo |
| (f) settlement maturity | yes | **Rejected** — different subject (the *venue's* money) and a settlement may never close, which would be unbounded |

```
anchor(identity) = max( coalesce(session.ends_at, session.starts_at) )
                   over the sessions of the identity's paid/partially_refunded orders
blocked          ⇔ now() < anchor + deletion.post_event_hold_hours
```

* **`max`** because erasure is per-**identity**: one unmatured order must hold the whole account.
  Multi-session and multi-day fall out for free. **[V]**
* **`coalesce(ends_at, starts_at)`** — see the boxed note below. **[V]**
* **the order's own session**, not every session of its event: a day-1 buyer's obligation is day 1. An
  event-grain cancellation that reaches them opens a `kernel.refund` row, which **arm 1** blocks on.
* **candidate set unchanged**, verbatim from PFA-22.


> ### ⚠ DO NOT "FIX" THIS INTO CONSISTENCY WITH G2
>
> **G2 fails CLOSED on a null `ends_at`. H2 deliberately does NOT. The inconsistency is the point.**
>
> `ends_at` is nullable (`078:170`) and `catalog.create_event_session` requires only `starts_at`
> (`078:805-807`), so an unknown end is reachable in production. G2's payout gate can hold that money
> forever because **`kernel.release_payout` is a human exit** — a person can look at a held payout and
> release it.
>
> **This gate has no exit.** Nothing in the corpus can force-tombstone an identity: `DELETION_PENDING`
> leaves only by the sweep finding every blocker false, and there is no override verb. So "fail closed on
> an unknown end" here does not mean *safe*, it means **an erasure request that can never complete** —
> an erasure-law failure, which is a worse outcome than the one it would be protecting against.
>
> The fallback is therefore `starts_at`: NOT NULL, still event-anchored, and at most **one session
> duration** early — hours, against a hold measured in weeks, so the hold swamps the gap.
>
> A later reader who notices the two gates disagree and "harmonises" them will convert a bounded hold
> into a permanent one. The correct harmonisation, if one is ever wanted, is to give **this** gate an
> exit — not to take G2's failure mode.

### The trade, stated

Both failure directions are real. Early tombstone destroys a live counterparty **irreversibly** (DSM has
no exit from ERASED). An indefinite hold is an erasure-law failure. H2 takes the bounded side of both:
every block resolves at a **named instant carried in the reason string**, and the longest possible block
is `session start/end + the owner's hold`. No arm can block forever.

### Four clocks, four keys, kept apart

| Concept | Question | Key | Anchor |
|---|---|---|---|
| Ticket expiry | admissible at a door? | `ticket.expiry_grace` | `ends_at` |
| Refund eligibility | may the buyer still ask? | `refund.*` (078:1544-1551) | request path |
| **Deletion safety** | may this identity be irreversibly tombstoned? | **`deletion.post_event_hold_hours`** | **max session end over their orders** |
| Payout maturity | may the venue's money leave? | `payout.settlement_maturity_interval` | max session end over the settlement's lines |

---

## 4. WHAT CHANGED

**`093_parts/10_money_settlement.sql` — new section 10j.** Body-only `CREATE OR REPLACE` of
`kernel.deletion_blockers_money`. BP-5, BP-6 and BP-12 arm 1 transcribed byte-for-byte from
`085:235-261`. Signature/return/volatility/security/`search_path` unchanged (SEAM-2a); ACLs preserved —
verified `service_role=X` only, no client grant. **[V]** Arm 2 re-anchored; the config read moved into a
subquery so no cast touches a discarded row; every failure arm returns a named block.

**`093_parts/40_config_privacy_freeze.sql`:**
1. seeds `deletion.post_event_hold_hours` v1 `'null'::jsonb` `restricted` (PFA-9 shape);
2. adds `deletion.%` to `set_platform_config`'s dual-control prefix list;
3. adds `deletion.post_event_hold_hours` to `higher_is_restrictive` — **lengthening executes, shortening
   parks** (short is the irreversible direction; long costs only recoverable latency). **[V]**
   `720 → 24` ⇒ `"parked"`; `720 → 2160` ⇒ `"ok"`. Under the old key, G7 P1-4 got `"ok"` for anything.
4. adds an hours-typed guard, the mirror of the interval guard: **[V]**
   `set_platform_config('deletion.post_event_hold_hours','"720 hours"')` ⇒ `precondition_failed: bad_value`.
5. **adds `ticket.%` to the dual-control prefix list — the last destructive key family outside it.**

### 4a. `ticket.%` joins dual control

The argument is H2's own evidence about what that key does. Setting `ticket.expiry_grace` wrongly does
not *degrade*: it writes the **terminal** label `expired` across every atom on every ended session within
one cron tick (`079:456`, cron `*/2` at `079:799-803`), and `088:1682/1735/1783` then **exclude** expired
atoms from `catalog.cancel_event`'s refund cascade — the holder loses **ticket and money**. No shipped
function writes `kernel.tickets.state` back out of `expired`. That is a more destructive single write
than several families already on the list, and it is the same reasoning that added `fee.%` (ruling A5)
and `deletion.%` (H2 above): one administrator must not cross an irreversible money or identity boundary
alone. The list is now `refund.` `payout.` `authn.` `comp.` `wallet.` `credential.` `door.session_`
`fee.` `deletion.` `ticket.`

**Confirmed by execution, not assumed** — the four checks the coordinator asked for:

| Check | Result **[V]** |
|---|---|
| `ticket.%` has a declared polarity entry? | **No entry** — grepped the whole map. It therefore takes §20.2.1's third arm (*not comparable ⇒ park*) |
| …so it parks in **both** directions | `72h → 96h` ⇒ `parked`; `72h → 24h` ⇒ `parked`; `max(version)` unchanged. **Intended**: the corpus declares no restrictive direction for a grace that is destructive when short and merely slow when long, so failing toward the approver is the honest reading |
| the two guards **compose**, neither shadows the other | a bare number is refused **outright** at the type guard and never reaches the dual-control branch — so a second admin can never be asked to rubber-stamp `'24'` ⇒ *twenty-four seconds*. Dual control governs only a **well-typed** wrong value |
| **not over-widened** | `inventory.per_user_active_hold_max` ⇒ `ok`, `inventory.hold_ttl_interval` ⇒ `ok` (single admin). Neither is destructive and both fail closed while unset (`081:615-626` collapses the cap to zero; `081:638` raises `hold_ttl_unset`). Control: `notify.announcement_hold_seconds` ⇒ `ok` |

**The old key.** `085` is immutable and `platform_config` is append-only, so
`deletion.refund_possible_window_hours` cannot be withdrawn. It survives as an **unread orphan** — the
same residue G2's rename left — and is recorded, not hidden. Nothing reads it after 093, which also
retires its poisonable read. This is why the config census moves **48 → 49** rather than staying flat.

**Rename justified, against an owner-signed ruling.** PFA-22 names the old spelling verbatim. Its
*semantics* are preserved exactly (dedicated operand; candidate-scoped NULL fail-closed; deletion safety
only). Only the spelling and the anchor change — and the anchor change is what makes the ruling's own
stated intent true. **Flagged as an owner item, not absorbed silently.**

---

## 5. TEST MATRIX — all executed **[V]**

Hold = 720h (30 days) unless noted. "→" = first blocker; `<clear>` = erasable.

| # | Scenario | Result |
|---|---|---|
| 1 | purchased 90 days before event (event in 10d) | → BP-12 post-event hold, matures `event_end+30d` |
| 2 | purchased day of event | → BP-12 post-event hold, **same instant as #1** — purchase timing is irrelevant |
| 3 | deletion requested **before** event | DELETION_PENDING, reason carries the instant; sweep does not tombstone |
| 4 | deletion requested **after** event (39d ago, 30d hold) | `<clear>` → **ERASED** — bounded |
| 5 | event **postponed** before deletion | anchor +30d, hold extends |
| 6 | postponed **after** the original date passed | anchor moved Oct 1 → Nov 15; buyer correctly re-blocked |
| 7 | event **cancelled** (session `status='cancelled'`) | → BP-12 post-event hold (and BP-12 arm 1 once `cancel_event` writes refunds) |
| 8 | **multi-session** (2 orders, days 10 & 11) | anchor = **day 11** (max), not day 10 |
| 9 | **multi-day** single session (days 10-13) | anchor = **`ends_at`** (day 13), not `starts_at` |
| 10 | open refund | → **BP-12 refund in flight** (arm 1, unchanged) |
| 11 | completed refund, order `refunded` | `<clear>` — not a candidate |
| 12 | partially refunded, event ahead | → BP-12 post-event hold — **was erasable under the old clock** |
| 13 | open dispute | → **BP-7 open native dispute** (088:483-490) |
| 14 | post-event chargeback (`identity_obligation` outstanding) | → **BP-10** |
| 15 | ticket **transferred out**, event ahead | → BP-12 post-event hold — custody left, the **order** did not |
| 16 | ticket **resold**, event ahead | → BP-12 post-event hold — same |
| 17 | **expired** ticket, past event, hold elapsed | `<clear>` |
| 18 | venue payout **pending** (identity payout in flight) | → **BP-5** |
| 19 | venue payout **completed** (`paid`) | `<clear>` — R1 P3 preserved |
| 20 | session with **no `ends_at`** | → BP-12, matures `starts_at + hold` — bounded, never indefinite |
| 21 | pending (unpaid) order | → **BP-12 pending arm** (082:656) |
| 22 | cancelled order only / no orders | `<clear>` — PFA-22 scoping intact |
| 23 | hold **unset** + candidate present | → BP-12 hold unset (**fail-closed, PFA-22 verbatim**) |
| 24 | hold unset + **no** candidate | `<clear>` — the owner's scoping ruling |
| 25 | hold `< 0` or `> 87600` | → policy invalid (range) |
| 26 | hold a **string** / boolean | → policy invalid (type) — **no raise** |
| 27 | poisoned version then a good one | good version **supersedes**; bad row survivable, not terminal |
| 28 | hold exactly elapsed to the second | `<clear>` — `now() < matures_at` is strict |

### pgTAP

`149` **132 → 141**, all pass. **[V]**
* **`I4` rewritten** — it read *"window 0h ⇒ the candidate falls outside it — unblocked"*, which was only
  true because the clock was `created_at` and the fixture order was seconds old. **That assertion encoded
  the payment-clock contract**, on a fixture whose session ends `now() + 15 days`. It now asserts the
  inverse and is **strictly stronger**: even a **zero** hold blocks while the event is ahead.
* `A16` **kept unchanged and still true** (085 still seeds the old row); `A16b` added for the new key.
* New: `I4b` bounded release · `I4c` maturity instant is exactly `ends_at + hold` · `I4d`/`I4e`
  poisoned-version immunity and recovery · `I6`-`I9` the anchor (max-over-orders, multi-day, null
  `ends_at` → `starts_at`, postponement).

`142` **253 → 261**: `H18m/n/o` dual control on the deletion clock (parked / no version / value still
null), `H18p` its hours-typed guard, `H18q/r` `ticket.expiry_grace` parks and lands no version, `H18s`
the bare number is still refused outright (the guards compose), `H18t` the widening is scoped —
`inventory.per_user_active_hold_max` still executes for one admin. Census `D1` 48→49, `D4` 40→41. `156` `A23` 48→49. `157` `A20` 48→49. All census **extensions**
with cited reasons; **nothing relaxed to a name filter, no assertion weakened**.

Full suite after the change: `TOTAL plan=3033 ok=3026 not_ok=7`. The 4 expected local-only deltas
(`060`, `132`) plus **3 failures that are not H2's**: `142 K3`, `143 A32`, `144 A14` all assert
*"kernel holds exactly 117 functions"* and now see **119** — from a concurrent agent's slice-30 additions
(`kernel.authorize_org_payout_dashboard`, `kernel.guard_connect_id_not_org_bound`), which `141 A14/A14a`
already tracks at 119. **H2 adds zero functions**: section 10j contains exactly one statement, a
`CREATE OR REPLACE` of a function both `077:1720` and `085:229` already create; the slice-40 diff creates
no object at all. **[V]** Those three censuses belong to that agent's delta.

---

## 6. DOES `ticket.expiry_grace` STILL CARRY DELETION SEMANTICS? — G1's 72 hours

**Verdict: G1's 72 hours STANDS, and H2 is what makes its reasoning valid.**

G1 claims 2-3 rested on *"BP-12 arm 2 independently blocks every buyer with a paid order"*, so
`ticket.expiry_grace` need not be the money clock and should be chosen on admissibility grounds alone.
G7 **P0-3 overturned that** — correctly — because it was true only while the key was *unset*; the moment
an owner set it, the payment clock let paid buyers through and `expiry_grace` was left carrying weight it
was never designed for.

After H2 the premise is restored, and **structurally rather than accidentally**:

* BP-1 drains at `ends_at + ticket.expiry_grace` (72h). BP-12 arm 2 drains at `anchor + hold`. For any
  hold ≥ the grace, **BP-12 strictly dominates BP-1 for every paid buyer** — and it dominates whatever
  the grace is set to, including a mistaken one.
* Executed: a paid buyer 100 hours after their session ended, `ticket.expiry_grace = "72 hours"` —
  `sweep_expired_ticket_atoms` expired the atom and **BP-1 cleared**, while BP-12's hold still blocked.
  **[V]** `expiry_grace` decided nothing about that identity's erasure.
* Executed: a **comp/import** holder — an active atom and **no `venue."order"` row at all** — is blocked
  by **BP-1 only**; arm 2 never engages, because it has no candidate order. **[V]**

So `ticket.expiry_grace` carries deletion semantics for **exactly one population**: holders of
comp/guest/imported atoms, who have no order. That is precisely the population G1 §7.2 identified
(*"the harmed population is small and specific… everyone with a paid order is gated by BP-12 anyway"*) —
a sentence that was aspirational when written and is now **true**. Its cost is erasure *latency* for that
small group, bounded at 72h; its floor (`door.session_absolute_max_interval = "24 hours"`, 078:1540) and
its 72 (`authn.money_role_maturity_hours`, 078:1560) are unaffected by anything here.

**Recommendation unchanged: `ticket.expiry_grace = '"72 hours"'::jsonb`, a jsonb STRING, chosen purely on
admissibility grounds.** Three H2 amendments to G1's operational text:

1. G1 §7.2's "TOO LONG" analysis is now correct as written rather than by accident — cite H2, not the
   unset state of a key, as the reason BP-12 covers paid buyers.
2. **G1 §7.3's 24-seconds cast trap is CLOSED, and this document said otherwise in an earlier draft.**
   Correcting it explicitly, because a stale "live trap" claim in the document the owner reads to decide
   G1 is worse than no claim at all: `'ticket.expiry_grace'` is **already first in the interval-typed key
   guard** at `40_config_privacy_freeze.sql:1248`, which landed in the previous train. A bare JSON number
   is refused with *"needs a JSON STRING such as "24 hours"; a bare number is read as SECONDS"*.
   **[V]** `set_platform_config('ticket.expiry_grace','24')` ⇒ `precondition_failed: bad_value`.
   G1 §7.3's manual pre-set verification is still **good practice** — it proves what the sweep *would*
   do before arming it — but it is no longer the only thing standing between a typo and every atom on
   every ended session going terminal.
3. **The dual-control half WAS still open, and H2 closes it: `ticket.%` is added to the prefix list.**
   See §4. That was the last destructive key family outside it.

---

## 7. RESIDUAL RISKS — recorded, not closed

1. **The anchor is mutable by the venue.** Inherited verbatim from G2's Part 3: a paired backward move of
   `starts_at`+`ends_at` is permitted while `door_open_at is null` (`079:628`), with a mandatory
   `reason_code` and a `session.update` audit row. A venue could shorten its buyers' deletion hold. The
   incentive is perverse (it destroys the venue's own counterparty) and the audit trail is complete, but
   it is real. Right fix: an immutable anchor stamped at `venue.finalize_primary_order`, or a
   backward-move guard — both DDL against frozen migrations, outside 093.
2. **Tombstoned-then-chargebacked.** Not covered by any hold. OR-13/16c's ruled path (the chargeback
   lands against the tombstone, `kernel.identity_obligation` / BP-10). A longer hold narrows the window;
   no commercially or legally viable hold closes it.
3. **The orphan key.** `deletion.refund_possible_window_hours` remains settable and reads to nothing.
   Recorded in `142 A16`/`149 A16b` comments so the next reader does not re-wire it.
4. ~~`ticket.expiry_grace` has no dual control and no type guard~~ — **both are now closed.** The type
   guard predates H2 (`40:1248`); H2 adds `ticket.%` to dual control. Retained here struck through
   rather than deleted, so a reader of an earlier draft of this document sees the correction.
5. **The hold value itself is a trade, not a derivation.** Stripe's ~120-day post-event dispute window
   (https://docs.stripe.com/disputes/how-disputes-work) cannot be fully covered by an erasure hold. 720h
   (30 days) is what the matrix was executed against and is offered on stated grounds; it is the owner's
   number, and 093 invents none.
