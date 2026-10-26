import { afterEach, describe, expect, it, vi } from "vitest";

// Owner decision 2026-10-22 (§F): fixtures/sample adapters are removed from production mode. The
// venue app's data source defaults to "fixtures" when NEXT_PUBLIC_VENUE_DATA_SOURCE is unset, and
// silently coerces any unknown value to "fixtures". On a Vercel PRODUCTION deployment that default
// is the wrong way round: a forgotten variable would serve invented venues and events from the real
// host. So on NEXT_PUBLIC_VERCEL_ENV=production the source must be stated explicitly, and anything
// but an explicit "database" or an explicit "fixtures" fails the build. Explicit "fixtures" stays
// allowed because the owner-only demo project (decision V-09) sets it on purpose and labels every
// page "Demo — sample data". Preview, development and local keep the fixtures default.

async function load(vercelEnv: string | undefined, source: string | undefined) {
  vi.resetModules();
  if (vercelEnv === undefined) vi.stubEnv("NEXT_PUBLIC_VERCEL_ENV", "");
  else vi.stubEnv("NEXT_PUBLIC_VERCEL_ENV", vercelEnv);
  if (source === undefined) vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", "");
  else vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", source);
  return import("@/lib/env");
}

afterEach(() => vi.unstubAllEnvs());

describe("production deployments never default to sample data", () => {
  it("production + unset source → the build refuses (fails closed)", async () => {
    await expect(load("production", undefined)).rejects.toThrow(/Refusing to build/);
  });

  it("production + an unknown value → refuses, instead of silently coercing to fixtures", async () => {
    await expect(load("production", "fixture")).rejects.toThrow(/Refusing to build/);
    await expect(load("production", "sample")).rejects.toThrow(/Refusing to build/);
  });

  it("production + explicit database → database mode", async () => {
    const m = await load("production", "database");
    expect(m.DATA_SOURCE).toBe("database");
  });

  it("production + explicit fixtures (the owner-only demo, V-09) → fixtures, by explicit choice", async () => {
    const m = await load("production", "fixtures");
    expect(m.DATA_SOURCE).toBe("fixtures");
    expect((await load("production", " Fixtures ")).DATA_SOURCE).toBe("fixtures");
  });

  it("preview, development and local keep the fixtures default", async () => {
    expect((await load("preview", undefined)).DATA_SOURCE).toBe("fixtures");
    expect((await load("development", undefined)).DATA_SOURCE).toBe("fixtures");
    expect((await load(undefined, undefined)).DATA_SOURCE).toBe("fixtures");
  });

  it("the rule as a pure function", async () => {
    const { productionDataSourceProblem } = await load(undefined, undefined);
    expect(productionDataSourceProblem("production", "")).toMatch(/NEXT_PUBLIC_VENUE_DATA_SOURCE/);
    expect(productionDataSourceProblem("production", "nonsense")).toMatch(/nonsense/);
    expect(productionDataSourceProblem("production", "database")).toBeNull();
    expect(productionDataSourceProblem("production", "fixtures")).toBeNull();
    expect(productionDataSourceProblem("preview", "")).toBeNull();
    expect(productionDataSourceProblem(undefined, "")).toBeNull();
    // Only the exact, trimmed word "production" is a production deployment.
    expect(productionDataSourceProblem("Production", "")).toBeNull();
    expect(productionDataSourceProblem(" production ", "")).toMatch(/NEXT_PUBLIC_VENUE_DATA_SOURCE/);
  });
});
