/**
 * Vitest config for the shared packages' parity tests.
 *
 * Run from web/ (which carries the vitest devDependency):
 *   npm run test:packages        →  vitest run -c ../packages/vitest.config.ts
 *
 * The parity suites import BOTH the package copies and the original mobile /
 * edge-function implementations, asserting identical outputs. Aliases below
 * resolve the three worlds without touching the mobile app's configuration.
 */
import path from 'node:path';
import { defineConfig } from 'vitest/config';

const repoRoot = path.resolve(__dirname, '..');

export default defineConfig({
  resolve: {
    alias: [
      { find: '@snatchit/types', replacement: path.resolve(__dirname, 'types/src/index.ts') },
      { find: '@snatchit/core', replacement: path.resolve(__dirname, 'core/src/index.ts') },
      { find: '@snatchit/design-tokens', replacement: path.resolve(__dirname, 'design-tokens/src/index.ts') },
      // Mobile app sources (parity reference) — mirrors the app's '@/*' → './*' alias.
      { find: /^@mobile\//, replacement: repoRoot + '/' },
      // The SAME root under the app's OWN alias. '@mobile/' gets a mobile file loaded; this is
      // what lets that file's own internal imports resolve once it is loading. src/config/app.ts
      // began importing '@/src/lib/money' at 90235b74 and this suite could no longer load it —
      // red in CI from then on, and invisible until the ML7 failure ahead of it was fixed.
      // Resolution only: it maps '@/' exactly where tsconfig's "@/*": ["./*"] maps it, so a
      // parity test reads the same file the app does. Nothing here can change a fee or an amount.
      // Must stay a regex anchored on '@/' — a bare '@' string would also swallow '@mobile/'
      // and '@snatchit/' above.
      { find: /^@\//, replacement: repoRoot + '/' },
      // Supabase edge-function shared modules (server source of truth).
      { find: /^@server-shared\//, replacement: path.join(repoRoot, 'supabase/functions/_shared') + '/' },
    ],
  },
  test: {
    root: __dirname,
    include: ['*/tests/**/*.test.ts'],
    environment: 'node',
  },
});
