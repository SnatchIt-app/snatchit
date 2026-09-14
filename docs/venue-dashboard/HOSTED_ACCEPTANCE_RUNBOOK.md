# Venue slice 1 — hosted acceptance runbook (automated, refreshed 2026-09-14)

**Execution is governed by [`SANDBOX_WINDOW_MANIFEST_VENUE.md`](SANDBOX_WINDOW_MANIFEST_VENUE.md)** — the venue
part of Claude A's single window manifest (project, pinned commits, the one migration, exact fixture writes, the
one setting change, cleanup, expected before/after state, owner MFA steps, evidence E1–E6). This runbook keeps
the rationale and the local rehearsal. Nothing here has been run against the sandbox except read-only preflights.

| Item | Value |
|---|---|
| Migration under test | `supabase/migrations/20260910120000_venue_api_read_views.sql` (+ rollback), pgTAP `188` — byte-identical to `ae2e2ea` |
| App under test | `venue/read-slice1-fixes` @ `2665a20` (F1–F4 approved by Claude A) — the frozen app fails eight checks |
| Kit | `venue/scripts/acceptance/` on `venue/slice1-acceptance-kit` (pin: the commit carrying the manifest) |
| Target | shared sandbox `ofaidukbieeekqaboscm` only; production ref is refused by the kit |
| Window | **not scheduled** — owner authorizes the specific window; Claude A's phases run first, then venue V0–V10, then any C preview. |

## Readiness

**Local replay (2026-09-14, fresh DB from `release/convergence-135` @ `c55ea50` + this migration):**
141/141 migrations, pgTAP 188 47/47 and 187 20/20, rollback removes the schema, double re-apply is idempotent
and 188 passes again. All 8 views `security_invoker` + `security_barrier`; `anon` has no USAGE.

**Automated kit, local harness (PostgREST exposing `venue_api`, auth stub, same fixture SQL as the sandbox):**

| App build | Result |
|---|---|
| frozen `ae2e2ea` | fails H3, C4-cross-venue, P1 ×3, C6 entry ×3 (below) |
| `venue/read-slice1-fixes` @ `2665a20` (integration build) | **135/135** |

**Defects the kit found in the frozen slice (fixed on `venue/read-slice1-fixes` @ `2665a20`; F1–F4 approved by Claude A 2026-09-14):**

- **F1 — refreshed sessions were never persisted (H3).** There was no Next.js proxy, and Server Components
  cannot write cookies, so a refresh lived for one render only. Hosted Supabase rotates refresh tokens and
  revokes a reused one after its reuse interval: roughly an hour after sign-in a staff member would be signed
  out on their second page load. The local auth stub does not rotate tokens, which is why earlier local
  verification passed. Fix: `src/proxy.ts` + `lib/supabase/proxy.ts` (official `@supabase/ssr` pattern,
  database mode only, no redirects, no authorization decisions).
- **F2 — an event id rendered under another venue's route (C4).** A public Venue B event opened at
  `/o/<A>/v/<A>/events/<B event>` rendered inside Venue A's dashboard. RLS kept drafts hidden, so only
  public catalog data was involved. Fix: `eventInScope` — a mismatch is "not found".
- **F3 — database mode misstated authorization (P1).** A grant-less caller saw "Capabilities come from your
  grants: Venue manager", every database-mode header showed the sample fixture names, and navigation linked
  to fixture ids. Fix: the role label only after verified grants, route ids instead of sample names,
  navigation built from the route scope.

- **F4 — route venue not bound to route org (C6, raised by Claude A).** Grants are matched per venue and per org
  independently, so Org A's owner entered `/o/A/v/<Venue B>` (labelled Org owner) and Venue A's manager entered
  `/o/B/v/A`. **RLS held**: the kit's C6 API checks prove Org A's owner cannot read Venue B's draft, draft session,
  hidden type or presale batch. Fix: entry reads the venue's own org through `venue_api.venues` and denies a
  mismatch.

No SQL, RLS or migration change is involved in F1–F4.

**Two different guarantees, both proven:** *no data* (RLS — the API checks C1–C7 call `venue_api` directly with each
role's token) and *denied entry* (the app — the browser checks prove a caller is not let in wearing a role it does
not hold at that route). C6 showed they can diverge: RLS held 6/6 while entry was open 0/3 before F4.

**C7 — unapproved venue (Claude A's F4 edge).** F4 makes entry depend on reading the venue row, and a *pending*
venue is not covered by the approved-venue policy. Fixtures add pending Venue C in Org A with Venue A's manager
also granted there: the manager reads the row via the own-staff policy and enters; Org A's owner reads it via the
org plane and enters; finance B and the outsider cannot read it and are denied. No over-denial.

**Sandbox, read-only preflight through the kit (2026-09-14 06:55Z): 8/8.** Ledger 130 rows (tip
`20260909000000`; the extra row is the sandbox-only `123`), no `ops`/`venue_api`, venue substrate empty,
flags dark, no fixture-id collisions or acceptance users, `pgcrypto` present, JWKS = **ES256** (so H2
exercises real JWKS verification). Authenticator: `pgrst.db_schemas=public, graphql_public, kernel` and
`pgrst.db_pre_request=public.sandbox_pre_request`. `transfers` FKs now reference `profiles(id)`.

## Two separately authorized steps (Claude A's requirement)

1. **Migration applied** — creates the views; the Data API still cannot reach them.
2. **Schema exposed** — adds `venue_api` to PostgREST `db_schemas`, an authenticator *configuration* change.
   The kit never performs it; it only verifies it. The existing `db_pre_request` hook must survive it.

Fast lever if anything looks wrong mid-run: remove `venue_api` from exposed schemas (closes the client
surface, leaves the views). Full reversal: `cleanup`, then the rollback file and the ledger row delete.

**Scope proof (manifest §4):** `preflight` records 24 out-of-scope table counts (native tickets, wallet passes,
checkout/payments/transfers/bids, refunds/payouts, door/scan, resale policies, profiles) and a
`catalog.platform_config` digest; `postflight` fails unless every one is back to baseline and
`db_pre_request` is unchanged. Cleanup deletes by exact id (the manifest's list), not by pattern.

## Who does what

| Step | Who | Owner time |
|---|---|---|
| Name the window; confirm the app build (fixes branch) | owner | 2 min |
| 0 preflight, 1 apply, 2 verify-apply | Claude D runs the kit; Claude A independently checks ledger count + Gate-2 census immediately before and after | — |
| 3 expose `venue_api` in the Dashboard (Supabase login + MFA) | **owner** | 3 min |
| 4 verify-exposure → 9 postflight | automated (A or D) | — |
| Review 3 evidence screenshots | **owner** | 5 min |
| **Owner total** | | **≈ 10 min** |

Automated wall time ≈ 8 min (browser phases dominate; the sandbox H3 includes a 12 s reuse-interval wait).

## Commands (from a checkout of `venue/slice1-acceptance-kit`, CLI linked; no `db push`, ever)

```bash
export REF=ofaidukbieeekqaboscm
export VENUE_ACCEPT_WINDOW=<window id named by the owner>
K="node venue/scripts/acceptance/accept.mjs --target sandbox --project-ref $REF"

# 0  read-only baseline (re-run at the start of the window; writes .runs/sandbox/baseline.json)
$K --phase preflight
# 1  MUTATION — migration + real-statement ledger row (24 statements) via `supabase db query -f`
$K --phase apply --window $VENUE_ACCEPT_WINDOW
# 2  read-only — 8 views, invoker+barrier, grants, ledger row
$K --phase verify-apply
# 3  OWNER — Dashboard → Integrations → Data API → Exposed schemas → add venue_api only
# 4  read-only — venue_api 404 not 406, catalog/venue still 406, no schema dropped, db_pre_request unchanged
$K --phase verify-exposure
```

Build and serve the app under test against the sandbox (keys are public-class; the anon key never
touches a file; `NEXT_PUBLIC_*` is inlined at build):

```bash
git worktree add ../venue-under-test venue/read-slice1-fixes && cd ../venue-under-test/venue && npm ci
export NEXT_PUBLIC_VENUE_DATA_SOURCE=database NEXT_PUBLIC_ENV_LABEL=sandbox
export NEXT_PUBLIC_SUPABASE_URL=https://$REF.supabase.co
export NEXT_PUBLIC_SUPABASE_ANON_KEY="$(supabase projects api-keys --project-ref $REF -o json | python3 -c 'import sys,json;print(next(k["api_key"] for k in json.load(sys.stdin) if k["name"]=="anon"))')"
npm run build && npm start   # http://localhost:3300
```

```bash
# 5  MUTATION — four synthetic users (Auth admin API, random passwords kept in .runs/sandbox/state.json, 0600)
#    + fixture rows with fixed 5a4d0b0e- ids (incl. Venue B draft/hidden type/presale batch and pending Venue C), one transaction
$K --phase fixtures   --window $VENUE_ACCEPT_WINDOW
# 6  sign-ins + refused write attempts: C1 anon ×8, H4 projection, C2 writes, H5 cross-tenant, C3 outsider, C5 owner,
#    C6 org grant without a venue grant at another org's venue (RLS), C7 pending-venue readability
$K --phase api        --window $VENUE_ACCEPT_WINDOW
# 7  headless browser: H1 login, C4 malformed/foreign ids, H2 tampered token, H3 refresh persisted + 12 s soak,
#    H6 logout, H5/C5 labels, C6 route venue/org binding, C7 pending-venue entry, C3 outsider, H7 concurrency, P1; 3 PNGs
$K --phase browser    --window $VENUE_ACCEPT_WINDOW
# 8  MUTATION — role precedence (adds two scanner grants), then immediate revocation of the manager grant
$K --phase precedence --window $VENUE_ACCEPT_WINDOW
$K --phase revocation --window $VENUE_ACCEPT_WINDOW
# 9  MUTATION — remove exactly the fixture rows and the four users; then compare counts with the baseline
$K --phase cleanup    --window $VENUE_ACCEPT_WINDOW
$K --phase postflight
```

Every phase prints PASS/FAIL per check, exits non-zero on any failure, and writes
`.runs/sandbox/evidence-<phase>-<time>.json`. Screenshots for the owner: `evidence-manager-events.png`,
`evidence-finance-denied-at-A.png`, `evidence-outsider-denied.png`.

## Stop conditions

Any FAIL in `api`, `browser`, `verify-apply` or `verify-exposure`: stop, remove `venue_api` from exposed
schemas, run `cleanup` + `postflight`, report the evidence file. In particular: data without a session, a
draft/hidden type/presale batch returned to finance B or the outsider, `capacity` selectable, a write not
refused, a tampered token accepted, `db_pre_request` changed, or `catalog`/`venue` reachable.

## Local rehearsal (no window needed)

```bash
LOCAL_STACK_SCHEMAS="public, kernel, ops, venue_api" admin/scripts/local-stack.sh start snatchit_rehears_venueapi_rc
# app: venue/.env.local with NEXT_PUBLIC_VENUE_DATA_SOURCE=database, URL http://localhost:3202, harness anon key
node venue/scripts/acceptance/accept.mjs --target local --phase all
```
