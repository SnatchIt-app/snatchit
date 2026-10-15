import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { safeInternalPath } from "@/lib/auth/redirect";

// Auth emails now return the session in the URL fragment (implicit flow, any device). These pin
// the safeguards around that: the page strips the fragment before any client or network work,
// nothing that reports telemetry reads the page URL, the route sends no Referer and is not cached,
// and `next` stays a same-origin path.
const read = (p: string) => readFileSync(path.resolve(__dirname, "..", p), "utf8");

describe("/auth/confirm handles a session-bearing fragment safely", () => {
  it("strips an implicit fragment before creating the Supabase client", () => {
    const page = read("src/app/auth/confirm/page.tsx");
    // null state: Next's patched replaceState then syncs the router URL too (passing history.state
    // would skip that, and the router could write the fragment back on a later update).
    expect(page).not.toContain("replaceState(window.history.state");
    const strip = page.indexOf('window.history.replaceState(null, "", window.location.pathname + window.location.search)');
    const client = page.indexOf("const supabase = getSupabaseBrowserClient();");
    expect(strip).toBeGreaterThan(-1);
    expect(client).toBeGreaterThan(strip);
    expect(page.slice(page.lastIndexOf("if (", strip), strip)).toContain('link.kind === "implicit"');
  });

  it("the error reporter never reads the page URL", () => {
    const obs = read("src/lib/observability.ts");
    expect(obs).not.toMatch(/\blocation\b|document\.URL|\bhref\b/);
  });

  it("sends Referrer-Policy: no-referrer and no-store on /auth/confirm, after the global rule", async () => {
    const mod = await import("../next.config");
    const rules = await mod.default.headers!();
    expect(rules[0].source).toBe("/(.*)");
    const confirm = rules.find((r) => r.source === "/auth/confirm");
    expect(confirm).toBeDefined();
    expect(rules.indexOf(confirm!)).toBeGreaterThan(0);
    expect(confirm!.headers).toEqual(
      expect.arrayContaining([
        { key: "Referrer-Policy", value: "no-referrer" },
        { key: "Cache-Control", value: "no-store" },
      ]),
    );
  });

  it("next= stays a same-origin path", () => {
    expect(safeInternalPath("/reset-password", "/account")).toBe("/reset-password");
    expect(safeInternalPath("https://evil.example/x", "/account")).toBe("/account");
    expect(safeInternalPath("//evil.example/x", "/account")).toBe("/account");
  });
});
