import type { ReactNode } from "react";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { DataTable, type Column, type SearchParamsLike } from "@/components/ui/DataTable";
import { KeyValue } from "@/components/ui/KeyValue";
import { Panel } from "@/components/ui/Panel";
import { Money } from "@/components/ui/Money";
import { DateTime } from "@/components/ui/DateTime";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { ReportFreshness } from "@/components/shell/Freshness";
import { humanize } from "@/lib/format";
import { callOps } from "@/lib/ops";
import { isRecord, str, type JsonRecord } from "@/lib/types";
import { subjectHref } from "@/lib/routes";
import Link from "next/link";

const MONEY_KEYS = /(_cents|amount|total|fee|volume|price|refunded|captured)$/i;
const TIME_KEYS = /(_at|_by_date|date|computed_at|timestamp)$/i;
const STATUS_KEYS = /(status|state|priority|kind|type|role|decision)$/i;

/** Route a (kind,id) pair to its detail page, when one exists (alias of subjectHref). */
export function hrefFor(kind: string | null | undefined, id: string | null | undefined): string | null {
  return subjectHref(kind, id);
}

/** Best-effort renderer for a single jsonb scalar/collection. */
export function renderValue(key: string, v: unknown, depth = 0): ReactNode {
  if (v === null || v === undefined || v === "") return <span className="text-dim">—</span>;
  if (typeof v === "boolean") return <StatusBadge status={String(v)} label={v ? "yes" : "no"} />;
  if (typeof v === "number") {
    if (MONEY_KEYS.test(key) && Number.isInteger(v)) return <Money cents={v} />;
    return <span className="tabular-nums">{v.toLocaleString("en-US")}</span>;
  }
  if (typeof v === "string") {
    if (TIME_KEYS.test(key) && !Number.isNaN(new Date(v).getTime()) && /\d{4}-\d{2}-\d{2}/.test(v)) {
      return <DateTime value={v} />;
    }
    if (STATUS_KEYS.test(key) && v.length <= 32) return <StatusBadge status={v} />;
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)) {
      const kind = key.replace(/_id$/, "");
      const href = hrefFor(kind, v);
      const short = <code className="font-mono text-[12px]">{v}</code>;
      return href ? (
        <Link href={href} className="link">
          {short}
        </Link>
      ) : (
        short
      );
    }
    if (v.length > 200) return <span className="whitespace-pre-wrap break-words">{v}</span>;
    return v;
  }
  if (Array.isArray(v)) {
    if (v.length === 0) return <span className="text-dim">[] (empty)</span>;
    if (v.every((x) => typeof x === "string" || typeof x === "number")) return v.join(", ");
    if (depth >= 1) return <code className="font-mono text-[11px]">{JSON.stringify(v).slice(0, 200)}</code>;
    return <GenericTable rows={v.filter(isRecord)} basePath="" />;
  }
  if (isRecord(v)) {
    if (depth >= 1) return <code className="whitespace-pre-wrap font-mono text-[11px]">{JSON.stringify(v, null, 1).slice(0, 400)}</code>;
    return <KeyValue columns={1} items={Object.entries(v).map(([k, val]) => ({ key: k, value: renderValue(k, val, depth + 1) }))} />;
  }
  return String(v);
}

/** Table with columns inferred from the union of keys across the first rows. */
export function GenericTable({
  rows,
  basePath,
  searchParams,
  nextCursor,
  maxColumns = 12,
}: {
  rows: JsonRecord[];
  basePath: string;
  searchParams?: SearchParamsLike;
  nextCursor?: string | null;
  maxColumns?: number;
}) {
  const keys: string[] = [];
  for (const r of rows.slice(0, 50)) for (const k of Object.keys(r)) if (!keys.includes(k)) keys.push(k);
  // id first, timestamps last, cap the width.
  keys.sort((a, b) => (a === "id" ? -1 : b === "id" ? 1 : TIME_KEYS.test(a) === TIME_KEYS.test(b) ? 0 : TIME_KEYS.test(a) ? 1 : -1));
  const shown = keys.slice(0, maxColumns);
  const columns: Column<JsonRecord>[] = shown.map((k) => ({
    key: k,
    header: humanize(k),
    align: MONEY_KEYS.test(k) ? "right" : "left",
    render: (row) => renderValue(k, row[k], 1),
  }));
  return (
    <DataTable
      columns={columns}
      rows={rows}
      rowKey={(r, i) => str(r.id) ?? `${i}`}
      basePath={basePath}
      searchParams={searchParams}
      nextCursor={nextCursor}
      dense
    />
  );
}

/**
 * Generic renderer for any `ops.*` jsonb payload: scalars as KeyValue,
 * arrays as tables, nested objects as panels. Lets every §3.3 page work as
 * soon as its RPC exists; the refined page replaces it later.
 */
export function GenericPayload({
  data,
  basePath,
  searchParams,
}: {
  data: unknown;
  basePath: string;
  searchParams?: SearchParamsLike;
}) {
  if (Array.isArray(data)) return <GenericTable rows={data.filter(isRecord)} basePath={basePath} searchParams={searchParams} />;
  if (!isRecord(data)) return <KeyValue items={[{ key: "value", value: renderValue("value", data) }]} />;

  const scalars: [string, unknown][] = [];
  const arrays: [string, JsonRecord[]][] = [];
  const objects: [string, JsonRecord][] = [];
  for (const [k, v] of Object.entries(data)) {
    if (Array.isArray(v)) arrays.push([k, v.filter(isRecord)]);
    else if (isRecord(v)) objects.push([k, v]);
    else scalars.push([k, v]);
  }
  const nextCursor = str(data.next_cursor);
  const computedAt = str(data.computed_at);

  return (
    <div className="space-y-6">
      {computedAt ? <ReportFreshness at={computedAt} /> : null}
      {scalars.length ? (
        <Panel eyebrow="Summary">
          <KeyValue items={scalars.filter(([k]) => k !== "next_cursor").map(([k, v]) => ({ key: k, value: renderValue(k, v) }))} columns={3} />
        </Panel>
      ) : null}
      {objects.map(([k, v]) => (
        <Panel key={k} eyebrow="Object" title={humanize(k)}>
          <KeyValue items={Object.entries(v).map(([kk, vv]) => ({ key: kk, value: renderValue(kk, vv, 1) }))} columns={3} />
        </Panel>
      ))}
      {arrays.map(([k, rows]) => (
        <Panel key={k} eyebrow={`${rows.length} row${rows.length === 1 ? "" : "s"}`} title={humanize(k)}>
          <GenericTable rows={rows} basePath={basePath} searchParams={searchParams} nextCursor={k === "items" ? nextCursor : undefined} />
        </Panel>
      ))}
    </div>
  );
}

/** Calls the RPC and renders either the failure alert or the generic payload. */
export async function GenericRpc({
  fn,
  args,
  basePath,
  searchParams,
}: {
  fn: string;
  args?: Record<string, unknown>;
  basePath: string;
  searchParams?: SearchParamsLike;
}) {
  const res = await callOps<unknown>(fn, args);
  if (!res.ok) return <OpsFailureAlert failure={res} fn={fn} retryHref={basePath} />;
  return (
    <>
      <p className="mb-3 font-mono text-[11px] text-dim">ops.{fn}()</p>
      <GenericPayload data={res.data} basePath={basePath} searchParams={searchParams} />
    </>
  );
}
