"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";
import { noteLocation } from "@/lib/nav-history";

/** Records each page this tab shows (pathname changes, including the first) for BackLink. */
export function NavTracker() {
  const pathname = usePathname();
  useEffect(() => {
    noteLocation(pathname);
  }, [pathname]);
  return null;
}
