import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getMyListings } from "@/lib/seller-listings";
import { SellerListings } from "@/components/account/SellerListings";
import { AccountHeader } from "@/components/account/AccountHeader";
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
    <div>
      <AccountHeader
        title="Your listings"
        action={
          <LinkButton href="/sell" size="md">
            List a ticket
          </LinkButton>
        }
      />
      <SellerListings listings={listings} />
    </div>
  );
}
