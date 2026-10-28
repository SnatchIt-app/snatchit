import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { pendingTotpFactors, verifiedTotpFactor } from "@/lib/auth/totp-factors";

/**
 * The console's cleanup of abandoned TOTP factors never removed anything.
 *
 * The cause is in the installed SDK, @supabase/auth-js 2.115.0, whose
 * `_listFactors` (dist/main/GoTrueClient.js:4997) is:
 *
 *     for (const factor of user?.factors ?? []) {
 *       data.all.push(factor);
 *       if (factor.status === 'verified') data[factor.factor_type].push(factor);
 *     }
 *
 * `data.totp` therefore holds ONLY verified factors — its own type says as much:
 * `Factor<'totp', 'verified'>[]`. A factor left behind by an abandoned enrolment
 * is `unverified`, so it appears in `data.all` and nowhere else. Filtering
 * `data.totp` for `status !== 'verified'` can only ever yield the empty set, so
 * the unenroll loop was unreachable and abandoned factors accumulated forever —
 * until GoTrue's per-user factor cap made `enroll()` fail and the operator was
 * shown the opaque "Could not start MFA." An organizer on the sandbox reached
 * four. Read `all` and filter by `factor_type`.
 *
 * The fixtures below are built the way the SDK builds them, not a convenient way.
 */

const PENDING: FactorInput = {
  id: "7e42b9a1-3c05-4f6d-8b17-ae905d3f2c64",
  status: "unverified",
  factor_type: "totp",
};
const VERIFIED: FactorInput = {
  id: "1d8c06f3-5b72-4e49-9a30-c4e7158b9d02",
  status: "verified",
  factor_type: "totp",
};

type FactorInput = { id: string; status: string; factor_type: string };

/** Exactly what the installed SDK builds, from a given set of `user.factors`. */
function sdkListFactors(factors: FactorInput[]) {
  const data: { all: FactorInput[]; totp: FactorInput[]; phone: FactorInput[]; webauthn: FactorInput[] } = {
    all: [],
    totp: [],
    phone: [],
    webauthn: [],
  };
  for (const f of factors) {
    data.all.push(f);
    if (f.status === "verified") data[f.factor_type as "totp" | "phone" | "webauthn"].push(f);
  }
  return data;
}

describe("abandoned TOTP factors, in the shape the installed SDK actually returns", () => {
  it("the SDK premise this all rests on: a pending factor is in `all` and absent from `totp`", () => {
    const data = sdkListFactors([PENDING]);
    // Asserted so this test fails loudly if a future SDK changes the shape.
    expect(data.totp).toEqual([]);
    expect(data.all).toEqual([PENDING]);
  });

  it("offers a pending factor for removal, which reading `totp` could never do", () => {
    expect(pendingTotpFactors(sdkListFactors([PENDING])).map((f) => f.id)).toEqual([PENDING.id]);
  });

  it("offers every pending factor, so repeated abandoned enrolments all get cleared", () => {
    const second = { ...PENDING, id: "5a39f7c2-8e14-4b0d-9f63-d2ac81e67b50" };
    const third = { ...PENDING, id: "c6071e4b-9d25-4a38-8e71-b3f0a95d2c18" };
    const data = sdkListFactors([PENDING, second, third]);
    expect(pendingTotpFactors(data).map((f) => f.id)).toEqual([PENDING.id, second.id, third.id]);
  });

  it("never offers a verified factor for removal, even beside pending ones", () => {
    const data = sdkListFactors([VERIFIED, PENDING]);
    const offered = pendingTotpFactors(data).map((f) => f.id);
    expect(offered).toEqual([PENDING.id]);
    expect(offered).not.toContain(VERIFIED.id);
  });

  it("offers nothing when the only factor is verified", () => {
    expect(pendingTotpFactors(sdkListFactors([VERIFIED]))).toEqual([]);
  });

  it("never offers another factor type — an unverified phone or webauthn factor is not ours to remove", () => {
    const phone = { id: "b83d20a6-4f19-4c72-9d05-e187a3c56f49", status: "unverified", factor_type: "phone" };
    const webauthn = { id: "e14a7b05-2c63-4d98-8f21-a607d9b35e14", status: "unverified", factor_type: "webauthn" };
    const data = sdkListFactors([PENDING, phone, webauthn]);
    expect(pendingTotpFactors(data).map((f) => f.id)).toEqual([PENDING.id]);
  });

  it("still prefers a verified factor when one exists", () => {
    expect(verifiedTotpFactor(sdkListFactors([PENDING, VERIFIED]))?.id).toBe(VERIFIED.id);
    expect(verifiedTotpFactor(sdkListFactors([VERIFIED]))?.id).toBe(VERIFIED.id);
  });

  it("reports no verified factor when every factor is pending", () => {
    expect(verifiedTotpFactor(sdkListFactors([PENDING]))).toBeUndefined();
  });

  it("treats an empty or absent response as nothing to do", () => {
    for (const d of [sdkListFactors([]), null, undefined, {}]) {
      expect(pendingTotpFactors(d)).toEqual([]);
      expect(verifiedTotpFactor(d)).toBeUndefined();
    }
  });
});

/**
 * The helper above is only worth anything if the flow actually calls it. Pinned
 * at the source, because the enrol effect runs in the browser against a live
 * GoTrue session and is not reachable from this suite.
 */
describe("the console's enrol effect reads the factors through the helper", () => {
  const src = (rel: string) => readFileSync(resolve(__dirname, "../src", rel), "utf8");
  const flow = () => src("components/auth/MfaFlow.tsx");

  it("asks the helper for both the verified factor and the pending ones", () => {
    expect(flow()).toContain("verifiedTotpFactor(factors)");
    expect(flow()).toContain("pendingTotpFactors(factors)");
  });

  it("never reads `.totp` off the listFactors response again", () => {
    expect(flow()).not.toMatch(/factors\s*(\?\.|\.)\s*totp/);
  });

  it("still unenrolls what the helper hands back, so the clean-up is reachable", () => {
    expect(flow()).toMatch(/for \(const f of pendingTotpFactors\(factors\)\) \{\s*await supabase\.auth\.mfa\.unenroll\(\{ factorId: f\.id \}\);/);
  });

  it("keeps challenging the factor the enrolment itself returned, not a re-derived one", () => {
    // The venue bug was re-deriving the factor at verify time; admin must not.
    expect(flow()).toContain("factorId: phase.factorId");
    expect(flow()).toContain("factorId: data.id");
  });
});
