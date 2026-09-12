# RULING F — How a venue ORGANIZATION becomes connected to Stripe

**Agent F · primary-money architecture pass · branch `feature/venue-native-and-product-v2`**
**Status:** design ruling. No code, no migration, no Stripe object created by this pass.

**Hard constraint governing everything below:** venue money must never be attached to an individual
employee's personal Stripe account. The Stripe account must correspond to the correct legal and
economic entity.

---

## PART 1 — CURRENT-STATE INVENTORY

### 1.1 The finding, verified — and corrected in one detail

**The prior pass's conclusion holds: there is no organization-level Stripe onboarding path anywhere in
the application.** A repo-wide grep across `supabase/functions/`, `web/`, `app/`, `src/` and
`packages/` for `stripe_connect_account_ref`, `set_org_connect_ref` and `set_org_payout_destination`
returns **zero hits**. Every reference lives in migrations, pgTAP fixtures, or specification
documents.

**One correction to the inventory.** `ADVERSARIAL_ARCHITECTURE_REVIEW.md:79` states the column "has
exactly one writer, `kernel.set_org_payout_destination` (`085:1601`)". There are **two** SQL writers:

| Writer | Where | Role | Authority | Callers |
|---|---|---|---|---|
| `kernel.set_org_connect_ref` | `supabase/migrations/077_kernel_identity_orgs_and_roles.sql:948` | **BIND-ONCE** — the onboarding path | `has_org_role([org_owner, org_finance])` (`077:970`), caller-JWT bound: RAISES if `auth.uid()` is NULL (`077:963-967`) | **0** |
| `kernel.set_org_payout_destination` | `supabase/migrations/085_kernel_money_native.sql:1601` | **RE-POINT** — the destination change | `has_org_role([org_owner])` only (`085:1620`), grant maturity (`:1623`), `aal2` step-up (`:1628-1634`), cool-down (`:1643`) | **0** |

The bind-once writer was overlooked. This *strengthens* the finding rather than weakening it: the
database verb for org onboarding **already exists and is already correctly authorized**; what is
missing is everything above it. `kernel.set_org_connect_ref` raises `destination_already_set`
(`077:990-993`) on a second bind, so it cannot be used for a re-point, and
`set_org_payout_destination` carries controls (step-up, cool-down, SoD-1) that make it wrong for a
first bind. The two are correctly separated. Neither has ever been called.

Downstream consumers of the column exist and are blocked by its absence:
`kernel.request_org_payout` (`087:445-447`) raises `precondition_failed: no_payout_destination`, and
`087:506/530/544` bind every dual-control approval to the current destination.

### 1.2 `supabase/functions/create-connect-account/index.ts` — what it actually creates

Read in full. The account-creation call is `index.ts:202-212`:

```
'type': 'express',
'country': 'US',
'business_type': 'individual',
'capabilities[transfers][requested]': 'true',
'business_profile[product_description]': 'Individual reselling event tickets on Snatch It',
'metadata[user_id]': userId,
```

| Question | Answer | Cite |
|---|---|---|
| Account type | Legacy **Express** (Stripe-hosted Express Dashboard, platform-liable) | `index.ts:203` |
| Capabilities | **`transfers` only.** `card_payments` is deliberately not requested | `index.ts:206` |
| Entity | **`individual`** — a natural person, never a company | `index.ts:204` |
| Country | Hardcoded **US** | `index.ts:204` |
| Where the id is stored | **`public.profiles.stripe_connect_id`**, written with the service-role client | `index.ts:215-218` |
| Who may call it | **Any authenticated user.** The only gate is a valid JWT (`index.ts:45-64`) plus a fail-closed rate limit of 5 per 600 s (`index.ts:130-158`). No role check exists, because there is no org | `index.ts:119`, `:131` |
| Subject derivation | Entirely from `auth.uid()` → the caller's own profile row. **There is no org parameter anywhere in the file** | `index.ts:168-172` |

Two additional behaviours worth carrying forward: a **stale-account self-heal** that archives a
test-mode Connect id into `stripe_connect_archive` and mints a fresh live account in the same request
(`index.ts:239-261`), and a **status-only mode** that is deliberately exempt from the rate limit
because clients fire it on mount, focus and foreground (`index.ts:126-130`).

State persisted after every call (`index.ts:285-293`): `stripe_onboarding_complete` (monotonic — only
ever set true, deliberately, because it gates listing creation), `stripe_charges_enabled`,
`stripe_payouts_enabled`, `stripe_connect_status`. The in-file comment records that these three
columns were previously **written by nothing at all** and sat at their defaults forever. That is the
precedent this ruling's data-model section is built to avoid repeating.

### 1.3 Onboarding UX today, and its return/refresh handling

| Surface | File | Behaviour |
|---|---|---|
| Mobile setup | `app/settings/payout-setup.tsx` | Debounced status check on mount, focus and foreground (`:102-131`), with a 6 s hard timeout so a slow Stripe round-trip cannot freeze the screen (`:76-81`). Never regresses status on a network error (`:90-96`). Opens the returned URL via `expo-web-browser`; web pre-opens a blank tab **before** the async call to survive popup blockers (`:140-143`) |
| Mobile return | `app/payout-return.tsx` | **Claims success unconditionally** — *"Payout setup complete… Your Stripe account is connected"* (`:48-52`) — then auto-routes to the profile tab after 1500 ms (`:34-39`) |
| Mobile refresh | `app/payout-refresh.tsx` | Correct: no error treatment, auto-routes back to `/settings/payout-setup` which mints a fresh link (`:32-40`) |
| Web | `web/src/components/account/PayoutSetup.tsx` | Three-state copy block (`:9-32`); full-page navigation, not a new tab (`:60`). **No web `/payout-return` route exists** — `find web/src/app -name "*payout*"` is empty; the comment at `:57-59` records that Stripe returns the browser to `snatchitapp.com/payout-return`, shared with mobile |

Redirect targets are hardcoded to `https://snatchitapp.com/payout-refresh` and
`https://snatchitapp.com/payout-return` (`create-connect-account/index.ts:98-99`), validated as HTTPS
at request time (`:161-163`), and deep-link into the app via the `snatchit://` scheme
(`payout-setup.tsx:22-34`).

**`app/payout-return.tsx` is wrong on Stripe's own terms** and must not be copied into the venue
dashboard. Stripe states of `return_url`: *"It doesn't mean that all information has been collected,
or that there are no outstanding requirements on the account. It only means the flow was entered and
exited properly. No state is passed with this URL."*
(<https://docs.stripe.com/connect/custom/hosted-onboarding>)

### 1.4 `kernel.organization` and the org-side fields

`kernel.organization` (`077:106-123`) carries, in full:

`org_id` · `legal_name` (not null, non-empty) · `display_name` · `status`
(`applied|approved|active|suspended|closed`) · **`stripe_connect_account_ref`** ·
`payout_destination_locked_until` · `payout_destination_set_by` (FK `auth.users`, `on delete
restrict`, retained at tombstone) · `home_region` · timestamps.

There are **no capability flags, no requirements state, no onboarding status** on the organization.
Whatever Stripe reports about an org account has nowhere to live today.

Structural facts:
- `UNIQUE(stripe_connect_account_ref) WHERE NOT NULL` (`077:124-126`) — one Connect payee per org, and
  no account may be shared across orgs.
- Client grant is column-scoped to `(org_id, display_name, status)` for `authenticated` (`077:120-123`).
  `legal_name`, the Connect ref and the payout lock are visible only to `org_owner`/`org_finance`/
  platform, and that scoping rides RPCs rather than grants (recorded errata E-1). pgTAP asserts the
  column is not directly selectable (`supabase/tests/141_phase2_identity_orgs_deletion.sql:225`).
- `kernel.create_organization` (`077:767`) takes `legal_name` + `display_name`, creates the row at
  status `applied`, and makes the caller sole `org_owner` by construction (`077:807-812`).
- Org roles are **single-valued** (`kernel.org_member.role`, `077:150`) and there is **no
  inheritance** — `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:1007`: *"no `org_owner` row can ever
  satisfy `has_org_role([org_finance])`… Nothing in this product should ever rely on role inheritance
  for a money action."* Every authority below is therefore granted by name.

### 1.5 The webhook's `account.updated` handling

`supabase/functions/stripe-webhook/index.ts:795-858`. It reads `id`, `details_submitted`,
`charges_enabled`, `payouts_enabled` off the event object, computes
`onboardingComplete = details_submitted && charges_enabled && payouts_enabled` (`:816-819`), and
writes four columns:

```
.from('profiles').update({ stripe_onboarding_complete, stripe_charges_enabled,
                           stripe_payouts_enabled, stripe_connect_status })
.eq('stripe_connect_id', accountId)
```
— `index.ts:827-837`.

**The match is `profiles.stripe_connect_id` and nothing else.** An organization's Connect account
would match **zero rows**, and the handler logs `matched_profiles: 0` and ACKs as success
(`:850-857`). Today an org account could be created and Stripe could disable it, and the platform
would never know. Extending this branch is a prerequisite of the whole design, not a nicety.

Secondary note: the handler trusts the event's embedded snapshot. Stripe advises otherwise — *"we
recommend using `data.object.id` to retrieve the `Account` object. The `Event` object's `data.object`
hash contains a snapshot… and those values might have changed"*
(<https://docs.stripe.com/connect/track-account-onboarding>).

### 1.6 What downstream code already expects of a destination

`supabase/functions/_shared/payouts.ts:83-98` — the destination pre-flight probe reads
`capabilities.transfers`, `details_submitted`, `payouts_enabled`, `requirements.disabled_reason`,
`requirements.currently_due`, and gates on exactly one thing:

```
if (!acct.ok || caps.transfers !== 'active') return { ok: false, reason: 'destination_not_ready', … }
```

The shipped money code already knows that **`transfers === 'active'` is the readiness predicate.**
This ruling adopts that predicate rather than inventing one.

### 1.7 The money model that constrains the answer

Ruling A (`docs/phase2/_decisions/A_venue_money.md:95-115, :256`) fixes the funds flow: the platform
mints an ordinary platform PaymentIntent, funds land in **Snatch It's own Stripe balance**, and the
org is paid later by `POST /v1/transfers` with `source_transaction`. No Connect object ever holds the
money. `kernel.payout.payee_kind ∈ ('organization','identity')` with `payee_org_id` FK →
`kernel.organization` (`085:114-121`) — **there is no `payee_venue_id` column.**

Consequence: Snatch It is the merchant of record, owns disputes, and is liable for negative balances.
Stripe's guidance is consistent: *"We recommend using separate charges and transfers only when you're
responsible for negative balances of your connected accounts"*
(<https://docs.stripe.com/connect/account-capabilities>). Legacy Express already places
fraud/dispute liability on the platform (<https://docs.stripe.com/connect/accounts>).

### 1.8 Missing artefacts, named

| Artefact | Specified at | Exists? |
|---|---|---|
| `connect-onboarding` edge function | `PHASE_2_EDGE_FUNCTION_SPEC.md:439-462`, `:1778` | **No** — `ls supabase/functions/` |
| Org arm of the `account.updated` webhook | edge spec §4 | **No** — `stripe-webhook/index.ts:837` |
| Any org/venue dashboard | — | **No** — `web/src/app/` has no venue or org route |
| Contract for `kernel.set_org_connect_ref` | open defect **G-3** (`PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md:69`) | drafted at RPC §20.1.1; `PFA-6` records the EXEC-class contradiction and that the caller-authorized reading is the one built |

---

## PART 2 — STRIPE, AS DOCUMENTED TODAY

### 2.1 Account models and who carries what

Stripe now has two Accounts APIs. The legacy types page labels Standard/Express/Custom a
**"Deprecated feature"** and steers new platforms to **Accounts v2** configurations (`merchant` /
`recipient` / `customer`), or to **Accounts v1 with controller properties**
(<https://docs.stripe.com/connect/accounts>, <https://docs.stripe.com/connect/accounts-v2>,
<https://docs.stripe.com/connect/migrate-to-controller-properties>).

v1 controller properties, and the legacy types they compose into
(<https://docs.stripe.com/connect/migrate-to-controller-properties>):

| Type | `losses.payments` | `fees.payer` | `requirement_collection` | `stripe_dashboard.type` |
|---|---|---|---|---|
| Standard | `stripe` | `account` | `stripe` | `full` |
| **Express** | **`application`** | `application_express` | **`stripe`** | `express` |
| Custom | `application` | `application_custom` | `application` | `none` |

Liability and verification, by legacy type (<https://docs.stripe.com/connect/accounts>):

| | Standard | **Express** | Custom |
|---|---|---|---|
| Who handles verification | Stripe | **Stripe** | Platform or Stripe |
| Who owns the dispute | Account (direct); **platform** (destination) | **Platform** | Platform |
| Negative-balance liability | Stripe | **Platform** (`losses.payments=application`) | Platform |
| Dashboard | Full | **Express (login-link only)** | None |
| Auto-updates for new compliance requirements | Yes | **Yes** | **No** |

`controller.stripe_dashboard.type` is **immutable** — *"To change a connected account's dashboard, you
must create a new `Account` object"* (<https://docs.stripe.com/connect/design-an-integration>). This
choice cannot be revisited without re-onboarding.

### 2.2 Onboarding mechanisms

**Hosted (Account Links)** — <https://docs.stripe.com/connect/custom/hosted-onboarding>,
<https://docs.stripe.com/api/account_links/create>:
- Required: `account`, `type` (`account_onboarding` | `account_update`), `refresh_url`, `return_url`.
  Optional `collection_options.fields` = `currently_due` | `eventually_due`.
- The URL is **single-use** and expires in **a few minutes**. *"Don't email, text, or otherwise send
  account link URLs outside of your platform application."*
- `refresh_url` fires on: expired link, already-visited link (refresh / back / forward), **or a
  messaging client auto-previewing the URL and burning it**. Handler must mint a fresh link and
  redirect back in.
- `return_url` proves nothing (quoted at §1.3). Check `requirements`, or listen to `account.updated`.
- Live mode requires HTTPS. **Not supported inside webviews** — standalone browsers only.
- Prefilling reduces prompts, but for `requirement_collection=stripe` accounts identity fields become
  unreadable once the first Account Link or Account Session is created.
- **`type=account_update` is not creatable for accounts with Stripe-hosted Dashboard access** — i.e.
  not for Express. Their self-service surface is the Express Dashboard login link
  (`POST /v1/accounts/{id}/login_links`).

**Embedded (Connect components + AccountSession)** — <https://docs.stripe.com/connect/embedded-onboarding>:
platform builds a server endpoint minting `POST /v1/account_sessions` and a client that calls
`loadConnectAndInitialize({ publishableKey, fetchClientSecret })` then
`create('account-onboarding')`. The client secret **must never be stored, logged or cached** —
`fetchClientSecret` must mint a fresh session each time. Requires CSP entries for
`connect-js.stripe.com` / `js.stripe.com` and `Cross-Origin-Opener-Policy: unsafe-none`
(`same-origin` breaks auth). Not usable in mobile webviews. Stripe's own line: *"Building and
maintaining an API onboarding flow is resource-intensive… Stripe strongly recommends that you use
embedded onboarding"* — i.e. embedded is the recommended alternative to **API** onboarding, not
necessarily to hosted.

### 2.3 Capabilities required for each money movement

<https://docs.stripe.com/connect/account-capabilities>, <https://docs.stripe.com/connect/charges>:

| Action | Capability that must be **ACTIVE** |
|---|---|
| (a) Direct charge on the connected account | **`card_payments`** — and requesting it *requires* also requesting `transfers` |
| (b) Destination of a destination charge | **`transfers`** |
| (c) Receive a `POST /v1/transfers` | **`transfers`** |
| (d) Payout to its own bank | **`payouts_enabled: true`** plus a **verified `external_account`**. There is no separately requested `payouts` capability in v1 (in v2 it is `stripe_balance.payouts`) |

Two traps: *"If a connected account has both `card_payments` and `transfers`, and the `status` of
either one is `inactive`, then both capabilities are disabled."* And requesting a capability can
itself add requirements and fire `account.updated` — some capabilities are permanent once requested.

`charges_enabled` / `payouts_enabled` are account-level **rollups** and can disagree with individual
capability statuses in both directions; the capabilities page's `legacy_payments` transition table
shows `card_payments: "inactive", transfers: "inactive"` alongside `charges_enabled: true`. **Gate the
specific money movement on the specific capability**; use the rollups only as coarse UI signals.
Sandboxes may not enforce capability gating — never validate the gate in test mode alone.

### 2.4 Observing readiness

Primary signal is **`account.updated`**, available for all connected accounts
(<https://docs.stripe.com/connect/webhooks>). `capability.updated` exists but no Connect readiness
pattern in the docs is built on it — treat it as supplementary, never as the sole signal. Also
relevant: `payout.failed` (which **disables the external account** until updated) and
`account.external_account.updated`.

`requirements` fields (<https://docs.stripe.com/connect/handling-api-verification>):
`currently_due` (resolve by `current_deadline` to stay active) · `eventually_due` (becomes
`currently_due` when a threshold trips, and can pull `current_deadline` earlier) · `past_due` (**a
subset of `currently_due`; these have already disabled capabilities**) · `pending_verification` (async
review in flight) · `disabled_reason` · `errors[]` · `current_deadline` (earliest across **all**
requested capabilities including hidden ones).

Enforcement, verbatim: *"Stripe typically disables payouts on the account if we don't receive the
information by the `current_deadline`… if payouts are already disabled and the account is
unresponsive to our inquiries, Stripe might also disable the ability to process charges."*

Because Express carries `requirement_collection = stripe`, **Stripe handles upcoming requirement
changes automatically** and `future_requirements` handling does not fall to this platform
(<https://docs.stripe.com/connect/handle-verification-updates>).

There is **no documented Stripe rule against caching account state.** The documented constraints are
narrower and both apply here: re-fetch by id rather than trusting an event snapshot
(<https://docs.stripe.com/connect/track-account-onboarding>), and identity data becomes unreadable
for Stripe-collected accounts after the first Account Link. The minimalism recommended in Part 3 §3
is therefore *this* platform's engineering position — grounded in the `profiles` columns that sat at
their defaults forever (`create-connect-account/index.ts:269-276`) — not an appeal to Stripe policy.

### 2.5 Company entities, and one account per legal entity

`business_type ∈ {company, individual, non_profit, government_entity}`. A `company` brings the
**Persons API** (`representative` / `owner` / `director` / `executive` / `authorizer`),
`company.owners_provided` / `directors_provided` / `executives_provided`, **`company.tax_id`** (EIN,
IRS-checked in the US), and `company.verification.document` (articles of incorporation — which
**Stripe Identity cannot satisfy**). Omitting `company.structure` makes Stripe default to *private*
and demand owner information (<https://docs.stripe.com/connect/identity-verification>,
<https://docs.stripe.com/connect/handling-api-verification>).

Prefilling is explicitly supported and reduces prompts, with two traps: setting `country` or
requesting any capability at creation **locks the country**; and prefilling `company.address`, any
`individual` field, any `Person`, `external_accounts`, or the `*_provided` flags **disables networked
onboarding** (<https://docs.stripe.com/connect/legal-entity-sharing>).

On entity scope (<https://docs.stripe.com/get-started/account/multiple-accounts>): *"You can only
associate each account with the tax ID and legal entity of one business."* But one legal entity may
back several accounts — *"When you have multiple projects or businesses that operate under the same
legal entity, you can use the same tax ID and business information across multiple accounts"* — and
Connect's mechanism for that is **networked onboarding / legal entity sharing**, which synchronizes
`business_type`, `country`, `company` and `individual` across accounts while copying
`external_accounts`, `business_profile` and statement descriptors once at creation. Eligibility
requires `requirement_collection = stripe` and hosted or user-authenticated embedded onboarding —
both satisfied by Express.

Using an individual's personal account for a business is permitted by Stripe when there is genuinely
no separate entity (<https://support.stripe.com/questions/selling-on-stripe-without-a-separate-business-entity>),
modelled honestly as `business_type=individual` or `company.structure=sole_proprietorship`. That is
irrelevant to a venue and does not soften this ruling's hard constraint: an *employee's* personal
account is never the venue's entity under any Stripe reading.

---

## PART 3 — THE DESIGN

### 3.1 The account belongs to the ORGANIZATION

**Ruling: one Stripe connected account per `kernel.organization`. No venue-level Connect account, and
no venue-level Connect column.**

Justification, from the schema and the money model:

1. **The schema already says so, structurally.** `catalog.venue.org_id` is `not null references
   kernel.organization(org_id) on delete restrict` (`078:100`) with `venue_org_idx` (`078:117`) — one
   org, many venues, and no venue without an org. `catalog.event` carries **both** `venue_id` and
   `org_id` (`078:136-137`), so every event already resolves to an org without traversing its venue.
2. **The money model has no venue-shaped hole to put an account in.** `kernel.payout.payee_kind` is
   `('organization','identity')` with `payee_org_id` and `payee_identity_id` under an XOR constraint
   (`085:114-146`). There is no `payee_venue_id`, no venue FK, and no venue index. A venue-level
   Connect account would have no column to live in and no code path to be resolved from.
3. **Every existing resolution is org-level.** `kernel.request_org_payout` locks the *organization*
   row and reads `v_org.stripe_connect_account_ref` (`087:427, :445-447`); the dual-control approval
   payload binds `destination_ref` to the org's ref (`087:506, :530, :544`);
   `kernel.list_org_payouts` filters on `payee_org_id` (`085:1465`). Introducing a venue-level
   destination means rewriting the settlement, approval-staleness and probation logic — all of which
   are already frozen and pgTAP-covered.
4. **A venue is not a legal person.** `kernel.organization.legal_name` is `not null` with a non-empty
   check (`077:107`) — the org is where the legal entity lives. `catalog.venue` has `name`,
   `neighborhood`, `address`, `capacity_hint`, `approval_status` (`078:98-115`) and no legal identity
   whatsoever. A Stripe account requires an EIN, a company structure, a representative and beneficial
   owners (§2.5); a venue has none of these. Attaching money to `catalog.venue` would force the
   platform to invent a legal entity for a room.
5. **The uniqueness constraint already asserts the ruling.** `UNIQUE(stripe_connect_account_ref) WHERE
   NOT NULL` (`077:124-126`) is a one-payee-per-org invariant. Nothing equivalent exists or could
   exist on `catalog.venue`.
6. **Venues are re-parentable; accounts are not.** `catalog.update_venue` treats `org_id` as a
   **tenancy move** with its own guard (`078:685-701`). A venue-bound Stripe account would be orphaned
   — or, worse, carried into a different legal entity — the moment a venue changed hands. An org-bound
   account is immune: the venue moves, the money identity stays with the entity that owns it.

**The multi-venue case, answered directly.** One organization operating several venues is the
*normal* case and it needs **one** account. Venues under one org share one legal entity by
construction, and Stripe binds an account to one tax ID and legal entity (§2.5). Per-venue settlement
is already handled without per-venue money: `venue.settlement` carries org, venue and event
(`087:44-67`) and `venue.settlement_line` is per-cause and per-`cause_ref` — the venue dimension lives
in the ledger, where it belongs, not in the Stripe topology.

**When a "venue group" really is several legal entities** — each venue its own LLC, which is common —
the correct modelling is **several organizations, one per legal entity**, each owning its venues.
`kernel.organization` is the unit of legal entity; `catalog.venue` is the unit of operations. This
needs no schema change, and Stripe's networked onboarding lets a shared owner reuse verified entity
data across those orgs' accounts (§2.5) — which is a further reason not to prefill `company.address`
or persons (it would disable exactly that reuse).

**What is knowingly given up.** Stripe permits several accounts under one legal entity, and its
strongest argument for that is statement descriptors: *"a customer who purchases from your business
'XYZ' might see a charge from your business 'ABC' on their statement, potentially resulting in a
dispute"* (<https://docs.stripe.com/get-started/account/multiple-accounts>). **That argument does not
apply here.** Under Ruling A the platform is the merchant of record and the buyer's statement shows
Snatch It's descriptor, never the venue's — Stripe's own capabilities page says so of the `transfers`
capability: *"a connected account's customers' bank statements display your platform's statement
descriptor, not the connected account's."* Per-venue bank accounts are the only real loss, and they
are recoverable later without re-architecting: a future per-venue payout destination would be an
additive column plus a resolution function, taken only on demonstrated demand.

### 3.2 The individual-seller onboarding cannot be generalized

**Ruling: an organization needs a separate integration — a new `connect-onboarding` edge function, as
`PHASE_2_EDGE_FUNCTION_SPEC.md:439-462` already specifies. `create-connect-account` must not be
extended.**

Not a preference. Six independent blockers:

1. **It has no subject but `auth.uid()`.** The account id is written to
   `profiles.stripe_connect_id` for the *calling user* (`index.ts:215-218`). Adding an `org_id`
   parameter is not a small change — it inverts the function's entire subject model. And an
   accidental fall-through to the individual path is precisely the hard-constraint failure: **a venue
   employee runs "set up payouts", and the venue's money is now bound to that employee's personal
   Stripe account.** The two paths must not share a door.
2. **Wrong entity, hardcoded.** `business_type: 'individual'` (`index.ts:204`) and
   `'Individual reselling event tickets on Snatch It'` (`:207`). A venue is `business_type: 'company'`,
   which brings the Persons API, EIN, company structure and entity documents (§2.5). These are not
   parameters on the same flow; they are a different KYC surface.
3. **No authorization surface exists.** The only gate is a valid JWT (`index.ts:119`). Org onboarding
   must be `has_org_role`-gated, and the gate must live in the RPC — `kernel.set_org_connect_ref`
   already enforces it (`077:970-973`).
4. **The write path is architecturally incompatible.** `create-connect-account` writes tables directly
   with the service-role client. `kernel.set_org_connect_ref` **RAISES on a service-role connection**
   because `auth.uid()` is NULL (`077:963-967`) — it must stamp `payout_destination_set_by`, the SoD-1
   operand, with a real human. So the org edge function must forward the *caller's* Authorization
   header for the bind. That is the opposite of how the existing function is written, and `PFA-6`
   records that this was a deliberate, ratified choice.
5. **The webhook cannot see org accounts.** `.eq('stripe_connect_id', accountId)` on `profiles`
   (`stripe-webhook/index.ts:837`). Generalizing the creator without extending the webhook produces an
   account nobody monitors.
6. **The return targets are wrong.** They deep-link into the mobile profile tab
   (`app/payout-return.tsx:36`) and assert success (`:48-52`). A venue operator on a desktop dashboard
   must land back in the dashboard, and must not be told they are done when Stripe has not said so.

**What is reused, and should be:** `_shared/stripe.ts` (the pinned `Stripe-Version`), the
`createSellerPayout` destination probe's readiness predicate (`_shared/payouts.ts:96-98`), the
fail-closed rate limiter (`create-connect-account/index.ts:70-93`), the HTTPS validation of redirect
targets (`:161-163`), the stale-account self-heal (`:239-261`), and the status-only exemption from
rate limiting (`:126-130`). This is a new function built from proven parts, not a new integration
built from nothing.

**Stripe-side shape of the new account** (deliberate, and immutable once chosen):

| Parameter | Value | Why |
|---|---|---|
| `type` | **`express`** | Stripe handles verification and all future compliance updates (§2.1); the venue gets a real payout view we do not have to build; the existing `login_links` code already serves it (`create-connect-account/index.ts:310`). `stripe_dashboard.type` is immutable — this is a one-time decision |
| `country` | `US` | Product is US-only. Note this locks the country (§2.5) |
| `business_type` | **`company`** | The org is a legal entity |
| `capabilities` | **`transfers` only** | The money model needs nothing else (§1.7, §2.3). Requesting `card_payments` would make the venue merchant of record, drag in the full merchant KYC + website-verification set, and couple the two capabilities so that either going inactive disables both (§2.3) |
| Prefill | `company[name]` ← `organization.legal_name`; `business_profile[name]` ← `display_name`; `business_profile[product_description]` | Reduces prompts. **Do not** prefill `company.address`, any `Person`, or `external_accounts` — that disables networked onboarding (§2.5) |
| `metadata[org_id]` | the org id | The webhook's fallback join, and the only thing that makes an account self-describing in the Stripe dashboard |
| Idempotency | `connect_org_${org_id}` | Edge spec §3.3 — one account per org, deterministically |
| Account Link | `type=account_onboarding`, `collection_options[fields]=eventually_due` | A venue holds money for a season. Collect once and avoid a mid-season interruption (<https://docs.stripe.com/connect/custom/hosted-onboarding>) |

**API-version note.** `_shared/stripe.ts:34` pins `2024-09-30.acacia`. Stripe steers *new* platforms
to Accounts v2, but Snatch It is an existing v1 platform with live Express accounts, and v1's hosted
onboarding page applies *"only to platforms that already use legacy connected account types"*. Stay on
v1 Express for the org path — same pinned version, same shared helpers, no cross-cutting bump. **Do
not mix v1 and v2 account shapes.** An Accounts-v2 migration is a separate, later decision, and it is
a re-onboarding event because the dashboard type is immutable.

### 3.3 The minimum persisted state

**Principle: Stripe remains authoritative for verification status. Postgres stores only what a
Postgres-side gate must evaluate without a network call, or what a dashboard must render without
one.** Every field below has a named consumer; a field with no consumer is a field that will sit at
its default forever, which is exactly what happened to `profiles.stripe_charges_enabled`
(`create-connect-account/index.ts:269-276`).

All fields live on `kernel.organization` beside the existing ref.

| FIELD | WHY | SOURCE OF TRUTH |
|---|---|---|
| `stripe_connect_account_ref` *(exists, `077:114`)* | The transfer destination; the webhook's join key; the identity of the payee. Already read by `087:445`, `087:506/530/544` | **Snatch It** — it is our pointer. The account it names is Stripe's |
| `connect_transfers_active boolean not null default false` *(new)* | **The product gate (G2/G3/G4).** `transfers === 'active'` is the only capability this money model needs, and the shipped probe already uses it (`_shared/payouts.ts:96-98`). Must be readable inside a `SECURITY DEFINER` RPC, so it cannot be a Stripe round-trip | **Stripe** (`capabilities.transfers`) — mirrored, never authored |
| `connect_payouts_enabled boolean not null default false` *(new)* | Separates "we may transfer to them" from "Stripe will move it to their bank". Drives the dashboard warning that money is arriving and stranded. **Not a sale gate** (§3.5) | **Stripe** (`payouts_enabled`) |
| `connect_requirements_due boolean not null default false` *(new)* | Renders the action-needed banner and the reconnect CTA. A **boolean**, not the array — the array is Stripe's, changes constantly, and has no Postgres consumer | **Stripe** (`requirements.currently_due` non-empty) |
| `connect_disabled_reason text` *(new, nullable)* | The one string that lets finance and support triage without Stripe dashboard access. Closed-ish set (§2.4) | **Stripe** (`requirements.disabled_reason`) |
| `connect_requirements_deadline timestamptz` *(new, nullable)* | Lets the product warn **before** Stripe disables payouts. The difference between a calm operator and an outage | **Stripe** (`requirements.current_deadline`) |
| `connect_state_synced_at timestamptz` *(new, nullable)* | Staleness. A stale row renders "checking…" and triggers a re-read rather than asserting a stale green | **Snatch It** |
| `payout_destination_set_by` *(exists, `077:117`)* | SoD-1 operand — `087:428-430` bars the setter from requesting the payout | **Snatch It** |
| `payout_destination_locked_until` *(exists, `077:115`)* | Post-change cool-down — `085:1643`, `087:444` | **Snatch It** |
| `legal_name` *(exists, `077:107`)* | Our own record of the entity, and the `company[name]` prefill source | **Snatch It** |

**Deliberately NOT stored.** `details_submitted` — it means only that the flow was exited (§1.3), and
`transfers` active is the real gate. `charges_enabled` — the org never takes a direct charge under this
money model. The `requirements` arrays, `errors`, `future_requirements` — no Postgres consumer, and
Express's `requirement_collection = stripe` means Stripe handles future requirements anyway (§2.4).
Any KYC or person data, EIN, `external_account`, bank details, `company` or `individual` hashes — the
platform holds none of it and must not start
(`PHASE_2_MONEY_AUTHORITY_SPEC.md:1212`: *"Snatch It holds no bank details"*), and for a
Stripe-collected account most of it is unreadable after the first Account Link anyway (§2.4).

**Writer.** A new `kernel.sync_org_connect_state(...)` shaped exactly like
`kernel.mark_payout_transfer_state` (`085:1668`) — **`SECURITY DEFINER`, `service_role` EXEC only, no
human path, and none may ever be added.** It cannot be `set_org_connect_ref`, which raises without a
caller JWT (`077:963-967`).

**Monotonicity, explicitly.** `profiles.stripe_onboarding_complete` is deliberately monotonic
(`create-connect-account/index.ts:281-284`) because flipping it false on a transient read would bar an
onboarded seller from listing. **`connect_transfers_active` must be the opposite: it must be able to
return to `false`.** A venue that loses `transfers` must stop selling. This is a real behavioural
difference between the two paths and must be stated in the migration's comment so nobody "fixes" it
into monotonicity later.

**Refresh discipline.** The sync reads the retrieved `Account`, not the webhook's embedded snapshot
(§2.4). Two writers keep it self-healing, mirroring the pattern that repaired the seller path: the
`account.updated` webhook, and any status read from the venue dashboard.

### 3.4 Role matrix

Roles are single-valued with **no inheritance** (`077:150`; dashboard spec `:1007`), so every
authority is named explicitly.

| Action | Authorized | Not authorized | Why |
|---|---|---|---|
| **INITIATE onboarding** — create the Account, mint the first Account Link | `org_owner`, `org_finance` | `org_admin`, `org_marketing`, `org_promoter_manager`, `org_member`, **all venue roles** | Matches the already-built predicate (`077:970-973`) and edge spec `:1778`. Binding the org's money identity is an org money act. `org_admin` runs people and venues, not the bank. **No venue role may ever initiate** — that is the hard constraint: `venue_manager` is a site role held by an employee, and letting it onboard is exactly how venue money ends up on an employee's account |
| **RECONNECT** — a fresh `account_onboarding` Account Link for outstanding requirements; resume an abandoned or expired flow | `org_owner`, `org_finance` | everyone else | The same flow re-entered. It **does not change the destination**, so it must **not** require step-up and must **not** trip the cool-down. Requiring `org_owner` + `aal2` here would leave a venue disabled and accruing money whenever the owner is unreachable — a self-inflicted outage with no fraud benefit |
| **VIEW payout status** — state line, requirements banner, deadline, masked account | `org_owner`, `org_finance` (full, incl. masked ref); **`venue_manager`, `venue_finance` — gate reason only, never the account ref** | `org_member`, `org_admin`, `org_marketing`, `org_promoter_manager`, `venue_box_office`, `venue_marketing`, `venue_promoter_manager`, `venue_scanner` | Full view matches `kernel.list_org_payouts` (`085:1452-1454`) and the frozen column scoping (`077:120-123`; RLS `:654`, `:757`). The venue-role carve-out is a **product requirement, not a widening**: a `venue_manager` who cannot put an event on sale must be told *why*, or the gate is inexplicable and generates a support call. They see one sentence, no `acct_` id, no capability names |
| **REPLACE / re-point the destination** | **`org_owner` ONLY**, `aal2` step-up, grant maturity, dual-control seam, cool-down | **`org_finance` explicitly excluded** | Already built and ratified: `085:1620` (`org_owner` only, SoD-1), `:1623` (maturity), `:1628-1634` (aal2, absent claim = `step_up_unavailable`), `:1643` (cool-down), plus `087:428-430` (the setter may not request the payout). Do not widen. Redirect-then-release is the canonical fraud primitive; **a first bind risks no money, a re-point risks all of it** — which is exactly why `org_finance` may initiate but not replace |
| **DISCONNECT** | **NOBODY** | — | No unbind verb exists in `077` or `085`, and adding one is strictly worse than the alternative. It would strand `kernel.payout` rows in `pending`/`submitted` with no destination while `request_org_payout` refuses with `no_payout_destination` (`087:445-447`), and `set_org_connect_ref` is bind-once by construction (`077:990-993`). The verb an operator actually wants is REPLACE, which exists. To stop an org entirely, `kernel.set_org_status` → `suspended`/`closed` (`077:940`) already blocks binding (`077:981-983`) |

**Should finance and manager differ? Yes, on two distinct axes.**
`org_finance` vs `org_owner` differ on **REPLACE only** — both may initiate, reconnect and view; only
the owner may re-point. That is the SoD-1 line the schema already draws and it is drawn in the right
place. `venue_manager`/`venue_finance` vs the org money roles differ **absolutely**: venue roles get a
read-only *reason*, never the account and never a write. A venue is not a legal entity and its staff
are not its owners.

### 3.5 The gates

**The candidate rule is nearly right. One correction, one addition.**

*Correction.* It says "may not **publish** for sale". `catalog.publish_event` (`081:899`) has **four**
targets — `announced`, `on_sale`, `live`, `completed` (`:920`) — and `announced` is a marketing state
in which the event is public and **nothing is purchasable**. Gating `announced` would stop a venue
announcing a show while its EIN clears verification: it costs the platform nothing and takes away
exactly the promotion window the venue needs. **Gate the `announced → on_sale` transition, not
"publish".**

*Addition.* Event status alone is not a sufficient guard. An event already `on_sale` when Stripe
disables the account must stop selling **immediately**, and its status will not change by itself. The
checkout path needs its own gate.

| # | Gate | Where exactly | Predicate | Failure |
|---|---|---|---|---|
| **G0** | Create org, create venue, create event, create ticket types, configure inventory, transition `draft → announced` | **NO GATE — deliberately** | — | `kernel.create_organization` (`077:767`), `catalog.create_venue` (`078:511`), `catalog.publish_event`→`announced` (`081:899`) and the `081` inventory writers stay untouched. **Requiring Stripe to draft an event is hostile and buys nothing** — nothing can be charged from a draft, and the venue's first hour in the product should be building their show, not filing an EIN |
| **G1** | `announced → on_sale` | **RPC precondition** in `catalog.publish_event` (`081:899`), beside the existing `empty_inventory` check (`:945-953`). `v_org_id` is already in hand at `:924` | org has `stripe_connect_account_ref IS NOT NULL` **AND** `connect_transfers_active` | `precondition_failed: payout_not_ready` |
| **G2** | Checkout / order creation | **RPC precondition** in `venue.create_primary_checkout` (`082:305`), beside the existing `not_on_sale` check (`:377-379`). `v_org_id` is already server-derived from the session's event at `:369-372` | same predicate | `precondition_failed: payout_not_ready`. **This is the gate that actually protects money.** G1 only protects the operator's expectations |
| **G3** | Payment intent creation | `primary-checkout` edge, before minting the PaymentIntent — reading the state via RPC, never re-deriving it | same predicate | 409. Belt-and-braces; the DB gate is authoritative and the edge must not carry its own copy of the rule |
| **G4** | Payout request | **ALREADY EXISTS** — `kernel.request_org_payout` raises `no_payout_destination` (`087:445-447`) | — | Do not duplicate |
| **G5** | Venue dashboard | **Client display only — never the enforcement point** | reads the same state via a read RPC | Disables "Put on sale" **with the reason as its label**. A greyed control with no explanation is the failure mode the dashboard spec explicitly forbids (`:1090`, `:1338`) |

**Flag.** Put G1/G2 behind a `catalog.platform_config` key —
`venue.require_connect_for_on_sale` — read with the same `order by version desc limit 1` idiom the
money code uses (`085:1646-1647`), following the **X-12 restrictive convention: NULL ⇒ gate ON**. This
lets a supervised pilot relax the gate without a migration, and fails closed if the key is missing.

**Why the gate is `transfers`, not `payouts_enabled`.** Under this money model the platform holds the
funds and transfers on settlement (§1.7). `transfers === 'active'` is what makes that transfer legal.
`payouts_enabled` governs only Stripe → the venue's bank. An org with `transfers` active and
`payouts_enabled` false **can still sell and can still be transferred to** — the money simply rests in
their Stripe balance. Blocking ticket sales for that would be over-strict and would take a healthy
event down over a bank-detail problem that harms nobody's ticket. It is a loud dashboard warning and a
notification (§3.6), **not a sale gate**.

### 3.6 Requirements that come due later, and Stripe disabling a live account

Stripe's behaviour is quoted at §2.4: unresolved `currently_due` past `current_deadline` typically
disables **payouts** first, and charges later if the account is unresponsive. The signal is
`account.updated`.

**What the product must do, in order:**

1. **Extend the webhook first.** `stripe-webhook/index.ts:795-858` gains an **org arm**: match
   `kernel.organization.stripe_connect_account_ref = account.id` (falling back to
   `metadata.org_id`), retrieve the Account by id rather than trusting the event snapshot (§2.4),
   and call the service-role-only `kernel.sync_org_connect_state`. **Without this every field in
   §3.3 is dead exactly the way `stripe_charges_enabled` was dead** — and today an org account
   silently matches zero profile rows and ACKs as success (`:850-857`). This is a prerequisite, not
   a follow-up.
2. **Do not stop selling on `currently_due` alone.** Requirements due, a future deadline, and
   `transfers` still `active` means Stripe is still willing to be transferred to. Taking a live
   on-sale event down over a paperwork item is a self-inflicted outage. **Warn loudly, gate nothing.**
3. **Do stop selling the instant `transfers` leaves `active`.** G2 makes this automatic on the next
   checkout attempt — no sweep, no race, no scheduled job.
4. **Do not flip the event out of `on_sale`.** `catalog.publish_event` is forward-only with no
   backward edge (`081:936-943`); an automated system must never consume an operator's one-way state
   machine on a transient Stripe state. The checkout gate is correct precisely because it is
   reversible for free — the account recovers, and sales resume with no operator action.
5. **Money already taken is untouched.** Paid orders settle normally; the settlement payout parks at
   `no_payout_destination` (`087:445`) or `destination_not_ready` (`_shared/payouts.ts:96-98`) and
   waits. `kernel.payout` rows stay `pending`. **No ticket is invalidated and no buyer is affected.**
6. **Notify.** `payout_failed` and `staff_payout_failed` exist (`092:248-250`) and route to org
   finance and owner non-opt-out (dashboard spec `:1210`). But **`092`'s catalog is a closed set and
   contains no event for "your payments account needs attention."** Two must be added:
   `org_connect_requirements_due` and `org_connect_disabled` — both mandatory, push + email, category
   `payout`, routed to `org_owner` + `org_finance`. Without them the venue's first signal is a failed
   payout, which arrives days after the problem started.

**What the venue must see** — operator language only, no internal architecture:

- **Requirements due, sales continuing.** A pinned, non-dismissible banner on dashboard home for
  `org_owner` / `org_finance`: *"Stripe needs a bit more information about your business before
  [date]. Ticket sales continue until then."* One button: **Continue payout setup**, which mints a
  fresh Account Link.
- **Sales blocked.** *"Ticket sales are paused because your payment setup needs attention."* On the
  event page the "Put on sale" control is disabled **with that sentence as its label**, never greyed
  in silence.
- **Money reassurance, always present when blocked.** *"Tickets already sold are unaffected. Money
  already collected is safe and will be paid out once this is resolved."* This is the sentence that
  prevents the support call.
- **Payouts disabled but sales fine.** *"We're still collecting your ticket sales. Stripe has paused
  deposits to your bank until [reason]. Nothing is lost."*
- **Venue staff without an org money role.** *"This venue can't sell tickets right now — the
  organization's payment setup needs attention. Your organization's owner and finance contact have
  been notified."* No account id, no capability names, no mention of transfers, settlement or the
  platform balance.

### 3.7 The onboarding UX, end to end

**Dashboard → Payments → Connect → Stripe → Return → Status.** The venue never needs to understand
Snatch It's payment architecture, and the flow never says *Connect*, *capability*, *transfer*,
*destination charge*, *platform balance*, *settlement*, or `acct_`.

1. **Dashboard.** An org with no payout setup sees **one** card, in the existing "Payout status" zone
   (dashboard spec `:444`): *"Set up payments to start selling tickets."* + **Set up payments**.
   Actionable for `org_owner` / `org_finance`; a read-only status line for venue roles. **Nothing else
   on the dashboard is blocked** — per G0 they can build the entire event first, and should.
2. **Payments section** (`Settings → Payments` — one section, not split across "Connect", "Payouts"
   and "Settlement"). Before setup it holds exactly three things: what happens — *"We collect the
   ticket money and send your share to your bank."*; what's needed — *"Your business details, your
   EIN, and a bank account. About 5–10 minutes."*; and the button.
3. **Connect.** `POST connect-onboarding` with the caller's JWT. The edge function: rate-limits
   fail-closed; reads the org's existing ref; if absent creates the Account per the §3.2 table; binds
   it via `kernel.set_org_connect_ref` **forwarding the caller's Authorization header** (the RPC
   raises on a service-role connection, `077:963-967`); then mints an Account Link with
   `collection_options[fields]=eventually_due` and venue-dashboard return/refresh URLs.
4. **Stripe verification.** A **full-page redirect** in a standalone browser — hosted onboarding is
   *"not supported when embedded through webviews"* and Account Links are single-use, expire in
   minutes, and must never be emailed or stored (§2.2).
5. **Return.** `return_url` is a **venue-dashboard route**, not `snatchitapp.com/payout-return` (which
   deep-links into the mobile profile tab, `app/payout-return.tsx:36`). It **must not claim success** —
   Stripe is explicit that return does not imply completion (§1.3). It renders *"Checking your details
   with Stripe…"*, re-reads org connect state, and resolves to one of three honest outcomes:
   **Ready to sell** · **Stripe is reviewing your details** (`pending_verification` — *"nothing to do
   right now, we'll email you"*) · **More information needed** (with the same Continue button).
   `refresh_url` is a route that immediately mints a fresh Account Link and redirects back into the
   flow — an expired link, a back button, or a messaging client previewing the URL all land here
   (§2.2), and the operator must never see an error for any of them.
6. **Status.** Afterwards the Payments section shows: a green / amber / red state line in operator
   language; the account **masked** (dashboard spec `:1194`); **Manage payouts and bank details** — an
   Express Dashboard **login link** (`POST /v1/accounts/{id}/login_links`, already implemented at
   `create-connect-account/index.ts:310`), **because `type=account_update` Account Links cannot be
   created for accounts with Stripe-hosted Dashboard access** (§2.2); and **Change payout
   destination**, the one place `kernel.set_org_payout_destination` is reachable — `org_owner` only,
   with the consequence stated **before** the change, not after (dashboard spec `:1196-1199`):
   *"Changing your bank details pauses payouts for a safety window. You'll see exactly when they
   resume."* Venue-role viewers see the state line and nothing else.

---

## Prerequisites this ruling creates

| # | Item | Package |
|---|---|---|
| P1 | `connect-onboarding` edge function (spec'd, `EDGE_FUNCTION_SPEC.md:439-462`; never built) | edge |
| P2 | Org arm of the `account.updated` webhook branch + retrieve-by-id | edge |
| P3 | `kernel.sync_org_connect_state` — `SECURITY DEFINER`, `service_role` EXEC only, no human path | new migration |
| P4 | Six additive columns on `kernel.organization` (§3.3) | same migration |
| P5 | G1 precondition in `catalog.publish_event`; G2 in `venue.create_primary_checkout` | `CREATE OR REPLACE`, same migration |
| P6 | `venue.require_connect_for_on_sale` in `catalog.platform_config` (NULL ⇒ restrictive) | same migration |
| P7 | `org_connect_requirements_due` + `org_connect_disabled` notify events | `092` amendment |
| P8 | Contract `kernel.set_org_connect_ref` — closes open defect **G-3** | RPC contracts §20.1.1 |
| P9 | Venue-dashboard routes for return / refresh / payments status | web |
| P10 | Stripe Dashboard: Connect branding (name, colour, icon) — required by hosted onboarding | ops |
