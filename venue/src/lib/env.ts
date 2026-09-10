/**
 * Environment — public-class values only. No service-role key exists in this
 * app, in any mode (see docs/venue-dashboard/SLICE1_HANDOFF.md, "credentials").
 *
 * NEXT_PUBLIC_VENUE_DATA_SOURCE  "fixtures" (default) | "database"
 * NEXT_PUBLIC_SUPABASE_URL       database mode only
 * NEXT_PUBLIC_SUPABASE_ANON_KEY  database mode only (anon/publishable key)
 * NEXT_PUBLIC_ENV_LABEL          "rehearsal" | "staging" | … — shown in the banner
 */
export type DataSource = "fixtures" | "database";

const rawSource = (process.env.NEXT_PUBLIC_VENUE_DATA_SOURCE ?? "fixtures").trim().toLowerCase();
export const DATA_SOURCE: DataSource = rawSource === "database" ? "database" : "fixtures";
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? null;
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? null;
export const ENV_LABEL = (process.env.NEXT_PUBLIC_ENV_LABEL ?? "local").trim() || "local";

/** Host shown in the banner (never the key). */
export function supabaseHost(): string | null {
  if (!SUPABASE_URL) return null;
  try {
    return new URL(SUPABASE_URL).host;
  } catch {
    return null;
  }
}

/** Database mode with a service-role-looking key is refused outright. */
export function keyLooksPrivileged(key: string | null): boolean {
  if (!key) return false;
  const part = key.split(".")[1];
  if (!part) return false;
  try {
    const payload = JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as { role?: unknown };
    return payload.role === "service_role";
  } catch {
    return false;
  }
}
