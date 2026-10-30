# Handset QA handoff — sandbox preview build

Owner of this document: release integration. Owner of the testing: Claude C.
Date: 2026-09-10. **Sandbox only. No production action is authorized by this handoff.**

## 1. The build

| | |
|---|---|
| Build ID | **`66be8872-163a-43c6-99ed-71de752f5f16`** |
| Source SHA | **`df9e0d3718086907faeff538fbba5b62bae38a1e`** |
| Includes D5 fix | `a8adfb1` (3-D Secure return) on `9196123` (runtime crypto) on `aa8c8b3` (AEAD + re-entry) |
| Profile / distribution | `preview` / internal (ad-hoc), iOS |
| App version / build number | 1.0.0 (**16**) · Expo SDK 54 |
| Expo fingerprint | `1fa6c2581671dcc071e11986c9886e431181ed51` |
| Status | finished 2026-09-10 16:12:58 |
| Build page (install from here) | https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/66be8872-163a-43c6-99ed-71de752f5f16 |
| Direct artifact | https://expo.dev/artifacts/eas/91gB3Xc7VDODq_ndzv_e1xSVrec2x74fGGgA5fF_iqY.ipa |

> **This build supersedes builds 13, 14 and 15.** Delete the old app before installing. Build 14 crashed at cold
> launch (`ReferenceError: Property 'crypto' doesn't exist`) and must not be used; build 13 predates the D5
> fixes.

### Install

1. Open the **build page** above **on the iPhone** (Safari). Scanning the QR code on that page from the
   desktop build page works too.
2. Tap **Install**, then confirm the iOS install prompt. The app appears on the home screen as *Snatch It*.
3. First launch: Settings → General → VPN & Device Management → trust the developer certificate if iOS asks.
4. Confirm the persistent **`SANDBOX — TEST MONEY ONLY`** badge is visible. If instead you get a full-screen
   **"Build misconfigured"** screen, stop and report the `F1`…`F8` code it prints — that is the environment
   guard refusing a wrong Supabase/Stripe pairing.

**Device restriction.** This is an ad-hoc build. It installs **only** on devices in the provisioning profile —
currently one: UDID `00008130-000E59801198001C`. Any other handset will fail to install and needs registration
plus a rebuild first.

**Credentials.** Sign in with the sandbox buyer. The password is in the local `scripts/sandbox/sandbox.env`;
never paste it into chat. Stripe test cards: success `4242 4242 4242 4242` · 3-D Secure `4000 0025 0000 3155` ·
decline `4000 0000 0000 0002`.

## 2. What is in the build

Cut from the release head `187e69e`, so unlike build 13 there is no source/head gap. It carries the D5
repair merged from `frontend/d5-3ds-return-and-session` at `aa8c8b3`, whose full lineage
(`8f94cda → a050125 → ceda719 → 5a6e6ad → aa8c8b3`) was reviewed rather than only the final commit.

| Change | Effect on QA |
|---|---|
| 3-D Secure return URL now `snatchit://checkout/<listingId>` | the completed challenge returns to the checkout screen instead of expo-router's unmatched/sitemap screen |
| `app/checkout/index.tsx` floor for a bare link | redirects Home and asserts no payment outcome |
| Settled-purchase resolution before the reservation pre-check | re-entry after a completed charge renders the settlement state; **"Your reservation has expired" is unreachable once a payment succeeded** |
| v3 session blob — XChaCha20-Poly1305, fresh 24-byte nonce per write | the torn-write session loss is closed and the blob is now authenticated |
| Typed storage outcomes | a transient Keychain/AsyncStorage error leaves the ciphertext intact instead of deleting a recoverable session |
| `AppState.currentState` gates the initial refresh | the refresh loop follows the foreground |

**Root-cause wording, stated carefully.** The **torn-write mechanism is supported** by the storage evidence
and by the server-side record: `auth.audit_log_entries` is empty and `auth.refresh_tokens` shows the three
2026-09-10 sessions each holding one token with zero revocations and zero rotations — a silent client-side
loss with no expiry, failed refresh or sign-out ever reaching the server. **Token expiry remains conditional**
on the sandbox `jwt_exp` value, which has not been read; it is a contributing hypothesis, not an established
fact. The missing AppState refresh wiring is retained as a **latent defect**, separate from the reproduced
storage defect, and is not claimed as the D5 cause.

## 3. Compiled environment evidence (read from the shipped IPA of build 14)

Extracted from `Payload/SnatchIt.app/main.jsbundle` (Hermes bytecode), not from `eas.json`:

| Check | Result |
|---|---|
| Supabase URLs in the bundle | **exactly one** — `https://ofaidukbieeekqaboscm.supabase.co` |
| JWTs in the bundle | **exactly one**, decoding to `ref = ofaidukbieeekqaboscm`, `role = anon` |
| Stripe publishable key | `pk_test_51T6Fb1Gl…` → sandbox account **`acct_1T6Fb1GlD5aqtxIw`** |
| `pk_live_51T6Far` (production account) | **0 matches** |
| `sk_test` / `sk_live` / `service_role` / `SUPABASE_SERVICE` | **0 matches** |
| Sandbox marker | `SANDBOX — TEST MONEY ONLY` present once (UTF-16LE in Hermes's string table) |
| D5 fix compiled in | `xchacha20poly1305` ×1, `poly1305` ×2, `v3.` ×1, `snatchit://checkout/` ×1, `already_settled` ×1, `sessionCipher: undecryptable` ×1 |
| Bundle identity | `com.jdt-inc.snatchit`, `CFBundleShortVersionString` 1.0.0, `CFBundleVersion` **14** |
| Install links | build page HTTP **200**; artifact HTTP **307** (signed redirect to the IPA) |

Metro bundling of the new dependency was proven before the build: a local
`expo export --platform ios` produced a Hermes bundle containing `xchacha20poly1305` and `poly1305`, and a
Node round-trip confirmed the AEAD (5-byte plaintext → 21 bytes with the Poly1305 tag). `@noble/ciphers`
2.4.0 is a runtime `dependency` in both `package.json` and `package-lock.json`.

## 4. Sandbox server-side state Claude C is testing against

Project **`ofaidukbieeekqaboscm`**. Ledger **129** rows.

| Check | Result |
|---|---|
| `20260909000000` in the ledger | yes, name `kernel_my_tickets_read`, exactly one row |
| `public.get_my_tickets` | exists, `pronargs = 0`, `SECURITY DEFINER`, `search_path=public, pg_temp`, `stable` |
| EXECUTE grants | `authenticated` ✔ · `anon` ✘ · `PUBLIC` ✘ |
| Authenticated caller owning no tickets | `POST /rest/v1/rpc/get_my_tickets` → **HTTP 200, body `[]`** |
| Anonymous caller | **HTTP 401**, `42501 permission denied for function get_my_tickets` |
| `kernel.tickets` rows | 0 — the Tickets screen must render its empty state, not an error |
| Migrations `110`–`120` | **not applied** in the sandbox (see §5) |

## 5. Deployed sandbox edge versions, and the mismatches that matter

Nine edge functions are deployed to the sandbox, all at version 3, deployed 2026-09-07T16:05:29Z from
repo commit `e9a9b1a`:

`create-payment-intent` · `confirm-payment` · `confirm-and-release` · `enforce-transfer-expiry` ·
`delete-account` · `notify-report` · `stripe-webhook` · `create-connect-account` · `send-push`

**Source parity: clean.** Every one of those nine is **byte-identical in source** between the deployed commit
`e9a9b1a` and the release head `7986711`. The only `_shared` change in that range is `offline-verify.ts`, which
is imported solely by `door-manifest` and `credential-sign` — neither deployed anywhere. **No source mismatch
invalidates the payment cases.**

Three deviations from production that QA must know about:

| Deviation | Effect on QA |
|---|---|
| **`notify-transfer` is not deployed** to the sandbox (excluded by `scripts/sandbox/10_provision.sh`). The DB trigger `notify_transfer_event()` fires `net.http_post` at the **sandbox** URL, which returns 404 and is fire-and-forget. | Transfer-progress **push/notification delivery will silently not happen** in the sandbox. Payment, settlement, payout and listing-state behaviour are unaffected. Do not raise a bug for a missing transfer notification; do not use the sandbox to sign off push routing. |
| **`auto-finalize-auctions` is not deployed.** | Auction finalization does not run. The staged QA listings are buy-now, so cases D1–D11 are unaffected. Do not test auction endings here. |
| **`verify_jwt = false` on all nine sandbox functions**, versus `true` in production for eight of them (`stripe-webhook` is `false` in both, correctly). | The platform-level JWT gate is off. Every payment edge still enforces auth itself — each reads the `Authorization` header and calls `auth.getUser(token)`, returning 401 — so an unauthenticated call is still rejected, just one layer later than production. Happy paths are faithful. **Do not sign off "edge rejects unauthenticated callers" from the sandbox**; that assertion needs production parity. |

**Sandbox is not repointed at production.** A read-only check of every sandbox DB function containing
`http_post` found **zero** targeting `hqycwntpfoztoinemqns`; four target the sandbox project and one targets
neither. No sandbox action can reach a production endpoint.

## 6. Ground rules while Claude C is testing

- The sandbox must stay stable: no further migrations, no edge redeploys, no schema changes until QA reports.
- Sandbox money is Stripe **test mode** only. No live key exists in this build.
- Report per case: case number, what you saw, and the time — server-side truth is checked afterwards against
  `payments`, `transfers`, `listings` and the deletion state.
