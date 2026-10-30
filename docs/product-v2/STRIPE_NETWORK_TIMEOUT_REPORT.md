# Checkout — CFNetwork -1001 timeout at payment-sheet presentation

**Session:** Front End · **Date:** 2026-09-04 · **Severity:** P1 (blocks purchase)
**Branch:** `frontend/stripe-network-timeout-fix` from `frontend/v2-final-integration` @ `9bc4c08`
**Status: FIXED AND VERIFIED ON PHYSICAL IPHONE (2026-09-04).** Owner confirmed the Stripe payment
sheet now loads and checkout works. No push, no deploy.

## 1. Physical iPhone symptom
Tapping **Pay $330** produced a native alert:
`Payment Failed — The operation couldn't be completed. (kCFErrorDomainCFNetwork error -1001.)`
The Stripe PaymentSheet / card-entry UI never appeared.

## 2. Previous defect vs this one
Different failures. The earlier `presentPaymentSheet(): Tried to resolve a promise more than once`
was a **UI concurrency** defect (double-tap → two presentations), fixed by the single-flight latch,
which is present in this bundle and is **not** implicated here. This one is a **configuration**
defect that surfaced as a network timeout.

## 3. Exact checkout call graph (Buy Now)
1. `Button onPress` → `payOnPress` → `handleConfirmPurchase` (`CheckoutNative.tsx`)
2. `payLatchRef.current.begin()` — synchronous single-flight latch (from the earlier fix)
3. *(already completed on mount)* `setupPayment()`:
   a. reservation pre-check — `supabase.from('listings').select(...)`
   b. `createPaymentIntent()` → `supabase.functions.invoke('create-payment-intent')` (Edge Function,
      `Authorization: Bearer <user access token>`) → returns `clientSecret`, `customerId`,
      `customerEphemeralKeySecret`, server-authoritative amounts
   c. `initPaymentSheet({ paymentIntentClientSecret, customerId, customerEphemeralKeySecret,
      merchantDisplayName, returnURL, applePay? })` → on success `setPaymentReady(true)`
4. `await presentPaymentSheet()` ← **fails here**
5. `Alert.alert('Payment Failed', …)`

## 4. Exact failing stage — proven, not inferred
The alert text appears at exactly two places (`CheckoutNative.tsx:335` and `:401`), both immediately
after `await presentPaymentSheet()` returns an error. Two independent facts place the failure there:
- The button read **“Pay $330”**. `payControl` only returns `action:'pay'` with that label when
  `paymentReady === true`, and `paymentReady` is set **only** after `initPaymentSheet` returns without
  error. Had the Edge Function or `initPaymentSheet` failed, the screen would show the inline
  `SAFE_PAYMENT_ERROR` and the button would read **“Try again”** — no alert at all.
- The failure path that produces an `Alert` exists nowhere else in the checkout screen.

So: `create-payment-intent` **succeeded**, `initPaymentSheet` **succeeded**, and
`presentPaymentSheet` failed at the network layer.

## 5. Root cause
`.env` held the Stripe publishable key wrapped in **smart quotes**:

```
EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY=‘pk_live_…’      ← U+2018 … U+2019
```

dotenv strips a matching pair of **straight** quotes (`"` or `'`) but **not** curly ones. Byte-level
evidence from the file (values never printed):

| Variable | First char | Last char | Result |
| --- | --- | --- | --- |
| `EXPO_PUBLIC_SUPABASE_URL` | U+0022 `"` | U+0022 `"` | stripped → **loaded correctly** |
| `EXPO_PUBLIC_SUPABASE_ANON_KEY` | U+0022 `"` | U+0022 `"` | stripped → **loaded correctly** |
| `EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY` | **U+2018 `‘`** | **U+2019 `’`** | **not stripped → malformed** |

The app therefore booted with a literal `‘pk_live_…’` (109 chars = 107-char key + 2 curly quotes).
This explains every observation:
- The key was **non-empty**, so the existing empty-key guard never fired and nothing was logged.
- The **Supabase** vars were straight-quoted, so the Edge Function call worked — which is why the
  PaymentIntent was created and the failure looked like it was "deep" in Stripe rather than config.
- `initPaymentSheet` accepted its parameters locally, so `paymentReady` became true.
- Only when the sheet actually loaded did the SDK authenticate to `api.stripe.com` with a malformed
  key; that request never completed and surfaced as `kCFErrorDomainCFNetwork -1001`
  (`NSURLErrorTimedOut`) with no indication that configuration was at fault.

## 6. Evidence trail
- Alert origin: `CheckoutNative.tsx:335,401`, both after `presentPaymentSheet()`.
- Gate: `payControl.ts:39` (`paymentReady` ⇒ label `Pay …`), `CheckoutNative.tsx` `setPaymentReady(true)`
  only after the `initPaymentSheet` error check.
- Env: codepoint dump of `.env` (above).
- Bundle before fix: an injected value beginning with a curly quote.
- Bundle after fix: `"EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY": { enumerable: true, value: "pk_live_…"` —
  a clean straight-quoted literal. `sk_` secret keys in bundle: **0**.

**Elapsed time before failure:** not measured on device. The root cause was established statically
with the evidence above, so no temporary device instrumentation was added — `-1001` is
`NSURLErrorTimedOut`, i.e. the iOS default request timeout elapsed.

## 7. Environment verification
- `EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY`: **present**, mode **LIVE** (`pk_live_`), prefix now **valid**.
- Supabase URL + anon key: present, correctly quoted, valid `https://` project host.
- **No `sk_` secret key anywhere in the client or bundle.**
- All three worktrees (`integration`, `home`, `phase0`) share one `.env` (identical hash; the first two
  are symlinks), so there is no per-worktree env divergence and the repair applies everywhere.

### Stripe mode
Client is **LIVE**. The backend reads `STRIPE_SECRET_KEY` from a Supabase Function secret
(`supabase/functions/create-payment-intent/index.ts`), which is deliberately **not** in the repo, so
backend mode is **UNKNOWN from the client** and a mismatch can be neither confirmed nor excluded here.
A mode mismatch is *unlikely* to be the cause: it produces an authentication/invalid-request error
rather than a timeout, and `initPaymentSheet` accepted the live-mode client secret.

> ⚠️ **Operational note:** this is a **live** key. A completed checkout on the device is a **real
> charge**. Cancel at the sheet unless a real payment is intended.

## 8. Backend / endpoint verification
- Function `create-payment-intent` **exists** in `supabase/functions/` and is invoked via
  `supabase.functions.invoke` with the user's access token — correct project, correct auth.
- **No** `localhost`, `127.0.0.1`, `192.168.`, `10.`, `ngrok`, tunnel or `DEV_API`/`BASE_URL` host
  anywhere in the payment path (asserted by test).
- The Edge Function demonstrably responded (the PaymentIntent existed), so it was not the timeout
  source. It was not invoked directly from this machine, because doing so needs a real user session
  and would create a live PaymentIntent — deliberately avoided.

## 9. Implemented fix
1. **`.env` repaired** (local, not committed; timestamped backup kept): the key is re-quoted with
   straight quotes. Value never printed.
2. **`src/config/envValue.ts` (new)** — `envValue()` trims whitespace and one matching pair of
   wrapping quotes, straight **or** curly, so a pasted-with-smart-quotes value can never reach the SDK
   again. Plus `looksLikeStripePublishableKey()` and `stripeKeyMode()` (shape only).
3. **`src/config/app.ts`** — `STRIPE_PUBLISHABLE_KEY` now goes through `envValue()`.
4. **`NativeAppShell.native.tsx`** — a key that is *present but malformed* now logs a precise
   developer error **at boot**, naming smart quotes as the likely cause. The dangerous silent case is
   gone; the value is never logged.
5. **`src/lib/checkout/paymentErrors.ts` (new)** + both alert sites — the customer sees
   `Payment connection timed out. Try again.` (or a generic line) instead of
   `kCFErrorDomainCFNetwork error -1001`; the raw SDK code/message goes to `console.warn`.

The timeout was **not** increased: the endpoint/credential was wrong, and that was corrected.

## 10. Files changed
`src/config/envValue.ts` (new) · `src/config/app.ts` · `src/providers/NativeAppShell.native.tsx` ·
`src/lib/checkout/paymentErrors.ts` (new) · `src/screens/checkout/CheckoutNative.tsx` (two alert
sites only) · `tests/payment-env.test.ts` (new) · this report. Local `.env` repaired (not committed).

## 11. Core-owned files changed
**None.** `supabase/**`, `payments.ts`, `money.ts`, `supabase.ts`, `packages/**`, `scripts/**`,
`.github/workflows/**`, `app.json`, `eas.json` untouched. Payment architecture, PaymentIntent
creation, fees, all-in amount and money logic unchanged. No secret moved client-side, no auth weakened.

## 12. Reservation behaviour preserved
Untouched. Release is wired **only** to navigation exit (`beforeRemove` on the listing), never to a
payment failure — asserted by test (`CheckoutNative` contains no `release_reservation`). A failed
payment initialisation leaves the hold and its remaining timer intact; `Checkout → Listing` keeps it;
`Listing → Home` still releases once via the existing RPC. No fresh 10-minute timer is started.

## 13. Verification
- Tests: **651 passed / 29 files** (+14). New coverage: smart/straight quote stripping, malformed-key
  rejection, sanitise-then-validate end to end, CFNetwork copy mapping (and that no raw code reaches
  the customer), `presentPaymentSheet` gated behind a successful init, payment failure never releases
  the reservation, and no localhost/tunnel host in the payment path. Existing latch tests retained
  (rapid taps → one presentation; cancel/error release the latch; retry works).
- Typecheck: clean (exit 0). Lint: 27 problems, **0 errors, 27 warnings** — no new warnings.
- iOS bundle: **HTTP 200, ~14.65 MB**, cache cleared; injected key is a clean straight-quoted
  `pk_live_…` literal; 0 `sk_` keys.

## 14. Physical-device status
**VERIFIED (2026-09-04).** After restarting Metro on 8081 with `--clear` from the integration worktree
(served bundle confirmed to carry a clean `pk_…` literal), the owner reported: *"stripe sheet loads
now, checkout works."* The payment sheet presents and the checkout flow completes.

Confirmed by this pass: the CFNetwork -1001 defect is resolved and `presentPaymentSheet` succeeds.
Not separately confirmed in the owner's words: the rapid-tap duplicate-presentation case (the earlier
single-flight latch). No red screen was reported, and the latch is present in the verified build.

Operational reminder that caused the original confusion: **Metro inlines `EXPO_PUBLIC_*` at bundle
time**, so any server started before an `.env` change keeps serving the old value until it is
restarted with `--clear`.

---

# SIGN IN LOGO ALIGNMENT

Small isolated UI correction bundled with this branch (unrelated to the timeout defect).

## Issue
The SN mark on **Sign in** sat at the top **left**, which no longer matched the approved Home header.
Inspection showed there was **no shared auth header**: `login`, `signup` and `reset-password` each
inlined the same `<Image>` as a bare child of a column (`inner: { flex: 1, paddingHorizontal: lg,
justifyContent: 'center' }`), so the mark hugged the left edge on **all three** screens, byte-identically.

## Change
Extracted one shared `src/components/auth/AuthBrandMark.tsx` and pointed all three screens at it. The
mark is the **sole child of a full-width, `alignItems: 'center'` row** — the same construction the
approved Home header uses, so it is mathematically centred to the **screen** and cannot be pushed by a
sibling. No absolute offsets, and the surrounding `paddingHorizontal` is symmetric.

Preserved exactly: the asset (`brand/sn-logo-white.png`), the size (30pt tall with the 1024×371 ratio
pinned so it can never squash), the `marginBottom` spacing beneath it, and the screens' existing
safe-area/top spacing (`KeyboardAvoidingView` + `inner` untouched). No background, plate, wordmark,
glow or red treatment was added.

## Scope
Diff across the three screens is **6 insertions / 12 deletions** — the component swap plus removal of
the now-dead `SN_MARK` const, `mark` style and `expo-image` import. **Zero** lines touching
`supabase.auth`, sign-in/sign-up handlers, inputs, buttons, validation or navigation.

## Test
`tests/auth-brand-mark.test.ts` — the mark is centred by a full-width centred row and is that row's
only child; the construction matches the Home header; asset, size and ratio unchanged; no plate/glow/
red treatment; and each of the three screens renders `<AuthBrandMark />` with the old left-aligned
inline copy gone.

## Result
| Item | Result |
| --- | --- |
| Sign In SN centered | **YES** |
| True screen centering | **YES** (full-width centred row, not leftover space) |
| Logo asset changed | NO |
| Logo size changed | NO |
| Other Sign In UI changed | NO |
| Auth behavior changed | NO |
| Shared auth screens affected | `login`, `signup`, `reset-password` (all three were left-aligned; now share `AuthBrandMark`) |

Verification after this change: **658 tests / 30 files**, tsc clean, lint 27 problems / 0 errors /
27 warnings (no new), iOS bundle HTTP 200.

## Follow-up: the mark also MOVED with the keyboard
Device review found a second, related defect: with no field focused the mark sat low, and focusing
Email/Password slid it up. Cause: the mark lived inside
`KeyboardAvoidingView > View{flex:1, justifyContent:'center'}` **together with the form**, so that
container vertically centred the whole block; when the keyboard shrank the available height the centred
block — mark included — rode upward.

Fixed by restructuring, not by keyboard offsets. New shared shell
`src/components/auth/AuthScreen.tsx`:

```
SCREEN
├── fixed brand header      ← OUTSIDE the KeyboardAvoidingView; insets.top + space.xl
│   └── centred SN mark
└── KeyboardAvoidingView
    └── ScrollView (flexGrow:1, centred, keyboardShouldPersistTaps)
        └── title, fields, forgot, button, sign-up link
```

The header cannot move because nothing keyboard-related wraps it, and it is positioned from the
safe-area inset plus a spacing token — no hardcoded Y for one device. The form keeps its previous
centred composition when there is room and now scrolls when the keyboard takes the space, so every
control stays reachable. All three screens (`login`, `signup`, `reset-password`) had the identical bug
and now share the shell; their own `KeyboardAvoidingView`/`inner` containers are gone.

Diff scope: **13 insertions / 30 deletions** across the three screens plus the mark component, with
**zero** lines touching auth calls, inputs, buttons, validation or navigation. Typography, field
underlines, the red Sign In button, Forgot-password placement and the Sign-up link are untouched.

Tests extended (`tests/auth-brand-mark.test.ts`): the mark is emitted **before** the
`KeyboardAvoidingView` opens (so it is outside it); the header uses `insets.top + space.xl` and no
absolute/hardcoded Y; only the form body carries `justifyContent:'center'`; the form keeps
`KeyboardAvoidingView` + `keyboardShouldPersistTaps` + `flexGrow:1`; and no auth screen retains its own
keyboard/centring container.

Verification: **663 tests / 30 files**, tsc clean, lint 27 problems / 0 errors / 27 warnings (no new),
iOS bundle HTTP 200.
