# RULING C — MONEY / LEDGER ACCOUNTING FACTS FOR A VENUE-DIRECT PRIMARY SALE

**Agent:** C · **Mode:** read-only evidence gathering · **Scope:** the shipped Postgres schema only
(`/Users/josetascon/snatchit-consol/supabase/migrations/`), plus
`docs/architecture/_governance/PHASE_2_ARCHITECTURE_FREEZE.md` and
`docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md`.

**Nothing was modified, migrated, applied or authored.** No Stripe-API behaviour is asserted anywhere in
this document; every claim below is a claim about rows, constraints, triggers, grants and function
bodies as they exist in the repository.

All file paths are relative to `/Users/josetascon/snatchit-consol/`. Citations are `file:line`.

---

## 0. THE ONE-PARAGRAPH ANSWER

A venue-direct primary sale, today, produces **no ledger fact of any kind**. It produces a
`venue."order"` row moved to `status='paid'`
(`supabase/migrations/085_kernel_money_native.sql:2056`), a `kernel.payment_native` link row
(`085:2060-2061`), ticket atoms, and — if a promoter code was presented — a `venue.attribution` row.
It produces **zero** `venue.settlement_line` rows, **zero** `venue.settlement` rows, and **zero**
`kernel.payout` rows. There is exactly **one** `INSERT INTO venue.settlement_line` in the entire
repository (`supabase/migrations/087_venue_settlement_and_export.sql:318`), it is fed by exactly two
seams, and **neither seam can emit a `primary_sale` candidate**. Consequently the database cannot
answer "how much do we owe venue X" — not approximately, not expensively, not at all — because the
obligation has no row. The `cause` value `'primary_sale'` is legal in the enum and has been since
`087:96`; it has never been written.

---

## 1. LEDGER SHAPE

### 1.1 The complete ledger/settlement table inventory

Seven money-bearing tables exist across `kernel.*` and `venue.*` in packages 076–092, plus the frozen
legacy `public.payments`. There is no double-entry ledger anywhere: no journal table, no account table,
no balancing constraint across tables.

| Table | File:line | Mutability |
|---|---|---|
| `kernel.payment_native` | `085:40-60` | **Append-only** (trigger `085:64-66`) |
| `kernel.refund` | `085:74-95` | Mutable (`status`, `stripe_refund_ref` via one RPC) |
| `kernel.payout` | `085:111-147` | Mutable (status + hold overlay via four RPCs) |
| `kernel.identity_obligation` | `085:165-184` | Mutable (`status` resolution only); `DELETE` revoked from `service_role` (`085:198`) |
| `venue.settlement` | `087:44-67` | Mutable header; four money columns write-once by construction |
| `venue.settlement_line` | `087:92-106` | **Append-only** (trigger `087:111-112`; `revoke update, delete ... from service_role` at `087:115`) |
| `kernel.reserve` | `091:29-36` | Empty by contract — "ALWAYS EMPTY and ALWAYS DROPPABLE; nothing may be added to it" (`091:13-15`) |
| `market.market_sale` (resale rail, for contrast) | `088:110-141` | Mutable |
| `public.payments` (frozen legacy) | `000_baseline_schema.sql:971-999` | Mutable |

### 1.2 `venue.settlement` — the money rollup header (`087:44-67`)

```
settlement_id uuid PK · org_id → kernel.organization · venue_id → catalog.venue
event_id → catalog.event (NULLABLE — period settlement) · period_start · period_end
status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed','paid'))
gross_minor integer · fees_minor integer · refunds_minor integer · net_minor integer   -- all NULLABLE
currency text NOT NULL DEFAULT 'USD'
created_at · updated_at
constraint settlement_waterfall_ck check (
  status = 'open'
  or (gross_minor is not null and fees_minor is not null
      and refunds_minor is not null and net_minor is not null
      and net_minor = gross_minor - fees_minor - refunds_minor))          -- 087:61-66
```

Indexes: `settlement_org_status_idx (org_id, status)` `087:68`; `settlement_event_idx (event_id)`
`087:69`. **There is NO unique constraint of any kind on `venue.settlement`.** Nothing prevents two
concurrently-open settlements over the same `(org_id, venue_id, event_id)` or over overlapping periods.
This matters for §7 (a `primary_sale` line could be claimed by two settlements — see §3.3).

`status='paid'` is written by exactly one function, `venue.on_payout_settled` (`087:360-397`, the write
at `087:377`).

### 1.3 `venue.settlement_line` — the immutable money lines (`087:92-106`)

```
id uuid PK
settlement_id uuid NOT NULL → venue.settlement
cause text NOT NULL CHECK (cause IN (...))          -- verbatim enum below
cause_ref uuid NOT NULL                              -- NO foreign key
amount_minor integer NOT NULL                        -- SIGNED: credits +, debits −
currency text NOT NULL DEFAULT 'USD'
is_rounding_bearer boolean NOT NULL DEFAULT false
occurred_at timestamptz                              -- NULLABLE, never written by the sole writer
created_at timestamptz NOT NULL DEFAULT now()
constraint settlement_line_cause_uq unique (settlement_id, cause, cause_ref)   -- 087:105
```

**The `cause` enum, verbatim (`087:95-98`):**

```sql
cause              text not null check (cause in (
                     'issue','primary_sale','comp','door_sale','p2p_transfer','market_sale',
                     'auction_sale','admin_action','refund_void','import','promoter_commission',
                     'settlement','chargeback')),   -- D3 closed set (schema §0.5)
```

Thirteen members. **`'primary_sale'` is member #2 and has been legal since the table was created.**
`'door_sale'`, `'issue'`, `'comp'`, `'import'` and `'refund_void'` are likewise legal and likewise
never written.

Indexes: `settlement_line_settlement_idx (settlement_id)` `087:107`;
`settlement_line_cause_ref_idx (cause_ref)` `087:108`. One partial unique index is added later:

```sql
create unique index if not exists attribution_one_commission_line_ever
  on venue.settlement_line (cause_ref) where cause = 'promoter_commission';   -- 090:214-215
```

That is the *only* cross-settlement uniqueness guarantee on the line table. There is **no analogous
index for `primary_sale`** (nor for any other cause).

Append-only enforcement: `087:110-112` fires `kernel.raise_append_only()` (`076:137-148`) on
`before update or delete`, and `087:115` revokes `update, delete` from `service_role`. **`INSERT` is
not revoked from `service_role`** (`087:114` revokes all from `anon, authenticated` only; `087:116`
grants `select` to `authenticated`).

### 1.4 `kernel.payout` (`085:111-147`)

**`cause` enum, verbatim (`085:120-121`):**

```sql
  cause              text not null check (cause in
                       ('settlement','market_sale','promoter_commission','refund_void')),
```

**`status` enum, verbatim (`085:125-126`):**

```sql
  status             text not null default 'pending'
                     check (status in ('pending','submitted','paid','failed','reversed')),
```

**`hold_state` enum, verbatim (`085:128-129`):**

```sql
  hold_state         text not null default 'none'
                     check (hold_state in ('none','held','probation_hold')),
```

**`hold_reason_code` is NOT an enum.** It is `hold_reason_code text` (`085:130`) — free text, no
CHECK, no domain, no reference table. The only values any shipped writer produces are
`'unfunded_settlement'` (`090:1486`), `'destination_probation'` (`087:489`), `'dispute'` (`088:846`),
and whatever caller-supplied string `kernel.hold_payout` receives (`085:769`, validated only as
non-blank at `085:782-784`).

Other columns and constraints:

```
payout_id uuid PK
payee_kind text NOT NULL CHECK (payee_kind IN ('organization','identity'))          -- 085:113
payee_org_id uuid → kernel.organization · payee_identity_id uuid → auth.users        -- 085:114-115
cause_ref uuid NOT NULL   -- "deliberately NO FK (cross-schema pointer, no cycle)"   -- 085:122
amount_minor integer NOT NULL CHECK (amount_minor > 0)                               -- 085:123
currency text NOT NULL DEFAULT 'USD'                                                 -- 085:124
held_by uuid → auth.users · held_at timestamptz                                      -- 085:131-132
stripe_transfer_ref text   -- write-once, mark_payout_transfer_state only            -- 085:133
source_transaction_ref text   -- NEVER WRITTEN BY ANY SHIPPED FUNCTION               -- 085:134
idempotency_key text NOT NULL
constraint payout_idempotency_uq unique (idempotency_key)                            -- 085:138
constraint payout_payee_xor_ck   (org XOR identity, keyed on payee_kind)             -- 085:139-142
constraint payout_hold_pairing_ck ((hold_state='none') = (reason IS NULL AND held_at IS NULL))  -- 085:143-145
constraint payout_held_by_ck (held_by is null or hold_state = 'held')                -- 085:146
```

`'held'` is deliberately **not** a `status` member: "the hold is the four-column overlay" (`085:109`).

RLS: enabled `085:159`, `revoke all ... from anon, authenticated` `085:160`, **zero policies**. Client
reads go through `kernel.list_org_payouts` (`085:1439`).

### 1.5 `kernel.refund` (`085:74-95`)

`reason_code` closed set, verbatim (`085:77-80`):

```sql
  reason_code       text not null check (reason_code in
                      ('buyer_request','event_cancelled','oversell_correction',
                       'dispute','admin_action','auto_compensation')),
```

`status` closed set (`085:84-85`): `('pending','submitted','succeeded','failed')`.
`amount_minor integer NOT NULL CHECK (amount_minor > 0)` (`085:80`).
`constraint refund_idempotency_uq unique (idempotency_key)` (`085:93`).
`constraint refund_ref_pairing_ck check (status = 'pending' or stripe_refund_ref is not null)`
(`085:94`) — makes "failed with no Stripe reference" unstorable.
Partial unique on the Stripe ref: `085:96-97`.

### 1.6 `kernel.identity_obligation` (`085:165-184`) — the OR-21 receivable

```
debtor_identity_id uuid NOT NULL → auth.users(id)          -- 085:167  ← IDENTITIES ONLY
origin_kind text NOT NULL CHECK (origin_kind IN ('chargeback','refund_clawback'))   -- 085:168
origin_ref uuid NOT NULL   -- soft ref
stripe_dispute_ref text
amount_minor integer NOT NULL CHECK (amount_minor > 0)     -- 085:171
status text NOT NULL DEFAULT 'outstanding'
       CHECK (status IN ('outstanding','recovered','written_off'))   -- 085:173-174
constraint identity_obligation_origin_uq unique (origin_kind, origin_ref)   -- 085:180
constraint identity_obligation_resolution_ck ...                            -- 085:181-183
```

**Decisive:** the debtor column is `uuid NOT NULL REFERENCES auth.users(id)`. An **organization can
never be a party to this table** — neither as debtor nor as creditor. This is a platform receivable
*from a person*, not an obligation *to a venue*.

### 1.7 `kernel.reserve` (`091:29-36`)

The only org-scoped balance shape in the schema: `reserve_id`, `org_id → kernel.organization`,
`balance_minor integer NOT NULL DEFAULT 0` (no CHECK — deliberately, so a Gate-M receivable posture is
not pre-empted, `091:21-22`), `currency`, timestamps. RLS on, **zero policies**, and
`revoke all ... from public, anon, authenticated, service_role` (`091:45`). 091's own header states it
is "ALWAYS EMPTY and ALWAYS DROPPABLE; nothing may be added to it" (`091:13-15`) and that it has
"no function, no RPC, no policy, no writer, no reserve math, no clawback, no double-entry ledger"
(`091:9-12`).

---

## 2. WHAT WRITES MONEY TODAY

### 2.1 Writers of `venue.settlement_line` — exactly ONE

| # | Writer | file:line | Caller outside pgTAP? |
|---|---|---|---|
| 1 | `kernel.close_settlement` | **`087:318-320`** | **NO** |

Verified by exhaustive grep over `supabase/**/*.sql` for `into venue.settlement_line`: a single hit
(`087:318`). Its rows come only from the union of two seams (`087:311-312`):

- `kernel.settlement_royalty_lines(p_settlement_id)` — stub at `087:205-209` (zero rows); real body
  `088:319-364`. Emits `cause='market_sale'` (positive, `088:337-350`) and `cause='chargeback'`
  (negative, `088:351-359`) **only**.
- `kernel.settlement_commission_lines(p_settlement_id)` — stub at `087:211-215` (zero rows); real body
  `090:1511-1553`. Emits `cause='promoter_commission'` (negative, `090:1549-1553`) **only**.

Therefore the reachable `cause` set of the entire line ledger is
**{`market_sale`, `chargeback`, `promoter_commission`}** — three of thirteen.

### 2.2 Writers of `kernel.payout` — exactly TWO

| # | Writer | file:line | `cause` written | Caller outside pgTAP? |
|---|---|---|---|---|
| 1 | `kernel.close_settlement` | **`087:341-345`** | `'settlement'`, `payee_kind='organization'`, `payee_org_id = settlement.org_id`, `amount = net_minor`, `idempotency_key = 'settlement:'||settlement_id` | **NO** |
| 2 | `kernel.pay_promoter_commission` | **`090:1483-1488`** | `'promoter_commission'`, `payee_kind='identity'`, minted **already held** (`hold_state='held'`, `hold_reason_code='unfunded_settlement'`, `held_by=NULL`, `held_at=now()`), `idempotency_key = 'promoter_commission:'||attribution_id||':'||identity_id` | **NO** |

The `payout.cause` members `'market_sale'` and `'refund_void'` have **no writer at all** — grep for
`into kernel.payout` returns only `087:341` and `090:1483`.

`close_settlement` mints a payout only when `v_net > 0` (`087:340`).

### 2.3 Mutators of `kernel.payout` (state, not creation)

| Function | file:line | Writes | Caller outside pgTAP? |
|---|---|---|---|
| `kernel.request_org_payout` | `087:408` | `pending → submitted` (`087:514`, `087:568`); `hold_state → 'probation_hold'` (`087:488-490`) | **NO** |
| `kernel.mark_payout_transfer_state` | `085:1668` | `submitted → paid|failed`; `paid → reversed` (`085:1717-1721`); write-once `stripe_transfer_ref` | **NO** (grants at `085:2129-2160`; service_role only, no edge function calls it) |
| `kernel.hold_payout` | `085:769` | `hold_state → 'held'` (`085:795-798`) | **NO** |
| `kernel.release_payout` | `085:807` | `hold_state → 'none'` (`085:829-832`) — the sole release path | **NO** |
| `kernel.record_dispute_native` (dispute freeze leg) | `088:839-852` | `hold_state → 'held'`, `hold_reason_code='dispute'` (`088:846-847`) | **NO** |

### 2.4 Writers of `kernel.refund` — one primary, one break-glass

| Function | file:line | Caller outside pgTAP? |
|---|---|---|
| `kernel.refund_primary_order` | INSERT at `085:598-599` | **NO** |
| `kernel.admin_refund` | `085:629` | **NO** |
| `kernel.mark_refund_state` (status sync only) | `085:1737` | **NO** |

### 2.5 Writers of `kernel.identity_obligation`

`kernel.record_identity_obligation` (`085:1793`; INSERT at `085:1819-1822`) and
`kernel.resolve_identity_obligation` (`085:1836`; UPDATE at `085:1864-1868`).
Grep across `supabase/functions/**`, `src/**`, `web/**`: **no caller.** Only
`supabase/tests/149_phase2_kernel_money_native.sql:580-592` and
`supabase/tests/141_phase2_identity_orgs_deletion.sql:280,319`.

### 2.6 The universal finding on callers

```
grep -rn "close_settlement|open_settlement|request_org_payout|pay_promoter_commission|
          finalize_primary_order|mark_payout_transfer_state|settlement_commission_lines|
          settlement_royalty_lines"  --include=*.ts --include=*.tsx --include=*.js --include=*.json
```

returns **two hits, both comments** in `src/lib/venue/client.ts:280` and `src/lib/venue/client.ts:288`.
There are **zero edge-function callers** (`supabase/functions/` contains `_shared`,
`auto-finalize-auctions`, `confirm-and-release`, `confirm-payment`, `create-connect-account`,
`create-payment-intent`, `delete-account`, `enforce-transfer-expiry`, `notify-report`,
`notify-transfer`, `send-push`, `stripe-webhook` — none references any Phase-2 money RPC).
There are **zero cron callers** of any settlement/payout function: the cron rows in the money packages
are `sweep-expired-refund-requests` (`085:2180`), the three CRM export ticks (`087:1518,1519,1531`)
and the two market sweeps (`088:1876,1878`).

**Conclusion for §2: every money-writing function in packages 085/087/088/090 is currently reachable
only from pgTAP tests.** The whole rail is dark, exactly as
`docs/architecture/_governance/PHASE_2_ARCHITECTURE_FREEZE.md:73-76` describes ("Gate-M gates
native-resale activation, seller disbursement, clawback and the ledger family; the 15.A flag gate …
gates `feature.native_issuance_enabled`"; the flag itself is seeded `false` at `078:1522`).

---

## 3. THE PRIMARY-SALE GAP

### 3.1 The finding

**There is no writer of a positive `primary_sale`-shaped settlement line, and no code path by which one
could be produced.** The enum member exists (`087:96`); the sole INSERT exists (`087:318`); the two
seams that feed it emit only `market_sale`, `chargeback` and `promoter_commission` (§2.1). The gap is
not a missing constant or a disabled branch — the *candidate producer does not exist*.

### 3.2 What is missing, precisely

1. **A candidate producer.** `kernel.close_settlement` collects candidates from exactly two
   `SETOF kernel.settlement_line_candidate` functions, named literally at `087:311-312`. Adding a
   `primary_sale` candidate requires either a third seam (a `close_settlement` body change) or
   widening one of the two existing seam bodies. The composite type is
   `kernel.settlement_line_candidate (cause text, cause_ref uuid, amount_minor bigint, currency text,
   payee_kind text, payee_id uuid)` (`087:26-33`).
2. **A split representation on the order.** `venue."order"` carries **`total_minor` and nothing else**
   (`082:83`). There are **no fee columns**: no `platform_fee_minor`, no `venue_proceeds_minor`, no
   `face_minor`. `venue.order_item` carries `unit_price_minor` (`082:169`) and `quantity` (`082:168`)
   — the face subtotal, nothing more. Compare `market.market_sale`, which *does* carry the three-way
   split with a summing CHECK (`088:118-120`, `088:134-138`). **The primary rail has no equivalent.**
3. **A platform-fee policy operand.** Grep over `078_catalog_reference_data_and_flags.sql:1544-1556`
   for every seeded money key: eight `refund.*` keys and four `payout.*` keys. **There is no primary
   ticketing fee key of any spelling.** The resale equivalent is explicitly parked fail-closed by
   PFA-30 (`POST_FREEZE_AMENDMENTS.md:2323-2353`): "Do NOT invent a platform fee rate/key/value, a
   royalty basis or percentage, a rounding bearer, fallback percentages, an implicit zero fee or zero
   royalty."
4. **A cross-settlement uniqueness guarantee.** `settlement_line_cause_uq` is scoped
   `(settlement_id, cause, cause_ref)` (`087:105`) — one line per cause **per settlement**. Since
   `venue.settlement` carries no uniqueness at all (§1.2), the same order could be lined into two
   settlements and paid twice. The promoter engine had to add
   `attribution_one_commission_line_ever` (`090:214-215`) precisely to close this hole for
   commissions; **no such index exists for `primary_sale`**.
5. **A refund/chargeback reversal path on the primary side.** `cause='refund_void'` is in the enum
   (`087:97`) and is bucketed into `refunds_minor` by `close_settlement` (`087:331`), but
   `kernel.refund_primary_order` writes only `kernel.refund` and the order status (`085:598-606`) —
   it lines nothing. `cause='chargeback'` *does* have a producer for primary orders (`088:351-359`,
   joining `payment_native.order_id → venue."order".org_id`), so a chargeback would post a negative
   line against a gross that is structurally zero.

### 3.3 The minimum row shape (evidence, not a proposal)

For the accounting to close, the row that must exist and does not is:

```
venue.settlement_line(
  settlement_id = <the org/venue/event settlement>,
  cause         = 'primary_sale',                 -- legal since 087:96, never written
  cause_ref     = venue."order".order_id,         -- see 3.4: 088 already assumes this
  amount_minor  = + <the amount the venue is owed for that order>,   -- signed, credits positive (087:100, 087:326-333)
  currency      = <settlement.currency>,          -- must equal the header or close_settlement raises (087:323-325)
  occurred_at   = <order paid_at>                 -- column exists (087:103), never written by 087:318
)
```

with `amount_minor` derived from a split that **has no storage location today**. Because
`close_settlement` derives its buckets purely from the sign convention (`087:326-333`), a
`primary_sale` line entered *net of platform fee* lands entirely in `gross_minor` and reports
`fees_minor = 0`; entering the gross plus a separate negative fee line requires a `cause` for the fee,
and **no fee-shaped cause member exists** in `087:95-98` (`'admin_action'` is the only unallocated
label, and it is a break-glass label, not a fee label).

### 3.4 Corroborating evidence that `cause_ref = order_id` is the intended shape

`kernel.record_dispute_native`'s payout-freeze leg already queries for it:

```sql
-- 088:842-844
or po.cause_ref in (select sl.settlement_id from venue.settlement_line sl
                     where sl.cause_ref = coalesce(v_pn.order_id, v_pn.sale_id))
```

This subquery looks up settlement lines whose `cause_ref` equals a **primary order id**. No such row is
ever written, so **for a primary order the dispute payout-freeze leg is dead code**: a chargeback on a
venue-direct ticket cannot freeze the org's settlement payout, because the join that would find it
depends on a `settlement_line` row nothing creates.

---

## 4. OBLIGATION ACCOUNTING — WHAT THE DATABASE RECORDS WHEN A BUYER PAYS

### 4.1 The full trace, buyer money → last row written

| Step | Function | Rows written | file:line |
|---|---|---|---|
| 1 | `venue.create_primary_checkout` | `venue."order"` (`status='pending'`, `total_minor`), `venue.order_item` (`unit_price_minor`, `quantity`) | `082:305`, INSERT at `082:437` |
| 2 | *(Stripe collection — out of scope; a `public.payments` row must exist)* | `public.payments` | `000_baseline_schema.sql:971-999` |
| 3 | `venue.finalize_primary_order` | `venue."order".status → 'paid'` | **`085:2056`** |
| 3a | " | `kernel.payment_native (payment_id, order_id, amount_minor, instrument_fingerprint)` | **`085:2060-2061`** |
| 3b | " | ticket atoms + ownership log via `kernel.issue_ticket_atoms` | `085:2045-2052` |
| 3c | " | `venue.attribution` (only if a promoter code/link was bound) | `090:1131-1135` via `085:2065` |

**That is the complete list.** No `venue.settlement` row. No `venue.settlement_line` row. No
`kernel.payout` row. No obligation row of any kind.

Evidence that step 3 is exhaustive: `venue.finalize_primary_order` runs `085:1881-1946` (guards),
`085:1941-2044` (locks, signing key, inventory), `085:2056` (order → paid), `085:2060-2061`
(`payment_native`), `085:2065` (`resolve_order_attribution`), `085:2067` (return). There is no other
INSERT/UPDATE in the body.

### 4.2 Does an obligation to the venue exist as a row anywhere?

**No.** Exhaustively:

- `venue.settlement_line` — the only place a venue credit could live. Reachable causes:
  `{market_sale, chargeback, promoter_commission}` (§2.1). None of them is a primary sale.
- `venue.settlement.gross_minor / net_minor` — derived from lines (`087:329-333`). Zero lines ⇒ zero
  gross. Also NULL until a close.
- `kernel.payout` — only two writers, neither triggered by a primary sale (§2.2).
- `kernel.identity_obligation` — `debtor_identity_id → auth.users` (`085:167`). Cannot name an
  organization, and models a debt *to* the platform, not *from* it.
- `kernel.reserve` — org-scoped `balance_minor` (`091:32`) but zero writers, zero grants, contractually
  always empty (`091:13-15`).
- `kernel.organization` — carries `stripe_connect_account_ref`, `payout_destination_locked_until`,
  `payout_destination_set_by` (`077:114-118`). No balance, no receivable, no payable.
- `venue."order"` — `total_minor` only (`082:83`), with no party-share decomposition.
- `venue.attribution` — carries `basis_minor` and `credited_amount_minor` (`090:176-177`), i.e. the
  face subtotal and the promoter's commission. This is the **only** per-order money decomposition
  anywhere in the venue rail, it exists **only for promoter-attributed orders**, and it is a promoter
  entitlement, not a venue obligation.

### 4.3 Can the system answer "how much do we owe venue X"?

**No.** The best available approximation is
`SELECT sum(total_minor) FROM venue."order" WHERE org_id = X AND status IN ('paid','partially_refunded')`,
which is:

- **gross, not net** — no fee split exists to subtract (§3.2 item 2);
- **not refund-adjusted at the money level** — `kernel.refund` rows are keyed on `payment_id`
  (`085:76`), and `venue."order".status` only records `'partially_refunded'` without the amount
  (`082:79-80`); the partial amount lives in `kernel.refund.amount_minor` and must be joined through
  `kernel.payment_native`;
- **not chargeback-adjusted** — `kernel.dispute_native` (`088:189-213`) links to `public.payments`, and
  its settlement effect (`088:351-359`) posts against a settlement that has no offsetting gross;
- **not commission-adjusted** — `venue.attribution.credited_amount_minor` is an org debit that is only
  materialised at settlement close, and 090 mints those payouts already-held because the funding source
  does not exist (`090:1483-1488`; `POST_FREEZE_AMENDMENTS.md` E-138);
- **not a ledger fact** — it cannot be reconciled, audited, frozen, disputed against, or paid from,
  because it is a query result, not a row.

The owner ruling of 2026-09-02 (`POST_FREEZE_AMENDMENTS.md`, E-138 / `COMMISSION_FUNDING_SOURCE`) has
already made this a *committed* obligation: OPTION B funds promoter commissions "FROM PRIMARY TICKET
REVENUE THROUGH THE VENUE SETTLEMENT ACCOUNTING MODEL (primary ticket revenue → promoter commission
liability → venue distributable settlement)", and the amendment records "IMPLEMENTATION: OPEN … Until
that leg is implemented, tested and authorized, every commission payout is minted and REMAINS HELD
`unfunded_settlement`." **The primary-sale settlement line is that missing leg.**

---

## 5. MONEY SAFETY INVARIANTS ALREADY ENFORCED

These are the structures a future migration must not weaken. They are the reason the gap is a gap and
not a leak.

### 5.1 Idempotency keys (unique, database-enforced)

```sql
constraint order_buyer_command_uq unique (buyer_id, command_idempotency_key)   -- 082:93  (C16)
constraint payment_native_payment_uq unique (payment_id)                        -- 085:56
constraint refund_idempotency_uq unique (idempotency_key)                       -- 085:93
constraint payout_idempotency_uq unique (idempotency_key)                       -- 085:138
constraint identity_obligation_origin_uq unique (origin_kind, origin_ref)       -- 085:180
constraint export_job_command_uq unique (requested_by, command_key)             -- 087:167
constraint market_sale_buyer_command_uq unique (buyer_id, command_idempotency_key)  -- 088:131
```

Deterministic key construction at the two payout writers:
`'settlement:' || p_settlement_id::text` (`087:343`) and
`'promoter_commission:' || v_a.id::text || ':' || v_p.identity_id::text` (`090:1482`).
`close_settlement` has no key column on `venue.settlement`, so `open_settlement` rides the audit row
plus a transaction advisory lock instead (`087:245-256`).

### 5.2 Partial unique indexes

```sql
create unique index if not exists refund_stripe_ref_uq
  on kernel.refund (stripe_refund_ref) where stripe_refund_ref is not null;          -- 085:96-97
create unique index if not exists identity_obligation_dispute_uq
  on kernel.identity_obligation (stripe_dispute_ref) where stripe_dispute_ref is not null;  -- 085:185-186
create unique index if not exists organization_connect_ref_key
  on kernel.organization (stripe_connect_account_ref) where stripe_connect_account_ref is not null;  -- 077:125-126
create unique index if not exists attribution_one_commission_line_ever
  on venue.settlement_line (cause_ref) where cause = 'promoter_commission';          -- 090:214-215
create unique index if not exists market_sale_payment_uq
  on market.market_sale (payment_id) where payment_id is not null;                   -- 088:153
```

### 5.3 Write-once / append-only triggers

- `kernel.raise_append_only()` (`076:137-148`) raises `append_only: % is immutable — % is not
  permitted` with SQLSTATE `P0001` on any UPDATE or DELETE. Attached to `kernel.payment_native`
  (`085:64-66`) and `venue.settlement_line` (`087:110-112`), among others.
- `venue.guard_order_item_immutable()` (`082:180-217`): "once the parent order is paid (or beyond), the
  purchase snapshot is frozen — no UPDATE/DELETE", including a defensive INSERT arm (`082:216`). The
  price snapshot behind any future primary_sale line is therefore already immutable.
- `venue.guard_order_candidate_freeze()` (`082:107-126`): attribution candidates freeze when the order
  leaves `pending`.
- Write-once by function logic, not trigger: `kernel.payout.stripe_transfer_ref`
  (`085:1712-1716`, "conflict_locked: stripe_transfer_ref is write-once"); the four
  `venue.settlement` money columns, written exactly once in the `open→closed` transaction
  (`087:334-337`) and never rewritten (a re-close short-circuits at `087:305-309`).
- `revoke delete on kernel.identity_obligation from service_role` (`085:198`) — "GP-2: no DELETE ever".
- `revoke update, delete on venue.settlement_line from service_role` (`087:115`);
  `revoke update, delete on kernel.org_contact_consent_event from service_role` (`082:297`).

### 5.4 Non-negative / positivity checks

```sql
amount_minor integer not null check (amount_minor > 0)        -- 085:47  payment_native
amount_minor integer not null check (amount_minor > 0)        -- 085:80  refund
amount_minor integer not null check (amount_minor > 0)        -- 085:123 payout
amount_minor integer not null check (amount_minor > 0)        -- 085:171 identity_obligation
total_minor integer not null check (total_minor > 0)          -- 082:83  order
unit_price_minor integer not null check (unit_price_minor > 0)-- 082:169 order_item
quantity integer not null check (quantity > 0)                -- 082:168 order_item
basis_minor integer not null check (basis_minor >= 0)         -- 090:176 attribution
credited_amount_minor integer not null check (credited_amount_minor >= 0)  -- 090:177
amount_minor integer not null check (amount_minor >= 0)       -- 088:195 dispute_native
```

`venue.settlement_line.amount_minor` is deliberately **unconstrained in sign** (`087:100`, `-- signed`)
— that is the ledger's whole convention. `kernel.reserve.balance_minor` is deliberately
unconstrained (`091:32`, rationale `091:21-22`).

The positivity check on `kernel.payout.amount_minor` is what makes `close_settlement` silently mint
**no payout** at `net_minor <= 0` (`087:340`) — the mechanism by which an org's commission debit is
recorded but never collected (`POST_FREEZE_AMENDMENTS.md` E-138).

### 5.5 Currency handling and conservation

- Every money table carries `currency text NOT NULL DEFAULT 'USD'` (`082:85`, `082:174`, `085:48`,
  `085:82`, `085:124`, `085:173`, `087:56`, `087:101`, `088:116`, `090:178`, `091:33`).
- **There is no CHECK constraint on any `currency` column anywhere** — no ISO-4217 validation, no
  reference table, no domain. `'usd'`, `'US$'`, `''` are all storable.
- Cross-row currency consistency is enforced **only inside `close_settlement`**, twice: a candidate in
  a foreign currency raises (`087:314-317`), and a post-insert scan raises if any line diverges from
  the header (`087:323-325`). `kernel.pay_promoter_commission` holds rather than raises on mismatch
  (`090:1455-1457`).
- **Conservation identity**: `settlement_waterfall_ck` (`087:61-66`) makes
  `net = gross − fees − refunds` unstorable if violated, and the derivation at `087:329-333` is
  constructed so that `net_minor = Σ(all lines)` exactly. The header equals the sum of its lines —
  **within a settlement**. There is no equivalent identity across settlements, across orders, or
  between `public.payments` and any `kernel.*` table.
- **Minor units**: all amounts are integer minor units. `public.payments` uses `int` in cents
  (`000_baseline_schema.sql:977` — "stored in cents for precision"). Every Phase-2 column is
  `integer`, i.e. capped at 2,147,483,647 minor units ≈ **$21.47M**. `close_settlement` accumulates in
  `bigint` then casts down (`087:335-336`, `v_gross::integer`), so a settlement above that ceiling
  aborts with `22003` mid-close. `kernel.settlement_line_candidate.amount_minor` is `bigint`
  (`087:29`) while the column is `integer` (`087:100`) — an acknowledged width divergence
  (`087:19-21`); `pay_promoter_commission` guards it explicitly with an
  `amount_overflow` hold at `090:1475-1477`.

### 5.6 Authority and separation-of-duties invariants on the payout path

- `kernel.request_org_payout` (`087:408`) enforces, in order: `org_owner|org_finance` role
  (`087:414-416`); settlement scope binds to the org **under the lock** (`087:417-420`); settlement
  not open (`087:421-423`); SoD-1 — the destination setter may not request a payout (`087:426-428`);
  money-role maturity (`087:429-431`); step-up — `step_up_unavailable` when the JWT carries no `aal`
  claim, `step_up_required` when it is not `aal2` (`087:433-440`); destination cool-down
  (`087:441-443`); **no destination bound ⇒ `no_payout_destination`** (`087:444-446`).
- `kernel.set_org_payout_destination` (`085:1601`) is `org_owner` only, SoD-1 excludes `org_finance`
  (`085:1618-1620`), demands `aal2` (`085:1624-1631`), and validates the ref shape
  `'^acct_[A-Za-z0-9]+$'` (`085:1632-1634`).
- `kernel.mark_payout_transfer_state` refuses `'submitted'` (`085:1683-1685`), refuses a held payout
  entirely (`085:1694-1696`), and is forward-only (`085:1703-1707`).
- `kernel.pay_promoter_commission` asserts its own call stack — it is unreachable except from
  `kernel.close_settlement` via `kernel.settlement_commission_lines` (`090:1412-1415`).
- Every money threshold key is seeded `NULL` (`078:1544-1556`) and every reader treats NULL as
  fail-closed / park-to-strictest (e.g. `087:522-524`, `085:544-553`).

---

## 6. REQUIRED ACCOUNTING FACTS UNDER EACH MERCHANT-OF-RECORD MODEL

### 6.0 A blocker common to all three models

`kernel.payment_native.payment_id` is `uuid NOT NULL REFERENCES public.payments(id)` (`085:42`), and
`venue.finalize_primary_order` refuses to mint unless a `public.payments` row exists, is `succeeded`,
belongs to the buyer, and covers the order (`085:1919-1934`). But `public.payments` is the *resale*
charge table:

```sql
listing_id  uuid  not null references public.listings(id),   -- 000_baseline_schema.sql:973
seller_id   uuid  not null references auth.users(id),        -- 000_baseline_schema.sql:975
mode        text  not null check (mode in ('buy_now','auction')),   -- 000_baseline_schema.sql:993
```

**A venue-direct primary sale has no `public.listings` row and no natural `seller_id`.** Every model
below must first resolve this: either `public.payments.listing_id`/`seller_id`/`mode` are relaxed, or a
primary-side payment table is introduced and `kernel.payment_native.payment_id` is re-pointed. This is
a schema change to a **frozen `public.*` table** and is orthogonal to the merchant-of-record choice —
it must be priced into all three options. (`085:12-13` records the standing rule "NEVER re-charge;
OBS-1: zero changes to `public.*`".)

### 6.1 Model A — Snatch It is merchant of record; separate charges and transfers; venue paid by transfer at settlement

This is the model the shipped schema was built for. It is by a wide margin the smallest delta.

**Sufficient as-is (no change):**

| Fact | Existing structure |
|---|---|
| The venue credit line | `venue.settlement_line.cause='primary_sale'` — enum member already legal, `087:96` |
| The rollup and its conservation identity | `venue.settlement` + `settlement_waterfall_ck` `087:61-66`; sign-derived buckets `087:329-333` |
| The disbursement instruction | `kernel.payout(cause='settlement', payee_kind='organization')` `085:120-121`, `085:113`; minted at `087:341-345` |
| The destination | `kernel.organization.stripe_connect_account_ref` `077:114` + the SoD/step-up/probation controls `087:426-500` |
| The transfer result | `kernel.payout.stripe_transfer_ref` write-once `085:133`, `085:1712-1716`; `settlement → paid` via `venue.on_payout_settled` `087:360-397` |
| Chargeback against the venue | `cause='chargeback'` producer for **primary orders already exists** `088:351-359` |
| Refund reversal bucket | `cause='refund_void'` in the enum `087:97`, bucketed at `087:331` |
| The dispute payout freeze | `088:839-852` — becomes live the moment `primary_sale` lines exist with `cause_ref=order_id` (§3.4) |

**New structures required (minimum):**

1. **A per-order split.** New columns on `venue."order"` (the immutable-after-paid table), mirroring
   `market_sale_split_ck` (`088:134-138`): e.g. `face_minor`, `platform_fee_minor`,
   `venue_proceeds_minor`, all-or-none NULL, summing to `total_minor`. *Or* the split is derived at
   close from `venue.order_item` (`082:168-170`) plus a policy key. Storing it is materially safer:
   `order_item` is already frozen after payment (`082:180-217`), whereas a config key can change
   between sale and close.
2. **One config key** for the primary platform fee (none exists — `078:1544-1556`). PFA-30
   (`POST_FREEZE_AMENDMENTS.md:2334-2344`) forbids inventing a rate; the owner must name it.
3. **A `primary_sale` candidate producer** — a third seam function returning
   `SETOF kernel.settlement_line_candidate`, plus the two-line change to the union at `087:311-312`.
   Emitting `(cause='primary_sale', cause_ref=order_id, amount_minor=+venue_proceeds_minor)`.
4. **A cross-settlement uniqueness index**, exactly analogous to `090:214-215`:
   `CREATE UNIQUE INDEX ... ON venue.settlement_line (cause_ref) WHERE cause = 'primary_sale'`.
   *Caveat from the adversarial pass:* `close_settlement`'s
   `on conflict (settlement_id, cause, cause_ref) do nothing` (`087:320`) is an **inference
   specification** that arbitrates only `settlement_line_cause_uq`; a violation of a new partial index
   raises `23505` and aborts the whole close. The `ON CONFLICT` clause must become a bare
   `DO NOTHING` for the index to be safe (`docs/phase2/ADVERSARIAL_ARCHITECTURE_REVIEW.md:181-191`).
5. **A refund line producer.** `kernel.refund_primary_order` (`085:598-606`) must either emit a
   `refund_void` line or a candidate seam must derive one from `kernel.refund` — otherwise a
   post-close refund never reduces the venue's next settlement.

**New enum members required: NONE.** `primary_sale`, `refund_void`, `chargeback` are all in
`087:95-98`; `settlement` is in `085:120-121`. This is the model the enums were drawn for.

**Platform revenue representation:** if the `primary_sale` line is entered *net* (venue proceeds only),
platform revenue is representable only by subtraction (`order.total_minor − Σ primary_sale lines`) and
never appears as a row. If it is entered *gross* with a separate negative fee line, a **new `cause`
member** is required — `087:95-98` has no fee label. This is the one place Model A may need an enum
widening, and it is a policy choice, not a technical one.

### 6.2 Model B — venue is merchant of record via Stripe destination charges / `on_behalf_of`

**Sufficient as-is:** the `venue.settlement` / `venue.settlement_line` pair as a *reporting* ledger; the
`chargeback` producer (`088:351-359`); `venue.order` / `order_item`; the RLS read model (`087:78-84`,
`087:117-125`).

**New structures required:**

1. **Everything in §6.1 items 1–5** — the split, the fee key, the candidate producer, the uniqueness
   index, the refund producer. Model B does not avoid the ledger work; it changes only *who moves the
   money*.
2. **A per-order snapshot of the destination account.** `kernel.organization.stripe_connect_account_ref`
   (`077:114`) is a **single mutable current-value column**, rewritten wholesale by
   `kernel.set_org_payout_destination` (`085:1648-1656`). Under Model B the destination is bound at
   charge time, so an order settled after a destination change would be reported against an account
   that never received it. A new column is needed on `venue."order"` or `kernel.payment_native`
   capturing the destination ref actually used, plus the application-fee amount. Neither table has a
   place for it today (`082:74-93`, `085:40-60`).
3. **A payout-suppression mechanism.** `close_settlement` unconditionally mints
   `kernel.payout(cause='settlement')` whenever `net_minor > 0` (`087:340-345`). Under Model B the
   venue has already been paid by Stripe; that payout row would be a *duplicate disbursement
   instruction*. Either a per-org payout mode column on `kernel.organization` or a settlement-level
   flag is required, and `close_settlement`'s body must branch on it.
4. **A platform-revenue line class.** The application fee is platform revenue retained at charge time.
   Representing it needs a `cause` member that does not exist (`087:95-98`) — see §6.1's closing note,
   except that here it is not optional: under Model B the venue's *gross* is the charge and the
   platform's fee is genuinely a deduction, so the gross/fee decomposition must be real.
5. **`venue.on_payout_settled` becomes unreachable** for these settlements — `settlement.status='paid'`
   has exactly one writer (`087:377`), gated on `payout.cause='settlement'` (`087:367`). Under Model B
   a settlement would remain permanently `'closed'`. Either a second `closed→paid` transition writer is
   needed, or `'paid'` acquires a different meaning for these rows.

**Net:** Model B is Model A's ledger work **plus** four structural additions **plus** a body change to
the single most safety-critical function in the schema (`kernel.close_settlement`, described at
`087:275` as "SSCAS #4").

### 6.3 Model C — venue is merchant of record via direct charges on the venue's connected account

Under C, funds never enter the platform balance. The accounting **inverts**: the platform has a
*receivable from the venue*, not a payable to it. Almost nothing in the shipped schema fits.

**New structures required:**

1. **§6.0's blocker becomes total.** `public.payments` is a record of *the platform's own charge*
   (`stripe_payment_intent_id`, `stripe_client_secret`, `stripe_livemode` —
   `000_baseline_schema.sql:986-987`, `045:15`). A charge on the venue's account is not that object.
   `kernel.payment_native.payment_id → public.payments(id)` (`085:42`) and
   `kernel.refund.payment_id → public.payments(id)` (`085:76`) and
   `kernel.dispute_native.payment_id → public.payments(id)` (`088:194`) all inherit the mismatch.
2. **An organization-debtor obligation table.** `kernel.identity_obligation.debtor_identity_id` is
   `NOT NULL REFERENCES auth.users(id)` (`085:167`) — an org id is unstorable. A receivable from a
   venue therefore has **no representation anywhere in the schema**. Widening that column is not
   available (the FK is to `auth.users`), so this is a new table plus a new resolution RPC pair
   mirroring `085:1793-1878`.
3. **`kernel.payout` becomes meaningless for primary sales.** Its `payee_*` columns and
   `payout_payee_xor_ck` (`085:139-142`) model *outbound* money; there is no inbound counterpart, and
   `amount_minor > 0` (`085:123`) makes a negative "collection" unstorable.
4. **`kernel.reserve` is the only org-scoped balance shape (`091:29-36`) and is contractually sealed**
   — "nothing may be added to it" (`091:13-15`), `revoke all ... from ... service_role` (`091:45`).
   Using it requires reopening a package the freeze record treats as closed.
5. **Refunds and chargebacks** execute on the connected account; `kernel.refund` (`085:74-95`) and
   `kernel.dispute_native` (`088:189-213`) both anchor to `public.payments` and both would need
   re-anchoring. `088:351-359`'s chargeback→settlement producer books the loss to the org via
   `payment_native.order_id`; under C the loss is already the org's and the line would double-count.
6. **The entire payout control surface is dead weight**: SoD-1 (`087:426-428`), destination probation
   (`087:466-495`), dual control (`087:521-560`), step-up (`087:433-440`) all guard an outbound
   transfer that no longer happens.

**Assessment:** Model C is not a migration; it is a different money architecture. The frozen corpus
contains no structure that anticipates it.

### 6.4 Minimality summary

| | New tables | New columns | New enum members | New indexes | `close_settlement` body change | New config keys |
|---|---|---|---|---|---|---|
| **A** | 0 | 3 on `venue."order"` (or 0 if derived) | 0 (1 if platform fee is a line) | 1 partial unique | yes (seam union + `ON CONFLICT`) | 1 |
| **B** | 0 | A's 3 + destination ref + fee amount + payout-mode flag | ≥1 (platform fee) | 1 partial unique | yes, larger (payout suppression + `paid` transition) | 1 |
| **C** | ≥1 (org obligation) + a primary payment table | many | several | several | rewritten | several |

---

## 7. RECONCILIATION — PROVING EVERY DOLLAR IS OWED, PAID, REFUNDED OR RETAINED

### 7.1 What exists

- **Within one settlement, conservation is provable.** `settlement_waterfall_ck` (`087:61-66`) makes a
  violating header unstorable, and the derivation at `087:329-333` guarantees
  `net_minor = Σ(all lines of that settlement)` exactly. `venue.settlement_line` is append-only
  (`087:110-112`, `087:115`), so the sum is stable once written.
- **Payout ↔ settlement linkage is idempotent and traceable.**
  `idempotency_key = 'settlement:'||settlement_id` (`087:343`) plus `payout_idempotency_uq`
  (`085:138`) makes double-minting impossible; `payout_cause_ref_idx` (`085:150`) makes the reverse
  lookup cheap; `venue.on_payout_settled` advances the header only when **no** `cause='settlement'`
  payout for that settlement is in a non-`paid` state (`087:387`) — a genuine completeness predicate.
- **A full audit trail exists.** `kernel.admin_audit` receives a row at every money transition:
  `settlement.open` (`087:265`), `settlement.close` (`087:348`), `payout.request` /
  `payout.probation_hold` / `payout.request_stale` (`087:491-495`, `087:513-516`, `087:544-548`,
  `087:562-570`), `payout.state_sync` (`085:1727-1732`), `payout.hold` / `payout.release`
  (`085:799-802`, `085:833-836`), `refund.issue` (`085:608-613`), `obligation.record` /
  `obligation.resolve` (`085:1827-1830`, `085:1869-1873`), `settlement.commission` (`090:1503-1506`).
- **Write-once external references.** `payout.stripe_transfer_ref` (`085:133`, conflict-checked at
  `085:1712-1716`) and `refund.stripe_refund_ref` (`085:89`, partial-unique at `085:96-97`) make the
  DB↔Stripe correspondence one-to-one on the DB side.

### 7.2 What is missing

1. **The collected side has no ledger representation at all.** Money collected for a primary order is
   recorded once, in `venue."order".total_minor` (`082:83`) and `kernel.payment_native.amount_minor`
   (`085:47`). Neither is a ledger line; neither is bucketed; neither is reconciled against anything.
   **The equation `collected = owed + paid_out + refunded + retained` has no left-hand side in the
   ledger.**
2. **No `primary_sale` line ⇒ `owed` is structurally zero** (§3). The venue's claim exists only as an
   arithmetic over `venue."order"`, and that arithmetic is gross, unadjusted and unauditable (§4.3).
3. **`retained` (platform revenue) has no row and no cause.** There is no fee column on the primary
   order (§3.2 item 2), no fee cause in `087:95-98`, and no fee config key (`078:1544-1556`). Platform
   revenue on primary ticketing is currently un-representable.
4. **`refunded` does not reach the settlement.** `kernel.refund` rows exist (`085:74-95`), but no path
   turns one into a `refund_void` line (§3.2 item 5), so a refund never reduces a settlement.
5. **No cross-settlement uniqueness on `primary_sale`**, and no uniqueness at all on `venue.settlement`
   (§1.2) — so even with a producer, the same order could be lined and paid twice. The commission engine
   needed `090:214-215` to close exactly this hole.
6. **No `public.payments` ↔ `kernel.*` reconciliation object.** `kernel.payment_native` links a payment
   to an order (`085:42-44`) with `payment_native_payment_uq` (`085:56`), but nothing asserts that every
   `succeeded` payment has a link, or that `payments.total ≥ order.total_minor` outside the one-shot
   check inside `finalize_primary_order` (`085:1931-1934`). An orphaned succeeded payment — money
   collected, order never finalized — is invisible.
7. **The dispute freeze leg is dead for primary orders** (§3.4, `088:842-844`) — a chargeback cannot
   freeze a venue payout that has no line.
8. **Currency is unvalidated** (§5.5) — cross-settlement aggregation over `currency` is only as sound
   as the writers' discipline.
9. **`integer` overflow at ~$21.47M per settlement** (§5.5) aborts a close with an opaque `22003`
   rather than degrading.
10. **No period-completeness assertion.** Nothing proves a settlement's line set is *complete* for its
    scope. The seams use `NOT EXISTS` dedupe (`088:349`, `090:1543`) under a per-org advisory lock
    (`088:330`, `090:1519`), which prevents *duplicates* but never proves *coverage*. There is no
    "every paid order in this window is lined" check anywhere.

### 7.3 The minimum reconciliation query that a future migration should make answerable

Today this returns nothing useful. It is the shape of the missing fact:

```sql
-- "which paid venue orders carry no primary_sale line?"  (the orphan sweep)
select o.order_id, o.org_id, o.total_minor, o.created_at
  from venue."order" o
 where o.status in ('paid','partially_refunded')
   and not exists (select 1 from venue.settlement_line l
                    where l.cause = 'primary_sale' and l.cause_ref = o.order_id);
```

The index it needs already exists: `settlement_line_cause_ref_idx` (`087:108`).

---

## APPENDIX — CITATION INDEX

| Fact | Citation |
|---|---|
| `settlement_line.cause` enum (13 members incl. `primary_sale`) | `supabase/migrations/087_venue_settlement_and_export.sql:95-98` |
| The ONLY `INSERT INTO venue.settlement_line` | `087:318-320` |
| Settlement waterfall CHECK | `087:61-66` |
| Sign-derived bucket derivation | `087:329-333` |
| The ONLY org payout mint | `087:341-345`, gated `087:340` |
| `settlement → paid` sole writer | `087:377` (fn `087:360-397`) |
| `settlement_line` append-only + service_role revoke | `087:110-112`, `087:115` |
| `settlement_line_cause_uq` | `087:105` |
| No unique constraint on `venue.settlement` | `087:44-69` (absence) |
| Royalty/chargeback seam (no `primary_sale` arm) | `088:319-364`, causes at `088:337`, `088:352` |
| Commission seam (no `primary_sale` arm) | `090:1511-1553`, cause at `090:1549` |
| `attribution_one_commission_line_ever` | `090:214-215` |
| `kernel.payout` table + all three enums | `085:111-147` (`cause` `085:120-121`, `status` `085:125-126`, `hold_state` `085:128-129`) |
| `hold_reason_code` is free text, no CHECK | `085:130` |
| Commission payout minted already-held | `090:1483-1488` |
| `kernel.refund` reason/status enums | `085:77-79`, `085:84-85` |
| `identity_obligation` debtor is `auth.users` only | `085:167` |
| `kernel.reserve` sealed stub | `091:29-36`, `091:13-15`, `091:45` |
| `venue."order"` has only `total_minor`, no fee split | `082:74-93` (esp. `082:83`) |
| `order_item` immutable after paid | `082:180-217` |
| `finalize_primary_order` writes: order→paid, payment_native, atoms | `085:2056`, `085:2060-2061`, `085:2045-2052` |
| `finalize_primary_order` requires a `public.payments` row | `085:1919-1934` |
| `public.payments.listing_id` NOT NULL FK to `public.listings` | `000_baseline_schema.sql:973` |
| `public.payments` amounts in cents | `000_baseline_schema.sql:977-985` |
| `kernel.organization` destination columns | `077:114-118`, unique index `077:125-126` |
| Destination change (single mutable column) | `085:1648-1656` |
| `request_org_payout` control stack | `087:414-446`, probation `087:466-496`, dual control `087:521-560` |
| `mark_payout_transfer_state` forward-only + held refusal | `085:1683-1721` |
| Dispute payout freeze (dead for primary orders) | `088:839-852`, esp. `088:842-844` |
| `market_sale` three-way split + summing CHECK (the contrast) | `088:118-120`, `088:134-138` |
| PFA-30 — resale split parked fail-closed | `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2323-2353` |
| E-138 / `COMMISSION_FUNDING_SOURCE` — Option B ruled, implementation OPEN | `POST_FREEZE_AMENDMENTS.md` (E-138 and `COMMISSION_FUNDING_SOURCE` entries, ~`:2469`, ~`:2482`) |
| Money config keys, all seeded NULL; no primary fee key | `078:1544-1556` |
| `feature.native_issuance_enabled` seeded false | `078:1522` |
| Freeze record: Gate-M gates the ledger family | `docs/architecture/_governance/PHASE_2_ARCHITECTURE_FREEZE.md:73-76` |
| `ON CONFLICT` is an inference spec, blocks a new partial index | `docs/phase2/ADVERSARIAL_ARCHITECTURE_REVIEW.md:181-191` |
| Zero production callers of any settlement/payout RPC | `src/lib/venue/client.ts:280,288` (comments only); `supabase/functions/` (absence) |
