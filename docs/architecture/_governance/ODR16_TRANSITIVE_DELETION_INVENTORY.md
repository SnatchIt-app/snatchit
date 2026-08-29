# `ODR-16` — The Transitive Deletion Inventory

**Built 2026-08-28.** This is the artifact `ODR16_FINAL_OWNER_BRIEF.md` §8 named as
**precondition #1**: *"No document in the corpus contains this inventory."* One does now.

> ## THE NUMBER 36 IS WRONG. IT IS 57.
>
> | | asserted | **derived** |
> |---|---|---|
> | blocking columns | 36 | **57** |
> | tables | 24 | **39** |
> | schemas | 5 | **4** (`public`, `kernel`, `venue`, `market`) |
> | columns with no stated `ON DELETE` | 10 | **16** |
> | package `077` contributes | 9 | **12** |
> | non-custody share | 26 of 36 | **50 of 57** |
>
> **57 = 13 already live + 44 designed.** The two halves were built by different methods
> on purpose: the live half by EXECUTION against a real PostgreSQL 17.11 replay of all 90
> migrations, the designed half by reading the Phase-2 corpus, which has no DDL to execute.
>
> **Ruling `16b` against 36 would have ruled on 63% of the surface.**

## Why the old figure was wrong — reconstructed, not guessed

The asserted 36 was an enumeration of **one document** (`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`)
reported as an enumeration of the corpus. The arithmetic closes exactly:

```
36  asserted
+ 6  columns that live in DOOR and PROMOTER, never opened      = 42 FK blockers
+ 2  blockers that are NOT FKs at all (see the box below)      = 44 designed
+13  already live in the shipped database                      = 57 total
```

The six missed: `kernel.door_freeze_override.granted_by` / `.revoked_by` ·
`venue.door_manifest.opened_by` / `.closed_by` · `venue.promoter_code.created_by` ·
`venue.attribution_review.decided_by`.

> ### TWO BLOCKERS THAT NO FK INVENTORY CAN FIND
>
> ```
> auth.users --CASCADE--> kernel.identity_contact_pref_event --raise_append_only()--> ABORT  (077)
> auth.users --CASCADE--> kernel.org_contact_consent_event   --raise_append_only()--> ABORT  (082)
> ```
>
> A referential `CASCADE` is a real `DELETE` on the referencing table and **fires row
> triggers**. `REVOKE DELETE` does not stop it; the trigger does. So the `CASCADE` chosen
> *specifically to avoid a deletion failure* produces one — earlier than the `RESTRICT`
> wall, and at a layer no column census reaches.
>
> **This is the single most consequential finding in this document.** From `077` the first
> failure is a `P0001` from a trigger on a table the deletion flow does not name. `ODR-16`'s
> options B (*refuse while custody is live*) and C (*forced hand-off*) were both designed
> against the `RESTRICT` cliff, and **neither predicate is ever evaluated**: B's refusal
> never lifts and C's hand-off never runs, for a reason that has nothing to do with custody.
>
> Cited: schema spec `1800`, `1807`, `1854`, `1866`; migration plan `1284`, `1366`; AO
> posture at schema spec `1770`.

## PART A — THE CURRENT DATABASE (derived by execution, not by reading)

Method: PostgreSQL 17.11, fresh cluster, all 90 migrations replayed (89 shipped +
the PR #28 hotfix), then the blocking set computed from `pg_constraint` as a
RECURSIVE transitive closure — every relation reachable from `auth.users` by
CASCADE/SET NULL/SET DEFAULT, then every NO ACTION/RESTRICT reference INTO any
relation in that closure. Depth bound 6; the closure saturates at depth 1.

**PART A DERIVED COUNT: 13 blocking columns / 8 tables / 1 schema.**

12 are direct references to `auth.users`. **One is second-order** and no
direct-reference census can see it.

| # | schema.table.column | FK target | ON DELETE | null? | append-only? | del-trigger | cleanup today | class | deletes if rows exist? | ledger? | domain | disposition |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | public.bids.bidder_id | auth.users | NO ACTION | NOT NULL | no (INSERT triggers only) | none | `delete from public.bids` | delete | NO | none | custody-adjacent (auction) | CLEANED mechanically |
| 2 | public.dispute_resolutions.actor_id | auth.users | NO ACTION | **NOT NULL** | **YES** — `trg_dispute_resolutions_append_only(U,D)` | RAISES on DELETE | **UNTOUCHED** | untouched | **NO** | the row IS the ledger | dispute / audit | **require OWNER DECISION** |
| 3 | public.listings.highest_bidder_id | auth.users | NO ACTION | nullable | no | none | `set null` | identity-neutral | NO | none | operational | CLEANED mechanically |
| 4 | public.listings.reserved_by | auth.users | NO ACTION | nullable | no | none | `set null` + status release | identity-neutral | NO | none | transfer (in-flight purchase) | CLEANED mechanically ⚠ see A.3 |
| 5 | public.listings.seller_id | auth.users | NO ACTION | NOT NULL | guarded (`trg_guard_listing_identity`) | none | sentinel | anonymize | NO | none | custody | CLEANED mechanically |
| 6 | public.listings.winner_user_id | auth.users | NO ACTION | nullable | no | none | `set null` | identity-neutral | NO | none | custody | CLEANED mechanically ⚠ see A.4 |
| 7 | public.payments.buyer_id | auth.users | NO ACTION | NOT NULL | no triggers at all | none | sentinel | anonymize | NO | Stripe PI survives | money | CLEANED mechanically |
| 8 | public.payments.seller_id | auth.users | NO ACTION | NOT NULL | no triggers at all | none | sentinel | anonymize | NO | Stripe PI survives | money | CLEANED mechanically |
| 9 | public.seller_flags.reviewed_by | auth.users | NO ACTION | nullable | no | none | `set null` | identity-neutral | NO | none | operational/audit | CLEANED mechanically |
| 10 | **public.stripe_connect_archive.profile_id** | **public.profiles** | NO ACTION | NOT NULL | no | none | sentinel (added by PR #28) | anonymize | **NO** | `stripe_connect_id` survives | money / forensics | CLEANED mechanically ⚠ see A.2 |
| 11 | public.transfers.buyer_id | auth.users | NO ACTION | NOT NULL | guarded (`trg_guard_transfer_state_columns`) | none | sentinel | anonymize | NO | none | custody / money | CLEANED mechanically |
| 12 | public.transfers.dispute_resolved_by | auth.users | NO ACTION | nullable | guarded | none | `set null` | identity-neutral | NO | `dispute_resolutions` | dispute | CLEANED mechanically ⚠ see A.1 |
| 13 | public.transfers.seller_id | auth.users | NO ACTION | NOT NULL | guarded | none | sentinel | anonymize | NO | none | custody / money | CLEANED mechanically |

Package where the object lands: all thirteen are ALREADY LIVE — this is the
shipped database, not Phase 2. Earliest package where the issue becomes live:
**already live today.**

### A.1 — #12 is dead on its own
`resolve_transfer_dispute` writes `transfers.dispute_resolved_by` (065:148) AND
inserts `dispute_resolutions` (065:154) in ONE call. So every user whose #12 is
cleared still has a #2 row blocking them. Clearing #12 alone frees nobody.

### A.2 — #10 is the second-order one
`profiles.id` is `ON DELETE CASCADE` from `auth.users` (000:14). The auth delete
CASCADES into `profiles`, and THAT delete trips
`stripe_connect_archive.profile_id -> profiles(id)`, NO ACTION (044:22).
044's header records **4 such rows live in production**.
Repointing to the sentinel cuts the local link but `stripe_connect_id` survives,
so Stripe-side forensics remain possible. Recorded, not free.

### A.3 — #4 has an unresolved race
Releasing a reservation the user holds on ANOTHER seller's listing is a required
FK clear, but it races an in-flight buy-now payment: a webhook landing after
deletion finds the listing released and `mark_listing_sold` raises. Closing it
means refusing deletion while a live reservation is held — which changes WHO MAY
DELETE and therefore belongs to 16b, not to mechanical cleanup.

### A.4 — #6 leaves an unrecoverable auction
A deleted user's won-but-unsettled auction is left `ended` with
`winner_user_id = NULL` and no recovery path. Belongs to 16b.

## PART A′ — DELETION-SENSITIVE BUT NON-BLOCKING (15 columns, 12 tables)

These do not block the delete. They determine what SURVIVES it, which is the
other half of what 16b must decide.

**CASCADE — the row is DESTROYED with the account (11):**
`admin_users.user_id` · `notification_preferences.user_id` · `notifications.user_id`
· `profiles.id` · `push_tokens.user_id` · `reports.reporter_id`
· `saved_listings.user_id` · **`seller_flags.seller_id`** · `seller_risk_scores.seller_id`
· `user_blocks.blocked_id` · `user_blocks.blocker_id`

**SET NULL — the row survives, the link is cut (4):**
`ambassador_applications.reviewer_id` · `ambassador_applications.user_id`
· `venue_partnership_inquiries.reviewer_id` · `venue_partnership_inquiries.user_id`

### A′.1 — two of these are findings, not bookkeeping
- **`seller_flags.seller_id` and `seller_risk_scores.seller_id` are CASCADE.**
  Deleting an account ERASES ITS OWN FRAUD HISTORY. A seller under risk review
  can clear their record by deleting and re-registering. Note the asymmetry with
  #9: the *reviewer* link is preserved (set null), the *subject* record is
  destroyed. Domain: operational/risk. Disposition: **require OWNER DECISION** —
  this is a policy choice about abuse, not a mechanical cleanup.
- **`user_blocks.blocked_id` is CASCADE.** A blocked user deleting their account
  removes the block. The blocker is not told. Domain: safety.
  Disposition: **require OWNER DECISION**.

### A′.2 — identity-reconstruction ledgers in the current DB
Only two candidates exist (`auth_audit_sweep_state`, `stripe_connect_archive`),
and neither records prior identity for the anonymized rows. **There is no ledger
that can reconstruct who a sentinel-repointed payment or transfer belonged to.**
That is a property of the current design, and 16b should be ruled knowing it:
today's anonymization is one-way and unauditable.

---

## PART B — THE PHASE-2 DESIGNED SCHEMA (read from the corpus; no DDL exists to execute)

**PART B DERIVED COUNT: 44 blocking columns / 31 tables / 3 schemas** (48 deletion-sensitive
across 35 tables). `catalog` contributes **zero** identity FKs — verified column by column at
schema spec `2055–2314` — so the asserted "5 schemas" was a scope leak from Part A.

**Transitivity result, stated as the negative finding it is:** every *referential* blocker in
the designed schema sits at depth 1. Only five Phase-2 relations are `CASCADE` from
`auth.users`, **nothing FK-references any of them**, and there is **zero `ON DELETE SET NULL`
anywhere in the corpus**. The closure is not empty only because of the two trigger aborts
above.

| # | schema.table.column | ON DELETE | null | AO? | cleanup | class | deletes? | ledger | domain | disposition (recommendation) | pkg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | kernel.identity_ext.identity_id | RESTRICT | NOT NULL (PK) | no | none | untouched | NO | no | identity | CLEANED | **077** |
| 2 | kernel.organization.payout_destination_set_by | RESTRICT | nullable | no | none | untouched | NO | admin_audit | money | **OWNER DECISION** — the SoD-1 operand; nulling it disarms "redirect the bank, then withdraw" | 077 |
| 3 | kernel.org_member.identity_id | RESTRICT | NOT NULL (PK) | no | none | untouched | NO | admin_audit | role | **OWNER DECISION** — deleting can violate the ≥1-`org_owner` invariant | 077 |
| 4 | kernel.org_member.granted_by | RESTRICT | *not stated* | no | none | untouched | NO | admin_audit | role | CLEANED (SET NULL) | 077 |
| 5 | kernel.org_invite.invitee_identity_id | RESTRICT | nullable | no | none | untouched | NO | no | role | CLEANED (SET NULL) | 077 |
| 6 | kernel.org_invite.invited_by | RESTRICT | NOT NULL | no | none | untouched | NO | no | role | CLEANED (delete pending invite) | 077 |
| 7 | kernel.platform_role.identity_id | RESTRICT | NOT NULL (PK) | no | none | untouched | NO | admin_audit | role | CLEANED | 077 |
| 8 | kernel.platform_role.granted_by | **SPEC SILENT** | *not stated* | no | none | untouched | NO | admin_audit | role | CLEANED (SET NULL) | 077 |
| 9 | kernel.admin_audit.actor_identity | **SPEC SILENT** | NOT NULL | **YES** | none | untouched | NO | *is* the ledger | audit | **TOMBSTONED** — AO makes rewrite physically impossible | 077 |
| 10 | kernel.approval_request.requested_by | RESTRICT | NOT NULL | no | none | untouched | NO | admin_audit | money | **OWNER DECISION** — `CHECK(approved_by <> requested_by)` | 077 |
| 11 | kernel.approval_request.approved_by | RESTRICT | nullable | no | none | untouched | NO | admin_audit | money | **OWNER DECISION** — `CHECK(state<>'approved' OR approved_by IS NOT NULL)` | 077 |
| 12 | **kernel.identity_contact_pref_event.identity_id** | **CASCADE** | NOT NULL | **YES** | cascade delete — **cannot execute** | inoperable | **NO — aborts inside the cascade** | none survives | CRM-privacy | **OWNER DECISION** | **077** |
| 13 | kernel.tickets.current_owner_id | RESTRICT | NOT NULL | engine-only | none — repointing **forbidden** by `CUSTODY-DEL-1` | untouched | NO | ticket_ownership_log | custody | **BLOCK** | 079 |
| 14 | kernel.ticket_ownership_log.from_identity | RESTRICT | nullable | **YES** | none — `CUSTODY-DEL-1` | untouched | NO | *is* the ledger | custody | **BLOCK** | 079 |
| 15 | kernel.ticket_ownership_log.to_identity | RESTRICT | NOT NULL | **YES** | none — `CUSTODY-DEL-1` | untouched | NO | *is* the ledger | custody | **BLOCK** | 079 |
| 16 | kernel.ticket_ownership_log.actor_identity | RESTRICT (roll-up only) | NOT NULL | **YES** | none — `CUSTODY-DEL-1` | untouched | NO | *is* the ledger | custody | **BLOCK** | 079 |
| 17 | kernel.door_freeze_override.granted_by | **SPEC SILENT** | NOT NULL | **YES** | none | untouched | NO | admin_audit | custody-authority | **TOMBSTONED** | 079 ▲ |
| 18 | kernel.door_freeze_override.revoked_by | **SPEC SILENT** | nullable | **YES** | none | untouched | NO | admin_audit | custody-authority | **TOMBSTONED** | 079 ▲ |
| 19 | kernel.wallet_pass.holder_identity_id | RESTRICT | NOT NULL | **IMM** | none | untouched | NO | log + generation | custody-credential | **BLOCK** | 083 ▲ |
| 20 | kernel.payout.payee_identity_id | RESTRICT | nullable | no | none | untouched | NO | settlement_line | money | **BLOCK** — money paid to a natural person | 085 |
| 21 | kernel.payout.held_by | RESTRICT | nullable | no | none | untouched | NO | admin_audit | money-risk | **TOMBSTONED** | 085 |
| 22 | **kernel.org_contact_consent_event.identity_id** | **CASCADE** | NOT NULL | **YES** | cascade delete — **cannot execute** | inoperable | **NO — aborts inside the cascade** | none survives | CRM-privacy | **OWNER DECISION** | **082** |
| 23 | venue.staff_role.identity_id | RESTRICT | NOT NULL (PK) | no | none | untouched | NO | admin_audit | role | CLEANED | 080 |
| 24 | venue.staff_role.granted_by | **SPEC SILENT** | *not stated* | no | none | untouched | NO | admin_audit | role | CLEANED (SET NULL) | 080 |
| 25 | venue.inventory_movement.actor_identity | **SPEC SILENT** | *not stated* | **YES** | none | untouched | NO | *is* an audit ledger | audit | **TOMBSTONED** | 081 |
| 26 | venue.inventory_hold.identity_id | **SPEC SILENT** | NOT NULL | no | none | untouched | NO | no | ops | CLEANED (TTL-bounded) | 081 |
| 27 | venue.order.buyer_id | RESTRICT | NOT NULL | no | none | untouched | NO | payment_native | money | **BLOCK** — the refund path resolves through it | 082 |
| 28 | venue.scan.actor_identity_id | RESTRICT | nullable | **YES** | none | untouched | NO | *is* the admission ledger | audit | **TOMBSTONED** | 086 |
| 29 | venue.comp_allocation.granted_to_identity | **SPEC SILENT** | nullable | no | none | untouched | NO | `granted_to_name` survives | ops | CLEANED (SET NULL) | 086 |
| 30 | venue.comp_allocation.granted_by | **SPEC SILENT** | *not stated* | no | none | untouched | NO | admin_audit | ops | CLEANED (SET NULL) | 086 |
| 31 | venue.guest_list.created_by | **SPEC SILENT** | *not stated* | no | none | untouched | NO | no | ops | CLEANED (SET NULL) | 086 |
| 32 | venue.door_manifest.opened_by | **SPEC SILENT** | NOT NULL | AO-ish | none | untouched | NO | *is* the door episode ledger | audit | **TOMBSTONED** | 086 |
| 33 | venue.door_manifest.closed_by | **SPEC SILENT** | nullable | AO-ish | none | untouched | NO | *is* the door episode ledger | audit | **TOMBSTONED** | 086 |
| 34 | venue.export_job.requested_by | RESTRICT (stated twice, with a reason) | NOT NULL | no | none — CASCADE positively ruled out | untouched (deliberate) | NO | the job row | CRM-privacy | **OWNER DECISION** | 087 |
| 35 | venue.promoter.identity_id | **SPEC SILENT** | *not stated* | no | none | untouched | NO | attribution snapshot | commercial | **OWNER DECISION** — the commission entitlement key | 090 |
| 36 | venue.promoter_link.status_changed_by | **SPEC SILENT** | nullable | no | none | untouched | NO | no | ops | CLEANED (SET NULL) | 090 |
| 37 | venue.promoter_code.created_by | **SPEC SILENT** | NOT NULL | no | none | untouched | NO | no | commercial | **OWNER DECISION** — NOT NULL and the code row must survive | 090 |
| 38 | venue.attribution_review.decided_by | **SPEC SILENT** | NOT NULL | **YES** | none | untouched | NO | *is* the adjudication ledger | **dispute** | **TOMBSTONED** | 090 |
| 39 | market.listing_native.seller_id | RESTRICT | NOT NULL | no | none | untouched | NO | market_sale | marketplace | **OWNER DECISION** — cancelled is cleanable, sold is not | 088 |
| 40 | market.offer.buyer_id | RESTRICT | NOT NULL | no | none | untouched | NO | market_sale | marketplace | **OWNER DECISION** — same split | 088 |
| 41 | market.market_sale.buyer_id | RESTRICT | NOT NULL | no | none | untouched | NO | ticket_ownership_log | money | **BLOCK** | 088 |
| 42 | market.market_sale.seller_id | RESTRICT | NOT NULL | no | none | untouched | NO | ticket_ownership_log | money | **BLOCK** | 088 |
| 43 | market.p2p_transfer.from_identity | RESTRICT | NOT NULL | no | none | untouched | NO | ticket_ownership_log | **transfer** | **BLOCK** | 088 |
| 44 | market.p2p_transfer.to_identity | RESTRICT | nullable | no | none | untouched | NO | ticket_ownership_log | **transfer** | **BLOCK** | 088 |

**Deletion-sensitive but NOT blocking (4):** `kernel.identity_demographic.identity_id` (CASCADE,
`077`) · `kernel.identity_contact_pref.identity_id` (CASCADE, `077`) ·
`kernel.org_contact_consent.identity_id` (CASCADE, `082`) ·
`kernel.identity_demographic_erasure.identity_id` (**no FK either way** — a bare identity uuid
deliberately retained past erasure, `purge_after` governed by `DEMOG` `D-6` whose `{N}` is
literally unfilled: **TOMBSTONED + require COUNSEL**).

### Breakdown by package (44 blocking)

`076` 0 · **`077` 12** · `078` 0 · `079` 6 · `080` 2 · `081` 2 · `082` 2 · `083` 1 · `084` 0 ·
`085` 2 · `086` 6 · `087` 1 · `088` 6 · `089` 0 · `090` 4 · `091` 0.

**27% of the designed blocking surface lands in the first content package.**

### Breakdown by domain (44 blocking)

role/identity/ops **16** · money **10** · custody **7** · audit **5** · CRM-privacy **3** ·
transfer **2** · dispute **1**. **Non-custody = 37 of 44 (84%).**

### Breakdown by recommended disposition (44 blocking)

**BLOCK** 11 · **TOMBSTONED** 9 · **CLEANED mechanically** 13 · **require OWNER DECISION** 11.

### The 16 SPEC-SILENT columns — a finding, not bookkeeping

There is **no global `ON DELETE` default stated anywhere** in §0 of the physical schema spec.
Two other specs call `RESTRICT` "the corpus default" (`CRM:1810`, `DEMOG:1019`) without citing
the document that would make it binding. Postgres's real default is `NO ACTION` — which blocks
identically but is a different `confdeltype` and is not deferrable-equivalent. Ten of the
sixteen are in the schema spec; **six are in DOOR and PROMOTER**, which is exactly the blind
spot that produced 36. ****Seven** of the sixteen-plus-one *(corrected 2026-08-29 — the table carries exactly seven `not stated` rows; "eight" was an internal off-by-one)* also state no nullability**, so whether `SET NULL`
— the cheapest cleanup available — is even possible is undetermined by the corpus.

Fix: a one-line amendment to schema spec §0.

---

## THE EARLIEST-LIVE SUBSET — the `077` claim, verified AND narrowed

**VERIFIED.** `kernel.identity_ext.identity_id` is `PK, FK→auth.users(id) on delete restrict`
(schema spec `246`, restated `256`), and `identity_ext` lands in `077` (plan `281`, `1281`,
index `3914`). **The correction from `079` to `077` holds.**

**BUT ONE CLAUSE OF THE GLOSS DOES NOT HOLD, and it changes the scope of every option.**
`ODR16_FINAL_OWNER_BRIEF.md` reads *"Every identity with one is undeletable the day `077`
applies."* The qualifier **"with one" is load-bearing and is being dropped downstream**:

> *"The only near-backfill is `kernel.identity_ext`, which is **lazily created per-identity on
> first write** (no bulk backfill of existing `auth.users`)."* — plan `264`, repeated `539`.

So at `077` the blocked population is *identities that have written an `identity_ext` row*, not
all identities. **The brief's "for every identity, custody or none" is an overstatement.** The
deadline is real; the universal quantifier is not, and nothing in the corpus says when — or
whether — `identity_ext` becomes total.

**Two things at `077` that the brief does not carry:** eleven *other* columns block there
(#1–#11), and `admin_audit.actor_identity` is `NOT NULL` on an append-only table — so **anyone
who ever performed one privileged action is permanently undeletable from `077`, with no rewrite
path, independent of `identity_ext`.**

**And at `078`:** the seeded sentinels `SN-VOID` and `SN-SYSTEM` become undeletable themselves
from `079`. No spec says so, and no spec says whether that is intended.

## CONFLICTS BETWEEN SPECS (7)

1. **`kernel.identity_demographic`'s delete trigger — a direct contradiction, and the one that
   matters most here.** `DEMOG:778`/`:1023` specify a `BEFORE DELETE FOR EACH ROW` trigger that
   writes the erasure tombstone, existing *specifically* so the `auth.users` cascade produces
   one. `PHASE_2_SUPABASE_MIGRATION_PLAN.md:1284` says the table carries *"exactly one trigger
   — the `updated_at` maintainer — and nothing else."* **Built as the plan says, account
   deletion cascades the gender answer away and writes no tombstone**, reopening the
   restore-resurrection hole `DEMOG` §8.2 exists to close, in the strictest erasure case.
2. `kernel.wallet_pass` package: WALLET says `084`; schema §13.5-C and plan say `083`.
3. `kernel.door_freeze_override` package: DOOR implies `086`; schema §13.5-B rules `079` —
   a seven-package disagreement.
4. **`CRM` §9.2 asserted `VERIFIED:` that `delete_account_cleanup` already repoints
   `current_owner_id`. It does not** — schema §5.1 re-read `019`/`020` and found it touches only
   `public.listings`/`payments`/`transfers`. Reconciled by `R4-5`/`K-6`, but **the false clause
   is exactly the sentence an implementer reads before extending `020` to the Phase-2 tables**,
   which `CUSTODY-DEL-1` now permanently forbids.
5. **`D-3`'s relation count is unreconcilable.** Registry `794` says six relations; `CRM:1810`
   names two; inheritance gives four; `DEMOG` `D-9` files a fifth separately. **Enumerating the
   corpus gives exactly FIVE.** Neither "four" nor "six" matches the objects.
6. `ticket_ownership_log.actor_identity`'s `ON DELETE` comes only from the table's roll-up line,
   not the column line — a DDL author working column-by-column writes `NO ACTION`, and
   `T-SCHEMA-*` asserts nothing about `confdeltype`.
7. The prior figure itself: 36/24/5, 10 silent, `077`=9 versus 44/31/3, 16 silent, `077`=12.

## WHAT THIS INVENTORY CANNOT SETTLE

| Undetermined | What would settle it | Status |
|---|---|---|
| The real `ON DELETE` for the 16 SPEC-SILENT columns | a global FK-default clause in schema spec **§0** | **does not exist** — §0 covers ids, money, time, causes, roles, RLS, immutability, lock order, baseline, and never states one |
| Nullability of 7 columns *(corrected 2026-08-29)* — i.e. whether `SET NULL` cleanup is even available | per-column DDL | **no DDL exists anywhere in the corpus**; §8 gives prose rows, not `CREATE TABLE` |
| Whether `identity_ext` becomes total (making the `077` block universal) | whether `handle_new_user` is extended, or RN first-run writes `locale` | **unspecified** |
| Lawful basis + retention for `identity_demographic_erasure` surviving the account | `DEMOG` `D-6` | **`{N}` is literally unfilled** |
| Whether `SN-VOID`/`SN-SYSTEM` are intended to be undeletable | any spec | **silent** |

## THE TWO FACTS THAT MOST CHANGE THE SHAPE OF `16b`

**1. `ODR-16` is filed against a wall that is not the first wall.** From `077` the first failure
is a `raise_append_only()` abort *inside a referential cascade* — a `P0001` from a trigger, on a
table the deletion flow does not name, before any `RESTRICT` is reached. **Options B and C were
both designed against the `RESTRICT` cliff and neither predicate is ever evaluated.**

**2. The decision is scoped as a custody decision, and 50 of 57 blocking columns are not
custody.** A venue scanner, a guest-list creator, a comp recipient, a promoter, a platform
admin, an approval requester, a CRM export requester, a bidder and a dispute resolver are each
independently undeletable, across packages `077`, `080`, `081`, `086`, `087`, `090` and the
live database. **`ODR-16`'s three-option table has no row that covers any of them.** That is
what `16d` means, and it is the majority of the problem.
