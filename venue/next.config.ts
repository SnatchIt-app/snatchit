import path from "node:path";
import type { NextConfig } from "next";

const isDev = process.env.NODE_ENV === "development";

/**
 * Preview build: self-only CSP. There is deliberately no connect-src entry for
 * Supabase or Stripe — this app has no backend client at all (see
 * src/lib/data.ts). If a future wiring adds one, the origin must be added here
 * on purpose, not inherited.
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
