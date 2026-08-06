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
 */
export default function RootError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // digest is the only handle on the server-side stack, which Next redacts
    // from the client for security. Without it a production report is
    // untraceable back to the platform log.
    captureException("app/error", error, { digest: error.digest ?? "none" });
  }, [error]);

  return (
    <Container className="py-16">
      <ErrorState
        title="Something went wrong"
        message="We hit an unexpected error. Try again — if it keeps happening, please contact support."
        onRetry={reset}
      />
    </Container>
  );
}
