import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { SummaryView } from "@/components/system/SummaryView";
import type { DailySummary } from "@/lib/types";

function render(cases: Record<string, unknown>) {
  const summary: DailySummary = {
    summary_date: "2026-11-24",
    generated_at: "2026-11-25T13:00:00Z",
    delivery_state: "portal_only",
    body: {
      cases,
      money: { live_24h: { captured_cents: 110, captured_count: 3, released_to_connected_cents: 180 } },
    },
  };
  return renderToStaticMarkup(createElement(SummaryView, { summary }));
}

describe("daily summary case counts retain their units", () => {
  it.each([0, 20, 1234])("renders %i open cases as a count, never cents", (count) => {
    const html = render({ open_total: count });
    const open = html.match(/<dt[^>]*>Open total<\/dt><dd[^>]*>(.*?)<\/dd>/)?.[1];
    expect(open).toBe(count.toLocaleString("en-US"));
    expect(html).toContain('data-cents="110"');
    expect(html).toContain("$1.10 USD");
    expect(html).toContain('data-cents="180"');
    expect(html).toContain("$1.80 USD");
    expect(html).not.toContain('data-cents="3"');
  });

  it("keeps missing counts unknown", () => {
    const html = render({ open_total: null });
    expect(html).toMatch(/Open total<\/dt><dd[^>]*><span[^>]*>—<\/span><\/dd>/);
  });
});
