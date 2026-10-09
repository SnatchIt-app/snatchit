-- O-R4 R4: read-only read-back for records #6 and #7, before and after R3. SELECT only.
-- Before R3 it must equal R0 (refund cents zero, amount_refunded_cents NULL, no state, log or ledger rows).
-- After R3, per record: one succeeded state row (via reconcile), one log row, one ledger row with the owner's source,
-- amount_refunded_cents = total, refunded_at unchanged, the transfer unchanged, and no case.
select p.id::text                                                         as payment_id,
       p.stripe_payment_intent_id                                         as pi,
       p.stripe_livemode                                                  as live,
       p.status,
       p.total,
       p.amount_refunded_cents,
       p.refund_requested_cents                                           as req,
       p.refund_succeeded_cents                                           as ok,
       p.refund_failed_cents                                              as failed,
       p.stripe_refund_id,
       to_char(p.refunded_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') as refunded_at_utc,
       (select jsonb_agg(jsonb_build_object('re', s.stripe_refund_id, 'status', s.status, 'amount', s.amount_cents,
                                            'source', s.source, 'via', s.last_observed_via) order by s.stripe_refund_id)
          from public.payment_refund_state s where s.payment_id = p.id)    as state,
       (select count(*) from public.payment_refund_state_log l where l.payment_id = p.id) as log_rows,
       (select jsonb_agg(jsonb_build_object('re', r.stripe_refund_id, 'amount', r.amount_cents, 'source', r.source)
                         order by r.stripe_refund_id)
          from public.payment_refunds r where r.payment_id = p.id)         as ledger,
       (select jsonb_agg(jsonb_build_object('status', t.status, 'payout_released_at', t.payout_released_at,
                                            'has_stripe_transfer', t.stripe_transfer_id is not null,
                                            'payout_review_status', t.payout_review_status) order by t.id)
          from public.transfers t where t.payment_id = p.id)               as transfers,
       (select count(*) from ops."case" c
         where c.subject_id = p.id
            or c.subject_id in (select t.id from public.transfers t where t.payment_id = p.id)
            or c.subject_ref in (select s.stripe_refund_id from public.payment_refund_state s
                                  where s.payment_id = p.id))              as cases
  from public.payments p
 where p.id in ('32913315-2bf7-4e58-b837-f6c5c34b722b', '700d469b-045c-430f-8d16-351d9ff3b838')
 order by p.total desc;
