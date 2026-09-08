# Migration 093 — final proposed scope

**Status: PROPOSAL. NOT AUTHORIZED. NOT AUTHORED.** No `.sql` file exists. Nothing here has been
written, applied, or tested against any database. This document describes what a migration would need
to contain if the rulings in `PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md` are signed. Those rulings are
themselves unsigned.

**Governing constraint, verbatim from the owner:** *"Keep 093 as small as safely possible."* Every
item below had to earn its place against four questions, and six candidates failed and were moved
out.

**Two facts that recur in every justification, so they are stated once here.**

- **WHY NOT CONFIG, the general case.** `catalog.set_platform_config` raises
  `precondition_failed: unknown_key` for any key not already present (`078:1103`). A key that does
  not exist cannot be created by configuration, only by a migration. There is no exception to this.
- **WHY NOT EDGE, the general case.** `venue.create_primary_checkout`, `catalog.publish_event` and
  both organization binders are granted to `authenticated` and reachable through PostgREST in one
  call. An edge function cannot defend a door it does not stand in front of. Where a control must
  hold against a direct client call, it belongs in SQL, and the edge check is defence in depth.

---

# Recommendation: ONE migration, not a 093–095 split

**A split was seriously considered and is rejected, on one decisive ground: no intermediate state is
sellable, so no boundary is a real milestone.**

Under any ordering, 093-alone and 093+094 both leave a system that can take real buyer money with no
row saying what the venue is owed. A boundary you cannot launch from is not a milestone; it is an
invitation to launch from it anyway, because the intermediate state *looks* finished and is one
configuration flip from disaster. The whole purpose of these rulings is that money must not move
before the obligation is a ledger fact.

Three further arguments against splitting:

1. **It converts an in-file ordering requirement into a cross-migration hazard.** The checkout gate
   reads a column created by the state-mirror item. Split them and a partially-applied system raises
   an undefined-column error on the buyer-facing checkout door, instead of cleanly refusing the sale.
2. **It triples the replay-parity surface.** Each migration is a separate apply, verification and
   ledger-reconciliation event against production.
3. **The usual reasons to split do not apply here.** The only lock that matters is on
   `public.payments`, which is 56 production rows and a catalogue-only change; every other item is a
   function replacement, which locks `pg_proc` and nothing else. And the one genuinely irreversible
   item, the signing-key row with its `ON DELETE RESTRICT`, becomes irreversible when the issuance
   flag is flipped, not when the migration applies.

**Manifest of the recommended single migration:** 0 new tables, 2 new columns, 0 new enum members,
0 new policies, 0 DDL on any money-ledger table, and `venue.finalize_primary_order` untouched.

---

# IN — the proposed contents

## 1. `public.payments` relaxation, rail-pairing check, seller-policy null-guard

*Ruling E.* Drop the two NOT NULL constraints, widen the mode, and in the same transaction re-impose
both requirements conditionally through a rail-pairing check, so a resale row carrying a null stays
unstorable. Ship the seller-side policy replacement in the same migration, never one without it.

- **WHY 093** — `NOT NULL` is a storage wall, not a behaviour. `public.payments.listing_id` is
  `NOT NULL REFERENCES public.listings` (`000_baseline_schema.sql:973`) and no application code can
  store a row that violates it.
- **WHY NOT EDGE** — an edge function cannot relax a constraint. This is the item that makes every
  other direct-rail item reachable: `kernel.payment_native` has a NOT NULL foreign key to this table
  and `venue.finalize_primary_order` raises if no row is found (`085:1919-1934`), so the requirement
  is bolted in twice inside frozen package 085.
- **WHY NOT CONFIG** — not a value.
- **WHY NOT LATER** — it gates the entire feature. Nothing else in this migration can be exercised
  while a direct sale cannot record a payment.

*Notes for the author:* atomic with the CHECK, no `NOT VALID`. Use a `lock_timeout`. The
one-success-per-listing index does **not** need rescoping — it has no clause making nulls equal, so
rows with no listing are all distinct to it and it becomes an automatic no-op for direct sales.

## 2. Signing-key bootstrap row

*Ruling B.* One owner-signed key row, created two-person in KMS.

- **WHY 093** — the provisioning RPC is an unconditional raise, so the migration is the only writer.
- **WHY NOT EDGE** — `service_role` holds `USAGE` only on the `kernel` schema; the edge role
  physically cannot insert the row.
- **WHY NOT CONFIG** — a key row is not a configuration value.
- **WHY NOT LATER** — `kernel.tickets.signing_key_id` is NOT NULL and the mint requires an active,
  in-window key. No ticket of any kind can exist without this row, so it is not deferrable behind a
  display-only launch.

*This item is 093's critical path*, because it depends on an owner ceremony rather than on
engineering. It should be scheduled first.

## 3. Three configuration key rows

*Rulings D2 and inventory readiness.* `inventory.hold_ttl_interval`,
`inventory.per_user_active_hold_max`, `ticket.expiry_grace` — created with values, or created and set
immediately after.

- **WHY 093** — all three are unseeded; the seeded key list contains none of them.
- **WHY NOT EDGE** — the config table is revoked from client roles and the setter refuses unknown keys.
- **WHY NOT CONFIG** — this is the general case above: configuration cannot create a key.
- **WHY NOT LATER** — the first two fail every reservation closed, so nothing can be bought at all.
  The third is worse in kind: while it is unset the expiry sweep returns zero, so a no-show buyer's
  ticket never expires and that buyer becomes **permanently undeletable**. That failure needs no money
  to trigger.

## 4. Column-scope `venue."order"` to omit buyer identity

*Ruling F.*

- **WHY 093** — a column-level `GRANT` is DDL.
- **WHY NOT EDGE** — the table is readable directly through PostgREST; an edge function cannot
  intercept that read.
- **WHY NOT CONFIG** — not a value.
- **WHY NOT LATER** — deferring it makes an attendee roster with money attached one join away, with no
  audit row, rate limit or consent gate, gated only by a dashboard toggle. Doing it now removes the
  ordering hazard entirely.

## 5. Two Connect state-mirror columns on `kernel.organization`

*Ruling A6.* `connect_transfers_active` and `connect_state_synced_at`. **Two, not six.**

- **WHY 093** — adding a column is DDL. It is additive and alters no existing constraint, which is what
  keeps it an implementation follow-up rather than a post-freeze amendment.
- **WHY NOT EDGE** — a SQL gate predicate cannot call Stripe. The fact has to be in the row the gate
  reads.
- **WHY NOT CONFIG** — per-organization state, not platform configuration.
- **WHY NOT LATER** — item 7 reads this column. Ship them apart and the buyer-facing checkout raises an
  undefined-column error instead of refusing the sale.

*The four columns that were cut* — payouts-enabled, disablement reason, requirement deadline,
outstanding-requirements flag — have no reader in the ruled design, and two of them would duplicate
columns that already exist on the individual plane. Cutting them is what makes this item honour the
owner's constraint against copying Stripe's account object into Postgres.

## 6. `kernel.sync_org_connect_state`, service_role only

*Ruling A6.*

- **WHY 093** — a new function is DDL, and only a definer function can write a table the edge role
  cannot reach.
- **WHY NOT EDGE** — `service_role` holds `USAGE` only on `kernel` and cannot `UPDATE`
  `kernel.organization` directly.
- **WHY NOT CONFIG** — not a value.
- **WHY NOT LATER** — without a writer, `connect_transfers_active` is false forever and the gate in
  item 7 refuses every sale permanently. It ships with the columns or not at all.

*Must be non-monotonic:* the flag has to be able to return to false, unlike `stripe_onboarding_complete`
(`create-connect-account:281`), or an account Stripe later disables stays sellable forever.

## 7. The checkout readiness gate, unconditional

*Ruling A6.* A precondition inside `venue.create_primary_checkout`: bound account reference present
**and** `connect_transfers_active`.

- **WHY 093** — replacing the function body is DDL.
- **WHY NOT EDGE** — the function is granted to `authenticated`. The edge check is defence in depth.
- **WHY NOT CONFIG** — **deliberately no key.** A configuration key whose only function is switching
  off the gate that protects money is not minimality; it is a second way to be wrong.
- **WHY NOT LATER** — this is the gate that protects money, and it is self-healing: it stops sales the
  moment Stripe disables an account, with no sweep and no backward event transition.

## 8. `kernel.set_org_connect_ref` — hardened

*Rulings A4 and A5.* Refuse any account identifier the platform did not mint for that organization,
at minimum refusing any identifier present in `public.profiles.stripe_connect_id`; restrict to
`org_owner`; require organization status `approved` or `active`; require aal2; emit
`security_payout_destination_changed`.

- **WHY 093** — function body replacement is DDL.
- **WHY NOT EDGE** — the RPC is granted to `authenticated`, so an edge-side check is bypassed by one
  direct call. This is the single highest-value item in the migration: it closes the
  personal-Stripe-account attach, which is the most likely attack and has total financial impact.
- **WHY NOT CONFIG** — authority rules are not values.
- **WHY NOT LATER** — the attack is live-reachable the moment an organization exists.

*Two author's notes.* `CREATE OR REPLACE` cannot drop a parameter, so what eliminates the
caller-supplied identifier is a **refusal in the body**, not a signature change. And no money-role
maturity requirement is imposed on the **first** bind: it would force a waiting period before
onboarding can start, at a moment when no money is yet at risk. Requiring `approved`/`active` status
here also subsumes the probation-clock defect, because a bind can no longer precede approval.

## 9. `kernel.set_org_payout_destination` — hardened

*Rulings A4 and A5.* The same refusal of non-platform-minted identifiers, plus an organization-status
gate, plus the notification emit.

- **WHY 093** / **WHY NOT EDGE** / **WHY NOT CONFIG** — as item 8; also granted to `authenticated`
  (`085:2137`).
- **WHY NOT LATER** — hardening only the first bind leaves the re-point verb able to redirect
  settlement money to a personal seller account, invisible to `077:124-126` because that index cannot
  see the individual plane. A suspended organization can also re-point today.

## 10. The platform revenue-share key row, value null

*Ruling A8.* Create the key. Do not set it.

- **WHY 093** — the key does not exist and configuration cannot create it.
- **WHY NOT EDGE** — not an edge concern.
- **WHY NOT CONFIG** — the general case; the *value* is configuration and is set later by the owner
  without a migration, which is exactly the point of creating the key now.
- **WHY NOT LATER** — this is the one place where "later" is unrecoverable. Settlement lines are
  append-only and the settlement header is write-once, so revenue recognised before the key exists
  cannot be restated afterwards.

## 11. `kernel.settlement_primary_lines` — the revenue seam

*Ruling A7.* A new seam emitting positive `primary_sale` lines, with an explicit negative refund arm.

- **WHY 093** — a new function is DDL, and the close engine's seam set is fixed in SQL.
- **WHY NOT EDGE** — `close_settlement` runs the seams inside one transaction; an edge function cannot
  participate in it, and a line written outside that transaction breaks the waterfall invariant.
- **WHY NOT CONFIG** — not a value.
- **WHY NOT LATER** — without it, gross is structurally zero, no organization payout is ever minted,
  and every commission is a debit against nothing. This is the item the whole feature exists for.

*Design constraints:* pure and `stable`; fail inert if the revenue-share rate is absent rather than
guessing; represent a refund as its own negative line and never by amending the original, which the
append-only trigger forbids.

## 12. `close_settlement` body — three-seam union, named conflict clause

*Ruling A7.* Inseparable from item 13.

- **WHY 093** — body replacement is DDL.
- **WHY NOT EDGE** / **WHY NOT CONFIG** — as above.
- **WHY NOT LATER** — the seam in item 11 is unreachable until the close engine unions it.

*The correction that matters:* the existing `ON CONFLICT` at `087:320` is written against an inferred
constraint and will abort closes once item 13's index exists. It must name the constraint it
tolerates. A **bare** `DO NOTHING` is forbidden — it would swallow conflicts on any index and silently
drop an already-lined order out of gross, underpaying the organization in a ledger that has no delete.

## 13. Two partial unique indexes

*Ruling A7.* Global uniqueness on the primary-sale cause reference and its refund counterpart, in the
shape already used for promoter commissions at `090:214-215`.

- **WHY 093** — index creation is DDL.
- **WHY NOT EDGE** — an application-level check cannot be transactionally safe against concurrent
  closes.
- **WHY NOT CONFIG** — not a value.
- **WHY NOT LATER** — the existing uniqueness is per-settlement (`087:105`), so the same order can be
  lined in two settlements and paid twice, and the append-only trigger means the bad line can never be
  deleted. Adding the index after the first double-line is too late by construction.

## 14. `settlement_commission_lines` — exclude `partially_refunded`

*Not on the original candidate list; the evidence put it here.* The commission seam excludes fully
refunded orders but not partially refunded ones, and a direct partial refund voids no atoms
(`085:562-564`), so the commission basis is unreduced and **full commission is paid on partly refunded
revenue**.

- **WHY 093** — body replacement is DDL.
- **WHY NOT EDGE** / **WHY NOT CONFIG** — as above.
- **WHY NOT LATER** — 093 is what activates this seam by giving it revenue to deduct from. Over-paying
  a promoter is unrecoverable in an append-only ledger; over-correcting is reversible.

## 15. The operatorship-transfer freeze

*Ruling C.* Body-only replacement of `catalog.update_venue` refusing an organization change, extended
to refuse while the departing organization holds a `pending` or `submitted` payout.

- **WHY 093** — body replacement is DDL.
- **WHY NOT EDGE** — there is no edge caller to intercept; the residual path is direct SQL.
- **WHY NOT CONFIG** — the config setter cannot create the key this would need, and a revoked grant
  would kill benign venue profile edits.
- **WHY NOT LATER** — the prescribed mechanism is already ruled and unbuilt, and the change is roughly
  fifteen lines.

**Dissent recorded.** The independent migration-design review would move this item **out**, arguing
that money never follows a venue — the payee is the sale-time `settlement.org_id`, never re-resolved
(`087:341-343`) — that the verb is `platform_admin`-only with zero client callers, and that the
severity is P1. That reasoning is sound and the owner may prefer it. It is kept in here because the
deferral's safety rests on a person remembering not to perform a transfer, while the code change is
a body-only replacement with essentially no risk surface. **If the owner defers it, the condition is
explicit: no venue operatorship transfer may be performed until it lands.**

---

# OUT — deferral is safe, and why

Each of these was a candidate and each was moved out deliberately, so that silence is not read as an
oversight.

| Item | Why it is safe to defer |
|---|---|
| Gating `publish_event` on Connect readiness | `announced` is marketing state with nothing purchasable (`081:920`). Gating it blocks promotion that costs nothing and risks nothing. Item 7 is the gate that protects money. |
| A `venue.require_connect_for_on_sale` key | Declined outright. A key whose only job is disabling the money gate is a second way to be wrong. |
| The four other Stripe mirror columns | No reader exists in the ruled design. They become justified when an operator console exists. |
| A separate probation-clock fix | Subsumed by item 8: requiring `approved`/`active` at bind means a bind can no longer precede approval. |
| Seeding `payout.destination_cooldown_hours` | The key exists; only its value is null. That is configuration, not a migration. It must still be set before activation. |
| Mapping `unique_violation` to a friendlier error | Cosmetic. |
| The commission seam's ability to raise out of `close_settlement` | Real and contradicts `087:204-207`, but it is the highest-priority follow-up rather than a blocker, because the seam is inert until 093 gives it revenue. |
| Purchase and ticket-ready notifications on the direct rail | **The one item where an edge function genuinely can do the work.** |
| Settlement header period uniqueness / overlap constraint | Item 13's global index converts the race into a clean failure rather than a double payment. The entitlement rule is ruled in A7 and can be enforced later. |
| In-database dual control on destination changes | Blocked by a frozen CHECK. Named as unbuilt in ruling A5. |
| A fee-shaped settlement cause | Only needed if the owner picks the settlement-deduction economics in A8, which would be a post-freeze amendment in its own right. |
| Un-parking the signing-key RPCs | Ruling B forbids it; the bootstrap row does not require it and un-parking exposes a function granted to every signed-in user. |
| Requiring a second money principal structurally | Ruling A5 requires it before payout; enforcing it in schema is a later refinement. |

---

# What is still NOT true after 093 lands

Stated plainly, because a migration that makes the system *look* finished is the specific risk of this
whole exercise.

- **No venue can actually be paid.** The `source_transaction` mapping for a settlement payout with
  many funding charges is unresolved on paper, and no payout executor exists.
- **No buyer can actually be refunded.** The buyer loses the ticket and gets no money. Ruling A9 makes
  this a hard precondition of selling, and 093 does not satisfy it.
- **No promoter can be paid.** Commission payouts mint held and nothing releases them.
- **Settlements are still opened by hand.** Nothing opens one automatically, so the standing report on
  paid orders with no revenue line is a launch requirement, not a nicety.
- **Disputes never resolve.** `kernel.resolve_dispute_native` always raises.
- **Booked events cannot be settled at all** where the event's organization differs from the venue's.

**Required before activation but outside this migration:** the `connect-onboarding` edge function, the
`primary-checkout` edge function, the webhook's native branch and its organization arm for
`account.updated`, and the refund executor or its named manual substitute.

**Required configuration after 093:** the platform revenue share, the refund window set to zero, the
ticket expiry value, the inventory hold values, `payout.destination_cooldown_hours`, PostgREST
exposure of the venue and catalog schemas, and the issuance feature flag — flipped last, after
everything else is verified.

---

# Ordering and locking

- **Items 5 and 6 and 7 are a unit.** The gate reads a column written by a verb that ships with it.
  Applied out of order, the buyer-facing checkout raises an undefined-column error rather than
  refusing a sale.
- **Items 11, 12 and 13 are a unit.** The seam is unreachable without the union, and the union without
  the index is a double-payment hazard in a ledger with no delete.
- **Item 1 gates everything on the direct rail** and should apply first among the DDL items.
- **Item 2 is the critical path** because it waits on an owner ceremony, not on engineering.
- **One lock matters: `public.payments`.** Use an explicit `lock_timeout`. Everything else is function
  and index work.
- **Everything here is safe to apply while the rails are dark**, which is the entire reason the
  sequencing is tractable.

---

**Nothing in this document has been authorised, authored, or applied.**
