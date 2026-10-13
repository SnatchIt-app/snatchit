"use client";

import { useState, useTransition } from "react";
import { useRouter, usePathname } from "next/navigation";
import { toggleSaveAction } from "@/lib/favorites-actions";
import { Icon } from "@/components/ui/Icon";
import { iconButtonClasses, buttonClasses } from "@/components/ui/Button";

function BookmarkIcon({ filled }: { filled: boolean }) {
  return <Icon name="bookmark" size={20} filled={filled} strokeWidth={1.9} />;
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
        className={iconButtonClasses("onArt", "disabled:opacity-60")}
      >
        <span className={saved ? "text-brand" : ""}>
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
      className={buttonClasses("secondary", "md", saved ? "!border-brand-text text-brand-text" : "")}
    >
      <BookmarkIcon filled={saved} />
      {label}
    </button>
  );
}
