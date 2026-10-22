# 176 readers: everything that reads `venue.ticket_type` or `venue.inventory_batch`

Migration `20261022000000_venue_public_arms_require_published_event.sql` (registry 176, pgTAP 246)
narrows two RLS policies. A narrowed policy can break a reader that the diff never shows, so this is
the list of every reader we could find, on every ref that matters, with three facts for each one:
the role it runs as, whether it can read a draft event's rows today, and whether 176 changes that.

**Short answer:** 176 changes what signed-in callers read directly from the two tables, or through
the `venue_api` views. Callers with no grant on the event lose a draft event's public types and
batches. Four staff roles lose a draft event's batches, but not its types. Nothing else changes. All
20 SQL functions that read the tables are `SECURITY DEFINER` and bypass RLS, so 176 does not affect
them. No client, edge function or pgTAP suite on any ref reads a draft event's public type or batch
as a caller that loses access.

## 1. Method

Read-only, on the local clone. `git ls-remote --heads origin` (290 heads) matched every local
tracking ref, so the refs below were current when this was written.

| Ref | Commit | Why it is here |
|---|---|---|
| base `origin/venue/api-read-views-provisional` | `8ccb26e1` | 176's base (the fix/154 chain plus 159) |
| `origin/fix/154-listing-visibility-20261015` | `bfc5cf97` | the chain through `20261015000200` |
| `origin/release/production-gate-20260918` | `6f982f36` | the release gate |
| `origin/feature/web-accounts-foundation` | `a111fb06` | web |
| `e46fc203` (= `origin/next/build30-integration`) | `e46fc203` | C's mobile base |
| `origin/next/build30-candidate` | `b5884efa` | C's newest mobile head |
| `origin/venue/production-readiness` (#122) | `b7a80c15` | D: venue app, acceptance kit |
| `origin/venue/dashboard-v2` | `ee1d90b7` | D: venue app source |
| D's open PR heads #120 `docs/dashboards-hosting-package`, #121 `admin/console-v2-integration`, #124 `admin/manual-refund-sop`, #129–#133 `feature/d-*`, #134 `admin/console-relist-expected` | `e1ea850b` `fec26b41` `3394cd7d` `bdb8d589`/`d4f10b6f`/`19ff62ee`/`f1d5164b`/`a0ad5bde` `6588a857` | D's open work |
| `origin/feature/venue-native-and-product-v2` (#52) | `9aed686c` | 093 primary ticketing |
| A's heads 157, 158, 170, 171, 172 and the registry | `07009ded` `f5abd471` `5ea55a0f` `b84c8e05` `5e31e62f` `14f3e8ec` | migrations ordered around 176 |
| `origin/main` | `eadd456a` | does not carry 076–102 at all (89 older files) |

No branch for D's Party Pass feature PRs had been pushed yet. Those PRs are covered by the contract
in §6, not by this list. A's 173–175 were not pushed either. Their registry descriptions touch only
`public`.

Searches:
1. `git grep -P '\bticket_types?\b|\binventory_batch(es)?\b'` on each ref, excluding `*.md` and `docs/`.
   Control: the base must return `081_venue_inventory.sql` (it does). A first attempt used `git grep -E`
   with `\b`, which that grep does not support, and returned zero on every ref. The zero was a broken
   search, not a clean result.
2. Every hit was then classified by hand. Most hits outside `supabase/` and `venue/` are
   `public.listings.ticket_type`, the resale listing's `GA/VIP/TABLE` column. It shares the name and
   is unrelated.
3. A script walked each ref's migrations in replay order. For every function whose **last**
   definition reads either table, it recorded `SECURITY DEFINER` or invoker, and it recorded every
   view and every policy that reads either table. The base, the release gate and `e46fc203` produce
   the same list. The venue branches lack only `public.get_my_tickets`, and carry the old
   `20260910120000` copy of the views.
4. The blobs of the 15 reader migrations (`076`–`102`, `116`, `20260909000000`) are identical on
   every ref that carries them, so one reading covers all refs.

## 2. Policies (RLS: runs as the caller)

| Policy | Reads | Today, on a draft event | After 176 |
|---|---|---|---|
| `venue_ticket_type_sel_public` (081) | `visibility = 'public'` | every authenticated caller reads the public type | **changed:** also requires `catalog.event.status <> 'draft'` |
| `venue_inventory_batch_sel_public` (081) | `venue.ticket_type` (caller's RLS) | every authenticated caller reads the public type's batch | **changed:** also requires the type's event to be non-draft |
| `venue_ticket_type_sel_venue` (081) | 080 definer helpers | org_owner, org_admin and venue_manager read all types; org_finance, org_member and the five lower venue labels read non-hidden types | unchanged (pgTAP 246 P3 pins the text) |
| `venue_inventory_batch_sel_venue` (081) | `venue.ticket_type` (caller's RLS) + helpers | org_owner, org_admin, org_finance, venue_manager, venue_finance and venue_scanner | unchanged (P4). The types it resolves through are visible to all six roles through `_sel_venue`, so the narrower public arm never was their only path |
| `venue_inventory_hold_sel_venue` (081) | `venue.inventory_batch` (caller's RLS) | org_owner, org_admin, org_finance, venue_manager and venue_scanner | unchanged. Its roles are a subset of the batch arm's, so the batch rows it resolves through stay visible |
| `catalog_event_sel_anon` / `_sel_org` (078), `catalog_event_sel_venue` (080) | the new subqueries' target | none of them reads either venue table | no cycle (42P17 impossible): they call only `has_org_role`, `is_platform` and `has_venue_role` (definers) |

`anon` cannot read either table today or after 176. Schema `venue` grants USAGE to `authenticated`
only (076, 081 E-30), and both policies stay `TO authenticated`.

## 3. Views (`security_invoker`: run as the caller)

| View | Ref | Today | After 176 |
|---|---|---|---|
| `venue_api.ticket_types` | base (`20261021120000`); D's branches (`20260910120000`, same SQL) | equals the base table under the caller's RLS, so the draft leak is here too | **changed, intended:** the draft row disappears exactly as in the table. 246 B11 and V1–V4 check this |
| `venue_api.inventory_batches` | same | same | same (B12) |

No other view on any ref reads either table.

## 4. SQL functions (all `SECURITY DEFINER`: unaffected)

Each function runs as its owner, the migration role `postgres`, which owns both tables. Neither table
has `FORCE ROW LEVEL SECURITY` (246 A7), so every function below reads every row, drafts included,
both today and after 176. Any status gate is the function's own code, and 176 does not touch it.

| Function | Last definition | Reads |
|---|---|---|
| `venue.create_ticket_type` | 081 | ticket_type |
| `venue.set_ticket_type_price` | 081 | ticket_type |
| `venue.create_inventory_batch` | 081 | ticket_type, inventory_batch |
| `venue.set_batch_capacity` | 081 | ticket_type, inventory_batch |
| `venue.reserve_primary_inventory` | 081 | ticket_type, inventory_batch |
| `venue.create_inventory_hold` | 081 | ticket_type, inventory_batch |
| `venue.release_inventory_hold` | 081 | ticket_type, inventory_batch |
| `venue.finalize_primary_order` | 085 | inventory_batch |
| `kernel.void_ticket_atom` | 085 | inventory_batch |
| `venue.issue_comp` | 086 | inventory_batch |
| `catalog.cancel_event` | 088 | inventory_batch |
| `market.create_listing` | 088 | ticket_type |
| `market.create_p2p_transfer` | 088 | ticket_type |
| `market.make_offer` | 088 | ticket_type |
| `venue.list_my_attributions` | 090 | ticket_type |
| `venue.list_promoter_attributions` | 090 | ticket_type |
| `kernel.issue_ticket_atoms` | 093 | inventory_batch |
| `venue.create_primary_checkout` | 093 | ticket_type, inventory_batch |
| `catalog.publish_event` | 102 | ticket_type, inventory_batch |
| `public.get_my_tickets` | 20260909000000 | ticket_type |

No `SECURITY INVOKER` function reads either table, and no `ops.*` console function does either.
`087` mentions `ticket_type` only as an export filter key, and `116` and `20261021130000` mean
`public.listings.ticket_type`.

## 5. Clients, edge functions, scripts and tests

| Reader | Where | Runs as | Today, on a draft event | After 176 |
|---|---|---|---|---|
| `listTicketTypes`, `sessionAvailability` in `src/lib/venue/client.ts` (mobile) | base, `e46fc203`, `next/build30-candidate`, #121, #122 | signed-in buyer, through `.schema('venue')` | cannot run: `venue` is not an exposed schema (last read: `public, graphql_public, kernel, ops`), and no screen calls either function on any ref | if ever wired: a buyer sees non-draft events only, which is what a buyer flow needs |
| `dbListTicketTypes`, `dbListBatches` in `venue/src/lib/db/adapters.ts` (venue app) | #122 `b7a80c15`, `dashboard-v2` | signed-in staff, through `venue_api` | per the role table in §7 | **one visible change:** an `org_member` can open a draft (078 `catalog_event_sel_org`) and still sees its types, but the batch list is now empty. The other roles that lose draft batches cannot open a draft event at all (`dbGetEvent` returns nothing for them), so nothing changes on their screen |
| `venue/src/lib/data.ts` preview fixtures | same | in-memory, no database | n/a | unaffected. The preview may now show an `org_member` more than DB mode does, which D may want to align |
| Acceptance kit `accept.mjs`, `sql/fixtures.sql.tmpl`, `sql/preflight.sql`, `sql/cleanup.sql` | #122 | the anon key with synthetic users; `postgres` for fixtures and read-backs | no ticket type sits on a draft event in the fixtures | every existing check is unaffected. Optional for D: add an outsider check that a draft's public type is absent |
| `venue/scripts/rehearsal-fixtures.sql` | #122 | postgres | no draft-event types | unaffected |
| `supabase/functions/primary-checkout` | base and later | the caller's JWT, calling the definer `venue.create_primary_checkout`; service_role for `payments` | definer | unaffected |
| `web/` and `admin/` | every ref | — | they never read `venue`, `venue_api` or `catalog`. Their `ticket_type` hits are `public.listings` | unaffected |
| pgTAP `145` (H1, H2, H7b, H10, A20) | every ref with 081 | fan / staff | the fan reads happen after the event is `on_sale` (F5/F6), and `A20` checks names only | unaffected (names kept) |
| pgTAP `226` (base) / `188` (D's branches) | | callers C1–C30 | no ticket type sits on the draft `e2` | unaffected |
| pgTAP `147`, `148`, `149`, `153` | every ref with 081 | `postgres` (they read `sold`/`held`, which no client role is granted) | owner | unaffected |

## 6. Contract for D's Party Pass PRs (and any new reader)

- A signed-in fan, or any caller without a grant on the event, reads a ticket type or batch only when
  it is `public` **and** its event is not `draft`. The test is `status <> 'draft'`, never
  `>= 'announced'`.
- A staff preview of a draft gets its rows through the unchanged `_sel_venue` arms. venue_manager,
  org_owner and org_admin see everything. org_finance, venue_finance and venue_scanner see non-hidden
  types and their batches. org_member, venue_box_office, venue_marketing and venue_promoter_manager
  see non-hidden types but no batches until publish. A screen that shows a draft's availability to
  those four roles must say that availability appears after publish. It must not read an empty list
  as "sold out".
- A new reader that needs draft rows for other roles needs a new staff arm or a definer read-model
  RPC, reviewed by A. It must not widen the public arm.

## 7. Role table (a draft event's public type T and its batch B; non-draft events unchanged)

| Caller | T today → after | B today → after |
|---|---|---|
| anon | no → no (schema wall) | no → no |
| signed-in with no grant on the event (fan, staff of another venue, org_marketing, org_promoter_manager, platform labels) | **yes → no** | **yes → no** |
| org_owner, org_admin (own org), venue_manager | yes → yes | yes → yes |
| org_finance, venue_finance, venue_scanner | yes → yes | yes → yes |
| org_member | yes → yes | **yes → no** |
| venue_box_office, venue_marketing, venue_promoter_manager | yes → yes | **yes → no** |

## 8. Found while reading: pre-existing, NOT changed by 176 (for A)

1. **Hidden-type batches are invisible to org_finance, venue_finance and venue_scanner.** The batch
   staff arm resolves the event through a `venue.ticket_type` read under the caller's RLS, and those
   roles cannot read hidden types. RLS §9.2 gives venue_finance and org_finance `A(full)`. 246 E6 pins
   the current behaviour.
2. **The lower venue labels read a draft's non-hidden types.** venue_finance, venue_box_office,
   venue_marketing, venue_promoter_manager and venue_scanner do, through `venue_ticket_type_sel_venue`,
   although none of them can read the draft event itself (080 `catalog_event_sel_venue`,
   T-RLS-CAT-01). 176 keeps that arm unchanged, as instructed.
3. **No platform arm.** RLS §9.1 and §9.2 give the platform labels `A(all)` or `A(full)`, but 081
   carries no platform arm on either table. The console reads through `ops.*` definers, so nothing
   breaks.
