import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ callOps: vi.fn(), requireOperator: vi.fn(), calls: [] as string[], operational: null as unknown, money: null as unknown }));
vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next/navigation", () => ({
  notFound: () => {
    throw new Error("notFound");
  },
  redirect: () => {
    throw new Error("redirect");
  },
  usePathname: () => "/system",
  useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }),
  useParams: () => ({}),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: mocks.requireOperator }));

import SystemPage from "@/app/(console)/system/page";

const OPERATIONAL = [
  { key: "inventory.per_user_active_hold_max", version: 3, value: 6, effective_from: "2026-10-31T00:00:00Z", created_at: "2026-10-31T00:00:00Z" },
  { key: "inventory.hold_ttl_interval", version: 4, value: "10 minutes", effective_from: "2026-10-31T00:00:00Z", created_at: "2026-10-31T00:00:00Z" },
  { key: "feature.native_issuance_enabled", version: null, value: null, effective_from: null, created_at: null },
  { key: "feature.native_scanning_enabled", version: null, value: null, effective_from: null, created_at: null },
];

function health() {
  return {
    generated_at: "2026-10-31T12:00:00Z",
    cron_jobs: { available: true, note: null, items: [] },
    ops_jobs: [],
    webhook_backlog: { unprocessed: 0, failed: 0, oldest_unprocessed_at: null, oldest_unprocessed_event_id: null },
    notify: { delivery: {}, outbox: {}, note: null },
    alerts: [],
  };
}

function ops(fn: string): unknown {
  mocks.calls.push(fn);
  switch (fn) {
    case "job_health":
      return { ok: true, data: health() };
    case "list_approvals":
    case "audit_log":
    case "list_actions":
      return { ok: true, data: { items: [], next_cursor: null } };
    case "settings":
      return { ok: true, data: [] };
    case "list_config_approvals":
      return mocks.money;
    case "list_operational_config":
      return mocks.operational;
    case "latest_summary":
      return { ok: true, data: null };
    default:
      return { ok: false, kind: "error", message: `unexpected ${fn}` };
  }
}

function render(): Promise<string> {
  return Promise.resolve(SystemPage({ searchParams: Promise.resolve({}) })).then((el) => renderToStaticMarkup(el));
}

beforeEach(() => {
  mocks.calls.length = 0;
  mocks.callOps.mockReset();
  mocks.callOps.mockImplementation(async (fn: string) => ops(fn));
  mocks.requireOperator.mockResolvedValue({ id: "0b000000-0000-4000-8000-0000000000aa", email: null, aal: "aal2", role: "platform_admin", whoami: { role: "platform_admin" } });
  mocks.operational = { ok: true, data: { items: OPERATIONAL, next_cursor: null, count_hint: 4 } };
  mocks.money = { ok: true, data: { items: [], money_keys: [
    { key: "fee.buyer_service_bps", version: 2, value: 1000 },
    { key: "refund.request_ttl_hours", version: 1, value: 72 },
  ] } };
});

describe("operational settings panel", () => {
  it("renders the four live values and one write form for platform_admin", async () => {
    const html = await render();
    expect(html).toContain("Operational settings");
    expect(html).toContain("Hold max per buyer");
    expect(html).toContain("inventory.per_user_active_hold_max");
    expect(html).toContain("feature.native_issuance_enabled");
    expect(html).toContain("feature.native_scanning_enabled");
    expect(html).toContain("10 minutes");
    expect(html).toContain("unset");
    expect(html).toContain("Apply now");
    expect(html).toContain('name="key"');
    expect(html).toContain('name="reason"');
    expect(html).toContain('name="confirm"');
    expect(html).toContain('name="idempotency_key"');
    expect(mocks.calls.filter((f) => f === "list_operational_config")).toHaveLength(1);
    // 197 also adds the read-only money live-values overview without changing 196 behaviour.
    expect(html).toContain("Live values (2 money keys)");
    expect(html).toContain("fee.buyer_service_bps");
  });

  it("does not read or render operational settings for a support operator", async () => {
    mocks.requireOperator.mockResolvedValue({ id: "0b000000-0000-4000-8000-0000000000aa", email: null, aal: "aal2", role: "platform_support", whoami: { role: "platform_support" } });
    const html = await render();
    expect(mocks.calls).not.toContain("list_operational_config");
    expect(mocks.calls).not.toContain("list_config_approvals");
    expect(html).toContain("Operational settings are visible to platform_admin only.");
    expect(html).not.toContain("Apply now");
  });

  it("shows the named needs-registry-197 state only for an unavailable read, and no write control", async () => {
    mocks.operational = { ok: false, kind: "error", message: "RPC ops.list_operational_config not available yet", unavailable: true };
    const html = await render();
    expect(html).toContain("Needs registry 197");
    expect(html).not.toContain("Apply now");
  });

  it("does not relabel denied as needs-197", async () => {
    mocks.operational = { ok: false, kind: "denied" };
    const html = await render();
    expect(html).toContain("Your account is not allowed to do this.");
    expect(html).not.toContain("Needs registry 197");
    expect(html).not.toContain("Apply now");
  });

  it("does not relabel an aal/mfa refusal as needs-197", async () => {
    mocks.operational = { ok: false, kind: "mfa" };
    const html = await render();
    expect(html).toContain("Re-verify with your authenticator");
    expect(html).not.toContain("Needs registry 197");
    expect(html).not.toContain("Apply now");
  });

  it("does not relabel a generic read failure as needs-197", async () => {
    mocks.operational = { ok: false, kind: "error", message: "boom" };
    const html = await render();
    expect(html).toContain("Request failed");
    expect(html).not.toContain("Needs registry 197");
    expect(html).not.toContain("Apply now");
  });

  it("does not render a write form for a malformed or partial successful payload", async () => {
    for (const data of [{ items: "nope" }, { items: [] }, { items: OPERATIONAL.slice(0, 3) }]) {
      mocks.operational = { ok: true, data };
      const html = await render();
      expect(html).toContain("Unrecognised payload from ops.list_operational_config");
      expect(html).not.toContain("Apply now");
    }
  });
});
