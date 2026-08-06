import path from "node:path";
import type { NextConfig } from "next";

const SUPABASE_HOST = "hqycwntpfoztoinemqns.supabase.co";
const envHost = (() => {
  try {
    return process.env.NEXT_PUBLIC_SUPABASE_URL
      ? new URL(process.env.NEXT_PUBLIC_SUPABASE_URL).hostname
      : null;
  } catch {
    return null;
  }
})();
const extraHost = envHost && envHost !== SUPABASE_HOST ? envHost : null;

const isDev = process.env.NODE_ENV === "development";

/**
 * Content Security Policy.
 * Scope: self + Supabase (REST/Storage/Realtime) + Stripe (Payment Element,
 * added for web checkout — js.stripe.com in script/frame, api.stripe.com in
 * connect, per Stripe's own CSP guidance). Sentry ingest is pre-allowed in
 * connect-src so enabling @sentry/nextjs later is a no-op here.
 * 'unsafe-inline' in script-src is required by Next.js hydration inline
 * scripts; the documented hardening path is nonce-based CSP via proxy.ts in
 * the transaction phase. 'unsafe-eval' is dev-only (React Refresh).
 */
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline' https://js.stripe.com${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  `img-src 'self' data: blob: https://${SUPABASE_HOST}${extraHost ? ` https://${extraHost}` : ""}`,
  "font-src 'self'",
  // Sentry: *.ingest.sentry.io covers EU and regionless DSNs too. Allowing
  // only the US host would have CSP-blocked error reporting on any other
  // region — silently, since a blocked report cannot report itself.
  `connect-src 'self' https://${SUPABASE_HOST} wss://${SUPABASE_HOST}${extraHost ? ` https://${extraHost} wss://${extraHost}` : ""} https://*.ingest.sentry.io https://*.ingest.us.sentry.io https://*.ingest.de.sentry.io https://api.stripe.com`,
  "frame-src https://js.stripe.com https://hooks.stripe.com",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  ...(isDev ? [] : ["upgrade-insecure-requests"]),
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: csp },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Permissions-Policy",
    // payment=(self) leaves room for Express Checkout later; the rest is off.
    value: "camera=(), microphone=(), geolocation=(), payment=(self), usb=()",
  },
  ...(isDev
    ? []
    : [{ key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" }]),
];

const nextConfig: NextConfig = {
  // web/ is self-contained (shared packages vendored via web/vendor tarballs —
  // see scripts/sync-packages.mjs), so the build root is this directory.
  turbopack: { root: path.join(__dirname) },
  // Shared packages are TypeScript-source-only; Next compiles them in place.
  transpilePackages: ["@snatchit/types", "@snatchit/core", "@snatchit/design-tokens"],
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: SUPABASE_HOST,
        pathname: "/storage/v1/object/public/**",
      },
      ...(extraHost
        ? [
            {
              protocol: "https" as const,
              hostname: extraHost,
              pathname: "/storage/v1/object/public/**",
            },
          ]
        : []),
    ],
  },
  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },
};

export default nextConfig;
