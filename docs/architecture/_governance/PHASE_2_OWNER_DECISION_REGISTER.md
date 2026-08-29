# Phase 2 — Owner Decision Register

**Status:** INSTRUMENT, not authority. This file **decides nothing** and **changes nothing** — with one
exception, stated here so it cannot be missed: it now **records** an owner ruling that was taken outside it
(`ODR-23`). Recording a ruling is not making one. Everything else is a reading aid: one place where every open
owner decision in the Phase 2 design corpus is stated once, in the form a decision needs to be decidable — a
question with named options, the failure under each option, the direction silence falls, and what is blocked
until it is answered.

---

> ## BASELINE
>
> **Rebuilt 2026-08-28 against branch `phase2/consolidation` at `269e473`.**
> The previous edition was built at `32249f2` and was **53 commits stale**. It did not know `O17`, `O18`,
> `R2B-1`, `C110`–`C134`, `D23`, `D30`–`D35`, the seventh registry amendment, `SEAM-2a`, `SEAM-4`, or that
> `declared_edge_count` had moved 39 → 45. Its headline of **123** was a floor, not a count.
>
> **Corpus scanned:** every `.md` file under `docs/architecture/**` at `269e473` — **39** of them (23 at the
> top level, 12 under `_governance/`, 4 under `_superseded/`) — plus `ARCHITECTURE_FREEZE.md` at the
> repository root. **40 files.**
>
> ### How to tell when this file has gone stale again
>
> Run all four. **Any one of them failing means this register is out of date and its bands are unverified.**
>
> ```
> # 1. how far this file's baseline has drifted
> git rev-list --count 269e473..HEAD -- docs/architecture ARCHITECTURE_FREEZE.md
> #   0 = the corpus has not moved since this rebuild.
> #   Anything else = re-run checks 2-5 before citing any count below.
>
> # 2. no open decision exists that this file does not carry
> grep -oE 'OPEN-GATED\(O[0-9]+\)' docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md \
>   | sort -u | wc -l                   # must be 9 as of 2026-08-28: O6 O9 O10 O12 O13 O14 O15 O16 O18.
>                                       # Was 13; O7, O8, O11 and O17 were CLOSED by owner rulings
>                                       # OR-4, OR-5, OR-6 and OR-1. Was 11 at 32249f2. COUNT IT, do
>                                       # not carry it — this number has gone stale four times.
>
> # 3. the corpus has not grown a document this file did not read
> find docs/architecture -name '*.md' | wc -l    # must be 62 as of 2026-08-29 (recursive: 24 top-level
>                                       # + _governance + _superseded). Was written as "39", which was
>                                       # never reproducible against this recipe — the number counted
>                                       # top-level only while the command counts recursively. Recounted
>                                       # mechanically 2026-08-29: 61 before this pass, 62 after
>                                       # _governance/X8_CAP_MAP_ID5_OWNER_BRIEF.md. COUNT IT.
>
> # 4. the count below still equals its own enumeration
> grep -cE '^#{2,3} ODR-[0-9]+ —' docs/architecture/_governance/PHASE_2_OWNER_DECISION_REGISTER.md
>                                       # must be 128
>
> # 5. the status split still equals its own enumeration (116 + 4 + 3 + 1 + 3 + 1 = 128)
> REG=docs/architecture/_governance/PHASE_2_OWNER_DECISION_REGISTER.md
> for T in 'OPEN — OWNER' 'CLOSED — OWNER RULING' 'MECHANICAL / ENGINEERING' \
>          'SUPERSEDED' 'BLOCKED BY ANOTHER DECISION' 'SPLIT'; do
>   printf '%4d  %s\n' "$(grep -cF "**Status.** $T" "$REG")" "$T"
> done                                  # must print 116, 4, 4, 1, 2, 1 as of 2026-08-29
>                                       # (was 116, 4, 3, 1, 3, 1 — ODR-128 moved BLOCKED → MECHANICAL
>                                       # when X-8 resolved. COUNT IT, do not carry it.)
> ```
>
> **Check 2 is the one that matters.** Every previous staleness in this corpus was a count that moved while
> its enumeration did not; this register went stale because two open decisions (`O17`, `O18`) and one
> integrator filing routed to an owner (`R2B-1`) were opened in three concurrent remediation passes and
> nothing here watched for them.

---

## THE COUNT, AND THE ENUMERATION BESIDE IT


> **This corpus has been bitten five times by a count that was updated while its enumeration was not** —
> record rows `D9`, `D11`, `D15`, the freeze document's *"44 rows … three open decisions"* (repaired at
> `269e473` by `C125`/`D33`, and **already stale again**: see `DF-35`), and this register's own previous
> edition. `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` §12 states the tally: *"Count-without-
> enumeration drift bit this corpus five times."*
> Every list below is **generated from this file's own entry headings**, not transcribed beside them. If the
> two ever disagree, the headings are right and the count is wrong. Regenerate with:
>
> ```
> grep -cE '^#{2,3} ODR-[0-9]+ —' docs/architecture/_governance/PHASE_2_OWNER_DECISION_REGISTER.md
> ```


**There are 128 dispositioned owner-decision entries in this register**, of which **120 are open and
awaiting the owner**.

Not counted, and held in their own sections below: **26 rows** of items that read as open and are already
settled (**21 owner-facing + 5 integrator**; bookkeeping close only — several rows bundle a set, so they
cover far more than twenty-six filings), and **41 rows** (`DF-1` … `DF-41`, contiguous) of items filed in
decision-shaped registers that are design defects with one correct answer. **128 + 26 + 41 = 195**
dispositioned rows in this file. Nothing found in the sweep is left undispositioned.

### Split by status — five values, used exactly

| Status | Count | Ids |
|---|:-:|---|
| **OPEN — OWNER** — awaiting the owner; nobody else may close it | **116** | every entry not named in the five rows below |
| **CLOSED — OWNER RULING** — the owner ruled; the ruling, its date and its reason are recorded | **4** | `ODR-23` (`OR-1`, `B`) · `ODR-2` (`OR-4`, corpus `[A]` BUILD) · `ODR-3` (`OR-5`, corpus `[C]` GATE P REDUCED) · **`ODR-7`** (`OR-6`, HYBRID PRECEDENCE) |
| **MECHANICAL / ENGINEERING** — determined by the corpus or by engineering; should never have been in the owner's set | **4** | `ODR-15` · `ODR-126` · `ODR-127` · **`ODR-128`** *(moved 2026-08-29: its blocking decision and all three fail-closed contradictions are resolved; 28 transcription sites remain)* |
| **SUPERSEDED** — overtaken by a later ratified row or ruling | **1** | `ODR-52` |
| **BLOCKED BY ANOTHER DECISION** — cannot be ruled until a named decision closes first | **2** | `ODR-81` (by `ODR-20`) · `ODR-100` (by `ODR-101`) — *`ODR-128` left this row 2026-08-29 when its own retention condition was met; see the MECHANICAL row* |
| **SPLIT** — the original question was rejected as misframed; the limbs carry their own statuses and the family is not closed | **1** | `ODR-4` (`OR-2`: `4a` RULED · `4b` BLOCKED BY `ODR-16` · `4c` ENGINEERING · `4d` MECHANICAL) |
| | **128** | |

**116 = 128 − 4 − 4 − 1 − 2 − 1.** The twelve non-open entries are enumerated above in full.
*(2026-08-29: `ODR-128` moved BLOCKED → MECHANICAL; the twelve-member non-open set is unchanged in
membership, redistributed across statuses. The previous arithmetic, − 4 − 3 − 1 − 3 − 1, was correct for
its date.)*

> **THERE ARE SIX STATUS VALUES, NOT FIVE — corrected 2026-08-28.** The previous text asserted *"there is no
> sixth status"* while `OR-2` had already given `ODR-4` a sixth (`SPLIT`), and the header claimed `120` open
> while the file held `119`. Both were carried, not counted. Two edits make the recipe reproduce again:
> `ODR-4`'s marker was `**Status. SPLIT`, which the recipe's `grep -F "**Status.** …"` could never match, and
> the two new `CLOSED` lines were bolded past the marker, which broke it the same way. **If a status line
> does not begin exactly `**Status.** `, check 5 silently under-counts it.** That is the whole failure mode.

### Split by what each one blocks

**The banding was re-verified at `269e473`, entry by entry, and two entries moved.** One had been
mis-banded **downward by eleven packages** because a remediation pass moved its artifact and the band did
not follow; one had been banded above its own `Blocks` line. Both are recorded at `§ WHAT MOVED` below.

| Band | Count | Ids |
|---|:-:|---|
| **Band 1 — blocks the start of implementation** | **7 register entries, 3 still open — but the TRUE Band-1 set is 4, because `ODR-16` belongs here and the register bands it 2 (see its entry)** | `ODR-1` · ~~`ODR-2`~~ **CLOSED `[A]` BUILD** · ~~`ODR-3`~~ **CLOSED `[C]` GATE P REDUCED** · **`ODR-4` (SPLIT: only `4b` open, BLOCKED BY `ODR-16`)** · `ODR-5` · ~~`ODR-7`~~ **CLOSED — OWNER RULING HYBRID** · ~~`ODR-23`~~ **CLOSED — OWNER RULING B** |
| **Band 2 — blocks a named migration package** | **30** | `ODR-8` … `ODR-22` · `ODR-24` … `ODR-34` · **`ODR-125`** · **`ODR-126`** · **`ODR-127`** · **`ODR-128`** *(four new)* |
| **Band 3 — blocks a named surface, contract, control or feature flag** | **58** | `ODR-35` … `ODR-92` |
| **Band 4 — blocks nothing in the current scope** | **33** | **`ODR-6`** *(re-banded down from Band 1)* · `ODR-93` … `ODR-123` · **`ODR-124`** *(new)* |
| | **128** | |

**7 + 30 + 58 + 33 = 128.** Band 2's 30: `ODR-8`–`ODR-22` is fifteen, `ODR-24`–`ODR-34` is eleven, plus
four new. Band 4's 33: `ODR-93`–`ODR-123` is thirty-one, plus `ODR-6` and `ODR-124`.

**The full enumeration.**


**Band 1 — blocks the start of implementation** — 7 entries

- **ODR-1** — Re-ratify the amended package registry *(now **seven** amendments and **45** edges — see the entry)*
- **ODR-2** — Is the event outbox in Phase 2? · **CLOSED — OWNER RULING, corpus `[A]` BUILD** (`OR-4`)
- **ODR-3** — What gate is the `notify` schema at? · **CLOSED — OWNER RULING, corpus `[C]` GATE P REDUCED** (`OR-5`)
- **ODR-4** — Acknowledge the two global-posture exceptions, and bind whoever next edits migration `020`
- **ODR-5** — Execute the migration-history repair, and authorize it
- **ODR-7** — Precedence between delta specifications · **CLOSED — OWNER RULING HYBRID** (`OR-6`)
- **ODR-23** — Adopt the Layer-0 privilege wall for the export builder? · **CLOSED — OWNER RULING B**

**Band 2 — blocks a named migration package** — 30 entries

- **ODR-8** — Per-org refund/payout thresholds at launch? · `077`
- **ODR-9** — Were `org_marketing` and `org_promoter_manager` intended to be storable at the org grain? · `077`
- **ODR-10** — Is `kernel.approval_request` an aggregate class or an intent record? · `077`
- **ODR-11** — The six threshold values · `078` seeds
- **ODR-12** — The money-role grant-maturity window · `078` seed
- **ODR-13** — `door.*` config visibility: `restricted` or `public`? · `078` seed row
- **ODR-14** — Confirm k = 25 and cell floor = 5, and where the constants live · `077` CHECK
- **ODR-15** — `notify.push_token` as a new table, or additive columns on `public.push_tokens`? · **MECHANICAL**
- **ODR-16** — How account deletion behaves for an identity holding custody · **`077`** *(corrected from `079` 2026-08-28 — see the entry)* · **BAND 1**
- **ODR-17** — `kernel.door_freeze_override`: move the table to `079`, or take a `SEAM-2` hook? · `079`/`086`
- **ODR-18** — Does disbursement auto-fire on `close_settlement`, or require an explicit human request? · `085`
- **ODR-19** — What `kernel.payout.status='paid'` asserts · `085`/`087`
- **ODR-20** — Does `venue.set_event_security_config` exist at all? · `078` + `086`
- **ODR-21** — The door-session selector: `door_session_id` or `session_ref`? · `086`
- **ODR-22** — `record_scan` under `FOR SHARE`, and whether M2 is signed · `086`
- **ODR-24** — Operatorship change: the new operator's CRM starts empty, and who tells them · `087`
- **ODR-25** — Export artifact retention: 24 hours or 7 days? · `087` sweep constant
- **ODR-26** — Settlement close: `org_finance`, `venue_finance`, or both? · `087`
- **ODR-27** — Where does the bid ledger live? · `088`
- **ODR-28** — `venue.promoter_link.status`, or promoter-grain deactivation only? · `090`
- **ODR-29** — Does a typed code beat a link when they name different promoters? · `090`
- **ODR-30** — Commission basis: face subtotal, or gross including fees? · `090`
- **ODR-31** — Do codes need redemption caps or expiry by default? · `090`
- **ODR-32** — Who bears a post-settlement chargeback on a commissioned sale? · gates the promoter program
- **ODR-33** — Promoter portal: web, or in the RN app? · `090` classification
- **ODR-34** — May the subject read their own consent *history*? · `082` (additive)
- **ODR-125** — `R2B-1`: does `market.on_atom_voided` carry `p_cause`, and what may it hold? · frozen at `085` **(NEW)**
- **ODR-126** — Does `090` still revert as one unit now that the two order-candidate columns are born in `082`? **(NEW · MECHANICAL)**
- **ODR-127** — RPC §6.3 and §7.1 both claim the inventory write · `083` **(NEW · MECHANICAL)**
- **ODR-128** — The six cross-document contradictions that `ODR-7` converts into transcription **(NEW · BLOCKED)**

**Band 3 — blocks a named surface, contract, control or feature flag** — 58 entries

- **ODR-35** — Does `org_admin` hold the money-plane read? · **surface H is BLOCKED**
- **ODR-36** — Extend grant maturity to the platform plane, or retract the platform-plane claim?
- **ODR-37** — The payout tier's operand
- **ODR-38** — Does `kernel.tickets.resale_state` have one writer pair, or two writer sets?
- **ODR-39** — Should the buyer self-service arm additionally gate on order value?
- **ODR-40** — `refund.scanned_atom_policy`: `refuse` or `platform_review`?
- **ODR-41** — A single-money-principal org blocked from payouts: escalate, or relax?
- **ODR-42** — Ship step-up at `aal1` freshness now, or block money actions until MFA?
- **ODR-43** — May a `venue_manager` mint another `venue_manager`?
- **ODR-44** — Who may disable a transfer freeze?
- **ODR-45** — The platform sub-role read boundary
- **ODR-46** — Re-map legacy `venue_manager` grants when the six-label enum lands
- **ODR-47** — Ratify the session-bounded Wallet token profile · gates `wallet.apple.enabled`
- **ODR-48** — Acknowledge that Wallet may not ship before the door M2 tables and offline step 3b
- **ODR-49** — Security sign-off on the `verify_jwt=false` set · gates deploy
- **ODR-50** — Who owns the Apple Developer account and may renew the Pass Type ID certificate?
- **ODR-51** — Wallet budget: KMS, APNs, storage — and the optional M2 signer it gates
- **ODR-52** — Post-open issuance: build the manifest supplement, or accept online-only door sales? · **SUPERSEDED**
- **ODR-53** — Offer a credential or Wallet pass while `resale_state ∈ {listed, locked}`?
- **ODR-54** — Does the pass carry the holder's name?
- **ODR-55** — Does transactional email exist in Phase 2?
- **ODR-56** — Announcement hold window, dual-control threshold, and the step-up primitive
- **ODR-57** — May the marketing concept **release** announcements, or only draft?
- **ODR-58** — Do venue-staff notifications share the consumer inbox table?
- **ODR-59** — Notification retention, and the `C48` retention floor
- **ODR-60** — Universal Links / App Links before any sensitive deep-link target
- **ODR-61** — Marketing's CRM and analytics ceiling — answered once, for three specs
- **ODR-62** — Is a platform-plane bulk extraction path wanted at all?
- **ODR-63** — Is `display_name` consent-gated in the export?
- **ODR-64** — Confirm `R7`: comped and zero-price custody are excluded from the mix card
- **ODR-65** — Ship with the population-differencing residual, or close it?
- **ODR-66** — Five roles hold both the by-name roster and the mix card
- **ODR-67** — The backup-retention window `{N}`
- **ODR-68** — Confirm the MVP transfer-freeze predicate is session-wide
- **ODR-69** — Drain active listings and initiated transfers at door-open?
- **ODR-70** — Does opening the manifest early bother anyone commercially?
- **ODR-71** — Should the `C25` compensate branch void the seller's atom at all?
- **ODR-72** — Name the guest-list write RPCs · surface F
- **ODR-73** — Name the mark-a-guest-arrived RPC · the door
- **ODR-74** — Name the promoter record and link RPCs, and a live slug-availability read · surface E
- **ODR-75** — Grant the two door pre-confirm reads · the door-open confirm
- **ODR-76** — Name a capacity-change RPC for an existing batch · §8.4
- **ODR-77** — Name an update RPC for `catalog.event` / `event_session` · §7.3
- **ODR-78** — Name `kernel.update_organization` · §16.1
- **ODR-79** — Inventory warning thresholds
- **ODR-80** — Kill switches for the three features that have none
- **ODR-81** — Confirm `venue.set_event_security_config`'s key set and `revoke_signing_key`'s ack parameter · **BLOCKED**
- **ODR-82** — Confirm the offline clock-skew time-bucket is 30 seconds
- **ODR-83** — Accept the maturity-helper race residual, or amend the global lock order?
- **ODR-84** — Ratify the self-bid and self-offer narrowings
- **ODR-85** — The credential token TTL value and re-sign cadence
- **ODR-86** — KMS provider, signing algorithm, and token wire format
- **ODR-87** — Notification permission priming
- **ODR-88** — May `venue_box_office` refund cash at the door?
- **ODR-89** — Does `org_admin` read `venue.settlement`?
- **ODR-90** — Does the original promoter earn on a marketplace resale?
- **ODR-91** — What is the remedy for a genuinely wrong attribution?
- **ODR-92** — `venue.get_dashboard_summary`: schedule it, or accept N queries?

**Band 4 — blocks nothing in the current scope** — 33 entries

- **ODR-6** — What happens to the untracked `043_profiles_select_column_restriction.sql` *(re-banded down from Band 1)*
- **ODR-93** — Cross-region native resale: saga/escrow, or intra-region-only?
- **ODR-94** — Offline first-admit-wins consensus under clock skew and partition
- **ODR-95** — Resale-policy snapshot drift
- **ODR-96** — Per-event identity-verification strength
- **ODR-97** — Which privacy regimes apply? *(counsel)*
- **ODR-98** — Is gender identity special-category / sensitive personal information? *(counsel)*
- **ODR-99** — Which mandatory notification types are legally compulsory, and where? *(counsel)*
- **ODR-100** — The confidential-IP document in repository history *(counsel)* · **BLOCKED**
- **ODR-101** — Repository visibility: private now, or stay public?
- **ODR-102** — Buy the Supabase Pro plan?
- **ODR-103** — GitHub Copilot?
- **ODR-104** — Add `age_band` in a later wave?
- **ODR-105** — Does `platform_admin` get aggregate demographic access at all?
- **ODR-106** — Who owns the compelled-disclosure runbook?
- **ODR-107** — Does a native-rail resale purchase create a contact relationship?
- **ODR-108** — Acknowledge that consent withdrawal is a state change, not a hard delete
- **ODR-109** — Confirm the attendee-lookup limit numbers
- **ODR-110** — Does an operator ever need a printed door list?
- **ODR-111** — Confirm that no demographic-based send exists, in any form
- **ODR-112** — Sub-promoters or sub-codes with a split commission?
- **ODR-113** — Code-enumeration thresholds
- **ODR-114** — Migrate the 12 legacy inbox types into the registry, or leave them alongside?
- **ODR-115** — Quiet hours · the `security_email_changed` mirror sweep · the promoter digest
- **ODR-116** — Rotating barcodes later? Google Wallet?
- **ODR-117** — Δ6: `catalog.event.announce_at` / `on_sale_at` for a scheduled on-sale
- **ODR-118** — Δ7: `venue.ticket_type` sale windows and per-order min/max
- **ODR-119** — Δ8: event-scoped, auto-expiring staff grants
- **ODR-120** — Δ9: `venue.guest_list.promoter_id`
- **ODR-121** — Δ10: org and venue `brand_logo_ref`
- **ODR-122** — Retain `venue_finance`, and do not rename `org_member` → `org_affiliate`
- **ODR-123** — Break-glass for the door
- **ODR-124** — `O18`: is the traceability matrix under the freeze's Rule 1? **(NEW)**

### Which of the open entries default to the unsafe direction if nobody answers

In blocking order: `ODR-2` (no outbox is built) · `ODR-3` (`notify` is never scheduled and a binding
dashboard dependency dangles) · `ODR-4` (irreversible posture exceptions ship inside `077`, and one routine
edit to migration `020` reintroduces the sentinel defect) · `ODR-15` (four push-token fixes have no home —
the *answer* is now mechanical, the *scheduling* still is not) · `ODR-16` (account deletion stops working for
anyone who has ever held a ticket, the day `079` lands) · `ODR-18` (a money-out path with an ambiguous auth
model) · `ODR-19` (a failed transfer reads `submitted` forever) · `ODR-21` (edge §3.9a is unimplementable as
written) · `ODR-26` (silence ratifies the permissive reading of an explicitly open settlement authority) ·
`ODR-27` (an implementer invents a `market.bid` money surface at build time) · `ODR-35` (`org_admin` gets the
money-plane read, silently) · `ODR-36` (the platform money-key arm has no maturity floor today) · `ODR-37`
(payouts are splittable past the dual-control ceiling today) · `ODR-46` (a box-office lead keeps
door-lifecycle authority through the cutover) · `ODR-49` (an unauthenticated endpoint ships unreviewed) ·
`ODR-50` (nobody owns the certificate that fails on a calendar) · `ODR-55` (a mandatory money notice with
push as its only channel) · `ODR-63` (every export file's shape is undecided) · `ODR-65` (an unquantified
inference channel ships unstated) · `ODR-75` (the door-open confirm asks a question the operator cannot
evaluate) · `ODR-80` (three features with no runtime kill switch) · `ODR-87` (a cold OS prompt loses the push
permission permanently) · `ODR-91` (no remedy exists, and support will ask for one within the first month) ·
`ODR-124` (the freeze's covered set stays wrong and more documents drift outside Rule 1) · `ODR-125` (an
unvalidated free-text string enters a custody/money compensation path, and the signature freezes at `085`) ·
`ODR-128` (six contradictions, and an implementer picks a side per file).

**That is 24** — the count is written after the list, from the list, for the reason in the box above.
**Recomputed 2026-08-28:** `ODR-2` and `ODR-3` were struck from this list when the owner ruled them, so the
figure moved 26 → 24 in the same edit that removed the two entries. A count that survives the removal of its
own members is the defect this register exists to prevent.
It was **25 of 123** at `32249f2`; `ODR-23` and `ODR-52` left the set (ruled and superseded respectively)
and `ODR-124`, `ODR-125` and `ODR-128` entered it. **25 − 2 + 3 = 26.** For these twenty-six, *not deciding*
is not deferral: the unsafe branch is already the one that ships.

### If only a few can be answered

**The corpus now states its own ruling order, and this register defers to it.**
`_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` §0.3:

```
O11  →  ODR-2  →  ODR-3  →  O17  →  ODR-4  →  ODR-1  →  R2B-1
```

In this register's ids that is
**`ODR-7` → `ODR-2` → `ODR-3` → `ODR-23` → `ODR-4` → `ODR-1` → `ODR-125`.`ODR-23` has since been ruled**, so
six remain. `ODR-7` goes first because six of the seven cross-document contradictions on the work plan **are**
delta-vs-delta conflicts (`ODR-128`), and ruling `ODR-7` converts them from decisions into transcription.
`ODR-1` goes late because it ratifies the outputs of the others.

**Two prerequisites the brief names, neither of them a decision:** close `G-25` before pricing `ODR-2`
(*"an owner pricing the O7 ruling is reading a list that a ratified correction already reduced by more than
half"* — `DF-23`), and give `ODR-4` one specialist pass before ruling it (the brief's own §D–G reads
*"Not analysed in this pass … It needs one specialist pass before you rule it"*).

---

## WHAT MOVED SINCE `32249f2` — the delta, stated so nothing is lost

Rule of this rebuild: **no prior entry is renumbered, reworded away or dropped.** Where an entry's substance
changed because the corpus moved, the id is kept and the change is recorded **with its cause**.

### One owner ruling recorded

| Entry | Was | Is | Recorded at |
|---|---|---|---|
| `ODR-23` / `O17` / `MD-2` | Band 2, OPEN, *"before `087`"* | **Band 1, CLOSED — OWNER RULING B**, 2026-08-28 | the entry itself, in full, with the owner's reason verbatim |

### Two entries re-banded, and why

| Entry | Was | Is | Cause |
|---|---|---|---|
| `ODR-23` | **Band 2** (*"before `087`"*) | **Band 1** — it gates `076`, the **first** Phase-2 migration | Ratified **`C115`** applied the new rule **`SEAM-4`** (*"a `GRANT` is authored at `max(relation, grantee role)`, and a role owed a grant from package `N` is created at or before `N`"*) and moved `CREATE ROLE crm_export_builder NOLOGIN` from `087` to **`076`**, with the first (column-scoped `auth.users`) grant in `076` itself. **A pass moved the artifact and the band did not follow — eleven packages of mis-banding, downward.** The brief states the consequence in one line: *"This decision gates the first migration, eleven packages earlier than three documents advertise."* **`HG-4`, CRM §13 `D-2`, RLS `MD-2` and record row `O17` all still say `087` at `269e473`** — see `DF-39`. |
| `ODR-6` | **Band 1** | **Band 4** | Its own `Blocks` line already read *"**Nothing numbered**; it collides with the `076`–`091` reservation that `ODR-1` ratifies."* Band 1 means *nothing downstream is safe to begin*, and that is not true of this one. Re-verified at head: the file is **untracked and on another branch** (`git ls-files supabase/migrations` returns 89 paths and none is `043_*`), and `_governance/PHASE_2_PREIMPLEMENTATION_CLOSEOUT.md` §9's own heading says of its whole list *"none blocks **authoring** `076`"*. **The hazard is real and the band was wrong.** |

### Five entries added

| New | What it is | Why it was missing |
|---|---|---|
| `ODR-124` | **`O18`** — is `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` (and `PHASE_2_SCOPE_AMENDMENT_2026_08.md`) under the freeze's Rule 1, or deliberately outside it? | Opened by the `R3` register-integrity pass (`D35`(d)) **after** `32249f2`. It also arrives carrying a contradiction — see the entry. |
| `ODR-125` | **`R2B-1`** — does `market.on_atom_voided` carry a third parameter `p_cause`, and what may it hold? **Frozen at `085` by `SEAM-2a`.** | Opened by the `R2B` replay-ordering pass (`C117`/`D23`) after `32249f2`, and deliberately **not** given an `O` id: *"every owner decision this pass encountered was already open under an existing id … and is routed there rather than re-numbered."* `R2B-1` had no home in any consolidated index, and its id **collides** — see the entry and the dedup ledger. |
| `ODR-126` | Does `090` still *"revert as one unit"* now that `venue.order.attribution_candidate_code_id`/`_link_id` are born in `082`? | Third of the three owner-facing questions `D23` routed out of the `R2B` pass. **MECHANICAL** — filed to the promoter-spec owner, not to the founder. |
| `ODR-127` | RPC §6.3 and §7.1 **both** claim the inventory write on `kernel.issue_ticket_atoms`. | Found by Agent L at `8c06c60` and named in `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` §7 as *"where an implementer first stops"*, unregistered. **MECHANICAL** — intra-document, so no precedence rule of any form reaches it. |
| `ODR-128` | The **six** remaining cross-document contradictions of Final Report §8 item 2. | **BLOCKED BY `ODR-7`** — ruling delta-spec precedence converts all six from decisions into transcription. |

### Corrections folded into existing entries

| Entry | Correction | Cause |
|---|---|---|
| `ODR-1` | It said *"the **six** amendments"* and *"the **38**-edge dependency graph"*. There are **seven** amendments and **45** edges. | The seventh amendment (`R2B`) landed after `32249f2`; `declared_edge_count` went 39 → 45 with six edges added and enumerated (`081→083`, `078→085`, `081→085`, `083→085`, `086→088`, `087→088`). Two further edges are **owed and declared nowhere** (`078→086`, `077→090`). |
| `ODR-3` | Two additive asks now ride it that the entry did not name: `Δ-N1` (`catalog.event_session.session_version`, correctness-blocking — `DF-24`) and `Δ-N2` (`kernel.identity_ext.locale`). | Notifications spec Appendix B, `ADDITIVE SCHEMA CHANGE` row. |
| `ODR-15` | Re-classified **MECHANICAL / ENGINEERING**. | The brief's *"decisions removed from the owner set as mechanical"* appendix. |
| `ODR-19`, `ODR-16` | Their **writers** are now contracted (`C104`, `C107`, `C109`, `C124`); the **decisions** are untouched and both records restate them as open. | `R1` unapplied-filings pass. |
| `ODR-27` | The `087 → 088` edge it needs is now declared (`C118`). | `R2B`. |
| `ODR-29`, `ODR-28` | Their columns moved: the two order-candidate columns are born in `082` (`C112`), and `venue.resolve_order_attribution` is now a `SEAM-2` hook (stub `085`, body `090`) (`C111`). **The decisions still gate `090`**; only the substrate moved. | `R2B`. |
| `ODR-52` | **SUPERSEDED.** | Door §7.7 + RPC §6.3/§12.4c, re-derived as mandatory by ratified `C113`. |

---

## How to read this file

**Nothing here is a ruling and nothing here is new** — except the one recorded ruling at `ODR-23`, which was
taken by the owner elsewhere and is transcribed here with its reason verbatim. Every other entry is assembled
from text that already exists in the corpus. Where the corpus carries a recommendation it is **quoted**, with
its source named; where it carries none — several deliberately carry none — the entry says so. Where two
documents disagree, both positions are stated and neither is preferred.

**One decision, one entry, one id.** The corpus files the same decision in as many as five places under as
many as three different ids. This register merges those into one entry and lists every filing site, with the
evidence for the merge.

**The `Status` line is new, and it is the second thing to read.** It is one of exactly five values:

| Status | Meaning |
|---|---|
| **OPEN — OWNER** | Awaiting the owner. **Nobody else may close it** — not a remediation pass, not this file. |
| **CLOSED — OWNER RULING** | The owner ruled. The entry records the ruling, the date, and the reason. **A prior owner ruling is never silently altered**; there is exactly one so far. |
| **MECHANICAL / ENGINEERING** | Determined by the corpus or by engineering; it should never have been in the owner's set. The entry says **what determines it** and **cites the authority**. |
| **SUPERSEDED** | Overtaken by a later ratified row or ruling. The entry **names what superseded it**. |
| **BLOCKED BY ANOTHER DECISION** | Cannot be ruled until a named decision closes first. The entry **names it**. |

**The `Silence` line is the one to read first.** Every entry states what happens if nobody answers, and
whether that direction is **SAFE** or **UNSAFE**. Twenty-six default to the unsafe direction — the permissive
grant, the missing floor, the unbounded value, the endpoint that ships unreviewed. A decision whose silent
default is safe can wait; one whose silent default is unsafe cannot, because *not deciding* is already a
decision and it has already been taken.

**Ordering.** Entries are ordered by what they block, most blocking first, then by blast radius:

| Band | Meaning |
|---|---|
| **Band 1 — blocks the start** | Must be answered before the first Phase-2 migration (`076`) or before the package DAG can be re-ratified at all. Nothing downstream is safe to begin. |
| **Band 2 — blocks a named migration package** | Implementation can start; one identified package in `076`–`091` cannot be authored correctly until this closes. Ordered by package number. |
| **Band 3 — blocks a named surface, contract, control or flag** | The migration chain proceeds; one identified surface, authority cell, contract or feature flag cannot be built or turned on. Ordered by blast radius — money plane, then door and Wallet, then product surfaces. |
| **Band 4 — blocks nothing in the current scope** | Real and unanswered, but nothing in Phase 2 waits on it. Includes the four counsel questions and four platform questions from outside the design corpus. |

> **How the banding was re-verified at `269e473`, because it failed once.** For every entry the artifact it
> names — a table, a column, a role, a function, a grant, a policy, a seed, a flag — was resolved to a package
> through `PHASE_2_PACKAGE_REGISTRY.md` §2.1 and `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 **at head**, not
> through the entry's own prose. That is the check `ODR-23` failed: its prose said `087` because four
> documents say `087`, while the registry at head puts its artifact in `076`. **An entry's band is a property
> of where its artifact lives, not of what its filing sites claim.**

---

## The id namespace, and what is still true of it

Ids in this file are **`ODR-1` … `ODR-128`** (*Owner Decision Register*). They are **additive**. They rename
nothing, renumber nothing, and replace no existing id anywhere in the corpus: every entry keeps and lists its
original ids, and those ids remain the ones to cite in their own documents.

**`ODR-` is now in use — by this file, and by five others.** The previous edition proved the prefix unused at
`32249f2`. At `269e473` it is cited as a live id by `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` §8/§9,
`_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` throughout, and `ARCHITECTURE_FREEZE.md`'s covered-set
section, which brings this file **inside Rule 1** (ratified `C126`). **That has a consequence stated here so
nobody trips on it:** editing this register is now an act requiring a ratified correction id, and this rebuild
is authorised as the third item of the brief's *"prerequisites to close before ruling"* — *"Rebuild the
owner-decision register at head — it is 53 commits stale and does not know `O17`, `O18` or `R2B-1`."*
`C126` also states the reading rule for it: *"its content is **derived**, so on any disagreement the owning
document governs and the register is corrected, never the reverse."*

The full map of the series this register had to cross is at the end of the file. It has grown from
**22** to **31** since `32249f2`, entirely through the six 2026-08-28 remediation passes minting private
id namespaces (`MB-n`, `MP-n`, `MN-n`, `R1-n`, `R2B-n`, `R3-n`, `R4-n`, `S2-n`, `V-n`, `DR-n`).

---

## How the corpus was searched, and why one pattern was not enough

The corpus does not mark open owner decisions consistently — that inconsistency **is** the problem this file
exists to solve, so the search could not assume any single marker. Every file listed above was read, and the
following independent sweeps were run across `docs/architecture/**` and `ARCHITECTURE_FREEZE.md`:

1. **The ratification record's own status table and every `OPEN-GATED(On)` token.** At `269e473`,
   `grep -oE 'OPEN-GATED\(O[0-9]+\)' | sort -u` returns **9 distinct ids as of 2026-08-28 — `O6` `O9` `O10` `O12` `O13` `O14` `O15` `O16` `O18`** (it returned 13 before the owner closed `O7`, `O8`, `O11` and `O17` via `OR-4`/`OR-5`/`OR-6`/`OR-1`). It returned 11
   at `32249f2`. **This is the sweep the previous edition did not have to re-run and this one does.**
2. **The register tables**, each under its own local id scheme — money §11 (`D-1`…`D-10`), CRM §13
   (`D-1`…`D-13`), demographics §14 (`D-1`…`D-14`), schema §13.7 + **new** §13.7a (`S-1`…`S-27`), RPC §20.14
   (`R-1`…`R-33`), RLS §15.7 (`MD-1`…`MD-19`) and §17 (`X-1`…`X-19`), role model §13 (`OD-1`…`OD-11`), door
   §16 (`OQ-1`…`OQ-8`) and **new** §21 (`DR-1`…`DR-3`), Wallet §15 (`OQ-W1`…`OQ-W10`), notifications §10
   (`O-N1`…`O-N15`), promoter §13 (bare `1`…`10`) and §14, registry §7 (`COND-A/B/C`) and §7.1, dashboard
   §20A.3 (`U-1`…`U-10`) / §21 (`Δ1`…`Δ12`) / §22 (`§22.1`…`§22.16`), edge §9 (unnumbered `1`…`17`), RN §12
   (unnumbered `1`…`13`), scope amendment §11 (`HG-1`…`HG-8`) and §14.2 (`OD-01`…`OD-81`).
3. **Status-word markers:** `OPEN-GATED`, `OPEN — owner`, `OPEN — recorded, not applied`.
4. **Prose markers:** `OWNER DECISION`, `OWNER-DECISION`, `owner ruling`, `the owner's`, `owed to the owner`,
   `owner must`, `awaiting owner`, `requires owner`, `owner ratification`, `owner sign-off`,
   `not decided here`, `recorded, not made`, `recorded rather than taken`, `left with its owner`.
5. **Negative-space markers** — the phrases the corpus uses when it declines to decide:
   `NO RECOMMENDATION IS OFFERED`, `Not made here`, `NO SIDE IS TAKEN`, `the choice is the owner's`,
   `a decision I declined to make alone`, `open question`, `must be chosen`, `not chosen`.
6. **The "what this pass deliberately did NOT do" paragraphs**, which every remediation pass in the record
   writes and which are where several decisions are named and nowhere else indexed. **All six 2026-08-28
   passes were read this way** — it is how `R2B-1` and the `090` single-unit-revert question were found:
   neither appears in any register table anywhere.

Sweep 6 is the one that matters. The decisions with the most careful reasoning behind them are precisely the
ones whose authors refused to write a recommendation, and those rows contain none of the words in sweep 4.

---

## What this file deliberately did NOT do

- It **decided nothing.** No option is chosen, no default is endorsed, no recommendation is authored. Where a
  recommendation appears it is quoted from the corpus and attributed. The single ruling recorded at `ODR-23`
  was taken by the owner, not here, and its reason is transcribed verbatim rather than paraphrased.
- It **closed nothing else.** The "appears open, is in fact settled" section names decisions a later ratified
  row or spec already answered, with the evidence — it does **not** close them. Closing them is a bookkeeping
  act in the ratification record, and that is an owner act under Rule 1.
- It **renumbered nothing and dropped nothing.** Every `ODR-n` from the previous edition survives with its id,
  including the ruled one, the superseded one and the three reclassified ones. New entries take `ODR-124`
  onward.
- It **altered no prior owner ruling.** There is exactly one, it is `ODR-23`, and it is recorded as given.
- It edited **no** other document, **no** `OFFLINE-VERIFY-v1` fenced block, nothing under `.github/`,
  `supabase/` or any migration. **No production contact of any kind was made.**

# BAND 1 — blocks the start of implementation

Seven decisions. **Nothing downstream is safe to begin until these are answered**, and two of them
(`ODR-1`, `ODR-5`) block work that has not started rather than work in progress, which is the cheapest
moment they will ever be answered at.

**One of the seven is now closed** (`ODR-23`, ruled B on 2026-08-28) and **one arrived here from Band 2**
(the same entry — see `§ WHAT MOVED`). **One left for Band 4** (`ODR-6`). The band is still seven.

**Ruling order inside this band, from the corpus:** `ODR-7` → `ODR-2` → `ODR-3` → *(`ODR-23`, ruled)* →
`ODR-4` → `ODR-1`.

---

## ODR-1 — Re-ratify the amended package registry

**Status.** OPEN — OWNER.

**The question.** Does the owner ratify the **six amendments the package registry has already written into
itself**, or send one or more of them back?

**The six, as the registry states them:** (1) `kernel.approval_request` placed in `077` + two packages renamed
(`083_kernel_signing_key` → `083_kernel_credential_infrastructure`, `087_venue_settlement` →
`087_venue_settlement_and_export`) + seven dependency edges; (2) the schema-security remediation (additive to
`077`/`078`/`086`/`090`, adding `venue.door_session` and recommending edge `086 → 087`); (3) the
`crm-export-worker` amendment; (4) the `K-2`/`K-3` missing-object repair (`kernel.identity_contact_pref_event`
→ `077`, `kernel.org_contact_consent_event` → `082`, the `087` purge substrate, edges `077 → 082` and
`078 → 082`); (5) `AUTHZ-PKG1` — four venue-plane read policies move `078`/`079` → `080`, edge `079 → 080`;
(6) the `MB-2`…`MB-5` unwritable-control pass.

**What breaks under each option.** *Ratify* — nothing; the registry's stated content is what every other
document already builds against. *Do not ratify (or leave it open)* — registry rule §6.5 says *"this registry
is updated **only** by ratified amendment."* Every package authored against the current text is therefore
authored against unauthorized content, and the sixteen-package band `076`–`091` has no ratified statement
behind it. This is not a documentation nicety: `SEAM-1` placement, the 38-edge dependency graph and the
rollback ordering all derive from the registry.

**Which way silence falls.** The registry stays `PENDING RE-RATIFICATION` and **no package may be authored at
all.** The default is **safe but total** — it is the one open decision whose silent default stops work rather
than shipping a defect.

**Blocks.** **Authoring any package.** Every migration in `076`–`091`.

**Filing sites.** `PHASE_2_PACKAGE_REGISTRY.md` header (six `⚠ AMENDMENT PENDING RE-RATIFICATION` blocks) ·
`PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2-K `OD-79` · `_governance/PHASE_2_RATIFICATION_RECORD.md` rows
`C72` / **`O10`** and `C73`/`C74` (`RATIFIED-PENDING-REGISTRY-RE-RATIFICATION`) ·
`PHASE_2_ROLE_MODEL_SPEC.md` §13 `OD-10` · `PHASE_2_PROMOTER_CODES_SPEC.md` §14.1 ·
`PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N7` · `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §22.15 ·
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.13 header and §3.10a header (both *"requires
re-ratification"*).

**Does the corpus recommend?** **Yes.** `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2-K, the scope amendment's
own consolidated index: *"Ratify as amended; the count changes to 17 only if OD-14 is Gate P."* The registry
itself declines to recommend on its own amendments, noting only *"No change here is an owner **decision**"* —
i.e. it claims the amendments are mechanical, not that they are ratified.

**Note.** `ODR-3`'s answer changes this one's arithmetic: `notify` at Gate P makes the band `076`–`092` and
seventeen packages, which falsifies the registry §2 assertion of *"16 packages … no gaps, no duplicates"*.
Answer `ODR-3` in the same sitting or ratify conditionally.

> ### AMENDMENT AT `269e473` — this entry's own arithmetic moved, and the instrument stating it went stale
>
> **The body above says "the SIX amendments" and "the 38-edge dependency graph". Both are wrong at head.**
> Preserved above rather than rewritten, because what the entry said and why it changed are both part of the
> record. The corrected figures:
>
> | | Said above | At `269e473` | Cause |
> |---|:-:|:-:|---|
> | Amendments pending re-ratification | six | **seven** | The **SEVENTH AMENDMENT** (`R2B`, the replay-ordering pass) was written into the registry header by ratified rows `C110`–`C118`/`D23`. Verify: `grep -c 'AMENDMENT PENDING RE-RATIFICATION' docs/architecture/PHASE_2_PACKAGE_REGISTRY.md` returns **7**. |
> | `declared_edge_count` | 38 | **45** | 38 → 39 by the fifth amendment (`AUTHZ-PKG1`, edge `079 → 080`); 39 → 45 by the seventh, **six added and enumerated**: `081 → 083` · `078 → 085` · `081 → 085` · `083 → 085` · `086 → 088` · `087 → 088`. Two of the six (`078 → 085`, `087 → 088`) were owed before that pass. |
>
> **The seventh amendment, as the registry states it:** the composite type `kernel.settlement_line_candidate`
> scheduled in `087` (`C116`/`S2-A` — it was the declared `RETURNS SETOF` type of two stubs and was created by
> nothing, so `087` failed `42704`); `market.on_atom_voided` fixed to its three-parameter form and the new
> binding rule **`SEAM-2a`** (`C117`/`S2-B` — a hook's parameter list, parameter **names** and return type are
> frozen at the stub, `CREATE OR REPLACE` may change only the body, and the replacing package asserts
> `COUNT(*) = 1` over `pg_proc`); `SEAM-1` corrected to take `max()` over what a body can **reach**, calls
> included; the new rule **`SEAM-4`** (a `GRANT` is authored at `max(relation, grantee role)`); and **four
> objects moved** — `kernel.issue_ticket_atoms` `081→083`, `venue.finalize_primary_order` `082→085`, the pair
> `venue.order.attribution_candidate_code_id`/`_link_id` `090→082`, and the role `crm_export_builder`
> **`087→076`** (which is what re-banded `ODR-23`).
>
> **Two edge declarations are still owed and appear nowhere:** `078 → 086` (recorded OPEN precisely because
> fixing it needs an amendment) and `077 → 090` (recorded nowhere at all). Both are declaration-only, both
> strictly increasing, and neither changes rollout order, placement or rollback posture. The brief proposes
> absorbing them into the same signature: *"with two declaration-only edges absorbed: `078 -> 086` and
> `077 -> 090` (45 -> 47)."*
>
> **What is now mechanical about this entry, and what is not.** Verified independently at head by parsing all
> four declared surfaces — **16 packages, `076`–`091`, 0 gaps, 0 duplicates; 45 edges, set-equal across plan
> §2 mermaid, plan §3, registry §2.1 and registry JSON `depends_on`; every dependency strictly precedes its
> dependent; DAG acyclic; package set identical across seven surfaces; all 8 `SEAM-2` stub→replacement edges
> declared.** The brief's verdict: *"`ODR-1` is mechanical as to the thing it names. **Do not reopen package
> numbering — there is no defect that warrants it.**"* **What is not mechanical** is the signature: `ODR-3`
> can falsify the count (a Gate-P `notify` makes the band `076`–`092` and seventeen), `ODR-23`'s ruling B
> means part of what the seventh amendment places is **not built**, and the registry declines to self-ratify.
> **A bare "ratify the current registry" is the wrong signature; a conditional one is not.**

---

## ODR-2 — Is the event outbox in Phase 2? · **CLOSED — OWNER RULING**

**Status.** CLOSED — OWNER RULING, corpus option `[A]` BUILD — ruled 2026-08-28. Ratification row **`OR-4`**.

> **The corpus option letters are authoritative for this decision and MUST be used when citing it.**
> `[A]` = BUILD. `[B]` = WITHDRAW. An intermediate owner brief circulated a different A/B/C lettering in
> which `A` meant NO OUTBOX; that lettering is superseded and must not be used to record or cite this
> ruling. There is no `[C]`: a broker / generalized event bus is prohibited by ratified text
> (`SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.2–§6.3, *"Do not build a broker, do not build sagas"*), so it was
> never an admissible form of this decision.

**The ruling.** Build the minimal transactional outbox as part of Phase 2: one transactional outbox table;
writes occur in the SAME transaction as the authoritative state change; post-commit processing through ONE
drainer; idempotent consumers; retryable delivery; advisory-lock / single-drainer semantics as already
specified; existing cron infrastructure where appropriate.

**Explicitly NOT built:** Kafka · RabbitMQ · SQS · Pub/Sub · NATS · EventBridge · Redis Streams · any
external message broker · distributed saga infrastructure · a generalized event bus. These are not Phase-2
options and contradict the ratified modular-monolith architecture.

**Counting methodology, ruled with the decision.** STRICT: *an event requires an outbox carrier ONLY when a
named Phase-2 post-commit consumer/handler exists, or a ratified contract requires the post-commit effect.*
A vague context reference is not a handler. **The count is always derived from the enumeration**, never
carried forward. The enumeration lives in `_governance/ODR2_BUILD_CONSEQUENCE_MAP.md`.

**What this ruling does NOT do.** It does not author `076`. It does not decide `ODR-3` (see `COND-D` below —
the coupling constrains ORDER, not answer). It does not perform the cross-document remediation, which is
mapped in `ODR2_BUILD_CONSEQUENCE_MAP.md` and not yet applied.

<details><summary>Original open-decision text, retained for audit</summary>

**Status (superseded).** OPEN — OWNER.

**The question.** Build the event outbox table and drainer in Phase 2 as the constitution promises **(a)**, or
amend the constitution to withdraw the promise and re-scope Wallet push, door events and notifications **(b)**?

**The two forms, as the corpus states them.** **(a) the constitution is right** — an outbox package is
Gate-P/MVP work missing from the plan; placement is **`076`** (*"the table has zero FK dependencies, so no
producer package gains an edge"*), drainer on the existing 2-minute `pg_cron` heartbeat, schema
`notify.outbox` if `ODR-3` is Gate P and `kernel.event_outbox` otherwise. **(b) the implementation specs are
right** — DA §6.2/§6.3 must stop claiming an outbox exists in Phase 2, `C12`'s event-envelope guarantees have
**no carrier** at MVP, and every design that emits an envelope message needs a stated alternative transport.
The schema spec puts it plainly: *"There is no third option in which DA:1253 stands and nothing implements
it."*

**What breaks under (b), priced.** From `PHASE_2_PACKAGE_REGISTRY.md` §7: *"the entire Apple Wallet push path
(pass supersession runs in the outbox consumer specifically so Wallet can never block or roll back a custody
transfer — the two alternatives, moving it into the custody transaction or leaving a superseded pass live, are
both prohibited by ratified invariants); the door-manifest open transaction as specified (its steps are
all-or-nothing and the last one writes the envelopes); scanner push-to-sync; every notification.
**Unaffected:** CRM export …, demographics, promoter codes, and money authority — each carries its own
scheduler."* **What breaks under (a):** one table and one RPC on a cron that already runs — the constitution's
own anti-over-engineering budget, per the notifications spec.

**Which way silence falls.** No outbox is built, because no implementation spec schedules one. **UNSAFE.** The
traceability matrix states the consequence: four capabilities become *"unimplementable **as designed**, not
merely degraded"*, and the Wallet push path has *"**no admissible alternative design**"*.

**Blocks.** Package **`076`**. Hard gate `HG-2` (*"No Wallet push path, no door-manifest open transaction as
specified, no scanner push-to-sync and no notification may ship before the outbox ruling is made"*). The
traceability matrix adds a deadline: *"Neither ruling can be deferred past `083`."*

**Filing sites.** `_governance/PHASE_2_RATIFICATION_RECORD.md` row `C51` / **`O7`** (`OPEN-GATED`) ·
`PHASE_2_PACKAGE_REGISTRY.md` §7 **`COND-A`** + the registry JSON `conditionals[0]` ·
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.3 **CONDITIONAL A** · `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8
`COND-A` · `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §13.1 and §14.2-B `OD-13` ·
`PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N2` and §1.8 `CONFLICT-2` · `PHASE_2_RLS_PERMISSION_SPEC.md` §15.7
`MD-11` · `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `G-1` / `D4` · `SNATCH_IT_DOMAIN_ARCHITECTURE.md`
§0.4 and the §6.3 boxed note · `SNATCH_IT_CANONICAL_DATA_MODEL.md` §15 `C51/O7`.

**Does the corpus recommend?** **Split, and the split is recorded.** `PHASE_2_NOTIFICATIONS_SPEC.md` §10:
*"Build it. It is one table plus one RPC on a cron that already runs — the constitution's own
anti-over-engineering budget."* The scope amendment records the disagreement rather than resolving it:
*"`NOTIF` §10 recommends **build it** … **`REGISTRY` and `SCHEMA` decline to recommend.** Not decided here."*
The schema spec's own words: *"**This is a conditional package element and this integration does NOT decide
it.** It is specified here so that a YES ruling is an apply, not a design exercise."*

</details>

---

## ODR-3 — What gate is the `notify` schema at? · **CLOSED — OWNER RULING**

**Status.** CLOSED — OWNER RULING, corpus option `[C]` GATE P REDUCED — ruled 2026-08-28. Ratification
row **`OR-5`**.

> **Corpus option letters are authoritative.** `[A]` = Gate P, full platform. `[B]` = Gate L. `[C]` = Gate P
> REDUCED. The intermediate brief's A/B/C lettering is superseded and must not be used to cite this ruling.
> Note that `[C]` did not exist in any corpus document before the ODR-2/ODR-3 brief constructed it; the owner
> has now ruled it, so it is canon.

**The ruling.** Build the minimum notification infrastructure required for venue-native ticketing **before the
first native ticket is issued**. It MUST support the mandatory native-ticket notification paths that would
otherwise ship silent: native purchase confirmation · ticket issuance confirmation · refund/reversal ·
payout / money-control mandatory notices · event cancellation · material event changes · transfer-related
mandatory notices where Phase 2 requires them · door / credential operational notices where required ·
promoter commission notification required by the retained `#32` · the push/in-app delivery infrastructure
those paths need.

**Explicitly NOT built in this reduced gate:** venue announcement composer · announcement abuse-control
surface · generalized notification campaign system · generalized template/locale platform beyond what
mandatory transactional notices actually require · `notify.schedule` · announcement scheduling cron · **SMS**
· speculative marketing notification infrastructure.

**Three pre-authoring blockers must be closed or scheduled first** — `N1` transactional email, `N2` Universal
Links / one-tap escalation collision, `N3` money-emitter ↔ notification-catalog mapping. Their state is in
`_governance/ODR3_GATE_P_REDUCED_SCOPE.md`. **The package may not be authored while any is NOT READY.**

<details><summary>Original open-decision text, retained for audit</summary>

**Status (superseded).** OPEN — OWNER.

**The question.** Is `notify` a **Gate-P MVP context**, as ratified row `C7` says, or **Gate L /
do-not-build**, as all four implementation specs say?

**What breaks under each.** *Gate L* — the venue dashboard's §16.5 carries a **binding** dependency on the
notification plane, and RLS `MD-10` rules that no Gate-L object may carry one; every notification stays on the
frozen `public.notifications` path, which the schema spec describes as having *"**no preference matrix, no
mandatory-type guard, no delivery-state ledger, no dedupe key and no locale**"*, leaving the money spec's seven
money emitters, the door's events #37–#44 and Wallet's holder-facing updates with **no carrier**; and the
traceability matrix records `G-19` — preference toggles *"that gate nothing"*, which replicates a named live
production defect. *Gate P* — nine `notify.*` tables land as package **`092`** (floored there by `SEAM-1`
because `notify.drain_outbox` reads `venue.promoter_link` at `090`), **the count becomes 17 and the range
`076`–`092`**, which falsifies registry §2's *"no gaps, no duplicates"* assertion and requires the
re-ratification of `ODR-1`.

**Which way silence falls.** The four implementation specs win by weight of numbers, `notify` is never
scheduled, and the dashboard surface ships against nothing. **UNSAFE.**

**Blocks.** Package **`092`**'s existence; the package count and range; everything in RLS §16.9 and dashboard
§16.5; and — because `notify.outbox` versus `kernel.event_outbox` is decided here — the schema home of
`ODR-2`'s table.

**Coupling — this is binding on how the two are asked.** `COND-D`, stated in `PHASE_2_PACKAGE_REGISTRY.md` §7
and `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §13.3: outbox-in with `notify`-out is coherent; outbox-out with
`notify`-out is coherent; both in is coherent; **`notify`-in with outbox-out is not**, because *"the
notifications design **is** the outbox pipeline."* **Rule `ODR-2` first, then `ODR-3`, in one sitting.**

**Filing sites.** `_governance/PHASE_2_RATIFICATION_RECORD.md` row `C52` / **`O8`** ·
`PHASE_2_PACKAGE_REGISTRY.md` §7 **`COND-B`** + JSON · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.4
**CONDITIONAL B** · `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `COND-B` ·
`PHASE_2_SCOPE_AMENDMENT_2026_08.md` §13.2, §8, §14.2-B `OD-14` · `PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N1`
and §1.8 `CONFLICT-1` · `PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 `MD-10` ·
`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §22.16 · `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `G-2` /
`G-19` · `SNATCH_IT_CANONICAL_DATA_MODEL.md` §1.6 and §15 `C7`.

**Does the corpus recommend?** **Split.** `PHASE_2_NOTIFICATIONS_SPEC.md` §10: *"Ratify the reading that C7's
*eviction* is satisfied vacuously (the leaves were never in the kernel), **and separately** authorise `notify`
at Gate P on its own merits — because the venue dashboard already has a binding dependency on it (`§16.5`),
which no Gate-L object may have."* `PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 `MD-10` refuses: *"**Not resolved
here** — it is a stop-and-ask. §16.9's matrices are conditional."*

---

## ODR-4 — SPLIT by owner ruling 2026-08-28 · **the original single decision is REJECTED AS MISFRAMED**

**Status.** SPLIT — the family is NOT closed. The owner reviewed the four-specialist analysis
(`_governance/ODR4_OWNER_DECISION_ANALYSIS.md`) and rejected the original framing on 2026-08-28. The single
entry is replaced by four sub-decisions plus one scheduling action, each with its own status. **Do not mark
the `ODR-4` family CLOSED until every row below is terminal.**

| Sub-decision | Classification | Status |
|---|---|---|
| **`ODR-4a`** — the GP-2 `DELETE` exception **class** | **OWNER RULING** | **YES, IN PRINCIPLE** (2026-08-28). Ratifies the narrow DELETE exception class required for genuine withdrawal/erasure. **NOT permission to invent further GP-2 exceptions.** The architecture must **mechanically assert the exact closed exception set catalog-wide** so a future one cannot be added "by analogy." |
| **`ODR-4b`** — the `auth.users` **CASCADE posture** | OWNER RULING | **BLOCKED BY `ODR-16`** — not to be ruled or implemented until `ODR-16` determines whether `auth.users` is actually deleted. Under option A the row is retained, the cascade never fires, and the Gate-L crypto-shred that would compensate is not built in Phase 2. |
| **`ODR-4c`** — the sentinel binding on migration `020` | **MECHANICAL / ENGINEERING** | Not an owner decision. The prohibition becomes a **DB `CHECK` + standing assertion on every correctly enumerated relation in scope, before any of those relations can hold production data.** Time-critical: the `CHECK` is free while empty and impossible after one repointed row. |
| **`ODR-4d`** — the scope | **MECHANICAL** | Correct the scope to the relations that actually carry **each** exception, separately. **The unsupported "six-relation" statement is not retained** — two of the six carry no cascade and one carries `RESTRICT`. |
| **`ODR-4` package placement** | SCHEDULING ACTION | **PENDING DEPENDENCY PROOF.** Option 5 accepted in principle: defer the demographic objects from `077` to the `086`/`087` boundary **provided the dependency proof holds**. A package-placement action — **not** approval to build the demographic subsystem. |

**Standing blockers to shipping the affected objects, kept open by the owner and not waived by `ODR-4a`:**
the cascade is blocked by append-only row triggers · the `BEFORE DELETE` tombstone trigger is missing from the
package · the tombstone UPSERT is incompatible with its append-only/PK design · the tombstone retention window
is unresolved · there is no tombstone reaper · account deletion is non-transactional and half-completes.

**Consequence map:** `_governance/ODR4_SPLIT_CONSEQUENCE_MAP.md`.

**The question, as originally posed and now superseded, is preserved below for the record.**

**The question.** Accept, as named exceptions to two standing corpus rules, that (i) `kernel.identity_demographic`
carries a **definer-scoped `DELETE`** — the single `GP-2` exception in the whole model — and (ii) the
demographic and contact/consent relations carry **`ON DELETE CASCADE` from `auth.users`** against the corpus
`ON DELETE RESTRICT` default; **and** bind whoever next edits migration `020` never to repoint those rows to
the `019` anonymization sentinel?

**What breaks under each.** *No `DELETE`* — *"keeping a withdrawn gender answer as a tombstoned row would
defeat the withdrawal."* *`RESTRICT` instead of `CASCADE`* — account deletion **fails outright** on the log of
a permission the account already withdrew; the demographics spec calls an orphaned answer *"the worst possible
residue"*, and the registry adds that `RESTRICT` *"needs an erasure path designed, and none exists."*
*Sentinel repoint (the live `019`/`020` house pattern)* — *"a sentinel row holding 'consent granted to 40
orgs' would be an accumulating grant belonging to nobody, and the gate in §5.1 would evaluate it"*, and on the
demographics side it would *"pile every deleted user's gender answer onto a single identity and create a
'sentinel demographics' row."*

**Which way silence falls.** **UNSAFE, and specifically so.** The exceptions ship unacknowledged inside `077`
and are **not reversible once data exists** (`HG-8`) — and the third limb has no enforcement at all:
repointing to the sentinel **is** what `019`/`020` already do, so silence plus one routine edit to `020`
reintroduces the defect.

**Scope has changed since the sign-off was first requested.** `PHASE_2_PACKAGE_REGISTRY.md` §7.1
`OWNER-DECISION-K2-D3`: *"**`D-3`'s outstanding sign-off now covers SIX relations, not four.**"* The two
`_event` consent ledgers inherit the cascade mechanically — *"but `D-3` is an unresolved sign-off, and
silently widening its scope from four relations to six is exactly the shape of change rule §6.5 exists to
stop."*

**Blocks.** Package **`077`** (hard gate `HG-8`), and packages `077`/`082` for the two `_event` ledgers.

**Filing sites.** `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2-C `OD-19` and §11 `HG-8` ·
`PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §14 `D-9` and `D-11` (and §10.2, §8.2) ·
`PHASE_2_CRM_EXPORT_SPEC.md` §13 `D-3`, §11.2 and §9.5 (correction `K-6`) ·
`PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 `MD-9` · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.15.2 (its
**own** `D-3`, a different id from the money spec's) · `PHASE_2_PACKAGE_REGISTRY.md` §7.1
`OWNER-DECISION-K2-D3` · `_governance/PHASE_2_RATIFICATION_RECORD.md` row `D13`.

**Does the corpus recommend?** **Yes, on both limbs.** `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2-C: *"Accept
as the single GP-2 exception in the model; a second must not be granted by analogy."*
`PHASE_2_PACKAGE_REGISTRY.md` §7.1: *"**CASCADE (recommended, and what §1.15 specifies):** deletion is clean;
the fan's evidence dies with the account, consistent with `§9.2`."*

---

## ODR-5 — Execute the migration-history repair, and authorize it

**Status.** OPEN — OWNER.

**The question.** Execute the migration-history repair event now under owner authorization, or continue to
hold every Phase-2 migration?

**What breaks under each.** *Execute* — a one-time, authorized repair event with a documented procedure.
*Don't* — `ARCHITECTURE_FREEZE.md` rule 5 and the pre-implementation closeout both state the repair is
**required before any Phase-2 migration is applied to any real database**; the engineering execution protocol
strengthens rule 5 into an **unconditional** prohibition on Supabase automatic production deployment until the
owner has *visually* confirmed the dashboard control is off (`AUTODEPLOY-1`, step 10a). Applying `076` without
it puts an unrepaired history under a sixteen-package chain.

**Which way silence falls.** Nothing is applied — **safe**, and it is the second of the two decisions here
whose silent default stops work rather than shipping a defect.

**Blocks.** **Applying any Phase-2 migration to any real database.** Not authoring — applying.

**Filing sites.** `ARCHITECTURE_FREEZE.md` rule 5 · `_governance/PHASE_2_PREIMPLEMENTATION_CLOSEOUT.md` §9
item 1 · `_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` §1 (`AUTODEPLOY-1`).

**Does the corpus recommend?** **It recommends the sequence, not a choice** — the repair is described as owed
and its execution as requiring owner authorization; no document argues for deferring it.

---

## ODR-7 — Precedence between delta specifications · **CLOSED — OWNER RULING**

**Status.** CLOSED — OWNER RULING, **HYBRID PRECEDENCE** — ruled 2026-08-28. Ratification row **`OR-6`**.

**The ruling, in the owner's own terms.** Of the three forms record row `C75` put on the table —
**(a) recency**, **(b) subject-matter ownership**, **(c) remediation-tag precedence** — the owner ruled a
**deterministic hybrid**:

1. **SUBJECT-MATTER OWNERSHIP IS AUTHORITATIVE.** For every disputed architecture statement, first resolve
   the subject to its designated normative owner: money authority → the money spec · custody → the
   custody/kernel authority · RPC signature → the designated RPC authority · physical DDL placement → the
   package registry / migration-plan authority · RLS and grants → the designated authorization authority ·
   door lifecycle → the door authority · notification delivery → the notification authority · CRM/export →
   the CRM authority. **Ownership is NEVER inferred from which document was edited most recently.**
2. **RATIFIED REMEDIATION / CORRECTION PRECEDENCE IS A FALLBACK ONLY.** Where the owner map is genuinely
   silent, a directly applicable ratified correction row may resolve the conflict. **It does NOT override an
   explicitly assigned subject owner merely because it is newer or carries a tag.** Form (c) is therefore
   demoted from a rule to a tie-breaker.
3. **RECENCY HAS NO AUTHORITY.** Never *newest commit wins*, *newest markdown wins*, *latest edited document
   wins*, or *higher correction number wins* — unless a ratified authority explicitly says so for that exact
   subject. **Form (a) is rejected outright.**
4. **FAIL CLOSED ON UNRESOLVED SAME-TIER CONTRADICTIONS.** If two same-authority sources conflict, or subject
   ownership is ambiguous, or both sides carry valid ratified tags, or the owner map and the correction
   hierarchy cannot deterministically select one — **the implementer does not choose**. The contradiction must
   fail CI / readiness, be registered, and be resolved explicitly. **This is part of the ruling, not an
   implementation detail of it.**

**What the ruling supplies that the corpus lacked.** `C75` recorded that form (b) was *"correct but requiring
an owner map the corpus does not yet have."* That map now exists:
`PHASE_2_SUBJECT_MATTER_OWNER_MAP.md`. Rule 4 is enforced mechanically by
`_governance/PRECEDENCE_CI_GATE_SPEC.md` and `scripts/precedence_gate.py`, wired into a required CI check.

**What it does NOT do.** It does not resolve **intra-document** conflicts — two sections of the SAME normative
document contradicting each other remains a mechanical defect, not a precedence question, and `ODR-7` must not
be cited to settle one. It does not retroactively re-decide anything already ruled. And it does not rewrite
the history below: the `D14` pass's use of form (c) on one instance stands as recorded, including its own
caveat that it *"is not ratified as a general rule and must not be cited as one"* — the ruling now supplies the
general rule that pass declined to invent, and does so with form (c) subordinate rather than primary.

**Consequences, recorded not yet applied.** `ODR-128`'s cross-document contradictions convert from decisions
into transcription — enumerated in `_governance/ODR128_CONTRADICTION_RESOLUTION.md`. `_governance/ODR7_PRECEDENCE_CONSEQUENCE_MAP.md`
carries the full site list.

<details><summary>Original open-decision text, retained for audit — do not delete</summary>

**Status (superseded).** OPEN — OWNER.

**The question.** When two documents in the **same tier** — two delta specs, or a delta spec and an
implementation spec — state contradictory authority for the same object, which governs: **(a) recency**,
**(b) subject-matter ownership**, or **(c) remediation-tag precedence**?

**The three forms, verbatim from record row `C75`.** *"**(a) recency** — the later ratified correction
governs, mechanical but blind to whether the later document is the right owner of the section; **(b)
subject-matter ownership** — a named owner per subject (authority branches → RPC; predicates/grants → RLS;
physical columns → schema; the money-authority *model* → the money spec), correct but requiring an owner map
the corpus does not yet have; **(c) remediation-tag precedence** — where two documents state the same rule and
one carries a ratified correction tag (`AUTHZ-*`, `J-*`, `K-*`, `S-*`, `H-*`) and the other carries none, the
tagged text governs and the untagged is presumed pre-remediation."*

**What breaks with no rule — this already happened.** `PHASE_2_MONEY_AUTHORITY_SPEC.md` §6.2 and
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §17.2 both carried a **build-ready** authority branch for
`kernel.approve_refund_request` and they contradicted each other, with the money spec's branch keyed on two
strings that are stored nowhere — *"an implementer following it routes every parked refund to the org arm,
above-ceiling and consumed-atom cases included."* Nothing in the corpus ranked them: `PHASE_2_SPEC_FOUNDATION.md`
§0 says *"if a source document conflicts with this file, surface the conflict; **do not silently pick a
side**"* — correct, and silent on which side wins — and `ARCHITECTURE_FREEZE.md` Rule 3 ranks **tiers**, placing
every delta spec in one. **The only available action was *surface it*, and that is exactly what nobody did.**

**Which way silence falls.** The standing obligation stays `SPEC_FOUNDATION` §0's *surface, do not pick a
side* — **safe in principle, and demonstrably not what happens in practice**: the defect above stood as a
build-ready contract for a full remediation cycle. The `D14` pass resolved that one instance using form (c) and
recorded that its reasoning *"is not ratified as a general rule and must not be cited as one"* and **does not
generalize to a conflict where neither side carries a ratified row**.

**Blocks.** No package. It blocks **the next delta-vs-delta conflict**, which has no stated resolution — and
this register documents several places where two documents already disagree (`ODR-23`, `ODR-39`, and the
`resale_state` writer question at `ODR-80`).

**Filing sites.** `_governance/PHASE_2_RATIFICATION_RECORD.md` row `C75` / **`O11`** (`OPEN-GATED`) ·
`ARCHITECTURE_FREEZE.md` Rule 3 boxed note · `PHASE_2_SPEC_FOUNDATION.md` §0 ·
`PHASE_2_MONEY_AUTHORITY_SPEC.md` §13.2 and its header banner.

**Does the corpus recommend?** **No, explicitly.** Record row `C75`: *"**Ranking delta specs against each
other decides which document's authority statement binds an implementer, which is an OWNER decision. It is NOT
made here.**"*

---


## `ODR-6` — RE-BANDED TO BAND 4

**`ODR-6` is not in Band 1 at `269e473`.** It was re-banded **down to Band 4** — see the entry there, and
`§ WHAT MOVED` for the cause. The id is unchanged and the entry is unchanged; only its band moved, because
its own `Blocks` line always read *"nothing numbered"* and Band 1 means *nothing downstream is safe to
begin*.

---


## ODR-23 — Adopt the Layer-0 privilege wall for the export builder? · **CLOSED**

**Status.** CLOSED — OWNER RULING B — ruled 2026-08-28.
**Also filed as** `O17` (ratification record) · `MD-2` (RLS §15.7) · `D-2` (CRM §13) · `HG-4` (scope
amendment §11).

> ### THE RULING
>
> **OPTION B.** The CRM export function **stays `postgres`-owned**. The dedicated `crm_export_builder` role
> is **NOT created**. The Layer-0 dedicated-role design is **rejected for Phase 2**.
>
> **The owner's reason, verbatim:**
>
> > *"the proposed privilege wall has failed to converge across repeated independent reviews and introduces
> > silent fail-closed data-integrity failure modes into CRM exports. We will retain the existing
> > `postgres`-owned `SECURITY DEFINER` model and strengthen `X-6` through structural/catalog assertions and
> > behavioral fixtures rather than maintaining a parallel grant/RLS policy matrix."*
>
> **Ruled:** 2026-08-28. **Ruled against:** the two admissible forms as record row `O17` states them —
> *"**(a) adopt** — the twelve `_sel_svc_export` policies of §16.10 clause 1, the `T-RLS-POL-02` amendment of
> clause 3, and the column-scoped `GRANT SELECT (id, email) ON auth.users`; **(b) stay `postgres`-owned** —
> none of them is built and the zero-policy list stands unamended."* **B was chosen.** `BYPASSRLS` was never
> a third form and is refused under either.

**What the ruling settles, mechanically, and what each owning document must now be corrected to say.**
This register applies none of these; it names them so the bookkeeping act is a transcription and not a
re-derivation. Every one of them is stated conditionally in its own document already, on `MD-2`.

| Consequence | Owning document | The text that already anticipates it |
|---|---|---|
| The twelve `_sel_svc_export` policies are **not built**, and the zero-policy list **stands unamended** | RLS §16.10 clause 5, §16.11 `T-RLS-POL-02` | `C133`: the `T-RLS-POL-02` amendment and its four converse assertions are *"**all gated on `MD-2`, which the test reads rather than assumes**"* |
| `CREATE ROLE crm_export_builder NOLOGIN` (`076`) and its **thirteen** grants across `076`/`077`/`078`/`079`/`082`/`087` come **back out** | package registry §2.2 seventh amendment, migration plan §8 | Registry JSON: *"`C115` reverts as one unit if so: **one `CREATE ROLE`, thirteen grants, twelve policies, no other package affected**."* |
| `HG-4` **discharges** | scope amendment §11 | `HG-4` is the gate; the decision it gates is now taken |
| Record row `C133`'s `OPEN-GATED(O17)` status resolves to the **not-built** shape | ratification record | `C133`'s own status cell: *"**OPEN-GATED(`O17`)** on which shape is built"* |
| RLS §15.7 `MD-2`'s bare *"Adopt"* must be **struck**, not merely annotated | RLS §15.7 | `O17`: *"RLS §15.7 carried the single word *"Adopt"* — in a column headed `Recommendation`, in a table whose preamble says each row *"blocks implementation of the item named"* — and it was read and cited as a ruling"* |
| CRM §10.1's *"**Recommendation: adopt Layer 0**"* becomes a recorded, **overruled** recommendation | CRM §10.1, §11.3 | preserved, not deleted — the recommendation was correctly made and correctly overruled |

**The deadline, stated accurately because the record must be — and because it is the reason this entry was
mis-banded.**

- **What it was recorded as:** *"before `087`"*. `HG-4` says so; CRM §13 `D-2` says *"Yes — before 087 / I"*;
  RLS `MD-2` inherits it; record row `O17` says *"it must be decided before `087` is authored"*.
- **What it had become:** **before `076`**. Ratified `C115` moved `CREATE ROLE crm_export_builder NOLOGIN`
  from `087` to `076` under the new rule `SEAM-4`, and put the first grant — the column-scoped
  `GRANT SELECT (id, email) ON auth.users` — in `076` itself. A `GRANT` resolves its grantee immediately, so
  the first grant in `077` against a role created in `087` is a hard `42704` at replay. The brief:
  *"**This decision gates the first migration, eleven packages earlier than three documents advertise.**"*
- **What that made this entry:** **mis-banded downward by eleven packages** — Band 2 (`087`) where it belonged
  in Band 1 (`076`). It is in Band 1 here.
- **What it is now:** **moot.** The ruling is taken. **But the stale deadline is not moot** — `HG-4`, CRM
  `D-2`, RLS `MD-2` and record row `O17` all still read `087` at `269e473`, and a reader who meets them
  without this entry will mis-schedule the discharge. Carried as **`DF-39`**.

**What the ruling does NOT close, and is now owed as engineering rather than as a decision.** The owner's
reason names the replacement control explicitly — *"strengthen `X-6` through structural/catalog assertions
and behavioral fixtures"* — and the corpus already knows what those are and that they do not exist:

- **No closed-world test on the demographic grant set** exists; the property is prose in five places and zero
  tests. The catalog assertions the brief names are two single queries — an empty grant set over the four
  demographic relations, and `rolbypassrls = false` / `rolsuper = false` on whatever owner the function ends
  up with.
- **The blank-column canary covers 1 of the 21 export columns.** Under `postgres` ownership the fail-open
  direction is the live one — a lost consent row emits **all** contact cells — which is loud in the product
  and is exactly what a behavioural fixture catches. The ECC database review's decisive argument runs this
  way and the ruling adopts it.
- **`kernel.tickets` still has no index on `org_id`**, while the contract calls `org_id` *"this function's
  FIRST predicate, on every branch."* The brief flags this as **independent of the ruling**: *"`kernel.tickets`
  needs an `(org_id, event_session_id)` index, or the org-grain driving path must be stated."* It survives
  ruling B unchanged.

**Why the corpus could not decide it, preserved as the record of what the owner was ruling on.** Four
independent passes enumerated the grant set and produced four different lists — ten, then twelve, then the
`auth.users` grant that appeared in no list, then `C115` finding the grants were in no package at all — and a
fifth review added four more (a `SELECT`-only grant set against a documented **writer** of
`venue.export_job`; no `GRANT USAGE ON SCHEMA` anywhere in the corpus; `auth.users` and `public.profiles`
granted with no policy, so both read **zero rows** under a role without `BYPASSRLS`; and the missing index).
The two specialist reviews **split**, which is the only decision in the brief where they did. The ruling's
first clause — *"has failed to converge across repeated independent reviews"* — is a finding about that
history, not a judgement about privilege walls.

**Below this line is the entry exactly as it stood at `32249f2`, preserved unchanged.** It is the statement
of the question the ruling answered, and it is kept so that what was decided, and on what basis, both remain
legible.

#### ODR-23 — the entry as it stood at `32249f2`
**Choice.** Own `venue.build_export_rows` with a dedicated `crm_export_builder` definer role holding **zero**
grants on the four demographic objects, so an `X-6` violation is a runtime permission error rather than a CI
finding — **or** reject it and let layers 1–3 stand alone. Named non-option: *"`BYPASSRLS` on the role is
**not** an acceptable shortcut — it would restore access to everything and delete the entire benefit."*
**Breaks.** *Adopting without the complete enumerated grant set and the blank-column canary* produces *"a
builder that runs, raises nothing, and emits a **blank contact column on every row** — which reads, to the
operator and to the audit counters alike, as 'nobody consented'. A silent wrong answer, in the one column the
whole document is about."* *Rejecting* leaves `X-6` resting on grep, catalog checks and pgTAP, and *"§10.2's
empty-file-set guard becomes load-bearing rather than merely important."* Adopting also deviates from the
frozen RPC §0 global (`SECURITY DEFINER` owned by `postgres`).
**Silence.** Ambiguous and **UNSAFE** — element 23 sits inside `087`, and a half-adoption is the zero-rows
failure.
**Blocks.** `087`, and hard gate `HG-4`: *"It changes **who owns** `venue.build_export_rows`. Deciding after
authoring means rewriting the function's ownership and its policy set, in the package that also creates the
bucket."*
**Filed at.** CRM §13 `D-2` + §10.1 + §11.3 · RLS §15.7 `MD-2` + §16.10 · AMEND §11 `HG-4`. **It has no
`OD-` id in the scope amendment's index, which the amendment itself notes.**
**Recommendation — yes, conditionally.** CRM §10.1: *"**Recommendation: adopt Layer 0.**"* — qualified: *"**This
cost is part of D-2**, and the zero-rows failure mode is the reason D-2 cannot be answered 'adopt it' without
also adopting the enumeration and the canary."* RLS `MD-2`: *"**Adopt.** The alternative is a `postgres`-owned
function with reach over everything. `BYPASSRLS` is not an acceptable substitute."*

---

# BAND 2 — blocks a named migration package

**Thirty decisions**, ordered by the package they gate. Implementation can begin once Band 1 closes; each of
these stops one identified package from being authored correctly.

**Changed at `269e473`:** `ODR-23` **left** this band for Band 1 (its artifact moved `087 → 076`); four
entries **arrived** — `ODR-125` (`R2B-1`, frozen at `085`), `ODR-126` and `ODR-127` (both **MECHANICAL**,
recorded here so they are not mistaken for the owner's), and `ODR-128` (**BLOCKED** by `ODR-7`). One entry in
this band, `ODR-15`, is now **MECHANICAL**; it keeps its band because its *scheduling* still rides `ODR-3`.

Each entry states: the question as a choice · what breaks under each option · **which way silence falls, and
whether that direction is safe** · the package · every filing site · the corpus recommendation, quoted.

</details>

---

### ODR-8 — Per-org refund/payout thresholds at launch? · `077`
**Status.** OPEN — OWNER.
**Choice.** One platform-wide threshold set (build nothing), **or** build `kernel.org_money_policy` — `org_id`
PK, override columns, org-scoped read, platform-only write, versioned, audited.
**Breaks.** *Build it* — *"it doubles the resolution logic (per-org → fall back to platform) at every decision
point"*, `077` gains a table, every threshold read becomes two-step, and `kernel.approval_request`'s
`config_versions` must pin the **org** policy version as well as the platform pair. *Don't* — every org shares
one ceiling.
**Silence.** Never built. **SAFE.**
**Blocks.** `077` scope — a conditional package element marked *"DO NOT BUILD WITHOUT AN OWNER RULING."*
**Filed at.** MONEY §11 `D-2` + §7.4 · REGISTRY §7 `COND-C` · SCHEMA §1.14 + §13.1 (`cond.` row) · AMEND
§14.2-A `OD-02`.
**Recommendation — yes, and it has been withdrawn from under itself.** MONEY §11: *"**No** — **but the stated
basis has since become false and the recommendation must be re-derived before it is acted on.** This row
argues from *"`platform_config` is world-readable"*. **It is not**: RLS §8.4 is a two-class model on
`visibility` (`AUTHZ-CFG1` / ratification **C71**), and money keys are `restricted`. A non-public home for
per-org limits may therefore already exist. **Recorded, not re-decided**."* The traceability matrix flags the
same premise as needing re-derivation (`TM-X2`). **Re-pose the question before answering it.**

### ODR-9 — Were `org_marketing` and `org_promoter_manager` intended to be storable at the org grain? · `077`
**Status.** OPEN — OWNER.
**Choice.** Confirm the six-label org set (what the schema pass restored), **or** rule marketing/promoter
venue-grain only — in which case *"the fix is the opposite one — remove them from §0.6."*
**Breaks.** Before the fix, `077` enumerated only four org labels, so the two labels were **unstorable** —
*"`23514` at write time on both the grant and the invite path, with no workaround short of a migration."*
Confirming the wrong reading entrenches it in a CHECK constraint.
**Silence.** Six labels ship. **SAFE while the tables are empty; unsafe after `077` applies** — the role model
warns *"the enums are still editable. After the venue-staff-roles package ships they are not."*
**Blocks.** `077` — `kernel.org_member.role` and `kernel.org_invite.role` CHECK sets.
**Filed at.** SCHEMA §13.7 `S-8` + §1.3.1 (defect `M-5`) · ROLE_MODEL §3.1–§3.4.
**Recommendation.** **None explicit.** The schema pass acted *"on the strength of §0.6's own canonical table;
the role model is the document that ratified the six"* and calls the correction *"mechanical **if** the
six-label set is right."*

### ODR-10 — Is `kernel.approval_request` an aggregate class or an intent record? · `077`
**Status.** OPEN — OWNER.
**Choice.** **Aggregate class** ⇒ a sixteenth SSCAS member ⇒ `C28`'s closure needs a formal amendment; **or
intent record** ⇒ `SSCAS: n/a`.
**Breaks.** Neither breaks anything at runtime — *"It is lock-ordered either way."* What changes is whether
`C28`'s ratified fifteen-member closure is still true.
**Silence.** Intent record; `C28`'s fifteen stands. **SAFE.**
**Blocks.** The parked refund branch (MONEY §6.1); the placement of the table in `077`.
**Filed at.** MONEY §11 `D-1` + §7.5 · RLS §17 `X-8` + §15.7 `MD-1` · RPC §16 item 8 + §17.1 · SCHEMA §0.9 +
§1.13 · AMEND §14.2-A `OD-01`.
**Recommendation — yes, three documents agree.** MONEY §11: *"Intent record — argued in §7.4; it is
lock-ordered either way, so an amendment is a one-line ratification"*. RLS §15.7 `MD-1`: *"Intent record — the
parked branch takes `FOR UPDATE` on exactly one pre-existing class (Ticket Atom); the approval row is a fresh
INSERT that contends on nothing."*
**Citation defect to be aware of.** Every citation points at MONEY **§7.4** (*"Per-org override"*); the SSCAS
argument is in **§7.5**.

### ODR-11 — The six threshold values · `078` seeds
**Status.** OPEN — OWNER.
**Choice.** The numbers for `refund.org_auto_execute_max_minor`, `refund.org_dual_control_max_minor`,
`refund.platform_support_max_minor`, `payout.request_auto_max_minor`, `payout.dual_control_min_minor`,
`refund.request_ttl_hours`.
**Breaks.** The operand changed under these numbers: *"**AMENDED (`MB-1`): the refund keys now denominate a
CUMULATIVE ceiling per payment (§6.1a), not a per-call one.**"* — *"A per-call £50 and a cumulative £50 are
different products"*, and *"an owner who sets the numbers against the old reading sets them against a control
that no longer exists."* Absent `refund.request_ttl_hours`: *"**A hold with no sweep is a bricked ticket**."*
**Silence.** Keys ship unset. For `refund.platform_support_max_minor` the fail-to-safe rule makes absent =
*"support may approve nothing"* — **safe and loud**. For `refund.org_auto_execute_max_minor`,
`refund.org_dual_control_max_minor` and `refund.request_ttl_hours` **no absent-key rule is stated anywhere** —
see the defect list, item **DF-7**.
**Blocks.** Tier behaviour. Values are runtime (`set_platform_config`); seeds consolidate into `078`.
**Filed at.** MONEY §11 `D-3` + §7.2 + §6.1a · RLS §15.7 `MD-3` + §15 item 4 · RPC §16.3 + §17.1a · AMEND
§14.2-A `OD-03`.
**Recommendation — none on the numbers.** MONEY §11: *"commercial + risk call; the keys ship, the values are
set by an audited `set_platform_config`. **No number is chosen by the `MB-1` pass**"*.

### ODR-12 — The money-role grant-maturity window · `078` seed
**Status.** OPEN — OWNER.
**Choice.** How many hours a money-role grant must be old before its holder may act as the second half of a
dual-control pair. The admissible range on record is **24–72 hours**.
**Breaks.** *Too short* — *"The attack becomes 'mint the counterparty, wait until tomorrow' … The control
degrades toward the cool-down it was designed to outrank, which stops nobody willing to wait."* *Too long* —
*"A genuine new hire cannot be the second half of a dual-control pair for their whole first week, so the org
is a **single-money-principal org** for that window and every refund and payout escalates to platform review …
The cost is real, it is operational, and it is paid by the honest case."*
**Silence.** The key ships regardless and fails to *no grant is mature* ⇒ nobody can approve anything.
**SAFE, but it presents as an outage** rather than a missing decision — the RPC spec's interim guidance is to
*"seed the key at the **restrictive** end of the range and record the seed as provisional."*
**Blocks.** The `SoD-1`/`SoD-2` guarantee — the control that makes `O-3`'s ratified SoD collapse survivable.
**Filed at.** RPC §1.1e (`AUTHZ-C1C`, *"THE WINDOW ITSELF IS AN OWNER DECISION, RECORDED HERE AND NOT MADE
HERE (`MD-14`)"*) · RLS §15.7 `MD-14` · record row `C58`.
**Recommendation — yes.** RLS §15.7 `MD-14`: *"**24–72 hours.** Long enough that minting a counterparty cannot
be same-session, short enough that a genuine hire is not blocked past their first day. The **key** ships
regardless and fails to *no grant is mature*; only the **number** is this decision."*

### ODR-13 — `door.*` config visibility: `restricted` or `public`? · `078` seed row
**Status.** OPEN — OWNER.
**Choice.** Leave the `door.*` `catalog.platform_config` namespace `restricted`, or move it to `public`.
**Breaks.** *Public* publishes `door.manifest_ttl_interval` and `door.implicit_freeze_offset_interval`, which
*"state **how long a door may operate on stale data** — which is the width of the window in which an offline
duplicate admission is possible"*, and since `AUTHZ-H3` also bounds the life of a bearer door-session token:
*"how long a stolen tablet keeps working"*, readable by a signed-out browser. *Restricted* costs nothing the
corpus can name — *"A client never needs it; the scanner receives its effective window inside the manifest it
is issued."*
**Silence.** `restricted` — the column `DEFAULT` is `restricted`, so the safe class is structural, not
remembered. **SAFE.**
**Blocks.** One seed row in `078`. *"It is isolated — moving it changes nothing else."*
**Filed at.** SCHEMA §13.7 `S-9` + §2.4.1 · RLS §17 `X-17` + §15.7 `MD-17`.
**Recommendation — yes, keep it restricted, with the reversal path named.** SCHEMA §2.4.1: *"**`door.*` is
classified `restricted`, and that is the one genuinely arguable line.** … **If the owner disagrees, this is
the row to move, and moving it changes nothing else."* §2.4.1 also frames its own status: *"**This is an
owner-facing ruling, and it is stated as a recommendation with its reasoning, because it narrows a property
(`public-read`) that RLS §8.4 already asserts.** It is filed for ratification, not applied unilaterally."*

### ODR-14 — Confirm k = 25 and cell floor = 5, and where the constants live · `077` CHECK
**Status.** OPEN — OWNER.
**Choice.** Keep 25/5 or raise them (lowering is asked against); **and separately** put them in
`catalog.platform_config` (tunable) or hard-code them in the `CHECK` constraint (rigid).
**Breaks.** *Tunable* — *"a tunable privacy floor is a floor that gets tuned"*, and it dissolves **R2**, the
only rule in the whole privacy set that is an actual database constraint (*"A sub-floor bucket is not merely
hidden — it **cannot physically be stored**"*). *Rigid* — any future change needs a migration.
**Silence.** 25/5, CHECK-enforced. **SAFE.**
**Blocks.** The `CHECK` constant in `077`.
**Filed at.** DEMOG §14 `D-5` + §5.2 + §5.4 · AMEND §14.2-C `OD-17`.
**Recommendation — yes.** DEMOG §5.2: *"**This spec recommends the CHECK constraint** — a tunable privacy
floor is a floor that gets tuned."* AMEND adds *"may be raised, never lowered."*

### ODR-15 — `notify.push_token` as a new table, or additive columns on `public.push_tokens`?
**Status.** MECHANICAL / ENGINEERING — **removed from the owner set at `269e473`.** Determined by the corpus: `PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N11` and `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.4 already answer it identically (*extend `public.push_tokens`*), and `_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md`'s *"decisions removed from the owner set as mechanical"* appendix names it explicitly: *"two documents already answer identically."* **What is still owed is not a choice but a home** — the four token fixes are scheduled by nothing until `ODR-3` closes, which is why the silence below is still marked UNSAFE.
**Choice.** New `notify.push_token` table, or extend the existing `public.push_tokens`.
**Breaks.** *New table* — *"a second token table creates a split-brain during migration."* *Extend* — `C7`
*"literally says 'into their own schema'"*, so extending is a deliberate, recorded deviation from a ratified
correction.
**Silence.** Unresolved; the four token fixes (`revoked_at`, `revoked_reason`,
`provider_receipt_checked_at`, `last_provider_error`) have no home. **UNSAFE** — a revoked push token is the
mechanism by which a mandatory money notice becomes silently undeliverable.
**Blocks.** The token model; `notify.register_push_token` / `revoke_push_token`. Rides `ODR-3`.
**Filed at.** NOTIF §10 `O-N11` + §6.1 extensions table · SCHEMA §13.4 · AMEND §14.2-H `OD-55`.
**Recommendation — yes, and it is the one sub-decision the schema pass did take.** NOTIF §10: *"**Extend
`public.push_tokens`.** A second token table creates a split-brain during migration and C7's eviction is
satisfied either way. Flagged because C7 literally says 'into their own schema'."*

### ODR-16 — How account deletion behaves for an identity holding custody · **`077`** · **BAND 1**

> **DEADLINE CORRECTED `079` → `077`, and RE-BANDED 2 → 1, on 2026-08-28.** `kernel.identity_ext.identity_id`
> is `PK, FK→auth.users ON DELETE RESTRICT`, and `identity_ext` is the 1:1 per-identity row — so **every
> identity with one becomes undeletable the day `077` applies**, two packages before the one this decision was
> filed against. Under this register's own re-banding rule (*"an entry's band is a property of where its
> artifact lives, not of what its filing sites claim"*), that makes it **Band 1**: it now gates the same
> package as `ODR-4`, and `ODR-4b` is additionally BLOCKED BY it. The `079` in the sentence below is left
> as-written because it is a quotation; read `077`.
**Status.** OPEN — OWNER.
**Choice.** **(a) tombstone** — retain the `auth.users` row marked erased, revoke credentials, crypto-shred
PII, keep an opaque dereferenceable uuid; **(b) refuse while custody is live** — deletion is refused, with a
named reason, until every held atom is terminal or transferred; **(c) forced hand-off** — deletion voids or
transfers the remaining atoms through the custody engine first.
**Breaks.** *(a)* *"the row survives deletion. The honest description is 'we keep an opaque identifier, and
nothing else'."* *(b)* *"a fan holding a ticket to next month's show cannot delete today"* — and must be told
why **inside the deletion flow, before the confirm step**. *(c)* *"a privacy action destroys or moves something
the person paid for."* **Inadmissible under all three:** reusing the `019` anonymization sentinel as the new
`current_owner_id` — it would render on the dispute surface as *"Deleted User"* (record `C96`).
**Silence.** **UNSAFE, and total:** every identity column is `ON DELETE RESTRICT` to `auth.users`, so
*"**account deletion as a whole stops working for anyone who has ever held a ticket, the day `079` lands.**"* — **read `077`; the quoted sentence is two packages optimistic.**
**Blocks.** Package `079` — not its authoring, its product behaviour, from the day it applies.
**Filed at.** Record row **`O15`** / `C95` · SCHEMA §5.1 `CUSTODY-DEL-1` + §13.7 `S-19` · CRM §9.2 · DEMOG
§8.2 · DOOR §7.6.
**Recommendation.** **None.** Three forms are stated with their costs; none is preferred.

### ODR-17 — `kernel.door_freeze_override`: move the table to `079`, or take a `SEAM-2` hook? · `079`/`086`
**Status.** OPEN — OWNER.
**Choice.** Move the table into `079` (what the schema pass did), or leave it at `086` and have `079` stub
`door_freeze_override_active()` returning false.
**Breaks.** The hook *"does fail safe — a `false` stub means 'no override', so `is_transfer_frozen` returns
**true** and transfers stay blocked — but it buys nothing."* Not moving it leaves forward reference `FR-7`,
because `kernel.lock_ticket` (`079`) rechecks `is_transfer_frozen` under the atom lock.
**Silence.** The table moves to `079`. **SAFE.**
**Blocks.** `079` / `086`.
**Filed at.** SCHEMA §13.5-B.
**Recommendation — yes.** *"moving the table removes the seam instead of papering it. **Recorded so the owner
can take the hook instead if `079`'s blast radius is judged too precious to touch.**"*

### ODR-18 — Does disbursement auto-fire on `close_settlement`, or require an explicit human request? · `085`
**Status.** OPEN — OWNER.
**Choice.** `payout-execute` fires from the scheduler on settlement close, **or** money moves only on an
explicit `kernel.request_org_payout` by a human.
**Breaks.** *Auto-fire* — money leaves on a schedule with no human in the loop, and the step-up predicates
(`aal`/`amr`, MONEY §8.3a) **cannot fire for a machine identity**, so the entire money-plane step-up control
is bypassed on the disbursement path. *Human step* — settlement close does not disburse; every payout carries
a manual step.
**Silence.** **UNSAFE ambiguity on a money-out path.** Edge §3.4 supports both readings in one sentence
(*"invoked by an authenticated finance user OR by a scheduler/service principal"*), so an implementer picks.
**Blocks.** `payout-execute`'s auth model (Class A versus a machine-identity path), package `085`; RPC §16.4.
**Filed at.** EDGE §9 reconciliation item 5 + §3.4 · RPC §16.4 · MONEY §8.3(c)/§8.3a.
**Recommendation.** **None** — it is filed as a confirmation request. **Not indexed in the scope amendment's
`OD-` series at all.**

### ODR-19 — What `kernel.payout.status='paid'` asserts · `085`/`087`
**Status.** OPEN — OWNER.
**Choice.** `paid` means *"the transfer succeeded and was not reversed"*, written synchronously by the payout
executor; **or** *"the funds reached the payee's bank"*, a `balance_transaction` fan-out from `payout.paid`.
**Breaks.** *"the two differ in what the venue is being told, and one of them is a promise about a bank we do
not observe."* Only `transfer.created` supplies the `stripe_transfer_ref` join key; `payout.paid`/`payout.failed`
describe the **connected account's own bank payout** (`po_…`), which aggregates many transfers and *"is **not
joinable to a single `kernel.payout` row**."*
**Silence.** Three of five `status` labels and `stripe_transfer_ref` have no writer at all: *"A failed transfer
therefore leaves the row reading `submitted` **forever** — nobody retries, nobody is alerted, and dashboard
§14.5's 'Failed payout: pinned, non-dismissible' banner can never fire."* **UNSAFE.**
**Blocks.** `kernel.mark_payout_transfer_state` (`085`) and `venue.on_payout_settled` (stub `085`, body
`087`); the edge spec §4 placeholder.
**Filed at.** Record row **`O16`** / `C92` · SCHEMA §1.9.2 + §13.7 `S-16` · EDGE §4 · VD §14.5.
**Recommendation.** **None on the meaning.** The writers are named either way — *"Both forms are served by the
single RPC above; only the caller and the triggering event change."*

### ODR-20 — Does `venue.set_event_security_config` exist at all? · `078` + `086`
**Status.** OPEN — OWNER.
**Choice.** **(a) schedule `catalog.event_security_config`** into `078` — `(event_id, key, value, version,
effective_from)`, append-only per version, `restricted` visibility since it overrides `door.*` — and the
ratified `O4-4` authority stands; **or (b) rule the function out**, as `venue.set_door_open_at` was
(`AUTHZ-R1`), in which case RLS §11.4's `O4-4` EXEC row goes with it and `086` never names it.
**Breaks.** *(a)* one additive table in an already-scheduled package. *(b)* **a ratified `O-4` authority row
keeps its authority and loses its object.** Doing neither and building anyway is what the schema pass refuses:
*"a function scheduled in `086` with nowhere to write is unbuildable regardless of which keys it accepts"*, and
*"inventing the table at build time is exactly what `S-13` refuses."*
**Silence.** `⛔ BLOCKED` — *"`086` must not schedule it while this stands"*, no EXEC row may be written, and
test `T-RPC-DOOR-24` is held. **SAFE (fails closed) and genuinely blocking.**
**Blocks.** `078` (the table), `086` (the function), RLS §11.4's `O4-4` EXEC row, ROLE_MODEL `R-16`.
**Filed at.** SCHEMA §13.7 `S-13` · RPC §20.14 `R-21` + §20.6.6 · RLS §15.7 `MD-18` · ROLE_MODEL §13 `OD-11` +
§11.2 `R-16` + §12 row 15 · record row `D17` · TRACE `G-14`.
**Recommendation.** **None — every document refuses.** ROLE_MODEL `OD-11`: *"**None — recorded, not
decided.**"* SCHEMA: *"the function's existence is not this spec's to decide."*
**Do not conflate with `ODR-81`**, which asks about the *key set*: *"answering `R-11` does not answer this."*

### ODR-21 — The door-session selector: `door_session_id` or `session_ref`? · `086`
**Status.** OPEN — OWNER.
**Choice.** The lookup handle is the uuid PK `door_session_id` (the schema's spelling), or a new
`session_ref text UNIQUE NOT NULL` column (the edge spec's spelling).
**Breaks.** Edge §3.9a *"is unimplementable as written: it selects rows by a column the schema does not define
… an implementer following §3.9a writes a `session_ref` that nothing stores."* Adopting `session_ref` costs
one schema column.
**Silence.** Two documents disagree and one is unimplementable. **UNSAFE.**
**Blocks.** Edge §3.9a and package `086`.
**Filed at.** RPC §20.14 `R-19` + §1.1d (`AUTHZ-H3a`) · RLS §17 `X-18` + §15.7 `MD-19` · EDGE §3.9a.
**Recommendation — yes.** RLS §15.7 `MD-19`: *"**`door_session_id`.** The schema owns the table and defines no
`session_ref`; the two designs are otherwise identical, so this is a spelling decision with a one-column
alternative. It is listed because **edge §3.9a is currently written against the other spelling** and one of
the two documents must move."*
**Note.** `R-19`'s second half — the PIN-free `/refresh` route — is **not** part of this choice; it is a
settled safety property (schema §3.10a.4 *"deliberately refused"* it). See defect **DF-12**.

### ODR-22 — `record_scan` under `FOR SHARE`, and whether M2 is signed · `086`
**Status.** OPEN — OWNER.
**Choice.** Two coupled door-transaction questions the scope amendment files as one. (i) Must
`venue.record_scan` take the rank-1 session `FOR SHARE` lock? (ii) Build the optional `door-manifest` edge
function that KMS-signs the M2 manifest, or accept TLS-only?
**Breaks.** *(i) no lock* — a scan's recorded `manifest_id` may be a racing one; *"Not needed for the theorem
(scans do not move custody)"*, so this degrades reconciliation evidence, not correctness. *(i) lock* — *"scans
briefly block during open/close (milliseconds, twice a night)."* *(ii) TLS-only* — *"M2's *integrity* then
rests on transport alone while M1's does not."*
**Silence.** No lock; TLS-only. **SAFE for correctness, weaker for evidence and integrity.**
**Blocks.** The door transaction shape; an optional element of `086`. Coupled to `ODR-51` (budget).
**Filed at.** DOOR §16 `OQ-6` and `OQ-7` part (a) · EDGE §3.9b + §5.4.2 · AMEND §14.2-I `OD-60`.
**Recommendation — split.** DOOR `OQ-6`: *"Recommend yes. **Implementer/owner preference.**"* DOOR `OQ-7`:
*"**Recommend building it**; the TLS-only fallback is acceptable for MVP if KMS budget is constrained."* The
scope amendment's `OD-60` records **no** recommendation.

### `ODR-23` — RE-BANDED TO BAND 1, AND RULED
Pointer only — the entry, its status and its ruling live in **Band 1**.
**`ODR-23` is not in Band 2 at `269e473`.** Its artifact — `CREATE ROLE crm_export_builder NOLOGIN` — moved
from `087` to `076` under ratified `C115`/`SEAM-4`, which makes it a Band-1 entry gating the **first**
Phase-2 migration, not a Band-2 entry gating the twelfth. **The full entry, the ruling, the owner's reason,
and the correction to its recorded deadline are in Band 1.** The id is unchanged.

### ODR-24 — Operatorship change: the new operator's CRM starts empty, and who tells them · `087`
**Status.** OPEN — OWNER.
**Choice.** Confirm `XO-1a` — a venue changing hands transfers no customer list, no consent and no
`first_seen_at` history — **and decide who tells the incoming operator.**
**Breaks.** *Without `XO-1a`* — *"**Org 2 receives Org 1's customer list**, complete with consent-gated email
for everyone who consented *to Org 1*"*, plus identical `customer_ref` values across the two orgs, which is
*"the defence inverted."* *With it* — *"Org 2 loses the venue's history for its own venue. A new operator sees
an empty CRM on day one and will ask why."* The only alternative named is out of scope: a private commercial
arrangement between two orgs, *"**not** a platform feature, and this spec builds nothing for it."*
**Silence.** `XO-1a` ships; **the "who tells them" limb has no default at all** — the incoming operator
discovers it at go-live.
**Blocks.** `087`.
**Filed at.** CRM §13 `D-12` + §4.4 case (e) + §5.1 (correction `K-14`, `XO-1a`/`XO-2`).
**Recommendation — yes, on the rule; none on the second limb.** CRM: *"That is the correct answer — the
audience belongs to the organization the person transacted with, not to the building — and it is a real
product consequence the incoming operator will contest. **Confirm, and decide who tells them.**"*

### ODR-25 — Export artifact retention: 24 hours or 7 days? · `087` sweep constant
**Status.** OPEN — OWNER.
**Choice.** 24 h or 7 d in the `crm-exports` bucket after `ready`.
**Breaks.** *7 days* *"is an operator convenience that multiplies the standing exposure sevenfold"* — the
bucket becomes a week of every venue's customer lists, and the *"the lake is bounded by a 24-hour sweep"*
defence weakens accordingly. *24 h* costs an operator a re-request.
**Silence.** **No default exists** — the sweep needs a literal constant (`expires_at`, `purge_after`, a
`platform_config` seed).
**Blocks.** The sweep constant; `087` element 20.
**Filed at.** CRM §13 `D-6` + §6.6 + §9.2/§9.3 · AMEND §14.2-G `OD-46`.
**Recommendation — yes.** CRM §13: *"**Recommend 24 h.**"* §6.6: *"Extending to 7 days is **owner decision
D-6**, with this document recommending against."*

### ODR-26 — Settlement close: `org_finance`, `venue_finance`, or both? · `087`
**Status.** OPEN — OWNER.
**Choice.** Which role may call `kernel.close_settlement`.
**Breaks.** Settlement close **drives payout**, so a venue-grain grant puts payout-triggering authority at
venue level. RLS flags it undecided at §15 item 3 while §9.13 **and** §11 already list `venue_finance` — *"the
spec contradicts itself."*
**Silence.** **UNSAFE.** Both are granted today (§11.1's `kernel.close_settlement` row grants org **and**
venue finance), so silence ratifies the permissive reading of an explicitly open question.
**Blocks.** `close_settlement`'s authority; the settlement package `087`.
**Filed at.** ROLE_MODEL §13 `OD-4` + §5.3 cell `B10` (left `⚠`) · RLS §15 item 3 + §9.13 + §11 · RPC §16 item
4 · AMEND §14.2-A `OD-11`.
**Recommendation.** **None, from any document.** ROLE_MODEL: *"None. Cell B10 left `⚠`."* AMEND: *"none —
O-1/O-3 do not reach it."*

### ODR-27 — Where does the bid ledger live? · `088`

> **SHARPENED 2026-08-29 (sprint agent D — read before ruling):** Meaning 1 AS CONTRACTED is **no
> native-rail auctions at all**, not "no native-only auctions": `create_auction`'s mirror precondition is
> FK-unsatisfiable (`public.bids.listing_id NOT NULL → public.listings`; the only bridge is the read-only
> `089` VIEW; no document specifies a mirror-row writer). The **auction finalize sweep is proven
> downstream in every branch** — vacuous under Meaning 1, R-9-shaped under Meaning 2 — and is FOLDED into
> this decision, not a separate bit. Consolidated brief: `_governance/OWNER_DECISION_QUEUE_2026_08_29.md` Q-2.
**Status.** OPEN — OWNER.
**Choice.** Accept *"native-only auctions are not offered in MVP"* — `create_auction` requires a listing that
mirrors to `public.listings`, and a native-only attempt raises
`precondition_failed('native_only_auction_unsupported')` **at create time, not at bid time** — **or** schedule
the EXT `market.bid` ledger into `088`.
**Breaks.** *Refuse* — a product capability is not offered. *Schedule* — a package change to `088`.
**Silence.** **UNSAFE, and named as such:** *"§16.5, schema §4.2 and schema §4.9 leave it open in three
different words. An implementer facing that silence creates a table no package specifies — and **a bid ledger
invented at build time is a money surface with no review**."*
**Blocks.** `088`. *"**Either way it must be decided before `088` is written.**"*
**Filed at.** RPC §20.14 `R-9` + §20.8.4 (`OPEN DECISION`) + §16.5 + §19 item 16 · SCHEMA §4.2/§4.9 · PLAN §8
`088` · RLS §15 item 6 · TRACE `G-5`. **Not indexed in the scope amendment's `OD-` series.**
**Recommendation — a proposal, explicitly not a ruling.** RPC §19 item 16: *"**The MVP position on the bid
ledger** (§20.8.4 `OPEN DECISION`) is a **proposal, not a ruling** — §16.5, schema §4.2 and schema §4.9 leave
it open in three different words."*

### ODR-28 — `venue.promoter_link.status`, or promoter-grain deactivation only? · `090`
**Status.** OPEN — OWNER.
**Choice.** Add `venue.promoter_link.status` (+ `status_changed_at`, `status_changed_by`, CHECK, partial
index, the `PL-1` immutability trigger) — **or** remove the dashboard's per-link status control and rely on
deactivating the whole promoter.
**Breaks.** *No column* — `venue.set_promoter_link_status` (RPC §20.9.4, marked **BLOCKED**), dashboard control
`U-4` and RLS §9.17's grant are *"expressible against nothing"*, and all three workarounds are closed (DELETE
blocked by `ON DELETE RESTRICT` plus the append-only attribution; slug rename blocked by immutability and by
flyers already printed). *Promoter-grain only* — *"it kills every link that promoter holds. 'Retire this one QR
code' and 'stand this promoter down' are not the same operational act."*
**Silence.** The column is added — *"but that is a ruling, not a default."* **SAFE** (a dead UI control is the
worst case in the other direction).
**Blocks.** `090`; dashboard control `U-4`.
**Filed at.** SCHEMA §13.7 `S-10` + §3.17.2 · RPC §20.14 `R-5` + §20.9.4 · RLS §17 `X-13` (schema half) · VD
`U-4`.
**Recommendation — yes, with the reversal stated.** SCHEMA §3.17.2: *"**This pass adds the column**, because
the alternative silently deletes a contracted RPC (§20.9.4) and a dashboard control (`U-4`) that RLS §9.17
already grants authority for … **If the owner prefers the promoter-grain control, the column comes back out
and §20.9.4 plus `U-4` are removed with it** — but that is a ruling, not a default."*

### ODR-29 — Does a typed code beat a link when they name different promoters? · `090`
**Status.** OPEN — OWNER.
**Choice.** **Code wins**, with the link recorded in `displaced_promoter_id` — or **link wins** and the code is
a fallback.
**Breaks.** *Link wins* — *"a code would be dead on every device that had ever touched any link — which is
most of them — and the code feature would silently not work in exactly the cases anyone would notice"*, and it
contradicts the owner's own stated requirement *"do not depend on links."* *Code wins* — *"promoter B can farm
promoter A's traffic by broadcasting B's code"*, mitigated by `touch_corroborated=false`,
`displaced_promoter_id` and eligibility rules `E4`–`E6` into *"a **venue policy** problem with full evidence,
not a silent money leak."*
**Silence.** Code wins. **SAFE, and irreversible:** *"Reversing it later is a **breaking change** to
already-frozen attributions."*
**Blocks.** The §2.3 precedence table (`P1`–`P10`), `venue.resolve_order_attribution`, pgTAP group D — package
`090`.
**Filed at.** PROMO §13 `OWNER DECISION 1` + §2.4 + §2.3 row `P2` · AMEND §14.2-F `OD-33`.
**Recommendation — yes.** AMEND `OD-33`: *"**Code wins**, link recorded in `displaced_promoter_id`. Reversing
later is a **breaking change** to frozen attributions."*

### ODR-30 — Commission basis: face subtotal, or gross including fees? · `090`
**Status.** OPEN — OWNER.
**Choice.** `basis_minor` = the order's surviving items at `unit_price_minor × quantity` (excluding platform
fees, buyer fees, taxes and tips), or gross-of-fees.
**Breaks.** *Gross* — *"fees are not the org's revenue, and paying a percentage of the platform's own fee would
make the promoter's commission move when the platform reprices."*
**Silence.** Face subtotal. **SAFE — but time-sensitive:** *"**It changes every promoter's effective rate;
deciding it after codes are live means renegotiating terms.**"*
**Blocks.** Terms; `venue.attribution.basis_minor` in `090`.
**Filed at.** PROMO §13 `OWNER DECISION 4` + §6.1/§6.2 · AMEND §14.2-F `OD-36`.
**Recommendation — yes.** AMEND `OD-36`: *"**Face subtotal.** Deciding after codes are live means
renegotiating every promoter's terms."*

### ODR-31 — Do codes need redemption caps or expiry by default? · `090`
**Status.** OPEN — OWNER.
**Choice.** No cap with opt-in expiry (`valid_from`/`valid_until` nullable), or a per-code `max_redemptions`
plus expiry-by-default.
**Breaks.** *Cap* — *"A per-code cap is a hot mutable counter on the checkout path"*, and it duplicates
`inventory_batch.release_kind = 'promoter_hold'`: *"two answers in the system for one question — the failure
**C27** exists to prevent."* *Expiry by default* — *"Codes are printed on flyers and live in Instagram bios;
auto-expiry would silently kill live campaigns."*
**Silence.** No cap, opt-in expiry. **SAFE.**
**The trigger that flips the answer, stated by the spec:** *"If 'Jordy has 60 tickets' must be enforced by the
*code*, this file's answer changes and a hot counter enters the checkout path."*
**Blocks.** The `venue.promoter_code` column set — `090`.
**Filed at.** PROMO §13 `OWNER DECISION 5` + §1.1 + §9.6 + §10.6 · AMEND §14.2-F `OD-37`.
**Recommendation — yes.** AMEND `OD-37`: *"No cap, opt-in expiry. Enforcing 'Jordy has 60' via the code puts a
hot counter in the checkout path."*

### ODR-32 — Who bears a post-settlement chargeback on a commissioned sale? · gates the promoter program
**Status.** OPEN — OWNER.
**Choice.** **The org**, via a negative `venue.settlement_line` in the next open settlement — or **the
promoter**.
**Breaks.** *Promoter bears it* is **not buildable in Phase 2**: it needs `C29` reserve and `C30` fan-side
liability, both Gate-M. *"Choosing 'promoter bears it' is therefore a decision to **gate the promoter program
on Gate M**, which is a schedule decision."* *Org bears it* — a named, bounded exposure: *"**exposure ≤ Σ
commission on charged-back attributed orders whose settlement closed before the dispute arrived**. At a
nightlife commission of 5–15% of face, that is 5–15% of the org's chargeback rate … It is not zero and this
file does not claim it is."*
**Silence.** The org absorbs. **SAFE and honest; the residual is named.**
**Blocks.** The promoter program's gate. If answered "promoter", it blocks the **entire** program on Gate M.
**Filed at.** PROMO §13 `OWNER DECISION 3` + §5.3 + §5.1 · AMEND §14.2-F `OD-35` · records `C29`/`C30`/`C31`.
**Recommendation — yes.** AMEND `OD-35`: *"**The org**, via a negative settlement line. 'Promoter bears it'
needs C29+C30 and is therefore a decision to **gate the program on Gate M**."* The spec adds a request: that
*"the instant-payout switch be *gated on C29 landing*, not on a feature flag someone can flip."*

### ODR-33 — Promoter portal: web, or in the RN app? · `090` classification
**Status.** OPEN — OWNER.
**Choice.** Web, mobile-first responsive, or a new RN surface.
**Breaks.** *RN* — three reasons on record: *"it is a money surface with an audit table; shipping it inside the
consumer app couples promoter releases to App Store review; and promoters are not a subset of app users (an
off-platform affiliate has no app)."* And *"If it becomes RN, it is a new §4 section, not an extension of any
existing one."*
**Silence.** Web. **SAFE.** It also decides reach: *"whether an off-platform affiliate (no app account) can be
served at all."*
**Blocks.** The §15 classification row for `090`; a new RN §4 section if reversed.
**Filed at.** PROMO §13 `OWNER DECISION 7` + §11.1 + §15 · RN §12 item 13 · AMEND §14.2-F `OD-39`.
**Recommendation — yes.** PROMO §11.1: *"`INFERENCE:` **recommend web, mobile-first responsive** — not an RN
surface."*

### ODR-34 — May the subject read their own consent *history*? · `082` (additive)
**Status.** OPEN — OWNER.
**Choice.** Current state only (today's `kernel.list_my_org_contact_consents`), or add one definer RPC that
returns the append-only history — *"you allowed this venue on 3 March and withdrew on 9 May."*
**Breaks.** *No* — *"the §5.3 evidence argument stands unimplemented"*, and CRM §5.3 argues at length that *"a
consent record is the person's own evidence in the dispute they are most likely to have."* *Yes* — *"one new
definer RPC, own-`identity_id` only, on `082` … and the `_event` tables' grant set stays empty because the RPC
is a definer — **no RLS posture changes either way.** The cost is one function, not a permission model."*
**Silence.** Deny-all with an empty grant set — the strictest posture. **SAFE**, *"but it is a default this
repair chose by inheritance, not a ruling."*
**Blocks.** Nothing. Would attach to `082`.
**Filed at.** `PHASE_2_PACKAGE_REGISTRY.md` §7.1 `OWNER-DECISION-K2-READ` · CRM §5.3 · record row `D13`.
**Recommendation.** **None.** Both outcomes are costed and neither is preferred.

---

## Added at `269e473` — Band 2

Four entries this band did not have. Three of them did not exist at `32249f2`; the fourth existed and was
unregistered.

---

### ODR-125 — `R2B-1`: does `market.on_atom_voided` carry `p_cause`, and what may it hold? · frozen at `085`
**Status.** OPEN — OWNER.
**Choice.** Six forms, as the corpus states them. **[A]** drop it — the two-parameter
`market.on_atom_voided(p_atom_id, p_refund_id)`. **[B]** keep it, descriptive, carrying ratified `D3`'s
thirteen cause labels. **[C]** keep it, descriptive, **closed to the six `kernel.refund.reason_code` labels**
(`buyer_request` · `event_cancelled` · `oversell_correction` · `dispute` · `admin_action` ·
`auto_compensation`), server-derived, **and renamed `p_reason_code`**. **[D]** keep it authority-bearing — the
value gates whether a `completed` sale may be voided. **[E]** keep it, free text, no CHECK. **[F]** keep it
with a purpose-built two-value set.
**Breaks.** *[A]* is the cleanest architecture, *"but a zero-money force-void may leave **no refund row to
derive from**, and that is exactly the fraud path where an operator most needs to know why a sale was
reversed."* *[B]* is uninformative by construction: the parameter is **currently inert** — nothing reads it
anywhere, `market.market_sale` has **no column that could store it**, and its sole caller derives
`cause := 'refund_void'` as a **constant on every path**, so a `D3` code would carry *"zero bits, forever."*
*[D]* *"puts a string in charge of whether the compensate-XOR-complete invariant is enforced. **Not in the
first cut.**"* *[E]* is *"an unvalidated string on a custody/money compensation path"* — nothing in the corpus
authorizes it and the nearest precedents are the opposite. *[F]* *"creates a seventh cause vocabulary
half-overlapping an existing one — a defect class **already realized twice** in this corpus."*
**Silence.** **[E] — free text, no CHECK.** *"this is what silence produces."* **UNSAFE**, and — this is the
whole reason it is Band 2 rather than Band 3 — **it is not reversible on the usual terms.** New binding rule
**`SEAM-2a`** (ratified `C117`) freezes a `SEAM-2` hook's **parameter list, parameter names and return type**
at the stub; `CREATE OR REPLACE` may change only the body. The stub is authored in `085`. **A ruling that
drops `p_cause`, or renames it, must land before `085` is authored** — after that, `CREATE OR REPLACE` cannot
add a parameter (`088` silently creates a **second, overloaded** routine, the two-argument no-op stays bound
to every call site, replay is green, and *"the C26 compensate arm is dead in production on every refunded
resold ticket"*) and cannot rename one (`42P13 cannot change name of input parameter`, a hard `088` replay
failure — loud, and therefore the better of the two).
**One bit is genuinely the owner's, and the brief says which.** *"**does a third parameter exist at all?**"*
Everything else the corpus already settles, and those limbs are **MECHANICAL**, not the owner's: `text` +
`CHECK` and never a native enum (schema §12.3, asserted by `T-SCHEMA-ROLE-02` over `pg_type.typtype`); never
client-supplied (the hook is `service_role`-only and definer, RLS §11); and no new vocabulary — ratified `D3`
is *"THE one canonical cause-code registry … any other cause list is a tagged subset of it."*
**A correction to the deadline framing, from the brief and recorded here because it changes how urgent this
is.** *"`SEAM-2a` freezes only the parameter's *existence*, name, type and return type — **not the value
set.** A parameter cannot carry a table CHECK; validation lives in the body, and `CREATE OR REPLACE` is
explicitly allowed to change the body. **Widening the value list later costs one `CREATE OR REPLACE` plus a
CHECK swap.**"* So the irreversible bit is narrow: existence and name.
**Blocks.** Package **`085`** — the stub's signature. Downstream, `088`'s replacement and the `C26`
compensate arm.
**Filed at.** Ratified **`C117`** and **`D23`** (*"`p_cause`'s admissible values and its effect on the body
are contracted nowhere — filed to the RPC owner as `R2B-1` and **not decided here**"*) ·
`PHASE_2_PACKAGE_REGISTRY.md` §2.2 seventh amendment and the JSON `seam_2_hooks` `r2b_note` ·
`PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `085` · `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §20.11.3 (the
three-parameter contract) · `_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` **DECISION 6** ·
`_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` §8 item 5. **It has no `O` id, by deliberate choice** —
`D23`: *"**No `O` id and no `RET` id is claimed:** every owner decision this pass encountered was already open
under an existing id … and is routed there rather than re-numbered."* **It also has no `OD-` id in the scope
amendment's index, and no row in any register table.** Before this rebuild it existed only inside prose.
**Its id collides.** `R2B-1` means **two different things inside the same file** — see the dedup ledger's
"same id, different decision" table.
**Does the corpus recommend?** **None on the value set** — explicitly filed out. But its constraints rule out
[E] (closed sets on money paths) and [F] (one cause registry), and make [B] uninformative. The brief's
engineering recommendation is **[C], with the rename**: *"Keeping a validated string on a `service_role`-only
path is cheap; a missing argument you needed is not, and you get no second chance at `085`. Reuse the ratified
six-label vocabulary rather than inventing a seventh. **The rename is the part worth insisting on:** every
other `cause` in this system is a `D3` code, this one can never hold one, and the name is frozen the moment
`085` applies."*
**Ships with it regardless of the ruling.** *"propagate the arity repair into the five documents the seventh
amendment skipped, or `088` either fails hard or silently overloads."* See `DF-41`.

### ODR-126 — Does `090` still "revert as one unit" now that the two order-candidate columns are born in `082`?
**Status.** MECHANICAL / ENGINEERING — **not the owner's.** Determined by the promoter-spec owner.
**Authority:** ratified **`D23`** routes it there by name and claims no `O` id for it — *"`090`'s *"reverts as
one unit"* property with the two order columns now born in `082` is filed to the **promoter-spec owner**"* —
and the same row states the pass *"took no owner decision"*. It is recorded here for one reason only: it is
the **third** of the three owner-facing-looking questions that pass surfaced, and the other two (`MD-2`,
`R2B-1`) **are** in this register. Leaving the third out is how a reader concludes there were two.
**The question.** `venue.order.attribution_candidate_code_id` and `_link_id`, with their freeze guard, moved
`090 → 082` under ratified `C112` (a `plpgsql` body in `082` was writing columns a later package added —
`42703`, unvalidated at `CREATE FUNCTION`, green at replay). The promoter package's stated rollback posture
was that `090` reverts as one unit. **Two of its objects now live eight packages earlier**, and their FKs are
adopted back in `090`. Does the property still hold, and if not, what is the corrected posture?
**Silence.** The stated posture stands and is untested against the new placement. **Not a security default** —
a rollback-posture claim, and the class of claim `C118` showed can be silently false (*"`CREATE OR REPLACE`
succeeds whether or not the routine exists"*).
**Blocks.** Nothing to author. `090`'s rollback statement.
**Filed at.** Record row `D23` · `PHASE_2_PACKAGE_REGISTRY.md` `090` scope/rollback rows · ratified `C112`.
**Does the corpus recommend?** **None** — it is filed, not answered.

### ODR-127 — RPC §6.3 and §7.1 both claim the inventory write · `083`
**Status.** MECHANICAL / ENGINEERING — **not the owner's.** Determined by the RPC-contracts owner.
**Authority:** it is **intra-document**, so no precedence rule of any form reaches it and `ODR-7` cannot help.
The corpus has already hit this class once and said so: ratified **`C121`** resolved an identical
same-document contradiction *"from the corpus, not by a new grant"*, and its own note reads *"Same document,
so `O11` cannot help."* The brief repeats it: *"**One conflict — RPC §6.3 vs §7.1, both claiming the inventory
write — is intra-document, and no precedence rule of any form reaches it.** … It needs its own ruling
regardless."*
**The defect.** `venue.finalize_primary_order` (§6.3) and `kernel.issue_ticket_atoms` (§7.1) each state the
inventory write. If both are built, *"`sold` increments twice and a second `issue` row violates a stated
unique."* And it is load-bearing beyond itself: **the `SEAM-1` derivation for the `081 → 083` move of
`kernel.issue_ticket_atoms` (`C114`) rests on the duplicated write set.**
**Silence.** **This is where an implementer first stops, unregistered.** `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md`
§7: *"**Unregistered (a readiness failure):** package `083`, on `kernel.issue_ticket_atoms` — `p_ctx` has no
SQL type, `serial_no` has no generator, `signing_key_id` has no resolver, and RPC §6.3 and §7.1 **both** claim
the inventory write … **Nothing warns the engineer.**"* Registered here so that something does.
**Blocks.** Package **`083`**, and the correctness of `C114`'s placement derivation.
**Filed at.** `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` §7 and §8 item 2 ·
`_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` §E · precedent at ratified `C121` ·
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §6.3 vs §7.1.
**Does the corpus recommend?** **None**, and it does not name the winner. `C121`'s method is the precedent:
resolve from the sibling statements rather than by granting anything new, and split a row rather than tick it.

### ODR-128 — The six cross-document contradictions that `ODR-7` converts into transcription

> ## UNBLOCKED BY `OR-6`, AND LARGER THAN FILED — 2026-08-28
>
> `ODR-7` is ruled, so this entry is no longer `BLOCKED BY ANOTHER DECISION`. Re-enumerated from HEAD:
> **it is NINE contradictions, not six.** One named item was two distinct contradictions folded under
> one label; two more of the same class were missing from this entry entirely (one of them carried
> only as defect `DF-15`).
>
> | | |
> |---|---|
> | resolved by the owner map (rule 1) | **8** — `X-1 X-2 X-3 X-4 X-5 X-6 X-7 X-9` |
> | resolved by the rule-2 fallback | **0** — the map covered every subject that resolved |
> | **FAIL CLOSED (rule 4)** | **1** — `X-8` |
>
> **`X-8` update 2026-08-28 (`OR-8`).** The owner ruled capability ownership, closing the subject's
> silence. **`X-8` still does not close**, on one bit the corpus cannot supply: the naming convention
> is deterministic in form but not in block letter (`A7` / `B13`), so **`OWNER NAMING DECISION
> REQUIRED`** and no row was written. Two further blockers survive that decision — the mapping has no
> normative home (`CAP-MAP` is owned-but-unhoused), and `ID-5` bars it.
>
> **`X-8` update 2026-08-29 (`OR-9`) — the owner supplied the bit; `X-8` STILL does not close.** The
> owner ruled **`A7`**, on the ground that `B13` would sit in a §5.3 block **transcribed** from DA §7.6
> and so would create a cell with no upstream row — recreating the ambiguity `X-8` is. **Applied:**
> `ROLE_MODEL` §5.3 block A carries `A7`, 70 rows; cells forced by the contract; **`SVC` `·` is the
> first denial of `service_role` in the matrix** and is a narrowing; **NEW HUMAN `EXECUTE` AUTHORITY
> CREATED: NO** (the `authenticated` grant was already ratified twice, `C93`/`C106`).
>
> **One of the two surviving blockers closed; the other did not, and it is not a decision.**
> **`CAP-MAP` is housed** — new `ROLE_MODEL` §5.4, thirteen rows transcribed unchanged from RLS §16.11a
> plus an enumerated gap list; RLS §16.11a becomes the roll-up (`ROLE_MODEL` §11.2 `R-19`, **filed not
> applied**). The housing *form* was mechanical, not chosen. **`ID-5` remains**, so the
> `A7 → kernel.record_money_denial` entry is written as **`⛔ BLOCKED`**, not as a mapping: RPC §0.1a
> and the §17.9 heading still say `EXEC: DEF` while §17.9's body contracts `authenticated` only, and
> §5.4 carries the `DEF`-exclusion rule **verbatim and unweakened**.
>
> **`ID-5`'s repair is a MECHANICAL REMEDIATION owed by the RPC owner (`ROLE_MODEL` §11.4 `P-6`), not
> an owner decision** — `C93` proved the `DEF` configuration unbuildable, and §0.1a's other grant class
> carries no tag, so the fix is a deletion at two sites with no value to choose. **`OR-6` may not be
> cited: the defect is intra-document and the scope limit is binding.**
> **REMAINING OWNER BITS FOR `X-8`: ZERO.** Brief: `_governance/X8_CAP_MAP_ID5_OWNER_BRIEF.md`.
> **This entry's status is unchanged** — `ODR-128` stays `BLOCKED BY ANOTHER DECISION` until `X-8`
> actually resolves, and no count in this register moves.
>
> **`X-8` update 2026-08-29, later the same day — `P-6` LANDED; `X-8` IS RESOLVED; this entry moved.**
> The RPC owner deleted the two `EXEC: DEF` residues (RPC §0.1a, §17.9 heading), invented nothing, and
> `ROLE_MODEL` §5.4's `A7 → kernel.record_money_denial` entry went live. Verified post-repair: hash-match
> on the thirteen transcribed rows, both join directions unique, exclusion rule byte-unedited, security
> posture unchanged (INDIRECT · two edge callers re-enumerated from HEAD · zero client routes · `SVC`
> denied), gate's `X-8` failure cleared with the gate script byte-unchanged. **All three fail-closed
> contradictions are now resolved** (`X-1`/`X-6` by `OR-7`; `X-8` by `OR-8`+`OR-9`+`P-6`), which is this
> entry's own stated condition for leaving `BLOCKED` — status is now **MECHANICAL / ENGINEERING** and the
> split table is recounted. **Found while verifying, NOT `X-8`: `ID-6`** (`venue.assert_may_request`,
> RPC §20.7.8 — second pre-existing instance of `ID-5`'s class; `T-RPC-GLOBAL-02` still fails corpus-wide
> on it; RPC owner's; registered in the contradiction resolution's intra-document list).
>
> **Updated 2026-08-28:** `X-1` and `X-6` closed when owner ruling `OR-7` named the writer-registry
> owner. The derived answer was **11 writers of `kernel.tickets`, not the 10 either side argued** —
> the eleventh a cron/sweep writer that the earlier count omitted.
>
> **The three that fail closed are not a shortfall of the ruling; they are the ruling working.** Two
> independent reviewers disagreed about `X-1`/`X-6`, and that disagreement IS the ambiguity: write
> authority has three declared owners and none defers, with ratified tags on both sides. `X-8` splits
> one indivisible call contract across two owners. **The CI gate is red until an owner act resolves
> them**, which is what rule 4 requires.
>
> **Status.** The decision half is discharged. **28 transcription sites across 8 files remain** — 17
> pure, 7 needing a `C`-row or discharge, 4 blocked. Full detail:
> `_governance/ODR128_CONTRADICTION_RESOLUTION.md`.

**Status.** MECHANICAL / ENGINEERING — **since 2026-08-29**, when the last fail-closed contradiction
(`X-8`) resolved. Originally BLOCKED BY ANOTHER DECISION (`ODR-7`, ruled `OR-6` 2026-08-28); the prior
edition's own condition — *"the row keeps this status until those three are resolved"* — is now met:
`X-1`/`X-6` closed by `OR-7`, `X-8` closed by `OR-8` + `OR-9` + the mechanical `P-6`. **What remains is
transcription** (the 28-site work list, 4 sites newly unblocked and still unedited), which is exactly what
this status means. No owner decision remains in this entry.
**Why it is one entry and not six.** `_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` §0.3 states the
mechanism: *"`O11` first, because **six of the seven "cross-document contradictions" in the work plan are**
delta-vs-delta conflicts; ruling `O11` **converts them from design decisions into transcription**."* They are
therefore not seven decisions and not six — they are **one decision (`ODR-7`) and six transcriptions waiting
on it**, plus one that no precedence rule reaches (`ODR-127`).
**The seven, as `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` §8 item 2 lists them.** *"the §6.3/§7.1
inventory write* **(→ `ODR-127`, not this entry)**; *the writer of `kernel.payment_native`; `cause_ref` grain;
`append_door_manifest_delta`'s return type; `assert_may_request`'s arity (**three live forms**); the
`kernel.tickets` writer set (**4 vs 10**); `078` seed semantics."*
**Silence.** **UNSAFE.** Each is two documents giving an implementer contradictory instructions with nothing
ranking them, and the corpus's own standing obligation — `PHASE_2_SPEC_FOUNDATION.md` §0's *"surface the
conflict; **do not silently pick a side**"* — is *"demonstrably not what happens in practice"* (`ODR-7`).
An implementer picks one per file.
**Blocks.** The earliest is `078` (seed semantics); `079` (`kernel.tickets` writer set, also RPC `R-24`);
`082`/`085` (`kernel.payment_native`'s writer); `083`/`086` (`append_door_manifest_delta`'s return type, also
door §21 `DR-1`); `087` (`cause_ref` grain and `assert_may_request`'s arity, also RPC `R-29`). **Band 2, at
`078`.**
**Filed at.** `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` §8 item 2 ·
`_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` §0.3 and §E · RPC §20.14 `R-24`, `R-29` · door §21 `DR-1`.
**Does the corpus recommend?** **On the six, no** — that is the point of the block. **On `ODR-7` it now does,
twice over:** *"Stated: none. **Practised: [B], six times.** Twelve local precedence rules exist in the corpus.
**Eleven of twelve are subject-matter ownership** … **Not one rule anywhere is recency.**"*
**Answer `ODR-7` first, then this is a transcription pass with a CI gate attached** — the detection half the
brief describes (*"a check asserting that every ratification row's correction actually appears in each
document its own sites column names"*) is **engineering with no policy content**, and is not the owner's.

---

# BAND 3 — blocks a named surface, contract, control or feature flag

Fifty-eight decisions. The migration chain can proceed; each of these stops one identified surface, one
authority cell, one contract or one flag. Ordered by blast radius — the money plane first, then the door and
Wallet, then the product surfaces.

**Read the `Silence` line.** **Thirteen** entries in this band default to the **unsafe** direction — `ODR-35`,
`ODR-36`, `ODR-37`, `ODR-46`, `ODR-49`, `ODR-50`, `ODR-55`, `ODR-63`, `ODR-65`, `ODR-75`, `ODR-80`, `ODR-87`,
`ODR-91`. **It was fourteen at `32249f2`**; `ODR-52` left the set because it is now **SUPERSEDED** — the
supplement it asked for is contracted at door §7.7 and mandatory under ratified `C113`.

**One entry in this band changed status at `269e473`:** `ODR-52` → SUPERSEDED. **One is BLOCKED:** `ODR-81`,
by `ODR-20`. The band count is unchanged at 58.

---

## The money plane

### ODR-35 — Does `org_admin` hold the money-plane read? · **surface H is BLOCKED**
**Status.** OPEN — OWNER.
**Choice.** **(A) deny** — MONEY §3.4's reading, corroborated by Domain §7.2's Org Admin *Cannot* column and
`O-2`'s *"not unrestricted financial authority"*. **(B) grant** — MONEY §10.1 row 35 and VD §5 row 35,
corroborated by RLS §9.7 and §9.13, which grant today.
**Breaks.** The two positions are held by the **same document**: §3.4 denies `org_admin` all money authority
and **labels its own position `INFERENCE`**, while §10.1 row 35 of that same document grants `●` and once
called the row *"unchanged"*. `O-1` and `O-3` name `org_owner` and `org_finance` and are **silent on
`org_admin`**, so neither position is a ruling.
**Silence.** **GRANT, silently — and this is the single most important line in this register.** RLS §9.7 grants
`org_owner/admin` `A(own-org orders)` SELECT on `venue.order`; RLS §9.13 grants `org_admin` `A(own-org)` SELECT
on `venue.settlement`, whose header carries gross, fees, refunds and net. *"**Both grant.** So the outcome of
leaving `D-8` open is not 'nothing gets built' — it is **Position B, built silently, with a `D` sitting unread
in §3.4**."* **UNSAFE**, and the remedy costs are asymmetric: *"widening later is a one-line matrix change;
**narrowing later is a migration plus removing a capability operators have been using**."*
**Blocks.** Venue dashboard **surface H**: *"UNRESOLVED. DO NOT BUILD SURFACE H FROM EITHER CELL."* It also
reopens `ODR-89`.
**Filed at.** Record rows `C85` / **`O13`** · MONEY §11 `D-8` + §11.1 (both positions in full) + §3.4 + §10.1
row 35 · VD §5.2 blocking banner + §22.13 · AMEND §14.2-A `OD-05`.
**Recommendation.** **NONE, and the absence is deliberate and stated.** MONEY §11: *"**NONE — deliberately.**
Every other row in this table carries a recommendation; this one must not, because the two positions are held
by the same document and the tie-break is an authority question, not a design question."* Record `C85`: *"**NO
SIDE IS TAKEN AND NO RECOMMENDATION IS OFFERED.**"*
**Answer `ODR-89` in the same sitting** — position (A) reopens it.

### ODR-36 — Extend grant maturity to the platform plane, or retract the platform-plane claim?
**Status.** OPEN — OWNER.
**Choice.** **(a)** a second, scope-free helper `kernel.platform_money_role_grant_matured()` reading
`kernel.platform_role.created_at` against the same key, bound on the `config.set_money_key` arm — *"a new
control and therefore a new ratification, not a clarification"*; **or (b)** retract schema §1.13.4's
platform-plane sentence and `S-3`'s `set_platform_config` clause, *"so the corpus stops describing a control it
does not have."*
**Breaks.** *(a)* extends a ratified control to a plane `C58` did not ratify it on. *(b)* deletes ratified
schema text and concedes that the platform plane is defended by dual control and audit alone.
**Silence.** **UNSAFE, and live today.** *"`config.set_money_key` therefore carries no maturity floor today,
visibly and on purpose"*, while *"`kernel.grant_platform_role` is itself held by `platform_admin`, so a
`platform_admin` can mint the second `platform_admin` that approves the raise of a money ceiling. **That is the
C58 attack one plane up, on the act the money spec calls larger than any refund it then authorizes.**"*
**Blocks.** No package. A live authority hole on the arm that governs every money threshold in the system.
**Filed at.** Record rows `C77` / **`O12`** · SCHEMA §1.13.4 + §13.7 `S-3` · RPC §20.14 `R-22` *(second
occurrence — see defect **DF-1**)* + §17.2 dispatch table · RLS §11.3a · MONEY §6.7a conflict 2 ·
SPEC_FOUNDATION §4.
**Recommendation.** **None; refused by both documents.** RPC §20.14: *"**This document does not choose.**"*
RLS §11.3a: *"**Neither is taken here.**"* Record `C77` adds: *"**Whichever is chosen, one document currently
says the opposite and must be corrected in the same act.**"*

### ODR-37 — The payout tier's operand
**Status.** OPEN — OWNER.
**Choice.** **(a) undisbursed org exposure** — Σ `kernel.payout.amount_minor` in `pending`/`held`/`submitted`
plus this payout: no new key, no window, not caller-mintable, decays as payouts complete. **(b) rolling per-org
window** — Σ over a new `payout.tier_window_hours`, disbursed and undisbursed alike.
**Breaks.** *(a)* *"**does not close the slow case:** an attacker who lets each payout settle before requesting
the next still disburses unbounded value below the ceiling over time."* *(b)* closes it, and costs a key plus a
width decision that is itself a second `ODR-12`-shaped question.
**Silence.** The tier stays compared against **one payout's amount**, and the caller supplies the settlement
period. **UNSAFE, and the defect is live:** *"**What is not open is whether payouts are currently splittable:
they are.**"* It is worse than the refund case because *"the caller **chooses the decomposition of the subject
itself**."*
**Acceptance criterion the corpus states, so a fix is checkable.** *"the tier operand must be invariant under
decomposition of any caller-chosen subject."*
**Blocks.** The payout tier in `kernel.request_org_payout` (§9.2 / RPC §10.3).
**Filed at.** Record rows `C90` / **`O14`** · MONEY §11 `D-10` + §9.2 + §7.2 · RPC §10.3 (`MB-1b`) + §21 ·
record row `D20`.
**Recommendation.** **None.** MONEY §11: *"**Not made here.** It is *who may disburse how much without a second
approver*, and unlike the refund case there is **no subject already in the corpus** to derive the answer
from."*

### ODR-38 — Does `kernel.tickets.resale_state` have one writer pair, or two writer sets?

> **OWNERSHIP CLOSED, DESIGN STILL OPEN — 2026-08-28.** Owner ruling `OR-7` names
> `PHASE_2_RPC_FUNCTION_CONTRACTS.md` the owner of *"which functions write table T"*, and
> `kernel.tickets.resale_state` is that subject applied to one column. **So the map subject
> `RESALE-WRITER` collapses onto `WRITER` and is no longer AMBIGUOUS.**
>
> **This entry does not close with it.** The owner document says outright *"This document does not
> choose"*, and the choice between (a) one writer pair and (b) two writer sets is a **design**
> decision, not an ownership dispute. What changed is its character: it is no longer a rule-4
> fail-closed ambiguity that nothing could resolve, but a registered open decision that closes the
> moment it is ruled. `CORRECTION_FALLBACK` stays `NO` on purpose — letting a ratified correction fill
> the owner's deliberate silence would decide this entry through the back door.
**Status.** OPEN — OWNER.
**Choice.** **(a)** extend `lock_ticket`/`unlock_ticket` to carry `refund_hold`, so `resale_state` has exactly
two writers and the freeze re-check is unbypassable by construction; **or (b)** keep the four money RPCs'
direct writes and **say so explicitly** in RLS §7.4 and the authority statement, pinned by tests asserting the
money RPCs perform no freeze re-check on release paths.
**Breaks.** *(a)* changes a custody-engine contract. *(b)* ratifies a second writer set. *"a hold release must
never be refused because doors opened, which is why (a) is not obviously right."*
**Silence.** **UNSAFE for consistency, not for security today:** *"Not a defect in either direction today …
**What is wrong is that nothing states which of the two the design is**, so an implementer picks one per
function."*
**Blocks.** Nothing named. The four functions are `request_order_refund`, `approve_refund_request`,
`cancel_refund_request`, `sweep_expired_refund_requests`.
**Filed at.** RPC §20.14 `R-25` + §0.7a + §12.4c · MONEY §6.1–§6.3 · record row `D20`. **Not in any
consolidated index.**
**Recommendation.** **None.** RPC: *"**This document does not choose.**"*
**Cross-reference defect:** RPC §0.7a points at `R-24` for this finding while the register and §21 point at
`R-25` — see **DF-13**.

### ODR-39 — Should the buyer self-service arm additionally gate on order value?
**Status.** OPEN — OWNER.
**Choice.** Leave the cumulative per-payment cap as the only bound, or add a second independent conjunct with
its own key excluding high-value orders from self-service entirely.
**Breaks.** *No exclusion* — *"**a buyer may self-serve part of an arbitrarily large order, up to
`refund.buyer_self_service_max_minor` in total on that payment**."* *Adding it wrongly* — *"adding it silently
inside the existing key is precisely what produced the ambiguity `MB-1` had to settle."*
**Silence.** Not built. **SAFE** — the cumulative cap is absolute per payment and the window key bounds
recency.
**Blocks.** The §6.1a buyer row only.
**Filed at.** MONEY §11 `D-9` + §6.1a · RPC §17.1a · record row `D20`. **Not in any consolidated index.**
**Recommendation — yes.** MONEY §11: *"**Not needed.** The cumulative cap bounds exposure absolutely, every
atom voided is the buyer's own, and `refund.buyer_self_service_window_hours` bounds recency."*

### ODR-40 — `refund.scanned_atom_policy`: `refuse` or `platform_review`?
**Status.** OPEN — OWNER.
**Choice.** Refunding an atom that has already been scanned in: refuse outright, or route to platform review.
**Breaks.** *`refuse`* — *"Refunding an attendee who already walked in is an ordinary goodwill act, so 'the
whole refund fails' is wrong product behavior."* *`platform_review`* — *"it is **also** the exact shape of an
insider-fraud primitive (staff scans a friend in, then refunds the ticket)"*, so it is seen rather than
silently allowed or silently blocked. RLS `MD-16` adds that the control **was inert** before `AUTHZ-C1A` and
now is not: *"the operational load it creates is real and arrives the day the fix ships."*
**Silence.** **No absent-key rule is stated for this key** — it is not in the fail-to-safe list. See **DF-7**.
**Blocks.** The consumed-atom refund path; a `078` seed.
**Filed at.** MONEY §11 `D-6` + §5.4 Race 3 + §7.2 · RLS §15.7 `MD-6` and `MD-16` · AMEND §14.2-A `OD-07`.
**Recommendation — yes.** MONEY §11: *"`platform_review` — refunding an attendee is legitimate, but it is also
the insider-collusion shape, so it should be seen, not silently allowed or silently blocked."*

### ODR-41 — A single-money-principal org blocked from payouts: escalate, or relax?
**Status.** OPEN — OWNER.
**Choice.** Escalate the first post-destination-change payout to `platform_risk`/`platform_admin` via the
existing `release_payout`, or let the same identity do both after the cool-down.
**Breaks.** *Relax* — *"reintroduces the exact named fraud primitive"* (`SoD-1`: redirect the bank account,
then release funds to it). *Escalate* — *"a one-person org therefore contacts Snatch It for exactly one
payout."*
**Silence.** Escalate; the path already exists and *"No code path bypasses the rule."* **SAFE.**
**Blocks.** The `release_payout` path (MONEY §8.2).
**Filed at.** MONEY §11 `D-5` + §8.2 · RLS §15.7 `MD-5` · AMEND §14.2-A `OD-06`.
**Recommendation — yes.** MONEY §11: *"**Escalate** via the existing `release_payout`. Relaxing reintroduces
the exact named fraud primitive."*

### ODR-42 — Ship step-up at `aal1` freshness now, or block money actions until MFA?
**Status.** OPEN — OWNER.
**Choice.** `authn.money_action_required_aal = 'aal1'` now with the level in config (flip to `aal2` on staff
MFA enrolment — a config change, not a code change), or block money actions until MFA ships.
**Breaks.** *`aal2` on day one* — *"nothing enrolls MFA today, so `aal2` on day one locks every operator
out."* *Block* — *"Blocking would ship a dashboard nobody can use."* *`aal1`* is defended: *"`aal1` freshness
is **not** security theatre: it defeats the most common real attack against a 90-day-refresh-token dashboard."*
**Silence.** `aal1`. **SAFE.**
**Blocks.** RLS §11.3 step-up; `078` seeds; a `NEW DASHBOARD SURFACE` (re-authentication flow).
**Filed at.** MONEY §11 `D-7` + §8.3 · RLS §15.7 `MD-7` · AMEND §14.2-A `OD-08` + §11 `HG-7`.
**Recommendation — yes, with a verification attached.** AMEND `OD-08`: *"**`aal1` with the level in config**,
so `aal2` is a config change not a code change. Paired with **HG-7**."* The verification is not a decision and
is owed either way: `UNVERIFIED:` whether this project's access tokens carry `amr` with per-factor timestamps —
*"If absent, freshness degrades to token age (`iat`), which is weaker and must be labelled as such."*

### ODR-43 — May a `venue_manager` mint another `venue_manager`?
**Status.** OPEN — OWNER.
**Choice.** Allow it, or require the grant to come from the org tier or `platform_admin`.
**Breaks.** *Allow* — minting a `venue_manager` mints **an `O-4` door-lifecycle principal**. *Deny* — *"a small
venue whose only manager is on holiday now needs an org-plane action to add a second."*
**Silence.** The guard is written (`AUTHZ-M7`). **SAFE, but it narrows a grant the corpus previously stated
affirmatively**, which is why it is filed as a decision rather than applied silently.
**Blocks.** `venue.grant_staff_role`.
**Filed at.** RLS §15.7 `MD-15` (`AUTHZ-M7`) · RPC §20.4.1 · ROLE_MODEL §12 row 32. **Not in any consolidated
index.**
**Recommendation — yes.** RLS `MD-15`: *"**No** … Recorded as a decision because it **narrows a grant the
corpus previously stated affirmatively**."*

### ODR-44 — Who may disable a transfer freeze?
**Status.** OPEN — OWNER.
**Choice.** `O-4` says not the scanner and does not say who. The placement on record is `platform_admin` under
step-up, *"placed there provisionally."*
**Breaks.** Placing it below the platform plane lets a venue principal defeat platform-wide custody state
(`kernel.is_transfer_frozen`). Leaving it unplaced leaves a capability with no actor.
**Silence.** `platform_admin` under step-up. **SAFE** (most restrictive) but explicitly provisional.
**Blocks.** The override RPC.
**Filed at.** ROLE_MODEL §13 `OD-7` + §5.3 `F3` + §8.1 `O4-5` · RLS §15.7 `MD-12` · DOOR §8.2/§8.3/§10A.3/§10A.7
· AMEND §14.2-A `OD-09`.
**Recommendation — yes, and the door spec has already gone further.** AMEND `OD-09`: *"`platform_admin` under
step-up, placed there provisionally."* The door spec independently rules `kernel.grant_door_freeze_override` =
`is_platform([platform_admin])` only, with **revoke** shared with `platform_risk` — *"may tighten, never loosen
— SoD."* Confirming the door spec's finer form closes this.

### ODR-45 — The platform sub-role read boundary
**Status.** OPEN — OWNER.
**Choice.** Confirm the least-privilege split the RLS spec already assigned — support = ops `V`, risk =
money/fraud read `A`, admin = full `A`/audit — or widen it; specifically, *"whether `platform_support` may read
money summaries at all, and whether `platform_risk` may read `kernel.admin_audit` fully."*
**Breaks.** Widening puts money summaries in the hands of the most numerous platform role. The assigned split
is narrower than the schema spec's generic `is_platform`.
**Silence.** The assigned split ships. **SAFE** (narrower than what the schema delegated).
**Blocks.** Every platform cell in RLS §7–§10.
**Filed at.** RLS §15 item 1 · AMEND §14.2-A `OD-12`.
**Recommendation.** **None.** AMEND `OD-12` carries an empty recommendation cell; RLS flags it as *"a real
authorization choice the schema spec delegated."*

### ODR-46 — Re-map legacy `venue_manager` grants when the six-label enum lands
**Status.** OPEN — OWNER.
**Choice.** Re-map existing grants at the cutover, or carry them across unchanged.
**Breaks.** *Carry across* — anyone granted `venue_manager` **for box-office work** retains manifest
open/close, which is an `O-4` door-lifecycle authority. *Re-map* — some staff lose access until re-granted.
**Silence.** Grants carry across. **UNSAFE**, and the amendment says which way to err: *"Under-provisioning is
safe here; over-provisioning is not."*
**Blocks.** Grant hygiene at the cutover.
**Filed at.** VD §22.12 · AMEND §14.2-J `OD-75`.
**Recommendation — yes, as a direction rather than a rule.** AMEND `OD-75`: *"Under-provisioning is safe here;
over-provisioning is not."*

## The door and Apple Wallet

### ODR-47 — Ratify the session-bounded Wallet token profile · gates `wallet.apple.enabled`
**Status.** OPEN — OWNER.
**Choice.** Grant the relaxation of the ratified constraint *"a `.pkpass` must never carry a longer TTL than
the token"*, with its conditions — or keep the constraint as written.
**Breaks.** *Keep as written* — *"That was circular (the pass carries *the* token) and, taken literally, makes
Wallet impossible — a short-TTL barcode expires on an offline phone and locks a paying fan out."* *Grant* —
*"If step 3b regresses … a short `exp` would still have expired the stale token within hours; a
session-bounded `exp` will not."* — a defence-in-depth layer is knowingly given up.
**Silence.** **UNSAFE.** The grant is treated as given while **both of its own conditions were unimplemented
when it was granted**: (1) the offline-window bound, which *"applies **only when `session.ends_at IS NULL`**"*
and *"on the common branch bound nothing"* — now discharged by a clamp on the computed `exp`; and (2) key
revocation force-closing open door episodes, where the ruling's own words are *"Without this I would reject
DL-4"* and the mechanism *"was specified nowhere as invoking it."*
**Blocks.** The `wallet.apple.enabled` flag via Wallet §13 items **10a** and **10b**.
**Filed at.** Record rows `C56` / **`O9`** · DOOR §16 `OQ-5` · WALLET §15 `OQ-W4` + §14 `DL-4` + §5.2/§5.2a +
§13 items 10a/10b · EDGE §5.6 + §9 item 15 · AMEND §14.2-D `OD-25`.
**Recommendation — yes, with the two conditions named as the substance of the sign-off.** WALLET §15
`OQ-W4`: *"Accept the session-bounded wallet profile with the three §5.3 mitigations **and both of the ruling's
own conditions, neither of which was implemented when granted** … **The owner is signing off on a relaxation
whose safety rests on these two; §13 items 10a/10b gate the enable on them.**"*

### ODR-48 — Acknowledge that Wallet may not ship before the door M2 tables and offline step 3b
**Status.** OPEN — OWNER.
**Choice.** Acknowledge the hard gate, or ship Wallet first.
**Breaks.** *Ship first* — *"Without step 3b, Scenarios 2, 3 and 4 all **ADMIT**, and this document's central
claim is false"*, i.e. *"deploying defect W-3 at scale, on devices the platform does not control"*, which
cannot be recalled.
**Silence.** The gate is asserted by the spec and by `HG-1`; only the acknowledgement is missing. **SAFE.**
**Blocks.** The whole Wallet feature enable; requires `086` before `083`/`084`.
**Filed at.** WALLET §15 `OQ-W3` + §0.2 + §4.5 + §13 item 10 · AMEND §11 `HG-1`. **Not in the scope
amendment's `OD-` series.**
**Recommendation — yes.** WALLET §15: *"**Hard gate: Wallet may not ship before the door-lifecycle spec's M2
tables and step 3b are implemented and drilled.** Shipping first deploys W-3 at scale onto devices we do not
control. **Owner acknowledgement required.**"* *(This is close to a defect rather than a choice — see
**DF-16**.)*

### ODR-49 — Security sign-off on the `verify_jwt=false` set · gates deploy
**Status.** OPEN — OWNER.
**Choice.** Sign off on `wallet-pass-webservice` alone, or on **the whole `verify_jwt=false` set**.
**Breaks.** *Function-only* — the higher-risk member goes unreviewed: `door-session` *"is the highest-risk
member of the set … RLS is bypassed entirely behind it. Its security sign-off is owed alongside
`wallet-pass-webservice`'s, not after it."* *No sign-off* — *"the second unauthenticated endpoint ships
unreviewed."*
**Silence.** The surface ships unreviewed. **UNSAFE.**
**Blocks.** Deploy; `wallet.apple.enabled` via Wallet §13 item 12.
**Filed at.** WALLET §15 `OQ-W6` + §6.1 + §11.6a/§11.6b + §13 item 12 · EDGE §7 members 2 and 3 + §3.11 ·
record row `D9` · AMEND §14.2-D `OD-27`.
**Recommendation — yes.** WALLET §15: *"Accept with the §6.1 compensating controls **and §11.6a's liveness
preconditions (H-4)**, subject to an explicit security sign-off … **The sign-off should cover the
`verify_jwt=false` set as a whole, not this function alone.**"*
**Stale count to ignore.** The `OQ-W6` row says *"one of five such surfaces"*; edge §7 — the sole authoritative
enumeration — has since moved the count to **four**. Read §7, not the row.

### ODR-50 — Who owns the Apple Developer account and may renew the Pass Type ID certificate?
**Status.** OPEN — OWNER.
**Choice.** Name a single owner, or a primary **and** a named backup with portal access and KMS import
authority.
**Breaks.** *"the Apple certificate is **the only object in this design that fails on a calendar rather than
on an event**"*, and its expiry means *"**no new passes can be built and no pass update can be signed** — a
silent, calendar-driven outage of the whole Wallet feature."* Single-owner: *"a single person's absence takes
the feature down."*
**Silence.** Nobody is named. **UNSAFE.**
**Blocks.** `wallet.apple.enabled` (Wallet §13 items 1, 3, 5); `pass-cert-provision` operations.
**Filed at.** WALLET §15 `OQ-W2` + §8.1/§8.4 + §13 · AMEND §14.2-D `OD-24`.
**Recommendation — yes.** WALLET §15: *"Name a primary and a **backup** with portal access and KMS import
authority; put the renewal in a shared calendar independent of the alerting. **Owner call — organizational,
not technical.**"*

### ODR-51 — Wallet budget: KMS, APNs, storage — and the optional M2 signer it gates
**Status.** OPEN — OWNER.
**Choice.** Approve the budget at expected pass volume, or constrain it.
**Breaks.** Constrained KMS budget makes the optional `door-manifest` M2-signing edge function a skip, and
*"M2's *integrity* then rests on transport alone while M1's does not."*
**Silence.** Unfunded; Wallet §13 item 18 is not green, so the flag cannot flip. **SAFE (blocks rather than
ships).**
**Blocks.** `wallet.apple.enabled`; the build/skip call on the optional `086` edge function. Coupled to
`ODR-22`(ii).
**Filed at.** WALLET §15 `OQ-W8` + §13 item 18 · EDGE §3.9b + §5.4.2 · DOOR §16 `OQ-7`.
**Recommendation.** **None on the budget** — the register's cell is literally *"—"*. The dependent build call
does carry one (EDGE §3.9b: *"build it. The TLS-only fallback is acceptable for MVP if KMS budget is
constrained"*).

### ODR-52 — Post-open issuance: build the manifest supplement, or accept online-only door sales?
**Status.** SUPERSEDED — by `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §7.7, which contracts `venue.append_door_manifest_delta(p_session_id, p_atoms, p_op, p_cause_ref)` and states in its own first line that it *"Closes Wallet **DL-1** (post-open issuance)"*; by `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §6.3, which makes `kernel.issue_ticket_atoms` call it with `p_op := 'add'`; and by ratified **`C113`** (2026-08-28), which re-derives that call as **mandatory, not advisory** and gives the hook its own `SEAM-2` placement (stub `083`, body `086`). **This entry was wrong when it was written** — door §7.7 was already in the corpus at `32249f2` and this register cited that very section as a filing site while still tabling the question. Wallet §15 `OQ-W7`, Wallet §14 `DL-1` and scope amendment `OD-28` are stale and should be marked closed by the same bookkeeping act as the rest of the settled set. **Nothing here closes them.**
**Choice.** Build an append-only manifest supplement — `venue.append_door_manifest_entries`, definer, called
from `kernel.issue_ticket_atoms` when an open episode exists — or state *"door sales after manifest open are
online-only"* as an operational limit.
**Breaks.** *Neither* — *"Atoms issued afterwards (box-office/door sales, late comps) are absent from M2, so an
offline door rejects them — **a paying fan refused with no remedy**."* *Supplement* — no cost named: *"**This
is safe under the theorem**: issuing a *new* atom is not a custody move of an existing one, its
`credential_version` starts at 0, and it can strand nobody."*
**Silence.** **UNSAFE — and it is the worst of the three:** neither the supplement nor the stated limit, so the
failure arrives as an unnoticed rejection at the door.
**Blocks.** Door sales after manifest open; a door-spec change in `086`; Wallet §13 item 11a's drill.
**Filed at.** WALLET §15 `OQ-W7` + §14 `DL-1` + §13 item 11a · DOOR §7.7 · AMEND §14.2-D `OD-28`.
**Recommendation — yes.** WALLET §15: *"Build the supplement; it is small, provably safe, and the alternative
silently refuses paying fans. **Owner call.**"*

### ODR-53 — Offer a credential or Wallet pass while `resale_state ∈ {listed, locked}`?
**Status.** OPEN — OWNER.
**Choice.** Hide/refuse while listed or locked, or issue and let the door reject.
**Breaks.** *Issue* — the holder can display a QR the door will refuse with `listed_locked`; *"a ticket being
sold or transferred should not gain a new copy on a device."* *Hide* — *"zero product cost: the holder can add
after delisting."*
**Silence.** **Two documents default in opposite directions.** WALLET §15 `OQ-W5` defaults to **hide/refuse**
(`mint_wallet_pass` raises `precondition_failed('atom_listed_locked')`); EDGE §9 item 2 defaults to
**sign-but-door-rejects** (*"Defaulted to sign-but-door-rejects; product/policy to confirm"*). Neither is
unsafe; the divergence is. Wallet says explicitly: *"**Answer both together.**"*
**Blocks.** The RN control; `kernel.mint_wallet_pass`'s precondition (`084`) and `credential-sign`'s (`083`).
**Filed at.** WALLET §15 `OQ-W5` + §9.2 + §11.6 + §12 `W-E 26` · EDGE §9 item 2 + §3.2 · RN §4.4.1/§5.3 ·
AMEND §14.2-D `OD-26`.
**Recommendation — yes, from the Wallet side only.** WALLET §15: *"Answer both together. Recommend
**hide/refuse while listed or locked** — it reduces screenshot-resale confusion at zero product cost, since the
holder can add after delisting. **Product call.**"* EDGE offers no recommendation.
**Stale pointer.** `OQ-W5` and Wallet §9.2 both cite *"edge §12.2"*; the edge spec on this branch has no §12 —
the live location is edge §9 item 2.

### ODR-54 — Does the pass carry the holder's name?
**Status.** OPEN — OWNER.
**Choice.** Name present, or absent.
**Breaks.** *Present* — *"'Jane Doe · &lt;Club&gt; · Tonight 11:00 PM', on a phone left on a bar in a nightlife
venue, tells any stranger a named person's location, that they are out, and that they are not home"*, and it is
the loudest violation of the corpus's no-identity-on-the-credential posture. *Absent* — a venue wanting visual
ID matching must use the scanner's authenticated single-record lookup instead.
**Silence.** No name. **SAFE.**
**Blocks.** The pass template (a `pass.json` field).
**Filed at.** WALLET §15 `OQ-W1` + §9.1 · AMEND §14.2-D `OD-23`.
**Recommendation — yes.** WALLET §15: *"**No name.** If a venue needs ID matching, put it behind the
scanner's authenticated single-record lookup, never on a lock screen. **Owner/product call.**"*

### ODR-55 — Does transactional email exist in Phase 2?
**Status.** OPEN — OWNER.
**Choice.** Stand up a real transactional-email capability (provider account plus SPF/DKIM/DMARC on the
domain), or ship without it and let every `E` delivery row go `suppressed` with reason `channel_unavailable`.
**Breaks.** *Without* — *"**19 of the 24 mandatory types name `E`**"*, and *"**a mandatory money notice with
push as its only channel is one revoked permission away from unreachable**."*
**Silence.** Email rows go `suppressed`. **Structurally safe, operationally unsafe** — the design degrades
cleanly while the reachability guarantee for mandatory money notices does not hold. It compounds `ODR-87`.
**Blocks.** `_shared/email.ts`; every `E` channel row across the notification groups; `EMAIL_ENABLED` /
`RESEND_API_KEY` in `notify-dispatch`.
**Filed at.** NOTIF §10 `O-N3` + §1.6 `D-16` + §2.1/§3.5/§4.6/§6.4 · EDGE §3.14 · AMEND §14.2-H `OD-48`.
**Recommendation — yes, as a sequencing instruction.** NOTIF §10: *"Decide before build. The design degrades
safely (email rows go `suppressed`), but a mandatory money notice with **push as its only channel** is one
revoked permission away from unreachable."*

### ODR-56 — Announcement hold window, dual-control threshold, and the step-up primitive
**Status.** OPEN — OWNER.
**Choice.** The hold-window length and recipient threshold above which an announcement needs dual control —
and whether a step-up primitive exists to gate release at all.
**Breaks.** Too short or too high a threshold sends a mis-addressed blast to a venue's whole audience with no
recall. The step-up limb is not free-standing: *"the platform has no step-up primitive today"*, so it depends
on `ODR-42`.
**Silence.** Seeds ship at 300 s / 500 recipients if they are seeded at all; the step-up gate does not exist.
**Blocks.** NOTIF §7; the `notify.announcement_hold_seconds` (floor 120) and
`notify.announcement_dual_control_threshold` seeds.
**Filed at.** NOTIF §10 `O-N5` + §7.3/§7.4 · AMEND §14.2-H `OD-50`.
**Recommendation — yes.** AMEND `OD-50`: *"300 s hold, 500-recipient threshold; step-up depends on OD-08."*

### ODR-57 — May the marketing concept **release** announcements, or only draft?
**Status.** OPEN — OWNER.
**Choice.** Draft-only, or draft-and-release.
**Breaks.** Release authority puts a venue-wide, unrecallable broadcast in the hands of the role with the
standing incentive to use it.
**Silence.** Draft only, as specified. **SAFE.**
**Blocks.** Composer authority; pgTAP `N-A41`.
**Filed at.** NOTIF §10 `O-N6` + §7.3 + §2.5 · AMEND §14.2-H `OD-51`.
**Recommendation — yes.** NOTIF §10: *"**Draft only** (§7.3). Needs owner ratification because it is a
product-authority call, not a technical one."*

### ODR-58 — Do venue-staff notifications share the consumer inbox table?
**Status.** OPEN — OWNER.
**Choice.** One `notify.notification` table with `org_id`/`venue_id` columns, or a separate staff surface.
**Breaks.** *Two tables* — *"would double every RLS and dedupe assertion."*
**Silence.** One table. **SAFE.**
**Blocks.** The `notify.notification` table shape; the RLS matrix; the dashboard surface.
**Filed at.** NOTIF §10 `O-N8` + §2.2 Group V + §6.1 · AMEND §14.2-H `OD-52`.
**Recommendation — yes.** AMEND `OD-52`: *"One table with `org_id`/`venue_id`; two would double every RLS and
dedupe assertion."*

### ODR-59 — Notification retention, and the `C48` retention floor
**Status.** OPEN — OWNER.
**Choice.** Retention for `notify.notification`, `notify.delivery` and `notify.outbox`, and whether the two
projections are marked **NON-REBUILDABLE** under `C48`.
**Breaks.** Marking them rebuildable when they are not means a rebuild silently loses delivery history; short
retention on `notification` loses the fan's own record of what they were told.
**Silence.** No policy; `C48`'s compaction floor has nothing to respect.
**Blocks.** Retention; the `C48` floor.
**Filed at.** NOTIF §10 `O-N9` + §8.8 · AMEND §14.2-H `OD-53`.
**Recommendation — yes.** AMEND `OD-53`: *"24 months / 90 days / 30 days, **both projections marked
NON-REBUILDABLE**."*

### ODR-60 — Universal Links / App Links before any sensitive deep-link target
**Status.** OPEN — OWNER.
**Choice.** Stand up AASA and `assetlinks.json`, or keep every notification target navigation-only.
**Breaks.** Without them, `N-DL-4` binds: *"a notification link may never carry a secret, a token, or a
one-time action."* Adding a sensitive target without them is the failure the rule exists to stop.
**Silence.** `N-DL-4` binds; targets stay navigational. **SAFE.**
**Blocks.** Any deep-link target more sensitive than navigation.
**Filed at.** NOTIF §10 `O-N15` + §4.4 `N-DL-4` · AMEND §14.2-H `OD-56`.
**Recommendation — yes.** AMEND `OD-56`: *"AASA/`assetlinks.json` required before a sensitive target."*

## Privacy, CRM and the venue dashboard

### ODR-61 — Marketing's CRM and analytics ceiling — answered once, for three specs
**Status.** OPEN — OWNER.
**Choice.** Confirm that both marketing labels get the `audience_v1` template at their own plane's grain, are
denied `operations_v1`, are denied the email/name lookup probe, and that the demographic mix card is **outside**
the export authorization — or widen any of those.
**Breaks.** *Widening to `operations_v1`* defeats CRM §3.1's invariant *"Finance sees money and no contact.
Marketing sees contact and no money. **Neither sees both.**"* *Granting the lookup* hands the existence oracle
to *"the role with the standing incentive to run a list."* *Reading `O-2`'s "CRM/export/analytics access as
authorized" to include the mix* breaches demographics `X-3`.
**Silence.** Ships as specified. **SAFE.**
**Blocks.** The export template and the mix-card grant.
**Filed at.** CRM §13 `D-7` + §3 + §6.4 · DEMOG §14 `D-8` + §6 · ROLE_MODEL §5 `H2`/`H3` · AMEND §14.2-C
`OD-20`.
**Recommendation — yes.** AMEND `OD-20`: *"Audience template only, at each label's plane grain; no money
columns; no email-lookup probe; the demographic mix is **outside** the export authorization."* CRM §13 adds the
merge instruction: *"**Both should be answered once, together.**"*
**Citation defect.** CRM `D-7` points at `ROLE OD-8` (door break-glass) where it means ROLE_MODEL §5 `H2`/`H3`
— a consequence of the `OD-8` / `OD-08` collision. See **DF-2**.

### ODR-62 — Is a platform-plane bulk extraction path wanted at all?
**Status.** OPEN — OWNER.
**Choice.** Not built in Phase 2 (platform roles get a throttled read only), or build one.
**Breaks.** *Routing it through the venue surface* *"would file a platform action in a venue's history and
would give a compromised platform account the venue export's rate limits rather than a platform-grade one."*
*Building one properly* needs dual control, its own retention and its own audit action.
**Silence.** *"**Platform bulk extraction is not built in Phase 2.**"* **SAFE.**
**Blocks.** Platform export.
**Filed at.** CRM §13 `D-8` + §3.2 (`K-3`) · RLS §15.7 `MD-8` + §11.6 · VD §22.6 · AMEND §14.2-C `OD-21`.
**Recommendation — yes.** AMEND `OD-21`: *"**Not built in Phase 2.** If wanted it needs dual control, its own
retention and its own audit action — not the venue surface."*

### ODR-63 — Is `display_name` consent-gated in the export?
**Status.** OPEN — OWNER.
**Choice.** Keep `emit_name := emit_email` — one predicate driving both cells, so a name is blank wherever
email is — or emit the global `public.profiles.display_name` on every row of every export.
**Breaks.** *Ungated* — this is the claim record `RET-5` **deleted as false**: *"**`display_name` was emitted on
every row of every export, at every org, ungated by consent** … Two orgs union their files on the name column
directly and corroborate with admission time, `first_seen_at`, ticket types and acquisition route. **The
non-consenting majority was exactly as joinable as the consenting minority; only the carrying column
differed.**"* *Gated* — *"an `audience_v1` export over a heavily transferred session is mostly `customer_ref`
and ops columns with name and email blank on the same rows."*
**Silence.** **No default** — *"it changes what every export file looks like."*
**Blocks.** Every export file's shape.
**Filed at.** CRM §13 `D-13` + §4.3/§4.4 + §5.1 + §8.3 (correction `K-18`, carrying `RET-5`) · VD §9.6 ·
record row `C69`. **Not in the scope amendment's `OD-` series.**
**Recommendation — yes.** CRM: *"**Recommend the gate as written.** If rejected, §4.3, §4.4 case (a) and case
(d)'s sub-case must be restated to claim only what an ungated name column leaves true, which is very little."*

### ODR-64 — Confirm `R7`: comped and zero-price custody are excluded from the mix card
**Status.** OPEN — OWNER.
**Choice.** Keep `R7` — population eligibility limited to custody acquired **for consideration** — or count
everyone in the room.
**Breaks.** *Count everyone* — *"restores a population the operator can mint for free, which **voids every
k-anonymity claim in §5**."* *`R7`* — *"a genuinely free event never renders the card"*, a real product loss,
and the roster and card denominators legitimately differ (which is why `holders_excluded_ineligible` is
stored).
**Silence.** `R7`. **SAFE.**
**Blocks.** The eligibility rule; the card.
**Filed at.** DEMOG §14 `D-12` + §5.2 · CRM §1.3 + assertion 3 (`K-20`) · VD §9.5 · record row `C62`. **Not in
the scope amendment's `OD-` series.**
**Recommendation — yes.** DEMOG: *"This spec recommends R7 as written and asks that any relaxation be an
amendment, not a config change."* VD §9.5 adds: *"It is **owner decision D-12** in the demographics spec, not
something this surface may soften with copy."*

### ODR-65 — Ship with the population-differencing residual, or close it?
**Status.** OPEN — OWNER.
**Choice.** **(a)** accept and record; **(b)** raise `k` above 25 for venues above a repeat-audience
threshold; **(c)** withhold the card from sessions whose eligible-holder set overlaps a prior session by more
than a stated fraction.
**Breaks.** *(a)* *"An operator running the same 300 regulars weekly, holding the roster by name, and diffing
week over week retains a real inference channel **whose size this document cannot state as a number**."*
*(b)/(c)* fewer cards render for exactly the residency venues that want them.
**Silence.** (a). **UNSAFE in the sense that an unquantified channel ships unstated to the venue.**
**Blocks.** Before the card ships.
**Filed at.** DEMOG §14 `D-13` + §5.3 vector 7 + §11 (`J-8`/`J-9`, carrying `RET-1`). **Not in the scope
amendment's `OD-` series.**
**Recommendation — yes.** DEMOG: *"This spec asserts **no** coverage here and recommends (a) with the residual
published in the venue-facing help text."*

### ODR-66 — Five roles hold both the by-name roster and the mix card
**Status.** OPEN — OWNER.
**Choice.** Accept and say so, or make the two grants mutually exclusive.
**Breaks.** *Accept* — *"The bound is a group bound, never an anonymity bound in the colloquial sense"*: the
floor of 5 is a bound over five people the reader **can name**, and it sharpens `ODR-65` because *"an operator
who can enumerate the room by name between two published snapshots knows **which** five people the delta ranges
over."* *Split* — `venue_manager` loses either the roster or the card, *"a significant product change."*
**Silence.** Accept. **SAFE only because the claim is corrected either way** — the corpus already restates the
bound honestly.
**Blocks.** Nothing; *"the claim is corrected either way."*
**Filed at.** DEMOG §14 `D-14` + §5.3 vector 6 + §11 · CRM §4.5 + `K-19` item (6) · record row `C70`. **Not in
the scope amendment's `OD-` series.**
**Recommendation.** **None.** CRM §4.5: *"only the owner can decide whether to split them."*

### ODR-67 — The backup-retention window `{N}`
**Status.** OPEN — OWNER.
**Choice.** The number of days of encrypted backup retention named in binding user-facing erasure copy and
used to set the tombstone's `purge_after`.
**Breaks.** A wrong number in binding copy is a promise the platform cannot keep; the tombstone's purge window
is derived from it.
**Silence.** **No default — the copy cannot ship:** *"**The user-facing copy cannot ship with a
placeholder.**"*
**Blocks.** The user-facing erasure copy; `purge_after = erased_at + {N} + margin`.
**Filed at.** DEMOG §14 `D-6` + §8.5 + §10.2 · CRM §13 `D-10` + §9.3 (which states *"this document does not
create a second one"*) · AMEND §14.2-C `OD-16`.
**Recommendation.** **None** — no number is proposed anywhere. Owner / ops, jointly.

### ODR-68 — Confirm the MVP transfer-freeze predicate is session-wide
**Status.** OPEN — OWNER.
**Choice.** Keep the session-wide predicate for MVP and correct the four documents that describe `C43`'s
per-open-manifest-ticket narrowing as implemented — **or** pull the narrowing into MVP, which *"is a **new**
ratification, not a clarification."*
**Breaks.** *Keep* — nothing functionally; the session-wide predicate is strictly more restrictive and the
narrowing is *"a pure additive conjunct"* later. *Pull it in* — a Gate-M item enters MVP.
**Silence.** Session-wide in code, narrowed in four documents. **Functionally safe, documentationally
UNSAFE** — *"four documents currently describe a narrowing nothing implements."*
**Blocks.** Four documents' correctness (schema §2.3.1, RPC §12.4b, RLS §14.3, migration plan).
**Filed at.** DOOR §16 `OQ-4` · RLS §17 `X-7` + §14.3.2 · VD §22.11 · EDGE §9 item 7 + §5.6 · RN §12 item 9 +
§4.5 · SCHEMA §2.3.1 · AMEND §14.2-I `OD-59`.
**Recommendation — yes.** AMEND `OD-59`: *"Keep the session-wide predicate; the narrowing is a pure additive
conjunct once `door_manifest_entry` is populated."* *(The confirmation is ceremony over a documentation defect
— see **DF-17**.)*

### ODR-69 — Drain active listings and initiated transfers at door-open?
**Status.** OPEN — OWNER.
**Choice.** Cancel them, return the atom to the owner and notify — or leave them and refuse the holder at the
door with `listed_locked`.
**Breaks.** *No drain* — *"a fan whose ticket is mid-transfer or listed therefore arrives at the door and is
refused, with no action available to them and none to the door"* until the `C43` TTL, hours later. *Drain* —
*"cancellation is a surprise"* to the seller; the alternative *"is worse but is *visible*."*
**Silence.** Drain — it is already in the door RPC's write set. **SAFE for admission; a product surprise.**
**Blocks.** DOOR §7.3 sign-off, plus the §11.3 notification copy.
**Filed at.** DOOR §16 `OQ-2` + §7.3 + §13.5 + §11.3 · AMEND §14.2-I `OD-58`.
**Recommendation — yes.** DOOR §16: *"Recommend: drain, with the notification in §11.3. **Product
sign-off.**"*

### ODR-70 — Does opening the manifest early bother anyone commercially?
**Status.** OPEN — OWNER.
**Choice.** **(i)** keep manifest-open and the transfer freeze coupled and accept the early freeze;
**(ii)** decouple — open the manifest early for offline capability, engage the freeze at `doors_at`;
**(iii)** re-snapshot the manifest at the freeze moment.
**Breaks.** *(ii)* *"reintroduces exactly the snapshot-then-freeze window §5.3 closes — a transfer committing
between manifest generation and freeze would strand a credential at an already-armed offline door."*
*(iii)* *"means devices must re-sync at doors, which reintroduces failure #10"* — the venue network dying at
doors time, on the night offline capability matters most.
**Silence.** Coupled. **SAFE on custody**; it costs the late-transfer window.
**Blocks.** The operating recommendation only — no code path differs; it sits on
`door.manifest_early_open_window` (default `'12 hours'`).
**Filed at.** DOOR §16 `OQ-1` + §5.3 + §14.5 + §10.6 · AMEND §14.2-I `OD-57`.
**Recommendation — yes.** DOOR §16: *"Recommend: keep them coupled; accept the early freeze. **Owner call.**"*

### ODR-71 — Should the `C25` compensate branch void the seller's atom at all?
**Status.** OPEN — OWNER.
**Choice.** Keep the ratified behaviour, or refund the buyer and merely unlock the seller's atom.
**Breaks.** *Keep* — this is *"§5.4's only unelevated residual"* and failure #22: a routine, **unelevated,
unaudited, human-free** sweep voids an atom that an open episode's snapshot still records as active, so an
offline device admits a refunded ticket (*"Revenue leak, not a double-admit"*). *Change* — *"it is ratified
behaviour in a document I do not own, `D2` makes `voided` the only money-reversal terminal, and the change
would ripple into the `C26` terminal state machine."*
**Silence.** Unchanged; the residual is bounded by the `revoke` delta for any device that syncs.
**Blocks.** `C25` semantics.
**Filed at.** DOOR §16 `OQ-8` + §5.4 + §7.6/§7.7 + §14 #22 · RPC §12.3 · AMEND §14.2-I `OD-61`.
**Recommendation.** **None.** DOOR: *"**I have not changed it** … Flagged for whoever owns RPC §12.3."*

### ODR-72 — Name the guest-list write RPCs · surface F
**Status.** OPEN — OWNER.
**Choice.** Contract create-list / add-guest / remove-entry, or drop the surface. *"**No RPC is named anywhere.**
Three distinct writes, zero signatures."*
**Silence.** VD's standing rule holds: *"the control is read-only or it does not render. Do not soften it to
'hidden behind a flag'."* **SAFE.**
**Blocks.** Venue dashboard surface F.
**Filed at.** VD §20A.3 `U-1` + §11.2 · TRACE `G-10` · AMEND §14.2-J `OD-62`.
**Recommendation.** **None** — `OD-62`'s cell is empty.

### ODR-73 — Name the mark-a-guest-arrived RPC · the door
**Status.** OPEN — OWNER.
**Choice.** Contract it, or the control does not render. RLS grants the door principal exactly this narrow
update and **no contract exists**.
**Silence.** The control does not render. **SAFE, and operationally expensive:** *"the single most-used control
at a door"*, *"the one a door will hit a thousand times a night."*
**Blocks.** The door.
**Filed at.** VD §20A.3 `U-2` + §11.5 · TRACE `G-9` · AMEND §14.2-J `OD-63`.
**Recommendation.** **None** — `OD-63`'s cell is empty.

### ODR-74 — Name the promoter record and link RPCs, and a live slug-availability read · surface E
**Status.** OPEN — OWNER.
**Choice.** Contract create/edit promoter, commission terms, create link, set status and an availability check
— or drop the surface. *"the UI is required to run a live global-namespace check **against nothing**."*
**Silence.** The controls do not render. **SAFE.**
**Blocks.** Venue dashboard surface E. Overlaps `ODR-28` on the `status` limb.
**Filed at.** VD §20A.3 `U-3`, `U-4` + §10.2/§10.3/§10.4 · TRACE `G-11` · AMEND §14.2-J `OD-64`.
**Recommendation.** **None** — `OD-64`'s cell is empty.

### ODR-75 — Grant the two door pre-confirm reads · the door-open confirm
**Status.** OPEN — OWNER.
**Choice.** Add a blast-radius dry-run read and a live-device-count read, or ship the confirm dialog without
them.
**Breaks.** Without them *"the most consequential door control in the product asks for a confirmation the
operator cannot evaluate."* The live-device count should come from `venue.door_session` — *"a presence fact"* —
rather than `scan_device.last_sync_at`, *"which reports a poll."*
**Silence.** The confirm dialog ships blind. **UNSAFE in the operational sense.**
**Blocks.** The door-open confirm.
**Filed at.** VD §20A.3 `U-5`/Δ11 and `U-6`/Δ12 + §12.4 · TRACE `G-16`/`G-17` · RLS §17 `X-19` · AMEND §14.2-J
`OD-65`.
**Recommendation — yes.** AMEND `OD-65`: *"Small, read-only, same role set as the open RPC. Without them the
most consequential door control asks for a confirmation the operator cannot evaluate."*

### ODR-76 — Name a capacity-change RPC for an existing batch · §8.4
**Status.** OPEN — OWNER.
**Silence.** The control does not render. **SAFE.** **Blocks.** VD §8.4.
**Filed at.** VD `U-8` + §8.4 · AMEND §14.2-J `OD-67`.
**Recommendation — partial.** AMEND `OD-67`: *"The guarded behaviour and refusal floor are already specified in
detail"* — i.e. only the signature is missing.

### ODR-77 — Name an update RPC for `catalog.event` / `event_session` · §7.3
**Status.** OPEN — OWNER.
**Choice.** Contract editing, or ship create-only. *"Creation is contracted; editing is not."*
**Silence.** Draft events cannot be edited. **SAFE.** **Blocks.** VD §7.3.
**Filed at.** VD `U-9` + §7.3 · AMEND §14.2-J `OD-68`. **Recommendation.** **None.**

### ODR-78 — Name `kernel.update_organization` · §16.1
**Status.** OPEN — OWNER.
**Choice.** Contract it, or the org display name cannot be edited. *"`catalog.update_venue` exists; the org has
no counterpart."*
**Silence.** Not editable. **SAFE.** **Blocks.** VD §16.1.
**Filed at.** VD `U-10` + §16.1 · AMEND §14.2-J `OD-69`. **Recommendation.** **None.**

### ODR-79 — Inventory warning thresholds
**Status.** OPEN — OWNER.
**Choice.** The low-inventory threshold values, and whether a per-venue override exists. *"no key is named and
no per-venue override exists. **Left unresolved rather than invented.**"*
**Silence.** No key; the zone-6 warning and the low-inventory notification rule both have nothing to fire on.
**Blocks.** VD §6.1 and the low-inventory notification rule.
**Filed at.** VD §22.8 · NOTIF low-inventory rule · AMEND §14.2-J `OD-76`.
**Recommendation.** **None.** AMEND `OD-76`: *"Left unresolved rather than invented."*

### ODR-80 — Kill switches for the three features that have none
**Status.** OPEN — OWNER.
**Choice.** Name runtime flags for demographics, promoter codes and CRM export, or leave them gated only by
package application.
**Breaks.** *"gated only by package application, which is a deploy and not a runtime control"* — there is no way
to turn any of the three off without a migration.
**Silence.** No kill switches. **UNSAFE** for anything that goes wrong in production on those three features.
**Blocks.** The scope amendment's own flag rule.
**Filed at.** AMEND §12.2 + §14.2-K `OD-78`.
**Recommendation.** **None.** AMEND: *"none — naming a new flag is a scope decision. The keys would be rows in a
table `078` already creates."*

## Contracts and confirmations

### ODR-81 — Confirm `venue.set_event_security_config`'s key set and `revoke_signing_key`'s ack parameter
**Status.** BLOCKED BY ANOTHER DECISION — **`ODR-20`.** There is no key set to confirm until the corpus says whether `venue.set_event_security_config` exists at all. RPC §20.14 `R-11` and `R-21` are two rows for that reason, and the corpus is explicit that they are different questions: *"answering `R-11` does not answer this."*
**Choice.** Confirm the authored closed key set — `door.manifest_ttl_interval`,
`door.manifest_early_open_window`, `door.implicit_freeze_offset_interval`, with anything else raising
`invalid_input` and the function creating no key — and the authored `p_ack_live_credentials` parameter on
`kernel.revoke_signing_key`; or supply different ones.
**Breaks.** *"RLS §11.4 grants a function no document defines; §20.6.6 supplies a definition so it is not
invented at build time, but the owner should confirm it rather than inherit it."* The ack parameter is
`INFERENCE`: *"the corpus specifies the pattern for the door override and not for key revocation, and the
consequence here is strictly larger."*
**Silence.** The authored forms stand, inherited rather than confirmed. **SAFE** — the override direction is
one-way (*"An event override may only be more restrictive than the platform value, never less"*).
**Blocks.** Rides `ODR-20`. **`ODR-20` and `ODR-81` are explicitly different questions:** *"answering `R-11`
does not answer this."*
**Filed at.** RPC §20.14 `R-11` + §20.6.6 + §20.7.5 + §19 items 10 and 11. **Not in any consolidated index.**
**Recommendation — the authored form itself, flagged as inherited.** RPC §20.6.6: *"the owner should confirm
the key set before it is built."*

### ODR-82 — Confirm the offline clock-skew time-bucket is 30 seconds
**Status.** OPEN — OWNER.
**Choice.** Confirm 30 s (so `± 2 time-buckets` = `± 60 s`), or set a different magnitude.
**Breaks.** *"**A tolerance with no stated width is not implementable: two scanner builds would each pick a
number, and admission would differ by vendor.**"* The corpus cited the bucket in **eight** places and defined it
in **none**.
**Silence.** 30 s stands as a **fixed protocol constant, deliberately not a config key** — *"signer and
long-offline verifier must agree"*, and a runtime-tunable value is read by the signer now and by the device
only at its last sync. **SAFE.**
**Blocks.** Nothing. *"**Not a blocker and not an open decision** … What is owed is confirmation of the
magnitude."* But: changing it later *"is a change to `OFFLINE-VERIFY-v1` … plus a scanner-SDK release, **not** a
config edit — so it is cheaper to confirm now than after the first build ships."*
**Filed at.** RPC §20.14 `R-22` *(first occurrence)* + §9.3 · record row `C79` (`MP-1`). **Not in any
consolidated index.**
**Recommendation — yes.** RPC §9.3: *"`30 s` is chosen as the smallest window that absorbs ordinary
unsynchronised-device drift without materially widening replay … **This is a numeric tolerance, not an
authority change** — it is decided here, not left open — but the owner should confirm the magnitude rather than
inherit it."*

### ODR-83 — Accept the maturity-helper race residual, or amend the global lock order?
**Status.** OPEN — OWNER.
**Choice.** Confirm the recorded residual on `kernel.money_role_grant_matured`, or put `kernel.org_member` into
the global lock order.
**Breaks.** *"**Three of the four race directions fail closed** … **One is open for the duration of one
transaction:** a money→money re-grant (`org_finance` → `org_owner`) resets `granted_at`, and a caller on the
pre-reset snapshot passes."* Closing it *"means putting `kernel.org_member` into the global lock order — an
amendment to a ratified invariant (`C28`), not a contract edit."*
**Silence.** The residual stands. **Bounded, but pointed the wrong way:** *"it is **exactly the direction the
control exists to stop** … **A reviewer who later finds it should find this row, not discover it.**"*
**Blocks.** Nothing.
**Filed at.** RPC §20.14 `R-23` + §1.1e · SCHEMA §13.6 · DA §6.2. **Not in any consolidated index.**
**Recommendation — implicit accept.** RPC: *"**§1.1e records this as an accepted residual and does not close
it.**"*

### ODR-84 — Ratify the self-bid and self-offer narrowings
**Status.** OPEN — OWNER.
**Choice.** Ratify the exclusion of a listing's own seller from bidding on and making offers against their own
listing, or leave the literal ratified grant.
**Breaks.** RLS §11.1 grants *"any `authenticated`"*, which read literally permits shill bidding on one's own
listing — *"which is a fraud primitive, not a capability."*
**Silence.** The narrowing stands as contracted (`policy_violation('self_bid')` / `('self_offer')`). **SAFE in
direction — but it is an unratified narrowing of a ratified row.**
**Blocks.** Nothing; `088` inherits it.
**Filed at.** RPC §19 item 9 + §20.8.4 + §20.8.5 · RLS §11.1. **Filed in no register at all — it exists only
in RPC §19.**
**Recommendation — the narrowing itself.** RPC §19: *"**Narrowing a ratified grant is a decision, not a
clarification**, and it is flagged for the owner rather than absorbed."*

### ODR-85 — The credential token TTL value and re-sign cadence
**Status.** OPEN — OWNER.
**Choice.** The numeric app-profile TTL and the rolling re-sign cadence.
**Breaks.** *"depends on the offline dead-zone tolerance at real venues and the acceptable screenshot-resale
window"* — *"long enough to survive a dead-zone at the door, short enough to bound a verifier running an M2
older than its `not_after`."*
**Silence.** `credential.app_ttl_interval` seeds at `'4 hours'`. **SAFE.**
**Blocks.** A `078` seed value only.
**Filed at.** EDGE §9 item 4 + §5.5 · WALLET §11.5. **Not in any consolidated index.**
**Recommendation.** **None** — *"needs a product/ops number. **Bounded, not fixed.**"*

### ODR-86 — KMS provider, signing algorithm, and token wire format
**Status.** OPEN — OWNER.
**Choice.** Ed25519 or ECDSA-P256; AWS KMS, GCP KMS or CloudHSM; compact JWT-like or custom COSE.
**Breaks.** Nothing security-wise — *"both satisfy the non-exposure rule."* Wallet §5.4 already sizes the QR
against an Ed25519 64-byte signature.
**Silence.** Unpinned. **SAFE, but the door SDK's wire format cannot be fixed.**
**Blocks.** The door SDK contract. No migration.
**Filed at.** EDGE §9 item 3 + §5.1/§5.3. **This is an infra/ops call, not the founder's**, and the edge spec
says so: *"**Flagged, not decided here** … left to infra/ops."*
**Recommendation.** **None**, beyond §5.1's *"Ed25519 preferred."*

### ODR-87 — Notification permission priming
**Status.** OPEN — OWNER.
**Choice.** Specify a pre-permission priming screen before the OS notification prompt, or ship the cold prompt.
**Breaks.** *"`INFERENCE:` one is needed — **a cold OS prompt with no context is the classic way to lose the
permission permanently** — but it is **not invented here.**"*
**Silence.** A cold OS prompt, and a permanently lost push permission. **UNSAFE — and it compounds `ODR-55`:**
if transactional email does not exist either, a mandatory money notice becomes unreachable.
**Blocks.** An RN surface that nothing specifies.
**Filed at.** RN §12 item 12 + §6.4. **This gap has NO id in any register in the corpus** — not `O-N1`…`O-N15`,
not the notifications spec's cross-agent list, not the scope amendment's index. It exists in exactly one place.
**Recommendation.** **None.**

### ODR-88 — May `venue_box_office` refund cash at the door?
**Status.** OPEN — OWNER.
**Choice.** Grant a capped cash-refund-at-door authority — *"its own cap, step-up and reason code"* — or not.
**Breaks.** *No* — `C46` requires refund-at-door to run through an authenticated staff principal, and among
venue-side principals *"only `org_finance` initiates a refund"*, so the door-refund path has **no operational
actor**. *Yes* — box office gains money authority `O-2` says it must not have.
**Silence.** Not granted. **Privilege-safe; leaves `C46`'s implied actor missing.**
**Blocks.** Nothing structural.
**Filed at.** ROLE_MODEL §13 `OD-5` + §5.3 cell `B6` + §7.6 · `C46`. **Not in the scope amendment's `OD-`
series.**
**Recommendation.** **None.** ROLE_MODEL: *"None granted here. If the answer is yes, it needs its own cap,
step-up and reason code — money-authority agent's call."*

### ODR-89 — Does `org_admin` read `venue.settlement`?
**Status.** OPEN — OWNER.
**Choice.** Keep the `A(own-org)` settlement SELECT, or deny settlement too.
**Breaks.** Nothing functional; coherence only. *"A settlement header shows gross, fees, refunds, net. That is
finance data, and it is arguably inconsistent with denying the payout ledger."*
**Silence.** Keep. **SAFE in isolation** — but see the note below.
**Blocks.** *"nothing; consistency only."*
**Filed at.** MONEY §11 `D-4` + §3.4 · RLS §15.7 `MD-4` · VD §5 row 37 · AMEND §14.2-A `OD-04`.
**Recommendation — yes.** MONEY §11: *"Keep — settlement is operational reconciliation, payout is money-out.
But the inconsistency is real and I am naming it rather than smoothing it."*
**Answer with `ODR-35`.** Answering `ODR-35` "deny" and this one "keep" is internally incoherent, and no
document says so — see **DF-8**.

### ODR-90 — Does the original promoter earn on a marketplace resale?
**Status.** OPEN — OWNER.
**Choice.** No — or a lifetime-attribution model.
**Breaks.** *Yes* fails four ways, per PROMO §5.6: **structural** — *"`venue.attribution.order_id` FKs
`venue.order`. A native resale is a `market.market_sale`, not an order. There is no column that could hold the
credit"*, and manufacturing one is a `venue → market` coupling the aggregate rules forbid; **commercial** —
*"Paying again on a resale pays them for someone else's decision to sell"*; **incentive** — *"A promoter who
earns on resale earns more when their allocation is scalped … the single most self-defeating money rule in the
platform"*; **consistency** — the venue's recapture is the `venue_royalty` line.
**Silence.** No commission on resale. **SAFE.**
**Blocks.** PROMO §5.6. Additive later as a `market_sale`-grain attribution with its own cause.
**Filed at.** PROMO §13 `OWNER DECISION 2` + §5.6 · AMEND §14.2-F `OD-34`.
**Recommendation — yes.** AMEND `OD-34`: *"**No.** Additive later as a `market_sale`-grain attribution with
its own cause."*

### ODR-91 — What is the remedy for a genuinely wrong attribution?
**Status.** OPEN — OWNER.
**Choice.** None on-ledger — an off-ledger commercial settlement, recordable later as a Gate-M adjustment — or
build an override.
**Breaks.** *Override* — *"an override that mutates an AO ledger destroys every guarantee in §4"*: the
no-double-commission proof, the freeze, and `displaced_promoter_id`'s evidentiary value.
**Silence.** No remedy exists, and the spec says what happens next: *"**Support will ask for an override within
the first month. The answer must be decided *before* someone builds one.**"* **UNSAFE by omission.**
**Blocks.** Nothing to build now; it is a pre-emptive prohibition on a future build.
**Filed at.** PROMO §13 `OWNER DECISION 6` + §3.4 + §4 · AMEND §14.2-F `OD-38`.
**Recommendation — yes.** AMEND `OD-38`: *"**None on-ledger** — the freeze is absolute; remedy is a commercial
settlement off-ledger. An override that mutates an AO ledger destroys every §4 guarantee."*

### ODR-92 — `venue.get_dashboard_summary`: schedule it, or accept N queries?
**Status.** OPEN — OWNER.
**Choice.** Schedule the aggregate RPC, or leave the dashboard home at N separate queries.
**Breaks.** *N queries* — a slower home screen, nothing more. *Schedule* — the aggregate-read risk: *"one
function, one grant, N projections, and the narrowest caller ends up seeing a number derived from data they may
not read."*
**Silence.** Deferred — and the corpus names the deferral itself as the problem: *"**Nothing else in the corpus
depends on it**, so it may be deferred without blocking a package — which is precisely why it will be deferred
by default unless named."*
**Blocks.** Only its own RLS §11 EXEC row, which is explicitly withheld: *"**No EXEC row is written for a
function whose existence is undecided** — writing one would make §11 the document that decided it."* If
scheduled, `SEAM-1` floors it at `090`.
**Filed at.** RPC §20.14 `R-10` + §20.10 · RLS §11.1c (`AUTHZ-R3`) · VD `U-7` / Δ3c · TRACE `G-18` · PLAN §8
preamble · AMEND §14.2-J `OD-66`.
**Recommendation — split.** AMEND `OD-66`: *"Home works at N queries."* RPC declines: *"it is contracted rather
than dropped so the decision is the owner's."*


---

# BAND 4 — blocks nothing in the current scope

**Thirty-three decisions.** Real, unanswered, and nothing in the Phase-2 scope waits on them. Four need
counsel rather than the owner; four are commercial or platform questions outside the design corpus entirely.
Kept in the same instrument so that "we never decided that" is never the answer.

**Changed at `269e473`:** `ODR-6` **arrived** from Band 1 (its own `Blocks` line always read *"nothing
numbered"*), and `ODR-124` (`O18`) is **new**. **One entry is BLOCKED:** `ODR-100`, by `ODR-101`.

Format: **choice** · *what breaks* · **silence** · blocks · filed at · recommendation.

---

### ODR-93 — Cross-region native resale: saga/escrow, or intra-region-only?
**Status.** OPEN — OWNER.
Saga/escrow over the `paid_pending_transfer` money-safety window, **or** explicit intra-region-only scoping of
native resale. *`C8` (single-DB sale) and `C14` (home-region log) are mutually exclusive, so cross-region
native resale is undefined; the two admissible forms are ratified constitution text and the **choice** is
this.* **Silence → SAFE:** the Miami single-region MVP builds neither.
Blocks: Gate M / multi-region. No package.
Filed at: record rows `C50` / **`O6`** · DA §0.4 + §6.2 · CDM §12 + §15 `C50` · risk register `R10` · AMEND
§14.2-K `OD-80`.
Recommendation: **none of substance** — AMEND `OD-80`: *"Miami single-region builds neither; carried so it is
not lost."*

### ODR-94 — Offline first-admit-wins consensus under clock skew and partition
**Status.** OPEN — OWNER.
Design the arbitration and fraud-queue mechanism, or continue on `C23`'s total order as the interim. *Without
it, offline scanning at scale has no defined arbitration for two doors that each admit first.* **Silence →
SAFE at current scale**, unsafe at offline scale.
Blocks: *"offline scanning at scale."* No package.
Filed at: DA §0.4 · `_governance/ARCHITECTURAL_RISK_REGISTER.md` (*"**Still OPEN**"*) · SCHEMA §12.
Recommendation: **none.**

### ODR-95 — Resale-policy snapshot drift
**Status.** OPEN — OWNER.
Define the runtime capture rule for a native listing that outlives a mid-sale policy change, or leave it. *A
listing can carry a policy the org has since changed; storage is versioned (schema §2.5) and the runtime
capture rule at listing time is open.* **Silence → SAFE until native resale.**
Blocks: Gate M / native resale. No package.
Filed at: DA §0.4 · risk register (*"decide before native resale"*) · SCHEMA §2.5 + §11 + §12 · CTO memo Gate M
item 15.
Recommendation: **none.**

### ODR-96 — Per-event identity-verification strength
**Status.** OPEN — OWNER.
Name-match-required versus custody-follows-credential, and how strong verification must be per ticket and per
event. *"where exactly identity binds, how strong the verification must be per ticket/event, and what happens
when a verified name legitimately differs (marriage, legal change, corporate holder) remain open."* **Silence →
SAFE:** custody is primary and name-match layers on.
Blocks: nothing named; high-risk events.
Filed at: DA §0.4 + the "three hardest open questions" appendix item 2 · risk register · SCHEMA §3.12 + §12.
Recommendation: **none.**

### ODR-97 — Which privacy regimes apply? *(counsel)*
**Status.** OPEN — OWNER.
*"(a) treat US-only, (b) treat GDPR as applying to visitor traffic, (c) build to the strictest and stop
asking."* **Silence → SAFE:** the design already satisfies the strictest reading.
Blocks: nothing. Filed at: DEMOG §14 `D-1` + §3.1 · AMEND §14.2-C `OD-15`.
Recommendation: *"Counsel. The design survives the strictest answer with no redesign."*

### ODR-98 — Is gender identity special-category / sensitive personal information? *(counsel)*
**Status.** OPEN — OWNER.
Yes or no. *A "yes" would normally force redesign; here it does not — the capture is already explicit-consent
shaped.* **Silence → SAFE.** Blocks: nothing.
Filed at: DEMOG §14 `D-2` + §3.1 · AMEND §14.2-C `OD-18`.
Recommendation: *"Counsel. A 'yes' requires no change."* The demographics spec asserts **no** legal conclusion
of its own, deliberately.

### ODR-99 — Which mandatory notification types are legally compulsory, and where? *(counsel)*
**Status.** OPEN — OWNER.
Treat the 24-type mandatory class as a product-ethics choice, or as a compliance control. *Consumer-protection
receipt rules, payment-reversal disclosure, card-network dispute notices and app-store guidance all bear on
it.* **Silence → the ethics judgement stands as if it were the legal answer** — harmless as product posture,
unsafe as compliance posture.
Blocks: *"whether the class is policy or compliance."* Nothing structural — *"the answer changes one registry
column."*
Filed at: NOTIF §10 `O-N4` + §3.4 + Appendix A2 · AMEND §14.2-H `OD-49`.
Recommendation: *"Counsel. The design is built so the answer changes one registry column."*

### ODR-100 — The confidential-IP document in repository history *(counsel)*
**Status.** BLOCKED BY ANOTHER DECISION — **`ODR-101`.** The roadmap ties them: if the repository is made private, this is a residual-exposure question; if it stays public, it becomes a history-rewrite decision that a visibility change alone cannot undo.
Accept the exposure, or rewrite history. *Tied to `ODR-101`: if the repository stays public, the IP agreement's
presence in history becomes a decision that cannot be undone by a visibility change alone.*
**Silence → exposure stands.**
Blocks: nothing in the design corpus.
Filed at: `_governance/SNATCHIT_GITHUB_REPOSITORY_STABILIZATION_ROADMAP.md` §6 / §19.7.
Recommendation: **none** — it is posed as a counsel question.

### ODR-101 — Repository visibility: private now, or stay public?
**Status.** OPEN — OWNER.
Make the repository private, or keep it public. *Staying public makes the Class-C removals and demo-credential
rotation immediate, and turns `ODR-100` into a history-rewrite decision.* **Silence → stays public.**
Blocks: nothing in the design corpus; it gates that roadmap's PR sequence.
Filed at: roadmap §8 / §19. **Note:** the whole roadmap is marked *AWAITING OWNER APPROVAL*.
Recommendation — yes: *"unless being public serves a deliberate goal *today*, **make the repository PRIVATE
now**."*

### ODR-102 — Buy the Supabase Pro plan?
**Status.** OPEN — OWNER.
Buy Pro (~$25/mo) or stay on the current plan. *Pro is what enables Supabase **branching**, and branching is
what a Development → Staging → Production chain needs; it also enables **PITR**, **network restrictions** and
**log drains**, all recommended by the security audit. Without it there is no production-like environment in
which to rehearse the sixteen-package chain.* **Silence → no staging environment**, and every Phase-2 migration
is rehearsed only against a local database.
Blocks: nothing in the corpus by name; it is the *"biggest structural gap before Phase 2"* in that document's
own words.
Filed at: `docs/architecture/PHASE_1_FOUNDATION.md` §6 (*"**Owner decision.**"*).
Recommendation: **none stated as such** — the section argues the need and stops.

### ODR-103 — GitHub Copilot?
**Status.** OPEN — OWNER.
Purchase now, or not. **Silence → not purchased.** Blocks: nothing.
Filed at: roadmap §18.
Recommendation — yes: *"**NO — not now.** … Decision: no purchase; re-evaluate at team ≥2."*

### ODR-104 — Add `age_band` in a later wave?
**Status.** OPEN — OWNER.
Add the field (`18_20 · 21_24 · 25_34 · 35_44 · 45_plus · prefer_not_to_say`, *"**Bands only. Never a date of
birth, never a year, never a derived integer age**"*), or not. *Adding without a fresh `notice_version` and its
own opt-in silently enrols someone in a new dimension; a DOB adds minor-data and identity-theft liability; it
may never be crossed with gender.* **Silence → SAFE:** not in Phase 2.
Blocks: nothing. Filed at: DEMOG §14 `D-3` + §1.5 · AMEND §14.2-E `OD-30`.
Recommendation: *"Value set pre-specified; needs a new `notice_version` and a separate opt-in. **Not Phase
2**."*

### ODR-105 — Does `platform_admin` get aggregate demographic access at all?
**Status.** OPEN — OWNER.
Yes, any session, audited — or zero platform access. *Yes means a platform-wide demographic read exists at all;
no means platform cannot diagnose a card.* **Silence → yes.** Blocks: nothing.
Filed at: DEMOG §14 `D-7` + §6 · AMEND §14.2-E `OD-31`.
Recommendation — and it leans against its own default: *"This spec defaults to yes, any session, audited. The
alternative (zero platform access) is also coherent and slightly stronger."*

### ODR-106 — Who owns the compelled-disclosure runbook?
**Status.** OPEN — OWNER.
Name an owner for the out-of-band, dual-controlled, audited direct-database procedure — *"never as a product
feature, never a self-service admin screen, never a role."* **Silence → nobody owns it; there is no product
default at all**, so when process arrives someone improvises or builds the screen §7.1 forbids.
Blocks: nothing. Filed at: DEMOG §14 `D-10` + §7.3 · AMEND §14.2-E `OD-32`.
Recommendation: *"Out-of-band, dual-controlled, audited; never a product feature."* — the shape, not the owner.

### ODR-107 — Does a native-rail resale purchase create a contact relationship?
**Status.** OPEN — OWNER.
No consent by default with the same unchecked opt-in at resale checkout; treat the settlement flow as a
customer relationship; or a flat "resale grants nothing" with no opt-in offered. *The third *"leaves a venue
permanently unable to contact a growing share of its actual audience, which is a real product loss that will be
relitigated"*; the second makes consent arrive *"by a legal inference from a money flow"* rather than the
person's own act.* **Silence → SAFE:** no consent for resale buyers.
Blocks: nothing — *"the recommended design ships either way"*; it gates CRM §11.1 element 28 only.
Filed at: CRM §13 `D-1` + §5.5 · AMEND §14.2-G `OD-43`. Owner **and counsel**.
Recommendation — yes: *"**Recommended answer: no consent by default, and put the same unchecked opt-in on the
native resale checkout, naming the org whose event it is.**"*

### ODR-108 — Acknowledge that consent withdrawal is a state change, not a hard delete
**Status.** OPEN — OWNER.
Accept the divergence from the demographics spec (which hard-deletes a withdrawn answer), or align them.
*Hard-deleting the consent record *"destroys the person's own evidence along with the platform's"* in the
dispute *"this venue emailed me and I never agreed"*, and removes the as-of evaluability the `gate_as_of` fix
and the replay property depend on.* **Silence → SAFE:** as designed.
Blocks: nothing. Filed at: CRM §13 `D-4` + §5.3 · AMEND §14.2-G `OD-44`. Owner and counsel.
Recommendation — yes: *"Adopt — a consent record is evidence about a relationship, and it is the person's own
evidence in the dispute they are most likely to have."*

### ODR-109 — Confirm the attendee-lookup limit numbers
**Status.** OPEN — OWNER.
Confirm `email_exact` 40/actor + 120/org per 24 h, `name_prefix` 20 + 60, `order_ref` 200 + 600, the
`attendee_list_page` limits, the 3-character minimum and `ambiguous_query` carrying no rows and no count — or
change the numbers. *Too loose and *"Iterating `a…z`, then `aa…zz` … returns the roster **one record at a time
at no rate cost** — the printed list §3.1 refuses, reassembled from the surface that was supposed to replace
it, by the exact role that was denied it."* Too tight and *"charging for a rejected call would turn the limiter
into a denial-of-service against the box office."** **Silence → SAFE:** the stated numbers ship, seeded in
`087` and read live so a limit can be tightened without a deploy.
Blocks: nothing. Filed at: CRM §13 `D-5` + §7.1/§7.2/§7.2a · AMEND §14.2-G `OD-45`.
Recommendation — yes, on the shape and not the numbers: *"The *shape* … should not change; the **numbers** are
a judgement the owner should own, because these are the sharpest anti-harvest controls in the document."*

### ODR-110 — Does an operator ever need a printed door list?
**Status.** OPEN — OWNER.
No (today's answer: one-at-a-time lookup), or yes with its own template and retention. *Yes → *"a printed list
is an unaudited export with none of §6's controls and a longer life than any of them."* No → *"**a box office
cannot print a paper list.** That is deliberate"* — a real 9 p.m. operational loss.* **Silence → SAFE:** the
denial stands.
Blocks: nothing. Filed at: CRM §13 `D-11` + §3.1 · AMEND §14.2-G `OD-47`.
Recommendation — yes: *"Today 'no' … A yes needs its own template, retention, and an honest note that print has
none of §6's controls."*

### ODR-111 — Confirm that no demographic-based send exists, in any form
**Status.** OPEN — OWNER.
Confirm the absence, or build one. *Any send is a new egress and contradicts `C40`; *"a `crm-export-deliver`
function emailing the CSV … puts the file in an inbox that outlives every control here."* The only admissible
future form is a **platform-side send** — *"the segment resolves inside Snatch It, the message goes out, and
the membership list never leaves."** **Silence → SAFE:** *"Not built, not designed, not stubbed."*
Blocks: nothing. Filed at: DEMOG §14 `D-4` + §9 `X-8` · CRM §13 `D-9` + §2.4 · AMEND §14.2-C `OD-22`.
Recommendation — yes: *"Stays closed; recorded so the absence is a decision, not a gap."*

### ODR-112 — Sub-promoters or sub-codes with a split commission?
**Status.** OPEN — OWNER.
Build a hierarchy, or not in Phase 2. *A split is a money change — two payees per attribution — which *"breaks
the one-payee-per-attribution shape in §4.3 step 2"*, the proof step that derives "at most one payout per
attribution."* **Silence → SAFE:** not built. Note DA §7.2 does mention promoter sub-links *"where allowed."*
Blocks: nothing. Filed at: PROMO §13 `OWNER DECISION 8` + §1.10 · AMEND §14.2-F `OD-40`.
Recommendation — yes: *"Not in Phase 2 — two payees per attribution breaks the one-payee shape."*

### ODR-113 — Code-enumeration thresholds
**Status.** OPEN — OWNER.
Confirm 30 `not_applicable` results from one principal in 5 minutes as the burst-audit trigger, or change it.
*Too tight *"locks out legitimate buyers who mistype"*; too loose widens the enumeration budget the §9.3
arithmetic depends on.* **Silence → SAFE:** the seeded value ships, tunable via config.
Blocks: nothing. Filed at: PROMO §13 `OWNER DECISION 10` + §9.4 · AMEND §14.2-F `OD-42`.
Recommendation — yes: *"Starting value, tunable via config; needs a real traffic baseline."*

### ODR-114 — Migrate the 12 legacy inbox types into the registry, or leave them alongside?
**Status.** OPEN — OWNER.
**Silence → SAFE:** left alongside. Blocks: nothing.
Filed at: NOTIF §10 `O-N10` + §2.6/§3.7 · AMEND §14.2-H `OD-54`.
Recommendation — yes: *"Leave them; register as `legacy=true`; do not touch working producers."*

### ODR-115 — Quiet hours · the `security_email_changed` mirror sweep · the promoter digest
**Status.** OPEN — OWNER.
Three deferrals bundled by the scope amendment. *Quiet hours are additive later via
`notify.delivery.next_attempt_at`; the mirror sweep was refused on evidence and *"the sound path is named there
and should be built deliberately, not assumed"*; the promoter digest matters because *"a working promoter
generates hundreds of these, and default-on per-order pings are a self-inflicted spam incident."** **Silence →
SAFE:** none in MVP.
Blocks: nothing. Filed at: NOTIF §10 `O-N12`, `O-N13`, `O-N14` · AMEND §14.2-H `OD-56` (first three limbs).
Recommendation — yes: *"First three: not in MVP."*

### ODR-116 — Rotating barcodes later? Google Wallet?
**Status.** OPEN — OWNER.
Adopt SafeTix-class rotating barcodes, or decline; add Google Wallet, or leave it out of scope. *Rotating
barcodes *"would add device-clock coupling and a new offline failure mode"* in exchange for *"a property
already held"* — currency is checked by `credential_version` plus M2, online **and** offline. Google Wallet
*"needs its own key custody, format, and review."** **Silence → SAFE:** neither is built.
Blocks: nothing. Filed at: WALLET §15 `OQ-W9`, `OQ-W10` + §1.2 · AMEND §14.2-D `OD-29`.
Recommendation — yes: *"Deferred; Google Wallet revisited after Apple ships and is measured."*

### ODR-117 — Δ6: `catalog.event.announce_at` / `on_sale_at` for a scheduled on-sale
**Status.** OPEN — OWNER.
Add the two nullable timestamps plus a sweep, or not. **Silence → SAFE:** VD §7.4 degrades.
Blocks: nothing. Filed at: VD §21 Δ6 · AMEND §14.2-J `OD-70`.
Recommendation — yes, with a boundary: *"Two nullable timestamps plus a sweep. **Explicitly not a virtual queue
or bot defence (C44)**."*

### ODR-118 — Δ7: `venue.ticket_type` sale windows and per-order min/max
**Status.** OPEN — OWNER.
Add them, or not. *Without them *"'Tables sell 1 per order' is currently unexpressible."** **Silence → SAFE:**
VD §8.6 degrades. Blocks: nothing.
Filed at: VD Δ7 · AMEND §14.2-J `OD-71`. Recommendation — yes, implicitly, on that argument.

### ODR-119 — Δ8: event-scoped, auto-expiring staff grants
**Status.** OPEN — OWNER.
Add `venue.staff_role.event_id` and `expires_at` with a sweep, or not. *This is also the **open half** of door
`OQ-3`: *"'box_office does not inherit' is true of the label and of the enum, and can still be false of the
human, through a `venue_manager` grant issued for an unrelated reason."* `O-2` raised the urgency — a one-night
box-office lead gets a permanent venue-wide grant that carries `O-4` manifest authority.* **Silence → the
over-provisioning stands**, partially mitigated by the `AUTHZ-M7` tier guard at `ODR-43`.
Blocks: nothing; VD §15.3 degrades. Pre-cleared as additive.
Filed at: VD Δ8 · DOOR §16 `OQ-3` (open half; the enum half is closed — see the settled section) · ROLE_MODEL
§11.3 `S-6` + §12 row 25 · AMEND §14.2-J `OD-72`.
Recommendation — yes: *"**Urgency raised by O-2**: a one-night `venue_box_office` lead now gets a permanent
venue-wide grant."*

### ODR-120 — Δ9: `venue.guest_list.promoter_id`
**Status.** OPEN — OWNER.
Add it, or keep string matching. **Silence → SAFE.** Blocks: nothing.
Filed at: VD Δ9 · AMEND §14.2-J `OD-73`. Recommendation: *"Low priority; today it is string matching."*

### ODR-121 — Δ10: org and venue `brand_logo_ref`
**Status.** OPEN — OWNER.
Add them, or drop the delta. **Silence → SAFE:** VD §16.4's honest *"not available yet"* stands.
Blocks: nothing. Filed at: VD Δ10 · AMEND §14.2-J `OD-74`.
Recommendation — yes, conditionally: *"Only if venue branding is a product commitment; otherwise drop the
delta."*

### ODR-122 — Retain `venue_finance`, and do not rename `org_member` → `org_affiliate`
**Status.** OPEN — OWNER.
Two role-model questions the scope amendment merges. *Deleting `venue_finance` — a label `O-2` does not list —
would break RLS §9.13 and §11, which depend on it, and would **silently close** the separate open question at
`ODR-26`. Renaming `org_member` ripples through six specs to fix a cosmetic collision already resolved by
naming the other concept (`kernel.is_org_affiliate`).* **Silence → SAFE:** retain and do not rename — both
already applied downstream.
Blocks: nothing today; the enums freeze when the venue-staff-roles package ships.
Filed at: ROLE_MODEL §13 `OD-1` and `OD-9` + §3.2 + §10 · AMEND §14.2-K `OD-81`.
Recommendation — yes: *"Retain (`RLS` §9.13/§11 both depend on it, and deleting it would silently close `RLS`
§15 item 3); do not rename."*

### ODR-123 — Break-glass for the door
**Status.** OPEN — OWNER.
Ship without a time-boxed audited break-glass grant, or add one. *Without: *"if `door_open_at` was mis-set and
no `venue_manager` is reachable, the door cannot open."* With: a new privilege-escalation path into an
`O-4`-restricted capability.* **Silence → SAFE, and safer than the row implies** — the door spec rules that
admission is **never** gated on manifest state, so the real cost is loss of *offline* scanning, not loss of
admission.
Blocks: nothing; operational risk only.
Filed at: ROLE_MODEL §13 `OD-8` + §8.2 · RLS §15.7 `MD-13` · DOOR §3.1 + §14 #10 + §14.5 · AMEND §14.2-A
`OD-10`.
Recommendation — yes: *"Ship without it — but the risk is real and should be seen here, not at 11 p.m."*

---

## Re-banded into this band at `269e473` — Band 4

---

### ODR-6 — What happens to the untracked `043_profiles_select_column_restriction.sql`
**Status.** OPEN — OWNER.
**Re-banded Band 1 → Band 4 at `269e473`.** The entry's own `Blocks` line has always read *"**Nothing
numbered**; it collides with the `076`–`091` reservation that `ODR-1` ratifies"* — and Band 1 means *nothing
downstream is safe to begin*, which is not true of this one. **Re-verified at head, not inferred:** the file
is untracked and lives on `mobile/profile-rpc-compat`; `git ls-files supabase/migrations` returns **89**
paths on `phase2/consolidation` and **none of them is `043_*`**; and
`_governance/PHASE_2_PREIMPLEMENTATION_CLOSEOUT.md` §9 — the sole filing site — heads its own list *"Owner
actions (exact blockers for the next stage — **none blocks *authoring* `076`**)"*. **The hazard is real and
the band was wrong**; nothing about the question itself has changed. Entry preserved verbatim below.

**The question.** Renumber the untracked migration file on `mobile/profile-rpc-compat` above the applied
maximum `075` **without** colliding with the reserved `076`–`091` Phase-2 band, fold it into another
migration, or delete it?

**What breaks under each.** *Renumber into the band* — it consumes a number the registry has reserved and
falsifies the sixteen-package assertion `ODR-1` is being asked to ratify. *Leave it as `043`* — the closeout
calls it a **back-dated-version hazard**: a migration numbered below the applied maximum, sitting in a tree
whose migrations guard asserts monotonic ordering. *Fold or delete* — the column restriction it carries has to
go somewhere or be abandoned.

**Which way silence falls.** The file sits untracked at `043` and the hazard stands. **UNSAFE** in the narrow
sense that the next person to run the migration tooling meets a numbering conflict rather than a decision.

**Blocks.** Nothing numbered; it collides with the `076`–`091` reservation that `ODR-1` ratifies.

**Filing sites.** `_governance/PHASE_2_PREIMPLEMENTATION_CLOSEOUT.md` §9 item 2.

**Does the corpus recommend?** **No.** The closeout states the three options and the hazard and stops.

---

## Added at `269e473` — Band 4

---

### ODR-124 — `O18`: is the traceability matrix under the freeze's Rule 1, or deliberately outside it?
**Status.** OPEN — OWNER. **And it arrives carrying a contradiction — read the box below before ruling it.**
**Choice.** As record row `O18` states them. **(a) COVER THEM** — add `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md`
and `PHASE_2_SCOPE_AMENDMENT_2026_08.md` to `ARCHITECTURE_FREEZE.md`'s covered-document list, *"which puts
every future edit behind a ratified correction ID, and accept that a derived register then cannot be rebuilt
without an amendment"*. **(b) DECLARE THEM DERIVED** — *"state in the freeze that they are **rebuildable
registers** whose authority is always the document they mirror (RLS §16.10/§16.11, RPC §18, the schema spec),
so a rebuild is maintenance rather than amendment — which is closer to how `C84` already describes the
matrix's *"at this baseline"* vocabulary."*
**Breaks.** *(a)* freezes two registers whose whole value is being regenerable; a rebuild after any upstream
edit then needs an amendment of its own. *(b)* leaves two documents that other covered documents cite by name
outside Rule 1 — the exact defect `C126` was raised against for the matrix, which *"was treated as authority
while sitting outside Rule 1."*

> ### THE CONTRADICTION, STATED BEFORE THE RULING IS ASKED FOR
>
> **Form (a) has already been executed — by a ratified row, without an owner ruling, and `O18` itself says a
> pass may not do that.**
>
> `O18`'s own premise reads: *"`ARCHITECTURE_FREEZE.md`'s covered-document list **does not name it** — nor
> `PHASE_2_SCOPE_AMENDMENT_2026_08.md` — **so neither is under Rule 1**"*, and its closing clause reads:
> *"**Not decided here, and NOT decidable here**: adding a document to the covered set is itself an act of
> the freeze, requiring owner approval under Rule 1, so a pass that added itself to the list would be the
> exact silent edit Rule 1 forbids. **`ARCHITECTURE_FREEZE.md` is therefore untouched by this pass.**"*
>
> **But ratified `C126` (the `R4` pass, rows `C126`/`D33`) had already added both** — by name, with their
> tier, plus `_governance/PHASE_2_PREIMPLEMENTATION_CLOSEOUT.md` and `_governance/GUARD_RESTORATION_PATCH.md`,
> and then this register as a fifth. `ARCHITECTURE_FREEZE.md` at `269e473` names all five.
>
> **The two passes did not collide by accident.** The `R3` pass that opened `O18` states it re-checked against
> the merged tip: *"`O17`/`O18` and `RET-*` were **re-checked against `901dfef`** and are free there"* — but
> it re-checked the **ids**, not the **premise**, and `901dfef` is the `R4` merge that carried `C126`.
>
> **So the live question is narrower than the row states, and it is sharper.** It is no longer *choose (a) or
> (b)*. It is: **ratify `C126`'s coverage act, or reverse it in favour of (b)** — and either way, decide
> whether a pass may extend the covered set on its own, because one just did. **This register takes no side
> and closes nothing.**

**Silence.** **UNSAFE, and it is already drifting.** `ARCHITECTURE_FREEZE.md` states its own re-check rule —
*"The covered set is now **37 of 37** files under `docs/architecture/`, and **that equality is the check to
re-run whenever a document is added** — `find docs/architecture -name '*.md' | wc -l` against the count of
paths named in this section."* **At `269e473` that command returns 39, and the two unnamed files are
`_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` and `_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md`**
— the NO-GO decision record and the owner's own decision brief, the two documents most likely to be cited as
authority, both outside Rule 1. The freeze's own note that *"the rule earned itself immediately"* is true and
it has now failed on its second use. Carried as **`DF-34`**.
**Blocks.** Nothing numbered; no package, no surface, no flag. **Band 4.** The record's own columns say the
same: gate `—`, MVP-must-implement `NO (governance)`.
**Filed at.** Record row **`O18`** and `D35`(d) · `ARCHITECTURE_FREEZE.md` covered-document list and its
maintenance note · matrix §0.1/§14 · ratified `C84` (the matrix has *"no mechanism that fails when its
baseline goes stale"*) · ratified `C126`/`D33`.
**Does the corpus recommend?** **No, explicitly.** `O18`: *"Two admissible forms, **both legitimate** … Not
decided here, and NOT decidable here."* `D35`(d) repeats it: *"Nothing was decided that belonged to the
owner: `O17` (`MD-2`) and `O18` (freeze coverage) are recorded and left."*
**Note for whoever rules it.** `C126`'s reading rule for a covered register is already written and survives
either form: *"its content is **derived**, so on any disagreement the owning document governs and the register
is corrected, never the reverse."* Form (b) is that sentence promoted from a row to the freeze; form (a) is
that sentence plus an amendment gate on top of it.


---

# APPEARS OPEN — IS IN FACT SETTLED

**Twenty-six rows** below still read as open in the document that raised them, but a later ratified row,
ruling or spec **already answered them**. **The enumeration, because the count alone is what this corpus keeps
getting wrong: 21 rows in table A + 5 rows in table B = 26.** Several rows bundle a set (four dashboard
deltas, five dashboard collisions, three RLS requests, seven RN items, five edge items, six schema and RPC
filings, two risk-register questions), so the rows cover far more than twenty-six filings. They are **not
entries in this register**, they are not counted in its total, and **this file does not close them** —
closing a row is an act in the ratification record and that is the owner's. Each row carries the evidence a
bookkeeping close would cite.

**Ten rows are new at `269e473`** — five in table A, marked **NEW**, and **all five of table B, which is a new
section**. They are the discharge trail of the six 2026-08-28 remediation passes, and they are here for one
reason: **a filing that was answered and never marked answered is indistinguishable, to the next reader, from
one that was not.**

## A — owner-facing rows

| Reads open at | The question | Already settled by | Evidence |
|---|---|---|---|
| ROLE_MODEL §13 `OD-2` (and §12 row 2, *"remains the owner's to confirm"*) | `venue_door` → `venue_scanner`: nominative or descriptive? | **`O-2`** | AMEND §14.1: *"**Closed, and listed so nobody re-opens them:** `ROLE` OD-2 (`venue_scanner` rename) … closed by **O-2**"*. Applied corpus-wide, and **finished at `269e473`**: ratified `C123` swept the last sixteen live sites across four delta specs, and *"every surviving `venue_door` string in the corpus is either the package name `086_venue_door_and_scan` or a correction block naming the label as abolished."* |
| ROLE_MODEL §13 `OD-3`, cell §5.3 `B1` left `⚠` | `set_org_payout_destination`: `org_owner` only, or owner + finance? | **`O-3`** | AMEND §14.1: *"`ROLE` … OD-3 (`set_org_payout_destination`) — closed by O-2/**O-3**"*. `O-3` rules it explicitly: *"**Payout destination change is `org_owner` ONLY** (`org_finance` excluded)"*, with the permanent requester-vs-setter split, destination probation and out-of-band notification as its compensating controls. **The `⚠` in §5.3 `B1` is stale, not open.** |
| ROLE_MODEL §13 `OD-6` | Role columns as native enum or `text` + `CHECK`? | **SCHEMA §12.3**, adopted downstream | AMEND §14.1: *"`ROLE` OD-6 (`text` + CHECK) — closed by `SCHEMA` §12.3"*. `T-SCHEMA-ROLE-02` asserts `pg_type.typtype='e'` returns **zero** rows across the four Phase-2 schemas, and ratified `C132` leans on the same fact. ROLE_MODEL's own row says *"**STATUS: ADOPTED downstream.**"* |
| ROLE_MODEL §13 `OD-10` | How does Phase-2 package numbering reconcile with the repo? | **`PHASE_2_PACKAGE_REGISTRY.md` §2/§4** | The registry is canonical: `071`–`075` are applied production migrations, Phase-2 occupies `076`–`091`, and *"arithmetic alone is not safe — decode by **package identity**."* |
| NOTIF §10 `O-N7` / §1.8 `CONFLICT-3` | At what number does Phase 2 begin? | **the registry**, plus the plan's own rule | `076`+ is forced: `071`–`075` are applied and the plan's rule says an applied migration may never be renumbered. |
| DOOR §16 `OQ-3`, **enum half only** | Does the venue enum need a fifth label for box office? | **`O-2`** / `DL-X2` | Door's own restatement: *"**The canonical venue enum is six labels and `venue_box_office` is one of them** … and RLS §11.4 **already excludes it** … that half needs no owner call and **must not be re-litigated as one**."* The surviving half is `ODR-119`. **Note the mis-citation:** AMEND §14.1 lists *"`DOOR` OQ-3 (`box_office` label) — superseded by O-2"* as **fully** closed; door §16 closes only the enum half. See `DF-40`. |
| DOOR §16 `OQ-7`, part (b) | The `door-manifest` auth model and the PIN route | **the door spec itself**, `EDGE-2` / `AUTHZ-H3` | *"**Resolved: `door-manifest` is a single staff-JWT route at `verify_jwt: true`, and the PIN route is DELETED**"* — the PIN check was satisfiable by *any* live PIN for that session, including one issued to a different device. Marked `OWNER DECISION — RECORDED, NOT MADE`; the ratification *"removes an authorization surface and adds none."* Part (a) — whether M2 is signed — is still open at `ODR-22`. |
| PROMO §14.1 | Package numbering in the promoter spec | **ratification `X-02`** | Re-titled **CLOSED BY RATIFICATION** (2026-08-28); *"no longer owed to anyone."* Corrections `X-01`…`X-04` moved `venue.settlement` to `087` etc. |
| PROMO §14.2 — **NEW** | Is a promoter modelled as venue staff, against `O-2`? | **`O-2`**, applied by ratified **`C123`**/`D32` | Marked **RESOLVED** in place, with the `VERIFIED:` badge over *"exactly four labels"* struck. `C123` records this as the worst site in the corpus, *"since it is a stated enum an implementer would author DDL from."* Its onward owner assignment is stamped `DISCHARGED`. |
| EDGE §9 item 11(a) | *"`venue.settlement` mapped `086` by promoter §0.3 vs `087`"* | **`X-01`, 2026-08-28** | Promoter §0.3 was corrected to `087`. The edge spec's *"the promoter spec is stale"* is itself now stale. |
| EDGE §9 items 1, 6, 13 (and 9, 17 in part) — **NEW** | Five edge-spec open questions | **`R6`/obs-1 · addenda A2/A3 · `EDGE-4` · `EDGE-2`** | Item 1 (`public.payments` ↔ native linkage) **RESOLVED**; item 6 (door-freeze canonical helper) **CLOSED**; item 13 (`venue.door_session` H-3) **CLOSED — "All five requests answered"**; items 9 and 17 **RESOLVED (`EDGE-2`)** with named residuals reported to the door-spec, CRM and registry owners. |
| RN §12 items 1, 2, 3, 4, 5, 6, 8 — **NEW** | Seven React-Native open questions | **the corpus + addenda A2/A3/A5** | All seven are marked **RESOLVED** in place at head. The four that remain open are items 9, 10, 11 and 12 — of which item 12 is `ODR-87` and item 9 is `ODR-68`. Item 7 (waitlist / friends-going) carries **no status word at all** and is a *"flagged so reviewers don't expect a home"* note, not a decision. |
| MONEY §6.7a conflict 1 | Immature-grant failure code: `sod_violation` or `precondition_failed('money_role_too_new')`? | **SCHEMA §13.7 `S-3(a)` / record `D16`** | *"the error is **`sod_violation`** … Recorded as ratification **D16**."* **Two sites still carry the losing code at `269e473`** — MONEY §6.7a and SCHEMA §1.13.4 — see `DF-14`. |
| VD §21 Δ1, Δ2, Δ3 (partly), Δ4 | Four dashboard column/RPC asks | **`O-4`, `AUTHZ-H10`, and the RPC contracts** | VD §21.0 marks each *"SATISFIED"*. Δ3's third RPC survives as `ODR-92`. |
| VD §21 Δ5 | `catalog.event` marketing fields | **ROLE_MODEL §11.3 `S-5`**, applied in `078` | AMEND §14.1: *"`VD` Δ5 — satisfied by `ROLE` S-5's marketing columns in `078`."* **And the two documents disagree at head:** VD §21.0 still reads *"Δ5–Δ10 — OPEN, unchanged."* One of the two is wrong; the AMEND row carries the evidence and VD carries the status. See `DF-40`. |
| VD §22.1, §22.2, §22.3, §22.4, §22.7 | Five dashboard-vs-spec collisions | **`O-1` … `O-4`** | AMEND §14.1 lists all five as closed by the owner rulings; VD marks each **RESOLVED** in place. |
| VD §22.6 | Platform read vs venue CRM export | **CRM `K-3`** | AMEND §14.1; VD §22.6 is marked RESOLVED in place. The remaining *question* — whether a platform bulk path is wanted at all — is `ODR-62`. |
| VD §22.9 | A CRM collision (attendee display-name source) | **CRM `K-5`** | AMEND §14.1; VD marks it RESOLVED. |
| CRM §14 `K-3`, `K-4`, `K-5` — **NEW** | Three CRM corrections that read as live findings | **the CRM spec itself** | Each is stamped **Resolved** / **Conflict resolved** in place. `K-11`, `K-12` and `K-13` additionally record *"no constitution edit"* / *"no edit requested"*, i.e. deliberate non-actions rather than pending ones. |
| DEMOG §16 `J-1` — **NEW** | VD §9.5's `UNVERIFIED` note on the mix card | **the demographics spec** | Stamped **Resolved**. `J-6` likewise records *"no constitution edit"* as a closed non-action. |
| Risk register `O1` and `O5` | Cancellation refund liability + reserve; cross-rail seat-identity dedup key | **`C29`** and **`C17`** | Risk register: `O1` *"Reframed as R4/C29"*; `O5` *"Reframed as C17 (external-seat-reference)"*. `O5` leaves a **verification** owed, not a decision. |

## B — integrator rows discharged since `32249f2` (**NEW section**)

These are not the owner's and never were. They are here because five of them were **filed and never applied**
for a full remediation cycle, which is the defect class the `R1` pass exists for — and because a discharged
filing that still reads live is how the next reviewer re-files it.

| Reads open at | Discharged by | Evidence |
|---|---|---|
| RLS §17 `X-10`, `X-11`, `X-12` | **the schema pass**, extended 2026-08-28 by `AUTHZ-C1C` | Each is struck through and marked DONE in the same table, and RLS §15.7 states *"`X-10`, `X-11` and `X-12` are DISCHARGED"*. **Each also still appears once as a bold, live-looking row, physically above its own struck copy** — see `DF-9`. |
| RPC §20.14 `R-1`, `R-2`, `R-3`, `R-4`, `R-16`, `R-17`, `R-18` | RLS §11 and the schema pass | All seven are struck and marked DONE. **`R-16`, `R-17` and `R-18` also still appear as live bold rows** — the `X-10`/`X-11`/`X-12` defect in a second register. See `DF-32`. |
| Schema §13.7 `S-15`, `S-16`, `S-17`, `S-18`, `S-22` and RPC §20.14 `R-27` | **the `R1` unapplied-filings pass** — ratified `C99`, `C104`, `C105`, `C106`, `C107`, `C109` | The `R1` pass found the same defect eleven times: *"a repair was **filed** … and never **applied**, so the corpus carried a request where it needed a column or a contract."* **`R-27` is marked APPLIED in schema §13.7a's discharge ledger and is still carried un-struck in RPC §20.14** — see `DF-32`. |
| Schema §13.7 `S-3` | **`AUTHZ-C1C`** — marked ✅ **DISCHARGED IN PART** | The venue-plane half landed; the **platform-plane half is the live open decision `ODR-36`** (`C77`/`O12`/`R-22`b), which is why the row is *in part* and not closed. |
| ROLE_MODEL §11.2 `R-18` | **ratified `C122`/`D31`** | The predicate-helper count that the corpus stated **four different ways** across five statements (eight, nine, nine, eleven) is settled at **ten**, enumerated by name, and the row is stamped ✅ **DISCHARGED**. *"the RLS owner never picked a number; the corpus stopped using one"* (`HELPER-DERIVED` clause 4). **RLS §16.10a `OPEN-2` still says nine** — see `DF-22`. |


---

# NOT THE FOUNDER'S — DEFECTS WEARING A DECISION'S CLOTHES

**Forty-one rows.** These are filed in decision-shaped registers, or cited as open questions, but they have
**one correct answer**. Ruling on them as if they were preferences risks ratifying a bug. They are **not
counted in this register's total**, and none should be put in front of the founder as a choice.

**Every row from the previous edition was re-verified at `269e473`** and carries the result. **Two are
RESOLVED**, **two are PARTLY RESOLVED**, and **eleven are new** (`DF-31` … `DF-41`), of which four are new
staleness created by the very passes that repaired the old staleness.

| # | Item | Where | Why it is a defect, not a decision | At `269e473` |
|---|---|---|---|---|
| **DF-1** | **`R-22` is used twice in RPC §20.14** for two unrelated items — the benign 30-second clock-skew confirmation (`ODR-82`) and the live money-plane authority hole (`ODR-36`) | RPC §20.14, self-reported as `R-26` | The row names its own answer: renumber the `MP-1` row, **never** the `C77`/`O12` row, which is cited externally by schema `S-3` and RLS §11.3a. A founder handed *"R-22"* gets an ambiguous ask. | **STANDS** — both rows present and un-renumbered |
| **DF-2** | **`OD-n` and `OD-nn` are two different series distinguished only by a leading zero** — ROLE_MODEL §13 `OD-1`…`OD-11` and AMEND §14.2 `OD-01`…`OD-81`, cited side by side in the same file | ROLE_MODEL §13 · AMEND §14.2 | It has already produced a mis-citation: AMEND `X-13` records that CRM `D-7` points at `ROLE OD-8` (door break-glass) where it means ROLE_MODEL §5 `H2`/`H3`. One correct fix (prefix one series); no owner preference. | **STANDS** |
| **DF-3** | **`S-1`…`S-6` mean different things in the schema spec and the role model**, and one citation is bare *and* mislabelled | SCHEMA §13.7 · ROLE_MODEL §11.3/§11.7 | ROLE_MODEL flags it itself: *"`S-5` here is the `catalog.event` marketing columns; `S-5` there is the `assert_door_session` token parameter — **the two most consequential rows in this pass, sharing an id**."* Worst instance: schema §1.12.1 cites *"**ratification `S-6`**"* — which names no ratification row at all. The proposed fix (`RM-S-1` etc.) is *"filed, not performed"*. | **STANDS**, and worse: schema §13.7 now runs to **`S-27`** while ROLE_MODEL §11.3 still stops at `S-6` |
| **DF-4** | **`D-3` means two different things**, and the schema spec writes its own bare | MONEY §11 `D-3` (threshold values) · SCHEMA §1.15.2 `D-3` (the cascade sign-off) | Inside the schema spec, `D-1` and `D-2` are qualified as *"(MONEY §11)"* and `D-3` is not — so a reader carries the money series into a row that means the CRM one. | **STANDS** |
| **DF-5** | **The `O1`…`O8` range claim is wrong, in three documents** | Record's Statuses block and row `D4` · `ARCHITECTURE_FREEZE.md` · DA §0.4 note | The unhyphenated architecture open-question series is `O1`…`O6` (the risk register enumerates exactly those). `O7` and `O8` are the **record's own** open decisions. As written, the disambiguation note asserts that the record's `O7`/`O8` are DA §0.4 open questions. **The note that exists to prevent an id collision contains one.** | **STANDS** — the freeze's rewritten box at head still reads *"`O1`…`O8` **unhyphenated** are the architecture open questions … `O6`/`O7`/`O8` as above"* |
| **DF-6** | **`MD-11` has no row of its own** — it exists only as a sentence inside `MD-10`'s cell, with no Recommendation and no Blocks column | RLS §15.7 | And it is the **event outbox**, which the domain architecture calls *"the only new infrastructure Phase 2 introduces."* A register entry that is a clause inside another entry is one a reader skips. | **STANDS**, and it is **cited externally as a live id twice** by scope amendment `OD-13` |
| **DF-7** | **Four money config keys have no absent-key semantics** | SCHEMA §1.13.4 `FAIL-TO-SAFE (X-12)` covers `authn.money_role_maturity_hours`, `comp.per_staff_step_up_max_units`, `comp.per_staff_step_up_window_hours`, `refund.platform_support_max_minor` — and no others | `refund.org_auto_execute_max_minor`, `refund.org_dual_control_max_minor`, `refund.request_ttl_hours` and `refund.scanned_atom_policy` have **no stated absent-key rule anywhere**, while `X-12`'s own reasoning applies verbatim. `refund.request_ttl_hours` is the worst: *"**A hold with no sweep is a bricked ticket.**"* **Filed as neither a decision nor a defect anywhere in the corpus.** | **STANDS** |
| **DF-8** | **`ODR-89` carries a recommendation and `ODR-35` is required to carry none, yet they are the same question at two grains** | MONEY §11 `D-4` vs `D-8` | Answering `D-4` *"Keep"* and `D-8` *"Deny"* is internally incoherent — an `org_admin` who may read the settlement header (gross, fees, refunds, net) but not the refunds order list. **The register does not say so.** This register says so at both entries. | **STANDS** |
| **DF-9** | **`X-10`, `X-11` and `X-12` each appear twice in RLS §17** — once bold and live, once struck and DONE | RLS §17 | On a skim the bold rows read as open work, and they sit **above** their own struck copies. One correct fix: delete the superseded rows. | **STANDS** — 24 rows for 19 ids |
| **DF-10** | **`venue.door_session` has two divergent physical specifications** | SPEC_FOUNDATION §6 note; schema §3.10a vs edge §3.9a | Four disagreements at once: `assert_door_session`'s fourth argument; a `session_ref text UNIQUE` column the schema spec does not define; `revoked_at IS NULL` + partial index vs a `status` column; `UNIQUE(token_hash)` present in the plan and absent from the edge spec. *"Two specs of one table cannot both be built."* | **PARTLY RESOLVED** — edge §9 item 13 is now **CLOSED (`EDGE-4`)**, *"All five requests answered"*. The **selector** limb remains the genuine one-column choice `ODR-21`, and schema `S-5` (the token parameter) is still open |
| **DF-11** | **`catalog.platform_config` is still described as world-readable, in two places, after `C71` made it two-class** | MONEY §7.4 · SCHEMA §1.14 (in the same file whose §2.4.1 rules the opposite) · TRACE §10 (`TM-X2`) | This is the unsafe direction: telling an implementer that the table holding every dual-control ceiling, step-up window and export cap is world-readable is exactly the defect `C71` was raised against. It also invalidates the stated premise of `ODR-8`. | **STANDS** — verified at MONEY §7.4 and SCHEMA §1.14 at head |
| **DF-12** | **`R-19`'s `/refresh` half is bundled under an owner id but is a settled safety property** | RPC §20.14 `R-19`(b) · RLS `MD-19` · schema §3.10a.4 | *"its `/refresh` route is the property schema §3.10a.4 **deliberately refused**"* — a path that outlives the PIN. Bundling it with the selector spelling risks the founder "deciding" a closed safety property. | **STANDS** |
| **DF-13** | **One finding, two ids** — RPC §0.7a cites `R-24` where the `R-` register and §21 cite `R-25` for the `resale_state` writer-set finding | RPC §0.7a vs §20.14 / §21 | One of the three references is wrong. | **STANDS**, and both `R-24` and `R-25` are still listed as outstanding filings by Final Report §8 item 4 |
| **DF-14** | **The immature-grant error code is already ruled and two sites still propose the losing one** | Ruled `sod_violation` by SCHEMA §13.7 `S-3(a)` / record `D16`; still proposed as `precondition_failed('money_role_too_new')` at SCHEMA §1.13.4 and listed as an unresolved conflict at MONEY §6.7a | *"a control whose denial arrives under two different codes is a control whose alerting cannot be written."* One correct answer, already recorded; what remains is deleting the losing text twice. | **STANDS** — both sites verified at head |
| **DF-15** | **MONEY §12 still carries the `NO SCHEMA CHANGE` line that `S-14` proved false** | MONEY §12 vs SCHEMA §1.9.1 / `S-14` | *"`kernel.payout.status='held'` does not exist and is not being created"*, and the classification *"was false under **every** candidate repair — even adding a CHECK label is DDL."* `NO SCHEMA CHANGE` is what a migration author reads to decide a package needs no DDL. | **STANDS** — `S-14` was explicitly **not** discharged by `R1` and was re-filed as `R-33` |
| **DF-16** | **Wallet `OQ-W3` is a proof, not a choice** | WALLET §15 `OQ-W3` / §0.2 / §4.5 · `HG-1` | *"Without step 3b, Scenarios 2, 3 and 4 all **ADMIT**, and this document's central claim is false."* Only the **acknowledgement** is genuinely owed, which is why `ODR-48` is phrased as one. | **STANDS** |
| **DF-17** | **Door `OQ-4` / RLS `X-7` is a documentation defect wearing a confirmation** | DOOR §16 `OQ-4` · RLS §17 `X-7` · four sibling specs | The substance is that four specs describe a `C43` narrowing **nothing implements**, while `C43` is `RATIFIED-MODELED-ONLY(GATE-M)`. The correct action is a documentation fix; `ODR-68`'s confirmation is ceremony over it. Only the *"pull the narrowing into MVP"* limb is the owner's. | **STANDS** |
| **DF-18** | **`_governance/PHASE_2_FINAL_PREIMPLEMENTATION_GATE.md` §10 does not exist** — the file ends at §9, while §5 cites *"the sixth is §10 `GATE-1`"* and §9 cites *"recorded in §10 as `GATE-2`"* | that file | **Two owner-facing gate items were lost in a salvage.** `GATE-1` = one `public` function retaining PUBLIC EXECUTE; `GATE-2` = *"§5's dependency bullets for packages at `080`, `084` and `088` name more dependencies than §3 and §2 … a content discrepancy … needs an architecture decision."* The content is not recoverable from this file. **Recover it from the superseded PR #22 branch or re-derive it — and if `GATE-2` turns out to be a real fork, it becomes an entry in this register.** | **STANDS — re-verified mechanically.** The file is 376 lines; its last section heading is `## 9.`; `grep -n '^## '` returns no §10. Both dangling citations are still present, at the §5 drift table and at the §9 numbering paragraph. **Carried forward unchanged and still owed.** |
| **DF-19** | **Record row `C85` points at `O11` twice where it means `O13`** | record row `C85` | *"and `O11` below"* and *"until `O11` closes"* — but `O11` is delta-spec precedence and the decision `C85` raises is `O13`. The head-of-record enumeration was repaired at `32249f2`; **the row body was not.** | **RESOLVED at `269e473`.** Fixed by commit `f97f6cd` (*"repair the ratification record's self-description after the hand-merges"*). The row now reads *"and `O13` below"* and *"until `O13` closes"*. Verified by diffing `32249f2` against head. |
| **DF-20** | **`ARCHITECTURE_FREEZE.md` still says the record has "44 rows" and "three open decisions (O6, O7, O8)"** | `ARCHITECTURE_FREEZE.md` | The record's own table says 114 rows and eleven open decisions `O6`–`O16`. **This is the count-without-a-matching-enumeration failure the record has already been bitten by, surviving in the freeze document.** | **RESOLVED at `269e473`** by ratified `C125`/`D33` (`R4-6`), which recounted mechanically **with the enumeration beside every count** and added the rule *"on any disagreement the record is authority and the freeze is a convenience copy."* **And immediately re-stale — see `DF-35`.** |
| **DF-21** | **`G-14` still carries `venue.set_door_open_at` as an open gap** | TRACE `G-14` | Record `RET-6` names it: the two role-model instances were corrected by `D13`; *"**`G-14` is NOT, and is owed by the matrix owner.**"* `O-5` makes `catalog.engage_door_freeze` the sole writer, so the EXEC row is the defect, not the ruling. | **STANDS** — `G-14` at matrix §1 and §604 both still name it |
| **DF-22** | **RLS §16.10a `OPEN-2` says *"the set of nine is ratified"* while §2.2's `AUTHZ-C1C` — same document — establishes ten** | RLS §16.10a vs §2.2 | `OPEN-2` is written against the pre-`C58` membership. Related: role-model `R-18` recorded the helper count stated **four different ways** across five statements; *"One number must win before that test can be written."* | **PARTLY RESOLVED.** The `R-18` half is **DISCHARGED** by ratified `C122`/`D31`: the count is **ten**, enumerated by name, and *"the RLS owner never picked a number; the corpus stopped using one."* **RLS §16.10a `OPEN-2` still says nine at head** — the half that was never the role model's to fix |
| **DF-23** | **`G-25`: the event catalog says 36 events and ratified `C11` says *"~10 sync + ~6 real outbox events"*, and no document says which sixteen survive** | TRACE `G-25` / §8.3 | Ordinarily bookkeeping — except that **it corrupts the pricing of `ODR-2`**: *"an owner pricing the O7 ruling is reading a list that a ratified correction already reduced by more than half."* **Fix this before ruling on `ODR-2`.** | **STANDS**, and it is now the **first** of the brief's four *"prerequisites to close before ruling"*, priced at ~1 hour |
| **DF-24** | **`Δ-N1`: `catalog.event_session.session_version` is correctness-blocking** | NOTIF §10 cross-agent list | *"**Without it a venue that moves the door time twice cannot notify twice** — the second change collides with the first row's dedupe key and is silently swallowed by `ON CONFLICT DO NOTHING`."* One correct answer. | **STANDS — the COLUMN. The WRITER does not have one correct answer: re-classified in part 2026-08-29.** The writer-parity triage (`E-1`) found the corpus states two coherent opposites — RPC §20.2.4 lists `session_version` among the columns the session-update RPC **must never touch** (*"a monotone counter owned by the notification plane"*, under which reading it has ZERO writers and ships permanently `1`), while the schema spec says it is advanced **only by the session-update RPC in the same transaction** and argues the failure is silent by construction. **WHO BUMPS IT — updated 2026-08-29: DISSOLVED, not ruled.** Three independent proofs (sprint agent D): the notification plane's own catalog names `catalog.update_event_session` as the bumper; the never-touch list is operationalized as patch-key rejection only; and the ratified dedupe property is satisfiable ONLY by the in-txn bump. One admissible value ⇒ no owner bit existed; RPC §20.2.4's four-word parenthetical repaired, `catalog.event_session`'s registry row is OK, and this DF row is DISCHARGED. The additive column itself still rides `ODR-3` unchanged |
| **DF-25** | **`X-05`: `refund_hold` has no offline reject mapping** | AMEND §15 `X-05` · MONEY §12-2 vs DOOR §9.2 | *"A `refund_hold` atom would snapshot into the manifest with **no reject mapping and no defined offline behaviour**."* `086`'s CHECK must admit all four labels. The online twin is edge §9 item 14. | **STANDS** — edge §9 item 14 is still open |
| **DF-26** | **Promoter `OWNER DECISION 9` is not a decision** | PROMO §13 row 9 / §8.2 | *"**Only flagged so nobody implements it as an RLS permission.**"* It is a guard against an implementation mistake. **It is deliberately absent from this register.** | **STANDS** |
| **DF-27** | **Promoter §14.4, §14.5, §14.7 are three defects filed among contradictions** | PROMO §14 | §14.4: attribution written at order **creation** contradicts *"written when paid"*; record `D7` already ruled the constitutions right. §14.5: widening the idempotency key to `order_id` is *"strictly stronger"*. §14.7: *"A function defined in `087` cannot reference a table created in `090`; **the migration would fail to apply**."* | **PARTLY RESOLVED and EXTENDED.** §14.7 is **CORRECTED** by ratification `X-03` (*"every `086` was `087`"*); §14.4 and §14.5 stand. **Add §14.6** — *"`check_rate_limit` cannot limit an unauthenticated principal"* — a fourth defect in the same section, open, owned by the edge-spec author, and absent from the previous edition. **§14.3** (`venue.promoter` cannot express the flat-per-ticket / `tier` / `party_kind` terms DA §1.7 ratifies) is a fifth: record row `D8` already ruled the constitution right and owes the columns to the schema integrator |
| **DF-28** | **The twelve uncontracted RPCs and the ten unbacked dashboard controls are missing contracts, not choices** | TRACE `G-3`…`G-7`, `G-13`…`G-15`, `G-20`, `G-21`, `G-24` · VD §20A.3 `U-1`…`U-10` | *"the corpus contracted the functions a **product surface** demanded. It did not contract the functions an **authority table** granted."* `G-24` (no inventory-hold expiry sweep) is a plain correctness bug. **`ODR-72`…`ODR-78` are in this register anyway**, because the corpus's standing rule makes them owner-gated stop-ship guards — but the founder's act there is *"authorize the contract to be written"*, not *"choose between options"*. Say that when tabling them. | **STANDS, and the framing is now provable.** At head **all ten `U-n` controls have a contract in RPC §20** and RLS §11.1c accepts every one of their EXEC rows except `venue.get_dashboard_summary`, which is *"**DEFERRED, not accepted**"* precisely because `ODR-92` is undecided. The gap is scheduling, not authorship: RPC `R-7` files the same functions as **missing from plan §8's Functions rows** for `080`, `086`, `087`, `088` and `090` |
| **DF-29** | **Edge §9 items 12, 14, 15, 16 and RN §12 items 10 and 11** | EDGE §9 · RN §12 | A missing write path, a return shape missing `signing_key_id` and a `reason` enum missing `refund_hold`, a granted ruling's condition satisfied by no code path (*"the exact 'a correct thing that nothing called' failure class"*), four config namespaces missing from the dual-control set, a wrong section pointer, and two banner strings for one condition. One correct answer each. | **STANDS** — all six still open at head. Add **edge §9 items 8 and 10** (the `promoter-code-preview` env list, and the notification package numbers) as two more of the same kind, both routed to sibling spec owners |
| **DF-30** | **RLS §16.10a `OPEN-1` and the `GP-3 NOTE`** | RLS §16.10a | `OPEN-1`: *"**No document in the corpus defines 'tonight'**"* — a dangling grant in RLS §8.3, not a fork; the fail-closed omission has already de-facto answered it. `GP-3 NOTE`: the org arm of `kernel_tickets_sel_venue` should be split under `GP-3`'s own naming rule and is deferred only because splitting it *"would fail CI in a way that reads as a regression"* — a sequencing problem, not a judgement call. | **STANDS.** Note the shape defect: the `GP-3 NOTE` is styled identically to `OPEN-1`/`OPEN-2` and **is not numbered `OPEN-3`**, so a grep for the series misses it |
| **DF-31** — **NEW** | **`COND-D` is cited as a package-registry id and the package registry does not contain it** | `PHASE_2_PACKAGE_REGISTRY.md` §7 · `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` · this register's previous edition | Registry §7 opens *"**Three** items … Each requires an owner ruling"* and defines **`COND-A`, `COND-B`, `COND-C` only**. The `COND-D` coupling rule (*"outbox-out with `notify`-in is incoherent"*) exists in that file **as prose with no id**, and the id `COND-D` is minted in the traceability matrix. The previous edition of this register cited *"`COND-D`, stated in `PHASE_2_PACKAGE_REGISTRY.md` §7"* — which is where it is not. **A reader who greps registry §7 for four `COND-*` rows finds three and concludes one was lost.** The rule itself is sound and is quoted correctly at `ODR-3`; only its home is wrong. | **NEW** |
| **DF-32** — **NEW** | **The `X-10`/`X-11`/`X-12` duplicate-row defect exists a second time, in a second register** | RPC §20.14 | `R-16`, `R-17` and `R-18` each appear **twice** — once struck and DONE, once live and bold — exactly as `DF-9` describes for RLS §17. **And a third variant:** `R-27` is stamped **APPLIED** in schema §13.7a's discharge ledger (ratified `C99`) and is still carried **un-struck** in RPC §20.14. Final Report §8 item 4 states the general form: *"Note §20.14's status column is **unreliable in both directions**."* One correct fix per row. | **NEW** |
| **DF-33** — **NEW** | **RPC §19's item numbering restarts, so `17` and `18` each name two unrelated items** | RPC §19 | The section carries items 1–18, then a second block headed *"Additions from this reconciliation pass"* numbered 17, 18, 19, 20, 21. Item **18** in the second block is owner-facing (the `p_door_session_id` / `/refresh` rulings filed for confirmation, `ODR-21`); item **18** in the first block is not. A citation of *"RPC §19 item 18"* is ambiguous, and this is the same failure class as `DF-1` and `DF-2`. | **NEW** |
| **DF-34** — **NEW** | **`ARCHITECTURE_FREEZE.md` claims a covered set of "37 of 37" and the tree holds 39** | `ARCHITECTURE_FREEZE.md` covered-set section | The freeze states its own re-check — *"that equality is the check to re-run whenever a document is added — `find docs/architecture -name '*.md' \| wc -l` against the count of paths named in this section"* — and records that *"it has already caught one addition."* **At `269e473` the command returns 39 and two files are named nowhere in the freeze:** `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` (the NO-GO decision record) and `_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` (the owner's own decision brief). **Both are outside Rule 1**, both are already cited as authority, and both landed after `C126`. Bears directly on `ODR-124`. | **NEW** |
| **DF-35** — **NEW** | **The freeze's repaired decision inventory is stale again, one pass after it was repaired — the fourth generation of the same defect** | `ARCHITECTURE_FREEZE.md` · `_governance/CTO_DECISION_MEMO.md` | `C125` recounted it *"mechanically at `f97f6cd`"* and wrote **"Eleven distinct open decisions block a gate, and they are `O6` … `O16`"** with a row-by-row table. **`O17` and `O18` were opened by the `R3` pass and the freeze does not name either.** The correct figures at head are **thirteen** open decisions, `O6`…`O18`; `grep -oE 'OPEN-GATED\(O[0-9]+\)' \| sort -u \| wc -l` over the record returns **13**. `C125`'s own sentence — *"**This is the third time that paragraph has gone stale**"* — is now the fourth, and its own remedy names the cause: *"This document has **no mechanism that fails when these numbers go stale**."* The CTO memo carries the same defect one generation further back. | **NEW** |
| **DF-36** — **NEW** | **A ratified row executed one form of an open owner decision, and the pass that opened the decision did not notice** | ratified `C126`/`D33` vs record row `O18` | `O18` asks *"cover them, or declare them derived"* and states *"**NOT decidable here**: adding a document to the covered set is itself an act of the freeze, requiring owner approval under Rule 1."* **`C126` had already added both**, four commits earlier, on the tip the `O18` pass merged onto and re-checked against. The `R3` pass re-checked that the **ids** `O17`/`O18` were free at `901dfef`; it did not re-check the **premise**. **This is not a duplicate of `DF-35`** — that one is a stale count, this one is a decision recorded as open whose (a) branch is already built. Stated in full at `ODR-124`. | **NEW** |
| **DF-37** — **NEW** | **VD §22's preamble undercounts its own section by two** | `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §22 | The preamble reads *"**New:** §22.10–§22.14"* and *"Six of nine are closed"*, over a section that runs to **§22.16**. §22.15 (the cross-spec package-map conflict, a filing site for `ODR-1`) and §22.16 (notification objects have no migration package, a filing site for `ODR-3`) are **outside the preamble's own range**, so a reader working the preamble misses two open rows — both of which point at Band-1 decisions. Count-without-enumeration again, in a sixth document. | **NEW** |
| **DF-38** — **NEW** | **Nine register rows reach no consolidated index, and one of them is a hard gate** | `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2 | The corpus's own consolidated owner-decision index (`OD-01`…`OD-81`) does not reach: **MONEY `D-9`** and **`D-10`** (the `MB-1`/`MB-1b` additions — `D-10` is `O14`, a **blocking** decision), **DEMOG `D-12`, `D-13`, `D-14`**, **CRM `D-12`, `D-13`**. **MONEY `D-8` is never cited by id at all** — `OD-05` carries its substance sourced only to VD §22.13, and `D-8` is the one row two specs mark BLOCKING. **CRM `D-2` has no `OD-` id** and appears only inside `HG-4` — *a hard gate with no entry in the decision index.* The per-feature map at §14 additionally still says demographics raises *"`D-1`…`D-11`"*, which was true before `D-12`–`D-14` existed. **This is why this register exists**, and it is filed as a defect because the index has one correct state and is not in it. | **NEW** |
| **DF-39** — **NEW** | **`HG-4`'s deadline is eleven packages late, in four documents, after the artifact moved** | AMEND §11 `HG-4` · CRM §13 `D-2` · RLS §15.7 `MD-2` · record row `O17` | All four say the Layer-0 decision must be made *"before `087`"*. Ratified `C115` moved `CREATE ROLE crm_export_builder NOLOGIN` to **`076`** under `SEAM-4`, and put the first grant in `076`. The brief names the fix as its second prerequisite: *"Correct the `HG-4` deadline from `087` to `076` in three documents"*, and lists *"correct the `HG-4` deadline from 087 to 076"* as item 9 of what a Layer-0 adoption would have required. **`ODR-23` has since been ruled B, so the deadline is moot for the ruling — but not for the discharge**, and a reader meeting `HG-4` without this register will schedule it eleven packages late. **This is the defect that mis-banded `ODR-23`.** | **NEW** |
| **DF-40** — **NEW** | **Two closure claims in `AMEND` §14.1 are wider than the rows they close** | AMEND §14.1 vs DOOR §16 `OQ-3` and VD §21.0 | §14.1 lists *"`DOOR` OQ-3 (`box_office` label) — superseded by `O-2`"* as closed; door §16 `OQ-3` at head closes only the **enum-label half** and states the **grant-hygiene half is still open** (*"Owner call"*) — that half is `ODR-119` and `ODR-46`. §14.1 also lists *"`VD` Δ5 — satisfied by `ROLE` `S-5`"*; **VD §21.0 at head still reads *"Δ5–Δ10 — OPEN, unchanged"***, and Δ5 alone among Δ5–Δ10 has no `OD-` id. **A closure claim wider than its row is how a live decision disappears**, which is exactly the failure `RET-1`…`RET-6` exist for. One correct answer each. | **NEW** |
| **DF-41** — **NEW** | **The seventh amendment's correction ids appear in two documents and in zero of the five an implementer builds from** | plan · registry vs schema spec · RPC contracts · RLS spec · door spec · money spec | Final Report §6's decisive measurement, reproduced: `R2B` correction-id occurrences are **54** in the migration plan, **52** in the package registry, and **0** in the physical schema spec, the RPC contracts, the RLS permission spec, the door spec and the money spec. **The mirror image also holds** — `kernel.mark_refund_state`, sole writer of three `kernel.refund` statuses and of `stripe_refund_ref`, is contracted in the RPC and schema specs and appears **zero** times in the plan, the registry and the RLS spec. *"By the corpus's own rule, a contracted function absent from plan §8 is a function nobody builds."* **Three hook signatures are still in their pre-freeze form; under `SEAM-2a` that is a `42P13` hard replay failure, or a silent overload leaving the `C26` compensate arm dead in production.** It is the whole of Final Report §8 item 1, it is why the verdict is NO-GO, and **it is not an owner decision** — it is a transcription pass. | **NEW** |

# THE DEDUPLICATION LEDGER

**How two filings were established to be the same decision.** Four kinds of evidence were accepted, in this
order of strength. Nothing was merged on resemblance alone.

1. **The corpus says so.** One document names the other's id for the same question — *"= schema §13.7 `S-13`"*,
   *"CRM D-10 ≡ demographics D-6"*, *"Both should be answered once, together."* Strongest, and used wherever
   available.
2. **A single answer settles both, and the same owner could not coherently answer one yes and the other no.**
   This is the scope amendment's own stated merge rule (§14.1) and this register reuses it verbatim.
3. **Same object, same authority cell, same failure.** Two documents describe one column, one predicate or one
   function, and the failure text matches.
4. **A merge already performed upstream.** The scope amendment §14.1 collapsed 133 raised items into 81; those
   merges are inherited and re-cited rather than re-derived.

**Two filings were kept separate despite an identical id** wherever rule 2 failed — see the "same id,
different decision" table below.

## Merges performed here, beyond the scope amendment's own

| ODR | Merged filings | Evidence |
|---|---|---|
| `ODR-1` | REGISTRY header · record `C72`/`O10` · record `C73`/`C74` (`RATIFIED-PENDING-REGISTRY-RE-RATIFICATION`) · AMEND `OD-79` · ROLE `OD-10` · PROMO §14.1 · NOTIF `O-N7` · VD §22.15 · SCHEMA §1.13 and §3.10a headers | Rule 1 + rule 2. AMEND §14.1 already merged five of them (*"Five reports of one numbering problem"*). The record's `O10` is **one of the six amendments** the registry header lists, and `C73`/`C74` are two more — all six discharge on one ratification act, so answering `OD-79` answers `O10` and vice versa. |
| `ODR-2` | record `C51`/`O7` · `COND-A` (registry, schema, plan) · AMEND `OD-13` · NOTIF `O-N2`/`CONFLICT-2` · RLS `MD-11` · TRACE `G-1`/`D4` | Rule 1: AMEND §14.1 names *"Five statements of the same missing outbox."* `MD-11` and `G-1` are two more statements of it. |
| `ODR-3` | record `C52`/`O8` · `COND-B` (registry, schema, plan) · AMEND `OD-14` · NOTIF `O-N1`/`CONFLICT-1` · RLS `MD-10` · VD §22.16 · TRACE `G-2` | Rule 1: *"Five statements of the same `notify` gate."* |
| `ODR-4` | AMEND `OD-19`/`HG-8` · DEMOG `D-9`, `D-11` · CRM `D-3` · RLS `MD-9` · SCHEMA §1.15.2 `D-3` · REGISTRY `OWNER-DECISION-K2-D3` | Rules 1 and 2 for the first four (AMEND §14.1). The two later filings are the **same sign-off with a widened scope**: *"`D-3`'s outstanding sign-off now covers **SIX** relations, not four"* — a scope amendment to one decision, not a second decision. |
| `ODR-10` | MONEY `D-1` · RLS `X-8` + `MD-1` · RPC §16 item 8 · SCHEMA §0.9 + §1.13 · AMEND `OD-01` | Rule 1: AMEND §14.1 — *"One question — is `approval_request` an aggregate class? — asked as a design question, as an RLS note, and as a C28-amendment request."* |
| `ODR-13` | SCHEMA `S-9` · RLS `X-17` + `MD-17` | Rule 1: RLS §17 `X-17`'s To column reads *"**owner ruling** (schema §13.7 `S-9`)"* — the RLS spec names the schema id for its own row. |
| `ODR-16` | record `O15`/`C95` · SCHEMA §5.1 `CUSTODY-DEL-1` · SCHEMA `S-19` | Rule 1: the record's `O15` row cites *"filed `S-19`"* and schema §5.1 is where the three admissible forms are stated. |
| `ODR-19` | record `O16`/`C92` · SCHEMA §1.9.2 · SCHEMA `S-16` · EDGE §4 | Rule 1: the record's `O16` row cites *"filed `S-16`"*. |
| `ODR-20` | SCHEMA `S-13` · RPC `R-21` · RLS `MD-18` · ROLE `OD-11` · TRACE `G-14` | Rule 1, four ways: RPC §20.14 `R-21`'s File column reads *"Owner ruling (schema §13.7 `S-13`)"*; RLS `MD-18` states the identical two-exit form; ROLE `OD-11` cites `S-13` and `R-21` by name. **One decision under four ids** — the sharpest instance in the corpus. |
| `ODR-21` | RPC `R-19` · RLS `X-18` + `MD-19` · EDGE §3.9a | Rule 1: `X-18` cites *"RPC §20.14 `R-19`"*; `MD-19` restates the same one-column alternative. |
| `ODR-23` | CRM `D-2` · RLS `MD-2` · AMEND `HG-4` | Rule 1: `HG-4` names *"`CRM` §13 D-2 … · `RLS` §15.7 **MD-2**"* as one gate. **This merge has no `OD-` id in the scope amendment's index**, which the amendment itself notes. |
| `ODR-26` | ROLE `OD-4` · RLS §15 item 3 · RPC §16 item 4 · AMEND `OD-11` | Rule 3 plus rule 1 — RPC §16 item 4 says *"mirrors RLS §15.3"*. |
| `ODR-28` | SCHEMA `S-10` · RPC `R-5` · RLS `X-13` (schema half) · VD `U-4` | Rule 1: schema §13.7 `S-10` says *"RPC §20.14 **R-5** poses it as a fork and it must be closed one way."* |
| `ODR-33` | PROMO `OWNER DECISION 7` · RN §12 item 13 · AMEND `OD-39` | Rule 1: RN §12 item 13 states it defers to *"the promoter spec['s]"* recommendation and marks itself *"→ owner decision."* |
| `ODR-35` | record `C85`/`O13` · MONEY `D-8` + §11.1 · VD §5.2 + §22.13 · AMEND `OD-05` | Rule 1: VD §22.13 cites *"`O13` in `PHASE_2_RATIFICATION_RECORD.md`"* and the money spec's `D-8` by name; record `C85` cites *"money §11 `D-8`"*. |
| `ODR-36` | record `C77`/`O12` · SCHEMA §1.13.4 + `S-3` · RPC `R-22`(2nd) · RLS §11.3a · MONEY §6.7a-2 | Rule 1: RPC §20.14's second `R-22` File column reads *"Owner ruling (`…SCHEMA…` §1.13.4 · §13.7 `S-3`)"*. |
| `ODR-37` | record `C90`/`O14` · MONEY `D-10` · RPC §10.3 `MB-1b` | Rule 1: MONEY `D-10` closes with *"Ratification `C90` / open decision `O14`"*; RPC §21 maps `MB-1b` to *"`C90` / `O14`"*. |
| `ODR-40` | MONEY `D-6` · RLS `MD-6` **and** `MD-16` · AMEND `OD-07` | Rule 2. `MD-16` is not a second decision: its recommendation is *"Unchanged"*; it exists to tell the owner the control **was inert** before `AUTHZ-C1A` and now is not. |
| `ODR-44` | ROLE `OD-7` · RLS `MD-12` · DOOR §8.2/§8.3/§10A.3/§10A.7 · AMEND `OD-09` | Rule 3: the door spec independently and more specifically rules the same capability (`platform_admin` grant-only, `platform_risk` may revoke). |
| `ODR-47` | record `C56`/`O9` · DOOR `OQ-5` · WALLET `OQ-W4` + `DL-4` · EDGE §9 item 15 · AMEND `OD-25` | Rule 1: the Wallet register's `OQ-W4` heading reads *"RULED by door §16 OQ-5 — GRANTED, owner sign-off still owed"*, and door `OQ-5`'s heading reads *"RULED (Wallet DL-4 / OQ-W4)"*. **One decision under three ids in two files, plus its two conditions in a third.** |
| `ODR-49` | WALLET `OQ-W6` · EDGE §7 members 2 and 3 · record `D9` · AMEND `OD-27` | Rule 1: `OQ-W6`'s recommendation itself widens the scope — *"The sign-off should cover the `verify_jwt=false` set as a whole, not this function alone"* — and edge §7 concurs from its side. |
| `ODR-53` | WALLET `OQ-W5` · EDGE §9 item 2 · AMEND `OD-26` | Rule 1: WALLET `OQ-W5` says *"**Answer both together.**"* Merged **despite opposite defaults**, which is recorded in the entry rather than smoothed. |
| `ODR-61` | CRM `D-7` · DEMOG `D-8` · ROLE §5 `H2`/`H3` · AMEND `OD-20` | Rule 1: CRM `D-7` — *"**Both should be answered once, together.**"* |
| `ODR-62` | CRM `D-8` · RLS `MD-8` · VD §22.6 · AMEND `OD-21` | Rule 1 (AMEND §14.1: *"One question — is a platform bulk-extraction path wanted at all?"*). |
| `ODR-66` | DEMOG `D-14` · CRM §4.5 | Rule 1: CRM §4.5 raises the identical question *"from the other side"* and has **no `D-` id of its own** for it. |
| `ODR-67` | DEMOG `D-6` · CRM `D-10` · AMEND `OD-16` | Rule 1, explicit: CRM §9.3 — *"this document does not create a second one."* |
| `ODR-68` | DOOR `OQ-4` · RLS `X-7` · VD §22.11 · EDGE §9 item 7 · RN §12 item 9 · SCHEMA §2.3.1 · AMEND `OD-59` | Rule 1 for the first three (AMEND §14.1); rules 1 and 3 for the rest — EDGE §9 item 7 and RN §12 item 9 are the same sentence in two files, each citing door `OQ-4`. **Six filings, one decision.** |
| `ODR-75` | VD `U-5`/Δ11 · VD `U-6`/Δ12 · RLS `X-19` · AMEND `OD-65` | Rule 1: AMEND §14.1 — *"Two reads on one confirm dialog, same surface, same role set, one grant."* |
| `ODR-92` | RPC `R-10` · RLS §11.1c · VD `U-7`/Δ3c · TRACE `G-18` · PLAN §8 · AMEND `OD-66` | Rule 1: RPC §20.14 `R-10` is filed as *"Owner ruling"* and RLS §11.1c refuses to write the EXEC row *"for a function whose existence is undecided"*, naming `R-10`. |
| `ODR-111` | DEMOG `D-4` · CRM `D-9` · AMEND `OD-22` | Rule 1: AMEND §14.1 — *"'Is a demographic-based send wanted' and 'confirm X-8 stays closed' are the same question from the two ends."* |
| `ODR-119` | VD Δ8 · DOOR `OQ-3` (open half) · ROLE §11.3 `S-6` + §12 row 25 · AMEND `OD-72` | Rule 1: door `OQ-3`'s open half names *"**VD Δ8's** per-event / expiring / per-capability grants"* as the **only** named remedy and says *"not in scope here."* |
| `ODR-122` | ROLE `OD-1` · ROLE `OD-9` · AMEND `OD-81` | Rule 4 — inherited from AMEND §14.2-K, which already bundles them. Kept bundled because one sitting closes both and neither can be answered without the other's context (`OD-1` is entangled with `ODR-26`). |

| `ODR-124` | record `O18` · `D35`(d) · `ARCHITECTURE_FREEZE.md` covered-set § · matrix §0.1/§14 · `C84` | Rule 1: `O18`'s own Sites column names the freeze's covered-document list and matrix §0.1/§14. **The scope amendment is merged into it rather than split out**, because `O18` states one question over two documents (*"nor `PHASE_2_SCOPE_AMENDMENT_2026_08.md` — so **neither** is under Rule 1"*) and no owner could coherently cover one and declare the other derived — rule 2. |
| `ODR-125` | `C117` · `D23` · registry §2.2 seventh amendment + JSON `seam_2_hooks.r2b_note` · plan §8 `085` · RPC §20.11.3 · brief DECISION 6 · Final Report §8 item 5 | Rule 1: every one of those sites names the filing `R2B-1` by that id and routes it to the same owner. **Merged despite the id colliding inside its own home file** — see the collision table. |
| `ODR-126` | record `D23` · registry `090` rollback row · `C112` | Rule 1: `D23` names it as the third of exactly three questions the pass routed out, and names its owner. |
| `ODR-127` | Final Report §7 + §8 item 2 · brief §E · RPC §6.3 vs §7.1 · precedent `C121` | Rule 3 (same object, same failure) plus rule 1 — the brief and the Final Report describe the same conflict and both exclude it from the `O11`-solvable set for the same stated reason. |
| `ODR-128` | Final Report §8 item 2 (six of its seven) · brief §0.3 · RPC `R-24`, `R-29` · door §21 `DR-1` | Rule 2, stated by the brief: one ruling (`ODR-7`) settles all six, and no owner could coherently rule delta-spec precedence one way and then resolve these six the other. Filed as one entry rather than six because **six entries would misrepresent the work as six decisions.** The seventh is `ODR-127` and is deliberately **not** merged, because no precedence rule reaches it. |

## Same id, different decision — kept separate, deliberately

| Id | Meaning A | Meaning B | Meaning C |
|---|---|---|---|
| `D-3` | MONEY §11 — the six threshold **values** | CRM §13 / SCHEMA §1.15.2 — the `ON DELETE CASCADE` sign-off | — |
| `D-6` | CRM §13 — export artifact retention, 24 h vs 7 d | DEMOG §14 — the backup window `{N}` | ROLE §11.7 — a rejected edit instruction, *"`D-6` here is rejected by `D6` there"* |
| `D-8` | CRM §13 — platform bulk extraction | DEMOG §14 — marketing's mix-card ceiling | MONEY §11 — `org_admin` on the money plane (**blocking**) |
| `D-12` | CRM §13 — operatorship change | DEMOG §14 — `R7` eligibility | — |
| `D-13` | CRM §13 — the `display_name` export gate | DEMOG §14 — the vector-7 differencing residual | record row `D13` — the `K-2`/`K-3` edges |
| `OD-8` | ROLE §13 — door break-glass | AMEND §14.2 `OD-08` — step-up at `aal1` | — |
| `OD-11` | ROLE §13 — does `set_event_security_config` exist | AMEND §14.2 `OD-11` — settlement close authority | — |
| `S-5` | SCHEMA §13.7 — the `assert_door_session` token parameter | ROLE §11.3 — the `catalog.event` marketing columns | — |
| `S-6` | SCHEMA §13.7 — the derived device-id parameter | ROLE §11.3 — the event-scoped grant extension point | — |
| `R-22` | RPC §20.14 — the 30-second clock-skew confirmation | RPC §20.14 — the platform-plane maturity ruling (**same table**) | — |
| `O3` | risk register — resale-policy snapshot drift | record — `O-3`, the ratified payout-visibility ruling | — |
| `O4` | risk register — identity-verification strength | record — `O-4`, the ratified door-manifest ruling | — |
| `O7` / `O8` | record — the outbox and the `notify` gate | asserted by three documents to be DA §0.4 open questions (**defect DF-5**) | — |

| **`R2B-1`** | **registry §2.2, seventh-amendment block — the *repair*: the composite type `kernel.settlement_line_candidate` (`C116`, `S2-A`), created by nothing and failing `087` at `42704`** | **registry §350, plan §8 `085`, record `C117`/`D23` — the *filing to the RPC owner*: `p_cause`'s admissible values (`ODR-125`)** | — |


> ### The `R2B-1` collision, in full — because one of its two meanings is an owner decision and the other is not
>
> **The seventh amendment mints two `R2B-n` series and puts them in the same file.**
>
> - **The repair series.** `PHASE_2_PACKAGE_REGISTRY.md` §2.2 enumerates the pass's repairs as
>   **`R2B`-1 (`C116`, `S2-A`)** — the missing composite type; **`R2B`-2 (`C117`, `S2-B`)** — the
>   `market.on_atom_voided` arity and the new `SEAM-2a` rule; **`R2B`-3 (`C114`, `V5`)** —
>   `kernel.issue_ticket_atoms` reading `kernel.signing_key`.
> - **The filed-request series.** Record row `D23` enumerates *"**Three requests filed to sibling owners:**
>   **`R2B-1`** → RPC owner (`p_cause`); **`R2B-2`** → RLS owner (the `_sel_svc_export` policy naming);
>   **`R2B-3`** → schema-spec owner (§13.2's sweep method)."*
>
> **All three ids collide, not just the first**, and `PHASE_2_PACKAGE_REGISTRY.md` carries **both** meanings of
> `R2B-1` and `R2B-2` — the repair block at §2.2, the filings at §350 and in the JSON `crm_export_builder`
> note. **The one that matters is `R2B-1`**, because one of its two meanings is an **open owner decision**
> frozen at `085` (`ODR-125`) and the other is a **ratified, applied repair** (`C116`). A reader who follows
> `R2B-1` from the migration plan into registry §2.2 lands on a composite type and concludes the question was
> answered.
>
> **This register cites `R2B-1` to mean the `p_cause` filing only**, and says so at `ODR-125`. The correct fix
> is one rename in one file and it belongs to the registry owner; nothing here performs it.


**Consequence for anyone automating over this corpus:** a dedup keyed on a normalized id string will merge the
ratified payout ruling `O-3` with the unrelated open question `O3`, the door break-glass question with the
step-up question, and a **ratified type creation with an open money decision** (`R2B-1`). Match on
**document + section + id**, never on id alone.

---

# THE ID NAMESPACES THIS REGISTER HAD TO CROSS

The original brief said "at least eight". The scan at `32249f2` found **twenty-two** distinct series carrying
open owner decisions or their filings, plus three more that carry decisions raised elsewhere. **At `269e473`
it is thirty-one**, and every one of the nine new series was minted on a single day — 2026-08-28 — by six
concurrent remediation passes, each of which correctly refused to reuse a sibling's prefix and thereby created
one more. Listed so the next reader knows what they are holding.

| # | Series | Home | What it means there |
|---|---|---|---|
| 1 | `O6` … **`O18`** | record | the record's own open decisions. **`O17` and `O18` are new since `32249f2`** and are `ODR-23` and `ODR-124` here |
| 2 | `O-1` … `O-5` | record | ratified **owner rulings** — closed, not decisions |
| 3 | `O1` … `O6` unhyphenated | DA §0.4 · risk register | architecture open questions; `O1` and `O5` reframed, `O2`/`O3`/`O4`/`O6` live |
| 4 | `C26` … **`C134`** · `D1` … **`D35`** · `RET-1` … `RET-6` | record | correction, doc-fix and retraction rows. **`C119` and `D24`–`D29` are deliberately free** — reserved by the `R4` pass for siblings that then took less than reserved |
| 5 | `D-1` … `D-10` | MONEY §11 | *"Owner decisions still required"* |
| 6 | `D-1` … `D-13` | CRM §13 | *"Open questions — owner, counsel, and architecture decisions"* |
| 7 | `D-1` … `D-14` | DEMOG §14 | *"Open questions — owner and counsel decisions required"* |
| 8 | `D-1` … `D-10` | ROLE §11.7 | edit instructions, not decisions; **`D-6` there is *rejected by* record row `D6`** |
| 9 | `S-1` … **`S-27`** | SCHEMA §13.7 + **new §13.7a** | requests to other integrators; `S-8`/`S-9`/`S-10`/`S-13` are owner rulings. **`S-23`…`S-27` are new**, filed by the `R1` pass |
| 10 | `S-1` … `S-6` | ROLE §11.3 | schema edits requested by the role model — a different series, all six ✅ APPLIED |
| 11 | `R-1` … **`R-33`** | RPC §20.14 | requests; seven are owner rulings or confirmations. **`R-28`…`R-33` are new**, filed by the `R1` pass |
| 12 | `R-1` … `R-18` | ROLE §11.2 | RLS edit instructions; `R-18` now ✅ DISCHARGED |
| 13 | `R1` … `R36` | risk register | risks |
| 14 | `X-1` … `X-19` | RLS §17 | requests to other integrators; three are owner-facing, three appear twice (`DF-9`) |
| 15 | **`MD-1` … `MD-19`** | **RLS §15.7** | ***"Owner decisions this document surfaces or inherits"* — the single richest owner-decision register in the corpus, referenced by no other register's rows. `MD-11` has no row of its own (`DF-6`); the table's last row is `MD-16`, out of sequence.** |
| 16 | `OD-1` … `OD-11` | ROLE §13 | *"Owner decisions still required"* |
| 17 | **`OD-01` … `OD-81`** | **AMEND §14.2** | **the corpus's own consolidated owner-decision index — 133 raised items merged to 81, of which 54 block. It collides with #16 by a leading zero, has already produced one mis-citation (`X-13`), and reaches none of `O11`–`O18` nor nine live register rows (`DF-38`).** |
| 18 | `OQ-1` … `OQ-8` | DOOR §16 | *"Open questions (owner decisions)"* |
| 19 | `OQ-W1` … `OQ-W10` | WALLET §15 | *"Open questions — owner decisions"* |
| 20 | `O-N1` … `O-N15` | NOTIF §10 | *"Open questions — owner decisions required"*, split across two tables and non-monotonic |
| 21 | `OWNER DECISION 1` … `10` | PROMO §13 | bare integers, cited inline as `OWNER DECISION n` |
| 22 | `COND-A` / `-B` / `-C` | REGISTRY §7 | ratified-but-unscheduled conditionals. **`COND-D` is cited as a member of this series and is not in this file** (`DF-31`) |
| 23 | `Δ1` … `Δ12` and `U-1` … `U-10` | VD §21 / §20A.3 | column asks and unbacked controls |
| 24 | `OWNER-DECISION-K2-D3` / `-READ` | REGISTRY §7.1 | two decisions the `K-2`/`K-3` repair hit and left |
| 25 | `HG-1` … `HG-8` · `G-1` … `G-30` · `OPEN-1`/`OPEN-2` (+ an unnumbered `GP-3 NOTE`) · unnumbered `#1`–`#17` (EDGE §9) · unnumbered `1`–`13` (RN §12) | AMEND §11 · TRACE · RLS §16.10a · EDGE §9 · RN §12 | hard gates, traceability gaps, and two registers with **no id prefix at all** |
| **26** | **`MB-1` … `MB-6`** | record, 2026-08-28 | the cumulative-authority and unwritable-control passes |
| **27** | **`MP-1`** · **`MN-2`/`MN-4`** | record, 2026-08-28 | the offline-manifest projection pass, and its notification siblings |
| **28** | **`R1-1` … `R1-4`** | record, 2026-08-28 | the unapplied-filings pass — *"filed under a **sixth** ID namespace, deliberately distinct from `R-n`, `S-n`, `MB-n`, `MP-n` and `MN-n`"* |
| **29** | **`R2B-1` … `R2B-3`** ×2 · **`S2-A`/`S2-B`** · **`V1` … `V7`** | record + registry §2.2, 2026-08-28 | the replay-ordering pass. **`R2B-n` names two different series in the same file** — see the collision note above. `V1`…`V7` are its seven routine-layer forward references |
| **30** | **`R3-1` … `R3-6`** · **`R4-1` … `R4-7`** | record, 2026-08-28 | the register-integrity and unswept-text passes |
| **31** | **`DR-1` … `DR-3`** | **DOOR §21**, new | requests filed to the RPC owner by `C134`. **Appears nowhere in the scope amendment** |

**Series that carry owner-facing content no consolidated index reaches:** `MD-n` (#15), the unnumbered
EDGE §9 / RN §12 series (#25), the `R2B-n` filing series (#29) and `DR-n` (#31). Between them they hold
`ODR-18`, `ODR-38`, `ODR-43`, `ODR-82`, `ODR-83`, `ODR-85`, `ODR-86`, `ODR-87` and `ODR-125` — and `ODR-87`
(notification permission priming) still has **no id in any register anywhere in the corpus**. It exists in
exactly one file, in one paragraph.

**The lesson the six passes taught, stated because it is about to recur.** Every one of them read the maxima
first, reserved a disjoint block, and minted a private prefix rather than reuse a sibling's — which is correct
discipline and is why `C119` and `D24`–`D29` sit free today. It is also why this corpus went from
twenty-two id series to thirty-one in a single day, why `R2B-1` means two things, and why this register went
stale in fifty-three commits. `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` §12 puts it as a process
finding: *"Six concurrent passes each claimed the same 'next free' ratification ids. Every collision was
renumbered by hand. Two later passes fixed it by reading the maxima first and reserving disjoint blocks — **the
fix is practice, not a rule, and it should become a rule.**"*

---

*End of `docs/architecture/_governance/PHASE_2_OWNER_DECISION_REGISTER.md`. Rebuilt at `269e473` on branch
`docs/register-rebuild-head`. **Instrument, not authority** — on any disagreement with a document that owns
the decision, the owning document governs and this file is corrected (ratified `C126`). One owner ruling is
recorded (`ODR-23`); nothing else here is a ruling and nothing here closes anything. **Re-run the four
staleness checks at the top before citing any count in this file.***
