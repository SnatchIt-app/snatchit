# Phase 2 — RPC / SECURITY DEFINER Function Contracts

**Status:** BUILD-READY DESIGN SPEC. **Design-only — NO SQL, no function bodies.** Each contract is written
so an implementing engineer can author a `SECURITY DEFINER` function from it **without making an architectural
decision**. Where a decision remained open it is flagged under §16 RECONCILIATION.

**Binding inputs (authority order):**
1. `scratchpad/SPEC_FOUNDATION.md` — **BINDING**: §5 SSCAS + global lock order; §4 C26/C27/C33/C35/C36 and D3
   cause-codes; §2 integrate-never-rewrite; §8 security invariants.
2. `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` — the authoritative tables/columns each function reads/writes
   (exact names used throughout).
3. `PHASE_2_RLS_PERMISSION_SPEC.md` — the sanctioned write path per RPC-only table; role checks match its
   `has_*_role` model and §11 EXECUTE-authority table.
4. `SNATCH_IT_DOMAIN_ARCHITECTURE.md` — C8 native-sale boundary (§6.2/§10), the transfer engine as sole
   custody writer (§9.4), the DB-enforced invariants (§2).
5. Frozen live money-core RPCs in `snatchit-phase0/supabase/migrations/` (`reserve_buy_now`,
   `mark_listing_sold`, `complete_auction_payment`, `ensure_transfer_exists`, `record_transfer_payout`,
   `admin_resolve_dispute`, `claim_stripe_webhook_event`, …). Native RPCs **complement** these; they never
   duplicate or rewrite the external-rail / money-in path.

---

## 0. Global RPC contract conventions (stated ONCE; every contract below inherits these)

To keep each contract readable, the following hold for **every** function unless a contract overrides them.
Read this section first; per-RPC blocks state only the deltas.

### 0.1 Definer discipline (every write RPC and every read RPC)
- **`SECURITY DEFINER`, owned by `postgres`**, `search_path` pinned (Phase-0 066). `REVOKE EXECUTE FROM
  anon, public` first, then GRANT EXECUTE narrowly (067). GRant target is `authenticated` **with an in-body
  predicate re-check** (the GRANT admits the call; the predicate decides authority) — except **definer-only**
  functions (marked `EXEC: service_role/definer`) which GRANT EXECUTE to `service_role` only and are invoked
  by another RPC or an edge function, never a UI.
- **Actor derivation (C35):** the acting principal is **always** `p_actor := auth.uid()` — **server-derived,
  never a client parameter.** No contract accepts a client-supplied actor/`buyer_id`/`user_id` as authority.
  Where a downstream principal must be named (e.g. native-sale buyer), it is **re-verified against a live
  table** (payment ownership), never trusted from the caller. Any `*_id` in the parameter list is
  **untrusted/client-supplied** and re-validated under lock; the only **trusted/server-derived** inputs are
  `auth.uid()`, `now()`, server-computed prices/fees, and values read from live tables inside the txn.
- **Role tests (C36):** authority is tested **only** via `kernel.has_org_role(org_id, role[])`,
  `kernel.has_venue_role(venue_id, role[])`, `kernel.has_event_role(event_id, role[])`,
  `kernel.is_platform(role[])` — live-table reads, never a JWT claim, never a bare `role='…'` string. Enum
  label sets are disjoint by scope (org/venue/platform).
- **Deny-by-default:** if the predicate fails → `RAISE insufficient_privilege` (`42501`); the function makes
  no writes. No fall-through.

### 0.2 Idempotency (C16 + C26)
- Any state-creating RPC accepts `p_command_key text` (**untrusted**) and enforces the schema's per-table
  `UNIQUE(<owner>, command_idempotency_key)`. A replay of the same key is a **no-op that returns the original
  outcome** (look-up-then-return), not a duplicate write or an error.
- Custody writes additionally rely on the ownership-log `UNIQUE(cause, cause_ref, ticket_atom_id)` (C26): a
  replayed cause+cause_ref+atom is rejected by the index → the transfer is a proven no-op (see §7 engines).
- Money-out writes rely on `kernel.payout.idempotency_key` / `kernel.refund.idempotency_key` deterministic
  keys (Phase-0 payout discipline). Retries recover the original row.

### 0.3 Audit (every privileged mutation)
- Every privileged RPC (approvals, role grants, refunds, voids, key ops, config, payout holds, capacity
  overrides) **INSERTs its own `kernel.admin_audit` row in the same transaction** — `actor_identity`
  (server-derived), `action` (namespaced), `subject_kind`/`subject_id`, `reason_code`, `before`/`after`. Not
  a separate client call; it commits or rolls back with the action.

### 0.4 Locks, lock order, SSCAS
- The **global lock order** (acquire ascending, release reverse — SPEC_FOUNDATION §5, schema §0.9):
  **`Event/Session → Inventory(batch, then shard ascending shard_no) → Order → Listing → Ticket Atom
  (ascending ticket_atom_id) → Payment/Payout/Reserve/Settlement`.**
- Every **synchronous multi-aggregate** write names its **SSCAS member** (§14) and lists the aggregate
  classes it locks, in that order. A function that touches **one** aggregate class is tagged
  `SSCAS: n/a (single-aggregate)` and is, by definition, not a cross-aggregate transaction.
- Row locks are `SELECT … FOR UPDATE` on the exact PK row(s); multi-atom lots lock atoms by **ascending
  `ticket_atom_id`**; sharded inventory draws ascending `shard_no` with `SKIP LOCKED` + a final single-shard
  fallback (C27).

### 0.5 Result & failure conventions
- **Result shape:** a single composite/JSON row `{ status, <ids>, <derived fields> }`; `status ∈
  {ok, noop_replay, rejected}` where relevant. Read RPCs return a set/JSON. Stated per-RPC where non-obvious.
- **Failure taxonomy (named, reused):** `insufficient_privilege(42501)` · `precondition_failed` (state/guard)
  · `oversell_rejected` (C27 CHECK) · `idempotency_replay` (returns original, not an error) ·
  `not_found` · `conflict_locked` (atom/listing already locked/terminal) · `payment_unverified`
  (C35 buyer/payment mismatch) · `frozen` (door-freeze, recon #3) · `policy_violation` (resale cap/window).
- **Retry semantics:** every RPC is **idempotent/re-entrant** by the keys in §0.2, so callers (webhooks,
  sweeps, double-taps) may retry safely. Stated per-RPC only where the retry path differs.
- **DELETE:** no RPC deletes rows (GP-2). Reversal = a forward state transition or a compensating row.

### 0.6 DB RPC vs EDGE-fronted (mandated distinction)
A contract is tagged one of:
- **`DB-RPC`** — pure in-Postgres, atomic; no external I/O.
- **`EDGE-FRONTED`** — an **Edge Function** performs the external side-effect (Stripe charge/refund/transfer,
  KMS signing, push) and then calls the atomic **DB-RPC** for the state transition. The DB-RPC itself never
  does external I/O (invariant: money-in is `public.payments`; signing is KMS via `credential-sign`). These
  are **flagged for the Edge spec (deliverable #5) to pick up** — this document does NOT design edge functions,
  only the DB-RPC they wrap and the boundary contract.

### 0.7 What kernel/venue RPCs may NEVER do (forbidden globally)
- Never accept a client actor as authority (C35). Never write a `public.*` money/custody row except by
  **linking** to a `public.payments` id (SPEC_FOUNDATION §7). Never charge/refund/transfer money or sign a
  credential inside Postgres (those are edge/Stripe/KMS). The **kernel never writes `market` tables**; the
  `market` layer writes `market.*` then calls the kernel engine in the same txn (C8 — no dependency
  inversion). `market`/`venue` never write `kernel.ticket_ownership_log`/`kernel.tickets` directly — only via
  the three kernel engines.

---

## 1. Predicate helpers & scoped read RPCs (the authorization + read substrate)

### 1.1 `kernel.has_org_role(p_org_id, p_roles text[])` · `kernel.has_venue_role(p_venue_id, p_roles[])` · `kernel.has_event_role(p_event_id, p_roles[])` · `kernel.is_platform(p_roles[])`
- **DB-RPC** (predicate helper). **Purpose:** the ONLY sanctioned role test (C36).
- **Actor:** `auth.uid()`. **Params:** all **untrusted** (scope id + requested label set). **Server-derived:**
  `auth.uid()`.
- **Reads:** `kernel.org_member` / `venue.staff_role` (+ valid non-expired `venue.door_pin` for `venue_door`) /
  `kernel.platform_role` (+ `public.admin_users` bootstrap). `has_event_role` resolves `catalog.event.venue_id`
  → `has_venue_role` (and `catalog.event.org_id` → `has_org_role` for org authority over an event).
- **Writes:** none. **Locks:** none (read). **SSCAS:** n/a. **Idempotency:** n/a (pure).
- **Result:** boolean. **Security:** live read (a revoke takes effect immediately; stale JWT cannot re-grant —
  I-5). `STABLE`, `search_path` pinned. **Forbidden callers:** none (any RPC/policy may call); never replaced
  by a bare string compare.

### 1.2 `market.get_ticket_history(p_ticket_atom_id)` — redacted owner history (recon #5)
- **DB-RPC** (read). **Purpose:** the ONLY client path to custody history; raw `kernel.ticket_ownership_log`
  is deny-all to clients (RLS §7.6).
- **Actor/role:** `auth.uid()` must be the atom's **current** owner (live `kernel.tickets.current_owner_id`).
- **Params:** `p_ticket_atom_id` (untrusted). **Reads:** `kernel.tickets`, `kernel.ticket_ownership_log`.
  **Writes:** none. **SSCAS:** n/a.
- **Result:** ordered rows of **plain verbs** (`bought · transferred · scanned · listed`) mapped from `cause`,
  with `occurred_at`. **HIDES:** raw cause-codes, `command_idempotency_key`, `credential_version_after`,
  `state_transition`, and **all prior-owner PII** (`from_identity`/`to_identity` → rendered "you
  transferred" / "transferred to you", never a counterpart id/name).
- **Failure:** `not_found` / `insufficient_privilege` if not current owner. **Forbidden callers:** anyone not
  the current owner (venue/org staff use `get_ticket_custody_chain`; platform uses full-chain RPC).

### 1.3 `kernel.get_ticket_custody_chain(p_ticket_atom_id)` — staff/platform chain
- **DB-RPC** (read). **Role:** issuing `venue_manager`/`org_owner`/`org_admin`/`org_finance` for **own-event
  atoms** (counterpart PII still redacted), OR `is_platform([platform_support])`; **`platform_risk`/
  `platform_admin` get the full unredacted chain** (fraud/dispute/audit).
- **Reads:** `kernel.ticket_ownership_log` + `kernel.tickets` (+ `catalog.event`/`event_session` to resolve
  own-event scope). **Writes:** none. **SSCAS:** n/a. **Result:** ordered log rows (redaction level by role).
- **Forbidden callers:** the ticket owner (they use §1.2); any client below `is_platform` outside own-event scope.

### 1.4 `market.get_market_sale_status(p_sale_id)` — pollable finalize status (recon #2)
- **DB-RPC** (read). **Role:** `auth.uid() ∈ {buyer_id, seller_id}` of the sale (owner-scoped).
- **Reads:** `market.market_sale`. **Writes:** none. **SSCAS:** n/a.
- **Result:** `{ terminal_state(pending|completed|compensated), sale_state(initiated|paid_pending_transfer|
  settled), paid_pending_since }` **only** — **no cause-codes, no fee split, no counterpart PII.** Drives the
  RN "Finalizing…" → success / compensated-refund flip. **SLO:** the bounded `paid_pending_transfer` dwell is
  named in the Edge spec; this read is cause-code-free by contract.
- **Forbidden callers:** anyone not buyer/seller (org finance royalty read is a separate scoped path).

> All three read RPCs are `STABLE`, definer, `search_path` pinned, GRANT EXECUTE to `authenticated` with the
> in-body owner/role recheck. They are the sanctioned substitute for direct SELECT on money/custody tables.

---

## 2. ORGANIZATION

### 2.1 `kernel.create_organization(p_legal_name, p_display_name, p_command_key)` — **DB-RPC**
- **Purpose:** apply to create an org; caller becomes its first `org_owner`. **Actor:** any `authenticated`.
  **Role:** none beyond authentication.
- **Params:** `p_legal_name`,`p_display_name`,`p_command_key` (all **untrusted**). **Server-derived:**
  `auth.uid()` → first owner; `status:='applied'`; `home_region:='us-east'`.
- **Preconditions:** names non-empty. **Locks:** none cross-aggregate (inserts a new org + its owner row).
  **SSCAS:** n/a (single new aggregate). **Idempotency:** `p_command_key` (dedupe the apply).
- **Reads:** — . **Writes:** `kernel.organization` (INSERT, status `applied`), `kernel.org_member` (INSERT
  `(org_id, auth.uid(), org_owner)`), `kernel.admin_audit` (`org.create`).
- **Result:** `{ status, org_id }`. **Failure:** `idempotency_replay`. **Forbidden callers:** anon.

### 2.2 `kernel.invite_org_member(p_org_id, p_invitee_ref, p_role, p_command_key)` — **DB-RPC**
- **Purpose:** invite an identity/handle to an org at a scoped role. **Role:** `has_org_role(p_org_id,
  [org_owner, org_admin])`; an `org_admin` **cannot** invite at `org_owner` (tier guard); **no self-invite to
  a higher tier** (I-11).
- **Params:** `p_org_id`,`p_invitee_ref` (email/handle/uid, untrusted),`p_role` (org enum only),`p_command_key`.
  **Server-derived:** `auth.uid()` = `invited_by`; `now()`.
- **Preconditions:** `p_role ∈ org enum`; caller tier ≥ granted tier. **Locks:** the org row (`FOR UPDATE` to
  serialize roster changes). **SSCAS:** n/a (org aggregate only). **Idempotency:** `p_command_key`.
- **Writes:** `kernel.org_invite` (INSERT `pending` — **canonical table, schema §1.3b**; created in migration
  package `072`; the former pending-marker fallback is superseded — addendum A1 CLOSED);
  `kernel.admin_audit` (`org.invite`). **Reads:** `kernel.org_member` (authority).
- **Result:** `{ status, invite_id }`. **Failure:** `insufficient_privilege`, `precondition_failed` (bad
  tier). **Forbidden callers:** org_member/finance; anyone outside the org.

### 2.3 `kernel.accept_org_invite(p_invite_id, p_command_key)` — **DB-RPC**
- **Purpose:** invitee accepts → becomes an `org_member` at the invited role. **Actor:** the **invitee**
  (`auth.uid()` must match the resolved invitee). **Role:** none beyond being the invitee.
- **Params:** `p_invite_id`,`p_command_key` (untrusted). **Server-derived:** `auth.uid()`.
- **Preconditions:** invite exists, pending, not expired, addressed to `auth.uid()`. **Locks:** the invite +
  org roster row (`FOR UPDATE`). **SSCAS:** n/a. **Idempotency:** `p_command_key` + invite terminal state.
- **Writes:** `kernel.org_member` (INSERT/activate role), `kernel.org_invite` (→ accepted), `kernel.admin_audit`
  (`org.invite.accept`). **Result:** `{ status, org_id, role }`. **Failure:** `not_found`, `precondition_failed`
  (expired / wrong invitee). **Forbidden callers:** anyone but the addressed invitee.

### 2.4 `kernel.change_org_role(p_org_id, p_identity_id, p_new_role, p_command_key)` — **DB-RPC**
- **Purpose:** change a member's org role (wraps schema `grant_org_role`/`revoke_org_role` UPDATE path).
  **Role:** `has_org_role(p_org_id, [org_owner, org_admin])`; `org_admin` cannot set/anyone to `org_owner`;
  **no self-promotion** (I-11).
- **Params:** `p_org_id`,`p_identity_id`,`p_new_role`(org enum),`p_command_key` — untrusted. **Server-derived:**
  `auth.uid()`. **Preconditions:** target is a member; **the "≥1 `org_owner`" invariant** — cannot demote the
  last owner. **Locks:** org roster (`FOR UPDATE`), re-count owners under lock. **SSCAS:** n/a.
- **Writes:** `kernel.org_member` (UPDATE role), `kernel.admin_audit` (`org.role.change`). **Result:**
  `{ status }`. **Failure:** `precondition_failed` (last-owner / tier), `insufficient_privilege`. **Forbidden
  callers:** org_member/finance; self-promotion.

### 2.5 `kernel.remove_org_member(p_org_id, p_identity_id, p_command_key)` — **DB-RPC**
- **Purpose:** revoke membership (role-remove via RPC, never a client DELETE — GP-2). **Role:** as §2.4;
  cannot remove the last `org_owner`; cannot remove a higher tier than caller.
- **Params/derived/locks:** as §2.4. **SSCAS:** n/a. **Idempotency:** `p_command_key` (removal is idempotent).
- **Writes:** `kernel.org_member` (role-remove/deactivate), `kernel.admin_audit` (`org.member.remove`).
- **Result:** `{ status }`. **Failure:** `precondition_failed` (last-owner), `insufficient_privilege`.
  **Forbidden callers:** self-removal of the last owner; org_member/finance.

---

## 3. VENUE

### 3.1 `catalog.create_venue(p_org_id, p_name, p_neighborhood, p_address, p_command_key)` — **DB-RPC**
- **Role:** `has_org_role(p_org_id, [org_owner, org_admin])`. **Params:** all **untrusted** except derived
  `auth.uid()`. **Server-derived:** `approval_status:='draft'`.
- **Preconditions:** org `approved`/`active`; `p_neighborhood ∈` frozen check-set. **Locks:** none
  cross-aggregate. **SSCAS:** n/a. **Idempotency:** `p_command_key`.
- **Reads:** `kernel.organization`,`kernel.org_member`. **Writes:** `catalog.venue` (INSERT draft),
  `kernel.admin_audit` (`venue.create`). **Result:** `{ status, venue_id }`. **Forbidden callers:** non-org
  roles; fans.

### 3.2 `catalog.approve_venue(p_venue_id, p_decision, p_reason_code, p_command_key)` — **DB-RPC**
- **Purpose:** platform approves/archives a venue (wraps schema `set_venue_approval`). **Role:**
  `is_platform([platform_admin])`. **Params:** `p_venue_id`,`p_decision(approved|archived|pending)`,
  `p_reason_code` (untrusted). **Server-derived:** `auth.uid()`.
- **Preconditions:** venue exists; legal transition. **Locks:** venue row `FOR UPDATE`. **SSCAS:** n/a.
- **Writes:** `catalog.venue` (UPDATE `approval_status`), `kernel.admin_audit` (`venue.approve`, before/after).
- **Result:** `{ status, approval_status }`. **Forbidden callers:** everyone except `platform_admin` (Miami
  approved-venues gate).

### 3.3 `catalog.update_venue(p_venue_id, p_patch, p_command_key)` — **DB-RPC**
- **Purpose:** edit benign venue profile fields; **operatorship (`org_id`) change is an audited op, not a
  silent overwrite** (CDM §1.2). **Role:** `has_venue_role(p_venue_id, [venue_manager])` OR
  `has_org_role(org_of_venue, [org_owner, org_admin])`.
- **Params:** `p_patch` (name/address/neighborhood/capacity_hint — untrusted); an `org_id` change requires
  `is_platform`/`org_owner` + explicit reason. **Locks:** venue row `FOR UPDATE`. **SSCAS:** n/a.
- **Writes:** `catalog.venue` (UPDATE), `kernel.admin_audit` (`venue.update`; mandatory on operatorship
  change). **Result:** `{ status }`. **Forbidden callers:** door/finance/promoter; fans.

---

## 4. EVENT

### 4.1 `catalog.create_event(p_venue_id, p_title, p_first_session, p_command_key)` — **DB-RPC**
- **Purpose:** create an event and **auto-create its implicit first `event_session`** (A1). **Role:**
  `has_venue_role(p_venue_id, [venue_manager])` OR `has_org_role(org_of_venue, [org_owner, org_admin])`.
- **Params:** `p_title`,`p_first_session` (starts_at/doors_at/label — untrusted). **Server-derived:**
  `org_id` from `catalog.venue.org_id`; `status:='draft'`; session `status:='scheduled'`, `home_region`.
- **Preconditions:** venue `approved`. **Locks:** none cross-aggregate (new event + child session). **SSCAS:**
  n/a. **Idempotency:** `p_command_key`.
- **Reads:** `catalog.venue`. **Writes:** `catalog.event` (INSERT draft), `catalog.event_session` (INSERT
  implicit session), `kernel.admin_audit` (`event.create`). **Result:** `{ status, event_id, session_id }`.
  **Forbidden callers:** non-venue/non-org roles.

### 4.2 `catalog.publish_event(p_event_id, p_target_status, p_command_key)` — **DB-RPC**
- **Purpose:** advance event lifecycle (`draft → announced → on_sale → live → completed`) — wraps schema
  `set_event_status`. **Role:** as §4.1. **Params:** `p_target_status` (untrusted, validated as a legal
  forward transition). **Server-derived:** `auth.uid()`.
- **Preconditions:** legal transition; on-sale requires ≥1 `venue.ticket_type` with a `venue.inventory_batch`
  (no empty on-sale). **Locks:** event row `FOR UPDATE`. **SSCAS:** n/a.
- **Reads:** `catalog.event`,`venue.ticket_type`,`venue.inventory_batch`. **Writes:** `catalog.event`
  (UPDATE `status`), `kernel.admin_audit` (`event.status`). **Result:** `{ status, event_status }`. **Failure:**
  `precondition_failed` (illegal transition / empty inventory). **Forbidden callers:** fans; door/promoter.

### 4.3 `catalog.create_event_session(p_event_id, p_session, p_command_key)` — **DB-RPC**
- **Purpose:** add a further session to a multi-night event (also the primitive `create_event` calls for the
  implicit one). **Role:** as §4.1. **Params:** `p_session` (label/starts_at/ends_at/doors_at — untrusted).
- **Preconditions:** event exists, not `completed`/`cancelled`; `ends_at > starts_at`; label unique per event.
  **Locks:** event row `FOR UPDATE` (serialize session set). **SSCAS:** n/a. **Idempotency:** `p_command_key`
  + `UNIQUE(event_id, session_label)`.
- **Writes:** `catalog.event_session` (INSERT), `kernel.admin_audit` (`session.create`). **Result:**
  `{ status, session_id }`. **Forbidden callers:** fans; door/promoter.

### 4.4 `catalog.cancel_event(p_event_id, p_reason_code, p_command_key)` — **DB-RPC (orchestrates a bounded batch of SSCAS #3)**
- **Purpose:** cancel an event and cascade: cancel sessions, cancel open native listings/auctions/p2p, and
  **void + refund all issued atoms** for the event (event-cancellation cascade = a **bounded batch of SSCAS
  member #3**). **Role:** `has_org_role(org, [org_owner, org_admin])` OR `has_venue_role(venue,
  [venue_manager])` OR `is_platform([platform_admin])`.
- **Params:** `p_event_id`,`p_reason_code`,`p_command_key` — untrusted. **Server-derived:** `auth.uid()`;
  refund `reason_code:='event_cancelled'`.
- **Preconditions:** event not already `cancelled`. **Locks & lock order (SSCAS #3 per atom, batched):**
  **Event/Session** (`FOR UPDATE`) → **Inventory batch(es)** (return capacity) → per issued atom **Ticket
  Atom (ascending `ticket_atom_id`)** → **Refund/Payment**. Open **Listings** are locked before their atoms
  where a listing exists. Iterates atoms in ascending-id order — no inversion.
- **Reads:** `catalog.event`/`event_session`, `kernel.tickets`, `market.listing_native`. **Writes:**
  `catalog.event` (→ `cancelled`), `catalog.event_session` (→ `cancelled`), `market.listing_native`/`auction`/
  `p2p_transfer` (→ `cancelled`/`expired`), then **via `kernel.void_ticket_atom` per atom** (cause
  `refund_void`), `venue.inventory_batch` (sold-- / return), `kernel.refund` (money reversal, EDGE-executes the
  Stripe refund — see §11.4/§13), `kernel.admin_audit` (`event.cancel`).
- **Emitted facts:** ownership-log `cause='refund_void'` (N atoms), `inventory_movement` `void_return`.
- **Result:** `{ status, atoms_voided, refunds_created }`. **Retry:** re-entrant — each atom's void is
  idempotent by `(refund_void, refund_id, atom)`; a re-run skips already-voided atoms. **Failure:**
  `precondition_failed`. **Forbidden callers:** fans; door/promoter/finance-only. **EDGE note:** the actual
  Stripe refunds are executed by the refund edge fn; this RPC records `kernel.refund` intents + voids atoms
  atomically.

---

## 5. TICKET TYPE / INVENTORY

### 5.1 `venue.create_ticket_type(p_event_id, p_kind, p_name, p_price_minor, p_visibility, p_command_key)` — **DB-RPC**
- **Role:** `has_venue_role(venue_of_event, [venue_manager])` OR `has_org_role(org, [org_owner, org_admin])`.
  **Params:** `p_kind(admission|table)`,`p_name`,`p_price_minor`,`p_visibility` — **untrusted; price is
  server-authoritative once stored** (snapshot). **Server-derived:** `currency:='USD'`.
- **Preconditions:** `p_price_minor > 0`; event not `completed`/`cancelled`; `UNIQUE(event_id, name)`. **Locks:**
  none cross-aggregate. **SSCAS:** n/a. **Idempotency:** `p_command_key`.
- **Writes:** `venue.ticket_type` (INSERT), `kernel.admin_audit` (`ticket_type.create`). **Result:**
  `{ status, ticket_type_id }`. **Forbidden callers:** fans; door/promoter.
- **Companion:** `venue.set_ticket_type_price` — same role, **money-consequential → live-table recheck (C9)**,
  never from JWT; writes an audited price change.

### 5.2 `venue.create_inventory_batch(p_ticket_type_id, p_session_id, p_release_kind, p_capacity, p_shard_count, p_command_key)` — **DB-RPC**
- **Purpose:** create the authoritative capacity counter (C27) for a type×session, optionally sharded (C4/C22).
  **Role:** `has_venue_role(venue, [venue_manager])` OR `has_org_role(org, [org_owner, org_admin])`.
- **Params:** `p_release_kind(public_sale|promoter_hold|comp|door|presale)`,`p_capacity`,`p_shard_count`
  (0=unsharded) — untrusted. **Server-derived:** `held:=0`,`sold:=0`,`is_sharded:=(p_shard_count>0)`.
- **Preconditions:** `p_capacity > 0`; type & session belong to the same event. **Locks:** none cross-aggregate.
  **SSCAS:** n/a. **Idempotency:** `p_command_key`.
- **Writes:** `venue.inventory_batch` (INSERT), `venue.inventory_batch_shard` (INSERT N shards summing to
  capacity, when sharded), `kernel.admin_audit` (`inventory.batch.create`). **Result:** `{ status, batch_id }`.
  **Forbidden callers:** fans; door/promoter/finance.

### 5.3 `venue.reserve_primary_inventory(p_batch_id, p_quantity, p_command_key)` — **DB-RPC** *(schema `reserve_inventory`; the buyer-checkout hold)*
- **Purpose:** the **buyer/door hold** — decrement `held` under lock, create a time-boxed
  `venue.inventory_hold` (server-max TTL). **This is the C27 oversell choke-point for holds.** **Actor:**
  `auth.uid()` (fan self-hold) or door/staff-on-behalf via `has_venue_role([venue_door, venue_manager])`.
- **Params:** `p_batch_id`,`p_quantity`,`p_command_key` — **untrusted**. **Server-derived:** `identity_id:=
  auth.uid()` (or the door's on-behalf buyer, server-set); `expires_at := now() + server_max_ttl` (never
  client-set); per-user cap read from `catalog.platform_config`.
- **Preconditions:** batch's session/event `on_sale`/`live`; **per-user active-hold cap (C5) enforced via a
  `user_id` advisory lock or `SERIALIZABLE` — never a `COUNT(*)<limit` trigger**; not door-frozen.
- **Locks & lock order:** **Inventory batch** (`FOR UPDATE`; or ordered shard draw ascending `shard_no`
  `SKIP LOCKED` + single-shard last-unit fallback). **SSCAS:** member-adjacent to #1 but **single aggregate
  (Inventory)** — no cross-aggregate lock. **Idempotency:** `UNIQUE(identity_id, command_idempotency_key)`.
- **Reads:** `venue.inventory_batch(_shard)`, `catalog.platform_config`. **Writes:** `venue.inventory_batch`
  (`held += q`, CHECK `held+sold<=capacity` → `oversell_rejected` on breach), `venue.inventory_batch_shard`,
  `venue.inventory_hold` (INSERT `active`), `venue.inventory_movement` (`hold`, cause-keyed).
- **Result:** `{ status, hold_id, expires_at, remaining }`. **Failure:** `oversell_rejected`,
  `precondition_failed` (cap/frozen), `idempotency_replay`. **Retry:** safe (cause+command keyed).
  **Forbidden callers:** anon; direct counter writes by anyone.

### 5.4 `venue.create_inventory_hold(p_batch_id, p_quantity, p_hold_kind, p_command_key)` — **DB-RPC** *(staff/comp/promoter hold)*
- **Purpose:** a **staff-initiated** hold (comp/promoter/presale) distinct from the buyer checkout hold —
  same counter mechanics, different authority + `release_kind` semantics. **Role:** `has_venue_role([venue_manager])`
  OR `has_org_role([org_owner, org_admin])` (comp is money-adjacent → live-recheck + step-up seam C39).
- **Params/locks/writes:** identical counter path to §5.3 (Inventory single-aggregate, `FOR UPDATE`, CHECK,
  movement `hold`), but `identity_id` is the grantee/holder and TTL/cap policy is the staff variant. **SSCAS:**
  single-aggregate. **Idempotency:** `p_command_key`.
- **Result:** `{ status, hold_id }`. **Forbidden callers:** fans (they use §5.3); door for comp.

### 5.5 `venue.release_inventory_hold(p_hold_id, p_command_key)` — **DB-RPC** *(schema `release_hold`)*
- **Purpose:** release/expire a hold and **return `held`** (idempotent, cause-keyed). **Actor:** the hold's
  owner (`auth.uid() = inventory_hold.identity_id`) OR `has_venue_role([venue_manager, venue_door])` OR the
  **expiry sweep** (definer). **Params:** `p_hold_id`,`p_command_key` — untrusted.
- **Preconditions:** hold `active`. **Locks:** **Inventory batch** (`FOR UPDATE`) then the hold row. **SSCAS:**
  single-aggregate (Inventory). **Idempotency:** hold terminal state + `p_command_key` (double-release no-op).
- **Writes:** `venue.inventory_hold` (→ `released`/`expired`), `venue.inventory_batch(_shard)` (`held -= q`),
  `venue.inventory_movement` (`release`). **Result:** `{ status, remaining }`. **Retry:** safe. **Forbidden
  callers:** a non-owner client for another user's hold.

> **Naming reconciliation:** the schema/RLS canonical names are `venue.reserve_inventory` / `venue.release_hold`;
> the brief's `reserve_primary_inventory` / `create_inventory_hold` / `release_inventory_hold` are the contract
> names above and map 1:1 (buyer-hold / staff-hold / release). Implementers may keep the schema names as the
> physical function names with these as documented aliases.

---

## 6. PRIMARY ORDER

### 6.1 `venue.create_primary_checkout(p_session_id, p_items, p_hold_ids, p_command_key)` — **DB-RPC** *(schema `create_order`)*
- **Purpose:** create a `pending` order + immutable order_items from held inventory, returning the amount to
  charge. **No money moves here** (money-in is Stripe → `public.payments`). **Actor:** `auth.uid()` (fan self)
  or door/staff-on-behalf (`has_venue_role([venue_door, venue_manager])`; buyer id **server-set**, never
  client-trusted).
- **Params:** `p_session_id`,`p_items[]`(ticket_type_id,quantity),`p_hold_ids[]`,`p_command_key` — **untrusted**.
  **Server-derived:** `buyer_id := auth.uid()` (or server-set on-behalf); `org_id` from session→event;
  `unit_price_minor` **snapshotted server-side from `venue.ticket_type`** (server-authoritative pricing);
  `total_minor` server-computed; `source ∈ {app,web,door,promoter_link}` server-tagged.
- **Preconditions:** holds belong to buyer, `active`, cover the items, not expired; session `on_sale`/`live`.
  **Locks & lock order:** **Event/Session** (read-lock for status) → **Inventory holds** (validate) → **Order**
  (insert). **SSCAS:** this is the pre-pay leg of member #1 but writes only the **Order** aggregate + reads
  holds; the inventory→ticket mint happens in §6.3. **Idempotency:** `UNIQUE(buyer_id, command_idempotency_key)`.
- **Reads:** `venue.ticket_type`,`venue.inventory_hold`,`catalog.event_session`. **Writes:** `venue.order`
  (INSERT `pending`), `venue.order_item` (INSERT, IMM-after-issue), optionally `venue.attribution` (in-txn if
  `source='promoter_link'`, AO). **Result:** `{ status, order_id, total_minor, currency }`. **Failure:**
  `precondition_failed` (stale/held-by-other), `idempotency_replay`. **Forbidden callers:** anon; a client
  supplying its own price or buyer_id.

### 6.2 `confirm_primary_payment_server_side(order_id, payment_intent)` — **EDGE-FRONTED** (boundary only)
- **Purpose:** the **Edge Function** that confirms the Stripe PaymentIntent for an order and, on the
  verified/settled webhook, calls the DB-RPC `venue.finalize_primary_order`. **This document does not design
  the edge fn** — flagged for deliverable #5. The DB contract it must honor:
  - money-in is recorded **only** as a `public.payments` row via the existing frozen webhook path
    (`claim_stripe_webhook_event` lease, `verify_jwt=false`) — **never re-implemented** (I-10, SPEC_FOUNDATION
    §2);
  - the buyer principal is **re-verified**: the `public.payments` row's `buyer_id` must equal the order's
    `buyer_id` before issuance (C35);
  - it then invokes `venue.finalize_primary_order` (§6.3) in one DB txn.
- **Forbidden:** the DB never charges; the edge never writes `kernel`/`venue` custody tables except through the
  finalize RPC.

### 6.3 `venue.finalize_primary_order(p_order_id, p_payment_id, p_command_key)` — **DB-RPC (SSCAS member #1)**
- **Purpose:** on a **verified paid** order, atomically draw inventory and **mint N ticket atoms** via the
  kernel engine (primary issuance). **Actor:** `service_role`/definer (called by the confirm edge fn / paid
  webhook). Authority is the **verified payment**, not a client.
- **Params:** `p_order_id`,`p_payment_id`(→`public.payments`),`p_command_key` — **untrusted, all re-validated**.
  **Server-derived:** buyer from the order; `cause:='issue'`, `cause_ref:=order_item.id`/order_id.
- **Preconditions (C35):** `public.payments(p_payment_id).buyer_id = order.buyer_id`, payment `status`
  verified/succeeded, order `pending`. **Locks & lock order (SSCAS #1):** **Event/Session** → **Inventory
  batch(_shard)** (`FOR UPDATE`, `sold += q`, CHECK) → **Order** (`FOR UPDATE`, → `paid`) → **Ticket Atom**
  (mint N, no lock needed on new rows) → **Payment** link. Strictly ascending — no inversion.
- **Reads:** `venue.order`/`order_item`,`public.payments`,`venue.inventory_batch(_shard)`. **Writes (one txn):**
  `venue.inventory_batch(_shard)` (`held -= q; sold += q`), `venue.inventory_movement` (`issue`),
  `venue.order` (→ `paid`), **`kernel.issue_ticket_atoms` (mints N atoms + N ownership-log `issue` rows)**,
  `kernel.payment_native` (link order↔`public.payments`). `venue.order_item` becomes IMM.
- **Emitted facts:** ownership-log `cause='issue'` (N rows, one per atom, `UNIQUE(cause,cause_ref,atom)` —
  **C26 multiplicity**); `inventory_movement` `issue`. **Result:** `{ status, atom_ids[], order_status }`.
- **Retry/idempotency:** re-entrant — replay hits `UNIQUE(buyer_id, command_key)` on the order + the
  ownership-log cause key → returns the original atom set (webhook redelivery safe). **Failure:**
  `payment_unverified`, `oversell_rejected`, `precondition_failed`. **Forbidden callers:** any client directly
  (definer-only); anything trusting a client buyer_id.

---

## 7. TICKET KERNEL (the sole custody writers — §9.4 transfer engine)

> These three are the **single-writer choke-points** into `kernel.tickets` + `kernel.ticket_ownership_log`.
> `lock_ticket`/`unlock_ticket`/`mark_ticket_scanned` mutate atom overlays. **No other code writes custody.**

### 7.1 `kernel.issue_ticket_atoms(p_ctx, p_command_key)` — **DB-RPC (SSCAS #1 mint leg)**
- **Purpose:** mint N atoms for a cause (primary `issue`, `comp`, `door_sale`, `import`) + append N ownership-log
  rows under one `cause_ref`. Called by `finalize_primary_order` / `issue_comp` / door-sale / import. **Actor:**
  `service_role`/definer; `actor_identity := auth.uid()` server-derived (or system sentinel for import/sweep).
- **Params:** `p_ctx` = { session_id, org_id, ticket_type_id, batch_id, owner_id (server-verified),
  quantity, cause(D3), cause_ref, signing_key_id }; `p_command_key` — **untrusted, re-validated**.
- **Preconditions:** cause ∈ {issue, comp, door_sale, import}; batch has capacity (C27); an `active`
  `kernel.signing_key` resolves for the event scope. **Locks & order:** **Inventory batch(_shard)** (`FOR
  UPDATE`) → new **Ticket Atoms**. **SSCAS:** #1. **Idempotency:** ownership-log
  `UNIQUE(cause, cause_ref, ticket_atom_id)` — replay is a no-op per atom; command key on the caller.
- **Writes:** `kernel.tickets` (INSERT N, `state='issued'→'active'`, `credential_version:=0`,
  `signing_key_id`, `current_owner_id:=owner`), `kernel.ticket_ownership_log` (INSERT N, `sequence=1`,
  `from_identity=NULL`, `cause`, `credential_version_after=0`, `state_transition`), `venue.inventory_batch`
  (`sold += N`), `venue.inventory_movement` (`issue`). **No secret written** (C33 — only `signing_key_id`).
- **Emitted facts:** ownership-log `cause` (N rows). **Result:** `{ status, atom_ids[] }`. **Failure:**
  `oversell_rejected`, `precondition_failed`. **Forbidden callers:** any client directly; anything writing
  `kernel.tickets` outside this fn.

### 7.2 `kernel.transfer_ticket_ownership(p_atom_id, p_to_identity, p_cause, p_cause_ref, p_payment_id, p_command_key)` — **DB-RPC (SSCAS #2; the transfer engine)**
- **Purpose:** the **sole custody-move engine** (§9.4). In one txn: validate transition, append ownership-log,
  update head, **bump `credential_version` (+1)** so old credentials fail closed. Serves native `market_sale`,
  `auction_sale`, `p2p_transfer`, `admin_action`. **Actor:** `service_role`/definer, invoked by
  `market.*`/`venue.*` accept/checkout in the **same txn** (C8); `actor_identity := auth.uid()` server-derived.
- **Params:** `p_atom_id`,`p_to_identity`,`p_cause(D3)`,`p_cause_ref`(sale_id/transfer_id),`p_payment_id`
  (nullable, native sale),`p_command_key` — **all untrusted, re-validated under lock.**
- **Preconditions (C35, live-recheck):** for `market_sale` — the referenced `public.payments(p_payment_id)`
  **belongs to the buyer** (`p_to_identity`) and the `market.listing_native` is `active`; **the client-passed
  buyer is NOT trusted**. Atom must be transferable: `state='active'`, `resale_state ∈ {listed, locked}` for
  the sanctioned path, not door-frozen (recon #3), not terminal.
- **Locks & lock order (SSCAS #2):** **Listing** (`FOR UPDATE`) → **Ticket Atom** (`FOR UPDATE` by
  `ticket_atom_id`) → **Payment** link. Ascending — no inversion. Multi-atom passes lock atoms ascending id.
- **Reads:** `kernel.tickets`,`market.listing_native`,`public.payments`,`kernel.signing_key`. **Writes (one
  txn):** `kernel.ticket_ownership_log` (INSERT `cause`, `credential_version_after = old+1`), `kernel.tickets`
  (`current_owner_id := p_to_identity`, `credential_version += 1`, `resale_state := 'none'`,
  `signing_key_id` re-pinned), `kernel.payment_native` (link, native sale), and the **market layer already
  wrote `market.market_sale`** before calling this (C8; this fn sets `terminal_state`).
- **Idempotency / C26:** the ownership-log `UNIQUE(cause, cause_ref, ticket_atom_id)` makes a **double-transfer
  of the same atom under the same sale physically impossible** (second insert conflicts → no-op). The atom
  `FOR UPDATE` + single-writer serialize concurrent attempts. **Compensate-XOR-complete** is enforced on
  `market.market_sale.terminal_state` (a `completed` sale cannot later be `compensated` and vice-versa).
- **Emitted facts:** ownership-log `cause` (1 per atom); credential bump (invalidates old QR — the delivery is
  the credential). **Result:** `{ status, atom_id, new_owner, credential_version }`. **Failure:**
  `payment_unverified`, `conflict_locked`, `precondition_failed`, `frozen`. **EDGE note:** the **new**
  credential token is minted by the `credential-sign` edge fn (KMS) keyed on the bumped `credential_version`
  (C33/recon #4) — **not** by this RPC. **Forbidden callers:** any client directly; the kernel never writes
  `market` tables (the market layer calls in).

### 7.3 `kernel.void_ticket_atom(p_atom_id, p_refund_id, p_command_key)` — **DB-RPC (SSCAS #3 void leg)**
- **Purpose:** move an atom to terminal `voided` with cause `refund_void` (D2 — **no `refunded` terminal**),
  return inventory, in the same txn as the refund. Serves buyer-refund, event-cancel, oversell-correction,
  C25 auto-compensation. **Actor:** `service_role`/definer (refund flows / sweep); or platform via
  `force_void_ticket` (§11.1).
- **Params:** `p_atom_id`,`p_refund_id`(→`kernel.refund`),`p_command_key` — untrusted. **Server-derived:**
  `cause:='refund_void'`, `cause_ref:=refund_id`, `to_identity:=` void-sentinel/issuer.
- **Preconditions:** atom not already terminal (**re-void across two refunds is blocked by the atom's current
  state under the `FOR UPDATE` lock**, not by log uniqueness). **Locks & order (SSCAS #3):** **Ticket Atom**
  (`FOR UPDATE`) → **Inventory batch** (`sold -= 1`, return) → **Refund/Payment**. **SSCAS:** #3.
  **Idempotency:** `UNIQUE(refund_void, refund_id, atom)` → N-atom void under one refund allowed, replay no-op.
- **Writes:** `kernel.ticket_ownership_log` (`refund_void`, `credential_version_after` bumped),
  `kernel.tickets` (→ `voided`, credential bump so any live QR dies), `venue.inventory_batch` (`sold -= 1`),
  `venue.inventory_movement` (`void_return`), `market.market_sale.terminal_state := 'compensated'` when driven
  by C25. **Result:** `{ status, atom_id }`. **Forbidden callers:** any client directly.

### 7.4 `kernel.lock_ticket(p_atom_id, p_reason, p_command_key)` / `kernel.unlock_ticket(p_atom_id, p_command_key)` — **DB-RPC (definer primitives; SSCAS #6/#7 overlays)**
- **Purpose:** set `kernel.tickets.resale_state` `none→listed` (list) / `none→locked` (p2p) and back. **These
  are internal primitives** called *inside* `market.create_listing` (#6) and `market.create_p2p_transfer` (#7)
  and their cancels — they are **not directly client-callable**. **Actor:** definer, `actor := auth.uid()`.
- **Preconditions:** atom `state='active'`, `resale_state='none'` to lock (or the matching set to unlock),
  current owner = the acting seller/sender, **not door-frozen (recon #3)**. **Locks:** **Ticket Atom** (`FOR
  UPDATE`). **SSCAS:** the overlay step of #6/#7 (the enclosing RPC also locks the Listing/Transfer aggregate,
  in order Listing → Ticket Atom). **Idempotency:** overlay is state-guarded (`listed`/`locked` re-set no-op).
- **Writes:** `kernel.tickets` (`resale_state`), and appends **no** ownership-log row (custody unchanged; only
  the overlay). **Result:** `{ status, resale_state }`. **Failure:** `conflict_locked` (already listed/locked
  → prevents double-sell), `frozen`. **Forbidden callers:** clients directly; scan/transfer of a
  `listed`/`locked` atom outside its sanctioned path.

### 7.5 `kernel.mark_ticket_scanned(p_atom_id, p_session_id, p_scan_ctx)` — **DB-RPC (called by `record_scan`)**
- **Purpose:** the custody-side terminal transition `active → scanned` (single admit, C41 MVP), invoked by
  `venue.record_scan` under the atom lock. **Actor:** door principal (`venue_door`/valid `door_pin`) or
  `venue_manager`, resolved by `record_scan`. **Params:** trusted `p_atom_id`/`p_session_id` (from the scan
  RPC), `p_scan_ctx` server-derived.
- **Preconditions:** atom `state='active'`, `resale_state='none'` (**a `listed`/`locked` atom cannot be
  scanned — "delist first"**), belongs to `p_session_id`, credential_version current (online verify, C37).
  **Locks:** **Ticket Atom** (`FOR UPDATE`). **SSCAS:** single-aggregate (atom) + the scan ledger write in
  `record_scan` (§9). **Idempotency:** the scan partial-unique enforces first-in-wins (a second `in` → the
  scan RPC records `duplicate`; the atom stays `scanned`).
- **Writes:** `kernel.tickets` (→ `scanned`) + an ownership-log entry is **not** appended (scan is not a
  custody change; the state move is recorded on the atom and the scan ledger). **Result:** `{ status,
  atom_state }`. **Forbidden callers:** clients directly; any scan of a listed/locked/terminal atom.

---

## 8. P2P (native send-to-friend; distinct from `public.transfers`)

### 8.1 `market.create_p2p_transfer(p_atom_id, p_to_ref, p_price_minor, p_command_key)` — **DB-RPC (SSCAS #7 start)**
- **Purpose:** open a native transfer (gift or policy-capped send), **locking the atom** (`resale_state:=
  locked`). **Actor:** `auth.uid()` must be the atom's **current owner**. **Params:** `p_atom_id`,`p_to_ref`
  (handle/phone/uid, untrusted),`p_price_minor`(nullable=gift),`p_command_key` — untrusted.
- **Preconditions:** owner-only; atom `active`,`resale_state='none'`, not door-frozen (recon #3); price within
  policy cap (`catalog.resale_policy` snapshot). **Locks & order (SSCAS #7):** **Ticket Atom** (`FOR UPDATE`)
  → **Transfer** (insert). **SSCAS:** #7. **Idempotency:** partial `UNIQUE(ticket_atom_id) WHERE
  status='initiated'` + `UNIQUE(from_identity, command_key)`.
- **Writes:** `market.p2p_transfer` (INSERT `initiated`, `expires_at := now()+TTL`), **`kernel.lock_ticket`**
  (`resale_state:=locked`). **Result:** `{ status, transfer_id, expires_at }`. **Failure:** `conflict_locked`
  (already listed/locked → blocks double-sell), `policy_violation`, `frozen`. **Forbidden callers:** non-owner.

### 8.2 `market.accept_p2p_transfer(p_transfer_id, p_command_key)` — **DB-RPC (SSCAS #8 accept → custody move)**
- **Purpose:** recipient accepts → **custody moves via the kernel engine** (`cause='p2p_transfer'`),
  credential bumps. **Actor:** the resolved recipient (`auth.uid() = to_identity`, or resolves `to_handle`).
- **Params:** `p_transfer_id`,`p_command_key` — untrusted. **Preconditions:** transfer `initiated`, not
  expired, addressed to `auth.uid()`; a priced send requires a **verified `public.payments`** row for the
  recipient (C35 re-check — money-in stays on the frozen path). **Locks & order:** **Transfer** (`FOR UPDATE`)
  → **Ticket Atom** (`FOR UPDATE`) → **Payment** (priced). **SSCAS:** #8.
- **Writes:** `market.p2p_transfer` (→ `accepted`/`completed`), **`kernel.transfer_ticket_ownership`**
  (`cause='p2p_transfer'`, cause_ref=transfer_id: ownership-log append + head + credential bump + `resale_state
  :=none`), `kernel.payment_native` (priced). **Idempotency:** `UNIQUE(p2p_transfer, transfer_id, atom)` +
  command key. **Result:** `{ status, atom_id, credential_version }`. **Failure:** `precondition_failed`
  (expired), `payment_unverified`. **Forbidden callers:** anyone but the addressed recipient.

### 8.3 `market.cancel_p2p_transfer(p_transfer_id, p_reason_code, p_command_key)` — **DB-RPC (owns the `expired` transition)**
- **Purpose:** sender cancels, or the **sweep** expires, an open transfer → **unlock the atom**. Folds
  `failed → cancelled` with a `reason_code`; **`expired` is a first-class state** driven by the TTL sweep
  (recon #1). **Actor:** the sender (`from_identity`), OR the expiry sweep (definer for `expired`).
- **Params:** `p_transfer_id`,`p_reason_code`,`p_command_key` — untrusted. **Preconditions:** transfer
  `initiated`. **Locks & order:** **Transfer** (`FOR UPDATE`) → **Ticket Atom** (`FOR UPDATE`, unlock).
  **SSCAS:** the unlock overlay (member #7 reverse). **Idempotency:** transfer terminal state + command key.
- **Writes:** `market.p2p_transfer` (→ `cancelled`/`expired`, `reason_code`), **`kernel.unlock_ticket`**
  (`resale_state:=none`). **Result:** `{ status, final_state }`. **Retry:** safe. **Forbidden callers:** the
  recipient (they accept/decline); non-parties.

> **P2P expiry sweep** — see §12.2 (`market.sweep_expired_p2p_transfers`), a definer batch that calls
> `cancel_p2p_transfer` with the `expired` transition for TTL-lapsed rows.

---

## 9. DOOR

### 9.1 `venue.create_door_pin(p_venue_id, p_session_id, p_label, p_pin_plain, p_expires_at, p_command_key)` — **DB-RPC** *(schema `issue_door_pin`)*
- **Purpose:** mint a loginless, session-scoped, expiring device principal. **Role:** `has_venue_role(p_venue_id,
  [venue_manager])` OR `has_org_role(org, [org_owner, org_admin])`. **Params:** `p_pin_plain` (**untrusted;
  hashed server-side, never stored plaintext**), `p_expires_at`,`p_label`,`p_command_key`.
- **Server-derived:** `pin_hash := hash(p_pin_plain)`; `status:='active'`. **Preconditions:** session belongs
  to the venue; `p_expires_at > now()`. **Locks:** none cross-aggregate. **SSCAS:** n/a. **Idempotency:**
  `p_command_key`.
- **Writes:** `venue.door_pin` (INSERT, `pin_hash` only), `kernel.admin_audit` (`door_pin.issue`). **Result:**
  `{ status, pin_id }` (**never returns the hash**). **Security:** `pin_hash` stripped from every client GRANT;
  constant-time compare only inside the door-auth path (I-9). **Forbidden callers:** door/finance/promoter; fans.

### 9.2 `venue.revoke_door_pin(p_pin_id, p_command_key)` — **DB-RPC**
- **Role:** as §9.1. **Locks:** pin row `FOR UPDATE`. **SSCAS:** n/a. **Writes:** `venue.door_pin` (→
  `revoked`), `kernel.admin_audit` (`door_pin.revoke`). **Result:** `{ status }`. **Idempotency:** terminal
  state. **Forbidden callers:** as §9.1.

### 9.3 `venue.validate_ticket_online(p_atom_id_or_credential, p_session_id)` — **DB-RPC (read; C37 live verify)**
- **Purpose:** the **online per-scan live verify** — returns whether an atom is admittable **without**
  recording admission (the door UI pre-check; `record_scan` does the authoritative admit). **Actor:** door
  principal (`venue_door`/valid `door_pin`) or `venue_manager` for the session.
- **Params:** `p_atom_id_or_credential`,`p_session_id` — untrusted. **Reads:** `kernel.tickets`
  (`state`,`resale_state`,`credential_version`,`current_owner_id`), `kernel.signing_key.public_key`,
  `venue.scan` (prior admit). **Writes:** none. **SSCAS:** n/a.
- **Result:** `{ admittable(bool), reason(active|already_scanned|listed_locked|voided|wrong_session|
  version_stale), credential_version }`. **Security:** signature verification of the presented token uses the
  **public key** (door-side / edge); the **private key is never in the DB** (C33). Online doors do a live
  per-scan verify (C37); offline doors verify against the cached manifest (±2 time-bucket skew). **Forbidden
  callers:** non-door clients.

### 9.4 `venue.record_scan(p_atom_id, p_session_id, p_scan_meta, p_command_key)` — **DB-RPC (AO; authoritative admit)**
- **Purpose:** record an admission attempt (AO ledger) and, on first valid `in`, move the atom to `scanned`
  via `kernel.mark_ticket_scanned`. **Actor:** door principal (`venue_door`/valid `door_pin`) or
  `venue_manager`. **Params:** `p_scan_meta` (device_id, direction default `in`, scan_type, device_boot_id,
  scan_sequence, occurred_at) — untrusted; `p_command_key`.
- **Preconditions:** session `live`; atom belongs to session; not `listed`/`locked`/terminal. **Locks & order:**
  **Ticket Atom** (`FOR UPDATE`) → scan ledger insert. **SSCAS:** atom + scan (custody-adjacent, single custody
  aggregate). **Idempotency:** partial `UNIQUE(ticket_atom_id, event_session_id) WHERE result='admitted' AND
  direction='in'` → **first-in-wins**; a second `in` is inserted as `result='duplicate'` (not an error).
- **Writes:** `venue.scan` (INSERT `admitted|duplicate|invalid|frozen|fraud_review`), `kernel.tickets` (→
  `scanned` via `mark_ticket_scanned`, first admit only). **Result:** `{ result, admitted(bool), atom_state }`.
  **Retry:** safe (duplicate recorded, not doubled). **Forbidden callers:** non-door clients; fans.

### 9.5 `venue.reconcile_offline_scans(p_device_id, p_batch, p_command_key)` — **DB-RPC (offline reconciliation, C23)**
- **Purpose:** ingest a device's queued offline scans, ordering by `(server_receipt_at, then device_boot_id +
  scan_sequence)` to resolve first-admit-wins across devices; flag conflicts. **Actor:** `venue_door`
  (own device) / `venue_manager`. **Params:** `p_batch[]` (offline scan rows, untrusted),`p_command_key`.
- **Preconditions:** device belongs to venue; manifest window valid. **Locks & order:** per atom **Ticket
  Atom** (ascending `ticket_atom_id`) `FOR UPDATE`, then scan inserts. **SSCAS:** batched atom + scan.
  **Idempotency:** the scan `UNIQUE(cause,cause_ref,batch,kind)`-style + partial-unique dedupe; replay of a
  device batch is a no-op.
- **Writes:** `venue.scan` (INSERT each attempt, `offline_pending:=false` after reconcile), `kernel.tickets`
  (first-admit-wins → `scanned`), `venue.scan_device` (`last_sync_at`,`manifest_version`). **Result:**
  `{ status, admitted, duplicates, conflicts }`. **Retry:** re-entrant. **Forbidden callers:** non-door.

---

## 10. SETTLEMENT

### 10.1 `venue.open_settlement(p_org_id, p_venue_id, p_event_id, p_period, p_command_key)` — **DB-RPC**
- **Role:** `has_venue_role([venue_finance])` OR `has_org_role([org_finance, org_owner])`. **Purpose:** open a
  settlement header. **Locks:** none cross-aggregate. **SSCAS:** n/a. **Writes:** `venue.settlement` (INSERT
  `open`), `kernel.admin_audit` (`settlement.open`). **Result:** `{ status, settlement_id }`. **Idempotency:**
  `p_command_key`. **Forbidden callers:** non-finance.

### 10.2 `kernel.close_settlement(p_settlement_id, p_command_key)` — **DB-RPC (SSCAS #4; + member #5 commission)**
- **Purpose:** roll up immutable settlement lines and **generate the payout** (never touches ticket history).
  Includes promoter commission (member #5) as a payout line. **Role:** `has_venue_role([venue_finance])` OR
  `has_org_role([org_finance])` OR `is_platform`.
- **Params:** `p_settlement_id`,`p_command_key` — untrusted. **Server-derived:** fee/royalty split from
  `catalog.platform_config`/`resale_policy` snapshots; **rounding residual assigned to the named
  `settlement_line.is_rounding_bearer`** (C31). **Preconditions:** settlement `open`.
- **Locks & order (SSCAS #4):** **Settlement** (`FOR UPDATE`) → **Payout**. Attribution→commission reads
  `venue.attribution`. **SSCAS:** #4 (+#5). **Idempotency:** `kernel.payout.idempotency_key` deterministic on
  `(cause, cause_ref, payee)` (Phase-0 discipline) → replay recovers the same payout.
- **Reads:** `venue.settlement(_line)`,`venue.attribution`,`market.market_sale`(royalty). **Writes:**
  `venue.settlement_line` (AO, incl. rounding bearer), `venue.settlement` (→ `closed`), `kernel.payout`
  (INSERT `pending`, cause `settlement` + `promoter_commission`), `kernel.admin_audit` (`settlement.close`).
- **Emitted facts:** payout cause `settlement`/`promoter_commission`. **Result:** `{ status, payout_ids[],
  net_minor }`. **EDGE note:** the actual Stripe Connect transfer is executed by the payout edge fn / existing
  `record_transfer_payout`-style pipeline (§13) — this RPC only records the payout intent. **Forbidden
  callers:** non-finance; anything touching ticket history from settlement.

### 10.3 `kernel.request_org_payout(p_org_id, p_settlement_id, p_command_key)` — **EDGE-FRONTED (DB-RPC records intent)**
- **Purpose:** org finance requests disbursement of a closed settlement's payout to the org's Stripe Connect
  destination. **DB-RPC side** records/advances `kernel.payout` `pending → submitted` and enforces the
  payout-destination cool-down (`payout_destination_locked_until`); **the edge fn executes the Stripe transfer**
  (reuses the frozen `source_transaction` funding + deterministic idempotency, SPEC_FOUNDATION §2).
- **Role:** `has_org_role([org_finance, org_owner])`. **Params:** `p_org_id`,`p_settlement_id`,`p_command_key`.
  **Preconditions:** settlement `closed`, payout `pending`, destination not locked. **Locks & order:**
  **Settlement** → **Payout** (`FOR UPDATE`). **SSCAS:** member #4 continuation (Settlement→Payout).
  **Idempotency:** payout `idempotency_key`.
- **Writes:** `kernel.payout` (→ `submitted`, `stripe_transfer_ref` set by the edge callback),
  `kernel.admin_audit` (`payout.request`). **Result:** `{ status, payout_id }`. **Failure:**
  `precondition_failed` (destination locked / not closed). **Forbidden callers:** non-finance; the DB never
  moves money itself.

---

## 11. ADMIN

### 11.1 `kernel.force_void_ticket(p_atom_id, p_reason_code, p_command_key)` — **DB-RPC**
- **Purpose:** platform/dispute void of an atom (fraud/oversell/admin) → wraps `void_ticket_atom` +
  (optionally) a `kernel.refund`. **Role:** `is_platform([platform_admin, platform_risk])`; **dual-control
  seam** for high-impact voids (C11). **Params:** `p_atom_id`,`p_reason_code`,`p_command_key` — untrusted.
- **Preconditions:** atom not already terminal. **Locks & order (SSCAS #3):** **Ticket Atom** → **Inventory**
  → **Refund/Payment**. **SSCAS:** #3. **Idempotency:** `UNIQUE(refund_void, refund_id, atom)`.
- **Writes:** `kernel.refund` (if money reversal), **`kernel.void_ticket_atom`**, `kernel.admin_audit`
  (`ticket.force_void`, before/after). **Result:** `{ status, atom_id }`. **Forbidden callers:** everyone
  except platform_admin/risk.

### 11.2 `kernel.hold_payout(p_payout_id, p_reason_code, p_command_key)` — **DB-RPC**
- **Purpose:** freeze a pending payout (risk/dispute) — extends the frozen `apply_payout_hold` discipline onto
  `kernel.payout`. **Role:** `is_platform([platform_risk, platform_admin])`. **Preconditions:** payout
  `pending`/`submitted`. **Locks:** payout row `FOR UPDATE`. **SSCAS:** single-aggregate (Payout).
- **Writes:** `kernel.payout` (→ `held`-equivalent status), `kernel.admin_audit` (`payout.hold`). **Result:**
  `{ status }`. **Idempotency:** terminal/held state + command key. **Forbidden callers:** non-platform-risk.

### 11.3 `kernel.release_payout(p_payout_id, p_command_key)` — **EDGE-FRONTED (DB-RPC advances state)**
- **Purpose:** release a held payout → resume disbursement (extends `admin_release_held_payout`). **Role:**
  `is_platform([platform_risk, platform_admin])`; dual-control seam. **DB-RPC** advances `kernel.payout` state
  and writes audit; the **edge fn re-submits the Stripe transfer**. **Locks:** payout `FOR UPDATE`. **SSCAS:**
  Payout single-aggregate. **Writes:** `kernel.payout` (→ `pending`/`submitted`), `kernel.admin_audit`
  (`payout.release`). **Result:** `{ status }`. **Forbidden callers:** non-platform-risk.

### 11.4 `kernel.refund_primary_order(p_order_id, p_amount_minor, p_reason_code, p_command_key)` — **EDGE-FRONTED (DB-RPC + Stripe refund)**
- **Purpose:** refund a primary order (full/partial) and **void the covered atoms** (SSCAS #3). The **Stripe
  refund is executed by the refund edge fn**; the DB-RPC records `kernel.refund` and voids atoms atomically.
  **Role:** owner (buyer-request, capped by policy) · `has_org_role([org_finance])` · `is_platform([
  platform_support (capped), platform_admin])`. (`admin_refund` for pure dispute is the platform-risk variant.)
- **Params:** `p_order_id`,`p_amount_minor`,`p_reason_code(buyer_request|event_cancelled|oversell_correction|
  dispute|admin_action|auto_compensation)`,`p_command_key` — untrusted; **amount re-validated** (`sum(refunds)
  ≤ payment.total` under `FOR UPDATE` on the payment).
- **Preconditions:** order `paid`/`partially_refunded`; buyer-request within window/cap. **Locks & order
  (SSCAS #3):** **Order** → **Ticket Atom(s)** (ascending id) → **Inventory** → **Refund/Payment** (`FOR
  UPDATE` on `public.payments` for the sum guard). **SSCAS:** #3. **Idempotency:** `kernel.refund.idempotency_key`.
- **Reads:** `venue.order`,`public.payments`,`kernel.payment_native`. **Writes:** `kernel.refund` (INSERT,
  `reason_code`), **`kernel.void_ticket_atom` per covered atom** (cause `refund_void`), `venue.order` (→
  `partially_refunded`/`refunded`), `venue.inventory_batch` (return), `kernel.admin_audit` (`refund.issue`).
- **Emitted facts:** ownership-log `refund_void` (N atoms), inventory `void_return`. **Result:** `{ status,
  refund_id, atoms_voided }`. **Retry:** re-entrant (idempotency_key + cause key). **Failure:**
  `precondition_failed` (over-refund / window), `insufficient_privilege`. **Forbidden callers:** a buyer
  refunding beyond policy cap; anyone refunding another buyer's order.

> **`kernel.admin_refund`** (platform_risk/admin dispute refund) is the same DB shape as §11.4 with
> `reason_code='dispute'`/`admin_action` and platform authority; listed here as a sibling, not re-detailed.

---

## 12. RECONCILIATION-TARGET READS & SWEEPS (recon #1–#5) + C25

### 12.1 `market.get_market_sale_status` (§1.4) — recon #2. `market.get_ticket_history` (§1.2) — recon #5. Door-freeze read — recon #3 (see §12.4). Credential offline contract — recon #4 (edge, see §13).

### 12.2 `market.sweep_expired_p2p_transfers()` — **DB-RPC (definer batch; recon #1)**
- **Purpose:** TTL sweep that transitions `initiated` p2p transfers past `expires_at` to **`expired`** and
  **unlocks the atom**. **Actor:** `service_role`/system sentinel (cron/heartbeat). **Params:** none (or a
  batch bound). **Preconditions:** `status='initiated' AND expires_at < now()`. **Locks & order:** per row
  **Transfer** → **Ticket Atom** (`FOR UPDATE`, ascending). **SSCAS:** member #7 reverse (unlock).
- **Writes:** calls `market.cancel_p2p_transfer(..., reason='expired')` per row → `market.p2p_transfer` (→
  `expired`), `kernel.unlock_ticket`. **Result:** `{ swept_count }`. **Retry:** idempotent/re-entrant (only
  acts on still-`initiated` rows). **Forbidden callers:** clients (definer-only).

### 12.3 `market.sweep_paid_pending_sales()` — **DB-RPC (definer batch; C25 auto-compensation)**
- **Purpose:** the C25 sweep that finalizes `market.market_sale` rows stuck in
  `sale_state='paid_pending_transfer'` past the **bounded dwell SLO**: either complete the transfer (if the
  payment is verified and the atom is still transferable) or **auto-compensate** (refund-void → `terminal_state
  ='compensated'`), driving the RN "Finalizing…" flip (recon #2). **Actor:** `service_role`/system sentinel.
- **Preconditions:** `sale_state='paid_pending_transfer' AND paid_pending_since < now() - dwell_slo`. **Locks
  & order:** **Listing** → **Ticket Atom** → **Payment** (complete branch) OR **Ticket Atom** → **Refund**
  (compensate branch). **SSCAS:** member #2 (complete) XOR member #9 (`paid_pending_transfer` compensation).
- **Writes (XOR):** complete → `kernel.transfer_ticket_ownership` (`market_sale`, `terminal_state:=completed`);
  compensate → `kernel.void_ticket_atom` + `kernel.refund` (`terminal_state:=compensated`). **Compensate-XOR-
  complete** guaranteed by the `market_sale` terminal state machine under its row lock (C26). **Result:**
  `{ completed, compensated }`. **Retry:** re-entrant. **Forbidden callers:** clients. **SLO:** the dwell bound
  is named in the Edge/ops spec; the sweep raises a max-age alarm (Invariant 3 A6).

### 12.4 Door-freeze signal (recon #3) — read + recheck contract — **ADDENDUM A2/A3 CLOSED**
- **Canonical form (RECONCILED — schema §2.3):** the stored signal is **`catalog.event_session.door_open_at`**
  (set when the session's offline door manifest opens); the ONLY authorization read is the derived helper
  **`kernel.is_transfer_frozen(p_ticket_atom_id)`** — true iff the atom's session has
  `door_open_at IS NOT NULL AND now() >= door_open_at`, narrowed **per-open-manifest-ticket, not blanket
  per-session** (C43). There is **no stored `kernel.tickets.transfer_frozen` column** — the earlier derived-
  column assumption is superseded; edge, client, and RPC all target the same helper.
- **Enforcement:** `market.create_listing`, `market.create_p2p_transfer`, `kernel.lock_ticket`, and
  `kernel.mark_ticket_scanned` **re-check `kernel.is_transfer_frozen` under the atom lock** (live-table
  recheck, not a client flag) and reject with `frozen`. The RN client reads the same helper (owner-scoped
  boolean) to disable Transfer/Sell; the edge layer never independently decides freeze.

---

## 13. EDGE-FRONTED functions (flagged for deliverable #5 — NOT designed here)

External I/O (Stripe / KMS / push) lives in Edge Functions; the DB-RPC does only the atomic state transition.
The Edge spec must design these; this doc fixes the DB boundary each wraps:

| Edge function (name TBD in #5) | Wraps DB-RPC | External side-effect | DB boundary invariant |
|---|---|---|---|
| `confirm_primary_payment_server_side` (§6.2) | `venue.finalize_primary_order` | Stripe PaymentIntent confirm; consumes verified webhook | money-in only via `public.payments` frozen path; buyer re-verified (C35) |
| `credential-sign` (C33, recon #4) | reads `kernel.tickets.credential_version` + `kernel.signing_key.public_key`; KMS signs | KMS sign; returns cacheable token + `credential_version`, TTL | **private key never in DB**; a transfer bump invalidates the cached token; online doors live-verify (C37) |
| refund executor | `kernel.refund_primary_order`/`admin_refund`/`cancel_event` | Stripe refund | DB records `kernel.refund` intent + voids atoms; edge executes charge reversal |
| payout executor | `kernel.close_settlement`/`request_org_payout`/`release_payout` | Stripe Connect transfer | reuses `source_transaction` funding + deterministic idempotency; DB records `kernel.payout` |
| signing-key provisioning | `kernel.provision/rotate/revoke_signing_key` | KMS keygen/rotate | DB stores `public_key`+`kms_handle_ref` only (no secret) |

`kernel.provision_signing_key` / `rotate_signing_key` / `revoke_signing_key` are **DB-RPCs** (`is_platform([
platform_admin])`, audited, active-key partial-unique per scope) whose KMS side is the edge provisioning path.

---

## 14. SSCAS ENFORCEMENT (critical) — member → RPC map + lock-order proof

### 14.1 SSCAS member → RPC(s)
| # | SSCAS member (SPEC_FOUNDATION §5) | RPC(s) | Aggregate classes locked, in global order |
|---|---|---|---|
| 1 | Primary issuance | `venue.finalize_primary_order` → `kernel.issue_ticket_atoms` | Event/Session → **Inventory(batch,shard asc)** → **Order** → **Ticket Atom(new)** → **Payment**(link) |
| 2 | Native sale / resale | `kernel.transfer_ticket_ownership` (called by market checkout / `respond_offer` accept / auction finalize) | **Listing** → **Ticket Atom(asc id)** → **Payment**(link) |
| 3 | Refund-void | `kernel.void_ticket_atom`, `kernel.refund_primary_order`, `kernel.force_void_ticket`, `catalog.cancel_event`(batch) | **Order**(if order-scoped) → **Ticket Atom(asc id)** → **Inventory** → **Refund/Payment** |
| 4 | Settlement → payout | `kernel.close_settlement`, `kernel.request_org_payout` | **Settlement** → **Payout** |
| 5 | Attribution → commission | `kernel.close_settlement` (commission line) | (Attribution read) → **Settlement** → **Payout** |
| 6 | Native listing create | `market.create_listing` → `kernel.lock_ticket` | **Listing** → **Ticket Atom** |
| 7 | P2P start | `market.create_p2p_transfer` → `kernel.lock_ticket` | **Transfer(Listing slot)** → **Ticket Atom** |
| 8 | P2P accept | `market.accept_p2p_transfer` → `kernel.transfer_ticket_ownership` | **Transfer** → **Ticket Atom** → **Payment** |
| 9 | `paid_pending_transfer` auto-compensation (C25) | `market.sweep_paid_pending_sales` | **Listing** → **Ticket Atom** → **Payment**(complete) XOR **Ticket Atom** → **Refund**(compensate) |
| +3b | Event-cancellation cascade (bounded batch of #3) | `catalog.cancel_event` | **Event/Session** → **Inventory** → per **Ticket Atom(asc id)** → **Refund** |
| +2b | Auction-close deposit release (variant of #2) | auction finalize sweep → `kernel.transfer_ticket_ownership` | **Listing/Auction** → **Ticket Atom** → **Payment** |

### 14.2 Lock-order proof (no illegal inversion exists)
The global order is a **total order** on aggregate classes: `Event/Session(1) < Inventory(2) < Order(3) <
Listing(4) < Ticket Atom(5) < Payment/Payout/Reserve/Settlement(6)`; within a class, rows are locked by
ascending id (shards ascending `shard_no`; atoms ascending `ticket_atom_id`). Each member above acquires a
**strictly increasing subsequence** of this order:
- #1: 2 → 3 → 5 → 6 (Event/Session read-gate at 1). Ascending. ✔
- #2: 4 → 5 → 6. Ascending. ✔  (Settlement class 6 shares rank with Payment; a sale never also locks a payout,
  so no same-rank cycle.)
- #3 / #3b: (3) → 5 → 2? — **NB:** refund-void returns **Inventory (class 2)** *after* touching the atom
  (class 5). To avoid a 5→2 back-edge, the void path acquires **Inventory before the Atom** where both are
  locked in one txn (cancel_event locks Inventory at rank 2 first, then atoms at rank 5), and the single-atom
  `void_ticket_atom` treats the inventory return as a **counter update under its own `FOR UPDATE` taken before
  the atom mutation completes** — i.e. the acquisition sequence is Inventory(2) → Atom(5) → Refund(6),
  ascending. **This is the one place to watch; the contract pins Inventory-before-Atom in every void path so
  no 5→2 inversion is possible.** ✔ *(Implementation note, not a new decision.)*
- #4/#5: 6 → 6 (Settlement then Payout, both rank 6) — ordered by a fixed sub-rank Settlement-before-Payout;
  no cycle. ✔
- #6: 4 → 5. #7: 4(Transfer occupies the Listing slot) → 5. #8: 4 → 5 → 6. #9: 4 → 5 → 6. All ascending. ✔
- Cross-member deadlock-freedom: because **every** member acquires locks in the same global ascending order,
  two concurrent members can never hold-and-wait in a cycle (Coffman condition #4 broken by construction) —
  the standard resource-ordering proof.

### 14.3 Assertion (mandated)
**No unnamed synchronous cross-aggregate transaction exists in this contract set.** Every RPC that writes more
than one aggregate class is mapped above to exactly one SSCAS member (or an enumerated variant #2b/#3b). Every
other RPC is **single-aggregate** (explicitly tagged `SSCAS: n/a`): the organization RPCs (org only), venue/
event/session/ticket_type/batch creation (one aggregate each), holds (Inventory only), door_pin/scan_device/
settlement-open (one aggregate), the read RPCs (no writes), `lock/unlock_ticket` and `mark_ticket_scanned`
(Ticket-Atom overlay only), `hold_payout` (Payout only). The market layer writing `market.market_sale` **then**
calling the kernel engine **in the same txn** is member #2 (C8) — not a second, unnamed transaction: the kernel
never writes `market`, the market never writes custody, so there is exactly one cross-aggregate txn per sale.

---

## 15. GATE-P DECISIONS RENDERED IN THESE CONTRACTS

- **C26** — `issue_ticket_atoms` mints N atoms under one `cause_ref` (§7.1); `refund_primary_order`/
  `void_ticket_atom` void N under one refund (§7.3/§11.4); replay is a no-op via `UNIQUE(cause, cause_ref,
  ticket_atom_id)` (§0.2, §7.2 idempotency); `transfer_ticket_ownership` + `market_sale` are
  **compensate-XOR-complete** via the sale terminal state machine (§7.2, §12.3).
- **C27** — `reserve_primary_inventory`/`issue_ticket_atoms` take `FOR UPDATE` on the inventory counter and
  enforce `held+sold ≤ capacity` (remaining ≥ 0) → `oversell_rejected` (§5.3, §7.1); sharded draw ascending
  `shard_no` + single-shard fallback.
- **C33** — no RPC handles private keys; `credential-sign` (edge) signs via KMS; every custody RPC **bumps
  `credential_version`** (§7.2/§7.3) and re-pins `signing_key_id`; DB stores only `public_key`+`kms_handle_ref`
  (§13).
- **C35** — buyer principal re-verified against `public.payments` in `transfer_ticket_ownership` /
  `finalize_primary_order` / `accept_p2p_transfer`; **client buyer_id never trusted** (§6.3, §7.2, §8.2);
  actor is always `auth.uid()`.
- **C36** — every role check is `has_org_role`/`has_venue_role`/`has_event_role`/`is_platform`, scope-qualified
  and disjoint-labeled (§0.1, §1.1, and every RPC's Role line); no bare string compare.

---

## 16. RECONCILIATION — contracts not fully closeable from inputs (flagged)

1. **CLOSED (addendum A1).** `kernel.org_invite` is now canonical in the physical schema (§1.3b) and created by
   migration package `072`; §2.2/§2.3 reference it directly. The pending-marker fallback is superseded.
2. **CLOSED (addenda A2/A3).** Door-freeze canonical form is `catalog.event_session.door_open_at` + the
   `kernel.is_transfer_frozen(atom_id)` helper (schema §2.3, migration `073`); §12.4 updated. No stored
   `transfer_frozen` column exists; client read and create-RPC recheck target the same helper.
3. **`platform_support` refund ceiling (§11.4).** RLS §7.10 grants support a *capped* `refund_primary_order`;
   the schema names only `admin_refund` for platform. The exact support cap / escalate-to-risk boundary is
   deferred to policy (mirrors RLS §15.4).
4. **Settlement-close authority scope (§10.2).** Both `org_finance` and `venue_finance` are plausible;
   contract accepts either (mirrors RLS §15.3) — confirm org-level vs venue-level (drives payout).
5. **Native auction bid RPC.** MVP reuses the frozen external `public.bids`/`auto-finalize-auctions` engine
   (CONFLICTS #6); a native `market.bid` ledger + bid RPC is an **extension point**, not contracted here.
   `market.create_auction` + finalize (→ member #2b) are contracted; the bid write path defers to the existing
   engine.
6. **`change_org_role` vs schema `grant_org_role`/`revoke_org_role`.** Contract uses the brief's names as the
   public surface; implementers may realize them as the schema's grant/revoke primitives (documented aliases).

---

*End of PHASE_2_RPC_FUNCTION_CONTRACTS.md. Design-only; no SQL, no function bodies. Companion to the physical
schema (deliverable #1), RLS spec (#3), and the Edge Function spec (#5, which picks up every EDGE-FRONTED item
flagged in §13), per SPEC_FOUNDATION §10.*
