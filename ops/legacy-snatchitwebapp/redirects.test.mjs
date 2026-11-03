// redirects.test.mjs: offline proof of the snatchitwebapp.vercel.app redirect package.
//
// Run from anywhere:   node --test ops/legacy-snatchitwebapp/redirects.test.mjs
//
// The rules in vercel.json are compiled with Vercel's own routing-utils
// (getTransformedRoutes, which turns `redirects` into the route list the edge
// evaluates, using path-to-regexp 6.1.0 with Vercel's options). Engine, in
// order:
//   1. @vercel/routing-utils, if it resolves from this directory, the repo
//      root or web/ (it is not a dependency today);
//   2. the copy bundled inside the installed vercel CLI (found on PATH, or at
//      VERCEL_CLI_DIR), located by its "../routing-utils/dist/index.js" marker;
//   3. the minimal matcher below. It supports only the syntax this file uses
//      ("/", literal segments, ":name", ":name*", "/:name(.*)", one optional
//      trailing slash written "{/}?") and throws on anything else. When 1 or 2
//      is available the test also proves the minimal matcher compiles this
//      config to the identical route list.
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
//
// Every Location is resolved the way a client resolves it, with
// new URL(location, legacy origin) (WHATWG: "\" reads as "/"), never by
// string concatenation. A relative or scheme-relative Location ("/x",
// "//host/x", "/\host") is therefore followed to wherever a browser would go,
// which is what the hostile-path test relies on.
//
// Vercel's own slash merge runs before any route. It is modelled as observed
// on the live legacy host on 2026-10-21 (LIVE_MERGE below pins every
// observation): when the request path, as the edge escapes it, contains "//",
// the answer is a 308 with a RELATIVE Location: that path with every run of
// "/" merged and the query re-encoded. The edge escapes a path like Go's
// net/url: a path made only of RFC 3986 path characters is kept as sent;
// any other character ("\", "|", '"', ...) makes it decode the whole path
// ("%2F" included) and percent-encode it again, so "\" comes out as "%5C"
// ("//\evil.example" -> "/%5Cevil.example"). The query is decoded per
// key and value ("+" is a space) and re-encoded like encodeURIComponent,
// dropping empty pairs ("//x?next=//evil.example" -> "/x?next=%2F%2Fevil.example").
//
// Edge variants; every combination is tested:
//   insensitive    routes match case-insensitively (Vercel's default for
//                  routes; the live edge is not pinned down, so both)
//   slashFallback  also try the path without its leading "/" (`vercel dev`)
//   merge          'live': the slash merge above runs first; false: routes
//                  see every path unmerged
//   rawBackslash   routes see a "\" in the request path raw (true) or as the
//                  edge escapes it, "%5C" (false). Not observed either way:
//                  the live host answers 200 to "/\evil.example", no hop
//   decodePath     routes match, and $n substitute, the percent-decoded path
//                  (not observed either way, so both)
// A merge that kept "\" raw is not one of the variants: it sends
// "//\evil.example" to https://evil.example/ before any route runs, so no
// vercel.json can pass it. The counterfactual test pins that, and verify.sh
// checks the live encoding.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LEGACY = 'https://snatchitwebapp.vercel.app';
const APP = 'https://app.snatchitapp.com';
const APP_HOST = 'app.snatchitapp.com';
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

// Routes both hosts share. Each must stay its own explicit rule (same path on
// the app host) so the Stripe return pages and the auth pages never depend on
// the catch-all.
const SHARED_RULES = [
  '/', '/login', '/signup', '/reset-password', '/payout-return', '/payout-refresh',
  '/listing/:id', '/checkout/:id', '/transfer/send/:id', '/transfer/receive/:id',
];

// Request paths that turn a relative Location into another host. The first
// six are required (the last two came from review: under a slash merge that
// kept "\" raw they leave for evil.example); verify.sh's HOSTILE list must
// contain them, and every entry of that list is run here too.
const HOSTILE_REQUIRED = ['//evil.example/', '//evil.example', '/%2F%2Fevil.example', '/\\evil.example',
  '//\\evil.example', '/\\//evil.example/'];
const HOSTILE_EXTRA = [
  '///evil.example/', '/%2F%2Fevil.example/', '/%2f%2fevil.example', '/\\evil.example/', '/\\\\evil.example/',
  '/\\/evil.example/', '/%5Cevil.example/', '/%5C%5Cevil.example', '/.//evil.example/', '/%09/evil.example/',
  '//evil.example/a//b', '//evil.example/?next=//evil.example', '//evil.example:443/',
  '//user@evil.example/', '//evil.example%2F', '/https://evil.example/', '/https:evil.example/',
  '/settings//evil.example/', '/login//evil.example/', '/my-listings//evil.example', '/%2F/evil.example/',
  '///\\evil.example/', '//\\/evil.example/', '//\\\\evil.example', '/\\\\//evil.example', '/%2F/\\evil.example',
  '//%2F\\evil.example', '//%5C/evil.example', '/./\\//evil.example/', '//\\evil.example?next=//\\evil.example',
  '/\\//evil.example/?next=%2F%2Fevil.example', '//x\\?next=//evil.example', '/\\%2F/evil.example/',
];

// Vercel's slash merge on the live legacy host, 2026-10-21 (curl --path-as-is
// --globoff, GET): request -> Location of its 308, or null for "no merge"
// (the request reached the legacy app and answered 200). The model must
// reproduce every row. Known gap, left out: a malformed escape in the query
// ("//x?a=%zz") came back as "a=zz"; the model keeps "%25zz".
const LIVE_MERGE = [
  ['//evil.example/', '/evil.example/'],
  ['/a//b?q=a%20b&n=%2F', '/a/b?q=a%20b&n=%2F'],
  ['//x/?a=1&a=2', '/x/?a=1&a=2'],
  ['//\\evil.example', '/%5Cevil.example'],
  ['/\\//evil.example/', '/%5C/evil.example/'],
  ['///\\evil.example/', '/%5Cevil.example/'],
  ['//\\/evil.example/', '/%5C/evil.example/'],
  ['//\\\\evil.example', '/%5C%5Cevil.example'],
  ['/\\\\//evil.example', '/%5C%5C/evil.example'],
  ['//%2F\\evil.example', '/%5Cevil.example'],
  ['/%2F/\\evil.example', '/%5Cevil.example'],
  ['//%5C/evil.example', '/%5C/evil.example'],
  ['/./\\//evil.example/', '/./%5C/evil.example/'],
  ['/a/%2F%2F\\b', '/a/%5Cb'],
  ['//x/a%2F%2Fb\\', '/x/a/b%5C'],
  ['//x/%2f\\', '/x/%5C'],
  ['//x/%2f', '/x/%2f'],
  ['//x/%5c', '/x/%5c'],
  ['//x/a%20b', '/x/a%20b'],
  ['//x/%41', '/x/%41'],
  ['//x/a:b@c', '/x/a:b@c'],
  ["//x/!'()*~;,=&+$", "/x/!'()*~;,=&+$"],
  ["//x/!'()*~\\", '/x/%21%27%28%29%2A~%5C'],
  ['//x/;,=&+$:@\\', '/x/;,=&+$:@%5C'],
  ['//x/%25\\', '/x/%25%5C'],
  ['//x/%3F\\', '/x/%3F%5C'],
  ['//x/%23\\', '/x/%23%5C'],
  ['//x/%20\\', '/x/%20%5C'],
  ['//x/%7e\\', '/x/~%5C'],
  ['//x/a[b]\\', '/x/a%5Bb%5D%5C'],
  ['//x/a|b', '/x/a%7Cb'],
  ['//x/a^b', '/x/a%5Eb'],
  ['//x/a`b', '/x/a%60b'],
  ['//x/a"b', '/x/a%22b'],
  ['//x/a<b>', '/x/a%3Cb%3E'],
  ['//x\\?a=1', '/x%5C?a=1'],
  ['//X/Y?A=B', '/X/Y?A=B'],
  ['//x?next=//evil.example', '/x?next=%2F%2Fevil.example'],
  ['//x?next=/a', '/x?next=%2Fa'],
  ['//x?next=%2F%2Fe', '/x?next=%2F%2Fe'],
  ['/a//b?x=\\y', '/a/b?x=%5Cy'],
  ['//x?q=a+b', '/x?q=a%20b'],
  ['//x?a=%41&b=%2f', '/x?a=A&b=%2F'],
  ['//x?a=b:c@d', '/x?a=b%3Ac%40d'],
  ["//x?a=!'()*~", "/x?a=!'()*~"],
  ['//x?a', '/x?a'],
  ['//x?a=&b', '/x?a=&b'],
  ['//x?a=b=c', '/x?a=b%3Dc'],
  ['//x?a=%E2%80%94', '/x?a=%E2%80%94'],
  ['//x?a=b;c,d$e', '/x?a=b%3Bc%2Cd%24e'],
  ['//x?a=b%3Dc%26d', '/x?a=b%3Dc%26d'],
  ['//x?a=%25', '/x?a=%25'],
  ['//x?=1', '/x?1'],
  ['//x?&&a=1', '/x?a=1'],
  ['//x?', '/x'],
  ['//x?&', '/x'],
  ['/\\evil.example', null],
  ['/%2F%2Fevil.example', null],
  ['/a%2F/b', null],
  ['/a/%2F/b', null],
  ['/%5C%5Cevil.example', null],
  ['/%5C/evil.example', null],
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
// "/", then normalizeRoutes' "\/" to "/" rewrite). It still knows
// `trailingSlash: false` so the planted-defect controls run on it too.
const NAME = '[A-Za-z_][A-Za-z0-9_]*';
const OPTIONAL_SLASH = '{/}?';
function minimalSourceToRegex(source) {
  let tail = '';
  if (source.endsWith(OPTIONAL_SLASH)) {
    source = source.slice(0, -OPTIONAL_SLASH.length);
    tail = '(?:/)?';
    if (source === '' || source === '/' || source.includes('(')) {
      throw new Error(`minimal matcher: "${OPTIONAL_SLASH}" only after a literal or ":name" segment: ${source}${OPTIONAL_SLASH}`);
    }
  }
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
      src += `/${escapeRe(p)}`;
    } else {
      throw new Error(`minimal matcher: unsupported segment "${p}" in ${source}`);
    }
  });
  return { src: `${src}${tail}$`, segments };
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
  // routing-utils escapes "/" inside the routes it generates itself (the
  // trailingSlash route, for one); compare semantically by applying the same
  // normalization it applies to redirect sources.
  return typeof r.src === 'string' ? { ...r, src: r.src.replace(/\\\//g, '/') } : r;
}

// ---------------------------------------------------------------- edge model

function splitUrl(rel) {
  const q = rel.indexOf('?');
  return q === -1 ? { pathname: rel, query: null } : { pathname: rel.slice(0, q), query: rel.slice(q + 1) };
}

function safeDecode(s) {
  try { return decodeURIComponent(s); } catch { return s; }
}

// The path as the edge escapes it (Go net/url EscapedPath): kept as sent when
// every character is an RFC 3986 path character, "%", "[" or "]"; otherwise
// decoded and re-encoded, keeping only unreserved characters and
// "$&+,/:;=@" ("!'()*" and "[]" are encoded too, as observed).
const EDGE_PATH_AS_SENT = /^[A-Za-z0-9\-._~!$&'()*+,;=:@/%[\]]*$/;
const EDGE_PATH_KEEP = /^[A-Za-z0-9\-._~$&+,/:;=@]$/;
function edgeEscapePath(pathname) {
  if (EDGE_PATH_AS_SENT.test(pathname)) return pathname;
  let out = '';
  for (const ch of safeDecode(pathname)) {
    out += EDGE_PATH_KEEP.test(ch) ? ch : [...Buffer.from(ch)].map((b) => `%${b.toString(16).toUpperCase().padStart(2, '0')}`).join('');
  }
  return out;
}

// The query as the slash merge re-encodes it.
function edgeQuery(query) {
  const enc = (s) => encodeURIComponent(safeDecode(s.replace(/\+/g, ' ')));
  return query.split('&').filter(Boolean).map((part) => {
    const eq = part.indexOf('=');
    if (eq === -1) return enc(part);
    const key = part.slice(0, eq);
    return key === '' ? enc(part.slice(eq + 1)) : `${enc(key)}=${enc(part.slice(eq + 1))}`;
  }).join('&');
}

// Vercel's slash merge: the relative Location it answers with, or null when
// it lets the request through. `mode` 'live' is the observed behaviour; 'raw'
// (counterfactual only) merges the raw path and keeps the query byte for byte.
function slashMerge(pathname, query, mode) {
  if (mode === 'raw') {
    if (!pathname.includes('//')) return null;
    return pathname.replace(/\/{2,}/g, '/') + (query === null ? '' : `?${query}`);
  }
  const escaped = edgeEscapePath(pathname);
  if (!escaped.includes('//')) return null;
  const q = query === null ? '' : edgeQuery(query);
  return escaped.replace(/\/{2,}/g, '/') + (q === '' ? '' : `?${q}`);
}

// What the client does with a Location: resolve it against the URL it asked
// for. Every Location here is absolute or starts with "/", so the legacy
// origin is the whole base; a relative-path Location would fail the
// absolute-Location tests before it mattered. A Location a browser cannot
// parse ("/\\" is "https:" with an empty host) resolves to null, which every
// host check counts as off the app host.
function resolveLocation(location) {
  try {
    return new URL(location, LEGACY);
  } catch {
    return null;
  }
}

function answer(status, location, route) {
  return { status, location, url: resolveLocation(location), route };
}

// One request (raw path and query, as sent on the wire) against the compiled
// routes. `route` is the index of the answering route, 'merge' for Vercel's
// own duplicate-slash step, -1 when nothing answers.
function respond(routes, target, opts) {
  const { pathname, query } = splitUrl(target);
  const qs = query === null ? '' : `?${query}`;
  if (opts.merge) {
    const merged = slashMerge(pathname, query, opts.merge);
    if (merged !== null) return answer(308, merged, 'merge');
  }
  const seen = opts.rawBackslash ? pathname : edgeEscapePath(pathname);
  const subject = opts.decodePath ? safeDecode(seen) : seen;
  for (let i = 0; i < routes.length; i++) {
    const r = routes[i];
    const re = new RegExp(r.src, opts.insensitive ? 'i' : '');
    const m = re.exec(subject) || (opts.slashFallback ? re.exec(subject.slice(1)) : null);
    if (!m) continue;
    let location = r.headers.Location.replace(/\$(\d+)/g, (_, n) => m[Number(n)] ?? '');
    if (query !== null && !location.includes('?')) location += qs;
    return answer(r.status, location, i);
  }
  return { status: 'filesystem', location: null, url: null, route: -1 };
}

// Follows redirects while the resolved Location stays on the legacy host.
function follow(routes, target, opts) {
  const hops = [];
  let next = target;
  for (;;) {
    const res = respond(routes, next, opts);
    hops.push(res);
    if (!res.url || res.url.origin !== LEGACY || hops.length >= 5) break;
    next = res.url.pathname + res.url.search;
  }
  const last = hops[hops.length - 1];
  return {
    hops,
    url: last.url,
    final: last.url ? last.url.href : null,
    location: last.location,
    statuses: hops.map((h) => h.status),
    trace: hops.map((h) => `${h.status} ${h.location}`).join(' -> '),
  };
}

const EDGE_VARIANTS = [];
for (const merge of ['live', false]) {
  for (const rawBackslash of [true, false]) {
    for (const insensitive of [true, false]) {
      for (const decodePath of [false, true]) {
        for (const slashFallback of [false, true]) {
          EDGE_VARIANTS.push({ insensitive, slashFallback, merge, rawBackslash, decodePath });
        }
      }
    }
  }
}

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

// The app host answers 308 to the same path without one trailing slash
// (observed 2026-10-21: /login/ -> /login, /payout-return/?client=app ->
// /payout-return?client=app). Shared and catch-all trailing-slash URLs rely
// on it; legacy-only routes must not, because their legacy path is a 404
// there (/my-listings and /settings/legal answered 404 on 2026-10-21).
function appHostNormalise(pathname) {
  return pathname.length > 1 && pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
}

// A request path that hits rule `source` (parameters filled, "{/}?" dropped).
function sampleFor(source) {
  if (source === '/') return '/';
  return source
    .replace(/\{\/\}\?$/, '')
    .replace(/:[A-Za-z_]\w*\(\.\*\)/g, 'zz-sample/x')
    .replace(/:[A-Za-z_]\w*\*/g, 'a/b')
    .replace(/:[A-Za-z_]\w*/g, 'abc-123');
}

function readHeredoc(tag) {
  const sh = fs.readFileSync(path.join(HERE, 'verify.sh'), 'utf8');
  const block = new RegExp(`<<'${tag}'\\n([\\s\\S]*?)\\n${tag}\\n`).exec(sh);
  assert.ok(block, `verify.sh has a ${tag} heredoc`);
  return block[1].split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
}

function readMatrix() {
  return readHeredoc('MATRIX').map((l) => {
    const f = l.split(/\s+/);
    assert.equal(f.length, 4, `matrix row has 4 fields: ${l}`);
    return { path: f[0], final: f[1], hops: Number(f[2]), dest: f[3] };
  });
}

// ---------------------------------------------------------------- .vercelignore

function escapeRe(c) {
  return c.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
}

// Does one gitignore-style pattern (as `.vercelignore` uses them, through the
// `ignore` package, case-insensitively) match `name`, a file at the package
// root? Comments and "!" lines never ignore.
function globMatches(pattern, name) {
  let p = pattern;
  if (p === '' || p.startsWith('#') || p.startsWith('!')) return false;
  if (p.startsWith('\\#') || p.startsWith('\\!')) p = p.slice(1);
  p = p.replace(/\/+$/, ''); // directory-only pattern: counted as matching the name too
  if (p.startsWith('/')) p = p.slice(1); // anchored at the package root, where `name` is
  while (p.startsWith('**/')) p = p.slice(3); // any depth, the root included
  if (p === '') return false;
  let re = '';
  for (let i = 0; i < p.length; i++) {
    const c = p[i];
    if (c === '\\' && i + 1 < p.length) {
      re += escapeRe(p[++i]);
    } else if (c === '*') {
      if (p[i + 1] === '*') { re += '.*'; i++; } else re += '[^/]*';
    } else if (c === '?') {
      re += '[^/]';
    } else if (c === '[') {
      const end = p.indexOf(']', i + 2);
      if (end === -1) { re += '\\['; continue; }
      let body = p.slice(i + 1, end);
      if (body.startsWith('!')) body = `^${body.slice(1)}`;
      re += `[${body.replace(/\\/g, '\\\\')}]`;
      i = end;
    } else {
      re += escapeRe(c);
    }
  }
  return new RegExp(`^${re}(?:/.*)?$`, 'i').test(name);
}

// Conservative reading of one .vercelignore line: it ignores `name` if the
// line matches in any plausible reading (as written minus trailing blanks, or
// fully trimmed).
function ignoreLineMatches(line, name) {
  const forms = new Set([line.replace(/\r$/, '').replace(/[ \t]+$/, ''), line.trim()]);
  return [...forms].some((p) => globMatches(p, name));
}

// Ordered gitignore evaluation with "!" re-includes, for the files that must
// stay OUT of the upload.
function isIgnored(lines, name) {
  let ignored = false;
  for (const line of lines) {
    const t = line.trim();
    if (t.startsWith('!')) {
      if (ignoreLineMatches(t.slice(1), name)) ignored = false;
    } else if (ignoreLineMatches(line, name)) {
      ignored = true;
    }
  }
  return ignored;
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
// Routes routing-utils generates itself (trailingSlash, cleanUrls) come
// first. There must be none; the offset keeps the other tests pointed at the
// right rule if a planted defect adds one.
const GENERATED = routes.length - redirects.length;

test(`compile with ${engineName}`, (t) => {
  t.diagnostic(`engine: ${engineName}`);
  t.diagnostic(`config: ${CONFIG_FILE}`);
  assert.equal(compiled.error, null, `routing-utils rejected the config: ${JSON.stringify(compiled.error)}`);
  assert.equal(routes.length, redirects.length, 'exactly one compiled route per redirect: nothing generated (no trailingSlash or cleanUrls route)');
});

test('minimal matcher compiles this config to the identical route list', (t) => {
  if (!realEngine) {
    t.skip('no routing-utils available; the minimal matcher is the engine');
    return;
  }
  const minimal = minimalEngine.getTransformedRoutes(structuredClone(config)).routes.map(normalizeRoute);
  assert.deepEqual(minimal, routes);
});

test('config holds only permanent redirects: no trailingSlash, cleanUrls, rewrites or headers', () => {
  assert.deepEqual(Object.keys(config).sort(), ['$schema', 'redirects']);
  assert.equal(config.trailingSlash, undefined, 'trailingSlash compiles to a relative Location ("/$1"); it must stay out');
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
    assert.equal(new URL(r.destination.replace(/:[A-Za-z_]\w*(\(\.\*\))?[*+?]?/g, 'x')).host, APP_HOST);
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

test('explicit shared-route rules: each is its own rule, same path, ahead of the catch-all', () => {
  const catchAll = redirects.length - 1;
  for (const source of SHARED_RULES) {
    const at = redirects.map((r, i) => (r.source === source ? i : -1)).filter((i) => i !== -1);
    assert.equal(at.length, 1, `vercel.json has exactly one rule with source ${source}`);
    const i = at[0];
    assert.equal(redirects[i].destination, `${APP}${source}`, `${source} -> the same path on the app host`);
    assert.ok(i < catchAll, `${source} comes before the catch-all`);
    const sample = sampleFor(source);
    for (const opts of EDGE_VARIANTS) {
      assert.equal(respond(routes, sample, opts).route, i + GENERATED, `${sample} is answered by its own rule, not the catch-all ${JSON.stringify(opts)}`);
    }
  }
});

test('compiled routes: every one is a 308 whose Location is absolute on https://app.snatchitapp.com/', () => {
  assert.ok(routes.length > 0);
  for (const r of routes) {
    assert.equal(r.status, 308, `308: ${r.src}`);
    assert.ok(r.headers && typeof r.headers.Location === 'string', `Location: ${r.src}`);
    for (const k of ['continue', 'dest', 'has', 'missing', 'handle', 'check']) {
      assert.equal(r[k], undefined, `${k} must not be set: ${r.src}`);
    }
    const loc = r.headers.Location;
    let u = null;
    try { u = new URL(loc.replace(/\$\d+/g, 'x')); } catch { /* relative: no base given on purpose */ }
    assert.ok(u, `Location must be an absolute URL, not relative: ${JSON.stringify(loc)} (${r.src})`);
    assert.ok(loc.startsWith(`${APP}/`), `Location starts with ${APP}/: ${loc}`);
    assert.equal(u.protocol, 'https:', loc);
    assert.equal(u.host, APP_HOST, loc);
    assert.equal(`${u.username}${u.password}`, '', loc);
  }
});

test('no rule is shadowed by an earlier rule', () => {
  redirects.forEach((r, i) => {
    const samples = [sampleFor(r.source)];
    if (r.source.endsWith(OPTIONAL_SLASH)) samples.push(`${samples[0]}/`);
    for (const sample of samples) {
      for (const opts of EDGE_VARIANTS) {
        assert.equal(respond(routes, sample, opts).route, i + GENERATED, `${sample} must hit rule ${i} (${r.source}) ${JSON.stringify(opts)}`);
      }
    }
  });
});

function hostileSamples() {
  const listed = readHeredoc('HOSTILE');
  for (const s of HOSTILE_REQUIRED) assert.ok(listed.includes(s), `verify.sh HOSTILE lists ${JSON.stringify(s)}`);
  return [...new Set([...HOSTILE_REQUIRED, ...HOSTILE_EXTRA, ...listed])];
}

test('slash merge model reproduces every live observation (LIVE_MERGE)', () => {
  const wrong = LIVE_MERGE
    .map(([target, want]) => {
      const { pathname, query } = splitUrl(target);
      return { target, want, got: slashMerge(pathname, query, 'live') };
    })
    .filter(({ want, got }) => want !== got)
    .map(({ target, want, got }) => `${JSON.stringify(target)}: live ${JSON.stringify(want)}, model ${JSON.stringify(got)}`);
  assert.deepEqual(wrong, []);
  for (const s of HOSTILE_REQUIRED) {
    if (s.includes('\\') && splitUrl(s).pathname.includes('//')) {
      assert.ok(LIVE_MERGE.some(([t]) => t === s), `${JSON.stringify(s)} has a live observation`);
    }
  }
});

test('hostile paths: the final URL is on app.snatchitapp.com, never another host', () => {
  const samples = hostileSamples();
  const runs = [];
  for (const s of samples) {
    for (const opts of EDGE_VARIANTS) runs.push({ s, opts, res: follow(routes, s, opts) });
  }
  // The property first, over every sample and variant at once, so a failure
  // lists every path that ends somewhere other than the app host.
  const offHost = runs
    .filter(({ res }) => !res.url || res.url.host !== APP_HOST || res.url.protocol !== 'https:')
    .map(({ s, opts, res }) => `${JSON.stringify(s)} -> ${res.final} ${JSON.stringify(opts)}: ${res.trace}`);
  assert.deepEqual(offHost, [], `paths whose final URL is not on https://${APP_HOST}/`);
  for (const { s, opts, res } of runs) {
    const where = `${JSON.stringify(s)} ${JSON.stringify(opts)}: ${res.trace}`;
    assert.ok(res.statuses.every((x) => x === 308), `all 308: ${where}`);
    assert.ok(res.hops.length <= 2, `at most the slash merge and one rule: ${where}`);
    for (const h of res.hops) {
      if (h.route === 'merge') {
        assert.equal(h.url.origin, LEGACY, `the slash merge stays on the legacy host: ${where}`);
      } else {
        assert.ok(h.location.startsWith(`${APP}/`), `a rule's Location is absolute on the app host: ${where}`);
      }
    }
  }
});

test('counterfactual: a slash merge that kept "\\" raw would send the backslash samples to evil.example, before any rule', () => {
  // Not a variant of the edge (the live merge writes "%5C"); this pins why
  // verify.sh resolves every hop with the WHATWG parser, and proves the
  // backslash samples are not vacuous.
  const samples = hostileSamples();
  const expected = samples.filter((s) => /^\/[\\/]*\\/.test(slashMerge(splitUrl(s).pathname, null, 'raw') ?? '')).sort();
  assert.ok(expected.includes('//\\evil.example') && expected.includes('/\\//evil.example/'), `both review samples are sensitive: ${expected}`);
  for (const live of EDGE_VARIANTS.filter((o) => o.merge === 'live')) {
    const opts = { ...live, merge: 'raw' };
    const runs = samples.map((s) => ({ s, res: follow(routes, s, opts) }));
    const off = runs.filter(({ res }) => !res.url || res.url.host !== APP_HOST);
    assert.deepEqual(off.map(({ s }) => s).sort(), expected, `off-host under a raw merge ${JSON.stringify(opts)}`);
    for (const { s, res } of off) {
      assert.equal(res.hops.length, 1, `left at the first hop: ${s}: ${res.trace}`);
      assert.equal(res.hops[0].route, 'merge', `the merge, not a rule, sent it off-host: ${s}: ${res.trace}`);
      assert.equal(res.url.host, 'evil.example', `${s}: ${res.trace}`);
    }
  }
});

test('slash merge re-encodes the query; every well-formed parameter arrives unchanged', () => {
  const queries = ['next=//evil.example', 'q=a+b&c=d:e@f', 'x=\\y', 'a=1&a=2', 'a&b=', "a=!'()*~;,$", 'q=a%20b&next=%2Faccount',
    'a=%E2%80%94', 'a=b%3Dc%26d', 'client=app'];
  const paths = ['//', '//login', '/login//', '//settings/legal', '//my-listings/', '/bid//abc-123', '//zz/unknown'];
  for (const p of paths) {
    for (const q of queries) {
      const want = [...new URLSearchParams(q)];
      for (const opts of EDGE_VARIANTS) {
        const res = follow(routes, `${p}?${q}`, opts);
        const where = `${p}?${q} ${JSON.stringify(opts)}: ${res.trace}`;
        assert.equal(res.url.host, APP_HOST, where);
        assert.deepEqual([...res.url.searchParams], want, `parameters: ${where}`);
      }
    }
  }
});

test('verify.sh resolves every Location with the WHATWG parser and has a minimum-row guard', () => {
  const sh = fs.readFileSync(path.join(HERE, 'verify.sh'), 'utf8');
  assert.match(sh, /new URL\(process\.argv\[1\], process\.argv\[2\]\)/, 'resolve() uses new URL(location, base)');
  assert.doesNotMatch(sh, /urljoin|python3/, 'no RFC 3986 resolver (it reads "\\" as a path character)');
  assert.doesNotMatch(sh, /sed -e 's#\/\/\*#\/#g'/, 'no textual slash-merge exemption');
  const min = (name) => Number((new RegExp(`^${name}=(\\d+)$`, 'm').exec(sh) || [])[1]);
  assert.equal(min('MIN_MATRIX_ROWS'), 30);
  assert.equal(min('MIN_HOSTILE_ROWS'), 4);
  assert.ok(readMatrix().length >= min('MIN_MATRIX_ROWS'), 'the matrix clears the guard');
  assert.ok(readHeredoc('HOSTILE').length >= min('MIN_HOSTILE_ROWS'), 'the hostile list clears the guard');
});

test('verify.sh matrix: every row lands where the matrix says, one absolute 308', () => {
  const rows = readMatrix();
  assert.ok(rows.length >= 30, `matrix has ${rows.length} rows`);
  for (const row of rows) {
    assert.ok(!row.path.includes('//'), `matrix rows avoid "//" (the slash merge adds a hop): ${row.path}`);
    const want = `${APP}${row.final}`;
    for (const opts of EDGE_VARIANTS) {
      const res = follow(routes, row.path, opts);
      const where = `${row.path} ${JSON.stringify(opts)}: ${res.trace}`;
      assert.ok(res.hops[0].location && res.hops[0].location.startsWith(`${APP}/`), `first Location absolute on the app host: ${where}`);
      assert.equal(res.location, want, `raw Location: ${where}`);
      assert.equal(res.final, want, `resolved: ${where}`);
      assert.equal(res.hops.length, row.hops, `hops: ${where}`);
      assert.ok(res.statuses.every((s) => s === 308), `all 308: ${where}`);
    }
  }
});

test('verify.sh matrix covers every rule, "/", query and trailing-slash cases', () => {
  const rows = readMatrix();
  const hit = new Set(rows.map((row) => respond(routes, row.path, EDGE_VARIANTS[0]).route));
  routes.forEach((r, i) => assert.ok(hit.has(i), `no matrix row exercises route ${i} (${r.src})`));
  assert.ok(rows.some((r) => r.path === '/'), 'row for "/"');
  assert.ok(rows.filter((r) => r.path.includes('?')).length >= 6, 'query rows');
  const slashed = rows.filter((r) => /.\/(\?|$)/.test(r.path));
  assert.ok(slashed.some((r) => !/\/(\?|$)/.test(r.final)), 'a trailing-slash row a legacy-only rule maps away');
  assert.ok(slashed.some((r) => r.final === r.path), 'a trailing-slash row that keeps the slash on the app host');
});

test('every legacy Expo route lands on an existing app-host page', () => {
  for (const [file, want] of Object.entries(LEGACY_ROUTES)) {
    const url = legacyUrlFor(file);
    const expected = fillParams(want);
    assert.ok(appRouteExists(expected), `${expected} is a page on the app host`);
    for (const opts of EDGE_VARIANTS) {
      for (const suffix of ['', '?x=1', '/', '/?x=1']) {
        if (url === '/' && suffix.startsWith('/')) continue;
        const res = follow(routes, url + suffix, opts);
        const where = `${file}: ${url}${suffix} ${JSON.stringify(opts)}: ${res.trace}`;
        assert.ok(res.url, where);
        assert.equal(res.url.origin, APP, `leaves for the app host: ${where}`);
        assert.equal(appHostNormalise(res.url.pathname), expected, `lands on ${expected}: ${where}`);
        assert.equal(res.url.search, suffix.endsWith('?x=1') ? '?x=1' : '', `query kept as is: ${where}`);
      }
    }
  }
});

test('query string is passed through byte for byte and nothing is added', () => {
  const queries = [null, 'client=app', 'client=web&x=1', 'q=a%20b&next=%2Faccount', 'a=1&a=2', 'a=', 'utm_source=x&utm_medium=y'];
  const paths = ['/', '/payout-return', '/payout-refresh', '/login', '/login/', '/bid/abc-123', '/settings/legal', '/settings/legal/', '/my-listings', '/zz/unknown/path'];
  for (const p of paths) {
    for (const q of queries) {
      const rel = q === null ? p : `${p}?${q}`;
      for (const opts of EDGE_VARIANTS) {
        const res = follow(routes, rel, opts);
        const i = res.location.indexOf('?');
        assert.equal(i === -1 ? null : res.location.slice(i + 1), q, `raw Location: ${rel} -> ${res.location}`);
        assert.equal(res.url.search, q ? `?${q}` : '', `resolved: ${rel} -> ${res.final}`);
      }
    }
  }
});

test('every path on the legacy host leaves for the app host (whole-host)', () => {
  const samples = ['/', '/a', '/a/b/c', '/a/', '/a//b', '//', '/index.html', '/vercel.json', '/_expo/static/js/web/x.js',
    '/favicon.ico', '/robots.txt', '/sitemap.xml', '/SETTINGS/legal', '/Login', '/settings/legal/extra', '/listing/a/b',
    '/settings//legal', '/my-listings//', '/%E2%80%94', '/a%2Fb', '/..', '/a/../b', '/\\', '//\\', '/a|b', '//a|b'];
  for (const s of samples) {
    for (const opts of EDGE_VARIANTS) {
      const res = follow(routes, s, opts);
      const where = `${s} ${JSON.stringify(opts)}: ${res.trace}`;
      assert.ok(res.url && res.url.host === APP_HOST, where);
      assert.ok(res.hops.length <= 2 && res.statuses.every((x) => x === 308), where);
      for (const h of res.hops) {
        if (h.route !== 'merge') assert.ok(h.location.startsWith(`${APP}/`), `rule Location absolute: ${where}`);
      }
    }
  }
});

test('.vercelignore evaluator: planted lines that would drop vercel.json or index.html are caught', () => {
  const dropsVercelJson = ['*', '**', '*.json', 'vercel.*', 'VERCEL.JSON', '/vercel.json', '**/vercel.json', 'vercel.json/',
    '[v]ercel.json', '[!x]ercel.json', 'vercel.jso?', '  vercel.json', 'vercel.json  ', 'vercel.json', '\\vercel.json', '*cel*'];
  const dropsIndexHtml = ['*.html', 'index.*', 'index.htm?', '*.htm*', '**/*.html', 'INDEX.HTML', '/index.html', 'index.html'];
  const harmless = ['', '# vercel.json', '!vercel.json', '!index.html', 'README.md', 'verify.sh', '*.test.mjs', '.vercel', '.DS_Store',
    'docs/vercel.json', 'sub/**', '*.md', '.*', 'vercel.json.bak', 'index.html~', '[x]ercel.json'];
  for (const l of dropsVercelJson) assert.ok(ignoreLineMatches(l, 'vercel.json'), `caught: ${JSON.stringify(l)} drops vercel.json`);
  for (const l of dropsIndexHtml) assert.ok(ignoreLineMatches(l, 'index.html'), `caught: ${JSON.stringify(l)} drops index.html`);
  for (const l of harmless) {
    assert.ok(!ignoreLineMatches(l, 'vercel.json') && !ignoreLineMatches(l, 'index.html'), `not a false alarm: ${JSON.stringify(l)}`);
  }
  assert.ok(isIgnored(['README.md'], 'README.md'));
  assert.ok(!isIgnored(['README.md', '!README.md'], 'README.md'), 'a later "!" re-includes');
});

test('package hygiene: files, .vercelignore keeps exactly vercel.json and index.html, fallback page', () => {
  const files = fs.readdirSync(HERE).filter((f) => f !== '.DS_Store').sort();
  assert.deepEqual(files, [...PACKAGE_FILES].sort(), 'no extra files (no package.json, no .vercel link)');
  const lines = fs.readFileSync(path.join(HERE, '.vercelignore'), 'utf8').split('\n');
  for (const keep of ['vercel.json', 'index.html']) {
    for (const line of lines) {
      assert.ok(!ignoreLineMatches(line, keep), `.vercelignore line ${JSON.stringify(line)} would keep ${keep} out of the upload`);
    }
  }
  for (const drop of ['README.md', 'verify.sh', 'redirects.test.mjs', '.vercel', '.DS_Store']) {
    assert.ok(isIgnored(lines, drop), `.vercelignore keeps ${drop} out of the upload`);
  }
  assert.ok(fs.statSync(path.join(HERE, 'verify.sh')).mode & 0o100, 'verify.sh is executable');

  const html = fs.readFileSync(path.join(HERE, 'index.html'), 'utf8');
  assert.match(html, /<meta name="robots" content="noindex">/);
  assert.match(html, /<a href="https:\/\/app\.snatchitapp\.com\/">/);
  assert.doesNotMatch(html, /<script|http-equiv="refresh"/i, 'plain link only');
  assert.doesNotMatch(html, /—|--/, 'no em dash or "--"');
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
