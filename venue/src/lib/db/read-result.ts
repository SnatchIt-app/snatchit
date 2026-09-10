/**
 * Result type for every database read. Failures are explicit and typed so the
 * UI can say what actually happened; nothing here ever falls back to fixtures.
 */
export type ReadFailureKind = "auth" | "permission" | "config" | "not_exposed" | "transport" | "error";

export type ReadFailure = { ok: false; kind: ReadFailureKind; message: string; code?: string; read: string };
export type ReadResult<T> = { ok: true; data: T } | ReadFailure;

type PgError = { code?: string | null; message?: string | null; details?: string | null; hint?: string | null };

/**
 * Maps a PostgREST/PostgreSQL error to a failure kind. Codes:
 *   PGRST301/PGRST302/401-class → auth (JWT missing/expired/invalid)
 *   PGRST106 → not_exposed (schema not in db-schemas)
 *   42501    → permission (insufficient_privilege from RLS/grants)
 *   42P01/42883 → config (object missing: migration not applied)
 */
export function mapReadError(read: string, e: PgError | null | undefined, status?: number): ReadFailure {
  const code = e?.code ?? undefined;
  const message = e?.message ?? "Request failed";
  if (code === "PGRST106") return { ok: false, kind: "not_exposed", message, code, read };
  if (code === "PGRST301" || code === "PGRST302" || status === 401) return { ok: false, kind: "auth", message, code, read };
  if (code === "42501") return { ok: false, kind: "permission", message, code, read };
  if (code === "42P01" || code === "42883" || code === "3F000") return { ok: false, kind: "config", message: `${message} (migration 20260910120000_venue_api_read_views not applied?)`, code, read };
  if (/fetch failed|ECONNREFUSED|ENOTFOUND|network|TypeError/i.test(message)) return { ok: false, kind: "transport", message, code, read };
  return { ok: false, kind: "error", message, code, read };
}

export function transportFailure(read: string, e: unknown): ReadFailure {
  return { ok: false, kind: "transport", message: e instanceof Error ? e.message : "Request failed", read };
}
