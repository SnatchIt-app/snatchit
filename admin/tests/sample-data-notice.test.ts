import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, describe, expect, it, vi } from "vitest";

/**
 * F2 (AV2-05) — "Sample data … fixture data, not Snatch It business data" is a
 * claim about where the figures come from. It used to fire for any label
 * matching /local|harness|rehears|sample|preview/i, and the label defaults to
 * "local" when NEXT_PUBLIC_ENV_LABEL is unset — so a hosted non-production
 * deploy on a real database would have called real money "fixture data".
 * Now: only an explicitly set label that is exactly local, harness or
 * rehearsal, and never on a Vercel production or preview deployment.
 * env.ts is read at import, so each case re-imports with stubbed env.
 */
vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({ usePathname: () => "/", useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }), useParams: () => ({}) }));

const NOTICE = "Sample data.";

async function notice(env: { label?: string; vercel?: string }): Promise<string> {
  vi.resetModules();
  vi.stubEnv("NEXT_PUBLIC_ENV_LABEL", env.label);
  vi.stubEnv("NEXT_PUBLIC_VERCEL_ENV", env.vercel);
  const { SampleDataNotice } = await import("@/components/analytics/sections");
  return renderToStaticMarkup(createElement(SampleDataNotice));
}

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("F2 — SampleDataNotice only for an explicit local harness label", () => {
  it("shown for exactly local, harness or rehearsal off Vercel (positive control)", async () => {
    for (const label of ["local", "harness", "rehearsal"]) {
      const html = await notice({ label });
      expect(html, label).toContain(NOTICE);
      expect(html, label).toContain(`(${label})`);
    }
    // `vercel dev` reports development — still a local machine.
    expect(await notice({ label: "harness", vercel: "development" })).toContain(NOTICE);
  });

  it("not shown when NEXT_PUBLIC_ENV_LABEL is unset (the 'local' default is not a claim about the data)", async () => {
    expect(await notice({})).toBe("");
    expect(await notice({ label: "" })).toBe("");
    expect(await notice({ label: "   " })).toBe("");
  });

  it("never for preview, sample or other look-alike labels", async () => {
    for (const label of ["preview", "Preview", "sample", "staging-preview", "local-preview", "rehearsal-2", "harness ", "LOCAL", "local harness", "sandbox", "staging", "production", "ci"]) {
      const html = await notice({ label });
      if (label === "harness ") {
        // Surrounding whitespace is trimmed, exactly as ENV_LABEL is.
        expect(html, JSON.stringify(label)).toContain(NOTICE);
        continue;
      }
      expect(html, JSON.stringify(label)).toBe("");
    }
  });

  it("never on a Vercel production or preview deployment, whatever the label", async () => {
    for (const vercel of ["production", "preview"]) {
      for (const label of ["local", "harness", "rehearsal"]) {
        expect(await notice({ label, vercel }), `${label}@${vercel}`).toBe("");
      }
    }
  });
});

describe("F2 — sampleDataLabel (pure rule)", () => {
  it("exact allowlist, explicit only, never on Vercel production/preview", async () => {
    const { sampleDataLabel, SAMPLE_DATA_LABELS } = await import("@/lib/env-policy");
    expect(SAMPLE_DATA_LABELS).toEqual(["local", "harness", "rehearsal"]);
    expect(sampleDataLabel({ label: "rehearsal", vercelEnv: undefined })).toBe("rehearsal");
    expect(sampleDataLabel({ label: " local ", vercelEnv: "development" })).toBe("local");
    expect(sampleDataLabel({ label: undefined, vercelEnv: undefined })).toBeNull();
    expect(sampleDataLabel({ label: "preview", vercelEnv: undefined })).toBeNull();
    expect(sampleDataLabel({ label: "local", vercelEnv: "preview" })).toBeNull();
    expect(sampleDataLabel({ label: "local", vercelEnv: "production" })).toBeNull();
  });
});
