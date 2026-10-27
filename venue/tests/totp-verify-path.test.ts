import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * `verifyTotpCode` itself, driven through a fake Supabase client.
 *
 * Why this file exists: the pure reader in `totp-factors.ts` was well covered,
 * but nothing asserted that `verifyTotpCode` *consults* it. E demonstrated on
 * `77bf774e` that deleting `ownsFactor` from the verify path left all 14 of
 * those tests passing — so the check the whole security argument rests on could
 * have vanished in a refactor without a single red test. These tests watch which
 * factor the challenge and verify calls actually target.
 */

type FactorRow = { id: string; status: string; factor_type: string; created_at?: string };

const h = vi.hoisted(() => ({
  factors: [] as { id: string; status: string; factor_type: string; created_at?: string }[],
  calls: [] as unknown[][],
  verifyFails: false,
  unenrollFails: false,
  aal: "aal2" as string | null,
}));

/** Exactly how @supabase/auth-js 2.115.0 buckets factors: `totp` is verified-only. */
function sdk(factors: FactorRow[]) {
  const data: Record<string, FactorRow[]> = { all: [], phone: [], totp: [], webauthn: [] };
  for (const f of factors) {
    data.all.push(f);
    if (f.status === "verified") data[f.factor_type].push(f);
  }
  return data;
}

vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    auth: {
      mfa: {
        listFactors: async () => ({ data: sdk(h.factors), error: null }),
        challenge: async ({ factorId }: { factorId: string }) => {
          h.calls.push(["challenge", factorId]);
          return { data: { id: "challenge-1" }, error: null };
        },
        verify: async ({ factorId, challengeId, code }: { factorId: string; challengeId: string; code: string }) => {
          h.calls.push(["verify", factorId, challengeId, code]);
          return h.verifyFails ? { data: null, error: { message: "invalid code" } } : { data: {}, error: null };
        },
        unenroll: async ({ factorId }: { factorId: string }) => {
          h.calls.push(["unenroll", factorId]);
          return h.unenrollFails ? { data: null, error: { message: "could not remove" } } : { data: {}, error: null };
        },
        enroll: async () => ({
          data: { id: "fresh-1", totp: { qr_code: "data:image/svg+xml;base64,AAA", secret: "SECRET", uri: "otpauth://totp/x" } },
          error: null,
        }),
      },
      getClaims: async () => ({ data: { claims: h.aal === null ? {} : { aal: h.aal } } }),
    },
  }),
}));

const { beginTotpEnroll, verifyTotpCode } = await import("@/lib/auth/step-up");

const VERIFIED: FactorRow = { id: "v-1111", status: "verified", factor_type: "totp", created_at: "2026-10-20T09:00:00.000Z" };
const PENDING: FactorRow = { id: "p-9999", status: "unverified", factor_type: "totp", created_at: "2026-10-27T18:00:00.000Z" };
// A factor id belonging to nobody in this session. Hex with letters: a uuid of
// digits alone has a 12-digit tail that reads as a card number to the pre-push
// scanner, and an all-zero one passes a Luhn check.
const FOREIGN = "b8e4a17c-5d92-4f30-ae61-3c7d095fb28e";

const targeted = (verb: string) => h.calls.filter((c) => c[0] === verb).map((c) => c[1]);

beforeEach(() => {
  h.factors = [];
  h.calls = [];
  h.verifyFails = false;
  h.unenrollFails = false;
  h.aal = "aal2";
});

describe("which factor a verify actually targets", () => {
  it("ignores a factor id that is not the caller's own and uses their own factor", async () => {
    h.factors = [VERIFIED];
    const r = await verifyTotpCode("123456", "somebody-elses-factor");
    expect(r.ok).toBe(true);
    expect(targeted("challenge")).toEqual([VERIFIED.id]);
    expect(targeted("verify")).toEqual([VERIFIED.id]);
  });

  it("will not let a hint promote a SECOND enrolment past a verified factor", async () => {
    // E's finding on 77bf774e: with a verified factor AND a stray pending one,
    // hinting the pending id made the verify complete a second enrolment — the
    // very state beginTotpEnroll refuses. Once a factor is verified it is the
    // only factor step-up may use, and both paths now say so.
    h.factors = [VERIFIED, PENDING];
    const r = await verifyTotpCode("123456", PENDING.id);
    expect(r.ok).toBe(true);
    expect(targeted("verify")).toEqual([VERIFIED.id]);
    expect(targeted("verify")).not.toContain(PENDING.id);
  });

  it("ignores a FOREIGN hint during a first enrolment and verifies the caller's own pending factor", async () => {
    // The case where `ownsFactor` is load-bearing. With a verified factor present
    // the hint is already refused by the verified-factor bound, so only this
    // shape — pending only, hint not ours — actually exercises the ownership
    // check. Without it, this test targets the foreign id and fails.
    h.factors = [PENDING];
    const r = await verifyTotpCode("123456", FOREIGN);
    expect(r.ok).toBe(true);
    expect(targeted("challenge")).toEqual([PENDING.id]);
    expect(targeted("verify")).toEqual([PENDING.id]);
  });

  it("verifies the hinted pending factor during a first enrolment, when no verified factor exists", async () => {
    h.factors = [PENDING];
    const r = await verifyTotpCode("123456", PENDING.id);
    expect(r.ok).toBe(true);
    expect(targeted("verify")).toEqual([PENDING.id]);
  });

  it("finds the pending factor during a first enrolment even with no hint at all", async () => {
    h.factors = [PENDING];
    const r = await verifyTotpCode("123456");
    expect(r.ok).toBe(true);
    expect(targeted("verify")).toEqual([PENDING.id]);
  });

  it("picks the newest pending factor when an operator scanned several times", async () => {
    const newer: FactorRow = { ...PENDING, id: "p-newest", created_at: "2026-10-27T18:30:00.000Z" };
    h.factors = [PENDING, newer];
    await verifyTotpCode("123456");
    expect(targeted("verify")).toEqual([newer.id]);
  });
});

describe("what a failure says, and does not say", () => {
  it("treats a wrong code as a wrong code — generic message, and never asks to re-enrol", async () => {
    h.factors = [VERIFIED];
    h.verifyFails = true;
    const r = await verifyTotpCode("000000");
    expect(r.ok).toBe(false);
    if (r.ok) throw new Error("unreachable");
    expect(r.message).toBe("Could not confirm the code. Check your authenticator and try again.");
    expect(r.needsEnroll).toBeUndefined();
  });

  it("asks for enrolment only when there is genuinely no factor, and issues no challenge", async () => {
    h.factors = [];
    const r = await verifyTotpCode("123456");
    expect(r.ok).toBe(false);
    if (r.ok) throw new Error("unreachable");
    expect(r.needsEnroll).toBe(true);
    expect(h.calls).toEqual([]);
  });

  it("rejects a malformed code before touching the network", async () => {
    h.factors = [VERIFIED];
    const r = await verifyTotpCode("12ab");
    expect(r.ok).toBe(false);
    expect(h.calls).toEqual([]);
  });

  it("reports the aal from the verified token, not an assumption", async () => {
    h.factors = [VERIFIED];
    h.aal = null;
    const r = await verifyTotpCode("123456");
    expect(r).toEqual({ ok: true, aal: null });
  });
});

describe("enrolment clears what it can, and never blocks on what it cannot", () => {
  it("removes every pending factor before issuing a new QR", async () => {
    const second: FactorRow = { ...PENDING, id: "p-second", created_at: "2026-10-27T18:10:00.000Z" };
    h.factors = [PENDING, second];
    const r = await beginTotpEnroll();
    expect(r.ok).toBe(true);
    expect(targeted("unenroll")).toEqual([PENDING.id, second.id]);
  });

  it("still enrols when an unenroll fails, because the newest pending factor is the one verified", async () => {
    // Deliberate, not an oversight: a factor we could not remove is left behind,
    // and `pickTotpFactor` prefers the newest, so a stale one can never be the
    // factor a verify targets. Blocking enrolment on a GoTrue hiccup would strand
    // the operator for no safety gain.
    h.factors = [PENDING];
    h.unenrollFails = true;
    const r = await beginTotpEnroll();
    expect(r.ok).toBe(true);
    if (!r.ok) throw new Error("unreachable");
    expect(r.factorId).toBe("fresh-1");
  });

  it("refuses to enrol over a verified factor", async () => {
    h.factors = [VERIFIED];
    const r = await beginTotpEnroll();
    expect(r.ok).toBe(false);
    expect(targeted("unenroll")).toEqual([]);
  });
});
