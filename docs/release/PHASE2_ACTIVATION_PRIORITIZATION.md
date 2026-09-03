# Phase-2 feature-activation prioritization

**Written 2026-09-03, immediately after the 24-hour dark-substrate observation closed
PASS** (`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md`, Checkpoint 2).

**This document activates nothing and builds nothing.** It is a read-only dependency
analysis and a single recommendation. Production remains **PHASE-2 DARK SUBSTRATE
DEPLOYED** and **FORWARD-ONLY**; every rail below is dark, and stays dark until an
owner authorizes otherwise.

**Method.** The graph below was derived mechanically from (a) the *deployed* schema —
migrations 076–092, ledger 107, read live — and (b) the repo's frozen corpus, and only
then compared against the existing planning documents. Where a claim is marked **[V]**
it was executed against production during this session, not inherited from a document.
The strategic objective — moving Snatch It from primarily P2P resale toward
venue-native first-party ticketing — was held to one side while the graph was built,
and applied only at the ranking step, so that the graph could contradict it if it
wanted to. It did not; the reason is given in §3 and it is a structural reason, not a
deference to the suggestion.

---

## 1 · What is actually deployed, measured

| Fact | Value | Consequence |
|---|---|---|
| Ledger | **[V]** 107 rows, max numeric version `092`, **0** rows ≥ 093 | Migrations 093–104 exist in the repo and are **not applied** |
| Exposed schemas | **[V]** `public,graphql_public,kernel` | `catalog`, `venue`, `market`, `notify` are unreachable by any client |
| Feature flags | **[V]** all five `false` | No rail is armed |
| Owner-unset keys | **[V]** 3 still `'null'::jsonb` | Push claim, backup window and deletion hold all fail closed |
| Config keys | **[V]** 43 (repo replay carries 49→54) | The config seeds introduced by 093+ do not exist in production |
| Cron | **[V]** 19 jobs (repo replay carries 22) | The refund and payout invoker ticks do not exist in production |
| Edge functions | **[V]** 11 deployed | `connect-onboarding`, `primary-checkout`, `refund-execute`, `payout-execute`, `credential-sign` are **all undeployed** |
| `kernel.organization` connect mirror columns | **[V]** 0 of 3 present | 093 is not applied; `connect_transfers_active` has no column, let alone a writer |
| Native data plane | **[V]** 0 rows across 17 native tables | Nothing native has ever been written |
| `kernel.signing_key` / `kernel.pass_type_cert` | **[V]** 0 / 0 rows | No credential can be minted; no wallet pass can be signed |
| `kernel.organization` / `catalog.venue` / `venue.ticket_type` | **[V]** 0 / 0 / 0 rows | No venue exists to sell anything |
| `kernel.platform_role` | **[V]** 0 rows | See §5 — this matters more than it looks |

## 2 · The dependency graph, derived from the deployed schema

Eight rails, and the graph is not a matter of taste. Every native rail's write path
begins at a **ticket atom** (`kernel.tickets`) or a **primary order**
(`venue.order`), and both of those are written only by the primary-issuance path.

```
                    ┌──────────────────────────────────────┐
                    │  A · Venue core → primary inventory  │
                    │      → primary ticket issuance       │
                    │  (writes kernel.tickets, venue.order,│
                    │   venue.attribution, kernel.payment_ │
                    │   native, venue.settlement)          │
                    └───┬───────┬───────┬───────┬───────┬──┘
                        │       │       │       │       │
              ┌─────────┘       │       │       │       └──────────┐
              ▼                 ▼       ▼       ▼                  ▼
     C · Door / scanning   D · Promoter  E · Native  F · Wallet   G · CRM
     (needs issued          attribution   resale     (needs a      (needs
      credentials +         (rows written  (market.   pass cert +   attendee
      signing keys)         at primary     listing_   an issued     demographics
              │             checkout)      native →   ticket)       from orders)
              │                   │        ticket)        │            │
              └───────────────────┴────────┬──────────────┴────────────┘
                                           ▼
                                  H · Promoter payout
                                  (needs D + settlement
                                   + payout executor;
                                   A4 rules it LAST)

     B · In-app notifications ── independent of A structurally,
                                 but 29 of its 31 registered types
                                 are emitted only by A/C/D/E/F/H.
```

**A is the unique root.** C, D, E, F, G and H are strict descendants: none of them has
a write path that does not pass through an issued native ticket or a primary order.
**B is the only rail that is structurally independent of A — and it is empty without
it**, which §3 quantifies.

## 3 · Rail-by-rail evaluation

Each rail is scored on the deployed substrate, not on the repo tip.

### A · Venue core → primary inventory → primary ticket issuance
- **Business value: HIGHEST.** It is the entire strategic pivot. It is also the only
  rail that creates first-party revenue rather than intermediating someone else's.
- **Dependency depth: DEEPEST — but it is root depth, not blocked depth.** Nothing
  upstream of it is missing; everything it needs is downstream of an owner decision.
- **Missing DB work:** apply **093–101** (093 primary ticketing; 094 organization
  obligation; 095 payout state machine; 096 reversal/recovery; 097 settlement
  ring-fence; 098 promoter pro-rata funding; 099 signing monitor + dark invokers;
  100 held-commission convergence; 101 cross-venue recovery guard), plus **102** for
  the credential signer that ticket issuance depends on. All are authored and replay
  clean locally; **none is applied.** Order matters (094 before 095; 096→097→098→099;
  100/101 after).
- **Missing edge work:** deploy **`connect-onboarding`**, **`stripe-webhook`** (native
  branch), **`refund-execute`**, **`primary-checkout`**, and **`credential-sign`** —
  five functions, all authored, **none deployed [V]**.
- **Missing web work:** a venue/organizer console — org onboarding, event and session
  creation, inventory and ticket-type publish, order and settlement views. This does
  not exist in any deployed form.
- **Missing mobile work:** buyer discovery and checkout for primary inventory, and
  ticket display backed by a signed credential rather than a listing row.
- **Config required:** `inventory.*` (single admin), `ticket.expiry_grace` (quorum),
  `payout.settlement_maturity_interval` (quorum), `fee.buyer_service_bps` (quorum),
  `deletion.post_event_hold_hours` (quorum, and **only after `refund-execute` is
  deployed**), then `feature.native_issuance_enabled = true` last of all.
- **Owner policy required:** G1 (expiry grace), G2 (maturity interval), G3 (KMS
  ceremony: provider, two named operators with separated cloud IAM, a booked window),
  G5 (post-payout recovery policy), the **Gate-M re-attestation** that gates applying
  094, ratification of `kernel.claim_refunds_for_execution`, the tax model and the
  `on_sale`/SALEABLE enforcement-locus choice, and acknowledgement of the
  `deletion.refund_possible_window_hours` → `deletion.post_event_hold_hours` rename.
- **External credentials:** a KMS provider and the signing ceremony; Stripe Connect
  Express for at least one real organization.
- **Stripe impact: LARGE.** New Connect accounts, a new native webhook branch, a new
  charge path, a new refund executor.
- **Money risk: HIGHEST** — it is the only rail that takes money. Mitigated by the
  ratified ordering: `primary-checkout` deploys **last**, after the refund path
  already works, so no dollar can be taken before it can be given back.
- **Security risk: MEDIUM-HIGH** — exposing `catalog` and `venue` over PostgREST is a
  two-person operational act that widens the API surface for the first time since the
  freeze; the KMS ceremony is **irreversible**.
- **Operational risk: HIGH** — nine forward-only migrations, five edge deploys, an
  irreversible ceremony, and a PostgREST cutover, on a FORWARD-ONLY production.
- **Ships independently: YES** (see §6).
- **Complexity: LARGE — but the balance has shifted.** The backend is essentially
  written. What remains is *deploy, ceremony, config, and frontend*, not database
  design.

### B · In-app notifications
- **Business value: LOW standalone, HIGH as a passenger.** **[V] The registry holds 31
  notification types and 61 templates — and exactly 2 have live emitters**
  (`account_deletion_pending`, `account_deletion_completed`). The other 29 are
  purchase, refund, payout, ticket, wallet, promoter and event-change types that only
  fire once A (or a descendant) is live. Activating B alone ships an inbox whose only
  content is account-deletion notices.
- **Dependency depth: SHALLOWEST.** **[V]** The client-facing API is already deployed
  and correctly granted: `notify.get_unread_count`, `mark_read`, `get_inbox`,
  `mark_all_read`, `dismiss`, `get_preference_matrix`, `set_preference`,
  `register_push_token`, `revoke_push_token` are all SECURITY DEFINER and executable
  by `authenticated`.
- **Missing DB work:** a cron row for a push dispatcher tick (the parked
  `notify-dispatch` deliberately does not exist), which under repo discipline means a
  **migration 093+**. Nothing else.
- **Missing edge work:** one dispatcher that claims deliveries, sends via the push
  provider, and calls `notify.record_delivery_result`.
- **Missing web/mobile work:** an inbox and a preference screen.
- **Config required:** `notify.delivery_lease_interval` (currently `'null'` — **[V]**
  the claim path refuses while it is null, which is why **0** deliveries have ever
  been claimed).
- **Owner policy required:** the lease value; the announcements flag stays false.
- **External credentials / Stripe / money risk:** none, none, **none**.
- **Security risk: MEDIUM** — it requires exposing `notify` over PostgREST *or*
  wrapping its verbs behind `kernel`. The wrapper is the narrower act and should be
  preferred; exposing a fourth schema is a freeze-relevant decision.
- **Ships independently: YES, technically. NO, usefully.**
- **Complexity: SMALL.**

### C · Door / scanning
- **Value: HIGH, but only where A already sold the ticket.** Depends on issued
  credentials and on signing keys (**[V]** `kernel.signing_key` = 0 rows), plus
  migrations 103/104, an operator/scanner app that does not exist, scan devices, door
  sessions and staff roles (**[V]** `venue.staff_role` = 0 rows). **Cannot precede A.**
  Money risk low; operational risk high (it fails in a doorway, in front of a queue).
  **Complexity: LARGE** (a new client app).

### D · Promoter attribution
- **Value: MEDIUM-HIGH** (it is the growth loop). **[V]** `venue.attribution` = 0 rows;
  attribution is written *at primary checkout*, so it is not a separate activation so
  much as a facet of A. Capture can ride A; **funding and payout must not**.
  **Cannot precede A. Complexity: SMALL on top of A.**

### E · Native resale
- **Value: MEDIUM.** `market.listing_native` references native ticket atoms, of which
  there are **[V]** zero. It cannot precede A. Critically, **the legacy P2P resale rail
  keeps running unchanged in the meantime** — this is the one rail where deferral costs
  the business nothing today. **Money risk: HIGH** (two live sale paths, one ledger).
  **Complexity: MEDIUM.**

### F · Wallet (Apple)
- **Value: MEDIUM** (conversion and retention, not revenue). Needs an issued ticket, an
  Apple Pass Type ID certificate (**[V]** `kernel.pass_type_cert` = 0 rows), APNs
  credentials, and the signer. **Cannot precede A. Complexity: MEDIUM.**

### G · CRM export
- **Value: MEDIUM** (a venue-facing sell, not a consumer feature). Needs attendee
  demographics that only A produces, the absent `crm_export_worker_secret`, and a
  worker that is not deployed — **[V]** the two ticks are already scheduled and
  correctly no-op. **Highest privacy/consent risk of any rail.** **Cannot usefully
  precede A. Complexity: MEDIUM.**

### H · Promoter payout
- **Value: MEDIUM.** Deepest node in the graph: needs D, settlement maturity, the
  payout executor, G4 and G5 signed. **Ruling A4 already places it last, and the
  substrate enforces it** — **[V]** zero payouts with `cause = 'promoter_commission'`,
  and any future one is born `held`. **Highest money risk. Must be last.
  Complexity: MEDIUM on top of A.**

## 4 · Ranked list

| # | Rail | Value | Depth | Independent? | Verdict |
|---|---|---|---|---|---|
| **1** | **A · Venue core → primary inventory → primary ticket issuance** | Highest | Root | **Yes** | **Recommended first activation** |
| 2 | D · Promoter attribution (**capture only**) | Med-High | Facet of A | No | Rides A; funding/payout stay dark |
| 3 | B · In-app notifications | Low alone / High with A | Shallowest | Technically | **Ride A, do not lead with it** |
| 4 | C · Door / scanning | High | A + signing | No | Second train, before first doors open |
| 5 | F · Wallet | Medium | A + cert | No | Third train |
| 6 | E · Native resale | Medium | A | No | Defer — legacy P2P covers it today |
| 7 | G · CRM | Medium | A + consent | No | Defer — highest privacy risk, lowest urgency |
| 8 | H · Promoter payout | Medium | D + settlement + G4/G5 | No | **Last, by ruling and by substrate** |

**Why A is first, stated as a structural argument rather than a strategic one.** Six of
the eight rails cannot be activated at all until A is, because their write paths begin
at a row only A creates. The seventh (B) can be activated but would deliver an inbox
with two live message types out of thirty-one. That leaves exactly one rail whose
activation is both possible and valuable. **The graph does not offer a choice, and it
would have said so regardless of the strategic framing.** If the graph had supported a
different first rail, this document would name it.

## 5 · A prerequisite the existing critical path does not number

**[V] `kernel.platform_role` has 0 rows.** **[V]** `catalog.set_platform_config`
requires `kernel.is_platform(array['platform_admin'])`, and **[V]**
`kernel.is_platform` satisfies its `platform_admin` arm either from
`kernel.platform_role` *or* from the frozen `public.admin_users` bootstrap — of which
**[V]** exactly **one** row exists, with a live auth user.

Therefore: **exactly one platform_admin exists in production today.** Single-admin
config acts are possible. **Every quorum/dual-control config act is not**, because it
needs a second distinct `platform_admin` — and that includes `ticket.expiry_grace`,
`payout.settlement_maturity_interval`, `fee.buyer_service_bps`,
`deletion.post_event_hold_hours`, and both executor arms. **[V]**
`kernel.grant_platform_role` requires only a single platform_admin and refuses a
self-grant, so the bootstrap admin *can* mint the second one — the path is open, it has
simply never been walked.

**Classification: OWNER POLICY DECISION** (choosing the second human) **+ OPERATIONAL
CONFIGURATION** (performing the grant). It costs one call and it blocks five later
steps, so it should be step zero of any train.

## 6 · Recommended first activation train

**NAME.** **Venue-direct primary ticketing, single-venue pilot** — the narrowest slice
of Rail A that can sell one real ticket for one real event at one real venue, and
refund it.

**WHY.** It is the unique root of the native dependency graph; it is the only rail that
creates first-party revenue; its backend is already written and locally replay-proven;
and its ratified ordering is deliberately safe — the refund path deploys before the
charge path, so the system can give money back before it can take it.

**BUSINESS VALUE.** First-party inventory, first-party margin, and the venue
relationship — the pivot away from intermediating other people's tickets. A
single-venue pilot converts twelve authored migrations and five authored edges from
sunk cost into revenue, and produces the operational evidence every later rail needs.

**SCOPE — in.** Venue and organization setup; Stripe Connect onboarding for one org;
event and session drafting and publish; inventory and ticket-type publish; primary
checkout; payment confirmation; ticket issuance against a real signing key; refund;
settlement maturity; venue payout (**by hand, once**). Promoter attribution is
*captured* if a code is used.

**SCOPE — out.** Native resale; wallet passes; door scanning; CRM export; promoter
commission *funding and release*; automated payout sweeps.

**DEPENDENCIES.** Migrations 093→101 in order, plus 102 for the credential signer.
PostgREST exposure of `catalog` and `venue` — **after** the migrations. Five edge
deploys. One KMS ceremony. One Connect-onboarded organization. One venue console.

**CURRENT BLOCKERS**, each of which is a discrete act and none of which is engineering:
1. A second `platform_admin` (§5) — blocks every quorum config key.
2. The Gate-M re-attestation — blocks applying 094.
3. Ratification of `kernel.claim_refunds_for_execution` — hard gate before step 1.
4. G1 and G2 values; G3 (ceremony); G5 (recovery policy). G4 blocks promoter payout
   only, which is out of scope here.
5. Tax model and the `on_sale`/SALEABLE enforcement locus — owner and counsel.
6. Acknowledgement of the `deletion.post_event_hold_hours` rename.
7. Nine-to-ten migrations unapplied; five edges undeployed; `catalog`/`venue`
   unexposed; zero signing keys; zero organizations.

**IMPLEMENTATION REQUIRED.** DB: apply 093–102, forward-only, in order. Edge: deploy
`connect-onboarding`, then `stripe-webhook` (native branch), then `refund-execute`,
then `credential-sign`, and **`primary-checkout` last**. Web: a venue console (org
onboarding, event/session, inventory, orders, settlement). RN: primary discovery,
checkout, and credential-backed ticket display. Stripe: Connect Express (US,
`business_type=company`, `transfers` requested, org id in metadata) and the native
webhook branch. Secrets: KMS credentials for the signer. Config: the five values in
the ratified order, `feature.native_issuance_enabled = true` last.

**OWNER DECISIONS REQUIRED.** Blockers 1–6 above, in that order. Four are signatures,
one is a ceremony with two named humans and a booked window, one is a counsel question.

**EXTERNAL REQUIREMENTS.** A KMS provider; two operators with separated cloud IAM; one
real venue partner willing to run a pilot event; a Stripe Connect Express account for
that venue.

**MIGRATION 093+ REQUIRED: YES** — 093 through 102, forward-only, unrollbackable in
practice. This is the single most consequential property of the train and the reason
it must not be started before the signatures exist.

**CAN THIS RAIL BE ACTIVATED WITHOUT ACTIVATING NATIVE RESALE, WALLET, CRM, PROMOTER
PAYOUT OR DISPUTES?**

**YES for four of the five, with one honest qualification.**
- **Native resale — YES.** `feature.native_resale_enabled` stays `false`; legacy P2P
  resale is untouched and keeps running.
- **Wallet — YES.** `wallet.apple.enabled` stays `false`; no pass cert exists and none
  is needed.
- **CRM — YES.** `crm_export_worker_secret` stays absent; the ticks keep no-opping.
- **Promoter payout — YES, and by design.** Attribution is captured at checkout;
  commission is born `held`; ruling A4 and the substrate both keep row 12 shut. G4
  is not needed for this train.
- **Disputes — QUALIFIED NO, and this is the one coupling worth naming.** The train
  must deploy `stripe-webhook`, and the version that carries the native primary branch
  is the same version that first wires the native dispute writers to real callers. So
  activating primary ticketing **does** bring the native dispute path online with it.
  That is acceptable — it is strictly better than the alternative, since without it the
  `chargeback` settlement-line arm cannot fire at all — but it must be a conscious
  decision, not a side effect, and **PFA-31 (`kernel.resolve_dispute_native`) should be
  closed before the rail carries material volume.**

**TEST PLAN.** Full local replay 000→102 (the repo's rehearsal harness, canonical
`LC_ALL=C` filename order) with the pgTAP suite green and the Gate-2 public-schema
census unchanged; a staging application of the same chain; then, in production, an
end-to-end pilot on a single real event: onboard → publish → sell one ticket → confirm
→ issue → scan-free entry → refund it → close settlement → pay out by hand. Assert
after each step against `scripts/release/phase2_postapply_verify.sql`, extended with
primary-rail invariants.

**RED-TEAM PLAN.** Before the charge path deploys: attempt cross-venue settlement
recovery (the P0-1 shape 101 closed); attempt to buy inventory that is not
`SALEABLE`; attempt checkout as a `DELETION_PENDING` identity (the F-5 guard);
attempt to mint a credential without a signing key; attempt a refund that exceeds the
face cap net of held commission (the A5 shape 100 closed); attempt a config write as a
single admin on a quorum key; re-run the PFA-1 sweep after every migration and after
the PostgREST exposure change.

**STAGING PLAN.** A Supabase branch or a paid staging project carrying the full
000→102 chain, the five edges, Stripe **test-mode** Connect, and a throwaway signing
key from the same KMS provider but a **different** key — the production key is minted
once, in the ceremony, and never leaves it.

**ROLLBACK / FIX-FORWARD MODEL.** **Production is FORWARD-ONLY; there is no rollback
of 093–102.** The safety model is therefore *reversible arming on an irreversible
substrate*: every capability is gated by a flag or an unset config value, so the abort
action at every step is to **unset the config or set the flag false**, not to unapply
a migration. Concretely — `feature.native_issuance_enabled = false` stops all selling
instantly; unsetting `fee.buyer_service_bps` fails checkout closed; the executor arms
stay `false` so no machine moves money; and `primary-checkout` deploying last means
the abort surface is complete before the first dollar is reachable. Any defect found
after apply is fixed forward with a new migration, exactly as 100 and 101 already
demonstrate.

## 7 · Classification of everything this train would require

| Item | Class |
|---|---|
| Apply migrations 093–102 | IMPLEMENTATION FOLLOW-UP (owner-gated; forward-only) |
| Deploy the five authored edges | IMPLEMENTATION FOLLOW-UP |
| Venue console (web) and primary buyer flow (RN) | IMPLEMENTATION FOLLOW-UP |
| `deletion.refund_possible_window_hours` → `deletion.post_event_hold_hours` rename and re-anchor | **POST-FREEZE AMENDMENT** |
| Native dispute writers gaining callers via `stripe-webhook`; PFA-31 closure | **POST-FREEZE AMENDMENT** |
| G1 · `ticket.expiry_grace` value | OWNER POLICY DECISION |
| G2 · `payout.settlement_maturity_interval` value | OWNER POLICY DECISION |
| G3 · KMS ceremony (provider, two operators, window) | OWNER POLICY DECISION (irreversible) |
| G5 · post-payout recovery policy | OWNER POLICY DECISION |
| Gate-M re-attestation (gates applying 094) | OWNER POLICY DECISION |
| Ratify `kernel.claim_refunds_for_execution` | OWNER POLICY DECISION |
| Tax model; `on_sale`/SALEABLE enforcement locus | OWNER POLICY DECISION (with counsel) |
| Choosing the second `platform_admin` | OWNER POLICY DECISION |
| Granting the second `platform_admin` (§5) | OPERATIONAL CONFIGURATION |
| Expose `catalog` + `venue` over PostgREST, after the migrations | OPERATIONAL CONFIGURATION (two-person) |
| `inventory.*`, `fee.buyer_service_bps`, `deletion.post_event_hold_hours` | OPERATIONAL CONFIGURATION (quorum) |
| `feature.native_issuance_enabled = true` | OPERATIONAL CONFIGURATION (last act) |
| Stripe Connect onboarding for the pilot organization | OPERATIONAL CONFIGURATION |
| Secret rotation (separate window; never on an activation train) | OPERATIONAL CONFIGURATION |

---

**PRODUCTION ACTIVATION: NOT AUTHORIZED.**
**NEXT ACTION: OWNER AUTHORIZATION TO BUILD THE RECOMMENDED ACTIVATION TRAIN.**
