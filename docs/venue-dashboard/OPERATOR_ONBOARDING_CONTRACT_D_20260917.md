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
