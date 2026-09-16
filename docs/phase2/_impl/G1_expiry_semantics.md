# G1 — What "ticket expired" MEANS, and the expiry model

**Status:** research finding, read-only. No migration, code or test modified.
**Branch:** `feature/venue-native-and-product-v2`, head `ca0ac0a`.
**Method:** static reading of `supabase/migrations/076..093` + `docs/`, **plus** an empirical replay on a
local rehearsal database (`scripts/rehearsal_reset.sh snatchit_rehears_expiry`, full 000..093 replay).
Every claim marked **[V]** below was executed against that database, not inferred.
**Relationship to R1** (`docs/phase2/_impl/R1_ticket_expiry_derivation.md`): R1's derivation finding is
confirmed. Three of its load-bearing conclusions are **corrected** — see §8.

---

## 0. HEADLINE

1. **`expired` means exactly one enforced thing:** *this credential is no longer admissible at a door.*
   Every other consequence is either a side effect of that (deletion unblocks, wallet pass follows) or
   is untouched (visibility, history, settlement, routine refund).
2. **The deletion clock does NOT need to be the same clock**, and — the finding R1 missed — for every
   buyer who *paid*, `ticket.expiry_grace` **is not the binding gate at all.** `kernel.deletion_blockers_money`
   BP-12 arm 2 already gates deletion on a second, purpose-built, order-anchored key
   (`deletion.refund_possible_window_hours`, `085:273`) which is **also unset and fails CLOSED**. **[V]**
   Setting `ticket.expiry_grace` alone unblocks nobody who bought a ticket.
3. **Because BP-12 independently holds the money line, `ticket.expiry_grace` does not have to be the
   money-safety clock, and therefore does not have to be long.** It should be chosen purely on
   admissibility grounds.
4. **Recommended value: `'"72 hours"'::jsonb`** — a jsonb **string**, spelled in **hours**, never days.
   Justified in §7 from three ratified constants, not from taste.
5. **The highest-risk implementation detail is the opposite of what R1 states.** A jsonb *number* does
   **not** fail the cast: `('24'::jsonb #>> '{}')::interval` = `00:00:24` — **twenty-four seconds**. **[V]**
   And `catalog.set_platform_config` cannot stop it, because 093 seeds the row as JSON `null`, so the
   type witness at `078:1115-1118` is disarmed for the first write, and `ticket.%` matches no
   dual-control prefix (`078:1145-1147`). One `platform_admin` statement, no second human, and every
   ticket of every past session is terminal within two minutes.

---

## 1. EVERY CONSUMER OF EXPIRY

The only writer of `state='expired'` is `kernel.sweep_expired_ticket_atoms` (`079:456`, cron
`*/2 * * * *` at `079:799-803`, `p_limit int default 100` **[V]**, `EXECUTE` to `postgres` +
`service_role` only **[V]**). Its transition is `active → expired` and nothing else (`079:503-505`).

**[V]** The complete set of functions in the applied database whose body writes `kernel.tickets.state`
is exactly three, and all three move *forward*:

| function | writes |
|---|---|
| `kernel.mark_ticket_scanned` | `'scanned'` |
| `kernel.void_ticket_atom` | `'voided'` |
| `kernel.sweep_expired_ticket_atoms` | `'expired'` |

**No shipped function writes `state` back to `'active'` or `'issued'`.** **[V]**

### 1.1 The consumer matrix

| Dimension | Affected by expiry? | Mechanism | Cite |
|---|---|---|---|
| **Scanner acceptance** | **YES — hard, terminal** | `kernel.mark_ticket_scanned` raises `not_active`; `venue.record_scan` catches it and writes `venue.scan.result='invalid'` | `079:433-437`, `086:1088-1097` |
| **Offline scan reconciliation** | **YES** | `venue.reconcile_offline_scans` replays each item through `record_scan` → same `not_active` refusal | `086:1130-1148` |
| **Door manifest (new adds)** | **YES** | an `'add'` delta is CHECK-constrained to `ticket_state='active'` | `086:379` (`dmd_add_active_ck`) |
| **Door manifest (already open)** | **NO — stale** | the base snapshot copies every atom in whatever state it held at open, and expiry appends **no** `revoke` delta; an offline device keeps a stale `active` entry | `086:781-785` |
| **QR / credential validity** | **INDIRECT** | `kernel.sweep_wallet_pass_lifecycle` sets `wallet_pass.status='expired'`, **one-way** (`where w.status='issued'`); the crypto wallet RPCs are PARKED fail-closed | `083:751-770`, `083:611-683` |
| **Ticket visibility in the app** | **NO** | RLS is `current_owner_id = auth.uid()` — state-independent **[V]** | `079:737-740`, `080:410-419` |
| **Attendee history** | **NO** | `market.get_ticket_history` reads `kernel.ticket_ownership_log`; expiry writes **no** log row **[V]** | `088:1552-1576`, `079:499-502` |
| **Routine refund (money)** | **NO** | `refund_primary_order` / `admin_refund` skip the *void* for `('voided','expired')` but still insert the `kernel.refund` row | `085:581-582`, `085:598-599`, `085:686` |
| **Buyer-initiated refund request** | **PARTIAL** | `kernel.request_order_refund` only targets `('issued','active')`; an expired atom is silently untargeted, but the money leg still parks/executes | `085:951` |
| **Cancellation refund** | **YES — CATASTROPHIC** | `catalog.cancel_event`'s three atom arms all filter `state in ('issued','active')`; an expired atom is voided by none and refunded by none **[V]** | `088:1682`, `088:1735`, `088:1783` |
| **Chargeback handling** | **DEGRADED** | `kernel.record_dispute_native` sets `resale_state='dispute_hold'` only for `('issued','active')`; an expired atom is skipped and audited with the **wrong** reason code `overlay_occupied` | `088:823-833` |
| **Deletion blocker (BP-1)** | **YES — this is the drain** | `kernel.deletion_blockers_custody` blocks on `state in ('issued','active')` **[V: clears on expiry]** | `079:706-717` |
| **Transfer eligibility** | **YES, but MOOT** | `kernel.transfer_ticket_ownership` requires `'active'` — and `is_transfer_frozen` is already TRUE from doors, long before expiry **[V]** | `088:650-651`, `079:265-289`, `078:441-445` |
| **Resale eligibility** | **YES, but MOOT** | `market.create_listing` / `checkout_buy_now` / `create_p2p_transfer` all require `'active'`; the rail is flag-off and P2P is parked anyway | `088:973`, `088:1272`, `088:1404`, `078:1524`, `088:1390` |
| **Financial obligation / settlement** | **NO** | settlement export and promoter commission survivorship both use `state <> 'voided'` — expired atoms still count and still settle | `087:818`, `090:1464` |
| **Notification** | **NONE** | no `notify` event type exists for atom expiry; the holder is never told their ticket died | grep of `092_notify_reduced.sql` |

### 1.2 The one-line reading

Of fifteen dimensions, expiry **enforces** exactly one that is live today (scanner acceptance),
**enables** exactly one (BP-1 deletion), **breaks** exactly one (cancellation refund), and **degrades**
one (chargeback overlay). Everything else is unaffected or unreachable.

**`expired` is therefore not "the ticket is over". It is "the door will refuse this."** Any design that
loads more meaning onto it is loading meaning onto a label three functions can read.

---

## 2. WHAT TIME FACTS ACTUALLY EXIST

### 2.1 `catalog.event` — no time at all

`078:134-158`. Columns: `event_id, venue_id, org_id, title, status, description, hero_image_ref,
category, genre_tags, created_at, updated_at`. **No `starts_at`, no `ends_at`, no cutoff, no timezone.**
The event is a marketing aggregate. Every candidate derivation anchored on "the event" is therefore
**not expressible**.

### 2.2 `catalog.event_session` — all time lives here

`078:173-197`:

| Column | Type | Null? | Role |
|---|---|---|---|
| `starts_at` | `timestamptz` | **NOT NULL** | the only guaranteed instant; freeze input |
| `ends_at` | `timestamptz` | **NULLABLE** | the sweep's anchor (`079:493-494`) |
| `doors_at` | `timestamptz` | nullable | informational; freeze input |
| `door_open_at` | `timestamptz` | nullable | canonical freeze head; sole writer `catalog.engage_door_freeze` (`086:436`) |
| `status` | `text` | not null | `scheduled\|live\|completed\|cancelled` |

`kernel.tickets.event_session_id` is `not null references catalog.event_session(session_id) on delete
restrict` (`079:34`), so the sweep's join is total and **a ticket always binds to exactly one session.**
Multi-session events are handled correctly by construction: **[V]** an atom on an ended session expired
while an atom on the same event's future session stayed `active`.

### 2.3 Timezone

**There is no timezone column anywhere in `catalog`, `kernel` or `venue`.** `catalog.venue`
(`078:98-115`) has `neighborhood` (a Miami-only check-set) and `address`, no tz. Every time column in
the phase-2 substrate is `timestamptz`. Expiry arithmetic is absolute-instant arithmetic; there is no
local-midnight ambiguity in the database. The timezone risk is entirely **client-side**: a venue
dashboard that submits a naive local wall-clock string for `ends_at`.

### 2.4 Is there a door-close or explicit venue cutoff in 086?

**There is a door-close fact, but it is not usable as an expiry anchor.**

- `venue.door_manifest.closed_at` (`086:252`) — written by `venue.close_door_manifest` (`086:811-838`).
  Real, but **per-episode, nullable, and only exists if native scanning ran.** Scanning is flag-off
  (`078:1523`), so today no session has ever had a manifest.
- `venue.door_manifest.not_after` (`086:251`) — a TTL, `now() + door.manifest_ttl_interval` (12h,
  `078:1536`), not a venue-declared cutoff.
- **There is no `admission_until` / `cutoff_at` / `last_entry_at` column anywhere.** An explicit venue
  cutoff concept **does not exist in the schema.**

### 2.5 The already-ratified post-session constants (the only numeric evidence in the corpus)

| Key | Seed | Cite |
|---|---|---|
| `door.max_override_interval` | `"2 hours"` | `078:1538` |
| `door.session_post_session_grace` | `"4 hours"` | `078:1541` |
| `door.manifest_ttl_interval` | `"12 hours"` | `078:1536` |
| `door.session_ttl_interval` | `"12 hours"` | `078:1539` |
| **`door.session_absolute_max_interval`** | **`"24 hours"`** | **`078:1540`** |
| `credential.app_ttl_interval` | `"4 hours"` | `078:1530` |
| `authn.money_role_maturity_hours` | `72` | `078:1560` |

---

## 3. THE CENTRAL QUESTION — IS ONE TIMESTAMP OVERLOADED?

### 3.1 The framing in the prompt is right, but the premise is incomplete

The prompt (and R1 §4, `H_migration_design.md:212-217`, `D_deletion_refund.md:189-195`, ruling D2)
all assert: *expiry is the only live drain of BP-1, therefore an unset key makes a no-show buyer
permanently undeletable.* Each half is individually true. Together they imply that setting
`ticket.expiry_grace` unblocks the buyer. **It does not.**

**[V] Measured on the rehearsal database**, for one identity holding one live atom on an ended session
and one `venue."order"` with `status='paid'`:

```
BP-1  → "BP-1: live custody — issued/active atom(s) held; clears via scan, void, expiry or transfer-out"
BP-12 → "BP-12: refund-possible window unset (deletion.refund_possible_window_hours) with
         candidate orders present"
```

After seeding `ticket.expiry_grace = '"24 hours"'` and letting the sweep run:

```
BP-1  → <CLEAR>
BP-12 → still blocking          -- unchanged
```

Only after **also** setting `deletion.refund_possible_window_hours` (and ageing the order past it) did
BP-12 clear.

`kernel.sweep_deletion_pending` `coalesce`s the blockers in order (`078:1709-1762`), so **both** must be
null before an identity is tombstoned. `deletion.refund_possible_window_hours` is seeded `'null'::jsonb`
at `085:2189` and its consumer at `085:268-283` **returns a blocker when the value is null and a
candidate order exists** — i.e. it is **fail-CLOSED**, unlike the expiry sweep.

**Consequence:** for every buyer who paid, `ticket.expiry_grace` is *not* the binding constraint on
erasure. `deletion.refund_possible_window_hours` is. The population for whom BP-1 is the sole live
blocker is exactly: **holders of comp, guest-list and imported atoms** — atoms with no `venue."order"`
row — plus anyone whose orders have all reached `refunded`/`cancelled`.

### 3.2 Do the two facts need the same clock? **No.**

| | admissibility | custody-conclusion (erasure) |
|---|---|---|
| question | can a door still legitimately admit this? | has this holder's live relationship to this credential ended? |
| correct anchor | the last instant a door session could be operating | the last instant a money or dispute path could reach back |
| ratified bound in corpus | `door.session_absolute_max_interval = 24h` (`078:1540`) | `deletion.refund_possible_window_hours`, anchored on `venue."order".created_at` (`085:277-281`) |
| who is harmed by "too short" | the ticket holder (terminal-ized live credential; excluded from `cancel_event` refund) | the platform (identity erased while money can still move) |
| who is harmed by "too long" | nobody — an unexpired atom is already transfer-frozen (`079:265-289`) and unscannable at a closed door | the holder (erasure latency) |

**They are different questions with different anchors and different victims. They should not share a
clock, and the corpus already agrees with itself on this point** — it built a separate, order-anchored
key for the money half rather than reusing the session anchor.

### 3.3 …but the coupling is structural, and here is exactly how much of it can be undone

`kernel.deletion_blockers_custody` (`079:706-717`) reads **only** `state`. 079 is immutable. So BP-1
cannot be given its own clock without a **new function body in a new migration**. That is legitimate
and precedented: BP-1's own body is already a `CREATE OR REPLACE` of the 077 stub under SEAM-2a
(`079:702-706`, `077:1708-1710`). A further replacement is the established pattern, not a violation.

So there are two implementable postures, and they are not exclusive:

**Posture A — do nothing structural; choose the grace on admissibility grounds only.**
Justified *because* BP-12 exists and is independent. A short-ish grace costs the platform nothing on
the money side, because BP-12 still holds that line on its own clock. This needs **only the config
value** and is the recommendation for now.

**Posture B — decouple BP-1 (the correct end state, a follow-up migration).**
Replace `kernel.deletion_blockers_custody` with a body that clears when the atom is terminal **or** the
atom's session ended more than `deletion.custody_conclusion_interval` ago:

```sql
-- SKETCH ONLY — not authored, not applied.
select 'BP-1: live custody — …'
 where exists (
   select 1 from kernel.tickets t
     join catalog.event_session s on s.session_id = t.event_session_id
    where t.current_owner_id = p_identity
      and t.state in ('issued','active')
      and (s.ends_at is null                                     -- unbounded session: still blocks
           or now() <= s.ends_at + <deletion.custody_conclusion_interval>))
```

This buys three things at once:
1. erasure stops depending on a *terminal label being stamped* — the grace can then be set for
   admissibility alone with no erasure pressure at all;
2. it fixes the **`state='issued'` residual** (BP-1 blocks on `'issued'` at `079:716`, the sweep drains
   only `'active'` at `079:491`/`079:505` — an `'issued'` atom is **permanently unsweepable**; the mint
   writes `'active'` at `083:559` so it is latent, but `'issued'` is the column DEFAULT at `079:41`);
3. it removes the last reason anyone would argue for a *long* expiry grace.

**Recommendation: A now, B as a named follow-up.** Do **not** stretch `ticket.expiry_grace` to serve
erasure. That is precisely the overload the prompt asks about, and it is avoidable.

---

## 4. CANDIDATE DERIVATIONS — EXPRESSIBILITY

| Candidate | Expressible? | Verdict |
|---|---|---|
| **event start** | **NO** — `catalog.event` has no time columns (`078:134-158`) | dead |
| **event end** | **NO** — same | dead |
| **session start** (`starts_at`) | YES (NOT NULL) | wrong: a ticket must survive its own show |
| **session end** (`ends_at`) | YES, but **nullable** | the shipped anchor (`079:493-494`) |
| **door close** | Only as `venue.door_manifest.closed_at` (`086:252`) — per-episode, nullable, and **no manifest has ever existed** (scanning flag-off, `078:1523`) | not usable as a sweep anchor |
| **explicit venue cutoff** | **NO** — no such column exists anywhere | dead |
| **session end + configurable grace** | YES | **the only candidate that is both expressible and correct** |
| **explicit per-atom TTL at mint** | **NO** — `kernel.tickets` has no `expires_at`/`valid_until` (`079:32-58`); the mint stamps none (`083:557-560`) | dead; would require altering an immutable table |

The derivation is settled and R1 is right about it. The weaknesses are in the **anchor**, not the
formula:

- **`ends_at` is nullable** and `catalog.create_event_session` requires only `starts_at`
  (`078:806-810`). A session created without an end **never expires anything**, whatever the grace.
  **[V]** confirmed with a live grace set.
- **`ends_at` is freely mutable in both directions, forever, with no reason code.**
  `catalog.update_event_session`'s time guard block (`079:624-659`) is entered **only** when
  `starts_at` or `doors_at` change. An `ends_at`-only patch skips `boundary_engaged` (`079:628`),
  `move_exceeds_grace` (`079:652`) and `reason_required` (`079:657`) entirely.
- **The `session_terminal` guard (`079:584`) is unreachable.** **[V]** The only function in the applied
  database that writes `catalog.event_session.status` is `catalog.cancel_event`. **Nothing ever sets
  `'completed'` or `'live'`.** So `ends_at` remains editable *forever*, including years after the show.

---

## 5. RED TEAM — WHERE TERMINAL EXPIRY CAN BE WRONG

Assume the recommended `'"72 hours"'` unless noted.

| # | Scenario | Wrongly terminal? | Detail |
|---|---|---|---|
| 1 | **Event postponed before expiry** | **NO — postponement is impossible today** | `catalog.update_event_session` refuses *any* later move of `starts_at`/`doors_at` once atoms exist, because `door.schedule_move_grace_interval` is unseeded and the guard is fail-closed (`079:634-652`). The venue's only sanctioned tools are `cancel_event` or a bare `ends_at` edit. |
| 2 | **Postponed after the original end** | **YES — the single most likely wrongful terminal** | **[V]** Atoms expire; moving `ends_at` five days out afterwards returns `{"swept_count": 0}` and the atoms stay `expired`. Combined with #5 the holder loses **ticket and refund**. 72h buys three days of cover; beyond that only a runbook (§6) recovers it. |
| 3 | **Rescheduled days later** | **YES** | identical to #2, guaranteed. |
| 4 | **Multi-session event** | **NO** | binding is `event_session_id` (`079:34`) and the sweep joins on it (`079:490`). **[V]** night-1 atom expired, night-2 atom on the same event stayed `active`. |
| 5 | **Event cancelled** | **SAFE before expiry; BROKEN after** | `catalog.cancel_event` filters `state in ('issued','active')` in all three arms (`088:1682/1735/1783`). **[V]** on a session with one expired atom: `would_refund_and_void = 0`, `excluded_expired = 1`. **The buyer loses the ticket AND the refund.** |
| 6 | **Late door operation** | **NO at 72h; MARGINAL at 24h; BROKEN below** | a door session may live at most `door.session_absolute_max_interval = 24h` (`078:1540`); a manifest 12h (`078:1536`). All close inside 72h. |
| 7 | **Scanner offline** | **NO at 72h** | `venue.reconcile_offline_scans` (`086:1130`) replays through `record_scan` → `mark_ticket_scanned`, which needs `'active'`. A batch reconciled after expiry silently becomes `result='invalid'` for **every** ticket in it. The ratified reconciliation window is `door.session_post_session_grace = 4h` (`078:1541`); 72h covers it 18×. |
| 8 | **Venue extends the event** | **NO — and it works** | an `ends_at`-only patch is permitted even after `door_open_at` is set (the guard at `079:628` is only reached on starts/doors changes), so extending correctly defers expiry. **The reverse is the hazard:** **[V]** moving `ends_at` *earlier* expired a live atom on the very next tick, with **no guard, no reason code and no audit of consequence**. |
| 9 | **Transfer near expiry** | **MOOT** | `kernel.is_transfer_frozen` is TRUE from `catalog.effective_freeze_at = least(door_open_at, coalesce(doors_at, starts_at))` (`078:441-445`) — i.e. from *doors*, strictly before `ends_at`. **[V]** TRUE on the expired atom. No transfer can be in flight anywhere near expiry. |
| 10 | **Resale near expiry** | **MOOT** | same freeze, plus `feature.native_resale_enabled=false` (`078:1524`) and `market.create_p2p_transfer` parked fail-closed (`088:1390`). |
| 11 | **Buyer deletes immediately after the event** | **NO harm** | deletion is `DELETION_PENDING`, re-swept every 2 min (`cron` job `sweep-deletion-pending` **[V]**). BP-1 defers for the grace; BP-12 defers for its own window. The user waits; nothing is lost. Erasure *before* money settles is BP-12's job, not expiry's. |
| 12 | **Chargeback after expiry** | **DEGRADED, not terminal** | `kernel.record_dispute_native` skips the `dispute_hold` overlay for a non-`('issued','active')` atom and audits reason `overlay_occupied` (`088:823-833`) — a **wrong** reason code for an expired atom. Money leg unaffected; BP-7 still blocks deletion on an open dispute (`088:484-491`). |
| 13 | **Refund after expiry** | **SAFE for money** | `refund_primary_order` (`085:581-582`) and `admin_refund` (`085:686`) skip the void but still write the `kernel.refund` row (`085:598-599`). Only `cancel_event` loses it. |
| 14 | **Wrong timezone** | **Schema-safe, client-exposed** | every column is `timestamptz`; **no** timezone column exists anywhere. The failure mode is a client submitting a naive local string for `ends_at`. A 72h grace absorbs a ±12h client error; a 4h grace does not. |
| 15 | **DST transition** | **NO — if spelled in hours** | `timestamptz + interval '72 hours'` is absolute-duration arithmetic and is DST-immune. `interval '3 days'` is **calendar** arithmetic in the session `TimeZone` and can differ by an hour across a DST boundary. **This is why the value must be spelled `"72 hours"` and never `"3 days"`.** |
| 16 | **`ends_at IS NULL`** | **Never expires — config cannot reach it** | `079:493` is deliberate (`POST_FREEZE_AMENDMENTS.md:1515-1516`); `create_event_session` requires only `starts_at` (`078:806`). **[V]** with a live grace, `swept_count: 0`. Reproduces the permanently-undeletable case in full for comp holders. |
| 17 | **`state='issued'` atom** | **Never expires — permanently unsweepable** | BP-1 blocks on `'issued'` (`079:716`); the sweep drains only `'active'` (`079:491`, `079:505`). Latent today (mint writes `'active'`, `083:559`) but `'issued'` is the column DEFAULT (`079:41`). |
| 18 | **Large session** | **Not a correctness bug, but the label is eventually-consistent** | `p_limit` default 100 **[V]** and the cron passes no argument (`079:802`) ⇒ **3,000 atoms/hour**. A 10,000-atom arena takes ~3.3h to drain. Reinforces `RPC §4.3.1`: *no path may trust `state <> 'expired'`.* |
| 19 | **Stale open manifest** | **Wrong in the *other* direction** | expiry appends no `revoke` delta; an offline device holding a manifest opened before expiry keeps a stale `'active'` entry (`086:781-785`). A wrongful **admit**, not a wrongful terminal. |

---

## 6. REVERSIBILITY

### 6.1 Is `expired` reversible in the schema?

**Physically yes; operationally no.** **[V]**

- The **only** constraint on `kernel.tickets.state` is `tickets_state_check` (a 5-value enum). There is
  **no** state-machine trigger. The two triggers on the table are `tg_tickets_set_updated_at` and
  `tg_custody_head_is_ledger_tail`, and the latter fires only `after insert or update of
  current_owner_id, credential_version` (`079:246-252`) — a `state` write is explicitly outside its
  clause set.
- **[V]** `update kernel.tickets set state='active' where … ` executed as the table owner **succeeds**.
- **[V]** But **no shipped function** writes `state` back (§1). There is no grant of `UPDATE` on
  `kernel.tickets` to `authenticated` (`079:727-735`).

So `expired` is reversible **only by a DBA statement outside every audited path** — i.e. the worst
possible form of reversibility: available in an incident, invisible to the ledger.

### 6.2 If a postponement moves `ends_at` later AFTER atoms expired?

**[V] Nothing happens.** The sweep re-runs and returns `{"swept_count": 0}`; the atoms remain
`expired`. The wallet pass is likewise stuck, because `sweep_wallet_pass_lifecycle` only advances rows
`where w.status = 'issued'` (`083:762`) — a pass already moved to `'expired'` never comes back.

### 6.3 Should it be reversible before some economic state is reached? **Yes.**

The natural point of no return is **settlement close**, not the label itself: `kernel.close_settlement`
(`093:582`) mints the venue payout; settlement lines are append-only and the header is write-once.
Before close, restating an atom costs nothing; after close, it cannot be reconciled.

**Proposed shape (new migration, NOT an edit to 079):**

```
kernel.reinstate_expired_atom(p_atom_id uuid, p_reason_code text, p_command_key text)
  · platform_admin only, shaped like kernel.force_void_ticket (085:739-751) — break-glass, not a user path
  · REFUSES if the atom's session has any settlement in a closed/closing state
  · REFUSES if the atom is 'scanned' or 'voided' (those are genuinely terminal)
  · writes state='active' + kernel.admin_audit; writes NO ticket_ownership_log row and NO
    credential_version bump — matching the sweep's own "expiry is not a custody move" discipline (079:499-502)
  · re-arms the wallet pass by resetting kernel.wallet_pass.status='issued' for the atom
```

Without it, the only recovery from a wrongful expiry is `kernel.admin_refund` (`085:686`) — money back,
ticket gone. That halves the "loses BOTH" hazard but does not fix it: the holder still cannot attend.

**Do not make the sweep itself reversible, and do not add a general un-expire verb.** The append-only /
terminal posture is correct; what is missing is a *bounded, audited, admin-only* escape hatch, which is
the same shape the corpus already accepted for `force_void_ticket`.

---

## 7. THE RECOMMENDATION

### 7.1 The model, precisely enough to implement

**Keep the shipped derivation. It is correct and it is the only expressible one.**

```
expired ⇔ state = 'active'
        ∧ session.ends_at IS NOT NULL
        ∧ now() > session.ends_at + config('ticket.expiry_grace')
```

**Set `ticket.expiry_grace` on ADMISSIBILITY grounds only.** Do not lengthen it to protect refunds or
erasure — refunds are protected by the runbook in §7.4 and erasure is protected by
`deletion.refund_possible_window_hours`.

### 7.2 The exact value

```sql
select catalog.set_platform_config(
  'ticket.expiry_grace',
  '"72 hours"'::jsonb,          --  jsonb STRING.  HOURS, not days.
  '<reason>', '<command key>');
```

**Justification, from evidence:**

1. **≥ 24h is a hard floor from a ratified constant.** `door.session_absolute_max_interval = "24 hours"`
   (`078:1540`) is the maximum lifetime the corpus grants a door session. A grace below it can
   terminal-ize an atom that a *still-valid* door session is entitled to scan — and `scanned` is the
   strictly better drain, because it is the one that also completes the money. A grace under 24h
   **contradicts a ratified number.** 72h clears it 3×.
2. **72 is the corpus's own expression of "long enough for a human to notice and act."**
   `authn.money_role_maturity_hours = 72` (`078:1560`) is the only multi-day interval the corpus has
   ratified, and it is ratified precisely as MD-14's *restrictive* end of a 24–72h range. Reusing the
   platform's own human-reaction constant is a derivation, not a preference.
3. **72h always crosses at least one full business day, for any day of the week.** A Friday-night show
   ending Saturday 02:00 expires Tuesday 02:00. This is the operational property that lets a
   mis-entered `ends_at` (§5 #8, #14) be caught before the label becomes terminal. 24h does not
   guarantee this; 48h does not guarantee it for a Friday show.
4. **Every ratified post-session operational window closes inside it:**
   `door.session_post_session_grace` 4h (`078:1541`), `door.manifest_ttl_interval` 12h (`078:1536`),
   `door.session_ttl_interval` 12h (`078:1539`), `door.max_override_interval` 2h (`078:1538`),
   `credential.app_ttl_interval` 4h (`078:1530`).

**Operational implications of TOO SHORT (< 24h):**
- an offline scan batch reconciled inside the ratified 4h post-session window is refused wholesale
  (`086:1130` → `079:433`) — every attendee in that batch is recorded `invalid`;
- a door session still legally open at hour 20 finds its atoms already terminal;
- any `ends_at` typo, client-timezone error, or deliberate early shortening (§5 #8) terminal-izes live
  tickets *the same night*, before any human is awake to see it;
- because expired atoms are excluded from `catalog.cancel_event` (§5 #5), each of those holders loses
  ticket **and** refund;
- and there is **no notification** (§1.1) — the holder finds out at the door.

**Operational implications of TOO LONG (say ≥ 30 days):**
- **the harmed population is small and specific:** holders of comp / guest / imported atoms, because
  everyone with a paid order is gated by BP-12 anyway (§3.1). Their erasure request sits in
  `DELETION_PENDING` with `deletion_block_reason = 'BP-1: live custody…'` for the whole window;
- no security or money exposure: an unexpired atom is already transfer-frozen (`079:265-289`),
  unlistable, and unscannable once the door episode closes;
- the only real cost is **erasure latency**, which is a regulatory-response-time risk, not a
  correctness one. 72h is comfortably inside any statutory window.

**Net:** the error is asymmetric — too short destroys entitlements irreversibly, too long adds
latency. **Bias long within the band, not short.** 72h.

### 7.3 THE TYPE TRAP — corrected, and it is worse than documented

R1 §5.2 and the `093:3221-3226` comment both state that a jsonb **number** "would fail the `::interval`
cast, hit the `exception when others` arm, and silently reproduce the fail-open bug." **That is wrong,
and the truth is far more dangerous.** **[V]**

```
select ('24'::jsonb #>> '{}')::interval;   -->  00:00:24     -- TWENTY-FOUR SECONDS
```

Postgres parses a bare numeric interval literal as **seconds**. So:

- `'"72 hours"'::jsonb` → 72 hours ✔
- `'72'::jsonb` (number) → **72 seconds** — the sweep runs, silently, at ~2-minute cadence, and every
  ticket of every past session is terminal within one tick. **[V]** confirmed end-to-end: with the key
  set to `24`, a live atom on a session that ended 30 hours ago swept to `expired`.
- `'"72"'::jsonb` (string "72") → also **72 seconds.**

And **nothing stops it**:

- `catalog.set_platform_config`'s type witness is `if jsonb_typeof(v_cur_val) <> 'null' and
  jsonb_typeof(p_value) <> jsonb_typeof(v_cur_val)` (`078:1115-1118`). 093 seeds the row
  `'null'::jsonb` (`093:3275`), so **the witness is disarmed for the very first write** — the first
  value sets the type, whatever it is.
- No RANGE arm exists for `ticket.*` (`078:1122-1143` covers four other keys only).
- `ticket.%` matches **no** dual-control prefix (`078:1145-1147`), so there is **no second human**.

**One `platform_admin` statement, typed wrong, is unrecoverable** — the atoms it terminal-izes are then
excluded from `cancel_event` refunds, and no shipped function un-expires them (§6).

**Mandatory pre-set verification (run in the same session, before the set):**

```sql
-- 1. prove the literal parses to the intended duration
select ('"72 hours"'::jsonb #>> '{}')::interval = interval '72 hours' as ok;      -- must be true

-- 2. prove what the sweep WOULD do, before arming it
select count(*) as would_expire_now
  from kernel.tickets t
  join catalog.event_session s on s.session_id = t.event_session_id
 where t.state = 'active' and s.ends_at is not null
   and now() > s.ends_at + interval '72 hours';

-- 3. prove the row's shape immediately after the set
select key, version, jsonb_typeof(value) as typ, (value #>> '{}')::interval as parsed
  from catalog.platform_config where key = 'ticket.expiry_grace' order by version desc limit 1;
--    typ MUST be 'string' and parsed MUST be 72:00:00
```

### 7.4 The cancellation runbook (this is what replaces "make the grace longer")

R1 §4.2 argues the grace must exceed the window in which a post-hoc cancellation could be issued. That
argument **proves too much**: a venue can cancel weeks later, so no finite grace closes it. The correct
resolution is procedural, and it must be written down:

> **A cancellation of an event whose session has already ended by more than `ticket.expiry_grace` MUST
> NOT rely on `catalog.cancel_event`.** Its three atom arms exclude expired atoms
> (`088:1682/1735/1783`) and will silently refund nobody. Use `kernel.admin_refund`
> (`085:660-700`) per payment instead — it skips the void for an expired atom but **still writes the
> `kernel.refund` row** (`085:686`, `085:598-599`), so the money returns.

Pair it with a standing alert:

```sql
-- must return zero rows: a cancellation that refunded nothing because the atoms were already expired
select a.subject_id, a.reason_code, a.created_at
  from kernel.admin_audit a
 where a.action = 'event.cancel_skip' and a.created_at > now() - interval '7 days';
```

### 7.5 Standing monitors (all three must read zero)

```sql
select count(*) from catalog.event_session where ends_at is null;            -- §5 #16
select count(*) from kernel.tickets       where state   = 'issued';          -- §5 #17
select count(*) from kernel.identity_ext                                     -- §3.1
 where deletion_state = 'DELETION_PENDING'
   and deletion_requested_at < now() - interval '30 days';
```

### 7.6 Ordered activation checklist

1. Set `ticket.expiry_grace = '"72 hours"'` (string, hours) — with §7.3's three checks.
2. Set `deletion.refund_possible_window_hours` (`085:2189`, still `null`, still fail-closed). **Without
   this, step 1 unblocks no paying buyer.**
3. Make `ends_at` mandatory at the product surface, and wire the §7.5 monitors.
4. Publish the §7.4 cancellation runbook.
5. Follow-up migration: `kernel.reinstate_expired_atom` (§6.3) and the BP-1 decoupling (§3.3 Posture B).
6. Only then flip `feature.native_issuance_enabled` (`078:1522`).

---

## 8. WHERE THIS CORRECTS R1

| R1 claim | Status | Correction |
|---|---|---|
| Derivation is `ends_at + grace`, already shipped, options (b)/(c) foreclosed | **CONFIRMED** | — |
| "A jsonb number would fail the `::interval` cast … and silently reproduce the fail-open bug" (§5.2) | **WRONG, and the error is dangerous** | `('24'::jsonb #>> '{}')::interval = 00:00:24` **[V]**. A number does not fail — it becomes **seconds**, the maximally destructive setting. And `set_platform_config`'s type witness is disarmed by the `null` seed (`078:1115-1118`), so nothing catches it. |
| "Expiry is the ONLY drain; without the key a no-show buyer is permanently undeletable" (§4) | **TRUE BUT INCOMPLETE, and therefore misleading** | BP-12 arm 2 (`085:268-283`) independently blocks every buyer with a paid order, fails CLOSED, and is equally unset (`085:2189`). **[V]** Setting `ticket.expiry_grace` alone changes nothing for a paying buyer. The BP-1-only population is comp/guest/imported holders. |
| "The grace must be long because `cancel_event` excludes expired atoms" (§4.2, §5.3) | **Directionally right, unbounded as stated** | No finite grace closes a cancellation that can arrive weeks later. The fix is the §7.4 runbook (`admin_refund` still returns money on an expired atom, `085:686`) plus the `event.cancel_skip` alert — not a longer number. |
| "24h–72h band; choosing within it is the owner's call" (§5.3) | **Band confirmed; the indeterminacy is not necessary** | Three ratified constants pick 72h: the 24h door floor (`078:1540`), the corpus's own 72h human-reaction constant (`078:1560`), and the business-day-crossing property. |
| §6.2: "093 should deviate from I-3 and seed a real interval" | **Superseded by what shipped, and shipped is right** | 093 seeds `'null'::jsonb` (`093:3275`) with the argument recorded in-file. The correct closure is the ordered checklist in §7.6, not a value baked into a migration. |
| §6.3: `ends_at is null` is a second fail-open path; recommend `SET NOT NULL` | **CONFIRMED [V]**, recommendation downgraded | `SET NOT NULL` makes the `ends_at is null` arm of `event_session_time_check` (`078:195-197`) dead and contradicts 078's deliberate nullability. Prefer product-surface enforcement + the §7.5 monitor, since the session-status guard that would have made this safe (`079:584`) is itself unreachable **[V]**. |
| §4.1: `state='issued'` is unsweepable | **CONFIRMED**, and it is now *fixable* | Posture B (§3.3) removes it as a side effect, because BP-1 stops depending on the label. |

---

## 9. EMPIRICAL LEDGER

Run on `snatchit_rehears_expiry` (full 000..093 replay via `scripts/rehearsal_reset.sh`). Fixture: one
org / venue / event; three sessions (ended 30h ago, future, `ends_at` NULL); four atoms; one paid
`venue."order"`.

| # | Assertion | Result |
|---|---|---|
| V1 | grace unset (`'null'::jsonb`, as 093 ships) ⇒ sweep no-op | `{"swept_count": 0}`, all atoms unchanged |
| V2 | BP-1 **and** BP-12 both block before expiry | both returned blocker strings |
| V3 | grace `"24 hours"` ⇒ only the ended-session atom expires | `{"swept_count": 1}`; future-session and `ends_at`-NULL atoms untouched |
| V4 | grace as jsonb **number** `24` ⇒ 24 **seconds**, sweep fires | atom re-expired; `('24'::jsonb #>>'{}')::interval = 00:00:24` |
| V5 | expiry writes no ownership-log row | 1 row per atom (the `issue` row) throughout |
| V6 | BP-1 clears on expiry; BP-12 does **not** | BP-1 `<CLEAR>`; BP-12 still blocking |
| V7 | BP-12 clears only when its own key is set and the order ages out | cleared after setting `deletion.refund_possible_window_hours` |
| V8 | postponing `ends_at` +5 days after expiry does **not** restore | `{"swept_count": 0}`; state stays `expired` |
| V9 | moving `ends_at` **earlier** expires a live atom on the next tick, unguarded | `{"swept_count": 1}` |
| V10 | `expired` is reversible by a raw owner `UPDATE` (no trigger blocks it) | succeeded |
| V11 | no shipped function writes `state` back to `active`/`issued` | 0 rows |
| V12 | exactly three functions write `kernel.tickets.state`, all forward | `mark_ticket_scanned`/`void_ticket_atom`/`sweep_expired_ticket_atoms` |
| V13 | `cancel_event` would touch 0 atoms on a session whose only atom is expired | `would_refund_and_void = 0`, `excluded_expired = 1` |
| V14 | an expired atom is still `is_transfer_frozen` | `true` |
| V15 | RLS on `kernel.tickets` is state-independent | `kernel_tickets_sel_owner USING (current_owner_id = auth.uid())` |
| V16 | nothing writes `event_session.status` except `catalog.cancel_event` | 1 row |
| V17 | `ends_at IS NULL` session never sweeps, whatever the grace | `{"swept_count": 0}` |
| V18 | sweep signature / cron cadence / grants | `p_limit integer DEFAULT 100`; `*/2 * * * *`; EXECUTE = `postgres`, `service_role` |
| V19 | `platform_config` is DELETE-proof (append-only) | `append_only: platform_config is immutable` |

---

## 10. CITATION INDEX

| Claim | Cite |
|---|---|
| Sweep definition / default limit | `079:456` |
| Config read + `exception when others` + inert return | `079:475-486` |
| Derivation predicate, `ends_at is not null` guard | `079:488-497` |
| `active → expired`, no log row, no credential bump | `079:499-506` |
| Cron `*/2 * * * *` | `079:799-803` |
| BP-1 live custody | `079:706-717` |
| `kernel.tickets` shape, `state` DEFAULT `'issued'` | `079:32-58`, `079:41` |
| Custody trigger clause set (state is outside it) | `079:246-252` |
| RLS: owner / platform | `079:737-745` |
| RLS: venue/org | `080:410-419` |
| `mark_ticket_scanned` requires `'active'` | `079:433-437` |
| `is_transfer_frozen` | `079:265-289` |
| `update_event_session` — time guard scope, `session_terminal`, `move_exceeds_grace` | `079:518`, `079:584`, `079:624-659` |
| `catalog.event` has no time columns | `078:134-158` |
| `catalog.event_session` shape | `078:173-197` |
| `catalog.venue` (no timezone) | `078:98-115` |
| `create_event_session` requires only `starts_at` | `078:806-810` |
| `effective_freeze_at` | `078:405-446`, esp. `078:441-445` |
| `set_platform_config` unknown-key refusal | `078:1103` |
| type witness disarmed by a `null` seed | `078:1115-1118` |
| RANGE arms (none for `ticket.*`) | `078:1122-1143` |
| dual-control prefixes (`ticket.%` excluded) | `078:1145-1147` |
| feature flags seeded `false` | `078:1522-1524` |
| `credential.app_ttl_interval` | `078:1530` |
| door constants | `078:1536`, `078:1538`, `078:1539`, `078:1540`, `078:1541` |
| `authn.money_role_maturity_hours = 72` | `078:1560` |
| deletion sweep, blocker `coalesce` order | `078:1696-1762` |
| erasure terminal entry (no `auth.users` delete, no atom re-pointing) | `078:1801-1860` |
| mint writes `state='active'` | `083:557-560` |
| wallet-pass lifecycle follows the atom, one-way | `083:751-770` |
| wallet crypto RPCs parked | `083:611-683` |
| BP-12 arm 2 + `deletion.refund_possible_window_hours` | `085:262-283` |
| `deletion.refund_possible_window_hours` seeded null | `085:2189` |
| routine refund skips void, still refunds | `085:581-582`, `085:598-599`, `085:686` |
| `request_order_refund` targets only `('issued','active')` | `085:951` |
| `force_void_ticket` is break-glass | `085:739-751` |
| door manifest table / `closed_at` / `not_after` | `086:242-264` |
| `dmd_add_active_ck` | `086:379` |
| `open_door_manifest` base snapshot (all states) | `086:781-785` |
| `close_door_manifest` | `086:811-838` |
| `record_scan` gate + `invalid` mapping | `086:1075-1097` |
| `validate_ticket_online` admissibility | `086:1111-1128` |
| `reconcile_offline_scans` | `086:1130-1148` |
| settlement export uses `state <> 'voided'` | `087:818` |
| `record_dispute_native` skips non-active atoms | `088:812-833` |
| transfer / listing / buy-now / p2p require `'active'` | `088:650-651`, `088:973`, `088:1272`, `088:1404` |
| `create_p2p_transfer` parked | `088:1390` |
| `cancel_event` excludes expired atoms (3 arms) | `088:1682`, `088:1735`, `088:1783` |
| `cancel_event` sets session/event `'cancelled'` | `088:1793` |
| `get_ticket_history` (ownership log only) | `088:1552-1576` |
| promoter survivorship uses `state <> 'voided'` | `090:1464` |
| 093 seeds `ticket.expiry_grace` `'null'::jsonb` + rationale | `093:3180-3275` |
| `close_settlement` (the economic point of no return) | `093:582` |
| E-18 (not seeded; `ends_at IS NULL` expires nothing) | `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:1506-1516`, `:644-655` |
| D2 approval text, unsigned | `docs/phase2/PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:786-802`, `:986` |
| I-3 (093 creates rows) | `docs/phase2/_rulings/H_migration_design.md:186-220` |
| deletion chain analysis | `docs/phase2/_decisions/D_deletion_refund.md:189-195`, `:440-443` |
| prior derivation research | `docs/phase2/_impl/R1_ticket_expiry_derivation.md` |
