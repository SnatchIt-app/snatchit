# D5 incident — financial truth, causes, and the resume plan

Build `aeb89616-a539-4e42-a5fa-bb7c46beb0e8` (source `9aae63f`, 1.0.0/13).
Sandbox `ofaidukbieeekqaboscm`. All evidence gathered read-only; nothing changed.

## Financial outcome — CONFIRMED, one charge, no duplicate

| | |
|---|---|
| Payment row | `4e474177` succeeded, total 11000, livemode false, refunded null |
| PaymentIntent | `pi_3UEC35GlD5aqtxIw137x9h4p` succeeded, `amount_received` 11000 |
| Charge | `ch_3UEC35GlD5aqtxIw1QMTwFAC` paid, captured 11000, refunded 0, disputed false |
| Listing `Device D4` | sold 17:47:07Z, holds released |
| Transfer | one, `73f83823` pending, payout withheld |
| Stripe intents last 4h (whole account) | 3; exactly 1 charged. The two browser refreshes made no attempt |

**Device D4 must not be repaid.** Its status is recorded as: handset flow failed, single payment settled.

## Cause 1 — CONFIRMED: return URL to a route that does not exist

`returnURL: 'snatchit://checkout'`; `app/checkout/` had only `[id].tsx`; no
`+not-found`. The completed challenge deep-linked into expo-router's default
unmatched (sitemap) screen — the reported "404". Fixed in `8f94cda`.

## Cause 2 — session loss: confirmed, corrected, and still open

**Confirmed (sandbox `auth.sessions` / `auth.refresh_tokens`, corroborated by
Claude A's independent read):** the three sessions created 17:38 / 17:42 /
17:45 each hold one refresh token, zero revoked, zero rotations. **The refresh
loop never ran.** No `/logout` was received.

**Corrected statement of the visible chain (per review item 5).** The earlier
wording "the app read the failure as a stale token and signed the buyer out" is
withdrawn: `useAuth` signs out only on `Invalid Refresh Token` / `Refresh Token
Not Found`, no token on those sessions was revoked, and no sign-out reached the
server. The supported chain is: the access token was no longer usable on return,
`getSession()` yielded **no session and no error**, and `useAuth`'s else-branch
set the session to null. Nothing signed anyone out; the client simply had no
session to show. `Buy Now` then correctly refused (`user?.id` null) while Home
kept stale profile text. Worth stating positively: the stale-token phrase list is
narrow, so transient network failure was never treated as revocation, and this
branch does not change that.

**Still open — why was the token unusable inside nine minutes?** Two candidate
mechanisms; neither is device-confirmed:

- *A's reading:* the access token expired while the app was backgrounded behind
  the 3-D Secure browser, and with the refresh loop stopped nothing renewed it.
  Sufficient **only if the sandbox access-token lifetime is well under nine
  minutes**; that setting could not be read from here (connector dropped
  mid-investigation). If `jwt_exp` is the 3600 s default, expiry alone does not
  fit the window.
- *Torn-write in `LargeSecureStore`* (hardened in `a050125`; the stable key it
  introduced reused the CTR keystream — closed with a random IV per write and a
  legacy read path in the follow-up commit): a fresh AES key
  written to the Keychain before the blob reached AsyncStorage; a suspend between
  the two leaves an undecryptable blob, and `getItem` clears it locally. Fits
  every server-side fact including the missing refresh grant. Confirmed only by a
  device artefact: the `[secureStorage] decrypt failed; clearing entry` warning
  in Sentry breadcrumbs or a device log from the D5 session.

Both fixes ship regardless, and they are separate defects: the refresh-loop
wiring is a latent defect (not the D5 cause); the storage adapter is the
reproduced-symptom path. The store now (a) returns null and keeps the ciphertext
when the Keychain or AsyncStorage is transiently unavailable, clearing only on a
missing key or a failed authentication, and (b) writes v3 XChaCha20-Poly1305
(@noble/ciphers, nonce per write) so tampering, truncation and a wrong key all
fail cleanly; v2 and legacy blobs are read and migrated, never deleted. Which one *caused* D5 is settled by `jwt_exp`
plus the breadcrumb, not by argument.

**Re-entry (review item 1, blocking) — CONFIRMED and fixed in this commit.** The
return URL lands on `checkout/[id]`; a remount ran the reservation pre-check
first and reported "Your reservation has expired" for a listing that was sold
*because this buyer paid*, and auction mode would have created a second intent.
`decideCheckoutSetup` now asks "already settled?" before anything else, renders
the completed settlement, and creates/initialises/presents nothing; two rapid
re-entries share one in-flight setup. Covered behaviourally with mocked
dependencies (tests/checkout-setup-reentry.test.ts).

## Build 14 cold-launch crash — CONFIRMED, fixed

Sentry `19d8d967a00043a59a889fe8e7dfa3b3`, 2026-09-10 18:41:47Z, sandbox:
`ReferenceError: Property 'crypto' doesn't exist`, before sign-in.

Cause: build 13's `secureStorage.ts` opened with
`import 'react-native-get-random-values'`, the polyfill that installs
`crypto.getRandomValues` on Hermes (SecRandomCopyBytes). The rewrite to a thin
binding dropped it. First write after launch — the legacy→v3 migration of the
build-13 blob during session restore — reached `randomBytes()` and the undefined
global. Not at module load; `@noble/ciphers` never touches the global.

Fix: the polyfill is the binding's first import again and the source is handed
to the store explicitly (`random` dep); the cipher and store read no global on
any write path, and a missing source fails with a typed error at wiring time.
Covered by a suite that runs with `globalThis.crypto` deleted: cold launch,
sign-in write, relaunch restore, the exact build-13→14 legacy migration, v2
migration, background/foreground refresh, Keychain and AsyncStorage unavailable,
tampered ciphertext, plus source guards on import order. Hermes itself cannot
run under vitest; the device pass on the next build is the final proof.

## Re-pinned baselines (read 2026-09-10 ~18:05Z)

| Listing | ID | Status | Payment rows | Live intent |
|---|---|---|---|---|
| Device D1 | `086dd027` | active | 2 (`79d37964` failed, `14a762bb` pending `pi_3UEC0D…`) | 1 |
| Device D2 | `9c6eecd4` | active | 1 (`f7762166` pending `pi_3UDGM3…`, Sept 8) | 1 |
| Device D3 | `5b9052c7` | active | **1** (`e569d654` pending `pi_3UEC4o…`, 17:47:58Z, unreported) | 1 |
| Device D4 | `f46feafe` | **sold** | 1 succeeded | — |
| Device D5 | `7ff98ba1` | active | **0** | 0 |
| Phone P1 | `c343406e` | active | 1 (`3a546cf3` pending, Sept 8) | 1 |
| Phone P2/P3 | — | sold | 1 succeeded each | — |

Only **Device D5** is clean. Pass conditions from here are judged on the
invariant — at most one `succeeded` payment and one captured charge per listing
— never on raw row counts.

## Replacement-build checks (before the matrix resumes)

1. **Identity.** EAS `gitCommitHash` equals the merge commit containing
   `8f94cda`; `appBuildVersion` > 13; profile `preview`; sandbox pair.
2. **3-D Secure return** (R1). On a clean listing, complete a challenge: the app
   returns to `checkout/[id]` and shows success; **no** sitemap/404; one intent,
   one charge.
3. **Background/foreground** (R2). Signed in, background the app ≥ 3 min, return:
   still signed in; a refresh grant appears in the auth log; no password login.
4. **Order recovery** (R3). Open Device D4 and Orders: sold, order present — the
   D5 payment surfaces without any repayment.
5. **Relaunch persistence** (R4). Force-quit, cold-start: buyer still signed in,
   no `[secureStorage] decrypt failed` warning, no new password login in the log.
6. **Callback re-entry** (R5, with Claude A). A bare `snatchit://checkout` and a
   stale `snatchit://checkout/<sold-id>` must land somewhere real and claim no
   outcome.

Resume order after R1–R5 pass: D6 on Device D3 (baseline 1 pending intent),
D7, D8 on Device D5, D9 on Phone P1, D10, D11, T, F.
