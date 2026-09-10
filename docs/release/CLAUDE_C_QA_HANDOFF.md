# Handset QA handoff — sandbox preview build

Owner of this document: release integration. Owner of the testing: Claude C.
Date: 2026-09-10. **Sandbox only. No production action is authorized by this handoff.**

## 1. The build

| | |
|---|---|
| Build ID | **`aeb89616-a539-4e42-a5fa-bb7c46beb0e8`** |
| Source SHA | **`9aae63fa2c9f062c8097c9876710499cd6e814a0`** |
| Profile / distribution | `preview` / internal (ad-hoc), iOS |
| App version / build number | 1.0.0 (13) · Expo SDK 54 |
| Expo fingerprint | `e6e8156ee8874deb3061d77e1ebf6fad25ddc951` |
| Status | finished 2026-09-09 02:17:30 |
| Build page (install from here) | https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/aeb89616-a539-4e42-a5fa-bb7c46beb0e8 |
| Direct artifact | https://expo.dev/artifacts/eas/IhTyI686t7hQynfBbcDkVsYSHSRMH20sUi-c8qJoO3Q.ipa |

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

## 2. What is in the build, and what is not

The build was produced from `9aae63f`. The release head has since moved to `7986711`. **The build does not
contain those later commits** — but nothing executable differs between them:

| Check | Result |
|---|---|
| Commits `9aae63f..7986711` | 2, both `docs(release)` / `docs(pfa18c)` |
| Files changed | 3, all `docs/release/*.md` |
| `src/`, `app/`, `supabase/`, `scripts/`, `assets/`, `components/`, `hooks/`, `constants/`, `tests/` | **0 files changed** |
| `package.json`, `package-lock.json`, `eas.json`, `app.json`, `babel.config.js`, `metro.config.js`, `tsconfig.json` | **all unchanged** |
| Expo fingerprint recomputed at `7986711` | `e6e8156ee8874deb3061d77e1ebf6fad25ddc951` — **identical to the build's** |

The fingerprint covers the native project, the JS entry graph, dependencies and build config; an identical
fingerprint means no build input changed. So QA results from this binary describe `7986711`'s executable
behaviour, even though the binary was cut at `9aae63f`. **Do not describe the build as containing `7986711`.**

## 3. Compiled environment evidence (read from the shipped IPA, not from `eas.json`)

Extracted from `Payload/SnatchIt.app/main.jsbundle` (Hermes bytecode):

| Check | Result |
|---|---|
| Supabase URLs in the bundle | **exactly one** — `https://ofaidukbieeekqaboscm.supabase.co` |
| JWTs in the bundle | **exactly one**, decoding to `ref = ofaidukbieeekqaboscm`, `role = anon` |
| Stripe publishable key | `pk_test_51T6Fb1Gl…` → sandbox account **`acct_1T6Fb1GlD5aqtxIw`** |
| `sk_test` / `sk_live` / `service_role` / `SUPABASE_SERVICE` | **0 matches** |
| Production ref / live account fragment | present **only** as env-guard constants — the fail-closed guard must recognise production in order to refuse it |
| Guard symbols | `ENV_GUARD_FAILURE`, `IS_SANDBOX_BUILD`, `Build misconfigured` all present |
| Sandbox marker | `SANDBOX — TEST MONEY ONLY` present once, stored **UTF-16LE** in Hermes's string table (the em dash puts it there — an ASCII `strings`/`grep` pass will not find it; both encodings were checked) |
| Feature code | `get_my_tickets` and `FilterSheet` both present |

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
