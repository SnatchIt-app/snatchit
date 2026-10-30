import type { Metadata } from "next";
import Link from "next/link";
import { callOps } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { toSearchHits, type SearchHit } from "@/lib/types";
import { first, type SearchParams } from "@/lib/search-params";
import { subjectHref } from "@/lib/routes";
import { humanize } from "@/lib/format";
import { PageHeader } from "@/components/ui/PageHeader";
import { Panel } from "@/components/ui/Panel";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { DataTable, type Column } from "@/components/ui/DataTable";
import { StatusBadge } from "@/components/ui/StatusBadge";

export const metadata: Metadata = { title: "Search" };
export const dynamic = "force-dynamic";

const KIND_ORDER = ["payment", "transfer", "listing", "user", "dispute", "case", "action"];
const KIND_TITLES: Record<string, string> = {
  payment: "Payments / orders",
  transfer: "Transfers",
  listing: "Listings",
  user: "Users",
  dispute: "Stripe disputes",
  case: "Cases",
  action: "Actions",
};

export default async function SearchPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  await requireOperator();
  const q = (first(sp.q) ?? "").trim().slice(0, 200);

  if (!q) {
    return (
      <>
        <PageHeader eyebrow="Find" title="Search" description="Payments (id, pi_), transfers (id, tr_), listings (id, event name), users (id, display name, exact email/phone), Stripe disputes (dp_), refunds (re_)." />
        <Alert state="empty" title="Type in the search box above (or press /) and hit Enter." />
      </>
    );
  }

  const res = await callOps<unknown>("search", { p_q: q, p_limit: 50 });
  if (!res.ok) {
    return (
      <>
        <PageHeader eyebrow="Find" title={`Search: ${q}`} />
        <OpsFailureAlert failure={res} fn="search" retryHref={`/search?q=${encodeURIComponent(q)}`} />
      </>
    );
  }
  const hits = toSearchHits(res.data);
  const groups = new Map<string, SearchHit[]>();
  for (const h of hits) {
    const k = h.kind ?? "other";
    groups.set(k, [...(groups.get(k) ?? []), h]);
  }
  const ordered = [...groups.entries()].sort(([a], [b]) => {
    const ia = KIND_ORDER.indexOf(a);
    const ib = KIND_ORDER.indexOf(b);
    return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
  });

  // One exact hit → the operator almost certainly wants that page.
  const only = hits.length === 1 ? subjectHref(hits[0].kind, hits[0].id) : null;

  return (
    <>
      <PageHeader
        eyebrow="Find"
        title={`Search: ${q}`}
        meta={
          <>
            {hits.length} hit{hits.length === 1 ? "" : "s"} across {groups.size} kind{groups.size === 1 ? "" : "s"}
            {only ? (
              <>
                {" · "}
                <Link href={only} className="link">
                  Open the only match →
                </Link>
              </>
            ) : null}
          </>
        }
      />
      {hits.length === 0 ? (
        <Alert state="empty" title="No matches.">
          Ids must be exact or a prefix of 8+ hex characters; emails and phones must match exactly (they are never searched by substring).
        </Alert>
      ) : (
        <div className="space-y-6">
          {ordered.map(([kind, rows]) => (
            <Panel key={kind} eyebrow={`${rows.length} hit${rows.length === 1 ? "" : "s"}`} title={KIND_TITLES[kind] ?? humanize(kind)}>
              <HitTable rows={rows} kind={kind} q={q} />
            </Panel>
          ))}
        </div>
      )}
    </>
  );
}

function HitTable({ rows, kind, q }: { rows: SearchHit[]; kind: string; q: string }) {
  const columns: Column<SearchHit>[] = [
    {
      key: "label",
      header: "Match",
      render: (h) => {
        const href = subjectHref(h.kind, h.id);
        const text = h.label ?? h.id ?? "—";
        return href ? (
          <Link href={href} className="link font-medium">
            {text}
          </Link>
        ) : (
          <span>{text}</span>
        );
      },
    },
    { key: "sub", header: "Detail", render: (h) => <span className="text-muted">{h.sub ?? "—"}</span> },
    { key: "status", header: "Status", render: (h) => <StatusBadge status={h.status} /> },
    { key: "id", header: "ID", render: (h) => <code className="font-mono text-[11px] text-dim">{h.id ?? "—"}</code> },
  ];
  return <DataTable columns={columns} rows={rows} rowKey={(h, i) => `${kind}-${h.id ?? i}`} basePath="/search" searchParams={{ q }} emptyText="No matches." caption={`${kind} results`} dense />;
}
