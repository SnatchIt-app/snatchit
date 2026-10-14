import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { Container } from "@/components/ui/Container";
import { AccountNav } from "@/components/account/AccountNav";
import { getAuthedUser } from "@/lib/auth/session";
import { unreadNotificationCount } from "@/lib/notifications";

// proxy.ts already gates /account/*; this is a defensive second check so the
// layout never renders account data without a validated session.
export default async function AccountLayout({ children }: { children: ReactNode }) {
  const user = await getAuthedUser();
  if (!user) redirect("/login?next=%2Faccount");

  const unread = await unreadNotificationCount();

  // Desktop: the grouped sidebar on the left, the section on the right.
  // Phones and tablets have no strip — /account is the hub and every section
  // carries a back chip to it (AccountHeader).
  return (
    <Container className="pb-10 pt-5 sm:pt-8 lg:pb-14 lg:pt-10">
      <div className="lg:grid lg:grid-cols-[240px_minmax(0,1fr)] lg:gap-14">
        <div className="max-lg:hidden">
          <div className="sticky top-24">
            <AccountNav unreadCount={unread} />
          </div>
        </div>
        <div className="min-w-0">{children}</div>
      </div>
    </Container>
  );
}
