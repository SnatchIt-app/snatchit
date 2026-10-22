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

/**
 * On a Vercel PRODUCTION deployment the data source must be stated explicitly. The default
 * ("fixtures" when the variable is unset, and the silent coercion of any unknown value to
 * "fixtures") is right for local and preview work, and wrong on the real host: a forgotten or
 * mistyped variable would serve invented venues and events from production. Owner decision
 * 2026-10-22 §F ("remove fixtures/sample adapters from production mode"). An explicit "fixtures"
 * stays allowed, because the owner-only demo project sets it on purpose (decision V-09) and every
 * page there is labelled "Demo — sample data". Returns the reason to refuse, or null.
 */
export function productionDataSourceProblem(vercelEnv: string | null | undefined, rawSource: string | null | undefined): string | null {
  if ((vercelEnv ?? "").trim() !== "production") return null;
  const src = (rawSource ?? "").trim().toLowerCase();
  if (src === "database" || src === "fixtures") return null;
  if (src === "") {
    return "Refusing to build: NEXT_PUBLIC_VENUE_DATA_SOURCE is not set on a production deployment. Set it to \"database\" (the venue dashboard) or \"fixtures\" (the owner-only demo); it never defaults in production.";
  }
  return `Refusing to build: NEXT_PUBLIC_VENUE_DATA_SOURCE="${src.slice(0, 40)}" is neither "database" nor "fixtures" on a production deployment; nothing is coerced to sample data there.`;
}

const productionProblem = productionDataSourceProblem(process.env.NEXT_PUBLIC_VERCEL_ENV, process.env.NEXT_PUBLIC_VENUE_DATA_SOURCE);
if (productionProblem) throw new Error(productionProblem);

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

/**
 * Database mode with a privileged key in the public slot is refused outright. Two shapes:
 *   - a new-format secret API key (`sb_secret_…`; the public one is `sb_publishable_…`), and
 *   - a legacy JWT key whose payload says `role: service_role`.
 */
export function keyLooksPrivileged(key: string | null): boolean {
  if (!key) return false;
  if (key.trim().toLowerCase().startsWith("sb_secret_")) return true;
  const part = key.split(".")[1];
  if (!part) return false;
  try {
    const payload = JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as { role?: unknown };
    return payload.role === "service_role";
  } catch {
    return false;
  }
}
