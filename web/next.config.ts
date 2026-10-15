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
 * Local preview harness (synthetic data on this machine only). When
 * SNATCHIT_LOCAL_HARNESS=1 and NEXT_PUBLIC_SUPABASE_URL is an http loopback
 * origin, that exact origin is allowed for images and connections (http, and
 * ws for Realtime, as production allows https + wss), and next/image may
 * optimize it. Never active on Vercel (VERCEL is set there),
 * and with the flag unset every header and image rule below is unchanged
 * (tests/next-config-headers.test.ts).
 */
const localHarnessOrigin = (() => {
  if (process.env.SNATCHIT_LOCAL_HARNESS !== "1" || process.env.VERCEL) return null;
  try {
    const u = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL ?? "");
    const loopback = u.hostname === "127.0.0.1" || u.hostname === "localhost";
    return u.protocol === "http:" && loopback ? u : null;
  } catch {
    return null;
  }
})();
const harnessSrc = localHarnessOrigin ? ` ${localHarnessOrigin.origin}` : "";
const harnessConnect = localHarnessOrigin ? `${harnessSrc} ws://${localHarnessOrigin.host}` : "";

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
  `img-src 'self' data: blob: https://${SUPABASE_HOST}${extraHost ? ` https://${extraHost}` : ""}${harnessSrc}`,
  "font-src 'self'",
  // Sentry: *.ingest.sentry.io covers EU and regionless DSNs too. Allowing
  // only the US host would have CSP-blocked error reporting on any other
  // region — silently, since a blocked report cannot report itself.
  `connect-src 'self' https://${SUPABASE_HOST} wss://${SUPABASE_HOST}${extraHost ? ` https://${extraHost} wss://${extraHost}` : ""} https://*.ingest.sentry.io https://*.ingest.us.sentry.io https://*.ingest.de.sentry.io https://api.stripe.com${harnessConnect}`,
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
      ...(localHarnessOrigin
        ? [
            {
              protocol: "http" as const,
              hostname: localHarnessOrigin.hostname,
              port: localHarnessOrigin.port,
              pathname: "/storage/v1/object/public/**",
            },
          ]
        : []),
    ],
    ...(localHarnessOrigin ? { dangerouslyAllowLocalIP: true } : {}),
  },
  async headers() {
    return [
      { source: "/(.*)", headers: securityHeaders },
      // An emailed auth link can land here with a session in the fragment until the page strips
      // it. Browsers never send fragments as a Referer, but this page also sends none at all and
      // is never cached (the later rule wins for the same key).
      {
        source: "/auth/confirm",
        headers: [
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "Cache-Control", value: "no-store" },
        ],
      },
      // Stripe's redirect lands here with payment_intent_client_secret in the query until the page
      // drops it; send no Referer from it and never cache it.
      {
        source: "/checkout/:id/complete",
        headers: [
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "Cache-Control", value: "no-store" },
        ],
      },
    ];
  },
};

export default nextConfig;
