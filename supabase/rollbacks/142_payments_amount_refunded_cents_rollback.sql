-- ============================================================================
-- 142_payments_amount_refunded_cents_rollback.sql
-- Reverses 142_payments_amount_refunded_cents.sql (drops the column).
--
-- CUTOFF — READ BEFORE RUNNING. This is safe only BEFORE the app build that
-- selects `payments.amount_refunded_cents` is released. Once that build is
-- installed anywhere, dropping the column brings back the column break: both
-- checkout reads return 400, the client discards the error, and a buyer who has
-- paid is treated as unpaid. After release, fix forward instead.
--
-- It refuses, changing nothing, when:
--   R1  20260906120000 is applied (public.payment_refunds exists). The column
--       then belongs to the payments RC, and so do its trigger, its writer and
--       the rows they wrote. Roll that back through its own rollback instead
--       (which drops this column too).
--   R2  any row carries a non-NULL amount. Dropping the column would destroy a
--       recorded refund amount that nothing else holds.
-- Otherwise the column holds only NULLs: nothing was ever written there, and
-- dropping it loses no data.
-- ============================================================================
begin;

set local lock_timeout = '3s';

do $$
declare
  v_filled bigint;
begin
  if to_regclass('public.payment_refunds') is not null then
    raise exception '142 rollback refused (R1): 20260906120000 is applied; the column belongs to the payments RC now — use its rollback';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'payments'
                and column_name = 'amount_refunded_cents') then
    execute 'select count(*) from public.payments where amount_refunded_cents is not null' into v_filled;
    if v_filled > 0 then
      raise exception '142 rollback refused (R2): % payment row(s) carry amount_refunded_cents; dropping the column would destroy them', v_filled;
    end if;
  end if;
end $$;

alter table public.payments drop column if exists amount_refunded_cents;

commit;
