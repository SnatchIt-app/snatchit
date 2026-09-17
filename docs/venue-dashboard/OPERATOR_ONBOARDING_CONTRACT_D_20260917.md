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
