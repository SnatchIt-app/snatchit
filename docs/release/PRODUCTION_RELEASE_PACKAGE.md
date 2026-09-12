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
| Candidate pinned + CI green at head | **PASSED** | **`df9e0d3`**, CI **34523989011**, five jobs green (supersedes `5bf2daa` / 34518588051) | release integration |
| Migration chain verified both orders | **PASSED** | 18/18; identical function hash fresh vs production order | release integration |
| Rollback battery | **PASSED** | 63/63 incl. archive, restore, deploy-window duplicate | release integration |
| Repo test suites | **PASSED** | pgTAP 4698 · mobile 1531 · admin 96 · typecheck · lint · web build · deno | release integration |
| Migration immutability + ordering, G-4 | **PASSED** | zero errors; assembled migrations match committed slices | release integration |
| Production ledger reconciliation | **PASSED** | 135 vs 140; exactly 5 pending, each confirmed unapplied | release integration |
| Sandbox tickets RPC verified | **PASSED** | ledger row, `SECURITY DEFINER`, empty result for authenticated, 401 for anon | release integration |
| Compiled sandbox build environment | **PASSED** | one Supabase URL, one anon JWT, sandbox Stripe account, zero secrets | release integration |
| Sandbox edge source parity | **PASSED** | all 9 deployed edges byte-identical to the release head | release integration |
| **Build 15 device cold-launch gate** | **PASSED 2026-09-10** | installs, launches, badge visible, sign-in works on the real native RNG, session survives force-quit + cold launch; corroborated server-side (§13) | owner + release integration |
| **Handset QA — 11 cases on the preview build** | **D8 NEXT** | D2, D5, D6, D6b, **D7 all passed** on build 16; D8–D11 outstanding (§20) | Claude C |
| **Sandbox↔production FK drift on `transfers`** | **RESOLVED in the sandbox** | migration **123** applied and verified (§19); still to ride the normal release path to production, where it is a proven no-op | release integration |
| **`bids_bidder_id_fkey` drifts the same way** | **OWNER DECISION** | latent — no code embeds profiles off bids today (§18) | release integration |
| **False "Transfer not found" copy** | **IN REVIEW, isolated** | Claude C's `5569385` splits not_found / offline / unavailable; one blocking copy change requested (§20) | Claude C |
| **Legacy transfer screens → V2 design system** | **IN PROGRESS, isolated** | owner-requested; must not touch the pinned candidate (§20) | Claude C |
| **3-D Secure automatic return (`handleURLCallback`)** | **PASSED on device** | build 16: the browser returned automatically after Authorize and checkout reached success; single-payment invariant confirmed server-side (§16) | release integration |
| **Build-13 legacy blob migration on a real device** | **OPEN — known gap** | never exercised on hardware; deleting build 14 cleared storage, so launch 1 was a fresh install (§13) | owner decision |
| **D5 3-D Secure return + session fix** | **PASSED** | AEAD, re-entry and runtime crypto all reviewed and verified (§10, §12) | release integration |
| **Runtime crypto availability** | **PASSED** | entry-first polyfill, guarded injectable RNG, named `RandomnessUnavailable`, Math.random fallback refused, Hermes smoke `SMOKE_OK` | release integration |
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


## 11. Build 14 BLOCKED — `ReferenceError: Property 'crypto' doesn't exist`

Reported from a handset against build `31846b72` (iOS build 14), Sentry environment `sandbox`, issue
`19d8d967a00043a59a889fe8e7dfa3b3`. The app crashes **before authentication**. **Build 14 must not be
shipped or used for QA**, and no further handset payment tests are to be requested.

### Cause, pinned to a commit

`git grep -l react-native-get-random-values` per commit:

```
9aae63f  -> src/lib/secureStorage.ts
a050125  -> src/lib/secureStorage.ts
aa8c8b3  -> (nothing anywhere in the tree)
```

The refactor in `aa8c8b3` that gutted `secureStorage.ts` and moved the RNG call into the new
`sessionCipher.ts` carried the call but **not** the `import 'react-native-get-random-values';`.
`sessionCipher.ts:51` calls a bare `crypto.getRandomValues(...)`; Hermes has no `crypto` global, so the first
session write throws. The dependency is still declared (`~1.11.0`) — only the import is missing.
`@noble/ciphers` also throws when the runtime lacks `crypto.getRandomValues` (`utils.js:799`), though on this
path the nonce is passed explicitly so its internal RNG is not reached.

### Why the pre-build verification did not catch it

Two checks were run before approving build 14, and **neither could have caught this**:

* the AEAD round-trip ran under **Node**, which has a global `crypto`;
* the Metro check (`expo export`) proves **module resolution**, not runtime globals.

A bundle that resolves and a cipher that works in Node say nothing about Hermes at runtime. That is the gap,
and it is the reason real runtime behavioural tests are now a release requirement rather than a nicety.

### Required before a replacement build is approved

| # | Requirement |
|---|---|
| 1 | Polyfill imported at the **app entry**, first import, ahead of any module that can reach the cipher — not in a leaf module, where evaluation order is incidental. `expo-crypto`'s native `getRandomBytes` is an acceptable alternative; pick one single source. |
| 2 | No bare global in library code: an injectable randomness source that throws a **named, legible** error when unavailable. |
| 3 | A startup availability check that fails closed with a readable message rather than a `ReferenceError` inside a storage call. |
| 4 | A regression test that **deletes `globalThis.crypto`** and exercises the real write path — it must succeed through the injected source or raise the named error, never a bare `ReferenceError`. |
| 5 | A test asserting the entry imports the polyfill before any cipher-reaching module, asserted on the import graph rather than on file text. |
| 6 | A session round-trip executed under **Hermes**, not Node. If no Hermes runtime is available locally, that gap is to be stated explicitly and on-device becomes the gate — an honest gap beats a green check that means nothing. |
| 7 | Everything already accepted stays intact: v3 XChaCha20-Poly1305 with a fresh 24-byte nonce per write, no AES-CTR keystream reuse, legacy/v2 read-and-migrate without deletion, torn-write behaviour in both orders, concurrent first writes minting one key, typed outcomes, no token material in logs. |

Approval of a replacement requires the crash fixed, the deleted-global test passing, CI green, bundle checks
green, **and** evidence that the crypto path actually executes at runtime.

Unchanged throughout: production, AWS, Supabase, flags and payment rows. The D5 payment remains one captured
$110 test charge and must not be retried.


## 12. Runtime crypto fix verified — build 15 — 2026-09-10

Integrated `9196123` at head **`5bf2daa04708acefddc435c4af745806f6bdb4e6`**; CI **34518588051** green on all
five jobs. Preview build **`cbb3fbbe-0bc1-4898-987b-ad9b8de03b72`**, iOS build number **15**, supersedes 13
and 14. EAS records `Commit 5bf2daa04708acefddc435c4af745806f6bdb4e6` — the pinned SHA.

### Review

| Requirement | Evidence |
|---|---|
| RN/Expo-compatible randomness | `react-native-get-random-values` is the **first import** of `app/_layout.tsx`. `src/lib/randomness.ts` refuses `no_global` and `no_native_module`, accepts `ExpoCrypto` or `RNGetRandomValues`, and runs a liveness self-test. |
| Math.random fallback refused | `insecure_fallback` is detected and rejected for session keys, with a test. |
| Named failures | `RandomnessUnavailable`, whose message names the missing polyfill; asserted under Hermes, never a bare `ReferenceError`. |
| Import graph, not text | Tests assert the polyfill is first in depth-first evaluation order from the entry, that the cipher is genuinely reachable from the entry, and that **no** module reachable from the entry reads the `crypto` global except the guarded randomness module. |
| AEAD preserved | v3 XChaCha20-Poly1305, fresh 24-byte nonce per write; no AES-CTR keystream reuse; legacy/v2 read-and-migrate; torn-write recovery both orders; one key under concurrent first writes; no token material logged. |
| `TextDecoder` | Removed from the cipher — Hermes has `TextEncoder` but **no** `TextDecoder`, a second latent cold-launch crash. Strict pure UTF-8 codecs replace it and a test forbids reintroduction. A repo search of the native application path finds **zero** uses. |
| Metro / native bundle | `expo export` succeeds; the shipped IPA carries `RNGetRandomValues`, `RandomnessUnavailable`, `react-native-get-random-values`, `xchacha20poly1305`, `v3.`, `snatchit://checkout/`, `already_settled`. |
| Real runtime test | `PORT=8083 npm run smoke:hermes` → **`SMOKE_OK`**. The real cipher and store, bundled by the project's own Metro and executed by the **Hermes CLI with no `crypto` global**: the named error without a source, then v3 write, restore, legacy migration and tamper rejection with an injected source. |

**One bundle finding, investigated and cleared.** The shipped bundle contains a single `new TextDecoder`.
It is not ours: it is inside `@sentry-internal/replay`'s bundled worker (an inlined `fflate`), written as
`"undefined" != typeof TextDecoder && new TextDecoder` with the follow-up `decode` in a `try/catch`. It
feature-detects, cannot throw at module scope on Hermes, and is not on the session or auth path.

### Compiled environment — read from the shipped IPA of build 15

Exactly one Supabase URL `https://ofaidukbieeekqaboscm.supabase.co`; exactly one JWT, `ref = ofaidukbieeekqaboscm`,
`role = anon`; Stripe `pk_test_51T6Fb1Gl…` → **`acct_1T6Fb1GlD5aqtxIw`**; **zero** matches for
`pk_live_51T6Far`, `sk_test`, `sk_live`, `service_role`, `SUPABASE_SERVICE`; `SANDBOX — TEST MONEY ONLY`
present once (UTF-16LE); `CFBundleVersion` **15**; build page HTTP 200.

### Upgrade-path evidence, and what is still device-only

Verified here: a blob produced by **build 13's exact algorithm** (`9aae63f`: fresh key, fixed `Counter(1)`,
bare hex) is byte-identical to `encryptLegacyForTests`, and the integrated code reads it, labels it `legacy`
and migrates it to v3 **without deleting ciphertext**. The same path executes under real Hermes in the smoke.
`session-store-hermes.test.ts` covers the build 13 → 14 upgrade explicitly, plus v2 migration, a locked
Keychain at launch (signed out this time, ciphertext intact, recovered next launch) and a tampered blob
clearing cleanly.

**Not verifiable off-device, and therefore outstanding:**

1. Cold launch of build 15 **on the handset with a build-13/14 session already persisted** — the real
   Keychain, the real AsyncStorage, the real native RNG.
2. Cold launch again **after the upgrade**, confirming the session is preserved or fails with a named guarded
   outcome — never a crash, never a silently deleted ciphertext.

The lesson from build 14 stands: a green bundle and a Node round-trip are not runtime evidence. The Hermes
smoke closes most of that gap, but the native modules cannot run in the bare engine, so these two remain
device-only and must pass before the payment matrix resumes.


## 13. Build 15 cold-launch gate — PASSED, 2026-09-10

Run on the owner's iPhone against build `cbb3fbbe` (build number **15**, source `5bf2daa`).

| Check | Device observation | Server-side corroboration | Verdict |
|---|---|---|---|
| Install + launch | installs, launches normally, no crash | — | **PASS** — the build-14 `ReferenceError: Property 'crypto' doesn't exist` is gone on real hardware |
| Sandbox badge | `SANDBOX — TEST MONEY ONLY` visible | — | **PASS** — the environment guard resolved a sandbox pair; no `F1`–`F8` blocker |
| First cold launch | signed out (deleting build 14 cleared storage), signed back in with no error | session `dd928989…` created `19:31:49.064813`, 1 token, 0 revoked | **PASS** — a fresh install, not a failure. Sign-in writes a v3 blob, drawing a 24-byte nonce from the **real native RNG** — the exact path that killed build 14 |
| Force-quit + second cold launch | still signed in, badge still visible, no error, no Sentry event | `sessions_total` **41**, unchanged; sessions strictly newer than `dd928989…`: **0**; that session still 1 token, 0 revoked, `updated_at` unmoved | **PASS** — the session was restored from the v3 blob; no re-authentication occurred |

Device report and server state agree: **no password login and no new session** followed the first sign-in.

One measurement caveat worth recording so it is not over-read: a boundary query with truncated seconds
(`created_at > '…19:31:49+00'`) returns **1**, because `dd928989…` is itself stored at `19:31:49.064813`.
Compared against that row's own timestamp the count is **0**. The correct reading is zero new sessions.

**What this does not yet prove.** `dd928989…` shows **0 rotations**, so the AppState refresh wiring has not
fired — expected for a session minutes old against a one-hour token lifetime. The cold-launch gate does not
speak to it either way; a rotation appearing on a longer-lived session is the evidence to look for.

### Known gap — build-13 legacy blob migration on real hardware

Deleting build 14 cleared the app's storage, so the first build-15 launch was a **fresh install**. The
build-13 legacy-format blob path was therefore **never exercised on a device**. It is verified byte-for-byte
against `9aae63f`'s exact algorithm, under real Hermes in the smoke, and in
`session-store-hermes.test.ts` — but not against a real Keychain and a real AsyncStorage.

Risk is bounded: it applies only to a device upgrading **from build 13 with a session in place**, which is now
a single handset, and the failure mode is a sign-out, never a crash or a money defect. Closing it needs a
device-side write of a legacy-format blob followed by a launch, which cannot be staged off-device. **Owner
decision: accept the gap, or schedule the device-side exercise.** It does not gate the payment matrix.

### Payment QA may resume, starting at D2

The gate is complete and the matrix is unpaused. Guidance for the next case:

* **Use `Device D5`** for D2. It is the only staged listing with **no payment history at all** (`payments = 0`),
  so a fee-total check is not confounded by a stale pending row. `Device D1` carries 2 pending rows,
  `D2`/`D3`/`Phone P1` one each; `D4`, `Phone P2` and `Phone P3` are sold.
* D2 is the fee-total check: open the listing → **Buy Now** → confirm the total reads **$110.00** with the
  service fee shown as 10%. Opening checkout creates a PaymentIntent but **no charge**; dismissing the sheet
  leaves a pending row, which is expected and harmless.
* **$110.90 or any fixed fee is a stop condition** — the model must stay 10% buyer / 10% seller.
* Unchanged sandbox caveats, neither a bug: `notify-transfer` and `auto-finalize-auctions` are not deployed
  there, and all nine sandbox edges run `verify_jwt=false`.
* **Device D4 stays untouched** — one captured $110 test charge, not retried and not modified.


## 14. D5 — money correct, browser return not wired (2026-09-10)

### Financial result: clean, and not to be touched

Exactly **one** succeeded $110 sandbox payment, **one** PaymentIntent, **one** captured charge, **no**
duplicate intent, `Device D5` sold, hold released, **one** pending transfer with no payout id, and **no**
webhook retries. The settlement path behaved correctly throughout. No retry, refund or manual settlement is
authorized, and `Device D5` must not be reused for the re-test.

### The defect

Acceptance failed on one point only: after **Authorize**, the 3-D Secure browser did not return to the app
automatically. Exiting manually let checkout complete normally. Claude C traced it to
`handleURLCallback(url)` never being wired.

**This is a wiring defect, not a money defect.** The charge succeeded, settled once, and produced no
duplicate — the failure is that the buyer had to dismiss a browser by hand.

### Review — concurred, with three refinements

Verified against the installed `@stripe/stripe-react-native` **0.50.3**:

| Point | Finding |
|---|---|
| Placement outside `StripeProvider` | **Correct.** The deep-link listener does run outside the provider. |
| How to reach the function there | `index.d.ts` does `export * from './functions'`, and `functions.d.ts` declares `export declare const handleURLCallback: (url: string) => Promise<boolean>`. The **module-level import** needs no provider context — use it rather than `useStripe()`. |
| Early return | The implementation is `Platform.OS === 'ios' ? await NativeStripeSdkModule.handleURLCallback(url) : false`. `true` means Stripe consumed the URL, so **return immediately** and never let the auth branch parse a Stripe redirect for `token_hash`/`code`. Android returns `false`, so the auth path is unaffected. |
| One placement covers both entry points | `NativeAppShell.native.tsx:246-247` funnels `Linking.getInitialURL()` **and** the `'url'` event through the same `handleUrl(url)`. Calling it at the top of that function covers the warm return **and** the cold-start case where iOS killed the app during the handoff. No second listener. |

Tests must be behavioural, not `toContain` on source: a Stripe URL takes the early return with the auth
exchange never invoked; an auth deep link still runs `verifyOtp` / `exchangeCodeForSession` exactly as today;
both the initial-URL path and the `'url'` event reach the call; and a rejection does not break the auth path.
The real browser return stays device-only — these prove wiring, not the redirect.

### Plan

1. Claude C stacks the fix on **`frontend/d5-3ds-return-and-session`** on top of `9196123` — not on
   `5bf2daa`. Keeping the D5 lineage in one reviewed chain is the flow that has worked twice; no rebase.
2. Release integration merges it into the candidate, runs the full battery and CI.
3. **Build 16** is cut before any QA resumes. D6–D11 do **not** continue on build 15.
4. Device re-test of D5 uses a different listing. Every remaining staged listing carries a stale pending row
   (`Device D1` two; `Device D2`, `Device D3`, `Phone P1` one each), which is harmless for a browser-return
   test. `Device D3` is the suggested choice.


## 15. Build 16 — 3-D Secure return fix (2026-09-10)

Integrated `a8adfb1` at head **`df9e0d3718086907faeff538fbba5b62bae38a1e`**; CI **34523989011** green on all
five jobs. Build **`66be8872-163a-43c6-99ed-71de752f5f16`**, iOS build number **16**; EAS records
`Commit df9e0d3718086907faeff538fbba5b62bae38a1e` — the pinned SHA.

### Diff review

`a8adfb1` extracts the URL handling into `src/lib/auth/deepLinkDispatch.ts` — pure orchestration with injected
effects — and rewires the shell to it. All three review refinements are present:

| Refinement | Implementation |
|---|---|
| Module-level function, not the hook | `import { StripeProvider, handleURLCallback } from '@stripe/stripe-react-native'`, injected as `stripeCallback`. No provider context needed, which is what the shell's position outside `StripeProvider` requires. |
| Early return on `true` | `if (await deps.stripeCallback(url)) return { kind: 'stripe' }` — the auth branch never parses a Stripe redirect for `token_hash`/`code`. |
| One funnel | `attachDeepLinkFunnel` routes `getInitialURL()` (cold start behind the browser) and the `'url'` event through the same dispatch; the effect returns its teardown. No second listener. |

Beyond the brief: a Stripe callback **rejection** is caught and the auth path still runs. The H-5 contract is
preserved verbatim — only `verifyOtp` and `exchangeCodeForSession` may mint a session, and there is still no
`setSession`-from-URL path.

Tests are behavioural: call ordering, no auth exchange when Stripe consumes the URL, auth links unchanged for
`token_hash`/`type` and for `code` including fragment parameters, both entry points reaching one dispatch, and
a rejection not breaking auth.

### Verification

Local: **1626 tests / 67 files**, admin 96/96, typecheck clean, lint 0 errors, env pairing OK, Hermes smoke
**`SMOKE_OK`**. Shipped IPA: `handleURLCallback`, `attachDeepLinkFunnel`, `dispatchDeepLink` and the
rejection-warning string all compiled in; exactly one Supabase URL (sandbox); one JWT scoped to the sandbox;
`pk_test_51T6Fb1Gl…`; **zero** `pk_live`/`sk_`/`service_role`; SANDBOX badge present; `CFBundleVersion` **16**;
build page HTTP 200.

**On the fingerprint.** Build 16 reports the same Expo fingerprint as build 15 (`1fa6c258…`). That is expected
and not a sign the build is unchanged: the fingerprint covers the **native** layer — native files, app config,
dependency set — and this change is JS-only. The shipped JS bundle differs (`sha256 c336cd04…`) and carries
the new symbols, which is the check that matters.

### Still device-only

The actual browser return after **Authorize** cannot be proven off-device. The tests prove the URL reaches
Stripe first and that the auth contract is intact; only a handset shows whether iOS dismisses the browser and
resolves the sheet. **QA stays paused** until the D5 return is re-tested on build 16.

Use a listing other than `Device D5`, which is sold and settled. Every remaining staged listing carries a
stale pending row (`Device D1` two; `Device D2`, `Device D3`, `Phone P1` one each) — harmless for a
browser-return test. `Device D3` is the suggested choice. Device D4 and Device D5 payments stay untouched.


## 16. D5 re-test on build 16 — PASSED, server-side confirmed (2026-09-10)

Run on `Device D3` (build 16, `66be8872`, source `df9e0d3`). Device observation: after completing 3-D Secure
the browser **returned to the app automatically** and checkout reached the success state — no white page, no
404, no reservation-expired message, no manual browser exit. The `handleURLCallback` wiring works on real
hardware.

### Single-payment invariant — CONFIRMED

| Check | Result |
|---|---|
| Listing | `Device D3` **sold** 20:49:56; `reserved_by` and `reserved_until` both NULL — hold released |
| Payment rows | **2**: `e569d654` **failed** (the superseded 17:47 intent) and `ca594f76` **succeeded** |
| **Succeeded payments** | **exactly one** |
| Amounts | item $100.00 · buyer fee $10.00 · seller fee $10.00 · **total $110.00** — 10%/10% intact |
| `stripe_livemode` | `false` |
| Stripe PaymentIntents | **2**: `pi_3UEEuMG…` **succeeded** with one charge, `pi_3UEC4oG…` **canceled** with **no charge** |
| **Captured charges** | **exactly one** — `ch_3UEEuMG…`, `captured=true`, `refunded=false`, `amount_refunded=0`, `disputed=false` |
| Transfer | 1 row, `pending`, **no payout id**, not released — payout correctly withheld |
| Payout attempts | 0 |
| Refunds | 0 |
| Webhook retries for this listing | **0** |

The stale pending row from 17:47 did not become a second charge: `create-payment-intent` marked it `failed`
and **cancelled its intent at Stripe**. Two intents, one charge — the invariant holds, and the supersede path
behaved exactly as designed.

**Pre-existing residue, unrelated:** one unresolved `webhook_retries` row from **2026-09-08 00:57:53**,
`settle_verified_payment` / `unknown_payment:pi_3UDDMB…`, with no listing attached. It predates this test by
two days and belongs to the old diagnostic session. Noted so it is not mistaken for a D3 finding; it does not
gate the matrix.

### Matrix resumed

D2 and D5 are complete on build 16. Remaining: **D6–D11** (and D1/D3/D4 only if attribution to this binary is
wanted — they passed on build 13).

Listing budget is tight: `Device D3`, `Device D4`, `Device D5`, `Phone P2` and `Phone P3` are sold. Three
remain, all with a harmless stale pending row: `Device D1` (2), `Device D2` (1), `Phone P1` (1). Suggested
allocation, since D8 and D9 each consume one and D6 consumes none:

* **D6** (3-D Secure cancellation) → `Device D2` — cancelled, so the listing survives
* **D8** (pending-payment recovery, force-quit) → `Device D1`
* **D9** (connection loss, Airplane Mode) → `Phone P1`
* **D7** (order + listing state) → read-only against `Device D3`, already sold
* **D10/D11** (deletion messaging and withdrawal) → need an unsettled order; run after D8 or D9

`Device D4` and `Device D5` payments stay untouched — neither is to be retried or modified.


## 17. Second 3-D Secure completion, and the D6 setup (2026-09-10)

### `Device D2` — a completion, not a cancellation

The run on `Device D2` tapped **Complete authentication**, not Cancel or Fail. It is recorded as **another
successful authentication/payment flow**, and **D6 remains un-run**.

Server-side, the same clean pattern as `Device D3`:

| Check | Result |
|---|---|
| Listing | **sold** 20:58:47, hold released |
| Payment rows | 2: `f7762166` **failed** (the superseded 2026-09-08 intent), `be791912` **succeeded** |
| **Succeeded payments** | **exactly one** — $100.00 + $10.00 + $10.00 = **$110.00**, `livemode=false` |
| Stripe intents | 2: `pi_3UEF3IG…` **succeeded** with `ch_3UEF3IG…`; `pi_3UDGM3G…` **canceled**, no charge |
| **Captured charges** | **exactly one** |
| Transfer | 1 row, `pending`, no payout id — payout withheld |
| Webhook retries | 0 |

That is now **two independent 3-D Secure completions** on build 16 (`Device D3`, `Device D2`), each settling
exactly once on a listing that already carried a stale pending row. `Device D2` stays settled once and must
not be retried.

### Sandbox prepared for D6

**`Device D6` created** — `c46a79a3-cc78-4997-819e-db4ca20c0c30`, $100 buy-now, `active`, **zero payment
history**, ends in 14 days. Synthetic fixture matching the existing staged listings; no financial state
touched.

**Two expiry problems found and fixed while preparing it**, without which D8 and D9 would have failed for the
wrong reason:

* **`Phone P1` had already expired** — `ends_at` 2026-09-10 03:44:25, nearly **20 hours** in the past. It
  still read `active` only because the sandbox expiry cron is disabled by design, so browse hid nothing but
  checkout would have refused it.
* **`Device D1` was ~4 hours from expiry.**

Both were extended to **14 days**. Nothing else about them changed — `Device D1` keeps its two stale pending
rows and `Phone P1` its one, which are harmless for D8 and D9.

Current inventory: `Device D1` (active, 2 pending), `Device D6` (active, clean), `Phone P1` (active, 1
pending). `Device D2`, `D3`, `D4`, `D5`, `Phone P2`, `P3` sold.

### The exact cancellation control for D6

The Stripe test 3-D Secure page for `4000 0025 0000 3155` offers **two** buttons, and **neither is a
cancellation**:

* **Complete authentication** → the challenge succeeds and the payment goes through. This is what was tapped
  on `Device D2`.
* **Fail authentication** → the challenge completes with a *failure*; the PaymentIntent is **declined**. This
  is a decline, not a cancellation — a different case.

**D6's cancellation is the browser's own control, not a button on the Stripe page:** the **Cancel** (or
**Done**) control in the **top-left of the browser bar** above the page content. Tapping it abandons the
challenge and returns a *canceled* result to the PaymentSheet.

| Case | Control | Expected |
|---|---|---|
| **D6 — cancellation** | **Cancel / Done, top-left of the browser bar** | returns into the app, **no charge**, no alarming alert, listing still buyable |
| D6b — decline (optional) | **Fail authentication** on the page | returns into the app, payment declined, **no charge**, listing still buyable |

Neither consumes the listing, so `Device D6` can serve both. Run **D6 first**; if it passes, D6b is a free
extra on the same listing.

`Device D1` stays reserved for **D8**, `Phone P1` for **D9**. Device D2, D3, D4 and D5 payments are settled
and must not be retried or modified.


## 18. D7 — "Transfer not found" is sandbox schema drift, not an app defect (2026-09-10)

`Device D3`'s order shows **Paid $110** and the sold listing correctly offers no Buy Now. Tapping **View
transfer** shows **"Transfer not found"** — while the transfer plainly exists. Traced against the pinned
build 16 source (`df9e0d3`).

### The trace

Routing is correct. `ListingDetailScreen` sends a buyer to `/transfer/receive/<id>` and a seller to
`/transfer/send/<id>`, and `transferId` is populated by a query that succeeds (which is why the button
appears at all).

The receive screen then runs:

```
.from('transfers')
.select('… seller:profiles!seller_id(display_name), listing:listings!listing_id(event_name, ticket_platform)')
.eq('id', id).eq('buyer_id', userId).single()
```

Reproduced as the real signed-in buyer against the sandbox:

| Probe | Result |
|---|---|
| **A** — the exact query, both embeds | **HTTP 400**, `PGRST200`: *"Searched for a foreign key relationship between 'transfers' and 'profiles' using the hint 'seller_id' … but no matches were found."* |
| **B** — identical query **without** the `profiles` embed | **HTTP 200**, full row returned: `status=pending`, listing embed resolves |
| **D** — the seller's send-screen shape (`buyer:profiles!buyer_id`) as the seller | **HTTP 400**, same `PGRST200` |
| **E** — buyer reading the seller's `profiles` row directly | **HTTP 200** |

So it is **not a missing record** (B returns it), **not an authorization failure** (RLS is never reached —
the request dies in schema-cache relationship resolution, and E shows the buyer may read profiles anyway),
and **not a loading error**.

### The actual cause — environment drift, and the app is right

| Environment | `transfers.buyer_id` / `seller_id` |
|---|---|
| **Production** | `REFERENCES profiles(id)` |
| **Sandbox** and every fresh replay of the repo chain | `REFERENCES auth.users(id)` |

**The app code is correct and works in production.** The embeds are unresolvable only in environments built
from the repo's migration chain. The embeds date to the **initial commit** and are present at the
pre-convergence base `10ad9e42` — this is neither a regression from the convergence, nor from the v2 UI, nor
from any D5 work.

**The finding therefore inverts:** D7 does not indict build 16. What it exposes is that **the repo's migration
chain does not reproduce production's schema** on these two constraints — the class of gap the Phase-0 note
warns about with "main reproduces prod ~99%". Any environment built from the chain — the sandbox, CI's fresh
DB, the local rehearsal — differs from production here, so any QA or parity assertion that leans on those
embeds is invalid off-production.

### Two separable defects

1. **Schema fidelity (owner decision).** A migration aligning the chain's FK targets to production's
   `profiles(id)` would be a **no-op against production** and would fix every fresh environment. It touches an
   applied table, so it needs its own authorization, and it must be **proved a no-op against production before
   apply** using the documented technique. The alternative is to accept the divergence and record it as a
   known non-parity, but then the transfer screens can never be QA'd outside production.
2. **False copy (app, implementation needed).** `app/transfer/receive/[id].tsx:90` and
   `app/transfer/send/[id].tsx:86` map **every** non-network error to the literal `'Transfer not found'`. A
   400 schema error is thus reported to the user as a missing record. Under this release's own principle —
   never state a failure that did not happen — these should separate `PGRST116` (no row, or not yours) from a
   request/schema error, which should surface its own distinct message. This mis-mapping is what disguised an
   environment gap as missing data for an entire QA cycle, and it is worth fixing regardless of how the FK
   question is decided.

### Status

**D7 stays open. D8 and D9 remain paused.** Nothing was recreated, retried or altered: the transfer row, the
settled order and the payment are untouched, and no schema change was applied anywhere.

## 19. Migration 123 applied to the sandbox — 2026-09-10

Owner-authorized, **sandbox only** (`ofaidukbieeekqaboscm`). No production change, no venue acceptance, no
mobile build. Executed via `scripts/release/apply_123_transfers_fk_sandbox.sh`.

### Preflight (unchanged from the earlier dry run)

```
baselines:   transfers=31  payments=46  listings=47  profiles=7  ledger=129
fk targets:  transfers_buyer_id_fkey -> auth.users  |  transfers_seller_id_fkey -> auth.users
orphans:     0
ledger 123:  (absent)
```

### Apply

Both constraints retargeted, each logging its own notice. Ledger row written once, no `ON CONFLICT`:
`version=123  name=transfers_profiles_fk_parity  statements=1  chars=4950  md5=e34a675450ea76c4ed41a3ce43ce39f1`,
matching the expected md5 exactly.

### Verification

| Check | Result |
|---|---|
| V1 | both FKs → `profiles`, `upd=a del=a match=s validated=true deferrable=false` — production's exact shape |
| V2 | `dispute_resolved_by` still → `auth`, untouched |
| V3 | 5 foreign keys on `transfers`, unchanged |
| V4 | RLS enabled, all 5 policies present |
| V5 | transfers **31**, payments **46**, listings **47** — identical to preflight |
| V6 | ledger **130** rows (129 + 1), `123` recorded exactly once |
| V7 | ledger content matches the migration file by md5 |
| **Buyer embed** | `seller:profiles!seller_id(display_name)` → **HTTP 200**, embed resolved (was 400 `PGRST200`) |
| **Seller embed** | `buyer:profiles!buyer_id(display_name)` → **HTTP 200**, embed resolved |

PostgREST picked the change up immediately; no schema-cache reload was needed.

### Nothing financial moved

`Device D3` still `sold` at 20:49:56; its payment still `succeeded`, **$110**, `paid_at` unchanged; its
transfer still `pending` with **no payout id** and nothing released. Project-wide totals unchanged:
19 succeeded payments, 4 transfers with a payout, 18 refund rows. The migration touched constraints only.

### One expected cosmetic on the handset

`seller.display_name` is **null** — the synthetic sandbox seller never had one set. The transfer screen may
show a blank or placeholder seller name. That is data, not a defect, and must not be read as a failure of this
fix.

### Build 16 unchanged

No mobile build was produced. The candidate stays pinned at `df9e0d3`; Claude C's corrected error copy is
being reviewed separately and deliberately **not** combined with this verification.


## 20. D7 CLOSED, and what is held aside (2026-09-10)

### D7 — passed on unchanged Build 16

After migration 123, **View transfer opens**: `Device D3`, **Pending**, mobile transfer, seller **"Unknown"**,
and the delivery-info form. The order reads **Paid $110**; the sold listing offers **no Buy Now**. No delivery
information was submitted and no delivery was confirmed.

Verified server-side after the re-test: transfer still `pending`, `delivery_email` and `delivery_phone` both
NULL, `buyer_confirmed_at` NULL, `seller_sent_at` NULL, no payout id. Counts unchanged — transfers **31**,
payments **46**, listings **47**, ledger **130**. The re-test wrote nothing.

Seller **"Unknown"** is the app rendering a null `display_name` gracefully; the synthetic sandbox seller never
had one. Correct fallback, not a defect.

**All four required D7 checks are satisfied** — order total, no Buy Now on the sold listing, the transfer
opening with correct state, and no seller-only controls offered to the buyer. **D7 is closed.**

Worth stating plainly: D7 was never an app defect. It was schema drift between the repo's chain and
production, and the app was right the whole time.

### D8 baseline, captured fresh

`Device D1` — `086dd027-fcd2-4cec-86a5-d753b8b2efb4`, `active`, $100 (total $110), no reservation, 13d 22h
left. Two payment rows: one `failed` (2026-09-08) and one **`pending`** (2026-09-10 17:43,
`pi_3UEC0DGlD5aqtxIw1G3EBTRn`, which at Stripe is `requires_payment_method`, $110.00, **no charge**). Zero
transfers, zero succeeded payments.

**Interpretation note for D8:** because that pending row has a live, amount-matching intent,
`create-payment-intent` will most likely **reuse** it rather than mint a new one — so this purchase may show
**one** intent total, not two. On D2 and D3 the stale rows were superseded and cancelled instead. Either is
correct; reuse must not be read as a duplicate-charge defect.

### Held aside from this matrix

Two branches, both owner-requested, both deliberately **outside** the pinned candidate:

1. Claude C's `5569385` — splits `not_found` / `offline` / `unavailable` on the transfer screens. Structure
   and tests accepted; one **blocking** copy change requested, because the `unavailable` body asserted "Your
   tickets and payment are not affected" from a read that had just failed and therefore could not know it.
2. The legacy buyer/seller transfer screens modernised onto the consumer V2 design system.

Neither is to be merged into `release/convergence-135` while build 16's matrix is open. Both are reviewed and
sequenced after QA closes.

## 21. D8 passed; the D9 attempt became a completed payment (2026-09-11)

### D8 — `Device D1`, server-side verified

The pending intent was **reused**, exactly as the baseline predicted: `pi_3UEC0D…`, created 2026-09-10 17:43,
paid 2026-09-11 01:05:12. So **one** intent for this purchase, not two.

| Check | Result |
|---|---|
| Payment rows | 2: one `failed` (2026-09-08), one **`succeeded`** |
| Succeeded payments | **exactly one**, $110.00 |
| Transfer | `pending`, **no payout id** |
| Webhook retries | **0** |

Reuse rather than supersede is correct behaviour and must not be logged as a duplicate charge.

> **Correction (2026-09-11):** the note that originally stood here — "handset observation still outstanding" —
> was wrong. The owner had already closed D8; see §22.

### D9 attempt on `Device D6` — a completed payment, NOT a D9 pass

The payment finished before the network was disconnected, so the interruption was never exercised. Recorded
as **another completed payment**; **D9 remains un-run**.

| Check | Result |
|---|---|
| Listing | **sold** 2026-09-11 01:19:01, `reserved_by` and `reserved_until` both NULL — hold released |
| Payment rows | 3: two `failed` (the D6/D6b attempts), one **`succeeded`** |
| **Succeeded payments** | **exactly one**, $110.00 |
| Stripe intents | 3: one `succeeded` with a charge; the two D6/D6b intents `requires_payment_method` with **no charge** |
| **Captured charges** | **exactly one** — captured, `refunded=false`, `amount_refunded=0`, `disputed=false`, `livemode=false` |
| Transfer | `pending`, **no payout id**, nothing released, send window to 2026-09-12 01:19:01 |
| Webhook retries | **0** |

`Device D6`'s payment is settled and must not be retried or modified.

### Inventory is now the binding constraint

**`Phone P1` is the only active listing left in the entire sandbox** — not just among the staged set. Every
other staged listing is sold, and there is no other active buy-now listing anywhere on the project.

That leaves **one shot** at D9. If the interruption is mistimed again, there is nothing left to attempt it
with. Recommendation, for owner approval: stage **two** further listings (`Device D7`, `Device D8`) before the
next attempt, so D9 has retries. D10/D11 are not at risk — eight unsettled orders exist (every sold listing's
transfer is `pending` with no payout).

### A more reproducible interruption procedure

The `4242` flow is unhittable by hand: the gap between the sheet closing and settlement completing is
milliseconds. The fix is to use a card that *creates* a human-scale pause.

**D9 (primary) — 3-D Secure handback.** Card `4000 0025 0000 3155`.

1. Buy Now → Pay. The 3-D Secure browser opens and **waits indefinitely** — an unmissable cue.
2. While it waits, swipe Control Centre down once to confirm the Airplane Mode toggle is reachable, then
   dismiss it. (Control Centre, not Settings — one tap instead of three.)
3. Tap **Complete authentication**. The authorization commits on Stripe's side at this point.
4. As the browser **begins dismissing**, swipe down and tap **Airplane Mode**.
5. Wait 15 s, then turn it off.

The window is now roughly a second of handback animation rather than milliseconds, and the charge is already
authorized when the network drops — which is precisely the state D9 exists to test.

**Expected:** no "contact support"; a calm "payment received / your payment is safe — don't pay again"; the
order appears shortly, settled by `stripe-webhook` (which **is** deployed in the sandbox, so this is genuinely
testable there).

**D9b (deterministic companion) — no network at confirm time.** Airplane Mode **before** tapping Pay on the
sheet. The confirm then fails with **no charge at all**. 100% reproducible, needs no timing, and it tests a
real and different path: the app must show a calm, retryable error rather than an alarming one, and must leave
the listing buyable. Worth running regardless of how D9 goes, and it consumes no listing.


## 22. Record reconciliation, listing readiness, and the D9 procedure design (2026-09-11)

### D8 — CLOSED (corrected record)

Handset, after force-quit and relaunch on `Device D1`: listing **sold**, **Buy Now gone**, Orders showed
**Purchased / Add transfer info**. §21 wrongly listed the handset observation as outstanding; D8 is closed.

Settlement-source evidence, which the earlier record lacked:

| Event | Time (UTC) |
|---|---|
| Stripe `payment_intent.succeeded` `evt_3UEC0D…15XAw03P` created | 01:05:10 |
| sandbox `stripe_webhook_events` received | 01:05:11.517 |
| `payments.paid_at` (Device D1) | **01:05:11.648** |
| webhook row marked processed | 01:05:11.850 |

`paid_at` falls inside the webhook's own processing window (1 attempt, no error), so the settlement was
**written by `stripe-webhook`**. **Tightened 2026-09-11:** that timing does *not* show whether the client was
alive at that instant, so the force-quit timing remains **owner-reported** rather than proven by this record.

### Phone P1 — reactivated (owner-authorized)

Found `status=active` but **`auction_status=ended`, `ended_at` 2026-09-10 03:46** — the earlier `ends_at`
extension (§17) had not reset the auction state, so Build 16 would still have treated it as an ended auction:
Explore filters on `auction_status='active'`, and the listing detail derives "Auction ended" from it. The §21
claim that Phone P1 was ready was therefore incomplete.

Preconditions asserted inside the transaction before any write — all held: `status=active`,
`auction_status=ended`, `ends_at` in the future (13d 21h), no succeeded/refunded payment, no transfer, no
winner, not sold, no reservation. Stripe independently confirmed **one** intent for the listing,
`requires_payment_method`, **no charge**.

Change: `auction_status 'ended' → 'active'`, `ended_at → NULL`, under `set local app.bypass_listing_guard =
'on'` (transaction-local; confirmed unset afterwards). Nothing else touched.

| Global check | Before | After |
|---|---|---|
| sold listings | 33 | 33 |
| succeeded payments | 21 | 21 |
| transfers | 33 | 33 |
| notifications referencing Phone P1 | 0 | 0 |

### Device D7 and Device D8 — staged (owner-authorized, sandbox only)

| Listing | id | State |
|---|---|---|
| Device D7 | `b1c3c478-b32e-4167-8f8d-2b9a4a4fd212` | active, auction active, $100, 14 days, 0 payments |
| Device D8 | `58cc00e3-e219-4095-9b57-cbdaa83df421` | active, auction active, $100, 14 days, 0 payments |

Listings 47 → 49. No settled listing or payment was modified.

### D9 — procedure design (A's side; the single handset sequence comes from Claude C)

Two separate cases, because they exercise different stages. Neither is a pass unless the interruption
demonstrably happened at the intended stage and Stripe is checked afterwards. **A missed timing window is
recorded as untested, not passed.**

**D9-A · Offline before confirm.** Load checkout **and** the PaymentSheet while online; **then** disconnect;
**then** tap Pay. Starting offline before Buy Now risks never reaching the confirmation path at all, which would
test nothing useful.

**D9-B · Interruption during 3-D Secure authentication/return** — two distinct stages, not one:

| Variant | When the network drops | What it exercises |
|---|---|---|
| **Offline before Complete** (C's test) | while the challenge page is open, before tapping **Complete authentication** | the challenge result may never reach Stripe; expect no authorization |
| **Offline after Complete** (A's test) | immediately after tapping **Complete authentication**, as the browser hands back | the challenge result may or may not have reached Stripe |

**Correction to §21:** it said the authorization "commits on Stripe's side" when Complete is tapped. That
overclaimed. Tapping Complete *submits* the challenge; whether Stripe received it, authorized, and captured
depends on requests that may not have left the device when the network dropped. Outcome is established only
from Stripe afterwards, never from the tap.

**Network control.** Airplane Mode on iOS can leave **Wi-Fi enabled** if Wi-Fi was re-enabled during a
previous Airplane Mode session. The sequence must include confirming the **Wi-Fi icon is off**, not just the
airplane icon on.

**Wording.** Nothing is promised in advance. For reference only, the Build 16 (`df9e0d3`) strings that *can*
appear are, verbatim:

* sheet, network-classified error: `Payment connection timed out. Try again.`
* sheet, other error: `We couldn't complete payment. Please try again.`
* settlement `pending`: title `Payment received`, body `You're all set. We're finalizing your order — it will
  appear in your purchases within a few minutes. Your payment is safe; please don't pay again.`
* settlement `failed` (raises an alert): title `Payment received`, body `Your payment went through, but we
  couldn't complete this order. Please don't pay again — contact support and we'll sort it out right away.`

Which one appears depends on the exact error text reaching `classifySettlement`. **Corrected 2026-09-11:** its
pending patterns are three business refusals (`no verified payment found`, `must be confirmed before`, `payment
has not succeeded`) plus **five** network phrasings — `network request failed`, `failed to fetch`, `fetch failed`,
`timed out`, `timeout`. An earlier version of this line listed only two network phrasings; that came from a
truncated read and was caught by Claude C. With confirm unreachable, anything outside those falls through to
`failed`. So **the `failed` alert appearing when Stripe shows the charge succeeded is the specific defect D9-B
is positioned to catch** — to be recorded as observed, not predicted.

**Discipline.** One attempt, then stop. The next attempt waits until that attempt's server-side result —
payment rows, Stripe intents and charges, listing, transfer — has been verified.

Listing allocation: **Phone P1** first; **Device D7** and **Device D8** as backups. D9-A consumes no listing if
the confirm fails as intended.

## 23. D9 procedure — AGREED between A and C (2026-09-11)

Supersedes the allocation and D9-B wording in §22. **Claude C delivers the single handset sequence to the
owner; this section is the written record of what was agreed.**

### Readiness — two independent reads, identical

| Listing | id | Read by C (02:03Z) and A (02:06Z) |
|---|---|---|
| Phone P1 | `c343406e-be85-49c1-9951-ac08bb1daab2` | active / active, $100, buy-now, ends 2026-09-24 23:35Z, no hold, 0 transfers; 1 row `3a546cf3` pending → `pi_3UDGNF…` `requires_payment_method`, no charge; the only intent at Stripe |
| Device D7 | `b1c3c478-b32e-4167-8f8d-2b9a4a4fd212` | active / active, $100, buy-now, ends 2026-09-25 02:01Z, no hold, 0 rows, 0 transfers, 0 intents |
| Device D8 | `58cc00e3-e219-4095-9b57-cbdaa83df421` | same as D7 |

C also confirmed settled listings unchanged: Device D1–D6 and Phone P2/P3 each sold, exactly one succeeded
payment, one transfer, no hold; no listing with more than one succeeded payment; no charge since 01:18:59Z.

### Three stages, one listing each

| Stage | Listing | Definition |
|---|---|---|
| **D9a** offline before confirm | Phone P1 | online through Buy Now, checkout, PaymentSheet and `4242` card entry; **then** Airplane Mode with Wi-Fi confirmed off; **then** tap Pay |
| **D9b** offline before Complete (C) | Device D7 | card `4000 0025 0000 3155`; challenge page on screen; Airplane Mode, Wi-Fi off; **then** tap Complete authentication |
| **D9c** offline after Complete (A) | Device D8 | same card; tap Complete **while online**; **immediately** Airplane Mode, Wi-Fi off |

**All stages:** offline 30 s → restore → confirm Wi-Fi has **reconnected** → close any open sheet with its
close control (**never Pay**) → Home → Orders → report exact on-screen text. One attempt, then stop until that
attempt is verified server-side (C owns verification; A cross-checks on request). A listing that ends
uncharged becomes the spare for a missed window. Whichever listing ends charged joins the settled,
never-retried set.

### A's amendments, accepted into the sequence

1. **Leaving the sheet.** The SDK (stripe-react-native 0.50.3, iOS SDK ~24.19.0) can keep the sheet open with
   its own error text after a confirm failure, so the allowed exit must be explicit: close it, never Pay.
   Closing returns `Canceled` → `releaseAbandonedHold`, which can show *"Your hold was released. Please go back
   and reserve again."* — legitimate whenever Stripe shows no charge.
2. **Wait for reconnection** before opening Orders, so its own offline state doesn't confound the result.
3. **D9a's expected server evidence is "unchanged".** An offline confirm never reaches Stripe, and on P1
   `create-payment-intent` will most likely **reuse** `pi_3UDGNF…` when Buy Now runs online. Expect that same
   single intent, still `requires_payment_method`, no charge. The handset observation carries D9a.
4. **The settled do-not-touch list grows** with whichever listing is charged.

### D9c — definition and interpretation rule (A)

At the moment the network goes off, the owner records which was true:
**(i)** the challenge browser was still on screen · **(ii)** the browser had dismissed but the app showed no
result yet · **(iii)** the app had already shown a result.

| Stripe afterwards | Timing note | Record as |
|---|---|---|
| no authorization, no charge | any | **D9c UNTESTED** — the result never reached Stripe, so the interruption landed at D9b's stage; D8 becomes spare |
| succeeded | (iii) | **D9c UNTESTED** — window missed; just another completed payment |
| succeeded | (i) or (ii) | **valid D9c evidence** — then judge the screen |
| `requires_action` / `requires_payment_method` / `canceled` | any | recorded exactly; no pass inferred |

Judging the screen when the evidence is valid:
* calm pending state, or the order appearing after reconnect → consistent with correct handling
* the `failed` **"contact support"** alert while Stripe shows the charge succeeded → **the defect D9c catches**
* **"Your hold was released…"** while Stripe shows the charge succeeded → also a defect
* SDK-owned sheet text → recorded verbatim, judged after verification

The window is short, so an honest **UNTESTED** is an expected outcome. No copy is promised in advance.


### Refinements from Claude C, verified against `df9e0d3` (2026-09-11)

* **Five network patterns, not two** — corrected in §22 above.
* **When `classifySettlement` runs.** It is reached from `finalizePurchase`, which runs after the PaymentSheet
  returns without error — **and also** on the `Canceled` path when `releaseAbandonedHold` finds Stripe already
  has the money: *"Stripe has the money: fall through to the normal settlement path rather than discard a real
  payment."* So closing the sheet (the agreed exit) does not bypass the classifier when the charge succeeded;
  the `failed` "contact support" alert stays reachable that way too. Most reachable in Stage 3.
* **Wi-Fi pre-flight** added once before Stage 1: Airplane Mode on → Wi-Fi tile off → Airplane Mode off, so iOS
  keeps Wi-Fi off in later Airplane Mode cuts. The Wi-Fi-off confirmation is still required at every cut.
* **Why one listing per stage** (C): a Stage 1 that fails as intended still leaves the buyer's **10-minute hold**
  and a live intent on Phone P1; running Stage 2 there would resume that intent and blur which attempt Stripe's
  record belongs to. A spare is reused only after its hold has cleared and a server read confirms it.
* **Verification flow:** after each attempt the owner stops; C verifies server-side (payment rows, Stripe
  intents, events and charges, listing and hold, transfer, webhook rows) and sends the result to A for
  cross-check before telling the owner to continue.

### Correction — reservation clearing does work (2026-09-11)

A claim sent to Claude C during D9 planning — that nothing clears an expired buy-now hold, so a listing left
`status='reserved'` stays hidden from browse indefinitely and spare reuse would need an authorised cleanup run —
was **wrong**, and has been retracted with C.

> **Corrected 2026-09-11:** an earlier version of this line said the claim "was never put to the owner". That was
> false. Claude C had independently "verified" it — by the same command-text search — and relayed it to the owner
> as verified, including scoring criterion (b) and the idea that spare reuse needs owner authorisation. C has
> withdrawn it in the incident record and is correcting it with the owner directly.

**How it went wrong:** the check searched `cron.job` commands for the text "reservation", found none, and stopped.
That missed an **indirect** call.

**Verified facts, both environments:**

| Fact | Sandbox | Production |
|---|---|---|
| `auto_finalize_expired_auctions` ends with an **unconditional** `perform public.cleanup_expired_reservations();` | yes | yes |
| `auto-finalize-auctions` cron schedule | `*/2`, active | `*/2`, active |
| runs in the last hour | **30, all succeeded** | **30, all succeeded** |
| `cleanup_expired_reservations` guard | skips listings holding a **succeeded** payment (N1, from `20260906110000`) — md5 `0271dca2…` | pre-Package-2 body, **no** guard — md5 `ecc0afc0…` |

The guard difference is **not drift**: `20260906110000` is one of the five migrations still pending in
production, so production runs the older body by design until the release.

**Consequences for D9:**

* An expired hold is cleared within **one 2-minute tick** after `reserved_until`. C's original statement — "the
  10-minute TTL clears it" — was correct.
* Phone P1's stale row `3a546cf3` is **pending**, not succeeded, so the N1 guard does not block clearing P1's
  Stage 1 hold.
* **Stage 1 hold criterion:** gone because `releaseAbandonedHold` released it when the sheet was closed after
  reconnect, **or** because the cron cleared it within about 2 minutes of `reserved_until`. The anomaly worth
  reporting is a `status='reserved'` row whose `reserved_until` is **more than ~4 minutes (two ticks) in the
  past**, on a listing with no succeeded payment.
* **Spare reuse needs no authorised cleanup.** An uncharged spare returns to `active` and reappears in Explore on
  its own within one tick after its TTL.

### Per-buyer hold sweep, evidence ordering, and the crossed verification (2026-09-11)

**Claude C's finding, verified against the live sandbox body.** `reserve_buy_now` is defined by
`20260906100000_checkout_reservation_authority.sql` (an earlier note here citing `018` was wrong — a
case-sensitive search missed that file's uppercase `FUNCTION`). It has **two** clearing paths, both skipping
listings that hold a succeeded payment:

1. **Target sweep** (live lines 32–35): the listing being reserved is reclaimed if its own hold has lapsed.
2. **Per-buyer sweep** (live lines 73–76): **all** of the caller's other `status='reserved'` holds are released,
   **lapsed or not** — there is no `reserved_until` condition:

   ```sql
   UPDATE public.listings SET status='active', reserved_by=null, reserved_until=null
    WHERE reserved_by = v_caller_id AND status='reserved' AND id <> p_listing_id
      AND NOT EXISTS (SELECT 1 FROM public.payments p
                       WHERE p.listing_id = public.listings.id AND p.status = 'succeeded');
   ```

**Evidence-ordering rule for D9.** If a stage's Buy Now happens inside the previous stage's 10-minute TTL, the
per-buyer sweep erases the previous listing's still-live hold, destroying the evidence of whether
`releaseAbandonedHold` released it. **Each stage's listing row is read before the owner taps the next Buy Now** —
by C for verification and by A for cross-check, before the owner is released.

**The crossed verification.** C independently "verified" the incorrect no-cron claim — but by the same method
(searching `cron.job` command text), so it was not independent confirmation; both checks missed the indirect call
in `auto_finalize_expired_auctions`. C has been sent the evidence and asked to withdraw scoring rule (b) and the
manual-cleanup assumption from the incident record. The correct rules are those in the correction above:
lapsed holds clear within one 2-minute tick in both environments, spare reuse needs no manual cleanup, and a
reserved row whose `reserved_until` is more than ~4 minutes in the past (no succeeded payment) is the anomaly.

**Lesson recorded:** three misses in this thread shared one cause — text search standing in for reading the live
definition (command text instead of function bodies, twice; a case-sensitive grep once). Verification of
database behaviour reads `pg_get_functiondef` from the target catalog.


### Owner-facing correction status (2026-09-11)

C independently re-verified the corrected facts on the sandbox at 02:14Z: `auto-finalize-auctions` runs `*/2`,
active, calling the SQL function directly (not over HTTP); 30 runs in the last 60 minutes, all succeeded, latest
ending 02:14:00Z; `auto_finalize_expired_auctions()` performs `cleanup_expired_reservations()`; zero reserved rows at
that moment. C's incident record now withdraws criterion (b) and the authorisation requirement, with the reason, and
adopts the corrected criterion. **Two statements were given to the owner and are withdrawn:**

1. that an expired-but-uncleared hold counts as "cleared" for scoring, and
2. that reusing a spare listing needs the owner to authorise a cleanup run.

**What is true:** a lapsed hold clears within one 2-minute tick in both environments; an uncharged spare restores
itself with no authorisation; the anomaly is a reserved row more than ~4 minutes past its window with no succeeded
payment. Unchanged and still true: browse hides reserved rows, and `reserve_buy_now`'s per-buyer sweep clears prior
unpaid holds on the next Buy Now, so each stage's listing is read before the next Buy Now.

C's production catalog reads are blocked in its session, so the production md5 comparison is recorded as A-reported,
not independently verified.

### Hold-release taxonomy and evidence timing (2026-09-11)

**Timing rule (Claude C; one word corrected by A).** After `reserved_until` plus one cron tick, an explicit release
and a cron clear leave **identical** rows. Only a read taken **before** `reserved_until` distinguishes them. Inside the
window:
- A row still `reserved` means no explicit release **landed**. One may have been attempted and failed offline (see
  *Offline behaviour*).
- A row already `active` means an **explicit** release, never the cron. The live sandbox
  `cleanup_expired_reservations` (md5 `0271dca2…`) requires `reserved_until <= now()`, plus the N1 succeeded-payment
  guard.

Both C (verification) and A (cross-check) therefore read each stage's listing as soon as the owner reports. Each logs
the read time against `reserved_until`, before the next Buy Now.

**Every explicit release path, verified against `df9e0d3`.**
- **Deployed webhook.** The sandbox `stripe-webhook` is deployed at version 3. Its `index.ts`, `_shared/sentry.ts` and
  `_shared/stripe.ts` are byte-identical to `df9e0d3` (`index.ts`: 919 lines, md5 `d379c156…`).
- **Live `release_reservation`** (md5 `1f447dd5…`). It returns early on `sold` and releases only a `reserved` hold
  owned by the caller. For the service role, the caller is `p_user_id`.

| # | Caller | Trigger and gate |
|---|---|---|
| 1 | `src/screens/checkout/CheckoutNative.tsx:364–386` (`releaseAbandonedHold`, RPC at :372) | PaymentSheet `Canceled` on Buy Now. It calls `confirmPaymentSuccess` first. A verified payment settles instead of releasing. An **unreachable** backend returns **without releasing**. Only a reachable backend with no verified payment releases the hold. Source error text: "Your hold was released. Please go back and reserve again." What the handset renders is not asserted. |
| 2 | `src/screens/ListingDetailScreen.tsx:186–207` (`beforeRemove` listener, RPC at :201) | The listing screen being **removed** (popped back toward Home). Pushing Checkout on top does not fire it. `shouldReleaseReservation` (`src/lib/listing/reservationExit.ts:33–40`) checks the **last-known client** listing state: status `reserved`, `reserved_by` = the user, no sale latched. **No UI and no prompt.** "ASK" in the file header means asking the server. The call is fire-and-forget, at most once per screen instance. |
| 3 | `supabase/functions/stripe-webhook/index.ts:361–412` (RPC at :398) | `payment_intent.payment_failed` **or** `payment_intent.canceled`, with `metadata.mode === 'buy_now'`. It runs only after the payment row was claimed `failed` (status not succeeded or refunded). An unclaimable row returns before the release. |
| 4 | `reserve_buy_now` per-buyer sweep (live lines 73–76) | The same buyer reserving any other listing. **Excluded by procedure** (read before the next Buy Now), not by mechanism. |

**Offline behaviour.** Neither client path can release while the handset is offline.
- Path 1 declines to release when the backend is unreachable.
- Path 2's single fire-and-forget RPC fails with only a `console.warn`. Its latch prevents a retry on that screen
  instance.

After an offline cancel or exit, the hold staying `reserved` until `reserved_until` plus a cron tick is the designed
backstop. It is not a defect and must **not** be scored as a failed release.

**Attribution.** The row alone establishes only "explicit release"; which path released it needs corroboration.
- A `payment_failed` or `canceled` webhook event near the read time points to path 3.
- The owner's report of their taps points to path 1 (cancelling the sheet) or path 2 (leaving the listing back to
  Home).

**Correction (same day).** The first version of this section (commit `05b5451`) and A's first message to C said path 2
"may prompt the owner first". Both suggested a report field for a declined release prompt. That was written before
`reservationExit.ts` was read, and it is wrong: path 2 has no UI. A retracted it to C and asked C to retract anything
already relayed to the owner.

### D9 Stage 1 readiness, attribution evidence, and two latent release gaps (2026-09-11)

**Readiness snapshot (sandbox, 02:27Z; read-only).**
- **Listings.** Phone P1 `c343406e`, Device D7 `b1c3c478` and Device D8 `58cc00e3` are all `active`/`active`, with no
  reservation and a future `ends_at`. D7 and D8 have no payments.
- **Phone P1's leftover row.** Phone P1 still carries buyer `1fcd0c69`'s pending row `3a546cf3` (`pi_3UDGNF…`, total
  11000 cents), created 2026-09-08.
- **Account.** The newest sandbox session belongs to `919d511e`, the account behind every Build 16 handset payment since
  2026-09-10.

**Expected Stage 1 side effect.** If Stage 1 runs as `919d511e`, loading checkout on Phone P1 should run
`create-payment-intent`'s other-buyers retire (`index.ts:588`, at `df9e0d3`), which cancels `pi_3UDGNF…`. This emits at
most one `payment_intent.canceled` event and moves `3a546cf3` from `pending` to `failed`. The webhook then calls
`release_reservation(P1, 1fcd0c69)`, which is a no-op because `919d511e` owns the hold.

This is the designed retirement, not a release of the owner's hold. The sandbox already shows the pattern on `9c6eecd4`:
a `canceled` event at 20:58:36.63Z, 80 ms before `919d511e`'s payment row, and that payment succeeded.

If the handset account is instead `1fcd0c69`, Stage 1 stops for A. The reuse path is expected, since 11000 cents matches
Build 16's $110 total for a $100 listing, but the intent has not been checked at Stripe.

**Attribution evidence sources.**
- `public.stripe_webhook_events` holds no PaymentIntent or listing column.
- `payments.failed_at` was null on every failed row in the last 3 days; neither the webhook nor the retire code sets it.
- `create-payment-intent` emits `payment_intent.canceled` itself, from three sites:
  - the other-buyers retire (`:588`);
  - the refused-buyer retire (`:421`);
  - the amount-mismatch cancel (`:633`).
- `stripe-webhook` logs "release_reservation succeeded" with the `listing_id` even when the RPC is a no-op.

Path 3 therefore needs function logs per stage: the retire `logStage` from `create-payment-intent` (payment row and PI id)
and the release line from `stripe-webhook`. An event row or that log line alone does not prove a release.

**Route facts (`df9e0d3`; appearance on the handset not asserted).**
- `listing/[id]` and `checkout/[id]` are root-Stack siblings of `(tabs)` (`app/_layout.tsx:123–129`), so the tab bar is
  not reachable from either screen without leaving it first.
- Checkout "Go back" (`CheckoutNative.tsx:526`) returns to the listing, and the hold is kept.
- Listing back (`ListingDetailScreen.tsx:1120`) goes to Home, where path 2 may fire.
- The result view's button (`CheckoutNative.tsx:702–708`) calls `router.replace`. Source does not establish whether it
  removes the listing screen underneath.

**Latent gap L1 — same-buyer cancel releases the live hold** (not observed; owner decision; Build 16 unchanged; *corrected in the Stage 1 section below: deterministic, not a race*).
- **Where.** `create-payment-intent`'s amount-mismatch branch cancels the buyer's own pending PI at Stripe (`:633`)
  *before* retiring the row (`:646–650`). By that point the buyer holds a live hold (`:412` refuses otherwise).
- **Failure.** If the `canceled` webhook claims the still-`pending` row first, `release_reservation(listing, same
  buyer)` releases the buyer's **live** hold.
- **Trigger.** A seller re-prices between the same buyer's attempts.
- **Stage 1 exposure.** Not reachable in Stage 1: Phone P1's amount matches, and `919d511e` does not own the row.

**Latent gap L2 — `release_reservation` has no succeeded-payment guard** (not observed; owner decision; Build 16
unchanged).
- **The gap.** `cleanup_expired_reservations` and the per-buyer sweep both skip a listing that holds a `succeeded`
  payment (N1). Live `release_reservation` (md5 `1f447dd5…`) checks only `sold` and hold ownership, and path 2 checks
  only the cached listing state.
- **Failure.** Leaving the listing screen after a payment succeeded, but before the listing reads `sold`, could release
  a paid order's hold.
- **Guard proposed to C.** After any attempt that may have been paid, the owner stays off the listing exit until a
  verifier confirms the listing is `sold` or the payment did not succeed.

### D9 Stage 1 (D9a, Phone P1): server verification, A cross-check, attribution (2026-09-11)

**Owner report so far (via C).**
- Airplane Mode was turned on before tapping Pay.
- The sheet showed the SDK's offline text and stayed open. No retry. Connectivity has been restored.
- Still outstanding: Wi-Fi-off confirmation, cut time, whether and when the sheet was closed, text after closing, the
  control used to reach Home, Orders, and Buy Now.

**Financial result.** C verified the database at 02:52:52Z and Stripe at 02:52:59Z. A cross-checked the database and
the Supabase logs at 02:55:07Z. A has no Stripe access, so the Stripe facts rest on C's read.
- **Stripe (C).** `pi_3UDGNF…` (`1fcd0c69`) was canceled at 02:50:46Z with no charge. The new `pi_3UEKY6…` (`919d511e`)
  is `requires_payment_method`, with no charge and no `requires_action`, `payment_failed` or `succeeded`. The confirm
  never reached Stripe.
- **Database (both).**
  - Phone P1 rows: `3a546cf3` is `failed`; `9f4ab181` (`919d511e`, `pi_3UEKY6…`, 11000) is `pending`; Phone P1 has 0
    transfers.
  - Listing: `active`/`active`, no hold, not sold.
  - Globals: payments 48, transfers 33, succeeded 21, multi-succeeded listings 0, reserved rows 0.
  - Webhooks: one event since 02:40Z (`canceled`, processed, 1 attempt) and 0 webhook retries.

**Timeline** (Supabase logs; handset = `SnatchIt/16`, JWT subject `919d511e`).

| UTC | Source | Event |
|---|---|---|
| 02:50:41.160 | handset | `reserve_buy_now` 204 — hold taken; live `v_minutes := 10`, so the window runs to ≈03:00:41 |
| 02:50:42.9–46.7 | `create-payment-intent` | auth `919d511e`; listing `reserved`; payments-lookup 0; retire's row update (PATCH 204, 46.128); `other-buyer-pending-retired` `3a546cf3` / `pi_3UDGNF…` / `1fcd0c69` (46.387); `pi-created` `pi_3UEKY6…` (46.589); `db-insert-ok` (46.675) |
| 02:50:46.564–.855 | `stripe-webhook` | claim; PATCH payments 200 (46.632); `release_reservation` as service role for `1fcd0c69` (46.690), logged "succeeded" |
| 02:50:42.419 → 02:52:24.282 | handset | no requests (the offline period lies within); realtime reconnect at 02:52:24.448 |
| 02:52:27.107 | handset | `release_reservation` 204, alongside `user_blocks` and `get_my_profile` (Home loads) |
| 02:52:27.3676 | `listings.updated_at` | the release's UPDATE |

**Attribution: path 2 (listing exit).**
- **The landed write** is the handset's authenticated call at 02:52:27.107. `updated_at` proves an UPDATE ran, and
  `release_reservation` updates only a reserved hold owned by the caller, so the hold still existed at that moment.
- **Path 3 is excluded.** Its only call ran for `1fcd0c69`, and the hold survived it.
- **Path 1 is excluded.** `releaseAbandonedHold` releases only after a reachable `confirm-payment`. None has reached the
  server since 2026-09-10 23:42:53Z, and `confirm-payment` invocations are visible in `function_edge_logs` (8 earlier
  calls by `919d511e`).
- **The per-buyer sweep is excluded:** there was no `reserve_buy_now` after 02:50:41.160.
- **The cron is excluded:** the window was open, and the write was a handset RPC.

**Verdict.** Server-side verification is complete, and A concurs: no charge, no succeeded payment, the confirm did not
reach Stripe, and the listing is active and buyable. **Stage 1 is not yet recorded as PASS.** §23 defines D9a with
"Wi-Fi confirmed off", and the post-reconnect report is part of the stage.

Blind checks for the owner's report, not to be prompted:
- the route back to Home went through the listing;
- the "hold was released" line was not shown;
- the handset reconnected by 02:52:24Z.

**Corrections.**
- **§23 amendment 3 is superseded.** It said checkout would "most likely reuse `pi_3UDGNF…`". As `919d511e`, checkout
  instead retired the other buyer's intent and minted a new one, as predeclared in the Stage 1 readiness section.
- **L1 is deterministic, not a race.** The webhook's claim predicate (`stripe-webhook/index.ts:373`,
  `status NOT IN (succeeded, refunded)`) also matches `failed` rows, contrary to its comment at `:383–386`.
  - *Evidence.* Stage 1's logs show it: the retire marked `3a546cf3` `failed` at 02:50:46.128, yet the webhook still
    claimed that row (02:50:46.632) and called `release_reservation`.
  - *Consequence.* Whenever `create-payment-intent` cancels the hold owner's **own** PaymentIntent, the `canceled` event
    releases that owner's live hold, whatever the ordering. In `df9e0d3` only the amount-mismatch branch does that.
  - *D9 impact.* None. Device D7 and Device D8 have no prior payment rows.

**Incidental Build 16 sandbox errors** (not D9 results; recorded for after the matrix). Response bodies are not in
the logs, so each cause below is consistent with the evidence rather than read from the error.
- **F1 — checkout summary query returns 400.**
  - *Cause.* `CheckoutNative.tsx:138` selects `cover_image_url`. No migration in the chain creates it, and the sandbox
    `listings` table does not have it. Observed at 02:50:42.217.
  - *Impact.* The same query supplies `reserved_until` and the order-summary fields, so checkout's summary and hold
    countdown in the sandbox are not representative.
  - *Production.* The source treats `cover_image_url` as a legacy column. Whether production has it is not checked: a
    production↔chain drift like D7 is suspected, not established.
- **F2 — bid history query returns 400.**
  - *Cause.* `useListingRealtime.ts:64` embeds `profiles(display_name, avatar_url)`. The sandbox `bids_bidder_id_fkey`
    targets `auth.users` (`000_baseline_schema.sql:144`), so the embed has no relationship to resolve, as in D7.
    Observed at 02:50:35.025.
  - *Status.* This is the recorded latent `bids_bidder_id_fkey` drift, now observed live on the listing screen.

### D9 Stage 1: owner report complete, and the verdict (2026-09-11)

**Owner report (via C).**
- The Wi-Fi symbol was gone before tapping Pay.
- Pay was tapped about 2 s after disconnecting.
- The sheet showed "The internet connection appears to be offline." (SDK/iOS text, not app copy) and stayed open.
- The owner closed the sheet **before** reconnecting. §23's order is reconnect first, then close, so this is a
  deviation.
- "No control returned me Home; I navigated Home manually."
- Orders shows no Phone P1 order. Phone P1 is active, with Buy Now available.
- No retry, no second attempt.

**Reconciliation with the server evidence.** Every blind check holds.
- **No "hold was released" line.** Closing the sheet offline made path 1 unreachable, so it returned without releasing
  and set no line. This matches the absence of any `confirm-payment` call since 2026-09-10 23:42:53Z.
- **The manual navigation removed the listing screen online.** The handset's `release_reservation` arrived at
  02:52:27.107, alongside the Home-screen loads, and its UPDATE landed at 02:52:27.3676. So the owner reconnected
  before leaving the listing screen.
- **Reconnection by 02:52:24Z.** Handset requests resume at 02:52:24.282.
- **Offline at Pay** is corroborated independently: no confirm reached Stripe (C's read), and the SDK showed its offline
  text. The cut came after `create-payment-intent`'s response was served at 02:50:46.688.

**Verdict: D9a PASS** (C verifies, A concurs).
- Offline before confirm produced no charge and no succeeded payment. No success was shown and there was no retry.
- The listing returned to buyable inside the window, released by path 2 at 02:52:27.107.

**Not exercised in Stage 1:** path 1 online (the confirm-first release after reconnecting), because the sheet was closed
while offline. This is recorded as **untested, not failed**. Phone P1 ended uncharged and is the spare for a missed
window.

**Carried into Stages 2 and 3.**
1. **Reconnect before closing the sheet.** Per `df9e0d3`, closing while offline skips path 1's confirm-first check.
   `releaseAbandonedHold` returns before `setPaymentReady(false)` and `runSettlement` just returns, so checkout keeps
   its ready state. After a possibly paid attempt (D9c), the Pay control may still be offered, and the never-Pay rule
   carries the safety.
2. **Name the back arrow and the swipe.** The owner's manual navigation Home is exactly the path-2 trigger, so the L2
   guard must name both, not only on-screen controls. After a possibly paid attempt, the owner stays on the screen
   until a verifier confirms the result.

### D9 Stage 2: baseline cross-check, and L1 reachability (2026-09-11)

**Baseline.** A read at 03:06:00Z; C read at 03:03:19Z. The two reads are identical, and no Buy Now had arrived.
- **Device D7 and Device D8:** `active`/`active`, no hold, 0 payments, 0 transfers. `updated_at` is 02:01:44.985,
  unchanged since staging.
- **Phone P1:** unchanged since 02:52:27.37.
- **Globals:** payments 48, transfers 33, succeeded 21, multi-succeeded listings 0, pending 3, reserved rows 0.
- **Webhook events:** none since 02:56Z.

**Stage 2 as issued by C** (D9b, Device D7):
1. Buy Now online; card `4000 0025 0000 3155`; Pay online; wait for the challenge.
2. Airplane Mode, with the Wi-Fi symbol confirmed gone. Note the time. Tap Complete once.
3. Stay offline 30 s. Reconnect and confirm.
4. Tap Done on the Stripe page if it is open, and X on the sheet if it is open.
5. **Guard:** stay on the checkout screen: no back, no Home, no second Pay or Complete. Report.

Orders and Buy Now are checked only after verification.

**A's verification notes for Stage 2.**
- **Path 1 online.** Closing online exercises path 1, untested in Stage 1: a reachable, unverified `confirm-payment`
  followed by a handset `release_reservation`.
- **Path 3 may fire too.** A `payment_failed` or `canceled` event for the D7 intent names `919d511e`, the hold owner,
  so the webhook's release is legitimate. The first UPDATE lands and the other is a no-op. Attribute by
  `listings.updated_at` against the handset and service-role release timestamps.
- **If the intent succeeded.** If Stripe shows the D7 intent `succeeded`, path 1's confirm returns verified and
  settlement runs. Record that exactly; no pass is inferred.
- **Missed window.** If Complete cannot be tapped offline, the window is missed: record untested, with no reload.
- **Swipe back.** A suggested to C that the next relay name the swipe-back gesture alongside "no back".

**L1 reachability, verified across every PaymentIntent cancel in `df9e0d3`.** A wrongful release of a live hold needs a
cancel of the **holder's own** `buy_now` intent while the hold is live.

`create-payment-intent`:

| Site | Reason | Outcome |
|---|---|---|
| `:624–654` | amount mismatch | **reachable: this is L1** |
| `:451` | `sold-to-another-buyer` (via `refuse()`) | another buyer's payment succeeded: sold in fact, intended money-wins outcome |
| `:457`, `:480` | `listing-sold` | `release_reservation` returns early on `sold` |
| `:463` | `not-reserved` | no hold |
| `:466`, `:497` | `reserved-by-another` | not the requester's hold; `:497` is auction mode, excluded by the webhook's release gate |
| `:469` | `reservation-expired` | releases an expired hold, the same outcome as cleanup |
| `:471`, `:527` | Buy Now disabled; client total mismatch | return without retiring |
| `:588` | other-buyers retire | the release names the other buyer, a no-op for the holder |
| `:829` | orphan cancel after a failed insert | no row to claim |

The other two functions that cancel PaymentIntents:
- **`enforce-transfer-expiry:235`** runs only after a settlement, so the listing is `sold`.
- **`primary-checkout:1450`** cancels unrecorded `native_primary` intents. These carry no `listing_id` and fail the
  webhook's `buy_now` gate.

### D9 Stage 2 (D9b, Device D7): server verification, A cross-check, attribution (2026-09-11)

**Owner report so far (via C).**
- The challenge appeared and stayed on screen.
- Airplane Mode was on, with Wi-Fi off, for about 30 s; then the owner reconnected.
- The flow returned to the PaymentSheet, which showed "Processing" and then its normal "Pay $110" state.
- No second Pay, no reload; the owner is still on checkout.
- **Not yet stated:** whether Complete was tapped while offline; whether the challenge closed by itself or via Done;
  the cut time.

**Financial result.** C verified Stripe at 03:13:53Z and the database at 03:13:45Z. A cross-checked the database and
the logs at 03:17:52Z. The Stripe facts rest on C's read.
- **Stripe (C).**
  - `pi_3UEKqq…` (`919d511e`) is `requires_payment_method`: no amount received, no charge.
  - `last_payment_error` is `payment_intent_authentication_failure`.
  - Events: created 03:10:08Z, `requires_action` 03:10:46Z, `payment_failed` 03:11:57Z.
  - No charges since 03:03Z.
- **Database (both).**
  - Device D7: `active`/`active`, no hold, `updated_at` 03:11:58.102968. Row `a79d6fe4` (`919d511e`) is `failed`.
    0 transfers.
  - Device D8 and Phone P1 are unchanged.
  - Globals: payments 49, transfers 33, succeeded 21, multi-succeeded 0, pending 3, reserved 0.
  - Webhooks: one event, `evt_3UEKqq…` `payment_failed` (received 03:11:57.960, processed, 1 attempt); 0 retries.

**Timeline** (Supabase logs).

| UTC | Source | Event |
|---|---|---|
| 03:10:03.961 | handset | `reserve_buy_now` 204 — hold taken; window to ≈03:20:04 |
| 03:10:04.838 | handset | F1 checkout `listings` 400 (F2 `bids` 400s also recur on the listing screen) |
| 03:10:05.7–08.9 | `create-payment-intent` | auth `919d511e`; listing `reserved`; payments-lookup 0; `pi-created` `pi_3UEKqq…` 11000; `db-insert-ok`. No retire and no cancel, so no L1 |
| 03:10:55.362 → 03:11:45.883 | handset | no REST requests (the ≈30 s offline period lies within). A realtime websocket upgrade at 03:11:36.005 carries no identity |
| 03:11:57.818–58.187 | `stripe-webhook` | claim; PATCH payments 200 (`a79d6fe4` pending→failed); `release_reservation` (service role) 03:11:58.076; release logged; complete; POST 200 |
| 03:11:58.102968 | `listings.updated_at` | the release's UPDATE |

There was no `confirm-payment` call, no handset `release_reservation`, and no second `create-payment-intent` through the
latest log lines.

**Attribution: path 3, credited.**
- The event resolves to the D7 intent, and its buyer `919d511e` is the hold owner.
- The release call landed 26 ms before the UPDATE.
- Path 1 did not run: the sheet was open and there was no `confirm-payment` call.
- Path 2 did not run: the owner stayed on checkout, and there was no handset release.
- The per-buyer sweep and the cron are excluded.

**Classification (§23 D9b): pending the owner's answer.**
- **Complete tapped while offline:** valid D9b evidence. The offline Complete never authorized. After reconnect, Stripe
  recorded an authentication failure. There was no charge. The app returned to a payable sheet without claiming
  success, and path 3 released the hold. A would record PASS, with the sheet text verbatim.
- **Complete not tapped offline:** the window was missed. D9b is UNTESTED, and Device D7 becomes a spare.

**X close, requested by C while online.** Prediction from `df9e0d3`:
1. `releaseAbandonedHold` calls `confirm-payment`. For an intent that is not succeeded, it returns
   `stripe_verified:false` and writes nothing beyond the rate-limit RPC (header `:15–17`; `:177`, `:209`, `:248`).
2. The handset then calls `release_reservation`. The listing is already `active`, so there is no UPDATE and
   `updated_at` must stay at 03:11:58.103.

If `updated_at` moves, or `confirm-payment` reports verified, stop and flag it.

**Observations.**
- **L3 candidate: same-sheet retry after `payment_failed` runs without a hold.** Not a D9 result; owner decision.
  - *Observed live.* After path 3's release, the owner's sheet offered "Pay $110" for `pi_3UEKqq…` while Device D7 had
    no hold.
  - *Why.* `stripe-webhook/index.ts:362–368` expects same-sheet retries after `payment_failed`, yet the webhook releases
    the hold on that event.
  - *Handling.* `settle_verified_payment`'s key lines include an `unfulfillable` outcome: another payment already holds
    the listing's one success, and the capture is refunded from the review queue. A conflict therefore appears to be
    handled by refund rather than a double sale. Only those lines were read.
  - *D9 coverage.* The no-second-Pay rule covers it.
- **The listing screen stays mounted under checkout.** It refetches bids, listings and profiles after each realtime
  websocket upgrade (03:10:53, 03:11:36, 03:12:02, 03:12:28, 03:13:16). Its cached listing has read `active` since
  03:12:04, so path 2's gate should not fire when the owner later leaves. The reconnect cadence is unclassified.

**Spares.**
- **Device D7:** only a `failed` row, so a rerun mints a fresh intent with no reuse and no cancel.
- **Phone P1:** carries `919d511e`'s pending `pi_3UEKY6…`, so a rerun reuses it only while the total matches.

### D9 Stage 2 classified UNTESTED; rerun sequencing (2026-09-11)

**Owner answers (via C).**
1. Complete was **not** tapped while offline.
2. After reconnecting, the owner tapped Done to close the Stripe page.
3. Airplane Mode went on as soon as the Stripe page loaded.

These fit the evidence: `requires_action` at 03:10:46Z (C's Stripe read), the last handset request at 03:10:55.362,
reconnection by 03:11:36–45, and the authentication failure at 03:11:57Z.

**Classification: D9b UNTESTED (missed window), not a failure.** Complete was never submitted while offline. Device D7
becomes the spare.

**Recorded separately, not scored as D9b.** An open challenge survived about 30 s offline. Done after reconnecting
produced the D6-style authentication failure:
- no charge;
- a payable sheet;
- no success claimed;
- a path 3 release of the owner's own hold.

**X close (online).** As of A's read at 03:21:47Z, it had not reached the server:
- no `confirm-payment` call, and no non-GET handset request since 03:13:00Z;
- Device D7 `updated_at` still 03:11:58.102968.

The prediction stands: a reachable, unverified confirm, then a handset release with no UPDATE. If X was tapped while
still offline, neither call happens, which is also designed behaviour.

**Rerun sequencing.** C recommends rerunning Stage 2 on Device D7 before Stage 3, and A agrees.
1. **Verify the X close first.** Device D7's `updated_at` must be read before the rerun's Buy Now, which will move it.
2. **Expected server path on the rerun:** `reserve_buy_now`, then `create-payment-intent` with `payments-lookup` count 1
   (`[failed]`), then `pi-created` for a new intent. The idempotency key is salted by the failed attempt. There is no
   retire and no cancel, so no L1. A logged cancel or `reuse-rejected-amount-mismatch` stops the stage.
3. **Timing emphasis for the owner:**
   - Wait until the challenge page shows its Complete button.
   - Then turn on Airplane Mode, with the Wi-Fi symbol confirmed gone.
   - Tap Complete once while offline, even if nothing visibly happens, and note what the page shows.
   - Wait 30 s, reconnect, tap Done or X if open, and stay on checkout.

### D9 Stage 2 rerun (D9b, Device D7): verification, and defect D9-UX-1 traced (2026-09-11)

**Owner report (to A directly).**
- The challenge was open. Airplane Mode was on, with Wi-Fi off.
- The owner tapped **Complete while offline**, and the challenge stayed on its stale screen.
- After reconnecting, the owner **reloaded** the page, then tapped back to the PaymentSheet. It showed "Processing",
  then "Pay $110".
- After closing the sheet, checkout displayed exactly: "Your reservation has expired. Please go back and reserve again."
- The Try Again button appeared to do nothing. No second Pay.

The owner asked A to treat the expired copy and the inactive Try Again control as a potential D9 defect until traced.

**Stripe.** A read it with the local Stripe CLI: read-only, account `acct_1T6Fb1GlD5aqtxIw` (sandbox, test mode), output
filtered to exclude client secrets.
- **Intent:** `pi_3UEL2L…` (Device D7, `919d511e`, `buy_now`, 11000) is `requires_payment_method`. Nothing received,
  no `latest_charge`, `last_payment_error` = `payment_intent_authentication_failure`.
- **Events:** created 03:22:01Z, `requires_action` 03:22:11Z, `payment_failed` 03:23:20Z.
- **Charges:** the newest charge on the account is from 01:18:59Z, so there was no charge in Stage 2 or its rerun.

**Database (03:30:58Z).**
- **Device D7:** `active`/`active`, no hold, `updated_at` 03:23:21.876063. Rows `a79d6fe4` (`pi_3UEKqq…`) and
  `9a3dd888` (`pi_3UEL2L…`) are both `failed`. 0 transfers.
- **Device D8 and Phone P1:** unchanged.
- **Globals:** payments 50, transfers 33, succeeded 21, multi-succeeded 0, pending 3, reserved 0.
- **Webhooks:** one event, `evt_3UEL2L…` `payment_failed` (received 03:23:21.717, processed, 1 attempt). 0 retries.
- **Cron:** `auto-finalize-auctions` ran every 2 min from 03:20 to 03:30; every run succeeded.

**Timeline** (handset = `SnatchIt/16`, `919d511e`).

| UTC | Event |
|---|---|
| 03:21:54.9 → 55.025 | First attempt's X close: `confirm-payment` "not succeeded" (`pi_3UEKqq…`), then handset `release_reservation`. A no-op: Device D7 had been active since 03:11:58 with no reserve before 03:21:57.58 (the `updated_at` proof was lost because the rerun began 2.5 s later) |
| 03:21:57.580 | `reserve_buy_now` — hold taken, would expire ≈03:31:58 |
| 03:21:58.450 | F1 summary query 400 (mount) |
| 03:21:58.458 / .623 | Setup pre-check #1 (settled-payment lookup; listing hold) — the hold is the buyer's |
| 03:21:59–22:01.6 | `create-payment-intent`: `payments-lookup` count 1 `[failed]`, `pi-created` `pi_3UEL2L…`; no retire or cancel, so no L1 |
| 03:21:58.6 → 03:22:56.9 | no handset REST requests; reconnected by 03:22:56.9 |
| 03:23:20Z | Stripe authentication failure, after the reload and return |
| 03:23:21.573–.957 | `stripe-webhook`: claim; PATCH 200; `release_reservation` 03:23:21.844 (UPDATE 03:23:21.876), **8½ min before expiry** |
| 03:23:23.9 → 24.062 | Rerun X close: `confirm-payment` "not succeeded", then handset `release_reservation`. A **proven no-op**: `updated_at` did not move |
| 03:23:25.798 / 26.202 | Setup pre-check #2: no hold, so `reservation_expired`; no intent created |
| 03:23:28.511 / 28.858 | Setup pre-check #3: the same refusal |

**Defect trace: D9-UX-1** (`df9e0d3`).
1. Closing the sheet runs `releaseAbandonedHold` (`CheckoutNative.tsx:364–386`). It sets `paymentReady=false` and the
   error "Your hold was released. Please go back and reserve again."
2. `payControl.ts:40` maps any `paymentError` to **"Try again"** with action `retry`. `CheckoutNative.tsx:517` wires
   retry to `setupPaymentRef.current()`.
3. Each Try Again re-runs `setupPayment`. `decideCheckoutSetup`'s `holdIsMine` fails because the listing is `active`,
   so it returns `reservation_expired` (`setupDecision.ts:87`). `CheckoutNative.tsx:228` then sets "Your reservation
   has expired…", replacing the hold-released line.
4. The control stays "Try again". Setup never re-reserves, so every tap repeats the refusal and appears to do nothing.

Pre-checks #2 and #3 are the owner's two Try Again taps. They are not remounts: the mount-time summary query
(`CheckoutNative.tsx:133–158`, always 400 in the sandbox) did not recur. They are not automatic re-runs either:
`useAuth` only ever sets `loading` to false (`useAuth.ts:69`, `:90`), so the setup effect cannot re-fire. Blind check for
the owner: two taps about 3 s apart, with the hold-released line possibly shown briefly before the first.

**Assessment.**
- **D9b, money and state: PASS on the interruption question** (A's recommendation; the owner decides).
  - The offline Complete never authorized, and there was no charge, no false success, and no second intent.
  - Path 3 released the hold correctly, and setup's refusals were correct.
  - The reload deviation did not change the Stripe outcome.
- **Path 1 online ran twice, as designed:** confirm first, then release. Both releases were no-ops because path 3 had
  already released the hold. A path-1 release of a **live** hold while online remains unexercised.
- **D9-UX-1: open. UX defect, not payment integrity.** Checkout conflates "hold released" with "reservation expired":
  `setupDecision` has one `reservation_expired` kind for any hold that is not the buyer's live hold. Once the hold is
  gone, it offers a live "Try again" that cannot recover without re-reserving. The copy says "go back"; the button says
  "try again".
  - *Scope.* Not interruption-specific: reachable after any authentication failure or cancel whose release lands before
    the retry.
  - *Fix direction* (after the matrix, not in Build 16): distinguish released from expired in the copy, and replace the
    retry with a go-back or re-reserve action once the hold is gone.
  - *Owner decisions.* Severity, and whether it gates release.
- **Stage 3 (Device D8):** unaffected; Device D8 is unchanged. If a similar end state appears, the owner goes back after
  verification rather than tapping Try Again.

**C's independent cross-check of the rerun** (C read Stripe at 03:30:14Z and the database at 03:30:08Z) matches A on
every fact and on the D9-UX-1 root cause. Four points from the exchange:
- **Confirmed by A:** the `create-payment-intent` stage lines are `payments-lookup` count 1 `["failed"]`, then
  `pi-created` `pi_3UEL2L…`, then `db-insert-ok`. There are no retire, amount-mismatch or canceled-intent lines, and no
  `payment_intent.canceled` event since 02:50:46Z. So: a fresh intent and no L1.
- **Added by A to C's reasoning:** the setup effect's dependencies alone cannot rule out a remount. The recurring-mount
  query did not recur, and `useAuth` never flips `loading` back, so the two re-runs are Try Again presses.
- **Deviations recorded (two):** the rerun began before the first attempt's X close was verified, and the challenge
  page was reloaded.
- **Classification, proposed by A and C and pending the owner's acceptance:**
  - Stage 2 (rerun) PASS on payment safety.
  - D9-UX-1 recorded as a recovery defect found in D9, not a payment failure.
  - Device D7 is not retried.
  - Stage 3 on Device D8 follows the owner's acknowledgment and a fresh baseline.

**Correction.** A earlier stated it had no Stripe access. That was wrong: the local Stripe CLI (read-only, sandbox
account) was available. The Stripe facts for Stage 1 and the first Stage 2 attempt rest on C's reads and have not been
re-read by A.

**Evidence-hygiene notes (C, acknowledged by A).**
- **The blind check on Try Again presses is compromised.** Before A's blind check arrived, C's report to the owner asked
  "Did you tap Try Again twice?" and said the hold-released line likely showed first. The owner's answers on those two
  points are prompted and cannot corroborate the trace. The attribution of the two setup re-runs to presses rests on the
  logs and source alone:
  - two pre-check pairs;
  - the mount-time query did not recur;
  - `useAuth` never flips `loading` back.
- **C overstated path-1 coverage, and has corrected it.** C's record and owner report had called the rerun's closes
  "the close path Stage 1 couldn't test". Path 1 online ran twice, but both releases were no-ops after path 3. A path-1
  release of a **live** hold while online remains unexercised.
- **Stage 3 protocol.** C alone issues handset steps. Stage 3 on Device D8 waits for the owner's acceptance of the
  Stage 2 classification. C then takes a fresh baseline immediately before issuing one procedure, including "go back,
  not Try Again". If the owner's acknowledgment reaches A first, A forwards it to C.

### D9: owner acceptance of Stage 2, and the Stage 3 baseline (2026-09-11)

**Owner decision (relayed by C).**
- The owner **accepted** the Stage 2 (rerun) classification: PASS on payment safety, with the two deviations recorded.
- D9-UX-1 is recorded as an **open non-financial UX defect**, kept out of Build 16.
- Device D7 is not to be modified.

**Stage 3 baseline.** C read the database at 03:43:43Z and 03:44:47Z, and Stripe at 03:42:53Z and 03:43:46Z. A read the
database at 03:46:27Z and Stripe (read-only CLI) at 03:46:29Z. The reads are identical:
- **Device D8:** `active`/`active`, $100, no hold, `updated_at` 02:01:44.985 (staging), 0 payments, 0 transfers.
- **Device D1:** `sold`, one succeeded payment (`14a762bb`), 1 transfer, `updated_at` 01:05:11.648. It also carries the
  old `1fcd0c69` failed row `79d37964` from 09-08.
- **Phone P1:** unchanged (02:52:27.368; one `failed` row, one `pending` row).
- **Device D7:** unchanged (03:23:21.876; both rows `failed`).
- **Globals:** payments 50, transfers 33, succeeded 21, multi-succeeded 0, pending 3, reserved 0.
- **Latest writes:** listing write 03:23:21.876; webhook event 03:23:21.717 (`payment_failed`); no retries since.
- **Stripe:** no Device D8 intent. The newest charge is from 01:18:59Z, and there have been no events since 03:23:20Z.

**Stage 3 procedure, as issued by C.** It changes one thing from §23's D9c definition, on the owner's instruction
("require server verification before any further action").
- The owner stops after reconnecting and reports.
- Closing any open sheet or browser, then Home and Orders, becomes the next single step. C issues it only after
  verification.
- The (i)/(ii)/(iii) timing note and the interpretation table are unchanged.
- The stay-put guard covers:
  - Pay, Try Again, Complete, Fail and Done;
  - the sheet's X and any alert buttons;
  - reload, the back arrow and the swipe;
  - Orders and other listings;
  - backgrounding and force-quit.

**Timing note for the verifiers (A).**
- **The hold keeps running during the stop:** Buy Now plus 10 minutes, then the next 2-minute cron tick clears it.
- **If the attempt is still `requires_action`,** a slow verification lets the hold expire under an open sheet, so the
  in-window read must be taken as soon as the owner reports.
- **If Stripe shows `succeeded`,** settlement does not depend on the handset, and Device D8 should read `sold`. That is
  valid D9c evidence only under timing (i) or (ii).
- **After an expiry or a release,** the later close may surface D9-UX-1; the owner goes back rather than tapping Try
  Again.

### D9 Stage 3 (D9c, Device D8): server verification, classification, and the SDK reconciliation (2026-09-11)

**Owner report (to C):** "completed exactly as instructed". There are no times, no (i)/(ii)/(iii) timing and no
on-screen text. The owner asked A to cross-check and classify from the server evidence and the recorded handset
sequence, and does not want to be asked again.

**Server evidence.** C read Stripe at 04:04:19Z and the database at 04:04:18Z and 04:09:20Z. A read Stripe (CLI) at
04:14:33Z, the database at 04:14:17Z, and the logs for 03:53–04:10Z. The reads are identical.
- **Stripe.**
  - `pi_3UELWp…` (Device D8, `919d511e`, `buy_now`, 11000) is `requires_payment_method`. Nothing received, no charge,
    `last_payment_error` = `payment_intent_authentication_failure`.
  - Events, each with an API request id and idempotency key: created 03:53:31Z (`req_vOhs…`), `requires_action`
    03:54:16Z (`req_vt1U…`), `payment_failed` 03:55:43Z (`req_HP80…`).
  - The newest charge on the account is from 01:18:59Z.
- **Database.**
  - Device D8: `active`/`active`, no hold, `updated_at` 03:55:44.642. Row `9fc40dd6` is `failed`. 0 transfers.
  - Device D1, Phone P1 and Device D7 are unchanged.
  - Globals: payments 51, transfers 33, succeeded 21, multi-succeeded 0, pending 3, reserved 0. The only payment
    created since 03:44Z is Device D8's.
  - Webhooks: one event (`payment_failed`; received 03:55:44.437, processed, 1 attempt). No retries.
- **Logs.**

  | UTC | Event |
  |---|---|
  | 03:53:02.6 | app resume (token refresh + realtime) |
  | 03:53:26.651 | `reserve_buy_now` — hold taken, window to ≈04:03:26.7 |
  | 03:53:27.525 / .536 / .716 | checkout mount (F1 400) and setup pre-check |
  | 03:53:28–31.6 | `create-payment-intent`: `payments-lookup` 0, `pi-created`, `db-insert-ok`; no retire or cancel, so no L1 |
  | 03:54:16Z | `requires_action` |
  | 03:54:26.8 → 03:55:20.4 | handset REST gap; realtime upgrade at 03:55:10.5 |
  | 03:55:43Z | `payment_failed` (authentication failure) |
  | 03:55:44.316–.732 | `stripe-webhook`: claim, PATCH, `release_reservation` .631 (UPDATE .642) — path 3, ≈7.7 min before expiry |
  | 03:59:17.094 | first realtime upgrade after ≈4 min with none |
  | 03:59:17.6–19.186 | `confirm-payment` "not succeeded" |
  | 03:59:19.277 | handset `release_reservation` — a no-op (`updated_at` unchanged): path 1 online, the third no-op |

  After 03:59:19.3 there were no handset REST requests. There was no second F1 query, so no remount, and no
  settled-payment read after 03:53:27.536, so no Try Again.

**Classification: D9c UNTESTED** (§23 D9c table, row 1: no authorization and no charge, whatever the timing). Proposed
by C and confirmed by A.
- **Payment safety held:** no charge, no settlement or transfer, the hold released correctly by path 3, the path-1 close
  a no-op, and no L1.
- **Device D8 becomes a spare:** one `failed` row, so a rerun mints a fresh intent.
- A path-1 release of a live hold while online remains unexercised.

**Discrepancy.** The issued procedure touches nothing after reconnecting until verification. The server shows two
handset-side events after the phone was back online: the challenge ended (cancel request, `payment_failed` 03:55:43),
and the sheet returned `Canceled` (≈03:59:17). A reconciled them against the Stripe iOS SDK source in the local Pods.

The local Pods are Stripe iOS 24.19.0. Build 16 pins `@stripe/stripe-react-native` 0.50.3, whose podspec requires
`~> 24.19.0`. `df9e0d3` commits no Podfile.lock, so the binary's exact patch is unverified.

1. **Challenge end.**
   - `STPPaymentHandler._markChallengeCanceled` (`:1959`, "only called after web-redirects") runs from
     `_retrieveAndCheckIntentForCurrentAction`.
   - In the in-app 3-D Secure browser flows, that re-check starts only from:
     - `safariViewControllerDidFinish` (the browser's Close/Done, `:2290`);
     - the `ASWebAuthenticationSession` completion (Cancel or callback, `:1783`);
     - `handleURLCallback` (return URL).
   - The `willEnterForeground` re-check (`:1664`) is registered only for **external** browser or app redirects
     (`:1712`, `:1873`). A screen lock or app switch does not trigger it in the in-app flow.
   - For a web-based 3DS2 card challenge (`use_stripe_sdk`), the SDK retrieves the intent 6 times, 3 s apart
     (`maxChallengeRetries = 5`, `:2048`; card `timeBetweenPollingAttempts` = 3 in `STPPaymentMethodEnums.swift`), before
     cancelling. The trigger was therefore ≈03:55:25–27, or at 03:55:43 for `redirect_to_url`: either way after
     reconnection.
2. **Sheet `Canceled`.**
   - `StripePaymentSheet` has no lifecycle-driven dismissal. Its only lifecycle observers are the confirm button's
     `willEnterForeground` and the polling view's background/active hooks.
   - The React Native wrapper's iOS sources have none either.
   - `Canceled` corresponds to a sheet dismissal (close button or swipe-down). It coincided with the app resuming after
     ≈4 min of realtime silence.

**Conclusion.** In this SDK version, neither event has an automatic trigger. Both most likely followed a handset action
or a return-URL callback. **Not proven**, and no conclusion is drawn about the owner's actions. Not excluded:
- a hosted test-page script redirecting to the return URL after reconnecting;
- a different 24.19.x patch in the binary;
- an accidental swipe.

The classification does not depend on this. The owner is not asked again.

**Post-verification recovery step (issued by C; no rerun).**
1. Note the checkout text as it is, and tap nothing on checkout.
2. Use the back arrow to reach the Device D8 listing, noting whether Buy Now shows. Do not tap it.
3. Go to Home, then Orders, and confirm there is no Device D8 order.
4. Report. C and A then run read-only checks that nothing moved.

Leaving the listing cannot release anything. The listing screen refetched Device D8 as `active` at 03:59:18.953, after
the 03:55:44.6 release, so path 2's gate is false; and there is no hold. Rerunning D9c, or leaving it untested, is the
owner's decision, and neither verifier issues rerun steps unless the owner asks.

**Blind expectation (A; not to be prompted).**
- The 03:59:17–19 sequence is `releaseAbandonedHold`. Per `df9e0d3` `:379–384`, it sets "Your hold was released.
  Please go back and reserve again." with a "Try again" control.
- No setup re-run has been logged since 03:53:27.7.
- So the source predicts that text, not "Your reservation has expired…". An expired-text report would imply an
  unlogged setup run: check for log-ingestion lag or a remount first. If the app was relaunched, record whatever is
  shown.

**Correction: the Stage 3 checkout-text expectation is not blind.** A exposed it before the owner's report. It appeared
in A's owner-visible reply (the narration above the tool calls), in commit `d661e4a`, whose diff is visible in A's
transcript, and in A's earlier Stage 2 rerun reports. C kept it out of everything the owner sees. The owner's
observation of the checkout text is therefore recorded as **not blind**. It cannot corroborate the source prediction,
which rests only on `CheckoutNative.tsx:379–384` and the absence of any logged setup re-run. **Lesson for A:** a blind
expectation goes only to the other verifier, never into owner-visible narration or committed files, until the owner has
reported.

### Records handoff: canonical production state (2026-09-12)

Claude B published `docs/release/PHASE2_PRODUCTION_STATE_20260912.md` (commit `55d37f5`, read-only
reconciliation, no production mutation) after C6. It is the source of truth for production state and
supersedes the "current state" statements in six historical Phase-2 records, which stay valid as history.

**Agrees with this package as already recorded** (line 32): ledger **135**, numeric tip **120**, max version
`20260902003623`. Also: one active global ES256 `kernel.signing_key`, fingerprint pinned (v2) with the monitor
enabled and healthy, **14** ACTIVE edge functions including `credential-sign` / `door-manifest` /
`door-session` deployed dark at v1 from `562fda9` with 0 requests and 0 signatures, issuance/scanning/resale
flags false, native data all 0, cron 24 active. `primary-checkout` is still **not** deployed in production.

**Flagged against the planned release sequence.**
1. **Apply order, not numbering.** Migration `121` stays deferred (only under `AUTHORIZE PFA-18C MIGRATION
   121`) and `122` is reserved for B. `123` (transfers FK parity) is applied to the **sandbox only**. If `123`
   reaches production before them, `121`/`122` fall below the numeric tip and a strictly-increasing guard
   rejects them. Sequence B's pair first, or clear their apply against a tip of `123`. Recorded in the
   registry.
2. **Doc location.** B's state document exists only on `origin/feature/venue-native-and-product-v2`, as do the
   six dated banners. The release path does not carry them yet; that merge is a prerequisite for the release
   records to read consistently.
3. **Not covered by B's reconciliation:** F1 (`listings.cover_image_url`, absent in the sandbox and selected by
   Build 16's checkout) and F2 (`bids_bidder_id_fkey` targeting `auth.users`). Both are suspected
   production↔chain drift of the same class as the D7 transfers FK. Classifying them needs a read-only
   production catalog read, which this handoff does not authorize and which is not requested here.
4. **"Combined chain 142"** in B's §3 is B's chain label, not a migration number on this line. `142` is
   unowned in the registry.

Standing restrictions and the historical production apply order (076–092, 093–109, 115–120, then 110–114) are
preserved unchanged. Nothing here is authorization to apply, deploy, or activate anything.

### F1 / F2 parity checks — read-only, four-way (2026-09-12)

Production `hqycwntpfoztoinemqns` and sandbox `ofaidukbieeekqaboscm` catalogs read read-only; chain state read
from `origin/release/convergence-135`; client usage from `df9e0d3`. No writes anywhere.

**F1 — `listings.cover_image_url`: not drift, a client defect.**

| Source | State |
|---|---|
| Production | column **absent** (`listings` media columns: `cover_image_path text NOT NULL` only) |
| Sandbox | column **absent** — identical |
| Chain / fresh replay | never created: no `cover_image_url` in any migration; `000_baseline_schema.sql:98` defines `cover_image_path` only |
| Client (`df9e0d3`) | `CheckoutNative.tsx:138` **selects** it; the other nine references are `(listing as any).cover_image_url` fallbacks that read a property nothing ever sets |

- **Difference:** none between environments. Build 16 asks every environment for a column that has never existed.
- **Impact:** the checkout order-summary query returns **400 everywhere, production included**. `display` stays
  null, so cover, event, venue and date fall back to route params, and `reservedUntil` is never set — the Buy
  Now countdown cannot render on checkout. Observed three times in sandbox logs (02:50:42.217, 03:10:04.838,
  03:21:58.450, 03:53:27.525). No payment or hold impact: the reservation itself is server-owned.
- **Proposed correction:** client-only — drop `cover_image_url` from the select (and, optionally, the dead
  `as any` fallbacks). No migration. It belongs on C's post-matrix branch; **Build 16's pin stays unchanged**,
  so the countdown gap persists for the remaining handset stages and must not be scored.

**F2 — `bids_bidder_id_fkey`: real production↔chain drift, same class as D7.**

| Source | Target of `bids.bidder_id` |
|---|---|
| Production | `public.profiles` |
| Sandbox | `auth.users` |
| Chain / fresh replay | `auth.users` (`000_baseline_schema.sql:144`), unchanged by any later migration |
| Client (`df9e0d3`) | `useListingRealtime.ts:64` embeds `*, profiles(display_name, avatar_url)` |

- **Difference:** production was corrected out of band; the chain still reproduces `auth.users`.
- **Impact:** the embed resolves in production and fails as PGRST200 → 400 in sandbox and in any fresh replay,
  so bid history is empty on the listing screen there (observed at 02:50:35.025 and on every later listing
  load). The release risk is the same one D7 exposed: **the chain no longer reproduces production**, so any
  environment rebuilt from it — DR restore, a new sandbox, a staging clone — loses bid-history display.
- **Proposed correction:** migration **124** + pgTAP **192**, mirroring `123`: conditional, orphan-guarded
  retarget of `bids_bidder_id_fkey` to `public.profiles(id)`, a no-op where the constraint already points
  there. **Production needs no apply** — it is already correct; 124 exists to make the chain match it. Apply to
  the sandbox only, under separate authorization, after the handset matrix.
- **Also confirmed by the same read:** production `transfers_buyer_id_fkey` and `transfers_seller_id_fkey`
  both target `public.profiles`, so `123` is a verified no-op against production, as recorded.

**Not checked:** every other table's FK set. These two were checked because the client exercises them.

### D9c reconciliation — what the evidence establishes, and what stays unverified (2026-09-12)

The owner reported "completed exactly as instructed" with no screen or timing capture. This reconciles that
against C's verification and A's independent reads. Nothing below is inferred from the owner's phrasing.

**Established (Stripe CLI, database, Supabase logs; C and A agree):**
- Hold taken 03:53:26.651; intent `pi_3UELWp…` created 03:53:31; `requires_action` 03:54:16.
- Handset REST silent 03:54:26.8 → 03:55:20.4, with a realtime upgrade at 03:55:10.5.
- `payment_failed` (authentication failure) 03:55:43, from an API request.
- Webhook released the hold 03:55:44.63 (path 3), ≈7.7 min before expiry.
- Sheet closed later: `confirm-payment` "not succeeded" 03:59:19.17, handset release 03:59:19.277 — a no-op.
- **No authorization, no charge, no settlement, no transfer.** Device D8 `active`, one `failed` row.

**Unverified, and recorded as such:**
- Whether Complete was tapped while offline. Stripe shows authentication never succeeded, which is equally
  consistent with a tap whose request never left the device and with no tap at all.
- The (i)/(ii)/(iii) state at the cut, the cut time (bounded only: after 03:54:26.8, before the 03:55:10.5
  reconnect), and every on-screen text.
- What ended the challenge at ≈03:55:25–27 and what dismissed the sheet at ≈03:59:17. The SDK source shows no
  automatic trigger for either, but that is not proof of a tap.

**Consequence.** D9c stays **UNTESTED**. Across all three attempts the 3-D Secure authentication never
succeeded at Stripe, so each one landed at D9b's stage and the D9c question — a charge that succeeds while the
handset is offline — has never been reached.

**Recommendation: no rerun before D10/D11.**
1. Three attempts have produced the same failure mode. A fourth is likely to produce another UNTESTED and
   consumes a spare listing.
2. The risk D9c targets is largely covered elsewhere: settlement is server-side and independent of the handset
   (`settle_verified_payment` via the webhook, observed live on the settled devices), and the client's pending
   path is code-verified and was exercised by D5's 3-D Secure success.
3. D10 and D11 (deletion messaging, withdrawal) do not depend on D9c.
4. If the owner wants the gap closed, the honest option is an instrumented test rather than handset timing: the
   window between Stripe's success and the client learning of it is too short to hit manually. Otherwise close
   D9c as UNTESTED with the residual risk accepted and recorded.

### Authorized preparations, and the proposed production ordering (2026-09-12)

The owner accepted **D9c as UNTESTED** with its documented limits; no further payment attempt for that case.
Authorized as isolated preparation only — **no hosted application, no deployment, no change to Build 16's pin**.

**C — F1 (client-only).** Drop `cover_image_url` from `CheckoutNative.tsx:138`; verify the order summary and the
Buy Now countdown load, including a listing with a missing image (the sandbox's storage render path 400s on
every load, so that case reproduces without setup). No migration.

**A — F2: migration 124 + pgTAP 192, written, not applied.**
- `supabase/migrations/124_bids_profiles_fk_parity.sql` — conditional, orphan-guarded retarget of
  `bids_bidder_id_fkey` to `public.profiles(id)` **ON DELETE CASCADE**. The cascade matters: production's bids
  constraint cascades, unlike 123's transfers constraints, which are NO ACTION. Parity, not an improvement.
- `supabase/rollbacks/124_bids_profiles_fk_parity_rollback.sql` — returns the chain's pre-124 target
  (`auth.users`, no action). Running it against production would create the drift.
- `supabase/tests/192_bids_profiles_fk_parity.sql` — plan 11, `BEGIN … ROLLBACK`, read-only: existence, target,
  `confdeltype='c'`, `confupdtype='a'`, MATCH SIMPLE, validated and not deferrable, the full
  `pg_get_constraintdef` string matched verbatim against production's, zero orphans, and that
  `bids_listing_id_fkey` and the three bids RLS policies are untouched.
- **Constraint comparison (read-only, 2026-09-12).** Production:
  `FOREIGN KEY (bidder_id) REFERENCES profiles(id) ON DELETE CASCADE`, 98 bids, 0 orphans. Sandbox and a fresh
  replay: `FOREIGN KEY (bidder_id) REFERENCES auth.users(id)`, 0 bids, 0 orphans.
- **Correction carried into 124's header:** 123 recorded this sibling as latent, "no code embeds profiles off
  bids today". That was wrong — `useListingRealtime.ts:64` has always embedded it.

**Proposed production ordering: `121` → `122` → `123` → `124`.** Conditional on each migration's own readiness
and approval; **not executable today**.

| # | Owner | State | Gate |
|---|---|---|---|
| 121 | B | written, PR #58 draft rev 2 | `AUTHORIZE PFA-18C MIGRATION 121`; deferred optional hardening |
| 122 | B | **not written** (086↔112/113 expired-episode drift; B estimates 2–4 h engineering + 1 h apply) | needed before the scanning flip, not before C6 |
| 123 | A | written, tested, **sandbox-applied** | production apply unauthorized; must not precede 121/122 |
| 124 | A | written, tested, **not applied anywhere** | production needs none (already correct); sandbox apply after the matrix |

**Scheduling effect of 122 — flagged.** 122 does not exist yet, so the sequence is a plan, not a runbook. Three
consequences:
1. Nothing in this chain can be applied to production as a batch until B writes, rehearses and gets 122
   approved.
2. `123` and `124` are both independent of `121`/`122` in content; they are held behind them **only** by the
   ordering guard.
3. If 122 slips past the release window, the alternatives are to apply `121` alone under its own
   authorization and keep `122`→`124` as a later batch, or to have B renumber the unwritten `122` above `124`
   — coordinated with the registry, and cheap precisely because it is unwritten. `123`'s number stays fixed
   either way: renumbering it would break the sandbox apply history.

**124 — fresh-replay and no-op proofs (local PG 17.11 harness, 2026-09-12).** Script:
`scripts/release/local_124_bids_fk_rehearsal.sh`. Local scratch database only; no sandbox, no production.

| Proof | Result |
|---|---|
| P1 fresh replay of the whole chain, 141 files in `LC_ALL=C` order, 124 withheld | `FOREIGN KEY (bidder_id) REFERENCES auth.users(id)` — the drift reproduces |
| P2 apply 124 | `FOREIGN KEY (bidder_id) REFERENCES profiles(id) ON DELETE CASCADE` — byte-identical to production |
| P3 apply 124 again | "already matches production — no change"; constraint oid **and** xmin unchanged, so no catalog row was rewritten |
| P4 pgTAP 192 | **11/11 pass** |
| P5 orphan present, constraint dropped | `124 REFUSED — 1 bids row(s)…`; constraint left absent, nothing created blind |
| P6 orphan removed, constraint still absent | "was ABSENT — creating it", then the production definition |

**Defect found by P5, in my own migration, and fixed before commit.** The first draft guarded with
`if exists (… and confrelid is distinct from profiles …)`. With the constraint **absent** that is false, so it
silently did nothing and printed "already matches production" — the worst of both: no repair and a misleading
notice. 124 now handles three states: correct → no-op; wrong → orphan check, drop, recreate; absent → orphan
check, create. **`123` carries the same two-state shape.** Its absent case never arose (the constraint existed
in both environments), and it is already applied to the sandbox, so it is recorded here rather than edited. If
123 is ever re-applied to a database where the constraint is missing, it will skip instead of repairing.

### D10/D11 — one coordinated procedure (sandbox account, issued by C)

**Safety precondition, checked read-only 2026-09-12.** `delete-account`'s header states there is **no grace
period**: the sweep tombstones as soon as no blocker remains, and cron `sweep-deletion-pending` `*/2` is active.
Account `919d511e` is safe to test with **only** because it holds live obligations — 2 pending payments,
13 pending transfers, 6 disputed, 2 seller_sent. Do not run this on an account without blockers, and do not
settle or clean those rows first. Baseline: `kernel.identity_ext.deletion_state` = `ACTIVE`,
`deletion_requested_at` null, `public.account_deletions` 0 rows.

**D10 — deletion request.** Settings → delete account → confirm.
- Expected: `delete-account` `action='request'` → `kernel.request_account_deletion` (always accepts) →
  `deletion_state` `DELETION_PENDING`, response carrying `pending_obligations` naming the live-rail blockers.
- The screen should show the pending banner. Record its exact text; no wording is promised in advance.
- `kernel.is_deletion_pending` is the freeze operand, so app actions may be refused while pending — record what
  is refused. **No payment attempt.**
- **The real assertion:** hold through at least two sweep ticks (≥4 min) and confirm `deletion_state` is still
  `DELETION_PENDING`. Blockers must prevent the tombstone.

**D11 — withdrawal.** Settings banner → withdraw.
- Expected: `action='withdraw'` → `kernel.withdraw_account_deletion` → `deletion_state` back to `ACTIVE`, with
  an alert titled "Request withdrawn". Not to be prompted to the owner.

**Server checks, run separately by C and A after each step, read-only.**
- `kernel.identity_ext`: `deletion_state`, `deletion_requested_at`, `deletion_block_reason`.
- `public.account_deletions` row count.
- `delete-account` edge logs: `[delete-account] request_account_deletion for <uid>: <status>
  pending_obligations=N`.
- Unchanged counts for listings, payments and transfers.
- Read within 2 minutes of each tap, so the read sits inside a sweep interval; log read time against the `*/2`
  schedule.

**Hard stop.** If `deletion_state` ever reads anything other than `ACTIVE` or `DELETION_PENDING`, stop and
report before any further tap. Do not create a replacement account.

### D10/D11 cross-check of C's draft, and finding F3 (2026-09-12)

**Blocker prediction confirmed independently.** `public.account_deletion_blockers` is definer-only and A's
session cannot execute it, so A replicated its body read-only for `919d511e`: **9 rows, all `active_transfer`**.
C's read agrees, so the sheet should carry exactly one deduped line.

**Why no `pending_payment` line** (A's open question, resolved): that arm fires only when
`created_at > now() - 24h`, or an unresolved `webhook_retries` row names the payment. The buyer's two pending
payments are `fd616e02` (99.6 h) and `9f4ab181` (25.5 h), neither with a retry row. `9f4ab181` crossed the
24-hour boundary about 1.5 h before the check, so the prediction is time-sensitive by construction: any pending
payment created during the test adds a line. No payment attempt is authorized, so this is a record note.
`public.webhook_retries` holds 1 unresolved row globally, not on this buyer's payments; if it were, an
`unresolved_review` line would appear.

**BP-7 before BP-13 — C's safety argument verified against `077`.** `kernel.sweep_deletion_pending` coalesces
BP-1..BP-12 in order and stops at the first non-null; the BP-7 live arm ("an open or disputed live transfer
must reach a terminal state first") sits inside that coalesce. The live-rail aggregate
(`public.account_deletion_block_reason`, the BP-13 string) applies only when the coalesce is null. The sweep
writes its result to `identity_ext.deletion_block_reason` and tombstones only when the reason is null. So the
baseline reads BP-13 because that is the aggregate function C called, and after a tick the **stored** reason
should read BP-7. The record should name which function produced which string; they disagree by design.

**F3 — latent copy defect (A-reported, not blocking D10).** `OBLIGATION_LABELS` in `app/settings/index.tsx`
maps eight kinds, but `account_deletion_blockers` can return three it does not: `open_dispute`,
`unresolved_review`, `open_payout_attempt`. Unknown kinds fall back to the raw token, so a user in those states
sees `open_dispute` in the deletion sheet. This account is all `active_transfer`, so D10 will not surface it.
Fix belongs alongside F1, scope C's call.

**Numbering note, not a collision.** `121_settlement` … `124_account_deletion` are pgTAP suites under
`supabase/tests`; 121–124 here are migrations under `supabase/migrations`. The registry pairs them
(121→189, 122→190, 123→191, 124→192), and CI counts planned assertions across `supabase/tests/*.sql` without
mapping a suite to a migration by number.

**F1 fix reviewed (C, `2ba5281`, branch `frontend/f1-checkout-summary-query`): approved as written.** Named
column list, blank-as-absence mapping, and `reservedUntilMs` returning null rather than NaN. Production also has
no `cover_image_url` (A, read-only, on the owner's authorization), so C's "correct either way" hedge can become
a statement: the column exists in no environment.

### Correction to C's auto-release caveat, and finding F4 (2026-09-12, sandbox read-only)

C carried a caveat that two of the buyer's `seller_sent` transfers had `auto_release_at` within 6 hours, so the
deletion sheet might gain an `unpaid_seller_obligation` line mid-run. **Inverted.** Read at 04:24:30Z:

| Transfer | `auto_release_at` | Age past deadline | State |
|---|---|---|---|
| `83b83858` | 2026-09-11T00:54:49Z | **27.5 h overdue** | `seller_sent`, `payout_released_at` null, no dispute |
| `8f59d37e` | 2026-09-11T01:20:24Z | **27.1 h overdue** | same |

They are not about to flip; they are long overdue and static. **The blocker set is therefore mechanically
stable for the run** — barring a manual buyer confirmation, no `active_transfer` can become
`unpaid_seller_obligation` during D10, so the single deduped line holds by construction rather than by luck.

**F4 — live-rail auto-release does not run in the sandbox** (A-reported, candidate, not blocking D10).
- `public.get_auto_release_candidates()` exists but is a read, and **no pg_cron job calls it**.
- Of the 21 active jobs, `market-sweep-expired-p2p-transfers` (`*/2`) operates on `market.p2p_transfer` — the
  **native** rail, `status='initiated'`, `expires_at` — not `public.transfers`. `payout-execute-tick` (`*/10`)
  executes payouts that have already been released.
- So live-rail auto-release must be driven from outside pg_cron (the `confirm-and-release` edge on an external
  schedule), and nothing is driving it in the sandbox.
- **Why it matters:** wherever this also holds, seller payouts wait indefinitely after the buyer goes quiet —
  the auto-release deadline is the mechanism that pays a seller when the buyer never confirms.
- **Open question for the owner:** whether production has a scheduler for `confirm-and-release` that the sandbox
  lacks. A production `cron.job` read is read-only but outside the F1/F2 parity authorization, so it was **not**
  performed; it is put to the owner instead.

### Ordering: A's rule corrected, and the owner's real menu (2026-09-12)

C asked whether renumbering the unwritten `122` above `124` would strand `121` below the tip once `124` applied.
Checking it showed **A's rule was wrong**, so the question dissolves.

**Sourced correction.** `supabase db push --include-all` means "include all migrations not found on remote
history table": the default plan carries only versions above the remote maximum, and `--include-all` carries
every missing version, applied in `LC_ALL=C` order. There is no monotonic guard in CI or `supabase/ci`, and
production has already applied **115–120 before 110–114**. So a lower-numbered migration is never rejected — it
is merely absent from the default plan.

**Revised menu for `121` · `122` · `123` · `124`** (still nothing authorized):
1. **Wait for `122`**, then apply `121` → `122` → `123` → `124` in one ascending pass.
2. **Apply `121` alone** under its phrase now; take `122`–`124` later.
3. **Apply `123` and `124` first**, and take `121`/`122` afterwards with `--include-all` and a dry-run that
   lists exactly the intended versions.
4. Renumbering the unwritten `122` remains available, but it is now a **tidiness** choice, not a requirement.

**The constraints that do bind**, whichever is chosen:
- Every apply dry-runs first and the planned list is checked exactly — that is the real protection against a
  default push silently skipping a lower-numbered file.
- Where production's apply order differs from file order, the rehearsal replays **production's** order, as
  `convergence_prod_order_rehearsal.sh` already does.
- `123` keeps its number regardless, to preserve its sandbox apply history.

**F4 sharpened (2026-09-12): a missing schedule, not a missing deploy.** The sandbox's edge function list shows
`enforce-transfer-expiry` and `confirm-and-release` both **ACTIVE at v3**. So the code that would flip a
`seller_sent` transfer at its `auto_release_at` is deployed; nothing invokes it. C verified the database half
independently and added that `public.apply_auto_release` is the function that would set `payout_released_at`,
and that nothing in the database calls it. Both verifiers agree: 21 active cron jobs, none touching
`confirm-and-release`, `auto_release`, `public.transfers` or `enforce-transfer-expiry`.

The remaining unknown is unchanged and belongs to the owner: whether production drives those edges on an
external schedule (GitHub Actions, an external cron, a platform scheduler) that the sandbox lacks. Neither
verifier has read production's `cron.job`; it sits outside the F1/F2 parity authorization.

C also corrected the origin of its earlier caveat: its query used `auto_release_at < now() + interval '6 hours'`,
which matches every past deadline too, and the result was then described as "about to flip". C's re-read matches
A's: 0 transfers with a future deadline inside 6 hours, and the other 13 open rows carry no `auto_release_at`
at all.

### Ordering, final: two layers, both real (2026-09-12)

A's previous entry said the ordering guard "does not exist". **That was wrong**, and wrong the same way the
original claim was: A searched `.github/workflows/ci.yml` and `supabase/ci/` and reported a *global* absence.
C found it; A then read it. Both layers hold, and they govern different things.

**Layer 1 — merge time, and it does reject.** `.github/workflows/migrations-guard.yml` §4, "Monotonic ordering
for added migrations (scheme-aware)", runs on **every** pull request. For each newly **added** migration it
computes `basemax` = the highest version of the same scheme in the **base branch**, and fails when the added
version is not strictly greater:

> `::error::$f ($s scheme) is not greater than the latest existing $s migration ($basemax). Migrations must be
> append-only and monotonic.`

**Layer 2 — apply time, and it does not reject.** `supabase db push --include-all` = "include all migrations
not found on remote history table". The default plan carries only versions above the remote max, so a
lower-numbered file is silently **omitted**, never rejected. Production's own apply order is out of numeric
order — 115–120 on 2026-09-08, then 110–114 on 2026-09-09 — per Claude B's canonical state document
(`PHASE2_PRODUCTION_STATE_20260912.md` §1, now on the release path at `e115424`).

**Consequence: renumbering is not merely tidiness.** If `123` and `124` merge first, `basemax` becomes `124`
and a PR adding `122` fails CI. The same applies to `121`: it is written in PR #58, so once `124` is in the
base branch that PR trips the guard on re-run. Renumbering `121` costs a re-review; renumbering the **unwritten**
`122` costs nothing.

**Recommended sequence (C's, adopted by A; owner decides):** merge `121` → `123` → `124`, and number `122`
above `124` when it is written. That unblocks the QA-relevant pair without waiting on the venue work, keeps
every PR ascending, and avoids re-reviewing `121`. `123` keeps its number either way. Applies still dry-run with
the planned list checked exactly — that remains the protection at layer 2.

**Lesson recorded (A).** An absence claim is only as wide as the search behind it. "No guard in `ci.yml` and
`supabase/ci`" is a fact; "there is no guard" was an inference, and it was false.

### F4 resolved: production schedules the tick; the sandbox does not (2026-09-12, read-only)

Owner-authorized read-only investigation. No function was invoked, no schedule changed, no payout moved.

**Answer: "no database schedule" was a SANDBOX fact, not a system fact.**

| Evidence | Production | Sandbox |
|---|---|---|
| `cron.job` count | **24** | 21 |
| `enforce-transfer-expiry` job | **present, `*/2`, active** | **absent** |
| Job command | `net.http_post` to `/functions/v1/enforce-transfer-expiry` with a service-role bearer read from `vault.decrypted_secrets` | — |
| Runs, last 24 h | **720 succeeded, 0 failed** | — |
| Edge invocations, last 24 h | **720 × POST 200** | none |
| Transfers past `auto_release_at`, unreleased | **0** | 2 (27.5 h and 27.1 h overdue) |
| Open (`pending`/`seller_sent`) transfers | 0 | 21 |
| `auto_released` rows | 4 | 0 |

Production also carries `apply_auto_release(uuid)` and `get_auto_release_candidates()`, and both
`confirm-and-release` and `enforce-transfer-expiry` are ACTIVE edge functions (v36 / v38). Jobs the sandbox
lacks entirely: `enforce-transfer-expiry`, `ops-daily-summary`, `ops-detect-tick`.

**So F4 is a sandbox environment gap, not a product defect.** Sellers are not stranded in production. The
sandbox's two overdue transfers are an artefact of the missing tick, and they are exactly why D10/D11's blocker
set is stable — worth keeping, not "fixing", for the duration of the matrix.

**Incidental finding F5 — cron success does not mean the tick ran.** 7 of the 727 pg_net POSTs to that endpoint
in the last 24 h returned **401**, the most recent at 2026-09-12T04:18:00.401Z, all with user agent
`pg_net/0.20.4`, i.e. the scheduler itself rather than an outside caller. Because `pg_net` is asynchronous,
`cron.job_run_details` records the job as **succeeded** — it succeeded in *queueing* the request — so an
operator watching cron health sees 720/720 green and never sees the seven skipped sweeps. Each miss
self-corrects on the next `*/2` tick, so the impact is a delayed sweep, not a lost one. Worth a monitor that
reads HTTP status rather than job status. Not blocking anything; owner's call.

**Evidence not accessible to A:** whether any scheduler outside this project (a CI workflow, a platform
scheduler, a third-party cron) also targets these endpoints — the repository shows none, and the 401s are
accounted for by `pg_net`, but absence outside the project cannot be proven from inside it.
