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
  consent off. Withdrawing consent stops analytics inclusion from that moment (D: aggregates are
  computed per request from current consent state, so it is immediate; a consent-off row counts in the
  "not disclosed" bucket, never dropped).
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
| Consent sub-line | Only in groups of at least 20 people, never on its own. You can turn this off any time. *(20 = D's threshold, CFT-906. This sentence is a promise the implementation must keep: it is true only with D's complementary suppression and fixed period buckets — if either is cut in review, this copy changes with it.)* |
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

## 8. Analytics questions for D — answered (CFT-906, D, 2026-09-16:
`docs/review/d-release-sprint/GENDER_ANALYTICS_TREATMENT_D.md` on `review/d-release-sprint @ 1698926`)
1. Dimension values: the five above, with **Self-describe shown only as the bucket "Self-described"** —
   the free text never leaves the row. **D:** agreed; `not_disclosed` absorbs three states — "prefer not
   to say", cleared, AND consent-off (dropping consent-off rows would expose "declined to say" vs
   "declined analytics" by subtracting two cuts); the free text must be **unreachable** by the aggregate
   layer (a derived column with no privilege on the text; "we don't select it" is not a control) — for A's
   CFT-901.
2. Suppression: **k = 20 adopted**, plus D's three additions: **complementary suppression** (when any cell
   is suppressed, the next-smallest is too, so subtraction yields only their sum), **fixed period
   buckets** (no free date picker — differencing two ranges isolates a day), and a **denominator floor of
   250** for a cut to publish at all. Suppressed cells render "—", never 0.
3. Consent filter: only consented rows count; every figure reads **"of respondents who consented
   (n = N)"**, never "of users" — a measured share, never a population estimate; the consent rate itself
   is shown beside the breakdown.
4. Opt-out: **every aggregate computed per request from current consent state, nothing cached** (the
   analytics contract already requires this), so withdrawal is immediate everywhere with no back-fill
   machinery; exports are frozen at generation and carry a timestamp and a "point-in-time, do not
   re-circulate" rule.
5. Access: **one SECURITY DEFINER function, `search_path=''`, returning already-suppressed rows** —
   suppression is server-side, never in the UI (raw counts in a network response are a leak).
6. Dashboard treatment (D §6): horizontal bars, not a pie; fixed category order, never sorted by size;
   "—" for suppressed; no time series by gender in v1; not a pink/blue palette (colour follows the
   entity; "Not disclosed" takes the neutral token because it is an absence, not a kind of person).
7. **D's flag (§0 of D's doc), for the owner:** nothing given so far names which *decision* this dimension
   informs. That bears on the 5.1.1 concern (a dimension nobody consumes is liability without benefit),
   and D cannot choose the right cuts without it. D recommends the owner name one or two concrete
   questions and that only those cuts are built. D proceeded with the full treatment regardless.

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
