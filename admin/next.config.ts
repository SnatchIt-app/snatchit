import path from "node:path";
import type { NextConfig } from "next";

const SUPABASE_HOST = "hqycwntpfoztoinemqns.supabase.co";

/**
 * The console may point at production, staging, or the local rehearsal stack
 * (http://localhost:<port>). Allow exactly the configured origin in
 * connect-src (plus its websocket twin), nothing else.
 */
const envOrigin = (() => {
  try {
    return process.env.NEXT_PUBLIC_SUPABASE_URL ? new URL(process.env.NEXT_PUBLIC_SUPABASE_URL) : null;
  } catch {
    return null;
  }
})();
const extraOrigins: string[] = [];
if (envOrigin && envOrigin.host !== SUPABASE_HOST) {
  const http = `${envOrigin.protocol}//${envOrigin.host}`;
  const ws = `${envOrigin.protocol === "https:" ? "wss:" : "ws:"}//${envOrigin.host}`;
  extraOrigins.push(http, ws);
}

const isDev = process.env.NODE_ENV === "development";

/**
 * Content Security Policy — self + Supabase only. No Stripe, no analytics.
 * img-src allows data: because the TOTP enrolment QR is an SVG data URL.
 * 'unsafe-inline' in script-src is required by Next.js hydration inline
 * scripts; 'unsafe-eval' is dev-only (React Refresh).
 */
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  `img-src 'self' data: blob: https://${SUPABASE_HOST}`,
  "font-src 'self'",
  `connect-src 'self' https://${SUPABASE_HOST} wss://${SUPABASE_HOST}${extraOrigins.length ? ` ${extraOrigins.join(" ")}` : ""}`,
  "frame-src 'none'",
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
  { key: "X-Robots-Tag", value: "noindex, nofollow" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
  },
  ...(isDev ? [] : [{ key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" }]),
];

const nextConfig: NextConfig = {
  // admin/ is self-contained; the build root is this directory (monorepo sibling of web/).
  turbopack: { root: path.join(__dirname) },
  poweredByHeader: false,
  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },
};

export default nextConfig;
