# Production release package — prepared, NOT executed

Date: 2026-09-10 · Owner: release integration.

**Nothing in this document has been executed.** No migration was applied to production, no edge deployed, no
flag changed, no cron touched, no Stripe setting changed, no AWS mutation, no merge to `main`. Every production
figure below is a read-only query.

## 1. Pinned candidate

| | |
|---|---|
| Branch | `release/convergence-135` |
| Commit | **`7986711`** |
| Base | `562fda9` (production-aligned 135 line) |
| Contains | payments RC P1–P3 · v2 consumer UI · tickets ownership RPC · filter-sheet fix · admin/ops console 115–120 · signing/door 110–114 |
| CI evidence | run **34320158401**, head `7986711`, **all five jobs green** |

CI at that exact commit: Gate-2 `tables=30 functions=88 policies=37 triggers=33`; pgTAP
`Files=71, Tests=4698, Result: PASS`; `deno check OK: 15 entrypoints (11 deployed + 4 production-aligned)`;
Typecheck/Lint/Unit, Admin console and Web build all success.

Local corroboration at the same tree: convergence rehearsal 18/18 (fresh order, production order, and an
identical function-definition hash across both); payments rollback battery 63/63; mobile 1531/1531; admin
96/96; migration immutability + ordering clean; G-4 assembled-migration integrity PASS.

## 2. Production ledger reconciled against the candidate

Read-only, 2026-09-10:

```
production ledger rows        135      numeric tip 120      max version 20260902003623
candidate chain               140
pending                         5
```

Each of the five was checked individually against `supabase_migrations.schema_migrations`; all five return
`applied_in_prod = 0`. Nothing is applied in production that is absent from the candidate. `110`–`120` are
already in production and are **not** part of this release.

## 3. Execution order

### 3a. Migrations — 5, in this order

| # | Version | What it does | Rollback |
|---|---|---|---|
| 1 | `20260906100000_checkout_reservation_authority` | reservation/settlement authority; `settle_listing_for_payment` | `…_rollback.sql` |
| 2 | `20260906110000_settle_verified_payment` | the single verified-settlement contract + `get_unsettled_payments` | `…_rollback.sql` |
| 3 | `20260906120000_payout_attempts_and_refund_monotonic` | payout attempt ledger, append-only `payment_refunds`, `amount_refunded_cents`, `account_deletions` | `…_rollback.sql` (archives in-transaction) |
| 4 | `20260906130000_deletion_sweep_live_rail_obligations` | BP-13 arm on `kernel.sweep_deletion_pending` (external rail only) | `…_rollback.sql` |
| 5 | `20260909000000_kernel_my_tickets_read` | `public.get_my_tickets()` — additive, read-only, one function + grant | `…_rollback.sql` |

Order is the canonical `LC_ALL=C` filename sort and matches what the rehearsal exercised. Migrations 1–4 have
inter-dependencies (2 requires 1; 4 requires 3); 5 depends only on Phase-2 `079`/`080`, already live.

### 3b. Edge deployments — 9, after the migrations

Changed between production's deployed Phase-2 tip and the candidate, therefore requiring redeploy:

`confirm-and-release` · `confirm-payment` · `create-connect-account` · `create-payment-intent` ·
`delete-account` · `enforce-transfer-expiry` · `notify-report` · `notify-transfer` · `stripe-webhook`

Unchanged, **do not redeploy**: `send-push`, `auto-finalize-auctions`.
Shared modules pulled in by the above: `_shared/payout-logic.ts`, `_shared/payouts.ts`.
Not deployed by this release and not to be deployed: `ops-refund-execute`, `credential-sign`, `door-manifest`,
`door-session`, `connect-onboarding`, `payout-execute`, `primary-checkout`, `refund-execute`.

**Migrate-then-deploy is mandatory** — the new edges call RPCs that only exist after migrations 1–4.

### 3c. Mobile — last

Production profile build from `7986711`, then TestFlight/App Store submission. The client depends on
`settle_verified_payment` (three-outcome settlement copy) and `get_my_tickets` (Tickets tab), so it must not
reach users before 3a and 3b are complete. `eas.json`'s `production` profile is byte-identical to the shipped
one and points at production Supabase + the live Stripe key; the compile-time environment guard fails the build
on any mispairing.

## 4. Validation after each stage

| Stage | Check | Expected |
|---|---|---|
| after 3a | ledger row count | 135 → **140** |
| after 3a | Gate-2 census | `tables=30 functions=88 policies=37 triggers=33` |
| after 3a | `public.get_my_tickets` | exists, `SECURITY DEFINER`, `search_path=public, pg_temp`, EXECUTE to `authenticated` only |
| after 3a | `kernel.signing_key` rows · native flags | still `0` · all three still `false` |
| after 3b | `list_edge_functions` | 11 functions, the nine redeployed at a new version, `verify_jwt` unchanged per function |
| after 3b | one real checkout end-to-end | single payment row, single PaymentIntent, no duplicate transfer |
| after 3b | `get_unsettled_payments` | drains to 0 |
| after 3c | client on production | no "contact support" on a cancelled sheet; Tickets tab renders the empty state |

## 5. Abort conditions

Stop and roll back the current stage if any of these holds:

1. Any migration errors, or the ledger lands on a count other than 140.
2. Gate-2 census differs from `30 / 88 / 37 / 33`.
3. `kernel.signing_key` becomes non-zero, or any `feature.native_*` flag becomes true — neither is part of this
   release.
4. A duplicate payment, duplicate transfer, or a payout without a matching attempt row appears in the first
   post-deploy checkout.
5. `AUTODEPLOY-VERIFIED-OFF` is missing from the merging PR, or `supabase branches list` shows a non-empty
   `git_branch` — merging would then apply migrations to production automatically (AUTODEPLOY-1).
6. Edge deploy is attempted before the migrations complete (PGRST202 on the new RPCs).
7. The payout cron is running during the edge deploy window — pause it first; a payout issued by old code
   inside the window creates a transfer with no attempt row.

## 6. Rollback limitations — read before relying on rollback

- **Edge order is inverted on the way back.** The pre-package edges must be redeployed *before* running the
  `20260906120000` rollback, or every payout/refund/deletion call fails `PGRST202` on the now-missing RPCs.
- **The rollbacks refuse while money is in flight.** Each of the four payment rollbacks raises
  `rollback … REFUSED - unsafe state present` while any D-detector is non-zero — open payout attempts,
  unsettled payments, unresolved reviews, identities held only by BP-13. Draining is a deliberate operator step,
  not an automatic one. `app.rollback_force=on` exists but must not be used without a ticket.
- **Rollback order is enforced.** `20260906130000` must go before `120000`, `110000` before `100000`; an
  out-of-order attempt is refused (O1/O2).
- **Data survives only via the archive.** `payout_attempts`, `payment_refunds`, `account_deletions` and the
  `amount_refunded_cents` facts are archived into `rollback_archive` inside the rollback transaction and
  restored by the forward migration on re-apply; a second rollback refuses while an unrestored archive exists.
  Export with `\copy` as well.
- **The deploy window is not reversible.** A payout issued by old code after rollback produces a transfer with
  no attempt row, and the unique index is gone at that point, so a duplicate `tr_` is possible. Re-applying
  `120000` aborts on such a duplicate until an operator resolves it — proven in the rollback battery (F12–F13).
- **Migration 5 is trivially reversible** (drops one function) and is independent of the payment rollbacks.
- **Forward fix is preferred** once real financial rows exist under the new schema; rollback becomes unsafe as
  soon as the drain cannot be completed quickly.

## 7. Scope boundaries

### Resale / marketplace release — this package

Migrations 1–5, edges 3b, mobile 3c. Ships the payments-reliability work, the v2 consumer UI, the
reservation-cancellation fix and the Tickets **read** surface. `get_my_tickets` returns the defined **empty
set** in production because `kernel.tickets` is empty; it neither requires nor enables native issuance.

### Native issuance / scanning — NOT this package

Requires, in its own separately gated sequence: C3 (inserting the trust root into `kernel.signing_key`,
governed by `110`'s insert guard, with `111` as two-person recovery), key delivery to the door plane (`114`),
deploying the native edges, and flipping `feature.native_issuance_enabled` / `feature.native_scanning_enabled`.
None of that is in scope here and none of it is authorized.

**AWS status: see Claude B's ceremony record**,
`docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md` §SESSION 8 — C2–C5 complete, key
corroborated read-only, C3 not authorized and not performed. This package does not advance C2 or C3 and takes
no dependency on them.

## 8. Release-gate table

| Gate | Status | Detail | Owner |
|---|---|---|---|
| Candidate pinned + CI green at head | **PASSED** | **`187e69e`**, CI **34514320391**, five jobs green (supersedes `7986711` / 34320158401) | release integration |
| Migration chain verified both orders | **PASSED** | 18/18; identical function hash fresh vs production order | release integration |
| Rollback battery | **PASSED** | 63/63 incl. archive, restore, deploy-window duplicate | release integration |
| Repo test suites | **PASSED** | pgTAP 4698 · mobile 1531 · admin 96 · typecheck · lint · web build · deno | release integration |
| Migration immutability + ordering, G-4 | **PASSED** | zero errors; assembled migrations match committed slices | release integration |
| Production ledger reconciliation | **PASSED** | 135 vs 140; exactly 5 pending, each confirmed unapplied | release integration |
| Sandbox tickets RPC verified | **PASSED** | ledger row, `SECURITY DEFINER`, empty result for authenticated, 401 for anon | release integration |
| Compiled sandbox build environment | **PASSED** | one Supabase URL, one anon JWT, sandbox Stripe account, zero secrets | release integration |
| Sandbox edge source parity | **PASSED** | all 9 deployed edges byte-identical to the release head | release integration |
| **Handset QA — 11 cases on the preview build** | **READY TO RESUME** | replacement build **14** (`31846b72`) verified from head `187e69e`; D3/D4 + auth-logo already passed; D1, D2, D5–D11 outstanding on the new binary | Claude C |
| **D5 3-D Secure return + session fix** | **PASSED** | `aa8c8b3` reviewed across its full lineage and integrated at `187e69e`; CI 34514320391 green; every required check has behavioural coverage | release integration |
| **`notify-transfer` change is untested** | **PENDING EVIDENCE** | changed in this release but not deployed to the sandbox, so no QA covers it | Claude C / release integration |
| **Edge auth parity (`verify_jwt`)** | **PENDING EVIDENCE** | sandbox runs `verify_jwt=false`; "edge rejects unauthenticated" cannot be signed off from sandbox | Claude C |
| **Push routing on a real device** | **PENDING EVIDENCE** | `notify-transfer` absent in sandbox; push must be proven elsewhere | Claude C |
| **Partial-refund exactness in ops** | **IMPLEMENTATION NEEDED** | proposed `121_ops_console_refund_exactness`; server-only, client already supports `certainty:'known'`; §14 acceptance cases A1–A8 | release integration, after owner decision |
| **Public `auction-media` evidence exposure** | **UNRESOLVED RELEASE RISK** | see below | owner + release integration |
| Deletion amendment PFA-32 signature | **OWNER DECISION** | required before the deletion behaviour ships | owner |
| Stripe `payment_intent.canceled` subscription | **OWNER DECISION** | webhook endpoint change | owner |
| Legacy orphan reconciliation + payout-cron pause | **OWNER DECISION** | must be scheduled inside the deploy window | owner |
| `AUTODEPLOY-VERIFIED-OFF` on the merging PR | **OWNER DECISION** | date-only line; `git_branch` must be empty at merge time | owner |
| Apply/deploy authorization itself | **OWNER DECISION** | nothing in §3 is authorized today | owner |
| Twilio Account SID rotation | **OWNER DECISION** | identifier, not a secret; local history still holds it | owner |
| C3 / native issuance | **OUT OF SCOPE** | separately gated; see §7 and Claude B's record | owner + Claude B |

### Unresolved release risk — legacy evidence in the public `auction-media` bucket

**27 objects** — 16 `listings.proof_of_ownership_path` and 11 `transfers.transfer_evidence_path`, 41 MB across
8 owner folders — sit in a bucket whose policy is `public read public buckets`. They are ticket-ownership
documents (screenshots, confirmations, typically carrying names, order numbers and barcodes) and are fetchable
without authentication by anyone who knows or can enumerate the object path. The private-bucket policies that
gate `proof-docs` do not apply to them.

Scope is closed, not growing: of 35 listings with a proof path, 19 are already private and 16 are legacy; of 17
transfers with an evidence path, 6 are private and 11 are legacy; nothing has landed in `auction-media` as
evidence since 2026-07-02.

**Owner:** owner decision on scope, executed by release integration as its own change.
**Proposed remediation scope** (deliberately *not* bundled with this release): copy the 27 objects to
`proof-docs`, repoint `listings.proof_of_ownership_path` / `transfers.transfer_evidence_path`, verify each new
object is reachable only through the private policies, then delete the public copies — with a rollback that
restores the paths, and an explicit check that a tombstoned account's evidence is not resurrected into the new
bucket. A separate owner decision covers the 7 unreferenced objects (delete or archive). This is data movement
touching the deletion/tombstone machine and must not ride along with a schema release.


## 9. D5 — 3-D Secure return, and what it cost

Claude C's D5 run on build `aeb89616` failed **after the charge had already succeeded**. Financial result,
recorded and not to be touched: **one** successful $110.00 test charge, **one** succeeded payment, `Device D4`
sold, holds released, **one** pending transfer with payout correctly withheld, and **no** duplicate charge
despite browser refreshes. No retry, refund or manual settlement is authorized.

Two defects, one trigger — the browser handoff:

1. `initPaymentSheet` passed `returnURL: 'snatchit://checkout'`, but `app/checkout/` held only `[id].tsx`.
   The completed challenge deep-linked into a route that matched nothing, so expo-router rendered its
   unmatched/sitemap screen. The buyer saw a "404" after authorising a real payment.
2. The Supabase client sets `autoRefreshToken: true`, which is only a JS timer; iOS suspends those on
   backgrounding, which is exactly what the 3-D Secure handoff does. No `AppState` wiring existed anywhere
   (`startAutoRefresh` appeared zero times in the source), so the refresh loop stopped.

**Money was never at risk from re-entry.** `create-payment-intent` refuses with `409 This listing is already
sold` on both the buy-now and auction paths, so a second intent could not be created regardless of what the
client did. The defect is recovery and messaging, not double-charging.

### Review of fix `8f94cda` — required changes

| # | Finding | Severity |
|---|---|---|
| 1 | On re-entry after a successful buy-now charge the reservation pre-check bails into **"Your reservation has expired. Please go back and reserve again."** — a false failure on a completed purchase, the same class as the "contact support" defect this release removes. Needs a settled-payment lookup before the reservation pre-check, rendering the completed settlement state instead. | **blocking** |
| 2 | Tests assert **file contents** (`toContain`) and route existence. They cannot prove the re-entry rule. Behavioural tests needed over the setup path with Stripe and supabase mocked. | **blocking** |
| 3 | `src/config/envGuard.ts` still declares `EXPECTED_RETURN_URL = 'snatchit://checkout'` and F8 fails anything else. No runtime caller passes `returnUrl`, so nothing breaks today, but the guard and its test now assert a URL the app no longer sends. Needs a prefix rule. | required |
| 4 | `startSessionAutoRefresh()` calls `startAutoRefresh()` unconditionally at mount without consulting `AppState.currentState`. Teardown, single-listener and native-only wiring are correct. | minor |
| 5 | The stated root cause overreaches — see below. | required (record) |

### Root cause, corrected

`useAuth` signs out **only** on `'Invalid Refresh Token'` / `'Refresh Token Not Found'`. Read-only evidence
from the sandbox:

* `auth.audit_log_entries` is **empty (0 rows)** — the "three password logins, zero refresh grants" claim
  cannot be corroborated from the database.
* `auth.refresh_tokens`: 39 tokens, **2 revoked, 2 rotations ever**. The three sessions created 2026-09-10 at
  17:38, 17:42 and 17:45 each hold exactly one token with **zero** revocations and **zero** rotations.

That corroborates the real defect — the refresh loop never ran — but rules out the stale-token branch, which
requires a revocation that did not occur. The symptoms are fully explained without it: the access token expired
while the app was backgrounded, `getSession()` returned `session = null` with **no error**, and the else-branch
set the session to null. Home still showed a buyer it had rendered while the session was alive, `Buy Now`
correctly refused once `user?.id` was null, and a relaunch landed on sign-in.

Two things this establishes positively: the app does **not** treat a transient network failure as revocation
(the phrase list is narrow), and the proposed fix does not weaken that — it starts and stops only the refresh
the client was already configured to perform.


## 10. D5 repair verified and built — 2026-09-10

Integrated `aa8c8b3` at release head **`187e69e2b95ec94bed04f387c205ad0c2cf92827`**; CI **34514320391**
green on all five jobs. Replacement sandbox preview build **`31846b72-f10b-4cc2-9208-4e32383f83c6`**,
iOS build number **14**, supersedes build 13.

Required checks, all satisfied by behavioural tests (1588 tests / 64 files):

| Requirement | Evidence |
|---|---|
| Authenticated v3 encryption, fresh 24-byte nonce per write | XChaCha20-Poly1305 from `@noble/ciphers` 2.4.0; key and nonce lengths enforced; two writes of the same plaintext differ |
| No AES-CTR keystream reuse | fixed `Counter(1)` exists only on the legacy **read** path; asserted that only v3 is written |
| Torn-write interruption, both orders | interruption after the Keychain write and on the Keychain write itself; previous session intact in both |
| Concurrent first writes produce one key | `loadOrCreateKey` memoises in flight; both blobs stay readable |
| Legacy and v2 migrate without deletion | both decrypt, are rewritten as v3, and a migration that cannot write still returns the session |
| Unavailable Keychain/AsyncStorage preserves ciphertext | typed `unavailable` outcome returns null and clears nothing; only a missing key or a failed AEAD clears |
| Tampered/truncated v3 fails safely | flipped bit, truncation, wrong key and non-hex all raise `undecryptable`; never garbage plaintext |
| No token material in logs | asserted every `warn` call carries a message and an error, never the session value |
| Settled re-entry creates/submits nothing | buy-now and auction: no intent, no `initPaymentSheet`, no `presentPaymentSheet`; two rapid re-entries share one in-flight setup |
| Return URL and fallback route | F8 accepts only `snatchit://checkout/<id>`; bare, empty-id, foreign path and foreign scheme all refused; the bare-link floor redirects Home and claims nothing |
| `AppState.currentState` gates initial refresh | covered, with teardown and transition tests |
| Metro installs and bundles `@noble/ciphers` | proven by a local `expo export` Hermes bundle **and** by the shipped IPA |

**Root-cause wording.** The torn-write mechanism is **supported** by the storage evidence and by the
server-side record (empty `auth.audit_log_entries`; three 2026-09-10 sessions each with one token, zero
revoked, zero rotations). **Token expiry remains conditional** on the sandbox `jwt_exp` value, which has not
been read, and is not claimed as established. The missing AppState refresh wiring is recorded as a **latent**
defect, separate from the reproduced storage defect. Claude C's earlier commit messages were left as written.

The original D5 payment remains settled exactly once: one $110 charge, one succeeded payment, `Device D4`
sold, holds released, one pending transfer with payout withheld. Nothing was retried, refunded or manually
settled, and the shared sandbox backend is unchanged at ledger 129.
