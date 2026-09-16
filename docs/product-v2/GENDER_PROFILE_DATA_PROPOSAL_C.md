# Profile gender — signup and profile proposal (C)

**Status: PROPOSAL, 2026-09-16. Nothing implemented. No migration, schema, analytics query or
production change is authorized.** Owner request of 2026-09-16 (it supersedes the interrupted
draft sent minutes earlier, which had the field optional and never asked at signup; every other
constraint of that draft carries over). A reviews the data contract, privacy, schema, RLS and
analytics implications; D defines the analytics dimensions and dashboard treatment. Task IDs
CFT-901…908 in `PREMIUM_EXPERIENCE_BACKLOG.md`.

## 1. Owner requirements (as given)
- Gender is a key analytics dimension; collect it during signup, respectfully and privacy-safe.
- The signup field is **required to be answered**, with **"Prefer not to say"** so nobody is forced to
  disclose. Inclusive predefined options plus an optional self-described value.
- Explain why it is requested; **explicit consent for analytics use**; editable or clearable later.
- **Private by default.** Never inferred from names, photos or behaviour.
- Analytics: **aggregated only, with small-group suppression.**
- RLS, retention, deletion, export and account-deletion behaviour defined **with A before schema work**.
- **Not used** in discovery, bidding, checkout, transfers or seller decisions unless separately approved.

## 2. Product truths this must hold
- A "Prefer not to say" answer, a cleared value and any disclosed value are **indistinguishable in every
  flow** outside the profile itself: same listings, same bids, same checkout, same transfers, same seller
  tools. Enforced by a source pin (CFT-907): the field name may appear only in the signup profile step,
  Settings › Edit profile, and the profile read model.
- Consent is **separate from the answer** and **declinable without consequence**: signup completes with
  consent off. Withdrawing consent stops analytics inclusion from that moment.
- No public display in this proposal. A visibility opt-in is **not** proposed; it would be a separate
  owner decision.

## 3. Concerns flagged (then proceeding as asked)
1. **App Store Review Guideline 5.1.1 (data minimisation):** apps should not require personal data that
   is not needed for the app to function. A required question that always accepts "Prefer not to say",
   with an honest one-line "why", is the mitigation that keeps disclosure optional in substance. A's
   privacy review should confirm; if A objects, the fallback is the same screen with the field
   answerable but skippable.
2. **Signup friction:** one extra decision on the profile step. It sits with Name, after the age
   confirmation and account creation, never before email/password.
3. **Self-described free text** is personal data that no aggregate can safely show; it must never reach
   analytics or dashboards (D treats it as the bucket "Self-described").

## 4. UI proposal
**Where.** `app/(auth)/signup.tsx`, step 2 (the step that already asks for Name), directly under Name.
Settings › Edit profile (`app/settings/edit-profile.tsx`) gets a "Gender" row under Bio.

**Signup, step 2.**
- Section label **"Gender"** with helper text under it (§5), and a "Why we ask" link that opens a bottom
  sheet (§5). The sheet is the only long text; the step itself stays one screen at default text size.
- Single-select list (radio group), fixed order: **Woman · Man · Non-binary · Self-describe · Prefer not
  to say.** Each row 44 pt, full-width, the app's selection ring; "Prefer not to say" is styled exactly
  like the others (no de-emphasis, never last-and-hidden: at the largest text size the list scrolls
  and the step's Continue stays docked, so the option is reachable, not buried).
- Choosing **Self-describe** reveals one text field under it (≤ 40 characters, trimmed, optional: the
  choice alone is a valid answer). Switching away hides the field and discards its text.
- **Consent** is its own checkbox after the list, **off by default**: "Include my answer in anonymous
  statistics." It is not tied to the option chosen (a self-described or undisclosed answer can still
  be consented; an undisclosed answer with consent contributes only to the "not disclosed" count).
- **Continue** stays enabled. Pressing it with no option chosen shows the validation line (§5) under the
  group and announces it; it does not block on consent.

**Settings › Edit profile.**
- Row **"Gender"** showing the current value, "Prefer not to say", or "Not set" once cleared. Tapping
  opens the same selector as signup plus the consent toggle, with its current states.
- **Clear gender** (destructive-styled row below the selector) asks once: it removes the answer and any
  self-description **and turns consent off**. Save is the existing profile save; a failed save reverts
  the row (the screen already does this for other fields).
- Consent can be changed on its own here; turning it off is immediate and needs no confirmation.

**Nothing else.** No badge, no card, no public profile line, no filter, no sort, no seller tool reads it.

## 5. Copy (exact strings, proposed)
| Where | String |
|---|---|
| Field label | Gender |
| Helper under label | Helps us understand who uses Snatch It. Private, never shown on your profile. |
| Why link | Why we ask |
| Why sheet title | Why we ask about gender |
| Why sheet body | We use anonymous, grouped statistics to understand who Snatch It serves and to make sure the app works well for everyone. Your answer is private, is never shown to other users, and never changes what you see, what you can bid on, or how you buy, sell or transfer tickets. You can change or clear it any time in Settings › Edit profile. |
| Options | Woman · Man · Non-binary · Self-describe · Prefer not to say |
| Self-describe field | label "Describe yourself (optional)" · placeholder "Your words" · counter "0/40" |
| Consent checkbox | Include my answer in anonymous statistics |
| Consent sub-line | Only in groups of at least N people, never on its own. You can turn this off any time. *(N = D's suppression threshold; placeholder until D defines it)* |
| Validation | Choose one option. "Prefer not to say" is always fine. |
| Profile row, cleared | Not set |
| Clear confirmation | Clear gender? This removes your answer and turns off its use in statistics. · Clear · Keep |
| Save failure | the existing profile copy (unchanged) |

No string names an inferred or guessed value; none uses "Other".

## 6. Accessibility behaviour
- **Group semantics:** the list container has `accessibilityRole="radiogroup"` and label "Gender"; the
  helper is the group's `accessibilityHint` (read once, not per option). Each option is
  `accessibilityRole="radio"` with `accessibilityState={{ checked }}`, 44 pt minimum, label = the option
  text only.
- **Self-describe reveal:** no animation (layout change only, so Reduce Motion needs no case). When the
  field appears, focus moves to it (`AccessibilityInfo.setAccessibilityFocus`) and its label is read; when
  it is hidden by choosing another option, "Self-description cleared" is announced.
- **Validation:** shown under the group and announced with `announceForAccessibility`; on Android the
  line is a polite live region. Continue is never disabled, so a screen-reader user learns why the step
  did not advance.
- **Consent:** `accessibilityRole="checkbox"`, `accessibilityState={{ checked }}`, the full sentence as its
  label, the sub-line as its hint.
- **Why sheet:** a modal with a heading, closes on Escape / the close button; focus returns to the link.
- **Dynamic Type:** every string wraps; "Prefer not to say" never truncates; at the largest size the
  step scrolls with Continue docked (the sell-form keyboard/dock work applies). Verified on device
  (CFT-908), not by tests.
- **VoiceOver order:** heading → helper → Why we ask → the five options → self-describe (when shown) →
  consent → Continue.

## 7. Data-contract questions for A (before any schema)
1. **Shape:** a separate owner-only table (e.g. `profile_demographics`: `user_id`, `gender` enum
   `woman | man | non_binary | self_described | undisclosed`, `self_described` text ≤ 40 nullable,
   `analytics_consent` boolean, `consented_at`, `updated_at`) rather than columns on `profiles`, so the
   existing `profiles` select policies and `get_my_profile` (memory: profile embeds are not to be
   replaced) stay untouched and no public read path can ever include it. C has no preference beyond
   "never readable by another user".
2. **RLS:** owner select/insert/update/delete only; no anon or public policy; no admin row-level read —
   analytics only through an aggregate function (§8). Service-role exposure per the grant manifest.
3. **Cleared vs undisclosed:** proposal — *cleared* = row deleted (or all nulls, consent false);
   *Prefer not to say* = `undisclosed` with consent as chosen. A decides which representation the
   contract wants; the client shows "Not set" vs "Prefer not to say" accordingly.
4. **Retention:** life of the account. **Account deletion:** hard delete with the account (same path as
   the rest of the profile). **Export:** included in the user's data export as its own section.
   **Consent withdrawal:** no inclusion from that moment; aggregates already produced are not recomputed.
5. **Client write path:** through an RPC (like `get_my_profile`) or direct table write under RLS — A's
   call; the client never sends the value anywhere else (no analytics event carries it).
6. **Audit:** whether writes need the existing audit pattern.

## 8. Analytics questions for D
1. Dimension values: the five above, with **Self-describe shown only as the bucket "Self-described"** —
   the free text never leaves the row.
2. Suppression: minimum cell size (C proposes **≥ 20**), applied to every cut, including cross-tabs with
   venue, event, city or time bucket; suppressed cells render as "—", never as 0.
3. Consent filter: only `analytics_consent = true` rows count; "not disclosed" is its own bucket, not
   dropped, so denominators stay honest.
4. Opt-out behaviour: withdrawal removes the row from every future aggregate; no back-fill.
5. Access: dashboards read one aggregate function/view; no row-level query path exists in admin tools.

## 9. Task IDs (all *proposed*, none started; CFT-901 blocks the rest)
| ID | Item | Owner | Blocked by |
|---|---|---|---|
| CFT-901 | Data contract: shape, RLS, retention, deletion, export, account deletion, consent semantics | A (C supplies §7) | — |
| CFT-902 | Signup step 2: Gender radio group, self-describe reveal, validation, Continue behaviour | C | 901 |
| CFT-903 | Settings › Edit profile: Gender row, selector, Clear gender, consent toggle, revert on failed save | C | 901 |
| CFT-904 | Copy and the "Why we ask" sheet (§5), strings in a module for tests and previews | C | — (text can be reviewed now) |
| CFT-905 | Accessibility behaviour (§6): roles, focus moves, announcements, live region, Dynamic Type | C | 902, 903 |
| CFT-906 | Analytics dimension, suppression threshold, consent filter, dashboard treatment | D | 901 |
| CFT-907 | Tests: pure validation, source pins (field read only in signup/profile/read model), static preview | C | 902–905 |
| CFT-908 | Device rows DV-G1…G4: signup with each answer incl. large text and VoiceOver; edit; clear; consent off then on; plus the App Store 5.1.1 note in the release packet | C (owner on device) | a build |

## 10. Non-goals
No inference of any kind; no public display; no use in ranking, eligibility, pricing, checkout,
transfers or seller decisions; no free text in analytics; no third-party sharing.
