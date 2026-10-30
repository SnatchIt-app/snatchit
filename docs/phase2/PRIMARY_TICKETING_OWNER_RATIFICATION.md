# Primary ticketing — owner ratification

**Status: RATIFIED by the owner, 2026-09-02.** This is the canonical owner-ruling artifact for
venue-direct primary ticketing. It supersedes the draft status of
`PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md`, which remains in force as the *evidence and reasoning*
behind these rulings but is no longer the authority on what was decided.

**Scope of this ratification.** It authorises development: migration 093, server-side infrastructure,
tests. **It authorises no production change of any kind.** Production remains PHASE-2 DARK SUBSTRATE
DEPLOYED and forward-only. No rail is activated.

**A note on numbering, because it matters.** The owner's ratification numbers rulings A1–A9
differently from the draft packet. This document uses **the owner's numbering** as canonical. The
mapping to the draft is given below so that no citation is lost.

| Owner ruling | Subject | Draft packet equivalent |
|---|---|---|
| A1 | Merchant / business of record | draft A1 + A2 (supersession) |
| A2 | Stripe charge architecture | draft A1 (charge model half) |
| A3 | Durable venue obligation / settlement | draft A7 + draft A3 (booked-event payee) |
| A4 | Promoter Option B | draft A7 (funding leg) |
| A5 | Venue revenue / platform economics | draft A8 |
| A6 | Stripe Connect ownership | draft A3 |
| A7 | Venue Stripe onboarding | draft A4 |
| A8 | Event / payment gating | draft A6 |
| A9 | Connect account security | draft A5 |
| B, C, D, D2, D3, E, F | unchanged | same letters |

---

# Ratified rulings

Each ruling below is recorded as the owner stated it. Where the owner's text is narrower or stronger
than the draft recommendation, **the owner's text governs** and the difference is noted. Nothing here
is paraphrased into weaker policy.

---

## A1 — Primary sale merchant / business of record

**RATIFIED.** Snatch It is the merchant/business of record for Snatch It venue-direct primary ticket
transactions.

This is a deliberate post-freeze clarification and supersession of any normative Phase-2 statement
that assigns merchant-of-record status to the venue organization.

**Amendment scope is bounded to the proven conflict.** Only the conflicting merchant-of-record
wording identified by the prior review is amended. The separate binding rule is preserved: a person is
never the primary-sale business counterparty; the organization remains the venue-side
economic/legal entity inside the Snatch It domain model.

**Two sentences are amended, both in `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md`:**

- `:851` — the clause "because the venue is the merchant of record for primary sales".
- `:142` — the clause "A person is never a primary-sale merchant of record; an org is." The remainder
  of that sentence, that the organization and not the user is the financial and contractual
  counterparty for primary sales, is **preserved verbatim and remains binding**.

**CLASSIFICATION: POST-FREEZE AMENDMENT.** Recorded as PFA-PT-1.

---

## A2 — Stripe charge architecture

**RATIFIED.** Primary buyer payment is collected through the Snatch It platform Stripe account using
the architecture recommended in the final ruling packet: separate charges and transfers, with no
`transfer_data`, no `on_behalf_of`, no `application_fee_amount`, and no `Stripe-Account` header.

Venue primary sales are **not** converted to direct connected-account charges.

**Payment collection, internal obligation accounting, and payout execution remain separate
concepts. No venue payout is implied by successful collection.**

**CLASSIFICATION: WITHIN FROZEN ARCHITECTURE**, ratified explicitly.

---

## A3 — Durable venue obligation / settlement

**RATIFIED.** Every successful venue-primary economic event must create sufficient durable internal
accounting facts for Snatch It to determine the venue-side economic obligation **without
reconstructing debt from Stripe history**.

The implementation must include the corrected settlement-opening model identified by adversarial
review. Specifically: a promoter organization selling inventory for another organization's venue must
not create an impossible settlement where neither organization can open or own it.

**The settlement/obligation owner must be derived from the actual venue-side economic counterparty
defined by the primary-sale contract, not merely the requesting organization. Any ambiguity must fail
closed.**

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP**, with the `open_settlement` correction as a body-only
replacement.

---

## A4 — Promoter Option B

**RATIFIED and unchanged.** The previously ratified Option B remains binding. Eligible primary
promoter commission is funded from primary-sale economics and reduces venue distributable before
venue money is released.

**Funding a commission is NOT equivalent to paying a commission.** Promoter payout execution remains
dark and separately gated.

**Nothing in 093 may accidentally release promoter money.** This is a hard constraint on the
migration and is asserted by test.

**CLASSIFICATION: WITHIN FROZEN ARCHITECTURE** (E-138 / `COMMISSION_FUNDING_SOURCE` unchanged).

---

## A5 — Venue revenue / platform economics

**RATIFIED.** Snatch It does not charge venue partners a SaaS fee, an onboarding fee, or a venue-side
platform commission for primary ticketing at launch.

**Primary ticket economics are buyer-funded.**

The venue-side entitlement **begins with the configured ticket face value**, subject only to
explicitly modeled adjustments such as: refunds, chargebacks, taxes where economically applicable,
promoter commissions under approved policy, and other explicitly owner-approved adjustments.

Snatch It revenue is funded through a **configurable buyer-side service fee**.

**Hard constraints on the migration:**
- No service-fee percentage is hardcoded in migration 093.
- No percentage is invented anywhere.
- Fee economics remain owner/config controlled.
- **Stripe processing cost treatment must be explicit.** Processing cost is **not** silently
  subtracted from venue face-value entitlement.

**This ruling resolves the draft's three-way economics fork in favour of buyer-funded**, and it also
selects the cheaper schema path: a buyer-funded fee needs no new settlement cause, whereas a
venue-side deduction would require adding a member to a frozen CHECK.

**OPEN ITEM SURFACED, NOT INVENTED — processing-cost allocation.** The owner's instruction was: *"If
the current architecture has no owner ruling for processing-cost allocation, surface that separately
rather than inventing policy."* Searched and confirmed: **no ratified ruling allocates Stripe
processing cost** on the primary rail. Because A5 fixes venue entitlement at face value and forbids
silent subtraction, the cost necessarily lands on the platform's side of the buyer-funded service fee
by elimination — but that is an inference, not a ruling. It is carried to the report as an owner item
and is **not** encoded in 093.

**CLASSIFICATION: OWNER POLICY DECISION**, executed as **OPERATIONAL CONFIG**; the key's creation is
**IMPLEMENTATION FOLLOW-UP**.

---

## A6 — Stripe Connect ownership

**RATIFIED.** The Stripe connected account used for venue settlement belongs to the **venue
organization legal/economic entity**.

It must **not** belong to an employee, an individual venue manager, a promoter user, a scanner, or an
ordinary seller profile.

Model:

```
ORGANIZATION
    ↓
STRIPE CONNECTED ACCOUNT
    ↓
ONE OR MORE VENUES
```

unless a mechanically proven legal/entity constraint requires a narrower structure. **No such
constraint was found**; Stripe permits one legal entity to back several accounts, and the schema has
`kernel.payout.payee_org_id` with no venue equivalent, so the ratified model stands as written.

**CLASSIFICATION: WITHIN FROZEN ARCHITECTURE.**

---

## A7 — Venue Stripe onboarding

**RATIFIED.** A dedicated **server-side** organization Connect onboarding flow is implemented.

Initial account posture: Stripe Connect **Express**, **United States** launch, **`business_type =
company`**, **`transfers` capability** required, **metadata binds the Snatch It organization
identifier**.

The server creates/resolves the connected account. **A caller must never be permitted to supply or
bind an arbitrary `acct_` identifier.**

**Both** known account-binding surfaces must reject caller-selected Stripe account IDs:
`kernel.set_org_connect_ref` (`077:948`) and `kernel.set_org_payout_destination` (`085:1601`).

**Cross-plane reuse of an ordinary seller's existing connected account must be prevented.**

Initial onboarding and account replacement must be auditable.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.**

---

## A8 — Event / payment gating

**RATIFIED.** A venue organization may exist, configure itself, create draft events, create ticket
types, and configure inventory **before** Stripe onboarding completes. It may **not** accept real
primary payments until all required Stripe payment/settlement prerequisites are satisfied.

**Four separate gates, not one boolean:**

| Gate | Meaning | Requires Connect readiness |
|---|---|---|
| **DRAFT** | organization, venue, event, ticket types, inventory exist | No |
| **PUBLISHABLE** | event may become publicly visible (`announced`) | No |
| **SALEABLE** | event may transition to `on_sale` and be purchased | **Yes** |
| **PAYABLE** | settlement may be closed and a payout requested | **Yes**, plus settlement prerequisites |

An event may safely be publicly visible before it becomes saleable, and that possibility is
preserved.

**Checkout must fail closed if the venue organization is not eligible for primary-sale collection.**

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.**

---

## A9 — Connect account security

**RATIFIED.** Organization Stripe account attachment/replacement is a privileged, audited operation.

The system must prevent: personal-account injection; cross-organization account reuse;
caller-supplied `acct_` replacement; stale onboarding callback binding; role-loss race during
onboarding; unauthorized reconnect; and direct client mutation.

**Replacement of an existing organization Stripe account is treated as higher risk than first-time
onboarding. A live payout destination is never silently replaced.**

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.**

---

## B — Credential signing / dual control

**RATIFIED.** The minimum safe two-person external/KMS-backed ceremony from the final ruling packet
is adopted.

Private signing key material is **not** treated as ordinary application database data. The database
stores only the approved public/trust/bootstrap facts the architecture requires. Signing key
provisioning remains separate from Apple Wallet. Old issued tickets remain verifiable after rotation.
A single application administrator must not be able to silently replace the trusted signing identity.

**093 implements only what is required to represent the approved bootstrap/trust state.**

**Explicitly excluded from this train:** no production key is provisioned; unrelated signing
administration RPCs stay parked.

**CLASSIFICATION: POST-FREEZE AMENDMENT** (owner-signed, narrow) — recorded as PFA-PT-2 — plus
**OPERATIONAL CONFIG** for the ceremony.

---

## C — Venue operatorship transfer

**RATIFIED.** Venue operatorship transfers are **frozen for initial launch**.

The reviewed body-only enforcement is implemented so a venue cannot change its operating
organization. Additionally:

- the no-direct-SQL operational policy is preserved;
- a CI invariant asserts that an event's organization cannot diverge from its venue's organization;
- any future transfer attempt is refused while the departing organization holds **PENDING or
  SUBMITTED payout facts**.

No self-service transfer workflow is needed for launch.

**This resolves the dissent recorded in the draft** — the independent migration review would have
deferred the freeze on minimality grounds; the owner has ruled it in.

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.**

---

## D — Deletion / refunds

**RATIFIED.** Deletion waiting window: **ZERO**. No arbitrary waiting period is introduced.

Financial and legal survivability is handled by the durable tombstone and payment-reference
architecture. A buyer may become tombstoned while later financial operations such as refunds and
chargebacks remain possible. Financial records required for those operations are **not** physically
deleted.

**CLASSIFICATION: OWNER POLICY DECISION**, executed as **OPERATIONAL CONFIG**. No migration required.

---

## D2 — Ticket expiry

**RATIFIED.** The missing ticket-expiry configuration contract is created, so direct tickets cannot
remain indefinitely live.

**The derivation is not invented — it is already shipped.** `kernel.sweep_expired_ticket_atoms`
(`079:488-497`) already expires an atom when `now() > catalog.event_session.ends_at + grace`, joined
through `t.event_session_id`. That is deterministic **event-derived expiry plus configurable grace**,
which is exactly the owner's stated preference, and it is ratified at
`PHYSICAL_POSTGRES_SCHEMA_SPEC.md:537-539`.

An explicit TTL is architecturally unavailable: `kernel.tickets` has no `expires_at` column
(`079:32-58`), the mint stamps none (`083:557-560`), and `catalog.event` carries no time facts at all
(`078:134-153`). All time lives on the session, and every column is `timestamptz`, so the arithmetic
is timezone-free.

**What 093 creates:** one `catalog.platform_config` row, key `ticket.expiry_grace`, whose value is a
**jsonb string holding an interval literal**. It must not be a number — a number fails the
`::interval` cast at `079:478` and the `exception when others` arm at `079:483-486` silently re-arms
the original bug.

**THE ONE OWNER STOP IN THIS TRAIN.** No grace numeric is ratified anywhere in the corpus. The key is
seeded with an architecture-derived provisional value and flagged, because leaving it absent is
forbidden by this ruling and because the value is changeable later by `set_platform_config` **without
a migration**. The owner's decision is therefore reversible and cheap, and it is reported separately
rather than presented as settled.

**A second fail-open path that configuration cannot reach**, surfaced not fixed by config:
`catalog.event_session.ends_at` is optional at creation (`078:806` requires only `starts_at`), and the
sweep skips null-`ends_at` sessions by design. A venue omitting `ends_at` reproduces the bug in full.
Carried as a separate schema decision.

**CLASSIFICATION: OPERATIONAL CONFIG**, whose key creation is **IMPLEMENTATION FOLLOW-UP**.

---

## D3 — Refund executor

**RATIFIED: BUILD THE REFUND EXECUTOR NOW.**

A raw service-role SQL or manual database write is **not** an acceptable normal operational refund
process. PFA-23's already-frozen executor shape remains authoritative and is implemented as specified
(`085:2144-2146`: the refund-execute edge, as service_role, forwarding the platform JWT for the
direct arm).

Manual production intervention may exist **only** as documented break-glass incident recovery, never
as the primary refund workflow.

The executor must be server-side, authenticated and authorized appropriately, idempotent,
Stripe-idempotent, replay-safe, auditable, compatible with tombstoned buyers, compatible with event
cancellation, safe if Stripe fails midway, safe if the worker retries, and **incapable of refunding
the wrong payment or order**.

**Not deployed in this train.**

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.**

---

## E — Payments contract amendment

**RATIFIED.** The narrowly scoped post-freeze payment-contract amendment is applied, using
**constrained relaxation plus an explicit rail-pairing constraint**.

Legacy and resale invariants remain exactly enforced for legacy and resale rows. Visibility is not
broadened. The existing seller policy is not destabilized. **No organization policy is added**, because
the previously verified test proves that would violate the frozen visibility model.

**This amendment is explicitly documented as POST-FREEZE.** Recorded as PFA-PT-3.

**CLASSIFICATION: POST-FREEZE AMENDMENT**, then implementation in 093.

---

## F — Attendee privacy

**RATIFIED FOR INITIAL LAUNCH.** Operational attendee access and marketing/CRM access remain
separate.

Default venue operational data may include, according to role: ticket status, ticket type, check-in
state, masked order reference, purchase time, refund state, authorized financial amount, and promoter
attribution where applicable.

**By default: no attendee name, no attendee email, no attendee phone, no individual demographic
field, no bulk attendee export, no CRM activation.**

Sensitive identity lookup, where operationally necessary, must be one record at a time, explicitly
authorized, logged and auditable.

`venue_scanner` receives only what is required for door validation. `venue_finance` does not
automatically receive marketing identity data. `venue_marketing` does not automatically receive
payment-sensitive data.

**The verified table-grain buyer-identity/display-name join that allows an unaudited attendee roster
is fixed.**

**X-6 is preserved: CRM/export must not depend on demographics.**

**CLASSIFICATION: IMPLEMENTATION FOLLOW-UP.**

---

# Post-freeze amendments created by this ratification

| Id | Amendment | Artifact touched |
|---|---|---|
| PFA-PT-1 | Merchant-of-record supersession, bounded to two clauses | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:142`, `:851` |
| PFA-PT-2 | Signing bootstrap trust state, KMS ceremony | migration 093, ops runbook |
| PFA-PT-3 | `public.payments` obligation re-scoped from resale-only to both rails | migration 093 |

---

# What this ratification does NOT authorize

Restated because the authorization above is broad and the boundary is not.

No production application of 093. No production schema change. No production flag flip. No production
schema exposure. No edge deployment. No production Stripe account creation. No production onboarding.
No production ticket mint. No production money movement. No secret rotation. No payout enablement. No
promoter payout enablement. No Wallet, CRM, or native resale enablement. No mobile build publication.

**This train ends at IMPLEMENTATION READY FOR OWNER REVIEW.**

---

**Ratified by the owner 2026-09-02. Recorded, not self-signed.**
