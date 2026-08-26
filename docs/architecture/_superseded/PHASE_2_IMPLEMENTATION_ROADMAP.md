# Snatch It — Phase 2 Implementation Roadmap

**Companion to `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` + `docs/architecture/_superseded/PHASE_2_ARCHITECTURE_REVIEW.md`.** Design/sequencing only — no code, SQL, migrations, or UI here. This is the layer the review identified as essential: the constitution is a **complete map**; this is the **short, ruthless path through it.** Build in this order, not in document order.

## Operating rules (apply to every phase)
- **Additive only.** New schemas beside the existing marketplace. The frozen money core and the live **external-rail marketplace stay untouched and shipping throughout** every phase below.
- **Staging-first, reproducible.** Every DB change is an append-only migration validated on staging and provable by the Phase-0 CI `db` fresh-bootstrap gate (`docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md`). Production DB apply stays a deliberate, gated promotion (Supabase auto-deploy remains OFF until history is reconciled).
- **Guardrails, not backlog.** Every object in the constitution is a *constraint on how you build*, not a *thing you must build now*. If a phase below doesn't name an object, you don't build it yet — you build the smallest thing that conforms.
- **The 15.A gate is a hard stop.** No native ticket credential is minted in production until every item in Review §15.A is done (C1, C2, C3, C4, C5, C6, C9, C10). This gate is repeated at the end of Phase 2A.

---

## Phase 2.0 — Foundation reconciliation (prerequisite; no product yet)
*Goal: a clean, reconciled, staged foundation to build primary ticketing on.*
- Close the Phase-0 owner actions (from `docs/security/SNATCH_IT_PHASE_0_COMPLETION_REPORT.md` §12): persistent staging (Stripe test), GitHub Pro + branch-protection ruleset, `migration repair` to reconcile history, HIBP, and ship the pending mobile security build.
- Stand up the **schema skeleton** additively — create empty `catalog`, `kernel`-extensions, `venue` schemas beside the existing `public`/marketplace (which is the external rail). Wire the modular-monolith GRANT boundaries and the "cross-schema writes only via kernel functions" discipline from day one (C7, C8).
- Decide **O5** (cross-rail seat-identity dedup key) on paper — it constrains the ticket model below.
- **Definition of done:** staging reproduces production; new empty schemas exist with correct GRANTs; CI enforces boundaries. No user-visible change.

## Phase 2A — Primary issuance core (the ticket atom)  ·  *no resale, no scanning yet*
*Goal: an approved venue can create an event and sell primary tickets that become real `kernel.tickets` a fan owns. This is where the 15.A gate is cleared.*
- **catalog:** `venues`, `events`, `event_session` (single implicit session auto-created for one-night events, per A3/C7).
- **kernel:** `organizations` + Stripe Connect payee + `org_members`; the **ticket atom** — `tickets`, `ticket_ownership_log`, and the single-writer **issuance + transfer engines** built correct from the start: **C1** asymmetric-signature credential (private key in kernel, public key for future doors), **C2** owner/principal authorization, **C3** `UNIQUE(cause,cause_ref)` on the log; first-class `payouts` + `refunds`.
- **venue:** `ticket_type` for `admission` + `table` only (GA + bottle service); `inventory_batch` (`public_sale` + `door`) + `inventory_hold` with server-max duration — oversell guarded by **C4** (`remaining≥0` + locked decrement, sharded/unit-row counter) and **C5** (serializable/advisory per-user caps); `orders`/`order_items`.
- **Money path:** `order` → existing **frozen** payment core → `kernel.issue_tickets()` (atomic issue + ownership-log + inventory draw). `resale_policy` ships as a stub set to `off` (C11).
- **Security:** extend the Phase-0 column-grant / no-self-grant / live-recheck discipline to every new authz + money-config table (**C9**); scope-qualified role helpers (A9).
- **✅ 15.A GATE (hard stop before this ships to production):** C1, C2, C3, C4, C5, C6-model, C9, C10-dedup-key all done and adversarially tested.
- **Definition of done:** a fan buys a primary GA/table ticket; it exists as a `kernel.tickets` row they own; no resale, no door yet.

## Phase 2B — Door + settlement  ·  *first venue live end-to-end*
*Goal: the fundraise demo — issue → buy → **scan** → **venue paid.***
- **venue:** `scan`, `door_pin` (loginless, event-scoped, expiring), `scan_device`; offline-first door built on the **C6** model from the start — asymmetric public-key verification, offline manifest **without any secret**, offline-window as an explicit reconcile/fraud state, first-admit-wins + fraud queue. `comp_allocation`, `guest_list`/`guest_entry`.
- **venue:** `settlement` → `kernel.payouts`; primary-void **refunds** (venues demand day-one refund capability).
- **admin:** the minimal **audited admin plane** (venue/org approval, refunds, held payouts) — replaces manual SQL; dual-control as a config-gated seam with the threshold itself dual-controlled (C11).
- **Definition of done + MILESTONE:** one approved Miami venue issues, scans at the door (including offline), and receives a reconciled payout. Demoable end-to-end story for the raise, with the marketplace still running untouched beside it.

## Phase 2C — Native resale (the differentiator; fast-follow)
*Goal: the unclaimed position — venue-governed secondary market on native tickets, with royalty.*
- **Resolve first (Review §15.D):** O1 (cancellation refund liability + the reserve that funds it), O3 (resale-policy snapshot drift), and confirm O5 (cross-rail dedup) is enforced.
- **market (native rail):** `listing(inventory_kind='native')` locking the ticket; `market_sale` written by `market` then `kernel.transfer_ticket_ownership()` in one txn (**C8**); `p2p_transfer`; `resale_policy` modes turned on incrementally (`transfers_only` → `fixed_cap`/`face_value_queue` → `buy_now` → `auction`/`offer`, per C11/A10); **venue royalty** captured at settlement via a named cross-context channel (never a join, C8).
- **Offline-transfer freeze (C6):** native resale/transfer for a session freezes once its offline door manifest opens — required before resale and offline scanning coexist.
- **Definition of done + MILESTONE:** a fan resells a native ticket; the credential invalidates atomically; the buyer's new credential works at the door; the venue earns its royalty. The full competitive thesis is real.

## Phase 2D — Promoter engine (nightlife distribution)
*Goal: arm the promoter — the distribution layer nightlife actually runs on.*
- **venue:** `promoter`, `promoter_link`, `attribution`, `affiliate`; commissions flow through `kernel.payouts` (`promoter_commission` type); instant-payout option.
- **Definition of done:** promoters sell via tracked links with per-link attribution and fast commission payout.

## Phase 3 — Social · Analytics · Adapters (later; not Phase 2)
- **social** schema (follows, venue-followers, groups, friend-attendance) — privacy-first (`attendance_visibility` default `only_me`, k≥3 aggregates, cross-venue firewall; C10); reads the graph, never writes ownership; group-buy via the one named `venue.reserve_group_claim()` door (A11).
- **analytics** schema (events_stream + rollups) once plain kernel queries stop sufficing.
- **External adapters** (first real integration): implement one adapter behind the anti-corruption layer with a hard REVOKE (zero EXECUTE on issue/transfer) and egress-allowlisted `validation_callback` (C10). Adding a provider = adapter + `resale_policy` mapping; touches no kernel invariant.

---

## Cross-cutting workstreams (run alongside, not as a phase)
- **Event outbox:** the trimmed ~16-event set (Review C11) on the existing cron; add an async consumer only when one exists.
- **Observability:** extend Phase-0 cron/webhook/payout health to issuance, scan-reconciliation, and the `paid_pending_transfer` dwell SLO (C3/C6 alarms).
- **Reproducibility:** every phase's migrations pass the CI fresh-bootstrap gate; no out-of-band objects (the Phase-0 Gate-2 lesson).

## Sequencing rationale (why this order)
1. **Revenue before differentiation.** Phase 2A–2B put a venue live and produce the fundraise demo without the slowest-to-build part (resale). 
2. **The gate is where it belongs.** The credential/authorization/concurrency must-fixes (15.A) are front-loaded into 2A because they are baked in at issuance and near-impossible to change afterward (Review H1).
3. **Resale is a fast-follow, not a foundation.** It has no inventory to trade until 2A–2B create native tickets and adoption; building it first is building a market with no sellers (PM finding).
4. **Social/analytics/adapters are deferred by design** (the brief) and by cost (two engineers) — they carry no first-venue value.

**One-line summary:** clear the foundation → build the ticket atom correctly (gate) → put a venue live at the door and get it paid → *then* turn on venue-governed resale → then promoters → then social/adapters. The marketplace never stops shipping; the money core is never reopened.
