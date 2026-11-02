import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

/**
 * Times a person TYPES are Eastern Time (owner decision, 2026-11-02). The console sends each one as an
 * instant with the offset that applies on that date, so the stored instant never depends on the database
 * session's TimeZone (production is UTC today, A; the old "Due (UTC)" field relied on that). A time that
 * does not exist, or happens twice, is refused instead of guessed.
 *
 * Modules load fresh under each runtime zone (see eastern-time.test.ts: a formatter keeps the zone it was
 * built in, and this machine runs America/New_York).
 */
const mocks = vi.hoisted(() => ({ callOps: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next/navigation", () => ({ notFound: () => { throw new Error("notFound"); }, redirect: () => { throw new Error("redirect"); }, usePathname: () => "/orders", useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }), useParams: () => ({}), useSearchParams: () => new URLSearchParams() }));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: vi.fn(async () => ({ id: "0fa1b2c3-d4e5-4f6a-8b7c-9d0e1f2a3b4c", email: null, aal: "aal2", role: "platform_admin", whoami: { role: "platform_admin" } })) }));

const ORIGINAL_TZ = process.env.TZ;
afterAll(() => {
  if (ORIGINAL_TZ === undefined) delete process.env.TZ;
  else process.env.TZ = ORIGINAL_TZ;
});

async function load(tz: string) {
  process.env.TZ = tz;
  vi.resetModules();
  const [format, params] = await Promise.all([import("@/lib/format"), import("@/lib/form-params")]);
  return { ...format, ...params };
}

for (const tz of ["UTC", "America/Los_Angeles"]) {
  describe(`runtime zone ${tz}`, () => {
    let m: Awaited<ReturnType<typeof load>>;
    beforeAll(async () => {
      m = await load(tz);
    });

    it("an Eastern wall clock becomes the instant with that date's offset (never a fixed −05:00)", () => {
      const ok = (wall: string) => {
        const r = m.etWallClockToInstant(wall);
        return r.ok ? r.iso : `refused:${r.reason}`;
      };
      expect(ok("2026-11-01T00:30")).toBe("2026-11-01T00:30:00-04:00"); // EDT, before the clocks go back
      expect(ok("2026-11-01T02:30")).toBe("2026-11-01T02:30:00-05:00"); // EST, after
      expect(ok("2026-11-01T23:59")).toBe("2026-11-01T23:59:00-05:00");
      expect(ok("2026-03-08T01:59")).toBe("2026-03-08T01:59:00-05:00"); // EST, before the jump
      expect(ok("2026-03-08T03:00")).toBe("2026-03-08T03:00:00-04:00"); // EDT, after
      expect(ok("2026-10-28T03:47:30")).toBe("2026-10-28T03:47:30-04:00");
      // the instants are right, not just the text
      const r = m.etWallClockToInstant("2026-11-01T23:59");
      expect(r.ok && r.date.toISOString()).toBe("2026-11-02T04:59:00.000Z");
    });

    it("a time in the spring gap or the repeated fall hour is refused with a plain reason", () => {
      const gap = m.etWallClockToInstant("2026-03-08T02:30");
      expect(gap).toMatchObject({ ok: false, reason: "skipped" });
      expect(!gap.ok && gap.message).toContain("does not exist in Eastern Time");
      const twice = m.etWallClockToInstant("2026-11-01T01:30");
      expect(twice).toMatchObject({ ok: false, reason: "repeated" });
      expect(!twice.ok && twice.message).toContain("happens twice in Eastern Time");
      for (const bad of ["tomorrow", "2026-02-30T10:00", "2026-11-01", "2026-11-01T24:00"]) {
        expect(m.etWallClockToInstant(bad).ok, bad).toBe(false);
      }
    });

    it("param.<key>:et coerces through the same rule; a stated zone is kept; empty clears", () => {
      expect(m.parseParamField("param.due_at:et")).toEqual({ key: "due_at", type: "et" });
      expect(m.coerceParam("et", "2026-11-01T23:59")).toEqual({ ok: true, value: "2026-11-01T23:59:00-05:00" });
      expect(m.coerceParam("et", "2026-11-01T23:59:00Z")).toEqual({ ok: true, value: "2026-11-01T23:59:00Z" });
      expect(m.coerceParam("et", "")).toEqual({ ok: true, value: null });
      expect(m.coerceParam("et", "2026-11-01T01:30").ok).toBe(false);
      expect(m.coerceParam("et", "next friday").ok).toBe(false);
    });

    it("an Eastern calendar day runs from its midnight to the next one: 25 h on Nov 1, 23 h on Mar 8", () => {
      expect(m.etDayStart("2026-11-01")?.toISOString()).toBe("2026-11-01T04:00:00.000Z");
      expect(m.etDayEnd("2026-11-01")?.toISOString()).toBe("2026-11-02T04:59:59.999Z");
      expect(m.etDayStart("2026-11-02")?.toISOString()).toBe("2026-11-02T05:00:00.000Z");
      expect(m.etDayStart("2026-03-08")?.toISOString()).toBe("2026-03-08T05:00:00.000Z");
      expect(m.etDayEnd("2026-03-08")?.toISOString()).toBe("2026-03-09T03:59:59.999Z");
      const hours = (d: string) => (m.etDayEnd(d)!.getTime() + 1 - m.etDayStart(d)!.getTime()) / 3_600_000;
      expect(hours("2026-11-01")).toBe(25);
      expect(hours("2026-03-08")).toBe(23);
      expect(hours("2026-11-02")).toBe(24);
      expect(m.etDayStart("nope")).toBeNull();
    });

    it("a stored instant pre-fills the input as its Eastern wall clock", () => {
      expect(m.toDatetimeLocalEt("2026-11-02T04:59:59Z")).toBe("2026-11-01T23:59");
      expect(m.toDatetimeLocalEt("2026-11-01T04:00:00+00:00")).toBe("2026-11-01T00:00");
      expect(m.toDatetimeLocalEt(null)).toBe("");
    });
  });
}

describe("/orders date filter sends Eastern day limits", () => {
  it("From 2026-11-01 To 2026-11-01 covers the whole 25 h Eastern day", async () => {
    process.env.TZ = "America/Los_Angeles";
    vi.resetModules();
    mocks.callOps.mockReset().mockResolvedValue({ ok: true, data: { items: [], next_cursor: null } });
    const { default: OrdersPage } = await import("@/app/(console)/orders/page");
    await OrdersPage({ searchParams: Promise.resolve({ from: "2026-11-01", to: "2026-11-01" }) });
    const call = mocks.callOps.mock.calls.find(([fn]) => fn === "list_orders");
    expect(call).toBeDefined();
    const args = JSON.stringify(call?.[1]);
    expect(args).toContain('"from":"2026-11-01T04:00:00.000Z"');
    expect(args).toContain('"to":"2026-11-02T04:59:59.999Z"');
    expect(args).not.toContain("T00:00:00Z");
  }, 30_000); // a fresh import of the whole /orders page graph (after resetModules) is slow under load
});

describe("every date-time input in the console is Eastern", () => {
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (/\.tsx$/.test(name)) files.push(p);
    }
  };
  walk(resolve(__dirname, "../src"));

  it("each <input type=\"datetime-local\"> posts a param.<key>:et field", () => {
    const found: string[] = [];
    for (const f of files) {
      const s = readFileSync(f, "utf8");
      for (const mt of s.matchAll(/<input[^>]*type="datetime-local"[^>]*>/g)) {
        found.push(f);
        expect(mt[0], f).toMatch(/name="param\.[a-z_]+:et"/);
      }
    }
    expect(found.length).toBeGreaterThanOrEqual(3); // case due (two forms) + relist end
  });

  it("the console-owned time inputs no longer ask for UTC", () => {
    // /money's From/To stay "(UTC)": they are ops.money_overview's report days, which count UTC days until
    // registry 200 moves the server to Eastern days. Relabelling them now would misstate the data.
    for (const rel of ["components/cases/CaseWork.tsx", "components/cases/NewCaseForm.tsx", "app/(console)/marketplace/[id]/page.tsx", "app/(console)/orders/page.tsx"]) {
      const s = readFileSync(resolve(__dirname, "../src", rel), "utf8");
      expect(s, rel).not.toMatch(/Due \(UTC\)|New end \(UTC\)|From \(UTC\)|To \(UTC\)|\(UTC\)`/);
      expect(s, rel).toMatch(/Eastern Time|\(ET\)/);
    }
    expect(readFileSync(resolve(__dirname, "../src/app/(console)/money/page.tsx"), "utf8")).toContain('label="From (UTC)"');
  });
});
