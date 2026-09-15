-- ============================================================================
-- 126_ops_console_refund_exactness.sql — the ops console can state a refunded
-- AMOUNT, because one now exists locally.
--
-- NUMBER. Written as `126`, the number the registry currently records. A
-- reassignment to `129` is PROPOSED and awaiting the owner, so that `127`/`128`
-- (security fixes) are not held behind this. If that is approved this file is
-- renamed — content unchanged, no other edit.
--
-- WHY THIS IS POSSIBLE NOW. `120` deliberately refuses to state an amount:
-- `refunded_cents = null`, `refunded_certainty = 'uncertain'`, and an upper
-- bound of Σ `payments.total` over refunded rows. That was right at the time —
-- nothing local recorded the amount, and `charge.refunded` fires for PARTIAL
-- refunds too, so summing `total` overstated a $10 refund on a $100 payment
-- tenfold. Since then `20260906120000` added `public.payment_refunds` (append
-- only), `payments.amount_refunded_cents`, and `record_payment_refund`. The
-- amount is recorded, so the console can stop saying "unknown".
--
-- ONE DEFINITION, TWO CALLERS. `ops.refund_facts` is the only place refund
-- semantics are expressed; `build_daily_summary` and `money_overview` map its
-- result into their own key names. Defining them separately in two functions is
-- exactly how the console ends up showing two versions of the truth.
--
-- ACCEPTANCE CASES A1–A8 (CONVERGENCE_135_REPORT.md:541-548 — §8 of the release
-- package previously cited §14, which does not contain them):
--   A1 partial refund        -> exact cents, certainty 'known', partial_count 1
--   A2 full refund           -> exact cents, full_count 1
--   A3 two partials, one pmt -> cents summed, the PAYMENT counted once
--   A4 refund outside window -> excluded here, included all-time
--   A5 no refunds at all     -> 0 with certainty 'known' (a known zero, not an unknown)
--   A6 legacy stored summary -> stays 'uncertain' + legacy_normalized, never re-labelled
--   A7 payment_refunds absent-> 120's uncertain shape, no error
--   A8 chargeback            -> counted exactly once, not doubled with the refund path
--
-- A8 works because the ledger carries BOTH `stripe_refund_id` and
-- `stripe_dispute_id` with `payment_refunds_payment_dispute_uniq` deduplicating
-- disputes, so each event is one row and summing rows cannot double-count.
--
-- A6 needs no change: `normalize_summary_body` passes through any body that
-- already carries `refunded_certainty`, and only rewrites legacy numeric bodies
-- into the uncertain shape. A stored 'known' body is therefore left alone and a
-- legacy body is never promoted. pgTAP 193 asserts both directions.
--
-- FULL vs PARTIAL is judged on the PAYMENT's cumulative refund
-- (`amount_refunded_cents >= total`), not on the window's slice, so a payment
-- finished off by a later refund reads as full even when only the last part
-- landed in this window.
--
-- ONE DELIBERATE BOUNDARY CHANGE, recorded rather than slipped in:
-- `build_daily_summary` counted refunds with a CLOSED upper bound
-- (`refunded_at <= v_to`) while `money_overview` used a half-open one
-- (`< hi`). `refund_facts` is half-open, which is the correct convention for a
-- day range and makes the two agree. The practical effect is one microsecond at
-- the end of a UTC day.
--
-- Applied nowhere by this file. Census +1 function.
-- ============================================================================
begin;

-- ── 1. The one definition ───────────────────────────────────────────────────
create or replace function ops.refund_facts(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cents    bigint;
  v_payments integer;
  v_full     integer;
  v_partial  integer;
begin
  -- A7: a database replayed before the RC has no ledger. Keep 120's shape and
  -- say why, rather than raising — the console must still render.
  if to_regclass('public.payment_refunds') is null then
    select coalesce(sum(p.total), 0), count(*)
      into v_cents, v_payments
      from public.payments p
     where p.status = 'refunded' and p.refunded_at >= p_from and p.refunded_at < p_to;
    return jsonb_build_object(
      'cents', null, 'count', v_payments, 'upper_bound_cents', v_cents,
      'partial_count', null, 'full_count', null,
      'certainty', 'uncertain',
      'source', 'public.payments', 'basis', 'refunded_at, UTC, half-open',
      'note', 'amount not available: public.payment_refunds is absent, so only refund STATUS is known. upper_bound_cents = the sum of payments.total over refunded rows; the true amount may be lower.');
  end if;

  -- A1/A3/A4/A8. One row per refund EVENT, windowed on the LEDGER's own
  -- created_at (A4), so two partials on one payment sum (A3) while the payment
  -- is counted once, and a chargeback -- deduplicated by
  -- payment_refunds_payment_dispute_uniq -- is counted exactly once (A8).
  select coalesce(sum(r.amount_cents), 0), count(distinct r.payment_id)
    into v_cents, v_payments
    from public.payment_refunds r
   where r.created_at >= p_from and r.created_at < p_to;

  -- A1/A2. Cumulative, not per-window: see the header.
  select count(*) filter (where p.amount_refunded_cents >= p.total),
         count(*) filter (where p.amount_refunded_cents <  p.total)
    into v_full, v_partial
    from public.payments p
   where p.id in (select r.payment_id from public.payment_refunds r
                   where r.created_at >= p_from and r.created_at < p_to);

  -- A5: an empty window is a KNOWN zero, not an unknown. The console must be
  -- able to say "$0.00" rather than "amount not recorded".
  return jsonb_build_object(
    'cents', v_cents, 'count', v_payments, 'upper_bound_cents', v_cents,
    'partial_count', coalesce(v_partial, 0), 'full_count', coalesce(v_full, 0),
    'certainty', 'known',
    'source', 'public.payment_refunds', 'basis', 'ledger created_at, UTC, half-open',
    'note', 'exact: summed from the append-only refund and chargeback ledger.');
end;
$$;

comment on function ops.refund_facts(timestamptz, timestamptz) is
  '126: the single definition of refunded money for the ops console. Sums public.payment_refunds over the window (each refund and chargeback is one row, disputes deduplicated), counts the PAYMENTS touched once each, and splits full from partial on the payment''s cumulative refund. certainty ''known'' once the ledger exists; falls back to 120''s ''uncertain'' shape when it does not, without raising.';

revoke execute on function ops.refund_facts(timestamptz, timestamptz) from public, anon, authenticated;
grant  execute on function ops.refund_facts(timestamptz, timestamptz) to service_role;

commit;
