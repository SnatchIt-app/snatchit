import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: () => undefined, push: () => undefined, replace: () => undefined }) }));

import { SessionCapacityForm } from "@/components/events/EventCommandForms";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const ids = { orgId: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2", venueId: "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75", eventId: "9a000000-0000-4000-8000-000000000001" };
const SESSION = "5e55e55e-0000-4000-8000-000000000001";
const base = { ids, commandKey: "k-cap", sessionId: SESSION };

/**
 * The pool form shows the server's own boundaries (migration 166) so the operator
 * is not left to discover them from a refusal — and says nothing at all when the
 * read is unavailable, rather than standing a zero in for an unknown.
 */
describe("the pool form shows what the server knows, and nothing it does not", () => {
  it("with the read: the pool, what releases hold, what is left, and the venue capacity", () => {
    const out = html(createElement(SessionCapacityForm, { ...base, capacity: 50, allocated: 40, remainingToAllocate: 10, capacityHint: 250 }));
    expect(out).toContain("Pool now: 50.");
    expect(out).toContain("Already allocated to releases: 40");
    expect(out).toContain("10 left to allocate");
    expect(out).toContain("Venue capacity 250.");
    expect(out).toContain('name="capacity"');
    expect(out).toContain('value="50"');
    expect(out).toContain('name="reason_code"');
  });
  it("an unlimited pool says so instead of showing a number", () => {
    const out = html(createElement(SessionCapacityForm, { ...base, capacity: null, allocated: 12, remainingToAllocate: null, capacityHint: null }));
    expect(out).toContain("No limit set");
    expect(out).toContain("Already allocated to releases: 12");
    expect(out).not.toContain("left to allocate");
    expect(out).not.toContain("Venue capacity");
    expect(out).not.toContain("Pool now");
  });
  it("without the read: no numbers are invented, and it says the server will name them", () => {
    const out = html(createElement(SessionCapacityForm, base));
    expect(out).toContain("not readable on this project yet");
    expect(out).not.toContain("Already allocated");
    expect(out).not.toContain("Pool now");
    // the capacity input itself carries no default, so nothing stands in for the unknown pool
    const tag = out.match(/<input[^>]*name="capacity"[^>]*>/)?.[0] ?? "";
    expect(tag).not.toBe("");
    expect(tag).toContain('value=""'); // empty, not a number standing in for the unknown pool
    expect(tag).not.toMatch(/value="[0-9]/);
  });
  it("a venue capacity with no pool set still shows both facts it has", () => {
    const out = html(createElement(SessionCapacityForm, { ...base, capacity: null, allocated: 0, remainingToAllocate: null, capacityHint: 250 }));
    expect(out).toContain("No limit set");
    expect(out).toContain("Venue capacity 250.");
  });
});
