// redirects.test.mjs: offline proof of the snatchitwebapp.vercel.app redirect package.
//
// Run from anywhere:   node --test ops/legacy-snatchitwebapp/redirects.test.mjs
//
// The rules in vercel.json are compiled with Vercel's own routing-utils
// (getTransformedRoutes, which turns `redirects` and `trailingSlash` into the
// route list the edge evaluates, using path-to-regexp 6.1.0 with Vercel's
// options). Engine, in order:
//   1. @vercel/routing-utils, if it resolves from this directory, the repo
//      root or web/ (it is not a dependency today);
//   2. the copy bundled inside the installed vercel CLI (found on PATH, or at
//      VERCEL_CLI_DIR), located by its "../routing-utils/dist/index.js" marker;
//   3. the minimal matcher below. It supports only the syntax this file uses
//      ("/", literal segments, ":name", ":name*", "/:name(.*)") and throws on
//      anything else. When 1 or 2 is available the test also proves the
//      minimal matcher compiles this config to the identical route list.
// LEGACY_REDIRECT_ENGINE=minimal forces 3. LEGACY_VERCEL_JSON=<file> tests
// another config (used for planted-defect negative controls).
//
// The edge is modelled as Vercel documents it: routes run in order, the first
// matching redirect answers, $1..$n are substituted, and the request's query
// string passes through unchanged when the Location has none ("Query
// parameters pass through unless you explicitly replace them in the
// destination", vercel.com/docs/routing/redirects). `vercel dev` does NOT
// append the query (it sends the Location verbatim), so it is not a check of
// this behaviour; verify.sh against the live host is.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LEGACY = 'https://snatchitwebapp.vercel.app';
const APP = 'https://app.snatchitapp.com';
const CATCH_ALL = { source: '/:path(.*)', destination: `${APP}/:path` };
const CONFIG_FILE = process.env.LEGACY_VERCEL_JSON
  ? path.resolve(process.env.LEGACY_VERCEL_JSON)
  : path.join(HERE, 'vercel.json');
const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));

// Route files of the legacy Expo web export, read from its bundle
// /_expo/static/js/web/entry-4b9a0f80374677a658d67904bfc97b9c.js
// (production dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ, 2026-05-07), _layout files
// left out. Value: the app-host path the visitor must land on.
const LEGACY_ROUTES = {
  '(tabs)/index': '/',
  '(tabs)/home': '/',
  '(tabs)/explore': '/browse',
  '(tabs)/create': '/sell',
  '(tabs)/bids': '/account',
  '(tabs)/profile': '/account',
  '(auth)/login': '/login',
  '(auth)/signup': '/signup',
  '(auth)/reset-password': '/reset-password',
  'bid/[id]': '/listing/[id]',
  'checkout/[id]': '/checkout/[id]',
  'listing/[id]': '/listing/[id]',
  'my-listings': '/account/listings',
  'payout-return': '/payout-return',
  'payout-refresh': '/payout-refresh',
  'settings/index': '/account/settings',
  'settings/edit-profile': '/account/profile',
  'settings/notifications': '/account/notifications',
  'settings/payout-setup': '/account/settings',
  'settings/preferences': '/account/settings',
  // Owner decision: these three follow the default /settings rule. The
  // alternative is the marketing /terms, /privacy and /support pages.
  'settings/legal': '/account/settings',
  'settings/privacy': '/account/settings',
  'settings/support': '/account/settings',
  'transfer/send/[id]': '/transfer/send/[id]',
  'transfer/receive/[id]': '/transfer/receive/[id]',
};

// Pages of the live consumer web app (snatchit-web, served on
// app.snatchitapp.com), from web/src/app at a111fb06
// (origin/feature/web-accounts-foundation, live since 2026-10-15).
const APP_ROUTES = [
  '/', '/account', '/account/listings', '/account/listings/[id]/edit',
  '/account/notifications', '/account/profile', '/account/purchases',
  '/account/sales', '/account/saved', '/account/settings',
  '/account/verify-phone', '/auth/confirm', '/browse', '/checkout/[id]',
  '/checkout/[id]/complete', '/forgot-password', '/listing/[id]', '/login',
  '/payout-refresh', '/payout-return', '/reset-password', '/sell', '/signup',
  '/transfer/receive/[id]', '/transfer/send/[id]',
];

const PACKAGE_FILES = ['.vercelignore', 'README.md', 'index.html', 'redirects.test.mjs', 'verify.sh', 'vercel.json'];

// ---------------------------------------------------------------- engines

function findVercelCliDir() {
  const candidates = [];
  if (process.env.VERCEL_CLI_DIR) candidates.push(process.env.VERCEL_CLI_DIR);
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const bin = path.join(dir, 'vercel');
    if (!fs.existsSync(bin)) continue;
    let real;
    try { real = fs.realpathSync(bin); } catch { continue; }
    for (let d = path.dirname(real); d !== path.dirname(d); d = path.dirname(d)) {
      candidates.push(d);
    }
  }
  for (const d of candidates) {
    try {
      const pkg = JSON.parse(fs.readFileSync(path.join(d, 'package.json'), 'utf8'));
      if (pkg.name === 'vercel' && fs.existsSync(path.join(d, 'dist', 'chunks'))) {
        return { dir: d, version: pkg.version };
      }
    } catch {
      // not the CLI package root; keep looking
    }
  }
  return null;
}

async function loadBundledRoutingUtils(cli) {
  const chunksDir = path.join(cli.dir, 'dist', 'chunks');
  const marker = '"../routing-utils/dist/index.js"';
  for (const name of fs.readdirSync(chunksDir).sort()) {
    if (!name.endsWith('.js')) continue;
    const file = path.join(chunksDir, name);
    const src = fs.readFileSync(file, 'utf8');
    if (!src.includes(marker)) continue;
    const local = new RegExp(`var (require_\\w+) = __commonJS\\(\\{\\s*${marker.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')}`).exec(src);
    const mod = await import(pathToFileURL(file).href);
    const tryExport = (exp) => {
      if (typeof mod[exp] !== 'function') return null;
      try {
        const m = mod[exp]();
        return m && typeof m.getTransformedRoutes === 'function' ? m : null;
      } catch {
        return null;
      }
    };
    if (local) {
      const alias = new RegExp(`\\b${local[1]} as (\\w+)`).exec(src);
      const m = tryExport(alias ? alias[1] : local[1]);
      if (m) return { engine: m, name: `vercel CLI ${cli.version} bundled routing-utils (${name})` };
    }
    for (const exp of Object.keys(mod).filter((k) => k.startsWith('require_dist'))) {
      const m = tryExport(exp);
      if (m) return { engine: m, name: `vercel CLI ${cli.version} bundled routing-utils (${name}, ${exp})` };
    }
  }
  return null;
}

async function loadEngine() {
  if (process.env.LEGACY_REDIRECT_ENGINE === 'minimal') {
    return { engine: null, name: 'minimal matcher (forced by LEGACY_REDIRECT_ENGINE=minimal)' };
  }
  for (const base of [HERE, path.resolve(HERE, '..', '..'), path.resolve(HERE, '..', '..', 'web')]) {
    try {
      const req = createRequire(path.join(base, 'index.js'));
      const resolved = req.resolve('@vercel/routing-utils');
      const m = req(resolved);
      if (typeof m.getTransformedRoutes === 'function') {
        return { engine: m, name: `@vercel/routing-utils (${resolved})` };
      }
    } catch {
      // not installed here
    }
  }
  const cli = findVercelCliDir();
  if (cli) {
    const found = await loadBundledRoutingUtils(cli);
    if (found) return found;
  }
  return { engine: null, name: 'minimal matcher (no routing-utils found)' };
}

// Minimal matcher: reproduces routing-utils' output for the syntax subset
// above, byte for byte (path-to-regexp 6.1.0, strict, sensitive, delimiter
// "/", then normalizeRoutes' "\/" to "/" rewrite).
const NAME = '[A-Za-z_][A-Za-z0-9_]*';
function minimalSourceToRegex(source) {
  if (source === '/') return { src: '^/$', segments: [] };
  const any = new RegExp(`^/:(${NAME})\\(\\.\\*\\)$`).exec(source);
  if (any) return { src: '^(?:/(.*))$', segments: [any[1]] };
  if (!source.startsWith('/')) throw new Error(`minimal matcher: source must start with "/": ${source}`);
  const parts = source.slice(1).split('/');
  const segments = [];
  let src = '^';
  parts.forEach((p, i) => {
    let m;
    if ((m = new RegExp(`^:(${NAME})\\*$`).exec(p))) {
      if (i !== parts.length - 1) throw new Error(`minimal matcher: ":${m[1]}*" must be last: ${source}`);
      src += '(?:/((?:[^/]+?)(?:/(?:[^/]+?))*))?';
      segments.push(m[1]);
    } else if ((m = new RegExp(`^:(${NAME})$`).exec(p))) {
      src += '(?:/([^/]+?))';
      segments.push(m[1]);
    } else if (/^[A-Za-z0-9_~-]+(?:\.[A-Za-z0-9_~-]+)*$/.test(p)) {
      src += `/${p.replace(/\./g, '\\.')}`;
    } else {
      throw new Error(`minimal matcher: unsupported segment "${p}" in ${source}`);
    }
  });
  return { src: `${src}$`, segments };
}

function minimalDestination(destination, segments) {
  const u = /^(https:\/\/[A-Za-z0-9.-]+)(\/[^?#]*)$/.exec(destination);
  if (!u) throw new Error(`minimal matcher: unsupported destination ${destination}`);
  let pathname = u[2];
  segments.forEach((name, i) => {
    pathname = pathname.replace(new RegExp(`:${name}(?![A-Za-z0-9_])[*+?]?`, 'g'), `$${i + 1}`);
  });
  if (pathname.includes(':')) throw new Error(`minimal matcher: unknown parameter in ${destination}`);
  return u[1] + pathname;
}

const minimalEngine = {
  getTransformedRoutes(cfg) {
    const extra = Object.keys(cfg).filter((k) => !['$schema', 'trailingSlash', 'redirects'].includes(k));
    if (extra.length) throw new Error(`minimal matcher: unsupported keys ${extra.join(', ')}`);
    const routes = [];
    if (cfg.trailingSlash === false) routes.push({ src: '^/(.*)\\/$', headers: { Location: '/$1' }, status: 308 });
    else if (cfg.trailingSlash !== undefined) throw new Error('minimal matcher: only trailingSlash false');
    for (const r of cfg.redirects || []) {
      if (r.has || r.missing || r.statusCode || r.permanent !== true) {
        throw new Error(`minimal matcher: only permanent redirects without has/missing: ${JSON.stringify(r)}`);
      }
      const { src, segments } = minimalSourceToRegex(r.source);
      routes.push({ src, headers: { Location: minimalDestination(r.destination, segments) }, status: 308 });
    }
    return { routes, error: null };
  },
};

function normalizeRoute(r) {
  // routing-utils escapes "/" inside the trailing-slash route; compare
  // semantically by applying the same normalization it applies to sources.
  return typeof r.src === 'string' ? { ...r, src: r.src.replace(/\\\//g, '/') } : r;
}

// ---------------------------------------------------------------- edge model

function splitUrl(rel) {
  const q = rel.indexOf('?');
  return q === -1 ? { pathname: rel, query: null } : { pathname: rel.slice(0, q), query: rel.slice(q + 1) };
}

// One request against the compiled routes. `opts.insensitive` matches
// case-insensitively (Vercel's default for routes); `opts.slashFallback`
// also tries the path without its leading "/" (what `vercel dev` does).
function respond(routes, rel, opts) {
  const { pathname, query } = splitUrl(rel);
  for (let i = 0; i < routes.length; i++) {
    const r = routes[i];
    const re = new RegExp(r.src, opts.insensitive ? 'i' : '');
    const m = re.exec(pathname) || (opts.slashFallback ? re.exec(pathname.slice(1)) : null);
    if (!m) continue;
    let loc = r.headers.Location.replace(/\$(\d+)/g, (_, n) => m[Number(n)] ?? '');
    if (query !== null && !loc.includes('?')) loc += `?${query}`;
    if (loc.startsWith('/')) loc = LEGACY + loc;
    return { status: r.status, location: loc, route: i };
  }
  return { status: 'filesystem', location: null, route: -1 };
}

// Follows redirects while they stay on the legacy host.
function follow(routes, rel, opts) {
  const hops = [];
  let current = rel;
  for (;;) {
    const res = respond(routes, current, opts);
    hops.push(res);
    if (!res.location || !res.location.startsWith(`${LEGACY}/`) || hops.length >= 5) break;
    current = res.location.slice(LEGACY.length);
  }
  const last = hops[hops.length - 1];
  return { hops, final: last.location, statuses: hops.map((h) => h.status) };
}

const EDGE_VARIANTS = [
  { insensitive: true, slashFallback: false },
  { insensitive: false, slashFallback: false },
  { insensitive: true, slashFallback: true },
  { insensitive: false, slashFallback: true },
];

function fillParams(p, sample = 'abc-123') {
  return p.replace(/\[[^\]]+\]/g, sample);
}

function legacyUrlFor(file) {
  const parts = file.split('/').filter((s) => !/^\(.*\)$/.test(s));
  if (parts[parts.length - 1] === 'index') parts.pop();
  return fillParams(`/${parts.join('/')}`);
}

function appRouteExists(pathname) {
  return APP_ROUTES.some((r) => new RegExp(`^${r.replace(/\[[^\]]+\]/g, '[^/]+')}$`).test(pathname));
}

function readMatrix() {
  const sh = fs.readFileSync(path.join(HERE, 'verify.sh'), 'utf8');
  const block = /<<'MATRIX'\n([\s\S]*?)\nMATRIX\n/.exec(sh);
  assert.ok(block, 'verify.sh has a MATRIX heredoc');
  return block[1]
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'))
    .map((l) => {
      const f = l.split(/\s+/);
      assert.equal(f.length, 4, `matrix row has 4 fields: ${l}`);
      return { path: f[0], final: f[1], hops: Number(f[2]), dest: f[3] };
    });
}

// ---------------------------------------------------------------- tests

const { engine: realEngine, name: engineName } = await loadEngine();
const engine = realEngine || minimalEngine;
let compiled;
try {
  compiled = engine.getTransformedRoutes(structuredClone(config));
} catch (err) {
  compiled = { routes: [], error: err.message };
}
const routes = (compiled.routes || []).map(normalizeRoute);
const redirects = config.redirects || [];

test(`compile with ${engineName}`, (t) => {
  t.diagnostic(`engine: ${engineName}`);
  t.diagnostic(`config: ${CONFIG_FILE}`);
  assert.equal(compiled.error, null, `routing-utils rejected the config: ${JSON.stringify(compiled.error)}`);
  assert.equal(routes.length, redirects.length + 1, 'one route per redirect plus the trailing-slash route');
});

test('minimal matcher compiles this config to the identical route list', (t) => {
  if (!realEngine) {
    t.skip('no routing-utils available; the minimal matcher is the engine');
    return;
  }
  const minimal = minimalEngine.getTransformedRoutes(structuredClone(config)).routes.map(normalizeRoute);
  assert.deepEqual(minimal, routes);
});

test('config holds only permanent redirects and trailingSlash false', () => {
  assert.deepEqual(Object.keys(config).sort(), ['$schema', 'redirects', 'trailingSlash']);
  assert.equal(config.trailingSlash, false);
  assert.ok(redirects.length > 0);
  for (const r of redirects) {
    assert.deepEqual(Object.keys(r).sort(), ['destination', 'permanent', 'source'], `only source/destination/permanent: ${r.source}`);
    assert.equal(r.permanent, true, `permanent: ${r.source}`);
  }
});

test('every destination is on https://app.snatchitapp.com/ and adds no query or fragment', () => {
  for (const r of redirects) {
    assert.ok(r.destination.startsWith(`${APP}/`), `destination on the app host: ${r.source} -> ${r.destination}`);
    assert.ok(!r.destination.includes('?') && !r.destination.includes('#'), `no query or fragment injected: ${r.destination}`);
    assert.ok(!/client=/.test(r.destination), `no client parameter: ${r.destination}`);
    assert.equal(new URL(r.destination.replace(/:[A-Za-z_]\w*(\(\.\*\))?[*+?]?/g, 'x')).host, 'app.snatchitapp.com');
  }
});

test('"/" is the first rule and the catch-all is the last and only catch-all', () => {
  assert.equal(redirects[0].source, '/');
  assert.equal(redirects[0].destination, `${APP}/`);
  const last = redirects[redirects.length - 1];
  assert.equal(last.source, CATCH_ALL.source);
  assert.equal(last.destination, CATCH_ALL.destination);
  assert.equal(redirects.filter((r) => r.source.includes('(.*)') || /^\/:[A-Za-z_]\w*[*]$/.test(r.source)).length, 1);
  assert.equal(new Set(redirects.map((r) => r.source)).size, redirects.length, 'no duplicate sources');
});

test('compiled routes: every one is a 308 redirect, trailing-slash strip first', () => {
  assert.deepEqual(routes[0], { src: '^/(.*)/$', headers: { Location: '/$1' }, status: 308 });
  for (const r of routes) {
    assert.equal(r.status, 308, `308: ${r.src}`);
    assert.ok(r.headers && typeof r.headers.Location === 'string', `Location: ${r.src}`);
    for (const k of ['continue', 'dest', 'has', 'missing', 'handle', 'check']) {
      assert.equal(r[k], undefined, `${k} must not be set: ${r.src}`);
    }
  }
  for (const r of routes.slice(1)) assert.ok(r.headers.Location.startsWith(`${APP}/`), r.headers.Location);
});

test('no rule is shadowed by an earlier rule', () => {
  redirects.forEach((r, i) => {
    const sample = r.source === '/' ? '/' : r.source
      .replace(/:[A-Za-z_]\w*\(\.\*\)/g, 'zz-sample/x')
      .replace(/:[A-Za-z_]\w*\*/g, 'a/b')
      .replace(/:[A-Za-z_]\w*/g, 'abc-123');
    for (const opts of EDGE_VARIANTS) {
      assert.equal(respond(routes, sample, opts).route, i + 1, `${sample} must hit rule ${i} (${r.source}) ${JSON.stringify(opts)}`);
    }
  });
});

test('verify.sh matrix: every row lands where the matrix says, all hops 308', () => {
  const rows = readMatrix();
  assert.ok(rows.length >= 30, `matrix has ${rows.length} rows`);
  for (const row of rows) {
    for (const opts of EDGE_VARIANTS) {
      const res = follow(routes, row.path, opts);
      assert.equal(res.final, APP + row.final, `${row.path} final ${JSON.stringify(opts)}`);
      assert.equal(res.hops.length, row.hops, `${row.path} hops ${JSON.stringify(opts)}`);
      assert.ok(res.statuses.every((s) => s === 308), `${row.path} all 308: ${res.statuses}`);
    }
  }
});

test('verify.sh matrix covers every rule, "/" and query cases', () => {
  const rows = readMatrix();
  const hit = new Set(rows.map((row) => respond(routes, row.path, EDGE_VARIANTS[0]).route));
  routes.forEach((r, i) => assert.ok(hit.has(i), `no matrix row exercises route ${i} (${r.src})`));
  assert.ok(rows.some((r) => r.path === '/'), 'row for "/"');
  assert.ok(rows.filter((r) => r.path.includes('?')).length >= 6, 'query rows');
});

test('every legacy Expo route lands on an existing app-host page', () => {
  for (const [file, want] of Object.entries(LEGACY_ROUTES)) {
    const url = legacyUrlFor(file);
    const expected = fillParams(want);
    assert.ok(appRouteExists(expected), `${expected} is a page on the app host`);
    for (const opts of EDGE_VARIANTS) {
      for (const suffix of ['', '?x=1', '/']) {
        if (suffix === '/' && url === '/') continue;
        const res = follow(routes, url + suffix, opts);
        const final = new URL(res.final);
        assert.equal(final.origin, APP, `${url}${suffix} leaves for the app host`);
        assert.equal(final.pathname, expected, `${file}: ${url}${suffix} -> ${res.final}`);
        assert.equal(final.search, suffix === '?x=1' ? '?x=1' : '', `${url}${suffix} query kept as is`);
      }
    }
  }
});

test('query string is passed through byte for byte and nothing is added', () => {
  const queries = [null, 'client=app', 'client=web&x=1', 'q=a%20b&next=%2Faccount', 'a=1&a=2', 'a=', 'utm_source=x&utm_medium=y'];
  const paths = ['/', '/payout-return', '/payout-refresh', '/login', '/bid/abc-123', '/settings/legal', '/my-listings', '/zz/unknown/path'];
  for (const p of paths) {
    for (const q of queries) {
      const rel = q === null ? p : `${p}?${q}`;
      const res = follow(routes, rel, EDGE_VARIANTS[0]);
      const i = res.final.indexOf('?');
      assert.equal(i === -1 ? null : res.final.slice(i + 1), q, `${rel} -> ${res.final}`);
    }
  }
});

test('every path on the legacy host leaves for the app host (whole-host)', () => {
  const samples = ['/', '/a', '/a/b/c', '/a/', '/a//b', '//', '/index.html', '/vercel.json', '/_expo/static/js/web/x.js',
    '/favicon.ico', '/robots.txt', '/sitemap.xml', '/SETTINGS/legal', '/Login', '/settings/legal/extra', '/listing/a/b'];
  for (const s of samples) {
    for (const opts of EDGE_VARIANTS) {
      const res = follow(routes, s, opts);
      assert.ok(res.final && res.final.startsWith(`${APP}/`), `${s} -> ${res.final} ${JSON.stringify(opts)}`);
      assert.ok(res.hops.length <= 3 && res.statuses.every((x) => x === 308), `${s}: ${res.statuses}`);
    }
  }
});

test('package hygiene: files, .vercelignore, fallback page', () => {
  const files = fs.readdirSync(HERE).filter((f) => f !== '.DS_Store').sort();
  assert.deepEqual(files, [...PACKAGE_FILES].sort(), 'no extra files (no package.json, no .vercel link)');
  const ignore = fs.readFileSync(path.join(HERE, '.vercelignore'), 'utf8').split('\n').map((l) => l.trim());
  for (const f of ['README.md', 'verify.sh', '*.test.mjs', '.vercel']) assert.ok(ignore.includes(f), `.vercelignore lists ${f}`);
  assert.ok(fs.statSync(path.join(HERE, 'verify.sh')).mode & 0o100, 'verify.sh is executable');

  const html = fs.readFileSync(path.join(HERE, 'index.html'), 'utf8');
  assert.match(html, /<meta name="robots" content="noindex">/);
  assert.match(html, /<a href="https:\/\/app\.snatchitapp\.com\/">/);
  assert.doesNotMatch(html, /<script|http-equiv="refresh"/i, 'plain link only');
  assert.doesNotMatch(html, /\u2014|--/, 'no em dash or "--"');
  assert.doesNotMatch(html, /\b(verified|instant(ly)?)\b|%/i, 'copy rules');
});

test('README pins the exact project, deployment and commands', () => {
  const readme = fs.readFileSync(path.join(HERE, 'README.md'), 'utf8');
  for (const s of [
    'VERCEL_ORG_ID=team_rld7LG9DKzgaph97l4H4jl9d VERCEL_PROJECT_ID=prj_b8imLCi045a8IwwWK3QJB19hg8lz vercel deploy --prod',
    'vercel project inspect',
    'dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ',
    'vercel promote dpl_AuvY87KC1byWe8EDAu9JUdsbDCZJ',
    './verify.sh --expect current',
  ]) {
    assert.ok(readme.includes(s), `README contains: ${s}`);
  }
  assert.doesNotMatch(readme, /^\s*export VERCEL_(ORG|PROJECT)_ID/m, 'pins are inline, never exported into the shell');
});
