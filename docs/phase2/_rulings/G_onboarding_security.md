# RULING G — VENUE CONNECT ONBOARDING SECURITY

**Branch** `feature/venue-native-and-product-v2` · read-only analysis · 2026-09-02
**Scope** attaching and replacing an organization's Stripe Connect account — the control set that must
be decided **before** the org onboarding path is built, because a successful attack on it redirects
real money to an attacker.
**Every claim carries a `file:line`.** Nothing here mutates production, authors a migration, creates a
Stripe object, or commits.

---

## 0. BOTTOM LINE

1. **The database controls are unusually good and mostly already written.** `set_org_connect_ref`
   (`supabase/migrations/077_kernel_identity_orgs_and_roles.sql:948-1013`) is bind-once, JWT-bound and
   audited; `set_org_payout_destination` (`supabase/migrations/085_kernel_money_native.sql:1601-1662`)
   demands `org_owner` + role maturity + step-up; `request_org_payout`
   (`supabase/migrations/087_venue_settlement_and_export.sql:414-576`) adds SoD-1 setter exclusion,
   destination probation, and staleness of any approval that predates a destination change. The
   replacement path is **already stronger than the attach path**, which is the correct asymmetry.
2. **The two live holes are not in the authorization logic — they are in what is *never checked* and
   what is *never announced*.**
   - **G-1.** Nothing anywhere verifies that a supplied `acct_…` belongs to the organization. Both
     binders take a caller-typed string and validate it with a **regex only**
     (`077:971-973`, `085:1633-1635`). A `venue_finance`-adjacent `org_finance` may bind their own
     personal Snatch It seller account at `077:967`.
   - **G-2.** `security_payout_destination_changed` and `security_payout_method_added` exist in the
     deployed notification catalogue (`supabase/migrations/092_notify_reduced.sql:269-270`, templates
     `:336-339`) and have **zero producers anywhere in the repo**. Neither binder calls
     `notify.emit_event`. The destination can change and nobody is told.
3. **Three second-order defects compound them:** the destination cool-down is seeded `null`
   (`supabase/migrations/078_catalog_reference_data_and_flags.sql:1553`) so replacement has no cool-off
   at all; the probation clock starts at **bind**, so a fraudster who binds early ages the probation
   out before the org is ever approved (`087:472-481`); and `set_org_payout_destination` performs **no
   org-status check**, so a *suspended* org's owner can still re-point the destination.
4. **In-database dual control for a destination change is unbuildable today** —
   `kernel.approval_request` closes its `action` and `subject_kind` vocabularies at the schema level
   (`077:269-276`, `077:299-302`) and no arm can represent `org.payout_destination.change` on subject
   kind `organization`. This is the PFA-4/PFA-18A impossibility class
   (`docs/phase2/_decisions/B_signing_dual_control.md:74-99`). **But it is a different, weaker
   impossibility than Decision B's:** the org-scoped second approver *does structurally exist*
   (`kernel.org_member` admits multiple `org_owner` rows, `077:147-152`), unlike the platform admin.
   The blocker is a frozen CHECK, and PFA-4's SCOPE OPENED clause explicitly permits a later package
   that owns the path to widen it (`B_signing_dual_control.md:100-107`). Recommendation: **do not
   build it for launch** (§5.2) — buy the same protection with cheap, buildable controls.

---

## 1. WHAT EXISTS TODAY

### 1.1 The individual-seller template — and why it is the *better* pattern

`supabase/functions/create-connect-account/index.ts` is the only shipped Connect onboarding path.

| Control | Where | Verdict |
|---|---|---|
| Caller verified from a real JWT, not a body field | `:45-64`, `:119` | **Good.** `supabase.auth.getUser(token)` — a forged `user_id` in the body is impossible because there is no such field. |
| Account **minted server-side**, never supplied by the caller | `:198-224` | **Good, and the single most important property.** The client cannot name an account. |
| Account bound to the identity inside Stripe | `:208` — `metadata[user_id]: userId` | **Good.** Gives an out-of-band ownership proof. |
| Row bound by `.eq('id', userId)` from the JWT | `:216-218` | **Good.** No caller-controlled row selector. |
| Rate-limited, fail-**closed** | `:70-93`, `:130-158` | **Good.** 5 mutating calls / 600s; an RPC error returns 503, not a bypass. |
| Redirect URLs are env/constant, never from the request | `:98-99`, `:161-163` | **Good.** No open-redirect and no caller-chosen return target. |
| `profiles.stripe_connect_id` is `UNIQUE` | `supabase/migrations/002_transfers.sql:25` | **Good** within the individual plane. |
| Return is state re-read from Stripe, not trusted from the URL | `:239-293` | **Good.** `status_only` re-fetches `accounts/{id}` and re-derives the flags. |
| Stale-account self-heal archives before re-minting | `:242-261` | **Good**, and it writes `stripe_connect_archive`. |
| `account.updated` matches by `stripe_connect_id`, writes flags only | `supabase/functions/stripe-webhook/index.ts:826-837` | **Good.** The webhook can never write an account **id**, only capability flags onto an already-bound row. |

**Two weaknesses the venue path must not inherit:**

- **T-1.** The archive/re-mint arm at `:242-261` nulls `stripe_connect_id` and mints a fresh account
  **on a `no such account` error string match** (`:244`). The trigger is a regex over a Stripe error
  message. This is safe today only because the replacement id is minted, not supplied. Any venue
  analogue that re-mints on an error *and* accepts a supplied id would be a destination-replacement
  primitive reachable by inducing a Stripe error.
- **T-2.** No notification fires on attach, on re-mint, or on `payouts_enabled` flipping false. The
  `account.updated` handler (`stripe-webhook/index.ts:826-857`) logs and ACKs silently. Its signature
  verification is solid — HMAC-SHA256 with constant-time compare, key rotation and a 300s replay
  tolerance (`:46-56`, `:72-119`, `:147-155`) — but it checks **neither `livemode` nor
  `event.account`**, and a **zero-match** update is only logged as `matched_profiles: 0` (`:856`)
  rather than alerted. For the org path a zero-match `account.updated` is exactly the signature of a
  destination that was rebound out of band, and it must page, not log.

### 1.2 The org plane as designed

| Element | Where |
|---|---|
| `kernel.organization.stripe_connect_account_ref` | `077:114` |
| `UNIQUE … WHERE stripe_connect_account_ref IS NOT NULL` | `077:124-126` |
| `payout_destination_set_by` (the SoD-1 operand) | `077:117-118` |
| `payout_destination_locked_until` (cool-down) | `077:115` |
| **Initial attach** — `kernel.set_org_connect_ref`, `org_owner`/`org_finance`, bind-once | `077:948-1013` |
| **Replacement** — `kernel.set_org_payout_destination`, `org_owner` only + maturity + aal2 | `085:1601-1662` |
| Column-scoped: `authenticated` may SELECT only `(org_id, display_name, status)` | `077:133-138` |
| Patch set closed to `display_name` — no jsonb bypass | `077:845-851` |
| Only `platform_admin` may move an org `applied → approved → active` | `077:897-899` |
| SoD-1: the destination setter may not request a payout | `087:428-431` |
| Destination probation on the first payout after a change | `087:465-495` |
| An approval is **staled** by a destination change | `087:506-514`, `087:544` |
| **No org onboarding edge function exists** | `docs/phase2/_decisions/A_venue_money.md:490` |
| **Neither RPC has a single caller** in `app/`, `src/`, `web/`, `packages/` or `supabase/functions/` — they are reachable-but-unwired | grep: hits only in migrations, rollbacks and `supabase/tests/141,149,151` |

A correction to the record: `A_venue_money.md:490` says orgs need the ref "populated via
`kernel.set_org_payout_destination` (`085:1601`)". The **initial** bind path is
`kernel.set_org_connect_ref` (`077:948`); `085:1601` is the *replacement* verb. The distinction is
load-bearing, because the two write different `admin_audit` actions and only `077` is bind-once.

---

## 2. THREAT TABLE

Ranked by consequence. "Buildable today?" means with no frozen-object mutation and no second approver.

| ID | THREAT | POSSIBLE? | PRECONDITION | IMPACT | RECOMMENDED CONTROL | BUILDABLE TODAY? |
|---|---|---|---|---|---|---|
| **G-1** | **`org_finance` (or `org_owner`) attaches their own personal Stripe account as the venue's payee.** Nothing checks account ownership; `077:971-973` validates `^acct_[A-Za-z0-9]+$` and nothing more. A staff member who has onboarded as an individual Snatch It seller already **holds** a valid `acct_` id (`create-connect-account:212`). | **YES.** The single most likely real attack. | One `org_finance` grant (invitable by any `org_admin`, `077:1040-1042`) and a valid `acct_` string. | **Total.** Every settlement payout for that org lands in a personal account, indefinitely, silently. | **Mint, never accept.** The org edge function must create the account itself with `metadata[org_id]`, exactly as `create-connect-account:202-212` does, and pass only the minted id to `set_org_connect_ref`. Add a DB-side cross-plane refusal: raise if the ref exists in `public.profiles.stripe_connect_id` or `public.stripe_connect_archive`. Restrict initial attach to `org_owner` (drop `org_finance` from `077:967`). | **YES** — all three. |
| **G-2** | **Silent replacement.** `security_payout_destination_changed` is defined (`092:269`) with templates (`092:336-337`) but has **no producer**; neither binder emits. Compare `change_org_role`, which does (`077:1263-1272`). | **YES — it is the current state.** | None. | Removes the only human tripwire on G-3/G-4; a hostile change is invisible until a payout lands elsewhere. | Emit `security_payout_destination_changed` from **both** binders, best-effort in a `begin…exception` block, exactly on the `077:1263-1279` pattern, keyed on the `admin_audit` row id. Recipients: **every** `org_owner` and `org_finance` of the org, plus the actor. Also emit on `payouts_enabled → false`. | **YES.** The type, the templates and the emitter all exist. |
| **G-3** | **Replacement on a live, selling org.** `org_owner` re-points the destination; future settlements pay the attacker. | **YES, but well fenced.** `085:1618-1634` demands `org_owner` + `money_role_grant_matured` (72h, `078:1560`) + `aal2`; `087:428-431` bars the setter from requesting the payout; `087:465-495` probation-holds the first payout after the change; `087:506-514` stales any pre-change approval. | A compromised or malicious matured `org_owner` session **with aal2**, plus a *second* org money role to request the payout. | High, but **delayed and detectable** — probation holds the first payout for `platform_risk` release. | Keep all four. Add G-2's notification, set `payout.destination_cooldown_hours` (G-5), and add an org-status gate (G-6). | **YES** — all config or additive. |
| **G-4** | **Cross-organization attachment / one account on two orgs.** | **Attach: NO — structurally prevented.** `077:124-126` is a partial unique index; `077:1000-1003` catches `unique_violation` and returns `conflict_locked`. | — | — | **Two gaps remain.** (a) `set_org_payout_destination` has **no** `unique_violation` handler (`085:1647-1653`) — a collision raises a raw 23505 instead of a mapped `conflict_locked`; the *prevention* holds, the error contract does not. (b) The unique index is **per-plane**: it cannot see `public.profiles.stripe_connect_id`, so a personal seller account can sit in both planes undetected — this is G-1's mechanism. Add the cross-plane check and a CI invariant (§6). | **YES.** |
| **G-5** | **Repeated replacement / no cool-off.** `payout.destination_cooldown_hours` seeds to **`null`** (`078:1553`); `085:1650-1651` then writes `payout_destination_locked_until = NULL`. The cool-down **never engages**. | **YES — it is the current state.** Note this is a **fail-OPEN** key, unlike `money_role_maturity_hours` which fails closed (`078:454-486`) and the probation/threshold keys which are X-12 restrictive (`087:476`, `087:524`). | Any successful G-3. | An attacker can re-point repeatedly to defeat manual reconciliation. | **Owner config decision, no code:** set `payout.destination_cooldown_hours` to a real number (recommend **72**, matching the money-role maturity floor at `078:1560`). Separately, treat the fail-open default as a defect: `085:1650` should fall back to a restrictive constant when the key is absent, mirroring X-12. | **YES** — the number is a config write; the fail-closed fallback is a body-only change. |
| **G-6** | **Fraudulent-venue onboarding / bind-before-approval.** Any authenticated user creates an org and becomes its sole `org_owner` with a self-declared `legal_name` (`077:807-812`), status `applied`. `set_org_connect_ref` accepts status `applied` (`077:980-982`), so a payee binds **before any platform review**. Worse: the probation operand is `max(occurred_at)` over `org.payout_destination.change` **and `org.connect_ref.bind`** (`087:472-476`), so binding early **ages the probation window out** — approve the org after `payout.destination_probation_days` and the first payout escapes probation entirely. | **YES.** | Any account. Approval to `active` still requires `platform_admin` (`077:897-899`), so this is a *timing* attack, not an authorization bypass. | Launders charges through a venue whose first payout skipped the probation control. | (a) Narrow `077:980` to `('approved','active')` — a payee is bound **after** review, not before. (b) Change the probation operand to `greatest(last_destination_change, org_activated_at)` so the clock starts at activation, not at bind. (c) Keep `platform_admin` approval as the KYB gate and record the reviewer in `admin_audit` (it already is, `077:936-943`). | **YES**, all three are body-only changes to unfrozen functions. |
| **G-7** | **Departing employee.** A removed `org_finance`/`org_owner` retains no authority: `has_org_role` is a **live table read**, never a JWT claim (`077:453-466`), so revocation is instant on the next call. The last-owner floor (`077:1325-1331`) prevents locking an org out. | **NO** for future writes. | — | — | **None needed.** But note `payout_destination_set_by` is retained at tombstone by design (`077:117-118`), so SoD-1 keeps binding a departed setter — correct, and it means removing the setter does **not** unlock the payout path. | n/a |
| **G-8** | **Replay of the onboarding callback / stale or leaked link.** | See §3. | | | | |
| **G-9** | **Role lost mid-onboarding, callback still lands.** | **NO.** Authority is checked **at the RPC**, not at the callback. `set_org_connect_ref` reads `auth.uid()` (`077:962-966`) and then `has_org_role` live (`077:967`). A demoted caller's return lands, the RPC raises 42501, and nothing binds. | — | — | **Preserve this by construction:** the return handler must carry **no** authority of its own and must re-call the bind RPC with the caller's JWT. Never let the return path run as `service_role`. `077:962-966` already raises when `auth.uid()` is NULL (T-RPC-CONNECT-04, `supabase/tests/141_phase2_identity_orgs_deletion.sql:646-649`). | Already correct. |
| **G-10** | **Venue operatorship transfer moves the money.** | **NO — the money does not follow the venue.** `kernel.payout.payee_org_id` is written from `venue.settlement.org_id`, the org **stamped at sale time** (`087:341-343`), never re-resolved from `catalog.venue`. `venue."order".org_id` (`082:78`) and `kernel.tickets.org_id` (`079:35`) are likewise stamped at create/mint. So the *departing* org keeps its own settlements and its own destination. | — | — | See §4. The Decision C freeze covers the *authorization* of a transfer but **not** the two residues below. | Partly. |
| **G-11** | **Direct SQL replacement.** `authenticated` cannot touch the column: `revoke all` + a SELECT grant limited to `(org_id, display_name, status)` (`077:133-138`). `service_role` holds **USAGE only** on `kernel` (`085:2092-2095`, PFA-21) — no table DML grant — so the edge key cannot `UPDATE kernel.organization` directly. **`postgres`/superuser can**, and nothing would notice. | **YES for superuser only.** | Superuser DB credentials (a dashboard SQL editor session, or a leaked DB password). | Total, and **unattributable** — a direct UPDATE writes no `admin_audit` row. | **A trigger, not a policy.** Add an `AFTER UPDATE OF stripe_connect_account_ref` trigger on `kernel.organization` that writes a `kernel.admin_audit` row unconditionally, with `actor_identity = coalesce(auth.uid(), <platform sentinel>)` and `reason_code = 'out_of_band'` when `auth.uid()` is NULL — the sentinel pattern already in use at `087:380`. A superuser can drop the trigger, but dropping it is itself a schema change that Gate-2 replay parity (`.github/workflows/ci.yml:536-538`) would surface. Pair with the §6 CI invariant. | **YES.** |
| **G-12** | **Service-role key leak — money redirection blast radius.** | **Bounded, and better than expected.** The key **cannot** rebind an org destination: `set_org_connect_ref` raises when `auth.uid()` is NULL (`077:962-966`, asserted at `tests/141:646-649`); `set_org_payout_destination` does the same (`085:1614-1617`); no `kernel` table DML grant exists (`085:2092-2095`). | **Partly.** | Leaked `SUPABASE_SERVICE_ROLE_KEY`. | The **individual** plane is fully exposed — `create-connect-account:216-218` and `:258` show the service client updating `profiles.stripe_connect_id` with no RLS in the way, so any seller's payout destination can be rewritten. The org plane is not. `notify.emit_event` is service_role-executable (`076:343-346`), so a leaked key can also *forge or suppress* security notices. | Move the individual-plane destination write behind a JWT-bound RPC with the same `auth.uid()` guard as `077:962-966` — this is the one place the org plane is *stronger* than the shipped individual plane and the gap should close in the other direction. Alert on `admin_audit` rows whose `actor_identity` is a sentinel. | **YES**, but it is a change to the shipped individual rail — schedule it, do not couple it to launch. |

---

## 3. G-8 — THE ONBOARDING CALLBACK, REPLAY AND LEAKED LINKS

**What the link is.** Stripe `account_links` are created at `create-connect-account/index.ts:333-338`
with `type: 'account_onboarding'`. Stripe account links are **single-use and short-lived** (minutes),
and the hosted flow authenticates the person itself — possession of the link grants the ability to
*complete Stripe's own onboarding form for that account*, which is a Stripe-side trust boundary, not a
Snatch It one. Possession grants **nothing in Snatch It**: the link's `return_url` and `refresh_url`
are fixed constants (`:98-99`), validated `https://`-only (`:161-163`), and are **not** caller-supplied
— so there is no open redirect and no attacker-chosen landing page.

**What the shipped handlers actually do — and they are exemplary.** `/payout-return` and
`/payout-refresh` exist only as Expo Router screens, and **each reads nothing whatsoever from the URL**:

- `app/payout-return.tsx:33-39` — no `useLocalSearchParams`, no `window.location`, no query or
  fragment parsing. It waits 1500ms and `router.replace('/(tabs)/profile')`.
- `app/payout-refresh.tsx:34-40` — the same, to `/settings/payout-setup`. Both registered at
  `app/_layout.tsx:101-102`.
- The native flow calls `WebBrowser.openAuthSessionAsync(url, 'snatchit://payout-return')`
  (`app/settings/payout-setup.tsx:34`, `:213-216`) and **deliberately ignores `result.type`**
  (`:217-219` — "do NOT branch behavior on it"), then re-derives state at `:228`.
- The deep-link handler `src/providers/NativeAppShell.native.tsx:166-218` parses query and fragment
  only for Supabase auth and explicitly refuses `setSession`-from-URL (`:207-209`); it has no payout
  branch at all.
- State is re-derived server-side on mount, foreground and focus —
  `app/settings/payout-setup.tsx:110-131` and `app/(tabs)/profile.tsx:193-211`, both via
  `status_only: true`, and neither regresses status on error (`payout-setup.tsx:90-96`).

`create-connect-account`'s `status_only` arm is the correct template: the only body field it reads is
`status_only` (`:123-124`), it takes **no** account id from the caller, reads
`profiles.stripe_connect_id` server-side (`:168-181`), and re-fetches the live account from Stripe
(`:241`) before writing any flag (`:285-293`). A replayed return re-derives the same state and is a
harmless no-op.

**One operational caveat for the venue path.** `REFRESH_URL`/`RETURN_URL` point at `snatchitapp.com`
(`create-connect-account/index.ts:98-99`), but nothing in this repo serves those paths on that host —
they exist only as in-app Expo screens, and `docs/security/STRIPE_APP_STORE_AUDIT.md:920` already
raises the question. Confirm the return target is served by a surface under our control **before** the
venue path uses it; otherwise a future DNS or hosting change turns it into an attacker-controlled
landing page for a mid-onboarding org owner.

**The rule for the venue path, stated as a requirement:**

> The return and refresh handlers MUST treat every URL-borne value as decoration. They MUST NOT accept
> an `account`, `org_id`, `user_id`, or token from the query string or fragment as authority or as a
> row selector. The org id MUST come from the caller's session; the account id MUST come from the
> minted record or from a live Stripe read; the authority MUST be re-evaluated at the RPC
> (`077:967`), not at the callback.

A replayed return is then idempotent by construction: `set_org_connect_ref` returns `noop_replay` for
the same id (`077:985-990`, asserted at `tests/141:638-641`) and refuses a *different* id with
`destination_already_set` (`077:991-993`, asserted at `tests/141:641-645`).

---

## 4. G-10 — OPERATORSHIP TRANSFER AND THE CONNECTED ACCOUNT

**Whose Stripe account should follow a venue? Neither — and the schema already agrees.**
`catalog.venue.org_id` (`078:98-99`) is the *current operator*. Money is bound to the **sale-time**
org everywhere: `venue.settlement.org_id` (`087:46`), `kernel.payout.payee_org_id` from
`v_s.org_id` (`087:341-343`), `venue."order".org_id` (`082:78`), `kernel.tickets.org_id` (`079:35`).
So a transfer moves *future* selling to the arriving org — which uses its **own**
`stripe_connect_account_ref` — and leaves historic settlements payable to the departing org. That is
the correct semantics and it needs no new control.

**Does the Decision C freeze fully cover it? No — three residues.**

1. **The freeze is ruled but not built.** `docs/phase2/_decisions/C_operatorship_transfer.md:413-416`
   adopts the freeze and `:428-440` prescribes `093_freeze_operatorship_transfer.sql`. **No 093
   exists** — migrations stop at `092_notify_reduced.sql`. Today the `org_id` arm of
   `catalog.update_venue` (`078:701`) is live, gated only by `platform_admin` (`078:689-692`). With one
   platform admin this is single-control, and it is not on the money-control path at all.
2. **A stale venue-role holder keeps reading settlements.** The RLS policies
   `venue_settlement_sel_venue` (`087:83-84`) and `venue_settlement_line_sel_venue` (`087:123-125`)
   carry no operator conjunct — noted at `C_operatorship_transfer.md:242`. Read-only, so it does not
   redirect money, but it discloses the departing org's settlement totals.
3. **The departing org's legacy settlements become un-closeable by its `venue_finance`.**
   `close_settlement`'s E-76 conjunct compares `catalog.venue.org_id` to `settlement.org_id`
   (`087:299-302`); after a transfer the venue arm fails. The `org_finance`/platform arms still work,
   so money is not stranded — but the operational path changes silently.

**Recommendation:** ship the 093 freeze as ruled, and add to it a **destination assertion** — a
transfer must refuse while the departing org has any `kernel.payout` in `pending`/`submitted`, so an
operatorship change can never race a payout against a destination the approver did not see.

---

## 5. ATTACH VERSUS REPLACE

These are different acts and must not share a control set. The shipped design already separates them
(`077:991-993` routes every re-point to `085:1601`); this section fixes what each should require.

### 5.1 Comparison

| | **ATTACH** (first bind, ref IS NULL) | **REPLACE** (re-point, ref IS NOT NULL) |
|---|---|---|
| Function | `kernel.set_org_connect_ref` (`077:948`) | `kernel.set_org_payout_destination` (`085:1601`) |
| Role today | `org_owner` **or `org_finance`** (`077:967`) | `org_owner` **only** — SoD-1 (`085:1618-1620`) |
| Role recommended | **`org_owner` only.** Attaching the payee is the same act as replacing it when the prior value was nothing. Drop `org_finance`. | Unchanged. |
| Step-up (aal2) | **None today.** | Required, fail-closed on an absent claim (`085:1626-1632`) |
| Step-up recommended | **Require it.** Same one-line pattern as `085:1626-1632`. | Unchanged. |
| Role maturity (72h) | **None today.** | Required (`085:1621-1623`) |
| Maturity recommended | **Require it** — it is the control that defeats "invite an accomplice, bind, remove them". | Unchanged. |
| Org status gate | `applied`/`approved`/`active` (`077:980-982`) | **None** — a *suspended* org can re-point |
| Status recommended | **`approved`/`active` only** (G-6) | **Add the same gate.** Suspension must freeze the payee. |
| Cool-down | n/a (bind-once) | Written but **inert** — key seeds `null` (`078:1553`, `085:1650`) |
| Cool-down recommended | n/a | **Set 72h** and make the absent key fail closed. |
| Probation on next payout | Yes — `org.connect_ref.bind` is an operand (`087:472-476`) | Yes — `org.payout_destination.change` (`087:472-476`) |
| SoD-1 payout exclusion | Yes, stamped at bind (`077:997-999`, `tests/141:635-637`) | Yes (`085:1649`, `087:428-431`) |
| Approval staleness | n/a | Yes (`087:506-514`, `087:544`) |
| Audit | `org.connect_ref.bind` (`077:1005-1009`) | `org.payout_destination.change` (`085:1655-1660`) |
| Notification | **NONE** | **NONE** — G-2 |
| Notification recommended | `security_payout_method_added` | `security_payout_destination_changed` |
| Second approver | Unbuildable in-DB (§5.2) | Unbuildable in-DB (§5.2) |

### 5.2 The control I am downgrading, and why

**Ideal:** replacement requires a second `org_owner` to approve before the new destination takes
effect. **Unbuildable today.** `kernel.approval_request` closes `action` to
`('refund.issue','payout.request','config.set_money_key')` and `subject_kind` to
`('order','settlement','config_key')` at the schema level (`077:269-276`), paired exhaustively by
CHECK (4) (`077:299-302`), with CHECK (7) forcing `amount_minor` non-null for anything that is not
`config.set_money_key` (`077:308`) — and a destination change **has no amount**. There is no arm a
destination approval can occupy without violating a frozen CHECK (23514). Encoding it as a
`config_key` would be a semantic lie of exactly the kind PFA-18A forbids
(`B_signing_dual_control.md:88-95`). 077 is immutable and hash-locked.

**How this differs from Decision B, and why it matters.** Decision B's impossibility is *two-layered*:
the vocabulary is closed **and** the second `platform_admin` does not exist (`B:100-119`). Here only
the first layer applies — `kernel.org_member` admits many `org_owner` rows (`077:147-152`), and
`invite_org_member` lets an `org_owner` invite at `org_owner` (`077:1040-1042`). So the second human
is real; only the frozen CHECK is in the way, and PFA-4's SCOPE OPENED clause permits a later package
that owns the path to widen the closed sets (`B:100-107`). **This is buildable — just not cheaply, and
not without a ratification.**

**The downgrade.** For launch, do **not** build in-DB dual control on the destination. Buy the same
property with three controls that are already written or trivial:

1. **The SoD-1 exclusion is already a de-facto second person** (`087:428-431`): whoever sets the
   destination cannot request the payout to it. An attacker who compromises one `org_owner` gets the
   destination but **not** the money — a second, distinct org money role must request the payout, with
   its own aal2 (`087:439-444`). This is dual control *at the moment money moves*, which is the moment
   that matters, and it already ships.
2. **Destination probation** (`087:465-495`) holds the first payout after any change until a
   `platform_risk`/`platform_admin` release. That release **is** the human second look — outside the
   database, where a second approver actually exists.
3. **Notification to the whole org money set** (G-2) gives the org's other owners the signal that
   in-DB dual control would have given them, one step later.

Record the ideal control as an owner-owed follow-up: *"extend `kernel.approval_request` narrowly to
carry `org.payout_destination.change` on `subject_kind = 'organization'`, per the PFA-4 SCOPE OPENED
clause"* — a later ratification, not launch scope.

---

## 6. THE CONTROL SET, SPECIFIED

### 6.1 Audit — table, action, fields

`kernel.admin_audit` (`077:236-247`) **can carry all of this unchanged**: `actor_identity` (FK to
`auth.users`, NOT NULL), `action` (deliberately open vocabulary, `077:239`), `subject_kind`,
`subject_id`, `reason_code`, `before` jsonb, `after` jsonb, `occurred_at`. It is append-only twice
over — `revoke update, delete … from service_role` (`077:259`) plus a `raise_append_only` trigger
(`077:261-264`) — and indexed on `(subject_kind, subject_id)`, `actor_identity`, `occurred_at`
(`077:249-254`).

| Action | Subject | `before` / `after` | Emitted by | Status |
|---|---|---|---|---|
| `org.connect_ref.bind` | `organization` / org_id | `null` / `{connect_account_id}` | `077:1005-1009` | **Exists** |
| `org.payout_destination.change` | `organization` / org_id | `{connect_ref}` / `{connect_ref}` | `085:1655-1660` | **Exists** |
| `org.connect_ref.bind_denied` | `organization` / org_id | — / `{error_code}` | `kernel.record_money_denial` already accepts `payout.destination` + `organization` (`085:1582-1584`) | **Reusable as-is** |
| `org.connect_ref.out_of_band` | `organization` / org_id | old / new ref | **NEW** trigger (G-11) | To build |
| `org.connect_ref.capability_lost` | `organization` / org_id | — / `{payouts_enabled:false, disabled_reason}` | **NEW**, from the org `account.updated` branch | To build |

**Two fields to add to the `after` payload of both existing binders**, at zero schema cost: the
**last 4** of the ref (never the whole id in a notification — `PHASE_2_CRM_EXPORT_SPEC.md:285` bars
Connect ids from leaving the trust boundary) and the **request origin** (`edge` vs `out_of_band`).

**Do not** log the full `acct_` id into any notification payload; the templates already ask only for
`{{destination_last4}}` (`092:336`).

### 6.2 Notifications — types, recipients, triggers

The catalogue is deployed and the correct precedent is `change_org_role` (`077:1263-1279`):
best-effort, wrapped in `begin … exception when others then raise warning`, keyed on the audit row id
so the event key is per-occurrence (the PFA-2 collision rule, `076:330-338`).

| Event | Type key (**already seeded**) | Fires on | Recipients |
|---|---|---|---|
| Attach | `security_payout_method_added` (`092:270`, templates `:338-339`) | `set_org_connect_ref` success | Every `org_owner` + `org_finance` of the org |
| Replace | `security_payout_destination_changed` (`092:269`, templates `:336-337`) | `set_org_payout_destination` success | Every `org_owner` + `org_finance`, **including** any who did not act |
| Payouts disabled | `staff_payout_failed` (`092:250`) or a new `security_*` sibling | org `account.updated` with `payouts_enabled: false`, or `disabled_reason` set | `org_owner` + `org_finance` |
| Probation hold | `payout_on_hold` (`092:249`) | Already emitted for payouts generally; ensure the `destination_probation` reason reaches the org | `org_owner` + `org_finance` |

All four are `delivery_class = 'mandatory'` with `{push,email}` (`092:268-272`) — a hostile actor
cannot mute them via preferences. **This is the single highest value-per-line control in this ruling.**

### 6.3 Immutable versus changeable

| Field | Verdict | Basis |
|---|---|---|
| `stripe_connect_account_ref` — **first** bind | **Immutable via the attach path.** Bind-once holds. | `077:991-993`; `tests/141:641-645` |
| `stripe_connect_account_ref` — thereafter | **Must remain changeable**, via `085:1601` only. A venue's bank relationship legitimately changes; freezing it would strand payouts and force a support back door, which is worse. | `085:1601-1662` |
| `payout_destination_set_by` | **Immutable at tombstone** — retained by design so SoD-1 keeps binding a departed setter. | `077:117-118` |
| `kernel.admin_audit` rows | **Immutable, already enforced twice.** | `077:259`, `077:261-264` |
| `kernel.payout.stripe_transfer_ref` | **Write-once**, already. | `085:133` |
| `venue.settlement.org_id` | **Immutable** — the payee snapshot. Never re-resolve from `catalog.venue`. | `087:46`, `087:341-343` |
| `catalog.venue.org_id` | Changeable in principle, **frozen for launch** — and 093 does not exist yet. | `078:701`; `C_operatorship_transfer.md:413-416` |
| Org `status` | Changeable, `platform_admin` only. | `077:897-899` |

### 6.4 CI and invariant checks

CI already runs a ratcheted pgTAP gate, a Gate-2 fresh-replay parity check and a privilege-parity
check (`.github/workflows/ci.yml:536-538`, `:587-596`, `:666-676`). Add to
`supabase/tests/` — these are cheap and each catches a distinct bad state:

1. **Cross-plane uniqueness.** No `kernel.organization.stripe_connect_account_ref` appears in
   `public.profiles.stripe_connect_id` or `public.stripe_connect_archive.stripe_connect_id`. *This is
   the check that would catch G-1 in production.* Nothing today can.
2. **One org per account.** Assert `organization_connect_ref_key` (`077:124-126`) **exists** — the
   invariant is structural, so test the index, not the data.
3. **Audit coverage.** Every distinct `stripe_connect_account_ref` value ever held has a matching
   `admin_audit` row in (`org.connect_ref.bind`, `org.payout_destination.change`,
   `org.connect_ref.out_of_band`). A ref with no audit row is a direct-SQL write (G-11).
4. **Notification wiring.** For each `admin_audit` row of those two actions, a `notify` envelope of
   the corresponding type exists. This is the regression test for G-2 and it fails **today**.
5. **Config not fail-open.** `payout.destination_cooldown_hours` and
   `payout.destination_probation_days` (`078:1553-1554`) are non-null in production config.
6. **Grant parity.** `set_org_connect_ref` and `set_org_payout_destination` are executable by
   `authenticated` and **not** `anon`; both raise 42501 on a claims-less connection —
   `tests/141:646-649` already asserts this for the first; add the twin for the second.

---

## 7. RANKED RECOMMENDATION

| Rank | Action | Cost | Blocks launch? |
|---|---|---|---|
| 1 | **Mint the org account in the edge function; never accept a caller-supplied `acct_`.** Copy `create-connect-account:198-224` with `metadata[org_id]`. | One edge function — which must be written anyway (`A_venue_money.md:490`). | **YES.** G-1 is unmitigated without it. |
| 2 | **Wire the two security notifications** (G-2). | ~15 lines in each binder; the pattern, the types and the templates all exist. | **YES.** |
| 3 | **Cross-plane ref check** in both binders + CI invariant §6.4.1. | One `exists` clause each. | **YES.** |
| 4 | **Attach := `org_owner` only, `approved`/`active` only, + aal2 + maturity** (§5.1, G-6). | Four lines in `077:967-982`, all copied from `085:1618-1634`. | **YES.** |
| 5 | **Set `payout.destination_cooldown_hours` = 72** and make the absent key fail closed (G-5). | A config write plus one `coalesce`. | **YES** — it is the difference between a written control and a live one. |
| 6 | **Org-status gate on replacement**; a suspended org may not re-point (§5.1). | One clause in `085:1641-1642`. | Strongly recommended. |
| 7 | **Out-of-band write trigger** (G-11) + CI invariant §6.4.3. | One trigger. | Recommended. |
| 8 | **Probation clock from activation, not bind** (G-6b). | One `greatest()` in `087:472-476`. | Recommended. |
| 9 | **Ship the 093 operatorship freeze** with the pending-payout assertion (§4). | Already ruled and specified. | Per Decision C: P1. |
| 10 | Individual-plane destination write behind a JWT-bound RPC (G-12). | Touches the shipped rail. | **No** — schedule separately. |
| — | In-DB dual control on replacement. | **DOWNGRADED — unbuildable without widening a frozen CHECK.** Substitutes: SoD-1 (`087:428-431`), probation (`087:465-495`), notification (G-2). Record as an owner-owed follow-up under the PFA-4 SCOPE OPENED clause. | No |
