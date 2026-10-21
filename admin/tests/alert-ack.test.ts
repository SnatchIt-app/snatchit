import { createElement, isValidElement, type ReactElement, type ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Port of PR #89 (3dab1614): alert delivery, acknowledgement and the
 * Acknowledge control on /system, checked against migration 146 as it stands
 * on release/production-gate-20260918:
 *
 *   ops.alert_ack(p_alert_key text, p_note text default null) returns jsonb
 *   {alert_key, state, incident_seq, acknowledged_at, acknowledged_by, …};
 *   raises 'not_found: no alert %' (P0002) and
 *   'precondition_failed: alert % is %, so there is nothing to acknowledge' (P0001).
 *
 * The real acknowledgeAlert → callOps → mapOpsError path runs; only the
 * Supabase client is faked.
 */
const h = vi.hoisted(() => ({
  reply: { data: null as unknown, error: null as unknown },
  calls: [] as { fn: string; args: Record<string, unknown> }[],
  revalidated: [] as string[],
}));

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: (p: string) => h.revalidated.push(p) }));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    schema: () => ({
      rpc: async (fn: string, args: Record<string, unknown>) => {
        h.calls.push({ fn, args });
        return h.reply;
      },
    }),
  }),
}));

import { acknowledgeAlert, submitAlertAck } from "@/lib/actions";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { AlertDelivery, AlertList } from "@/components/system/AlertList";
import { AlertAckForm, AlertAckResult, alertAckView } from "@/components/system/AlertAckForm";
import type { OpsAlert } from "@/lib/types";

const KEY = "job_failure:ops:refunds";
const ME = "aaaaaaaa-0000-4000-8000-000000000001";
const OTHER = "bbbbbbbb-0000-4000-8000-000000000002";
const ACKED = { alert_key: KEY, state: "firing", incident_seq: 2, acknowledged_at: "2026-10-21T10:00:00Z", acknowledged_by: ME, queued_at: null, delivered_at: null, notify_attempts: 0 };

const ackForm = (fields: Record<string, string>) => {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.set(k, v);
  return fd;
};

beforeEach(() => {
  h.calls.length = 0;
  h.revalidated.length = 0;
  h.reply = { data: ACKED, error: null };
});

describe("acknowledgeAlert calls 146's ops.alert_ack exactly", () => {
  it("sends p_alert_key and p_note, and reports the acknowledged incident", async () => {
    const s = await acknowledgeAlert(KEY, "on it, tracked in the ops channel");
    expect(h.calls).toEqual([{ fn: "alert_ack", args: { p_alert_key: KEY, p_note: "on it, tracked in the ops channel" } }]);
    expect(s).toEqual({ submitted: true, acknowledgedAt: "2026-10-21T10:00:00Z", incidentSeq: 2 });
  });

  it("an empty note goes as null (the function's default), and success revalidates the page", async () => {
    const s = await submitAlertAck({}, ackForm({ alert_key: KEY, incident_seq: "2", note: "   ", revalidate: "/system" }));
    expect(h.calls[0].args).toEqual({ p_alert_key: KEY, p_note: null });
    expect(s.acknowledgedAt).toBe("2026-10-21T10:00:00Z");
    expect(h.revalidated).toEqual(["/system"]);
  });

  it("a revalidate value that is not a path is ignored", async () => {
    await submitAlertAck({}, ackForm({ alert_key: KEY, incident_seq: "2", note: "", revalidate: "https://example.test/system" }));
    expect(h.revalidated).toEqual([]);
  });

  it("146's own refusals come back in its words, as a refusal, and revalidate nothing", async () => {
    for (const error of [
      { code: "P0002", message: `not_found: no alert ${KEY}` },
      { code: "P0001", message: `precondition_failed: alert ${KEY} is recovered, so there is nothing to acknowledge` },
    ]) {
      h.reply = { data: null, error };
      h.revalidated.length = 0;
      const s = await submitAlertAck({}, ackForm({ alert_key: KEY, incident_seq: "2", note: "", revalidate: "/system" }));
      expect(s).toEqual({ submitted: true, refused: error.message });
      expect(h.revalidated).toEqual([]);
    }
  });

  it("an error code the console has never seen stays generic, with the database's message and code", async () => {
    h.reply = { data: null, error: { code: "XX000", message: "alert_ack: a rule added after this build" } };
    const s = await acknowledgeAlert(KEY, "");
    expect(s.refused).toBeUndefined();
    expect(s.failure).toEqual({ ok: false, kind: "error", code: "XX000", message: "alert_ack: a rule added after this build" });
    const html = renderToStaticMarkup(createElement(OpsFailureAlert, { failure: s.failure!, fn: "alert_ack" }));
    expect(html).toContain("Request failed");
    expect(html).toContain("alert_ack: a rule added after this build");
    expect(html).toContain("XX000");
  });

  it("the reader gate's refusals keep their console meaning", async () => {
    h.reply = { data: null, error: { code: "42501", message: "insufficient_privilege: not an operator" } };
    expect((await acknowledgeAlert(KEY, "")).failure).toEqual({ ok: false, kind: "denied" });
    h.reply = { data: null, error: { code: "P0001", message: "step_up_required: aal2" } };
    expect((await acknowledgeAlert(KEY, "")).failure).toEqual({ ok: false, kind: "mfa" });
    h.reply = { data: null, error: { code: "PGRST202", message: "Could not find the function ops.alert_ack" } };
    expect((await acknowledgeAlert(KEY, "")).failure).toMatchObject({ kind: "error", unavailable: true, message: "RPC ops.alert_ack not available yet" });
  });

  it("refuses locally, without calling the database, when the key is missing or the note too long", async () => {
    expect(await acknowledgeAlert("", "x")).toMatchObject({ invalid: expect.stringMatching(/alert key/) });
    expect(await acknowledgeAlert(KEY, "x".repeat(2001))).toMatchObject({ invalid: expect.stringMatching(/2000/) });
    expect(h.calls).toEqual([]);
  });

  it("the form's rendered incident goes with the call; the same incident back is a plain acknowledgement", async () => {
    const s = await submitAlertAck({}, ackForm({ alert_key: KEY, incident_seq: "2", note: "", revalidate: "/system" }));
    expect(h.calls).toEqual([{ fn: "alert_ack", args: { p_alert_key: KEY, p_note: null } }]);
    expect(s).toEqual({ submitted: true, acknowledgedAt: "2026-10-21T10:00:00Z", incidentSeq: 2, shownIncidentSeq: 2 });
  });

  it("a different incident acknowledged than the one shown comes back as a warning that names both, and still refreshes the page", async () => {
    // 146's alert_ack acknowledges whatever incident the row holds when the call arrives: if the condition cleared
    // and re-fired after the page loaded, the operator has just acknowledged an incident they never saw.
    h.reply = { data: { ...ACKED, incident_seq: 3 }, error: null };
    const s = await submitAlertAck({}, ackForm({ alert_key: KEY, incident_seq: "2", note: "looking at it", revalidate: "/system" }));
    expect(s.acknowledgedAt).toBe("2026-10-21T10:00:00Z");
    expect(s.incidentSeq).toBe(3);
    expect(s.shownIncidentSeq).toBe(2);
    expect(s.warning).toContain("A new incident #3 opened since you loaded this page, which showed incident #2; it is now acknowledged.");
    expect(h.revalidated).toEqual(["/system"]);
    // an answer that does not say which incident it acknowledged is not passed off as the one shown
    h.reply = { data: { ...ACKED, incident_seq: undefined }, error: null };
    expect((await acknowledgeAlert(KEY, "", 2)).warning).toContain("did not report which incident it acknowledged");
    expect((await acknowledgeAlert(KEY, "", 2)).acknowledgedAt).toBe("2026-10-21T10:00:00Z");
  });

  it("refuses locally, without calling the database, when the form does not say which incident it showed", async () => {
    for (const seq of [undefined, "", "0", "-1", "2.5", "two"]) {
      const fields: Record<string, string> = { alert_key: KEY, note: "", revalidate: "/system" };
      if (seq !== undefined) fields.incident_seq = seq;
      expect(await submitAlertAck({}, ackForm(fields)), String(seq)).toMatchObject({ invalid: expect.stringMatching(/which incident/) });
    }
    expect(h.calls).toEqual([]);
  });

  it("an answer without acknowledged_at is not reported as acknowledged", async () => {
    h.reply = { data: { alert_key: KEY, state: "firing" }, error: null };
    const s = await submitAlertAck({}, ackForm({ alert_key: KEY, incident_seq: "2", note: "", revalidate: "/system" }));
    expect(s.acknowledgedAt).toBeUndefined();
    expect(s.failure).toMatchObject({ kind: "error", message: "Unrecognised response from alert_ack" });
    expect(h.revalidated).toEqual([]);
  });
});

describe("the alerts panel states only what the alert row records", () => {
  const base: OpsAlert = { alert_key: KEY, kind: "job_failure", state: "firing", first_fired_at: "2026-10-21T09:00:00Z", last_fired_at: "2026-10-21T09:30:00Z", fire_count: 3 };
  const delivery = (a: Partial<OpsAlert>) => renderToStaticMarkup(createElement(AlertDelivery, { alert: { ...base, ...a }, meId: ME }));
  const list = (alerts: OpsAlert[]) => renderToStaticMarkup(createElement(AlertList, { alerts, meId: ME }));

  it("confirmed delivery is a report from notify-report, not proof anyone read it", () => {
    const html = delivery({ delivered_at: "2026-10-21T09:10:00Z", delivery_status: 200, notify_attempts: 1 });
    expect(html).toContain("Delivery confirmed");
    expect(html).toContain("(HTTP 200)");
    expect(html).toContain("not proof anyone read it");
  });

  it("queued is not delivered", () => {
    const html = delivery({ queued_at: "2026-10-21T09:05:00Z", notify_attempts: 1 });
    expect(html).toContain("Queued");
    expect(html).toContain("not confirmed delivered");
    expect(html).not.toContain("Delivery confirmed");
  });

  it("failed attempts carry the last error, and the attempt limit is named", () => {
    const html = delivery({ notify_attempts: 5, delivery_status: 401, last_notify_error: "HTTP 401 from notify-report" });
    expect(html).toContain("Not delivered</span> after 5 attempts: HTTP 401 from notify-report — attempt limit (5) reached");
    expect(delivery({ notify_attempts: 1, last_notify_error: "HTTP 401 from notify-report" })).not.toContain("attempt limit");
  });

  it("no attempt reads as not sent, with the reason the row gives, and never as 'nobody was told'", () => {
    const html = delivery({ notify_attempts: 0, last_notify_error: "functions base URL (Vault project_url) is not configured" });
    expect(html).toContain("Not sent: no delivery attempt is recorded for this incident (functions base URL (Vault project_url) is not configured)");
    expect(html.toLowerCase()).not.toContain("nobody");
  });

  it("an acknowledgement is its own fact, beside the delivery state", () => {
    expect(delivery({ acknowledged_at: "2026-10-21T09:20:00Z", acknowledged_by: ME })).toMatch(/Acknowledged<\/span>.*by me · still firing until the condition clears/);
    const other = delivery({ acknowledged_at: "2026-10-21T09:20:00Z", acknowledged_by: OTHER });
    expect(other).toContain("by bbbbbbbb");
    expect(other).toContain("Not sent: no delivery attempt is recorded");
  });

  it("an unacknowledged alert gets the Acknowledge form; an acknowledged one, or one without a key, does not", () => {
    const html = list([base]);
    expect(html).toContain(`name="alert_key" value="${KEY}"`);
    expect(html).toContain('name="revalidate" value="/system"');
    expect(html).toMatch(/<textarea[^>]*name="note"/);
    expect(html).toContain("Acknowledge");
    expect(list([{ ...base, acknowledged_at: "2026-10-21T09:20:00Z", acknowledged_by: ME }])).not.toContain('name="alert_key"');
    expect(list([{ ...base, alert_key: undefined }])).not.toContain('name="alert_key"');
  });

  it("a recurrence is marked as a new incident and acknowledged as one", () => {
    const html = list([{ ...base, incident_seq: 2 }]);
    expect(html).toContain("Incident #2");
    expect(html).toContain("Acknowledge incident #2");
    expect(list([{ ...base, incident_seq: 1 }])).not.toContain("Incident #");
  });

  it("the form posts the incident it shows", () => {
    expect(list([{ ...base, incident_seq: 2 }])).toContain('name="incident_seq" value="2"');
    expect(list([{ ...base, incident_seq: 1 }])).toContain('name="incident_seq" value="1"');
    // 146's column is not null default 1; a row without it is read as incident 1, as the badge already does
    expect(list([base])).toContain('name="incident_seq" value="1"');
  });

  it("the standing note leaves delivery to the owner and tells nobody to switch it on", () => {
    for (const html of [list([]), list([base])]) {
      expect(html).toContain("both owner decisions");
      expect(html).toContain("alert_delivery_enabled");
      expect(html).not.toMatch(/\b(flip|set it to true|turn it on|switch it on)\b/i);
    }
  });
});

describe("an acknowledgement's result outlives the refresh that hides the form", () => {
  const base: OpsAlert = { alert_key: KEY, kind: "job_failure", state: "firing", first_fired_at: "2026-10-21T09:00:00Z", last_fired_at: "2026-10-21T09:30:00Z", fire_count: 3, incident_seq: 2 };
  /** The children of each alert's <li>, as AlertList returns them (no render: the element tree React reconciles). */
  const slots = (alerts: OpsAlert[]): ReactNode[][] => {
    const found: ReactNode[][] = [];
    const walk = (n: ReactNode) => {
      if (Array.isArray(n)) return n.forEach(walk);
      if (!isValidElement(n)) return;
      const el = n as ReactElement<{ children?: ReactNode }>;
      if (el.type === "li") found.push(([] as ReactNode[]).concat(el.props.children));
      else walk(el.props.children);
    };
    walk(AlertList({ alerts, meId: ME }));
    return found;
  };
  const ackSlot = (children: ReactNode[]) => children.findIndex((c) => isValidElement(c) && c.type === AlertAckForm);

  it("AlertList keeps the acknowledgement control mounted, in the same place, once the row is acknowledged", () => {
    // The action's response carries the refreshed page (revalidatePath). React keeps a client component's state only
    // if the same component stays at the same place in the tree, so the slot must not disappear when acknowledged_at
    // is set — otherwise the warning below is unmounted the moment it arrives.
    const [before] = slots([base]);
    const [after] = slots([{ ...base, incident_seq: 3, acknowledged_at: "2026-10-21T10:00:00Z", acknowledged_by: ME }]);
    const i = ackSlot(before);
    expect(i).toBeGreaterThanOrEqual(0);
    expect(ackSlot(after)).toBe(i);
    expect(before.length).toBe(after.length);
    expect((before[i] as ReactElement<{ acknowledged: boolean; incidentSeq: number }>).props).toMatchObject({ acknowledged: false, incidentSeq: 2 });
    expect((after[i] as ReactElement<{ acknowledged: boolean; incidentSeq: number }>).props).toMatchObject({ acknowledged: true, incidentSeq: 3 });
  });

  it("the result stays on screen after the refresh, until the row moves on to a newer incident", () => {
    const warned = { submitted: true, acknowledgedAt: "2026-10-21T10:00:00Z", incidentSeq: 3, shownIncidentSeq: 2, warning: "A new incident #3 opened…" };
    expect(alertAckView(warned, { incidentSeq: 2, acknowledged: false })).toBe("result"); // the answer, before the refreshed rows
    expect(alertAckView(warned, { incidentSeq: 3, acknowledged: true })).toBe("result"); // after the refresh hides the form
    expect(alertAckView(warned, { incidentSeq: 4, acknowledged: false })).toBe("form"); // a newer incident needs its own acknowledgement
    expect(alertAckView(warned, { incidentSeq: 4, acknowledged: true })).toBe("none");
    expect(alertAckView({}, { incidentSeq: 2, acknowledged: false })).toBe("form");
    expect(alertAckView({}, { incidentSeq: 2, acknowledged: true })).toBe("none");
    expect(alertAckView({ submitted: true, refused: "precondition_failed: …" }, { incidentSeq: 2, acknowledged: false })).toBe("form");
  });

  it("the warning reads as a warning, in the action's words; a plain acknowledgement as a success", () => {
    const warn = renderToStaticMarkup(
      createElement(AlertAckResult, { state: { acknowledgedAt: "2026-10-21T10:00:00Z", incidentSeq: 3, shownIncidentSeq: 2, warning: "A new incident #3 opened since you loaded this page, which showed incident #2; it is now acknowledged." } }),
    );
    expect(warn).toContain("not the incident this page showed");
    expect(warn).toContain("A new incident #3 opened since you loaded this page, which showed incident #2; it is now acknowledged.");
    expect(warn).toContain("stays firing until the condition clears");
    const ok = renderToStaticMarkup(createElement(AlertAckResult, { state: { acknowledgedAt: "2026-10-21T10:00:00Z", incidentSeq: 2, shownIncidentSeq: 2 } }));
    expect(ok).toContain("Acknowledged.");
    expect(ok).toContain("Incident #2.");
    expect(ok).not.toContain("not the incident");
  });
});

describe("/system uses the ported panel, and owner-decision settings say so", () => {
  const page = readFileSync(resolve(__dirname, "../src/app/(console)/system/page.tsx"), "utf8");
  const help = (key: string) => page.match(new RegExp(`\\n\\s*${key}:\\s*\\n?\\s*"([^"]+)"`))?.[1] ?? "";

  it("renders AlertList for the firing alerts", () => {
    expect(page).toContain("<AlertList alerts={health.alerts} meId={me.id} />");
  });

  it("alert_delivery_enabled and refund_resolution_detector_enabled are named owner decisions, with no instruction to flip them", () => {
    for (const key of ["alert_delivery_enabled", "refund_resolution_detector_enabled"]) {
      const text = help(key);
      expect(text, key).toMatch(/^Owner decision; not changed without the owner\./);
      expect(text, key).not.toMatch(/\b(flip|set (it )?(back )?to true|turn (it )?on)\b/i);
    }
  });
});
