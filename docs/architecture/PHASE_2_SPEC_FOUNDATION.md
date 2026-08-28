# Phase 2 Spec Foundation — binding shared vocabulary (committed copy)

> Rescued from the session scratchpad into the repository so its binding decisions survive the session. Referenced by all six implementation specs as "SPEC_FOUNDATION". Paths inside refer to the original session layout.


**Every Phase 2 implementation spec (schema, migration, RLS, RPC, edge, RN) MUST use the exact names, decisions, and IDs in this file.** It resolves the Gate-P open decisions so no spec author decides them on the fly. If a source document conflicts with this file, surface the conflict; do not silently pick a side. This file is design-only — no SQL/code.

Source authority order: `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` (§11 naming constitution binds) > `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` > `docs/architecture/_superseded/PHASE_2_FINAL_ARCHITECTURE_AUDIT.md` / `docs/architecture/_governance/ARCHITECTURAL_RISK_REGISTER.md` / `docs/architecture/_governance/CTO_DECISION_MEMO.md` (Gate decisions) > roadmap. Phase-0 docs (`docs/architecture/PHASE_1_FOUNDATION.md`, `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md`, `docs/security/SNATCH_IT_PHASE_0_COMPLETION_REPORT.md`) now live in this repository at those paths.

---

## 1. Contexts = Postgres schemas (MVP scope)
- **`kernel`** — identity extensions, organizations, ticket atom, ownership log, credential key-refs, payments-native, payouts, refunds, reserve (extension point), admin audit. The trusted core; cross-schema **writes** only via `kernel` SECURITY DEFINER functions.
- **`catalog`** — venues, events, event_sessions, platform_config, resale_policies. Kernel-owned reference data (A7/C7), readable by all.
- **`venue`** — ticket_types, inventory, orders, staff, scans, doors, settlements, comps, guest list, promoters.
- **`market`** — native/external listing bridge, auction, offer, market_sale, p2p_transfer. Integrates with the **existing live `public` marketplace**, does not replace it.
- **Deferred (document as extension points, DO NOT create in MVP):** `social`, `analytics`, `notify`, `adapter`, and the money-ledger objects (`reserve` beyond a stub, `clawback/receivable`, double-entry `ledger`) — Gate M / Gate L.

## 2. Existing live system — INTEGRATE, NEVER REWRITE
The frozen money core + external-rail marketplace live in `public`. Do not alter their semantics.
- **Identity:** `auth.users` (Supabase auth) + `public.profiles` are the identity system. Phase 2 does NOT create a new identities table. The canonical "Identity" object = `auth.users.id` (uuid). Kernel/venue/market rows reference `auth.users(id)`. Any Phase-2 per-identity extension (e.g. residency region, KYC ref) goes in a new additive `kernel.identity_ext` table keyed by `auth.users.id`, never by mutating `profiles`.
- **External rail (unchanged):** `public.listings`, `public.bids`, `public.payments`, `public.transfers`, `public.disputes`, `public.notifications`, risk/payout tables. The native rail's `market` objects reference these where a native listing must appear in the same discovery/checkout surface, via an additive bridge — see §7 "market bridge".
- **Money-in:** `public.payments` (frozen Stripe charge record, integer USD cents, deterministic idempotency, signed+replay-protected webhooks) remains the sole money-in event. Native orders/market_sales LINK to a `public.payments` row; they never re-implement charging.
- **Payouts/transfers writers:** existing service_role-only RPCs (migrations 056a/059/061/064). Native payouts extend this discipline, never bypass it.

## 3. Migration numbering baseline
True applied max across the phase0 chain = **070** (`070_reconcile_rls_policies_and_triggers.sql`), plus website-form timestamped files. Five **production security migrations** were then applied on top of it on 2026-08-27 — `071` (DB-1 guard_proof_status), `072` (H-1 listing INSERT guards), `073` (SEC-3 storage bucket upload constraints), `074` (SEC-1 privilege cleanup), `075` (SEC-4 + D-5 replay parity / storage policies / cron) — so the **true applied max is now `075`**. **Phase 2 migrations begin at `076_` and continue the zero-padded version-prefix scheme** (consistent with 066–075), NOT Supabase timestamp prefixes. Phase-2 packages are `076`–`091`; `071`–`075` are **not** Phase-2 packages (canonical map: `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md`). Surface that this tree (`mobile/profile-rpc-compat`) only physically contains up to ~045; the authoritative chain incl. 000_baseline_schema.sql + 046–070 is on `phase0/lockdown` — Phase 2 migrations are authored assuming the phase0 chain is merged to the integration branch first (a stated precondition, not a Phase-2 migration).

## 4. Resolved Gate-P physical decisions (BINDING — do not re-decide)

### C26 — Ownership-log idempotency (fixes the broken `UNIQUE(cause,cause_ref)`)
- The ownership log's idempotency key is **`UNIQUE(cause, cause_ref, ticket_atom_id)`** — one cause (e.g. one issuance batch, one refund) may write **N rows, one per ticket atom**, so multiplicity is allowed; but the *same atom* cannot be written twice for the *same* cause+cause_ref → replayed commands are no-ops.
- Double-transfer of the *same ticket in one sale* is prevented by: (a) `FOR UPDATE` on the atom row + single-writer transfer engine, and (b) a **per-`market_sale` terminal state machine** (`pending → completed | compensated`, `UNIQUE` one terminal), so a sale is EITHER forward-completed (cause=`market_sale`) OR auto-compensated (cause=`refund_void`) — never both. The compensate-XOR-complete guard is a CHECK/state constraint on `market_sale`, not on the log's uniqueness.
- Re-void across two different refund objects is prevented by the atom's **current state** (a `voided` atom rejects further terminal transitions under the row lock), not by the log uniqueness.

### C27 — `remaining` single source of truth
- **Authoritative:** a **locked mutable counter** on the inventory unit — `venue.inventory_batch` holds `capacity`, `held`, `sold` as columns; `remaining` is computed `capacity - held - sold` and guarded by a CHECK (`held>=0`, `sold>=0`, `held+sold<=capacity`) enforced inside the SECURITY DEFINER reserve/issue functions under `FOR UPDATE`.
- **Audit/derived:** `venue.inventory_movement` is an append-only ledger of every decrement/increment (hold, release, issue, void-return) for reconciliation and replay — it is NOT the operational truth; it must reconcile to the counter, and a nightly job asserts equality.
- Hot-row mitigation (C4/C22): the counter may be **sharded into `inventory_batch_shard` sub-counter rows**; `remaining = capacity - Σ(shard.held+shard.sold)`; last-unit fairness handled by ordered shard draw + a final single-shard fallback. Sharding is an MVP-optional optimization behind the same functions.

### C33 — Credential key-reference model (NO secret on the ticket row)
- The ticket credential is an **asymmetric signature**. The private signing key NEVER appears in any DB-readable table, mobile client, scanner, browser, or offline manifest. It lives in a KMS/HSM. 
- The DB stores only a **key reference**: `kernel.signing_key` holds `key_id`, `scope` (`per_event` default; `per_venue`/`global` allowed), `catalog` event/venue ref, `public_key`, `status` (`active|rotating|revoked`), `not_before`, `not_after`. The private key material is a KMS handle, not a column.
- `kernel.tickets` stores `credential_version` (monotonic int, derived-from/pinned-to the ownership log head) and the `signing_key_id` used; the actual signed token is produced by the **`credential-sign` Edge Function** calling KMS, never by Postgres. Doors verify with the `public_key` from the manifest.

### C35 — Acting principal at the kernel boundary
- Every `kernel`/`venue` SECURITY DEFINER write function takes the acting identity from **`auth.uid()` (server-derived), never a client-passed id**. The market→kernel native-sale path passes the buyer as a **server-verified** principal: the kernel re-checks that the payment (`public.payments`) belongs to the acting buyer and that the listing is `active`; it does NOT trust a `market`-supplied `buyer_id`. Trusted params = server-derived only; untrusted params = ids/amounts, all re-validated.

### C36 — Structural scope-qualified roles
- Roles are **scope-typed**, never bare strings. Model:
  - `kernel.org_member(org_id, identity_id, role)` where role ∈ `org_owner|org_admin|org_finance|org_marketing|org_promoter_manager|org_member` (org scope). **`SPEC CORRECTION` (ROLE_MODEL `F-1`)**
  - `venue.staff_role(venue_id, identity_id, role)` where role ∈ `venue_manager|venue_finance|venue_box_office|venue_marketing|venue_promoter_manager|venue_scanner` (venue scope). **`SPEC CORRECTION` (ROLE_MODEL `F-2`)**
  - `kernel.platform_role(identity_id, role)` where role ∈ `platform_admin|platform_support|platform_risk` (platform scope) — extends existing `public.admin_users`.
- Predicate helpers — **the canonical TEN, enumerated and never counted** (defining contracts: `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §1.1–§1.1e; membership rule: RLS §2.2 **`HELPER-DERIVED`**): `kernel.has_org_role(org_id, role[])`, `kernel.has_venue_role(venue_id, role[])`, `kernel.has_event_role(event_id, role[])` (event → resolves via catalog to venue), `kernel.is_platform(role[])` · **`kernel.has_org_role_over_venue(venue_id, role[])`** · **`kernel.has_org_role_over_event(event_id, role[])`** · **`kernel.is_org_affiliate(org_id)`** · **`kernel.is_promoter_for_event(event_id)`** · **`kernel.assert_door_session(device_id, session_id, door_session_id, token)`** · **`kernel.money_role_grant_matured(org_id)`**. **Door principals are NOT tested by `has_venue_role`** — see `PHASE_2_ROLE_MODEL_SPEC.md` §7; `assert_door_session` is `DEF`/`service_role` only and **never an RLS predicate** (RM-5). **`SPEC CORRECTION` (ROLE_MODEL `F-3`, extended; completed by `F-4` / `AUTHZ-C1C`)**

> **`SPEC CORRECTION` — the C36 label lists above were the pre-O-2 sets (`SF-2`).** They named `venue_door` and `venue_promoter`, **the exact strings ruling O-2 abolished**, in the file every implementation spec is told to take its names from. O-2 (RATIFIED, Gate P) renames `venue_door → venue_scanner`, **removes `venue_promoter` entirely** — a promoter is a `promoter_link` row-ownership relationship, never a staff-role label — and fixes the canonical stored set at **fifteen plane-prefixed labels in three disjoint enums**: org (6), venue (6), platform (3). Standing rule **RM-1**: every label MUST begin with its plane token. This is the same defect ratification row **D5** purged from the constitutions; it survived here.
>
> **The helper list gained a fourth omission after F-3 was filed.** `kernel.money_role_grant_matured(org_id)` is **new** with `AUTHZ-C1B` and is what makes SoD-1/SoD-2 mean what they claim — without it the money-plane counterparty stays mintable by the role that needs one. ROLE_MODEL filed **F-1…F-3** and **no `F-4`**, so the helper is added here on the authz pass's own authority and the omission is reported back. **`PHASE_2_RLS_PERMISSION_SPEC.md` §2.2 additionally states its helper count four different ways** (heading "eleven", ten bullets, RM-2 "nine", two tests "eleven") — **not resolved here; reported to the RLS owner**, because `T-RLS-ROLE-02` enumerates "the eleven helpers" structurally and cannot be written until one number is right. No RLS/RPC may compare a bare `role='finance'`; scope is always in the predicate. Org and venue role enums are DISJOINT label sets so cross-scope confusion is structurally impossible.
>
> ---
>
> ### ✅ `DISCHARGED 2026-08-28` — `AUTHZ-C1C` · ratification rows **C73** / **D13** · RPC **§1.1e** · RLS **§2.2 `HELPER-DERIVED`**
>
> **The filing above stands as the record of what was found; this block records what was done about it. Nothing above is deleted.**
>
> **(1) The count.** The report named four statements in the RLS spec; there were **six** across four documents, and they gave **three** numbers over **two** sets. Resolved **mechanically, not by choosing**: the **union** of every name any statement gives is **ten**; the **intersection** of the three statements that actually *enumerate* (RLS §2.2's bullets, the traceability matrix's `C2 · O-2` row, and RPC §1.1–§1.1d) is **nine**; the sole element of the difference is **`kernel.money_role_grant_matured`**. **"Eleven" corresponds to no set — there is no eleventh helper anywhere in this corpus under any name** — and **"nine" is simply the membership before ratification row `C58`**. RLS §11.2's EXEC table, which nobody had counted, independently already carried all ten. All six statements now read **ten and enumerate by name**; `HELPER-DERIVED` clause 4 forbids any of them being a bare count again.
>
> **(2) `T-RLS-ROLE-02` is writable.** The report was right that it *"cannot be written until one number is right"* — and the fix is not to pick the number. **A count assertion passes on the wrong set of the right size**, which is exactly the failure that let a helper reach four money call sites with no definition. The test now consumes the **literal ten-name enumeration**; **`T-RLS-ROLE-06`** asserts that enumeration equals `pg_proc` in both directions with a non-vacuity guard; **`T-RLS-ROLE-07`** asserts the definer/owner/`STABLE`/`search_path`/grant shape per name.
>
> **(3) The helper this section added "on the authz pass's own authority" now has a contract and a ratification.** `kernel.money_role_grant_matured` was bound in RPC §10.3, §17.1, §17.2 and §17.7 and **defined nowhere**; RPC **§1.1e** supplies the full contract, and **C73** ratifies it. **`F-4` is filed** by the role model — this list was *also* missing `assert_door_session` and `is_promoter_for_event`, which no `F-n` row had ever asked for, and both are added above.
>
> **(4) Two things found that this report did not name, both recorded rather than fixed silently:** the **platform plane** of the maturity control is unbound and the ratified signature cannot express it (**C74 / `OPEN-GATED(O11)`**, RPC §20.14 `R-22`); and RPC **§10.3** took `p_org_id` and `p_settlement_id` without requiring them to agree, so every authority predicate could be a true statement about the wrong organization (fixed under the settlement's lock, `T-RPC-AUTHZ-20`).

### C41 — Re-entry (MVP decision)
- **MVP = no re-entry.** `venue.scan` records admission; `kernel.tickets.state` terminal `scanned` stands for the single-night GA MVP. Re-entry is a **named future change** (like H6): the extension point is a `venue.scan` table that already supports **multiple scan rows per ticket per session** with a `direction` (`in|out`) column defaulting to `in` and a `scan_type`; MVP enforces first-`in`-wins and treats a second `in` as duplicate. Turning on re-entry later = relax the terminal rule + honor `out`/`in` pairs. No schema rewrite required. Document this explicitly in schema + RN specs.

### C42 — Optional seat/unit hedge
- `kernel.tickets` carries a **nullable `seat_ref`** (text/opaque) and a nullable `unit_row_id` FK to an optional `venue.inventory_unit` table. MVP GA/table inventory leaves these NULL (scalar capacity via the counter). Reserved seating later = populate `inventory_unit` unit-rows + `seat_ref`; the atom, ownership log, and credential are unchanged (additive). `table` ticket_type is GA-with-a-named-table (deposit + at-the-room balance, C45 deferred), NOT assigned seating — it also leaves `seat_ref` NULL in MVP. Document that unit-rows (C4/C22 sharding) and seats are the same mechanism.

### D3 — Canonical cause-code registry (ONE list, both docs)
`issue · primary_sale · comp · door_sale · p2p_transfer · market_sale · auction_sale · admin_action · refund_void · import · promoter_commission · settlement · chargeback`. New causes added only by amendment. Every spec uses exactly this enum for ownership-log `cause` and money-ledger cause. (D1: use "SSCAS"/"closed set" language, never "the one cross-aggregate transaction". D2: ticket has NO `refunded` terminal — money reversal = `voided` with cause `refund_void`.)

## 5. SSCAS — the closed set of sanctioned synchronous cross-aggregate transactions (for RPC lock order)
> **ENUMERATION SUPERSEDED (consolidation 2026-08-25, Agent E finding E-1).** The **canonical closed
> enumeration is the FIFTEEN-member list in `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` §15 C12** (members 10–15
> added by C28's closure audit: event-cancellation cascade, dispute-resolution reversal, C25
> auto-compensation, auction deposit-release, group-buy claim, wallet checkout — the last two non-MVP,
> modeled only). The 9-member working list below is retained for provenance; where numbering differs,
> **CDM C12 wins**. The global lock order is identical in both and unchanged (shard draw = ascending
> sub-counter/`shard_no`).

Every synchronous multi-aggregate write is ONE named member of the canonical set; no other is allowed. **Global lock order (acquire ascending, release descending):**
`Event/Session → Inventory(batch, then sub-counter/shard ascending shard_no) → Order → Listing → Ticket Atom(ascending ticket_atom_id) → Payment/Payout/Reserve/Settlement`.
Original working members (provenance; see supersession note above):
1. **Primary issuance** (`issue_ticket_atoms`): Order → Inventory draw → Ticket mint (N atoms) → ownership-log `issue`.
2. **Native sale / resale** (`transfer_ticket_ownership` via market): Listing → Ticket lock/transfer → ownership-log `market_sale` → Payment link (C8).
3. **Refund-void** (`refund_primary_order` / `void_ticket_atom`): Refund → Ticket(s) void (N atoms) → Inventory return → ownership-log `refund_void`.
4. **Settlement → payout** (`close_settlement`): Settlement lines → Payout (never touches ticket history).
5. **Attribution → commission** (`promoter_commission` at settlement): Attribution → Payout (`promoter_commission`).
6. **Native listing create** (`create_listing` native): Ticket lock → Listing.
7. **P2P transfer start/accept** (`create_p2p_transfer`/`accept_p2p_transfer`): Ticket lock → Transfer → (on accept) ownership-log `p2p_transfer`.
8. **Dispute freeze + resolution** (`admin_resolve_dispute` native): Dispute → Ticket freeze → (on resolve) Payment reversal + Payout clawback + ownership-log adjust.
9. **`paid_pending_transfer` auto-compensation** (C25 sweep): Payment state → Ticket unlock/void → Listing → Refund.
(+ event-cancellation cascade = a bounded batch of member #3, and auction-close deposit release = member #2 variant — both enumerated so the set is genuinely closed.)

## 6. Canonical table inventory (exact names, owner, PK, source-of-truth status, MVP)
`SoT` = source of truth · `PROJ` = projection/derived · `AO` = append-only · `MUT` = mutable-state · `EXT` = extension point (spec but not create in MVP).

### kernel
| table | PK | kind | notes |
|---|---|---|---|
| `kernel.identity_ext` | `identity_id`→auth.users | MUT | residency_region (default 'us-east'), kyc_ref; additive to profiles |
| `kernel.organization` | `org_id` | MUT | Stripe Connect payee ref (reuse existing connect ids), status |
| `kernel.org_member` | `(org_id,identity_id)` | MUT | role enum (C36 org scope) |
| `kernel.platform_role` | `(identity_id,role)` | MUT | extends public.admin_users |
| `kernel.tickets` (ticket atom) | `ticket_atom_id` | SoT | event_session_id, org_id, ticket_type_id, current_owner_id (PROJ head), state, resale_state, credential_version, signing_key_id, home_region, seat_ref (null), unit_row_id (null), external_seat_ref (null, C17) |
| `kernel.ticket_ownership_log` | `(ticket_atom_id, sequence)` | SoT/AO | the ledger; C26 idempotency `UNIQUE(cause,cause_ref,ticket_atom_id)` |
| `kernel.signing_key` | `key_id` | MUT | public_key + KMS handle ref; C33 |
| `kernel.payment_native` | `id` | MUT | links order/market_sale ↔ public.payments; never re-charges |
| `kernel.payout` | `payout_id` | MUT | native payouts; type incl promoter_commission; extends payout discipline |
| `kernel.refund` | `refund_id` | MUT | money reason; drives refund_void |
| `kernel.reserve` | `reserve_id` | EXT | Gate M — stub only in MVP |
| `kernel.admin_audit` | `id` | AO | privileged action log (extends existing admin logging) |
| `kernel.identity_demographic` | `identity_id` | MUT | **J-4.** Voluntary self-described attributes; profile enrichment only, never signup. Value never leaves Postgres — no edge function, no log, no notification payload. Pkg `077` |
| `kernel.identity_demographic_erasure` | `id` | AO | **J-4 / J-12.** Value-free erasure tombstone `(identity_id, erased_at)`. `identity_id` is deliberately **FK-free** — a CASCADE FK would delete the tombstone in the very statement that creates the need for it. Written by a `BEFORE DELETE` row trigger, so *every* removal path produces one. Pkg `077` |
| `kernel.identity_contact_pref` | `identity_id` | MUT | **K-8.** The fan's master contact switch. Definer-only; no client role reads it. Pkg `077` |
| `kernel.identity_contact_pref_event` | `id` | AO | **K-8 / K-19.** `(identity_id, venue_email_contact, occurred_at)`. Exists so the consent gate is **as-of evaluable**: without history a paged export necessarily evaluates its conjuncts at inconsistent instants. Definer/`service_role` only, `REVOKE UPDATE, DELETE`. Pkg `077` |
| `kernel.org_contact_consent` | `(identity_id, org_id)` | MUT | **K-8.** Per-org, per-order contact consent — the gate for **both** the email and the name cell in an export. Pkg `082` |
| `kernel.org_contact_consent_event` | `id` | AO | **K-8 / K-19.** `(identity_id, org_id, event ∈ granted\|withdrawn, occurred_at, notice_version, source_order_id)`. Same as-of reason as above. Definer/`service_role` only, `REVOKE UPDATE, DELETE`. Pkg `082` |
| `kernel.org_customer_key` | `org_id` | MUT | **K-8.** The per-org HMAC key behind `customer_ref`. Definer/`service_role` only — **no human role, including `platform_admin`**. Pkg `077` |

### catalog
| table | PK | kind | notes |
|---|---|---|---|
| `catalog.venue` | `venue_id` | MUT | org_id owner, approval status |
| `catalog.event` | `event_id` | MUT | venue_id, status |
| `catalog.event_session` | `session_id` | MUT | event_id; single implicit session auto-created for one-night events (A1/A3) |
| `catalog.platform_config` | `key` | MUT | fee/window/policy VALUES (A8); app logic frozen |
| `catalog.resale_policy` | `policy_id` | MUT | modes off/transfers_only/fixed_cap/face_value_queue/buy_now/auction/offer (A10); default off (C11) |

### venue
| table | PK | kind | notes |
|---|---|---|---|
| `venue.ticket_type` | `ticket_type_id` | MUT | admission|table (C11); price snapshot |
| `venue.inventory_batch` | `batch_id` | SoT | capacity/held/sold counter (C27 authoritative); public_sale|door |
| `venue.inventory_batch_shard` | `(batch_id,shard_no)` | SoT | optional sub-counter (C4/C22) |
| `venue.inventory_movement` | `id` | AO/PROJ | audit ledger, reconciles to counter (C27) |
| `venue.inventory_hold` | `hold_id` | MUT | server-max TTL |
| `venue.inventory_unit` | `unit_row_id` | EXT | C42 optional seat/unit hedge |
| `venue.order` | `order_id` | MUT | buyer, pending→paid→partially_refunded→refunded→cancelled |
| `venue.order_item` | `id` | MUT→immutable | immutable after issue |
| `venue.staff_role` | `(venue_id,identity_id,role)` | MUT | C36 venue scope |
| `venue.door_pin` | `pin_id` | MUT | loginless, event/session-scoped, expiring |
| `venue.scan_device` | `device_id` | MUT | manifest sync state |
| `venue.scan` | `scan_id` | AO | direction in|out (C41 hedge), scan_type, offline_pending, fraud_flag |
| `venue.settlement` | `settlement_id` | MUT | → kernel.payout; never touches ticket history |
| `venue.settlement_line` | `id` | AO | rounding-bearer named (C31 later balances) |
| `venue.comp_allocation` | `id` | MUT | A4 |
| `venue.guest_list` / `venue.guest_entry` | `id` | MUT | A4 |
| `venue.promoter` / `venue.promoter_link` / `venue.attribution` | `id` | MUT | Phase 2D; commissions via kernel.payout |
| `venue.door_session` | `door_session_id` | SoT | **H-3 — the bearer artifact the door actually holds.** The PIN *provisions*; this row is what every subsequent relay call presents. `token_hash` is never client-readable **on any path, for any role, including `platform_admin`** — there is no legitimate reader of a verifier. Deny-all RLS, no DELETE, revoke-only forward transition; `revoke_door_pin` cascades to it. Pkg `086`. **Two specifications of this table diverge — see the note below** |
| `venue.holder_mix_snapshot` | `snapshot_id` | PROJ | **J-4.** Per-session published aggregate. Suppressed snapshots emit no denominators (R6). Pkg `087` |
| `venue.holder_mix_bucket` | `(snapshot_id, bucket)` | PROJ | **J-4.** Per-bucket counts with the floor of 5 as a `CHECK` — **a sub-floor bucket cannot physically be stored**, not merely hidden. Pkg `087` |
| `venue.export_job` | `job_id` | MUT | **K-8.** CRM export lifecycle `queued→running→ready→failed` + `revoked`/`expired`/`purged`, with `artifact_state` tracked **separately** from the job state because the two genuinely diverge (a job is `revoked` the instant the RPC commits; its object survives until the purge route runs). Pkg `087` |

### market (native rail; bridges to existing public.*)
| table | PK | kind | notes |
|---|---|---|---|
| `market.listing_native` | `listing_id` | MUT | inventory_kind native; locks ticket_atom; resale_policy_snapshot; may reference/mirror into public.listings for unified discovery (bridge, §7) |
| `market.auction` | `auction_id` | MUT | child of listing (A-model) |
| `market.offer` | `offer_id` | MUT | buyer-initiated |
| `market.market_sale` | `sale_id` | SoT | consummated resale; terminal state machine pending→completed|compensated (C26) |
| `market.p2p_transfer` | `transfer_id` | MUT | native P2P; distinct from public.transfers (external) |

> **`SPEC CORRECTION` — eleven tables added to this inventory (`SF-1`).** Four passes recorded additions here and **none was applied**, so this section — the file every implementation spec is told to treat as the canonical name list — was missing objects that four other specs had already contracted, scheduled into packages, and written pgTAP against.
>
> | Source | Correction ID | Tables |
> |---|---|---|
> | `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §10.2 | **J-4** | `kernel.identity_demographic` · `kernel.identity_demographic_erasure` · `venue.holder_mix_snapshot` · `venue.holder_mix_bucket` |
> | `PHASE_2_CRM_EXPORT_SPEC.md` §11.2 | **K-8** (as amended by **K-19**) | `kernel.identity_contact_pref` · **`kernel.identity_contact_pref_event`** · `kernel.org_contact_consent` · **`kernel.org_contact_consent_event`** · `kernel.org_customer_key` · `venue.export_job` |
> | `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §17 / schema §3.10a / edge §3.9a | **H-3** | `venue.door_session` |
>
> **The standing count of "eight" is stale and is corrected here to eleven.** `PHASE_2_SCOPE_AMENDMENT_2026_08.md` **X-14** and its request **R-6** both say *eight* — four demographics plus four CRM. That was accurate when written and is not now: **K-19 added the two consent event logs**, taking the CRM set from four to six (**K-8** says *six*, and the CRM spec's own RLS delta lists six deny-all rows). Adding `venue.door_session` gives **eleven**. Anyone reconciling against X-14's number will still find two missing and conclude this section is right.
>
> **Why the two event logs are not bookkeeping.** `kernel.identity_contact_pref` and `kernel.org_contact_consent` are **mutable**. A CRM export is built in **pages**, so without an append-only history the consent gate necessarily evaluates its conjuncts at *different instants across pages* — which falsifies the byte-identical determinism the export's replay property depends on. The event logs are what make the gate as-of evaluable at one stamped `gate_as_of`. They carry **no contact value** — an org id, a state, a timestamp.
>
> **REPORTED, NOT RESOLVED — `venue.door_session` has two divergent specifications, and this inventory deliberately states neither.** `PHASE_2_EDGE_FUNCTION_SPEC.md` §3.9a and `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §3.10a (with migration plan `086`) disagree on four points: **(1)** the `assert_door_session` fourth argument (`p_session_ref` vs `p_door_session_id`); **(2)** the non-secret selector — a separate `UNIQUE` text `session_ref` column vs the PK itself, with the schema spec carrying **no `session_ref` column at all**; **(3)** the revocation model (`revoked_at IS NULL` + partial index vs a `status` column + partial `UNIQUE(device_id, event_session_id) WHERE status='active'`); **(4)** `UNIQUE(token_hash)`, present in the plan and absent from the edge spec's list. **These are not stylistic** — (1) is a signature the door's entire authorization surface is called through, and (2) decides what a client sends. **Owners: schema + RPC + edge, together.** This row names the table so it stops being invisible; it does not pick a side.
>
> **Also owed, and not this file's to give:** `PHASE_2_RLS_PERMISSION_SPEC.md` §6 needs the matching **deny-all rows** — ten from J-3/K-7, plus `venue.door_session`. A table in this inventory with no §6 row is a table an implementer creates with default grants.

## 7. Market bridge rule
Native listings appear in the same discovery/checkout as external ones WITHOUT rewriting `public.listings`. Bridge = a read view (`market.listing_unified`) unioning `public.listings` (external) and `market.listing_native` (native) with a discriminator; checkout routes by rail. Native checkout calls `kernel.transfer_ticket_ownership` (C8); external checkout stays on the existing path. No native object mutates a `public.*` money/custody row except by linking to a `public.payments` id.

## 8. Phase-0 security invariants every spec preserves
deny-by-default RLS; no broad `USING(true)` on sensitive tables; no direct client writes to money/custody ledgers (RPC-only); column-scoped grants; live-table recheck for money-consequential actions (not stale JWT); SECURITY DEFINER `search_path` pinned (066); explicit REVOKE-then-GRANT (067); `service_role` = machine identity never human authority (056b/063); constant-time secret comparison; stripe-webhook keeps `verify_jwt=false`.

## 9. Product language (RN spec) — never leak architecture terms
User-facing: Official Ticket · Resale Ticket · Transfer · My Ticket · Venue · Event · Ticket Type · Buy · Bid · Sell. NEVER show: kernel, catalog, rail, ticket atom, SSCAS, credential_version.

## 10. Deliverable file names (exact)
1 `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` · 2 `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md` · 3 `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` · 4 `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` · 5 `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` · 6 `docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` · 7 `docs/architecture/_superseded/PHASE_2_IMPLEMENTATION_SPEC_REVIEW.md`. Write to repo root `/Users/josetascon/snatchit/`.
