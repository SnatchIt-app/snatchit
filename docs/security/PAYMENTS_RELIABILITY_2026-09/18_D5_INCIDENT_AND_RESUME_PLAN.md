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

## Cause 2 — session loss: what is confirmed and what is not

**Confirmed from the sandbox auth log and `auth.sessions`:**
- three `password` logins 17:38:31 / 17:42:57 / 17:45:30; **zero** refresh grants
- **zero** `/logout` calls in the window
- each session: one refresh token, **none revoked**, `refreshed_at` null
- the access-token lifetime (1 h) could not have elapsed in the 9-minute window

So the server never saw an expiry, a failed refresh, a revocation or a sign-out.
Whatever signed the buyer out happened **entirely on the device, silently**.

**Withdrawn as the D5 cause:** "the token expired unrefreshed". The missing
`AppState` auto-refresh wiring is a **real latent defect** (`startAutoRefresh`
appeared nowhere) and stays fixed in `8f94cda`, but the timeline rules it out as
what happened here. `useAuth`'s stale-token `signOut()` path is also ruled out —
it would have produced a `/logout`.

**Leading HYPOTHESIS, structurally supported, not device-confirmed:** a torn
write in `LargeSecureStore`. It minted a new AES key on every write and stored
it in the Keychain *before* the blob reached AsyncStorage. A suspend or relaunch
between those two writes — the 3-D Secure handoff, the deep-link relaunch — left
key N+1 against blob N; the next `getItem` failed to decrypt and **deleted the
session locally with no server call**. That is the only mechanism found that
matches every server-side observation. Hardened in this branch by reusing one
key per storage key (tested). Confirmation needs a device artefact: the
`[secureStorage] decrypt failed; clearing entry` warning in a Sentry breadcrumb
or device log from the D5 session.

`Home` showing "sandbox buyer" while `Buy Now` refused: both read `useAuth()`,
so this was stale rendered profile text, not a disagreement between guards.

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
