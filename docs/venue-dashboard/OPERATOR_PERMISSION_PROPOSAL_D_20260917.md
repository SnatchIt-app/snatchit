# Operator permissions for organisation onboarding — proposal for the owner's ruling (D, 2026-09-17)

**Status:** a proposal. Nothing here is decided, applied or deployed. Migration 138 stays outside the marketplace
candidate. The proposal answers owner item 2 (facts O1–O4 in the 138 contract's change log 2), A's F-138-8
(implemented in development at `ops/138-operator-onboarding` @ be80aad) and A's F-138-9. PFA-4 is preserved
unchanged throughout, and the current restrictions are treated as compatibility constraints.

---

## 1. The facts that decide the design (each verified; source in brackets)

| # | Fact |
|---|---|
| F1 | **The frozen organisation verbs are the customer's, not the platform's** (RPC §2.1–2.5). `create_organization` is a self-service *apply*: the caller becomes the first `org_owner` at `applied`. `invite_org_member`, `change_org_role` and `remove_org_member` require the caller to be `org_owner`/`org_admin` **of that organisation**, with the tier guard and I-11 (no self-promotion). `accept_org_invite` confers the role only on the **addressed invitee** (the identity, or an account whose email matches). `org_owner` and `org_finance` are money roles whose authority matures from **acceptance** (AUTHZ-C1B). |
| F2 | **No roster verb has a platform arm.** Only these do: `set_org_status` (platform_admin), `revoke_org_invite` (inviter tier *or* platform_admin), `approve_venue` (platform_admin), `grant_staff_role`/`revoke_staff_role` (platform_admin among others). [077, 078, 080] |
| F3 | **`kernel` is API-exposed, and `authenticated` may execute every organisation verb.** The sandbox records `pgrst.db_schemas = public, graphql_public, kernel` (acceptance manifest), and the production runbook adds `kernel` to the exposed schemas. On a replay of the candidate chain, `authenticated` holds EXECUTE on `create_organization`, `invite_org_member`, `change_org_role`, `remove_org_member`, `accept_org_invite`, `revoke_org_invite` and `set_org_status`. `catalog` and `venue` are **not** exposed. (No production read was made for this.) |
| F4 | **So the console's two-person rule binds only operators who hold no organisation role.** Anyone holding `org_owner` can call `kernel.invite_org_member(…, 'org_owner', …)` directly, as one person. 138's `org_create` makes the creating operator `org_owner` (O4, test I34). That operator could therefore invite anyone as owner **without the console**. The problem is structural, not stylistic. |
| F5 | O1–O3 as tested at be80aad. A platform operator with no org role passes every framework gate and is refused by the verb (I32, I44). support's four framework write permissions therefore do nothing (I16–I21). An elevation completes only when the **approver** holds org_owner/org_admin there (I72–I73). |
| F6 | **No invite is delivered automatically.** There is no edge function, notification template or event for an organisation invite. The invitee's RLS policy shows an invite only when `invitee_identity_id = auth.uid()`, so an **email-addressed** invite is invisible to its invitee until they are given its id. Acceptance by `invite_id` works once they have it. |
| F7 | PFA-4 (signed 2026-08-31): no platform role may be minted by any direct, single-actor, client-authored or bypass path. The grant arm stays fail-closed until the approved dual-control path exists (I61, I66). |
| F8 | F-138-8, fixed in development: the requester can no longer be the beneficiary of `org_member_elevate` or `org_member_invite_admin` (L1–L4). F-138-9, still open: a routine, single-person `org_member_role_change` grants `org_finance` (I26, I38). |

## 2. Principles

1. **Two planes, never merged.** Platform operators act on the platform plane: statuses, approvals, venue
   lifecycle, audited reads. Customer organisation members act on the organisation plane: their own roster,
   staff and venues. **Operating the platform never makes an operator a member of a customer organisation.**
   That rule is what F4 needs, not a matter of style.
2. **The customer is the owner of record.** Ownership reaches an identity the customer controls, only by that
   identity **accepting** an invite. The maturity clock (AUTHZ-C1B) starts at acceptance, as frozen.
3. **Two-person stays at least as strong.** Requester ≠ approver (118 plus `approval_sod_ck`).
   Beneficiary ≠ requester (F-138-8). Beneficiary ≠ approver, enforced in the verb that runs as the approver.
4. **A console-only verb must not be callable by one person outside the console.** Any new platform verb that
   needs two people is **not** granted to `authenticated`; only the framework's definer reaches it (F3).
5. **Nothing frozen is widened except by a signed amendment.** Org-plane verbs, the tier guard, I-11,
   AUTHZ-C1B and PFA-4 stay exactly as they are.

## 3. Proposal

### 3.1 Who does what

| Actor | May do | May not do |
|---|---|---|
| **Customer `org_owner`/`org_admin`** (organisation plane, frozen verbs) | manage their own roster (invite, change role, remove, within tier and I-11); later, their venues and staff | anything on another organisation |
| **`platform_admin`** (console) | create an organisation **with no members** (A1); request or approve the **bootstrap owner invite** (A2, two-person); set organisation status (reason for suspend/close); revoke a pending invite (frozen platform arm); create a venue **in draft** for an organisation (A3); submit a draft venue (`venue_submit`, in development); request or approve venue approval (two-person); grant or revoke venue staff (frozen platform arm; reason required); every read; the audited contact-email and invitee reveals | become a member of a customer organisation; change a customer's roster; mint a platform role (PFA-4) |
| **`platform_support`** (console) | every read; the audited contact-email and invitee reveals (closed reason sets); escalate a write to a platform_admin | any write. Its four current framework write permissions are removed, because the domain already refuses them (F5) |
| **`platform_risk`** | reads, as today | onboarding writes |

**Removed from the console:** `org_create` (the self-service verb that makes the operator owner),
`org_update`, `org_member_invite`, `org_member_invite_admin`, `org_member_role_change`, `org_member_elevate`
and `org_member_remove`. Each one either fails for an operator with no org role (F5) or would require the
operator to hold one (F4).

### 3.2 How the customer becomes the owner

1. **Platform_admin A** creates the organisation with **no members** (A1). It sits at `applied`; the audit
   reason is `platform_bootstrap`.
2. A reviews the application and sets it `approved` (existing `org_status_set`, single-person, audited).
3. A requests `org_owner_bootstrap_invite` with the customer's address, **verified out of band** (A2). The
   address is stored only as a label plus a held reference that no API role can read (owner item 1). The
   request is refused at the console if the address or identity is A's own.
4. **Platform_admin B** (≠ A, and not the invitee) sees the exact address through the audited reveal
   (`get_action_invitee`, reason `approval_review`) and approves. The verb runs as B. It refuses if the
   organisation already has an `org_owner` or a pending owner invite, or if the invitee is B.
5. **Delivery.** Today an operator gives the customer the invite id or link by the verified channel (F6). A
   notification template is a later, separate package.
6. The customer signs in with the addressed account and calls the frozen `accept_org_invite`. They become
   `org_owner`; `granted_at` starts the maturity clock, and money approvals stay closed to them until it
   matures (AUTHZ-C1B).
7. From then on the **customer** runs their roster on the organisation plane. Operators keep only the
   platform actions in 3.1.
8. **Venues.** A creates a draft venue for the organisation (A3), or the customer does once a customer surface
   exists. `venue_submit` moves it to `pending` (in development, tests K1–K17). Approval is two-person.
9. **Recovery**, when the organisation has lost its only owner (account deleted or erased): the same two-person
   bootstrap invite, allowed only while the organisation has **no** `org_owner`. It carries a closed reason
   code and never replaces an existing owner.

### 3.3 The two-person set, explicitly

`venue_approve` (approve or archive, pending venues only) · `platform_role_grant` (**fail-closed**, PFA-4,
unchanged) · `org_owner_bootstrap_invite`. For each: requester ≠ approver, beneficiary ≠ requester,
beneficiary ≠ approver, and the verb is reachable only through the framework.

### 3.4 F-138-9 (org_finance)

Under this proposal **the console changes no organisation role**, so `org_finance` is only ever granted by the
customer on the organisation plane, under AUTHZ-C1B maturity, as frozen. **If the owner instead keeps console
role changes, `org_finance` should join `org_owner` and `org_admin` in the two-person set**, because it is a
money role.

## 4. What it takes

### 4.1 In 138, without an amendment (compatibility-preserving)
- Remove the seven console types in 3.1, and support's write permissions.
- Keep: the reads, `get_org_contact_email`, `get_action_invitee`, the invitee masking, `org_status_set`,
  `org_invite_revoke` (platform_admin), `venue_submit`, `venue_approve`, venue staff (platform_admin),
  `platform_role_grant` (fail-closed).
- 206 sections I/L shrink to the kept types; J, K and M stay; mutants are re-run with written predictions.
- Until A1–A3 are signed and built, the console **cannot onboard a new organisation**. It can approve
  organisations and venues the customer created. That is the honest interim, and it removes F4's bypass.

### 4.2 The amendment (owner signature required; the PFA class, because it adds a platform arm to the frozen RPC §2/§3.1)
- **A1 `kernel.bootstrap_organization(legal_name, display_name, command_key)`.** platform_admin. Inserts the
  organisation at `applied` with **no `org_member` row**. Audit `org.create`, reason `platform_bootstrap`.
- **A2 `kernel.invite_bootstrap_owner(org_id, invitee_ref, command_key)`.** platform_admin. Preconditions: no
  `org_owner` member, no pending `org_owner` invite, and the invitee is not the caller (identity or email).
  Writes a `kernel.org_invite` row at `org_owner`. Audit reason `platform_bootstrap_owner` (a money-role class
  under AUTHZ-C1B).
- **A3.** A platform_admin arm on `catalog.create_venue` that writes `draft` only.
- **Grants.** A2 is executable by **no API role**; only the ops framework's definer reaches it (principle 4).
  A1 and A3 are console-only for the same reason.
- **Unchanged.** `accept_org_invite`, the org-plane roster verbs, the tier guard, I-11, AUTHZ-C1B, PFA-4, 118's
  approval machinery and `approval_sod_ck`.
- **Test obligations.**
  - An operator is never a member after bootstrap.
  - A2 refuses an owned organisation, a second pending owner invite, and self-invites by requester or approver.
  - A direct RPC call to A2 by one platform_admin is refused.
  - Acceptance by the addressed account yields `org_owner` with `granted_at` = acceptance, and the money
    predicate is closed until maturity.
  - The recovery path works only when the organisation has no owner.
  - Each rule has a negative control with a predicted failure set.

## 5. Alternatives considered and rejected

| Alternative | Why not |
|---|---|
| **Keep the status quo:** the operator becomes owner (O4) | Merges the planes, and puts a money role in the operator's hands. Through F4 that operator can grant ownership alone, without the console. |
| **A platform arm inside `invite_org_member`/`change_org_role`/`remove_org_member`** | Gives every platform_admin standing owner authority over every organisation. Because `kernel` is exposed, it is single-person by direct call unless dual control moves into those verbs, which is the PFA-4 problem again, across the whole roster. |
| **Give support an org or venue role so its permissions work** | Excluded by the owner. It is the same plane-merging as the status quo. |
| **Customer self-service only** | Frozen-clean and a viable fallback. But no customer surface for `create_organization` exists yet, invites are not delivered (F6), and venue creation needs `catalog`, which is not exposed. No concierge onboarding. |
| **Support requests writes that a platform_admin approves** | Needs an approval predicate that depends on the requester's role, not only the type. That changes the approval model every console action uses, so it is not for this package. |

## 6. Decisions requested
1. Adopt the principles and the bootstrap flow (A1–A3, a signed amendment), **or** choose customer
   self-service only.
2. Interim 138 scope: remove the seven organisation-plane console types and support's write permissions now
   (recommended).
3. Support: reads plus the two audited reveals only (recommended).
4. F-138-9: moot under 1–2. If console role changes are kept, `org_finance` becomes two-person.
5. Bootstrap invite delivery: an operator sends the invite link by the verified channel for now (recommended),
   with a notification template later as its own package.
6. Held invitee references for approvals that are denied or expire stay in the non-readable table. Accept
   that, or add cleanup; cleanup would redefine 118's `approve_action`, a sixth object in 138.

---
*Evidence for every fact above is on `ops/138-operator-onboarding` (206 at be80aad, 161 assertions; 52 mutants
with predicted failure sets) and in the change logs of `OPERATOR_ONBOARDING_CONTRACT_D_20260917.md`.*
