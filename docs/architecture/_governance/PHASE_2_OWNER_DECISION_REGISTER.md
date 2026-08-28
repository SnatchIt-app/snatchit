# Phase 2 — Owner Decision Register

**Status:** INSTRUMENT, not authority. This file **decides nothing** and **changes nothing**. It is a reading
aid: one place where every open owner decision in the Phase 2 design corpus is stated once, in the form a
decision needs to be decidable — a question with named options, the failure under each option, the direction
silence falls, and what is blocked until it is answered.

**Built:** 2026-08-28, against branch `phase2/consolidation` at `32249f2`.
**Corpus scanned:** every `.md` file under `docs/architecture/**` at that commit — **36** of them (23 at the
top level, 9 under `_governance/`, 4 under `_superseded/`) — plus `ARCHITECTURE_FREEZE.md` at the repository
root. **37 files.** Verify with `find docs/architecture -name '*.md' | wc -l`, which returns 37 once this file
exists.

---

## THE COUNT, AND THE ENUMERATION BESIDE IT


> **This corpus has been bitten four times by a count that was updated while its enumeration was not**
> (record rows `D9`, `D11`, `D15`, and the freeze document's still-stale *"44 rows … three open decisions"*).
> The list below is **generated from this file's own entry headings**, not transcribed beside them. If the two
> ever disagree, the headings are right and the count is wrong. Regenerate it with:
>
> ```
> grep -cE '^#{2,3} ODR-[0-9]+ —' docs/architecture/_governance/PHASE_2_OWNER_DECISION_REGISTER.md
> ```


**There are 123 open owner decisions in the Phase 2 design corpus.**

Not counted, and held in their own sections below: **17 rows** of items that read as open and are already
settled (bookkeeping close only — several rows bundle a set, so they cover more than seventeen filings), and
**30 rows** of items filed in decision-shaped registers that are design defects with one correct answer.
**123 + 17 + 30 = 170** dispositioned rows in this file. Nothing found in the sweep is left undispositioned.

**Split by what each one blocks:**

| Band | Count | Ids |
|---|:-:|---|
| **Band 1 — blocks the start of implementation** | **7** | `ODR-1` … `ODR-7` |
| **Band 2 — blocks a named migration package** | **27** | `ODR-8` … `ODR-34` |
| **Band 3 — blocks a named surface, contract, control or feature flag** | **58** | `ODR-35` … `ODR-92` |
| **Band 4 — blocks nothing in the current scope** | **31** | `ODR-93` … `ODR-123` |
| | **123** | |

**The full enumeration.**


**Band 1 — blocks the start of implementation** — 7 entries

- **ODR-1** — Re-ratify the amended package registry
- **ODR-2** — Is the event outbox in Phase 2?
- **ODR-3** — What gate is the `notify` schema at?
- **ODR-4** — Acknowledge the two global-posture exceptions, and bind whoever next edits migration `020`
- **ODR-5** — Execute the migration-history repair, and authorize it
- **ODR-6** — What happens to the untracked `043_profiles_select_column_restriction.sql`
- **ODR-7** — Precedence between delta specifications

**Band 2 — blocks a named migration package** — 27 entries

- **ODR-8** — Per-org refund/payout thresholds at launch? · `077`
- **ODR-9** — Were `org_marketing` and `org_promoter_manager` intended to be storable at the org grain? · `077`
- **ODR-10** — Is `kernel.approval_request` an aggregate class or an intent record? · `077`
- **ODR-11** — The six threshold values · `078` seeds
- **ODR-12** — The money-role grant-maturity window · `078` seed
- **ODR-13** — `door.*` config visibility: `restricted` or `public`? · `078` seed row
- **ODR-14** — Confirm k = 25 and cell floor = 5, and where the constants live · `077` CHECK
- **ODR-15** — `notify.push_token` as a new table, or additive columns on `public.push_tokens`?
- **ODR-16** — How account deletion behaves for an identity holding custody · `079`
- **ODR-17** — `kernel.door_freeze_override`: move the table to `079`, or take a `SEAM-2` hook? · `079`/`086`
- **ODR-18** — Does disbursement auto-fire on `close_settlement`, or require an explicit human request? · `085`
- **ODR-19** — What `kernel.payout.status='paid'` asserts · `085`/`087`
- **ODR-20** — Does `venue.set_event_security_config` exist at all? · `078` + `086`
- **ODR-21** — The door-session selector: `door_session_id` or `session_ref`? · `086`
- **ODR-22** — `record_scan` under `FOR SHARE`, and whether M2 is signed · `086`
- **ODR-23** — Adopt the Layer-0 privilege wall for the export builder? · before `087`
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
- **ODR-52** — Post-open issuance: build the manifest supplement, or accept online-only door sales?
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
- **ODR-81** — Confirm `venue.set_event_security_config`'s key set and `revoke_signing_key`'s ack parameter
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

**Band 4 — blocks nothing in the current scope** — 31 entries

- **ODR-93** — Cross-region native resale: saga/escrow, or intra-region-only?
- **ODR-94** — Offline first-admit-wins consensus under clock skew and partition
- **ODR-95** — Resale-policy snapshot drift
- **ODR-96** — Per-event identity-verification strength
- **ODR-97** — Which privacy regimes apply? *(counsel)*
- **ODR-98** — Is gender identity special-category / sensitive personal information? *(counsel)*
- **ODR-99** — Which mandatory notification types are legally compulsory, and where? *(counsel)*
- **ODR-100** — The confidential-IP document in repository history *(counsel)*
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

**Which of the 123 default to the unsafe direction if nobody answers.** In blocking order:
`ODR-2` (no outbox is built) · `ODR-3` (`notify` is never scheduled and a binding dashboard dependency dangles)
· `ODR-4` (irreversible posture exceptions ship inside `077`, and one routine edit to migration `020`
reintroduces the sentinel defect) · `ODR-15` (four push-token fixes have no home) · `ODR-16` (account deletion
stops working for anyone who has ever held a ticket, the day `079` lands) · `ODR-18` (a money-out path with an
ambiguous auth model) · `ODR-19` (a failed transfer reads `submitted` forever) · `ODR-21` (edge §3.9a is
unimplementable as written) · `ODR-23` (a half-adopted privilege wall emits a blank contact column that reads
as *"nobody consented"*) · `ODR-26` (silence ratifies the permissive reading of an explicitly open settlement
authority) · `ODR-27` (an implementer invents a `market.bid` money surface at build time) · `ODR-35`
(`org_admin` gets the money-plane read, silently) · `ODR-36` (the platform money-key arm has no maturity floor
today) · `ODR-37` (payouts are splittable past the dual-control ceiling today) · `ODR-46` (a box-office lead
keeps door-lifecycle authority through the cutover) · `ODR-49` (an unauthenticated endpoint ships unreviewed)
· `ODR-50` (nobody owns the certificate that fails on a calendar) · `ODR-52` (a paying fan is refused at the
door with no remedy and no stated limit) · `ODR-55` (a mandatory money notice with push as its only channel)
· `ODR-63` (every export file's shape is undecided) · `ODR-65` (an unquantified inference channel ships
unstated) · `ODR-75` (the door-open confirm asks a question the operator cannot evaluate) · `ODR-80` (three
features with no runtime kill switch) · `ODR-87` (a cold OS prompt loses the push permission permanently) ·
`ODR-91` (no remedy exists, and support will ask for one within the first month).

**That is 25 of the 123** — the count is written after the list, from the list, for the reason in the box
above. For these twenty-five, *not deciding* is not deferral: the unsafe branch is already the one that ships.

**If only four can be answered this week**, the corpus's own priority stands and this register agrees with it:
`ODR-1` (blocks authoring any package), `ODR-2` and `ODR-3` (five features' schedules, and they must be ruled
together with the outbox first), and `ODR-4` (blocks `077`, the second package in the chain). Add `ODR-35`,
`ODR-36` and `ODR-37` if the money plane is being built before the door.


---

## How to read this file

**Nothing here is a ruling and nothing here is new.** Every entry is assembled from text that already exists
in the corpus. Where the corpus carries a recommendation it is **quoted**, with its source named; where it
carries none — several deliberately carry none — the entry says so. Where two documents disagree, both
positions are stated and neither is preferred.

**One decision, one entry, one id.** The corpus files the same decision in as many as five places under as
many as three different ids. This register merges those into one entry and lists every filing site, with the
evidence for the merge.

**The `Silence` line is the one to read first.** Every entry states what happens if nobody answers, and
whether that direction is **SAFE** or **UNSAFE**. Twenty-five of the 123 default to the unsafe direction — the
permissive grant, the missing floor, the unbounded value, the endpoint that ships unreviewed. A decision whose
silent default is safe can wait; one whose silent default is unsafe cannot, because *not deciding* is already a
decision and it has already been taken.

**Ordering.** Entries are ordered by what they block, most blocking first, then by blast radius:

| Band | Meaning |
|---|---|
| **Band 1 — blocks the start** | Must be answered before the first Phase-2 migration (`076`) or before the package DAG can be re-ratified at all. Nothing downstream is safe to begin. |
| **Band 2 — blocks a named migration package** | Implementation can start; one identified package in `076`–`091` cannot be authored correctly until this closes. Ordered by package number. |
| **Band 3 — blocks a named surface, contract, control or flag** | The migration chain proceeds; one identified surface, authority cell, contract or feature flag cannot be built or turned on. Ordered by blast radius — money plane, then door and Wallet, then product surfaces. |
| **Band 4 — blocks nothing in the current scope** | Real and unanswered, but nothing in Phase 2 waits on it. Includes the four counsel questions and four platform questions from outside the design corpus. |

---

## The new id namespace, and the proof it is unused

Ids in this file are **`ODR-1` … `ODR-n`** (*Owner Decision Register*). They are **additive**. They rename
nothing, renumber nothing, and replace no existing id anywhere in the corpus: every entry keeps and lists its
original ids, and those ids remain the ones to cite in their own documents.

**Why a new namespace was needed.** Open owner decisions are currently filed under **twenty-two distinct
series** — the full map is at the end of this file — and several of the collisions are documented hazards in
the corpus itself. The worst of them, in the order a reader meets them:

| Series | Where | Collision |
|---|---|---|
| `O6` … `O16` | `_governance/PHASE_2_RATIFICATION_RECORD.md` | `O6`–`O8` unhyphenated also read as DA §0.4 architecture open questions; `O-1`…`O-5` hyphenated are owner *rulings*. Filed as record row `D4`. |
| `D-n` | `PHASE_2_MONEY_AUTHORITY_SPEC.md` §11 | Three unrelated `D-n` series exist (money, CRM, demographics), **and** the record's own `D1`–`D21` rows collide with all three. |
| `D-n` | `PHASE_2_CRM_EXPORT_SPEC.md` §14 | as above |
| `D-n` | `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §16 | as above |
| `S-n` | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.7 | Collides with a different `S-n` series in `PHASE_2_ROLE_MODEL_SPEC.md`. Filed as a known hazard by record row `D17` (*"the `S-`/`D-` edit-id namespace collisions"*). |
| `S-n` | `PHASE_2_ROLE_MODEL_SPEC.md` §11.7 | as above |
| `R-n` | `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §20.14 | Three unrelated `R` series (RPC requests, role-model RLS edits, risk register `R1`–`R36`); the record avoided a fourth by minting `RET-`. |
| `X-n` | `PHASE_2_RLS_PERMISSION_SPEC.md` §17 | — |
| `OD-n` | `PHASE_2_ROLE_MODEL_SPEC.md` §13 | — |
| `OQ-n` / `OQ-Wn` | `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §16 / `PHASE_2_APPLE_WALLET_SPEC.md` §15 | — |
| `OD-nn` | `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2 | **`OD-01`…`OD-81` — the corpus's own consolidated index. It collides with the role model's `OD-1`…`OD-11` by a leading zero, and both are cited in the same file.** Already produced one mis-citation (`X-13`). |
| `MD-n` | `PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 | **The richest owner-decision register in the corpus — nineteen open rows with recommendations and blocking columns — and no other register's rows reference it.** |
| `O-N n` · `OWNER DECISION n` · unnumbered | notifications §10 · promoter §13 · edge §9 · RN §12 | four further series, two of them with **no id prefix at all** |
| `COND-A/B/C/D` | `PHASE_2_SCOPE_AMENDMENT_2026_08.md` · registry §7 | — |
| `Δn` / `U-n` | `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` | — |

**Proof `ODR-` is unused.** Two checks, run against the whole repository at `32249f2`:

```
$ grep -rIoE '\bODR-[0-9]+' . --exclude-dir=.git | wc -l
0

$ grep -rIin 'odr' . --exclude-dir=.git
.git:1:gitdir: .../worktrees/wt-odr
package-lock.json:65,735,2679,4807     (npm integrity sha512- hashes)
web/package-lock.json:2397             (npm integrity sha512- hash)
```

The only case-insensitive occurrences of the three letters anywhere in the repository are inside base64
npm integrity digests and this worktree's own path. A third check enumerated **every** id-shaped token
(`^[A-Z]{1,8}-?[0-9]{1,3}[a-z]?$`) across `docs/architecture/**` and `ARCHITECTURE_FREEZE.md` — 118 distinct
prefixes, listed below — and `ODR-` is in none of them:

```
A A- ADDITIVE- API APPR- ATTR- AUDIT- AUTHZ- B B- BCP- C C- CAT- CFG CFG- COL- COMP- CONFLICT- CONNECT-
CRM CRM- CUSTODY- D D- DAG- DASH- DAY DB- DEFAULT- DEL- DEM DEMO- DEV- DL- DOOR- DRIFT- DS- E E- EA- EDGE-
EX- EXEC- EXPIRY- F F- FORCE- FR- G G- GATE- GLOBAL- GP- GUEST- H H- HG- I I- INV- J J- JORDY K K- KEY- L
L- M M- MARKET- MB- MD- MN- MONEY- MP- N NEW- NOTIFY- O O- OBS- OD- OFFER- OPEN- OQ- ORG- P P- PAYOUT-
PG PKG PL- POL- PROJ- PROMO- PSD PURGE- Q R R- REPLAY- RET- RM- ROLE- RV- S S- SEAM- SEC- SENTINEL- SET-
SETTLE- SF- SHA SHA- STAFF- SUBJ- T T- TM U- V V- W W- WALLET- X X- XO-
```

---

## How the corpus was searched, and why one pattern was not enough

The corpus does not mark open owner decisions consistently — that inconsistency **is** the problem this file
exists to solve, so the search could not assume any single marker. Every file listed above was read in full,
and the following independent sweeps were run across `docs/architecture/**` and `ARCHITECTURE_FREEZE.md`:

1. **The register tables**, each under its own local id scheme — money §11, CRM §14, demographics §16,
   schema §13.7, RPC §20.14, RLS §17, role model §13, door §16, Wallet §15, registry §7 and §7.1,
   dashboard's `Δ`/`U` lists, and the ratification record's `OPEN-GATED` rows.
2. **Status-word markers:** `OPEN-GATED`, `OPEN — owner`, `OPEN — recorded, not applied`.
3. **Prose markers:** `OWNER DECISION`, `OWNER-DECISION`, `owner ruling`, `the owner's`, `owed to the owner`,
   `owner must`, `awaiting owner`, `requires owner`, `owner ratification`, `owner sign-off`,
   `not decided here`, `recorded, not made`, `recorded rather than taken`, `left with its owner`.
4. **Negative-space markers** — the phrases the corpus uses when it declines to decide:
   `NO RECOMMENDATION IS OFFERED`, `Not made here`, `NO SIDE IS TAKEN`, `the choice is the owner's`,
   `a decision I declined to make alone`, `open question`, `must be chosen`, `not chosen`.
5. **The "what this pass deliberately did NOT do" paragraphs**, which every remediation pass in the record
   writes and which are where several decisions are named and nowhere else indexed.

Sweep 4 is the one that matters: the decisions with the most careful reasoning behind them are precisely the
ones whose authors refused to write a recommendation, and those rows contain none of the words in sweep 3.

---

## What this file deliberately did NOT do

- It **decided nothing.** No option is chosen, no default is endorsed, no recommendation is authored. Where a
  recommendation appears it is quoted from the corpus and attributed.
- It **closed nothing.** The "appears open, is in fact settled" section names decisions a later ratified row
  or spec already answered, with the evidence — it does **not** close them. Closing them is a bookkeeping act
  in the ratification record, and that is an owner act under Rule 1.
- It **renumbered nothing.** Every `ODR-n` is additive and lives only in this file.
- It edited **no** other document, **no** `OFFLINE-VERIFY-v1` fenced block, nothing under `.github/`,
  `supabase/` or any migration.

---

# BAND 1 — blocks the start of implementation

Seven decisions. **Nothing downstream is safe to begin until these are answered**, and two of them
(`ODR-1`, `ODR-5`) block work that has not started rather than work in progress, which is the cheapest
moment they will ever be answered at.

---

## ODR-1 — Re-ratify the amended package registry

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

---

## ODR-2 — Is the event outbox in Phase 2?

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

---

## ODR-3 — What gate is the `notify` schema at?

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

## ODR-4 — Acknowledge the two global-posture exceptions, and bind whoever next edits migration `020`

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

## ODR-6 — What happens to the untracked `043_profiles_select_column_restriction.sql`

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

## ODR-7 — Precedence between delta specifications

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

# BAND 2 — blocks a named migration package

Twenty-seven decisions, ordered by the package they gate. Implementation can begin once Band 1 closes; each
of these stops one identified package from being authored correctly.

Each entry states: the question as a choice · what breaks under each option · **which way silence falls, and
whether that direction is safe** · the package · every filing site · the corpus recommendation, quoted.

---

### ODR-8 — Per-org refund/payout thresholds at launch? · `077`
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

### ODR-16 — How account deletion behaves for an identity holding custody · `079`
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
*"**account deletion as a whole stops working for anyone who has ever held a ticket, the day `079` lands.**"*
**Blocks.** Package `079` — not its authoring, its product behaviour, from the day it applies.
**Filed at.** Record row **`O15`** / `C95` · SCHEMA §5.1 `CUSTODY-DEL-1` + §13.7 `S-19` · CRM §9.2 · DEMOG
§8.2 · DOOR §7.6.
**Recommendation.** **None.** Three forms are stated with their costs; none is preferred.

### ODR-17 — `kernel.door_freeze_override`: move the table to `079`, or take a `SEAM-2` hook? · `079`/`086`
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

### ODR-23 — Adopt the Layer-0 privilege wall for the export builder? · before `087`
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

### ODR-24 — Operatorship change: the new operator's CRM starts empty, and who tells them · `087`
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

# BAND 3 — blocks a named surface, contract, control or feature flag

Fifty-eight decisions. The migration chain can proceed; each of these stops one identified surface, one
authority cell, one contract or one flag. Ordered by blast radius — the money plane first, then the door and
Wallet, then the product surfaces.

**Read the `Silence` line.** Fourteen entries in this band default to the **unsafe** direction — `ODR-35`, `ODR-36`, `ODR-37`, `ODR-46`, `ODR-49`, `ODR-50`, `ODR-52`, `ODR-55`, `ODR-63`, `ODR-65`, `ODR-75`, `ODR-80`, `ODR-87`, `ODR-91`.

---

## The money plane

### ODR-35 — Does `org_admin` hold the money-plane read? · **surface H is BLOCKED**
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
**Choice.** Draft-only, or draft-and-release.
**Breaks.** Release authority puts a venue-wide, unrecallable broadcast in the hands of the role with the
standing incentive to use it.
**Silence.** Draft only, as specified. **SAFE.**
**Blocks.** Composer authority; pgTAP `N-A41`.
**Filed at.** NOTIF §10 `O-N6` + §7.3 + §2.5 · AMEND §14.2-H `OD-51`.
**Recommendation — yes.** NOTIF §10: *"**Draft only** (§7.3). Needs owner ratification because it is a
product-authority call, not a technical one."*

### ODR-58 — Do venue-staff notifications share the consumer inbox table?
**Choice.** One `notify.notification` table with `org_id`/`venue_id` columns, or a separate staff surface.
**Breaks.** *Two tables* — *"would double every RLS and dedupe assertion."*
**Silence.** One table. **SAFE.**
**Blocks.** The `notify.notification` table shape; the RLS matrix; the dashboard surface.
**Filed at.** NOTIF §10 `O-N8` + §2.2 Group V + §6.1 · AMEND §14.2-H `OD-52`.
**Recommendation — yes.** AMEND `OD-52`: *"One table with `org_id`/`venue_id`; two would double every RLS and
dedupe assertion."*

### ODR-59 — Notification retention, and the `C48` retention floor
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
**Choice.** Stand up AASA and `assetlinks.json`, or keep every notification target navigation-only.
**Breaks.** Without them, `N-DL-4` binds: *"a notification link may never carry a secret, a token, or a
one-time action."* Adding a sensitive target without them is the failure the rule exists to stop.
**Silence.** `N-DL-4` binds; targets stay navigational. **SAFE.**
**Blocks.** Any deep-link target more sensitive than navigation.
**Filed at.** NOTIF §10 `O-N15` + §4.4 `N-DL-4` · AMEND §14.2-H `OD-56`.
**Recommendation — yes.** AMEND `OD-56`: *"AASA/`assetlinks.json` required before a sensitive target."*

## Privacy, CRM and the venue dashboard

### ODR-61 — Marketing's CRM and analytics ceiling — answered once, for three specs
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
**Choice.** Contract create-list / add-guest / remove-entry, or drop the surface. *"**No RPC is named anywhere.**
Three distinct writes, zero signatures."*
**Silence.** VD's standing rule holds: *"the control is read-only or it does not render. Do not soften it to
'hidden behind a flag'."* **SAFE.**
**Blocks.** Venue dashboard surface F.
**Filed at.** VD §20A.3 `U-1` + §11.2 · TRACE `G-10` · AMEND §14.2-J `OD-62`.
**Recommendation.** **None** — `OD-62`'s cell is empty.

### ODR-73 — Name the mark-a-guest-arrived RPC · the door
**Choice.** Contract it, or the control does not render. RLS grants the door principal exactly this narrow
update and **no contract exists**.
**Silence.** The control does not render. **SAFE, and operationally expensive:** *"the single most-used control
at a door"*, *"the one a door will hit a thousand times a night."*
**Blocks.** The door.
**Filed at.** VD §20A.3 `U-2` + §11.5 · TRACE `G-9` · AMEND §14.2-J `OD-63`.
**Recommendation.** **None** — `OD-63`'s cell is empty.

### ODR-74 — Name the promoter record and link RPCs, and a live slug-availability read · surface E
**Choice.** Contract create/edit promoter, commission terms, create link, set status and an availability check
— or drop the surface. *"the UI is required to run a live global-namespace check **against nothing**."*
**Silence.** The controls do not render. **SAFE.**
**Blocks.** Venue dashboard surface E. Overlaps `ODR-28` on the `status` limb.
**Filed at.** VD §20A.3 `U-3`, `U-4` + §10.2/§10.3/§10.4 · TRACE `G-11` · AMEND §14.2-J `OD-64`.
**Recommendation.** **None** — `OD-64`'s cell is empty.

### ODR-75 — Grant the two door pre-confirm reads · the door-open confirm
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
**Silence.** The control does not render. **SAFE.** **Blocks.** VD §8.4.
**Filed at.** VD `U-8` + §8.4 · AMEND §14.2-J `OD-67`.
**Recommendation — partial.** AMEND `OD-67`: *"The guarded behaviour and refusal floor are already specified in
detail"* — i.e. only the signature is missing.

### ODR-77 — Name an update RPC for `catalog.event` / `event_session` · §7.3
**Choice.** Contract editing, or ship create-only. *"Creation is contracted; editing is not."*
**Silence.** Draft events cannot be edited. **SAFE.** **Blocks.** VD §7.3.
**Filed at.** VD `U-9` + §7.3 · AMEND §14.2-J `OD-68`. **Recommendation.** **None.**

### ODR-78 — Name `kernel.update_organization` · §16.1
**Choice.** Contract it, or the org display name cannot be edited. *"`catalog.update_venue` exists; the org has
no counterpart."*
**Silence.** Not editable. **SAFE.** **Blocks.** VD §16.1.
**Filed at.** VD `U-10` + §16.1 · AMEND §14.2-J `OD-69`. **Recommendation.** **None.**

### ODR-79 — Inventory warning thresholds
**Choice.** The low-inventory threshold values, and whether a per-venue override exists. *"no key is named and
no per-venue override exists. **Left unresolved rather than invented.**"*
**Silence.** No key; the zone-6 warning and the low-inventory notification rule both have nothing to fire on.
**Blocks.** VD §6.1 and the low-inventory notification rule.
**Filed at.** VD §22.8 · NOTIF low-inventory rule · AMEND §14.2-J `OD-76`.
**Recommendation.** **None.** AMEND `OD-76`: *"Left unresolved rather than invented."*

### ODR-80 — Kill switches for the three features that have none
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
**Choice.** The numeric app-profile TTL and the rolling re-sign cadence.
**Breaks.** *"depends on the offline dead-zone tolerance at real venues and the acceptable screenshot-resale
window"* — *"long enough to survive a dead-zone at the door, short enough to bound a verifier running an M2
older than its `not_after`."*
**Silence.** `credential.app_ttl_interval` seeds at `'4 hours'`. **SAFE.**
**Blocks.** A `078` seed value only.
**Filed at.** EDGE §9 item 4 + §5.5 · WALLET §11.5. **Not in any consolidated index.**
**Recommendation.** **None** — *"needs a product/ops number. **Bounded, not fixed.**"*

### ODR-86 — KMS provider, signing algorithm, and token wire format
**Choice.** Ed25519 or ECDSA-P256; AWS KMS, GCP KMS or CloudHSM; compact JWT-like or custom COSE.
**Breaks.** Nothing security-wise — *"both satisfy the non-exposure rule."* Wallet §5.4 already sizes the QR
against an Ed25519 64-byte signature.
**Silence.** Unpinned. **SAFE, but the door SDK's wire format cannot be fixed.**
**Blocks.** The door SDK contract. No migration.
**Filed at.** EDGE §9 item 3 + §5.1/§5.3. **This is an infra/ops call, not the founder's**, and the edge spec
says so: *"**Flagged, not decided here** … left to infra/ops."*
**Recommendation.** **None**, beyond §5.1's *"Ed25519 preferred."*

### ODR-87 — Notification permission priming
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

Thirty-one decisions. Real, unanswered, and nothing in the Phase-2 scope waits on them. Four need counsel
rather than the owner; four are commercial or platform questions outside the design corpus entirely. Kept in
the same instrument so that "we never decided that" is never the answer.

Format: **choice** · *what breaks* · **silence** · blocks · filed at · recommendation.

---

### ODR-93 — Cross-region native resale: saga/escrow, or intra-region-only?
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
Design the arbitration and fraud-queue mechanism, or continue on `C23`'s total order as the interim. *Without
it, offline scanning at scale has no defined arbitration for two doors that each admit first.* **Silence →
SAFE at current scale**, unsafe at offline scale.
Blocks: *"offline scanning at scale."* No package.
Filed at: DA §0.4 · `_governance/ARCHITECTURAL_RISK_REGISTER.md` (*"**Still OPEN**"*) · SCHEMA §12.
Recommendation: **none.**

### ODR-95 — Resale-policy snapshot drift
Define the runtime capture rule for a native listing that outlives a mid-sale policy change, or leave it. *A
listing can carry a policy the org has since changed; storage is versioned (schema §2.5) and the runtime
capture rule at listing time is open.* **Silence → SAFE until native resale.**
Blocks: Gate M / native resale. No package.
Filed at: DA §0.4 · risk register (*"decide before native resale"*) · SCHEMA §2.5 + §11 + §12 · CTO memo Gate M
item 15.
Recommendation: **none.**

### ODR-96 — Per-event identity-verification strength
Name-match-required versus custody-follows-credential, and how strong verification must be per ticket and per
event. *"where exactly identity binds, how strong the verification must be per ticket/event, and what happens
when a verified name legitimately differs (marriage, legal change, corporate holder) remain open."* **Silence →
SAFE:** custody is primary and name-match layers on.
Blocks: nothing named; high-risk events.
Filed at: DA §0.4 + the "three hardest open questions" appendix item 2 · risk register · SCHEMA §3.12 + §12.
Recommendation: **none.**

### ODR-97 — Which privacy regimes apply? *(counsel)*
*"(a) treat US-only, (b) treat GDPR as applying to visitor traffic, (c) build to the strictest and stop
asking."* **Silence → SAFE:** the design already satisfies the strictest reading.
Blocks: nothing. Filed at: DEMOG §14 `D-1` + §3.1 · AMEND §14.2-C `OD-15`.
Recommendation: *"Counsel. The design survives the strictest answer with no redesign."*

### ODR-98 — Is gender identity special-category / sensitive personal information? *(counsel)*
Yes or no. *A "yes" would normally force redesign; here it does not — the capture is already explicit-consent
shaped.* **Silence → SAFE.** Blocks: nothing.
Filed at: DEMOG §14 `D-2` + §3.1 · AMEND §14.2-C `OD-18`.
Recommendation: *"Counsel. A 'yes' requires no change."* The demographics spec asserts **no** legal conclusion
of its own, deliberately.

### ODR-99 — Which mandatory notification types are legally compulsory, and where? *(counsel)*
Treat the 24-type mandatory class as a product-ethics choice, or as a compliance control. *Consumer-protection
receipt rules, payment-reversal disclosure, card-network dispute notices and app-store guidance all bear on
it.* **Silence → the ethics judgement stands as if it were the legal answer** — harmless as product posture,
unsafe as compliance posture.
Blocks: *"whether the class is policy or compliance."* Nothing structural — *"the answer changes one registry
column."*
Filed at: NOTIF §10 `O-N4` + §3.4 + Appendix A2 · AMEND §14.2-H `OD-49`.
Recommendation: *"Counsel. The design is built so the answer changes one registry column."*

### ODR-100 — The confidential-IP document in repository history *(counsel)*
Accept the exposure, or rewrite history. *Tied to `ODR-101`: if the repository stays public, the IP agreement's
presence in history becomes a decision that cannot be undone by a visibility change alone.*
**Silence → exposure stands.**
Blocks: nothing in the design corpus.
Filed at: `_governance/SNATCHIT_GITHUB_REPOSITORY_STABILIZATION_ROADMAP.md` §6 / §19.7.
Recommendation: **none** — it is posed as a counsel question.

### ODR-101 — Repository visibility: private now, or stay public?
Make the repository private, or keep it public. *Staying public makes the Class-C removals and demo-credential
rotation immediate, and turns `ODR-100` into a history-rewrite decision.* **Silence → stays public.**
Blocks: nothing in the design corpus; it gates that roadmap's PR sequence.
Filed at: roadmap §8 / §19. **Note:** the whole roadmap is marked *AWAITING OWNER APPROVAL*.
Recommendation — yes: *"unless being public serves a deliberate goal *today*, **make the repository PRIVATE
now**."*

### ODR-102 — Buy the Supabase Pro plan?
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
Purchase now, or not. **Silence → not purchased.** Blocks: nothing.
Filed at: roadmap §18.
Recommendation — yes: *"**NO — not now.** … Decision: no purchase; re-evaluate at team ≥2."*

### ODR-104 — Add `age_band` in a later wave?
Add the field (`18_20 · 21_24 · 25_34 · 35_44 · 45_plus · prefer_not_to_say`, *"**Bands only. Never a date of
birth, never a year, never a derived integer age**"*), or not. *Adding without a fresh `notice_version` and its
own opt-in silently enrols someone in a new dimension; a DOB adds minor-data and identity-theft liability; it
may never be crossed with gender.* **Silence → SAFE:** not in Phase 2.
Blocks: nothing. Filed at: DEMOG §14 `D-3` + §1.5 · AMEND §14.2-E `OD-30`.
Recommendation: *"Value set pre-specified; needs a new `notice_version` and a separate opt-in. **Not Phase
2**."*

### ODR-105 — Does `platform_admin` get aggregate demographic access at all?
Yes, any session, audited — or zero platform access. *Yes means a platform-wide demographic read exists at all;
no means platform cannot diagnose a card.* **Silence → yes.** Blocks: nothing.
Filed at: DEMOG §14 `D-7` + §6 · AMEND §14.2-E `OD-31`.
Recommendation — and it leans against its own default: *"This spec defaults to yes, any session, audited. The
alternative (zero platform access) is also coherent and slightly stronger."*

### ODR-106 — Who owns the compelled-disclosure runbook?
Name an owner for the out-of-band, dual-controlled, audited direct-database procedure — *"never as a product
feature, never a self-service admin screen, never a role."* **Silence → nobody owns it; there is no product
default at all**, so when process arrives someone improvises or builds the screen §7.1 forbids.
Blocks: nothing. Filed at: DEMOG §14 `D-10` + §7.3 · AMEND §14.2-E `OD-32`.
Recommendation: *"Out-of-band, dual-controlled, audited; never a product feature."* — the shape, not the owner.

### ODR-107 — Does a native-rail resale purchase create a contact relationship?
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
Accept the divergence from the demographics spec (which hard-deletes a withdrawn answer), or align them.
*Hard-deleting the consent record *"destroys the person's own evidence along with the platform's"* in the
dispute *"this venue emailed me and I never agreed"*, and removes the as-of evaluability the `gate_as_of` fix
and the replay property depend on.* **Silence → SAFE:** as designed.
Blocks: nothing. Filed at: CRM §13 `D-4` + §5.3 · AMEND §14.2-G `OD-44`. Owner and counsel.
Recommendation — yes: *"Adopt — a consent record is evidence about a relationship, and it is the person's own
evidence in the dispute they are most likely to have."*

### ODR-109 — Confirm the attendee-lookup limit numbers
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
No (today's answer: one-at-a-time lookup), or yes with its own template and retention. *Yes → *"a printed list
is an unaudited export with none of §6's controls and a longer life than any of them."* No → *"**a box office
cannot print a paper list.** That is deliberate"* — a real 9 p.m. operational loss.* **Silence → SAFE:** the
denial stands.
Blocks: nothing. Filed at: CRM §13 `D-11` + §3.1 · AMEND §14.2-G `OD-47`.
Recommendation — yes: *"Today 'no' … A yes needs its own template, retention, and an honest note that print has
none of §6's controls."*

### ODR-111 — Confirm that no demographic-based send exists, in any form
Confirm the absence, or build one. *Any send is a new egress and contradicts `C40`; *"a `crm-export-deliver`
function emailing the CSV … puts the file in an inbox that outlives every control here."* The only admissible
future form is a **platform-side send** — *"the segment resolves inside Snatch It, the message goes out, and
the membership list never leaves."** **Silence → SAFE:** *"Not built, not designed, not stubbed."*
Blocks: nothing. Filed at: DEMOG §14 `D-4` + §9 `X-8` · CRM §13 `D-9` + §2.4 · AMEND §14.2-C `OD-22`.
Recommendation — yes: *"Stays closed; recorded so the absence is a decision, not a gap."*

### ODR-112 — Sub-promoters or sub-codes with a split commission?
Build a hierarchy, or not in Phase 2. *A split is a money change — two payees per attribution — which *"breaks
the one-payee-per-attribution shape in §4.3 step 2"*, the proof step that derives "at most one payout per
attribution."* **Silence → SAFE:** not built. Note DA §7.2 does mention promoter sub-links *"where allowed."*
Blocks: nothing. Filed at: PROMO §13 `OWNER DECISION 8` + §1.10 · AMEND §14.2-F `OD-40`.
Recommendation — yes: *"Not in Phase 2 — two payees per attribution breaks the one-payee shape."*

### ODR-113 — Code-enumeration thresholds
Confirm 30 `not_applicable` results from one principal in 5 minutes as the burst-audit trigger, or change it.
*Too tight *"locks out legitimate buyers who mistype"*; too loose widens the enumeration budget the §9.3
arithmetic depends on.* **Silence → SAFE:** the seeded value ships, tunable via config.
Blocks: nothing. Filed at: PROMO §13 `OWNER DECISION 10` + §9.4 · AMEND §14.2-F `OD-42`.
Recommendation — yes: *"Starting value, tunable via config; needs a real traffic baseline."*

### ODR-114 — Migrate the 12 legacy inbox types into the registry, or leave them alongside?
**Silence → SAFE:** left alongside. Blocks: nothing.
Filed at: NOTIF §10 `O-N10` + §2.6/§3.7 · AMEND §14.2-H `OD-54`.
Recommendation — yes: *"Leave them; register as `legacy=true`; do not touch working producers."*

### ODR-115 — Quiet hours · the `security_email_changed` mirror sweep · the promoter digest
Three deferrals bundled by the scope amendment. *Quiet hours are additive later via
`notify.delivery.next_attempt_at`; the mirror sweep was refused on evidence and *"the sound path is named there
and should be built deliberately, not assumed"*; the promoter digest matters because *"a working promoter
generates hundreds of these, and default-on per-order pings are a self-inflicted spam incident."** **Silence →
SAFE:** none in MVP.
Blocks: nothing. Filed at: NOTIF §10 `O-N12`, `O-N13`, `O-N14` · AMEND §14.2-H `OD-56` (first three limbs).
Recommendation — yes: *"First three: not in MVP."*

### ODR-116 — Rotating barcodes later? Google Wallet?
Adopt SafeTix-class rotating barcodes, or decline; add Google Wallet, or leave it out of scope. *Rotating
barcodes *"would add device-clock coupling and a new offline failure mode"* in exchange for *"a property
already held"* — currency is checked by `credential_version` plus M2, online **and** offline. Google Wallet
*"needs its own key custody, format, and review."** **Silence → SAFE:** neither is built.
Blocks: nothing. Filed at: WALLET §15 `OQ-W9`, `OQ-W10` + §1.2 · AMEND §14.2-D `OD-29`.
Recommendation — yes: *"Deferred; Google Wallet revisited after Apple ships and is measured."*

### ODR-117 — Δ6: `catalog.event.announce_at` / `on_sale_at` for a scheduled on-sale
Add the two nullable timestamps plus a sweep, or not. **Silence → SAFE:** VD §7.4 degrades.
Blocks: nothing. Filed at: VD §21 Δ6 · AMEND §14.2-J `OD-70`.
Recommendation — yes, with a boundary: *"Two nullable timestamps plus a sweep. **Explicitly not a virtual queue
or bot defence (C44)**."*

### ODR-118 — Δ7: `venue.ticket_type` sale windows and per-order min/max
Add them, or not. *Without them *"'Tables sell 1 per order' is currently unexpressible."** **Silence → SAFE:**
VD §8.6 degrades. Blocks: nothing.
Filed at: VD Δ7 · AMEND §14.2-J `OD-71`. Recommendation — yes, implicitly, on that argument.

### ODR-119 — Δ8: event-scoped, auto-expiring staff grants
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
Add it, or keep string matching. **Silence → SAFE.** Blocks: nothing.
Filed at: VD Δ9 · AMEND §14.2-J `OD-73`. Recommendation: *"Low priority; today it is string matching."*

### ODR-121 — Δ10: org and venue `brand_logo_ref`
Add them, or drop the delta. **Silence → SAFE:** VD §16.4's honest *"not available yet"* stands.
Blocks: nothing. Filed at: VD Δ10 · AMEND §14.2-J `OD-74`.
Recommendation — yes, conditionally: *"Only if venue branding is a product commitment; otherwise drop the
delta."*

### ODR-122 — Retain `venue_finance`, and do not rename `org_member` → `org_affiliate`
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

# APPEARS OPEN — IS IN FACT SETTLED

Seventeen rows below still read as open in the document that raised them, but a later ratified row, ruling or
spec **already answered them**. Several rows bundle a set (four dashboard deltas, five dashboard collisions,
three RLS requests, two risk-register questions), so the rows cover more than seventeen filings. They are **not entries in this register**, they are not counted in its total, and
**this file does not close them** — closing a row is an act in the ratification record and that is the owner's.
Each row below carries the evidence a bookkeeping close would cite.

| Reads open at | The question | Already settled by | Evidence |
|---|---|---|---|
| ROLE_MODEL §13 `OD-2` (and §12 row 2, *"remains the owner's to confirm"*) | `venue_door` → `venue_scanner`: nominative or descriptive? | **`O-2`** | AMEND §14.1: *"**Closed, and listed so nobody re-opens them:** `ROLE` OD-2 (`venue_scanner` rename) … closed by **O-2**"*. Already applied corpus-wide; residual `venue_door` strings survive only in explicitly historical contexts. |
| ROLE_MODEL §13 `OD-3`, cell §5.3 `B1` left `⚠` | `set_org_payout_destination`: `org_owner` only, or owner + finance? | **`O-3`** | AMEND §14.1: *"`ROLE` … OD-3 (`set_org_payout_destination`) — closed by O-2/**O-3**"*. `O-3` rules it explicitly: *"**Payout destination change is `org_owner` ONLY** (`org_finance` excluded)"*, with the permanent requester-vs-setter split, destination probation and out-of-band notification as its compensating controls. **The `⚠` in §5.3 `B1` is stale, not open.** |
| ROLE_MODEL §13 `OD-6` | Role columns as native enum or `text` + `CHECK`? | **SCHEMA §12.3**, adopted downstream | AMEND §14.1: *"`ROLE` OD-6 (`text` + CHECK) — closed by `SCHEMA` §12.3"*. Schema §3.9/§1.3 specify it and `077` asserts `pg_type.typtype='e'` returns **zero** rows across the four Phase-2 schemas (`T-SCHEMA-ROLE-02`). ROLE_MODEL's own row says *"**STATUS: ADOPTED downstream.**"* |
| ROLE_MODEL §13 `OD-10` | How does Phase-2 package numbering reconcile with the repo? | **`PHASE_2_PACKAGE_REGISTRY.md` §2/§4** | The registry is canonical: `071`–`075` are applied production migrations, Phase-2 occupies `076`–`091`, three stale scales existed and *"arithmetic alone is not safe — decode by **package identity**."* |
| NOTIF §10 `O-N7` / §1.8 `CONFLICT-3` | At what number does Phase 2 begin? | **the registry**, plus the plan's own rule | `076`+ is forced: `071`–`075` are applied and the plan's rule at `:102` says an applied migration may never be renumbered. |
| DOOR §16 `OQ-3`, enum half | Does the venue enum need a fifth label for box office? | **`O-2`** / `DL-X2` | Door's own restatement: *"**The canonical venue enum is six labels and `venue_box_office` is one of them** … and RLS §11.4 **already excludes it** … that half needs no owner call and **must not be re-litigated as one**."* The surviving half is `ODR-119`. |
| DOOR §16 `OQ-7`, part (b) | The `door-manifest` auth model and the PIN route | **the door spec itself**, `EDGE-2` / `AUTHZ-H3` | *"**Resolved: `door-manifest` is a single staff-JWT route at `verify_jwt: true`, and the PIN route is DELETED**"* — the PIN check was satisfiable by *any* live PIN for that session, including one issued to a different device. Marked `OWNER DECISION — RECORDED, NOT MADE`; the ratification *"removes an authorization surface and adds none."* Part (a) — whether M2 is signed — is still open at `ODR-22`. |
| PROMO §14.1 | Package numbering in the promoter spec | **ratification** | The section is re-titled **CLOSED BY RATIFICATION**; corrections `X-01`…`X-04` moved `venue.settlement` to `087` etc. |
| EDGE §9 item 11(a) | *"`venue.settlement` mapped `086` by promoter §0.3 vs `087`"* | **`X-01`, 2026-08-28** | Promoter §0.3 was corrected to `087`. The edge spec's *"the promoter spec is stale"* is itself now stale. |
| MONEY §6.7a conflict 1 | Immature-grant failure code: `sod_violation` or `precondition_failed('money_role_too_new')`? | **SCHEMA §13.7 `S-3(a)` / record `D16`** | *"the error is **`sod_violation`**, not `precondition_failed('money_role_too_new')` … Recorded as ratification **D16**."* Two sites still carry the losing code — see defect **DF-14**. |
| VD §21 Δ1, Δ2, Δ3 (partly), Δ4 | Four dashboard column/RPC asks | **`O-4`, `AUTHZ-H10`, and the RPC contracts** | VD §21.0 marks each *"SATISFIED"*. Δ3's third RPC survives as `ODR-92`. |
| VD §21 Δ5 | `catalog.event` marketing fields | **ROLE_MODEL §11.3 `S-5`**, applied in `078` | AMEND §14.1: *"`VD` Δ5 — satisfied by `ROLE` S-5's marketing columns in `078`."* |
| VD §22.1, §22.2, §22.3, §22.4, §22.7 | Five dashboard-vs-spec collisions | **`O-1` … `O-4`** | AMEND §14.1 lists all five as closed by the owner rulings. |
| VD §22.6 | Platform read vs venue CRM export | **CRM `K-3`** | AMEND §14.1; VD §22.6 is marked RESOLVED in place. The remaining *question* — whether a platform bulk path is wanted at all — is `ODR-62`. |
| VD §22.9 | A CRM collision | **CRM `K-5`** | AMEND §14.1. |
| RLS §17 `X-10`, `X-11`, `X-12` | Three schema/plan requests | **the schema pass** | Each is struck through and marked DONE in the same table. **Each also still appears once as a bold, live-looking row** — see defect **DF-9**. |
| Risk register `O1` and `O5` | Cancellation refund liability + reserve; cross-rail seat-identity dedup key | **`C29`** and **`C17`** | Risk register: `O1` *"Reframed as R4/C29 — it is a missing object + payout-timing policy, not merely a question"*; `O5` *"Reframed as C17 (external-seat-reference) — confirm enforced before native issuance for events with external inventory."* `O5` leaves a **verification** owed, not a decision. |

---

# NOT THE FOUNDER'S — DEFECTS WEARING A DECISION'S CLOTHES

Thirty rows. These are filed in decision-shaped registers, or cited as open questions, but they have **one
correct answer**.
Ruling on them as if they were preferences risks ratifying a bug. They are **not counted in this register's
total**, and none should be put in front of the founder as a choice.

| # | Item | Where | Why it is a defect, not a decision |
|---|---|---|---|
| **DF-1** | **`R-22` is used twice in RPC §20.14** for two unrelated items — the benign 30-second clock-skew confirmation (`ODR-82`) and the live money-plane authority hole (`ODR-36`) | RPC §20.14, self-reported as `R-26` | The row names its own answer: renumber the `MP-1` row, **never** the `C77`/`O12` row, which is cited externally by schema `S-3` and RLS §11.3a. A founder handed *"R-22"* gets an ambiguous ask. |
| **DF-2** | **`OD-n` and `OD-nn` are two different series distinguished only by a leading zero** — ROLE_MODEL §13 `OD-1`…`OD-11` and AMEND §14.2 `OD-01`…`OD-81`, cited side by side in the same file | ROLE_MODEL §13 · AMEND §14.2 | It has already produced a mis-citation: AMEND `X-13` records that CRM `D-7` points at `ROLE OD-8` (door break-glass) where it means ROLE_MODEL §5 `H2`/`H3`. One correct fix (prefix one series); no owner preference. |
| **DF-3** | **`S-1`…`S-6` mean different things in the schema spec and the role model**, and one citation is bare *and* mislabelled | SCHEMA §13.7 · ROLE_MODEL §11.3/§11.7 | ROLE_MODEL flags it itself: *"`S-5` here is the `catalog.event` marketing columns; `S-5` there is the `assert_door_session` token parameter — **the two most consequential rows in this pass, sharing an id**."* Worst instance: schema §1.12.1 cites *"**ratification `S-6`**"* — which names no ratification row at all — far from any section that would disambiguate it. The proposed fix (`RM-S-1` etc.) is *"filed, not performed"* only because a corpus-wide rename exceeded the author's mandate. |
| **DF-4** | **`D-3` means two different things**, and the schema spec writes its own bare | MONEY §11 `D-3` (threshold values) · SCHEMA §1.15.2 `D-3` (the cascade sign-off) | Inside the schema spec, `D-1` and `D-2` are qualified as *"(MONEY §11)"* and `D-3` is not — so a reader carries the money series into a row that means the CRM one. |
| **DF-5** | **The `O1`…`O8` range claim is wrong, in three documents** | Record's Statuses block and row `D4` · `ARCHITECTURE_FREEZE.md` line 26 · DA §0.4 note | The unhyphenated architecture open-question series is `O1`…`O6` (risk register enumerates exactly those). `O7` and `O8` are the **record's own** open decisions — the outbox and the `notify` gate. As written, the disambiguation note asserts that the record's `O7`/`O8` are DA §0.4 open questions. The note that exists to prevent an id collision contains one. |
| **DF-6** | **`MD-11` has no row of its own** — it exists only as a sentence inside `MD-10`'s cell, with no Recommendation and no Blocks column | RLS §15.7 | And it is the **event outbox**, which the domain architecture calls *"the only new infrastructure Phase 2 introduces."* A register entry that is a clause inside another entry is one a reader skips. |
| **DF-7** | **Four money config keys have no absent-key semantics** | SCHEMA §1.13.4 `FAIL-TO-SAFE (X-12)` covers `authn.money_role_maturity_hours`, `comp.per_staff_step_up_max_units`, `comp.per_staff_step_up_window_hours`, `refund.platform_support_max_minor` — and no others | `refund.org_auto_execute_max_minor`, `refund.org_dual_control_max_minor`, `refund.request_ttl_hours` and `refund.scanned_atom_policy` have **no stated absent-key rule anywhere**, while `X-12`'s own reasoning applies verbatim (*"a comparison against NULL is neither true nor false, so the guard simply does not fire"*). `refund.request_ttl_hours` is the worst: *"**A hold with no sweep is a bricked ticket.**"* **This is filed as neither a decision nor a defect anywhere in the corpus.** |
| **DF-8** | **`ODR-89` carries a recommendation and `ODR-35` is required to carry none, yet they are the same question at two grains** | MONEY §11 `D-4` vs `D-8` | Answering `D-4` *"Keep"* and `D-8` *"Deny"* is internally incoherent — an `org_admin` who may read the settlement header (gross, fees, refunds, net) but not the refunds order list. **The register does not say so.** This register says so at both entries. |
| **DF-9** | **`X-10`, `X-11` and `X-12` each appear twice in RLS §17** — once bold and live, once struck and DONE | RLS §17 | On a skim the bold rows read as open work. One correct fix: delete the superseded rows. |
| **DF-10** | **`venue.door_session` has two divergent physical specifications** | SPEC_FOUNDATION §6 note; schema §3.10a vs edge §3.9a | Four disagreements at once: `assert_door_session`'s fourth argument (`p_session_ref` vs `p_door_session_id`); a `session_ref text UNIQUE` column the schema spec does not define at all; `revoked_at IS NULL` + partial index vs a `status` column; `UNIQUE(token_hash)` present in the plan and absent from the edge spec. *"Two specs of one table cannot both be built."* The **selector** limb is a genuine one-column choice (`ODR-21`); the rest is reconciliation. |
| **DF-11** | **`catalog.platform_config` is still described as world-readable, in two places, after `C71` made it two-class** | MONEY §7.4 · SCHEMA §1.14 (in the same file whose §2.4.1 rules the opposite) · TRACE §10 (`TM-X2`) | This is the unsafe direction: *"telling an implementer that the table holding every dual-control ceiling, step-up window and export cap is world-readable"* is exactly the defect `C71` was raised against. It also invalidates the stated premise of `ODR-8`, which is why that entry says **re-pose the question before answering it**. |
| **DF-12** | **`R-19`'s `/refresh` half is bundled under an owner id but is a settled safety property** | RPC §20.14 `R-19`(b) · RLS `MD-19` · schema §3.10a.4 | *"its `/refresh` route is the property schema §3.10a.4 **deliberately refused**"* — a path that outlives the PIN. Bundling it with the selector spelling risks the founder "deciding" a closed safety property. |
| **DF-13** | **One finding, two ids** — RPC §0.7a cites `R-24` where the `R-` register and §21 cite `R-25` for the `resale_state` writer-set finding | RPC §0.7a vs §20.14 / §21 | One of the three references is wrong. |
| **DF-14** | **The immature-grant error code is already ruled and two sites still propose the losing one** | Ruled `sod_violation` by SCHEMA §13.7 `S-3(a)` / record `D16`; still proposed as `precondition_failed('money_role_too_new')` at SCHEMA §1.13.4 and listed as an unresolved conflict at MONEY §6.7a | *"a control whose denial arrives under two different codes is a control whose alerting cannot be written."* One correct answer, already recorded; what remains is deleting the losing text twice. |
| **DF-15** | **MONEY §12 still carries the `NO SCHEMA CHANGE` line that `S-14` proved false** | MONEY §12 vs SCHEMA §1.9.1 / `S-14` | *"`kernel.payout.status='held'` does not exist and is not being created"*, and the classification *"was false under **every** candidate repair — even adding a CHECK label is DDL."* `NO SCHEMA CHANGE` is what a migration author reads to decide a package needs no DDL. |
| **DF-16** | **Wallet `OQ-W3` is a proof, not a choice** | WALLET §15 `OQ-W3` / §0.2 / §4.5 · `HG-1` | *"Without step 3b, Scenarios 2, 3 and 4 all **ADMIT**, and this document's central claim is false."* Only the **acknowledgement** is genuinely owed, which is why `ODR-48` is phrased as one. |
| **DF-17** | **Door `OQ-4` / RLS `X-7` is a documentation defect wearing a confirmation** | DOOR §16 `OQ-4` · RLS §17 `X-7` · four sibling specs | The substance is that four specs describe a `C43` narrowing **nothing implements**, while `C43` is `RATIFIED-MODELED-ONLY(GATE-M)`. The correct action is a documentation fix; `ODR-68`'s confirmation is ceremony over it. Filed as a decision because *"if the board wants the narrowing in MVP it is a **new** ratification, not a clarification"* — that limb, and only that limb, is the owner's. |
| **DF-18** | **`_governance/PHASE_2_FINAL_PREIMPLEMENTATION_GATE.md` §10 does not exist** — the file ends at §9, while §5 cites *"the sixth is §10 GATE-1"* and §9 cites *"recorded in §10 as GATE-2"* | that file | **Two owner-facing gate items were lost in a salvage.** `GATE-1` = one `public` function retaining PUBLIC EXECUTE; `GATE-2` = *"§5's dependency bullets for packages at `080`, `084` and `088` name more dependencies than §3 and §2 … a content discrepancy … needs an architecture decision."* The content is not recoverable from this file. **Recover it from the superseded PR #22 branch or re-derive it — and if `GATE-2` turns out to be a real fork, it becomes an entry in this register.** |
| **DF-19** | **Record row `C85` points at `O11` twice where it means `O13`** | `_governance/PHASE_2_RATIFICATION_RECORD.md` row `C85` | *"and `O11` below"* and *"until `O11` closes"* — but `O11` is delta-spec precedence and the decision `C85` raises is `O13`. The head-of-record enumeration was repaired at `32249f2`; **the row body was not.** A reader following `C85` to `O11` finds an unrelated question. |
| **DF-20** | **`ARCHITECTURE_FREEZE.md` still says the record has "44 rows" and "three open decisions (O6, O7, O8)"** | `ARCHITECTURE_FREEZE.md` line 24 | The record's own table says 114 rows and eleven open decisions `O6`–`O16`. **This is the count-without-a-matching-enumeration failure the record has already been bitten by, surviving in the freeze document.** |
| **DF-21** | **`G-14` still carries `venue.set_door_open_at` as an open gap** | TRACE `G-14` | Record `RET-6` names it: the two role-model instances were corrected by `D13`; *"**`G-14` is NOT, and is owed by the matrix owner.**"* `O-5` makes `catalog.engage_door_freeze` the sole writer, so the EXEC row is the defect, not the ruling. |
| **DF-22** | **RLS §16.10a `OPEN-2` says *"the set of nine is ratified"* while §2.2's `AUTHZ-C1C` — same document — establishes ten** | RLS §16.10a vs §2.2 | `OPEN-2` is written against the pre-`C58` membership. Related: role-model `R-18` records the helper count stated **four different ways** (eight, nine, nine, eleven) across five statements; *"One number must win before that test can be written"* — a counting error with exactly one right answer, explicitly *"the RLS owner's call"*, not the founder's. |
| **DF-23** | **`G-25`: the event catalog says 36 events and ratified `C11` says *"~10 sync + ~6 real outbox events"*, and no document says which sixteen survive** | TRACE `G-25` / §8.3 | Ordinarily bookkeeping — except that **it corrupts the pricing of `ODR-2`**: *"an owner pricing the O7 ruling is reading a list that a ratified correction already reduced by more than half."* **Fix this before ruling on `ODR-2`.** |
| **DF-24** | **`Δ-N1`: `catalog.event_session.session_version` is correctness-blocking** | NOTIF §10 cross-agent list | *"**Without it a venue that moves the door time twice cannot notify twice** — the second change collides with the first row's dedupe key and is silently swallowed by `ON CONFLICT DO NOTHING`."* One correct answer. |
| **DF-25** | **`X-05`: `refund_hold` has no offline reject mapping** | AMEND §15 `X-05` · MONEY §12-2 vs DOOR §9.2 | *"A `refund_hold` atom would snapshot into the manifest with **no reject mapping and no defined offline behaviour**."* `086`'s CHECK must admit all four labels. The online twin is edge §9 item 14. |
| **DF-26** | **Promoter `OWNER DECISION 9` is not a decision** | PROMO §13 row 9 / §8.2 | *"**Only flagged so nobody implements it as an RLS permission.**"* It is a guard against an implementation mistake. **It is deliberately absent from this register.** |
| **DF-27** | **Promoter §14.4, §14.5, §14.7 are three defects filed among contradictions** | PROMO §14 | §14.4: attribution written at order **creation** contradicts *"written when paid"* — *"an ignorable ledger row is a contradiction in terms"*; record `D7` already ruled the constitutions right. §14.5: widening the idempotency key to `order_id` is *"strictly stronger"*. §14.7: *"A function defined in `087` cannot reference a table created in `090`; **the migration would fail to apply**."* |
| **DF-28** | **The twelve uncontracted RPCs and the ten unbacked dashboard controls are missing contracts, not choices** | TRACE `G-3`…`G-7`, `G-13`…`G-15`, `G-20`, `G-21`, `G-24` · VD §20A.3 `U-1`…`U-10` | *"the corpus contracted the functions a **product surface** demanded. It did not contract the functions an **authority table** granted."* `G-24` (no inventory-hold expiry sweep) is a plain correctness bug: *"an abandoned checkout removes inventory from sale permanently."* **`ODR-72`…`ODR-78` are in this register anyway**, because the corpus's standing rule makes them owner-gated stop-ship guards — but the founder's act there is *"authorize the contract to be written"*, not *"choose between options"*. Say that when tabling them. |
| **DF-29** | **Edge §9 items 12, 14, 15, 16 and RN §12 items 10 and 11** | EDGE §9 · RN §12 | A missing write path (*"or §3.3 has no write path"*), a return shape missing `signing_key_id` and a `reason` enum missing `refund_hold`, a granted ruling's condition satisfied by no code path (*"the exact 'a correct thing that nothing called' failure class"*), four config namespaces missing from the dual-control set (*"one `platform_admin` could enable Wallet before the §13 checklist was green"*), a wrong section pointer, and two banner strings for one condition. One correct answer each. |
| **DF-30** | **RLS §16.10a `OPEN-1` and the `GP-3 NOTE`** | RLS §16.10a | `OPEN-1`: *"**No document in the corpus defines 'tonight'**"* — a dangling grant in RLS §8.3, not a fork; the fail-closed omission has already de-facto answered it. `GP-3 NOTE`: the org arm of `kernel_tickets_sel_venue` should be split under `GP-3`'s own naming rule and is deferred only because splitting it *"would fail CI in a way that reads as a regression"* — a sequencing problem, not a judgement call. |

---

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

**Consequence for anyone automating over this corpus:** a dedup keyed on a normalized id string will merge the
ratified payout ruling `O-3` with the unrelated open question `O3`, and the door break-glass question with the
step-up question. Match on **document + section + id**, never on id alone.

---

# THE ID NAMESPACES THIS REGISTER HAD TO CROSS

The brief said "at least eight". The scan found **twenty-two distinct series carrying open owner decisions or
their filings**, plus three more that carry decisions raised elsewhere. Listed so the next reader knows what
they are holding.

| # | Series | Home | What it means there |
|---|---|---|---|
| 1 | `O6` … `O16` | record | the record's own open decisions |
| 2 | `O-1` … `O-5` | record | ratified **owner rulings** — closed, not decisions |
| 3 | `O1` … `O6` unhyphenated | DA §0.4 · risk register | architecture open questions; `O1` and `O5` reframed, `O2`/`O3`/`O4`/`O6` live |
| 4 | `C26` … `C98` · `D1` … `D21` · `RET-1` … `RET-6` | record | correction, doc-fix and retraction rows |
| 5 | `D-1` … `D-10` | MONEY §11 | *"Owner decisions still required"* |
| 6 | `D-1` … `D-13` | CRM §13 | *"Open questions — owner, counsel, and architecture decisions"* |
| 7 | `D-1` … `D-14` | DEMOG §14 | *"Open questions — owner and counsel decisions required"* |
| 8 | `D-1` … `D-10` | ROLE §11.7 | edit instructions, not decisions |
| 9 | `S-1` … `S-22` | SCHEMA §13.7 | requests to other integrators; `S-8`/`S-9`/`S-10`/`S-13` are owner rulings |
| 10 | `S-1` … `S-6` | ROLE §11.3 | schema edits requested by the role model |
| 11 | `R-1` … `R-27` | RPC §20.14 | requests; seven are owner rulings or confirmations |
| 12 | `R-1` … `R-18` | ROLE §11 | RLS edit instructions |
| 13 | `R1` … `R36` | risk register | risks |
| 14 | `X-1` … `X-19` | RLS §17 | requests to other integrators; three are owner-facing |
| 15 | **`MD-1` … `MD-19`** | **RLS §15.7** | ***"Owner decisions this document surfaces or inherits"* — nineteen rows, every one open, each with a Recommendation and a Blocks column. It is the single richest owner-decision register in the corpus and it is referenced by no other register's rows.** |
| 16 | `OD-1` … `OD-11` | ROLE §13 | *"Owner decisions still required"* |
| 17 | **`OD-01` … `OD-81`** | **AMEND §14.2** | **the corpus's own consolidated owner-decision index — 133 raised items merged to 81, of which 54 block. It collides with #16 by a leading zero and has already produced one mis-citation (`X-13`).** |
| 18 | `OQ-1` … `OQ-8` | DOOR §16 | *"Open questions (owner decisions)"* |
| 19 | `OQ-W1` … `OQ-W10` | WALLET §15 | *"Open questions — owner decisions"* |
| 20 | `O-N1` … `O-N15` | NOTIF §10 | *"Open questions — owner decisions required"*, split into blocking and non-blocking tiers |
| 21 | `OWNER DECISION 1` … `10` | PROMO §13 | bare integers, cited inline as `OWNER DECISION n` |
| 22 | `COND-A` / `-B` / `-C` / `-D` | REGISTRY §7 | ratified-but-unscheduled conditionals; `COND-D` is the coupling rule, not a decision |
| 23 | `Δ1` … `Δ12` and `U-1` … `U-10` | VD §21 / §20A.3 | column asks and unbacked controls |
| 24 | `OWNER-DECISION-K2-D3` / `-READ` | REGISTRY §7.1 | two decisions the `K-2`/`K-3` repair hit and left |
| 25 | `HG-1` … `HG-8` · `G-1` … `G-25` · `OPEN-1`/`OPEN-2` · unnumbered `#1`–`#17` (EDGE §9) · unnumbered `1`–`13` (RN §12) | AMEND §11 · TRACE · RLS §16.10a · EDGE §9 · RN §12 | hard gates, traceability gaps, and two registers with **no id prefix at all** |

**Two of these carry decisions that no consolidated index reaches:** `MD-n` (#15) and the unnumbered EDGE §9 /
RN §12 series (#25). Between them they hold `ODR-18`, `ODR-38`, `ODR-43`, `ODR-82`, `ODR-83`, `ODR-85`,
`ODR-86` and `ODR-87` — and `ODR-87` (notification permission priming) has **no id in any register anywhere in
the corpus**. It exists in exactly one file, in one paragraph.
