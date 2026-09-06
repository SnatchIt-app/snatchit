import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { newIdempotencyKey } from "@/lib/idempotency";
import { isUuid } from "@/lib/routes";
import { canRequest } from "@/lib/permissions";
import { formatRatio, humanize, labelFor, shortId } from "@/lib/format";
import { str, num, toUserDetail, type JsonRecord, type Report } from "@/lib/types";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { KeyValue } from "@/components/ui/KeyValue";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DateTime } from "@/components/ui/DateTime";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { ConfirmForm } from "@/components/ui/ConfirmForm";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { IdLink } from "@/components/ui/IdLink";
import { OrderTable } from "@/components/orders/OrderTable";
import { ListingTable } from "@/components/marketplace/ListingTable";
import { CaseTable } from "@/components/cases/CaseTable";
import { NewCaseForm } from "@/components/cases/NewCaseForm";

export const metadata: Metadata = { title: "User" };
export const dynamic = "force-dynamic";

export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const me = await requireOperator();
  const path = `/users/${id}`;

  const res = await callOps<unknown>("user_detail", { p_user_id: id });
  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="User" title={<code className="font-mono">{shortId(id)}</code>} />
        {res.kind === "error" && res.message.toLowerCase().includes("not_found") ? (
          <Alert state="empty" title="No user with this id." retryHref="/users" retryLabel="Back to users" />
        ) : (
          <OpsFailureAlert failure={res} fn="user_detail" retryHref={path} />
        )}
      </>
    );
  }
  const u = toUserDetail(res.data);
  if (!u) {
    return (
      <>
        <PageHeader eyebrow="User" title={<code className="font-mono">{shortId(id)}</code>} />
        <Alert state="failed" title="Unrecognised payload from ops.user_detail()" retryHref={path} />
      </>
    );
  }
  const risk = u.seller_risk_score;
  const activeRestriction = u.restrictions.find((r) => !r.lifted_at);

  const profileExtras = Object.entries(u.profile).filter(
    ([k]) => !["id", "display_name", "full_name", "email_masked", "phone_masked", "created_at", "avatar_url", "avatar_path", "bio", "preferred_neighborhoods"].includes(k),
  );

  return (
    <>
      <PageHeader
        eyebrow={
          <>
            <Link href="/users" className="hover:text-ink">
              Users
            </Link>{" "}
            / {id === me.id ? "me" : shortId(id)}
          </>
        }
        title={u.display_name || u.full_name || shortId(id)}
        description={u.full_name && u.full_name !== u.display_name ? u.full_name : undefined}
        meta={
          <span className="flex flex-wrap items-center gap-2">
            <StatusBadge status={u.is_listing_blocked ? "held" : "active"} label={u.is_listing_blocked ? "listing creation blocked" : "listing creation allowed"} />
            {u.profile.is_verified_seller === true ? <StatusBadge status="ok" label="verified seller" /> : null}
            {u.is_operator ? <StatusBadge status="info" label="console operator" /> : null}
            {risk?.risk_tier ? <StatusBadge status={str(risk.risk_tier)} label={`risk ${str(risk.risk_tier)}`} /> : null}
            <span className="font-mono">
              <code>{id}</code>
            </span>
          </span>
        }
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Panel eyebrow="Masked" title="Profile">
            <KeyValue
              columns={3}
              items={[
                { key: "email_masked", label: "Email (masked)", value: u.email_masked ? <span className="font-mono text-[12px]">{u.email_masked}</span> : null },
                { key: "phone_masked", label: "Phone (masked)", value: u.phone_masked ? <span className="font-mono text-[12px]">{u.phone_masked}</span> : null },
                { key: "created_at", label: "Profile created", value: <DateTime value={u.profile.created_at} /> },
                { key: "auth_created", label: "Account created", value: <DateTime value={u.auth.created_at} /> },
                { key: "email_confirmed_at", value: <DateTime value={u.auth.email_confirmed_at} /> },
                { key: "phone_confirmed_at", value: <DateTime value={u.auth.phone_confirmed_at} /> },
                { key: "last_sign_in_at", value: u.auth.last_sign_in_at ? <DateTime value={u.auth.last_sign_in_at} /> : <span className="text-dim">unavailable</span> },
                ...profileExtras.map(([k, v]) => ({
                  key: k,
                  value: typeof v === "boolean" ? <StatusBadge status={String(v)} label={v ? "yes" : "no"} /> : typeof v === "string" || typeof v === "number" ? String(v) : null,
                })),
              ]}
            />
          </Panel>

          <Panel eyebrow="Stripe Connect" title="Seller onboarding">
            <KeyValue
              columns={3}
              items={Object.entries(u.onboarding).map(([k, v]) => ({
                key: k,
                value: typeof v === "boolean" ? <StatusBadge status={String(v)} label={v ? "yes" : "no"} /> : v === null ? null : <StatusBadge status={v} variant="neutral" />,
              }))}
            />
            <p className="mt-3 text-[11px] text-dim">Stripe account ids are never shown here; presence flags only.</p>
          </Panel>

          <Panel eyebrow={`${u.listings.length}`} title="Listings (latest 50)">
            <ListingTable rows={u.listings} basePath={path} hideSeller />
          </Panel>

          <Panel eyebrow={`${u.orders_as_buyer.length}`} title="Orders as buyer (latest 50)">
            <OrderTable rows={u.orders_as_buyer} basePath={path} caption="Orders as buyer" emptyText="No purchases." />
          </Panel>

          <Panel eyebrow={`${u.orders_as_seller.length}`} title="Orders as seller (latest 50)">
            <OrderTable rows={u.orders_as_seller} basePath={path} caption="Orders as seller" emptyText="No sales." />
          </Panel>

          <Panel eyebrow={`${u.reports_received.length} received · ${u.reports_made.length} made`} title="Reports">
            <h3 className="eyebrow text-dim">Received (this user is the target)</h3>
            <div className="mt-2">
              <ReportMiniTable rows={u.reports_received} basePath={path} who="reporter" />
            </div>
            <h3 className="eyebrow mt-4 text-dim">Made by this user</h3>
            <div className="mt-2">
              <ReportMiniTable rows={u.reports_made} basePath={path} who="target" />
            </div>
          </Panel>

          <Panel eyebrow={`${u.seller_flags.length}`} title="Seller flags">
            <FlagTable rows={u.seller_flags} basePath={path} />
          </Panel>

          <Panel eyebrow="seller_risk_scores" title="Risk score">
            {!risk ? (
              <p className="text-dim">No risk score row (never sold).</p>
            ) : (
              <KeyValue
                columns={3}
                items={[
                  { key: "risk_tier", value: <StatusBadge status={str(risk.risk_tier)} /> },
                  { key: "account_age_days", value: num(risk.account_age_days)?.toString() ?? null },
                  { key: "total_listings", value: num(risk.total_listings)?.toString() ?? null },
                  { key: "active_listings", value: num(risk.active_listings)?.toString() ?? null },
                  { key: "total_completed", value: num(risk.total_completed)?.toString() ?? null },
                  { key: "total_disputes", value: num(risk.total_disputes)?.toString() ?? null },
                  { key: "total_dispute_losses", value: num(risk.total_dispute_losses)?.toString() ?? null },
                  { key: "total_expired", value: num(risk.total_expired)?.toString() ?? null },
                  { key: "dispute_rate", value: formatRatio(risk.dispute_rate) },
                  { key: "dispute_loss_rate", value: formatRatio(risk.dispute_loss_rate) },
                  { key: "expiry_rate", value: formatRatio(risk.expiry_rate) },
                  { key: "rapid_send_count", value: num(risk.rapid_send_count)?.toString() ?? null },
                  { key: "open_flags_count", value: num(risk.open_flags_count)?.toString() ?? null },
                  { key: "critical_flags_count", value: num(risk.critical_flags_count)?.toString() ?? null },
                  { key: "updated_at", value: <DateTime value={risk.updated_at} /> },
                ]}
              />
            )}
          </Panel>

          <Panel eyebrow={`${u.cases.length}`} title="Cases on this user">
            <CaseTable rows={u.cases} basePath={path} meId={me.id} emptyText="No cases reference this user." />
          </Panel>
        </div>

        <div className="space-y-6">
          <Panel eyebrow="Enforced by can_create_listing()" title="Listing creation">
            <div className="mb-3 flex flex-wrap items-center gap-2 text-[13px]">
              <StatusBadge status={u.is_listing_blocked ? "held" : "active"} label={u.is_listing_blocked ? "blocked" : "allowed"} />
              {u.is_listing_blocked && risk ? (
                <span className="text-muted">
                  since <DateTime value={risk.listing_blocked_at} />
                </span>
              ) : null}
            </div>
            {u.is_listing_blocked && risk && str(risk.listing_blocked_reason) ? <p className="mb-3 text-[12px] text-muted">Reason on record: {str(risk.listing_blocked_reason)}</p> : null}
            {u.is_listing_blocked ? (
              canRequest(me.role, "user_unrestrict") ? (
                <ConfirmForm
                  idempotencyKey={newIdempotencyKey()}
                  actionType="user_unrestrict"
                  subjectKind="user"
                  subjectId={id}
                  params={{ kind: "listing_blocked" }}
                  expected={{ is_listing_blocked: true }}
                  revalidate={path}
                  label="Unblock listing creation"
                />
              ) : (
                <Alert state="info" title="Only founders and risk operators can lift a block." compact />
              )
            ) : canRequest(me.role, "user_restrict") ? (
              <ConfirmForm
                idempotencyKey={newIdempotencyKey()}
                actionType="user_restrict"
                subjectKind="user"
                subjectId={id}
                params={{ kind: "listing_blocked" }}
                expected={{ is_listing_blocked: false }}
                revalidate={path}
                label="Block listing creation"
                danger
              >
                <p className="text-[12px] text-muted">Sets seller_risk_scores.is_listing_blocked; the apps call can_create_listing() before creating a listing. Existing listings and orders are untouched. Account suspension does not exist and is not offered.</p>
              </ConfirmForm>
            ) : (
              <Alert state="info" title="Your role cannot block listing creation." compact />
            )}
          </Panel>

          <Panel eyebrow={`${u.restrictions.length}`} title="Restriction history">
            {u.restrictions.length === 0 ? (
              <p className="text-dim">No console restrictions recorded{u.is_listing_blocked ? " (the current block was set outside the console)" : ""}.</p>
            ) : (
              <ol className="space-y-3">
                {u.restrictions.map((r, i) => (
                  <li key={r.id ?? i} className={`border-l-2 pl-3 ${r.lifted_at ? "border-line-neutral" : "border-warning"}`}>
                    <p className="text-[13px] text-ink">
                      <StatusBadge status={r.lifted_at ? "resolved" : "held"} label={r.lifted_at ? "lifted" : "active"} /> <span className="ml-2">{humanize(r.kind ?? "restriction")}</span>
                    </p>
                    <p className="mt-1 text-[12px] text-muted">{r.reason}</p>
                    <p className="mt-1 text-[11px] text-dim">
                      by {r.actor === me.id ? "me" : r.actor_label ?? shortId(r.actor)} · <DateTime value={r.created_at} />
                    </p>
                    {r.lifted_at ? (
                      <p className="mt-1 text-[11px] text-dim">
                        lifted <DateTime value={r.lifted_at} />
                        {r.lift_reason ? ` — ${r.lift_reason}` : ""}
                      </p>
                    ) : null}
                  </li>
                ))}
              </ol>
            )}
            {activeRestriction && !u.is_listing_blocked ? <Alert state="warning" title="Console restriction is active but the risk row says allowed — investigate." compact /> : null}
          </Panel>

          <Panel eyebrow="Manual" title="Open a case on this user">
            <NewCaseForm subjectKind="user" subjectId={id} revalidate={path} defaultTitle={u.display_name ? `${u.display_name} — ` : undefined} />
          </Panel>
        </div>
      </div>
    </>
  );
}

function ReportMiniTable({ rows, basePath, who }: { rows: Report[]; basePath: string; who: "reporter" | "target" }) {
  const columns: Column<Report>[] = [
    { key: "created_at", header: "Filed", render: (r) => <DateTime value={r.created_at} /> },
    { key: "reason", header: "Reason", render: (r) => <span className="font-mono text-[12px]">{r.reason ?? "—"}</span> },
    { key: "status", header: "Status", render: (r) => <StatusBadge status={r.status} label={labelFor("report", r.status)} /> },
    who === "reporter"
      ? { key: "reporter", header: "Reporter", render: (r) => <IdLink kind="user" id={r.reporter_id} label={r.reporter_label ?? undefined} /> }
      : { key: "target", header: "Target", render: (r) => <IdLink kind={r.target_type} id={r.target_id} label={r.target_label ?? undefined} /> },
    { key: "notes", header: "Notes", render: (r) => <span className="line-clamp-2 max-w-[320px] text-[12px] text-muted">{r.notes ?? "—"}</span> },
    { key: "id", header: "Report", render: (r) => <IdLink kind="report" id={r.id} /> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(r, i) => r.id ?? `${i}`} basePath={basePath} emptyText="None." caption="Reports" dense />;
}

function FlagTable({ rows, basePath }: { rows: JsonRecord[]; basePath: string }) {
  const columns: Column<JsonRecord>[] = [
    { key: "created_at", header: "Raised", render: (r) => <DateTime value={r.created_at} /> },
    { key: "flag_type", header: "Flag", render: (r) => <span className="font-mono text-[12px]">{str(r.flag_type) ?? "—"}</span> },
    { key: "severity", header: "Severity", render: (r) => <StatusBadge status={str(r.severity)} variant={str(r.severity) === "critical" ? "danger" : str(r.severity) === "warning" ? "warn" : "neutral"} /> },
    { key: "details", header: "Details", render: (r) => <span className="line-clamp-2 max-w-[320px] text-[12px] text-muted">{str(r.details) ?? "—"}</span> },
    { key: "listing_id", header: "Listing", render: (r) => <IdLink kind="listing" id={str(r.listing_id)} /> },
    { key: "transfer_id", header: "Transfer", render: (r) => <IdLink kind="transfer" id={str(r.transfer_id)} /> },
    {
      key: "resolution",
      header: "Review",
      render: (r) =>
        str(r.reviewed_at) ? (
          <span className="text-[12px]">
            {str(r.resolution) ?? "reviewed"} <DateTime value={r.reviewed_at} relative={false} />
          </span>
        ) : (
          <span className="text-dim">unreviewed</span>
        ),
    },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(r, i) => str(r.id) ?? `${i}`} basePath={basePath} emptyText="No seller flags." caption="Seller flags" dense />;
}
