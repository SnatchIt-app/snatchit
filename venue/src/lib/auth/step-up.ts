"use server";

import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * TOTP step-up on the venue host, server side.
 *
 * Why server side: the venue app's CSP is `connect-src 'self'` in every mode
 * and there is no browser Supabase client anywhere in it (next.config.ts says
 * a browser-side origin must be added on purpose, never inherited). Running
 * enrol/challenge/verify through a server action keeps that promise: the code
 * the operator types is posted to this app, which talks to GoTrue from the
 * server and lets @supabase/ssr rewrite the session cookie with the new aal2
 * token. Nothing about the factor is held by this app between calls.
 *
 * This raises the CALLER'S OWN session only. It is not an authorization for
 * anything: every verb that cares (here, `kernel.set_org_connect_ref` through
 * the Connect edge) re-reads `aal` from the verified JWT itself.
 */
export type TotpFactorState =
  | { kind: "verified"; factorId: string }
  | { kind: "unverified"; factorId: string }
  | { kind: "none" }
  | { kind: "unavailable"; message: string };

export type EnrollStarted = { ok: true; factorId: string; qrSvg: string; secret: string; uri: string } | { ok: false; message: string };
export type StepUpResult = { ok: true; aal: string | null } | { ok: false; message: string; needsEnroll?: boolean };

const GENERIC = "Could not confirm the code. Check your authenticator and try again.";

type Factor = { id: string; status?: string; factor_type?: string };

/** What factor the caller already has. A verified one means step-up is a code away. */
export async function totpFactorState(): Promise<TotpFactorState> {
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.mfa.listFactors();
    if (error) return { kind: "unavailable", message: error.message };
    const totp: Factor[] = (data?.totp as Factor[] | undefined) ?? [];
    const verified = totp.find((f) => f.status === "verified");
    if (verified) return { kind: "verified", factorId: verified.id };
    const pending = totp[0];
    if (pending) return { kind: "unverified", factorId: pending.id };
    return { kind: "none" };
  } catch (e) {
    return { kind: "unavailable", message: e instanceof Error ? e.message : "MFA unavailable" };
  }
}

/**
 * Starts enrolment for a caller with no verified factor and returns the QR to
 * scan. An abandoned unverified factor is removed first: its secret was shown
 * once and can never be completed, and GoTrue refuses a duplicate name.
 */
export async function beginTotpEnroll(): Promise<EnrollStarted> {
  try {
    const supabase = await createSupabaseServerClient();
    const { data: list, error: listErr } = await supabase.auth.mfa.listFactors();
    if (listErr) return { ok: false, message: listErr.message };
    const totp: Factor[] = (list?.totp as Factor[] | undefined) ?? [];
    if (totp.some((f) => f.status === "verified")) return { ok: false, message: "This account already has an authenticator. Enter a code instead." };
    for (const f of totp) await supabase.auth.mfa.unenroll({ factorId: f.id });
    const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: `Snatch It venue ${new Date().toISOString().slice(0, 19)}` });
    if (error) return { ok: false, message: error.message };
    const totpData = data?.totp as { qr_code?: string; secret?: string; uri?: string } | undefined;
    if (!data?.id || !totpData?.qr_code || !totpData.secret || !totpData.uri) return { ok: false, message: "Enrolment did not return a code to scan." };
    return { ok: true, factorId: data.id, qrSvg: totpData.qr_code, secret: totpData.secret, uri: totpData.uri };
  } catch (e) {
    return { ok: false, message: e instanceof Error ? e.message : "Could not start enrolment." };
  }
}

/**
 * Challenge + verify for the caller's factor. On success @supabase/ssr writes
 * the new (aal2) session cookie through this app's cookie handler, so the next
 * request — and the edge call made from it — carries aal2.
 * `factorId` is optional: the caller's own verified factor is used when absent,
 * so a client cannot nominate someone else's factor.
 */
export async function verifyTotpCode(code: string, factorId?: string): Promise<StepUpResult> {
  const digits = (code ?? "").replace(/\s+/g, "");
  if (!/^\d{6}$/.test(digits)) return { ok: false, message: "Enter the 6-digit code from your authenticator." };
  try {
    const supabase = await createSupabaseServerClient();
    let id = factorId;
    if (!id) {
      const state = await totpFactorState();
      if (state.kind === "none") return { ok: false, message: "This account has no authenticator yet.", needsEnroll: true };
      if (state.kind === "unavailable") return { ok: false, message: state.message };
      id = state.factorId;
    }
    const { data: challenge, error: chErr } = await supabase.auth.mfa.challenge({ factorId: id });
    if (chErr || !challenge?.id) return { ok: false, message: chErr?.message ?? GENERIC };
    const { error: vErr } = await supabase.auth.mfa.verify({ factorId: id, challengeId: challenge.id, code: digits });
    if (vErr) return { ok: false, message: GENERIC };
    const { data } = await supabase.auth.getClaims();
    const aal = typeof data?.claims?.aal === "string" ? data.claims.aal : null;
    return { ok: true, aal };
  } catch (e) {
    return { ok: false, message: e instanceof Error ? e.message : GENERIC };
  }
}
