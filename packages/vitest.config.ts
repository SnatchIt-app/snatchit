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
