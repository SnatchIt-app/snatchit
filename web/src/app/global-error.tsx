"use client";

import { useEffect } from "react";
import { captureException } from "@/lib/observability";

/**
 * Last-resort boundary: catches errors thrown by the root layout itself, which
 * app/error.tsx cannot — it renders *inside* that layout. Because the layout
 * failed, this component has to supply its own <html> and <body>, and cannot
 * use any shared UI component or global CSS (those may be exactly what broke).
 * Hence the self-contained stylesheet below.
 *
 * Native palette, hard-coded on purpose (the --sn-* tokens live in the CSS
 * that may not have loaded): Midnight by default — canvas #000, ink #fff,
 * brand-red pill with a black label — and Daylight (#fff / #0B0C0E) when the
 * OS prefers light. The sn-theme cookie can't be read here, so this follows
 * the system setting only.
 */
const css = `
:root { color-scheme: dark light; }
.sn-ge-body {
  margin: 0;
  min-height: 100vh;
  min-height: 100dvh;
  display: flex;
  align-items: center;
  justify-content: center;
  box-sizing: border-box;
  padding: 24px 20px;
  background: #000000;
  color: #ffffff;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -webkit-text-size-adjust: 100%;
}
.sn-ge-wrap { width: 100%; max-width: 420px; text-align: center; }
.sn-ge-eyebrow {
  margin: 0 0 12px;
  font-size: 11px;
  font-weight: 600;
  line-height: 1.45;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: #ff1a1a;
}
.sn-ge-title { margin: 0 0 10px; font-size: 26px; font-weight: 700; line-height: 1.12; }
.sn-ge-body-text { margin: 0 0 28px; font-size: 15px; line-height: 1.47; color: rgba(255, 255, 255, 0.58); }
.sn-ge-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 52px;
  padding: 0 28px;
  border: 0;
  border-radius: 9999px;
  background: #ff1a1a;
  color: #000000;
  font: inherit;
  font-size: 16px;
  font-weight: 700;
  line-height: 1.25;
  cursor: pointer;
  transition: background-color 180ms ease, transform 90ms ease;
}
.sn-ge-button:hover { background: #ff5353; }
.sn-ge-button:active { transform: scale(0.98); }
.sn-ge-button:focus-visible { outline: 2px solid #ffffff; outline-offset: 2px; }
@media (prefers-color-scheme: light) {
  .sn-ge-body { background: #ffffff; color: #0b0c0e; }
  .sn-ge-eyebrow { color: #d31212; }
  .sn-ge-body-text { color: #686c73; }
  .sn-ge-button:focus-visible { outline-color: #0b0c0e; }
}
@media (prefers-reduced-motion: reduce) {
  .sn-ge-button { transition: none; }
  .sn-ge-button:active { transform: none; }
}
`;

export default function GlobalError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  useEffect(() => {
    captureException("app/global-error", error, { digest: error.digest ?? "none" });
  }, [error]);

  return (
    <html lang="en">
      <body className="sn-ge-body">
        {/* Static, author-controlled CSS — injected raw so quotes in the font stack survive SSR escaping. */}
        <style dangerouslySetInnerHTML={{ __html: css }} />
        <main className="sn-ge-wrap">
          <p className="sn-ge-eyebrow">Snatch It</p>
          <h1 className="sn-ge-title">Something went wrong</h1>
          <p className="sn-ge-body-text">
            We hit an unexpected error loading the page. Try again — if it keeps
            happening, please contact support.
          </p>
          <button type="button" className="sn-ge-button" onClick={() => retry()}>
            Try again
          </button>
        </main>
      </body>
    </html>
  );
}
