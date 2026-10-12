"use client";

import { useEffect, useRef, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import { NAV } from "@/components/shell/Sidebar";

const CHORD_MS = 1000;
/** Per-viewer switch for the single-key shortcuts (WCAG 2.1.4). Only this browser remembers it. */
const OFF_KEY = "snatchit.console.shortcuts";

function shortcutsOff(): boolean {
  try {
    return window.localStorage.getItem(OFF_KEY) === "off";
  } catch {
    return false;
  }
}

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
      if (shortcutsOff()) return;
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

/** In the account menu: turns the single-key shortcuts (/ and g then a key) off or back on. */
const TOGGLED = "snatchit:shortcuts-toggled";
const subscribe = (cb: () => void) => {
  window.addEventListener("storage", cb);
  window.addEventListener(TOGGLED, cb);
  return () => {
    window.removeEventListener("storage", cb);
    window.removeEventListener(TOGGLED, cb);
  };
};

export function ShortcutToggle() {
  const off = useSyncExternalStore(subscribe, shortcutsOff, () => false);
  const toggle = () => {
    try {
      if (off) window.localStorage.removeItem(OFF_KEY);
      else window.localStorage.setItem(OFF_KEY, "off");
    } catch {
      /* storage blocked: nothing to remember the choice in */
    }
    window.dispatchEvent(new Event(TOGGLED));
  };
  return (
    <button type="button" onClick={toggle} aria-pressed={!off} className="btn btn-ghost btn-sm mt-3 w-full justify-between">
      <span>Single-key shortcuts</span>
      <span className="text-muted">{off ? "Off" : "On"}</span>
    </button>
  );
}
