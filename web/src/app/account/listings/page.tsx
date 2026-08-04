import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getMyListings } from "@/lib/seller-listings";
import { SellerListings } from "@/components/account/SellerListings";
import { LinkButton } from "@/components/ui/Button";

export const metadata: Metadata = {
  title: "Your listings",
  robots: { index: false, follow: false },
};

export default async function AccountListingsPage() {
  const user = await getAuthedUser();
  if (!user) redirect("/login?next=%2Faccount%2Flistings");

  const listings = await getMyListings(user.id);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
          Your listings
        </h1>
        <LinkButton href="/sell" size="md">
          List a ticket
        </LinkButton>
      </div>
      <SellerListings listings={listings} />
    </div>
  );
}
