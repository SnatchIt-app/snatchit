# Phase 8 batch — Account settings completion (nine subroutes)

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase8-settings-completion` (from the Phase 7 checkpoint).
Not committed — awaiting device review. No push, no PR, no Core-owned file touched.

## 1. Phase 7 checkpoint SHA

`90e6b8331515bf59dcac031acd9d81382b77423f` — `feat(frontend-v2): redesign auth transfer and listings`.
Verified at checkpoint: 511 tests / 19 files, tsc clean, 30 lint warnings / 0 errors.

## 2. Branch / base

`frontend/v2-phase8-settings-completion`, branched from `90e6b83`. No rebase, no force-push.

## 3. Files changed

```
M  app/settings/notifications.tsx      M  app/settings/edit-profile.tsx     M  app/settings/support.tsx
M  app/settings/preferences.tsx        M  app/settings/payout-setup.tsx     M  app/settings/legal.tsx
M  app/settings/blocked-users.tsx      M  app/settings/verify-phone.tsx     M  app/settings/privacy.tsx
A  src/components/account/SettingsHeader.tsx   shared back + Oswald title (used by all nine)
A  tests/settings-completion.test.ts
A  docs/product-v2/PHASE_8_SETTINGS_COMPLETION_REPORT.md
```

The Settings hub (`app/settings/index.tsx`) and every approved surface, shared UI primitive, theme token
and Core file are byte-unchanged.

## 4. Group A behavior inventory (notifications / preferences / blocked-users)

**Notifications:** `notification_preferences` fetch; six toggles; device-permission check
(`getPermissionsAsync`) with a focus re-check and an "Open settings" recovery; OPTIMISTIC toggle that
flips immediately and reverts + alerts on a failed write. **Preferences:** hydrate from `get_my_profile`,
multi-select neighborhoods, save to `profiles.preferred_neighborhoods`, with explicit `saveError`
handling (the earlier swallowed-save bug). **Blocked-users:** two-step fetch (`user_blocks` → `profiles`),
a `loadFailed` state distinct from empty, focus refetch + pull-to-refresh, unblock confirm + delete +
refresh, fallback "Blocked user" label.

## 5. Group A preserved

**All.** Optimistic-with-revert, the permission banner + recovery, the `saveError`-and-do-not-navigate
rule, and the load-failed-vs-empty safety distinction are unchanged and source-guarded. A failed save
never looks successful; a failed load never reads as "no one blocked".

## 6. Group B behavior inventory (edit-profile / payout-setup / verify-phone)

**Edit-profile:** `get_my_profile` hydrate; immediate avatar pick+upload (independent DB write);
validation (display name 2-50, optional NANP phone with formatted display, bio ≤ 200); save normalizes
the phone before persisting. **Payout-setup:** debounced status probe (`get_my_profile` +
`create-connect-account` status_only, 6s timeout), mount/focus/AppState re-checks, the
`openAuthSessionAsync` deep-link onboarding (`snatchit://payout-return`), and "never regress status on a
blip". **Verify-phone:** `updateUser({ phone })` → `verifyOtp({ type: 'phone_change' })`, 30s resend
cooldown, already-verified check, rate/expired/invalid error mapping.

## 7. Group B preserved

**All.** Every Supabase/Stripe call, the validation rules, the phone normalization, the OTP flow, the
cooldown and the status-probe/never-regress logic are unchanged (source-guarded). Payout is a
presentation-only pass — Stripe Connect is untouched.

## 8. Group C behavior inventory (support / legal / privacy)

**Support:** three FAQ entries (expand/collapse) + a `support@snatchitapp.com` mailto. **Legal:** the
Terms of Service content + the "Key terms summary" accordion + a link to Privacy. **Privacy:** the full
Privacy Policy content. Legal and privacy are static content screens with an effective date.

## 9. Group C preserved

**All.** The mailto and FAQ copy are intact. Legal and privacy CONTENT is byte-preserved — the redesign
touched only the imports, the header, and the StyleSheet; every content string, section, bullet and the
"Effective Date: March 20, 2026" label is verbatim. Tests assert specific legal phrases
("10% service fee", "Form 1099-K", "binding individual arbitration", "PCI DSS Level 1 certified",
"not intended for users under 18") still appear.

## 10. Persistence behavior

Preserved and, where relevant, protected. Notifications revert the optimistic flip on failure;
preferences show a human `saveError` and do NOT navigate back on failure (only success returns);
blocked-users keeps `loadFailed` separate from empty; edit-profile alerts on a failed save. A failed
persistence never looks successful anywhere.

## 11. Payout behavior

Unchanged. Status derives from Stripe's authoritative `details_submitted` via the status_only edge
function; the UI never implies money is available before that; a network error keeps the current status
rather than downgrading it; the deep-link onboarding + return re-check is intact. Copy dropped the raw
"Stripe Express account" phrasing from the button labels but keeps Stripe named where it is the honest
processor. No Stripe Connect backend change.

## 12. Phone verification behavior

Unchanged. The `phone_change` OTP flow, the 30s resend cooldown, the already-verified short-circuit and
the error mapping are preserved. No custom SMS provider added (Twilio stays configured in Supabase). The
verified-state copy was reworded off the banned "you're all set" phrase to "You can now sell tickets on
Snatch It."

## 13. Privacy / public-data handling

Preserved. Edit-profile adds no social fields (no followers/following/views); the phone is
verification-only and is not surfaced publicly here; blocked-users shows only a display name (falling
back to "Blocked user") and the block date, never private account data. The privacy policy's statement
that the number is "never shown on your public profile and never used for marketing" is intact.

## 14. Support / legal presentation

Support: an Oswald page title, an "Contact us" section with a secondary email button, and hairline FAQ
rows with a +/− affordance (no emoji). Legal/privacy: an Oswald uppercase page title, Inter body at 15/22
with red-tinted section eyebrows, red bullet dots and a bordered "Key terms summary" panel — readable,
sharp, no marketing styling, content untouched.

## 15. Accessibility

Every screen wears the shared `SettingsHeader` (labelled back, Oswald header). Toggles carry
`accessibilityLabel`; the notifications permission banner and the preferences/edit-profile errors are
`role="alert"`; the blocked-users retry and unblock are labelled buttons; verify-phone code field uses
`textContentType="oneTimeCode"`; FAQ headers expose `expanded` state; controls meet 44pt (or hitSlop).
No toggle/save state is colour-only — a word always accompanies red/green.

## 16. Motion

Restrained: only the primitives' press-scale and the FAQ/step show-hide. No confetti, pulsing or
bouncing.

## 17. Tests added

12 tests in `tests/settings-completion.test.ts`. Suite total **523 / 20 files** (was 511 / 19). No
existing test weakened.

## 18. Exact test result

Group A (revert-on-fail, saveError-no-navigate, load-failed-vs-empty); Group B (edit validation +
normalize + no social fields, payout never-regress + deep link, OTP phone_change + cooldown + no banned
phrase); Group C (support mailto + no chat/SLA, legal content verbatim, privacy content verbatim); house
rules (no kernel.tickets / no money import across all nine, no emoji in the seven interactive screens,
all nine wear SettingsHeader). All pass.

## 19. Typecheck

`tsc --noEmit` clean.

## 20. Lint

`expo lint`: 28 problems, **0 errors, 28 warnings** — two fewer than the 30 baseline, **no new warnings**
(the rewrites removed stale eslint-disable directives and unused imports).

## 21. Native iOS bundle

`platform=ios` metro bundle builds **HTTP 200**, 14.5 MB, no real errors (only a Reanimated worklet log
string matches a naive grep). The redesigned screens (`SettingsHeader`, `Your scene`, `Payout setup`,
`Phone verification`, `Privacy policy`, `notification_preferences`) and preserved paths (`verifyOtp`,
`create-connect-account`, `user_blocks`, `preferred_neighborhoods`) are present in the bundle.

## 22. Physical-device verification

**Not performed by this session.** The local simulator remains blocked (SDK 26.5 present, only a 26.2
runtime → 0 eligible destinations); no simulator claim is made. Prepared for one account/settings review
pass across all nine: notifications (toggles + permission banner), preferences (save + failed-save
message), blocked-users (list/empty/failed + unblock), edit-profile (avatar + validation + save),
payout-setup (each status + refresh), verify-phone (send/verify/resend), support (FAQ + email), legal +
privacy (scroll + links). Use a dev-safe account for any state that writes; no production data should be
mutated to stage states.

## 23. Core dependencies

None new. Consumes existing contracts only: `notification_preferences`, `profiles`,
`get_my_profile`, `user_blocks`, the `create-connect-account` edge function + Stripe Connect deep link,
Supabase phone OTP (`updateUser` / `verifyOtp`), and the avatar bucket. No schema, RLS, RPC, edge
function or money/auth architecture touched. No `kernel.tickets` query; no venue-primary path (093 still
off).

## 24. Adaptive-nav readiness

Ready to start as its own batch. The account area is now fully V2 and every settings surface is a
predictable, always-visible-navigation utility context — none participate in the Home-only scroll-collapse
dock, so building the dock will not disturb them. Direction is documented in
`docs/product-v2/NAVIGATION_V2_DIRECTION.md`.

## 25. Tickets readiness

**Blocked.** No Tickets surface was built and none should be until Core delivers the canonical contract.
Every completed surface expresses ownership only through existing data (transfers, listings, profile),
never as a ticket object.

## 26. Exact ticket blocker

`kernel.tickets` has no authenticated SELECT available to the app. To ship Tickets, Core must provide, at
minimum:

1. **An owner-scoped authenticated read of `kernel.tickets`** — an RLS SELECT policy (or a dedicated RPC
   / PostgREST view) that returns the signed-in user's own tickets, reachable from the mobile client.
2. **A documented ticket row shape** the client can render event-first: event reference (name/date/venue
   or a joinable listing/event id), ticket type, quantity, and an explicit **ownership / fulfillment
   state** plus an **upcoming-vs-past** signal (or a date the client can derive it from).
3. **A stable status/error vocabulary** for that read, so the Tickets UI can map states without parsing
   raw Postgres/RPC strings.

If (and only if) barcode/QR/wallet surfaces are later wanted, Core must additionally provide the
issuance/redemption contract (a token or pass source). Until item 1 exists, Tickets stays a documented
direction, not a product surface.

## 27. Recommended next batch

**Global adaptive navigation** (the Home-only full-dock → compact-Home scroll-collapse, the five-
destination model with Search inside Home), since every transactional and account surface is now V2 and
the direction is documented. Tickets remains gated on the Core contract above; if Core delivers items
1-3 first, pair a **Tickets + Ticket Detail** batch with the nav work instead.
