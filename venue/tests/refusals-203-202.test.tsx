import type { ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: () => undefined, push: () => undefined, replace: () => undefined }) }));

import { EventCommandPanel, type EventCommandKeys } from "@/components/events/EventCommandPanel";
import { FEE_POLICY_INVALID_COPY, REFUSAL_COPY, refusalCopy, refusalToken } from "@/lib/events/command-contract";
import { venueTimeZone } from "@/lib/events/zone";
import type { Event } from "@/lib/types";

/**
 * D's 203 (#226) and 202 (#225), draft, not applied. Their exact server messages:
 *  - cancel_event on a completed event: "precondition_failed: event_completed — a completed event is not
 *    cancelled; refunds after the event go through admin refunds"
 *  - update_event_session on a completed or cancelled event: "precondition_failed: event_terminal"
 *  - publish_event fee refusals keep the prefix "precondition_failed: fee_policy_unset" and append a reason
 *    after " — ": "has no value", "is a JSON <type>, not a number", "must be an integer 0..10000, got <v>".
 */
const ORG = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";
const VEN = "1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e";
const EVT = "2c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f";
const SES = "3d4e5f6a-7b8c-4d9e-8f0a-1b2c3d4e5f6a";
const html = (el: ReactElement) => renderToStaticMarkup(el);
const ids = { orgId: ORG, venueId: VEN, eventId: EVT };
const keys: EventCommandKeys = { details: "k-details", publish: "k-publish", cancel: "k-cancel", sessionNew: "k-new", session: { [SES]: "k-session" }, capacity: { [SES]: "k-capacity" } };
const event = (status: string) =>
  ({ eventId: EVT, venueId: VEN, orgId: ORG, title: "Fixture night", status, resaleMode: "off", sessions: [{ sessionId: SES, eventId: EVT, label: "Doors", startsAt: "2026-12-06T01:00:00Z", doorsAt: null, endsAt: null, status: "scheduled", doorOpenAt: null }] }) as Event;
const panel = (status: string) => html(<EventCommandPanel ids={ids} event={event(status)} keys={keys} zone={venueTimeZone("database", "America/New_York")} capacities={{}} />);

describe("203: refusals on finished events, in the operator's words", () => {
  it("cancel on a completed event says it is already completed and who handles refunds", () => {
    const m = "precondition_failed: event_completed — a completed event is not cancelled; refunds after the event go through admin refunds";
    expect(refusalToken(m)).toBe("event_completed");
    expect(refusalCopy(m)).toBe(REFUSAL_COPY.event_completed);
    expect(refusalCopy(m)).toContain("already completed");
    expect(refusalCopy(m)).toContain("Snatch It");
  });
  it("a session change on a finished event maps to event_terminal", () => {
    expect(refusalCopy("precondition_failed: event_terminal")).toBe(REFUSAL_COPY.event_terminal);
  });
});

describe("202: fee refusals match on the prefix, and the copy follows the appended reason", () => {
  const prefix = "precondition_failed: fee_policy_unset";
  it("no value (or no reason, from a server before 202) reads 'not set yet'", () => {
    expect(refusalCopy(prefix)).toBe(REFUSAL_COPY.fee_policy_unset);
    expect(refusalCopy(`${prefix} — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it`)).toBe(REFUSAL_COPY.fee_policy_unset);
  });
  it("a stored but invalid fee says so, instead of 'not set yet'", () => {
    for (const m of [
      `${prefix} — fee.buyer_service_bps is a JSON string, not a number; this event cannot go on sale until the owner sets an integer`,
      `${prefix} — fee.buyer_service_bps must be an integer 0..10000, got 12000; this event cannot go on sale until the owner corrects it`,
    ]) {
      expect(refusalToken(m), m).toBe("fee_policy_unset");
      expect(refusalCopy(m), m).toBe(FEE_POLICY_INVALID_COPY);
    }
    expect(FEE_POLICY_INVALID_COPY).toContain("Snatch It");
  });
});

describe("203 / D's F-18: a finished event offers no session, capacity or add-night form", () => {
  for (const status of ["completed", "cancelled"]) {
    it(`${status}: the forms are gone, and the page says why`, () => {
      const h = panel(status);
      for (const key of ["k-session", "k-capacity", "k-new", "k-cancel"]) expect(h, key).not.toContain(`value="${key}"`);
      expect(h).not.toContain("Add another night");
      expect(h).toContain(`This event is ${status}. Its nights, times and capacity can no longer change.`);
    });
  }
  it("NEGATIVE CONTROL — an event that is not finished still offers every form", () => {
    for (const status of ["draft", "announced", "on_sale"]) {
      const h = panel(status);
      for (const key of ["k-session", "k-capacity", "k-new", "k-cancel"]) expect(h, `${status} ${key}`).toContain(`value="${key}"`);
      expect(h).toContain("Add another night");
    }
  });
});
