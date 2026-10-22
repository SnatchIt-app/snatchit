import { describe, expect, it } from "vitest";
import { safeInternalPath } from "../src/lib/auth/redirect";

const TAB = String.fromCharCode(9);
const NUL = String.fromCharCode(0);
const LF = String.fromCharCode(10);
const DEL = String.fromCharCode(127);

describe("safeInternalPath", () => {
  it("accepts plain internal paths with query strings", () => {
    expect(safeInternalPath("/cases?status=open&priority=p1", "/")).toBe("/cases?status=open&priority=p1");
    expect(safeInternalPath("/", "/x")).toBe("/");
  });

  it("rejects absolute, protocol-relative, backslash and control-char payloads", () => {
    for (const bad of [
      "https://evil.com",
      "//evil.com",
      "/\\evil.com",
      "javascript:alert(1)",
      "/cases " + TAB,
      "/cases" + LF,
      "/cases" + NUL,
      "/cases" + DEL,
      " /cases",
      "",
      null,
      undefined,
      "/" + "a".repeat(600),
    ]) {
      expect(safeInternalPath(bad, "/fallback")).toBe("/fallback");
    }
  });

  it("refuses to bounce back into the auth screens", () => {
    expect(safeInternalPath("/login", "/")).toBe("/");
    expect(safeInternalPath("/login?next=/x", "/")).toBe("/");
    expect(safeInternalPath("/mfa", "/")).toBe("/");
    expect(safeInternalPath("/mfa?next=/x", "/")).toBe("/");
    expect(safeInternalPath("/loginaudit", "/")).toBe("/loginaudit");
  });
});

/**
 * E-L4 — dot segments and empty segments. "/.//evil.com" passes the
 * single-leading-slash check, yet after dot-segment removal its path is
 * "//evil.com"; a consumer that normalises before resolving reads it as
 * protocol-relative. Any "." or ".." segment, and any empty segment that is
 * not a trailing slash, is refused (fallback, never rewritten). WHATWG URL
 * treats "%2e" as "." in a segment, so the encoded forms are refused too. The
 * query string and fragment are not path segments and are left alone.
 */
describe("safeInternalPath — dot and empty segments (E-L4)", () => {
  it("refuses /./, /../ and // segments anywhere in the path, including %2e-encoded dots and a trailing /. or /..", () => {
    for (const bad of [
      "/.//evil.com",
      "/./evil.com",
      "/./",
      "/.",
      "/..",
      "/../x",
      "/a/./b",
      "/a/../b",
      "/a//b",
      "/a//",
      "/a///b",
      "/orders/..",
      "/orders/.",
      "/orders/./",
      "/%2e%2e/x",
      "/%2E/x",
      "/%2e//evil.com",
      "/a/.%2e/b",
      "/a/%2E./b",
      "/a/%2e%2E",
      "/.//evil.com?next=/",
      "/a/../b#frag",
    ]) {
      expect(safeInternalPath(bad, "/fallback"), bad).toBe("/fallback");
    }
  });

  it("still accepts dots inside names, hidden files, a trailing slash, and dot or double-slash sequences in the query or fragment", () => {
    for (const ok of ["/a.b", "/x/..y", "/x/y..", "/x/.hidden", "/orders/", "/orders/x.json", "/cases?q=a//b", "/a?x=/./y", "/a?next=%2F..%2Fb", "/a#/../b", "/orders/9a900000-0000-4000-8000-0000000000f1"]) {
      expect(safeInternalPath(ok, "/fallback"), ok).toBe(ok);
    }
  });
});
