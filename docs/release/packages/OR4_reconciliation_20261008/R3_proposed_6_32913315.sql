-- O-R4 R3: reconcile ONE historical refund into payment_refund_state.
-- Record #6 32913315 pi_3U0XuwGdOzCmGbHw0WVJfW3y. Package docs/release/packages/OR4_reconciliation_20261008.
--
-- PRODUCTION WRITE. Run only on the owner's own R3 approval, naming this file and its sha256.
-- It is one atomic statement:
--   * every guard runs before the write and every assertion after it;
--   * any failure raises, and the whole DO block rolls back.
-- Not reversible once it succeeds:
--   * payment_refund_state_log and payment_refunds are append-only;
--   * payments.stripe_refund_id and refunded_at are set-once, and amount_refunded_cents is non-decreasing
--     (guard_payment_transitions);
--   * 150's rollback guard (payment_refund_state rows = 0) stops holding.
-- Scope: one succeeded refund equal to the payment total. Any other R1 outcome (pending, failed, canceled, partial,
-- several refund objects) is refused here and needs its own plan.
do $r3$
declare
  c_payment_id  constant uuid        := '32913315-2bf7-4e58-b837-f6c5c34b722b';
  c_pi          constant text        := 'pi_3U0XuwGdOzCmGbHw0WVJfW3y';
  c_total       constant integer     := 1100;
  c_refunded_at constant timestamptz := '2026-08-04 17:20:05+00';  -- R0, UTC, to the second
  c_refund_id   constant text        := 're_3U0XuwGdOzCmGbHw0bL9UYzT';    -- R1: the refund object's id (re_...), never the ARN
  c_status      constant text        := 'succeeded';       -- R1: the REFUND object's status, never the payment badge
  c_amount      constant integer     := 1100;   -- R1: that refund object's amount
  c_source      constant text        := 'dashboard';       -- the owner's recorded decision for this row
  c_refund_count constant text       := '1'; -- R1: how many refunds the payment lists; must be 1
  c_evidence    constant text        := 'Stripe live API read 2026-10-10 acct_1T6FarGdOzCmGbHw by A: refund list for the PI count 1 has_more false, status succeeded, 1100 usd, created 2026-08-04T17:20:02Z, metadata empty so source dashboard per stripe-webhook refundSource, D blind check 78d9572a';     -- where status, id and count were read (under the sha256)
  v_pay   public.payments%rowtype;
  v_tr0   jsonb;
  v_tr1   jsonb;
  v_po0   jsonb;
  v_po1   jsonb;
  v_n     integer;
  v_res   jsonb;
begin
  -- 1. inputs: unfilled markers and out-of-scope outcomes stop here, before anything is read
  if c_refund_id !~ '^re_[A-Za-z0-9]{10,64}$' or c_refund_id ~ '^re_[0-9]+$' then
    -- shape only: an all-digit suffix (an ARN with re_ prepended) is refused; the id's origin is the evidence below
    raise exception 'R3_GUARD input: % is not a Stripe refund id', c_refund_id;
  end if;
  if c_refund_count is distinct from '1' then
    raise exception 'R3_GUARD input: refund count % is out of scope (exactly one); one call per refund needs its own plan',
      c_refund_count;
  end if;
  if c_evidence is null or length(c_evidence) < 20 or c_evidence like '\_\_%' then
    raise exception 'R3_GUARD input: evidence for the refund details is not recorded: %', c_evidence;
  end if;
  if c_status is distinct from 'succeeded' then
    raise exception 'R3_GUARD input: refund status % is out of scope (succeeded only); stop and re-plan', c_status;
  end if;
  if c_source is null or c_source not in ('expiry','dashboard','admin','unfulfillable') then
    raise exception 'R3_GUARD input: source % is not one of the four owner-decided values', c_source;
  end if;
  if c_amount is distinct from c_total then
    raise exception 'R3_GUARD input: refund amount % differs from total %; partial or split refunds need their own plan',
      c_amount, c_total;
  end if;

  -- 2. prestate: exactly the state R0 measured; anything else stops the write
  select * into v_pay from public.payments where id = c_payment_id for update;
  if not found then
    raise exception 'R3_GUARD prestate: payment % not found', c_payment_id;
  end if;
  if v_pay.stripe_payment_intent_id is distinct from c_pi then
    raise exception 'R3_GUARD prestate: payment intent is %, expected %', v_pay.stripe_payment_intent_id, c_pi;
  end if;
  if v_pay.stripe_livemode is distinct from true then
    raise exception 'R3_GUARD prestate: stripe_livemode is %; only live payments are reconciled', v_pay.stripe_livemode;
  end if;
  if v_pay.status is distinct from 'refunded' then
    raise exception 'R3_GUARD prestate: status is %, expected refunded', v_pay.status;
  end if;
  if v_pay.total is distinct from c_total then
    raise exception 'R3_GUARD prestate: total is %, expected %', v_pay.total, c_total;
  end if;
  if date_trunc('second', v_pay.refunded_at) is distinct from c_refunded_at then
    raise exception 'R3_GUARD prestate: refunded_at is %, expected %', v_pay.refunded_at, c_refunded_at;
  end if;
  if v_pay.amount_refunded_cents is not null then
    raise exception 'R3_GUARD prestate: amount_refunded_cents is %, expected NULL', v_pay.amount_refunded_cents;
  end if;
  if (v_pay.refund_requested_cents, v_pay.refund_succeeded_cents, v_pay.refund_failed_cents)
     is distinct from (0, 0, 0) then
    raise exception 'R3_GUARD prestate: refund state cents are (%, %, %), expected zeros',
      v_pay.refund_requested_cents, v_pay.refund_succeeded_cents, v_pay.refund_failed_cents;
  end if;
  if v_pay.stripe_refund_id is not null and v_pay.stripe_refund_id is distinct from c_refund_id then
    raise exception 'R3_GUARD prestate: payments.stripe_refund_id already holds %, not %',
      v_pay.stripe_refund_id, c_refund_id;
  end if;
  select count(*) into v_n from public.payment_refund_state
   where payment_id = c_payment_id or stripe_refund_id = c_refund_id;
  if v_n <> 0 then
    raise exception 'R3_GUARD prestate: % refund-state row(s) already exist for this payment or refund id', v_n;
  end if;
  select count(*) into v_n from public.payment_refunds
   where payment_id = c_payment_id or stripe_refund_id = c_refund_id;
  if v_n <> 0 then  -- hazard 1: a ledger row under another key would double-count
    raise exception 'R3_GUARD prestate: % ledger row(s) already exist for this payment or refund id', v_n;
  end if;
  select count(*) into v_n from public.transfers
   where payment_id = c_payment_id and (payout_released_at is not null or stripe_transfer_id is not null);
  if v_n <> 0 then  -- hazard 2: a paid transfer would raise REFUNDED_AFTER_PAYOUT
    raise exception 'R3_GUARD prestate: % transfer(s) of this payment carry a payout', v_n;
  end if;
  select count(*), jsonb_agg(to_jsonb(t) order by t.id) into v_n, v_tr0
    from public.transfers t where t.payment_id = c_payment_id;
  if v_n <> 1 or (v_tr0 -> 0 ->> 'status') is distinct from 'reversed' then
    raise exception 'R3_GUARD prestate: expected exactly one reversed transfer, found %: %', v_n, v_tr0;
  end if;
  -- what an after-payout flag would write (flag_payout_reversal_required): payout_decisions and payout_attempts
  select jsonb_build_object(
           'decisions', (select count(*) from public.payout_decisions d where d.payment_id = c_payment_id),
           'attempts',  (select jsonb_agg(to_jsonb(a) order by a.id) from public.payout_attempts a
                          where a.transfer_id in (select t.id from public.transfers t where t.payment_id = c_payment_id)))
    into v_po0;

  -- 3. the write: the one sanctioned writer, observed_via = reconcile
  v_res := public.record_refund_state(c_pi, c_refund_id, c_status, c_amount, null, c_source, 'reconcile');

  -- 4. postconditions: anything unexpected rolls the write back
  if (v_res ->> 'recorded') is distinct from 'true'
     or (v_res ->> 'counted') is distinct from 'true'
     or (v_res ->> 'succeeded_cents')::int is distinct from c_amount
     or (v_res ->> 'requested_cents')::int is distinct from 0
     or (v_res ->> 'failed_cents')::int is distinct from 0 then
    raise exception 'R3_ASSERT result: %', v_res;
  end if;
  select * into v_pay from public.payments where id = c_payment_id;
  if v_pay.status is distinct from 'refunded'
     or v_pay.amount_refunded_cents is distinct from c_amount
     or date_trunc('second', v_pay.refunded_at) is distinct from c_refunded_at
     or v_pay.stripe_refund_id is distinct from c_refund_id
     or (v_pay.refund_requested_cents, v_pay.refund_succeeded_cents, v_pay.refund_failed_cents)
        is distinct from (0, c_amount, 0) then
    raise exception 'R3_ASSERT payment: %', to_jsonb(v_pay);
  end if;
  select count(*) into v_n from public.payment_refund_state
   where payment_id = c_payment_id;
  if v_n <> 1 then raise exception 'R3_ASSERT state rows: %', v_n; end if;
  select count(*) into v_n from public.payment_refund_state
   where payment_id = c_payment_id and stripe_refund_id = c_refund_id and status = 'succeeded'
     and amount_cents = c_amount and source = c_source and failure_reason is null and last_observed_via = 'reconcile';
  if v_n <> 1 then raise exception 'R3_ASSERT state row content'; end if;
  select count(*) into v_n from public.payment_refund_state_log
   where payment_id = c_payment_id;
  if v_n <> 1 then raise exception 'R3_ASSERT log rows: %', v_n; end if;
  select count(*) into v_n from public.payment_refund_state_log
   where payment_id = c_payment_id and stripe_refund_id = c_refund_id and status = 'succeeded'
     and amount_cents = c_amount and observed_via = 'reconcile';
  if v_n <> 1 then raise exception 'R3_ASSERT log row content'; end if;
  select count(*) into v_n from public.payment_refunds
   where payment_id = c_payment_id;
  if v_n <> 1 then raise exception 'R3_ASSERT ledger rows: %', v_n; end if;
  select count(*) into v_n from public.payment_refunds
   where payment_id = c_payment_id and stripe_refund_id = c_refund_id and stripe_dispute_id is null
     and amount_cents = c_amount and source = c_source;
  if v_n <> 1 then raise exception 'R3_ASSERT ledger row content'; end if;
  select jsonb_agg(to_jsonb(t) order by t.id) into v_tr1 from public.transfers t where t.payment_id = c_payment_id;
  if v_tr1 is distinct from v_tr0 then
    raise exception 'R3_ASSERT transfer changed: % -> %', v_tr0, v_tr1;
  end if;
  select jsonb_build_object(
           'decisions', (select count(*) from public.payout_decisions d where d.payment_id = c_payment_id),
           'attempts',  (select jsonb_agg(to_jsonb(a) order by a.id) from public.payout_attempts a
                          where a.transfer_id in (select t.id from public.transfers t where t.payment_id = c_payment_id)))
    into v_po1;
  if v_po1 is distinct from v_po0 then
    raise exception 'R3_ASSERT payout records changed: % -> %', v_po0, v_po1;
  end if;

  raise notice 'R3_OK %', jsonb_build_object('payment_id', c_payment_id, 'refund_id', c_refund_id,
    'source', c_source, 'refund_count', c_refund_count, 'evidence', c_evidence,
    'amount_refunded_cents', v_pay.amount_refunded_cents, 'result', v_res);
end
$r3$;
