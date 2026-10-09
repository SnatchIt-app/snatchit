-- O-R4 R1b: the webhook-ledger read the owner authorised for D on 2026-10-09 ("read-only webhook-event-log and
-- refund-count queries required for reconciliation"). Run by D only. SELECT only, each as its own read-only request.
-- It authorises reads, not writes. The restore criteria are in README §"Refund count: restore path", written before
-- any of these ran.
-- Table: public.stripe_webhook_events (025; 064 added claimed_at, failed_at, attempt_count). It has no payload, so no
-- refund id can come from it.

-- Q1: ledger span and size. Control: the ledger holds rows across 2026-08-04, and shows whether it kept recording after.
select count(*)                                    as total_rows,
       count(*) filter (where processed)           as processed_rows,
       min(received_at)                            as first_received,
       max(received_at)                            as last_received,
       count(*) filter (where received_at > '2026-08-04 17:20:19.342+00') as rows_after_the_two_refunds
  from public.stripe_webhook_events;

-- Q2: by type.
select event_type, count(*) as n, min(received_at) as first_received, max(received_at) as last_received
  from public.stripe_webhook_events
 group by event_type
 order by event_type;

-- Q3: every event whose id shares #6's or #7's PaymentIntent core. Positive control: the other events of those two
-- payment flows (for example payment_intent.succeeded) also reached the ledger.
select event_id, event_type, received_at, processed, processed_at, attempt_count
  from public.stripe_webhook_events
 where event_id like 'evt\_3U0XuwGdOzCmGbHw%' or event_id like 'evt\_3U0YzcGdOzCmGbHw%'
 order by received_at;

-- Q4: every charge.refunded and refund.* event, all time.
select event_id, event_type, received_at, processed, processed_at
  from public.stripe_webhook_events
 where event_type = 'charge.refunded' or event_type like 'refund.%'
 order by received_at;
