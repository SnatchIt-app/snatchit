# Internal device-verification build — preparation package for the owner's confirmation (A, 2026-09-18)

**NOTHING HAS BEEN SUBMITTED.** The owner authorized *preparation* and required: *"Confirm the exact combined commit, changed files, build configuration and release notes before submitting the internal build."* This document is that confirmation request. **No build has been requested, no branch pushed, no deploy, no sandbox change.** PRs #72–#74 remain **draft and do-not-merge**.

## 1. The combined commit

| | |
|---|---|
| **Integration branch** | `integration/device-verify-20260918` (local only, not pushed) |
| **Combined head** | **`8da50c0`** |
| **Base** | `release/production-gate-20260918` = `6561d1f` |
| **Structure** | two no-fast-forward merges onto the base: `4c26332` (Batch 1/1b/1c) then `8da50c0` (F-SEC-1 + F-SEC-2). No rebase, no cherry-pick, no squash |
| **Proposed tag** | `candidate/2026-09-18-build-d1` (following `candidate/2026-09-18-build-c3` = Build 19) — **not created yet** |

**Every authorized head is an ancestor of `8da50c0`** — verified individually, not assumed:

| Batch | Head the owner authorized | Ancestor of `8da50c0` |
|---|---|---|
| Batch 1 | `2fe7abd` | **YES** |
| Batch 1b | `0ca71ff` | **YES** |
| Batch 1c | `2567401` | **YES** |
| F-SEC-1 | `016d8e2` | **YES** |
| F-SEC-2 | `f3cff27` | **YES** |

**On `f3cff27`:** the owner's list named it for F-SEC-2, and A had last reviewed `a6a8323`. A resolved the difference rather than assuming: `a6a8323` is an ancestor of `f3cff27`, and the one commit between them changes `src/hooks/useSecurityNotices.ts` by **+5 lines that are entirely comment** — D's record of why the TM7 mutant is equivalent today and what would end that equivalence. **No behaviour change**, so A's auth review of `a6a8323` carries to `f3cff27`.

**The merge altered neither side.** A compared the merged tree against each source head file by file — `useSecurityNotices.ts` and `security-notice.test.ts` are **byte-identical to `f3cff27`**; `profile.tsx`, `edit-profile.tsx`, `transfer/receive/[id].tsx`, `transferState.ts`, `home.tsx` and `PlaceBidScreen.tsx` are **byte-identical to `2567401`**. No conflicts arose; the two lines of work are disjoint in every file they touch.

## 2. Changed files — 24 files, +3038 / −92 against `6561d1f`

**Application code (11 files):** `app/(tabs)/home.tsx` · `app/(tabs)/profile.tsx` · `app/my-listings.tsx` · `app/settings/edit-profile.tsx` · `app/transfer/receive/[id].tsx` · `app/transfer/send/[id].tsx` · `src/components/SellerListingCard.tsx` · `src/hooks/useSecurityNotices.ts` · `src/lib/home/filterLoad.ts` (new) · `src/lib/transfer/transferState.ts` · `src/screens/PlaceBidScreen.tsx`

**Tests (13 files):** one shared reader `tests/helpers/screen-view.ts` (new), ten new suites, two amended.

**GATED SURFACE: ZERO LINES.** `git diff --stat 6561d1f..8da50c0` over `src/lib/payments.ts`, `src/lib/checkout/`, `src/lib/auth/signOut.ts`, `supabase/`, `scripts/`, `.github/`, `app.json`, `package.json`, `package-lock.json`, `eas.json` returns nothing. **No payment, checkout, sign-out, migration, schema, CI or dependency change is in this build.**

## 3. Verification of the combined tree

A ran these on the merged head itself, because a merge can produce a tree neither branch tested:

| Gate | Result at `8da50c0` |
|---|---|
| `npm run typecheck` | **exit 0** |
| `npm run lint` | **exit 0** — 29 warnings, 0 errors (unchanged baseline) |
| `npm run test` (full vitest) | **exit 0 — 116 files, 2332 tests, all passed** |

The count reconciles: the gate carries 106 files / 2250 tests, the three client batches add 8 files / 67 tests, and the two security branches add 2 files / 15 tests. No concurrent vitest was running.

## 4. Build configuration — read, not changed

| Setting | Value | Note |
|---|---|---|
| Profile | **`preview`** | `distribution: internal`, the same profile Build 19 used |
| Environment | **`EXPO_PUBLIC_APP_ENV=sandbox`** | points at the **sandbox** Supabase project and the **test** Stripe publishable key — **not production** |
| Version | `1.0.0` (`app.json`) | unchanged |
| Build number | assigned **remotely** | `eas.json` sets `cli.appVersionSource: "remote"` and `preview.ios.autoIncrement: true`, so **no file edit is needed and none is proposed** |
| Bundle id | `com.jdt-inc.snatchit` | unchanged |
| infoPlist | `ITSAppUsesNonExemptEncryption`, `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` | unchanged; `UIDesignRequiresCompatibility` still **not** set (the iOS 27 gate recorded earlier) |
| Submit config | untouched | this is an internal build; **no App Store submission is proposed** |

**Nothing in `app.json` or `eas.json` changes for this build.** Secrets are referenced by name only.

## 5. Release notes (internal build — what to test, and what is unchanged)

**This build exists to put eleven source-and-test-verified fixes on a device. None has ever run on hardware.**

**Consumer state correctness**
1. **Place bid** no longer builds a form on a `$0` floor after a failed read, and a rejected read no longer leaves the spinner forever.
2. **Home → "Recently sold" / "Ended"** no longer claim an empty marketplace when their fetch fails.
3. **My listings** delete/cancel take a per-listing lock, so a double tap cannot fire twice.

**Transfers — wording only, no rule change**
4. **Send transfer** no longer says "Transfer window expired"; it says the send window has passed and sending may still work.
5. **Receive transfer** shows **no window line at all** once the seller has sent, and the buyer's wording says *the seller* may still send — the buyer is no longer told to send.

**Avatars**
6. **Profile** and **Settings › Edit Profile** stay busy through upload *and* database save.
7. Both are now same-tick safe: two presses in one event loop produce **one** upload and **one** database write.

**Security notice**
8. **"Sign out of all devices"** cannot invoke the sign-out twice from two presses in one event loop.
9. A **thrown** failure on either security action now shows the existing failure message instead of failing silently.
10. A throw **after** a successful sign-out is logged, never reported as a failed sign-out.

**Unchanged and explicitly not in this build:** server behaviour, session policy, transfer rules, payments, checkout, sign-out internals, database schema, migrations, sandbox data, the retained Line 3 proof files. Migration 138 and 141 remain unapplied. The environment is the sandbox.

## 6. After the build — roles as the owner set them

- **C owns handset verification** and must test the changed flows on-device.
- **D records the distinction between source/test review and device evidence** — this is the point of the build: everything above is *source and test* evidence, and **no flow in this list has device evidence yet**.
- **Deferred until after device verification**, by the owner: **F-SEC-3**, **F-SEC-1-B** (the uniqueness-assertion follow-up in 1b/1c), and the **unknown-outcome copy decision**.

## 7. What A needs before submitting

The owner's confirmation of §1–§5. On confirmation A will tag `candidate/2026-09-18-build-d1` at `8da50c0` and submit the `preview` build. **Until then nothing is pushed, tagged, built or submitted.**
