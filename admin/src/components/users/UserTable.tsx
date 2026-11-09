import Link from "next/link";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import type { UserListItem } from "@/lib/types";

/** What the page filter matches on a user row (masked contact only — the console never sees raw email or phone). */
export function userFilterText(u: UserListItem): string {
  return [
    u.display_name,
    u.id,
    u.email_masked,
    u.is_verified_seller ? "verified" : "not verified",
    u.stripe_onboarding_complete ? "onboarding complete" : "onboarding incomplete",
    u.risk_tier,
    u.is_listing_blocked ? "listing creation blocked" : "listing creation allowed",
  ]
    .filter(Boolean)
    .join(" ");
}

export function UserTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
  filterable = false,
}: {
  rows: UserListItem[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  /** Client-side text filter over the rows on this page. */
  filterable?: boolean;
}) {
  const columns: Column<UserListItem>[] = [
    {
      key: "display_name",
      header: "User",
      render: (u) => (
        <span className="flex flex-col">
          {u.id ? (
            <Link href={`/users/${u.id}`} className="link font-medium">
              {u.display_name || u.id.slice(0, 8)}
            </Link>
          ) : (
            u.display_name ?? "—"
          )}
          <code className="font-mono text-[0.625rem] text-dim">{u.id}</code>
        </span>
      ),
      sortValue: (u) => u.display_name || u.id || null,
    },
    { key: "email", header: "Email (masked)", render: (u) => <span className="font-mono text-[0.75rem]">{u.email_masked ?? "—"}</span>, sortValue: (u) => u.email_masked ?? null },
    { key: "verified", header: "Verified seller", render: (u) => <StatusBadge status={String(u.is_verified_seller ?? false)} label={u.is_verified_seller ? "verified" : "no"} />, sortValue: (u) => u.is_verified_seller ?? false },
    {
      key: "onboarding",
      header: "Stripe onboarding",
      render: (u) => <StatusBadge status={String(u.stripe_onboarding_complete ?? false)} label={u.stripe_onboarding_complete ? "complete" : "incomplete"} />,
      sortValue: (u) => u.stripe_onboarding_complete ?? false,
    },
    { key: "listings", header: "Listings", align: "right", render: (u) => <span className="tabular-nums">{u.listing_count ?? 0}</span>, sortValue: (u) => u.listing_count ?? 0, firstSortDir: "desc" },
    { key: "risk", header: "Risk tier", render: (u) => (u.risk_tier ? <StatusBadge status={u.risk_tier} /> : <span className="text-dim">—</span>), sortValue: (u) => u.risk_tier ?? null },
    {
      key: "blocked",
      header: "Listing creation",
      render: (u) => <StatusBadge status={u.is_listing_blocked ? "held" : "active"} label={u.is_listing_blocked ? "blocked" : "allowed"} />,
      sortValue: (u) => u.is_listing_blocked ?? false,
    },
    { key: "open_cases", header: "Open cases", align: "right", render: (u) => <span className="tabular-nums">{u.open_cases ?? 0}</span>, sortValue: (u) => u.open_cases ?? 0, firstSortDir: "desc" },
    { key: "created_at", header: "Joined", render: (u) => <TimeAgo value={u.created_at} />, sortValue: (u) => u.created_at ?? null, firstSortDir: "desc" },
  ];
  return (
    <DataTable
      columns={columns}
      rows={rows}
      rowKey={(u, i) => u.id ?? `${i}`}
      basePath={basePath}
      searchParams={searchParams}
      nextCursor={nextCursor}
      emptyText="No users match."
      caption="Users"
      dense
      filterable={filterable}
      filterText={userFilterText}
    />
  );
}
