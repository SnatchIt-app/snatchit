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
