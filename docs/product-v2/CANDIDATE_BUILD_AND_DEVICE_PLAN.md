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

### 1a. Pin pre-flight and the one-command submission (2026-09-15)

Pin: tag `candidate/2026-09-18-pin` = `4b012fd` on `release/candidate-20260918` (A). Verified by C from origin:
`231f120` (C's rebased stack) is an ancestor; `app/` and `src/` are byte-identical to the approved head `db5bddf`
(0 differing files); `eas.json` is identical to Build 16's (`df9e0d3`); the `preview` profile is `distribution:
internal`, `EXPO_PUBLIC_APP_ENV=sandbox`, the sandbox Supabase URL, `ios.autoIncrement: true`,
`appVersionSource: remote`, Sentry auto-upload off, public-class values only; `envGuard.ts` carries the sandbox ref;
`app.json` `expo.version` 1.0.0.

**HOLD:** GitHub CI at the pin has not passed (the run at the docs tip failed; runs at the pin were cancelled by
later pushes). O-2 reads "after the required checks pass", so the build is NOT submitted until A reports CI green
at the pin. If a fix moves the pin, A names the new tag and this pre-flight is re-run against it.

When A reports green, the submission is, from a clean worktree at the tag (the owner's EAS login; nothing else
changes):

```bash
git fetch origin "refs/tags/candidate/2026-09-18-pin:refs/tags/candidate/2026-09-18-pin" && git worktree add /Users/josetascon/snatchit-candidate candidate/2026-09-18-pin && cd /Users/josetascon/snatchit-candidate && npm ci && git rev-parse --short HEAD && eas build --platform ios --profile preview --non-interactive --message "candidate 2026-09-18 pin 4b012fd"
```

Record afterwards: the EAS build id and the assigned build number (expected 17), in `RELEASE_PACKET_C_SECTION.md`.

**Re-pin pre-flight (2026-09-15, later):** CI is green at `release/candidate-20260918 @ aabe029` (A: all five jobs,
pgTAP 4980 PASS on the real stack); A names it the intended pin. Verified by C from origin: `231f120` is an
ancestor; `app/` and `src/` identical to `db5bddf`; `eas.json` identical to Build 16; `envGuard` sandbox ref and
`expo.version` 1.0.0 unchanged; the whole delta `4b012fd..aabe029` is four `docs/release` files,
`scripts/rehearsal_test.sh` and `supabase/tests/193_ops_console_refund_exactness.sql` — no app, src, eas.json or
edge change. The tag `candidate/2026-09-18-pin` moves to `aabe029` after D's incremental re-run and the 193
fixture re-review; the submission command above is unchanged except its `--message` names the new commit. Still
HELD until A sends the moved tag and states CI green at it (O-2's condition). Thursday morning submission stands.

## 2. Targeted device test plan (ordered, time-boxed; rows from `DEVICE_VERIFICATION_CHECKLIST.md`)

Principles (directive rule 8): retest changed behaviour and integration risks; do not repeat the Build 16 matrix. Closed Build 16 results and their limitations stand. Sandbox writes only inside A's serialized window; every write row names A.

### Block 0 — smoke (15 min, no window)
Cold start on sandbox; sign in; Home paints; Reduce Motion off/on toggle; VoiceOver on/off. Stop the plan if the build cannot sign in.

### Block 1 — no-window rows (≈60–75 min)
DV-101 card handoff · DV-103 quiet refresh + **T re-run** (Tickets loading changed in batch 1) · DV-106 image fallback · DV-107 preserved place · DV-201 press response · DV-203 pending labels on non-money actions (Your scene "Saving…", report "Sending report…") · DV-204 reversible actions offline (airplane mode) · DV-206 Reduce Motion · DV-206b VoiceOver · DV-208 Dynamic Type · DV-208b unsaved-work dialogs · DV-609 seller proceeds copy · DV-611 sign-out revoke (A read-back) · DV-611L legacy registration on a fresh install (A read-back) · **new this sprint:** empty/failed/filtered states on Home, Explore, Bids, Tickets (airplane mode → "couldn't load", filters → "No matches", empty account → empty state; never an empty state during load); cancelled listing appears as "Cancelled" in Bids; expired-session notice on the login screen.

### Block 2 — sandbox window rows (A serializes; ≈90–120 min in one window)
DV-302 hold row + Pay withdrawn in the margin · DV-301 hold ran out · DV-304 price change (A stages) · DV-305 interruption ("Checking your payment"; **no new attempt at D9c**) · DV-306 "Confirming payment" → "Finalizing your order" · DV-308 refund faces (A stages rows) · DV-202 bid/purchase/receipt haptics · DV-203b bid outcome with a staged outbid · DV-205 double tap (A read-back: one row each) · DV-402 claim vs possession through a full transfer · DV-404 / DV-404b provider return · DV-501 at-zero "Confirming result" (A read-back: no client finalize) · DV-502 in-place bid · DV-504 connection health · DV-505 My Bids order · DV-611S account switch on the legacy path (A read-back).

### Block 2b — sprint-specific integration risks (A's C-3; in the same window)
DV-L1 failed attempt then retry on the same listing · DV-L2 leaving checkout after success · DV-607b cancelled listing · DV-607c delayed transfer · DV-607d unavailable account + F3 labels · DV-F8 partial refund. No-window: DV-607a session expiry · DV-605 listing gone · DV-611C cold-launch registration · DV-T.

### Sandbox state (A, 2026-09-15 late): 124, 125, 127, 128, 129, 130 applied (ledger 136); 126 deferred by owner ruling; `stripe-webhook` v4 + `create-payment-intent` v4 deployed from the tag
DV-L1/L2 and DV-611 L/S/R/C are therefore runnable on build 17. Rows that need the `ops` schema (126) are
**not-run-on-sandbox** (not failed). Superseded note below kept for history.

### Handset session 1 — Block 0 + Block 1 (build 17, no sandbox window needed; A on read-backs)
Install: open the EAS build page on the provisioned iPhone and tap Install
(`https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/53e5e98b-dbe9-405d-a7c8-159375c3fbc6`, build 17,
`aabe029`). Trust the ad-hoc profile if iOS asks. Record: iPhone model, iOS version, tester, start time.

**Block 0 — smoke (15 min). Stop the session if any step fails.**
1. Cold start → the app opens on the sandbox (no environment refusal at launch). Evidence: the launch itself (`envGuard` refuses a wrong project ref; A quotes the rule).
2. Sign in as the DV buyer → Home paints. Evidence: A's read-back of the `auth.sessions` row with the build's user-agent (proves URL + anon key).
3. Settings › Notifications shows no remedy banner. Evidence: A's read-back of one `push_tokens` row for this device, `is_active=true` — this is **DV-611L** on a fresh install.
4. Settings › Accessibility › Reduce Motion off → on → off: the app keeps working. VoiceOver on → off once.

**Block 1 — no-window rows (≈60–75 min), in this order; per row record PASS / FAIL / UNTESTED + the exact on-screen text.**
| Order | Row | Do | PASS when |
|---|---|---|---|
| 1 | DV-101 | Home → tap a card | title, venue, date, price painted immediately; Buy now / Bid disabled until the fresh row lands |
| 2 | DV-107 | scroll Home, open a listing, back | same scroll position and filters |
| 3 | DV-103 + DV-T | Tickets tab, leave and return; Explore, search then refresh; then the Build 16 Tickets empty-state procedure | previous content stays; no full-page spinner on refocus |
| 4 | DV-106 | open a listing whose image 400s (fixture P1/D7/D8) | branded fallback in the reserved frame, no white flash |
| 5 | DV-201 | tap stepper keys, quick-add chips, a seller row | 0.98 compress on every control |
| 6 | DV-203 (no-window part) | save Your scene; submit a report | "Saving…" / "Sending report…" beside a spinner; button width does not jump |
| 7 | DV-204 | airplane mode ON: toggle a notification preference; pick an area in Your scene; tap Done; then ONE "Sign out" tap | toggle reverts with the inline notice; chips roll back with the notice; Done waits ("Saving…") and stays; **sign out: record what happens** (known limitation: on build 17 an offline sign-out may silently do nothing) → airplane mode OFF |
| 8 | DV-208b | edit a listing, change a field, swipe back; Report, choose a reason, swipe back | "Discard changes?" / "Discard this report?"; Keep stays, Discard leaves |
| 9 | DV-206 | Reduce Motion ON | sheets and stack transitions cross-fade; spinner is the static mark; every state change still visible → OFF |
| 10 | DV-206b | VoiceOver ON, repeat row 6 | pending label read; rollback notices announced → OFF |
| 11 | DV-208 | largest accessibility text size | CTAs reachable; sticky prices/buttons do not clip; long names wrap → default size |
| 12 | DV-609 | create a listing, quantity 2 | "$X for all 2 tickets", no "per ticket" |
| 13 | DV-605 | from a cold start, open a deleted listing's id (A supplies the link) | "Listing not found" + "Browse live listings" lands on Home, no dead Back |
| 14 | empty/failed/filtered states | airplane mode ON: Home, Explore, Bids, Tickets; then OFF; filters with no match; the empty-account tab | "couldn't load" offline, "No matches" filtered, empty state only when truly empty, never during load |
| 15 | DV-611C | kill and relaunch the app while signed in | A read-back: `register_push_token` called on relaunch, outcome `refreshed` |
| 16 | DV-611 | Sign out (online) | A read-back: this device's row `is_active=false`, `revoked_reason='signed_out'` (129 is on the sandbox, so the verb path is live); login screen shows NO "expired" notice |
| 17 | DV-607a | sign in again; A invalidates the session server-side while the app is backgrounded; foreground | login shows "Your session expired. Sign in to pick up where you left off." |
| 18 | DV-611S | sign in as the DV seller on the same device | A read-back: outcome `rebound` (same device secret, new account) — the RPC path is live on this sandbox, so the legacy 23505 case does not apply; record the outcome observed |

Exit: every row has a result; a FAIL on a money or privacy row blocks the candidate; a presentation FAIL is logged and triaged. Block 2/2b need A's serialized sandbox window and follow in session 2.

### Sandbox state and the rows it blocks (A, 2026-09-15 evening)
Applied on the sandbox: 124, 125. 126 stopped (the sandbox never received 110–120, so it lacks the `ops` schema;
admin-only, no effect on the app). **127 and 128 not applied; 129 and 130 wait on the owner's window
extension.** Consequences for Friday: **DV-L1 / DV-L2** (need 127 + the two edges) and **DV-611 L/S/R/C** (need
128 + 129) cannot run until the owner rules and A resumes; every other Block 1, 2 and 2b row is unaffected. If the
ruling comes after Thursday's build, those rows run later in the same build (no code change is needed for them);
if it never comes this week, they are reported UNTESTED with this reason, not skipped silently.

### Block 3 — only if the owner authorises 128 on the sandbox
DV-611R registration/refresh/rebind/recovery outcomes per the frozen contract.

### Explicitly not closed by this candidate
Populated native Tickets (issuance disabled, CFT-801) and D9c (no further attempts) stay UNTESTED; the deferred Premium items stay in the backlog.

### Evidence and exit
Per row: PASS / FAIL / UNTESTED, the on-screen text observed, and A's read-back where marked. A FAIL on a money or privacy row blocks the candidate; a FAIL on a presentation row is logged and triaged (fix on the sprint branch → A re-integrates → re-run that row only). Exit: every Block 1 and Block 2 row has a result; UNTESTED rows carry their reason.

## 3. Time budget (deadline-backward)
- Fri 09-18 (owner, 2026-09-15: handset verification and corrections only): Block 0 (15 min) → Block 1 (≈60–75 min) → Blocks 2/2b in A's SBX-2 window (≈90–120 min) → Block 3 if 128 is on the sandbox; corrections only for a failing row (fix → A re-integrates → re-run that row); packet inputs from C by EOD (results, limitations, restart instructions).
- Thu 09-17: A's pin by midday → candidate checks on the pin (fresh `tsc` / `vitest` / lint counts, `envGuard` sandbox ref, `eas.json` `preview` profile diff vs Build 16, expected build number) → EAS preview build submitted (owner O-2) → install on the handset Thu evening.
- Wed 09-16: 128 rebind to the frozen contract (2–4 active hours) + tests; C-4 rebase started on A's Wed integrated head, finished on the pin.
- Tue 09-15: candidate-recovery slice landed and reviewed (error/empty/failed states, cancelled listing in Bids, expired-session notice, not-found outcome); gates green.
- Mon 09-14 (now): this plan; sprint branch open.
