import type { Metadata } from "next";
import { listMyNotifications } from "@/lib/notifications";
import { NotificationsList } from "@/components/account/NotificationsList";
import { AccountHeader } from "@/components/account/AccountHeader";
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
    return (
      <div>
        <AccountHeader title="Notifications" />
        <ErrorState title="Couldn't load your notifications" message="Refresh the page, or try again shortly." />
      </div>
    );
  }

  return (
    <div>
      <AccountHeader title="Notifications" />
      {notifications.length > 0 ? (
        <NotificationsList notifications={notifications} />
      ) : (
        <EmptyState
          icon="bell"
          title="No notifications yet"
          message="Updates on saved listings and your account will show up here."
        />
      )}
    </div>
  );
}
