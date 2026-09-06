/**
 * Pure mapping from a PostgREST/Supabase error to the console's result
 * kinds. Kept free of `server-only` so it is unit-testable; `ops.ts` is the
 * only production caller.
 */
export type OpsFailure =
  | { ok: false; kind: "denied" }
  | { ok: false; kind: "mfa" }
  | { ok: false; kind: "error"; message: string; code?: string; unavailable?: boolean };

export type OpsResult<T> = { ok: true; data: T } | OpsFailure;

export type PostgrestLikeError = {
  code?: string | null;
  message?: string | null;
  details?: string | null;
  hint?: string | null;
};

/** PostgREST codes meaning "the function/schema is not there (yet)". */
const UNAVAILABLE_CODES = new Set([
  "PGRST202", // function not found in schema cache
  "PGRST106", // schema not in exposed list
  "PGRST200",
  "42883", // undefined_function
  "3F000", // invalid_schema_name
  "42P01", // undefined_table
]);

export function mapOpsError(fn: string, err: PostgrestLikeError | null | undefined): OpsFailure {
  const code = (err?.code ?? "").toString();
  const message = (err?.message ?? "").toString();
  const lower = message.toLowerCase();

  if (code === "42501" || lower.includes("insufficient_privilege")) {
    return { ok: false, kind: "denied" };
  }
  if (lower.includes("step_up_required") || lower.includes("step_up_unavailable")) {
    return { ok: false, kind: "mfa" };
  }
  if (UNAVAILABLE_CODES.has(code) || (code === "" && lower.includes("could not find the function"))) {
    return {
      ok: false,
      kind: "error",
      code: code || undefined,
      unavailable: true,
      message: `RPC ops.${fn} not available yet`,
    };
  }
  // Generic: keep the server's message (PostgREST messages carry no secrets),
  // never echo request args.
  return {
    ok: false,
    kind: "error",
    code: code || undefined,
    message: message || "Request failed",
  };
}
