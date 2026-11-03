import { PageHeader } from "@/components/ui/PageHeader";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { DataTable } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { RESTRICTED_VIEW_TITLE, TestRecordBadge } from "@/components/ui/HiddenTestRowsNotice";
import { requireOperator } from "@/lib/auth/session";
import { callOps } from "@/lib/ops";
import { toCase, toListPage, toListingSummary, toOrderRow, toReport, type ListingSummary, type OpsCase, type OrderRow, type Report } from "@/lib/types";
import { DateTime } from "@/components/ui/DateTime";

export const dynamic = "force-dynamic";
export const metadata = { title: RESTRICTED_VIEW_TITLE };

/**
 * The restricted historical view (DC-1 spec §3; owner decision 2026-10-22 §F):
 * the ONE place in the console that passes `p_include_test = true`. Every
 * other table, chart and search calls the readers with the default and never
 * sees a test row. Read-only; the server still gates it (`ops.assert_reader`,
 * platform_admin + aal2). Rows are badged from the server's `is_test`; nothing
 * is classified here.
 */
const LIMIT = 50;

export default async function TestDataPage() {
  await requireOperator();
  const [cases, orders, listings, reports] = await Promise.all([
    callOps<unknown>("list_cases", { p_filters: {}, p_cursor: null, p_limit: LIMIT, p_include_test: true }),
    callOps<unknown>("list_orders", { p_filters: {}, p_cursor: null, p_limit: LIMIT, p_include_test: true }),
    callOps<unknown>("list_listings", { p_filters: {}, p_cursor: null, p_limit: LIMIT, p_include_test: true }),
    callOps<unknown>("list_reports", { p_filters: {}, p_cursor: null, p_limit: LIMIT, p_include_test: true }),
  ]);
  const caseRows = cases.ok ? (toListPage(cases.data).items.map(toCase).filter((c): c is OpsCase => c !== null) as OpsCase[]) : [];
  const orderRows = orders.ok ? (toListPage(orders.data).items.map(toOrderRow).filter((o): o is OrderRow => o !== null) as OrderRow[]) : [];
  const listingRows = listings.ok ? (toListPage(listings.data).items.map(toListingSummary).filter((l): l is ListingSummary => l !== null) as ListingSummary[]) : [];
  const reportRows = reports.ok ? (toListPage(reports.data).items.map(toReport).filter((r): r is Report => r !== null) as Report[]) : [];
  const classified = [...caseRows, ...orderRows, ...listingRows, ...reportRows].some((r) => r.is_test === true || r.is_test === false);
  const sp = {};

  /**
   * DC-2 fail-closed. Production's readers are `(p_filters, p_cursor, p_limit)` only — registry 180,
   * which adds `p_include_test`, is NOT applied there. PostgREST answers PGRST202 for the four-argument
   * call, which `mapOpsError` marks `unavailable`.
   *
   * ANY of the four refusing closes the whole page, not just its own section. A partial view would be
   * read as "the rest of the rows ARE classified", which is the one claim this page must never make when
   * it cannot stand behind it. So: no tables, no badges, no classification sentence — a named state that
   * says which migration is missing.
   */
  const needsRegistry180 = [cases, orders, listings, reports].some((r) => !r.ok && r.kind === "error" && r.unavailable === true);
  if (needsRegistry180) {
    return (
      <>
        <PageHeader
          eyebrow="System"
          title={RESTRICTED_VIEW_TITLE}
          description="This view asks the server to include test records. This server does not support that yet, so nothing is listed here."
          meta="Needs registry 180."
        />
        <Alert state="info" title="Needs registry 180 — the readers on this server cannot include test records.">
          <p>
            The console asked this server for cases, orders, listings and reports, test records included. This server does not
            support that request yet, so it refused it.
          </p>
          <p className="mt-2">
            <strong>No rows are shown and nothing has been classified.</strong> This is not an outage. Other screens do not ask for test records, so this refusal does not affect them.
            Applying registry 180 enables this view.
          </p>
        </Alert>
      </>
    );
  }
  return (
    <>
      <PageHeader
        eyebrow="System"
        title={RESTRICTED_VIEW_TITLE}
        description="Every row the readers return with test records included, badged by the server's own classification. Read-only. Nothing here is hidden from the audit log or the detail pages; the ordinary views exclude the badged rows."
        meta={classified ? "The server classifies rows." : "No row below has a classification from the server."}
      />
      <section aria-labelledby="td-cases" className="mb-8">
        <h2 id="td-cases" className="mb-2 title-section">Cases</h2>
        {!cases.ok ? (
          <OpsFailureAlert failure={cases} fn="list_cases" retryHref="/system/test-data" subject="Cases" />
        ) : (
          <DataTable
            id="td-cases-table"
            columns={[
              { key: "id", header: "Case", render: (c: OpsCase) => <code className="font-mono">{(c.id ?? "").slice(0, 8)}</code> },
              { key: "case_type", header: "Type", render: (c: OpsCase) => c.case_type ?? "—" },
              { key: "status", header: "Status", render: (c: OpsCase) => <StatusBadge status={c.status} /> },
              { key: "is_test", header: "Classification", render: (c: OpsCase) => (c.is_test === true ? <TestRecordBadge isTest /> : c.is_test === false ? "Real" : "Not classified") },
              { key: "created_at", header: "Created", render: (c: OpsCase) => <DateTime value={c.created_at ?? null} /> },
            ]}
            rows={caseRows}
            rowKey={(c, i) => c.id ?? `${i}`}
            basePath="/system/test-data"
            searchParams={sp}
            emptyText="No cases."
            dense
          />
        )}
      </section>
      <section aria-labelledby="td-orders" className="mb-8">
        <h2 id="td-orders" className="mb-2 title-section">Orders</h2>
        {!orders.ok ? (
          <OpsFailureAlert failure={orders} fn="list_orders" retryHref="/system/test-data" subject="Orders" />
        ) : (
          <DataTable
            id="td-orders-table"
            columns={[
              { key: "payment_id", header: "Payment", render: (o: OrderRow) => <code className="font-mono">{(o.payment_id ?? "").slice(0, 8)}</code> },
              { key: "payment_status", header: "Status", render: (o: OrderRow) => <StatusBadge status={o.payment_status} /> },
              { key: "stripe_livemode", header: "Stripe mode", render: (o: OrderRow) => (o.stripe_livemode === true ? "live" : o.stripe_livemode === false ? "test" : "unknown") },
              { key: "is_test", header: "Classification", render: (o: OrderRow) => (o.is_test === true ? <TestRecordBadge isTest /> : o.is_test === false ? "Real" : "Not classified") },
              { key: "created_at", header: "Created", render: (o: OrderRow) => <DateTime value={o.created_at ?? null} /> },
            ]}
            rows={orderRows}
            rowKey={(o, i) => o.payment_id ?? `${i}`}
            basePath="/system/test-data"
            searchParams={sp}
            emptyText="No orders."
            dense
          />
        )}
      </section>
      <section aria-labelledby="td-listings" className="mb-8">
        <h2 id="td-listings" className="mb-2 title-section">Listings</h2>
        {!listings.ok ? (
          <OpsFailureAlert failure={listings} fn="list_listings" retryHref="/system/test-data" subject="Listings" />
        ) : (
          <DataTable
            id="td-listings-table"
            columns={[
              { key: "id", header: "Listing", render: (l: ListingSummary) => <code className="font-mono">{(l.id ?? "").slice(0, 8)}</code> },
              { key: "event_name", header: "Event", render: (l: ListingSummary) => l.event_name ?? "—" },
              { key: "status", header: "Status", render: (l: ListingSummary) => <StatusBadge status={l.status} /> },
              { key: "is_test", header: "Classification", render: (l: ListingSummary) => (l.is_test === true ? <TestRecordBadge isTest /> : l.is_test === false ? "Real" : "Not classified") },
            ]}
            rows={listingRows}
            rowKey={(l, i) => l.id ?? `${i}`}
            basePath="/system/test-data"
            searchParams={sp}
            emptyText="No listings."
            dense
          />
        )}
      </section>
      <section aria-labelledby="td-reports" className="mb-8">
        <h2 id="td-reports" className="mb-2 title-section">Reports</h2>
        {!reports.ok ? (
          <OpsFailureAlert failure={reports} fn="list_reports" retryHref="/system/test-data" subject="Reports" />
        ) : (
          <DataTable
            id="td-reports-table"
            columns={[
              { key: "id", header: "Report", render: (r: Report) => <code className="font-mono">{(r.id ?? "").slice(0, 8)}</code> },
              { key: "target_type", header: "Target", render: (r: Report) => `${r.target_type ?? "—"} ${r.target_label ?? ""}`.trim() },
              { key: "status", header: "Status", render: (r: Report) => <StatusBadge status={r.status} /> },
              { key: "is_test", header: "Classification", render: (r: Report) => (r.is_test === true ? <TestRecordBadge isTest /> : r.is_test === false ? "Real" : "Not classified") },
            ]}
            rows={reportRows}
            rowKey={(r, i) => r.id ?? `${i}`}
            basePath="/system/test-data"
            searchParams={sp}
            emptyText="No reports."
            dense
          />
        )}
      </section>
    </>
  );
}
