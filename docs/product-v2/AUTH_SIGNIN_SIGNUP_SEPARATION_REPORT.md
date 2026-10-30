# AUTH SIGN IN / SIGN UP SEPARATION

Front End session. Branch `frontend/stripe-network-timeout-fix`.
No backend change, no schema change, no RLS change, no migration.

---

## The rule this implements

Sign up is where the account is built. Sign in is where a returning person gets
back in as fast as possible. Everything the account needs is collected once, at
sign up, and never asked for again.

---

## What was already there (inspected before anything was written)

The architecture was inspected against the deployed database, not assumed.

| Capability | Where it already lived | Verdict |
|---|---|---|
| Phone OTP send/verify | `app/settings/verify-phone.tsx` — `updateUser({ phone })` + `verifyOtp({ type: 'phone_change' })`, 30s resend cooldown | reused verbatim |
| SMS delivery | Supabase Auth, provider `twilio_verify` | reused, no custom SMS built |
| US phone normalisation | `src/utils/phone.ts` — NANP rules, 10-digit storage convention | reused |
| Email + password sign in | `signInWithPassword`, `resetPasswordForEmail` | preserved unchanged |
| Auth error copy | `src/lib/auth/authForms.ts` — `friendlyAuthError` | preserved and extended |
| Name storage | `public.profiles.display_name` | reused |
| Phone storage | `auth.users.phone` / `phone_confirmed_at`, plus `public.profiles.phone_number` | reused |
| Gender storage | `kernel.identity_demographic.gender_identity` via `kernel.set_my_demographics(text, text)` (migration 077) | reused |

Live auth configuration read from the project's public settings endpoint:

```
external.email      true
external.phone      true            phone provider enabled
disable_signup      false
mailer_autoconfirm  true            signUp returns a session immediately
phone_autoconfirm   false           a code is always really checked
sms_provider        twilio_verify
```

Population, read as aggregates only: 19 users, 18 with an email, 3 with a phone,
2 with a confirmed phone. **Sixteen of nineteen accounts cannot use phone sign in
today.** That single number is why the email path is preserved as a first-class
way in rather than as a token fallback.

---

## SIGN IN

**Primary auth method: phone OTP.** The screen opens on the mobile number field.

```
SIGN IN

Mobile number
[ CONTINUE ]

Use email instead
```

Then the verification step:

```
VERIFY NUMBER
Code sent to ••• ••• 1234

Code
[ VERIFY ]
Resend code in 30s
Use a different number
```

### Phone OTP contract

```
signInWithOtp({ phone: '+1XXXXXXXXXX', options: { shouldCreateUser: false } })
verifyOtp({ phone: '+1XXXXXXXXXX', token, type: 'sms' })
```

The number is converted to E.164 by `toE164US()` before it can reach the
provider, using the same NANP rules the profile fields enforce, so a number that
is valid in one part of the app cannot be invalid in another.

The session is established by the provider. Nothing on the screen calls
`setSession`, `refreshSession`, or any admin surface, and a test asserts those
absences against the shipped source.

### Can an unknown phone create a user?

**No.** Every send carries `shouldCreateUser: false`. Verified live against the
project with a reserved fictional number: the provider answered

```
422  otp_disabled  "Signups not allowed for otp"
```

and created nothing. That response is classified as `unknown_account` and shown
as **"This number isn't linked to an account."** with a SIGN UP button beneath
it. The screen never reaches `signUp`, and a source guard asserts
`shouldCreateUser: true` appears nowhere in it.

This follows the provider's own behaviour rather than inventing a lookup of our
own, which is also the safest available answer on account enumeration: the app
does not probe any table to decide what to say.

### Error states

Provider errors are classified by code first and message second, because the
message text is the part that changes between provider releases. No raw provider
string, error code or system text is ever shown.

| Situation | Copy |
|---|---|
| Number has no account | This number isn't linked to an account. |
| Malformed number | Enter a valid US mobile number. |
| Number on another account | That number is already on another account. |
| Send failed | We couldn't send the code. Try again. |
| Wrong code | That code didn't match. Check the text and try again. |
| Expired code | That code expired. Send a new one. |
| Rate limited | Too many attempts. Wait a few minutes and try again. |
| Network | Connection problem. Check your signal and try again. |

Rate limiting is classified before anything else on both stages, so a throttled
resend is never reported to the person as a bad code.

### Email fallback

Preserved in full, not as a stub: email, password, **Forgot password?**, the same
`signInWithPassword` and `resetPasswordForEmail` calls, the same
`friendlyAuthError` mapping. One tap away via "Use email instead", and back via
"Use mobile number instead".

### Existing-user compatibility

An email-only account signs in exactly as it did before. Nothing forces a phone
number first: a test asserts the email sign-in handler contains no phone or OTP
logic at all. Those users can add and verify a number later through the existing
`settings/verify-phone` screen, which then makes phone sign-in work for them —
no migration, no forced re-onboarding, nothing destructive.

---

## SIGN UP

Four steps on one screen. The steps exist so seven fields do not arrive at once.

```
STEP 1  Email · Password · 18+ confirmation · Terms and Privacy
STEP 2  Name · Gender
STEP 3  Mobile number
STEP 4  Verify number  ->  CREATE ACCOUNT
```

### Why the account is created at step 1

Linking a phone to an identity and writing a profile both require a session.
`mailer_autoconfirm` is on, so `signUp({ email, password })` returns a session
immediately and steps 2 to 4 write to the real account through ordinary
contracts.

If email confirmation is ever switched back on, `signUp` returns no session; the
flow stops at a `check_email` state showing the exact message it always showed
("Account created. Check your email to confirm, then sign in.") and nothing
downstream is attempted against an account that does not exist yet.

### The onboarding gate

The root layout sends anyone with a session to Home. Because the session now
appears at step 1, the signup screen raises a flag that holds that redirect until
the flow finishes. It is released on success, on failure, and on unmount, so the
router can never be left held.

The gate changes **routing only**. A test asserts the module mentions no session,
token, role or permission, and that the layout effect it guards still only calls
`router.replace`.

### Phone verification

Real and server-authoritative, through the contract already shipped:

```
updateUser({ phone: e164 })                                   sends the code
verifyOtp({ phone: e164, token, type: 'phone_change' })       the provider checks it
```

The number becomes part of the authenticated identity (`auth.users.phone` +
`phone_confirmed_at`) — which is exactly what phone sign-in later looks up, so a
person who signs up today can sign in by phone tomorrow. Nothing in the client
marks a number verified on its own say-so, and the profile is written only after
the provider has accepted the code.

### Gender

Exactly three options, no icons, no emoji, no explanatory paragraph, built from
the existing V2 `Chip` and exposed as one accessible radiogroup.

| Shown | Stored |
|---|---|
| MALE | `man` |
| FEMALE | `woman` |
| PREFER NOT TO SAY | `prefer_not_to_say` |

Those values are the vocabulary the deployed `kernel.identity_demographic` check
constraint accepts, so no translation table and no second gender column is
introduced. A test reads the accepted vocabulary out of migration 077 and asserts
every option is in it, so a change on either side fails the build.

### Canonical storage

| Field | Canonical home | How it is written |
|---|---|---|
| Email | `auth.users.email` | `supabase.auth.signUp` |
| Name | `public.profiles.display_name` | `profiles` update scoped `.eq('id', user.id)` |
| Phone (identity) | `auth.users.phone` + `phone_confirmed_at` | `updateUser` + `verifyOtp` |
| Phone (app copy) | `public.profiles.phone_number` | same update, 10-digit normalised |
| Gender | `kernel.identity_demographic.gender_identity` | `kernel.set_my_demographics(text, text)` |

No new column, no new table, no shadow copy in device storage. The profiles write
carries exactly `display_name` and `phone_number`; a test extracts that payload
from the shipped source and asserts nothing else is in it.

The demographics RPC is SECURITY DEFINER and derives the row from `auth.uid()`,
so there is no identity argument for a client to get wrong. It was confirmed live
that `authenticated` holds USAGE on the `kernel` schema and EXECUTE on the
function, and that PostgREST routes the schema.

`notice_version` is sent as `signup-demographics/v1`, recording which privacy
notice was on screen when the person answered. The RPC rejects an empty one.

### Core blockers

**None.** Every field the owner asked for already has a deployed, owner-scoped,
front-end-reachable contract. No `AUTH_PROFILE_COMPLETION_CORE_HANDOFF.md` was
needed and none was created.

---

## Files changed

New:

- `src/lib/auth/phoneAuth.ts` — E.164, mask, cooldown, provider-error classification and copy
- `src/lib/auth/signupFlow.ts` — step machine, validation, the three gender options, canonical vocabulary
- `src/lib/auth/onboardingGate.ts` — holds the root redirect while signup finishes
- `src/components/auth/GenderSelect.tsx` — three chips, one radiogroup
- `tests/auth-phone-signin.test.ts` — the 11 sign-in requirements
- `tests/auth-signup-profile.test.ts` — the 9 sign-up requirements

Modified:

- `app/(auth)/login.tsx` — phone OTP primary, email and password preserved as the second way in
- `app/(auth)/signup.tsx` — four-step collection, real verification, canonical writes
- `app/_layout.tsx` — four lines: read the gate, return early while it is raised

Untouched: `app/(auth)/reset-password.tsx`, `app/settings/verify-phone.tsx`,
`src/lib/auth/authForms.ts`, `src/utils/phone.ts`, the auth shell and brand mark,
and every backend artefact.

---

## Verification

| | |
|---|---|
| Backend changed | NO |
| Schema changed | NO |
| RLS changed | NO |
| Migrations added | NO |
| Tests | 714 passed / 32 files (was 663 / 30) |
| Typecheck | clean, exit 0 |
| Lint | 27 problems, 0 errors, 27 warnings — no new warnings, none on any touched file |
| Native iOS bundle | HTTP 200, 14,991,802 bytes, no resolution or syntax error |
| Bundle contains the new path | `shouldCreateUser` ×7, `set_my_demographics` ×3, `PREFER NOT TO SAY`, `Use email instead`, `signup-demographics/v1` |

### Design system

The SN mark is unchanged: same asset, same 30pt height, still centred to the
screen and still pinned near the top safe area outside the keyboard-responsive
region. Both properties are re-asserted in the sign-in tests. Type, colour,
spacing and controls are the approved V2 tokens throughout; the only new visual
is the gender row, built from the existing chip.
