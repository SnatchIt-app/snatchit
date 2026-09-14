import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("next/navigation", () => ({ usePathname: () => "/cases/abc", useRouter: () => ({ push: () => {} }) }));

import { NAV, isNavActive } from "@/lib/nav";
import { NAV as SIDEBAR_NAV } from "@/components/shell/Sidebar";
import { MobileNav, MobileNavPanel } from "@/components/shell/MobileNav";

/**
 * F9 — below `md` (768 px) the console had no navigation at all. The mobile menu
 * must offer exactly the sidebar's sections (no new routes, no data reads) and be
 * keyboard/screen-reader operable.
 */
describe("F9 navigation model", () => {
  it("Today is active only on /", () => {
    expect(isNavActive("/", "/")).toBe(true);
    expect(isNavActive("/cases", "/")).toBe(false);
  });
  it("a section is active on itself and its detail pages, not on look-alike prefixes", () => {
    expect(isNavActive("/cases", "/cases")).toBe(true);
    expect(isNavActive("/cases/123", "/cases")).toBe(true);
    expect(isNavActive("/casesx", "/cases")).toBe(false);
  });
  it("the sidebar and the mobile menu share one list (same sections, same order)", () => {
    expect(SIDEBAR_NAV).toBe(NAV);
    expect(NAV.map((n) => n.href)).toEqual(["/", "/cases", "/orders", "/money", "/users", "/marketplace", "/reports", "/system"]);
  });
});

describe("F9 mobile menu rendering", () => {
  const panel = (open: boolean, pathname = "/cases/abc") =>
    renderToStaticMarkup(createElement(MobileNavPanel, { id: "mobile-nav", open, pathname, onNavigate: () => {} }));

  it("renders nothing while closed", () => {
    expect(panel(false)).toBe("");
  });

  it("open: a labelled nav with every section, exact hrefs, and aria-current on the active one only", () => {
    const html = panel(true);
    expect(html).toContain('<nav id="mobile-nav" aria-label="Console sections (menu)"');
    for (const item of NAV) expect(html).toContain(`href="${item.href}"`);
    expect(html.match(/href="/g)?.length).toBe(NAV.length);
    expect(html.match(/aria-current="page"/g)?.length).toBe(1);
    expect(html).toMatch(/<a[^>]*aria-current="page"[^>]*href="\/cases"|<a[^>]*href="\/cases"[^>]*aria-current="page"/);
  });

  it("the toggle is a real button, collapsed by default, wired to the panel, and hidden from md up", () => {
    const html = renderToStaticMarkup(createElement(MobileNav));
    expect(html).toContain('aria-expanded="false"');
    expect(html).toContain('aria-controls="mobile-nav"');
    expect(html).toMatch(/<button[^>]*type="button"/);
    expect(html).toContain("md:hidden");
    expect(html).not.toContain("<nav");
  });
});
