// Target adapters: where SQL runs, where the Data API/Auth live, and how synthetic users are made.
//   local   — the Docker-free rehearsal harness (psql on 127.0.0.1, PostgREST + auth-stub on :3202).
//   sandbox — the shared Supabase sandbox via the linked Supabase CLI (postgres) and the Auth admin API.
// Production is refused by ref before anything else happens.
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPO = resolve(HERE, "../../../..");
export const PRODUCTION_REF = "hqycwntpfoztoinemqns";
export const SANDBOX_REF = "ofaidukbieeekqaboscm";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const ROLES = {
  manager: { email: "acceptance.venue-manager-a@example.com", localId: "5a4d0b0e-0000-4000-8000-0000000000d1", label: "venue_manager @ Venue A" },
  owner: { email: "acceptance.venue-owner-a@example.com", localId: "5a4d0b0e-0000-4000-8000-0000000000d2", label: "org_owner @ Org A" },
  finance: { email: "acceptance.venue-finance-b@example.com", localId: "5a4d0b0e-0000-4000-8000-0000000000d3", label: "venue_finance @ Venue B" },
  outsider: { email: "acceptance.venue-outsider@example.com", localId: "5a4d0b0e-0000-4000-8000-0000000000d4", label: "signed in, no grant" },
};

export function assertUuid(v, what) {
  if (!UUID.test(String(v))) throw new Error(`${what} is not a UUID: ${v}`);
  return v;
}

function parseJsonColumn(raw) {
  const text = raw.trim();
  if (!text) throw new Error("query returned nothing");
  // psql -At prints the value; supabase db query -o json prints rows. Last json-ish line wins for psql.
  try {
    const d = JSON.parse(text);
    const rows = Array.isArray(d) ? d : d.rows ?? d;
    const cell = Array.isArray(rows) ? rows[rows.length - 1]?.j : d.j ?? d;
    return typeof cell === "string" ? JSON.parse(cell) : cell;
  } catch {
    const line = text.split("\n").filter((l) => l.trim().startsWith("{")).pop();
    if (!line) throw new Error(`unparseable query output: ${text.slice(0, 300)}`);
    return JSON.parse(line);
  }
}

export function makeTarget(opts) {
  if (opts.projectRef === PRODUCTION_REF || String(opts.url ?? "").includes(PRODUCTION_REF)) {
    throw new Error("REFUSING: this kit never targets production.");
  }
  if (opts.target === "local") return localTarget(opts);
  if (opts.target === "sandbox") return sandboxTarget(opts);
  throw new Error(`unknown --target ${opts.target} (local | sandbox)`);
}

function localTarget({ db = "snatchit_rehears_venueapi_rc", url = "http://localhost:3202" }) {
  if (!/rehears/.test(db)) throw new Error("REFUSING: local database name must contain 'rehears'");
  if (!/^http:\/\/(localhost|127\.0\.0\.1):/.test(url)) throw new Error("REFUSING: local target URL must be loopback");
  const harnessEnv = readFileSync(join(REPO, "admin/.env.local.example-harness"), "utf8");
  const anonKey = harnessEnv.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY=(\S+)/)[1];
  const psql = (args, input) =>
    execFileSync("psql", ["-h", "127.0.0.1", "-U", "postgres", "-d", db, "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1", ...args], {
      encoding: "utf8",
      input,
      env: { ...process.env, PGHOST: "127.0.0.1", PATH: `/opt/homebrew/opt/postgresql@17/bin:${process.env.PATH}` },
    });
  return {
    name: "local",
    describe: `local harness db=${db} api=${url}`,
    url,
    anonKey,
    canInspectRoleSettings: false,
    sqlFile: (file) => parseJsonColumn(psql(["-f", file])),
    sqlText: (sql) => parseJsonColumn(psql([], sql)),
    execFile: (file) => psql(["-f", file]),
    async createUser(role) {
      const r = ROLES[role];
      const password = randomBytes(18).toString("base64url");
      psql([], `insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
        values ('${assertUuid(r.localId, "local id")}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '${r.email}', '{"provider":"email","providers":["email"]}', '{"acceptance":"venue-slice1"}', now(), now(), now());
        insert into ops_harness.accounts (email, password_plain, user_id, aal, label) values ('${r.email}', '${password}', '${r.localId}', 'aal1', 'ACCEPTANCE ${r.label}');`);
      return { id: r.localId, email: r.email, password };
    },
    async deleteUser(user) {
      psql([], `delete from ops_harness.accounts where email = '${user.email.replace(/'/g, "")}';
        delete from auth.users where id = '${assertUuid(user.id, "user id")}';`);
    },
  };
}

function sandboxTarget({ projectRef }) {
  if (projectRef !== SANDBOX_REF) throw new Error(`REFUSING: --project-ref must be the shared sandbox ${SANDBOX_REF}`);
  const url = `https://${projectRef}.supabase.co`;
  const cli = (args) => execFileSync("supabase", args, { encoding: "utf8", cwd: REPO, stdio: ["ignore", "pipe", "pipe"] });
  let keys = null;
  const apiKeys = () => {
    if (!keys) {
      const list = JSON.parse(cli(["projects", "api-keys", "--project-ref", projectRef, "-o", "json"]));
      const find = (n) => list.find((k) => k.name === n)?.api_key;
      keys = { anon: find("anon"), service: find("service_role") };
      if (!keys.anon) throw new Error("anon key not found via supabase projects api-keys");
    }
    return keys;
  };
  const query = (file) => cli(["db", "query", "--linked", "--project-ref", projectRef, "-f", file, "-o", "json"]);
  const admin = async (method, path, body) => {
    const service = apiKeys().service; // held in memory only; never logged, never written
    if (!service) throw new Error("service_role key unavailable; cannot manage synthetic users");
    const res = await fetch(`${url}/auth/v1/admin/${path}`, {
      method,
      headers: { apikey: service, Authorization: `Bearer ${service}`, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`auth admin ${method} ${path} -> ${res.status} ${text.slice(0, 200)}`);
    return text ? JSON.parse(text) : null;
  };
  return {
    name: "sandbox",
    describe: `sandbox ${projectRef}`,
    url,
    get anonKey() {
      return apiKeys().anon;
    },
    canInspectRoleSettings: true,
    sqlFile: (file) => parseJsonColumn(query(file)),
    sqlText(sql) {
      const dir = mkdtempSync(join(tmpdir(), "venue-accept-sql-"));
      const f = join(dir, "q.sql");
      writeFileSync(f, sql, { mode: 0o600 });
      try {
        return parseJsonColumn(query(f));
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    },
    execFile: (file) => query(file),
    async createUser(role) {
      const r = ROLES[role];
      const password = randomBytes(18).toString("base64url");
      const u = await admin("POST", "users", { email: r.email, password, email_confirm: true, app_metadata: { acceptance: "venue-slice1" } });
      return { id: assertUuid(u.id, "created user id"), email: r.email, password };
    },
    async deleteUser(user) {
      await admin("DELETE", `users/${assertUuid(user.id, "user id")}`);
    },
  };
}
