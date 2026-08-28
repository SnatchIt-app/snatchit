# Phase 2 — Demographics & Privacy Spec

**Status:** BUILD-READY DESIGN SPEC. **Design-only — NO SQL, NO migrations, NO implementation code.**
Illustrative fragments inside this document are prose aids, never files to copy.

**Scope.** The owner has approved capturing attendee gender information so venues and promoters can
understand event audience composition, with the explicit constraint: *"treat this as privacy-sensitive
product data … do not expose individual demographic attributes to venues unless explicitly required and
justified … prefer aggregate analytics where possible,"* and, from an earlier instruction in this
programme, *"do NOT treat this as permission to build invasive profiling."*

This spec's governing posture, stated once and applied everywhere below:

> **The venue's product need is "what kind of room did I sell." That need is fully served by a small number
> of bucket counts. It is never served by knowing which person is in which bucket. Therefore no code path,
> for any role, ever returns one identity's demographic value to another human — and the minimum viable
> collection is one field.**

Where a less invasive design delivers the same product value, this spec chooses the less invasive design and
says why in-line. Six such choices are called out as **[LESS-INVASIVE]**.

**Binding inputs (authority order).**

1. `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` (CDM) — §1.6 (`analytics` PII-minimized, k≥3 social
   precedent), §4 identity/erasure/deletion, §5 storage categories, §11 naming constitution.
2. `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` (DA) — §7.1/§7.2 role model, §7.6 permission matrix
   ("View buyer PII" row), §8.7 C34/C38, C10 (`attendance_visibility` default `only_me`, k≥3 floor).
3. `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` — **C34** (provable erasure,
   RATIFIED-MODELED-ONLY **GATE-L**, spec at Gate P) and **C38** (identity-merge grant reconciliation,
   GATE-L).
4. `docs/architecture/PHASE_2_SPEC_FOUNDATION.md` — §1 schemas (`analytics` **deferred, do not create**),
   §6 canonical table inventory, §8 Phase-0 security invariants.
5. `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` — §1.1 the 15 principals, §1.3 GP-1/GP-2, §6
   column-scoped read table, §2 C36 predicate helpers.
6. `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §9.5 — **the render contract for the
   "Ticket holder mix" card, already ratified.** This document supplies the storage, capture, and
   aggregation half that §9.5 marked `UNVERIFIED` and delegated.
7. Live Phase-0 precedent in `supabase/migrations/`: **042** (`get_my_profile()` SECURITY DEFINER own-row
   read), **052** (anon column restriction), **062** (authenticated column restriction), **068**
   (authenticated SELECT reduced to the public-safe set), **019/020** (anonymized-sentinel account deletion).

**Evidence labelling.** `VERIFIED:` = read directly from the repository in this session.
`INFERENCE:` = a design conclusion drawn by this document.

---

## 0. The precedent this design is built on (VERIFIED)

`VERIFIED:` migration 062's own header states the structural fact that determines this entire design:

> *"Column privileges in Postgres are per-role, not per-row, so a column granted to `authenticated` is
> readable on ANY row, not just the caller's own."*

`VERIFIED:` 068 therefore reduced `authenticated`'s SELECT on `public.profiles` to eight public-safe columns
(`id, display_name, avatar_url, avatar_path, bio, created_at, is_verified_seller,
stripe_onboarding_complete`), and 042 introduced `public.get_my_profile()` — `SECURITY DEFINER`,
`search_path` pinned, zero parameters, `WHERE p.id = auth.uid()`, `REVOKE ALL … FROM PUBLIC, anon,
authenticated` then `GRANT EXECUTE … TO authenticated` — as the only way an owner reads their own sensitive
fields.

`INFERENCE:` the demographic answer is strictly more sensitive than `wallet_balance`. So this spec applies
the 068/042 pattern **at its strongest setting**: the demographic table carries **zero column grants to
`anon` and `authenticated`** — not a reduced set, an empty set — and the only read is a parameterless
own-row `SECURITY DEFINER` RPC. There is no "public-safe subset" of a gender answer.

`VERIFIED:` no date-of-birth, birthdate, or age column exists anywhere in `supabase/migrations/` (grep for
`birth|dob|date_of_birth` returns zero hits). `public.profiles` has 21 columns, none of them demographic.
`VERIFIED:` `kernel.identity_ext` (schema spec §1.1) carries only `residency_region` and `kyc_ref`.

---

## 1. What is collected

### 1.1 The complete field list — one field

| # | Field | Type | Nullable | Value set | Justification |
|---|---|---|---|---|---|
| 1 | `gender_identity` | text + CHECK | yes (row absent = never answered) | `woman` · `man` · `non_binary` · `another_gender_identity` · `prefer_not_to_say` | The single stated owner requirement. Venues and promoters book talent, set door policy, price tables, and pitch sponsors against room composition; a five-bucket count answers that. |

Supporting columns on the same row, none of them demographic:

| Column | Purpose |
|---|---|
| `identity_id` | PK, `→ auth.users(id) ON DELETE CASCADE` |
| `notice_version` | which version of the disclosure text the person saw when they answered — the consent record |
| `first_answered_at` | when they first answered (product analytics on the prompt, never per-person) |
| `updated_at` | last change |

**That is the entire collection surface. One dimension. Five values. No free text.**

### 1.2 Value-set decisions and their reasons

- **No free-text "self-describe" box. [LESS-INVASIVE]** A free-text gender field is the highest-risk field
  this product could hold: it is unbounded PII, it is frequently a coming-out disclosure, it cannot be
  k-anonymized (a one-off string *is* an identifier), and it would have to be either suppressed on sight
  (making the box a lie) or shown (re-identifying the writer). `another_gender_identity` is offered as a
  first-class, equal-weight bucket instead. This delivers the venue's product value — a person outside the
  binary is counted — while collecting nothing that can single anyone out.
- **`prefer_not_to_say` is a real, stored answer, but it is never a reported bucket.** It exists so a person
  can close the prompt deliberately rather than be re-asked; see §1.3.
- **The absence of a row is a distinct state from `prefer_not_to_say` in the database, and an
  indistinguishable state everywhere else.** See §12 (the "optional means optional" proof).
- **The value set is closed and CHECK-constrained.** Adding a bucket is an additive amendment; adding a
  *dimension* requires a new `notice_version` and a fresh, separate opt-in (§3.4).

### 1.3 Why `prefer_not_to_say` is stored but never published

`INFERENCE:` if `prefer_not_to_say` were a published bucket, declining would become a visible, countable act
— a venue could watch "12 people refused" and treat refusal as a signal. Folding it into the non-response
denominator makes an explicit decline **byte-identical, at every readable surface, to never having opened
the screen.** That is the property that makes the answer genuinely optional (§12), and it costs the venue
nothing they can act on.

Concretely: `holders_responded` (the published `N`) counts rows whose `gender_identity` is one of the four
substantive values. `prefer_not_to_say` rows and absent rows both land in `holders_total − holders_responded`.

### 1.4 The NOT-collected list (and why)

Nothing below is collected, inferred, purchased, derived, or reserved as a column.

| Not collected | Why not |
|---|---|
| **Race / ethnicity** | Special-category data under GDPR Art. 9 and enumerated as sensitive under several US state regimes. In a venue-admission context it also creates a direct disparate-impact and discriminatory-door-policy exposure. No product need survives that. |
| **Sexual orientation** | Art. 9 special category. For a Miami nightlife marketplace this is a *plausible* venue ask and the answer is a flat no. Snatch It will not build the surface that lets a promoter count who is queer in a room. |
| **Religion · political opinion · philosophical belief · trade-union membership** | Art. 9. No product need. |
| **Health, disability, accessibility needs** | Art. 9, plus US health-adjacent statutes. If accessibility accommodation is ever built it is a **per-order operational request** attached to that order, consumed by box office, purged after the event, and it never enters demographics or any rollup. |
| **Biometrics / facial data / voice** | Art. 9, plus the BIPA/CUBI class of US statutes with private rights of action. The door verifies an asymmetric signed credential (C33), never a face. |
| **Date of birth / exact age** | `VERIFIED:` none exists today. A 21+ door check in Florida is performed against a government ID at the door by a human — the platform gains nothing by holding a DOB and takes on a minor-data and identity-theft liability by holding one. See §1.5 for the `age_band` option. |
| **Precise geolocation, location history, device location** | Not needed for room composition; a location trail is re-identifying on its own. `preferred_neighborhoods` (existing, migration 015) is a *discovery preference the fan sets*, is not demographic, and is explicitly out of every rollup in this spec. |
| **Immigration status, citizenship, national origin** | Special-category or near-adjacent everywhere; catastrophic misuse potential; no product need. |
| **Income, occupation, employer, education** | Classic profiling attributes. Not needed to describe a room. |
| **Marital / relationship / parental status** | Same. |
| **Any inferred demographic** | **No model or heuristic ever infers gender** from a first name, an avatar, a purchase pattern, a social graph, or a photo. `INFERENCE:` inferred demographics are simultaneously the least accurate and the least consented data a platform can hold, and they defeat the entire "self-described" premise. |
| **Any third-party demographic append** | No data broker, no enrichment vendor, no CDP-side append, no ad-platform lookalike inference written back. |
| **Household / co-attendee inference** | Deriving one person's attributes from who they transfer tickets to is profiling by another name. |

### 1.5 The `age_band` option — specified, not built

`INFERENCE:` age is the most likely second ask, so its shape is fixed here to prevent an ad-hoc future
decision. If the owner later approves it:

- Field: `age_band`, value set `18_20` · `21_24` · `25_34` · `35_44` · `45_plus` · `prefer_not_to_say`.
- **Bands only. Never a date of birth, never a year, never a derived integer age.** A band is what the
  product uses; a DOB is what an attacker uses.
- It is a **new dimension**, so per §3.4 it requires a new `notice_version` and its own opt-in — answering
  gender must never silently enrol someone in age.
- It inherits every rule in §5 unchanged (same k, same floor, same one-dimension-at-a-time rule; it may
  never be crossed with gender).

**Owner decision D-3 (§13).** Not in Phase 2.

---

## 2. Capture surfaces

### 2.1 Signup: nothing. [LESS-INVASIVE]

**No demographic question appears at signup, at first launch, at onboarding, or anywhere in a purchase
flow.** `INFERENCE:` three reasons, in order of weight:

1. **Consent at signup is not freely given.** The person is mid-task and wants a ticket; a field placed
   there is answered under practical compulsion even when technically skippable. That is the exact defect
   that makes a consent record worthless later.
2. **A signup field reads as mandatory** no matter how it is labelled. Everything on a signup form looks
   required; "optional" markers do not survive user perception.
3. **It measurably suppresses signup completion**, so the business pays for data it should not be taking
   there anyway.

### 2.2 The only capture surface: optional profile enrichment

`NEW RN SURFACE` — one card, one screen, one control.

- **Where:** the fan's own Profile / Settings area, alongside existing self-service (`app/(tabs)/profile.tsx`
  neighbourhood). Never on Home, never on the Event page, never on the Tickets tab, never on a ticket.
- **Entry point:** a dismissible card. Card title: *"About you (optional)"*.
- **The screen:** the question, five equal-weight options, a Save control, and — once answered — a
  **Remove my answer** control on the same screen, at the same level of prominence as Save.
- **Prompt frequency:** at most **once per 90 days**, and **at most 3 surfacings ever** if dismissed each
  time. After the third dismissal the card never returns; the screen remains reachable from Settings for
  anyone who later wants it. `INFERENCE:` a prompt that keeps coming back is a soft coercion mechanism, and
  three tries is generous.
- **Never surfaced:** between "Pay" and "here is your ticket"; over a live ticket; while a transfer or
  listing is in progress; in a push notification; in an email.

### 2.3 The UX principle, and the dark patterns that are banned

**Principle: the fan must be able to say nothing, twice — once by dismissing, once by choosing
`prefer_not_to_say` — and be materially no worse off either time.**

Explicitly banned on this surface:

| Banned | Why |
|---|---|
| Any pre-selected default | A pre-checked answer is a fabricated consent record. |
| Asymmetric affordances (a filled "Share" button vs a grey text "Not now") | Visual weight is a coercion channel. All five options and both actions are typographically equal. |
| Burying `prefer_not_to_say` below a fold or behind "more options" | It is the fifth option in the same list, same size, same colour. |
| Any reward, discount, credit, priority, badge, or perk for answering | Paying for a special-category-adjacent disclosure invalidates consent *and* poisons the data (people answer to get the perk). **[LESS-INVASIVE]** |
| Any penalty, degraded experience, or withheld feature for not answering | §12 proves there is none. |
| A profile-completeness meter, a "your profile is 80% complete" nag, or a red dot | A manufactured sense of obligation is the same coercion with better manners. |
| "Most people share this" / social-proof framing | Normative pressure applied to a protected attribute. |
| Re-asking after an explicit `prefer_not_to_say` | That answer is honoured permanently; only the fan reopens it. |
| Interstitials, full-screen takeovers, or anything that must be dismissed to proceed | It is never on a critical path. |

### 2.4 Prompt copy (exact, binding)

Rendered copy is only the quoted strings. Follows the DA/RN product-language rule: no architecture terms.

> **About you (optional)**
>
> Venues see a summary of who's holding tickets to their events — never your individual answer, and never
> your name next to it.
>
> **How do you describe your gender?**
> ○ Woman  ○ Man  ○ Non-binary  ○ Another gender identity  ○ Prefer not to say
>
> We only show a venue a breakdown once at least 25 ticket holders for that event have shared. You can
> change or remove this any time in Settings. We don't sell this, and it never leaves Snatch It attached to
> your name.
>
> [ Save ]   [ Not now ]

Confirmation after Save:

> *"Saved. You can change or remove this any time in Settings."*

After Remove:

> *"Removed. Your answer is deleted and won't be counted in any new summary."*

---

## 3. Consent and notice model

### 3.1 The legal basis is left to counsel; the design survives the strict answer

`INFERENCE:` this document is not the compliance authority. Two determinations belong to the owner and
counsel (see §13, D-1 and D-2): **which regimes reach a Miami-based marketplace whose fans include EU/UK
visitors and California residents**, and **whether gender identity is special-category / "sensitive personal
information" under those regimes.** GDPR Art. 9 does not name gender identity verbatim; some supervisory
authorities and some US state statutes treat it as sensitive; this document asserts no conclusion.

**The design is built so that the strictest plausible answer requires no redesign**: the capture is an
affirmative, unbundled, granular, freely-given opt-in with a versioned notice, a one-tap withdrawal, and no
detriment for refusal — which satisfies an Art. 9(2)(a) explicit-consent posture without depending on it.

### 3.2 What is recorded as the consent record

`notice_version` on the demographic row, plus `first_answered_at`. That is the whole record. The notice text
for every version is kept in the repository (`catalog.platform_config`-adjacent, versioned in git) so
"what did this person actually read" is answerable without storing a copy per person.

`INFERENCE:` a per-person consent-event ledger was considered and **rejected [LESS-INVASIVE]** — it would
accumulate a timestamped history of a person's engagement with a gender question, which is a worse artefact
than the answer itself. §8.3 forbids demographic history categorically, and this is the same rule.

### 3.3 What the user is told, in plain words

Four claims, all of which this spec makes true:

1. **Purpose** — "so venues understand who's coming to their events."
2. **Aggregate only** — "shown as a group total, never your individual answer, never beside your name."
3. **Threshold** — "only when at least 25 ticket holders for that event have shared."
4. **Control and non-sale** — "change or remove any time; we don't sell it; it never leaves Snatch It
   attached to your name."

**Not said, deliberately:** no regime names, no "GDPR-compliant", no "erased forever". Per C34, no
GDPR/CCPA erasure claim may be made before C34 is implemented, and C34 is **GATE-L**. §8.5 gives the honest
sentence that replaces it.

### 3.4 Consent versioning rules

| Change | Effect on existing consent |
|---|---|
| Copy edit that does not change meaning | New `notice_version`, existing answers stand. |
| **Adding a bucket** to `gender_identity` (e.g. a sixth option) | New `notice_version`, existing answers stand — the question is unchanged, the answer space widened. |
| **Adding a dimension** (e.g. `age_band`) | **Fresh, separate opt-in required.** Answering gender never enrols anyone in age. The new dimension starts with zero responses. |
| **Widening who sees the aggregate** (a new role, a new surface) | New `notice_version` and an in-app notice to everyone who has answered, with a one-tap path to remove. |
| **Any individual-level disclosure** | Forbidden by §7. There is no consent version that unlocks it. |

---

## 4. The canonical analytics semantic — DECIDED

The owner asked this document to decide it. For a transferred or resold ticket, three candidate subjects
give materially different numbers.

### 4.1 The decision

> **CANONICAL: `holder_mix` — the distinct identities that hold custody of at least one non-voided ticket
> for a given `catalog.event_session`, evaluated as of a named snapshot instant `as_of`.**
>
> Formally: `DISTINCT kernel.tickets.current_owner_id` over the rows where
> `event_session_id = :session AND state <> 'voided'`, at time `as_of`, **restricted to R7-eligible custody**
> (§5.2 — the ownership-log head cause is not `comp`, and the atom's issuance was not zero-price).
> The counting unit is **the person, not the ticket** — a fan holding four tickets is one holder.
> The rollup is `(event_session, dimension, bucket) → holder_count`, and nothing finer exists anywhere.

`INFERENCE:` the eligibility restriction is a **privacy** qualifier, not a product one — see §5.2's
"Why R7 exists". It is stated here rather than only in §5 so that nobody reads the canonical definition alone
and implements the unrestricted population.

The two rejected semantics keep reserved names so they can never be conflated if either is ever added:

| Name | Definition | Status |
|---|---|---|
| **`purchaser_mix`** | grouped by `venue.order.buyer_id` — the original purchaser. | **NOT BUILT. Not reserved for MVP.** |
| **`admitted_mix`** | grouped by the identity holding the ticket at the moment of an `admitted` `venue.scan`. | **NOT BUILT.** Named extension point only; requires package 086. |

### 4.2 Why `holder_mix`, defended against each alternative

**Against `purchaser_mix`.** It is simply wrong about people. One person buying a table of six is *one*
purchaser, and grouping by buyer either counts them once (erasing five attendees) or six times (a single
person's gender contributing six units to the chart). Every transfer and every resale makes it staler.
It answers "who paid", which is a *finance* question already answered by the settlement surfaces, and the
venue asking about room composition is not asking it.

**Against `admitted_mix`.** It is the only semantic that describes who was actually in the room — and it is
rejected as canonical for four reasons, in order:

1. **It is empty when the decision is made.** A venue books talent, sets door policy, and closes sponsor
   deals *before* doors. A metric that reads zero until 11pm on the night is not the metric the product
   exists to serve.
2. **It is systematically incomplete.** No-shows, un-scanned guests, comped walk-ins, and any offline-scan
   reconciliation gap (C37: offline is honestly *shrunk*, not closed) all bias it, and the bias is
   invisible in the chart.
3. **It is the most re-identifying of the three, structurally.** It requires joining a demographic value to
   a *scan event*, which carries a timestamp, a device, and a door. A scan timeline plus a rare bucket is a
   person. `holder_mix` reads only the custody head — no time, no place. **[LESS-INVASIVE]**
4. **It creates a live in-room demographic count**, which is a surface a door team could act on in the
   moment. That is precisely the "invasive profiling" the owner ruled out.

**For `holder_mix`.** It is well-defined at every instant including before doors; it is a pure function of
the custody head that the kernel already maintains authoritatively; it needs no join to scans, orders,
promoters, prices, or time; it counts people rather than tickets, matching the ratified card subtitle; and
it is correct through transfers and resales by construction — custody is the thing that moved.

### 4.3 What the dashboard shows before doors (binding)

Before doors, the card shows the **latest published `holder_mix` snapshot**, and the header line names its
`as_of` so nobody reads it as a live in-room count.

> Subtitle (already binding, dashboard §9.5): *"Based on N of M ticket holders who shared this. One person
> can hold more than one ticket, so this counts people, not tickets."*
>
> Added by this spec, always rendered beneath it: *"As of {as_of, e.g. 'Fri 6 Sep, 9:00 AM'}. This is who
> holds tickets — not a door count."*

**Two binding corrections to that copy (`SPEC CORRECTION` to dashboard §9.5).**

1. **`N` and `M` render only when the snapshot published.** Per R6 (§5.2) a suppressed snapshot returns the
   single boolean `suppressed: true` and carries no denominators, so the "Based on N of M" string is a
   published-state string. The suppressed state renders the suppressed copy **and no numbers of any kind** —
   not a total, not a response count, not a reason, not an `as_of`.
2. **`M` is the eligible population, not the room.** Per R7 comped and zero-price custody is excluded, so `M`
   is not "everyone holding a ticket" and must not be captioned as if it were. The subtitle's second sentence
   gains: *"Counts people who bought a ticket to this event."*

After doors, the card continues to show the last published `holder_mix` snapshot, unchanged and still
`as_of`-stamped. **The card never becomes a door count**, and the words "attendee", "audience", and
"demographics" remain banned from it per §9.5. `INFERENCE:` letting the card silently switch meaning at
doors-open would be the worst outcome — an operator would compare a pre-door number to a post-door number
that measured a different population.

### 4.4 Snapshot lifecycle

`holder_mix` is recomputed on a schedule (§5.4), each recomputation producing a candidate snapshot that is
**published or discarded** by the rules in §5. After the event session ends, the last published snapshot is
final and is retained per §8.4. Historical snapshots are **never client-readable** (§5.3, defence 3).

---

## 5. Aggregation model

### 5.1 The only rollup that exists

**One shape, no variants:**

```
venue.holder_mix_snapshot   (event_session_id, dimension, as_of, holders_total, holders_responded, …)
venue.holder_mix_bucket     (snapshot_id, bucket, holder_count)
```

There is **no ticket-type axis, no promoter axis, no source axis, no price axis, no time-of-purchase axis,
no scan-status axis, no session-crossing axis, and no cross-event "unique people across my events"
rollup** — not as a column, not as a filter, not as a stored variant, not as a parameter. This is the
differencing defence and it is discussed in §5.3.

`dimension` is CHECK-constrained to `gender_identity` in Phase 2.

**The population is not "everyone holding a ticket" — it is R7-eligible holders only (§5.2).** Every
occurrence of "holder", `holders_total` and `holders_responded` below means the R7-eligible set.

### 5.2 Minimum cell size and suppression — enforced in the database

Adopting the ratified dashboard §9.5 thresholds, and closing the gaps that render-side rules cannot close.

`INFERENCE:` **the correction that produced R7–R9.** R1–R6 as originally written floor the *cells* of a
distribution but say nothing about *who is in the population the distribution is computed over* — and at this
product the operator controls that population. A `venue_manager` mints sessions and mints comps, both at zero
marginal cost. Every k-anonymity argument in this section is an argument about an adversary who observes a
population; it is void against an adversary who **composes** one. R7 removes the free contributor, R8 makes
the churn bound quantify over answers rather than membership, and R9 stops two near-identical populations
from being published side by side. §5.3 states honestly what remains uncovered.

| Rule | Value | Where enforced |
|---|---|---|
| **R1 — event minimum** | `holders_responded >= 25` (k = 25) | Rollup writer refuses to publish; snapshot persisted as `suppressed`, zero bucket rows. |
| **R2 — per-bucket floor** | every persisted bucket `holder_count >= 5` | **A `CHECK (holder_count >= 5)` constraint on `venue.holder_mix_bucket`.** A sub-floor bucket is not merely hidden — it **cannot physically be stored.** |
| **R3 — mandatory merge** | the fully determined algorithm below | Rollup writer. |
| **R4 — completeness (the complement rule)** | `SUM(bucket.holder_count) = snapshot.holders_responded`, always | Writer assertion + read-side re-derivation (§10.4) + nightly reconciliation job (the C27 counter-vs-ledger pattern) + pgTAP assertion 16. |
| **R5 — all-or-nothing** | if R3 cannot produce **at least two** persisted buckets each ≥ 5 summing to `holders_responded`, the snapshot is `suppressed` and **zero** bucket rows are written | Rollup writer. |
| **R6 — denominator suppression** | a `suppressed` snapshot publishes **no `holders_total`, no `holders_responded`, and no reason** to any client | Rollup writer stores them; `venue.get_holder_mix` never emits them (§10.4). |
| **R7 — population eligibility** | a holder is counted only if their custody of the atom was acquired **for consideration**: the ownership-log head cause is not `comp`, and the atom's issuance was not zero-price | Rollup writer. |
| **R8 — publication churn gate, over the contributor multiset** | see §5.3 defence 4 | Rollup writer. |
| **R9 — cross-session near-duplicate gate** | see §5.3 defence 7 | Rollup writer. |

**R3, fully determined.** The previous wording ("buckets below the floor are merged into `other`, smallest
first, repeating until `other >= 5`") is under-determined and its two worked examples contradicted it — the
40-person example merges `man = 5`, which is *not* below the floor, while the 23/1/1 example stops before
doing the same thing. The algorithm is therefore stated as an ordered procedure with no discretion left in it:

```text
1. Start from the raw counts of the four substantive buckets. other := 0.
2. While some NAMED bucket has a count in [1,4]:
       move the smallest such named bucket (ties: alphabetical) into other.
3. If other is now in [1,4]:
       while other < 5 and at least one NAMED bucket remains:
           move the smallest remaining named bucket (ties: alphabetical) into other.
4. Persist iff: at least TWO buckets remain, every one is >= 5, and they sum to
   holders_responded. Otherwise SUPPRESS with zero bucket rows (R5).
```

Step 3 is the step the old prose omitted, and step 4's **two-bucket minimum** is what makes the two worked
examples agree. `INFERENCE:` a single-bucket chart (`{other: 26}`) is not a privacy leak in itself, but its
*existence* announces that the distribution was skewed enough to collapse — the same distribution-shape
disclosure that R6 removes from the suppression reason. A card that would render one bar renders nothing.

**Why R4 is not optional.** The card publishes `N` (`holders_responded`) whenever it publishes at all. If
suppressed buckets were simply omitted, the residual `N − Σ(shown)` would be computable — suppressing a single
small bucket would *hand over* its exact count. Mandatory merge into `other` means the published set always
sums to `N` and there is no residual to compute. R5 is the corollary: when merging cannot reach a legal set,
the whole dimension suppresses rather than leak.

**Why R6 exists — the finding it closes.** The suppressed projection previously returned
`{suppressed, reason, holders_total, holders_responded}` with **no floor on the denominators**. A
`venue_manager` could create a throwaway session, comp one ticket to a target, and read `holders_responded`:
`1` means that person gave a substantive answer, `0` means they did not. That is exactly the
"shared demographics: yes/no" artefact X-4 bans, reachable from the read path the spec itself specifies. A
suppressed snapshot now returns the single boolean `suppressed: true` and nothing else — no denominators, no
reason, no `as_of`. The card's "Based on N of M" copy is a **published-snapshot-only** string (§4.3).

**Why R7 exists.** A comp costs the venue nothing, and the same `venue_manager` mints both the session and the
comps. Any bound of the form "an inferable group is at least 5 people" assumes those 5 people are not
manufactured. R7 removes the zero-cost contributor: comped custody, and custody issued at zero price, are
excluded from `holders_total` and `holders_responded` alike, so a contributor to the published distribution
always cost someone real money.

**Consequences of R7, stated honestly.** (a) A genuinely free event — no paid tier at all — never renders the
card, because every holder is ineligible. That is the correct outcome (at a free event the operator can mint
the entire population, so no anonymity bound holds at all) and it is a real product loss. **Owner decision
D-12 (§14).** (b) `holders_total` is therefore **not** the count of everyone in the room, and the card's
denominator is the eligible population, not attendance. §4.3's copy is amended accordingly. (c) The roster
surface in the CRM spec counts *all* holders; the two numbers legitimately differ and the CRM spec's
non-contradiction assertion is restated to compare like with like.

**Worked example — the 40-person event from the brief.** 40 holders, of whom 38 are R7-eligible (two were
comped); 26 of the eligible responded: 20 `woman`, 5 `man`, 1 `non_binary`. R1 passes (26 ≥ 25). R2 fails for
`non_binary` (1 < 5). R3 step 2 moves it: `other` = 1. R3 step 3 fires because `other` ∈ [1,4]: the smallest
remaining named bucket (`man`, 5) moves in, `other` = 6. Step 4: two buckets, both ≥ 5, summing to 26 →
persist `woman = 20`, `other = 6`. The single non-binary holder is inside a bucket of six and the venue cannot
tell whether `other` contains one, six, or any mix.

Had the split been 25/1: step 2 gives `other` = 1; step 3 pulls `woman` (25) in, `other` = 26; step 4 finds
**one** bucket → **R5 suppresses the entire card**, and R6 means the operator is told only that it is
suppressed. Same for 23/1/1.

**What is enforced where — corrected, because the previous claim was false.** The spec previously said
"removing any one of layers 1–3 still leaves a correct floor". It does not, and the reason is worth stating
because it is the kind of claim a reviewer stops checking once it is written down: layers 1 and 3 were **the
same function** — the writer decides what to persist, and the RPC "can only return what exists" is not an
independent check, it is a restatement of the writer's decision. Only R2 was ever a database constraint.
The honest table, and the read-side re-derivation that makes the claim true where it can be made true:

| Rule | Writer | Database constraint | Read-side re-derivation (§10.4) | Reconciliation job |
|---|:--:|:--:|:--:|:--:|
| R1 event minimum | ✔ | ✗ (a snapshot's own counters are not a cross-table constraint) | **✔ — `get_holder_mix` refuses to emit buckets unless `holders_responded >= 25` on the row it read** | ✔ |
| R2 bucket floor | ✔ | **✔ `CHECK (holder_count >= 5)`** | **✔ — refuses to emit if any returned bucket < 5** | ✔ |
| R3 merge | ✔ | ✗ | ✗ (not re-derivable without the raw counts, which are not stored) | ✗ |
| R4 completeness | ✔ | ✗ | **✔ — refuses to emit unless `Σ holder_count = holders_responded`** | ✔ |
| R5 all-or-nothing | ✔ | ✗ | **✔ — refuses to emit fewer than two buckets** | ✔ |
| R6 denominator suppression | ✔ | ✗ | **✔ — the RPC's suppressed branch physically has no denominator field to fill** | n/a |
| R7 eligibility | ✔ | ✗ | ✗ (the eligible set is not retained; see §8.4) | ✗ |
| R8 / R9 gates | ✔ | ✗ | ✗ | ✗ |

`INFERENCE:` "the read re-derives what it can from the row it is about to return, and refuses rather than
degrades" is a genuinely independent second layer for R1/R2/R4/R5/R6 — it fails closed against a writer bug,
a manual `INSERT`, a restored-from-backup row, and a future migration that back-fills. R3, R7, R8 and R9 are
writer-only and this document says so rather than implying otherwise; they are covered by the reconciliation
job where the job can see them and by pgTAP where it cannot. **The UI is never the enforcement, at any layer.**

### 5.3 Differencing defence — pre-computed fixed rollups, chosen and defended

Three options were available. The choice is **pre-computed fixed rollups** (option B), with a churn gate for
the temporal axis.

**A — Query-shape restriction (rejected as the primary defence).** Allowing a general aggregate query and
policing its shape at the RPC boundary is fragile: it survives only as long as every future engineer
resists adding "just one filter", and the failure is silent — a `p_ticket_type` parameter added in good
faith reopens every intersection at once. Defence-in-depth keeps the RPC's two-argument shape (§10.3), but
it is not what the safety rests on.

**C — Noise / differential privacy (rejected).** At the real population sizes here — n ≈ 25 to a few
hundred per session — the noise required for a meaningful ε swamps the signal, and the venue is handed a
chart that is mostly perturbation while *believing* it is data. Worse, DP is only sound with a maintained
privacy budget across repeated queries; a venue dashboard read daily by five staff for six months has no
plausible budget accounting, and an unaccounted DP system provides confidence without protection. Noise is
the wrong tool for small-n operational reporting.

**B — Pre-computed fixed rollups (CHOSEN).**

> **The axes an attacker would difference across do not exist.** The only materialized demographic aggregate
> is `(event_session, dimension, bucket) → count`. There is no per-ticket-type number, no per-promoter
> number, no per-time-window number, and no per-scan-status number anywhere in the database, in any view, in
> any cache, in any export, or behind any parameter. **Those** intersections are not blocked at a policy
> layer — their operands are absent.

**Scope of that claim, stated because the previous wording overstated it.** The spec previously headlined this
as *"you cannot difference aggregates that do not exist"* and let the sentence stand as the answer to
differencing in general. **That claim is deleted.** It is true about **axes** and false about **populations**:
the `(session, dimension, bucket)` aggregate very much exists, one instance of it exists per session, and an
operator who can compose two populations — by minting a session, by minting custody, or by choosing which two
of their own sessions to compare — differences two aggregates that both exist. Fixed rollups are a defence
against slicing, not against an adversary who controls the input set. Vectors 4, 6 and 7 below are the
population-side defences, and vector 7 records what is still not covered.

This defence is structural rather than procedural for the axis case, which is the property the constitutions
favour (C36's "type error, not a lint finding"). It composes with the residual vectors:

1. **Ticket-type differencing** — no ticket-type rollup exists. The dashboard's one-dimension rule (§9.5)
   means there is no second axis control to build against, and there is no second axis to build.
2. **Promoter differencing** — no promoter-scoped rollup exists, and §6 denies the promoter axis to
   `promoter_manager` as well, precisely because a promoter-attributed sub-population is usually far below
   k = 25 and would be intersectable against the event total.
3. **Scan-status differencing** — `admitted_mix` is not built (§4.1). There is no demographic × scan join
   anywhere.
4. **Temporal differencing (the one people miss).** Even with a single fixed shape, an observer who records
   Tuesday's chart and Wednesday's chart differences the two. If `holders_total` went 25 → 26, the bucket
   that moved by 1 identifies the new holder's answer.
   **Defence R8 — the publication churn gate, over the contributor multiset.** The previous rule gated on
   ≥ 5 changes of **membership**, which quantified over the wrong set: the buckets track **answers**, and a
   stable member who edits their answer moves a bucket by 1 while causing zero membership churn. So a
   `venue_manager` watching a 300-holder session sees a clean ±1 every time one person changes their mind.
   The gate is therefore redefined over the object the buckets are actually a function of:
   > Let `C(s)` be the **contributor multiset** of candidate/published snapshot `s`: the set of pairs
   > `(identity_id, post-merge bucket)` for every R7-eligible holder with a substantive answer at `s.as_of`.
   > **Churn** between two snapshots is `|C₁ △ C₂|` — the symmetric difference over *pairs*, so a member
   > entering contributes 1, a member leaving contributes 1, and **a member changing their answer
   > contributes 2**. A candidate publishes only if churn ≥ 5 against the last published snapshot for the
   > same `(session, dimension)`; otherwise the previous snapshot stands and the recomputation is discarded.
   **The bound this buys, stated exactly:** any observable change between two published snapshots is the
   aggregate effect of ≥ 5 contributor-pair changes, so a bucket delta of +1 attributes to one of at least
   three distinct people (5 pair-changes is at minimum 3 people, since an answer change costs 2). **The
   anonymity set is ≥ 3 people, not ≥ 5** — the earlier text claimed 5 by conflating pairs with people, and
   that claim is deleted. To restore 5, the gate is stated as **churn ≥ 5 pairs **and** ≥ 5 distinct
   identities appearing in `C₁ △ C₂`**, which is the form the writer implements and pgTAP asserts.
   `C(s)` is computed by the writer and **is not stored** (§8.4): the comparison is made against `C` of the
   previous published snapshot, recomputed at that snapshot's `as_of` from the ownership log plus the *current*
   answer table. The consequence — a member who both changed their answer *and* was compared against a
   recomputed past — is stated in vector 7.
5. **Historical time-series access** — there is none. `venue.get_holder_mix` takes no `as_of` and returns
   exactly one snapshot: the latest published one. There is no history endpoint, no "compare to last week",
   no trend line, and no export (§9). An observer must therefore poll and record by hand, which is
   rate-limited and audited (§11).
6. **Cross-event intersection.** An org running many events can intersect the holder sets of two events it
   can see — and, per the CRM spec's roster surface, it can see those holder sets **by name**. Each event's
   chart independently obeys k = 25 and floor 5, so the smallest inferable group remains ≥ 5 — but they are
   **5 people the operator can name**, not 5 unknowns. The bound is a group bound, never an anonymity bound
   in the colloquial sense, and §11's row is corrected to say so.
7. **Population differencing — the operator composes the input set (the vector this design does not fully
   close).** Two sessions of the same venue whose eligible-holder sets differ by one person yield that
   person's exact answer by subtraction, with **every bucket ≥ 5 on both sides**, so no floor binds and no
   temporal gate fires — the two snapshots are not in the same series. R7 makes the differing member cost a
   real ticket at a real price rather than a free comp, which raises the price of the attack without bounding
   it.
   **Defence R9 — the cross-session near-duplicate gate.** A candidate snapshot for session `S` does not
   publish if the symmetric difference of its **R7-eligible holder set** and that of any other currently
   published snapshot on a session reachable by the same venue **or** the same org is < 5 distinct identities.
   Eligible holder sets are reconstructible at any past instant from `kernel.ticket_ownership_log` (§5.4), so
   R9 needs no new stored object and no retained identity reference.
   **What R9 bounds and what it does not — the acknowledged gap.** It bounds differencing driven by
   *membership*: two near-identical rooms cannot both render. It does **not** bound differencing driven by
   *answers* among stable members across sessions, because answers are deliberately not historied (§8.3) and
   a responder set is therefore not reconstructible at a past instant. An operator running the same 300
   regulars weekly, holding the roster by name, and diffing week over week retains a real inference channel
   whose size this document cannot state as a number. **It is recorded as an open gap, not as covered.**
   The Phase-2 mitigations are R8's ≥ 5-identity churn gate within a series, R9 across series, the 24-hour
   recompute cadence, the audited and rate-limited read (§11), and the kill switch (§5.5). **Owner decision
   D-13 (§14)** asks whether that is enough for the sessions-per-venue-per-week rates this product actually
   sees, and names the two levers if it is not: raise k, or take the card off repeat-audience venues.

### 5.4 Refresh cadence and the writer's read set

- Recompute per open `event_session` **at most once per 24 hours**, plus one recomputation at doors-open.
- Each recomputation is published or discarded by R1–R9. A discarded recomputation leaves no row.
- The job is a `pg_cron`-invoked `SECURITY DEFINER` RPC (§10.3), `service_role`/definer EXECUTE only.
- **No edge function.** `INFERENCE:` keeping the entire computation inside Postgres means the demographic
  value never crosses a process boundary — no HTTP body, no function log, no error breadcrumb, no
  observability payload. That is a deliberate, checkable contribution to C34's future PII-sink inventory
  (§8.6).

**The declared read set, corrected.** R8 and R9 compare against holder sets at a *past* instant, and the
previously declared read set (`kernel.tickets` ⋈ `kernel.identity_demographic`) holds only the custody
**head** — from which no past instant is computable, so the churn rule as written was not computable from the
data the writer was declared to read. The writer's read set is therefore:

| Relation | Why |
|---|---|
| `kernel.tickets` | the custody head and `state <> 'voided'` filter for the current candidate |
| `kernel.ticket_ownership_log` | **added.** Reconstructs the eligible-holder set at a past `as_of` (R8's previous-snapshot comparison, R9's cross-session comparison) and supplies the head **cause** that R7 filters on |
| `venue.order` / `venue.order_item` | **added, price only.** R7's zero-price test, reached through the issuance entry's `cause_ref`. No buyer identity is read, no total is retained |
| `kernel.identity_demographic` | the answers |
| `venue.holder_mix_snapshot` | the last published snapshot for R8, and every currently published snapshot in scope for R9 |
| `catalog.event_session`, `catalog.event`, `catalog.venue` | the session anchor, and the venue/org reachability set R9 quantifies over |
| `catalog.platform_config` | the §5.5 kill switch and the k/floor constants if D-5 makes them configurable |

**Still not read:** `venue.scan`, `venue.attribution`, `venue.ticket_type`, `public.profiles`, any price
beyond the zero/non-zero test, and any identity outside the session's own holders.

### 5.5 Kill switch

`INFERENCE:` stopping the cron is not a kill switch. It stops *new* snapshots while every venue keeps reading
the last published card, forever — so the one lever an operator would reach for during an incident is the one
lever that does not work, and it fails in the direction of continued disclosure.

**`catalog.platform_config` key `demographics.holder_mix_enabled` (boolean, seeded `true`), read live by
`venue.get_holder_mix` on every call.** When false, the read returns `{ suppressed: true }` for every session
regardless of what is stored — no denominators, no buckets, no `as_of`. It is a **read-path** switch, not a
writer switch, which is the whole point: it takes effect on the next call, needs no deploy, needs no cron, and
does not depend on the writer running.

Two companions, both definer-only:

- **`venue.unpublish_holder_mix(p_event_session_id uuid)`** — un-publishes one session's snapshot, for the
  single-event case (a venue reports a problem with one card). Audited.
- **`venue.unpublish_all_holder_mix()`** — un-publishes every snapshot, for the case where the constant, the
  merge, or the eligibility rule is found wrong and every stored card is suspect. Audited. `INFERENCE:` this
  exists because the alternative during an incident is a `DELETE` typed at a psql prompt at 2 a.m.

Turning the switch off does **not** delete snapshots — the numbers are needed to diagnose whatever caused the
switch to be thrown. It makes them unreadable by every client role, which is the property an incident needs.

---

## 6. Visibility matrix

Roles below use the O-2 canonical labels; the parenthetical is the C36 enum label / RLS-spec principal where
they differ. **"Aggregate" always means: the latest published `holder_mix` snapshot for one event session,
one dimension, buckets ≥ 5, summing to N — and nothing else.**

| Role | Individual value | Aggregate | Scope | Surface | Notes |
|---|:--:|:--:|---|---|---|
| **fan / buyer** (`fan`, `owner`) | **own only** | ✗ | own row | RN Settings | via `kernel.get_my_demographics()` |
| **anon** | ✗ | ✗ | — | — | zero grants |
| **`org_owner`** (`o_own`) | ✗ | ✔ | sessions of events in own org | Dashboard §9.5 card | audited read |
| **`org_admin`** (`o_adm`) | ✗ | ✔ | same | same | audited read |
| **`org_finance`** (`o_fin`) | ✗ | **✗** | — | — | see below |
| **`venue_manager`** (`v_mgr`) | ✗ | ✔ | sessions at own venue | Dashboard §9.5 card | audited read |
| **`venue_finance`** (`v_fin`) | ✗ | **✗** | — | — | see below |
| **`box_office`** (`v_mgr`-delegated box office) | ✗ | **✗** | — | — | see below |
| **`marketing`** | ✗ | ✔ | own venue/org sessions | Dashboard §9.5 card, **on screen only** | **not exportable** (§9) |
| **`promoter_manager`** | ✗ | ✔ **event-level only** | sessions at own venue/event | Dashboard §9.5 card | **no promoter axis** — see below |
| **`promoter`** / ambassador (`promo`) | ✗ | **✗** | — | — | nothing, from any surface |
| **`scanner`** / door (`v_door`, `door_pin`) | ✗ | **✗** | — | — | absolutely nothing |
| **`platform_support`** (`p_sup`) | ✗ | **✗** | — | — | see §7.2 |
| **`platform_risk`** (`p_rsk`) | ✗ | **✗** | — | — | not a risk signal |
| **`platform_admin`** (`p_adm`) | ✗ | ✔ | any session | Internal admin plane | audited; **owner decision D-7** |
| **`service_role`** (`svc`) | definer path only | definer path only | — | — | rollup writer; never a human path |

### 6.1 The denials that are deliberate, with reasons

**`org_finance` / `venue_finance` — denied. [LESS-INVASIVE]** Audience composition is not money data. The DA
already limits finance roles to `◐(limited)` on "View buyer PII" (§7.6), and nothing in settlement, payout,
reconciliation, or reporting requires a gender breakdown. Granting it would widen the blast radius of a
compromised finance account for zero product gain.

**`box_office` — denied. [LESS-INVASIVE]** Box office is a per-order service role that looks up one record at
a time (dashboard §12.6 manual lookup). Denying the aggregate also denies the one surface where an
individual value could ever end up rendered beside a name in a service context — which is how these leaks
actually happen in practice.

**`promoter_manager` — granted the event-level aggregate, denied the promoter axis. [LESS-INVASIVE]** The
owner's framing includes promoters wanting audience insight, and this design gives them the *event's* mix.
It refuses "the mix my promoter drove" because: (a) a promoter-attributed sub-population at a Miami club
night is routinely 10–40 people, far below k = 25, so most such cuts would suppress anyway; (b) a
promoter-scoped aggregate is *exactly* the second axis that makes the event aggregate differenceable
(§5.3 vector 2); and (c) the promoter's genuine commercial need — how many tickets did my code sell, and
what did I earn — is already fully served by the attribution and commission surfaces, which are unchanged
by this spec. The product value lost is close to zero; the differencing surface removed is the largest one.

**`promoter` (the individual attribution identity) — denied entirely.** DA §7.2 already bounds a promoter to
"own attributed aggregate counts", and a demographic mix is not a count of that promoter's sales. Promoters
and ambassadors are attribution identities, not org staff.

**`scanner` / door — denied entirely.** DA §7.2: door "cannot list attendees in bulk, see contact/PII beyond
scan verification". A door principal may be a loginless `door_pin` on a shared device in a crowd. There is
no version of this data that belongs there.

**`platform_support` / `platform_risk` — denied.** Support's job is resolving one person's problem, and §7
establishes that individual demographic access does not exist for anyone; an aggregate does not help a
support ticket either. Gender is not a risk signal and treating it as one would be discriminatory scoring.

---

## 7. Individual-level access

### 7.1 The rule

> **No. There is no code path, for any role, on any surface, that returns one identity's demographic value
> to another human. The only individual read that exists anywhere in the system is the person reading their
> own row.**

This is stronger than "default no" and it is deliberate. `INFERENCE:` a break-glass individual read is the
feature that always ends up used routinely, and — critically — **its absence is what makes the whole design
coercion-resistant.** If no venue, promoter, door, or support agent can ever verify what a given fan
answered, then demanding an answer at the door, or conditioning entry on one, gains the demander nothing.
A break-glass path would quietly delete that property.

### 7.2 The consequences, accepted honestly

- **Support cannot see a user's answer.** A ticket saying "my answer looks wrong" is resolved by directing
  the person to Settings, where they see and change it themselves. This is a real reduction in support
  capability and it is the correct trade.
- **Nobody can debug a specific person's row.** Engineering debugging operates on counts, null-rates, and
  constraint violations, never on values. The pgTAP suite (§12) is the substitute for eyeballing rows.
- **No staff member can write a demographic value on anyone's behalf.** There is no admin write RPC at all
  (§10.3), so a box-office operator cannot record a guess, and a compromised staff account cannot forge or
  overwrite an answer.

### 7.3 Compelled disclosure

If a subpoena, warrant, or equivalent legal process compels disclosure of an individual's demographic
record, it is handled **out of band by counsel** as a documented, dual-controlled, audited direct-database
action — never as a product feature, never a self-service admin screen, never a role. **Owner decision
D-10 (§13):** this runbook needs an owner.

---

## 8. Retention, edit, delete, and the honest Phase-2 promise

### 8.1 Edit

Any time, unlimited, from Settings. No cooldown, no approval, no audit of the *value*. An edit overwrites in
place and bumps `updated_at`.

### 8.2 Delete

"Remove my answer" **hard-deletes the row.** Not a soft-delete, not a tombstone carrying the old value, not
a status flag. The demographic row is deliberately **not** a ledger and is therefore a named, justified
exception to CDM §10 / RLS GP-2's "no row deletion" default — see §10.2.

Account deletion removes it automatically via `ON DELETE CASCADE` from `auth.users(id)` (`VERIFIED:` the
established pattern in migrations 012/023/033).

`VERIFIED:` **critical interaction with migration 019/020.** The existing account-deletion path repoints
ledger-referenced rows to the anonymized sentinel `00000000-0000-0000-0000-000000000000`. The demographic row
**must never be repointed to that sentinel** — doing so would pile every deleted user's gender answer onto a
single identity and create a "sentinel demographics" row. `ON DELETE CASCADE` is the correct behaviour and
`delete_account_cleanup` must not be extended to touch this table. **This is an explicit constraint on
whoever next edits 020.**

### 8.3 No history, ever

There is **no `demographic_history` table, no change-log, no trigger writing prior values, no soft-delete
tombstone carrying a value, and no audit row containing a value.** `INFERENCE:` a timestamped history of a
person's gender answers is the single worst artefact this feature could produce — it would record a
transition, which is far more sensitive than any current state, and it would survive the person's attempt to
remove it.

The audit trail records **that** a change occurred — `(identity_id, action ∈ {set, changed, cleared},
occurred_at)` — and **never what the value was or became.** Enforced by pgTAP assertion 19 (§12).

### 8.4 What happens to aggregates already computed

Nothing, and this is safe by construction: **`venue.holder_mix_snapshot` and `venue.holder_mix_bucket`
contain no identity references at all** — only a session id, a dimension, an `as_of`, the counters, and bucket
counts. A published snapshot cannot be traced back to any contributor because the contributor set is never
stored.

**This survives R8/R9.** The contributor multiset `C(s)` those gates compare over is computed inside the
writer's transaction and discarded with it. It is **never persisted**, in no table, no materialized view, and
no temp object outliving the transaction — a stored `(snapshot, identity, bucket)` set would be precisely the
timestamped per-person answer history §8.3 forbids, arrived at from the aggregation side. The previous
published snapshot's `C` is **recomputed** from `kernel.ticket_ownership_log` (custody at that `as_of`) plus
the *current* answer table, which is why §5.3 vector 7 states the residual it states.

The effect of a removal is therefore precise and honestly statable: **from the next published snapshot
onward, that person is not counted.** Snapshots already published are frozen numbers containing nothing that
points at anyone.

Retention of snapshots: kept for the life of the event record (they are operational reporting, CDM §5
"Analytics — PII-minimized"), and they contain no personal data to retain.

### 8.5 Reconciliation with C34, and the honest Phase-2 promise

`VERIFIED:` C34 (provable erasure — per-identity DEK lifecycle reaching every backup generation, PII-sink
inventory + purge, retained-graph re-identification mitigation, 7-year financial-retention reconciliation) is
**RATIFIED-MODELED-ONLY (GATE-L)**, spec at Gate P, **not built in Phase 2**. The constitutions are explicit
that no GDPR/CCPA erasure claim may be made before C34 exists.

Therefore Phase 2 **must not** tell a user their data is "erased", "permanently deleted", "gone forever", or
"removed everywhere". The honest, checkable promise is:

> **"When you remove your answer, we delete it from Snatch It's database right away, and it stops being
> counted in any new summary. Summaries we've already shown a venue are just numbers — they don't contain
> anything that points back to you. Encrypted backups of our database are kept for {N} days for disaster
> recovery; we don't read them, and your answer ages out of them. If we ever had to restore from one, we
> re-apply removals as part of the restore."**

`{N}` is **owner decision D-6 (§13)** — the sentence cannot ship with a placeholder.

**The mechanism that makes the last clause true: `kernel.identity_demographic_erasure`.** A minimal,
append-only, **value-free** tombstone `(identity_id, erased_at, purge_after)`. Its sole purpose is to let a
post-restore purge re-apply removals that a restore would otherwise resurrect. It records **only that a
removal happened**, never what was removed.

This tombstone is itself a small privacy cost — it reveals that a given identity once answered and later
withdrew — and that trade is accepted deliberately, with three mitigations: it is **definer-only** (no human
role, including `platform_admin`, holds any grant on it), it holds **no value**, and it is **purged at
`purge_after`** = `erased_at + backup_retention_window + margin`, after which it has no remaining purpose.

**Phase-2 posture toward C34, stated for the record.** This feature is designed to make C34 *easier*, not
harder, when it is built at Gate L:

| C34 part | This feature's Phase-2 contribution |
|---|---|
| Per-identity DEK lifecycle | One table, one column, one owner-scoped read path — a trivially enumerable encryption target when DEKs land. |
| PII-sink inventory + purge | The sink list is **closed and short today**: the table, the erasure tombstone, and nothing else. No edge function, no log, no notification payload, no search index, no export, no third-party destination, no cache (§5.4, §9). |
| Retained-graph re-identification | The rollups store **zero identity references**, so no retained demographic edge exists in the graph. |
| 7-year financial retention | No demographic value appears in any money, custody, order, settlement, or payout object, so the financial-retention obligation and demographic erasure never conflict. |

### 8.6 Interaction with C38 (identity merge, GATE-L)

`VERIFIED:` C38 is GATE-L and not built in Phase 2. When merge lands, its demographic rule is fixed here so
it is not decided ad hoc:

> **Merge never unions demographic answers.** The survivor keeps the survivor's own row if one exists; the
> non-survivor's demographic row is **hard-deleted** and a tombstone written. If only the non-survivor had
> answered, the survivor is left with **no answer** and may be prompted normally. A merge must never
> manufacture a demographic answer the survivor did not give, and must never present two conflicting
> answers for resolution by an operator — which would be individual-level disclosure to staff (§7).

This mirrors C38's own "conflicts fail closed to the narrower capability" rule, applied to data instead of
grants.

---

## 9. Export constraints — handed to the CRM export agent as binding requirements

The CRM export design (dashboard §9.6) must satisfy every constraint below. These are stated as
requirements on that agent's design, not as suggestions.

| # | Constraint |
|---|---|
| **X-1** | **No individual-level demographic data leaves the platform. Ever.** Not as a column, not as a code, not as a hash, not as a boolean, not as a derived flag, not in a segment name, not in a filename, not in a header, not in a job's metadata. |
| **X-2** | **Demographic values may not be an export *filter*.** "Export attendees where gender = X" is individual-level disclosure by construction even when the column is absent from the file — the row set *is* the disclosure. The closed enumerated filter set (dashboard §9.2/§9.6) must not gain a demographic member. |
| **X-3** | **The aggregate mix is not an exportable object** (already binding, §9.5): no CSV, no PDF, no print view, no image render, no API, no scheduled report, no email digest. It is a read on screen. |
| **X-4** | **No proxy fields.** No "shared demographics: yes/no" column, no response-completeness score, no sort order or row order derived from the demographic table. A proxy is X-1 with extra steps. |
| **X-5** | **No third-party destination ever receives a demographic field**: no webhook, no CDP sync, no Klaviyo/Mailchimp/Braze property, no ad-platform audience upload, no pixel parameter, no analytics event property, no data-warehouse sync. |
| **X-6** | **The export query touches no demographic object.** The export builder's SQL contains zero references to `kernel.identity_demographic`, `kernel.identity_demographic_erasure`, `venue.holder_mix_snapshot`, or `venue.holder_mix_bucket`. **This is CI-checkable and must be a CI check** (grep the export builder + a catalog assertion, pgTAP assertion 27). |
| **X-7** | If a campaign genuinely needs audience composition, the answer is **the on-screen aggregate**, not data movement. Composition informs the *creative*; it does not need to travel. |
| **X-8** | **A demographic-based send is not Phase 2.** If a demographic *segment* is ever wanted ("send this to women holding tickets"), the only admissible form is a **platform-side send** — the segment resolves inside Snatch It, the message goes out, and the membership list never leaves. **Owner decision D-4 (§13).** Until then: not built, not designed, not stubbed. |
| **X-9** | Every export authorization check is unaffected by this spec, but the export **audit record must record that the demographic constraint set applied** — so a future auditor can show the constraint was live at the time of every export. |

---

## 10. Schema, RLS, and RPC deltas

### 10.1 Classification and package map

`VERIFIED:` the current MVP chain is packages **076–091** (SPEC_FOUNDATION §3 numbering scheme, migration
plan §5 headings shifted +3 after production hotfixes consumed 073/074/075 on `main`). Mapping used here:
`076` schemas+grants · `077` kernel identity/orgs/roles · `078` catalog · `079` kernel ticket atom +
ownership log · `080` venue staff roles + predicates · `081` venue inventory · `082` venue orders ·
`083` signing key · `084` late-binding FK adopt · `085` kernel money-native · `086` door + scan ·
`087` venue settlement · `088` market native rail · `089` bridge view + late FK · `090` promoter engine ·
`091` `kernel.reserve` stub.

| Element | Classification | Package |
|---|---|---|
| `kernel.identity_demographic` | `ADDITIVE SCHEMA CHANGE` | **077** |
| `kernel.identity_demographic_erasure` | `ADDITIVE SCHEMA CHANGE` | **077** |
| `kernel.get_my_demographics()` | `NEW RPC` | **077** |
| `kernel.set_my_demographics(...)` | `NEW RPC` | **077** |
| `kernel.clear_my_demographics()` | `NEW RPC` | **077** |
| `venue.holder_mix_snapshot` | `ADDITIVE SCHEMA CHANGE` | **087** |
| `venue.holder_mix_bucket` | `ADDITIVE SCHEMA CHANGE` | **087** |
| `venue.refresh_holder_mix(...)` (definer/cron) | `NEW RPC` | **087** |
| `venue.get_holder_mix(...)` | `NEW RPC` | **087** |
| `venue.unpublish_holder_mix(...)` / `venue.unpublish_all_holder_mix()` (definer, §5.5) | `NEW RPC` | **087** |
| `catalog.platform_config` seed `demographics.holder_mix_enabled` (§5.5 kill switch) | `ADDITIVE SCHEMA CHANGE` (data) | **087** |
| Nightly R1/R2/R4/R5 reconciliation job | `NEW RPC` (definer) | **087** |
| `kernel.ticket_ownership_log`, `venue.order`, `venue.order_item` — **read dependency added** by R7/R8/R9 (§5.4) | **`NO SCHEMA CHANGE`** — reads only | 079 / 082 must precede 087 |
| RLS spec §6 column-scoped table — add 4 deny-all rows | `SPEC CORRECTION` | doc |
| RLS spec §7/§9 — add 4 role matrices | `SPEC CORRECTION` | doc |
| SPEC_FOUNDATION §6 canonical table inventory — add 4 tables | `SPEC CORRECTION` | doc |
| Dashboard §9.5 `UNVERIFIED` note → resolved contract | `SPEC CORRECTION` | doc |
| Dashboard §9.1 attendee list — no demographic column, no answered-flag, no derived sort | `SPEC CORRECTION` | doc |
| Attendee-list, order, ticket, scan, settlement, payout objects | **`NO SCHEMA CHANGE`** | — |
| `kernel.identity_ext`, `public.profiles` | **`NO SCHEMA CHANGE`** | — |
| Edge functions | **`NO SCHEMA CHANGE` / none** | — |
| RN "About you (optional)" card + screen + remove control | `NEW RN SURFACE` | gated on **077** |
| Dashboard "Ticket holder mix" card | `NEW DASHBOARD SURFACE` (spec exists) | gated on **087** |

**Why package 087 and not 086.** The rollup reads `kernel.tickets` + `kernel.ticket_ownership_log` (079),
`catalog.event_session`/`event`/`venue` + `catalog.platform_config` (078), and `venue.order`/`venue.order_item`
(082, **price only**, for R7's zero-price test) — and nothing else. It deliberately does **not** read
`venue.scan` (086), because `admitted_mix` is not built (§4.1). 087 is chosen as the first package after the
full custody + session + order chain is adopted, keeping the demographic objects off the critical path of every
MVP gate. The rollup has **no dependency on 086** and could move earlier if the schedule wants it; it must not
move earlier than **082** (R7 needs the order price) or **084** (the late-binding FK adopt), whichever is
later. `INFERENCE:` the 082 floor is new — R7 did not exist when 087 was chosen, and the dependency is worth
naming rather than discovering during sequencing.

**Why the fan-side objects ride in 077 and not a package of their own.** 077 is the identity package; the
demographic row is keyed by `auth.users(id)` and depends on nothing else. Placing it there means the RN
surface unblocks at the earliest possible point and answers accumulate before any venue can read a
threshold-clearing aggregate — which is the desired ordering.

### 10.2 Schema delta (additive)

**`kernel.identity_demographic`** — MUT, **not a ledger**, no history.

| Column | Notes |
|---|---|
| `identity_id` | PK, `→ auth.users(id) ON DELETE CASCADE` |
| `gender_identity` | text, `CHECK (gender_identity IN ('woman','man','non_binary','another_gender_identity','prefer_not_to_say'))` — text+CHECK per migration-plan DECISION 1, never a Postgres ENUM |
| `notice_version` | text NOT NULL |
| `first_answered_at` | timestamptz NOT NULL |
| `updated_at` | timestamptz NOT NULL |

- **Two named exceptions to global postures, both deliberate and justified:**
  - **GP-2 (`DELETE` denied everywhere) is excepted** for this table *inside the definer RPC only*. Clients
    still hold zero DELETE. The justification is §8.2/§8.3: keeping a withdrawn gender answer as a
    tombstoned row would defeat the withdrawal, and this table references no ledger.
  - **The `ON DELETE RESTRICT` FK default is excepted** in favour of `ON DELETE CASCADE` from `auth.users`.
    Justification: an orphaned demographic answer belonging to a deleted account is the worst possible
    residue, and `VERIFIED:` cascade-from-`auth.users` is already the house pattern (012/023/033).
  - **Both exceptions require acknowledgment by the schema and RLS spec owners.** Flagged as such.

**`kernel.identity_demographic_erasure`** — AO, definer-only, value-free.

| Column | Notes |
|---|---|
| `identity_id` | PK |
| `erased_at` | timestamptz NOT NULL |
| `purge_after` | timestamptz NOT NULL — `erased_at + {N} + margin` (D-6) |

**`venue.holder_mix_snapshot`** — PROJ/derived, rebuildable, **zero identity references**.

| Column | Notes |
|---|---|
| `snapshot_id` | PK |
| `event_session_id` | `→ catalog.event_session` |
| `dimension` | text, `CHECK (dimension = 'gender_identity')` in Phase 2 |
| `as_of` | timestamptz — the instant the holder set was evaluated |
| `holders_total` | int — distinct **R7-eligible** holders of ≥1 non-voided ticket (the `M`). **Never emitted on a suppressed snapshot** (R6) |
| `holders_responded` | int — distinct eligible holders with a substantive answer (the `N`); `CHECK (holders_responded <= holders_total)`. **Never emitted on a suppressed snapshot** (R6) |
| `holders_excluded_ineligible` | int — how many holders R7 removed. Diagnostic; **definer-only, never emitted to any client**, so the eligible and total populations can be reconciled without publishing either |
| `suppressed` | boolean |
| `suppression_reason` | text, `CHECK` ∈ `below_event_minimum` · `merge_cannot_reach_legal_set` · `churn_gate` · `near_duplicate_population` · `null when not suppressed`. **Definer-only and never returned to a client** — the reason discriminates the *shape* of the distribution (a `merge_cannot_reach_legal_set` on a 25-response session says "one bucket holds almost everyone", which is a disclosure the suppression exists to prevent). It is readable by the reconciliation job and by `platform_admin` on the internal plane only |
| `published_at`, `computed_at` | timestamptz |
| | `UNIQUE (event_session_id, dimension, as_of)`; partial unique index enforcing **at most one published snapshot per (session, dimension)** |

**`venue.holder_mix_bucket`** — PROJ/derived.

| Column | Notes |
|---|---|
| `snapshot_id` | PK part, `→ venue.holder_mix_snapshot` |
| `bucket` | PK part, text, `CHECK (bucket IN ('woman','man','non_binary','another_gender_identity','other'))` — note **`prefer_not_to_say` is not a legal bucket** (§1.3) |
| `holder_count` | int, **`CHECK (holder_count >= 5)`** — the floor as a database constraint (R2) |

### 10.3 RLS delta

Following the proven `public.profiles` pattern (068 column grants + 042 `SECURITY DEFINER` own-row read),
at its strongest setting.

**Grants — all four tables:**

```
REVOKE ALL ON kernel.identity_demographic            FROM PUBLIC, anon, authenticated;
REVOKE ALL ON kernel.identity_demographic_erasure    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON venue.holder_mix_snapshot              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON venue.holder_mix_bucket                FROM PUBLIC, anon, authenticated;
-- and NO re-GRANT of any column to any client role. The grant set is EMPTY, not reduced.
```

`INFERENCE:` this is the one place the design goes further than 068. 068 re-granted a public-safe column
list because `display_name` genuinely is public-safe. **No column of a gender answer is public-safe**, and
because column privileges are per-role not per-row (§0), any grant at all would expose every row to every
signed-in user. RLS policies are therefore not the enforcement here — **the absence of a grant is**, exactly
as 052/062/068 established.

**RLS itself:** `ENABLE ROW LEVEL SECURITY` on all four, **with no policy admitting `anon` or
`authenticated`** — deny-by-default, belt and braces behind the empty grant set.

**RLS spec §6 additions (`SPEC CORRECTION`):**

| Table | World/broad-readable columns | RESTRICTED |
|---|---|---|
| `kernel.identity_demographic` | **none — no client role holds any column grant** | entire table → `kernel.get_my_demographics()` (own row only); never cross-identity, never platform |
| `kernel.identity_demographic_erasure` | **none** | entire table → definer/`service_role` only; no human role |
| `venue.holder_mix_snapshot` | **none** | entire table → `venue.get_holder_mix()` (role- and scope-checked) |
| `venue.holder_mix_bucket` | **none** | entire table → `venue.get_holder_mix()` |

**RLS spec §7/§9 matrices (`SPEC CORRECTION`)** — for all four tables, across the 15 principals:
`SEL = V` for the principals §6 authorizes via RPC and `D` for everyone else; `INS/UPD = R` for `owner` on
`kernel.identity_demographic` and `D` for all 14 others; `INS/UPD = D` for every principal on the other
three tables (`svc` definer path only); `DEL = D` for all 15 principals on all four tables (the §10.2
exception is inside the definer, never a client cell). `svc` shows the definer path only, never a UI path.

### 10.4 RPC contracts

Every contract inherits RPC-spec §0 globals: `SECURITY DEFINER` owned by `postgres`, `search_path` pinned
(066), `REVOKE EXECUTE FROM PUBLIC, anon` then a narrow `GRANT` (067), actor **always** `auth.uid()`
server-derived (C35), role tests only via the C36 predicate helpers, no client actor parameter.

---

**`kernel.get_my_demographics()`** — `DB-RPC`, read.
- **Purpose:** the *only* individual read in the system.
- **Params:** **none.** `INFERENCE:` parameterless is load-bearing — a signature with no identity argument
  makes "read someone else's row" unexpressible, exactly as 042 established for `get_my_profile()`.
- **Actor:** `auth.uid()`; raises `insufficient_privilege(42501)` when NULL.
- **Reads:** `kernel.identity_demographic WHERE identity_id = auth.uid()`.
- **Returns:** `{ gender_identity, notice_version, updated_at }` or the empty set (never answered).
- **EXEC:** `authenticated`. **SSCAS:** n/a (single-aggregate).

---

**`kernel.set_my_demographics(p_gender_identity text, p_notice_version text)`** — `DB-RPC`, write.
- **Purpose:** the fan sets or changes their own answer.
- **Params:** both **untrusted**; `p_gender_identity` re-validated against the CHECK value set inside the
  body, `p_notice_version` against the known notice-version list. **No identity parameter exists.**
- **Actor:** `auth.uid()`; raises on NULL.
- **Writes:** upsert one row keyed by `auth.uid()`. Sets `first_answered_at` on insert only; always bumps
  `updated_at`. Writes an audit row recording `(identity_id, action, occurred_at)` — **never the value**.
- **Idempotent:** re-calling with the same value is a no-op update.
- **Returns:** `{ status: 'ok' }`. **EXEC:** `authenticated`. **SSCAS:** n/a.
- **Forbidden:** there is **no** `kernel.admin_set_demographics` and no staff write path of any kind (§7.2).

---

**`kernel.clear_my_demographics()`** — `DB-RPC`, write.
- **Purpose:** withdrawal.
- **Params:** none. **Actor:** `auth.uid()`.
- **Writes:** `DELETE` the caller's row (the §10.2 GP-2 exception, inside the definer); upsert one
  `kernel.identity_demographic_erasure` row with `purge_after`; write the value-free audit row.
- **Idempotent:** calling with no row present is `{ status: 'noop_replay' }`, not an error.
- **EXEC:** `authenticated`. **SSCAS:** n/a.

---

**`venue.refresh_holder_mix(p_event_session_id uuid)`** — `DB-RPC`, definer-only writer.
- **Purpose:** compute a candidate snapshot and publish or discard it.
- **EXEC:** **`service_role` / definer only.** `REVOKE EXECUTE FROM anon, authenticated` — no human path.
  Invoked by `pg_cron` per §5.4.
- **Reads:** the declared read set of §5.4 — `kernel.tickets`, `kernel.ticket_ownership_log`,
  `venue.order`/`venue.order_item` (**zero/non-zero price test only**), `kernel.identity_demographic`,
  `venue.holder_mix_snapshot`, `catalog.event_session`/`event`/`venue`, `catalog.platform_config`.
  **Does not read** `venue.scan`, `venue.attribution`, `venue.ticket_type`, `public.profiles`, or any buyer
  identity.
- **Algorithm, in order:** resolve the eligible holder set (**R7**) → compute `holders_total`,
  `holders_responded`, `holders_excluded_ineligible`, raw bucket counts → **R1** event minimum → **R3** merge,
  the fully determined procedure of §5.2 → **R5** two-bucket / all-or-nothing → **R8** contributor-multiset
  churn gate against the last published snapshot for this `(session, dimension)` → **R9** cross-session
  near-duplicate gate over every currently published snapshot on a session reachable by the same venue or org
  → persist. R2 is additionally enforced by the CHECK constraint; R4 by a writer assertion **and** by the
  read-side re-derivation in `get_holder_mix`; R6 by `get_holder_mix`'s return shape.
- **Writes:** at most one `holder_mix_snapshot` (+ its buckets). A discarded recomputation writes nothing.
  Publishing a new snapshot un-publishes the prior one (the partial unique index enforces one published
  snapshot per session+dimension). **Writes no contributor multiset and no identity reference of any kind** —
  `C(s)` exists only inside the transaction (§8.4).
- **Returns:** `{ status: 'published' | 'suppressed' | 'discarded_churn_gate' | 'discarded_near_duplicate' }`
  — to `service_role` and the job log only; no client ever sees this value.
- **SSCAS:** n/a — reads only, then writes one derived aggregate; it is **not** a member of the closed set
  and touches no money, custody, or inventory row.

---

**`venue.unpublish_holder_mix(p_event_session_id uuid)`** / **`venue.unpublish_all_holder_mix()`** —
`DB-RPC`, definer-only writers (§5.5). Set `published_at = NULL` on the targeted snapshot(s); delete nothing;
write one `kernel.admin_audit` row per invocation naming the actor and the count affected.
**EXEC:** `service_role` / `platform_admin` step-up only. `REVOKE EXECUTE FROM anon, authenticated`.

---

**`venue.get_holder_mix(p_event_session_id uuid, p_dimension text)`** — `DB-RPC`, read.
- **Purpose:** the dashboard §9.5 card's only data source.
- **Params:** **exactly two, and this is the contract.** No `as_of`, no ticket type, no promoter, no source,
  no date range, no scan status, no limit/offset, no ordering, no free-form filter. **Adding a third
  parameter to this function is a design change requiring re-review of §5.3, not a routine enhancement.**
- **Actor:** `auth.uid()`. **Authority:** resolves the session → event → venue → org, then requires
  `kernel.has_venue_role(venue_id, ['venue_manager','marketing','promoter_manager'])` **or**
  `kernel.has_org_role(org_id, ['org_owner','org_admin'])` **or** `kernel.is_platform(['platform_admin'])`.
  Everyone else: `insufficient_privilege(42501)`. Per §6, `org_finance`, `venue_finance`, `box_office`,
  `venue_door`/`door_pin`, `promoter`, `platform_support`, `platform_risk`, `fan`, `anon` are denied.
- **Returns:** exactly one of two shapes, and the suppressed shape has **no other fields to fill** (R6):
  - `{ suppressed: true }` — nothing else. No `reason`, no `holders_total`, no `holders_responded`, no
    `as_of`, no bucket rows. `INFERENCE:` this is the single most important line in the contract. The
    previous shape returned the denominators on a suppressed snapshot, which let a `venue_manager` mint a
    throwaway session, comp one ticket to a target, and read `holders_responded ∈ {0,1}` as that person's
    "did you answer" bit — the exact proxy X-4 bans. The suppressed branch must be a constant.
  - `{ suppressed: false, as_of, holders_total, holders_responded, buckets: [{bucket, holder_count}, …] }`,
    where the buckets always sum to `holders_responded` (R4).
- **Read-side re-derivation, fail-closed (the second enforcement layer of §5.2).** Before emitting the
  published shape the function re-checks, on the row it just read: `holders_responded >= 25` (R1);
  `min(holder_count) >= 5` (R2); `Σ holder_count = holders_responded` (R4); `count(buckets) >= 2` (R5);
  `holders_responded <= holders_total`. **Any failure returns `{ suppressed: true }` and raises a
  reconciliation alarm** — it never returns a partial or corrected card. This layer is what makes a
  writer bug, a hand-written `INSERT`, or a restored-from-backup row fail closed at the read.
- **Kill switch (§5.5).** `catalog.platform_config['demographics.holder_mix_enabled']` is read **live on
  every call**; when false the function returns `{ suppressed: true }` for every session regardless of stored
  state. A snapshot whose `published_at IS NULL` is likewise `{ suppressed: true }`.
- **Side effects:** writes one audit row per call — `(actor, event_session_id, dimension, occurred_at)`
  (§11). **Rate-limited per principal** using the existing fail-closed rate-limit pattern (005/021).
- **EXEC:** `authenticated` with the in-body predicate re-check (RPC §0.1). **SSCAS:** n/a.

---

**Nightly reconciliation job** — `DB-RPC`, definer-only. Asserts R4 (`Σ buckets = holders_responded`) and
R2 (`min(holder_count) >= 5`) across every published snapshot, and alarms on violation. This mirrors the
C27 counter-vs-ledger reconciliation discipline.

---

## 11. Abuse prevention

| Vector | Defence |
|---|---|
| **Coercion at the door** ("tell me what you answered to get in") | Structural: **no one can verify an answer** (§7). Demanding it gains the demander nothing, so the demand has no payoff. This is the single most important abuse property in the design. |
| **Staff entering a value on a fan's behalf** | Structural: no admin write RPC exists. `set_my_demographics` has no identity parameter and keys on `auth.uid()`. |
| **A venue splitting one event into many sessions to shrink cells** | R1 applies **per session independently**; a 10-holder session never renders. Splitting reduces what the operator sees, never increases it. |
| **A venue creating throwaway micro-events to isolate a person** | k = 25 eligible responses required per session, **and** R6 means a session that does not publish returns the constant `{suppressed: true}` — no denominators, no reason. The previous design leaked here: it returned `holders_responded` on the suppressed snapshot, so a one-person session answered "did this person share" directly. That is closed. |
| **Sybil accounts to skew a chart** | R7: only custody **acquired for consideration** counts — comped and zero-price atoms are excluded — so a manufactured contributor costs a real ticket at a real price, and refunds remove it. **The previous rebuttal ("each fake data point costs a real ticket purchase") was false and is deleted:** a comp costs nothing and the `venue_manager` mints both the session and the comps, so before R7 the operator could compose the entire population for free. R7 makes the rebuttal true; it does not make manufacturing impossible, only priced. |
| **Scraping via repeated reads** | Every `get_holder_mix` call is audited (actor, session, dimension, time) and rate-limited per principal, fail-closed (005/021 pattern). The export history / activity feed already surfaces staff reads (dashboard §17); demographic reads join it. |
| **Temporal differencing by a patient observer** | R8 churn gate over the contributor multiset — §5.3 vector 4. Bounded at ≥ 5 changed contributor pairs **and** ≥ 5 distinct changed identities per observable delta. |
| **Population differencing across two sessions the operator composed** | R7 (prices the differing member) + R9 (two near-identical populations cannot both publish). **Partly open** — R9 bounds membership differencing, not answer differencing among stable members across sessions. §5.3 vector 7 states the gap; D-13 owns it. |
| **A future engineer adding a filter parameter** | `get_holder_mix`'s two-argument shape is stated as a contract, asserted by pgTAP (arity/arg-name assertion 14), and the rollup has no finer-grained operands to filter over. |
| **Demographic data leaking through an export or an integration** | X-1…X-9 (§9), with X-6 as a CI check. |
| **Demographic value escaping through logs / observability** | No edge function, no external call, no log statement, no notification payload, no Sentry breadcrumb touches the value (§5.4). The value never crosses a process boundary out of Postgres. |
| **Re-identification by an operator who also knows the guest list** | Bounded, not eliminated — and the bound is weaker than "anonymity" suggests. Five roles hold **both** the CRM spec's by-name roster read and this card (`org_owner`, `org_admin`, `org_marketing`, `venue_manager`, `venue_marketing`), so the smallest inferable group is 5 people **the reader can name**, not 5 unknowns. Floor 5 and the absence of a second axis are what bound it; the roster is what makes the bound a group bound rather than an anonymity bound. Stated here, in the CRM spec, and as **D-14**. |
| **Stopping the leak once it is found** | §5.5: a live read-path kill switch plus two un-publish RPCs. Stopping the cron is **not** a kill switch — it stops new snapshots while venues keep reading the last published card. |
| **A compromised finance/door/promoter/support account** | Those roles hold nothing (§6). The blast radius of the most commonly-compromised accounts is zero. |

---

## 12. Optional means optional — the proof

**Claim: a fan who answers nothing has a fully functional product, and their silence leaks nothing.**

**(a) No flow reads the table.** Purchase, checkout, issuance, transfer, listing creation, resale, bidding,
scan/admission, refund, dispute, payout, and settlement contain **zero reads** of
`kernel.identity_demographic`. The complete set of readers is: `kernel.get_my_demographics` (own row) and
`venue.refresh_holder_mix` (definer aggregate). Assertable — pgTAP assertions 27 and 10 enumerate every
function, view, and writer that references the table and assert those sets are exactly these.

**(b) No UI state depends on it.** No badge, no completeness meter, no red dot, no lock icon, no "finish
your profile" state, no reduced feature set, no different ranking, no different pricing, no different
notification cadence. The card is dismissible and stops asking after three dismissals (§2.2).

**(c) The venue cannot tell who didn't answer.** The published objects contain **no identity references at
all** (§8.4). The dashboard attendee list carries no demographic column, no answered/not-answered flag, and
no sort or filter derived from either (`SPEC CORRECTION` to dashboard §9.1). The only thing derivable is
*how many* did not share (`M − N`), which is a count with no membership.

**(d) Declining is indistinguishable from never answering.** `prefer_not_to_say` is never a published
bucket (§1.3); both a deliberate decline and an absent row land in `M − N`. There is no surface, RPC,
export, or view where the two states differ. **The absence is therefore not a signal**: it is not a signal
about the person (nobody can attribute it) and it is not a signal about their intent (declining and
ignoring are the same observation). pgTAP assertion 12 asserts `prefer_not_to_say` never appears as a bucket.

**(e) The honest residuals.**

1. **The denominator on a published card.** A venue with 38 eligible holders and N = 26 learns that 12
   eligible people did not share. That is a property of publishing any denominator at all, it identifies
   nobody at a population of ≥ 25, and it is the price of the "Based on N of M" transparency the ratified
   card copy requires. Removing the denominator on a published card would make the chart misleading, which is
   a worse trade.
2. **The denominator on a *suppressed* card is a different thing entirely, and it is gone.** At small `M` the
   same two numbers stop being a population statistic and become a per-person bit — `M = 1, N = 1` is one
   named person's answered/not-answered flag. Per R6 the suppressed shape carries no numbers at all (§10.4).
   This is the correction that makes claim (d) above survive contact with an operator who controls the
   population: without it, "declining is indistinguishable from never answering" held at the *bucket* surface
   and failed at the *denominator* surface.
3. **What claim (d) still does not cover.** Declining and never answering are indistinguishable on every
   surface. Neither is distinguishable from *not being eligible* either, since R7's exclusions are folded
   into a definer-only counter (`holders_excluded_ineligible`) that no client reads. What remains is §5.3
   vector 7: an operator running the same audience repeatedly, holding the roster by name, retains an
   inference channel this design bounds but does not close.

---

## 13. pgTAP assertion list (described; no SQL files written)

**Grants and RLS**
1. `anon` holds **zero** rows in `information_schema.role_column_grants` for all four tables.
2. `authenticated` holds **zero** rows in `role_column_grants` for all four tables. *(This is the assertion
   that would have caught the pre-068 `public.profiles` exposure.)*
3. RLS is enabled on all four tables and no policy exists whose roles include `anon` or `authenticated`.
4. `DELETE` is denied to `anon` and `authenticated` on all four tables (GP-2).
5. All five RPCs are `SECURITY DEFINER`, owned by `postgres`, with `search_path` pinned (066 pattern), and
   have `EXECUTE` revoked from `PUBLIC` and `anon` (067 pattern).
6. `venue.refresh_holder_mix` and the reconciliation job have `EXECUTE` revoked from `authenticated` —
   `service_role` only.

**Own-row isolation**
7. With identities A and B both holding rows, `get_my_demographics()` called as A returns exactly A's row
   and zero rows of B's.
8. `get_my_demographics()` raises when `auth.uid()` is NULL.
9. **Signature assertion:** `get_my_demographics` and `clear_my_demographics` have arity 0, and
   `set_my_demographics` has no parameter whose name or type could denote an identity (no `uuid` parameter
   at all). *(Structural — "read someone else's row" must be inexpressible, not merely denied.)*
10. No admin/staff write function for demographics exists: the set of functions writing
    `kernel.identity_demographic` is exactly `{set_my_demographics, clear_my_demographics}`.

**Value set**
11. The CHECK rejects a `gender_identity` outside the five-value set, including empty string and free text.
12. The bucket CHECK rejects `prefer_not_to_say` as a bucket value.

**Suppression (R1–R9)**
13. `holder_mix_bucket` CHECK rejects an insert with `holder_count = 4` and accepts `5`. *(The floor as a
    database constraint, not a render rule.)*
14. **`venue.get_holder_mix` has exactly two parameters**, named for session and dimension, with no `as_of`,
    filter, limit, offset, or ordering parameter. *(The differencing contract, asserted.)*
15. A session with `holders_responded = 24` returns `suppressed`; the same session at 25 returns buckets.
16. **R4 invariant scan:** for every published snapshot, `Σ holder_count = holders_responded`.
17. **The complement case:** a 26-response session split 20/5/1 persists `{woman: 20, other: 6}` — the
    1-count bucket is absent, `other` ≥ 5, and the sum still equals 26 so no residual is computable. Asserts
    R3 **step 3** specifically: `man = 5` is above the floor and is merged anyway, which is the step the
    previous prose omitted.
18. **R5 two-bucket minimum:** a 25-response session split 24/1 persists a `suppressed` snapshot with **zero**
    bucket rows; so does 23/1/1; so does any split whose merge collapses to a single bucket.
19. **R8 churn gate:** a recomputation whose contributor-multiset churn since the last published snapshot is
    4 pairs returns `discarded_churn_gate` and writes no snapshot; at 5 pairs spread over 5 distinct
    identities it publishes; at 5 pairs arising from **2** identities each changing their answer it does
    **not** publish (the distinct-identity limb).
20. At most one published snapshot exists per `(event_session_id, dimension)` (partial unique index).
21. `holders_responded <= holders_total` on every snapshot.

**Visibility**
22. `get_holder_mix` **denies**: `anon`, `fan`, `owner`, `org_finance`, `venue_finance`, `box_office`,
    `venue_door`, a valid `door_pin` principal, `promoter`, `platform_support`, `platform_risk`.
23. `get_holder_mix` **allows**: `venue_manager`, `marketing`, `promoter_manager` (venue scope);
    `org_owner`, `org_admin` (org scope); `platform_admin`. And a `venue_manager` of venue X is **denied**
    on a session belonging to venue Y.
24. Every call to `get_holder_mix` writes exactly one audit row naming actor, session, dimension, time.

**No history, no leakage**
25. **No history:** zero triggers on `kernel.identity_demographic` other than the `updated_at` maintainer;
    no table anywhere has a column whose type/CHECK matches the gender value set except
    `kernel.identity_demographic` and `venue.holder_mix_bucket`.
26. **Audit carries no value:** audit rows written by `set_/clear_my_demographics` contain no column
    holding a gender value (assert by column set and by content scan).
27. **Reader enumeration (the X-6 / §12(a) check):** the set of functions, views, and matviews in the
    catalog whose definition references `kernel.identity_demographic` is exactly
    `{get_my_demographics, set_my_demographics, clear_my_demographics, refresh_holder_mix}`. Any addition
    fails the suite. Mirrored by a CI grep over the export builder and edge-function sources.
28. **Snapshots hold no identity reference:** `holder_mix_snapshot` and `holder_mix_bucket` have no `uuid`
    column referencing `auth.users`, and no FK to any identity-bearing table.

**Erasure**
29. `clear_my_demographics` removes the row and writes exactly one erasure row; a second call is
    `noop_replay` and does not write a duplicate.
30. Deleting the `auth.users` row cascades the demographic row away, and the row is **not** repointed to the
    `00000000-0000-0000-0000-000000000000` sentinel; the sentinel identity holds no demographic row after
    any account deletion.
31. The erasure tombstone holds no gender value column, and no human role holds any grant on it.

**Population control (R6–R9, the read-side layer, and the kill switch)**

*Numbering continues rather than renumbering: assertions 1–31 are referenced by number from this document
(§5.2, §8.3, §9 X-6, §11, §12) and from the CRM spec's §10.4 and §12, and a renumber would silently break
every one of those references.*

32. **R6 — the suppressed shape is a constant.** `get_holder_mix` on a suppressed or unpublished session
    returns a value with **exactly one key**, `suppressed`. Asserted structurally (the returned record's
    field set), not by inspecting values, so a future engineer cannot add `holders_total` back and pass.
    Two sessions differing only in `holders_responded` (0 vs 1) return **byte-identical** results.
    *(This is the assertion that would have caught the throwaway-session + one-comp oracle.)*
33. **R7 eligibility.** A session whose holders are all comped renders nothing at any response count. A
    session of 30 paid holders + 5 comped holders has `holders_total = 30`. An atom whose issuing order line
    has `unit_price_minor = 0` is excluded even when its cause is `primary_sale`.
34. **R8 churn is over pairs *and* identities.** 5 pair-changes arising from 2 identities each changing their
    answer does **not** publish; 5 pair-changes over 5 distinct identities does.
35. **R9 near-duplicate gate.** Two sessions of the same venue whose eligible-holder sets differ by 4
    identities: only one of them has a published snapshot. At a difference of 5, both may publish. The gate
    also quantifies across venues of the same org.
36. **Read-side re-derivation, fail-closed.** With a published snapshot hand-corrupted to violate R1, R2, R4
    or R5 (bypassing the writer), `get_holder_mix` returns `{suppressed: true}` — not the corrupted card, not
    a corrected card — and raises the reconciliation alarm.
37. **Kill switch.** With `demographics.holder_mix_enabled = false`, `get_holder_mix` returns
    `{suppressed: true}` for a session that has a valid published snapshot; setting it back to `true` restores
    the card without a recompute. `venue.unpublish_all_holder_mix()` leaves every snapshot row present and
    every `published_at` null.
38. **The suppression reason never reaches a client.** No client-callable function returns
    `suppression_reason`, and `anon`/`authenticated` hold no grant on the column.
39. **No contributor multiset is persisted.** No table, view, matview or unlogged/temp object outliving a
    transaction holds a `(snapshot_id | session_id, identity_id, bucket)` tuple. Asserted as a column-set scan
    across the catalog, alongside assertion 25's no-history scan.

---

## 14. Open questions — owner and counsel decisions required

| ID | Decision | Owner | Blocking? |
|---|---|---|---|
| **D-1** | **Which privacy regimes apply** to a Miami-based marketplace whose fans include EU/UK visitors and California residents (GDPR/UK GDPR, CPRA, other US state regimes)? Options: (a) treat US-only, (b) treat GDPR as applying to visitor traffic, (c) build to the strictest and stop asking. This spec is built so (c) needs no redesign. | **Counsel** | No — design survives any answer |
| **D-2** | **Is gender identity special-category / "sensitive personal information"** under the regimes from D-1? GDPR Art. 9 does not name it verbatim; some supervisory authorities and some US state statutes treat it as sensitive. This document asserts **no** legal conclusion. The capture is already an affirmative, unbundled, versioned, freely-given opt-in with one-tap withdrawal and no detriment — an explicit-consent posture — so a "yes" answer requires no change. | **Counsel** | No |
| **D-3** | **Add `age_band` in a later wave?** Value set pre-specified in §1.5. Requires a new `notice_version` and a separate opt-in. **Not Phase 2.** | Owner | No |
| **D-4** | **Is a demographic-based platform-side send ever wanted** (segment resolves inside Snatch It, list never exported — X-8)? Currently: not built, not designed, not stubbed. | Owner | No |
| **D-5** | **Confirm k = 25 and floor = 5.** Adopted from the ratified dashboard §9.5. The owner may **raise** these; this spec asks that they never be lowered, and that any change be a documented amendment rather than a config tweak. Related: should the thresholds live in `catalog.platform_config` (tunable) or be hard-coded in the CHECK constraint (rigid)? **This spec recommends the CHECK constraint** — a tunable privacy floor is a floor that gets tuned. | Owner | **Yes — the CHECK constant** |
| **D-6** | **Backup retention window `{N}` days.** Required to fill the §8.5 promise sentence and to set `purge_after` on the erasure tombstone. The user-facing copy **cannot ship with a placeholder.** | Owner / ops | **Yes** |
| **D-7** | **Does `platform_admin` get aggregate access at all?** This spec defaults to yes, any session, audited. The alternative (zero platform access) is also coherent and slightly stronger. | Owner | No |
| **D-8** | **Confirm `marketing`'s ceiling**: aggregate on screen, never exportable, and confirm whether the grant is venue-scoped, org-scoped, or both. The O-2 ratification gives `marketing` "CRM/export/analytics access as authorized"; this spec reads the demographic mix as **outside** that export authorization per §9.5 and X-3. | Owner | No |
| **D-9** | **Acknowledgment of the two named global-posture exceptions** (§10.2): the definer-scoped `DELETE` on `kernel.identity_demographic`, and `ON DELETE CASCADE` from `auth.users` against the `RESTRICT` default. Both need the schema and RLS spec owners' sign-off. | Architecture | **Yes — before 077** |
| **D-10** | **Owner for the compelled-disclosure runbook** (§7.3) — out-of-band, dual-controlled, audited, never a product feature. | Owner / counsel | No |
| **D-11** | **Constraint handed to whoever next edits migration 020:** `delete_account_cleanup` must **not** be extended to repoint the demographic row to the anonymized sentinel (§8.2). Needs acknowledgment by the account-deletion owner. | Architecture | **Yes — before 077** |
| **D-12** | **R7 excludes comped and zero-price custody (§5.2). Confirm the product consequence:** a genuinely free event never renders the card, and `M` on every card is the paying population rather than the room. The alternative — count everyone — restores a population the operator can mint for free, which voids every k-anonymity claim in §5. This spec recommends R7 as written and asks that any relaxation be an amendment, not a config change. | Owner | **Yes — the eligibility rule** |
| **D-13** | **§5.3 vector 7 is an acknowledged open gap.** R9 bounds *membership* differencing across sessions; it does not bound *answer* differencing among stable members across sessions, because answers are deliberately not historied. For a venue running the same regulars weekly this is a real, unquantified channel. Decide whether Phase 2 ships with it: (a) accept and record; (b) raise k above 25 for venues above a repeat-audience threshold; (c) withhold the card from sessions whose eligible-holder set overlaps a prior session by more than a stated fraction. This spec asserts **no** coverage here and recommends (a) with the residual published in the venue-facing help text. | Owner | **Yes — before the card ships** |
| **D-14** | **Five roles hold both the by-name roster (CRM spec §3 X1) and this card (X11):** `org_owner`, `org_admin`, `org_marketing`, `venue_manager`, `venue_marketing`. The floor-5 bound is therefore a bound over **5 people the reader can name**, not 5 unknowns. Decide whether that is intended. Options: accept and say so in §11 (done); or make the two grants mutually exclusive, which costs `venue_manager` one of them and is a significant product change. | Owner | No — but the claim is corrected either way |

---

## 15. Summary of the "less invasive, same value" choices

| # | Where a broader design was available | What this spec does instead | Product value lost |
|---|---|---|---|
| 1 | Free-text self-describe gender field | Closed five-value set with `another_gender_identity` | None — the bucket still counts |
| 2 | Ask at signup (higher response rate) | Optional profile enrichment only, ≤3 prompts | Some response volume; consent validity gained |
| 3 | Incentivize answering with a perk | No reward, no penalty | Volume, and data quality *improved* |
| 4 | `admitted_mix` (true in-room count) | `holder_mix` (custody head, no scan join) | Post-hoc precision; pre-doors utility gained |
| 5 | Promoter-scoped demographic cut | Event-level only for `promoter_manager` | Near zero — most cuts would suppress anyway; the largest differencing surface removed |
| 6 | Per-person consent-event ledger | One `notice_version` column, no history | None — the consent record is equally provable |

---

## 16. Correction index for this document

| Tag | Applies to | Effect |
|---|---|---|
| **J-1** | Venue dashboard §9.5 `UNVERIFIED` note | Resolved: storage (§10.2), capture (§2), and aggregation (§5) supplied. §9.5's render contract is unchanged and remains binding. |
| **J-2** | Venue dashboard §9.1 attendee list | Constraint added: no demographic column, no answered/not-answered indicator, no derived sort or filter. |
| **J-3** | RLS spec §6 + §7/§9 | Four deny-all rows and four role matrices added (§10.3). |
| **J-4** | SPEC_FOUNDATION §6 table inventory | Four tables added (§10.2). |
| **J-5** | RPC contracts spec | Five contracts added (§10.4). |
| **J-6** | CDM §4 / DA §8.7 (C34) | No constitution edit. This document records the Phase-2-safe interim promise (§8.5) and the C38 merge rule for demographics (§8.6), both consistent with the GATE-L status. **The frozen constitutions are not modified by this document.** |
| **J-7** | Migration 020 / account deletion | Constraint recorded (§8.2, D-11): never repoint the demographic row to the anonymized sentinel. |
| **J-8** | **This document, §4.1 · §4.3 · §5.1–§5.5 · §8.4 · §10.2 · §10.4 · §11 · §12(e) · §13** | **H-6 remediation.** The privacy floors were proved against a population the operator controls. Added: R6 (denominator suppression — the suppressed projection is now the constant `{suppressed: true}`), R7 (population eligibility — comped and zero-price custody excluded), R8 (churn redefined over the contributor multiset `(identity, bucket)`, with a distinct-identity limb), R9 (cross-session near-duplicate gate), a fully determined R3 merge with a two-bucket minimum in R5, a fail-closed read-side re-derivation of R1/R2/R4/R5/R6, the §5.4 declared read set the churn rule actually needs, and the §5.5 kill switch. **Two claims deleted** — see J-9. |
| **J-9** | **Deleted claims (recorded verbatim so they cannot be cited from an older copy)** | (1) *"You cannot difference aggregates that do not exist."* — deleted as the general answer to differencing; it is true about axes and false about populations (§5.3 B). (2) *"each fake data point costs a real ticket purchase"* — deleted; comps cost nothing and the `venue_manager` mints both the session and the comps (§11). (3) *"Removing any one of layers 1–3 still leaves a correct floor"* — deleted; layers 1 and 3 were the same function and only R2 was a database constraint (§5.2). (4) The R6-era bound *"an anonymity set of at least 5, matching the per-bucket floor"* — deleted; 5 contributor-pair changes is at minimum 3 people, and the ≥ 5 bound is restored only by the added distinct-identity limb (§5.3 vector 4). |
| **J-10** | Venue dashboard §9.5 card copy | **Correction (§4.3).** "Based on N of M" is a published-state string only — the suppressed state renders no numbers, no reason and no `as_of`. `M` is the R7-eligible paying population, not the room, and the subtitle says so. |

---

*This document is design-only. No SQL file, migration, rollback, or implementation code was written or
applied in producing it, and no production database was mutated.*
