import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ callOps: vi.fn(), role: "platform_admin" }));
vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh() {} }), usePathname: () => "/system", useSearchParams: () => new URLSearchParams() }));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: async () => ({ id: "operator", role: mocks.role }) }));

import SystemPage from "@/app/(console)/system/page";

beforeEach(() => {
  mocks.role = "platform_admin";
  mocks.callOps.mockReset();
  mocks.callOps.mockImplementation(async (fn: string) => {
    if (fn === "job_health") return { ok: true, data: {
      generated_at: "2026-11-25T12:00:00Z",
      ops_jobs: [{ job_name: "daily_summary", enabled: true, consecutive_failures: 3, last_error: "Check failed: review the payment queue", recent_runs: [] }],
      cron_jobs: { available: true, items: [{ jobid: 42, jobname: "ops_daily_summary", schedule: "0 13 * * *", active: true, last_status: "failed", failures_24h: 3, last_message: "Scheduled run failed" }] },
      webhook_backlog: { unprocessed: 2, failed: 1, oldest_unprocessed_event_id: "evt_private_reference" },
      notify: { delivery: {}, outbox: {} }, alerts: [],
    } };
    if (fn === "settings") return { ok: true, data: [{ key: "actions_enabled", value: false }] };
    if (fn === "latest_summary") return { ok: true, data: null };
    if (fn === "list_operational_config") return { ok: false, kind: "denied" };
    return { ok: true, data: { items: [], next_cursor: null } };
  });
});

async function render() {
  return renderToStaticMarkup(await SystemPage({ searchParams: Promise.resolve({}) }));
}

describe("Platform health keeps operations visible and separates technical detail", () => {
  it("uses clear sections while preserving warnings, retry and pause controls outside closed details", async () => {
    const html = await render();
    const disclosures = [...html.matchAll(/<details\b[^>]*>[\s\S]*?<\/details>/g)].map((m) => m[0]);
    const visible = html.replace(/<details\b[^>]*>[\s\S]*?<\/details>/g, "");
    expect(html).toContain("Platform health");
    for (const label of ["Automated checks", "Scheduled tasks", "Payment updates", "Approvals", "Sales rules", "Change history"]) expect(visible).toContain(label);
    expect(visible).toContain("Check failed: review the payment queue");
    expect(visible).toContain("Scheduled run failed");
    expect(visible).toContain("Run now");
    expect(visible).toContain('name="action_type" value="job_retry"');
    expect(visible).toContain('name="subject_ref" value="daily_summary"');
    expect(visible).toContain('name="subject_ref" value="actions_enabled"');
    expect(visible).toContain('id="setting-actions_enabled-value"');
    expect(visible).toContain('name="param.value:boolean"');
    expect(visible).toContain('value="false" selected=""');
    expect(visible).toContain("Money settings, Operational settings, alert acknowledgements and opening evidence");
    expect(visible).toContain("Save setting");
    for (const raw of ["0 13 * * *", "evt_private_reference"]) {
      expect(visible).not.toContain(raw);
      const detail = disclosures.find((block) => block.includes(raw));
      expect(detail).toBeDefined();
      expect(detail).toContain("Technical details");
      expect(detail).not.toMatch(/^<details[^>]*\bopen(?:\s|=|>)/);
    }
    expect(mocks.callOps.mock.calls.map(([fn]) => fn).sort()).toEqual(["audit_log", "job_health", "latest_summary", "list_actions", "list_approvals", "list_config_approvals", "list_operational_config", "settings"]);
  });

  it("keeps founder-only controls unavailable to support operators", async () => {
    mocks.role = "platform_support";
    const html = await render();
    expect(html).not.toContain('name="action_type" value="job_retry"');
    expect(html).not.toContain('id="setting-actions_enabled-value"');
    expect(html).toContain("Only founders can see Settings.");
    expect(mocks.callOps.mock.calls.map(([fn]) => fn)).not.toContain("settings");
  });
});
