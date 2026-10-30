# AUTH + PHONE VERIFICATION PATHS — COMPLETE AUDIT

Branch `frontend/auth-verification-paths-fix`, based on
`frontend/stripe-network-timeout-fix` at `215aba1`.
No backend change, no schema change, no RLS change, no migration.

---

## The reported bug, and what it actually was

Signed in, Settings → Phone verification → enter number → the SMS arrives → the
app jumps to Home instead of showing the code field.

**No OTP screen was at fault.** All three advance their own step correctly on a
successful send. The root layout pulled the person away.

```
app/_layout.tsx  (before)

  useEffect(() => {
    if (loading) return;
    if (isRecovery) return;
    if (onboarding) return;
    if (session) { …; router.replace('/(tabs)/home'); }   // line 88
    else        { …; router.replace('/(auth)/login'); }
  }, [session, loading, isRecovery, onboarding]);
                ^^^^^^^ the session OBJECT
```

`src/hooks/useAuth.ts` calls `setSession(newSession)` on **every**
`onAuthStateChange` event. Supabase hands a fresh session object to events that
are not sign-ins: `USER_UPDATED` and `TOKEN_REFRESHED` both carry one.

So the exact chain was:

```
tap Send code
  -> supabase.auth.updateUser({ phone })      Twilio sends the SMS
  -> Supabase emits USER_UPDATED with a session
  -> useAuth setSession(new object)
  -> the effect's `session` dependency changed identity
  -> `if (session)` is true
  -> router.replace('/(tabs)/home')
```

The screen had already called `setStep('enter_code')`. It was simply unmounted
underneath.

**This was never only a phone-verification bug.** `TOKEN_REFRESHED` fires on the
same path roughly hourly and on every app foreground, so the same line would
throw anyone out of any screen and back to Home. That never got reported because
nobody was watching for it. Password recovery was already exempt only because the
`isRecovery` flag happened to hold, and sign up only because the onboarding gate
happened to hold. Every other in-app flow was exposed.

---

## The fix: navigate on authentication PHASE, not on session identity

`src/lib/auth/rootRoute.ts` (new, pure):

```ts
type AuthPhase = 'signed_out' | `signed_in:${userId}`
```

Signed out is one phase. Signed in as a given person is another. A refreshed
token, a changed phone, a changed password, changed metadata — none of those
change the phase, so the root layout does not move. Signing out of one account
and into another does change it, so that still routes.

`rootRouteDecision()` is the layout's whole navigation policy as one pure
function: hold while loading, hold during recovery, hold during signup, then
navigate **only when the phase differs from the phase last navigated for**.

Two deliberate properties:

- **A hold never records a phase.** When the hold lifts, the boundary is
  evaluated honestly, so signup still lands on Home after it completes.
- **Nothing branches on event names.** The routing code reads phase, never
  `event === '…'`, so an event Supabase adds later cannot cause a stray redirect.
  The event classification is exported as documentation and asserted in tests.

The layout now also separates the two concerns it had conflated: Sentry identity
reporting updates on every session change, navigation only on a boundary.

---

## Inventory: every reachable auth / OTP path

| # | Route | Context | Supabase call | OTP type | Advances on send | Completes to |
|---|---|---|---|---|---|---|
| 1 | `app/(auth)/login.tsx` phone | logged out | `signInWithOtp` `shouldCreateUser:false` | `sms` | `setStep('enter_code')` | Home, via the signed_out → signed_in boundary |
| 2 | `app/(auth)/login.tsx` email | logged out | `signInWithPassword` | n/a | n/a | Home, same boundary |
| 3 | `app/(auth)/login.tsx` forgot | logged out | `resetPasswordForEmail` | n/a | n/a | stays on Sign in |
| 4 | `app/(auth)/signup.tsx` step 1 | logged out → in | `signUp` | n/a | `setStep('about')` | held by the onboarding gate |
| 5 | `app/(auth)/signup.tsx` step 3 | logged in, mid onboarding | `updateUser({ phone })` | `phone_change` | `setStep('verify')` | step 4 |
| 6 | `app/(auth)/signup.tsx` step 4 | logged in, mid onboarding | `verifyOtp` | `phone_change` | n/a | writes, then releases the gate → Home |
| 7 | `app/settings/verify-phone.tsx` | **logged in** | `updateUser({ phone })` | `phone_change` | `setStep('enter_code')` | code step |
| 8 | `app/settings/verify-phone.tsx` | **logged in** | `verifyOtp` | `phone_change` | n/a | **back to Settings / Create listing** |
| 9 | `app/(auth)/reset-password.tsx` | recovery session | `updateUser({ password })` | n/a | n/a | sign out → Sign in |
| 10 | `NativeAppShell.native.tsx` deep link | logged out | `verifyOtp({ token_hash })` / `exchangeCodeForSession` | email types | n/a | recovery screen, or the boundary |

Entry points to verification: Settings → Phone verification, and Create listing's
"Verify phone" prompt. **Both reach the same single screen. There is no stale
second copy of the flow.**

`app/(tabs)/_layout.tsx` has no auth guard, `app/(auth)/_layout.tsx` is a bare
Stack, and the settings routes are top-level in the root Stack, not inside the
auth group. So the root effect was the only thing that could have caused this,
and it was.

---

## Two further corrections in the same screen

**Return destination.** Done previously called `router.back()` unconditionally.
It now goes through `leaveVerification()`, which falls back to `/settings` when
there is nothing to pop rather than assuming the stack. It returns the person
where they started, from either entry point, and never to Home.

**Profile phone sync.** The screen wrote `auth.users.phone` but never the app's
`public.profiles.phone_number`, so a number verified in Settings did not appear
where Sign up and Edit profile put it. It is now written — **only after
`verifyOtp` succeeds**, never on the send. Same column, no second copy, no new
mechanism. Sending an SMS is not verification and records nothing.

---

## Results

### Auth events

| Event | Navigates? | Correct |
|---|---|---|
| `INITIAL_SESSION` | once, on first settle | YES |
| `SIGNED_IN` | on the boundary | YES |
| `SIGNED_OUT` | on the boundary | YES |
| `TOKEN_REFRESHED` | **no** | YES |
| `USER_UPDATED` | **no** | YES — this was the bug |
| `PASSWORD_RECOVERY` | held by `isRecovery` | YES |

### Flows

| Flow | Send | Advances to OTP | Verify gates completion | Destination |
|---|---|---|---|---|
| Phone sign in | YES | YES | YES | Home |
| Email sign in | n/a | n/a | n/a | Home |
| Forgot password | YES | n/a | n/a | stays on Sign in |
| Sign up | YES | YES | YES | Home, only after the writes |
| Settings phone verification | YES | **YES — fixed** | YES | **Settings** |
| Phone change | YES | YES | YES | Settings, session preserved |
| Unknown phone | refused | n/a | n/a | stays on Sign in, nothing created |

Resend on all three OTP screens reuses the same send handler, keeps the step,
never navigates, never changes OTP type, and never creates a user. Every error
state — wrong code, expired code, rate limit, send failure, network, unknown
account — returns before any step change, so nobody is dropped out of a flow by a
provider error.

---

## Files changed

New:
- `src/lib/auth/rootRoute.ts`
- `tests/auth-verification-paths.test.ts`

Modified:
- `app/_layout.tsx` — navigation split from identity reporting; routes through the decision
- `app/settings/verify-phone.tsx` — routing contract documented, safe return destination, post-verification profile sync
- `tests/auth-signup-profile.test.ts` — two assertions restated against the new policy

Untouched: Sign in and Sign up presentation, the auth shell, the SN mark, Home,
AdaptiveDock, Stripe, Checkout, reservations, money, tickets, and every backend
artefact.

---

## Verification

| | |
|---|---|
| Tests | **754 passed / 33 files** (was 715 / 32) |
| Test matrix | all 44 numbered cases covered |
| Typecheck | clean, exit 0 |
| Lint | 27 problems, 0 errors, 27 warnings — no new, none on any touched file |
| Native iOS bundle | HTTP 200, 14,998,606 bytes, no resolution or syntax error |
| Bundle contains the fix | `rootRouteDecision` ×3, `same_phase`, `leaveVerification` |
| Backend / schema / RLS | unchanged |

---

## Physical iPhone test plan

**A — Phone sign in.** Logged out. Number → Continue → code arrives → enter it →
Home.

**B — Email sign in.** Logged out. "Use email instead" → credentials → Home.
Check "Forgot password?" still sends its email.

**C — Sign up.** New account through all four steps. Confirm it does **not** jump
to Home after step 1, that the code step appears after the number is sent, and
that Home comes only after the code is accepted.

**D — Settings phone verification (the reported bug).** Signed in → Settings →
Phone verification → number → Send code. **The code field must appear and stay.**
Enter the code → back to Settings, not Home.

**E — Resend.** One resend each in A and D, after the 30 second cooldown. The
control stays disabled until the timer runs out, and the code field never leaves.

**F — Token refresh, the latent bug.** Leave the app open on any screen other
than Home for over an hour, or background and foreground it. It should stay put.
Before this change it would have jumped to Home.

Ready for the device pass.
