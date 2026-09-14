#!/usr/bin/env node
// Venue dashboard slice 1 — automated acceptance runner (local rehearsal or the shared sandbox).
//
//   node venue/scripts/acceptance/accept.mjs --target local   --phase all
//   node venue/scripts/acceptance/accept.mjs --target sandbox --project-ref ofaidukbieeekqaboscm --phase preflight
//   VENUE_ACCEPT_WINDOW=W1 node venue/scripts/acceptance/accept.mjs --target sandbox --project-ref ofaidukbieeekqaboscm --window W1 --phase fixtures
//
// Phases (R = read-only, W = writes):
//   preflight R · apply W · verify-apply R · verify-exposure R · fixtures W · api R* · browser R* ·
//   precedence W · revocation W · cleanup W · postflight R · all (local target only)
//   R* = signs in the synthetic users and makes write ATTEMPTS that must be refused.
// Sandbox guard: every phase except preflight/verify-apply/verify-exposure/postflight needs
// --window <id> AND the same id in $VENUE_ACCEPT_WINDOW. Production is refused outright.
// Exposure of venue_api (PostgREST db_schemas) is NOT done by this kit: it is a separately
// authorized configuration step; verify-exposure only checks it (and that db_pre_request survived).
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { makeTarget, REPO, ROLES, assertUuid } from "./lib/target.mjs";
import { launchBrowser } from "./lib/cdp.mjs";

// ---------------------------------------------------------------- args
const argv = process.argv.slice(2);
const arg = (k, d) => {
  const i = argv.indexOf(`--${k}`);
  return i >= 0 ? argv[i + 1] : d;
};
const opts = {
  target: arg("target", "local"),
  phase: arg("phase", "preflight"),
  projectRef: arg("project-ref"),
  db: arg("db", "snatchit_rehears_venueapi_rc"),
  app: arg("app", "http://localhost:3300"),
  window: arg("window"),
  chrome: arg("chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
  out: arg("out"),
};
const OUT = opts.out ?? join(REPO, "venue/scripts/acceptance/.runs", opts.target);
mkdirSync(OUT, { recursive: true, mode: 0o700 });
const STATE = join(OUT, "state.json");
const BASELINE = join(OUT, "baseline.json");
const SQL = (f) => join(REPO, "venue/scripts/acceptance/sql", f);

const READ_ONLY = new Set(["preflight", "verify-apply", "verify-exposure", "postflight"]);
const target = makeTarget(opts);
function guard(phase) {
  if (target.name !== "sandbox" || READ_ONLY.has(phase)) return;
  if (!opts.window || process.env.VENUE_ACCEPT_WINDOW !== opts.window) {
    throw new Error(`REFUSING phase '${phase}' on the sandbox: needs --window <id> and VENUE_ACCEPT_WINDOW=<same id> (the scheduled acceptance window).`);
  }
}

// ---------------------------------------------------------------- results
const results = [];
function check(phase, id, ok, detail = "") {
  results.push({ phase, id, ok: !!ok, detail: typeof detail === "string" ? detail : JSON.stringify(detail) });
  console.log(`${ok ? "PASS" : "FAIL"}  ${phase.padEnd(15)} ${id}${detail && !ok ? `  — ${typeof detail === "string" ? detail : JSON.stringify(detail)}` : ""}`);
}
const saveJson = (file, v) => {
  writeFileSync(file, JSON.stringify(v, null, 2), { mode: 0o600 });
  chmodSync(file, 0o600);
};
const loadState = () => {
  if (!existsSync(STATE)) throw new Error(`no synthetic users recorded at ${STATE}; run --phase fixtures first`);
  return JSON.parse(readFileSync(STATE, "utf8"));
};

// ---------------------------------------------------------------- ids
const ID = {
  orgA: "5a4d0b0e-0000-4000-8000-00000000000a",
  orgB: "5a4d0b0e-0000-4000-8000-00000000000b",
  venA: "5a4d0b0e-0000-4000-8000-0000000000aa",
  venB: "5a4d0b0e-0000-4000-8000-0000000000bb",
  e1: "5a4d0b0e-0000-4000-8000-0000000000e1",
  e2: "5a4d0b0e-0000-4000-8000-0000000000e2",
  e3: "5a4d0b0e-0000-4000-8000-0000000000e3",
  f1: "5a4d0b0e-0000-4000-8000-0000000000f1",
  tPublic: "5a4d0b0e-0000-4000-8000-000000000011",
  tHidden: "5a4d0b0e-0000-4000-8000-000000000012",
  bPublic: "5a4d0b0e-0000-4000-8000-000000000021",
  bPresale: "5a4d0b0e-0000-4000-8000-000000000022",
};
const A = `/o/${ID.orgA}/v/${ID.venA}`;
const B = `/o/${ID.orgB}/v/${ID.venB}`;
const TITLE = { e1: "Hosted Acceptance Night A (synthetic, on sale)", e2: "Hosted Acceptance Draft A (synthetic)", e3: "Hosted Acceptance Night B (synthetic, announced)" };
const DENIED = "You don't have access to this.";
const NO_GRANT = "holds no staff or organization role at this venue";
const SIGN_IN = "Sign in to continue";

// ---------------------------------------------------------------- http helpers
async function rest(path, { token, method = "GET", body, profile = "venue_api", contentProfile, apikey = true } = {}) {
  const headers = { "Accept-Profile": profile };
  if (apikey) headers.apikey = target.anonKey;
  if (token) headers.Authorization = `Bearer ${token}`;
  if (method !== "GET") {
    headers["Content-Profile"] = contentProfile ?? profile;
    headers.Prefer = "return=representation";
  }
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(`${target.url}/rest/v1/${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {}
  return { status: res.status, json, text };
}
async function passwordToken(user) {
  const res = await fetch(`${target.url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: target.anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email: user.email, password: user.password }),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok || !j.access_token) throw new Error(`sign-in for ${user.email} failed: ${res.status}`);
  return j.access_token;
}
const jwtPart = (t, i) => JSON.parse(Buffer.from(t.split(".")[i], "base64url").toString("utf8"));
const ids = (rows, k) => (Array.isArray(rows) ? rows.map((r) => r[k]).sort() : rows);
const denied = (r) => [401, 403].includes(r.status) && r.json?.code === "42501";

// ---------------------------------------------------------------- phases
async function preflight() {
  const snap = target.sqlFile(SQL("preflight.sql"));
  if (snap.ledger_count === null) check("preflight", "local replay: no migration ledger to inspect (expected)", target.name === "local", "");
  else check("preflight", "076-092 recorded in the ledger, no duplicate versions", snap.ledger_076_092 === 17 && snap.ledger_dupes === 0, { ledger_count: snap.ledger_count, tip: snap.ledger_tip_timestamp, dupes: snap.ledger_dupes });
  check("preflight", "catalog/venue/kernel schemas present", ["catalog", "venue", "kernel"].every((s) => snap.schemas_present.includes(s)), snap.schemas_present);
  check("preflight", "no fixture-id collisions (5a4d0b0e-)", snap.fixture_id_collisions === 0, snap.fixture_id_collisions);
  check("preflight", "no leftover acceptance users", snap.acceptance_users === 0, snap.acceptance_users);
  check("preflight", "feature flags dark", snap.feature_flags.every((f) => f.v === false), snap.feature_flags);
  if (target.name === "sandbox") {
    check("preflight", "venue_api not yet applied (views 0, no ledger row)", snap.venue_api_views === 0 && snap.ledger_has_venue_api === 0, { views: snap.venue_api_views, ledger: snap.ledger_has_venue_api });
    const probe = await rest("nonexistent");
    check("preflight", "venue_api not exposed yet (406 PGRST106)", probe.status === 406 && probe.json?.code === "PGRST106", probe.text.slice(0, 160));
    const jwks = await fetch(`${target.url}/auth/v1/.well-known/jwks.json`).then((r) => r.json()).catch(() => null);
    snap.jwks_algs = jwks?.keys?.map((k) => k.alg ?? k.kty) ?? [];
    check("preflight", "JWKS reachable (records signing algorithm)", jwks !== null, snap.jwks_algs);
  }
  saveJson(BASELINE, snap);
  console.log(`baseline -> ${BASELINE}`);
}

function apply() {
  const mig = join(REPO, "supabase/migrations/20260910120000_venue_api_read_views.sql");
  const tmp = join(tmpdir(), `ledger_20260910120000_${process.pid}.sql`);
  writeFileSync(tmp, execFileSync("python3", [join(REPO, "venue/scripts/acceptance/ledger-row.py"), mig], { encoding: "utf8" }), { mode: 0o600 });
  try {
    target.execFile(mig);
    target.execFile(tmp);
  } finally {
    rmSync(tmp, { force: true });
  }
  check("apply", "migration + real-statement ledger row executed", true);
}

function verifyApply() {
  const v = target.sqlFile(SQL("verify-apply.sql"));
  check("verify-apply", "8 views", v.views === 8, v.view_names);
  check("verify-apply", "every view security_invoker + security_barrier", v.not_security_invoker.length === 0 && v.not_security_barrier.length === 0, v);
  check("verify-apply", "anon has no USAGE; authenticated has USAGE", v.anon_usage === false && v.authenticated_usage === true, v);
  check("verify-apply", "authenticated SELECT on all 8, no other client grants", v.authenticated_select_grants === 8 && v.non_select_grants_to_clients === 0 && v.anon_or_public_grants === 0, v);
  check("verify-apply", "no SECURITY DEFINER functions in venue_api", v.definer_functions_in_schema === 0, v);
  if (target.name === "sandbox") check("verify-apply", "ledger row 20260910120000 = venue_api_read_views with 24 statements", v.ledger_row_statements === 24 && v.ledger_row_name === "venue_api_read_views", { name: v.ledger_row_name, statements: v.ledger_row_statements });
}

async function verifyExposure() {
  const nx = await rest("nonexistent");
  check("verify-exposure", "venue_api exposed (missing relation -> 404, not 406)", nx.status === 404, nx.text.slice(0, 160));
  for (const p of ["catalog", "venue"]) {
    const r = await rest(p === "catalog" ? "event" : "staff_role", { profile: p });
    check("verify-exposure", `${p} still NOT exposed (406 PGRST106)`, r.status === 406 && r.json?.code === "PGRST106", r.text.slice(0, 160));
  }
  if (target.canInspectRoleSettings) {
    const base = existsSync(BASELINE) ? JSON.parse(readFileSync(BASELINE, "utf8")) : null;
    const now = target.sqlFile(SQL("preflight.sql"));
    const get = (arr, k) => (arr.find((s) => s.startsWith(`${k}=`)) ?? "").slice(k.length + 1);
    const schemas = get(now.authenticator_pgrst, "pgrst.db_schemas").split(",").map((s) => s.trim()).filter(Boolean);
    check("verify-exposure", "authenticator pgrst.db_schemas includes venue_api", schemas.includes("venue_api"), schemas);
    if (base) {
      const before = get(base.authenticator_pgrst, "pgrst.db_schemas").split(",").map((s) => s.trim()).filter(Boolean);
      check("verify-exposure", "no previously exposed schema was dropped", before.every((s) => schemas.includes(s)), { before, after: schemas });
      const hookBefore = get(base.authenticator_pgrst, "pgrst.db_pre_request");
      check("verify-exposure", "db_pre_request hook unchanged", get(now.authenticator_pgrst, "pgrst.db_pre_request") === hookBefore, { before: hookBefore, after: get(now.authenticator_pgrst, "pgrst.db_pre_request") });
    } else check("verify-exposure", "baseline present for before/after comparison", false, "run preflight before exposure");
  }
}

async function fixtures() {
  if (existsSync(STATE)) throw new Error(`state exists at ${STATE}; run cleanup first`);
  const users = {};
  try {
    for (const role of Object.keys(ROLES)) users[role] = await target.createUser(role);
  } finally {
    saveJson(STATE, { target: target.describe, createdAt: new Date().toISOString(), users });
  }
  const sql = readFileSync(SQL("fixtures.sql.tmpl"), "utf8")
    .replaceAll("{{MANAGER_A}}", assertUuid(users.manager.id, "manager"))
    .replaceAll("{{OWNER_A}}", assertUuid(users.owner.id, "owner"))
    .replaceAll("{{FINANCE_B}}", assertUuid(users.finance.id, "finance"));
  const r = target.sqlText(sql);
  check("fixtures", "2 orgs, 2 venues, 3 events, 3 sessions, 2 types, 2 batches, 2 staff, 1 member", r.orgs === 2 && r.venues === 2 && r.events === 3 && r.sessions === 3 && r.ticket_types === 2 && r.batches === 2 && r.staff_roles === 2 && r.org_members === 1, r);
  check("fixtures", "remaining computed 174 / 0", r.remaining?.[ID.bPublic] === 174 && r.remaining?.[ID.bPresale] === 0, r.remaining);
}

async function api() {
  const { users } = loadState();
  const T = {};
  for (const k of Object.keys(users)) T[k] = await passwordToken(users[k]);
  const P = "api";

  // Token premise: no venue/org role lives in the JWT.
  const claims = jwtPart(T.manager, 1);
  check(P, "H2 JWT role=authenticated, no venue/org role claim", claims.role === "authenticated" && !JSON.stringify(claims).match(/venue_(manager|finance|scanner)|org_owner/), Object.keys(claims));
  check(P, "H2 JWT header algorithm recorded", !!jwtPart(T.manager, 0).alg, jwtPart(T.manager, 0).alg);

  // C1 anon on all eight views.
  for (const v of ["venues", "events", "event_sessions", "resale_policies", "ticket_types", "inventory_batches", "my_staff_roles", "my_org_roles"]) {
    const r = await rest(`${v}?select=*&limit=1`);
    check(P, `C1 anon denied on venue_api.${v}`, denied(r) && !Array.isArray(r.json), `${r.status} ${r.text.slice(0, 120)}`);
  }
  if (target.name === "sandbox") {
    const r = await rest("events", { apikey: false });
    check(P, "C1 no apikey -> gateway 401", r.status === 401, r.status);
  }

  // H4 manager projection.
  let r = await rest(`events?venue_id=eq.${ID.venA}&select=event_id,status&order=event_id`, { token: T.manager });
  check(P, "H4 manager reads both Venue A events incl. draft", JSON.stringify(r.json) === JSON.stringify([{ event_id: ID.e1, status: "on_sale" }, { event_id: ID.e2, status: "draft" }]), r.text);
  r = await rest(`ticket_types?event_id=eq.${ID.e1}&select=ticket_type_id,visibility&order=ticket_type_id`, { token: T.manager });
  check(P, "H4 manager reads public + hidden ticket types", JSON.stringify(ids(r.json, "ticket_type_id")) === JSON.stringify([ID.tPublic, ID.tHidden]), r.text);
  r = await rest(`inventory_batches?event_session_id=eq.${ID.f1}&select=batch_id,remaining&order=batch_id`, { token: T.manager });
  check(P, "H4 manager reads remaining 174 / 0", JSON.stringify(r.json) === JSON.stringify([{ batch_id: ID.bPublic, remaining: 174 }, { batch_id: ID.bPresale, remaining: 0 }]), r.text);
  r = await rest("inventory_batches?select=capacity", { token: T.manager });
  check(P, "H4 capacity is not a column (42703)", r.status === 400 && r.json?.code === "42703", r.text.slice(0, 120));
  r = await rest("my_staff_roles", { token: T.manager });
  check(P, "H4 my_staff_roles = own venue_manager row only", JSON.stringify(r.json) === JSON.stringify([{ venue_id: ID.venA, role: "venue_manager" }]), r.text);
  r = await rest("my_org_roles", { token: T.manager });
  check(P, "H4 my_org_roles empty for manager", Array.isArray(r.json) && r.json.length === 0, r.text);

  // C2 write attempts (must all be refused; state verified afterwards).
  const writes = [
    ["POST", "events", { event_id: "5a4d0b0e-0000-4000-8000-0000000000e9", venue_id: ID.venA, org_id: ID.orgA, title: "WRITE PROBE", status: "draft" }],
    ["PATCH", `events?event_id=eq.${ID.e1}`, { title: "TAMPERED" }],
    ["DELETE", `inventory_batches?batch_id=eq.${ID.bPublic}`, undefined],
    ["POST", "my_staff_roles", { venue_id: ID.venB, role: "venue_manager" }],
    ["PATCH", `inventory_batches?batch_id=eq.${ID.bPublic}`, { release_kind: "presale" }],
  ];
  for (const [method, path, body] of writes) {
    const w = await rest(path, { token: T.manager, method, body, contentProfile: "venue_api" });
    check(P, `C2 ${method} ${path.split("?")[0]} refused (42501)`, denied(w), `${w.status} ${w.text.slice(0, 120)}`);
  }
  r = await rest("staff_role", { token: T.manager, method: "POST", body: {}, profile: "venue" });
  check(P, "C2 base schema venue not reachable (406 PGRST106)", r.status === 406 && r.json?.code === "PGRST106", r.text.slice(0, 120));
  r = await rest("rpc/grant_staff_role", { token: T.manager, method: "POST", body: {} });
  check(P, "C2 no RPC in venue_api (404)", r.status === 404, r.text.slice(0, 120));
  const after = target.sqlText(`select json_build_object(
    'titles', (select json_object_agg(event_id, title) from catalog.event where event_id::text like '5a4d0b0e-%'),
    'probe', (select count(*) from catalog.event where event_id = '5a4d0b0e-0000-4000-8000-0000000000e9'),
    'remaining', (select json_object_agg(batch_id, remaining) from venue.inventory_batch where batch_id::text like '5a4d0b0e-%'),
    'staff', (select count(*) from venue.staff_role where venue_id::text like '5a4d0b0e-%')) as j;`);
  check(P, "C2 nothing changed (titles, no probe row, remaining, grants)", after.titles[ID.e1] === TITLE.e1 && after.probe === 0 && after.remaining[ID.bPublic] === 174 && after.staff === 2, after);

  // H5 cross-tenant: finance at Venue B.
  r = await rest(`events?event_id=eq.${ID.e2}`, { token: T.finance });
  check(P, "H5 finance B cannot read Venue A draft", Array.isArray(r.json) && r.json.length === 0, r.text);
  r = await rest(`ticket_types?ticket_type_id=eq.${ID.tHidden}`, { token: T.finance });
  check(P, "H5 finance B cannot read Venue A hidden type", Array.isArray(r.json) && r.json.length === 0, r.text);
  r = await rest(`inventory_batches?batch_id=eq.${ID.bPresale}`, { token: T.finance });
  check(P, "H5 finance B cannot read Venue A presale batch", Array.isArray(r.json) && r.json.length === 0, r.text);
  r = await rest("my_staff_roles", { token: T.finance });
  check(P, "H5 finance my_staff_roles = Venue B only", JSON.stringify(r.json) === JSON.stringify([{ venue_id: ID.venB, role: "venue_finance" }]), r.text);

  // C3 outsider: grant views empty; only catalog-public rows (expected by design).
  r = await rest("my_staff_roles", { token: T.outsider });
  const r2 = await rest("my_org_roles", { token: T.outsider });
  check(P, "C3 outsider has no grants", Array.isArray(r.json) && !r.json.length && Array.isArray(r2.json) && !r2.json.length, `${r.text} ${r2.text}`);
  r = await rest(`events?venue_id=eq.${ID.venA}&select=event_id&order=event_id`, { token: T.outsider });
  check(P, "C3 outsider sees public event only (draft absent)", JSON.stringify(ids(r.json, "event_id")) === JSON.stringify([ID.e1]), r.text);
  r = await rest(`event_sessions?event_id=eq.${ID.e2}`, { token: T.outsider });
  check(P, "C3 outsider cannot read the draft's session", Array.isArray(r.json) && r.json.length === 0, r.text);
  r = await rest(`ticket_types?event_id=eq.${ID.e1}&select=ticket_type_id`, { token: T.outsider });
  check(P, "C3 outsider sees public type only (hidden absent)", JSON.stringify(ids(r.json, "ticket_type_id")) === JSON.stringify([ID.tPublic]), r.text);
  r = await rest(`inventory_batches?event_session_id=eq.${ID.f1}&select=batch_id`, { token: T.outsider });
  check(P, "C3 outsider sees public batch only (presale absent)", JSON.stringify(ids(r.json, "batch_id")) === JSON.stringify([ID.bPublic]), r.text);

  // C5 org owner through the org plane.
  r = await rest("my_org_roles", { token: T.owner });
  check(P, "C5 owner my_org_roles = org_owner @ Org A", JSON.stringify(r.json) === JSON.stringify([{ org_id: ID.orgA, role: "org_owner" }]), r.text);
  r = await rest(`events?venue_id=eq.${ID.venA}&select=event_id&order=event_id`, { token: T.owner });
  check(P, "C5 owner reads both Venue A events incl. draft", JSON.stringify(ids(r.json, "event_id")) === JSON.stringify([ID.e1, ID.e2]), r.text);
  r = await rest(`events?venue_id=eq.${ID.venB}&select=event_id`, { token: T.owner });
  check(P, "C5 owner sees Org B only as public (announced), never a grant", JSON.stringify(ids(r.json, "event_id")) === JSON.stringify([ID.e3]), r.text);
}

// ---- browser helpers
function authCookie(cookies) {
  const parts = cookies.filter((c) => /^sb-.+-auth-token(\.\d+)?$/.test(c.name));
  if (!parts.length) return null;
  const base = parts[0].name.replace(/\.\d+$/, "");
  const ordered = parts.filter((c) => c.name === base).concat(parts.filter((c) => c.name.startsWith(`${base}.`)).sort((a, b) => Number(a.name.split(".").pop()) - Number(b.name.split(".").pop())));
  const raw = ordered.map((c) => c.value).join("");
  const json = raw.startsWith("base64-") ? Buffer.from(raw.slice(7), "base64url").toString("utf8") : decodeURIComponent(raw);
  return { base, parts: ordered, session: JSON.parse(json), template: ordered[0] };
}
async function writeAuthCookie(page, ck, session) {
  const value = `base64-${Buffer.from(JSON.stringify(session)).toString("base64url")}`;
  for (const p of ck.parts) await page.deleteCookie(p.name, opts.app);
  const chunks = value.length <= 3180 ? [value] : value.match(/.{1,3180}/g);
  for (let i = 0; i < chunks.length; i++) {
    await page.setCookie({ name: chunks.length === 1 ? ck.base : `${ck.base}.${i}`, value: chunks[i], url: opts.app, path: "/", httpOnly: ck.template.httpOnly, secure: ck.template.secure, sameSite: ck.template.sameSite ?? "Lax", expires: ck.template.expires > 0 ? ck.template.expires : undefined });
  }
}
async function signIn(page, user, next) {
  await page.goto(`${opts.app}/login?next=${encodeURIComponent(next)}`);
  await page.fill('input[name="email"]', user.email);
  await page.fill('input[name="password"]', user.password);
  await page.click('button[type="submit"]');
  const left = await page.waitFor(`location.pathname !== '/login' || document.body.innerText.includes('Sign-in failed')`, 20000);
  await page.waitFor("document.readyState === 'complete'", 5000);
  return left && !(await page.text()).includes("Sign-in failed");
}
async function visit(page, path) {
  await page.goto(`${opts.app}${path}`);
  return page.text();
}

async function browser() {
  const { users } = loadState();
  const P = "browser";
  const br = await launchBrowser(opts.chrome);
  try {
    // Signed out, and the app must be in database mode against this target.
    const anon = await br.newPage();
    let t = await visit(anon, `${A}/events`);
    check(P, "H1 signed out -> Sign in to continue (database mode)", t.includes(SIGN_IN), t.slice(0, 200));
    check(P, "P1 signed out: no role label and no sample fixture names", !/Venue manager|Org owner|\(sample\)/.test(t), t.slice(0, 300));
    await anon.close();

    // Manager: real login, page content, projection, no write controls.
    const m = await br.newPage();
    check(P, "H1 manager signs in through /login", await signIn(m, users.manager, `${A}/events`), await m.url());
    t = await m.text();
    check(P, "H1 events list shows both Venue A events", t.includes(TITLE.e1) && t.includes(TITLE.e2), t.slice(0, 400));
    check(P, "H1 remaining-only figure (174 available)", t.includes("174 available"), t.slice(0, 400));
    check(P, "C5 strip derives Venue manager from grants", t.includes("Capabilities come from your grants") && t.includes("Venue manager"), t.slice(0, 300));
    check(P, "H1 header shows the signed-in email", t.includes(users.manager.email), t.slice(0, 300));
    check(P, "H1 Sign out offered", t.toLowerCase().includes("sign out"), "");
    check(P, "H1 no Create event control in database mode", !t.toLowerCase().includes("create event"), "");
    await m.screenshot(join(OUT, "evidence-manager-events.png"));
    t = await visit(m, `${A}/events/${ID.e1}`);
    check(P, "H1 event setup: both ticket types, no status writes", t.includes("General admission (synthetic)") && t.includes("Hidden early bird (synthetic)") && t.includes("Status changes are not available in database mode"), t.slice(0, 400));
    t = await visit(m, `${A}/events/${ID.e1}/inventory`);
    check(P, "H1 inventory: remaining-only note", t.includes("remaining") && !t.includes("venue.release_inventory_hold"), t.slice(0, 300));
    for (const sub of ["attendees", "door"]) {
      t = await visit(m, `${A}/events/${ID.e1}/${sub}`);
      check(P, `H1 ${sub}: not wired in database mode`, t.includes("not wired to the database yet"), t.slice(0, 200));
    }
    t = await visit(m, `${A}/events?role=org_owner&state=empty`);
    check(P, "C5 query-string role/state ignored", t.includes("Venue manager") && t.includes(TITLE.e1), t.slice(0, 300));

    // C4 malformed / foreign / non-existent ids.
    for (const [label, path, back] of [
      ["non-UUID org and venue", "/o/not-a-uuid/v/also-not-a-uuid/events", false],
      ["non-UUID venue", `/o/${ID.orgA}/v/not-a-uuid/events`, false],
      ["injection string", "/o/%27%20OR%201%3D1--/v/x/events", false],
      ["non-UUID event", `${A}/events/not-a-uuid`, true],
      ["Venue B event under Venue A", `${A}/events/${ID.e3}`, true],
      ["non-existent event", `${A}/events/00000000-0000-4000-8000-000000000000`, true],
    ]) {
      t = await visit(m, path);
      check(P, `C4 ${label} fails closed`, t.includes(DENIED) && !t.includes(TITLE.e3) && (!back || t.includes("Back to events")), t.slice(0, 200));
    }
    t = await visit(m, A.toUpperCase().replace("/O/", "/o/").replace("/V/", "/v/") + "/events");
    check(P, "C4 uppercase UUIDs: own venue or closed denial, never other data", (t.includes(TITLE.e1) || t.includes(DENIED)) && !t.includes(TITLE.e3), t.includes(TITLE.e1) ? "renders" : "denied");

    // H2 tampered access token is rejected.
    await visit(m, `${A}/events`);
    let ck = authCookie(await m.cookies(opts.app));
    check(P, "H2 session cookie present after login", !!ck, "");
    const good = ck.session;
    const bad = { ...good, access_token: good.access_token.slice(0, -4) + (good.access_token.endsWith("AAAA") ? "BBBB" : "AAAA"), expires_at: Math.floor(Date.now() / 1000) + 3000 };
    await writeAuthCookie(m, ck, bad);
    t = await visit(m, `${A}/events`);
    check(P, "H2 tampered token -> Sign in to continue, no data", t.includes(SIGN_IN) && !t.includes(TITLE.e1), t.slice(0, 200));

    // H3 refresh: force the session past expiry; the refreshed session must be persisted to the cookie.
    await m.close();
    const m2 = await br.newPage();
    await signIn(m2, users.manager, `${A}/events`);
    await new Promise((r) => setTimeout(r, 1100)); // a refresh in the same second as sign-in can re-mint an identical access JWT
    ck = authCookie(await m2.cookies(opts.app));
    const before = ck.session;
    await writeAuthCookie(m2, ck, { ...before, expires_at: Math.floor(Date.now() / 1000) - 120 });
    t = await visit(m2, `${A}/events`);
    check(P, "H3 expired session still renders data (refreshed)", t.includes(TITLE.e1), t.slice(0, 200));
    const afterCk = authCookie(await m2.cookies(opts.app));
    check(P, "H3 refreshed session persisted to the cookie (rotated refresh token, future expiry)", !!afterCk && afterCk.session.refresh_token !== before.refresh_token && afterCk.session.expires_at > Math.floor(Date.now() / 1000), afterCk ? { expires_at: afterCk.session.expires_at, access_changed: afterCk.session.access_token !== before.access_token, refresh_changed: afterCk.session.refresh_token !== before.refresh_token } : "cookie gone");
    // Hosted GoTrue revokes a reused refresh token once its reuse interval (10 s default) has passed, so on the
    // sandbox wait past it: a refresh that was not persisted would sign the user out here.
    if (target.name === "sandbox") await new Promise((r) => setTimeout(r, 12000));
    t = await visit(m2, `${A}/events`);
    check(P, `H3 next request ${target.name === "sandbox" ? "12 s later (past the refresh-token reuse interval)" : "after refresh"} still signed in`, t.includes(TITLE.e1), t.slice(0, 200));

    // H6 logout.
    await m2.click('form[action="/logout"] button');
    await m2.waitFor("location.pathname === '/login'", 15000);
    check(P, "H6 Sign out lands on /login", (await m2.url()).includes("/login"), await m2.url());
    check(P, "H6 auth cookie removed", !authCookie(await m2.cookies(opts.app)), "");
    t = await visit(m2, `${A}/events`);
    check(P, "H6 after sign-out -> Sign in to continue", t.includes(SIGN_IN), t.slice(0, 200));
    await m2.close();

    // H5 / C5 finance at Venue B.
    const f = await br.newPage();
    await signIn(f, users.finance, `${B}/events`);
    t = await f.text();
    check(P, "H5 finance sees Venue B event; strip = Venue finance", t.includes(TITLE.e3) && t.includes("Venue finance"), t.slice(0, 300));
    for (const [label, path] of [["events", `${A}/events`], ["draft", `${A}/events/${ID.e2}`], ["inventory", `${A}/events/${ID.e1}/inventory`]]) {
      t = await visit(f, path);
      check(P, `H5 finance denied at Venue A ${label}`, t.includes(DENIED) && t.includes(NO_GRANT) && !t.includes(TITLE.e2), t.slice(0, 200));
    }
    await f.screenshot(join(OUT, "evidence-finance-denied-at-A.png"));
    t = await visit(f, `${B}/events?role=org_owner`);
    check(P, "C5 finance cannot promote itself via ?role", t.includes("Venue finance") && !t.includes("Org owner"), t.slice(0, 300));
    await f.close();

    // C5 owner.
    const o = await br.newPage();
    await signIn(o, users.owner, `${A}/events`);
    t = await o.text();
    check(P, "C5 owner sees both A events; strip = Org owner", t.includes(TITLE.e1) && t.includes(TITLE.e2) && t.includes("Org owner"), t.slice(0, 300));
    t = await visit(o, `${B}/events`);
    check(P, "C5 owner denied at Venue B", t.includes(DENIED) && t.includes(NO_GRANT), t.slice(0, 200));
    await o.close();

    // C3 outsider + H7 no cross-user caching (two isolated sessions at once).
    const mgr = await br.newPage();
    const out = await br.newPage();
    await signIn(mgr, users.manager, `${A}/events`);
    await signIn(out, users.outsider, `${A}/events`);
    const [tm, to] = [await visit(mgr, `${A}/events`), await visit(out, `${A}/events`)];
    check(P, "H7 concurrent: manager sees A events", tm.includes(TITLE.e1), tm.slice(0, 200));
    check(P, "H7 concurrent: outsider sees denial, never A's rows", to.includes(DENIED) && to.includes(NO_GRANT) && !to.includes(TITLE.e1) && !to.includes(TITLE.e2), to.slice(0, 200));
    await out.screenshot(join(OUT, "evidence-outsider-denied.png"));
    check(P, "P1 grant-less caller: no role label claimed, no sample fixture names", !/Capabilities come from your grants: (Venue|Org)|Venue manager|\(sample\)/.test(to), to.slice(0, 300));
    check(P, "P1 manager header shows no sample fixture names in database mode", !/\(sample\)/.test(tm), tm.slice(0, 300));
    for (const path of [`${A}/events/${ID.e1}`, `${A}/events/${ID.e1}/door`, `${B}/events`, `${A}/events?role=venue_manager&state=live`]) {
      t = await visit(out, path);
      check(P, `C3 outsider denied: ${path.replace(A, "A").replace(B, "B")}`, t.includes(DENIED) && !t.includes(TITLE.e1), t.slice(0, 200));
    }
    await mgr.close();
    await out.close();
  } finally {
    await br.close();
  }
}

async function precedence() {
  const { users } = loadState();
  target.sqlText(`insert into venue.staff_role (venue_id, identity_id, role) values
    ('${ID.venA}', '${assertUuid(users.owner.id, "owner")}', 'venue_scanner'),
    ('${ID.venB}', '${assertUuid(users.finance.id, "finance")}', 'venue_scanner');
    select json_build_object('staff', (select count(*) from venue.staff_role where venue_id::text like '5a4d0b0e-%')) as j;`);
  const To = await passwordToken(users.owner);
  const Tf = await passwordToken(users.finance);
  let r = await rest("my_staff_roles", { token: To });
  check("precedence", "owner now also holds venue_scanner @ A", JSON.stringify(r.json) === JSON.stringify([{ venue_id: ID.venA, role: "venue_scanner" }]), r.text);
  r = await rest("my_staff_roles?order=role", { token: Tf });
  check("precedence", "finance holds venue_finance + venue_scanner @ B", JSON.stringify(r.json) === JSON.stringify([{ venue_id: ID.venB, role: "venue_finance" }, { venue_id: ID.venB, role: "venue_scanner" }]), r.text);
  const br = await launchBrowser(opts.chrome);
  try {
    const o = await br.newPage();
    await signIn(o, users.owner, `${A}/events`);
    let t = await o.text();
    check("precedence", "owner label stays Org owner (outranks scanner)", t.includes("Org owner"), t.slice(0, 300));
    const f = await br.newPage();
    await signIn(f, users.finance, `${B}/events`);
    t = await f.text();
    check("precedence", "finance label stays Venue finance (outranks scanner)", t.includes("Venue finance"), t.slice(0, 300));
  } finally {
    await br.close();
  }
}

async function revocation() {
  const { users } = loadState();
  const br = await launchBrowser(opts.chrome);
  try {
    const m = await br.newPage();
    await signIn(m, users.manager, `${A}/events`);
    check("revocation", "manager signed in before revocation", (await m.text()).includes(TITLE.e1), "");
    target.sqlText(`delete from venue.staff_role where venue_id = '${ID.venA}' and identity_id = '${assertUuid(users.manager.id, "manager")}' and role = 'venue_manager';
      select json_build_object('ok', true) as j;`);
    const t = await visit(m, `${A}/events`);
    check("revocation", "next request without re-login -> denial", t.includes(DENIED) && t.includes(NO_GRANT) && !t.includes(TITLE.e2), t.slice(0, 200));
  } finally {
    await br.close();
  }
  const Tm = await passwordToken(users.manager);
  let r = await rest("my_staff_roles", { token: Tm });
  check("revocation", "my_staff_roles empty after revocation", Array.isArray(r.json) && r.json.length === 0, r.text);
  r = await rest(`events?event_id=eq.${ID.e2}`, { token: Tm });
  check("revocation", "draft no longer readable after revocation", Array.isArray(r.json) && r.json.length === 0, r.text);
}

async function cleanup() {
  const r = target.sqlFile(SQL("cleanup.sql"));
  check("cleanup", "fixture rows removed (leftover 0)", r.leftover === 0, r);
  if (existsSync(STATE)) {
    const { users } = JSON.parse(readFileSync(STATE, "utf8"));
    for (const [role, u] of Object.entries(users ?? {})) {
      try {
        await target.deleteUser(u);
        check("cleanup", `synthetic user removed: ${role}`, true);
      } catch (e) {
        check("cleanup", `synthetic user removed: ${role}`, false, e.message);
      }
    }
    rmSync(STATE, { force: true });
  }
}

function postflight() {
  const now = target.sqlFile(SQL("preflight.sql"));
  check("postflight", "no acceptance users left", now.acceptance_users === 0, now.acceptance_users);
  check("postflight", "no fixture ids left", now.fixture_id_collisions === 0, now.fixture_id_collisions);
  if (existsSync(BASELINE)) {
    const base = JSON.parse(readFileSync(BASELINE, "utf8"));
    for (const k of ["organizations", "venues", "events", "sessions", "ticket_types", "batches", "staff_roles", "org_members", "auth_users"]) {
      check("postflight", `count ${k} back to baseline (${base.counts[k]})`, now.counts[k] === base.counts[k], { before: base.counts[k], after: now.counts[k] });
    }
  } else check("postflight", "baseline present", false, "no baseline.json");
}

// ---------------------------------------------------------------- main
const PHASES = { preflight, apply, "verify-apply": verifyApply, "verify-exposure": verifyExposure, fixtures, api, browser, precedence, revocation, cleanup, postflight };
async function run(phase) {
  guard(phase);
  console.log(`\n== ${phase} (${target.describe})`);
  try {
    await PHASES[phase]();
  } catch (e) {
    check(phase, "phase completed without error", false, e.message);
    if (["fixtures", "api", "browser", "precedence", "revocation"].includes(phase)) return false;
  }
  return true;
}

const started = new Date().toISOString();
if (opts.phase === "all") {
  if (target.name !== "local") throw new Error("REFUSING: --phase all is for the local rehearsal target only; run sandbox phases one at a time inside the window.");
  for (const p of ["preflight", "verify-apply", "verify-exposure", "fixtures", "api", "browser", "precedence", "revocation"]) {
    if (!(await run(p))) break;
  }
  await run("cleanup");
  await run("postflight");
} else if (PHASES[opts.phase]) {
  await run(opts.phase);
} else {
  throw new Error(`unknown --phase ${opts.phase}`);
}

const failed = results.filter((r) => !r.ok);
const evidence = join(OUT, `evidence-${opts.phase}-${started.replace(/[:.]/g, "-")}.json`);
saveJson(evidence, { target: target.describe, phase: opts.phase, started, finished: new Date().toISOString(), app: opts.app, passed: results.length - failed.length, failed: failed.length, results });
console.log(`\n${results.length - failed.length}/${results.length} checks passed · evidence -> ${evidence}`);
process.exit(failed.length ? 1 : 0);
