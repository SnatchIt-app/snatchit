import type { Metadata } from "next";
import Link from "next/link";
import { callOps, type OpsResult } from "@/lib/ops";
import { requireOperator } from "@/lib/auth/session";
import { CASE_PRIORITIES, CASE_STATUSES, num, toCase, toCaseDetail, toListPage, type OpsCase } from "@/lib/types";
import { cursorOf, first, limitOf, list, type SearchParams } from "@/lib/search-params";
import { humanize } from "@/lib/format";
import { PageHeader } from "@/components/ui/PageHeader";
import { OpsFailureAlert } from "@/components/ui/Alert";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TimeAgo } from "@/components/ui/DateTime";
import { Icon, type IconName } from "@/components/ui/Icon";
import { NewCaseForm } from "@/components/cases/NewCaseForm";
import { CaseSplit } from "@/components/cases/CaseSplit";
import { CaseControls, CaseFacts, CaseNotes, assigneeName, caseEnvelope } from "@/components/cases/CaseWork";

export const metadata: Metadata = { title: "Cases" };
export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACTIVE = "open,in_progress,waiting";
const KEYS = ["status", "priority", "assignee", "case_type", "subject_kind", "subject_id"] as const;
type Key = (typeof KEYS)[number];
type Params = Partial<Record<Key, string>>;

/**
 * Saved views: the questions an operator brings to the queue. Each is only a
 * preset of the filters below, with how many cases it holds right now.
 */
const VIEWS: { key: string; label: string; hint: string; icon: IconName; params: Params }[] = [
  { key: "active", label: "Open", hint: "Open, in progress or waiting", icon: "case", params: { status: ACTIVE } },
  { key: "unowned", label: "Needs an owner", hint: "Open and unassigned", icon: "users", params: { status: ACTIVE, assignee: "unassigned" } },
  { key: "urgent", label: "Urgent", hint: "Open at priority P1", icon: "alert", params: { status: ACTIVE, priority: "p1" } },
  { key: "mine", label: "Assigned to me", hint: "Open and yours", icon: "check", params: { status: ACTIVE, assignee: "me" } },
];

const STATUS_LABEL: Record<string, string> = { open: "Open", in_progress: "In progress", waiting: "Waiting", resolved: "Resolved", dismissed: "Dismissed" };
const ASSIGNEE_LABEL: Record<string, string> = { me: "Me", unassigned: "Unassigned" };

function href(params: Record<string, string | undefined>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) q.set(k, v);
  const s = q.toString();
  return s ? `/cases?${s}` : "/cases";
}

export default async function CasesPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const me = await requireOperator();

  const status = list(sp.status)?.filter((s) => (CASE_STATUSES as string[]).includes(s));
  const priority = list(sp.priority)?.filter((p) => (CASE_PRIORITIES as string[]).includes(p));
  const assigneeRaw = first(sp.assignee);
  const caseType = list(sp.case_type);
  const subjectKind = first(sp.subject_kind);
  const subjectId = first(sp.subject_id);
  const openRaw = first(sp.open);
  const open = openRaw && UUID.test(openRaw) ? openRaw : null;
  const cursor = cursorOf(sp);

  const applied: Params = {
    status: status?.length ? status.join(",") : undefined,
    priority: priority?.length ? priority.join(",") : undefined,
    assignee: assigneeRaw === "me" || assigneeRaw === "unassigned" || (assigneeRaw && UUID.test(assigneeRaw)) ? assigneeRaw : undefined,
    case_type: caseType?.length ? caseType.join(",") : undefined,
    subject_kind: subjectKind,
    subject_id: subjectId && UUID.test(subjectId) ? subjectId : undefined,
  };
  const toFilters = (p: Params) => {
    const f: Record<string, unknown> = {};
    if (p.status) f.status = p.status.split(",");
    if (p.priority) f.priority = p.priority.split(",");
    if (p.case_type) f.case_type = p.case_type.split(",");
    if (p.subject_kind) f.subject_kind = p.subject_kind;
    if (p.subject_id) f.subject_id = p.subject_id;
    if (p.assignee === "me") f.assignee = me.id;
    else if (p.assignee === "unassigned") f.unassigned = true;
    else if (p.assignee) f.assignee = p.assignee;
    return f;
  };

  const [res, detailRes, ...viewRes] = await Promise.all([
    callOps<unknown>("list_cases", { p_filters: toFilters(applied), p_cursor: cursor, p_limit: limitOf(sp) }),
    open ? callOps<unknown>("case_detail", { p_case_id: open }) : Promise.resolve(null),
    ...VIEWS.map((v) => callOps<unknown>("list_cases", { p_filters: toFilters(v.params), p_cursor: null, p_limit: 1 })),
  ]);
  const countOf = (r: OpsResult<unknown>) => (r.ok && typeof r.data === "object" && r.data !== null ? num((r.data as Record<string, unknown>).count_hint) : null);

  const page = res.ok ? toListPage(res.data) : null;
  const rows: OpsCase[] = page ? page.items.map(toCase).filter((c): c is OpsCase => c !== null) : [];
  const total = cursor ? null : countOf(res);

  const same = (p: Params) => KEYS.every((k) => (p[k] ?? undefined) === applied[k]);
  const activeView = VIEWS.find((v) => same(v.params))?.key ?? null;
  const chips = chipList(applied);
  const keep = { ...applied, cursor: cursor ?? undefined };
  const openHref = (id: string) => href({ ...keep, open: id });
  const closeHref = href(keep);
  const at = open ? rows.findIndex((r) => r.id === open) : -1;
  const prev = at > 0 ? rows[at - 1] : null;
  const next = at >= 0 && at < rows.length - 1 ? rows[at + 1] : null;
  const meRef = { id: me.id, label: me.whoami.email_masked ?? me.email ?? me.id.slice(0, 8) };

  return (
    <>
      <PageHeader
        eyebrow="Work"
        title="Cases"
        meta={total !== null ? `${total.toLocaleString("en-US")}${chips.length ? " matching" : ""} case${total === 1 ? "" : "s"}` : undefined}
        description="Detector-raised and manual cases across payments, transfers, disputes, users, and jobs."
        actions={
          <details data-popover className="relative">
            <summary className="btn btn-ghost">
              <Icon name="plus" size={16} />
              New manual case
            </summary>
            <div className="popover glass glass-solid right-0 w-[min(28rem,calc(100vw-2rem))] p-5">
              <p className="title-section text-[1.25rem]">New manual case</p>
              <p className="mb-4 mt-1 text-[0.8125rem] text-muted">A free-standing case with no subject. To attach a case to an order, listing or user, open it from that record&apos;s page.</p>
              <NewCaseForm subjectKind="none" revalidate="/cases" />
            </div>
          </details>
        }
      />

      <nav aria-labelledby="views-h" className={`enter-2 mb-6 ${open ? "hidden xl:block" : ""}`}>
        <h2 id="views-h" className="sr-only">
          Saved views
        </h2>
        <ul className="grid grid-cols-2 gap-px overflow-hidden rounded-[20px] border border-[rgba(70,50,30,0.09)] bg-[rgba(70,50,30,0.09)] xl:grid-cols-4">
          {VIEWS.map((v, i) => {
            const n = countOf(viewRes[i]);
            const on = activeView === v.key;
            return (
              <li key={v.key} className="min-w-0">
                <Link
                  href={on ? "/cases" : href(v.params)}
                  aria-current={on ? "page" : undefined}
                  aria-label={`${v.label}: ${n ?? "count unavailable"}${on ? " — showing; select to clear" : ""}`}
                  className={`group relative flex h-full flex-col px-5 pb-4 pt-4 transition-colors md:px-6 ${on ? "bg-white" : "bg-[#fffdfa] hover:bg-white"}`}
                >
                  {on ? <span aria-hidden="true" className="absolute inset-x-5 bottom-0 h-[3px] rounded-full bg-[#26211d] md:inset-x-6" /> : null}
                  <span className="flex items-center justify-between gap-2 text-[0.875rem] text-muted group-hover:text-ink">
                    <span className="flex items-center gap-2">
                      <Icon name={v.icon} size={16} strokeWidth={1.6} className={n && v.key !== "mine" ? "text-[#a82d17]" : ""} />
                      {v.label}
                    </span>
                    <span aria-hidden="true" className="text-[0.75rem]">{on ? "Clear" : ""}</span>
                  </span>
                  {n === null ? <span className="mt-3 text-[0.9375rem] font-medium leading-[2.625rem] text-muted">Count unavailable</span> : <span className="stat-num mt-3">{n}</span>}
                  <span className="mt-2 text-[0.75rem] text-muted">{v.hint}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      <CaseSplit openId={open} closeHref={closeHref}>
        <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,28rem)_minmax(0,1fr)]">
          {/* The queue. Below xl it gives way to the open case, which carries a way back. */}
          <section aria-labelledby="queue-h" className={`panel enter-3 min-w-0 overflow-visible ${open ? "hidden xl:block" : ""}`}>
            <div className="flex flex-wrap items-center gap-2 border-b border-line p-3 md:p-4">
              <h2 id="queue-h" className="sr-only">
                {chips.length ? "Matching cases" : "All cases"}
              </h2>
              <Chip title="Status" name="status" kind="check" options={CASE_STATUSES.map((s) => [s, STATUS_LABEL[s] ?? humanize(s)])} applied={applied} />
              <Chip title="Priority" name="priority" kind="check" options={CASE_PRIORITIES.map((p) => [p, p.toUpperCase()])} applied={applied} />
              <Chip title="Assignee" name="assignee" kind="radio" options={[["me", "Me"], ["unassigned", "Unassigned"]]} applied={applied} />
              <Chip title="Type" name="case_type" kind="text" options={[]} applied={applied} />
            </div>

            {chips.length ? (
              <div className="flex flex-wrap items-center gap-2 border-b border-line px-3 py-2.5 md:px-4">
                <span className="text-[0.75rem] font-medium text-muted">Showing</span>
                {chips.map((c) => (
                  <Link
                    key={c.key}
                    href={href({ ...applied, [c.key]: undefined, ...(c.key === "subject_kind" ? { subject_id: undefined } : {}) })}
                    className="badge gap-1.5 py-1 pr-1.5 transition-colors hover:border-[rgba(28,25,23,0.4)]"
                    aria-label={`Remove filter: ${c.label}`}
                  >
                    {c.label}
                    <span aria-hidden="true" className="grid h-4 w-4 place-items-center rounded-full bg-[#efece7]">
                      <Icon name="close" size={10} strokeWidth={2.5} />
                    </span>
                  </Link>
                ))}
                <Link href="/cases" className="ml-1 rounded-full px-2 text-[0.8125rem] font-medium text-muted underline-offset-4 hover:text-ink hover:underline">
                  Clear all
                </Link>
              </div>
            ) : null}

            {!res.ok ? (
              <div className="p-3">
                <OpsFailureAlert failure={res} fn="list_cases" retryHref={href(applied)} subject="Cases" />
              </div>
            ) : rows.length === 0 ? (
              <div className="flex flex-col items-center px-6 py-14 text-center">
                <span className="grid h-12 w-12 place-items-center rounded-full bg-[#f5f3ef]">
                  <Icon name={chips.length ? "filter" : "check"} size={20} />
                </span>
                <p className="title-section mt-4">{chips.length ? "No cases match these filters." : "No cases."}</p>
                <p className="mt-1 max-w-sm text-[0.875rem] text-muted">{chips.length ? "Remove a filter, or choose another view." : "Detectors open cases here when something needs a person."}</p>
                {chips.length ? (
                  <Link href="/cases" className="btn btn-ghost mt-5">
                    Show all cases
                  </Link>
                ) : null}
              </div>
            ) : (
              <>
                <p id="queue-keys" className="sr-only">
                  Use the up and down arrow keys to move between cases, Enter to open one, and Escape to close it.
                </p>
                <ul aria-describedby="queue-keys" className="flex flex-col gap-0.5 p-1.5">
                  {rows.map((c, i) => (
                    <CaseRow key={c.id ?? i} c={c} meId={me.id} href={c.id ? openHref(c.id) : null} selected={!!c.id && c.id === open} />
                  ))}
                </ul>
              </>
            )}

            {page && (page.next_cursor || cursor) ? (
              <div className="flex items-center justify-between gap-2 border-t border-line p-3">
                {cursor ? (
                  <Link href={href(applied)} className="btn btn-ghost btn-sm">
                    First page
                  </Link>
                ) : (
                  <span />
                )}
                {page.next_cursor ? (
                  <Link href={href({ ...applied, cursor: page.next_cursor })} className="btn btn-ghost btn-sm">
                    Older cases
                    <Icon name="chevron" size={14} />
                  </Link>
                ) : null}
              </div>
            ) : null}
          </section>

          {/* The open case — or, on wide screens, where it will appear. */}
          <section
            aria-labelledby={open ? "case-pane-title" : undefined}
            aria-label={open ? undefined : "Case detail"}
            className={`panel glass-solid enter-3 min-w-0 xl:sticky xl:top-24 ${open ? "" : "hidden xl:block"}`}
          >
            {open && detailRes ? (
              <CasePane id={open} res={detailRes} me={meRef} closeHref={closeHref} prev={prev?.id ? openHref(prev.id) : null} next={next?.id ? openHref(next.id) : null} />
            ) : (
              <div className="flex flex-col items-center px-8 py-20 text-center">
                <span className="grid h-12 w-12 place-items-center rounded-full bg-[#f5f3ef]">
                  <Icon name="case" size={20} />
                </span>
                <p className="title-section mt-4">Choose a case</p>
                <p className="mt-1 max-w-xs text-[0.875rem] text-muted">Its details, owner, status and notes open here, next to the queue.</p>
              </div>
            )}
          </section>
        </div>
      </CaseSplit>
    </>
  );
}

const PRIORITY_TINT: Record<string, string> = {
  p1: "bg-[#f7e0da] text-[#a82d17]",
  p2: "bg-[#fbead6] text-[#8f4605]",
};

/** One case in the queue: priority, the problem, where it comes from, who has it. */
function CaseRow({ c, meId, href, selected }: { c: OpsCase; meId: string; href: string | null; selected: boolean }) {
  const who = assigneeName(c, meId);
  const closed = c.status === "resolved" || c.status === "dismissed";
  const body = (
    <>
      <span className={`status-icon mt-0.5 ${PRIORITY_TINT[c.priority ?? ""] ?? "bg-[rgba(70,50,30,0.07)] text-[rgba(35,30,26,0.72)]"}`} aria-hidden="true">
        <Icon name={closed ? "check" : c.priority === "p1" ? "alert" : c.priority === "p2" ? "clock" : "flag"} size={16} strokeWidth={2} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-start justify-between gap-3">
          <span className={`line-clamp-2 text-[0.9375rem] font-medium leading-snug ${closed ? "text-muted" : ""}`}>{c.title ?? humanize(c.case_type ?? "Case")}</span>
          <span className="shrink-0 pt-0.5 text-[0.75rem] text-muted">
            <TimeAgo value={c.detected_at ?? c.created_at} />
          </span>
        </span>
        <span className="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-[0.8125rem] text-muted">
          <StatusBadge status={c.priority} />
          {c.status !== "open" ? <StatusBadge status={c.status} /> : null}
          <span title={c.case_type}>{c.case_type ? humanize(c.case_type) : "Manual"}</span>
          <span aria-hidden="true">·</span>
          <span className={who === "me" ? "font-medium text-ink" : ""}>{who ?? "Unassigned"}</span>
          {c.due_at && !closed ? (
            <>
              <span aria-hidden="true">·</span>
              <span>
                Due <TimeAgo value={c.due_at} />
              </span>
            </>
          ) : null}
        </span>
      </span>
    </>
  );
  return (
    <li>
      {href ? (
        <Link
          href={href}
          scroll={false}
          data-case-link={c.id}
          aria-current={selected ? "true" : undefined}
          className={`relative flex items-start gap-3.5 rounded-[14px] px-3 py-3 transition-colors ${selected ? "bg-white shadow-[0_1px_2px_rgba(40,30,20,0.06)] ring-1 ring-[rgba(70,50,30,0.12)]" : "hover:bg-[rgba(255,255,255,0.6)]"}`}
        >
          {selected ? <span aria-hidden="true" className="absolute inset-y-3 left-0 w-[3px] rounded-full bg-[#26211d]" /> : null}
          {body}
        </Link>
      ) : (
        <div className="flex items-start gap-3.5 px-3 py-3">{body}</div>
      )}
    </li>
  );
}

/** The detail pane: what the case is, its facts, the work on it, and its notes. */
function CasePane({
  id,
  res,
  me,
  closeHref,
  prev,
  next,
}: {
  id: string;
  res: OpsResult<unknown>;
  me: { id: string; label: string };
  closeHref: string;
  prev: string | null;
  next: string | null;
}) {
  const nav = (
    <div className="flex items-center justify-between gap-2 border-b border-line px-5 py-3 md:px-6">
      <Link href={closeHref} scroll={false} className="btn btn-ghost btn-sm xl:hidden">
        <Icon name="back" size={14} />
        All cases
      </Link>
      <Link href={closeHref} scroll={false} className="hidden rounded-lg text-[0.8125rem] text-muted hover:text-ink xl:inline">
        Close <span className="kbd ml-1">Esc</span>
      </Link>
      <span className="flex items-center gap-1">
        {prev ? (
          <Link href={prev} scroll={false} className="btn-icon" aria-label="Previous case">
            <Icon name="back" size={16} />
          </Link>
        ) : null}
        {next ? (
          <Link href={next} scroll={false} className="btn-icon" aria-label="Next case">
            <Icon name="chevron" size={16} />
          </Link>
        ) : null}
      </span>
    </div>
  );

  if (!res.ok) {
    return (
      <>
        {nav}
        <div className="p-5 md:p-6">
          <h2 id="case-pane-title" tabIndex={-1} className="title-section outline-none">
            Case {id.slice(0, 8)}
          </h2>
          <div className="mt-4">
            <OpsFailureAlert failure={res} fn="case_detail" retryHref={href({ open: id })} subject="This case" />
          </div>
        </div>
      </>
    );
  }
  const detail = toCaseDetail(res.data);
  if (!detail || !detail.case) {
    return (
      <>
        {nav}
        <div className="p-5 md:p-6">
          <h2 id="case-pane-title" tabIndex={-1} className="title-section outline-none">
            No case with this id.
          </h2>
          <p className="mt-2 text-[0.875rem] text-muted">It may have been removed, or the link is wrong.</p>
        </div>
      </>
    );
  }
  const c = detail.case;
  const envelope = caseEnvelope(c, id, "/cases");
  const closed = c.status === "resolved" || c.status === "dismissed";
  return (
    <>
      {nav}
      <div className="flex flex-col gap-6 px-5 pb-6 pt-5 md:px-6">
        <div>
          <p className="kicker" title={c.case_type}>
            {c.case_type ? humanize(c.case_type) : "Manual case"}
          </p>
          <h2 id="case-pane-title" tabIndex={-1} className="title-display mt-1 text-[1.75rem] leading-tight outline-none">
            {c.title ?? humanize(c.case_type ?? "Case")}
          </h2>
          <div className="mt-2.5 flex flex-wrap items-center gap-2">
            <StatusBadge status={c.status} />
            <StatusBadge status={c.priority} />
          </div>
          {c.summary ? <p className="mt-3 text-[0.9375rem] leading-relaxed text-muted">{c.summary}</p> : null}
          {closed ? <p className="mt-3 text-[0.875rem] font-medium">This case is {c.status}.</p> : null}
        </div>

        <CaseFacts c={c} meId={me.id} notes={detail.notes.length} />

        <section aria-labelledby="pane-work-h">
          <h3 id="pane-work-h" className="mb-1 text-[0.8125rem] font-semibold">
            Work this case
          </h3>
          <CaseControls c={c} detail={detail} me={me} envelope={envelope} idPrefix="pane" />
        </section>

        <section aria-labelledby="pane-notes-h">
          <h3 id="pane-notes-h" className="mb-3 text-[0.8125rem] font-semibold">
            Notes
          </h3>
          <CaseNotes c={c} detail={detail} meId={me.id} envelope={envelope} idPrefix="pane" limit={3} />
        </section>

        <div>
          <Link href={`/cases/${id}`} className="btn btn-primary btn-lg w-full">
            Open full case
            <Icon name="arrow" size={16} />
          </Link>
          <p className="mt-2 text-center text-[0.75rem] text-muted">Timeline, the subject&apos;s record and every action taken.</p>
        </div>
      </div>
    </>
  );
}

function chipList(applied: Params): { key: Key; label: string }[] {
  const out: { key: Key; label: string }[] = [];
  if (applied.status) out.push({ key: "status", label: `Status: ${applied.status.split(",").map((s) => STATUS_LABEL[s] ?? s).join(", ")}` });
  if (applied.priority) out.push({ key: "priority", label: `Priority: ${applied.priority.toUpperCase().replace(/,/g, ", ")}` });
  if (applied.assignee) out.push({ key: "assignee", label: `Assignee: ${ASSIGNEE_LABEL[applied.assignee] ?? applied.assignee.slice(0, 8)}` });
  if (applied.case_type) out.push({ key: "case_type", label: `Type: ${applied.case_type.split(",").map(humanize).join(", ")}` });
  if (applied.subject_kind || applied.subject_id)
    out.push({ key: "subject_kind", label: `About: ${applied.subject_kind ? humanize(applied.subject_kind) : "record"}${applied.subject_id ? ` ${applied.subject_id.slice(0, 8)}` : ""}` });
  return out;
}

/**
 * One chip per filter (Status ▾, Priority ▾ …) opening a small GET form for
 * that dimension alone; every other applied filter rides along as a hidden
 * field, so applying one never drops the rest.
 */
function Chip({ title, name, kind, options, applied }: { title: string; name: Key; kind: "check" | "radio" | "text"; options: [string, string][]; applied: Params }) {
  const selected = (applied[name] ?? "").split(",").filter(Boolean);
  const label =
    kind === "text"
      ? selected.length
        ? selected.map(humanize).join(", ")
        : null
      : selected.length === 1
        ? (options.find(([v]) => v === selected[0])?.[1] ?? selected[0])
        : selected.length > 1
          ? `${selected.length} selected`
          : null;
  const keepKeys = KEYS.filter((k) => k !== name);
  const choices: [string, string][] = kind === "radio" ? [["", "Anyone"], ...options] : options;
  return (
    <details data-popover className="relative">
      <summary className={`filter-chip ${selected.length ? "!bg-ink !text-white !shadow-none" : ""}`} aria-label={`${title} filter${label ? `: ${label}` : ""}`}>
        <span className={selected.length ? "text-white/70" : "text-muted"}>{title}</span>
        {label ? <span className="max-w-[9rem] truncate font-semibold">{label}</span> : null}
        <Icon name="down" size={14} />
      </summary>
      <form method="get" action="/cases" className="popover glass glass-solid left-0 w-[min(17rem,calc(100vw-2rem))] p-2">
        {keepKeys.map((k) => (applied[k] ? <input key={k} type="hidden" name={k} value={applied[k]} /> : null))}
        <fieldset className="flex flex-col gap-0.5 p-1">
          <legend className="px-1.5 pb-1 pt-1 text-[0.75rem] font-semibold text-muted">{title}</legend>
          {kind === "text" ? (
            <label htmlFor={`f-${name}`} className="grid gap-1 px-1.5 pb-1 text-[0.8125rem] text-muted">
              Case type
              <input id={`f-${name}`} name={name} defaultValue={applied[name] ?? ""} placeholder="e.g. refund_pending" className="field" />
            </label>
          ) : (
            choices.map(([v, l]) => (
              <label
                key={v || "any"}
                htmlFor={`f-${name}-${v || "any"}`}
                className="flex min-h-9 cursor-pointer items-center gap-2.5 rounded-lg px-1.5 py-1.5 text-[0.8125rem] transition-colors hover:bg-[rgba(28,25,23,0.04)]"
              >
                <input
                  id={`f-${name}-${v || "any"}`}
                  type={kind === "check" ? "checkbox" : "radio"}
                  name={name}
                  value={v}
                  defaultChecked={v ? selected.includes(v) : selected.length === 0}
                  className="h-4 w-4 shrink-0 accent-[#1c1917]"
                />
                <span>{l}</span>
              </label>
            ))
          )}
        </fieldset>
        <div className="mt-1 flex items-center justify-between gap-2 border-t border-line p-1.5 pt-2.5">
          <Link href={href({ ...applied, [name]: undefined })} className="btn btn-ghost btn-sm">
            Clear
          </Link>
          <button type="submit" className="btn btn-primary btn-sm">
            Apply
          </button>
        </div>
      </form>
    </details>
  );
}
