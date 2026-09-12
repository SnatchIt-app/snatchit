# H6 — Payout destination lifecycle and money authority

**Agent F · backend-only · 2026-09-02**
Branch `feature/venue-native-and-product-v2`, source tip `7d45cbf`.
Evidence: local rehearsal DB `snatchit_rehears_dest` (108 migrations replayed, GATE-2
`tables=27 functions=70 policies=37 triggers=24`, matching the CI baseline).
**No production mutation. No Stripe call. No deploy.**
Two findings were fixed under coordinator direction after the first pass — F-3 and F-4,
in `docs/phase2/_impl/093_parts/30_connect_org.sql` §9/§10 and
`supabase/functions/connect-onboarding/index.ts`. **Nothing is deployed.** See §8.

The rehearsal harness executes `SET ROLE authenticated` / `SET ROLE service_role`, so every
verdict below is grant-enforced, not merely body-enforced. Where a refusal is `permission
denied for function` that is the *grant* refusing; where it is a named `precondition_failed`
that is the *body* refusing. Both are recorded.

---

## 1. TASK 1 — can a payout destination be established today, and by what path?

### 1.1 The prior claim is confirmed, and it is about the wrong verb

`kernel.set_org_payout_destination` has **zero non-comment callers** anywhere in the repo.
Every hit is a definition (`085:1601`, `093:2925`), a grant array, a rollback, a pgTAP
fixture, a ruling, or a comment (`supabase/functions/connect-onboarding/index.ts:33`,
`docs/phase2/_impl/E1_connect_onboarding.md:325`). `web/`, `app/`, `src/`, `packages/` and
`supabase/functions/` contain **no call site at all**. **CONFIRMED FROM BYTES.**

### 1.2 But a destination CAN be established, by exactly one path

`supabase/functions/connect-onboarding/index.ts` runs the complete sequence end to end:

| step | file:line | verb | credential |
|---|---|---|---|
| resolve (human) | `:384` | `kernel.get_org_connect_state` | caller JWT, `authenticated` |
| resolve (machine) | `:484` | `kernel.get_org_connect_ref` | `service_role` |
| pre-mint refusals | `:1291-1330` | org_status ∈ (approved, active) · `org_owner` only · aal2 · safe redirects | caller JWT |
| **mint** | `:1337` `createOrgAccount` | Stripe `POST /accounts`, `business_type=company`, `metadata[org_id]` | platform Stripe key |
| **stage** | `:786` | `kernel.stage_org_connect_ref` | `service_role` |
| **bind** | `:891` | `kernel.set_org_connect_ref` | caller JWT, `org_owner` + aal2 |
| verify | `:1382` `readAccount` | Stripe `GET /accounts/{id}` | platform Stripe key |
| mirror | `:1047` | `kernel.sync_org_connect_state` | `service_role` |

`supabase/functions/stripe-webhook/index.ts:1268` is the second, ongoing caller of
`sync_org_connect_state` on the `account.updated` org arm.

**Answer: yes — through `connect-onboarding`, and through nothing else.** The caveat is
deployment, not code: `connect-onboarding` is undeployed and 093 is not applied to
production (`PRIMARY_TICKETING_ACTIVATION_MATRIX.md:43`). "Today" above means *in this
branch*.

---

## 2. TASK 2 — the intended lifecycle, and whether the re-point verb is launch-critical

### 2.1 The real order is MINT → STAGE → BIND → VERIFY, not bind-after-verify

The lifecycle in the brief (`created → verification → transfers active → authorized bind`)
is **not** what the code does, and the code is right. The bind happens at `index.ts:891`,
immediately after the mint, **before** the operator has entered Stripe's hosted flow.

That is deliberate and safe:

- Binding after verification would mean carrying the `acct_` id across the Stripe redirect
  and back — the stale-callback primitive ruling G §3 closes by making the return URL carry
  no state at all (`isSafeRedirect` refuses any query or fragment, `:184-196`).
- A bound-but-unverified org **cannot sell**: `venue.create_primary_checkout` requires
  `stripe_connect_account_ref IS NOT NULL` **AND** `connect_transfers_active`
  (`093:2645`, `payout_not_ready`). Verification gates the sale, not the bind.
- The two-key property is intact and grant-enforced: staging requires `service_role`
  (proved §3.1[1b]: `authenticated` gets `permission denied for function`), binding
  requires a human `org_owner` on aal2 and raises `42501` on a machine session
  (proved §3.4[4a]: `service_role` gets `permission denied` before the body is even
  reached).

### 2.2 Is `set_org_payout_destination` launch-critical? **NO.**

`kernel.set_org_connect_ref` fully establishes the payout destination. It writes
`stripe_connect_account_ref`, stamps `payout_destination_set_by` (the SoD-1 operand),
consumes `connect_pending_ref`, writes the `org.connect_ref.bind` audit row and emits
`security_payout_destination_changed`. Proved at §3.1[1e]/[1f]. Nothing downstream
distinguishes a destination set by the first bind from one set by a re-point.

**The "no usable caller" finding is about a verb that is not on the launch path.** Do not
build a caller for it. This report recommends against it.

### 2.3 The sharper finding: the re-point verb is *unreachable*, not merely uncalled

`set_org_payout_destination` requires `connect_pending_ref` to be staged
(`093:2995`, `no_pending_connect_ref` — proved at §3.1[1g]). The only staging caller is
`connect-onboarding`, and its mint-and-stage block is inside `if (!accountId)`
(`index.ts:1287`) — it **never** stages a replacement for an already-bound org, by design
(the no-re-mint rule, ruling G T-1). So the re-point path has no staging producer at all.

Consequences, in order of when they bite:

1. **BIND-ONCE plus an unreachable re-point means a mis-bound org is permanently
   mis-bound.** The first bind is the only bind any shipped path can perform.
2. The `409 destination_unusable` arm (`index.ts:1416`) tells the operator to "contact
   support to change your payout destination" — and support has no verb that works
   without a manual `service_role` `stage_org_connect_ref` plus an out-of-band Stripe mint.

This is a **day-2 operations gap, not a launch blocker.** It becomes urgent the first time a
venue rotates a bank/entity or an account goes unusable. The minimum fix is not a new SQL
verb — the verb exists and is correct. It is a `mode: 'replace'` branch in
`connect-onboarding` that (a) requires `org_owner` + aal2 up front, (b) mints a second
account, (c) stages it, (d) calls `set_org_payout_destination` on the caller's JWT. **Not
implemented in this pass** — it is out of the launch scope this task defines, and building
it would be building the caller the brief asks me not to build speculatively.

---

## 3. TASK 3 — attacks on the authority model

Grant surface, read from `pg_proc` on the rehearsal DB:

| function | `authenticated` | `service_role` | `anon` |
|---|---|---|---|
| `set_org_connect_ref` | **t** | f | f |
| `set_org_payout_destination` | **t** | f | f |
| `stage_org_connect_ref` | f | **t** | f |
| `sync_org_connect_state` | f | **t** | f |
| `get_org_connect_ref` | f | **t** | f |
| `get_org_connect_state` | **t** | f | f |
| `request_org_payout` | **t** | f | f |
| `mark_payout_transfer_state` | f | **t** | f |
| `hold_payout` / `release_payout` | **t** (`is_platform` in body) | f | f |

`kernel.organization` carries **no** table or column privilege for `authenticated`,
`service_role` or `anon` — SELECT, UPDATE, and the `stripe_connect_account_ref` column
specifically, all `f`. Every write is through a definer verb.

---

### A1 · an `org_owner` pays themselves by binding a different `acct_` they control

**SQL layer: NOT PROVED.**

```
[1a] set_org_connect_ref(orgA,'acct_ATTACKERPOCKET')  -> precondition_failed: no_pending_connect_ref
[1b] stage_org_connect_ref(orgA,'acct_ATTACKERPOCKET') -> ERROR: permission denied for function stage_org_connect_ref
[1c] (service_role) stage_org_connect_ref(orgA,'acct_ORGAMINTED') -> ok
[1d] set_org_connect_ref(orgA,'acct_ATTACKERPOCKET')  -> precondition_failed: connect_ref_not_platform_minted
[1e] set_org_connect_ref(orgA,'acct_ORGAMINTED')      -> ok, newly_bound=true
[1f] connect_pending_ref=NULL  stripe_connect_account_ref=acct_ORGAMINTED  setby=ownerA
[1g] set_org_payout_destination(orgA,'acct_ATTACKERPOCKET') -> no_pending_connect_ref
[1h] second owner, same call                                 -> no_pending_connect_ref
[1i] org_finance                                             -> insufficient_privilege: org_owner only (SoD-1)
[1j] aal1 owner                                              -> step_up_required
```

RT-A-3's provenance fix holds on both binders, and the staging grant is the load-bearing
line — `authenticated` is refused by the ACL before any body logic runs.

**Stripe layer: PROVED — and this is the finding that matters.**

The `acct_` is provenance-locked. **The bank account inside it is not, and that is the
actual money destination.** `connect-onboarding` step 12 (`index.ts:1470`) issues an
**Express Dashboard login link** whenever `detailsSubmitted && transfersActive`. That branch
sits on the RECONNECT path, *outside* the `if (!accountId)` block, so it is reached with:

- `ONBOARDING_ROLES = ['org_owner', 'org_finance']` (`index.ts:316`) — **`org_finance`
  qualifies**, the role SoD-1 explicitly excludes from naming the payee (`093:2934`);
- **no aal2 requirement** (the step-up check is inside the mint branch, `index.ts:1310`);
- **no `admin_audit` row** and **no `security_payout_destination_changed` emit** — both live
  in the SQL binders, which this path does not call.

From the Express Dashboard the holder changes the external payout bank account. Every
control A7/A9/RT-A-3 built governs *which Stripe account* is the payee; **none governs which
bank account that Stripe account pays out to**, and the weaker of the two org money roles
can reach it silently.

**Verdict: PARTIALLY PROVED.** Not exploitable through SQL; exploitable one layer up, by
`org_finance`, with no audit trail on our side.

---

### A2 · a FORMER org owner triggers a payout or a destination change

**NOT PROVED.** `kernel.has_org_role` is a live join on `kernel.org_member`
(`077:453-466`), so deleting the membership row is immediate and total:

```
[2a] set_org_payout_destination -> insufficient_privilege: org_owner only (SoD-1)
[2b] request_org_payout         -> insufficient_privilege: org_owner or org_finance required
[2c] get_org_connect_state      -> insufficient_privilege: org_owner or org_finance required
```

**Residue worth recording, all confirmed at [2d]:**

- `stripe_connect_account_ref = acct_ORGAMINTED` — the destination they chose survives
  their removal untouched.
- `payout_destination_set_by` still names the removed identity, so the SoD-1 exclusion in
  `request_org_payout` (`087:429`) keeps excluding a person who is gone — harmless, but it
  means SoD-1's operand can name a non-member indefinitely.
- If the departing owner was the Express account holder at Stripe, revoking their
  `org_member` row revokes **nothing** at Stripe. Combined with A1, they keep the ability to
  change the payout bank account through any surviving Express Dashboard session.
- Role revocation emits no `security_payout_destination_changed` and triggers no destination
  re-verification.

---

### A3 · a venue operator crosses an organization boundary

**NOT PROVED, cleanly.** Every verb is org-scoped through `has_org_role`, and no venue role
appears in any role array in this slice.

```
[3a] orgB owner -> set_org_payout_destination(orgA)   -> insufficient_privilege (SoD-1)
[3b] orgB owner -> set_org_connect_ref(orgB,'acct_ORGAREPLACE') -> no_pending_connect_ref
[3c] orgB owner -> get_org_connect_state(orgA)        -> insufficient_privilege
[3d] venue operator (no org_member row anywhere)      -> insufficient_privilege on all three
[3e] (service_role) stage orgA's BOUND acct onto orgB -> conflict_locked: connect account already bound to another org
```

`connect-onboarding`'s endpoint gate (`index.ts:316`) also admits no venue role, and
`kernel.get_org_connect_ref` — the one verb with no role predicate — is protected by its
grant and is called only after the org-role check at `index.ts:1240`.

---

### A4 · `service_role` as an arbitrary money mover

**NOT PROVED for moving money — and the refusal is stronger than the rulings claim.**

```
[4a] set_org_connect_ref        -> ERROR: permission denied for function set_org_connect_ref
[4b] set_org_payout_destination -> ERROR: permission denied for function set_org_payout_destination
[4c] request_org_payout         -> ERROR: permission denied for function request_org_payout
```

Ruling G-12 argues the org plane is safe because these verbs *raise* when `auth.uid()` is
NULL. In fact they are never reached: the ACL refuses first. Two independent controls, and
the outer one is the stronger.

**PARTIALLY PROVED for arming a move.** A leaked key can:

- **[4f]** read the full `acct_` id of any org — `get_org_connect_ref` returned
  `acct_ORGAMINTED`. Ruling G §6.1 bars Connect ids from leaving the trust boundary; a
  leaked key is outside it.
- **[4d]** set `connect_transfers_active = true` on any **bound** org. That boolean is the
  sole operand of the sale gate (`093:2645`), so a leaked key can **turn selling on for an
  organization Stripe has disabled**, making the platform merchant of record for tickets it
  cannot settle. The RT-A-5 hardening blocks the unbound case only — **[4e]** on an unbound
  org correctly raised `org_not_bound`.
- **[8c]** stage any non-individual-plane `acct_` onto any org, arming a latent re-point.
  **`connect_pending_ref` has no TTL, no expiry column and no sweeper** (`sweepers = 0` over
  `pg_proc`); a staged value sits on the row indefinitely waiting for any `org_owner` with
  aal2 to complete it. `orgB` still carried `acct_LATERPERSONAL` at the end of the run.

---

### A5 · a personal seller `acct_` reaches an organization payout destination

**Forward direction: NOT PROVED.** Both the live-profile and the archive arms fire, at both
the stage and the bind door, and the TOCTOU variant is caught because the bind re-checks:

```
[5a] stage a LIVE  profiles.stripe_connect_id      -> account_not_platform_minted_for_org
[5b] stage an ARCHIVED stripe_connect_archive id   -> account_not_platform_minted_for_org
[5c] stage clean -> id becomes personal -> bind    -> account_not_platform_minted_for_org
```

**Reverse direction: PROVED.**

```
[5d] UPDATE public.profiles SET stripe_connect_id='acct_ORGAMINTED' WHERE id=<seller>;
     on_profile = acct_ORGAMINTED   on_org = acct_ORGAMINTED     -- both planes, same account
```

`public.profiles.stripe_connect_id` is unique within its own table and has **no check
against `kernel.organization`**. Nothing prevents an organization's bound payout destination
from also becoming an individual seller's. Two consequences:

1. `supabase/functions/_shared/payouts.ts` — the individual rail — would transfer
   marketplace seller proceeds into the **organization's** Connect account. `create-connect-account`
   writes `profiles.stripe_connect_id` with the service client and no RLS in the way
   (G-12's own finding), so a leaked key is sufficient.
2. It **permanently bricks the org**: the cross-plane refusal in `stage_org_connect_ref` and
   both binders now matches the org's own account, so re-staging and re-pointing raise
   `account_not_platform_minted_for_org` forever.

The cross-plane refusal is a one-way check on a two-way table. Ruling G's own
recommendation — move the individual-plane destination write behind a JWT-bound RPC — is the
fix, and this makes it a launch-adjacent item rather than a scheduled one.

---

### A6 · stale / replacement destination race — **PROVED**

Reproduction, in order, against the rehearsal DB:

```
-- structural
information_schema: kernel.payout columns matching destination|connect|acct  ->  0

INSERT kernel.payout(... status='submitted', idempotency_key='po:race1')      -- claim
[6a] destination at claim                 -> acct_ORGAMINTED
[6b] (service_role) stage acct_RACEDEST
     (org_owner, aal2)  set_org_payout_destination(orgA,'acct_RACEDEST')  -> {"status":"ok"}
[6c] payout row after the re-point        -> status=submitted  hold_state=none  transfer_ref=NULL
     destination now                      -> acct_RACEDEST
[6d] approval_request pinning this payout -> 0
[6e] (service_role) mark_payout_transfer_state(p1,'paid','tr_race')  -> {"status":"ok"}
     payout                                -> paid / tr_race
```

**The destination was re-pointed under a submitted payout, the payout row recorded nothing,
and the terminal write accepted `paid` with no destination predicate of any kind.**

`kernel.payout` has **zero** destination columns. The *only* place a payout's destination is
ever bound is `kernel.approval_request.payload->>'destination_ref'`
(`087:544`), and it is:

- written **only** on the dual-control parked arm — a payout below
  `payout.dual_control_min_minor` advances straight to `submitted` (`087:570`) with no
  destination record anywhere;
- checked **only at request time** (`087:506`, `087:530`), never at execution.

**Secondary damage — the race disarms the next control.** The destination-probation arm
(`087:475-482`) holds "the first payout after a destination change", operationalised as *no
payout of this org reached `paid` since the change*. The raced payout was marked `paid`
**after** the change — audit order at [8a]:

```
org.connect_ref.bind           23:46:29
org.payout_destination.change  23:48:03.347
payout.state_sync (paid)       23:48:03.359
```

so the next payout after the re-point sails through un-held. One race costs two controls.

**Bonus, [8b]: a SUSPENDED organization can still request and advance a payout.**
`request_org_payout` has **no org-status gate**, while 093 added `('approved','active')` to
*both* binders. Suspension freezes the payee and leaves the payout running.

---

### A7 · a disconnected or transfers-disabled account at payout time — **PROVED**

```
[7f] functions reading connect_transfers_active at all:
       kernel.get_org_connect_state · kernel.sync_org_connect_state · venue.create_primary_checkout
     -- no payout function appears

[7a] sync_org_connect_state(orgA, acct_RACEDEST, false, ...)  -> connect_transfers_active=false
[7b] request_org_payout (non-setter org_owner, aal2, matured) -> {"status":"pending_approval"}   ** SUCCEEDS **
[7c] destination NULLed -> request_org_payout                 -> no_payout_destination  ** correctly refused **
```

A payout maturing against an account Stripe has **disabled** proceeds normally. Only a NULL
`stripe_connect_account_ref` is caught. Because no org payout executor exists, the failure
surfaces at Stripe or nowhere — it does not fail closed in our system.

Contrast with the shipped individual rail, which does exactly the right thing at attempt
time: `supabase/functions/_shared/payouts.ts:96` refuses when
`caps.transfers !== 'active'`, **before** spending the idempotency key. The org rail has no
equivalent.

---

## 4. TASK 4 — destination validity as a payout predicate

| predicate | at request (`kernel.request_org_payout`, 087) | at execution |
|---|---|---|
| destination bound (non-NULL) | **ENFORCED** — `087:447` `no_payout_destination` | **MISSING** — no executor; `mark_payout_transfer_state` (`085:1668`) has no destination predicate |
| `connect_transfers_active` | **MISSING** — proved A7[7b] | **MISSING** |
| account not disconnected / disabled | **MISSING** — no concept beyond NULL | **MISSING** |
| destination unchanged since authorization | **PARTIAL** — only the dual-control parked arm, via `approval_request.payload.destination_ref` (`087:506`/`:530`/`:544`) | **MISSING** — proved A6 |
| org not `suspended` | **MISSING** — proved A6[8b] | **MISSING** |
| destination cool-down elapsed | ENFORCED (`087:445`) but **fails OPEN** — `payout.destination_cooldown_hours` is seeded NULL, so `payout_destination_locked_until` is never written ([8d]) | n/a |
| destination probation | ENFORCED (`087:475-482`) but **disarmable** by a paid-after-change payout — proved A6[8a] | n/a |
| SoD-1 setter exclusion · maturity · aal2 · org role | **ENFORCED** | n/a |

**A payout that matures against a destination that has since been disabled does not fail
closed today. It proceeds to `submitted` and, once an executor exists, will be paid to
whatever `kernel.organization.stripe_connect_account_ref` says at that instant.**

---

## 5. The replacement-race answer: bind at claim, re-verify at execution

**Bind the destination at claim time, and re-read it at execution *only as a fail-closed
cross-check* — never as the source of truth.**

Why not re-read at execution as the authority: the money belongs to a settlement whose payee
was decided when `request_org_payout` authorized it, behind SoD-1 exclusion, money-role
maturity, aal2, and (above threshold) a second approver. A re-point landing after that
authorization is a **new** decision that passed **none** of those controls. Letting the
executor re-read means the new destination silently inherits an approval it was never
granted. `087:506` already refuses exactly this staleness at request time (defect E-85); a
pure execution-time re-read re-opens the same hole one step later, where it is worse because
the money actually moves.

Why not bind-at-claim alone: it pays an account Stripe may have disabled between claim and
execution, or one deliberately abandoned — A7's failure, in the other direction.

**The pair is the answer:**

1. Record `destination_ref` on `kernel.payout` at **every** `pending → submitted`
   transition — the direct-advance arm (`087:570`), the approved-request arm (`087:513`),
   and any future path. `kernel.payout` has no such column; 093 can add one additively.
2. The executor sends **that** value to Stripe, never a fresh read.
3. Before sending, assert the recorded value still equals
   `kernel.organization.stripe_connect_account_ref` **and** `connect_transfers_active` is
   true **and** org status ∈ `('approved','active')`.
4. On any mismatch: **do not pay and do not fail.** Return the payout to
   `status='pending'`, `hold_state='held'`, `hold_reason_code='destination_changed'` (or
   `'destination_disabled'`), so a human re-authorizes through the controlled path.
   Fail closed; strand nothing.

**One configuration note that changes the urgency.** `payout.dual_control_min_minor` is
seeded NULL, and X-12's restrictive reading makes every payout park — so *today* the
approval row pins `destination_ref` for every payout and the race is largely masked. **The
moment an owner sets that threshold, every payout below it advances with no destination
record anywhere.** The exposure is created by configuring the system, not by leaving it
unconfigured. Land the `kernel.payout.destination_ref` column before that config key is set,
not after.

---

## 6. Ranked findings

| # | finding | severity | evidence | status |
|---|---|---|---|---|
| F-1 | Replacement race: no destination is bound to a payout outside the dual-control arm; execution has no destination predicate | **P0** | A6 | OPEN |
| F-2 | `connect_transfers_active` is not a payout predicate — a disabled account's payout proceeds | **P0** | A7[7b], [7f] | OPEN |
| F-3 | Express Dashboard login link reaches `org_finance` with no aal2, no audit, no notification; the bank account behind the `acct_` is ungoverned | **P0** | A1, `index.ts:316`/`:1470` | **FIXED §8.1** |
| F-4 | Reverse cross-plane: an org-bound `acct_` can be written onto `public.profiles`, mis-routing seller payouts and permanently bricking the org's re-point | **P1** | A5[5d] | **FIXED §8.2** |
| F-5 | The re-point verb is unreachable (no staging producer for a bound org) — BIND-ONCE makes a mis-bind permanent | **P1** | §2.3 | OPEN |
| F-6 | `request_org_payout` has no org-status gate; a suspended org still pays out | **P1** | A6[8b] | OPEN |
| F-7 | A raced paid-after-change payout disarms destination probation for the next one | **P1** | A6[8a] | OPEN |
| F-8 | `connect_pending_ref` has no TTL and no sweeper — a staged ref arms a re-point forever | **P2** | A4[8c] | OPEN |
| F-9 | Destination cool-down fails open (`payout.destination_cooldown_hours` seeded NULL) | **P2** | [8d] — already recorded in `093_parts/30`'s §5 header | OPEN |
| F-10 | A leaked `service_role` key can arm the sale gate on any bound org and read every org's full `acct_` id | **P2** | A4[4d], [4f] | OPEN |

**Held clean under attack:** the RT-A-3 provenance requirement on both binders; the
`service_role`/human two-key split (grant-enforced, not merely body-enforced); the forward
cross-plane refusal including its TOCTOU variant; live-join role revocation; org-boundary
scoping; the RT-A-5 unbound-org guard on `sync_org_connect_state`.

## 7. Scope note

The remaining open findings land outside this task's permitted edit surface — `kernel.payout`
(085) and `kernel.request_org_payout` (087), both owned by the payout-executor agent.
`docs/phase2/_impl/093_parts/10_money_settlement.sql` was **not touched**.

---

## 8. Fixes landed (second pass, coordinator-directed)

Both are in `docs/phase2/_impl/093_parts/30_connect_org.sql` (canonical) with
`supabase/migrations/093_primary_ticketing.sql` regenerated by `scripts/assemble_093.sh`;
the G-4 integrity gate passes byte-for-byte. Replay 108/108. Full pgTAP 3048 assertions,
4 failures — exactly the documented local-only deltas (060, 132). **Nothing deployed.**

### 8.1 F-3 — `kernel.authorize_org_payout_dashboard` (slice 30 §9) + edge gate

The Express Dashboard login link is the only surface that edits the **external bank
account** behind a bound `acct_` — the destination that actually receives the money — and it
rode the onboarding edge's endpoint gate (`org_owner` **or** `org_finance`, `index.ts:316`)
with no step-up, no audit row and no notification.

**Why a SQL verb rather than three lines in the edge.** That is the RT-A-3 lesson restated:
a control living only in an edge is advisory. SQL cannot make Stripe's link unreachable, but
it *can* make the authorization row and the officer notification structural and put the
authority test in the same place and shape as the two binders. A future caller that skips it
produces no authorization row — a detectable absence, not a silent bypass.

The verb requires a caller JWT, `org_owner` only (SoD-1, matching `set_org_connect_ref`),
aal2, org status ∈ (`approved`,`active`), and a bound destination. It writes
`org.payout_destination.dashboard_grant` / `express_dashboard_login` to `kernel.admin_audit`
and emits `security_payout_destination_changed` to every `org_owner` and `org_finance`,
best-effort in the established `§4`/`§5` pattern. `authenticated` only.

**Two deliberate non-behaviours,** each with a test pinning it:
- it does **not** stamp `payout_destination_set_by` (L6h) — otherwise an owner could clear
  their own SoD-1 payout exclusion (`087:428-431`) by opening a dashboard;
- it does **not** write `org.payout_destination.change` (L6i) — otherwise every dashboard
  open would arm destination probation and hold the next payout.

The edge calls it **before** the Stripe call and fails closed on every arm including a
missing function; `index.ts` maps the refusals to distinct 403/409 codes. The
`account_onboarding` branch beside it is unchanged and deliberately so: it resumes an
unfinished flow on an account that is not yet transfers-active and has no money to redirect
(F §3.4). **Separating the two was not awkward — they were already separate branches doing
categorically different things, and only the shared gate above them hid it.**

Re-verified against the original reproduction:

```
[F3-1] org_finance, aal2   -> insufficient_privilege: org_owner required (SoD-1; org_finance may view … may not open the payout dashboard)
[F3-2] org_owner, aal1     -> step_up_required
[F3-3] service_role        -> permission denied for function authorize_org_payout_dashboard
[F3-4] org_owner + aal2    -> ok; audit row: dashboard_grant / express_dashboard_login / last4=NTED / leaks_acct_id=f / actor=owner
[F3-5] notify envelopes    -> 3 (both owners + finance), origin=express_dashboard_login
[F3-6] suspended org       -> org_not_bindable
```

### 8.2 F-4 — `kernel.guard_connect_id_not_org_bound` + 2 triggers (slice 30 §10)

**Why a trigger and not a check in `create-connect-account`.** There is no verb on that side
to put a check in: `profiles.stripe_connect_id` is written by a direct service-role UPDATE
with no RLS in the way (`create-connect-account/index.ts:217`, `:258`) — ruling G's own G-12
finding. The inbound edge path cannot actually inject an org id anyway, because it writes
`created.id`, minted by Stripe seconds earlier. An edge check would guard the one caller that
was never the threat and miss the two that are: a leaked service-role key, and any future
writer. `BEFORE INSERT OR UPDATE OF stripe_connect_id` on `public.profiles` **and**
`public.stripe_connect_archive` (the binders read the archive with the identical `exists`
clause, so an org id there bricks the org one table over). `SECURITY DEFINER` is required,
not decorative — neither `authenticated` nor `service_role` can read `kernel.organization`.
Both bound and staged-but-unbound refs are refused. Existing rows are reported by a
migration-time `raise warning`, never a hard failure.

```
[F4-1] superuser UPDATE  (the original A5[5d]) -> account_bound_to_organization
[F4-2] service_role UPDATE (the G-12 path)     -> account_bound_to_organization
[F4-3] a STAGED-but-unbound ref                -> account_bound_to_organization
[F4-4] via stripe_connect_archive              -> account_bound_to_organization
[F4-5] NON-VACUITY: acct_REALSELLER            -> writes normally
[F4-6] the org is NOT bricked — re-stage       -> {"staged": true, "status": "ok"}
```

### 8.3 Coverage and census

15 assertions added to `supabase/tests/141_phase2_identity_orgs_deletion.sql` (L6a-L6j,
L7a-L7e), plan 198 → 213, all passing. Two of the five §10 assertions are non-vacuity: a
trigger that refused everything would satisfy the refusal tests and break every seller
onboarding.

Both new functions are `kernel`, so the kernel census moves 117 → 119 and the five-schema
routine total 251 → 253, updated with named commentary in tests 141 (A14, A14a, F2), 142
(K3), 143 (A32), 144 (A14), 148 (B2, B4), 154 (A10), 156 (A20), 157 (A46).
`guard_connect_id_not_org_bound` carries **no grant to anyone** — PostgreSQL does not check
EXECUTE on a trigger function — so it appears in neither the F2 nor the F3 grant list, pinned
by name in A14a. `.github/workflows/ci.yml` `EXPECT_TRIGGERS` 24 → 26 (`EXPECT_FUNCS` is a
`public`-schema counter and is unchanged).

---

## 9. Recorded, as asked — the two things deliberately NOT built

**No caller for `set_org_payout_destination`. Agreed, with the trap stated.** It is off the
launch path (§2.2) and in fact unreachable (§2.3). But the day-2 consequence is real and
someone will hit it: **BIND-ONCE plus an unreachable re-point means a mis-bound organization
is permanently mis-bound.** There is no shipped path that corrects a first bind — not a
wrong entity, not a wrong account, not an account Stripe later refuses. Worse, the edge
*advertises* the recovery: the `409 destination_unusable` arm (`index.ts:1416`) tells the
operator to "contact support to change your payout destination", and support's only route is
a manual `service_role` `stage_org_connect_ref` plus an out-of-band Stripe mint. The verb is
correct and needs no change; what is missing is a `mode: 'replace'` branch in
`connect-onboarding` (owner + aal2 up front → mint → stage → `set_org_payout_destination` on
the caller's JWT). **Not urgent for launch. Urgent the first time a venue rotates a bank or
an account goes unusable, and it should not be discovered then.**

**Nothing about `payout.dual_control_min_minor`. Agreed, and the timing is the point.** The
key is seeded NULL, so X-12's restrictive reading parks every payout and the
`approval_request.payload.destination_ref` pin is currently the only thing binding a
destination to a payout — which is why the F-1 race is partly masked today. **Setting that
threshold is what creates the exposure:** every payout below it advances straight to
`submitted` (`087:570`) with no destination record anywhere. So `kernel.payout.destination_ref`
must land **before** that config key is ever set, not after. The exposure is created by
configuring the system, not by leaving it unconfigured — which is the opposite of how a
config key is normally reasoned about, and is exactly why it needs saying out loud.
