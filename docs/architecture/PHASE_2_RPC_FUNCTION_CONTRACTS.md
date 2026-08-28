# Phase 2 — RPC / SECURITY DEFINER Function Contracts

**Status:** BUILD-READY DESIGN SPEC. **Design-only — NO SQL, no function bodies.** Each contract is written
so an implementing engineer can author a `SECURITY DEFINER` function from it **without making an architectural
decision**. Where a decision remained open it is flagged under §16 RECONCILIATION.

**Binding inputs (authority order):**
1. `docs/architecture/PHASE_2_SPEC_FOUNDATION.md` (committed copy of the session SPEC_FOUNDATION) — **BINDING**: §5 SSCAS + global lock order; §4 C26/C27/C33/C35/C36 and D3
   cause-codes; §2 integrate-never-rewrite; §8 security invariants.
2. `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` — the authoritative tables/columns each function reads/writes
   (exact names used throughout).
3. `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` — the sanctioned write path per RPC-only table; role checks match its
   `has_*_role` model and §11 EXECUTE-authority table.
4. `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` — C8 native-sale boundary (§6.2/§10), the transfer engine as sole
   custody writer (§9.4), the DB-enforced invariants (§2).
5. Frozen live money-core RPCs in `supabase/migrations/` (`reserve_buy_now`,
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
- **Role labels (C36, O-2/O-4):** the canonical set is the **fifteen** labels of
  `PHASE_2_ROLE_MODEL_SPEC.md` §3 / RLS §2.1 — org `org_owner·org_admin·org_finance·org_marketing·
  org_promoter_manager·org_member`; venue `venue_manager·venue_finance·venue_box_office·venue_marketing·
  venue_promoter_manager·venue_scanner`; platform `platform_admin·platform_support·platform_risk`.
  **`venue_door` is renamed `venue_scanner`** and **`venue_promoter` is removed** — a promoter's authority is
  row ownership (`venue.promoter.identity_id = auth.uid()` / `kernel.is_promoter_for_event`), tested on a
  **live** row, never by `has_venue_role`. A display name (`box_office`, `scanner`, `marketing`) is as illegal
  in a predicate as a bare `role='finance'` — it is a member of no enum.

### 0.1a EDGE-CALLER-JWT — the binding rule for every edge function on a money or custody path

> **An edge function holding `SUPABASE_SERVICE_ROLE_KEY` MUST NOT invoke a money or custody RPC with a
> service-role client.** For any RPC in this document that authorizes on **caller identity**, the edge
> function MUST construct its Supabase client from the **caller's own `Authorization` header**, so that
> `auth.uid()` and `auth.jwt()` resolve to the human *inside the transaction*. The service-role key may be
> used for that function's other work — Stripe calls, KMS calls, webhook callbacks, denial logging, push
> fan-out — but **never** to invoke a money or custody RPC on a human's behalf.

On a service-role client, inside the RPC: `auth.uid()` is **NULL**, so **every** `has_org_role` /
`has_venue_role` / `is_platform` check **silently degrades**; `auth.jwt()` is the service token, carrying **no
`uid`, no `aal`, no `amr`**, so step-up freshness is unenforceable; and the only remaining way to name the
actor is for the edge to **attest** it as a parameter — which is exactly the client-supplied-authority pattern
**ratified row C35 forbids**, and which §0.1 forbids in the same words two paragraphs above. This is the
single highest-severity correction the money-authority spec makes. The edge integrator states the mirror in
`PHASE_2_EDGE_FUNCTION_SPEC.md` §3.4/§3.5; **both statements must exist**, because either document alone reads
as describing the other's job.

**Two grant classes follow from it, and every contract below is tagged with one:**

| Class | Grant | Bound by EDGE-CALLER-JWT? |
|---|---|---|
| **caller-authorized** (default) | `REVOKE EXECUTE FROM anon, public`; `GRANT EXECUTE TO authenticated` + in-body predicate | **Yes** |
| **`EXEC: DEF`** (definer-only) | `REVOKE EXECUTE FROM anon, authenticated, public`; `GRANT EXECUTE TO service_role` **only** | **No** — it has *no human actor by construction*, and is the **only** sanctioned use of a service-role client against this schema |

**The door is the exception that proves the rule.** It has no `auth.uid()` *by design*, and therefore may not
authorize on caller identity at all. Its authority comes from `kernel.assert_door_session(device_id,
session_id)` re-validating a **server-validated device assertion** against live tables — not from an edge
attestation of a human. A door RPC that accepted an edge-supplied `p_actor_identity` would be the same C35
violation wearing a different hat.

**A denied money action currently leaves no trace, and that is fixed here, not worked around.** §0.3 writes
the audit row **in the same transaction** as the action; a failed predicate `RAISE`s, which rolls the
transaction back and takes the audit row with it. Postgres has no autonomous transactions. **Repeated failed
attempts to change a payout destination or fire a payout are the single highest-value fraud signal in the
system, and they are invisible.** The edge therefore catches `insufficient_privilege` / `sod_violation` /
`step_up_required` from a money RPC and, **in a separate transaction**, calls `kernel.record_money_denial`
(§17.9) — `EXEC: DEF`, no human path.

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
- The **global lock order** (acquire ascending, release reverse — SPEC_FOUNDATION §5, schema §0.9), **with two
  additions from the delta specs**:
  **`Event/Session(1) → Inventory(2: batch, then shard ascending shard_no) → Order(3) → Listing(4) → Ticket
  Atom(5: ascending ticket_atom_id) → Approval/Request(5.5) → Payment/Payout/Reserve/Settlement(6)`.**
  - **Rank 1 is promoted from a read-gate to a real lock.** Every RPC that can move custody, or that reads the
    freeze boundary to decide, first takes `SELECT … FROM catalog.event_session WHERE session_id = <resolved
    from the atom> FOR SHARE`. `venue.open_door_manifest` / `close_door_manifest` take `FOR UPDATE` on the same
    row. **Rank 1 is the lowest rank in the total order, so prefixing any acquisition sequence with it is
    unconditionally ascending** — every existing member re-proves trivially (§14.2). `FOR SHARE` is shared:
    arbitrarily many concurrent transfers hold it without blocking each other; only the twice-a-night
    `FOR UPDATE` conflicts. The cost is one extra single-row b-tree lock on a row the RPC already had to read.
  - **`Approval/Request` is placed at 5.5** — after the custody rows an approval holds, before the money rows
    it authorizes — so no inversion is introducible. See §17.1's SSCAS note and RLS **MD-1**.
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
- **DELETE:** no RPC deletes rows (GP-2). **One named exception, granted once and not by analogy:**
  `kernel.clear_my_demographics` (§17.20) hard-deletes the caller's own `kernel.identity_demographic` row
  **inside the definer**; clients hold zero DELETE. Keeping a withdrawn gender answer as a tombstoned row
  would defeat the withdrawal, and that table references no ledger. Everywhere else, reversal is a forward
  state transition or a compensating row.

### 0.8 Named tests and named policies — where authority is asserted

Two conventions that the eight delta specs left implicit, stated here so an implementer knows where each kind
of enforcement lives:

- **RLS policy names** follow `<schema>_<table>_<verb>_<principal-class>` and are registered, table by table,
  in **RLS §16.10**. **No contract in this document is protected by a policy.** Every RPC here is a definer
  function, so a table policy on the objects it writes **never runs** (RLS GP-3a). A reader looking for "the
  policy that protects `kernel.payout`" will not find one, and must not add one: authority on the money and
  custody planes is `REVOKE EXECUTE` + narrow `GRANT EXECUTE` + the in-body predicate, and nothing else.
- **Test ids** are `T-RPC-<AREA>-<nn>` here and `T-RLS-<AREA>-<nn>` in the RLS spec. Every contract below
  names the tests it requires; the consolidated list is **§18**. Two delta specs contribute 23 RPCs with **no
  named test and no named policy anywhere**; §18 supplies the tests, and the paragraph above supplies the
  reason there is no policy to name.

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
- **Reads:** `kernel.org_member` / `venue.staff_role` / `kernel.platform_role` (+ `public.admin_users`
  bootstrap). **`venue.door_pin` is NOT read by any role predicate** — the door path is
  `kernel.assert_door_session` (§1.5). `has_event_role` resolves `catalog.event.venue_id` → `has_venue_role`
  (and `catalog.event.org_id` → `has_org_role` for org authority over an event).
- **Writes:** none. **Locks:** none (read). **SSCAS:** n/a. **Idempotency:** n/a (pure).
- **Result:** boolean. **Security:** live read (a revoke takes effect immediately; stale JWT cannot re-grant —
  I-5). `STABLE`, `search_path` pinned. **Forbidden callers:** none (any RPC/policy may call); never replaced
  by a bare string compare.
- **CHANGED — `has_venue_role` reads `venue.staff_role` and no other table.** The former clause *"Door path
  also accepts a valid non-expired `venue.door_pin` bound to the session as a `venue_door` device principal"*
  is **removed** (ROLE_MODEL R-8 / §7.5). It made the predicate's **meaning depend on the caller**: a reviewer
  looking at `USING (kernel.has_venue_role(v, ARRAY['venue_manager']))` had to know whether a loginless,
  shared, deliberately weak device PIN could satisfy it. After the change the answer is always **no**, for
  every policy and every RPC in the corpus, without reading the helper. **`T-RPC-ROLE-01`:**
  `pg_get_functiondef('kernel.has_venue_role')` does not reference `venue.door_pin`.

### 1.1a `kernel.has_org_role_over_venue(p_venue_id, p_roles[])` · `kernel.has_org_role_over_event(p_event_id, p_roles[])` — **NEW RPC** ×2
- **DB-RPC** (predicate helper), `STABLE`, `EXEC: authenticated`.
- **Purpose:** the **only** sanctioned expression of org→venue / org→event inheritance on the **read** path
  (RM-3). Resolves `catalog.venue.org_id` / `catalog.event.org_id`, then delegates to `has_org_role`.
- Exists because the corpus **described** the inheritance in prose but never named a helper for it, while
  simultaneously granting `org_owner`/`org_admin` a direct venue-table read. Naming it closes that gap and
  stops every policy re-inlining the same two-table join — the *"hundreds of policy clauses"* failure mode.
- **Writes:** none. **Locks:** none. **SSCAS:** n/a. **Result:** boolean.
- **Forbidden:** any policy re-inlining the join instead of calling these (**`T-RPC-ROLE-02`**). **RM-4 holds:
  there is no venue→org path in either direction of any helper.**

### 1.1b `kernel.is_org_affiliate(p_org_id)` — **NEW RPC**
- **DB-RPC** (predicate helper), `STABLE`, `EXEC: authenticated`.
- **Purpose:** true iff **any** `kernel.org_member` row exists for `(p_org_id, auth.uid())`, at any role.
  Distinguishes *affiliation* (connected to this org at all) from the *base membership role* `org_member`,
  which is an enum label in that row.
- > **RM-6 — affiliation is a SCOPING input, never an AUTHORIZING one.** It may decide *which* orgs appear in
  > a context switcher or *which* rows a roster read returns. It may **never** be the sole gate on any
  > capability. Every capability requires a named role. **`T-RPC-ROLE-03`:** `is_org_affiliate` does not
  > appear as the sole predicate in any policy or RPC authority check.

### 1.1c `kernel.is_promoter_for_event(p_event_id)` — **NEW RPC** (Phase 2D)
- **DB-RPC** (predicate helper), `STABLE`, `EXEC: authenticated`.
- **Purpose:** true iff a live `venue.promoter_link` exists for `(p_event_id, auth.uid())`. **Replaces the
  deleted `has_venue_role(…,[venue_promoter])` test everywhere.**
- A promoter holds **no row in any of the three authz tables**, so every administrative predicate returns
  false for them and deny-by-default (I-1) denies the capability without a policy having to say so. The only
  path from promoter to administrator is an explicit invitation or grant by an already-authorized principal —
  and **none of `grant_org_role` / `invite_org_member` / `accept_org_invite` / `grant_staff_role` /
  `grant_platform_role` takes a `promoter_id`, `promoter_link_id`, `attribution_id` or referral id as input**,
  so no promoter artifact can appear on the write path to a grant (**`T-RPC-ROLE-04`**).

### 1.1d `kernel.assert_door_session(p_device_id, p_session_id)` — **NEW RPC** — **EXEC: DEF**
- **DB-RPC**. **Purpose:** the *entire* authorization surface of the door path. Raises unless a valid,
  unexpired, unrevoked door session binds that device to that session.
- **Reads:** `venue.scan_device` (`status='active'`), `venue.door_pin` (`status='active'`,
  `expires_at > now()`, bound to `p_session_id`) — **live**. **Writes:** none. **Locks:** none. **SSCAS:** n/a.
- **Actor:** none. **`auth.uid()` is NULL on this path**, by design. The door client never talks to PostgREST:
  it calls the `door-session` edge function, which holds `service_role` and invokes the definer RPC with a
  **server-derived** `p_actor_device_id`. The Postgres principal is a machine identity acting on a
  server-validated **device** assertion, never on a client claim.
- **NEVER an RLS predicate (RM-5).** It must not appear in any `USING` clause (**`T-RPC-ROLE-05`**:
  `assert_door_session` appears in no `pg_policy` expression).
- **Security-critical, and treated as such:** `postgres`-owned, pinned `search_path`, `EXECUTE` revoked from
  `anon`/`authenticated`, covered by the package's adversarial verification. Concentrating the door's whole
  authorization surface into one auditable function is the point; it is also a single point of failure.
- **Warning for the implementer:** every policy and RPC that assumes a non-null `auth.uid()` must be re-read
  against the door flow. Because the door reaches the database only via `service_role`, **RLS is bypassed on
  that path entirely** and this function is the only gate.
- **The four capabilities a door session authorizes, and nothing else:** scan/admit for its session, offline
  batch for its device, manifest sync for its device, guest-entry check-in (`status` + `checked_in_at` only)
  for its session. It is denied on every other capability, **including the entire consumer plane** — it has no
  `auth.uid()`, therefore no owned rows, therefore no consumer capability. That is not a policy choice; it
  falls out of the credential model.
- **Why not a Supabase JWT for the door** (rejected, recorded so it is not re-proposed): (a) it re-creates the
  broad authenticated session O-2 forbids — a stolen door tablet's blast radius becomes *"everything a fan can
  do"* rather than *"scan this room tonight"*; (b) it puts authority in a JWT claim, which C9/I-5 forbid for
  anything money-consequential, and admission **is** custody-consequential (it drives `state → scanned`);
  (c) a JWT survives a revoke for up to its TTL, while a door PIN is revoked *now* and the next scan fails —
  which is the entire point of a door credential.
- **Attribution gap this creates and how it is closed:** `venue.scan` has `device_id` but **no actor column**,
  and `device_id` is NULL on the authenticated-staff path — so a staff admit records *who admitted nobody at
  all*. Requires the schema owner's `venue.scan.actor_identity_id` + the non-anonymous CHECK (RLS §17 X-2).

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
  package `077`; the former pending-marker fallback is superseded — addendum A1 CLOSED);
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
  `auth.uid()` (fan self-hold) or door/staff-on-behalf via `has_venue_role([venue_scanner, venue_manager])`.
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
  owner (`auth.uid() = inventory_hold.identity_id`) OR `has_venue_role([venue_manager, venue_scanner])` OR the
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
  or door/staff-on-behalf (`has_venue_role([venue_scanner, venue_manager])`; buyer id **server-set**, never
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
  (INSERT `pending`), `venue.order_item` (INSERT, IMM-after-issue), and — where a promoter code or link is
  presented — the **mutable candidate columns** `venue.order.attribution_candidate_code_id` /
  `_link_id`. **Result:** `{ status, order_id, total_minor, currency }`. **Failure:**
  `precondition_failed` (stale/held-by-other), `idempotency_replay`. **Forbidden callers:** anon; a client
  supplying its own price or buyer_id.

> **`SPEC CORRECTION` — this RPC no longer writes `venue.attribution`.** It previously said *"optionally
> `venue.attribution` (in-txn if `source='promoter_link'`, AO)"*, and RLS §9.17 said the same. **Four
> documents disagreed with those two:** DA §1.7 says attribution is written when an attributed order is
> **paid**; CDM §1.3 defines it as an append-only record of a **sale**.
>
> The placement was not merely inconsistent, it was **unsatisfiable**. An append-only ledger row written for a
> **pending** order records a sale that has not happened and may never happen. Most abandoned carts never pay,
> so the ledger fills with rows every reader must then "ignore" — and an ignorable append-only ledger row is a
> contradiction in terms. It makes the owner requirement *"immutable once economically committed"* impossible
> to satisfy, because the row would be frozen **before** the economic commitment. And it makes a promoter's
> dashboard show earnings that evaporate.
>
> **Resolution:** the pre-pay **candidate** lives in two nullable, guard-triggered columns on `venue.order`
> (mutable only while `status='pending'`, frozen the instant it leaves), and the **attribution row is written
> in `venue.finalize_primary_order`** (§6.3) via `venue.resolve_order_attribution` (§17.14). The candidate is
> 1:1 with the order, has the order's exact lifetime, and dies with it — which is why it lives on the order
> row rather than in a second table the hottest write path would have to join. **`T-RPC-ATTR-01`:** no
> `venue.attribution` row exists while the order is `pending`, even with both candidates set.

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
- **ADDED — attribution freezes here.** Inside this transaction, under the order lock it already holds, this
  RPC calls **`venue.resolve_order_attribution(p_order_id)`** (§17.14). **Order-paid is the point where the
  platform first has irreversible economic consequence** — money captured, tickets minted, capacity consumed —
  which is what *"economically committed"* means. (Ticket issuance is the same instant but the wrong
  **aggregate**: attribution is a property of the **order**, the money event, not of the ticket, the asset —
  *"refunds, receipts, and attribution attach to the order; custody attaches to the ticket"*. Settlement close
  is far too late: the promoter needs to see the sale the night it happens, and the terms in force at
  settlement rather than at sale would govern the commission.)
- **ADDED — post-open issuance feeds the door manifest.** Where an open manifest episode exists for the
  session, `kernel.issue_ticket_atoms` calls **`venue.append_door_manifest_delta(..., p_op := 'add')`**
  (§17.13) so a synced offline scanner's admissible set tracks atoms minted after the base snapshot. Without
  it, a fan who buys at the box office after doors open is refused by every offline scanner. **If no episode
  is open the call is a silent no-op, never an error** — issuance must never fail because the door is shut.
- **ADDED — `kernel.issue_ticket_atoms` is NEVER frozen** (§12.4). Minting from ∅ is not a custody move, and
  door-release inventory (`release_kind='door'`) exists precisely to be sold after doors open.

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
- **ADDED — this is THE freeze enforcement point** (`SPEC CORRECTION`, §12.4). It re-checks
  `kernel.is_transfer_frozen(p_atom_id)` under the atom lock and rejects with `frozen`. It was **absent from
  the recheck set**, which meant the freeze gated transfer *start* but not *completion*: a transfer initiated
  at 21:00 and accepted at 23:30 with doors open at 22:00 moved custody and bumped `credential_version`
  **after** the manifest snapshot was taken — precisely the credential-stranding C6 exists to prevent. Because
  this is the **sole custody-move engine**, enforcing here makes bypass structurally impossible; the
  caller-level rechecks exist only for error quality.
- **Locks & lock order (SSCAS #2):** **Event/Session** (`FOR SHARE`, rank 1 — the freeze read) → **Listing**
  (`FOR UPDATE`) → **Ticket Atom** (`FOR UPDATE` by `ticket_atom_id`) → **Payment** link. Ascending — no
  inversion. Multi-atom passes lock atoms ascending id.
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
  `venue.record_scan` under the atom lock. **Actor:** door principal — **either** an authenticated `venue_scanner` **or** the `service_role` edge path asserting `kernel.assert_door_session` (§1.1d) — or
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

> ### `SPEC CORRECTION` — CRITICAL. This function MUST NOT consult `kernel.is_transfer_frozen`.
>
> §12.4 and RLS §14.3 previously made `kernel.mark_ticket_scanned` re-check `kernel.is_transfer_frozen` under
> the atom lock **and reject with `frozen`**.
>
> **Trace it.** Opening the door manifest sets `catalog.event_session.door_open_at`. `is_transfer_frozen` then
> returns **true for every atom of the session** — the predicate is session-wide (§12.4a), and even in its
> corrected form it is true for every atom past `effective_freeze_at`. `mark_ticket_scanned` is the
> custody-side transition `venue.record_scan` invokes on the first valid admit. Therefore, **from the moment
> doors open until the end of the night, every scan of every valid ticket is rejected. Nobody gets in.** That
> is not a degraded mode or an edge case — it is the normal, intended operating sequence of every event, and
> it fails 100% of admissions.
>
> **The intent is already covered.** The evident purpose was to stop a mid-transfer atom being scanned. **That
> is fully enforced by this function's own precondition `resale_state = 'none'`** — the "delist first" rule
> two bullets above. An atom in an open p2p or an active listing carries `locked`/`listed` and is refused on
> that precondition alone, with a *better* reason code (`listed_locked`), whether or not the door is open. The
> freeze check adds nothing.
>
> **It is also categorically wrong.** The freeze is a **custody-move** guard. Scanning is **not a custody
> move** — this very contract says so: *"an ownership-log entry is **not** appended (scan is not a custody
> change)"*. Applying a custody-move guard to a non-custody-move is a category error, and the category error
> is what produced the total-denial behaviour.
>
> **Correction:** `kernel.mark_ticket_scanned` is **removed from the freeze recheck set** (§12.4) and must
> never reference `kernel.is_transfer_frozen`.
>
> **Why admission still works after doors open.** Four conditions gate an admit, and **none of them is the
> freeze**: (1) the session is `live` — `venue.record_scan`'s own precondition, and the only thing that stops
> admission; (2) the atom is `state='active'` and belongs to the session; (3) `resale_state='none'`, which
> independently covers every case the freeze check was reaching for; (4) `credential_version` is current
> (online live verify, C37) or matches the manifest entry (offline). **Opening the manifest changes none of
> them.** It changes `door_open_at`, which drives `is_transfer_frozen`, which after this correction **has no
> reader on the admission path at all.** The drain (§12.4c) additionally guarantees condition (3) is
> satisfiable: any atom left `listed`/`locked` when doors open is unlocked back to its owner at open time, so
> a fan mid-transfer is not refused at the door with no remedy.
>
> **Made structural, not merely documented.** A prose correction to a check that "seemed safer" will be
> re-added by the next engineer who reads the freeze section. **`T-RPC-DOOR-01` (structural):**
> `pg_get_functiondef('kernel.mark_ticket_scanned')` **does not match** `is_transfer_frozen`, so a future edit
> re-breaking admission fails CI rather than failing at the door. Behavioural regressions
> `T-RPC-DOOR-02..04` are in §18.

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
  recipient (C35 re-check — money-in stays on the frozen path). **ADDED: `NOT
  kernel.is_transfer_frozen(atom)` — rejects `frozen`** (`SPEC CORRECTION`, §12.4; this closes the
  start-but-not-completion gap named in §7.2). **Locks & order:** **Event/Session** (`FOR SHARE`, rank 1) →
  **Transfer** (`FOR UPDATE`) → **Ticket Atom** (`FOR UPDATE`) → **Payment** (priced). **SSCAS:** #8.
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
  recipient (they accept/decline); non-parties. **`declined` owner (explicit):** the addressed recipient
  writes `declined` through the accept endpoint's decline branch (`accept_p2p_transfer` with
  `p_decision='decline'` — same auth: `auth.uid() = to_identity`), which unlocks the atom exactly like
  cancel; the sender cannot decline, the recipient cannot cancel.

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
  principal — **either** an authenticated `venue_scanner` **or** the `service_role` edge path asserting
  `kernel.assert_door_session` (§1.1d) — or `venue_manager` for the session.
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
  via `kernel.mark_ticket_scanned`. **Actor:** door principal — **either** an authenticated `venue_scanner` **or** the `service_role` edge path asserting `kernel.assert_door_session` (§1.1d) — or
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
  scan_sequence)` to resolve first-admit-wins across devices; flag conflicts. **Actor:** `venue_scanner` (or the `service_role` edge path asserting `assert_door_session`)
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
- **`SPEC CORRECTION` — Role NARROWS to `EXEC: DEF` + `is_platform([platform_support (capped),
  platform_admin])`.** Buyer, `org_finance` and the new `org_owner` authority reach this function **only via
  `kernel.request_order_refund` (§17.1)**, which calls it definer→definer in the same transaction. **This
  remains the sole writer of `kernel.refund`** on every tier, which is what preserves R7 money-single-path:
  the request/approve objects *request*; none of them writes a money row.
- **`SPEC CORRECTION` — the voidable/consumed partition.** `kernel.void_ticket_atom` requires the atom not to
  be terminal, and `scanned` **is** terminal with **no `scanned → voided` edge in the frozen state machine**.
  So as previously contracted, a refund on an order containing a scanned atom raised `precondition_failed` and
  **the entire refund failed, including its money leg** — no spec said so, and no operator surface warned
  about it. Refunding an attendee who already walked in is an ordinary goodwill act, so "the whole refund
  fails" is wrong product behaviour; but voiding a scanned atom is an illegal transition **and** the exact
  shape of an insider-fraud primitive (staff scans a friend in, then refunds the ticket). Therefore:
  - covered atoms are partitioned into **`voidable`** (`state ∈ {issued, active}`) and **`consumed`**
    (`state = 'scanned'`);
  - a refund covering only `voidable` atoms behaves exactly as contracted today;
  - a refund covering **any** `consumed` atom **never voids it, never returns inventory** (the seat *was*
    consumed — returning it would oversell the room), and its tier is governed by
    `refund.scanned_atom_policy ∈ {refuse, platform_review}`, default `platform_review`;
  - **the money leg still completes**, and the result names the split explicitly:
    `{ atoms_voided[], atoms_not_voided[{atom_id, reason:'already_scanned'}] }` — **never a silent partial**;
  - the audit row carries the consumed-atom list, so the goodwill-vs-collusion pattern is queryable after the
    fact. **That is the control that makes the capability safe, rather than the refusal.**
  - **No new ticket state, no new edge in the state machine, no terminal re-animation.** The atom stays
    `scanned`; only money moves.
- **`custody_moved` is added to the failure taxonomy** (§0.5): an atom whose `current_owner_id` is no longer
  the order's buyer is **not refundable through this path**, full stop — voiding it would confiscate a
  stranger's ticket, and the reseller already recovered their money in the resale, so refunding the primary
  purchase too is double recovery. It becomes a platform dispute (`admin_refund`), not an org action.
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

> **`SPEC CORRECTION` — the freeze applies to the COMPLETE branch only. Freezing both strands money forever.**
>
> The complete branch is a **custody move** and is therefore `frozen` when the session's boundary has passed.
> The compensate branch is a **refund-void**, which C23 also freezes. **If the freeze applied to both, a sale
> caught by doors-open could do neither** — complete is refused as `frozen`, compensate is refused as `frozen`
> — and the buyer's money sits in `paid_pending_transfer` **permanently**. That is the exact unbounded-dwell
> failure C25 exists to forbid, reintroduced by the guard meant to protect custody.
>
> **Ruling: complete is frozen; the compensate branch is EXEMPT.** A sale caught by doors-open therefore
> resolves as `compensated` — the buyer is refunded. That is not a compromise, it is the **correct** outcome:
> a buyer who cannot receive a working credential before an offline door opens was never going to be admitted.
> Exempting compensate moves no ticket to a new owner and strands nothing.
>
> **The exemption carries one obligation:** because it voids an atom while an episode may be open, it **MUST
> write a `revoke` delta** via `venue.append_door_manifest_delta` (§17.13), or it re-opens the offline
> revocation leak the exemption was granted to avoid. This is also the **only** voiding exemption that fires
> **without a human** — it is a routine, unelevated sweep — which is why the delta is mandatory rather than
> advisory. **`T-RPC-DOOR-07`:** the compensate branch succeeds on a frozen session and the complete branch is
> refused.

### 12.4 Door-freeze signal (recon #3) — read + recheck contract — **CORRECTED**

The stored signal is **`catalog.event_session.door_open_at`**; the ONLY authorization read is the derived
helper **`kernel.is_transfer_frozen(p_ticket_atom_id)`**. There is **no stored
`kernel.tickets.transfer_frozen` column** — edge, client, and RPC all target the same helper. **`NO SCHEMA
CHANGE` to the helper's signature or to any call site**; only its body and its recheck set change.

#### 12.4a The corrected predicate — total, so the freeze can never silently fail to engage

The previous body was `door_open_at IS NOT NULL AND now() >= door_open_at`, which is **fail-open at NULL**: a
session whose manifest is never opened is never frozen. Replaced with:

```text
catalog.effective_freeze_at(p_session_id) -> timestamptz NOT NULL          -- NEW RPC (STABLE helper)
  := LEAST(
       door_open_at,                                              -- explicit: first manifest open (nullable)
       COALESCE(doors_at, starts_at) + config('door.implicit_freeze_offset_interval')
     )                                                            -- implicit backstop: NEVER null

kernel.is_transfer_frozen(p_ticket_atom_id) ->
       now() >= catalog.effective_freeze_at(session_of(atom))
   AND NOT EXISTS (active, unexpired kernel.door_freeze_override covering this atom)
```

`starts_at` is `NOT NULL` (schema §2.3), so **`effective_freeze_at` is total** — there is no input for which
it returns NULL, and therefore **no input for which the freeze silently never engages**. That is fail-closed
expressed as a type, not as a promise (**`T-RPC-DOOR-08`**). `doors_at` rather than `starts_at` is the primary
backstop because `doors_at` is when humans physically arrive and a scanner is realistically armed;
`starts_at` is often an hour later, and freezing there would leave an hour of live-door / open-transfer
overlap — exactly the window C6 exists to close. The failure direction is deliberately asymmetric: a
`doors_at` set too early freezes transfers early (an annoyance, recoverable by the §17.11 override); a
`doors_at` set too late is bounded by `LEAST` against `starts_at` and against any explicit open. **There is no
input that produces "never frozen."**

`door_open_at` itself is a **cached monotone head of an append-only episode ledger** —
`door_open_at ≡ MIN(opened_at) FROM venue.door_manifest WHERE session_id = s`. Because episodes are stamped
with the transaction's own `now()` and the ledger is INSERT-only, `MIN` can only ever be the **first** open:
no second open moves it, no close clears it, no UPDATE path exists. **"Cannot move backwards" stops being a
rule someone has to remember and becomes arithmetic.** Its sole writer is `catalog.engage_door_freeze`
(§17.12), which is `EXEC: DEF` and appears in **no** RLS EXEC row.

#### 12.4b **The narrowing four documents describe and nothing implements — corrected**

Schema §2.3, **this section**, RLS §14.3 and the migration plan all said the freeze is *"narrowed
per-open-manifest-ticket, not blanket per-session, per C43."* **The specified predicate is session-wide.**
There is no per-ticket term in it, and none was ever specified. And **C43 is
`RATIFIED-MODELED-ONLY(GATE-M)` — it is not MVP**, so the narrowing could not be built in this phase even if a
predicate existed.

> **MVP: the freeze is session-wide.** `is_transfer_frozen(atom)` is true for **every** atom of a session once
> `now() >= effective_freeze_at(session)`, subject only to an active override. The per-open-manifest-ticket
> narrowing is a **purely additive conjunct** deferred to Gate M with C43; adding it later strictly *reduces*
> the frozen set and breaks no caller of the MVP predicate.

This is the reconciliation, not a new decision. Stating it removes an implementer's only reason to hunt for a
per-ticket term that was never written. Recorded for the amendment owner (RLS §17 X-7).

#### 12.4c The recheck set — **wrong in one direction, incomplete in three**

| RPC | §12.4 as written | **This spec** | Why |
|---|:---:|:---:|---|
| `market.create_listing` | rechecks | **rechecks** | correct (error quality) |
| `market.create_p2p_transfer` | rechecks | **rechecks** | correct (error quality) |
| `kernel.lock_ticket` | rechecks | **rechecks** | correct — a choke-point |
| **`kernel.mark_ticket_scanned`** | **rechecks → `frozen`** | **MUST NOT RECHECK** | **§7.5 — CRITICAL. Nobody gets in.** |
| **`kernel.transfer_ticket_ownership`** | absent | **rechecks — THE enforcement point** | sole custody engine; bypass becomes structurally impossible |
| **`market.accept_p2p_transfer`** | absent | **rechecks** | the freeze gated *start* but not *completion* (§7.2) |
| **`kernel.void_ticket_atom`** (routine refund path only) | absent | **rechecks** | C23 extends the freeze to refund-voids |
| **`kernel.request_order_refund`** — parked branch only | — | **rechecks** | a parked refund places a custody hold; it must not be parked on a door-open session (§17.1) |
| `market.cancel_p2p_transfer` (cancel-to-self) | — | **exempt** | C43, ratified: owner and `credential_version` unchanged; nothing can strand |
| `market.cancel_listing` | — | **exempt** | delisting strands nothing |
| `catalog.cancel_event` | — | **exempt** | the session is being cancelled; no admission will occur |
| `kernel.force_void_ticket` · `kernel.admin_refund` | — | **exempt, audited** | platform break-glass; residual is the C6 reconcile window |
| `market.sweep_paid_pending_sales` — **complete** | — | **frozen** | it is a custody move |
| `market.sweep_paid_pending_sales` — **compensate** | — | **exempt** | §12.3 — otherwise money is stranded forever |
| `kernel.issue_ticket_atoms` (door sale · comp · import) | — | **exempt — never frozen** | minting from ∅ is not a custody move |

**Every exempt path that voids an atom MUST write a `revoke` delta** (§17.13) when an episode is open. This
binds all three voiding exemptions — `catalog.cancel_event`, `force_void_ticket`/`admin_refund`, and the C25
compensate branch. Omitting it re-opens the offline-revocation leak the exemptions were granted around.

**Two layers, deliberately.** The **enforcement** points are `kernel.transfer_ticket_ownership` and
`kernel.lock_ticket` — the choke-points nothing bypasses. The caller-level rechecks (`create_listing`,
`create_p2p_transfer`, `accept_p2p_transfer`) exist for **error quality**, so a fan sees *"Transfers are
closed"* rather than a generic engine failure. Both layers must hold.

**The drain, without which the corrected freeze locks fans out.** `mark_ticket_scanned` requires
`resale_state='none'`; once the freeze engages, `accept_p2p_transfer` is refused as `frozen`, so a pending
transfer's atom stays `locked` until its TTL expires — possibly hours. A fan mid-transfer would arrive at the
door and be refused with **no action available to them and none to the door**. `venue.open_door_manifest`
(§17.10) therefore drains the session's in-flight overlays *before* taking the snapshot: `initiated` p2p
transfers → `cancelled` (`reason_code='door_freeze'`, atom unlocked back to the **sender** — which C43 exempts
because owner and `credential_version` do not change) and `active` listings → `cancelled`, atom unlocked.
**Excluded:** any listing whose sale is `paid_pending_transfer` — money is already taken and the C25 sweep
owns that row (§12.3). The drain **moves no custody, appends no ownership-log row, and bumps no
`credential_version`**, so the Door Safety Theorem is unaffected.

The RN client reads the same helper (owner-scoped boolean) to disable Transfer/Sell; **the edge layer never
independently decides freeze.**

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

> **Numbering aligned to the canonical FIFTEEN-member enumeration in `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md`
> §15 C12** (consolidation 2026-08-25, Agent E finding E-1). CDM C12 numbering is authoritative; the
> earlier SPEC_FOUNDATION 9-member working list is provenance only.

| C12 # | SSCAS member (canonical, CDM C12) | RPC(s) | Aggregate classes locked, in global order |
|---|---|---|---|
| 1 | Primary issuance | `venue.finalize_primary_order` → `kernel.issue_ticket_atoms` | Event/Session → **Inventory(batch,shard asc)** → **Order** → **Ticket Atom(new)** → **Payment**(link) |
| 2 | Native sale / resale (C8) | `kernel.transfer_ticket_ownership` (called by market checkout / `respond_offer` accept / auction finalize) | **Listing** → **Ticket Atom(asc id)** → **Payment**(link) |
| 3 | Refund-void | `kernel.void_ticket_atom`, `kernel.refund_primary_order`, `kernel.force_void_ticket` | **Order**(if order-scoped) → **Inventory** → **Ticket Atom(asc id)** → **Refund/Payment** (Inventory-before-Atom per §14.2 NB) |
| 4 | Settlement close → payout | `kernel.close_settlement`, `kernel.request_org_payout` | **Settlement** → **Payout** |
| 5 | Attribution → commission | `kernel.close_settlement` (commission line) | (Attribution read) → **Settlement** → **Payout** |
| 6 | Native listing create | `market.create_listing` → `kernel.lock_ticket` | **Listing** → **Ticket Atom** |
| 7 | Native transfer start | `market.create_p2p_transfer` → `kernel.lock_ticket` | **Transfer(Listing slot)** → **Ticket Atom** |
| 8 | Native P2P accept | `market.accept_p2p_transfer` → `kernel.transfer_ticket_ownership` | **Transfer** → **Ticket Atom** → **Payment** |
| 9 | Dispute open → freeze | native dispute-freeze RPC (webhook `charge.dispute.created` branch) + `kernel.hold_payout` | **Dispute** → **Ticket**(freeze overlay) → **Payout**(hold) |
| 10 | Event-cancellation cascade | `catalog.cancel_event` (bounded batch of member #3 per atom) | **Event/Session** → **Inventory** → per **Ticket Atom(asc id)** → **Refund** |
| 11 | Dispute-resolution reversal | `kernel.admin_resolve_dispute`-native path (`force_void_ticket` + refund/clawback executors) | **Dispute** → **Ticket Atom** → **Refund/Payment** → **Payout**(clawback/release) |
| 12 | C25 auto-compensation | `market.sweep_paid_pending_sales` | **Listing** → **Ticket Atom** → **Payment**(complete) XOR **Ticket Atom** → **Refund**(compensate) |
| 13 | Auction deposit-release | auction finalize sweep → `kernel.transfer_ticket_ownership` (+ deposit-auth void) | **Listing/Auction** → **Ticket Atom** → **Payment** |
| 14 | Group-buy claim *(non-MVP; modeled only)* | future `venue.reserve_group_claim()` (A11 one legal door) | **Inventory**(hold) — single-class once inside the door |
| 15 | Wallet checkout *(non-MVP; modeled only — wallet is later-phase)* | future wallet-debit → `create_primary_checkout` path | **Order** → **Payment/Wallet-ledger** |

### 14.2 Lock-order proof (no illegal inversion exists)
The global order is a **total order** on aggregate classes: `Event/Session(1) < Inventory(2) < Order(3) <
Listing(4) < Ticket Atom(5) < Payment/Payout/Reserve/Settlement(6)`; within a class, rows are locked by
ascending id (shards ascending `shard_no`; atoms ascending `ticket_atom_id`). Each member above acquires a
**strictly increasing subsequence** of this order:
- #1: 2 → 3 → 5 → 6 (Event/Session read-gate at 1). Ascending. ✔
- #2: 4 → 5 → 6. Ascending. ✔  (Settlement class 6 shares rank with Payment; a sale never also locks a payout,
  so no same-rank cycle.)
- #3 / #10 (cancel cascade): (3) → 5 → 2? — **NB:** refund-void returns **Inventory (class 2)** *after*
  touching the atom (class 5). To avoid a 5→2 back-edge, the void path acquires **Inventory before the Atom**
  where both are locked in one txn (cancel_event locks Inventory at rank 2 first, then atoms at rank 5), and
  the single-atom `void_ticket_atom` treats the inventory return as a **counter update under its own
  `FOR UPDATE` taken before the atom mutation completes** — i.e. the acquisition sequence is Inventory(2) →
  Atom(5) → Refund(6), ascending. **This is the one place to watch; the contract pins Inventory-before-Atom
  in every void path so no 5→2 inversion is possible.** ✔ *(Implementation note, not a new decision.)*
- #4/#5: 6 → 6 (Settlement then Payout, both rank 6) — ordered by a fixed sub-rank Settlement-before-Payout;
  no cycle. ✔
- #6: 4 → 5. #7: 4(Transfer occupies the Listing slot) → 5. #8: 4 → 5 → 6. #12: 4 → 5 → 6. All ascending. ✔
- #9/#11 (dispute freeze / resolution reversal): Dispute is an admin-plane aggregate outside the six-rank
  money/custody order; within the txn the money/custody acquisitions are Ticket(5) → Refund/Payment(6) →
  Payout(6, fixed sub-rank after Payment) — ascending; the Dispute row is locked first and nothing re-enters
  a lower rank afterward. ✔
- #13: 4 → 5 → 6. Ascending. ✔  #14/#15: non-MVP, modeled only — #14 is single-class (Inventory hold) once
  inside the A11 door; #15 is Order(3) → Wallet/Payment(6), ascending. ✔ (proof obligations restated at build
  time under the execution protocol).
- Cross-member deadlock-freedom: because **every** member acquires locks in the same global ascending order,
  two concurrent members can never hold-and-wait in a cycle (Coffman condition #4 broken by construction) —
  the standard resource-ordering proof.

### 14.3 Assertion (mandated)
**No unnamed synchronous cross-aggregate transaction exists in this contract set.** Every RPC that writes more
than one aggregate class is mapped above to exactly one of the fifteen canonical SSCAS members (CDM C12). Every
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
   migration package `077`; §2.2/§2.3 reference it directly. The pending-marker fallback is superseded.
2. **CLOSED (addenda A2/A3).** Door-freeze canonical form is `catalog.event_session.door_open_at` + the
   `kernel.is_transfer_frozen(atom_id)` helper (schema §2.3, migration `078`); §12.4 updated. No stored
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

## 17. NEW RPC contracts from the eight Phase-2 delta specs

Every contract inherits §0 (definer discipline, C35 actor derivation, C36 role tests, deny-by-default,
audit-in-txn, `p_command_key` idempotency, no DELETE, EDGE-CALLER-JWT, the two grant classes). Only deltas are
stated. **Lock acquisition order is given for every contract, including the read-only ones** (where it is
`none`, that is a claim, not an omission) — because two of the eight source specs supply no lock statement at
all, and an unstated lock order is how a deadlock class gets built.

**Where a source spec supplied no test and no policy, this document supplies the test and states why there is
no policy.** The money and role specs together contribute 23 RPCs with **no named test and no named RLS policy
anywhere**; the notifications spec names two RPCs with **no contract body at all** (§17.28). Those gaps are
filled here and flagged in §19 as authored rather than transcribed.

### 17.1 `kernel.request_order_refund(p_order_id, p_atom_ids uuid[], p_amount_minor int, p_reason_code, p_command_key)` — **EDGE-FRONTED** · `NEW RPC`

- **Purpose.** The single org-and-buyer-facing refund door. Decides the tier server-side, then **either**
  executes through the canonical money writer **or** parks an approval request with a custody hold. **The
  caller does not choose which.**
- **Role.** owner-of-order (`venue.order.buyer_id = auth.uid()`, capped + windowed) ·
  `has_org_role(order.org_id, ['org_owner','org_finance'])` ·
  `is_platform(['platform_support','platform_risk','platform_admin'])`. **`org_admin` and every venue role are
  forbidden callers.** **Bound by EDGE-CALLER-JWT** (§0.1a) — this is one of the three RPCs where a
  service-role invocation would silently degrade every predicate above.
- **Params.** All **untrusted**: `p_order_id`, `p_atom_ids[]` (**may legitimately be empty** — a fee-only or
  goodwill refund with no custody effect; always an exceptional tier, since there is no ticket to point at),
  `p_amount_minor`, `p_reason_code ∈ {buyer_request, oversell_correction}` for org callers.
  `event_cancelled` is produced only by `catalog.cancel_event`; `dispute` / `admin_action` /
  `auto_compensation` are platform/system causes and are **rejected from this entry point** for org and buyer
  callers (`policy_violation`).
- **Server-derived.** `p_actor := auth.uid()`; `org_id := venue.order.org_id` (**a real column — the client
  never supplies the org**); the covered-atom set; `expected_amount`; the tier; and **every threshold's
  `(key, version)` from `catalog.platform_config`, pinned onto the request row** so a mid-flight config change
  cannot silently re-tier a parked request and an auditor can reconstruct why a refund took the tier it did.
- **Covered-atom derivation (fully server-side).** The atoms of an order are `kernel.ticket_ownership_log`
  rows with `sequence = 1` whose `cause_ref` is one of that order's `venue.order_item.id` values — two indexed
  joins, no schema change. **Atoms carry no price**, so per-atom value is `venue.order_item.unit_price_minor`
  for the atom's `ticket_type_id`, unique per order and an immutable purchase snapshot. The RPC recomputes
  `expected := Σ unit_price_minor(atom) + fee_component(config)` and **rejects any `p_amount_minor` exceeding
  it**. Amount is never client-authoritative (C35).
- **Preconditions.** (1) Order `status ∈ {paid, partially_refunded}`. (2) Buyer/order/org relationship
  verified server-side from live tables. (3) Every named atom belongs to this order — a foreign atom is
  `not_found`, **never a partial success**. (4) Every named atom has `current_owner_id = order.buyer_id`, else
  `custody_moved`. (5) Every named atom has `resale_state = 'none'`, else `conflict_locked` **naming the open
  listing or transfer**, so the operator knows what to cancel. (6) `p_amount_minor ≤ expected_amount` **and**
  `Σ(refunds for the payment) + p_amount_minor ≤ payment.total`, the latter under `FOR UPDATE` on
  `public.payments`. (7) **Parked branch only:** `NOT kernel.is_transfer_frozen(atom)` for every atom, else
  `frozen` — a request may not be *parked* on a door-open session (§12.4c). Below-threshold *execution* is
  unchanged and still voids the ticket at the door.
- **Tier decision (server-side, from config).**

  | Condition | Outcome | Effect |
  |---|---|---|
  | buyer caller, within `refund.buyer_self_service_window_hours` and ≤ `refund.buyer_self_service_max_minor` | `executed` | direct |
  | org caller, ≤ `refund.org_auto_execute_max_minor`, no consumed atom | `executed` | direct |
  | org caller, ≤ `refund.org_dual_control_max_minor` | `pending_approval` | park + hold |
  | any consumed (scanned) atom, `refund.scanned_atom_policy = 'platform_review'` | `pending_platform_review` | park + hold |
  | org caller, > `refund.org_dual_control_max_minor` | `pending_platform_review` | park + hold |
  | any consumed atom, `refund.scanned_atom_policy = 'refuse'` | `rejected` | none |

- **Locks & acquisition order.** **Event/Session** (`FOR SHARE`, rank 1 — the freeze read, parked branch) →
  **Order** (`FOR UPDATE`, rank 3) → **Ticket Atom(s)** ascending `ticket_atom_id` (rank 5) → **Approval**
  (rank 5.5, INSERT) → **Payment** (`FOR UPDATE` on `public.payments`, rank 6, for the sum guard). Strictly
  ascending; conforms to §0.4.
- **SSCAS.** Executed branch: **member #3** (existing refund-void). Parked branch: `n/a (single locked
  aggregate class — Ticket Atom)`; the `kernel.approval_request` row is a **fresh INSERT** that contends on
  nothing but its trailing unique index, acquired last. **See RLS MD-1** — if a reviewer judges the approval
  object an aggregate class rather than an intent record, the parked branch is a sixteenth SSCAS member and
  C28's closure needs a formal amendment. It is lock-ordered either way, so the amendment would be a one-line
  ratification, not a redesign.
- **Writes.** *Executed branch* — delegates to `kernel.refund_primary_order` in the same txn (definer→definer);
  **that function alone writes `kernel.refund`. This function writes no money row.** *Parked branch* —
  `kernel.approval_request` (INSERT `pending`), `kernel.tickets.resale_state := 'refund_hold'` on each covered
  **voidable** atom, `kernel.admin_audit` (`refund.request`).
- **Why the hold is on the atom row.** It is the row the scan path already locks, so the guard costs nothing
  on the door hot path and adds no cross-schema read to `record_scan` (R8 scan isolation preserved). The
  existing `lock_ticket` precondition `resale_state='none'` then does all the work: an atom at `refund_hold`
  **cannot** enter a p2p transfer or a listing, with no new check written anywhere.
- **Idempotency.** `p_command_key` unique per `(actor, key)` on `kernel.approval_request`; the executed branch
  inherits `kernel.refund.idempotency_key`. **A replay returns the original outcome, never a second refund.**
  A *second, different* partial refund on the same order mints a new `refund_id` and therefore a new,
  non-colliding key — so successive partials compose correctly.
- **Result.** `{ status ∈ {executed, pending_approval, pending_platform_review, rejected, noop_replay},
  refund_id?, request_id?, amount_minor, atoms_voided[], atoms_not_voided[{atom_id, reason}], tier,
  approval_required_role? }`.
- **Errors.** `insufficient_privilege(42501)` · `precondition_failed` · `custody_moved` · `conflict_locked` ·
  `frozen` · `not_found` · `over_refund` · `policy_violation` · `step_up_required`.
- **Forbidden.** Any client writing `kernel.refund` directly; `org_admin`; every venue role; a buyer refunding
  another buyer's order; any caller supplying an `org_id` or an actor.
- **The cost this incurs, stated rather than buried.** A `refund_hold` **stops the ticket working at the door
  while the request is parked** — a denial-of-admission capability in the hands of every
  `org_owner`/`org_finance`. It is bounded, not eliminated: auto-executed refunds place no hold; every hold is
  bounded by `refund.request_ttl_hours` and released by §17.4; a request cannot be parked on a door-open
  session; and **the buyer must be told** (a ticket that silently stops scanning is the worst failure mode in
  this area). **A hold with no sweep is a bricked ticket — the exact lesson C43 already learned about p2p
  locks.**
- **Tests.** `T-RPC-MONEY-01` (tier table, one case per row) · `T-RPC-MONEY-02` (`custody_moved` on a resold
  atom) · `T-RPC-MONEY-03` (a scanned atom is reported in `atoms_not_voided[]`, is not voided, returns no
  inventory, and the money leg still completes) · `T-RPC-MONEY-04` (parked on a frozen session ⇒ `frozen`) ·
  `T-RPC-MONEY-05` (replay returns the original outcome, exactly one refund row).
- **Policy:** none, and none is possible — see §0.8.

### 17.2 `kernel.approve_refund_request(p_request_id, p_decision, p_reason_code, p_command_key)` — **EDGE-FRONTED** · `NEW RPC`

- **Purpose.** The second act of dual control. On approve, release the holds and call the canonical money
  writer. On deny, release the holds and terminate the request. **Dual control cannot be done in one
  transaction** — two humans, two sessions, two points in time force a durable pending object — which is why
  §17.1 has two branches rather than one.
- **Role.** For `pending_approval`: `has_org_role(request.org_id, ['org_owner','org_finance'])` **AND
  `auth.uid() <> request.requested_by`** — SoD-2, enforced **structurally**, backed by the table constraint
  `CHECK (approved_by IS NULL OR approved_by <> requested_by)`. For `pending_platform_review`:
  `is_platform(['platform_support','platform_risk','platform_admin'])`, subject to the support cap. **Bound by
  EDGE-CALLER-JWT.**
- **`action`-dispatched.** The same function serves the payout-above-threshold branch (`action =
  'payout.request'`) and the money-config branch (`action = 'config.set_money_key'`), under the same SoD rule.
  For payout, the §17.7 destination-setter exclusion applies **to the approver as well** — otherwise the
  destination-setter could simply approve instead of request.
- **Preconditions.** Request `state = 'pending'` and not expired. **Every §17.1 precondition is RE-EVALUATED
  under lock at approval time — the stored payload is *evidence*, never authority.** Specifically: the order
  is still refundable; the atoms are still owned by the buyer; the payment sum guard still passes; the amount
  is **recomputed** from `venue.order_item` and must still equal the pinned `expected_amount`. Drift ⇒
  `precondition_failed`, and the request moves to **`stale`** with holds released, rather than executing on
  stale facts.
- **Locks & acquisition order.** **Order** (rank 3) → **Ticket Atom(s)** ascending (rank 5) → **Approval**
  (`FOR UPDATE`, rank 5.5) → **Refund/Payment** (rank 6). Ascending.
- **SSCAS.** Member **#3** (approve branch); single-aggregate (deny branch).
- **Writes.** `kernel.approval_request` (→ `approved`/`denied`/`stale`), `kernel.tickets.resale_state :=
  'none'` per held atom, then on approve **`kernel.refund_primary_order`** (which writes `kernel.refund`, the
  voids, the inventory return, the order status, and the `refund.issue` audit); `kernel.admin_audit`
  (`refund.request_approved` / `refund.request_denied`).
- **Idempotency.** `p_command_key` + the request's terminal state.
- **Result.** `{ status, request_id, refund_id?, atoms_voided[], atoms_not_voided[] }`.
- **Errors.** **`self_approval`** — its own named failure, distinct from a bare `42501`, so the UI can say
  *"a different person must approve this"* rather than "permission denied" · `insufficient_privilege` ·
  `precondition_failed` · `not_found` · `conflict_locked` · `step_up_required`.
- **The generic-payload footgun, named and mitigated.** A generic `payload jsonb` invites the approval to
  become a client-supplied authority vector (*"approve this, amount = X"*). The payload is **server-computed
  at request time and re-derived and re-compared here**; the stored copy exists for the approver's UI, and the
  executing code trusts **nothing** in it. A mismatch is `stale`, **never an override**.
- **Tests.** `T-RPC-MONEY-06` (self-approval raises `self_approval`) · `T-RPC-MONEY-07` (a payload mutated
  between request and approval ⇒ `stale`, holds released, no refund) · `T-RPC-MONEY-08` (the approver of a
  payout may not be `payout_destination_set_by`).

### 17.3 `kernel.cancel_refund_request(p_request_id, p_reason_code, p_command_key)` — **DB-RPC** · `NEW RPC`

- **Role.** the requester · `has_org_role([org_owner, org_finance])` of the request's org · platform.
- **Preconditions.** Request `state='pending'`. **Locks:** **Ticket Atom(s)** ascending (release the overlay)
  → **Approval** (`FOR UPDATE`). **SSCAS:** single-aggregate + atom overlay.
- **Writes.** `kernel.approval_request` (→ `cancelled`), `kernel.tickets.resale_state := 'none'` per held
  atom, `kernel.admin_audit` (`refund.request_cancelled`). **Idempotency:** terminal state + `p_command_key`.
- **Result.** `{ status, request_id }`. **Errors.** `not_found` · `precondition_failed` ·
  `insufficient_privilege`.

### 17.4 `kernel.sweep_expired_refund_requests()` — **DB-RPC** · `EXEC: DEF` · `NEW RPC`

- **Purpose.** Release every `refund_hold` on a request past `expires_at` (= `created_at +
  refund.request_ttl_hours`). **This function is not optional** — without it a parked request is an
  **unbounded denial-of-admission on a paying customer's ticket**, which is precisely the failure C43 learned
  from p2p locks.
- **Actor.** `service_role`/scheduler only. Pattern: `market.sweep_expired_p2p_transfers` (§12.2).
- **Preconditions.** `state='pending' AND expires_at < now()`. **Locks & order:** requests processed in
  `expires_at` order with `SKIP LOCKED`; within each request, **Ticket Atom(s)** locked ascending
  `ticket_atom_id` (rank 5) → **Approval** (rank 5.5). Bounded batch.
- **Writes.** `kernel.tickets.resale_state := 'none'` per held atom, `kernel.approval_request` (→ `expired`),
  `kernel.admin_audit` (`refund.request_expired`), and a notification emit.
- **Result.** `{ swept_count, holds_released }`. **Retry:** re-entrant (acts only on still-`pending` rows).
- **Note.** The C43 p2p TTL sweep **cannot** release these — it selects from `market.p2p_transfer`, and a
  `refund_hold` atom has no p2p row. `refund_hold` needs its **own** sweep, and this is it.
- **Test.** `T-RPC-MONEY-09` — an expired request releases every hold and the atom scans again.

### 17.5 `kernel.list_org_payouts(p_org_id, p_venue_id, p_filters, p_cursor)` — **DB-RPC (read)** · `NEW RPC`

- **Purpose.** The **only** read path to `kernel.payout` for any org or venue role — the mechanism that makes
  O-3's read grant real. There is **no direct table SELECT grant** (RLS §7.9 note 15ᵇ).
- **Role.** `has_org_role(p_org_id, ['org_owner','org_finance'])` · `has_venue_role(p_venue_id,
  ['venue_finance'])` (**settlement-cause arm only**) · `is_platform`. `org_admin`, `org_member`,
  `venue_manager`, `venue_scanner`, the door session and `promoter` ⇒ `insufficient_privilege`.
- **Params.** `p_org_id` **required and untrusted**; `p_venue_id` used only by the venue arm; `p_filters` a
  **closed set** `{status[], cause[], date_from, date_to}`; `p_cursor` opaque. **No parameter may widen
  scope** — the filter is always applied *in addition to* `payee_org_id = p_org_id`.
- **The venue arm, and why it is narrow.** `kernel.payout` has **no `venue_id`**. A payout's venue is
  derivable **only** for `cause='settlement'`, via `cause_ref → venue.settlement_line →
  venue.settlement.venue_id`, and is **undefined** for `promoter_commission`, `market_sale`, and every
  identity-payee payout. The former unqualified *"V(own-venue payouts)"* was **not expressible against the
  physical schema at all.** `venue_finance` therefore reads settlement-caused payouts for its own venue and
  **zero rows of every other cause**.
- **Returns.** `payout_id, cause, cause_ref, amount_minor, currency, status, created_at, updated_at,
  settlement_id?` and a **`stripe_transfer_ref` presence boolean, not the ref itself**, for org roles — an
  operator needs *"has it left?"*, not the identifier. **Never bank data; the platform holds none.**
- **Locks:** **none** (read-only; no `FOR UPDATE`). **SSCAS:** n/a.
- **Errors.** `insufficient_privilege` · `not_found` (an unknown org id is **indistinguishable from
  unauthorized by design**, so the RPC is not an org-existence oracle).
- **Test.** `T-RPC-MONEY-10` — `venue_finance` sees settlement-cause rows for its own venue and nothing else;
  a tampered `p_org_id` yields `42501`, not another org's rows.

### 17.6 `kernel.list_org_refunds(p_org_id, p_venue_id, p_filters, p_cursor)` — **DB-RPC (read)** · `NEW RPC`

- Same shape and same scope rules as §17.5. **The join direction is part of the contract, not an
  implementation detail:** org scope resolves `kernel.refund.payment_id → kernel.payment_native.payment_id →
  order_id → venue.order.org_id`, filtered on `venue.order.org_id = p_org_id` (`venue.order.org_id` is a real
  column, so this is a two-hop join, not a search). `venue_finance`'s own-venue arm resolves through the same
  join filtered on `catalog.event_session → catalog.event.venue_id`.
- **Returns.** `refund_id, order_id, reason_code, amount_minor, currency, status, created_at,
  atoms_voided_count`. **Buyer PII is not in the projection.**
- **The `sale_id` arm MUST FAIL CLOSED.** A refund whose `payment_native` link is a `sale_id` (native resale)
  would resolve through `market.market_sale → listing → atom.org_id`. In MVP native resale is
  `resale_policy='off'` (Gate M), so that arm returns no rows — and it must **return no rows**, never fall
  through to an unfiltered read. **`T-RPC-MONEY-11`** asserts it.
- **Locks:** none. **SSCAS:** n/a.

### 17.7 `kernel.set_org_payout_destination(p_org_id, p_connect_account_ref, p_reason_code, p_command_key)` — **EDGE-FRONTED** · `NEW RPC` (contract written for the first time)

Referenced by RLS §7.2/§11, schema §1.2 and the dashboard, **and contracted nowhere** until now.

- **Role.** `has_org_role(p_org_id, ['org_owner'])` **only**, with **step-up**. `org_finance` is **excluded
  entirely** — under O-3 it holds payout-request authority, and one identity may not hold both halves of the
  named fraud primitive (*redirect the bank account, then release funds to it*). **Bound by
  EDGE-CALLER-JWT** — and this is the RPC where the rule bites hardest, because the step-up predicate reads
  `auth.jwt()`, which on a service-role client carries no `aal` and no `amr` at all.
- **What is actually being changed, which bounds the blast radius.** The platform **holds no bank details**;
  `kernel.organization.stripe_connect_account_ref` is an opaque Stripe Connect account id, and bank details
  are collected by Stripe's own KYC'd onboarding. So "change the payout destination" means *re-point the org
  at a different Connect account that has itself passed Stripe identity/bank verification* — a materially
  higher bar than typing an IBAN into a form. Consequently `before`/`after` in the audit row are Stripe
  account ids, which are safe to store: **no control here may ever cause bank numbers to enter the database,
  and none does.**
- **The control set, ranked by what it actually stops** (not by what sounds strongest):

  | # | Control | Stops | Cost |
  |---|---|---|---|
  | 1 | **SoD-1 identity split** — records `payout_destination_set_by`, and `request_org_payout` **rejects when `auth.uid() = payout_destination_set_by`, permanently for that destination**, not merely during the cool-down | the named fraud primitive, **structurally** | a single-principal org must escalate |
  | 2 | **Destination probation** — the **first** payout to a destination changed within `payout.destination_probation_days` is created `held`, releasable only by `is_platform(['platform_risk','platform_admin'])` via the existing `release_payout`. Reuses machinery that already exists; needs no new column | money leaving to a fresh destination unreviewed | a support touch on the first payout |
  | 3 | **Out-of-band notification** — on change, notify **every** `org_owner` and `org_finance` **including the actor**, by push *and* email, immediately, with a one-tap *"I did not authorize this"* that calls `hold_payout` on every pending payout for the org | a silent takeover | none |
  | 4 | **Step-up freshness** — `auth.jwt()->>'aal'` vs `authn.money_action_required_aal`, and the newest `amr` timestamp vs `authn.money_action_max_age_seconds` | session-riding, stolen refresh tokens | a re-auth flow + retry |
  | 5 | **Denial audit** — `kernel.record_money_denial` (§17.9) | *nothing on its own* — it is **how you find out** | one extra edge call on failure |
  | 6 | **Cool-down** — `payout_destination_locked_until` | a rushed attacker only | operator confusion if unexplained |

  **Note the ordering: the control that already exists (the cool-down) is the weakest in the set.** A
  cool-down is a *detection window*, not a control — it stops nobody willing to wait, and its value is
  entirely contingent on control 3. O-3's requirement that destination change be "strictly stronger than a
  payout request" is met by controls 1–4, **not** by the timer that exists today.
- **Step-up is enforced in the FUNCTION BODY, never in RLS.** Not because RLS cannot call `auth.jwt()` — it
  can — but because **the money path is not a table policy at all**: every money mutation is `EXECUTE` on a
  definer function (GP-1), so a table policy never runs. *Any design that says "enforce step-up in RLS" is
  describing a policy that will never be evaluated on the path that matters.*
- **The shippable position.** `authn.money_action_required_aal` ships at **`aal1`** and flips to `aal2` as a
  **config change, not a code change**, once staff MFA enrollment exists — nothing enrolls MFA today, so
  `aal2` on day one would lock every operator out. `aal1` freshness is not theatre: it defeats the most common
  real attack on a 90-day-refresh-token dashboard (an unattended or hijacked session) and forces an
  interaction the attacker must reproduce.
- **`UNVERIFIED:` whether this project's access tokens actually carry `amr` with per-factor timestamps.** No
  production access was used. **This must be checked against a real token before the predicate is
  implemented**; if `amr` is absent, freshness degrades to token age (`iat` + a shortened access-token TTL),
  which measures *token* age rather than *authentication* age and **must be labelled as such rather than
  described as "recent authentication."**
- **Locks & order.** **Organization** row `FOR UPDATE` (admin plane, outside the six money/custody ranks) →
  nothing else. **SSCAS:** n/a (single aggregate).
- **Writes.** `kernel.organization` (`stripe_connect_account_ref`, `payout_destination_set_by := auth.uid()`,
  `payout_destination_locked_until := now() + config('payout.destination_cooldown_hours')`),
  `kernel.admin_audit` (`org.payout_destination.change`, `subject_kind='organization'`, before/after = Stripe
  account ids, `reason_code` **mandatory**).
- **Errors.** `insufficient_privilege` · `step_up_required` · `precondition_failed` · `not_found`.
- **Tests.** `T-RPC-MONEY-12` (`org_finance` is refused) · `T-RPC-MONEY-13` (the setter is refused a
  subsequent `request_org_payout` **after** the cool-down elapses — the permanence of SoD-1) ·
  `T-RPC-MONEY-14` (a stale-`amr` token raises `step_up_required` and writes nothing).

### 17.8 `kernel.list_approval_requests(p_org_id, p_filters, p_cursor)` — **DB-RPC (read)** · `NEW RPC`

- **Role.** `has_org_role(p_org_id, ['org_owner','org_finance'])` · `is_platform`. The second approver's inbox.
- **Params.** `p_org_id` untrusted, re-checked; `p_filters` a closed set `{state[], action[], date_from,
  date_to}`. **Locks:** none. **SSCAS:** n/a.
- **Returns.** `request_id, action, subject_kind, subject_id, amount_minor, tier, state, requested_by
  (display), requested_at, expires_at, reason_code` — **and the evidence payload marked as evidence**, never
  as an authorization input.
- **Errors.** `insufficient_privilege` · `not_found`.

### 17.9 `kernel.record_money_denial(p_action, p_subject_kind, p_subject_id, p_error_code)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC`

- **Purpose.** Append a `*.denied` audit row **for an action that failed**. Exists because §0.3 writes audit
  **in the same transaction** as the action, and a failed predicate `RAISE`s — which rolls the transaction
  back and takes the audit row with it. **Postgres has no autonomous transactions.**
- **Why it matters:** repeated failed attempts to change a payout destination or fire a payout are the
  **single highest-value fraud signal in the system, and today they leave no trace at all.**
- **Actor.** `service_role` only; `REVOKE EXECUTE FROM anon, authenticated, public`. **No human path.**
  Called by the edge (`refund-execute`, `payout-execute`) **in a separate transaction** after catching
  `insufficient_privilege` / `sod_violation` / `step_up_required` from a money RPC.
- **Locks:** none. **SSCAS:** n/a. **Writes:** `kernel.admin_audit` (`<action>.denied`). **Idempotency:**
  none required — a denial is an event, and duplicates are informative rather than harmful.
- **Contains no payload from the failed call** beyond the four parameters, so a denial can never become a
  side channel for the data the denied call was refused.

### 17.10 `venue.open_door_manifest(p_session_id, p_reason_code, p_command_key)` — **DB-RPC** · `NEW RPC`

- **Purpose.** Open (or re-open) the session's offline door manifest and, **on the first open ever**,
  atomically engage the session's terminal transfer-freeze boundary.
- **Role.** `has_venue_role(venue_of_session,['venue_manager'])` OR
  `has_org_role_over_venue(venue,['org_owner','org_admin'])` OR `is_platform(['platform_admin'])`, live-
  rechecked. **`venue_scanner`, any door session, `venue_box_office`, every finance / marketing / promoter
  role, `platform_support` and `platform_risk` are denied (O-4).** Opening the manifest **freezes custody for
  an entire session** — that is a security boundary, and *the scanner may not create the boundary it works
  inside*. The operational objection is real (a manager may not be at the door at 11 p.m.) and the answer is
  **scheduling plus remote action** — the dashboard is online, so a manager can open from anywhere — not a
  weaker credential at the door. Residual ops risk recorded as RLS **MD-13**.
- **Params.** `p_session_id` (untrusted, re-resolved), `p_reason_code ∈ {doors_open, reopen_device_failure,
  reopen_operator, drill}` (validated), `p_command_key`. **Server-derived (C35):** `auth.uid()`, `opened_at :=
  now()`, `manifest_version`, `not_after`, `manifest_digest`, the entry snapshot. **No client timestamp is
  ever accepted.**
- **Preconditions.** Session exists and `status ∈ {scheduled, live}`; parent event `status ∈ {on_sale, live}`;
  `now() >= COALESCE(doors_at, starts_at) - config('door.manifest_early_open_window')` (early opening is
  permitted and encouraged for pre-sync at soundcheck, but not arbitrarily early); **no
  `kernel.door_freeze_override` is active for the session** — an override and an open manifest are mutually
  exclusive by construction.
- **Locks & acquisition order.** `catalog.event_session` **`FOR UPDATE`** (rank 1) → *[drain:
  `market.p2p_transfer` / `market.listing_native` `FOR UPDATE` (rank 4) → `kernel.tickets` `FOR UPDATE`
  ascending `ticket_atom_id` (rank 5)]* → inserts. Ascending, no inversion.
- **SSCAS.** `n/a (single-aggregate — Event/Session)`. The drain is a **bounded batch of the existing members
  #6-reverse and #7-reverse** (the unlock overlay) — the same construction that classifies
  `catalog.cancel_event` as a bounded batch of member #3. **The set stays closed at fifteen; no sixteenth
  member and no amendment.**
- **Idempotency.** Two-layer: a state guard (an `open` episode returns `noop_replay` with the **existing**
  `manifest_id`, issues no new `manifest_version`, and does **not** touch `door_open_at`) **plus**
  `UNIQUE(session_id, command_idempotency_key)`. Two managers pressing "Open doors" simultaneously: the first
  to acquire `FOR UPDATE` wins; the second blocks, re-reads, and returns `noop_replay`. **Both operators see
  "Door open."**
- **Writes.** `venue.door_manifest` (INSERT), `venue.door_manifest_entry` (INSERT N),
  `catalog.event_session.door_open_at` **via `catalog.engage_door_freeze` (first open only)**,
  `market.p2p_transfer` / `market.listing_native` (drained → `cancelled`, `reason_code='door_freeze'`),
  `kernel.tickets.resale_state` (→ `none`, via `kernel.unlock_ticket`), `kernel.admin_audit`.
- **Result.** `{ status, manifest_id, manifest_version, entry_count, opened_at, door_open_at,
  freeze_newly_engaged, drained_transfers, drained_listings }`.
- **Errors.** `insufficient_privilege(42501)` · `not_found` · `precondition_failed` (`session_terminal` |
  `event_not_live` | `too_early` | `override_active`) · `idempotency_replay`.
- **The snapshot and the boundary are ONE transaction**, which is what makes an offline scanner's 90-second-old
  snapshot exactly as safe as a fresh one: there is no interval in which the manifest has been read but the
  freeze is not yet in force — precisely the interval in which a transfer would strand a credential.
- **Tests.** `T-RPC-DOOR-09` (a drained atom then scans successfully — the end-to-end lockout regression) ·
  `T-RPC-DOOR-10` (every denied principal ⇒ `42501`, `door_open_at` unchanged) · `T-RPC-DOOR-11` (second open
  after a close creates a new episode and leaves `door_open_at` **byte-identical**) · `T-RPC-DOOR-12` (a
  listing whose sale is `paid_pending_transfer` is **not** drained).

### 17.11 `venue.close_door_manifest` · `kernel.grant_door_freeze_override` · `kernel.revoke_door_freeze_override` · `kernel.sweep_expired_door_overrides` — `NEW RPC` ×4

- **`venue.close_door_manifest(p_session_id, p_reason_code, p_command_key)`** — role as §17.10. **Does not
  unfreeze and does not touch `door_open_at`** — closing the door is not an unfreeze, and an operator reading
  "closed" as "back to normal" is the mistake the surface copy must prevent. Locks: session row `FOR UPDATE`
  (rank 1) → the manifest row. SSCAS n/a. No open episode ⇒ `noop_replay`, **never an error**. Writes the
  episode's `closed_at`/`closed_by`/`close_reason` and audit; **explicitly writes nothing to
  `catalog.event_session`**. `offline_pending_count > 0` is **surfaced, not blocking** — a lost device must
  never be able to pin a session open forever.
- **`kernel.grant_door_freeze_override(p_session_id, p_ticket_atom_id, p_reason_code, p_expires_at,
  p_ack_live_devices, p_command_key)`** — `is_platform(['platform_admin'])` **only**: an override defeats a
  safety property, so it requires authority **strictly above** the authority that engaged the freeze. **Hard
  precondition: no episode with `status='open'` exists for the session** — the admin must close it first, and
  *that* is what preserves the Door Safety Theorem (no custody move can commit while an offline manifest is
  armed, override or not). Also: `p_expires_at` within `config('door.max_override_interval')`, closed-set
  reason code, and `p_ack_live_devices` **must equal the current count of devices still inside their
  downloaded `not_after`** — a deliberate speed bump forcing the admin to look at the number before defeating
  a safety property. Locks: `catalog.event_session` `FOR UPDATE` (rank 1), which serializes against a
  concurrent open. SSCAS n/a. **Explicitly does NOT write `catalog.event_session`** — the historical boundary
  survives verbatim. Errors: `insufficient_privilege` · `precondition_failed` (`manifest_open` |
  `ttl_too_long` | `bad_reason_code` | `unacknowledged_live_devices`).
- **`kernel.revoke_door_freeze_override(p_override_id, p_command_key)`** —
  `is_platform(['platform_admin','platform_risk'])`. **Risk may *tighten* but not *grant*** — the role that
  can loosen a safety property is strictly narrower than the role that can restore it (freezer ≠ releaser).
  Terminal-state idempotent.
- **`kernel.sweep_expired_door_overrides()`** — `EXEC: DEF`, cron. **Emits notifications and closes the audit
  trail only.** Overrides expire arithmetically inside `is_transfer_frozen` (`expires_at > now()`), so **this
  sweep must never be load-bearing for correctness** — correctness that depends on a cron running is the
  failure class this whole area exists to prevent. **`T-RPC-DOOR-13`:** past `expires_at`,
  `is_transfer_frozen` returns true again **with no sweep having run**.
- **The residual, stated rather than glossed.** A device that is offline across a break-glass act cannot be
  reached: setting `not_after := now()` server-side does not shorten the `not_after` the device already
  downloaded. The bound is that downloaded TTL and nothing more. **Do not describe this residual as closed by
  the re-sync requirement — it is not.**

### 17.12 `catalog.engage_door_freeze(p_session_id, p_opened_at)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC`

- **Purpose.** The **sole writer** of `catalog.event_session.door_open_at`. Sets it iff currently NULL;
  otherwise a no-op returning the existing value. **Never NULLs it. Never changes a non-NULL value.**
- **Actor.** `service_role`/definer only. `REVOKE EXECUTE FROM anon, authenticated, public`. **Never
  client-callable and it appears in NO RLS EXEC row.** A trigger enforces the single-writer property
  independently of grants, so the guard survives a future RPC bug rather than only a future grant bug.
- **Why it exists at all:** `venue.*` writing `catalog.*` directly would be a cross-schema write outside the
  single-writer discipline. This mirrors `venue.record_scan → kernel.mark_ticket_scanned` exactly — the owning
  schema exposes a definer primitive and the calling schema invokes it in the same transaction.
- **Preconditions.** The caller holds `FOR UPDATE` on the session row — **asserted, not assumed**; the
  primitive re-takes it, a no-op re-entrant acquisition in the same transaction.
- **Locks:** session row (rank 1, re-entrant). **SSCAS:** n/a. **Result:** `{ door_open_at, newly_engaged }`.
- **Tests.** `T-RPC-DOOR-14` — a direct `UPDATE … SET door_open_at = NULL`, a backwards move, and a
  future-dated set all raise.

### 17.13 `venue.append_door_manifest_delta(p_session_id, p_atoms, p_op, p_cause_ref)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC`

- **Purpose.** Append to the open episode's delta log so a synced device's admissible set tracks changes made
  **after** the base snapshot. **Two operations only**, and both are **monotone in safety**:

  | `p_op` | Written by | Meaning | Why it is safe |
  |---|---|---|---|
  | `add` | `kernel.issue_ticket_atoms` (door sale · comp · import) | a newly minted atom becomes admissible | the atom is **new**: `credential_version = 0`, never transferred, and it **cannot** be transferred (the session is frozen). Its reference value cannot go stale, so it **can strand nobody** |
  | `revoke` | `kernel.void_ticket_atom` on any exempt path (§12.4c) | an atom ceases to be admissible | strictly **narrows** the admissible set; a device that misses it is no worse off than today, one that receives it is strictly safer |

  `add` can only admit an atom that is provably current; `revoke` can only refuse. **Neither can cause an
  offline door to admit something it should not** — which is why the delta log needs no freeze of its own and
  no new lock.
- **Actor.** `service_role`/definer only; same posture as §17.12. Never in an RLS EXEC row.
- **Preconditions.** An episode with `status='open'` exists. **If none exists the call is a SILENT NO-OP, not
  an error** — issuance and voiding must never fail because the door happens to be shut.
- **Locks & order.** **None of its own.** The caller already holds `FOR SHARE` on the session row (rank 1) —
  `issue_ticket_atoms` as the promoted form of the Event/Session read-gate member #1 already models,
  `void_ticket_atom` per §12.4c. The delta insert takes no further lock.
- **SSCAS.** `n/a` — one aggregate class (an Event/Session child), written under a lock the caller already
  holds. **Members #1 and #3 keep their existing numbers. No sixteenth member.**
- **Idempotency.** PK `(manifest_id, seq)` + `UNIQUE(manifest_id, ticket_atom_id, op)` — a replayed mint or
  void appends nothing.
- **Writes.** `venue.door_manifest_delta` (INSERT N), `venue.door_manifest.max_delta_seq` (advance).
- **The honest limit, stated rather than implied.** A door sale requires taking payment, which requires
  network, so the *selling* device is online by construction and can admit its own sale immediately. **A
  different scanner that is offline will refuse that ticket until it syncs.** Post-open issuance is
  *admissible online immediately, and offline only after the admitting device syncs*. That is an operational
  limit, not a safety property, and it belongs in the door runbook.
- **Tests.** `T-RPC-DOOR-15` (a mint with an open episode appends one `add` per atom, each with
  `credential_version = 0`; the CHECK rejects an `add` with a non-zero version — **the theorem made
  structural**) · `T-RPC-DOOR-16` (a mint with **no** open episode appends nothing and does **not** error).

*End of docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md. Design-only; no SQL, no function bodies. Companion to the physical
schema (deliverable #1), RLS spec (#3), and the Edge Function spec (#5, which picks up every EDGE-FRONTED item
flagged in §13), per SPEC_FOUNDATION §10.*
