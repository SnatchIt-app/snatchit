# R1 — How a venue-direct ticket's EXPIRY is derived

**Status:** research finding, read-only. No repo file modified; no migration authored.
**Branch:** `feature/venue-native-and-product-v2`
**Scope of the question:** whether ticket expiry derives from event/session end, a configured grace,
or an explicit TTL — and what `093` must therefore create.

**Headline.** *The derivation is already shipped and already event-derived.* It is
`event_session.ends_at + config('ticket.expiry_grace')`. Nothing about the derivation needs to be
invented, chosen, or ruled on. The **only** unratified quantity in the entire chain is the scalar
value of the grace interval, and the **only** thing `093` must create is one
`catalog.platform_config` row.

---

## 1. THE SWEEP

**Function:** `kernel.sweep_expired_ticket_atoms(p_limit int default 100)`
`supabase/migrations/079_kernel_ticket_atom_and_ownership_log.sql:456`

**The config key it reads — exact string:**

```
'ticket.expiry_grace'
```

read at `079:477`, via the standard latest-version lookup:

```sql
v_grace := (select (c.value #>> '{}')::interval
              from catalog.platform_config c
             where c.key = 'ticket.expiry_grace'
             order by c.version desc
             limit 1);
```
`079:476-482`

The `::interval` cast on `value #>> '{}'` is the **type witness**: the key's value must be a JSON
**string** parseable as a Postgres `interval`.

**Behaviour when the key is unset — VERIFIED, returns zero:**

```sql
exception when others then
  v_grace := null;
end;
if v_grace is null then
  return jsonb_build_object('swept_count', 0);
end if;
```
`079:483-486`

The `exception when others` arm at `079:483-484` means **absent, JSON-null, and unparseable all
collapse to the same no-op**. Zero atoms are swept. The function's own header comment states the
intent verbatim:

> `config('ticket.expiry_grace')`: a CLASS A key under PFA-9's applied ruling (spelled + consumed, in
> NO authoritative seed table — completeness correction E-18): NOT seeded, and the consumer is
> fail-to-safe. Here the safe direction is INERT
> — `079:467-474`

**The state transition it performs:**

```sql
update kernel.tickets
   set state = 'expired', updated_at = now()
 where ticket_atom_id = v_row.ticket_atom_id
   and state = 'active';
```
`079:502-506`

`active → expired` **only**. `scanned`/`voided`/`expired` are terminal (§7.6) and are not rewritten
(`079:498-501`). No `kernel.ticket_ownership_log` row, no `credential_version` bump — expiry is a
lifecycle fact, not a custody move, so `kernel.tg_custody_head_is_ledger_tail` does not fire.

**Scheduled:** `cron.schedule('sweep-expired-ticket-atoms', '*/2 * * * *', …)` — `079:799-803`.

### 1.1 The derivation is ALREADY in the shipped body

This is the load-bearing finding of the whole investigation:

```sql
for v_row in
  select t.ticket_atom_id
    from kernel.tickets t
    join catalog.event_session s on s.session_id = t.event_session_id
   where t.state = 'active'
     -- a session with no ends_at has not verifiably ended: fail-inert.
     and s.ends_at is not null
     and now() > s.ends_at + v_grace
   limit p_limit
   for update of t skip locked
```
`079:488-497`

The shipped predicate is **exactly** `now() > session.ends_at + grace`. The architecture has already
ruled the derivation. Option (a) — deterministic event-derived expiry plus configurable grace — is
not a recommendation to be adopted; it is the code that is already in production bytes.

---

## 2. THE DERIVATION SOURCES AVAILABLE

### 2.1 `catalog.event` (078) — carries NO time facts at all

`supabase/migrations/078_catalog_reference_data_and_flags.sql:134-153`

```sql
create table if not exists catalog.event (
  event_id       uuid primary key default gen_random_uuid(),
  venue_id       uuid not null references catalog.venue(venue_id) on delete restrict,
  org_id         uuid not null references kernel.organization(org_id) on delete restrict,
  title          text not null,
  status         text not null default 'draft'
                 check (status in ('draft','announced','on_sale','live','completed','cancelled')),
  description    text,
  hero_image_ref text,
  category       text,
  genre_tags     text[] not null default '{}' …,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
```

**There is no `end_at`, no `starts_at`, no `doors_close`, and no timezone column on `catalog.event`.**
The event is a marketing/aggregation object. **All time lives on the session.** This closes the
question definitively: expiry cannot derive from the event row.

### 2.2 `catalog.event_session` (078) — the session concept, and it HAS an end time

`078:173-197`

```sql
create table if not exists catalog.event_session (
  session_id      uuid primary key default gen_random_uuid(),
  event_id        uuid not null references catalog.event(event_id) on delete restrict,
  session_label   text,
  starts_at       timestamptz not null,
  ends_at         timestamptz,
  doors_at        timestamptz,
  door_open_at    timestamptz,
  status          text not null default 'scheduled'
                  check (status in ('scheduled','live','completed','cancelled')),
  home_region     text not null default 'us-east',
  session_version integer not null default 1,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint event_session_label_uq unique (event_id, session_label),
  constraint event_session_time_check
    check (ends_at is null or starts_at is null or ends_at > starts_at)
);
```

Facts that matter:

| Column | Type | Null? | Role |
|---|---|---|---|
| `starts_at` | `timestamptz` | **NOT NULL** | the only guaranteed time fact |
| `ends_at` | `timestamptz` | **NULLABLE** | the sweep's anchor — see §6.2 |
| `doors_at` | `timestamptz` | nullable | informational |
| `door_open_at` | `timestamptz` | nullable | canonical door-freeze signal (`078:180-184`) |

**Timezone:** there is **no** timezone column anywhere in `catalog` — every time column is
`timestamptz`, i.e. an absolute instant. Expiry arithmetic is therefore timezone-free and
deterministic; there is no local-midnight ambiguity to resolve. This is a positive finding: it
removes an entire class of owner question.

`kernel.tickets.event_session_id` is `not null references catalog.event_session(session_id) on
delete restrict` (`079:34`), so **every ticket atom always has a resolvable session**, and the join
in the sweep is total.

### 2.3 `kernel.tickets` (079) — has NO expiry column

`079:32-58`. The time columns are `issued_at`, `created_at`, `updated_at`. There is **no
`expires_at`, no `ttl`, no `valid_until`.**

This eliminates option **(b) explicit TTL from mint**: there is nowhere to store a per-atom TTL. The
mint engine (`kernel.issue_ticket_atoms`, `083:439`) inserts
`(event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, state, credential_version,
signing_key_id)` — `083:557-560` — and writes `state='active'` directly; it stamps no expiry.
Adopting (b) would require an `ALTER TABLE kernel.tickets`, a rewrite of the mint, **and** a rewrite
of the sweep in 079 — all of which are immutable. (b) is architecturally unavailable, not merely
unattractive.

### 2.4 The already-ratified time boundary that sits *before* the end

`catalog.effective_freeze_at(p_session_id)` — `078:405-446`:

```sql
return least(
  v_row.door_open_at,                                  -- explicit, nullable
  coalesce(v_row.doors_at, v_row.starts_at) + v_offset -- implicit, NEVER null
);
```
`078:441-445`

This is the **load-bearing** guard. `kernel.is_transfer_frozen` (`079:276`) freezes every atom of a
session once `now() >= effective_freeze_at(session)` — i.e. **at doors, strictly before the session
ends**. The expiry sweep is downstream of a guard that is already stronger.

### 2.5 Adjacent, ALREADY-RATIFIED post-session-end grace constants

These are the corpus's only existing "how long after a session may an artifact live" values, seeded
in 078's 41-key block:

| Key | Seeded value | Cite |
|---|---|---|
| `door.session_post_session_grace` | `'"4 hours"'::jsonb` | `078:1541` |
| `door.session_ttl_interval` | `'"12 hours"'::jsonb` | `078:1539` |
| `door.manifest_ttl_interval` | `'"12 hours"'::jsonb` | `078:1534` |
| `door.session_absolute_max_interval` | `'"24 hours"'::jsonb` | `078:1540` |

`door.session_post_session_grace` is documented as: *"a token may not outlive the session it is
bound to by more than this — covers late reconciliation of an offline batch without leaving a live
credential for a finished show"* — `docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md:1318`.

These are **not** a value for `ticket.expiry_grace`, but they establish the corpus's ratified
outer bound on post-session operational activity: **24 hours** (`door.session_absolute_max_interval`).
See §5.3 for why that matters as a floor.

---

## 3. WHAT THE FROZEN ARCHITECTURE SAYS

The corpus is unusually explicit, and it says the derivation — never a number.

**Physical schema spec — the derivation, stated normatively:**

> The writer. `kernel.sweep_expired_ticket_atoms(p_limit)` — `service_role`/scheduler only, no human
> path, re-entrant, bounded batch. It advances `active → expired` for atoms whose
> `catalog.event_session` has ended by more than `config('ticket.expiry_grace')`
> — `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:537-539`

> **`expired` is presentational** — it is what makes *My Tickets* render a past ticket as spent
> rather than live — `…SCHEMA_SPEC.md:530-531`

**RPC contracts §12.5 — the same derivation, plus the standing rule:**

> **Purpose.** Advance `active → expired` for atoms whose `catalog.event_session` ended more than
> `config('ticket.expiry_grace')` ago. **Actor:** `service_role`/`pg_cron` only — **no human path**
> — `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md:2034-2035`

> **No path may trust `state <> 'expired'` because the tick was supposed to have run.**
> — `…RPC_FUNCTION_CONTRACTS.md:2049`

**POST-FREEZE errata E-18 — the key's classification and the `ends_at IS NULL` rule:**

> **E-18 — `ticket.expiry_grace` is a PFA-9 CLASS A key the register missed; the consumer ships
> fail-INERT.** Spelled and consumed by `kernel.sweep_expired_ticket_atoms` (schema §1.5.1, RPC
> §12.5), in no authoritative seed table, **no value anywhere**
> — `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:1506-1508`

> And a session with `ends_at IS NULL` expires nothing: "ended by more than the grace" is unevaluable
> without an end, and **the sweep never guesses one.**
> — `…POST_FREEZE_AMENDMENTS.md:1515-1516`

> `ticket.expiry_grace` — ADDED 2026-08-31 (completeness correction, package 079; erratum E-18) …
> in NO authoritative seed table, **NO value anywhere**. Same CLASS A disposition: NOT seeded; the
> consumer is fail-to-safe. The safe direction for THIS consumer is INERT
> — `…POST_FREEZE_AMENDMENTS.md:644-651`

**Owner ruling D2 — approves the mechanism, names no number, and is UNSIGNED:**

> **CLASSIFICATION: OPERATIONAL CONFIG**, but the key does not exist, so **its creation is
> IMPLEMENTATION FOLLOW-UP in a migration** — `set_platform_config` refuses unknown keys (`078:1103`).
> — `docs/phase2/PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:794-795`

> **APPROVAL TEXT — D2** — The ticket expiry configuration key is created by the migration and set to
> a value before the direct rail is activated. Until it is set, tickets never expire and any buyer
> holding an unscanned ticket is permanently undeletable. This requires no money to trigger and is
> therefore a precondition of issuance, not of selling.
> — `…FINAL_OWNER_RULINGS.md:797-802`

> | D2 | Ticket expiry key | **PENDING OWNER SIGNATURE** |
> — `…FINAL_OWNER_RULINGS.md:986`

**093 scope + the H ruling — the key belongs in 093:**

> `ticket.expiry_grace` — the sweep returns `{"swept_count": 0}` while unset (`079:477-485`). Not a
> sale blocker. But a no-show buyer's atom stays `active` forever, the live-custody deletion blocker
> never clears, and that buyer becomes **permanently undeletable**
> — `docs/phase2/_rulings/H_migration_design.md:212-217`

> 093 creates the ROWS. The VALUES are `set_platform_config` calls after 093 and before the flag flips.
> — `…H_migration_design.md:218-220`

> **Expiry key.** … The 093 placement is the correct one (`078:1096-1098` refuses unregistered keys;
> `ticket.expiry_grace` is registered nowhere) … It also belongs in **MUST**, not SHOULD
> — `docs/phase2/ADVERSARIAL_ARCHITECTURE_REVIEW.md:147-152`

### 3.1 Is there a ratified statement of HOW LONG after an event a ticket stays live?

**No.** Exhaustive search of `docs/`, every migration, and every ruling/decision file returns **ten**
mentions of `ticket.expiry_grace` across `_rulings/` and `_decisions/`, plus the spec/errata cites
above. **Not one of them carries a duration.** Every one of them says the same three things: the key
is unseeded, the sweep is inert while it is unseeded, and the value is owed forward.

---

## 4. THE DELETION INTERACTION — CONFIRMED

**The blocker predicate, verbatim:**

```sql
create or replace function kernel.deletion_blockers_custody(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$
  -- BP-1 LIVE CUSTODY (dsm §2): any kernel.tickets row with
  -- current_owner_id = :id and state in the non-terminal half of the enum.
  -- Drains: scanned · voided to SN-VOID · expired · transferred out. A listed
  -- or locked atom still blocks (the overlay keeps state='active').
  select 'BP-1: live custody — issued/active atom(s) held; clears via scan, void, expiry or transfer-out'
   where exists (select 1 from kernel.tickets t
                  where t.current_owner_id = p_identity
                    and t.state in ('issued','active'))
$$;
```
`079:707-717`

**The chain is confirmed, and all three alternative drains are closed today:**

1. **Scan** requires `feature.native_scanning_enabled` — seeded `false` at `078:1523`, gate at
   `086:1077`.
2. **P2P transfer out** — `market.create_p2p_transfer` is parked fail-closed unconditionally
   (`088:1390`); `feature.native_resale_enabled` seeded `false` (`078:1524`).
3. **Void** — `kernel.force_void_ticket` is platform_admin / platform_risk break-glass
   (`085:739-751`), not a user path.

> **4. So BP-1 clears only by scan, void, or expiry.** … **Expiry** requires `ticket.expiry_grace`,
> a PFA-9 CLASS A key that is **not seeded**; `kernel.sweep_expired_ticket_atoms` returns
> `{"swept_count":0}` and does nothing while it is unset (`079:474-485`). **This is a hard
> operational finding: without `ticket.expiry_grace`, a no-show buyer's atom never reaches `expired`
> and BP-1 never clears.**
> — `docs/phase2/_decisions/D_deletion_refund.md:189-195`

> **`ticket.expiry_grace` must be set.** Unset, `kernel.sweep_expired_ticket_atoms` is a no-op
> (`079:474-485`) and a no-show buyer's atom never leaves `active` — BP-1 blocks for ever. This is a
> *larger* permanent-block risk than BP-12, because it needs no money at all to trigger.
> — `…D_deletion_refund.md:440-443`

### 4.1 Residual: the sweep drains `active` but BP-1 also blocks on `issued`

BP-1 blocks on `state in ('issued','active')` (`079:716`). The sweep advances **only** `active`
(`079:491`, `079:505`). An atom sitting in `'issued'` is therefore **permanently unsweepable** and
would block deletion forever regardless of the config value.

Today this is latent, not live: the mint inserts `'active'` directly (`083:559`), so no writer
produces an `'issued'` row. But `'issued'` is the column **DEFAULT** (`079:41`), so any future
writer that omits `state` lands in the unsweepable half. **Flag as a standing invariant to monitor,
not a 093 blocker.** A monitoring query — `select count(*) from kernel.tickets where state='issued'`
— must read zero forever.

### 4.2 The hazard that bounds the grace from below (concrete, not theoretical)

`079:470-473` warns that stamping `expired` on a guessed grace "could terminal-ize an atom a later
refund path still needs." That warning has a **specific, findable instance**:

`catalog.cancel_event` selects atoms for the void+refund cascade with
`t.state in ('issued','active')` — at `088:1682`, `088:1735`, and `088:1783`. **An atom already
swept to `expired` is excluded from the cancellation refund entirely** and lands in the
`no_refund_lineage` / skip path.

By contrast, the *routine* refund path is safe: `085:581-582` skips `voided`/`expired` atoms for
**voiding** but still writes the `kernel.refund` row (`085:598-599`), so money is still returnable.

**Consequence for the grace value:** the grace must exceed the window in which a post-hoc event
cancellation could realistically still be issued. This is the only genuine engineering constraint on
the number, and it argues **against a very short grace**.

---

## 5. THE ANSWER

### 5.1 Recommendation: **(a) deterministic event-derived** — already implemented, do not re-derive

Expiry = `catalog.event_session.ends_at + config('ticket.expiry_grace')`.

This is not a proposal. It is `079:488-497`, ratified at
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:537-539` and `PHASE_2_RPC_FUNCTION_CONTRACTS.md:2034-2035`.
Options (b) and (c) are foreclosed:

- **(b) explicit TTL from mint** — no storage column on `kernel.tickets` (§2.3); would require
  altering an immutable table and rewriting two immutable functions.
- **(c) something else** — `catalog.event` carries no time facts at all (§2.1); there is no other
  time source in the schema that a ticket could reference.

**093 must therefore change NO logic. It creates one row.**

### 5.2 Exactly what 093 must create

**One row** in `catalog.platform_config` (`078:217-227` — PK `(key, version)`, append-only per
version via `tg_platform_config_append_only`, `078:241-244`):

| Field | Value | Why |
|---|---|---|
| `key` | `'ticket.expiry_grace'` | exact string read at `079:477` |
| `version` | `1` | first version; `platform_config_version_check` requires `>= 1` (`078:226`) |
| `value` | a **JSON string** parseable by `::interval`, e.g. `'"72 hours"'::jsonb` | the consumer casts `(c.value #>> '{}')::interval` at `079:478`; precedent is every `door.*` interval key at `078:1533-1541` |
| `visibility` | `'restricted'` | it is an operational threshold, not a client span (PFA-8 posture, cf. `078:1531-1541`) |

Written with `on conflict (key, version) do nothing`, matching the 078 seed idiom (`078:1581`).

**Type, stated unambiguously:** the value is a **jsonb string containing a Postgres interval
literal** — *not* a jsonb number, and *not* an hours integer. A number would fail the
`::interval` cast at `079:478`, hit the `exception when others` arm at `079:483`, and silently
reproduce the exact fail-open bug this work exists to close. This is the single highest-risk
implementation detail in the item.

**No other key is required.** The derivation reads exactly one config key.

**Post-093 setter behaviour (useful, and confirmed):** `ticket.%` is **not** matched by the
dual-control prefix test —
`v_dual := p_key like 'refund.%' or … or p_key like 'door.session\_%'` (`078:1145-1147`). So a later
`catalog.set_platform_config('ticket.expiry_grace', …)` is a **single `platform_admin` write with no
approval round**. The key also has no declared polarity (`078:1148-1196`, `else null`), which is
immaterial precisely because it is not dual-controlled.

### 5.3 Is a numeric value ratified anywhere in the corpus? **NO — and this is a genuine STOP.**

Searched: all 30 phase-2 migrations, `docs/architecture/`, `docs/architecture/_governance/`,
`docs/phase2/_rulings/`, `docs/phase2/_decisions/`, and the owner rulings file. **`ticket.expiry_grace`
has no value anywhere in the corpus.** `POST_FREEZE_AMENDMENTS.md:648-649` states this in terms:
*"in NO authoritative seed table, NO value anywhere."* Ruling **D2 is PENDING OWNER SIGNATURE**
(`PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:986`) and its approval text (`:797-802`) deliberately says
"set to a value" without naming one.

Per the owner's instruction, **this is the one value that must be stopped on, and only this one.**

**The narrowest possible question the owner must answer — one interval, nothing else:**

> **How long after `catalog.event_session.ends_at` may an unscanned ticket remain `active` before the
> sweep labels it `expired`?**

Everything else — the anchor (`ends_at`), the operator (`+`), the direction, the state transition,
the schedule, the visibility, the type — is already ratified and needs no owner input.

**Bounded decision support (constraints, not an invented answer):**

- **Floor, from the shipped architecture:** `door.session_absolute_max_interval = '24 hours'`
  (`078:1540`) is the ratified outer bound on how long a door session can still operate after a
  show. A grace **≥ 24 hours** guarantees the sweep can never terminal-ize an atom that a still-open
  door episode could have scanned — and `scanned` is the strictly better drain, because it is the
  one that also completes the money. A grace **below 24 hours contradicts a ratified constant** and
  should not be chosen.
- **Also arguing upward:** §4.2 — an expired atom is excluded from `catalog.cancel_event`'s refund
  cascade (`088:1682/1735/1783`), so a short grace narrows the post-hoc cancellation window.
- **Arguing downward:** every hour of grace is an hour a no-show buyer stays undeletable
  (`H_migration_design.md:212-217`), which is the erasure-law exposure the whole item exists to close.
- **Nearest ratified neighbour for "post-session operational grace":**
  `door.session_post_session_grace = '4 hours'` (`078:1541`).

A value in the **24h – 72h** band satisfies both bounds. **Choosing within that band is the owner's
call and is not made here.**

---

## 6. FAIL-CLOSED SHAPE

### 6.1 The two senses of "safe", and why the shipped one is the wrong one for custody

The corpus is internally consistent and deliberate: it chose **fail-INERT** for this consumer,
because `expired` is a *terminal* label and mis-stamping it destroys entitlement
(`079:467-474`, `POST_FREEZE_AMENDMENTS.md:648-653`). That reasoning is sound **for the atom**.

It is **fail-OPEN for the identity.** With the key absent, tickets stay live forever, BP-1 never
clears, and the buyer is permanently undeletable — an erasure-law and App-Store failure
(`H_migration_design.md:212-217`, `D_deletion_refund.md:189-195`).

**Both readings are correct.** They are in tension, and the tension is resolved by *removing the
missing-key state*, not by re-arguing which direction the code should fail in.

### 6.2 The correct fail-closed behaviour — and it CAN be achieved without touching 079/083/085

**079, 083 and 085 are immutable and must not be edited. They do not need to be.**

The sweep's fail-open condition is `v_grace is null` (`079:485`). That condition is **data, not
code.** 093 eliminates it by seeding the row **with a real interval value**, not with
`'null'::jsonb`.

> **This is the one place where 093 should deviate from ruling I-3's stated shape.**
> `H_migration_design.md:186-193` prescribes `value 'null'::jsonb` for all three config keys, and
> `:218-220` separates "093 creates the ROWS, values come later via `set_platform_config`". For the
> other two keys that separation is correct — **they fail closed on their own** (`inventory.hold_ttl_interval`
> raises `hold_ttl_unset` at `081:633-637`; `inventory.per_user_active_hold_max` fails to a zero cap
> at `081:613-626`). `ticket.expiry_grace` is the **opposite** case: a null value *is* the fail-open
> state. Seeding it null creates the row and leaves the bug fully armed.

**Therefore:**

| Key | 093 seeds | Rationale |
|---|---|---|
| `inventory.hold_ttl_interval` | `'null'::jsonb` (per I-3) | consumer already fails closed |
| `inventory.per_user_active_hold_max` | `'null'::jsonb` (per I-3) | consumer already fails closed |
| **`ticket.expiry_grace`** | **a real interval string** | **null IS the fail-open state** |

This requires an owner value before 093 can be authored — which is precisely why §5.3 stops on it.

**Fallback if the owner value is not available in time:** seed the row `'null'::jsonb` per I-3
*and* treat "expiry grace unset" as a **named, dated, monitored launch blocker** gating
`feature.native_issuance_enabled`. That is strictly worse — it moves a code-enforced precondition
into a human process — but it is honest, and it matches D2's approval text ("set to a value **before
the direct rail is activated**", `FINAL_OWNER_RULINGS.md:799-800`). It must not be the silent default.

### 6.3 The SECOND fail-open path, which config alone cannot close

Even with the key correctly set, the sweep skips any session where `ends_at is null`
(`079:492-493`), and E-18 confirms this is deliberate: *"the sweep never guesses one"*
(`POST_FREEZE_AMENDMENTS.md:1515-1516`).

**`ends_at` is optional at session creation.** `catalog.create_event_session` (078) validates only:

- `starts_at` required — `raise exception 'invalid_input: starts_at required'` (`078:806`)
- `ends_at`, if present, must be after `starts_at` (`078:809`)

and the table CHECK explicitly tolerates the null (`event_session_time_check`, `078:195-197`).

**So a venue that creates a session without `ends_at` reproduces the permanent-undeletable bug in
full, with the config key correctly set.** Config cannot reach this; 079 and 078 are immutable.

Three options, **flagged for decision rather than presumed** — none is required for the expiry
derivation itself, and this is a *separate* item from §5.3's value question:

1. **093 tightens the column:** `alter table catalog.event_session alter column ends_at set not null`.
   Safe today — the substrate is dark and holds no rows. But it contradicts 078's deliberate
   nullability and would make the `ends_at is null` arm of `event_session_time_check` dead. This is a
   **schema decision**, so it needs an owner/architecture bit; it is not a silent implementation choice.
2. **093 adds a narrower CHECK** requiring `ends_at` only for sessions of events on the venue-direct
   rail — more surgical, more complex, and needs a rail discriminator that may not exist on the row.
3. **Product-surface requirement only** — the venue dashboard makes `ends_at` mandatory. **Fail-open**
   at the database, and therefore the weakest option; acceptable only with an accompanying monitoring
   query (`select count(*) from catalog.event_session where ends_at is null`) wired to an alert.

**Recommendation: option 1**, raised to the owner alongside the §5.3 value question — but recorded
here as a distinct item, not folded into it.

---

## 7. SUMMARY OF CITATIONS

| Claim | Cite |
|---|---|
| Sweep function | `supabase/migrations/079_kernel_ticket_atom_and_ownership_log.sql:456` |
| Config key string `'ticket.expiry_grace'` | `079:477` |
| Value cast to `interval` (the type witness) | `079:478` |
| Unset/unparseable → `swept_count: 0` | `079:483-486` |
| Derivation `now() > s.ends_at + v_grace` | `079:488-497` |
| `ends_at is not null` guard | `079:492-493` |
| Transition `active → expired` | `079:502-506` |
| Cron `*/2 * * * *` | `079:799-803` |
| BP-1 live-custody blocker | `079:707-717` |
| `catalog.event` — no time columns | `078:134-153` |
| `catalog.event_session` — `starts_at` NOT NULL, `ends_at` nullable | `078:173-197` |
| `catalog.platform_config` shape | `078:217-227` |
| `effective_freeze_at` (freeze at doors) | `078:405-446` |
| `set_platform_config` refuses unknown keys | `078:1103` |
| `ticket.%` not dual-controlled | `078:1145-1147` |
| Interval-key seed precedent | `078:1531-1541` |
| `door.session_absolute_max_interval = 24 hours` | `078:1540` |
| `door.session_post_session_grace = 4 hours` | `078:1541` |
| Mint writes `state='active'`, stamps no expiry | `083:557-560` |
| Routine refund still refunds an expired atom | `085:581-582`, `085:598-599` |
| `cancel_event` EXCLUDES expired atoms from refund | `088:1682`, `088:1735`, `088:1783` |
| Derivation ratified (schema spec) | `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:537-539` |
| Derivation ratified (RPC contracts §12.5) | `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md:2034-2035` |
| E-18: CLASS A, no value anywhere, `ends_at IS NULL` expires nothing | `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:1506-1516`, `:644-651` |
| D2 ruling, unsigned | `docs/phase2/PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:786-802`, `:986` |
| I-3 (093 creates rows) | `docs/phase2/_rulings/H_migration_design.md:186-220` |
| Deletion chain closed but for expiry | `docs/phase2/_decisions/D_deletion_refund.md:189-195`, `:440-443` |
| 093 placement correct, belongs in MUST | `docs/phase2/ADVERSARIAL_ARCHITECTURE_REVIEW.md:147-152` |
