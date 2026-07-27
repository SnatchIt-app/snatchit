// https://docs.expo.dev/guides/using-eslint/
const { defineConfig } = require('eslint/config');
const expoConfig = require('eslint-config-expo/flat');

module.exports = defineConfig([
  expoConfig,
  {
    // web/ and packages/ carry their own lint setups (web/eslint.config.mjs);
    // keep `expo lint` scoped to the mobile app exactly as before.
    ignores: ['dist/*', 'web/**', 'packages/**'],
  },
]);
