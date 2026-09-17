# Smallest usable operator-onboarding surface — D's scoping (2026-09-17)

**Authorized by the owner's ruling of 2026-09-17: "local investigation and planning, not production operations."**
Nothing here is built, applied or scheduled. Scoped against the real RPC signatures read from the pinned tree
`/tmp/wt-pin` (`9bef640`), not from the readiness report's summary.

---

## 0. The finding that changes the shape

I expected "four screens on the existing console". That is wrong, in both directions, and both matter.

**Wrong because it is not enough.** Half the onboarding verbs **cannot be reached from a browser at all today**:

| Schema | PostgREST-exposed? | Onboarding verbs living there |
|---|---|---|
| `kernel` | **yes** (production exposes `public, graphql_public, kernel, ops`) | `create_organization`, `update_organization`, `set_org_status`, `invite_org_member`, `change_org_role`, `remove_org_member`, `revoke_org_invite`, `grant_platform_role`, `set_org_connect_ref`, `get_org_connect_state` |
| `catalog` | **no** — the venue kit asserts it stays **406** | `create_venue`, `approve_venue`, `update_venue`, `create_event`, `create_event_session`, `publish_event` |
| `venue` | **no** — same assertion | `grant_staff_role`, `revoke_staff_role` |

And **`ops.*` contains no organisation, venue, staff or event read of any kind** — I grepped the whole `ops`
surface. The console cannot *list* an organisation, so it cannot offer one to act on. The write side is done; the
read side does not exist.

**Wrong because bespoke screens would be the wrong build.** The console already has an audited, role-gated,
approval-capable action framework — `ops.action_dispatch`, `ops.action_precheck`, `ops.action_allowed_roles`,
`ops.action_requires_approval`, `ops.approve_action`, `ops.audit_write`, and a `/actions/[id]` UI. Four screens
calling the verbs directly would **bypass the console's own two-person approval, role gating and audit trail** —
the machinery every other privileged console action already goes through. Onboarding is exactly the class of
action that should inherit it. `action_dispatch` branches on a hardcoded `case a.action_type`, so new action types
are a migration, not configuration.

**So the smallest usable surface is a migration plus a thin UI, in that order** — and the migration is the larger
half. Saying "four screens" would have under-scoped it by the part that actually carries the risk.

---

## 1. What the verbs actually look like

Every write verb is `SECURITY DEFINER`, returns `jsonb`, and **takes a `p_command_key text`** — idempotency is
designed in at the contract level, so the UI must generate, persist and re-send a command key per action rather
than treating retry as free.

```
kernel.create_organization(p_legal_name text, p_display_name text, p_command_key text) -> jsonb
kernel.invite_org_member(p_org_id uuid, p_invitee_ref text, p_role text, p_command_key text) -> jsonb
kernel.change_org_role(p_org_id uuid, p_identity_id uuid, p_new_role text, p_command_key text) -> jsonb
kernel.set_org_status(p_org_id uuid, p_target_status text, p_reason_code text, p_command_key text) -> jsonb
kernel.grant_platform_role(p_identity_id uuid, p_role text, p_reason_code text, p_command_key text) -> jsonb
catalog.create_venue(p_org_id uuid, p_name text, p_neighborhood text, p_address text, p_command_key text) -> jsonb
catalog.approve_venue(p_venue_id uuid, p_decision text, p_reason_code text, p_command_key text) -> jsonb
venue.grant_staff_role(p_venue_id uuid, p_identity_id uuid, p_role text, p_command_key text) -> jsonb
venue.revoke_staff_role(p_venue_id uuid, p_identity_id uuid, p_role text, p_command_key text) -> jsonb
```

Access control is inside the functions (`kernel.has_org_role`, `kernel.is_platform`), not in grants.

---

## 2. The screens

Four, and the fourth already exists.

| # | Screen | Reads | Writes | Notes |
|---|---|---|---|---|
| 1 | **Organisations** — list + detail (members, invites, status, Connect state) | new `ops` reads | `create_organization`, `update_organization`, `set_org_status`, `invite_org_member`, `change_org_role`, `remove_org_member`, `revoke_org_invite` | the spine; everything else hangs off an org |
| 2 | **Venue approval queue** — pending venues, approve/reject with a reason | new `ops` read | `create_venue`, `approve_venue` | the one step with a real decision in it; belongs behind approval |
| 3 | **Staff roles** — per venue, grant/revoke, current holders | new `ops` read | `grant_staff_role`, `revoke_staff_role` | needs the venue read from 2 |
| 4 | **Action execution + approval** | — | — | **already built** (`/actions/[id]`, approvals, audit); reused, not rebuilt |

Everything a screen writes goes through `ops.action_*` so it inherits approval, role gating and the audit trail.

---

## 3. Dependencies, in order

1. **A migration number from A** (my numbers route through A; I never pick one on a branch).
2. **Read paths**: `ops` views or functions for organisations, members, invites, venues, staff roles. None exist.
3. **Reachability for `catalog` and `venue` verbs.** Two options, and **I recommend the wrapper**:
   - **Wrappers** — `kernel.*` (or `ops.*`) functions that call the `catalog`/`venue` verbs. Keeps both schemas
     unexposed, keeps the venue kit's 406 assertions true, and keeps the blast radius to the functions we name.
   - **Exposing `catalog`/`venue` in PostgREST** — cheaper to write, and I would not do it: it makes every object
     in both schemas a client-reachable surface and invalidates a standing acceptance assertion. Not worth it.
4. **The four-file rule** for every new object: grant-decision manifest, Gate-2 census in `ci.yml`,
   `expected_grants.txt`, and a rollback restoring the *applied* body.
5. **New `ops.action_type` branches** in `action_dispatch`, plus the allowed-roles and approval-required registry
   entries — the approval decision per action is an owner/policy call, not mine. My recommendation: venue approval
   and platform-role grants require two-person; the rest do not.
6. **pgTAP coverage** with a negative control per branch, per the house rule that a green test is not evidence
   until removing the guard fails it.

---

## 4. Effort, honestly

I said I would not quote a number without scoping, and the scoping has changed the answer, so here it is with what
drives it rather than as a single figure:

| Piece | Band | What drives it |
|---|---|---|
| Migration — reads, wrappers, action types, grants, rollback | **the larger half** | breadth of the read surface, and the four-file discipline per object; the rollback must restore applied bodies |
| pgTAP with negative controls | moderate | one control per dispatch branch |
| Screens 1–3 on the existing shell | **the smaller half** | auth, MFA, layout, actions UI and audit already exist; this is forms plus tables |
| Screen 4 | **zero** | already built |

**What I will not do is convert that into days without one more thing**: the read surface's shape depends on
decisions I do not own — which fields an operator may see (organisation legal names and member identities are
personal data and fall under the same care as the analytics dimension), and which actions need two-person
approval. Give me those two answers and the estimate becomes a number rather than a band. Both are owner
decisions and both are quick to make.

---

## 5. The decision actually on the critical path

Not "build or not". It is: **is the first venue onboarded by hand, or is the surface built first?**

- **By hand** is workable exactly once, with the owner authorising each action, `kernel.admin_audit` as the only
  trail, and no approval gate. It is not a process and should not be described to a client as one.
- **Build first** costs the migration above and removes the hand-run entirely.

**My recommendation: hand-run the first venue under per-action authorization, and build the surface in parallel.**
The first onboarding teaches what the screens need — which fields are actually consulted, where an operator
hesitates, what a venue asks for — and that information is worth more than the week it costs to start building
blind. It also keeps the critical path off the migration, which has to queue behind the release work anyway.

Suggested owner: **me**. The console is my surface, the four-file discipline and the analytics-contract care for
personal data already apply to it, and the action framework is the part I would otherwise be reviewing.

---

## 6. Migration number and the sequencing rule that travels with it

**138 is allocated provisionally by A** (136 = A's batch-1 security-notice wrappers, 137 = A's `notify_outbid`
Vault-form fix). Not written; nothing starts before the owner's two decisions and the hand-run ruling.

**Checked before the file exists, because this is cheap now and expensive later:**

| Body 138 would redefine | Defined | Last redefined |
|---|---|---|
| `ops.action_dispatch` | 115 | **118** |
| `ops.action_precheck` | 115 | **118** |
| `ops.action_allowed_roles` | 115 | 115 |
| `ops.action_requires_approval` | 115 | 115 |
| `ops.audit_write` | 115 | 115 |

All numbered and all below 138, so a numbered 138 sorts after them under LC_ALL=C — **no timestamp-ordering trap**
of the kind that bit 134. Checked specifically, because that failure mode is invisible until a fresh replay.

**The hazard here is 118, not 115.** 138 must redefine `action_dispatch` and `action_precheck` from **118's
applied body**, and its rollback must restore **118's** body — restoring 115's would silently revert 118's
corrections. This is the four-file rule's "restore the applied body, not an older baseline", with a specific file
name attached so the instruction cannot be followed vaguely.

**B's 126 is clear** — it redefines no `ops.action_*` and not `audit_write`, so there is no collision on the
dispatch surface even though 126 may land either side of 138.

**Open with A:** whether 136's wrappers touch `ops` or the action framework. If they do, the later-numbered file is
written against the earlier's applied body; if 136 is purely `notify`/`public`, there is no interaction.
