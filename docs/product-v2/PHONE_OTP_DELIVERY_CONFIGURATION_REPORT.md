# PHONE OTP DELIVERY — CONFIGURATION REPORT

> **Redacted for publication.** The Twilio Account SID that appeared in this table has been replaced with
> `AC_REDACTED_TWILIO_ACCOUNT_SID`. The real identifier lives only in the Twilio console and in local history.

Front End session. Branch `frontend/stripe-network-timeout-fix`.
No backend change, no schema change, no RLS change, no migration.
No credential value appears anywhere in this document.

---

## Symptom

Physical iPhone. A valid Miami mobile number is entered on Sign in, CONTINUE is
tapped, and the screen returns:

> We couldn't send the code. Try again.

No SMS arrives.

---

## Root cause

**The Twilio account behind Supabase Auth is not active. Twilio rejects the
request at authentication, before any message is ever created.**

Read from the project's own Auth logs, three attempts at 22:10:05, 22:10:44 and
22:10:46 UTC on 2026-09-06, all identical:

```
path        POST /otp
status      422
error_code  sms_send_failed
error       422: Error sending confirmation OTP to provider: authentication
            failed, account AC7c9****** with status 4 is not active
            More information: https://www.twilio.com/docs/errors/20003
auth_event  { action: user_confirmation_requested, traits: { provider: phone } }
```

That tells us four things precisely:

1. The request reached Supabase Auth and was accepted. Phone auth is on.
2. Supabase Auth **did** contact Twilio. Credentials are present and the account
   is recognised by SID.
3. Twilio refused with error **20003**, and named the reason: the account is
   **not active** (suspended or closed).
4. Nothing about the number, the geography or the message content was ever
   evaluated. The call died at authentication.

This is not a frontend defect, not a Supabase misconfiguration, and not a
rate limit. It is an account-state problem on the Twilio side.

An earlier line in the same log window, from a deliberate probe with a reserved
fictional number, returned `otp_disabled` / "Signups not allowed for otp" —
confirming the non-creating sign-in path behaves correctly and separately.

---

## Configuration state

Read from the deployed project at runtime, not from the repository.

| Item | State |
|---|---|
| Phone auth enabled | **YES** (`external.phone: true`) |
| SMS provider | **Twilio Verify** (`sms_provider: twilio_verify`) |
| Phone autoconfirm | **OFF** (`phone_autoconfirm: false`) — codes are really checked |
| Email auth | enabled, unaffected |
| Signups | enabled (`disable_signup: false`) |
| Account SID configured in Supabase | **YES** — Twilio identified the account by SID in its refusal |
| Auth token configured in Supabase | **YES** — a missing token gives a different 20003 shape; this one names the account and its status |
| Verify Service SID configured | **PRESUMED YES**, not directly observable. Supabase would fail earlier with a different error if the Verify service reference were absent; it cannot be confirmed without dashboard access |
| Messaging Service SID | **NOT REQUIRED** for the Twilio Verify provider |

Because the provider is **Twilio Verify**, Supabase requires Account SID, Auth
Token and a Verify Service SID. It does **not** need a Messaging Service SID or a
purchased sender number. No second messaging system should be created.

---

## What could not be inspected, and why

**Twilio Console: not inspected.** Chrome is connected and reachable, but
`console.twilio.com` presented a sign-in screen. Authenticating on the owner's
behalf is out of bounds, so the browser session was stopped there and the tab
closed. Nothing was typed into any credential field.

**Supabase dashboard: not inspected.** The Authentication → Providers page did
not render for automation, and reaching it would likewise have required signing
in.

Everything reported above therefore comes from the runtime: the public auth
settings endpoint, the project's Auth logs, and the database. Those sources are
authoritative for the failure; they cannot tell us the Twilio plan tier, whether
the Verify service still exists, or the geo-permission table.

| Question | Answer |
|---|---|
| Twilio account exists | **YES** — Twilio resolved the SID and reported its status |
| Twilio account type (trial / paid) | **UNKNOWN** — needs console access |
| Verify Service exists | **UNKNOWN** — moot while the account is inactive |
| Verify Service active | **UNKNOWN** — moot while the account is inactive |
| US SMS geo allowed | **NOT REACHED** — the call failed at authentication, before geography was considered |
| Trial recipient restriction blocking the test | **NO** — a trial restriction produces error 21608 on a message that was actually attempted, not a 20003 account-status refusal |
| Rate limit encountered | **NO** — all three attempts returned `sms_send_failed`; no `over_sms_send_rate_limit` appears anywhere in the window |

---

## Test number, and a second finding

`(786) 201-7279`, normalised to `+17862017279`:

| | |
|---|---|
| Linked to an existing auth user | **YES** |
| Phone confirmed | **NO** (`phone_confirmed_at` is null) |

So the "couldn't send the code" message is case **B — a real delivery failure**,
not a misclassified unknown-account response. Supabase found the user and raised
`user_confirmation_requested`; only the SMS leg failed.

**Second finding, worth acting on separately.** The user record holding that
number is a stale one: created 2026-02-19, phone-only identity, never signed in,
no email, no password-bearing email account attached, an empty profile row, and
never confirmed. It is not the account that signs in by email.

The consequence: **once Twilio is alive, signing in with that number will
succeed into that empty February record, not into the owner's real account.**
Nothing has been deleted or altered — removing an auth user is destructive and is
the owner's call. Options, when the SMS path works again:

- delete the stale record, then add and verify the number on the intended
  account through Settings → Phone verification; or
- keep it and use a different number for the intended account.

---

## Owner action required

**YES. This is a billing or support action on Twilio and cannot be done from
here.**

Exactly what needs to happen, in order:

1. Sign in to the Twilio Console and open the account whose SID begins `AC7c9045`.
2. Check its status. Error 20003 with "status 4 is not active" means the account
   is suspended or closed. Typical causes: a trial that lapsed, an unpaid
   balance, or a compliance or verification hold.
3. Reactivate it. If Twilio asks for a payment method, a balance top-up, or an
   upgrade from trial, **that is the approval decision** — no payment, upgrade,
   number purchase or subscription was made here.
4. While in the console, confirm the Verify service used by Supabase still exists
   and is active, and that Geo Permissions allow United States (+1). Both are
   unverifiable until the account is usable.
5. If the account cannot be recovered and a new Twilio account is created, the
   new Account SID, Auth Token and Verify Service SID must be entered in Supabase
   under Authentication → Providers → Phone. Those values belong only there.

Nothing else is blocking. The moment Twilio authenticates, both OTP paths should
work with no code change.

---

## Both code paths are blocked by the same cause

Sign in uses `POST /otp` (`signInWithOtp`). Sign up and Settings use the phone
change path (`updateUser({ phone })` then `verifyOtp({ type: 'phone_change' })`).
Supabase Auth routes both through the same configured SMS provider, so both fail
identically today and both are expected to recover together. Neither could be
tested end to end: sending more attempts at a dead provider proves nothing and
only risks a rate-limit block on the number for later, genuine testing.

---

## Frontend

**The classifier is already correct.** The real response — `sms_send_failed`,
HTTP 422 — maps to `send_failed`, which is exactly the copy the device showed:
"We couldn't send the code. Try again." That matches the specified mapping for a
real SMS send failure, and it is correctly distinct from the unknown-account
message. No behaviour needed fixing.

One test was added to pin that: the observed provider payload (SID redacted) is
now a fixture asserting it classifies as `send_failed`, is not treated as a
missing account, and that the account SID, the provider's name and the status
code never reach the person's screen. This prevents a future classifier edit from
quietly turning a real delivery outage into "This number isn't linked to an
account", which would send people to create duplicate accounts during an outage.

| | |
|---|---|
| Runtime source changed | **NO** |
| Test added | one case in `tests/auth-phone-signin.test.ts` |
| Sign In UI / OTP UI / Sign Up UI | unchanged |
| Home, Checkout, Stripe, reservations, money | untouched |
| Backend, schema, RLS, migrations | unchanged |
| Tests | 715 passed / 32 files |
| Typecheck | clean, exit 0 |
| Lint | 27 problems, 0 errors, 27 warnings, no new |
| Native iOS bundle | unchanged from `d2430b5` (a test file is not bundled) |

---

## Architecture confirmation

Unchanged and correct:

```
iPhone  ->  Supabase Auth  ->  Twilio  ->  SMS
```

The app holds no Twilio credential of any kind. Nothing Twilio-related exists in
`EXPO_PUBLIC_*`, in the client bundle, or in the repository. The mobile client
never contacts Twilio directly. Twilio credentials live only in the Supabase Auth
provider configuration.

---

# ADDENDUM — TWILIO CONSOLE INSPECTED DIRECTLY

Console inspected read-only through the owner's own signed-in Chrome session.
Nothing was changed, purchased, enabled or sent. No credential value was read or
recorded. A parallel documentation review of Twilio error 20003 ran alongside,
with no console access.

## Account identity: it is the right account, and it is not a subaccount

| | |
|---|---|
| Console account SID | `AC_REDACTED_TWILIO_ACCOUNT_SID` |
| SID in the Supabase error | `AC_REDACTED_TWILIO_ACCOUNT_SID` |
| Match | **exact** |
| Friendly name | "My first Twilio account" |
| Parent / subaccount | **standalone parent** — the billing group contains exactly one account, which is this one |

A parent/subaccount credential mismatch is a documented cause of 20003. It is
ruled out: there is no second account.

## Status and the reason for it

The console header carries a **Suspended** badge.

The reason is on the billing page, and it is mundane:

| | |
|---|---|
| Balance | **−$3.20** |
| Billing type | **Pay-as-you-go** — a real paid account, **not a trial** |
| Auto-recharge | **not set up** |
| Payment method on file | Visa ending 8410, expires 12/2030 — valid, not expired, name and billing address present |
| Payments in September 2026 | none |
| Bill history | $3.37 Feb · $3.32 Mar · $3.30 Apr · $3.30 May · $3.30 Jun · $3.30 Jul · **$0.00 Aug · $0.00 Sep** |

The picture is unambiguous. A small recurring monthly charge of about $3.30 ran
from February through July. The prepaid balance was consumed, auto-recharge was
never enabled so nothing topped it up, the balance crossed zero to −$3.20, and
Twilio suspended the account. Billing stops dead in August, which is exactly when
the service went dark. Twilio then refuses every API call with 20003, and
Supabase relays it as `sms_send_failed`.

**The card on file was never charged, because auto-recharge was never turned on.**
This is not a declined card or an expired card. It is an empty balance with no
mechanism to refill it.

## Verify service: exists, correct, and not the problem

| | |
|---|---|
| Verify service exists | **YES** |
| Friendly name | **Snatch It** |
| Service SID | `VA2bcedf20dd459667a954ee11727a77c9` |
| Enabled channel | **SMS** |
| Last updated | 2026-07-09 |

Exactly one service. No duplicates. Nothing needs creating.

## US delivery: allowed

Read from SMS Geo Permissions: **2 of 237 countries are enabled — United States
(+1) and Canada (+1).** Everything else is off, which is a deliberate and correct
US-only posture for a Miami launch.

## What the documentation rules out

Twilio publishes distinct error codes for the other candidate causes, and none of
them is 20003:

| Candidate cause | Error Twilio would actually return | Ruled out |
|---|---|---|
| Trial account, unverified recipient | **21608** | YES |
| Trial rate limit on Verify | **60624** | YES |
| Messaging geo permission block | **21408** | YES |
| Verify geo permission block | **60605** (HTTP 403) | YES |
| Wrong Verify Service SID | 20404 / 60200 class | YES |

Twilio's own 20003 page lists "Account is suspended or closed" as a documented
cause. That is what the console shows. The account-status clause in the message
also proves Twilio resolved the SID to a real account and rejected on state, not
on credential shape, so the Account SID and Auth Token held by Supabase are
functionally correct.

`status 4` itself has no public definition anywhere in Twilio's documentation;
the published account status enum is only `active` / `suspended` / `closed`. The
console's own "Suspended" badge resolves it.

## The one open question

The Verify Services page carries Twilio's banner:

> To send messages to any recipient, upgrade your account and add an approved
> Primary Compliance Profile

An unapproved Primary Compliance Profile is **also** a documented cause of 20003.
It is not possible to tell from outside whether this banner is a generic notice
shown because the account is suspended, or a second gate that will still block
delivery once the balance is positive. Trust Hub would answer it, but that page
returns no content while the account is suspended.

**Practical consequence:** funding the account is required either way. If SMS
still fails afterwards with 20003 or 21608, the compliance profile is the next
step and costs nothing to submit.

## Not verified

- **The Verify Service SID stored in Supabase.** The Supabase dashboard does not
  render for browser automation, and signing in was out of bounds. It cannot be
  confirmed that Supabase holds `VA2bcedf20dd459667a954ee11727a77c9`. This is not
  the current blocker: a wrong Service SID produces a Verify 20404/60200 error,
  not an account-status 20003. Worth a glance once SMS is flowing.
- **The exact minimum top-up amount.** The Add funds dialog would not open under
  automation. Twilio's console presents its own minimum at that point.

## Corrective action, pending owner approval

**Nothing was done. This is the action to approve.**

1. **Add funds to the Twilio balance.** Enough to clear −$3.20 and go positive.
   This charges the Visa ending 8410 already on file. Twilio's documented
   reactivation time once the balance is above zero is 5 to 10 minutes.
2. **Optional, recommended: enable auto-recharge.** At roughly $3.30 a month, the
   same silent suspension will happen again otherwise, and next time it will
   happen to live users signing in rather than to a test.
3. **If SMS still fails after funding**, submit the Primary Compliance Profile in
   Trust Hub. Free, but it needs business details and takes review time.

No plan upgrade is needed. The account is already pay-as-you-go, the Verify
service already exists, the geo permissions are already correct, and no phone
number needs buying for Verify.

## Testing still outstanding

None of this has been exercised. After funding, still to prove:

1. Sign in OTP: `signInWithOtp` to a number linked to an account, SMS arrives,
   `verifyOtp` establishes a session, the app opens.
2. Resend after the 30 second cooldown.
3. Sign up / add phone: `updateUser({ phone })` sends a `phone_change` code, and
   `verifyOtp` confirms it. Same provider, but a different Supabase code path.
4. The stale phone-only user from 2026-02-19 still holds the test number, so a
   successful phone sign-in with it lands in that empty record. Untouched, as
   instructed.

One controlled send, to a number of the owner's choosing, on the owner's word.

---

# POST-FUNDING VERIFICATION

Inspection only. No OTP was sent, no auth record was changed, no billing setting
was touched, and no application code was modified.

## Twilio, after funding

| | |
|---|---|
| Account status | **Active** — the console badge that read "Suspended" now reads Active |
| Balance | **+$16.80** |
| Month-to-date spend | **$1.15** — billing has resumed, which is independent proof the account is live again |
| Auto-recharge | **still OFF** |
| Account SID | unchanged, still the one Supabase uses |

The suspension is cleared. The original blocker is gone.

**Auto-recharge recommendation, not executed.** Usage has been about $3.30 a
month. A sensible setting is a trigger around $10 with a recharge around $20:
roughly six months of runway per top-up, and the balance never crosses zero
unattended. Left OFF pending approval, as instructed. Worth doing before launch,
because the next silent suspension lands on real users signing in rather than on
a test.

## Supabase Auth, re-checked live

| | |
|---|---|
| Phone auth enabled | **YES** |
| SMS provider | **Twilio Verify** |
| `phone_autoconfirm` | **FALSE** — codes are still really checked |
| `mailer_autoconfirm` | TRUE, unchanged |
| Signups | enabled |
| `shouldCreateUser` on the Sign in path | **FALSE**, unchanged in source |

Nothing drifted. Nothing needed changing.

## Verify service

Still present and correct: friendly name **Snatch It**, SMS channel enabled,
one service, no duplicates.

**The Primary Compliance Profile banner is still on that page**, now alongside an
unrelated Australia sender-ID notice that does not apply to a US-only product. An
unapproved compliance profile is a documented cause of the same 20003 error, so
it may still gate delivery. Per instruction it was left alone: the only way to
know is one real send. If that send fails, the Twilio error code will say whether
compliance is the reason.

## The stale phone-only record: provably empty

User `ae61589d`, created 2026-02-19, holds the number today.

| | |
|---|---|
| Email | none |
| Phone confirmed | **NO** |
| Ever signed in | **NO** |
| Active sessions | 0 |
| Auth identities | 1 (phone) |

Dependent data, counted across every user-referencing table in `public`,
`kernel`, `market`, `venue` and `notify`:

```
listings 0 · bids 0 · payments 0 · transfers 0 · payout_decisions 0
saved_listings 0 · notifications 0 · push_tokens 0 · admin_users 0
seller_flags 0 · seller_risk_scores 0
kernel: tickets 0 · ticket_ownership_log 0 · payout 0 · obligations 0
        org_member 0 · platform_role 0 · demographics 0 · identity_ext 0
        wallet_pass 0
market: listings 0 · sales 0 · offers 0 · p2p_transfers 0
venue:  orders 0 · staff_role 0 · promoter 0 · inventory_hold 0
notify: preference 0
```

Two rows exist, both created automatically by signup triggers and both empty:
one `public.profiles` row with no display name, and one
`public.notification_preferences` row.

**Verdict: CASE A.** No business history, no money, no tickets, no roles. It is
an abandoned record from a February phone-signup attempt that never completed.

Both dependent foreign keys are `ON DELETE CASCADE`, so removing the auth user
removes those two empty rows and orphans nothing.

## The intended account: identified, not guessed

`2b117757` — the account whose email is the owner's own address, confirmed
against the identity already present in this environment rather than inferred.
It also holds the platform admin row, 63 listings, 58 bids and 46 payments, and
has the most recent sign-in. The owner confirmed this is the target.

Its current state is a clean slate for the transfer:

| | |
|---|---|
| Account exists | YES |
| `auth.users.phone` | **empty** |
| Pending `phone_change` | **empty** |
| `public.profiles` row | present |
| `profiles.phone_number` | **null** |

Nothing conflicts. Nothing will be overwritten.

## What was NOT done, and why

The phone was not freed and no OTP was sent.

Freeing the number needs either the Supabase Admin Auth API, which requires the
service_role key that correctly does not exist in this repository or in any local
env file, or the dashboard. Direct SQL against `auth.users` was available but is
not this project's documented admin path, so it was declined. The owner elected
to perform the removal in the dashboard.

Every OTP test needs the owner's physical device to receive the SMS and read the
code back. None was triggered.

## Status

| | |
|---|---|
| Twilio reactivated | YES |
| Supabase config healthy | YES |
| Stale record safe to remove | YES |
| Phone transfer performed | **NO** — owner action |
| Phone-change SMS received | not yet tested |
| Sign In SMS received | not yet tested |
| Resend tested | not yet tested |
| Sign Up phone verification tested | not yet tested |
| Compliance profile required | **UNKNOWN** — one real send will answer it |
| Source changed | NO |
| Backend / schema / RLS changed | NO |

Remaining blocker: the number is still attached to the stale record, so it must
be freed before it can be linked to the owner's account.
