# T1 — pgTAP triage of the migration-093 regressions (files 141–146)

**Scope.** The six pgTAP files `supabase/tests/141`–`146`. Files 148/151/153–157 belong to a
different agent and were not touched. Migration `093_primary_ticketing.sql`, everything under
`docs/phase2/_impl/093_parts/`, and migrations 000–092 were not modified.

**Harness.** Local only: `scripts/rehearsal_reset.sh snatchit_rehearsal_t1` (108/108 migrations
applied; GATE-2 census matches the CI baseline exactly — tables=27 functions=70 policies=37
triggers=24) then `scripts/rehearsal_test.sh snatchit_rehearsal_t1 <files>`. No remote was
contacted; no commits were made.

**093 revision this triage is pinned to.** `093_primary_ticketing.sql`, **4038 lines,
`md5 = 6ab87362e3a6983d0ad1355758835402`** — the revision that includes the two money P0 fixes, the
`settlement.refund_window_interval` key and the connect staging verb. **093 was re-assembled from
`docs/phase2/_impl/093_parts/` four times while this triage ran** (2752 → 3078 → 3275 → 4038 lines);
every number below was re-derived from the live catalog against the revision named here, never
carried over from a previous pass. See §5 for the full sequence.

**Authority for every category-A edit.** `docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md`
(ratified by the owner 2026-09-02), cited by owner ruling number in the test comment itself.

**Classification key.**

* **A — RATIFIED CONTRACT CHANGE.** The owner changed the behaviour the test asserts. The
  assertion is updated to the new truth and stays at least as strict.
* **B — TEST SETUP DRIFT.** The fixture no longer builds because a precondition changed. Setup
  fixed, assertion identical.
* **C — GENUINE 093 DEFECT.** The migration is wrong. The test was **not** edited.

---

## 1. Result

| File | Before | After | State |
|---|---|---|---|
| `141_phase2_identity_orgs_deletion.sql` | plan 188, ok 105, not_ok 3, **151 psql errors** (aborted in the connect-onboarding block) | plan 193, ok 193, not_ok 0 | **PASS** |
| `142_phase2_catalog_config_and_seeds.sql` | plan 249, ok 245, not_ok 4 | plan 250, ok 250, not_ok 0 | **PASS** |
| `143_phase2_ticket_custody_kernel.sql` | plan 154, ok 73, not_ok 2, **148 psql errors** (aborted at 143:497) | plan 155, ok 155, not_ok 0 | **PASS** |
| `144_phase2_venue_staff_authz.sql` | plan 114, ok 113, not_ok 1 | plan 114, ok 114, not_ok 0 | **PASS** |
| `145_phase2_venue_inventory.sql` | plan 96, ok 78, not_ok 2, **47 psql errors** (aborted at 145:393) | plan 96, ok 96, not_ok 0 | **PASS** |
| `146_phase2_venue_orders.sql` | plan 71, ok 44, not_ok 1, **57 psql errors** (aborted at 146:157) | plan 75, ok 75, not_ok 0 | **PASS** |

**Final suite total: plan 888, ok 888, not_ok 0, psql_err 0 — ALL-PASS**, from a clean
`rehearsal_reset` (108/108 migrations, GATE-2 census matching the CI baseline).

Counts by classification: **A = 20**, **B = 7**, **C = 1 (since FIXED in 093 — see §3)**.

The two documented local-only deltas (`060_payments_money.sql` not_ok=2, `132_replay_parity.sql`
not_ok=2) were not touched.

---

## 2. Every failure, classified

| # | File:line (post-edit) | Symptom | Class | Ruling / evidence | Disposition |
|---|---|---|---|---|---|
| 1 | `141:95` A14 | kernel function census: have 113, want 109 | **A** | Ruling **A6** adds `kernel.sync_org_connect_state` (`093:1485`) and `kernel.get_org_connect_state` (`093:2345`); ruling **A3** adds `kernel.settlement_primary_lines` (`093:361`); ruling **D3** adds `kernel.get_refund_execution_context` (`093:784`) | 109 → 113, with all four named in the comment and pinned by grant class in F2/F3 |
| 2 | `141:314` F2 | authenticated EXECUTE closure gained `get_org_connect_state` | **A** | Ruling **A6** — the masked human read half (the ratification: "the read path for humans… masks the account id") | Name added to the by-name closure; count 59 → 60 |
| 3 | `141:357` F3 | service_role EXECUTE closure gained `sync_org_connect_state` and `get_refund_execution_context` | **A** | Ruling **A6/A9** — sync is service_role **only** ("never `authenticated`, never anon"); ruling **D3** — the refund executor is "server-side, authenticated and authorized appropriately" | Both names added; count 34 → 36. `settlement_primary_lines` is deliberately in **neither** closure (no grant at all), which its absence from both asserts |
| 4 | `141:648` (was) | `ERROR: step_up_unavailable: the session carries no aal claim` — file aborted, 151 cascading errors | **B + A** | Rulings **A7/A9**; `kernel.set_org_connect_ref` (`093:1992`) now demands org_owner only, an aal2 claim fail-closed on absence, org status `approved|active`, and a cross-plane refusal of any `acct_` on `public.profiles` / `public.stripe_connect_archive` | **B:** the fixture steps the session up (`tap._aal2()`, the established 149/151 idiom) and approves org1 through `kernel.set_org_status`. **A:** five new assertions L0a–L0e (`141:682`, `:688`, `:694`, `:696`, `:705`) prove each new gate *before* the setup satisfies it, so satisfying a gate cannot mask a regression in it. L1–L5 unchanged; L4's title drops the now-inaccurate "org_finance" from its prose only |
| 5 | `142:264` D1 | config key census: have 47, want 43 | **A** | Rulings **D2** and **A5** seed four keys at version 1: `ticket.expiry_grace`, `fee.buyer_service_bps`, `inventory.hold_ttl_interval`, `inventory.per_user_active_hold_max` (`093:2714` and neighbours) | 43 → 47 |
| 6 | `142:270` D4 | restricted class: have 39, want 35 | **A** | Same four; all land `restricted`, so D3/D5 (the public class) are untouched | 35 → 39 |
| 7 | `142:292` D5a | — | **A (strengthening)** | Same | **New** assertion naming the four keys and pinning `version = 1`, `visibility = 'restricted'` and `value = 'null'::jsonb`, so the raised counts in D1/D4 cannot pass vacuously |
| 8 | `142:703` G20 | caught `P0001 operatorship_transfer_frozen`, wanted `42501 insufficient_privilege: operatorship change is platform_admin only` | **A (inverted)** | Ruling **C**: "Venue operatorship transfers are **frozen for initial launch**… a venue cannot change its operating organization." `093:2837` (`catalog.update_venue`) raises **before** the `is_platform` check, deliberately, so the error carries no authority oracle | Assertion inverted to the new contract, still matched on the **exact errcode and the exact full message** (the file's RED-B rule) |
| 9 | `142:1206` K3 | kernel census 113 vs 109 | **A** | Same as #1 | 109 → 113 |
| 10 | `143:152` A32 | kernel census 113 vs 109 | **A** | Same as #1 | 109 → 113 |
| 11 | `143:508`/`143:511` D1/D1a | `ticket.expiry_grace is NOT seeded`: have 1, want 0 | **A** | Ruling **D2**: "leaving it absent is forbidden by this ruling." 093 seeds it at version 1 with a **JSON-null** value | D1 inverted to "exists at version 1, owner-UNSET, JSON-null"; **new** D1a asserts *no version of the key carries a value*. `kernel.sweep_expired_ticket_atoms` reads `(value #>> '{}')::interval`, SQL NULL for a JSON null, so **D2/D3 (the sweep is inert) are unchanged in text and in substance** — E-18's property now rests on the absent *value* rather than the absent *key*, which is the only thing the ruling moved |
| 12 | `143:497` (was) | `duplicate key value violates unique constraint "platform_config_pkey"` — file aborted, 148 cascading errors | **B** | 093 owns version 1 of `ticket.expiry_grace` | The D4 setup now inserts **version 2** (`143:521`). The reader is `order by c.version desc limit 1`, so version 2 is exactly what an owner calling `catalog.set_platform_config` would produce. D4–D11 unchanged |
| 13 | `144:100` A14 | kernel census 113 vs 109 | **A** | Same as #1 | 109 → 113 |
| 14 | `145:391/395` G1,G2 | `inventory.*` keys `UNSEEDED`: have 1, want 0 | **A** | Ruling **A5** ("no percentage is invented anywhere… fee economics remain owner/config controlled") applied through the D2 key discipline | G1/G2 restate E-28 on the property that still holds — **neither key carries a value** — and `venue.reserve_primary_inventory` still `coalesce(v_cap_max, 0)` → refuses, and still refuses `hold_ttl_unset`. G3–G7 byte-unchanged and still pass |
| 15 | `145:393` (was) | `platform_config_pkey` collision — file aborted, 47 cascading errors | **B** | 093 owns version 1 of both inventory keys | Setup inserts now use **version 2** (`145:407`, `145:415`) |
| 16 | `146:98/107` B7/B7a | `venue.order is client-read only` failed — `authenticated` lost table-grain SELECT | **A** | Ruling **F**: "the verified table-grain buyer-identity/display-name join that allows an unaudited attendee roster is fixed." `093:3063-3064` revokes the table grant and re-grants 12 of 13 columns; `buyer_id` is withheld | B7 keeps the write half verbatim and **tightens** the read half from "has SELECT" to "has NO table-grain grant"; **new** B7a `bag_eq` pins the exact 12-column set by name, so a re-widened grant fails immediately |
| 17 | `146:157` (was) | `platform_config_pkey` collision — file aborted, 57 cascading errors | **B** | Same as #15 | Setup inserts now use **version 2** (`146:181`, `146:182`) |
| 18 | `146:228` F0 | `create_primary_checkout` would raise `precondition_failed: payout_not_ready` in the happy path | **B + A** | Ruling **A8**: "checkout must fail closed if the venue organization is not eligible for primary-sale collection." `093:1806-1812` requires both a bound `stripe_connect_account_ref` and `connect_transfers_active` | **A:** **new** F0 asserts the fail-closed refusal *first*, on the exact message. **B:** the fixture then makes the org ready through the real verbs — `kernel.set_org_connect_ref` (org_owner + aal2 + approved org) then `kernel.sync_org_connect_state` — never a direct `UPDATE` |
| 19 | `146:260` F0a | `precondition_failed: service_fee_unset` — appeared mid-triage when 093 was re-assembled | **B + A** | Ruling **A5**: "No service-fee percentage is hardcoded in migration 093. No percentage is invented anywhere." `093:1835` refuses to quote rather than falling back to zero | **A:** **new** F0a asserts the refusal on the exact full message, positioned after F0 exactly as the migration orders the two gates. **B:** the fixture then sets `fee.buyer_service_bps` at **version 2** (`146:263`). F1–F8 unchanged; F3's `total_minor = 10000` still holds because `total_minor` remains FACE VALUE and the fee is returned as `buyer_fee_minor` |
| 20 | `146:340`/`146:342` I1/I1a | `SELECT … WHERE buyer_id = tap.buyer()` as `authenticated` is no longer expressible | **A** | Ruling **F**, same grant change as #16 | I1's owner scope is now asserted on the row count the RLS owner policy alone yields (**strictly stronger**: a leaking policy shows up as count > 2, where the old `buyer_id` predicate would have hidden it); **new** I1a proves `buyer_id` is unreadable |
| 21 | `146:347` I3 | `ERROR: permission denied for table order` | **C** | See §3 | **Test NOT edited.** 146 aborts here; I3/I4/I5 do not run |

---

## 3. Category C — the one genuine 093 defect

### C-1 — Ruling F's column-scoping of `venue."order"` makes `venue.order_item` unreadable by every client

**Severity: functional break, client-facing, 100 % of authenticated reads. Status: REPORTED → FIXED in 093 (`kernel.is_order_buyer`). Test never edited.**

**Statement.** `093:3063` executes `revoke select on venue."order" from authenticated;` and re-grants
12 named columns, withholding `buyer_id`. But the RLS policy `venue_order_item_sel_owner` on
`venue.order_item` (from package 082) reads `buyer_id` **in a subquery over `venue."order"`**:

```
venue_order_item_sel_owner ON venue.order_item USING (
  EXISTS (SELECT 1 FROM venue."order" o
           WHERE o.order_id = order_item.order_id AND o.buyer_id = auth.uid()))
```

A `USING` clause is exempt from the column ACL **only for the table the policy is attached to**. A
subquery inside it against a *different* relation is an ordinary table reference and is checked
against the invoking role's privileges. `authenticated` no longer holds `SELECT (buyer_id)` on
`venue."order"`, so evaluating this policy raises `42501`.

**Reproduction (minimal — no fixture, empty table, any authenticated session):**

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
SELECT set_config('role','authenticated', true);
SELECT count(*) FROM venue.order_item;
-- ERROR:  permission denied for table order
ROLLBACK;
```

**Blast radius — total for clients.** `authenticated` is the *only* role holding `SELECT` on
`venue.order_item` (`service_role` holds none; `anon` has no `venue` schema `USAGE`). All three of
that table's SELECT policies are OR'd and all are evaluated, so the failure is unconditional: it is
independent of which rows exist, of whether the caller is the buyer, of org role and of venue role.
**`venue.order_item` is dead for every client, including the buyer reading their own order lines
through PostgREST.** No ruling authorises that; ruling F removes an *attendee roster join*, not the
buyer's own order.

**Why 093 missed it — the analogy it relies on does not hold.** `093` justifies the change by
pointing at the identical fix 080 applied to `kernel.tickets.current_owner_id`, and it explicitly
verifies that removing the column does not narrow the *owner policy on the same table*. That
verification is correct and is not the problem. The problem is the case it does not consider: a
policy on a **different** table that subqueries the withheld column. Confirmed by census — **no**
policy anywhere references `kernel.tickets.current_owner_id` from outside `kernel.tickets`, so 080
never met this case, and "the reasoning transfers verbatim" is precisely where the defect entered.
`venue.order_item` is the one place it does not transfer.

**What is NOT affected** (swept and confirmed clean): no view reads `buyer_id`; no `SECURITY
INVOKER` function executable by `authenticated` reads `venue."order"`; `market.offer`'s owner policy
references only its own table's `buyer_id` plus `market.listing_native.seller_id` and is untouched by
093. `venue."order"` itself reads correctly for buyer, org and venue personas (146 I1/I2/I4 pass).

**RESOLVED IN 093 — reported, not worked around.** The test was never edited. 093 was subsequently
corrected along exactly the line recommended: `venue_order_item_sel_owner` is now

```
venue_order_item_sel_owner ON venue.order_item USING (kernel.is_order_buyer(order_id))
```

where `kernel.is_order_buyer(uuid)` is a `security definer` predicate that reads the column the
caller may not. That is the first of the two options below, and it is why the kernel census moved:
`is_order_buyer` is one of the seven functions 093 adds. `146` now passes 75/75 with I3 unmodified.

The options as reported at the time were:

* rewrite `venue_order_item_sel_owner` so the owner arm does not select `buyer_id` from
  `venue."order"` — e.g. resolve ownership through a `SECURITY DEFINER` predicate, the idiom the
  rest of the corpus already uses for cross-table authority (`kernel.has_org_role`,
  `kernel.has_venue_role`) — **this is what shipped**; **or**
* keep the policy and accept that it requires a policy-owner-evaluated predicate, which the current
  shape is not.

Granting `authenticated` `SELECT (buyer_id)` back would have undone ruling F and was explicitly
ruled out as a fix.

**Generalisation worth keeping.** The defect class is *"a column revoke breaks a policy on a
DIFFERENT table that subqueries the revoked column."* It recurred immediately: the same ruling-F
treatment of `venue.inventory_hold.identity_id` landed later in the triage window, and `145` H4/H6
were rewritten ahead of it for exactly this reason (§6, item 2).

---

## 4. Assertion-count changes (none is a relaxation)

| File | plan | Δ | Why |
|---|---|---|---|
| 141 | 188 → 198 | +10 | L0a–L0e: the four gates rulings A7/A9 added, plus the approval step. L0f–L0h + L1a: the connect-STAGING provenance control (ruling A7) that closed the `acct_ORPHANATTACKER` P0. A14a: the seven kernel functions 093 adds, by name with grant class |
| 142 | 249 → 250 | +1 | D5a names the four config keys rulings D2/A5 added |
| 143 | 154 → 155 | +1 | D1 splits into D1/D1a (key exists ∧ no version carries a value) |
| 144 | 114 | 0 | census only |
| 145 | 96 | 0 | G1/G2 restated on the surviving property; H4/H6 re-expressed on the RLS-yielded rows after the ruling-F `inventory_hold.identity_id` revoke. No count change |
| 146 | 71 → 75 | +4 | B7a (exact 12-column grant), F0 (ruling A8 payout gate), F0a (ruling A5 service-fee gate), I1a (`buyer_id` unreadable). The connect-staging call is fixture only — its contract is asserted in 141 |

No assertion was deleted, loosened, converted to `todo()`, or given a weaker matcher. Two matchers
were made **stricter**: 142 G20 now pins the exact errcode *and* the exact full message, and 146 B7
went from "has a grant" to "has no table-grain grant" plus a by-name column closure.

---

## 5. Operational note — 093 was a moving target, and the census-query discrepancy

093 was re-assembled four times during this triage. The sequence, and what each pass changed for
these six files:

| 093 | lines | what appeared | effect on the six |
|---|---|---|---|
| `6c6a80af…` | 2752 → 3078 | `kernel.get_refund_execution_context` (D3); the A5 `service_fee_unset` gate | census 112 → 113; new 146 F0a |
| `90430ede…` | 3275 | `kernel.get_org_connect_ref`, `kernel.is_order_buyer` (the C-1 fix) | census → 115; 146 unblocked, C-1 resolved |
| `6ab87362…` | 4038 | `kernel.stage_org_connect_ref` (A7 provenance); `settlement.refund_window_interval`; the `venue.inventory_hold` column revoke; two money P0 fixes | census → 116; config → 48; 145 H4/H6 revoke landed; 141/146 fixture staging |

### The census-query discrepancy, resolved

The coordinator measured `information_schema.routines` at 109 pre-093 / 116 post-093 and asked
whether the assertions' own query (`pg_proc JOIN pg_namespace WHERE nspname='kernel'`) sees
something different, since it appeared to pin 113.

**It does not. There is no discrepancy, and no function is invisible to the assertion.** Measured on
two rehearsal databases built from the same chain — one stopped at `092_notify_reduced.sql`, one
with 093:

| | `pg_proc` (the assertion's query) | `information_schema.routines` |
|---|---|---|
| pre-093 | **109** | **109** |
| post-093 | **116** | **116** |
| delta | **+7** | **+7** |

The two catalogs agree exactly at both endpoints. The `113` was simply a stale read of this
document mid-flight: the pin tracked 112 → 113 → 115 → 116 as 093 grew, and 113 was the value while
093 contained only four of the seven. (For completeness: the two catalogs *can* legitimately differ —
`information_schema.routines` hides routines the current user cannot access and excludes aggregates —
but neither applies here, since the harness runs as `postgres` and `kernel` holds no aggregates.)

Also confirmed: no migration in the `2026*` timestamped tail creates anything in `kernel`, so
"stopped at 092" is a sound pre-093 baseline.

---

## 6. Follow-up pass — three coordinator items

### Item 1 — kernel census 113 → 116, verified BY NAME

`093` adds **seven** kernel functions, zero removed (`kernel.settlement_royalty_lines` was
`create or replace`d, not added, and moves nothing). All seven are `security definer`. Verified
individually against the live catalog, not accepted as a delta:

| function | ruling | grant class |
|---|---|---|
| `get_org_connect_state` | A6 | `authenticated` — the **masked** human read |
| `get_org_connect_ref` | A6 | `service_role` — the **unmasked** id, server only |
| `sync_org_connect_state` | A6/A9 | `service_role` — the privileged capability write |
| `stage_org_connect_ref` | A7 | `service_role` — the staging verb (see item 1b) |
| `settlement_primary_lines` | A3 | **no grant at all** — definer-internal, like 087's two SEAM-2 line stubs |
| `get_refund_execution_context` | D3 | `service_role` — the refund executor's context read |
| `is_order_buyer` | F | `authenticated` — the C-1 fix predicate |

Updated: `141:A14` (census, **116**), `142:K3`, `143:A32`, `144:A14`; `141:F2` closure +`is_order_buyer`
(60 → **61**); `141:F3` closure +`get_org_connect_ref` +`stage_org_connect_ref` (36 → **38**).

**New `141` A14a — the by-name pin the coordinator asked for.** A `bag_eq` listing all seven with
their `prosecdef` flag *and* their `authenticated`/`service_role` grant class. Naming alone would let
a re-classification through, so the grant class is part of the pinned string: if
`stage_org_connect_ref` or `get_org_connect_ref` were ever exposed to `authenticated` — which would
collapse the whole provenance control, since a caller that can stage can authorise its own bind —
A14a fails by name. Anyone moving the census must now state which function they added.

### Item 1b — the `stage_org_connect_ref` provenance control (category **B** fixture + category **A** coverage)

`kernel.set_org_connect_ref` now requires the supplied id to equal `kernel.organization
.connect_pending_ref`, and **consumes** it on success. New errors `no_pending_connect_ref` and
`connect_ref_not_platform_minted`. Fixtures in `141` and `146` now stage first, as the server does.

Four new assertions in `141` give the P0 its first coverage — it had none:

* **L0f** — bind with **nothing staged** → `no_pending_connect_ref`. This is the
  `acct_ORPHANATTACKER` attack directly: an account in neither `public.profiles` nor
  `public.stripe_connect_archive` can no longer enter through the RPC. The old cross-plane check
  (L0e) is a *blocklist* and could only ever enumerate known-bad accounts; ruling A7's prohibition is
  absolute, so the control had to become structural.
* **L0g** — the server stages the account it minted (the only writer of `connect_pending_ref`).
* **L0h** — binding a **different** id than the staged one → `connect_ref_not_platform_minted`.
  Staging is a *match*, not a flag.
* **L1a** — after a successful bind `connect_pending_ref` **is NULL**: one staging authorises exactly
  one bind and can never be replayed into a later re-point.

The arm order is asserted implicitly and deliberately preserved: `noop_replay` (L3) and the
bind-once arm (L4) sit **before** the provenance check, so consuming the pending ref cannot break the
idempotent onboarding retry — noted in the L4 comment so a future reorder is caught.

### Item 2 — `145` H4/H6 under the ruling-F `inventory_hold` revoke (category **A**)

`venue.inventory_hold.identity_id` is column-revoked from `authenticated` (9 of 10 columns
re-granted), closing a P0 where a red team rebuilt a full attendee roster — names and money — as a
mere `venue_manager` by joining `identity_id` to `public.profiles`, whose policy is `USING (true)`.

Both sites follow the `146 I1` precedent — drop the client-side identity predicate, assert on what
the RLS policy itself yields:

* **H4** `WHERE identity_id = tap.buyer() AND status='active'` → `WHERE status='active'`. The buyer
  holds no org or venue role over this event, so `venue_inventory_hold_sel_owner` is the only arm
  that can admit a row. **Strictly stronger:** a policy leaking another holder's hold now surfaces as
  a count > 2, where the old predicate would have filtered it away unseen.
* **H6** `WHERE identity_id <> tap.buyer()` → proved from the **complementary seat**: a different
  signed-in fan, holding no hold and no role, must see **zero**. **Strictly stronger and now
  non-vacuous:** the fixture mints holds for the buyer only, so the old form counted foreign rows
  among rows the owner policy had *already* filtered to the buyer and could not have failed. The new
  form has H4's two rows to hide.

`identity_id` was **not** re-granted. Verified in both directions, ahead of the revoke landing:

* the **old** predicates under a simulated revoke → `ERROR: permission denied for table inventory_hold`;
* the **rewritten** file → 96/96 both under the simulated revoke and, once it shipped, for real.

### Item 3 — E-76 current-operator conjunct: no change needed in these six

`venue_order_sel_venue` / `venue_order_item_sel_venue` gained the current-operator conjunct. No
assertion of mine covered the old behaviour:

* `146 I4` reads through **`venue_order_sel_org`** (the org_owner arm), not the venue arm — `tap.seller()`
  holds no venue staff role in this fixture, so the conjunct cannot affect it;
* `146 I5` is a policy-*text* regression check for the strings `platform_support` / `venue_scanner`,
  neither of which the conjunct introduces;
* no file of mine constructs an operatorship divergence — `142 G20` proves the transfer is refused
  outright under ruling C.

Recorded as instructed and **not** chased: the identical E-76 omission on `catalog.event` and
`kernel.tickets` (078/079 surfaces owned elsewhere), and `comp_allocation.granted_to_name` /
`guest_entry.guest_name` remaining readable by owner ruling — those are venue-authored lists, not
purchaser rosters.
