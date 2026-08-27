# PRE-PHASE-2 REMAINING BLOCKERS

**As of 2026-08-27, after 075 applied. Production ledger 89, `main` @ `23a8a3e`, auto-deploy OFF.**

## WHAT EXACTLY STILL PREVENTS US FROM STARTING PHASE 2?

Three things, and none of them is a database problem.

1. **The security gate can be silenced.** A required check reports green while security assertions fail. The fix is written and correct; it is sitting in an unmerged PR.
2. **The migration plan's numbers are wrong.** `PHASE_2_SUPABASE_MIGRATION_PLAN.md` assigns packages `071`–`086`. Every number from `071` to `075` is now an applied production migration. Following the plan literally produces a filename collision on the first commit.
3. **Five of the six approved features have no specification.** Only the venue dashboard was written.

Everything else is either decidable during implementation or is a decision only you can make.

---

## BLOCKER — MUST FIX BEFORE PHASE 2

### B-1. `todo()` / `skip()` masking ratchet — PR [#18](https://github.com/SnatchIt-app/snatchit/pull/18)

**This is the one that matters.** The pgTAP gate on `main` enforces four things: `result=PASS`, zero bad plans, assertions-run == assertions-planned, and the coverage floor (16 files / 287 assertions).

It does **not** enforce anything about `todo()`. The run that shipped 075 printed this, on a green required check:

```
files=16 tests_ran=287 result=PASS failing_files=0 bad_plans=0 todo_failing=2
```

`todo_failing=2` is computed, printed, labelled *"(not gating)"* in the step summary — and gates nothing. Wrapping a failing security assertion in `todo()` keeps the check green, keeps `tests_ran` at 287, and keeps the coverage ratchet satisfied, because all three of those guards compare the suite against **itself**. `skip()` is worse: skipped assertions still count toward `Tests=` and can never fail, so every existing guard is blind to it.

Phase 2 adds sixteen migrations, four new schemas and an entirely new RLS surface. Building that on a gate that can be silenced by a three-character edit is the wrong order of operations.

PR #18 closes it with three guards — a runtime ratchet on `todo_failing`, a **static** ratchet on `todo(` occurrences (a `todo()` around an assertion that currently *passes* emits no runtime marker at all, so the runtime count alone cannot see one being added), and a flat ban on `skip(`.

**Its ratchets are still exactly correct against post-075 `main`** — measured, not assumed: 2 `todo()` calls (F-2, F-3 in `060_payments_money.sql`), 0 `skip()` calls, `EXPECT_TODO=2`. The third pinned finding, the `proof_status` fail-open, was correctly removed from the suite when 071 shipped. **PR #18 needs a mechanical rebase and nothing else.**

Status: `CONFLICTING/DIRTY` — the base has moved by four migrations and two ratchet raises since it was authored.

### B-2. MONEY-1 impersonation matrix — PR [#19](https://github.com/SnatchIt-app/snatchit/pull/19)

The MONEY-1 verdict was **not exploitable — by grants and PostgREST behaviour, not by design**. That distinction is the whole reason this is a blocker. `request_is_service_role()` is fail-open when `request.jwt.claims` is NULL; what saves us today is that no client role holds EXECUTE on the functions that call it. Phase 2 adds a new generation of `SECURITY DEFINER` money RPCs. One over-broad `GRANT EXECUTE` in package `080` re-opens it, and nothing in CI would notice.

PR #19 is the executable regression that would notice. Without it, "not exploitable" is a statement about a snapshot, not a property the build enforces.

Status: `CONFLICTING/DIRTY`. Rebase and merge.

### B-3. Phase-2 migration renumber `071–086` → `076–091`

`PHASE_2_SUPABASE_MIGRATION_PLAN.md` §41 states *"True applied max across the phase0 chain = 070. Phase-2 migrations begin at `071_`."* That was true when it was written. It is now false — `071`, `072`, `073`, `074` and `075` are applied to production.

The package table assigns:

| Package | Spec number | Must become |
|---|---|---|
| A schema skeleton | `071` | `076` |
| B organizations + permissions | `072` | `077` |
| C catalog | `073` | `078` |
| D ticket kernel | `074` | `079` |
| E inventory | `075`, `076` | `080`, `081` |
| F orders | `077` | `082` |
| G credential infrastructure | `078`, `079` | `083`, `084` |
| kernel money-native | `080` | `085` |
| H scan infrastructure | `081` | `086` |
| I settlement | `082` | `087` |
| J native marketplace bridge | `083`, `084` | `088`, `089` |
| promoter engine | `085` | `090` |
| K money-ledger stub | `086` | `091` |

Sixteen packages, `076`–`091`. Cross-references inside the specs move with them (`073` seeds the feature flags; `079` adopts the late-binding FKs; the addenda A1/A2/A3 name packages `072`, `073` and `083`).

This is mechanical and is naturally the first commit of Phase 2 — but I am classifying it as a blocker rather than a Phase-2 task because **the specs are currently wrong**, and an engineer following them writes `071_create_phase2_schemas_and_grants.sql` on day one. The immutability guard would reject it, after the work was done.

### B-4. Five of six approved features have no specification

The scope amendment produced exactly one artifact: `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` (1,187 lines, branch `design/venue-dashboard` @ `239393e`, unmerged). Verified against git — the `design/wallet`, `design/wallet-a` and `design/privacy` branches carry **zero commits**, and their worktrees are clean.

Not written:

- Apple Wallet passes (including the requirement you set: the old owner's pass must not remain a valid admission credential after transfer)
- Demographic capture
- Promoter codes
- Venue CRM export
- Notifications
- `PHASE_2_SCOPE_AMENDMENT_2026_08.md` — the integrating document itself

This blocks **those six features**, not the Phase-2 core. Packages `076`–`091` are the kernel/catalog/inventory/orders/settlement spine and do not depend on any of them. If you want the core started while the feature specs are written, that is a coherent plan — but it is your call, and it is listed under Owner Decisions below.

---

## NON-BLOCKER — CAN FIX DURING PHASE 2

| | Item | Why it can wait |
|---|---|---|
| N-1 | **Gate-2 is structurally blind to storage and cron drift.** It counts `pg_policies WHERE schemaname='public'` only. Both the RED tree (six orphan storage policies present) and the GREEN tree printed `policies=37`, and **Gate-2 passed on RED**. | `132_replay_parity.sql` now covers the two known instances with explicit set-equality. Widening Gate-2 to `storage` + `cron` is a genuine improvement, but the specific drift is caught today. |
| N-2 | **Supabase CLI pin is one minor behind** — CI pins `2.115.0`, current is `2.116.0`. The version-drift assertion that would surface this rides in PR #18. | The pin is deliberate: 2.115.0's ordering behaviour is the one verified against this ledger. Upgrading is a decision, not a fix. |
| N-3 | **`strict_required_status_checks_policy: false`** on the `main-protection` ruleset — a PR can merge with green checks computed against a stale base. | Real but narrow. Every migration-bearing PR in this series was rebased onto current `main` and re-checked by hand anyway. |
| N-4 | **`supabase/tests/README.md` is stale** — claims 13 files / 234 assertions; reality is 16 / 287, and it still lists the `proof_status` `todo()` that 071 removed. | Documentation only. No gate reads it. |
| N-5 | **Superseded PRs still open:** [#21](https://github.com/SnatchIt-app/snatchit/pull/21) (superseded 073), [#22](https://github.com/SnatchIt-app/snatchit/pull/22) (superseded integration), [#23](https://github.com/SnatchIt-app/snatchit/pull/23) (superseded 075). | Housekeeping — **but do #21 soon.** It is the only one that reports `MERGEABLE/CLEAN`, and it carries a superseded `073`. The immutability guard would almost certainly reject it, but it is a live footgun sitting one click away. I have not closed them; that is a repo action outside this authorization. |
| N-6 | **7 Dependabot advisories on the default branch** (4 high, 3 moderate), surfaced on every push. | Pre-existing, unrelated to the DB work, and `npm audit` is advisory-only in CI by design. |

---

## ACCEPTED DEBT — DOES NOT BLOCK IMPLEMENTATION

| | Item | Standing |
|---|---|---|
| D-1 | **F-2** — `transfers.stripe_transfer_id` has no unique index; the same Stripe transfer id can land on two rows. Self-documented in migration 056a. | Pinned by a deliberate `todo()` in `060_payments_money.sql:61`. Flips green the day an index migration ships. **PR #18's ratchet is what keeps this from quietly growing to three.** |
| D-2 | **F-3** — `payments` has no column-guard trigger; the money-evidence table's amounts are mutable by any service-path writer, unlike `listings` (046) and `transfers` (055). | Pinned by `todo()` at `060:71`. Classified, not implemented — an intentional asymmetry, recorded rather than hidden. |
| D-3 | **No staging environment.** Engineering Standards §5 "staging-first" is aspirational; it needs a Supabase Pro plan. | The compensating control is what this whole series used: rolled-back transactional dry runs, fresh-replay CI, and read-only production pre-checks. It worked — five migrations, zero production surprises — but it is not the same thing as staging, and Phase 2 is structural where these were metadata. |
| D-4 | **`000_baseline_schema.sql` is a reconstructed baseline, not a transcript** of what was executed against production. This is the root cause of both SEC-3 and SEC-4. | 075 closes the two known divergences. There is no guarantee it closes all of them — only that nothing else has been found. `UNVERIFIED`: no exhaustive baseline-vs-production diff has been performed. |
| D-5 | **`buy_now_price` re-pricing severity is unknown**, pending an installed-base measurement that was never taken. | Carried forward from the payments work. It is a client-version question, not a schema question. |

---

## OWNER DECISION REQUIRED

I am not deciding any of these. Each blocks a specific workstream and I have named which.

### O-1. Refund authority — *blocks package `085` (kernel money-native) and the venue settlement path*

The two specs contradict each other outright.

`PHASE_2_RLS_PERMISSION_SPEC.md` §7.10 (`kernel.refund`): `org_owner/admin/member → D D D D`. No org role has refund SELECT, and no org role has refund EXEC. Refund execution belongs solely to `platform_support` (`refund_primary_order`, capped, audited), `platform_risk` and `platform_admin` (`admin_refund`).

`SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.6, row *"Issue refund (> micro)"*: **✔ᴰ✱ for Org Owner** and ✔ᴰ✱ for Org Finance — dual-control, audited.

One of these is the product. **Which?** Can a venue refund its own buyer, or must every refund route through platform staff?

### O-2. Venue role catalog — *blocks packages `077` (org roles) and `080` (venue staff roles)*

The two documents do not use the same role set. Measured from the text:

- RLS spec: `org_owner`, `org_admin`, `org_finance`, `org_member`, `venue_manager`
- Domain architecture: `org_owner`, `org_admin`, `org_finance`, `org_member`, `scanner` — plus a §7.6 matrix with **Box Office**, **Marketing**, **Promoter Mgr**, **Promoter**, **Ambassador** columns that have no counterpart in the RLS spec at all.

`venue_manager` and `scanner` are not the same role, and five roles exist in one spec and not the other. **The canonical list has to come from you** — it determines the `venue.staff_role` enum, which is an applied-migration commitment that cannot be edited afterwards.

### O-3. `org_owner` payout read / request mismatch — *blocks packages `085` and `087`*

`PHASE_2_RLS_PERMISSION_SPEC.md` §7.9 (`kernel.payout`): `org_member/owner/admin → D` on SELECT. `org_owner` **cannot read the payout ledger at all**; only `org_finance` gets `V(own-org payouts)`.

`SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.6: *"Initiate payout (≤ threshold)"* ✔✱ **Org Owner**; *"Initiate/approve payout (> threshold)"* ✔ᴰ✱ **Org Owner**; *"Change payout/bank account"* ✔✱ **Org Owner**.

So one spec has the org owner initiating and approving payouts, and the other denies them sight of the payout ledger. **Can an org owner see and request their own payouts, or is that strictly the finance role's job?**

### O-4. Door-manifest open/close authority — *blocks package `086` (scan infrastructure)*

Who is permitted to open and close a door manifest, and with what effect on transfers already in flight? No role in either matrix is assigned this right.

### O-5. `catalog.event_session.door_open_at` has no write lifecycle — *blocks `086`, and gates the Apple Wallet safety guarantee*

This one is worth reading carefully, because it looks closed and is not.

The column is **read** in three places: `kernel.is_transfer_frozen(atom_id)` (RLS spec §1152), the door-manifest RPC's predicate `door_open_at IS NOT NULL AND now() >= door_open_at` (RPC contracts §748, narrowed per-open-manifest-ticket per C43), and the React Native spec. It is declared `timestamptz` **nullable** in schema §2.3. Review R3 records it as **FIXED**, and addenda A2/A3 as **CLOSED**.

What was fixed is the *canonical form* — that the freeze signal is this column and not a `transfer_frozen` boolean. What was never specified is the **writer**: no RPC in `PHASE_2_RPC_FUNCTION_CONTRACTS.md` sets `door_open_at`. Nothing states who may set it, whether it may be moved backwards (un-freezing transfers that were already refused), what happens when it is NULL at door time, or whether it is derived from `doors_at` or set independently.

That is not a cosmetic gap. **A nullable column with no writer means the door freeze can silently never engage** — the same failure shape as the D-5 cron job that 075 just fixed: present, correct, and called by nothing.

And it propagates: the Apple Wallet spec's stale-pass / offline-door safety guarantee **depends on this contract**, because a revoked pass is only reliably rejected if the door manifest froze at a defined moment. Per your instruction, the Wallet spec must state that dependency explicitly — it cannot be written until O-5 is resolved.

### O-6. Sequencing of the six approved features (see B-4)

Do you want packages `076`–`091` (the kernel/catalog/inventory/orders/settlement spine) started while the five missing feature specs are written — or the amendment completed first? The spine does not depend on any of the six.

---

## RECOMMENDED ORDER

1. Rebase and merge **PR #18**, then **PR #19**. Both are code-complete; #18's ratchets are already correct against post-075 `main`. Neither touches the database.
2. Close **PR #21** (and #22, #23) so no superseded migration can be merged by accident.
3. Answer **O-1 through O-5**. O-5 is the one with a live failure mode behind it.
4. Renumber the migration plan `071–086` → `076–091` (**B-3**) as the first Phase-2 commit.
5. Decide **O-6**, and write the five missing feature specs on that schedule.

Steps 1, 2 and 4 are a few hours. Step 3 is yours. Nothing here requires another production change — **the database is done.**

---

*075 is applied and verified; see `075_PRODUCTION_VERIFICATION_REPORT.md`. This report authorizes nothing and changes nothing. `076` does not exist. No Phase-2 work has begun.*
