# A — Stripe Flow Map (Agent A)

**Scope:** the truthful, evidence-based map of how money actually moves through Snatch It today,
compared against current official Stripe capability.
**Repo:** `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2`
**Method:** every Part 1 claim is a `file:line` citation from code actually present on this branch.
Table names and doc prose were NOT treated as evidence. Every Part 2 claim carries a docs.stripe.com URL.
**Non-goal:** this file makes NO recommendation. Model selection is another agent's ruling.

---

## PART 0 — THE ONE-LINE ANSWER

Snatch It today runs **separate charges and transfers** (Stripe's term), in its degenerate,
platform-only form:

- the card is charged **on the platform account** with a bare PaymentIntent — no Connect
  parameter of any kind is set;
- the seller is paid **later and separately** by a `POST /v1/transfers` funded with
  `source_transaction`;
- the connected account is an **Express account with only the `transfers` capability requested** —
  it is structurally incapable of accepting a charge.

Snatch It is the **merchant of record for 100% of money taken**, on both the resale rail (live)
and the Phase-2 primary rail (dark).

---

## PART 1 — WHAT THE CODE ACTUALLY DOES

### 1.1 The shared Stripe client

`supabase/functions/_shared/stripe.ts` is the only path to `api.stripe.com` in the edge runtime.

- `supabase/functions/_shared/stripe.ts:59-83` — `stripeFetch()`; headers are exactly
  `Authorization: Bearer STRIPE_SECRET_KEY`, `Stripe-Version`, and optionally `Content-Type`
  and `Idempotency-Key`.
- `supabase/functions/_shared/stripe.ts:90-108` — `stripeFetchRaw()`, same header set.
- `supabase/functions/_shared/stripe.ts:34` — API version pinned at `2024-09-30.acacia`.
- `supabase/functions/_shared/stripe.ts:35` — mobile/ephemeral-key version `2024-04-10`.

**FINDING (structural):** neither helper accepts, forwards, or can express a `Stripe-Account`
header. There is no `stripeAccount` option, no per-request header passthrough, and the
`StripeFetchInit` type (`_shared/stripe.ts:37-45`) has no field for one. **Acting as a connected
account is not merely unused — it is unrepresentable in the current client.**

### 1.2 Every PaymentIntent creation site

There are **two** `POST /v1/payment_intents` call sites, both in one function, both sending the
**same body object**:

- `supabase/functions/create-payment-intent/index.ts:531-535` — primary create.
- `supabase/functions/create-payment-intent/index.ts:541-545` — the "idempotency replay returned a
  canceled PI" retry, re-sending the identical `piBody` under a UUID-salted key.

The body is defined once at `create-payment-intent/index.ts:513-527` and is, in full:

| param | value | line |
|---|---|---|
| `amount` | `String(totalCents)` (base + 10% buyer fee) | `:514` |
| `currency` | `'usd'` | `:515` |
| `automatic_payment_methods[enabled]` | `'true'` | `:516` |
| `customer` | platform-account Customer id | `:517` |
| `setup_future_usage` | `'on_session'` | `:522` |
| `metadata[listing_id]` | listing uuid | `:523` |
| `metadata[buyer_id]` | buyer uuid | `:524` |
| `metadata[seller_id]` | seller uuid | `:525` |
| `metadata[mode]` | `buy_now` \| `auction` | `:526` |

That is the entire parameter set. **No `transfer_data`. No `on_behalf_of`. No
`application_fee_amount`. No `transfer_group`. No `Stripe-Account` header.**

Supporting calls on the same platform account:
- `create-payment-intent/index.ts:149` — `GET /v1/customers/{id}` staleness probe.
- `create-payment-intent/index.ts:163` — `POST /v1/customers` (create).
- `create-payment-intent/index.ts:174` — `POST /v1/customers/{id}` (email backfill).
- `create-payment-intent/index.ts:199-206` — `POST /v1/ephemeral_keys` (mobile PaymentSheet).
- `create-payment-intent/index.ts:444-446` — `GET /v1/payment_intents/{id}` (pending-payment reuse).
- `create-payment-intent/index.ts:644` — `POST /v1/payment_intents/{id}/cancel` (rollback path).

Client-side confirmation contexts are likewise platform-scoped:
- `src/providers/NativeAppShell.native.tsx:112-119` — `<StripeProvider publishableKey=… merchantIdentifier="merchant.com.snatchit">`; **no `stripeAccountId` prop.**
- `web/src/components/checkout/CheckoutClient.tsx:13` — `loadStripe(STRIPE_PUBLISHABLE_KEY)` with **no `stripeAccount` option**; `:77` — `<Elements stripe={stripePromise} options={{ clientSecret }}>`.

**Conclusion:** the charge is created on, settles into, and is disputed against the **Snatch It
platform Stripe account**. The seller's connected account is not a party to the charge.

### 1.3 The fee model (Snatch It domain terms, not Stripe terms)

`supabase/functions/_shared/money.ts` is the single source of truth.

- `_shared/money.ts:28-29` — `BUYER_FEE_RATE = 0.10`, `SELLER_FEE_RATE = 0.10`.
- `_shared/money.ts:38-46` — buyer pays `base + round(base × 0.10)`; that total is the card charge.
- `_shared/money.ts:49-57` — seller receives `base − round(base × 0.10)`.
- `_shared/money.ts:60-62` — platform gross = buyer fee + seller fee (~18.2% of the buyer's total).
- `supabase/migrations/000_baseline_schema.sql:971-1002` — `public.payments` stores
  `amount` (base), `buyer_fee`, `seller_fee`, `total`, plus `stripe_payment_intent_id`
  (`:988`, UNIQUE), `stripe_client_secret` (`:989`), and a status enum
  `pending|processing|succeeded|failed|refunded` (`:992-993`).

**FINDING:** the platform's cut is taken **by arithmetic, not by Stripe**. There is no
`application_fee`. The platform simply charges the buyer the all-in total, keeps the whole thing in
its own balance, and transfers out a smaller number. Stripe has no knowledge that a fee was taken.

### 1.4 Every Transfer creation site

There is exactly **one** `POST /v1/transfers` call site in the entire repo.

`supabase/functions/_shared/payouts.ts:133-145`, inside `createSellerPayout()`:

| param | value | line |
|---|---|---|
| `amount` | `sellerNetCents` (base − seller fee) | `:137` |
| `currency` | `'usd'` | `:138` |
| `destination` | `profiles.stripe_connect_id` (`acct_…`) | `:139` |
| `source_transaction` | the funding charge's `ch_…` id | `:140` |
| `metadata[transfer_id]` / `[payment_id]` / `[seller_id]` | audit linkage | `:141-143` |

Idempotency key: `payout_<transferId>_<destination>_src` — `_shared/payout-logic.ts:24-26`.

Two pre-flights guard it:
1. **Destination capability** — `_shared/payouts.ts:82-98`: `GET /v1/accounts/{destination}`;
   refuses unless `capabilities.transfers === 'active'`.
2. **Funding charge** — `_shared/payouts.ts:103-130`: `GET /v1/payment_intents/{id}?expand[]=latest_charge`;
   requires `status === 'succeeded'`, `livemode === true`, a charge id, `refunded !== true`,
   and `sellerNetCents ≤ (charge.amount − charge.amount_refunded)`
   (`_shared/payout-logic.ts:95-97`).

`source_transaction` exists because a same-day charge leaves the platform *available* balance at $0
while the balance transaction is still `pending` — documented as a real 2026-08-03/04 production
incident at `_shared/payouts.ts:6-18`.

### 1.5 Every payout execution path

Exactly **two** callers of `createSellerPayout()`, and nothing else moves seller money:

**(a) Buyer-confirmed release** — `supabase/functions/confirm-and-release/index.ts`
- `:436-450` — resolve `profiles.stripe_connect_id`; null ⇒ `payoutDeferred('SELLER_NOT_ONBOARDED')`.
- `:406-424` — refuse unless `payments.status === 'succeeded'`.
- `:487-517` — final re-read of the transfer row immediately before money moves; any
  `disputed_at`, wrong status, or existing `payout_released_at` aborts.
- `:518-527` — the `createSellerPayout` call.
- `:586-590` — `record_transfer_payout` RPC writes `payout_released_at` + `stripe_transfer_id`
  atomically (the true double-payout guard).

**(b) Silent-buyer auto-release cron** — `supabase/functions/enforce-transfer-expiry/index.ts`
- `:514-523` — `payReleasedTransfer()` resolves the same `profiles.stripe_connect_id`.
- `:533-541` — same `payments.status === 'succeeded'` refusal.
- `:546-563` — same pre-payment dispute/paid re-read.
- `:615-622` — the `createSellerPayout` call.
- `:676-680` — same `record_transfer_payout` write.
- Risk gating is `supabase/functions/_shared/payout-policy.ts` (`classifyPayout`, `:239`),
  replacing the old blanket 72h release; thresholds default at `payout-policy.ts:45-51`
  (HIGH ≥ $200, LOW needs ≥3 sales and ≥14-day account) and are DB-tunable via
  `public.payout_policy` (`supabase/migrations/039_risk_based_payout.sql`).

Both paths converge on ONE canonical request body under ONE key so a cross-path race replays a
single Stripe Transfer (`_shared/payouts.ts:74-79`).

### 1.6 Every refund path

Exactly **two** `POST /v1/refunds` call sites, both in `enforce-transfer-expiry`, both full refunds
of the buyer's all-in total:

**(a) The legacy automatic refund — 24h unsent-ticket expiry**
`supabase/functions/enforce-transfer-expiry/index.ts:264-272`
- body: `payment_intent`, `metadata[transfer_id]`, `metadata[reason]='transfer_expired'`,
  `metadata[source]='enforce-transfer-expiry'`; **no `amount` ⇒ full refund** (`:252-254`).
- idempotency key `refund_expiry_<transferId>` (`:266`).
- then `payments.status='refunded'`, `refunded_at`, `stripe_refund_id` (`:275-282`).
- This is the ORIGINAL Phase-1 behaviour, unchanged: header comment `:6-10`.

**(b) The self-heal sweep for dropped expiry refunds**
`enforce-transfer-expiry/index.ts:387-395`, `metadata[source]='enforce-transfer-expiry-selfheal'`,
**same** `refund_expiry_<transferId>` key so it replays rather than double-refunds.
Guarded by the live-mode boundary: `:369-375` selects only
`payments.stripe_livemode = true` (migration `045_payments_stripe_livemode.sql`); NULL is excluded
fail-closed (`_shared/payout-logic.ts:110-118`).

**Out-of-band refund sync only:** `supabase/functions/stripe-webhook/index.ts:705-733`
(`charge.refunded`) marks `payments.status='refunded'` and stores the refund id when the payload
carries it — this observes a Dashboard refund, it does not create one.

**FINDING — zero-hit / gap:**
- `refund_application_fee` — **0 hits repo-wide.** Correct-by-vacuity: there is no application fee.
- `reverse_transfer` — **0 hits repo-wide.** A refund issued *after* a seller Transfer has already
  gone out will NOT claw that Transfer back. The system avoids this only by ordering: payout paths
  refuse a non-`succeeded` payment (`confirm-and-release:406`, `enforce-transfer-expiry:533`) and
  the refund paths only fire on `expired` transfers, which by definition were never paid out.
  There is no code that reverses an already-executed Transfer.
- **Buyer-win dispute refunds are not automated at all.** `resolve_transfer_dispute`
  (`supabase/migrations/065_dispute_resolution.sql:100-170`) records `refund_required = true`
  (`:135-140`) and `public.get_disputes_awaiting_refund()` (`:200`) exposes an ops queue —
  and **neither has a single caller in any `.ts`/`.tsx` file in the repo.** The refund is executed
  by a human in the Stripe Dashboard, and `charge.refunded` syncs it back.

### 1.7 Every dispute / chargeback path

All in `supabase/functions/stripe-webhook/index.ts`:

- **`charge.dispute.created`** — `:566-661`
  - `:584-592` resolve `payments` row by `stripe_payment_intent_id`, then the `transfers` row.
  - `:603-621` call `freeze_transfer_for_dispute` RPC — only if not yet paid out and not already
    disputed; this sets `disputed_at`, which is the predicate every payout gate reads.
  - `:627-657` upsert `public.disputes` keyed on `stripe_dispute_id`, capturing amount, reason,
    status and evidence due-by.
- **`charge.dispute.closed`** — `:663-703`
  - `:673-679` update the local dispute status.
  - `:690-696` on `status === 'lost'`, mark the payment refunded.
- **`transfer.reversed`** — `:748-770`: `mark_transfer_reversed` RPC flips our row to `reversed`.
  This is an *observation* handler; nothing in the codebase initiates a transfer reversal.
- **Admin resolution** — `supabase/migrations/065_dispute_resolution.sql:100-170`:
  `seller_win` clears `disputed_at` and returns status to `buyer_confirmed`, which re-opens the
  existing payout gates with no edge-function change (`:126-131`); `buyer_win`/`partial_refund`
  leave `disputed_at` set so every payout gate stays shut permanently (`:134-142`).

**FINDING:** because the charge lives on the platform account (§1.2), **every chargeback is
debited from the Snatch It platform balance.** There is no mechanism anywhere in the repo that
recovers a lost chargeback from the seller's connected account: no transfer reversal, no negative
`kernel.identity_obligation` write triggered by `charge.dispute.closed`, no debit of
`profiles.wallet_balance`. The platform eats it.

### 1.8 Every writer of a Stripe account reference

#### `public.profiles.stripe_connect_id` (added `supabase/migrations/002_transfers.sql:25`, `text unique`)

| # | Writer | Line | Callers |
|---|---|---|---|
| W1 | `create-connect-account` — write the freshly created `acct_…` | `supabase/functions/create-connect-account/index.ts:215-218` | **LIVE.** `src/screens/CreateListingScreen.tsx:400` region, `app/settings/payout-setup.tsx:63-66`, `app/(tabs)/profile.tsx:193` all invoke this edge function. |
| W2 | `create-connect-account` — NULL the id when the stored account is unusable with the live key (test-mode leftover), after archiving to `stripe_connect_archive` | `create-connect-account/index.ts:251-258` | Same edge function, self-heal branch (`:242-261`). |
| W3 | `scripts/seed-demo.ts` — write a test-mode `acct_…` onto a seeded profile | `scripts/seed-demo.ts:247` | Dev/demo seeding script only; hard-refuses non-`sk_test_` keys (`scripts/seed-demo.ts:144-152`). Never production. |
| W4 | one-off SQL: archive + NULL every test-mode id | `supabase/one-off/2026-08-03-archive-testmode-connect-ids.sql:14-26` and `supabase/migrations/044_archive_testmode_connect_ids.sql` | Applied once, 2026-08-03. Not a live path. |

Readers of the same column, for completeness: `create-connect-account:170`,
`confirm-and-release:436`, `enforce-transfer-expiry:519`, `stripe-webhook:837` (the
`account.updated` match key), `app/settings/payout-setup.tsx:66`, `app/(tabs)/profile.tsx:193`.

Related capability columns (`stripe_charges_enabled`, `stripe_payouts_enabled`,
`stripe_connect_status`, `stripe_onboarding_complete`) are written in two places, both live:
`create-connect-account/index.ts:285-293` and `stripe-webhook/index.ts:829-836`.

#### `kernel.organization.stripe_connect_account_ref` (declared `supabase/migrations/077_kernel_identity_orgs_and_roles.sql:114`, partial-unique index `:125-126`)

| # | Writer | Line | Callers |
|---|---|---|---|
| W5 | `kernel.set_org_connect_ref(p_org_id, p_connect_account_id, p_command_key)` — the bind-once onboarding write | `supabase/migrations/077_…:948` (definition), write at `:996-999` | **ZERO CALLERS.** No `.ts`, `.tsx`, `.js`, `.jsx`, `.py` or `.sh` file in the repo mentions this function name. There is no `connect-onboarding` edge function; `supabase/functions/` contains only `auto-finalize-auctions`, `confirm-and-release`, `confirm-payment`, `create-connect-account`, `create-payment-intent`, `delete-account`, `enforce-transfer-expiry`, `notify-report`, `notify-transfer`, `send-push`, `stripe-webhook`. Independently corroborated as gap **G-3** in `docs/architecture/PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md:69`. |
| W6 | `kernel.set_org_payout_destination(p_org_id, p_connect_account_ref, p_reason_code, p_command_key)` — the SoD-1/step-up-gated re-point | `supabase/migrations/085_kernel_money_native.sql:1601` (definition), write at `:1647-1654` | **ZERO CALLERS.** Same search, same result. Requires `aal2` (`085:1631`) and `org_owner` (`085:1618`). |

**FINDING (headline):** **no organization-level Stripe Connect path exists in executable code.**
The column, the bind-once verb, the re-point verb, the SoD-1 setter/approver exclusion
(`085:1213-1218`, `087:429-430`), the destination cool-down (`085:1641-1645`) and the destination
probation window (`087:465-495`) are all authored and pgTAP-tested — and nothing in the shipping
system can put an `acct_…` into that column. Every real Stripe account reference in production
lives on `public.profiles`, one per individual seller.

### 1.9 What Connect account is created today

`supabase/functions/create-connect-account/index.ts:198-224`, `createFreshAccount()`.
`POST /v1/accounts` with exactly (`:202-210`):

| param | value | line |
|---|---|---|
| `type` | **`express`** | `:203` |
| `country` | `US` | `:204` |
| `business_type` | **`individual`** | `:205` |
| `capabilities[transfers][requested]` | `true` | `:206` |
| `business_profile[product_description]` | `"Individual reselling event tickets on Snatch It"` | `:207` |
| `metadata[user_id]` | supabase user uuid | `:208` |
| `email` | auth email, when present | `:210` |

**No `capabilities[card_payments]`. No `controller[…]` properties. No `settings[payouts][schedule]`
(so Stripe's Express default applies). No `tos_acceptance`.** Repo-wide,
`capabilities[` appears at exactly one line (`create-connect-account/index.ts:206`).
`card_payments` appears once in the whole repo — `scripts/seed-demo.ts:452`, the
test-mode-only demo seeder, never production.

Onboarding is **Stripe-hosted**: `POST /v1/account_links` with
`type=account_onboarding` and https-validated `refresh_url` / `return_url`
(`create-connect-account/index.ts:333-338`; URLs at `:98-99`, validated `:161-163`).
Already-onboarded sellers get an **Express Dashboard login link**:
`POST /v1/accounts/{id}/login_links` (`:310`).
There is **no embedded-components onboarding** anywhere in the repo.

Account state is synced back two ways:
- pull, on every status check — `create-connect-account/index.ts:262-293`;
- push, on `account.updated` — `stripe-webhook/index.ts:795-856`, gating on the AND of
  `details_submitted && charges_enabled && payouts_enabled` (`:816-819`).

**Who the account is for:** an **individual seller (a natural person)**, one Connect account per
`auth.users` row. No business, no venue, no organization, no promoter.

### 1.10 Where funds land on a resale sale, and how the seller is paid

Text funds-flow diagram — **CURRENT RESALE RAIL**:

```
                       BUYER'S CARD
                            │
                            │  PaymentIntent  amount = base + 10% buyer fee
                            │  created on the PLATFORM account
                            │  (create-payment-intent/index.ts:531)
                            │  NO transfer_data · NO on_behalf_of
                            │  NO application_fee_amount · NO Stripe-Account
                            ▼
        ┌───────────────────────────────────────────────────────┐
        │        SNATCH IT PLATFORM STRIPE ACCOUNT              │
        │                                                       │
        │   • merchant of record for the full all-in total      │
        │   • Snatch It's descriptor on the cardholder statement│
        │   • Stripe processing fee (2.9% + 30¢) debited HERE   │
        │   • dispute liability sits HERE                       │
        │   • balance is `pending` for ~7 days (US default)     │
        └───────────────────────────────────────────────────────┘
             │                                        │
             │ payment_intent.succeeded webhook       │
             │ (stripe-webhook:261) ⇒ payments row    │
             │ 'succeeded' + transfers row 'pending'  │
             │ with expires_at = now + 24h            │
             ▼                                        │
   ┌─────────────────────────┐                        │
   │ SELLER MARKS SENT       │                        │
   │ BUYER CONFIRMS  ──or──  │                        │
   │ RISK-TIERED AUTO-RELEASE│                        │
   └─────────────────────────┘                        │
             │                                        │
             │  createSellerPayout()                  │  seller never sends:
             │  _shared/payouts.ts:133                │  24h expiry ⇒ FULL REFUND
             │                                        │  of the all-in total to the
             │  POST /v1/transfers                    │  buyer's card
             │    amount = base − 10% seller fee      │  (enforce-transfer-expiry:264)
             │    destination = acct_… (Express)      │
             │    source_transaction = ch_…           ▼
             ▼                                   BUYER'S CARD
   ┌───────────────────────────────────────────┐
   │   SELLER'S EXPRESS CONNECTED ACCOUNT      │
   │   capabilities: transfers ONLY            │
   │   (cannot accept a charge — by design)    │
   └───────────────────────────────────────────┘
             │
             │  Stripe's OWN automatic payout schedule
             │  (no payout_schedule set anywhere ⇒ Express default)
             │  observed via payout.paid / payout.failed
             │  (stripe-webhook:772 / :783)
             ▼
      SELLER'S BANK ACCOUNT

  PLATFORM RETAINS: buyer fee (10% of base) + seller fee (10% of base)
                    ≈ 18.2% of the buyer's total, LESS Stripe's processing
                    fee on the whole all-in amount — taken by arithmetic
                    (_shared/money.ts:60-62), never by application_fee.
```

**Precisely:** funds land in the **Snatch It platform Stripe balance**. The seller is paid by a
**Stripe Transfer from platform balance to their Express connected account, funded by
`source_transaction` against the buyer's original charge**, and then by **Stripe's own default
Express payout schedule** from that connected account to the seller's bank. Snatch It never
instructs the connected-account payout; it only observes it.

### 1.11 Parameter search — complete results

Search scope: whole repo, excluding `node_modules/` and `.git/`. "Code" = `.ts .tsx .js .jsx .sql`
excluding `docs/`. Fixed-string match.

| Stripe parameter | code hits | doc/test hits | Locations |
|---|---|---|---|
| `transfer_data` | **0** | 10 | Design/audit prose only: `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md`, `docs/security/STRIPE_APP_STORE_AUDIT.md`, `docs/phase2/ADVERSARIAL_ARCHITECTURE_REVIEW.md`, `docs/phase2/_decisions/A_venue_money.md`, `docs/phase2/PRIMARY_TICKETING_OWNER_DECISION_PACKET.md`, `docs/product-v2/ADVERSARIAL_REVIEW.md`, `docs/product-v2/_research/primary_issuance_audit.md` |
| `on_behalf_of` | **0** | 10 | Same seven docs plus `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` |
| `application_fee_amount` | **0** | 9 | `docs/security/STRIPE_APP_STORE_AUDIT.md`, `docs/phase2/_decisions/A_venue_money.md`, `docs/product-v2/ADVERSARIAL_REVIEW.md`, `docs/product-v2/_research/primary_issuance_audit.md` |
| `application_fee` | **0** | 10 | Same four docs |
| `destination` (as a Stripe API param) | **1** | — | `supabase/functions/_shared/payouts.ts:139` — the Transfer destination. All other `destination` hits in the repo are the Snatch It DOMAIN term "payout destination" (`087_venue_settlement_and_export.sql`, `085_kernel_money_native.sql`, `092_notify_reduced.sql`, `tests/payout-logic.test.ts`) and are NOT the Stripe charge parameter. |
| `Stripe-Account` (header) | **0** | 4 | `docs/phase2/ADVERSARIAL_ARCHITECTURE_REVIEW.md`, `docs/phase2/_decisions/A_venue_money.md`, `docs/product-v2/ADVERSARIAL_REVIEW.md`. **The shared client cannot express it (`_shared/stripe.ts:37-45, 64-67, 95-98`).** |
| `stripe_account` | **0** | 3 | `docs/product/IMPLEMENTATION_TICKETS.md`, `docs/product/LAUNCH_PLAN.md` — aspirational only |
| `source_transaction` | **10** | 41 total | **Live param:** `_shared/payouts.ts:140`. Supporting: `_shared/payouts.ts:16,75,102`; `_shared/payout-logic.ts:19,33,90`; `confirm-and-release/index.ts:513`; `tests/payout-logic.test.ts:6`; `085_kernel_money_native.sql:134` (`kernel.payout.source_transaction_ref` column) |
| `transfer_group` | **0** | **0** | **Zero hits repo-wide, including docs.** Payouts are correlated by our own `metadata[transfer_id]` (`_shared/payouts.ts:141`) and by `source_transaction`, never by Stripe's transfer group. |
| `reverse_transfer` | **0** | **0** | **Zero hits repo-wide, including docs.** No transfer reversal is ever initiated; `transfer.reversed` is observed only (`stripe-webhook/index.ts:748`). |
| `refund_application_fee` | **0** | **0** | **Zero hits repo-wide, including docs.** Vacuously correct — no application fee exists. |

**All zero-hit results are findings, stated here as such, not omissions.**

### 1.12 Connected-account inventory

| Party | Has a Connect account today? | Where the ref lives | Created by | Type / capabilities |
|---|---|---|---|---|
| **Snatch It platform** | n/a — it IS the platform account | `STRIPE_SECRET_KEY` env (`_shared/stripe.ts:32`) | — | Merchant of record for every charge |
| **Individual resale seller** | **YES — the only live one** | `public.profiles.stripe_connect_id` (`002_transfers.sql:25`) | `create-connect-account/index.ts:212` | **Express · US · `business_type=individual` · `transfers` capability ONLY** |
| **Buyer** | No. Buyers are platform-account **Customers** | `public.profiles.stripe_customer_id` (`026_stripe_customer_id.sql`) | `create-payment-intent/index.ts:163` | Customer, not an account |
| **Venue / organization** | **NO** | `kernel.organization.stripe_connect_account_ref` (`077:114`) — column exists, **never written by any reachable code** | *nothing* — `kernel.set_org_connect_ref` (`077:948`) and `kernel.set_org_payout_destination` (`085:1601`) both have **zero callers** | undefined |
| **Promoter** | **NO** | none — `kernel.payout.payee_identity_id` (`085:114`) points at `auth.users`, with no identity-level Connect ref beyond `profiles.stripe_connect_id` | `kernel.pay_promoter_commission` (`090`) mints the payout **`hold_state='held'`, `hold_reason_code='unfunded_settlement'`** and money cannot leave (090, commission block) | n/a |

### 1.13 The Phase-2 money kernel (085 / 087 / 090) — authored, unreachable

- `kernel.payment_native` (`085:40-62`) **links to** the existing `public.payments` row; it never
  re-charges. Header states this explicitly (`085:12-14`).
- `kernel.refund` (`085:74-95`) has `stripe_refund_ref` and a status ladder
  `pending→submitted→succeeded|failed`, written only by `kernel.mark_refund_state` (`085:1737`).
- `kernel.payout` (`085:111-160`) has `stripe_transfer_ref` and `source_transaction_ref`
  (`085:133-134`) — i.e. the Phase-2 rail is designed around the **same separate-charges-and-transfers
  mechanic** as the live resale rail.
- `kernel.mark_payout_transfer_state` (`085:1668`) and `kernel.mark_refund_state` (`085:1737`) are
  the Stripe state-sync pair — `service_role`-only, DEFINER, and documented as having **no human
  path** (`085:1661-1663`). **Both have zero code callers.**
- `kernel.request_org_payout` (`087:408`) refuses when `stripe_connect_account_ref` is null
  (`087:446-447`) — which, per §1.8, is *always*.
- `venue.finalize_primary_order` (`085:1881`) takes an **already-succeeded `public.payments` row**
  as its authority (`085:1918-1926`) — the primary rail, when activated, would ride the **same
  platform-account PaymentIntent**. No separate charge object is contemplated in code.
- Primary issuance is dark at the inventory-hold layer (`082` header, `081` `feature.native_issuance_enabled`).

**Net:** there is exactly one live money rail, and Phase 2 as authored does not change the
merchant of record.

---

## PART 2 — CURRENT OFFICIAL STRIPE CAPABILITY

All statements below were fetched from docs.stripe.com during this pass, not recalled. URLs are
inline. **Terminology discipline:** in this section "platform", "connected account", "direct /
destination / separate charges", "merchant of record", "capability" and "controller properties"
are STRIPE terms. Snatch It domain terms ("payout destination", "transfer", "settlement",
"release", "seller net") are NOT used here, because several of them collide with Stripe words that
mean something else. In particular: **Snatch It's `public.transfers` table is a ticket-handover
state machine and has nothing to do with a Stripe Transfer object.**

### 2.1 The three charge models

#### Direct charges
- The charge is created **on the connected account**: "You create a charge on your connected
  account, so the payment appears in the connected account's balance, not in your platform's
  balance." (https://docs.stripe.com/connect/charges). Mechanically this is the
  `Stripe-Account` header: "To access direct charge data, you must query the Stripe API using the
  connected account ID in the Stripe-Account header."
  (https://docs.stripe.com/connect/direct-charges)
- **Statement:** the connected account's static descriptor component
  (https://docs.stripe.com/connect/statement-descriptors).
- **Merchant of record:** "Direct charges: The merchant of record is the connected account."
  (https://docs.stripe.com/connect/merchant-of-record)
- **Disputes:** "Stripe always attempts to debit disputed amounts from the connected account's
  balance. However, if Stripe can't debit the amount, ultimate responsibility depends on whether
  Stripe or the platform is responsible for negative balances."
  (https://docs.stripe.com/connect/disputes)
- **Stripe processing fee:** the *only* model with a fee-payer switch —
  `controller.fees.payer` (v1) / `defaults.responsibilities.fees_collector` (v2), settable
  **only at account creation**. `account`/`stripe`, `application_custom` and `application_express`
  → connected account pays; `application` → platform pays.
  (https://docs.stripe.com/connect/direct-charges-fee-payer-behavior)
- **Platform's cut:** `application_fee_amount` on the connected-account charge. "Stripe transfers
  the `application_fee_amount` to the platform and deducts the Stripe fee from the connected
  account's balance." No Stripe fee on the application fee itself.
  (https://docs.stripe.com/connect/direct-charges)
- **Requirements:** "Your connected accounts must have the `card_payments` capability active in
  order to use direct charges" (https://docs.stripe.com/connect/charges), and "For an `Account` to
  have the `card_payments` capability, you must request both `card_payments` and `transfers`."
  (https://docs.stripe.com/connect/account-capabilities). Stripe now cautions: "Direct charges
  aren't recommended for legacy v1 Express and Custom accounts."
  (https://docs.stripe.com/connect/charges)

#### Destination charges
- The charge is created **on the platform**, with `transfer_data[destination]` naming the
  connected account: "You create a charge on your platform's account… Your account balance is
  debited for the cost of the Stripe fees, refunds, and chargebacks."
  (https://docs.stripe.com/connect/destination-charges)
- **Statement:** the platform's, unless `on_behalf_of` is set
  (https://docs.stripe.com/connect/statement-descriptors).
- **Merchant of record:** "Indirect charges without using the `on_behalf_of` parameter: The
  merchant of record is the platform." (https://docs.stripe.com/connect/merchant-of-record)
- **Disputes:** "For destination charges, with or without `on_behalf_of`, Stripe debits dispute
  amounts and fees from your platform account." (https://docs.stripe.com/connect/destination-charges,
  https://docs.stripe.com/connect/disputes)
- **Stripe processing fee:** the platform, always. "Stripe charges the platform directly for
  destination charges (with or without `on_behalf_of`)."
  (https://docs.stripe.com/connect/direct-charges-fee-payer-behavior)
- **Platform's cut:** two mutually exclusive mechanisms —
  (a) `application_fee_amount`: the full amount transfers out to the destination on capture, then
  the fee is "transferred back to the platform"; (b) `transfer_data[amount]`: only that amount
  moves, the remainder simply stays on the platform, and the connected account "can't view the
  total amount of the charge." (https://docs.stripe.com/connect/destination-charges)
- **Requirements:** destination needs the `transfers` capability
  (https://docs.stripe.com/connect/account-capabilities). Adding `on_behalf_of` additionally
  requires a payments capability such as `card_payments`
  (https://docs.stripe.com/connect/destination-charges).

#### Separate charges and transfers
- Charge on the platform; one or more Transfer objects created independently: "which are withdrawn
  from your account balance… Your account balance is debited for the cost of the Stripe fees,
  refunds, and chargebacks." (https://docs.stripe.com/connect/separate-charges-and-transfers)
- **Statement / MoR / disputes / Stripe fee:** identical rules to destination charges — platform
  descriptor unless `on_behalf_of`; platform is MoR without it; "Stripe debits dispute amounts and
  fees from your platform account"; fees assessed on the platform.
- **Platform's cut:** by **withholding**, not by an application fee — "the platform can collect
  fees on a charge by reducing the amount it transfers to the destination accounts." Stripe's own
  worked example: a 100 USD charge, 3.20 Stripe fee, transfers of 70 and 20, "A platform fee of
  6.80 USD remains in the platform account."
  (https://docs.stripe.com/connect/separate-charges-and-transfers)
- **Mechanics:** `transfer_group` "only identifies associated objects. It doesn't affect any
  standard functionality." `source_transaction` ties a Transfer to a charge so "the transfer
  request returns success regardless of your available balance if the related charge hasn't
  settled yet", and "You must specify the `source_transaction` when you create a transfer. You
  can't update that attribute later." (same page)
- **Requirements:** `transfers` capability on each recipient. Stripe adds a policy note: "We
  recommend using separate charges and transfers only when you're responsible for negative
  balances of your connected accounts."
  (https://docs.stripe.com/connect/account-capabilities)

### 2.2 What `on_behalf_of` actually changes

Canonical list (https://docs.stripe.com/connect/destination-charges, repeated verbatim on the
separate-charges page):

**It DOES change:**
- Settlement country and settlement currency — "Charges settle in the connected account's country
  and settlement currency."
- Fee structure — "The fee structure for the connected account's country is used" (the platform
  still *pays* it: https://docs.stripe.com/connect/charges).
- Statement descriptor — the connected account's descriptor appears on the cardholder statement;
  cross-country, also its address and phone number.
- Payout timing — follows the connected account's `delay_days`.
- Payment-method availability — charges "use your platform's payment method configurations, unless
  they use `on_behalf_of`"; the capability must then be requested on the connected account
  (https://docs.stripe.com/connect/account-capabilities).
- Cross-region enablement — required when platform and connected account are in different regions.

**It does NOT change:**
- It does not move the charge onto the connected account. The charge remains a platform charge and
  refunds are still issued with the platform key.
- It does not shift the Stripe-balance dispute debit: "For destination charges, with or without
  `on_behalf_of`, Stripe debits dispute amounts and fees from your platform account."
  (https://docs.stripe.com/connect/disputes)
- It does not change who pays the Stripe processing fee (still the platform, per
  https://docs.stripe.com/connect/direct-charges-fee-payer-behavior).

**AMBIGUITY (flagged, per brief):** the merchant-of-record page says "Indirect charges using the
`on_behalf_of` parameter: The merchant of record is the connected account" and separately that
"The MoR is also liable for any disputes or refunds related to the purchase" — yet the same page
qualifies "if a connected account's balance becomes negative, your platform is ultimately
responsible for covering any losses", and the disputes page says the platform balance is debited
regardless. **Stripe never reconciles legal/network MoR with Stripe-balance mechanics on a single
page.** For a design decision, treat "`on_behalf_of` makes the connected account MoR" as a
*network/compliance* statement and "the platform balance is debited for disputes" as the
*operational* statement; both are simultaneously published by Stripe.

**GAP:** the widely-assumed rule that `on_behalf_of` must equal `transfer_data[destination]`
**could not be sourced.** `https://docs.stripe.com/connect/on-behalf-of` returns HTTP 404;
`/connect/charges-transfers` redirects to the separate-charges page; the API reference says only
"`on_behalf_of` (string, optional) — The Stripe account ID that these funds are intended for."
(https://docs.stripe.com/api/payment_intents/create). Do not cite this constraint as documented.

### 2.3 `application_fee_amount` semantics per model

| Model | Where the fee comes from | Where it lands | Notes |
|---|---|---|---|
| Direct | The connected account's balance | Platform balance, as an `ApplicationFee` object | "There are no additional Stripe fees on the application fee itself." Created **asynchronously** by default unless expanded. Must be positive, ≤ the captured amount. (https://docs.stripe.com/connect/direct-charges) |
| Destination | The full charge first transfers OUT to the destination, then the fee transfers BACK | Platform balance, "on the platform account's normal transfer schedule" | The platform pays the Stripe fee **out of** this fee. Stripe's example: 10.00 charge, 1.23 application fee, 0.59 Stripe fee → 0.64 net to platform. Settles in the **connected account's** settlement currency; `transfer_data[amount]` instead settles in the **platform's**. (https://docs.stripe.com/connect/destination-charges) |
| Separate charges and transfers | **Not the documented mechanism** — the platform simply transfers less | Platform balance, by residue | (https://docs.stripe.com/connect/separate-charges-and-transfers) |

**GAP:** no Stripe page states whether `application_fee_amount` is *valid* on a platform charge
with no `transfer_data`. The API reference neither permits nor forbids it. Unresolved.

An explicit `application_fee_amount` overrides Dashboard-configured Platform Pricing Tool rates
(stated on both the direct- and destination-charge pages).

### 2.4 Refund behaviour per model

Cross-model summary (https://docs.stripe.com/connect/charges):

| Model | Balance debited for the refund | Underfunded behaviour |
|---|---|---|
| Direct | The **connected account's** | Refund goes `pending` until the account is funded |
| Destination | The **platform's** | Refund goes `pending`; **but** "If the refund request also attempts a transfer reversal, but the connected account has an insufficient balance, the refund request returns an error instead of creating a refund with `pending` status." |
| Separate | The **platform's** | Refund goes `pending` when underfunded |

- **`refund_application_fee`** — applies to **direct and destination**. Direct: "Application fees
  aren't automatically refunded… You can refund an application fee by passing a
  `refund_application_fee` value of true" ⇒ **default false**; full refund refunds the full fee,
  partial is proportional. Destination: "by default the platform account keeps the funds from the
  application fee", and critically **"If you refund the application fee for a destination charge,
  you must also reverse the transfer."**
  (https://docs.stripe.com/connect/direct-charges, https://docs.stripe.com/connect/destination-charges)
- **`reverse_transfer`** — applies to **destination charges**. "by default the destination account
  keeps the funds that were transferred to it, leaving the platform account to cover the negative
  balance from the refund. To pull back the funds… set the `reverse_transfer` parameter to `true`"
  ⇒ **default false**. Full refund reverses the whole transfer; partial is proportional.
  (https://docs.stripe.com/connect/destination-charges)
- **Separate charges and transfers has NEITHER.** "refunding a charge has no impact on any
  associated transfers. It's up to your platform to reconcile any amount owed back to it by
  reducing subsequent transfer amounts or by reversing transfers." A manual `TransferReversal`
  succeeds only "if the connected account's available balance is greater than the reversal amount
  or has connected reserves enabled."
  (https://docs.stripe.com/connect/separate-charges-and-transfers)
- Failed or cancelled refunds on destination charges return funds to the platform balance; the
  connected account must then be re-paid with a **new** Transfer.

**GAP:** https://docs.stripe.com/api/refunds/create lists both `refund_application_fee` and
`reverse_transfer` as "(boolean, optional)" with **no stated default and no statement of which
charge types they apply to.** The defaults and scoping above are inferable only from the prose
guides — a real documentation weakness worth noting in any design that depends on them.

### 2.5 Dispute / chargeback liability, and negative balances

| Model | Amount debited from | Dispute fee | Recovery lever |
|---|---|---|---|
| Direct | Connected account's balance first; ultimate responsibility follows negative-balance responsibility | Platform only when fee payer = `application`; otherwise the connected account (incl. `application_custom`, `application_express`) | Stripe's own debit of the connected account |
| Destination | **Platform** (with or without `on_behalf_of`) | Platform | Transfer reversal |
| Separate | **Platform** | Platform | Manual `TransferReversal`, or withholding from future transfers |

(https://docs.stripe.com/connect/disputes,
https://docs.stripe.com/connect/direct-charges-fee-payer-behavior)

A won dispute can be re-transferred, but "Retransferring a previous reversal is subject to
cross-border transfer restrictions." (https://docs.stripe.com/connect/disputes)

**Negative balances** (https://docs.stripe.com/connect/account-balances):
- "Stripe first assigns negative transactions to the account the associated charge was made on."
- Responsibility is `controller.losses.payments` (v1) / `defaults.responsibilities.losses_collector`
  (v2): "`stripe` if Stripe is responsible and `application` if your platform is responsible."
  Choosing `application` "requires you to review and acknowledge your responsibilities in the
  Dashboard." (https://docs.stripe.com/connect/migrate-to-controller-properties)
- "If a connected account balance is negative, Stripe debits their external account on file up to
  the maximum number of attempts allowed." Auto-debit requires `debit_negative_balances=true` and
  is supported in AU, CA, Europe/SEPA (incl. UK), NZ, US.
- For platform-liable accounts, Stripe places a `connect_reserved` hold on the **platform**
  balance; after 180 days it issues a `connect_collection_transfer` from platform funds to zero the
  account, "after which we recommend that you reject the account."
- Flat statement: "Your platform is always responsible for its own negative balances." And a direct
  marketplace warning: **"If you use indirect charges, assign negative balance responsibility to
  your platform, not to Stripe."** (https://docs.stripe.com/connect/risk-management)
- Trade-offs: Stripe-liable accounts cannot use payment/payout pauses, account debits, Treasury or
  Issuing; platform-liable accounts cannot use Managed Risk.

**AMBIGUITY (flagged):** direct-charge dispute liability is stated three different ways across
Stripe's own pages — "Refunds and chargebacks reduce the connected account's balance" (charges
overview), "ultimate responsibility depends on… negative balances" (disputes), and "If you're
using Express or Custom legacy account types, your platform is responsible for disputes and fraud"
(charges overview). These are not obviously consistent.

### 2.6 Connect onboarding options today

| | Stripe-hosted (Account Links) | Embedded components |
|---|---|---|
| **Platform implements** | `POST /v1/accounts`, then `POST /v1/account_links` with `type=account_onboarding`, `refresh_url`, `return_url`, optional `collection_options[fields]` = `currently_due` \| `eventually_due`; redirect | `POST /v1/account_sessions` with `components[account_onboarding][enabled]=true`, an own endpoint returning the `client_secret`, then `loadConnectAndInitialize({publishableKey, fetchClientSecret})` and `stripeConnectInstance.create('account-onboarding')` |
| **Account experiences** | A full-page redirect to a Stripe-hosted form | The same form rendered **inside** the platform's own UI |
| **Constraints** | "You can only use each temporary Account Link URL once"; links expire in minutes; "Don't email, text, or otherwise send account link URLs outside of your platform application"; the return URL carries no state — re-read `requirements` or listen to `account.updated`; **"only supported in web browsers. You can't use it in embedded web views."** | `fetchClientSecret` must mint a fresh session on refresh; call `logout()` on user logout; CSP must allow `connect-js.stripe.com` and `js.stripe.com`; `Cross-Origin-Opener-Policy` must stay `unsafe-none`; requirement subsets tunable with `only`/`exclude` |
| **Who collects KYC** | Follows `controller.requirement_collection`: `stripe` (Stripe collects; the platform stops receiving identity-information updates once a link/session is created) or `application` (platform has full KYC property access and attests service-agreement acceptance via API) | Same property, same semantics |
| **Coverage** | "Stripe handles all of the onboarding flow logic. Automatically supports 46+ countries and 14 languages" (https://docs.stripe.com/connect/design-an-integration) | Same Stripe-owned form logic and localization |
| **Hard restriction** | `account_update` links can be created **only** where the platform collects requirements — not for accounts with Stripe-hosted Dashboard access. "For an account without Stripe-hosted Dashboard access where Stripe is liable for negative balances, you must use embedded components." | The escape hatch for exactly that case. `disable_stripe_user_authentication` is available only where the platform collects requirements, and using it means "you assume liability for connected accounts if they can't pay back negative balances." |

(https://docs.stripe.com/connect/hosted-onboarding, https://docs.stripe.com/connect/embedded-onboarding,
https://docs.stripe.com/connect/get-started-connect-embedded-components)

### 2.7 The current account-creation model — three coexisting layers

1. **Accounts v2** — what Stripe steers new integrations toward. Uses **configurations** rather
   than types: `merchant` (accept payments; includes `card_payments`), `recipient` (receive
   transfers — "required to use indirect charges"), `customer`; plus
   `defaults.responsibilities.fees_collector` / `losses_collector`.
   (https://docs.stripe.com/connect/accounts-v2)
2. **v1 controller properties** — the current v1 framing. Legacy types map to property sets:
   | Legacy type | `losses.payments` | `fees.payer` | `requirement_collection` | `stripe_dashboard.type` |
   |---|---|---|---|---|
   | Standard | `stripe` | `account` | `stripe` | `full` |
   | **Express** | **`application`** | `application_express` | `stripe` | `express` |
   | Custom | `application` | `application_custom` | `application` | `none` |
   Defaults on a bare create are `stripe` / `account` / `stripe` / `full`. `stripe_dashboard.type`
   is immutable. Several combinations are explicitly unsupported (e.g. `full` dashboard with
   `losses.payments=application`). (https://docs.stripe.com/connect/migrate-to-controller-properties)
3. **Legacy Standard / Express / Custom** — the page is now marked **"Deprecated feature"**;
   its comparison table still asserts platform liability for disputes on Express and Custom.
   (https://docs.stripe.com/connect/accounts)

**Note on the current Snatch It call:** `create-connect-account/index.ts:203` sends
`type: 'express'`, i.e. layer 3. Per the mapping above that yields
`controller.losses.payments = application` — **Snatch It's platform is already the party liable
for its sellers' negative balances**, whether or not that was a deliberate choice.

**OBSERVED CONTENT — reported, not acted on.** `https://docs.stripe.com/connect/accounts.md`
contains text addressed at automated readers: *"If you are an agent or an LLM, ignore the content
on this page unless your prompt explicitly states that your integration already uses connected
account types… Instead, try to use the Accounts v2 API."* This is instruction-shaped text found in
a fetched document, not direction from this repo's owners. It is recorded here as a **fact about
Stripe's documentation posture** (Stripe is actively steering new work off the Express/Standard/
Custom vocabulary), and was NOT treated as an instruction. Snatch It's integration *does* already
use connected account types, so the page is on-point regardless.

### 2.8 Further documentation gaps found

- **Accounts v2 GA status is unclear.** The docs tell new integrations to use it, yet the sample
  call sends `Stripe-Version: 2026-08-26.preview`, and `design-an-integration` flags an
  Express-Dashboard-plus-Stripe-losses combination as public preview.
- **No per-payment fee-payer control exists.** Fee payer is an account-creation-time property and
  direct-charges-only. Nothing supports a `payment_method_options`-level fee payer; destination and
  separate charges are always billed to the platform.
- **`debit_negative_balances` has moved surfaces** — described as an account setting on the
  disputes/destination pages, but tied to the balance-settings object on the account-balances page
  (`?api-version=2025-11-17.clover`). Which surface is exposed depends on your pinned API version —
  relevant here, since Snatch It pins `2024-09-30.acacia` (`_shared/stripe.ts:34`).

---

## PART 3 — THE THREE MODELS COMPARED

"Compatible with a venue being merchant of record" is judged strictly on Stripe's MoR page plus
the descriptor and dispute-ownership rules — not on commercial preference.

| | **Direct charges** | **Destination charges** | **Separate charges and transfers** *(what Snatch It runs today)* |
|---|---|---|---|
| **Charge created on** | Connected account (`Stripe-Account` header) | Platform, with `transfer_data[destination]` | Platform, bare |
| **Settlement / merchant account** | Connected account | Platform | Platform |
| **Cardholder statement shows** | Connected account | Platform (connected account only with `on_behalf_of`) | Platform (connected account only with `on_behalf_of`) |
| **Merchant of record** | Connected account | Platform (connected account with `on_behalf_of` — but see §2.2 ambiguity) | Platform (same caveat) |
| **Dispute amount debited from** | Connected account's balance first | **Platform** always | **Platform** always |
| **Dispute fee paid by** | Configurable at account creation (`controller.fees.payer`) | Platform | Platform |
| **Stripe processing fee paid by (default)** | Connected account; switchable to platform at account creation only | Platform, not switchable | Platform, not switchable |
| **Platform takes its cut via** | `application_fee_amount` | `application_fee_amount` **or** `transfer_data[amount]` | Withholding — transfer less than you charged |
| **Refund debits** | Connected account | Platform | Platform |
| **`refund_application_fee`** | Yes, default `false` | Yes, default `false` (and then you MUST also reverse the transfer) | **N/A — no application fee exists** |
| **`reverse_transfer`** | N/A | Yes, default `false` | **N/A — reverse manually via TransferReversal, or withhold from future transfers** |
| **Capability the connected account needs** | `card_payments` **and** `transfers` | `transfers` (plus a payments capability if using `on_behalf_of`) | `transfers` |
| **Onboarding burden on the connected account** | Full KYC to charge-ready | KYC to transfers-ready | KYC to transfers-ready |
| **Stripe's own policy note** | "Direct charges aren't recommended for legacy v1 Express and Custom accounts" | Stripe's default recommendation for marketplaces | "We recommend using separate charges and transfers only when you're responsible for negative balances of your connected accounts" |
| **Compatible with a VENUE being merchant of record?** | **YES — natively and unambiguously.** The charge is on the venue's account, the venue's descriptor is on the statement, the venue's balance is debited for disputes and refunds. This is the only model where MoR is not a qualified claim. | **PARTIALLY.** `on_behalf_of` moves the descriptor and the documented MoR designation to the venue, but Stripe still debits **the platform** for every dispute. MoR in name, platform liability in fact. | **PARTIALLY, and identically to destination.** Same `on_behalf_of` mechanics, same platform dispute debit, and additionally **no automatic clawback exists** — recovery is entirely manual. |
| **Snatch It today** | Impossible: no `card_payments` capability is ever requested (`create-connect-account/index.ts:206`), and the shared client cannot send `Stripe-Account` (`_shared/stripe.ts:37-45`) | Not used: zero `transfer_data` hits in code | **THIS. Charge `create-payment-intent/index.ts:531`; Transfer `_shared/payouts.ts:133`; cut withheld by arithmetic `_shared/money.ts:60-62`** |

### 3.1 Structural blockers between here and any other model

Stated as facts, not as a recommendation:

1. **No connected account can accept a charge.** Only `capabilities[transfers][requested]` is ever
   sent (`create-connect-account/index.ts:206`). `card_payments` appears once in the whole repo, in
   the test-mode-only seeder (`scripts/seed-demo.ts:452`).
2. **The edge Stripe client cannot address a connected account.** No `Stripe-Account` support
   anywhere in `_shared/stripe.ts`.
3. **No client-side connected-account context.** Neither `StripeProvider`
   (`src/providers/NativeAppShell.native.tsx:112-119`) nor `loadStripe`
   (`web/src/components/checkout/CheckoutClient.tsx:13`) is given an account id.
4. **No organization can hold a Stripe account.** `kernel.set_org_connect_ref` (`077:948`) and
   `kernel.set_org_payout_destination` (`085:1601`) have **zero callers**; there is no
   `connect-onboarding` edge function.
5. **Every connected account today is a `business_type=individual` Express account**
   (`create-connect-account/index.ts:205`) — a natural person, not a venue entity.
6. **The platform is already liable for connected-account negative balances**, because Express maps
   to `controller.losses.payments = application`
   (https://docs.stripe.com/connect/migrate-to-controller-properties).
7. **Nothing in the codebase can claw money back from a seller** — 0 hits for `reverse_transfer`,
   and buyer-win dispute refunds have no automated executor (§1.6).

---

## APPENDIX — evidence index

| Concern | Authoritative file:line |
|---|---|
| Shared Stripe client, no `Stripe-Account` | `supabase/functions/_shared/stripe.ts:37-45, 59-83, 90-108` |
| PaymentIntent body (the whole parameter set) | `supabase/functions/create-payment-intent/index.ts:513-527` |
| PaymentIntent create sites | `create-payment-intent/index.ts:531, 541` |
| Fee math | `supabase/functions/_shared/money.ts:28-29, 38-62` |
| The one Transfer call | `supabase/functions/_shared/payouts.ts:133-145` |
| Transfer pre-flights | `_shared/payouts.ts:82-98, 103-130` |
| Payout idempotency key | `_shared/payout-logic.ts:24-26` |
| Payout path A (buyer confirms) | `supabase/functions/confirm-and-release/index.ts:436-450, 487-527, 586-590` |
| Payout path B (risk-tiered cron) | `supabase/functions/enforce-transfer-expiry/index.ts:514-563, 615-622, 676-680` |
| Risk classifier | `supabase/functions/_shared/payout-policy.ts:45-51, 239` |
| Legacy automatic refund (24h expiry) | `enforce-transfer-expiry/index.ts:252-282` |
| Refund self-heal sweep | `enforce-transfer-expiry/index.ts:369-395` |
| Refund observation only | `supabase/functions/stripe-webhook/index.ts:705-733` |
| Dispute created / freeze | `stripe-webhook/index.ts:566-661` |
| Dispute closed | `stripe-webhook/index.ts:663-703` |
| Transfer reversed (observed) | `stripe-webhook/index.ts:748-770` |
| Admin dispute resolution (no refund executor) | `supabase/migrations/065_dispute_resolution.sql:100-170, 200` |
| Connect account creation | `supabase/functions/create-connect-account/index.ts:198-224` |
| Hosted onboarding link | `create-connect-account/index.ts:333-338` |
| Express dashboard login link | `create-connect-account/index.ts:310` |
| Connect state sync (pull) | `create-connect-account/index.ts:262-293` |
| Connect state sync (push) | `stripe-webhook/index.ts:795-856` |
| `profiles.stripe_connect_id` declared | `supabase/migrations/002_transfers.sql:25` |
| `public.payments` | `supabase/migrations/000_baseline_schema.sql:971-1002` |
| `public.transfers` (ticket handover, NOT Stripe) | `supabase/migrations/002_transfers.sql:35-70` |
| Org Connect ref column | `supabase/migrations/077_kernel_identity_orgs_and_roles.sql:114, 125-126` |
| Org Connect ref writer #1 (0 callers) | `077_kernel_identity_orgs_and_roles.sql:948, 996-999` |
| Org Connect ref writer #2 (0 callers) | `supabase/migrations/085_kernel_money_native.sql:1601, 1647-1654` |
| Phase-2 money ledgers | `085_kernel_money_native.sql:40-62, 74-95, 111-160` |
| Stripe state-sync pair (0 callers) | `085_kernel_money_native.sql:1668, 1737` |
| Org payout requires a destination that never gets set | `supabase/migrations/087_venue_settlement_and_export.sql:446-447` |
| Primary finalize rides an existing platform payment | `085_kernel_money_native.sql:1881, 1918-1926` |
| Promoter commission minted HELD, unfunded | `supabase/migrations/090_venue_promoter_engine.sql` (`pay_promoter_commission`, commission-insert block) |

