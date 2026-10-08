import { describe, expect, it } from "vitest";
import { decideProxyRedirect } from "../src/lib/auth/proxy-logic";

const base = { search: "", nextParam: null as string | null };

describe("decideProxyRedirect", () => {
  it("lets anonymous visitors reach /login and framework assets", () => {
    for (const pathname of ["/login", "/_next/static/x.js", "/favicon.ico"]) {
      expect(decideProxyRedirect({ ...base, pathname, isAuthed: false, aal: null })).toEqual({ type: "none" });
    }
  });

  it("sends anonymous visitors on any console route to /login with a safe next", () => {
    expect(decideProxyRedirect({ ...base, pathname: "/cases", search: "?status=open", isAuthed: false, aal: null })).toEqual({
      type: "redirect",
      path: "/login?next=%2Fcases%3Fstatus%3Dopen",
    });
    expect(decideProxyRedirect({ ...base, pathname: "/mfa", isAuthed: false, aal: null })).toEqual({
      type: "redirect",
      path: "/login?next=%2F",
    });
    expect(decideProxyRedirect({ ...base, pathname: "/denied", isAuthed: false, aal: null })).toEqual({
      type: "redirect",
      path: "/login?next=%2Fdenied",
    });
  });

  it("sends aal1 sessions to /mfa carrying the destination", () => {
    expect(decideProxyRedirect({ ...base, pathname: "/orders/abc", isAuthed: true, aal: "aal1" })).toEqual({
      type: "redirect",
      path: "/mfa?next=%2Forders%2Fabc",
    });
    expect(decideProxyRedirect({ ...base, pathname: "/", isAuthed: true, aal: null })).toEqual({
      type: "redirect",
      path: "/mfa?next=%2F",
    });
  });

  it("allows aal1 sessions on /mfa and /denied", () => {
    expect(decideProxyRedirect({ ...base, pathname: "/mfa", isAuthed: true, aal: "aal1" })).toEqual({ type: "none" });
    expect(decideProxyRedirect({ ...base, pathname: "/denied", isAuthed: true, aal: "aal1" })).toEqual({ type: "none" });
  });

  it("allows aal2 sessions everywhere", () => {
    for (const pathname of ["/", "/cases", "/system", "/denied", "/search"]) {
      expect(decideProxyRedirect({ ...base, pathname, isAuthed: true, aal: "aal2" })).toEqual({ type: "none" });
    }
  });

  it("bounces aal2 sessions off /login and /mfa to a safe next", () => {
    expect(decideProxyRedirect({ ...base, pathname: "/login", isAuthed: true, aal: "aal2", nextParam: "/cases" })).toEqual({
      type: "redirect",
      path: "/cases",
    });
    expect(decideProxyRedirect({ ...base, pathname: "/mfa", isAuthed: true, aal: "aal2", nextParam: "https://evil.com" })).toEqual({
      type: "redirect",
      path: "/",
    });
    expect(decideProxyRedirect({ ...base, pathname: "/mfa", isAuthed: true, aal: "aal2", nextParam: null })).toEqual({
      type: "redirect",
      path: "/",
    });
  });

  it("sends aal1 sessions on /login to /mfa (never straight in)", () => {
    expect(decideProxyRedirect({ ...base, pathname: "/login", isAuthed: true, aal: "aal1", nextParam: "/money" })).toEqual({
      type: "redirect",
      path: "/mfa?next=%2Fmoney",
    });
  });

  it("never builds a next that points back at /login or /mfa", () => {
    const r = decideProxyRedirect({ ...base, pathname: "/login", isAuthed: true, aal: "aal1", nextParam: "/login?next=/x" });
    expect(r).toEqual({ type: "redirect", path: "/mfa?next=%2F" });
  });
});
