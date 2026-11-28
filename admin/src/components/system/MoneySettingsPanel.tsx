import { newIdempotencyKey } from "@/lib/idempotency";
import { shortId } from "@/lib/format";
import { showValue, type MoneyConfigList, type MoneyConfigRequest } from "@/lib/money-config";
import { KeyValue } from "@/components/ui/KeyValue";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { Alert } from "@/components/ui/Alert";
import { MoneyDecisionForm, MoneyRequestForm } from "@/components/system/MoneyConfigForms";

/**
 * Money settings: pending money-key requests (decided by a different founder)
 * and the request form. platform_admin only — the page renders this only for
 * admins, and the database refuses everyone else (ops.list_config_approvals).
 */
export function MoneySettingsPanel({ list, meId }: { list: MoneyConfigList; meId: string }) {
  const pending = list.items.filter((r) => r.state === "pending");
  // The list is newest first; a decided request leaves `pending`, so the last few decisions stay visible here.
  const recent = list.items.filter((r) => r.state !== "pending").slice(0, 5);
  return (
    <div className="space-y-6">
      {pending.length === 0 ? (
        <p className="text-dim">No money-key requests awaiting a decision.</p>
      ) : (
        <div className="space-y-5">
          {pending.map((r) => (
            <MoneyRequestCard key={r.request_id} request={r} />
          ))}
        </div>
      )}
      {recent.length > 0 ? (
        <div className="border-t border-line-neutral pt-4">
          <h3 className="eyebrow text-dim">Recently decided</h3>
          <ul className="mt-2 divide-y divide-line-neutral text-[12px]">
            {recent.map((r) => (
              <li key={r.request_id} className="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-2">
                <StatusBadge status={r.state} />
                <code className="font-mono text-ink">{r.key ?? "—"}</code>
                <span className="text-dim">
                  {showValue(r.value_at_request)} → {showValue(r.proposed_value)}
                </span>
                <span className="text-dim">
                  requested by {r.requested_by_me ? "me" : shortId(r.requested_by)}
                  {r.decided_by ? <> · decided by {r.decided_by === meId ? "me" : shortId(r.decided_by)}</> : null} <TimeAgo value={r.updated_at} />
                </span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      <MoneyKeysOverview keys={list.money_keys} />
      <div className="border-t border-line-neutral pt-4">
        <h3 className="eyebrow text-dim">Request a change</h3>
        <p className="mt-1 text-[12px] text-muted">
          A loosening waits for a different founder to approve. A tightening applies at once. The server decides which it is and records you as the requester.
        </p>
        <div className="mt-3 max-w-xl">
          {list.money_keys.length === 0 ? (
            <Alert state="empty" title="No money keys were returned." compact />
          ) : (
            <MoneyRequestForm moneyKeys={list.money_keys} commandKey={newIdempotencyKey()} />
          )}
        </div>
      </div>
    </div>
  );
}

/** Every money key's live value, always visible (the request form only shows one key at a time). */
function MoneyKeysOverview({ keys }: { keys: MoneyConfigList["money_keys"] }) {
  if (keys.length === 0) return null;
  return (
    <div className="border-t border-line-neutral pt-4">
      <table className="w-full text-left text-[0.75rem]">
        <caption className="eyebrow mb-2 text-left text-dim">Live values ({keys.length} money keys)</caption>
        <thead>
          <tr className="border-b border-line-neutral text-dim">
            <th scope="col" className="py-1 pr-3 font-normal">Key</th>
            <th scope="col" className="py-1 pr-3 font-normal">Live value</th>
            <th scope="col" className="py-1 font-normal">Version</th>
          </tr>
        </thead>
        <tbody>
          {keys.map((k) => (
            <tr key={k.key} className="border-b border-line-neutral">
              <td className="py-1 pr-3">
                <code className="break-all font-mono text-[0.6875rem] text-ink">{k.key}</code>
              </td>
              <td className="py-1 pr-3">
                <code className={`font-mono ${k.value === null ? "text-dim" : "text-ink"}`}>{k.value === null ? "unset" : showValue(k.value)}</code>
              </td>
              <td className="py-1 tabular-nums text-dim">{k.version ?? "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function MoneyRequestCard({ request: r }: { request: MoneyConfigRequest }) {
  const expired = r.is_expired === true;
  return (
    <div className="border border-line-neutral p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="text-[14px] font-semibold text-ink">
          <code className="font-mono">{r.key ?? "—"}</code>{" "}
          <span className="text-dim">
            {showValue(r.value_at_request)} → <span className="text-ink">{showValue(r.proposed_value)}</span>
          </span>
        </p>
        <span className="text-[12px] text-dim">
          requested by {r.requested_by_me ? "me" : shortId(r.requested_by)} <TimeAgo value={r.created_at} /> · expires <TimeAgo value={r.expires_at} />
        </span>
      </div>
      <KeyValue
        columns={3}
        items={[
          { key: "reason", label: "Requester's reason", value: r.reason_code },
          { key: "live", label: "Live value now", value: <code className="font-mono text-[12px]">{showValue(r.live_value)}</code> },
          {
            key: "unchanged",
            label: "Key unchanged since request",
            value:
              r.key_changed_since_request === true ? (
                <StatusBadge status="stale" label={`changed — v${r.version_at_request ?? "?"} → v${r.live_version ?? "?"}`} />
              ) : (
                <StatusBadge status="ok" label="yes" />
              ),
          },
          { key: "request", label: "Request", value: <code className="font-mono text-[11px]">{r.request_id}</code> },
        ]}
      />
      {r.key_changed_since_request === true ? (
        <p className="mt-2 text-[12px] text-warning">The key changed after this request was made. Approving writes the proposed value over the live value. If you do not want that, deny it and request again.</p>
      ) : null}
      <div className="mt-3">
        {r.requested_by_me ? (
          <Alert state="info" title="You requested this — a different founder must decide." compact />
        ) : expired ? (
          <Alert state="info" title="This request has expired and can no longer be decided." compact />
        ) : !r.can_decide ? (
          <Alert state="info" title="This request cannot be decided by you (expired or already decided)." compact />
        ) : (
          <div className="grid gap-4 md:grid-cols-2">
            <MoneyDecisionForm requestId={r.request_id} decision="approve" commandKey={newIdempotencyKey()} label="Approve and apply" danger />
            <MoneyDecisionForm requestId={r.request_id} decision="deny" commandKey={newIdempotencyKey()} label="Deny" />
          </div>
        )}
      </div>
    </div>
  );
}
