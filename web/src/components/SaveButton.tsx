"use client";

import { useState, useTransition } from "react";
import { useRouter, usePathname } from "next/navigation";
import { toggleSaveAction } from "@/lib/favorites-actions";

function BookmarkIcon({ filled }: { filled: boolean }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 16 18" className="size-4">
      <path
        d="M2.5 1.5h11a1 1 0 0 1 1 1V16l-6.5-3.5L1.5 16V2.5a1 1 0 0 1 1-1Z"
        fill={filled ? "currentColor" : "none"}
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
    </svg>
  );
}

/**
 * Save/unsave toggle. `icon` variant overlays the top-right of a listing
 * card image (mirrors the status badge's top-left placement); `labeled`
 * variant is the listing-detail inline control.
 */
export function SaveButton({
  listingId,
  initialSaved,
  variant = "icon",
}: {
  listingId: string;
  initialSaved: boolean;
  variant?: "icon" | "labeled";
}) {
  const [saved, setSaved] = useState(initialSaved);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();
  const pathname = usePathname();

  function handleClick(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    const next = !saved;
    setSaved(next); // optimistic
    startTransition(async () => {
      const result = await toggleSaveAction(listingId, saved);
      if (result.error === "AUTH_REQUIRED") {
        router.push(`/login?next=${encodeURIComponent(pathname)}`);
        return;
      }
      if (result.error) {
        setSaved(saved); // revert
        return;
      }
      setSaved(result.saved);
    });
  }

  const label = saved ? "Saved" : "Save";

  if (variant === "icon") {
    return (
      <button
        type="button"
        onClick={handleClick}
        disabled={isPending}
        aria-pressed={saved}
        aria-label={saved ? "Remove from saved listings" : "Save listing"}
        className="flex size-9 items-center justify-center bg-black/85 text-white transition-colors duration-200 hover:text-primary disabled:opacity-60 motion-reduce:transition-none"
      >
        <span className={saved ? "text-primary" : ""}>
          <BookmarkIcon filled={saved} />
        </span>
      </button>
    );
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={isPending}
      aria-pressed={saved}
      className={`inline-flex min-h-11 items-center gap-2 text-[11px] font-medium uppercase tracking-[0.25em] transition-colors duration-200 disabled:opacity-60 motion-reduce:transition-none ${
        saved ? "text-primary" : "text-white/60 hover:text-primary"
      }`}
    >
      <BookmarkIcon filled={saved} />
      {label}
    </button>
  );
}
