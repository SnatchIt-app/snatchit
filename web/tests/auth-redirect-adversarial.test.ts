/**
 * Open-redirect corpus for src/lib/auth/redirect.ts.
 *
 * Complements tests/auth-redirect.test.ts. This guard is load-bearing in two
 * places that take untrusted input:
 *   - login/signup/auth-confirm read `next` straight off the query string;
 *   - NotificationsList renders `safeInternalPath(n.link, …)` as an <a href>,
 *     and notifications.link is DB content (stored-redirect surface).
 *
 * The property test at the bottom is the actual security contract: whatever
 * comes back must resolve to the app's own origin.
 */
import { describe, expect, it } from "vitest";
import { safeInternalPath } from "@/lib/auth/redirect";

const FB = "/account";
const BASE = "https://snatchit.app";

/** Inputs that must never survive the guard. */
const REJECTED = [
  // protocol-relative
  "//evil.com",
  "///evil.com",
  "//evil.com/path?a=b",
  "//attacker@evil.com",
  // absolute
  "https://evil.com",
  "http://evil.com/account",
  "HTTPS://EVIL.COM",
  "https:/evil.com",
  // scheme abuse
  "javascript:alert(1)",
  "JaVaScRiPt:alert(1)",
  "data:text/html,<script>alert(1)</script>",
  "mailto:x@evil.com",
  "vbscript:msgbox(1)",
  // backslash variants browsers may read as protocol-relative
  "/\\evil.com",
  "\\\\evil.com",
  "/\\\\evil.com",
  "/path\\..\\evil",
  // leading / embedded whitespace and line terminators
  "\t//evil.com",
  " /account",
  "\n/account",
  "/account\n",
  "/account\r\nSet-Cookie: session=x",
  "/account\r\nLocation: https://evil.com",
  "/acc ount",
  "/account\u2028//evil.com",
  "/account\u000b",
  "/account\u00a0x",
  // not rooted
  "account",
  "./account",
  "../account",
  "?next=/account",
  "#fragment",
  // auth loop guard
  "/auth/",
  "/auth/confirm",
  "/auth/confirm?next=/account",
  "/auth/anything/deep",
  // unicode slash lookalikes never start a valid path
  "／／evil.com",
  "／account",
];

/** Inputs that are allowed through — each must still be same-origin. */
const ACCEPTED = [
  "/",
  "/account",
  "/account/saved",
  "/browse?category=festivals&sort=ending",
  "/listing/8f2c-1?ref=share#details",
  "/legit?next=//evil.com",
  "/%2F%2Fevil.com",
  "/%09//evil.com",
  "/..//evil.com",
  "/./..//evil.com",
  "/@evil.com",
  "/auth",
  "/authorize",
  "/AUTH/confirm",
  "/" + "a".repeat(511), // exactly MAX_LENGTH
];

describe("safeInternalPath — rejection corpus", () => {
  it("falls back for every hostile input", () => {
    for (const input of REJECTED) {
      expect(safeInternalPath(input, FB), JSON.stringify(input)).toBe(FB);
    }
  });

  it("falls back for empty / nullish input", () => {
    expect(safeInternalPath(null, FB)).toBe(FB);
    expect(safeInternalPath(undefined, FB)).toBe(FB);
    expect(safeInternalPath("", FB)).toBe(FB);
  });

  it("enforces the 512-character limit inclusively", () => {
    expect(safeInternalPath("/" + "a".repeat(511), FB)).toHaveLength(512);
    expect(safeInternalPath("/" + "a".repeat(512), FB)).toBe(FB);
    expect(safeInternalPath("/" + "a".repeat(5_000), FB)).toBe(FB);
  });

  it("does not crash on non-string input cast through the signature", () => {
    expect(safeInternalPath(0 as unknown as string, FB)).toBe(FB);
    expect(safeInternalPath(123 as unknown as string, FB)).toBe(FB);
    expect(safeInternalPath({} as unknown as string, FB)).toBe(FB);
    expect(safeInternalPath([] as unknown as string, FB)).toBe(FB);
  });
});

describe("safeInternalPath — acceptance corpus", () => {
  it("returns real internal destinations unchanged", () => {
    for (const input of ACCEPTED) {
      expect(safeInternalPath(input, FB), JSON.stringify(input.slice(0, 40))).toBe(input);
    }
  });

  it("SECURITY: everything it returns resolves to this origin", () => {
    // The one guarantee that matters. Percent-encoded slashes stay a single
    // path segment, and "/..//evil.com" normalises to "<origin>//evil.com" —
    // the authority is already fixed by the base URL, so neither escapes.
    for (const input of [...ACCEPTED, ...REJECTED]) {
      const out = safeInternalPath(input, FB);
      expect(new URL(out, BASE).origin, JSON.stringify(input.slice(0, 40))).toBe(BASE);
    }
  });

  it("a nested open-redirect payload is defused when the next page re-checks it", () => {
    const carried = safeInternalPath("/legit?next=//evil.com", FB);
    expect(carried).toBe("/legit?next=//evil.com");
    // /legit then reads its own `next` and runs it through the same guard.
    const nested = new URL(carried, BASE).searchParams.get("next");
    expect(nested).toBe("//evil.com");
    expect(safeInternalPath(nested, FB)).toBe(FB);
  });

  it("blocks /auth/ by prefix only — '/auth' itself and other cases pass", () => {
    // Documented so a future case-insensitive route matcher or an /auth page
    // is a deliberate decision rather than a surprise redirect loop.
    expect(safeInternalPath("/auth", FB)).toBe("/auth");
    expect(safeInternalPath("/AUTH/confirm", FB)).toBe("/AUTH/confirm");
    expect(safeInternalPath("/authenticate", FB)).toBe("/authenticate");
    expect(safeInternalPath("/auth/confirm", FB)).toBe(FB);
  });

  it("GAP: non-whitespace control characters are not blocked", () => {
    // The source comment claims embedded control characters are blocked, but
    // the character class is [^\s\\] and \s does not cover NUL, \x01 or DEL.
    // These stay same-origin, so it is not an open redirect; the risk is a
    // Node ERR_INVALID_CHAR (500) if the value reaches a Location header.
    // Expected: reject anything below \x20 plus \x7f.
    expect(safeInternalPath("/account\u0000", FB)).toBe("/account\u0000");
    expect(safeInternalPath("/account\u0001", FB)).toBe("/account\u0001");
    expect(safeInternalPath("/account\u007f", FB)).toBe("/account\u007f");
    // ...whereas the whitespace-class control characters ARE blocked.
    expect(safeInternalPath("/account\u000c", FB)).toBe(FB);
    expect(safeInternalPath("/account\u2029", FB)).toBe(FB);
  });

  it("does not validate the fallback it is handed", () => {
    // Every caller passes a hardcoded constant, but the function itself would
    // happily return an attacker-supplied fallback.
    expect(safeInternalPath("//evil.com", "https://evil.com")).toBe("https://evil.com");
  });
});
