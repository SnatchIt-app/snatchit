# V3 Package 5 — tickets, profile, settings, authentication, security notices

**B → C · 2026-09-22.** Read at release source `5b255838`. Every file in this package except
`app/(tabs)/profile.tsx` is byte-identical between the inventory baseline and that commit; `profile.tsx` was
re-read and its sign-out still has no confirmation (F-10).

**Artifacts:** `pkg5-auth.png` · `pkg5-tickets-profile.png` · `pkg5-settings-account.png`.

---

## 1 · Authentication

**Four signup steps plus a terminal exit:** `account → about → phone → verify`, and `check_email` when email
confirmation is on. **Back exists only on steps 3 and 4** — the account already exists after step 1, so there
is nothing to go back to.

**Three sign-in surfaces:** phone (the default), the code step, and email + password, which remains a full
second way in.

Facts the design carries and must not lose:

- **Gender is mandatory**; "Prefer not to say" is one of the three values, not an opt-out of the question.
- The **18+ confirmation** gates Continue on step 1. **Terms and Privacy are in-app documents, not web links.**
- The **auth error sanitiser** suppresses technical strings; every unmapped failure falls back to
  *"Something went wrong. Please try again."*
- The **OTP error map has 8 entries** — invalid number, number already taken, send failure, wrong code, expired
  code, rate limit, offline, generic. Each renders inline, not as an alert.
- **Resend is on a 30-second cooldown** and says so.
- The **session-end notice** has three reasons — expired, password updated, signed out on this device — and a
  user-initiated sign-out deliberately shows none.

**Keyboard:** every auth screen is a single field or two above a primary action. The action must ride above the
keyboard, and the code field must stay visible while the keypad is up.

---

## 2 · Tickets

**"No tickets yet" is the state that ships today** — `public.get_my_tickets()` legitimately returns `[]` for
every user. It is not a placeholder for missing design.

Populated shows two sections (Upcoming / Past) and **two badge families**: ownership (Valid / Used / Void /
Expired) and fulfillment (Listed for resale / Transfer in progress / Payment hold / Disputed). "Owned" and
"held" are deliberately hidden.

**Cards are non-tappable by design.** There is no ticket detail, no QR, no Wallet — all dark. **None of those
are designed here**, because designing them would be proposing capabilities.

---

## 3 · Profile

Own profile: identity, masked phone, verification badges, seller stats, the conditional payouts row, sign out.
**"Proceeds —" when zero is deliberate: unknown and zero are different.** The public profile says the same
thing out loud when the trust RPC fails — *"This is not a record of zero sales."* — and that sentence is the
model for every unavailable-data state in the app.

The payouts row appears only when the seller has sold or active listings, and **its probe never regresses on a
timeout**.

---

## 4 · Settings, account actions and the security notice

**Nine navigation rows, no toggles on the hub, no external links on the hub.** The only OS handoffs anywhere in
Settings are `Linking.openSettings()` in Notifications, the `mailto:` in Support, and the Stripe browser hop in
Payout setup.

**Deletion state is tri-state and must stay that way:** a failed probe is **never** read as "not pending". The
pending banner offers Withdraw; the failed probe offers Retry.

**Notifications** carries the device-permission banner, **one wired toggle** (`Listing sold` — five more are
defined and deliberately hidden), the optimistic-write rollback notice, the four-phase push challenge
(including *"Never share this code."*, which is security copy and stays verbatim) and the five registration
remedies.

**The security notice banner's title and body come verbatim from the server.** The client owns no sentence
about the event, and the design must hold **arbitrary length**. Dismissal is server-confirmed — there is no
local-only dismissal, and if the RPC fails the banner stays and says so.

**Account actions keep every guard exactly as it ships** — including the three inconsistencies, which are
findings, not design decisions: sign-out confirms in Settings but not on the Profile tab or the security banner
(**F-10**), and unblock confirms in Blocked users but not on the public profile (**F-11**).

---

## 5 · Explicitly absent — verified, and not designed

Biometric unlock, MFA, change password from settings, change email, resend email confirmation, data export,
session/device list, language or theme settings, an offline banner on Settings, a "complete your profile"
prompt, and any toast system. **None exist in the code and none are designed.**

---

## 6 · Implementation criteria

1. Signup keeps four steps; Back appears only on 3 and 4; gender stays required.
2. Terms and Privacy stay in-app documents.
3. The auth error sanitiser and the 8-entry OTP map survive; no technical string reaches a user.
4. The 30-second resend cooldown and its label survive.
5. The Tickets empty state is treated as a success state, not an error, and cards stay non-tappable.
6. "Proceeds —" for zero and the "not a record of zero sales" sentence survive verbatim.
7. Deletion probe stays tri-state; a failure is never rendered as "not pending".
8. One wired notification toggle; the other five stay hidden; the rollback notice is announced to screen readers.
9. The security notice renders server copy of any length and never dismisses locally.
10. Every account-action guard is unchanged, including the three inconsistent ones.
11. Verified at the largest text size, narrowest width, with a long display name and a missing avatar.
12. `typecheck` · `lint` · `test` green; real screenshots beside the boards.
