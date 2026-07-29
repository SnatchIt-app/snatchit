import type { Metadata } from "next";
import { listSavedListings } from "@/lib/favorites";
import { ListingCard } from "@/components/ListingCard";
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
    return <ErrorState title="Couldn't load your saved listings" message="Refresh the page, or try again shortly." />;
  }

  const withListing = saved.filter((row) => row.listing !== null);
  const missingCount = saved.length - withListing.length;

  return (
    <div>
      <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        Saved
      </h1>

      {withListing.length > 0 ? (
        <>
          <div className="mt-7 grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-3">
            {withListing.map((row) => (
              <ListingCard key={row.id} listing={row.listing!} isSaved />
            ))}
          </div>
          {missingCount > 0 ? (
            <p className="mt-6 text-[12.5px] text-white/40">
              {missingCount} saved listing{missingCount === 1 ? "" : "s"} no longer available.
            </p>
          ) : null}
        </>
      ) : (
        <div className="mt-7">
          <EmptyState
            title="Nothing saved yet"
            message="Tap the bookmark on any listing to save it here."
            action={<LinkButton href="/browse">Browse tickets</LinkButton>}
          />
        </div>
      )}
    </div>
  );
}
