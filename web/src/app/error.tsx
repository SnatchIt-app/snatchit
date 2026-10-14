"use client";

import { useEffect } from "react";
import { Container } from "@/components/ui/Container";
import { ErrorState } from "@/components/ui/ErrorState";
import { captureException } from "@/lib/observability";

/**
 * Root error boundary. Catches anything thrown below the root layout that a
 * more specific boundary did not already handle — previously only /browse had
 * one, so a failure anywhere else showed Next's default error screen and was
 * reported nowhere.
 *
 * `retry` (Next 16) re-fetches and re-renders the segment; the older `reset`
 * only re-rendered, so a transient server failure stayed stuck on this screen.
 */
export default function RootError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  useEffect(() => {
    // digest is the only handle on the server-side stack, which Next redacts
    // from the client for security. Without it a production report is
    // untraceable back to the platform log.
    captureException("app/error", error, { digest: error.digest ?? "none" });
  }, [error]);

  return (
    <Container className="py-10 sm:py-16">
      <ErrorState
        as="h1"
        title="Something went wrong"
        message="We hit an unexpected error. Try again — if it keeps happening, please contact support."
        onRetry={retry}
      />
    </Container>
  );
}
