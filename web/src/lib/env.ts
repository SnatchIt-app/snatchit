/**
 * Environment access — public-class values only.
 * The service-role key must NEVER appear in this app (browser or server):
 * all privileged operations live in Supabase edge functions.
 */
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? null;
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? null;

/**
 * Fail-fast in production.
 *
 * Without this, missing Supabase env degrades silently: hasSupabaseEnv goes
 * false and listings.ts serves FIXTURE_LISTINGS with HTTP 200, so a
 * misconfigured deploy looks like a working marketplace showing invented
 * inventory at invented prices. Buyers could click through to checkout on
 * tickets that do not exist.
 *
 * Throwing at module load turns that into a failed build/boot instead, which
 * is the only safe direction to fail. Dev keeps the fixture path so the UI can
 * be worked on without a database.
 */
const IS_PROD = process.env.NODE_ENV === "production";

if (IS_PROD) {
  const missing = [
    !SUPABASE_URL && "NEXT_PUBLIC_SUPABASE_URL",
    !SUPABASE_ANON_KEY && "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  ].filter(Boolean);
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(", ")}. ` +
        "Refusing to start — serving fixture data in production would show " +
        "buyers listings that do not exist.",
    );
  }
}

/**
 * Dev-only fixture escape hatch. Always true in production, because the guard
 * above has already thrown if the env is incomplete.
 */
export const hasSupabaseEnv = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);

/** Publishable (client-safe) key only — same trust class as the Supabase anon key. */
export const STRIPE_PUBLISHABLE_KEY = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? null;

/** Canonical site origin for metadata, canonicals, and sitemaps. */
export const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

/**
 * Public storage host used for listing cover images. Falls back to the
 * production project host so fixture data still renders when env is absent.
 */
export const STORAGE_BASE_URL = `${SUPABASE_URL ?? "https://hqycwntpfoztoinemqns.supabase.co"}/storage/v1/object/public`;
