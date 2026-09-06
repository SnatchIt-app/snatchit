"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { NAV } from "@/components/shell/Sidebar";

const CHORD_MS = 1000;

function isTypingTarget(el: EventTarget | null): boolean {
  if (!(el instanceof HTMLElement)) return false;
  const tag = el.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
}

/**
 * `/` focuses the global search; `g` then a section key navigates. Nothing
 * fires while typing in a field; single-key chords time out after a second.
 */
export function KeyboardShortcuts() {
  const router = useRouter();
  const pendingG = useRef<number | null>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (isTypingTarget(e.target)) return;

      if (e.key === "/") {
        e.preventDefault();
        const box = document.getElementById("global-search") as HTMLInputElement | null;
        box?.focus();
        box?.select();
        return;
      }

      if (pendingG.current !== null) {
        window.clearTimeout(pendingG.current);
        pendingG.current = null;
        const target = NAV.find((n) => n.key === e.key.toLowerCase());
        if (target) {
          e.preventDefault();
          router.push(target.href);
        }
        return;
      }

      if (e.key === "g") {
        pendingG.current = window.setTimeout(() => {
          pendingG.current = null;
        }, CHORD_MS);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router]);

  return null;
}
