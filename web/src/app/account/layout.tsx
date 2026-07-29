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

  return (
    <Container className="py-10 lg:py-14">
      <p className="eyebrow text-primary/80">Account</p>
      <div className="mt-6">
        <AccountNav unreadCount={unread} />
      </div>
      <div className="mt-9">{children}</div>
    </Container>
  );
}
