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
> `event_session_id = :session AND state <> 'voided'`, at time `as_of`.
> The counting unit is **the person, not the ticket** — a fan holding four tickets is one holder.
> The rollup is `(event_session, dimension, bucket) → holder_count`, and nothing finer exists anywhere.

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

### 5.2 Minimum cell size and suppression — enforced in the database

Adopting the ratified dashboard §9.5 thresholds, and closing the two gaps that render-side rules cannot
close:

| Rule | Value | Where enforced |
|---|---|---|
| **R1 — event minimum** | `holders_responded >= 25` (k = 25) | Rollup writer refuses to publish; snapshot persisted as `suppressed`, zero bucket rows. |
| **R2 — per-bucket floor** | every persisted bucket `holder_count >= 5` | **A `CHECK (holder_count >= 5)` constraint on `venue.holder_mix_bucket`.** A sub-floor bucket is not merely hidden — it **cannot physically be stored.** |
| **R3 — mandatory merge** | buckets below the floor are merged into `other`, smallest first, repeating until `other >= 5` | Rollup writer. |
| **R4 — completeness (the complement rule)** | `SUM(bucket.holder_count) = snapshot.holders_responded`, always | Writer assertion + nightly reconciliation job (the C27 counter-vs-ledger pattern) + pgTAP assertion 16. |
| **R5 — all-or-nothing** | if R3 cannot produce a set where *every* persisted bucket ≥ 5, the snapshot is `suppressed` and **zero** bucket rows are written | Rollup writer. |
| **R6 — publication churn gate** | see §5.3 defence 4 | Rollup writer. |

**Why R4 is not optional.** The card publishes `N` (`holders_responded`). If suppressed buckets were simply
omitted, the residual `N − Σ(shown)` would be computable — suppressing a single small bucket would *hand
over* its exact count. Mandatory merge into `other` means the published set always sums to `N` and there is
no residual to compute. R5 is the corollary: when merging cannot reach the floor (e.g. 25 responses split
23/1/1 — `other` would be 2), the whole dimension suppresses rather than leak.

**Worked example — the 40-person event from the brief.** 40 holders, 26 responded: 20 `woman`, 5 `man`, 1
`non_binary`. R1 passes (26 ≥ 25). R2 fails for `non_binary` (1 < 5). R3 merges it toward `other`; `other` =
1, still below the floor, so the next-smallest bucket (`man`, 5) merges in: `other` = 6. Persisted:
`woman = 20`, `other = 6`, summing to 26. The single non-binary holder is inside a bucket of six and the
venue cannot tell whether `other` contains one, six, or any mix. Had the split been 25/1 the merge could not
reach 5 and **R5 suppresses the entire card.**

**Three layers, and the database is load-bearing.** (1) The **rollup writer** applies R1–R6 before
persisting — suppressed values never enter a readable table at all. (2) The **CHECK constraint** makes a
sub-floor row unstorable even if the writer is wrong. (3) The **RPC** can only return what exists. (4) The
**UI** renders the suppressed copy. Removing any one of layers 1–3 still leaves a correct floor; the UI
alone is never the enforcement.

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

> **You cannot difference aggregates that do not exist.** The only materialized demographic aggregate is
> `(event_session, dimension, bucket) → count`. There is no per-ticket-type number, no per-promoter number,
> no per-time-window number, and no per-scan-status number anywhere in the database, in any view, in any
> cache, in any export, or behind any parameter. The intersections the brief warns about are not blocked at
> a policy layer — **their operands are absent.**

This defence is structural rather than procedural, which is exactly the property the constitutions favour
(C36's "type error, not a lint finding"). It also composes with the four residual vectors:

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
   **Defence R6 — the publication churn gate:** a new snapshot is published **only if at least 5 distinct
   identities have entered or left the holder set since the last published snapshot** (adds + removes, so
   refunds and transfers-out count). Otherwise the previous snapshot stands unchanged and the recomputation
   is discarded.
   **Why this is sufficient, stated as a bound:** any observable change between two published snapshots is
   the aggregate effect of ≥ 5 distinct people entering or leaving. A bucket delta of +1 therefore
   attributes to *one of at least five* people whose membership changed, and the observer cannot tell which
   — an anonymity set of at least 5, matching the per-bucket floor. The bound holds for every delta of every
   bucket, including the final snapshot, because R6 has **no exemption** (the doors-open recomputation is
   published only if it also clears the churn gate; otherwise the prior snapshot simply stands as final).
5. **Historical time-series access** — there is none. `venue.get_holder_mix` takes no `as_of` and returns
   exactly one snapshot: the latest published one. There is no history endpoint, no "compare to last week",
   no trend line, and no export (§9). An observer must therefore poll and record by hand, which is
   rate-limited and audited (§11).
6. **Cross-event intersection (residual, bounded, stated).** An org running many events could in principle
   intersect the holder sets of two events it can see. Each event's chart independently obeys k = 25 and
   floor 5, so the smallest inferable group remains ≥ 5, and no cross-event or "unique people across my
   events" rollup exists to make the intersection convenient. This is a genuine residual, it is bounded, and
   it is recorded here rather than hidden.

### 5.4 Refresh cadence

- Recompute per open `event_session` **at most once per 24 hours**, plus one recomputation at doors-open.
- Each recomputation is published or discarded by R1–R6. A discarded recomputation leaves no row.
- The job is a `pg_cron`-invoked `SECURITY DEFINER` RPC (§10.3), `service_role`/definer EXECUTE only.
- **No edge function.** `INFERENCE:` keeping the entire computation inside Postgres means the demographic
  value never crosses a process boundary — no HTTP body, no function log, no error breadcrumb, no
  observability payload. That is a deliberate, checkable contribution to C34's future PII-sink inventory
  (§8.6).

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
contain no identity references at all** — only a session id, a dimension, an `as_of`, two totals, and bucket
counts. A published snapshot cannot be traced back to any contributor because the contributor set is never
stored.

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
| Nightly R4 reconciliation job | `NEW RPC` (definer) | **087** |
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

**Why package 087 and not 086.** The rollup reads `kernel.tickets.current_owner_id` (079) and
`catalog.event_session` (078) and nothing else — it deliberately does **not** read `venue.scan` (086),
because `admitted_mix` is not built (§4.1). 087 is chosen as the first package after the full custody +
session chain is adopted, keeping the demographic objects off the critical path of every MVP gate. The
rollup has **no dependency on 086** and could move earlier if the schedule wants it; it must not move
earlier than 084 (the late-binding FK adopt).

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
| `holders_total` | int — distinct holders of ≥1 non-voided ticket (the `M`) |
| `holders_responded` | int — distinct holders with a substantive answer (the `N`); `CHECK (holders_responded <= holders_total)` |
| `suppressed` | boolean |
| `suppression_reason` | text, `CHECK` ∈ `below_event_minimum` · `merge_cannot_reach_floor` · `null when not suppressed` |
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
- **Reads:** `kernel.tickets` (custody head, non-voided, for the session) ⋈ `kernel.identity_demographic`.
  **Does not read** `venue.scan`, `venue.order`, `venue.attribution`, `venue.ticket_type`, or any price.
- **Algorithm:** compute `holders_total`, `holders_responded`, raw bucket counts → apply **R1** → **R3**
  merge → **R5** all-or-nothing → **R6** churn gate against the last published snapshot → persist. R2 is
  additionally enforced by the CHECK constraint, R4 by a writer assertion.
- **Writes:** at most one `holder_mix_snapshot` (+ its buckets). A discarded recomputation writes nothing.
  Publishing a new snapshot un-publishes the prior one (the partial unique index enforces one published
  snapshot per session+dimension).
- **Returns:** `{ status: 'published' | 'suppressed' | 'discarded_churn_gate' }`.
- **SSCAS:** n/a — reads only, then writes one derived aggregate; it is **not** a member of the closed set
  and touches no money, custody, or inventory row.

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
- **Returns:** either
  `{ suppressed: true, reason, holders_total, holders_responded }` — with **no bucket rows** — or
  `{ suppressed: false, as_of, holders_total, holders_responded, buckets: [{bucket, holder_count}, …] }`,
  where the buckets always sum to `holders_responded` (R4).
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
| **A venue creating throwaway micro-events to isolate a person** | Same: k = 25 responses required per session. An event with one target attendee renders nothing. |
| **Sybil accounts to skew a chart** | Only identities holding a **non-voided ticket for that session** are counted, so each fake data point costs a real ticket purchase, and refunds remove it. |
| **Scraping via repeated reads** | Every `get_holder_mix` call is audited (actor, session, dimension, time) and rate-limited per principal, fail-closed (005/021 pattern). The export history / activity feed already surfaces staff reads (dashboard §17); demographic reads join it. |
| **Temporal differencing by a patient observer** | R6 churn gate — §5.3 vector 4. Bounded at an anonymity set of ≥ 5 per observable delta. |
| **A future engineer adding a filter parameter** | `get_holder_mix`'s two-argument shape is stated as a contract, asserted by pgTAP (arity/arg-name assertion 14), and the rollup has no finer-grained operands to filter over. |
| **Demographic data leaking through an export or an integration** | X-1…X-9 (§9), with X-6 as a CI check. |
| **Demographic value escaping through logs / observability** | No edge function, no external call, no log statement, no notification payload, no Sentry breadcrumb touches the value (§5.4). The value never crosses a process boundary out of Postgres. |
| **Re-identification by an operator who also knows the guest list** | Bounded, not eliminated: floor 5 means the smallest inferable group is 5 people, and no second axis exists to narrow it. Cross-event intersection is the stated residual (§5.3 vector 6). |
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

**(e) The one honest residual.** A venue with 40 holders and N = 26 learns that 14 people did not share. That
is a property of publishing any denominator at all, it identifies nobody, and it is the price of the
"Based on N of M" transparency the ratified card copy requires. Removing the denominator would make the
chart misleading, which is a worse trade.

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

**Suppression (R1–R6)**
13. `holder_mix_bucket` CHECK rejects an insert with `holder_count = 4` and accepts `5`. *(The floor as a
    database constraint, not a render rule.)*
14. **`venue.get_holder_mix` has exactly two parameters**, named for session and dimension, with no `as_of`,
    filter, limit, offset, or ordering parameter. *(The differencing contract, asserted.)*
15. A session with `holders_responded = 24` returns `suppressed`; the same session at 25 returns buckets.
16. **R4 invariant scan:** for every published snapshot, `Σ holder_count = holders_responded`.
17. **The complement case:** a 26-response session split 20/5/1 persists `{woman: 20, other: 6}` — the
    1-count bucket is absent, `other` ≥ 5, and the sum still equals 26 so no residual is computable.
18. **R5:** a 25-response session split 24/1 persists a `suppressed` snapshot with **zero** bucket rows.
19. **R6 churn gate:** a recomputation whose holder-set churn since the last published snapshot is 4 returns
    `discarded_churn_gate` and writes no snapshot; at churn 5 it publishes.
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

---

*This document is design-only. No SQL file, migration, rollback, or implementation code was written or
applied in producing it, and no production database was mutated.*
