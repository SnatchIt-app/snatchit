# Primary ticketing — final owner rulings

**Status: DRAFT. NOT APPROVED. NOT SIGNED.** Every ruling below carries approval text written so the
owner can adopt it verbatim. No ruling in this document has been adopted. Nothing here has been
implemented. Migration 093 has not been authored. Production is unchanged and every Phase-2 rail
remains dark.

**Supersedes nothing yet.** On signature this document becomes the controlling record for the six
decisions in `PRIMARY_TICKETING_OWNER_DECISION_PACKET.md` plus the two upstream decisions that were
found to sit above them.

**Evidence.** Every claim is cited `file:line` against the branch tip. The underlying research is in
`docs/phase2/_rulings/`: `A_stripe_flow_map.md`, `B_frozen_normative_review.md`,
`C_money_ledger_accounting.md`, `D_promoter_settlement.md`, `E_refunds_disputes.md`,
`F_org_onboarding.md`, `G_onboarding_security.md`. Prior evidence is in `docs/phase2/_decisions/`.

**Classification vocabulary**, used on every ruling: WITHIN FROZEN ARCHITECTURE · IMPLEMENTATION
FOLLOW-UP · OWNER POLICY DECISION · OPERATIONAL CONFIG · POST-FREEZE AMENDMENT.

---

# Part 0 — the two decisions that sit above the other six

The previous packet asked the owner to rule on six things. Research found that two prior questions
were never asked, and that both of them change the answers to the six.

### Decision 1 — who is the merchant and business of record for a venue-direct primary sale?

It was never ruled. It was assumed, twice, in opposite directions, and the assumption is load-bearing
for the charge model, the refund model, the dispute model and the promoter model.

### Decision 2 — how does a venue organization become connected to Stripe at all?

There is no path. `kernel.organization.stripe_connect_account_ref` (`077:114`) has exactly two
writers, `kernel.set_org_connect_ref` (`077:948`) and `kernel.set_org_payout_destination`
(`085:1601`), and **both have zero callers** in any application, web, or edge-function file. There is
no `connect-onboarding` edge function, though `PHASE_2_EDGE_FUNCTION_SPEC.md:439` specifies one and
the SQL binder's own error text names it: *"connect-onboarding must use the caller's Authorization
header"* (`077:964`).

**Consequence, stated plainly: no venue organization can be paid today, under any of the six
decisions, regardless of how they are ruled.** Decision A of the previous packet is unreachable until
Decision 2 is answered. That is why these two come first.

---

# Part 1 — rulings A1 through A9

Decision A of the previous packet ("how a venue actually gets paid") is decomposed into nine rulings
because it turned out to contain two upstream decisions, one supersession of the written corpus, one
security posture change and one genuine pricing choice. Ruling them as a single yes/no would have
hidden all five.

---

## A1 — Merchant and business of record

**Finding.** Snatch It is already the merchant of record for 100% of money it takes today, by
construction and not by choice. On the live resale rail the card is charged with a bare PaymentIntent
on the platform account — the complete parameter set is amount, currency,
`automatic_payment_methods[enabled]`, customer, `setup_future_usage` and four metadata keys
(`create-payment-intent/index.ts:513-527`). Repo-wide code hit counts: `transfer_data` **0**,
`on_behalf_of` **0**, `application_fee_amount` **0**, `application_fee` **0**, `Stripe-Account` **0**.
The last of those is not merely unused but unrepresentable: `_shared/stripe.ts` has no header
passthrough.

**A precision the owner should not be denied: there is no shipped direct-rail charge at all.** Grep
returns zero references to `venue.create_primary_checkout` or `venue.finalize_primary_order` from any
edge function or web file. So for the direct rail this ruling is not ratifying existing behaviour —
it is choosing the behaviour before it is written. What the shipped bytes *do* establish is that the
platform has no capability to do anything else: every connected account in production is Express, US,
`business_type=individual`, with `capabilities[transfers][requested]` only
(`create-connect-account/index.ts:202-210`), which is structurally incapable of accepting a charge,
because Stripe requires an active `card_payments` capability for direct charges and `card_payments`
cannot be requested without also requesting `transfers`. Choosing anything but A1 therefore means
re-onboarding every account, not changing a parameter.

**Four independent constraints converge on keeping it that way.**

1. **The ratified promoter ruling forbids one alternative outright and constrains the other.**
   `POST_FREEZE_AMENDMENTS.md:2469` fixes the ordering: a commission is *"an economic deduction from
   the venue's primary-sale proceeds before the corresponding distributable venue money leaves the
   settlement system."* **Direct charges** pay the venue at the till, which removes the object that
   sentence operates on — an outright conflict that cannot be closed by adding facts to the database.
   **Destination charges** conflict for a different and narrower reason: the commission basis is
   computed at settlement close from the atoms that actually survived, summing
   `unit_price_minor * surviving_count` over non-voided atoms and returning `basis_zero` for a
   refunded order (`090:1461-1473`). No charge-time parameter — `transfer_data[amount]` or
   `application_fee_amount` — can know that number, because it does not exist yet when the charge is
   created. Separate charges and transfers is the only model of the three that preserves the ratified
   ordering literally and needs no amendment. This distinction matters and is stated rather than
   collapsed: the case against destination charges is weaker than the case against direct charges.
2. **Refund liquidity.** `PHASE_2_MONEY_AUTHORITY_SPEC.md:1486-1493` §9.4 states what is deliberately
   not built: *"No reserve. No clawback. No instant payout."* Its justification at `:1489` is that
   refunds are funded from the Stripe balance. That premise only holds if the balance is the
   platform's. Direct charges would require building the reserve that §9.4 says does not exist.
3. **Ledger cost.** Platform-as-merchant needs **zero new enum members and zero new tables**. Venue
   direct charges invert the accounting and need an organization-debtor obligation table that cannot
   be built by widening `kernel.identity_obligation`, whose `debtor_identity_id` is `NOT NULL
   REFERENCES auth.users` (`085:167`) and therefore cannot store an organization at all. That is a
   different architecture, not a migration.
4. **Dispute exposure does not actually move.** Express maps to `controller.losses.payments =
   application`, so Snatch It is *already* liable for connected-account negative balances. Stripe's
   own note on separate charges and transfers is that it is recommended *"only when you're responsible
   for negative balances of your connected accounts"* — which is the position Snatch It already
   occupies.

**RULING.** Snatch It is the merchant and business of record for venue-direct primary sales. The
charge model is separate charges and transfers, unchanged from what ships today. The organization is
paid by Transfer at settlement.

**CLASSIFICATION: OWNER POLICY DECISION**, ratifying what is **WITHIN FROZEN ARCHITECTURE**. No code
change is required to adopt this ruling; it makes explicit what the shipped bytes already do.

> **APPROVAL TEXT — A1**
>
> Snatch It is the merchant of record and the business of record for venue-direct primary ticket
> sales. Payment is taken on the Snatch It platform Stripe account. The charge model is separate
> charges and transfers. No venue-direct PaymentIntent may set `transfer_data`, `on_behalf_of`,
> `application_fee_amount`, or be created against a connected account via the `Stripe-Account`
> header. A connected organization is paid by a Stripe Transfer at settlement, funded from the
> platform balance. No connected account may request the `card_payments` capability.

---

## A2 — Supersession of the contrary line in the corpus

**This ruling exists so that adopting A1 does not quietly overwrite the written record.**

**Finding. There are two contrary sentences, not one, and the stronger of the two is the one that is
easy to miss.** A search for `merchant` across all of `docs/architecture/` returns exactly two hits.
`business of record` returns zero. Both hits contradict A1 and both must be ruled on, or signing A1
leaves a live contradiction in the corpus.

**Hit 1 — `SNATCH_IT_DOMAIN_ARCHITECTURE.md:851`**, the weaker one: *"The buyer owns it as data (it is
about their purchase), but the venue holds refund authority because the venue is the merchant of
record for primary sales."*

**Hit 2 — `SNATCH_IT_DOMAIN_ARCHITECTURE.md:142`**, the stronger one: *"The org, not the user, is the
financial and contractual counterparty for primary sales. A person is never a primary-sale merchant
of record; an org is."*

Both quotes are verbatim. They are not equally weighty and this document will not pretend otherwise.

**Hit 1 is genuinely weak, and wrong on its own terms.** It is a descriptive aside inside a "Hard
cases, resolved explicitly" bullet whose actual subject is who owns the *order object*, not how funds
flow. It says "venue" where `:2219` says *"Money is paid to an org, never to a 'venue'"*. Its
operative claim — that the venue holds refund authority — is contradicted by the deployed money
authority spec, which states verbatim that *"`org_admin` and every venue role are forbidden callers"*
(`PHASE_2_MONEY_AUTHORITY_SPEC.md:673`), and by the §7.6 refund matrix, which leaves every venue-plane
column blank on every refund row (`DOMAIN:1889-1892`) and declares at `:1958` that where the two
disagree on a money cell, the matrix wins.

**Hit 2 is not weak.** It sits in the "Why it is a distinct object" column of the `organization` row
in the §1.1 object catalogue — a definitional entity table, not an aside. Its function in context is
to justify modelling organizations as first-class objects instead of a `user_type` flag, and its
binding content is the person-versus-organization distinction, which ruling **A3 adopts in full**.
The same table row calls the organization *"The **payee** for primary sales"* — payee, not merchant.
But the sentence as written says an org *is* the primary-sale merchant of record, and under A1 the
platform is. That is a real conflict and it will not be resolved by reading the row's intent
charitably.

**What actually carries no normative weight is the term itself.**
`PHASE_2_SUBJECT_MATTER_OWNER_MAP.md` registers 41 subjects and merchant-of-record is not among them,
and that map states that ownership is taken from the corpus's own declarations and never inferred.
Merchant-of-record appears in no matrix, no invariant, no ratification row, no RPC contract and no
RLS predicate. It has never been ruled. That is why this document rules it now rather than claiming
it was already settled.

**RULING.** Both sentences are superseded by A1 and corrected in place. `:142` retains its binding
content — the counterparty and payee is an organization and never a person — and loses only its
merchant-of-record phrasing.

**CLASSIFICATION: POST-FREEZE AMENDMENT**, narrow and owner-signed. It amends prose, not schema.

> **APPROVAL TEXT — A2**
>
> Two sentences in `SNATCH_IT_DOMAIN_ARCHITECTURE.md` are superseded by ruling A1 and are to be
> corrected in place, each carrying a reference to this document.
>
> At `:851`, the clause "because the venue is the merchant of record for primary sales" is struck and
> replaced with a statement that the platform is the merchant of record and that refund authority sits
> with the buyer, organization owner, organization finance role and the platform, per
> `PHASE_2_MONEY_AUTHORITY_SPEC.md:673`.
>
> At `:142`, the clause "A person is never a primary-sale merchant of record; an org is" is struck and
> replaced with "A person is never the counterparty or payee for a primary sale; an organization is.
> The merchant of record is the platform." The remainder of that sentence — that the organization and
> not the user is the financial and contractual counterparty for primary sales — is unchanged and
> remains in force, and is adopted by ruling A3.
>
> No other sentence in the architecture is amended by this ruling. Merchant-of-record is added to the
> subject-matter owner map as a registered subject owned by this document, so that it is never again
> inferred from prose.

---

## A3 — The payee is the organization

**Finding.** The schema has already decided this and cannot express the alternatives. `kernel.payout`
carries `payee_org_id` and **no `payee_venue_id`** (`085:114-146`) — a venue-bound account has no
column to live in. `kernel.organization.legal_name` is the legal entity (`077:107`); `catalog.venue`
holds name, address and capacity, and cannot carry a tax ID, a representative or beneficial owners.
`UNIQUE(stripe_connect_account_ref) WHERE NOT NULL` (`077:124-126`) already asserts one payee per
organization. And `catalog.update_venue` can re-parent a venue's `org_id` (`078:697`), so a
venue-bound account would be orphaned or dragged into the wrong legal entity by an unrelated tenancy
move.

Stripe's constraint agrees: an account maps to exactly one tax ID and legal entity, while one legal
entity may back several accounts. A multi-venue operator under one legal entity is therefore one
account, and per-venue reporting granularity already exists in `venue.settlement` and
`venue.settlement_line`. A "venue group" that is genuinely several LLCs is modelled as several
organizations, which the schema already supports. The usual argument for per-venue accounts —
separate statement descriptors — does not apply under A1, because the buyer's statement shows Snatch
It's descriptor regardless.

**But "the organization" is ambiguous today, and the ambiguity is not cosmetic.** `catalog.event.org_id`
(`078:137`) is an independent column from `catalog.venue.org_id` (`078:100`), and the architecture
explicitly contemplates them differing: `DOMAIN:2220` describes a venue that *"may host events booked
by other orgs"*, and `:2225-2226` has a renting promoter collective settling to its own Connect
account. So the organization that **sells** an event is not necessarily the organization that
**operates** the room.

Ruling A1 makes this a payee question rather than a merchant question, which narrows it but does not
dissolve it: the platform is merchant of record either way, but somebody has to be transferred to,
and the schema currently cannot open a settlement at all when the two organizations differ. That
blocker is stated and ruled in A7, because it lives in `open_settlement` rather than in the payee
model.

**RULING.** The Stripe payee is the organization that sells the event — the one on
`catalog.event.org_id`. Never a venue. Never a person. Never, by default, the room operator when the
two differ.

**CLASSIFICATION: WITHIN FROZEN ARCHITECTURE** for organization-as-payee; **OWNER POLICY DECISION**
for naming the selling organization as the payee where a booked event's organization differs from its
venue's.

> **APPROVAL TEXT — A3**
>
> The Stripe connected account for primary ticketing belongs to the organization, which is the legal
> entity. One connected account per organization. A venue is never a Stripe payee and never holds an
> account reference. An individual person's Stripe account is never a venue or organization payout
> destination under any circumstance. An operator whose venues sit in separate legal entities models
> them as separate organizations.
>
> Where an event's organization differs from its venue's organization — a promoter or touring
> production renting a room — the payee is the organization that sells the event, which is the
> organization recorded on the event. The room operator is not a party to the ticket sale and is not
> paid by this system; any rent or door split between the two organizations is settled outside Snatch
> It and is not modelled. Until the settlement blocker identified in ruling A7 is closed, an event
> whose organization differs from its venue's organization may not be sold on the direct rail at all.

---

## A4 — How an organization becomes connected

**Finding, and it is the single most consequential defect this pass found.** Both binders accept the
Stripe account id **as a caller-supplied string, validated by regex only** — `p_connect_account_id
!~ '^acct_[A-Za-z0-9]+$'` at `077:971-973` and the same shape at `085:1633-1635`. Nothing verifies
that the account exists, that it belongs to the organization, or that it has the `transfers`
capability. Both functions are granted to `authenticated` (`077:2121`, `085:2115`) and the `kernel`
schema is exposed through PostgREST, so both are directly client-reachable.

**The exploit is not theoretical and needs no unusual access.** A staff member who has onboarded as
an ordinary individual Snatch It seller already holds a valid `acct_` id of their own
(`create-connect-account/index.ts:212`). The uniqueness index at `077:124-126` is scoped to the
organization plane and cannot see `public.profiles.stripe_connect_id`, so binding a personal seller
account as an organization's payee is **undetectable by any constraint in the database**. Initial
attach admits `org_finance` as well as `org_owner` (`077:967`), and any `org_admin` can invite an
`org_finance` (`077:1040-1042`).

**This is precisely the outcome the owner's own constraint forbids: venue money attached to an
individual employee's Stripe account.**

**The fix already exists in the repository, on the other plane.**
`create-connect-account/index.ts:198-224` mints the account server-side and writes back `created.id`
from Stripe's own response. It never accepts a caller-supplied id, because there is no parameter to
poison. Applying that same shape to the organization plane closes the attack outright rather than
mitigating it.

**Why the seller function cannot simply be reused.** It hardcodes `business_type: 'individual'`
(`:204`), derives its subject solely from `auth.uid()` with no role check (`:119`), writes
`profiles.stripe_connect_id` (`:215`), and runs as service_role — which is incompatible with
`set_org_connect_ref`, whose contract *requires* a caller JWT in order to stamp the SoD-1 operand
(`077:962-966`). The shared parts that should be reused are `_shared/stripe.ts`, the
`transfers === 'active'` probe (`_shared/payouts.ts:96`), the fail-closed rate limiter and the
stale-account self-heal.

**Two implementation facts that constrain the fix.** First, `CREATE OR REPLACE FUNCTION` cannot drop a
parameter, so the caller-supplied argument cannot simply be deleted from the signature without a
`DROP FUNCTION` and its dependency fallout. What eliminates the attack is therefore a **refusal in
the body**, not a signature change. Second, the binder cannot become service_role-only, because its
contract requires a caller JWT in order to stamp the SoD-1 operand (`077:962-966`).

**Both binders take the poisoned parameter, not just one.** `kernel.set_org_payout_destination`
(`085:1601`) validates by regex alone (`085:1633-1635`) and is granted to `authenticated`
(`085:2137`). Fixing only the first bind would leave an `org_owner` with an aal2 session able to
re-point settlement money to a personal seller account — invisible to `077:124-126`, which cannot see
`public.profiles.stripe_connect_id`. The ruling covers both verbs.

**RULING.** An organization becomes connected only through a new `connect-onboarding` edge function
that mints the account server-side. Both binders refuse any account identifier the platform did not
mint for that organization.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP** for the edge function and for both binder body changes;
the account shape is **OPERATIONAL CONFIG**.

> **APPROVAL TEXT — A4**
>
> An organization's Stripe connected account is created server-side by a new `connect-onboarding`
> edge function and never by a client. The account is created as Express, US, `business_type` =
> `company`, requesting the `transfers` capability only, carrying `metadata[org_id]`, under an
> idempotency key derived from the organization id. Onboarding uses a Stripe-hosted Account Link
> requesting `eventually_due` fields.
>
> Both `kernel.set_org_connect_ref` and `kernel.set_org_payout_destination` are replaced so that they
> refuse any Stripe account identifier that the platform did not mint for that organization. At
> minimum each must refuse an identifier that appears anywhere in `public.profiles.stripe_connect_id`,
> which is the cross-plane refusal that closes the personal-seller-account attack; the complete form
> additionally requires the identifier to match an onboarding record the platform itself created for
> that organization. The refusal lives in the function body, because replacing a function cannot
> remove its parameter. No client-supplied Stripe account identifier may ever be bound as an
> organization payout destination by either verb.

---

## A5 — Attach authority is raised to match replacement

**Finding: the weaker gate guards the more consequential act.**

| | first bind — `set_org_connect_ref` (`077:948`) | re-point — `set_org_payout_destination` (`085:1601`) |
|---|---|---|
| role | `org_owner` **or `org_finance`** | `org_owner` only |
| step-up | none | aal2 required, fails closed |
| SoD maturity | none | `money_role_grant_matured` |
| cool-down | none | `payout.destination_cooldown_hours` |
| account-ref validation | regex only | regex only |

The first bind decides where every future dollar of that organization's money goes, and it is the one
with no step-up, no maturity delay, no cool-down and a wider role set.

**Three further defects found in the same area.**

- **The cool-down that does exist is inert.** `payout.destination_cooldown_hours` seeds `null`
  (`078:1553`), so `085:1650` writes `locked_until = NULL`. This key **fails open**, unlike the
  maturity key (`078:454-486`) and the probation and threshold keys, which fail closed. One of
  replacement's four extra controls is currently switched off.
- **Probation can be aged out before it begins.** Any user can create an organization, become its
  sole `org_owner` (`077:807-812`), and bind a payee while the organization is still `applied`
  (`077:980-982`). The probation operand is `max(occurred_at)` over the two destination audit actions
  `org.payout_destination.change` and `org.connect_ref.bind` (`087:472-476`) — organization approval
  is **not** among them. So binding early and being approved later means the first payout escapes
  probation entirely, and fixing it requires an approval audit action that does not currently exist
  in that list.
- **The alarm exists and is wired to nothing.** `security_payout_destination_changed` and
  `security_payout_method_added` are seeded with templates in the deployed catalogue (`092:269-270`,
  `:336-339`) and have **zero producers**. Neither binder emits. `change_org_role` does this
  correctly at `077:1263-1279` — but note that the established pattern is deliberately best-effort:
  it wraps the emit in `exception when others … raise warning` (`077:1276-1279`) so a failed notice
  never rolls back the underlying change. A ruling that says "must emit" without saying whether a
  failed emit blocks the bind is ambiguous, so this one says.
- **A5 as first drafted would have deadlocked a single-owner organization.** `request_org_payout`
  admits only `org_owner` and `org_finance` (`087:417-418`) and refuses the person who set the
  destination (`087:428-430`), while `create_organization` mints exactly one `org_owner`
  (`077:807-812`). Restricting binding to `org_owner` alone therefore means the sole owner both sets
  the destination and is permanently barred from requesting a payout: money in, no exit. The ruling
  below closes this rather than shipping it.

**On dual control, and why this is a weaker impossibility than Decision B's.**
`kernel.approval_request` closes `action` and `subject_kind` at the schema level (`077:269-276`,
`:299-302`) and CHECK (7) forces `amount_minor` non-null (`077:308`) — a destination change has no
amount. But unlike Decision B, the second approver **does structurally exist**, because
`kernel.org_member` admits multiple owners. Only the frozen CHECK blocks it, and PFA-4's scope clause
permits a later package to widen it. For launch the substitutes are real: SoD-1 forces a second
person at the moment money moves (`087:428-431`), probation forces a platform human to look
(`087:465-495`), and the unwired notification gives the other owners the signal.

**RULING.** Attach is raised to the authority level of replacement, the cool-down key is seeded to a
non-null value, probation is measured from approval rather than from bind, and both binders emit the
security notification that already exists.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP**, except the cool-down value, which is **OPERATIONAL
CONFIG**, and the deferral of in-database dual control, which is a named **IMPLEMENTATION FOLLOW-UP**
for a later package.

> **APPROVAL TEXT — A5**
>
> Binding an organization's first payout destination requires `org_owner` authority and an aal2
> step-up session, and may not occur before the organization's status is `approved` or `active`. A
> matured money-role grant is **not** required for the first bind, because it would impose a waiting
> period before onboarding can even begin, at a moment when no money is yet at risk; maturity remains
> required for re-pointing, where money is at risk.
>
> Because the person who sets the destination is permanently barred from requesting a payout, an
> organization must seat a second money principal — an `org_finance` member distinct from the owner
> who bound the destination — before its first payout request. An organization with exactly one money
> principal cannot be paid, and the product must say so at binding time rather than at payout time.
>
> The payout-destination cool-down key `payout.destination_cooldown_hours` must be seeded to a
> non-null value before the direct rail is activated; it currently fails open, unlike every
> comparable money key.
>
> Payout probation is measured from the later of organization approval and destination binding, so
> that binding early cannot age out probation. This requires recording organization approval as an
> audit action in the probation operand, which it is not today.
>
> Both the first bind and any subsequent re-point must emit `security_payout_destination_changed` to
> every organization owner. Consistent with the established pattern, a failed emit warns and does not
> roll back the bind; the bind is the security-critical act and must not be blocked by a notification
> outage. Failure to emit must be visible in logs.
>
> In-database dual control on destination changes is deferred and named as unbuilt. It is blocked only
> by a frozen constraint and not by the absence of a second approver, which distinguishes it from
> ruling B. SoD-1, probation and the notification are accepted as the launch substitute.

---

## A6 — The readiness gate

**Finding.** A second silent-monitoring gap sits alongside the notification gap. The `account.updated`
webhook handler matches only `profiles.stripe_connect_id` (`stripe-webhook/index.ts:837`) and
acknowledges `matched_profiles: 0` as success (`:850`). An organization account would be created and
then never monitored: no requirement deadline, no disablement signal, nothing.

**Gate on `transfers`, not on `payouts_enabled`.** An organization whose `transfers` capability is
active can be sold through and transferred to; a stranded bank deposit is a warning to the operator,
not a reason to stop selling tickets to fans.

**Gate at `on_sale`, not at publish.** `announced` is marketing state with nothing purchasable
(`081:920`), so gating publication would block promotion that costs nothing and risks nothing. The
gate that actually protects money is `venue.create_primary_checkout` (`082:377`), because it stops
sales the moment Stripe disables an account, with no sweep required and no backward state transition
— the event status machine is forward-only by construction (`081:937-940`) and must stay that way.

**The gate belongs in SQL and must not be conditional.** `venue.create_primary_checkout` is granted
to `authenticated`, so it is reachable by a single PostgREST call; an edge function cannot defend a
door it does not stand in front of. The edge check is belt-and-braces, not the control. And a
configuration key whose only function is to switch the money gate off is not minimality — it is a
second way to be wrong, so no such key is created.

**On mirroring Stripe state.** The owner's constraint is that Stripe's account object must not be
copied into Postgres, and the honest test of that constraint is whether each column has a consumer.
Applying it strictly leaves **two**: the transfers-active flag, which the gate reads, and a
last-synced timestamp, which makes staleness detectable. Payouts-enabled, the disablement reason, the
requirement deadline and an outstanding-requirements flag all failed the test — they have no reader
in the ruled design, and two of them would duplicate columns that already exist on the individual
plane. They are named here as excluded rather than quietly dropped, because a future operator console
is the thing that would justify them, and it does not exist yet.

One property is easy to get wrong and expensive: the transfers flag **must be non-monotonic**, unlike
the existing `stripe_onboarding_complete` (`create-connect-account:281`), which only ever ratchets
forward. A monotonic flag means an account Stripe later disables stays sellable forever.

**RULING.** Selling is gated on an active `transfers` capability, enforced unconditionally in
`venue.create_primary_checkout`, backed by a two-column non-monotonic state mirror kept current by
the webhook.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.** Adding columns to a frozen table is additive and does
not alter any existing constraint or contract, which is what distinguishes it from ruling A8's
settlement-deduction option — that one would add a member to a frozen CHECK, changing the meaning of
a shipped constraint, and is therefore a post-freeze amendment. The distinction is stated because the
two rulings would otherwise look inconsistently classified.

> **APPROVAL TEXT — A6**
>
> A venue-direct primary sale may not be created unless the selling organization holds a bound Stripe
> account whose `transfers` capability is active. The gate is enforced inside
> `venue.create_primary_checkout` itself, unconditionally, with no configuration key able to disable
> it, because that function is directly callable by any authenticated client. The checkout edge
> function re-asserts the same check as defence in depth, never as the control.
>
> Readiness is gated on the `transfers` capability and never on `payouts_enabled`; a blocked bank
> payout is surfaced to the operator as a warning and does not stop ticket sales. An event may reach
> `announced` with no Stripe account; it may not be sold without one. No event is ever moved backward
> out of `on_sale` by this gate.
>
> Postgres mirrors exactly two facts: whether the `transfers` capability is currently active, and when
> that fact was last synchronised from Stripe. No further Stripe account field may be mirrored without
> a named consumer for it. Nothing about identity, banking, ownership, requirements or verification is
> stored. Stripe remains authoritative. The transfers flag must be able to move back to false when
> Stripe disables an account; a monotonic flag would leave a disabled account sellable forever.
>
> The mirror is written by a new service_role-only synchronisation verb invoked from the webhook,
> because the edge role holds `USAGE` only on the `kernel` schema and cannot otherwise write the
> column. That verb ships in the same migration as the columns, or the gate refuses every sale
> permanently.

---

## A7 — The obligation must be a ledger fact before the rail is activated

**Finding, restated because it is the whole reason Decision A existed.** There is exactly **one**
`INSERT INTO venue.settlement_line` in the repository (`087:318`), fed by two seams that can only emit
`market_sale` / `chargeback` (`088:337,352`) and `promoter_commission` (`090:1549`). **No
`primary_sale` writer exists**, even though `primary_sale` is already a member of the closed 13-member
cause set (`087:95-98`). Gross is therefore structurally zero, and `close_settlement` mints a payout
only `if v_net > 0` (`087:340`).

A paid venue order writes exactly three things: `order.status='paid'` (`085:2056`), a
`payment_native` row (`085:2060`), and atoms. **No obligation row exists anywhere.** The question
"how much do we owe organization X" is unanswerable from the database. `kernel.identity_obligation`
cannot hold the answer because `debtor_identity_id` is `NOT NULL REFERENCES auth.users` (`085:167`).

Two consequences that follow and should be visible to the owner:

- **The promoter ruling's funding leg is inert until this lands — but A7 alone does not complete it.**
  Option B deducts commission from primary revenue. With no primary revenue line, a commission is a
  debit against nothing: `close_settlement` computes net as `−commission`, mints no organization
  payout, and records a debt no one collects. A7 supplies the revenue the deduction is taken from.
  **It does not release the commission to the promoter.** Commission payouts are minted already
  `held` with reason `unfunded_settlement`, and the only release verb is `kernel.release_payout`
  (`085:807`), which is platform-role-only and called by nothing outside pgTAP. After A7 the
  organization is correctly debited and paid net, and the promoter's payout still sits held forever.
  Saying A7 "makes Option B implementable" would overstate it; A7 makes Option B *fundable*, and the
  release path remains unbuilt and is named as a follow-up below.
- **The chargeback payout-freeze is already dead code for primary orders.** `088:842-844` queries for
  `settlement_line.cause_ref = order_id`, which can never match while no primary line is written.
- **A booked event cannot be settled at all.** `kernel.open_settlement` requires the venue to belong
  to the requesting organization **and**, when the settlement is event-scoped, the event to belong to
  both that venue and that same organization (`087:254-259`; its own comment reads "the scope binds
  to the subject: venue ∈ org; event ∈ venue ∧ org"). When a promoter organization sells an event in
  another organization's room — which `DOMAIN:2220` explicitly contemplates — **neither organization
  can open a settlement**, so the seam can never fire and a paid order produces no obligation,
  permanently. This is a harder failure than the missing writer, because no seam can fix it.

**Three traps for whoever implements it.**

1. **Double-lining.** The existing uniqueness is per-settlement —
   `unique (settlement_id, cause, cause_ref)` at `087:105` — so the same order can be lined in two
   settlements and paid twice, and the append-only trigger (`087:112-115`) means the bad line can
   never be deleted. The promoter package solved exactly this with a global partial unique index at
   `090:214-215`; primary sales need the same.
2. **The conflict clause must be named, not bare.** `close_settlement`'s `ON CONFLICT` at `087:320`
   is written against an inferred constraint and will abort closes once a second index exists. But
   replacing it with a *bare* `DO NOTHING` swallows conflicts on **any** index, which would silently
   drop an already-lined order out of gross — turning a loud failure into quiet underpayment of the
   venue, in a ledger that cannot be corrected afterwards. It must name the constraint it tolerates.
3. **Which settlement claims an order is currently a race.** `venue.settlement.period_start` and
   `period_end` are nullable (`087:49-50`) with no overlap or uniqueness constraint, so two open
   settlements can both have a claim on the same paid order. The global unique index makes the second
   one fail rather than double-pay, which is the right failure, but the ruling must say which
   settlement is entitled to it rather than leaving it to whichever closes first.

**RULING.** No venue-direct sale may be taken until a paid direct order produces a `primary_sale`
revenue line, protected against cross-settlement double-lining, with an explicit refund
representation.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP** of a contract the frozen architecture already defines.

> **APPROVAL TEXT — A7**
>
> Venue-direct primary ticketing may not be activated until a paid direct order produces a positive
> `primary_sale` line in `venue.settlement_line`, so that the platform's obligation to the
> organization is a ledger fact rather than a reconstruction from Stripe history.
>
> The line is minted by a new settlement seam at settlement close, joining the two seams that already
> exist. It is accepted and recorded that between payment and settlement close the obligation is not
> yet a ledger row and is answerable only from the paid order itself. That window is acceptable only
> with a standing control that reports paid direct orders carrying no revenue line, because nothing
> opens a settlement automatically — it is a manual finance action, and without that report the
> failure mode is silence with real money in it.
>
> A global partial unique index must prevent the same order being lined in more than one settlement,
> matching the protection already applied to promoter commissions. The conflict clause in
> `close_settlement` is corrected in the same change to name the constraint it tolerates; a bare
> conflict clause is forbidden, because it would silently drop an already-lined order out of gross and
> underpay the organization in a ledger that has no delete. Where two open settlements could both
> claim a paid order, the entitled settlement is the one whose scope is narrower — an event-scoped
> settlement takes precedence over a period-scoped one — and the ambiguity is resolved before the
> seam is written, not by whichever settlement closes first.
>
> A refund is represented as its own negative line and never by amending the original revenue line,
> which the append-only trigger forbids and the new unique index would make unamendable in any case.
>
> This ruling is the **funding** leg of the ratified promoter commission ruling (Option B), which
> remains in force and is not modified, reopened or discarded by anything in this document. It is
> recorded explicitly that A7 does not release a promoter commission payout: those are minted `held`
> with reason `unfunded_settlement`, the only release verb is platform-role-only and has no caller,
> and building that release path is a named follow-up that must be closed before any promoter is told
> they will be paid.
>
> An event whose organization differs from its venue's organization cannot have a settlement opened
> under the current contract and therefore may not be sold on the direct rail until that is closed.
> Closing it is a separate change to `kernel.open_settlement` and is not authorised by this ruling.

---

## A8 — The platform's economics on direct sales

**This is the one ruling in Part 1 that is a genuine business choice rather than a forced move, and
it is the only one that can change what a buyer pays.**

**Finding.** No revenue-share key exists. The seeded configuration set contains no `revenue.*`,
`fee.*` or `commission.*` family, and `catalog.set_platform_config` raises
`precondition_failed: unknown_key` (`078:1103`) for any key not already present — so the key can only
be created by a migration, and its *value* can then be set by the owner without one.

**Today the direct rail has no fee of any kind.** `venue."order".total_minor` is the sum of
`unit_price_minor * quantity` (migration 082), there is no buyer-fee column and no tax column
(`082:83`, and the absence of any fee or tax column on `venue."order"` was verified across the whole
table definition, not inferred from that one line), and the order total is therefore all-in by
construction. The marketplace rail is different: `BUYER_FEE_RATE` and `SELLER_FEE_RATE` are both 0.10
(`_shared/money.ts:28-29`), combining to a platform cut of roughly 18.2% of the seller's price, taken
by arithmetic (`_shared/money.ts:60-62`) and never by a Stripe application fee.

**The schema makes the two mechanisms cost very different amounts.**

| Mechanism | Who pays | Schema cost | Changes what the buyer pays? |
|---|---|---|---|
| Buyer-funded fee on the direct rail | buyer | fee columns on `venue."order"`; **no enum change** | **Yes** |
| Deduction from the organization's settlement | organization | **a new member on a frozen CHECK** on an append-only ledger (`087:95-98` has no platform-fee cause) — a post-freeze amendment | No |
| No platform share at launch | nobody | key created, left null; seam writes gross only | No |

The stated business direction is buyer-funded transaction economics, and the shipped schema is
cheapest in exactly that direction. But adopting it raises what a fan pays for a direct ticket above
the face price they see today, and that is a pricing change which must be made deliberately and
displayed honestly, never absorbed silently into a total.

**No percentage is proposed here.** The owner sets the number.

**RULING.** The key is created by the migration with no value. The mechanism and the number are owner
decisions, recorded here as a fork rather than a recommendation dressed as a finding.

**CLASSIFICATION: OWNER POLICY DECISION**, executed as **OPERATIONAL CONFIG**, with the key's
creation as **IMPLEMENTATION FOLLOW-UP**. Choosing the settlement-deduction mechanism would
additionally require a **POST-FREEZE AMENDMENT**.

> **APPROVAL TEXT — A8**
>
> A configuration key for the platform's share of venue-direct primary sales is created by the
> migration with no value set. Selling on the direct rail may not be activated while that key is
> unset. The owner sets both the mechanism and the rate. Snatch It does not charge venues to work
> with the platform: no venue subscription, no monthly platform fee, no onboarding fee, and no charge
> that exists independently of a completed transaction. If the platform's share is funded by the
> buyer, the amount the buyer pays must be displayed as a single all-in total at every point of
> decision, and the change from today's face-value pricing is acknowledged as a deliberate pricing
> change. If instead the share is taken as a deduction from the organization's settlement, that
> requires a new cause on a frozen ledger constraint and is to be brought back as a separate
> post-freeze amendment before implementation. Until the owner sets a value, the platform's share on
> direct sales is zero.

---

## A9 — Preconditions on taking the first direct dollar

**Three findings that outrank the charge-model question because they are model-independent.**

1. **A full refund today takes the ticket and returns no money.** On a delegated or full refund,
   `kernel.refund_primary_order` voids the buyer's atoms (`085:593`) and moves the order to
   `refunded` (`085:604`) in the same transaction, while the `kernel.refund` row is born `pending`
   with no reachable transition out. `kernel.mark_refund_state` (`085:1737`) is the executor's
   callback and has **zero callers repo-wide**. The one `POST /v1/refunds` in the repository
   (`enforce-transfer-expiry/index.ts:264,387`) belongs to the legacy resale expiry sweep and is not
   a primary path. **The buyer loses the ticket and gets nothing.** This is not a charge-model
   question and no charge model fixes it.
   *Scope, stated precisely rather than dramatised:* a direct **partial** refund voids nothing at all
   by design — "Direct-partial: money only (voids nothing)" (`085:562-564`) — and writes
   `partially_refunded` rather than `refunded`. So the partial case loses no ticket, but still
   returns no money, and it additionally leaves the commission basis unreduced, which means full
   commission is paid on partly refunded revenue.
2. **`source_transaction` does not generalize.** One settlement payout has many funding charges, but
   Stripe accepts a single source transaction per transfer and it cannot be changed after creation.
   The payout row records one reference. This must be resolved on paper before a payout executor is
   written, not discovered inside it.
3. **A lost dispute has no exit.** `kernel.resolve_dispute_native` (`088:913-931`) always raises, so a
   lost dispute freezes the organization's payout and the buyer's atoms permanently.

**One thing the corpus has already decided that D3 must not reopen.** `085:2144-2146` names the
intended caller of `kernel.refund_primary_order` as *"the refund-execute edge (as service_role,
forwarding the platform JWT for the direct arm)"* under PFA-23, and the grant arrays are already
shaped for it. So the executor's shape and grant are fixed by the record; what remains genuinely open
is whether it is built now or replaced by a named manual process for a limited launch.

**RULING.** Refund executability is a hard precondition of selling, not a follow-up.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP**, blocking.

> **APPROVAL TEXT — A9**
>
> Venue-direct selling may not be activated until a refund recorded by the database results in money
> actually returning to the buyer, by an automated executor or by a named written process with a
> named accountable human and a defined write-back step. A refund path that voids a buyer's ticket
> without returning their money is not acceptable at any volume, including a single sale. Before a
> payout executor is authored, the mapping between one settlement payout and its many funding charges
> must be settled in writing, because Stripe binds one source transaction per transfer and it cannot
> be amended afterwards. The permanent-freeze behaviour on a lost dispute is recorded as a known
> defect with no exit path and must be closed before the direct rail carries material volume.

---

# Part 2 — the remaining rulings

## B — Signing keys and dual control

**Re-evaluated against Decisions 1 and 2: unchanged.** Nothing about merchant of record or Stripe
onboarding touches credential signing. The findings stand: a display-only launch does not avoid the
problem, because `signing_key_id` is NOT NULL, the foreign key restricts deletion, and the mint
requires an active in-window key — you cannot skip the key by skipping the QR code. In-database dual
control remains unbuildable *and* the second approver does not exist, because the platform role table
is unmintable and the admin allowlist is a single row.

**One cross-reference worth recording.** A5 also fails to get in-database dual control, but for a
weaker reason: there the second approver *does* exist and only a frozen CHECK blocks it. The two
should not be conflated in any future package that tries to solve "dual control" once.

**CLASSIFICATION: POST-FREEZE AMENDMENT** (owner-signed, narrow), plus **OPERATIONAL CONFIG** for the
KMS ceremony and runbook, plus a deferred **IMPLEMENTATION FOLLOW-UP**.

> **APPROVAL TEXT — B**
>
> Signing keys are created two-person in KMS under IAM controls, using the algorithm the frozen
> architecture already specifies. One bootstrap key row is inserted by the migration and is signed by
> the owner. The database signing-key RPCs remain parked and are not un-parked; un-parking would
> expose a function granted to every signed-in user. Real dual control on key operations is deferred
> and must be closed before scanning is activated. The owner accepts that a wrong key at launch is
> silent, deferred and permanent, since the key is pinned at mint, rotation never re-pins, revoke is
> parked, and the foreign key blocks deletion.

---

## C — Venue operatorship transfer freeze

**Re-verified: still valid, and now with two additions.**

The freeze mechanically closes the retained-capability exploit, provably, from a writer census: the
operating org lives at `catalog.venue.org_id` (`078:100`) and is mutated in exactly one place
(`078:701`), inside a `platform_admin`-only, reason-coded, audited arm (`078:688-704`), with no client
caller anywhere. The ruling to freeze is recorded at `_decisions/C_operatorship_transfer.md:413-416`
and the mechanism it prescribes is a body-only replacement in migration 093 (`:428-440`). **That
migration does not exist, so the freeze is currently unenforced in code.**

**Addition 1, from the money side: money correctly does not follow a venue.** `venue.settlement.org_id`
is a snapshot (`087:46`), validated against the venue's org only at open time (`087:254`), and
`kernel.payout.payee_org_id` is written from the settlement's frozen org and never re-resolved
(`087:341-343`). Orders and tickets carry a sale-time `org_id` that no writer ever updates
(`082:78`, `079:35`). So a transfer cannot redirect historical money.

**Addition 2, and it is new: the freeze should also refuse a transfer while money is in flight.** A
departing organization with a `pending` or `submitted` payout is a live financial relationship, and
the freeze as prescribed does not mention it.

**One residual hole to record rather than fix here.** The settlement RLS policies
(`087:83-84`, `087:123-125`) carry no current-operator conjunct, so a stale venue-role holder can
still read settlement headers and lines after a transfer. That is a read leak, not a money path.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.** Lifting the freeze later requires a real atomic
transfer and would be a **POST-FREEZE AMENDMENT**.

> **APPROVAL TEXT — C**
>
> Venue operatorship transfers are frozen for launch. The transfer verb is replaced body-only so that
> a request carrying an organization change is refused; the grant is not revoked, because that would
> also kill benign venue profile edits. The freeze additionally refuses a transfer while the
> departing organization holds a payout in `pending` or `submitted` state. A written no-direct-SQL
> policy and an admin roster review accompany the code change. CI carries a test asserting the
> refusal and a standing invariant that no event's organization differs from its venue's, which is
> the only control that catches a superuser transfer. Lifting the freeze requires shipping a real
> atomic transfer and is a post-freeze amendment.

---

## D — The refund window on account deletion

**Re-evaluated against Decisions 1 and 2: unchanged, and A1 strengthens it.** Because the platform is
merchant of record and holds the funds, a refund after deletion binds to the payment, not to the
customer, and the Stripe payment reference survives erasure. Event cancellation never reads deletion
state. Under direct charges this would have been materially harder.

The status quo is untenable rather than merely imperfect: with the key unset, one paid direct order
makes that buyer **permanently undeletable**, because the order table is immutable and a normally
consumed order stays `paid` forever. That is harmless while dark and an erasure-law failure the
moment direct selling starts.

**CLASSIFICATION: OWNER POLICY DECISION** executed as **OPERATIONAL CONFIG**. No migration required.

> **APPROVAL TEXT — D**
>
> The post-deletion refund waiting period is set to zero. A waiting period is the wrong instrument: the
> ratified machine already accepts chargebacks landing against a tombstone with no window, and a
> refund is strictly easier than a chargeback. Zero disables the arm cleanly and requires no
> migration. It is recorded that a gifted ticket refunds the original payer and not the current
> holder.

---

## D2 — The ticket expiry key

**Re-evaluated: unchanged, and it remains the item that needs no money at all to cause harm.** The
expiry configuration key is unseeded and the sweep returns zero while it is unset, so a no-show
buyer's ticket never expires and the live-custody deletion blocker never clears. The holder has no
disposal path, because native resale is flag-gated off and peer transfer is parked fail-closed, so
the blocker clears only by scan, void or expiry.

**CLASSIFICATION: OPERATIONAL CONFIG**, but the key does not exist, so **its creation is
IMPLEMENTATION FOLLOW-UP in a migration** — `set_platform_config` refuses unknown keys (`078:1103`).

> **APPROVAL TEXT — D2**
>
> The ticket expiry configuration key is created by the migration and set to a value before the direct
> rail is activated. Until it is set, tickets never expire and any buyer holding an unscanned ticket
> is permanently undeletable. This requires no money to trigger and is therefore a precondition of
> issuance, not of selling.

---

## D3 — Refund executor versus named manual process

**Re-evaluated against A9, which promotes it.** This was previously a choice; A9 makes executability a
hard precondition, so the remaining choice is only *how*, not *whether*.

Dashboard-only refunding is **not acceptable alone**, because the database row stays `pending`
forever and that pending row then permanently blocks the buyer's deletion — the failure compounds.
Dashboard plus a named write-back process is acceptable for a limited launch. Building the executor
is cheaper than operating that process, and exactly one automatic refund path already exists on the
legacy rail and should be extended rather than replaced.

**The executor's shape is not actually an open question.** `085:2144-2146` already designates *"the
refund-execute edge (as service_role, forwarding the platform JWT for the direct arm)"* as
`refund_primary_order`'s intended caller under PFA-23, and the grant arrays are shaped for exactly
that. Whoever builds it should follow the record rather than redesign it; the only open decision is
build-now versus named-process-now.

**CLASSIFICATION: OWNER POLICY DECISION** on the mechanism; **IMPLEMENTATION FOLLOW-UP** either way.

> **APPROVAL TEXT — D3**
>
> Refund execution is delivered either as an automated executor extending the existing legacy refund
> path, or as a named written manual process with a named accountable human and a defined database
> write-back step. Dashboard refunding alone is not acceptable, because it leaves refund rows pending
> forever and those rows permanently block the buyer's account deletion. The owner names which of the
> two is adopted for launch, and if the manual process is chosen, names the human who owns it.

---

## E — The payments reshape

**Re-evaluated against Decision 1: confirmed, and A1 makes it unavoidable.** `public.payments`
requires a listing, a seller and a resale mode; `public.payments.listing_id` is `NOT NULL REFERENCES
public.listings` (`000_baseline_schema.sql:973`) and `venue.finalize_primary_order` requires that row
(`085:1919-1934`), so the requirement is bolted in twice inside frozen package 085. A venue-direct
sale has none of the three. The proof that this is a real defect and not a modelling preference is
already in the repository: the money test suite fabricates a fake listing and a fake seller purely to
give finalize a payment row.

**This blocker is common to all three charge models**, so it is not created by ruling A1 and is not
avoided by ruling against it.

Synthesizing a sentinel listing is forbidden twice in the record and would also cap the platform at
one direct sale forever through the one-success-per-listing index. That index does **not** need
rescoping: it carries no clause making nulls equal, so rows with no listing are all distinct to it and
it becomes an automatic no-op for direct sales.

**CLASSIFICATION: OWNER POLICY DECISION**, then **POST-FREEZE AMENDMENT**, then implementation.

> **APPROVAL TEXT — E**
>
> The frozen payments-shape obligation is re-scoped from resale-only to both rails, as a post-freeze
> amendment. It is implemented as constrained relaxation: the two NOT NULL constraints are dropped and
> the mode widened, and in the same transaction both requirements are re-imposed conditionally through
> a rail-pairing check, so that a resale row carrying a null remains unstorable. The net loosening of
> the resale rail is zero. No fake listing row is ever synthesized and no column is added to the frozen
> payments table. The seller-side policy replacement ships in the same migration as the shape change,
> never one without the other; native payments become invisible through the seller-side policy, which
> is correct because there is no seller, and the buyer still sees their own row.

---

## F — Attendee privacy

**Re-verified: unchanged by both upstream decisions.** Merchant of record does not affect what a venue
may read, and organization onboarding does not create a new identity surface. The one real hole is not
a verb: the order table is granted at table grain, so buyer identity is readable by manager and finance
roles, and one join produces an attendee roster with money attached, with no audit row, no rate limit
and no consent gate. It is inert today and live the moment issuance flips.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.**

> **APPROVAL TEXT — F**
>
> A venue receives everything needed to run a door and a box office: ticket status and type, check-in,
> a masked order reference, purchase time, refund state, money for manager and finance roles, and
> promoter attribution. It receives no attendee name and no email by default, because the mechanism
> that makes those tenant-safe is parked with no ratified implementation. After that un-park, name and
> email are available on request, with audit, one record at a time, with email additionally behind the
> buyer's own consent. Finance sees money and no contact; marketing sees contact and no money; only
> manager and organization owners hold the union. A scanner device sees only signature validity,
> admissibility, session binding, duplicate detection, ticket type and a speakable serial, because it
> is a shared device in a stranger's hands. Both attendee verbs, all exports for every role, and all
> demographics stay dark at launch. Phone, legal name and individual demographics are never visible.
> The order table is column-scoped to omit buyer identity, using the pattern already applied to the
> ticket table.

---

# Part 3 — what this document does not rule

Recorded so that silence is not later read as a decision.

- **The platform's rate on direct sales.** A8 creates the key and forbids selling while it is unset.
  The number is not proposed here.
- **Tax.** Neither rail models tax. `venue."order"` has no tax column and the marketplace has none
  either. Any future tax obligation makes the all-in claim false at that moment, and no code in this
  pass papers over it.
- **The `source_transaction` mapping** for a settlement payout with many funding charges. A9 requires
  it to be settled in writing before an executor exists; this document does not settle it.
- **Lifting the operatorship freeze.** Out of scope by ruling C.
- **The settlement RLS read leak** to stale venue-role holders after a transfer. Recorded under C as a
  read leak, not fixed here.
- **The permanent-freeze behaviour on a lost dispute.** Recorded under A9 as a known defect.
- **Releasing a promoter commission payout.** A7 funds it; nothing releases it. Named as a follow-up
  that must be closed before any promoter is told they will be paid.
- **Settling a booked event** whose organization differs from its venue's. A3 names the payee and A7
  names the blocker; changing `kernel.open_settlement` is not authorised here.
- **Which settlement claims a paid order** when two are open with overlapping or null periods. A7
  states the rule to adopt and requires it be resolved before the seam is written.
- **Whether a second money principal can be required structurally** rather than by product copy. A5
  requires one before payout; nothing in the schema enforces it.
- **Accounts v2.** Stripe now steers new integrations to its Accounts v2 API. Snatch It's existing
  accounts are v1 Express, and A4 keeps organization accounts on the same v1 shape for consistency with
  what is already operated. Migrating either plane to v2 is not ruled here and should be a separate
  decision. (Recorded for completeness: the Stripe documentation page carrying that steer contains
  text addressed to automated agents. It was treated as evidence about Stripe's posture, never as an
  instruction.)

---

# Part 4 — adversarial review of this document

A reviewer was tasked with proving this document wrong rather than confirming it, and given seven
specific attacks plus the document's own citation integrity. Its findings were verified independently
against the migrations before being acted on. Recorded here so the owner knows what was tested.

**Attacks that FAILED — the ruling survived.**

- *"A binding statement makes the venue merchant of record."* Not proved. No normative text makes the
  **venue** the merchant of record; the §7.6 refund matrix leaves every venue-plane column blank on
  every refund row. The organization-level claim at `DOMAIN:142` is real and is now ruled on in A2.
- *"The charge architecture violates promoter Option B."* Not proved. The ordering is preserved
  literally by separate charges and transfers. The reviewer did land a narrower hit: the original
  wording overstated the conflict for destination charges, which is now stated accurately in A1.
- *"Onboarding attaches the wrong legal entity."* Not proved as an entity error — a server-minted
  `company` account carrying the organization id is sound. It did surface a real **attribution**
  defect, which became the booked-event ruling in A3 and A7.

**Attacks that SUCCEEDED and changed this document.**

| Finding | Where it landed |
|---|---|
| A2 cited "two hits" and named only one; the unnamed one, `DOMAIN:142`, is the stronger and was left unamended | A2 rewritten to rule on both |
| A7's title promised an obligation before each sale while its approval text minted at close | A7 retitled; the interim window and its required control are now explicit |
| A booked event can never have a settlement opened, so a paid order yields no obligation permanently | New rulings in A3 and A7 |
| A4 replaced only one of the two binders that take a caller-supplied account id | A4 now covers both |
| A5 as drafted deadlocked a single-owner organization: the destination setter is barred from requesting payout | A5 now requires a second money principal and drops the maturity requirement on first bind |
| A7's bare conflict clause would silently underpay rather than fail loudly | A7 now requires a named constraint |
| A7 claimed to make Option B implementable; it only makes it fundable — nothing releases the held commission | A7 corrected; release named as a follow-up |
| Citation `085:580` pointed at the branch that explicitly never voids | Corrected to `085:593`, with the partial-refund case stated |
| Probation operand described as including a role change; it does not | A5 corrected, and the missing approval audit action named |
| Seven further off-by-one citations | Corrected in place |

**Two disagreements recorded rather than resolved silently.** The migration-design reviewer would
defer the operatorship freeze out of the migration on minimality grounds, arguing money never follows
a venue. Ruling C keeps it, because the deferral's safety depends on a person remembering not to
perform a transfer, and the code change is a body-only function replacement. The same reviewer would
mirror two Stripe columns rather than six; that argument was accepted and A6 was tightened.

---

# Signature block

**This document is NOT approved.** No ruling above is in force. Nothing has been implemented.

| Ruling | Subject | Status |
|---|---|---|
| A1 | Merchant and business of record | PENDING OWNER SIGNATURE |
| A2 | Supersession of `DOMAIN:851` | PENDING OWNER SIGNATURE |
| A3 | The payee is the organization | PENDING OWNER SIGNATURE |
| A4 | How an organization becomes connected | PENDING OWNER SIGNATURE |
| A5 | Attach authority raised to match replacement | PENDING OWNER SIGNATURE |
| A6 | The readiness gate | PENDING OWNER SIGNATURE |
| A7 | The obligation row | PENDING OWNER SIGNATURE |
| A8 | Platform economics on direct sales | PENDING OWNER SIGNATURE |
| A9 | Preconditions on the first direct dollar | PENDING OWNER SIGNATURE |
| B | Signing keys and dual control | PENDING OWNER SIGNATURE |
| C | Operatorship transfer freeze | PENDING OWNER SIGNATURE |
| D | Refund window on deletion | PENDING OWNER SIGNATURE |
| D2 | Ticket expiry key | PENDING OWNER SIGNATURE |
| D3 | Refund executor versus manual process | PENDING OWNER SIGNATURE |
| E | The payments reshape | PENDING OWNER SIGNATURE |
| F | Attendee privacy | PENDING OWNER SIGNATURE |

Owner signature: _______________________  Date: _______________

Rulings A8 and D3 additionally require the owner to supply a value, not only a signature: A8 the
mechanism and rate, D3 the mechanism and, if manual, the accountable human.
