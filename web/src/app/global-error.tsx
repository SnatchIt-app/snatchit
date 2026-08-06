"use client";

import { useEffect } from "react";
import { captureException } from "@/lib/observability";

/**
 * Last-resort boundary: catches errors thrown by the root layout itself, which
 * app/error.tsx cannot — it renders *inside* that layout. Because the layout
 * failed, this component has to supply its own <html> and <body>, and cannot
 * use any shared UI component or global CSS (those may be exactly what broke).
 * Hence the inline styles.
 */
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    captureException("app/global-error", error, { digest: error.digest ?? "none" });
  }, [error]);

  return (
    <html lang="en">
      <body
        style={{
          margin: 0,
          minHeight: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#0B0B0C",
          color: "#F5F5F5",
          fontFamily:
            "Inter, system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
          padding: "24px",
        }}
      >
        <div style={{ maxWidth: 420, textAlign: "center" }}>
          <p
            style={{
              fontSize: 12,
              letterSpacing: "0.25em",
              textTransform: "uppercase",
              color: "#FF1A1A",
              margin: "0 0 12px",
            }}
          >
            Snatch It
          </p>
          <h1 style={{ fontSize: 22, fontWeight: 700, margin: "0 0 12px" }}>
            Something went wrong
          </h1>
          <p style={{ fontSize: 14, lineHeight: 1.6, color: "rgba(245,245,245,0.6)", margin: "0 0 24px" }}>
            We hit an unexpected error loading the page. Try again — if it keeps
            happening, please contact support.
          </p>
          <button
            onClick={reset}
            style={{
              background: "#FF1A1A",
              color: "#fff",
              border: "none",
              borderRadius: 0,
              padding: "12px 24px",
              fontSize: 14,
              fontWeight: 700,
              cursor: "pointer",
            }}
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
