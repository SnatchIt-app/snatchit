import { describe, expect, it } from "vitest";
import { doorsNotAfterStart, endsAfterStarts, formatInZone, parseWallClock, toOffsetInstant, zoneOffsetAt } from "@/lib/events/instants";

const NY = "America/New_York";

describe("the venue's offset at an instant", () => {
  it("follows DST without a table of ours", () => {
    expect(zoneOffsetAt(new Date("2026-11-30T19:00:00Z"), NY)).toBe("-05:00"); // EST
    expect(zoneOffsetAt(new Date("2026-07-04T19:00:00Z"), NY)).toBe("-04:00"); // EDT
    expect(zoneOffsetAt(new Date("2026-11-30T19:00:00Z"), "UTC")).toBe("+00:00");
    expect(zoneOffsetAt(new Date("2026-11-30T19:00:00Z"), "Asia/Kolkata")).toBe("+05:30");
    expect(zoneOffsetAt(new Date("2026-11-30T19:00:00Z"), "Europe/Madrid")).toBe("+01:00");
  });
  it("an unknown zone or a bad instant is null, never a guess", () => {
    expect(zoneOffsetAt(new Date("2026-11-30T19:00:00Z"), "Mars/Olympus")).toBeNull();
    expect(zoneOffsetAt(new Date("nope"), NY)).toBeNull();
    expect(zoneOffsetAt(new Date("2026-11-30T19:00:00Z"), "")).toBeNull();
  });
});

describe("parseWallClock — what the datetime-local input gives", () => {
  it("takes YYYY-MM-DDTHH:MM with or without seconds", () => {
    expect(parseWallClock("2026-11-30T19:00")).toEqual({ date: "2026-11-30", time: "19:00" });
    expect(parseWallClock(" 2026-11-30T19:00:00 ")).toEqual({ date: "2026-11-30", time: "19:00" });
  });
  it("refuses anything else, including a date that does not exist", () => {
    for (const bad of ["", "2026-11-30", "19:00", "2026-11-30 19:00", "2026-02-31T19:00", "2026-13-01T19:00", "2026-11-30T25:00", "2026-11-30T19:60", "x"]) {
      expect(parseWallClock(bad), bad).toBeNull();
    }
  });
});

describe("toOffsetInstant — the literal the database stores unambiguously", () => {
  it("a Miami pop-up at 7pm on 30 November is -05:00, and the same instant round-trips", () => {
    const r = toOffsetInstant("2026-11-30T19:00", NY);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.iso).toBe("2026-11-30T19:00:00-05:00");
    expect(r.offset).toBe("-05:00");
    expect(r.utc).toBe("2026-12-01T00:00:00.000Z");
    expect(formatInZone(new Date(r.utc), NY)).toBe("2026-11-30T19:00");
  });
  it("summer in the same zone is -04:00, so the offset is not a constant", () => {
    const r = toOffsetInstant("2026-07-04T21:00", NY);
    expect(r.ok && r.iso).toBe("2026-07-04T21:00:00-04:00");
    expect(r.ok && r.utc).toBe("2026-07-05T01:00:00.000Z");
  });
  it("a half-hour zone and UTC are handled", () => {
    expect(toOffsetInstant("2026-11-30T19:00", "Asia/Kolkata")).toMatchObject({ ok: true, iso: "2026-11-30T19:00:00+05:30" });
    expect(toOffsetInstant("2026-11-30T19:00", "UTC")).toMatchObject({ ok: true, iso: "2026-11-30T19:00:00+00:00", utc: "2026-11-30T19:00:00.000Z" });
  });
  it("a local time that does not exist (spring forward) is refused, not shifted", () => {
    // US clocks jump 02:00 → 03:00 on 2026-03-08; 02:30 never happens.
    const r = toOffsetInstant("2026-03-08T02:30", NY);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.reason).toBe("nonexistent");
  });
  it("a local time that happens twice (fall back) is refused, not silently assigned an hour", () => {
    // US clocks fall 02:00 → 01:00 on 2026-11-01; 01:30 happens twice.
    const r = toOffsetInstant("2026-11-01T01:30", NY);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.reason).toBe("ambiguous");
  });
  it("bad input and an unknown zone are reported as themselves", () => {
    expect(toOffsetInstant("not a time", NY)).toMatchObject({ ok: false, reason: "bad_input" });
    expect(toOffsetInstant("2026-11-30T19:00", "Mars/Olympus")).toMatchObject({ ok: false, reason: "unknown_zone", detail: "Mars/Olympus" });
  });
  it("every produced literal is one PostgreSQL reads back as the same instant (offset-qualified, seconds present)", () => {
    for (const [local, zone] of [["2026-11-30T19:00", NY], ["2026-07-04T21:00", NY], ["2026-01-01T00:00", "Europe/Madrid"], ["2026-06-15T12:34", "Asia/Kolkata"]] as const) {
      const r = toOffsetInstant(local, zone);
      expect(r.ok, `${local} ${zone}`).toBe(true);
      if (!r.ok) continue;
      expect(r.iso).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$/);
      expect(new Date(r.iso).toISOString()).toBe(new Date(r.utc).toISOString());
      expect(formatInZone(new Date(r.iso), zone)).toBe(local);
    }
  });
});

describe("the orderings the server also enforces", () => {
  it("ends after starts, compared as instants across zones", () => {
    expect(endsAfterStarts("2026-11-30T19:00:00-05:00", "2026-11-30T23:00:00-05:00")).toBe(true);
    expect(endsAfterStarts("2026-11-30T19:00:00-05:00", "2026-11-30T19:00:00-05:00")).toBe(false);
    // 20:00 in Madrid is BEFORE 19:00 in New York as instants, and string order would say otherwise.
    expect(endsAfterStarts("2026-11-30T19:00:00-05:00", "2026-11-30T20:00:00+01:00")).toBe(false);
    expect(endsAfterStarts("x", "2026-11-30T20:00:00Z")).toBe(false);
  });
  it("doors at or before the start", () => {
    expect(doorsNotAfterStart("2026-11-30T19:00:00-05:00", "2026-11-30T18:00:00-05:00")).toBe(true);
    expect(doorsNotAfterStart("2026-11-30T19:00:00-05:00", "2026-11-30T19:00:00-05:00")).toBe(true);
    expect(doorsNotAfterStart("2026-11-30T19:00:00-05:00", "2026-11-30T20:00:00-05:00")).toBe(false);
  });
});
