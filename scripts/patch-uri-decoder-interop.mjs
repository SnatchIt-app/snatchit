/** Keep the patched upstream decoder callable by Expo 54's CommonJS consumers.
 * The upstream ESM implementation stays untouched. Only its export is translated
 * for require()/Metro; no decoding algorithm is maintained locally.
 */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// npm's integrity pin authenticates the package; this also refuses changed or
// cached source before producing a compatibility entrypoint.
const SOURCE_SHA256 = '6a86ac891edf15c5efa0841ebb31935e3669d58b98318b57d7b08a4530317cb0';
const originalExports = { types: './index.d.ts', default: './index.js' };
const compatibleExports = {
  types: './index.d.ts',
  'react-native': './index.cjs',
  require: './index.cjs',
  default: './index.js',
};

export function patchDecoder(directory) {
  const manifestPath = join(directory, 'package.json');
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.name, 'decode-uri-component');
  assert.equal(manifest.version, '0.5.1', 'Re-review compatibility before changing the pinned decoder');
  const source = readFileSync(join(directory, 'index.js'), 'utf8');
  assert.equal(createHash('sha256').update(source).digest('hex'), SOURCE_SHA256,
    'Unexpected upstream decoder source; refusing to generate compatibility code');
  assert.ok([originalExports, compatibleExports].some(value =>
    JSON.stringify(value) === JSON.stringify(manifest.exports)), 'Unexpected package exports');
  const declaration = 'export default function decodeUriComponent(';
  assert.equal(source.split(declaration).length, 2);
  const commonjs = "'use strict';\n" + source.replace(declaration, 'function decodeUriComponent(')
    + '\nmodule.exports = decodeUriComponent;\n';
  writeFileSync(join(directory, 'index.cjs'), commonjs);
  manifest.exports = compatibleExports;
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

export function patchInstalledDecoders(projectRoot) {
  const require = createRequire(join(projectRoot, 'package.json'));
  const directories = new Set();
  for (const parent of ['expo-router', '@react-navigation/core']) {
    const consumer = createRequire(require.resolve(`${parent}/package.json`));
    const queryString = createRequire(consumer.resolve('query-string'));
    directories.add(dirname(queryString.resolve('decode-uri-component')));
  }
  for (const directory of directories) patchDecoder(directory);
  return directories.size;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const count = patchInstalledDecoders(fileURLToPath(new URL('../', import.meta.url)));
  console.log(`[uri-decoder-interop] verified upstream 0.5.1; ${count} CommonJS/Metro entrypoint(s)`);
}
