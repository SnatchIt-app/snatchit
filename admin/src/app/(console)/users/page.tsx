import type { Metadata } from "next";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { num, toListPage, toUserListItem, type UserListItem } from "@/lib/types";
import { cursorOf, first, limitOf, type SearchParams } from "@/lib/search-params";
import { PageHeader } from "@/components/ui/PageHeader";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { FilterField, FilterForm } from "@/components/ui/FilterField";
import { UserTable } from "@/components/users/UserTable";

export const metadata: Metadata = { title: "Users" };
export const dynamic = "force-dynamic";

export default async function UsersPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  await requireOperator();

  const q = (first(sp.q) ?? "").trim().slice(0, 200);
  const isSeller = first(sp.is_seller);
  const blocked = first(sp.blocked);
  const filters: Record<string, unknown> = {};
  if (q) filters.q = q;
  if (isSeller === "true" || isSeller === "false") filters.is_seller = isSeller === "true";
  if (blocked === "true" || blocked === "false") filters.blocked = blocked === "true";

  const res = await callOps<unknown>("list_users", { p_filters: filters, p_cursor: cursorOf(sp), p_limit: limitOf(sp) });
  const page = res.ok ? toListPage(res.data) : null;
  const rows: UserListItem[] = page ? page.items.map(toUserListItem).filter((u): u is UserListItem => u !== null) : [];
  const countHint = res.ok && typeof res.data === "object" && res.data !== null ? num((res.data as Record<string, unknown>).count_hint) : null;

  return (
    <>
      <PageHeader
        eyebrow="People"
        title="Users"
        description="Buyers and sellers. Contact details are masked by the database; the console never sees raw email or phone."
        meta={countHint !== null ? `${countHint.toLocaleString("en-US")} user${countHint === 1 ? "" : "s"}` : undefined}
      />
      <FilterForm action="/users">
        <FilterField label="Search" className="min-w-[260px]">
          <input name="q" defaultValue={q} placeholder="display name, user id, exact email or phone" className="field py-1.5 text-[13px]" />
        </FilterField>
        <FilterField label="Seller">
          <select name="is_seller" defaultValue={isSeller ?? ""} className="field min-w-[140px] py-1.5 text-[13px]">
            <option value="">Anyone</option>
            <option value="true">Sellers (onboarded or has listings)</option>
            <option value="false">Buyers only</option>
          </select>
        </FilterField>
        <FilterField label="Listing creation">
          <select name="blocked" defaultValue={blocked ?? ""} className="field min-w-[140px] py-1.5 text-[13px]">
            <option value="">Any</option>
            <option value="true">Blocked</option>
            <option value="false">Allowed</option>
          </select>
        </FilterField>
      </FilterForm>
      {!res.ok ? <OpsFailureAlert failure={res} fn="list_users" retryHref="/users" /> : <UserTable rows={rows} basePath="/users" searchParams={sp} nextCursor={page?.next_cursor} />}
    </>
  );
}
