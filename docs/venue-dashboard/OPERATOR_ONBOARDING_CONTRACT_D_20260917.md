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
