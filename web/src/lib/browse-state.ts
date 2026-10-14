import type { BrowseFilters } from "@/lib/listings";

/** Whether the feed was narrowed (a search or any filter). A sort order alone narrows nothing. */
export function isNarrowed(f: BrowseFilters): boolean {
  return Boolean(f.q || f.category || f.neighborhood || f.type || f.maxPrice);
}
