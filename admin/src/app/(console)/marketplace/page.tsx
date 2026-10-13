import type { Metadata } from "next";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { num, toListPage, toListingSummary, type ListingSummary } from "@/lib/types";
import { cursorOf, first, limitOf, type SearchParams } from "@/lib/search-params";
import { PageHeader } from "@/components/ui/PageHeader";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { FilterField, FilterForm, FilterSelect } from "@/components/ui/FilterField";
import { ListingTable } from "@/components/marketplace/ListingTable";

export const metadata: Metadata = { title: "Marketplace" };
export const dynamic = "force-dynamic";

const LISTING_STATUSES = ["active", "sold", "expired", "cancelled", "draft", "reserved"];
const AUCTION_STATUSES = ["active", "ended", "sold", "cancelled", "expired"];

export default async function MarketplacePage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  await requireOperator();

  const status = first(sp.status);
  const auctionStatus = first(sp.auction_status);
  const hasReports = first(sp.has_reports);
  const sellerId = first(sp.seller_id);
  const q = (first(sp.q) ?? "").trim().slice(0, 200);

  const filters: Record<string, unknown> = {};
  if (status) filters.status = status;
  if (auctionStatus) filters.auction_status = auctionStatus;
  if (hasReports === "true" || hasReports === "false") filters.has_reports = hasReports === "true";
  if (sellerId && /^[0-9a-f-]{36}$/i.test(sellerId)) filters.seller_id = sellerId;
  if (q) filters.q = q;

  const res = await callOps<unknown>("list_listings", { p_filters: filters, p_cursor: cursorOf(sp), p_limit: limitOf(sp) });
  const page = res.ok ? toListPage(res.data) : null;
  const rows: ListingSummary[] = page ? page.items.map(toListingSummary).filter((l): l is ListingSummary => l !== null) : [];
  const countHint = res.ok && typeof res.data === "object" && res.data !== null ? num((res.data as Record<string, unknown>).count_hint) : null;

  return (
    <>
      <PageHeader
        eyebrow="Listings"
        title="Marketplace"
        description="Listings and their moderation state. Prices and fees are shown as recorded and are never edited from the console."
        meta={countHint !== null ? `${countHint.toLocaleString("en-US")} listing${countHint === 1 ? "" : "s"}` : undefined}
      />
      <FilterForm action="/marketplace" sticky={{ seller_id: sellerId }}>
        <FilterField label="Status">
          <FilterSelect name="status" options={LISTING_STATUSES} value={status} />
        </FilterField>
        <FilterField label="Auction status">
          <FilterSelect name="auction_status" options={AUCTION_STATUSES} value={auctionStatus} />
        </FilterField>
        <FilterField label="Reports">
          <select name="has_reports" defaultValue={hasReports ?? ""} className="field min-w-[120px] py-1.5 text-[13px]">
            <option value="">Any</option>
            <option value="true">Reported</option>
            <option value="false">Not reported</option>
          </select>
        </FilterField>
        <FilterField label="Search" className="min-w-[220px]">
          <input name="q" defaultValue={q} placeholder="listing id or event name" className="field py-1.5 text-[13px]" />
        </FilterField>
      </FilterForm>
      {!res.ok ? <OpsFailureAlert failure={res} fn="list_listings" retryHref="/marketplace" /> : <ListingTable rows={rows} basePath="/marketplace" searchParams={sp} nextCursor={page?.next_cursor} />}
    </>
  );
}
