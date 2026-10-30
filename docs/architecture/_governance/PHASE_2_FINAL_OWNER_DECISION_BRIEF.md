# Phase 2 — Final Owner Decision Brief

**Corpus:** `phase2/consolidation` @ `c7376f3` · **Date:** 2026-08-28
**Method:** seven independent read-only specialist reviews (architecture/contracts, PostgreSQL/database ×2 — one via the ECC `database-reviewer` harness, security/authorization, event/notification systems, CRM/privacy, adversarial consistency).
**Nothing in the corpus was modified to produce this brief.** No migration, no freeze, no production contact, no decision resolved.

---

## 0. READ THIS FIRST — three corrections to the framing

The Final Consolidation Report named five decision groups. The adversarial review found the frame wrong in three places, and each was independently verified.

### 0.1 A sixth decision is missing, and it is the one the register itself ranks fourth

**`ODR-4` — the two global-posture exceptions on `kernel.identity_demographic`.** It blocks **`077`**, the second package. Its exceptions are **not reversible once data exists**. Its silent default is marked **UNSAFE** in the register's own words, and the third limb has no enforcement at all — *"repointing to the sentinel **is** what `019`/`020` already do, so silence plus one routine edit to `020` reintroduces the defect."*

The register's own prioritisation paragraph names it: *"If only four can be answered this week … `ODR-1`, `ODR-2` and `ODR-3`, and **`ODR-4` (blocks `077`, the second package in the chain)**."* The five dropped exactly the one the register ranks fourth. **It is added below as decision 6.**

### 0.2 Ruling these decisions does not, by itself, unblock the build

`076` is gated by `ODR-1`, `ODR-2`, `ODR-3` and `O17`; `077` is then gated by `ODR-4`; **applying** anything is separately gated by `ODR-5` (staging/apply authorization — silence is SAFE there, nothing applies). Beyond the rulings, the mechanical remediation in Final Report §8 items 1–3 must still land. **A team that rules six things today can author `076` and will stop at `077`.**

### 0.3 Order matters — rule them in this sequence

```
O11  →  ODR-2  →  ODR-3  →  O17  →  ODR-4  →  ODR-1  →  R2B-1
```

`O11` first, because six of the seven "cross-document contradictions" in the work plan **are** delta-vs-delta conflicts; ruling `O11` converts them from design decisions into transcription. `ODR-1` late, because it ratifies the outputs of the others — and `O17` option (b) would *delete* content the seventh amendment places.

---

# DECISION 1 — `O11` / `ODR-7`: precedence between same-tier specifications

## A. The decision
Two documents can give an engineer contradictory instructions about **who may approve a refund, move ticket custody, or change a money limit** — and no rule says which to believe. This picks the rule.

## B. Why you have to decide it
The corpus states it outright (ratification row `C75`): *"Ranking delta specs against each other decides which document's authority statement binds an implementer, which is an OWNER decision. It is NOT made here."* The register agrees: *"Does the corpus recommend? **No, explicitly.**"*

**Genuinely yours: the resolution rule.** **Mechanical, not yours: the detection gate** that goes with it — that is engineering with no policy content.

## C. Options
- **[A] Recency** — the later ratified correction governs.
- **[B] Subject-matter ownership** — one named owner per subject; every other statement is a derived restatement and is *the defect* on disagreement.
- **[C] Remediation-tag precedence** — where one side carries a ratified correction tag and the other carries none, the tagged text governs.
- **[D] Hybrid** — **[B]** as the rule, **[C]** as a narrow tie-breaker where the owner map is silent, **[A] abolished**, plus a mechanical restatement-completeness gate in CI.

## D. What each means
| | Behaviour | Security | Complexity | Prevents the failure that caused NOT READY? |
|---|---|---|---|---|
| **A** | compare dates, take later | blind to ownership | looks cheapest | **No** |
| **B** | look up subject → owner | correct where the map is populated | the map is the work | partially — names the gap, cannot see it |
| **C** | check which side is tagged | sound when exactly one side is tagged | lowest | **No** |
| **D** | map, then tag, then surface | strongest | one table + two scripts | **Yes — only option that does** |

## E. Failure mode
Tested against five real conflicts on record. **Recency scores 4 of 5 and is still the worst option** — it scores well only because the recent passes happened to be the ownership-aware ones, which is a confound, not a property. It is also **not mechanically checkable at all**: six concurrent passes claimed the same ratification IDs today and were renumbered by hand, so "later ratified" is a merge artifact, not a property of the text.

**[C]** is indeterminate on 2 of 5 (both sides tagged) and degrades as more passes run. **[B]** alone is silent or ambiguous on 2 of 5.

**One conflict — RPC §6.3 vs §7.1, both claiming the inventory write — is intra-document, and no precedence rule of any form reaches it.** A ratified row already hit this class and recorded *"same document, so `O11` cannot help."* It needs its own ruling regardless (Final Report §8 item 2).

## F. Corpus recommendation
**Stated: none.** **Practised: [B], six times.**

Twelve local precedence rules exist in the corpus. **Eleven of twelve are subject-matter ownership**, two of them formally `RATIFIED` with mechanical assertions (`EXEC-DERIVED` / `C60`, `HELPER-DERIVED` / `C76`), one of which inverts the freeze's own tier order so the ratification record outranks it (`C125`). **Not one rule anywhere is recency.** Choosing [B]/[D] ratifies existing practice; choosing [A] would overturn two ratified rules.

## G. Engineering recommendation
**[D].** It is two markdown parsers and one table, in the CI job that already exists — the opposite of an enterprise governance programme, and sized for a solo founder. The detection half is the part that matters: a check asserting that every ratification row's correction actually appears in each document its own sites column names. Against the real failure, `R2B`'s rows name schema, RPC, door and money; **those files contain the IDs zero times**, so the check turns that into a red build on the commit that created it.

## H. OWNER CHOICE
```
[A] Recency — later ratified correction governs
[B] Subject-matter ownership only
[C] Remediation-tag precedence only
[D] Hybrid: ownership map + tag tie-breaker + CI detection gate; recency abolished

RECOMMENDED: D
```

---

# DECISION 2 — `ODR-2` + `ODR-3`: the event outbox and the `notify` schema

## A. The decision
**Outbox:** one small table you drop a "this happened" note into, *inside the same transaction as the money write*, drained a couple of minutes later by a background job. **`notify`:** a nine-table notification platform (23 RPCs, 2 edge functions, 2 cron jobs, 2 client surfaces). Ruled together, outbox first.

## B. Why you have to decide it
Saying no to the outbox makes named capabilities **unbuildable**, not degraded — Apple Wallet push *"has no admissible alternative design, since both fallbacks are prohibited by ratified invariants."* And nine tables plus two client surfaces is a real programme. Both are scope-and-cost calls.

**Mechanical, remove from your set:** the schema *name*; whether push tokens extend `public.push_tokens` (two documents already answer identically — *"a second token table creates a split-brain"*); the package number.

## C. Options
Fixed by `COND-D`. Only three combinations are coherent:
- **[A]** Outbox IN + `notify` IN — the full design. Band becomes `076`–`092`, 17 packages.
- **[B]** Outbox IN + `notify` OUT — outbox at `076`, `notify` stays Gate L. Band stays `076`–`091`.
- **[C]** Both OUT — requires amending the constitutions to withdraw the promise.

*(`notify` IN + outbox OUT is incoherent — the notify design **is** an outbox pipeline.)*

## D. What each means
**[A]** Mobile notification centre, working preferences, undisableable money/security notices, venue announcement composer, email/SMS-ready. Costs the largest single package in the programme, two more cron jobs on a path with **zero Sentry coverage**, and two RPCs that currently have **no contract body at all**.

**[B]** Unblocks Apple Wallet push, the door-manifest open transaction and scanner push-to-sync. Notifications continue on the production path. Venue dashboard §16.5 must be re-scoped. Preferences stay inert.

**[C]** Apple Wallet ships without a working push path, or not at all; the door-manifest open transaction *"cannot be authored as specified."*

## E. Failure mode
- **[A]** — the complexity is the failure mode. A cron that silently stops: **this codebase has done it twice.**
- **[B]** — native purchase confirmations must be scheduled explicitly, or buyers get a ticket and silence. Inert preference toggles carried forward knowingly.
- **[C]** — a previous owner keeps a live Wallet pass. That is a **door-fraud primitive** on a custody platform.

## F. Corpus recommendation
**Split, and the split is on the record.** `NOTIFICATIONS` §10 says *"Build it."* The registry and schema spec **decline to recommend**. The schema spec refuses on principle: *"This is a conditional package element and this integration does NOT decide it."* But it closes the option space: *"There is no third option in which DA:1253 stands and nothing implements it."*

Both defaults-on-silence are marked **UNSAFE** in the register.

## G. Engineering recommendation
**[B].** Three reasons specific to Snatch It:

1. **The money-safety property this is nominally about is already solved in production, and you bought it the hard way.** Migration `054`'s header records that a notification side effect with no exception handler aborted the parent transaction — **competitive bidding was silently dead from Feb to Aug 2026.** The fix is now the house discipline: `enqueue_notification` is non-raising, idempotent, service-role-only and in-transaction; outbound HTTP goes via `pg_net` after commit. `notify` does not buy that property. It buys preference enforcement, delivery observability, retry and a mobile inbox — real product value, priced as a feature.
2. **The outbox is the expensive thing to retrofit; `notify` is not.** Adding an outbox later means reopening every money and custody producer. Adding `notify` later is purely additive.
3. **Wallet forces the outbox on security grounds**, independent of notifications.

**Conditions if [B]:** Sentry on the drainer day one; a `done`-row purge in the drainer; native-purchase notification producers scheduled; re-scope dashboard §16.5.

## H. OWNER CHOICE
```
[A] Build both — outbox at 076 + notify platform at 092 (band becomes 076-092, 17 packages)
[B] Outbox only — kernel.event_outbox at 076, notify stays Gate L (band stays 076-091)
[C] Build neither — amend the constitutions to withdraw the promise

RECOMMENDED: B
```
**Before ruling:** close `G-25`. Ratified `C11` trimmed the event catalog from 36 to ~16 and **no document says which sixteen survive.** You are currently pricing a list a ratified correction already cut by more than half. The register says so: *"Fix this before ruling on `ODR-2`."* ~1 hour of engineering.

---

# DECISION 3 — `O17` / `MD-2`: the `crm_export_builder` Postgres role

## A. The decision
Venues download a CSV of who is coming. One function assembles it. Today every privileged function runs as `postgres` and can read **every table** — including the four holding attendees' self-reported gender and demographic data, which the export is forbidden by rule (`X-6`) from ever touching.

Run **this one function** as a deliberately weak login with read access to exactly the tables it needs? Then a future engineer reaching for demographic data gets a **runtime permission error** instead of a CI finding.

## B. Why you have to decide it
It **deviates from a frozen global** (*"`SECURITY DEFINER`, owned by `postgres`"*, stated for every function in the system), it changes what ships in **six** packages, and four independent sites record it as open.

**Note on the "Adopt" you may have seen:** it sits in a column headed **Recommendation**, and the corpus records that *"the word 'Adopt' alone read as a ruling and was cited as one."* **No owner has ruled.**

## C. Options
- **[A]** Adopt as specified — role + 13 grants + 12 policies + canary.
- **[B]** Stay `postgres`-owned — `X-6` rests on the three detective layers.
- **[C]** Adopt, gap-closed — [A] plus three fixes below.

*(`BYPASSRLS` is refused in four places as a named non-option.)*

## D. What each means
**Correcting a premise:** the role does **not** make the consent gate safer. The gate is an in-body four-part conjunction that suppresses on anything missing — it works identically under either option. **RLS subjection is a hazard here, not a safeguard:** a role subject to RLS reading a table with RLS on and no policy reads **zero rows**.

So the role buys exactly one thing: **`X-6` becomes structurally impossible to violate rather than merely detectable.**

**On realized privacy the two options are equivalent** — the CSV, the bucket and the retention window are where the risk lives, and neither option touches them. On *bounded* privacy [A] is better in principle and, as written today, not better in fact.

## E. Failure mode
**[A] as specified:** ship the role with fewer than 12 policies → the export succeeds, its own invariant balances at `cells_emitted = 0`, and the file ships with **every name and email blank** — which reads to a venue as *"nobody consented,"* not as *"the query was denied."* Nothing alerts. **The trap is already laid: the migration plan names 3 of the 12 policies.**

Three gaps found in the wall itself:
- The "closed twelve" grant set **does not cover six relations the builder demonstrably reads**.
- **`kernel.identity_ext` is granted whole-table**, and its only substantive columns are `kyc_ref` and `residency_region` — *both on the export's own never-exported list*.
- **Nothing asserts any of it** — no closed-world test on the grant set, none that `rolbypassrls = false`, none that it holds no write anywhere.

**[B]:** an engineer adds a demographic reference and the grep misses it (dynamic SQL, a rename, a view, a nested function). **This repo has already shipped exactly that class of vacuous check** — migration `073`, where *"every audit that read the migration source concluded the limits were in place. They were not."*

## F. Corpus recommendation
**Adopt, conditionally** — in four places, always qualified: *"D-2 cannot be answered 'adopt it' without also adopting the enumeration and the canary."* And **five** places insist no decision has been taken.

**Documents disagree on the deadline.** Four say *"before `087`"*; the corpus at head puts the `CREATE ROLE` in **`076`**. `SEAM-4` forces it — a `GRANT` resolves its grantee immediately, so the first grant in `077` is a hard `42704`. **This decision gates the first migration, eleven packages earlier than three documents advertise.**

## G. Engineering recommendation — **TWO SPECIALISTS DISAGREE. Read both.**

This is the only decision in the brief where the reviews split, and the split is worth your attention because
the second reviewer found four **more** blocking gaps than the first.

### Position 1 — CRM/privacy reviewer: **adopt, gap-closed [C]**
`X-6` is a promise about a **protected class**; the three detective layers all depend on a human noticing a CI
diff; and the retrofit cost is asymmetric — adding the wall later means dropping and recreating twelve policies
across five already-applied packages in production. Twelve one-line policies is one afternoon, front-loaded.

### Position 2 — ECC `database-reviewer` (independent Postgres lens): **stay `postgres`-owned [B]**
It accepts that the role buys something real — a `postgres`-owned definer on Supabase carries `BYPASSRLS`, so a
bug that loses the consent row emits **all** contact cells, whereas under the role RLS is a second fail-closed
gate. Then it found four further gaps that no previous pass caught:

- **The grant set is `SELECT`-only, and the builder is a documented *writer*** of `venue.export_job` — it
  accumulates the four gate counters page by page. That is `42501` on the first page. **And the repair is
  blocked from both sides:** an `UPDATE` grant without a policy updates zero rows *silently*, and adding an
  UPDATE policy fails `T-RLS-POL-05` (*"no Phase-2 table carries an INSERT, UPDATE or DELETE policy"*).
- **No `GRANT USAGE ON SCHEMA` to the role exists anywhere in the corpus.** Table privileges without schema
  `USAGE` are inert — `42501` before any policy is reached. The enumeration only ever counted tables.
- **`auth.users` gets a grant and no policy**, and `public.profiles` (verified against the live migrations) has
  RLS with a `TO authenticated` policy. Under the role both read **zero rows** — every email and every
  `display_name` blank. The reason no existing definer notices is that `postgres` carries `BYPASSRLS`, which is
  precisely the attribute the new role must not have.
- **`kernel.tickets` has no index on `org_id`**, while the contract calls `org_id` *"this function's FIRST
  predicate, on every branch."* At org grain there is no session anchor, so the driver is a sequential scan of
  every atom on the platform.

**Its decisive argument is about which way each option fails, and it runs opposite to the intuition:**
`postgres`-owned fails **open** on a *consent* bug — loud in the product, and caught by a fixture that is
already specified. Role-owned fails **closed and silent** on a *privilege* bug, and **the only detector covers
1 of the 21 export columns.** A silently-empty `checked_in` column is caught by nothing in this design and
reads to a venue as *"nobody scanned in."*

Its second argument is about convergence: **four independent passes have now enumerated this grant set and
produced four different lists** — ten, then twelve, then the `auth.users` grant that appeared in no list, then
`C115` finding the grants were in no package at all — and this review adds four more. Under `postgres`
ownership every one of those findings is a non-event, because the grant set and the policy set are both empty
and nothing has to stay in sync.

It also notes that `GP-3a` already put the entire money plane behind `EXECUTE` on `postgres`-owned definers
where no table policy ever runs, and the corpus is not weaker for it — it moved its assurance to structural
assertions over `pg_proc`. The consistent move here is the same one.

### My synthesis
**I now recommend `[B]`, with the `X-6` assurance strengthened rather than the wall built.** The deciding
factor is not the count of gaps but what the count *means*: an enumeration that four careful passes could not
converge on is not a boundary anyone will keep correct as the product grows — and `090` already proves it, by
bringing three new relations into the read set with no grant row. Meanwhile the thing actually worth having —
*"a demographic reference is a runtime error"* — does not require **this** role; it requires **any** owner
lacking those grants, and it can be asserted over the catalog far more cheaply than twelve policies can be
kept in sync.

`[C]` remains defensible, and Position 1's protected-class argument is not wrong. Choose it only if you will
close **all** of C-1…C-4 and H-1/H-4 before `076` — not as a follow-up.

## H. OWNER CHOICE
```
[A] Adopt Layer 0 as currently specified
    -- not recommended by either reviewer; the wall has four known holes

[B] Stay postgres-owned; X-6 rests on the detective layers, strengthened with
    catalog assertions (empty demographic grant set, rolbypassrls=false)
    -- ECC database reviewer's recommendation; my synthesis

[C] Adopt, gap-closed -- [A] plus, ALL before 076 is authored:
      1. re-derive the relation set from the builder's actual read path
         (7 relations missing: profiles, ticket_type, ticket_ownership_log,
          scan, organization, attribution/promoter_link/promoter)
      2. GRANT USAGE ON SCHEMA kernel, catalog, venue, auth
      3. resolve the venue.export_job WRITE (counters) -- grant+policy, or
         route it through a postgres-owned helper
      4. verify relrowsecurity on auth.users and public.profiles; policy them
         or route those two reads through a narrow helper
      5. column-scope or drop kernel.identity_ext (kyc_ref, residency_region)
      6. assert rolbypassrls=false, rolsuper=false, and the empty demographic
         grant set over the catalog -- currently prose in five places, zero tests
      7. extend the blank-column canary past the contact column (1 of 21 today)
      8. fix the migration plan to enumerate all twelve policies, conditionally
      9. correct the HG-4 deadline from 087 to 076
    -- CRM/privacy reviewer's recommendation

RECOMMENDED: B   (revised -- the brief as first published said C)
```
**Independent of the ruling:** `kernel.tickets` needs an `(org_id, event_session_id)` index, or the org-grain
driving path must be stated. And **under no ruling may the role ship without all twelve policies.**

**Two facts to check on a branch before ruling** — both single queries, both load-bearing:
`select relrowsecurity from pg_class where oid = 'auth.users'::regclass;` and
`select rolbypassrls from pg_roles where rolname = 'postgres';`

---

# DECISION 4 — `ODR-4`: the `kernel.identity_demographic` posture exceptions *(ADDED — was missing from the five)*

## A. The decision
The demographics table takes **two documented exceptions to global security posture**, and they ship inside package `077`. This acknowledges them — or refuses them.

## B. Why you have to decide it
`HG-8`: *"must be acknowledged before `077`."* **Neither is reversible once data exists.** Silence is marked **UNSAFE, and specifically so** — the third limb has no enforcement at all, and *"silence plus one routine edit to `020` reintroduces the defect."* The register still shows it `OPEN — owner`, and the sign-off scope **widened from four relations to six** without being re-taken.

## C. Options
Acknowledge as specified · acknowledge with the widened six-relation scope explicitly re-signed · refuse and require the exceptions removed before `077`.

## D–G
**Not analysed in this pass.** `ODR-4` was outside the five this brief was scoped to, and it was found by the adversarial reviewer at the end. Its register entry carries the options, the breakage per option and the silence default. **It needs one specialist pass before you rule it** — that is the honest statement, and inventing an analysis here would be worse than admitting the gap.

## H. OWNER CHOICE
```
DEFERRED PENDING ONE SPECIALIST PASS — do not rule blind.
Blocks 077. Irreversible once data exists. Silence is UNSAFE.
```

---

# DECISION 5 — `ODR-1`: package-registry re-ratification

## A. The decision
The registry has taken **seven** amendments today, each marked pending re-ratification, because its own rule says it is *"updated only by ratified amendment."* This signs them off.

## B. Why you have to decide it
**Mostly you don't — this is bookkeeping over an already-verified structure.** But the registry declines to self-ratify, and two of its contents are not derived: the package *count* turns on `ODR-3`, and the `crm_export_builder` placement is expressly contingent on `O17`.

## C–E. SPECIAL CHECK — is this still a substantive choice?

**Verified independently, at head, by parsing the documents:**

| Property | Result |
|---|---|
| Package count | **16** |
| Band | `076`–`091`, **0 gaps, 0 duplicates** |
| Declared edges | **45**, matching the JSON field |
| **Set-equality across all four surfaces** | **PASS** — all four enumerate the same 45 |
| Every dependency strictly precedes its dependent | **PASS**, all 45 |
| DAG acyclic | **PASS** |
| Package set identical across **seven** surfaces | **PASS** |
| All 8 SEAM-2 stub→replacement edges declared | **PASS** |

**No amendment renumbered any package.** Five of seven are pure bookkeeping; one is a forced object move; **only the seventh changes what an implementer builds where.**

**Verdict: `ODR-1` is mechanical as to the thing it names. Do not reopen package numbering — there is no defect that warrants it.**

**But a bare "ratify the current registry" is the wrong signature, for three reasons of record:**
1. **`ODR-3` can falsify it.** A Gate-P `notify` makes the band `076`–`092` / seventeen and explicitly falsifies the "no gaps, no duplicates" assertion.
2. **The instrument stating `ODR-1` is stale.** It describes *"the six amendments"* and a *"38-edge"* graph. There are **seven** and **45**. You would be signing a description that no longer matches the artifact.
3. **Two edge declarations are owed** — `078 → 086` (recorded OPEN precisely because fixing it needs an amendment) and `077 → 090` (recorded nowhere). Both declaration-only, both strictly increasing, neither changes rollout order, placement or rollback posture.

## F. Corpus recommendation
The registry says of itself, six times: *"No change here is an owner **decision**."* Function placement is *"derived, not chosen."*

## G. Engineering recommendation
Ratify conditionally, and absorb the two owed edges into the same amendment.

## H. OWNER CHOICE
```
[A] Ratify unconditionally as-is
[B] Ratify all seven amendments — band 076-091, 16 packages, 45 edges —
    CONDITIONAL on ODR-3 (a Gate-P notify reopens this for that delta alone),
    with two declaration-only edges absorbed: 078 -> 086 and 077 -> 090 (45 -> 47)
[C] Reopen package numbering

RECOMMENDED: B
```
**This ratification does not authorise authoring `076`**, which stays gated on `O17` and `ODR-2`.

---

# DECISION 6 — `R2B-1`: the `p_cause` parameter, frozen at `085`

## A. The decision
When a ticket is killed, the kernel tells the resale marketplace to reverse the sale, via `market.on_atom_voided`. That function is built in two stages — an empty shell in `085`, the real body in `088`. PostgreSQL will not let you change a function's **shape** between those stages: rename an argument and `088` dies; add or remove one and Postgres **silently creates a second function**, leaves the empty shell live and bound to every call site, and the migration **replays green** while the compensation never runs.

The shell takes a third argument, `p_cause`. **No document says what values are legal or what it does with them.**

## B. Why you have to decide it — and how much of it is actually yours
**One bit is genuinely yours and genuinely irreversible: does a third parameter exist at all?**

**Everything else is mechanical and the corpus already settles it:**
- `text` + `CHECK`, never a native enum — schema §12.3, asserted.
- Never client-supplied — the hook is `service_role`-only, and classification values on money paths are *"never a parameter."*
- No new vocabulary — ratified `D3` is *"THE one canonical cause-code registry … any other cause list is a tagged subset of it."*

**And a correction to the deadline framing: `SEAM-2a` freezes only the parameter's *existence*, name, type and return type — not the value set.** A parameter cannot carry a table CHECK; validation lives in the body, and `CREATE OR REPLACE` is explicitly allowed to change the body. **Widening the value list later costs one `CREATE OR REPLACE` plus a CHECK swap.**

## C. Options
- **[A]** Drop it — two-parameter signature.
- **[B]** Keep, descriptive, D3's 13 labels.
- **[C]** Keep, descriptive, closed to the six `kernel.refund.reason_code` labels, server-derived, **renamed `p_reason_code`**.
- **[D]** Keep, authority-bearing — the value gates whether a `completed` sale can be voided.
- **[E]** Keep, free text, no CHECK — *this is what silence produces.*
- **[F]** Keep, purpose-built 2-value set.

## D–E. What each means, and what breaks
**The parameter is currently inert:** nothing reads it anywhere — no Writes row, no test — and `market.market_sale` has **no column that could store it**. Its sole caller derives `cause := 'refund_void'` as a **constant on every path**, so under [B] a D3 code carries **zero bits, forever**.

The informative value is a different column: `kernel.refund.reason_code`, six labels, which the schema explicitly calls *"distinct from the ownership cause, which is always `refund_void`."*

- **[A]** cleanest architecture — but a zero-money force-void may leave **no refund row to derive from**, and that is exactly the fraud path where an operator most needs to know why a sale was reversed.
- **[D]** puts a string in charge of whether the compensate-XOR-complete invariant is enforced. **Not in the first cut.**
- **[E]** unvalidated string on a custody/money compensation path. Nothing in the corpus authorizes it; the nearest precedents are the opposite.
- **[F]** creates a seventh cause vocabulary half-overlapping an existing one — a defect class **already realized twice** in this corpus.

## F. Corpus recommendation
**None on the value set** — explicitly filed out. But its constraints rule out [E] (closed sets on money paths) and [F] (one cause registry), and make [B] uninformative.

## G. Engineering recommendation
**[C], with the rename.** Keeping a validated string on a `service_role`-only path is cheap; a missing argument you needed is not, and you get no second chance at `085`. Reuse the ratified six-label vocabulary rather than inventing a seventh. **The rename is the part worth insisting on:** every other `cause` in this system is a D3 code, this one can never hold one, and the name is frozen the moment `085` applies.

## H. OWNER CHOICE
```
[A] Drop it — market.on_atom_voided(p_atom_id, p_refund_id)
[B] Keep, D3's 13 labels (always 'refund_void' in practice)
[C] Keep, renamed p_reason_code, closed to the six kernel.refund.reason_code labels,
    server-derived, descriptive only:
      buyer_request · event_cancelled · oversell_correction ·
      dispute · admin_action · auto_compensation
[D] Keep, authority-bearing (requires a C26 amendment)
[E] Keep, free text (the silence default)
[F] Keep, purpose-built 2-value set

RECOMMENDED: C
```
**Ships with it regardless:** propagate the arity repair into the five documents the seventh amendment skipped, or `088` either fails hard or silently overloads.

---

## Appendix — decisions removed from the owner set as mechanical

| Item | Why it is not yours | Where it is already settled |
|---|---|---|
| The `notify` schema *name* | costs nothing either way | `NOTIFICATIONS` §1.8 reading (a) |
| Push tokens: new table or extend `public.push_tokens` | two documents already answer identically | schema §13.4, `NOTIFICATIONS` §10 |
| `p_cause`: enum vs `text`+CHECK | banned corpus-wide, asserted | schema §12.3 |
| `p_cause`: may a client supply it | `service_role`-only, definer | RLS §11 |
| `p_cause`: new vocabulary permitted | *"any other cause list is a tagged subset"* | `D3` |
| Package number arithmetic | SEAM-1…SEAM-4, *"derived, not chosen"* | registry §6.6 |
| The `O11` detection gate | engineering, no policy content | Final Report §8 item 6 |

## Appendix — prerequisites to close before ruling

| # | Item | Cost | Blocks |
|---|---|---|---|
| 1 | **`G-25`** — mark which ~16 of the 36 catalogued events survive ratified `C11` | ~1 hour | pricing `ODR-2` |
| 2 | Correct the `HG-4` deadline from `087` to `076` in three documents | minutes | `O17` being read as eleven packages away |
| 3 | Rebuild the owner-decision register at head — it is 53 commits stale and does not know `O17`, `O18` or `R2B-1` | ~1 hour | the accuracy of every band |
| 4 | One specialist pass on **`ODR-4`** | one pass | ruling `ODR-4` |

## Appendix — what was verified as sound

The registry's structural integrity (16 packages, 45 edges, four-surface parity, acyclic, seven-surface package-set agreement, all 8 SEAM-2 edges declared). The `COND-D` coherence argument. The `O17` "one silently wrong combination" stated identically in four documents with no drift. That all five original decisions are genuinely still open at head — every remediation pass explicitly states it decided nothing owner-owned. And that `supabase/migrations/` is unchanged since the consolidation baseline.
