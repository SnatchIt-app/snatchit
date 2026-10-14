import { describe, expect, it } from "vitest";
import { readConfirmLink } from "@/lib/auth/confirm-link";

const q = (s: string) => new URLSearchParams(s);

describe("readConfirmLink: what an email link brought to /auth/confirm", () => {
  it("PKCE: the web's own reset and sign-up links come back as ?code=", () => {
    expect(readConfirmLink(q("next=%2Freset-password&code=abc"), "")).toEqual({ kind: "pkce", code: "abc" });
  });

  it("implicit: hash tokens, with their type", () => {
    expect(readConfirmLink(q("next=%2Freset-password"), "#access_token=a&refresh_token=r&type=recovery")).toEqual({
      kind: "implicit",
      accessToken: "a",
      refreshToken: "r",
      type: "recovery",
    });
  });

  it("token_hash: needs both token_hash and type", () => {
    expect(readConfirmLink(q("token_hash=h&type=signup"), "")).toEqual({ kind: "token_hash", tokenHash: "h", type: "signup" });
    expect(readConfirmLink(q("token_hash=h"), "")).toEqual({ kind: "none" });
  });

  it("keeps the page's precedence: hash, then token_hash, then code", () => {
    expect(readConfirmLink(q("code=c&token_hash=h&type=signup"), "#access_token=a&refresh_token=r").kind).toBe("implicit");
    expect(readConfirmLink(q("code=c&token_hash=h&type=signup"), "").kind).toBe("token_hash");
  });

  it("an expired-link redirect (error params, no credential) is none, so the page says Link expired", () => {
    expect(readConfirmLink(q("error=access_denied&error_code=otp_expired"), "")).toEqual({ kind: "none" });
    expect(readConfirmLink(q(""), "#error=access_denied&error_code=otp_expired")).toEqual({ kind: "none" });
    expect(readConfirmLink(q("code="), "")).toEqual({ kind: "none" });
  });
});
