# Admin analytics — data contract (2026-09-14)

Every number the redesigned Today overview and Money analytics page show, where it comes from, what window it
covers, and what the UI does when the data is incomplete. **No migration, view, index or `ops` function change is
made on `admin/analytics-redesign`**; items that need one are listed under *Dependencies* for release integration.

Principles: USD only · UTC calendar days · measures are never netted against each other · an unknown value renders
as unknown, never as `0` · a chart point is a database aggregate over that exact period, never interpolated or
derived from a current total.

## 1. Business measures — `ops.money_overview(p_from date, p_to date)` (migration 116/118/120)

| On screen | Definition (as the function computes it) | Window / basis | Incomplete data → UI |
|---|---|---|---|
| **Captured sales (incl. buyer fees)** | Σ `payments.total`, `status ∈ (succeeded, refunded)` | `paid_at` in [from, to+1) UTC | RPC failure → error state. Refunds are **not** subtracted (labelled). |
| **Platform fees (gross, before refunds)** | Σ `buyer_fee + coalesce(seller_fee,0)`, `status = succeeded` | `paid_at` UTC | Labelled gross; never called net revenue. Fees on payments later refunded drop out (status ≠ succeeded) — stated in the definition. |
| **Fully refunded payments** (count) | count of `payments` with `status = refunded`; amount: `value_cents = null`, `certainty = 'uncertain'`, `upper_bound_cents = Σ total` | `refunded_at` UTC | **Labelled "fully refunded", not "refunds"** (A's correction): the newer writer `public.record_payment_refund` (20260906120000) sets `status = refunded` only when the refund covers the whole total, so a partial refund keeps `status = succeeded`, `refunded_at` null — it is absent from this count and the bound, and still counted in full in captured sales. The tile says so. Amount, three designed states: **unknown** (today): "Amount not recorded — at most $X"; **known** (`certainty = 'exact'`): the amount; **mixed**: known sum and the "at most" remainder shown separately, never added. The true refund count (incl. partials, e.g. `refunded_partial_count`) arrives with refund exactness. |
| **Seller funds released** | Σ `payments.amount − coalesce(seller_fee,0)` for transfers with `stripe_transfer_id` set | `payout_released_at` UTC | Labelled "to connected accounts — not a bank payout". |
| **Seller funds pending release** | same share, transfers in `seller_sent / buyer_confirmed / auto_released`, no Stripe transfer, payment succeeded | **point in time** (now), ignores the range | Labelled "now", excluded from period comparison and charts. |
| **Bank payouts** | not tracked (`basis = 'not_tracked'`) | — | Shown as "Not tracked" with the reason; never a number. |
| **Change vs previous period** | the same function over the equal-length range immediately before | e.g. 30 d vs the 30 d before | Previous = 0 → "none in previous period" (no % ). Either side unknown → "no comparison". Refund change is on the **count**. |
| **Freshness** | `computed_at` returned by the function (live query) | per request | Oldest point's `computed_at` bounds a series; > 15 min → "stale" badge; missing → "unknown", never "fresh". |

### Trends — interim read path

No time-series read exists. A trend is **one `ops.money_overview` call per bucket**: per UTC day for ranges ≤ 31
days, per Monday-start week (clipped to the range) up to 366 days — at most 31 or 53 calls, 6 concurrent. Each
point is a genuine aggregate over that period. **If any bucket fails, the chart shows an error, not a gap.** The
current UTC day is partial and labelled "today so far".

### Interim cost — measured (local, PostgreSQL 17, synthetic volume, 8 s statement timeout, 2026-09-14)

One `ops.money_overview` call as the harness operator, today's schema (no index on `payments.paid_at`,
`payments.refunded_at`, `transfers.payout_released_at`), realistic pending set (0.1 % of transfers):

| Payments | 1 day | 7 days | 30 days | 366 days | 30-point daily trend (6 concurrent) |
|---|---|---|---|---|---|
| ~10 k | 36 ms (160 ms cold) | 36 ms | 36 ms | 36 ms | well under 1 s |
| ~100 k | 197 ms | 183 ms | 222 ms | 237 ms | ≈ 6 s of work, ≈ 1–1.5 s wall |
| ~1 M | 744 ms | 704 ms | 907 ms | 1.8 s | ≈ 20–50 s of work — **not viable** |

Findings: (1) every call also runs the point-in-time *seller funds pending* join, which a per-bucket series
repeats and discards — with an unrealistic 40 % pending set it alone took 1.7 s at 1 M rows; (2) with candidate
date indexes short ranges drop to 0.4–1.1 s at 1 M rows but the pending join remains; (3) no single call
approached the 8 s timeout. (4) Correctness, not only cost: *seller funds pending* has no date predicate
(`from`/`to` null, basis `now()`), so rendered per bucket it would show today's pending on every day — which is
why it is excluded from charts, comparisons and AN-1.

**Conclusion — conditional.** The interim path is acceptable **at the volumes measured here, which are not
production's**: production's payment count has not been read (the sandbox has 51 rows; a read of production needs
the owner's authorization — A will ask). If production is well below ~50 k payments the interim is fine; at ~100 k a
30-point trend costs ≈ 6 s of database work; at ~1 M it is not viable. AN-1 (one set-based query, no point-in-time
pending, the three date indexes) should land before production reaches ~100 k payments — re-check this line
whenever the count is known. The measurement database was a throwaway copy and has been dropped.

## 2. Operational counts — `ops.today()` (migration 116) — unchanged

`metrics.*`: `open_cases`, `transfers_overdue`, `transfers_due_6h`, `evidence_due_72h`, `stripe_disputes_open`,
`disputes_open`, `refunds_pending`, `paid_unsettled`, `payout_review`, `jobs_failing`, `webhook_backlog`,
`approvals_pending`, `alerts_firing`, `reports_pending` — each point-in-time, definitions as already shown on
Today. `attention[]`: open cases ordered by priority, due date, detection time (≤ 200). Failure → the existing
`OpsFailureAlert`; business analytics never replace or hide this section, and render after it.

## 3. Dependencies for release integration (A) — none are required for the preview

| Id | Need | Why | Shape / notes |
|---|---|---|---|
| **AN-1** (recommended; approved in principle by A — **number assigned by A later, not chosen on a branch**) | `ops.money_timeseries(p_from, p_to, p_grain)` — read-only, `security definer`, `assert_reader()`, `search_path = ''` | Replace N interim calls with one set-based query; must land before ~100 k payments (see measured cost) | `generate_series` buckets left-joined to the **same definitions above**, **without** the point-in-time pending join; rows `{bucket_from, bucket_to, captured_cents, captured_count, fees_cents, fees_count, refunded_count, refunded_upper_bound_cents, refunded_known_cents, refunded_certainty, released_cents, released_count}` + `computed_at`; zero-filled; range ≤ 400 d; day grain ≤ 92 d. **Carries** the indexes on `payments(paid_at)`, `payments(refunded_at)`, `transfers(payout_released_at)` (A confirmed none exist). Reviewed together with refund exactness so refund fields (incl. partial-refund counts from the ledger) take one definition. |
| **AN-2** | Refund amounts (known) | Today every refund amount is unknown (migration 120) | Blocked on the refund-exactness migration (proposed renumber 126 → 129). The UI already renders known / unknown / mixed; no change to `120` semantics requested. |
| **AN-3** | Net platform revenue | Fees minus fees returned by refunds | Not shown. Needs AN-2 plus a definition of how fees are attributed on partial refunds. |
| **AN-4** | Ticket sales excluding buyer fees (Σ `payments.amount`) | "Captured sales" includes buyer fees | Not shown; would be a field on AN-1 (or `money_overview`). Optional. |
| **AN-5** | Bank payouts | Stripe-side; `payout.paid` only logged | Out of scope; stays "Not tracked". |

## 4. Preview data

Browser previews run against the **local synthetic harness** (`admin/scripts/local-stack.sh`: 13 fixture payments,
11 transfers). Every preview page carries a visible "Sample data" notice. No hosted project was read.
