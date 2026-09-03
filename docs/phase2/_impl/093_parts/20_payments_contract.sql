-- ============================================================================
-- 093 · PART 20 — THE PAYMENTS CONTRACT AMENDMENT
-- POST-FREEZE AMENDMENT **PFA-PT-3** — `public.payments` obligation re-scoped
-- from resale-only to BOTH RAILS (owner ratification 2026-09-02, ruling E:
-- "constrained relaxation plus an explicit rail-pairing constraint").
-- ----------------------------------------------------------------------------
-- Authorities (read, not assumed):
--   · docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md §E  — RATIFIED,
--     recorded as PFA-PT-3, classification POST-FREEZE AMENDMENT → 093.
--   · docs/phase2/_decisions/E_payments_reshape.md §6 (design), §6.2 (why the
--     resale rail is EXACTLY as strict after this as before), §6.3 (the RLS
--     disposition), §6.4 (the one named residual), §8 (statement order).
--   · docs/phase2/_rulings/H_migration_design.md §5.3 (the one lock that
--     matters; `set local lock_timeout`; `NOT VALID` explicitly rejected).
--   · docs/phase2/093_FINAL_PROPOSED_SCOPE.md §1 + manifest ("0 new policies,
--     0 DDL on any money-ledger table, venue.finalize_primary_order untouched").
--   · docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2392
--     (PUBLIC_PAYMENTS_NATIVE_SHAPE — the obligation this discharges).
-- ----------------------------------------------------------------------------
-- THE PROBLEM, IN BYTES. `public.payments` requires a listing, a seller and a
-- resale mode:
--   000_baseline_schema.sql:973  listing_id uuid NOT NULL references public.listings(id)
--   000_baseline_schema.sql:975  seller_id  uuid NOT NULL references auth.users(id)
--   000_baseline_schema.sql:995  mode       text NOT NULL check (mode in ('buy_now','auction'))
-- A venue-direct sale has NO listing and NO seller — its counterparty is an
-- organization. And the requirement is bolted in TWICE inside frozen 085:
--   085:42        kernel.payment_native.payment_id NOT NULL → public.payments(id)
--   085:1919-1937 venue.finalize_primary_order: `select p.buyer_id, p.total,
--                 p.status ... if not found then raise 'payment_unverified'`.
-- So the direct rail cannot record money until this table admits its shape.
-- ----------------------------------------------------------------------------
-- THE SHAPE OF THE FIX. Three DDL facts, ONE transaction:
--   1. widen the `mode` CHECK to admit the direct rail's label;
--   2. drop NOT NULL on `listing_id` and `seller_id` (catalogue-only);
--   3. re-impose BOTH requirements CONDITIONALLY via a rail-pairing CHECK.
-- Net loosening of the resale rail: **ZERO**. The enforcement moves from a
-- column constraint to a table constraint with identical effect — a resale row
-- carrying a null is still unstorable, it just fails 23514 instead of 23502.
-- Every one of the 12 live-rail breaks enumerated in E §2 (headed by the
-- create-payment-intent double-charge at :417-422 and the swallowed 23502 in
-- confirm-payment:243-273) REQUIRES a resale row carrying a null, and step 3
-- makes that row unstorable. The 87-site blast radius is not touched by this
-- part: no consumer is rewritten here — the constraint is simply made precise
-- enough that no consumer can ever meet a row it was not written for.
-- ----------------------------------------------------------------------------
-- WHAT THIS PART DELIBERATELY DOES NOT DO (each forbidden by name):
--   · NO column is added to public.payments — EDGE_FUNCTION_SPEC:1811-1817,
--     "No column is added to the frozen public.payments table — ever."
--     In particular NO `order_id`; the forward link lives only in
--     kernel.payment_native.order_id (085:43).
--   · NO sentinel listing and NO synthesized listing row —
--     POST_FREEZE_AMENDMENTS.md:2392 ("No fake listing row"), and E §5.2 which
--     forbids it a second time. A single sentinel would also cap the platform
--     at ONE succeeded direct sale forever via idx_payments_one_success_per_listing.
--   · NO use of the 019 anonymization sentinel user for seller_id. It buys the
--     identical RLS invisibility as NULL while making deleted-user rows and
--     venue-direct rows indistinguishable in the ledger (E §5.2).
--   · NO RLS policy is added, dropped or altered — see §4 below.
--   · NO rescope of idx_payments_one_success_per_listing — see §5 below.
--   · NO `create or replace` of venue.finalize_primary_order or any other 085
--     function. Its body needs only buyer_id, total and status (E §4), all of
--     which a direct row supplies. This is the decisive saving over option A:
--     no owner-signed authored-money-verb amendment is required.
--   · NO `NOT VALID`. H §5.3 rejects it explicitly: on 56 rows it buys nothing
--     and it opens exactly the window the ratification forbids — a period in
--     which a null is insertable with the pairing constraint not yet in force.
-- ----------------------------------------------------------------------------
-- TRANSACTION OWNERSHIP. This is a PART, not a migration. It emits no `begin;`
-- and no `commit;` — 093 is ONE apply and the three DDL facts above MUST land
-- in the same transaction as each other (ratification §E), so the assembled
-- migration owns the transaction boundary.
--
-- LOCK NOTE — THIS IS THE ONE ITEM IN 093 THAT TAKES A LOCK THAT MATTERS.
-- `public.payments` is the only LIVE table in the whole of 093 (56 production
-- rows) and the resale rail writes to it constantly (create-payment-intent,
-- stripe-webhook, enforce-transfer-expiry). Every statement below takes
-- ACCESS EXCLUSIVE: `drop not null` is catalogue-only and instant; the two
-- `add constraint` full-scan 56 rows, i.e. microseconds. The exclusive WINDOW
-- is trivial — the exclusive WAIT is not. Without a timeout this queues every
-- in-flight resale payment write behind a single slow reader. `set local
-- lock_timeout` therefore makes the migration FAIL FAST and be retried rather
-- than stall live payment writes. Per H §5.3 the setting is for the whole
-- transaction; it is emitted here, in the part that needs it, and is
-- deliberately NOT reset — if the 093 assembler hoists an identical
-- `set local lock_timeout` into its header, this line is a harmless no-op and
-- may be dropped.
-- ============================================================================

set local lock_timeout = '3s';


-- ============================================================================
-- 0. PRE-FLIGHT — assert the shape this amendment was written against
-- ----------------------------------------------------------------------------
-- The amendment was authored against 000:973/975/995 plus four purely additive
-- alterations (007 stripe_refund_id, 022 service_fee→buyer_fee + seller_fee,
-- 045 stripe_livemode). If the live catalogue is not that shape, the reasoning
-- above does not apply and we refuse rather than guess. Re-run tolerant: a
-- second application finds the columns already nullable and says so.
-- ============================================================================
do $$
declare
  v_listing_notnull boolean;
  v_seller_notnull  boolean;
  v_mode_notnull    boolean;
  v_bad             bigint;
begin
  select a.attnotnull into v_listing_notnull from pg_attribute a
   where a.attrelid = 'public.payments'::regclass and a.attname = 'listing_id'
     and not a.attisdropped;
  select a.attnotnull into v_seller_notnull  from pg_attribute a
   where a.attrelid = 'public.payments'::regclass and a.attname = 'seller_id'
     and not a.attisdropped;
  select a.attnotnull into v_mode_notnull    from pg_attribute a
   where a.attrelid = 'public.payments'::regclass and a.attname = 'mode'
     and not a.attisdropped;

  -- the exact column names are load-bearing: the pairing CHECK below names
  -- them, and 022 renamed a *different* column (service_fee→buyer_fee), so
  -- "the names are what 000 says" is a claim worth executing, not assuming.
  if v_listing_notnull is null or v_seller_notnull is null or v_mode_notnull is null then
    raise exception
      'PFA-PT-3 preflight: public.payments is missing one of listing_id/seller_id/mode — refusing to amend an unrecognised table';
  end if;

  -- mode NOT NULL is what makes the pairing CHECK below EXHAUSTIVE. A CHECK
  -- evaluates to NULL (and therefore PASSES) on a NULL input, so a nullable
  -- `mode` would silently open a third, unpaired rail. Assert it.
  if not v_mode_notnull then
    raise exception
      'PFA-PT-3 preflight: public.payments.mode is nullable — the rail-pairing CHECK would not be exhaustive';
  end if;

  if not v_listing_notnull and not v_seller_notnull then
    raise notice 'PFA-PT-3: listing_id/seller_id already nullable — re-run, proceeding idempotently';
  end if;

  -- the relaxation must start from a base that the pairing CHECK will accept.
  -- Deliberately phrased as the POST-amendment predicate, not the legacy one:
  -- on a first run every row is a resale row carrying both columns and
  -- satisfies the resale arm, and on a re-run existing direct rows satisfy the
  -- direct arm — so this stays true in both worlds. Phrasing it as "every row
  -- is legacy" would make the part fail on its own second application. It also
  -- catches an unrecognised `mode` before §1 widens the vocabulary. Without it,
  -- §3's immediate validation would fail with a bare 23514 and no reason.
  select count(*) into v_bad from public.payments
   where not (
     (mode in ('buy_now', 'auction') and listing_id is not null and seller_id is not null)
     or
     (mode = 'native_primary' and listing_id is null and seller_id is null)
   );
  if v_bad > 0 then
    raise exception
      'PFA-PT-3 preflight: % existing public.payments row(s) would fail payments_rail_pairing_ck — investigate before relaxing', v_bad;
  end if;
end $$;


-- ============================================================================
-- 1. WIDEN `mode` — admit the direct rail's label
-- ----------------------------------------------------------------------------
-- BEFORE: mode text NOT NULL check (mode in ('buy_now','auction'))   [000:995]
-- AFTER : mode text NOT NULL check (mode in ('buy_now','auction','native_primary'))
--
-- WHY 'native_primary' and not a new invented word: it is the frozen
-- PaymentIntent-metadata vocabulary. EDGE_FUNCTION_SPEC:373 specifies the
-- direct-rail PI metadata as `{ rail:'native_primary', order_id, buyer_id,
-- org_id, session_id }`, and :1206/:1211 key the webhook's new branches off
-- `metadata.rail` with `external` = existing behaviour. The column and the
-- metadata now say the same word.
--
-- WHY THIS IS SAFE TO WIDEN AT ALL — VERIFIED, not assumed: `payments.mode`
-- has **zero SQL consumers**. A grep of every migration for a `payments`-scoped
-- `mode` reference returns nothing; the only `.mode` hits in 085/088/092 are
-- `market.resale_policy.mode` (088:978-989, :1409-1415), an unrelated column.
-- Dispatch on mode happens in TypeScript over STRIPE METADATA, not over this
-- column, and 074:172-177 pins that fact in the tree: both dynamic RPC call
-- sites (stripe-webhook/index.ts:405, web/src/lib/checkout.ts:163) are "a
-- CLOSED two-branch selection on metadata.mode over exactly
-- { 'mark_listing_sold', 'complete_auction_payment' }". Nothing in the database
-- reads public.payments.mode. Adding a value to the CHECK is therefore purely
-- additive: all 56 production rows satisfy the widened form unchanged.
--
-- The constraint is located BY CATALOGUE, not by name. 000:995 authored it as
-- an inline column CHECK, so PostgreSQL named it `payments_mode_check`; we do
-- not depend on that, we find the sole check constraint whose key is exactly
-- {mode} and refuse if there is more than one.
-- ============================================================================
do $$
declare
  v_attnum smallint;
  v_conname text;
  v_n int;
begin
  select a.attnum into v_attnum from pg_attribute a
   where a.attrelid = 'public.payments'::regclass and a.attname = 'mode'
     and not a.attisdropped;

  -- conkey is int2vector; cast to smallint[] so the array equality operator is
  -- the one we mean (there is no cast the other way).
  select count(*) into v_n from pg_constraint c
   where c.conrelid = 'public.payments'::regclass
     and c.contype = 'c'
     and c.conkey::smallint[] = array[v_attnum]::smallint[];

  if v_n > 1 then
    raise exception
      'PFA-PT-3: % check constraints key ONLY public.payments.mode; 000 authored exactly one — refusing to guess which to widen', v_n;
  elsif v_n = 1 then
    select c.conname into v_conname from pg_constraint c
     where c.conrelid = 'public.payments'::regclass
       and c.contype = 'c'
       and c.conkey::smallint[] = array[v_attnum]::smallint[];
    execute format('alter table public.payments drop constraint %I', v_conname);
  end if;
  -- v_n = 0: already dropped by an interrupted run; the add below is guarded.
end $$;

do $$ begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.payments'::regclass
       and conname  = 'payments_mode_check'
  ) then
    alter table public.payments
      add constraint payments_mode_check
      check (mode in ('buy_now', 'auction', 'native_primary'));
  end if;
end $$;


-- ============================================================================
-- 2. RELAX — drop the two NOT NULLs
-- ----------------------------------------------------------------------------
-- Catalogue-only: `drop not null` clears pg_attribute.attnotnull and rewrites
-- no heap. The FOREIGN KEYS are RETAINED UNCHANGED — listing_id still
-- references public.listings(id) and seller_id still references
-- auth.users(id); a foreign key simply does not apply to a NULL, so a
-- non-null value is still forced to name a real listing / a real user.
-- Idempotent by definition — `drop not null` on an already-nullable column is
-- a no-op, not an error.
--
-- This statement, on its own, would be the dangerous change the adversarial
-- review describes. It is never on its own: §3 lands in the same transaction,
-- so there is no instant at which a null is insertable on the resale rail.
-- ============================================================================
alter table public.payments alter column listing_id drop not null;
alter table public.payments alter column seller_id  drop not null;


-- ============================================================================
-- 3. RE-IMPOSE — the rail-pairing CHECK  ← THE LOAD-BEARING STATEMENT
-- ----------------------------------------------------------------------------
-- This is the constraint that makes §2 safe. It re-imposes BOTH dropped NOT
-- NULLs conditionally, and it pins the mode to the rail in the same breath, so
-- no row can sit half-way between the two rails:
--
--   RESALE / LEGACY arm : mode in ('buy_now','auction')
--                         → listing_id NOT NULL **and** seller_id NOT NULL
--   DIRECT / PRIMARY arm: mode = 'native_primary'
--                         → listing_id IS NULL   **and** seller_id IS NULL
--
-- Exhaustive because `mode` is NOT NULL (asserted in §0) and constrained by
-- §1 to exactly those three values. Every other combination — a 'buy_now' row
-- missing a seller, a 'native_primary' row carrying a listing, a 'native_primary'
-- row carrying a seller, a resale row with a listing but no seller — is
-- rejected 23514 at INSERT. The eight-way truth table has exactly two
-- satisfying rows and they are the two rails.
--
-- NO CONTRADICTION WITH ANY EXISTING CHECK. The complete set on this table is:
--   amount > 0 · buyer_fee >= 0 · total > 0        [000:981-984]
--   seller_fee >= 0                                 [000:983 / re-added 022:42-44]
--   status in ('pending','processing','succeeded','failed','refunded') [000:991-992]
--   mode in (...)                                   [000:995, widened in §1]
-- Every one of those keys a DIFFERENT column. This constraint keys listing_id,
-- seller_id and mode, and it only ever RESTRICTS combinations that were
-- previously unreachable anyway. It cannot conflict with the money CHECKs and
-- it cannot conflict with the widened mode CHECK, of which it is a refinement.
--
-- NO `NOT VALID` — H §5.3, explicitly rejected. `add constraint` validates
-- immediately against all 56 rows (microseconds), so the constraint is in
-- force for existing rows and new rows from the instant the transaction
-- commits. §0 has already proved the validation will pass.
-- ============================================================================
do $$ begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.payments'::regclass
       and conname  = 'payments_rail_pairing_ck'
  ) then
    alter table public.payments
      add constraint payments_rail_pairing_ck
      check (
        (
          mode in ('buy_now', 'auction')
          and listing_id is not null
          and seller_id  is not null
        )
        or
        (
          mode = 'native_primary'
          and listing_id is null
          and seller_id  is null
        )
      );
  end if;
end $$;


-- ============================================================================
-- 4. THE SELLER-SIDE DISPOSITION — **NO POLICY DDL**, ASSERTED INSTEAD
-- ----------------------------------------------------------------------------
-- ADVERSARIAL_REVIEW J-2 is CORRECT that a null seller_id makes a direct row
-- invisible through `"payments: seller select" USING (seller_id = auth.uid())`
-- (000:1027-1029) — `NULL = auth.uid()` is NULL, which is not TRUE, so the row
-- never matches. It is WRONG that this needs a replacement policy. Three
-- reasons, all ratified (E §6.3, ratification §E "No organization policy is
-- added ... The existing seller policy is not destabilized"):
--
--   (a) THE INVISIBILITY IS THE CORRECT BEHAVIOUR. A venue-direct order has no
--       seller. `buyer_id` stays NOT NULL, so `"payments: buyer select"`
--       (000:1021-1023) still shows the buyer their own order payment — the
--       only client-side read that should exist on this table.
--   (b) NOTHING LOSES ACCESS IT HAS. There are zero direct client reads of
--       public.payments in /app, /src, /components, /hooks, /packages, and no
--       venue read in src/lib/venue/. Every org money read goes through
--       venue.settlement_line, kernel.payout and scoped DEFINER RPCs.
--   (c) AN ORG-SCOPED POLICY IS NOT IMPLEMENTABLE AND WOULD BREAK CI. The org
--       linkage lives in kernel.payment_native → venue."order".org_id, and
--       085:69 revokes all on kernel.payment_native from anon/authenticated, so
--       a policy could only reach it through a NEW security-definer helper.
--       And supabase/tests/010_rls_smoke.sql:42 PINS the policy count at
--       exactly 2 — a third policy fails the suite. 093's own manifest says
--       "0 new policies".
--
-- So this part ships no `create policy`, no `drop policy`, no `alter policy`.
-- What it ships instead is the ASSERTION that the invisibility holds and that
-- the frozen visibility model is intact — the guarantee made executable at
-- migration time rather than asserted only in a test file. Broadening
-- visibility is not merely avoided here; it is proved not to have happened.
--
-- NOTE — this is the one place where the drafting brief and the 093 scope memo
-- (093_FINAL_PROPOSED_SCOPE.md:58-59, "ship the seller-side policy replacement
-- in the same migration") read as asking for policy DDL, while the OWNER
-- RATIFICATION and E §6.3 forbid it. The ratification controls, and a
-- null-guard added to the existing predicate would in any case be a provable
-- no-op: `seller_id is not null and seller_id = auth.uid()` selects exactly the
-- rows `seller_id = auth.uid()` already selects, at the cost of a gratuitous
-- drop/create of a policy on a live table.
-- ============================================================================
do $$
declare
  v_policies int;
  v_nonselect int;
  v_seller_qual text;
begin
  -- 4a. the frozen count is unchanged — mirrors 010_rls_smoke.sql:42 in-migration
  select count(*) into v_policies
    from pg_policies where schemaname = 'public' and tablename = 'payments';
  if v_policies <> 2 then
    raise exception
      'PFA-PT-3: public.payments carries % RLS policies, expected exactly 2 (000 buyer+seller select) — visibility model altered', v_policies;
  end if;

  -- 4b. still SELECT-only — mirrors 010_rls_smoke.sql:48-50
  select count(*) into v_nonselect
    from pg_policies
   where schemaname = 'public' and tablename = 'payments' and cmd <> 'SELECT';
  if v_nonselect <> 0 then
    raise exception
      'PFA-PT-3: public.payments carries % non-SELECT RLS policies — client writes must remain impossible', v_nonselect;
  end if;

  -- 4c. the seller policy is byte-intact: a bare equality on seller_id, with no
  --     null-guard bolted on and no org linkage smuggled in. This is the
  --     regression guard — if a later change rewrites the predicate, 093's
  --     assertion is where it surfaces.
  select pg_get_expr(p.polqual, p.polrelid) into v_seller_qual
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'payments'
     and p.polname = 'payments: seller select';

  if v_seller_qual is null then
    raise exception 'PFA-PT-3: policy "payments: seller select" is missing from public.payments';
  end if;
  if v_seller_qual !~ 'seller_id' or v_seller_qual !~ 'auth\.uid\(\)' then
    raise exception 'PFA-PT-3: "payments: seller select" no longer reads (seller_id = auth.uid()): %', v_seller_qual;
  end if;
  if v_seller_qual ~* 'org|payment_native|is not null|is null' then
    raise exception 'PFA-PT-3: "payments: seller select" has been widened or null-guarded — forbidden by ruling E §6.3: %', v_seller_qual;
  end if;

  -- 4d. ASSERT THE INVISIBILITY ITSELF. Under SQL three-valued logic the
  --     policy predicate on a direct row is `NULL = <uuid>` → NULL, and RLS
  --     admits a row only when the qual is TRUE. A direct-rail payment is
  --     therefore invisible to every seller, by construction, with no policy
  --     change required. Executed, not merely claimed.
  if ((null::uuid = gen_random_uuid()) is true) then
    raise exception 'PFA-PT-3: NULL seller_id compares TRUE — the direct-rail invisibility guarantee does not hold';
  end if;
end $$;


-- ============================================================================
-- 5. idx_payments_one_success_per_listing — VERIFIED, NEEDS NO RESCOPING
-- ----------------------------------------------------------------------------
-- The gap matrix reported this partial unique index as a fourth blocker
-- requiring a rescope. **That report is FALSE**, and this section records the
-- verification rather than the assumption.
--
-- Read at 003_payment_integrity.sql:52-54, in full:
--
--     create unique index if not exists idx_payments_one_success_per_listing
--       on public.payments (listing_id)
--       where status = 'succeeded';
--
-- There is NO `nulls not distinct` clause. Under the default (NULLS DISTINCT)
-- a unique index treats every NULL as distinct from every other NULL, so an
-- unlimited number of succeeded rows with `listing_id IS NULL` coexist without
-- collision: the index becomes an AUTOMATIC NO-OP for direct sales, and is
-- preserved byte-for-byte for resale rows, where listing_id is still forced
-- NOT NULL by §3. Its absence here is meaningful rather than accidental — this
-- codebase uses `nulls not distinct` deliberately where it wants it (078:269,
-- 083:309), so the plain form at 003:52 is a choice.
--
-- Consequences, both correct:
--   · supabase/tests/060_payments_money.sql:38-41 ("second succeeded payment
--     for the same listing rejected, 23505") keeps passing unchanged — its
--     fixture rows are 'buy_now' rows with a real listing.
--   · Two succeeded 'native_primary' rows coexist, as they must: two different
--     direct orders are two different charges.
--
-- Therefore this part issues NO DDL against that index — dropping and
-- recreating it would take a second ACCESS EXCLUSIVE lock on the live table
-- for a change with no effect.
--
-- THE ONE NAMED RESIDUAL (E §6.4): with listing_id NULL, the equivalent
-- direct-rail invariant — one succeeded charge per ORDER — is not carried by
-- this index. It is partially covered already: payment_native_payment_uq
-- (085:56) stops one payment linking twice, and finalize_primary_order's
-- order.status='paid' short-circuit (085:1971-1980) stops a double mint. NOT
-- covered: two DISTINCT succeeded PaymentIntents for the same order, where the
-- second finalize returns idempotency_replay and leaves a stranded succeeded
-- charge with no payment_native row. Primary mitigation is the frozen
-- deterministic PI idempotency key `pi_native_${order_id}_${total}_c${customerId}`
-- (EDGE_FUNCTION_SPEC:379-381), which prevents it at the edge. The database
-- backstop E §6.4 suggests — a partial unique index on
-- kernel.payment_native (order_id) where order_id is not null — is
-- **deliberately OUT of this part and out of 093**: the 093 manifest commits to
-- "0 DDL on any money-ledger table" and kernel.payment_native is one. It is
-- carried forward as a named residual, not silently dropped.
-- ============================================================================


-- ============================================================================
-- 6. CATALOGUE COMMENTS — the amendment, recorded where the reader will be
-- ============================================================================
comment on column public.payments.listing_id is
  'Resale listing this charge is against. NULL ONLY on the venue-direct rail '
  '(mode = ''native_primary''), where the sale has no resale listing and the '
  'counterparty is an organization — the order is linked via '
  'kernel.payment_native.order_id (085:43), never by a column on this table. '
  'The NOT NULL from 000:973 is re-imposed conditionally by '
  'payments_rail_pairing_ck. POST-FREEZE AMENDMENT PFA-PT-3 (ruling E).';

comment on column public.payments.seller_id is
  'Individual seller of a resale listing. NULL ONLY on the venue-direct rail '
  '(mode = ''native_primary''): a direct order has no individual seller. NULL '
  'says that truthfully; the 019 anonymization sentinel would say it falsely '
  'and make deleted-user rows indistinguishable from venue-direct rows. A NULL '
  'here is deliberately invisible to "payments: seller select" (000:1027-1029) '
  '— see ruling E §6.3; no replacement policy exists or is wanted. The NOT NULL '
  'from 000:975 is re-imposed conditionally by payments_rail_pairing_ck. '
  'POST-FREEZE AMENDMENT PFA-PT-3 (ruling E).';

comment on column public.payments.mode is
  'Rail label. ''buy_now''/''auction'' = resale rail (000:995). '
  '''native_primary'' = venue-direct rail, matching the frozen PaymentIntent '
  'metadata vocabulary (EDGE_FUNCTION_SPEC:373, metadata.rail). This column has '
  'ZERO SQL consumers — dispatch is a closed selection on Stripe metadata in '
  'TypeScript (074:172-177), not on this column. Paired to listing_id/seller_id '
  'by payments_rail_pairing_ck. POST-FREEZE AMENDMENT PFA-PT-3 (ruling E).';

comment on constraint payments_rail_pairing_ck on public.payments is
  'PFA-PT-3 (ruling E, ratified 2026-09-02). The load-bearing half of the '
  'constrained relaxation: it re-imposes, conditionally, the two NOT NULLs that '
  '000:973/975 imposed unconditionally. Resale rail (mode in buy_now/auction) '
  'MUST carry both listing_id and seller_id; direct rail (mode = native_primary) '
  'MUST carry neither. No row can be half-way between the rails. Net loosening '
  'of the resale rail: ZERO — a resale row carrying a NULL remains unstorable, '
  'failing 23514 where it used to fail 23502. Do not drop this without also '
  'restoring the two NOT NULLs in the same transaction.';

comment on constraint payments_mode_check on public.payments is
  'PFA-PT-3: widened from 000:995''s (buy_now, auction) to admit '
  'native_primary. Purely additive — all pre-amendment rows satisfy it '
  'unchanged. Kept as a separate constraint from payments_rail_pairing_ck so '
  'the rail vocabulary and the rail pairing can be reasoned about separately.';

-- ============================================================================
-- END 093 · PART 20 — PFA-PT-3
-- Follow-ups this part creates, none of which are a runtime break and none of
-- which belong in the migration (E §6.2, §8 "Accompanying, not in the migration"):
--   · scripts/release/phase2_preflight.sql:92-94 — the M3 orphan assertion
--     ("every payment's listing exists") must be rail-scoped to
--     mode in ('buy_now','auction') or every direct row reports as an orphan.
--   · src/types/index.ts:190-213 and packages/types/src/index.ts:179-202 —
--     listing_id/seller_id become nullable, PaymentMode gains native_primary.
--     No generated database.types.ts exists in the repo, so nothing breaks at
--     compile time; the declarations are simply now incorrect.
--   · New pgTAP in a 093_* file (existing suites untouched): a native_primary
--     row with both columns NULL inserts; a buy_now row with either column NULL
--     is rejected 23514; a native_primary row carrying a listing_id or a
--     seller_id is rejected 23514; two succeeded native_primary rows coexist;
--     two succeeded buy_now rows for one listing still collide 23505; a
--     native_primary row is visible to its buyer and to NO other authenticated
--     user.
--   · Rollback (supabase/rollbacks/093_*): drop payments_rail_pairing_ck,
--     restore both NOT NULLs, restore the narrow mode CHECK — VALID ONLY WHILE
--     ZERO native_primary ROWS EXIST, with a fail-loud guard. Once real money
--     lands on the direct rail the posture is FORWARD-FIX ONLY, matching 085.
--   · Errata for the amendment record: 019_anonymized_sentinel_user.sql:6's
--     rationale ("preserves NOT NULL constraints on payments") is no longer
--     strictly true for seller_id; and the E §6.4 one-charge-per-order residual
--     above, with its edge-side mitigation.
--   · Edge-side, already scoped separately as gap-matrix F5: stripe-webhook must
--     branch on metadata.rail BEFORE :267, because its downstream reads
--     metadata.listing_id (:327/:333/:379/:385), which a direct PI does not
--     carry. This part neither creates nor mitigates that; it is required by
--     the frozen spec regardless.
-- ============================================================================
