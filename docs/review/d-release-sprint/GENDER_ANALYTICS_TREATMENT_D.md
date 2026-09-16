# CFT-906 — gender as an analytics dimension: treatment, suppression and dashboards (D)

**Status: PROPOSAL, 2026-09-16. Nothing implemented, no schema, no query run anywhere, no production
read.** Owner request of 2026-09-16, relayed to me by C; I am treating it as an assignment and will
confirm it directly with the owner at my next checkpoint. Blocked on **CFT-901** (A's data contract):
shape, RLS, retention, deletion, export and consent semantics come first — the definitions below assume
them and must be re-checked against whatever A lands. Companion to C's
`docs/product-v2/GENDER_PROFILE_DATA_PROPOSAL_C.md`; this answers C's §8 and adds what that section
does not yet cover. When CFT-901 settles, these definitions move into
`admin/docs/ANALYTICS_DATA_CONTRACT.md`, which is where changing facts live.

---

## 0. One thing to settle before any of this is built

The requirement says gender is "a key analytics dimension". Nothing I have been given says **which
decision it informs**. That matters more than the mechanics below, for three reasons: App Store
Guideline 5.1.1 asks whether the data is needed for the app to function (C's §3.1); a dimension nobody
consumes is pure liability, since the safest data is the data not collected; and I cannot design the
right cuts without knowing the question. My recommendation is that the owner name one or two concrete
questions — e.g. "does the buyer mix at a venue differ from the city's event-goer mix?" or "are
completion rates even across groups?" — and that we build only those cuts. If no decision can be named,
the honest engineering answer is to collect less, or to collect it later when a question exists.

I am proceeding with the full treatment as asked; this is a recommendation, not a refusal.

---

## 1. Dimension values (answers C §8.1: agreed, with one addition)

| Value | Source | Notes |
|---|---|---|
| `woman` | predefined | |
| `man` | predefined | |
| `non_binary` | predefined | |
| `self_described` | **bucket only** | the free text never reaches analytics — see below |
| `not_disclosed` | "Prefer not to say", a cleared value, **and** consent-off | an absence, not a category of person |

**The free text must be unreachable by the aggregate layer, not merely unselected.** If the aggregate
function can see the column, one careless `group by` exposes it. The dimension must be a separate
derived value (a generated column or an enum written alongside the text), and the analytics function
must have no privilege on the free-text column at all. "We don't select it" is not a control.

**Addition C's list does not have:** `not_disclosed` must absorb three different states — answered
"prefer not to say", answered then cleared, and answered with consent withheld. They must be
indistinguishable in every aggregate. If consent-off rows were dropped instead of bucketed, the
published denominators would silently exclude them and the difference between "declined to say" and
"declined analytics" would become visible by subtraction across two cuts.

---

## 2. Suppression (answers C §8.2 — agreed threshold, but the rule as drafted has a hole)

**Threshold: k = 20.** I am taking C's number; it is defensible for this population and it is a round
number a person can be told. What follows is what has to be true for that number to mean anything.

### 2.1 The hole: suppressing small cells is not enough
Five categories and a visible total means a single suppressed cell is recoverable by subtraction.
Publish Woman 340, Man 410, Non-binary 25, Self-described "—", Not disclosed 180, total 970, and the
suppressed cell is 15. The promise in the consent copy would be false the first time it was tested.

**Rule: complementary suppression.** Whenever any cell in a cut is suppressed, suppress the
next-smallest cell too, so at least two are hidden. Subtraction then yields only their *sum*, never
either one. Apply it within every row and every column of a cross-tab, iterating until no single cell
is isolable.

### 2.2 The second hole: differencing across filters
Arbitrary date ranges defeat any per-cell threshold: run a cut for Jan 1–31 and again for Jan 1–30 and
the difference is one day, which may be one person.

**Rules:** fixed, non-overlapping period buckets on any cut that includes gender — no free date picker;
the threshold is applied to the **cut actually queried**, never to a precomputed base that is then
filtered client-side; and no cut may combine gender with more than one other dimension.

### 2.3 The third hole: a mostly-suppressed table invites lowering k
If four of five cells read "—", the dashboard looks broken and someone will argue the threshold down.

**Rule: a denominator floor.** A cut is published only if its total consenting respondent count is at
least **250**; below that the whole cut renders "Not enough data to show this safely", not a table of
dashes. At current scale this means the top-level breakdown may be the only thing that ever publishes,
and venue- or event-level cuts may publish nothing for a long time. That is the correct outcome, and
saying so now is cheaper than arguing about it in front of a chart.

### 2.4 Suppression is server-side
The aggregate function must **never return a count below k**. If it returns raw numbers and the UI hides
them, the raw numbers are in the network response and in any client log. Suppression happens in SQL, and
the function returns the suppressed marker, not a number the caller is trusted to hide.

---

## 3. Consent filter and denominator honesty (answers C §8.3)

Agreed: only `analytics_consent = true` rows count, and `not_disclosed` stays as its own bucket.

**What C's draft does not yet say, and what I will enforce in every chart:** the population is
*consenting respondents*, not users. Two consequences.

1. **Labelling.** Every figure reads "of respondents who consented (n = N)" with the period. Never "of
   users", never "of buyers". A share presented against the wrong denominator is a wrong number, not a
   presentation choice.
2. **It is a measured share, never a population estimate.** Consent and disclosure rates almost
   certainly differ between groups, so the mix of respondents is not the mix of users, and no amount of
   sample size fixes that. Any chart or export carries that sentence. If someone wants to reason about
   the real population, this dimension cannot answer it and must not be used as though it could.

The consent rate itself is a legitimate and much safer metric — one number, no categories — and is worth
showing next to the breakdown so a reader can see how much of the population the breakdown speaks for.

---

## 4. Opt-out (answers C §8.4 — I propose a stronger rule than "no back-fill")

C proposes: withdrawal removes the row from future aggregates, no back-fill, no recomputation of
published aggregates. I would go further, and it is cheaper, not dearer.

**Every aggregate is computed per request from current consent state.** Nothing is precomputed or
cached across requests — a rule the analytics contract already imposes on `ops.*` and `venue_api` reads
for authorization reasons, and it does the privacy work here for free. Withdrawal then takes effect
everywhere the moment it happens, with no back-fill machinery and no stale published cell quietly
describing someone who left.

That leaves one genuine gap, which needs a rule rather than silence: **an exported file is frozen at the
moment of export** and cannot honour a later withdrawal. So exports carry the generation timestamp and
the same suppression, and the runbook says they are point-in-time and must not be re-circulated after a
reporting period. If the owner wants withdrawal to reach exports too, that requires an export register,
which I would rather not build unless asked.

Deletion is A's (CFT-901), but the analytics consequence is simple: account deletion removes the row,
and because aggregates are computed live, the next read no longer counts it.

---

## 5. Access path (answers C §8.5)

- **One `SECURITY DEFINER` function with `search_path = ''`**, returning already-suppressed aggregates.
  Nothing else in the console may read the column.
- `EXECUTE` to the console role only; **no grant of any kind** on the underlying table column to
  `anon`, `authenticated`, or the console's read role. Following this repo's four-file rule, adding it
  touches the grant-decision manifest, the Gate-2 census, `expected_grants.txt`, and a rollback that
  restores the applied body.
- **No row-level path in any admin tool**, and no filter combination that narrows to an individual: the
  denominator floor and the one-extra-dimension limit are what enforce that, so they belong in the
  function's signature, not in UI code.
- A negative control belongs in the test suite from day one: remove the suppression branch and a test
  must fail. A green test that never had a count below k in its fixture proves nothing — the fixture
  must contain a cell of size 1.

---

## 6. Dashboard treatment

**Form.** A single horizontal bar chart of the five categories, with the count and the share. Not a pie:
the job is comparing magnitudes across five items, one of which is an absence. Not a donut with a
number in the hole. At these cardinalities a plain bar chart plus a table twin is the whole design.

**Order and colour.**
- Fixed category order — Woman, Man, Non-binary, Self-described, Not disclosed — **never sorted by
  size**. A filter that changes the counts must not reorder or repaint the bars, or the reader loses the
  ability to compare two views.
- Categorical hues assigned by identity in fixed order from the design system, never cycled.
- **Not a pink/blue palette.** It encodes a stereotype, it breaks the rule that colour follows the
  entity rather than its meaning, and it fails the moment a third category exists.
- `Not disclosed` renders in the neutral/muted token, not a hue: it is an absence, and giving it a
  category colour implies it is a kind of person.
- Identity is never carried by colour alone — the legend is always present and the five bars are
  directly labelled.

**Suppressed cells** render as "—" with a footnote naming the threshold. Never `0`, never an empty bar,
never omitted from the axis: a missing row is indistinguishable from a zero row, and both misread as
"nobody".

**No time series by gender in v1.** A time axis multiplies the cells by the number of buckets, drives
every cell under the threshold, and opens the differencing attack in §2.2. If trend is genuinely needed
later, it is one line — consent rate over time — not five.

**One measure per chart, one axis.** Count and share are the same measure in two units and may share a
bar; anything else (completion rate, spend) is a separate chart, never a second y-axis.

**Every chart carries:** the exact period, the denominator, "of respondents who consented", the
suppression threshold, and the measured-share caveat from §3.2. A partial current period is labelled as
partial. A failed read is an error state, never zero.

---

## 7. What I need, and what I am not doing

Needed before CFT-906 can move: A's CFT-901 contract; the owner's answer to §0; and confirmation of the
two numbers I have chosen — **k = 20** (C's, adopted) and the **250 denominator floor** (mine).

**For C's consent copy:** the sentence "Only in groups of at least 20 people" works, and I would rather
it stayed that plain. But note what it becomes: a promise to the user that the implementation must
actually keep. It is only true with complementary suppression (§2.1) and the fixed period buckets
(§2.2). If either is dropped, the sentence has to change, because a recoverable cell makes it false.

Not doing, and not authorized to do: any migration, any query against production or the shared sandbox,
any schema work, any dashboard build. This document is a proposal.
