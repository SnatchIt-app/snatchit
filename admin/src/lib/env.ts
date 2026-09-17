/**
 * Environment access — public-class values only.
 *
 * The service-role key must NEVER appear in this app (browser or server).
 * Every read and mutation the console performs is an `ops.*` RPC executed
 * with the operator's own JWT; the database re-checks role + aal2 itself.
 */
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? null;
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? null;

/** Canonical console origin (used for absolute links only; no email flows here). */
export const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3200";

/**
 * Human label of the environment the console is pointed at — rendered as a
 * header badge so an operator never mutates production thinking it is
 * staging. "production" renders red.
 */
export const ENV_LABEL = (process.env.NEXT_PUBLIC_ENV_LABEL ?? "local").trim() || "local";
export const IS_PRODUCTION_ENV_LABEL = ENV_LABEL.toLowerCase() === "production";

const IS_PROD = process.env.NODE_ENV === "production";

/**
 * Fail-fast in production (same posture as web/): a console that boots
 * without Supabase env would render an empty shell that looks like "no
 * attention items" — the worst possible failure mode for an operations tool.
 */
if (IS_PROD) {
  const missing = [
    !SUPABASE_URL && "NEXT_PUBLIC_SUPABASE_URL",
    !SUPABASE_ANON_KEY && "NEXT_PUBLIC_SUPABASE_ANON_KEY",
    !process.env.NEXT_PUBLIC_SITE_URL && "NEXT_PUBLIC_SITE_URL",
  ].filter(Boolean);
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(", ")}. ` +
        "Refusing to start — an operations console with no database looks like an empty queue.",
    );
  }

  if (process.env.NEXT_PUBLIC_VERCEL_ENV === "production") {
    const raw = process.env.NEXT_PUBLIC_SITE_URL!;
    let parsed: URL | null = null;
    try {
      parsed = new URL(raw);
    } catch {
      parsed = null;
    }
    const host = parsed?.hostname ?? "";
    const isLocal = host === "localhost" || host === "127.0.0.1" || host === "::1" || host.endsWith(".local");
    if (!parsed || parsed.protocol !== "https:" || isLocal) {
      throw new Error(
        `NEXT_PUBLIC_SITE_URL is "${raw}", which cannot be the production origin (must be https:// on a real host).`,
      );
    }
    if (!IS_PRODUCTION_ENV_LABEL) {
      // A production deploy that says "staging" in the header is a lie the
      // operator will act on. Refuse it.
      throw new Error(
        `NEXT_PUBLIC_ENV_LABEL is "${ENV_LABEL}" on a Vercel production deploy; it must be "production".`,
      );
    }
  }
}

export const hasSupabaseEnv = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);
