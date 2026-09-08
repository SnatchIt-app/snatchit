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

**Defect found and recorded (owner decision):** `eas.json` `development` and `preview` pair the **live account's TEST
publishable key with the PRODUCTION Supabase project**. A build from either reads and writes production data while
payments silently cannot work. They are listed in `KNOWN_VIOLATIONS` so CI fails on anything new, and the runtime guard
(F4) now refuses such a build — **those two profiles are unusable until repointed.** They were left otherwise untouched.

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

## 5. Two client-side findings from the review, still unverified (they need the app to run)

1. `CheckoutNative.tsx` does not apply the benign-error filter to `mark_listing_sold` failures, so the documented,
   expected refusal after settlement may surface a "Payment Received … contact support" alert on a **successful**
   purchase. The server behaviour is already proven correct; this is presentation only.
2. The same path sets the sold state regardless, so the user could see a support alert followed by "Purchase complete".

Neither was changed: both need a running app to confirm, and both are UI-level, outside the payments-reliability
migrations under review.
