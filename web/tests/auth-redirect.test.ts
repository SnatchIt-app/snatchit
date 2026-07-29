import { describe, expect, it } from "vitest";
import { safeInternalPath } from "../src/lib/auth/redirect";

describe("safeInternalPath", () => {
  it("accepts a plain internal path", () => {
    expect(safeInternalPath("/account/saved", "/account")).toBe("/account/saved");
  });

  it("accepts a path with a query string", () => {
    expect(safeInternalPath("/browse?category=festivals", "/account")).toBe(
      "/browse?category=festivals",
    );
  });

  it("falls back for missing input", () => {
    expect(safeInternalPath(null, "/account")).toBe("/account");
    expect(safeInternalPath(undefined, "/account")).toBe("/account");
    expect(safeInternalPath("", "/account")).toBe("/account");
  });

  it("rejects protocol-relative URLs (open redirect)", () => {
    expect(safeInternalPath("//evil.com", "/account")).toBe("/account");
    expect(safeInternalPath("///evil.com", "/account")).toBe("/account");
  });

  it("rejects absolute URLs to other origins", () => {
    expect(safeInternalPath("https://evil.com", "/account")).toBe("/account");
    expect(safeInternalPath("http://evil.com/account", "/account")).toBe("/account");
  });

  it("rejects backslash tricks browsers may treat as protocol-relative", () => {
    expect(safeInternalPath("/\\evil.com", "/account")).toBe("/account");
  });

  it("rejects paths not starting with a single slash", () => {
    expect(safeInternalPath("account", "/account")).toBe("/account");
    expect(safeInternalPath("javascript:alert(1)", "/account")).toBe("/account");
  });

  it("rejects auth-route redirect targets to prevent loops", () => {
    expect(safeInternalPath("/auth/confirm", "/account")).toBe("/account");
  });

  it("rejects overly long input", () => {
    const long = "/" + "a".repeat(600);
    expect(safeInternalPath(long, "/account")).toBe("/account");
  });

  it("rejects embedded whitespace/control characters", () => {
    expect(safeInternalPath("/account\n.evil.com", "/account")).toBe("/account");
  });
});
