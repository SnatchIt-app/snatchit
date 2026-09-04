# E1 — `connect-onboarding`: organization Stripe Connect onboarding

**Status:** implemented against migration 093 as authored, **NOT DEPLOYED**. One new file:
`supabase/functions/connect-onboarding/index.ts`. No migration authored, no Stripe object created,
no remote touched, nothing committed.
**Branch:** `feature/venue-native-and-product-v2`
**Governing rulings:** `docs/phase2/_rulings/F_org_onboarding.md` (Part 3 — the design),
`docs/phase2/_rulings/G_onboarding_security.md` (§2 threats, §3 callbacks, §5.1 attach-vs-replace),
`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.3 (`:439-462`, matrix `:1778`).
**Owner rulings honoured:** A6 (org is the payee), A7 (venue money never on a personal account),
A9 (server-side authority).

**Headline.** Written against `docs/phase2/_impl/093_parts/30_connect_org.sql` at its authored
signatures; type-checks clean. **RT-A-4 fixed** — the resolve operand is `kernel.get_org_connect_ref`
(093:1319, service_role only), never the last4-only human verb. **RT-A-3's two-key sequence is wired**
— `kernel.stage_org_connect_ref` (093:329) runs between the mint and the bind. **RECONNECT is
implemented**, so `409 reconnect_unavailable` is gone. No seams left open.

---

## 1. THE ENDPOINT

`POST /functions/v1/connect-onboarding` · `verify_jwt: true` · Auth model **Class A** (edge spec §0,
EA-1) with one Class B leg.

### Request — a three-key allow-list

```jsonc
{
  "org_id":      "uuid",     // required
  "status_only": false,      // optional, default false
  "command_key": "…"         // accepted for spec §3.3 compatibility, then IGNORED
}
```

Any other key is a `400 unexpected_field`. **There is no field, no fallback and no error path by
which a caller-supplied string reaches `kernel.set_org_connect_ref`.** An allow-list is used rather
than a deny-list because it is provable by reading twenty lines
(`index.ts` `BODY_KEYS` / `parseBody`), where "reject things that look like an account id" is not.

`command_key` is ignored on purpose. The bind key is derived as `connect_org_bind_${org_id}`:
deterministic, so a retry is byte-identical, and immune to a client that would otherwise be able to
defeat its own replay protection.

**`return_url` / `refresh_url` are NOT accepted**, though edge spec §3.3 lists them. Ruling G §3
overrules it — a caller-chosen landing page is an open redirect that catches a mid-onboarding org
owner. They are env constants (`VENUE_CONNECT_RETURN_URL`, `VENUE_CONNECT_REFRESH_URL`), validated
`https:` **and** host-pinned to `snatchitapp.com`, matching the shipped seller path
(`create-connect-account/index.ts:98-99`, `:161-163`) and closing Ruling G §3's "confirm the return
target is served by a surface under our control" caveat against a bad env var.

### Response — 200

```jsonc
{
  "status": "not_connected|onboarding_required|pending_verification|restricted|ready",
  "org_id": "uuid",
  "connect_account_last4": "1a2b",     // MASKED — the full acct_ id never leaves
  "transfers_active": true,
  "payouts_enabled": true,
  "details_submitted": true,
  "requirements_due": false,
  "disabled_reason": null,
  "requirements_deadline": "2026-11-01T00:00:00.000Z",
  "checked_at": "2026-09-02T20:00:00.000Z",
  "url": "https://connect.stripe.com/…"  // mutating calls only; absent on status_only
}
```

`not_connected` returns only `{status, org_id, checked_at}` — there is nothing to mask and no Stripe
call was made.

**The full `acct_` id is never returned** (Ruling G §6.1; `PHASE_2_CRM_EXPORT_SPEC.md:285` bars
Connect ids from leaving the trust boundary; dashboard spec `:1194` shows it masked). This is a
deliberate narrowing of edge spec §3.3's `{ connect_account_id, … }`. The client has no use for the
whole id, because it can never send one back.

### Response — errors, `{ error, code }`

| HTTP | `code` | When |
|---|---|---|
| 400 | `invalid_body` · `unexpected_field` · `invalid_org_id` · `invalid_status_only` | body allow-list / shape |
| 401 | `unauthenticated` | no `Authorization: Bearer`, or a dead token |
| 403 | `forbidden` | `has_org_role([org_owner, org_finance])` false — the endpoint gate |
| 403 | `bind_requires_owner` | caller is `org_finance`: may initiate and view, may not bind (093:658) |
| 403 | `step_up_required` · `step_up_unavailable` | no aal2 session / no `aal` claim at all (093:665-672, AUTHZ-M4) |
| 404 | `org_not_found` | the RPC reports no such org |
| 409 | `destination_already_set` · `conflict_locked` · `org_not_bindable` · `cross_plane_refusal` | bind-once; cross-org collision; org not `approved`/`active` (093:712); the individual-plane refusal (093:717) |
| 409 | `destination_unusable` | a **bound** account Stripe will not return — fail closed, never re-mint |
| 409 | `no_pending_connect_ref` · `connect_ref_not_platform_minted` | RT-A-3 provenance: nothing staged, or a different value staged (093:906-914) |
| 502/503 | `stage_failed` · `stage_unavailable` | `stage_org_connect_ref` did not land — **fatal, never swallowed** |
| 429 | `rate_limited` | 5 mutating calls / 600 s, `Retry-After: 600` |
| 500 | `misconfigured` · `bind_failed` · `malformed_account_ref` · `internal_error` | ours |
| 502 | `link_unavailable` · `state_not_persisted` | Stripe returned no usable URL; or the capability mirror did not persist (§5) |
| 503 | `authority_unavailable` · `connect_state_unavailable` · `bind_unavailable` · `rate_limit_unavailable` · `stripe_unavailable` · `state_writer_unavailable` | **every fail-closed branch** |

`code` exists so the dashboard can render the distinct operator sentences Ruling F §3.6 prescribes
without parsing prose. No SQL text, no capability names and no account id cross the boundary.

### Order of operations

1. `Authorization: Bearer` present → else 401.
2. `service.auth.getUser(token)` → else 401.
3. Body allow-list + shape → else 400.
4. **`kernel.has_org_role(org_id, [org_owner, org_finance])`, caller JWT** — the *endpoint* gate,
   before the limiter and before anything is created. **This is also the authority gate for step 6**,
   which is service_role and carries none of its own.
5. Rate limit, mutating calls only, fail-closed.
6. **Resolve — two reads, never interchangeable:**
   `kernel.get_org_connect_state` (093:985, `authenticated`) for `org_status`, last4 and the mirror,
   and **`kernel.get_org_connect_ref` (093:1081, service_role) for the full `acct_` id — the resolve
   operand.** They read the same column through different doors; if they disagree the request fails
   closed at 503 and alarms.
7. **Bound** → straight to step 10 with the real id. **`status_only` reports the live bound state;
   mutating calls mint a fresh Account Link (RECONNECT).** No mint, no owner/aal2 gate — F §3.4 is
   explicit that resuming a flow changes no destination and must not require step-up.
8. **Unbound + `status_only`** → `not_connected`.
9. **Unbound + mutating** → pre-mint refusals (`org_status ∈ (approved, active)`;
   `has_org_role([org_owner])`; `aal == 'aal2'`; safe redirect config) → mint (idempotency key
   `connect_org_${org_id}`) → **`kernel.stage_org_connect_ref`, service_role** → 
   **`kernel.set_org_connect_ref`, caller JWT**. The order is load-bearing (§6.3).
10. Capture `observed_at`, then `GET /v1/accounts/{id}`. `status_only` returns here — **no write**.
11. **`kernel.sync_org_connect_state`** (5 args, service_role) — **failure fails the request** (§5).
12. `account_onboarding` Account Link with `collection_options[fields]=eventually_due`, or an Express
    Dashboard login link if onboarding is already complete.

## 2. THE ACCOUNT SHAPE (Ruling F §3.2 — several of these are immutable)

```
type                                  = express        # dashboard type cannot change without re-onboarding
country                               = US             # requesting a capability at creation LOCKS this
business_type                         = company        # the org is the legal entity — ruling A7's line
capabilities[transfers][requested]    = true           # AND NOTHING ELSE
business_profile[product_description] = "Live event ticketing sold through Snatch It"
metadata[org_id]                      = <org uuid>
metadata[snatchit_plane]              = "organization"
```

**`card_payments` is deliberately not requested.** Under Ruling A the platform is merchant of record
and pays the org by `POST /v1/transfers`; requesting `card_payments` would make the venue merchant of
record, drag in the whole merchant KYC + website-verification set, and **couple the two
capabilities — if either goes `inactive`, Stripe disables both**.

**No `email` is sent.** The seller path attaches the caller's auth email
(`create-connect-account/index.ts:210`). On this plane that would stamp an employee's personal
address onto the venue's money identity, and it would follow them out of the door.

**Nothing is prefilled at all.** Ruling F §3.2 suggests `company[name] <- legal_name` and
`business_profile[name] <- display_name` to reduce prompts, but 093's `get_org_connect_state` returns
neither — `legal_name` is not client-readable (`077:120-123`) and the verb is minimal by design.
Prefill is a prompt-reduction nicety; widening a money-path read verb to serve one is a poor trade,
so Stripe collects both during hosted onboarding. `company.address`, any Person, any individual field
and `external_accounts` stay absent for the original reason — prefilling them disables Stripe's
networked onboarding, which is how a venue group with several orgs (one LLC each) reuses one verified
legal entity.

Every argument to the create call is server-derived: the org id from a validated uuid, the names from
`kernel.organization` via the read RPC.

---

## 3. SECURITY PROPERTIES

| # | Property | How |
|---|---|---|
| **S1** | **Anonymous is refused.** | `Authorization: Bearer` required, then `auth.getUser`. Both 401. |
| **S2** | **Authority is server-side and precedes creation.** | `kernel.has_org_role` runs on the caller's JWT before the limiter and before Stripe. The org id comes from the body; the ANSWER is computed in Postgres against `auth.uid()`, so a forged `org_id` buys nothing (`077:453-466`). |
| **S3** | **Two gates, not one.** Endpoint: `org_owner`/`org_finance`. **Bind: `org_owner` only** (093:658 dropped finance, SoD-1) **plus an aal2 step-up** (093:665-672) **plus `org_status ∈ (approved, active)`** (093:712). No venue role at either. | Roles are single-valued with no inheritance (`077:150`), so every name is listed explicitly. Ruling A7: a `venue_manager` is an employee of a site, not an officer of the entity. |
| **S3b** | **Every bind precondition is refused BEFORE the account is minted.** | 093's own `get_org_connect_state` header names the failure this prevents: mint-then-refuse strands a live Stripe account with no row pointing at it. The `aal` claim is decoded from the already-verified token as a **pre-flight only** — the DB re-reads `request.jwt.claims` and stays authoritative, so this can refuse earlier but never permit. |
| **S4** | **THE SERVER MINTS; THE CALLER NEVER NAMES AN ACCOUNT.** Closes **G-1**. | Three-key body allow-list; the only value passed to `set_org_connect_ref` is the id Stripe just returned, re-validated against `^acct_[A-Za-z0-9]+$`. |
| **S4b** | **Provenance is enforced in the database, not just by this function's good behaviour.** Closes **RT-A-3**. | `stage_org_connect_ref` (093:329, service_role) records the platform-minted id; the bind then accepts *only* that value. A blocklist could not catch an attacker's own fresh Stripe account — the red team bound `acct_ORPHANATTACKER` straight through the cross-plane check — and this is an allowlist of exactly one value written by a credential a browser session never holds. |
| **S4c** | **Two keys, and this function is the only place they meet.** | Staging needs `service_role`; binding needs a human `org_owner` on an aal2 session and refuses a `service_role` connection outright (093:850-856). A leaked service key can stage and get no further; a compromised owner can bind only what the platform minted for that org. The two clients are never collapsed. |
| **S4d** | **The pending ref is single-use.** | Consumed by a successful bind (093:938), so it cannot be replayed into a later re-point. |
| **S4e** | **The sentinel can never reach Stripe.** | 093's `connect_account_ref` is the literal `masked:call_kernel.get_org_connect_ref` when bound. It is consumed only as a third bound/unbound signal and refused by name at the resolve; the account id comes solely from `get_org_connect_ref`. |
| **S5** | **Bind rides the caller's JWT, not service_role.** | `set_org_connect_ref` raises when `auth.uid()` is NULL (`077:962-966`) because it stamps `payout_destination_set_by` — the SoD-1 operand that later bars the setter from requesting the payout (`087:428-431`). |
| **S6** | **Role re-checked at completion, not only at initiation.** Closes **G-9**. | Authority is re-read live by `get_org_connect_state`, again by `set_org_connect_ref` (`077:967`), and again on every return/refresh call, because the return route calls this same function. A role lost mid-onboarding cannot complete a bind. |
| **S7** | **The return URL carries no trusted state.** Closes **G-8**. | Redirect targets are rejected unless they have empty `search` **and** empty `hash` — state cannot be put in the URL, so no handler can be tempted to read it. Follows `app/payout-return.tsx:33-39`, which reads nothing. Status is recomputed from (caller session × live Stripe) on every call. |
| **S8** | **Replay is a no-op.** | Stripe idempotency key `connect_org_${org_id}` replays the same account; `set_org_connect_ref` returns `noop_replay` for the same id (`077:985-990`) and refuses a different one (`077:991-993`); `status_only` is a pure read. A refreshed, back-buttoned or link-previewed return changes nothing. |
| **S9** | **Resolve-before-create, from the verb that actually returns an id.** Closes **RT-A-4**. | `kernel.get_org_connect_ref` (093:1081) is the operand; the mint block sits inside `if (!accountId)` and is unreachable when one exists. Called with the **service** client — it has no `has_org_role` predicate by design (that tests `auth.uid()`, NULL on a machine session), so **its protection is its grant and its authority gate is S2**, which always runs first. A read failure is 503, never "assume unbound". |
| **S9b** | **Three-way cross-check between the readers.** | `(ref !== null)` must equal `connect_bound` **and** the presence of the `connect_account_ref` sentinel. Disagreement means we do not know whether this org has an account — the single question that decides whether to mint — so the request fails closed at 503 and raises Sentry. No winner is picked. |
| **S10** | **NO STALE-ACCOUNT RE-MINT.** Closes Ruling G **T-1**. | The seller path archives a dead id and mints a replacement (`create-connect-account:239-261`). On this plane that is a *destination-replacement primitive* reachable by inducing a Stripe error — no `org_owner`, no aal2, no cool-down, no `org.payout_destination.change` audit row. Here a bound-but-unreachable account is `409 destination_unusable` and routes the operator to `kernel.set_org_payout_destination`, which has those controls. |
| **S11** | **Fail closed on every ambiguity.** | Limiter RPC error → 503. `has_org_role` unreadable → 503, never allow. Read RPC missing/erroring → 503, and **in particular never "assume no account and mint one"**. Unsafe redirect config → 500 before any Stripe call. |
| **S12** | **No open redirect.** | Env-only, `https:`-only, host-pinned, state-free. Validated twice — before minting, and again before link creation. |
| **S13** | **Every mutating path leaves a trace.** | The bind writes `org.connect_ref.bind` to `kernel.admin_audit` (093:736, append-only twice over) and emits `security_payout_destination_changed` to every `org_owner`/`org_finance` (093:759 — but see B9, the drainer arm is still missing). Every refusal calls `kernel.record_money_denial('payout.destination','organization',…)` (`085:1567`, `authenticated`-only so the actor is a real human). Structured `[connect-onboarding]` logs on mint, bind, denial and link issue. Sentry on orphans, mirror failures and misconfiguration. |
| **S19** | **The capability mirror is not written best-effort.** | `sync_org_connect_state` failure is `console.error` + Sentry + a non-2xx (§5), never a warn. |
| **S14** | **`status_only` mutates nothing.** | It reads the ref, retrieves the account from Stripe, derives status, returns. No mirror write, no link creation, no limiter consumption. |
| **S15** | **The full account id never leaves.** | Responses and Sentry extras carry `last4` only. |
| **S16** | **Live Stripe read, never a cached or event-borne snapshot.** | `GET /v1/accounts/{id}` every time — Stripe's own guidance, and the reason `status_only` is trustworthy. |
| **S17** | **`transfers === 'active'` is the readiness predicate.** | Adopted from the shipped probe `_shared/payouts.ts:96-98` rather than invented. `ready` outranks outstanding requirements, per Ruling F §3.6.2: warn loudly, gate nothing — taking a live on-sale event down over a paperwork item is a self-inflicted outage. |
| **S18** | **No idempotency key on link creation.** | Account Links are single-use and expire in minutes; a deterministic key would replay a burned link. The one place a fresh result is the correct result. |

### The one residual: the orphan account

If `get_org_connect_state` says NULL and the bind then says `destination_already_set`, an unbound
Stripe account exists that nothing references. The function **does not delete it and does not
rebind** — an error-triggered destination swap is precisely Ruling G T-1, and deletion is
irreversible. It logs `ORPHAN Stripe account minted` and raises a Sentry event with the org id and
last4 for reconciliation.

The window is effectively closed by construction: concurrent requests for one org replay the same
idempotency key, so the only way to reach it is a stale read of a ref bound more than 24 h earlier —
i.e. a read RPC that lied. Documented rather than engineered away, because every alternative
(delete, rebind, retry) is worse.

---

## 4. WHAT MUST HAPPEN BEFORE THIS COULD BE DEPLOYED

**Blocking.**

| # | Item | Why |
|---|---|---|
| **B1** | **Migration 093 part 30 applied** — `kernel.get_org_connect_state` (:981), the hardened `kernel.set_org_connect_ref` (:628) and `kernel.sync_org_connect_state` (:121), with the three new `kernel.organization` columns (:88-96). | ~~Previously blocking on a reader that did not exist.~~ 093 supplies it. Until applied, `get_org_connect_state` returns `PGRST202` and every call fails closed at `503 connect_state_unavailable` — creating nothing. |
| **B1b** | ~~`kernel.get_org_connect_ref`~~ — **DONE**, 093:1081, `service_role` EXEC only (revoke at :1100, grant at :1102). Wired. | n/a |
| **B1c** | ~~pending-ref recording verb~~ — **DONE**, `kernel.stage_org_connect_ref` (093:329, revoke :408, grant :410). Wired at step 7c. | n/a — closes 093 residual R30-6. |
| **B2** | PostgREST exposed schemas must include `kernel` (Dashboard → API → `db_schemas`), or every `.schema('kernel')` call 404s. | Same precondition `delete-account/index.ts:28-29` records. |
| **B3** | Env: `VENUE_CONNECT_RETURN_URL`, `VENUE_CONNECT_REFRESH_URL`, plus the existing `STRIPE_SECRET_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SENTRY_SERVER_DSN`. | The defaults point at dashboard routes that **do not exist yet** (see B5). Host-pinning means a target outside `snatchitapp.com` is refused, not silently used. |
| **B4** | Deploy with `verify_jwt: true`. There is no `supabase/config.toml` in this repo, so it is a deploy-time flag. | Edge spec §3.3. |

**Prerequisites this function depends on but does not own** (Ruling F "Prerequisites this ruling
creates"):

| # | Item | Effect if missing |
|---|---|---|
| **B5** | **P9** — venue-dashboard `/dashboard/payments/connect/return` and `/refresh` routes. `return` must **not** claim success; it re-calls this function with `status_only: true`. `refresh` immediately re-calls it to mint a fresh link. | Stripe sends the operator to a 404. Onboarding is unusable end-to-end. |
| **B6** | **P3/P4 — DONE in 093.** `sync_org_connect_state` + `connect_transfers_active` / `connect_state_synced_at`. Note the verb writes `transfers_active` in **both** directions, correctly: a venue that loses `transfers` must stop selling, which is the opposite of `profiles.stripe_onboarding_complete`'s deliberate monotonicity. | n/a |
| **B7** | **P2** — the org arm of the `account.updated` webhook. **Owned by another agent; not touched here, and reported as now calling `sync_org_connect_state` — 093 residual R30-2 is stale.** `metadata[snatchit_plane]=organization` is set by this function to give that arm an unambiguous discriminator. | Without it `connect_transfers_active` only ever changes at onboarding time: an account Stripe later disables would keep selling until someone re-ran this endpoint. |
| **B8** | **P5/P6** — G1 in `catalog.publish_event` (`announced → on_sale`), G2 in `venue.create_primary_checkout`, behind `venue.require_connect_for_on_sale` (NULL ⇒ gate ON). | Onboarding binds a payee but nothing enforces that a selling org has one. |
| **B9** | **P7 / G-2 — HALF DONE.** 093:759 makes `set_org_connect_ref` emit `security_payout_destination_changed` to every `org_owner`/`org_finance`, so the producer exists. **The routing half does not:** 093 residual R30-1 records that `notify.drain_outbox` (092:730) has no arm for that type and counts the envelope `unmapped`. | **A destination change still reaches nobody.** Do not read the emit as evidence G-2 is closed. Not fixable from the edge. |
| **B10** | **P10** — Stripe Dashboard Connect branding (name, colour, icon), required by hosted onboarding. | Stripe refuses to render the hosted flow. |

**Recommended before first live use** (Ruling G, owner/config decisions, none owned by this file):
set `payout.destination_cooldown_hours` (currently seeds `null` → the cool-down never engages,
`078:1553`); narrow `set_org_connect_ref`'s org-status gate from `applied|approved|active` to
`approved|active` (**G-6** — binding before platform review ages the probation window out); add the
cross-plane refusal so a ref that already exists in `public.profiles.stripe_connect_id` cannot be
bound (**G-1/G-4b**); add the `AFTER UPDATE OF stripe_connect_account_ref` audit trigger (**G-11**).

---

## 5. THE MIRROR WRITE, AND WHY ITS FAILURE IS NOT SWALLOWED

`kernel.sync_org_connect_state` (093:121) is called at its authored signature — five arguments:

```
sync_org_connect_state(p_org_id uuid, p_connect_account_ref text,
                       p_transfers_active boolean, p_observed_at timestamptz,
                       p_command_key text)
```

Both selectors are passed because both are held. `p_observed_at` is captured **immediately before**
the Stripe retrieve, not `now()`, because that is the instant the function stores and compares — a
later observation must never be able to look older than this one.

Four behaviours come from the verb and are **not** re-implemented in the edge: the ref-wins /
org-id-fallback resolution; the `conflict_locked` refusal of an account that is not the org's bound
destination; the `noop_replay` return for an out-of-order observation (a return, not a raise); and
the heartbeat-vs-transition split that stamps freshness without writing an audit row when the fact is
unchanged — which is what makes it safe to call on every poll without burying capability losses.

**The decision on failure: fail the request.** `connect_transfers_active` is the operand of the G1
on-sale gate and the G2 checkout gate, so "the mirror did not persist" *is* "this organization cannot
take money, and nothing said so". A 200 carrying a working onboarding link plus a `console.warn` is
indistinguishable from success in any log search anyone actually runs — the failure would surface as
a venue that silently cannot sell, weeks later, with no signal pointing here.

So every outcome is `console.error` + `captureException` + a non-2xx:

| Outcome | HTTP | `code` |
|---|---|---|
| `PGRST202` / "could not find the function" (signature drift, 093 unapplied) | 503 | `state_writer_unavailable` |
| RPC threw (transport) | 503 | `state_writer_unavailable` |
| `conflict_locked` — the minted account is not the org's bound destination | 409 | `conflict_locked` |
| any other error | 502 | `state_not_persisted` |

The non-2xx body carries the full state snapshot **plus `bound: true`**, so a client never reads it
as "nothing happened". Retrying the whole request is safe and is the intended recovery: the Stripe
idempotency key replays the same account, `set_org_connect_ref` returns `noop_replay`, and this verb
is a no-op on an unchanged fact. Nothing is double-created and nothing is double-bound.

The alternative considered and rejected was surfacing it as a 200 with a `state_persisted: false`
flag. It is strictly worse: a flag in a success body is exactly the kind of thing a client ignores,
and the request genuinely did not achieve what it claims to.

---

## 6. RT-A-4, RECONNECT, AND THE ONE SEAM LEFT OPEN

### 6.1 What RT-A-4 was

The resolve read a key carrying an account identifier off `kernel.get_org_connect_state`. That verb
returns `connect_account_last4` and **never** an id, because it is `authenticated`-reachable and must
not publish a payout destination to a browser session. So the read yielded `undefined`,
resolve-before-create was dead, `status_only` reported `not_connected` for organizations that were
bound, and the create path ran for orgs that already had an account. Stripe's idempotency key hid it
for 24 h; past the window **every attempt minted a new live connected account bound to nothing.**

**Fixed** by calling `kernel.get_org_connect_ref(p_org_id uuid) returns text` (093:1081) with the
**service_role** client. It returns NULL for an unbound org and never raises. The split is kept
exactly as authored — state-for-humans returns last4, ref-for-machines returns the identifier, and
`get_org_connect_state` is still what feeds anything surfaced to the client. Two guards were added
around it: a read failure is 503 and never degrades to "assume unbound", and the two verbs are
cross-checked (`ref !== null` must equal `connect_bound`) with a fail-closed 503 on disagreement.

`get_org_connect_ref` has no `has_org_role` predicate by design — that predicate tests `auth.uid()`,
which is NULL on a machine session, so it could only ever refuse. **Its protection is its grant, and
its authority gate is this function's step 4**, which authenticates the human and checks the org role
before the call is made. The call site carries that as a comment so it is not hoisted later.

### 6.2 RECONNECT — now implemented

With the real id, an already-bound org takes the same tail as a fresh one: live
`GET /v1/accounts/{id}`, capability mirror, then a link — `login_links` when onboarding is complete
(Express cannot be given an `account_update` Account Link), otherwise a fresh `account_onboarding`
link with `collection_options[fields]=eventually_due`. `409 reconnect_unavailable` is gone.

**Reconnect carries no owner gate and no step-up, deliberately.** Ruling F §3.4: resuming an
abandoned or expired flow does not change the destination, and requiring `org_owner` + aal2 to
re-enter a half-finished flow would leave a venue disabled and accruing money whenever the owner is
unreachable — a self-inflicted outage with no fraud benefit. Every mint-path gate therefore lives
inside the `if (!accountId)` branch.

The stale-account arm returns as a **refusal, not a self-heal**: a bound account Stripe will not
return is `409 destination_unusable` + Sentry, routing the operator to
`kernel.set_org_payout_destination`, which has the step-up, cool-down and audit row a re-mint would
skip (Ruling G T-1). A freshly minted account that reads back 404 is treated as transient (503).

### 6.3 RT-A-3 — the two-key sequence, wired

The red team bound `acct_ORPHANATTACKER` by calling `set_org_connect_ref` directly as
`authenticated`, on both a first bind and a live re-point. The cross-plane refusal could not stop it:
that is a blocklist over the individual seller plane, and an attacker's own fresh Stripe account is
on neither list. 093's fix is structural — the bind now accepts **only** an identifier the platform
has staged for that org, and staging is `service_role`.

**The sequence this function now runs, in this order:**

| # | Step | Client | Verb |
|---|---|---|---|
| 1 | authority | caller JWT | `kernel.has_org_role([org_owner, org_finance])` |
| 2 | resolve | **service_role** | `kernel.get_org_connect_ref` (093:1319) |
| 3 | mint (only if unresolved) | — | Stripe `POST /v1/accounts`, key `connect_org_${org_id}` |
| 4 | **stage** | **service_role** | `kernel.stage_org_connect_ref` (093:329) |
| 5 | **bind** | **caller JWT** | `kernel.set_org_connect_ref` (093:806) |
| 6 | sync | **service_role** | `kernel.sync_org_connect_state` (093:157) |

Steps 4 and 5 are the two keys. **Staging needs a machine credential; binding needs a human
`org_owner` on an aal2 session and refuses a `service_role` connection outright.** Neither alone can
bind: a leaked service-role key can stage a ref and get no further; a compromised owner can bind only
what the platform already minted for that org. This edge is the only place both halves meet, so the
two clients are deliberately kept separate — there is a comment on `stageConnectRef` saying not to
collapse them however tempting the shared code looks.

Three behaviours are left to the verb and not re-implemented: the cross-plane refusal (which it runs
**earliest of all**, so a personal seller account is now rejected *before* an operator is sent to
Stripe rather than after); the already-bound-to-another-org refusal; and overwrite-safe idempotency.

**Staging failure is fatal to the request** (`502 stage_failed` / `503 stage_unavailable`, both with
`console.error` + Sentry). Swallowing it would leave a live Stripe account that can never be bound —
the orphan outcome reached by a different road.

**Two bind errors mapped:** `no_pending_connect_ref` (nothing staged — what a direct-RPC attacker
gets, and what this function would get if step 7c were removed) and `connect_ref_not_platform_minted`
(staged one value, bound another). Both are unreachable from this function's own flow, so both log at
error and raise Sentry rather than being treated as ordinary user errors.

**The replay path still works, and depends on ordering inside the RPC.** The provenance check sits
*after* the replay and bind-once arms (093:895-914) because a successful bind clears the pending ref
— checking provenance first would turn the idempotent retry that G-8 depends on, and that
`tests/141:638-641` asserts, into a hard failure. `bindConnectRef` treats `noop_replay` as success
(`{ok: true, replay: true}`), never as an error.

### 6.4 Known limitation — carried, not fixed

**`connect_pending_ref` has no TTL** (093 residual R30-7). It is consumed by a successful bind, but
an abandoned onboarding leaves a staged value in place until the next stage call overwrites it.
Harmless: it can only ever authorise binding the account the platform itself minted for that
organization, so a stale pending ref grants nothing that a fresh one would not. A TTL sweep would be
the tidier long-term shape and is not in 093. **Not worked around in the edge** — re-staging on a
retry is a `noop_replay`, and a re-mint stages under its own command key and replaces the value.

---

## 7. VERIFICATION PERFORMED

**Type-checked.** `deno` is not installed on this machine, so `deno check` could not be run. Instead
the file was compiled with the repo's own TypeScript (`node_modules/typescript`, `tsc --noEmit`)
under `strict`, `target es2022`, `moduleResolution bundler`, with the two remote specifiers
(`deno.land/std@0.177.0/http/server.ts`, `esm.sh/@supabase/supabase-js@2.39.0`) mapped to hand-written
stubs and a `Deno.env` global declared. `--listFiles` confirms the real
`_shared/sentry.ts` and `_shared/stripe.ts` were pulled in and checked. **Result: zero errors**, and
zero again with `--noUnusedLocals --noUnusedParameters --noImplicitOverride`.

**Not verified, and why:**

- **No Stripe call was made.** No account was created, no link minted, no live or test key touched.
  The account/link parameter shapes are transcribed from Ruling F §3.2 and §2.2 and have not been
  exercised against the API.
- **Red-team scenarios re-checked by inspection, not execution.** (a) *Fresh org onboards and binds*
  — the six steps appear once each and in order: `hasOrgRole` (:1181) → `getOrgConnectRef` (:1233) →
  `createOrgAccount` (:1344) → `stageConnectRef` (:1354) → `bindConnectRef(caller, …)` (:1363) →
  `syncMirror` (:1435). (b) *Already-bound org never reaches account creation* — `accountId` is set
  from `get_org_connect_ref` before any branch, and `createOrgAccount` has exactly one call site,
  inside `if (!accountId)`; `status_only` on a bound org skips the `not_connected` early return
  (guarded by `!accountId`) and falls through to the live `GET /v1/accounts/{id}`, so it reports true
  bound state. (c) *Bind without staging is refused* — enforced in the RPC, not here; the edge maps
  `no_pending_connect_ref` and alarms on it, since from this flow it is unreachable. **Traced by
  grep over the control flow, not executed** — see below.
- **No RPC was called.** No local Postgres was started and production was not touched. Every
  signature was re-read from the source as authored:
  `kernel.get_org_connect_state(uuid)` (093:1206, grant :1272),
  `kernel.get_org_connect_ref(uuid) returns text` (093:1319, grant :1340),
  `kernel.sync_org_connect_state(uuid, text, boolean, timestamptz, text)` (093:157, grant :284),
  `kernel.stage_org_connect_ref(uuid, text, text)` (093:329, grant :410),
  `kernel.set_org_connect_ref(uuid, text, text)` (093:806),
  `kernel.has_org_role(uuid, text[])` (077:453) and
  `kernel.record_money_denial(text, text, uuid, text)` (085:1567) — the last two confirmed **not**
  redefined anywhere in `093_parts/`.
- **`db: { schema: 'kernel' }` is not type-verified against real `supabase-js` typings.** With an
  untyped `Database` generic, `SchemaName` defaults to `'public'` and a literal `'kernel'` may be
  rejected by `tsc` where the stub accepts it. This is the exact construct shipped in
  `delete-account/index.ts:154-158` (deployed 2026-09-02), so it is house-consistent — but a real
  `deno check` on a machine with Deno should confirm it.
- **Error-message matching is string-based** for `destination_already_set`, `conflict_locked`,
  `org_not_bindable`, `account_not_platform_minted_for_org`, `no_pending_connect_ref`,
  `connect_ref_not_platform_minted`, `step_up_required`, `step_up_unavailable` and `42501`, because these RPCs signal through `raise exception` text rather
  than distinct SQLSTATEs. Verified against the migration source, not against a live PostgREST error
  payload — the exact shape PostgREST puts in `error.message` should be confirmed once before relying
  on the 409-vs-403 split. The `PGRST202` branch matches on `error.code` first and only falls back to
  message text.
- **The `aal` pre-flight decode is untested against a real Supabase JWT.** It base64url-decodes the
  payload of an already-verified token and reads `claims.aal`; a token shaped differently degrades to
  `null` ⇒ `step_up_unavailable` ⇒ refusal, which is the fail-closed direction, but it would block
  onboarding entirely if the claim is not present where expected. **Confirm against one real aal2
  session before enabling.**
- **Concurrency was not exercised.** The one-account-per-org argument rests on Stripe's idempotency
  semantics plus the partial unique index (`077:124-126`); it was reasoned, not load-tested.
- **`stripe-webhook/index.ts` was not opened or modified** — another agent owns it.
