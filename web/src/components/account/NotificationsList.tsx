"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import {
  markAllNotificationsReadAction,
  markNotificationReadAction,
} from "@/lib/notifications-actions";
import type { AppNotification } from "@/lib/notifications";
import { UnreadDot } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Icon } from "@/components/ui/Icon";
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
        <div className="-mt-2 mb-3 flex justify-end">
          <Button variant="ghost" size="sm" onClick={markAllReadLocal}>
            Mark all as read
          </Button>
        </div>
      ) : null}

      <ul className="border-t border-line">
        {items.map((n) => {
          const unread = !n.read_at;
          const content = (
            <div className="flex items-start gap-3">
              <span className="flex h-[22px] w-2 shrink-0 items-center">{unread ? <UnreadDot /> : null}</span>
              <div className="min-w-0 flex-1">
                <p className={`text-[15px] leading-snug break-words ${unread ? "font-semibold text-ink" : "font-medium text-ink-2"}`}>
                  {n.title}
                </p>
                {n.body ? <p className="t-body-sm mt-1 break-words text-muted">{n.body}</p> : null}
                <p className="mt-1.5 text-[12px] text-muted">{timeAgo(n.created_at)}</p>
              </div>
            </div>
          );

          if (n.link) {
            return (
              <li key={n.id} className="border-b border-line">
                <Link
                  href={safeInternalPath(n.link, "/account/notifications")}
                  onClick={() => unread && markReadLocal(n.id)}
                  className="group -mx-3 flex items-center gap-3 rounded-panel px-3 py-4 transition-colors hover:bg-surface"
                >
                  <div className="min-w-0 flex-1">{content}</div>
                  <Icon name="chevronRight" size={18} strokeWidth={2} className="text-faint group-hover:text-muted" />
                </Link>
              </li>
            );
          }

          return (
            <li key={n.id} className="border-b border-line py-4">
              <div className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
                <div className="min-w-0 grow basis-48">{content}</div>
                {unread ? (
                  <Button variant="ghost" size="sm" className="-my-1" onClick={() => markReadLocal(n.id)}>
                    Mark read
                  </Button>
                ) : null}
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
