import Link from "next/link";
import type { ReactNode } from "react";
import type { Operator } from "@/lib/auth/session";
import { newIdempotencyKey } from "@/lib/idempotency";
import { canRequest } from "@/lib/permissions";
import { ACTION_STATE_LABELS, DISPUTE_OUTCOME_LABELS, labelFor } from "@/lib/format";
import type { OpsAction, OrderDetail } from "@/lib/types";
import type { MoneyGuards, PendingGuard } from "@/lib/pending-actions";
import { Panel } from "@/components/ui/Panel";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { Money } from "@/components/ui/Money";
import { Alert } from "@/components/ui/Alert";
import { ConfirmForm } from "@/components/ui/ConfirmForm";
import { NewCaseForm } from "@/components/cases/NewCaseForm";

/** Kept importable from here for existing callers; the logic lives in lib/pending-actions. */
export { unsettledAction } from "@/lib/pending-actions";

function PendingRequest({ action }: { action: OpsAction }) {
  return (
    <Alert state="info" title={`Already requested — ${ACTION_STATE_LABELS[action.state ?? ""] ?? action.state}`} compact>
      Nothing more can be requested here until it finishes.{" "}
      {action.id ? (
        <Link href={`/actions/${action.id}`} className="link">
          Track action
        </Link>
      ) : null}
    </Alert>
  );
}

/**
 * list_actions could not confirm that nothing is pending. The form stays
 * hidden: re-offering it could park a second request for the same money.
 */
function GuardUnverified({ path }: { path: string }) {
  return (
    <Alert state="failed" title="Couldn't check for an earlier request" retryHref={path} retryLabel="Try again" compact>
      The request form is hidden until ops.list_actions answers, so a second request cannot be parked by mistake. Nothing was changed.
    </Alert>
  );
}

/** pending → the existing request; clear → the form; anything else (failed read, missing guard) → hidden. */
function guarded(guard: PendingGuard | null, path: string, form: ReactNode) {
  if (guard?.kind === "pending") return <PendingRequest action={guard.action} />;
  if (guard?.kind === "clear") return form;
  return <GuardUnverified path={path} />;
}

/** The order's state-changing actions: dispute resolution, payout release, refund execution, a manual case. */
export function OrderActions({
  d,
  me,
  path,
  refundEnabled,
  disputeOpen,
  canRelease,
  canRefund,
  guards,
}: {
  d: OrderDetail;
  me: Pick<Operator, "role">;
  path: string;
  refundEnabled: boolean;
  disputeOpen: boolean;
  canRelease: boolean;
  canRefund: boolean;
  /** From loadMoneyGuards(): list_actions plus the rows already read. Required, so no caller can skip the check. */
  guards: MoneyGuards;
}) {
  const p = d.payment!;
  const t = d.transfer;
  const nothing = !disputeOpen && !canRelease && !canRefund;
  return (
    <>
      <Panel eyebrow="Safe actions" title="Actions">
        <p className="text-[0.75rem] text-muted">
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
              <p className="text-[0.6875rem] text-dim">Buyer win / partial refund does not move money — a Refund pending case opens and the refund is executed separately.</p>
            </ConfirmForm>
          ) : (
            <Alert state="info" title="Only founders and risk operators can record dispute outcomes." compact />
          )}
        </Panel>
      ) : null}

      {canRelease && t?.id ? (
        <Panel eyebrow="Two-founder approval" title="Release held payout">
          {canRequest(me.role, "payout_release") ? (
            guarded(
              guards.release,
              path,
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
              <p className="text-[0.75rem] text-muted">
                Marks the transfer released; the payout worker creates the Stripe Transfer to the seller&apos;s connected account on its next run (not a bank payout). Requires the other founder&apos;s approval under System → Approvals; nothing changes until then.
              </p>
              <p className="text-[0.6875rem] text-dim">
                Current review status: <StatusBadge status={t.payout_review_status} label={labelFor("payout_review", t.payout_review_status ?? "none")} />
                {t.payout_risk_tier ? <> · risk tier {t.payout_risk_tier}</> : null}
              </p>
            </ConfirmForm>,
            )
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
            guarded(
              guards.refund,
              path,
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
                <p className="text-[0.75rem] text-ink">
                  Full refund of <Money cents={p.total} /> only — partial refunds are not supported by the local money model (payments records refund status, not a refunded amount; a partial would be rejected as <code className="font-mono">not_supported</code>).
                </p>
                <p className="text-[0.6875rem] text-dim">
                  Parked as awaiting approval; after the other founder approves, the ops-refund-execute function calls Stripe with a stable idempotency key. The console never calls Stripe. The payment shows “refunded” only after the webhook lands.
                </p>
              </ConfirmForm>
            </>,
            )
          )}
        </Panel>
      ) : null}

      <Panel eyebrow="Manual" title="Open a case on this order">
        <NewCaseForm subjectKind="payment" subjectId={p.id} revalidate={path} defaultTitle={d.listing?.event_name ? `${d.listing.event_name} — ` : undefined} />
      </Panel>
    </>
  );
}
