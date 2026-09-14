# Venue dashboard — slice-1 integration record (2026-09-14)

Local development and verification only. Nothing applied, exposed, seeded or deployed on any hosted project.

## Branches (all based on the frozen `venue/read-adapters-slice-1` @ `700fd46`, code `ae2e2ea`)

| Branch | Head | Content | Checks |
|---|---|---|---|
| `venue/read-slice1-fixes` | `ebd01eb` | F1 session refresh persisted (proxy), F2 event bound to route venue, F3 truthful database-mode presentation | typecheck, lint, vitest 84/84, build |
| `venue/light-theme` | `530d35d` | white-background appearance, AA tokens, token contrast test | typecheck, lint, vitest 86/86, build |
| `venue/slice1-acceptance-kit` | `610f34d` | automated local/sandbox acceptance runner + hosted runbook (no app code) | kit 119 checks |
| `venue/slice1-integration` | this branch | fixes + light theme + kit, merged with `--no-ff` (Shell.tsx auto-merged) | typecheck, lint, vitest 97/97, build, kit 119/119 |

Suggested review order for Claude A: fixes (behaviour, small diff) → light theme (presentation) → kit (tests/docs).
The integration branch is the proof that the three combine; it is not a release branch. `venue/**` is not part
of `release/convergence-135`.

## Kit results on the local replay (`release/convergence-135` @ `c55ea50` + `20260910120000`, PostgREST exposing venue_api)

| App build | preflight | verify-apply | verify-exposure | fixtures | api | browser | precedence | revocation | cleanup | postflight |
|---|---|---|---|---|---|---|---|---|---|---|
| frozen `ae2e2ea` | 5/5 | 5/5 | 3/3 | 2/2 | 36/36 | fails H3, C4 cross-venue, P1 ×3 | ✓ | ✓ | ✓ | ✓ |
| integration | 5/5 | 5/5 | 3/3 | 2/2 | 36/36 | 44/44 | 4/4 | 4/4 | 5/5 | 11/11 |

## Previews — light appearance, database mode, real sign-ins (`venue/docs/screenshots/light-database/`)

`40-db-signed-out`, `41-db-login` (desktop/mobile), `42-db-manager-events` (desktop/mobile), `43-db-manager-event-setup`,
`44-db-manager-inventory` (desktop/mobile), `45-db-finance-denied-at-venue-A` (desktop/mobile),
`46-db-outsider-no-grant` (desktop/mobile). Synthetic users and fixture rows were removed afterwards
(cleanup 5/5, postflight counts back to baseline).
