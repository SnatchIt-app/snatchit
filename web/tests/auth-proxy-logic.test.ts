import { describe, expect, it } from "vitest";
import { decideProxyRedirect } from "../src/lib/auth/proxy-logic";

describe("decideProxyRedirect", () => {
  it("leaves public pages untouched for anonymous visitors", () => {
    for (const pathname of ["/", "/browse", "/listing/abc-123"]) {
      expect(
        decideProxyRedirect({ pathname, search: "", isAuthed: false, nextParam: null }),
      ).toEqual({ type: "none" });
    }
  });

  it("leaves public pages untouched for authenticated visitors", () => {
    expect(
      decideProxyRedirect({ pathname: "/browse", search: "", isAuthed: true, nextParam: null }),
    ).toEqual({ type: "none" });
  });

  it("redirects anonymous visitors away from /account with a safe return path", () => {
    const result = decideProxyRedirect({
      pathname: "/account/saved",
      search: "",
      isAuthed: false,
      nextParam: null,
    });
    expect(result).toEqual({ type: "redirect", path: "/login?next=%2Faccount%2Fsaved" });
  });

  it("preserves the query string in the return path", () => {
    const result = decideProxyRedirect({
      pathname: "/account",
      search: "?tab=saved",
      isAuthed: false,
      nextParam: null,
    });
    expect(result).toEqual({ type: "redirect", path: "/login?next=%2Faccount%3Ftab%3Dsaved" });
  });

  it("does not let an open-redirect payload survive into the login next param", () => {
    // pathname itself is always internal (Next.js guarantees this), but this
    // asserts the return path is still built through safeInternalPath.
    const result = decideProxyRedirect({
      pathname: "/account",
      search: "",
      isAuthed: false,
      nextParam: null,
    });
    expect(result.type).toBe("redirect");
    if (result.type === "redirect") {
      expect(result.path.startsWith("/login?next=%2Faccount")).toBe(true);
    }
  });

  it("sends already-authenticated visitors away from /login to /account by default", () => {
    expect(
      decideProxyRedirect({ pathname: "/login", search: "", isAuthed: true, nextParam: null }),
    ).toEqual({ type: "redirect", path: "/account" });
  });

  it("sends already-authenticated visitors to a safe next param instead", () => {
    expect(
      decideProxyRedirect({
        pathname: "/signup",
        search: "",
        isAuthed: true,
        nextParam: "/listing/abc-123",
      }),
    ).toEqual({ type: "redirect", path: "/listing/abc-123" });
  });

  it("rejects an unsafe next param when redirecting an authenticated visitor away from /login", () => {
    expect(
      decideProxyRedirect({
        pathname: "/login",
        search: "",
        isAuthed: true,
        nextParam: "https://evil.com",
      }),
    ).toEqual({ type: "redirect", path: "/account" });
  });

  it("does not gate /login or /signup for anonymous visitors", () => {
    for (const pathname of ["/login", "/signup"]) {
      expect(
        decideProxyRedirect({ pathname, search: "", isAuthed: false, nextParam: null }),
      ).toEqual({ type: "none" });
    }
  });
});
