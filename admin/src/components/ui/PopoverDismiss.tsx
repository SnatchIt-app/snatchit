"use client";

import { useEffect } from "react";

/**
 * Popovers here are <details data-popover> — they open and close without
 * JavaScript. This adds what a person expects on top: Escape closes the open
 * one and returns focus to its toggle; a click outside closes it.
 */
export function PopoverDismiss() {
  useEffect(() => {
    const openOnes = () => Array.from(document.querySelectorAll<HTMLDetailsElement>("details[data-popover][open]"));
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      const open = openOnes();
      if (open.length === 0) return;
      const last = open[open.length - 1];
      last.open = false;
      last.querySelector<HTMLElement>(":scope > summary")?.focus();
    };
    const onClick = (e: MouseEvent) => {
      for (const d of openOnes()) if (!d.contains(e.target as Node)) d.open = false;
    };
    window.addEventListener("keydown", onKey);
    document.addEventListener("click", onClick);
    return () => {
      window.removeEventListener("keydown", onKey);
      document.removeEventListener("click", onClick);
    };
  }, []);
  return null;
}
