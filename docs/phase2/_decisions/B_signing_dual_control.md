# DECISION B — CREDENTIAL SIGNING AND DUAL CONTROL

**Branch** `feature/venue-native-and-product-v2` · read-only analysis · 2026-09-02
**Scope** how a `kernel.signing_key` gets provisioned and activated safely, so primary ticketing can
launch **without** Apple Wallet and **without** the door/scanning rail.
**Every claim below carries a `file:line`.** Nothing here mutates production, authors a migration, or
commits.

---

## 0. BOTTOM LINE

1. **A display-only launch is genuinely possible — but it does NOT avoid the signing key.** Ticket
   *display* is already reachable today with zero new crypto. Ticket *existence* is not: the mint
   refuses to write an atom unless an ACTIVE, scope-coherent `kernel.signing_key` row resolves, and
   `kernel.tickets.signing_key_id` is `NOT NULL` with an `ON DELETE RESTRICT` FK. **You cannot skip the
   key by skipping the QR.**
2. **The size of the decision is therefore small, and it is not a cryptography decision.** What launch
   needs is *one row that truthfully references one real KMS key*. It does not need `credential-sign`,
   M1/M2 manifests, offline verify, `.pkpass`, or the 086 door rail.
3. **In-DB dual control is not merely unbuildable — the second approver does not exist.** Production
   holds exactly one platform admin, and PFA-4 makes a second one unmintable. An in-DB approval
   workflow built today would be dual control in form only.
4. **Recommendation:** generate the key pair in KMS under two-person IAM control, and land exactly one
   `global`-scope row via an owner-signed, single-purpose **migration 093**. Leave all six parked
   credential-lifecycle RPCs raising, byte-for-byte. Classification: **POST-FREEZE AMENDMENT**
   (owner-signed, PFA-4-shaped narrow scope) with an **OPERATIONAL CONFIG** component and an
   **IMPLEMENTATION FOLLOW-UP** deferred.

---

## 1. THE PREMISE, VERIFIED

Every element of the brief's premise is true as shipped.

| Claim | Verified at |
|---|---|
| `kernel.provision_signing_key` is an unconditional `raise` stub, zero mutation | `supabase/migrations/083_kernel_credential_infrastructure.sql:375-384` |
| `kernel.rotate_signing_key` likewise | `083:385-394` |
| The raise text names PFA-18A verbatim | `083:381`, `083:391` |
| `kernel.revoke_signing_key` is parked too (authored in 086 per PFA-17) | `supabase/migrations/086_venue_door_and_scan.sql:714-721` |
| The three `pass_type_cert` RPCs are parked on the same string | `083:395-425` |
| `kernel.tickets.signing_key_id` is `NOT NULL` | `supabase/migrations/079_kernel_ticket_atom_and_ownership_log.sql:48` |
| …and carries an `ON DELETE RESTRICT` FK added late at 084 | `supabase/migrations/084_kernel_tickets_late_binding_fks.sql:52-55` |
| The mint fails closed without an ACTIVE, in-window, scope-coherent key | `083:514-530` |
| `finalize_primary_order` resolves the key and fails closed first | `supabase/migrations/085_kernel_money_native.sql:1948-1961` |
| 083 states it plainly: "No key can be provisioned while the lifecycle is parked (PFA-18A), so the mint cannot run" | `083:431-433` |
| The parked posture is asserted by pgTAP and would break on a naive un-park | `supabase/tests/147_phase2_kernel_credential_infrastructure.sql:106-120`; `supabase/tests/150_phase2_venue_door_and_scan.sql:103` |
| 076–092 are applied to production; all 5 feature flags false; zero native money rows | `docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:19-21,41-43` |

Production therefore holds **zero signing keys**, and no sanctioned path can create one.

---

## 2. THE PARKED DECISION — WHY, EXACTLY

### 2.1 PFA-18 — the requirement (ratified, still binding)

`docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:1224-1250`.

RLS §11.7 mandates a second approver via `kernel.approval_request` for the `pass_type_cert` lifecycle.
RPC §20.7.3 authored the same for `provision_signing_key` **by inference** and flagged it (R-11). The
owner ratified the inference (`:1245-1250`):

> the signing-key lifecycle at 083 … is DUAL-CONTROLLED: a second `platform_admin` approver via
> `kernel.approval_request`, parallel to `pass_type_cert`.

So the **requirement** is: two distinct `platform_admin` principals, second-approver activation.

### 2.2 PFA-18A — why the mechanism is unbuildable

`POST_FREEZE_AMENDMENTS.md:1252-1315`.

`kernel.approval_request` (077, immutable, hash-locked) closes its vocabulary at the schema level:

- `action in ('refund.issue','payout.request','config.set_money_key')` — `077:269-270`
- `subject_kind in ('order','settlement','config_key')` — `077:275-276`
- CHECK (4) pairs them exhaustively — `077:299-302`
- CHECK (7) forces `amount_minor` non-null for anything that is not `config.set_money_key` — `077:308`
- the org-scope arm forces `org_id` non-null for the two money actions and NULL for the config one — `077:312-314`

There is **no arm a credential approval can occupy**. Writing one would violate a frozen CHECK (23514).
083 may not mutate 077, may not extend the vocabulary, and may not semantically lie by encoding a
signing key as a `config_key`. This is the **PFA-4 impossibility class** (`:126-172`) reaching the
credential lifecycle.

The owner chose option (a) — fail closed — and rejected (b) single-control fallback and (c) overloading
077 (`:1268-1284`). The interpretation constraints are explicit (`:1300-1307`): dual-control
REQUIREMENT preserved · NO single-control fallback · 077 not mutated · no credential vocabulary added ·
no semantic overloading · **ZERO credential mutation / signing-key activation / partial approval /
authority escalation** on the parked path.

The forward obligation is deliberately **UNASSIGNED** (`:1308-1313`): "A later design chooses the
mechanism through separate ratification." 083 builds no shadow approval framework.

### 2.3 PFA-4 — the same class, and the precedent that matters

`POST_FREEZE_AMENDMENTS.md:126-172`, owner signature `:207-231`.

`grant_platform_role`'s dual control is unbuildable for identical reasons, and its grant arm ships
fail-closed — **no `kernel.platform_role` row can be minted by anyone** (`:219-231`). The owner ruling
(`:213-221`) is the load-bearing precedent for Decision B:

> "Amend the approval_request closed sets **only as narrowly as necessary** to represent and execute
> that platform-grant approval path."

and the SCOPE OPENED clause (`:223-231`) confirms the closed sets **may be extended by a later package
that owns the path** — 077's bytes stay frozen, the constraint is altered forward. So a credential arm
is *reachable* by the same route. It is expensive, and §4 shows launch does not need it.

### 2.4 The finding PFA-18A did not record: there is no second approver

`kernel.is_platform(['platform_admin'])` resolves through `kernel.platform_role` **or** the
`public.admin_users` bootstrap (`077:468-488`). PFA-4 leaves `platform_role` unmintable. And
`public.admin_users` is a single-row allowlist:

- table + RLS-on, zero policies, `REVOKE ALL … FROM PUBLIC, anon, authenticated` — `supabase/migrations/033_marketplace_expansion.sql:101-112`
- seeded with exactly one account, and the file says so — `033:113-123`, `033:251` (`COUNT(*) … = 1`)
- "service_role bypasses RLS; that is the ONLY write path" — `033:107-109`

**Consequence:** even if the `approval_request` vocabulary were extended tomorrow, the SoD check
(`approved_by <> requested_by`, `077:293-294`) could never be satisfied — there is one platform admin,
and the only way to create a second is a service-role write to `admin_users`, which is itself
single-control. An in-DB dual-control workflow built now would be **ceremony without a second
principal**. This is the single most decision-relevant fact in this document.

---

## 3. THE SIGNING SCHEMA (083) — WHAT THE DB ACTUALLY STORES

`083:49-124`.

```
kernel.signing_key(
  key_id uuid PK, scope text, event_id uuid, venue_id uuid,
  public_key text NOT NULL,      -- verify key, distributable
  kms_handle_ref text NOT NULL,  -- opaque KMS handle/ARN, NOT key material
  status text, not_before timestamptz NOT NULL, not_after timestamptz, …)
```

- **Scope model** — `scope in ('per_event','per_venue','global')`, default `per_event` (`083:51-52`),
  with a coherence CHECK forcing exactly the matching target set (`083:63-68`) and a window CHECK
  `not_after > not_before` (`083:69`).
- **One ACTIVE key per scope target** — three partial unique indexes (`083:73-79`), including
  `signing_key_active_global_uq on ((true)) where status='active' and scope='global'` (`083:78-79`) —
  i.e. **at most one active global key can exist database-wide**.
- **Status lifecycle** — `active|rotating|revoked` (`083:57-58`).
- **No private key material ever reaches Postgres.** This is C33, stated at `083:36-41`: `public_key`
  is the verify key; `kms_handle_ref` is an opaque ARN; "Signed tokens are produced only by the
  credential-sign edge fn calling KMS."
- **Immutability guard** — `kernel.guard_signing_key_immutable()` (`083:83-105`) is a **BEFORE UPDATE**
  trigger only. It freezes `public_key`, `kms_handle_ref`, `scope`, `event_id`, `venue_id`,
  `not_before`; it makes `revoked` terminal. It deliberately leaves `status` and `not_after` mutable
  (`083:81-82`). **It does not guard INSERT at all** — see §5.
- **Read surface** — `revoke all … from anon, authenticated` (`083:111`), then a column-scoped
  `grant select (key_id, scope, event_id, venue_id, public_key, status, not_before, not_after) to
  authenticated` (`083:114-116`) with a deliberately row-universal policy (`083:118-124`).
  `kms_handle_ref` is column-fenced away. This is PFA-16's ruled outcome —
  `POST_FREEZE_AMENDMENTS.md:1124-1173`: anon gets nothing, because 076 grants `kernel` USAGE to
  `authenticated` only (`supabase/migrations/076_create_phase2_schemas_and_grants.sql:71,77`).

---

## 4. HOW A CREDENTIAL IS PRODUCED AND VERIFIED — AND WHAT LAUNCH ACTUALLY NEEDS

### 4.1 Production (`credential-sign`, EDGE §3.2)

`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md:399-438`.

- POST, `verify_jwt: true`; authorization is *entirely* `kernel.tickets.current_owner_id = auth.uid()`
  re-read live (`:405-407`).
- Request `{ ticket_atom_id }`; response `{ token, credential_version, signing_key_id, not_after,
  ttl_seconds }` (`:410-413`).
- The token signs `{ atom_id, session_id, credential_version, key_id, issued_at, exp }` (`:412-413`).
- `KMS.sign(kms_handle_ref, canonical_payload)` — Ed25519 preferred, ECDSA-P256 acceptable
  (`:418-419`, `:1274-1277`). **The private key never leaves KMS.**
- **No state write.** Signing does not mutate custody (`:415-417`).

### 4.2 Key selection at mint

Two callers, and they differ in an important way:

- `kernel.issue_ticket_atoms` **does not choose** — it reads `signing_key_id` out of `p_ctx`
  (`083:479`) and then validates it: ACTIVE, `not_before <= now()`, `not_after > now()`, and **scope
  coherence** against the session's event/venue (E-46, `083:514-530`). Wrong scope ⇒ refuse, "an
  active-but-wrong-scope key would mint atoms the door cannot verify" (`083:524-525`).
- `venue.finalize_primary_order` **does** choose, most-specific-first:
  `order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end limit 1`
  (`085:1948-1960`). **A `per_event` key silently outranks a `per_venue` key, which outranks
  `global`.** Remember this for §5.
- The atom pins the key at insert (`083:557-559`), `credential_version = 0`.

### 4.3 Verification and rotation

- EDGE §5.2 (`:1289-1290`): "The signer for an atom is resolved by `kernel.tickets.signing_key_id`
  (pinned at issue/transfer), **NOT** by a fresh lookup — so a mid-event rotation does not orphan
  already-issued credentials."
- Rotation is old `active→rotating`, new `active`, in one txn with validity overlap
  (`:1521-1526`). **Already-issued tickets keep verifying against the key they were pinned to,
  retained permanently.** They are never re-pinned — 088 confirms no ratified resolver exists
  (`supabase/migrations/088_market_native_rail.sql:606`, E-97).
- Scanner trust path: the door joins **M2** (`venue.get_door_manifest`, per-atom `signing_key_id`
  only) → **M1** (the `kernel.signing_key` public projection, KMS-signed, served by the door-session
  edge). PFA-24 ruled this, `POST_FREEZE_AMENDMENTS.md:2064-2078`: M2 carries `signing_key_id` and
  **never** `public_key`, never key material. M1 contents at `EDGE_SPEC:1342-1350`; 086 implements the
  M2 half at `086:335,364,860-866`.

### 4.4 The definitive display-vs-scannable answer

| Property | What it needs | Status today |
|---|---|---|
| **Ticket exists** | a `kernel.tickets` row from `issue_ticket_atoms` | **needs an ACTIVE signing-key row** — `083:514-530`, pinned `083:557-559`; column `NOT NULL` `079:48`; FK `084:52-55` |
| **Ticket displayable** | owner `SELECT` on `kernel.tickets` | **already works** — `grant select on kernel.tickets to authenticated` `079:735`; policy `kernel_tickets_sel_owner` `079:737-741`; `kernel` exposed in prod `PHASE2_DEPLOYMENT_RECORD_20260902.md:24-26` |
| **Ticket scannable** | `credential-sign` + KMS sign + M1/M2 + door rail + `feature.native_scanning_enabled` | **not built** — `supabase/functions/` holds 11 legacy functions, none of them `credential-sign`; flag false `078:1523` |

**So: YES — primary ticketing can launch display-only.** A customer can buy, and hold a ticket the app
renders from `kernel.tickets` (identity, event, tier, serial), checked at the door by a human against a
staff list. `credential-sign`, Wallet, and 086 are all cleanly separable — the door never calls
`credential-sign` (`EDGE_SPEC:405-407`), it verifies with the public key. This matches the independent
finding in `docs/product-v2/_research/primary_issuance_audit.md:228-243`.

**BUT the key is not optional, and this is the whole decision.** The `NOT NULL` column plus the mint's
activation boundary mean the *infrastructure* is required even with no QR anywhere in the product. The
question is therefore never "do we need signing at launch?" (no) but "**how does one honest row get
into `kernel.signing_key`?**"

---

## 5. THREAT MODEL

### 5.1 Can one administrator silently replace a trusted signing key?

**Today: no one can create or replace a key at all.** All six lifecycle RPCs raise before any statement
(`083:375-425`, `086:714-721`). The table is `revoke all` to anon/authenticated with a SELECT-only
policy (`083:111-124`). No INSERT/UPDATE/DELETE grant or write policy exists for any client role. The
only write path is a superuser/`postgres` connection: the Supabase SQL editor, or a migration.

**After any un-parking or direct write, yes — and by four distinct routes:**

**(T1) Scope shadowing — the highest-yield attack.** `finalize_primary_order` resolves
most-specific-scope-first (`085:1955-1960`). Anyone able to insert a `per_event` key silently
outranks the legitimate `global` or `per_venue` key **for that event only**, with no alert, no
uniqueness collision (the partial unique index is per target, `083:73-77`), and no operator-visible
change. The mint's scope-coherence check *passes* — the attacker's key genuinely governs the scope.
Every atom minted for that event is then pinned to a key whose KMS handle the attacker controls, and
pinning is permanent (§4.3). If scanning later activates, the attacker can mint verifying credentials
for that event indefinitely.

**(T2) The `authenticated` EXECUTE grant is a loaded trap for the un-parking author.** 083 places
`provision_signing_key` and `rotate_signing_key` in the **caller-authorized** grant array
(`083:846-853`) and grants EXECUTE **to `authenticated`** (`083:869-871`), with a comment explaining
why this is currently safe: "Credential lifecycle is EDGE-FRONTED (G-7) — authenticated at the edge;
the parked bodies fail closed regardless" (`083:843-845`). The `kernel` schema **is** exposed through
PostgREST in production (`PHASE2_DEPLOYMENT_RECORD_20260902.md:24-26`). **The bodies contain no
principal check** — they raise first. A 093 that un-parks by `CREATE OR REPLACE` without adding
`is_platform(['platform_admin'])` **inside the body** hands signing-key provisioning to every signed-in
user over the public API. This exact trap is already recorded as E-47(a)
(`POST_FREEZE_AMENDMENTS.md:1869`; restated `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md:164`).

**(T3) Unguarded INSERT.** `guard_signing_key_immutable` is `BEFORE UPDATE` only (`083:104-105`).
Nothing validates at INSERT that `public_key` is a real key, that `kms_handle_ref` names a real KMS
object, or that the two correspond. A placeholder string satisfies every constraint. **Postgres cannot
tell a real key from a fake one** — by design, since it holds no key material (C33, `083:36-41`).

**(T4) Window mutation.** The guard deliberately leaves `not_after` mutable (`083:81-82`,
absent from the immutability list `083:88-93`). A table-UPDATE-capable principal can extend or truncate
a key's validity, silently ending or prolonging issuance.

### 5.2 Real-world blast radius, given scanning is dark

**Immediately: near zero.** `credential-sign` does not exist, nothing signs, `feature.native_scanning_enabled`
is false (`078:1523`), the 086 door rail is dark, and Wallet is dark (`wallet.apple.enabled` false,
`078:1525`). A rogue key today mints nothing and forges no entry, because **there is no entry gate to
forge**. Human door checks read a name and a serial, not a signature.

**Deferred and permanent: high.** The damage is not at the door, it is in the *pinning*. Every atom
minted under a wrong, placeholder, or attacker-held key is bound to it forever (`083:557-559`; no
re-pinning resolver, `088:606`). Rotation does not fix already-issued atoms (`EDGE_SPEC:1289-1290`).
Revocation is itself parked (`086:714-721`), and the FK is `ON DELETE RESTRICT` (`084:54`) — once one
atom exists, the row cannot even be deleted. **A bad key at launch is a permanent, unfixable defect in
every ticket sold under it, discovered only when the door rail turns on.**

### 5.3 The threat I consider most serious

Not forged entry. **It is that the whole failure mode is silent and deferred, and the control PFA-18
ratified to prevent it cannot function** — because production has one platform admin
(`033:113-123`, `033:251`) and PFA-4 makes a second unmintable
(`POST_FREEZE_AMENDMENTS.md:219-231`). Any dual control implemented *inside* Postgres today would pass
its own SoD CHECK only if someone first service-role-wrote a second row into `admin_users`, a
single-control act. That produces an audit trail that *looks* like two-person control and is not. A
launch-time key inserted casually — a placeholder handle "to unblock the mint", a `per_event` key added
by hand for one show — would not be noticed for months, and by then every ticket sold is
irrecoverably pinned to it. **The control must be relocated to a plane where a second principal
actually exists, or it is theatre.**

---

## 6. OPTIONS

### Option A — In-DB dual control: narrowly amend `approval_request`, then un-park the RPCs

Extend 077's `action` / `subject_kind` / pairing CHECK with a `signing_key.provision` ×
`signing_key` arm (constraint altered forward by 093; 077's bytes untouched), add the writer/approver
arms, then `CREATE OR REPLACE` the real bodies with an in-DB `is_platform` check.

- **Advantages** — implements PFA-18 literally, at the layer it named. Discharges the PFA-18A forward
  obligation permanently. Explicitly inside the amendment space PFA-4's ruling already opened
  (`POST_FREEZE_AMENDMENTS.md:223-231`). Every future key gets the same control.
- **Disadvantages** — by far the largest build: five closed sets across five surfaces, a new approver
  verb (only `approve_refund_request` exists, `085:1089`), a requester/approver UI, plus KMS integration
  and `signing-key-provision` (`EDGE_SPEC:579-592`) before the first key exists. Touches the frozen
  money-approval substrate for a non-money purpose.
- **Failure modes** — **the SoD CHECK can never be satisfied** with one platform admin (§2.4), so the
  path is dead on arrival until an independent second-admin process exists. Any error in the CHECK
  rewrite risks the live money-approval path. E-47(a) trap (T2). CHECK (7)/(8) and the org-scope arm
  need credential-shaped exemptions, widening the surface further.
- **Launch implications** — weeks, and it blocks issuance the whole time. Wrong instrument for a
  display-only launch.

### Option B — Un-park with single in-DB authority; enforce two-person control in the edge/runbook

`CREATE OR REPLACE` the bodies with `is_platform(['platform_admin'])`, and require two humans in the
`signing-key-provision` edge or the ops procedure.

- **Advantages** — smallest code change; produces a reusable provisioning path.
- **Disadvantages** — **explicitly rejected by the owner.** PFA-18A option (b), verbatim: "single-control
  fallback (platform_admin alone) — REJECTED by owner: the unavailable approval mechanism does NOT
  authorize downgrading the security requirement" (`:1274-1276`); the signature repeats it
  (`:1298-1300`).
- **Failure modes** — the DB is the authority boundary, and edge-side ceremony is bypassable by anyone
  who can call the RPC directly; with the `authenticated` grant (T2) that is anyone signed in, unless the
  new body's check is exactly right. Re-opens a security boundary the owner closed on the record.
- **Launch implications** — fast, and it would require re-litigating a signed ruling. **Not viable.**

### Option C — KMS/IAM dual control + one owner-signed bootstrap row in migration 093 · **RECOMMENDED**

Generate one asymmetric key pair in KMS (Ed25519 preferred, `EDGE_SPEC:1274-1277`) under two-person
IAM control. Land **exactly one** `scope='global'` row carrying its real `public_key` and real
`kms_handle_ref` via an owner-signed, single-purpose migration 093 reviewed and merged by a second
party. **Leave all six lifecycle RPCs parked, unchanged.**

- **Advantages** — the dual control is *real*, because KMS/IAM is a plane where a second principal
  genuinely exists, unlike `admin_users`. The DB never gains a provisioning path, so T1/T2/T3/T4 all
  stay shut: no RPC is un-parked, the `authenticated` EXECUTE grant stays inert, and no runtime write
  path is created. `global` scope makes T1 structurally impossible while it is the only key —
  `signing_key_active_global_uq` allows exactly one (`083:78-79`), and any later per-event shadow key
  would need the same migration+review route. The corpus explicitly sanctions this shape: `global` is
  "allowed **but discouraged** … only for a **controlled bootstrap**" (`EDGE_SPEC:1286-1288`) — this is
  that bootstrap. Suites 147/150 stay green unchanged. Because the key is real, atoms minted under it
  remain verifiable when scanning eventually activates — no permanent defect (§5.2).
- **Disadvantages** — key provisioning is a code-review-and-deploy event, not a runtime operation:
  rotation and revocation stay unavailable in-band, so a compromise response is another migration.
  Requires an owner signature (a new PFA), because activating a key by a route the ratified mechanism
  did not contemplate is exactly the kind of decision PFA-18A reserved.
- **Failure modes** — (i) a wrong or placeholder `kms_handle_ref` is undetectable by Postgres (T3), so
  the migration must be gated on an out-of-band proof that the handle signs and the stored `public_key`
  verifies; (ii) if `not_after` is set, issuance hits a **hard cliff** with no in-band extension —
  `083:519` requires `not_after > now()`, rotation and revoke are parked, and only another migration can
  move the window (`083:81-82` leaves it mutable); (iii) the migration must be idempotent or a
  `db push --include-all` replay could attempt a second row.
- **Launch implications** — unblocks issuance in one migration. Fully compatible with display-only:
  nothing signs, nothing scans, and the row is simply the anchor the `NOT NULL` FK demands.

### Option D — Defer entirely by scoping launch to display-only tickets

- **This option does not exist.** The evidence in §4.4 eliminates it: display-only removes
  `credential-sign`, M1/M2, Wallet and the door rail, but it does **not** remove the key. `079:48`
  (`NOT NULL`), `084:52-55` (FK RESTRICT) and `083:514-530` (mint activation boundary) each
  independently force a key row to exist before the first atom is written. Deferring the key defers
  primary ticketing altogether.
- Listed here because it is the intuitive read, and getting it wrong would produce a launch plan that
  fails at the first `finalize_primary_order`.

---

## 7. RECOMMENDATION — MINIMUM SAFE ARCHITECTURE

**Adopt Option C.**

1. **KMS (operational, outside the DB).** Create one asymmetric signing key — **Ed25519 preferred,
   ECDSA-P256 acceptable**, the primitives the frozen architecture already specifies
   (`EDGE_SPEC:1274-1277`). Nothing new is invented here. Create it under an IAM policy requiring two
   named humans; scope the role to `kms:CreateKey` for provisioning and `kms:Sign` for the future
   signer, exactly as `EDGE_SPEC:1293-1297` specifies. Export the public key. **Prove out of band that
   the handle signs and the exported `public_key` verifies that signature** before writing anything to
   Postgres — Postgres provably cannot check this (§5.1 T3).
2. **Database (migration 093).** Insert exactly one `scope='global'`, `status='active'` row with the
   real `public_key` and real `kms_handle_ref`. Change nothing else.
3. **Leave parked.** `provision_signing_key`, `rotate_signing_key`, `revoke_signing_key` and the three
   `pass_type_cert` RPCs keep raising, byte-identical. PFA-18A's ratified posture holds literally: no
   RPC activates a credential, no single-control fallback is introduced, 077 is untouched, no credential
   vocabulary is added.
4. **Do not build**, at launch: `credential-sign`, `signing-key-provision`, M1/M2, the 086 door rail,
   Wallet. Leave `feature.native_scanning_enabled`, `feature.native_resale_enabled` and
   `wallet.apple.enabled` false (`078:1523-1525`).
5. **Compensating controls, because rotation and revocation are unavailable in-band:**
   - a monitor alerting on **any** row appearing in `kernel.signing_key` beyond the expected one, and on
     any `per_event`/`per_venue` row appearing at all (the T1 shadowing signal);
   - a documented compromise runbook whose first step is flipping
     `feature.native_issuance_enabled` false — the one in-band control that still works — followed by an
     emergency migration;
   - a named calendar owner for the key's `not_after`, if a bounded window is chosen.

**Why this is the minimum *safe* architecture, not merely the minimum:** it declines to build the thing
that cannot be built honestly (in-DB dual control with one admin), it declines to weaken the thing the
owner refused to weaken (single-control provisioning), and it puts the real control where a second
principal actually exists. The residual risk it accepts is narrow and named: key provisioning becomes a
reviewed deploy rather than a runtime operation.

### Classification

**PRIMARY: POST-FREEZE AMENDMENT** — owner signature required. Activating a signing key by a route the
ratified mechanism did not contemplate is precisely the class PFA-18A reserved ("STILL CLOSED:
credential provisioning/rotation (parked)", `:1308-1315`). The amendment should be narrow in the shape
PFA-4's ruling models (`:223-231`): it authorizes **one bootstrap key, by migration, under out-of-band
two-person control** — and authorizes nothing else. It must state, as PFA-4 does, what it does **not**
authorize: no un-parking of any RPC, no generalized provisioning path, no runtime write path, no
extension of 077's closed sets, no second key without a fresh signature.

Secondary components:
- **OPERATIONAL CONFIG** — the KMS key, the IAM two-person policy, the monitor, the runbook.
- **IMPLEMENTATION FOLLOW-UP (deferred, not launch-blocking)** — a credential-compatible dual-control
  mechanism (Option A) discharging PFA-18A's forward obligation, plus `signing-key-provision`,
  `credential-sign`, and the 086 rail, before scanning activates. E-47(a)'s in-DB principal-check
  requirement binds that work.

---

## 8. WHAT MIGRATION 093 WOULD NEED TO CONTAIN

*(Description only — not authored here.)*

**Must contain**

1. A header recording: the new PFA id and owner-signature date; that 076–092 bytes are untouched; the
   out-of-band proof reference that the KMS handle signs and the stored `public_key` verifies; and the
   named two humans who provisioned the KMS key.
2. **Exactly one** `insert into kernel.signing_key`:
   `scope='global'`, `event_id`/`venue_id` NULL (required by `signing_key_scope_target_ck`, `083:63-68`),
   `status='active'`, real `public_key`, real `kms_handle_ref`, `not_before` = an explicit timestamp at
   or before the launch window, `not_after` = an owner decision (see the cliff in §6 Option C failure
   mode (ii); NULL is defensible only with the monitor and runbook in place).
3. **Insert-once idempotency** — guard the INSERT on `where not exists (select 1 from
   kernel.signing_key)` so a `db push --include-all` replay cannot attempt a second row. The partial
   unique index (`083:78-79`) would reject a duplicate active global key anyway, but it would do so by
   aborting the migration rather than by no-op.
4. **A self-check that aborts the transaction** unless, at commit: exactly one row exists in
   `kernel.signing_key`; its `scope='global'`; its `status='active'`; and `not_before <= now()` with
   `not_after` NULL or `> now()` — i.e. the row it just wrote actually satisfies `083:514-530` and
   `085:1948-1960`. A key row that does not resolve is worse than no row: it looks provisioned and
   still refuses to mint.
5. A new pgTAP file asserting: exactly one active `global` key; the mint's activation boundary now
   resolves for a representative session; and — critically — that **all six lifecycle RPCs still raise
   their exact PFA-18A strings**, so a later un-park cannot land silently.

**Must NOT contain**

6. No `CREATE OR REPLACE` of `provision_signing_key`, `rotate_signing_key`, `revoke_signing_key`, or
   any `pass_type_cert` RPC. Suites `147:106-120` and `150:103` must pass **unmodified** — that is the
   mechanical proof the ratified posture survived.
7. No change to `kernel.approval_request`'s CHECKs, writer set, or approver arms (`077:266-320`).
8. No new GRANT of any kind, and no widening of the existing `authenticated` EXECUTE grant
   (`083:869-871`). No INSERT/UPDATE/DELETE grant or write policy on `kernel.signing_key`.
9. No `per_event` or `per_venue` key. No second key. No `pass_type_cert` row (Wallet stays dark).
10. No feature-flag flip — `feature.native_issuance_enabled` is a separate, later, owner-executed
    `catalog.set_platform_config` call (`078:1522`), and it must be the last step.

**Companion rollback** (`supabase/rollbacks/093_*.sql`) — delete the row **only if** `kernel.tickets` is
empty, and say plainly in the file that the FK is `ON DELETE RESTRICT` (`084:52-55`), so the rollback
becomes structurally unavailable the moment the first atom is minted. After that point the posture is
forward-only, exactly as the 2026-09-02 deployment recorded for 076–092
(`PHASE2_DEPLOYMENT_RECORD_20260902.md:44`).

**Sequencing note.** 093 unblocks Blocker #2 only. It does not unblock the `public.payments` native
shape, the two unseeded `inventory.*` config keys, the `venue` PostgREST exposure, or the missing
`primary-checkout` edge — see `docs/product-v2/_research/primary_issuance_audit.md:175-215`. Landing
093 alone activates nothing, which is the correct property for a key-bootstrap migration.
