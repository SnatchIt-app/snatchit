# Shared packages (`@snatchit/*`)

Light shared packages proving code reuse between the mobile app and the web
app, per the Web Platform Architecture Report (Phase 0). **The mobile app is
untouched**: these are *copies*, not moves — mobile `src/` remains the source
of truth until the post-App-Review monorepo migration, and parity test suites
fail if the copies ever drift from the originals.

| Package | Contents | Consumed by |
|---|---|---|
| `@snatchit/types` | Domain types (`Listing`, `Profile`, `Bid`, …) — copy of `src/types/index.ts` | web (and mobile later) |
| `@snatchit/core` | Money/fee math, `finalSoldPrice`, marketplace constants, categories/neighborhoods, ticket-platform transfer instructions | web |
| `@snatchit/design-tokens` | Brand tokens (colors/spacing/radius/type/shadows) as TS + generated `tokens.css` custom properties | web |

## Workspace mechanics (deliberately boring)

The repo root is the Expo app on **npm + package-lock.json** (EAS builds run
`npm ci` against it). To guarantee zero mobile dependency-resolution changes
during App Review, there is **no pnpm/turborepo workspace yet**:

- `web/` is a self-contained npm project that consumes these packages via
  `file:` dependencies (npm installs them as symlinks).
- Packages are TypeScript-source-only (no build step); the web app compiles
  them via Next.js `transpilePackages`.
- Cross-package imports are **type-only** (`import type { … } from
  '@snatchit/types'`), so they are erased at build time.

The pnpm + Turborepo monorepo (`apps/mobile` + `apps/web`) is deferred until
the current Apple review cycle concludes, exactly as the architecture report
sequences it.

## Running the parity tests

From `web/` (which carries the vitest devDependency):

```
npm run test:packages
```

(equivalent to `vitest run -c ../packages/vitest.config.ts`)

Regenerate CSS variables after a token change:

```
cd packages/design-tokens && npm run generate
```
