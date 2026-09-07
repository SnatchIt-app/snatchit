import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { newIdempotencyKey } from "@/lib/idempotency";
import { isUuid } from "@/lib/routes";
import { canRequest } from "@/lib/permissions";
import { labelFor, shortId } from "@/lib/format";
import { SUPABASE_URL } from "@/lib/env";
import { evidenceItems, str, toListingDetail, type Bid, type JsonRecord, type Report } from "@/lib/types";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { KeyValue } from "@/components/ui/KeyValue";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime } from "@/components/ui/DateTime";
import { Money } from "@/components/ui/Money";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { ConfirmForm } from "@/components/ui/ConfirmForm";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { IdLink, PartyLink } from "@/components/ui/IdLink";
import { EvidenceList } from "@/components/ui/EvidenceLink";
import { OrderTable } from "@/components/orders/OrderTable";
import { CaseTable } from "@/components/cases/CaseTable";
import { NewCaseForm } from "@/components/cases/NewCaseForm";
import { ActionTable } from "@/components/actions/ActionTable";
import { ReportResolveForms } from "@/components/reports/ReportResolveForms";

export const metadata: Metadata = { title: "Listing" };
export const dynamic = "force-dynamic";

export default async function ListingPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const me = await requireOperator();
  const path = `/marketplace/${id}`;

  const res = await callOps<unknown>("listing_detail", { p_listing_id: id });
  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="Listing" title={<code className="font-mono">{shortId(id)}</code>} />
        {res.kind === "error" && res.message.toLowerCase().includes("not_found") ? (
          <Alert state="empty" title="No listing with this id." retryHref="/marketplace" retryLabel="Back to marketplace" />
        ) : (
          <OpsFailureAlert failure={res} fn="listing_detail" retryHref={path} />
        )}
      </>
    );
  }
  const d = toListingDetail(res.data);
  if (!d || !d.listing) {
    return (
      <>
        <PageHeader eyebrow="Listing" title={<code className="font-mono">{shortId(id)}</code>} />
        <Alert state="failed" title="Unrecognised payload from ops.listing_detail()" retryHref={path} />
      </>
    );
  }
  const l = d.listing;
  const raw = l.raw;
  const canRelist = l.status === "active" && l.auction_status === "cancelled";
  const transacted = d.payments.some((p) => p.payment_status === "succeeded" || p.payment_status === "refunded");
  const openReports = d.reports.filter((r) => r.status !== "actioned" && r.status !== "dismissed");

  return (
    <>
      <PageHeader
        eyebrow={
          <>
            <Link href="/marketplace" className="hover:text-ink">
              Marketplace
            </Link>{" "}
            / listing {shortId(id)}
          </>
        }
        title={l.event_name ?? "Listing"}
        description={[l.venue, l.neighborhood, l.event_date, l.event_time, l.ticket_type, l.quantity ? `×${l.quantity}` : null, l.category, l.ticket_platform].filter(Boolean).join(" · ")}
        meta={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status={l.status} label={`status: ${l.status ?? "—"}`} />
            <StatusBadge status={l.auction_status} label={`auction: ${l.auction_status ?? "—"}`} />
            <StatusBadge status={l.proof_status} label={`proof: ${l.proof_status ?? "—"}`} />
            <span className="font-mono">
              <code>{id}</code>
            </span>
          </span>
        }
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Panel eyebrow="As recorded — read only" title="Listing">
            <KeyValue
              columns={3}
              items={[
                { key: "seller", value: <PartyLink id={l.seller_id} displayName={d.seller?.display_name} emailMasked={d.seller?.email_masked} meId={me.id} /> },
                { key: "buy_now_price", value: l.buy_now_enabled ? <Money cents={l.buy_now_price} /> : <span className="text-dim">buy now disabled</span> },
                { key: "starting_bid", value: <Money cents={l.starting_bid} /> },
                { key: "current_bid", value: <Money cents={l.current_bid} /> },
                { key: "bid_count", value: String(l.bid_count ?? 0) },
                { key: "winning_bid_amount", value: <Money cents={l.winning_bid_amount} /> },
                { key: "winner_user_id", label: "Winner", value: l.winner_user_id ? <IdLink kind="user" id={l.winner_user_id} /> : null },
                { key: "created_at", value: <DateTime value={l.created_at} /> },
                { key: "starts_at", value: <DateTime value={raw.starts_at} /> },
                { key: "ends_at", value: <DateTime value={l.ends_at} /> },
                { key: "ended_at", value: <DateTime value={raw.ended_at} /> },
                { key: "sold_at", value: <DateTime value={l.sold_at} /> },
                { key: "duration_hours", value: str(raw.duration_hours) ?? (typeof raw.duration_hours === "number" ? String(raw.duration_hours) : null) },
                { key: "reserved_by", value: str(raw.reserved_by) ? <IdLink kind="user" id={str(raw.reserved_by)} /> : null },
                { key: "reserved_until", value: <DateTime value={raw.reserved_until} /> },
                { key: "restrictions", value: str(raw.restrictions) },
              ]}
            />
            <h3 className="eyebrow mt-4 text-dim">Files (proof of ownership: audited access, short-lived link)</h3>
            <div className="mt-2">
              <EvidenceList items={evidenceItems(d.evidence, { listingId: l.id ?? id, transferId: d.transfer?.id ?? null })} publicBase={SUPABASE_URL ? `${SUPABASE_URL}/storage/v1/object/public` : null} />
            </div>
          </Panel>

          <Panel eyebrow={`${d.payments.length}`} title="Payments on this listing">
            <OrderTable rows={d.payments} basePath={path} caption="Payments" emptyText="No payments." />
          </Panel>

          <Panel eyebrow={d.transfer ? "1" : "0"} title="Transfer obligation">
            {!d.transfer ? (
              <p className="text-dim">No transfer row.</p>
            ) : (
              <KeyValue
                columns={3}
                items={[
                  { key: "transfer", value: <IdLink kind="transfer" id={d.transfer.id} full /> },
                  { key: "status", value: <StatusBadge status={d.transfer.status} label={labelFor("transfer", d.transfer.status)} /> },
                  { key: "payment", value: <IdLink kind="payment" id={d.transfer.payment_id} full /> },
                  { key: "expires_at", label: "Seller deadline", value: <DateTime value={d.transfer.expires_at} /> },
                  { key: "seller_sent_at", value: <DateTime value={d.transfer.seller_sent_at} /> },
                  { key: "buyer_confirmed_at", value: <DateTime value={d.transfer.buyer_confirmed_at} /> },
                  { key: "payout_review_status", value: d.transfer.payout_review_status ? <StatusBadge status={d.transfer.payout_review_status} label={labelFor("payout_review", d.transfer.payout_review_status)} /> : null },
                  { key: "stripe_transfer_id", label: "Stripe Transfer", value: d.transfer.stripe_transfer_id ? <code className="font-mono text-[12px]">{d.transfer.stripe_transfer_id}</code> : <span className="text-dim">none</span> },
                ]}
              />
            )}
          </Panel>

          <Panel eyebrow={`${d.bids.count ?? 0} total`} title="Bids">
            <KeyValue
              columns={3}
              items={[
                { key: "count", value: String(d.bids.count ?? 0) },
                { key: "highest", value: <Money cents={d.bids.highest} /> },
                { key: "highest_bidder_id", label: "Highest bidder", value: d.bids.highest_bidder_id ? <IdLink kind="user" id={d.bids.highest_bidder_id} /> : null },
              ]}
            />
            <div className="mt-3">
              <BidTable rows={d.bids.recent} basePath={path} />
            </div>
          </Panel>

          <Panel eyebrow={`${openReports.length} open · ${d.reports.length} total`} title="Reports on this listing">
            <ReportTable rows={d.reports} basePath={path} />
          </Panel>

          <Panel eyebrow={`${d.seller_flags.length}`} title="Seller flags on this listing">
            <FlagTable rows={d.seller_flags} basePath={path} />
          </Panel>

          <Panel eyebrow={`${d.cases.length}`} title="Cases">
            <CaseTable rows={d.cases} basePath={path} meId={me.id} emptyText="No cases reference this listing." />
          </Panel>

          <Panel eyebrow={`${d.actions.length}`} title="Actions history">
            <ActionTable rows={d.actions} basePath={path} meId={me.id} hideSubject />
          </Panel>
        </div>

        <div className="space-y-6">
          {canRelist ? (
            <Panel eyebrow="Domain rule" title="Relist">
              {canRequest(me.role, "listing_relist") ? (
                <ConfirmForm idempotencyKey={newIdempotencyKey()} actionType="listing_relist" subjectKind="listing" subjectId={id} expected={{ status: l.status, auction_status: l.auction_status }} revalidate={path} label="Relist" danger>
                  <p className="text-[12px] text-muted">
                    admin_relist_listing only accepts admin-owned inventory that has never transacted; anything else is rejected by the domain guard. Price and fees are not editable.
                    {transacted ? " This listing has a captured payment — expect a rejection." : ""}
                  </p>
                  <div>
                    <label htmlFor="relist-ends" className="eyebrow block text-dim">
                      New end (UTC) <span aria-hidden="true">*</span>
                    </label>
                    <input id="relist-ends" type="datetime-local" name="param.new_ends_at" required className="field mt-1" />
                    <p className="text-[11px] text-dim">Enter the new auction end as a UTC wall-clock time; it is stored as timestamptz.</p>
                  </div>
                </ConfirmForm>
              ) : (
                <Alert state="info" title="Only a founder can relist." compact />
              )}
            </Panel>
          ) : (
            <Panel eyebrow="Actions" title="Relist">
              <Alert state="info" title="Relist applies only to active listings whose auction is cancelled." compact>
                Current: status {l.status ?? "—"}, auction {l.auction_status ?? "—"}.
              </Alert>
            </Panel>
          )}

          {openReports.length ? (
            <Panel eyebrow={`${openReports.length}`} title="Resolve reports">
              <div className="space-y-6">
                {openReports.map((r) => (
                  <div key={r.id} id={`report-${r.id}`} className="border-b border-line-neutral pb-4 last:border-b-0 last:pb-0">
                    <p className="text-[13px] text-ink">
                      <span className="font-mono">{r.reason ?? "report"}</span> <StatusBadge status={r.status} label={labelFor("report", r.status)} />
                    </p>
                    <p className="mt-1 text-[12px] text-muted">{r.notes ?? "—"}</p>
                    <p className="mt-1 text-[11px] text-dim">
                      by <IdLink kind="user" id={r.reporter_id} label={r.reporter_label ?? undefined} /> · <DateTime value={r.created_at} />
                    </p>
                    <div className="mt-3">
                      <ReportResolveForms report={r} revalidate={path} />
                    </div>
                  </div>
                ))}
              </div>
            </Panel>
          ) : null}

          <Panel eyebrow="Manual" title="Open a case on this listing">
            <NewCaseForm subjectKind="listing" subjectId={id} revalidate={path} defaultTitle={l.event_name ? `${l.event_name} — ` : undefined} />
          </Panel>
        </div>
      </div>
    </>
  );
}

function BidTable({ rows, basePath }: { rows: Bid[]; basePath: string }) {
  const columns: Column<Bid>[] = [
    { key: "created_at", header: "Placed", render: (b) => <DateTime value={b.created_at} /> },
    { key: "amount", header: "Amount", align: "right", render: (b) => <Money cents={b.amount} /> },
    { key: "bidder", header: "Bidder", render: (b) => <PartyLink id={b.bidder_id} displayName={b.bidder_display_name} /> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(b, i) => b.id ?? `${i}`} basePath={basePath} emptyText="No bids." caption="Recent bids" dense />;
}

function ReportTable({ rows, basePath }: { rows: Report[]; basePath: string }) {
  const columns: Column<Report>[] = [
    { key: "created_at", header: "Filed", render: (r) => <DateTime value={r.created_at} /> },
    { key: "reason", header: "Reason", render: (r) => <span className="font-mono text-[12px]">{r.reason ?? "—"}</span> },
    { key: "status", header: "Status", render: (r) => <StatusBadge status={r.status} label={labelFor("report", r.status)} /> },
    { key: "reporter", header: "Reporter", render: (r) => <IdLink kind="user" id={r.reporter_id} label={r.reporter_label ?? undefined} /> },
    { key: "notes", header: "Notes", render: (r) => <span className="line-clamp-2 max-w-[320px] text-[12px] text-muted">{r.notes ?? "—"}</span> },
    { key: "resolved_at", header: "Resolved", render: (r) => <DateTime value={r.resolved_at} /> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(r, i) => r.id ?? `${i}`} basePath={basePath} emptyText="No reports." caption="Reports" dense />;
}

function FlagTable({ rows, basePath }: { rows: JsonRecord[]; basePath: string }) {
  const columns: Column<JsonRecord>[] = [
    { key: "created_at", header: "Raised", render: (r) => <DateTime value={r.created_at} /> },
    { key: "flag_type", header: "Flag", render: (r) => <span className="font-mono text-[12px]">{str(r.flag_type) ?? "—"}</span> },
    { key: "severity", header: "Severity", render: (r) => <StatusBadge status={str(r.severity)} variant={str(r.severity) === "critical" ? "danger" : str(r.severity) === "warning" ? "warn" : "neutral"} /> },
    { key: "details", header: "Details", render: (r) => <span className="line-clamp-2 max-w-[360px] text-[12px] text-muted">{str(r.details) ?? "—"}</span> },
    { key: "reviewed_at", header: "Reviewed", render: (r) => <DateTime value={r.reviewed_at} /> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(r, i) => str(r.id) ?? `${i}`} basePath={basePath} emptyText="No flags." caption="Seller flags" dense />;
}
