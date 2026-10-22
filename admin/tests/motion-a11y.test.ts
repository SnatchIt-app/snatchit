import { createElement, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * V-1 item 5 — motion and accessibility of everything V-1 added: any
 * transition or animation is at most 200 ms and is disabled under
 * prefers-reduced-motion by the stylesheet's global rule; every new control is
 * a native element with the global visible focus ring and a sensible focus
 * order; nothing new can widen a phone layout. Checked the way
 * a11y-responsive.test.ts checks: on the sources and the rendered markup.
 */
import { ClientTable } from "@/components/ui/ClientTable";
import { SortFilterList } from "@/components/ui/SortFilterList";
import { HowThisWorks } from "@/components/orders/WorkflowDiagrams";

const SRC = resolve(__dirname, "../src");
const src = (rel: string) => readFileSync(resolve(SRC, rel), "utf8");
const css = src("app/globals.css");
const h = (el: ReactElement) => renderToStaticMarkup(el);

/** Everything V-1 added or rewrote. */
const NEW_COMPONENTS = [
  "components/ui/ClientTable.tsx",
  "components/ui/SortFilterList.tsx",
  "components/ui/StatusBreakdown.tsx",
  "components/ui/HiddenTestRowsNotice.tsx",
  "components/analytics/PeriodComparison.tsx",
  "components/orders/WorkflowDiagrams.tsx",
  "components/charts/FigureMeta.tsx",
  "components/charts/KpiTile.tsx",
  "components/charts/ChartCard.tsx",
];
/** The CSS rules V-1 added. */
const NEW_CSS_RULES = [".reveal"];

const ms = (value: string): number => {
  const m = value.trim().match(/^([\d.]+)(ms|s)$/);
  if (!m) throw new Error(`not a duration: ${value}`);
  return m[2] === "s" ? Number(m[1]) * 1000 : Number(m[1]);
};
/** The css text of one top-level rule. */
const rule = (selector: string): string => {
  const i = css.indexOf(`${selector} {`);
  expect(i, `${selector} is defined in globals.css`).toBeGreaterThan(-1);
  return css.slice(i, css.indexOf("}", i));
};

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

describe("motion: at most 200 ms, and none under prefers-reduced-motion", () => {
  it("the stylesheet's global reduced-motion rule removes every animation and transition", () => {
    const block = css.slice(css.indexOf("@media (prefers-reduced-motion: reduce)"));
    const body = block.slice(0, block.indexOf("}", block.indexOf("}") + 1));
    expect(body).toMatch(/\*,\s*\*::before,\s*\*::after\s*\{/);
    expect(body).toContain("animation-duration: 0.01ms !important;");
    expect(body).toContain("animation-iteration-count: 1 !important;");
    expect(body).toContain("transition-duration: 0.01ms !important;");
  });

  it("every duration in the rules V-1 added is at most 200 ms", () => {
    for (const sel of NEW_CSS_RULES) {
      const text = rule(sel);
      const durations = [...text.matchAll(/(?:animation|transition)\s*:\s*[^;]*?(\d+(?:\.\d+)?m?s)/g)].map((m) => ms(m[1]));
      expect(durations.length, `${sel} declares a timed animation or transition`).toBeGreaterThan(0);
      for (const d of durations) expect(d, `${sel}: ${d}ms`).toBeLessThanOrEqual(200);
    }
  });

  it("every Tailwind duration in the new components is at most 200 ms, and none adds a continuous animation", () => {
    for (const rel of NEW_COMPONENTS) {
      const s = src(rel);
      for (const m of s.matchAll(/\bduration-(\d+)\b/g)) expect(Number(m[1]), `${rel}: duration-${m[1]}`).toBeLessThanOrEqual(200);
      for (const m of s.matchAll(/\b(?:transition|animation)\s*:\s*[^;"']*?(\d+(?:\.\d+)?m?s)/g)) expect(ms(m[1]), `${rel}: ${m[0]}`).toBeLessThanOrEqual(200);
      // a loop (pulse, spin, bounce, ping) is never restrained; the chart skeleton's pulse predates V-1 and is excluded
      expect(s.replace(/function ChartSkeleton[\s\S]*$/, ""), `${rel}: no animate-* utility`).not.toMatch(/\banimate-(?!none\b)/);
    }
  });

  it("the disclosure's reveal is the only animation V-1 adds, and it is used where the disclosure opens", () => {
    expect(rule(".reveal")).toMatch(/animation:\s*fade-in\s+1[2-6]0ms/);
    expect(src("components/orders/WorkflowDiagrams.tsx")).toContain('className="reveal mt-4 space-y-6"');
  });
});

// ---------------------------------------------------------------------------
// Focus: native controls, the global ring, a sensible order
// ---------------------------------------------------------------------------

describe("focus: new controls are native, keep the global visible ring, and come in reading order", () => {
  it("the stylesheet gives every focused control a visible ring", () => {
    expect(css).toMatch(/:focus-visible\s*\{\s*outline:\s*2px solid #231e1a;/);
  });

  it("no new control hides its outline or leaves the tab order", () => {
    for (const rel of NEW_COMPONENTS) {
      const s = src(rel);
      expect(s, rel).not.toMatch(/\boutline-none\b/);
      expect(s, rel).not.toMatch(/tabIndex=\{-1\}/);
      expect(s, rel).not.toMatch(/\bonKeyDown=/); // native buttons, inputs and selects need no key handler
    }
  });

  const rows = [
    { key: "a", cells: ["A", "1"], sort: { n: 1 }, filter: "a" },
    { key: "b", cells: ["B", "2"], sort: { n: 2 }, filter: "b" },
  ];
  const columns = [
    { key: "name", header: "Name", headerText: "Name", sortable: false, firstDir: "asc" as const },
    { key: "n", header: "N", headerText: "N", sortable: true, firstDir: "asc" as const },
  ];

  it("ClientTable: the filter field comes before the sort buttons, which come before the rows; the status is a polite live region", () => {
    const html = h(createElement(ClientTable, { columns, rows, filterable: true, emptyText: "none" }));
    const field = html.search(/<input[^>]*type="search"/);
    const button = html.indexOf('<button type="button"');
    const body = html.indexOf("<tbody");
    expect(field).toBeGreaterThan(-1);
    expect(field).toBeLessThan(button);
    expect(button).toBeLessThan(body);
    expect(html).toMatch(/<p id="[^"]+" role="status" aria-live="polite"/);
    expect(html).toMatch(/<input id="([^"]+)"[^>]*aria-describedby="([^"]+)"/);
  });

  it("SortFilterList: select, direction button, filter field, then the list; every control labelled", () => {
    const html = h(createElement(SortFilterList, { items: [{ key: "x", node: createElement("li", null, "x"), sort: { d: "1" }, filter: "x" }], sortOptions: [{ key: "d", label: "Detected" }], noun: "cases", listDescribedBy: "queue-keys" }));
    const select = html.indexOf("<select");
    const button = html.indexOf('<button type="button"');
    const field = html.search(/<input[^>]*type="search"/);
    const list = html.indexOf("<ul");
    expect(select).toBeGreaterThan(-1);
    expect(select).toBeLessThan(button);
    expect(button).toBeLessThan(field);
    expect(field).toBeLessThan(list);
    expect(html).toMatch(/<label for="([^"]+)"[^>]*><span>Sort<\/span><select id="\1"/);
    expect(html).toMatch(/<label for="([^"]+)"[^>]*><span>Filter rows on this page<\/span><input id="\1"/);
    expect(html).toMatch(/<button type="button" aria-label="Sort direction: ascending"/);
  });

  it("HowThisWorks: a native disclosure whose summary is the only control; the diagrams inside are images, not controls", () => {
    const html = h(createElement(HowThisWorks));
    expect(html).toMatch(/^<details class="[^"]*"><summary class="[^"]*">How this works<\/summary>/);
    expect(html.match(/<button/g) ?? []).toHaveLength(0);
    expect(html.match(/<a /g) ?? []).toHaveLength(0);
    expect(html.match(/<svg[^>]*role="img"/g)?.length).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// Phone width: nothing new widens the page
// ---------------------------------------------------------------------------

describe("phone width: every new element shrinks, wraps or scrolls inside its container", () => {
  it("tables and the comparison scroll inside their container", () => {
    expect(src("components/ui/ClientTable.tsx")).toMatch(/<div className=\{`overflow-x-auto /);
    expect(src("components/analytics/PeriodComparison.tsx")).toContain('<div className="overflow-x-auto">');
  });
  it("toolbars wrap and their fields never exceed the viewport", () => {
    for (const rel of ["components/ui/ClientTable.tsx", "components/ui/SortFilterList.tsx"]) {
      const s = src(rel);
      expect(s, rel).toMatch(/<div className="flex flex-wrap items-center gap-x-4 gap-y-2/);
      expect(s, rel).toMatch(/w-\[min\(1\drem,calc\(100vw-4rem\)\)\]/);
      expect(s, rel).toMatch(/<label htmlFor=\{filterId\} className="flex min-w-0 flex-wrap/);
    }
  });
  it("the breakdown bar fills its column and its legend wraps; the grids are one column first", () => {
    const s = src("components/ui/StatusBreakdown.tsx");
    expect(s).toMatch(/data-breakdown-bar="" aria-hidden="true" className="[^"]*\bw-full\b[^"]*\boverflow-hidden\b/);
    expect(s).toMatch(/<ul className="[^"]*\bflex-wrap\b/);
    expect(s).toMatch(/<div data-breakdown="" className="min-w-0">/);
    expect(src("app/(console)/orders/page.tsx")).toContain('className="grid grid-cols-1 gap-4 border-b border-line px-3 py-3 md:grid-cols-3 md:px-4"');
    expect(src("app/(console)/cases/page.tsx")).toContain('className="grid grid-cols-1 gap-4 border-b border-line px-3 py-3 sm:grid-cols-2 md:px-4"');
  });
  it("the diagrams scale with their container: a viewBox, no fixed width or height, w-full max-w-full h-auto", () => {
    const html = h(createElement(HowThisWorks));
    for (const svg of html.match(/<svg[^>]*>/g) ?? []) {
      expect(svg).toMatch(/viewBox="0 0 360 \d+"/);
      expect(svg).not.toMatch(/\swidth="/);
      expect(svg).not.toMatch(/\sheight="/);
      expect(svg).toMatch(/class="[^"]*\bw-full\b[^"]*\bmax-w-full\b/);
      expect(svg).toMatch(/class="[^"]*\bh-auto\b/);
    }
    expect(html.match(/<svg/g)?.length).toBe(2);
    expect(src("components/orders/WorkflowDiagrams.tsx")).toContain('<figure className="min-w-0">');
  });
  it("the label line and the tile states never force a single line", () => {
    for (const rel of ["components/charts/FigureMeta.tsx", "components/charts/KpiTile.tsx", "components/ui/HiddenTestRowsNotice.tsx"]) {
      expect(src(rel), rel).not.toContain("whitespace-nowrap");
    }
  });
});
