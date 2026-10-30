-- ============================================================================
-- 142_payments_amount_refunded_cents.sql — the column the candidate app reads
-- (go/no-go for 8f45e9b, shape A′; owner authorised local authoring 2026-09-18)
--
-- WHY. The candidate client selects `payments.amount_refunded_cents` in both of
-- checkout's settled-payment reads (src/screens/checkout/CheckoutNative.tsx:228
-- and :595). Production has no such column: 20260906120000, which creates it, is
-- part of the payments RC and is not in this release. PostgREST answers that
-- select with 400 (42703), the client discards the error, and a buyer who has
-- already paid is treated as unpaid (D's column break).
--
-- WHAT. The column only — the exact DDL of 20260906120000 (§3, line 306), so the
-- two can apply in either order and leave the same column: `int`, nullable, no
-- default, no constraint. `IF NOT EXISTS` makes the later of the two a no-op; the
-- post-check below refuses to continue over a same-named column of any other
-- shape, which IF NOT EXISTS alone would silently accept.
--
-- NULL = unknown. NEVER BACKFILLED. Production's refund writer (the deployed
-- stripe-webhook, charge.refunded) sets status 'refunded' and `refunded_at` on
-- any refund, partial or full, and records no amount. An existing refunded row's
-- amount is therefore not known here, and inventing `total` would turn a partial
-- refund into a full one. 20260906120000 takes the same position ("a refund we
-- did not observe is not a fact we may invent"). The client must read NULL as
-- "amount unknown", never as "fully refunded" — that client change ships with
-- this release.
--
-- NOT HERE. No writer, trigger, index or grant. The monotonic trigger and
-- `record_payment_refund` stay with 20260906120000.
--
-- GRANTS / RLS. Unchanged. `public.payments` has table-level grants only (no
-- column-level grants), so the new column is covered by the existing SELECT;
-- RLS is buyer-own / seller-own SELECT with no client INSERT or UPDATE policy,
-- so no client can write it. The grant-decision manifest, the Gate-2 census and
-- expected_grants.txt do not move (no table, function, policy or trigger added;
-- grants are table-level).
--
-- COST. Adding a nullable column with no default is a catalog-only change:
-- ACCESS EXCLUSIVE for the duration of the ALTER, no table rewrite
-- (relfilenode unchanged — proven in the rehearsal). lock_timeout makes a busy
-- table fail the apply cleanly instead of queueing every payments read behind it.
--
-- ROLLBACK: supabase/rollbacks/142_payments_amount_refunded_cents_rollback.sql —
-- refuses once any row carries a value or once 20260906120000 is applied. Its
-- cutoff is the release of the app build that selects this column: after that,
-- dropping the column re-creates the column break for every installed copy.
--
-- pgTAP: supabase/tests/209_payments_amount_refunded_cents.sql.
-- ============================================================================
begin;

set local lock_timeout = '3s';

alter table public.payments add column if not exists amount_refunded_cents int;

-- The shape IF NOT EXISTS cannot promise.
do $$
declare
  v_type text; v_nullable text; v_default text;
begin
  select c.data_type, c.is_nullable, c.column_default
    into v_type, v_nullable, v_default
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'payments'
     and c.column_name = 'amount_refunded_cents';
  if v_type is distinct from 'integer' or v_nullable is distinct from 'YES' or v_default is not null then
    raise exception '142: public.payments.amount_refunded_cents exists as (type %, nullable %, default %) — expected (integer, YES, none)',
      v_type, v_nullable, coalesce(v_default, 'none');
  end if;
end $$;

commit;
