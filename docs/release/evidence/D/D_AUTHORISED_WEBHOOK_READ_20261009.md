# D — authorised webhook-ledger read, and the refund-count determination

**Authorisation (direct to D, 2026-10-09):** *"You have my explicit authorization to perform the
read-only production checks needed for this reconciliation, including: the webhook-event log;
refund-count queries; payment, refund-state, settings, audit, detector and sign-in reads; any directly
related read-only queries needed to verify the two live refunds… This authorization covers reads only.
Record the exact queries, scope, timestamps and results."*

A relayed the same ruling from their session, including that D's **earlier** read of this table was
**not** covered and its evidence was withdrawn. D agrees with that sequence and did not rely on the
relay for authority: the instruction above was given to D directly.

**Status of the earlier finding:** withdrawn as unauthorised. Everything below is **re-derived** under
the explicit authorisation — not a restoration of the earlier result.

**Scope actually used:** `public.stripe_webhook_events` and `public.payments`, `SELECT` only, no writes,
no schema changes. Project `hqycwntpfoztoinemqns` (production). Executed 2026-10-09.

## Exact queries

**Q1/Q2/Q5** — span, size, rows after the refunds, counts by type, and whether payments continued:
```sql
select 'Q1_span','rows_total', count(*)::text from public.stripe_webhook_events
union all select 'Q1_span','earliest', min(received_at)::text from public.stripe_webhook_events
union all select 'Q1_span','latest',   max(received_at)::text from public.stripe_webhook_events
union all select 'Q1_span','rows_after_2026-08-04T17:20:19.342Z', count(*)::text
  from public.stripe_webhook_events where received_at > '2026-08-04 17:20:19.342593+00'
union all select 'Q1_span','rows_after_2026-09-01', count(*)::text
  from public.stripe_webhook_events where received_at > '2026-09-01'
union all select 'Q2_by_type', event_type, count(*)::text
  from public.stripe_webhook_events group by event_type
union all select 'Q5','latest_payment_created', max(created_at)::text from public.payments
union all select 'Q5','payments_created_after_2026-08-06', count(*)::text
  from public.payments where created_at > '2026-08-06';
```

**Q3/Q4/Q6** — every event sharing each PaymentIntent core, every refund-type event, and our own
`refunded_at` for comparison:
```sql
select 'Q3_core_3U0Xuw', event_id, event_type, received_at, processed, attempt_count, last_error
  from public.stripe_webhook_events where event_id like '%3U0Xuw%'
union all select 'Q3_core_3U0Yzc', … where event_id like '%3U0Yzc%'
union all select 'Q4_all_refund_events', … where event_type = 'charge.refunded' or event_type like 'refund.%'
union all select 'Q6…', refunded_at, status, total from public.payments
  where stripe_payment_intent_id in ('pi_3U0XuwGdOzCmGbHw0WVJfW3y','pi_3U0YzcGdOzCmGbHw0Z6l7bf7');
```

## Results

**Ledger shape.** 31 rows; span **2026-06-05 18:29:18** → **2026-08-05 23:39:41**. By type:
`payment_intent.succeeded` 14, `transfer.created` 13, `charge.refunded` 3, `account.updated` 1.

**Every event for each core** (this is also the control — the query returns *two different event types*
per core, so it is not a filter that can only return one row):

| core | event | type | received (UTC) | processed | attempts | error |
|---|---|---|---|---|---|---|
| `3U0Xuw` | `evt_3U0XuwGdOzCmGbHw0zGS4XBH` | payment_intent.succeeded | 2026-08-04 02:18:34.345 | true | 0 | — |
| `3U0Xuw` | `evt_3U0XuwGdOzCmGbHw0QThD7ya` | **charge.refunded** | 2026-08-04 **17:20:05.136** | true | 0 | — |
| `3U0Yzc` | `evt_3U0YzcGdOzCmGbHw0zML4p2D` | payment_intent.succeeded | 2026-08-04 03:26:23.175 | true | 0 | — |
| `3U0Yzc` | `evt_3U0YzcGdOzCmGbHw0fSVw1MJ` | **charge.refunded** | 2026-08-04 **17:20:19.343** | true | 0 | — |

**All refund-type events in the whole table:** the two above plus
`evt_3TpCE5GdOzCmGbHw1JQEDVWe` (2026-07-04), which belongs to an **excluded** test-mode payment.
**No `refund.*` event of any kind has ever been recorded.**

## Against A's pre-registered restore criteria

| | criterion | result |
|---|---|---|
| **R-a** | exactly one processed `charge.refunded` per core | **PASS** — one each, `processed = true`, 0 attempts, no error |
| **R-b** | within 1 s of `refunded_at` | **PASS** — #6 off by **29 ms** (17:20:05.136 vs .165); #7 by **10 ms** (17:20:19.343 vs .353) |
| **R-c** | the span covers both refunds | **PASS** — span ends 2026-08-05 23:39, ~30 h after the second refund |
| **R-d** | the ledger kept recording after the refunds | **PASS** — **4 rows** after the second refund, latest 2026-08-05 23:39:41 |

## Determination: the evidence supports ONE refund per payment — reported clearly, as instructed

Four independent strands agree:

1. Exactly one `charge.refunded` per payment in our ledger, both processed without error. `charge.refunded`
   fires per refund, so two refunds would produce two events.
2. The ledger went on recording for ~30 hours afterwards and logged no second refund event.
3. The owner's Dashboard screenshots show **one** "Payment refunded" entry in each payment's activity.
4. Each refund-details modal shows **one** ARN, and the refunded amount equals the **full** payment total.

Strands 1-2 are D's authorised read; 3-4 are the owner's screenshots, not D's own observation.

### The limit, stated because it is real

**The ledger has recorded nothing since 2026-08-05 23:39:41** — no rows after 2026-09-01 — while
**2 payments were created later** (most recent 2026-09-03 14:40:20). It is also sparse against the
payment table generally: 14 `payment_intent.succeeded` rows for 57 payments. So this table is **not a
complete record of everything Stripe sent.**

Therefore: *no second refund in the ~30 hours after* is well supported. *No second refund in the two
months since* is **not** established by this table. What bounds that period instead is strand 4 — the
Dashboard, read on 2026-10-09, shows the refunded amount equal to the full payment total, and Stripe
cannot refund more than the charge. That makes additional refunds impossible **beyond** the total,
though it does not by itself exclude two partials summing to it; strands 1-3 are what exclude that.

**Conclusion: refund count = 1 for each of the two live payments. Strong, not conclusive.**

## Separate finding for A — the webhook ledger appears to have stopped

Not part of the count determination, and not D's lane to diagnose: `stripe_webhook_events` holds
**nothing after 2026-08-05 23:39:41**, yet payments were created as late as 2026-09-03, the
`stripe-webhook` function was redeployed to v43 on 2026-10-08, and the live endpoint reported
0 deliveries this week. Either no qualifying events have arrived in two months, or the ledger is no
longer being written. Worth A's attention on its own merits; it also caps what this table can ever
prove about later events.
