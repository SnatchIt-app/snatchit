/**
 * tests/helpers/edge-vm.ts — load a REAL Supabase Edge Function handler
 * (Deno, https imports) into a Node vm for vitest, with mocked I/O.
 *
 * Why: the edge handlers are the code that actually moves money, but their
 * URL imports (`https://deno.land/...`, `https://esm.sh/...`) cannot be
 * resolved by vitest. The audit's reproduce.cjs proved the pattern: strip the
 * import statements, transpile the TypeScript, and evaluate the module in a
 * vm whose globals supply exactly the names the imports would have bound.
 * The handler under test is the genuine source file — not a simplified copy.
 *
 * What is mocked (and recorded): the supabase-js client (query builder + rpc
 * + auth + storage), `stripeFetch`/`stripeFetchRaw`, `captureException`,
 * `Deno.env`, `console`. Pure `_shared` modules (money, payout-logic,
 * payout-policy) are the REAL modules, imported by vitest.
 *
 * Nothing here talks to a network, a database, or a real Stripe key.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHmac, webcrypto } from 'node:crypto';
import vm from 'node:vm';
import ts from 'typescript';

export const REPO_ROOT = resolve(__dirname, '..', '..');

// ── Supabase client mock ─────────────────────────────────────────────────

export interface QueryCall {
  table: string;
  op: 'select' | 'insert' | 'update' | 'upsert' | 'delete';
  body: unknown;
  /** every filter in call order: ['eq','status','succeeded'], ['neq',...], ['in',...], ['or', expr], ['is',...], ['gt',...], ['lt',...] */
  filters: Array<[string, ...unknown[]]>;
  select: string | null;
  terminal: 'single' | 'maybeSingle' | 'list';
  limit: number | null;
  order: Array<[string, unknown]>;
  schema: string | null;
}
export type TableHandler = (q: QueryCall) => { data?: unknown; error?: { message: string; code?: string } | null; count?: number } | Promise<{ data?: unknown; error?: { message: string; code?: string } | null; count?: number }>;
export type RpcHandler = (name: string, params: Record<string, unknown>, schema: string | null) => { data?: unknown; error?: { message: string; code?: string } | null } | Promise<{ data?: unknown; error?: { message: string; code?: string } | null }>;

export interface MockSupabaseOptions {
  tables?: Record<string, TableHandler>;
  rpc?: RpcHandler;
  /** what `auth.getUser(token)` returns; default: a fixed user */
  user?: { id: string; email?: string } | null;
  storage?: Record<string, { list?: (prefix: string) => unknown[]; remove?: (paths: string[]) => void }>;
}

export interface MockSupabase {
  client: unknown;
  /** every query awaited, in order */
  queries: QueryCall[];
  /** every rpc call, in order */
  rpcs: Array<{ name: string; params: Record<string, unknown>; schema: string | null }>;
  /** createClient invocations (url, key, options) — to assert which credential/schema a path used */
  clients: Array<{ key: string; schema: string | null; authHeader: string | null }>;
}

export function mockSupabase(opts: MockSupabaseOptions = {}): MockSupabase {
  const queries: QueryCall[] = [];
  const rpcs: MockSupabase['rpcs'] = [];
  const clients: MockSupabase['clients'] = [];

  function makeClient(schema: string | null): unknown {
    const from = (table: string) => {
      const q: QueryCall = { table, op: 'select', body: undefined, filters: [], select: null, terminal: 'list', limit: null, order: [], schema };
      const b: Record<string, unknown> = {};
      const chain = (fn: () => void) => (...a: unknown[]) => { fn.call(null, ...(a as [])); return b; };
      b.select = (cols?: string) => { if (q.op === 'select' || q.select === null) q.select = cols ?? '*'; return b; };
      for (const op of ['insert', 'update', 'upsert', 'delete'] as const) {
        b[op] = (body?: unknown) => { q.op = op; q.body = body; return b; };
      }
      for (const f of ['eq', 'neq', 'in', 'is', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'contains', 'not', 'or', 'filter', 'match']) {
        b[f] = (...a: unknown[]) => { q.filters.push([f, ...a]); return b; };
      }
      b.limit = (n: number) => { q.limit = n; return b; };
      b.order = (c: string, o?: unknown) => { q.order.push([c, o]); return b; };
      b.single = () => { q.terminal = 'single'; return b; };
      b.maybeSingle = () => { q.terminal = 'maybeSingle'; return b; };
      b.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => {
        queries.push(q);
        const h = opts.tables?.[table];
        const run = async () => {
          if (!h) return { data: q.terminal === 'list' ? [] : null, error: null };
          const r = await h(q);
          return { data: r.data ?? null, error: r.error ?? null, count: r.count };
        };
        return run().then(res, rej);
      };
      void chain;
      return b;
    };
    return {
      from,
      rpc: async (name: string, params: Record<string, unknown> = {}) => {
        rpcs.push({ name, params, schema });
        if (!opts.rpc) return { data: null, error: null };
        const r = await opts.rpc(name, params, schema);
        return { data: r.data ?? null, error: r.error ?? null };
      },
      auth: {
        getUser: async () => (opts.user === null ? { data: { user: null }, error: { message: 'invalid token' } } : { data: { user: opts.user ?? { id: 'user-1', email: 'u@example.test' } }, error: null }),
        admin: { deleteUser: async () => ({ error: null }) },
      },
      storage: {
        from: (bucket: string) => ({
          list: async (prefix: string) => ({ data: opts.storage?.[bucket]?.list?.(prefix) ?? [], error: null }),
          remove: async (paths: string[]) => { opts.storage?.[bucket]?.remove?.(paths); return { data: null, error: null }; },
        }),
      },
      schema: (s: string) => makeClient(s),
    };
  }

  const client = new Proxy({}, {
    // createClient(url, key, options) → a client; we record key + schema + auth header
    apply() { return makeClient(null); },
  });
  void client;

  return {
    client: (url: string, key: string, options?: { db?: { schema?: string }; global?: { headers?: Record<string, string> } }) => {
      const schema = options?.db?.schema ?? null;
      clients.push({ key: String(key), schema, authHeader: options?.global?.headers?.Authorization ?? null });
      return makeClient(schema);
    },
    queries,
    rpcs,
    clients,
  };
}

// ── Stripe transport mock ────────────────────────────────────────────────

export interface StripeCall { path: string; method: string; body: unknown; idempotencyKey: string | null }
export type StripeRoute = (call: StripeCall) => { ok: boolean; status?: number; data: unknown } | Promise<{ ok: boolean; status?: number; data: unknown }>;

export function mockStripe(route: StripeRoute) {
  const calls: StripeCall[] = [];
  const raw = async (path: string, init?: { method?: string; body?: unknown; idempotencyKey?: string }) => {
    const call = { path, method: init?.method ?? 'GET', body: init?.body ?? null, idempotencyKey: init?.idempotencyKey ?? null };
    calls.push(call);
    const r = await route(call);
    return { ok: r.ok, status: r.status ?? (r.ok ? 200 : 400), data: r.data };
  };
  const strict = async (path: string, init?: { method?: string; body?: unknown; idempotencyKey?: string }) => {
    const r = await raw(path, init);
    if (!r.ok) throw new Error(`Stripe ${path} failed: ${JSON.stringify(r.data)}`);
    return r.data;
  };
  return { calls, stripeFetchRaw: raw, stripeFetch: strict };
}

// ── Loader ───────────────────────────────────────────────────────────────

export interface LoadedEdge {
  /** the function passed to `serve()` */
  handler: (req: Request) => Promise<Response>;
  logs: Array<{ level: 'log' | 'warn' | 'error'; args: unknown[] }>;
  sentry: Array<{ tag: string; error: unknown; ctx: unknown }>;
}

export interface LoadEdgeOptions {
  /** every named import the file needs that is not supplied by default (serve, createClient, captureException, captureMessage, Deno) */
  provide?: Record<string, unknown>;
  env?: Record<string, string | undefined>;
  supabase: MockSupabase;
  /** used for `fetch` inside the handler (push notifications etc.); default: 200 {} */
  fetch?: typeof fetch;
}

const IMPORT_RE = /^import[\s\S]*?from\s+['"][^'"]+['"];[ \t]*$/gm;

export async function loadEdgeHandler(relPath: string, opts: LoadEdgeOptions): Promise<LoadedEdge> {
  const abs = resolve(REPO_ROOT, relPath);
  const source = readFileSync(abs, 'utf8');
  const needed = new Set<string>();
  for (const m of source.matchAll(IMPORT_RE)) {
    const inner = m[0].replace(/^import\s*/, '').replace(/\s*from[\s\S]*$/, '');
    const braces = inner.match(/\{([\s\S]*)\}/);
    if (braces) {
      const typeOnly = /^import\s+type\s/.test(m[0]);
      for (const part of braces[1].split(',')) {
        const trimmed = part.trim();
        if (!trimmed || typeOnly || /^type\s/.test(trimmed)) continue; // erased at transpile time
        const name = trimmed.split(/\s+as\s+/).pop()?.trim();
        if (name) needed.add(name);
      }
    }
  }
  const stripped = source.replace(IMPORT_RE, '');
  const js = ts.transpileModule(stripped, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None }, fileName: abs }).outputText;

  let handler: LoadedEdge['handler'] | undefined;
  const logs: LoadedEdge['logs'] = [];
  const sentry: LoadedEdge['sentry'] = [];
  const env = { ...opts.env };
  const provided: Record<string, unknown> = {
    serve: (f: LoadedEdge['handler']) => { handler = f; },
    createClient: opts.supabase.client,
    captureException: async (tag: string, error: unknown, ctx?: unknown) => { sentry.push({ tag, error, ctx }); },
    captureMessage: async (tag: string, error: unknown, _level?: unknown, ctx?: unknown) => { sentry.push({ tag, error, ctx }); },
    ...opts.provide,
  };
  for (const n of needed) {
    if (!(n in provided)) throw new Error(`edge-vm: ${relPath} imports '${n}' but the test did not provide it`);
  }
  const ctx: Record<string, unknown> = {
    ...provided,
    Deno: { env: { get: (k: string) => env[k] } },
    console: {
      log: (...a: unknown[]) => logs.push({ level: 'log', args: a }),
      warn: (...a: unknown[]) => logs.push({ level: 'warn', args: a }),
      error: (...a: unknown[]) => logs.push({ level: 'error', args: a }),
      info: (...a: unknown[]) => logs.push({ level: 'log', args: a }),
      debug: () => {},
    },
    Request, Response, Headers, URL, URLSearchParams, TextEncoder, TextDecoder, crypto: webcrypto, Date, JSON, Math, Promise, Error, Array, Object, String, Number, Boolean, Map, Set, RegExp, Symbol, Uint8Array, ArrayBuffer,
    setTimeout, clearTimeout, atob, btoa, structuredClone, encodeURIComponent, decodeURIComponent, parseInt, parseFloat, isNaN, isFinite,
    fetch: opts.fetch ?? (async () => new Response('{}', { status: 200 })),
  };
  vm.runInNewContext(js, ctx, { filename: abs });
  if (!handler) throw new Error(`edge-vm: ${relPath} never called serve()`);
  return { handler, logs, sentry };
}

// ── Request builders ─────────────────────────────────────────────────────

export function signedStripeWebhookRequest(secret: string, event: Record<string, unknown>, url = 'https://edge.test/stripe-webhook'): Request {
  const body = JSON.stringify(event);
  const t = Math.floor(Date.now() / 1000);
  const sig = createHmac('sha256', secret).update(`${t}.${body}`).digest('hex');
  return new Request(url, { method: 'POST', body, headers: { 'stripe-signature': `t=${t},v1=${sig}`, 'content-type': 'application/json' } });
}

export function authedJsonRequest(body: unknown, opts: { url?: string; token?: string; method?: string } = {}): Request {
  return new Request(opts.url ?? 'https://edge.test/fn', {
    method: opts.method ?? 'POST',
    body: JSON.stringify(body),
    headers: { authorization: `Bearer ${opts.token ?? 'test-jwt'}`, 'content-type': 'application/json', apikey: 'anon' },
  });
}

export async function json(res: Response): Promise<Record<string, unknown>> {
  const text = await res.text();
  try { return JSON.parse(text) as Record<string, unknown>; } catch { return { _raw: text }; }
}
