/**
 * Adversarial / edge-case coverage for src/lib/format.ts.
 *
 * Complements tests/format.test.ts (happy paths). Everything here is
 * deterministic: `now` is always passed explicitly, and every date literal
 * carries a Z suffix so no assertion depends on the runner's timezone.
 *
 * Where a case documents CURRENT-but-wrong behaviour it is marked `BUG:` in a
 * comment, with the behaviour a fix should produce. Those assertions pin the
 * defect so a fix flips the test instead of passing silently.
 */
import { describe, expect, it } from "vitest";
import { PLATFORM_INSTRUCTIONS } from "@snatchit/core";
import { STORAGE_BASE_URL } from "@/lib/env";
import {
  categoryLabel,
  coverImageUrl,
  deliveryLabel,
  fmtEndsIn,
  fmtEventDate,
  fmtEventTime,
  listingCardStatus,
  neighborhoodLabel,
  platformLabel,
} from "@/lib/format";

const XSS = "<script>alert(1)</script>";
const TRAVERSAL = "../../etc/passwd";
const UNICODE = "２０２６年 🎫 Ünïcødé";
const LONG = "a".repeat(10_000);

/**
 * Object.prototype keys are the interesting class of "unknown" string: a plain
 * object literal returns a truthy value for every one of them, so a
 * `lookup[key]` truthiness check does not mean "known platform".
 */
const PROTO_KEYS = [
  "__proto__",
  "constructor",
  "toString",
  "valueOf",
  "hasOwnProperty",
  "isPrototypeOf",
  "propertyIsEnumerable",
  "toLocaleString",
];

describe("fmtEventDate — adversarial", () => {
  it("passes hostile-looking strings through untouched (no mangling, no escaping)", () => {
    // React escapes on render; this helper must not silently rewrite content.
    expect(fmtEventDate(XSS)).toBe(XSS);
    expect(fmtEventDate(TRAVERSAL)).toBe(TRAVERSAL);
    expect(fmtEventDate(UNICODE)).toBe(UNICODE);
    expect(fmtEventDate(LONG)).toBe(LONG);
    expect(fmtEventDate("")).toBe("");
  });

  it("passes through fullwidth digits rather than half-parsing them", () => {
    expect(fmtEventDate("２０２６-１０-１７")).toBe("２０２６-１０-１７");
  });

  it("passes through a full datetime — the contract is date-only strings", () => {
    expect(fmtEventDate("2026-10-17T20:00:00Z")).toBe("2026-10-17T20:00:00Z");
  });

  it("passes through partial dates where any component is zero or missing", () => {
    expect(fmtEventDate("2026-00-17")).toBe("2026-00-17");
    expect(fmtEventDate("2026-10-00")).toBe("2026-10-00");
    expect(fmtEventDate("0000-10-17")).toBe("0000-10-17");
    expect(fmtEventDate("2026-10")).toBe("2026-10");
  });

  it("is timezone-independent for real date-only values", () => {
    // Built with the local-midnight constructor, so the weekday cannot drift.
    expect(fmtEventDate("2028-02-29")).toBe("Tue, Feb 29, 2028");
    expect(fmtEventDate("2026-12-31")).toBe("Thu, Dec 31, 2026");
  });

  it("passes an out-of-range month through instead of printing 'undefined'", () => {
    // MONTHS[12] is undefined and used to be interpolated straight into the
    // output as "Tue, undefined 5, 2026".
    expect(fmtEventDate("2026-13-05")).toBe("2026-13-05");
    expect(fmtEventDate("2026-00-05")).toBe("2026-00-05");
  });

  it("does not validate 2-digit years (documented gap)", () => {
    // Day 32 is now out of range and passes through.
    expect(fmtEventDate("2026-10-32")).toBe("2026-10-32");
    // "26" is mapped to 1926 by the Date constructor, so the weekday belongs
    // to 1926 while the printed year is "26".
    expect(fmtEventDate("26-10-17")).toBe("Sun, Oct 17, 26");
    // Feb 29 in a non-leap year rolls to Mar 1 for the weekday only.
    expect(fmtEventDate("2026-02-29")).toBe("Sun, Feb 29, 2026");
  });

  it("throws on null/undefined — callers must pass the NOT NULL column", () => {
    expect(() => fmtEventDate(undefined as unknown as string)).toThrow(TypeError);
    expect(() => fmtEventDate(null as unknown as string)).toThrow(TypeError);
  });
});

describe("fmtEventTime — adversarial", () => {
  it("handles the 12-hour boundaries", () => {
    expect(fmtEventTime("00:00:00")).toBe("12:00 AM");
    expect(fmtEventTime("11:59:59")).toBe("11:59 AM");
    expect(fmtEventTime("12:00:00")).toBe("12:00 PM");
    expect(fmtEventTime("23:59:59")).toBe("11:59 PM");
  });

  it("passes unparseable input through", () => {
    expect(fmtEventTime("abc")).toBe("abc");
    expect(fmtEventTime(XSS)).toBe(XSS);
    expect(fmtEventTime(UNICODE)).toBe(UNICODE);
    expect(fmtEventTime("１２:００")).toBe("１２:００");
    expect(fmtEventTime(LONG)).toBe(LONG);
  });

  it("passes empty / whitespace-only input through instead of showing midnight", () => {
    // Number("") === 0, not NaN, so the NaN guard never fired and a missing
    // time was shown to buyers as a confident 12:00 AM start.
    expect(fmtEventTime("")).toBe("");
    expect(fmtEventTime("   ")).toBe("   ");
  });

  it("range-checks the hour", () => {
    expect(fmtEventTime("25:00:00")).toBe("25:00:00");
    expect(fmtEventTime("-1:00:00")).toBe("-1:00:00");
  });

  it("inherits Number() coercion quirks (hex / exponent hour strings)", () => {
    // Documented, not exploitable: event_time is a `time` column.
    expect(fmtEventTime("0x16:00:00")).toBe("10:00 PM");
    expect(fmtEventTime("1e1:00:00")).toBe("10:00 AM");
  });

  it("echoes the minute field verbatim without zero-padding", () => {
    expect(fmtEventTime("9:5")).toBe("9:5 AM");
    expect(fmtEventTime("22")).toBe("10:00 PM");
  });
});

describe("fmtEndsIn — adversarial", () => {
  const now = new Date("2026-07-27T12:00:00Z");
  const at = (ms: number) => new Date(now.getTime() + ms).toISOString();

  it("treats the exact boundary as ended", () => {
    expect(fmtEndsIn(now.toISOString(), now)).toBe("Ended");
    expect(fmtEndsIn(at(-1), now)).toBe("Ended");
  });

  it("never renders '0m' for a still-live auction", () => {
    for (const ms of [1, 999, 1_000, 30_000, 59_999, 60_000]) {
      // Math.max(minutes, 1) floors sub-minute remainders at "1m".
      const out = fmtEndsIn(at(ms), now);
      expect(out, `${ms}ms`).not.toBe("0m");
      expect(out, `${ms}ms`).toBe("1m");
    }
  });

  it("rolls over at the hour and day boundaries", () => {
    expect(fmtEndsIn(at(59 * 60_000 + 59_999), now)).toBe("59m");
    expect(fmtEndsIn(at(60 * 60_000), now)).toBe("1h 0m");
    expect(fmtEndsIn(at(24 * 60 * 60_000 - 1), now)).toBe("23h 59m");
    expect(fmtEndsIn(at(24 * 60 * 60_000), now)).toBe("1d 0h");
  });

  it("returns Ended for every unparseable value (fails closed)", () => {
    for (const bad of ["", "  ", "not-a-date", XSS, TRAVERSAL, UNICODE, LONG, "9999999-99-99"]) {
      expect(fmtEndsIn(bad, now), JSON.stringify(bad.slice(0, 20))).toBe("Ended");
    }
    expect(fmtEndsIn(undefined as unknown as string, now)).toBe("Ended");
  });

  it("handles far-future timestamps without overflowing the format", () => {
    expect(fmtEndsIn("9999-12-31T23:59:59Z", now)).toMatch(/^\d+d \d+h$/);
    // Beyond the max Date range -> NaN -> Ended, not a crash.
    expect(fmtEndsIn("+275760-09-14T00:00:00Z", now)).toBe("Ended");
  });
});

describe("listingCardStatus — adversarial", () => {
  const now = new Date("2026-07-27T12:00:00Z");
  const at = (ms: number) => new Date(now.getTime() + ms).toISOString();
  const DAY = 24 * 60 * 60_000;
  const base = { status: "active", auction_status: "active", ends_at: at(30 * DAY) };

  it("checks cancelled FIRST — a cancelled row is never offered for bidding", () => {
    // The source comment says this ordering is load-bearing. A cancelled
    // listing keeps status='active', so any later branch would leak a
    // withdrawn listing back into the LIVE state.
    expect(listingCardStatus({ ...base, auction_status: "cancelled" }, now)).toBe("ENDED");
    // ...including rows that are ALSO marked sold, in either column.
    expect(
      listingCardStatus({ status: "sold", auction_status: "cancelled", ends_at: at(30 * DAY) }, now),
    ).toBe("ENDED");
    expect(
      listingCardStatus({ status: "active", auction_status: "cancelled", ends_at: at(-DAY) }, now),
    ).toBe("ENDED");
    // ...and reserved rows.
    expect(
      listingCardStatus(
        { status: "reserved", auction_status: "cancelled", ends_at: at(30 * DAY) },
        now,
      ),
    ).toBe("ENDED");
  });

  it("orders sold above reserved and above the clock", () => {
    expect(listingCardStatus({ ...base, status: "sold", auction_status: "ended" }, now)).toBe("SOLD");
    expect(listingCardStatus({ status: "reserved", auction_status: "sold", ends_at: at(-DAY) }, now)).toBe(
      "SOLD",
    );
    // RESERVED outranks an expired clock (the hold is still live server-side).
    expect(listingCardStatus({ ...base, status: "reserved", ends_at: at(-DAY) }, now)).toBe("RESERVED");
    expect(listingCardStatus({ ...base, status: "reserved", auction_status: "ended" }, now)).toBe(
      "RESERVED",
    );
  });

  it("uses inclusive boundaries at now and at exactly 24h", () => {
    expect(listingCardStatus({ ...base, ends_at: now.toISOString() }, now)).toBe("ENDED");
    expect(listingCardStatus({ ...base, ends_at: at(-1) }, now)).toBe("ENDED");
    expect(listingCardStatus({ ...base, ends_at: at(1) }, now)).toBe("ENDING SOON");
    expect(listingCardStatus({ ...base, ends_at: at(DAY) }, now)).toBe("ENDING SOON");
    expect(listingCardStatus({ ...base, ends_at: at(DAY + 1) }, now)).toBe("LIVE");
  });

  it("fails closed on an unparseable ends_at", () => {
    // NaN fails both comparisons, so the card advertises bidding on a listing
    // whose end time cannot be read — while fmtEndsIn on the SAME value says
    // "Ended". Expected: ENDED (fail closed). Not reachable while ends_at is
    // NOT NULL in the DB, but the two helpers disagree on identical input.
    for (const bad of ["", "garbage", UNICODE]) {
      expect(listingCardStatus({ ...base, ends_at: bad }, now), bad).toBe("ENDED");
      expect(fmtEndsIn(bad, now), bad).toBe("Ended");
    }
    // A null ends_at coerces to epoch 0 and DOES end up ENDED — so the
    // fail-open is specific to unparseable strings.
    expect(listingCardStatus({ ...base, ends_at: null as unknown as string }, now)).toBe("ENDED");
  });

  it("matches status values case-sensitively and exactly", () => {
    // Guarded by DB CHECK constraints; documented so a future enum rename
    // cannot silently downgrade a cancelled listing to LIVE.
    expect(listingCardStatus({ ...base, auction_status: "CANCELLED" }, now)).toBe("LIVE");
    expect(listingCardStatus({ ...base, status: "Sold" }, now)).toBe("LIVE");
    expect(listingCardStatus({ ...base, auction_status: " cancelled " }, now)).toBe("LIVE");
    expect(listingCardStatus({ ...base, status: XSS, auction_status: XSS }, now)).toBe("LIVE");
  });
});

describe("platformLabel — adversarial", () => {
  it("returns a non-empty display name for every key in the shared table", () => {
    for (const key of Object.keys(PLATFORM_INSTRUCTIONS)) {
      const label = platformLabel(key);
      expect(label, key).toBe(PLATFORM_INSTRUCTIONS[key as keyof typeof PLATFORM_INSTRUCTIONS].displayName);
      expect(label.length, key).toBeGreaterThan(0);
    }
  });

  it("falls back to 'Other Platform' for anything not in the table", () => {
    for (const bad of ["", " ", "unknown_platform", "TICKETMASTER", XSS, TRAVERSAL, UNICODE, LONG]) {
      expect(platformLabel(bad), JSON.stringify(bad.slice(0, 20))).toBe("Other Platform");
    }
  });

  it("survives Object.prototype keys (optional chaining saves it)", () => {
    for (const key of PROTO_KEYS) {
      expect(platformLabel(key), key).toBe("Other Platform");
    }
  });

  it("never reflects the input into the label", () => {
    expect(platformLabel(XSS)).not.toContain("script");
  });
});

describe("deliveryLabel — adversarial", () => {
  it("produces a clean sentence for every real platform", () => {
    for (const key of Object.keys(PLATFORM_INSTRUCTIONS)) {
      const label = deliveryLabel(key);
      if (key === "other") {
        expect(label).toBe("Official platform transfer");
        continue;
      }
      expect(label, key).toMatch(/^Official .+ transfer$/);
      expect(label, key).not.toContain("(");
      expect(label, key).not.toContain(")");
      expect(label, key).not.toContain("Other Platform");
    }
  });

  it("uses the generic sentence for unknown, empty and hostile input", () => {
    for (const bad of ["", " ", "OTHER", "Other", "unknown_platform", XSS, TRAVERSAL, UNICODE, LONG]) {
      expect(deliveryLabel(bad), JSON.stringify(bad.slice(0, 20))).toBe("Official platform transfer");
    }
  });

  it("never interpolates raw input — the text feeds public JSON-LD", () => {
    expect(deliveryLabel(XSS)).not.toContain("<");
    expect(deliveryLabel(TRAVERSAL)).not.toContain("..");
  });

  it("falls back for Object.prototype keys instead of throwing", () => {
    // `PLATFORM_INSTRUCTIONS["constructor"]` is the inherited Object
    // constructor — truthy — so the `!known` guard passes and the function
    // then reads `.displayName.replace(...)` on undefined.
    // Expected: "Official platform transfer" (same as any unknown value).
    // Actual: TypeError, which would 500 the listing page render.
    // platformLabel() survives the same input because it uses `?.` + `??`.
    // Not reachable today: listings.ticket_platform has a 16-value CHECK
    // constraint (migration 033). It is a contract violation regardless.
    for (const key of PROTO_KEYS) {
      expect(deliveryLabel(key), key).toBe("Official platform transfer");
    }
    expect(deliveryLabel("__proto__")).toBe("Official platform transfer");
  });
});

describe("categoryLabel / neighborhoodLabel — adversarial", () => {
  it("title-cases unknown values", () => {
    expect(neighborhoodLabel("somewhere new")).toBe("Somewhere New");
    expect(categoryLabel("deep house")).toBe("Deep House");
    expect(categoryLabel("")).toBe("");
  });

  it("does not strip or escape hostile input in the fallback path", () => {
    // Title-casing only — it upper-cases each word's first letter and leaves
    // punctuation (including the angle brackets) intact. Output is
    // React-escaped at render time.
    expect(categoryLabel(XSS)).toBe("<Script>Alert(1)</Script>");
    expect(neighborhoodLabel(TRAVERSAL)).toBe("../../Etc/Passwd");
    expect(categoryLabel(LONG)).toHaveLength(LONG.length);
  });

  it("returns a real string for Object.prototype keys", () => {
    // `CATEGORY_LABELS["__proto__"]` is Object.prototype — not nullish — so
    // `?? capitalize()` never fires and the inherited value is returned while
    // the signature promises `string`. Rendering it as a React child throws
    // "Objects are not valid as a React child".
    // Expected: "__proto__" title-cased (or the generic fallback).
    expect(typeof categoryLabel("__proto__")).toBe("string");
    expect(typeof categoryLabel("toString")).toBe("string");
    expect(typeof neighborhoodLabel("constructor")).toBe("string");
    expect(typeof neighborhoodLabel("hasOwnProperty")).toBe("string");
    // Title-cased fallback, same as any other unrecognised value.
    expect(categoryLabel("toString")).toBe("ToString");
    // Same root cause as the deliveryLabel crash above: unguarded index into a
    // plain object with a caller-supplied string key.
  });
});

describe("coverImageUrl — adversarial", () => {
  const storageOrigin = new URL(STORAGE_BASE_URL).origin;

  it("joins the bucket prefix onto the stored path", () => {
    expect(coverImageUrl("abc/cover.jpg")).toBe(`${STORAGE_BASE_URL}/auction-media/abc/cover.jpg`);
  });

  it("SECURITY: no input can move the URL off the storage origin", () => {
    for (const bad of [
      "",
      TRAVERSAL,
      "../../../../../../etc/passwd",
      "//evil.com/x.jpg",
      "https://evil.com/x.jpg",
      "http://evil.com/x.jpg",
      "\\\\evil.com\\x.jpg",
      "..\\..\\x.jpg",
      XSS,
      UNICODE,
      "a?x=1#frag",
      LONG,
    ]) {
      const url = coverImageUrl(bad);
      expect(new URL(url).origin, JSON.stringify(bad.slice(0, 24))).toBe(storageOrigin);
      expect(url.startsWith(STORAGE_BASE_URL), JSON.stringify(bad.slice(0, 24))).toBe(true);
    }
  });

  it("neutralises traversal segments so the bucket prefix cannot be escaped", () => {
    const url = coverImageUrl(TRAVERSAL);
    // Previously the raw "../../" survived and a URL parser normalised the
    // auction-media prefix away, pointing at another public storage path.
    expect(url).not.toContain("..");
    expect(new URL(url).pathname).toContain("/auction-media/");
  });

  it("does not percent-encode, and does not detect an already-absolute URL", () => {
    expect(coverImageUrl("a b.jpg")).toContain("/auction-media/a b.jpg");
    // A row storing a full URL produces a doubled, broken URL rather than
    // passing it through — callers must store bucket-relative paths.
    expect(coverImageUrl("https://cdn.example.com/x.jpg")).toBe(
      `${STORAGE_BASE_URL}/auction-media/https://cdn.example.com/x.jpg`,
    );
  });

  it("produces the bucket root for an empty path rather than throwing", () => {
    expect(coverImageUrl("")).toBe(`${STORAGE_BASE_URL}/auction-media/`);
  });

  it("returns the bucket root for null/undefined instead of a 'null' path", () => {
    const root = `${STORAGE_BASE_URL}/auction-media/`;
    expect(coverImageUrl(null as unknown as string)).toBe(root);
    expect(coverImageUrl(undefined as unknown as string)).toBe(root);
  });
});
