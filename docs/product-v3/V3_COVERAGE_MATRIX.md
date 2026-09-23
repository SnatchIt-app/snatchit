# V3 coverage matrix — the completeness check for the whole consumer app

**B · started 2026-09-22 · living document.** Reconciled against the repository, not against memory. The redesign
is not complete until every row here is designed and handed off, or explicitly blocked with a reason, and C has
reviewed the handoff for implementation gaps.

**Repository baseline — CORRECTED 2026-09-22.** Design target is the release source
**`5b255838`** (*"Merge #90 into the release gate"*, on `release/production-gate-20260918`), not the earlier
"Build 22 + #81 + #84" line. C's implementation branch is **`v3/midnight-app` @ `31819593`**.
My first inventory was read from an older worktree and two findings were wrong because of it — see
`V3_FINDINGS_RECONCILED.md`, which supersedes the findings table at the bottom of this file.

**Inventory counted from the tree:** **36 route files** under `app/`, **50 component files**, **~110
`Alert.alert` dialogs across 20 files**. A route list alone misses most of the surface — the dialogs, sheets and
role-conditional states below are where the screens actually live.

**Status key:** ✅ designed & handed off · 🟡 in the current package · ⬜ not started · 🚫 blocked (reason given)

---

## Package status

| # | Package | Scope | Status |
|---|---|---|---|
| 1 | Shared foundations, navigation, reusable states | tokens, components, the four state screens, dock | 🟡 **delivered this round** |
| 2 | Discovery → bidding → checkout | Home, Search, Listing, Bid entry, Checkout, payment outcomes | ⬜ Home/Search/Listing already approved; bid entry + checkout outstanding |
| 3 | Selling and listing management | Create, My listings, Edit, payout setup/return/refresh | ⬜ inventory complete, design outstanding |
| 4 | Orders, transfers and support | Send, Receive, report/dispute, support | ⬜ Order/Receive approved; Send + dispute outstanding |
| 5 | Tickets, account, settings, auth, remaining routes | Tickets, Profile, 10 settings routes, auth, security notice | ⬜ inventory in progress |

---

## 1 · Shared foundations 🟡

| Screen / state | Source | Who sees it / how | Existing behaviour and protected rules | Design status | Impl owner | Dependency / decision |
|---|---|---|---|---|---|---|
| Colour roles | `src/theme/v2.ts:33-84` | every screen | canvas `#000000`, brand.red `#FF1A1A`, status.error `#FF4D4D` ≠ brand red, success reserved for confirmed money | ✅ `pkg1-foundations.png` | C | **AMENDMENT A-1**: hairlines go neutral `#28292D` (shipped `border.*` are red-tinted) |
| Type scale | `src/theme/v2.ts:108-160`, `typography.ts` | every screen | display tokens uppercase-only; `MIN_LINE_HEIGHT_RATIO` 1.25; prices tabular | ✅ same | C | **AMENDMENT A-2**: a mixed-case display role for names (approved) **and** sentence headings (new). Device-measured leading still open |
| Radius | `src/theme/v2.ts:103-106` | every screen | `{none:0, pill:9999}`; Button/Input/Chip/Badge/Sheet/Skeleton all use `none`; comments say "square is the brand", "no pill button" | ✅ same | C | **AMENDMENT A-3**: add `media:8`, `chrome:22`. The shipped dock is already a 33pt pill, so the rule is already broken in product |
| Spacing, targets | `v2.ts space`, `typography.ts` | every screen | 4/8/12/16/24/32/48; `MIN_TOUCH_TARGET` 44; display scale capped 1.3 | ✅ same | C | none — unchanged |
| Button — 4 variants × 4 states | `src/components/ui/Button.tsx` | every screen | primary red + **black** label; destructive is `status.error` **outline, never filled**; disabled dims, never recolours; `pendingLabel` holds width | ✅ `pkg1-components.png` | C | radius per A-3 |
| Input — 5 states | `src/components/ui/Input.tsx` | all forms | label above, hairline under, **radius 0 kept**; focus raises hairline to brand red; label is never the placeholder | ✅ same | C | none |
| Chip | `src/components/ui/Chip.tsx` | filters, pickers | one scrolling row, never wraps | ✅ same | C | radius per A-3 |
| Badge — 5 tones | `src/components/ui/Badge.tsx` | listings, transfers | **meaning carried by a WORD, never colour alone**; venue-direct variant deliberately absent | ✅ same | C | none |
| StickyBar — wide + stacked | `src/components/ui/StickyBar.tsx` | listing, checkout | stacks below `STACK_WIDTH = 352`; structural, not a breakpoint | ✅ same | C | none |
| Skeleton | `src/components/ui/Skeleton.tsx` | all lists | opacity pulse 0.4→0.7/1200ms, **no shimmer**; still under Reduce Motion | ✅ `pkg1-states.png` | C | none |
| Spinner | `src/components/ui/Spinner.tsx` | all | announces "busy"; static under Reduce Motion | ✅ same | C | none |
| State: offline | `StateView` + `STATE_COPY.offline` | any network screen with nothing cached | "You're offline" / "Check your internet connection and try again." / Retry; **auto-retries when connection returns** | ✅ `pkg1-states.png` | C | none |
| State: error | `STATE_COPY.error` | server answered badly | "Couldn't load this" / "Something went wrong on our side. Try again in a moment."; **an abort or timeout lands here, not on offline** | ✅ same | C | none |
| State: noMatch | `STATE_COPY.noMatch` | query ran, returned nothing | "Nothing matches" / "Try the venue name, or a shorter word." | ✅ same | C | none |
| State: empty | `EmptyState` | genuinely empty, screen-specific copy | no glyph, no emoji, one sentence, at most one action | ✅ same | C | none |
| State: loading | `ScreenState` | nothing shown yet | spinner; skeletons where geometry is known | ✅ same | C | none |
| **Failure surface rule** | `src/lib/screens/refreshPolicy.ts` | every list screen | `shouldShowLoading` / `phaseAfterError` / `failureSurface` — a state screen replaces content **only when there is nothing to keep**; a failed quiet refresh keeps the rows | ✅ same | C | **inline failure banner is PROPOSED** — the rule exists, the visual form is new |
| Dock — 5 destinations | `AdaptiveDock.tsx`, `navItems.ts` | every tab screen | Home · Create · Bids · Tickets · Profile; per-route collapse; keyboard retreat; selected = lighter capsule, never a red frame | ✅ `compare-profile-nav.png` | C | "Sell" label for Create (owner decision); "Profile"→"You" changes the accessible name |
| Profile photo item — 4 image states | `AdaptiveDock` + `getAvatarUrl` | signed-in | 66×66 target + hitSlop 6; circular crop is the product's convention | ✅ same | C | must survive account switch (acceptance criterion) |

---

## 2 · Discovery → bidding → checkout ⬜

| Screen / state | Source | Who sees it / how | Existing behaviour and protected rules | Design status | Impl owner | Dependency |
|---|---|---|---|---|---|---|
| Home / discovery | `app/(tabs)/home.tsx` | signed-in, dock Home | all-in prices via `DiscoveryCard.priceAllIn` | ✅ approved | C | — |
| Search + filters | `app/(tabs)/home.tsx`, `FilterSheet.tsx` | header search entry | filters are real `listings` columns; **no count of excluded listings exists** | ✅ approved | C | — |
| Listing detail | `src/screens/ListingDetailScreen.tsx` | `/listing/{id}` | `detailState` → `ActionKind`; **23 `Alert.alert` dialogs** | 🟡 base approved; **dialog set not yet designed** | C | needs the full `ActionKind` × role matrix |
| Bid entry | `src/screens/PlaceBidScreen.tsx`, `app/bid/[id].tsx` | `router.push('/bid/{id}')` from the listing CTA | **the listing CTA opens this screen; it does not submit** | ⬜ | C | **O-2**: the submit control must carry the selected bid and its fee-inclusive total |
| Checkout | `src/screens/checkout/CheckoutNative.tsx`, `app/checkout/[id].tsx` | buy-now / winner pay | payment outcomes, reservation and hold rules — protected | ⬜ | C + A | financial wording review |
| Outbid toast | `src/components/listing/OutbidToast.tsx` | live bid overtaken | — | ⬜ | C | — |
| Listing status banner | `src/components/listing/ListingStatusBanner.tsx` | reserved / ended / cancelled | — | ⬜ | C | — |

---

## 3 · Selling and listing management ⬜ — inventory complete

Create is **one scrolling page with five sections** (Event · Ticket · Selling method · Photos · Confirm) — **no
wizard, no steps, no draft saving**. Exactly **two images**: one 16:9 cover and one private proof to
`proof-docs`. Max 10 MB, JPEG/PNG/WebP/HEIC. **No `maxLength` on any Create field**; Edit caps restrictions at
500. Fees 10% buyer + 10% seller. Durations 1/3/6/12/24/48h. 16 ticket platforms in Create.

| Screen / state | Source | Who sees it / how | Existing behaviour and protected rules | Design status | Impl owner | Dependency |
|---|---|---|---|---|---|---|
| Create — 5 sections + review card | `CreateListingScreen.tsx:576-819` | dock Create, signed-in | validation surfaces only after first submit | ⬜ | C | — |
| Create — price helper | `:700-733` | when the price is valid | "You get {sellerNet} · buyers pay {buyerAllIn} total" | ⬜ | C | per-listing vs per-ticket must be stated |
| Create — risk banner, 3 tones | `:822-836`, `sellState.ts:237-242` | after `can_create_listing` | medium / high / critical copy | ⬜ | C | ⚠ see functional finding F-3 |
| Create — 3 pickers (area, platform, date/time) | `:874-982` | row taps | **neither search sheet has a no-results state** | ⬜ | C | needs a noMatch state |
| Create — high-risk sheet | `:985-991` | risk `warn` | "Account under review" · Cancel / Continue anyway | ⬜ | C | — |
| Create — 8 alerts | `:392,396,417,434,470,494,503,557` | gates and failures | incl. phone-verification and payout-setup gates | ⬜ | C | — |
| Image picker — 3 alerts | `useImageUpload.ts:143-149` | photo permission, size, picker busy | permission-restricted state | ⬜ | C | — |
| MediaUpload — 6 states | `MediaUpload.tsx` | both image tiles | empty / picking / uploading / selected / error / disabled; 8 classified error strings | ⬜ | C | — |
| My listings — 5 filters | `app/my-listings.tsx:196-208` | Profile rows | All / Active / Send tickets / Sold / Ended | ⬜ | C | — |
| My listings — 5 empty variants | `:232-248` | per filter | distinct copy per filter | ⬜ | C | — |
| My listings — offline/error | `:223-224` | nothing cached | `ScreenState`, auto-retry | ⬜ | C | — |
| My listings — 5 alerts | `:107,111,124,134,139` | cancel/delete | **"This listing has bids. Cancelling will void all bids."** — destructive, protected | ⬜ | C | — |
| Seller row — 6 badges + 4 bottom lines | `SellerListingCard.tsx`, `sellerListing.ts` | My listings | Active / Ending soon / Ended / Reserved / Sold / Cancelled | ⬜ | C | — |
| Edit listing — form + guard | `app/listing/edit/[id].tsx` | owner, **only while `bid_count === 0`** | unsaved-changes guard: "Discard changes?" | ⬜ | C | ⚠ F-1, F-2 |
| Edit — 9 alerts | `:76,82,86,109,114,129,131` + guard | gates and failures | | ⬜ | C | — |
| Payout setup — 4 status states | `app/settings/payout-setup.tsx:141-155` | Settings / Profile / Create gate | not_connected / onboarding_required / connected + refresh | ⬜ | C | — |
| Payout return | `app/payout-return.tsx` | Stripe redirect | success + 1500ms auto-redirect | ⬜ | C | — |
| Payout refresh | `app/payout-refresh.tsx` | expired onboarding link | **the one true "expired" state in this flow** | ⬜ | C | — |

---

## 4 · Orders, transfers and support ⬜ — inventory complete

**The DB allows 7 transfer statuses** (`024_disputes.sql:62-70`): `pending, seller_sent, buyer_confirmed,
disputed, expired, auto_released, reversed`. **The shared vocabulary type covers only 5.** `expired` and
`reversed` fall to a default branch and render a bare lowercase badge with **no state block and no explanation
for either role** — see F-17, the most serious gap found in this inventory.

### Seller — send transfer (`app/transfer/send/[id].tsx`, 13 alerts)

| Screen / state | Source | Who / how | Existing behaviour and protected rules | Design | Owner | Dependency |
|---|---|---|---|---|---|---|
| Loading / offline / not found | `:259-270` | seller only (`.eq('seller_id')`) | "Transfer not found" has **no retry control** | ⬜ | C | — |
| Delivery target + missing warning | `:289-299` | buyer has no email+phone | "The buyer must provide their delivery info before you can send tickets." | ⬜ | C | — |
| Platform instructions | `PlatformInstructions.tsx:52-114` | per provider | returns null when no entry exists | ⬜ | C | provider claims are our own encoding |
| Expiry countdown | `:306-312` | `pending` + `expires_at` | "{h}h {m}m remaining to send" / "Transfer window expired" | ⬜ | C | — |
| Pending — evidence + CTA | `:326-349` | `pending` | proof screenshot required before "Mark as sent" | ⬜ | C | — |
| **Mark-as-sent — 7 outcomes** | `:128-170`, `markSent.ts:92-95` | submit | includes an explicit **unconfirmed** third state: "We couldn't confirm this transfer was marked as sent." | ⬜ | C | **this is the action-not-sent vs unknown-result distinction, already correct in code** |
| seller_sent + **4 payout states** | `:352-369` | `seller_sent` | window open / passed / held / manual review | ⬜ | C + A | financial wording |
| Add-proof recovery | `:372-390` | sent without a screenshot | "It can't be replaced" | ⬜ | C | — |
| buyer_confirmed — 2 variants | `:393-401` | released vs processing | **"Your payout has been released"** vs "is being processed" | ⬜ | C + A | — |
| auto_released | `:404-408` | — | "The buyer review window passed without a dispute." | ⬜ | C + A | — |
| disputed | `:411-415` | — | "Your payout is on hold pending review." | ⬜ | C | — |

### Buyer — receive transfer (`app/transfer/receive/[id].tsx`, 9 alerts)

| Screen / state | Source | Existing behaviour and protected rules | Design | Owner | Dependency |
|---|---|---|---|---|---|
| Loading / offline / not found | `:284-299` | — | ✅ approved (unreachable variant) | C | — |
| Delivery gate + form | `:311-315`, `DeliveryInfoForm.tsx` | buyer must supply a destination before the seller can send | ⬜ | C | saved preferences are **proposed, not built** |
| Provider handoff button | `:323-333`, `providerHandoff.ts` | 15 named providers; absent for `other` | ⬜ | C | — |
| Return prompt after provider | `:374-385` | **"that is what releases payment to the seller"** | ⬜ | C + A | — |
| Countdown banner | `:338-344` | ⚠ shown for disputed/auto_released/expired too (F-19) | ⬜ | C | — |
| pending / seller_sent claim | `:360-372` | **"That is the seller's update, not a confirmation."** — the reported-vs-possession rule, protected | ✅ approved | C | — |
| Seller's proof + viewer | `:387-395`, `ProofImageViewer.tsx` | silently absent if the signed URL fails (F-20) | ⬜ | C | — |
| Release warning | `:397-401` | **"By confirming, you release payment to the seller."** | ✅ approved | C + A | **O-1** |
| Confirm — success + 8 server errors | `:192-221` | server strings shown verbatim, incl. "This order is under review." | ⬜ | C + A | — |
| Dispute — confirm + 2 outcomes | `:228-258` | "This will freeze the transfer and notify support." | ⬜ | C | — |
| buyer_confirmed / auto_released / disputed | `:426-444` | auto_released: **"The review window closed without a confirmation or a report from you, so payment went to the seller."** | ⬜ | C + A | — |
| **`expired` — seller** | `transferState.ts:98-110` → `send/[id].tsx:283` | **"Order expired" / "This order expired before it was marked as sent. Don't transfer the tickets for this order."** — server fact first | ⬜ design the block | C | none — copy exists |
| **`expired` / `reversed` — buyer** | no branch in `receive/[id].tsx` | **nothing renders**; badge falls to a lowercase `default:` label | 🚫 **blocked on F-17b** | C + A | neutral copy drafted for review; a refund sentence needs payment evidence |

### Tickets, report, support

| Screen / state | Source | Existing behaviour and protected rules | Design | Owner | Dependency |
|---|---|---|---|---|---|
| Tickets — loading / offline / error / empty | `(tabs)/tickets.tsx:140-148` | **"No tickets yet" is today's real state** — the RPC returns `[]` | ⬜ | C | F-22: whether the migration is applied decides empty vs error |
| Tickets — populated, 2 sections, 2 badge families | `:153-172`, `TicketEventGroup.tsx` | Valid/Used/Void/Expired + Listed/Transfer/Hold/Disputed; **cards are non-tappable by design** | ⬜ | C | no detail, no QR, no Wallet — all dark |
| Tickets — DEV fixtures banner | `:118-138` | "Sample tickets — no server data" | ⬜ | C | `__DEV__` only |
| Report listing / user | `app/report/[type]/[id].tsx` | 4–5 reasons, notes `{n}/1000`, discard guard | ⬜ | C | **no report route exists for a transfer or order** |
| Report — signed-out / failure / success | `:62,70,74` | "We review reports within 24 hours" | ⬜ | C | — |
| Support — FAQ + mailto | `settings/support.tsx` | static; no loading/error state exists | ⬜ | C | — |

## 5 · Tickets, account, settings, auth ⬜ — inventory complete for auth/profile/settings

**29 distinct sub-screens and states** across authentication, profile and settings. Structural facts that
constrain the design:

- **There is no toast or snackbar anywhere in the app.** Every transient message is a native `Alert` or an
  inline `<Text accessibilityRole="alert">`. **Do not design a toast system.**
- **Web forks exist with different copy.** `settings/index.tsx` and `edit-profile.tsx` branch on
  `Platform.OS === 'web'` with `window.alert`/`window.confirm` and reworded strings. Native and web are not
  copy-identical.
- **Signup is 4 steps + a terminal exit**: `account → about → phone → verify`, plus `check_email` when email
  confirmation is on. Back exists only on steps 3–4 — the account already exists after step 1.
- **Only one of six notification toggles is wired** (`WIRED_PREF_KEYS = ['notify_listing_sold']`). The other
  five are defined and deliberately hidden. **Do not draw the hidden five.**

### Authentication

| Screen / state | Source | Who / how | Existing behaviour and protected rules | Design | Owner | Dependency |
|---|---|---|---|---|---|---|
| Sign in — phone, enter number | `login.tsx:189-221` | signed-out landing; phone is the default method | `shouldCreateUser:false` — an unknown number must not create an account | ⬜ | C | — |
| Sign in — phone, enter code | `login.tsx:223-255` | after send | masked number, 30s resend cooldown | ⬜ | C | — |
| Sign in — email/password | `login.tsx:257-302` | "Use email instead" | email+password remains a full second way in | ⬜ | C | — |
| Session-end notice | `login.tsx:173-175`, `sessionEnd.ts:44-49` | after a marked sign-out; consumed once | 3 reasons: expired / password changed / signed out on this device | ⬜ | C | — |
| OTP error map — 8 strings | `phoneAuth.ts:110-122` | any OTP failure | covers invalid, taken, send-failed, mismatch, expired, rate-limited, offline | ⬜ | C | — |
| Auth error sanitiser | `authForms.ts:39-63` | any Supabase auth error | technical strings suppressed — **protected** | ⬜ | C | — |
| Forgot password — 3 alerts | `login.tsx:149-154` | email method | two are **bare-title alerts** (F-13) | ⬜ | C | — |
| Signup step 1 — account | `signup.tsx:241-312` | `/(auth)/signup` | email + password ≥6 + **18+ checkbox**; legal links are in-app | ⬜ | C | — |
| Signup step 2 — about | `signup.tsx:314-337` | after a session exists | name 2–50; **gender is mandatory** (`prefer_not_to_say` is a value) | ⬜ | C | — |
| Signup step 3 — phone | `signup.tsx:339-364` | — | "Your number is how you sign in from now on." | ⬜ | C | — |
| Signup step 4 — verify | `signup.tsx:366-403` | — | button is `Create account`; no skip control | ⬜ | C | F-9 |
| Signup terminal — check email | `signup.tsx:405-411` | only when `signUp` returns no session | — | ⬜ | C | — |
| Signup validation — 8 strings | `signupFlow.ts:80-104` | per step | — | ⬜ | C | — |
| Reset password + 3 outcomes | `reset-password.tsx:30,46,51` | deep link → `PASSWORD_RECOVERY` | includes a **recursive "Try again"** when the global sign-out fails | ⬜ | C | — |

### Profile

| Screen / state | Source | Who / how | Existing behaviour and protected rules | Design | Owner | Dependency |
|---|---|---|---|---|---|---|
| Own profile — loading / offline / error | `(tabs)/profile.tsx:213-227` | Profile tab | `ScreenState` + auto-retry | ⬜ | C | — |
| Own profile — identity + badges | `:238-279` | own only | masked phone `+1 (***) ***-1234` or `—` | ⬜ | C | — |
| Avatar pick/upload — 5 states | `:189-203`, `avatarImage.ts:83-149` | tap avatar | permission, cancel (silent), upload fail, save fail, success | ⬜ | C | feeds the dock photo |
| Seller stats | `:282-296` | own | **`—` when 0 by design** — unknown vs zero is deliberate | ⬜ | C | — |
| Payouts row — 3 states | `:299-307` | only if sold>0 or active>0 | 6s probe timeout **silently keeps the current value** | ⬜ | C | — |
| Sign out (no confirm) | `:205-211,311` | own profile | ⚠ inconsistent with Settings | ⬜ | C | F-10 |
| Public profile — not found | `profile/[id].tsx:185-192` | row missing / RLS-hidden | "Profile unavailable" | ⬜ | C | — |
| Public profile — you blocked them | `:197-209` | viewer has a block row | Unblock action | ⬜ | C | — |
| Trust panel — stats unavailable | `:234-239` | RPC errored | **"This is not a record of zero sales."** — the unknown-vs-zero rule, protected | ⬜ | C | — |
| Trust panel — normal + 5 tiers | `:242-260`, `reputation.ts:26-78` | any viewer | New / Trusted / Top / Elite / Needs review | ⬜ | C | — |
| Active listings (public) + empty | `:266-272` | any viewer | — | ⬜ | C | — |
| Block — confirm + 2 outcomes | `:147-164` | not self | destructive confirm | ⬜ | C | — |
| Unblock from profile (no confirm) | `:166-174` | blocked view | ⚠ inconsistent with Blocked users | ⬜ | C | F-11 |

### Settings hub and sub-screens

| Screen / state | Source | Who / how | Existing behaviour and protected rules | Design | Owner | Dependency |
|---|---|---|---|---|---|---|
| Settings hub — 9 navigation rows | `settings/index.tsx:321-347` | from Profile | **no toggles, no external links on the hub** | ⬜ | C | — |
| Deletion-probe-failed banner | `:295-302` | `identity_ext` read failed | **tri-state: a failure is never read as "not pending"** — protected | ⬜ | C | — |
| Deletion-pending banner + withdraw | `:304-318` | `DELETION_PENDING` | re-checked on AppState active | ⬜ | C | — |
| Sign out — confirm | `:119-140` | hub | 2-button destructive | ⬜ | C | — |
| Sign out all devices — confirm | `:143-169` | hub | "…stops notifications everywhere" | ⬜ | C | — |
| **Delete account — double confirm** | `:248-282` | hub | two dialogs native, two `window.confirm` on web | ⬜ | C | F-12 |
| Deletion accepted + obligations | `:176-205` | edge fn accepted | 9 obligation labels; `cancelable:false` | ⬜ | C | F-14 |
| Edit profile — form + validation | `edit-profile.tsx:140-203` | hub | bio counter `{n}/200`, name 2–50, US phone | ⬜ | C | — |
| Verify phone — 3 states | `verify-phone.tsx:133-192` | hub, and from the Create gate | enter / code / verified | ⬜ | C | F-9 |
| Notifications — load + error | `notifications.tsx:119-138` | hub | — | ⬜ | C | — |
| Notifications — device permission banner | `:144-158` | always | **the only `Linking.openSettings()` in Settings** | ⬜ | C | — |
| Notifications — 1 wired toggle | `:224-241` | hub | optimistic write + rollback | ⬜ | C | F-15 |
| Notifications — failed-toggle notice | `:101-117` | write failed | "It's back to {on\|off}" — announced | ⬜ | C | — |
| Notifications — push challenge, 4 phases | `:160-208`, `challenge.ts:270-293` | device proof-of-possession | **"Never share this code."** — security copy, protected | ⬜ | C | — |
| Notifications — registration remedy, 5 causes | `:210-222`, `registration.ts:228-248` | failed/waiting | device-bound-to-another-account, secure storage, signed out, rate-limited, app too old | ⬜ | C | — |
| Your scene — chips + autosave | `preferences.tsx:96-121` | hub | "Changes save as you go" | ⬜ | C | — |
| Your scene — rollback + leave-while-saving | `:33,79` | save failed / back gesture | "Still saving" / Wait / Leave anyway | ⬜ | C | — |
| Blocked users — load failed | `blocked-users.tsx:116-123` | query error | **"This is not a record that you have blocked no one."** — protected | ⬜ | C | — |
| Blocked users — empty / rows / unblock confirm | `:124-156,95-109` | hub | — | ⬜ | C | — |
| Support — FAQ + mailto | `support.tsx:52-79` | hub | external `mailto:`, failures swallowed | ⬜ | C | — |
| Terms / Privacy | `legal.tsx`, `privacy.tsx` | hub + signup | **in-app documents, not web links**; long static content | ⬜ | C | — |
| Security notice banner | `SecurityNoticeBanner.tsx:36-48` | above every signed-in tab | **title and body are server-rendered, unbounded length**; dismissal is server-confirmed, never local-only | ⬜ | C | must design for arbitrary-length server copy |
| Error boundary | `src/components/ErrorBoundary.tsx` | crash | the last-resort screen | ⬜ | C | — |

### Explicitly absent — do NOT design these

Verified absent from the code: biometric/Face ID unlock, MFA/2FA, change password from settings, change email,
resend email confirmation, account data export, session/device list, language or theme settings, an offline
banner on Settings, and any "complete your profile" prompt. Also absent: draft saving in Create, a toast system,
and a no-results state in either Create picker sheet.

## Functional findings — SUPERSEDED

> **This table is superseded by `V3_FINDINGS_RECONCILED.md`**, which re-reads every finding against the
> release source `5b255838` and C's branch `v3/midnight-app`, labels each ①–⑤, and corrects F-17 and F-19.
> It is kept here only as the original record.

## Functional findings — original record, NOT visual work

Found while inventorying. **These are defects in the current app, not redesign items.** They are listed so they
are not silently "fixed" by a redesign or silently lost. C and A own triage.

| # | Finding | Source |
|---|---|---|
| **F-1** | **Edit listing can hang on a permanent spinner.** `load()` returns early when `!listingId \|\| !user` without clearing `loading`, and the "Not allowed" / "Cannot edit" branches also return without `setLoading(false)` — the spinner persists until the alert's OK navigates back. Dismiss any other way and it never clears | `app/listing/edit/[id].tsx:72,82-94` |
| **F-2** | **Edit offers 6 ticket platforms; Create offers 16.** A listing on a platform outside the six shows no chip selected. The stored value survives a save, but the UI misrepresents it | `edit/[id].tsx:31-38` vs `CreateListingScreen.tsx:84-101` |
| **F-3** | **A transient RPC failure shows an account-reputation warning.** A network hiccup tells the seller "We've noticed some recent issues. Please double-check your listing details." Failing open is intentional; the copy misattributes the cause | `CreateListingScreen.tsx:386-389` |
| **F-4** | **Signed-out publish is silent.** `handlePublish` returns with no message when `!user`, but `submitted` is set, so every field turns red with no explanation | `CreateListingScreen.tsx:410` |
| **F-5** | **Neither Create search sheet has a no-results state.** A non-matching search renders an empty scroll view | `CreateListingScreen.tsx:892,933-937` |
| **F-6** | **Stripe onboarding cancellation has no UI.** The auth-session result is only `console.log`ged; a user who backs out sees nothing | `app/settings/payout-setup.tsx:126` |
| **F-7** | **Two different messages for the same banned-content rule** | `CreateListingScreen.tsx:416` vs `edit/[id].tsx:114` |
| **F-8** | **No offline detection on Create or payout-setup.** Only My listings uses `ScreenState`; Create surfaces offline only as an upload error string | — |
| **F-9** | **Phone verification is not enforced.** There is no skip control, but the account is created at step 1 and the onboarding gate lowers unconditionally on unmount — abandoning after step 1 leaves a usable, phone-less session on Home. No code in scope gates listing creation on `phone_confirmed_at` | `signup.tsx:85-88,112-136`; `onboardingGate.ts` |
| **F-10** | **Two sign-out entry points disagree on confirmation.** Settings confirms; the Profile tab button and the security banner sign out immediately | `settings/index.tsx:119` vs `profile.tsx:205`, `useSecurityNotices.ts:73` |
| **F-11** | **Two unblock entry points disagree on confirmation.** Blocked users confirms; the public profile does not | `blocked-users.tsx:95` vs `profile/[id].tsx:166` |
| **F-12** | **Web and native delete-account copy differ.** Different wording for the same two-step confirmation | `settings/index.tsx:248-282` |
| **F-13** | **Bare-title alerts.** `Alert.alert('Enter your email first')` and `Alert.alert(invalid)` pass the message as the title with no body | `login.tsx:150`, `reset-password.tsx:30` |
| **F-14** | **Delete-account obligation labels can leak raw server tokens** when a `kind` is unrecognised | `settings/index.tsx:193` |
| **F-15** | **Five of six notification preferences are defined but hidden** (`WIRED_PREF_KEYS`). Intentional, but worth confirming it stays that way | `notificationPrefs.ts:29-33` |
| **F-16** | **A signed-out guard on the public profile is likely unreachable**, since the root layout replaces signed-out sessions with the login route | `profile/[id].tsx:148` vs `app/_layout.tsx:108-118` |
| **F-17** | **🔴 `expired` and `reversed` transfers show nothing.** The DB allows 7 statuses; the UI vocabulary covers 5. Both fall to a default branch that renders a bare lowercase badge — **no state block, no explanation, and no mention of the refund** — for buyer and seller alike. The refund is announced **only by push**: "Your full refund has been issued." A buyer who opens the app instead of tapping the notification learns nothing. This is the owner's "recorded refund vs known full refund" distinction with no screen behind it | `transferState.ts:22-27,53`; `024_disputes.sql:62-70`; `enforce-transfer-expiry:649-662` |
| **F-18** | **`TransferStatusBadge.tsx` is never imported anywhere.** It already contains the missing words — `expired → "Transfer Expired"`, `reversed → "Payment Reversed"` — and nothing renders them. Likewise `transferStatusCopy(status, 'seller')` is never called: all six call sites pass `'buyer'`, so the seller copy at `transferState.ts:70,82,86` is dead | `TransferStatusBadge.tsx:10,12` |
| **F-19** | **The buyer sees the seller's deadline on settled transfers.** The countdown is gated only on `status !== 'buyer_confirmed'`, so a disputed, auto-released, expired or reversed transfer still shows "Transfer window expired" to the buyer | `receive/[id].tsx:338` |
| **F-20** | **A failed proof-image signed URL is silent.** The proof block just disappears; the buyer is not told there was an image they could not load | `receive/[id].tsx:105-107` |
| **F-21** | **Raw PostgREST error text reaches the buyer.** The delivery-info save shows `rpcErr.message` unfiltered — the only place in these screens where it does; the seller path deliberately filters through `userFacing` | `receive/[id].tsx:183` vs `markSent.ts:110-112` |
| **F-22** | **The buyer is never shown the auto-release deadline.** `auto_release_at` is not even in the select list, so the one date that decides whether payment leaves is invisible to the person it affects. The seller sees a countdown; the buyer sees it only after the fact | `receive/[id].tsx:119` |
| **F-23** | **`send-push` ignores notification preferences** for everything except listing-sold; every transfer, dispute and expiry push goes out regardless | `send-push/index.ts:266-295` vs `stripe-webhook:364-380` |
| **F-24** | **Any unrecognised `type` segment silently becomes a listing report** | `report/[type]/[id].tsx:40` |

---

## Open owner decisions

| # | Decision | Recommendation |
|---|---|---|
| **A-1 · A-2 · A-3** | The three foundation amendments above (neutral hairlines, a mixed-case display role for sentence headings, `radius.media`/`radius.chrome`) | Adopt all three. A-3 is the material one: it follows from the screens already approved, and the shipping dock already breaks the "square is the brand" rule. Flagged rather than assumed |
| **O-1** | Automatic-release wording | A + C, blocking the order screen only |
| **O-2** | Bid CTA vs bid-entry submit label | C — the submission control must reflect the selected bid and its fee-inclusive total |
| **O-3** | What "Report a problem" does offline | C |
| **O-4** | Mixed-case display leading, measured on device | C |
