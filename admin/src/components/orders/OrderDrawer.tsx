"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, type ReactNode } from "react";
import { Icon } from "@/components/ui/Icon";

/**
 * The order preview: slides in over the work queue so the queue stays in view
 * behind it. It is a URL state (?open=<payment id>), so it survives reload,
 * can be linked, and works without JavaScript; this wrapper only adds the
 * keyboard behaviour — focus moves into the drawer, Escape closes it, and
 * focus returns to the row that opened it.
 */
export function OrderDrawer({ id, closeHref, title, children }: { id: string; closeHref: string; title: string; children: ReactNode }) {
  const router = useRouter();
  const heading = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    heading.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      e.preventDefault();
      close();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  function close() {
    router.push(closeHref, { scroll: false });
    // Return focus to the row that opened the drawer — the visible one (the
    // phone card and the table row share the id; only one is displayed).
    let tries = 0;
    const back = () => {
      const target = Array.from(document.querySelectorAll<HTMLElement>(`[data-row-link="${CSS.escape(id)}"]`)).find((el) => el.offsetParent !== null);
      if (target && !document.getElementById("drawer-title")) target.focus();
      else if (tries++ < 20) window.setTimeout(back, 50);
    };
    window.setTimeout(back, 50);
  }

  return (
    <>
      <Link href={closeHref} scroll={false} aria-label="Close order preview" className="drawer-scrim fixed inset-0 z-40 bg-[rgba(28,25,23,0.18)]" tabIndex={-1} />
      <aside role="dialog" aria-modal="false" aria-labelledby="drawer-title" className="drawer glass glass-solid fixed inset-y-3 right-3 z-50 flex w-[min(30rem,calc(100vw-1.5rem))] flex-col rounded-[28px]">
        <div className="flex items-start justify-between gap-3 border-b border-line px-6 pb-4 pt-5">
          <div className="min-w-0">
            <p className="kicker">Order preview</p>
            <h2 id="drawer-title" ref={heading} tabIndex={-1} className="title-display mt-1 text-[1.5rem] outline-none">
              {title}
            </h2>
          </div>
          <button type="button" onClick={close} className="btn-icon" aria-label="Close order preview (Escape)">
            <Icon name="close" size={18} />
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-6 py-5">{children}</div>
      </aside>
    </>
  );
}
