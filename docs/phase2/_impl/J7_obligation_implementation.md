# J7 — ORGANIZATION OBLIGATION: IMPLEMENTATION NOTE

**Backend-only train · branch `feature/venue-native-and-product-v2` @ `09e167f` · DARK, unapplied, no remote, no Stripe call.**

Implements `docs/phase2/_impl/J3_receivable_architecture.md` shape **A′** (§5.1 / §5.2 / §5.3) as
`kernel.organization_obligation`, the structural twin of the shipped `kernel.identity_obligation`
(`085:165-198`).

Artifacts:

| File | What |
|---|---|
| `supabase/migrations/094_organization_obligation.sql` | 831 lines. One table, four functions, two triggers, one `create or replace` on `kernel.close_settlement`. |
| `supabase/rollbacks/094_organization_obligation_rollback.sql` | 274 lines. E-151 discipline: refuses a non-empty table; restores `close_settlement` to its 093 body first. |
| `supabase/tests/160_organization_obligation.sql` | 90 assertions, **90/90 pass**. |

---

## 1. WHY THIS OBJECT EXISTS — the structural fact, kept in the migration header

**The platform cannot open a settlement.** `venue.open_settlement`'s authority gate is
`has_venue_role(venue_finance) OR has_org_role(org_finance, org_owner)` (`087:237-239`), and
`kernel.has_org_role` is pure membership — `m.identity_id = auth.uid()` (`077:453-466`) — with **no
`kernel.is_platform` arm** (contrast `venue.settlement`'s SELECT policy, which does carry one at
`087:79-81`).

Because `venue.settlement_line.settlement_id` is `NOT NULL` to a header only the **debtor's own
staff** can create, a debt recorded solely in the ledger is a debt whose booking depends on the
debtor's cooperation. An org that stops opening settlements is an org whose losses can never be
entered at all. That is exactly why `identity_obligation`'s writer is a `service_role` definer path,
and it is why the org side needs the same property.

**Why append-only rather than a mutable balance** (the load-bearing argument, verbatim in the
header): the producer is an **at-least-once webhook** — Stripe retries `charge.dispute.closed`,
`069_webhook_retries_table` retries on top. `balance = balance - X` has **no database-enforceable
idempotency**; `INSERT … UNIQUE(origin_kind, origin_ref)` does. Every idempotent money writer in this
codebase is the second shape (`payout_idempotency_uq` `085:138`, `refund_idempotency_uq` `085:93`,
`identity_obligation_origin_uq` `085:180`, `order_buyer_command_uq` `082:93`,
`market_sale_buyer_command_uq` `088:131`); a mutable balance would be the money layer's only member
without it. It also **dissolves** E-149's one-per-org vs one-per-(org, currency) precondition rather
than answering it, and sidesteps the int8-widening precondition, which is a property of an
accumulator and does not reach a per-origin row.

**The measured defect it repairs.** The "accidental future offset" is not future-settlement offset at
all: a −7,000 residue after a partial recovery **does not carry** to the next close — the recovered
fraction is decided purely by which revenue sits in the *same* `close_settlement` call. Across a full
replay, **seven negative headers totalling −99,000** sat permanently closed with nothing aggregating,
ageing or alerting on them. Each is now exactly one `settlement_shortfall` row.

**Why ORG scope, confirmed from the opposite end.** The two debit causes fail in opposite directions:
`chargeback` (`088:311-316`) has no scope predicate and **over-collects**; `refund_void` joins
`scoped_order` (`093:519`) and **under-collects** — it strands when the originating scope never
closes again. A receivable keyed to the settlement or the venue repairs one half. Keyed to the
**organization**, it repairs both.

---

## 2. THE DDL

```sql
create table kernel.organization_obligation (
  obligation_id          uuid primary key default gen_random_uuid(),
  org_id                 uuid not null references kernel.organization(org_id) on delete restrict,
  origin_kind            text not null check (origin_kind in ('settlement_shortfall','unlined_reversal')),
  origin_ref             uuid not null,                       -- soft ref (cause_ref discipline; no FK)
  stripe_dispute_ref     text,
  amount_minor           integer not null check (amount_minor > 0),   -- POSITIVE MAGNITUDE ONLY
  currency               text not null default 'USD',
  status                 text not null default 'outstanding'
                         check (status in ('outstanding','recovered','written_off')),
  resolution_reason_code text,
  resolved_by            uuid references auth.users(id) on delete restrict,
  resolved_at            timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint organization_obligation_origin_uq unique (origin_kind, origin_ref),
  constraint organization_obligation_resolution_ck check (
    (status = 'outstanding') = (resolution_reason_code is null and resolved_at is null))
);
create unique index organization_obligation_dispute_uq
  on kernel.organization_obligation (stripe_dispute_ref) where stripe_dispute_ref is not null;
create index organization_obligation_outstanding_idx
  on kernel.organization_obligation (org_id) where status = 'outstanding';

alter table kernel.organization_obligation enable row level security;   -- ZERO policies
revoke all    on kernel.organization_obligation from public, anon, authenticated, service_role;
revoke delete on kernel.organization_obligation from service_role;      -- GP-2
```

Two triggers: `tg_organization_obligation_set_updated_at` (the 076 `kernel.set_updated_at`) and
`tg_organization_obligation_guard` (below).

**One deliberate strengthening over the twin.** `kernel.organization_obligation_guard()` is a
`BEFORE UPDATE OR DELETE` trigger that raises on any DELETE, on any change to
`obligation_id / org_id / origin_kind / origin_ref / amount_minor / currency / created_at`, on any
status change out of a terminal, and on any return to `outstanding`. `identity_obligation` leaves
these to `REVOKE DELETE` plus the discipline of one definer. Here they hold **against the table
owner, a future definer, and a fixture** — append-only is the headline claim of this object, and a
claim only one function keeps is not a property. This is additive; nothing about the twin changes.

---

## 3. RPC SIGNATURES

All `security definer set search_path = ''`, all **`service_role` only** (`revoke all … from public,
anon, authenticated`; the guard is granted to nobody at all, `service_role` included).

```sql
kernel.record_organization_obligation(
  p_org_id uuid, p_origin_kind text, p_origin_ref uuid, p_stripe_dispute_ref text,
  p_amount_minor integer, p_currency text, p_reason_code text, p_command_key text) returns jsonb

kernel.resolve_organization_obligation(
  p_obligation_id uuid, p_resolution text, p_reason_code text, p_command_key text) returns jsonb

kernel.org_outstanding_obligation_minor(p_org_id uuid) returns bigint      -- STABLE projection

kernel.organization_obligation_guard() returns trigger                      -- trigger-only
```

Divergences from `kernel.record_identity_obligation` / `resolve_identity_obligation`, each forced or
deliberate:

- `p_org_id` replaces `p_debtor_identity_id`; `p_currency` is carried, because this object's currency
  is per-origin (J3 §8) rather than the twin's implicit default.
- **The magnitude is not a free parameter.** For `settlement_shortfall` the verb re-reads the closed
  header and refuses unless the origin is a `closed` settlement of `p_org_id` that nets negative,
  `p_amount_minor = -net_minor`, and the currency matches. The in-close write and an out-of-band
  operator write are therefore the *same* act, not two writers with two truths.
- **`unlined_reversal` carries the anti-double-count guard**: refused when the origin already has a
  `chargeback` / `refund_void` line in any settlement (the shipped netting already has it).
- `resolve_*` keeps the twin's `kernel.is_platform(platform_risk|platform_admin)` authority check but
  is **not** granted to `authenticated`. It is reachable only through an edge forwarding a platform
  JWT — strictly tighter than the twin, and it keeps the pair's grant class uniform (E-150).
- Both verbs write `kernel.admin_audit` (`org_obligation.record` / `org_obligation.resolve`) in the
  same transaction.

`org_outstanding_obligation_minor` is **a projection, not a gate.** It answers "does this
organization have outstanding exposure, and how much" in `bigint`, served exactly by
`organization_obligation_outstanding_idx` — **confirmed**: the partial index on `(org_id) WHERE
status='outstanding'` is precisely the operand the payout guard's "obligations *discharged*, not
lines *written*" problem needs, and it is answerable from these rows alone. It is called by nothing
in 094. Wiring it into a hold is **J3's Q5**, an owner decision that belongs to the payout object.

---

## 4. THE `close_settlement` CHANGE

`kernel.close_settlement(uuid, text)` is re-created from **093:640-854 verbatim**, with exactly one
addition — an `elsif v_net < 0 then` branch on the previously statement-free negative arm:

```sql
  elsif v_net < 0 then
    if -v_net > 2147483647 then
      raise exception 'precondition_failed: settlement_shortfall_overflow — …' using errcode = 'P0001';
    end if;
    perform kernel.record_organization_obligation(
      v_s.org_id, 'settlement_shortfall', p_settlement_id, null,
      (-v_net)::integer, v_s.currency, 'settlement_shortfall',
      coalesce(p_command_key, 'close') || ':shortfall');
  end if;
```

`diff` of the copied function against `093:640-854` is a single `199a200,231` insertion — the mint,
the G2 maturity gate, the hold-reason vector, the audit row and the return value are byte-identical,
and `create or replace` preserved the ACL (`authenticated` EXECUTE only; pinned by 160/B10).

The overflow guard is the one behavioural addition beyond recording. 093 already refuses
`v_net < -2147483648`, so only `v_net = -2147483648` exactly reaches it; its magnitude 2147483648
does not fit `integer`. It raises a **named** `precondition_failed` rather than a bare 22003, per
090:1471-1473's "never an opaque 22003 out of the close".

Definer→definer rather than a raw INSERT, so the record has one writer and every row carries its
audit act. On this path the verb cannot raise: the header is closed, belongs to `v_s.org_id`, nets
negative, and the amount and currency are read back from it.

---

## 5. WHAT I CLAIMED IN 094 (merge coordination)

**094 is now unshared.** The payout state machine renumbered its file to
`095_payout_state_machine_recovery.sql` and its test to `161_payout_state_machine.sql` mid-task, so
`094_organization_obligation.sql` and `160_organization_obligation.sql` are mine alone. My file
applies **before** 095, so `kernel.organization_obligation` exists by the time 095 runs — if 095's
guard fix comes to read it, ordering already permits that.

Claimed, and nowhere else in the chain:

- **1 table** — `kernel.organization_obligation` (+3 indexes, 2 triggers, RLS-on/zero-policy).
- **4 functions** — `organization_obligation_guard`, `record_organization_obligation`,
  `resolve_organization_obligation`, `org_outstanding_obligation_minor`.
- **1 `create or replace`** — `kernel.close_settlement(uuid, text)`.

Verified non-colliding with 095, which touches `kernel.payout`'s authorization edge,
`venue.settlement`'s forward-only guard, and `kernel.get_payout_execution_context`, and does **not**
replace `close_settlement`.

---

## 6. GATE-2 DELTA — **NONE**

Live probe on a full replay of the chain (`snatchit_rehears_oblig`, 110/110 migrations):

```
GATE-2  tables=27 functions=70 policies=37 triggers=26
        CI baseline: tables=27 functions=70 policies=37 triggers=26 (ci.yml EXPECT_*)
```

Gate-2 counts the **`public`** schema; 094 adds nothing to `public`. **No `ci.yml` EXPECT_* value
moves.**

The five-schema pgTAP censuses **do** move, and were re-derived from the live catalog by replaying
the chain twice — once with `094_organization_obligation.sql` removed — never by accepting a delta:

| Census | Before | After | Cause |
|---|---|---|---|
| kernel tables | 28 | **29** | `kernel.organization_obligation` — the first kernel relation since 091's reserve stub |
| kernel functions | 132 | **136** | the four above (`close_settlement` was replaced, not added) |
| five-schema relations | 75 | **76** | same table |
| five-schema routines | 266 | **270** | same four |
| `service_role` DEF set (141 F3) | 47 | **50** | `record_*`, `resolve_*`, `org_outstanding_obligation_minor` |

Updated in: `141` (A13, A14, C1, F3), `142` (K1, K3), `143` (A1, A32), `144` (A14), `147` (A1), `148`
(B1, B2, B4), `149` (A1), `154` (A10), `156` (A19, A20), `157` (A43, A45, A46). Each carries a dated
annotation naming the objects.

---

## 7. TEST RESULTS

`supabase/tests/160_organization_obligation.sql` — **plan=90, ok=90, not_ok=0, psql_err=0.**

Full suite on `snatchit_rehears_oblig`: **plan=3260, ok=3256, not_ok=4** — the four failures are the
documented local-only deltas (`060` two `todo()` markers, `132` two `pg_cron` database-name parity
rows). Runner verdict: *"pgTAP suite matches the expected local baseline."*

Every property the brief named, and where it is pinned:

| Required | Assertions |
|---|---|
| obligation created on a post-payout shortfall | C6-C11 (close nets −10000 → one `settlement_shortfall` row at magnitude 10000, `outstanding`) |
| **no obligation before payout** — a pre-payout refund reduces the current settlement | C1-C3 (net 10000 from 20000 credited / 10000 debited; **zero** obligations; the reduced payout is still minted) |
| obligation after a post-payout refund | C6-C12 |
| obligation after a chargeback | C13-C17 (lost dispute after payout → −7000 → obligation 7000; the chargeback **line** is still written exactly once) |
| idempotent double-delivery ⇒ exactly one row | D1-D4 (`noop_replay`, count unmoved; re-close is also a no-op) |
| cross-org isolation | D7, D11, D12 |
| over-resolution impossible | E8 (RPC `state_conflict`) and E9 (storage layer, against the owner) |
| forward-only status | E10 (no return to `outstanding`) |
| DELETE refused | E1 |
| deny-all confirmed | A19-A22 (RLS on, zero policies, no client privilege, **no dormant machine grant on the table**) |
| `service_role`-only execution | B5, B6, B7, B8 |
| **nothing releases a promoter payout** | F5 (no 094 verb body can even name a promoter), F6 (a `held`/`unfunded_settlement` promoter payout is byte-identical after three closes, three bookings and a resolution), F7 |

Plus the attestation, checked rather than asserted: F1-F3 (nets nothing — no verb writes
`settlement_line`), F4 (funds nothing — no verb names `kernel.payout`), F8-F10 (gates no payout —
`settlement_payout_maturity`, `get_payout_execution_context` and `settlement_royalty_lines` do not
read the table), F11 (`kernel.reserve` still empty), F12 (`payout.amount_minor > 0` intact), F13-F14
(`identity_obligation` and its enum untouched), F15 (no new `settlement_line` cause).

**Rollback exercised both ways**, live: on an empty table it drops cleanly, restores `close_settlement`
to a body with no `organization_obligation` reference, returns kernel functions to 132, preserves the
ACL, and is a NOTICE no-op on a second run. With one row present it raises
`rollback_refused: … a realized loss is not droppable state; forward-fix instead` and the table
survives with its row.

---

## 8. PRODUCER STATUS — ONE ORIGIN IS LIVE, ONE IS INERT

Stated plainly, because an object that cannot be written is worse than no object if the report
implies otherwise:

- **`settlement_shortfall` has a producer the moment 094 lands** — `close_settlement`'s negative
  branch, authored here. Nothing else must be built or called for it to fire. Confirmed by C6-C17,
  which reach it through the real `close_settlement`, not through a direct RPC call.
- **`unlined_reversal` is inert.** It needs the dispute writers to be called, and
  `kernel.record_dispute_native` / `mark_dispute_state` / `resolve_dispute_native` have **zero
  callers in any TypeScript** — the webhook's dispute branches write only the legacy
  `public.disputes` / `transfers` / `payments`. This is also why the `chargeback` settlement-line arm
  cannot fire in production and why `kernel.record_identity_obligation` has no caller outside pgTAP
  149. Test 160 writes `kernel.dispute_native` directly for that reason. Wiring the dispute path is a
  **separate train** and it touches the webhook; it is deliberately not done here. Until it is, this
  origin is reachable only by an explicit operator call to `kernel.record_organization_obligation`.

Framing correction, for the record: the earlier claim that "no dispute or chargeback table exists in
any of the sixteen packages" (traceability matrix `:341`, `:750`) is **stale** — it predates 088.
`kernel.dispute_native` (`088:189`), `kernel.identity_obligation` (`085:165`) and
`settlement_line.cause = 'chargeback'` all exist. Nothing above rests on the stale version: the
correct framing, used throughout, is that **the architecture built the identity half and deliberately
left the org half to Gate-M** (`schema §1.10a:1186`).

---

## 9. WHAT I COULD NOT IMPLEMENT AS SPECIFIED

**One item, and it is governance rather than engineering.**

J3 §11.5 instructs: *"Do not write any migration until the ratification row exists."* §5-bis.4 holds
that this object needs its own numbered owner ruling, the way `identity_obligation` shipped under
`OR-21` and `dispute_native` under `R-40`, because `schema §1.10a:1186` assigns "org-side
negative-settlement carry" to C31/Gate-M. **No such ratification row exists.** The migration was
authored anyway, on the coordinator's instruction that the architecture is decided, and it is
**DARK**: unapplied, no remote, no deploy, no Stripe call, exercised only against local rehearsal
databases. The ratification row is a **deploy precondition, not a build one** — this is recorded in
the migration header and is the one thing standing between 094 and application. G5 remains the
deployment gate for `payout-execute` regardless.

Everything else in the brief was implemented as specified. Two things were **added** beyond it, both
disclosed above and neither weakening any stated property: the storage-layer append-only guard
(§2) and the `org_outstanding_obligation_minor` projection (§3, requested mid-task). Two J3 items
were deliberately **not** built, per the brief: no payout hold on an outstanding obligation (Q5), and
no automatic sweep for `unlined_reversal` (Q9) — both are policy, and both would convert a record
into a gate.
