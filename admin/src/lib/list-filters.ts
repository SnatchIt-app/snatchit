import { num } from "@/lib/types";
import { toListPage } from "@/lib/types";

/** The Cases page's filter params, as list_cases reads them. */
export type CaseParams = Partial<Record<"status" | "priority" | "assignee" | "case_type" | "subject_kind" | "subject_id", string>>;

/**
 * list_cases reads `assignee` as 'me' | 'unassigned' | <uuid>. "Me" is sent as
 * the operator's id; "unassigned" must travel as assignee='unassigned' — a
 * separate `unassigned` key is ignored by the function, which then returns
 * assigned cases too.
 */
export function caseFilters(p: CaseParams, meId: string): Record<string, unknown> {
  const f: Record<string, unknown> = {};
  if (p.status) f.status = p.status.split(",");
  if (p.priority) f.priority = p.priority.split(",");
  if (p.case_type) f.case_type = p.case_type.split(",");
  if (p.subject_kind) f.subject_kind = p.subject_kind;
  if (p.subject_id) f.subject_id = p.subject_id;
  if (p.assignee === "me") f.assignee = meId;
  else if (p.assignee) f.assignee = p.assignee;
  return f;
}

/**
 * A list read's total, or null when it cannot be known. count_hint is computed
 * only for the first page (and omitted for some filters); without it, the page
 * length is the total only when this is the first and only page.
 */
export function listTotal(r: { ok: boolean; data?: unknown }, onLaterPage: boolean): number | null {
  if (onLaterPage || !r.ok || typeof r.data !== "object" || r.data === null) return null;
  const hint = num((r.data as Record<string, unknown>).count_hint);
  if (hint !== null) return hint;
  const page = toListPage(r.data);
  return page.next_cursor ? null : page.items.length;
}
