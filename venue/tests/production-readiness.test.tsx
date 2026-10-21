/**
 * Guards for the production-readiness branch (venue/production-readiness, 2026-10-21): what a
 * database-mode host at venue.snatchitapp.com needs that the fixture demo never exercised.
 * Each block names the fix it guards; each was run against the unfixed code first and failed.
 */
import { existsSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);

describe("database mode has a route loading state (loading.tsx under o/[org]/v/[venue])", () => {
  it("the segment ships a loading.tsx", () => {
    expect(existsSync(new URL("../src/app/o/[org]/v/[venue]/loading.tsx", import.meta.url))).toBe(true);
  });
  it("renders an accessible, mode-neutral skeleton with the main landmark", async () => {
    const { default: Loading } = await import("@/app/o/[org]/v/[venue]/loading");
    const out = html(<Loading />);
    expect(out).toContain('id="main"');
    expect(out).toContain('role="status"');
    expect(out).toContain('aria-live="polite"');
    expect(out).toContain("Loading");
    expect(out).toContain('class="skel"');
    // Shown in both modes before the page knows who is looking: no data, no mode, no role.
    expect(out).not.toMatch(/sample|demo|fixture|database|Venue manager|Org owner/i);
  });
});
