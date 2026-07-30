"use client";

import { useState, useTransition } from "react";
import { useRouter, usePathname } from "next/navigation";
import { reserveBuyNowAction } from "@/lib/checkout-actions";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";

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
        router.push(`/login?next=${encodeURIComponent(pathname)}`);
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
      <Button variant="primary" className="w-full" onClick={handleClick} disabled={isPending}>
        {isPending ? "Reserving…" : "Buy now"}
      </Button>
    </div>
  );
}
