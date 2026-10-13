import type { Metadata } from "next";
import { listSavedListings } from "@/lib/favorites";
import { ListingCard } from "@/components/ListingCard";
import { AccountHeader } from "@/components/account/AccountHeader";
import { EmptyState } from "@/components/ui/EmptyState";
import { ErrorState } from "@/components/ui/ErrorState";
import { LinkButton } from "@/components/ui/Button";

export const metadata: Metadata = {
  title: "Saved listings",
  robots: { index: false, follow: true },
};

export default async function SavedListingsPage() {
  let saved: Awaited<ReturnType<typeof listSavedListings>>;
  try {
    saved = await listSavedListings();
  } catch {
    return (
      <div>
        <AccountHeader title="Saved" />
        <ErrorState title="Couldn't load your saved listings" message="Refresh the page, or try again shortly." />
      </div>
    );
  }

  const withListing = saved.filter((row) => row.listing !== null);
  const missingCount = saved.length - withListing.length;

  return (
    <div>
      <AccountHeader title="Saved" />

      {withListing.length > 0 ? (
        <>
          <div className="grid grid-cols-1 gap-x-5 gap-y-8 sm:grid-cols-2 xl:grid-cols-3">
            {withListing.map((row) => (
              <ListingCard key={row.id} listing={row.listing!} isSaved />
            ))}
          </div>
          {missingCount > 0 ? (
            <p className="t-body-sm mt-8 border-t border-line pt-4 text-muted">
              {missingCount} saved listing{missingCount === 1 ? "" : "s"} no longer available.
            </p>
          ) : null}
        </>
      ) : (
        <EmptyState
          icon="bookmark"
          title="Nothing saved yet"
          message="Tap the bookmark on any listing to save it here."
          action={<LinkButton href="/browse">Browse tickets</LinkButton>}
        />
      )}
    </div>
  );
}
