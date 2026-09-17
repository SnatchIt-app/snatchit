# Operator onboarding — contract draft for migration 138 (D, 2026-09-17)

**Status: DRAFT FOR A'S REVIEW. Nothing built, applied or scheduled. No migration authored.**
Owner decisions of 2026-09-17 relayed through A: D owns implementation, A reviews the contract and 138.
Scoping and verb signatures: `OPERATOR_ONBOARDING_SCOPE_D_20260917.md`. Signatures re-read from the pinned
tree, not from memory.

---

## 0. Three things to settle before 138 is written

Everything else here is mechanical. These three are decisions, and two of them are the owner's.

### 0.1 "Any change elevating someone to organisation ownership/admin authority" cannot be expressed today

`ops.action_requires_approval(p_action_type text)` takes **only the action type**. It cannot see `params`.
But elevation is a property of the *target role*, not of the action: `org_member_role_change` is routine when
the new role is `staff` and elevating when it is `owner` or `admin`. The owner's rule is params-dependent and
the framework's approval predicate is not.

Three ways out:

| | Approach | Cost | Risk |
|---|---|---|---|
| **(a)** | Split the types — `org_member_role_change` vs `org_member_elevate`, `org_member_invite` vs `org_member_invite_admin` — and have **`ops.action_precheck` reject a type/role mismatch** | two extra types, one precheck rule | none once the precheck guard exists; without it the *caller* chooses whether approval applies, which is not a control |
| **(b)** | Change `action_requires_approval` to take the action row | touches a 115 function the whole framework depends on | larger blast radius; A's call, not mine |
| **(c)** | Require approval for **every** member invite and role change | a second person for routine staff invites | over-approves, which is the safe direction |

**Recommendation: (a), and it is only safe with the precheck guard.** If A wants the smallest risk surface for
the first venue, take **(c)** now and narrow to (a) later — over-approving is reversible, under-approving is not.

### 0.2 "Account identifier" needs one word from the owner

The permitted field list has *member display name and account identifier*, and separately restricts *contact
email* to workflows that need it. If the account identifier **is** the email address, the two rules contradict
each other and the restriction is void the moment an operator opens the members list.

**My reading, for confirmation:** a non-secret stable handle that distinguishes two people with the same display
name — the identity UUID, or a masked address (`j••••@gmail.com`) — and **never** the deliverable address. If the
owner means the real email, then §1.4 disappears and the members list carries it, which I would not recommend.

### 0.3 The domain verbs cannot be told who requested the action

`ops.action_dispatch` passes the requester explicitly where the domain verb accepts one —
`public.resolve_transfer_dispute(subject_id, outcome, v_uid, …)` in 118. **The onboarding verbs take no actor.**
`kernel.grant_platform_role` does `v_uid := auth.uid()` then `kernel.is_platform(...)` (077), and the others
follow the same shape. Called from the framework they will resolve `auth.uid()` to the **executing session** —
which for an approval-gated action is the **approver**, not the requester.

This is not a privilege escalation: both parties are platform operators and the domain check still runs, which
is the "preserve stronger existing controls" property (§3.4). It is an **attribution split**: `ops.action`
records requester and approver; the domain's own audit records the approver as actor. Two trails, different
names, same event.

Options are (i) add an optional actor parameter to the onboarding verbs — changes `kernel`/`catalog`/`venue`
signatures, not D's surface; (ii) a GUC the verbs consult — still changes the verbs; (iii) **accept and document**.
**Recommendation: (iii), written into the contract and shown in the UI**, with `ops.action` named as the
authoritative record of who decided. What must not happen is discovering it during an incident.

---

## 1. The read surface — new `ops` functions

`ops.*` **contains no organisation, venue, staff or event read today.** The console cannot list an organisation,
so it cannot offer one to act on. This half does not exist and is the precondition for everything else.

`ops` **is** PostgREST-exposed, so every function here is reachable by anyone holding a session with the console
role. `EXECUTE` goes to the console role only — never `authenticated`, never `anon`. All are
`SECURITY DEFINER` with `search_path = ''`, keyset-paged, and **never cached across requests or users**
(authorization-scoped, per the analytics contract).

### 1.1 Field allowlist (the owner's decision, as a table)

| Field | Exposed | Where |
|---|---|---|
| organisation id, legal name, display name, status | yes | 1.2, 1.3 |
| venue id, name, neighborhood, address, status | yes | 1.3 |
| member display name, account identifier (§0.2) | yes | 1.3 |
| role, invitation status | yes | 1.3 |
| Connect **readiness status** | yes — the status only | 1.2 |
| contact email | **restricted** | 1.4, separately and audited |
| gender | **no** | — |
| bank / tax details | **no** | — |
| Connect account id, secrets, tokens | **no** | — |
| anything else on the account | **no** | — |

### 1.2 Organisations

```
ops.list_organizations(p_status text default null, p_q text default null,
                       p_limit int default 50, p_cursor timestamptz default null)
  -> org_id, legal_name, display_name, status, venue_count, member_count, created_at

ops.get_organization(p_org_id uuid)
  -> org_id, legal_name, display_name, status, created_at,
     connect_readiness text,      -- a status word only: 'not_started'|'pending'|'ready'|'restricted'
     venue_count, member_count
```

`connect_readiness` is derived from `kernel.get_org_connect_state` and **flattened to a word**. The Connect
account reference never leaves the function: returning it would put a payment-provider identifier into a list
view for no operator benefit.

### 1.3 Venues, members, staff

```
ops.list_venues(p_org_id uuid default null, p_status text default null,
                p_limit int default 50, p_cursor timestamptz default null)
  -> venue_id, org_id, org_display_name, name, neighborhood, address, status, created_at

ops.list_org_members(p_org_id uuid)
  -> identity_id, display_name, account_identifier, role, invitation_status, joined_at

ops.list_venue_staff(p_venue_id uuid)
  -> identity_id, display_name, account_identifier, role, granted_at
```

`list_venues` with `p_status = 'pending'` is the approval queue; it needs no separate verb.

### 1.4 Contact email — a separate audited verb, not a column

```
ops.get_org_contact_email(p_org_id uuid, p_reason_code text) -> text
```

Every call writes an `ops.audit_write` row with the operator, the org and the reason code. **The restriction is
the verb, not a convention.** A field an operator is asked to look at "only when needed" but which arrives in
every members list is not restricted — it is merely labelled, and the first careless screenshot ends it. This
is the same rule as the gender-analytics note: *"we don't select it" is not a control.*

`p_reason_code` is a closed set — `onboarding_contact`, `payout_problem`, `legal_request`, `support_escalation`
— so the audit is queryable rather than free text.

---

## 2. The write surface — new action types, no new doors

Nothing here adds a schema exposure. `catalog` and `venue` stay unexposed (406) exactly as the venue kit
asserts. `ops.action_dispatch` is `SECURITY DEFINER` owned by `postgres`, so it reaches those verbs as the
definer; **the browser never does.** Schema exposure is a PostgREST setting, not a privilege — that asymmetry is
what lets the framework be the only door.

### 2.1 Action types

| Action type | Domain verb | Allowed roles | Two-person approval |
|---|---|---|---|
| `org_create` | `kernel.create_organization` | platform_admin | no |
| `org_update` | `kernel.update_organization` | platform_admin | no |
| `org_status_set` | `kernel.set_org_status` | platform_admin | no |
| `org_member_invite` | `kernel.invite_org_member` | platform_admin, platform_support | no *(see §0.1(c))* |
| `org_member_invite_admin` | `kernel.invite_org_member` | platform_admin | **yes** |
| `org_member_role_change` | `kernel.change_org_role` | platform_admin | no *(see §0.1(c))* |
| `org_member_elevate` | `kernel.change_org_role` | platform_admin | **yes** |
| `org_member_remove` | `kernel.remove_org_member` | platform_admin | no |
| `org_invite_revoke` | `kernel.revoke_org_invite` | platform_admin, platform_support | no |
| `platform_role_grant` | `kernel.grant_platform_role` | platform_admin | **yes** |
| `venue_create` | `catalog.create_venue` | platform_admin | no |
| `venue_approve` | `catalog.approve_venue` | platform_admin | **yes** |
| `venue_staff_grant` | `venue.grant_staff_role` | platform_admin, platform_support | no |
| `venue_staff_revoke` | `venue.revoke_staff_role` | platform_admin, platform_support | no |

The approval set is exactly the owner's three: venue approval, platform-role grants, and elevation to
organisation ownership/admin authority.

### 2.2 The precheck guard that makes §0.1(a) a control

`ops.action_precheck` must reject, before anything is dispatched:

* `org_member_role_change` / `org_member_invite` whose target role is `owner` or `admin`
  → *"use org_member_elevate / org_member_invite_admin; this change requires two-person approval"*;
* `org_member_elevate` / `org_member_invite_admin` whose target role is **not** `owner` or `admin`
  → rejected, so the approval-bearing type cannot be used to launder a routine change into a pre-approved slot.

Without the second rule the split is cosmetic. The negative control is the first rule removed: an elevation
requested as a routine role change must then reach `succeeded`, and the test must fail.

### 2.3 Idempotency

Every onboarding verb takes `p_command_key text`. The framework already has `ops.action.idempotency_key`
(`^[A-Za-z0-9._:-]{8,80}$`, unique). **138 derives the command key from the action row** — the action id is the
natural choice — so a retried dispatch of the same action row reaches the domain with the same command key and
the domain's own idempotency holds. The UI must not mint a fresh key per attempt; a retry is the *same* action.

---

## 3. What 138 touches, and the two baselines

This is the part that will go wrong if it is not written down.

| Object | Change | **Redefine from** |
|---|---|---|
| `ops.action.action_type` CHECK | add the 14 types | the constraint as 115 declares it |
| `ops.action.subject_kind` CHECK | add `organization`, `venue`, `org_member` | as above |
| `ops.action_dispatch(ops.action)` | add the case arms | **118's applied body** |
| `ops.action_precheck(...)` | add §2.2 | **118's applied body** |
| `ops.action_allowed_roles(text)` | add the rows in §2.1 | **115's body** (not redefined in 118) |
| `ops.action_requires_approval(text)` | add the three | **115's body** (not redefined in 118) |
| new `ops` read functions (§1) | create | n/a |

**`action_dispatch` and `action_precheck` live in 115 and are redefined in 118. Restoring 115's body silently
reverts 118's corrections.** The other three are 115-only. Both baselines appear in one migration, so the
rollback must restore each object from *its own* applied body, not from one baseline for all five. A has
attached this rule to 138's registry row.

No timestamp-ordering trap: every object 138 redefines is owned by a numbered migration below it.

### 3.1 The four-file rule

Adding the read functions touches four files, not one: the grant-decision manifest
(`supabase/ci/assert_public_table_grant_decisions.sql` — a row per function), the Gate-2 census in `ci.yml`,
`supabase/ci/expected_grants.txt`, and a rollback restoring the applied bodies. The action-framework changes
touch the `ops` census, not the `public` one.

### 3.2 Preserve stronger existing controls

Routing through the framework **adds** approval; it must never replace a verb's own check. `kernel.is_platform`
and `kernel.has_org_role` still run inside each verb when dispatch calls it. A test must prove it: dispatch an
onboarding action as a session without the platform role and assert the **domain** verb refuses, not merely the
framework.

---

## 4. Evidence 138 must carry

* A negative control per approval rule: remove the rule, the action must reach `succeeded`, the test must fail.
* The §2.2 mismatch controls, both directions.
* The §3.2 control: the domain check still refuses under the framework.
* An audit control: every dispatched onboarding action writes an `ops.audit_write` row, and
  `ops.get_org_contact_email` writes one per call.
* A read control: each new read returns **only** the §1.1 columns. Add a column the allowlist excludes and a
  test must fail — otherwise the allowlist is prose.
* Rollback restores each of the five objects from its own applied body; census returns to its pre-138 numbers.

---

## 5. Not in this contract

Events and sessions (`catalog.create_event`, `create_event_session`, `publish_event`) — real onboarding work,
but not needed to stand up the first venue, and each adds an action type and an approval question. Deferred
deliberately.

No part of this is authorization to apply anything. Onboarding actions remain subject to a named execution
window, and the assisted first venue is the owner's to open.

---

## Appendix — baselines and constraints, verified mechanically (D, 2026-09-18)

Added after A's rulings of 2026-09-17: ① take (a) with the precheck guard in both directions;
③ accepted as framed; ② with the owner. 138 carries pgTAP **206**. These are the two things most likely
to go wrong when 138 is written, so they are established now rather than during the write.

### A.1 The two baselines are confirmed, not assumed

Every migration in the chain was searched for a definition of each of the five objects:

| Object | Defined in | Redefined in | 138 redefines from |
|---|---|---|---|
| `ops.action_dispatch` | 115 | **118** | 118's applied body |
| `ops.action_precheck` | 115 | **118** | 118's applied body |
| `ops.action_allowed_roles` | 115 | — | 115's body |
| `ops.action_requires_approval` | 115 | — | 115's body |
| `ops.audit_write` | 115 | — | 115's body |

No other migration touches any of them, so the rollback restores each object from exactly one place.
118 also adds `claimed_until` and `attempt` columns to `ops.action`; it does **not** touch either CHECK.

Every onboarding verb likewise has exactly one definition and no later redefinition:
`create_organization`, `invite_org_member`, `change_org_role`, `set_org_status`, `grant_platform_role`
in **077**; `create_venue`, `approve_venue` in **078**; `grant_staff_role`, `revoke_staff_role` in **080**.

### A.2 The CHECK constraints are 115's inline, auto-named ones

`action_type` and `subject_kind` are declared inline in 115's `create table`, so PostgreSQL named them
(`action_action_type_check`, `action_subject_kind_check` by convention). Nothing alters them afterwards.

**Drop them by name WITHOUT `if exists`.** A `drop constraint if exists` that matches nothing does not fail —
it leaves the old constraint in place, and 138 then applies "successfully" while the first onboarding action
of a new type is rejected at insert. A bare `drop constraint` fails loudly at migration time, which is the
correct moment to learn the name is different. Re-add under the same explicit names.

### A.3 The migration proves its own constraint change

Inside 138's `do $chk$` block, before `commit`: insert a row bearing one new `action_type` and one new
`subject_kind` and assert it succeeds; insert one bearing a bogus `action_type` and assert it is rejected;
roll both back. A widened constraint that silently admits everything, or still admits nothing new, is the
failure this catches — and it catches it in the migration rather than in pgTAP 206, where a fixture could
mask it.

---

## Change log — what the contract got wrong, and what the build corrected (D, 2026-09-18)

Migration written and delivered as `ops/138-operator-onboarding` @ **b49bc55** (off the integrated head
e9b52ce). Applied nowhere. Four corrections to the draft above, each found while building rather than while
writing:

| Draft said | Built as | Why |
|---|---|---|
| "console role only, never `authenticated`" | `grant execute … to authenticated` + `perform ops.assert_reader()` | The 116 house pattern is the opposite shape and **stronger**: assert_reader requires an operator role *and* an aal2 MFA session. The draft line was weaker than what already existed. |
| Five objects redefined, incl. `audit_write` | **Four** | `audit_write` takes `p_action text` and `ops.audit.subject_kind` has no CHECK, so new action names and subject kinds flow through as data. One less baseline to get wrong. |
| Member rows show "display name" | `ops.identity_display_name`, never `ops.actor_label` | `actor_label` falls back to `ops.mask_email(auth.users.email)`, so an accepted member with no profile display name would have shown a masked address on a list where the owner ruled the identifier is the identity UUID. |
| Contact email is the only masked field question | Pending invites needed their own ruling | `kernel.org_invite.invitee_ref` **is** the address and `invitee_identity_id` is null until acceptance, so a pending invite has no other handle. Owner ruled (2026-09-17): masked address for pending invites only, always beside the stable `invite_id`, never searchable, full address only via the audited verb. `ops.mask_email` already existed in 115 and the console already shows `email_masked` on every user card, so this is the established treatment rather than a new concession. |

**One thing the contract did not anticipate at all, now pinned in 206 (B1/B2):** `ops` is the
PostgREST-exposed schema holding the console's privileged surface and it has **no census anywhere** — not
Gate-2 (which counts `public`), not the five-schema pins, not the grant manifest. 206 asserts that every
`ops` function reachable by `authenticated` is `SECURITY DEFINER` with `search_path` pinned and that anon can
execute nothing in `ops`. True today across all 38 such functions. It earns its place: a mutant that added a
function with plain `create function` kept PostgreSQL's default PUBLIC execute grant, and B2 caught it.

**Evidence at b49bc55:** fresh local replay 157/157 with 138 applied, Gate-2 32/107/37/38 (public census
unchanged); pgTAP 206 44/44 with the plan counted programmatically; six negative controls, each on a
baseline verified clean first. The 118-vs-115 baseline rule is proved rather than asserted — the new arms
were spliced into bodies extracted from 118 and both are byte-identical to 118 outside the single insertion,
and after the rollback all four `prosrc` values are byte-identical to 118's and 115's respectively.

---

## Change log 2 — through the front door (D, 2026-09-17; head `7eb4caf` on `ops/138-operator-onboarding`)

Still applied nowhere; off the marketplace candidate by the owner's ruling. Three defects in D's own
migration, each found by asking what a test actually executes:

| Id | Defect | Found by | Now |
|---|---|---|---|
| F-138-2 | `ops.execute_action` validates against hardcoded lists and 138 never touched it, so all fourteen types answered `unknown action_type`. The first cut was **inert** while passing 45 component assertions | A | redefined from 118's applied body; the rollback restores 118's |
| F-138-5 | The routine/elevating guard sat only in `action_precheck`, which runs only for approval-gated types, so it **never ran** for the two routine types whose refusal is the point | D | in `execute_action`, on every action's path; precheck keeps its copy as a second layer |
| F-138-6 | The guard read `coalesce(new_role, role)` while the invite arm reads `role`. A routine invite carrying a decoy `new_role:'org_member'` beside `role:'org_owner'` **wrote an org_owner invite with no second approver** (confirmed on the rehearsal DB) | D, while writing 206's decoy cases | the guard reads exactly the key its arm reads, per type, and refuses the other key outright |

**Evidence at 7eb4caf.** CI 35238876930 succeeded on all five jobs. Its pgTAP footer reads Files=88, Tests=5381, against 5308 at b7ce654; the +73 is 206 going from 45 to 118, the only test file changed. Locally: 206 rewritten to 118 assertions. Section I calls no
component: every action goes through `execute_action`, every decision through `approve_action`, as an
authenticated operator at aal2, and every outcome is read from `ops.action` **and** from the domain table.
38 negative controls were injected inside the suite's own transaction (applied, complete and rolled-back
checks; clean 118/118 between). Every failing set equals the prediction written before the run. One of D's
predictions was wrong and is recorded: removing the self-approval check changed only the message, because
115's `approval_sod_ck` is a second barrier. MS2 removes both and reproduces the predicted effects.
On b7ce654 the new suite fails 65/118, all in section I. Rollback: `ops` functions 100 → 91, with names
and bodies identical to a replay stopped at 136; constraints identical; re-apply identical.

**§4 evidence, now met through the entry point:**
- *Approval rules.* Removing each rule lets venue_approve, elevate and invite_admin reach `succeeded`, and
  their hold and no-effect tests fail. platform_role_grant cannot reach `succeeded` (PFA-4 below), so its
  control is the hold-status test.
- *Mismatch, both directions:* I1–I10.
- *§3.2:* I16–I21, I32, I44, I72–I73. The MX mutants remove the verb's org-role check and those tests fail.
- *Audit:* H4 and I45.
- *Reads:* G7.

### For the owner — facts the build surfaced, each pinned by a test, none decided here
| # | Fact | Pinned by |
|---|---|---|
| O1 | Member, invite and venue-creation verbs (077/078) require the **caller** to be org_owner or org_admin of that organisation. A platform operator with no org role there passes every framework gate and is refused by the verb | I32, I44 |
| O2 | So **platform_support's four framework permissions** (invite, revoke invite, grant or revoke staff) do nothing unless support also holds an org or venue role | I16–I21 |
| O3 | An elevation or admin invite completes only when the **approver** is org_owner or org_admin of that organisation. A second platform_admin who holds no org role there approves, and the verb refuses to run it | I72–I73 |
| O4 | `kernel.create_organization` makes the **creating operator org_owner** of the new organisation | I34 |
| O5 | `kernel.grant_platform_role` is **fail-closed pending PFA-4**: an approved platform-role grant always ends `rejected` | I61, I66 |
| O6 (F-138-7) | `catalog.create_venue` writes `draft`, so a venue the console creates is **not in `list_venues(status => pending)`**, the approval queue this contract names | I41 |
| O7 (F-138-3) | The raw invitee address is stored in `ops.action.params` and in the `action.requested` row's `after.params` in `ops.audit` (not in `kernel.admin_audit`). `authenticated` cannot select either table, but `ops.action_detail`, `ops.list_actions` and `ops.audit_log` return whole rows to **any operator at aal2**. The masked invite label and the audited contact-email read can therefore be bypassed by reading the action log | probe only; not yet a test — the pin depends on the ruling |

---

## Change log 3 — under the owner's rulings on the permission proposal (D, 2026-09-17; head `8ecc929`)

Still applied nowhere; outside the marketplace candidate. What changed from `215694c`:
- **Removed from the console:** `org_create`, `org_update`, `org_member_invite`, `org_member_invite_admin`,
  `org_member_role_change`, `org_member_elevate`, `org_member_remove`, and every `platform_support` write.
- **Added:** `org_bootstrap` (A1) and `org_owner_bootstrap_invite` (A2), the second two-person with a
  required reason. `venue_create` now dispatches A3.
- **Venue staff:** grants refuse any target holding platform authority.
- **Invitee addresses:** held references are released on every terminal state.
- **Delivery:** stays manual, through a verified channel. Nothing sends anything.

### Amendment text for the owner's signature — PFA-33 (proposed id; A places it in `_governance/POST_FREEZE_AMENDMENTS.md`)

> **SIGNED by the owner, 2026-09-17, in D's conversation:** "I approve and sign PFA-33 at governance commit bf7fd66,
> amendment checksum 2da381a1… . Record the signed block exactly as defined in the corrected placement note."
> The signed block is the fenced block below, byte-unchanged. Under A's placement-note rule (fences excluded, no
> trailing newline, UTF-8) it is md5 2da381a1667b0c9e873b709ff3f1d7ce, 5731 bytes, 59 lines, identical at
> `release/candidate-20260918 @ bf7fd66`. The governance record is A's to update.
> Signing PFA-33 does not authorize applying migration 138 (owner ruling 4, same message).

```
ID:                          PFA-33 (proposed)
FROZEN RULES AFFECTED:       RPC §2.1–2.5 (organisation verbs are org-plane: create_organization makes the caller the
                             first org_owner; roster verbs require has_org_role; accept_org_invite binds to the
                             addressed invitee) and RPC §3.1 (create_venue requires has_org_role).
WHY:                         the operator console must onboard a customer organisation without the operator becoming a
                             member of it. kernel is API-exposed and authenticated may execute the roster verbs, so any
                             operator holding an org role can bypass console two-person approval by direct RPC (proposal
                             F3–F4).
OWNER RULINGS (verbatim, 2026-09-17, in chat to D):
  1. "Approve the proposed platform-assisted bootstrap flow and the A1–A4 contract amendments for implementation and
     review. Creating an organization must not make the operator its owner. The customer gains ownership by accepting
     the invitation."
  2. "Remove the seven organization-management console actions identified in §3.1 and support's write permissions."
  3. "Support retains authorized reads and the two audited contact reveals, with the stated purpose restrictions.
     Organization membership must not be a workaround for support access."
  4. "Customer roster management stays on the customer side. Preserve the existing role restrictions and maturity
     rules; do not introduce single-person platform elevation."
  5. "Use manual invite delivery through a verified channel initially. This approves the workflow design, not sending a
     particular invitation or enabling outbound notifications."
  6. "Implement cleanup of held invite addresses when an action becomes terminal. Document that untouched expired
     requests remain retained under lazy expiry, and propose bounded cleanup for those separately. Do not enable a new
     scheduled job under this instruction."
  7. "Approve A4: refuse customer-organization invitation acceptance by identities holding platform authority,
     including the bootstrap admin path. Test the email-change sequence A and D reproduced. Also identify other
     membership-creation paths so the broader 'operators are never members' claim is not inferred from this acceptance
     guard alone."
  8. "Record server-log exposure as unverified. Prepare the exact logging-settings read scope separately; no
     production read is authorized here."
  Also: "Require explicit per-function privilege revokes and tests covering the identified catalog and service-role
  gaps. Preserve PFA-4 and two-person approval."
AMENDMENT:
  A1 kernel.bootstrap_organization(legal_name, display_name, command_key) — platform_admin; organisation at 'applied'
     with NO org_member row; admin_audit org.create reason 'platform_bootstrap'.
  A2 kernel.invite_bootstrap_owner(org_id, invitee_ref, command_key) — platform_admin; runs as the APPROVER of the
     two-person console action; refuses a closed organisation, an organisation with an org_owner, a pending org_owner
     invite, the caller as invitee, and an invitee holding platform authority; writes a pending org_owner invite;
     admin_audit reason 'platform_bootstrap_owner'. A 'suspended' organisation is NOT refused (only 'closed' is), so
     an owner can be bootstrapped during recovery. Owner to confirm this is intended.
  A3 catalog.bootstrap_venue(org_id, name, neighborhood, address, command_key) — platform_admin; draft venue for an
     approved/active organisation; admin_audit venue.create reason 'platform_bootstrap'.
     DEVIATION FROM THE APPROVED WORDING ("a platform_admin arm on catalog.create_venue"): a separate verb, because
     create_venue carries authenticated EXECUTE by frozen contract and an arm inside it could not be console-only
     (principle 4). create_venue's body and grants are unchanged and pinned (206 I86).
  A4 kernel.accept_org_invite — 077's body plus one refusal: an identity for which
     kernel.is_platform(platform_admin, platform_support, platform_risk) holds (including the public.admin_users
     bootstrap) cannot accept. Grants unchanged (206 I87).
  Console-only: A1–A3 revoked from public, anon, authenticated and service_role, asserted per function (206 I84). The
  service_role gap is closed PER FUNCTION for these verbs, not schema-wide (service_role holds intended grants
  elsewhere). The catalog gap: 206 I85 asserts zero PUBLIC/anon EXECUTE on any catalog function.
UNCHANGED:                   the org-plane roster verbs, the tier guard, I-11, AUTHZ-C1B maturity, PFA-4 (platform-role
                             grants fail-closed, 206 I63–I65), 118's approval machinery and approval_sod_ck.
SECURITY IMPACT:             strictly narrowing for operators; no new single-person path to any organisation role.
LIMIT:                       every guard here is per identity (auth.uid()). "Operators are never members" is enforced
                             per ACCOUNT, not per PERSON. A person who holds platform authority on one account and
                             joins a customer organisation with a second, ordinary account is governed by operator
                             account policy, not by these guards. No in-database control or detector can see it.
IMPLEMENTED AT:              ops/138-operator-onboarding @ 0cfa8ba — migration 138 (unapplied, outside the marketplace
                             candidate), rollback supabase/rollbacks/138_ops_operator_onboarding_rollback.sql, pgTAP 206.
OWNER SIGNATURE REQUIRED:    YES (amends frozen RPC §2 and §3). A records how the owner signs.
```

### Membership-creation paths (ruling 7) — so "operators are never members" is not inferred from A4 alone
| Path | Writer (source) | State at 8ecc929 |
|---|---|---|
| (a) accepting an invite | `kernel.accept_org_invite` (077:1147) | **closed by A4**; email-change sequence refused (I36); support (I37) and admin_users bootstrap (I38) refused |
| (b) creating an organisation directly | `kernel.create_organization` (077:811), authenticated over RPC | **OPEN** — a platform identity becomes org_owner (pinned I89–I90). Proposed **A5**: refuse it for identities holding platform authority (they use A1). Needs the owner's word |
| (c) venue staff | `venue.grant_staff_role` (080:224), platform_admin arm | **closed at the console** (I57–I59). STANDING CONDITION: `venue` is not API-exposed; if it ever is, the refusal must move into the verb by amendment |
| (d) platform authority granted to an existing member | `grant_platform_role` (fail-closed, PFA-4); an `admin_users` insert by SQL | **not closed by any guard**. PFA-4 keeps the first shut. The second is out-of-band. Proposed: a read that lists identities holding both platform authority and any org/venue role, as a detector, not a control |
| (e) out-of-band SQL | postgres / service_role writes | outside any in-database control; covered only by access policy and the (d) detector |
| (f) a second, ordinary account held by an operator | any customer path, as an identity with no platform authority | **not closable in SQL** (A, review of 8ecc929). Every guard is per identity; this is operator account policy. Stated as LIMIT in PFA-33 |
Role changes of existing members (`change_org_role`, 077:1244) confer no membership and stay customer-side.

### Lazy-expiry retention and a bounded cleanup proposal (ruling 6)
The terminal-state trigger releases a held address on succeeded, succeeded_at_provider, failed, unknown or rejected
(206 I67–I73). **An expired request nobody touches keeps its reference** (I71), because only `approve_action` writes
expiry. Proposed separately, NOT built:
- an operator-invoked `ops.release_expired_invitee_references(p_dry_run boolean default true)`: platform_admin at aal2,
  audited.
- It lists (dry run), or marks rejected, actions whose pending approval has `expires_at` older than a bound (for
  example 7 days past expiry). The existing trigger then releases their references.
- No schedule. Each run is a person's decision, dry-run first.

### Server logs (ruling 8)
Server-log exposure of request parameters is **unverified**. Stock PostgreSQL does not log bind parameters on error,
and PostgREST binds the request body, but the project's settings have not been read. A has prepared the read scope
(`SERVER_LOG_SETTINGS_READ_SCOPE_20260917.md`). No production read is authorized.

### Evidence at 8ecc929
Local:
- fresh replay Gate-2 32|107|37|38
- every pgTAP file: 87 files, 0 not-ok, 0 errors (5393 assertions)
- 206 = 136
- census pins updated with named additions in ten suites
- 28 mutants, 28/28 on written predictions. Four prediction errors (a test dependency I missed each time) and one
  fixture dependency (I83) are recorded in the harness.
- rollback identical to an exact no-138 replay across ops/kernel/catalog/venue functions (bodies and ACLs), tables,
  triggers and constraints; `accept_org_invite` restored byte-identical to 077; re-apply identical.
CI: run 35247904544 at 8ecc929 succeeded on all five jobs. pgTAP footer: Files=88, Tests=5399, Result: PASS; 206 ok.
The total matches the written prediction (5424 at be80aad minus 25, the only count change being 206 going from 161 to 136).
The local run above covered 87 of the 88 files, so CI is the evidence for the full set.

### Independent review at 8ecc929 (A, 2026-09-17): no defect found
A verified CI 35247904544 and a local fresh replay (Gate-2 32|107|37|38). Suites 206 136/136, 141 213/213, 140 59/59,
142 261/261, 144 118/118 and 181 128/128 passed.
Effective EXECUTE ACLs (coalesce(proacl, acldefault)):
- A1, A2, A3, the helper and the release trigger function: no anon, authenticated, service_role or PUBLIC.
- accept_org_invite, create_organization and create_venue: authenticated only, unchanged.
A2 locks the organisation row, so concurrent bootstrap invites serialise.
Answers to D's four points:
- (a) The only membership-creating writes in migrations are 077:811, 077:1147 (redefined at 138:1282) and 080:224. A
  added path (f), a second ordinary account, recorded above.
- (b) Agreed.
- (c) No current leak. Hardening is not required for the verdict, but A recommends it before 138 is applied anywhere.
- (d) Agreed.
Observation for the owner: A2 does not refuse a suspended organisation (recorded in A2's text above).

### Hardening at 0cfa8ba — a failing bootstrap invite records fixed text (A's point c)
What: in the bootstrap-invite dispatch arm, the recorded outcome message is no longer `replace(sqlerrm, ref, label)`.
Each of the 11 messages kernel.invite_bootstrap_owner raises maps to its fixed leading text (checked: 11 raises, 11
prefixes). Anything else becomes `invite verb failed; message withheld (sqlstate …)`. The header says so.
Why: the outcome lands in ops.action and ops.audit, which every operator reads. At 8ecc929, a verb message quoting the
reference lower-cased or trimmed passed the exact-string mask. No current message did, so this was not a live leak.
Tests: 206 I99–I102 (plan 136 → 140). A padded, mixed-case reference is requested, the approver comes to hold it
lower-cased, and the verb refuses. The outcome is fixed text, and no ops.action or ops.audit row holds any spelling.
Evidence (local):
- RED, written first, on 8ecc929's code: only I101 failed, because it recorded the verb's full message.
- MC0 (the verb quotes lower(trim(ref))) on 8ecc929 failed I101 and I102: the address reached 2 rows.
- Fresh replay Gate-2 32|107|37|38.
- Local pgTAP: 87 files (the local runner covers 87 of the 88), 5397/5397, ALL-PASS; 206 140/140.
- Green mutants (scratchpad mut206_c.py), 6/6 on written predictions:
  - MC1, the verb quotes the lower-cased ref: survives. That is the hardening working.
  - MC2, back to replace(): fails I101.
  - MC3, MC2 plus the quoting verb: fails I101 and I102.
  - MC4, an unknown verb message quoting the ref: fails I101 only; it is withheld.
  - MC6, the self_invite mapping dropped: fails I101.
  - MC5, the fallback passes sqlerrm plus an unknown message: fails I101, I102, I77, I79 and I80.
- One prediction was wrong: MC5 was written as I101 and I102. It removes all masking from the self_invite refusal, which
  I42's flow reaches with later.b@example.com, so I77/I79/I80 also caught it. Corrected in the harness with that reason.
- Rollback at 0cfa8ba: identical to an exact no-138 replay (functions 352, tables 50, triggers 51, ops.action
  constraints 9); accept_org_invite back to 077 (a7bd0984…); re-apply identical (367 functions).
- The 28 mutants in mut206_v3.py were run at 8ecc929 and not re-run here. This delta changes only that exception
  handler's message, and none of those mutants touches it.
CI: run 35249486531 at 0cfa8ba succeeded on all five jobs. pgTAP footer: Files=88, Tests=5403, Result: PASS; 206 ok
(5399 + the 4 new assertions, as predicted).

## Change log 4 — the owner's rulings after PFA-33 (D, 2026-09-17; head `5960b51` on `ops/138-operator-onboarding`)

### The owner's rulings (verbatim, in D's conversation; also received by A directly)
> I approve and sign PFA-33 at governance commit bf7fd66, amendment checksum 2da381a1… . Record the signed block exactly
> as defined in the corrected placement note.
> For the remaining 138 decisions:
> 1. A suspended organization may receive a recovery owner invite only when it has no current owner, using the same
>    two-person approval, identity checks and audit controls. No invite may replace an existing owner.
> 2. Approve A5: prevent a platform-authority identity from directly creating an organization and becoming its owner.
>    Route creation through the approved platform bootstrap flow.
> 3. Approve the names-only detection read for platform identities who also hold organization membership. It must be
>    read-only, scoped, and reported without exposing unrelated personal data.
> 4. Do not apply migration 138 yet. Integrate A5 and the approved amendment, rerun the front-door tests and review,
>    then bring me a new apply package.
> 5. Defer the server-log settings read; it remains a separately authorized production-read question.
> Keep 138 outside the marketplace candidate. Continue the Build 19 handset checks and the already-approved sandbox
> work independently. DV-ST2b may run before Line 3, but Line 3 remains a separate irreversible authorization and must
> not start until I explicitly say "ready for Line 3."

### What changed at d5fb9ae (code) and 5960b51 (test output only)
- **A5 (ruling 2).** `kernel.create_organization` is 077's body plus one refusal. An identity for which
  `kernel.is_platform(platform_admin, platform_support, platform_risk)` holds, including the `public.admin_users`
  bootstrap, gets `42501 insufficient_privilege: platform_authority`. Operators create through `org_bootstrap` (A1).
  Grants are unchanged (206 I133), and the rollback restores 077's body.
- **Recovery (ruling 1).** The verbs already allowed a suspended organisation with no owner, so the new tests pin the
  behaviour and one audit field was added:
  - A2's `kernel.admin_audit` row now carries `org_status`, so a recovery is distinguishable.
  - The rest of the flow is unchanged: the same two-person action, the same identity checks, refusal at request
    (precheck) and at execution (the verb) once an owner exists.
- **Detection read (ruling 3).** `ops.list_platform_identity_memberships()`:
  - Callable by platform_admin at aal2 only. It is STABLE, so the database refuses any write inside it, and it writes
    nothing.
  - Returns exactly (platform_authority, identity_name, organization_name, org_role). There is no identity id, no
    address and no organisation id. A missing display name reads `(no display name)`.
  - Scope follows the ruling: organisation membership only. Venue staff are not included; that is a one-line
    extension if the owner wants it.
- **A6, proposed (D's reading of "No invite may replace an existing owner"; the owner confirms or strikes).**
  `kernel.accept_org_invite` refuses an invite whose role is not org_owner when the accepter is currently an org_owner
  of that organisation (`precondition_failed: owner_role_change`). The check runs under the organisation row lock.
- **F-138-12 (D; confirmed in source by A).** 077's acceptance does
  `insert … on conflict (org_id, identity_id) do update set role = excluded.role, granted_by, granted_at = now()`.
  - Probe on the local replay at 0cfa8ba: a sole org_owner invites their own address at org_member, accepts, and the
    organisation has 0 owners.
  - `change_org_role` refuses exactly that (077:1234–1240), and `remove_org_member` refuses the removal equivalent
    (077:1330).
  - An org_admin can also invite the owner's address at a lower tier. If the owner accepts, the owner is demoted by an
    admin's invite, which bypasses "only an org_owner may change an org_owner".
  - 077 is in production.
- **Other effects of that upsert on an EXISTING member, stated as facts for the owner and NOT changed** (A asked;
  compared with `change_org_role`):
  1. Self-promotion is not reachable through an invite. Only org_owner and org_admin can invite, and only an org_owner
     can invite at org_owner.
  2. The maturity clock (AUTHZ-C1B) resets on EVERY acceptance, including lateral moves, demotions and an owner
     re-accepting an owner invite (A6 allows that). `change_org_role` resets only on promotion INTO a money role. The
     reset never shortens maturity, but it can restart an owner's clock.
  3. A role change through acceptance emits no `security_org_role_granted/revoked` notice and writes
     `org.invite.accept`, not `org.role.change`.
  4. Whether an existing member's re-acceptance at the same or a lower role should be a no-op is an owner question.
     A6 answers it only for owners.
- **141 (fixture only).** Sections K, L and P had `tap.admin_user()` (a platform_admin through `public.admin_users`)
  create org1 and act as its owner. A5 refuses that.
  - org1's owner is now a customer identity, `tap._o141()`.
  - Only L0d, the platform approval, runs as the admin.
  - Every assertion is textually unchanged except the owner identity it names (K2, K10, K11, L2, L6f, L6h). 141 is
    213/213.
- **Header correction.** The 8ecc929 and 0cfa8ba headers said "SEVEN OBJECTS REDEFINED" but listed six. With
  create_organization the count is seven and the list matches.

### Evidence at 5960b51
Local:
- RED, written first, on 0cfa8ba's code: A5 (I89, I90, I103–I105, I107), I111 and A6 (I118, plus the I119–I122
  cascade: without A6 the sole owner was demoted) failed. The detector did not exist.
- Fresh replay: Gate-2 32|107|37|38. Census ops functions 91→104 (+13), kernel 157→159, catalog 17→18, ops tables
  13→14.
- Local pgTAP: 87 files, 5428/5428, ALL-PASS; 206 171/171; 141 213/213.
- `mut206_d.py`: 14/14 on written predictions. One was corrected after its first run: MD-anon-granted was written as
  I131, and also failed B2 (206's "anon can execute NOTHING in ops"). The reason is recorded in the harness.
  - A5 removed: I89, I90, I103–I105, I107, I125.
  - A5 admin-only: I104, I107, I125.
  - A5 ACL widened: I133.
  - A6 removed: I118–I122.
  - A6 last-owner-only: I121, I122. This is what makes the "any owner" wording testable.
  - Audit status dropped: I111.
  - A2 refuses suspended: I110–I114, I116.
  - owner_exists not rechecked: I46, I74, I92, I93, I115, I116.
  - Detector admits support: I127. No gate: I127, I128. Exposes the identifier: I125, I126. Misses admin_users: I125.
    Volatile: I130. anon granted: B2, I131.
- `mut206_c.py` (outcome-message hardening): 6/6 at plan 170, before I133 was added.
- `mut206_v3.py` (28) stands at 8ecc929 and was not re-run: its predictions predate I99–I133.
- Rollback: identical to an exact no-138 replay (functions 352, tables 50, triggers 51, ops.action constraints 9).
  accept_org_invite is a7bd0984…, create_organization is 11a046a6…, both with ACL
  `{postgres=X/postgres,authenticated=X/postgres}`. Re-apply is identical (368 functions).
- The 14 mutants were re-run on 5960b51's suite text: 14/14.
- Every local pgTAP output was parsed with TAP::Parser, the parser pg_prove uses: 87 files, tests_run 5428, no
  failures, no parse errors.
CI:
- d5fb9ae, run 35255295038: FAILED. 206 reported "Tests: 173, Failed: 170-171" against plan 171. Two unasserted setup
  calls returned the text `ok`, which pg_prove counts as tests. The local runner counts only numbered lines, so it
  passed. Reproduced by parsing the local output with TAP::Parser (tests_run=173, failed 170,171).
- 5960b51 prefixes every unasserted setup call with `setup: `. No assertion changed.
- 5960b51, run 35255707849: succeeded on all five jobs. pgTAP Files=88, Tests=5434, Result: PASS; 141 ok, 206 ok.
  That is 5403 + 31 (206: 140 → 171).

### Follow-on amendment text — PFA-34 (proposed; placed by A at governance b7895bb on release/candidate-20260918)
The block below is mirrored from the placed text, so the two records carry the same checksum: under the PFA-33/PFA-34
extraction rule (the fenced block, fences excluded, no trailing newline, UTF-8) it is md5 026cb858319bc7c0181e1dad01e23ef1,
2726 bytes, 27 lines, verified by D against b7895bb. The only change from D's source block (ea1c2999…) is the ID line,
which D's own text invited. PFA-33's block is untouched (2da381a1…, 5731 bytes, 59 lines).
```
ID:                          PFA-34 (proposed) — follow-on to PFA-33
FROZEN RULES AFFECTED:       RPC §2.1 (create_organization makes the caller the first org_owner) and RPC §2.3
                             (accept_org_invite binds the addressed invitee and writes the invite's role).
WHY:                         owner rulings 1–3 of 2026-09-17, given after PFA-33 was signed.
AMENDMENT:
  A5 kernel.create_organization — refuses any identity holding platform authority (platform_role, or platform_admin
     through public.admin_users). Operators create organisations only through the console's org_bootstrap (PFA-33 A1).
     Customers' self-service creation is unchanged.
  R1 Recovery — a SUSPENDED organisation with no current org_owner may receive the PFA-33 A2 owner invite through the
     same two-person action, identity checks and audit. It is refused whenever an org_owner exists, at request and at
     execution. The domain audit records the organisation's status at issue. No invite replaces an existing owner.
  A6 kernel.accept_org_invite — APPROVED by the owner, 2026-09-17: "accepting an invite must never overwrite or
     demote an existing organization owner." It refuses an invite whose role is not org_owner when the accepter is
     currently an org_owner of that organisation, checked under the organisation row lock. An owner's role changes
     only through kernel.change_org_role, which enforces the last-owner and owner-tier rules. The owner also ruled:
     "Keep the existing maturity-clock and audit behavior unless a separate change is approved" — so an owner
     accepting an org_owner invite still rewrites granted_by, still resets granted_at, and is still audited as
     org.invite.accept. That is pinned by 206 I134-I136, so a later change to it cannot pass silently.
  D1 ops.list_platform_identity_memberships() — a detector, not a control: platform identities holding organisation
     membership. platform_admin at aal2; read-only (STABLE; writes nothing, including no audit row); returns names
     only (authority, identity name, organisation name, role). Running it against any hosted project is a read the
     owner authorizes for that project.
UNCHANGED:                   PFA-33 A1–A4 and its LIMIT; the tier guard, I-11, AUTHZ-C1B maturity; the invite verb;
                             acceptance for non-owners (the upsert's other effects are recorded as facts, not changed).
IMPLEMENTED AT:              ops/138-operator-onboarding @ a9aa34e — migration 138 (unapplied, outside the marketplace
                             candidate), rollback supabase/rollbacks/138_ops_operator_onboarding_rollback.sql, pgTAP 206.
OWNER SIGNATURE REQUIRED:    YES.
```

### Apply-package inputs (D → A; A assembles the package and brings it to the owner; nothing here authorizes anything)
1. **Artifact.** `supabase/migrations/138_ops_operator_onboarding.sql` @ 5960b51 (the migration is unchanged since d5fb9ae). It is one transaction, and its
   in-file sanity block aborts the whole migration on any mismatch, so a failure leaves nothing applied. Rollback:
   `supabase/rollbacks/138_ops_operator_onboarding_rollback.sql`. It restores code, not data. It refuses rather than
   narrowing the CHECK constraints if rows with a 138 action_type exist.
2. **Prerequisites.**
   - 077, 078 and 080 (kernel, catalog, venue) and 115 and 118 (ops) must be applied.
   - Production: A's release package records 115–120 applied on 2026-09-08.
   - Sandbox ofaidukbieeekqaboscm: my witness reads show NO `ops` schema (`ident_no_ops=true`), so a sandbox apply of
     138 first needs 115–120 there. That is a separate, owner-authorized step.
3. **Pre-apply reads, each authorized per target project.**
   - (a) The ledger contains 077, 078, 080, 115 and 118, and not 138.
   - (b) md5(prosrc) and ACL of the seven objects 138 redefines match an exact no-138 replay:
     - `ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)` 67cd21460e02fb5e53aa0e01e9858a03, ACL
       `{postgres=X/postgres,authenticated=X/postgres}`
     - `ops.action_dispatch(ops.action)` b37e66a70168c79b5eed9dccaf0d1917, ACL `{postgres=X/postgres}`
     - `ops.action_precheck(ops.action)` 00e2e682a7ce88db32c9268dd264d066, ACL `{postgres=X/postgres}`
     - `ops.action_allowed_roles(text)` 98d8aba103710706fd8fb6d4081a0a1c, ACL `{postgres=X/postgres}`
     - `ops.action_requires_approval(text)` 57174426627268e60df6bae330f58b8a, ACL `{postgres=X/postgres}`
     - `kernel.accept_org_invite(uuid,text)` a7bd098425f1ca041f402449bba4e1a9, ACL
       `{postgres=X/postgres,authenticated=X/postgres}`
     - `kernel.create_organization(text,text,text)` 11a046a68ef5f48e0b6d0ab62f2a6d7d, ACL
       `{postgres=X/postgres,authenticated=X/postgres}`

     Any mismatch is a stop: the rollback would restore the repo body over something else.
   - (c) The detection query, run before apply as a names-only standalone read. A4 and A5 stop NEW memberships; they
     remove none that already exist. Its text is the function body without the gate, and it is sent to the owner
     before any run.
   - (d) A census of ops/kernel/catalog function counts and ops table count, for the post-apply delta.
4. **Post-apply verification.**
   - Deltas: ops functions +13, kernel +2, catalog +1, ops tables +1, triggers +2 (action_invitee update refusal;
     release on ops.action). public census unchanged.
   - `kernel.bootstrap_organization`, `kernel.invite_bootstrap_owner`, `catalog.bootstrap_venue`,
     `ops.identity_holds_platform_authority` and `ops.action_invitee_release_on_terminal` are executable by none of
     public, anon, authenticated or service_role.
   - `create_organization` and `accept_org_invite` ACLs are unchanged.
   - `ops.list_platform_identity_memberships` is executable by authenticated only.
5. **Blast radius.**
   - Operators can no longer create organisations directly or accept customer invites.
   - An owner can no longer be demoted by accepting an invite (if A6 is kept).
   - Onboarding console actions become available; they require platform_admin, and invites require two people.
   - No public-schema change, no data migration, no notification, no job.
6. **Owner approval points.**
   - Each pre-apply read, per project.
   - The sandbox apply, including 115–120 there, if chosen.
   - The production apply.
   - The follow-on amendment's signature, including the A6 decision.
   - The server-log settings read stays deferred (ruling 5).

## Change log 5 — A6 approved; A's review of 5960b51 (D, 2026-09-17)

### A's independent review of 5960b51: PASS, with two findings
A verified CI 35255707849, a local replay (157 migrations, Gate-2 32|107|37|38, 5428/5428, 206 171/171, 141 213/213),
re-parsed every file with TAP::Parser (87 files, 5428, no parse errors; plus 000_helpers' plan(6) = CI's 5434),
diffed the two kernel bodies against 077 as extracted text, recomputed all seven pre-apply md5s from the migration
text independently, and ran eight of its own mutants with predictions written first.
- **F-A6-TEST (test gap, fixed below).** Nothing pinned A6's `v_inv.role <> 'org_owner'` clause: an A6 that refused
  EVERY acceptance by an owner killed no test in 206 or 141.
- **F-ACL-REPLAY (apply package, adopted).** The pre-apply ACL strings come from a local replay running as superuser
  with parity grants, and a hosted project's ACLs can legitimately differ. Adopted: a prosrc md5 mismatch stays a hard
  stop; an ACL mismatch is report-and-decide, with the expectation taken from a real Supabase stack (a local
  `supabase start` at CLI 2.115.0 avoids any hosted read).
- A also recorded a lead that is not a 138 defect: CI's 141 prints
  `notify.emit_event(unknown, unknown, uuid, text, jsonb) does not exist` from request_account_deletion's best-effort
  emit. It appears on 0cfa8ba and on the candidate 6561d1f too, so it predates this work. It may bear on F-NOTICE-1.

### The owner's ruling (verbatim, 2026-09-17)
> Approve A6 for the follow-on amendment: accepting an invite must never overwrite or demote an existing organization
> owner. Keep the existing maturity-clock and audit behavior unless a separate change is approved. Add tests for a sole
> owner, multiple owners, lower-role invites and concurrent acceptance, with rollback evidence.

### What was added
- **206, plan 171 → 178.**
  - I134a, I134: a non-member accepts an org_owner invite and becomes an owner; that owner then accepts a SECOND
    org_owner invite and it succeeds. This is the positive case F-A6-TEST asked for.
  - I135: still org_owner, and the row was overwritten as before (granted_by is the second inviter).
  - I135b: the maturity clock still resets. `now()` is frozen inside the suite's transaction, so the row is backdated
    ten days first, the way 141 K12 does it; without that the reset is invisible.
  - I136: the audit is unchanged — one org.invite.accept row, and still no org.role.change.
  - I137, I138: an org_admin invite and an org_finance invite cannot demote an owner either, in two other
    organisations, so the refusal is not one role label's accident.
- **`scripts/rehearsal_138_a6_concurrency.sh`** — two real sessions, loopback only, OUTSIDE pg_prove (pgTAP runs in one
  transaction and cannot show a lock wait or a committed breach). Its evidence is its own output:
  - S1 forward: with an org_owner acceptance open and uncommitted, an owner's lower-role acceptance BLOCKS on the
    organisation row — shown by `pg_blocking_pids`, not by timing — and is refused (owner_role_change) after the
    holder commits. Owners 3.
  - S2 reverse: with the organisation row held by another session, a legitimate org_owner acceptance blocks and then
    SUCCEEDS. A6 serialises; it does not refuse legitimate acceptance.
  - S3 race: two owners accept lower-role invites simultaneously; both refused; both still owners.
  - C1 control: the same race against 077's acceptance body — both COMMIT and the organisation is left with ZERO
    owners. That is the breach A6 closes, committed, on the same fixture.
  - C2 control, the rollback RED direction: on the same fixture, 138 refuses the sole owner's lower-role acceptance
    (owners 1); after `supabase/rollbacks/138_ops_operator_onboarding_rollback.sql` the identical call succeeds and
    owners drop to 0.
  - Run at 2026-09-17 on a scratch replay database: ALL PASS (S1, S2, S3, C1, C2).

### Evidence
- Local pgTAP: 87 files, 5435/5435, ALL-PASS; TAP::Parser on every file: 87 files, tests_run 5435, no failures, no
  parse errors.
- `mut206_d.py`: 16/16 on written predictions, including the two new ones the gap called for —
  MA6-over-broad-any-acceptance kills I134, I135, I135b, I136; MA6-org_member-only kills I137, I138.
- Three earlier predictions were corrected, each with its reason recorded in the harness: MA6-removed,
  MA6-last-owner-only and MR-suspended-refused now also name the new tests they cascade into. They were written for
  the 171-assertion suite, before I134–I138 existed.
- Rollback: unchanged from change log 4 (identical to an exact no-138 replay; re-apply identical), now with the RED
  direction above.
CI: head `a9aa34e`, run 35257712408, all five jobs success. pgTAP Files=88, Tests=5441, Result: PASS; 206 ok.
That is 5434 + 7 (206: 171 → 178). The migration and rollback are byte-identical to 5960b51; a9aa34e adds tests and
the concurrency script only.

### PFA-34 placement, verified by D (2026-09-17)
A placed the amendment at governance `b7895bb` on `release/candidate-20260918`, status PROPOSED, NOT SIGNED. D
verified it independently against that commit: the placed block is md5 `026cb858319bc7c0181e1dad01e23ef1`, 2726 bytes,
27 lines, under the same extraction rule as PFA-33, and a line-by-line diff against D's source block
(`ea1c2999dc1099f869e23eb227c1671f`) shows exactly ONE difference — the ID line, which D's own text invited. The block
above now mirrors the placed text, so both records carry the same checksum. PFA-33's block is untouched
(`2da381a1667b0c9e873b709ff3f1d7ce`, 5731 bytes, 59 lines).

### Open test-precision item (A's nit on I136; not load-bearing)
I136 adds two counts and asserts the sum is 1, so a compensating pair (0 `org.invite.accept` rows and 1
`org.role.change` row) would also pass. The MA6 mutants kill it either way, so coverage is intact. Splitting it into
two assertions is deliberately DEFERRED: a test-only head now would make PFA-34's IMPLEMENTED AT commit stale while it
sits with the owner for signature. It goes into the next 138 head, whenever one is needed — for example if the owner
extends D1 to venue staff.

### The 115–120 sandbox prerequisite: D agrees with A's recommendation, with D's own reasons
A recommends not applying 115–120 to the sandbox during the sprint, and treating CI, both replays, the mutants and the
two-session proof as the rehearsal. D agrees, having checked the two claims in source rather than taking them:
- `117_ops_console_automation.sql:1123-1126` schedules `ops-detect-tick` every 5 minutes and `ops-daily-summary`
  daily. Every witness read D has taken pins `cron jobs=22 active=22 list_md5=c2c5c079fd854567942f821e5ab57a8e`; two
  new jobs change that fingerprint and start detectors that WRITE (ops.job_run, ops cases) from live sandbox data.
- `119_listing_block_insert_guard.sql:46,103` creates one PUBLIC function and one PUBLIC trigger. D's sandbox census
  counts the public schema only, so the W-C3 closing figure 32|109|37|37 would become 32|110|37|38 mid-sprint, and the
  Line 3 reconciliation would be comparing against a moved baseline.
- D's witness scripts also use `to_regnamespace('ops') is null` as the sandbox-versus-production identity check. After
  a 115–120 apply that check flips, so every earlier read's identity line stops being comparable and D would need a new
  discriminator before the next witness.
If the owner wants a hosted rehearsal of 138, D's position is the same as A's: it is its own window, after the sprint,
with the census baselines re-taken first.

## Change log 6 — ruling 6 (venue staff in the detector) and the PFA-34 divergence it creates (D, 2026-09-17)

### The owner's decisions of 2026-09-17, after signing PFA-34 (verbatim)
> 1. I sign PFA-34 at governance commit b7895bb, checksum 026cb858… . Record the amendment exactly; signing does not
>    authorize applying migration 138.
> 2. Keep the per-project pre-apply checks and exact function-hash verification in the package.
> 3. Approve the names-only detection read, restricted to an MFA-authenticated platform admin, with no emails, IDs or
>    unrelated personal data.
> 4. Do not apply migrations 115–120 to the sandbox during this sprint. If a hosted 138 rehearsal is needed, prepare it
>    as a separate future window with fresh baselines and a replacement environment check.
> 5. Do not authorize any production apply.
> 6. Extend the detection read to include platform identities holding venue-staff roles. Carry the deferred test split
>    with that change and send the revised head for review.

PFA-34 is therefore SIGNED at governance `b7895bb`, block md5 `026cb858319bc7c0181e1dad01e23ef1` (2726 bytes, 27
lines), verified by D against that commit. Signing does not authorize applying 138, and no production apply is
authorized.

### Ruling 6 implemented, held locally
`ops.list_platform_identity_memberships()` now returns
`(platform_authority, identity_name, membership_kind, organization_name, venue_name, role)` and covers
`kernel.org_member` AND `venue.staff_role`, joined to the venue's organisation. Still platform_admin at aal2, still
STABLE, still names only — no identity id, no organisation or venue id, no address. 206 goes 178 → 180: I125 pins the
five overlaps (three organisation, two venue), I139 pins a venue-only overlap (platform authority plus a venue staff
role and NO organisation membership), I129 pins the six-column result, and A's nit is closed by splitting I136 into
I136 (exactly one `org.invite.accept` row) and I136b (no `org.role.change` row).

Local evidence: replay Gate-2 32|107|37|38; 206 180/180 with a clean TAP::Parser pass; `mut206_d.py` 19/19 on written
predictions, including three new ones — MD-venue-missed (kills I125, I139), MD-venue-name-dropped (I125) and
MA6-audit-writes-role-change (I136b, which otherwise had no killing mutant). Two predictions were corrected after their
first run, each with its reason recorded in the harness: MD-exposes-identifier also kills I139, which selects on the
display name.

**The head is committed locally as `1cacdf5` and deliberately NOT pushed, with no CI run**, because the owner narrowed
the away-period scope to "migration 138/PFA-34 documentation review only". It goes to A with its CI when the owner
returns.

### Documentation finding: PFA-34's D1 clause and ruling 6 diverge
PFA-34, as signed, says D1 lists "platform identities holding organisation membership". Ruling 6 widens the detector to
venue staff. The moment the head above lands, the signed amendment and the implementation will disagree about D1's
scope. That is a governance item, not a code defect, and it needs the owner's signature either way.

Proposed replacement clause, for A to place as an erratum to PFA-34 or as its own follow-on (A assigns the id):

```
  D1 ops.list_platform_identity_memberships() — a detector, not a control: platform identities that hold
     organisation membership OR a venue staff role (owner ruling 6, 2026-09-17, widening the clause signed in
     PFA-34). platform_admin at aal2; read-only (STABLE; writes nothing, including no audit row); returns names
     only — authority, identity name, membership kind, organisation name, venue name, role — and no identity,
     organisation or venue id. Running it against any hosted project is a read the owner authorizes for that project.
```

Until that is placed and signed, the contract records the divergence rather than papering over it.

### Away-period scope (owner, 2026-09-17)
> Finish the independent DV-ST2b after-read and API-log evidence when A's ten-minute window completes. Confirm the
> final classification and preserve the "rows stayed visible; message not captured" limitation. Review A's F-NOTICE-1
> fix once the branch arrives. Require a regression test proving withdrawal retires only the pending deletion notice
> for that user and does not affect other notice types. Review any F-BIDS-1 or candidate merge updates that arrive; do
> not request another build. Continue migration 138/PFA-34 documentation review only. Keep 138 and migrations 115–120
> unapplied and do not run detection or server-log reads. Prepare the witness checklist for Line 3, but do not execute
> permanent transfer writes or upload proof while I am away. No production reads, production changes, sandbox writes,
> secrets, push key, payouts, outbound notifications or new builds are authorized.

D's Line 3 checklist is prepared at `docs/venue-dashboard/LINE3_WITNESS_CHECKLIST_D_20260917.md` and executes nothing.
