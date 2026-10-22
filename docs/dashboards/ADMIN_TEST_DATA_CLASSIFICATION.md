# Admin console: test/beta records out of the normal experience

Owner decision (2026-10-22, `OWNER_DECISIONS_20261022_PENDING_RELAY.md` §F): remove all test/beta data from the normal admin experience, classifying records only by **explicit environment/test markers and verified lineage**, never by name or appearance; preserve legitimate users and the four approved listings; keep transaction, order, refund, transfer and audit history in restricted historical views; never silently hide a real unresolved operational case; back up and report counts before and after; no irreversible purge, no ambiguous bulk deletion.

This document is the classification inventory, the exclusion rules per surface, and the server contract F asks A to implement. Nothing here is applied; A numbers and writes the migration, the owner authorises the production read and apply.

## 1. What markers exist in production (verified on the gate chain, 2026-10-22)

| Marker | Where | Values | Who set it | Verified lineage |
|---|---|---|---|---|
| `payments.stripe_livemode` | migration 045 | `true` live · `false` test · `NULL` unclassified (pre-045 rows) | Stripe, recorded by the webhook/intent path | Stripe's own assertion of the mode the charge ran in. The only explicit environment marker in the schema. |
| `public.listing_visibility` (154 = `20261015000000`) | side table, deny-all; `listing_is_public(uuid)`; `is_public` computed field | a row present = hidden from every public surface | The owner's 2026-10-15 cleanup: "all old test/beta listings disappear; only the four approved listings stay public; preserve private transaction history". 44 rows at apply (D's post-apply read) | The owner classified these listings as test/beta by that instruction; the four approved listings have no row. |

There is **no** `is_test` or environment column on `profiles`, `transfers`, `ops.case`, `reports` or `ops.action`. Their classification can only come from lineage to the two markers above.

Grepped and absent: any other `livemode`, `is_test`, `test_mode`, `sandbox`, `environment` or `beta` column in `supabase/migrations` on `fix/154` @ `d06f37f9`.

## 2. Lineage rules (confirmed test only; everything else stays visible)

A record is **test** when, and only when, one of these holds. `NULL` livemode is **unclassified, not test**: it stays in the normal views, because hiding on an unknown would be classifying by appearance.

| Kind | Test when | Not test when |
|---|---|---|
| payment | `stripe_livemode = false` | `true` or `NULL` |
| transfer | its payment is test | — |
| listing | it has a `listing_visibility` row **and** has no live (`true`) payment; or every payment on it is test | it is one of the four approved listings; it has any live payment; no marker |
| case | its subject payment/transfer/listing is test (subject-less cases are never test) | subject not test, or no subject |
| report | its target listing/user is test by the listing rule (user targets: never test) | — |
| ops.action | its subject is test by the rules above | — |
| user / profile | **never classified in this slice.** Legitimate users must be preserved and no explicit marker exists; a user whose only activity is test is still a user | — |

Rationale for listings: the 154 row alone marks "hidden from the public feed", which the owner applied to test/beta listings, but a hidden listing that carried a live payment is real history and must not leave the normal views. The live-payment check protects that.

Open cases on test subjects: D's 2026-10-13 triage counted **19 open cases: 15 test-mode p1, 1 synthetic, 3 real**. The 15 leave the default queue and Today's attention tiles but stay reachable (§3) and stay open. Closing them is an operator action the owner takes, not a side effect of this change.

## 3. Exclusion per surface, and the restricted historical view

Default = test rows excluded. A single read-time switch, **"Show test/beta records"** (platform_admin only, off by default, no persistence beyond the page URL), is the restricted historical view the owner asked for. With it on, every excluded row returns, marked **"Test-mode record"**, and nothing else changes. Writes are unaffected: an action on a test record stays possible, audited and visible in the record's own detail page by its URL.

| Surface | Default | With the switch |
|---|---|---|
| Today (`ops.today`): counts, attention cases | test cases and test payments excluded from every tile | included, counted separately |
| Cases (`list_cases`, `case_detail`) | test cases excluded from the list; a test case opened by URL renders with the badge | listed with the badge |
| Orders (`list_orders`, `order_detail`, `order_timeline`) | test payments excluded from the list and the queue counts; detail by URL renders with the badge (already shown today as "stripe test mode") | listed |
| Money (`money_overview`, `list_payouts`, `reconciliation_queue`) | test payments and their transfers excluded from every figure and bucket | included; the KPI header says "includes test records" |
| Users (`list_users`, `user_detail`) | **unchanged** (no classification) | unchanged |
| Marketplace (`list_listings`, `listing_detail`) | test listings excluded from the list; detail by URL renders with the badge | listed |
| Reports (`list_reports`) | reports on test listings excluded | listed |
| Search (`ops.search`) | test hits excluded | included |
| Actions / approvals (`list_actions`, `list_approvals`, `action_detail`) | **unchanged**: a pending approval must never disappear from the approver's queue, test subject or not | unchanged |
| System (`job_health`, alerts, settings, audit log) | unchanged; `audit_log` is history and stays whole | unchanged |
| Detectors (`detect_*`) | unchanged in this slice (they may keep opening test cases; those are excluded at read time). A later owner decision can make detectors skip test subjects. | — |
| Exports | **none exist** in the console (grepped at #121 `2fc0c8f4`: no CSV/download surface). Nothing to change. | — |

What is never hidden: any payment, transfer, refund or audit row (history stays whole in detail pages and `audit_log`); any real unresolved case (its subject is not test); any pending approval; any user.

## 4. Server contract (A writes; registry number via A — 180 / pgTAP 250 were offered, F asks before using)

No new table. No data change. One migration:
1. `ops.is_test_payment(uuid)`, `ops.is_test_transfer(uuid)`, `ops.is_test_listing(uuid)`, `ops.is_test_case(uuid)` — `stable`, `security definer`, `set search_path = ''`, implementing §2 verbatim; plus `ops.is_test_subject(kind text, id uuid)`.
2. Every read function in §3 marked "excluded" gains `p_include_test boolean default false` and applies the predicate; row payloads gain `is_test boolean` so the console can badge without a second read. Signatures stay otherwise identical (the console's existing calls keep working with the default).
3. `ops.today` returns `test_excluded` counts alongside, so the console can say "N test records hidden" without a second call.
4. A read-only **count pack** (before/after, run by A under owner authorisation): per kind, `total`, `test`, `unclassified`, `live`; the 15/1/3 case split; the 44 listing rows and how many carry a live payment.
5. pgTAP: each predicate on fixtures covering every §2 branch; `NULL` livemode never test; the four approved listing ids never test; a hidden listing with a live payment never test; an open case on a real subject always returned by default; a pending approval always returned; the switch returns every excluded row and nothing more; `audit_log` unchanged. Mutants: the `NULL` branch flipped to test; the live-payment guard dropped; the approval list filtered.
6. Rollback: restore the previous function bodies (the 116/118/144/152 definers; A pins the applied md5s). No data to restore.

Four-file rule: these are `ops` schema functions with `authenticated` execute like their neighbours; the public-schema CI manifests are unaffected (A confirms, as for 159/176).

## 5. Console contract (F, after A's contract)

- A `showTest` page-level switch (`?test=1`, platform_admin only) passed as `p_include_test` to the §3 reads; a "Test-mode record" badge from `is_test` on every row and detail that carries it (the existing `stripe_livemode === false` badge becomes the same component); the Today and Money headers state "N test records hidden" / "includes test records".
- Analytics (`MoneyCharts`, `MoneyKpis`): exclude by default, identical to the server; no local filtering, no invented figure.
- Tests: the switch defaults off; every list passes the flag; the badge renders only from `is_test`; the approvals queue never filters; RED/GREEN and mutants as usual.

## 6. Venue dashboard (F): fixtures mode unreachable in production

Today fixtures mode is the **default** when `NEXT_PUBLIC_VENUE_DATA_SOURCE` is not `database`. For a production deployment that is the wrong default: `env.ts` will refuse to start (build-time) when `NEXT_PUBLIC_VERCEL_ENV=production` and the source is not `database`, so sample data can never be served from the production host. Preview and local keep fixtures. Own small PR on #122's base, with tests.

## 7. Counts to report (A reads; owner authorises)

Before: the §4 count pack on production. After the migration applies: the same pack (totals unchanged, since nothing is deleted or modified), plus the default-view counts per surface (what the console now shows) against the switch-on counts (what it shows with the historical view). Backup: A's standard pre-apply dump/snapshot before the apply, as for 152–156.

## 8. Not in scope here
- Deleting or modifying any row (no purge, no bulk edit).
- Classifying users.
- Detector behaviour (a later decision).
- The sandbox and local harness rows labelled `harness:` (they exist only in private local copies, never in production).
