/**
 * Reading the operator's TOTP factors out of `supabase.auth.mfa.listFactors()`.
 *
 * Pure on purpose: the decision lives in a `"use client"` effect that builds a
 * browser Supabase client, so it could not be put under test where it was
 * written. It lives here instead, shaped exactly like the SDK's response.
 *
 * **Read `all`, never `totp`.** @supabase/auth-js 2.115.0 builds the response in
 * `_listFactors` (dist/main/GoTrueClient.js:4997) as
 *
 *     for (const factor of user?.factors ?? []) {
 *       data.all.push(factor);
 *       if (factor.status === 'verified') data[factor.factor_type].push(factor);
 *     }
 *
 * so `data.totp` holds only VERIFIED factors — its own type says as much:
 * `Factor<'totp', 'verified'>[]`. A factor left behind by an abandoned enrolment
 * is `unverified`, so it appears in `data.all` and nowhere else, and filtering
 * `data.totp` for `status !== 'verified'` can only ever yield the empty set.
 * `data.totp` is not a shortcut for "the TOTP factors"; it is "the verified TOTP
 * factors". Covered by tests/totp-factor-cleanup.test.ts.
 */
export type FactorRow = {
  id: string;
  status?: string;
  factor_type?: string;
};

/** The shape `supabase.auth.mfa.listFactors()` resolves its `data` to. */
export type ListFactorsData = {
  all?: FactorRow[];
  totp?: FactorRow[];
  phone?: FactorRow[];
  webauthn?: FactorRow[];
} | null | undefined;

/**
 * Every TOTP factor on the operator, verified or not. `all` is the only field
 * that carries the unverified ones, and it carries every factor type, so the
 * `factor_type` filter is load-bearing: a pending phone or webauthn factor is
 * not a TOTP factor and is not this flow's to touch.
 */
function totpFactors(data: ListFactorsData): FactorRow[] {
  return (data?.all ?? []).filter((f) => f.factor_type === "totp");
}

/**
 * The verified factor, when the operator already has one. It wins: once one
 * exists the console only ever challenges it, and nothing below may touch it.
 */
export function verifiedTotpFactor(data: ListFactorsData): FactorRow | undefined {
  return totpFactors(data).find((f) => f.status === "verified");
}

/**
 * The pending TOTP factors — the ones an abandoned enrolment left behind.
 *
 * Their secret was shown once and is gone, so they can never be completed and
 * are only clutter; GoTrue counts them against its per-user factor cap, so
 * enough of them make the next `enroll()` fail outright.
 */
export function pendingTotpFactors(data: ListFactorsData): FactorRow[] {
  return totpFactors(data).filter((f) => f.status !== "verified");
}
