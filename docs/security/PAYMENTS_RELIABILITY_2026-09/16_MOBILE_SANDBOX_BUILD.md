# Sandbox-only mobile build — configuration, isolation evidence, and device test status

Tested commit: **`1d67a3e`** (this document and the preflight land on top). Previous sandbox-verified commit: `8fd4408`
(server-side matrix 49/49). Changes since `8fd4408` are the mobile build configuration and guard described here, plus
docs; no migration, edge function or fee logic changed.

## 1. What was built

A **clearly labeled, sandbox-only** build path that cannot be confused with production:

| Piece | File | Effect |
|---|---|---|
| Sandbox build profile | `eas.json` (new 4th profile) | `EXPO_PUBLIC_APP_ENV=sandbox`, sandbox Supabase URL, empty Sentry. Client identifiers are deliberately **empty in git**; local builds take them from the git-ignored `scripts/sandbox/sandbox.env`. The `production` profile is byte-identical (diff is insertions only). |
| Runtime guard | `src/config/envGuard.ts` | Pure function over three compile-time strings. Refuses F1–F8: live key on the sandbox DB, **TEST key on the PRODUCTION DB**, right mode/wrong Stripe account, mislabeled env, unknown host, unset env, altered PaymentSheet return URL. |
| Guard placement | `src/lib/supabase.ts` (first import) | Runs **before** `createClient`, i.e. before any network call, auth refresh or PaymentSheet init. On failure the client is pointed at an unroutable host. |
| Blocking screen + badge | `app/_layout.tsx` | A failure renders a non-dismissible full-screen blocker (never a module-load throw, which crashes iOS silently). A correct sandbox build shows a persistent `SANDBOX — TEST MONEY ONLY` badge. |
| Build-time twin | `scripts/ci/assert-env-pairing.mjs` | Fails CI on any new bad pairing; also decodes a legacy anon JWT and checks its `ref` matches the URL. |
| Build wrapper | `scripts/sandbox/30_build_ios_sim.sh` | Re-verifies the sandbox pair, then builds. Refuses production refs outright. |
| Tests | `tests/env-guard.test.ts` | 10 cases: 2 accepted pairings, 8 refused. |

**Defect found and recorded (owner decision):** `eas.json` `development` and `preview` paired the **live account's TEST
publishable key with the PRODUCTION Supabase project**. A build from either read and wrote production data while
payments silently could not work. **RESOLVED 2026-09-07 — both profiles now target the sandbox pair; see §6.**

## 2. Isolation evidence — from the shipping bundle, not from configuration files

`EXPO_PUBLIC_*` values are inlined by Babel at bundle time, so the only conclusive proof is the compiled artifact. The
iOS Hermes bundle was exported with the sandbox environment and scanned by exact byte match:

| Byte pattern in the shipping bundle | Count | Meaning |
|---|---|---|
| `https://ofaidukbieeekqaboscm.supabase.co` | 1 | the app targets the sandbox project |
| `https://hqycwntpfoztoinemqns.supabase.co` | **0** | no production URL is compiled in |
| `hqycwntpfoztoinemqns` (bare) | 1 | the guard's comparison constant only — no URL |
| sandbox publishable key (`pk_test_51T6Fb1…`) | 1 | sandbox Stripe account |
| `pk_live_51T6Far…` / `pk_test_51T6Far…` | **0 / 0** | no live key, no live-account key |
| `sk_test_` / `sk_live_` / `service_role` | **0 / 0 / 0** | no Stripe secret key and no service-role credential in the app |
| `SnatchIt env guard`, `SANDBOX` | 1, 2 | guard and badge are present in the binary |

## 3. Device test status — simulator BLOCKED by a missing Xcode component

**No flow was executed on a simulator or a device. Nothing here may be counted as device verification.**

Root cause, established by elimination: Xcode 26.6 provides the iOS 26.5 **SDK** but no matching **simulator runtime**;
the only installed runtime is iOS 26.2, which `simctl` can boot (a device was booted successfully) but `xcodebuild`
will not build against — `xcodebuild -showdestinations` lists **no** `platform:iOS Simulator` destination at all and
`-showBuildSettings` fails with "Found no destinations for the scheme". An explicit `-destination` and a
CoreSimulatorService restart both failed identically. The same missing component also makes the connected iPhone
ineligible ("iOS 26.5 is not installed"), so it blocks the physical path as well.

This is a free Apple download, not a purchase. It was **not** run unattended: the download is ~9 GB and must expand,
while the machine had 9.5 GB free after safe cache reclamation (npm cache, unavailable simulators, CocoaPods cache —
all self-regenerating). Starting it could have filled the disk.

`scripts/sandbox/30_build_ios_sim.sh` now detects this condition up front and prints the remedy instead of failing deep
inside Xcode.

## 4. Classification

| Class | Items |
|---|---|
| **Proven server-side (real Stripe test mode, 49/49)** | checkout + settlement, cancellation, duplicate/out-of-order webhooks, partial + full refunds, dispute lost chargeback, real Connect transfer + idempotent repeat + reversal, deletion obligations under the real sweep, rate limiter, mode boundary. `15_SANDBOX_RESULTS.md`. Do not re-test on a device. |
| **Proven by artifact inspection (this document §2)** | the app binary targets the sandbox and contains no production endpoint and no secret. |
| **Proven by unit test** | the guard's accept/refuse matrix (`tests/env-guard.test.ts`), fee model 10/10 with no fixed fee. |
| **Simulator-automatable, NOT YET RUN (blocked)** | sign-in with the synthetic users; checkout with fee totals shown; PaymentSheet cancel then retry; 3DS completion; 3DS cancellation returning to the app; success reflected in order/listing UI; background/network-loss recovery with no duplicate payment; deletion messaging with pending obligations. |
| **Physical-iPhone only (justified)** | Apple Pay (`isPlatformPaySupported()` is false on a simulator and the merchant entitlement is device-bound); push-notification routing (skipped unless `Device.isDevice`); real Wi-Fi/cellular handoff. |
| **Explicitly NOT physical-only** | test-mode 3DS is a Stripe-hosted in-app sheet with no bank hand-off; biometrics are unused by the app. |

## 5. The two client-side findings — investigated, one premise corrected, both fixed

Reproduced as failing unit tests first, then fixed. `tests/checkout-settlement.test.ts` (22 cases) fails before the fix
and passes after.

**Finding 2 confirmed as stated.** The post-charge path set the sold state unconditionally, so *every* outcome —
including a genuine failure — ended on "Purchase complete!" immediately after a support alert.

**Finding 1 was right about the symptom and wrong about the cause, and the originally proposed fix would have been
harmful.** After a normal settlement `mark_listing_sold` returns **no error at all** (the core answers
`already_settled`). The message `This listing has already been sold.` is raised **only** when the listing is bound to a
*different* payment — post-charge that means the platform holds the buyer's money and cannot fulfil the order.
Filtering it away as "benign", as the finding proposed, would have shown "Purchase complete!" for an unfulfillable
order. It was not done. The real false alarm came from a different refusal — `No verified payment found for this
listing…` — which fires while Stripe simply has not flipped the PaymentIntent yet: nothing is wrong and nothing is
lost.

**A third, pre-existing defect surfaced:** the shipped tolerance pattern `/already sold/i` never matched the SQL
wording "has already been **been** sold" (only the edge's "is already sold"). Corrected in one place to
`/already (been )?sold/i`, with every caller cited.

**The fix** introduces three explicit outcomes that may never be collapsed, in `src/lib/payments.ts`
(`classifySettlement`, `SETTLEMENT_COPY` as the single source of user-facing copy) and consumed by
`CheckoutNative.tsx`:

| Outcome | When | What the buyer sees |
|---|---|---|
| `completed` | no RPC error, or the server itself reports `settled` / `already_settled` | success screen, unchanged copy |
| `pending` | the charge is captured or still settling and the webhook will finish it; or the RPC never reached the server | **no alert**; a calm "Payment received — your payment is safe; please don't pay again" |
| `failed` | a terminal refusal, including the unfulfillable case above | an actionable alert, and **never** "Purchase complete!" |

Fee model untouched (10% / 10%, no fixed fee).

## 6. `development` / `preview` repointed to the sandbox (2026-09-07)

Both profiles bound `EXPO_PUBLIC_SUPABASE_URL` to the **production** project while carrying the LIVE Stripe account's
TEST publishable key (`pk_test_51T6Far…`). Since `EXPO_PUBLIC_*` is inlined at bundle time, every binary ever produced
from those profiles talked to production data and could not take a payment. Both now bind the isolated pair.

| | before | after |
|---|---|---|
| `EXPO_PUBLIC_APP_ENV` | `development` / `staging` | `sandbox` (both) |
| Supabase project | `hqycwntpfoztoinemqns` (PRODUCTION) | `ofaidukbieeekqaboscm` (sandbox) |
| Anon key | `sb_publishable_dBAq…` (production, opaque — carries no project ref) | sandbox legacy anon JWT (`ref=ofaidukbieeekqaboscm`, `role=anon`) |
| Stripe | `pk_test_51T6Far…` (LIVE account, test mode) | `pk_test_51T6Fb1…` (Stripe Sandbox `acct_1T6Fb1GlD5aqtxIw`) |

**Build semantics preserved exactly — only the environment binding changed.** `development` keeps
`developmentClient: true` + `distribution: internal`; `preview` keeps `distribution: internal`; neither has
`autoIncrement`, a `channel`, or an `ios.simulator` flag, and none was added. `production` (`autoIncrement: true`,
`pk_live_51T6Far…`, production project) and the `submit.production` block are **byte-identical** — the diff is 8 lines,
all inside the `development`/`preview` `env` objects. The `sandbox` profile is untouched. The Sentry DSN on both
profiles is unchanged, so internal builds keep reporting crashes; their `environment` tag is now `sandbox` rather than
`development`/`staging`, which is what they actually are.

**`APP_ENV=sandbox` (not `development`/`staging`) is deliberate.** The guard treats any other label leniently, so those
values would have left F1 dormant and, more importantly, `IS_SANDBOX_BUILD` false — no `SANDBOX — TEST MONEY ONLY`
badge (`app/_layout.tsx:144`). A build that spends test money must say so on screen. It also makes F1 a second,
independent tripwire if the URL is ever pointed back at production. Nothing keys off the old labels: the only other
readers are `NativeAppShell.native.tsx:33` (Sentry environment) and two `!== 'production'` dev-affordance checks
(`ListingDetailScreen.tsx:1286`, `app/settings/blocked-users.tsx:52`), which behave identically under `sandbox`.

**Why the sandbox client identifiers are committed.** Both are public client identifiers designed to ship inside a
binary: the anon key is a `role=anon` JWT whose authority is whatever RLS grants it, and the publishable key is meant to
be public (Stripe's own term). The repo already commits the production anon JWT and `pk_live_…` in the `production`
profile on the same basis, and an EAS cloud build cannot run with empty values — leaving them blank would have left both
profiles unbuildable, i.e. the defect unfixed. Committing the **legacy JWT** anon key also strengthens the check: it
embeds its own project ref, so `assert-env-pairing.mjs`'s F9 decode now catches a URL/anon-key mismatch that the opaque
`sb_publishable_…` form could not express. No `sk_*`, no `whsec_*` and no service-role key is in `eas.json` or in any
committed file; those stay in the git-ignored `scripts/sandbox/sandbox.secrets.env`.

**`KNOWN_VIOLATIONS` is now empty** (`scripts/ci/assert-env-pairing.mjs`) and documented as needing to stay empty. The
script still exits 1 on any new bad pairing.

**Verification (2026-09-07, `release/payments-converged-rc`)**

| Check | Result |
|---|---|
| `node scripts/ci/assert-env-pairing.mjs` | exit 0 — `env pairing check OK (4 profiles)`, one `note` for the intentionally empty `sandbox` profile, no `KNOWN`/`resolved` lines |
| `npx vitest run tests/env-guard.test.ts` | 10/10 pass |
| `evaluateEnv()` (the shipping guard) over each profile's `env` | `development` ACCEPTED, badge on · `preview` ACCEPTED, badge on · `production` ACCEPTED, badge off · `sandbox` refused F6 (identifiers empty in git — pre-existing and intended) |
| Negative control: `preview` URL flipped back to production in a scratch copy | exit 1 with F4 + F5 + F9 |
| `production` profile before/after | parsed JSON identical (`JSON.stringify` equality) |

**Two residuals, neither introduced here.** (1) `assert-env-pairing.mjs` is invoked only by
`scripts/sandbox/30_build_ios_sim.sh:36`; no `.github/workflows/*` job runs it, so it is not yet a CI gate — wiring it
into the `quality` job is a one-line change outside this scope. (2) `eas build --profile sandbox` still cannot produce a
runnable binary (empty identifiers, guard F6); with `development`/`preview` now correctly paired, that profile's
emptiness no longer withholds anything that is not already committed, and the owner may want to fill it or drop it.
