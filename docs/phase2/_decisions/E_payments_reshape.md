# DECISION E — THE PAYMENTS RESHAPE

**Repo:** `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2`
**Method:** read-only analysis. No SQL executed, no migration authored, no production touched.
**Scope:** can `public.payments` carry a venue-direct (primary) payment, and what is the smallest safe change that lets it.

---

## 0. VERDICT (one screen)

| Question | Answer |
|---|---|
| Is the reported deficiency real? | **YES — confirmed on all four constraints**, with one correction: the partial unique index does **not** need rescoping. |
| Does a genuinely additive path exist (leave `public.payments` untouched)? | **NO.** Every "don't touch `payments`" variant costs a *larger* amendment than touching it, because it requires rewriting an authored-once money verb and contradicts the frozen "`payments` is the sole money-in event" principle. |
| Is the adversarial RLS trap real? | **YES as stated, but the prescribed remedy is wrong.** Native invisibility to the seller policy is *correct behaviour*; an org-scoped replacement policy is neither needed nor implementable, and would break a pinned CI assertion. |
| Consumer blast radius | **87 distinct reference sites** (47 SQL · 40 non-SQL). **18** touch `listing_id`/`seller_id`/`mode` by name; **12** of those sit on the live resale path. |
| Recommendation | **A constrained relaxation** — drop the two NOT NULLs, widen `mode`, and re-impose both NOT NULLs *conditionally* via a rail-pairing CHECK in the same transaction. Net effect on the resale rail: **zero loosening**. |
| Post-freeze amendment required? | **YES** — one, and it is the amendment the corpus already anticipated (`PUBLIC_PAYMENTS_NATIVE_SHAPE`), plus a re-scope from resale-only to both rails. |
| Classification | **OWNER POLICY → POST-FREEZE AMENDMENT → then implementation in 093.** |

---

## 1. THE EXACT CURRENT SHAPE OF `public.payments`

Defined once, never redefined. Four additive alterations since.

### 1.1 Table DDL — `supabase/migrations/000_baseline_schema.sql:971-1001`

| Column | Definition | Line |
|---|---|---|
| `id` | `uuid primary key default gen_random_uuid()` | `:972` |
| **`listing_id`** | **`uuid NOT NULL references public.listings(id)`** | **`:973`** |
| `buyer_id` | `uuid NOT NULL references auth.users(id)` | `:974` |
| **`seller_id`** | **`uuid NOT NULL references auth.users(id)`** | **`:975`** |
| `amount` | `int NOT NULL check (amount > 0)` | `:981` |
| `buyer_fee` | `int NOT NULL check (buyer_fee >= 0)` | `:982` |
| `seller_fee` | `int NOT NULL default 0 check (seller_fee >= 0)` | `:983` |
| `total` | `int NOT NULL check (total > 0)` | `:984` |
| `stripe_payment_intent_id` | `text UNIQUE` | `:987` |
| `stripe_client_secret` | `text` | `:988` |
| `status` | `text NOT NULL default 'pending' check (status in ('pending','processing','succeeded','failed','refunded'))` | `:991-992` |
| `payment_method` | `text` | `:994` |
| **`mode`** | **`text NOT NULL check (mode in ('buy_now','auction'))`** | **`:995`** |
| `created_at` / `paid_at` / `failed_at` / `refunded_at` | timestamps | `:998-1001` |

*(The gap matrix cites `:972/:974/:993`; the shipped bytes are `:973/:975/:995`. `ADVERSARIAL_REVIEW.md` J-18 already recorded this citation drift. The lines above were read directly.)*

### 1.2 Later alterations — all purely additive

| Migration | Change |
|---|---|
| `007_transfer_expiry.sql:44-45` | `add column if not exists stripe_refund_id text` |
| `022_seller_fee_column.sql:36` | `RENAME COLUMN service_fee TO buyer_fee` (guarded by `information_schema` probes at `:26-34`) |
| `022_seller_fee_column.sql:42-44` | `add column if not exists seller_fee int NOT NULL DEFAULT 0 CHECK (seller_fee >= 0)` |
| `045_payments_stripe_livemode.sql:15-17` | `add column if not exists stripe_livemode boolean` + `COMMENT ON COLUMN` |

**No migration anywhere in the tree contains `INSERT INTO payments` or `DELETE FROM payments`.** All writes come from edge functions; the only in-DB `UPDATE` to `payments.status` was removed at `061`.

### 1.3 Indexes and constraints

| Object | Definition | Line |
|---|---|---|
| `idx_payments_listing_id` | btree `(listing_id)` | `000:1005-1006` |
| `idx_payments_buyer_id` | btree `(buyer_id)` | `000:1007-1008` |
| `idx_payments_seller_id` | btree `(seller_id)` | `000:1009-1010` |
| `idx_payments_stripe_pi` | btree `(stripe_payment_intent_id)` | `000:1011-1012` |
| `idx_payments_status` | btree `(status)` | `000:1013-1014` |
| **`idx_payments_one_success_per_listing`** | **`UNIQUE (listing_id) WHERE status = 'succeeded'`** | **`003_payment_integrity.sql:52-54`** |
| `transfers_payment_id_key` | `UNIQUE (payment_id)` on `public.transfers` (paired guard) | `003:67-71` |

### 1.4 RLS — enabled, two SELECT policies, no write policy

| Policy | Predicate | Line |
|---|---|---|
| `alter table public.payments enable row level security` | — | `000:1017` |
| `"payments: buyer select"` | `USING (buyer_id = auth.uid())` | `000:1021-1023` |
| **`"payments: seller select"`** | **`USING (seller_id = auth.uid())`** | **`000:1027-1029`** |
| *(none)* | No INSERT / UPDATE / DELETE policy exists — stated at `000:1031-1032` | — |

`070_reconcile_rls_policies_and_triggers.sql` contains **zero** `payments` references — the 000 policies are still the live shape.

### 1.5 Grants

`public.payments` retains Supabase's default `GRANT ALL ON ALL TABLES IN SCHEMA public` to `anon`/`authenticated`, less `TRUNCATE, REFERENCES, TRIGGER` revoked wholesale at `063_revoke_unsafe_execute_and_truncate.sql:50,54`. Those residual DML grants are **inert**: with RLS on and no write policy, client INSERT/UPDATE/DELETE all fail `42501`. `074_privilege_cleanup.sql` names `payments` only in a comment (`:17`).

### 1.6 Triggers

**None.** No `CREATE TRIGGER ... ON public.payments` exists anywhere in the tree. `supabase/tests/060_payments_money.sql:68-75` records this as open gap **F-3** (`SELECT todo('F-3: add a payments amount/status guard trigger', 1)`) — any service-path writer can mutate `amount`/`total` unguarded.

### 1.7 The five properties a venue-direct payment collides with

1. `listing_id NOT NULL → public.listings(id)` (`000:973`) — a direct event order has no resale listing.
2. `seller_id NOT NULL → auth.users(id)` (`000:975`) — a direct order has no individual seller; the counterparty is an org.
3. `mode NOT NULL CHECK IN ('buy_now','auction')` (`000:995`) — no truthful label exists for a primary sale.
4. `idx_payments_one_success_per_listing` (`003:52-54`) — **the reported blocker here is FALSE.** The index carries no `NULLS NOT DISTINCT` clause, so Postgres treats every NULL `listing_id` as distinct. A nullable `listing_id` makes this index a silent no-op *for native rows only*, while preserving it byte-for-byte for resale rows. **It needs no rescoping.** (The codebase uses `NULLS NOT DISTINCT` deliberately elsewhere — `078:269`, `083:309` — so its absence here is meaningful, not accidental.) The *consequence* of that no-op is a real residual, handled in §6.4.
5. `public.listings.neighborhood NOT NULL CHECK IN (nine Miami values)` (`000:70-77`) — relevant only if anything tries to synthesize a listing (see §5.2).

---

## 2. CONSUMER BLAST RADIUS

**87 distinct reference sites: 47 SQL · 40 non-SQL.** Of these, **18** name `listing_id`, `seller_id`, or `mode`; the remaining 69 key on `payments.id` (or `stripe_payment_intent_id`) and are structurally indifferent to the nullability of either column.

Column legend: **L** = `listing_id` · **S** = `seller_id` · **M** = `mode` · **id** = keys on `payments.id` only.

### 2.1 Foreign keys referencing `public.payments` — 8, all to `(id)`

**Zero FKs anywhere reference `listing_id`, `seller_id`, or `mode`.**

| # | Site | Child column | Clause | Impact |
|---|---|---|---|---|
| 1 | `supabase/migrations/002_transfers.sql:41` | `public.transfers.payment_id` | `not null references payments(id)` | id — none |
| 2 | `supabase/migrations/024_disputes.sql:17` | `public.disputes.payment_id` | nullable | id — none |
| 3 | `supabase/migrations/039_risk_based_payout.sql:80` | `public.payout_decisions.payment_id` | `ON DELETE SET NULL` | id — none |
| 4 | `supabase/migrations/069_webhook_retries_table.sql:14` | `public.webhook_retries.payment_id` | nullable | id — none |
| 5 | `supabase/migrations/085_kernel_money_native.sql:42` | `kernel.payment_native.payment_id` | `not null ... on delete restrict` | id — none |
| 6 | `supabase/migrations/085_kernel_money_native.sql:76` | `kernel.refund.payment_id` | `not null ... on delete restrict` | id — none |
| 7 | `supabase/migrations/088_market_native_rail.sql:121` | `market.market_sale.payment_id` | nullable | id — none |
| 8 | `supabase/migrations/088_market_native_rail.sql:194` | `kernel.dispute_native.payment_id` | `not null ... on delete restrict` | id — none |

### 2.2 SQL consumers that name L / S / M — the only SQL sites that matter

| # | Site | Object | Cols | Behaviour on a NULL row | Verdict under §6 design |
|---|---|---|---|---|---|
| 9 | `supabase/migrations/061_ensure_transfer_exists_requires_verified_payment.sql:93` | `ensure_transfer_exists` (**authoritative** def; supersedes `010:50-57`, `0591:24-28`) | **L** | `WHERE listing_id = p_listing_id` never matches NULL → `RAISE 'No verified payment found for this listing'` (`:99`). Fails **loud** | **Unreachable** — pairing CHECK forbids a NULL-L resale row |
| 10 | `supabase/migrations/061_...sql:91` → `:111-114` | same fn, `seller_id` → `INSERT INTO public.transfers` | **S** | `transfers.seller_id` is `not null` (`002_transfers.sql:42`) → `23502` mid-checkout | **Unreachable** — same |
| 11 | `supabase/migrations/0563_scope_transfer_guard_bypass_to_function.sql:83` | `delete_account_cleanup` (**authoritative**; supersedes `020:61-63`, `0551:136`) | **S** | `where seller_id = p_user_id` never matches NULL. Harmless — a NULL carries no PII. Buyer leg (`:82`) still scrubs native rows | **Safe.** Contradicts the stated rationale at `019:6` ("preserves NOT NULL constraints") — record as errata |
| 12 | `supabase/migrations/20260902003623_admin_relist_listing_rpc.sql:65` | `admin_relist_listing` | **L** | `EXISTS (... WHERE p.listing_id = p_listing_id)` goes false → the "has payment history" guard silently fails to fire | **Unreachable** — a native row has no listing to relist |
| 13 | `supabase/migrations/000_baseline_schema.sql:1027-1029` | RLS `"payments: seller select"` | **S** | `NULL = auth.uid()` → NULL → not TRUE → **row silently invisible to every seller** | **Intended.** See §6.3 — this is the adversarial trap, and the correct behaviour |
| 14 | `supabase/migrations/003_payment_integrity.sql:52-54` | `idx_payments_one_success_per_listing` | **L** | NULLs distinct → invariant does not apply to native rows | **Intended**, with a named residual — §6.4 |
| 15 | `000:1005-1006` / `000:1009-1010` | `idx_payments_listing_id` / `idx_payments_seller_id` | L / S | btree indexes NULLs normally | None |
| 16 | `supabase/one-off/2026-08-04-backfill-payments-stripe-livemode.sql:11-13` | one-off `UPDATE` | id | Touches none of the three; marked executed, do-not-rerun | None |

### 2.3 SQL consumers keyed on `payments.id` — 31 sites, all indifferent

| Site | Object | Shape |
|---|---|---|
| `039_risk_based_payout.sql:186` | `get_auto_release_candidates()` | `JOIN public.payments p ON p.id = t.payment_id`; projects `p.amount` |
| `039_risk_based_payout.sql:388` | `get_payout_review_queue()` | same join; projects `p.amount`, `p.amount - p.seller_fee` |
| `065_dispute_resolution.sql:215` | `get_disputes_awaiting_refund()` | same join; `WHERE p.status <> 'refunded'` |
| `088_market_native_rail.sql:485` | `kernel.deletion_blockers_market()` | `join public.payments p on p.id = d.payment_id`; `p.buyer_id = p_identity` |
| `092_notify_reduced.sql:619` | `notify.drain_outbox()` refund branch | `join public.payments p on p.id = rf.payment_id`; reads `p.buyer_id` |
| `085:536, :539` | `kernel.refund_primary_order` | `FOR UPDATE` lock + `p.total` |
| `085:660, :699` | `kernel.admin_refund` | `p.total`, `p.status` |
| `085:969, :972` | `kernel.request_order_refund` | lock + `p.total` |
| **`085:1919`** | **`venue.finalize_primary_order`** | **`p.buyer_id, p.total, p.status`** — see §4 |
| `088:614, :695, :719` | `kernel.transfer_ticket_ownership` | `%rowtype`; `buyer_id`, `status`, `total` |
| `088:765, :789-858` | `kernel.record_dispute_native` | `%rowtype`; keyed on `stripe_payment_intent_id`; `id`, `buyer_id` |
| `088:1141, :1174-1175` | `market.respond_offer` | `%rowtype`; `buyer_id`, `status` |
| `088:1195, :1202-1218` | `market.mark_sale_paid_state` | `%rowtype`; `buyer_id`, `status`, `stripe_payment_intent_id` |
| `088:1657-1767` (7 sites) | `catalog.cancel_event` | locks + `p.total`, keyed on `payment_id` |

**Not a consumer despite its name:** `complete_auction_payment` (`000:1041` → `003:179` → **`0590_strict_auth_on_listing_checkout_rpcs.sql:117`** authoritative) touches only `public.listings`. Zero `payments` statements in any of its three bodies.

**Phase-2 reads nothing sensitive:** a targeted scan of `085`, `088`, `092` for `payments.listing_id`, `payments.seller_id`, `payments.mode` returns **zero hits**. The entire native money plane needs only `id`, `buyer_id`, `total`, `status`, `stripe_payment_intent_id`. `%ROWTYPE` declarations depend on column *existence*, not nullability.

### 2.4 Non-SQL consumers — 40 sites

**Edge functions** (`supabase/functions/`) — 22 sites.

| # | Site | Op | Cols | Break if NULL rows exist? |
|---|---|---|---|---|
| 17 | `stripe-webhook/index.ts:267-273` | UPDATE…RETURNING claim | **L** selected | No — `listing_id` is projected but never read; all downstream uses `metadata.listing_id` |
| 18 | `stripe-webhook/index.ts:291-295` | SELECT `id` by PI | id | No |
| 19 | `stripe-webhook/index.ts:508-514` | UPDATE `status='failed'` | **L** selected, unused | No |
| 20 | `stripe-webhook/index.ts:585-590` | SELECT `id` by PI (dispute) | id | No |
| 21 | `stripe-webhook/index.ts:691-695` | UPDATE `status='refunded'` by id | id | No |
| 22 | `stripe-webhook/index.ts:716-725` | UPDATE refund fields by PI | id | No |
| **23** | **`create-payment-intent/index.ts:417-422`** | SELECT `.eq('listing_id').eq('buyer_id').eq('mode')` | **L, M** | **YES — highest financial severity.** The duplicate-payment guard (`:432`) and pending-PI reuse (`:440`) both miss → a fresh PaymentIntent for an already-paid listing → **double charge**, with the voided partial index offering no backstop |
| 24 | `create-payment-intent/index.ts:570-587` | INSERT | **L, S, M** | No error (always supplies all three) — but loses the `23502` backstop if `listing.seller_id` were ever NULL |
| 25 | `create-payment-intent/index.ts:606-619` | SELECT + strict `===` compare on `listing_id`/`mode` | **L, M** | **YES** — 23505 race-recovery path not taken → 500 *after* a PI was created |
| **26** | **`confirm-payment/index.ts:243-250` → `:259-273`** | SELECT `id, listing_id, seller_id, buyer_id` → `transfers.insert(...)` | **L, S** | **YES — worst in the codebase.** `23502` on `transfers`; the catch at `:268-273` swallows **every** error code and the function returns 200 unconditionally (`:290-297`) → buyer charged, no transfer row, no alert, no retry |
| 27 | `confirm-payment/index.ts:216-225` | UPDATE by PI + buyer | id | No |
| 28 | `confirm-and-release/index.ts:405-409` | SELECT by `id` | id | No |
| 29 | `confirm-and-release/index.ts:586-590` | `rpc('record_transfer_payout')` | — | No (body does not touch payments) |
| 30 | `enforce-transfer-expiry/index.ts:202-206` | SELECT by id | id | No |
| 31 | `enforce-transfer-expiry/index.ts:276-283` | UPDATE refund by id | id | No |
| 32 | `enforce-transfer-expiry/index.ts:366-374` | `transfers` + embedded **`payments!inner(...)`** | id | No — the inner embed resolves through `transfers.payment_id`, not L/S |
| 33 | `enforce-transfer-expiry/index.ts:397-405` | UPDATE (Phase 1b self-heal) | id | No |
| 34 | `enforce-transfer-expiry/index.ts:421-425` | UPDATE `stripe_livemode=false` | id | No |
| 35 | `enforce-transfer-expiry/index.ts:526` | SELECT by id | id | No |
| 36 | `enforce-transfer-expiry/index.ts:722-723` | `rpc('get_auto_release_candidates')` | id | No |
| 37 | `enforce-transfer-expiry/index.ts:749-754` | `rpc('apply_payout_hold')` | — | No |
| 38 | `_shared/payout-policy.ts:62-90` | `PayoutCandidate` interface | L, S (sourced from `transfers`) | No |

**Web** (`web/`) — 4 sites.

| # | Site | Cols | Break? |
|---|---|---|---|
| **39** | `web/src/lib/checkout.ts:136-143` — SELECT `.eq("listing_id")...` | **L** | **YES (silent).** Fallback verification returns null → `verified` stays false → `:148-155` tells a charged buyer "We couldn't confirm this payment with Stripe"; `mark_listing_sold`/`complete_auction_payment`/`ensure_transfer_exists` (`:162-174`) all skipped |
| **40** | `web/src/lib/sales.ts:62-68` — `transfers` + embedded `payment:payments!payment_id(...)`, run as the seller | **S** (via RLS) | **YES (silent).** The embed is gated by the seller RLS policy; a NULL `seller_id` makes it resolve to `null` → `grossCents`/`netCents`/`paymentStatus`/`soldAtLabel` all null (`:88-95`). No throw — `:71` only guards the outer `transfers` query |
| 41 | `web/src/lib/checkout.ts:171-174` — `rpc("ensure_transfer_exists")` | L, S | Transitively #9/#10 |
| 42 | `web/src/app/checkout/[id]/complete/page.tsx:45` | — | Transitively #39/#41 |

**Mobile / shared** — 6 sites. **No direct table access anywhere in `/app`, `/src`, `/components`, `/hooks`, `/packages`** — RLS keeps the client off `payments` entirely (noted in-code at `src/lib/salePrice.ts:13`).

| # | Site | Break? |
|---|---|---|
| 43 | `src/lib/payments.ts:64` — invokes `create-payment-intent` | Inherits #23/#25 |
| 44 | `src/lib/payments.ts:117-119` — invokes `confirm-payment` | Inherits #26 |
| 45 | `src/screens/checkout/CheckoutNative.tsx:282` / `:345` | Inherits #44 |
| 46 | `src/screens/checkout/CheckoutNative.tsx:298-300` / `:362-364` — `rpc('ensure_transfer_exists')`; error only `console.warn`-ed at `:302` | Transitively #9/#10, **silently** |
| 47 | `src/types/index.ts:190-213` — `Payment` type: `listing_id: string`, `seller_id: string`, `mode: PaymentMode`, all non-nullable | **Type-level lie.** No generated `database.types.ts` exists in the repo, so nothing breaks at compile time — but the declaration becomes incorrect and must be updated |
| 48 | `packages/types/src/index.ts:179-202` — byte-identical duplicate of #47 | Same |

**Scripts / tests** — 4 sites.

| # | Site | Break? |
|---|---|---|
| 49 | `scripts/seed-demo.ts:631-636` — `.eq('listing_id', listingId)` idempotency probe | **YES (wrong results)** — probe misses → duplicate seed rows every run |
| 50 | `scripts/seed-demo.ts:650-663` — INSERT (L, S, M) | No |
| 51 | `scripts/release/phase2_preflight.sql:92-94` — `M3 payments: every payment's listing exists` (`where not exists (... l.id = p.listing_id)`) | **YES** — every native row would report as an orphan. **Preflight assertion must be rail-scoped** |
| 52 | `tests/payout-policy.test.ts:18`, `tests/money.test.ts:123` | No — in-memory fixtures / comments |

### 2.5 pgTAP assertions that constrain any 093

| Assertion | Site | Constraint imposed on 093 |
|---|---|---|
| `payments: exactly 2 SELECT-only policies (000)` | `supabase/tests/010_rls_smoke.sql:42` | **093 must add NO new RLS policy** or this fails |
| `transfers/payments: zero non-SELECT policies` | `supabase/tests/010_rls_smoke.sql:48-50` | 093 must add no write policy |
| `second succeeded payment for the same listing rejected (23505)` | `supabase/tests/060_payments_money.sql:38-41` | The 003 index must keep working for resale rows — it does |
| `buyer sees exactly their own payments` = 3 | `supabase/tests/060_payments_money.sql:26-27` | Fixture-scoped; unaffected |
| `F-3: add a payments amount/status guard trigger` (TODO) | `supabase/tests/060_payments_money.sql:68-75` | Pre-existing gap; 093 does not close it |
| Fixtures at `000_helpers.sql:155-161`, `149:169,198,247`, `153:53`, `154:21`, `155:44`, `157:27` | all supply L+S+M explicitly | **All pass unchanged** under the §6 design |

**The smoking gun:** `supabase/tests/149_phase2_kernel_money_native.sql:160-172` must create a **fake resale listing** (`'Money Night'`, neighborhood `'wynwood'`, `ticket_type 'GA'`) and a **fake seller** just to produce a `payments` row for `venue.finalize_primary_order` to consume. The test fixture is itself the proof of the deficiency, and it uses precisely the workaround the frozen amendment forbids in production.

---

## 3. THE COUPLING TO PHASE-2, AND THE FROZEN INTENT

### 3.1 `kernel.payment_native` — `085_kernel_money_native.sql:40-69`

```
id                     uuid primary key
payment_id             uuid NOT NULL references public.payments(id) on delete restrict   -- :42
order_id               uuid references venue."order"(order_id) on delete restrict         -- :43
sale_id                uuid                                                              -- :46 (FK adopted by 089)
amount_minor           integer NOT NULL check (amount_minor > 0)
currency               text NOT NULL default 'USD'
linked_at              timestamptz NOT NULL default now()
instrument_fingerprint text                                                               -- C112, promoter self-deal detector input
created_at             timestamptz NOT NULL default now()
constraint payment_native_payment_uq unique (payment_id)                                  -- :56
constraint payment_native_subject_xor_ck check (order_id XOR sale_id)                     -- :57-59
```

Plus: append-only trigger (`:64-66`), RLS enabled with **no policy** and `revoke all ... from anon, authenticated` (`:68-69`) — the entire native money plane is service_role/DEFINER-only.

### 3.2 What the frozen corpus says `payment_native` is

Unambiguous, in three independent places:

- **`docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:806-807`** — "the additive **bridge row** linking a native `venue.order` or `market.market_sale` to a frozen `public.payments` row. Native flows **link**, never re-charge."
- **Same file `:813`** — `payment_id` is "**the sole money-in event**".
- **Same file `:838`** — "SoT for the native↔frozen link; **`public.payments` remains SoT for the charge itself**."
- **Same file `:57-58` (§0.3)** — "Native money objects **link** to `public.payments` (integer cents, USD) for money-in; they never re-charge and never redefine the cents math."
- **Same file `:3677`** — the frozen mapping row: `public.payments` = "**Sole money-in event.** `kernel.payment_native.payment_id` FKs here; native orders/sales **link**, never re-charge."
- **`085_kernel_money_native.sql:13`** — "four ledger tables that LINK to the frozen public.payments (NEVER re-charge; OBS-1: zero changes to public.*)".

**Answer to the question posed:** `payment_native` was designed as the *link ledger*, with `public.payments` as the **shared money-in spine for both rails**. It was never intended to be, and structurally cannot be, a native-rail payment fact — it has no `status`, no Stripe PaymentIntent reference, no charge lifecycle. Its `amount_minor` is explicitly "a **mirror** of the charged cents, for reconciliation" (`SCHEMA_SPEC:817`).

### 3.3 `PUBLIC_PAYMENTS_NATIVE_SHAPE` — scope

**`docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2392`**, filed under *"Forward obligations opened by the 088 rulings"*:

> `public.payments.listing_id NOT NULL → public.listings` (frozen Phase-0) has no native-sale writer while `market_sale.payment_id` and `kernel.dispute_native.payment_id` FK `public.payments`; the native money path cannot record a payment without a live-rail listing row. **No fake listing row, no opportunistic Phase-0 mutation, no activation**: a deployment/live-rail compatibility decision owed before native money activation.

**Does it cover the primary rail?** The text names only 088 objects (`market_sale`, `dispute_native`) — it is *filed* as a resale-rail item. But the bytes settle it: `kernel.payment_native.payment_id` FKs `public.payments` (`085:42`) and `venue.finalize_primary_order` reads `public.payments` directly (`085:1919`). **The primary rail has the identical dependency.** `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md:411` (row D4) reaches the same conclusion — *"Bytes win. It blocks PRIMARY too. Re-scope the obligation"* — and `:431` (M3) classifies it **OWNER POLICY DECISION → then POST-FREEZE AMENDMENT**.

**Conclusion: the obligation covers both rails, and the re-scope from resale-only to both rails is itself part of the amendment this decision requires.**

### 3.4 The `order_id` column question — already settled, negatively

`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md:355-397` (§3.1, `primary-checkout`) says at `:373-374` that the edge "Records the `public.payments` row (frozen table) **with the new `order_id` linkage column**". That phrasing is **explicitly superseded** later in the same frozen document:

**`PHASE_2_EDGE_FUNCTION_SPEC.md:1811-1817` (§9 Reconciliation #1, "RESOLVED — spec-review R6; security-review obs-1"):**

> **No column is added to the frozen `public.payments` table — ever.** The webhook resolves the native order/sale from the PaymentIntent's `metadata.order_id`/`metadata.sale_id`, and the forward link lives exclusively in `kernel.payment_native`... Any reverse lookup is a JOIN through `kernel.payment_native`, never a frozen-table change. *(Earlier phrasing that `public.payments` might "carry" a native id is superseded by this resolution.)*

`PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md:413` (D6) records the same precedence ruling, and the shipped `085` DDL matches. **Adding `payments.order_id` is out of bounds without amending §9 recon #1.**

---

## 4. WHAT `venue.finalize_primary_order` ACTUALLY NEEDS

`085_kernel_money_native.sql:1881` (definition), `:1918-1935` (the payments interaction). Body read in full.

```sql
-- C35: the payment IS the authority — verified, succeeded, and the buyer's.
select p.buyer_id, p.total, p.status into v_pay from public.payments p where p.id = p_payment_id;   -- :1919
if not found then raise 'payment_unverified: payment % not found'; end if;                          -- :1920-1922
if v_pay.status <> 'succeeded'      then raise 'payment_unverified: payment % is %'; end if;        -- :1923-1925
if v_pay.buyer_id <> v_order.buyer_id then raise 'payment_unverified: buyer mismatch'; end if;      -- :1926-1928
if v_pay.total < v_order.total_minor  then raise 'payment_unverified: does not cover order'; end if;-- :1929-1934
if exists (select 1 from kernel.refund r where r.payment_id = p_payment_id and r.status <> 'failed')
  then raise 'payment_unverified: payment % already carries a refund'; end if;                      -- :1935-1937
```

and at the end:

```sql
insert into kernel.payment_native (payment_id, order_id, amount_minor, instrument_fingerprint)      -- :2060-2061
values (p_payment_id, p_order_id, v_order.total_minor, p_instrument_fingerprint);
```

**Precise answer:**

- **Does it need a row to exist?** **Yes, unconditionally.** `if not found then raise` at `:1920`. There is no bypass, no flag, no alternate branch.
- **Which columns?** Exactly **three**: `buyer_id`, `total`, `status`. Nothing else.
- **Does it read `listing_id`, `seller_id`, or `mode`?** **No.** Verified by targeted scan across `085`, `088`, `092`: zero hits.
- **Could a different table satisfy it?** **Not without rewriting `:1919`.** And the FK at `085:42` (`payment_native.payment_id NOT NULL → public.payments(id)`) independently forces a real `public.payments` row to exist before `:2060` can commit, so even a rewritten `:1919` would not free the flow from `public.payments` unless `085:42` were also altered.

**This is the decisive fact for option A.** The primary rail's coupling to `public.payments` is *doubly* enforced — once by a function body and once by a NOT NULL FK — and both live in frozen `085`.

---

## 5. THE THREE OPTIONS

### 5.1 ADDITIVE A — leave `public.payments` untouched; carry the direct-rail payment fact in Phase-2

**Shape:** extend `kernel.payment_native` (or add a 093 `kernel.payment_native_charge`) with `status`, `stripe_payment_intent_id`, `total`, `buyer_id`; make `payment_native.payment_id` nullable; rewrite `venue.finalize_primary_order` to read the new table.

**Is it possible without modifying frozen migration bytes?** **No.** Three independent blocks:

1. **`085:1919` must be rewritten.** A `CREATE OR REPLACE FUNCTION venue.finalize_primary_order` in 093 does not edit the 085 *file*, but it replaces an **authored-once money verb**. The corpus governs this explicitly: `POST_FREEZE_AMENDMENTS.md:2288-2289` — *"the caller is authored once and is never rewritten by another package"*; and `:2396` rules that a body-only amendment to an authored money verb requires **"an owner-signed PFA, since it touches an authored money verb"** (PFA-29 O-C precedent). `finalize_primary_order` is SSCAS member #1, the single most protected function in the schema (`085:1877-1880`; `RLS §11` calls a wrong grant here "the single highest-severity migration defect available in this schema").
2. **`085:42` must be altered.** `payment_native.payment_id NOT NULL → public.payments(id)` would have to become nullable, which is a frozen-table relaxation in `kernel` — the exact class of change option A exists to avoid.
3. **It contradicts the frozen architecture at its stated principle.** `SCHEMA_SPEC:57-58`, `:813`, `:838`, `:3677` and `085:13` all state that native rails **link** to `public.payments` as the sole money-in event and never carry the charge themselves. Option A inverts that principle, requiring amendments to §0.3, §1.8, §13's mapping row, and the RPC §6.3 contract.

| | |
|---|---|
| **Advantages** | Zero DDL on the live resale table. Zero risk to the 56 production payment rows. |
| **Disadvantages** | Requires the **largest** amendment surface of the three: an owner-signed PFA to rewrite an authored money verb, a frozen `kernel` FK relaxation, and amendments to four sections of the schema spec. Creates a second money-in source of truth — the exact duplication the corpus was designed to prevent. |
| **Failure modes** | Two money-in ledgers drift; reconciliation (Stripe → DB) needs two queries and can disagree; `kernel.refund.payment_id NOT NULL → public.payments(id)` (`085:76`) means refunds of native payments would have **no valid target**, requiring a second relaxation; `kernel.dispute_native.payment_id NOT NULL` (`088:194`) the same. |
| **Risk to the live resale rail** | **Near zero** — its only virtue. |
| **Launch implications** | Longest path. Multiple owner signatures, four spec amendments, and a rewrite of the most protected function in the schema, all before the first ticket is sold. |

**Verdict: REJECTED.** Option A is additive to `public.*` and destructive to the frozen architecture. It is the largest amendment dressed as the smallest change.

### 5.2 ADDITIVE B — add nullable columns; satisfy the NOT NULLs with sentinels or synthesized rows

**Shape:** add `payments.order_id uuid` (nullable); for each direct order, write a `payments` row with a synthesized or sentinel `listing_id` and a sentinel `seller_id`, `mode='buy_now'`.

**Four independent disqualifications:**

1. **The `order_id` column is forbidden outright.** `PHASE_2_EDGE_FUNCTION_SPEC.md:1811-1817` — "No column is added to the frozen `public.payments` table — **ever**." Adding it needs its own amendment, and the link it would carry already exists in `kernel.payment_native.order_id`.
2. **A fake listing row is forbidden by name.** `POST_FREEZE_AMENDMENTS.md:2392` — "**No fake listing row**, no opportunistic Phase-0 mutation." This is not an inference; it is the obligation text.
3. **A single sentinel listing caps the platform at ONE venue-direct sale, forever.** `idx_payments_one_success_per_listing` (`003:52-54`) is `UNIQUE (listing_id) WHERE status='succeeded'`. If every direct payment shares one sentinel `listing_id`, the *second* successful direct sale in the platform's history fails with `23505`. Per-order synthesized listings evade this — at the cost of point 4.
4. **Per-order synthesized listings are grotesque and actively harmful.** Each would need to satisfy: `neighborhood` ∈ nine Miami values (`000:70-77`) — a venue in Fort Lauderdale would be recorded as being in Wynwood; `ticket_type` ∈ `('GA','VIP','TABLE')` (`000:79`); `transfer_method` ∈ `('mobile_transfer','email')` (`000:81`); `duration_hours` ∈ `(1,3,6,12,24,48)` (`000:88`); `starting_bid > 0`, `current_bid NOT NULL`, `ends_at NOT NULL`, `cover_image_path NOT NULL` (`000:97`). And `"listings: public select" USING (true)` (`000:117-118`) makes every one of them **world-readable**: they would surface in the marketplace feed, in seller dashboards, in `profile_trust_stats` (`030`/`031`), and in the `admin_relist_listing` history guard. `listings.status` admits only `('active','reserved','sold')` (`000:292-293`) — there is no `synthetic` label to hide behind.

**On the sentinel seller specifically.** `019_anonymized_sentinel_user.sql:14-34` seeds `00000000-0000-0000-0000-000000000000` for the *anonymization* of deleted users' financial records. Reusing it for native payments is **strictly worse than NULL**: it produces exactly the same RLS invisibility (`'0000…' = auth.uid()` is never true for a real user) while additionally making deleted-user rows and venue-direct rows **indistinguishable in the ledger** — a reconciliation and audit hazard for no benefit. If the answer must render as "no individual seller", `NULL` says that truthfully and the sentinel says it falsely.

| | |
|---|---|
| **Advantages** | No constraint is relaxed; every existing consumer query keeps matching. |
| **Disadvantages** | Forbidden twice over by frozen text; requires two amendments anyway; injects phantom rows into a world-readable live-marketplace table. |
| **Failure modes** | Single-sentinel: platform-wide cap of one direct sale. Per-order: marketplace pollution, false geography, corrupted trust stats, corrupted admin guards, and `payments.mode` recording a lie that `create-payment-intent:417-422` will then match against. |
| **Risk to the live resale rail** | **HIGH** — this is the only option that writes rows into a live, client-readable production table. |
| **Launch implications** | Every synthesized listing is a support ticket waiting to happen. |

**Verdict: REJECTED — grotesque, and forbidden by the frozen obligation text.**

### 5.3 DESTRUCTIVE C — relax the NOT NULLs, widen `mode`, rescope the index, replace the RLS policy

**As stated in the brief, C is genuinely dangerous** — §2 enumerates 12 live-rail consumers that would silently misbehave, headed by a **double-charge path** (#23) and a **silently swallowed `23502`** (#26). Two of the four prescribed elements are also wrong:

- **"Rescope the unique index" — unnecessary.** NULLs are already distinct in `idx_payments_one_success_per_listing`; the index needs no change (§1.7 item 4).
- **"Ship a replacement seller-side RLS policy" — wrong, and CI-breaking.** See §6.3.

**Verdict on C as written: REJECTED.** But C's *core* — relaxing the two NOT NULLs and widening `mode` — is the only mechanism that reaches the goal. It becomes safe when paired with the constraint C omits, which is §6.

---

## 6. RECOMMENDATION — THE SMALLEST SAFE CHANGE

**Adopt C's mechanism, and re-impose both NOT NULLs conditionally in the same transaction via a rail-pairing CHECK.**

### 6.1 The design

Three DDL facts, one transaction:

1. **Widen `mode`** to admit one native label. Recommended: **`'native_primary'`** — it matches the frozen PI-metadata vocabulary (`EDGE_FUNCTION_SPEC:373` uses `metadata.rail = 'native_primary'`; the webhook default is *absent-`rail` ⇒ `external`*). Adding a value to a CHECK is purely additive: all 56 production rows satisfy the widened form.
2. **Drop `NOT NULL`** on `listing_id` and `seller_id`. Catalog-only operation; no table rewrite; no row changes.
3. **Add a rail-pairing CHECK** asserting: `mode IN ('buy_now','auction')` ⟺ both columns NOT NULL; `mode = 'native_primary'` ⟺ both columns NULL.

### 6.2 Why this is *smaller* than it looks

The pairing CHECK means **the resale rail is exactly as strict after 093 as before it.** A resale writer that omits `listing_id` or `seller_id` still fails loudly at INSERT — the enforcement moves from a column constraint to a table constraint, with identical effect. Every one of the 12 live-rail breaks in §2 requires a resale row carrying a NULL, and the CHECK makes that row **unstorable**:

| Break | Requires | Under the pairing CHECK |
|---|---|---|
| #23 double-charge (`create-payment-intent:417-422`) | a resale row with NULL `listing_id` or NULL `mode` | **unstorable** |
| #26 swallowed `23502` (`confirm-payment:243-273`) | a resale row with NULL L or S | **unstorable** |
| #39 "couldn't confirm" (`web/checkout.ts:136-143`) | a resale row with NULL L | **unstorable** |
| #40 blank sales money (`web/sales.ts:62-68`) | a `transfers` row whose payment has NULL S — but `transfers` exist only for resale | **unstorable** |
| #9/#10 `ensure_transfer_exists` | a resale row with NULL L or S | **unstorable** |
| #12 `admin_relist_listing` guard | a *native* row shadowing a listing — but a native row has no listing | **not applicable** |
| #49 seed-demo probe | a resale row with NULL L | **unstorable** |
| #51 `phase2_preflight.sql:92-94` orphan check | native rows counted as orphans | **must be rail-scoped** — the one genuine follow-up |

**Residual code work after 093: two items** — rail-scope the preflight assertion (`scripts/release/phase2_preflight.sql:92-94`), and correct the two hand-written type declarations (`src/types/index.ts:190-213`, `packages/types/src/index.ts:179-202`). Neither is a runtime break; there is no generated `database.types.ts` in the repo.

The remaining exposure is **edge-side and already scoped as F5**: `stripe-webhook` must branch on `metadata.rail` *before* `:267`, because its downstream uses `metadata.listing_id` (`:327`, `:333`, `:379`, `:385`) which a native PI does not carry. That is edge work required by the frozen spec regardless of what 093 does to the schema; 093 neither creates nor mitigates it.

### 6.3 The adversarial trap, answered

`ADVERSARIAL_REVIEW.md` J-2 is **correct that nullable `seller_id` makes native payments invisible through `"payments: seller select"` (`000:1027-1029`)**, and correct that no org-scoped policy exists to replace it. But **the prescribed remedy is the wrong fix**, for three reasons:

1. **The invisibility is correct behaviour, not a defect.** A venue-direct order *has no seller*. `buyer_id` stays `NOT NULL`, so `"payments: buyer select"` (`000:1021-1023`) still shows the buyer their own order payment — which is the only client-side read that should exist.
2. **No venue-facing surface reads `public.payments`.** Verified: there are zero direct client reads of `payments` in `/app`, `/src`, `/components`, `/hooks`, `/packages`, and no venue read in `src/lib/venue/`. Every org money read goes through `venue.settlement_line`, `kernel.payout`, and scoped DEFINER RPCs. Nothing is losing access it currently has.
3. **An org-scoped policy is not implementable and would break CI.** The org linkage lives in `kernel.payment_native → venue."order".org_id`, and `085:69` does `revoke all on kernel.payment_native from anon, authenticated` — so a policy could only reach it through a new SECURITY DEFINER helper. And `supabase/tests/010_rls_smoke.sql:42` pins the policy count at exactly 2; a third policy fails the suite.

**Correct disposition: 093 adds no RLS policy at all.** It makes the invisibility *deliberate and tested* — a new pgTAP assertion that a `native_primary` row is visible to its buyer and to no one else. If a venue-facing `payments` read is ever specified, it is a separate, scoped RPC, not a policy.

### 6.4 The one real residual this creates

With `listing_id` NULL, `idx_payments_one_success_per_listing` (`003:52-54`) does not constrain native rows. The equivalent primary-rail invariant is *one succeeded charge per order*, and it is only **partially** covered today:

- `payment_native_payment_uq` (`085:56`) stops one payment linking twice.
- `finalize_primary_order`'s `order.status='paid'` short-circuit (`:1971-1980`) stops a double mint.
- **Not covered:** two *distinct* succeeded PaymentIntents for the same order. The second finalize returns `idempotency_replay` without inserting a link — leaving a stranded succeeded charge with no `payment_native` row.

Mitigations, in order of preference: (a) the frozen deterministic PI idempotency key `pi_native_${order_id}_${total}_c${customerId}` (`EDGE_FUNCTION_SPEC:379-381`) already prevents this at the edge; (b) 093 may additionally add a **partial unique index on `kernel.payment_native (order_id) WHERE order_id IS NOT NULL`** — additive, on a frozen table, following the established late-additive pattern of `089`'s FK adoption; (c) a reconciliation query for succeeded `native_primary` payments with no `payment_native` link. **This residual must be named in the amendment; it is not a reason to prefer A or B, both of which have it too.**

### 6.5 Operational risk

`public.payments` holds **56 production rows**. `DROP NOT NULL` is catalog-only (no rewrite). `DROP/ADD CHECK` and the pairing `ADD CHECK` each scan 56 rows — microseconds. All three take `ACCESS EXCLUSIVE` briefly; set a short `lock_timeout` so the migration fails fast rather than queueing behind a long transaction. **All statements must be in one transaction**, so there is never a window in which a NULL is insertable without the pairing constraint in force.

---

## 7. CLASSIFICATION AND AMENDMENT REQUIREMENT

### Classification

| Layer | Class |
|---|---|
| Choosing the shape (relax-with-pairing vs. sentinel vs. Phase-2-carries-the-fact) | **OWNER POLICY** — `PUBLIC_PAYMENTS_NATIVE_SHAPE` is filed as *"a deployment/live-rail compatibility decision"*; `GAP_MATRIX:431` (M3) and `:469` both classify it as an owner decision that must precede code |
| Recording that decision + re-scoping the obligation to both rails | **POST-FREEZE AMENDMENT** |
| Writing 093 once the shape is ratified | **IMPLEMENTATION FOLLOW-UP** |
| Choosing the literal `mode` label | **IMPLEMENTATION FOLLOW-UP** (within the ratified shape) |
| Edge rail-gating of `stripe-webhook` | **IMPLEMENTATION FOLLOW-UP** — separate item (gap matrix F5), not part of this decision |

### Post-freeze amendment required: **YES**

One amendment, covering three things:

1. **Ratify the shape** — resolve `PUBLIC_PAYMENTS_NATIVE_SHAPE` with the §6 design (constrained relaxation + rail-pairing CHECK), explicitly rejecting the fake-listing and sentinel-seller paths the obligation already forbids.
2. **Re-scope the obligation from resale-only to both rails** — `POST_FREEZE_AMENDMENTS.md:2392` names only 088 objects; `085:42` and `085:1919` prove the primary rail carries the identical dependency (`GAP_MATRIX:411`, row D4: *"Bytes win. It blocks PRIMARY too. Re-scope the obligation"*).
3. **Record two consequential findings as errata** — (a) `019_anonymized_sentinel_user.sql:6`'s rationale ("preserves NOT NULL constraints on payments") is no longer strictly true for `seller_id`; (b) the §6.4 one-charge-per-order residual, with its mitigation.

### Documents that would need amending

| Document | What changes |
|---|---|
| `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2392` | `PUBLIC_PAYMENTS_NATIVE_SHAPE` → SATISFIED/RATIFIED with the ruled shape; scope corrected to **both rails** |
| `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3677` | The `public.payments` mapping row gains the `native_primary` mode and the conditional-NOT-NULL pairing |
| `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md:143` (F4), `:431` (M3), `:411` (D4), `:469` step 2 | F4 → RESOLVED; D4's re-scope recommendation → executed |
| `docs/product-v2/ADVERSARIAL_REVIEW.md` J-2 | Answered: confirmed, with the corrected remedy (no replacement RLS policy — §6.3) |

### Documents that do **NOT** need amending under this recommendation

- `PHASE_2_EDGE_FUNCTION_SPEC.md:1811-1817` (§9 recon #1) — **untouched**, because no column is added to `public.payments`. This is a direct consequence of choosing §6 over option B, and it is the single largest amendment saving available.
- `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §0.3 / §1.8 / §1.10 / §13.2 — **untouched**, because `public.payments` remains the sole money-in event and `kernel.payment_native` remains a pure link ledger. Option A would have required all four.
- `085_kernel_money_native.sql` — **no byte changes, and no `CREATE OR REPLACE` of `venue.finalize_primary_order`.** Its body already needs only `buyer_id`, `total`, `status` (§4), all of which a `native_primary` row supplies. **No owner-signed authored-money-verb amendment is required.** This is the decisive advantage over option A.

---

## 8. WHAT MIGRATION 093 WOULD CONTAIN (description only — not authored here)

**Precondition: the owner must ratify the shape before 093 is written.**

Scoped to this decision (093 also carries unrelated items per `GAP_MATRIX:474-478` — the signing-key bodies, the two `inventory.*` config rows, `door.schedule_move_grace_interval`, and the primary-rail notify emit clauses; those are out of scope here).

**In one transaction, in this order:**

1. **Widen the `mode` CHECK** — drop `payments_mode_check`, re-add it admitting `'native_primary'` alongside `'buy_now'` and `'auction'`. `payments.mode` has **zero SQL consumers** (verified across the whole tree), so nothing in the database reads it; dispatch on mode happens in TypeScript over *Stripe metadata*, not the column (documented at `074:172-177`).
2. **`ALTER COLUMN listing_id DROP NOT NULL`** and **`ALTER COLUMN seller_id DROP NOT NULL`** — catalog-only; the FKs to `public.listings(id)` and `auth.users(id)` are retained unchanged and simply stop applying to NULL.
3. **Add the rail-pairing CHECK** — resale arm: `mode IN ('buy_now','auction')` requires both columns NOT NULL. Native arm: `mode = 'native_primary'` requires both columns NULL. Validated immediately (56 rows). This is the load-bearing statement: it re-imposes today's strictness on the resale rail as a table constraint.
4. *(Recommended, §6.4)* **A partial unique index on `kernel.payment_native (order_id) WHERE order_id IS NOT NULL`** — additive, no frozen bytes touched, closing the one-succeeded-charge-per-order gap in the database rather than relying solely on edge idempotency.
5. **Comments** on the relaxed columns and the new constraint, recording the amendment id and stating that NULL means "venue-direct order — counterparty is an org, linked via `kernel.payment_native.order_id`".

**093 must NOT:**

- Add any column to `public.payments` (`EDGE_FUNCTION_SPEC:1811-1817`).
- Add, drop, or alter any RLS policy on `public.payments` — `supabase/tests/010_rls_smoke.sql:42` pins the count at exactly 2, and the invisibility of native rows to the seller policy is intended (§6.3).
- Alter `idx_payments_one_success_per_listing` — it already behaves correctly (§1.7 item 4) and `supabase/tests/060_payments_money.sql:38-41` pins it.
- `CREATE OR REPLACE` `venue.finalize_primary_order` or any other `085` function — no body change is needed, and one would require an owner-signed PFA.
- Insert any row into `public.listings`, or use the `019` sentinel user for anything.
- Touch `auth.users`, `public.transfers`, or any `kernel`/`venue` table beyond the item-4 index.

**Accompanying, not in the migration:**

- **New pgTAP** (a `093_*` file, keeping the existing suites untouched): a `native_primary` row with NULL `listing_id`/`seller_id` inserts successfully; a `buy_now` row with either column NULL is rejected `23514`; a `native_primary` row with a non-NULL `listing_id` is rejected `23514`; two succeeded `native_primary` rows coexist; two succeeded `buy_now` rows for one listing still collide `23505`; a `native_primary` row is visible to its buyer and to **no** other authenticated user.
- **`scripts/release/phase2_preflight.sql:92-94`** — rail-scope the M3 orphan assertion to `mode IN ('buy_now','auction')`.
- **`src/types/index.ts:190-213`** and **`packages/types/src/index.ts:179-202`** — `listing_id`/`seller_id` become nullable; `PaymentMode` gains `native_primary`.
- **Rollback** (`supabase/rollbacks/093_*`): drop the pairing CHECK, restore both NOT NULLs, restore the narrow `mode` CHECK — **valid only while zero `native_primary` rows exist**, with a fail-loud guard. Once real money lands on the native rail the posture is forward-fix only, matching `085`'s stated rollback posture ("FORWARD-FIX ONLY FROM FIRST ROW").

---

## 9. SOURCES

`supabase/migrations/000_baseline_schema.sql` · `002_transfers.sql` · `003_payment_integrity.sql` · `007_transfer_expiry.sql` · `019_anonymized_sentinel_user.sql` · `022_seller_fee_column.sql` · `039_risk_based_payout.sql` · `045_payments_stripe_livemode.sql` · `061_ensure_transfer_exists_requires_verified_payment.sql` · `063_revoke_unsafe_execute_and_truncate.sql` · `0563_scope_transfer_guard_bypass_to_function.sql` · `074_privilege_cleanup.sql` · `085_kernel_money_native.sql` · `088_market_native_rail.sql` · `092_notify_reduced.sql` · `20260902003623_admin_relist_listing_rpc.sql` · `supabase/tests/{010,030,060,080,090,149,153,154,155,157}` · `supabase/functions/{stripe-webhook,create-payment-intent,confirm-payment,confirm-and-release,enforce-transfer-expiry}` · `web/src/lib/{checkout,sales}.ts` · `src/screens/checkout/CheckoutNative.tsx` · `src/types/index.ts` · `packages/types/src/index.ts` · `scripts/seed-demo.ts` · `scripts/release/phase2_preflight.sql` · `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` · `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` · `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` · `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md` · `docs/product-v2/ADVERSARIAL_REVIEW.md`
