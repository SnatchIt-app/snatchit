import type { Metadata } from "next";
import Link from "next/link";
import { getMyProfile } from "@/lib/profile";
import { savedListingsCount } from "@/lib/favorites";
import { unreadNotificationCount } from "@/lib/notifications";
import { getMyPurchases } from "@/lib/transfers";
import { getMySales } from "@/lib/sales";
import { Chip } from "@/components/ui/Badge";

export const metadata: Metadata = {
  title: "Your account",
  robots: { index: false, follow: true },
};

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
      <h1 className="font-display text-[clamp(1.9rem,4vw,2.6rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        {profile?.display_name || "Your account"}
      </h1>

      {profile ? (
        <div className="mt-6 flex flex-wrap items-center gap-x-6 gap-y-2 border-y border-primary/15 py-5 text-[13.5px]">
          <span className="text-white/70">{profile.email}</span>
          {profile.is_verified_buyer ? <Chip tone="red">Verified buyer</Chip> : null}
          {profile.is_verified_seller ? <Chip tone="red">Verified seller</Chip> : null}
        </div>
      ) : null}

      <div className="mt-9 grid grid-cols-2 gap-5 sm:grid-cols-4">
        <StatCard label="Saved" value={saved} href="/account/saved" />
        <StatCard label="Unread" value={unread} href="/account/notifications" />
        <StatCard label="Purchases" value={purchases.length} href="/account/purchases" />
        <StatCard label="Sales" value={sales.length} href="/account/sales" />
      </div>

    </div>
  );
}

function StatCard({
  label,
  value,
  href,
  note,
}: {
  label: string;
  value: string | number;
  href: string | null;
  note?: string;
}) {
  const inner = (
    <>
      <p className="font-display text-[32px] font-bold leading-none text-ink">{value}</p>
      <p className="mt-2 text-[10px] font-medium uppercase tracking-[0.25em] text-white/45">{label}</p>
      {note ? <p className="mt-2 text-[11.5px] leading-snug text-white/35">{note}</p> : null}
    </>
  );
  if (!href) {
    return <div className="border border-primary/15 bg-card p-5">{inner}</div>;
  }
  return (
    <Link href={href} className="block border border-primary/15 bg-card p-5 transition-colors duration-200 hover:border-primary/40 motion-reduce:transition-none">
      {inner}
    </Link>
  );
}
