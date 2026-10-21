import path from "node:path";
import type { NextConfig } from "next";

const isDev = process.env.NODE_ENV === "development";

/**
 * Self-only CSP in both modes. There is deliberately no connect-src entry for
 * Supabase or Stripe: the browser never calls a backend. Fixture mode has no
 * backend client at all; database mode runs every Supabase call (sign-in,
 * session refresh, venue_api reads) on the server (src/lib/supabase/server.ts,
 * src/lib/supabase/proxy.ts), so the page only ever talks to 'self'. If a
 * future change adds a browser-side call, its origin must be added here on
 * purpose, not inherited. No value here is host-specific, so the same policy
 * serves the preview host and venue.snatchitapp.com.
 *
 * Mirrors admin/next.config.ts where it applies: the same Permissions-Policy,
 * and HSTS outside `next dev`. HSTS is max-age only: includeSubDomains would
 * bind every snatchitapp.com subdomain to HTTPS, which is not this app's call,
 * and preload is not wanted. Browsers ignore HSTS on plain http (localhost).
 * Not mirrored: admin's upgrade-insecure-requests. Every subresource here is
 * same-origin and relative (no absolute URL in src/, pinned by a test), so it
 * would change nothing on https and only matter on http://localhost.
 */
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self'",
  "connect-src 'self'",
  "frame-src 'none'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: csp },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Robots-Tag", value: "noindex, nofollow" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), payment=(), usb=()" },
  ...(isDev ? [] : [{ key: "Strict-Transport-Security", value: "max-age=63072000" }]),
];

const nextConfig: NextConfig = {
  // venue/ is self-contained; the build root is this directory (monorepo sibling of admin/ and web/).
  turbopack: { root: path.join(__dirname) },
  poweredByHeader: false,
  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },
};

export default nextConfig;
