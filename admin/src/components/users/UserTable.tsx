import Link from "next/link";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import type { UserListItem } from "@/lib/types";

export function UserTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
}: {
  rows: UserListItem[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
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
          <code className="font-mono text-[10px] text-dim">{u.id}</code>
        </span>
      ),
    },
    { key: "email", header: "Email (masked)", render: (u) => <span className="font-mono text-[12px]">{u.email_masked ?? "—"}</span> },
    { key: "verified", header: "Verified seller", render: (u) => <StatusBadge status={String(u.is_verified_seller ?? false)} label={u.is_verified_seller ? "verified" : "no"} /> },
    {
      key: "onboarding",
      header: "Stripe onboarding",
      render: (u) => <StatusBadge status={String(u.stripe_onboarding_complete ?? false)} label={u.stripe_onboarding_complete ? "complete" : "incomplete"} />,
    },
    { key: "listings", header: "Listings", align: "right", render: (u) => <span className="tabular-nums">{u.listing_count ?? 0}</span> },
    { key: "risk", header: "Risk tier", render: (u) => (u.risk_tier ? <StatusBadge status={u.risk_tier} /> : <span className="text-dim">—</span>) },
    {
      key: "blocked",
      header: "Listing creation",
      render: (u) => <StatusBadge status={u.is_listing_blocked ? "held" : "active"} label={u.is_listing_blocked ? "blocked" : "allowed"} />,
    },
    { key: "open_cases", header: "Open cases", align: "right", render: (u) => <span className="tabular-nums">{u.open_cases ?? 0}</span> },
    { key: "created_at", header: "Joined", render: (u) => <TimeAgo value={u.created_at} /> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(u, i) => u.id ?? `${i}`} basePath={basePath} searchParams={searchParams} nextCursor={nextCursor} emptyText="No users match." caption="Users" dense />;
}
