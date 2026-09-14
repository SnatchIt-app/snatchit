import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const src = (rel: string) => readFileSync(resolve(__dirname, "../src/app/(console)", rel), "utf8");
const DETAIL_PAGES = ["marketplace/[id]/page.tsx", "cases/[id]/page.tsx", "users/[id]/page.tsx", "orders/[paymentId]/page.tsx", "actions/[id]/page.tsx"];

describe("detail pages do not overflow below lg (UI audit: 1066-1374 px wide pages at 768)", () => {
  it.each(DETAIL_PAGES)("%s declares a minmax(0,1fr) single column before lg:grid-cols-3", (rel) => {
    const s = src(rel);
    expect(s).not.toMatch(/className="grid gap-6 lg:grid-cols-3"/);
    expect(s).toMatch(/className="grid grid-cols-1 gap-6 lg:grid-cols-3"/);
  });
});

describe("System settings controls have their own ids (UI audit: 3 unnamed comboboxes)", () => {
  it("the <li> anchor and the form control no longer share an id", () => {
    const s = src("system/page.tsx");
    expect(s).toContain("const inputId = `setting-${s.key}-value`;");
    expect(s).toContain('id={`setting-${s.key}`}');
  });
});
