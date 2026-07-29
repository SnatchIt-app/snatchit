import type { Metadata } from "next";
import { Suspense } from "react";
import {
  getActiveListings,
  type BrowseFilters,
  type BrowseSort,
} from "@/lib/listings";
import { Container } from "@/components/ui/Container";
import { EmptyState } from "@/components/ui/EmptyState";
import { LinkButton } from "@/components/ui/Button";
import { Skeleton } from "@/components/ui/Skeleton";
import { ListingCard } from "@/components/ListingCard";
import { FilterControls } from "@/components/browse/FilterControls";
import { FiltersSheet } from "@/components/browse/FiltersSheet";

export const metadata: Metadata = {
  title: "Browse Miami tickets",
  description:
    "Live ticket listings across Miami — clubs, festivals, arenas, and more. Bid or Buy Now with all-in pricing and buyer protection.",
  // Filtered/paginated variants canonicalize to the base browse page.
  alternates: { canonical: "/browse" },
};

type SearchParams = Record<string, string | string[] | undefined>;

function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

const SORTS: BrowseSort[] = ["ending", "newest", "price_asc", "price_desc"];

function parseFilters(sp: SearchParams): BrowseFilters {
  const sort = first(sp.sort);
  const type = first(sp.type);
  const max = Number(first(sp.max));
  return {
    q: first(sp.q)?.slice(0, 80) || undefined,
    category: first(sp.category) || undefined,
    neighborhood: first(sp.neighborhood) || undefined,
    type: type === "buy_now" || type === "auction" ? type : undefined,
    maxPrice: Number.isFinite(max) && max > 0 ? max : undefined,
    sort: SORTS.includes(sort as BrowseSort) ? (sort as BrowseSort) : "ending",
  };
}

export default async function BrowsePage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const filters = parseFilters(sp);
  const listings = await getActiveListings(filters, 24);
  const activeCount = [filters.q, filters.category, filters.neighborhood, filters.type, filters.maxPrice].filter(Boolean).length;

  return (
    <Container className="py-10 lg:py-14">
      <div className="mb-9">
        <h1 className="text-[clamp(1.9rem,4vw,2.6rem)] font-extrabold leading-none tracking-[-0.03em] text-ink">
          Browse tickets
        </h1>
        <p className="mt-3 text-[14.5px] font-medium text-muted">
          {listings.length} live listing{listings.length === 1 ? "" : "s"} across Miami · every
          price includes fees
        </p>
      </div>

      <div className="grid gap-10 lg:grid-cols-[264px_minmax(0,1fr)] lg:gap-12">
        {/* Desktop filter rail */}
        <aside className="hidden lg:block" aria-label="Filters">
          <div className="sticky top-28 rounded-[14px] border border-white/[0.07] bg-card p-5">
            <Suspense fallback={<Skeleton className="h-96" />}>
              <FilterControls idPrefix="rail" />
            </Suspense>
          </div>
        </aside>

        <div>
          {/* Mobile filter sheet */}
          <div className="mb-6 lg:hidden">
            <Suspense fallback={<Skeleton className="h-11" />}>
              <FiltersSheet activeCount={activeCount} />
            </Suspense>
          </div>

          {listings.length > 0 ? (
            <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-3">
              {listings.map((l, i) => (
                <ListingCard key={l.id} listing={l} priority={i < 3} />
              ))}
            </div>
          ) : (
            <EmptyState
              title="Nothing matches those filters"
              message="Try widening the neighborhood or price range — or clear everything and browse it all."
              action={
                <LinkButton href="/browse" variant="secondary">
                  Clear all filters
                </LinkButton>
              }
            />
          )}
        </div>
      </div>
    </Container>
  );
}
