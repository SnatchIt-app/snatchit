import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { ownsFactor, pendingTotpFactors, pickTotpFactor, stepUpAction } from "@/lib/auth/totp-factors";

/**
 * The sandbox organizer could not enrol an authenticator at all: scanning the QR
 * and entering its code answered "This account has no authenticator yet." and
 * replaced the QR, forever.
 *
 * The cause is in the installed SDK, @supabase/auth-js 2.115.0, whose
 * `_listFactors` is:
 *
 *     for (const factor of user?.factors ?? []) {
 *       data.all.push(factor);
 *       if (factor.status === 'verified') data[factor.factor_type].push(factor);
 *     }
 *
 * `data.totp` therefore holds ONLY verified factors. A factor that has just been
 * enrolled is `unverified`, so it appears in `data.all` and nowhere else — and a
 * reader that looks at `data.totp` cannot see the very factor the operator is
 * holding in their hand. First enrolment is impossible by construction.
 *
 * The fixtures below are that shape, not a convenient one.
 */

const PENDING: { id: string; status: string; factor_type: string; created_at: string } = {
  id: "9f3a1c52-7b64-4de8-9a21-c05e8b7d4f16",
  status: "unverified",
  factor_type: "totp",
  created_at: "2026-10-27T18:00:00.000Z",
};
const VERIFIED = {
  id: "2c7e45b9-1a08-4f6d-8b33-ae9152d7c604",
  status: "verified",
  factor_type: "totp",
  created_at: "2026-10-20T09:00:00.000Z",
};

/** Exactly what the installed SDK builds, from a given set of user.factors. */
function sdkListFactors(factors: { id: string; status: string; factor_type: string; created_at?: string }[]) {
  const data: Record<string, typeof factors> = { all: [], phone: [], totp: [], webauthn: [] };
  for (const f of factors) {
    data.all.push(f);
    if (f.status === "verified") data[f.factor_type].push(f);
  }
  return data;
}

describe("the first enrolment, in the shape the installed SDK actually returns", () => {
  it("sees a just-enrolled factor that the SDK reports only in `all`", () => {
    const data = sdkListFactors([PENDING]);
    // The premise, asserted so this test fails loudly if the SDK ever changes:
    expect(data.totp).toEqual([]);
    expect(data.all).toHaveLength(1);

    expect(pickTotpFactor(data)).toEqual({ kind: "unverified", factorId: PENDING.id });
  });

  it("does not report `none`, because `none` is what made the UI mint a new QR over the one just scanned", () => {
    expect(pickTotpFactor(sdkListFactors([PENDING])).kind).not.toBe("none");
  });

  it("finds every pending factor, so repeated abandoned scans can be cleared", () => {
    const second = { ...PENDING, id: "4b81d0a7-6c29-4e35-9f70-d3ac86e15b2f", created_at: "2026-10-27T18:05:00.000Z" };
    const data = sdkListFactors([PENDING, second]);
    expect(pendingTotpFactors(data).map((f) => f.id)).toEqual([PENDING.id, second.id]);
  });

  it("prefers the newest pending factor — the operator is holding the newest QR", () => {
    const newer = { ...PENDING, id: "4b81d0a7-6c29-4e35-9f70-d3ac86e15b2f", created_at: "2026-10-27T18:05:00.000Z" };
    expect(pickTotpFactor(sdkListFactors([PENDING, newer]))).toEqual({ kind: "unverified", factorId: newer.id });
  });
});

describe("an account that already has an authenticator", () => {
  it("is verified, and step-up is one code away", () => {
    const data = sdkListFactors([VERIFIED]);
    expect(data.totp).toHaveLength(1);
    expect(pickTotpFactor(data)).toEqual({ kind: "verified", factorId: VERIFIED.id });
  });

  it("prefers the verified factor over a stray pending one, so a wrong code never re-enrols", () => {
    expect(pickTotpFactor(sdkListFactors([PENDING, VERIFIED]))).toEqual({ kind: "verified", factorId: VERIFIED.id });
  });

  it("reports no pending factor to clear when only a verified one exists", () => {
    expect(pendingTotpFactors(sdkListFactors([VERIFIED]))).toEqual([]);
  });
});

describe("an account with no factor at all", () => {
  it("is the only case that may ask for enrolment", () => {
    expect(pickTotpFactor(sdkListFactors([]))).toEqual({ kind: "none" });
    expect(pickTotpFactor(null)).toEqual({ kind: "none" });
    expect(pickTotpFactor(undefined)).toEqual({ kind: "none" });
  });
});

describe("a factor id arriving from the browser is a hint, never an authority", () => {
  it("is accepted only when it is one of the caller's own factors", () => {
    const data = sdkListFactors([PENDING]);
    expect(ownsFactor(data, PENDING.id)).toBe(true);
  });

  it("is rejected when it belongs to nobody in this session — including a verified-looking id", () => {
    const data = sdkListFactors([PENDING]);
    expect(ownsFactor(data, VERIFIED.id)).toBe(false);
    expect(ownsFactor(data, "not-a-uuid")).toBe(false);
    expect(ownsFactor(sdkListFactors([]), PENDING.id)).toBe(false);
  });

  it("counts a pending factor as owned, since first enrolment verifies exactly that one", () => {
    expect(ownsFactor(sdkListFactors([PENDING]), PENDING.id)).toBe(true);
  });
});

describe("the wiring that broke it: the form must carry the factor id it enrolled", () => {
  const form = readFileSync(resolve(__dirname, "../src/components/auth/StepUpForm.tsx"), "utf8");
  const stepUp = readFileSync(resolve(__dirname, "../src/lib/auth/step-up.ts"), "utf8");

  it("keeps the enrolled factor id in phase state and passes it to the verify call", () => {
    expect(form).toMatch(/factorId/);
    expect(form).toMatch(/verifyTotpCode\(\s*code\s*,\s*[^)]*factorId/);
  });

  it("never re-enrols on a wrong code — only when the server says there is genuinely no factor", () => {
    // A wrong code must leave the scanned QR alone; re-enrolling is what destroyed it.
    expect(form).toMatch(/needsEnroll/);
    const verifyBlock = form.slice(form.indexOf("const submit"), form.indexOf("if (phase.kind === \"loading\")"));
    expect(verifyBlock).toMatch(/r\.needsEnroll/);
  });

  it("reads the caller's factors through the shared pure reader, not `data.totp` inline", () => {
    expect(stepUp).toMatch(/from "@\/lib\/auth\/totp-factors"/);
    // No listFactors result may be read through its `.totp` bucket — that bucket
    // is "verified only". `enrolled.totp` is a different shape (the new factor's
    // own QR payload) and is named apart precisely so this check can be exact.
    expect(stepUp).not.toMatch(/\blist\?\.totp|\bdata\?\.totp/);
    expect(stepUp).toMatch(/pickTotpFactor\(list\)/);
    expect(stepUp).toMatch(/pendingTotpFactors\(list\)/);
  });
});

describe("a refreshed page, and the dead end it produced", () => {
  const form = readFileSync(resolve(__dirname, "../src/components/auth/StepUpForm.tsx"), "utf8");

  it("never asks for a code against an UNFINISHED enrolment — its secret was shown once and is gone", () => {
    // The 2026-10-27 dead end: reading `all` made a leftover pending factor
    // visible, so the screen offered a code box with no QR, and the only thing
    // that clears a stale pending factor (beginTotpEnroll) was never reached.
    expect(stepUpAction({ kind: "unverified", factorId: PENDING.id })).toBe("enrol");
  });

  it("asks for a code only when a factor is actually verified", () => {
    expect(stepUpAction({ kind: "verified", factorId: VERIFIED.id })).toBe("ask_code");
  });

  it("enrols when there is no factor at all", () => {
    expect(stepUpAction({ kind: "none" })).toBe("enrol");
  });

  it("routes the screen through that decision rather than testing `kind` inline", () => {
    expect(form).toMatch(/stepUpAction\(/);
    // The old shape — treating unverified the same as verified — must not return.
    expect(form).not.toMatch(/kind === "verified" \|\| s\.kind === "unverified"/);
  });

  it("gives the operator a way to get a fresh code without reloading", () => {
    expect(form).toMatch(/Show a new code/);
  });

  it("says, in words, that an unfinished setup was cleared and older entries are dead", () => {
    expect(form).toMatch(/replacedUnfinished/);
    expect(form).toMatch(/unfinished authenticator setup/);
  });

  it("says, in words, when the account already has a confirmed authenticator", () => {
    expect(form).toMatch(/already has a confirmed authenticator/);
  });
});
