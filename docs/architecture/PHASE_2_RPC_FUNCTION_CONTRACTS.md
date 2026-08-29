# Phase 2 — RPC / SECURITY DEFINER Function Contracts

**Status:** BUILD-READY DESIGN SPEC. **Design-only — NO SQL, no function bodies.** Each contract is written
so an implementing engineer can author a `SECURITY DEFINER` function from it **without making an architectural
decision**. Where a decision remained open it is flagged under §16 RECONCILIATION.

**§1–§16 are the core surface. §17 adds every `NEW RPC` from the eight Phase-2 delta specs, §18 is the
consolidated test register, and §19 lists what is AUTHORED here rather than transcribed — read §19 before
implementing anything in §17.20–§17.25, where the source specs were incomplete.**

> **Reconciliation pass (`AUTHZ-H3` · `AUTHZ-H3a/b` · `APPR-SUBJ-1/2` · `AUTHZ-DEM1` · `AUTHZ-CRM1/2`) — the
> five signature changes an implementer must not miss**, because each breaks a call site that currently
> compiles in prose:
> 1. **`kernel.assert_door_session`** gains `(p_door_session_id, p_session_token)` and **returns the bound
>    `(device_id, event_session_id)` instead of a boolean** (§1.1d).
> 2. **`venue.record_scan` / `venue.reconcile_offline_scans`** take a distinct **`p_actor_device_id`**,
>    supplied from that return value; `p_scan_meta.device_id` is **rejected**, not ignored (§9.4/§9.5).
> 3. **`venue.finalize_export` LOSES `p_cells_emitted` / `p_cells_suppressed`** — they are accumulated inside
>    the definer and cannot be supplied (§17.22).
> 4. **`venue.list_attendees` gains `p_reason_code`**, required on the platform arm (§17.22).
> 5. **`venue.retire_scan_device` is superseded by `venue.set_scan_device_status`** (§20.4.3, §20.13).
>
> **One contract is `⛔ BLOCKED`:** `venue.set_event_security_config` (§20.6.6) writes to a table that exists
> in no package. **`086` must not schedule it** until owner ruling `R-21`.

> **§20 is the SET CLOSURE, and it is the first thing to read if you are about to write SQL.**
> `PHASE_2_RLS_PERMISSION_SPEC.md` §11 is the complete statement of Phase-2 write authority, and §1–§19 of
> this document were a **proper subset** of it: **49 functions were granted EXECUTE, or scheduled as objects
> in migration plan §8, with no contract anywhere in the corpus** — including the whole native-marketplace
> write surface, the C33 key lifecycle, `catalog.set_platform_config` (every money threshold in the system),
> the Connect-onboarding writer (the precondition for every payout), and the inventory-hold expiry sweep
> (without which held capacity never returns to the counter). §20 contracts every one of them, reports the
> **reverse** difference — **14 contracts here that no EXEC row grants**, six of them `EXEC: DEF` custody or
> sweep primitives — and files what other specs must change in §20.14. **Nothing in §0–§19 is rewritten.**

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
session_id, door_session_id, token)` re-validating a **server-validated device assertion** against live tables — not from an edge
attestation of a human. A door RPC that accepted an edge-supplied `p_actor_identity` would be the same C35
violation wearing a different hat.

**A denied money action currently leaves no trace, and that is fixed here, not worked around.** §0.3 writes
the audit row **in the same transaction** as the action; a failed predicate `RAISE`s, which rolls the
transaction back and takes the audit row with it. Postgres has no autonomous transactions. **Repeated failed
attempts to change a payout destination or fire a payout are the single highest-value fraud signal in the
system, and they are invisible.** The edge therefore catches `insufficient_privilege` / `sod_violation` /
`step_up_required` from a money RPC and, **in a separate transaction**, calls `kernel.record_money_denial`
(§17.9) — **caller-authorized**, bound by EDGE-CALLER-JWT like every other money RPC: the edge makes this
call on the **caller's own `Authorization` client** — the same client it built for the call that was just
denied — so `actor_identity := auth.uid()`, and the function RAISES when `auth.uid()` IS NULL (`S-17`;
`C93`/`C106`). *This sentence previously read "`EXEC: DEF`, no human path" — superseded residue of the
pre-`S-17` contract, removed 2026-08-29 under `ID-5`/`P-6`; the classification above is the already-ratified
one, transcribed from §17.9's own body, not invented here.*

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
  a **sanctioned kernel custody writer**, enumerated in §0.7a.

#### 0.7a The sanctioned custody-writer set — enumerated, because *"the three kernel engines"* named a set smaller than the corpus contracts (`MB-6a`)

> **The prohibition is unchanged and is not narrowed here: no `market` or `venue` function writes
> `kernel.tickets` or `kernel.ticket_ownership_log` itself, ever.** What is corrected is the *permitted
> delegation set*. The clause read *"only via the three kernel engines"* — `issue_ticket_atoms`,
> `transfer_ticket_ownership`, `void_ticket_atom` (§7.1–§7.3) — while **seven** kernel functions are
> contracted as writers of `kernel.tickets` *(six at this subsection's first writing; `kernel.sweep_expired_ticket_atoms` — §12.5, `C109` — is the seventh, and its row below was added 2026-08-29 when the omission was found by the writer-parity pass)*, and three of them are the ones the door and market paths
> actually delegate to. Under the literal rule **§9.4, §8.1, §8.3, §17.10, §20.8.1 and §20.8.2 are all
> non-conformant**, every one of them correctly. A rule that five conforming contracts violate is not a rule
> an implementer or an assertion can apply, and the one contract that *did* write the atom directly (§9.5)
> was therefore indistinguishable from the five that did not. **That is the mechanism, not the typo.**

| Sanctioned writer | Contract | What it writes | Delegating callers |
|---|---|---|---|
| `kernel.issue_ticket_atoms` | §7.1 | mint: `kernel.tickets` INSERT + ownership-log `sequence=1` | `venue.finalize_primary_order` (§6.3), `venue.issue_comp` (§20.5.2) |
| `kernel.transfer_ticket_ownership` | §7.2 | custody move: ownership-log append + head + credential bump | `market.accept_p2p_transfer` (§8.2), `market.respond_offer` accept branch (§20.8.6) |
| `kernel.void_ticket_atom` | §7.3 | void leg: ownership-log `refund_void` + `kernel.tickets → voided` | `kernel.refund_primary_order` (§11.4), `catalog.cancel_event` (§4.4) |
| `kernel.lock_ticket` / `kernel.unlock_ticket` | §7.4 | `kernel.tickets.resale_state` overlay only; **no** ownership-log row | `market.create_p2p_transfer` (§8.1), `market.cancel_p2p_transfer` (§8.3), `market.create_listing` (§20.8.1), `market.cancel_listing` (§20.8.2), `venue.open_door_manifest` drain (§17.10) |
| `kernel.mark_ticket_scanned` | §7.5 | `kernel.tickets → scanned`; **no** ownership-log row (a scan is not a custody move) | `venue.record_scan` (§9.4), **`venue.reconcile_offline_scans` (§9.5)** |
| `kernel.sweep_expired_ticket_atoms` | §12.5 | `kernel.tickets → expired` (cron batch, actor `SN-SYSTEM`); **no** ownership-log row (expiry is presentational, §12.5) | **none — cron only.** *Row added 2026-08-29: the writer was contracted by a later pass (`C109`/`S-22`) with no row here, exactly the invisibility standing rule 2 warns about* |

**Two standing rules over that table, both structural rather than editorial:**

1. **Every `market`/`venue` contract that names `kernel.tickets` or `kernel.ticket_ownership_log` in its
   **Writes** line MUST name the sanctioned writer it delegates to, in that same line.** Naming it only in
   the **Locks** line is not sufficient: the Writes line is what a reader takes the write set from, and
   §20.8.2 carried the delegation in Locks and a bare `kernel.tickets.resale_state (→ none)` in Writes
   (`MB-6a`). A Writes line that names the table and not the writer reads as a direct write and is
   reviewed as one.
2. **Adding a member to this table is an amendment, not an implementation detail.** Each of the five carries
   a property that lives *only* in it — `mark_ticket_scanned`'s must-not-recheck-the-freeze property
   (§7.5; pinned structurally over `pg_proc.prosrc` by the migration plan) is the sharpest, because a caller
   that writes `state := 'scanned'` itself is **outside the assertion that pins it** and the assertion still
   passes. A sixth writer added without a row here would be invisible to exactly the same assertion.

**Nothing in the money plane is exempted by this table, and the table above is the CLOSED custody-writer set — seven functions.** *(The previous sentence read "nothing is added to it", which §12.5 had already falsified when a later pass contracted the expiry sweep without a row here; the row now exists above and the closure claim is re-stated over the corrected enumeration.)* **The complete `kernel.tickets` writer set is ELEVEN**: the seven above plus the four money RPCs next. `kernel.request_order_refund`,
`kernel.approve_refund_request`, `kernel.cancel_refund_request` and `kernel.sweep_expired_refund_requests`
(§17.1–§17.4) write `kernel.tickets.resale_state` themselves; they are `kernel.*` functions, so §0.7's
`market`/`venue` prohibition does not reach them and this pass does not re-route them. **It is flagged
rather than changed** — see §20.14 `R-24`, because the overlay primitives §7.4 exist precisely so that
`resale_state` has one writer pair, and four money RPCs bypassing them is the same shape one level in.

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

### 1.1c `kernel.is_promoter_for_event(p_event_id)` — **NEW RPC** (Phase 2D) — **CORRECTED (`AUTHZ-M10`)**
- **DB-RPC** (predicate helper), `STABLE`, `EXEC: authenticated`.
- **Purpose:** true iff the caller is a **live promoter of that event by either route** — link **or code**:
  ```text
  EXISTS ( SELECT 1 FROM venue.promoter p
            WHERE p.identity_id = auth.uid()        -- the ONLY column comparable to an auth uid
              AND p.status = 'active'
              AND ( EXISTS (SELECT 1 FROM venue.promoter_link l
                             WHERE l.promoter_id = p.promoter_id
                               AND l.event_id = p_event_id AND l.status = 'active')
                 OR EXISTS (SELECT 1 FROM venue.promoter_code c
                            JOIN venue.promoter_code_scope s USING (code_id)
                             WHERE c.promoter_id = p.promoter_id
                               AND c.status = 'active' AND s.event_id = p_event_id) ) )
  ```
  **Replaces the deleted `has_venue_role(…,[venue_promoter])` test everywhere.**
- **Two defects closed, and both are broken for the population the feature creates.**
  **(a) There is no column to bind `auth.uid()` to on `promoter_link`.** The old definition — *"a live
  `venue.promoter_link` exists for `(p_event_id, auth.uid())`"* — is unwritable: identity lives on
  `venue.promoter` (`identity_id uuid FK→auth.users`, schema §3.17); `promoter_link` carries `promoter_id`, a
  **`venue.promoter` primary key**. Any implementation that writes `promoter_id = auth.uid()` compares two
  unrelated uuid spaces and is **false for every row that will ever exist** — the predicate **fails closed**,
  and every promoter-gated surface is empty for everyone. The resolution is always **identity → promoter →
  links/codes**, never a direct comparison. **`T-RPC-AUTHZ-10`:** no function body contains
  `promoter_id = auth.uid()`.
  **(b) Resolving over links only makes a code-only promoter not a promoter.** The engine issues **codes** as
  well as links; a code-sourced attribution has `link_id IS NULL` **by design** (RLS §9.17); and a promoter
  given codes and no link is the ordinary shape for door and print distribution. Under a link-only predicate
  that promoter is **not a promoter to any gated surface** — the same defect §9.17 already fixed once on the
  attribution read path, still live on the event path. The code route is part of the predicate, not an
  enhancement to it. **`T-RPC-AUTHZ-11`:** a promoter with an active code scoped to the event and **no link at
  all** satisfies `is_promoter_for_event`.
- **Requires `venue.attribution.promoter_id` and `venue.promoter.status`** — filed as RLS §17 X-13; schema
  §3.17 lists neither today, so both the old predicate and the corrected one are currently unwritable, and
  only one of them is unwritable *and* silently false.
- A promoter holds **no row in any of the three authz tables**, so every administrative predicate returns
  false for them and deny-by-default (I-1) denies the capability without a policy having to say so. The only
  path from promoter to administrator is an explicit invitation or grant by an already-authorized principal —
  and **none of `grant_org_role` / `invite_org_member` / `accept_org_invite` / `grant_staff_role` /
  `grant_platform_role` takes a `promoter_id`, `promoter_link_id`, `attribution_id` or referral id as input**,
  so no promoter artifact can appear on the write path to a grant (**`T-RPC-ROLE-04`**).

### 1.1d `kernel.assert_door_session(p_device_id, p_session_id, p_door_session_id, p_session_token)` — **NEW RPC** — **EXEC: DEF** — **CORRECTED (`AUTHZ-H3`)**

> **`AUTHZ-H3` — THE DOOR'S ONLY GATE PROVED PROVISIONING, NOT POSSESSION. SIGNATURE CHANGE.**
>
> **The defect (schema §3.10a.0, edge §3.9a, filed as schema §13.7 `S-5` and edge recon #13).**
> `assert_door_session(p_device_id, p_session_id)` took **two identifiers and no secret**. Its two reads —
> `venue.scan_device.status='active'` and a live `venue.door_pin` for the session — are both **provisioning
> facts**; neither is a possession fact. Worse, `venue.door_pin` carries **no device column** (schema §3.10),
> so the PIN branch was satisfied by *any* live PIN for that session, including one issued to a different
> device. And `p_device_id` arrives on a `service_role` path where — as this contract's own warning says —
> **RLS is bypassed entirely and this function is the only gate**. Net: **anyone holding one live
> `(device_id, event_session_id)` pair — the two least secret values in the system, both of which appear in
> manifests, dashboards and logs — reached all four door capabilities unauthenticated**, and a session could
> not be revoked independently of the PIN because nothing consulted a token.
>
> **The fix gives the concentrated gate something to check. It removes no liveness check** — clauses 3 and 4
> below are the two old reads, unchanged, and they are why a bearer token here does **not** reintroduce the
> door-JWT problem ROLE_MODEL §7.3 rejects (schema §3.10a.2).

- **DB-RPC**. **Purpose:** the *entire* authorization surface of the door path. Raises unless a valid,
  unexpired, unrevoked door session **whose token the caller actually holds** binds that device to that
  session — and **returns the bound pair** so no caller downstream has to be trusted for it.
- **Params.** `p_device_id` uuid · `p_session_id` uuid · `p_door_session_id` uuid · `p_session_token` text.
  **All four untrusted.** `p_door_session_id` is the **non-secret selector** (`venue.door_session`'s PK);
  `p_session_token` is the verifier, returned once at mint and never re-returned.
- **Returns `(device_id uuid, event_session_id uuid)` — the BOUND pair, not a boolean.** This is the half of
  the fix that is not cosmetic. A boolean leaves the edge free to fabricate a device id for the very next
  call; returning the bound values means **the identity the ledger records is the identity the database
  resolved**. Every relay handler passes the returned `device_id` onward as `p_actor_device_id` (§9.4/§9.5),
  never a value from the request. **`p_device_id` is retained only as a cross-check that must equal the bound
  value** — a mismatch is a hard refusal and a Sentry event, because that shape is an attack, not a client
  bug — and is **never** the source of the device identity.
- **The four clauses, all live, on every call** (schema §3.10a.2, verbatim):
  1. `venue.door_session` row `p_door_session_id` exists, `status='active'`, `expires_at > now()`,
     `device_id = p_device_id`, `event_session_id = p_session_id`;
  2. `token_hash` matches `p_session_token` under a **constant-time** comparison;
  3. `venue.scan_device.status='active'` — **live**, as before;
  4. `venue.door_pin` (via the row's `pin_id`) `status='active' AND expires_at > now()` — **live**, as before.
- **Digest construction and the timing rule.** `token_hash = sha256(door_session_id::text || ':' ||
  secret)` — a **plain digest, deliberately not a slow KDF**: the token is ≥ 256 bits of server-generated
  CSPRNG that no human types, and putting a deliberately expensive function on **the scan hot path** is the
  one place in this system where that cost is unaffordable. The **opposite** substitution is the standard
  catastrophe: `door_pin.pin_hash` is low-entropy and keeps its slow KDF. Binding the selector into the
  digest means a verifier harvested from one row cannot be replayed against another id.
  **When `p_door_session_id` does not resolve, the function performs a dummy compare against a fixed decoy
  digest and returns the same failure**, so the absent-id and wrong-token paths cost the same. Unknown id ·
  wrong token · expired · revoked · session mismatch · unknown device return **the same error and the same
  timing budget** — the anti-enumeration obligation that previously sat only on the PIN attempt now sits
  here, where every relay call lands.
- **Reads:** `venue.door_session` (by PK), `venue.scan_device`, `venue.door_pin` — **live**.
  **Writes:** `venue.door_session.last_seen_at`, **throttled** to at most once per
  `config('door.session_touch_interval')` — a write on every scan would put a row update inside the
  admission transaction. **Locks:** none. **SSCAS:** n/a (admin/door plane; outside the six ranks — the set
  stays closed at fifteen).
- **Actor:** none. **`auth.uid()` is NULL on this path**, by design. The door client never talks to PostgREST:
  it calls the `door-session` edge function, which holds `service_role` and invokes the definer RPC. The
  Postgres principal is a machine identity acting on a **verified possession** assertion, never on a client
  claim.
- **Errors.** One class, deliberately: `insufficient_privilege(42501)` with a single opaque reason for all
  six failure shapes above. **`not_found` is never returned** — distinguishing "no such session" from "wrong
  token" is the enumeration oracle the dummy compare exists to close.
- **Tests.** `T-RPC-DOOR-30` (**the `AUTHZ-H3` regression, written as a negative**: a call carrying a valid
  `device_id` and `event_session_id` and **no token** — the exact call that succeeded before this fix —
  raises) · `T-RPC-DOOR-31` (a token minted for device A is refused for device B, and one minted for session
  S1 for S2, **with the same error as an unknown id**) · `T-RPC-DOOR-32` (revoking the **PIN** fails the next
  call by clause 4 **and** leaves no `status='active'` session row — RV-1, both halves).
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

> **`AUTHZ-H3a` — TWO PASSES DESIGNED THIS CREDENTIAL INDEPENDENTLY AND DID NOT CONVERGE. BOTH
> DIVERGENCES ARE RESOLVED HERE, IN FAVOUR OF THE PASS THAT OWNS THE TABLE.**
>
> **(a) The selector's name and physical form.** The edge spec (§3.9a) specifies a **separate `session_ref`
> text column** as the lookup handle, with `token_hash = sha256(session_ref || ':' || secret)` and a wire
> format `Authorization: DoorSession <session_ref>.<secret>`. The schema spec (§3.10a.1) — which **owns the
> table** — defines **no `session_ref` column at all**: it makes `door_session_id` (the uuid PK) *"the
> non-secret selector, returned to the client alongside the secret"*, and files the predicate to this
> document as `assert_door_session(p_device_id, p_session_id, p_door_session_id, p_session_token)`.
> **Resolved to `p_door_session_id`.** A parameter that selects a row by a column the table does not have is
> unimplementable, and inventing the column here would be this document authoring schema. The two designs are
> otherwise identical — a non-secret selector plus a high-entropy verifier, digest-bound to each other — so
> nothing but the spelling changes. **Filed to the edge owner (§20.14 `R-19`):** §3.9a's token format becomes
> `DoorSession <door_session_id>.<secret>`, its `session_ref` prose becomes `door_session_id`, and its
> derived rate-limit principal becomes `uuidv5(NS_DOOR_SESSION, door_session_id)`. *(Alternative, if the
> owner prefers the edge spelling: the schema owner adds `session_ref text UNIQUE NOT NULL` to §3.10a.1 and
> this signature takes `p_session_ref`. It is a one-column decision either way — but it must be made in the
> schema, not here.)*
>
> **(b) Refresh.** Edge §3.9a specifies a `/refresh` route that extends `expires_at` **without re-presenting
> the PIN**; schema §3.10a.4 **deliberately declines** to add one, on the ground that *"a refresh path that
> extends a session without re-presenting the PIN is a path that outlives the PIN — precisely the property
> ROLE_MODEL §7.3 refuses."* **Resolved in favour of the schema pass: there is no `venue.refresh_door_session`
> contract, and none is authored here.** `/refresh` is served by **re-minting** against the PIN
> (§9.6), which re-runs the rate limit and re-reads every liveness fact. The functional cost is one PIN
> re-entry when a session ages out; the alternative is a bearer credential whose lifetime is decoupled from
> the credential it was minted against, which is the whole class of defect `AUTHZ-H3` just closed.
> **Filed to the edge owner (§20.14 `R-19`).**

### 1.1e `kernel.money_role_grant_matured(p_org_id)` — **NEW RPC** — **AUTHORED HERE FOR THE FIRST TIME (`AUTHZ-C1C`)**

> **`AUTHZ-C1C` — THE CONTROL THAT CLOSES `C58` WAS INVOKED BY FOUR CALL SITES AND DEFINED BY NONE.**
>
> **The defect.** Ratification row **C58** closes *"the money-plane SoD counterparty is mintable by the very
> role that needs one"* with a **new predicate helper**, `kernel.money_role_grant_matured(org_id)`. That
> helper is bound as a conjunct in **§10.3** (`request_org_payout`), **§17.1** (`request_order_refund`, org
> arm), **§17.2** (`approve_refund_request`, both `org` arms) and **§17.7**
> (`set_org_payout_destination`); RLS §2.2 lists it among the sanctioned helpers and states that helpers are
> *"defined as SECURITY DEFINER helpers in the RPC spec"*; RLS §11.2 gives it an EXEC row. **This document
> defined §1.1 … §1.1d and stopped.** So the predicate that makes SoD-1 and SoD-2 mean what they claim had
> **four callers and no contract** — no signature, no volatility, no grant class, no statement of what
> *matured* means, and above all **no statement of what it returns when the config key is absent**, which is
> the one behaviour every other fail-to-safe predicate in this corpus writes down (`AUTHZ-M3`, `AUTHZ-M4`,
> `AUTHZ-M8`).
>
> **Why an undefined predicate is worse here than elsewhere.** By ruling **GP-3a** every money mutation is
> `EXECUTE` on a definer function, so **there is no table policy to review** on this plane. An implementer
> reaching four call sites that name a function nothing defines writes the function, and the cheapest
> spelling — `now() - granted_at > interval` against a NULL config — evaluates to **NULL**, which is not
> true, which under `NOT (immature)` is **admit**. The failure is silent, it is on the highest-value money
> writes in the system, and nothing downstream would see it.

- **DB-RPC** (predicate helper), **`STABLE`**, **`SECURITY DEFINER`**, owner `postgres`, `search_path` pinned
  per 066, **`EXEC: authenticated`** (explicit `REVOKE EXECUTE FROM public, anon` then
  `GRANT EXECUTE TO authenticated`, per 067 — RLS §11.2).
- **Signature.** `kernel.money_role_grant_matured(p_org_id uuid) RETURNS boolean`. **One argument, and it is
  the scope, not the actor.** There is no actor parameter and there may never be one: the identity tested is
  **`auth.uid()`, server-derived inside the body** (**C35** — *the kernel authorizes the principal itself; a
  caller-supplied actor is never trusted*). A caller that could pass the identity could pass a matured one.
- **Actor:** `auth.uid()`, server-derived. **Params:** `p_org_id` — **untrusted** (a scope id, exactly as in
  `has_org_role`; passing a scope the caller holds no grant in returns **false**, never an error).
- **Reads:** `kernel.org_member` (**live**, by `(org_id, identity_id)` — the row's `role` and `granted_at`)
  and `catalog.platform_config` (the `authn.money_role_maturity_hours` key). **Never a JWT claim** (C9 / RLS
  I-5), like every other helper in §2.2 — a stale token cannot assert a maturity it does not have, and a
  revoke or a re-grant takes effect on the next call.
- **Writes:** none. **Locks:** none. **SSCAS:** n/a. **Idempotency:** n/a (pure).
- **Result:** boolean. **Never raises** — it is a predicate, and the *caller* raises (see *Errors*, below).

- **The maturity predicate, stated once and derived, not chosen** (**C58** ratified form · RLS §11.3a ·
  schema §1.13.4 · RLS §17 `X-11`):

  ```text
  -- 1. READ THE KEY FIRST, AND FAIL CLOSED ON IT BEFORE ANY ARITHMETIC.
  v_hours := (SELECT value FROM catalog.platform_config
               WHERE key = 'authn.money_role_maturity_hours'
               ORDER BY version DESC LIMIT 1);          -- current version; see the pinning note
  IF v_hours IS NULL THEN RETURN false; END IF;         -- absent, NULL or unparseable => NO grant is mature

  -- 2. THE GRANT MUST BE A MONEY GRANT, AND IT MUST BE OLD ENOUGH.
  RETURN EXISTS (
    SELECT 1
      FROM kernel.org_member m
     WHERE m.org_id      = p_org_id
       AND m.identity_id = auth.uid()                   -- server-derived; C35
       AND m.role IN ('org_owner','org_finance')        -- the org-plane money roles, schema §1.13.4
       AND m.granted_at <= now() - make_interval(hours => v_hours)
  );
  ```

  **Four things about that shape are load-bearing.**
  1. **`granted_at`, never `created_at`.** `kernel.org_member.role` is single-valued and changed by `UPDATE`
     (schema §1.3), so `created_at` records **when the person joined the org**, not when they acquired money
     authority. A two-year member promoted to `org_finance` this morning passes a `created_at` test
     trivially — which is the attack, not the control. `granted_at` is set on INSERT by `accept_org_invite`
     and **re-set by `change_org_role` whenever the new role is a money role** (RLS §17 `X-11`): a promotion
     into `org_finance` starts a fresh clock, **including a lateral `org_finance` → `org_owner` move**, and a
     move to a **non**-money role does not (there is nothing to time).
  2. **The key is read and rejected on its own line, before any comparison.** This is the `AUTHZ-M4` lesson
     applied one predicate over: `now() - NULL` is NULL, `granted_at <= NULL` is NULL, and **whether NULL
     admits or denies is decided by whether the implementer wrote `matured` or `NOT immature`.** One spelling
     is a lockout and the other is a silent bypass of the control on the highest-value money write in the
     system. The early return removes the question rather than answering it. **A body that reaches
     `make_interval` with a NULL is a defect regardless of what it then returns.**
  3. **`EXISTS`, not a count and not a join.** The org grant key is `(org_id, identity_id)` — at most one row
     — so this is a primary-key point probe, which is why `STABLE` is honest and why the helper costs the
     same on the hot path as `has_org_role`.
  4. **The money-role set is exactly `{org_owner, org_finance}`.** No `venue.staff_role` label holds money
     authority (schema §1.13.4), so no venue label is comparable here, and the labels appear **only** as
     elements of the `IN` list inside this helper's own body — which is what `T-RLS-ROLE-02` clause (c)
     permits and what it forbids everywhere else.

- **THE WINDOW ITSELF IS AN OWNER DECISION, RECORDED HERE AND NOT MADE HERE (`MD-14`).** The **key** ships
  regardless (`078`, X-12/R-18); the **number** does not exist yet, and this contract does not invent one.
  RLS `MD-14` records the admissible range as **24–72 hours** with the two failure directions stated; both
  are real and neither is a default:

  | Direction | What it costs |
  |---|---|
  | **Too short** (hours) | The attack becomes *"mint the counterparty, wait until tomorrow"* — pre-meditation, but not much of it. The control degrades toward the cool-down it was designed to outrank (§17.7 control 6), which stops nobody willing to wait |
  | **Too long** (a week+) | A genuine new hire cannot be the second half of a dual-control pair for their whole first week, so the org is a **single-money-principal org** for that window and every refund and payout escalates to platform review under `MD-5`. The cost is real, it is operational, and it is paid by the honest case |

  **The parameter, not the value, is what this contract fixes.** An implementer who needs a number before the
  owner rules must seed the key at the **restrictive** end of the range and record the seed as provisional —
  never leave it unseeded, because unseeded is *"nobody can approve anything"* (correct, but it presents as
  a total money-plane outage rather than as a missing decision).

- **Fail-closed behaviour, in all four directions it can fail.**
  1. **Key absent, NULL or unparseable ⇒ `false`.** Binding, X-12: *no grant is mature*. **The test deletes
     the config row rather than setting it to `0`**, because a missing seed and a seeded `0` behave
     identically only if the early return is actually there.
  2. **No `kernel.org_member` row for `(p_org_id, auth.uid())` ⇒ `false`**, not an error. The caller's role
     test has already failed or is about to; this helper is a **conjunct**, never the thing that reports a
     missing grant.
  3. **A row at a non-money role ⇒ `false`.** An `org_admin` is not made mature by longevity, because it was
     never a money principal.
  4. **`auth.uid()` NULL (a `service_role` invocation) ⇒ `false`.** The helper does not degrade on the edge
     path; **EDGE-CALLER-JWT** already requires the caller's JWT to reach the RPC, and `T-RLS-EDGE-01`
     asserts the raise. A predicate that returned `true` for a machine identity would hand the whole control
     to whatever holds the service key.

- **Never the sole gate, and never applied to a stop.** Two standing constraints, both from C58:
  - **Conjunct only.** It sits **beside** the role test, never in place of it (`has_org_role(...) AND
    money_role_grant_matured(...)`). A mature grant is not an authority; it is a property of one.
  - **Requesters and approvers, denials and cancels.** It binds **both halves of both primitives** — the
    destination **setter** (§17.7) as much as the payout **requester** (§10.3), the refund **requester**
    (§17.1) as much as the refund **approver** (§17.2) — because *applied to one half of a pair it is applied
    to neither*: a fresh account simply moves to the other side. And it is **never** applied to
    `approve_refund_request`'s **deny** branch, to `cancel_refund_request` (§17.3), to
    `sweep_expired_refund_requests` (§17.4) or to `hold_payout`. **A control that blocks *stopping* a payment
    is a control pointed the wrong way.**

- **Errors — the helper raises nothing; the CALLER raises `sod_violation`.** All four call sites raise
  **`sod_violation`**, **not** `insufficient_privilege` and **not** `precondition_failed`: the role is
  genuinely held, and a permission error sends the operator to re-check a grant that is correct.
  > **Supersedes schema §13.7 `S-3`'s spelling.** `S-3` filed this precondition as
  > `precondition_failed('money_role_too_new')`. Four call sites (§10.3, §17.1, §17.2, §17.7) and the
  > behavioural tests (`T-RLS-MONEY-06`, `T-RPC-AUTHZ-05`/`-07`) say `sod_violation`, and the argument is
  > stated at each one. **`sod_violation` stands; `S-3`'s spelling is withdrawn as a divergence, not a second
  > option** — two error codes for one predicate is how a UI ends up telling an operator two different things
  > about the same refusal. Recorded as ratification row **D16**.

- **Interaction with the global lock order (§0.4): it adds no edge, and the residual is stated rather than
  assumed away.** The helper takes **no lock** and reads two tables that are **outside the six money/custody
  ranks** — `kernel.org_member` (admin plane, `077`) and `catalog.platform_config` (`078`). It is therefore
  callable at any point in any caller's lock sequence without perturbing it, and it is **evaluated before the
  first money-plane lock is taken** at all four sites, so a caller that fails it acquires nothing.
  **The residual, named:** because `kernel.org_member` is not locked, a `change_org_role` committing between
  the caller's snapshot and its commit is not observed, and the helper answers as of the transaction
  snapshot. **Three of the four race directions fail closed** — a promotion *into* a money role is invisible
  to an older snapshot, which still sees the non-money role and returns `false`; a revoke likewise. **One
  direction is open for the duration of one transaction**: a money→money re-grant (`org_finance` →
  `org_owner`, which resets the clock) committing inside the window lets the caller pass on the pre-reset
  `granted_at`. It is bounded by the caller's transaction, the re-grant is itself an audited act by an
  already-authorized principal, and **closing it would require `kernel.org_member` to enter the global lock
  order — an amendment to a ratified invariant, which this contract does not make.** Filed at §20.14 `R-23`.
- **Config version pinning.** `kernel.approval_request.config_versions` pins the `(key, version)` pair of
  **every** threshold a parked request was evaluated under, and `authn.money_role_maturity_hours` is one of
  them. **The helper itself always reads the CURRENT version** — maturity is a property of the caller at the
  instant they act, not of the request they are acting on, and an approver must be mature **now**, not as of
  whenever the requester filed. This is the one deliberate asymmetry with `AUTHZ-M3`'s support cap, which
  *is* pinned, because a cap is a property of the request. Stated so an implementer does not "fix" one into
  the other.
- **Forbidden.** Any body that hand-rolls this comparison instead of calling the helper; any caller that
  passes an identity; any use as a **sole** predicate; any application to a deny, cancel, sweep or hold path.
- **Tests.** **`T-RPC-AUTHZ-17`** (the helper set is **exactly** the ten of §1.1–§1.1e — see RLS
  `T-RLS-ROLE-06`) · **`T-RPC-AUTHZ-18`** (with `authn.money_role_maturity_hours` **deleted from
  `catalog.platform_config`** — the state a missed seed produces, **not** set to `0` — the helper returns
  `false` for an `org_owner` whose grant is a year old; asserted **on the helper directly**, because
  `T-RLS-MONEY-07` asserts it only through the callers and would pass on a helper that raises) ·
  **`T-RPC-AUTHZ-19`** (structural, over `pg_get_functiondef`: the set of functions calling
  `money_role_grant_matured` is **exactly** `{request_order_refund, approve_refund_request,
  request_org_payout, set_org_payout_destination}` — a fifth caller is an over-application and a missing
  fourth is the half-pair defect C58 names) · `T-RPC-AUTHZ-05` and `T-RPC-AUTHZ-07` (the two behavioural
  tests, both of which **perform the mint through the real `invite_org_member` / `accept_org_invite` path**,
  because the mint is the attack) · `T-RLS-MONEY-06`, `T-RLS-MONEY-07`.
- **Package — SEAM-1 computed, not chosen: `078`.** The helper reads `kernel.org_member` (created by
  **`077`**) and `catalog.platform_config` (created, with the `authn.money_role_maturity_hours` seed, by
  **`078`**), so `max(077, 078) = 078`. **It is not authored in `077` beside `has_org_role`**, which reads
  only `kernel.org_member`: doing so would be a forward reference `077 → 078` to a table and a seed row that
  do not exist yet — the same shape SEAM-1 caught at `079 → 085`, `085 → 088` and `086 → 087`. `078` already
  depends on `077`, so no new dependency edge is created and **no package is added, renamed or renumbered**
  (the canonical band stays `076`–`091`). Recorded in plan §8 `078` and in the package registry.
- **Policy:** none, and none is possible — see §0.8.

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

> **Freeze clause (`OR-17`, F-6):** refuses when the caller's `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).
- **Purpose:** apply to create an org; caller becomes its first `org_owner`. **Actor:** any `authenticated`.
  **Role:** none beyond authentication.
- **Params:** `p_legal_name`,`p_display_name`,`p_command_key` (all **untrusted**). **Server-derived:**
  `auth.uid()` → first owner; `status:='applied'`; `home_region:='us-east'`.
- **Preconditions:** names non-empty. **Locks:** none cross-aggregate (inserts a new org + its owner row).
  **SSCAS:** n/a (single new aggregate). **Idempotency:** `p_command_key` (dedupe the apply).
- **Reads:** — . **Writes:** `kernel.organization` (INSERT, status `applied`), `kernel.org_member` (INSERT
  `(org_id, auth.uid(), org_owner)`), `kernel.admin_audit` (`org.create`).
- **Result:** `{ status, org_id }`. **Failure:** `idempotency_replay`. **Forbidden callers:** anon.

> ### `AUTHZ-C1B` — THE MONEY-PLANE COUNTERPARTY IS MINTABLE BY THE ROLE THAT NEEDS ONE
>
> **Read this before §2.2–§2.5, because it is a property of the four of them together and of none of them
> individually.** Every money separation-of-duties primitive in the corpus compares two `auth.uid()` values:
> **SoD-1** rejects `auth.uid() = organization.payout_destination_set_by` (§17.7); **SoD-2** requires
> `approved_by <> requested_by` (§17.2). **Both are satisfied by any two distinct uids — and the RPCs below
> mint uids.**
>
> `invite_org_member` and `change_org_role` guard exactly **tier** (an `org_admin` may not act at `org_owner`
> tier) and **self** (I-11). **`org_owner` is the top tier, so neither guard binds it.** One `org_owner`
> invites a second account they control at `org_finance` — permitted, it is below them and is not self —
> accepts it (`accept_org_invite` authorizes on *being the addressed invitee*, and the invitee is them), and
> **now holds both halves of both primitives.** The out-of-band notice §17.7 relies on goes to *"every
> `org_owner` and `org_finance`"* — **i.e. to both of the attacker's own accounts.**
>
> **The corpus reasons about second-account evasion exactly once — for promoters** (§1.1c's `T-RPC-ROLE-04`:
> no grant RPC accepts a promoter artifact, so a promoter cannot walk into an administrator role) — **and
> never for the money plane**, where the same evasion is worth money rather than attribution.
>
> **The fix is NOT here.** Blocking the invite would be wrong: an org genuinely needs to add finance staff,
> and a headcount rule (*"≥2 money principals"*) is satisfied by the same attack, because it counts accounts
> and accounts are what the attacker mints. **The fix is `kernel.money_role_grant_matured(org_id)`, applied at
> the money primitives** (§17.2, §17.7, `request_org_payout`, §17.1's org arm): a money-role grant younger
> than `authn.money_role_maturity_hours` **cannot approve and cannot request**, though it keeps every
> operational capability it has. **Maturity prices the attack in the one currency an attacker cannot mint:
> elapsed time** — during which destination probation, the out-of-band notice and the approval queue are all
> live and visible to any *pre-existing* second principal.
>
> **What the three RPCs below owe it:** `kernel.org_member.granted_at` (RLS §17 X-11), written by
> `accept_org_invite` and **reset by `change_org_role` whenever the new role is a money role** — a promotion
> into `org_finance` starts a fresh clock; a lateral move to a non-money role does not. Without the column the
> predicate is unwritable and SoD-1/SoD-2 remain satisfiable by a counterparty the attacker minted.

### 2.2 `kernel.invite_org_member(p_org_id, p_invitee_ref, p_role, p_command_key)` — **DB-RPC**
- **Purpose:** invite an identity/handle to an org at a scoped role. **Role:** `has_org_role(p_org_id,
  [org_owner, org_admin])`; an `org_admin` **cannot** invite at `org_owner` (tier guard); **no self-invite to
  a higher tier** (I-11).
- **`AUTHZ-C1B`:** inviting at a **money role** (`org_owner`, `org_finance`) is permitted and unchanged — the
  grant simply starts immature. **The audit row records the money-role class**, so an invite → accept →
  immediate-approval attempt is a legible pattern in `kernel.admin_audit` rather than three unrelated rows.
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

> **Freeze clause (`OR-17`, F-6):** refuses when the caller's `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).
- **Purpose:** invitee accepts → becomes an `org_member` at the invited role. **Actor:** the **invitee**
  (`auth.uid()` must match the resolved invitee). **Role:** none beyond being the invitee.
- **Params:** `p_invite_id`,`p_command_key` (untrusted). **Server-derived:** `auth.uid()`.
- **Preconditions:** invite exists, pending, not expired, addressed to `auth.uid()`. **Locks:** the invite +
  org roster row (`FOR UPDATE`). **SSCAS:** n/a. **Idempotency:** `p_command_key` + invite terminal state.
- **Writes:** `kernel.org_member` (INSERT/activate role, **`granted_at := now()`** — `AUTHZ-C1B`),
  `kernel.org_invite` (→ accepted), `kernel.admin_audit` (`org.invite.accept`). **Result:**
  `{ status, org_id, role }`. **Failure:** `not_found`, `precondition_failed` (expired / wrong invitee).
  **Forbidden callers:** anyone but the addressed invitee.
- **`granted_at` is the maturity clock and is set HERE, not at invite.** The invite is a proposal the invitee
  may sit on for days; the grant exists from acceptance. Setting the clock at invite time would let an
  attacker pre-age a counterparty by inviting early and accepting at the moment of the attack — which is the
  same attack with a scheduler.

### 2.4 `kernel.change_org_role(p_org_id, p_identity_id, p_new_role, p_command_key)` — **DB-RPC**
- **Purpose:** change a member's org role (wraps schema `grant_org_role`/`revoke_org_role` UPDATE path).
  **Role:** `has_org_role(p_org_id, [org_owner, org_admin])`; `org_admin` cannot set/anyone to `org_owner`;
  **no self-promotion** (I-11).
- **Params:** `p_org_id`,`p_identity_id`,`p_new_role`(org enum),`p_command_key` — untrusted. **Server-derived:**
  `auth.uid()`. **Preconditions:** target is a member; **the "≥1 `org_owner`" invariant** — cannot demote the
  last owner. **Locks:** org roster (`FOR UPDATE`), re-count owners under lock. **SSCAS:** n/a.
- **Writes:** `kernel.org_member` (UPDATE role; **`granted_at := now()` whenever `p_new_role` is a money role
  and the previous role was not** — `AUTHZ-C1B`), `kernel.admin_audit` (`org.role.change`). **Result:**
  `{ status }`. **Failure:** `precondition_failed` (last-owner / tier), `insufficient_privilege`. **Forbidden
  callers:** org_member/finance; self-promotion.
- **Why the clock resets on promotion into money and not on every change.** The maturity window protects the
  **money** capability, so it must start when that capability is acquired — otherwise an `org_owner` invites a
  second account as `org_member` (a benign role, no money authority, nobody looks), waits out the window, and
  promotes it to `org_finance` the instant it is needed, arriving with a fully matured grant. A lateral move
  between non-money roles, or a demotion, does not reset it: nothing is being acquired.

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

> **Freeze clause (`OR-17`, F-1):** refuses when the caller's `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).
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
> physical function names with these as documented aliases. **This convention is extended to every divergent
> name in the corpus by the register at §20.13, which is the canonical namer** — *"two names for one function
> produces two functions or none"* — and `T-RPC-SET-02` asserts exactly one physical function per row of it.
>
> **The fourth write authority schema §3.5 names for `venue.inventory_hold` — the expiry sweep — is
> contracted at §20.3.3**, and it was contracted nowhere before. Without it a hold never leaves `active`, so
> `held` is never returned and an abandoned checkout removes inventory from sale permanently.

---

## 6. PRIMARY ORDER

### 6.1 `venue.create_primary_checkout(p_session_id, p_items, p_hold_ids, p_command_key)` — **DB-RPC** *(schema `create_order`)*

> **Freeze clause (`OR-17`, F-1):** refuses when the caller's `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).
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

### 6.3 `venue.finalize_primary_order(p_order_id, p_payment_id, p_command_key, p_instrument_fingerprint text DEFAULT NULL)` — **DB-RPC (SSCAS member #1)**

> **Freeze clause (`OR-17`, F-1):** refuses when the order's buyer's `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).
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
  `kernel.payment_native` (link order↔`public.payments`, **including `instrument_fingerprint :=
  p_instrument_fingerprint`** — the promoter self-deal detector's only input; PROMO §1.8). `venue.order_item`
  becomes IMM. **`p_instrument_fingerprint`** is the Stripe instrument fingerprint of the SUCCEEDING charge,
  supplied by the webhook edge (edge §4 `native_primary`); **untrusted, opaque, never validated, never
  logged; NULL when unavailable** — NULL is "no signal", never "no match" (PROMO §1.8), and a NULL never
  delays or fails issuance. **Ordering, load-bearing: the `kernel.payment_native` INSERT precedes the
  `resolve_order_attribution` call below**, so §17.14's read sees the current order's fingerprint
  in-snapshot — the resolver's signature is SEAM-2a-frozen at `(p_order_id)` and can never take it as a
  parameter. *(Added 2026-08-29 — the column had ZERO contracted writers while being read by §17.14 and
  scheduled by three documents; every alternative dataflow is closed by a named ruling: OBS-1 forbids the
  `public.payments` stash, `R-34` closes the writer pair at two, the AO posture forbids post-hoc UPDATE,
  SEAM-2a forbids the resolver parameter. Contract omission repaired, not new behavior; `C112` discipline
  moves the column to `085` with this writer.)*
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
> `lock_ticket`/`unlock_ticket`/`mark_ticket_scanned` mutate atom overlays. **The ownership LOG has exactly
> these three writers. The atom HEAD (`kernel.tickets`) has ELEVEN — the seven of §0.7a's closed table plus
> the four money RPCs (§17.1–§17.4) that write `resale_state` themselves (flagged at §20.14 `R-24`/`R-25`).**
> *(This note previously read "No other code writes custody", which eight contracts in this same document
> falsified; corrected 2026-08-29 to the enumerated form — `OR-7`: count follows enumeration.)*

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
  `from_identity=NULL`, `cause`, `credential_version_after=0`, `state_transition`), `venue.inventory_batch`**`(_shard)`**
  (`sold += N` — *the shard conversion was absent from this line while §5.3/§5.5/§20.5.x all carry it; added 2026-08-29, red-team P1-2: a mint that converts only the batch drifts the sharded draw into permanent phantom holds*), `venue.inventory_movement` (`issue`). **No secret written** (C33 — only `signing_key_id`).
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
  **belongs to the buyer** (`p_to_identity`) and the `market.listing_native` is `active` (offer accept) or `reserved` under this sale (buy-now, §20.8.10) at the market caller's entry, re-validated under the listing lock that caller already holds; **the client-passed
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
  `signing_key_id` re-pinned), `kernel.payment_native` (link, native sale — **born with
  `instrument_fingerprint NULL`: there is no webhook context at transfer time, and NULL = no-signal per
  PROMO §1.8; recorded 2026-08-29, not an oversight**), and the **market layer already
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
  `cause:='refund_void'`, `cause_ref:=refund_id`, **`to_identity := SN-VOID`** — the seeded platform void
  sentinel (schema §1.16), **never the issuer and never the anonymization sentinel**, which is a different
  uuid with a different meaning owned by a `public`-schema deletion path (`T-SCHEMA-SENTINEL-06`).
- **Preconditions:** atom not already terminal (**re-void across two refunds is blocked by the atom's current
  state under the `FOR UPDATE` lock**, not by log uniqueness). **Locks & order (SSCAS #3):** **Ticket Atom**
  (`FOR UPDATE`) → **Inventory batch** (`sold -= 1`, return) → **Refund/Payment**. **SSCAS:** #3.
  **Idempotency:** `UNIQUE(refund_void, refund_id, atom)` → N-atom void under one refund allowed, replay no-op.
- **Writes:** `kernel.ticket_ownership_log` (`refund_void`, `to_identity := SN-VOID`,
  `credential_version_after` bumped),
  **`kernel.tickets` (`state → 'voided'`, **`current_owner_id := SN-VOID`** — the platform void sentinel of
  schema §1.16 — and the credential bump so any live QR dies)**, `venue.inventory_batch`**`(_shard)`** (`sold -= 1` — *shard added 2026-08-29, P1-2, same basis as §7.1*),
  `venue.inventory_movement` (`void_return`), **`market.on_atom_voided`** (the `market`-owned definer
  primitive of §20.11.3 — **never a direct `UPDATE market.market_sale`**, per §0.7) when driven by C25.
  **Result:** `{ status, atom_id }`. **Forbidden callers:** any client directly.
  - **`SPEC CORRECTION` (`S-18`; schema §1.6.2/§1.16; ratification `C107`) — THE HEAD WRITE OMITTED
    `current_owner_id`, AND WITH THE NEW DEFERRED CUSTODY TRIGGER THAT MAKES EVERY VOID ABORT AT COMMIT.**
    The log row already sets `to_identity := ` the void sentinel; the `kernel.tickets` write named only
    *"→ `voided`, credential bump"*. `kernel.tg_custody_head_is_ledger_tail` (schema §1.6.2, package `079`)
    is a `CONSTRAINT TRIGGER … DEFERRABLE INITIALLY DEFERRED` asserting that the head's `to_identity` and
    `credential_version_after` equal the greatest-sequence log row's. **This contract bumps
    `credential_version`, which is one of the clauses the trigger fires on** — so at COMMIT the log tail says
    `SN-VOID`, the cached head says the buyer, and **the transaction aborts.**
  - **What that takes down, because this is the void leg of SSCAS #3 and four callers sit on it:**
    `kernel.refund_primary_order` (§11.4), `kernel.force_void_ticket` (§11.1), `catalog.cancel_event` (§4.4)
    and the **C25 auto-compensation sweep** (§12.3). **Every refund that voids a ticket fails.**
  - **`T-SCHEMA-CUSTODY-06` asserts the void COMMITS — a test the contract as written cannot pass.** Which is
    the useful property of the trigger and the reason the repair is one line: **without** the trigger the
    same omission is *silent and permanent* — after every refund-void the log says sentinel and the head says
    the buyer, **on the one surface that exists to settle custody disputes**. The trigger converts a wrong
    answer into a failed build. **A build that does not run is still a build that does not run.**
  - **`SN-VOID` becomes the recorded `current_owner_id` of every voided ticket**, which is why `S-20`
    requires it excluded from every identity projection — CRM export rows, holder-mix buckets, notification
    fan-out, attendee lists, demographics, and any *"tickets owned by X"* read. **An export that does not
    exclude it emails a sentinel and counts it as an attendee.**
  - **`state` is deliberately outside the trigger's clause set** (schema §1.6.2), which is what lets
    `kernel.sweep_expired_ticket_atoms` (§12.5) move `active → expired` without appending a log row. **That
    exemption covers `state` and nothing else** — an implementer who reads it as "the trigger is lenient"
    reintroduces exactly this defect.

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

> **Freeze clause (`OR-17`, F-4):** refuses when `to_identity`'s `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).
- **Purpose:** recipient accepts → **custody moves via the kernel engine** (`cause='p2p_transfer'`),
  credential bumps. **Actor:** the resolved recipient (`auth.uid() = to_identity`, or resolves `to_handle`).
- **Params:** `p_transfer_id`,`p_command_key` — untrusted. **Preconditions:** transfer `initiated`, not
  expired, addressed to `auth.uid()`; a priced send requires a **verified `public.payments`** row for the
  recipient (C35 re-check — money-in stays on the frozen path). **ADDED: `NOT
  kernel.is_transfer_frozen(atom)` — rejects `frozen`** (`SPEC CORRECTION`, §12.4; this closes the
  start-but-not-completion gap named in §7.2). **Locks & order:** **Event/Session** (`FOR SHARE`, rank 1) →
  **Transfer** (`FOR UPDATE`) → **Ticket Atom** (`FOR UPDATE`) → **Payment** (priced). **SSCAS:** #8.
- **Writes:** `market.p2p_transfer` (→ `accepted`/`completed`), then **via the kernel engine
  `kernel.transfer_ticket_ownership`** (§7.2; `cause='p2p_transfer'`, cause_ref=transfer_id): ownership-log
  append + head + credential bump + `resale_state:=none` + **`kernel.payment_native` (priced link — written
  by the ENGINE, §7.2's own Writes line; this caller delegates it, same form as §20.8.6)**. **Idempotency:** `UNIQUE(p2p_transfer, transfer_id, atom)` +
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

### 9.2 `venue.revoke_door_pin(p_pin_id, p_command_key)` — **DB-RPC** — **CORRECTED (`AUTHZ-H3`, obligation RV-1)**
- **Role:** as §9.1. **Locks:** pin row `FOR UPDATE` → its `venue.door_session` rows `FOR UPDATE` ascending
  `door_session_id`. **SSCAS:** n/a (admin/door plane).
- **RV-1 (BINDING) — the cascade.** Revoking a PIN **revokes every `venue.door_session` minted from it
  (`door_session.pin_id = p_pin_id`, `status='active'`) in the SAME transaction**, stamping
  `status='revoked'`, `revoked_at := now()`, `revoked_reason := 'pin_revoked'`. **Without the cascade,
  revoking a PIN leaves live bearer tokens behind** — which is `AUTHZ-H3` reproduced one level up, and it is
  the single most important line in this contract.
  > **What RV-1 does and does not enforce, stated so it is not skipped as redundant.** §1.1d clause 4 already
  > makes those sessions fail on their next call, so **RV-1 is not what enforces revocation — it is what
  > makes the state observable.** A `status='active'` row whose PIN is dead is a row that **lies to the
  > operator console**, and the console is where a manager decides whether the door is secure. A cascade
  > implemented "later, by a sweep" restores exactly that lie for the length of the sweep interval.
- **Writes:** `venue.door_pin` (→ `revoked`), `venue.door_session` (→ `revoked` ×N, RV-1),
  `kernel.admin_audit` (`door_pin.revoke`, **carrying the cascaded session count**). **Result:**
  `{ status, sessions_revoked int }` — the count is returned because the operator revoking a PIN mid-event
  needs to know how many live doors they just closed. **Idempotency:** terminal state; a replay revokes no
  second time and returns `sessions_revoked = 0`. **Forbidden callers:** as §9.1; **a door session may never
  call it** (O-4).
- **Test.** `T-RPC-DOOR-32` (both halves: the next door call raises, **and** the PIN's sessions hold no
  `active` row — the second half is what the console depends on and the first passes without it).

### 9.3 `venue.validate_ticket_online(p_atom_id_or_credential, p_session_id)` — **DB-RPC (read; C37 live verify)**
- **Purpose:** the **online per-scan live verify** — returns whether an atom is admittable **without**
  recording admission (the door UI pre-check; `record_scan` does the authoritative admit). **Actor:** door
  principal — **either** an authenticated `venue_scanner` **or** the `service_role` edge path asserting
  `kernel.assert_door_session` (§1.1d) — or `venue_manager` for the session.
- **Params:** `p_atom_id_or_credential`,`p_session_id` — untrusted. **Reads:** `kernel.tickets`
  (`state`,`resale_state`,`credential_version`,`current_owner_id`), `kernel.signing_key.public_key`,
  `venue.scan` (prior admit). **Writes:** none. **SSCAS:** n/a.
- **Result:** `{ admittable(bool), reason(active|already_scanned|listed_locked|voided|wrong_session|
  version_stale|**refund_hold**), credential_version, **signing_key_id** }`. **Security:** signature
  verification of the presented token uses the **public key** (door-side / edge); the **private key is never
  in the DB** (C33). Online doors do a live per-scan verify (C37); offline doors verify against the cached
  manifest (±2 time-bucket skew, defined immediately below). **Forbidden callers:** non-door clients.
- **A time-bucket is `30 seconds`, so `± 2 time-buckets` is `± 60 seconds` — `SPEC CORRECTION` (`MP-1`).**
  `OFFLINE-VERIFY-v1` conjunct 3a reads *"`now() <= token.exp`, ± 2 time-buckets"* and cites **this section**
  as the definition site. **This section did not define it, and neither did anything else in the corpus** —
  the phrase occurs in edge §5.4.3/§5.4, door §9.2/§14, Wallet §2.3/§5.2 and domain §10.4, in every case as a
  citation, in no case as a magnitude. **A tolerance with no stated width is not implementable: two scanner
  builds would each pick a number, and admission would differ by vendor.** The value is stated here because
  the fenced block routes the reader here, and the block is the single normative statement and is not
  editable from a downstream document.
- **It is a fixed protocol constant, deliberately NOT a `catalog.platform_config` key.** Every other door
  tolerance in this design is config-seeded (door §10.6), and this one must not be. The value has to be
  **identical on the signer and on a verifier that has been offline for hours** — that is the entire point of
  a skew window. A runtime-tunable key is read by the signer at sign time and by the device only at its last
  sync, so lowering it strands passes already in wallets and raising it widens a replay window on devices
  that will never learn the new value. It is versioned with the predicate: changing it is a change to
  `OFFLINE-VERIFY-v1`, made in edge §5.4.3 first, and a scanner-SDK release.
- **`INFERENCE — AUTHORED`, and filed for owner confirmation (§20.14 `R-22`).** The corpus fixes the *shape*
  (±2 buckets) and never the width; `30 s` is chosen as the smallest window that absorbs ordinary
  unsynchronised-device drift without materially widening replay, and it is **unrelated to
  `credential.wallet_exp_skew`** (6 hours), which is added to `exp` at sign time by a server with a correct
  clock and solves a different problem. Nothing else in the corpus constrains the number, so it is authored
  rather than derived, and it is recorded as authored rather than presented as inherited. **This is a
  numeric tolerance, not an authority change** — it is decided here, not left open — but the owner should
  confirm the magnitude rather than inherit it.
- **`signing_key_id` is REQUIRED in the result, and it is not decoration (edge recon #14).** The offline path
  already binds the key id: `venue.door_manifest_entry` carries `signing_key_id` (§20.6.1) and the door's
  offline check 3c refuses a credential whose key id is not the one the manifest pinned. **With no online
  counterpart, the key-id binding held on exactly one of the two admission paths** — and the claim
  §20.7.5 makes about revocation (*"blast radius = the atoms pinned to that key"*) is only true if **both**
  paths check it. The online verify therefore returns the atom's live `kernel.tickets.signing_key_id` and the
  caller refuses on mismatch, exactly as the offline path does. **`T-RPC-DOOR-25`:** an atom whose
  `signing_key_id` names a **revoked** key is refused online **and** offline, asserted on both paths, because
  a test on one path passes while the other is the hole.
- **`refund_hold` is a required `reason` label (edge recon #14, door §9.2).** §17.1 parks a refund by setting
  `kernel.tickets.resale_state := 'refund_hold'`, which makes the atom non-admittable. Without the label the
  **online** door refuses that atom with **no reason to render** and the box office cannot tell a parked
  refund from a void. **The offline path cannot see it at all** — a `refund_hold` set after the manifest was
  snapshotted reaches the door only as a `revoke` delta (§17.13), which is the documented and accepted gap,
  not a new one.

### 9.4 `venue.record_scan(p_atom_id, p_session_id, p_actor_device_id, p_scan_meta, p_command_key)` — **DB-RPC (AO; authoritative admit)** — **CORRECTED (`AUTHZ-H3b`)**

> **`AUTHZ-H3b` — THE DEVICE ATTRIBUTION IN THE ADMISSION LEDGER WAS A VALUE THE CALLER CHOSE.**
> This function read `device_id` **out of `p_scan_meta`** — the parameter its own contract labels
> *untrusted* — and `venue.reconcile_offline_scans` (§9.5) took it as a bare parameter. On the door path
> there is no RLS and no `auth.uid()`, so in both cases the device attribution written into the **append-only**
> `venue.scan` ledger was **an unauthenticated string that selected which device's scans were written**.
> Every control that reads it downstream is reading a self-declared field: the C23 offline ordering by
> `(device_boot_id, scan_sequence)`, the X-2 insider-fraud trail, the per-device reconciliation.
> **Binding the session to a device (`AUTHZ-H3`) fixes nothing if the scan RPCs take the device from
> somewhere else.** *(Schema §3.10a.3 / §13.7 `S-6`; edge §3.9a request #3; matrix X-5.)*

- **Purpose:** record an admission attempt (AO ledger) and, on first valid `in`, move the atom to `scanned`
  via `kernel.mark_ticket_scanned`. **Actor:** door principal — **either** an authenticated `venue_scanner` **or** the `service_role` edge path asserting `kernel.assert_door_session` (§1.1d) — or
  `venue_manager`.
- **`p_actor_device_id` — a distinct parameter, server-derived, never client-attested.**
  - On the **door-session path** it is **the value `kernel.assert_door_session` returned** (§1.1d), never a
    value from the request body. The function **asserts `p_actor_device_id = door_session.device_id` for the
    asserted session** and raises otherwise. The edge is structurally forbidden from passing anything else:
    EA-6 (*no function passes an actor, a role, or an authority assertion as an RPC parameter*) — **the
    device id was exactly such an assertion**, and this is how it stops being one.
  - On the **authenticated-staff path** it is **NULL**, and `venue.scan.actor_identity_id` carries the
    attribution instead (RLS §17 X-2's `CHECK (device_id IS NOT NULL OR actor_identity_id IS NOT NULL)`).
  - **`p_scan_meta.device_id` is DROPPED.** Not deprecated, not tolerated — removed from the accepted shape,
    because *"a field that looks like identity and is not is worse than no field"* (schema §3.10a.3). A
    `p_scan_meta` carrying a `device_id` key raises `invalid_input`, so a stale client fails loudly instead of
    writing a lie into an append-only ledger.
- **Params:** `p_scan_meta` (direction default `in`, scan_type, device_boot_id, scan_sequence, occurred_at)
  — untrusted **telemetry only, no identity**; `p_command_key`.
- **Preconditions:** session `live`; atom belongs to session; not `listed`/`locked`/terminal. **Locks & order:**
  **Ticket Atom** (`FOR UPDATE`) → scan ledger insert. **SSCAS:** atom + scan (custody-adjacent, single custody
  aggregate). **Idempotency:** partial `UNIQUE(ticket_atom_id, event_session_id) WHERE result='admitted' AND
  direction='in'` → **first-in-wins**; a second `in` is inserted as `result='duplicate'` (not an error).
- **Writes:** `venue.scan` (INSERT `admitted|duplicate|invalid|frozen|fraud_review`), `kernel.tickets` (→
  `scanned` via `mark_ticket_scanned`, first admit only). **Result:** `{ result, admitted(bool), atom_state }`.
  **Retry:** safe (duplicate recorded, not doubled). **Forbidden callers:** non-door clients; fans.

### 9.5 `venue.reconcile_offline_scans(p_session_id, p_actor_device_id, p_batch, p_command_key)` — **DB-RPC (offline reconciliation, C23)** — **CORRECTED (`AUTHZ-H3b`)**
- **Purpose:** ingest a device's queued offline scans, ordering by `(server_receipt_at, then device_boot_id +
  scan_sequence)` to resolve first-admit-wins across devices; flag conflicts. **Actor:** `venue_scanner` (or the `service_role` edge path asserting `assert_door_session`)
  (own device) / `venue_manager`. **Params:** `p_batch[]` (offline scan rows, untrusted),`p_command_key`.
- **`p_actor_device_id` replaces the bare `p_device_id`, under the §9.4 rule verbatim** (`AUTHZ-H3b`):
  server-derived from `assert_door_session`'s return value on the door path, asserted equal to
  `door_session.device_id`, NULL on the authenticated-staff path. **`p_session_id` is added** because the
  assert is per `(device, session)` and a batch that spans sessions cannot be bound to one — a batch row
  naming a different session raises rather than being attributed to the asserted one.
- **The assert is re-run per CALL, never per BATCH ITEM and never cached across items.** Caching it across a
  600-row offline batch is what converts *"revoked on the next call"* into *"revoked eventually"*, and an
  offline batch is precisely the call that arrives after the longest gap.
- **Preconditions:** device belongs to venue; manifest window valid. **Locks & order:** per atom **Ticket
  Atom** (ascending `ticket_atom_id`) `FOR UPDATE`, then scan inserts. **SSCAS:** batched atom + scan.
  **Idempotency:** the scan `UNIQUE(cause,cause_ref,batch,kind)`-style + partial-unique dedupe; replay of a
  device batch is a no-op.
- **Writes:** `venue.scan` (INSERT each attempt, `offline_pending:=false` after reconcile), `kernel.tickets`
  (→ `scanned` **via `kernel.mark_ticket_scanned`**, first admit only — §9.4's rule verbatim, and see the
  `MB-6` block below), `venue.scan_device` (`last_sync_at`,`manifest_version`). **Result:**
  `{ status, admitted, duplicates, conflicts }`. **Retry:** re-entrant. **Forbidden callers:** non-door.

> **`MB-6` — THE OFFLINE PATH DECLARED A DIRECT `kernel.tickets` WRITE, AND IT IS THE BATCHED ONE.**
> This contract's **Writes** line read *"`kernel.tickets` (first-admit-wins → `scanned`)"* with **no
> delegation named**, while its online sibling §9.4 — the *same* admission decision, one row at a time —
> routes through `kernel.mark_ticket_scanned`. That is a **§0.7 violation** (`market`/`venue` never write
> `kernel.tickets` directly), and it is not tidiness:
>
> - **`mark_ticket_scanned` carries the must-not-recheck-the-freeze property, and it carries it *structurally*.**
>   `PHASE_2_SUPABASE_MIGRATION_PLAN.md` pins it as an assertion over `pg_proc.prosrc` — *the body references
>   `is_transfer_frozen` **nowhere***, *"the defect a well-meaning engineer re-introduces"*, blast radius
>   *"100% of admissions from doors-open to end of night."* **A reconcile path that writes the atom itself is
>   not covered by that assertion**: the assertion inspects one function's body and passes, while the
>   admission decision runs in another function it never reads.
> - **The batch multiplies it.** §9.4 admits one atom per call; this function admits **up to 600 rows** per
>   call, queued while the device was offline — the exact traffic that arrives *after* doors open, which is
>   the window in which a freeze re-check refuses a legitimate ticket.
> - **RLS is not the backstop here.** This RPC is reached through the `door-session` edge function, where
>   `verify_jwt=false` and there is no `auth.uid()` — the function body is the *only* place any of this is
>   enforced.
>
> **Corrected form, preserving first-admit-wins and the batch semantics exactly:** the per-atom admission is
> `kernel.mark_ticket_scanned(atom, session, scan_ctx)`, **called once per admitted row inside the batch
> loop**, under the atom lock this contract already takes ascending `ticket_atom_id`. The ordering rule is
> unchanged (`server_receipt_at`, then `device_boot_id` + `scan_sequence`); **the engine's own partial unique
> is what resolves first-admit-wins across devices**, so a losing row is written `result='duplicate'` and the
> conflict is reported, exactly as today. **No new state, no new lock, no new lock-order rank, no change to
> the SSCAS classification** (batched atom + scan, unchanged) — and no change to `mark_ticket_scanned`
> itself, which is what keeps the `prosrc` assertion the pin it is. **`T-RPC-DOOR-35`** asserts the routing
> structurally (this function's body references `kernel.tickets` **nowhere**), because a value-based test
> cannot tell the two implementations apart: they produce the same rows until the day someone adds a freeze
> re-check to one of them. **`AUTHZ-H3b`'s per-call assert rule is untouched** and still applies per call,
> never per batch item.

### 9.6 `venue.mint_door_session(p_venue_id, p_session_id, p_device_id_claim, p_pin, p_command_key)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (`AUTHZ-H3`)

**The only writer that creates a `venue.door_session` row**, and the only place the PIN is exchanged for a
possession credential. Filed by edge §3.9a request #4 and schema §3.10a.1.

- **Authority.** **`DEF` — `service_role` only**, `REVOKE EXECUTE FROM anon, authenticated`. There is no
  human path and no caller-identity predicate: this is the mint route of the `door-session` edge function
  (`verify_jwt: false`), and **`auth.uid()` is NULL by design**. The edge derives no authority from the
  request body; this function re-validates everything server-side.
- **Params — ALL FOUR UNTRUSTED, and the naming says so.** `p_device_id_claim` is a **claim**, not an
  identity: it is what the tablet asserts about itself and is authorized only by the PIN presented with it.
  `p_pin` is the plaintext PIN, compared **constant-time** against `venue.door_pin.pin_hash` under the slow
  KDF (I-9, Phase-0 §9) — the low-entropy credential keeps the expensive construction, unlike the session
  token (§1.1d).
- **Preconditions, re-validated server-side — the edge asserts none of them.**
  1. A `venue.door_pin` for `p_venue_id` bound to `p_session_id` with `status='active' AND expires_at >
     now()` whose hash matches `p_pin`.
  2. `venue.scan_device(p_device_id_claim).status='active'` **and** its `venue_id = p_venue_id` (**DS-2**:
     cross-venue is the highest-value confusion on a path with no RLS behind it).
  3. The PIN's `event_session_id = p_session_id` (**DS-1**: a PIN is session-scoped; a session minted from a
     PIN for a different night is the exact confusion the binding exists to prevent).
  4. The event session belongs to that venue.
  **Every failure returns the same opaque error with the same timing budget** — the PIN attempt's
  anti-enumeration obligation, unchanged.
- **Server-derived, never client-set.** `door_session_id` (uuid, the selector); the **secret** — ≥ 256 bits
  of CSPRNG, returned **once** and never re-returned by any route; `token_hash := sha256(door_session_id::text
  || ':' || secret)`; `pin_id`; `venue_id`; and
  `expires_at := LEAST( now() + config('door.session_ttl_interval'), pin.expires_at,
  session_end + config('door.session_post_session_grace') )` — a **server maximum**, the same discipline
  `venue.inventory_hold.expires_at` carries.
- **At most one live session per `(device, session)`, enforced by the DATABASE.** The partial
  `UNIQUE(device_id, event_session_id) WHERE status='active'` (schema §3.10a.1) is what makes revocation
  **total**: with a second live session possible, a revoke closes one door and leaves another open and the
  operator cannot see it. **A re-mint for a `(device, session)` that already holds a live session revokes the
  prior row in the same transaction** and returns a fresh secret — that is how the edge's `/refresh` is
  served (§1.1d `AUTHZ-H3a`(b)), and it re-runs the rate limit and every liveness check above, which is the
  whole point.
- **Locks & order.** `venue.door_pin` row `FOR SHARE` → `venue.scan_device` row `FOR SHARE` → the prior
  `venue.door_session` row `FOR UPDATE` (re-mint only) → INSERT. Admin/door plane, **outside the six SSCAS
  ranks; the closed set stays at fifteen.** **SSCAS:** n/a.
- **Idempotency.** `p_command_key`. **A replay returns `{ status: 'noop_replay' }` and the ORIGINAL
  `door_session_id` — but NOT the secret**, which was returned once and is unrecoverable by construction. A
  client that lost the secret re-mints; it does not replay.
- **Writes.** `venue.door_session` (INSERT `active`; the superseded row → `revoked`,
  `revoked_reason='superseded'`), `kernel.admin_audit` (`door_session.mint`, carrying `device_id`,
  `event_session_id`, `pin_id`, `door_session_id` — **never the secret and never the hash**).
- **Result.** `{ status, door_session_id, secret, expires_at, bound_device_id, bound_session_id }`.
  **`secret` appears in this result and in no other result, log line, audit payload, or error in the corpus.**
- **Errors.** `insufficient_privilege(42501)` — one opaque class for every precondition above ·
  `idempotency_replay`.
- **Test.** `T-RPC-DOOR-26` (a PIN for session S1 cannot mint a session bound to S2; a device at venue V2
  cannot mint against V1's PIN; both fail with the **same** error and timing as a wrong PIN) ·
  `T-RPC-DOOR-27` (a second mint for the same `(device, session)` leaves exactly one `active` row, and the
  superseded token is refused by §1.1d on its next call).

### 9.7 `venue.revoke_door_session(p_door_session_id, p_reason_code, p_command_key)` — **DB-RPC** · `NEW RPC` (`AUTHZ-H3`)

**The lost-or-stolen-tablet control** — it closes one door without disturbing the PIN every other device at
that door is using. Filed by edge §3.9a request #4.

- **Authority.** `has_venue_role(venue, ['venue_manager'])` OR `has_org_role_over_venue(venue,
  ['org_owner','org_admin'])` OR `is_platform(['platform_admin'])` — the **O-4 allow-list, unchanged**, and
  **a door session may never call it** (a credential that can revoke its siblings is a credential that can
  close the door it is standing at). `EXEC: authenticated` with the in-body predicate re-check; also callable
  by `service_role` from the edge.
- **Params.** `p_door_session_id` (untrusted; resolved to its venue for the authority check — a caller with
  no role over that venue gets `insufficient_privilege`, **never `not_found`**, which would confirm the id).
  `p_reason_code` **mandatory**, from the D3 registry (`device_lost` · `device_stolen` · `device_recall` ·
  `superseded` · `pin_revoked` · `operator_request`).
- **Preconditions.** Row exists and `status='active'`. **Locks:** the row `FOR UPDATE`. **SSCAS:** n/a.
- **Writes.** `venue.door_session` (→ `revoked`, `revoked_at`, `revoked_reason`), `kernel.admin_audit`
  (`door_session.revoke`, mandatory `reason_code`).
- **Effective on the NEXT call, and that is the property being bought.** §1.1d re-reads the row on **every**
  relay call and caches nothing, so revocation lands at the next scan. **This is the property a door JWT
  would destroy** (ROLE_MODEL §7.3) and it is only actually true because the token is a row rather than a
  self-describing claim.
- **Idempotency.** Terminal state + `p_command_key`; re-revoking is `noop_replay`, not an error.
- **Result.** `{ status, door_session_id }`. **Errors.** `insufficient_privilege` · `precondition_failed(
  reason_required | already_revoked)` · `idempotency_replay`.
- **Related revocation paths, so the set is closed and none is assumed.** (1) `venue.revoke_door_pin` (§9.2)
  cascades via **RV-1**; (2) `venue.set_scan_device_status(..., 'retired', …)` (§20.4.3) cascades via
  **RV-2**; (3) `venue.close_door_manifest(…, 'device_recall')` **should** revoke the session's tokens
  (recommended, edge §3.9a); (4) this function. **Four paths, and every one of them lands in the same
  transaction as the act that motivated it** — a revocation deferred to a sweep is a live bearer token.
- **Test.** `T-RPC-DOOR-28` (a `venue_scanner` and a door session are both refused; the next relay call on a
  revoked session raises with the same error as an unknown id).

### 9.8 `venue.sweep_expired_door_sessions()` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (`AUTHZ-H3`)

- **Purpose.** Move `active` rows past `expires_at` to `status='expired'`. `service_role`/`pg_cron` only;
  `REVOKE EXECUTE FROM anon, authenticated`. Bounded batch, `SKIP LOCKED`, re-entrant.
- **NOT LOAD-BEARING, and this is stated because three sweeps in this document look alike and only two of
  them are safe to skip.** Expiry is **arithmetic** — `expires_at > now()` inside §1.1d clause 1 — so a
  session is dead the moment it expires whether or not this ever runs. It exists to keep `status` truthful
  for the operator console. **Same posture as `kernel.sweep_expired_door_overrides` (§17.11); the opposite of
  `venue.sweep_expired_inventory_holds` (§20.3.3), which IS load-bearing because it returns a stored counter,
  and of `kernel.sweep_expired_refund_requests` (§17.4), which releases a custody hold.**
- **Writes.** `venue.door_session` (→ `expired`). **No audit row** — an expiry is arithmetic reaching a
  label, not a privileged mutation. **No DELETE, ever:** an expired door session is evidence about who was at
  the door.
- **Result.** `{ swept_count }`. **SSCAS:** n/a.

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
  `venue.settlement_line` (AO, incl. rounding bearer), **`venue.settlement` (→ `closed`, **AND the four money
  columns `gross_minor` / `fees_minor` / `refunds_minor` / `net_minor`** — schema §3.13.1, defect `R1-2`)**,
  `kernel.payout` (INSERT `pending`, cause `settlement` + `promoter_commission`), `kernel.admin_audit`
  (`settlement.close`).
  - **`SPEC CORRECTION` (`R1-2`; ratification `C103`) — this contract RETURNED `net_minor` and wrote none of
    the four.** The Writes line named only *"`venue.settlement` (→ `closed`)"*, and the four columns appeared
    **exactly twice corpus-wide, both DDL**. So the number the dashboard shows a venue, and the header
    `venue.on_payout_settled` later moves to `paid`, were **NULL forever** — while this function had the
    figure in hand, since it could not have generated the payout without it. **A function that returns a
    column it does not write is a function that computed the number and threw it away.**
  - **One derivation, inside the header's own `FOR UPDATE`, from the lines this transaction just wrote:**
    `gross_minor` = Σ the positive revenue lines · `fees_minor` = Σ the platform-fee and royalty lines ·
    `refunds_minor` = Σ the refund lines · `net_minor` = `gross − fees − refunds`, **including the rounding
    residual assigned to `settlement_line.is_rounding_bearer` (C31)**, so the header equals the sum of the
    lines exactly and not to within a cent. Schema §3.13.1's CHECK makes the identity a table constraint;
    the four are **write-once**, because a re-close is already refused by the `open` precondition.
  - **Not a view over the lines, and the reason is the seams.** `settlement_royalty_lines` (`088`) and
    `settlement_commission_lines` (`090`) are `CREATE OR REPLACE` — a view would return **different numbers
    before and after `090` replays** for a settlement closed at `087`. A payout must be explicable by the
    arithmetic that produced it.
- **Emitted facts:** payout cause `settlement`/`promoter_commission`. **Result:** `{ status, payout_ids[],
  net_minor }` — **and `net_minor` is now a read-back of the column this function wrote, not a value that
  exists only in the response.** **EDGE note:** the actual Stripe Connect transfer is executed by the payout
  edge fn / existing `record_transfer_payout`-style pipeline (§13) — this RPC only records the payout intent.
  **Forbidden callers:** non-finance; anything touching ticket history from settlement.
- **Tests.** `T-SCHEMA-SETTLE-03` / `-04` (schema §3.13.1) are this contract's assertions: a `closed` row
  with any of the four NULL raises, and the stored header equals the sum of its own lines — asserted against
  the lines, never against a literal, because a literal passes on a function that stores a constant.

### 10.3 `kernel.request_org_payout(p_org_id, p_settlement_id, p_command_key)` — **EDGE-FRONTED (DB-RPC records intent)**
- **Purpose:** org finance requests disbursement of a closed settlement's payout to the org's Stripe Connect
  destination. **DB-RPC side** records/advances `kernel.payout` `pending → submitted` and enforces the
  payout-destination cool-down (`payout_destination_locked_until`); **the edge fn executes the Stripe transfer**
  (reuses the frozen `source_transaction` funding + deterministic idempotency, SPEC_FOUNDATION §2).
- **Role:** `has_org_role(p_org_id, [org_finance, org_owner])` — **the scope argument is explicit, per RM-2**;
  a bare `has_org_role([...])` is not a legal predicate in this corpus and the earlier shorthand here was a
  transcription defect, not a different rule. **Params:** `p_org_id`,`p_settlement_id`,`p_command_key`.
  **Preconditions:** settlement `closed`, payout `pending`, destination not locked, **and
  `settlement.org_id = p_org_id`, re-resolved under the settlement's own lock** — see the scope-binding note
  below. **Locks & order:**
  **Settlement** → **Payout** (`FOR UPDATE`) → **Approval** (rank 5.5, INSERT — parked arm only).
  **SSCAS:** member #4 continuation (Settlement→Payout).
  **Idempotency:** payout `idempotency_key`.
- **Three preconditions this contract did not state, all of them controls the money spec already relies on:**
  1. **SoD-1 (structural).** Rejects when `auth.uid() = kernel.organization.payout_destination_set_by`,
     **permanently for that destination**, not merely during the cool-down — `sod_violation`. §17.7 control 1.
  2. **`kernel.money_role_grant_matured(p_org_id)`** (`AUTHZ-C1B`, schema §13.7 `S-3`; **contract: §1.1e**). **A money-role grant
     younger than `authn.money_role_maturity_hours` may neither request nor approve.** Without it, SoD-1 is
     satisfied by any two distinct `auth.uid()` values **and an `org_owner` can mint the second one** through
     the ordinary invite/accept flow. `sod_violation`, **not** `insufficient_privilege` — the role is
     genuinely held, and a permission error would send the operator to re-check a grant that is correct.
     **It binds the destination-SETTER (§17.7) as well as this requester: applied to one half of a pair it is
     applied to neither.**
  3. **Step-up per `AUTHZ-M4`** — an absent `aal`/`amr` claim raises **`step_up_unavailable`**, distinctly,
     and never evaluates to a pass or a fail.
  **None of the three is ever applied to a deny or a cancel** (schema §13.7 `S-3`): a control that blocks
  *stopping* a payout is a control pointed the wrong way.
- **Scope binding — the one way a client-supplied `p_org_id` could defeat the maturity check, closed here
  (`AUTHZ-C1C`).** This function takes **two** untrusted identifiers, and every authority predicate on it —
  `has_org_role`, SoD-1 and `money_role_grant_matured` — is evaluated against `p_org_id`, while the money it
  moves is selected by `p_settlement_id`. **Nothing previously required the two to agree.** A caller holding
  a mature `org_finance` grant at Org A could therefore pass `p_org_id = A` (every predicate passes) and
  `p_settlement_id` = a settlement of Org B, and the checks would be true statements about the wrong
  organization. **`settlement.org_id = p_org_id` is therefore a precondition, re-resolved under the
  settlement's `FOR UPDATE` in the same transaction, raising `not_found`** (never `insufficient_privilege` —
  the caller must not learn that the settlement exists). The actor was never client-passed (C35 is honoured
  at all four call sites: the identity is always `auth.uid()` inside the helper), but **a scope that does not
  bind to the subject is the same defect wearing the other parameter**. **`T-RPC-AUTHZ-20`.**
- **Above `payout.dual_control_min_minor` it PARKS an approval instead of advancing, and it WRITES
  `required_approver_class` when it does (`AUTHZ-C1A`, schema §13.7 `S-1`).** RLS §11.3 states the parking;
  the column is what carries the tier forward, and this is its third writer (with §17.1 and §20.2.1).
  Server-set from the same evaluation that decided to park, **pinned exactly as `config_versions` is**,
  **never a parameter**: `required_approver_class := 'org'` for an org-approvable payout, `'platform'` where
  the amount or a risk condition sends it to platform review — at which point **`platform_support` is DENIED
  on the payout arm** (§17.2), because it holds no payout authority anywhere else and must not acquire one
  through the generic approval object. `subject_kind='settlement'`, `subject_id := p_settlement_id`, resolved
  under the settlement's lock per **`APPR-SUBJ-1`** (§17.0a).
- **DESTINATION PROBATION — THE THIRD ARM, AND THE ONE THAT HAD NO WRITER (`S-15`; schema §1.9.1; ratification
  `C105`).** §17.7 control 2 requires that **the first payout to a destination changed within
  `payout.destination_probation_days` does not disburse until `platform_risk` releases it.** Schema §1.9's
  write-authority row attributed that to this function as *"INSERT-with-`probation_hold`"* — and **this
  contract had no INSERT arm and no probation arm at all**, so the label had no writer, `probation_hold` was
  unreachable, and Control 4 of the destination-change set had **no storable outcome**. Corrected here:

  > **This function does not INSERT a payout — `kernel.close_settlement` does (§10.2, at `pending`).** The
  > probation arm therefore **declines to advance** the existing `pending` row and marks it, rather than
  > creating anything:
  >
  > ```text
  > IF destination changed within config('payout.destination_probation_days')
  >    AND no payout to this destination has yet reached 'paid'   -- "the FIRST payout"
  > THEN  status      stays 'pending'          -- NOT advanced to 'submitted'
  >       hold_state       := 'probation_hold'
  >       hold_reason_code := 'destination_probation'
  >       held_at          := now()
  >       held_by          := NULL              -- no human initiated it; the pairing CHECK requires NULL
  > ```
  >
  > **All four columns or none — the pairing CHECK makes a partial write unstorable** (`hold_state='none'`
  > **iff** `hold_reason_code IS NULL AND held_at IS NULL`; `held_by IS NULL` whenever
  > `hold_state <> 'held'`). That is why the arm is spelled out as a column list rather than as *"set the
  > hold"*: the contract as filed named one column of four, and a row that names one is rejected by the
  > constraint.
  > **`held_by` is NULL and that is a queryable fact, not an omission** — it is what separates a probation
  > hold from a risk hold on the dashboard's three pills without inferring from the absence of an audit row.
  > **Released by `kernel.release_payout` (§11.3) and by nothing else**, under
  > `is_platform(['platform_risk','platform_admin'])` (O-3); release restores nothing, because `status` was
  > never overwritten — it is still the `pending` this arm declined to advance.
  > **`status='held'` NEVER EXISTED** (schema §1.9.1): it is not in the enum, not in plan §5's CHECK, and
  > adding it would be lossy, since `release_payout` would then have to guess between "not yet sent to
  > Stripe" and "already sent" — the difference between paying once and paying twice.
  > **The ratified behaviour is unchanged:** money does not leave, and only `platform_risk`/`platform_admin`
  > release it.

- **Writes:** `kernel.payout` — **direct arm** (→ `submitted`; `stripe_transfer_ref` is written later by
  `kernel.mark_payout_transfer_state`, §20.7.6, **not by a callback param on this function**), **probation
  arm** (`hold_state := 'probation_hold'` + `hold_reason_code` + `held_at`, `held_by := NULL`, **`status`
  untouched**), `kernel.approval_request` (INSERT `pending` with `required_approver_class` **and
  `amount_minor`**, schema §1.13.5 — parked arm), `kernel.admin_audit` (`payout.request`, and
  `payout.probation_hold` on the probation arm). **Result:** `{ status ∈ {submitted, probation_held,
  pending_approval, pending_platform_review, noop_replay}, payout_id, request_id?,
  required_approver_class? }` — **`probation_held` is returned distinctly**, because a surface that reports
  `submitted` for a payout that did not submit is the failure §14.5's three-pill rule exists to prevent.
  **Failure:** `precondition_failed` (destination locked / not closed) · `sod_violation` ·
  `step_up_required` · **`step_up_unavailable`**. **Forbidden callers:** non-finance; the DB never moves
  money itself.
- **Tests (probation arm).** **`T-RPC-MONEY-31`** — a destination changed inside the probation window leaves
  `status='pending'`, sets exactly the three hold columns with `held_by IS NULL`, and returns
  `probation_held`; **asserted on `status` as an equality against `pending`, not on the absence of a
  transfer**, because the defect this closes is a contract that had nowhere to record the outcome.
  **`T-RPC-MONEY-32`** — `release_payout` on that row restores `hold_state='none'` and leaves `status`
  **still `pending`**, and a second `request_org_payout` then advances it normally.

> **`MB-1b` — THE PAYOUT TIER HAS THE SAME SPLITTING SHAPE AS `MB-1`, AND ITS AGGREGATE SUBJECT IS MINTED BY
> THE CALLER. OPEN — this pass does not close it, and it is not a defect in this contract's text but in the
> operand nobody named.**
> `payout.request_auto_max_minor` / `payout.dual_control_min_minor` are compared against **one payout's
> amount**. A payout is generated by `kernel.close_settlement` (§10.2) from a settlement whose **period is a
> caller-supplied parameter** — `venue.open_settlement(p_org_id, p_venue_id, p_event_id, p_period, …)`
> (§10.1), open to `org_owner` / `org_finance` / `venue_finance`, **the same principals the tier gates**. An
> org that must not disburse £X in one payout may open N narrow-period settlements and disburse it in N
> payouts, each below the ceiling.
>
> **It is worse than the refund case.** `MB-1` splits a **fixed** subject — the payment exists and its total
> is not caller-chosen, which is exactly why §17.1a's aggregate is invariant under decomposition. Here the
> caller **chooses the decomposition of the subject itself**, so no aggregate scoped to "this settlement" can
> be invariant by construction.
>
> **The property a correct fix must have, so the fix is checkable rather than plausible: the tier operand
> must be invariant under decomposition of any caller-chosen subject.**
>
> **Two admissible forms; the choice is the owner's — money spec `D-10`.** **(a) Undisbursed org exposure:**
> `Σ kernel.payout.amount_minor` for the org in a non-terminal state (`pending` · `held` · `submitted`) plus
> this payout — no new key, no window, not caller-mintable (splitting a settlement does not change the sum of
> its parts), decays as payouts complete; **does not close the slow case**, where each payout settles before
> the next is requested. **(b) Rolling per-org window:** Σ over a new `payout.tier_window_hours`, disbursed
> and undisbursed alike — closes the slow case, costs a key and a width decision.
>
> **Why this contract does not choose.** It is *who may disburse how much without a second approver*, and
> unlike `MB-1` there is **no subject already in the corpus** the answer can be derived from. **What is not
> open is whether payouts are splittable today: they are.**

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
- **Writes:** **`kernel.payout` — `hold_state := 'held'`, `hold_reason_code := p_reason_code`,
  `held_by := auth.uid()` (server-derived, C35), `held_at := now()`. `status` is NOT written** (schema §1.9.1,
  `S-15`; ratification `C105`). `kernel.admin_audit` (`payout.hold`). **Result:** `{ status, hold_state }`.
  **Idempotency:** already-held + command key. **Forbidden callers:** non-platform-risk.
  - **`SPEC CORRECTION` — this line read *"→ `held`-equivalent status"*, which is a contract writing a value
    that does not exist.** `kernel.payout.status` is `pending · submitted · paid · failed · reversed`;
    `held` is not a member, is not in plan §5's CHECK, and **a corpus-wide grep for `held` returns only
    `venue.inventory_batch.held`, an integer capacity counter** — the wrong-column trap in its purest form.
    The hold lives on the **orthogonal** `hold_state` column, which reproduces the shape of the frozen
    Phase-0 discipline this function is contracted to extend (`public.transfers.payout_review_status` +
    `payout_hold_until`, migration `039`). **Extending a discipline means reproducing its shape, not
    renaming its outcome.**
  - **All four columns move together or the pairing CHECK rejects the row** (`hold_state='none'` **iff**
    `hold_reason_code IS NULL AND held_at IS NULL`).

### 11.3 `kernel.release_payout(p_payout_id, p_command_key)` — **EDGE-FRONTED (DB-RPC advances state)**
- **Purpose:** release a held payout → resume disbursement (extends `admin_release_held_payout`). **Role:**
  `is_platform([platform_risk, platform_admin])`; dual-control seam. **DB-RPC** advances `kernel.payout` state
  and writes audit; the **edge fn re-submits the Stripe transfer**. **Locks:** payout `FOR UPDATE`. **SSCAS:**
  Payout single-aggregate. **Writes:** **`kernel.payout` — `hold_state := 'none'`, `hold_reason_code := NULL`,
  `held_by := NULL`, `held_at := NULL`. `status` is NOT written and is not read to decide anything** (schema
  §1.9.1, `S-15`; ratification `C105`). `kernel.admin_audit` (`payout.release`). **Result:**
  `{ status, hold_state }`. **Forbidden callers:** non-platform-risk.
  - **`SPEC CORRECTION` — this line read *"→ `pending`/`submitted`"*, and as written it was UNIMPLEMENTABLE
    under any single-column repair.** It had to restore **which** of the two the row was, after a `held`
    status had overwritten exactly that fact — and the two are *"not yet submitted to Stripe"* and *"already
    submitted to Stripe"*, **the difference between sending money once and sending it twice.** With
    `hold_state` orthogonal there is nothing to restore: `status` was never touched, so the row resumes the
    lifecycle position it already held. **`T-SCHEMA-PAYOUT-02` asserts this as an equality against the
    pre-hold value rather than against a literal**, because the defect this closes is a release that has to
    guess.
  - **It releases `probation_hold` as well as `held`** — one release path for both labels, under
    `is_platform(['platform_risk','platform_admin'])` (O-3). A probation hold released by anyone else, or by
    the passage of time, would make §17.7 control 2 a delay rather than a review.

### 11.4 `kernel.refund_primary_order(p_order_id, p_amount_minor, p_reason_code, p_command_key)` — **EDGE-FRONTED (DB-RPC + Stripe refund)**
- **Purpose:** refund a primary order (full/partial) and **void the covered atoms** (SSCAS #3). The **Stripe
  refund is executed by the refund edge fn**; the DB-RPC records `kernel.refund` and voids atoms atomically.
- **`SPEC CORRECTION` — Role NARROWS to `EXEC: DEF` + `is_platform([platform_support (capped),
  platform_admin])`.** Buyer, `org_finance` and the new `org_owner` authority reach this function **only via
  `kernel.request_order_refund` (§17.1)**, which calls it definer→definer in the same transaction. **This
  remains the sole ORDER-SCOPED writer of `kernel.refund`** on every tier — the complete writer set is four (§20.7.7: this function, `admin_refund` payment-scoped, the C25 sweep's compensate arm, `mark_refund_state` state-sync; *"sole writer" corrected to the per-path form 2026-08-29, red-team P2-7*) — which is what preserves R7 money-single-path per path:
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

> **`kernel.admin_refund`** (platform_risk/admin dispute refund) is broadly the same DB shape as §11.4 with
> `reason_code='dispute'`/`admin_action` and platform authority. **This sentence was the whole of its
> contract, and a sibling is not a contract — it is now written out at §20.7.1.** Three differences the
> "same shape" reading hides: it is **payment-scoped, not order-scoped** (the only path to a native-resale or
> fee-only reversal); it is the **sanctioned destination for this section's own `custody_moved` ruling**; and
> it is **freeze-exempt (§12.4c)**, which binds it to the mandatory `revoke`-delta obligation.

---

## 12. RECONCILIATION-TARGET READS & SWEEPS (recon #1–#5) + C25

### 12.1 `market.get_market_sale_status` (§1.4) — recon #2. `market.get_ticket_history` (§1.2) — recon #5. Door-freeze read — recon #3 (see §12.4). Credential offline contract — recon #4 (edge, see §13).

### 12.2 `market.sweep_expired_p2p_transfers()` — **DB-RPC (definer batch; recon #1)**
- **Purpose:** TTL sweep that transitions `initiated` p2p transfers past `expires_at` to **`expired`** and
  **unlocks the atom**. **Actor:** `service_role`/system sentinel (cron/heartbeat). **Params:** none (or a
  batch bound). **Preconditions:** `status='initiated' AND expires_at < now()`. **Locks & order:** per row
  **Transfer** → **Ticket Atom** (`FOR UPDATE`, ascending). **SSCAS:** member #7 reverse (unlock).
- **Writes:** calls `market.cancel_p2p_transfer(..., reason='expired')` per row → `market.p2p_transfer` (→
  `expired`), `kernel.unlock_ticket`; **and, as the tick's SECOND STATEMENT, `market.offer` (`pending →
  expired WHERE expires_at < now()`)** — §20.8.5 folded the offer expiry tick into this sweep *"rather than
  given its own function"*, and this Writes line was the one place that never said so (declaration omission,
  repaired 2026-08-29; presentational only — enforcement is `respond_offer`'s arithmetic, `S-12`/§4.3.1, and
  `T-SCHEMA-OFFER-01` tests with this sweep DISABLED for exactly that reason). **Result:** `{ swept_count }`. **Retry:** idempotent/re-entrant (only
  acts on still-`initiated` rows). **Forbidden callers:** clients (definer-only).

### 12.3 `market.sweep_paid_pending_sales()` — **DB-RPC (definer batch; C25 auto-compensation)**
- **Purpose:** the C25 sweep that finalizes `market.market_sale` rows stuck in
  `sale_state='paid_pending_transfer'` past the **bounded dwell SLO**: either complete the transfer (if the
  payment is verified and the atom is still transferable) or **auto-compensate** (refund-void → `terminal_state
  ='compensated'`), driving the RN "Finalizing…" flip (recon #2). **Actor:** `service_role`/system sentinel.
- **Preconditions:** `sale_state='paid_pending_transfer' AND paid_pending_since < now() - dwell_slo`. **Locks
  & order:** **Listing** → **Ticket Atom** → **Payment** (complete branch) OR **Ticket Atom** → **Refund**
  (compensate branch). **SSCAS:** member #2 (complete) XOR member #9 (`paid_pending_transfer` compensation).
- **Writes (XOR):** complete → `kernel.transfer_ticket_ownership` (`market_sale`, `terminal_state:=completed`; for a buy-now sale the complete branch is `market.finalize_market_sale` §20.8.10 — one completer body, webhook-prompt or sweep-late);
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

### 12.5 `kernel.sweep_expired_ticket_atoms(p_limit int)` — **DB-RPC (definer batch)** · `EXEC: DEF` · `NEW RPC` (schema §1.5.1, `MN-4`; filed as §13.7 `S-22`)

> **`kernel.tickets.state='expired'` is in the CHECK, its transition is specified in §7.6, and no function in
> any of the sixteen packages wrote it.** This sweep exists in the schema spec, the migration plan and the
> package registry (`079`) **and in zero RPC contracts and zero RLS EXEC rows.** *"Contract it and give it an
> EXEC row"* is `S-22` verbatim; this is that contract. Ratification **C109**.

- **Purpose.** Advance `active → expired` for atoms whose `catalog.event_session` ended more than
  `config('ticket.expiry_grace')` ago. **Actor:** `service_role`/`pg_cron` only — **no human path**; the
  actor of record is the **`SN-SYSTEM` sentinel** (schema §1.16), which is a scheduler identity and never a
  human. `REVOKE EXECUTE FROM anon, authenticated`.
- **HOW LOAD-BEARING IT IS, STATED FIRST, BECAUSE THAT IS WHAT DECIDES THE REST OF THE CONTRACT.** One
  expects the security consequence to be *a ticket to a past show can still be listed or transferred*. **It
  cannot.** `kernel.is_transfer_frozen` freezes **every atom of a session** once
  `now() >= catalog.effective_freeze_at(session)` (`079`), and that boundary is at **doors** — strictly
  before the session ends. **The load-bearing guard is already arithmetic and already stronger than the
  label.** `expired` is **presentational**: it is what makes *My Tickets* render a past ticket as spent
  rather than live, and what keeps a venue's atom counts honest after the night. **Same posture as
  `venue.sweep_expired_door_sessions` (§9.8) and `kernel.sweep_expired_door_overrides` (§17.11); the opposite
  of `venue.sweep_expired_inventory_holds` (§20.3.3) and `kernel.sweep_expired_refund_requests` (§17.4),
  which return a stored counter and release a custody hold.**
- **THE STANDING RULE THIS INHERITS — §4.3.1's, second instance, and it is binding on every OTHER contract,
  not on this one.** **No path may trust `state <> 'expired'` because the tick was supposed to have run.**
  A transfer, listing or admission precondition that reads `state <> 'expired'` as an expiry check is
  **wrong**, however green it looks: it is a test of whether a cron ran. Every such precondition must test
  the **arithmetic** (`is_transfer_frozen` / `effective_freeze_at`). **Nothing does today and nothing may
  start** — which is exactly why this sweep can ride an existing heartbeat instead of getting its own
  control.
- **Preconditions.** `state = 'active'` **AND** the atom's session ended by more than the grace window.
  **`scanned`, `voided` and `expired` atoms are left alone — they are terminal (§7.6)** and re-writing a
  terminal state is how a sweep becomes a second writer of somebody else's column.
- **Locks & order.** Bounded batch of `p_limit`, `FOR UPDATE SKIP LOCKED` on `kernel.tickets` — **rank 5**,
  the only rank taken. **SSCAS:** `n/a` — **a bounded batch of one**, the construction `catalog.cancel_event`
  and `venue.open_door_manifest` already use. **No member added; C28's closed fifteen stands.**
- **Writes.** `kernel.tickets.state → 'expired'`, **and nothing else. It appends NO
  `kernel.ticket_ownership_log` row and bumps NO `credential_version`** — an expiry is a **lifecycle fact,
  not a custody move**, and the atom's owner does not change. **`kernel.tg_custody_head_is_ledger_tail`
  (schema §1.6.2) therefore does not fire on it, which is precisely why `state` was kept outside that
  trigger's clause set.** A sweep routed through the transfer engine would be the wrong construction **and**
  would trip the trigger at COMMIT. **No audit row** — an expiry is arithmetic reaching a label, not a
  privileged mutation (same posture as §9.8). **No DELETE, ever.**
- **Result.** `{ swept_count }`. **Idempotency / retry.** Re-entrant by construction: a second run in the
  same window is a no-op, and `SKIP LOCKED` makes concurrent runs safe. **It must not raise on an empty
  batch.**
- **Scheduling.** The **2-minute `pg_cron` heartbeat that already runs** — the one `081`'s
  `venue.sweep_expired_inventory_holds` uses. **No new cron entry**, and it is therefore **not blocked on the
  `COND-A` outbox ruling.** **SEAM-1: it reads `catalog.event_session` (`078`) and writes `kernel.tickets`
  (`079`) → `max(078, 079) = 079`.** `078 → 079` is already declared; **no edge, no package change.**
- **Forbidden.** Every client and every human role. **No caller may treat a non-`expired` state as evidence
  the session is live.**
- **Tests.** `T-SCHEMA-EXPIRY-01` (schema §1.5.1 — an `active` atom of an ended session becomes `expired`,
  **and no ownership-log row is appended and `credential_version` is unchanged**; both halves, because the
  first passes even if the sweep went through the transfer engine) · **`T-RPC-SWEEP-01`** (structural: **no
  transfer, listing or admission precondition in the corpus reads `state <> 'expired'` as an expiry test** —
  asserted over the function set, because a single behavioural test cannot see a guard that is merely
  redundant today and load-bearing after someone deletes the arithmetic one).
- **Reported, not applied here (§20.14 `R-30`).** `PHASE_2_RLS_PERMISSION_SPEC.md` §11 needs an **EXEC row**
  for this function — `DEF`, `pg_cron`/`service_role` only, `REVOKE EXECUTE FROM anon, authenticated`. It has
  none, which is half of what `S-22` asked for.

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
**That sentence was their entire specification — the C33 key lifecycle, contracted in one line. Full
contracts are at §20.7.3–§20.7.5**, including the properties this line leaves out: that no parameter can
carry private key material, that rotation is one transaction because zero active keys stops the box office,
that `rotating` still verifies while `revoked` invalidates every live credential, and that a revoke with no
active successor is refused.

---

## 14. SSCAS ENFORCEMENT (critical) — member → RPC map + lock-order proof

### 14.1 SSCAS member → RPC(s)

> **Numbering aligned to the canonical FIFTEEN-member enumeration in `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md`
> §15 C12** (consolidation 2026-08-25, Agent E finding E-1). CDM C12 numbering is authoritative; the
> earlier SPEC_FOUNDATION 9-member working list is provenance only.

| C12 # | SSCAS member (canonical, CDM C12) | RPC(s) | Aggregate classes locked, in global order |
|---|---|---|---|
| 1 | Primary issuance | `venue.finalize_primary_order` → `kernel.issue_ticket_atoms` | Event/Session → **Inventory(batch,shard asc)** → **Order** → **Ticket Atom(new)** → **Payment**(link) |
| 2 | Native sale / resale (C8) | `kernel.transfer_ticket_ownership` (called by market checkout — `market.finalize_market_sale`, §20.8.10 — / `respond_offer` accept / auction finalize) | **Listing** → **Ticket Atom(asc id)** → **Payment**(link) |
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
| 13 | Auction deposit-release | auction finalize sweep → `kernel.transfer_ticket_ownership` (+ deposit-auth void) | **Listing/Auction** → **Ticket Atom** → **Payment** | **(MVP-dormant — `OR-11`; modeled lock row preserved for the post-MVP surface)**
| 14 | Group-buy claim *(non-MVP; modeled only)* | future `venue.reserve_group_claim()` (A11 one legal door) | **Inventory**(hold) — single-class once inside the door |
| 15 | Wallet checkout *(non-MVP; modeled only — wallet is later-phase)* | future wallet-debit → `create_primary_checkout` path | **Order** → **Payment/Wallet-ledger** |

> **Addendum — §20.12.** The set-closure pass (§20) adds contracts for 49 previously uncontracted functions.
> Six of them participate in a member above **as callers**: `venue.issue_comp` (#1), `market.respond_offer`
> accept (#2 — already named in that row's cell), `kernel.admin_refund` and `market.on_atom_voided` (#3),
> `kernel.pay_promoter_commission` (#5), `market.create_listing` (#6, already named) and
> `market.cancel_listing` (#6 reverse). **No row above is rewritten and no member is added; the set stays
> closed at fifteen.** §20.12 gives each one's acquisition sequence and re-proves it ascending. The one
> ordering fact it introduces — `market.on_atom_voided` takes rank 4 inside member #3 and is therefore
> invoked **before** the rank-5 atom lock — is consistent with §14.2's NB below.

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
2. **RE-OPENED, then CLOSED with corrections.** The canonical form (`catalog.event_session.door_open_at` +
   the `kernel.is_transfer_frozen(atom_id)` helper, no stored `transfer_frozen` column) stands. But the
   *predicate* and the *recheck set* were both wrong, and §12.4 now carries the corrections: (a)
   `mark_ticket_scanned` **removed** from the recheck set — as written it rejected **every admission for the
   rest of the night**; (b) `transfer_ticket_ownership` and `accept_p2p_transfer` **added**, closing a freeze
   that gated transfer start but not completion; (c) the C25 **compensate** branch **exempted**, without which
   a sale caught by doors-open strands the buyer's money forever; (d) the predicate body replaced with the
   **total** form over `catalog.effective_freeze_at`, which was fail-open at NULL; (e) the
   "per-open-manifest-ticket narrowing per C43" that four documents described is **stated as deferred**, since
   the specified predicate is session-wide and C43 is `RATIFIED-MODELED-ONLY(GATE-M)`.
3. **`platform_support` refund ceiling (§11.4).** RLS §7.10 grants support a *capped* `refund_primary_order`;
   the schema names only `admin_refund` for platform. The exact support cap / escalate-to-risk boundary is
   deferred to policy (mirrors RLS §15.4).
4. **Settlement-close authority scope (§10.2).** Both `org_finance` and `venue_finance` are plausible;
   contract accepts either (mirrors RLS §15.3) — confirm org-level vs venue-level (drives payout).
5. **Native auction bid RPC. — CLOSED with a name and an open decision (§20.8.4).** MVP reuses the frozen
   external `public.bids`/`auto-finalize-auctions` engine (CONFLICTS #6); a native `market.bid` ledger is an
   **extension point**. What this entry got wrong was concluding that the *bid RPC* therefore needed no
   contract: **RLS §11.1 grants EXECUTE on it and plan `088` schedules it as an object**, so it is built
   either way, and it was built from a name nobody had written. It is now named **`market.place_bid`** and
   contracted at §20.8.4, together with `market.create_listing`, `cancel_listing`, `create_auction`,
   `make_offer` and `respond_offer` — **the whole six-function native write surface, which no section of
   §1–§19 contracted.** The residue is narrower and is stated as an `OPEN DECISION` rather than an omission:
   **what happens to a native-only auction that does not mirror to `public.listings`.** §20.8.4 proposes
   refusing it at `create_auction` in MVP; §20.14 R-9 files the ruling.
6. **`change_org_role` vs schema `grant_org_role`/`revoke_org_role`.** Contract uses the brief's names as the
   public surface; implementers may realize them as the schema's grant/revoke primitives (documented aliases).
7. **`kernel.close_settlement` is contracted in a package that precedes the table it reads.** It reads
   `venue.attribution` and writes `promoter_commission` payouts, but the settlement package lands **before**
   the promoter-engine package that *creates* `venue.attribution`. A function defined in the earlier package
   cannot reference a table created in the later one. **Resolution:** the settlement package defines
   `close_settlement` **promoter-agnostic**, and the promoter package issues a `CREATE OR REPLACE` adding the
   commission leg — so the partial unique index guaranteeing *at most one commission line ever per
   attribution* must also land with the promoter package, not before it. Owner: the migration-plan author.
8. **`kernel.approval_request`'s SSCAS status is FLAGGED, not assumed** (§17.1, RLS MD-1). Argued as an intent
   record; if a reviewer judges otherwise it is a sixteenth member and C28's closure needs a formal amendment.
   It is lock-ordered either way. **Unchanged by §20**, which adds two further parkers of an approval
   (`catalog.set_platform_config` §20.2.1, `kernel.grant_platform_role` §20.1.4, and the signing-key trio
   §20.7.3–§20.7.5) using the identical construction — so the flag's disposition covers them too, and **no
   §20 contract required a sixteenth member** (§20.0d, §20.12).
9. **The `notify` gate is DISPUTED and this document does not settle it** (§17.24, RLS MD-10). C7 is
   `RATIFIED · Gate P · MVP` and names `notify`; four implementation specs defer it to Gate L; the
   notifications spec explicitly declines to resolve the conflict. Its companion question — whether the event
   **outbox**, described by the domain architecture as *"the only new infrastructure Phase 2 introduces"*, is
   scheduled in any Phase-2 package — is also unanswered, and it is not.

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

### 17.0a `kernel.approval_request` — the two integrity rules the DATABASE cannot hold, stated as binding obligations (`APPR-SUBJ-1` · `APPR-SUBJ-2`; schema §1.13.3 / §13.7 `S-2`)

**Binding on every function that writes or reads a `kernel.approval_request` row** — §17.1, §17.2, §17.3,
§17.4, §10.3 and §20.2.1's parked arm.

> **The residual is ACCEPTED, and it is not equivalent to a constraint. Say so, or the next reader assumes
> it is.** `kernel.approval_request.subject_id` has **no foreign key, by necessity, not by omission**: it
> points at three different tables in three different packages, and the package order forbids the FK in
> both directions — the approval table is **`077`**, `venue.order` is **`082`**, `venue.settlement` is
> **`087`**. A polymorphic column cannot carry an FK anyway, and even a per-kind FK could not be declared
> from `077` against tables that do not exist yet. **So the integrity is relocated into the RPC layer or it
> does not exist at all.** What follows is the relocation. It is weaker than a constraint in exactly one
> way — **a direct `INSERT` by a superuser or a future definer bypasses it**, where an FK would not — and
> that residual is **accepted here on the record**, mitigated by the fact that every writer is enumerated
> (`T-RPC-AUTHZ-15`) and the table holds no client grant. **It must never be described as "equivalent to a
> foreign key", in this document or in a review.**

- **`APPR-SUBJ-1` (the REQUESTING function).** Before inserting, the requester **resolves `subject_id`
  under the subject's own lock, in the same transaction that writes the row** — `venue.order FOR UPDATE`
  (rank 3) for `subject_kind='order'`, `venue.settlement FOR UPDATE` for `'settlement'`, the key's latest
  `catalog.platform_config` row `FOR UPDATE` for `'config_key'` — and **raises `not_found` if it does not
  resolve.** The lock is not decoration: resolving without it lets the subject vanish between the check and
  the insert, which is the failure the FK would have prevented. `subject_kind` and the
  `action ↔ subject_kind` pairing (`AUTHZ-M2`) are written in the same statement, never inferred later.
- **`APPR-SUBJ-2` (the APPROVING function).** §17.2 **re-resolves `subject_id` under the same lock** as part
  of its "every precondition is re-evaluated under lock" rule, and **a subject that has vanished moves the
  request to `stale`** — with holds released — **never to `denied` and never to `approved`.** `stale` is the
  correct terminal state because nothing was decided: the approver is told to re-request, rather than
  discovering that an approval quietly executed against a row that is gone. This is the same disposition
  §17.2 already applies to a drifted amount or a re-tiered atom, extended to the subject itself.
- **Test.** `T-RPC-AUTHZ-15` (the set of functions inserting `kernel.approval_request` is **exactly**
  `{request_order_refund, request_org_payout, set_platform_config}`, structural over `pg_get_functiondef` —
  **because the enumeration is what the accepted no-FK residual rests on**; the moment a fourth writer
  appears, `APPR-SUBJ-1` is a convention again) · `T-RPC-AUTHZ-16` (a request whose `subject_id` is deleted
  while parked resolves to **`stale`** on approval — **not `denied`, not `approved`** — releases every hold,
  and writes no money row; asserted on all three `subject_kind` values, because one branch passing says
  nothing about the other two).

> **`required_approver_class` — two passes designed it independently and CONVERGED. The three-label set is
> kept.** RLS §17 **X-10** / §20.14 **R-16** filed
> `CHECK (required_approver_class IN ('org','platform','platform_admin'))`; schema §1.13.2 adopted that exact
> spelling and recorded the reason a two-label set (`org` · `platform`) is wrong: **it would let
> `platform_support` approve a raise of the cap that bounds `platform_support`** — `refund.issue` at
> `platform` is approvable by `platform_support`, and collapsing `config.set_money_key` into the same label
> hands the capped role the lever on its own cap (`AUTHZ-C1A2`). **The third label is not a tier refinement;
> it is the entire content of `AUTHZ-C1A2`.** No pass proposed narrowing it, and none may without re-opening
> that ruling.

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
  never supplies the org**); the covered-atom set; `expected_amount`; the tier; **`required_approver_class`**;
  and **every threshold's `(key, version)` from `catalog.platform_config`, pinned onto the request row** so a
  mid-flight config change cannot silently re-tier a parked request and an auditor can reconstruct why a
  refund took the tier it did.
- **`required_approver_class` is written here, and it is the ONLY thing that carries the tier forward
  (`AUTHZ-C1A`).** The `status` values below (`pending_approval`, `pending_platform_review`) are **this
  function's return strings**. They are not stored anywhere: `kernel.approval_request.state` is
  `pending · approved · denied · cancelled · expired · stale`, and until now the table had **no tier column at
  all**. So the tier the table below decides was computed, returned to the caller, and **discarded** — and
  §17.2's authority branch, which claims to branch on it, had nothing to read. This function therefore
  **persists the tier as `required_approver_class ∈ {org, platform, platform_admin}`**, set server-side from
  the same evaluation that produced the row of the table, and **pinned exactly as `config_versions` is**:
  a later config change may no more re-class a parked request than it may re-tier one. **It is never a
  parameter and never derived from `payload`.** *(Schema: RLS §17 X-10.)*
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
  `refund_exposure_minor(payment) + p_amount_minor ≤ payment.total`, the latter under `FOR UPDATE` on
  `public.payments`. **The same aggregate feeds the tier test — §17.1a; computed once, after the lock, used
  twice.** (7) **Parked branch only:** `NOT kernel.is_transfer_frozen(atom)` for every atom, else
  `frozen` — a request may not be *parked* on a door-open session (§12.4c). Below-threshold *execution* is
  unchanged and still voids the ticket at the door.
- **Tier decision (server-side, from config). Every row's operand is `cumulative`, defined in §17.1a — never
  `p_amount_minor` alone.**

  | Condition | Outcome (returned) | `required_approver_class` (**stored**) | Effect |
  |---|---|---|---|
  | buyer caller, within `refund.buyer_self_service_window_hours` and `cumulative ≤ refund.buyer_self_service_max_minor` | `executed` | *(none — nothing is parked)* | direct |
  | org caller, `cumulative ≤ refund.org_auto_execute_max_minor`, no consumed atom | `executed` | *(none)* | direct |
  | org caller, `cumulative ≤ refund.org_dual_control_max_minor` | `pending_approval` | **`org`** | park + hold |
  | any consumed (scanned) atom, `refund.scanned_atom_policy = 'platform_review'` | `pending_platform_review` | **`platform`** | park + hold |
  | org caller, `cumulative > refund.org_dual_control_max_minor` | `pending_platform_review` | **`platform`** | park + hold |
  | any consumed atom, `refund.scanned_atom_policy = 'refuse'` | `rejected` | *(none)* | none |

  **The consumed-atom row takes precedence over the amount rows.** A scanned atom routes to `platform` **even
  when the amount is below `refund.org_dual_control_max_minor`** — the trigger for platform review is the
  *consumed custody*, not the size. That ordering is the whole point of `MD-6` (*"staff scans a friend in,
  then refunds"*), and it is stated explicitly because a table read top-to-bottom by an implementer produces
  the opposite result: the org-amount row would match first and the collusion shape would be handed to the
  org arm. **`T-RPC-MONEY-01` covers one case per row and one case for this precedence.**

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
  `kernel.approval_request` (INSERT `pending`, **with `required_approver_class`, `subject_kind='order'` and
  `subject_id := p_order_id` — the `action ↔ subject_kind` pairing of RLS §16.1 `AUTHZ-M2` is written here, not
  assumed**), `kernel.tickets.resale_state := 'refund_hold'` on each covered **voidable** atom,
  `kernel.admin_audit` (`refund.request`).
- **Grant maturity on the org arm (`AUTHZ-C1B`; contract: §1.1e).** An `org_owner`/`org_finance` caller must
  satisfy `kernel.money_role_grant_matured(order.org_id)` — **`order.org_id`, resolved under the order's own
  lock, never a parameter**. **This binds the REQUESTER, not only the approver**, and
  that is deliberate: SoD-2 is a pair, and a control applied to one half of a pair is applied to neither. A
  freshly-minted second account can no more open the request than close it. `sod_violation` on failure —
  **not** `insufficient_privilege`, because the role is genuinely held and telling the operator "permission
  denied" would send them to re-check a grant that is correct.
- **Why the hold is on the atom row.** It is the row the scan path already locks, so the guard costs nothing
  on the door hot path and adds no cross-schema read to `record_scan` (R8 scan isolation preserved). The
  existing `lock_ticket` precondition `resale_state='none'` then does all the work: an atom at `refund_hold`
  **cannot** enter a p2p transfer or a listing, with no new check written anywhere.
- **Idempotency.** `p_command_key` unique per `(actor, key)` on `kernel.approval_request`; the executed branch
  inherits `kernel.refund.idempotency_key`. **A replay returns the original outcome, never a second refund.**
  A *second, different* partial refund on the same order mints a new `refund_id` and therefore a new,
  non-colliding key — so successive partials compose correctly **as keys**. **`MB-1`: key composition is not
  authority composition.** That sentence is true of idempotency keys and was false of the tier, and it read
  as though one implied the other. Partials still compose as keys; **their authority is decided on the
  cumulative operand of §17.1a**, so the N-th partial is tiered on the sum of all N, not on its own size.
- **Result.** `{ status ∈ {executed, pending_approval, pending_platform_review, rejected, noop_replay},
  refund_id?, request_id?, amount_minor, **cumulative_minor**, atoms_voided[], atoms_not_voided[{atom_id,
  reason}], tier, required_approver_class? }` — **`cumulative_minor` is returned (`MB-1`) so an operator sent
  to dual control on a small refund can see that it was the payment's accumulated exposure and not their own
  amount that tiered it**; a tier the surface cannot explain is a tier the surface will be asked to work
  around. **`approval_required_role` is renamed to `required_approver_class` so the
  returned value and the stored column are the same word.** Two names for the same fact is how the tier went
  missing in the first place.
- **Errors.** `insufficient_privilege(42501)` · `sod_violation` · `precondition_failed` · `custody_moved` ·
  `conflict_locked` · `frozen` · `not_found` · `over_refund` · `policy_violation` · `step_up_required` ·
  **`step_up_unavailable`** (§17.7's `AUTHZ-M4`).
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
  `T-RPC-MONEY-05` (replay returns the original outcome, exactly one refund row) · **`T-RPC-MONEY-21`
  (`MB-1` — the splitting regression: N calls each at or below `refund.org_auto_execute_max_minor` against
  one payment; the call at which `cumulative` crosses the ceiling returns `pending_approval`, and **no
  sequence of calls moves more than the ceiling without an approval**)** · **`T-RPC-MONEY-22`** (the same for
  the buyer arm: a second self-service refund on the same payment tiers on the sum, not on its own amount).
- **Policy:** none, and none is possible — see §0.8.

#### 17.1a The tier operand is CUMULATIVE, and the aggregate is the PAYMENT (`MB-1`)

> **Predicate-identical to `PHASE_2_MONEY_AUTHORITY_SPEC.md` §6.1a by construction** — the two tier tables
> were corrected in the same pass, for the reason `C75` records: there is no precedence rule between delta
> specifications, so two copies of one predicate must be made to agree at the moment they are changed, never
> reconciled afterwards.

> **THE DEFECT THIS REPLACES.** Every row of §17.1's tier table compared **the single call's
> `p_amount_minor`** against its threshold. The only aggregate anywhere was the over-refund ceiling
> (precondition 6), which bounds the **total to the order value** and says **nothing about the tier**.
> **Consequence: one `org_owner` or `org_finance` refunds an arbitrarily large order to zero without ever
> reaching `pending_approval`, by issuing ⌈total / `refund.org_auto_execute_max_minor`⌉ calls each at or below
> the auto-execute ceiling.** SoD-2 on refunds was unenforceable against the exact insider it names — not
> because the control was weak, but because the control was never reached. The idempotency bullet made it
> worse by blessing the shape: *"successive partials compose correctly"* is **true of the keys and false of
> the authority**, and nothing said so. **The edge spec's `check_rate_limit(user, 'refund-execute', 10, 60)`
> is not the missing control:** 600 calls an hour is a throughput limit, not a value limit. It is named here
> because it is the control a reviewer reaches for, and reaching for it is how this survives review twice.

**Definition (one aggregate, stated once, used by every refund tier row in the corpus).**

> `refund_exposure_minor(payment)` :=
> **Σ `kernel.refund.amount_minor`** for that `payment_id` whose `status ∈ {pending, submitted, succeeded}`
> — every refund that is not `failed` (schema §1.10)
> **+ Σ `kernel.approval_request.amount_minor`** of every request against that payment whose
> `state = 'pending'` — parked, holds live, money not yet moved.
>
> **`cumulative` := `refund_exposure_minor(payment)` + `p_amount_minor`.** Every threshold in §17.1's table,
> and the `refund.platform_support_max_minor` cap at §17.2, is compared against `cumulative`. **No refund
> threshold anywhere in this corpus is compared against a single call's amount.**

Parked requests resolve to the payment through `venue.order` → `kernel.payment_native` → `public.payments` —
the same link `venue.finalize_primary_order` (§6.3) writes and `kernel.refund_primary_order` (§11.4) reads.
Refunds from other causes count: an `event_cancelled` refund from `catalog.cancel_event` (§4.4), an
`admin_refund`, or a C25 auto-compensation (§12.3) each raise the exposure and tighten the tier of the next
org refund on that payment. **More money already returned means more scrutiny, not less** — stated because it
will otherwise be read as a bug the first time an org hits it.

**Why the payment, and why no time window.** Derived, not chosen:

1. **It is the subject the over-refund ceiling already sums** (precondition 6). One aggregate serves both
   guards; a second subject for the tier would be a second aggregate that can disagree with the first.
2. **The lock already exists.** Precondition 6 takes `public.payments` `FOR UPDATE`, and `kernel.refund`
   carries `payment_id` NOT NULL with an index on it (schema §1.10). The cumulative test adds **no lock, no
   lock-order rank, no SSCAS member, no index** — this contract's rank-6 Payment acquisition is unchanged and
   `RLS MD-1` / D-1 are not reopened.
3. **It is the subject the money rail aggregates against** — a refund is `refunds.create` on the original
   charge — so the database's aggregate and Stripe's are the same set and cannot drift.
4. **Invariance under decomposition, which only this subject has.** A rolling *time* window is defeated by
   waiting; an *actor*-scoped window is defeated by the second money principal — **the collusion counterparty
   SoD-2 is named after** — so an actor-scoped aggregate is the one shape that fails against precisely the
   attacker the control exists for. Σ over the payment is invariant: the parts of an order sum to the whole,
   so splitting a refund into N calls changes **no** tier decision.
5. **The corpus already uses a cumulative operand wherever an authority is per-act** —
   `comp.per_staff_step_up_max_units` / `comp.per_staff_step_up_window_hours` count *"this actor's
   `comp.allocate` and `comp.issue` units within the window"* (§20.5.1). **The pattern was in the corpus and
   the refund table did not use it.**

**The sum is computed AFTER the payment lock, in the same transaction, or it is a per-call test with extra
steps.** Two concurrent sub-ceiling calls must serialize on the row the over-refund guard already locks, so
the second observes the first. A cumulative test evaluated before that `FOR UPDATE` reproduces the defect in
the form hardest to see in review.

**The parked term needs a COLUMN and may not be read from `payload`.** No authority predicate in the approval
functions reads `payload` (`T-RPC-AUTHZ-01` asserts it structurally), and the cumulative operand is an
authority input, not evidence. `kernel.approval_request` therefore requires **`amount_minor integer`**,
server-set at request time, **pinned exactly as `required_approver_class` and `config_versions` are**, never a
parameter, NULL only for `action = 'config.set_money_key'`. **`C57`'s lesson repeated: a tier decided from a
value the row does not store is a control that does not run.** Additive, package `077`; filed as §20.14
`R-27`.

**The buyer arm — the ambiguity is settled here, and the operand is stated.** The buyer row said only
*"≤ `refund.buyer_self_service_max_minor`"*, and **no document said whether that cap bounded the refund
amount or the order's eligibility.** The readings have opposite security properties: under the *amount*
reading a buyer drained an arbitrarily large order in ⌈total / cap⌉ calls; under the *eligibility* reading the
key silently meant *"which orders may be self-serviced at all"*, which no document states and no surface
shows. **Settled: the operand is `cumulative`, the same as every other row** — one operand for the whole
table, because a table in which one row means *this call* and another means *this order* gets implemented as
whichever the reader assumed. **Consequence, stated rather than left to be discovered: a buyer may self-serve
part of an arbitrarily large order, up to `refund.buyer_self_service_max_minor` in total on that payment** —
bounded absolutely, every atom voided their own, recency still bounded by
`refund.buyer_self_service_window_hours`. **An additional order-value exclusion, if the owner wants one, is a
second independent conjunct with its own key — money spec `D-9`, not decided here.**

**What this does NOT decide.** The **numbers** remain owner decision `D-3` and none is chosen here — but they
now denominate a **cumulative ceiling per payment**, so `D-3` must be answered against that reading.

**Adjacent tiered money actions, checked rather than assumed.** `payout.*` has the same shape and is worse —
§10.3 `MB-1b`. Payout **destination change** (§17.7) carries no value tier and is not splittable by value.
**Comps** (§20.5.1) were already cumulative-over-window and are the precedent above.

### 17.2 `kernel.approve_refund_request(p_request_id, p_decision, p_reason_code, p_command_key)` — **EDGE-FRONTED** · `NEW RPC`

- **Purpose.** The second act of dual control. On approve, release the holds and call the canonical money
  writer. On deny, release the holds and terminate the request. **Dual control cannot be done in one
  transaction** — two humans, two sessions, two points in time force a durable pending object — which is why
  §17.1 has two branches rather than one.
- **Role — `AUTHZ-C1A`: the branch is keyed on `(action, required_approver_class)` and on NOTHING ELSE.**

  > **The defect this replaces, stated plainly because it is the highest-severity finding in this document.**
  > The old text branched on `pending_approval` vs `pending_platform_review`. **Those two strings are §17.1's
  > return statuses. They are not stored.** `kernel.approval_request.state` is
  > `pending · approved · denied · cancelled · expired · stale`; the table had **no tier column**; and this
  > function's own re-evaluation list named the order, the atoms and the amount — **not the tier**. An
  > implementer with the schema in front of them has three discriminators to branch on (`action`, `state`,
  > `org_id`) and **all three route every parked refund to the org arm.** The result is not a mis-routed
  > queue item: **an org executes a refund the tier table sent to platform review** — above the dual-control
  > ceiling, or on a **consumed (scanned) atom**, which is the collusion shape `MD-6` exists to surface. The
  > control read as present in four documents and was absent in the only place it ran.

  | `action` | `required_approver_class` | May approve |
  |---|---|---|
  | `refund.issue` | `org` | `has_org_role(request.org_id, ['org_owner','org_finance'])` **AND** `auth.uid() <> request.requested_by` **AND** `kernel.money_role_grant_matured(request.org_id)` |
  | `refund.issue` | `platform` | `is_platform(['platform_support','platform_risk','platform_admin'])`, **`platform_support` bounded by the cap re-evaluated per `AUTHZ-M3` below — against `cumulative` (§17.1a), never this request's amount alone (`MB-1`)** |
  | `payout.request` | `org` | as `refund.issue`/`org`, **plus the §17.7 destination-setter exclusion applied to the APPROVER** — otherwise the destination-setter simply approves instead of requesting |
  | `payout.request` | `platform` | `is_platform(['platform_risk','platform_admin'])`. **`platform_support` is denied** — it holds no payout authority anywhere else, and the generic approval object must not become the place it acquires one |
  | `config.set_money_key` | `platform_admin` | **`is_platform(['platform_admin'])` ONLY**, AND `auth.uid() <> request.requested_by` — see the note below. **NO maturity floor: `kernel.money_role_grant_matured` is org-scoped and cannot be applied here — `AUTHZ-C1C`, filed as §20.14 `R-22` / ratification `C77`. This arm is the C58 attack one plane up and it is deliberately, visibly open pending an owner ruling** |

  Common to every arm: SoD-2 (`auth.uid() <> requested_by`), enforced **structurally** and backed by the table
  constraint pair of `AUTHZ-M1` — `CHECK (approved_by IS NULL OR approved_by <> requested_by)` **and** the
  companion `CHECK (state <> 'approved' OR approved_by IS NOT NULL)` **without which the first is vacuously
  satisfiable by any writer that forgets the column.** Plus step-up per `AUTHZ-M4`. **Bound by
  EDGE-CALLER-JWT.**

  **`state = 'pending' AND NOT expired` is an ACTIONABILITY precondition, never an authority input.** Those
  are two questions and they get two columns. **No authority predicate in this function reads `payload`** —
  `T-RPC-AUTHZ-01`, structural, over `pg_get_functiondef`.

  > **`AUTHZ-C1A2` — `config.set_money_key` takes a second distinct `platform_admin`, and never
  > `platform_support` or `platform_risk`.** The money spec §7.3 says *"a second distinct `platform_admin`"*.
  > This contract and RLS §11.3 both previously stated the whole non-org arm as
  > `is_platform(['platform_support','platform_risk','platform_admin'])` — one predicate spanning three
  > different approval flows. Under it, **`platform_support` approves the raise of its own ceiling**: the role
  > capped precisely because it is not trusted with unbounded money is the role that lifts the cap, and the
  > cap it lifts is the one bounding it on the arm directly above. Raising `refund.org_auto_execute_max_minor`
  > is, in the money spec's own words, a larger act than any single refund it would then authorize — it is the
  > authority behind every later refund, so it takes the highest authority in the system, twice.
  > **`T-RPC-AUTHZ-03`.**

- **`action`-dispatched.** The same function serves all three flows. **`action` alone is not the dispatch key
  — `(action, required_approver_class)` is.** A single `action` spans two approver classes (a refund parked at
  `org` and a refund parked at `platform` are the same action with different authority), which is precisely
  why branching on `action` was never sufficient and why the missing column was invisible.
- **Preconditions.** Request `state = 'pending'` and not expired. **Every §17.1 precondition is RE-EVALUATED
  under lock at approval time — the stored payload is *evidence*, never authority.** Specifically: the order
  is still refundable; the atoms are still owned by the buyer; the payment sum guard still passes; the amount
  is **recomputed** from `venue.order_item` and must still equal the pinned `expected_amount`. Drift ⇒
  `precondition_failed`, and the request moves to **`stale`** with holds released, rather than executing on
  stale facts.
- **The tier is re-derived and must still equal the pinned class.** The re-evaluation list above named the
  amount, the atoms and the order — **and not the tier**, which is the other half of why `AUTHZ-C1A` went
  unnoticed: nothing re-checked a value nothing stored. The recomputed tier (from the **pinned**
  `config_versions`, not from live config) must equal the stored `required_approver_class`; a mismatch is
  **`stale`**, never a re-route. In particular **an atom that became `scanned` while the request was parked
  re-tiers it to `platform`** — and because a re-tier is `stale` rather than a silent escalation, the org
  approver is told to re-request rather than finding their approval quietly ineffective. `T-RPC-AUTHZ-02`.
- **The re-derivation uses the CUMULATIVE operand, and EXCLUDES this request from the parked term (`MB-1`).**
  `cumulative := refund_exposure_minor(payment) − this_request.amount_minor + recomputed_amount` (§17.1a).
  Without the exclusion **every parked request double-counts itself and re-tiers upward on its own approval**,
  so a correctly-tiered `org` request goes `stale` the moment its approver touches it. The error fails in the
  **safe** direction, which is exactly why it survives a value-based suite; `T-RPC-MONEY-23` names it.
  A **genuine** rise in exposure while parked (another refund executed meanwhile) re-tiers upward and is
  `stale` — the same disposition `AUTHZ-C1A` already specifies, and no new one is introduced.
- **`AUTHZ-M3` — the support cap binds HERE, under lock, and an unset key is ZERO.**
  `refund.platform_support_max_minor` was applied at **request** (§17.1's tier table) and appeared at approval
  only as the prose *"subject to the support cap."* **Prose is not a predicate, and approval is the act that
  moves the money** — on the `platform` arm it is reachable by `platform_support` directly, with no org
  approver in the loop. The cap is therefore re-evaluated against **`cumulative` as §17.1a defines it**
  (**`MB-1`** — the recomputed amount **plus** the payment's existing exposure, this request excluded from the
  parked term; a cap applied to the recomputed amount **alone** is defeated by N parked sub-cap refunds on one
  payment, which is §17.1's split one arm over — `T-RPC-MONEY-24`), against the
  version **pinned in `config_versions`** (so the cap a request was tiered under is the cap it is approved
  under), exactly as every other precondition in this list is. Over the cap ⇒ `insufficient_privilege` naming
  the cap, and the request stays `pending` for `platform_risk`/`platform_admin` — **it is not denied**, since
  the refund may be perfectly legitimate and only the approver is wrong.
  **An unset or NULL key evaluates to ZERO, not unbounded** — `COALESCE(config, 0)` — so a missed seed row
  means *support may approve nothing*, which is loud, rather than *support may approve anything*, which is a
  missing-row-shaped privilege escalation on the one platform role the model deliberately caps. `MD-3` still
  owes the number; it no longer owes the behaviour when there is no number. `T-RPC-AUTHZ-04`.
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
  *"a different person must approve this"* rather than "permission denied" · **`sod_violation`** (grant
  immature, or the payout destination-setter) · `insufficient_privilege` · `precondition_failed` ·
  `not_found` · `conflict_locked` · `step_up_required` · **`step_up_unavailable`**.
- **The generic-payload footgun, named and mitigated.** A generic `payload jsonb` invites the approval to
  become a client-supplied authority vector (*"approve this, amount = X"*). The payload is **server-computed
  at request time and re-derived and re-compared here**; the stored copy exists for the approver's UI, and the
  executing code trusts **nothing** in it. A mismatch is `stale`, **never an override**. **The mitigation was
  a rule with nothing checking it; `T-RPC-AUTHZ-01` now checks it** — and the reason that matters is
  `AUTHZ-C1A`: with the tier absent from the row, `payload` was the *only* place a diligent implementer could
  have found it, so the missing column was actively pushing the authority branch into the one structure this
  paragraph forbids it to read.
- **Tests.** `T-RPC-MONEY-06` (self-approval raises `self_approval`) · `T-RPC-MONEY-07` (a payload mutated
  between request and approval ⇒ `stale`, holds released, no refund) · `T-RPC-MONEY-08` (the approver of a
  payout may not be `payout_destination_set_by`) · **`T-RPC-AUTHZ-01`** (**no authority branch in any of the
  three approval-dispatched functions reads `payload`** — structural) · **`T-RPC-AUTHZ-02`** (a request parked
  at `org` whose atom is scanned while parked ⇒ `stale` on approval, holds released, **no refund**, and the
  org approver is **never** able to complete it) · **`T-RPC-AUTHZ-03`** (`platform_support` and `platform_risk`
  are both refused `action='config.set_money_key'`; the **requesting** `platform_admin` is refused; a second
  distinct `platform_admin` succeeds) · **`T-RPC-AUTHZ-04`** (with `refund.platform_support_max_minor`
  **deleted**, `platform_support` approves nothing at any amount; `platform_risk` on the same row succeeds) ·
  **`T-RPC-AUTHZ-05`** (`AUTHZ-C1B`: an `org_owner` who mints a second `org_finance` **through the real
  `invite_org_member` / `accept_org_invite` path** cannot approve their own request while the grant is
  immature — the fixture must perform the mint, because **the mint is the attack**) ·
  **`T-RPC-MONEY-23`** (`MB-1` — **the self-exclusion**: a single parked request approved with no other
  activity on the payment does **not** go `stale`, i.e. the cumulative recomputation excludes the request
  under approval from the parked term; and a request parked while a *second* refund executed meanwhile
  **does** go `stale`, so the test distinguishes the two rather than asserting only the happy path) ·
  **`T-RPC-MONEY-24`** (`MB-1` — `platform_support` cannot approve N parked refunds on one payment, each
  under `refund.platform_support_max_minor`, whose **sum** exceeds it; the approval at which `cumulative`
  crosses raises `insufficient_privilege` naming the cap and the request stays `pending`).

### 17.3 `kernel.cancel_refund_request(p_request_id, p_reason_code, p_command_key)` — **DB-RPC** · `NEW RPC`

- **Role.** the requester · `has_org_role([org_owner, org_finance])` of the request's org · platform.
- **Preconditions.** Request `state='pending'`. **Locks:** **Ticket Atom(s)** ascending (release the overlay)
  → **Approval** (`FOR UPDATE`). **SSCAS:** single-aggregate + atom overlay.
- **Writes.** `kernel.approval_request` (→ `cancelled`), `kernel.tickets.resale_state := 'none'` per held
  atom, `kernel.admin_audit` (`refund.request_cancelled`). **Idempotency:** terminal state + `p_command_key`.
- **Result.** `{ status, request_id }`. **Errors.** `not_found` · `precondition_failed` ·
  `insufficient_privilege`.
- **Notification (`OR-15`, 2026-08-29):** emits `refund_request_cancelled` (best-effort class per `OR-14`) — a buyer whose refund request/hold is cancelled or reverted is told; the silent reversion was the N3 ninth-candidate defect.


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

- **Role.** `has_org_role(p_org_id, ['org_owner'])` **only**, with **step-up**, **and
  `kernel.money_role_grant_matured(p_org_id)`** (`AUTHZ-C1B`; contract: §1.1e — and here `p_org_id` **is** the
  row being mutated, so no scope-binding gap of the §10.3 kind exists). `org_finance` is **excluded entirely** — under
  O-3 it holds payout-request authority, and one identity may not hold both halves of the named fraud
  primitive (*redirect the bank account, then release funds to it*). **Bound by EDGE-CALLER-JWT** — and this
  is the RPC where the rule bites hardest, because the step-up predicate reads `auth.jwt()`, which on a
  service-role client carries no `aal` and no `amr` at all.
- **Why maturity binds the SETTER and not only the requester.** SoD-1's whole content is *"the identity that
  set the destination may not request the payout to it."* An `org_owner` who mints a second `org_finance`
  account satisfies that by **setting as A and requesting as B** — so a maturity check applied only to the
  requester is defeated by moving the fresh account to the other side of the pair. **Both halves of both
  primitives carry it, or neither does.**
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
  | 2 | **Destination probation** — the **first** payout to a destination changed within `payout.destination_probation_days` is **created `pending` by `close_settlement` and NOT advanced to `submitted` by `request_org_payout`, carrying `hold_state='probation_hold'` + `hold_reason_code` + `held_at`, `held_by` NULL** (§10.3's probation arm), releasable only by `is_platform(['platform_risk','platform_admin'])` via the existing `release_payout`. **`SPEC CORRECTION` (`S-15`/`S-14`; ratification `C105`): this cell read *"is created `held` … needs no new column"*. `kernel.payout.status='held'` NEVER EXISTED** — it is absent from the enum and from plan §5's CHECK — **and *"needs no new column"* was false under every candidate repair**, since even adding a CHECK label is DDL. It is **four additive columns on `kernel.payout`** (`hold_state`, `hold_reason_code`, `held_by`, `held_at`; schema §1.9/§1.9.1), no new table, no new RPC, no new package, no edge. **The ratified behaviour is unchanged: money does not leave, and only `platform_risk`/`platform_admin` release it (O-3)** | money leaving to a fresh destination unreviewed | a support touch on the first payout |
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
- **`AUTHZ-M4` — an ABSENT freshness claim RAISES; it does not evaluate.** The predicate compares
  `auth.jwt()->>'aal'` and the newest `amr` timestamp against config. **If the claim is absent, the comparison
  is against NULL** — and NULL is not true, so a predicate written as `stale_check` denies while one written
  as `NOT (fresh_check)` admits. **The system's actual security posture would be decided by an operator
  precedence, on a question the bullet above says has not been checked against a real token.** One of those
  two spellings is a lockout and the other is a silent bypass of the control on the highest-value money write
  in the system, and nothing in the corpus says which gets written.

  > **The rule: an absent `aal` or `amr` claim raises `step_up_unavailable` — a distinct error — and never
  > evaluates to a pass or a fail.** The failure is then **loud in both directions**: the money action does
  > not proceed, *and* the operator sees a cause that names the real problem instead of a permission denial
  > that sends them hunting through role grants that are correct. It also converts `MD-7`'s open question into
  > a first-run failure: if this project's tokens do not carry `amr`, **the very first money action says so**,
  > and the documented degradation to `iat` is then adopted as a **deliberate, labelled config choice** rather
  > than inferred from behaviour months later.
  >
  > Applies at every step-up site: this function, `request_org_payout`, `approve_refund_request`,
  > `allocate_comp`, `issue_comp`, and every `R✱` cell of ROLE_MODEL §5.3.
  > **`T-RPC-AUTHZ-06`:** a token carrying **no** `amr` claim raises `step_up_unavailable`, asserted
  > **distinctly** from `step_up_required` (a stale claim) and from `42501` (a role failure), at all five
  > sites — three distinguishable outcomes, because a test that only asserts "it failed" would have passed on
  > either broken spelling.
- **Locks & order.** **Organization** row `FOR UPDATE` (admin plane, outside the six money/custody ranks) →
  nothing else. **SSCAS:** n/a (single aggregate).
- **Writes.** `kernel.organization` (`stripe_connect_account_ref`, `payout_destination_set_by := auth.uid()`,
  `payout_destination_locked_until := now() + config('payout.destination_cooldown_hours')`),
  `kernel.admin_audit` (`org.payout_destination.change`, `subject_kind='organization'`, before/after = Stripe
  account ids, `reason_code` **mandatory**).
- **Errors.** `insufficient_privilege` · `sod_violation` (grant immature) · `step_up_required` ·
  **`step_up_unavailable`** · `precondition_failed` · `not_found`.
- **Tests.** `T-RPC-MONEY-12` (`org_finance` is refused) · `T-RPC-MONEY-13` (the setter is refused a
  subsequent `request_org_payout` **after** the cool-down elapses — the permanence of SoD-1) ·
  `T-RPC-MONEY-14` (a stale-`amr` token raises `step_up_required` and writes nothing) · **`T-RPC-AUTHZ-07`**
  (`AUTHZ-C1B`: a second `org_owner` minted through the real invite/accept path is refused **both**
  `set_org_payout_destination` and `request_org_payout` while immature) · **`T-RPC-AUTHZ-06`** (an absent
  `amr` claim raises `step_up_unavailable`, distinctly from both of the above).

### 17.8 `kernel.list_approval_requests(p_org_id, p_filters, p_cursor)` — **DB-RPC (read)** · `NEW RPC`

- **Role.** `has_org_role(p_org_id, ['org_owner','org_finance'])` · `is_platform`. The second approver's inbox.
- **Params.** `p_org_id` untrusted, re-checked; `p_filters` a closed set `{state[], action[], date_from,
  date_to}`. **Locks:** none. **SSCAS:** n/a.
- **Returns.** `request_id, action, subject_kind, subject_id, amount_minor, tier, state, requested_by
  (display), requested_at, expires_at, reason_code` — **and the evidence payload marked as evidence**, never
  as an authorization input.
- **Errors.** `insufficient_privilege` · `not_found`.

### 17.9 `kernel.record_money_denial(p_action, p_subject_kind, p_subject_id, p_error_code)` — **DB-RPC** · `NEW RPC`

- **Purpose.** Append a `*.denied` audit row **for an action that failed**. Exists because §0.3 writes audit
  **in the same transaction** as the action, and a failed predicate `RAISE`s — which rolls the transaction
  back and takes the audit row with it. **Postgres has no autonomous transactions.**
- **Why it matters:** repeated failed attempts to change a payout destination or fire a payout are the
  **single highest-value fraud signal in the system, and today they leave no trace at all.**
- **Actor — `SPEC CORRECTION` (`S-17`; schema §1.12.1; ratification `C106`). THE PREVIOUS TEXT MADE THIS
  FUNCTION FAIL ON ITS FIRST CALL, IN PRODUCTION, ON THE FRAUD PATH.** It read *"`service_role` only;
  `REVOKE EXECUTE FROM anon, authenticated, public`. **No human path.**"* — and this function's **entire
  purpose is to name the human who was just refused.** On a `service_role` connection `auth.uid()` is NULL,
  `kernel.admin_audit.actor_identity` is `NOT NULL FK→auth.users`, and the FK forbids an invented sentinel:
  **the INSERT cannot satisfy its own constraint.** The corrected rule, which is the schema's design:

  > **`SECURITY DEFINER`, `EXECUTE` to `authenticated` ONLY — never `anon`, never `service_role` — and it is
  > BOUND BY EDGE-CALLER-JWT** (§0.1a) like every other money RPC. **`actor_identity := auth.uid()`,
  > server-derived. It RAISES when `auth.uid()` IS NULL**, so a service-role invocation fails loudly instead
  > of writing a wrong row — the same fail-closed shape `T-RLS-EDGE-01` asserts for every human-predicate
  > RPC. **The signature keeps its four parameters and NO actor parameter is added**, so this is not the
  > `p_user_id`-trust pattern (C35/`S-6`) in a new place.

  **Residue removal, 2026-08-29 (`ID-5` / `ROLE_MODEL` §11.4 `P-6`).** After `S-17` landed in this body,
  this section's own **heading** and §0.1a's closing sentence still carried the superseded `EXEC: DEF`
  label — which made this document fail its own `T-RPC-GLOBAL-02` and made the capability map's
  `DEF`-exclusion rule fire on a stale tag. Both labels are now removed. The function's grant class is the
  §0.1a **default** (caller-authorized), which carries no heading tag by this document's own convention;
  nothing about the grants, the signature, or the semantics changed with the labels.

  **Definer because `kernel.admin_audit` is audit-only/deny-all.** Not granted to `anon` because a denial
  before authentication has no principal to record and belongs to rate-limiting, not to audit.
  **Who knows the principal at the moment of denial?** Not the database — that transaction was rolled back.
  Not the scheduler. **The edge, and it holds the principal as a verified JWT** — the *same* client it built
  for the call that was just denied. The denial log is that call's second transaction on that same client.
  **This EXTENDS EDGE-CALLER-JWT's scope by one function; it weakens nothing.**
- **The pollution vector, named because granting a write to `authenticated` deserves the argument.** A
  malicious authenticated caller can now insert denial rows. It **cannot forge `auth.uid()`**, so every row
  it writes is **about itself**: it cannot frame another principal and it cannot suppress a row (the edge
  writes those). It can only make its own denial count look worse and grow the table. Bounded by three
  things that all already exist: `p_action` is validated against a **closed allow-list of money `*.denied`
  names**; `(subject_kind, subject_id)` is validated against the same pairing rule `APPR-SUBJ-1` imposes
  (§17.0a); and the call is **rate-limited per actor** through the production
  `public.check_rate_limit(p_user_id, p_action, p_max, p_window_seconds)` (migration `005`, applied).
- **Rejected repairs** (schema §1.12.1 carries the full table): a `p_actor_identity_id` parameter is the
  C35-forbidden pattern with nothing to validate it against; the `SN-SYSTEM` sentinel **destroys the only
  fact the row exists to carry** (*"how many denials"* is not *"by whom"*); making `actor_identity` nullable
  weakens a `NOT NULL` on the audit backbone for one writer, and the nullable rows would be the ones that
  matter most.
- **Why it is NOT in the definer-only exclusion list.** RLS §3.1 lists it among RPCs with *"no human actor
  by construction"*. **The genuine members of that list are the cron sweeps** — `sweep_expired_refund_requests`,
  `market.sweep_expired_p2p_transfers`, `market.sweep_paid_pending_sales`,
  `kernel.sweep_expired_door_overrides`, `catalog.sweep_implicit_door_freezes`,
  `kernel.sweep_expired_ticket_atoms` (§12.5) — and they are served by the `SN-SYSTEM` sentinel of schema
  §1.16. **A denial has a human actor. It is the only reason to write the row.**
- **Locks:** none. **SSCAS:** n/a. **Writes:** `kernel.admin_audit` (`<action>.denied`, `actor_identity :=
  auth.uid()`). **Idempotency:** none required — a denial is an event, and duplicates are informative rather
  than harmful.
- **Contains no payload from the failed call** beyond the four parameters, so a denial can never become a
  side channel for the data the denied call was refused.
- **Tests.** `T-SCHEMA-AUDIT-01` (invoked on a **`service_role`** connection it **RAISES** and writes no row
  — asserted on the service-role path deliberately, because that is how it was contracted and it is the call
  that cannot satisfy `actor_identity NOT NULL`) · `T-SCHEMA-AUDIT-02` (on the caller's own JWT it writes
  exactly one row whose `actor_identity` **equals `auth.uid()`**, and **no parameter can change that value**
  — asserted structurally over the signature, because a later "convenience" parameter is exactly how this
  returns) · `T-SCHEMA-AUDIT-03` (`p_action` outside the closed allow-list raises; `anon` holds no
  `EXECUTE`).
- **Reported, not applied here (§20.14 `R-28`).** `PHASE_2_RLS_PERMISSION_SPEC.md` must remove this function
  from §3.1's definer-only exclusion list and change its §11 EXEC row from `DEF` to *`authenticated`,
  EDGE-CALLER-JWT-bound*; `PHASE_2_MONEY_AUTHORITY_SPEC.md` §8.4 Control 6 must drop *"no human path"*.
  **Five documents said `service_role`-only in six places and the schema says the opposite; it cannot both
  raise on a service-role connection and be callable only on one.**

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
  `market.p2p_transfer` / `market.listing_native` (drained → `cancelled`, `reason_code='door_freeze'`) **via
  `market.on_door_freeze_engaged` (§17.10a — ratified `C110`: a `venue.*` function writing `market.*` rows
  directly was a §0.7-shape violation AND a `42P01` before `088`; the hook is the sanctioned cross-schema
  form, stubbed `086`, replaced `088`)**,
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

### 17.10a `market.on_door_freeze_engaged` · `market.door_freeze_drain_preview` — the C110 hooks, contracted at the owner — `NEW RPC` ×2 (SEAM-2; ratified `C110`)

> **Added 2026-08-29 (writer-parity pass, `RC-6`).** `C110` ratified these two hooks — signatures frozen by
> `SEAM-2a` — and they were carried by the migration plan, the package registry and the ratification record
> while **this document contracted neither and §17.10's Writes row still described the pre-`C110` direct
> write.** That is the one divergence shape transcription cannot fix, because transcription runs the other
> way: the ratified correction had landed everywhere EXCEPT the canonical owner. Both contracts below are
> **transcription of `C110`, not new design** — the drain semantics are §17.10's own text, relocated behind
> the sanctioned cross-schema form §17.12 names (*"the owning schema exposes a definer primitive and the
> calling schema invokes it in the same transaction"*).

- **`market.on_door_freeze_engaged(p_event_session_id uuid, p_cause_ref uuid) RETURNS TABLE (drained_transfers
  integer, drained_listings integer, atoms_unlocked integer)`** — **DB-RPC (definer hook)** · `EXEC: DEF`.
  Stubbed **`086`** (returns zeros, writes nothing), `CREATE OR REPLACE`d **`088`**. Real body, in the
  caller's transaction: drain `market.p2p_transfer` and `market.listing_native` to `cancelled`
  (`reason_code='door_freeze'`), excluding `market_sale.sale_state='paid_pending_transfer'`
  (`T-RPC-DOOR-12`), and unlock the drained atoms via `kernel.unlock_ticket` (§7.4). **Sole caller:**
  `venue.open_door_manifest` (§17.10), same transaction as the freeze. **Writes:** `market.p2p_transfer`,
  `market.listing_native` (and `kernel.tickets.resale_state` via `kernel.unlock_ticket`). **Zero drained is
  the true count, not an inert one, for every package before `088`** — no overlay can exist either, because
  `kernel.lock_ticket`'s only callers are themselves `088` (`C110`).
- **`market.door_freeze_drain_preview(p_event_session_id uuid) RETURNS TABLE (pending_transfers integer,
  active_listings integer, excluded_paid_pending integer, atoms_to_unlock integer)`** — **DB-RPC (definer
  read hook)** · `EXEC: DEF` · **writes nothing.** Stubbed `086` (zeros), replaced `088`. Sole caller:
  `venue.preview_door_open_impact` (§20.6.3), before the confirm enables (dashboard §12.4).

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

### 17.14 `venue.resolve_order_attribution(p_order_id)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC`

- **Purpose.** The promoter-attribution precedence engine, and the **sole writer of `venue.attribution`**.
- **Actor.** `service_role`/definer only; `REVOKE EXECUTE FROM anon, authenticated`. Called **only** from
  `venue.finalize_primary_order` **inside the paid transaction** (§6.3).
- **Preconditions.** Called with the order row already locked `FOR UPDATE` by the caller, in the transaction
  setting `status='paid'`.
- **Reads (no locks taken).** `venue.order` (the candidate columns), `venue.order_item`,
  `venue.promoter_code`, `venue.promoter_code_scope`, `venue.promoter_link`, `venue.promoter`,
  `catalog.event_session → event`, `kernel.payment_native` (instrument fingerprint, for self-deal detection).
- **Locks & acquisition order.** **None of its own.** The only lock in the path is the caller's **Order**
  (rank 3), which `finalize_primary_order` already holds. **This is a deliberate constraint on the design, not
  a lucky outcome:** any version of this feature that locked a promoter or code row during checkout would have
  required a constitutional amendment **and** created a deadlock class between "a manager deactivates a code"
  and "a buyer checks out". **A promoter engine must never be able to stall a checkout.**
- **SSCAS.** `n/a`. **Member #1's lock sequence is unchanged**, and member **#5 (Attribution → commission)**
  keeps its ratified shape — attribution is **read**, not locked, at settlement close. **C28's closed fifteen
  and its lock order stand unamended.**
- **Writes.** **0 or 1** `venue.attribution` row. Nothing else.
- **Idempotency.** `UNIQUE(order_id)` — a replayed finalize hits the constraint and the function returns the
  **existing** row.
- **The race at the freeze boundary, and why it is deliberately not serialized.** A manager deactivates a code
  at the same moment a checkout commits. Whichever state the resolver's snapshot saw is final: if the status
  flip commits first the code reads `inactive` and no attribution is written; if the checkout commits first
  the attribution stands and the deactivation binds only future sales. A benign sub-second race with a
  deterministic outcome in **both** directions.
- **CROSS-CUTTING RULE, binding on this and every promoter RPC.** **No attribution condition — unknown code,
  deactivated code, out-of-scope code, malformed input, missing promoter, rate-limited preview, or resolver
  error — may abort a checkout, refuse a payment, or roll back an issuance.** Because this function runs
  inside `finalize_primary_order`, **a raise here would roll back the money and the tickets.** It therefore
  **never raises**: every non-happy path resolves to "no attribution row", and an *unexpected* internal error
  is caught, written to `kernel.admin_audit` as `attribution.resolver_error` with the order id, and swallowed.
  **A missing commission is a support ticket; a failed checkout on a sold-out Friday is a business incident.**
  `INFERENCE:` this asymmetry appears in no binding input and is the single most important operational rule
  attached to this feature.
- **Tests.** `T-RPC-ATTR-02` (a deliberately faulted resolver still commits the order, the payment link and
  the atoms, and writes `attribution.resolver_error`) · `T-RPC-ATTR-03` (finalizing twice produces exactly one
  attribution and the second call returns the first row) · `T-RPC-ATTR-04` (both race orderings).

### 17.15 Promoter-code management — `venue.create_promoter_code` · `create_promoter_codes_bulk` · `set_promoter_code_status` · `set_promoter_code_scope` · `set_promoter_code_window` — `NEW RPC` ×5

- **Role (all five).** `has_venue_role(venue,['venue_manager','venue_promoter_manager'])` OR
  `has_org_role(['org_owner','org_admin','org_promoter_manager'])`, scoped to the promoter's org. **A promoter
  is explicitly forbidden from minting their own codes.** A self-minted code is a self-minted *distribution
  surface over the org's namespace*: the promoter could seize `CLUBSPACE`, `NYE`, or a rival's brand, and
  because codes are immutable and the namespace is global, **those grabs are permanent**. The org must be the
  issuer. (The *request* path — a promoter asking for a code — is a legitimate product need and is a
  notification/inbox flow, **not a permission**.)
- **Locks:** none cross-aggregate. **SSCAS:** n/a (single aggregate). **Idempotency:** `p_command_key`; a
  replay returns the same `code_id`, while a *different* command key with the same normalized code returns
  `code_taken` — **never a silent second code**.
- **`create_promoter_code`** — preconditions: promoter `active` and in the caller's org; normalization passes
  the length/alphabet CHECKs; every scoped event belongs to the promoter's org; `valid_until > valid_from`;
  for `kind='generated'` the display form meets the entropy floor. Writes one `venue.promoter_code` + N scope
  rows + `kernel.admin_audit('promoter_code.issue')`. Returns `{ status, code_id, code_display,
  code_normalized, confusable_with[] }` — `confusable_with` lists existing codes within edit-distance 1, for
  an issue-time warning; **that index is issue-time only and is never touched at checkout.** Errors:
  `code_taken` · `invalid_code_format` · `promoter_inactive` · `event_out_of_org` · `entropy_below_floor` ·
  `unauthorized`.
- **`create_promoter_codes_bulk`** — `p_count` **capped at 1,000 per call**, so the transaction, the lock time
  and the audit row all stay bounded; a larger program is multiple calls. Server-side CSPRNG at the entropy
  floor; on a unique violation, retry that one code up to 5 times then **fail the call — never silently emit
  fewer codes than requested**. Writes N codes and **one** audit row recording `(promoter_id, count, kind,
  scope)`, not N. Errors add `count_exceeds_cap` · `generation_exhausted`.
- **`set_promoter_code_status` / `_scope` / `_window`** — audited; **neither scope nor window is
  retroactive**: no recorded attribution is affected. **Explicitly impossible:** changing `promoter_id`,
  `code_display`, `code_normalized` or `kind` — the immutability trigger raises regardless of caller **and no
  RPC accepts those parameters**. No-reassignment is enforced twice.
- **Tests.** `T-RPC-PROMO-01` (a promoter cannot EXECUTE any of the five) · `T-RPC-PROMO-02` (the same
  normalized code in two different orgs raises — global scope proven, not assumed) · `T-RPC-PROMO-03` (an
  UPDATE of `promoter_id`/`code_display`/`kind` raises as `postgres`, as `service_role`, and through every RPC
  above).

### 17.16 `venue.preview_promoter_code(p_code_display, p_session_id)` — **EDGE-FRONTED** (read) · `NEW RPC`

- **Role.** any `authenticated`; also reachable **unauthenticated only through the `promoter-code-preview`
  edge wrapper** (§17.17).
- **Returns exactly one of** `{ status:'eligible', promoter_display_name, method_hint:'code' }` **or**
  `{ status:'not_applicable' }` — **for every failure**: unknown code, inactive, out of window, wrong org, out
  of scope, inactive promoter. **The single response for all failures IS the design:** any distinction turns
  this into a code-existence oracle. The client copy is *"That code isn't valid for this event"*, which is
  true in every branch.
- **Writes:** none. **Locks:** none. **SSCAS:** n/a. **Rate-limited by its edge wrapper, not here.**
- **Advisory only.** A code that previews eligible may still lose at commit (a link cannot beat it, but a
  deactivation can). **The client must never persist the preview as the answer.**
- **Test.** `T-RPC-PROMO-04` — the `not_applicable` payload is **byte-identical** across unknown, inactive,
  expired, out-of-org and out-of-scope inputs, asserted by payload equality so an oracle cannot creep back in
  through a field.

### 17.17 The rate-limit adaptation — `public.check_rate_limit` and an unauthenticated principal

`public.check_rate_limit(p_user_id **uuid**, p_action text, p_limit int, p_window int)` is a **frozen Phase-0
function** (migration `005`), `GRANT EXECUTE … TO service_role` **only**. Two consequences bind this document:

1. **A rate-limited RPC cannot be a plain PostgREST call** — the limiter is unreachable from `authenticated`.
   That is why §17.16 is fronted by an edge function rather than called directly, and it is the *reason* that
   function exists, not an implementation detail of it.
2. **Its first parameter is a `uuid`, so it cannot rate-limit an unauthenticated principal at all.** A buyer
   may type a promoter code before signing in, and that path has no user uuid to key on.

> **Recorded as an ADAPTATION of a frozen function's contract, not a change to it.** The edge wrapper
> **derives** a principal — `uuidv5(NS_PROMOCODE, ip || ':' || sha256(user_agent))` — and passes it as
> `p_user_id`. The function is unmodified; a synthetic uuid is supplied where a real one does not exist.
> Limits: **10/min authenticated, 5/min anonymous per derived principal**, **fail-closed** (503 on limiter
> error, 429 over-limit). A burst of `not_applicable` results from one principal writes
> `kernel.admin_audit('promoter_code.enumeration_suspected')` and disables code entry for that session.
> **Flagged so it is a reviewed decision rather than a clever workaround, and because it will recur for every
> future anonymous-callable edge function.** Owner: the edge-spec author.
>
> `INFERENCE:` the derived principal is a **rate-limiting key only**. It is never persisted as an identity,
> never joined to a real `auth.users` row, and never used in an authorization predicate. An IP+UA hash is a
> weak, spoofable key; it is proportionate for an advisory preview whose every failure mode returns the same
> payload, and it would **not** be proportionate for anything that writes.
>
> The edge function must also **never log the submitted code string** at info level — only the outcome class.

### 17.18 `venue.bind_order_attribution` · `venue.review_attribution_flag` — `NEW RPC` ×2 (**was ×3**)

> **`AUTHZ-H10` — `venue.decide_flagged_attribution` IS DELETED. Two RPCs wrote one ledger under
> contradictory authority, and every product surface was wired to the permissive one.**
>
> `venue.review_attribution_flag` admitted **both promoter-manager labels**; `venue.decide_flagged_attribution`
> denied them, in a sentence this document itself wrote: *"a promoter manager adjudicating a flag against a
> promoter they recruited and are measured on is the fox at the henhouse."* Same ledger
> (`venue.attribution_review`), same decision (release / deny), **opposite authority.**
>
> **The restrictive one was decoration, and the ledger's own design is why.** `venue.attribution_review` is
> **append-only with effective decision = `max(seq)`** — chosen so a wrong decision is corrected by appending
> rather than editing. The conflicted party therefore never needs to overwrite anything: **they append
> `release` at `seq+1` through the permissive function, and it is the effective decision.** A deny-list on one
> writer is worth nothing while a second writer without it can append to the same ledger.
>
> **And the permissive one is the one that exists everywhere else.** Venue dashboard §10.7 / §21.4 Δ4 /
> screen E / E4, promoter-codes spec §7.7, and **migration plan `090`'s Functions row** all name
> `review_attribution_flag`. `decide_flagged_attribution` is named by RLS §11.5 and ROLE_MODEL §11 R-16 and by
> **no product surface and no package** — so it would have been the function nobody built, whose deny-list
> nobody enforced, cited as the reason the control existed.
>
> **Ruling: `review_attribution_flag` survives — name, contract, ledger semantics, package `090` — and takes
> `decide_flagged_attribution`'s restrictive allow-list**, which is the half that was load-bearing. `G5`'s
> cell is satisfied by the survivor; dashboard Δ4 and Δ7 are the same control and always were. Recorded in the
> naming register (§20.13) and filed to RLS/ROLE_MODEL/dashboard owners as **R-13**.

- **`venue.bind_order_attribution(p_order_id, p_code_display, p_link_slug, p_command_key)`** — attach or
  replace the *candidate* on a pending order (the "I forgot to enter the code" path). **Role:** the order's
  buyer, OR a door/box-office principal for an on-behalf order. **Pre:** `order.status = 'pending'`; at most
  one code and one link (two of either ⇒ `invalid_input`). **Locks:** the order row `FOR UPDATE` (rank 3 —
  inside the ratified order, no new class). **SSCAS:** n/a. **Writes:** the candidate columns + audit
  (`attribution.candidate_changed`, old → new). **Does not write `venue.attribution`.** A rebind while pending
  is **last-write-wins, audited, and not an error** — a buyer correcting a typo is the common case. Any
  binding attempted once `status <> 'pending'` ⇒ **`attribution_frozen`**. **Never fails the order:** an
  unresolvable code sets the candidate to NULL and returns `{ status:'ok', bound:false,
  reason:'not_applicable' }`.
- **`venue.review_attribution_flag(p_attribution_id, p_decision, p_reason_code, p_note, p_command_key)`** —
  adjudicate a self-deal flag; **the sole writer of `venue.attribution_review`.** **Role (`AUTHZ-H10`):**
  `has_venue_role(venue,['venue_manager'])` OR `has_org_role_over_venue(venue,['org_owner','org_admin'])` ·
  `is_platform(['platform_risk'])`. **BOTH promoter-manager labels are DENIED** — `venue_promoter_manager` and
  `org_promoter_manager`; ROLE_MODEL §5.3 **G5** marks both `·`, and a promoter manager adjudicating a flag
  against a promoter they recruited and are measured on is the fox at the henhouse (same separation-of-duties
  principle as propose-vs-approve). **`platform_admin` holds no EXECUTE here.** **Pre:** attribution exists,
  in scope, `self_deal_flag = true`, and **no
  `promoter_commission` settlement line exists for it** ⇒ else `attribution_settled`. **Locks:** none
  cross-aggregate. **SSCAS:** n/a. **Writes:** one `venue.attribution_review` row at `seq = max(seq)+1` +
  audit. **The attribution row is not touched.** **The effective decision is `max(seq)`** — a wrong denial is
  corrected by appending, never by an edit — and **supersession closes at settlement**: once the commission
  line exists, the money and the decision freeze together.
- ~~**`venue.decide_flagged_attribution(...)`**~~ — **DELETED (`AUTHZ-H10`).** Dashboard Δ7 and Δ4 are the
  same control; both are satisfied by `review_attribution_flag` above, which now carries this function's
  allow-list. **Nothing in the corpus is left without a writer**: `090`'s Functions row never named it.
- **The hold semantics these interact with.** An unreviewed flag makes the commission **`payable = 0`, and
  that is a HOLD, not a forfeiture.** Because at most one commission line may ever exist per attribution, a
  hold must **write no line at all** rather than a zero line — a zero line would consume the one slot and
  permanently forfeit a commission that adjudication might later release.
- **Tests.** `T-RPC-PROMO-05` (a flagged attribution produces no settlement line while unreviewed; `release`
  ⇒ the next close pays it; `deny` ⇒ no line ever, and the attribution stays visible) · `T-RPC-PROMO-06`
  (review after the commission line exists ⇒ `attribution_settled`) · `T-RPC-PROMO-07` (`seq` 2 overrides
  `seq` 1 and **both rows survive**) · **`T-RPC-AUTHZ-08`** (`AUTHZ-H10`: `venue_promoter_manager` and
  `org_promoter_manager` are refused, **asserted after a `venue_manager` has already written `seq=1`** — the
  attack is *appending over an existing decision*, so a test on an empty ledger would miss it — and **no row
  is written at any `seq`**) · **`T-RPC-AUTHZ-09`** (exactly **one** function in `pg_proc` writes
  `venue.attribution_review`).

### 17.19 `venue.get_my_promoter_summary` · `venue.list_my_attributions` · `venue.list_promoter_attributions` — `NEW RPC` ×3 (reads)

- **The first two derive authority from `venue.promoter.identity_id = auth.uid()` on a LIVE row (C9), never
  from `has_venue_role`** — which returns false for every promoter after the label's removal. **The promoter
  id set is derived from `auth.uid()` and is NOT accepted as input**, so the filter cannot be widened by
  passing a parameter.
- **`AUTHZ-M9` — these RPCs are now the ONLY promoter read path, because the direct grant that defeated them
  is gone.** RLS §9.17 previously gave the promoter **`A`** on `venue.attribution` — *"direct read via an RLS
  policy + column GRANT"*, i.e. **every column off the table** — while §16.7 and the projection below both
  state the redaction is *"enforced by the read RPC's projection, **not by hoping the client omits
  columns**."* **A direct grant defeats exactly that.** A promoter with `A` selects `displaced_promoter_id`
  (a rival's identity), the reviewer's private `note`, and **`touch_corroborated`** — the hijack-detection
  signal whose whole point is that the promoter must not see which of their hijacks were detected. Corrected
  to **`V`**: no direct SELECT on `venue.attribution` or `venue.attribution_review`; these two functions are
  the surface. `T-RPC-PROMO-11` is unchanged in intent and finally enforceable.
- **The own-row filter, stated once and used verbatim** (`AUTHZ-M10`): `promoter_id IN (SELECT promoter_id
  FROM venue.promoter WHERE identity_id = auth.uid() AND status='active')` — **never `promoter_id =
  auth.uid()`**, which compares a `venue.promoter` PK to an `auth.users` id and returns nothing, forever.
  §9.17's *"second correction"* wrote the broken form while correcting a different break in the same
  predicate; both failures present identically as an empty promoter dashboard, which is why this one survived
  the correction that was supposed to fix it.
- **`get_my_promoter_summary(p_org_id, p_event_id, p_window)`** — per-event and total: tickets attributed,
  gross attributed, commission accrued, commission **held** (flagged, unreviewed), commission **paid**, code
  count, link count. Reads `venue.attribution` filtered to the caller's own promoter rows and `kernel.payout`
  filtered to `cause='promoter_commission' AND cause_ref IN (those attributions)`. **This filter is the
  entirety of RLS §7.9's "scoped RPC"** — the promoter never touches the payout table and never sees an org
  aggregate. **Never returns** buyer identity, buyer contact, other promoters' order ids, org totals, or
  `instrument_fingerprint`.
- **`list_my_attributions(p_org_id, p_filters, p_cursor)`** — keyset pagination on `(order_paid_at DESC, id
  DESC)`. **Projection:** `occurred_at · event title · ticket type · qty · basis_minor ·
  credited_amount_minor · method · terms_version · self_deal_flag · self_deal_reasons · review decision +
  reason_code · payout status`. **Redacted:** buyer name/email/id, order ref, `displaced_promoter_id`, the
  reviewer's `note`, `instrument_fingerprint`, and **`touch_corroborated`** — the venue's hijack-detection
  signal; showing it to the promoter would turn a fraud control into a coaching tool for gaming it.
- **`list_promoter_attributions(p_scope_kind, p_scope_id, p_filters, p_cursor)`** — the back-office view.
  `has_venue_role(['venue_manager','venue_finance','venue_promoter_manager'])` OR
  `has_org_role(['org_owner','org_admin','org_finance','org_promoter_manager'])`. **No buyer PII in any
  projection** — it returns an order **reference**, never an attendee, so *the promoter dimension never
  becomes a back door into the attendee list*. `venue_scanner`, the door session, `org_member` and `promoter`
  are denied outright.
- **Locks:** none (reads). **SSCAS:** n/a.
- **Tests.** `T-RPC-PROMO-08` (promoter A cannot see promoter B's attributions — direct table **and** through
  every read RPC) · `T-RPC-PROMO-09` (**a code-sourced attribution, `link_id IS NULL`, IS visible to its own
  promoter** — the regression the §9.17 predicate correction prevents; without it a promoter sees none of
  their code earnings) · `T-RPC-PROMO-10` (no read RPC here returns buyer name, email, id or
  `instrument_fingerprint`, asserted by **column-list comparison**, not by inspection) · `T-RPC-PROMO-11`
  (`displaced_promoter_id` and `touch_corroborated` are absent from the promoter's own projection).

### 17.20 Demographics — `kernel.get_my_demographics` · `set_my_demographics` · `clear_my_demographics` · `venue.refresh_holder_mix` · `venue.unpublish_holder_mix` · `venue.unpublish_all_holder_mix` · `venue.get_holder_mix` · `venue.reconcile_holder_mix` — `NEW RPC` ×8 — **CORRECTED (`AUTHZ-DEM1`)**

> **`AUTHZ-DEM1` — three transcription defects, all of them corrections the demographics spec made to
> ITSELF after this section was written.** They are applied here because this document is what an
> implementer builds from, and on all three points it currently contradicts the binding source (§10.4).
> (1) **`set_my_demographics` / `clear_my_demographics` wrote an audit row** — deleted by that spec's
> **J-11**. (2) **`get_holder_mix`'s suppressed shape returned the denominators** — a per-person *"did you
> answer"* oracle, closed by **R6**. (3) **The §5.5 kill switch had no writer** — supplied by the
> `unpublish_*` pair below, which is why the count moves from six to eight.

- **`kernel.get_my_demographics()`** — **DB-RPC** read, `EXEC: authenticated`. **Params: none, and
  parameterless is load-bearing** — a signature with no identity argument makes *"read someone else's row"*
  **unexpressible**, not merely denied. Actor `auth.uid()`; raises `insufficient_privilege(42501)` when NULL.
  Returns `{ gender_identity, notice_version, updated_at }` or the empty set. **`first_answered_at` is stored
  but deliberately NOT projected** — its purpose is product analytics on the prompt, never per-person.
  Locks: none. SSCAS: n/a.
- **`kernel.set_my_demographics(p_gender_identity, p_notice_version)`** — write. Both params **untrusted** and
  re-validated in-body against the CHECK value set and the known notice-version list. **No identity parameter
  exists.** Upserts one row keyed by `auth.uid()`; sets `first_answered_at` on insert only; always bumps
  `updated_at`.
  **It writes NO audit row of any kind (`AUTHZ-DEM1`(1); demographics J-11).** This section previously
  specified `(identity_id, action, occurred_at)` — *"never the value"* — and that is **not sufficient**,
  because the source spec's own §8.3 names a timestamped history of a person's gender answers as *"the
  single worst artefact this feature could produce — it would record a **transition**"*, and
  `(identity, set → changed → cleared, when)` **is** that transition record with the value elided. There is
  also no table it could go in: the demographics schema delta names no audit object, so the only fitting home
  was `kernel.admin_audit` — **permanent and platform-readable** — which would have nullified the §8.5
  tombstone's purge window, the sole mitigation on offer. **The aggregate READ audit on
  `venue.get_holder_mix` is unchanged and remains binding**: that one records a staff member reading a room,
  not a fan answering a question about themselves.
  Idempotent. Locks: none. SSCAS: n/a. **There is no `kernel.admin_set_demographics` and no staff write path
  of any kind** (`T-RPC-DEMO-01`: the set of functions writing `kernel.identity_demographic` is **exactly**
  `{set_my_demographics, clear_my_demographics}`).
- **`kernel.clear_my_demographics()`** — withdrawal. Params: none. **Hard-DELETEs the caller's own row — the
  single named GP-2 exception (§0.5), inside the definer.** The value-free
  `kernel.identity_demographic_erasure` tombstone (with `purge_after`) is written by a **`BEFORE DELETE FOR
  EACH ROW` trigger on `kernel.identity_demographic`, not by this function** (demographics J-12), so **every**
  removal path produces one — withdrawal, the `auth.users` cascade, a definer delete, a future C38 merge. The
  cascade was the one path that wrote no tombstone, which made **the strictest erasure case the one case a
  post-restore purge could not re-apply.** **Writes no audit row** (`AUTHZ-DEM1`(1)): the tombstone is the
  only trace, it is value-free, definer-only, and self-purging — precisely the properties an
  `kernel.admin_audit` row would have destroyed.
  Idempotent (`noop_replay` when no row is present, **not** an error). Locks: none. SSCAS: n/a.
- **`venue.refresh_holder_mix(p_event_session_id)`** — **`EXEC: DEF`**, `pg_cron`. Reads the **declared read
  set** the churn rule actually needs (demographics §5.4): `kernel.tickets`, `kernel.ticket_ownership_log`,
  `venue.order`/`venue.order_item` (**zero/non-zero price test only**), `kernel.identity_demographic`,
  `venue.holder_mix_snapshot`, `catalog.event_session`/`event`/`venue`, `catalog.platform_config`. **Does not
  read** `venue.scan`, `venue.attribution`, `venue.ticket_type`, `public.profiles`, or any buyer identity.
  **Algorithm, in order (H-6 remediation — the previous text named three of these seven):** resolve the
  **R7-eligible** holder set — **comped and zero-price custody EXCLUDED**, because the privacy floors were
  otherwise proved against a population the operator controls, *and comps cost nothing while the
  `venue_manager` mints both the session and the comps* → compute `holders_total`, `holders_responded`,
  **`holders_excluded_ineligible`**, raw bucket counts → **R1** event minimum → **R3** merge (the fully
  determined procedure) → **R5** two-bucket / all-or-nothing → **R8** contributor-multiset churn gate, with
  its distinct-identity limb → **R9** cross-session near-duplicate gate over every published snapshot
  reachable by the same venue or org → persist. R2 is additionally a `CHECK` **on the table**; R4 by a writer
  assertion **and** by `get_holder_mix`'s read-side re-derivation; R6 by `get_holder_mix`'s return shape.
  **Writes** at most one snapshot (+ its buckets); **a discarded recomputation writes nothing**; publishing
  un-publishes the prior one. **Writes no contributor multiset and no identity reference of any kind** — the
  contributor set exists only inside the transaction. Locks: none — it reads `kernel.tickets` without locking
  and writes only its own derived aggregate, so it takes **no rank-5 lock and introduces no ordering
  obligation.** SSCAS: n/a — **not** a member of the closed set; touches no money, custody or inventory row.
  Returns `{ status ∈ {published, suppressed, discarded_churn_gate, **discarded_near_duplicate**} }` — **to
  `service_role` and the job log only; no client ever sees this value.**
- **`venue.unpublish_holder_mix(p_event_session_id)` · `venue.unpublish_all_holder_mix()`** — **ADDED here**
  (demographics §5.5 — the kill switch had no writer). Set `published_at = NULL` on the targeted snapshot(s);
  **delete nothing**; write **one `kernel.admin_audit` row per invocation**, naming the actor and the count
  affected. **`EXEC`: `service_role` / `platform_admin` step-up only; `REVOKE EXECUTE FROM anon,
  authenticated`.** Locks: the targeted snapshot rows `FOR UPDATE`. SSCAS: n/a. Idempotent — a snapshot
  already unpublished is not re-counted.
  `INFERENCE:` these **do** write audit where the fan-side writes deliberately do not, and the asymmetry is
  the point — an operator retracting a published aggregate is a privileged mutation with an actor; a fan
  answering a question about themselves is not. **Unpublish rather than delete**, because deleting destroys
  the evidence of what was shown, which is the one thing an incident review needs.
- **`venue.get_holder_mix(p_event_session_id, p_dimension)`** — read. **Exactly two parameters, and that IS
  the contract.** No `as_of`, no ticket type, no promoter, no source, no date range, no scan status, no
  limit/offset, no ordering, no free-form filter. **Adding a third parameter is a design change requiring
  privacy re-review, not a routine enhancement** — it is the differencing-attack contract (`T-RPC-DEMO-02`
  asserts the arity and parameter names). Authority: resolves session → event → venue → org, then
  `has_venue_role(venue,['venue_manager','venue_marketing','venue_promoter_manager'])` OR
  `has_org_role_over_event(event,['org_owner','org_admin'])` OR `is_platform(['platform_admin'])`; **denied**
  to `org_finance`, `venue_finance`, `venue_box_office`, `venue_scanner`, the door session, `promoter`,
  `platform_support`, `platform_risk`, `fan`, `anon`.
  - **The suppressed branch is a CONSTANT — `{ suppressed: true }`, and nothing else (`AUTHZ-DEM1`(2),
    R6).** No `reason`, no `holders_total`, no `holders_responded`, no `as_of`, no bucket rows. **This is the
    single most important line in the contract.** The previous shape returned the **denominators** on a
    suppressed snapshot, which lets a `venue_manager` **mint a throwaway session, comp one ticket to a
    target, and read `holders_responded ∈ {0,1}` as that person's "did you answer" bit** — the exact
    per-person proxy X-4 bans, reachable by the role that holds the card, at the cost of one comp. **The
    suppressed branch must have no other fields to fill.**
  - The published branch is `{ suppressed: false, as_of, holders_total, holders_responded, buckets:
    [{bucket, holder_count}, …] }`, where the buckets **always sum to `holders_responded`** so the residual
    is not computable. **Which branch you get is decided by the writer's suppression rules, never by the
    reader.**
  - **Read-side re-derivation, fail-closed — the second enforcement layer.** Before emitting the published
    shape the function re-checks, **on the row it just read**: `holders_responded >= 25` (R1);
    `min(holder_count) >= 5` (R2); `Σ holder_count = holders_responded` (R4); `count(buckets) >= 2` (R5);
    `holders_responded <= holders_total`. **Any failure returns `{ suppressed: true }` and raises a
    reconciliation alarm** — it never returns a partial or a corrected card. This layer is what makes a
    writer bug, a hand-written `INSERT`, or a restored-from-backup row **fail closed at the read**.
  - **Kill switch, read LIVE on every call.** `catalog.platform_config['demographics.holder_mix_enabled']`
    false ⇒ `{ suppressed: true }` for every session regardless of stored state; a snapshot with
    `published_at IS NULL` likewise. (The key is `restricted` under RLS §8.4 `AUTHZ-CFG1`; the function reads
    it inside the definer, so no client policy applies.)
  Writes one audit row **per call**; rate-limited per principal, fail-closed. Locks: none.
- **`venue.reconcile_holder_mix()`** — the nightly reconciliation job, **`EXEC: DEF`**. Asserts R4
  (`Σ buckets = holders_responded`) and R2 (`min(holder_count) >= 5`) across every published snapshot and
  alarms on violation, mirroring the C27 counter-vs-ledger discipline.
  **`INFERENCE:` the source spec classifies this as a `NEW RPC` but never names it.** Named here so it can be
  granted, tested and cited; flagged in §19 as authored, not transcribed.
- **`D-14`, recorded because it bounds what the floor actually means.** **Five roles hold both the roster
  read (`venue.list_attendees`) and the mix card** — `venue_manager`, `venue_marketing`, `org_owner`,
  `org_admin`, `org_marketing`. For them the floor of 5 is *"a bound over five people the reader can
  **name**"*. The floor remains the right control; the claim that it anonymises **against those five** is
  weaker than against a stranger, and is stated rather than assumed (CRM K-19(6)).
- **A consent rule that binds this document, not just the product.** **Widening who may see the aggregate — a
  new role, a new surface — requires a new `notice_version` and an in-app notice to everyone who has already
  answered.** Adding a role to `get_holder_mix`'s authority predicate is therefore an RLS/RPC change **with a
  product-side obligation attached**, and must not be treated as a routine matrix edit.

### 17.20a `kernel.write_demographic_erasure_tombstone()` / trigger `tg_identity_demographic_erasure` — **TRIGGER WRITER** · `NEW` (J-12; authored 2026-08-29 — name authored, shape DERIVED)

> **Four documents required this trigger; none named it; the plan's `077` row actively denied it; and its
> specified operation ("upserts") was incompatible with its own table's ratified append-only class.** The
> shape question is now CLOSED BY DERIVATION (sprint agent 6, 2026-08-29): DO-UPDATE is invalid by ratified
> invariant (the AO class is inside `C64`'s ratified set and `raise_append_only` is attached with no
> exemption text anywhere), and ON-CONFLICT-DO-NOTHING is eliminated by §8.5's own ratified purpose — the
> corpus itself already called it *"silently wrong… the second erasure is dated by the first."* **The
> unique surviving form is APPEND-MANY: pure INSERT, one immutable row per erasure, PK `id`** — which is
> also the only form under which the corpus's two physical definitions (DEMOG §10.2 vs SPEC_FOUNDATION)
> reconcile, and is the house event-log discipline (`identity_contact_pref_event` /
> `org_contact_consent_event`, `C70`/`K-19`). The names are authored (the §17.20 `reconcile_holder_mix`
> convention; flagged in §19). **Two of the register's six standing OR-2 blockers discharge with this
> contract** (the missing-from-package trigger; the UPSERT incompatibility); four stand (cascade-vs-AO on
> the contact/consent tables → ODR-16/4b · the `{N}` window → D-6 · the reaper + its ODR-4a class
> amendment · non-transactional deletion).

- **Form.** `BEFORE DELETE FOR EACH ROW` on `kernel.identity_demographic`; function `SECURITY DEFINER`,
  `search_path` pinned; **body references no gender column** (DEMOG §13 assertion 25 — asserted over
  `pg_get_functiondef`, the Wallet-31 construction).
- **Write.** Pure **INSERT** into `kernel.identity_demographic_erasure`
  `(identity_id, erased_at := now(), purge_after := now() + {N} + margin)` — value-free, **one row per
  removal, never an update of a prior row**. `{N}` is symbolic pending **D-6**; the contract is closed over
  it. Fires on EVERY removal path: `clear_my_demographics`'s definer DELETE (§17.20 — the path that exists
  under every ODR-16 ruling), the `auth.users` CASCADE (fires only under ODR-16 B/C), and any future
  definer delete (C38 merge).
- **Package.** Ships **in the same package as its table** (ratified, ODR-4 analysis) — `077` at HEAD; both
  move together if the ODR-4 Option-5 placement action executes.
- **Never:** raises on the happy path beyond the INSERT's own constraints; reads any other table; carries
  any demographic value.
- **Tests.** DEMOG §13 assertions **25** (no-gender-column, structural), **29** (**restated one-per-removal**
  per the split map's own instruction: clear → re-answer → clear yields TWO tombstone rows with distinct
  `erased_at`), **30** (cascade path yields its own row; tombstone FK-free so it survives the deletion that
  caused it).

### 17.21 Contact preferences and consent — `kernel.get_my_contact_prefs` · `set_my_contact_prefs` · `list_my_org_contact_consents` · `grant_org_contact_consent` · `withdraw_org_contact_consent` — `NEW RPC` ×5

- All five are **DB-RPC**, `EXEC: authenticated`, **own-row only**, and **none takes an identity parameter of
  any type.** `get_my_contact_prefs()` and `list_my_org_contact_consents()` are **parameterless**.
- **There is no staff-side write path — no `admin_set_contact_consent`, no `p_identity_id` anywhere.** **A
  venue can never record a contact consent on a fan's behalf.** `T-RPC-CRM-01` asserts this structurally: the
  set of functions writing `kernel.org_contact_consent` is exactly
  `{grant_org_contact_consent, withdraw_org_contact_consent}`, and **neither has a `uuid` parameter that could
  denote an identity.**
- **Every one of the three writes ALSO appends one row to an append-only event log, in the SAME transaction
  (`AUTHZ-CRM1`; CRM K-19(1)).** `kernel.identity_contact_pref_event` for the master switch,
  `kernel.org_contact_consent_event` for the per-org consent.

  > **Why the current-state rows are not sufficient, and why this is a correctness fix rather than
  > bookkeeping.** The export's consent gate has four conjuncts, **two of them mutable** (the master switch
  > and the per-org consent). §6.3 promises a build is **byte-identical on replay** and that per-export
  > membership is therefore not stored. But a paged build evaluates its conjuncts once per page, so with no
  > history it necessarily evaluates them **at inconsistent instants** — a fan who withdraws mid-build is in
  > page 1 and out of page 9. That falsifies the determinism claim, assertion 22, and the whole reason
  > membership is not persisted. The fix is `gate_as_of`, stamped at **claim** and re-stamped on re-claim
  > (one instant per build), **which is only answerable if both mutable conjuncts are as-of evaluable** —
  > hence the two logs. `INFERENCE:` the log is also what makes a **re-grant after a withdrawal**
  > representable at all: the current-state row holds one `granted_at` and one `withdrawn_at`, so
  > grant → withdraw → grant overwrites its own history — and that cycle belongs to the person who changed
  > their mind, who is exactly the person the record exists to protect in the dispute they are most likely
  > to have.
  >
  > **Both logs are AO, `REVOKE UPDATE, DELETE`, definer/`service_role` only, with an EMPTY client grant set
  > and zero policies** (RLS §6, §16.6). A column grant on `kernel.org_contact_consent_event` to
  > `authenticated` would publish a **timestamped history of who allowed which venue to email them and when
  > they changed their mind** — strictly worse than the current-state table it derives from, which is why it
  > inherits the same posture rather than a relaxed one on the grounds that it is *"just a log"*.
  >
  > **A no-op appends no event.** Re-granting an existing consent, re-withdrawing a withdrawn one, or setting
  > a preference to the value it already holds is a no-op update and writes **no** log row — otherwise the
  > log records a client's retry pattern rather than a person's decisions.
- `set_my_contact_prefs(p_venue_email_contact)` — the master kill switch; value re-validated in-body against
  the CHECK set; **appends one `kernel.identity_contact_pref_event` row**; idempotent; audited
  (`crm_contact.pref_changed`); rate-limited per identity.
- `grant_org_contact_consent(p_org_id, p_notice_version, p_source_order_id)` — `p_org_id` untrusted and
  re-validated as a live org; `p_notice_version` validated against the known list; sets `state='granted'`
  **and appends one `kernel.org_contact_consent_event(…, 'granted', …)` row in the same transaction**;
  re-granting is a **no-op update** appending no event; audited; rate-limited.
- `withdraw_org_contact_consent(p_org_id)` — sets `state='withdrawn'`, stamps `withdrawn_at`, **and appends
  one `…_event(…, 'withdrawn', …)` row in the same transaction**; idempotent (`noop_replay` if already
  withdrawn, appending no event). **Withdrawal is a state change, never a row deletion**; it takes
  effect **immediately on every on-screen read and at the next export build** — a build whose `gate_as_of`
  precedes the withdrawal is unaffected, **and that is the documented semantic, not an accident**.
- **`D-3` / K-6, carried here because it is an obligation on a function outside this document:** a
  contact-preference or contact-consent row **must never be repointed to migration 020's anonymized
  sentinel.** The row cascades away with the account or it stays with the person; pointing a live consent at
  the sentinel would make a deleted account appear to consent.
- **Locks:** none for any of the five. **SSCAS:** n/a. **Result shapes** for the three write RPCs are
  `{ status }` / `{ status:'noop_replay' }` — **authored here; the source spec states idempotency but no
  result shape** (§19).

### 17.22 CRM export — `venue.request_export` · `build_export_rows` · `finalize_export` · `authorize_export_download` · `revoke_export` · `claim_artifacts_for_purge` · `confirm_artifact_purged` · `reconcile_export_orphans` · `list_export_jobs` · `sweep_expired_exports` · `venue.list_attendees` · `venue.lookup_attendee` — `NEW RPC` ×12 — **CORRECTED (`AUTHZ-CRM2`)**

> **The CRM surface is now EIGHTEEN contracts: the five own-row contact RPCs of §17.21 plus the twelve here,
> plus `venue.assert_may_request` — the shared request/download predicate named below, which is a contract
> because two functions must evaluate the SAME one or they drift.** The three purge contracts and the
> template-scoped download are new; the count and the reasons are CRM K-9/K-15/K-16.
>
> **`AUTHZ-CRM2` — three signature-level defects, applied from the CRM pass's own remediation.**
> 1. **`finalize_export` was TOLD the numbers that are the only evidence its gate ran.** Parameters removed.
> 2. **`authorize_export_download` re-checked the ROLE SET and never the TEMPLATE** — so `org_marketing`
>    could download a colleague's **operations** export: order refs, order totals, unit prices, refund state.
> 3. **Nothing in the design could delete a Storage object.** Revoke, retention and the sweep all claimed to
>    delete and had **no agent**. Three definer contracts supply one.

- **`venue.request_export(p_scope_kind, p_scope_id, p_template_id, p_filters, p_command_key)`** — **DB-RPC**,
  the authorization and admission point. **Builds no data.** Authorizes per the two template allow-lists
  (audience: `org_owner`/`org_admin`/`org_marketing` at org grain, `venue_manager`/`venue_marketing` at venue
  grain; **operations, which adds money columns: `org_owner`/`org_admin`/`venue_manager` only** — the
  narrowest allow-list in either spec). **Rejects `scope_kind='all'` — it is not a member of the CHECK set.**
  Validates the filter set against a **closed conjunctive grammar** (anything outside it raises; no OR, no
  NOT, no nesting, no demographic filter name). Enforces the size caps **at request**, so a too-large job
  fails immediately rather than after a five-minute build. Rate-limits **fail-closed**. **Freezes `as_of :=
  now()`.** **Resolves and freezes `org_id` — the job's org — from the scope object, in the same transaction
  that authorized against it (XO-1a).** **Mints `kernel.org_customer_key` LAZILY on the org's first export
  (`OR-19` — R-39a = B): after authorization succeeds, insert-if-absent the org's key row — `key_material` a
  server-generated random 32 B, created inside this definer and nowhere else — keyed on the frozen `org_id`,
  then proceeds against whichever row now stands. Concurrent first requests converge benignly: every
  contender attempts the same insert-if-absent on the PK, exactly one insert wins, the rest are no-ops, and
  every committed job reads the single surviving row — one deterministic key per org, no retry, no error
  surfaced. The key material is never returned by this or any RPC, never logged, never in an error
  (CRM §4.3/§11.2); orgs that never export never have a key. This is the ONLY writer of
  `kernel.org_customer_key` (fence row); `venue.build_export_rows` READS it and never writes it — the
  `O17`/X-6 postgres-owned builder surface is unchanged.** Writes the job row `queued`, the key row when
  absent, **and** the `crm_export.request` audit row
  **with `constraint_set_version`** in the same transaction. Idempotent on `(auth.uid(), p_command_key)`.
  **Locks:** none. **SSCAS:** n/a. Returns `{ job_id, state, as_of }`.
  - **The authorization is `venue.assert_may_request(actor, scope_kind, scope_id, template_id)` — one
    function, shared verbatim with `authorize_export_download`** (`AUTHZ-CRM2`(2)). Two functions evaluating
    two copies of one allow-list is how the download check lost the template. **Contracted at §20.7.8
    (`R1-4`/`C108`) — it had a package number and nothing else until then. Called in RAISING mode here (the
    default); `p_raise := false` is used by `list_export_jobs` alone.**
  - `INFERENCE:` **freezing `org_id` here rather than resolving it at build time is not tidiness.**
    Authorization resolved the scope's org at request; a build-time re-resolution could read a **different**
    org for the same venue, because **`catalog.venue.org_id` is mutable while `catalog.event.org_id` is
    stamped at create**. A job must be built against the org it was **authorized** against, or the
    authorization proved something about a tenancy that no longer holds — which is the venue-grain leak at a
    re-operated venue (H-11).
- **`venue.build_export_rows(p_job_id, p_cursor, p_limit)`** — **`EXEC: DEF`**; `REVOKE EXECUTE FROM anon,
  authenticated`, **no human path**. **Re-derives authority from the job row's recorded actor and scope, not
  from the caller.** One bounded page, at the job's frozen `as_of`, in a **deterministic, demographic-free
  order** so two builds of the same job are byte-identical. **This function is the entire SQL surface that
  touches customer data**, and it **contains no dynamic SQL** (`T-RPC-CRM-02`: no `EXECUTE`, no `format(`, no
  `quote_ident(`). **Locks:** none. **Never logs a row.**
  - **It ACCUMULATES the four gate counters on the job row, page by page, inside the definer** — incremented
    by the code that evaluates each cell, not by code that is told the verdict (`AUTHZ-CRM2`(1)). This is
    where `finalize_export`'s numbers come from.
  - **The consent gate is evaluated at `gate_as_of`, ONE instant for the whole build** — stamped at claim,
    re-stamped on re-claim — read from the two append-only event logs of §17.21. A paged build that
    re-evaluates the two mutable conjuncts per page evaluates them at **inconsistent instants**, which
    falsifies the byte-identical-replay property that is the entire reason per-export membership is not
    stored.
  - **`emit_name := emit_email` — ONE predicate driving BOTH cells** (CRM K-18). `display_name` was
    previously emitted **on every row of every export at every org, ungated by consent**, from the one global
    `public.profiles.display_name` string — so two orgs union their files on it directly and corroborate with
    admission time, ticket types and acquisition route. **The per-org HMAC `customer_ref` removes the
    platform-supplied *stable* join key and nothing else** — that is the corrected claim, and the deleted one
    (*"the non-consenting majority … is unjoinable"*) must not be cited from an older copy.
    `display_name` **stays ungated on screen**, in the single-record lookup and in the door projection, where
    a surface cannot be unioned with another org's. `name_cells_emitted`/`name_cells_suppressed` join the
    counter pair; the legend covers both columns.
  - **XO-1a is this function's FIRST predicate, on every branch.** Every grain — `session`, `event`, `venue`,
    `org` — ANDs **`kernel.tickets.org_id = job.org_id`**, read from the job row and **never re-derived**.
    The `customer_ref` HMAC key is `org_customer_key(job.org_id)` and the consent gate's `EXISTS` binds
    `org_id = job.org_id`. `INFERENCE:` **these three must move together.** If a future refactor takes any
    one of them from the **atom** instead of the **job**, the venue-grain export at a re-operated venue leaks
    the prior operator's list — and, for the HMAC, **two orgs get the same pseudonym for the same person,
    joining their files directly**, which is the opposite of what the pseudonym exists to do.
- **`venue.finalize_export(p_job_id, p_row_count, p_byte_count, p_sha256, p_object_path)`** — **`EXEC: DEF`**;
  `running → ready`; writes `crm_export.generate`. Idempotent. Every `generate` row carries a non-null
  `constraint_set_version`.

  > **The gate counters are GONE from this signature, and that is the point (`AUTHZ-CRM2`(1); CRM K-19(3)).**
  > They were `p_cells_emitted, p_cells_suppressed` — **worker-supplied parameters** — for numbers the source
  > spec calls *"the only evidence the consent gate ran on this export."* **Evidence the caller hands you is
  > not evidence about the caller.** A worker that skipped, mis-evaluated or short-circuited the gate would
  > report whatever counts it liked, and every downstream check — the audit row, the auditor's query,
  > assertion 13 — would agree with it. Instead:
  > - **`venue.build_export_rows` accumulates the four counters on the job row, page by page, INSIDE the
  >   definer**, in the same statement that decides each cell. The counter is incremented by the code that
  >   **evaluates** the gate, never by code that is **told** what the gate decided.
  > - **`finalize_export` reads them from the job row and copies them into the audit payload. It cannot be
  >   told them.** The contract and the audit payload therefore agree by construction rather than by
  >   convention — there is no second source for the number.
  > - **It cross-checks `p_row_count` against the DB-side accumulated row count and raises `count_mismatch`
  >   on disagreement**, leaving the job reclaimable. `cells_emitted + cells_suppressed = row_count` is then
  >   an invariant over two independently-derived numbers rather than an identity the worker can satisfy by
  >   arithmetic.
  > - **The worker still supplies `byte_count`, `sha256` and `object_path`** — those are facts about the
  >   *artifact*, which only the worker can observe, and they are **not** evidence that a **database**
  >   predicate ran. `artifact_sha256` stays useful: it proves which bytes were produced and is checkable
  >   against the object if a dispute needs it.
  > - **The blank-column canary, because "zero rows" and "nobody consented" are indistinguishable in the
  >   output.** A `ready` job with `contact_cells_emitted = 0` **and** `contact_cells_suppressed = row_count`
  >   raises a `platform_risk` signal. `INFERENCE:` `cells_emitted + cells_suppressed = row_count` **balances
  >   perfectly at `cells_emitted = 0`**, so the invariant alone detects nothing; only a positive assertion
  >   separates a gate that never emitted from a gate that never ran.
- **`venue.authorize_export_download(p_job_id)`** — **re-checks the caller's authority LIVE against the grant
  tables at this instant**, so an export prepared before a revocation **fails after it** (EX-4). Raises on any
  state but `ready`. Rate-limited. Writes the `crm_export.download` audit row **in-txn, before the URL is
  returned**, and returns `{ object_path, ttl_seconds: 300 }` for the edge to sign. **Locks:** none.

  > **The re-check is over `(scope, template_id)` — NOT over the role set — and that one predicate is the
  > whole finding (`AUTHZ-CRM2`(2); CRM K-15 / H-12).**
  >
  > ```text
  > -- WRONG (what this contract specified — it did not mention template_id at all):
  > --   caller still holds one of {org_owner, org_admin, org_marketing,
  > --                              venue_manager, venue_marketing} over job.scope
  > -- RIGHT:
  >    venue.assert_may_request(auth.uid(), job.scope_kind, job.scope_id, job.template_id)
  >    -- the SAME predicate a fresh request for that (scope, template) would face:
  >    --   audience_v1   → org_owner, org_admin, org_marketing (org grain),
  >    --                   venue_manager, venue_marketing (venue grain)
  >    --   operations_v1 → org_owner, org_admin, venue_manager  ONLY
  > ```
  >
  > **The concrete break.** `org_marketing` holds X10 (read export history), so it can see a colleague's
  > `job_id`; it holds a marketing-class role over the scope, so a **role-set** re-check passes; and it
  > downloads an **`operations_v1`** file — order refs, order totals, **unit prices**, refund state. The
  > stated invariant *"Finance sees money and no contact. Marketing sees contact and no money. Neither sees
  > both."* is then defeated by **any org that ever ran one operations export, without a single grant being
  > wrong.**
  >
  > **Two supporting rules so the fix cannot be undone from the side.** (a) The `◐` on X8/X9 in the CRM
  > matrix is **defined, not decorative**: it means *"jobs whose `template_id` that role may request"* — for
  > both marketing labels, `audience_v1` only — and the same reading applies to **revoke**. (b)
  > **`venue.assert_may_request` is one function, called by both `request_export` and this one**, and
  > assertion 24b is stated as an **equality between the request and download predicates** so the two cannot
  > drift.
- **`venue.revoke_export(p_job_id, p_reason_code)`** — the requester, plus `venue_manager` / org owner-admin
  over the job's scope, plus **`platform_admin`** — the one export-lifecycle write a platform role holds,
  because **revoking is not extraction** — and, per `AUTHZ-CRM2`(2), **template-scoped for both marketing
  labels**. `ready → revoked` **in the same transaction, so no further download is authorized from that
  instant**; sets `artifact_state = 'delete_pending'`; audited; idempotent.
  **It does not delete the object.** The previous contract said it *"signals the edge to delete"*, which
  named no mechanism — **there was no delete route to signal.** The honest bound on revoke is
  **`min(300 s, time-to-purge)`**, not zero.
- **`venue.claim_artifacts_for_purge(p_limit int)`** — **`EXEC: DEF`**; `REVOKE EXECUTE FROM anon,
  authenticated`. Takes the 064 claim lease over a bounded page of jobs in `artifact_state='delete_pending'`
  and returns `(job_id, object_path)` for the purge route. **Returns nothing else — no scope, no counts, no
  actor.** Idempotent under the lease. Locks: the claimed job rows `FOR UPDATE SKIP LOCKED`.
- **`venue.confirm_artifact_purged(p_job_id, p_outcome)`** — **`EXEC: DEF`**. `p_outcome ∈ {deleted,
  not_found}` — **both are success**; a 404 from Storage means the object is gone, which is the goal. Sets
  `artifact_state='deleted'`, advances `ready → expired → purged` where retention allows, writes
  `crm_export.purge`. Idempotent.
- **`venue.reconcile_export_orphans(p_org_id, p_object_paths text[])`** — **`EXEC: DEF`**, daily. Given the
  paths the purge route listed under one `{org_id}/` prefix, returns those with no live job row or whose job
  claims the artifact is already gone (the route deletes those), and marks `artifact_state='deleted'` for job
  rows whose object is absent — **alarming when such a job is still `ready`**, because a `ready` job with no
  bytes fails at download.
  > **Why a definer function cannot do the deleting, stated so nobody re-proposes it.** A `SECURITY DEFINER`
  > Postgres function **cannot call the Storage API**, and its only in-DB option — `DELETE FROM
  > storage.objects` — **drops the metadata row and orphans the bytes**, which is worse than doing nothing:
  > the object survives while every accounting says it is gone. The bytes are deleted by `POST /purge` on the
  > `crm-export` edge function, driven by the `pg_cron` + `pg_net` pattern of migrations 014/032/034. **The
  > reconciliation runs in BOTH directions** — without it the 24-hour retention bound is a statement about
  > **rows**, and rows are not what leaks.
- **`venue.list_export_jobs(p_scope_kind, p_scope_id, p_cursor)`** — scope-checked per X10. **Job metadata
  only — never a row, never an object path, never a signed URL** — **including `template_id` and a
  `downloadable` boolean computed with `authorize_export_download`'s own predicate**, so the panel never
  renders a download control the RPC will refuse. **The list itself stays role-scoped rather than
  template-scoped**: seeing *that* an operations export happened is export-history transparency and is
  deliberate; downloading it is not.
  - **`downloadable := venue.assert_may_request(auth.uid(), job.scope_kind, job.scope_id, job.template_id,
    p_raise := false)`** — §20.7.8. **This is the ONLY caller in the corpus that suppresses the raise**, and
    `T-RPC-CRM-06` asserts that structurally. It is safe here and only here because this function returns
    **job metadata and nothing else**: a `false` renders a disabled control, it never gates a byte.
- **`venue.sweep_expired_exports()`** — **`EXEC: DEF`**, `pg_cron` hourly. **MARKS** artifacts past
  `expires_at` as `artifact_state='delete_pending'` and moves `ready → expired`; `expired → purged` once
  `artifact_state='deleted'` and `purge_after` has passed; one audit row per transition. **It deletes no
  bytes** — the purge route does. The previous contract said *"deletes artifacts"*, which a Postgres function
  cannot do.
- **`venue.list_attendees(p_session_id, p_filters, p_cursor, p_reason_code)`** — the holder-grain roster read
  (dashboard Δ3). Four authority branches (venue/org **operations**, venue/org **marketing**, venue/org
  **finance** for the money-only projection, and platform), **column-scoped by role — and denied classes are
  ABSENT from the result shape, not null.** Filters validated against the same closed grammar. Rate-limited.
  **Audited on every page.** Denied: `venue_box_office`, `venue_scanner`, the door session, `promoter`, both
  promoter-manager labels, `org_member`, `fan`, `anon`. **Locks:** none.
  - **`p_reason_code` is REQUIRED and non-empty when the authority that resolved is the PLATFORM branch, and
    ignored on the venue/org branches** (`AUTHZ-M12`, CRM K-19(4)). A **closed enum** — `support_ticket` ·
    `risk_investigation` · `incident` · `data_subject_request` — plus an optional ticket reference. **Free
    text is not accepted.** Recorded in the audit row with the session id. *A platform read of a venue's
    attendees is an investigation, and an investigation has a reason; the venue/org arms are routine
    operations and do not.*
  - **The platform branch is separately limited and capped**, because it was the only branch with no scope
    object: `attendee_list_page_platform` at **40/hour and 200/24 h per actor**, plus a **20-distinct-session
    cap per 24 h**. Its audit action is **`crm_lookup.platform_roster`, distinct from the venue action**, so
    a platform read never disappears into a venue's page-view volume. `platform_support` is limited to the
    operations projection and holds **no** contact columns. **This is a throttle and a record, not the
    dual-controlled platform extraction path `MD-8` declines to build.**
  - **XO-1a applies here too.** The org resolved during authorization is the operand of
    `kernel.tickets.org_id = :org_id`, of the `customer_ref` HMAC key, and of the consent gate — **resolved
    once, in the same statement that authorized, and used for all three.** A roster read at a re-operated
    venue therefore shows the current operator's own sessions and none of the prior operator's, exactly as
    the export does; **the two surfaces must agree or the export becomes the narrow one and the screen
    becomes the leak.**
- **`venue.lookup_attendee(p_session_id, p_query_kind, p_query_value)`** — **one record**, service context.
  `p_query_kind ∈ {email_exact, order_ref, name_prefix}`. `venue_manager`, `venue_box_office`, org
  owner/admin, `platform_support`; **denied to both marketing labels.**
  - **Rate-limited per actor AND per org, for EVERY `query_kind`** (CRM K-17 / H-14) — not *"hard on
    `email_exact`"*, which is what this contract said and which **left `name_prefix` limited by nothing at
    all**. Limits are looked up by `(action = 'attendee_lookup_by_' || p_query_kind, actor)` and
    `(…, org)`, so **a `query_kind` with no configured limit RAISES rather than passes** — the fail-closed
    posture 021 established for the limiter, applied to the limiter's own configuration.
  - **`name_prefix` additionally:** `length(trim(p_query_value)) >= 3`, else `prefix_too_short`, **raised
    before the lookup and WITHOUT consuming the rate budget** (the call reached no data; charging for it
    makes the limiter a denial-of-service against the box office). **More than one match raises
    `ambiguous_query`, returning no rows and NO COUNT** — not a count, not a truncated list, not the first
    result, not *"3 matches — refine your search"*. **A count is the harvest:** `"sm"` → 14 and `"smi"` → 9
    reconstruct the roster's name distribution without ever returning a record.
    `INFERENCE:` `venue_box_office` holds the lookup, so before this limit an operator could iterate
    `a…z`, `aa…zz` against one session and **reassemble, one record at a time and at no rate cost, the
    printed list the design explicitly refuses to give it.**
  - **Audited with the query KIND and OUTCOME, never the value** — `crm_lookup.attendee` records
    `(actor, session, query_kind, outcome ∈ {hit, no_match, ambiguous, rate_limited, prefix_too_short})`.
    *Logging a probed address would build the harvest list inside our own audit.* **`ambiguous` and
    `rate_limited` are the load-bearing outcomes** — a run of them is the signature of an alphabet sweep and
    the **only** evidence of one, since the probed strings are deliberately never stored.
  - Email is **not** an export filter, **not** a bulk match key, and **not** a suppression key: there is no
    "upload a list and tell me who's coming" surface, in any form.
- **The two structural rules that keep the whole surface honest.** (1) **Platform roles read the roster and do
  NOT use the venue CRM export** — see RLS §11.6 for the full resolution; **platform bulk extraction is not
  built in Phase 2.** (2) **Finance sees money and no contact; marketing sees contact and no money; neither
  sees both.** Only `venue_manager`, `org_owner` and `org_admin` hold the union, which is why the operations
  template's allow-list is the narrowest in the document.
- **Layer-0 note — RESOLVED by owner ruling `OR-1` (RLS `MD-2`/`O17`, 2026-08-28): the builder is
  `postgres`-owned and §0.1's global applies unamended.** The previously recommended narrow owner role
  (`crm_export_builder`) required three things to ship together — (a) a thirteen-grant `SELECT` set over
  the roster/consent relations, (b) a column-scoped `GRANT SELECT (id, email) ON auth.users`, and (c) one
  permissive `<schema>_<table>_sel_svc_export` policy per relation — and its role-without-(c) combination
  read zero rows **silently** (RLS filters rather than raising), shipping a blank contact column that
  reads as *"nobody consented."* Per the ruling, **none of (a)–(c) is built**; the deviation from §0.1 is
  withdrawn and no second definer owner exists. The `X-6` demographic prohibition is enforced instead by
  the structural/catalog assertions and behavioural fixtures of
  `_governance/X6_POSTGRES_OWNED_ASSURANCE_PLAN.md` (catalog-closure, source-scan, consent-matrix and
  canary tests), with the blank-column canary above unchanged. **`BYPASSRLS` remains refused** in any
  future revisiting of a narrow-owner design — it would restore access to everything and delete the
  entire benefit.
- **Tests.** `T-RPC-CRM-03` (a `venue_marketing` at V1 of Org 1 is denied at V2 of the same org;
  `org_marketing` at Org 1 reaches all Org 1 venues and no Org 2 venue) · `T-RPC-CRM-04` (a job exceeding the
  row cap ends `failed` and **writes no artifact — it never truncates**) · `T-RPC-CRM-05` (two builds of the
  same job produce byte-identical output and the same hash) · `T-RPC-CRM-06` (**reader enumeration**: no
  export function's definition matches a demographic relation, **with a non-vacuity guard proving the
  assertion can see all twelve export functions**) · `T-RPC-CRM-07` (no audit row's payload contains an `@`
  in a value position, an `org_customer_key`, or a `customer_ref`) ·
  **`T-RPC-CRM-08`** (`AUTHZ-CRM2`(1): `finalize_export` **has no `p_cells_emitted`/`p_cells_suppressed`
  parameter** — asserted structurally over `pg_proc.proargnames`, because a parameter that is *ignored* is
  a parameter a future refactor re-honours; and a worker `p_row_count` disagreeing with the accumulated count
  raises `count_mismatch` and leaves the job reclaimable) ·
  **`T-RPC-CRM-09`** (`AUTHZ-CRM2`(2): an `org_marketing` holding a valid `job_id` for an **`operations_v1`**
  export over a scope it does hold a marketing role on is **refused at download** — the fixture must use a
  role that *passes* the role-set check, or the test passes against the broken predicate) ·
  **`T-RPC-CRM-10`** (the request predicate and the download predicate are the **same function**, asserted as
  an equality rather than by two independent role lists) ·
  **`T-RPC-CRM-11`** (`AUTHZ-CRM2`(3): a revoked job reaches `artifact_state='deleted'`, and the daily
  reconciliation flags **both** directions — a bucket object with no job row, and a `ready` job with no
  object) ·
  **`T-RPC-CRM-12`** (`p_reason_code` absent on the **platform** branch of `list_attendees` is refused; the
  reason lands in the audit row with the session id; the platform limiter trips **before** the venue limiter
  would have; **the venue branch is unaffected by an absent reason code**) ·
  **`T-RPC-CRM-13`** (a `name_prefix` lookup of 2 characters raises `prefix_too_short` **and consumes no rate
  budget**; a 3-character prefix matching two holders raises `ambiguous_query` **carrying no count**) ·
  **`T-RPC-CRM-14`** (`OR-19` mint: two concurrent FIRST `request_export` calls for one org commit exactly
  ONE `kernel.org_customer_key` row and both jobs' `customer_ref` values agree for the same holder; an org
  with no export job has no key row; no RPC result, audit payload or error text contains `key_material`).

### 17.23 Apple Wallet — `kernel.mint_wallet_pass` + twelve — `NEW RPC` ×13

- **`kernel.mint_wallet_pass(p_atom_id, p_command_key)`** — **EDGE-FRONTED**, `EXEC: authenticated`;
  authorizes `kernel.tickets.current_owner_id = auth.uid()` **in-body, live-read** (C35/I-5). **Preconditions:**
  atom `state='active'`; `resale_state='none'`; `config('wallet.apple.enabled')`. **Locks:** `kernel.tickets`
  PK **`FOR SHARE` (rank 5)** — single lock, no ordering question. **SSCAS: n/a** — **no custody move, no
  ownership-log row, and no `credential_version` bump**, asserted structurally (`T-RPC-WALLET-01`:
  `pg_get_functiondef('kernel.mint_wallet_pass')` references neither `market.*` nor
  `kernel.ticket_ownership_log`). **Idempotency:** `UNIQUE(holder_identity_id, command_idempotency_key)` + a
  state guard — an existing `issued` generation for the same owner returns `noop_replay` **with the same
  serial**. Supersedes any prior `issued` generation and inserts generation *g+1*. Returns build context to
  the **edge**: `serial`, `generation`, `credential_version`, `signing_key_id`, `pass_type_cert_id`, and the
  plaintext auth token **once — never stored in plaintext, never re-returned**. Errors:
  `insufficient_privilege(42501)` · `precondition_failed(atom_not_active | atom_listed_locked |
  wallet_disabled)` · `not_found`. **The kill switch is not role-bypassable** — `platform_admin` also gets
  `wallet_disabled` (`T-RPC-WALLET-02`).
- **`kernel.revoke_wallet_pass(p_wallet_pass_id, p_reason_code, p_command_key)`** —
  `is_platform(['platform_admin','platform_support'])`; the support path for a leaked pass file or a lost
  device. Pass → `revoked`, all its device registrations unregistered, holder prompted to re-add.
  **No credential impact** — the auth token grants only *"fetch/register this one pass"*. Audited in-txn.
- **`kernel.provision_pass_type_cert` · `rotate_pass_type_cert` · `revoke_pass_type_cert`** —
  `is_platform(['platform_admin'])` **only**, dual-controlled, audited. **Rotation is one transaction**: old
  row `active → rotating`, new row `active`, both under the partial `UNIQUE(pass_type_identifier) WHERE
  status='active'`, so **a mid-rotation snapshot never shows zero or two active certificates**.
- **`kernel.supersede_wallet_passes_for_atom(p_atom_id, p_reason_code)`** — **`EXEC: DEF`**. Marks every
  `issued` pass for the atom `superseded`/`invalidated`/`consumed`/`expired` per reason. **Called from the
  OUTBOX CONSUMER, not inside the custody transaction — a Wallet failure must never be able to roll back or
  block a transfer.** Locks: the pass rows only; **it takes no custody lock and therefore imposes no ordering
  obligation on the transfer engine**, which is the whole point of running it outside that transaction.
- **`kernel.touch_wallet_pass` · `get_wallet_pass_build_context` · `register_wallet_pass_device` ·
  `unregister_wallet_pass_device` · `list_updated_wallet_passes` · `record_wallet_push_result` ·
  `sweep_wallet_pass_lifecycle`** — all **`EXEC: DEF`**, `REVOKE EXECUTE FROM anon, authenticated, public`.
  - `get_wallet_pass_build_context(p_serial, p_auth_token)` — **constant-time comparison against
    `auth_token_hash` inside the function** (I-9), and it **returns an identical shape for "not found" and
    "bad token"** so it is not an enumeration oracle. `T-RPC-WALLET-03`: `pg_get_functiondef` contains a
    constant-time comparison and **no bare `=` against `auth_token_hash`**.
  - `register_wallet_pass_device(...)` — constant-time auth; upserts on
    `UNIQUE(wallet_pass_id, device_library_identifier)`; **encrypts the push token**. A wrong token writes
    **no** row.
  - `record_wallet_push_result(...)` — appends the push log, increments the failure count, and **unregisters
    on a permanent APNs rejection**. Idempotent on the outbox dedup key.
  - `sweep_wallet_pass_lifecycle()` — cron; reconciles pass status to atom state. **Explicitly NOT
    load-bearing: every safety property holds whether or not it ever runs.** Stated because *"a correct thing
    that nothing called"* is the exact failure class the door ruling was issued to eliminate.
- **Locks (the twelve non-mint RPCs).** `INFERENCE — AUTHORED, not transcribed:` the source spec supplies no
  lock statement for any of them. **None takes a lock in the six money/custody ranks.** They lock only
  `kernel.wallet_pass` / `wallet_pass_device` / `pass_type_cert` rows, which are **admin-plane objects outside
  the global order**, so no ordering obligation is created and no member's proof changes. `sweep_…` and
  `supersede_…` process rows with `SKIP LOCKED` in bounded batches. **This is the property that lets the
  Wallet feature be added without re-proving §14.2**, and it must be preserved by any future Wallet RPC.
- **Structural guarantee this rests on.** The partial `UNIQUE(ticket_atom_id) WHERE status = 'issued'` gives
  **at most one live pass generation per atom, enforced by the database rather than by the RPC** — the
  structural half of the "no two people admitted on one atom" guarantee.

### 17.24 Notifications — the twenty-three `notify.*` RPCs

**Scope caveat first.** §16.9 of the RLS spec records that `notify`'s gate is **DISPUTED and unresolved**
(C7 says `Gate P · MVP`; four implementation specs say Gate L), and that the notifications spec **explicitly
declines to resolve it**. **The contracts below are conditional** — recorded so nothing is invented under time
pressure if the owner ratifies, and **they are not authority to build.** Owner decision RLS **MD-10**.
> **SUPERSEDED (`OR-5`→`OR-12`, annotated 2026-08-29 per choice 10):** `MD-10` was CLOSED by `OR-5`
> (Gate P REDUCED) and `OR-12` ratified `092` as the reduced package — the sentence above is preserved as
> history; **the reduced 16-RPC surface IS authority to build**, under the `OR-14` two-behavior emit block
> below.

- **Consumer (`EXEC: authenticated`, `auth.uid()`-scoped):** `notify.get_inbox(p_cursor, p_limit ≤ 50)`
  (own rows, newest first, **keyset-paginated** — the current web inbox truncates at 50 with no pagination) ·
  `get_unread_count()` (**fails to `0`, never raises** — it renders in a global header) · `mark_read(p_ids)` ·
  `mark_all_read()` (write `read_at` only) · `dismiss(p_ids)` (writes `dismissed_at`; **never deletes**) ·
  `get_preference_matrix()` · `set_preference(p_type_key, p_channel, p_enabled)` ·
  `register_push_token(...)` (**always sets `user_id = auth.uid()`** and `last_used = now()`, fixing a device
  that changes hands keeping the previous owner's `user_id`) · `revoke_push_token(p_token)` ·
  `report_announcement(p_announcement_id, p_reason)`. **Locks:** none. **SSCAS:** n/a.
- **`notify.channel_enabled(p_identity uuid, p_type_key text, p_channel text) RETURNS boolean`** —
  **`EXEC: DEF`**, and the single resolver. **Order of evaluation is the contract:** registry row absent or
  inactive ⇒ false; channel not in `allowed_channels` ⇒ false; **`delivery_class = 'mandatory'` ⇒ TRUE, and
  RETURN NOW — the preference table is never read**; preference row exists ⇒ its `enabled`; otherwise channel
  ∈ `default_channels`. **Step 3 returns before step 4 is reachable**, so even a preference row that somehow
  existed for a mandatory type could not suppress anything. That is one of two independent guarantees; the
  other is the DDL guard, and `set_preference` raises `mandatory_type_not_configurable` before touching the
  table. **Both layers must hold.**
- **`notify.emit_event(...)`** — **`EXEC: DEF`**, **non-raising**. A producer that cannot emit its envelope
  **`OR-14` (R2, 2026-08-29) — TWO emission behaviors, owner-ratified; every producer explicitly
  classified, no implicit default, no third behavior:**
  - **`notify.emit_event(...)` — BEST-EFFORT, non-raising** (this contract as written): pure notification
    delivery; a failed envelope logs a warning and the producer's money/custody work commits regardless.
  - **`notify.emit_event_required(...)` — REQUIRED, RAISING (§17.24a, authored name):** identical envelope
    semantics, but a failed envelope write RAISES and the producer transaction FAILS. Used ONLY where a
    required system invariant depends on the envelope — the credential/Wallet-critical facts where
    committing without it leaves stale authority live (`#17` ownership_changed, `wallet_pass_available`,
    void/revoke-driven supersession, cert/key rotation). Both are `076` objects (same SEAM-1).
  - The per-producer classification table is NORMATIVE and lives at
    **`_governance/R2_EMITTER_CLASSIFICATION.md`** (adopted 2026-08-29: **6 REQUIRED · 27 BEST-EFFORT ·
    0 unclassified**, cross-checked both directions); a producer without a class is a defect
    (`T-RPC-NOTIFY-09` asserts the closure both ways). **One flag for the owner:** `wallet_pass_available`
    is classified BEST-EFFORT by OR-14's own test (it drives no supersession; REQUIRED would let a notice
    failure block pass issuance) — override only by explicit ruling. Tests: `T-RPC-NOTIFY-04A/-04B/-04C`,
    `-08`, `-09`, `T-EDGE-NOTIFY-01/-02`; `N-A29` split BE/REQ; **`N-A30` re-scoped to best-effort
    producers only** — its universal `EXCEPTION WHEN OTHERS` wrap would swallow the REQUIRED raise, and
    `-08` asserts the six REQUIRED bodies contain no swallow. Delivery remains best-effort for BOTH classes — the class governs
    the ENVELOPE write, never the drain.
  logs a warning and **commits its money/custody work regardless**. **Lock order:** the outbox row is written
  **last within its transaction, after every money/custody row**, and `sequence` is allocated per
  `(aggregate_kind, aggregate_id)` **under the aggregate's existing row lock**, which every SSCAS member
  already holds — so **no new lock and no new deadlock class**. Idempotency: `UNIQUE(event_type, event_key)`.
  **The payload never contains a recipient list and never contains rendered copy** — only ids and scalars.
- **`notify.drain_outbox(p_limit)`** — **`EXEC: DEF`**, cron. **BOUNDED-EXPANSION OBLIGATION (ODR-3
  §3.2, carried 2026-08-29 — binding; the machinery that held it, `notify.schedule.expand_cursor`, left
  with the dropped table):** a custody-expansion envelope (the four event-viability types fan out over
  every active atom) may NOT be drained as one unbounded set-based INSERT. Two admissible mechanisms, the
  choice ENGINEERING (assigned to the `092` author, not ruled here): (i) a cursor pair on `notify.outbox`
  (`ADDITIVE: expand_cursor uuid, expanded_count int`) advancing per tick, envelope `done` only at
  exhaustion; or (ii) internal chunking re-run to completion under `UNIQUE(dedupe_key)` idempotency. Either
  way a 50,000-holder cancellation drains over multiple ticks instead of one long-lock transaction. `pg_try_advisory_xact_lock` + `FOR UPDATE SKIP
  LOCKED LIMIT p_limit`, then **one set-based `INSERT … SELECT … ON CONFLICT (dedupe_key) DO NOTHING`** per
  envelope — no row loop. **Poison quarantine:** a handler that raises marks **that envelope** `dead` and
  continues; **one bad row can never block the batch.**
- **`notify.sweep_scheduled()`** — **`EXEC: DEF`**, cron. Advisory lock with early return; claim a bounded
  batch under a lease; **expand set-wise, one statement, cursor-bounded**, so a 50,000-holder event drains
  over many ticks instead of holding one long transaction and one long lock; `done` only when the cursor is
  exhausted; **on failure the cursor and state are left unadvanced**, so a failure retries the window rather
  than dropping events. **Three guards catch a double run, and only the third is load-bearing:** the advisory
  lock prevents overlap, the lease prevents a crashed run wedging a row, and **`UNIQUE(dedupe_key)` is what
  correctness depends on** — every failure mode collapses to the same no-op.
- **`notify.register_push_token` — extended 2026-08-29 (sprint agent 3, mechanical):** after the insert,
  UPSERT `notify.identity_channel_state (identity_id,'push','ok', now(),'token_registered')` iff a row
  exists in state `unreachable` — a live registration is the fact that ends unreachability (the enum's `ok`
  exists for exactly this; without the reset, `unreachable` is permanent and a re-registered device's
  mandatory pushes stay suppressed, contradicting §3.5's transport-facts-track-transport structure).
- **`notify.enqueue(recipient, type_key, subject_kind, subject_id, params, dedupe_key)`** — **`EXEC: DEF`**,
  non-raising. **Supersedes by extension:** the legacy `public.enqueue_notification` stays unmodified serving
  its existing types; this one derives channels, template and target from the registry.
- **`notify.resolve_web_link(p_target_kind, p_target_id)`** — **`EXEC: DEF`**. Composes a web path from a
  **closed set**. `notify.notification` stores `target_kind` (closed enum) + `target_id`, and **never a
  URL** — the existing producers build links by string-concatenating a uuid, which is safe only because the
  input is a uuid, and **that pattern must not be extended.**
- **Staff announcements (`EXEC: authenticated`, role-gated):** `draft_announcement` (venue/org manager, org
  owner/admin, **and marketing**) · `preview_announcement_audience` (**returns a COUNT only, never an
  enumeration** — there is no parameter through which an audience can be widened, which denies an
  audience-harvesting primitive) · `approve_announcement` / `cancel_announcement` / `revoke_announcement`
  (`venue_manager`, `org_owner`, `org_admin` — **never marketing**; drafting and releasing are distinct acts).
  **Above a blast-radius threshold, release requires a second distinct approve-authorized principal, so a
  single compromised credential cannot blast a stadium.** A **mandatory hold window** precedes send, during
  which cancel means nothing leaves the database. **After the hold, revocation is partial and the UI must say
  which part:** in-app entries are replaced, pending deliveries are `suppressed`, and **push notifications
  already delivered cannot be removed — they stay on the device forever.** The remedy after delivery is a
  correction announcement, which is **the only cap exemption in the design**. Per-subject caps are counted
  **over rows, not over `check_rate_limit`** — the limiter is keyed `(user_id, action)`, so two managers at
  one venue would each get a full quota and together double the blast; **the cap must live on the subject**,
  and the limiter is the second layer, not the first.
- **Recipient derivation — four sanctioned forms, and nothing else.** Row-column (a uuid on the causing row) ·
  custody expansion (`current_owner FROM kernel.tickets WHERE event_session_id = $1 AND state='active'`,
  **evaluated at expansion time, never at schedule time**, so a ticket transferred away notifies the *new*
  holder) · scope-role **union** (always an explicit array union, **never inheritance**; an unresolvable scope
  yields the **empty set** plus an error, **never a broadcast**) · self. **Illegal:** a recipient list as an
  RPC parameter, a recipient list inside an outbox payload, or any `SELECT` over `auth.users` outside those
  four forms. `T-RPC-NOTIFY-01` asserts it structurally over `pg_proc` and `pg_get_functiondef`.

### 17.25 `notify.claim_deliveries` and `notify.record_delivery_result` — contracts **AUTHORED, not transcribed**

These two are named as `NEW RPC` in the notifications spec **with no contract body anywhere in its 1,566
lines** — no signature, no parameters, no return type, no precondition, no lock statement, no error set, no
idempotency clause, no SSCAS statement. Everything below is **`INFERENCE`**, derived from the delivery-row
state machine, the lease predicate, the retry schedule and the dispatcher description the spec *does* supply.
**Flagged in §19 for review as authored material.**

**`notify.claim_deliveries(p_channel text, p_limit int) RETURNS SETOF delivery_claim`** — **`EXEC: DEF`**

- **Purpose.** Atomically lease a bounded batch of due deliveries to one dispatcher, so two dispatchers can
  never work the same row.
- **Actor.** `service_role` only; invoked by the `notify-dispatch` edge function on its cron tick.
- **Params.** `p_channel ∈ {push, email}`; `p_limit` bounded server-side (**`INFERENCE:` default 200,
  hard-capped; the "100" in the source is an Expo *request chunk* in the edge function, not a claim size —
  conflating the two would couple the DB batch to a third party's request limit**).
- **Preconditions.** `state='pending' AND next_attempt_at <= now() AND (claimed_until IS NULL OR claimed_until
  < now())`.
- **The claim itself is the lock:** a single `UPDATE … SET state='claimed', claimed_until = now() +
  config('notify.delivery_lease_interval'), attempt = attempt + 1 … WHERE <predicate> … RETURNING`, ordered by
  `next_attempt_at`, with `SKIP LOCKED`. **No separate `SELECT … FOR UPDATE`** — the update *is* the
  serialization point, which is the same claim-lease shape the webhook path already proves.
- **Locks & order.** `notify.delivery` rows only. **The `notify` plane sits outside the six money/custody
  ranks**, and this function touches nothing inside them, so **it creates no ordering obligation and no
  member's lock-order proof changes.** `SKIP LOCKED` makes it safe to run multiple dispatchers without
  redesign.
- **SSCAS.** n/a — single aggregate class, no money, no custody.
- **Idempotency.** The lease. A crashed dispatcher's rows become re-claimable when `claimed_until` passes;
  `UNIQUE(notification_id, channel)` upstream guarantees a re-fan-out creates **no second delivery row**.
- **Returns.** Per row: `delivery_id, notification_id, channel, attempt, recipient_id, type_key,
  template_key, params, locale_resolved` — **enough to render, and no more**.
- **Errors.** None expected; a limiter or config failure raises and the tick is retried.
- **The honest limit, which no lease can close.** A dispatcher that dies in the ~200 ms window between the
  provider returning 200 and the `sent_at` write **will re-post after the lease expires**, and the user gets
  two banners for one row. Narrowing that window is the lease's job; **closing it would require exactly-once
  semantics against a third party that does not offer them.** For MANDATORY money types the design
  **deliberately prefers a rare duplicate banner to a rare missing one**, and the support-visible consequence
  is bounded because both banners open **the same single notification row** — the app never shows two refunds.

**`notify.record_delivery_result(p_delivery_id, p_outcome, p_provider_message_id, p_provider_receipt_id,
p_apns_status, p_error text)` — `EXEC: DEF`**

> **`device_not_registered` arm — EXTENDED 2026-08-29 (sprint agent 3; every joint forced by §3.2/§3.5's
> own text):** ⇒ `state='failed'` **and** `public.push_tokens.revoked_at = now()`,
> `revoked_reason='device_not_registered'`; **then, iff no row remains for the recipient identity with
> `revoked_at IS NULL`**, UPSERT `notify.identity_channel_state (identity_id, channel='push',
> state='unreachable', since=now(), reason='device_not_registered')` — the only outcome that is an
> identity-level transport fact, the only value the closed enum admits for push, and the §3.5 all-tokens-
> revoked condition verbatim. Lock order delivery → token → channel-state. **A transport fact, never
> `notify.preference`** — it suppresses nothing by itself; `channel_enabled` unchanged. The EMAIL arm
> (`bounced_hard`/`complained` transitioning a `sent` delivery) is **CONDITIONAL(N1)** — signature
> reserved, body not authored: no provider exists and the current terminal-state guard forbids it.

- **Purpose.** The single terminal-state writer for a delivery, and the only place a push token is ever
  marked inactive.
- **Actor.** `service_role` only; called by `notify-dispatch` after the provider call and by
  `notify-receipts` on the receipt poll.
- **Outcome mapping (the contract):** `sent` ⇒ `state='sent'`, stamp `sent_at`, persist
  `provider_message_id`/`provider_receipt_id`, clear the lease. **Persisting the ticket id is required** — the
  current path echoes the provider response into a 200 and discards it, which is why no receipt loop is
  possible today. `transient` ⇒ back to `state='pending'` with `next_attempt_at` per the backoff schedule
  (+1 m, +5 m, +25 m, +2 h, +12 h; **five attempts, then `dead`**), honouring a provider `Retry-After` by
  **setting `next_attempt_at`, never by spinning**. `device_not_registered` ⇒ `state='failed'` **and**
  `public.push_tokens.revoked_at = now()`, `revoked_reason='device_not_registered'` — **the first code path in
  the system's history that ever marks a token inactive.** `permanent` (message too big, invalid credentials)
  ⇒ `state='dead'` + `last_error`, and **`captureException` on a MANDATORY type** (the notification path has
  no error reporting at all today). `no_transport` ⇒ `state='suppressed'` with the reason; if no transport at
  all is available for a mandatory type, record `undelivered_mandatory`.
- **Locks & order.** The `notify.delivery` row, then optionally the `public.push_tokens` row. **Both outside
  the money/custody ranks; no ordering obligation.** `INFERENCE:` acquire delivery-then-token consistently, so
  a receipt batch touching many tokens cannot deadlock against a dispatcher.
- **SSCAS.** n/a. **Idempotency.** Terminal-state guarded: a second call on an already-`sent`/`dead` row is a
  **no-op returning the existing state**, never a second token revocation.
- **Dead-letter.** `state='dead'` with `last_error`. **There is no separate DLQ table — the delivery row IS
  the dead letter**, which keeps the failure attached to the notification a support agent is already looking
  at.
- **Returns.** `{ status, delivery_id, state }`.

### 17.26 `venue.read_operational_audit(p_scope_kind, p_scope_id, p_filters, p_cursor)` — **DB-RPC (read)** · `NEW RPC`

- **Role.** `has_org_role([org_owner, org_admin, org_finance])` OR
  `has_venue_role([venue_manager, venue_finance])`, **restricted to the caller's own org/venue subject**.
- **Returns plain verbs with no `before`/`after` payloads, and EXCLUDES the security plane entirely** —
  role grants, platform actions, key operations and money-denial rows are never visible here. Platform reads
  the security plane through the existing `is_platform` path.
- **Locks:** none. **SSCAS:** n/a. Every call is itself audited.

---

## 18. Consolidated test register

Every `T-RPC-*` id named above, plus the ones that belong to no single contract. Two source specs supply **no
named test for any of their 23 RPCs**; those rows are authored here (§19).

| Group | Ids | What they defend |
|---|---|---|
| **Door — admission** | `T-RPC-DOOR-01` (structural: `mark_ticket_scanned` does not reference `is_transfer_frozen`) · `T-RPC-DOOR-02` (admit succeeds with the freeze engaged) · `T-RPC-DOOR-03` (second scan ⇒ `duplicate`, atom stays `scanned`) · `T-RPC-DOOR-04` (`status='completed'` ⇒ `precondition_failed` — admission is gated by session status, not manifest state) | **§7.5 — the CRITICAL defect. `T-RPC-DOOR-01` is what stops it recurring** |
| **Door — freeze set** | `T-RPC-DOOR-05` (`transfer_ticket_ownership` and `accept_p2p_transfer` ⇒ `frozen`) · `T-RPC-DOOR-06` (routine void ⇒ `frozen`; `cancel_event` succeeds) · `T-RPC-DOOR-07` (compensate succeeds, complete refused) · `T-RPC-DOOR-08` (`effective_freeze_at` NOT NULL over every status × nullability combination) | §12.4 |
| **Door — lifecycle** | `T-RPC-DOOR-09` (drained atom scans) · `T-RPC-DOOR-10` (denied principals ⇒ `42501`, `door_open_at` unchanged) · `T-RPC-DOOR-11` (re-open leaves `door_open_at` byte-identical) · `T-RPC-DOOR-12` (a `paid_pending_transfer` listing is not drained) · `T-RPC-DOOR-13` (override expires with no sweep having run) · `T-RPC-DOOR-14` (direct writes to `door_open_at` raise) · `T-RPC-DOOR-15` / `T-RPC-DOOR-16` (delta log) | §17.10–§17.13 |
| **Money** | `T-RPC-MONEY-01..14` **+ `-21..-24` (`MB-1`, the cumulative operand — appended rather than inserted, so `-15..-20` in §18.1 keep their numbers)** | §17.1–§17.7, §17.1a |
| **Approval integrity** | `T-RPC-AUTHZ-15` (the set of functions inserting `kernel.approval_request` is **exactly** three — the enumeration the accepted no-FK residual rests on) · `T-RPC-AUTHZ-16` (a vanished `subject_id` resolves to **`stale`** on approval, holds released, no money row, on all three `subject_kind` values) | **§17.0a** `APPR-SUBJ-1/2` |
| **Role model** | `T-RPC-ROLE-01` (`has_venue_role` does not reference `door_pin`) · `-02` (no re-inlined inheritance join) · `-03` (`is_org_affiliate` never a sole gate) · `-04` (no grant RPC accepts a promoter artifact) · `-05` (`assert_door_session` in no `pg_policy`) · **`T-RPC-AUTHZ-17`** (the helper set is **exactly** the ten of §1.1–§1.1e, by name — see RLS `T-RLS-ROLE-06`) | §1.1–§1.1e |
| **Attribution** | `T-RPC-ATTR-01..04` | §6.1, §17.14 |
| **Promoter** | `T-RPC-PROMO-01..11` | §17.15–§17.19 |
| **Demographics** | `T-RPC-DEMO-01` (exactly two writer functions) · `T-RPC-DEMO-02` (`get_holder_mix` arity is 2) · **`T-RPC-DEMO-03`** (`AUTHZ-DEM1`(1): `set_my_demographics` and `clear_my_demographics` write **zero** rows to `kernel.admin_audit` — asserted over the audit table, not over the function text) · **`T-RPC-DEMO-04`** (`AUTHZ-DEM1`(2): the suppressed branch returns `{suppressed:true}` and **no other key** — asserted over the result's key set, because a NULL denominator is still a denominator) · **`T-RPC-DEMO-05`** (the read-side re-derivation fails closed on a hand-written sub-floor row) | §17.20 |
| **CRM** | `T-RPC-CRM-01..13` | §17.21–§17.22 |
| **Wallet** | `T-RPC-WALLET-01..03` | §17.23 |
| **Notify** *(conditional on MD-10)* | `T-RPC-NOTIFY-01` (recipient derivation) · `T-RPC-NOTIFY-02` (a mandatory type cannot be suppressed, asserted as `service_role` **and** as `postgres`) · `T-RPC-NOTIFY-03` (a claimed delivery inside its lease is not re-claimable) · `T-RPC-NOTIFY-04` (`emit_event`/`enqueue` never raise: an injected constraint violation leaves the caller's transaction committed) | §17.24–§17.25 | **RETIRED `OR-14` (2026-08-29): replaced by `T-RPC-NOTIFY-04A/-04B/-04C`, `-08`, `-09` (`_governance/R2_EMITTER_CLASSIFICATION.md`) — the universal never-raise claim is false for the six REQUIRED producers.**
| **Money (S-24 additions, 2026-08-29 — red-team P2-10: these four existed only at §20.7.7 and were absent from this register and the matrix)** | `T-RPC-MONEY-25` · `-26` · `-27` · `-28` — the refund state-machine set (label reachability incl. the pre-fix failure; forward-only both directions; second-different-`stripe_refund_ref` raises / equal is `noop_replay`; `refund_exposure_minor` boundary) |
| **Order/market state-sync (authored 2026-08-29)** | `T-RPC-ORG-04..06` (§20.1.6/§20.1.7) · `T-RPC-ORDER-01..04` (§20.7.9) · `T-RPC-MARKET-08..10` (§20.8.7) |
| **Global posture** | `T-RPC-GLOBAL-01` (every function `postgres`-owned, `SECURITY DEFINER`, pinned `search_path`) · `T-RPC-GLOBAL-02` (every `EXEC: DEF` function has no grant to `anon`/`authenticated`) · `T-RPC-GLOBAL-03` (**no RPC accepts a client-supplied actor/`buyer_id`/`user_id` as authority** — signature inspection over `pg_proc`) · `T-RPC-GLOBAL-04` (every human-authorized RPC **raises** when `auth.uid()` is NULL, so a service-role invocation fails loudly rather than degrading — **the enforceable form of §0.1a**) | §0.1, §0.1a |

**Ids, not rows (`G-22`).** The thirteen group rows above enumerate **83 distinct ids**
(4+4+8+14+2+5+4+11+5+13+3+4+4) — the demographics group grew from 2 to 5 (`AUTHZ-DEM1`), CRM from 7 to 13
(`AUTHZ-CRM2`), and the approval-integrity group is new (`APPR-SUBJ-1/2`). A CI plan provisioned from the row count under-provisions by 58. Every suffix
above is written as a full id (`G-23`), so a harness grepping for `T-RPC-` finds all of them.

#### 18.1 §20 additions — the set-closure register

Every id below is named at its contract in §20. **73 ids across 16 groups**, bringing the document's total to
**156** (83 in §18 + 73 here). The seven added by this reconciliation pass are `T-RPC-STAFF-05/-06`
(`AUTHZ-H3` RV-2), `T-RPC-DOOR-25` through `-32` minus the two already listed (the online key-id binding, the
mint/revoke set and the two live counts), `T-RPC-KEY-05` (the signing-key force-close) and
`T-RPC-MARKET-07` (offer expiry as arithmetic).

| Group | Ids | What they defend |
|---|---|---|
| **Set closure** | `T-RPC-SET-01` (**the reconciliation itself**: `pg_proc` minus trigger functions equals RLS §11 ∪ this document, in both directions, with a non-vacuity guard) · `T-RPC-SET-02` (exactly one physical function per row of §20.13's naming register) | §20.0, §20.13 |
| **Connect onboarding** | `T-RPC-CONNECT-01` (bind stamps `payout_destination_set_by`) · `-02` (**the bypass regression** — an `org_finance` re-point raises `destination_already_set`) · `-03` (same id/same org ⇒ `noop_replay`; different org ⇒ `conflict_locked`) · `-04` (service-role invocation raises) | §20.1.1 |
| **Organization & identity** | `T-RPC-ORG-01` (self-approval raises; `closed` is terminal; suspension cascades to nothing) · `-02` (self-branch signature has no uuid parameter; `kyc_ref` audit carries no value) · `-03` (**structural** — `update_organization` references no money or status column) | §20.1.2, §20.1.3, §20.1.5 |
| **Role model (platform)** | `T-RPC-ROLE-06` (one approver inserts no `platform_role` row) · `-07` (self-approval ⇒ `sod_violation`) · `-08` (last-`platform_admin` revoke raises, counting `public.admin_users`) · `-09` (an `org_*`/`venue_*` label as `p_role` raises) | §20.1.4 |
| **Config** | `T-RPC-CFG-01` (raise parks, lower executes) · `-02` (a `jsonb` value on a money key parks in either apparent direction) · `-03` (unknown key raises) · `-04` (**zero UPDATE and zero DELETE paths on `platform_config`**, as `postgres` and as `service_role`) · `-05` (a live listing's governing resale policy survives a later tightening) | §20.2.1, §20.2.2 |
| **Catalog update** | `T-RPC-CAT-01` (`venue_id`/`org_id`/`status` in a patch raise; a title change on `on_sale` without a reason raises; a `cancelled` event refuses every patch) · `-02` (`door_open_at` in a patch raises; a later `doors_at` past the grace raises; any move after the boundary engages raises) | §20.2.3, §20.2.4 |
| **Inventory** | `T-RPC-INV-01` (a price change leaves an existing order's snapshot, refund ceiling and settlement line byte-identical) · `-02` (a shrink below `held+sold` raises **for every role including `platform_admin`**) · `-03` (sharded grow preserves `Σ shard = batch` and the movement ledger) · `-04` (**the `G-24` regression** — with the sweep disabled `remaining` is provably wrong; with it enabled the hold's capacity returns) · `-05` (a hold converting in-window is skipped, not released) · `-06` (a re-run releases nothing further) | §20.3 |
| **Staff & devices** | `T-RPC-STAFF-01` (self-grant, superseded labels and cross-scope labels all raise; org inheritance goes **through the §1.1a helper**) · `-02` (a revoked scanner's next `record_scan` raises **on the same JWT**) · `-03` (a registered device with no live session is refused by `assert_door_session` and therefore by every door RPC) · `-04` (cross-venue sync raises; an out-of-order poll cannot lower stored sync state) · **`-05`** (a retired device's next door call raises **and** it holds no `active` `door_session` row — **both halves**, since the first passes even if RV-2 was never built) · **`-06`** (a door session calling `set_scan_device_status` raises; un-retire does not resurrect a revoked session) | §20.4 |
| **Comps** | `T-RPC-COMP-01` (**the R-15/E6/E7 split** — `venue_box_office` refused on allocate, permitted on issue) · `-02` (above the C39 threshold a stale-`amr` token raises and moves no counter) · `-03` (a comp atom scans, transfers and refunds identically to a purchased atom; a replayed issue mints no second atom) | §20.5.1, §20.5.2 |
| **Guest list** | `T-RPC-GUEST-01` (a checked-in entry cannot be removed or edited; the removal audit carries the removed row; **no client role holds table DELETE**) · `-02` (**structural** — `check_in_guest_entry` writes no `guest_entry` column outside `status`/`checked_in_at`) | §20.5.3–§20.5.6 |
| **Door — set closure** | `T-RPC-DOOR-17` (**the manifest result carries no identity column**, by column-list comparison) · `-18` (box office and a foreign door session refused; delta-only poll returns the same digest) · `-19` (**structural** — `sweep_implicit_door_freezes` references neither `engage_door_freeze` nor `door_open_at`) · `-20` (the implicit freeze engages **with no sweep having run**) · `-21` (preview counts reconcile to the open's drained counts; `paid_pending_transfer` in neither) · `-22` (**the live-device predicate equals the override guard's expression**) · `-23` (**structural** — `set_session_door_schedule` never references `door_open_at`) · `-24` (a loosening security override raises for every role; a Wallet-span violation raises — **held while §20.6.6 is `⛔ BLOCKED`**) · **`-25`** (an atom pinned to a **revoked** key is refused **online and offline**, asserted on both paths) · **`-26`/`-27`** (mint: a PIN for S1 cannot mint a session bound to S2 and a foreign-venue device cannot mint, both with the same error and timing as a wrong PIN; a re-mint leaves exactly one `active` row and the superseded token is refused) · **`-28`** (a `venue_scanner` and a door session are both refused `revoke_door_session`) · **`-29`** (a revoked PIN or a retired device drops out of `live_sessions` in the same transaction, while `live_devices` may still count its un-lapsed manifest — **asserted as a difference**) · **`-30`/`-31`/`-32`** (the `AUTHZ-H3` regression trio, §1.1d) · **`-33`/`-34`** (**`MP-1` — structural:** every field the `OFFLINE-VERIFY-v1` predicate reads appears in `get_door_manifest`'s entry projection **and** in its `op='add'` delta projection, by column-list comparison; with `-34` deriving the compared read set **from the fenced block** so `-33` cannot pass against a stale hard-coded list) · **`-35`** (**`MB-6` — structural:** `venue.reconcile_offline_scans`'s body references `kernel.tickets` **nowhere**, so the offline admit is provably routed through `kernel.mark_ticket_scanned` and is inside the `prosrc` assertion that pins the must-not-recheck-the-freeze property; a value-based test cannot distinguish the two implementations) | §20.6, §9.1–§9.8 |
| **Money — set closure** | `T-RPC-MONEY-15` (**an `admin_refund` void on an open episode appends one `revoke` delta per atom** — the §12.4c exemption obligation) · `-16` (a resold atom's primary payment refunds money only, returning `custody_moved`) · `-17` (`platform_support` and `org_owner` both refused) · `-18` (`pay_promoter_commission`'s write set pinned; no external call) · `-19` (**a flagged unreviewed attribution yields NO settlement line**, and `release` + close pays it) · `-20` (the same attribution cannot be lined into a second settlement) | §20.7.1, §20.7.2 |
| **Credential keys (C33)** | `T-RPC-KEY-01` (**no parameter and no written column accepts key material**) · `-02` (**structural** — `rotate_signing_key` references neither the ownership log nor `kernel.tickets`) · `-03` (exactly one `active` key per scope at every observable instant during a rotation; a pre-rotation atom still verifies) · `-04` (revoking the only active key raises; a wrong acknowledgement count raises; the revoked row and its `public_key` survive) · **`-05`** (with two `open` episodes in the key's scope and one outside it, an approved revoke closes **exactly the two**, in the same transaction as the key row — asserted **on the episode rows**, not on the absence of admissions, which would pass on a manifest that merely lapsed) | §20.7.3–§20.7.5 |
| **Native marketplace** | `T-RPC-MARKET-01` (non-owner, issuing `venue_manager` and `platform_admin` all refused a listing; double-list raises; frozen session raises) · `-02` (cancel withdraws pending offers and cancels the auction; `paid_pending_transfer` raises on the direct path **and** is excluded from the drain) · `-03` (**two concurrent equal bids: exactly one clears**, under real concurrency) · `-04` (anti-snipe extends `ends_at`; a seller's own bid raises `self_bid`) · `-05` (**accept with another identity's payment raises `payment_unverified` and moves no custody** — the C35 regression) · `-06` (accept withdraws every other pending offer, marks the listing `sold`, and a replay appends no second ownership-log row) · **`-07`** (an offer past `expires_at` whose stored `status` is still `pending` — **the sweep suppressed** — is refused and writes no `market_sale`) · **`-11`…`-18`** (the R-37 buy-now set: one-winner reservation under real concurrency; `self_purchase`; seller-unbreakable reservation; mark→finalize completion + replay; frozen finalize → C25 compensate; cancel three-arm forward-only; mark-vs-cancel determinism; the lapse worker's PI-death protocol both arms) | §20.8 |
| **Promoter — records** | `T-RPC-PROMO-12` (**structural** — `create_promoter` writes none of the three authz tables) · `-13` (a terms change leaves every existing attribution's `terms_version` and the commission it pays byte-identical) · `-14` (slug check refused to a fan and to a foreign org; result payload is `{available}` and nothing else) | §20.9 |
| **Dashboard** | `T-RPC-DASH-01` (for every tile × role, the summary equals the owning read's value **or the key is absent** — never null, never a computed second answer) | §20.10 |
| **Seams** | `T-RPC-SEAM-01` (`settlement_royalty_lines` returns rows after `088` — the stub was **replaced**, not merely present) · `-02` (`settlement_commission_lines` returns a row after `090`) · `-03` (`on_atom_voided` flips a seeded sale to `compensated`, a `completed` sale raises, **and the call sits before the rank-5 atom lock**) | §20.11 |

#### 18.2 `T-RPC-AUTHZ-*` — the authority-defect remediation register

**A separate id namespace on purpose.** These **sixteen** assertions defend properties that were **stated in
prose and enforced nowhere**, across five sections of this document and three of the RLS spec. Filing them
under `MONEY`/`PROMO`/`COMP`/`STAFF` would scatter them into groups whose other members test *behaviour*;
these test *whether the control exists at all*, and a reviewer should be able to run the set and get an answer
to that one question. **16 ids** — `-15`/`-16` are `APPR-SUBJ-1/2` (§17.0a), listed in §18's approval-integrity
row and repeated here so the namespace stays contiguous.

| Id | Assertion | Defect |
|---|---|---|
| `T-RPC-AUTHZ-01` | **No authority branch in any of the three approval-dispatched functions reads `payload`** — structural, over `pg_get_functiondef` | `AUTHZ-C1A` |
| `T-RPC-AUTHZ-02` | A request parked at `required_approver_class='org'` whose atom becomes `scanned` while parked ⇒ **`stale`** on approval, holds released, **no refund**, and the org approver can never complete it | `AUTHZ-C1A` |
| `T-RPC-AUTHZ-03` | On `action='config.set_money_key'`: `platform_support` refused, `platform_risk` refused, **the requesting `platform_admin` refused**, a second distinct `platform_admin` succeeds | `AUTHZ-C1A2` |
| `T-RPC-AUTHZ-04` | With `refund.platform_support_max_minor` **deleted**, `platform_support` approves nothing at any amount; `platform_risk` on the same row succeeds | `AUTHZ-M3` |
| `T-RPC-AUTHZ-05` | An `org_owner` who mints a second `org_finance` **through the real `invite_org_member` / `accept_org_invite` path** cannot approve their own refund request while the grant is immature. **The fixture must perform the mint — the mint is the attack** | `AUTHZ-C1B` |
| `T-RPC-AUTHZ-06` | A token carrying **no `amr` claim** raises **`step_up_unavailable`**, asserted **distinctly** from `step_up_required` and from `42501`, at all five step-up sites — three distinguishable outcomes, because a test asserting only "it failed" passes on either broken spelling | `AUTHZ-M4` |
| `T-RPC-AUTHZ-07` | A second `org_owner` minted through the real invite/accept path is refused **both** `set_org_payout_destination` and `request_org_payout` while immature — SoD-1 covered on **both** sides | `AUTHZ-C1B` |
| `T-RPC-AUTHZ-08` | Both promoter-manager labels are refused `review_attribution_flag` and write **no** `venue.attribution_review` row at any `seq` — asserted **after** a `venue_manager` has written `seq=1`, because appending over an existing decision is the attack | `AUTHZ-H10` |
| `T-RPC-AUTHZ-09` | Exactly **one** function in `pg_proc` writes `venue.attribution_review` | `AUTHZ-H10` |
| `T-RPC-AUTHZ-10` | No function body contains `promoter_id = auth.uid()` — structural, because the defect reads as correct | `AUTHZ-M10` |
| `T-RPC-AUTHZ-11` | A promoter with an active code scoped to the event and **no link at all** satisfies `is_promoter_for_event` and sees their own attributions | `AUTHZ-M10` |
| `T-RPC-AUTHZ-12` | With `comp.per_staff_step_up_max_units` **deleted from `catalog.platform_config`** — the state a missed seed produces, not set to `0` — `allocate_comp` and `issue_comp` at `quantity = 1` both raise on a stale-`amr` token and move no counter | `AUTHZ-M8` |
| `T-RPC-AUTHZ-13` | The comp count is **per actor**: actor A at the threshold does not step-up actor B's first comp at the same venue and session | `AUTHZ-M8` |
| `T-RPC-AUTHZ-14` | A `venue_manager` granting `venue_manager` raises `tier_guard`; **the same caller granting each of the other five succeeds** (so the test proves a narrowing, not a lockout); an `org_admin` of the venue's org grants `venue_manager` successfully | `AUTHZ-M7` |
| `T-RPC-AUTHZ-15` | The set of functions inserting `kernel.approval_request` is **exactly** `{request_order_refund, request_org_payout, set_platform_config}` — structural. **The accepted no-FK residual rests on this enumeration**; a fourth writer turns `APPR-SUBJ-1` back into a convention | `APPR-SUBJ-1` |
| `T-RPC-AUTHZ-16` | A parked request whose `subject_id` is deleted resolves to **`stale`** on approval — not `denied`, not `approved` — releases every hold and writes no money row. **Asserted on all three `subject_kind` values**, because one branch passing says nothing about the other two | `APPR-SUBJ-2` |
| `T-RPC-AUTHZ-17` | The `kernel` predicate-helper set in `pg_proc` is **exactly** the ten names enumerated in RLS §2.2 — asserted as a **set equality against a literal list**, in both directions, never as a count. A count assertion passes on the wrong set of the right size, which is precisely how `money_role_grant_matured` was invoked by four call sites and defined by none | **`AUTHZ-C1C`** / `HELPER-DERIVED` |
| `T-RPC-AUTHZ-18` | With `authn.money_role_maturity_hours` **deleted from `catalog.platform_config`** — the state a missed seed produces, **not** set to `0` — `kernel.money_role_grant_matured` returns **`false`** for an `org_owner` whose grant is a year old, and **does not raise**. Asserted **on the helper directly**: `T-RLS-MONEY-07` exercises it only through the callers and would pass on a helper that raised | **`AUTHZ-C1C`** (fail-to-safe, X-12) |
| `T-RPC-AUTHZ-19` | The set of functions whose body calls `kernel.money_role_grant_matured` is **exactly** `{request_order_refund, approve_refund_request, request_org_payout, set_org_payout_destination}` — structural, over `pg_get_functiondef`. **Both directions fail**: a fifth caller is an over-application (a deny, cancel or sweep path that a control must never block), and a missing fourth is the half-pair defect C58 names, since a fresh account simply moves to the unbound side | **`AUTHZ-C1C`** / C58 |
| `T-RPC-AUTHZ-20` | `kernel.request_org_payout` with `p_org_id` = an org where the caller holds a **mature** `org_finance` grant and `p_settlement_id` = a settlement of a **different** org raises **`not_found`** and moves no money — the authority predicates all pass, which is the point. **The fixture must give the caller a genuinely valid grant at `p_org_id`**, or the test passes on the role check and never reaches the binding | **`AUTHZ-C1C`** (scope binding) |

> **Four of these fourteen assert a FAIL-TO-SAFE default** (`-04`, `-06`, `-12`, and RLS's
> `T-RLS-MONEY-07`), and every one of them is written to **delete the config row rather than set it to zero**.
> That distinction is the entire test: a missing seed row and a seeded `0` produce identical behaviour only if
> the `COALESCE` is actually there, and a fixture that sets `0` passes whether or not it is.

---

## 19. What is AUTHORED here rather than transcribed — read this before implementing

The eight delta specs are not uniformly complete, and pretending otherwise would hand an implementer inferred
material as if it were ratified. Everything in this list is **`INFERENCE`**, marked so it can be reviewed as a
design decision rather than absorbed as a citation.

1. **`notify.claim_deliveries` and `notify.record_delivery_result` (§17.25) are wholly authored.** Their
   source names them as `NEW RPC` and supplies **no contract body at all**. The claim predicate, the lease
   semantics, the batch bound, the outcome mapping, the return shapes and the idempotency rule are derived
   from the delivery-row state machine and the retry schedule the spec does give.
2. **Locks and lock order for 22 RPCs.** The Wallet spec supplies a lock statement for exactly one of its
   thirteen; the CRM spec supplies none for its fourteen; the demographics spec supplies none for its six.
   §17.20, §17.21, §17.22 and §17.23 state one for each — mostly *"none, and here is why that is safe"*, which
   is a claim about the design, not an absence of information.
3. **Result shapes** for `set_my_contact_prefs`, `grant_org_contact_consent`, `list_attendees`,
   `lookup_attendee`, `build_export_rows`, `finalize_export`, `revoke_export` and `list_export_jobs` — the CRM
   spec describes behaviour and idempotency but no return shape for these.
4. **`venue.reconcile_holder_mix()` is named here.** Its source classifies it as a `NEW RPC` but never gives
   it a name, and its own assertion list says "all five RPCs" while listing six.
5. **The `notify` matrices and contracts are CONDITIONAL** on owner decision MD-10 (§17.24). They are not
   authority to build.
6. **`p_limit` for `claim_deliveries`** is a DB batch bound, deliberately **not** the provider request chunk
   the source mentions; conflating them would couple the database batch to a third party's request limit.
7. **Test ids.** Every `T-RPC-*` id is authored. The money and role specs name **no test at all** for their 23
   RPCs; the door, promoter, CRM, demographics and Wallet specs each carry their own assertion lists, which
   §18 references by property rather than renumbering.

**§20 additions to this list.** §20 closes a set difference, so most of its material is **transcribed
authority** — the RLS §11 EXEC row is quoted at each contract. The following are **not**, and are marked at
their site as well as here.

8. **Authority PROPOSED where RLS §11 is silent** — §20.1.1 `set_org_connect_ref` (adopting edge §9 recon
   #12's proposal rather than inventing a third), §20.1.5 `update_organization`, §20.2.3/§20.2.4 the catalog
   update pair, §20.3.2 `set_batch_capacity`, §20.3.3 the hold sweep, §20.6.3/§20.6.4 the two door reads,
   §20.9.1–§20.9.5 the promoter records and links, §20.10 `get_dashboard_summary`, §20.11.1–§20.11.3 the
   three seams. **A proposal in a contract document is not authority**; §20.14 R-3 files each for the RLS
   owner. Where the proposal mirrors an existing row it says which one.
9. **Two narrowings of granted rows** — §20.8.4 and §20.8.5 exclude the listing's own **seller** from
   bidding and offering. RLS §11.1 grants *"any `authenticated`"*, which read literally permits shill
   bidding on one's own listing. **Narrowing a ratified grant is a decision, not a clarification**, and it is
   flagged for the owner rather than absorbed.
10. **`venue.set_event_security_config` is wholly authored AND `⛔ BLOCKED`** (§20.6.6). RLS §11.4 grants
    EXECUTE and ROLE_MODEL §11 row 15 classifies it `NEW RPC`; **no document states what it configures**, and
    **no table exists for it to write to.** The key set, the tighten-only direction and the Wallet-span
    invariant re-check are authored so they are not invented at build time — but the storage gap is a
    separate, harder block (§20.14 **`R-21`**), and `086` must not schedule the function while it stands.
    Owner confirmation on the key set remains `R-11`.
11. **`kernel.revoke_signing_key`'s `p_ack_live_credentials`** (§20.7.5) mirrors §17.11's
    `p_ack_live_devices`. The corpus specifies the acknowledgement pattern for the door override and not for
    key revocation, where the consequence is strictly larger.
12. **Dual control on the signing-key trio** (§20.7.3–§20.7.5). RLS §11.7 mandates it for the *Wallet*
    `pass_type_cert` trio and §11.1 does not state it for the *signing-key* trio. Contracted with it, because
    the asymmetry reads as an omission: the pass certificate signs a wallet artifact, the signing key signs
    the admission credential itself.
13. **`venue.set_scan_device_status`** (§20.4.3, **superseding this document's earlier
    `venue.retire_scan_device`** — §20.13) and the **`market.offer` expiry sweep** (§20.8.5). Each
    corresponds to a status label the schema defines and **no function writes** — the same shape as `G-24`,
    found twice more during the reconciliation. **The setter's name, its two-way domain and obligation RV-2
    are TRANSCRIBED from schema §3.11.1, not authored**; only the earlier one-way `retire` was authored, and
    it is withdrawn.
14. **`market.respond_offer`'s `counter` branch** (§20.8.6). RLS §11.1 grants *"respond"* without
    enumerating the verbs; a negotiation surface with no counter is a decline button.
15. **`market.create_auction`'s `ends_after_freeze` warning field** (§20.8.3). The corpus states the freeze
    and never connects it to auction scheduling.
16. **The MVP position on the bid ledger** (§20.8.4 `OPEN DECISION`) is a **proposal, not a ruling** —
    §16.5, schema §4.2 and schema §4.9 leave it open in three different words. §20.14 R-9 files it.
17. **The upsert_identity_ext split into a self function and an admin function** (§20.1.3). One function
    whose parameter semantics depend on the caller's role is the pattern ROLE_MODEL R-8 removed from
    `has_venue_role`; two functions make the answer structural.
18. **The second named GP-2 exception** (§20.5.5 `venue.remove_guest_entry`). Granted on the same reasoning
    as the first (§0.5's `clear_my_demographics`): the object references no ledger, draws no capacity and
    moves no custody. **It is not a precedent for anything that does.**

**RPCs still lacking a named RLS policy after this pass: all of them — and that is correct, not a gap.**
Every contract in this document is a `SECURITY DEFINER` function, so a table policy on the objects it writes
never runs (§0.8, RLS GP-3a). Authority is `REVOKE EXECUTE` + a narrow `GRANT EXECUTE` + the in-body
predicate. The **only** policies in the Phase-2 model are **read** policies, registered by name in RLS §16.10
— no exception (`OR-1` retired the former Layer-0 carve-out). An implementer who writes policies for the
money or custody tables will produce policies that are never evaluated **and believe they are protected** —
which is the single most likely way to build this wrong.

---

**Additions from this reconciliation pass** (the four remediation passes' cross-file requests):

17. **The door-session contract set** — §9.6 `venue.mint_door_session`, §9.7 `venue.revoke_door_session`,
    §9.8 `venue.sweep_expired_door_sessions`. Schema §3.10a names all three (plus the `revoke_door_pin`
    cascade) in its write-authority list and files them here; **the bodies, parameter lists, error classes,
    lock orders, result shapes and the mint-supersedes-prior-session rule are authored.** The **security
    properties** — the four assert clauses, the plain-digest-vs-slow-KDF split, RV-1, the partial unique —
    are transcribed from schema §3.10a and are **not** this document's inventions.
18. **The `p_door_session_id` / `/refresh` resolutions** (§1.1d `AUTHZ-H3a`) are **rulings between two
    sibling specs**, not transcription. Both are filed back for confirmation (§20.14 `R-19`), and the
    alternative for the selector is stated so the owner can take it.
19. **The `venue.assert_may_request` helper** (§17.22) is named here. The CRM spec states the predicate must
    be *"the same predicate a fresh request would face"* and gives it no name; **an unnamed shared predicate
    is two copies of a predicate**, which is exactly how the download check lost the template.
20. **`kernel.revoke_signing_key`'s door-episode force-close write set and lock order** (§20.7.5). Edge §5.6
    and door §16 OQ-5 **require** the force-close as a grant condition; **which rows it writes, in which
    order, and that `episodes_force_closed` is the blast-radius number shown to the operator are authored.**
21. **Error-class opacity on the door path** — §1.1d returns one class for six distinct failures and
    **never `not_found`**. The specs require equal timing and shape; **collapsing the error class is this
    document's expression of that**, and it is stated because an implementer who returns `not_found` for an
    unknown id has re-opened the enumeration oracle the dummy compare closes.

## 20. SET CLOSURE — the reconciliation of this document against RLS §11 and migration plan §8

**Why this section exists, stated once.** A traceability pass established a structural property of the
corpus, and it is the reason a dozen gaps survived four integration passes:

> **`PHASE_2_RLS_PERMISSION_SPEC.md` §11's EXECUTE-authority table is the complete statement of Phase-2 write
> authority. This document was a proper *subset* of it.**

The corpus contracted the functions a **product surface** demanded. It did not contract the functions an
**authority table** granted. Nine of the missing functions are additionally **scheduled as objects** in
`PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8's per-package **Functions** rows — so an implementer opens the plan,
sees the object, finds no signature anywhere in the corpus, **and invents one.** That is how an authority
model gets quietly reinterpreted by whoever writes the SQL first.

§20 closes the difference in **both** directions. It adds no authority: every contract below cites the RLS
§11 EXEC row or the ratified ruling it derives from, and **where RLS §11 is silent the contract says so and
proposes**, marked `PROPOSED AUTHORITY` — never assumed. Nothing in §0–§19 is rewritten; §20 is additive.

### 20.0a Method (reproducible, not editorial)

1. **Set A** — every function granted EXECUTE anywhere in RLS §11, all eight blocks (§11.1–§11.8).
2. **Set B** — every function named in migration plan §8's per-package **Functions** rows, `076`–`091`.
3. **Set C** — every function carrying a contract in this document, §1–§19.
4. **Δ1 = (A ∪ B) \ C** — authorized or scheduled, uncontracted. *An engineer will invent each one.*
5. **Δ2 = C \ A** — contracted, unauthorized. *Equally a defect: a function with no EXEC row has no stated
   grant class, so a migration author must guess between `authenticated` and `service_role`.*

**Aliases are resolved before differencing**, using §20.13's naming register, so a name divergence
(`catalog.publish_event` ↔ `catalog.set_event_status`) is counted as **one function with two names** (a
`G-20` defect) and **not** as a member of both differences.

**Trigger functions are excluded from the two GRANT-difference sets** — they are never `EXECUTE`d by a
principal and hold no grant, so neither §11's authority table nor a grant class applies to them — **but
they are NOT excluded from the canonical writer registry. The previous text here excluded them "by
construction" from every set; under owner ruling `OR-7` that exclusion is NON-CONFORMANT and was the root
cause of three findings** (`kernel.set_updated_at` absent from every per-table writer set; the
demographic-erasure tombstone trigger with no name and no contract, `J-12`; the class being the one most
likely to be silently absent — `RC-3`, `WRITER_PARITY_ROOT_CAUSE_MAP`). **A trigger that WRITES a table is
a WRITER and must appear in the registry with kind `trigger`** (`kernel.set_updated_at`,
`kernel.raise_append_only` and `catalog.tg_door_open_at_is_ledger_head` write nothing on their guard paths
— a raising guard is not a writer; `set_updated_at` DOES write `updated_at` and IS one). Behavioural
specification may remain in the plan row that creates a trigger; writer IDENTITY lives here. *(Corrected
2026-08-29, writer-parity pass; the exclusion sentence survives only inside this correction as history.)*

### 20.0b **Δ1 — authorized or scheduled, and contracted nowhere** (the forward difference, in full)

**49 functions.** `A` = has an RLS §11 EXEC row · `B` = named in plan §8 · `U-n` = dashboard §20A.3 unbacked
control · `G-n` = traceability-matrix gap id.

| # | Function | In | Closed at |
|---|---|:---:|---|
| 1 | `kernel.set_org_connect_ref` | — *(edge §3.3 only; **`G-3`**)* | §20.1.1 |
| 2 | `kernel.set_org_status` | `A` | §20.1.2 |
| 3 | `kernel.upsert_identity_ext` | `A` | §20.1.3 |
| 4 | `kernel.grant_platform_role` | `A` | §20.1.4 |
| 5 | `kernel.revoke_platform_role` | `A` | §20.1.4 |
| 6 | `kernel.update_organization` | `U-10`, **`G-12`** | §20.1.5 |
| 7 | `catalog.set_platform_config` | `A` ×2, `B`(`078`), **`G-6`** | §20.2.1 |
| 8 | `catalog.set_resale_policy` | `A`, `B`(`078`), **`G-20`** | §20.2.2 |
| 9 | `catalog.update_event` | `U-9`, **`G-12`** | §20.2.3 |
| 10 | `catalog.update_event_session` | `U-9`, **`G-12`** | §20.2.4 |
| 11 | `catalog.set_session_door_schedule` | `A` *(as the mis-named `venue.set_door_open_at`, **`G-14`**)* | §20.6.5 |
| 12 | `venue.set_ticket_type_price` | `A`, `B`(`081`), **`G-20`** | §20.3.1 |
| 13 | `venue.set_batch_capacity` | `U-8`, **`G-12`** | §20.3.2 |
| 14 | `venue.sweep_expired_inventory_holds` | schema §3.5 object list + the `081` partial index, **`G-24`** | §20.3.3 |
| 15 | `venue.grant_staff_role` | `A`, **`G-13`** | §20.4.1 |
| 16 | `venue.revoke_staff_role` | `A`, **`G-13`** | §20.4.2 |
| 17 | `venue.register_scan_device` | `A`, `B`(`086`), **`G-13`** | §20.4.3 |
| 18 | `venue.sync_scan_device_manifest` | `A` *(as the unnamed **"manifest-sync"**, **`G-13`**)* | §20.4.4 |
| 19 | `venue.allocate_comp` | `A`, `B`(`086`), **`G-4`** | §20.5.1 |
| 20 | `venue.issue_comp` | `A`, `B`(`086`), **`G-4`** | §20.5.2 |
| 21 | `venue.create_guest_list` | RLS §9.16, `U-1`, **`G-10`** | §20.5.3 |
| 22 | `venue.upsert_guest_entry` | RLS §9.16, `U-1`, **`G-10`** | §20.5.4 |
| 23 | `venue.remove_guest_entry` | RLS §9.16, `U-1`, **`G-10`** | §20.5.5 |
| 24 | `venue.check_in_guest_entry` | RLS §9.16 n39, `U-2`, **`G-9`** | §20.5.6 |
| 25 | `venue.get_door_manifest` | `A`, `B`(`086`), **`G-15`** | §20.6.1 |
| 26 | `catalog.sweep_implicit_door_freezes` | `A`, `B`(`086`), **`G-21`** | §20.6.2 |
| 27 | `venue.preview_door_open_impact` | `U-5`/Δ11, **`G-16`** | §20.6.3 |
| 28 | `venue.get_live_device_count` | `U-6`/Δ12, **`G-17`** | §20.6.4 |
| 29 | `venue.set_event_security_config` | `A` (O4-4), **`G-14`** | §20.6.6 |
| 30 | `kernel.admin_refund` | `A`, `B`(`085`), **`G-7`** | §20.7.1 |
| 31 | `kernel.pay_promoter_commission` | `A`, **`G-7`** | §20.7.2 |
| 32 | `kernel.provision_signing_key` | `A`, `B`(`083`), **`G-7`** | §20.7.3 |
| 33 | `kernel.rotate_signing_key` | `A`, `B`(`083`), **`G-7`** | §20.7.4 |
| 34 | `kernel.revoke_signing_key` | `A`, `B`(`083`), **`G-7`** | §20.7.5 |
| 35 | `market.create_listing` | `A`, `B`(`088`), **`G-5`** | §20.8.1 |
| 36 | `market.cancel_listing` | `A`, `B`(`088`), **`G-5`** | §20.8.2 |
| 37 | `market.create_auction` | `A`, `B`(`088`), **`G-5`** | §20.8.3 |
| 38 | `market.place_bid` | `A` *(as the unnamed **"bid RPC"**)*, `B`(`088`), **`G-5`** | §20.8.4 |
| 39 | `market.make_offer` | `A`, `B`(`088`), **`G-5`** | §20.8.5 |
| 40 | `market.respond_offer` | `A`, `B`(`088`), **`G-5`** | §20.8.6 |
| 41 | `venue.create_promoter` | RLS §9.17, `U-3`, **`G-11`** | §20.9.1 |
| 42 | `venue.update_promoter` | RLS §9.17, `U-3`, **`G-11`** | §20.9.2 |
| 43 | `venue.create_promoter_link` | RLS §9.17, `U-4`, **`G-11`** | §20.9.3 |
| 44 | `venue.set_promoter_link_status` | RLS §9.17, `U-4`, **`G-11`** | §20.9.4 |
| 45 | `venue.check_promoter_slug_available` | `U-4`, **`G-11`** | §20.9.5 |
| 46 | `venue.get_dashboard_summary` | `U-7`, **`G-18`** | §20.10 |
| 47 | `kernel.settlement_royalty_lines` | `B`(`087`,`088`) | §20.11.1 |
| 48 | `kernel.settlement_commission_lines` | `B`(`087`,`090`) | §20.11.2 |
| 49 | `market.on_atom_voided` | `B`(`085`,`088`) | §20.11.3 |
| 50 | `venue.normalize_promoter_code` | `B`(`090`) | §20.11.4 |

*(Fifty rows for forty-nine functions: `catalog.set_session_door_schedule` at row 11 is the **re-homing** of
the row `venue.set_door_open_at`, which §20.6.5 rules **does not exist**. It is listed so the EXEC row it
replaces stays traceable, not because a fiftieth function is created.)*

### 20.0c **Δ2 — contracted here, and granted by no EXEC row** (the reverse difference, in full)

**A contract with no EXEC row is as much a defect as an EXEC row with no contract**, and for a concrete
reason: RLS §11's two grant classes (caller-authorized vs **`DEF`**) are what tell a migration author whether
to write `GRANT EXECUTE TO authenticated` or `GRANT EXECUTE TO service_role`. A function absent from §11 has
**no stated grant class**, so the author guesses — and the guess that fails open (`authenticated` on a
definer-only primitive) is the same class of defect as the missing contracts above, arriving from the other
side. **Six of the fourteen below are `EXEC: DEF` custody or sweep primitives where that guess is
catastrophic.**

**This document cannot fix these — RLS §11 is not our file.** They are filed for the RLS integrator, with the
grant class this document already fixes, so each row can be written without re-deriving it.

> **CLOSED (`AUTHZ-R2`).** RLS §11 now carries all fourteen, in a new **§11.1a**, with the `DEF` rows listed
> first and the grant class exactly as stated below. **`market.cancel_p2p_transfer` is recorded as
> dual-class** — caller-authorized for the sender, `DEF` for the `expired` transition it owns — which is the
> one row that could not be written as a single grant and is the reason the table below carries a "grant class
> this document fixes" column at all. The reverse difference Δ2 is empty.

| # | Contracted at | Function | Grant class this document fixes | Consequence of the missing row |
|---|---|---|---|---|
| 1 | §2.2 | `kernel.invite_org_member` | caller-authorized (`org_owner`,`org_admin`) | the org roster's **write** door has authority stated only in a contract |
| 2 | §2.3 | `kernel.accept_org_invite` | caller-authorized (the addressed invitee) | — |
| 3 | §3.3 | `catalog.update_venue` | caller-authorized (`venue_manager` OR org owner/admin) | the **operatorship (`org_id`) change** — an audited tenancy move — is authorized nowhere in §11 |
| 4 | §5.2 | `venue.create_inventory_batch` | caller-authorized (`venue_manager` OR org owner/admin) | the capacity counter (C27) is **created** by a function §11 does not mention |
| 5 | §5.4 | `venue.create_inventory_hold` | caller-authorized (`venue_manager` OR org owner/admin) | §11.1's `reserve_inventory`/`release_hold` row grants *"any authenticated (own hold)"*, which is the **buyer** hold's authority. The **staff** hold has different authority and no row |
| 6 | §6.3 | `venue.finalize_primary_order` | **`DEF`** | **SSCAS member #1.** Mints every atom in the system. A guessed `authenticated` grant hands any signed-in user the mint |
| 7 | §7.4 | `kernel.lock_ticket` | **`DEF`** | the resale-overlay choke-point and a freeze **enforcement** point (§12.4c) |
| 8 | §7.4 | `kernel.unlock_ticket` | **`DEF`** | — |
| 9 | §7.5 | `kernel.mark_ticket_scanned` | **`DEF`** | the custody-side `active → scanned` terminal transition |
| 10 | §8.3 | `market.cancel_p2p_transfer` | caller-authorized (the sender) **+ `DEF`** for the `expired` transition | it **owns the `expired` state**, so it is dual-class; §11.1's `create_p2p_transfer`/`accept_p2p_transfer` row omits it entirely |
| 11 | §9.3 | `venue.validate_ticket_online` | caller-authorized (`venue_scanner`,`venue_manager`) **OR** the `service_role` door path via `assert_door_session` | the C37 live-verify read — the same dual-path shape §11.1 spells out for `record_scan` |
| 12 | §11.1 | `kernel.force_void_ticket` | caller-authorized (`platform_admin`,`platform_risk`) | a **platform break-glass void**, exempt from the door freeze (§12.4c), with no authority row |
| 13 | §12.2 | `market.sweep_expired_p2p_transfers` | **`DEF`** | recon #1's TTL sweep |
| 14 | §12.3 | `market.sweep_paid_pending_sales` | **`DEF`** | **C25 auto-compensation** — the sweep that stops a buyer's money dwelling in `paid_pending_transfer` forever |

> **`T-RPC-SET-01` (structural, and the only test that keeps §20 true).** Enumerate `pg_proc` for the four
> Phase-2 schemas, subtract the trigger functions of §20.0a, and assert the result equals the union of the
> functions named in RLS §11 and the functions contracted in this document — **in both directions**. A future
> RPC added to one surface and not the other then fails CI rather than waiting for a fifth audit pass.
> Non-vacuity guard: the assertion must prove it can see at least the fifty functions §20 names.

### 20.0d Two properties §20 preserves, asserted rather than assumed

- **SSCAS stays closed at fifteen.** Not one contract below requires a sixteenth member. Every
  multi-aggregate write in §20 is either a **caller of an existing member** (`venue.issue_comp` → member #1's
  mint leg; `market.create_listing` → member #6; `market.respond_offer` accept → member #2;
  `kernel.admin_refund` → member #3; `kernel.pay_promoter_commission` → member #5's payout leg) or a
  **bounded batch of one** (`venue.sweep_expired_inventory_holds`), which is the construction
  `catalog.cancel_event` (#3) and `venue.open_door_manifest` (#6/#7-reverse) already use. Everything else is
  tagged `SSCAS: n/a (single-aggregate)`. **§14.1's member → RPC map gains callers, not members** — the
  addendum is §20.12. **C28's closed fifteen and §14.2's lock-order proof stand unamended.**
- **No new lock class and no new ordering obligation.** Every lock taken below is an existing rank of
  `Event/Session(1) < Inventory(2) < Order(3) < Listing(4) < Ticket Atom(5) < Approval/Request(5.5) <
  money-plane(6)`, or an **admin-plane** row (organization, identity_ext, platform_role, staff_role,
  scan_device, signing_key, promoter, platform_config, guest_list) outside the six ranks — the same
  classification §17.23 uses for the Wallet objects, and for the same reason: an object outside the order
  creates no ordering obligation, so no member's proof changes.

### 20.0e ADDENDUM — objects that entered sets A/B AFTER §20.0b was computed (`R1`, 2026-08-28)

**§20.0b's *"49 functions"* is NOT amended, and that is deliberate.** It is the output of the differencing
run described in §20.0a against the corpus as it stood at that pass; **editing the number would make the
method unreproducible** while leaving the run undocumented. **Six objects have since been scheduled into
packages by later passes and were uncontracted here** — the same Δ1 shape, arriving after the difference was
taken. They are listed rather than folded in, so a re-run of §20.0a's method reproduces `49` and this
addendum accounts for the remainder.

| Object | Entered via | In | Closed at |
|---|---|---|---|
| `kernel.mark_payout_transfer_state` | `MB-2b` (schema §1.9.2, plan `085`, registry `085`) | **B** — no EXEC row (`R-31`) | **§20.7.6** |
| `venue.on_payout_settled` | `MB-2b` (stub `085`, body `087`) | **B** — no EXEC row (`R-31`) | **§20.11.5** |
| `kernel.sweep_expired_ticket_atoms` | `MN-4` (schema §1.5.1, plan/registry `079`) | **B** — no EXEC row (`R-30`) | **§12.5** |
| `venue.assert_may_request` | `K-3` / `R-7` (plan `087`, registry `087`) | **A ∪ B** — *called* by RLS §7.5/§11.6, **granted by no EXEC row** (`R-29`) | **§20.7.8** |
| **`kernel.mark_refund_state`** | **this pass** (`R1-1`, schema §1.10.1) — the writer `kernel.refund` never had | neither yet (`R-31`) | **§20.7.7** |
| `kernel.record_money_denial` | already contracted (§17.9); **its EXEC row is wrong, not missing** | **A** | §17.9 (`R-28`) |

**Both properties of §20.0d survive, checked rather than assumed.** **SSCAS stays closed at fifteen:**
§20.7.6, §20.7.7 and §20.7.8 are `n/a (single-aggregate)` or write nothing; §12.5 is a **bounded batch of
one**; §20.11.5 participates in no member. **No new lock class:** §20.7.6/§20.7.7 take the money plane
(rank 6), §12.5 takes Ticket Atom (rank 5), §20.7.8 takes nothing, and §20.11.5 takes the settlement header,
an admin-plane row outside the six ranks. **§20.11.5 introduces the pass's one new ordering obligation and it
is stated in its own contract**, not here.

### 20.1 ORGANIZATION AND PLATFORM AUTHORITY — the `077` / `085` gap

#### 20.1.1 `kernel.set_org_connect_ref(p_org_id, p_connect_account_id, p_command_key)` — **EDGE-FRONTED** · `NEW RPC` (`G-3`)

**The precondition for every payout in the system, wrapped by an edge function and contracted nowhere.**
`connect-onboarding` (edge §3.3, `verify_jwt=true`) creates the Stripe Express `Account` and the
`AccountLink`, then must record the account id on the org. Edge §9 recon #12 files the request verbatim:
*"it appears in neither `PHASE_2_RPC_FUNCTION_CONTRACTS.md` nor RLS §11's EXEC table … or §3.3 has no write
path."* It has none. Connect onboarding cannot complete, so **no org can ever be paid.**

- **Signature.** `kernel.set_org_connect_ref(p_org_id uuid, p_connect_account_id text, p_command_key text)`.
- **Actor & EXECUTE authority.** `p_actor := auth.uid()`. `PROPOSED AUTHORITY` — **RLS §11 is silent on this
  function entirely.** Proposed: `has_org_role(p_org_id, ['org_owner','org_finance'])`, which is exactly the
  predicate edge §3.3 already states and edge §9 recon #12 already proposes; this document adopts it rather
  than inventing a third. Caller-authorized ⇒ **bound by EDGE-CALLER-JWT (§0.1a)**: `connect-onboarding` holds
  the service-role key for its Stripe calls and **must** build its Supabase client from the caller's
  `Authorization` header to invoke this, or both role predicates silently degrade to false-on-NULL.
- **`SPEC CORRECTION` — this function is BIND-ONCE, and that is a security property, not a convenience.**
  It and `kernel.set_org_payout_destination` (§17.7) write **the same column**,
  `kernel.organization.stripe_connect_account_ref`. §17.7 restricts that write to `org_owner` **only** and
  wraps it in the full control set — SoD-1, destination probation, out-of-band notification, step-up
  freshness — expressly because `org_finance` holding both halves of *"redirect the account, then release
  funds to it"* is the named fraud primitive. **This function grants `org_finance`.** If it could overwrite a
  non-NULL ref it would be a **complete bypass of §17.7's entire control set through a lower-authority
  door**, and nothing in the corpus currently says it cannot. Therefore:
  - `stripe_connect_account_ref IS NULL` ⇒ **bind**, and stamp `payout_destination_set_by := auth.uid()` so
    **SoD-1 applies from the very first destination** (without the stamp, the identity that onboards is also
    eligible to request the first payout — the primitive, on day one);
  - ref is non-NULL and **equal** to `p_connect_account_id` ⇒ `noop_replay` (this is the *"reuse existing
    connect ids"* path SPEC_FOUNDATION §2 requires, and the common case on a re-onboarding retry);
  - ref is non-NULL and **different** ⇒ **`precondition_failed('destination_already_set')`**, whose message
    names `kernel.set_org_payout_destination` as the only path. **A re-point is never an onboarding event.**
- **Preconditions.** Org exists and `status ∈ {applied, approved, active}` (a `suspended`/`closed` org may not
  bind a payee); `p_connect_account_id` matches the Stripe account-id shape and is **not already bound to
  another org** — the schema's `UNIQUE(stripe_connect_account_ref) WHERE NOT NULL` makes that structural, and
  a violation surfaces as `conflict_locked`, never as a silent re-point.
- **Locks & acquisition order.** `kernel.organization` row `FOR UPDATE` — **admin plane, outside the six
  money/custody ranks**; nothing else is locked. No ordering obligation.
- **SSCAS.** `n/a (single-aggregate — Organization)`.
- **Idempotency.** `p_command_key`, plus the bind-once state guard above. A replayed onboarding returns the
  bound id.
- **Postconditions / writes.** `kernel.organization` (`stripe_connect_account_ref`,
  `payout_destination_set_by := auth.uid()` **on the bind only**), `kernel.admin_audit`
  (`org.connect_ref.bind`, `subject_kind='organization'`, `before=NULL`, `after=<account id>`). **No bank
  detail ever enters the database** — the stored value is an opaque Stripe account id and bank details are
  collected by Stripe's own KYC'd onboarding (§17.7 makes the same point about the same column).
- **Result.** `{ status, org_id, connect_account_id, newly_bound bool }`.
- **Errors.** `insufficient_privilege(42501)` · `not_found` · `precondition_failed(org_not_bindable |
  destination_already_set | malformed_account_ref)` · `conflict_locked` (id bound to another org) ·
  `idempotency_replay`.
- **Forbidden callers.** `org_admin`, `org_member`, `org_marketing`, `org_promoter_manager`, every venue role,
  every platform role, fans, `anon`. **Platform is deliberately excluded**: a platform role binding an org's
  payee is a money-destination write, and RLS §11.3 already rules that no platform role touches the
  destination — only `hold_payout`/`release_payout`.
- **Tests.** `T-RPC-CONNECT-01` (bind on NULL succeeds and stamps `payout_destination_set_by`) ·
  `T-RPC-CONNECT-02` (**the bypass regression**: an `org_finance` re-point of a non-NULL ref raises
  `destination_already_set` and writes nothing — asserted, because this is the whole of §17.7's control set
  defended at a second door) · `T-RPC-CONNECT-03` (the same id re-bound to the same org ⇒ `noop_replay`; to a
  different org ⇒ `conflict_locked`) · `T-RPC-CONNECT-04` (invoked on a service-role client, `auth.uid()` is
  NULL and the function **raises** rather than binding — the §0.1a enforceable form).

#### 20.1.2 `kernel.set_org_status(p_org_id, p_target_status, p_reason_code, p_command_key)` — **DB-RPC**

- **Signature / authority.** `is_platform(['platform_admin'])` — **RLS §11.1, verbatim.** The org lifecycle's
  only writer after `create_organization` (§2.1) inserts at `applied`.
- **Params.** `p_target_status ∈ {applied, approved, active, suspended, closed}` (schema §1.2's enum, closed
  set, re-validated in-body), `p_reason_code` **mandatory on every non-forward transition**. All untrusted.
- **Preconditions.** Org exists; the transition is legal —
  `applied → approved → active`, and `{approved, active} → suspended → active`, and any state `→ closed`.
  **`closed` is terminal**; there is no path out of it, and re-opening is a new org.
- **Locks & acquisition order.** `kernel.organization` row `FOR UPDATE` (admin plane). Nothing else.
- **SSCAS.** `n/a (single-aggregate)`.
- **Idempotency.** `p_command_key` + the state guard (target = current ⇒ `noop_replay`).
- **Writes.** `kernel.organization.status`; `kernel.admin_audit` (`org.status.change`, before/after,
  `reason_code`).
- **Result.** `{ status, org_id, org_status }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `precondition_failed(illegal_transition | terminal_state | reason_required)` · `idempotency_replay`.
- **What suspension does NOT do, stated because an implementer will otherwise assume it.** Suspending an org
  **moves no custody, voids no atom, cancels no event and stops no admission.** It is an authority state read
  by other functions' preconditions (`catalog.create_venue` §3.1 requires `approved`/`active`;
  `kernel.request_org_payout` §10.3 reads it). Making it cascade would make a support action into a
  bounded-batch custody operation, which is `catalog.cancel_event`'s job (§4.4) and requires that authority.
- **Forbidden callers.** Every org role including `org_owner` (an org cannot approve itself),
  `platform_support`, `platform_risk`, every venue role, fans, `anon`.
- **Test.** `T-RPC-ORG-01` (an `org_owner` self-approval raises; `closed → active` raises; a suspension
  leaves every atom, session and scan of that org's events untouched — asserted by row count, not inspection).

#### 20.1.3 `kernel.upsert_identity_ext(p_patch, p_command_key)` — **DB-RPC**

- **Authority — two disjoint branches in one function, which is why the parameter set is split.** RLS §11.1:
  *"owner (benign) · `is_platform([platform_admin])` (region/kyc)"*.
  - **self branch:** `auth.uid()` writes **only** `locale` on its own row. No identity parameter exists on
    this branch, so *"edit someone else's row"* is **unexpressible**, the same construction §17.20 uses for
    demographics.
  - **platform branch:** `is_platform(['platform_admin'])` writes `residency_region` / `kyc_ref` for a named
    `p_identity_id`, audited with `reason_code`.
- **Signature.** `kernel.upsert_identity_ext(p_patch jsonb, p_command_key text)` for the self branch;
  `kernel.admin_set_identity_ext(p_identity_id uuid, p_patch jsonb, p_reason_code text, p_command_key text)`
  for the platform branch. **`INFERENCE` — the split into two functions is authored here.** One function
  whose *"is this parameter honoured?"* answer depends on the caller's role is the pattern
  ROLE_MODEL R-8 removed from `has_venue_role` (§1.1), and for the same reason: a reviewer reading the call
  site cannot tell what it does. Two functions make the answer structural.
- **Preconditions.** `residency_region ∈` the allowed-region CHECK set (MVP: `us-east`); `locale` is a
  well-formed BCP-47 tag or NULL — **NULL is meaningful** (schema §1.1: it means *"not stated"*, the third
  link of the resolution chain, not a default). `kyc_ref` is an opaque handle: **no PII is accepted into it**,
  and the audit row records that it changed, never its value.
- **Locks.** The `kernel.identity_ext` row `FOR UPDATE` (admin plane). **SSCAS.** `n/a`.
- **Idempotency.** `p_command_key`; the upsert is naturally idempotent (PK = `identity_id`).
- **Writes.** `kernel.identity_ext`; `kernel.admin_audit` (`identity_ext.update` — **platform branch only**;
  a fan setting their own locale is not a privileged mutation and §0.3 does not reach it).
- **Result.** `{ status, identity_id }`. **Errors.** `insufficient_privilege` · `precondition_failed(
  bad_region | bad_locale)` · `not_found`.
- **Forbidden callers.** Any principal writing another identity's row outside the platform branch; **every
  org and venue role** — a venue may not set an attendee's region, locale or KYC reference, which is the same
  boundary §17.21 draws around contact consent.
- **Test.** `T-RPC-ORG-02` (the self-branch signature has **no** uuid parameter; a `venue_manager` and an
  `org_owner` are both refused on the platform branch; a `kyc_ref` change writes an audit row whose payload
  contains no value).

#### 20.1.4 `kernel.grant_platform_role(p_identity_id, p_role, p_reason_code, p_command_key)` · `kernel.revoke_platform_role(...)` — **DB-RPC** ×2

**The grant of platform authority itself, uncontracted.** Every `is_platform` predicate in the corpus reads
the table these two write.

- **Authority.** `is_platform(['platform_admin'])` **plus the `public.admin_users` bootstrap** — RLS §11.1
  verbatim — **with dual control (C11)**. The bootstrap exists because the first `platform_admin` cannot be
  granted by a `platform_admin`; it is a **read** of the frozen Phase-0 table, never a write to it.
- **Dual control is structural here, not a seam.** A grant creates a `kernel.approval_request`
  (`action='platform_role.grant'`) that a **second distinct `platform_admin`** must approve, and **only the
  approval inserts the `kernel.platform_role` row** — the same two-step §11.3 mandates for
  `catalog.set_platform_config` on money-namespace keys, and for the same reason: a control that gates money
  authority is exactly as money-consequential as the action it gates. `kernel.approval_request`'s SoD CHECK
  (`approved_by <> requested_by`, plan `077`) enforces the distinctness in the database.
- **Direction asymmetry, matching §11.3's.** **Revocation executes directly; only a grant needs the second
  approver.** A security control that is hard to *tighten* during an incident is a liability, and the failure
  modes are not symmetric: an over-eager revoke locks an operator out for minutes, an unapproved grant hands
  out `platform_risk`.
- **`p_role ∈ {platform_admin, platform_support, platform_risk}`** — the platform enum only, re-validated
  in-body (C36; org and venue labels are members of a different enum and raise).
- **No self-grant, and no last-admin revoke.** `p_identity_id = auth.uid()` on the grant path raises
  `precondition_failed('self_grant')` (I-11). A revoke that would leave **zero** identities holding
  `platform_admin` across `kernel.platform_role` ∪ `public.admin_users` raises `precondition_failed(
  'last_platform_admin')`, re-counted **under the lock**, not before it — the same construction §2.4 uses for
  the last `org_owner`.
- **Locks & acquisition order.** `kernel.platform_role` rows for `p_identity_id` `FOR UPDATE`, then the
  `kernel.approval_request` row (rank 5.5) on the grant path. Both admin plane; the request object's rank is
  the only one in the global order and it is acquired last, so no inversion. **SSCAS.** `n/a`.
- **Idempotency.** `p_command_key`; PK `(identity_id, role)` makes a re-grant a `noop_replay` and a
  re-revoke terminal.
- **Writes.** `kernel.approval_request` (grant path), `kernel.platform_role` (INSERT on approval / DELETE-free
  revoke — **the revoke removes the PK row, which is the one place a role table has no state column**;
  GP-2's "no RPC deletes rows" is satisfied because the audit row carries the removed grant, exactly as §2.5
  handles `org_member`), `kernel.admin_audit` (`platform_role.grant` / `.revoke`, before/after, mandatory
  `reason_code`).
- **Result.** `{ status, identity_id, role, request_id }` (`request_id` non-null on a parked grant).
- **Errors.** `insufficient_privilege` · `precondition_failed(self_grant | last_platform_admin | bad_role)` ·
  `sod_violation` (self-approval of one's own parked grant) · `idempotency_replay`.
- **Forbidden callers.** `platform_support`, `platform_risk`, **every org and venue role including
  `org_owner`**, fans, `anon`, and any `service_role` path — this is one function where no `DEF` door exists
  at all, because a machine identity granting platform authority is the shape of a supply-chain compromise.
- **Tests.** `T-RPC-ROLE-06` (a grant with one approver inserts **no** `platform_role` row) ·
  `T-RPC-ROLE-07` (self-approval of one's own request raises `sod_violation`) · `T-RPC-ROLE-08` (revoking
  the last `platform_admin` raises, counting `public.admin_users` in the total) · `T-RPC-ROLE-09` (an `org_*`
  or `venue_*` label passed as `p_role` raises — the disjoint-enum property, C36).

#### 20.1.5 `kernel.update_organization(p_org_id, p_patch, p_command_key)` — **DB-RPC** (`U-10`, `G-12`)

- **Authority.** `PROPOSED AUTHORITY` — **RLS §11 is silent.** Proposed: `has_org_role(p_org_id,
  ['org_owner','org_admin'])`, by symmetry with `catalog.update_venue` (§3.3), which grants
  `venue_manager` **OR** org owner/admin for the venue's benign profile fields. Dashboard §16.1 asks for it
  and RLS §7.2's column grants imply it; neither names a function.
- **The patch set is closed, and its complement is the point.** Writable: `display_name`. **Not writable by
  this function, each for a stated reason:** `legal_name` (it is the payee's legal identity and changing it
  after a Connect account is bound de-synchronises the platform from Stripe's KYC record — a
  `platform_admin` action with a reason code, not an org self-service edit); `status` (§20.1.2);
  `stripe_connect_account_ref` and `payout_destination_*` (§17.7 / §20.1.1 — **a benign-profile RPC that
  could touch a money column is the §20.1.1 bypass in another costume**); `home_region` (C14 single-region;
  changing it is a data-residency decision). **A key outside the writable set raises `invalid_input`; it is
  never silently ignored** — silent ignore is how a UI ships a control that does nothing.
- **Locks.** `kernel.organization` row `FOR UPDATE` (admin plane). **SSCAS.** `n/a`. **Idempotency.**
  `p_command_key`; a no-change patch is `noop_replay`.
- **Writes.** `kernel.organization`; `kernel.admin_audit` (`org.update`, before/after).
- **Result.** `{ status, org_id }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `invalid_input(unwritable_key)` · `precondition_failed(empty_name)`.
- **Forbidden callers.** `org_finance`, `org_marketing`, `org_promoter_manager`, `org_member`, every venue
  role, fans, `anon`.
- **Test.** `T-RPC-ORG-03` (**structural**: the function's definition references none of
  `stripe_connect_account_ref`, `payout_destination_set_by`, `payout_destination_locked_until`, `status`,
  `legal_name`, `home_region`; a patch naming any of them raises `invalid_input`).

#### 20.1.6 `kernel.revoke_org_invite(p_invite_id, p_command_key)` — **DB-RPC** · `NEW RPC` (fence `kernel.org_invite` row; `RC-4` "a revoke RPC"; authored 2026-08-29, sprint agent 2)

> **Three of `kernel.org_invite.status`'s five labels had no writer** (triage `F-4`). *(Historical count — the enum is FOUR labels since `OR-18` struck `declined`, 2026-08-29.)* Schema §1.3b's
> write-authority line names *"a revoke RPC"*, RLS §7.3b grants EXECUTE on *"revoke"* to two org tiers and
> platform, the plan's `077` Functions row scheduled neither name — the `RC-4` shape verbatim.

- **Purpose.** Withdraw a `pending` invite before acceptance. The invite is the capability *offer*, never the
  capability itself (RLS §7.3b) — revoking it removes the offer and releases the partial
  `UNIQUE(org_id, invitee_ref) WHERE status='pending'` so the same person can be re-invited without waiting
  out `expires_at`.
- **Authority.** Caller-authorized — `has_org_role(invite.org_id, [org_owner, org_admin])` OR
  `is_platform([platform_admin])` (RLS §7.3b: *"invite-revoke (inviter-tier or platform)"*). **Tier guard:**
  an `org_admin` may not revoke an `org_owner`-tier invite — the reading consistent with §2.2's invite guard
  and §2.5's *"cannot remove a higher tier than caller"*, this function's own family. `INFERENCE — flagged
  (R-11 standard):` the venue plane rules role *revocation* the opposite way (§20.4.2); the org-plane sibling
  is the nearer precedent and is followed; the owner may relax the guard — a one-line change here and nowhere
  else.
- **Scope binding.** `org_id` is **read from the invite row under its lock, never a parameter** (`AUTHZ-C1C`).
- **Params.** `p_invite_id`, `p_command_key` — untrusted. **Server-derived:** `auth.uid()`, `now()`.
- **Preconditions.** Invite exists; `status='pending'` — including a pending row past `expires_at` (revoking
  a lapsed offer is the immediate form of the sweep's unique-release). An **accepted** invite raises
  `precondition_failed('invite_not_pending')`: membership is removed only by `kernel.remove_org_member`
  (§2.5) — reaching an accepted invite here would bypass the "≥1 `org_owner`" invariant.
- **Locks.** The invite row `FOR UPDATE`. Nothing else. **SSCAS:** n/a. Race with `accept_org_invite`: both
  take the row lock; exactly one commits, the loser raises on the now-terminal status.
- **Writes.** `kernel.org_invite` (→ `revoked`), `kernel.admin_audit` (`org.invite.revoke`, before/after,
  **carrying the invited role's money-role class** — §2.2's `AUTHZ-C1B` legibility rule applies to the
  withdrawal: invite → revoke → re-invite-lower is a pattern, not three rows).
- **Result.** `{ status }`. **Idempotency.** `p_command_key` + terminal state — replay on `revoked` revokes
  nothing twice (§9.2 posture).
- **Errors.** `not_found` · `insufficient_privilege` · `precondition_failed('invite_not_pending' | 'tier')` ·
  `idempotency_replay`.
- **Forbidden callers.** The addressed invitee (they hold accept, only — §7.3b); org_member/org_finance;
  every venue role; `platform_support`/`platform_risk`; anon.
- **Tests.** `T-RPC-ORG-04` (an `org_admin` revoking an `org_owner`-tier invite raises; an `org_owner`
  succeeds; **after revoke a re-invite of the same `invitee_ref` succeeds, and while `pending` it fails on
  the partial unique** — the release is the load-bearing half) · `T-RPC-ORG-05` (concurrent accept/revoke:
  exactly one wins; a revoked-then-accepted invite raises and writes **no `kernel.org_member` row —
  asserted on the roster, not on the error**).

#### 20.1.7 `kernel.sweep_expired_org_invites(p_limit int DEFAULT 500)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (RLS §7.3b service_role row; authored 2026-08-29)

> **RLS §7.3b's service_role row grants *"definer (expiry sweep → `expired`)"* — an EXECUTE for a function
> no document contracted**, the `R-29` shape on the invite table. Unlike the offer tick (§4.3.1 — *"an
> offer holds nothing"*), this transition is load-bearing at exactly one point: the partial
> `UNIQUE(org_id, invitee_ref) WHERE status='pending'` means a lapsed invite that never leaves `pending`
> **blocks re-inviting that person permanently**. Name authored here so it can be granted, tested and cited
> (the §17.20 `reconcile_holder_mix` convention); flagged in §19.

- **Authority.** **`EXEC: DEF`** — `REVOKE EXECUTE FROM anon, authenticated, public`, `GRANT EXECUTE TO
  service_role` only. **Scheduling: an explicit `cron.schedule` entry in its package (`077`), 2-minute
  cadence** — *NOT "the heartbeat that already runs": red-team `P0-1` (2026-08-29) proved no shared
  heartbeat dispatcher exists in production or in any band package; every sweep names its own entry until
  the dispatcher question (`P0-1`, filed) is settled.* No human path; `auth.uid()` NULL by construction.
- **Preconditions.** `status='pending' AND expires_at < now()`, ordered by `expires_at`, `LIMIT p_limit`,
  **`FOR UPDATE SKIP LOCKED`** — a row mid-accept is skipped, not fought over (§20.3.3 construction).
- **The sweep is never the enforcement** (§4.3.1's rule): `accept_org_invite` already refuses an
  over-`expires_at` invite on the row, regardless of stored status. The tick makes the stored label agree
  with the arithmetic **and releases the partial unique**, which the arithmetic cannot do.
- **Writes.** `kernel.org_invite` (→ `expired`) only. No audit rows — a TTL lapse is not an administrative
  action (§12.2 posture). **Each row its own transaction** (poison-quarantine, §20.3.3).
- **Result.** `{ swept }`. **Idempotency.** Re-entrant; overlapping ticks harmless.
- **Tests.** `T-RPC-ORG-06` (with the tick **disabled**, accept of a past-`expires_at` `pending` invite
  raises — the `T-SCHEMA-OFFER-01` construction; after one tick the same `invitee_ref` can be re-invited —
  the unique-release half, asserted because it is the reason this sweep exists).

### 20.2 CATALOG AND CONFIG — the `078` gap

#### 20.2.1 `catalog.set_platform_config(p_key, p_value, p_reason_code, p_command_key)` — **DB-RPC** (`G-6`)

**Every money threshold in the system is set through this function, and it had no signature.** The refund
tiers, the payout dual-control minimum, the destination probation window, the step-up AAL and max age, the
door freeze offset and manifest TTL, the CRM caps and retention — all of them are `catalog.platform_config`
rows, and RLS §11.3 makes this their mandatory dual-control writer.

- **Signature.** `catalog.set_platform_config(p_key text, p_value jsonb, p_reason_code text,
  p_command_key text)`.
- **Authority.** `is_platform(['platform_admin'])` — RLS §11.1 and §11.3. **Caller-authorized ⇒ bound by
  EDGE-CALLER-JWT.**
- **Dual control is MANDATORY, not a seam, for SEVEN key namespaces** — RLS §11.3: `refund.*`, `payout.*`,
  `authn.*`, **`comp.*`** (`AUTHZ-M8` — those keys are the gate on the insider-fraud control), and, added by
  edge recon #16 / Wallet §11.5b, **`wallet.*`**, **`credential.*`** and **`door.session_*`**. For those keys
  the call **creates a `kernel.approval_request`** which a **second distinct `platform_admin`** must approve,
  and **only the approval inserts the new `(key, version+1)` row.**

  > **Why the three new namespaces belong here and are not scope creep.** `wallet.*` and `credential.*` gate
  > a **feature-enable** — `wallet.apple.enabled` is a kill switch RLS §11.7 states is *"not
  > role-bypassable"*, and a kill switch one account can flip is not a kill switch. `door.session_*` sets
  > **the lifetime of a bearer credential** (`door.session_ttl_interval`,
  > `door.session_absolute_max_interval`, `door.session_post_session_grace`): raising it extends how long
  > every stolen door tablet on the platform keeps working, which is the same class of act as raising a
  > refund ceiling and is now the direct lever on `AUTHZ-H3`'s revocation guarantee. **The direction
  > asymmetry applies unchanged — two approvers to loosen, one to tighten** — so shortening a session TTL
  > during an incident still executes in one transaction.
- **`required_approver_class = 'platform_admin'` is WRITTEN on the parked path (`AUTHZ-C1A`, schema §13.7
  `S-1`).** The money arm of this function is one of the three writers of that column (with §17.1 and
  §10.3), and **it is the arm with the narrowest approver set**: `action='config.set_money_key'` at
  `required_approver_class='platform_admin'` is approvable by `is_platform(['platform_admin'])` **only**
  (§17.2, `AUTHZ-C1A2`). It is **server-set from the namespace and the direction, never a parameter**, and
  pinned exactly as `config_versions` is. Writing it here is what stops `platform_support` — the role capped
  *because* it is not trusted with unbounded money — from approving the raise of the cap that bounds it.
  **`subject_kind='config_key'` and `subject_id` are written with it**, per `APPR-SUBJ-1` below.
- **Direction asymmetry (RLS §11.3, binding).** **Lowering a limit executes directly; only raising one needs
  the second approver.** *"A security control that is hard to tighten in an incident is a liability."*
  The direction is computed server-side from the key's declared **polarity**, never supplied by the caller:
  - `p_value` numerically **more restrictive** than the current version (a lower ceiling, a higher required
    AAL, a shorter max age, a longer probation) ⇒ execute in one transaction;
  - **less restrictive** ⇒ park an approval request;
  - **not comparable** (a non-scalar value, a namespace change, a key with no declared polarity) ⇒ **park.**
    `INFERENCE:` the third arm is authored here. RLS §11.3 states the asymmetry for the scalar case and is
    silent on the rest, and *"not comparable"* must fail toward the approver, or a `jsonb` object becomes the
    door through which a threshold is raised without one.
- **Preconditions.** `p_key` is a **member of the seeded key registry** (`078` seeds every key; **this
  function creates no new key** — a key that no code reads is a config row that lies, and a key an implementer
  invents at 2 a.m. is worse); `p_value` passes the key's declared type/range; `p_reason_code` mandatory for
  every key, not only the money namespaces.
- **Locks & acquisition order.** The key's latest `catalog.platform_config` row `FOR UPDATE` (admin plane,
  serialising two concurrent version bumps) → `kernel.approval_request` (rank 5.5) on the parked path.
  Ascending; nothing else. **SSCAS.** `n/a (single-aggregate)`. The approval object's own SSCAS status is the
  open flag of §16.8 and is **unchanged** by this contract.
- **Idempotency.** `p_command_key` + `UNIQUE(key, version)`. **Config is append-only per version** (schema
  §2.4): a change **inserts** `(key, version+1)`; **no row is ever updated or deleted**, so an object
  governed by an old version stays interpretable (C11/O3). A replay returns the version it created.
- **Writes.** `catalog.platform_config` (INSERT one new version — direct path, or from the approval),
  `kernel.approval_request` (parked path), `kernel.admin_audit` (`config.change`, before/after = the two
  version numbers **and** the two values, `reason_code`).
- **Result.** `{ status ∈ {ok, parked, noop_replay}, key, version, request_id }`. **A parked call returns
  `parked` with the request id and `version` unchanged** — the UI must say *"waiting for a second
  approver"*, never *"saved"*.
- **Errors.** `insufficient_privilege` · `precondition_failed(unknown_key | bad_value | reason_required)` ·
  `sod_violation` (approving one's own parked change) · `idempotency_replay`.
- **Forbidden callers.** `platform_support`, `platform_risk` (risk holds `hold_payout`, not the thresholds
  that decide when a payout needs approval at all), **every org and venue role**, fans, `anon`, and every
  `service_role` path — **a migration is not a config change** (plan §4: values are seeded in `078`; flips
  are never a migration).
- **Tests.** `T-RPC-CFG-01` (raising `payout.dual_control_min_minor` parks and inserts no version; lowering it
  executes) · `T-RPC-CFG-02` (a `jsonb`-object value on a money key **parks**, whichever direction it
  appears to move) · `T-RPC-CFG-03` (a key not in the `078` registry raises `unknown_key`) ·
  `T-RPC-CFG-04` (the config table has **zero** UPDATE and **zero** DELETE paths — asserted as `postgres`
  and as `service_role`, because the append-only-per-version property is what makes an old snapshot
  interpretable).

#### 20.2.2 `catalog.set_resale_policy(p_scope_kind, p_scope_id, p_policy, p_command_key)` — **DB-RPC**

- **Authority.** `has_org_role(['org_owner','org_admin'])` OR `has_venue_role(['venue_manager'])` ·
  `is_platform(['platform_admin'])` — RLS §11.1 verbatim.
- **Params.** `p_scope_kind ∈ {org, venue, event}` with `p_scope_id`; `p_policy` = `{ mode ∈ {off, capped,
  free}, price_cap_bps, transfer_window }`, all untrusted and re-validated against the CHECK set.
- **Versioning is the whole contract.** `catalog.resale_policy` is **snapshot-referenced**:
  `market.listing_native` stores `resale_policy_id` **and** `resale_policy_version` at listing creation
  (schema §4.1, O3/C11). So a policy change **inserts a new version** and **never mutates a live one** — a
  listing created under `capped` at 110% stays governed by that version for its whole life, and a tightening
  binds only listings created after it. **Retroactive tightening is not offered**, because it would change
  the terms of an offer a seller already published and a buyer may already have acted on.
- **Preconditions.** Scope exists and the caller's authority covers it (an `org_admin` may not set a policy
  on a venue outside their org — resolved through `has_org_role_over_venue`, §1.1a, never a re-inlined join);
  `mode='capped' ⇒ price_cap_bps` present and within the platform ceiling read from
  `catalog.platform_config`. **A venue may tighten below the platform ceiling and may never exceed it.**
- **Locks.** The scope's latest policy row `FOR UPDATE` (admin plane). **SSCAS.** `n/a`.
- **Idempotency.** `p_command_key` + `UNIQUE(scope, version)`; an identical policy is `noop_replay` and
  **issues no new version** — version churn on a no-op edit would make the snapshot references unreadable.
- **Writes.** `catalog.resale_policy` (INSERT new version), `kernel.admin_audit` (`resale_policy.change`).
- **Result.** `{ status, policy_id, version }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `precondition_failed(cap_exceeds_platform_ceiling | bad_mode | scope_out_of_authority)` ·
  `idempotency_replay`.
- **Forbidden callers.** `org_finance`, `org_marketing`, both promoter-manager labels, `venue_box_office`,
  `venue_scanner`, the door session, `venue_finance`, promoters, fans, `anon`.
- **Test.** `T-RPC-CFG-05` (a live listing's governing policy is unchanged by a subsequent tightening —
  asserted through `market.get_market_sale_status`'s fee split on a sale of that listing, not by reading the
  policy table).

#### 20.2.3 `catalog.update_event(p_event_id, p_patch, p_command_key)` — **DB-RPC** (`U-9`, `G-12`)

**Creation is contracted; editing is not.** `catalog.create_event` (§4.1) exists and no update counterpart
does, in any document.

- **Authority.** `PROPOSED AUTHORITY` — RLS §11 is silent on the update half. Proposed: **identical to
  `catalog.create_event`** (RLS §11.1: `has_org_role(['org_owner','org_admin'])` OR
  `has_venue_role(['venue_manager'])`). Editing an event one may create is not a wider capability.
- **Editability is bounded by lifecycle, not by role, and the boundary is `draft`.** Dashboard §7.3
  specifies editability while `draft`. This contract states what happens after:
  - **`draft`** — the full benign patch set: `title`, `description`, `hero_image_ref`, `category`,
    `genre_tags`.
  - **`announced` / `on_sale` / `live`** — `description`, `hero_image_ref`, `category`, `genre_tags` remain
    editable; **`title` requires a `reason_code` and is audited**, because the title is what a buyer saw on
    the receipt for a ticket they already hold.
  - **`completed` / `cancelled`** — **nothing is editable.** `precondition_failed('event_terminal')`.
  - **Never editable by this function:** `venue_id` (moving an event between venues re-parents its sessions,
    its inventory and its signing-key scope — it is not a patch, and Phase 2 does not build it),
  `org_id`, `status` (that is `catalog.publish_event`, §4.2).
- **Locks.** `catalog.event` row `FOR UPDATE` (**rank 1** — the lowest rank in the total order, so prefixing
  it is unconditionally ascending, §0.4). Nothing else. **SSCAS.** `n/a (single-aggregate — Event/Session)`.
- **Idempotency.** `p_command_key`; a no-change patch is `noop_replay`.
- **Writes.** `catalog.event`; `kernel.admin_audit` (`event.update`, before/after — **mandatory on a title
  change after `announced`**).
- **Result.** `{ status, event_id }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `precondition_failed(event_terminal | reason_required)` · `invalid_input(unwritable_key)`.
- **Forbidden callers.** fans, promoters, the door session, `venue_scanner`, `venue_box_office`, every
  finance and marketing label.
- **Test.** `T-RPC-CAT-01` (a patch naming `venue_id`, `org_id` or `status` raises `invalid_input`; a title
  change on an `on_sale` event without a reason code raises; on a `cancelled` event every patch raises).

#### 20.2.4 `catalog.update_event_session(p_session_id, p_patch, p_command_key)` — **DB-RPC** (`U-9`, `G-12`)

- **Authority.** `PROPOSED AUTHORITY` — as §20.2.3, mirroring `catalog.create_event_session` (§4.3).
- **The patch set, and the three columns it must never touch.** Writable: `session_label`, `starts_at`,
  `ends_at`, `doors_at` — **subject to the guard below**. **Never writable here:**
  - **`door_open_at`** — `catalog.engage_door_freeze` (§17.12) is its **sole writer** under ruling O-5, and
    a trigger enforces that independently of grants. See §20.6.5.
  - **`session_version`** — never a **patch key** (a client-named write raises `invalid_input`, `T-RPC-CAT-02`) —
    **but the BODY auto-increments it, in this transaction, under the row's `FOR UPDATE`, whenever
    `starts_at`/`doors_at`/`ends_at`/`status` change.** *(Corrected 2026-08-29, E-1 DISSOLVED: this line
    previously read "a monotone counter owned by the notification plane" — an ownership attribution with an
    EMPTY REFERENT: the notification plane's own catalog names THIS function as the bumper (NOTIF Group E,
    "`session_version`. A monotonic counter bumped by `catalog.update_event_session`"), the schema spec says
    "advanced only by the session-update RPC, inside the same transaction … no other writer touches it", and
    the ratified dedupe property is satisfiable ONLY by the in-txn bump — a bump performed at drain time reads
    the same live value for two queued changes and reproduces the exact swallowed-second-notification failure
    the column exists to prevent. Three sites to four words; one admissible value; no owner bit exercised.)*
  - **`event_id`** — re-parenting a session moves its atoms' event scope.
- **The time guard, which is a custody property and not a validation nicety.** `starts_at` and `doors_at`
  are the **inputs to `catalog.effective_freeze_at`** (§12.4a), and that function is what decides when
  transfers stop. Therefore:
  - while the session is `scheduled` **and** `door_open_at IS NULL` **and** no atom has been issued against
    it, all four fields move freely;
  - once **any atom exists** for the session, `starts_at`/`doors_at` may move **only earlier or by less than
    `config('door.schedule_move_grace_interval')`**, and any move is audited with a mandatory reason code —
    **moving them later pushes the implicit freeze backstop later**, which is precisely the *"hour of
    live-door / open-transfer overlap"* §12.4a's choice of `doors_at` exists to close;
  - once `door_open_at IS NOT NULL`, `doors_at` and `starts_at` are **frozen** —
    `precondition_failed('boundary_engaged')`. The boundary has been taken; the schedule that produced it is
    now evidence. (The post-publish schedule move that O4-3 was reaching for is §20.6.5, which carries these
    same guards and the audit trail.)
  - `ends_at > starts_at` always; `session_label` unique per event always.
- **Locks.** `catalog.event_session` row `FOR UPDATE` (rank 1). **SSCAS.** `n/a`. **Idempotency.**
  `p_command_key`.
- **Writes.** `catalog.event_session`; `kernel.admin_audit` (`session.update`, before/after, reason code
  where required).
- **Result.** `{ status, session_id, effective_freeze_at }` — **the recomputed boundary is returned**, so the
  operator sees the consequence of the edit in the same round trip rather than discovering it at the door.
- **Errors.** `insufficient_privilege` · `not_found` · `precondition_failed(boundary_engaged |
  move_exceeds_grace | reason_required | session_terminal)` · `invalid_input(unwritable_key)`.
- **Forbidden callers.** As §20.2.3.
- **Test.** `T-RPC-CAT-02` (a patch naming `door_open_at` raises `invalid_input`; a later `doors_at` on a
  session with issued atoms raises `move_exceeds_grace`; any `doors_at` move after `door_open_at` is set
  raises `boundary_engaged`).

### 20.3 INVENTORY — the `081` gap, including the sweep that returns held capacity

#### 20.3.1 `venue.set_ticket_type_price(p_ticket_type_id, p_price_minor, p_reason_code, p_command_key)` — **DB-RPC**

Promoted from §5.1's one-line *"Companion"* note to a contract: it carries its own RLS §11.1 EXEC row, it is
money-consequential, and *"same role, live-recheck"* is not a signature.

- **Authority.** `has_venue_role(venue_of_event, ['venue_manager'])` OR `has_org_role(org,
  ['org_owner','org_admin'])` — RLS §11.1, **with the live-table recheck C9 requires** for a
  money-consequential write (never a JWT claim).
- **Preconditions.** `p_price_minor > 0`; the type's event is not `completed`/`cancelled`; `p_reason_code`
  mandatory.
- **The property that makes a price change safe, stated because it is easy to break.** **Every order snapshots
  `unit_price_minor` from `venue.ticket_type` at `create_primary_checkout` time** (§6.1, server-authoritative
  pricing). So a price change **binds only orders created after it** and **cannot re-price a pending order, a
  paid order, a refund amount, or a settlement line.** `kernel.request_order_refund` (§17.1) derives
  `expected` from `venue.order_item.unit_price_minor` — *"an immutable purchase snapshot"* — and never from
  the type. **An implementer who "simplifies" the order item to a lookup on the type re-prices history and
  breaks every refund cap in the system.**
- **Locks.** `venue.ticket_type` row `FOR UPDATE` (rank 2, Inventory class). Nothing else. **SSCAS.**
  `n/a (single-aggregate — Inventory)`.
- **Idempotency.** `p_command_key`; an identical price is `noop_replay`.
- **Writes.** `venue.ticket_type.price_minor`; `kernel.admin_audit` (`ticket_type.price_change`,
  before/after, `reason_code`).
- **Result.** `{ status, ticket_type_id, price_minor }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `precondition_failed(bad_price | event_terminal | reason_required)`.
- **Forbidden callers.** `venue_box_office`, `venue_scanner`, the door session, `venue_finance`,
  `org_finance`, both promoter-manager labels, promoters, fans, `anon`.
- **Test.** `T-RPC-INV-01` (a price change after an order is created leaves that order's
  `order_item.unit_price_minor`, its refundable ceiling and its settlement line **byte-identical**).

#### 20.3.2 `venue.set_batch_capacity(p_batch_id, p_new_capacity, p_reason_code, p_command_key)` — **DB-RPC** (`U-8`, `G-12`)

- **Authority.** `PROPOSED AUTHORITY` — RLS §11 is silent. Proposed: **identical to
  `venue.create_inventory_batch`** (§5.2) — `has_venue_role(['venue_manager'])` OR
  `has_org_role(['org_owner','org_admin'])`. Changing a counter one may create is not a wider capability;
  **but see the refusal floor, which is where the real control lives.**
- **The refusal floor is a C27 property, and it is absolute.** Under the batch lock:
  **`p_new_capacity >= held + sold`**, always. Below that, `precondition_failed('below_committed')` naming
  the two numbers. There is **no force flag, no override role and no platform bypass** — a capacity beneath
  what is already committed would mean *"tickets exist for seats that do not"*, which is the oversell C27
  exists to make structurally impossible. **A room that got smaller is a refund decision
  (`kernel.request_order_refund`), never a counter edit.**
- **Sharded batches.** When `is_sharded`, the delta is distributed across shards and the invariant
  `Σ shard.capacity = batch.capacity` is re-asserted **inside the transaction**, with shards locked
  **ascending `shard_no`** (C27/§0.4). A shrink draws down only from shards whose own `held + sold` leaves
  room; if the distribution cannot be satisfied, the whole call raises rather than leaving a partial spread.
- **Locks & acquisition order.** `venue.inventory_batch` `FOR UPDATE` (rank 2) → `venue.inventory_batch_shard`
  ascending `shard_no` `FOR UPDATE` (rank 2, within-class ascending). Ascending; nothing else.
  **SSCAS.** `n/a (single-aggregate — Inventory)`.
- **Idempotency.** `p_command_key`; an identical capacity is `noop_replay`.
- **Writes.** `venue.inventory_batch.capacity` (+ shard capacities), `venue.inventory_movement` (a
  cause-keyed `capacity_change` row, so the counter still reconciles to its ledger — **the C27 discipline is
  that every capacity delta has a ledger row, and an edit is a delta**), `kernel.admin_audit`
  (`inventory.capacity.change`, before/after, mandatory `reason_code`).
- **Result.** `{ status, batch_id, capacity, held, sold, remaining }`.
- **Errors.** `insufficient_privilege` · `not_found` · `precondition_failed(below_committed | bad_capacity |
  shard_distribution_unsatisfiable | reason_required)` · `idempotency_replay`.
- **Forbidden callers.** Fans, promoters, the door session, `venue_scanner`, `venue_box_office`, every
  finance and marketing label, **and every platform role** — a platform capacity edit on a venue's room is
  not a support action.
- **Tests.** `T-RPC-INV-02` (a shrink below `held + sold` raises **as every authorized role, and as
  `platform_admin`**, and writes nothing) · `T-RPC-INV-03` (after a sharded grow, `Σ shard.capacity =
  batch.capacity` and the movement ledger reconciles).

#### 20.3.3 `venue.sweep_expired_inventory_holds(p_limit)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (`G-24`)

> **Without this function, held capacity never returns to the counter.** Schema §3.5 lists *"the expiry
> sweep"* among `venue.inventory_hold`'s write authorities and states *"expiry sweep flips `active→expired`
> and returns `held`"*; migration plan `081` builds the partial index `expires_at WHERE status='active'`
> **precisely so a sweep can use it**; and then `081`'s Functions row names `create_inventory_hold` and
> `release_inventory_hold` and **no sweep**, its Tests row is silent, §12's sweeps are the two `market.*`
> ones, and RLS §11 grants no such EXEC. **Four documents build the runway and none lands the plane.**
>
> **Consequence if it stays unbuilt:** a `venue.inventory_hold` row never leaves `active` on its own, so
> every abandoned checkout removes inventory from sale **permanently**. A sold-out-looking Friday with
> nobody in the room is not a degraded mode; it is the guaranteed steady state. This is the exact shape of
> `kernel.sweep_expired_refund_requests`, which the money spec calls *"not optional"* and which **is**
> contracted (§17.4).

- **Signature.** `venue.sweep_expired_inventory_holds(p_limit int DEFAULT 500) RETURNS { swept, released_qty,
  batches_touched }`.
- **Authority.** `PROPOSED AUTHORITY` — RLS §11 is silent. Proposed **`EXEC: DEF`** — `REVOKE EXECUTE FROM
  anon, authenticated, public`, `GRANT EXECUTE TO service_role` only; invoked by the **2-minute `pg_cron`
  heartbeat that already runs** (the same carrier §8-COND-A names, and one this sweep does **not** depend on
  the outbox ruling for — it needs a scheduler, not a carrier). No human path, no actor: `auth.uid()` is NULL
  by construction, exactly as for `market.sweep_expired_p2p_transfers` (§12.2).
- **Preconditions.** Selects `venue.inventory_hold WHERE status='active' AND expires_at < now()`, ordered by
  `expires_at`, `LIMIT p_limit`, **`FOR UPDATE SKIP LOCKED`** — so a hold a checkout is mid-conversion on is
  skipped rather than fought over, and two heartbeats overlapping is harmless.
- **It performs no counter arithmetic of its own.** Per row it calls **`venue.release_inventory_hold(hold_id,
  p_command_key := 'sweep:'||hold_id)`** (§5.5) with the `expired` transition. **The sweep is a scheduler, not
  a second writer of the counter** — the same construction §12.2 uses (`sweep_expired_p2p_transfers` calls
  `cancel_p2p_transfer`), and it is what keeps `venue.inventory_batch.held` single-writer.
- **Locks & acquisition order.** Per row, inherited from `release_inventory_hold`: **Inventory batch
  (`FOR UPDATE`, rank 2) → the hold row.** Rows are processed in ascending `batch_id` then `hold_id` so a
  batch is never re-entered, and **the batch lock is taken before the hold** — the same
  Inventory-before-anything discipline §14.2's NB pins for the void path. **SSCAS.** `n/a` — a **bounded batch
  of a single-aggregate operation**, which is not a cross-aggregate transaction and needs no member. **The set
  stays closed at fifteen.**
- **Idempotency.** Per row, `release_inventory_hold`'s own terminal-state guard plus the deterministic command
  key: a hold already `released`/`converted`/`expired` is a no-op, so a re-run, an overlapping tick and a
  crashed mid-batch retry all converge. **Each row is its own transaction**, so one poisoned hold cannot
  block the batch — the poison-quarantine shape §17.24 requires of `drain_outbox`.
- **Result.** `{ swept, released_qty, batches_touched }`. **Errors.** None expected; a row that raises is
  counted, audited as `inventory.hold.sweep_error` and skipped, and the tick continues.
- **Load-bearing status, stated because §17.11 states the opposite about its own sweep and the distinction
  matters.** `kernel.sweep_expired_door_overrides` is explicitly **not** load-bearing — overrides expire
  arithmetically inside `is_transfer_frozen` whether or not it runs. **This sweep IS load-bearing.**
  `venue.inventory_batch.held` is a **stored counter**, not a derived predicate: nothing recomputes it, so an
  unswept hold is permanently consumed capacity. **`T-RPC-INV-04` asserts the difference:** with the sweep
  disabled, `remaining` on a batch with an expired hold is provably wrong; with it enabled, it returns to the
  pre-hold value.
- **Forbidden callers.** Every client, every human role, every edge function on a caller-JWT client.
- **Tests.** `T-RPC-INV-04` (above) · `T-RPC-INV-05` (a hold that converts to a sale in the same window is
  **skipped, not released** — the `SKIP LOCKED` + terminal-state pair, asserted under concurrency, because
  releasing a converted hold would return capacity that was actually sold) · `T-RPC-INV-06` (a re-run over
  the same window releases nothing further and the counter is unchanged).

### 20.4 VENUE STAFF AND DEVICES — the `080` / `086` gap

#### 20.4.1 `venue.grant_staff_role(p_venue_id, p_identity_id, p_role, p_command_key)` — **DB-RPC** (`G-13`)

**The primary authority-conferring write in the venue plane, uncontracted.** Every `has_venue_role` predicate
in the corpus reads the table this function writes.

- **Authority — `AUTHZ-M7`, and it is NARROWER than the row this contract was written against.**
  `has_venue_role(p_venue_id, ['venue_manager'])` **for the five non-manager labels only**; granting
  **`venue_manager` itself** requires `kernel.has_org_role_over_venue(p_venue_id, ['org_owner','org_admin'])`
  or `is_platform(['platform_admin'])`. **The inheritance is expressed through the §1.1a helper and never as a
  re-inlined `catalog.venue.org_id` join** (`T-RPC-ROLE-02`).
- **`p_role` ∈ the six canonical venue labels** — `venue_manager · venue_finance · venue_box_office ·
  venue_marketing · venue_promoter_manager · venue_scanner` — re-validated in-body against the `080` CHECK.
  **`venue_door` and `venue_promoter` are not members and raise** (ROLE_MODEL R-8; the label sets are
  disjoint by scope, so an `org_*` or `platform_*` label raises too).
- **No self-grant (I-11), and the tier guard — `AUTHZ-M7`, which did not exist.** `p_identity_id = auth.uid()`
  raises `precondition_failed('self_grant')`. **A `venue_manager` may NOT grant `venue_manager`**; that raises
  `precondition_failed('tier_guard')` and directs the caller to the org plane.

  > **The previous reasoning was true of the label lattice and false of the capability set, and a tier guard
  > is about the capability set.** *"There is no higher venue label to guard against"* is correct as a
  > statement about names — and `venue_manager` is nonetheless **one of only three principals that may
  > `open_door_manifest`** (RLS §11.4, ruling O-4), i.e. **engage a session's terminal transfer-freeze
  > boundary and take custody offline for the night.** A `venue_manager` minting another `venue_manager` is
  > therefore minting a custody-boundary principal, from inside the venue, with no org-plane involvement and
  > no step-up — and O-4's whole content is that *"the scanner may not create the security boundary it works
  > inside."* One compromised venue-manager credential otherwise self-perpetuates: revoke it and the account
  > it granted is still there, still able to grant.
  >
  > **The cost is one org-plane round trip and nothing else.** `org_owner`/`org_admin` already reach every
  > venue through `has_org_role_over_venue` (§1.1a), so no new authority is created and no venue becomes
  > unmanageable — it is the *same* principals the corpus already relies on for the recovery case §20.4.2
  > describes (*"a venue with zero managers is recoverable — the org tier above it reaches the venue"*). This
  > closes the symmetry: the org tier is who **restores** a venue manager, so it is who **creates** one.
  > Owner decision **MD-15** records that this narrows a previously affirmative grant.
- **The promoter exclusion is structural, and this contract must not break it.** **`grant_staff_role` accepts
  no `promoter_id`, `promoter_link_id`, `attribution_id` or referral id of any kind** — §1.1c's
  `T-RPC-ROLE-04` asserts exactly this over the grant RPCs, and adding a promoter artifact to this signature
  would create the promoter → administrator write path that predicate exists to deny.
- **Preconditions.** Venue exists and is not `archived`; `p_identity_id` resolves to a live `auth.users` row.
  **The target need not already be affiliated with the org** — `kernel.is_org_affiliate` is a *scoping* input
  and never an authorizing one (RM-6), so requiring affiliation here would import an authorization meaning it
  does not have.
- **Locks & acquisition order.** The `venue.staff_role` rows for `(p_venue_id, p_identity_id)` `FOR UPDATE` —
  **admin plane**, outside the six ranks. Nothing else. **SSCAS.** `n/a (single-aggregate)`.
- **Idempotency.** `p_command_key`; PK `(venue_id, identity_id, role)` makes a re-grant a `noop_replay`.
- **Writes.** `venue.staff_role` (INSERT), `kernel.admin_audit` (`venue.staff_role.grant`,
  `subject_kind='identity'`, before/after = the label set).
- **Result.** `{ status, venue_id, identity_id, role }`.
- **Errors.** `insufficient_privilege(42501)` · `not_found` · `precondition_failed(self_grant | tier_guard |
  bad_role | venue_archived)` · `idempotency_replay`.
- **Forbidden callers.** `venue_box_office`, `venue_scanner`, **the door session** (it holds no `auth.uid()`
  and is denied on every capability outside its four, §1.1d), `venue_finance`, `venue_marketing`, both
  promoter-manager labels, `org_finance`, `org_member`, promoters, fans, `anon`, and **`platform_support` /
  `platform_risk`** — neither holds a venue-roster write in RLS §11.
- **Test.** `T-RPC-STAFF-01` (self-grant raises; `venue_door`/`venue_promoter`/`org_owner` as `p_role` raise;
  a `venue_box_office` caller raises; an `org_admin` of the venue's org succeeds **through the §1.1a
  helper**, asserted by the function's definition referencing `has_org_role_over_venue` and not
  `catalog.venue`) · **`T-RPC-AUTHZ-14`** (`AUTHZ-M7`: a `venue_manager` granting `venue_manager` raises
  `tier_guard`; **the same caller granting each of the other five succeeds** — so the test proves a narrowing,
  not a lockout; an `org_admin` of the venue's org grants `venue_manager` successfully).

#### 20.4.2 `venue.revoke_staff_role(p_venue_id, p_identity_id, p_role, p_command_key)` — **DB-RPC** (`G-13`)

- **Authority.** As §20.4.1 — RLS §11.1 pairs them in one row.
- **Self-revoke is PERMITTED, and the asymmetry with §20.4.1 is deliberate.** Dropping one's own authority is
  not a privilege escalation, and refusing it would leave a departing manager unable to stand down. **There is
  no "last `venue_manager`" floor**, unlike §2.4's last-`org_owner` invariant: a venue with zero managers is
  recoverable — the org tier above it reaches the venue through `has_org_role_over_venue` and can grant a new
  one. **An org with zero owners is not recoverable, which is why that floor exists and this one does not.**
  Stated because the symmetry is tempting and would be wrong.
- **Revocation takes effect immediately, everywhere, with no TTL.** `has_venue_role` is a **live table read**
  (§1.1, I-5), so a revoked principal's next call fails inside the function — no JWT survives it. This is the
  property that makes a door PIN revocable *now* (§1.1d) and it holds identically here.
- **Locks / SSCAS / idempotency / writes.** As §20.4.1; the row is removed and `kernel.admin_audit`
  (`venue.staff_role.revoke`) carries the removed grant (the §2.5 / §20.1.4 treatment of GP-2 on a
  PK-only role table). A re-revoke is `noop_replay`.
- **Result.** `{ status }`. **Errors.** `insufficient_privilege` · `not_found` · `idempotency_replay`.
- **Test.** `T-RPC-STAFF-02` (a revoked `venue_scanner`'s next `record_scan` raises **within the same
  session and the same JWT** — the live-read property, asserted behaviourally).

#### 20.4.3 `venue.register_scan_device(p_venue_id, p_label, p_command_key)` — **DB-RPC** (`G-13`)

- **Authority.** `has_venue_role(p_venue_id, ['venue_manager'])` — RLS §11.1 (*"`register_scan_device` /
  manifest-sync | `has_venue_role([venue_manager])`; sync also `venue_scanner` (own device)"*), plus org→venue
  inheritance by the same §1.1a helper the paired row's manager branch uses.
- **Params.** `p_venue_id`, `p_label` (untrusted, display only), `p_command_key`. **Server-derived:**
  `device_id`, `status := 'active'`, `manifest_version := NULL`, `last_sync_at := NULL`, `device_boot_id :=
  NULL`.
- **A registered device is not yet an authorized device, and conflating the two is the failure to avoid.**
  Registration creates a hardware identity in `venue.scan_device`. **It confers no authority at all**: the
  door path's entire authorization surface is `kernel.assert_door_session(device_id, session_id,
  door_session_id, token)` (§1.1d), which additionally requires **a live `venue.door_session` whose token the
  caller holds**, minted against an active, unexpired `venue.door_pin` **bound to that session**. A device
  with no minted session can do nothing — **and since `AUTHZ-H3`, neither can one that has a live PIN but no
  token.** **`T-RPC-STAFF-03` asserts it:** a freshly registered device with no session is refused by
  `assert_door_session`, and therefore by `record_scan`, `get_door_manifest` and `reconcile_offline_scans`.
- **Status changes are a separate verb this contract also defines — `venue.set_scan_device_status`, which
  SUPERSEDES the `venue.retire_scan_device` this document previously authored.**

  > **Naming reconciliation (schema §3.11.1 / §13.7 `S-11`).** Two passes named the same writer
  > independently: this document authored **`venue.retire_scan_device(p_device_id, p_reason_code,
  > p_command_key)`** (one-way, `active → retired`); the schema pass — which owns `venue.scan_device.status`
  > — named **`venue.set_scan_device_status(p_device_id, p_status, p_reason_code, p_command_key)`**
  > (two-way, `p_status ∈ {active, retired}`) and filed it here. **Resolved to the schema pass's name and
  > shape**, for the reason it gives and this document did not consider: **un-retire must be permitted**,
  > because the common real case is a device found again, and a one-way transition pushes operators to
  > register a duplicate device row — **which fragments the scan ledger's device attribution, the exact
  > property X-2 exists to protect**. `retire_scan_device` does not exist; the naming register (§20.13)
  > records the supersession so an implementer following an older copy does not build both.

  `venue.set_scan_device_status(p_device_id, p_status, p_reason_code, p_command_key)` — **authority: the
  O-4 allow-list** (`has_venue_role(venue,['venue_manager'])` OR
  `has_org_role_over_venue(venue,['org_owner','org_admin'])` OR `is_platform(['platform_admin'])`), **and a
  door session may never call it** (O-4: the scanner may not change the boundary it scans against — *and a
  device that can retire itself can also un-retire itself*). `p_status` re-validated in-body against the
  `active · retired` CHECK set; `p_reason_code` **mandatory**.
- **RV-2 (BINDING) — retiring a device revokes every `active` `venue.door_session` for it in the SAME
  transaction.** `revoked_reason := 'device_retired'`. §1.1d clause 3 already makes those sessions fail, so
  **RV-2 is not what enforces revocation — it is what makes the console truthful**, the same reasoning as
  RV-1 (§9.2). Un-retiring (`retired → active`) revokes nothing and restores nothing: the device must
  re-mint against a live PIN, because a session revoked by RV-2 is terminal.
- **This is the fastest kill switch in the system, and `AUTHZ-H3` is what makes it non-negotiable.**
  Before the door session existed, retirement *"revoked nothing by itself"* — a retired device with a live
  PIN was still admitted. It now stops a **physical device that already holds a live bearer token**, without
  waiting for the session TTL and **without revoking the PIN every other device at the door is also using**.
  A dashboard showing a *Retire device* control the database cannot honour is worse than no control, because
  a manager will believe the device is dead.
- **Locks & order on a status change.** `venue.scan_device` row `FOR UPDATE` → its `venue.door_session` rows
  `FOR UPDATE` ascending `door_session_id` (RV-2). Admin plane; **no SSCAS rank**.
- **Test.** `T-RPC-STAFF-05` (a retired device's next door call raises, **and** it holds no `status='active'`
  session row — **both halves**, because the first passes even if RV-2 was never implemented) ·
  `T-RPC-STAFF-06` (a door session calling it raises; un-retire does not resurrect a revoked session).
- **Locks.** None on register (INSERT); the status-change lock order is stated above. **Admin plane. SSCAS.** `n/a`.
- **Idempotency.** `p_command_key`; a status change to the value already held is `noop_replay`, not an error.
- **Writes.** `venue.scan_device`; `venue.door_session` (→ `revoked` ×N on retire, RV-2); `kernel.admin_audit`
  (`scan_device.register` / **`device.status.change`** with before/after and the mandatory `reason_code`).
- **Result.** `{ status, device_id }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `precondition_failed(venue_archived)` · `idempotency_replay`.
- **Forbidden callers.** `venue_scanner` (it may **sync** its own device, never register one), the door
  session, `venue_box_office`, every finance/marketing/promoter label, fans, `anon`.

#### 20.4.4 `venue.sync_scan_device_manifest(p_device_id, p_session_id, p_known_manifest_version)` — **DB-RPC** · `NEW RPC` (`G-13`) — **the function RLS §11.1 grants and never names**

RLS §11.1's row reads *"`venue.register_scan_device` / **manifest-sync**"*, and schema §3.11's write authority
reads *"`venue.register_scan_device`, **manifest-sync RPC**"*. **Two documents grant EXECUTE on a function
with no name.** It is named here.

- **Naming, stated plainly.** **`venue.sync_scan_device_manifest` is a name this document assigns.** No
  source names it. Chosen to match the file's verb-first convention and to say what it does to which object
  (`venue.scan_device`'s `manifest_version` / `last_sync_at`), so it is not confused with
  **`venue.get_door_manifest`** (§20.6.1), which *returns the manifest* and writes nothing.
- **Signature.** `venue.sync_scan_device_manifest(p_device_id uuid, p_session_id uuid,
  p_known_manifest_version int, p_device_boot_id uuid)`.
- **Authority — the dual path, verbatim from RLS §11.1.** (a) an authenticated `venue_manager` for the venue,
  or a `venue_scanner` **for its own device only** (the device's `venue_id` must be one the caller holds
  `venue_scanner` on, and the sync may not name another device); **or** (b) the `service_role` **edge** path
  with `kernel.assert_door_session(p_device_id, p_session_id, p_door_session_id, p_session_token)` asserted
  in-body. **Never a `door_pin` tested
  by `has_venue_role`** (R-8). On branch (b) `auth.uid()` is NULL **by design**, exactly as for
  `record_scan`.
- **What it does, and what it deliberately does not.** It **records sync state and returns the delta cursor**:
  the current `manifest_version`, the `manifest_digest`, `not_after`, and `max_delta_seq`. **It does not
  return manifest entries** — that is `get_door_manifest`'s job, and splitting them is what lets a scanner
  poll cheaply on a bad connection without re-downloading a 5,000-row snapshot. A caller whose
  `p_known_manifest_version` already equals the current one gets `{ up_to_date: true }` and nothing else.
- **Preconditions.** Device `status='active'` and belongs to the session's venue; an episode with
  `status='open'` exists for `p_session_id` — **if none is open the call returns `{ open: false }` and is
  not an error**, the same non-raising posture §17.13 requires (a scanner polling before doors is normal).
- **Locks & acquisition order.** `venue.scan_device` row `FOR UPDATE` (admin plane) → a **read** of
  `venue.door_manifest` under no lock. Nothing in the six ranks. **SSCAS.** `n/a`.
- **Idempotency.** Naturally idempotent — it is a state stamp, not a state transition. **`last_sync_at`
  advances monotonically** and `manifest_version` never moves backwards on a device row; a stale, out-of-order
  poll from a reconnecting device therefore **cannot roll a device's sync state backwards** and be read as
  fresher than it is. `p_device_boot_id` is recorded for C23 offline ordering and never used as authority.
- **Writes.** `venue.scan_device` (`manifest_version`, `last_sync_at`, `device_boot_id`).
  **No audit row** — a scanner polling every 30 seconds is not a privileged mutation, and §0.3's audit rule
  would fill `kernel.admin_audit` with a heartbeat.
- **Result.** `{ open bool, up_to_date bool, manifest_id, manifest_version, manifest_digest, not_after,
  max_delta_seq, deltas_available int }`.
- **Errors.** `insufficient_privilege` · `not_found` · `precondition_failed(device_retired |
  device_wrong_venue)`.
- **Forbidden callers.** A `venue_scanner` naming a device it does not hold; any client on the door path
  (the door never talks to PostgREST — it reaches the database only through the `door-session` edge
  function, §1.1d).
- **Test.** `T-RPC-STAFF-04` (a scanner syncing another venue's device raises; an out-of-order poll carrying
  a **lower** `p_known_manifest_version` does not lower the stored one).

### 20.5 COMPS AND GUEST LISTS — the `086` gap (`G-4`, `G-9`, `G-10`)

> **RLS §11.1 carries a fully argued split authority model for `allocate_comp` / `issue_comp` — R-15/E6/E7,
> C39 step-up gating, `venue_box_office` denied on one and permitted on the other — and this document
> contracted neither.** Dashboard §20A.1 lists them under *"mapped — write controls with a named RPC"*,
> which is **wrong**: the name exists, the contract does not. **That listing is not evidence and must not be
> taken as any** (a request to the dashboard owner is filed in §20.14).

#### 20.5.1 `venue.allocate_comp(p_session_id, p_batch_id, p_quantity, p_reason_code, p_command_key)` — **DB-RPC** (`G-4`)

- **Authority — the capacity half of the split.** `has_venue_role(venue, ['venue_manager'])` OR
  `kernel.has_org_role_over_venue(venue, ['org_owner','org_admin'])` — RLS §11.1 verbatim.
  **`venue_box_office` is DENIED**, and the reason is the whole point of the split: *"allocating comp
  **capacity** is an inventory decision"*, and O-2 grants box office issuance, not inventory.
- **C39-gated — and `AUTHZ-M8` gives the gate a threshold for the first time.** Above
  **`comp.per_staff_step_up_max_units`** the call requires **step-up** (`auth.jwt()->>'aal'` vs
  `authn.money_action_required_aal`, and `amr` freshness vs `authn.money_action_max_age_seconds`, **raising
  `step_up_unavailable` on an absent claim per `AUTHZ-M4`**) **and a live re-check of the grant** — the same
  predicate §17.7 specifies, enforced **in the function body, never in RLS**, because on the money plane every
  mutation is `EXECUTE` on a definer function and a table policy never runs (GP-3a). **Caller-authorized ⇒
  bound by EDGE-CALLER-JWT**, and this is a case where it bites: the step-up predicate reads `auth.jwt()`,
  which on a service-role client carries no `aal` and no `amr` at all.

  > **`AUTHZ-M8` — C39 has been cited in five documents as *"above the per-staff threshold"* and the threshold
  > has never had a key, a contract or a test.** A gate whose threshold does not exist is not a gate: an
  > implementer reads `config('…')` into NULL, compares `quantity > NULL`, gets NULL — **not true** — and
  > **no comp at any quantity requires step-up.** That is unmetered comp issuance by `venue_box_office`, the
  > most liberally granted of the new labels, on the capability the domain architecture names *"the
  > insider-fraud primitive"* (§7.5: *"un-stepped-up bulk comping"*). The traceability matrix already records
  > it as asserted by neither surface (`G-8b(i)`).
  >
  > - **Key: `comp.per_staff_step_up_max_units`** (integer, units of admission), with
  >   **`comp.per_staff_step_up_window_hours`** for the window. `catalog.platform_config`, seeded in `078`
  >   alongside the money thresholds.
  > - **The count is per ACTOR, per VENUE, per SESSION, within the window** — summing this actor's
  >   `comp.allocate` and `comp.issue` units. Per-staff is what C39 says, and it is what makes the control an
  >   insider-fraud control rather than a venue budget: a venue-wide cap is exhausted by legitimate volume and
  >   then either raised or ignored.
  > - **An unset or NULL key evaluates to ZERO, not unbounded** — `COALESCE(config, 0)` — so a missed seed row
  >   means *every comp requires step-up*, which is loud and recoverable, rather than *no comp ever does*,
  >   which is the defect and is silent. **Same rule as `AUTHZ-M3`'s support cap, stated at both sites
  >   deliberately: a fail-to-zero convention living in one place is a convention, not a control.**
  > - **`comp.*` therefore joins the dual-control config namespace** (RLS §11.3): raising the ceiling needs a
  >   second `platform_admin`; lowering it may execute directly.
- **Preconditions.** Session exists and is not terminal; `p_batch_id` is a batch of that session with
  `release_kind='comp'` — **a comp may not be allocated against a `public_sale` batch**, which is what keeps
  comps visible as comps in the ledger rather than laundered through paid inventory; `p_quantity > 0`;
  `p_reason_code` mandatory. **Comp draws real capacity (A4): it never bypasses the counter.**
- **Locks & acquisition order.** **Inventory batch `FOR UPDATE` (rank 2)** — or the sharded draw ascending
  `shard_no` with `SKIP LOCKED` + the single-shard last-unit fallback (C27) — then the
  `venue.comp_allocation` INSERT. **SSCAS.** `n/a (single-aggregate — Inventory)`: `venue.comp_allocation` is
  an Inventory-class child written under the batch lock this function already holds, the same classification
  §17.13 uses for a manifest delta written under the caller's session lock. **No sixteenth member.**
- **Idempotency.** `p_command_key`.
- **Writes.** `venue.inventory_batch(_shard)` (`held += q`, CHECK `held + sold <= capacity` →
  `oversell_rejected` on breach), `venue.inventory_movement` (`hold`, cause-keyed),
  `venue.comp_allocation` (INSERT `status='allocated'`), `kernel.admin_audit` (`comp.allocate`, with
  `quantity` and `reason_code`).
- **Result.** `{ status, comp_allocation_id, quantity, remaining }`.
- **Errors.** `insufficient_privilege(42501)` · `step_up_required` · `oversell_rejected` · `not_found` ·
  `precondition_failed(batch_not_comp_kind | session_terminal | reason_required)` · `idempotency_replay`.
- **Forbidden callers.** **`venue_box_office`** (the named denial), `venue_scanner`, the door session,
  `venue_finance`, `org_finance`, both marketing labels, both promoter-manager labels, promoters, fans,
  `anon`.
- **Tests.** `T-RPC-COMP-01` (`venue_box_office` is refused on allocate and permitted on issue — the split,
  asserted in both directions) · `T-RPC-COMP-02` (an allocation above the C39 threshold on a stale-`amr`
  token raises `step_up_required` and writes **nothing**, including no counter movement) ·
  **`T-RPC-AUTHZ-12`** (`AUTHZ-M8`: with `comp.per_staff_step_up_max_units` **deleted from
  `catalog.platform_config`** — the state a missed seed produces, not set to 0 — `allocate_comp` and
  `issue_comp` at `quantity = 1` both raise on a stale-`amr` token and move no counter) ·
  **`T-RPC-AUTHZ-13`** (the count is **per actor**: actor A at the threshold does not step-up actor B's first
  comp at the same venue and session).

#### 20.5.2 `venue.issue_comp(p_comp_allocation_id, p_grantee, p_quantity, p_command_key)` — **DB-RPC (calls SSCAS member #1's mint leg)** (`G-4`)

- **Authority — the issuance half.** `has_venue_role(venue, ['venue_manager','venue_box_office'])` OR
  `kernel.has_org_role_over_venue(venue, ['org_owner','org_admin'])` — RLS §11.1 verbatim. **C39-gated**, as
  §20.5.1. Issuing **one** comp against an **already-allocated** batch is an issuance operation, *"which is
  exactly what O-2 grants box office and nothing more."*
- **Params.** `p_comp_allocation_id`; `p_grantee` = `{ identity_id | name }` (schema §3.15 allows either —
  a comp for a guest with no account is `granted_to_name`); `p_quantity` (≤ the allocation's unissued
  remainder). All untrusted.
- **Preconditions.** Allocation exists, `status='allocated'`, and the requested quantity does not exceed what
  it has left. **The batch is not re-drawn**: capacity was consumed at allocate time, so issuance converts
  `held → sold` and **can never oversell**, which is why the box office may hold this half and not the other.
- **Locks & acquisition order (member #1's mint leg).** **Inventory batch(_shard) `FOR UPDATE` (rank 2)**
  (`held -= q; sold += q`) → **new Ticket Atoms (rank 5)** via `kernel.issue_ticket_atoms` with
  `cause='comp'` (§7.1 names `comp` in its cause set) → the `venue.comp_allocation` status update.
  **Strictly ascending — no inversion.**
- **SSCAS.** **Member #1 (Primary issuance), mint leg** — `venue.issue_comp` joins
  `venue.finalize_primary_order` as a **caller** of member #1, exactly as §7.1 already anticipates by naming
  `issue_comp` among `issue_ticket_atoms`'s callers. **§14.1 gains a caller, not a member. No sixteenth.**
- **Idempotency.** `p_command_key` **and** the ownership-log `UNIQUE(cause, cause_ref, ticket_atom_id)` with
  `cause_ref := comp_allocation_id` — so a replayed issue mints nothing further and returns the original
  atom set (C26 multiplicity: N atoms under one `cause_ref`).
- **A comp atom is a ticket atom in every respect that matters, and this contract says so once.** It is
  minted with `credential_version = 0`, an `active` signing key, `resale_state='none'`; it scans, transfers
  and refunds through the same engines. **It is not a second class of admission.** Where an open door-manifest
  episode exists, `kernel.issue_ticket_atoms` appends an `add` delta (§17.13) so an offline scanner admits it
  — the box-office-after-doors case §6.3 already covers, and comps are its most common instance.
- **Writes.** `venue.inventory_batch(_shard)`, `venue.inventory_movement` (`issue`),
  `kernel.tickets` + `kernel.ticket_ownership_log` (N rows, `cause='comp'`) **via `kernel.issue_ticket_atoms`
  only** — never directly (§0.7), `venue.comp_allocation` (→ `issued` when fully drawn),
  `venue.door_manifest_delta` (`add`, where an episode is open), `kernel.admin_audit` (`comp.issue`).
- **Result.** `{ status, atom_ids[], comp_status }`.
- **Errors.** `insufficient_privilege` · `step_up_required` · `not_found` ·
  `precondition_failed(allocation_exhausted | allocation_revoked)` · `idempotency_replay`.
- **Forbidden callers.** `venue_scanner`, the door session, `venue_finance`, `org_finance`, both marketing
  labels, both promoter-manager labels, promoters, fans, `anon`.
- **Per-staff comp totals stay visible to `venue_manager` and above** (RLS §11.1) — *"this is the
  insider-fraud control surface and hiding it defeats it."* The read is `venue.read_operational_audit`
  (§17.26) filtered on `comp.allocate`/`comp.issue`, which is why those two audit actions carry `quantity` in
  the payload and are **not** members of the security plane that read excludes.
- **Test.** `T-RPC-COMP-03` (a comp atom scans, transfers and refunds identically to a purchased atom;
  replaying `issue_comp` with the same command key mints no second atom).

#### 20.5.3 `venue.create_guest_list(p_session_id, p_name, p_command_key)` — **DB-RPC** (`U-1`, `G-10`)

- **Authority.** **RLS §9.16's matrix, not §11** — `org_owner`/`org_admin` (own org) and `venue_manager`
  (own venue) hold `EXEC: guest-list RPCs`. **§11 carries no row for any of the four functions in §20.5.3–
  §20.5.6**; the authority is real and lives in §9.16, and the missing §11 rows are filed in §20.14 as a
  reverse-direction defect.
- **Preconditions.** Session exists, not terminal; `p_name` non-empty and unique per session.
- **Locks.** None cross-aggregate (INSERT). **Admin plane** — a guest list draws **no capacity**: schema
  §3.16 is explicit that conversion to admission happens *"only via the named hold function"*, so a guest
  list is a roster, not inventory, and cannot oversell a room by existing. **SSCAS.** `n/a`.
- **Idempotency.** `p_command_key`. **Writes.** `venue.guest_list`; `kernel.admin_audit`
  (`guest_list.create`).
- **Result.** `{ status, guest_list_id }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `precondition_failed(session_terminal | name_taken)`.
- **Forbidden callers.** `venue_scanner` (it checks guests **in**, §20.5.6, and creates nothing),
  `venue_box_office`, `org_finance`, `venue_finance`, both promoter labels, fans, `anon`.

#### 20.5.4 `venue.upsert_guest_entry(p_guest_list_id, p_entry_id, p_guest_name, p_party_size, p_command_key)` — **DB-RPC** (`U-1`, `G-10`)

- **Authority.** As §20.5.3 (RLS §9.16: `INS`/`UPD` = `R`, RPC-only).
- **One function for add and edit, deliberately.** `p_entry_id` NULL ⇒ insert; non-NULL ⇒ update that entry's
  `guest_name`/`party_size`. A door list is edited constantly up to and past doors, and two functions would
  duplicate the same authority and the same guards.
- **`status` and `checked_in_at` are NOT writable here** — they belong to §20.5.6, whose authority set is
  strictly wider (it includes `venue_scanner`) and whose write is strictly narrower. **A management RPC that
  could also set `arrived` would hand the manager path a door capability and, worse, would let a check-in be
  silently undone by an edit.** `invalid_input` on either key.
- **Preconditions.** List exists; `p_party_size >= 1`; entry (when named) belongs to that list. **An entry may
  be edited after doors open** — names are corrected at the door constantly — **but not once
  `status <> 'pending'`**, which makes an arrival record immutable in the same way an issued order item is
  (`precondition_failed('entry_checked_in')`).
- **Locks.** The `venue.guest_list` row `FOR UPDATE` (admin plane) to serialise concurrent edits, then the
  entry. **SSCAS.** `n/a`. **Idempotency.** `p_command_key`.
- **Writes.** `venue.guest_entry`; `kernel.admin_audit` (`guest_entry.upsert`).
- **Result.** `{ status, entry_id }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `invalid_input(unwritable_key)` · `precondition_failed(entry_checked_in | bad_party_size)`.

#### 20.5.5 `venue.remove_guest_entry(p_entry_id, p_reason_code, p_command_key)` — **DB-RPC** (`U-1`, `G-10`)

- **Authority.** As §20.5.3. RLS §9.16 marks `DEL` **`D` for every client role** with note 38: *"`guest_entry`
  rows are removed only via the parent guest-list RPC cascade, never client DELETE (GP-2)."*
- **This is the RPC that note 38 points at, and it is a real DELETE inside the definer** — the schema's
  `guest_entry.guest_list_id … on delete cascade` is the mechanism, and §0.5's no-DELETE rule (GP-2) is
  satisfied the same way it is for `kernel.clear_my_demographics`: **the client holds zero DELETE**, and the
  audit row carries the removed entry. **This is a second named GP-2 exception and it is granted narrowly, on
  the same reasoning as the first:** a guest list references no ledger, draws no capacity, and moves no
  custody, so a tombstoned "removed guest" row would be a permanent record of somebody who was struck from a
  door list — which is exactly what removing them was meant to prevent. **It is not a precedent for any
  object that references money, custody or inventory.**
- **Preconditions.** Entry `status='pending'` — **a checked-in guest cannot be removed**
  (`precondition_failed('entry_checked_in')`): the arrival is evidence, and deleting it would erase an
  admission record. `p_reason_code` mandatory.
- **Locks.** The parent `venue.guest_list` row `FOR UPDATE`, then the entry. **SSCAS.** `n/a`.
  **Idempotency.** `p_command_key`; an already-absent entry is `noop_replay`, never `not_found`.
- **Writes.** DELETE one `venue.guest_entry`; `kernel.admin_audit` (`guest_entry.remove`, **`before` carries
  the full removed row**, `reason_code`).
- **Result.** `{ status }`. **Errors.** `insufficient_privilege` · `precondition_failed(entry_checked_in |
  reason_required)`.
- **Test.** `T-RPC-GUEST-01` (a checked-in entry cannot be removed or edited; the removal audit row carries
  the removed guest's name; **no client role holds table DELETE on `venue.guest_entry`**, asserted as
  `anon`, `authenticated` and every named role).

#### 20.5.6 `venue.check_in_guest_entry(p_entry_id, p_session_id, p_outcome, p_command_key)` — **DB-RPC** (`U-2`, `G-9`)

> **A door hits this a thousand times a night, and RLS grants exactly this narrow update — to a function that
> did not exist.** RLS §9.16 note 39: *"door updates only `status`/`checked_in_at` on entries for its
> session."* Dashboard `U-2`: *"the single most-used control at a door and it has no contract."*

- **Signature.** `venue.check_in_guest_entry(p_entry_id uuid, p_session_id uuid, p_outcome text,
  p_command_key text)`, `p_outcome ∈ {arrived, no_show}`.
- **Authority — the dual path, matching `record_scan`'s exactly.** (a) an authenticated `venue_scanner` or
  `venue_manager` for the session's venue; **or** (b) the `service_role` **edge** path with
  `kernel.assert_door_session(device_id, p_session_id, door_session_id, token)` asserted in-body. §1.1d names *"guest-entry check-in
  (`status` + `checked_in_at` only) for its session"* as **one of the four capabilities a door session
  authorizes** — so branch (b) is not an extension of the door credential, it is the function the existing
  grant was written for. `org_owner`/`org_admin` and `venue_manager` also hold it through §9.16.
- **The write is exactly two columns, and that narrowness is the grant.** `status` and `checked_in_at`.
  **Nothing else** — not `guest_name`, not `party_size`, not `guest_list_id`. **`T-RPC-GUEST-02`
  (structural):** the function's definition writes no `venue.guest_entry` column outside that pair, so a door
  credential can never be widened into a roster-editing capability by a later edit.
- **Preconditions.** Entry exists and its `guest_list.event_session_id = p_session_id` — **an entry from
  another session is refused even for an authorized principal**, which is what confines a door session to its
  own room; **session `status='live'`**, the same gate `record_scan` uses (§9.4) and, per `T-RPC-DOOR-04`,
  the only thing that stops admission.
- **Locks.** The `venue.guest_entry` row `FOR UPDATE` (admin plane; a guest entry is not a ticket atom and
  takes no rank-5 lock). **SSCAS.** `n/a (single-aggregate)`.
- **Idempotency — first-arrival-wins, mirroring C41.** `status='pending' → p_outcome` sets `checked_in_at :=
  now()` (server-derived; **no client timestamp is ever accepted**). A second `arrived` on an
  already-`arrived` entry returns `{ status:'noop_replay', already: true, checked_in_at }` — **the original
  timestamp, never overwritten** — and is **not an error**, because a door tapping twice is normal and an
  error toast at a door is a queue. `arrived → no_show` raises `precondition_failed('already_arrived')`: an
  arrival cannot be un-done by the door, only by a manager, and **Phase 2 builds no such reversal** (a
  mis-tapped arrival is a support note, not a state machine).
- **Writes.** `venue.guest_entry` (`status`, `checked_in_at`). **No `kernel.admin_audit` row** — a
  thousand-per-night door tap is not a privileged mutation and §0.3 does not reach it; the guest entry's own
  `checked_in_at` **is** the record, and `venue.read_operational_audit` (§17.26) would be unreadable if every
  arrival landed in it.
- **A guest check-in is NOT an admission and writes no custody.** It appends **no** `venue.scan` row, moves
  **no** `kernel.tickets` state, and returns **no** capacity. Where a guest-list entry is converted into a
  real admission, that happens through the **named hold function** (schema §3.16, A4/A11) → `issue_comp`
  (§20.5.2) → `kernel.issue_ticket_atoms`, and the atom is scanned normally. **Two ledgers, and they must not
  be conflated:** `venue.scan` is the admission ledger for ticket atoms; `venue.guest_entry.status` is a
  roster mark.
- **Result.** `{ status, entry_id, entry_status, checked_in_at, already bool }`.
- **Errors.** `insufficient_privilege(42501)` · `not_found` · `precondition_failed(wrong_session |
  session_not_live | already_arrived)`.
- **Forbidden callers.** `venue_box_office` (it issues comps, §20.5.2; it does not work the guest list — RLS
  §9.16 gives it no row), every finance/marketing/promoter label, `org_member`, fans, `anon`, and **any door
  session naming an entry outside its own session**.

### 20.6 DOOR READS, SWEEPS, AND THE `set_door_open_at` CONTRADICTION

#### 20.6.1 `venue.get_door_manifest(p_session_id, p_since_delta_seq)` — **DB-RPC (read)** · `NEW RPC` (`G-15`)

**The read that delivers the offline admissible set to every scanner**, wrapped by both the `door-manifest`
and `door-session` edge functions, with an EXEC row and no statement of its parameters, its result shape or
its digest.

- **Authority — the dual path, RLS §11.4 verbatim.** `has_venue_role(venue, ['venue_scanner',
  'venue_manager'])` **OR** the `service_role` edge path with `kernel.assert_door_session` **bound to that
  session**. Org owner/admin reach it through `has_org_role_over_venue`. **`venue_box_office`,
  `venue_finance`, `venue_marketing`, both promoter-manager labels, `org_finance`, `org_marketing`,
  promoters, fans and `anon` are denied** — the manifest is the list of everyone admissible tonight, which is
  an attendee-adjacent projection, and the roster read with its column scoping is `venue.list_attendees`
  (§17.22), not this.
- **Reads.** `venue.door_manifest` (the `open` episode for the session), `venue.door_manifest_entry` (the
  base snapshot), `venue.door_manifest_delta` (`seq > p_since_delta_seq`).
  **Writes: none. Locks: none.** It takes **no** `FOR SHARE` on the session row: it is a read of an
  append-only ledger whose head is already stamped, and taking rank 1 here would put a
  thousand-poll-per-night read in contention with the twice-a-night `FOR UPDATE` of
  `open_door_manifest`/`close_door_manifest`. **SSCAS.** `n/a`.
- **Result shape — `SPEC CORRECTION` (`MP-1`).** This contract and door §7.5 described **two different wire
  shapes for one function**, and **neither could evaluate `OFFLINE-VERIFY-v1`** (edge §5.4.3). The shape here
  omitted `ticket_state` (conjunct 3b.iv dead), omitted `session_id` (conjunct 3 and the no-M2 clause have no
  input), and its delta row omitted `signing_key_id` (conjunct 3c dead for **every atom supplemented after
  doors open** — contradicting the CHECK door §10.3a added for precisely that reason). Door §7.5's shape
  omitted `resale_state` (conjunct 3b.v dead, which is H-2 in the admitting direction). **One reconciled
  shape, stated identically here and in door §7.5:**

  ```
  { open, manifest_id, manifest_version, session_id, opened_at, not_after,
    manifest_digest, max_delta_seq, entries[], deltas[] }

  entry              := { ticket_atom_id, serial_no, ticket_type_id,
                          credential_version, signing_key_id, ticket_state, resale_state }
  delta(op='add')    := { seq, ticket_atom_id, op } ∪ entry    -- the FULL entry payload
  delta(op='revoke') := { seq, ticket_atom_id, op }             -- membership removal needs nothing more
  ```

  **The delta rule is op-conditional on purpose, and it is the database's rule, not this contract's.** Door
  §10.3a CHECKs `(op='add') = (credential_version IS NOT NULL)`, `(op='add') ⇒ signing_key_id IS NOT NULL`,
  `⇒ credential_version = 0`, `⇒ ticket_state = 'active'`, `⇒ resale_state = 'none'`, and requires
  `serial_no`/`ticket_type_id` on `add` — with all six NULL on `revoke`. This projection is therefore a
  straight column read in both branches; it synthesizes no constant, which is what stops the wire and the
  table from drifting apart a second time. **`serial_no` and `ticket_type_id` are not predicate inputs** —
  they are operator-facing, and they are required on `add` so the delta row is *exactly* the entry
  projection, which is what makes door §7.5a checkable by column-list comparison rather than by reading.

  **`session_id` is load-bearing.** Conjunct 3 binds the token to *"the device's bound scanning session"* and
  the no-offline-authority clause refuses *"an M2 for another session"* — undeterminable from a manifest that
  never says which session it is for. `T-RPC-DOOR-18` already asserts a **door session** bound to a different
  session is refused; that is the *authority* check, and it is not the same as the device being able to tell
  that a **cached** M2 belongs to a different session, which is what the block requires and what this field
  supplies.

  **`p_since_delta_seq` NULL ⇒ full snapshot + all deltas; non-NULL ⇒ deltas only**, which is the cheap poll
  a reconnecting scanner makes. **The parameter is `p_since_delta_seq`** — door §7.5 said `p_since_version`
  and door §7.7/§15 said `p_since_seq`; the first names the wrong quantity (`manifest_version` counts
  *episodes*, `seq` counts *deltas within* an episode), so a device passing one where the other is expected
  re-downloads or skips silently. Door §7.5 and §7.7 now carry this spelling.
- **The manifest carries NO identity column, by construction.** Schema `086`: `door_manifest_entry` and
  `door_manifest_delta` *"carry no identity column by construction"* — **no holder id, no name, no email, no
  order reference.** A scanner needs to know *which credential is admissible*, never *who holds it*, and a
  lost tablet is therefore not an attendee-list breach. **`T-RPC-DOOR-17` (structural):** the result's column
  list contains no identity-bearing column, asserted by column-list comparison rather than inspection.
- **`manifest_digest` is what makes an offline snapshot verifiable**, and this contract fixes its meaning:
  a hash over the **ordered entry set plus `manifest_version` plus `not_after`**, computed **inside the open
  transaction** (§17.10) and stored on the episode. `get_door_manifest` **returns the stored digest and never
  recomputes one** — a recomputed digest would silently agree with whatever the read happened to see, which
  defeats the purpose. A device compares the digest it downloaded against the digest it re-fetches to know
  whether its cached snapshot is still the one the server issued.
- **`not_after` is the offline authority bound, and it is not extendable retroactively.** §17.11 states the
  residual plainly: *"setting `not_after := now()` server-side does not shorten the `not_after` the device
  already downloaded. The bound is that downloaded TTL and nothing more. Do not describe this residual as
  closed by the re-sync requirement — it is not."* This read is where the value reaches the device, so the
  residual is restated here rather than left to be rediscovered.
- **No open episode ⇒ `{ open: false, status: 'no_open_manifest' }` with empty `entries[]`/`deltas[]`, not an
  error** — a scanner polling before doors is the normal case. **Both keys, `SPEC CORRECTION` (`MP-1`):** this
  contract returned only the boolean and door §7.5 returned only `{status:'no_open_manifest'}`, while door
  §11.2 and RN §7 branch on the **label** and §20.4.4 branches on the **boolean**. Returning either one alone
  breaks whichever consumer reads the other, so both are returned and neither consumer changes.
- **Errors.** `insufficient_privilege(42501)` · `not_found` (unknown session).
- **Test.** `T-RPC-DOOR-17` (above) · `T-RPC-DOOR-18` (a `venue_box_office` and a door session bound to a
  **different** session are both refused; a delta-only poll returns no entries and the same digest) ·
  **`T-RPC-DOOR-33` (structural — the `MP-1` acceptance property).** Every field named in the
  `OFFLINE-VERIFY-v1` predicate appears in this result's **entry** projection, and every such field appears
  in its **`op='add'` delta** projection — asserted by **column-list comparison**, never by inspecting a
  returned row, because the defect is a missing column and a sampled row proves only that one atom was
  populated. Paired with **`T-RPC-DOOR-34`**, which derives the compared read set by parsing the fenced block
  for `M2[atom].<field>` rather than hard-coding it here, and fails if that parse yields fewer than five
  distinct per-atom fields — otherwise a sixth conjunct added to the predicate leaves `-33` green against a
  stale list, which is a gate checking a copy of the requirement instead of the requirement. Door §15
  assertions **77–83** are the DB-level half of the same property; these two are the contract-level half, and
  **both are required** — the door spec's group asserts over the tables, this one over what the function
  returns, and `MP-1` was a defect in the second with the first already correct.

#### 20.6.2 `catalog.sweep_implicit_door_freezes(p_limit)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (`G-21`)

- **Authority.** **`EXEC: DEF`**, cron — RLS §11.4 verbatim, paired there with
  `kernel.sweep_expired_door_overrides` (§17.11) under one note: *"**Neither is load-bearing for
  correctness**; the helper computes the boundary arithmetically whether or not either ever runs."*
- **What it does.** For sessions whose `catalog.effective_freeze_at` has passed by the implicit backstop
  (`COALESCE(doors_at, starts_at) + config('door.implicit_freeze_offset_interval')`) while `door_open_at` is
  still NULL — i.e. **nobody ever opened a manifest** — it emits the operator notification and closes the
  audit trail (`door.implicit_freeze_engaged`). **It does not write `catalog.event_session`.**
- **It must NOT call `catalog.engage_door_freeze`, and this is the single thing an implementer will get
  wrong.** Setting `door_open_at` from a sweep would make it **non-equal to `MIN(venue.door_manifest.
  opened_at)`** over an empty episode set, which the `catalog.tg_door_open_at_is_ledger_head` trigger (`086`)
  raises on — and it would convert the *cached monotone head of an append-only ledger* into a value a cron
  invented. §12.4a's whole point is that *"cannot move backwards stops being a rule someone has to remember
  and becomes arithmetic."* **`T-RPC-DOOR-19` (structural):** this function's definition references neither
  `engage_door_freeze` nor `door_open_at`.
- **Locks.** None — it reads `catalog.event_session` and `venue.door_manifest` and writes only audit and
  notification rows. **SSCAS.** `n/a`. **Idempotency.** A per-session marker (the audit action + session id)
  makes a re-run emit nothing further.
- **Result.** `{ swept }`. **Errors.** None expected.
- **Not load-bearing, and the corpus's own reason.** `kernel.is_transfer_frozen` evaluates
  `now() >= catalog.effective_freeze_at(session)` **arithmetically, on every call** (§12.4a), and
  `effective_freeze_at` is **total** — there is no input for which it returns NULL. So the freeze engages
  whether or not this sweep ever runs; the sweep only tells a human it happened. **`T-RPC-DOOR-20`:** past
  the implicit backstop, `is_transfer_frozen` returns true **with no sweep having run** — the same assertion
  shape as `T-RPC-DOOR-13`.
- **Forbidden callers.** Every client, every human role.

#### 20.6.3 `venue.preview_door_open_impact(p_session_id)` — **DB-RPC (read)** · `NEW RPC` (`U-5` / Δ11, `G-16`)

> **The most consequential door control in the product asks for a confirmation the operator cannot
> evaluate.** Dashboard §12.4 requires the confirm dialog to show what the drain will cancel **before** the
> confirm enables; `venue.open_door_manifest` returns `drained_transfers` / `drained_listings` **after** it
> commits. Principle 7 is unsatisfiable without this read.

- **Authority.** `PROPOSED AUTHORITY` — RLS §11 is silent. Proposed: **byte-identical to
  `venue.open_door_manifest`** (§17.10 / RLS §11.4) — `has_venue_role(venue, ['venue_manager'])` OR
  `has_org_role_over_venue(venue, ['org_owner','org_admin'])` OR `is_platform(['platform_admin'])`, with
  `venue_scanner`, any door session, `venue_box_office`, every finance/marketing/promoter role,
  `platform_support` and `platform_risk` denied (O-4). **A dry run of an action must not be visible to
  anyone who could not perform the action** — the counts are a live picture of who is mid-transfer in that
  room tonight, and a wider grant would make the preview an intelligence surface the open is not.
- **Returns exactly what the confirm must show, and nothing that would let it be used as a list.**
  `{ pending_transfers int, active_listings int, excluded_paid_pending int, atoms_to_unlock int,
   freeze_would_newly_engage bool, effective_freeze_at, override_active bool, live_device_count int }`.
  **Counts only — no atom ids, no seller ids, no buyer ids, no listing ids.** The same reasoning
  §17.24 applies to `notify.preview_announcement_audience` (*"returns a COUNT only, never an enumeration"*):
  a preview that enumerates is an enumeration primitive wearing a preview's name.
- **`excluded_paid_pending` is separated deliberately**, because it is the one number that explains a
  discrepancy the operator will otherwise see: a listing whose sale is `paid_pending_transfer` is **not**
  drained (§12.4c, `T-RPC-DOOR-12`) — the C25 sweep owns that row — so the count the preview shows and the
  count the open reports must be reconcilable, and this field is how.
- **Advisory, and it says so.** The numbers are read without locks and **may change between the preview and
  the open** — a transfer accepted in the intervening seconds is drained and was never previewed. **The
  client must never persist the preview as the answer**, the same caveat §17.16 attaches to
  `preview_promoter_code`. The open's own returned counts are authoritative.
- **Writes: none. Locks: none** (a `FOR SHARE` here would put a dialog render in contention with the open).
  **SSCAS.** `n/a`.
- **Errors.** `insufficient_privilege(42501)` · `not_found` · `precondition_failed(session_terminal)`.
- **Test.** `T-RPC-DOOR-21` (the preview's `pending_transfers + active_listings` equals the open's
  `drained_transfers + drained_listings` when nothing changes in between; a `paid_pending_transfer` listing
  appears in `excluded_paid_pending` and in neither drained count; every principal O-4 denies is refused).

#### 20.6.4 `venue.get_live_device_count(p_session_id)` — **DB-RPC (read)** · `NEW RPC` (`U-6` / Δ12, `G-17`)

- **Authority.** `PROPOSED AUTHORITY` — RLS §11 is silent. Proposed: as §20.6.3, **plus
  `is_platform(['platform_admin'])` unconditionally** — it is the number a `platform_admin` is required to
  acknowledge before a break-glass override, so denying them the read would make
  `kernel.grant_door_freeze_override`'s `p_ack_live_devices` precondition unsatisfiable.
- **Definition, and it must match the override's predicate exactly or the acknowledgement is theatre.**
  The count of `venue.scan_device` rows with `status='active'` that are **still inside the `not_after` of the
  manifest they last downloaded** — §17.11's *"the current count of devices still inside their downloaded
  `not_after`"*. **Not** "devices that pinged recently", **not** "devices registered to the venue".
  `T-RPC-DOOR-22` asserts the two predicates are the same expression, because a preview that counts one
  population while the guard counts another is worse than no preview: the admin types a number that means
  nothing and the speed bump is removed.
- **A second number, added by `AUTHZ-H3`: `live_sessions`, read from `venue.door_session`.** The manifest
  count above is the **override's** predicate and does not change. But the operator's *"who is live at this
  door"* question is now answerable from a **fact** — `venue.door_session` rows with `status='active' AND
  expires_at > now()` for the session — where before it could only be answered from
  `scan_device.last_sync_at`, **which reports a poll and not a presence**: a tablet that has been switched
  off for an hour still shows its last sync. The two numbers legitimately differ (a device can hold a live
  session and a lapsed manifest, or the reverse), and **both are returned rather than reconciled**, because
  collapsing them would put the override's acknowledgement back on a population it does not guard.
  The projection is the **non-secret** one only (RLS §16.4a): `door_session_id`, `device_id`,
  `event_session_id`, `issued_at`, `expires_at`, `status`, `last_seen_at`. **`token_hash` is returned by no
  RPC, to no role.**
- **Returns.** `{ live_devices int, live_sessions int, as_of, stalest_not_after }`. `stalest_not_after` is
  included because it is the answer to the operator's actual next question — *"how long until this is
  zero?"* — and it costs the same query.
- **Writes: none. Locks: none. SSCAS: n/a.**
- **Errors.** `insufficient_privilege` · `not_found`.
- **Test.** `T-RPC-DOOR-29` — a device whose PIN was revoked (RV-1) or whose row was retired (RV-2) drops out
  of `live_sessions` **in the same transaction as the revoke**, while `live_devices` may still count its
  un-lapsed manifest. **Asserted as a difference**, because a test that only checks both fall to zero would
  pass on an implementation that conflated them.

#### 20.6.5 **`venue.set_door_open_at` — RESOLUTION: it does not exist** (`G-14`)

RLS §11.4 grants EXECUTE on **`venue.set_door_open_at` (O4-3)** to `venue_manager` / org owner-admin /
`platform_admin`. Ruling **O-5** makes **`catalog.engage_door_freeze` the sole writer** of
`catalog.event_session.door_open_at` (§17.12: *"Never client-callable and it appears in NO RLS EXEC row.
A trigger enforces the single-writer property independently of grants"*). **Both cannot be true.** The
traceability matrix states the fork exactly: *"Either the EXEC row is stale or O-5's sole-writer property is
false."*

**Ruling: the EXEC row is stale. `venue.set_door_open_at` is not built, in either grant class.** Three
independent reasons, any one of which is sufficient:

1. **As a caller-authorized function it is unimplementable.** `catalog.tg_door_open_at_is_ledger_head`
   (created in `086`, attached to `catalog.event_session`) raises unless `door_open_at =
   MIN(venue.door_manifest.opened_at)` — and it may never be cleared and never moved once set (plan `086`
   Tests: *"three separate raises"*). A function granted to a human could therefore only ever succeed by
   **first inserting a manifest episode** — which is `venue.open_door_manifest` (§17.10), already contracted,
   already carrying the drain, the snapshot and the atomicity that make the boundary safe. The remaining
   behaviour is a function that always raises.
2. **As a definer-only function it is redundant and it destroys the property it would implement.**
   `catalog.engage_door_freeze` **is** the definer-only writer. A second one gives a *sole-writer* property
   two writers, which is a contradiction in terms — and the sole-writer property is what §12.4a leans on to
   make *"cannot move backwards"* **arithmetic rather than a rule someone has to remember.** Two writers puts
   it back to being a rule.
3. **The RLS row's grant class refutes the reading that would save it.** §11.4 grants it to three **human**
   role classes, not `DEF`. Whatever O4-3 intended, it did not intend a definer primitive.

**The capability O4-3 was reaching for is real, and it is re-homed rather than dropped.** What an operator
legitimately needs is not *"set the boundary"* — the boundary is taken by opening the door — but *"correct
the published door time for a session whose doors moved."* That is `doors_at`, a **schedule** column, and it
is a different column from `door_open_at`, the **boundary head**. **The EXEC row conflated a schedule with a
ledger head.** It is contracted as:

**`catalog.set_session_door_schedule(p_session_id, p_doors_at, p_reason_code, p_command_key)` — DB-RPC**

- **Authority.** The O4-3 row's own allow-list, inherited unchanged: `has_venue_role(venue,
  ['venue_manager'])` OR `has_org_role_over_venue(venue, ['org_owner','org_admin'])` OR
  `is_platform(['platform_admin'])`, with every O-4 exclusion intact.
- **Writes `catalog.event_session.doors_at`. It never references `door_open_at`** — `T-RPC-DOOR-23`
  (structural), the same shape as `T-RPC-DOOR-01`, so a future engineer who *"seemed safer"* their way back
  to writing the head fails CI rather than failing at the door.
- **Guards, which are §20.2.4's and are custody properties, not validation.** `doors_at` is an input to
  `catalog.effective_freeze_at`, so: freely movable while no atom exists for the session; movable **earlier
  freely and later only within `config('door.schedule_move_grace_interval')`** once atoms exist, audited with
  a mandatory reason code — moving it later pushes the implicit backstop later, which re-opens the
  live-door/open-transfer overlap C6 exists to close; and **frozen entirely once `door_open_at IS NOT NULL`**
  (`precondition_failed('boundary_engaged')`) — once the boundary is taken, the schedule that produced it is
  evidence.
- **Locks.** `catalog.event_session` `FOR UPDATE` (rank 1). **SSCAS.** `n/a`. **Idempotency.**
  `p_command_key`. **Writes.** `catalog.event_session.doors_at`; `kernel.admin_audit`
  (`session.door_schedule.change`, before/after, `reason_code`).
- **Result.** `{ status, session_id, doors_at, effective_freeze_at }` — **the recomputed boundary is
  returned**, so the operator sees the consequence in the same round trip.
- **Errors.** `insufficient_privilege` · `not_found` · `precondition_failed(boundary_engaged |
  move_exceeds_grace | reason_required)`.

**Filed for the RLS integrator (§20.14) — and now DISCHARGED (`AUTHZ-R1`).** RLS §11.4's
`venue.set_door_open_at` row has been **replaced** by `catalog.set_session_door_schedule` with the same
allow-list, carrying the schedule-vs-ledger-head reasoning at the row itself. The two documents now agree, and
`catalog.engage_door_freeze` is the sole writer of `door_open_at` in the authority table as well as in the
trigger.

#### 20.6.6 `venue.set_event_security_config(p_event_id, p_overrides, p_reason_code, p_command_key)` — **DB-RPC** (`G-14`) — **⛔ BLOCKED (schema §13.7 `S-13`)**

> **⛔ BLOCKED — NOT BUILDABLE, AND THE BLOCK IS SEPARATE FROM THE KEY-SET QUESTION.**
> **The `Writes` line below says "the per-event door-config rows" and no such table exists in any package.**
> The schema pass (§13.7 `S-13`) swept every package for it and found nothing: there is no
> `catalog.event_security_config`, no per-event override table, and no column on `catalog.event` or
> `catalog.event_session` that could hold a versioned key/value override. **A function scheduled in `086`
> with nowhere to write is unbuildable regardless of which keys it accepts** — the `R-11` key-set flag was
> already open, and this is a second, independent block underneath it.
>
> **This document does not invent the table**, and the schema pass explicitly declined to as well: *"the
> function's existence is not this spec's to decide."* The two exits, both owner rulings, are stated so the
> decision is made once rather than at build time:
>
> | Exit | What it costs | What it implies here |
> |---|---|---|
> | **(a) Schedule `catalog.event_security_config`** into `078` — `(event_id, key, value, version, effective_from)`, AO per version, exactly like `catalog.platform_config`, and **`visibility='restricted'` by §2.4.1 since it overrides `door.*`** | one additive table in an already-scheduled package | the contract below stands as written, its `INFERENCE` key-set flag (`R-11`) still open, and `BLOCKED` lifts |
> | **(b) Rule the function out**, as `venue.set_door_open_at` was ruled out (`AUTHZ-R1`, §11.4) | the O4-4 capability is dropped; nothing else in the corpus depends on it | this section is deleted, RLS §11.4's O4-4 EXEC row goes with it, and plan `086` never names it |
>
> **Until one of those is chosen, the contract below is a specification and not an instruction.** It is
> retained rather than deleted because deleting it would lose the safety direction (the one-way restriction
> rule) that whoever builds it must have — but **`086` must not schedule this function while it is
> `BLOCKED`**, and an implementer who reaches it should stop, not improvise a table.
>
> *Related and NOT the same question:* `R-11` asks the owner to confirm the **key set**. `S-13` asks whether
> the function exists at all. Answering `R-11` does not answer `S-13`.

- **Provenance, stated first because it is thin.** RLS §11.4 grants EXECUTE on this function under the O-4
  allow-list, and ROLE_MODEL §11 row 15 classifies it `NEW RPC — same boundary`. **No document in the corpus
  states what it configures.** The contract below is **`INFERENCE` — AUTHORED, not transcribed**, and is
  flagged in §19 accordingly. It is written so an implementer has a signature and a safety direction rather
  than a blank; **the owner should confirm the key set before it is built.**
- **Authority.** The O-4 allow-list verbatim: `has_venue_role(venue, ['venue_manager'])` OR
  `has_org_role_over_venue(venue, ['org_owner','org_admin'])` OR `is_platform(['platform_admin'])`;
  `venue_scanner`, any door session, `venue_box_office`, every finance/marketing/promoter role,
  `platform_support` and `platform_risk` denied.
- **What it configures: a closed set of per-event overrides of `door.*` platform config keys** —
  `door.manifest_ttl_interval`, `door.manifest_early_open_window`, `door.implicit_freeze_offset_interval`.
  A key outside that set raises `invalid_input`; **this function creates no key**, exactly as
  `catalog.set_platform_config` (§20.2.1) creates none.
- **The safety direction is one-way, and it is the whole design.** **An event override may only be more
  restrictive than the platform value, never less** — a shorter manifest TTL, a narrower early-open window, a
  shorter implicit-freeze offset. A loosening raises `precondition_failed('loosens_platform_floor')` and
  directs the caller to `catalog.set_platform_config`, where a `platform_admin` and a second approver decide.
  This is the same asymmetry RLS §11.4 states for the override roles (*"risk may **tighten**, never
  **loosen**"*) and §11.3 states for money thresholds, applied to the door plane so a venue cannot widen its
  own offline window.
- **The cross-config invariant survives the override and is re-asserted per event.** Plan `078` asserts
  `credential.wallet_default_span + credential.wallet_exp_skew <= door.manifest_ttl_interval` over the seeded
  values — *"a Wallet token may never outlive the offline window any manifest could authorise."* **A
  per-event TTL override can break that invariant**, so this function re-evaluates it against the effective
  event values and raises `precondition_failed('wallet_span_exceeds_manifest_ttl')` rather than storing a
  configuration in which a Wallet pass outlives every manifest the event can issue.
- **Locks.** The event's config row `FOR UPDATE` (admin plane). **SSCAS.** `n/a`. **Idempotency.**
  `p_command_key`; versioned per event, append-only, exactly like `catalog.platform_config` — **and for the
  same reason:** a manifest already issued under an old TTL must stay interpretable.
- **Writes.** The per-event door-config rows — **⛔ this is the blocked line: no such table exists in any
  package (`S-13`, above)**; `kernel.admin_audit` (`event.security_config.change`, before/after, mandatory
  `reason_code`).
- **Result.** `{ status, event_id, version, effective }` — `effective` is the **merged** platform+event view,
  so the operator sees what will actually apply rather than only what they typed.
- **Errors.** `insufficient_privilege` · `not_found` · `invalid_input(unknown_key)` ·
  `precondition_failed(loosens_platform_floor | wallet_span_exceeds_manifest_ttl | reason_required)`.
- **Test.** `T-RPC-DOOR-24` (a loosening override raises for every authorized role including
  `platform_admin`; an override that would let a Wallet pass outlive the manifest TTL raises).

### 20.7 MONEY AND KEYS — the `083` / `085` / `087` gap (`G-7`)

#### 20.7.1 `kernel.admin_refund(p_payment_id, p_atom_ids, p_amount_minor, p_reason_code, p_command_key)` — **EDGE-FRONTED (DB-RPC + Stripe refund)**

§11.4's closing note calls this *"the same DB shape as §11.4 … listed here as a sibling, not re-detailed."*
**A sibling is not a contract.** It has its own EXEC row, its own authority, its own freeze exemption and its
own delta obligation, and `refund-execute` (edge §3.5) wraps it. Written out here.

- **Authority.** `is_platform(['platform_risk','platform_admin'])` — RLS §11.1 verbatim. **`platform_support`
  is excluded**, which is the difference from §11.4: support holds a *capped* `refund_primary_order` reached
  only through `kernel.request_order_refund`; this is the **uncapped dispute instrument** and it sits one
  tier up. **Caller-authorized ⇒ bound by EDGE-CALLER-JWT**, and `refund-execute` must therefore build its
  client from the caller's `Authorization` header — a service-role invocation would make `is_platform` NULL
  and silently degrade the only gate on an uncapped refund.
- **Why it exists separately from `kernel.refund_primary_order` (§11.4), which an implementer will otherwise
  merge.** Three reachability differences, each load-bearing:
  1. **It is not order-scoped.** §11.4 refunds a `venue.order`; `admin_refund` refunds a **payment**, which
     is the only path that reaches a **native resale** (`market.market_sale`, whose money is a
     `kernel.payment_native` row with no `venue.order` behind it) and a fee-only or goodwill reversal.
  2. **It is the sanctioned destination for `custody_moved`.** §11.4 adds `custody_moved` to the failure
     taxonomy and rules that an atom whose `current_owner_id` is no longer the order's buyer *"becomes a
     platform dispute (`admin_refund`), not an org action."* **This is that function.** It may therefore
     refund a primary purchase whose atom has since been resold — and it **must not void that atom**, for
     §11.4's stated reason: the reseller already recovered their money and the current holder is a stranger
     to the dispute. `p_atom_ids` on such a payment is rejected with `custody_moved`; the money leg proceeds
     alone.
  3. **It is freeze-exempt.** §12.4c: `kernel.force_void_ticket` · `kernel.admin_refund` — *"exempt,
     audited"* — platform break-glass, *"residual is the C6 reconcile window."*
- **The exemption's mandatory obligation, which §12.4c binds and which is the easiest thing here to omit.**
  Because it may void an atom while a manifest episode is open, **every void it performs MUST write a
  `revoke` delta** via `venue.append_door_manifest_delta` (§17.13). *"Omitting it re-opens the offline
  revocation leak the exemptions were granted around."* **`T-RPC-MONEY-15`:** an `admin_refund` void on a
  session with an open episode appends exactly one `revoke` delta per voided atom.
- **The voidable/consumed partition applies unchanged** (§11.4). Atoms partition into `voidable`
  (`state ∈ {issued, active}`) and `consumed` (`state='scanned'`); a `consumed` atom is **never voided and
  never returns inventory** (the seat *was* consumed), **the money leg still completes**, and the result
  names the split — `{ atoms_voided[], atoms_not_voided[{atom_id, reason}] }`, **never a silent partial**.
  The audit row carries the consumed list so the goodwill-vs-collusion pattern stays queryable. **The
  `refund.scanned_atom_policy` config tier does not gate this function** — `platform_review` *is* the tier
  the caller already holds.
- **Params.** `p_payment_id` (→ `public.payments` or `kernel.payment_native`), `p_atom_ids uuid[]`
  (**may be empty** — a fee-only reversal), `p_amount_minor`, `p_reason_code ∈ {dispute, admin_action}`
  (RLS §11.3 rejects these codes from the org entry point; here they are the **only** legal values),
  `p_command_key`. All untrusted; **amount re-validated** under `FOR UPDATE` on the payment
  (`Σ refunds ≤ payment.total`).
- **Locks & acquisition order (SSCAS #3).** **Inventory (rank 2, before the atom — §14.2's NB, so no 5→2
  back-edge)** → **Ticket Atom(s) ascending `ticket_atom_id` (rank 5)** → **Refund/Payment (rank 6,
  `FOR UPDATE` on the payment for the sum guard)**. Ascending. **SSCAS: member #3 (Refund-void).**
  `admin_refund` joins `void_ticket_atom` / `refund_primary_order` / `force_void_ticket` as a **caller of
  member #3** — §14.1 gains a name in that row's RPC cell, **not a member.**
- **Idempotency.** `kernel.refund.idempotency_key` (deterministic, Phase-0 payout discipline) + the
  ownership-log `UNIQUE(refund_void, refund_id, atom)`. A retried edge call recovers the original refund.
- **Writes.** `kernel.refund` (INSERT — **`kernel.refund_primary_order` remains the sole writer of
  `kernel.refund` on the *order* path; this is the sole writer on the *dispute* path, and R7
  money-single-path holds because no request/approve object writes a money row on either**),
  `kernel.void_ticket_atom` per voidable atom, `venue.inventory_batch` (return), `market.market_sale`
  (→ `terminal_state='compensated'` via `market.on_atom_voided`, §20.11.3, where the payment is a native
  sale), `venue.door_manifest_delta` (`revoke`), `kernel.admin_audit` (`refund.admin`, before/after,
  consumed-atom list, mandatory `reason_code`).
- **Result.** `{ status, refund_id, atoms_voided[], atoms_not_voided[] }`.
- **Errors.** `insufficient_privilege(42501)` · `payment_unverified` · `custody_moved` ·
  `precondition_failed(over_refund | bad_reason_code)` · `not_found` · `idempotency_replay`.
- **Forbidden callers.** `platform_support`, **every org role including `org_owner` and `org_finance`**
  (they reach a refund only through `request_order_refund`), every venue role, fans, `anon`.
- **Tests.** `T-RPC-MONEY-15` (above) · `T-RPC-MONEY-16` (a refund on a payment whose atom has been resold
  completes the money leg, voids nothing, and returns `custody_moved` in `atoms_not_voided`) ·
  `T-RPC-MONEY-17` (`platform_support` is refused; `org_owner` is refused).

#### 20.7.2 `kernel.pay_promoter_commission(p_settlement_id, p_attribution_ids, p_command_key)` — **DB-RPC** · `EXEC: DEF`

- **Authority.** **`EXEC: DEF`** — RLS §11.1: *"definer (settlement path)"*. `REVOKE EXECUTE FROM anon,
  authenticated, public`; `GRANT EXECUTE TO service_role` only. **Called from `kernel.close_settlement`
  (§10.2) inside the closing transaction, and from nowhere else.** No human path, no actor.
- **What it is, in one sentence, because the name suggests something it is not.** It **records a
  `kernel.payout` row** with `cause='promoter_commission'`. **It moves no money.** The Stripe Connect
  transfer is executed by the payout edge fn (§13), reusing the frozen `source_transaction` funding and
  deterministic idempotency. A function named `pay_*` that writes a ledger row is exactly the kind of name
  that gets an external call added to it by a well-meaning engineer; **it must never perform external I/O**
  (§0.7), and `T-RPC-MONEY-18` asserts the DB-side of that by pinning its write set.
- **The double-payment guard is a database constraint, not this function's logic.** Migration `090` creates
  `CREATE UNIQUE INDEX ON venue.settlement_line (cause_ref) WHERE cause = 'promoter_commission'` — *"the
  constraint whose absence made double-payment possible"* (schema §3.14.1). **At most one commission line may
  ever exist per attribution, across every settlement.** This function relies on that index rather than
  re-deriving the check, so a concurrent second close is rejected by Postgres rather than by a race-prone
  `NOT EXISTS`.
- **The hold semantics it must honour (§17.18).** An unreviewed self-deal flag makes the commission
  **`payable = 0`, and that is a HOLD, not a forfeiture** — so this function **writes no line at all** for a
  flagged, unadjudicated attribution. *"A zero line would consume the one slot and permanently forfeit a
  commission that adjudication might later release."* **`T-RPC-MONEY-19` asserts the absence**, which is the
  only way to test a hold that is expressed as a missing row.
- **Preconditions.** Settlement is being closed in the calling transaction and is locked `FOR UPDATE` by the
  caller — **asserted, not assumed**; each attribution is in scope, `self_deal_flag = false` **or** its
  latest `venue.attribution_review` at `max(seq)` is `release`; the promoter's commercial terms resolve
  (`commission_kind='bps' ⇒ commission_bps`, `'flat_per_ticket' ⇒ commission_flat_minor` — the `090` XOR
  CHECK), and the **`terms_version` recorded on the attribution row governs**, not the promoter's current
  terms. *"The terms in force at settlement rather than at sale would govern the commission"* is the failure
  §6.3 rules out, and it is enforced here by reading the attribution's snapshot.
- **Locks & acquisition order.** **None of its own.** The caller holds **Settlement (rank 6)**; this function
  appends `venue.settlement_line` rows and inserts `kernel.payout` (rank 6, Payout after Settlement by the
  fixed sub-rank of §14.2). **SSCAS: member #5 (Attribution → commission), payout leg** — §14.1 already maps
  member #5 to `kernel.close_settlement`; this is the primitive that row's *"commission line"* refers to.
  **Attribution is READ, never locked** (§17.14), so *"C28's closed fifteen and its lock order stand
  unamended."* **No sixteenth member.**
- **Idempotency.** `kernel.payout.idempotency_key` deterministic on `(cause, cause_ref, payee)` (Phase-0
  discipline) **plus** the `090` partial unique. A replayed close recovers the same payout and inserts no
  second line.
- **Writes.** `venue.settlement_line` (AO, `cause='promoter_commission'`, `cause_ref = attribution_id`),
  `kernel.payout` (INSERT `pending`, `payee_identity_id` = the promoter, `cause='promoter_commission'`),
  `kernel.admin_audit` (`settlement.commission`).
- **Result.** `{ status, lines_written, payout_ids[], held[] }` — `held[]` names the attributions skipped for
  an unadjudicated flag, so the close's own result explains the arithmetic rather than leaving a silent gap.
- **Errors.** `precondition_failed(settlement_not_locked | terms_unresolvable)` · `conflict_locked` (the
  cross-settlement unique — a second attempt to line the same attribution).
- **Forbidden callers.** Every client, every human role, **including `org_finance` and `platform_admin`** —
  the only door to a commission payout is closing a settlement.
- **Tests.** `T-RPC-MONEY-18` (write-set pinned: it writes `settlement_line`, `payout` and `admin_audit` and
  **nothing else**, and performs no external call) · `T-RPC-MONEY-19` (a flagged, unreviewed attribution
  yields **no** settlement line, and a later `release` + close pays it) · `T-RPC-MONEY-20` (lining the same
  attribution into a second settlement is rejected by the index).

#### 20.7.3 `kernel.provision_signing_key(p_scope, p_scope_id, p_public_key, p_kms_handle_ref, p_not_before, p_reason_code, p_command_key)` — **EDGE-FRONTED** (`G-7`)

> **The C33 key lifecycle — the security linchpin of the whole credential design.** Every ticket credential in
> the system verifies against a key these three functions manage; §13 gives them one line and no contract.

- **Authority.** `is_platform(['platform_admin'])` — RLS §11.1 verbatim — **and dual-controlled**, on the
  same reasoning as §20.1.4: a key operation is at least as consequential as a platform-role grant, and
  RLS §11.7 already mandates dual control for the *Wallet* certificate trio, which is the strictly less
  consequential of the two credential surfaces. `INFERENCE:` §11.1 does not spell out dual control for the
  signing-key trio while §11.7 does for `pass_type_cert`. **Contracted with it, and flagged**, because the
  asymmetry reads as an omission rather than a decision: the pass certificate signs a wallet artifact, the
  signing key signs the admission credential itself.
- **`SPEC CORRECTION`/clarification — no private key material crosses this boundary, and the parameter list
  is what enforces it.** `p_public_key` is the **verify** key (safe to distribute — doors carry it);
  `p_kms_handle_ref` is an **opaque handle** to KMS. **There is no parameter through which a private key
  could be passed**, which makes C33 structural rather than a promise: an implementer cannot store a secret
  through this function even by mistake. The KMS keygen happens in the `signing-key-provision` edge fn
  (§13/edge §3.6) **before** this call, and this RPC records the references. **`T-RPC-KEY-01`:** no parameter
  and no column written accepts key material, asserted alongside the `083` CI scan that fails the build on
  any tracked `*.p12`/`*.p8`/`*.cer` or `BEGIN … PRIVATE KEY`.
- **Preconditions.** `p_scope ∈ {per_event, per_venue, global}` with scope/target coherence (schema §1.7:
  `per_event ⇒ event_id NOT NULL`, etc.); **no `active` key already exists for that scope target** — the
  partial `UNIQUE(event_id) WHERE status='active' AND scope='per_event'` (and its per-venue/global analogues)
  makes a second one impossible, so a duplicate provision surfaces as `conflict_locked` and the caller is
  directed to `rotate_signing_key`; `p_not_before` is not in the past by more than a clock-skew tolerance.
  **`scope='global'` additionally requires an explicit reason code naming the exception** — schema §1.7:
  *"global allowed but discouraged — a global key is an existential single point, R3."*
- **Locks.** The scope target's `kernel.signing_key` rows `FOR UPDATE` (admin plane, outside the six ranks)
  → the `kernel.approval_request` row (rank 5.5) on the parked path. **SSCAS.** `n/a (single-aggregate)`.
- **Idempotency.** `p_command_key`; a replay returns the provisioned `key_id`.
- **Writes.** `kernel.approval_request` (first call), `kernel.signing_key` (INSERT `active`, **on the second
  approver's approval only**), `kernel.admin_audit` (`signing_key.provision`, `subject_kind='signing_key'`,
  after = `{scope, target, kms_handle_ref}` — **never the public key blob**, which would make the audit table
  the largest object in the database for no investigative value).
- **Result.** `{ status, key_id, request_id }`. **Errors.** `insufficient_privilege` · `sod_violation` ·
  `conflict_locked` (active key exists) · `precondition_failed(scope_incoherent | global_requires_reason)`.
- **Forbidden callers.** `platform_support`, `platform_risk`, **every org and venue role**, fans, `anon`, and
  every `service_role` path — as with §20.1.4, no `DEF` door exists at all.

#### 20.7.4 `kernel.rotate_signing_key(p_old_key_id, p_public_key, p_kms_handle_ref, p_reason_code, p_command_key)` — **EDGE-FRONTED** (`G-7`)

- **Authority.** As §20.7.3.
- **Rotation is ONE transaction, and the invariant is what makes it safe.** Old row `active → rotating`, new
  row inserted `active`, **both under the scope's partial `UNIQUE(... ) WHERE status='active'`** — so **a
  mid-rotation snapshot never shows zero or two active keys** for a scope. Schema §1.7 states the mechanism
  (*"rotation flips old→`rotating` and new→`active` in one txn"*); this contract states the consequence,
  which is the reason it must not be split into two calls: with zero active keys, `kernel.issue_ticket_atoms`
  (§7.1) fails its precondition *"an `active` `kernel.signing_key` resolves for the event scope"* and **the
  box office stops selling**; with two, `credential-sign` has no deterministic signer.
- **`rotating` is not `revoked`, and conflating them strands every live credential.** A key in `rotating`
  **still verifies** — its `public_key` stays world-readable and its validity window stays open until
  `not_after`. Credentials signed under it remain valid until they are re-minted by the next custody move or
  their TTL lapses. **Rotation invalidates nothing.** Only `revoke_signing_key` (§20.7.5) does, and that is
  precisely why the two are separate functions with separate reason codes.
- **What rotation does NOT do.** It **appends no ownership-log row, bumps no `credential_version`, and
  re-pins no existing atom's `signing_key_id`.** Only a custody move re-pins (§7.2). An implementer who
  "helpfully" re-pins the event's atoms during a rotation performs N custody-table writes outside the three
  kernel engines, which §0.7 forbids outright. **`T-RPC-KEY-02` (structural):** this function's definition
  references neither `kernel.ticket_ownership_log` nor `kernel.tickets`.
- **Preconditions.** `p_old_key_id` is `active` and its scope resolves; `p_not_after` on the old row is set
  to a value **not earlier than the longest live credential TTL** (`config('credential.*')`), so rotation
  cannot retroactively expire a token a fan already holds.
- **Locks / SSCAS / idempotency / writes / errors.** As §20.7.3; both rows are updated under the one scope
  lock. Audit action `signing_key.rotate`, before/after = the two `key_id`s.
- **Test.** `T-RPC-KEY-03` (during and after a rotation, exactly one `active` key exists for the scope at
  every observable instant; an atom minted before the rotation still verifies against the `rotating` key).

#### 20.7.5 `kernel.revoke_signing_key(p_key_id, p_reason_code, p_command_key)` — **EDGE-FRONTED** (`G-7`)

- **Authority.** As §20.7.3, **dual-controlled without exception** — and unlike §20.2.1's direction
  asymmetry, **there is no "tightening executes directly" arm here.** Revocation is not a tightening in
  effect: it **invalidates every credential signed under the key**, so its blast radius is *"every ticket
  holder for this event is refused at the door until re-minted."* That is an availability event of the same
  magnitude as an over-broad grant, in the opposite direction. **The asymmetry that applies to a threshold
  does not apply to a key, and that is stated here so the §20.2.1 precedent is not read across.**
- **Preconditions.** Key exists and is `active` or `rotating`; `p_reason_code` from a closed set
  (`compromise_suspected` · `compromise_confirmed` · `superseded` · `scope_retired`) and **mandatory**;
  **an acknowledgement parameter mirroring §17.11's `p_ack_live_devices`** — `p_ack_live_credentials` must
  equal the current count of non-terminal atoms bound to the key. *"A deliberate speed bump forcing the admin
  to look at the number before defeating a safety property"* is exactly the shape needed here, and for the
  same reason. `INFERENCE:` the parameter is authored; the corpus specifies the pattern for the door override
  and not for key revocation, and the consequence here is strictly larger.
- **What it breaks, stated so the runbook is written before the incident and not during it.** Atoms whose
  `signing_key_id` is the revoked key **cannot be verified online (C37) and cannot be admitted offline** —
  their manifest entries reference a key the door will reject. **Recovery is re-minting credentials under the
  successor key**, which requires the successor to exist. **Therefore: provision or rotate first, revoke
  second.** A revoke with no `active` successor for the scope raises
  `precondition_failed('no_active_successor')` — the one guard that stops a single call from closing a door.
- **It FORCE-CLOSES every open door episode in the key's scope, in its own transaction — and that write set
  and lock order were not stated (edge §5.6, door §16 OQ-5 grant condition 2; edge recon #15).**

  > **Why it must, and why "the doors will notice" is not an answer.** A revoked key's atoms *"cannot be
  > verified online (C37) and cannot be admitted offline"* — but an **already-open** door episode is holding
  > a snapshotted manifest whose entries pin `signing_key_id` to the key being revoked. Those doors keep
  > admitting from a cached manifest until it lapses, which is precisely the window revocation exists to
  > close. **OQ-5 was granted on the condition that revocation force-closes those episodes**, and until this
  > is stated **a granted ruling rests on a condition nothing satisfies.**

  - **Scope.** Every `venue.door_manifest` episode with `status='open'` whose `catalog.event_session`
    resolves to an event in the revoked key's scope (schema §1.7's key scope: platform / org / venue /
    event). **Closed with cause `key_revoked`**, a D3 code, not with the operator's `p_reason_code`.
  - **Lock order — stated, because this function reaches rank 1 and the money contracts around it do not.**
    **`catalog.event_session` `FOR UPDATE` (rank 1) for each affected session, ascending `session_id`** →
    **`venue.door_manifest` (episode row)** → **`kernel.signing_key` (admin plane, LAST)**. Rank 1 is taken
    **before** the key row, which is outside the six ranks: taking the key row first and then reaching for
    rank 1 would be the one inversion available on this path. Ascending within rank 1 by `session_id`, the
    same discipline §7.2 and §9.5 use for atoms.
  - **`kernel.approval_request` (rank 5.5)** is inserted by the dual-control arm **before** any of the
    above — it is the parked-intent write, and the force-close happens on the **approval**, not on the
    request. A revoke that is merely *requested* closes no doors.
  - **THE SCOPE'S OPEN-EPISODE COUNT IS THE BLAST RADIUS, and it is what the acknowledgement is actually
    about.** `p_ack_live_credentials` is the count of non-terminal atoms bound to the key; **the operator
    is additionally shown, and the result additionally returns, `episodes_force_closed`** — because *"every
    ticket holder for this event is refused at the door until re-minted"* is an abstraction, while *"you are
    about to close 4 live doors, mid-event"* is the number a human can refuse on. **A wrong
    `p_ack_live_credentials` raises and writes nothing**, force-close included: the speed bump is in front
    of the whole transaction, not in front of half of it.
  - **The recovery order does not change and is now load-bearing twice over.** *Provision or rotate first,
    revoke second.* A force-closed episode is re-opened by `venue.open_door_manifest` (§17.10), which
    rebuilds the snapshot under the **successor** key — which is why `precondition_failed(
    'no_active_successor')` is *"the one guard that stops a single call from closing a door"*: without a
    successor, the re-open produces a manifest nothing can verify either.
- **Locks / SSCAS / idempotency.** Lock order as stated above (it **extends** §20.7.3 rather than inheriting
  it — §20.7.3 takes no rank-1 lock). **SSCAS:** `n/a` — no money, custody or inventory row is written;
  `catalog.event_session` is locked as a **freeze/boundary read-modify**, not as an SSCAS member, and **the
  closed set stays at fifteen.** Terminal-state idempotent (`revoked` is terminal — schema §1.7's status is
  forward-only, guarded by a trigger); a replay force-closes nothing a second time and returns
  `episodes_force_closed = 0`.
- **Writes.** `kernel.signing_key` (→ `revoked`, `not_after := now()`), **`venue.door_manifest`** (every
  `open` episode in scope → `closed`, `close_cause='key_revoked'`), **`venue.door_manifest_delta`** (a
  terminal marker per closed episode, so a reconnecting scanner learns the episode ended rather than polling
  a manifest that stopped changing), `kernel.approval_request`, `kernel.admin_audit` (`signing_key.revoke`,
  mandatory `reason_code`, the acknowledged credential count, **and the force-closed episode ids**).
  **Revoked keys are retained** (plan `083` rollback posture: *"revoked keys and certs are retained so
  historical credentials stay verifiable and explicable"*) — **this function never deletes a row.**
- **Result.** `{ status, key_id, request_id, credentials_invalidated int, episodes_force_closed int }`.
- **Errors.** `insufficient_privilege` · `sod_violation` · `not_found` ·
  `precondition_failed(no_active_successor | unacknowledged_live_credentials | reason_required |
  already_revoked)`.
- **Test.** `T-RPC-KEY-04` (revoking the only `active` key for a scope raises; a wrong
  `p_ack_live_credentials` raises and writes nothing; a revoked key's row survives and its `public_key`
  stays readable so historical credentials remain explicable) · **`T-RPC-KEY-05`** (with **two** `open`
  episodes in the key's scope and one outside it, an approved revoke closes **exactly the two**, in the same
  transaction as the key row, and a scanner polling a closed episode is told the episode ended — asserted on
  the episode rows, **not** on the absence of admissions, which would pass on a manifest that merely lapsed).

#### 20.7.6 `kernel.mark_payout_transfer_state(p_payout_id, p_new_status, p_stripe_transfer_ref, p_failure_code, p_command_key)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (schema §1.9.2, defect `MB-2b`; filed as §13.7 `S-16`)

> **This function exists in the schema spec, the migration plan and the package registry, and in ZERO
> contracts, ZERO RLS EXEC rows and one edge-spec placeholder that names no function** (*"`mark`-style state
> sync RPCs"*, §4). It is the writer of three of `kernel.payout`'s five `status` labels and of
> `stripe_transfer_ref`. **A function scheduled into a package with no contract is a function an engineer
> invents**, and the one they will invent is a webhook handler that clears holds.

- **Purpose.** Record what Stripe reported about a transfer that has already been decided and written.
  **It moves no money and calls nothing external.**
- **Authority.** **`EXEC: DEF`** — `service_role` only, `REVOKE EXECUTE FROM anon, authenticated, public`,
  **no human path**. Class B (`EA-3` B-ii) from the edge. **No human path may be added:** a principal who can
  set a payout to `paid` can retire an org's undisbursed exposure without money moving.
- **Params.** `p_payout_id`; `p_new_status ∈ {paid, failed, reversed}` — **`pending` and `submitted` are not
  accepted arguments**: `pending` is the INSERT default and `submitted` belongs to
  `kernel.request_org_payout` (§10.3), which takes the destination cool-down, SoD-1, the maturity floor and
  the step-up. Accepting `submitted` here would be a second door onto the state the money controls guard.
  `p_stripe_transfer_ref` (`tr_…`); `p_failure_code` (nullable, `failed` only); `p_command_key`.
- **Preconditions.**
  1. **Forward-only** — `submitted → paid|failed|reversed`; `paid → reversed` is the one terminal-to-terminal
     edge and it is legal (Stripe can reverse a settled transfer). Any other pair raises
     `precondition_failed('payout_state_backwards')`.
  2. **It REFUSES to advance a row whose `hold_state <> 'none'`** (`precondition_failed('payout_held')`),
     leaving **both** `status` and `hold_state` untouched. **A held payout that Stripe reports as paid is a
     reconciliation incident, not a state transition** — silently clearing the hold would defeat Control 4 of
     §17.7 **by webhook**, which is the one attacker path that needs no role at all.
  3. **`p_stripe_transfer_ref` is mandatory and write-once** — equal on replay, else `conflict_locked`. It is
     the join key to an external ledger.
  4. **`p_failure_code` is required for `failed` and rejected otherwise** (`invalid_input`).
- **Locks & order.** `kernel.payout` row `FOR UPDATE` — money plane, **rank 6**. Nothing else. **SSCAS:**
  `n/a` (single aggregate); **no member added, C28's closed fifteen stands, no new lock class.**
- **Writes.** `kernel.payout` (`status`, `stripe_transfer_ref`, `failure_code` where applicable),
  `kernel.admin_audit` (`payout.state_sync`, before/after) in the same txn. **On `→ paid` it additionally
  calls `venue.on_payout_settled(p_payout_id)`** — the SEAM-2 hook (§20.11.5), which is the only writer of
  `venue.settlement.status='paid'`. **Nothing else.**
- **Result.** `{ status ∈ {updated, noop_replay}, payout_id, new_status }`. **Idempotency.** `p_command_key`
  plus the forward-only and equal-ref rules; a redelivered event on a row already in the target state returns
  `noop_replay` and **does not raise** — a webhook that raises is a webhook Stripe retries forever.
- **Errors.** `not_found` · `precondition_failed('payout_state_backwards' | 'payout_held')` ·
  `conflict_locked` · `invalid_input`.

- **THE EVENT MAPPING, CORRECTED — the four Stripe events are NOT four sources for one row** (schema §1.9.2;
  edge §4's row is corrected in the same pass):

  | Stripe event | What it actually is | What it may drive here |
  |---|---|---|
  | `transfer.created` | platform → connected-account transfer, id `tr_…` | confirms `submitted` and **writes `stripe_transfer_ref`** — **the only event that supplies the join key** |
  | `transfer.reversed` | that same transfer, reversed | `→ reversed` |
  | `payout.paid` / `payout.failed` | the **connected account's own bank payout**, id `po_…` | **nothing on a single `kernel.payout` row.** One bank payout **aggregates many transfers**, so it is not attributable to one row; treating it as one is a mis-join that marks arbitrary payouts paid |

- **CONSEQUENCE, STATED BECAUSE IT DECIDES WHO WRITES `failed`.** A transfer that cannot be created fails as a
  **synchronous Stripe API error, not as an event.** There is no `transfer.failed`. So **the `payout-execute`
  edge function — not `stripe-webhook` — is the natural writer of `failed`**, in the same request that caught
  the error, with the classifier `payout-logic.ts` already carries. The pre-fix corpus routed `failed` to a
  webhook that will never fire, which is why *"a failed transfer reads `submitted` forever"* and dashboard
  §14.5's pinned *Failed payout* banner could never fire.
- **WHAT `paid` ASSERTS IS AN OWNER DECISION AND IS NOT TAKEN HERE — `O16`, recorded, left open.** Either
  (a) *"the transfer succeeded and was not reversed"*, written **synchronously by the executor** on the
  `transfers.create` return; or (b) *"the funds reached the payee's bank"*, which requires a
  `balance_transaction` fan-out from `payout.paid` to recover which transfers that bank payout covered.
  **Both are served by this one RPC — only the caller and the trigger change** — so the decision costs no
  contract change either way. They differ in **what the venue is being told**, and one of them is a promise
  about a bank we do not observe. **This contract does not choose.** Until `O16` is answered, an implementer
  builds form (a), which is the form with no unbuilt dependency, and the choice is visible in one place.
- **Callers.** `payout-execute` (edge §3.4) — `failed` synchronously, and `paid` under form (a);
  `stripe-webhook` (edge §4) — `reversed` from `transfer.reversed`, and the `stripe_transfer_ref` confirmation
  from `transfer.created`.
- **Forbidden.** Every human role including `platform_admin` and `platform_risk`; any caller supplying
  `pending` or `submitted`; any handler keyed on `payout.paid`/`payout.failed` writing a `kernel.payout` row.
- **Tests.** `T-SCHEMA-PAYOUT-05` (the label-completeness sweep — schema §1.9.2; this contract is what makes
  it pass) · `T-SCHEMA-PAYOUT-06` (a `hold_state='held'` payout **raises** and leaves **both** columns
  unchanged — both halves, because the first passes if the function merely returned early after clearing the
  hold) · `T-SCHEMA-PAYOUT-07` (forward-only) · **`T-RPC-MONEY-29`** (structural: **no handler keyed on
  `payout.paid` or `payout.failed` calls this function with a payout id derived from a `po_…`** — asserted
  over the webhook's branch table, because the mis-join is invisible from any single-row test) ·
  **`T-RPC-MONEY-30`** (a replayed `transfer.reversed` returns `noop_replay` and writes no second audit row).

#### 20.7.7 `kernel.mark_refund_state(p_refund_id, p_new_status, p_stripe_refund_ref, p_failure_code, p_command_key)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (schema §1.10.1, defect `R1-1`)

> **`kernel.refund` had three unreachable `status` labels and a Stripe join key with zero writers and zero
> readers.** Its complete writer set was `refund_primary_order`, `admin_refund` and the C25 sweep — **all
> three INSERT at the `pending` DEFAULT.** `submitted`, `succeeded` and `failed` were written by nothing, and
> `stripe_refund_ref` occurred **once** in the whole corpus: the schema's own DDL line. Edge §3.5's
> *"records `stripe_refund_id` via a callback param"* and edge §4's *"extend to also reconcile
> `kernel.refund` state"* are **two placeholders naming no function** — the `MB-2b` shape verbatim, on the
> refund table this time. **`MB-1`'s cumulative operand sums `status ∈ {pending, submitted, succeeded}` over
> a column that could only hold `pending`.**

- **Purpose.** Record what Stripe reported about a refund that has already been decided and written. **It
  moves no money, calls nothing external, and touches no `public.*` table.** The Stripe call belongs to
  `refund-execute` (edge §3.5); this is the one function that writes the outcome back.
- **Authority.** **`EXEC: DEF`** — `service_role` only, `REVOKE EXECUTE FROM anon, authenticated, public`.
  **No human path**, and none may be added: a human who can set a refund to `succeeded` can retire an
  exposure that never settled and buy tier headroom under §17.1a. Class B (`EA-3` B-ii) from the edge.
- **Params.** `p_refund_id`; `p_new_status ∈ {submitted, succeeded, failed}` — **`pending` is not an
  accepted argument**, since it is the INSERT default and accepting it would make the state machine
  reversible through a parameter; `p_stripe_refund_ref` (`re_…`); `p_failure_code` (nullable, `failed`
  only); `p_command_key`.
- **Preconditions.**
  1. **Forward-only.** `pending → submitted → succeeded|failed`. Any other pair raises
     `precondition_failed('refund_state_backwards')`. `succeeded` and `failed` are terminal.
  2. **`p_stripe_refund_ref` is mandatory on every accepted transition** and **write-once**: if the row
     already carries one it must be **equal**, else `conflict_locked`. It is the join key to an external
     ledger; a second value silently re-points the reconciliation.
  3. **`p_failure_code` is required for `failed` and rejected otherwise** (`invalid_input`) — a failure with
     no cause is the audit row that made the whole reconciliation worthless.
- **THE CASE AN IMPLEMENTER WILL GET WRONG, AND THE RULE THAT SETTLES IT.** A `stripe.refunds.create` that
  **itself** errors produces **no `re_…`**, so nothing left the database for Stripe and **the row stays
  `pending`** — the executor retries under the deterministic `refund_${refund_id}` key. **`failed` means
  Stripe ACCEPTED the refund and then could not settle it.** Collapsing the two puts a never-attempted
  refund and a rejected one into one label, and **only one of them may be retried automatically**. Schema
  §1.10.1's `CHECK (status = 'pending' OR stripe_refund_ref IS NOT NULL)` makes the wrong version
  unstorable rather than merely wrong.
- **Locks & order.** `kernel.refund` row `FOR UPDATE` — money plane, **rank 6**. Nothing else. **SSCAS:**
  `n/a` (single aggregate); **no member is added and C28's closed fifteen stands.**
- **Writes.** `kernel.refund` (`status`, `stripe_refund_ref`, `failure_code` where applicable),
  `kernel.admin_audit` (`refund.state_sync`, before/after) **in the same transaction**. **Nothing else** —
  in particular it does **not** re-void, un-void or touch a ticket atom: custody was settled by
  `refund_primary_order` at request time and a Stripe-side failure does not un-refund a ticket. **That is a
  reconciliation incident for a human, not a state transition** — the same posture §20.7.6 takes for a held
  payout Stripe reports as paid.
- **Result.** `{ status ∈ {updated, noop_replay}, refund_id, new_status }`.
- **Idempotency.** `p_command_key` per `(actor, key)`; **plus** natural idempotency from the forward-only
  guard and the equal-ref rule — a redelivered `charge.refunded` for a row already `succeeded` returns
  `noop_replay`, it does not raise. **A webhook that raises is a webhook Stripe retries forever.**
- **Errors.** `not_found` · `precondition_failed('refund_state_backwards')` · `conflict_locked` (a
  different `stripe_refund_ref`) · `invalid_input`.
- **Callers, and which label each may write** — the mapping is part of the contract because the pre-fix
  corpus routed four Stripe events at one placeholder:

  | Caller | Trigger | Label | Why it is attributable |
  |---|---|---|---|
  | `refund-execute` (edge §3.5) | the object `stripe.refunds.create` **returns** | `submitted` | the create call returns the `re_…`; this is the first moment our row has a join key |
  | `stripe-webhook` (edge §4) | `charge.refunded` / `refund.updated` | `succeeded` | **the event payload carries the `re_…` the executor stored** — a refund is not aggregated the way a bank payout is, so unlike `payout.paid` (§20.7.6) the join is exact |
  | `stripe-webhook` (edge §4) | `refund.failed` / `charge.refund.updated → failed` | `failed` | same join key |

- **Forbidden.** Every human role including `platform_admin`; any caller supplying `pending`; any client
  writing `kernel.refund` directly.
- **Tests.** `T-RPC-MONEY-25` (**the completeness sweep** — for each of `pending`/`submitted`/`succeeded`/
  `failed` a named function in the chain writes it; this is schema `T-SCHEMA-REFUND-01`'s RPC half and it
  fails against the pre-fix corpus) · `T-RPC-MONEY-26` (forward-only both ways: `succeeded → submitted`
  raises and `failed → succeeded` raises) · `T-RPC-MONEY-27` (a second, different `stripe_refund_ref`
  raises; an **equal** one returns `noop_replay` and writes no second audit row — both halves, because the
  redelivery path is the common one and a raise there loops Stripe) · `T-RPC-MONEY-28` (`refund_exposure_minor`
  **excludes** a `failed` refund and **includes** a `submitted` one, asserted on the aggregate of §17.1a).

#### 20.7.8 `venue.assert_may_request(p_actor, p_scope_kind, p_scope_id, p_template_id, p_raise boolean DEFAULT true) RETURNS boolean` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (`AUTHZ-CRM2`; `C66` / `K-15`)

> **IT GOT A PACKAGE NUMBER AND NOTHING ELSE.** `087` names it in all four registry surfaces and in migration
> plan §8; RLS §7.5 and §11.6 *call* it; CRM §9.2, §12 and `K-15` rest the *"marketing cannot download the
> money export"* fix on it; RPC §17.22 names it twice. **It had no contract, no return type, no parameter
> types, no security context, no grant and no RLS EXEC row** — and schema §13.1's own row still reads
> *"contracted and scheduled nowhere."* **Two independent implementations of one authorization predicate is
> how a download outlives the authority that granted it**, which is the `H-12` break this function exists to
> close.

- **Purpose.** **The single shared export-authorization predicate.** *May this actor request — and therefore
  download — an export of this template at this scope, **right now**, evaluated live against the grant
  tables?* One function, three callers, **one implementation**: `venue.request_export`,
  `venue.authorize_export_download` and `venue.list_export_jobs` (§17.22).
- **THE RETURN SHAPE, SETTLED (`R1-4`; ratification `C108`). The corpus asked for two incompatible things
  and this is the resolution.** The name implies **raising**; `venue.list_export_jobs` needs a
  **`downloadable` boolean** *"computed with `authorize_export_download`'s own predicate"* (CRM §9.5, RLS
  §11.6, RLS `X-19`). Three candidate shapes were considered and two are rejected on the record:

  | Shape | Rejected because |
  |---|---|
  | Two functions — `assert_may_request` (raises) + `may_request` (boolean) | **Two objects is two implementations**, which is the exact defect this function exists to prevent, and `T-RLS-CRM-05` asserts an **equality between call sites** that two names cannot satisfy. It would also add an object to `087` for no authority gain |
  | One 4-parameter boolean, with the raise moved into each caller | The predicate is then the boolean and **the refusal is the caller's**, so a caller that forgets to check it silently authorizes. **A control that depends on callers remembering IS a convention** — the construction `AUTHZ-M1` refuses |

  > **ADOPTED: one function, `RETURNS boolean`, with `p_raise boolean DEFAULT true`.** In the default
  > (raising) mode it raises `insufficient_privilege(42501)` on denial and returns `true` on success — so
  > **the safe behaviour is what a caller gets by writing nothing**. `p_raise := false` is an explicit,
  > greppable opt-out used by **exactly one caller**, `list_export_jobs`, which returns **job metadata only,
  > no row and no object path**, and projects the boolean as `downloadable`. **One predicate, one body, one
  > allow-list; the two authorizing call sites and the lister cannot drift, because there is nothing to keep
  > in step.**
  >
  > **`T-RPC-CRM-06` is structural and is the guard on the opt-out:** `request_export` and
  > `authorize_export_download` call this function **in raising mode**, asserted over their bodies, and
  > `list_export_jobs` is the **only** caller passing `p_raise := false`. A future caller that suppresses the
  > raise is a review reject, not a runtime surprise.
- **Authority.** **`EXEC: DEF` — TRUE definer-only, OWNER RULING `Q-1`/`ID-6` (`OR-10`, 2026-08-29):**
  `REVOKE EXECUTE FROM anon, authenticated, public`; `GRANT EXECUTE TO service_role` only (§0.1a's class,
  exactly). It reads `kernel.org_member`, `venue.staff_role` and the scope objects, which the caller does
  not hold. **Its three callers — `request_export`, `authorize_export_download`, `list_export_jobs` — are
  all `postgres`-owned `SECURITY DEFINER` functions (`T-RPC-GLOBAL-01`), and a definer-internal call is
  privilege-checked as the OWNER, not the session role, while `auth.uid()` still resolves to the caller's
  JWT — so the legitimate caller path needs NO grant on this helper.** *(The previous text granted
  `EXECUTE` to `authenticated` on the reasoning that it "is called inside definers that run as the
  caller's `auth.uid()`" — a true premise with a FALSE inference, and a grant NO live path used. The
  owner applied least privilege; the un-ruled grant would also have opened a `not_found` existence oracle
  over scope uuids and made `p_actor` a foreign-uuid authority probe outside `T-RPC-CRM-07`'s structural
  sight. NO direct product/human role possesses this helper — it has no §5.3 capability row, no §5.4 map
  entry, no RLS policy reference, no client route; that absence is the negative evidence, and
  `T-RPC-GLOBAL-02` now passes over the full corpus.)* **It grants nothing and writes nothing** — a leaked
  `true` for a scope the caller cannot name discloses nothing, because every caller re-resolves the scope
  itself.
- **`p_actor` is a parameter and that needs the argument, because `EA-6`/C35 forbid actor parameters.** This
  is **not** an edge-supplied actor: every caller passes **`auth.uid()`**, evaluated inside a definer in the
  same transaction, and `authorize_export_download` passes it alongside `job.scope_kind`/`job.scope_id`/
  `job.template_id` read from the **job row**. It is a parameter rather than an internal `auth.uid()` read
  **so the predicate is a pure function of its inputs and therefore assertable as an equality between call
  sites** (`T-RLS-CRM-05`). **`T-RPC-CRM-07`: no caller passes anything but `auth.uid()` for `p_actor`,
  asserted structurally** — the one assertion that keeps the parameter from becoming the C35 pattern.
- **Params.** `p_actor uuid`; `p_scope_kind text ∈ {session, event, venue, org}` — **`all` is not a member
  and raises `invalid_input`**, per §17.22; `p_scope_id uuid`; `p_template_id text ∈ {audience_v1,
  operations_v1}`; `p_raise boolean DEFAULT true`.
- **The predicate, stated once, because this is the corpus's only statement of it.**

  ```text
  audience_v1    -> org grain:   org_owner, org_admin, org_marketing
                    venue grain: venue_manager, venue_marketing
  operations_v1  -> org grain:   org_owner, org_admin
                    venue grain: venue_manager
                    (the narrowest allow-list in either spec -- it adds MONEY columns)
  ```
  **Both grains are resolved through the org that owns the scope object, re-resolved here rather than
  trusted** — `catalog.venue.org_id` is mutable while `catalog.event.org_id` is stamped at create, which is
  the `H-11` re-operated-venue leak. **Platform roles are DENIED on every arm** (`platform_support`,
  `platform_risk`, `platform_admin`): platform reads the roster (§17.22 `list_attendees`) and does not use
  the venue CRM export; bulk platform extraction is not built in Phase 2 (`MD-8`). Also denied:
  `venue_box_office`, `venue_scanner`, both promoter-manager labels, `venue_finance`, `org_finance`,
  `org_member`, promoters, a door session, `fan`, `anon`.
- **THE BREAK IT CLOSES, so the template argument is not dropped in a refactor.** `org_marketing` holds
  `X10` (read export history), so it can see a colleague's `job_id`; it holds a marketing-class role over the
  scope, so a **role-set** re-check passes; and it downloads an **`operations_v1`** file — order refs, order
  totals, **unit prices**, refund state. §3.1's *"Finance sees money and no contact. Marketing sees contact
  and no money. Neither sees both."* is then defeated by **any org that ever ran one operations export, with
  no grant being wrong.** **The template is the conjunct that was missing, and it is why the list stays
  role-scoped while the download is template-scoped.**
- **Locks:** none. **SSCAS:** `n/a`. **Writes:** **nothing.** It is `STABLE`, not `IMMUTABLE` — it reads live
  grant tables, and *"live"* is the entire point (an export prepared before a revocation fails after it,
  `EX-4`). **It writes no audit row**: the *decision* is audited by its callers (`crm_export.request` /
  `crm_export.download`), and a predicate that logged on every list row would drown them.
- **Errors.** `insufficient_privilege(42501)` in raising mode · `invalid_input` (unknown `scope_kind`,
  unknown `template_id`, `scope_kind='all'`) · `not_found` (scope object absent) — **`not_found` is raised in
  both modes**, because a nonexistent scope is a caller bug, not a denial, and returning `false` for it would
  let a lister render "not downloadable" for a job whose scope was deleted.
- **Package.** `087`, unchanged and already declared: it reads `venue.export_job` (`087`),
  `kernel.org_member` (`077`) and `venue.staff_role` (`080`) → **SEAM-1 `max(077, 080, 087) = 087`**, and
  `087` declares `077`, `081`, `085`, `086`. **No package added, renamed or renumbered; no dependency edge
  added.**
- **Tests.** `T-RLS-CRM-05` (cited, not renumbered — `request_export` and `authorize_export_download` resolve
  to the **same** function, asserted as an equality between the two call sites) · **`T-RPC-CRM-06`** (the
  raising-mode structural assertion above) · **`T-RPC-CRM-07`** (`p_actor` is always `auth.uid()`) ·
  **`T-RPC-CRM-08`** (`org_marketing` is refused an `operations_v1` download **and** sees
  `downloadable = false` for that job in `list_export_jobs` — **both halves in one test**, because the panel
  and the RPC disagreeing is `X-19`'s failure and a test of either alone passes on it).
- **Reported via §20.14 `R-29` — APPLIED 2026-08-29 with the ruled class.** `PHASE_2_RLS_PERMISSION_SPEC.md`
  §11.6 now carries the **`DEF`** EXEC row (`OR-10`; this bullet's first edition asked for "`EXECUTE` to
  `authenticated`, `REVOKE` from `anon`, `EXEC: DEF`" — the self-contradiction `ID-6` named; corrected);
  the migration plan §8 `087` row and the package registry both name it with a **four**-parameter signature
  and must carry the defaulted fifth; `PHASE_2_CRM_EXPORT_SPEC.md` §9.5 should cite the return shape rather
  than restating it.

#### 20.7.9 `venue.cancel_pending_order(p_order_id, p_reason_code, p_command_key)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (fence `venue.order` row; edge §4 "order cancel RPC"; authored 2026-08-29)

> **`venue.order.status` has five labels and its complete writer set reached four.** `create_primary_checkout`
> INSERTs `pending`, `finalize_primary_order` writes `paid`, `refund_primary_order` writes
> `partially_refunded`/`refunded` — **`cancelled` was written by nothing.** Edge §4 routed
> `payment_intent.payment_failed` at *"venue.release_inventory_hold / order cancel RPC"* — a placeholder
> naming no function, the `MB-2b`/`R1-1` shape on the order table.

- **Purpose.** Record that a pending order's payment path has terminally failed: the container closes without
  money ever having moved. **It moves no money, calls nothing external, touches no `public.*` table.**
- **Authority.** **`EXEC: DEF`** — `service_role` only, `REVOKE EXECUTE FROM anon, authenticated, public`.
  Class B (`EA-3` B-ii) from the edge. **No human path in this contract** — a human who can cancel a pending
  order can strand a buyer mid-retry.
- **Params.** `p_order_id`; `p_reason_code` — **required**, ∈ `('payment_failed')` (closed set, extended only
  by contract change); `p_command_key`.
- **Preconditions.**
  1. **Forward-only.** `pending → cancelled` only. `paid`/`partially_refunded`/`refunded` raise
     `precondition_failed('order_not_pending')`; already-`cancelled` returns `noop_replay`.
  2. **THE CASE AN IMPLEMENTER WILL GET WRONG — the terminal-failure rule (`SPEC CORRECTION` to edge §4's
     row).** `payment_intent.payment_failed` fires per **attempt**, and edge §3.1 contracts in-session retry
     **against the same order** (*"a canceled PI is retired and a fresh salted PI minted"*; checkout replay
     returns the same `order_id` — which requires the order still `pending`). §6.3's own precondition is
     `order 'pending'`, so cancel-on-first-decline followed by a late success finalizes nothing: **money
     captured, no tickets, webhook non-2xx, Stripe retries forever.** The webhook therefore calls this
     function **only when the PaymentIntent is TERMINAL** (`payment_intent.canceled`, or a `payment_failed`
     whose intent status is `canceled`) — a mere failed attempt cancels nothing and releases nothing.
- **Locks.** `venue.order` row `FOR UPDATE` — **rank 3 (Order)**. Nothing else. **SSCAS:** n/a (C28's closed
  fifteen stands).
- **Writes.** `venue.order` (→ `cancelled`), `kernel.admin_audit` (`order.cancel`, before/after +
  `reason_code`) in the same txn. **Nothing else — in particular it touches no inventory.** No order→hold
  linkage exists to reach (schema §3.7 carries no hold ids; §3.5 no `order_id`; the PI metadata none) — the
  failure path's capacity return is owned by `venue.sweep_expired_inventory_holds` (§20.3.3) at hold TTL,
  the same bound the checkout's hold timer displayed. **Edge §4's "release the inventory hold" arm has no
  order-derivable implementation and is corrected to "(capacity returns via the §20.3.3 sweep at hold
  TTL)"** — prompt release would need an additive `order_id` column on `venue.inventory_hold`: a schema
  change, not this contract.
- **Result.** `{ status ∈ {cancelled, noop_replay}, order_id }`. **Idempotency.** `p_command_key` +
  forward-only; a redelivered terminal-failure event on a cancelled row returns `noop_replay` and never
  raises — **a webhook that raises is a webhook Stripe retries forever.**
- **Errors.** `not_found` · `precondition_failed('order_not_pending')` · `invalid_input`.
- **Callers.** `stripe-webhook` (edge §4) under the terminal-failure rule — nothing else. (An abandoned
  order with no payment attempt receives no Stripe event and stays `pending`; its holds return via §20.3.3
  so no capacity is lost; sweeping stale `pending` orders is presentational — the §4.3.1 disposition —
  and deliberately unscheduled.)
- **Forbidden.** Every human role; any caller on a non-terminal failure; any client.
- **Tests.** `T-RPC-ORDER-01` (**label-completeness sweep** over schema §3.7's five labels — for each, a
  named function in the chain writes it; fails against the pre-fix corpus) · `T-RPC-ORDER-02` (cancel of a
  `paid` order raises and leaves `status` untouched; replay on `cancelled` returns `noop_replay`, no second
  audit row — both halves) · `T-RPC-ORDER-03` (**structural** — no webhook branch keyed on
  `payment_intent.payment_failed` calls this function without asserting the intent's terminal status) ·
  `T-RPC-ORDER-04` (cancel-then-finalize race: after cancel, `finalize_primary_order` raises and **mints
  nothing — asserted on `kernel.tickets`**, not on the error).

#### 20.7.10 `kernel.record_identity_obligation(p_debtor_identity_id, p_origin_kind, p_origin_ref, p_stripe_dispute_ref, p_amount_minor, p_reason_code, p_command_key)` — **DB-RPC** (`OR-21`, F-P2-1)

- **EXEC: DEF** — `service_role` only, **no human path** (the §20.7.7 posture). Callers: the native
  `charge.dispute.closed`(lost) webhook branch (edge §4) and platform ops tooling for live-rail chargebacks;
  the frozen external-rail webhook branches remain byte-for-byte untouched.
- **Table:** `kernel.identity_obligation` (schema §1.10a — origin-immutable; `origin_kind` CHECK in
  `chargeback`/`refund_clawback`; `amount_minor > 0`; `UNIQUE(origin_kind, origin_ref)`;
  `stripe_dispute_ref` write-once partial UNIQUE; `status` `outstanding → recovered | written_off`
  forward-only; `REVOKE DELETE` outright; deny-all RLS).
- **Validations:** ① debtor FK resolves — **no state precondition**: recording against ACTIVE,
  DELETION_PENDING or ERASED is legal by design (recording against the tombstone is the Q2 path working);
  ② `origin_kind` in the closed set; a native `refund_clawback` requires the `kernel.refund` row
  `status='succeeded'` with a non-`buyer_request` reason; ③ `amount_minor > 0`, currency `'USD'` (C13);
  ④ duplicate `(origin_kind, origin_ref)` → `noop_replay` returning the existing id, no second audit row.
- **Writes (one txn — and nothing else):** INSERT `kernel.identity_obligation` (`outstanding`) +
  `kernel.admin_audit` (`obligation.record`, before/after). Moves no money; touches no `public.*` table;
  no external I/O. **SEAM-1:** writes `identity_obligation` (`085`) + `admin_audit` (`077`) →
  `max(077,085) = 085`; the `077 → 085` edge is pre-declared — **no edge added**. Locks: own row only —
  no SSCAS membership; C28's closed fifteen stand.
- **Emissions:** none (`OR-14`: not a producer). **Errors:** §0.5.

#### 20.7.11 `kernel.resolve_identity_obligation(p_obligation_id, p_resolution, p_reason_code, p_command_key)` — **EDGE-FRONTED DB-RPC** (`OR-21`)

- **Authority:** `platform_risk` · `platform_admin` (the `hold_payout`/`release_payout` seam,
  EDGE-CALLER-JWT §3.1; `is_platform`, C36); actor server-derived (C35).
- `p_resolution ∈ {recovered, written_off}` — `recovered` records an externally-completed recovery;
  `written_off` is the ops write-off act the F-P2-1 filing names. `FOR UPDATE`; only `outstanding`
  transitions; same-resolution replay → `noop_replay`; different terminal → `state_conflict`.
- **Writes:** status + resolution triple (`resolution_reason_code`, `resolved_by`, `resolved_at`) +
  `kernel.admin_audit` (`obligation.resolve`) in-txn. Moves no money. Does **not** touch the deletion
  machine — the sweep re-evaluates BP-10 on its next pass. Dual-control deliberately not added (single
  audited platform act; recorded as out of scope, not an open bit). **Package `085`** (same SEAM-1).

#### 20.7.12 `kernel.has_outstanding_obligations(p_identity_id uuid) RETURNS boolean` — **STABLE definer predicate** (`OR-21`)

- **The BP-10 / ODR-16 Q4 operand read:** TRUE iff any `kernel.identity_obligation` row has
  `debtor_identity_id = p_identity_id` AND `status = 'outstanding'` (EXISTS over the partial index).
  `EXEC: DEF` — no client grant; caller: `kernel.sweep_deletion_pending` (§20.17.4).
- **SEAM-2 (`OR-17` fold):** stub in `077` returning `false` — true-not-inert (no origin object exists
  before `085`); `CREATE OR REPLACE`d in `085`, signature frozen (SEAM-2a); `077 → 085` pre-declared.
- **Tests:** `T-SCHEMA-OBLIG-01`…`-07` (label completeness by named writers; forward-only; pairing CHECK;
  `noop_replay`; the operand flip false→true→false; the Q2 ERASED-identity witness — recording against a
  tombstone commits and raises nothing; deny-all/REVOKE incl. DELETE impossible for every principal).

### 20.8 THE NATIVE MARKETPLACE WRITE SURFACE — the `088` gap (`G-5`)

> **RLS §11.1 carries EXEC rows for six `market.*` writers and this document contracts none of them.**
> Package `088` creates `market.listing_native`, `market.auction` and `market.offer` — **three tables whose
> only writers are these six functions.** §8 covers P2P only. One of the six is granted EXECUTE under the
> name *"bid RPC"*: **the authority table declines to name a function even while granting it.**

**Two boundary facts that bound every contract below, stated once.**

- **C8 — the market never writes custody and the kernel never writes `market`.** A native sale is: the
  `market` layer writes `market.market_sale`, **then** calls `kernel.transfer_ticket_ownership` **in the same
  transaction** (§0.7, §7.2). That is SSCAS member #2, *"not a second, unnamed transaction"* (§14.3).
- **The MVP price-discovery rail, and the one decision the corpus leaves open.** §16.5 rules that MVP
  **reuses the frozen external `public.bids` / `auto-finalize-auctions` engine**, and schema §4.2 says bids
  live on `public.bids` *"when the listing mirrors there"*, with a native `market.bid` ledger as an
  **extension point (EXT, C42-style), not created in `088`.** **Neither document says what happens to a
  native-only auction that does not mirror.** §20.8.3/§20.8.4 state the MVP position and flag the residue
  rather than inventing a ledger — see §20.8.4's `OPEN DECISION`.

#### 20.8.1 `market.create_listing(p_atom_id, p_price_minor, p_listing_mode, p_command_key)` — **DB-RPC (SSCAS member #6)**

- **Authority.** **owner of the atom** — RLS §11.1 (*"owner of the atom · platform (cancel)"*): `auth.uid()`
  must equal `kernel.tickets.current_owner_id` on a **live read under the atom lock** (C9/I-5), never from a
  client parameter and never from a JWT claim. There is no role branch: **no venue or org role may list
  someone's ticket**, which is the property that makes the resale rail a consumer surface rather than an
  operator one.
- **Params.** `p_atom_id`, `p_price_minor`, `p_listing_mode ∈ {buy_now, auction, offer}`, `p_command_key` —
  all untrusted.
- **Preconditions, in the order they must be evaluated.** Atom `state='active'`, `resale_state='none'`
  (**`conflict_locked` otherwise — this is what blocks a double-sell**); caller is the current owner;
  **`NOT kernel.is_transfer_frozen(p_atom_id)` → `frozen`** (§12.4c: *"rechecks — correct (error quality)"*,
  so a fan sees *"Transfers are closed"* rather than an engine failure); the price is within the governing
  `catalog.resale_policy` cap → `policy_violation`; `feature.native_resale_enabled` is ON, else
  `precondition_failed('feature_disabled')`.
- **The policy snapshot is taken here and is immutable for the listing's life.** `resale_policy_id` **and**
  `resale_policy_version` are written onto the row (schema §4.1, O3/C11). §20.2.2's tightening therefore
  binds only later listings. **An implementer who resolves the policy at sale time instead re-prices an offer
  a buyer already accepted.**
- **Locks & acquisition order (member #6).** **Listing (rank 4)** — the INSERT plus the partial
  `UNIQUE(ticket_atom_id) WHERE status='active'` — → **Ticket Atom (rank 5) `FOR UPDATE`** via
  `kernel.lock_ticket` (§7.4), which sets `resale_state := 'listed'` and **re-checks the freeze at the
  choke-point** (§12.4c: *"correct — a choke-point"*). Ascending. **SSCAS: member #6 (Native listing
  create)** — §14.1's existing row, now with a contract behind it.
- **Idempotency.** `UNIQUE(seller_id, command_idempotency_key)` (C16) + the partial unique on the atom. A
  replay returns the original `listing_id`; a **second** listing of the same atom is rejected by the index,
  not by a race-prone `NOT EXISTS`.
- **Writes.** `market.listing_native` (INSERT `active`), `kernel.tickets.resale_state` (→ `listed`, via
  `kernel.lock_ticket` **only** — §0.7: the market layer never writes custody directly).
  **No ownership-log row** — listing is an overlay, not a custody move (§7.4).
- **Result.** `{ status, listing_id, resale_state, policy_version }`.
- **Errors.** `insufficient_privilege(42501)` · `conflict_locked` (already listed/locked) · `frozen` ·
  `policy_violation` (cap/window) · `precondition_failed(atom_not_active | feature_disabled)` ·
  `idempotency_replay`.
- **Forbidden callers.** Anyone who is not the atom's current owner — **including every venue role, every org
  role and every platform role**; `anon`.
- **Test.** `T-RPC-MARKET-01` (a non-owner, a `venue_manager` of the issuing venue and a `platform_admin` are
  each refused; a second listing of a listed atom raises `conflict_locked`; a listing on a frozen session
  raises `frozen`).

#### 20.8.2 `market.cancel_listing(p_listing_id, p_reason_code, p_command_key)` — **DB-RPC (member #6 reverse)**

- **Authority.** the listing's **seller** · **`is_platform(['platform_admin','platform_risk'])`** — RLS
  §11.1's *"platform (cancel)"*. `INFERENCE:` §11.1 says *"platform"* without naming labels;
  `platform_admin`/`platform_risk` are contracted (a takedown is a risk act), **`platform_support` is not**,
  and this is flagged rather than assumed.
- **Exempt from the freeze (§12.4c: *"delisting strands nothing"*).** Cancelling returns the atom to its
  **existing** owner with an unchanged `credential_version`, so it cannot strand a credential and must stay
  available after doors open — indeed `venue.open_door_manifest`'s drain (§12.4c) *is* this operation,
  performed in bulk with `reason_code='door_freeze'`.
- **Preconditions.** Listing `status='active'`. **A listing whose sale is `paid_pending_transfer` is NOT
  cancellable** — `precondition_failed('sale_in_flight')`: money is already taken and `market.sweep_paid_
  pending_sales` (§12.3) owns that row. This is the same exclusion `T-RPC-DOOR-12` asserts for the drain, and
  it must hold on the direct path too or the drain's exclusion is bypassable by one tap.
- **Locks & acquisition order.** **Listing (rank 4) `FOR UPDATE`** → **Ticket Atom (rank 5)** via
  `kernel.unlock_ticket` (`resale_state → 'none'`). Ascending. **SSCAS:** the unlock overlay, member #6
  reverse — the same classification §8.3 carries for #7 reverse.
- **Idempotency.** Terminal state + `p_command_key`; a re-cancel is `noop_replay`.
- **Writes.** `market.listing_native` (→ `cancelled`, `reason_code`), `kernel.tickets.resale_state` (→
  `none`, **via `kernel.unlock_ticket` only** — §0.7/§0.7a; the delegation was named in this contract's
  **Locks** line and not in its **Writes** line, which is `MB-6a`: its sibling §20.8.1 names it in both, and
  a Writes line that names the table and not the writer reads as a direct write). Where an auction or open
  offers hang off the listing, **`market.auction` → `cancelled` and every
  `pending` `market.offer` → `withdrawn` in the same transaction** — an offer against a cancelled listing
  that stayed `pending` would be a live commitment against nothing, and a buyer would see it in their app.
- **Result.** `{ status, listing_id, offers_withdrawn int }`.
- **Errors.** `insufficient_privilege` · `not_found` · `precondition_failed(sale_in_flight |
  not_active)` · `idempotency_replay`.
- **Forbidden callers.** Any non-seller client; every org and venue role; `platform_support`.
- **Test.** `T-RPC-MARKET-02` (cancelling a listing withdraws its pending offers and cancels its auction;
  a `paid_pending_transfer` listing raises `sale_in_flight` on the direct path **and** is excluded from the
  drain).

#### 20.8.3 `market.create_auction(p_listing_id, p_reserve_minor, p_min_increment_minor, p_anti_snipe_seconds, p_ends_at, p_command_key)` — **DB-RPC**

> **OWNER RULING `OR-11` (`Q-2`/`R-9`, 2026-08-29) — OPTION A: no native-rail auctions in MVP.**
> `create_auction` **MUST reject every native-rail listing** (`native_auction_not_offered`) — the mirror
> precondition below was FK-unsatisfiable anyway (no mirror writer exists), and the owner accepted that
> consequence knowingly. `market.auction` ships in `088` as **dormant substrate that can hold no rows**;
> this contract and §20.8.4 are **contracted-but-dormant**. `market.bid` does not exist in the MVP native
> rail; the finalize sweep is **vacuous in MVP** (proven a pure function of this ruling). Legacy
> external-rail auctions are unchanged. **An MVP scope decision only — not a permanent prohibition**; the
> post-MVP path is Option B's enumerated surface.

- **Authority.** the **listing seller** — RLS §11.1 (*"listing seller (create)"*), re-checked live against
  `market.listing_native.seller_id`.
- **Preconditions.** Listing exists, `status='active'`, `listing_mode='auction'`, and **has no auction**
  (`UNIQUE(listing_id)` — one auction per listing, schema §4.2); `min_increment_minor > 0`;
  `p_ends_at > now()` and within `config` bounds; `reserve_minor` (nullable) `>= 0`. The atom is already
  `resale_state='listed'` from §20.8.1 — **`create_auction` takes no atom lock and changes no overlay.**
- **Locks & acquisition order.** **Listing (rank 4) `FOR UPDATE`** (the parent, serialising against a
  concurrent cancel) → the `market.auction` INSERT. **SSCAS.** `n/a (single-aggregate — Listing class;
  `market.auction` is a Listing-class child written under the parent's lock)`.
- **Idempotency.** `p_command_key` + `UNIQUE(listing_id)`.
- **Writes.** `market.auction` (INSERT `active`, `current_highest_bid_minor := NULL`).
- **Result.** `{ status, auction_id, ends_at }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `conflict_locked` (auction exists) · `precondition_failed(listing_not_active | bad_increment |
  ends_in_past)` · `idempotency_replay`.
- **`ends_at` and the door boundary.** An auction may legally end **after** `effective_freeze_at`, and
  nothing here prevents it — but its finalize is a **custody move** and will be refused as `frozen`
  (§12.4c). **This function warns rather than refuses:** the result carries
  `{ ends_after_freeze bool, effective_freeze_at }` so the seller's UI can say so at creation time.
  Refusing outright would be wrong — a session's boundary can move (§20.6.5), and an auction on a
  multi-session event has no single boundary. `INFERENCE:` the warning field is authored; the corpus states
  the freeze and never connects it to auction scheduling.
- **Forbidden callers.** Any non-seller; every org, venue and platform role.

#### 20.8.4 `market.place_bid(p_auction_id, p_amount_minor, p_command_key)` — **DB-RPC** · `NEW RPC` — **the function the corpus never named**

> **Naming, stated plainly: `market.place_bid` is a name this document assigns.** RLS §11.1 grants EXECUTE
> to *"any `authenticated` (bid)"* on a row literally reading **`market.create_auction` / bid RPC**; plan
> `088`'s Functions row reads *"`create_auction`, **the bid RPC**, `make_offer`"*; schema §4.2's write
> authority reads *"`create_auction`, **the bid RPC**, the finalize sweep."* **(All three are MVP-dormant under `OR-11` — the sweep is vacuous, the bid ledger absent, `create_auction` rejects native listings.)** Three documents grant, schedule
> and assign write authority to a function none of them names. **Chosen to match the file's verb-first
> convention** (`make_offer`, `respond_offer`, `create_auction`, `create_listing`) and to avoid colliding
> with the EXT relation name `market.bid`.

- **Authority.** **any `authenticated`** — RLS §11.1 verbatim — **except the listing's own seller**, who is
  refused with `policy_violation('self_bid')`. `INFERENCE:` the seller exclusion is authored; *"any
  authenticated"* read literally permits shill bidding on one's own listing, which is a fraud primitive, not
  a capability. **Flagged for the owner** rather than silently assumed, because it narrows a granted row.
- **Preconditions.** Auction `status='active'` and `now() < ends_at`; listing `status='active'`;
  `p_amount_minor >= COALESCE(current_highest_bid_minor + min_increment_minor, reserve_minor,
  min_increment_minor)` — evaluated **under the auction row lock**, so two simultaneous bids cannot both
  clear the same head; `feature.native_resale_enabled` ON.
- **Locks & acquisition order.** **Listing/Auction (rank 4) `FOR UPDATE`** on the `market.auction` row, and
  **nothing else**. **It takes no rank-5 atom lock**, because a bid is not a custody event and the atom is
  already `listed`. **SSCAS.** `n/a (single-aggregate — Listing class)`.
- **Idempotency.** `p_command_key`; a replay returns the original bid outcome and does **not** re-raise the
  head.
- **Anti-snipe, and it is a write this function owns.** When a clearing bid lands within
  `anti_snipe_seconds` of `ends_at`, `ends_at := now() + anti_snipe_seconds` **under the same lock**. This is
  why the extension cannot live in the finalize sweep: by the time a sweep runs, the auction has ended.
- **Writes.** `market.auction` (`current_highest_bid_minor`, `ends_at` on an anti-snipe extension) — the
  **derived head** schema §4.2 describes as *"updated in the bid txn"* — **plus the bid ledger row, whose
  home is the open decision below.**
- **`OPEN DECISION` — the bid ledger's home, stated rather than invented.** §16.5 rules that MVP reuses the
  frozen external `public.bids` engine; schema §4.2 qualifies that with *"when the listing mirrors there"*;
  and schema §4.9 records `market.bid` as an **EXTENSION POINT**, explicitly **not created in `088`**.
  **Nothing resolves the native-only case.** The MVP position contracted here:
  1. **`market.create_auction` requires a listing that mirrors to `public.listings`**, so `public.bids` is
     the ledger and the frozen `auto-finalize-auctions` engine is the finalizer. `market.place_bid` writes
     the head and delegates the ledger append to the frozen path, **never re-implementing it** (I-10,
     SPEC_FOUNDATION §2).
  2. **A native-only auction is NOT offered in MVP.** `precondition_failed('native_only_auction_unsupported')`
     at `create_auction` time, not at bid time — failing at the first door rather than after a seller has
     collected bids.
  3. Lifting (2) requires the EXT `market.bid` ledger, which is a package change and an owner decision.
  **This is a proposal, not a ruling.** It is the reading most consistent with §16.5 and I-10; the owner may
  instead schedule `market.bid`. **Either way it must be decided before `088` is written, because an
  implementer facing this silence will create a `market.bid` table that no package specifies.**
- **Result.** `{ status, auction_id, current_highest_bid_minor, ends_at, is_leading bool }`.
- **Errors.** `insufficient_privilege(42501)` · `policy_violation(self_bid)` ·
  `precondition_failed(auction_ended | below_increment | below_reserve | listing_not_active |
  feature_disabled | native_only_auction_unsupported)` · `idempotency_replay`.
- **Forbidden callers.** the listing's seller; `anon`. **No role is required to bid** — bidding is a consumer
  capability.
- **Test.** `T-RPC-MARKET-03` (two concurrent bids at the same amount: exactly one clears and the other
  raises `below_increment`, asserted under real concurrency, not sequentially) · `T-RPC-MARKET-04` (a bid
  inside the anti-snipe window extends `ends_at`; the seller's own bid raises `self_bid`).

#### 20.8.5 `market.make_offer(p_listing_id, p_amount_minor, p_expires_at, p_command_key)` — **DB-RPC**

> **Freeze clause (`OR-17`, F-3):** refuses when the caller's `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).

- **Authority.** **any `authenticated`** — RLS §11.1 (*"any authenticated (offer)"*) — **except the listing's
  seller**, refused with `policy_violation('self_offer')` on the same reasoning as §20.8.4 and flagged the
  same way.
- **Preconditions.** Listing `active` and `listing_mode ∈ {buy_now, offer}` (an auction takes bids, not
  offers); `p_amount_minor > 0` and within the governing resale-policy cap → `policy_violation`;
  `p_expires_at` within `config` bounds, **server-clamped, never client-trusted**;
  `feature.native_resale_enabled` ON.
- **An offer moves no money and takes no hold.** It is a **stated intent**, not an authorization: **no
  `public.payments` row, no card authorization, no inventory hold, no atom lock.** The payment is verified
  at accept time by `respond_offer` (§20.8.6, C35). **An implementer who takes a hold here creates a
  capacity-consuming object with no sweep** — precisely the `G-24` failure this pass just closed in §20.3.3.
- **Multiple live offers per listing are legal, and a buyer may hold at most one.** A second `pending` offer
  from the same buyer on the same listing **replaces** the first (the earlier row → `withdrawn`, audited),
  rather than raising: raising the amount is the common case and two live offers from one buyer against one
  listing is a commitment they cannot both honour.
- **Locks & acquisition order.** **Listing (rank 4) `FOR SHARE`** — shared, because many buyers offer
  concurrently and none of them mutates the listing — then the `market.offer` INSERT. **SSCAS.**
  `n/a (single-aggregate — Listing class)`.
- **Idempotency.** `UNIQUE(buyer_id, command_idempotency_key)` (C16).
- **Writes.** `market.offer` (INSERT `pending`; the buyer's prior `pending` offer → `withdrawn`).
- **Result.** `{ status, offer_id, expires_at, replaced_offer_id }`.
- **Errors.** `insufficient_privilege` · `not_found` · `policy_violation(self_offer | above_cap)` ·
  `precondition_failed(listing_not_active | wrong_listing_mode | feature_disabled)` · `idempotency_replay`.
- **Offer expiry.** `market.offer.status='expired'` is reached by **the same sweep pattern as §12.2** — a
  `DEF` batch on the heartbeat. `INFERENCE:` the corpus gives `market.offer` an `expires_at` and an
  `expired` status label and **schedules no sweep**, which is the `G-24` shape again in a second place.
  Because an expired offer holds nothing, **it is not load-bearing** (unlike §20.3.3) — a stale `pending`
  offer is a UI wart, not consumed capacity — so it is folded into `market.sweep_expired_p2p_transfers`'s
  tick as a second statement rather than given its own function. **Filed in §20.14 for the plan owner.**

#### 20.8.6 `market.respond_offer(p_offer_id, p_decision, p_payment_id, p_command_key)` — **DB-RPC (SSCAS member #2 on accept)**

> **Freeze clause (`OR-17`, F-2):** refuses when **the offer's buyer**'s `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).

- **Authority.** the **listing seller** — RLS §11.1 (*"listing seller (respond)"*), live-rechecked.
  `p_decision ∈ {accept, decline, counter}`.
- **Accept is a native sale, and it is member #2 — not a new member.** §14.1 #2 already names its RPC cell
  *"`kernel.transfer_ticket_ownership` (called by market checkout / **`respond_offer` accept** / auction
  finalize)"*. This contract is what that parenthesis pointed at.
- **The expiry check is ARITHMETIC and is never the stored label (schema §13.7 `S-12`).** Under the offer
  row's `FOR UPDATE`, accept requires **`market.offer.expires_at > now()`**, evaluated on the row, **in
  addition to and regardless of `status`**. **`status='expired'` is written by the `088` sweep tick and the
  tick is presentational** (§20.8.5: an expired offer holds nothing, so the sweep is explicitly *not*
  load-bearing). An accept path that trusts `status='pending'` because the sweep was *supposed* to have run
  **consummates an expired offer every time the tick is late — which is the ordinary condition of cron**, not
  an incident. This is the same distinction §9.8 draws for door sessions and §17.11 for freeze overrides:
  **where a sweep is presentational, every consumer of the state must compute it.** Over-expiry ⇒
  `precondition_failed('offer_expired')`. **`T-RPC-MARKET-07`:** an offer past `expires_at` whose stored
  `status` is still `pending` (the sweep suppressed) is refused, and no `market_sale` row is written.
- **Preconditions on accept (C35, the ones that matter).** Offer `pending`, not expired; listing still
  `active`; atom still `resale_state='listed'` and owned by the seller; **`p_payment_id` resolves to a
  verified `public.payments` row whose buyer is `market.offer.buyer_id`** — re-verified against the live
  table, **the client-passed buyer is never trusted**; **`NOT kernel.is_transfer_frozen(atom)` → `frozen`**
  (the caller-level recheck of §12.4c; the enforcement point remains
  `kernel.transfer_ticket_ownership`, §7.2, which nothing bypasses).
- **The market writes its own row FIRST, then calls the kernel — C8, and the order is not stylistic.**
  `market.market_sale` is inserted (`sale_state='initiated' → 'paid_pending_transfer'`), **then**
  `kernel.transfer_ticket_ownership(cause='market_sale', cause_ref=sale_id, p_payment_id)` is called **in the
  same transaction**, which appends the ownership-log row, moves the head, **bumps `credential_version`**,
  clears `resale_state` and sets `terminal_state`. **The kernel never writes `market` and the market never
  writes custody** (§0.7). One cross-aggregate transaction per sale (§14.3).
- **Locks & acquisition order (member #2).** **Event/Session `FOR SHARE` (rank 1 — the freeze read)** →
  **Listing (rank 4) `FOR UPDATE`** → **Ticket Atom (rank 5) `FOR UPDATE`** → **Payment (rank 6) link**.
  Ascending — no inversion, and identical to §7.2's stated sequence.
- **Idempotency.** `UNIQUE(buyer_id, command_idempotency_key)` on `market_sale` **plus** the ownership-log
  `UNIQUE(cause, cause_ref, ticket_atom_id)`, which makes *"a double transfer of the same atom under the same
  sale physically impossible"* (§7.2). **Compensate-XOR-complete** holds on `market_sale.terminal_state`.
- **Decline and counter.** `decline` → offer `declined`, **nothing else touched**. `counter` → the offer is
  `declined` and a **new `pending` offer is written with the seller as its author** and the buyer as its
  recipient, so the same accept path serves the counter-accept and no second state machine is created.
  `INFERENCE:` `counter` is authored — RLS §11.1 grants *"respond"* without enumerating the verbs, and a
  negotiation surface with no counter is a decline button.
- **The losing offers.** On accept, **every other `pending` offer on that listing → `withdrawn`** in the same
  transaction, and the listing → `sold`. Leaving them `pending` against a sold listing would show buyers a
  live commitment against a ticket that is gone.
- **Writes.** `market.offer` (→ `accepted`/`declined`/`withdrawn` ×N), `market.listing_native` (→ `sold`),
  `market.market_sale` (INSERT), then via the kernel engine `kernel.ticket_ownership_log` +
  `kernel.tickets` + `kernel.payment_native`.
- **Result.** `{ status, sale_id, atom_id, credential_version, offers_withdrawn int }` — matching §7.2's
  shape, so the RN "Finalizing…" flip reads the same fields it reads for every other native sale (§1.4).
- **Errors.** `insufficient_privilege(42501)` · `payment_unverified` · `conflict_locked` · `frozen` ·
  `precondition_failed(offer_expired | listing_not_active | not_pending)` · `idempotency_replay`.
- **Forbidden callers.** Any non-seller; every org, venue and platform role; the buyer (they make and
  withdraw offers, they do not respond to them).
- **Test.** `T-RPC-MARKET-05` (accept with a payment belonging to a **different** identity raises
  `payment_unverified` and moves no custody — the C35 regression) · `T-RPC-MARKET-06` (accept withdraws every
  other pending offer and marks the listing `sold`; a replayed accept returns the original sale and appends
  no second ownership-log row).

#### 20.8.7 `market.mark_sale_paid_state(p_sale_id, p_payment_id, p_command_key)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (fence `market.market_sale` row; authored 2026-08-29)

> **The C25 clock had no writer.** `sale_state='initiated'` is the INSERT default; §12.3's sweep selects on
> `sale_state='paid_pending_transfer' AND paid_pending_since < now() - dwell_slo`; the RN "Finalizing…"
> poll (recon #2) resolves off the same state — and edge §4's `native_resale` row said *"mark `market_sale`
> `paid_pending_transfer`"* while naming **no function**. `paid_pending_since` occurred as a written column
> nowhere. Without this contract a paid buyer's sale never enters the sweep's predicate — **the exact
> unbounded dwell C25 exists to forbid.**

- **Purpose.** Record that Stripe reported the buyer's payment for an `initiated` native resale. **It moves
  no custody and calls nothing external** — the transfer is driven by the accept path or the C25 sweep,
  never by the webhook (edge §4).
- **Authority.** **`EXEC: DEF`** — `service_role` only, `REVOKE EXECUTE FROM anon, authenticated, public`,
  **no human path**: a principal who can mark a sale paid starts a custody-completion clock with no money
  behind it. Class B (`EA-3` B-ii).
- **Params.** `p_sale_id`; `p_payment_id` (uuid → `public.payments` — the frozen money-in row the webhook
  just recorded); `p_command_key`. **No `p_new_status`:** exactly one transition is webhook-drivable
  (`initiated → paid_pending_transfer`) — the `terminal_state` machine belongs to the engine and the C25
  sweep (C26), and `settled` is not a Stripe-reportable fact. A status parameter with one legal value is a
  second door (§20.7.6's reasoning).
- **Preconditions.**
  1. **Forward-only.** `initiated → paid_pending_transfer`. A row already there — or terminal — with an
     **equal** `p_payment_id` returns `noop_replay`; any other pair raises
     `precondition_failed('sale_state_backwards')`.
  2. **`p_payment_id` mandatory and write-once** — equal on replay, else `conflict_locked`. It is the value
     §7.2's C35 check verifies at transfer; a second value silently re-points which charge a custody move
     settles against.
  3. **C35 at the earliest moment:** `public.payments(p_payment_id)` must belong to
     `market_sale.buyer_id`, live-verified — a mis-joined payment fails **at the mark**, before it starts a
     completion clock → `payment_unverified`.
- **Locks.** `market.market_sale` row `FOR UPDATE` — **rank 4** (the rank `on_atom_voided` writes it at).
  Nothing else. **SSCAS:** n/a.
- **Writes.** `market.market_sale` (`sale_state := 'paid_pending_transfer'`, `paid_pending_since := now()`,
  `payment_id := p_payment_id`), `kernel.admin_audit` (`market_sale.state_sync`, before/after) in-txn.
  **Nothing else** — no listing, no atom, no `kernel.payment_native` (the resale link is born at transfer
  by the engine — `R-34`).
- **Result.** `{ status ∈ {updated, noop_replay}, sale_id, paid_pending_since }`.
- **Idempotency.** `p_command_key` + forward-only + equal-ref; a redelivered `payment_intent.succeeded`
  never raises.
- **Errors.** `not_found` · `precondition_failed('sale_state_backwards')` · `conflict_locked` ·
  `payment_unverified`.
- **Callers.** `stripe-webhook` (edge §4), keyed `metadata.rail='native_resale'` — the ONLY caller. **NOT
  the offer rail:** §20.8.6's accept verifies an existing payment and runs
  `initiated → paid_pending_transfer → completed` in one transaction; it never dwells and never calls this.
- **CONSEQUENCE, STATED BECAUSE IT BOUNDS THE CALLER SET.** This function updates a row that must already
  exist, so its live-caller population is the checkout that INSERTs `market.market_sale` at `initiated`
  **before** payment — §14.1 member #2's *"market checkout"*, which remains a MISSING CONTRACT (owner
  filing `R-37`). The ordering is pinned: `market.get_market_sale_status` (§1.4) polls by `p_sale_id`, so
  the row precedes the payment **by contract**; a webhook-INSERT variant is closed by recon #2, not merely
  disfavored. **`R-37` RULED OPTION B (`OR-22`, 2026-08-29): the caller exists — `market.checkout_buy_now` (§20.8.8)
  INSERTs at `initiated`; this contract and edge §4's `native_resale` branch are LIVE, and after this mark
  the webhook calls `market.finalize_market_sale` (§20.8.10) for prompt completion, with §12.3 the bounded
  backstop.**
- **Forbidden.** Every human role; any client; the offer-accept path; any caller supplying a status.
- **Tests.** `T-RPC-MARKET-08` (**completeness**: for each `sale_state` label a named writer exists; fails
  against the pre-fix corpus) · `T-RPC-MARKET-09` (foreign payment raises `payment_unverified`, no clock;
  equal-ref replay `noop_replay`, no second audit row; different ref `conflict_locked` — all three arms) ·
  `T-RPC-MARKET-10` (after the mark, a §12.3 tick past `dwell_slo` selects the row — the integration half
  proving the clock started).

#### 20.8.8 `market.checkout_buy_now(p_listing_id, p_command_key)` — **DB-RPC** · `NEW RPC` (R-37/`OR-22`, authored 2026-08-29)

- **EXEC:** `EXECUTE` to `authenticated`; fronted by the `resale-checkout` edge (Class A, EA-1 — caller-JWT
  client); buyer := `auth.uid()`, never a body field (C35). Direct PostgREST invocation is harmless: a
  PI-less reservation the lapse worker's NULL-ref arm releases.
- **SEAM-1:** writes `market.listing_native` + `market.market_sale` (`088`), `kernel.admin_audit` (`077`);
  reads `kernel.tickets` (`079`), `catalog.platform_config` (`078`) → `max(077,078,079,088) = 088` — the
  §20.8.7 arithmetic; **no edge added**.
- **Validation (order):** ① `feature.native_resale_enabled` ON → `precondition_failed('feature_disabled')`
  (the A-GATEM binding stands — the rail is architecture-complete and feature-dark until Gate-M + 2C);
  ② listing `status='active'` → `conflict_locked('listing_reserved')` if `reserved`,
  `precondition_failed('listing_not_active')` otherwise; ③ `listing_mode='buy_now'` →
  `precondition_failed('wrong_listing_mode')` (`INFERENCE` — offer-mode listings take offers, MVP position);
  ④ buyer ≠ seller → `policy_violation('self_purchase')` (the §20.8.4/§20.8.5 self-dealing family; closes
  the live rail's audit §2.2 MEDIUM); ⑤ atom live-read (no lock): `state='active'`,
  `resale_state='listed'`, `current_owner_id = seller` → `precondition_failed('atom_not_active')`;
  ⑥ `NOT kernel.is_transfer_frozen(atom)` → `frozen` (error-quality only; §7.2 is the enforcement);
  ⑦ price/split from the **listing's immutable policy snapshot** (§20.8.1 — no re-pricing), split-sums
  CHECK. **Deterministic amount: the total the edge charges is this RPC's return value — never edge- or
  client-computed (§3.1 rule).**
- **Reservation:** Listing (rank 4) `FOR UPDATE` serializes all contenders → `status := 'reserved'`; INSERT
  `market.market_sale` (`sale_state='initiated'`, `terminal_state='pending'`, buyer/seller/price/split,
  `reservation_expires_at := now() + config('resale.buy_now_reservation_ttl_minutes')` — server-set, never
  client, §5.3 pattern; seed 10 min, `078`). **No atom lock, no overlay change** (the §20.8.4 reasoning: not
  a custody event; `listed` already bars every other custody path). Race outcome: one winner; the loser
  fails ② under the lock; structural backstop **partial `UNIQUE(listing_id) WHERE sale_state='initiated'`**
  — the index, never a `NOT EXISTS` (§20.8.1's construction). The unique `initiated` sale IS the
  reservation record (owner = `buyer_id`, clock = `reservation_expires_at`) — one fact, one home.
- **Freeze clause (`OR-17`, F-2 rider):** refuses when the caller's `deletion_state = 'DELETION_PENDING'`
  (`kernel.is_deletion_pending`) — buy-now is buyer-side `market_sale` creation, the F-2 class.
- **Money:** none here (§6.1 shape). The edge then mints the PI (`metadata: {rail:'native_resale', sale_id,
  buyer_id, listing_id}`), records `public.payments` `pending` on the frozen path, and stores the ref via
  §20.8.9. Forward link in `kernel.payment_native` at transfer only (edge §9 recon #1, R-34).
- **Idempotency:** `UNIQUE(buyer_id, command_idempotency_key)` (C16) — replay returns the same
  `sale_id`/total; plus the partial unique.
- **Result:** `{ status, sale_id, listing_id, total_minor, currency, reservation_expires_at }`.
- **Emissions:** none — reservation-start is a ruled non-event (`#11 TicketReserved` = REMOVE, OR-3).
- **Consequences while `reserved`** (existing contract text, no edits needed): `make_offer` refused
  (`listing_not_active`, §20.8.5); `respond_offer` accept refused (§20.8.6); seller `cancel_listing`
  refused (`not_active`, §20.8.2) — **the seller cannot break a live reservation**; the door-freeze drain
  and `catalog.cancel_event` MAY cancel a `reserved` listing (they never touch the sale — a late payment
  resolves through §20.8.7 → C25).
- **Tests:** `T-RPC-MARKET-11`/`-12`/`-13` (§18.1).

#### 20.8.9 `market.bind_checkout_payment_ref(p_sale_id, p_payment_intent_ref, p_command_key)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (R-37/`OR-22`)

- **Why:** edge §4's own discipline — *"joined on the ref the executor stored, never on the PI"* — and the
  §20.7.6/§20.7.7 sibling shape (this records the `pi_…`). Without a stored ref the lapse worker cannot
  deterministically kill the right PI.
- **EXEC: DEF** — `service_role` only; called by `resale-checkout /begin` immediately after PI mint,
  **before** the client response (a delivered clientSecret implies a stored ref — the property the worker's
  NULL-ref arm relies on). Writes `market.market_sale.payment_intent_ref` (`088`) + `kernel.admin_audit` →
  `088`.
- **Validation:** sale exists, `sale_state='initiated'`; ref **write-once** — equal on replay →
  `noop_replay`, different → `conflict_locked` (§20.8.7 precondition 2, verbatim shape). Lock: sale row
  `FOR UPDATE`, rank 4. **Result:** `{ status ∈ {bound, noop_replay}, sale_id }`. **Emissions:** none.

#### 20.8.10 `market.finalize_market_sale(p_sale_id, p_command_key)` — **DB-RPC (SSCAS member #2 — "market checkout")** · `EXEC: DEF` · `NEW RPC` (R-37/`OR-22`)

- **This is the function §14.1 row 2's cell has pointed at since ratification** (*"called by market
  checkout"*). No new SSCAS member.
- **EXEC: DEF** — `service_role` only; callers: `stripe-webhook` (prompt, post-§20.8.7-mark) and
  `market.sweep_paid_pending_sales`'s complete branch for buy-now sales (late, per row). No human path.
  Writes `market.listing_native`, `market.offer`, `market.market_sale` (`088`) and calls
  `kernel.transfer_ticket_ownership` → `088`.
- **Validation (C35, live-recheck under lock):** sale `sale_state='paid_pending_transfer'`,
  `terminal_state='pending'`; `payment_id` set and `public.payments(payment_id).buyer_id =
  market_sale.buyer_id` re-verified (§20.8.6's C35 clause verbatim); listing `status='reserved'` and its
  unique live sale is this one; atom `state='active'`, `resale_state='listed'`, owner = seller; freeze via
  the engine (§7.2 is THE enforcement point).
- **Locks (member #2, ascending):** Event/Session `FOR SHARE` (1) → Listing (4) `FOR UPDATE` → sale (4) →
  the engine takes Atom (5) → Payment (6) — identical to §20.8.6/§7.2.
- **Writes (one txn — C8, order load-bearing):** listing → `sold`; every other `pending` `market.offer` on
  the listing → `withdrawn` (§20.8.6's losing-offers rule); then
  `kernel.transfer_ticket_ownership(cause='market_sale', cause_ref=sale_id, p_payment_id)` — ownership-log
  append, head move, `credential_version += 1`, `resale_state → none`, `kernel.payment_native` link born
  `instrument_fingerprint NULL` (ratified R-34/§7.2 — *"no webhook context at transfer time … not an
  oversight"*; the buy-now self-deal input is the `self_purchase` refusal at entry); `terminal_state :=
  'completed'`.
- **Custody progression (whole rail):** `initiated` (atom `listed`, seller custody) →
  `paid_pending_transfer` (mark; no custody change) → **completed** (engine move + credential bump; new
  pass via `credential-sign`) — XOR — **compensated** (§12.3: refund + void + mandatory `revoke` manifest
  delta; on a `scanned` atom, money-only per O-1).
- **Idempotency:** ownership-log `UNIQUE(cause, cause_ref, ticket_atom_id)` + terminal-XOR under the sale
  lock + `p_command_key` — a webhook/sweep race or replay yields exactly one custody move and returns the
  original result.
- **Failure:** `frozen` (leaves `paid_pending_transfer`; §12.3's frozen-exempt compensate resolves with
  refund) · `payment_unverified` · `conflict_locked` · `precondition_failed(listing_not_reserved |
  atom_not_active | not_paid_pending)`. Non-terminal failures leave the dwell clock running; C25 is the
  bound.
- **Emissions:** the engine's REQUIRED-RAISING `ownership_changed`/pass-supersession envelope fires inside
  `transfer_ticket_ownership` (R2 row 1 — callers inherit). This function itself BE-emits
  `purchase_confirmed` (existing type — no catalogue amendment; R2 row 26a), same-txn last write.
- **Tests:** `T-RPC-MARKET-14`/`-15`/`-17` (§18.1).

#### 20.8.11 `market.cancel_buy_now_sale(p_sale_id, p_reason_code, p_command_key)` — **DB-RPC** · `EXEC: DEF` · `NEW RPC` (R-37/`OR-22`)

- **EXEC: DEF** — `service_role` only; callers: `stripe-webhook` (`payment_intent.canceled` / TERMINAL
  `payment_failed`, resale arm) and `resale-checkout` (`/release`, `/sweep-lapsed`) — **never a client
  directly**: a client-callable cancel would sever a sale from a still-live PI (the orphan-money defect the
  PI-death gate exists to prevent). The buyer's abandon reaches it only through `/release`. Writes
  `market.market_sale`, `market.listing_native` (`088`) + `kernel.admin_audit` → `088`.
- **Validation:** forward-only, `initiated → cancelled` **only**; `paid_pending_transfer` or terminal →
  `precondition_failed('sale_state_backwards')` (money taken ⇒ §12.3 owns the row — the §20.8.2
  `sale_in_flight` money-wins priority); replay on `cancelled` → `noop_replay`. Reason ∈ `{buyer_released,
  reservation_expired, payment_failed, payment_cancelled}` — carried in the `kernel.admin_audit` row.
- **Locks:** Listing (4) `FOR UPDATE` → sale (4). **Writes:** sale `sale_state := 'cancelled'`; listing
  `reserved → active` **guarded** (only if still `reserved` and its live sale is this one — a
  drain/cancel_event may already have moved it; then skip the listing write). Pre-reservation `pending`
  offers untouched (made while `active`; actionable again).
- **Emissions:** none (the buyer-visible failure notice is R2 row 28's `purchase_failed` on the Stripe
  event, rail-agnostic). **Tests:** `T-RPC-MARKET-16`/`-17`/`-18`.

#### 20.8.12 `market.list_lapsed_checkouts(p_limit int DEFAULT 100)` — **DB-RPC (read)** · `EXEC: DEF` · `NEW RPC` (R-37/`OR-22`)

- `STABLE`, definer, `service_role` only — the `/sweep-lapsed` worker's read. Selects `market_sale` rows
  `sale_state='initiated' AND reservation_expires_at < now()` (partial index), `SKIP LOCKED`, returning
  `[{sale_id, payment_intent_ref}]`. No lease — the worker's ops are idempotent (PI-cancel + forward-only
  cancel), stated so nobody adds one. Not a writer — no fence row.

### 20.9 PROMOTER RECORDS AND LINKS — the `090` gap (`U-3`, `U-4`, `G-11`)

> **§17.15–§17.19 contract the promoter *code* RPCs and the promoter *read* RPCs. Nothing contracts the
> promoter *record* or the promoter *link*.** RLS §9.17 says only *"promoter CRUD"*; §11.5's block covers
> codes, attribution and reads and carries **no row for any function below**. `U-4` additionally requires a
> **live slug-availability read that does not exist** — *"the UI is required to check a global namespace
> against nothing."*

#### 20.9.1 `venue.create_promoter(p_org_id, p_identity_ref, p_terms, p_command_key)` — **DB-RPC**

> **Freeze clause (`OR-17`, F-7):** refuses when the enrolled identity's `deletion_state = 'DELETION_PENDING'` (`kernel.is_deletion_pending`; error per §0.5).

- **Authority.** `PROPOSED AUTHORITY` — RLS §11 has no row. Proposed: **the §11.5 promoter-code allow-list,
  unchanged** — `has_venue_role(venue, ['venue_manager','venue_promoter_manager'])` OR
  `has_org_role(['org_owner','org_admin','org_promoter_manager'])`, scoped to the promoter's org. Creating
  the promoter a code is minted for cannot require less authority than minting the code.
- **A promoter is not a role, and this function must not become a grant path.** Creating a
  `venue.promoter` row confers **no `venue.staff_role`, no `kernel.org_member` row and no platform role** — a
  promoter *"holds no row in any of the three authz tables, so every administrative predicate returns false
  for them and deny-by-default denies the capability without a policy having to say so"* (§1.1c). Their
  authority is **row ownership** (`venue.promoter.identity_id = auth.uid()`), tested live by
  `kernel.is_promoter_for_event` and by §17.19's reads. **`T-RPC-PROMO-12` (structural):** this function's
  definition writes none of `venue.staff_role`, `kernel.org_member`, `kernel.platform_role`.
- **Params.** `p_org_id`; `p_identity_ref` (email/handle/uid — **untrusted, resolved server-side**, and
  **nullable**: schema §3.17 permits an off-platform party, and `party_kind='affiliate'` is *"attributed by
  API key or link instead of a personal account"*); `p_terms` = `{ tier, party_kind, commission_kind,
  commission_bps | commission_flat_minor, currency, terms_version }`.
- **Preconditions — the commercial-terms XOR, enforced here and by the `090` CHECK.**
  `commission_kind='bps' ⇒ commission_bps` present (0–10000) and `commission_flat_minor` NULL; `'flat_per_
  ticket' ⇒` the converse. **A promoter with no terms at all is rejected** (plan `090` Tests). `tier ∈
  {professional_invited, public_ambassador}` and `party_kind ∈ {promoter, affiliate}` — the ratified label
  sets, re-validated in-body. `terms_version` is **server-assigned**, never client-supplied.
- **Locks.** None cross-aggregate (INSERT). **Admin plane. SSCAS.** `n/a`. **Idempotency.** `p_command_key`.
- **Writes.** `venue.promoter` (INSERT `active`), `kernel.admin_audit` (`promoter.create`, with the terms).
- **Result.** `{ status, promoter_id, terms_version }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `precondition_failed(terms_xor_violation | bad_tier | bad_party_kind)` · `idempotency_replay`.
- **Forbidden callers.** **A promoter creating another promoter**, `org_finance`, `venue_finance`,
  `venue_box_office`, `venue_scanner`, the door session, both marketing labels, `org_member`, fans, `anon`.

#### 20.9.2 `venue.update_promoter(p_promoter_id, p_patch, p_reason_code, p_command_key)` — **DB-RPC**

- **Authority.** As §20.9.1 (`PROPOSED`).
- **Terms changes are VERSIONED, never overwritten, and this is the contract's central property.**
  `venue.attribution` records `terms_version` per attributed sale, and §20.7.2 pays commission from **the
  version recorded on the attribution row**, not the promoter's current terms. So a terms change **writes a
  new `terms_version`** and **binds only sales attributed after it**. *"The terms in force at settlement
  rather than at sale would govern the commission"* is the failure §6.3 rules out; an in-place terms
  overwrite reintroduces it silently, changing the commission owed on sales that already happened.
  **`T-RPC-PROMO-13`:** a terms change leaves every existing attribution's `terms_version`, and the
  commission a subsequent close pays for those sales, **byte-identical**.
- **Patch set.** `tier`, `party_kind`, `commission_kind` + its amount, `currency`, `status ∈ {active,
  inactive}`. **Never writable:** `org_id`, `identity_id` (re-pointing a promoter record at a different
  person would silently reassign their earnings — the same no-reassignment property §17.15 enforces on codes,
  where *"changing `promoter_id` … is explicitly impossible"*), `promoter_id`.
- **`status='inactive'` is the deactivation control the product actually has** — see §20.9.4. It takes effect
  at the next `venue.resolve_order_attribution` (§17.14), which reads the promoter live; **it is not
  retroactive** and no recorded attribution is affected.
- **Locks.** The `venue.promoter` row `FOR UPDATE` (admin plane). **SSCAS.** `n/a`. **Idempotency.**
  `p_command_key`; a no-change patch is `noop_replay` and **issues no new `terms_version`** (version churn
  would make the attribution snapshots unreadable).
- **Writes.** `venue.promoter`; `kernel.admin_audit` (`promoter.update`, before/after terms, `reason_code`
  mandatory on a terms change).
- **Result.** `{ status, promoter_id, terms_version }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `invalid_input(unwritable_key)` · `precondition_failed(terms_xor_violation | reason_required)`.

#### 20.9.3 `venue.create_promoter_link(p_promoter_id, p_event_id, p_slug, p_command_key)` — **DB-RPC**

- **Authority.** As §20.9.1 (`PROPOSED`). **A promoter may not mint their own link**, on exactly §17.15's
  reasoning for codes: `venue.promoter_link.slug` is **globally unique** (schema §3.17) and the link is
  **IMM once created**, so a self-minted slug is *"a self-minted distribution surface over a global
  namespace"* and the grab is **permanent**.
- **Preconditions.** Promoter exists, `status='active'`, in the caller's org; `p_slug` passes the format
  CHECK; **`p_slug` is globally free** — enforced by `UNIQUE(slug)`, so a race surfaces as `slug_taken` from
  the index rather than from a check-then-insert.
- **The link is immutable once created** (schema §3.17). There is no `update_promoter_link`; correcting a
  slug means creating a new link and deactivating the promoter or the link (§20.9.4). **Stated because a
  well-meaning `update` RPC would break the `attribution.link_id` FK's meaning**: an attribution names the
  link that produced it, and re-slugging a link retroactively rewrites how a past sale was attributed.
- **Locks.** None cross-aggregate (INSERT). **Admin plane. SSCAS.** `n/a`. **Idempotency.** `p_command_key`;
  a replay returns the same `link_id`, while a **different** command key with the same slug returns
  `slug_taken` — **never a silent second link**, the same rule §17.15 states for codes.
- **Writes.** `venue.promoter_link` (INSERT), `kernel.admin_audit` (`promoter_link.create`).
- **Result.** `{ status, link_id, slug }`. **Errors.** `insufficient_privilege` · `not_found` ·
  `slug_taken` · `precondition_failed(promoter_inactive | invalid_slug_format | event_out_of_org)` ·
  `idempotency_replay`.

#### 20.9.4 `venue.set_promoter_link_status(p_link_id, p_status, p_reason_code, p_command_key)` — **DB-RPC** — **BLOCKED on an additive schema column**

- **The conflict, stated rather than worked around.** Dashboard `U-4` requires *"change link status."*
  **`venue.promoter_link` has no `status` column** — schema §3.17 defines exactly `link_id`, `promoter_id`,
  `slug`, `created_at` and marks the row **IMM once created**. And it **cannot be deleted**:
  `venue.attribution.link_id` is `FK … on delete restrict`, so any link that ever produced a sale is
  permanent by construction. **A control the dashboard requires is expressible against no column.**
- **What the product actually has in MVP, and it is sufficient.** Deactivating a promoter
  (`venue.update_promoter`, `status='inactive'`, §20.9.2) makes **every one of their links inert at the next
  `resolve_order_attribution`**, because §17.14 reads `venue.promoter` live. **Per-link deactivation is a
  finer-grained control than the corpus has a column for, not a missing capability.** A venue that needs one
  link dead today has: deactivate the promoter, or let the link resolve and adjudicate the attributions.
- **Contracted, and conditional.** If the owner schedules the column, this is its writer, and it must carry
  these properties: authority as §20.9.1; `p_status ∈ {active, inactive}`; **never retroactive** (no recorded
  attribution is affected, matching §17.15's rule for code status/scope/window); the `venue.promoter_link`
  row `FOR UPDATE` (admin plane); `SSCAS: n/a`; idempotent on `p_command_key` + terminal state; writes the
  status and `kernel.admin_audit('promoter_link.status')`; errors `insufficient_privilege` · `not_found` ·
  `precondition_failed(reason_required)`.
- **Filed for the schema owner (§20.14).** Either **add `venue.promoter_link.status text NOT NULL DEFAULT
  'active' CHECK (status IN ('active','inactive'))` to package `090`** — additive, on an unbuilt table, so
  it is a design edit and not a schema alteration — **or** the dashboard's `U-4` status control must be
  removed from the surface. **This document cannot make either change**, and until one is made the control
  renders against nothing.

#### 20.9.5 `venue.check_promoter_slug_available(p_slug)` — **DB-RPC (read)** · `NEW RPC` (`U-4`, `G-11`)

- **The read the UI is required to run and that does not exist.** Dashboard `U-4`: *"no availability-check
  read exists — the UI is required to run a live global-namespace check before enabling create, against
  nothing."*
- **Authority.** `PROPOSED AUTHORITY` — RLS §11 is silent. Proposed: **the §20.9.3 allow-list, and no
  wider.** **This must not be `authenticated`.** `venue.promoter_link.slug` is a **global** namespace: an
  open availability check is a **cross-tenant enumeration oracle** — anyone could map every promoter slug on
  the platform, which is competitive intelligence about who is selling for whom. The same reasoning makes
  `venue.preview_promoter_code` (§17.16) return a single `not_applicable` payload for every failure.
- **Returns.** `{ available bool }` — **and nothing else.** **No owner, no org, no promoter name, no
  created_at, no "taken by another org" distinction.** A caller learns only whether *they* may create it.
- **Advisory, and it says so.** The check is unlocked and **may lose to a concurrent create**;
  `UNIQUE(slug)` is the authority and `create_promoter_link` returns `slug_taken`. **The client must never
  persist the check as the answer** — same caveat as §17.16 and §20.6.3.
- **Rate-limited per principal, fail-closed** — an availability check called in a loop *is* the enumeration
  primitive the authority narrowing was chosen to prevent, so the narrowing alone is not sufficient.
- **Writes: none. Locks: none. SSCAS: n/a.** **Errors.** `insufficient_privilege(42501)` ·
  `invalid_input(bad_slug_format)`.
- **Test.** `T-RPC-PROMO-14` (an `authenticated` fan and an `org_owner` of a **different** org are both
  refused; the result payload is `{available}` and nothing else, asserted by field-list comparison so an
  oracle cannot creep back in through an added field).

### 20.10 `venue.get_dashboard_summary(p_scope_kind, p_scope_id)` — **DB-RPC (read)** · `NEW RPC` (`U-7`, `G-18`)

- **The least severe of the ten, and it is contracted rather than dropped so the decision is the owner's.**
  Dashboard §6.1 asks for every home tile in one round trip; **no delta spec adopted it**; home degrades to
  N queries rather than failing (`G-18`).
- **Authority.** `PROPOSED AUTHORITY` — RLS §11 is silent. Proposed: **the union of the authorities of the
  reads it aggregates, evaluated per tile, with denied tiles ABSENT from the result rather than null** —
  the identical construction §17.22 mandates for `venue.list_attendees` (*"column-scoped by role — and
  denied classes are ABSENT from the result shape, not null"*). A `venue_marketing` caller gets the audience
  tiles and **no money tile key at all**; a `venue_finance` caller gets the money tiles and **no contact
  tile key**. `has_org_role` / `has_venue_role` / `has_org_role_over_venue` decide, per tile, live.
- **This is the contract's whole risk, and it is why the construction is not negotiable.** An aggregate read
  is the classic place where a permission model quietly widens: one function, one grant, N projections, and
  the narrowest caller ends up seeing a number derived from data they may not read. **Absent-not-null is what
  makes over-exposure detectable by a key-set comparison in a test** rather than by reading the body.
- **Returns (per tile, each present only if authorized).** `{ sessions_today[], on_sale_count,
  tickets_sold_today, gross_today_minor, holds_active, comps_issued, door_open bool, scans_admitted,
  pending_refund_requests, pending_approvals, export_jobs_ready }`. **Counts and scalars only — no row
  lists, no attendee names, no order references.**
- **It aggregates; it must not re-implement.** Every number is derived from the same predicate its owning
  read uses (`venue.list_attendees` for audience counts, `kernel.list_org_payouts`/`list_org_refunds` for
  money, `venue.get_door_manifest`'s episode for `door_open`). **`T-RPC-DASH-01`:** for every tile and every
  role, the summary's value equals the value the owning read returns, or the key is absent — asserted across
  the full role × tile matrix, because a summary that computes its own answer is a second authority model.
- **Writes: none. Locks: none. SSCAS: n/a.** Rate-limited per principal (it is a home screen; it is polled).
- **Errors.** `insufficient_privilege(42501)` (only when **no** tile is authorized — a caller authorized for
  one tile gets that tile, not a 403) · `not_found`.
- **The owner's actual decision (`G-18`), stated so it can be taken rather than drifted into.** Accept N
  queries on home, or schedule this RPC. **Nothing else in the corpus depends on it**, so it may be deferred
  without blocking a package — which is precisely why it will be deferred by default unless named.

### 20.11 SEAM AND HOOK FUNCTIONS — plan objects with no contract

These **five** are **named as objects in migration plan §8** and contracted nowhere. **Four** of them are
**`CREATE OR REPLACE` seams**: a stub lands in one package and a later package replaces its body. An
implementer who does not know a function is a seam will either write the full body too early (and reference a
table that does not exist yet — the SEAM-1 failure the plan's §13 exists to prevent) or forget the
replacement (and ship a stub that silently returns nothing).

#### 20.11.1 `kernel.settlement_royalty_lines(p_settlement_id)` — **DB-RPC** · `EXEC: DEF` · SEAM-2

- **Signature.** `RETURNS SETOF settlement_line_candidate` — `{ cause, cause_ref, amount_minor, currency,
  payee_kind, payee_id }`. **A pure read that returns candidate rows; it inserts nothing.**
  `kernel.close_settlement` (§10.2) writes them.
- **Authority.** **`EXEC: DEF`** — `REVOKE EXECUTE FROM anon, authenticated, public`; called only by
  `close_settlement` inside the closing transaction. `PROPOSED` — plan §8 names the object and states no
  grant.
- **The seam, and both bodies.** Created in **`087`** as a stub returning **zero rows** — *"so a close at
  `087` is arithmetically complete without it"* (plan `087` Tests). Replaced in **`088`** by
  `CREATE OR REPLACE` adding the **`market_sale` royalty arm**, because `market.market_sale` does not exist
  until `088`. **A rollback of `088` must restore the `087` stub body** (plan `088` Rollback) — *"a rollback
  of `088` must not leave `settlement_royalty_lines` reading a dropped table."*
- **Locks: none** (it reads under the caller's Settlement lock). **SSCAS:** `n/a` — it writes nothing.
- **Idempotency.** Pure; `STABLE`. Determinism is required: **two calls in one transaction must return the
  same set**, or the settlement's arithmetic is not reproducible from its inputs.
- **Errors.** None — **it must not raise.** A raise here rolls back a settlement close.
- **Test.** Plan `088`'s own assertion, cited rather than renumbered: *"`settlement_royalty_lines` now
  returns rows for a seeded native sale (the stub was replaced, not merely present)"* — filed as
  `T-RPC-SEAM-01`.

#### 20.11.2 `kernel.settlement_commission_lines(p_settlement_id)` — **DB-RPC** · `EXEC: DEF` · SEAM-2

- **Signature / authority / posture.** As §20.11.1. Created in **`087`** as a zero-row stub; replaced in
  **`090`** adding the **`venue.attribution` arm**; the `090` rollback restores the `087` body.
- **Why the seam exists at all, which §16.7 already flags.** `kernel.close_settlement` is contracted in a
  package that **precedes the table it reads**: it reads `venue.attribution` and writes
  `promoter_commission` payouts, and the promoter package that *creates* `venue.attribution` lands later. The
  seam is the resolution — *"the settlement package defines `close_settlement` promoter-agnostic, and the
  promoter package issues a `CREATE OR REPLACE` adding the commission leg."*
- **It must honour the hold semantics of §17.18 / §20.7.2** — a flagged, unadjudicated attribution yields
  **no candidate row at all**, not a zero-amount one, because *"a zero line would consume the one slot"*
  under `090`'s cross-settlement `UNIQUE(cause_ref) WHERE cause='promoter_commission'`.
- **Test.** Plan `090`'s assertion, cited: *"`settlement_commission_lines` now returns a row for a seeded
  attribution"* — filed as `T-RPC-SEAM-02`, **plus** the negative: a flagged unreviewed attribution yields
  none (`T-RPC-MONEY-19`).

#### 20.11.3 `market.on_atom_voided(p_atom_id, p_refund_id, p_cause)` — **DB-RPC** · `EXEC: DEF` · SEAM-2

- **This function exists to preserve C8 in the one direction that is easy to violate.** §7.3 says
  `kernel.void_ticket_atom` writes *"`market.market_sale.terminal_state := 'compensated'` when driven by
  C25"* — **and §0.7 says the kernel never writes `market` tables.** The seam is how both are true: the
  kernel calls **`market.on_atom_voided`**, a `market`-owned definer primitive, in the same transaction.
  **This mirrors `venue.record_scan → kernel.mark_ticket_scanned` and `venue.open_door_manifest →
  catalog.engage_door_freeze` exactly** — *"the owning schema exposes a definer primitive and the calling
  schema invokes it in the same transaction"* (§17.12). **An implementer who writes
  `UPDATE market.market_sale` inside `kernel.void_ticket_atom` breaks the modular-monolith boundary and the
  `085`-before-`088` package order at once.**
- **Authority.** **`EXEC: DEF`**, `service_role` only. `PROPOSED` — plan §8 names it and states no grant.
- **The seam.** Created in **`085`** as a **no-op stub** (`market.market_sale` does not exist yet); replaced
  in **`088`** by `CREATE OR REPLACE` setting `terminal_state := 'compensated'`. A rollback of `088` restores
  the stub.
- **Preconditions & idempotency.** The sale row is located by `ticket_atom_id`; **if no sale exists the call
  is a silent no-op, not an error** — most voided atoms were never resold, and a void must never fail because
  the market layer has nothing to say. **Compensate-XOR-complete** is enforced under the sale's row lock: a
  `completed` sale **cannot** be flipped to `compensated` (`conflict_locked`), which is the C26 terminal
  state machine and the reason this is a function rather than an `UPDATE`.
- **Locks & order.** `market.market_sale` row `FOR UPDATE` — **rank 4 (Listing class)**. **The caller
  (`void_ticket_atom`, member #3) already holds Inventory(2) and is about to take Ticket Atom(5)**, so this
  acquisition sits **between** them and the sequence stays ascending: 2 → 4 → 5 → 6. **This is the one
  ordering fact the seam introduces and it must be honoured: `on_atom_voided` is called BEFORE the atom lock,
  not after.** `T-RPC-SEAM-03` asserts the call order structurally.
- **SSCAS.** `n/a` — it participates in member #3, adding no member.
- **Test.** Plan `088`'s assertion, cited: *"`on_atom_voided` flips a seeded sale to `compensated`"* —
  filed as `T-RPC-SEAM-03`, plus the XOR negative (a `completed` sale raises).

#### 20.11.4 `venue.normalize_promoter_code(p_code text) RETURNS text` — **IMMUTABLE STRICT** · not an RPC in the authority sense

- **The one function in §20 with no actor, no authority and no grant question.** It is `IMMUTABLE STRICT`,
  pure, and used inside a **unique index** — `UNIQUE(code_normalized)`, *"global — the only index on the
  checkout hot path"* (plan `090`). It is contracted here because **plan `090` names it and nothing states
  its contract**, and because its one operational property is severe.
- **`FROZEN ONCE `090` APPLIES WITH LIVE CODES`** — plan `090` states this and this document restates it as a
  contract term: **the function's output is baked into a unique index.** Changing its body silently
  invalidates every index entry computed under the old definition, so two codes that collided yesterday may
  not collide today and a lookup may miss a live code. **There is no migration that "just" changes it** — it
  requires a full index rebuild and a collision audit, and it must be treated as a data migration on the
  checkout hot path, not a function edit.
- **Behaviour.** Case-fold, trim, and collapse the Crockford-confusable classes (`O`/`0`, `I`/`L`/`1`) —
  which is what makes plan `090`'s assertion true: *"`UNIQUE(code_normalized)` rejects a second code
  differing only by Crockford-confusable characters after normalization."*
- **`STRICT` matters:** `NULL` in ⇒ `NULL` out, so a null code cannot normalize to the empty string and
  collide with another null. **`IMMUTABLE` matters:** without it Postgres refuses the expression index.
- **It reads no table and takes no lock.** Any future version that consulted a table would cease to be
  `IMMUTABLE` and the index would be invalid — **which is a second, independent reason the body is frozen.**

#### 20.11.5 `venue.on_payout_settled(p_payout_id)` — **DB-RPC** · `EXEC: DEF` · SEAM-2 (schema §1.9.2, defect `MB-2b`; filed as §13.7 `S-16`)

> **The fifth seam, and the one §20.11's own preamble did not know about** — it was created by the
> unwritable-control pass after this section was written, and it landed in the schema spec, the migration
> plan and the package registry **with no contract, exactly like the four above.** *"These four"* is now
> five; the count is corrected rather than left to read as a closed set.

- **Purpose.** Advance `venue.settlement` `closed → paid` when **every** `cause='settlement'` payout of that
  settlement has reached `status='paid'`. **It is the only writer of `venue.settlement.status='paid'`**
  (schema §3.13), which had no writer at `734c814` — `kernel.close_settlement` writes only `→ closed`.
- **Signature.** `(p_payout_id uuid) RETURNS void`. It takes the **payout**, not the settlement, because its
  caller is the payout state writer and the settlement is recovered from `kernel.payout.cause_ref`. A
  settlement parameter would let a caller assert a settlement is paid while naming a payout of another one.
- **Authority.** **`EXEC: DEF`**, `service_role` only; `REVOKE EXECUTE FROM anon, authenticated, public`.
  Called **only** by `kernel.mark_payout_transfer_state` (§20.7.6) inside the same transaction as the
  `→ paid` write. **No human path.**
- **Why it is a hook and not a function body inside the payout writer — SEAM-1 forces it.** It reads
  `kernel.payout` (`085`) and writes `venue.settlement` (`087`) → **`max(085, 087) = 087`**, while its caller
  lives in `085`. So `085` ships a **no-op stub** and `087` `CREATE OR REPLACE`s the real body — the
  identical construction as `market.on_atom_voided` (stub `085`, replaced `088`, §20.11.3). **`085 → 087` is
  already declared; no edge is added.** **A rollback of `087` must restore the `085` stub body**, per the
  rollback rule §20.11.1 states for the royalty seam.
- **It is ALSO the §0.7 boundary answer, and that is not incidental.** `kernel.*` may not write `venue.*`
  tables. The kernel payout writer therefore calls a **`venue`-owned definer primitive** in the same
  transaction — the same shape as `venue.record_scan → kernel.mark_ticket_scanned` and
  `kernel.void_ticket_atom → market.on_atom_voided`. **An implementer who writes `UPDATE venue.settlement`
  inside `mark_payout_transfer_state` breaks the modular-monolith boundary and the `085`-before-`087`
  package order at once.**
- **Preconditions & idempotency.** The settlement is located through `kernel.payout.cause_ref`; **if the
  payout's `cause <> 'settlement'` the call is a silent no-op, not an error** — a `market_sale` or
  `promoter_commission` payout has no settlement header to advance, and a payout must never fail because the
  settlement layer has nothing to say (the same rule §20.11.3 states for a voided atom that was never
  resold). A settlement already `paid` is a no-op. **`closed → paid` only:** an `open` settlement raises
  `precondition_failed`, because a payout for a settlement that never closed is a defect upstream and
  swallowing it hides it.
- **The completeness predicate is a NEGATIVE and must be written as one.** *Every* `cause='settlement'`
  payout of that settlement is `paid` ⇔ **no** such payout exists in a non-`paid` state. Written as a
  positive count it passes on a settlement whose second payout row has not been created yet. The read takes
  the settlement's payouts **under the settlement header's own `FOR UPDATE`**, so two concurrent
  `→ paid` transitions cannot both observe "one left" and neither advance, nor both advance.
- **Locks & order.** `venue.settlement` header `FOR UPDATE` — **admin/settlement plane, taken AFTER the
  caller's rank-6 payout row lock**, which is the one ordering fact this seam introduces and it must be
  honoured. **This is a settlement→payout inversion of §10.2's acquisition order and it is safe only because
  this path never takes a second payout lock:** it reads the sibling payouts in the same snapshot, it does
  not lock them. `T-RPC-SEAM-04` asserts the read is a read.
- **SSCAS.** `n/a` — it participates in no member and adds none; `venue.settlement`'s status column is a
  header field, not an aggregate write.
- **Writes.** `venue.settlement` (→ `paid`), `kernel.admin_audit` (`settlement.paid`). **It never writes
  `kernel.payout`** — the row that triggered it is already locked and written by its caller, and a hook that
  writes back into its caller's aggregate is how a re-entrant loop gets built.
- **Errors.** `precondition_failed` (settlement `open`). It must otherwise **not raise** — a raise here rolls
  back the payout state sync, so a settlement-layer disagreement would silently un-record a Stripe fact.
- **Tests.** `T-SCHEMA-SETTLE-01` (schema §1.9.2 — `paid` is reachable and is reached **only** when every
  settlement-caused payout is `paid`, asserted with two payouts, one still `submitted`) ·
  `T-SCHEMA-SETTLE-02` (the `085` stub is a no-op: it exists, returns, and changes no row — the SEAM-2
  property, asserted **at `085`** rather than after `087` replays) · **`T-RPC-SEAM-04`** (structural: the
  hook takes the settlement header lock and **no** payout row lock, and a `cause='promoter_commission'`
  payout is a silent no-op rather than an error).

### 20.12 §14.1 ADDENDUM — new RPCs mapped to EXISTING SSCAS members

**No row of §14.1 is rewritten and no member is added.** This table records which of §20's contracts
participate in a member that already exists, so §14.2's proof covers them without amendment.

| C12 # | Member | RPC(s) §20 adds as a **caller** | Acquisition sequence | Ascending? |
|---|---|---|---|---|
| 1 | Primary issuance | **`venue.issue_comp`** (§20.5.2) → `kernel.issue_ticket_atoms` | Inventory(2) → Ticket Atom(5, new) | ✔ |
| 2 | Native sale / resale (C8) | **`market.respond_offer`** accept (§20.8.6) → `kernel.transfer_ticket_ownership` — *already named in §14.1's cell; now contracted* | Event/Session(1, `FOR SHARE`) → Listing(4) → Ticket Atom(5) → Payment(6) | ✔ |
| 3 | Refund-void | **`kernel.admin_refund`** (§20.7.1); **`market.on_atom_voided`** (§20.11.3) inside it | Inventory(2) → **Sale(4)** → Ticket Atom(5, asc id) → Refund/Payment(6) | ✔ |
| 5 | Attribution → commission | **`kernel.pay_promoter_commission`** (§20.7.2) — the payout leg of §14.1's *"commission line"* | (Attribution **read**, unlocked) → Settlement(6) → Payout(6, fixed sub-rank) | ✔ |
| 6 | Native listing create | **`market.create_listing`** (§20.8.1) → `kernel.lock_ticket` — *already named; now contracted* | Listing(4) → Ticket Atom(5) | ✔ |
| 6-rev | Listing unlock overlay | **`market.cancel_listing`** (§20.8.2) → `kernel.unlock_ticket` | Listing(4) → Ticket Atom(5) | ✔ |

**Bounded batches of a single-aggregate operation, which are not members** (the construction §17.10 uses for
its drain): `venue.sweep_expired_inventory_holds` (§20.3.3) — Inventory(2) per row, rows ordered ascending
`batch_id` then `hold_id`, each row its own transaction.

**Everything else in §20 is `SSCAS: n/a (single-aggregate)`.** **The set stays closed at fifteen. No contract
in this section required a sixteenth member, and none was added.**

**The reconciliation pass's additions do not change that, and each is checked rather than assumed.**
`venue.mint_door_session` · `revoke_door_session` · `sweep_expired_door_sessions` (§9.6–§9.8) and
`venue.set_scan_device_status` (§20.4.3) touch **`venue.door_session` and `venue.scan_device` only** — schema
§3.10a places both on the **admin plane, outside the six ranks**, and `venue.door_session` *"joins no custody
sequence"*. `venue.revoke_door_pin`'s RV-1 cascade adds a second admin-plane row to a transaction that was
already admin-plane. The **one** addition that reaches a rank is `kernel.revoke_signing_key`'s door-episode
force-close (§20.7.5), which takes **`catalog.event_session` at rank 1 before the key row** — a single rank,
taken first, ascending across sessions, with no second rank below it: **not a cross-aggregate money or
custody sequence, therefore not a member.** The three CRM purge contracts and the demographics `unpublish_*`
pair write derived or lifecycle state and touch no money, custody or inventory row at all.

**One ordering fact §20 introduces**, recorded here because it is the only one: **`market.on_atom_voided`
takes rank 4 inside member #3, and must therefore be invoked BEFORE the rank-5 atom lock, not after**
(§20.11.3). This is consistent with §14.2's NB, which already pins **Inventory-before-Atom** in every void
path for the same reason — the void path is the one place in the corpus where a lower rank is naturally
reached for late.

### 20.13 NAMING REGISTER — the canonical name for every function with two (`G-20`)

**Two names for one function produces two functions or none.** Six divergences exist between RLS §11 /
dashboard §20A and this document's §2–§9. **This document is the canonical namer** (traceability `G-20`), and
§5's existing *"Naming reconciliation"* note establishes the convention: the schema/RLS name may remain the
**physical** function name, with the contract name as a documented alias. That convention is extended to all
six and to the three names §20 assigns.

| RLS §11 / schema name | Contract name (§) | Ruling |
|---|---|---|
| `kernel.grant_org_role` / `revoke_org_role` | `kernel.change_org_role` (§2.4) / `remove_org_member` (§2.5) | **Alias.** One function per pair; §16.6 already records it |
| `catalog.set_venue_approval` | `catalog.approve_venue` (§3.2) | **Alias** |
| `catalog.set_event_status` | `catalog.publish_event` (§4.2) | **Alias** |
| `venue.reserve_inventory` | `venue.reserve_primary_inventory` (§5.3) | **Alias** (§5's note) |
| `venue.release_hold` | `venue.release_inventory_hold` (§5.5) | **Alias** (§5's note) |
| `venue.create_order` | `venue.create_primary_checkout` (§6.1) | **Alias** |
| `venue.issue_door_pin` | `venue.create_door_pin` (§9.1) | **Alias** |
| `venue.record_offline_scans` | `venue.reconcile_offline_scans` (§9.5) | **Alias** |
| `venue.set_ticket_type_price` | *(unchanged)* — §20.3.1 | **Not a divergence**; it had no contract, now it has one |
| `catalog.set_resale_policy` | *(unchanged)* — §20.2.2 | **Not a divergence**; same |
| *"manifest-sync"* (unnamed) | **`venue.sync_scan_device_manifest`** (§20.4.4) | **NAMED HERE** |
| *"bid RPC"* (unnamed) | **`market.place_bid`** (§20.8.4) | **NAMED HERE** |
| the nightly holder-mix reconciliation (unnamed) | `venue.reconcile_holder_mix` (§17.20) | Named in §17.20; recorded here for completeness |
| `venue.set_door_open_at` | **— does not exist —** | **RULED OUT** (§20.6.5); the capability is re-homed as `catalog.set_session_door_schedule`. **RLS §11.4's row is now replaced — `AUTHZ-R1` DISCHARGED** |
| `venue.retire_scan_device` | **`venue.set_scan_device_status`** (§20.4.3) | **SUPERSEDED, not aliased** (schema §3.11.1 / §13.7 `S-11`). This document authored a one-way `retire`; the schema pass — which owns `venue.scan_device.status` — named a two-way setter and gave the reason: **un-retire must be permitted**, because a found device otherwise gets a duplicate row and **the scan ledger's device attribution fragments**, which is the property X-2 exists to protect. One function, `p_status ∈ {active, retired}`, carrying obligation **RV-2** |
| `venue.decide_flagged_attribution` | `venue.review_attribution_flag` (§17.18) | **DELETED, not aliased** (`AUTHZ-H10`, §17.18). Two functions writing one append-only ledger under opposite authority is not a naming divergence — it is two authorities, and `max(seq)` made the permissive one decisive. The survivor carries the restrictive allow-list |

> **`T-RPC-SET-02`:** exactly one physical function exists per row of this table. An alias that becomes a
> second `CREATE FUNCTION` is the failure `G-20` predicts, and it is invisible until two call sites disagree.

**Authored-not-transcribed names (the §17.20 `reconcile_holder_mix` convention; added 2026-08-29):**
`kernel.revoke_org_invite` (§20.1.6) · `kernel.sweep_expired_org_invites` (§20.1.7) ·
`venue.cancel_pending_order` (§20.7.9) · `market.mark_sale_paid_state` (§20.8.7) · `market.checkout_buy_now` / `bind_checkout_payment_ref` / `finalize_market_sale` / `cancel_buy_now_sale` / `list_lapsed_checkouts` (§20.8.8–§20.8.12, R-37/`OR-22`) ·
`kernel.write_demographic_erasure_tombstone` / `tg_identity_demographic_erasure` (§17.20a).
Each is the unique function three-plus documents pointed at by phrase or grant; only the NAME is authored —
authority, shape and package were derived, per each contract's own header.

### 20.14 REQUESTS TO OTHER INTEGRATORS — what §20 cannot fix in its own file

**This document owns `PHASE_2_RPC_FUNCTION_CONTRACTS.md` and edited nothing else.** Each item below is a
change another spec's owner must make; each names the file, the section and the reason.

> **`AUTHZ-R1`–`R4` are DISCHARGED.** The RLS spec is under the same remediation pass as this document, and
> §11 now carries: the replaced O4-3 row (`R-1`, §11.4), the fourteen reverse-difference rows (`R-2`, new
> §11.1a), rulings on all fifteen `PROPOSED AUTHORITY` sites (`R-3`, new §11.1c), and the four guest-list rows
> (`R-4`, new §11.1b). **`R-3`'s one rejection:** `venue.get_dashboard_summary` is **deferred, not accepted** —
> its existence is still owner ruling `R-10`, and §11 declines to be the document that decides it by writing
> a grant. The rows below are what remains outstanding.

| # | File | Change | Why it cannot wait |
|---|---|---|---|
| ~~R-1~~ | `PHASE_2_RLS_PERMISSION_SPEC.md` §11.4 | **DONE** — the `venue.set_door_open_at` (O4-3) row is replaced by `catalog.set_session_door_schedule`, same allow-list, with the schedule-vs-ledger-head reasoning recorded at the row | — |
| ~~R-2~~ | `PHASE_2_RLS_PERMISSION_SPEC.md` §11 | **DONE** — §11.1a carries all fourteen, `DEF` rows first | — |
| ~~R-3~~ | `PHASE_2_RLS_PERMISSION_SPEC.md` §11 | **DONE** — §11.1c rules on all fifteen; fourteen accepted (three narrowed), `get_dashboard_summary` deferred to `R-10` | — |
| ~~R-4~~ | `PHASE_2_RLS_PERMISSION_SPEC.md` §11 | **DONE** — §11.1b, §9.16's authority rolled up unchanged | — |
| ~~R-16~~ | schema §1.13 / plan `077` | **DONE by the schema pass** — `required_approver_class` and the three CHECKs landed, in the **three-label** spelling this document filed. This document now **writes** it in all three writers (§17.1, §10.3, §20.2.1) and **reads** it in §17.2 | — |
| ~~R-17~~ | schema (`kernel.org_member`) / plan `077` | **DONE by the schema pass** — `granted_at` landed; `kernel.money_role_grant_matured` is bound in §17.1, §17.2, §17.7 **and now §10.3** | — |
| ~~R-18~~ | plan §8 `078` | **DONE by the schema/plan pass** — the three keys are seeded and `comp.*` joined the dual-control namespace. **Extended here:** §20.2.1 adds `wallet.*`, `credential.*` and `door.session_*` (edge recon #16), and RLS §8.4 makes all seven `visibility='restricted'` | — |
| **R-19** | `PHASE_2_EDGE_FUNCTION_SPEC.md` §3.9a | **Two divergences between §3.9a and schema §3.10a, resolved here in favour of the pass that owns the table — §3.9a must be brought into line** (full reasoning: §1.1d `AUTHZ-H3a`). **(a)** The session's lookup handle is **`door_session_id`** (the uuid PK), not a `session_ref` text column — **no such column exists in §3.10a.1**. So the wire format is `DoorSession <door_session_id>.<secret>`, `token_hash = sha256(door_session_id::text \|\| ':' \|\| secret)`, and the derived limiter principal is `uuidv5(NS_DOOR_SESSION, door_session_id)`. **(b)** There is **no `/refresh` that extends a session without re-presenting the PIN**, and no `refresh_door_session` RPC is contracted; `/refresh` **re-mints** through §9.6 | §3.9a is unimplementable as written: it selects rows by a column the schema does not define, and its refresh route is the one property schema §3.10a.4 deliberately refused (*"a path that outlives the PIN"*). **The alternative for (a) is a one-column schema addition, not an edge edit** — but it must be decided in the schema, and until it is, an implementer following §3.9a writes a `session_ref` that nothing stores |
| **R-20** | `PHASE_2_EDGE_FUNCTION_SPEC.md` §3.9a · `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` | **`assert_door_session` returns the bound `(device_id, event_session_id)`, and the edge MUST pass that returned device id as `p_actor_device_id`** — never a value from the request, which is now **rejected** rather than ignored (`invalid_input`) if it appears in `p_scan_meta`. Also: **`venue.reconcile_offline_scans` takes `p_session_id`** (the assert is per `(device, session)`, so a batch spanning sessions cannot be bound to one) | §3.9a already states the obligation in prose (per-relay rule 3); the **signature** it must call is now fixed, and matrix **X-5** should cite it. A batch parameter that changed shape is a compile error the edge author must see, not a runtime surprise |
| **R-21** | **Owner ruling** (schema §13.7 `S-13`) | **`venue.set_event_security_config` is `⛔ BLOCKED`** (§20.6.6): it writes *"the per-event door-config rows"* and **no such table exists in any package.** Either schedule `catalog.event_security_config` into `078` (`restricted` visibility, AO per version) **or** rule the function out as `venue.set_door_open_at` was. **This document does not invent the table, and `086` must not schedule the function while it is BLOCKED** | A function scheduled with nowhere to write is unbuildable regardless of which keys it accepts. **This is separate from `R-11`**, which asks about the key set — answering `R-11` does not answer this |
| **R-22** | **Owner confirmation** (`MP-1`) | **The offline clock-skew time-bucket is `30 seconds`, so conjunct 3a's `± 2 time-buckets` is `± 60 seconds`** (§9.3). The corpus cited the bucket in **eight** places and defined its width in **none**; §9.3 now states it, as a **fixed protocol constant rather than a config key** — signer and long-offline verifier must agree, which a runtime-tunable value cannot guarantee. `INFERENCE — AUTHORED`: the magnitude is authored, not derived, and the owner should confirm it | **Not a blocker and not an open decision** — a tolerance with no width is unimplementable, so a number had to be stated rather than left for two scanner builds to each guess, and it is stated. What is owed is confirmation of the magnitude. Changing it later is a change to `OFFLINE-VERIFY-v1` (edge §5.4.3 first) plus a scanner-SDK release, **not** a config edit — so it is cheaper to confirm now than after the first build ships |
| **R-13** | `PHASE_2_ROLE_MODEL_SPEC.md` §11 R-16 + §12 row 17 · `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §21.4 | **Drop `venue.decide_flagged_attribution`** (`AUTHZ-H10`, §17.18). Δ7 and Δ4 are the same control; `venue.review_attribution_flag` is the sole writer of `venue.attribution_review` and now carries the restrictive allow-list | Two functions writing one append-only ledger under opposite authority meant the deny-list stopped nothing: effective decision is `max(seq)`, so the conflicted party appends `release` at `seq+1`. **Plan `090` never named the deleted function**, so nothing is left without a writer |
| **R-14** | `PHASE_2_ROLE_MODEL_SPEC.md` §5 (supersession clause) | **Add §11 to the list of sections §5.3 supersedes.** It currently names *"RLS §7.x/§9.x role rows and DA §7.6"* and **omits §11 — the one table that calls itself the authority model for every money and custody write** | This omission is the mechanism of `AUTHZ-H5`: ROLE_MODEL edit R-14 rewrote `venue_door → venue_scanner` lexically across §11, preserving capabilities §5 was simultaneously removing, and no clause said §5 governed. RLS §11.0 now states the rule from its own side and `T-RLS-EXEC-01` asserts it; **the role model should state it too, because a rule that only the downstream document knows is the rule that was just violated** |
| **R-15** | `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` | `G-8b(i)` is **closed on the specification side**: the C39 threshold now has keys (`comp.per_staff_step_up_max_units`, `comp.per_staff_step_up_window_hours`), a contract (§20.5.1) and tests (`T-RPC-AUTHZ-12/15`). It stays open on the **plan** side until `086`'s Tests row names them (`R-7`) | `G-8b(i)` records comps as *"asserted by neither surface"*; half of that is now false and the matrix should not keep asserting it |
| **R-5** | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §3.17 / plan `090` | **Add `venue.promoter_link.status`** (additive, on an unbuilt table), **or** the dashboard's `U-4` status control must be removed. **`AUTHZ-M10` adds two more to the same section:** **`venue.promoter.status`** (the `AND p.status='active'` conjunct in every corrected promoter predicate) and the **`venue.attribution.promoter_id`** (+ `org_id`, `event_id`) denormalization that RLS §9.17 has relied on since the attribution-write correction — **§3.17 lists only `link_id` today** | §20.9.4 is contracted against a column that does not exist. The link is IMM and FK-restricted, so there is no other expression of the control. And without `promoter.status` / `attribution.promoter_id`, **both the old promoter predicate and the corrected one are unwritable** — the difference being that the old one is unwritable *and*, if written as stated, silently false for every row |
| **R-16** | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.13 / plan `077` | **`kernel.approval_request` gains `required_approver_class`** (`NOT NULL`, `CHECK IN ('org','platform','platform_admin')`), the **`CHECK (state <> 'approved' OR approved_by IS NOT NULL)`** companion, the **`subject_kind` CHECK** and the **`action ↔ subject_kind` pairing CHECK**, plus index `(action, required_approver_class, state)`. Full text: RLS §17 **X-10** | **`AUTHZ-C1A`:** without the column the authority branch has nothing to read and every parked refund reaches the org arm. **`AUTHZ-M1`:** without the companion CHECK, *"SoD as a table constraint, not a convention"* is satisfied by any writer that leaves `approved_by` NULL |
| **R-17** | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` (`kernel.org_member`) / plan `077` | **`granted_at timestamptz NOT NULL DEFAULT now()`**, written by `accept_org_invite` and reset by `change_org_role` on promotion **into** a money role. RLS §17 **X-11** | **`AUTHZ-C1B`:** without it `kernel.money_role_grant_matured` cannot be written, and SoD-1/SoD-2 stay satisfiable by a counterparty the attacker minted through the ordinary invite flow |
| **R-18** | `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `078` (config seeds) | Three keys: **`authn.money_role_maturity_hours`**, **`comp.per_staff_step_up_max_units`**, **`comp.per_staff_step_up_window_hours`**; and **`comp.*` joins the money dual-control namespace**. All four of these plus `refund.platform_support_max_minor` must be documented **fail-to-safe** — an absent key means *no grant is mature* / *every comp needs step-up* / *support approves nothing*. RLS §17 **X-12** | A threshold that gates an authority and does not exist is not a gate. The `comp.*` pair is C39, cited in five documents with **no key anywhere**; `authn.money_role_maturity_hours` is new with `AUTHZ-C1B` |
| **R-6** | `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `081` | **Add `venue.sweep_expired_inventory_holds` to the Functions row and its assertion to the Tests row** | `G-24`. The index is built for a sweep the package does not create; without it held capacity never returns and every abandoned checkout removes inventory from sale permanently |
| **R-7** | `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `080`, `086`, `087`, `088`, `090` | **Add the §20 functions missing from the Functions rows** — `080`: `grant_/revoke_staff_role`; `086`: `sync_scan_device_manifest`, `check_in_guest_entry`, guest-list CRUD, `preview_door_open_impact`, `get_live_device_count`, `set_session_door_schedule`, **`mint_door_session`, `revoke_door_session`, `sweep_expired_door_sessions`, `set_scan_device_status`** (`AUTHZ-H3`), and **NOT `set_event_security_config`, which is `⛔ BLOCKED` (`R-21`)**; **`087`: `claim_artifacts_for_purge`, `confirm_artifact_purged`, `reconcile_export_orphans`, `assert_may_request`** (`AUTHZ-CRM2`) and **`077`/`082`: the two contact `_event` logs' writers** (`AUTHZ-CRM1`); `088`: nothing (all six are already listed); `090`: `create_/update_promoter`, `create_promoter_link`, `check_promoter_slug_available`. **Also `unpublish_holder_mix` / `unpublish_all_holder_mix`** in the demographics package | A contracted function with no package is a function nobody builds. §8 is where an implementer looks. **`venue.retire_scan_device` must NOT be scheduled** — it is superseded (§20.13), and scheduling both builds two writers for one column |
| **R-7a** | *(annotation to `R-7`, 2026-08-29)* | `R-7`'s "the demographics package" | **resolves to `086`** — schema §13.5-A moved the holder-mix pair there, and SEAM-1 places all three functions at `max(...)=086` (the unpublish pair writes `venue.holder_mix_snapshot` `086` + `kernel.admin_audit` `077`; reconcile reads only `086` relations). **And `R-7` omitted `venue.reconcile_holder_mix`** — contracted at §17.20 (authored name, flagged in §19), built by nothing, silently re-lost by every list that copied `R-7`. All three are now scheduled in plan/registry `086` | Writer-parity sprint |
| **R-8** | `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §20A.1 → §20A.2 | **Move the `venue.allocate_comp` / `venue.issue_comp` rows** out of *"mapped — write controls with a named RPC"* | `G-4`. §20A.1 asserts a contract that did not exist; the name existed and the contract did not. §20.5 now supplies it, so the rows may move to *"mapped"* only once §20 is merged — **and the earlier listing must not be cited as evidence that they were mapped** |
| **R-9** | **Owner ruling** | **The bid ledger's home** (§20.8.4 `OPEN DECISION`): accept "native-only auctions are not offered in MVP", or schedule the EXT `market.bid` ledger into `088` | §16.5, schema §4.2 and schema §4.9 leave it open in three different words. An implementer facing that silence creates a table no package specifies — and a bid ledger invented at build time is a money surface with no review |
| **R-10** | **Owner ruling** | **`venue.get_dashboard_summary`** (`G-18`): accept N queries on home, or schedule it | Nothing depends on it, which is exactly why it drifts. §20.10 makes it decidable |
| **R-11** | **Owner confirmation** | **`venue.set_event_security_config`'s key set** (§20.6.6) and **`kernel.revoke_signing_key`'s acknowledgement parameter** (§20.7.5) are `INFERENCE — AUTHORED`. Both narrow or extend a granted row | RLS §11.4 grants a function no document defines; §20.6.6 supplies a definition so it is not invented at build time, but the owner should confirm it rather than inherit it |
| **R-12** | `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `088` | **Fold `market.offer` expiry into the `088` sweep tick** (§20.8.5) | `market.offer` has `expires_at` and an `expired` label that nothing writes — the `G-24` shape a second time. **Not** load-bearing (an offer holds nothing), so it needs a statement, not a new function |
| **R-22** | **Owner ruling** (`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.13.4 · §13.7 `S-3`) | **THE PLATFORM-PLANE HALF OF THE GRANT-MATURITY CONTROL IS UNBOUND, AND THE RATIFIED SIGNATURE CANNOT EXPRESS IT.** Schema §1.13.4 defines the money roles as `{org_owner, org_finance}` (org plane) **and `{platform_admin, platform_support, platform_risk}` (platform plane)**, states that `kernel.platform_role.created_at` **already is** the platform grant time, and `S-3` accordingly asks that **the money arm of `set_platform_config`** carry the precondition. **C58's ratified form names only `kernel.org_member.granted_at`, and the ratified helper takes one argument — an `org_id` — which the platform plane does not have.** So `config.set_money_key` (§17.2, `required_approver_class='platform_admin'`) is gated by `auth.uid() <> requested_by` and a second distinct `platform_admin` (`AUTHZ-C1A2`) **and by no maturity floor at all** — which is the C58 attack one plane up: `kernel.grant_platform_role` is held by `platform_admin`, so a `platform_admin` can mint the second `platform_admin` that approves the raise of a money ceiling. **Two admissible forms, and the choice is the owner's:** (a) a **second helper**, `kernel.platform_money_role_grant_matured()` (no scope argument; reads `kernel.platform_role.created_at` against the same key), bound on the `config.set_money_key` arm of §17.2 and on §20.2.1's money arm — **a new control and therefore a new ratification, not a clarification**; or (b) **rule the platform plane out of scope** and retract schema §1.13.4's platform-plane sentence and `S-3`'s `set_platform_config` clause, so the corpus stops describing a control it does not have. **This document does not choose**: (a) extends a ratified control to a plane C58 did not ratify it on, and (b) deletes ratified schema text | The gap is invisible from either side on its own. Schema §1.13.4 reads as though both planes are covered; C58 and §1.1e read as though only the org plane was ever in scope; and the one function that spans them — `set_platform_config`'s money arm — is named by `S-3` and by no call site. **An implementer reading §1.1e alone will not know the platform arm is deliberately unbound, and an implementer reading §1.13.4 alone will try to pass an `org_id` that does not exist.** Recorded as ratification row **C77 / OPEN-GATED(O12)** |
| **R-23** | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.6 (global lock order) · `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.2 | **Confirm the accepted residual on `kernel.money_role_grant_matured` (§1.1e), or amend the lock order.** The helper reads `kernel.org_member` **unlocked**, so a `change_org_role` committing between the caller's snapshot and its commit is not observed. **Three of the four race directions fail closed** (a promotion into a money role, and a revoke, are both invisible to an older snapshot, which sees the pre-change row and returns `false`). **One is open for the duration of one transaction:** a money→money re-grant (`org_finance` → `org_owner`) resets `granted_at`, and a caller on the pre-reset snapshot passes. **§1.1e records this as an accepted residual and does not close it**, because closing it means putting `kernel.org_member` into the global lock order — an amendment to a ratified invariant (C28/§0.4), not a contract edit | The residual is small and bounded and the re-grant is itself an audited act by an already-authorized principal — but it is **exactly the direction the control exists to stop** (a freshly-authorized money principal acting), so it must be an accepted residual on the record rather than an unstated one. **A reviewer who later finds it should find this row, not discover it** |

| **R-24** | `PHASE_2_RLS_PERMISSION_SPEC.md` **§7.5** (and its **§5** quick-reference row) | **THE DOCUMENT THAT CALLS ITSELF *"the complete statement of Phase-2 write authority"* NAMES FOUR WRITERS OF `kernel.tickets`; THIS DOCUMENT CONTRACTS ELEVEN** *(corrected 2026-08-29 — this row itself said TEN while §12.5, authored later under `C109`/`S-22`, is the eleventh; the count is now derived from the enumeration, `OR-7` consequence map)*. §7.5 reads *"Write RPCs: `issue_ticket_atoms`, `transfer_ticket_ownership`, `void_ticket_atom`, `record_scan` (state→scanned)"* and §5's table reads *"same three + scan RPC"*. **Seven are missing, and one of the four listed is the wrong function.** Missing: **`kernel.mark_ticket_scanned`** (§7.5 here — the admission writer, i.e. 100% of admissions), **`kernel.lock_ticket` / `kernel.unlock_ticket`** (§7.4 — the `resale_state` overlay pair), and the **four money RPCs that write `resale_state` themselves** — `kernel.request_order_refund` (§17.1, `→ 'refund_hold'`), `kernel.approve_refund_request` (§17.2), `kernel.cancel_refund_request` (§17.3), `kernel.sweep_expired_refund_requests` (§17.4) — **and `kernel.sweep_expired_ticket_atoms` (§12.5, cron, `state → expired`), the eleventh, added to this document after this row was first filed and folded in 2026-08-29**. Wrong function: the fourth entry is **`record_scan`**, a `venue.*` wrapper — so **the authority statement's own list asserts a §0.7 violation as the design** (`venue` writing `kernel.tickets`), which is precisely the `G-20` *"two names for one function"* collision the traceability matrix already flags, here in the one table where the difference decides whether the `prosrc` freeze assertion covers the writer. **A writer absent from the authority list is a writer nothing reviews and no assertion counts** — the `C60` shape (§11 drifting from the role model with nothing able to see it), one table down. **Requested:** complete the list, replace `record_scan` with `mark_ticket_scanned`, and give it a structural assertion in the shape of `T-RLS-EXEC-01` — *every function that writes `kernel.tickets` appears in the authority statement*, derived from `pg_proc` rather than hand-maintained | Filed by `MB-6`. §0.7a now enumerates the sanctioned **delegation** set from the RPC side, which is the callee half; the RLS spec owns the **authority** half, and while the two disagree the corpus states two different write sets for its most security-critical table |
| **R-25** | **Owner ruling** (this document §7.4 · §17.1–§17.4 · `PHASE_2_MONEY_AUTHORITY_SPEC.md` §6.1–§6.3) | **FOUR MONEY RPCs WRITE `kernel.tickets.resale_state` WITHOUT GOING THROUGH THE `lock_ticket`/`unlock_ticket` OVERLAY PAIR, WHICH EXISTS SO THAT COLUMN HAS ONE WRITER PAIR.** They are `kernel.*` functions, so §0.7's `market`/`venue` prohibition does not reach them and **this pass changed nothing** — but §7.4 is the choke-point where the overlay's preconditions and the freeze re-check live (§12.4c: *"correct — a choke-point"*), and four functions setting the column beside it means the choke-point is one of five. **Two admissible forms and the choice is the owner's:** (a) **extend `lock_ticket`/`unlock_ticket` to carry `refund_hold`** (`p_reason` gains the label; §7.4's contract says `none→listed` / `none→locked` *"and back"* and would need the third pair) so `resale_state` has exactly two writers and the freeze re-check is unbypassable by construction; or (b) **keep the direct writes and say so explicitly** in §7.4 and in the RLS authority statement, with `T-RPC-MONEY-*` pinning that the money RPCs perform **no** freeze re-check on the release paths — a hold release must never be refused because doors opened, which is why (a) is not obviously right. **This document does not choose:** (a) changes a custody-engine contract, (b) ratifies a second writer set | Filed by `MB-6`. Not a defect in either direction today — §17.1 precondition 7 does check the freeze on the parked branch, and the release paths are correct to skip it. What is wrong is that **nothing states which of the two the design is**, so an implementer picks one per function |
| **R-27** | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.13 / plan `077` | **`kernel.approval_request` gains `amount_minor integer`** — NULL only for `action = 'config.set_money_key'`, with `CHECK (action = 'config.set_money_key' OR amount_minor IS NOT NULL)` and `CHECK (amount_minor IS NULL OR amount_minor > 0)`. Server-set at request time by the requesting function, **pinned exactly as `required_approver_class` and `config_versions` are** — never a parameter, never derived from `payload`. **Additive to a table already scheduled in `077`; no new table, no new package, no DAG edge, and `C72`'s pending second amendment is untouched** | **`MB-1`:** the cumulative tier operand (§17.1a) needs the **parked** exposure as an *authority* input, and no authority predicate may read `payload` (`T-RPC-AUTHZ-01`, structural). Without the column the parked term is unreadable, so the tier falls back to settled refunds only and **a parked request stops counting against the ceiling — reopening the split through the approval queue instead of the execute path.** This is `C57` one column over: **a tier decided from a value the row does not store is a control that does not run** |
| **R-28** | `PHASE_2_RLS_PERMISSION_SPEC.md` §3.1 + §11 · `PHASE_2_MONEY_AUTHORITY_SPEC.md` §8.4 Control 6 | **`kernel.record_money_denial` must LEAVE §3.1's definer-only exclusion list, and its §11 EXEC row must change from `DEF` to `EXECUTE` to `authenticated` only, EDGE-CALLER-JWT-bound.** §17.9 and edge §0.2/§3.4/§3.5 are fixed in this pass; MONEY §8.4 Control 6 must drop *"no human path"* | **`S-17`. The function is specified two mutually exclusive ways in six places across five documents**, and only one of them can be built: schema §1.12.1 has it RAISE when `auth.uid()` IS NULL, which a `service_role`-only function does on **every** call. **It cannot both raise on a service-role connection and be callable only on one.** §3.1's *"no human actor by construction"* is said of the one money RPC whose entire purpose is to name the human actor |
| **R-29** | `PHASE_2_RLS_PERMISSION_SPEC.md` §11.6 · `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `087` · `PHASE_2_PACKAGE_REGISTRY.md` `087` (`k3_named` + JSON) · `PHASE_2_CRM_EXPORT_SPEC.md` §9.5 | **`venue.assert_may_request` needs an EXEC row — and the class is now RULED: `DEF` (`Q-1`/`ID-6`, `OR-10` 2026-08-29; the first edition of this row instructed "`EXECUTE` to `authenticated`, `REVOKE` from `anon`, `EXEC: DEF`" — the contradiction itself; corrected to the ruling)** — RLS §11.6's row is applied as `DEF`; the plan and registry name a **four**-parameter signature that must become five: `(p_actor, p_scope_kind, p_scope_id, p_template_id, p_raise boolean DEFAULT true) RETURNS boolean` (§20.7.8, `R1-4`/`C108`). CRM §9.5 should **cite** the return shape rather than restate it | **It got a package number and nothing else.** A function three documents call, with no grant class stated, is a function whose migration author guesses between `authenticated` and `service_role` — and the guess decides whether `list_export_jobs` can compute `downloadable` at all. **The defaulted parameter is the whole return-shape resolution; a four-parameter signature in the plan silently re-opens the two-implementations defect `K-15` closed** |
| **R-30** | `PHASE_2_RLS_PERMISSION_SPEC.md` §11 | **`kernel.sweep_expired_ticket_atoms` needs an EXEC row** — `DEF`, `pg_cron`/`service_role` only, `REVOKE EXECUTE FROM anon, authenticated`. Contracted at §12.5 by this pass | **`S-22` asked for a contract AND an EXEC row and got neither.** The contract is now here; the grant is the half this document cannot write. A sweep with no stated grant class is the one function shape an implementer most reliably grants to `authenticated` |
| **R-31** | `PHASE_2_RLS_PERMISSION_SPEC.md` §11 · `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `085` · `PHASE_2_PACKAGE_REGISTRY.md` `085` | **Three money state-sync functions need EXEC rows and two need plan/registry object entries.** EXEC rows (all `DEF`, `service_role` only, `REVOKE EXECUTE FROM anon, authenticated, public`, **no human path**): `kernel.mark_payout_transfer_state` (§20.7.6), `venue.on_payout_settled` (§20.11.5), **`kernel.mark_refund_state`** (§20.7.7). Plan/registry `085` must additionally gain **`kernel.mark_refund_state`**, the **partial unique on `kernel.refund.stripe_refund_ref`** and the **`CHECK (status = 'pending' OR stripe_refund_ref IS NOT NULL)`** (schema §1.10.1) | The first two are the `S-16` pair — in the schema, the plan and the registry, and in **zero** contracts and **zero** EXEC rows. The third is the same defect one table over, found by this pass: `kernel.refund`'s only writers all INSERT at the `pending` DEFAULT, so three of four `status` labels were unreachable and `stripe_refund_ref` had **zero writers and zero readers corpus-wide**. **SEAM-1 places all three where they already are (`max(077, 085) = 085`; the hook body at `087`); no package and no edge changes** |
| **R-32** | `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §14.5 · §14 (settlement panel) | **(a)** `S-21`, restated because it is still open: the three payout pills are three straight column reads — *held* = `hold_state='held'`, *on probation* = `hold_state='probation_hold'`, *failed* = `status='failed'`; **`status` never carries a hold** and `status='held'` never existed. **(b)** The settlement panel's four figures are straight header reads and are **NULL until close** (schema §3.13.1) — render *"not yet closed"*, never zeroes | (a) §14.5 states *"They must never render as one pill"* as a working requirement; naming the column is what stops the implementer deriving the probation pill from the **absence** of a `payout.hold` audit row, the construction `AUTHZ-M1` refuses. (b) **Zero and unknown are the same pixel and only one of them is a bug** — and until this pass the four columns had no writer at all |
| **R-33** | `PHASE_2_MONEY_AUTHORITY_SPEC.md` §8.4 Control 4 · §12 | **Restating `S-14`, which is still open:** Control 4's *"created at status `held` rather than `submitted`"* must become *"created `pending` by `close_settlement` and **not advanced** to `submitted`, carrying `hold_state='probation_hold'`"*, and §12's `NO SCHEMA CHANGE` must become **`SCHEMA CHANGE` — four additive columns on `kernel.payout`**. RPC §17.7 control 2 and §10.3's probation arm are fixed in this pass | **`kernel.payout.status='held'` does not exist and is not being created.** While §8.4 still says it, the two documents disagree about the physical representation of the one control that stops money reaching a freshly-changed destination — and §12's classification is what a migration author reads to decide the package needs no DDL |
| **R-34** | `PHASE_2_RLS_PERMISSION_SPEC.md` §7.8 + §5 · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.8 | **`kernel.payment_native`'s writer set is `venue.finalize_primary_order` (§6.3) + `kernel.transfer_ticket_ownership` (§7.2) — TWO, with `market.accept_p2p_transfer` (§8.2) and `market.respond_offer` (§20.8.6) as delegating callers through the engine.** Both derived documents named `kernel.issue_ticket_atoms` (whose Writes line does not name the table) and omitted the actual writer of every primary-purchase link; schema §1.8's *"written by issuance / native-sale engines"* and its *"only"* are competing definitions, not restatements. Filed under `OR-7`: the registry governs, derived lists agree exactly or point. **The §8.2 ambiguity (X-1's "2 or 3") is closed in this document — §8.2's Writes line now carries the delegation form, 2026-08-29.** `instrument_fingerprint`'s writer is **DISCHARGED 2026-08-29**: `venue.finalize_primary_order` (§6.3) writes it from the webhook-supplied parameter; the resale link is born NULL (§7.2); membership unchanged at two — the X-1 `R-` filing the consequence map demanded is this row | Writer-parity pass, 2026-08-29 |
| **R-35** | this document §20.0e (registry) · `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `079` Triggers row · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.5 | **`kernel.set_updated_at` is a WRITER (kind `trigger`) under `OR-7` and has no contract and no complete attachment map; and `079` attaches NO `updated_at` maintainer to `kernel.tickets` while schema §"Global conventions" states mutable rows' `updated_at` is *"maintained by the existing `set_updated_at` helper trigger pattern"* and the column exists on the atom.** The schema's own rule uniquely determines the answer — the attachment is required — so this is a MECHANICAL CONTRACT/PLACEMENT omission, not an owner decision; but scheduling the trigger is the plan owner's build edit and creating it is Phase-2 implementation, so **this row FILES it and this pass builds nothing**. The registry carries it as MISSING_CONTRACT until contracted | Writer-parity pass, 2026-08-29 |
| **R-36** | this document §20.1.6-adjacent · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.3b · dashboard :1125 | **`org_invite.status='declined'` has no writer and no granted verb — OWNER.** RLS §7.3b gives the invitee exactly one EXEC (accept); adding a decline verb extends a closed authority set (`R-11` class). Two dispositions: (i) grant `kernel.decline_org_invite` (invitee-only, `pending → declined`) — then transcription-grade; (ii) strike `declined` from the enum (three sites) — an unwanted invite lapses; the smaller surface, and the dashboard's own §687 house principle is that declining is indistinguishable from silence. **CLOSED — OWNER RULING `OR-18` (2026-08-29): disposition (ii) — `declined` STRUCK at all three sites (schema §1.3b · plan §8 `077` · dashboard §15.1); no decline RPC is authored; the invitee's single EXEC (accept) stands; the fence's `kernel.org_invite` row is parity-true on the four-label enum; any future decline verb is a new reviewed contract (`R-11` class)** | Sprint agent 2, 2026-08-29 |
| **R-37** | RN §4.3b · this document §14.1/§20.8.6/§20.8.7 · edge spec §4 | **The native-resale money-in leg has NO designed write path and the surface is RATIFIED** — "market checkout" is a phrase, not residue: RN §4.3b contracts buy-now purchase, and §20.8.7's writer is a dormant pair with edge §4 until the INSERT-at-`initiated` checkout exists. OWNER: (i) descope direct buy-now from MVP (RN §4.3b reduces to the offer rail — whose own payment mint STILL needs a smaller design); or (ii) commission the design (one edge + one DB-RPC + the `reserved`-state ruling — RN :590 expects a listing state the schema enum lacks — + RLS row + fence + `088`). Triple-gated dark in MVP, which is why no gate tripped. **RULED OPTION B — `OR-22`, 2026-08-29: commissioned as §20.8.8–§20.8.12 + the `resale-checkout` edge (18th) + the `reserved`/`cancelled` labels + the 078 TTL seed; reserved semantics DERIVED, not ruled; ZERO new dependency edges; the rail stays feature-gated dark until Gate-M + 2C (A-GATEM stands — activating earlier is one explicit owner amendment of that binding); the offer-rail payment mint remains the surviving residual, filed** | Sprint agent 2, 2026-08-29; ruled 2026-08-29 |
| **R-38** | `kernel.payout` "native-sale payout path" · MONEY §2.1/§10.5 · DA C29-C31 | **CLOSED-AS-GATED 2026-08-29 (`C135`) — BOUND TO GATE M; no owner bit exists.** The identity-payee `cause='market_sale'` INSERT and its disbursement timing are Gate-M policy by ratified text (C29/C30/C31 RATIFIED-MODELED-ONLY(GATE-M) · MONEY §9.4 · the A-GATEM `feature.native_resale_enabled` binding · OR-11), and the rail is unreachable in MVP — so by OR-7's own definition the writer is NOT "structurally required" and MISSING_CONTRACT was the wrong fence code. Fence row reclassified to the ratified-gate `c` encoding (`kernel.GATEM_NATIVE_SALE_PAYOUT`); the contract is owed by the Gate-M amendment and may not be closed by build-time invention. F-P2-1's obligation record does NOT close this (it books debt, not disbursement); R-37 commissions only the money-in leg and leaves this untouched | Sprint agent 2, 2026-08-29 · reconciled 2026-08-29 |
| **R-39** | CRM §4.3/§11.2 · this document §2.1/§17.22 | **`org_customer_key`: (a) MINT site is a genuine 2-way choice** — at `create_organization` (in-txn, literal reading) vs lazily at first `request_export` (`ON CONFLICT DO NOTHING`; strictly smaller blast radius — no secret for orgs that never export). Both satisfy every stated property; once ruled, transcription-grade. **(b) ROTATION has no physical carrier** for its own coupled side-effect (the template-version bump + venue notice ride an object no document defines, and the notice carrier is the gated notify plane) — rule the carrier (and whether rotation is Phase-2 at all; CRM frames it as incident response) before any contract. **CLOSED — OWNER RULING (2026-08-29): (a) `OR-19` — minted LAZILY inside the first successful `venue.request_export` (§17.22 mint clause; the table's ONLY writer; not `create_organization`, never the builder — X-6/O17 surface unchanged); (b) `OR-20` — rotation DEFERRED to the incident-response/security runbook (owed artifact `ORG_CUSTOMER_KEY_ROTATION_RUNBOOK`, filed in the owner decision queue's engineering register); rotation is exceptional, never routine; no carrier object is authored, the notification set is not amended for it, and any future automated rotation requires a new reviewed contract** | Sprint agent 2, 2026-08-29 |
| **P0-1** | plan §8 Scheduled-ticks rows ×4 · production `014_frequent_cron_schedules.sql` | **THE SHARED 2-MINUTE HEARTBEAT DOES NOT EXIST** (red-team, 2026-08-29): production's only 2-minute jobs are two single-purpose entries; no dispatcher function exists in any band package; five load-bearing sweeps ride the phrase and `sweep_expired_refund_requests` had no Scheduled-ticks row at all. **The false premise is corrected at every plan site; each sweep now names an explicit per-package `cron.schedule` obligation. ENGINEERING CHOICE FILED, not taken: one dispatcher function vs per-job entries** — two admissible forms; the per-job form is the written default until ruled | Red team, 2026-08-29 |
| **R-26** | **Whoever owns the corpus-wide id scheme** (the hazard this record already documents for `R-`, `K-`, `O`/`O-` and `S-`/`D-`) | **`R-22` IS USED TWICE IN THIS TABLE, FOR TWO UNRELATED ITEMS.** One `R-22` is `MP-1`'s offline clock-skew time-bucket confirmation; the other is the platform-plane grant-maturity owner ruling (`C77`/`O12`), which schema §13.7 `S-3` and RLS §11.3a both cite **by that id**. Two rows with one id is the `O3`/`O-3` mistake inside a single table, and the second one is load-bearing in three documents. **Requested:** renumber one of them — **not** the `C77`/`O12` row, which is cited externally — and state the rule that `R-` ids are allocated by reading the table's current maximum, the same discipline the ratification record states for its own rows | Found by `MB-1`/`MB-6` while allocating this pass's ids. **Not fixed here**, because renumbering a row two sibling documents cite is exactly the change that must not be made unilaterally by a pass that owns neither |

---

### 20.15 `public.delete_account_cleanup(p_user_id uuid)` — **LIVE `public.*` WRITER — FROZEN, not a Phase-2 RPC** (declared 2026-08-29)

> **Why this section exists.** The function is live in production and *"appears in no write-authority row of
> any spec"* (schema §5.1's own words). Under `OR-7` a live writer with no canonical declaration is a
> MISSING CONTRACT; this section is the declaration. **It is a transcription of the PRODUCTION body**
> (migrations `020` → `0551` → `0563`; write set enumerated from the SQL, not from prose) — chosen by the
> schema spec's own method, *"read from the applied migrations."* **It confers no new authority and this
> document does not own its behavior** — the frozen Stripe/public core does.

- **Write set (production, exact):** `public.listings` — UPDATE: own-live-auction cancel
  (`auction_status→'cancelled'`, `status→'active'`, `reserved_by/reserved_until→NULL`, `ended_at`) and
  `seller_id → sentinel` (identity-guard trigger disabled/re-enabled around it) · `public.payments` —
  UPDATE `buyer_id`/`seller_id → sentinel` · `public.transfers` — UPDATE `buyer_id`/`seller_id → sentinel`.
  **Nothing else** — no profiles (auth CASCADE), no storage (the edge function's job), no favorites, no
  notifications, no bids.
- **Binding constraints, restated not invented:** `CUSTODY-DEL-1` (schema §5.1 — this function must never
  be extended to touch Phase-2 custody) and demographics `D-11` (it must never be pointed at
  `kernel.identity_demographic` — the tombstone trigger, not sentinel repointing, is that table's removal
  discipline).
- **⚠ DECLARED FOLLOW-UP OBLIGATION — PR #28.** The open, unmerged hotfix (`fix/account-deletion-residue`,
  migration `20260828041500`) **extends the write set to SIX tables**: + `public.bids` (DELETE),
  + `public.seller_flags` (`reviewed_by → NULL`), + `public.stripe_connect_archive` (`profile_id →
  sentinel`), plus listing-head reconciliation, reservation release, `dispute_resolved_by → NULL`, and the
  two image-path rewrites. **On merge, this section and the writer registry MUST be re-derived to the
  merged body** — three new registry rows are required at that point. Declaring the unmerged body today
  would declare authority that does not exist in production.
- **⚠ CUTOVER (`OR-17`, F-P0-1/A):** from the `077` apply — same release train — the deletion request
  surface switches to `kernel.request_account_deletion` (accept-into-DELETION_PENDING, §20.17). PR #28's
  request-time 409s retire (transfer 409 → BP-7; `dispute_resolutions` 409 lifts per 16d);
  `auth.admin.deleteUser` is called by nothing; this function is invoked by the terminal live-clear arm's
  residue only as the §4.5/§5 policy fold determines, is never extended to any `kernel.*` relation
  (CUSTODY-DEL-1), and F-P1-5's retention side-table rider governs the pre-cutover interim.

### 20.16 `kernel.set_updated_at()` — **TRIGGER WRITER — the `updated_at` maintainer** (contracted 2026-08-29, `R-35`)

- **Kind:** `trigger` (`BEFORE UPDATE FOR EACH ROW`; sets `NEW.updated_at := now()`). Created in package
  `076` (plan §8); **attached per table by each package's Triggers row**. Never `EXECUTE`d by a principal;
  holds no grant class (§20.0a) — but under `OR-7` it IS a writer and this is its registry identity.
- **Attachment map (the schema census, complete):** `077` `078` `081` `082` `085` `087` `088` `091` attach
  it to their MUT tables (per-package Triggers rows), and — **added 2026-08-29, the R-35 census
  correction** — `079` (`kernel.tickets`), `083` (`kernel.signing_key`, `kernel.wallet_pass`,
  `kernel.pass_type_cert`), `086` (`venue.scan_device`, `venue.comp_allocation`, `venue.guest_list`,
  `venue.guest_entry`), `090` (`venue.promoter`, `venue.promoter_link`). **The prior record claimed
  `kernel.tickets` was the only required-but-not-attached site; the census refutes that — TEN tables across
  FOUR packages lacked the maintainer** the schema's own global convention requires (*"Mutable rows carry
  `updated_at` (maintained by the existing `set_updated_at` helper trigger pattern)"*). One rule, one
  admissible map, no owner decision.
- **What it never does:** no write to any column but `updated_at`; no raise; no read. `wallet_pass.last_updated_at`
  is a distinct business column (`touch_wallet_pass`'s) and is NOT this trigger's.
- **Registry treatment:** CATEGORY writer — carried once here rather than repeated on ~40 fence rows.

### 20.17 THE DELETION STATE MACHINE — the `OR-17` fold (F-P0-1 Option A, 2026-08-29)

> Normative machine: `_governance/DELETION_STATE_MACHINE_SPEC.md` (OR-13). Everything here ships in `077`
> (cutover ≤ the `077` apply, same release train) except the hook bodies, which land in their operand's
> birth packages (`079`/`080`/`082`/`083`/`085`/`086`/`088`/`090` — registry hooks array).

#### 20.17.1 `kernel.request_account_deletion(p_command_key)` — **DB-RPC**

- **EXEC:** `authenticated` — own identity only; **no identity parameter** (the §17.21 discipline; the
  subject is `auth.uid()`, always).
- **ALWAYS ACCEPTS** (§1.1 of the machine): no request-time refusal exists. Creates the `kernel.identity_ext`
  row lazily if absent; sets `deletion_state := 'DELETION_PENDING'`, `deletion_requested_at := now()`,
  `deletion_block_reason := NULL`.
- **In the same transaction:** Q5 auto-expiry — every **pending** `kernel.approval_request` naming the
  caller flips `pending → expired`; **decided rows are immutable** (§3.1.2 of the machine: the expiry routes
  through §17.3/§17.4 release semantics; the caller's own-order-refund exemption stands).
- Re-request while pending → `noop_replay`. Request while ERASED is unreachable (no session exists).
- **Emissions:** BE-emits `account_deletion_pending` (`notify.emit_event`, `OR-14`) — same-txn, last write;
  a failed emit warns and commits (R2 row 31).
- **Errors:** §0.5 taxonomy. **Tests:** `T-RPC-DEL-01` (accept + re-request idempotent), `T-RPC-DEL-02`
  (Q5: pending expire, decided immutable), `T-RPC-NOTIFY-10` (injected emit failure: state write commits).

#### 20.17.2 `kernel.withdraw_account_deletion(p_command_key)` — **DB-RPC**

- **EXEC:** `authenticated`, own identity, no identity parameter. `DELETION_PENDING → ACTIVE`; clears
  `deletion_requested_at`/`deletion_block_reason`. Withdraw while ACTIVE → `noop_replay`; while ERASED —
  unreachable. Expired Q5 approvals are NOT resurrected (§3.1.2: expiry is a release, not a suspension).
- **Tests:** `T-RPC-DEL-03`.

#### 20.17.3 `kernel.is_deletion_pending(p_identity uuid) RETURNS boolean` — **STABLE definer predicate**

- The single freeze operand every F-clause calls (the `has_org_role`/`is_transfer_frozen` house pattern;
  one implementation). `EXEC: DEF` — no client grant; callers are the F-clause hosts and the sweep.

#### 20.17.4 `kernel.sweep_deletion_pending(p_limit int DEFAULT 100)` — **cron definer (EXEC: DEF)**

- Its own `cron.schedule` (2 min) is created **by `077`** (P0-1 discipline); register row in
  `_governance/CRON_SCHEDULE_REGISTER.md`. `SKIP LOCKED` over the pending partial index; re-entrant; full
  predicate re-evaluation every pass (the half-completion detector).
- **Per identity, evaluates BP-1…BP-12 in order:** BP-11 and Q5 direct (`077` tables); BP-6-live/BP-7/BP-8/
  BP-9 direct over the live `public.*` rail (precondition baseline — no DAG edge); BP-10 via
  `kernel.has_outstanding_obligations` (§20.7.12, `OR-21`); BP-1/2/3/4/5/12 via the SEAM-2 evaluator hooks
  (§20.17.5). First true predicate → recorded in `deletion_block_reason`, pass moves on.
- **At all-false, terminal entry (idempotent):** erased marker write (OPEN-3 literal); retained request
  metadata (`deletion_requested_at` survives); `077`-plane role/invite clears; PR#28-minus-repointing live
  clears (the §4.5/§5 named engineering fold; never touches `kernel.*` custody — CUSTODY-DEL-1; never
  `auth.admin.deleteUser`); the four `on_identity_erased_*` cleanup hooks (§20.17.5); OPEN-6a demographic
  slot (recorded, not implemented); BE-emit `account_deletion_completed` (R2 row 32; copy constraint §4.7 —
  never "permanently deleted").
- **Tests:** `T-RPC-DEL-04` (tombstone only when all predicates false), `T-RPC-DEL-05` (half-completion
  re-detected next pass), `T-RPC-NOTIFY-11` (failed emit re-emitted next pass, deduped).

#### 20.17.5 The ten deletion SEAM-2 hooks — signatures frozen here (SEAM-2a)

| Hook | Stub (`077`) returns | Replaced in | Covers |
|---|---|---|---|
| `kernel.deletion_blockers_custody(p_identity uuid) RETURNS text` | `NULL` | `079` | BP-1 |
| `kernel.deletion_blockers_orders(p_identity uuid) RETURNS text` | `NULL` | `082` | BP-12 pending-order arm |
| `kernel.deletion_blockers_wallet(p_identity uuid) RETURNS text` | `NULL` | `083` | BP-2 |
| `kernel.deletion_blockers_money(p_identity uuid) RETURNS text` | `NULL` | `085` | BP-5 · BP-6 kernel arm · BP-12 refund/paid-window arm |
| `kernel.deletion_blockers_market(p_identity uuid) RETURNS text` | `NULL` | `088` | BP-3 · BP-4 |
| `kernel.on_identity_erased_staff(p_identity uuid) RETURNS void` | no-op | `080` | INV #23/#24 |
| `kernel.on_identity_erased_door(p_identity uuid) RETURNS void` | no-op | `086` | INV #29–#31 |
| `kernel.on_identity_erased_market(p_identity uuid) RETURNS void` | no-op | `088` | 16d hard-delete allowance ONLY (draft/cancelled listings, non-accepted offers) |
| `kernel.on_identity_erased_promoter(p_identity uuid) RETURNS void` | no-op | `090` | INV #36 (`venue.promoter` row SURVIVES) |
| `kernel.has_outstanding_obligations(p_identity_id uuid) RETURNS boolean` | `false` | `085` | BP-10 (`OR-21`, §20.7.12) |

Each stub's neutral result is **the true value over an empty world** (its operand table does not exist
before the replacing package — the C113/§0.4b argument); each replacing package asserts the stub body is no
longer live (`pg_get_functiondef` ≠ stub — the §0.4b discipline). Freeze clauses F-1…F-7 are authored as
preconditions inside their host RPCs' own sections (riders at §2.1, §2.3, §5.3, §6.1, §6.3, §8.2, §20.8.5,
§20.8.6, §20.9.1); F-5 and the delete-account edge switch are deploy artifacts on the `077` release train
(FR-9; §20.15 cutover note).

## 21. Correction index — the `MB-1` / `MB-6` cumulative-authority and custody-routing pass (2026-08-28)

**Authority:** ratification rows **`C88`** (cumulative refund tier operand), **`C89`** (`MB-6` — offline scan
routing + the §0.7a enumeration), **`C90` / open decision `O14`** (payout tier operand, recorded open) and
**`D20`** (documentation + integrator requests), filed in
`docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` by this pass. The `MB-1` half is
**predicate-identical** to `PHASE_2_MONEY_AUTHORITY_SPEC.md` §6.1a/§14 by construction: both tier tables were
corrected in the same edit, which is the only discipline available while `C75`/`O11` (no precedence rule
between delta specs) stands open.

| § | Before | After | Ratified by |
|---|---|---|---|
| **§0.7** | *"only via the three kernel engines"* | *"only via a sanctioned kernel custody writer, enumerated in §0.7a"* — **the prohibition is unchanged; the delegation set is stated** | `C89` |
| **§0.7a** | *did not exist* | **NEW** — five sanctioned writers with their callers, plus the two standing rules: **the Writes line must name the writer**, and **adding a member is an amendment** | `C89` |
| **§9.5** | **Writes:** `kernel.tickets` (first-admit-wins → `scanned`) — a declared direct write, in the **batched** path, behind `verify_jwt=false` | routed **via `kernel.mark_ticket_scanned`**, once per admitted row inside the batch loop, under the existing ascending atom lock; `T-RPC-DOOR-35` asserts it structurally | `C89` |
| **§17.1** | tier table keyed on `p_amount_minor`; buyer row's operand unstated; precondition 6 the only aggregate | every row keyed on `cumulative`; buyer operand settled; precondition 6 names the shared aggregate; `cumulative_minor` returned | `C88` |
| **§17.1a** | *did not exist* | **NEW** — the definition, the derivation of the payment as subject, the after-the-lock rule, the `amount_minor` obligation, the buyer resolution | `C88` |
| **§17.2** | support cap and re-derivation keyed on the recomputed single amount | both keyed on `cumulative`, **excluding this request from the parked term**; `T-RPC-MONEY-23`/`-24` | `C88` |
| **§10.3** | above-threshold payout parks; operand unstated | **`MB-1b`** block — the shape, the invariance property a fix needs, two admissible forms, **no choice made** | `C90` / `O14` |
| **§20.8.2** | `kernel.tickets.resale_state (→ none)` in **Writes**, delegation only in **Locks** | delegation named in **Writes** (`MB-6a`) | `C89` |
| **§18 / §18.1** | Money `-01..14`; Door set closure `-17`…`-34` | `T-RPC-MONEY-21..24` and `T-RPC-DOOR-35` **appended**, so no existing id moves | `C88`, `C89` |
| **§20.14** | `R-1`…`R-23` | **`R-24`** (RLS names 4 writers of `kernel.tickets`, **11** are contracted — corrected from "10" 2026-08-29, the eleventh is §12.5 — and the 4th is `record_scan`) · **`R-25`** (four money RPCs bypass the `lock_ticket`/`unlock_ticket` overlay — owner ruling, unchanged here) · **`R-26`** (`R-22` is used twice in this table) · **`R-27`** (`kernel.approval_request.amount_minor`) | `D20` |

**What this pass deliberately did NOT do.** It chose **no threshold value** (`D-3` untouched). It closed
**no** open decision — `O6`…`O13` stand and **`O14` is added, not closed**. It changed **no** role set and
**no** authority cell: every predicate keeps the principals `O-1`/`O-3`/`C57`/`C58` gave it. It touched
**nothing** in the frozen Stripe money core, no `public.*` table, and no ratified ownership invariant — the
`MB-1` change is to the **operand an authority threshold is compared against**, and the `MB-6` change is to
**which function performs a write that already happens**. It **weakened no CI gate, ratchet or floor** and
changed no workflow file. It renumbered **no** package (`076`–`091`), **no** migration (`071`–`075`), no
ratification row and no test id. It touched **no `OFFLINE-VERIFY-v1` fenced block** — none appears in either
file it edited, and the four copies were extracted and hashed after the last edit to confirm they remain
byte-identical, one distinct body, `sha256 afb5184d58b62da5cb03cb8c4c7923953b4206c52f8afa23dee6403069fe6344`.

---

## 22. Correction index — the `R1` unapplied-filings pass (2026-08-28)

**Authority:** ratification rows **`C99`–`C109`** and **`D22`**, filed in
`docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` by this pass.

**The shape, stated once because it is the finding and not an anecdote: the repair landed in the document
that hosted the defect, and not in the artifact an implementer builds from.** Requests were *filed* —
`S-15`…`S-22` in schema §13.7, `R-24` and `R-27` in §20.14 — and never *applied*. **A filing is not a column
and it is not a contract.** Every row below is one unapplied filing, and each was a column that could not be
written or a contract that instructed the pre-fix behaviour.

| § | Before | After | Ratified by |
|---|---|---|---|
| **§7.3** | Writes: `kernel.tickets` *"→ `voided`, credential bump"* — **`current_owner_id` omitted** while the log row sets `to_identity := ` the sentinel | `current_owner_id := SN-VOID` in the write set; `market_sale` routed through `market.on_atom_voided` (§0.7). **The credential bump fires `tg_custody_head_is_ledger_tail`, so as written EVERY void aborted at COMMIT** — taking down `refund_primary_order`, `force_void_ticket`, `catalog.cancel_event` and C25 | `C107` (`S-18`) |
| **§10.2** | Writes: `venue.settlement (→ closed)`; **returns `net_minor`** | writes the four money columns from the lines it just wrote, under the header's own lock, rounding bearer included; `net_minor` is a read-back. **They had ZERO writers: two occurrences corpus-wide, both DDL** | `C103` |
| **§10.3** | no INSERT arm, **no probation arm** | an explicit probation arm that **declines to advance** and writes all four hold columns (`held_by` NULL, `status` untouched), returning `probation_held`. **`probation_hold` had no writer and the row as described was un-INSERTable** | `C105` (`S-15`) |
| **§11.2 / §11.3** | *"→ `held`-equivalent status"* / *"→ `pending`/`submitted`"* | `hold_state` writes with `status` untouched. **`status='held'` never existed**; §11.3 as written had to *guess* which of two lifecycle values a hold had overwritten — **the difference between paying once and twice** | `C105` (`S-15`) |
| **§12.5** | *did not exist* | **NEW** — `kernel.sweep_expired_ticket_atoms`, the writer `kernel.tickets.state='expired'` never had, plus §4.3.1's standing rule as an obligation on **other** contracts | `C109` (`S-22`) |
| **§17.7** control 2 | *"created `held` … needs no new column"* | created `pending` and not advanced, carrying `hold_state='probation_hold'`; **four additive columns**, since *"needs no new column"* was false under every candidate repair | `C105` (`S-14`/`S-15`) |
| **§17.9** | `service_role` only, **no human path** | `authenticated` only, EDGE-CALLER-JWT-bound, actor server-derived, **raises on NULL**; signature unchanged. **As written it could not execute ONCE**, on the fraud path | `C106` (`S-17`) |
| **§17.22** | `assert_may_request` named twice, contracted nowhere | cites §20.7.8; `list_export_jobs` names the `p_raise := false` call as the corpus's only one | `C108` |
| **§20.0e** | *did not exist* | **NEW** — the six objects that entered sets A/B after §20.0b was computed. **`49` is not amended**, so §20.0a's method stays reproducible | `D22` |
| **§20.7.6** | *did not exist* | **NEW** — `kernel.mark_payout_transfer_state`. **In the schema, the plan and the registry, and in ZERO contracts and ZERO EXEC rows.** Corrects the event mapping: only `transfer.created` supplies the join key; `payout.paid`/`payout.failed` are the connected account's own bank payout and are **not attributable to one row**; `failed` is a **synchronous API error**, so the executor writes it. **`O16` recorded, not decided** | `C104` (`S-16`) |
| **§20.7.7** | *did not exist* | **NEW** — `kernel.mark_refund_state`. `kernel.refund`'s only writers all INSERT at the `pending` DEFAULT: three of four labels unreachable, **`stripe_refund_ref` with zero writers and zero readers**, and `MB-1`'s cumulative operand permanently `pending`-only | `C101`, `C102` |
| **§20.7.8** | *did not exist* | **NEW** — `venue.assert_may_request`, which **got a package number and nothing else**. Return shape settled: one function, `RETURNS boolean`, `p_raise DEFAULT true`; two rejected shapes recorded | `C108` |
| **§20.11** | *"These four"* | **five** — `venue.on_payout_settled` (§20.11.5), the SEAM-2 hook that is the only writer of `venue.settlement.status='paid'`, and the §0.7 boundary answer | `C104` (`S-16`) |
| **§20.14** | `R-1`…`R-27` | **`R-28`** (record_money_denial: RLS + MONEY) · **`R-29`** (assert_may_request: EXEC row + the five-parameter signature) · **`R-30`** (sweep EXEC row) · **`R-31`** (three state-sync EXEC rows + the `085` objects) · **`R-32`** (dashboard pills + settlement header) · **`R-33`** (MONEY §8.4 *"created `held`"*) · **`R-34`** (payment_native writer pair; X-1 transcription) · **`R-35`** (set_updated_at — CLOSED 2026-08-29) · **`R-36`** (invite `declined` — CLOSED 2026-08-29, `OR-18`) · **`R-37`** (market checkout: owner) · **`R-38`** (native-sale payout ↔ Gate M — CLOSED-AS-GATED 2026-08-29, `C135`) · **`R-39`** (org_customer_key — CLOSED 2026-08-29, `OR-19`/`OR-20`) · **`P0-1`** (the heartbeat that did not exist) | `D22` |

**What this pass deliberately did NOT do.** It **decided no open decision**: `O16` (what `payout.status='paid'`
asserts) is **recorded in two documents and left open**, and `O6`…`O15`, `D-3`, `D-9`, `D-10` and `MB-1b`'s
payout operand are untouched — §1.13.2's payout tier row now says *open* rather than implying settled. It
changed **no role set and no authority cell**: every predicate keeps the principals `O-1`/`O-3`/`C57`/`C58`
gave it, and the one grant that moves — `record_money_denial` — moves to the **schema's already-ratified**
design. It **weakened no ratified invariant**: `C106` *extends* EDGE-CALLER-JWT by one function, `C99`/`C103`
*add* constraints, and `C105` corrects a classification while preserving the behaviour `O-3` ratified. It
touched **nothing** in the frozen Stripe money core, **no `public.*` table**, and **no money movement** — every
change names *which function writes which column*. It **weakened no CI gate, ratchet or floor** and changed no
workflow file. It renumbered **no** package (`076`–`091`), **no** migration (`071`–`075`), no ratification row
and **no existing test id** — every test id is appended. It added **no dependency edge**: all five new objects
are placed by SEAM-1 inside already-declared edges (`077 → 085`, `085 → 087`, `078 → 079`), and the four
declared surfaces are the registry owner's to re-verify. It touched **no `OFFLINE-VERIFY-v1` fenced block** —
one appears in `PHASE_2_EDGE_FUNCTION_SPEC.md` §5.4.3 and it was not edited; the four copies were extracted
and hashed after **every** commit: **4 blocks, 1 distinct body, 2017 bytes, 34 lines,
`sha256 afb5184d58b62da5cb03cb8c4c7923953b4206c52f8afa23dee6403069fe6344`.**

---

*End of docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md. Design-only; no SQL, no function bodies. Companion to the physical
schema (deliverable #1), RLS spec (#3), and the Edge Function spec (#5, which picks up every EDGE-FRONTED item
flagged in §13), per SPEC_FOUNDATION §10.*
