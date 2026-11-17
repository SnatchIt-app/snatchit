import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, describe, expect, it, vi } from "vitest";

/**
 * F2 (AV2-05) — "Sample data … fixture data, not Snatch It business data" is a
 * claim about where the figures come from. It used to fire for any label
 * matching /local|harness|rehears|sample|preview/i, and the label defaults to
 * "local" when NEXT_PUBLIC_ENV_LABEL is unset — so a hosted non-production
 * deploy on a real database would have called real money "fixture data".
 *
 * A label alone is not proof either: admin/.env.example ships
 * NEXT_PUBLIC_ENV_LABEL=local, and a developer who fills in the production
 * Supabase URL from that template runs `next dev` with that label. So the
 * notice needs BOTH an explicitly set label of exactly harness or rehearsal
 * AND a NEXT_PUBLIC_SUPABASE_URL whose hostname is loopback (localhost,
 * 127.0.0.1 or ::1), and it never shows on a Vercel production or preview
 * deployment. env.ts is read at import, so each case re-imports with stubbed env.
 */
vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({ usePathname: () => "/", useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }), useParams: () => ({}) }));

const NOTICE = "Sample data.";
/** The harness origin (admin/.env.local.example-harness). */
const HARNESS_URL = "http://localhost:3202";
/** Synthetic hosted project URLs: real-database shapes, not real projects. */
const HOSTED_URLS = ["https://synthetic-ref.supabase.co", "https://db.example.com", "http://10.0.0.5:3202", "http://192.168.1.20:54321"];

async function notice(env: { label?: string; vercel?: string; url?: string | null }): Promise<string> {
  vi.resetModules();
  vi.stubEnv("NEXT_PUBLIC_ENV_LABEL", env.label);
  vi.stubEnv("NEXT_PUBLIC_VERCEL_ENV", env.vercel);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", env.url === null ? undefined : (env.url ?? HARNESS_URL));
  const { SampleDataNotice } = await import("@/components/analytics/sections");
  return renderToStaticMarkup(createElement(SampleDataNotice));
}

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("F2 — SampleDataNotice only for a harness label on a loopback Supabase URL", () => {
  it("shown for exactly harness or rehearsal on a loopback URL off Vercel (positive control)", async () => {
    for (const label of ["harness", "rehearsal"]) {
      for (const url of [HARNESS_URL, "http://127.0.0.1:54321", "http://[::1]:3202", "https://localhost"]) {
        const html = await notice({ label, url });
        expect(html, `${label}@${url}`).toContain(NOTICE);
        expect(html, `${label}@${url}`).toContain(`(${label})`);
      }
    }
    // `vercel dev` reports development — still a local machine.
    expect(await notice({ label: "harness", vercel: "development" })).toContain(NOTICE);
  });

  it("label=local (the .env.example default) is not a claim about the data — no notice, whatever the URL", async () => {
    for (const url of [...HOSTED_URLS, HARNESS_URL]) {
      expect(await notice({ label: "local", url }), url).toBe("");
    }
  });

  it("a harness label pointed at a non-loopback Supabase URL → no notice", async () => {
    for (const label of ["harness", "rehearsal"]) {
      for (const url of HOSTED_URLS) {
        expect(await notice({ label, url }), `${label}@${url}`).toBe("");
      }
    }
  });

  it("no notice when the Supabase URL is unset, empty or not a URL", async () => {
    for (const url of [null, "", "   ", "localhost:3202", "not a url"]) {
      expect(await notice({ label: "harness", url }), JSON.stringify(url)).toBe("");
    }
  });

  it("look-alike loopback hosts do not count", async () => {
    for (const url of ["https://localhost.example.com", "https://localhost.supabase.co", "http://127.0.0.1.nip.io:3202", "https://user@localhost-db.example.com", "http://localhost@db.example.com"]) {
      expect(await notice({ label: "harness", url }), url).toBe("");
    }
  });

  it("not shown when NEXT_PUBLIC_ENV_LABEL is unset (the 'local' default is not a claim about the data)", async () => {
    expect(await notice({})).toBe("");
    expect(await notice({ label: "" })).toBe("");
    expect(await notice({ label: "   " })).toBe("");
  });

  it("never for preview, sample or other look-alike labels", async () => {
    for (const label of ["local", "preview", "Preview", "sample", "staging-preview", "local-preview", "rehearsal-2", "harness ", "LOCAL", "HARNESS", "local harness", "sandbox", "staging", "production", "ci"]) {
      const html = await notice({ label });
      if (label === "harness ") {
        // Surrounding whitespace is trimmed, exactly as ENV_LABEL is.
        expect(html, JSON.stringify(label)).toContain(NOTICE);
        continue;
      }
      expect(html, JSON.stringify(label)).toBe("");
    }
  });

  it("never on a Vercel production or preview deployment, whatever the label or URL", async () => {
    for (const vercel of ["production", "preview"]) {
      for (const label of ["local", "harness", "rehearsal"]) {
        expect(await notice({ label, vercel }), `${label}@${vercel}`).toBe("");
      }
    }
  });
});

describe("F2 — sampleDataLabel (pure rule)", () => {
  it("exact allowlist, explicit only, loopback URL only, never on Vercel production/preview", async () => {
    const { sampleDataLabel, SAMPLE_DATA_LABELS } = await import("@/lib/env-policy");
    expect(SAMPLE_DATA_LABELS).toEqual(["harness", "rehearsal"]);
    expect(sampleDataLabel({ label: "rehearsal", vercelEnv: undefined, supabaseUrl: HARNESS_URL })).toBe("rehearsal");
    expect(sampleDataLabel({ label: " harness ", vercelEnv: "development", supabaseUrl: "http://127.0.0.1:3202" })).toBe("harness");
    expect(sampleDataLabel({ label: "harness", vercelEnv: undefined, supabaseUrl: "http://[::1]:3202" })).toBe("harness");
    expect(sampleDataLabel({ label: "harness", vercelEnv: undefined, supabaseUrl: "https://synthetic-ref.supabase.co" })).toBeNull();
    expect(sampleDataLabel({ label: "local", vercelEnv: undefined, supabaseUrl: "https://synthetic-ref.supabase.co" })).toBeNull();
    expect(sampleDataLabel({ label: "local", vercelEnv: undefined, supabaseUrl: HARNESS_URL })).toBeNull();
    expect(sampleDataLabel({ label: "harness", vercelEnv: undefined, supabaseUrl: undefined })).toBeNull();
    expect(sampleDataLabel({ label: undefined, vercelEnv: undefined, supabaseUrl: HARNESS_URL })).toBeNull();
    expect(sampleDataLabel({ label: "preview", vercelEnv: undefined, supabaseUrl: HARNESS_URL })).toBeNull();
    expect(sampleDataLabel({ label: "harness", vercelEnv: "preview", supabaseUrl: HARNESS_URL })).toBeNull();
    expect(sampleDataLabel({ label: "harness", vercelEnv: "production", supabaseUrl: HARNESS_URL })).toBeNull();
  });

  it("isLoopbackUrl: exactly localhost, 127.0.0.1 and ::1", async () => {
    const { isLoopbackUrl } = await import("@/lib/env-policy");
    for (const u of ["http://localhost:3202", "https://localhost", "http://127.0.0.1:54321", "http://[::1]:3202", " http://localhost:3202 "]) expect(isLoopbackUrl(u), u).toBe(true);
    for (const u of [undefined, null, "", "localhost", "ftp://localhost", "https://synthetic-ref.supabase.co", "http://127.0.0.2:3202", "http://0.0.0.0:3202", "http://localhost.example.com", "http://foo.localhost"]) expect(isLoopbackUrl(u), String(u)).toBe(false);
  });
});
