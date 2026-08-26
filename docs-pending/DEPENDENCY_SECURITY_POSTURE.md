# Dependency Security Posture

Status date: 2026-08-25 (branch `repo/deps-security`, base `main` @ f66bf1d).
Toolchain used for all numbers below: node v24.13.1, npm 11.8.0.

## 1. Audit counts (npm audit, committed lockfiles)

| Tree | Scope | Before this PR | After this PR |
|---|---|---|---|
| root (`package.json`) | all deps | 2 critical / 15 high / 12 moderate / 1 low (30) | 0 critical / 9 high / 12 moderate / 0 low (21) |
| root | prod only (`--omit=dev`) | — | 0 critical / 9 high / 11 moderate (20) |
| web (`web/package.json`) | all deps | 0 critical / 6 high (6) | **0 (clean)** |
| web | prod only (`--omit=dev`) | — | **0 (clean)** |

What this PR changed (lockfiles + one manifest line; no source code):

- **web:** `next` 16.2.12 → **16.3.3** (direct prod dep, non-major; pulls fixed
  `postcss` ≥8.5.23 and `sharp` ≥0.35.0), plus `npm audit fix` (no `--force`):
  `brace-expansion`, `js-yaml` 4.3.0→4.3.1, `nanoid` — all transitive,
  lockfile-only. Advisories closed: GHSA-qx2v-qp2m-jg93,
  GHSA-6g55-p6wh-862q, GHSA-fxqj-rqcc-2cmp, GHSA-r28c-9q8g-f849 (postcss),
  GHSA-f88m-g3jw-g9cj (sharp/libvips CVE-2026-33327/-33328/-35590/-35591),
  GHSA-mh99-v99m-4gvg, GHSA-rgw5-rvv9-x895 (brace-expansion),
  GHSA-5p4m-2wfm-xmqj (js-yaml), GHSA-2v37-7h3g-55p8 (nanoid).
- **root:** `npm audit fix` (no `--force`) + in-range `npm update
  brace-expansion` — lockfile-only, `package.json` untouched. Closed both
  criticals (`shell-quote`, `tar`) and the fixable highs: `@xmldom/xmldom`,
  `brace-expansion` (1.1.14→1.1.18), `js-yaml`, `nanoid`, `undici`, `ws`.

Note on root "prod" scope: npm classifies the Expo/Metro toolchain as prod
because `expo` and friends live in `dependencies` (required layout for an Expo
app). Functionally these packages are **build/dev-server tooling** — Metro,
`@expo/cli`, config plugins, `xcode` — and none of their code ships inside the
compiled app binary. The exploitability notes below reflect that.

## 2. Accepted-advisory allowlist

Everything remaining in the root tree is gated behind **expo@57 (semver-major,
forbidden in this PR)** or has no published fix. Each entry: advisory / package
/ why accepted.

| Advisory | Package (installed) | Severity | Why accepted |
|---|---|---|---|
| GHSA-qx2v-qp2m-jg93, GHSA-6g55-p6wh-862q, GHSA-fxqj-rqcc-2cmp, GHSA-r28c-9q8g-f849 | `postcss` ≤8.5.22 via `@expo/metro-config` (expo@54) | high | Fix requires expo@57 major. postcss here runs only at Metro bundle time on developer/CI machines against first-party CSS; the XSS/file-read vectors need attacker-controlled CSS or sourceMappingURL input, which the build does not accept. The **web** tree's postcss (the internet-facing surface) is already fixed via next 16.3.3. |
| GHSA-w3rx-r6r6-pgpr, GHSA-5p2g-fcmc-qvqq | `image-size` via `metro` (expo@54) | high | Fix requires expo@57 major. DoS via crafted ICNS/JXL/HEIF, only reachable when Metro processes a malicious asset checked into the repo — attacker needs commit access first. Build-time only; not shipped in the app. |
| (chain of the two rows above) | `metro`, `metro-config`, `metro-transform-worker`, `@expo/metro`, `@expo/metro-config`, `@expo/cli`, `@expo/config`, `@expo/config-plugins`, `@expo/prebuild-config`, `expo`, `expo-asset`, `expo-constants`, `expo-linking`, `expo-notifications`, `expo-router`, `expo-splash-screen` | high/moderate | Same root causes propagated up the Expo dependency chain; npm counts each hop as a separate finding (16 of the 21 remaining). All resolve together with expo@57. |
| GHSA-w5hq-g745-h8pq | `uuid` <11.1.1 via `xcode` and `@expo/ngrok` | moderate | Missing buffer bounds check in v3/v5/v6 *when a caller passes `buf`* — neither consumer does. `xcode` is prebuild-time tooling (fix via expo@57); `@expo/ngrok` is a dev-only tunnel helper with **no fix available** (`fixAvailable: false`). |

Review cadence: re-run `npm audit` on this allowlist at least monthly and on
every dependency PR; delete rows as expo@57 lands.

## 3. Enforcement recommendation (NOT applied here — workflows owned elsewhere)

`.github/workflows/security.yml` currently runs both audits with `|| true`
(lines 102–107): purely advisory. With web at 0 and root's prod-scope
remainder fully allowlisted above, flip to **blocking on prod-scope
high/critical not in the allowlist**:

```yaml
      - name: Audit — mobile app (root, prod scope, allowlisted)
        # Blocks on high/critical in prod deps EXCEPT the accepted expo@54
        # toolchain chain documented in DEPENDENCY_SECURITY_POSTURE.md.
        # better-npm-audit supports GHSA exclusions; npm audit alone does not.
        run: |
          npx better-npm-audit@3 audit --level high --production \
            --exclude GHSA-qx2v-qp2m-jg93,GHSA-6g55-p6wh-862q,GHSA-fxqj-rqcc-2cmp,GHSA-r28c-9q8g-f849,GHSA-w3rx-r6r6-pgpr,GHSA-5p2g-fcmc-qvqq

      - name: Audit — web (prod scope, blocking)
        working-directory: web
        run: npm audit --omit=dev --audit-level=high
```

Notes for the workflow owner:
- Web needs no allowlist — plain blocking `npm audit` works today.
- If adding a dev dependency to root is undesirable, the fallback is
  `npm audit --omit=dev --audit-level=critical || true` for root plus a
  scheduled issue-creating job, but the better-npm-audit form is preferred:
  it fails on any *new* prod high/critical while tolerating the accepted set.
- Keep the exclusion list in the workflow byte-identical to §2; a PR that
  edits one must edit both.
- Moderates (uuid chain) stay non-blocking at `--level high` by design.

## 4. Backlog: expo@57 upgrade (named item)

**Item:** Upgrade `expo` 54 → 57 (with `expo-router`, `expo-constants`,
`expo-linking`, `expo-notifications`, `expo-splash-screen`, and the RN version
Expo 57 pins).

**Closes:** all 21 remaining root findings except `@expo/ngrok` (dev-only,
no fix published; drops out of prod scope regardless).

**Blast radius:** semver-major across the entire mobile toolchain — new
React Native + Metro versions, config-plugin API changes, prebuild output
drift (`ios/` is checked in), possible Expo SDK API renames in `app/`, `src/`,
`components/`, and new EAS build images. Requires: full typecheck/lint/test,
fresh prebuild diff review, an EAS build, and a TestFlight smoke pass —
its own PR, not combinable with routine dependency bumps. The mobile app is
under App Store review cadence (build 13); schedule the upgrade between
release trains.

## 5. Dependabot overlap (for the integrator)

Branches open at time of writing — **all four are fully superseded by this
PR** and their PRs can be closed once `repo/deps-security` merges:

| Dependabot branch | Bumps | Covered here by |
|---|---|---|
| `dependabot/npm_and_yarn/web/multi-9b209d8bca` | next 16.2.12→16.3.3 (+postcss) | next 16.3.3 bump |
| `dependabot/npm_and_yarn/web/multi-33a90a5774` | next 16.2.12→16.3.3 (+sharp) | next 16.3.3 bump |
| `dependabot/npm_and_yarn/web/multi-5e81c1b34f` | brace-expansion (web, lockfile-only) | web `npm audit fix` |
| `dependabot/npm_and_yarn/web/js-yaml-4.3.1` | js-yaml 4.3.0→4.3.1 (web dev, lockfile-only) | web `npm audit fix` |

## 6. Verification run for this PR (all green)

- root `npm run typecheck` (tsc --noEmit): 0 errors
- root `npm run lint` (expo lint): 0 errors, 44 pre-existing warnings
- root `npm run test` (vitest): 116/116 passed (5 files)
- web `npm ci && npm run build` (next 16.3.3, CI placeholder env): build
  succeeded, all routes emitted
- `npm audit`: web 0 total; root 0 critical / 9 high / 12 moderate, all
  accounted for in §2
