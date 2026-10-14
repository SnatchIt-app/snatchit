"use client";

import { useSyncExternalStore } from "react";
import { Icon } from "@/components/ui/Icon";

function subscribe(cb: () => void) {
  window.addEventListener("online", cb);
  window.addEventListener("offline", cb);
  return () => {
    window.removeEventListener("online", cb);
    window.removeEventListener("offline", cb);
  };
}

/**
 * Native StateView "offline" copy, as a floating notice: shown only while the
 * browser reports no connection, so nothing on the page is presented as fresh
 * when it may not be.
 */
export function OfflineNotice() {
  const online = useSyncExternalStore(subscribe, () => navigator.onLine, () => true);
  if (online) return null;
  return (
    <div role="status" className="pointer-events-none fixed inset-x-0 top-20 z-50 flex justify-center px-4">
      <p className="glass pointer-events-auto flex items-center gap-2.5 rounded-full px-4 py-2.5 text-[14px] font-medium text-ink shadow-[var(--sn-shadow-float)]">
        <Icon name="offline" size={18} className="text-warning" />
        You&apos;re offline. Check your internet connection and try again.
      </p>
    </div>
  );
}
