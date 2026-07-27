/**
 * Root vitest config — scopes `npm test` to the mobile app's existing suites
 * in tests/ (fee math, payout policy, payout races, backward compat).
 *
 * This preserves the pre-web behavior exactly: without this file, vitest's
 * default glob would also sweep the new web/ and packages/ test files into
 * the mobile test run. Package parity suites run separately via
 * `npm run test:packages` inside web/ (see packages/vitest.config.ts).
 */
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    environment: 'node',
  },
});
