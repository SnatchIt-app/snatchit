import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ChartCard } from "@/components/charts/ChartCard";
import { NAV } from "@/lib/nav";

const table = { caption: "Captured sales per day", head: ["Period", "Sales (USD)"], rows: [["Nov 24", "$25.00"], ["Nov 25 (today so far)", "Unknown"]] };

describe("dashboard presentation keeps exact data accessible", () => {
  it("offers three labelled views with one active view and preserves unknown and partial values", () => {
    const html = renderToStaticMarkup(createElement(ChartCard, { title: "Captured sales", description: "USD per day", state: { kind: "ok" }, table, definition: "Captured payments only." }, createElement("svg", { "aria-label": "Sales trend" })));
    expect(html).toContain('aria-label="Captured sales view"');
    expect(html.match(/aria-checked="true"/g)).toHaveLength(1);
    expect(html.match(/aria-checked="false"/g)).toHaveLength(2);
    expect(html).toContain('scope="row">Nov 24');
    expect(html).toContain("$25.00");
    expect(html).toContain("Nov 25 (today so far)");
    expect(html).toContain("Unknown");
    expect(html).toContain("Details · how to read this figure");
    expect(html).toContain("Captured payments only.");
  });
  it("an unavailable read offers no data views or fabricated values", () => {
    const html = renderToStaticMarkup(createElement(ChartCard, { title: "Sales", description: "USD", state: { kind: "unavailable", message: "Not returned by the server." }, table }));
    expect(html).toContain("Not available");
    expect(html).not.toContain("aria-checked");
    expect(html).not.toContain("$25.00");
  });
  it("every existing navigation destination explains the task without adding routes", () => {
    expect(NAV).toHaveLength(8);
    for (const item of NAV) expect(item.description.length).toBeGreaterThan(10);
  });
});
