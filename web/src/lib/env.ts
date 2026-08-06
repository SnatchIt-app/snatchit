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
    // NEXT_PUBLIC_SITE_URL is required too, and its failure is the quietest of
    // the three: it falls back to http://localhost:3000, which is then baked
    // into signup-confirmation and password-reset email links (auth/actions.ts)
    // and into the Stripe checkout return_url (PaymentForm.tsx). Users are
    // locked out of their accounts, and 3DS buyers land nowhere after paying,
    // with nothing logged anywhere.
    !process.env.NEXT_PUBLIC_SITE_URL && "NEXT_PUBLIC_SITE_URL",
  ].filter(Boolean);
  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(", ")}. ` +
        "Refusing to start — serving fixture data in production would show " +
        "buyers listings that do not exist, and a localhost SITE_URL silently " +
        "breaks auth emails and post-payment redirects.",
    );
  }

  // Presence alone is not enough. NEXT_PUBLIC_SITE_URL=http://localhost:3000
  // is truthy, passes the check above, builds green, deploys green — and then
  // every password-reset and signup-confirmation email points at localhost
  // while 3DS buyers are redirected there after paying. That exact value is
  // what sits in .env.local, so promoting it to the Vercel Production scope is
  // a copy-paste away.
  //
  // Only enforced on real production deploys (VERCEL_ENV=production), not on
  // previews or local `next build`, which legitimately run against other hosts.
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
        `NEXT_PUBLIC_SITE_URL is "${raw}", which cannot be the production ` +
          "origin. It must be an https:// URL on a real host — it is baked " +
          "into password-reset and signup-confirmation email links and into " +
          "the Stripe checkout return_url.",
      );
    }
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
