/**
 * Root vitest config — scopes `npm test` to the mobile app's existing suites
 * in tests/ (fee math, payout policy, payout races, backward compat).
 *
 * This preserves the pre-web behavior exactly: without this file, vitest's
 * default glob would also sweep the new web/ and packages/ test files into
 * the mobile test run. Package parity suites run separately via
 * `npm run test:packages` inside web/ (see packages/vitest.config.ts).
 */
import path from 'node:path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  // The app resolves `@/…` through tsconfig paths; vitest needs the same alias
  // or any suite importing app code fails to resolve.
  resolve: {
    alias: [
      // Metro picks NativeAppShell.native.tsx / .web.tsx by platform; vitest has no platform suffixes, so this one
      // specifier resolves to the web passthrough (react only). It resolved to nothing before, so no suite that
      // ran then is affected; it lets tests/return-to-root-layout.test.ts run the real app/_layout.tsx.
      // WARNING: any future test importing '@/src/providers/NativeAppShell' gets this WEB no-op shell, not the
      // native funnel (deep links, forgetReturnToForAuthLink → dispatch). Test native shell behaviour by
      // importing NativeAppShell.native.tsx directly.
      { find: /^@\/src\/providers\/NativeAppShell$/, replacement: path.resolve(__dirname, 'src/providers/NativeAppShell.web.tsx') },
      { find: /^@\/(.*)$/, replacement: path.resolve(__dirname, '$1') },
    ],
  },
  test: {
    include: ['tests/**/*.test.ts'],
    environment: 'node',
  },
});
