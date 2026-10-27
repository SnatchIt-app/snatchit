/**
 * Reading the caller's TOTP factors out of `listFactors()`.
 *
 * Pure on purpose: `step-up.ts` is `"use server"` and builds a Supabase client,
 * so the decision that actually went wrong in the sandbox could not be put under
 * test where it lived. It lives here now, shaped exactly like the SDK's response.
 *
 * **Read `all`, never `totp`.** @supabase/auth-js 2.115.0 builds the response as
 *
 *     for (const factor of user?.factors ?? []) {
 *       data.all.push(factor);
 *       if (factor.status === 'verified') data[factor.factor_type].push(factor);
 *     }
 *
 * so `data.totp` holds only VERIFIED factors. A factor that was just enrolled is
 * `unverified` and appears in `data.all` alone — which means a reader looking at
 * `data.totp` cannot see the factor whose QR the operator is holding, reports
 * "no authenticator yet", and sends the UI off to enrol again over the top of it.
 * That was the sandbox loop of 2026-10-27. `data.totp` is not a shortcut for
 * "the TOTP factors"; it is "the verified TOTP factors".
 */
export type FactorRow = {
  id: string;
  status?: string;
  factor_type?: string;
  created_at?: string;
};

/** The shape `supabase.auth.mfa.listFactors()` resolves its `data` to. */
export type ListFactorsData = {
  all?: FactorRow[];
  totp?: FactorRow[];
  phone?: FactorRow[];
  webauthn?: FactorRow[];
} | null | undefined;

export type TotpFactorState =
  | { kind: "verified"; factorId: string }
  | { kind: "unverified"; factorId: string }
  | { kind: "none" };

/** Every TOTP factor on the caller, verified or not. */
function totpFactors(data: ListFactorsData): FactorRow[] {
  return (data?.all ?? []).filter((f) => f.factor_type === "totp");
}

const at = (f: FactorRow): number => {
  const t = Date.parse(f.created_at ?? "");
  return Number.isNaN(t) ? 0 : t;
};

/**
 * A verified factor wins: once one exists, step-up is a code away and nothing
 * should ever offer enrolment again. Otherwise the NEWEST pending factor, which
 * is the one whose QR the operator most recently scanned — an operator who
 * scanned several times before we fixed this has older, dead ones behind it.
 */
export function pickTotpFactor(data: ListFactorsData): TotpFactorState {
  const factors = totpFactors(data);
  const verified = factors.find((f) => f.status === "verified");
  if (verified) return { kind: "verified", factorId: verified.id };
  const pending = factors.filter((f) => f.status !== "verified");
  if (pending.length === 0) return { kind: "none" };
  // Later index wins ties: GoTrue appends, so the last row is the most recent
  // when timestamps are absent or equal.
  const newest = pending.reduce((best, f) => (at(f) >= at(best) ? f : best), pending[0]);
  return { kind: "unverified", factorId: newest.id };
}

/** Pending factors, oldest first — all of them, so abandoned scans can be cleared. */
export function pendingTotpFactors(data: ListFactorsData): FactorRow[] {
  return totpFactors(data).filter((f) => f.status !== "verified");
}

/**
 * Whether a factor id names one of THIS caller's own TOTP factors.
 *
 * The browser may send the id it just enrolled, so that a verify lands on that
 * exact factor rather than on whatever a fresh list happens to return first. It
 * is a hint and nothing more: an id that is not the caller's own is refused here
 * and the server falls back to its own reading, so no client can nominate a
 * factor belonging to anybody else.
 */
export function ownsFactor(data: ListFactorsData, factorId: string): boolean {
  const id = (factorId ?? "").trim();
  if (!id) return false;
  return totpFactors(data).some((f) => f.id === id);
}
