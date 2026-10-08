import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { isUuid } from "@/lib/routes";
import { toListPage, toOrderRows } from "@/lib/types";
import { PageHeader } from "@/components/ui/PageHeader";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";

export const metadata: Metadata = { title: "Transfer" };
export const dynamic = "force-dynamic";

/**
 * Transfers have no page of their own: the unified order page is keyed by
 * payment id. Resolve the owning payment via list_orders (uuid match on
 * transfers.id) and redirect; fall back to search when nothing matches.
 */
export default async function TransferRedirectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  await requireOperator();
  const res = await callOps<unknown>("list_orders", { p_filters: { q: id }, p_cursor: null, p_limit: 5 });
  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="Transfer" title={<code className="font-mono">{id}</code>} />
        <OpsFailureAlert failure={res} fn="list_orders" retryHref={`/transfers/${id}`} />
      </>
    );
  }
  const rows = toOrderRows(toListPage(res.data).items).filter((r) => r.transfer_id === id);
  if (rows.length === 1 && rows[0].payment_id) redirect(`/orders/${rows[0].payment_id}`);
  return (
    <>
      <PageHeader eyebrow="Transfer" title={<code className="font-mono">{id}</code>} />
      <Alert state="empty" title="No order carries this transfer id." retryHref={`/search?q=${encodeURIComponent(id)}`} retryLabel="Search instead" />
    </>
  );
}
