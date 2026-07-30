/**
 * Environment access — public-class values only.
 * The service-role key must NEVER appear in this app (browser or server):
 * all privileged operations live in Supabase edge functions.
 */
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? null;
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? null;

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
