import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getMyListing } from "@/lib/seller-listings";
import { canEdit } from "@/lib/seller-listing-status";
import { EditListingForm } from "@/components/account/EditListingForm";
import { AccountHeader } from "@/components/account/AccountHeader";
import { Alert } from "@/components/ui/Alert";
import { LinkButton } from "@/components/ui/Button";

export const metadata: Metadata = {
  title: "Edit listing",
  robots: { index: false, follow: false },
};

export default async function EditListingPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  const user = await getAuthedUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(`/account/listings/${id}/edit`)}`);

  // getMyListing is already scoped to seller_id — another seller's listing
  // simply isn't found, so this doubles as the ownership check.
  const listing = await getMyListing(user.id, id);
  if (!listing) notFound();

  const editable = canEdit(listing.badge, listing.realBidCount);

  return (
    <div className="max-w-[560px]">
      {/* A pushed screen under Your listings: the back link stays on desktop too. */}
      <AccountHeader
        title="Edit listing"
        back={{ href: "/account/listings", label: "Your listings", text: "Your listings", desktop: true }}
      />

      {editable ? (
        <EditListingForm
          listingId={listing.id}
          eventName={listing.event_name}
          venue={listing.venue}
          restrictions={listing.restrictions ?? ""}
          ticketPlatform={listing.ticket_platform}
        />
      ) : (
        <div className="space-y-5">
          <Alert tone="error">
            {listing.realBidCount > 0
              ? "This listing already has bids, so its details are locked. Cancel it from Your listings if you need to pull it."
              : "This listing is no longer active, so it can't be edited."}
          </Alert>
          <LinkButton href="/account/listings" variant="secondary">
            Back to your listings
          </LinkButton>
        </div>
      )}
    </div>
  );
}
