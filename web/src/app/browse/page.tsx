import type { Metadata } from "next";
import { Suspense } from "react";
import {
  getActiveListings,
  type BrowseFilters,
  type BrowseSort,
} from "@/lib/listings";
import { CATEGORY_LABELS, NEIGHBORHOOD_LABELS } from "@snatchit/core";
import { Container } from "@/components/ui/Container";
import { EmptyState } from "@/components/ui/EmptyState";
import { LinkButton } from "@/components/ui/Button";
import { Skeleton } from "@/components/ui/Skeleton";
import { SearchForm } from "@/components/ui/SearchInput";
import { FeedRow } from "@/components/listing/FeedRow";
import { FilterControls } from "@/components/browse/FilterControls";
import { FiltersSheet } from "@/components/browse/FiltersSheet";
import { QuickChips } from "@/components/browse/QuickChips";

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

const SORT_LABEL: Record<BrowseSort, string> = {
  ending: "Ending soonest",
  newest: "Newest first",
  price_asc: "Lowest price first",
  price_desc: "Highest price first",
};

export default async function BrowsePage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const filters = parseFilters(sp);
  const listings = await getActiveListings(filters, 24);
  const now = new Date();
  const activeCount = [filters.category, filters.neighborhood, filters.type, filters.maxPrice].filter(Boolean).length;
  const scope = [
    filters.category ? (CATEGORY_LABELS as Record<string, string>)[filters.category] ?? filters.category : null,
    filters.neighborhood ? (NEIGHBORHOOD_LABELS as Record<string, string>)[filters.neighborhood] ?? filters.neighborhood : null,
  ].filter(Boolean);

  return (
    <Container className="pb-10 pt-6 lg:pb-14 lg:pt-10">
      <div className="mb-6 lg:mb-8">
        <h1 className="t-display-lg text-ink">Browse</h1>
        <p className="t-body mt-1.5 text-muted">
          {listings.length} live listing{listings.length === 1 ? "" : "s"} across Miami · every price includes fees
        </p>
      </div>

      <div className="grid gap-8 lg:grid-cols-[256px_minmax(0,1fr)] lg:gap-14">
        {/* Desktop filter rail */}
        <aside className="max-lg:hidden" aria-label="Filters">
          <div className="sticky top-24">
            <Suspense fallback={<Skeleton className="h-96" />}>
              <FilterControls idPrefix="rail" />
            </Suspense>
          </div>
        </aside>

        <div className="min-w-0">
          <SearchForm
            defaultValue={filters.q ?? ""}
            keep={{
              category: filters.category,
              neighborhood: filters.neighborhood,
              type: filters.type,
              max: filters.maxPrice ? String(filters.maxPrice) : undefined,
              sort: filters.sort === "ending" ? undefined : filters.sort,
            }}
          />
          <div className="-mx-5 mt-4 flex items-center gap-2 overflow-x-auto px-5 pb-1 [scrollbar-width:none] sm:-mx-8 sm:px-8 lg:hidden [&::-webkit-scrollbar]:hidden">
            <Suspense fallback={<Skeleton className="h-10 w-28 rounded-full" />}>
              <FiltersSheet activeCount={activeCount} />
              <QuickChips />
            </Suspense>
          </div>

          <div className="mt-6 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-line pb-2.5">
            <h2 className="t-section text-ink-2">
              {filters.q ? <>Results for &ldquo;{filters.q}&rdquo;</> : `${listings.length} listing${listings.length === 1 ? "" : "s"}`}
              {scope.length ? <span className="font-normal text-muted"> · {scope.join(" · ")}</span> : null}
            </h2>
            <p className="t-body-sm text-muted">{SORT_LABEL[filters.sort ?? "ending"]}</p>
          </div>

          {listings.length > 0 ? (
            <ul>
              {listings.map((l) => (
                <li key={l.id} className="border-b border-line last:border-b-0">
                  <FeedRow listing={l} now={now} />
                </li>
              ))}
            </ul>
          ) : (
            <EmptyState
              icon="search"
              title={filters.q ? `Nothing matches \u201c${filters.q}\u201d` : "Nothing matches those filters"}
              message="Try a wider neighborhood or price range, or clear the filters and browse everything."
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
