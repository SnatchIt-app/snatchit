import { afterEach, describe, expect, it } from 'vitest';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const script = pathToFileURL(resolve('scripts/patch-uri-decoder-interop.mjs')).href;
const roots: string[] = [];
const consumer = (parent: string) => {
  const fromParent = createRequire(require.resolve(`${parent}/package.json`));
  return fromParent.resolve('query-string');
};
const decoderDirectory = () => dirname(createRequire(consumer('expo-router')).resolve('decode-uri-component'));
const runPatch = (root: string) => spawnSync(process.execPath, ['--input-type=module', '-e',
  `import {patchDecoder} from ${JSON.stringify(script)}; patchDecoder(${JSON.stringify(root)});`], { encoding: 'utf8' });
const fixture = () => {
  const root = mkdtempSync(join(tmpdir(), 'snatchit-decoder-test-'));
  roots.push(root);
  cpSync(decoderDirectory(), root, { recursive: true });
  return root;
};
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

describe('patched URI decoder with existing Expo/navigation consumers', () => {
  it.each(['expo-router', '@react-navigation/core'])('%s keeps query-string 7 and parses real query values', parent => {
    const entry = consumer(parent);
    const queryString = require(entry);
    const packageVersion = JSON.parse(readFileSync(join(dirname(entry), 'package.json'), 'utf8')).version;
    expect(packageVersion).toBe('7.1.3');
    expect(JSON.parse(readFileSync(join(decoderDirectory(), 'package.json'), 'utf8')).version).toBe('0.5.1');
    expect({ ...queryString.parse('name=Jos%C3%A9+Smith&next=%2Ftickets%2Fabc&tag=a&tag=b') }).toEqual({
      name: 'José Smith', next: '/tickets/abc', tag: ['a', 'b'],
    });
    expect(queryString.stringify({ next: '/tickets/abc', name: 'José Smith' })).toBe('name=Jos%C3%A9%20Smith&next=%2Ftickets%2Fabc');
  });

  it('keeps upstream ESM decoding identical to the generated CommonJS entrypoint', async () => {
    const root = fixture();
    expect(runPatch(root).status).toBe(0);
    const samples = ['', 'a+b', '%C3%A5', '%F0%9F%8E%AB', '%E0%A4%A', '%FE%FF', '%C2', '%G1', '%C0%AF', '%ED%A0%80', '%25C3%25A5'];
    const code = `import decode from ${JSON.stringify(pathToFileURL(join(root, 'index.js')).href)};
      import {createRequire} from 'node:module';const require=createRequire(import.meta.url);
      const common=require(${JSON.stringify(join(root, 'index.cjs'))});
      console.log(JSON.stringify(${JSON.stringify(samples)}.map(value=>[decode(value),common(value)])));`;
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', code], { encoding: 'utf8' });
    expect(result.status, result.stderr).toBe(0);
    for (const [esm, commonjs] of JSON.parse(result.stdout)) expect(commonjs).toBe(esm);
  });

  it('handles the upstream quadratic-denial-of-service payload through the actual consumer', () => {
    const code = `const q=require(${JSON.stringify(consumer('expo-router'))});let payload='';
      for(let i=0;i<32000;i++)payload+='%'+Math.floor(i/256).toString(16).padStart(2,'0')+'%'+(i%256).toString(16).padStart(2,'0')+'x';
      payload+='%zz';const output=q.parse('value='+payload);if(typeof output.value!=='string')process.exit(2);console.log('decoded');`;
    const result = spawnSync(process.execPath, ['-e', code], { encoding: 'utf8', timeout: 2500 });
    expect(result.error).toBeUndefined();
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout.trim()).toBe('decoded');
  });

  it('round-trips a ticket link through the real React Navigation path parser and serializer', () => {
    const core = dirname(require.resolve('@react-navigation/core/package.json'));
    const parse = pathToFileURL(join(core, 'lib/module/getStateFromPath.js')).href;
    const stringify = pathToFileURL(join(core, 'lib/module/getPathFromState.js')).href;
    const code = `import {getStateFromPath} from ${JSON.stringify(parse)};
      import {getPathFromState} from ${JSON.stringify(stringify)};
      const config={screens:{Tickets:'tickets/:id'}};
      const state=getStateFromPath('/tickets/abc?name=Jos%C3%A9+Smith',config);
      console.log(JSON.stringify({params:state.routes[0].params,path:getPathFromState(state,config)}));`;
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', code], { encoding: 'utf8' });
    expect(result.status, result.stderr).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual({ params: { id: 'abc', name: 'José Smith' }, path: '/tickets/abc?name=Jos%C3%A9%20Smith' });
  });

  it('is idempotent and leaves the upstream ESM source untouched', () => {
    const root = fixture();
    const source = readFileSync(join(root, 'index.js'));
    expect(runPatch(root).status).toBe(0);
    const generated = readFileSync(join(root, 'index.cjs'));
    expect(runPatch(root).status).toBe(0);
    expect(readFileSync(join(root, 'index.cjs'))).toEqual(generated);
    expect(readFileSync(join(root, 'index.js'))).toEqual(source);
  });

  it.each(['source', 'version', 'exports'])('refuses unexpected %s rather than silently using unreviewed code', change => {
    const root = fixture();
    if (change === 'source') writeFileSync(join(root, 'index.js'), readFileSync(join(root, 'index.js'), 'utf8') + '\n// drift');
    else {
      const file = join(root, 'package.json');
      const manifest = JSON.parse(readFileSync(file, 'utf8'));
      if (change === 'version') manifest.version = '0.5.2';
      else manifest.exports = { default: './unexpected.js' };
      writeFileSync(file, JSON.stringify(manifest));
    }
    expect(runPatch(root).status).not.toBe(0);
  });
});
