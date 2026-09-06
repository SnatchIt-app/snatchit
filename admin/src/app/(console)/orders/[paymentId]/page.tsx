import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { newIdempotencyKey } from "@/lib/idempotency";
import { isUuid } from "@/lib/routes";
import { canRequest } from "@/lib/permissions";
import { labelFor, shortId, DISPUTE_OUTCOME_LABELS } from "@/lib/format";
import { asArray, str, num, bool, toOrderDetail, toSettings, toTimeline, type JsonRecord, type OrderDetail } from "@/lib/types";
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
import { CaseTable } from "@/components/cases/CaseTable";
import { NewCaseForm } from "@/components/cases/NewCaseForm";
import { ActionTable } from "@/components/actions/ActionTable";
import { Timeline } from "@/components/orders/Timeline";

export const metadata: Metadata = { title: "Order" };
export const dynamic = "force-dynamic";

function isNotFound(message: string | undefined): boolean {
  return (message ?? "").toLowerCase().includes("not_found");
}

export default async function OrderPage({ params }: { params: Promise<{ paymentId: string }> }) {
  const { paymentId } = await params;
  if (!isUuid(paymentId)) notFound();
  const me = await requireOperator();
  const path = `/orders/${paymentId}`;

  const [detailRes, timelineRes, settingsRes] = await Promise.all([
    callOps<unknown>("order_detail", { p_payment_id: paymentId }),
    callOps<unknown>("order_timeline", { p_payment_id: paymentId }),
    me.role === "platform_admin" ? callOps<unknown>("settings") : Promise.resolve(null),
  ]);

  if (!detailRes.ok) {
    return (
      <>
        <PageHeader eyebrow="Order" title={<code className="font-mono">{shortId(paymentId)}</code>} />
        {detailRes.kind === "error" && isNotFound(detailRes.message) ? (
          <Alert state="empty" title="No payment with this id." retryHref="/orders" retryLabel="Back to orders" />
        ) : (
          <OpsFailureAlert failure={detailRes} fn="order_detail" retryHref={path} />
        )}
      </>
    );
  }
  const d = toOrderDetail(detailRes.data);
  if (!d || !d.payment) {
    return (
      <>
        <PageHeader eyebrow="Order" title={<code className="font-mono">{shortId(paymentId)}</code>} />
        <Alert state="failed" title="Unrecognised payload from ops.order_detail()" retryHref={path} />
      </>
    );
  }
  const p = d.payment;
  const t = d.transfer;
  const l = d.listing;
  const timeline = timelineRes.ok ? toTimeline(timelineRes.data) : null;

  // Refund execution is gated by ops.setting refund_execute_enabled; only a
  // platform_admin can read settings, so anyone else assumes disabled.
  let refundEnabled = false;
  if (settingsRes && settingsRes.ok) {
    const s = toSettings(settingsRes.data).find((x) => x.key === "refund_execute_enabled");
    refundEnabled = s?.value === true;
  }

  const disputeOpen = Boolean(t?.disputed_at) && !t?.dispute_resolved_at;
  const canRelease = t?.status === "seller_sent" && !t?.payout_released_at && !disputeOpen;
  const canRefund = p.status === "succeeded";
  const eventTitle = l?.event_name ?? "Order";

  return (
    <>
      <PageHeader
        eyebrow={
          <>
            <Link href="/orders" className="hover:text-ink">
              Orders
            </Link>{" "}
            / payment {shortId(p.id)}
          </>
        }
        title={
          l?.id ? (
            <Link href={`/marketplace/${l.id}`} className="hover:text-primary">
              {eventTitle}
            </Link>
          ) : (
            eventTitle
          )
        }
        description={
          l ? [l.venue, l.event_date, l.event_time, l.ticket_type, l.quantity ? `×${l.quantity}` : null, l.ticket_platform].filter(Boolean).join(" · ") : undefined
        }
        meta={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status={p.status} label={`payment: ${labelFor("payment", p.status)}`} />
            <StatusBadge status={t?.status ?? null} label={t ? `transfer: ${labelFor("transfer", t.status)}` : "no transfer row"} />
            <StatusBadge status={d.seller_funds_state} label={`funds: ${labelFor("funds", d.seller_funds_state)}`} />
            <span className="font-mono">
              payment <code>{p.id}</code>
            </span>
            {t?.id ? (
              <span className="font-mono">
                · transfer <code>{t.id}</code>
              </span>
            ) : null}
            {p.stripe_livemode === false ? <StatusBadge status="test" label="stripe test mode" variant="muted" /> : null}
          </span>
        }
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Panel eyebrow="Parties" title="Buyer & seller (masked)">
            <KeyValue
              columns={2}
              items={[
                {
                  key: "buyer",
                  value: (
                    <span className="flex flex-col gap-0.5">
                      <PartyLink id={d.buyer?.id ?? p.buyer_id} displayName={d.buyer?.display_name} emailMasked={d.buyer?.email_masked} meId={me.id} />
                      <span className="text-[11px] text-dim">phone {d.buyer?.phone_masked ?? "—"}</span>
                    </span>
                  ),
                },
                {
                  key: "seller",
                  value: (
                    <span className="flex flex-col gap-0.5">
                      <PartyLink id={d.seller?.id ?? p.seller_id} displayName={d.seller?.display_name} emailMasked={d.seller?.email_masked} meId={me.id} />
                      <span className="text-[11px] text-dim">
                        {d.seller?.is_verified_seller ? "verified seller" : "not verified"} · onboarding {d.seller?.stripe_onboarding_complete ? "complete" : "incomplete"}
                        {d.seller?.stripe_payouts_enabled === null || d.seller?.stripe_payouts_enabled === undefined ? "" : ` · payouts ${d.seller.stripe_payouts_enabled ? "enabled" : "disabled"}`}
                      </span>
                    </span>
                  ),
                },
              ]}
            />
          </Panel>

          <Panel eyebrow="Captured payment" title="Payment">
            <KeyValue
              columns={3}
              items={[
                { key: "amount", label: "Amount (ticket price)", value: <Money cents={p.amount} /> },
                { key: "buyer_fee", value: <Money cents={p.buyer_fee} /> },
                { key: "seller_fee", value: <Money cents={p.seller_fee} /> },
                { key: "total", label: "Total charged to buyer", value: <Money cents={p.total} /> },
                { key: "mode", value: p.mode ? <StatusBadge status={p.mode} variant="neutral" /> : null },
                { key: "payment_method", value: p.payment_method },
                { key: "stripe_payment_intent_id", label: "Stripe PaymentIntent", value: p.stripe_payment_intent_id ? <code className="font-mono text-[12px]">{p.stripe_payment_intent_id}</code> : null },
                { key: "status", value: <StatusBadge status={p.status} label={labelFor("payment", p.status)} /> },
                { key: "created_at", value: <DateTime value={p.created_at} /> },
                { key: "paid_at", label: "Captured at", value: <DateTime value={p.paid_at} /> },
                { key: "failed_at", value: <DateTime value={p.failed_at} /> },
                { key: "refunded_at", value: <DateTime value={p.refunded_at} /> },
              ]}
            />
          </Panel>

          <Panel eyebrow="Seller obligation" title="Transfer">
            {!t ? (
              <Alert state={p.status === "succeeded" ? "warning" : "info"} title={p.status === "succeeded" ? "Captured payment without a transfer row." : "No transfer obligation (payment not captured)."} compact>
                {p.status === "succeeded" ? "This is a settlement gap (audit F02). Escalate with the payment id — do not mark anything sold by hand." : null}
              </Alert>
            ) : (
              <>
                <KeyValue
                  columns={3}
                  items={[
                    { key: "status", value: <StatusBadge status={t.status} label={labelFor("transfer", t.status)} /> },
                    { key: "transfer_method", value: t.transfer_method },
                    { key: "created_at", value: <DateTime value={t.created_at} /> },
                    { key: "expires_at", label: "Seller deadline", value: <DateTime value={t.expires_at} /> },
                    { key: "auto_release_at", label: "Auto-release at", value: <DateTime value={t.auto_release_at} /> },
                    { key: "expired_at", value: <DateTime value={t.expired_at} /> },
                    { key: "seller_sent_at", value: <DateTime value={t.seller_sent_at} /> },
                    { key: "buyer_viewed_at", value: <DateTime value={t.buyer_viewed_at} /> },
                    { key: "buyer_confirmed_at", value: <DateTime value={t.buyer_confirmed_at} /> },
                    { key: "delivery_email", label: "Delivery email (masked)", value: t.delivery_email ? <span className="font-mono text-[12px]">{t.delivery_email}</span> : null },
                    { key: "delivery_phone", label: "Delivery phone (masked)", value: t.delivery_phone ? <span className="font-mono text-[12px]">{t.delivery_phone}</span> : null },
                    { key: "id", label: "Transfer id", value: <code className="font-mono text-[12px]">{t.id}</code> },
                  ]}
                />
                <h3 className="eyebrow mt-4 text-dim">Evidence (signed links, expire in 10 min)</h3>
                <div className="mt-2">
                  <EvidenceList items={d.evidence.filter((e) => e.key !== "proof_of_ownership_path")} />
                </div>
              </>
            )}
          </Panel>

          <Panel eyebrow="Where the seller's share sits" title="Seller funds state">
            <div className="flex flex-wrap items-center gap-3">
              <StatusBadge status={d.seller_funds_state} label={labelFor("funds", d.seller_funds_state)} variant={d.seller_funds_state === "released_to_connected_account" ? "ok" : undefined} />
              <code className="font-mono text-[11px] text-dim">{d.seller_funds_state ?? "—"}</code>
            </div>
            {t ? (
              <KeyValue
                columns={3}
                items={[
                  { key: "payout_review_status", value: t.payout_review_status ? <StatusBadge status={t.payout_review_status} label={labelFor("payout_review", t.payout_review_status)} /> : "none" },
                  { key: "payout_risk_tier", value: t.payout_risk_tier ? <StatusBadge status={t.payout_risk_tier} variant="neutral" /> : null },
                  { key: "payout_reason_codes", value: t.payout_reason_codes?.length ? t.payout_reason_codes.join(", ") : null },
                  { key: "payout_hold_until", value: <DateTime value={t.payout_hold_until} /> },
                  { key: "payout_released_at", label: "Release recorded at", value: <DateTime value={t.payout_released_at} /> },
                  {
                    key: "stripe_transfer_id",
                    label: "Stripe Transfer (connected account)",
                    value: t.stripe_transfer_id ? <code className="font-mono text-[12px]">{t.stripe_transfer_id}</code> : <span className="text-dim">none — funds not released</span>,
                  },
                  { key: "seller_share", label: "Seller share (amount − seller fee)", value: p.amount !== null && p.amount !== undefined ? <Money cents={p.amount - (p.seller_fee ?? 0)} /> : null },
                ]}
              />
            ) : null}
            <p className="mt-3 text-[11px] text-dim">
              {d.bank_payout.note ?? "Bank payouts from the connected account to the seller's bank are not tracked."} “Released to connected account” is a Stripe Transfer, not a bank payout.
            </p>
          </Panel>

          <Panel eyebrow={`${d.disputes.length} stripe · ${t?.disputed_at ? 1 : 0} in-app`} title="Disputes">
            {t?.disputed_at ? (
              <div className="mb-4">
                <h3 className="eyebrow text-dim">In-app dispute (transfer)</h3>
                <KeyValue
                  columns={3}
                  items={[
                    { key: "disputed_at", value: <DateTime value={t.disputed_at} /> },
                    { key: "dispute_reason", value: t.dispute_reason },
                    { key: "dispute_notes", value: t.dispute_notes },
                    { key: "dispute_resolution", value: t.dispute_resolution ? <StatusBadge status={t.dispute_resolution} variant="neutral" /> : <StatusBadge status="dispute_open" label="unresolved" /> },
                    { key: "dispute_resolved_at", value: <DateTime value={t.dispute_resolved_at} /> },
                    { key: "dispute_resolved_by", value: t.dispute_resolved_by ? <IdLink kind="user" id={t.dispute_resolved_by} /> : null },
                  ]}
                />
              </div>
            ) : null}
            <h3 className="eyebrow text-dim">Stripe disputes (chargebacks)</h3>
            <div className="mt-2">
              <StripeDisputeTable rows={d.disputes} basePath={path} />
            </div>
            {d.dispute_resolutions.length ? (
              <>
                <h3 className="eyebrow mt-4 text-dim">Resolutions recorded</h3>
                <div className="mt-2">
                  <ResolutionTable rows={d.dispute_resolutions} basePath={path} />
                </div>
              </>
            ) : null}
          </Panel>

          <Panel eyebrow={`${d.payout_decisions.length}`} title="Payout decisions (risk classifier)">
            <PayoutDecisionTable rows={d.payout_decisions} basePath={path} />
          </Panel>

          <Panel eyebrow="Refund facts" title="Refund">
            <KeyValue
              columns={3}
              items={[
                { key: "payment_status", value: <StatusBadge status={d.refund.payment_status} label={labelFor("payment", d.refund.payment_status)} /> },
                { key: "refunded_at", value: <DateTime value={d.refund.refunded_at} /> },
                { key: "stripe_refund_id", value: d.refund.stripe_refund_id ? <code className="font-mono text-[12px]">{d.refund.stripe_refund_id}</code> : <span className="text-dim">none</span> },
              ]}
            />
            <p className="mt-3 text-[11px] text-dim">“Refunded” is set by the Stripe charge.refunded webhook after the provider refund succeeded — never by the console.</p>
            {d.refund.refund_actions.length ? (
              <div className="mt-3">
                <h3 className="eyebrow text-dim">Refund execution attempts</h3>
                <div className="mt-2">
                  <ActionTable rows={d.refund.refund_actions} basePath={path} meId={me.id} hideSubject />
                </div>
              </div>
            ) : null}
          </Panel>
        </div>

        <div className="space-y-6">
          <OrderActions d={d} me={me} path={path} refundEnabled={refundEnabled} disputeOpen={disputeOpen} canRelease={canRelease} canRefund={canRefund} />
        </div>
      </div>

      <div className="mt-6 space-y-6">
        <Panel eyebrow={`${d.cases.length}`} title="Cases on this order">
          <CaseTable rows={d.cases} basePath={path} meId={me.id} emptyText="No cases reference this payment, transfer or listing." />
        </Panel>
        <Panel eyebrow={`${d.actions.length}`} title="Actions history">
          <ActionTable rows={d.actions} basePath={path} meId={me.id} />
        </Panel>
        <Panel eyebrow="Chronology" title="Timeline">
          {!timelineRes.ok ? <OpsFailureAlert failure={timelineRes} fn="order_timeline" retryHref={path} /> : timeline ? <Timeline data={timeline} /> : null}
        </Panel>
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------

function OrderActions({
  d,
  me,
  path,
  refundEnabled,
  disputeOpen,
  canRelease,
  canRefund,
}: {
  d: OrderDetail;
  me: Awaited<ReturnType<typeof requireOperator>>;
  path: string;
  refundEnabled: boolean;
  disputeOpen: boolean;
  canRelease: boolean;
  canRefund: boolean;
}) {
  const p = d.payment!;
  const t = d.transfer;
  const nothing = !disputeOpen && !canRelease && !canRefund;
  return (
    <>
      <Panel eyebrow="Safe actions" title="Actions">
        <p className="text-[12px] text-muted">
          Every action needs a reason, checks the state you see here before acting, and is recorded with your identity. Results shown are the server&apos;s answer — never optimistic.
        </p>
        {nothing ? <Alert state="info" title="No state-changing action applies to this order right now." compact /> : null}
      </Panel>

      {disputeOpen && t?.id ? (
        <Panel eyebrow="Dispute open" title="Resolve dispute">
          {canRequest(me.role, "dispute_resolve") ? (
            <ConfirmForm
              idempotencyKey={newIdempotencyKey()}
              actionType="dispute_resolve"
              subjectKind="transfer"
              subjectId={t.id}
              expected={{ status: t.status }}
              revalidate={path}
              label="Record resolution"
              danger
            >
              <div>
                <label htmlFor="dispute-outcome" className="eyebrow block text-dim">
                  Outcome <span aria-hidden="true">*</span>
                </label>
                <select id="dispute-outcome" name="param.outcome" required defaultValue="" className="field mt-1">
                  <option value="" disabled>
                    Choose…
                  </option>
                  {Object.entries(DISPUTE_OUTCOME_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="dispute-notes" className="eyebrow block text-dim">
                  Notes for the record
                </label>
                <textarea id="dispute-notes" name="param.notes" rows={2} maxLength={2000} className="field mt-1" />
              </div>
              <p className="text-[11px] text-dim">Buyer win / partial refund does not move money — a Refund pending case opens and the refund is executed separately.</p>
            </ConfirmForm>
          ) : (
            <Alert state="info" title="Only founders and risk operators can record dispute outcomes." compact />
          )}
        </Panel>
      ) : null}

      {canRelease && t?.id ? (
        <Panel eyebrow="Two-founder approval" title="Release held payout">
          {canRequest(me.role, "payout_release") ? (
            <ConfirmForm
              idempotencyKey={newIdempotencyKey()}
              actionType="payout_release"
              subjectKind="transfer"
              subjectId={t.id}
              expected={{ payout_review_status: t.payout_review_status ?? null }}
              revalidate={path}
              label="Request release"
              danger
            >
              <p className="text-[12px] text-muted">
                Marks the transfer released; the payout worker creates the Stripe Transfer to the seller&apos;s connected account on its next run (not a bank payout). Requires the other founder&apos;s approval under System → Approvals; nothing changes until then.
              </p>
              <p className="text-[11px] text-dim">
                Current review status: <StatusBadge status={t.payout_review_status} label={labelFor("payout_review", t.payout_review_status ?? "none")} />
                {t.payout_risk_tier ? <> · risk tier {t.payout_risk_tier}</> : null}
              </p>
            </ConfirmForm>
          ) : (
            <Alert state="info" title="Only a founder can request a payout release." compact />
          )}
        </Panel>
      ) : null}

      {canRefund ? (
        <Panel eyebrow="Two-founder approval" title="Execute refund">
          {!canRequest(me.role, "refund_execute") ? (
            <Alert state="info" title="Only a founder can request a refund." compact />
          ) : (
            <>
              {!refundEnabled ? (
                <Alert state="warning" title="Disabled until ops-refund-execute is deployed." compact>
                  {me.role === "platform_admin"
                    ? "ops.setting refund_execute_enabled is false. Follow the Stripe Dashboard SOP; the request below will be rejected as disabled."
                    : "Refund execution state is only visible to founders; assume disabled and follow the Stripe Dashboard SOP."}
                </Alert>
              ) : null}
              <ConfirmForm
                idempotencyKey={newIdempotencyKey()}
                actionType="refund_execute"
                subjectKind="payment"
                subjectId={p.id ?? ""}
                expected={{ status: p.status }}
                revalidate={path}
                label={refundEnabled ? "Request refund" : "Request refund (will be rejected: disabled)"}
                danger
                className="mt-3"
              >
                <div>
                  <label htmlFor="refund-amount" className="eyebrow block text-dim">
                    Amount in cents (optional — empty = full total <Money cents={p.total} />)
                  </label>
                  <input id="refund-amount" name="param.amount_cents:integer" type="number" min={1} max={p.total ?? undefined} step={1} inputMode="numeric" className="field mt-1" placeholder={p.total !== null && p.total !== undefined ? String(p.total) : ""} />
                </div>
                <p className="text-[11px] text-dim">
                  Parked as awaiting approval; after the other founder approves, the ops-refund-execute function calls Stripe with a stable idempotency key. The console never calls Stripe. The payment shows “refunded” only after the webhook lands.
                </p>
              </ConfirmForm>
            </>
          )}
        </Panel>
      ) : null}

      <Panel eyebrow="Manual" title="Open a case on this order">
        <NewCaseForm subjectKind="payment" subjectId={p.id} revalidate={path} defaultTitle={d.listing?.event_name ? `${d.listing.event_name} — ` : undefined} />
      </Panel>
    </>
  );
}

// ---------------------------------------------------------------------------

function StripeDisputeTable({ rows, basePath }: { rows: JsonRecord[]; basePath: string }) {
  const columns: Column<JsonRecord>[] = [
    { key: "created_at", header: "Opened", render: (r) => <DateTime value={r.created_at} /> },
    { key: "stripe_dispute_id", header: "Stripe dispute", render: (r) => <code className="font-mono text-[12px]">{str(r.stripe_dispute_id) ?? "—"}</code> },
    { key: "status", header: "Status", render: (r) => <StatusBadge status={str(r.status)} /> },
    { key: "reason", header: "Reason", render: (r) => str(r.reason) ?? "—" },
    { key: "amount", header: "Amount", align: "right", render: (r) => <Money cents={num(r.amount)} /> },
    { key: "evidence_due_by", header: "Evidence due", render: (r) => <DateTime value={r.evidence_due_by} /> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(r, i) => str(r.id) ?? `${i}`} basePath={basePath} emptyText="No Stripe disputes (chargebacks) on this payment." caption="Stripe disputes" dense />;
}

function ResolutionTable({ rows, basePath }: { rows: JsonRecord[]; basePath: string }) {
  const columns: Column<JsonRecord>[] = [
    { key: "created_at", header: "Recorded", render: (r) => <DateTime value={r.created_at} /> },
    { key: "outcome", header: "Outcome", render: (r) => <StatusBadge status={str(r.outcome)} variant="neutral" /> },
    { key: "resolution", header: "Resolution", render: (r) => str(r.resolution) ?? "—" },
    { key: "refund_required", header: "Refund required", render: (r) => <StatusBadge status={String(bool(r.refund_required) ?? false)} label={bool(r.refund_required) ? "yes — not executed by this record" : "no"} /> },
    { key: "actor", header: "By", render: (r) => str(r.actor_label) ?? shortId(r.actor_id) },
    { key: "reason", header: "Reason / notes", render: (r) => <span className="text-[12px] text-muted">{[str(r.reason), str(r.notes)].filter(Boolean).join(" — ") || "—"}</span> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(r, i) => str(r.id) ?? `${i}`} basePath={basePath} emptyText="No resolutions." caption="Dispute resolutions" dense />;
}

function PayoutDecisionTable({ rows, basePath }: { rows: JsonRecord[]; basePath: string }) {
  const columns: Column<JsonRecord>[] = [
    { key: "decided_at", header: "Decided", render: (r) => <DateTime value={r.decided_at} /> },
    { key: "decision", header: "Decision", render: (r) => <StatusBadge status={str(r.decision)} /> },
    { key: "risk_tier", header: "Risk tier", render: (r) => <StatusBadge status={str(r.risk_tier)} variant="neutral" /> },
    { key: "reason_codes", header: "Reason codes", render: (r) => <span className="font-mono text-[11px]">{asArray(r.reason_codes).join(", ") || "—"}</span> },
    { key: "hold_until", header: "Hold until", render: (r) => <DateTime value={r.hold_until} /> },
    {
      key: "flags",
      header: "Buyer confirmed / dispute",
      render: (r) => (
        <span className="text-[12px]">
          {bool(r.buyer_confirmed) ? "confirmed" : "not confirmed"} / {bool(r.dispute_open) ? "dispute open" : "no dispute"}
        </span>
      ),
    },
    { key: "actor", header: "Actor", render: (r) => (str(r.actor) ? <span className="font-mono text-[11px]">{str(r.actor)}</span> : <span className="text-dim">system</span>) },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(r, i) => str(r.id) ?? `${i}`} basePath={basePath} emptyText="No payout decisions recorded." caption="Payout decisions" dense />;
}
