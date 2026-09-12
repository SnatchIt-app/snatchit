# RED TEAM A — Connect / identity / privacy half of 093

**Target** `snatchit-consol` @ `mobile/profile-rpc-compat` · adversarial review, 2026-09-02
**Method** actual reproduction on a local rehearsal database. No production, no Stripe, no CLI against a remote.
**Database** `snatchit_redteam_a_rehearsal` (the harness refuses any name without `rehears` in it, so the
assigned `snatchit_redteam_a` could not be used verbatim; the assigned name is embedded).
**Impersonation idiom** `tap.login(uuid)` / `tap.login_service()` / `tap.login_anon()` from
`supabase/tests/000_helpers.sql`, plus an `aal2` claim injector and a try/catch wrapper.

Scope as assigned: `connect-onboarding`, the four Connect RPCs (slice 30), the `catalog.update_venue`
freeze and `venue."order"` column scoping (slice 40), the checkout readiness gate and fee resolution,
and the config key rows. **Slice 10 (money) was excluded** and nothing below rests on it.

---

## 0. DISCLOSURE — I MODIFIED ONE REPO FILE BY ACCIDENT. READ THIS FIRST.

While verifying that `supabase/migrations/093_primary_ticketing.sql` matched its reviewed slices, I ran
`scripts/assemble_093.sh`. That script **writes** the assembled file. It is untracked in git, so there
was no committed copy to restore and I could not undo it.

**What changed:** the file went from 2752 lines to 3078. The previous copy was **stale** — it had been
assembled from an older `30_connect_org.sql` and was missing the entire ruling-A5 buyer-fee block. I
confirmed this against the database built from the old file: `venue.create_primary_checkout` had the A8
readiness gate but **no** `fee.buyer_service_bps` reader.

**Two consequences, both needing action by someone other than me:**

1. **This was itself a finding, and it is now masked.** The reviewed artifact and the applied artifact
   had diverged, and nothing in the pipeline caught it. Whatever else is done, `assemble_093.sh` needs
   a CI check that the assembled file is byte-identical to a fresh assembly of the slices.
2. **The regenerated file now contains slice 10's in-progress edits.** Another agent was revising
   `10_money_settlement.sql` while I ran the assembler. Re-run `scripts/assemble_093.sh` once slice 10
   settles, and do not treat the current assembled file as reviewed.

Every finding below was then re-measured on a database rebuilt from the **current** slices, so the
findings themselves are sound. I made no other repo change.

---

## 1. FINDINGS — RANKED

### P0

---

#### RT-A-1 · The attendee roster is fully reconstructable, with names and money attached. Ruling F ITEM 4 is bypassed, not enforced.

**PROVED.** Slice 40 ITEM 4 revokes `buyer_id` from `authenticated` on `venue."order"` to close
"the verified table-grain buyer-identity/display-name join that allows an unaudited attendee roster."
The join was not closed. It moved one table over.

Three facts compose:

1. `venue.inventory_hold.identity_id` is granted to `authenticated` — table-grain SELECT, all ten
   columns, `identity_id` included. Slice 40 never touched it.
2. Its RLS policy `venue_inventory_hold_sel_venue` admits **`org_owner`, `org_admin`, `org_finance`,
   `venue_manager` and `venue_scanner`** to every hold row for their events — the same population
   ITEM 4 was written to blind.
3. `public.profiles` carries `profiles_select_all USING (true)` and grants `display_name`,
   `avatar_url` and `bio` to `authenticated`. Any identity id resolves to a person.

`venue."order"` still exposes `total_minor`, `status`, `created_at`, `source` and `event_session_id`,
so once a hold is tied to an identity the order is tied to it by arithmetic:
`order.total_minor = hold.quantity × ticket_type.price_minor`.

**Reproduction** (as `venue_manager`; identical output as `org_owner`):

```sql
select tap.login('…e6'::uuid);   -- venue_manager on the venue
select p.display_name as attendee_name, p.avatar_url, p.bio,
       o.order_id, o.total_minor as money, o.status, o.created_at, o.source
  from venue.inventory_hold h
  join venue.inventory_batch b on b.batch_id = h.batch_id
  join venue.ticket_type tt    on tt.ticket_type_id = b.ticket_type_id
  join public.profiles p       on p.id = h.identity_id
  join venue."order" o         on o.event_session_id = b.event_session_id
                              and o.total_minor = h.quantity * tt.price_minor;
```

```
 attendee_name  | order_id                             | money | status | created_at        | source
----------------+--------------------------------------+-------+--------+-------------------+--------
 ATTENDEE ALICE | 33333333-0000-0000-0000-00000000000a | 10000 | paid   | 2026-09-02 21:20… | web
 ATTENDEE BOB   | 33333333-0000-0000-0000-00000000000b | 15000 | paid   | 2026-09-02 21:20… | web
```

No audit row, no rate limit, no consent gate — exactly the property ruling F required be removed.
The control immediately above it in the same file did work: a direct `select buyer_id from
venue."order"` returns `permission denied`. The grant was narrowed; the *capability* was not.

`org_marketing` and non-members see zero rows, so the RLS grain is right — the column set is wrong.

**Fix direction.** ITEM 4's own reasoning ("a row-level clause cannot express a per-policy column set,
so the discipline is carried by the GRANT") applies verbatim to `venue.inventory_hold`. Re-grant it
column-scoped without `identity_id`, exactly as 080 did to `kernel.tickets.current_owner_id`. Audit
`venue.scan.actor_identity_id` and `venue.comp_allocation.granted_to_identity` in the same pass; both
are `authenticated`-readable identity columns on venue-scoped tables. Separately, `profiles_select_all
USING (true)` is what turns any leaked identity id into a name, and it is worth its own review.

---

### P1

---

#### RT-A-2 · `venue.order_item` is now unreadable by every authenticated role, including the buyer reading their own order.

**PROVED.** ITEM 4's header asserts:

> THE BUYER'S OWN READ IS UNAFFECTED — VERIFIED, NOT ASSUMED. … A policy USING clause is a POLICY
> EXPRESSION evaluated by the executor; it is outside the column ACL entirely.

That claim is **false as applied**. It holds for `venue."order"` itself — a buyer still reads their own
order row. It fails for `venue.order_item`, whose policy `venue_order_item_sel_owner` reaches across:

```sql
EXISTS (SELECT 1 FROM venue."order" o
         WHERE o.order_id = order_item.order_id AND o.buyer_id = auth.uid())
```

PostgreSQL enforces column privileges inside that subquery for the querying role. With `buyer_id`
revoked, **every** SELECT on `venue.order_item` dies before any row filtering:

```
select tap.login(tap.buyer());
select * from venue.order_item;
ERROR:  permission denied for table order
```

Same error for `venue_manager` and `org_owner` — all three `order_item` policies traverse
`venue."order"`. Mechanism confirmed by re-granting the single column inside a transaction:

```
grant select (buyer_id) on venue."order" to authenticated;   -- buyer_own_items = 1
revoke select (buyer_id) on venue."order" from authenticated; -- permission denied
```

**Impact.** The buyer's order-detail view and the org back office both break. Fail-closed, so not a
leak — but the migration ships a silent functional regression that no test caught, and (see RT-A-1) it
does so while the roster it was written to close stays open.

**Fix direction.** Grant `buyer_id` back and carry the discipline in the policies instead, or rewrite
the three `order_item` policies so they do not reference `buyer_id` (e.g. a `SECURITY DEFINER`
predicate helper).

---

#### RT-A-3 · The cross-plane refusal enumerates two tables instead of proving provenance. An arbitrary `acct_` binds — on both verbs, including the live re-point.

**PROVED.** Ruling A7: *"A caller must never be permitted to supply or bind an arbitrary `acct_`
identifier."* The implemented control refuses ids found in `public.profiles.stripe_connect_id` or
`public.stripe_connect_archive`. Anything else passes on nothing but the regex.

```sql
-- as org_owner, aal2, on an approved/active org
select kernel.set_org_connect_ref('bbbbbbbb-…','acct_PERSONAL1','k');
  → REFUSED: account_not_platform_minted_for_org        (in profiles — control works)
select kernel.set_org_connect_ref('bbbbbbbb-…','acct_ARCHIVED1','k');
  → REFUSED: account_not_platform_minted_for_org        (in archive — control works)
select kernel.set_org_connect_ref('bbbbbbbb-…','acct_ORPHANATTACKER','k');
  → ALLOWED: {"status":"ok","newly_bound":true,"connect_account_id":"acct_ORPHANATTACKER"}
```

The same hole on the **higher-risk** verb, re-pointing an already-live destination:

```sql
-- org had stripe_connect_account_ref = 'acct_LIVEBOUND'
select kernel.set_org_payout_destination('aaaaaaaa-…','acct_ATTACKERPOCKET','x','k');
  → ALLOWED: {"status":"ok"}
-- kernel.organization.stripe_connect_account_ref = 'acct_ATTACKERPOCKET'
```

**Why the edge does not save this.** `connect-onboarding` is written around the right rule ("THE SERVER
MINTS THE ACCOUNT. THE CALLER NEVER NAMES ONE") — but `kernel.set_org_connect_ref` and
`kernel.set_org_payout_destination` are both granted to `authenticated` and reachable through PostgREST
in one call. Every result above was produced as `authenticated`. **The edge's provenance discipline is
advisory; the RPC is the door, and the RPC accepts any well-formed string.** Slice 30's own header says
so ("the edge function mints the account server-side … and everything below exists to make any other
value unusable") — the second half is not achieved.

**A concrete supply of qualifying accounts exists**, and RT-A-4 creates it: the onboarding edge mints
**orphan** connected accounts that are, by construction, in none of the three tables — live on the
platform, controlled by whoever completed the Stripe flow, and invisible to both the refusal and the
per-plane unique index. G-1's premise (a rogue or compromised `org_owner`) plus one orphan is a working
destination-diversion.

**Fix direction.** Provenance must be a positive fact, not the absence of two rows. Either record every
platform-minted org account in a table the binder checks *inclusively*, or have the binder verify
`metadata[snatchit_plane]='organization'` and `metadata[org_id]=p_org_id` out-of-band before it commits.
The edge already writes both.

---

#### RT-A-4 · `connect-onboarding` and its two RPCs do not share a contract. Two independent mismatches.

**PROVED by signature comparison against the built database.**

**(a) `get_org_connect_state` never returns the key the edge reads.** The RPC returns
`status, org_id, org_status, connect_bound, connect_account_last4, connect_transfers_active,
connect_state_synced_at` (verified from `prosrc`). The edge reads:

```ts
const ref = typeof row.connect_account_id === 'string' ? row.connect_account_id : null;
```

`connect_account_id` does not exist, so `accountId` is **always null**. It also reads `row.legal_name`
and `row.display_name`, neither of which the RPC returns. Consequences:

- **Resolve-before-create is dead** — the property the edge's header calls "not an optimisation, it is
  the property that keeps one org to one account."
- **`status_only` reports `not_connected` for a bound, selling organization** (the `!accountId &&
  statusOnly` branch), which is the state that invites an operator to re-onboard.
- Every non-probe call mints. Within Stripe's 24-hour idempotency window the deterministic key
  `connect_org_${orgId}` replays the same account and the bind returns `noop_replay`, so this hides.
  **After 24 hours the key expires**, Stripe mints a *new* account, and the bind fails
  `destination_already_set` → one live orphan connected account per window, by the edge's own
  design ("WE DO NOT DELETE IT AND WE DO NOT REBIND"). Those orphans are RT-A-3's ammunition.
- Accounts are minted with no `company[name]` / `business_profile[name]`.

**(b) `sync_org_connect_state` is called with a signature that does not exist.** The RPC is
`(p_org_id uuid, p_connect_account_ref text, p_transfers_active boolean, p_observed_at timestamptz,
p_command_key text)`. The edge sends `p_org_id, p_connect_account_id, p_transfers_active,
p_payouts_enabled, p_requirements_due, p_disabled_reason, p_requirements_deadline` — seven args, four of
which name columns slice 30 deliberately declined to add. PostgREST resolves by argument name, so this
is a hard `PGRST202`, swallowed by the best-effort `catch`.

**Compound effect.** (b) plus residual R30-2 (no `account.updated` org arm exists) means
`connect_transfers_active` has **no writer at all**. It stays `false` for every organization, and the
A8 gate then refuses every primary checkout — correct and fail-closed, but the primary rail cannot be
activated, and the only mirror-writer that exists today is broken in a way that logs a warning and
returns 200.

---

#### RT-A-5 · `sync_org_connect_state` skips its own G-4 guard when the account ref is omitted, widening the leaked-service-key blast radius onto the org plane.

**PROVED.** The bound-destination guard is conditioned on the ref being supplied:

```sql
if p_connect_account_ref is not null
   and v_org.stripe_connect_account_ref is distinct from p_connect_account_ref then
  raise exception 'conflict_locked: …';
```

Pass `NULL` and it never runs. The org resolves by `p_org_id` and the write proceeds:

```sql
select tap.login_service();
select kernel.sync_org_connect_state('aaaaaaaa-…', null, true, null, 'k');
  → ALLOWED: {"status":"ok","connect_transfers_active":true,"connect_state_synced_at":"2026-09-02T21:24:11…"}
```

Ruling G §2/G-12 records that a leaked `SUPABASE_SERVICE_ROLE_KEY` **cannot** reach the org plane: both
binders raise on `auth.uid() IS NULL` and no kernel table DML grant exists. I re-confirmed both of those
(see §2). But 093 adds a service-role-only verb that writes an org money-gate operand, and it accepts a
subject with no proof about the account. A leaked key can now flip `connect_transfers_active` back to
`true` for any org whose Stripe account Stripe has disabled, re-opening sales to a dead destination —
and can hold `connect_state_synced_at` fresh indefinitely through the unaudited heartbeat branch.

It cannot write the *ref*, so this is capability re-enablement, not destination theft. Still a real
widening of a boundary ruling G asserted was closed.

**Fix direction.** Require `p_connect_account_ref` whenever `p_org_id` resolves an org that already has
a bound ref, and refuse a `true` transition for an org with `stripe_connect_account_ref IS NULL`.

---

#### RT-A-6 · The primary-checkout edge reads `venue."order"` as `service_role`, which holds no grant on it. Every checkout 500s at the org-attribution step.

**PROVED.** `supabase/functions/primary-checkout/index.ts:808-818` builds a `service_role` client and
reads the order back — this is where `org_id` is server-derived (item 6's attribution control):

```ts
const venueService = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { db: { schema: 'venue' } });
const { data: orderRow } = await venueService.from('order')
  .select('order_id, org_id, event_session_id, buyer_id, status, total_minor, currency')
```

Measured:

```
select tap.login_service();
select order_id from venue."order" limit 1;   → REFUSED: permission denied for table order
select buyer_id from venue."order" limit 1;   → REFUSED: permission denied for table order
```

`service_role` holds **zero** table grants across `venue`, `kernel`, `catalog`, `market` and `notify`
(`information_schema.role_table_grants` returns no rows), and `supabase/ci/parity_grants.sql` grants it
only on 27 `public.*` tables. The read-back fails, the edge returns
`{ error: 'Checkout could not be completed. Please try again.' }` 500.

This is 082-era posture rather than something 093 introduced, but it sits directly on the assigned
surface and it is an activation blocker. Note also that the column list requests `buyer_id`, which
slice 40 just revoked — so if the grant is widened to `service_role`, that select must not be the way
it is widened.

---

#### RT-A-7 · The G-2 human tripwire reaches nobody. Reproduced end-to-end.

**PROVED.** Slice 30 adds the missing `notify.emit_event` producers on both binders. `notify.drain_outbox`
has no arm for the event type, so the envelopes are counted `unmapped` and marked done:

```
select kernel.set_org_connect_ref('aaaaaaaa-…','acct_TRIPWIRE','k');   → ok
select event_type, count(*) from notify.outbox group by 1;
  security_payout_destination_changed | 2
select notify.drain_outbox(100);
  {"dead": 0, "done": 2, "deferred": 0, "resolved": 0, "unmapped": 2}
```

`resolved: 0`. This is residual R30-1, self-declared in the slice — recorded here because it is
*reproduced*, and because §5 of slice 30 names this notification as one of the three substitutes for
the dual control that was ruled unbuildable. Two of those three (SoD-1 payout exclusion, destination
probation) are real; this one is currently inert.

---

#### RT-A-8 · The destination cool-down never engages. Reproduced.

**PROVED.** After a successful re-point, `payout_destination_locked_until` is `NULL`:

```
 stripe_connect_account_ref | payout_destination_locked_until
----------------------------+---------------------------------
 acct_ATTACKERPOCKET        |                                 (null)
```

`payout.destination_cooldown_hours` is seeded null and §5 writes `NULL` rather than a restrictive
fallback. G-5, acknowledged and ruled out of 093 as configuration — confirmed live because it is a
launch precondition, and because it is what lets RT-A-3 be repeated at will to defeat reconciliation.

---

### P2

- **RT-A-9 · Case-variant binding.** `acct_personal1` binds while `acct_PERSONAL1` sits in `profiles`;
  `acct_orphanattacker` binds to org A while `acct_ORPHANATTACKER` is bound to org B. Both the refusal
  and the partial unique index are case-sensitive `text` comparisons. Stripe ids *are* case-sensitive,
  so no money moves — but this consumes the **bind-once** slot with an unreachable id (the org can then
  only recover through `set_org_payout_destination`, behind maturity + step-up), and it defeats any
  case-insensitive reconciliation of "one account per org."
- **RT-A-10 · `set_org_payout_destination` leaks a raw 23505.** `duplicate key value violates unique
  constraint "organization_connect_ref_key"` instead of `conflict_locked`. G-4a, ruled cosmetic. It is
  also a working oracle for whether a guessed `acct_` is bound to some organization.
- **RT-A-11 · The C16 short-circuit ignores session and items.** Keyed on `(buyer_id, command_key)`
  only. `create_primary_checkout('00000000-…-0000', '[]'::jsonb, '{}', <own prior key>)` returns the
  prior order. Own orders only, and the edge catches the mismatch — recorded because the arguments are
  not validated at all before the short-circuit returns.
- **RT-A-12 · `venue_scanner` is one grant away from RT-A-1.** `venue_inventory_hold_sel_venue` names
  `venue_scanner` explicitly. It currently returns zero rows only because the policy's join key comes
  from a nested read of `venue.inventory_batch`, which the scanner cannot see, so `has_event_role(NULL)`
  is false. Grant a scanner any `inventory_batch` visibility — a plausible door-ops change — and the
  full roster opens. The safety here is accidental, not designed.
- **RT-A-13 · No G-11 audit trigger.** `kernel.organization` carries one non-internal trigger,
  `tg_organization_updated_at`. A superuser `UPDATE` of `stripe_connect_account_ref` still writes no
  `admin_audit` row. Recommended by ruling G, not built.

---

## 2. WHAT I TRIED THAT HELD

Each of these was executed, not reasoned about.

**Binding / cross-plane (item 1, 2).** Personal `acct_` live in `public.profiles` — refused on both
verbs. `acct_` in `public.stripe_connect_archive` — refused on both verbs. Cross-org reuse of an
exact id — refused (`conflict_locked` on the bind; the unique index on the re-point). Whitespace and
non-ASCII variants — rejected by `^acct_[A-Za-z0-9]+$`. No TOCTOU: the individual plane's writer mints
ids rather than accepting them, so no value can be moved into `profiles` after a bind clears the check.

**Role escalation (item 3).** On `set_org_connect_ref` *and* `set_org_payout_destination`:
`org_finance`, `org_admin`, `org_marketing`, `venue_manager` and a non-member were all refused 42501.
The `org_admin` → invite → `org_finance` path (077:1040-1042) buys nothing now that both verbs are
`org_owner`-only; roles are single-valued with no inheritance, so the narrowing is real. `org_admin`
is also refused by `get_org_connect_state`; `org_finance` is admitted, by design, and gets only the
masked last-4.

**Step-up (item 3).** An `org_owner` session with no `aal` claim: `step_up_unavailable`. Fail-closed
on the absent claim, as specified.

**Stale onboarding (item 4).** Owner demoted mid-flow, then completing the bind — refused (`has_org_role`
is a live read). Bind against a `suspended` org — refused. Re-point against a `suspended` org — refused
(the new G-6 gate; this one really is closed). Bind against an `applied`, pre-review org — refused.

**Callback replay (item 5).** No reproduction possible and none needed: `connect-onboarding` takes
`{org_id, status_only, command_key}` only, rejects any other key with a 400, refuses caller-supplied
`return_url`/`refresh_url`, pins both to an allow-listed host, and `isSafeRedirect` forbids any query
or fragment — so no state is URL-borne to replay. `status_only` performs no write. The submitted
`command_key` is discarded and re-derived from the org id. This part is well built.

**Organization tampering (item 6).** `catalog.create_event` derives `org_id` from `catalog.venue.org_id`
server-side; a caller cannot attribute an event to another org. `venue.create_primary_checkout` derives
`v_org_id` from the session's event. The A8 gate refused both ways round: no `stripe_connect_account_ref`
→ `payout_not_ready`; ref present but `connect_transfers_active=false` → `payout_not_ready`. The C16
short-circuit does precede the gate (deliberately), but it can only return an order the caller already
owns, so it is not an attribution bypass.

**Price tampering (item 7).** The fee gate fails closed as specified: with the key seeded null,
`service_fee_unset`. With `1000` bps, `{"total_minor":10000,"buyer_fee_minor":1000,"charge_total_minor":11000}`
— face value never contaminated. `fee.buyer_service_bps` is unreadable by a buyer (restricted RLS
returns 0 rows) and unreachable by `service_role` (no `catalog` USAGE), so the rate cannot be learned
client-side. The `idempotency_replay` return does drop the fee fields, but the edge handles it
correctly — it recovers the original quote from the PaymentIntent and returns `quote_unavailable`
rather than inventing one. **I could not make the server quote a price it did not compute.**

**Operatorship transfer (item 8).** Refused through `catalog.update_venue` as `org_owner`; benign
profile edits still work, so the freeze is surgical as intended. A case-variant patch key (`ORG_ID`)
hits `unwritable_key`, not the update. Direct `UPDATE catalog.venue` / `catalog.event` as
`authenticated` and as `service_role` — `permission denied`. `service_role` cannot even call
`update_venue` (no `catalog` USAGE). One non-internal trigger on `catalog.venue`
(`tg_venue_set_updated_at`), no transfer path. `venue_org_id_fkey` is `ON DELETE RESTRICT` /
`ON UPDATE NO ACTION` — no cascade re-points it. No other RPC writes `catalog.venue.org_id`.

**Scanner PII (item 10).** `venue_scanner` reached zero rows on `venue.inventory_hold`,
`venue."order"`, `venue.inventory_batch`, `kernel.tickets`, `venue.scan` and `venue.comp_allocation`,
and is refused on `profiles.full_name`, `profiles.phone_number` and `auth.users.email`. No attendee
name, email, phone or buyer id is reachable by a scanner. (See RT-A-12 for how narrow the margin is.)

**Direct SQL / service-role (item 11).** `authenticated` cannot call `sync_org_connect_state`, cannot
`UPDATE kernel.organization`, and cannot `SELECT stripe_connect_account_ref`. `service_role` cannot call
`set_org_connect_ref` or `get_org_connect_state` (no grant), cannot `UPDATE kernel.organization`, and
holds `USAGE`-only on `kernel` with no table grant. `anon` has no `kernel` USAGE at all. The one thing
`service_role` *can* now do is RT-A-5.

**Config tampering (item 12).** Direct `INSERT` of a higher-version row as `authenticated`, `anon` and
`service_role` — all refused (`permission denied for table platform_config`; `service_role` cannot even
reach the schema). `UPDATE` of an existing row — refused. `catalog.set_platform_config` as a non-platform
caller — `insufficient_privilege: platform_admin required`. A buyer cannot read a `restricted` row.
The highest-version-wins read is real but only reachable by `platform_admin`, so it is not a shadowing
primitive for anyone else.

---

## 3. READINESS

**One P0 stands: RT-A-1.** Ruling F's attendee-privacy requirement is not met — the roster is
reconstructable with names and money by every org and venue-manager role the ruling was written to
blind, and the migration's own control (`venue."order"` column scoping) is bypassed rather than broken.
By the stated rule, that stops readiness.

Beyond it, the primary rail cannot be activated as it stands: `connect_transfers_active` has no working
writer (RT-A-4), the checkout edge's order read-back has no grant (RT-A-6), and `venue.order_item` is
unreadable by anyone (RT-A-2). All three fail closed, so nothing is *unsafe* — but nothing works either.

The authorization core is genuinely strong. Every role, status, step-up and staleness gate I attacked
held, on both binders, without exception. The failures are all in the seams: what the refusal *enumerates*
rather than *proves* (RT-A-3), what the edge and the RPC each *assume* the other returns (RT-A-4), and
which table the privacy grant *did not* cover (RT-A-1).
