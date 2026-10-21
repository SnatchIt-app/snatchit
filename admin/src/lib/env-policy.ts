/**
 * Pure environment rules, kept apart from env.ts so they can be tested with
 * any input. env.ts reads each `process.env.NEXT_PUBLIC_*` by its literal
 * name (that is what Next.js inlines into the browser bundle) and passes the
 * values in here.
 */

/**
 * Labels that mean "this console is wired to the local synthetic harness".
 * Exact values only: anything else — unset, "preview", "staging", "sample",
 * a typo — is not a claim that the figures are fixtures.
 */
export const SAMPLE_DATA_LABELS = ["local", "harness", "rehearsal"] as const;

/**
 * The label to show in the "Sample data" notice, or null for no notice.
 * The notice says the figures are not Snatch It business data, so it needs an
 * explicitly set allowlisted label, and it never appears on a Vercel
 * production or preview deployment (both can point at a real database).
 */
export function sampleDataLabel(input: { label: string | undefined; vercelEnv: string | undefined }): string | null {
  const vercel = (input.vercelEnv ?? "").trim();
  if (vercel === "production" || vercel === "preview") return null;
  const label = (input.label ?? "").trim();
  return (SAMPLE_DATA_LABELS as readonly string[]).includes(label) ? label : null;
}

/** The `role` claim of a legacy Supabase JWT key; undefined when the value is not a decodable JWT. */
function legacyJwtRole(key: string): string | null | undefined {
  const parts = key.split(".");
  if (parts.length !== 3 || !parts[1]) return undefined;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload: unknown = JSON.parse(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4)));
    if (!payload || typeof payload !== "object") return undefined;
    const role = (payload as { role?: unknown }).role;
    return typeof role === "string" ? role : null;
  } catch {
    return undefined;
  }
}

/**
 * Why this value must not be used as NEXT_PUBLIC_SUPABASE_ANON_KEY, or null.
 * That variable is inlined into the browser bundle, so a privileged key there
 * is published to every visitor. Refused:
 *  - any `sb_secret_…` key (new-format secret key);
 *  - a legacy JWT key whose `role` claim is `service_role`, or any role
 *    other than `anon`.
 * Accepted: `sb_publishable_…`, a legacy anon JWT, and values that are
 * neither (e.g. the CI placeholder). The message never contains the key.
 */
export function anonKeyProblem(raw: string | null | undefined): string | null {
  const key = (raw ?? "").trim();
  if (!key) return null;
  const advice = "Use the project's publishable key (sb_publishable_…) or the legacy anon key. Rotate the exposed key if it was ever deployed.";
  if (key.startsWith("sb_secret_")) {
    return `NEXT_PUBLIC_SUPABASE_ANON_KEY is a Supabase secret key (sb_secret_…). It would be shipped to every browser. ${advice}`;
  }
  const role = legacyJwtRole(key);
  if (role === "service_role") {
    return `NEXT_PUBLIC_SUPABASE_ANON_KEY is a legacy JWT with role service_role. It would be shipped to every browser and bypasses RLS. ${advice}`;
  }
  if (typeof role === "string" && role !== "anon") {
    return `NEXT_PUBLIC_SUPABASE_ANON_KEY is a legacy JWT whose role is not "anon". ${advice}`;
  }
  return null;
}

/**
 * Hosts a Vercel production deploy of the console may name in
 * NEXT_PUBLIC_SITE_URL. admin.snatchitapp.com is the final production domain.
 * snatchit-admin.vercel.app is a transition entry: it is the live origin
 * today and stays the rollback alias while the custom domain is cut over.
 * Remove it once admin.snatchitapp.com is live and the old alias is retired.
 */
export const PRODUCTION_SITE_HOSTS = ["admin.snatchitapp.com", "snatchit-admin.vercel.app"] as const;

/**
 * Why NEXT_PUBLIC_SITE_URL cannot be the production origin, or null.
 * Must be https://, on one of PRODUCTION_SITE_HOSTS, with no port and no
 * credentials (a path is ignored). The message shows the parsed host only,
 * never the raw value, which could carry credentials.
 */
export function productionSiteUrlProblem(raw: string | undefined): string | null {
  let url: URL | null = null;
  try {
    url = new URL(raw ?? "");
  } catch {
    url = null;
  }
  const shown = url ? `host "${url.hostname}"` : "a value that is not a URL";
  const want = `It must be https://${PRODUCTION_SITE_HOSTS[0]} (or https://${PRODUCTION_SITE_HOSTS[1]} during the transition).`;
  if (!url || url.protocol !== "https:") {
    return `NEXT_PUBLIC_SITE_URL (${shown}) cannot be the production origin: it must be https:// on a real host. ${want}`;
  }
  if (url.username || url.password || url.port || !(PRODUCTION_SITE_HOSTS as readonly string[]).includes(url.hostname)) {
    return `NEXT_PUBLIC_SITE_URL (${shown}${url.port ? `, port ${url.port}` : ""}${url.username || url.password ? ", with credentials" : ""}) is not this console's production origin. ${want}`;
  }
  return null;
}
