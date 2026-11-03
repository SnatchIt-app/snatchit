import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import nextConfig, { SCAN_PERMISSIONS_POLICY, SCAN_ROUTE } from "../next.config";

describe("camera permission is granted to the scanner route only", () => {
  it("the catch-all still denies the camera; the scan route, listed last so it wins, allows it for this origin and nothing else", async () => {
    const rules = await nextConfig.headers!();
    expect(rules[0].source).toBe("/(.*)");
    expect(rules[0].headers.find((h) => h.key === "Permissions-Policy")?.value).toContain("camera=()");
    const last = rules[rules.length - 1];
    expect(last.source).toBe(SCAN_ROUTE);
    expect(last.headers).toEqual([{ key: "Permissions-Policy", value: SCAN_PERMISSIONS_POLICY }]);
    expect(SCAN_PERMISSIONS_POLICY).toContain("camera=(self)");
    for (const denied of ["microphone=()", "geolocation=()", "payment=()", "usb=()"]) expect(SCAN_PERMISSIONS_POLICY).toContain(denied);
    expect(rules.filter((r) => r.source === SCAN_ROUTE)).toHaveLength(1);
  });
  it("the route pattern is the scanner page's own path", () => {
    expect(SCAN_ROUTE).toBe("/o/:org/v/:venue/events/:event/scan");
    expect(existsSync(resolve(__dirname, "../src/app/o/[org]/v/[venue]/events/[event]/scan/page.tsx"))).toBe(true);
  });
  it("the CSP did not gain a browser-side backend origin: the scanner talks to its own server actions", async () => {
    const csp = (await nextConfig.headers!())[0].headers.find((h) => h.key === "Content-Security-Policy")?.value ?? "";
    expect(csp).toContain("connect-src 'self'");
    expect(csp).not.toContain("supabase.co");
  });
});
