# DV-ST2b — D's witness record (2026-09-17)

D witnessed this window read-only, under the owner's direct authorization in D's own conversation: "D: go — take the
before and after witness reads for the DV-ST2b window." A executed; C guided the owner; D read.

## What D read

| Read | Time (UTC) | Output md5 |
|---|---|---|
| before | 18:35:23Z | `466fd2d8db214b2a60ea4e779344252f` |
| after | 18:39:55Z | `466fd2d8db214b2a60ea4e779344252f` |

The two files are identical line for line, and identical to the ST2a baseline file: `relacl` =
`postgres=arwdDxtm/postgres,anon=arwdm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres`;
authenticated select/insert/update/delete all true; anon SELECT true; derived column-privilege rows 50 (excluding
postgres); RLS enabled; 3 policies.

**Reconciliation of the one number that looked like a disagreement.** A's capture reported `column_acls=0` and D's read
reported 50. Both are right and they measure different things, checked by D in the same read-only transaction:
`pg_attribute.attacl` non-null = 0 (no per-column ACL — A's restore precondition), `public.bids` has 5 columns, and
`information_schema.column_privileges` has 50 rows for bids excluding postgres because that view expands TABLE-level
grants across columns and grantees.

## The window, as reported by A (D did not observe these)

Revoked 18:36:23Z; restored by A 18:38:56Z; length 2m33s against the owner's six-minute bound; A's verify at 18:39:07Z
matched its capture. The watchdog never fired.

## Classification

**PASS on the server half**, on A's read-only API-log check at 18:49:10Z (sandbox project only): six
`GET /rest/v1/bids` → 403 with `PostgREST; error=42501` as the DV buyer, all between 18:37:12Z and 18:37:48Z, i.e.
inside the window; 200s before the window; no 403 outside it.

**The limitation stands, verbatim and deliberately:** the purchase rows stayed visible on one pull-to-refresh
(observed); whether a message, banner or error state appeared is **NOT CAPTURED**, which is not "none". Half the row is
evidence and half is absent.

**A bound on what the window proved, from the log:** the pre-window 200s carry `content_length: 2` — an empty array —
so the DV buyer has no bids at all and that account's Bids tab is purchases-only. The list therefore survived a failing
bids read because purchases populate it, not because a bids-populated list survived. That is narrower than "the screen
tolerates a bids failure".

**An observation for C, not a defect:** one pull-to-refresh produced six requests over 36 seconds (client retry).

## F-ST2B-1 — the window's own control failed twice (recorded as a defect, not a footnote)

One root cause, three self-invocations in A's script, two of them unreachable because they were invoked by bare name
with no path:
1. the watchdog did not arm for 28 seconds (18:36:23Z–18:36:51Z), so for that period the six-minute bound rested on A
   staying responsive — which is what the watchdog exists not to rely on;
2. the post-restore verify did not run automatically; A ran it explicitly at 18:39:07Z and it passed.

D's position, which A adopted: the second occurrence is the more serious, because a verify that silently does not run
produces a window that *looks* verified. A's explicit run and D's independent after-read are what stand in its place,
and both are named for that reason. The fix is stated as "arming that is not verified is not arming", and D adds "a
verify that did not run is not a verify". A's script now has zero bare self-invocations and checks the watchdog pid
before the window counts as in effect.

## What D's evidence can and cannot support

D read the database before and after. D did not observe the revoke, the restore, the handset, or the API log. What D
can state independently: the grant state before the window and after it are byte-identical, so nothing about bids
access was left changed.
