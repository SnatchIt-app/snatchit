"use client";

import { useState, useTransition } from "react";
import { useRouter, usePathname } from "next/navigation";
import { reserveBuyNowAction } from "@/lib/checkout-actions";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { loginHrefFor } from "@/lib/auth/login-href";

export function BuyNowButton({ listingId }: { listingId: string }) {
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();
  const pathname = usePathname();

  function handleClick() {
    setError(null);
    startTransition(async () => {
      const result = await reserveBuyNowAction(listingId);
      if (result.error === "AUTH_REQUIRED") {
        router.push(loginHrefFor(pathname, window.location.search));
        return;
      }
      if (result.error) {
        setError(result.error);
        return;
      }
      router.push(`/checkout/${listingId}`);
    });
  }

  return (
    <div className="space-y-2.5">
      {error ? <Alert tone="error">{error}</Alert> : null}
      <Button variant="primary" size="lg" className="w-full" onClick={handleClick} pending={isPending} pendingLabel="Reserving…" disabled={isPending}>
        Buy now
      </Button>
    </div>
  );
}
