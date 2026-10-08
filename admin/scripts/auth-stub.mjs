#!/usr/bin/env node
// ============================================================================
// admin/scripts/auth-stub.mjs — TEST HARNESS ONLY. SYNTHETIC. NOT GoTrue.
//
// A zero-dependency Node script that emulates the slice of the Supabase API
// gateway the admin console uses, so the Next.js app can run locally against
// the Docker-free rehearsal Postgres (see admin/scripts/README.md):
//
//   /rest/v1/*        -> transparent proxy to PostgREST (default :3201)
//   /auth/v1/*        -> minimal GoTrue emulation (password login, refresh,
//                        user, logout, settings, jwks, TOTP MFA stubs)
//
// Fidelity limits (read before trusting anything):
//   * Passwords are plain text in ops_harness.accounts (fixtures.sql). Nothing
//     here is a credential store. Emails are *.example.test.
//   * MFA: every TOTP challenge is satisfied by the fixed code 123456
//     (HARNESS_MFA_CODE). No real TOTP. The QR "image" is a placeholder SVG.
//   * Sessions are stateless HS256 JWTs. Logout revocation and challenges live
//     in this process's memory only, so a restart forgets revocations (tokens
//     stay valid until exp) and pending challenges.
//   * Refresh tokens are signed blobs; rotation does not invalidate the old
//     token (no replay protection). Fine for a harness, wrong for production.
//   * Factor enrollments persist in ops_harness.factors (harness-only schema,
//     never part of supabase/migrations).
//
// Safety: binds 127.0.0.1 only, proxies only to a loopback PostgREST, and only
// talks to a loopback Postgres whose database name contains "rehears".
//
// Usage:
//   node auth-stub.mjs                 # serve (env below)
//   node auth-stub.mjs --mint anon     # print the harness anon JWT
//   node auth-stub.mjs --mint service_role
//   node auth-stub.mjs --mint user <uuid> <email> [aal1|aal2]
//
// Env: HARNESS_PORT=3202 HARNESS_POSTGREST_URL=http://127.0.0.1:3201
//      HARNESS_JWT_SECRET (>=32 chars) HARNESS_PUBLIC_URL=http://localhost:3202
//      HARNESS_PGHOST=127.0.0.1 HARNESS_PGPORT=5432 HARNESS_PGUSER=postgres
//      HARNESS_PGDATABASE=snatchit_rehearsal_admin HARNESS_PSQL=psql
//      HARNESS_JWT_TTL=3600 HARNESS_MFA_CODE=123456
// ============================================================================
import http from 'node:http';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';

// ---------------------------------------------------------------------------
// Config + safety preamble
// ---------------------------------------------------------------------------
const env = process.env;
const CFG = {
  port: Number(env.HARNESS_PORT || 3202),
  postgrestUrl: env.HARNESS_POSTGREST_URL || 'http://127.0.0.1:3201',
  publicUrl: env.HARNESS_PUBLIC_URL || `http://localhost:${env.HARNESS_PORT || 3202}`,
  secret: env.HARNESS_JWT_SECRET || 'snatchit-local-harness-jwt-secret-0000000000',
  pgHost: env.HARNESS_PGHOST || '127.0.0.1',
  pgPort: env.HARNESS_PGPORT || '5432',
  pgUser: env.HARNESS_PGUSER || 'postgres',
  pgDb: env.HARNESS_PGDATABASE || 'snatchit_rehearsal_admin',
  psql: env.HARNESS_PSQL || 'psql',
  ttl: Number(env.HARNESS_JWT_TTL || 3600),
  mfaCode: env.HARNESS_MFA_CODE || '123456',
};

function die(msg) {
  process.stderr.write(`[auth-stub] ABORT: ${msg}\n`);
  process.exit(1);
}
function isLoopbackHost(h) {
  return ['127.0.0.1', 'localhost', '::1', '[::1]'].includes(h);
}
if (CFG.secret.length < 32) die('HARNESS_JWT_SECRET must be at least 32 characters');
if (!isLoopbackHost(CFG.pgHost)) die(`HARNESS_PGHOST='${CFG.pgHost}' is not loopback`);
if (!/rehears/.test(CFG.pgDb)) die(`HARNESS_PGDATABASE='${CFG.pgDb}' must contain 'rehears'`);
if (!/^[a-z0-9_]+$/.test(CFG.pgDb)) die('HARNESS_PGDATABASE must be [a-z0-9_]');
{
  const u = new URL(CFG.postgrestUrl);
  if (!isLoopbackHost(u.hostname)) die(`HARNESS_POSTGREST_URL host '${u.hostname}' is not loopback`);
}

// Environment handed to psql: scrub anything that could steer it remote.
const PSQL_ENV = { ...env };
for (const k of [
  'SUPABASE_DB_URL', 'SUPABASE_DB_PASSWORD', 'SUPABASE_ACCESS_TOKEN', 'SUPABASE_PROJECT_ID',
  'SUPABASE_PROJECT_REF', 'SUPABASE_URL', 'DATABASE_URL', 'POSTGRES_URL',
  'POSTGRES_URL_NON_POOLING', 'POSTGRES_PRISMA_URL', 'PGSERVICE', 'PGSERVICEFILE',
  'PGPASSFILE', 'PGPASSWORD', 'PGSSLMODE', 'PGURL', 'PGDATABASE', 'PGHOST', 'PGPORT', 'PGUSER',
]) delete PSQL_ENV[k];
PSQL_ENV.PGCONNECT_TIMEOUT = '5';

// ---------------------------------------------------------------------------
// Postgres access via psql (no npm deps). Values go through psql variables and
// :'var' quoting, never string-concatenated into SQL.
// ---------------------------------------------------------------------------
async function q(sql, vars = {}) {
  const args = ['-X', '-q', '-tA', '-v', 'ON_ERROR_STOP=1',
    '-h', CFG.pgHost, '-p', CFG.pgPort, '-U', CFG.pgUser, '-d', CFG.pgDb];
  for (const [k, v] of Object.entries(vars)) {
    const s = String(v);
    if (/[\r\n\0]/.test(s)) throw new Error(`refusing control characters in variable ${k}`);
    args.push('-v', `${k}=${s}`);
  }
  // SQL goes in on stdin (not -c): psql only interpolates :'var' for -f/stdin.
  const stdout = await new Promise((resolve, reject) => {
    const child = spawn(CFG.psql, args, { env: PSQL_ENV, stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '', err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('error', reject);
    child.on('close', (code) => code === 0 ? resolve(out) : reject(new Error(`psql exit ${code}: ${err.trim()}`)));
    child.stdin.end(sql + '\n');
  });
  return stdout.split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

const ACCOUNT_SQL_BASE = `
  select row_to_json(x) from (
    select a.email, a.password_plain, a.user_id, a.aal, a.label,
           u.created_at, u.updated_at, u.email_confirmed_at,
           coalesce(u.raw_app_meta_data,'{}'::jsonb)  as app_metadata,
           coalesce(u.raw_user_meta_data,'{}'::jsonb) as user_metadata
      from ops_harness.accounts a
      join auth.users u on u.id = a.user_id`;

async function accountByEmail(email) {
  const rows = await q(`${ACCOUNT_SQL_BASE} where lower(a.email) = lower(:'email')) x`, { email });
  return rows[0] || null;
}
async function accountById(uid) {
  const rows = await q(`${ACCOUNT_SQL_BASE} where a.user_id = :'uid'::uuid) x`, { uid });
  return rows[0] || null;
}
async function factorsFor(uid) {
  return q(`select row_to_json(f) from (
              select id, friendly_name, factor_type, status, created_at, updated_at
                from ops_harness.factors where user_id = :'uid'::uuid order by created_at) f`, { uid });
}
async function factorInsert(f) {
  await q(`insert into ops_harness.factors (id, user_id, friendly_name, factor_type, status)
           values (:'id'::uuid, :'uid'::uuid, :'name', 'totp', 'unverified')`,
    { id: f.id, uid: f.user_id, name: f.friendly_name });
}
async function factorVerify(id) {
  await q(`update ops_harness.factors set status = 'verified', updated_at = now() where id = :'id'::uuid`, { id });
}
async function factorDelete(id, uid) {
  const rows = await q(`delete from ops_harness.factors f where f.id = :'id'::uuid and f.user_id = :'uid'::uuid
                        returning row_to_json(f)`, { id, uid });
  return rows.length;
}

// ---------------------------------------------------------------------------
// HS256 JWT (mirrors Supabase claim shape)
// ---------------------------------------------------------------------------
const b64u = (s) => Buffer.from(s).toString('base64url');
function hmac(data) {
  return crypto.createHmac('sha256', CFG.secret).update(data).digest('base64url');
}
function signJwt(payload) {
  const h = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64u(JSON.stringify(payload));
  return `${h}.${p}.${hmac(`${h}.${p}`)}`;
}
function verifyJwt(token) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const expected = hmac(`${parts[0]}.${parts[1]}`);
  const a = Buffer.from(parts[2]); const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  let header, payload;
  try {
    header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
    payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
  } catch { return null; }
  if (header.alg !== 'HS256') return null;
  if (typeof payload.exp === 'number' && payload.exp <= now()) return { payload, expired: true };
  return { payload, expired: false };
}
const now = () => Math.floor(Date.now() / 1000);
const ISS = `${CFG.publicUrl}/auth/v1`;

// Deterministic API keys (fixed iat so the string is stable across runs and can
// live in admin/.env.local.example-harness).
const KEY_IAT = 1756000000; // 2025-08-24T01:46:40Z
function mintApiKey(role) {
  return signJwt({ iss: 'supabase-harness', ref: 'local-harness', role, iat: KEY_IAT, exp: KEY_IAT + 10 * 365 * 86400 });
}

function accessTokenFor(acct, sess) {
  const iat = now();
  return signJwt({
    iss: ISS,
    sub: acct.user_id,
    aud: 'authenticated',
    exp: iat + CFG.ttl,
    iat,
    email: acct.email,
    phone: '',
    app_metadata: { provider: 'email', providers: ['email'], ...acct.app_metadata },
    user_metadata: acct.user_metadata,
    role: 'authenticated',
    aal: sess.aal,
    amr: sess.amr,
    session_id: sess.id,
    is_anonymous: false,
  });
}

// Refresh token: signed, self-describing blob {sid, uid, aal, amr, n}.
function mintRefresh(sess) {
  const body = b64u(JSON.stringify({ sid: sess.id, uid: sess.user_id, aal: sess.aal, amr: sess.amr, n: crypto.randomUUID() }));
  return `${body}.${hmac(`rt.${body}`)}`;
}
function parseRefresh(tok) {
  if (typeof tok !== 'string') return null;
  const [body, sig] = tok.split('.');
  if (!body || !sig) return null;
  const exp = hmac(`rt.${body}`);
  const a = Buffer.from(sig); const b = Buffer.from(exp);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try { return JSON.parse(Buffer.from(body, 'base64url').toString()); } catch { return null; }
}

// In-memory only (see fidelity notes).
const revokedSessions = new Set();
const challenges = new Map(); // challenge_id -> {factor_id, uid, exp}

// ---------------------------------------------------------------------------
// User JSON (GoTrue shape; supabase-js reads user.factors[].status for AAL)
// ---------------------------------------------------------------------------
async function userJson(acct) {
  const factors = await factorsFor(acct.user_id);
  const ts = acct.created_at;
  return {
    id: acct.user_id,
    aud: 'authenticated',
    role: 'authenticated',
    email: acct.email,
    email_confirmed_at: acct.email_confirmed_at || ts,
    phone: '',
    confirmed_at: acct.email_confirmed_at || ts,
    last_sign_in_at: new Date().toISOString(),
    app_metadata: { provider: 'email', providers: ['email'], ...acct.app_metadata },
    user_metadata: { ...acct.user_metadata, harness_label: acct.label },
    identities: [{
      identity_id: acct.user_id, id: acct.user_id, user_id: acct.user_id, provider: 'email',
      identity_data: { email: acct.email, email_verified: true, sub: acct.user_id },
      last_sign_in_at: ts, created_at: ts, updated_at: ts,
    }],
    factors,
    created_at: ts,
    updated_at: acct.updated_at || ts,
    is_anonymous: false,
  };
}

function newSession(acct, opts = {}) {
  const t = now();
  const aal = opts.aal || (acct.aal === 'aal2' ? 'aal2' : 'aal1');
  const amr = [{ method: 'password', timestamp: t }];
  if (aal === 'aal2') amr.unshift({ method: 'totp', timestamp: t });
  return { id: crypto.randomUUID(), user_id: acct.user_id, aal, amr };
}

async function sessionJson(acct, sess) {
  const token = accessTokenFor(acct, sess);
  return {
    access_token: token,
    token_type: 'bearer',
    expires_in: CFG.ttl,
    expires_at: now() + CFG.ttl,
    refresh_token: mintRefresh(sess),
    user: await userJson(acct),
    weak_password: null,
  };
}

// ---------------------------------------------------------------------------
// HTTP plumbing
// ---------------------------------------------------------------------------
function cors(req, res) {
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', req.headers['access-control-request-headers'] || '*');
  res.setHeader('Access-Control-Expose-Headers', '*');
  res.setHeader('Access-Control-Max-Age', '600');
  res.setHeader('X-Snatchit-Test-Harness', 'auth-stub; synthetic; not GoTrue');
}
function json(res, status, body, extra = {}) {
  const buf = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {
    'Content-Type': 'application/json;charset=UTF-8',
    'Content-Length': buf.length,
    'X-Supabase-Api-Version': '2024-01-01',
    ...extra,
  });
  res.end(buf);
}
// GoTrue 2024-01-01 error envelope: numeric code + string error_code + msg.
function authError(res, status, error_code, msg) {
  return json(res, status, { code: status, error_code, msg: `TEST HARNESS: ${msg}` });
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}
async function readJson(req) {
  const raw = await readBody(req);
  if (!raw.length) return {};
  try { return JSON.parse(raw.toString()); } catch { return {}; }
}
function bearer(req) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m ? m[1].trim() : null;
}
// Resolves the calling user from the Bearer token; writes the error itself.
async function requireUser(req, res) {
  const tok = bearer(req);
  if (!tok) { authError(res, 401, 'no_authorization', 'missing Authorization: Bearer <access_token>'); return null; }
  const v = verifyJwt(tok);
  if (!v) { authError(res, 401, 'bad_jwt', 'invalid JWT (wrong secret, malformed, or not HS256)'); return null; }
  if (v.expired) { authError(res, 401, 'bad_jwt', 'token is expired'); return null; }
  const p = v.payload;
  if (p.role !== 'authenticated' || !p.sub) { authError(res, 401, 'bad_jwt', 'not a user token'); return null; }
  if (revokedSessions.has(p.session_id)) { authError(res, 403, 'session_not_found', 'session was signed out'); return null; }
  const acct = await accountById(p.sub);
  if (!acct) { authError(res, 403, 'user_not_found', `no ops_harness.accounts row for ${p.sub}`); return null; }
  return { acct, claims: p };
}

// ---------------------------------------------------------------------------
// /rest/v1 proxy -> PostgREST
// ---------------------------------------------------------------------------
const PG_URL = new URL(CFG.postgrestUrl);
function proxyRest(req, res, url) {
  const path = url.pathname.replace(/^\/rest\/v1/, '') || '/';
  const headers = { ...req.headers };
  delete headers.host; delete headers.connection; delete headers['content-length'];
  headers.host = `${PG_URL.hostname}:${PG_URL.port}`;
  const opts = { hostname: PG_URL.hostname, port: PG_URL.port, method: req.method, path: path + url.search, headers };
  const up = http.request(opts, (ur) => {
    const h = { ...ur.headers };
    delete h['access-control-allow-origin'];
    res.writeHead(ur.statusCode, h);
    ur.pipe(res);
  });
  up.on('error', (e) => {
    json(res, 502, { code: 'HARNESS_UPSTREAM', message: `TEST HARNESS: PostgREST unreachable at ${CFG.postgrestUrl}: ${e.message}`, details: null, hint: 'run admin/scripts/local-stack.sh start' });
  });
  req.pipe(up);
}

// ---------------------------------------------------------------------------
// /auth/v1 routes
// ---------------------------------------------------------------------------
const PLACEHOLDER_QR = (label) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">` +
  `<rect width="200" height="200" fill="#fff"/><rect x="10" y="10" width="180" height="180" fill="none" stroke="#000" stroke-width="4"/>` +
  `<text x="100" y="80" font-family="monospace" font-size="14" text-anchor="middle">TEST HARNESS</text>` +
  `<text x="100" y="105" font-family="monospace" font-size="12" text-anchor="middle">${label}</text>` +
  `<text x="100" y="135" font-family="monospace" font-size="16" text-anchor="middle">code: ${CFG.mfaCode}</text></svg>`;

async function handleAuth(req, res, url) {
  const p = url.pathname.replace(/^\/auth\/v1/, '') || '/';
  const m = req.method;

  if (m === 'GET' && (p === '/health' || p === '/')) {
    return json(res, 200, { version: 'test-harness', name: 'auth-stub', description: 'TEST HARNESS — synthetic GoTrue subset, not for production' });
  }
  if (m === 'GET' && p === '/settings') {
    return json(res, 200, {
      external: { email: true, phone: false, anonymous_users: false },
      disable_signup: true, mailer_autoconfirm: true, phone_autoconfirm: false,
      sms_provider: '', saml_enabled: false, mfa_enabled: true,
      harness: 'TEST HARNESS — synthetic',
    });
  }
  if (m === 'GET' && p === '/.well-known/jwks.json') {
    // Empty key set: supabase-js getClaims() then falls back to GET /user for HS256.
    return json(res, 200, { keys: [] }, { 'Cache-Control': 'no-store' });
  }

  if (m === 'POST' && p === '/token') {
    const grant = url.searchParams.get('grant_type');
    const body = await readJson(req);
    if (grant === 'password') {
      const email = String(body.email || '').trim();
      const password = String(body.password || '');
      if (!email || !password) return authError(res, 400, 'validation_failed', 'email and password are required');
      let acct;
      try { acct = await accountByEmail(email); } catch (e) { return authError(res, 500, 'unexpected_failure', `fixture lookup failed (is fixtures.sql applied?): ${e.message}`); }
      if (!acct || acct.password_plain !== password) return authError(res, 400, 'invalid_credentials', 'Invalid login credentials');
      const sess = newSession(acct);
      log(`login ${acct.email} aal=${sess.aal}`);
      return json(res, 200, await sessionJson(acct, sess));
    }
    if (grant === 'refresh_token') {
      const rt = parseRefresh(body.refresh_token);
      if (!rt) return authError(res, 400, 'refresh_token_not_found', 'Invalid Refresh Token: Refresh Token Not Found');
      if (revokedSessions.has(rt.sid)) return authError(res, 400, 'refresh_token_already_used', 'session signed out');
      const acct = await accountById(rt.uid);
      if (!acct) return authError(res, 400, 'user_not_found', 'account gone');
      const sess = { id: rt.sid, user_id: rt.uid, aal: rt.aal, amr: rt.amr || [] };
      return json(res, 200, await sessionJson(acct, sess));
    }
    return authError(res, 400, 'unsupported_grant_type', `grant_type='${grant}' not emulated (password, refresh_token only)`);
  }

  if (p === '/user') {
    const u = await requireUser(req, res); if (!u) return;
    if (m === 'GET') return json(res, 200, await userJson(u.acct));
    if (m === 'PUT') return authError(res, 501, 'not_implemented', 'PUT /user (updateUser) not emulated');
  }

  if (m === 'POST' && p === '/logout') {
    const tok = bearer(req);
    const v = tok ? verifyJwt(tok) : null;
    if (v && v.payload && v.payload.session_id) revokedSessions.add(v.payload.session_id);
    res.writeHead(204); return res.end();
  }

  // ---- MFA -----------------------------------------------------------------
  if (p === '/factors' && m === 'GET') {
    const u = await requireUser(req, res); if (!u) return;
    return json(res, 200, await factorsFor(u.acct.user_id));
  }
  if (p === '/factors' && m === 'POST') {
    const u = await requireUser(req, res); if (!u) return;
    const body = await readJson(req);
    const type = body.factor_type || 'totp';
    if (type !== 'totp') return authError(res, 422, 'mfa_factor_type_not_supported', `factor_type '${type}' not emulated (totp only)`);
    const friendly = String(body.friendly_name || '').trim() || 'Authenticator';
    const existing = await factorsFor(u.acct.user_id);
    if (existing.some((f) => f.friendly_name === friendly)) {
      return authError(res, 422, 'mfa_factor_name_conflict', `a factor named '${friendly}' already exists for this user`);
    }
    const f = { id: crypto.randomUUID(), user_id: u.acct.user_id, friendly_name: friendly };
    await factorInsert(f);
    const issuer = body.issuer || 'Snatch It (TEST HARNESS)';
    const secret = 'HARNESSTESTSECRET234567';
    log(`mfa enroll ${u.acct.email} factor=${f.id}`);
    return json(res, 200, {
      id: f.id, type: 'totp', friendly_name: friendly,
      totp: {
        qr_code: PLACEHOLDER_QR(friendly),
        secret,
        uri: `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(u.acct.email)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}`,
      },
    });
  }
  let fm;
  if ((fm = /^\/factors\/([0-9a-f-]{36})$/.exec(p)) && m === 'DELETE') {
    const u = await requireUser(req, res); if (!u) return;
    const n = await factorDelete(fm[1], u.acct.user_id);
    if (!n) return authError(res, 404, 'mfa_factor_not_found', 'factor not found');
    return json(res, 200, { id: fm[1] });
  }
  if ((fm = /^\/factors\/([0-9a-f-]{36})\/challenge$/.exec(p)) && m === 'POST') {
    const u = await requireUser(req, res); if (!u) return;
    const factors = await factorsFor(u.acct.user_id);
    if (!factors.some((f) => f.id === fm[1])) return authError(res, 404, 'mfa_factor_not_found', 'factor not found for this user');
    const id = crypto.randomUUID();
    const exp = now() + 300;
    challenges.set(id, { factor_id: fm[1], uid: u.acct.user_id, exp });
    return json(res, 200, { id, type: 'totp', expires_at: exp });
  }
  if ((fm = /^\/factors\/([0-9a-f-]{36})\/verify$/.exec(p)) && m === 'POST') {
    const u = await requireUser(req, res); if (!u) return;
    const body = await readJson(req);
    const ch = challenges.get(String(body.challenge_id || ''));
    if (!ch || ch.factor_id !== fm[1] || ch.uid !== u.acct.user_id) {
      return authError(res, 422, 'mfa_challenge_expired', 'challenge not found (expired, wrong factor, or the stub was restarted)');
    }
    if (ch.exp < now()) { challenges.delete(body.challenge_id); return authError(res, 422, 'mfa_challenge_expired', 'MFA challenge expired'); }
    if (String(body.code || '') !== CFG.mfaCode) return authError(res, 422, 'mfa_verification_failed', `Invalid TOTP code entered (harness accepts ${CFG.mfaCode})`);
    challenges.delete(body.challenge_id);
    await factorVerify(fm[1]);
    // Mint an aal2 session carrying the original session_id (GoTrue keeps the
    // session and upgrades its AAL).
    const t = now();
    const sess = {
      id: u.claims.session_id || crypto.randomUUID(), user_id: u.acct.user_id, aal: 'aal2',
      amr: [{ method: 'totp', timestamp: t }, ...(Array.isArray(u.claims.amr) ? u.claims.amr.filter((a) => a.method !== 'totp') : [{ method: 'password', timestamp: u.claims.iat || t }])],
    };
    log(`mfa verified ${u.acct.email} -> aal2`);
    return json(res, 200, await sessionJson(u.acct, sess));
  }

  // Convenience mirror of what supabase-js computes client-side in
  // mfa.getAuthenticatorAssuranceLevel(): aal from the JWT, nextLevel = aal2 if
  // any verified factor, amr from the JWT. Not a real GoTrue endpoint.
  if (m === 'GET' && p === '/authenticator-assurance-level') {
    const u = await requireUser(req, res); if (!u) return;
    const factors = await factorsFor(u.acct.user_id);
    const currentLevel = u.claims.aal || null;
    const nextLevel = factors.some((f) => f.status === 'verified') ? 'aal2' : currentLevel;
    return json(res, 200, { currentLevel, nextLevel, currentAuthenticationMethods: u.claims.amr || [] });
  }

  return authError(res, 404, 'not_found', `${m} /auth/v1${p} is not emulated by the harness`);
}

// ---------------------------------------------------------------------------
function log(msg) { process.stdout.write(`[auth-stub ${new Date().toISOString()}] ${msg}\n`); }

async function serve() {
  const server = http.createServer(async (req, res) => {
    const started = Date.now();
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    cors(req, res);
    res.on('finish', () => log(`${req.method} ${url.pathname}${url.search ? '?' + url.searchParams.toString().slice(0, 80) : ''} -> ${res.statusCode} ${Date.now() - started}ms`));
    try {
      if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
      if (url.pathname.startsWith('/rest/v1')) return proxyRest(req, res, url);
      if (url.pathname.startsWith('/auth/v1')) return await handleAuth(req, res, url);
      if (url.pathname === '/' || url.pathname === '/health') {
        return json(res, 200, { harness: 'TEST HARNESS', synthetic: true, rest: `${CFG.publicUrl}/rest/v1 -> ${CFG.postgrestUrl}`, auth: `${CFG.publicUrl}/auth/v1 (stub)`, mfa_code: CFG.mfaCode });
      }
      return json(res, 501, { code: 'HARNESS_NOT_EMULATED', message: `TEST HARNESS: ${url.pathname} (storage/functions/realtime/graphql) is not emulated` });
    } catch (e) {
      log(`ERROR ${req.method} ${url.pathname}: ${e.stack || e}`);
      if (!res.headersSent) authError(res, 500, 'unexpected_failure', e.message);
      else res.end();
    }
  });
  server.listen(CFG.port, '127.0.0.1', () => {
    log(`TEST HARNESS auth-stub listening on http://127.0.0.1:${CFG.port} (public ${CFG.publicUrl})`);
    log(`proxy /rest/v1 -> ${CFG.postgrestUrl}; db ${CFG.pgUser}@${CFG.pgHost}:${CFG.pgPort}/${CFG.pgDb}; mfa code ${CFG.mfaCode}; jwt ttl ${CFG.ttl}s`);
  });
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => { log(`${sig} — shutting down`); server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 1000).unref(); });
}

// ---------------------------------------------------------------------------
const argv = process.argv.slice(2);
if (argv[0] === '--mint') {
  const what = argv[1];
  if (what === 'anon' || what === 'service_role') {
    process.stdout.write(mintApiKey(what) + '\n');
  } else if (what === 'user') {
    const [uid, email, aal = 'aal1'] = argv.slice(2);
    if (!uid || !email) die('usage: --mint user <uuid> <email> [aal1|aal2]');
    const acct = { user_id: uid, email, app_metadata: {}, user_metadata: {} };
    const sess = newSession({ ...acct, aal }, { aal });
    process.stdout.write(accessTokenFor(acct, sess) + '\n');
  } else {
    die('usage: --mint anon | service_role | user <uuid> <email> [aal]');
  }
} else if (argv.length) {
  die(`unknown args: ${argv.join(' ')}`);
} else {
  serve();
}
