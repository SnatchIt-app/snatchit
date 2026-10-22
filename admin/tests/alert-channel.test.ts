import { renderToStaticMarkup } from "react-dom/server";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * The read-only "Delivery channel" block on /system's Alerts panel (v2 with
 * the PR #89 port). The owner asked for the alert channel to be prepared on
 * the owner's verified account email, with no unverified recipient and
 * nothing activated. The block states only what a record establishes:
 *
 *  1. alert_delivery_enabled, read from ops.settings (platform_admin only,
 *     116:1593-1601). A literal true or false is shown as read; anything else
 *     (not readable for the role, a failed read, no row, any other value)
 *     is "unknown", never a default.
 *  2. Schedule: no console read returns what a pg_cron job runs.
 *     ops.job_health lists each cron job's jobid, jobname, schedule and
 *     active flag only (143:186-197), and no other read covers
 *     ops.dispatch_alerts (146 adds no read). So the block never asserts
 *     "not scheduled": it says the server does not show it.
 *  3. Channel: the runbook's prepared state, labelled as not read from the
 *     server (the email channel's settings are edge-function secrets).
 *  4. A pointer to docs/dashboards/ALERT_CHANNEL_RUNBOOK.md.
 * It never displays an email address and holds no control.
 *
 * The real page renders here, with the real callOps; only the Supabase
 * client and the session are faked.
 */
const h = vi.hoisted(() => ({
  role: "platform_admin",
  settings: { data: null as unknown, error: null as unknown },
  cron: { available: true, note: null as string | null, items: [] as unknown[] },
  calls: [] as string[],
}));

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
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    schema: () => ({
      rpc: async (fn: string) => {
        h.calls.push(fn);
        switch (fn) {
          case "job_health":
            return { data: jobHealth(), error: null };
          case "list_approvals":
          case "audit_log":
          case "list_actions":
            return { data: { items: [], next_cursor: null }, error: null };
          case "settings":
            return h.settings;
          case "latest_summary":
            return { data: null, error: null };
          default:
            return { data: null, error: { code: "XX000", message: `unexpected call ${fn}` } };
        }
      },
    }),
  }),
}));
vi.mock("@/lib/auth/session", () => ({
  requireOperator: vi.fn(async () => ({ id: "0b000000-0000-4000-8000-0000000000aa", email: null, aal: "aal2", role: h.role, whoami: { role: h.role } })),
}));

import SystemPage from "@/app/(console)/system/page";

function jobHealth() {
  return {
    generated_at: "2026-10-21T12:00:00Z",
    cron_jobs: h.cron,
    ops_jobs: [],
    webhook_backlog: { unprocessed: 0, failed: 0, oldest_unprocessed_at: null, oldest_unprocessed_event_id: null },
    notify: { delivery: {}, outbox: {}, note: null },
    alerts: [
      {
        alert_key: "case:p1:0001",
        kind: "p1_case",
        state: "firing",
        payload: { title: "P1 case open" },
        first_fired_at: "2026-10-13T21:00:00Z",
        last_fired_at: "2026-10-21T11:55:00Z",
        fire_count: 4,
        notify_attempts: 0,
        incident_seq: 1,
      },
    ],
  };
}

const setting = (key: string, value: unknown) => ({ key, value, updated_at: "2026-10-13T21:10:00Z", updated_by: null, updated_by_label: null });
const OTHER_SETTINGS = [setting("actions_enabled", true), setting("detectors_enabled", true)];
const withSwitch = (value: unknown) => ({ data: [...OTHER_SETTINGS, setting("alert_delivery_enabled", value)], error: null });

const EXISTING_READS = ["audit_log", "job_health", "latest_summary", "list_actions", "list_approvals", "settings"];
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/;
const COMPONENT_SRC = resolve(__dirname, "../src/components/system/AlertChannel.tsx");

async function renderSystem(): Promise<string> {
  const el = await SystemPage({ searchParams: Promise.resolve({}) });
  return renderToStaticMarkup(el);
}

const decode = (s: string) => s.replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
const text = (html: string) => decode(html.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();

/** The block's markup: its own <section>, which holds no nested section. */
function block(html: string): string {
  const start = html.indexOf('<section aria-labelledby="alert-delivery-channel"');
  expect(start, "the Delivery channel block is rendered").toBeGreaterThanOrEqual(0);
  return html.slice(start, html.indexOf("</section>", start) + "</section>".length);
}

/** dt label -> { text of the dd, the dd's <strong> value } */
function rows(blockHtml: string): Record<string, { text: string; value: string | null }> {
  const out: Record<string, { text: string; value: string | null }> = {};
  for (const m of blockHtml.matchAll(/<dt[^>]*>([\s\S]*?)<\/dt>\s*<dd[^>]*>([\s\S]*?)<\/dd>/g)) {
    const strong = m[2].match(/<strong[^>]*>([\s\S]*?)<\/strong>/);
    out[text(m[1])] = { text: text(m[2]), value: strong ? text(strong[1]) : null };
  }
  return out;
}

beforeEach(() => {
  h.role = "platform_admin";
  h.settings = withSwitch(false);
  h.cron = { available: true, note: null, items: [] };
  h.calls.length = 0;
});

describe("/system's Alerts panel carries a read-only Delivery channel block", () => {
  it("sits inside the Alerts panel, above the alert list and before the Approvals panel", async () => {
    const html = await renderSystem();
    const title = html.indexOf(">Alerts</h2>");
    const start = html.indexOf('<section aria-labelledby="alert-delivery-channel"');
    const list = html.indexOf("P1 case open");
    const approvals = html.indexOf(">Approvals (second founder)</h2>");
    expect(title).toBeGreaterThan(0);
    expect(start, "block after the Alerts title").toBeGreaterThan(title);
    expect(list, "block before the first alert").toBeGreaterThan(start);
    expect(approvals).toBeGreaterThan(list);
    expect(text(block(html))).toMatch(/^Delivery channel /);
  });

  it("makes no read beyond the page's existing six, each once", async () => {
    await renderSystem();
    expect([...h.calls].sort()).toEqual(EXISTING_READS);
  });

  it("holds no control: nothing in it can send, schedule or switch", async () => {
    for (const s of [withSwitch(false), withSwitch(true)]) {
      h.settings = s;
      const b = block(await renderSystem());
      expect(b).not.toMatch(/<(form|button|input|select|textarea)\b/);
    }
  });
});

describe("1. alert_delivery_enabled is shown as ops.settings returns it, else unknown", () => {
  it("false: read as false, and what false means for ops.dispatch_alerts", async () => {
    h.settings = withSwitch(false);
    const r = rows(block(await renderSystem()))["Delivery switch"];
    expect(r.value).toBe("false");
    expect(r.text).toContain("alert_delivery_enabled");
    expect(r.text).toContain("ops.dispatch_alerts posts nothing while it is false");
    expect(r.text).toContain("Read from ops.settings");
  });

  it("true: read as true, and the switch alone still schedules nothing", async () => {
    h.settings = withSwitch(true);
    const r = rows(block(await renderSystem()))["Delivery switch"];
    expect(r.value).toBe("true");
    expect(r.text).toContain("a call to ops.dispatch_alerts can post alerts");
    expect(r.text).toContain("the switch schedules nothing by itself");
    expect(r.text).toContain("Read from ops.settings");
  });

  it("unknown for a reader who is not platform_admin, and the page still makes no settings call", async () => {
    h.role = "platform_support";
    h.settings = withSwitch(true); // would read true if it were called
    const r = rows(block(await renderSystem()))["Delivery switch"];
    expect(r.value).toBe("unknown");
    expect(r.text).toContain("ops.settings is readable by platform_admin only");
    expect(h.calls).not.toContain("settings");
    expect([...h.calls].sort()).toEqual(EXISTING_READS.filter((f) => f !== "settings"));
  });

  it("unknown when the ops.settings read fails, never the seeded default", async () => {
    h.settings = { data: null, error: { code: "XX000", message: "settings failed" } };
    const r = rows(block(await renderSystem()))["Delivery switch"];
    expect(r.value).toBe("unknown");
    expect(r.text).toContain("ops.settings could not be read");
  });

  it("unknown when ops.settings returns no alert_delivery_enabled row (migration 146 not applied)", async () => {
    h.settings = { data: OTHER_SETTINGS, error: null };
    const r = rows(block(await renderSystem()))["Delivery switch"];
    expect(r.value).toBe("unknown");
    expect(r.text).toContain("ops.settings returned no alert_delivery_enabled row");
  });

  it("unknown for any value other than a literal true or false, which it does not echo", async () => {
    for (const v of ["true", "false", 1, 0, null, {}, "x"]) {
      h.settings = withSwitch(v);
      const r = rows(block(await renderSystem()))["Delivery switch"];
      expect(r.value, JSON.stringify(v)).toBe("unknown");
      expect(r.text, JSON.stringify(v)).toContain("neither true nor false");
    }
  });
});

describe("2. Schedule: never asserted, because no read returns it", () => {
  const cronLists = [
    { available: true, note: null, items: [] },
    { available: true, note: null, items: [{ jobid: 7, jobname: "ops-detect-tick", schedule: "*/5 * * * *", active: true }] },
    { available: true, note: null, items: [{ jobid: 9, jobname: "ops-dispatch-alerts", schedule: "*/5 * * * *", active: true }] },
    { available: false, note: "cron.job_run_details is not present on this database; run history unavailable", items: [] },
  ];

  it("reads 'not shown by the server (owner/A to verify)' for every switch state and cron list", async () => {
    for (const s of [withSwitch(false), withSwitch(true), { data: null, error: { code: "XX000", message: "settings failed" } }]) {
      for (const cron of cronLists) {
        h.settings = s;
        h.cron = cron;
        const b = block(await renderSystem());
        const r = rows(b)["Schedule"];
        expect(r.value).toBe("not shown by the server (owner/A to verify)");
        expect(r.text).toContain("ops.job_health lists each pg_cron job's name, schedule and active flag, not the command it runs");
        expect(r.text).not.toMatch(/\bnone\b/i);
        expect(text(b)).not.toMatch(/not scheduled|is scheduled|Schedule:? none/i);
      }
    }
  });
});

describe("3. Channel and 4. runbook: prepared, not active, and labelled as not a server read", () => {
  it("states the prepared channel in every switch state, and where that line comes from", async () => {
    for (const s of [withSwitch(false), withSwitch(true), { data: null, error: { code: "XX000", message: "settings failed" } }]) {
      h.settings = s;
      const r = rows(block(await renderSystem()));
      expect(r["Channel"].value).toBe("email to the owner's verified account email — prepared, not active (owner action)");
      expect(r["Channel"].text).toContain("From the runbook, not read from the server");
      expect(r["Runbook"].text).toContain("docs/dashboards/ALERT_CHANNEL_RUNBOOK.md");
    }
  });

  it("never displays or hard-codes an email address", async () => {
    for (const s of [withSwitch(false), withSwitch(true), { data: null, error: { code: "XX000", message: "settings failed" } }]) {
      h.settings = s;
      expect(block(await renderSystem())).not.toMatch(EMAIL);
    }
    expect(readFileSync(COMPONENT_SRC, "utf8")).not.toMatch(EMAIL);
  });
});
