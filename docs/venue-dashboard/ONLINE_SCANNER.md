# The online phone-web scanner (venue app) — operator runbook and record

Branch `venue/online-scanner` (F, 2026-10-26). Contract: `planning/2026-10-26-launch/CONTRACTS.md` C7 and A's P8 amendment of 2026-10-26 (staff-session path). Nothing in this document is a new rule; where the server does not yet exist (D's 163) the page says so.

## 1. What it is

One page in the venue dashboard, `/o/<org>/v/<venue>/events/<event>/scan`, for a staff member's own phone browser. The staff member signs in to the venue app, picks the session, gives the phone a label, grants the camera, and points it at the guest's pass. Each decoded pass is sent once to the server's admission verb under the staff member's own session, and the screen shows the server's answer as one of five words:

| Word | Meaning | Colour |
|---|---|---|
| ADMITTED | the server recorded this pass as admitted for THIS scan (command key) | green |
| ALREADY USED | the server already holds an admission for this pass (after B's 183: with the time and the phone label of the first one) | amber |
| WRONG EVENT | the pass's own session claim is not the selected session; never sent | red |
| INVALID | the server refused it (183 reasons: refunded/cancelled, expired, not active, listed and locked, an old version of the pass, unknown ticket), or the verifier refused it before the call (not a pass, another credential type, not signed by a trusted key, past its expiry) | red |
| CANNOT VERIFY | offline, no answer, scanning not enabled on this project, session not admitting, rate-limited, server error, or demo mode. Never an admission. | neutral |

Refusals decided on the phone (WRONG EVENT, a stale or unreadable pass, offline) never reach the server and are not in `venue.scan`; the counts strip's "refused by the server" counts server refusals only (E review F-R2). A pass counts as stale only 5 minutes past its own `exp`, so a phone clock slightly ahead does not refuse valid passes (F-R5).

Rules the code enforces (`venue/src/lib/scan/*`, tested in `venue/tests/scan-*.test.ts`):

- One attempt in flight at a time. Frames decoded while an attempt is in flight are ignored. The same decoded code is not re-sent for 6 s after it was seen or answered.
- A green is only ever the server's `result='admitted'` for the command key the screen sent. A timeout, a transport failure or an unknown answer is CANNOT VERIFY with a **Check again (same key)** button; the retry re-sends the SAME command key, so the server can only answer `duplicate` (after 183, with `prior`) or, today, `invalid` which the screen resolves through `validate_ticket_online` (state `scanned` → ALREADY USED, flagged "possibly this phone's previous attempt").
- ADMITTED clears after 2.5 s, refusals after 8 s, CANNOT VERIFY only by a tap: a person decides.
- Known offline (`navigator.onLine === false`) is CANNOT VERIFY before anything is sent. There is no offline queue; offline admission is out of scope for the pop-up (CONTRACTS C7).
- Signed out (session expired) and no role (42501) block the screen and stop the camera; sign in again or ask a manager for the `venue_scanner` role.
- No manual code entry, no override, no re-entry on this screen. An exception is a person's decision at the door and is recorded by the manager (see §5), never typed into the scanner as an admit.
- The camera reads a pass. It does not verify age or identity. The 21+ ID check stays with the person at the door.

## 2. Server surface the page uses (D's 163, dark until exposed)

| Call | Used for | Until it exists |
|---|---|---|
| `venue_cmd.record_scan(p_atom_id, p_session_id, p_scan_meta, p_command_key)` | the admission | PGRST106 / PGRST202 → CANNOT VERIFY "Scanning is not enabled on this project yet" |
| `venue_cmd.validate_ticket_online(p_atom_id, p_session_id)` | resolving a server `invalid` into ALREADY USED vs INVALID | the server's own word (INVALID) is shown |
| `venue_api.session_admissions` | the per-session counts strip (admitted / already used / refused, last admitted at) | "Attendance counts are not available on this project yet." (never zero) |

`scan_meta` carries exactly `{device_label (≤64, no identity), credential_version, key_id}` (B §4 allow-list; D's wrapper refuses anything else) and **never `occurred_at`** on the online path: the server writes `now()` into `venue.scan.occurred_at` (108 would otherwise coalesce a client value, and `last_admitted_at` reads it), so a phone clock can never set the ledger's time (E review F-R1). Never a device id (the staff path is actor-attributed; `auth.uid()` is the actor).

**Verification before the call (B's TICKET-CREDENTIAL-CONTRACT-v1 §3, implemented in `venue/src/lib/scan/verify.ts`, run inside the server action):** decode (the reference decoder, vendored in `wire.ts` and proven equal to `supabase/functions/_shared/offline-verify.ts` on every golden token) → `typ` → algorithm whitelist → `kid` in the trusted keyring → key status and window → algorithm pin → public-key normalization (`keys.ts`, vendored) → ES256/EdDSA signature over the exact signed bytes with WebCrypto → session binding → expiry with the reference tolerance (2 × 30 s) on the SERVER clock. The keyring is the `kernel.signing_key` public projection (column grant 083:114 + 103:95, policy `kernel_signing_key_sel_public`), read per scan under the staff session with the nine granted columns named (`kms_handle_ref` is fenced). `tests/scan-verify.test.ts` runs all 19 golden vectors through it with the fixture's real keys: every signature/key/session/expiry refusal matches the reference's reason; what only a manifest could refuse passes here and is the server's. A refusal renders INVALID ("not signed by a trusted Snatch It key", "out of date", "not a Snatch It pass") or WRONG EVENT; a keyring that cannot be read is CANNOT VERIFY (retryable). Nothing here admits; the security boundary stays the server (B §4).

## 3. Browser and camera support (what was checked, what was not)

- The page is the only route whose `Permissions-Policy` allows `camera=(self)` (`venue/next.config.ts`, pinned by `tests/scan-headers.test.ts`). The CSP is unchanged: the browser talks only to the venue app's own server actions.
- Decoding: the browser's `BarcodeDetector` when it exists and reports `qr_code` (feature-detected at run time), otherwise **jsQR 1.4.0** (Apache-2.0, no dependencies, 280 KB unpacked, loaded only on this page via a dynamic import). Added as an exact dependency after checking: no existing QR library anywhere in the monorepo, licence permissive, pure JavaScript (works wherever `getUserMedia` and canvas work), the smallest of the candidates (`qr-scanner` 524 KB MIT, `html5-qrcode` 2.6 MB Apache-2.0, `@zxing/browser` 5.8 MB MIT).
- The symbol the camera must read (C, 2026-10-26, `planning/2026-10-26-launch/C/evidence/qr-renders/`): a real token is ~349 characters → QR version 14–15 at error-correction M, drawn up to 320 pt wide on the phone (≈ 4 pt per module) with a 4-module quiet zone, black on white. Frames are decoded at up to 640 px wide; hold the phone 15–25 cm from the screen, screen brightness up.
- The camera needs https and a user tap (iOS). In-app browsers (Instagram, Facebook, some mail apps) often refuse the camera: open the page in Safari or Chrome.
- **Not yet proven on hardware.** No real phone camera has scanned a real pass on this branch. The unit tests prove the decoder, the outcome map and the state machine; a simulator is not camera proof. §6 is the checklist for the first two-phone run.

## 4. Staff onboarding (what a manager does before doors)

1. Each door person has their own venue-app account (email + password; no shared logins). A manager grants `venue_scanner` at the venue (`venue.grant_staff_role(venue, identity, 'venue_scanner', key)`; a manager account can also scan). Org owner/admin accounts cannot scan unless they also hold a venue role: the server refuses them.
2. On the phone: open `https://<venue host>/o/<org>/v/<venue>/events/<event>/scan`, sign in, pick the session, type the phone's label (for example `Door A phone`), tap **Start scanning**, allow the camera. Bookmark the page.
3. Dry run with a test pass before doors. Watch the result strip read ADMITTED once, then ALREADY USED on the second scan.
4. Keep the phone on a charger or a battery pack; the camera is the biggest drain.

## 5. Spare device, hotspot and exceptions

- **Spare phone:** sign in on a second phone with the same steps and label it differently (`Door A spare`). Any signed-in scanner account can take over at any time; there is no device binding on this path.
- **Hotspot:** if the venue Wi-Fi drops, tether the scanner phones to one hotspot phone. While offline the screen says CANNOT VERIFY and nothing is admitted on the phone's word.
- **Pass shows CANNOT VERIFY twice:** tap **Check again (same key)** once the connection is back. If it stays, move the guest aside, keep the line moving with the spare phone, and let a manager decide. The manager records the decision (who, what pass, why) in the door log; the scanner never gets an override button.
- **Guest's pass is out of date (INVALID · stale):** ask them to open the pass again in the Snatch It app; it re-issues every few hours. A screenshot does not refresh.
- **ALREADY USED:** the pass was admitted before (the strip says when and from which phone once 183 lands). Do not re-admit on the phone. A manager decides with the guest.
- **21+:** the ID check is a person's task; the camera result says nothing about age.

## 6. Two-phone checklist (for E / Jose, first real-camera run on the sandbox)

Preconditions: sandbox exposure of `venue_cmd`/`venue_api` (A, P6), 163 applied (D), a published test session with one issued pass (C/A), two phones with scanner accounts, the venue app preview in database mode pointed at the sandbox.

| # | Step | Expect |
|---|---|---|
| 1 | Phone A: sign in, pick the session, label `Door A phone`, Start scanning, allow camera | status chip "Ready"; counts strip reads "no scans recorded yet" (not zero-by-default) |
| 2 | Phone A scans the buyer's pass | ADMITTED (green), clears after ~2.5 s; "1 admitted from this phone"; counts strip updates |
| 3 | Phone A keeps the same pass in frame | nothing is re-sent for 6 s; afterwards ALREADY USED (amber) |
| 4 | Phone B scans the same pass | ALREADY USED; after 183: "Already admitted at HH:MM (Door A phone)" |
| 5 | Phone B scans a pass for another session | WRONG EVENT (red), no server call |
| 6 | Phone B scans a random QR (a URL) | INVALID · "not a Snatch It pass" |
| 7 | Phone A: airplane mode, scan a fresh pass | CANNOT VERIFY · offline; nothing admitted; airplane mode off → Check again (same key) → the server's answer |
| 8 | Phone A: lock the phone 30 s, unlock | camera resumes by itself or by one tap; no stray result |
| 9 | Manager revokes Phone B's `venue_scanner` role; Phone B scans | blocked "This account cannot scan here"; camera stops |
| 10 | Sign Phone A out in another tab; scan | blocked "Signed out" with a Sign in again link |
| 11 | Refund the pass (sandbox), scan it on Phone A | INVALID · "Not valid for this session" |
| 12 | Read the counts strip on both phones | identical numbers; equal to the venue.scan rows for the session |

Record browser (Safari/Chrome + version), phone model, and whether `BarcodeDetector` or jsQR decoded (the chip does not say; E can read it from the network tab: jsQR loads a chunk named `jsqr`).

## 7. Known limits on this branch

- No hardware proof yet (§3). No sandbox proof yet: `venue_cmd` is dark everywhere; P6/163 pending.
- Times are shown in the phone's zone in database mode until D's 162 venue timezone lands; the page says so.
- `prior` on the staff path can only name what B's 183 carries (actor label and, if D passes `scan_meta` through, the phone label).
- Verification runs in the venue app's server action with the staff session (B §3, option c); the keyring is read per scan (B: refresh per scanning session; a per-page-session cache is a later optimisation once the two-phone run gives p95 figures, E F-R4).
