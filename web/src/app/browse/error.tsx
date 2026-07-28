"use client";

import { useEffect } from "react";
import { Container } from "@/components/ui/Container";
import { ErrorState } from "@/components/ui/ErrorState";

export default function BrowseError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[browse]", error);
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
