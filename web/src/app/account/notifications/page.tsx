import type { Metadata } from "next";
import { listMyNotifications } from "@/lib/notifications";
import { NotificationsList } from "@/components/account/NotificationsList";
import { EmptyState } from "@/components/ui/EmptyState";
import { ErrorState } from "@/components/ui/ErrorState";

export const metadata: Metadata = {
  title: "Notifications",
  robots: { index: false, follow: true },
};

export default async function NotificationsPage() {
  let notifications: Awaited<ReturnType<typeof listMyNotifications>>;
  try {
    notifications = await listMyNotifications();
  } catch {
    return <ErrorState title="Couldn't load your notifications" message="Refresh the page, or try again shortly." />;
  }

  return (
    <div>
      <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        Notifications
      </h1>
      <div className="mt-7">
        {notifications.length > 0 ? (
          <NotificationsList notifications={notifications} />
        ) : (
          <EmptyState title="No notifications yet" message="Updates on saved listings and your account will show up here." />
        )}
      </div>
    </div>
  );
}
