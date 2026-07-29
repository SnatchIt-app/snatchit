"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import {
  markAllNotificationsReadAction,
  markNotificationReadAction,
} from "@/lib/notifications-actions";
import type { AppNotification } from "@/lib/notifications";
import { UnreadDot } from "@/components/ui/Badge";
import { safeInternalPath } from "@/lib/auth/redirect";

function timeAgo(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const min = Math.floor(ms / 60_000);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m ago`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const days = Math.floor(hr / 24);
  return `${days}d ago`;
}

export function NotificationsList({ notifications }: { notifications: AppNotification[] }) {
  const [items, setItems] = useState(notifications);
  const [, startTransition] = useTransition();
  const unreadCount = items.filter((n) => !n.read_at).length;

  function markReadLocal(id: string) {
    setItems((prev) => prev.map((n) => (n.id === id ? { ...n, read_at: n.read_at ?? new Date().toISOString() } : n)));
    startTransition(() => {
      markNotificationReadAction(id);
    });
  }

  function markAllReadLocal() {
    const now = new Date().toISOString();
    setItems((prev) => prev.map((n) => ({ ...n, read_at: n.read_at ?? now })));
    startTransition(() => {
      markAllNotificationsReadAction();
    });
  }

  return (
    <div>
      {unreadCount > 0 ? (
        <div className="mb-5 flex justify-end">
          <button
            type="button"
            onClick={markAllReadLocal}
            className="inline-flex min-h-11 items-center text-[11px] font-medium uppercase tracking-[0.25em] text-primary hover:text-[#ff5f5f]"
          >
            Mark all as read
          </button>
        </div>
      ) : null}

      <ul className="divide-y divide-primary/15 border-y border-primary/15">
        {items.map((n) => {
          const unread = !n.read_at;
          const content = (
            <>
              <div className="flex items-start gap-3">
                {unread ? <span className="mt-1.5"><UnreadDot /></span> : <span className="mt-1.5 size-[7px] shrink-0" />}
                <div className="min-w-0 flex-1">
                  <p className={`text-[14.5px] leading-snug ${unread ? "font-bold text-ink" : "font-medium text-white/70"}`}>
                    {n.title}
                  </p>
                  {n.body ? <p className="mt-1 text-[13px] leading-relaxed text-white/50">{n.body}</p> : null}
                  <p className="mt-1.5 text-[11px] uppercase tracking-[0.2em] text-white/35">{timeAgo(n.created_at)}</p>
                </div>
              </div>
            </>
          );

          if (n.link) {
            return (
              <li key={n.id}>
                <Link
                  href={safeInternalPath(n.link, "/account/notifications")}
                  onClick={() => unread && markReadLocal(n.id)}
                  className="block py-4 transition-colors duration-200 hover:bg-white/[0.03] motion-reduce:transition-none"
                >
                  {content}
                </Link>
              </li>
            );
          }

          return (
            <li key={n.id} className="py-4">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 flex-1">{content}</div>
                {unread ? (
                  <button
                    type="button"
                    onClick={() => markReadLocal(n.id)}
                    className="shrink-0 text-[10.5px] font-medium uppercase tracking-[0.2em] text-white/45 hover:text-primary"
                  >
                    Mark read
                  </button>
                ) : null}
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
