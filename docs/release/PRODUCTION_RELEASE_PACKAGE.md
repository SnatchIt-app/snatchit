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

`paid_at` falls inside the webhook's own processing window, which is **consistent with `stripe-webhook`
settling the order after the client was killed** — the path D8 exists to exercise. (`settle_verified_payment`
is shared with `confirm-payment`, so this is strong timing evidence rather than a recorded source field.)

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

Which one appears depends on the exact error text reaching `classifySettlement`. Its pending patterns include
`network request failed` and `failed to fetch`; an offline error phrased any other way falls through to
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
