# Venue dashboard — slice-1 integration record (2026-09-14)

Local development and verification only. Nothing applied, exposed, seeded or deployed on any hosted project.

## Branches (all based on the frozen `venue/read-adapters-slice-1` @ `700fd46`, code `ae2e2ea`)

| Branch | Head | Content | Checks |
|---|---|---|---|
| `venue/read-slice1-fixes` | `2665a20` | F1 session refresh persisted (proxy), F2 event bound to route venue, F3 truthful database-mode presentation (F1–F3 approved by Claude A), F4 route venue bound to route org | typecheck, lint, vitest 89/89, build |
| `venue/light-theme` | `530d35d` | white-background appearance, AA tokens, token contrast test | typecheck, lint, vitest 86/86, build |
| `venue/slice1-acceptance-kit` | `b3cdfd0` | automated local/sandbox acceptance runner + hosted runbook (no app code) | kit 128 checks |
| `venue/slice1-integration` | this branch | fixes + light theme + kit, merged with `--no-ff` (Shell.tsx auto-merged) | typecheck, lint, vitest 102/102, build, kit 128/128 |

Suggested review order for Claude A: fixes (behaviour, small diff) → light theme (presentation) → kit (tests/docs).
The integration branch is the proof that the three combine; it is not a release branch. `venue/**` is not part
of `release/convergence-135`.

## Kit results on the local replay (`release/convergence-135` @ `c55ea50` + `20260910120000`, PostgREST exposing venue_api)

| App build | preflight | verify-apply | verify-exposure | fixtures | api | browser | precedence | revocation | cleanup | postflight |
|---|---|---|---|---|---|---|---|---|---|---|
| frozen `ae2e2ea` | 5/5 | 5/5 | 3/3 | 2/2 | 36/36 | fails H3, C4 cross-venue, P1 ×3 (and C6 entry ×3 with the extended kit) | ✓ | ✓ | ✓ | ✓ |
| integration (with F4, kit C6) | 5/5 | 5/5 | 3/3 | 2/2 | 42/42 | 47/47 | 4/4 | 4/4 | 5/5 | 11/11 |

## Previews — light appearance, database mode, real sign-ins (`venue/docs/screenshots/light-database/`)

`40-db-signed-out`, `41-db-login` (desktop/mobile), `42-db-manager-events` (desktop/mobile), `43-db-manager-event-setup`,
`44-db-manager-inventory` (desktop/mobile), `45-db-finance-denied-at-venue-A` (desktop/mobile),
`46-db-outsider-no-grant` (desktop/mobile). Synthetic users and fixture rows were removed afterwards
(cleanup 5/5, postflight counts back to baseline).

## Claude A's adjacent case — org grant without a venue grant (kit C6, 2026-09-14)

RLS holds on every build: Org A's owner and Venue A's manager cannot read Venue B's draft, draft session,
hidden type or presale batch (6/6). The app entry did not bind the route venue to the route org, so
`/o/A/v/B` (Org A owner) and `/o/B/v/A` (Venue A manager) passed entry; F4 closes that (3/3 after, 0/3 before).
To be confirmed on the sandbox in the acceptance window.
