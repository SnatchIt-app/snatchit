# Legacy host redirect: snatchitwebapp.vercel.app

Redirect-only deployment package for the retired Expo web export at
https://snatchitwebapp.vercel.app. **Nothing here is deployed.** The owner runs
the single production deploy below. What was checked (audit LEG-01, a read of
the project): `snatchitwebapp` has no Git link, so a merge or push does not
change snatchitwebapp.vercel.app; only that command does. What was not
checked: whether any other Git-linked Vercel project builds from a root
directory that contains `ops/`. Earlier wording here and in the first commit
message said no Vercel project builds from `ops/`; that was never verified
and is withdrawn.

| | |
|---|---|
| Vercel team | `gnvprod-5449s-projects` (`team_rld7LG9DKzgaph97l4H4jl9d`) |
| Vercel project | `snatchitwebapp` (`prj_b8imLCi045a8IwwWK3QJB19hg8lz`), framework Other, no Git link, no env vars |
| Current production | `dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ` (CLI deploy 2026-05-07 from `bd2963e2`, dirty tree), the rollback target |
| Public alias | `snatchitwebapp.vercel.app` only. The two team aliases and the three immutable deployment URLs sit behind Vercel Deployment Protection (302 to `vercel.com/sso-api`) |
| Ruling | `sprint-control/REDIRECT_INVENTORY.md`, decision row "Legacy host redirect": **whole-host 308 that keeps path and query, with no client injected** |
| Audit | sprint 1021, LEG-01 to LEG-03 (STR-05, F-3, owner checklist row 13) |

## Why

- **LEG-01.** The host still serves the May 2026 Expo app (sign-in, sign-up,
  password reset, payout pages) against production Supabase. Its
  `/payout-return` says payout setup is complete unconditionally. Every path
  answers 200.
- **LEG-02.** It prerenders superseded Terms (effective March 20, 2026, with an
  old fee figure) and ships seller and buyer badge strings that the claims
  rules no longer allow. The host is crawlable (no robots meta, `/robots.txt`
  is the SPA fallback page). The old build came from a dirty tree, so it
  cannot be rebuilt and corrected; replacing it is the fix.
- **LEG-03.** The earlier F-3 draft (one `/:path*` rule) has two gaps. Vercel's
  routing-utils compiles `/:path*` to `^(?:/((?:[^/]+?)(?:/(?:[^/]+?))*))?$`,
  which does not match `/` in a plain regex test. And the legacy-only routes
  (`/explore`, `/my-listings`, `/settings/*`, `/bid/:id`, ...) are 404 on the
  app host, so a same-path redirect would land old bookmarks on 404s. This
  package adds an explicit `/` rule and maps every legacy route. It follows A's
  keep-query resolution, not W14's "no query forwarding".

## Files

| File | Purpose | Uploaded |
|---|---|---|
| `vercel.json` | 22 permanent redirects and nothing else (no `trailingSlash`, `cleanUrls`, rewrites or headers) | yes |
| `index.html` | `noindex` fallback with a plain link to https://app.snatchitapp.com/. Never served while the rules match (redirects run before the filesystem); it keeps the static output non-empty | yes |
| `.vercelignore` | keeps everything else out of the upload | no |
| `README.md` | this runbook | no |
| `verify.sh` | live curl matrix, GET only, exit 1 on any mismatch (needs `curl` and `node`) | no |
| `redirects.test.mjs` | offline proof with Vercel's own rule compiler | no |

No `package.json` on purpose: with framework Other and no package.json,
Vercel serves the directory as static files with no install or build step,
the same shape as the current deployment.

## Rules

Evaluated in order; the first match answers. Every rule is `permanent: true`
(308), and **every Location our rules emit is absolute on
`https://app.snatchitapp.com/`**: one rule hop and the visitor is off the
legacy host. Vercel's own slash merge may add one relative hop on the legacy
host first (see the notes). No destination carries a query or fragment, so the
visitor's query string passes through (Vercel: "Query parameters pass through
unless you explicitly replace them in the destination") and nothing such as
`client=` is ever added, except that Vercel's slash merge and the app host's
trailing-slash 308 may re-encode it (semantically equivalent). Observed for
both on 2026-10-21: `+` becomes `%20`; `/`, `:`, `@`, `;`, `,`, `$` and `\`
are percent-encoded; `%41` comes back as `A`; `!'()*~` are left alone. Two
changes are not equivalent, both for degenerate queries only: empty pairs
(`&&`) are dropped, and an empty-key pair `=1` comes back as `1`.

| # | Legacy path | App-host destination | Kind |
|---|---|---|---|
| 1 | `/` | `/` | root |
| 2 | `/home`, `/home/` | `/` | legacy tab |
| 3 | `/explore`, `/explore/` | `/browse` | legacy tab |
| 4 | `/create`, `/create/` | `/sell` | legacy tab |
| 5 | `/bids`, `/bids/` | `/account` | legacy tab |
| 6 | `/profile`, `/profile/` | `/account` | legacy tab |
| 7 | `/my-listings`, `/my-listings/` | `/account/listings` | legacy |
| 8 | `/bid/:id`, `/bid/:id/` | `/listing/:id` | legacy |
| 9 | `/settings/edit-profile`, with or without `/` | `/account/profile` | legacy settings |
| 10 | `/settings/notifications`, with or without `/` | `/account/notifications` | legacy settings |
| 11 | `/settings/payout-setup`, with or without `/` | `/account/settings` (Payouts section) | legacy settings |
| 12 | `/settings`, `/settings/*` (preferences, legal, privacy, support, anything else), with or without `/` | `/account/settings` | legacy settings, default rule |
| 13 to 21 | `/login`, `/signup`, `/reset-password`, `/payout-return`, `/payout-refresh`, `/listing/:id`, `/checkout/:id`, `/transfer/send/:id`, `/transfer/receive/:id` | same path | shared |
| 22 | everything else, `/:path(.*)` | same path | catch-all, last |

Rules 2 to 12 are written with a trailing `{/}?` in `vercel.json` (path-to-regexp
for "one optional slash"; routing-utils compiles `/my-listings{/}?` to
`^/my-listings(?:/)?$`).

Notes:
- Rules 13 to 21 give the same result as the catch-all. They are explicit so
  the Stripe return pages and the shared routes do not depend on the catch-all;
  the test fails if any of them, or `/`, stops being its own rule.
- The catch-all is `/:path(.*)` rather than `/:path*`, so it also takes `/`,
  empty segments and anything else; nothing on the host falls through to the
  filesystem.
- **No `trailingSlash`, on purpose.** `trailingSlash: false` compiles to a
  route `^/(.*)/$` with the *relative* Location `/$1`. That is a risk under
  edge behaviour that is not pinned down, not a demonstrated live open
  redirect. If that route saw `//evil.example/` unmerged, it would answer
  `Location: //evil.example`, which a browser reads as a scheme-relative URL
  and follows to https://evil.example/; if it saw `/\evil.example/` with a raw
  `\`, it would answer `Location: /\evil.example`, which a browser reads the
  same way (so would `%2F`, `%5C` and `%09` forms if the edge matched the
  decoded path). This was shown on a local emulator and in the offline model
  only. The live edge (today's deployment, which has no rules) merges `//` and
  percent-encodes `\` in the merged Location (`//\evil.example` answers
  `/%5Cevil.example`); what a route sees for a raw `\` without `//`
  (`/\evil.example`) was not observed.
  Without `trailingSlash`, every Location our rules emit is absolute on
  `app.snatchitapp.com`; Vercel's own slash merge may add one relative hop on
  the legacy host first. The test resolves every Location with
  `new URL(location, legacy origin)` and fails on any sample path whose final
  host is not the app host; `verify.sh` fails any matrix row whose first
  Location is not absolute on `https://app.snatchitapp.com/`, and any
  hostile-path hop that resolves off both hosts.
- **Trailing slashes now.** A legacy-only URL with one trailing slash is
  mapped directly by its rule (`/my-listings/?x=1` to
  `https://app.snatchitapp.com/account/listings?x=1`, one hop). Every other
  trailing-slash URL falls to the catch-all with the slash kept:
  `/login/` lands on `https://app.snatchitapp.com/login/`, and the app host
  then answers 308 to `/login` (observed 2026-10-21 for `/login/`,
  `/payout-return/?client=app` and `/account/listings/`). The legacy-only rules
  take the slash themselves because the app host would strip it from the
  *legacy* path: `/my-listings/` would end on `/my-listings`, a 404 there
  (observed 2026-10-21, as is `/settings/legal`).
- **The one relative Location left is Vercel's, not ours.** Before any rule,
  Vercel merges repeated slashes with its own 308 and a relative Location.
  Observed on the live legacy host 2026-10-21: `//evil.example/` to
  `/evil.example/`, `/a//b` to `/a/b`, `//\evil.example` to
  `/%5Cevil.example`, `/\//evil.example/` to `/%5C/evil.example/`,
  `//x?next=//evil.example` to `/x?next=%2F%2Fevil.example`. A path holding a
  character outside the RFC 3986 path set (`\`, `|`, `"`, ...) is decoded
  whole, `%2F` included, and percent-encoded again before the merge. That hop
  stays on the legacy host and the next request is answered by the rules above
  with an absolute Location. The test models the edge with and without that
  step, and pins every observation (`LIVE_MERGE`). It stays on the legacy host
  only because the merge writes `\` as `%5C`: a merge that kept it raw would
  answer `//\evil.example` with `/\evil.example`, which a browser follows to
  https://evil.example/ before any rule runs, and no `vercel.json` could change
  that. The test pins this as a counterfactual; `verify.sh` checks the live
  encoding on every run (the `//\evil.example` and `/\//evil.example/` rows).
- Legacy "Your Scene" (`/settings/preferences`) has no web equivalent; it goes
  to `/account/settings`.

## Owner decisions

1. **Who runs the one production deploy.** Default: the owner runs the deploy
   command below (F's session was refused permission; checklist row 13).
2. **`/settings/legal`, `/settings/privacy`, `/settings/support`.** Default
   (this package): they follow rule 12 to `/account/settings`, which asks a
   signed-out visitor to sign in. Alternative: send them to
   https://snatchitapp.com/terms, https://snatchitapp.com/privacy and
   https://snatchitapp.com/support (all answered 200 on 2026-10-21). That
   matches intent better but leaves the app host, so the test's "every
   destination on app.snatchitapp.com" rule and the matrix rows would change
   with it. Decide before the deploy: browsers cache 308s, so a later change
   does not reach visitors who already followed the old one.
3. **Redirect, never delete.** Confirm.

## Prerequisites

Already true per the REDIRECT_INVENTORY final state (2026-10-16): F-1 (the
app-host `/payout-return` and `/payout-refresh` pages) is live and A-1 moved
the Connect secrets to them. The redirect must never go out before both, or
Stripe returns land on a 404. `verify.sh` re-checks that both pages answer 200.

## Pre-flight (read-only)

Run from this directory in a checkout of the merged branch. Put the pins
**inline on each command, never `export` them**: an exported pin would send
the next `vercel deploy` in that shell, for any project, to this one. Never
run any of this from the repo root: the main checkout's root `.vercel/` is
linked to `snatchit-web`.

```sh
cd ops/legacy-snatchitwebapp
ls -A                      # exactly: .vercelignore README.md index.html redirects.test.mjs verify.sh vercel.json
                           # (no .vercel, no package.json)

vercel whoami              # the account that owns gnvprod-5449s-projects

VERCEL_ORG_ID=team_rld7LG9DKzgaph97l4H4jl9d VERCEL_PROJECT_ID=prj_b8imLCi045a8IwwWK3QJB19hg8lz vercel project inspect
#   must print: Found Project gnvprod-5449s-projects/snatchitwebapp
#               ID   prj_b8imLCi045a8IwwWK3QJB19hg8lz
#               Name snatchitwebapp
#   With both pins set the CLI never links or creates a project; a wrong
#   pin fails with "Project not found" and exit 1.

vercel inspect snatchitwebapp.vercel.app --scope gnvprod-5449s-projects
#   must print: id dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ, target production,
#   aliases snatchitwebapp.vercel.app and the two team aliases.
#   Any other id: stop (someone deployed since this package was written,
#   and the rollback target below is wrong).

vercel inspect app.snatchitapp.com --scope gnvprod-5449s-projects
#   note the snatchit-web dpl id; it must be the same after the deploy.

node --test redirects.test.mjs     # all pass
./verify.sh --expect current       # exit 0: legacy app still served, destinations OK, SSO hosts 302
```

Also check, in the dashboard, Project snatchitwebapp, Settings, Security,
Deployment Retention: the rollback target is 167 days old. The audit read a
30-day production retention with 10 deployments kept, and did not check
whether `dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ` survives once it stops being
current. The two older May deployments of this project still answer today,
which suggests the keep-10 floor protects all three, but that is not
confirmed. If the policy would remove it, rollback is only possible for as
long as it exists; losing it only loses the ability to restore the retired
app.

## Deploy (owner only, exactly once)

```sh
cd ops/legacy-snatchitwebapp
test ! -e .vercel && test ! -e package.json && \
VERCEL_ORG_ID=team_rld7LG9DKzgaph97l4H4jl9d VERCEL_PROJECT_ID=prj_b8imLCi045a8IwwWK3QJB19hg8lz vercel deploy --prod
```

Record the deployment id and URL it prints. Do not run `vercel link`, do not
pass `--force`, and do not deploy a second time to "fix" something: on Hobby,
rollback reaches only the immediately previous production deployment, so a
second deploy would make `dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ` unreachable by
`vercel rollback`. To correct the package, roll back first, then deploy once
more.

## Verify (after)

```sh
./verify.sh                        # exit 0: every row 308 to the exact URL, query kept
vercel inspect snatchitwebapp.vercel.app --scope gnvprod-5449s-projects
#   the new id, target production
vercel inspect app.snatchitapp.com --scope gnvprod-5449s-projects
#   the same snatchit-web id as in the pre-flight
```

Then open https://snatchitwebapp.vercel.app/settings/legal and
https://snatchitwebapp.vercel.app/payout-return?client=app in a private window:
each lands on app.snatchitapp.com, the second with `?client=app` kept.

What `verify.sh` checks:
- **Legacy host:** every matrix row, including `/`, query cases (encoded,
  repeated keys, `client=app` kept, nothing added) and trailing slashes: one
  308 whose raw Location is absolute on `https://app.snatchitapp.com/` and
  byte-identical to the expected URL. A first Location that is relative,
  scheme-relative or on any other host fails the row.
- **Hostile paths** (`//evil.example/`, `/%2F%2Fevil.example`,
  `/\evil.example`, `//\evil.example`, `/\//evil.example/` and variants): every
  hop's Location is resolved with the WHATWG URL parser, as a browser does it
  (`\` read as `/`). A hop that resolves anywhere other than the legacy host or
  the app host fails, whatever its raw text; a relative hop is followed only
  while it resolves on the legacy host (Vercel's slash merge). The chain must
  end in a 308 whose Location is written absolute on the app host. With
  `--expect current` the chain must end in a 200 on the legacy host instead.
- **App-host destinations:** each distinct destination answers 200, or a 30x
  to `https://app.snatchitapp.com/login` (sign-in gate). A destination with a
  trailing slash must first get the app host's 308 to the same URL without
  it; that hop is followed and shown. Fake-id and unknown-path rows are only
  reported. The gate answers for any `/account/*` path, page or not, so page
  existence is proven by the test against the web route tree, not by this
  check.
- Every Location, relative or absolute, is resolved with `node`
  (`new URL(location, request URL)`). Matrix rows still compare the raw
  header byte for byte; hostile rows are judged by the resolved origin. The
  earlier `python3` `urljoin` resolver is gone: it reads `\` as a path
  character, so a Location `/\evil.example` stayed on the legacy host for it
  while a browser goes to evil.example.
- **Row guard:** fewer than 30 matrix rows or 4 hostile rows is a failure
  (exit 1), so an emptied or truncated list cannot pass.
- **Deployment protection:** the two team aliases and the three old immutable
  deployment URLs still answer 302 to `vercel.com/sso-api`, so the old app and
  its Terms stay private.

## Rollback

Promote the previous production deployment back to the domain:

```sh
vercel promote dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ --scope gnvprod-5449s-projects
./verify.sh --expect current       # exit 0 again
```

`dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ` is a production-target deployment, so the
CLI re-points the production aliases to it without a rebuild. The
Instant Rollback form is equivalent:
`vercel rollback dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ --scope gnvprod-5449s-projects`.

After a rollback, Vercel may stop assigning the production domain to new
production deployments automatically. If a later corrected deploy does not
show up in `vercel inspect snatchitwebapp.vercel.app --scope gnvprod-5449s-projects`,
promote it by its id with `vercel promote <id> --scope gnvprod-5449s-projects`.

Rollback only restores the retired app for new visitors; see the cache caveat.

## Why redirect and never delete

- Deleting the project is irreversible and frees the name
  `snatchitwebapp.vercel.app`. Whether someone else can then claim it is not
  documented, so treat it as claimable.
- Old URLs still exist: bookmarks and history, Stripe account links issued
  before the 2026-10-16 Connect secret change, the website field of seeded
  test-mode accounts (`scripts/seed-demo.ts`), and stale docs (A-5). After a
  delete they would hit a 404 or a name someone else controls. With the
  redirect they reach the right page on the app host.
- The redirect retires the UI only. The public anon key and publishable key in
  the old bundle stay public in every client; RLS and grants remain the
  boundary.

## Caveat: 308 is cached by browsers

Vercel documents 308 as "Cached by client". A browser that followed a legacy
URL keeps going straight to app.snatchitapp.com even after a rollback (benign:
it lands on the live app). The same applies to a mapping changed later, which
is why owner decision 2 comes before the deploy. Check with `verify.sh` (curl
has no cache) or a fresh private window, not a browser that already visited.

## Evidence limits

- Nothing was deployed. `/` handling and query pass-through at the edge are
  modelled from Vercel's routing-utils and docs, not observed on a live
  deployment; `./verify.sh` after the deploy is the proof.
- `vercel dev` sends a redirect's Location verbatim without the query, so it is
  not a valid check of query pass-through.
- Whether the edge matches rules against the raw or the percent-decoded path,
  whether rules see a raw `\` or the edge's `%5C`, and whether its slash merge
  always runs before the rules, is not pinned down. The test runs every sample
  under every combination; all end on the app host. The slash merge, its `\`
  encoding and its query re-encoding were observed only on today's deployment,
  which has no rules; `verify.sh` re-checks them after the deploy. The model
  differs from it in one observed case: a malformed query escape (`%zz`) came
  back as `zz`, where the model keeps `%25zz`.
- Whether the edge matches case-insensitively is not pinned down; the matrix
  uses lowercase paths and the test checks both ways.
- The legacy route list comes from the old bundle; the app-host page list is
  `web/src/app` at `a111fb06` (live web on 2026-10-21). If the web app drops or
  renames a page, update `APP_ROUTES` in the test and re-run `verify.sh`.
