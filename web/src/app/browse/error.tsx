"use client";

import { useEffect } from "react";
import { Container } from "@/components/ui/Container";
import { ErrorState } from "@/components/ui/ErrorState";
import { captureException } from "@/lib/observability";

export default function BrowseError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    captureException("browse", error, { digest: error.digest ?? "none" });
  }, [error]);

  return (
    <Container className="py-16">
      <ErrorState
        title="Couldn't load listings"
        message="The marketplace didn't answer in time. Give it another shot."
        onRetry={reset}
      />
    </Container>
  );
}
