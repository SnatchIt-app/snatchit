"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, type KeyboardEvent, type ReactNode } from "react";

/**
 * Keyboard behaviour for the cases split view. The view itself is plain URL
 * state (?open=<case id>) rendered on the server, so it works without
 * JavaScript; this wrapper only adds:
 *
 *   ↑ / ↓ (or k / j), Home, End — move between cases in the queue
 *   Enter                      — open the focused case (it is a link)
 *   Escape                     — close the case and return focus to its row
 *
 * When a case opens, focus moves to its heading so a screen reader announces it.
 */
export function CaseSplit({ openId, closeHref, children }: { openId: string | null; closeHref: string; children: ReactNode }) {
  const router = useRouter();
  const root = useRef<HTMLDivElement>(null);

  const rowLinks = () => Array.from(root.current?.querySelectorAll<HTMLElement>("[data-case-link]") ?? []).filter((el) => el.offsetParent !== null);

  useEffect(() => {
    if (!openId) return;
    document.getElementById("case-pane-title")?.focus();
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key !== "Escape" || e.defaultPrevented) return;
      const t = e.target as HTMLElement | null;
      // Escape inside an open disclosure or a field belongs to that control.
      if (t?.closest("details[open] form") || t?.matches("input, textarea, select")) return;
      e.preventDefault();
      router.push(closeHref, { scroll: false });
      let tries = 0;
      const back = () => {
        const row = rowLinks().find((el) => el.dataset.caseLink === openId);
        if (row && !document.getElementById("case-pane-title")) row.focus();
        else if (tries++ < 80) window.setTimeout(back, 50);
      };
      window.setTimeout(back, 50);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [openId, closeHref]);

  function onListKey(e: KeyboardEvent<HTMLDivElement>) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const links = rowLinks();
    const i = links.indexOf(document.activeElement as HTMLElement);
    if (i < 0) return;
    let next = -1;
    if (e.key === "ArrowDown" || e.key === "j") next = Math.min(links.length - 1, i + 1);
    else if (e.key === "ArrowUp" || e.key === "k") next = Math.max(0, i - 1);
    else if (e.key === "Home") next = 0;
    else if (e.key === "End") next = links.length - 1;
    if (next < 0) return;
    e.preventDefault();
    links[next].focus();
  }

  return (
    <div ref={root} onKeyDown={onListKey}>
      {children}
    </div>
  );
}
