import type { Metadata } from "next";
import Link from "next/link";
import { getMyProfile } from "@/lib/profile";
import { savedListingsCount } from "@/lib/favorites";
import { unreadNotificationCount } from "@/lib/notifications";
import { getMyPurchases } from "@/lib/transfers";
import { getMySales } from "@/lib/sales";
import { Badge } from "@/components/ui/Badge";
import { ACCOUNT_GROUPS, ACCOUNT_OVERVIEW_HREF } from "@/components/account/sections";
import { AccountSection, SettingsRow, SettingsRows } from "@/components/account/SettingsRow";

export const metadata: Metadata = {
  title: "Your account",
  robots: { index: false, follow: true },
};

/** First letter of the name (or the email), for the initials avatar. */
function initialOf(name: string | null | undefined, email: string | null | undefined): string {
  const source = (name || email || "").trim();
  return source ? source[0]!.toUpperCase() : "?";
}

/**
 * The account hub — native "You" (identity, badges, figures) over the native
 * settings-hub rows: the way into every section on phones and tablets, and
 * the overview's three columns beside the sidebar on desktop.
 */
export default async function AccountOverviewPage() {
  const profile = await getMyProfile();
  const [saved, unread, purchases, sales] = await Promise.all([
    savedListingsCount(),
    unreadNotificationCount(),
    profile ? getMyPurchases(profile.id) : Promise.resolve([]),
    profile ? getMySales(profile.id) : Promise.resolve([]),
  ]);

  return (
    <div>
      <div className="flex items-center gap-4">
        <span
          aria-hidden="true"
          className="inline-flex size-14 shrink-0 items-center justify-center rounded-full bg-brand-soft text-[22px] font-bold text-brand-text lg:size-16 lg:text-[26px]"
        >
          {initialOf(profile?.display_name, profile?.email)}
        </span>
        <div className="min-w-0 flex-1">
          <h1 className="t-name-state break-words text-ink lg:t-name-feature">
            {profile?.display_name || "Your account"}
          </h1>
          {profile ? <p className="t-body-sm mt-0.5 wrap-anywhere text-muted">{profile.email}</p> : null}
        </div>
      </div>

      {profile && (profile.is_verified_buyer || profile.is_verified_seller) ? (
        <div className="mt-4 flex flex-wrap gap-2">
          {profile.is_verified_buyer ? <Badge tone="success">Verified buyer</Badge> : null}
          {profile.is_verified_seller ? <Badge tone="success">Verified seller</Badge> : null}
        </div>
      ) : null}

      <ul className="mt-7 grid grid-cols-2 border-t border-line sm:grid-cols-4 lg:mt-9">
        <Stat label="Saved" value={saved} href="/account/saved" />
        <Stat label="Unread" value={unread} href="/account/notifications" />
        <Stat label="Purchases" value={purchases.length} href="/account/purchases" />
        <Stat label="Sales" value={sales.length} href="/account/sales" />
      </ul>

      <div className="mt-8 space-y-8 lg:mt-12 lg:grid lg:grid-cols-3 lg:gap-8 lg:space-y-0">
        {ACCOUNT_GROUPS.map((group) => (
          <AccountSection key={group.label} title={group.label}>
            <SettingsRows>
              {group.links
                .filter((link) => link.href !== ACCOUNT_OVERVIEW_HREF)
                .map((link) => (
                  <SettingsRow
                    key={link.href}
                    href={link.href}
                    title={link.label}
                    unread={link.showsUnread && unread > 0}
                  />
                ))}
            </SettingsRows>
          </AccountSection>
        ))}
      </div>
    </div>
  );
}

/** One figure in the hub strip: the value in the price face, its micro label under it. */
function Stat({ label, value, href }: { label: string; value: string | number; href: string }) {
  return (
    <li className="border-b border-line">
      <Link href={href} className="pressable group block py-4 pr-3">
        <span className="t-price block text-[28px] leading-none text-ink group-hover:underline group-hover:decoration-2 group-hover:underline-offset-4">
          {value}
        </span>
        <span className="t-micro mt-2 block text-muted group-hover:text-ink-2">{label}</span>
      </Link>
    </li>
  );
}
