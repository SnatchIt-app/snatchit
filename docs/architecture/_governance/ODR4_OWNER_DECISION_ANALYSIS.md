# `ODR-4` — Owner Decision Analysis

**Subject:** the global-posture exceptions on `kernel.identity_demographic` and the contact/consent relations
**Corpus:** `phase2/consolidation` @ `269e473` · **Date:** 2026-08-28
**Method:** four independent read-only reviewers — PostgreSQL/database mechanics, security/authorization, privacy & data governance, adversarial architecture. Two carried ECC agent prompts. No database was contacted; no file in the corpus was modified to produce this.
**Status: NOT READY FOR A SINGLE RULING AS FRAMED.** Not because the question is hard, but because the question as posed is wrong in five specific ways, three of which the reviewers falsified against the corpus.

---

## 0. The headline, before the detail

Four reviewers, four lenses, and they converge on findings none of them was briefed to look for.

**Both exceptions are privacy-positive.** They are the *only two mechanisms in the design by which a gender answer ever physically leaves the database*. Refusing either does not make the data safer — **it makes the data undeletable.** The privacy reviewer put it plainly: *"A refusal of ODR-4 is not a conservative ruling — it is a ruling that this data cannot be deleted."*

**But the exception cannot currently execute.** Two of the relations in scope are append-only ledgers carrying `raise_append_only()` triggers. A referential cascade **is** a DELETE on the referencing table and **fires its row triggers** — so from `077`, account deletion aborts for any identity that ever touched the contact master switch, which is essentially every fan. `RESTRICT` was rejected precisely because it *"would make an account deletion fail on the log of a permission the account already withdrew."* **CASCADE as specified produces the identical failure one layer down.**

**And its compensating control is not in the package.** The `BEFORE DELETE` tombstone trigger — the entire mitigation for the cascade — is specified in the demographics spec and **contradicted** by the migration plan, which states the table carries *"exactly one trigger, the `updated_at` maintainer, and nothing else."* The registry lists no trigger. The physical schema spec does not define the table at all. **Two reviewers found this independently, from different lenses.** Signing the exception while its only control is absent from the package is signing a bare exception.

---

## 1. What the two exceptions are (VERIFIED, quoted)

`PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §10.2:

> **"GP-2 (`DELETE` denied everywhere) is excepted** for this table *inside the definer RPC only*. Clients still hold zero DELETE. The justification is §8.2/§8.3: keeping a withdrawn gender answer as a tombstoned row would defeat the withdrawal, and this table references no ledger."

> **"The `ON DELETE RESTRICT` FK default is excepted** in favour of `ON DELETE CASCADE` from `auth.users`. Justification: an orphaned demographic answer belonging to a deleted account is the worst possible residue, and `VERIFIED:` cascade-from-`auth.users` is already the house pattern (012/023/033)."

**The rule both violate is one sentence** — `PHASE_2_RLS_PERMISSION_SPEC.md` §1.3: *"**GP-2 — DELETE is DENY for every role on every table.** All FKs are `ON DELETE RESTRICT`."* Exception (i) violates its first clause, (ii) its second. That they share a sentence is why they were filed as one decision — and is not a reason to rule them together.

**A third source nobody cites:** `SNATCH_IT_CANONICAL_DATA_MODEL.md` §10, declared *constitutional*, rule 4 *"tombstone, don't erase"* and rule 9 *"Deletion is archive/anonymize, never a dangling pointer."* The hard DELETE is therefore **also a constitutional exception**, and limb 3 (never repoint to the sentinel) **contradicts constitutional rules 1 and 9** — which is *why* it has no enforcement: the constitution points the implementer the other way.

**The house-pattern claim was checked and holds.** `012`, `023` and `033` all carry `ON DELETE CASCADE` to `auth.users`. That `VERIFIED:` badge is true.

---

## 2. Five claims in the framing that are false or overstated

### F1 — *"the single GP-2 exception in the model"* — **FALSE**
Six sites say one exists and *"a second must not be granted by analogy."* `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §20.5.5 grants a second, explicitly: *"This is a second named GP-2 exception and it is granted narrowly, **on the same reasoning as the first**."* That phrase **is** by analogy. `RPC` §0.5 contradicts itself internally on the same point.

**Consequence:** you are being asked to grant "the single exception" on a uniqueness premise that is already void. The correct question is *"ratify a two-member exception class and its closure rule."*

### F2 — *"scope widened from four to six relations"* — **FALSE, and one option is unsignable**
The count appears in two documents and is **enumerated in neither**. Reconstructed: the original cascade scope is **two** (`identity_contact_pref`, `org_contact_consent`), becoming **four** with the two `_event` ledgers. The "four" in "four to six" was a *canonical-inventory* tally, silently relabelled as the sign-off scope.

Of the six as commonly listed, **`kernel.org_customer_key` has no `auth.users` FK at all** and **`venue.export_job.requested_by` carries `ON DELETE RESTRICT` — the opposite of the exception.** The option offered in the owner brief — *"acknowledge with the widened six-relation scope re-signed"* — **would have you sign a CASCADE exception over relations that do not carry one. That option is withdrawn.**

### F3 — *"neither is reversible once data exists"* — **overstated, and asymmetric**
Both are catalog-only reversals. Exception (i): `CREATE OR REPLACE FUNCTION` — no dependency on data at all. Exception (ii): `DROP CONSTRAINT` + `ADD CONSTRAINT … ON DELETE RESTRICT` — every surviving row already satisfies it; brief lock, no rewrite. The registry's own rollback posture for `077` is **`CLEAN_WHILE_EMPTY`**, not forward-fix-only.

**Honest restatement:** the schema is reversible in both directions. What is irreversible is **rows already destroyed** — which per §8.2/§8.3 is the *intended* outcome. This is expensive-and-embarrassing, not technically irreversible, and it should not carry the urgency weight the framing gives it.

### F4 — *"silence is UNSAFE — one routine edit to `020`"* — **mechanism real, causal arrow backwards**
`020` needs **no edit at all** for the cascade limb: the cascade fires in `auth.admin.deleteUser`, four calls later in the edge function, which nobody has to touch. And `020`'s pattern applies only to tables whose rows must *survive* deletion — under CASCADE the demographic row exerts no such pressure.

**The path that actually forces the repoint is refusing the cascade.** Under `RESTRICT`, deletion fails and the sentinel is the obvious house-pattern fix. **Limb 3's risk is a consequence of ruling *against* limb 2, not of silence on it.**

### F5 — *"blocks `077`"* — **true only by placement, and placement is movable**
`077` is twelve tables; demographics is a rider on a package whose stated purpose is *"organizations + permissions + dual-control substrate."* The **only** downstream reader is `refresh_holder_mix`, nine packages later. Moving objects between **existing** packages is precedented and ratified — the seventh amendment moved two functions under *"NO package added, renamed or renumbered."*

**The caveat that kills the lazy version:** the three demographic RPCs are also in `077`, and demographics has **no runtime kill switch** — *"gated only by package application, which is a deploy and not a runtime control."* So *"apply now, decide later"* is **not** available. Deferral or a flag is.

---

## 3. What the reviewers found that nobody was looking for

### 3.1 The cascade cannot execute — **CRITICAL** (database lens)
`kernel.identity_contact_pref_event` and `kernel.org_contact_consent_event` are declared **AO — INSERT-only, `raise_append_only()` trigger, `REVOKE UPDATE, DELETE`** — while carrying `identity_id → auth.users` **`ON DELETE CASCADE`**. A referential cascade fires row triggers. `REVOKE DELETE` does not stop a cascade; **the trigger does.**

From `077` (and again at `082`), `auth.admin.deleteUser()` aborts for any identity with an event-log row — and the preference RPC *appends unconditionally*, so that is nearly every fan. The `K-2` repair added the FK and the append-only posture **in the same subsection** without noticing.

*Fix:* split the guard — `raise_no_update()` `BEFORE UPDATE` for these two, privilege (`REVOKE DELETE FROM PUBLIC, anon, authenticated`) carrying the no-client-DELETE half. Client DELETE stays impossible; the RI cascade proceeds. Add an assertion that deleting an `auth.users` row with N event rows **succeeds** and leaves zero.

### 3.2 The tombstone trigger is not in the package — **CRITICAL** (found independently by security and database lenses)
| Document | What it says |
|---|---|
| demographics spec §8.2/§10.2, assertion 25, ratified `C64` | **exactly two** triggers: `updated_at` + the `BEFORE DELETE` tombstone writer |
| **migration plan `077` Triggers row** | *"**exactly one trigger — the `updated_at` maintainer — and nothing else**"* |
| package registry `077` | no trigger, no trigger function |
| physical schema spec | **no definition of the table at all** |

A ratified correction (`J-12`) already moved tombstone-writing *out of* the withdrawal RPC and into the trigger. Built as the plan is written, **no removal path writes any tombstone** — not withdrawal, not cascade — and it fails **silently**: the DELETE succeeds and nothing errors. That is strictly worse than the defect `C64` was ratified to fix.

### 3.3 The tombstone is an UPSERT into an append-only table — **CRITICAL** (database lens)
Specified as *"a `BEFORE DELETE` trigger that **upserts** the erasure row"*, into a table declared **AO with PK `identity_id`**. Answer → clear → answer again → clear: the `ON CONFLICT DO UPDATE` performs an UPDATE, `raise_append_only()` raises, the exception propagates, **and the withdrawal RPC refuses to withdraw.** `ON CONFLICT DO NOTHING` is silently wrong instead — `purge_after` never advances.

The table also has **two incompatible physical definitions** — `SPEC_FOUNDATION` gives PK `id`, the demographics spec gives PK `identity_id`. That decides whether the tombstone is one-per-identity or append-many, and therefore whether AO is even the right class.

### 3.4 The tombstone has no reaper, and its window is undecided — **HIGH** (privacy lens)
`purge_after` is `NOT NULL timestamptz` = `erased_at + {N} + margin`, where `{N}` is **open decision `D-6`**. There is **no purge job, cron entry, function or index anywhere in the sixteen packages.**

§8.5 offers the self-purge as one of exactly three mitigations for the tombstone's acknowledged privacy cost (*"it reveals that a given identity once answered and later withdrew"*). **One of the three has no writer.** As specified the tombstone is **permanent** — and a `NOT NULL` column whose value is an undecided constant cannot be authored at all.

### 3.5 The cascade is inert under one admissible answer to the account-deletion decision — **CRITICAL** (privacy lens, confirmed by adversarial lens)
`O15`/`ODR-16` has three admissible forms. Form **(a) tombstone the identity** *retains* the `auth.users` row. **A retained row means `ON DELETE CASCADE` never fires** — so the demographic answer **survives account deletion indefinitely**, and the tombstone trigger writes nothing.

The compensating mechanism named in (a) is C15 crypto-shred — which is **`RATIFIED-MODELED-ONLY`, Gate L, not built in Phase 2.** So under `O15`(a) there is **neither cascade nor crypto-shred**, and §8.5's binding fan-facing copy — *"we delete it from Snatch It's database right away"* — ships false for account deletion.

**Ruling `ODR-4` before `ODR-16` risks granting an irreversible-sounding exception to a mechanism a later ruling makes dead code.**

### 3.6 The live deletion path half-completes, irreversibly, with no detector — **CRITICAL** (privacy + database lenses)
`supabase/functions/delete-account/index.ts` makes **four separate calls in no transaction**: cleanup RPC (commits) → bids → storage → `auth.admin.deleteUser`. Only the last fires any cascade. If it fails, the function returns *"contact support"* and stops — **financial rows anonymized, bids gone, avatars gone, account still live, no retry, no reconciliation, no tombstone.** Nothing anywhere queries for *"cleanup ran but the user still exists."*

Deletion is also **refused with 409** if the user has any pending transfer, with no queue and no "delete when clear" path.

From `079` this gets worse: every identity column becomes `ON DELETE RESTRICT`, so the final call raises `23503` **after** the cleanup already committed. **Deletion does not stop working — it half-works, irreversibly, on every attempt.**

### 3.7 The scope cannot be listed — **HIGH** (all three non-adversarial lenses)
Three reviewers independently could not enumerate the six. Five are nameable with citations; the sixth is stated nowhere. **An acknowledgement whose subject cannot be enumerated is not an acknowledgement** — and the `DELETE` exception covers **one** relation while the CASCADE covers a different set, so a single count cannot describe both.

### 3.8 Limb 3 is not an owner decision — **all four lenses agree**
It can be enforced with `CHECK (identity_id <> '00000000-0000-0000-0000-000000000000')` on each relation in scope, plus extending the standing assertion the corpus **already wrote for the custody side** — whose justification applies verbatim: *"the shortcut is taken at whichever call site the implementer happens to be looking at."*

**This is the one genuinely time-critical item.** The CHECK is free while the tables are empty and **impossible after a single row has been repointed** — `VALIDATE CONSTRAINT` then fails, and the repair is not a migration but a merged sentinel row with no recorded pre-image. Unlike custody, **there is no ledger to reconstruct from.**

Per-relation urgency differs and no document says so: `identity_demographic`'s single-column PK makes a repoint fail loud on the *second* occurrence — after one person's answer is already welded to "Deleted User." **`org_contact_consent`'s composite PK gives no tripwire at all**, and accumulates silently — the literal *"consent granted to 40 orgs"* row the export gate would evaluate.

---

## 4. Also established

**Collection is genuinely minimal and coercion-resistant.** No demographic question at signup, first launch, onboarding or any purchase flow; one dismissible card in the fan's own settings, at most once per 90 days and **at most three surfacings ever**; one field, five closed values, **no free text**; `prefer_not_to_say` stored but never a published bucket, so an explicit decline is byte-identical at every readable surface to never having opened the screen. Dark patterns are enumerated and banned specifically. **The privacy reviewer called this the strongest privacy work in the corpus, and I see no reason to discount that.**

**Neither exception is needed for the product.** Capture, the subject's own read, and the entire venue-facing rollup work identically with or without them. **The trade is not "privacy vs product" — it is "subject rights vs schema uniformity."**

**Exception (i) may not be strictly necessary.** `UPDATE … SET gender_identity = NULL` erases the value, needs no GP-2 exception, no `BEFORE DELETE` trigger and no separate erasure table. Its cost is that `first_answered_at` reveals the person once answered — **which is exactly what the tombstone reveals**, except the tombstone was supposed to self-purge and (3.4) does not. The corpus never states this comparison. **The DELETE is still cleaner; it is not the only option, and you are granting an irreversible-sounding precedent on a protected class.**

**Four of the corpus's six retractions are against this one document's anonymity arguments** — all found in a single remediation pass, all after it was marked BUILD-READY. The real per-bucket anonymity bound was **≥3, not ≥5**, restored only by adding a distinct-identity limb. One retraction carries its own lesson: *"this is the class of claim a reviewer stops checking once it is written down."* **Of the nine anonymity rules, exactly one is a database constraint; five are re-derived fail-closed at read; four are writer-only prose.**

**Two gaps that are not `ODR-4` but will land on you:** there is **no retention limit** on demographic rows and no re-consent cadence; and there is **no capture kill switch** — the design can stop *showing* the data instantly and cannot stop *taking* it at all.

---

## 5. The option set

> **`[1]` Acknowledge both exceptions as specified.**
> Rejected by all four reviewers **in this form** — not on the merits of the exceptions, but because (3.1) the cascade cannot execute, (3.2) its compensating control is absent from the package, and (3.3) the tombstone as specified raises on the second withdrawal.

> **`[2]` Acknowledge with the "widened six-relation scope" re-signed.**
> **WITHDRAWN — unsignable.** Two of the six carry no cascade; one carries the opposite (`RESTRICT`). See F2.

> **`[3]` Refuse the exceptions.**
> Makes privacy **worse**, not better: withdrawal stops being withdrawal, and under `RESTRICT` account deletion fails outright for anyone who answered — so the person who asked to be erased keeps both their answer **and** their account. It also **forces** the `020` sentinel edit that limb 3 exists to forbid.

> **`[4]` SPLIT — the reviewers' consensus shape.**
> - **4a** — ratify the GP-2 **DELETE exception class** (two members, with a closure rule), not "the single exception." *Genuine owner ruling.*
> - **4b** — the `auth.users` CASCADE posture, **conditional on `ODR-16`/`O15` ≠ (a)**. *Genuine owner ruling, but not soundly rulable until `ODR-16` is ruled.*
> - **4c** — the `020` binding. **Not an owner decision** — a `CHECK` plus a test extension. *Engineering, and time-critical.*
> - **4d** — correct the scope to the enumerated relations. *Documentation fix before 4b is signed.*

> **`[5]` DEFER the demographic objects from `077` to `086`/`087`.**
> Breaks no declared dependency, adds/renames/renumbers no package, uses the precedented seventh-amendment mechanism. **Converts `ODR-4` from a start-blocker into a schedulable decision** and removes the `HG-8` gate from `077`. Requires a registry amendment and a ratified row. **Does not remove the need to rule 4a/4b — it removes the deadline.**

---

## 6. Corpus recommendation vs engineering recommendation

### CORPUS RECOMMENDATION
**None.** The exceptions are *"flagged as requiring acknowledgment"* and the register records `ODR-4` as `OPEN — owner` with no recommendation. The corpus recommends neither granting nor refusing.

### ENGINEERING RECOMMENDATION (mine, from the four reviews — **not** the corpus's)
**Option `[4]`, split, with `4c` executed now as engineering and `4b` held for `ODR-16`.** Specifically:

1. **Do `4c` immediately** — the sentinel `CHECK` on every relation in scope plus the standing assertion. It is free today, impossible after one row, and it is not yours to rule.
2. **Fix the three build defects before any acknowledgement is signed** — the append-only guard so the cascade can execute (3.1); the tombstone trigger into the plan, registry and schema spec (3.2); the tombstone's PK/AO class so the upsert is expressible (3.3). **Acknowledging an exception whose control is absent from the package is the failure this whole programme exists to prevent.**
3. **Rule `ODR-16` first**, then `4b` — or record `4b` explicitly as *conditional on `O15` ≠ (a)*.
4. **Rule `4a` on the two-member class**, with the closure rule stated mechanically: an assertion that GP-2 has **exactly** the enumerated exceptions catalog-wide. That is the mechanical form of *"a second must not be granted by analogy"*, and it costs one assertion.
5. **Take `[5]` (defer to `086`/`087`) if you want the deadline gone** — it is cheap, precedented, and under the `O17 = B` ruling it also shrinks the window in which nothing but a CI grep stands between an export function and this table from nine packages to zero.

---

## 7. What would have to be true for the exceptions to be safe

1. **The cascade must be able to execute** — 3.1 fixed, with an assertion that a real `auth.users` delete succeeds and leaves zero rows.
2. **The tombstone trigger must exist in the package that ships the table** — 3.2 fixed, with the ratified two-trigger assertion in `077`'s Tests row.
3. **The tombstone must be writable twice** — 3.3 fixed; its PK and AO class settled.
4. **`purge_after` must have a value and a reaper** — `D-6` resolved, purge scheduled, `(purge_after)` indexed.
5. **The third limb must be a database constraint, not a sentence** — 3.8.
6. **The scope must be listable** — the `DELETE` exception scoped to one relation, the CASCADE scoped to its actual set.
7. **`ODR-16` must be ruled, or the acknowledgement recorded as conditional** — 3.5.
8. **The deletion path must be resumable and detectable** — 3.6. *A cascade is only as good as the delete that fires it.*

---

## 8. What could not be verified

- **No database was contacted.** `rolbypassrls` on `postgres` and `relrowsecurity` on `auth.users` remain unchecked; both are single queries and both are load-bearing.
- **The sixth relation in the "widened scope"** is enumerated in no document. Five are nameable with citations.
- **Whether the pgTAP suites will exist.** The demographics assertion list opens *"described; no SQL files written."* The assertions bounding the writer-only anonymity rules do not exist as code.
- **Whether `O15`(a) would apply platform-wide or only to custody-holding identities** — the reading under which the cascade goes inert is an inference.
- **Legal questions** — which regimes apply, and whether gender identity is special-category — are genuinely legal, not technical, and are left open. The design is deliberately built so that a "yes" requires no redesign, which is a real asset.

---

## 9. Owner choice — presented, not made

```
[1] Acknowledge both exceptions as specified
    -- rejected by all four reviewers in this form (the cascade cannot execute,
       its compensating control is absent from the package)

[2] Acknowledge with the "six-relation scope" re-signed
    -- WITHDRAWN: unsignable. Two of the six carry no cascade; one carries RESTRICT

[3] Refuse the exceptions
    -- makes privacy worse: withdrawal stops being withdrawal, deletion fails
       outright, and it forces the very 020 edit limb 3 forbids

[4] SPLIT  <-- reviewers' consensus
      4a  ratify the GP-2 DELETE exception CLASS (two members + closure rule)
      4b  the CASCADE posture, CONDITIONAL on ODR-16/O15 != (a)
      4c  the 020 binding -- NOT a decision; a CHECK + assertion, do it now
      4d  correct the scope to the enumerated relations

[5] DEFER the demographic objects from 077 to 086/087
    -- removes the deadline; does not remove the need to rule 4a/4b

ENGINEERING RECOMMENDATION: [4], with 4c executed immediately as engineering,
the three build defects fixed before any acknowledgement is signed, and 4b held
until ODR-16 is ruled.  Optionally [5] to remove the 077 deadline entirely.

CORPUS RECOMMENDATION: none. The corpus records this as OPEN - owner with no
recommendation on either side.
```

**No ruling is made in this document.**
