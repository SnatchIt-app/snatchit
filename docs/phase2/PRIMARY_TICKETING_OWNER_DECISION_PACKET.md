# Primary ticketing — owner decision packet

**Status:** decisions REQUIRED. Nothing here is implemented. No migration is authored. Production is
unchanged and every rail remains dark.

**How to read this.** Six decisions block venue-direct ticketing. Each states what the system does
today, why a decision is needed, the realistic options, a recommendation, and how that
recommendation is classified against the frozen architecture. Full evidence, with `file:line`
citations, is in `docs/phase2/_decisions/`.

**One sentence of context that changes everything else.** The database for venue-direct ticketing is
finished and deployed. What blocks a first ticket is not engineering volume; it is six rulings, one
migration, two edge functions and a client.

---

## Decision A — how a venue actually gets paid

**Current.** Money moves today by separate charges and transfers: the PaymentIntent is created on
the platform account with no `transfer_data`, no `on_behalf_of` and no application fee, funds land
in the platform balance, and a seller is paid later by a transfer with `source_transaction` set to
the funding charge. For a venue-direct sale, `venue.finalize_primary_order` writes no payout, no
settlement and no settlement line. There is exactly one `INSERT` into `venue.settlement_line` in the
entire repository, and its two sources are the resale royalty seam and the negative promoter
commission seam. **No primary-sale revenue line exists anywhere.** Gross is therefore always zero,
the payout condition never fires, and no venue payout is ever minted. Turning the payout rail on
later does not fix this, because the line does not exist to be paid.

**Why a decision is required.** Selling now would mean taking real money for a venue and having no
row in any table that says what the venue is owed. The debt would be reconstructable only from
Stripe history, which is the specific failure the architecture was designed to avoid.

**Options.**

| | Approach | Trade |
|---|---|---|
| 1 | Platform collects; the obligation is a `primary_sale` settlement line minted at settlement close by a third seam | No Stripe change, no money-ledger DDL, compatible with the ratified promoter Option B |
| 2 | Same, but the line is minted at sale inside `finalize_primary_order` | Strongest fact, but amends a frozen contract and adds lock pressure to the hottest money path |
| 3 | Destination charges; the venue becomes merchant of record | Stripe becomes the ledger, but every account needs re-onboarding and it breaks promoter Option B |
| 4 | Per-order immediate transfer, resale-style | Closest to proven code, but pays the venue before commission can be deducted |

**Recommendation: Option 1.** Add a `settlement_primary_lines` seam and replace `close_settlement`'s
body so it unions three seams instead of two.

**Why.** The cause code `primary_sale` already exists in the schema. The frozen contract already
assigns write authority to the settlement close engine and already defines gross as the sum of
positive revenue lines. Seam replacement is the established mechanism, used twice before. A writer
was simply never written.

**Classification: IMPLEMENTATION FOLLOW-UP**, with two carve-outs: the revenue split percentage is
**OWNER POLICY** because no frozen key defines it, and the `public.payments` change it depends on is
a **POST-FREEZE AMENDMENT** (see Decision E).

**093 impact:** one new seam function, one `CREATE OR REPLACE` of `close_settlement`, two additive
partial unique indexes, a refund arm, one config key. No DDL on any money ledger table.
**Edge impact:** `primary-checkout`, the webhook's native branch and `payout-execute` must be
authored. **Stripe impact:** none to the charge model.

**Three failure modes the owner should know about.**
1. **Silent non-recognition.** Nothing opens a settlement automatically; it is a manual finance
   action. Switch collection on without it and you are in today's state with real money in it. This
   needs an alert on paid orders that have no revenue line.
2. **Cross-settlement double-lining.** The existing uniqueness is scoped to one settlement. The
   promoter package solved this for commissions with a partial unique index; primary sales have no
   equivalent yet. Without it a line can be paid twice, and the append-only trigger means the bad
   line can never be deleted.
3. **`source_transaction` does not generalize.** One settlement payout has many funding charges, but
   Stripe accepts one source transaction and the payout row records one reference. This must be
   resolved on paper before the payout executor is written.

**OWNER RULING REQUIRED:** approve Option 1, and set the platform's revenue share on direct sales.

---

## Decision B — credential signing and dual control

**Current.** `kernel.provision_signing_key` and `rotate_signing_key` are unconditional raises,
parked because the ratified dual-control mechanism was found unbuildable. Production holds zero
signing keys.

**The finding that sizes this decision.** A display-only launch does **not** avoid the problem.
Ticket display already works with no new cryptography, and the door, Wallet and credential-signing
rails are cleanly separable. But ticket *existence* is not: `signing_key_id` is NOT NULL, the
foreign key restricts deletion, and the mint requires an active, in-window key. **You cannot skip
the key by skipping the QR code.** Launch needs one row truthfully referencing one real key.

**A second finding.** In-database dual control is not merely unbuildable, the second approver does
not exist: the platform role table is unmintable and the admin allowlist is a single row. The
separation-of-duties check could never be satisfied.

**Recommendation.** Two-person key creation in KMS with IAM controls, plus one owner-signed
bootstrap key row in the migration. The database RPCs stay parked. Use the algorithm the frozen
architecture already specifies; invent nothing.

**Classification: POST-FREEZE AMENDMENT** (owner-signed and narrow), plus **OPERATIONAL CONFIG** for
the KMS and runbook, plus a deferred **IMPLEMENTATION FOLLOW-UP** for real dual control before
scanning activates.

**Two traps for whoever writes 093.** The parked function is granted to `authenticated` and is safe
only because it raises first, so a naive un-park exposes it to every signed-in user. And key scope
resolution prefers per-event over global, so a per-event key silently outranks the bootstrap key
with no collision and no alert.

**Most serious threat.** Not forged entry, since the door gate does not exist yet. It is that a
wrong key at launch is silent, deferred and permanent: the key is pinned at mint, rotation never
re-pins, revoke is parked, and the foreign key blocks deletion. It would be discovered only when
scanning turns on, and every ticket sold until then would carry it.

**OWNER RULING REQUIRED:** approve the KMS ceremony and sign the bootstrap key row.

---

## Decision C — venue operatorship transfer

**Current exploit.** When a venue moves between organizations, nothing clears its staff roles and
the events keep their original organization stamp. A previous operator's manager retains a large
set of capabilities over the new operator's venue.

**A correction to the prior review.** The current-operator conjunct that package 087 applies does
**not** defend the scenario. It compares the venue's organization to the scope object's, so the new
operator's own events satisfy it and every bound verb passes for the previous operator's manager.
The only thing that closes it is clearing staff roles on transfer.

**Verified capabilities retained today**, with flags as seeded: read the new operator's draft
events; create, update, publish and cancel their events; re-price ticket types; change capacity; set
resale policy including royalty; open and close door manifests, which irreversibly engages a one-way
freeze; mint door PINs and scan devices; allocate comps; manage guest lists; grant five staff labels
and revoke every manager the new operator seats; org-wide authority over their promoter program
including commission rates; and rename the venue. On rail activation this extends to orders
including buyer identity and totals, tickets, holds and scans.

**An amplifier both prior documents missed:** the retained manager can seat a finance confederate,
which is the label that unlocks settlement operations.

**Severity: P1, not activation-blocking.** The transfer verb is platform-admin only, reason-coded
and audited, with no client caller anywhere. The residual path is direct SQL as a superuser.

**Does the freeze close it? Yes, provably.** A writer census shows exactly one site that repoints a
venue's organization, one event insert with a server-derived organization, an update verb that
rejects both fields, and no organization merge or re-parent verb anywhere. Absent a transfer, the
invariant holds by construction.

**Recommended enforcement, three layers.**
1. A `CREATE OR REPLACE` of the transfer verb in 093, byte-identical except that it refuses a
   request carrying an organization change. Not a revoked grant, which would kill benign profile
   edits, and not a config flag, because the config setter cannot create keys.
2. A written no-direct-SQL policy and an admin roster review.
3. CI: a test asserting the refusal, plus a standing invariant that no event's organization differs
   from its venue's. That invariant is the only control that catches a superuser transfer.

**Classification: IMPLEMENTATION FOLLOW-UP.** Lifting the freeze later requires a real atomic
transfer and would be a **POST-FREEZE AMENDMENT**.

**OWNER RULING REQUIRED:** confirm the freeze for launch.

---

## Decision D — deletion and refunds

**Is a waiting period required? No, and it is the wrong instrument.** Set the refund window to zero.
The ratified machine already accepts that chargebacks land against the tombstone with no waiting
window, and a refund is strictly easier than a chargeback. A clock would also be the only
time-driven member of a closed set of eleven event-driven predicates. Zero disables the arm cleanly
and needs no migration.

**The status quo is untenable, though.** With the key unset, one paid direct order makes that buyer
**permanently undeletable**, because the order table is immutable and a normally consumed order
stays paid forever. Harmless while dark; an erasure-law and app-store failure the moment direct
selling starts.

**A second permanent-block risk, larger than the first.** A ticket expiry configuration key is
unseeded, and the expiry sweep returns zero while it is unset. A no-show buyer's ticket therefore
never expires, and the live-custody blocker never clears. **This needs no money at all to trigger**
and must be set before the direct rail goes live.

**What happens to a direct ticket on deletion.** The request is always accepted, then the
live-custody blocker holds. The holder has no disposal path: native resale is flag-gated off and
peer transfer is parked fail-closed, so the blocker clears only by scan, void or expiry.

**Can a refund reach a tombstoned identity? Yes, and it already works.** Event cancellation never
reads deletion state; it walks tickets to the payment and books the refund against it, and the
Stripe payment reference survives erasure. A Stripe refund binds to the payment, not the customer.
One policy gap worth stating: a gifted ticket refunds the original payer, not the holder.

**The executor gap.** A recorded refund never pays anyone: the RPC inserts a pending row and makes
no Stripe call, and there is no claimer, no tick and no executor. Worse, that pending row then
permanently blocks the buyer's deletion. Exactly one automatic refund path exists on the legacy rail
and it should be extended rather than replaced.

**Recommendation.** Window zero, and treat refund **executability** as a hard precondition of selling
direct tickets. Dashboard-only refunding is not acceptable alone, because it leaves rows pending
forever. Dashboard plus a named write-back process is acceptable for a limited launch, but building
the executor is cheaper than operating that process.

**Classification:** window value is **OWNER POLICY** executed as **OPERATIONAL CONFIG**; the expiry
key is **OPERATIONAL CONFIG**; the executor is **IMPLEMENTATION FOLLOW-UP**; tombstone refund
reachability is **WITHIN FROZEN ARCHITECTURE**. **No post-freeze amendment needed. No 093 required**
unless the executor is database-tick-driven.

**OWNER RULING REQUIRED:** set the window to zero, set the expiry key, and decide executor versus
named manual process.

---

## Decision E — the payments reshape

**Current deficiency, confirmed.** `public.payments` requires a listing, a seller and a resale mode.
A venue-direct order has none of the three. The native payment table has a NOT NULL foreign key to
it, and finalize raises if no row is found, so the requirement is bolted in twice, both inside
frozen package 085. The proof is already in the repository: the existing money test suite has to
fabricate a fake Miami listing and a fake seller purely to give finalize a payment row, which is
exactly the workaround the freeze forbids.

**One correction to the earlier report.** The one-success-per-listing index does **not** need
rescoping. It carries no clause making nulls equal, so rows with no listing are all distinct to it.
The index stays byte-identical for resale and becomes an automatic no-op for direct sales. Separately,
the `mode` column has zero SQL consumers anywhere; the payment dispatch reads Stripe metadata, not
the column.

**Does a genuinely additive path exist? No.** Carrying the fact entirely in a Phase-2 table would
require replacing an authored-once money verb, which the governance record explicitly classifies as
requiring an owner-signed amendment, plus relaxing a frozen foreign key, plus amending three sections
of the schema specification. It is the largest amendment, not the smallest. And synthesizing a
sentinel listing is forbidden twice in the record, in one place verbatim: no fake listing row, and no
column added to the frozen payments table ever. A single sentinel would also cap the platform at one
direct sale forever through that same index.

**Blast radius: 87 sites**, 47 in SQL and 40 elsewhere; 18 name the three columns and 12 sit on the
live resale path. The worst three would fail silently rather than loudly: a constraint violation
swallowed behind a success response, a duplicate guard that stops matching, and a seller screen that
renders blank money with no error.

**Recommendation: constrained relaxation.** Drop the two NOT NULLs, widen the mode, and in the same
transaction re-impose both requirements conditionally through a rail-pairing check. Every one of the
twelve breakages needs a *resale* row carrying a null, and the check makes that unstorable. **Net
loosening of the resale rail: zero.** Fifty-six production rows, no table rewrite, sub-second.

**The earlier adversarial finding was half right.** Native payments do become invisible through the
seller-side policy, but that is *correct*: there is no seller, and the buyer still sees their own row
because buyer identity stays required. No organization-scoped policy is needed, because nothing
venue-facing reads that table; none is implementable, because the native payment table is revoked
from client roles; and adding one would fail an existing test that pins the policy count. The
migration should add no policy and instead assert the invisibility.

**POST-FREEZE AMENDMENT REQUIRED: YES, exactly one.** Ratify the existing payments-shape obligation
and re-scope it from resale-only to both rails. Notably this path leaves the edge specification, the
schema specification's core sections and the whole of package 085 unamended, with no money-verb
rewrite.

**Classification: OWNER POLICY, then POST-FREEZE AMENDMENT, then implementation in 093.**

**OWNER RULING REQUIRED:** ratify the re-scoped payments obligation and approve constrained
relaxation.

---

## Decision F — attendee privacy

**What a venue can see today.** No deployed verb returns an attendee name or email to any venue
role. The ticket table was scoped correctly, excluding the owner column. Door surfaces are
ticket-grain with no identity.

**The one real hole, and it is not a verb.** The order table is granted at table grain, so buyer
identity is readable by manager and finance roles, and any signed-in user can read display names.
One join produces an attendee roster with money attached: no audit row, no rate limit, no consent
gate. The parked CRM verbs do not close this; they only close the audited door. It is inert today
and live the moment issuance flips.

**Minimum door dataset: six facts.** Signature validity, admissibility, session binding, duplicate
detection, ticket type for routing, and a speakable serial. The deployed door manifest already
returns exactly this, and it is tighter than the spec's "name plus validity", which belongs to a
box-office single-record lookup rather than a scanner device.

**Recommended posture.** A venue gets everything needed to run a door and a box office: ticket
status and type, check-in, a masked order reference, purchase time, refund state, money for manager
and finance, and promoter attribution. It gets **no attendee name and no email by default**, because
the mechanism that makes those tenant-safe is parked with no ratified implementation. After that
un-park, name and email are on request with audit, one record at a time, with email additionally
behind the buyer's own consent. Finance sees money and no contact; marketing sees contact and no
money; only manager and organization owners hold the union. The scanner sees the six facts and
nothing else, because it is a shared device in a stranger's hands.

**Stays dark at launch:** both attendee verbs, all exports for every role, and all demographics.
Phone, legal name and individual demographics are never visible.

**093 work: one required item.** Column-scope the order table to omit buyer identity, using the same
pattern already applied to the ticket table. The owner's own read is unaffected because that is a
policy predicate rather than a column grant. **Classification: IMPLEMENTATION FOLLOW-UP.**

**OWNER RULING REQUIRED:** approve the launch matrix and the default-no-contact posture.

---

# Proposed 093 contents — NOT AUTHORIZED

This is what migration 093 would need if every recommendation above is accepted. **It is a
description, not a migration.** Nothing has been authored.

### MUST be in 093
1. **The signing-key bootstrap row** (Decision B). One owner-signed key, created two-person in KMS.
   Without it no ticket can be minted at all.
2. **The two inventory configuration rows** (`hold_ttl_interval`, `per_user_active_hold_max`). They
   do not exist and the config setter refuses unknown keys, so only a migration can create them.
   Until they exist every reservation fails closed.
3. **The `public.payments` shape change** for direct orders (Decision E), together with its
   replacement seller-side policy in the same migration. Never one without the other.
4. **The operatorship-transfer freeze** (Decision C): a body-only replacement that refuses an
   organization change.
5. **Column-scoping the order table** to omit buyer identity (Decision F).

### SHOULD be in 093
6. **The primary-sale settlement seam and the `close_settlement` replacement** (Decision A), plus
   the partial unique index that prevents cross-settlement double-lining.
7. **The ticket expiry configuration key** (Decision D), without which tickets never expire and
   deletion blocks forever.
8. **Emitting the purchase and ticket-ready notices** on the direct rail, which currently emits
   nothing.

### MUST NOT be in 093
- Any change to migrations 076 through 092. They are immutable.
- Un-parking the signing-key RPCs. The bootstrap row does not require it, and un-parking would
  expose a function granted to every signed-in user.
- Un-parking the attendee verbs or anything CRM.
- Any feature flag flip. Flags are configuration, not migration.
- A lease column on the refund table. The existing unique key makes it unnecessary.
- Anything to do with Wallet, scanning, native resale or promoter payouts.

### CONFIG after 093
- The refund window set to zero.
- The ticket expiry value.
- The inventory hold values.
- PostgREST exposure of the venue and catalog schemas.
- The issuance feature flag, flipped last, after everything else is verified.

### EDGE work after 093
- `primary-checkout`, which mints the PaymentIntent.
- The webhook's native branch, which calls finalize on payment success. Note that the current
  webhook returns a non-success status for an unknown mode, so a native charge would retry for days
  until this branch exists.
- The refund executor, or the named manual write-back process.
- The payout executor, once the source-transaction question is settled on paper.

### OWNER action after 093
- Sign the bootstrap key ceremony.
- Set the platform revenue share on direct sales.
- Approve the attendee privacy matrix.
- Confirm the operatorship freeze and the no-direct-SQL policy.
- Decide refund executor versus manual process, and name the human who owns it.
- Accept, in writing, how a venue is paid until the settlement seam ships.
