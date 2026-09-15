# Candidate build configuration and targeted device test plan (release sprint, target 2026-09-18)

Prepared 2026-09-14 by C. Configuration only — no build is cut by this document;
hosted builds, sandbox mutations and production remain separately authorised.
Build 16 (`df9e0d3`, profile `preview`) stays the historical tested pin.

## 1. Candidate build configuration (proposed; A pins the commit)

| Field | Value | Source |
|---|---|---|
| EAS profile | `preview` — same profile as Build 16: `distribution: internal`, `EXPO_PUBLIC_APP_ENV=sandbox`, sandbox Supabase URL/anon key, `pk_test_` publishable key, Sentry auto-upload off, `ios.autoIncrement: true` | `eas.json` |
| Why not `sandbox` profile | it builds an iOS **simulator** binary; handset verification needs a device build | `eas.json` `build.sandbox.ios.simulator` |
| App version / build number | `expo.version` 1.0.0; build number assigned remotely (`appVersionSource: remote`, autoIncrement) — expected next = 17; A records the assigned number in the release packet | `app.json`, `eas.json` |
| Source commit | ONE integrated commit on A's release branch containing `frontend/premium-batch-1..4` heads (43e3a97, 73a5f19, d48c290, 9091397) plus the candidate-recovery slice (this sprint) and any B/A fixes A integrates; A pins it, C records it in the plan header | A's release package |
| Runtime | no `expo-updates` (`runtimeVersion` unset): the binary is the artifact; no OTA | `app.json` |
| Env guard | build must pass the sandbox-vs-prod guard (`src/config/envGuard.ts`: sandbox ref `ofaidukbieeekqaboscm`, prod ref `hqycwntpfoztoinemqns`); a prod ref with a `pk_test_` key or vice versa is a refused build | envGuard |
| Secrets | none in `eas.json` beyond public-class values (anon key, `pk_test_`, Sentry DSN); nothing else may be added to the profile | CLAUDE.md standing rule |
| Local prerequisites | `npx tsc --noEmit -p tsconfig.json` clean; `npx vitest run` all green; `npm run lint` 0 errors, at the pinned commit — A witnesses | gates |
| Owner authorisation needed | the hosted EAS build itself; installing on the handset; the sandbox window for the money rows | directive |

Record in the release packet: EAS build id, assigned build number, pinned commit, profile, date, device (model, iOS version), tester.

## 2. Targeted device test plan (ordered, time-boxed; rows from `DEVICE_VERIFICATION_CHECKLIST.md`)

Principles (directive rule 8): retest changed behaviour and integration risks; do not repeat the Build 16 matrix. Closed Build 16 results and their limitations stand. Sandbox writes only inside A's serialized window; every write row names A.

### Block 0 — smoke (15 min, no window)
Cold start on sandbox; sign in; Home paints; Reduce Motion off/on toggle; VoiceOver on/off. Stop the plan if the build cannot sign in.

### Block 1 — no-window rows (≈60–75 min)
DV-101 card handoff · DV-103 quiet refresh + **T re-run** (Tickets loading changed in batch 1) · DV-106 image fallback · DV-107 preserved place · DV-201 press response · DV-203 pending labels on non-money actions (Your scene "Saving…", report "Sending report…") · DV-204 reversible actions offline (airplane mode) · DV-206 Reduce Motion · DV-206b VoiceOver · DV-208 Dynamic Type · DV-208b unsaved-work dialogs · DV-609 seller proceeds copy · DV-611 sign-out revoke (A read-back) · DV-611L legacy registration on a fresh install (A read-back) · **new this sprint:** empty/failed/filtered states on Home, Explore, Bids, Tickets (airplane mode → "couldn't load", filters → "No matches", empty account → empty state; never an empty state during load); cancelled listing appears as "Cancelled" in Bids; expired-session notice on the login screen.

### Block 2 — sandbox window rows (A serializes; ≈90–120 min in one window)
DV-302 hold row + Pay withdrawn in the margin · DV-301 hold ran out · DV-304 price change (A stages) · DV-305 interruption ("Checking your payment"; **no new attempt at D9c**) · DV-306 "Confirming payment" → "Finalizing your order" · DV-308 refund faces (A stages rows) · DV-202 bid/purchase/receipt haptics · DV-203b bid outcome with a staged outbid · DV-205 double tap (A read-back: one row each) · DV-402 claim vs possession through a full transfer · DV-404 / DV-404b provider return · DV-501 at-zero "Confirming result" (A read-back: no client finalize) · DV-502 in-place bid · DV-504 connection health · DV-505 My Bids order · DV-611S account switch on the legacy path (A read-back).

### Block 3 — only if the owner authorises 128 on the sandbox
DV-611R registration/refresh/rebind/recovery outcomes per the frozen contract.

### Explicitly not closed by this candidate
Populated native Tickets (issuance disabled, CFT-801) and D9c (no further attempts) stay UNTESTED; the deferred Premium items stay in the backlog.

### Evidence and exit
Per row: PASS / FAIL / UNTESTED, the on-screen text observed, and A's read-back where marked. A FAIL on a money or privacy row blocks the candidate; a FAIL on a presentation row is logged and triaged (fix on the sprint branch → A re-integrates → re-run that row only). Exit: every Block 1 and Block 2 row has a result; UNTESTED rows carry their reason.

## 3. Time budget (deadline-backward)
- Fri 09-18: release packet inputs from C (verification results, limitations, exact restart instructions if anything is left running). Reserve the day; no new code.
- Thu 09-17: candidate build (owner-authorised), Block 0–1 on the handset, Block 2 in A's window, fixes and re-runs of changed rows.
- Wed 09-16: 128 rebind to the frozen contract (2–4 active hours) + tests; integration fixes from A's snapshot.
- Tue 09-15: candidate-recovery slice landed and reviewed (error/empty/failed states, cancelled listing in Bids, expired-session notice, not-found outcome); gates green.
- Mon 09-14 (now): this plan; sprint branch open.
