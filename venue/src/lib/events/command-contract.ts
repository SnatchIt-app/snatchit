/**
 * The event / session / venue command contract, as pure functions: which keys
 * each verb accepts, what the dashboard refuses before sending, and what every
 * server refusal means in the operator's words. No I/O, so each rule is a test.
 *
 * Read from the bodies on the chain (D's lists, 2026-10-26; the verbs reached
 * through 164's `venue_cmd` SECURITY INVOKER wrappers, dark until exposure):
 *   create_event(p_venue_id, p_title, p_first_session jsonb, p_command_key)
 *   update_event(p_event_id, p_patch jsonb, p_command_key)
 *   create_event_session(p_event_id, p_session jsonb, p_command_key)
 *   update_event_session(p_session_id, p_patch jsonb, p_command_key)
 *   publish_event(p_event_id, p_target_status, p_command_key)
 *   cancel_event(p_event_id, p_reason_code, p_command_key)
 *   update_venue(p_venue_id, p_patch jsonb, p_command_key)
 * and from 162: set_venue_timezone(p_venue_id, p_timezone, p_reason_code, p_command_key),
 *   set_session_sales_capacity(p_session_id, p_capacity, p_reason_code, p_command_key).
 *
 * Two rules drive the whole file. The patch verbs REFUSE an unknown key
 * (`invalid_input: unwritable_key <k>`), so the dashboard sends only the keys
 * it means. The session verbs IGNORE unknown keys silently, which is worse, so
 * the dashboard refuses them here instead of letting a typo vanish.
 */
import { toOffsetInstant, type InstantResult } from "@/lib/events/instants";

export type FieldProblem = { field: string; message: string };
export type Built<T> = { ok: true; value: T } | { ok: false; problems: FieldProblem[] };

const problem = (field: string, message: string): FieldProblem => ({ field, message });

/** `catalog.update_event`'s allowed patch keys, exactly (078:901). */
export const EVENT_PATCH_KEYS = ["title", "description", "hero_image_ref", "category", "genre_tags", "reason_code"] as const;
/** `catalog.create_event_session` / `update_event_session` keys (078:749, 093:6950). `door_open_at` has a sole writer and is not one. */
export const SESSION_KEYS = ["session_label", "starts_at", "ends_at", "doors_at", "reason_code"] as const;
/** `catalog.update_venue`'s allowed patch keys. `org_id` is deliberately absent: the server refuses it (operatorship_transfer_frozen). */
export const VENUE_PATCH_KEYS = ["name", "neighborhood", "address", "capacity_hint", "reason_code"] as const;
/** The nine CHECK values on `catalog.venue.neighborhood`. */
export const NEIGHBORHOODS = ["south beach", "wynwood", "brickell", "downtown miami", "design district", "coconut grove", "little havana", "miami beach", "midtown"] as const;
/** `catalog.publish_event` accepts only these; cancellation is `cancel_event`. */
export const PUBLISH_TARGETS = ["announced", "on_sale", "live", "completed"] as const;

export type PublishTarget = (typeof PUBLISH_TARGETS)[number];
export type EventStatusName = "draft" | PublishTarget | "cancelled";

/** The forward-only ladder the server enforces (`illegal_transition (a -> b)`). */
const LADDER: EventStatusName[] = ["draft", "announced", "on_sale", "live", "completed"];

export function nextPublishTarget(current: EventStatusName): PublishTarget | null {
  if (current === "cancelled") return null;
  const i = LADDER.indexOf(current);
  if (i < 0 || i >= LADDER.length - 1) return null;
  return LADDER[i + 1] as PublishTarget;
}

export function transitionIsLegal(current: EventStatusName, target: PublishTarget): boolean {
  return nextPublishTarget(current) === target;
}

/** A session as the operator typed it: wall clock plus the venue's zone. */
export type SessionInput = { label?: string; startsLocal: string; endsLocal?: string; doorsLocal?: string; reasonCode?: string };

/** `p_session` / `p_first_session`: starts_at is required, every time is an offset-qualified instant, unknown keys never appear. */
export function buildSessionPayload(input: SessionInput, timeZone: string): Built<Record<string, unknown>> {
  const problems: FieldProblem[] = [];
  const out: Record<string, unknown> = {};

  const label = (input.label ?? "").trim();
  if (label.length > 120) problems.push(problem("session_label", "Keep the label under 120 characters."));
  else if (label) out.session_label = label;

  const instant = (local: string, field: string): string | null => {
    const r: InstantResult = toOffsetInstant(local, timeZone);
    if (r.ok) return r.iso;
    problems.push(problem(field, instantProblemCopy(r, timeZone)));
    return null;
  };

  if (!(input.startsLocal ?? "").trim()) {
    problems.push(problem("starts_at", "A session needs a start time."));
  } else {
    const starts = instant(input.startsLocal, "starts_at");
    if (starts) out.starts_at = starts;
  }
  if ((input.endsLocal ?? "").trim()) {
    const ends = instant(input.endsLocal as string, "ends_at");
    if (ends) out.ends_at = ends;
  }
  if ((input.doorsLocal ?? "").trim()) {
    const doors = instant(input.doorsLocal as string, "doors_at");
    if (doors) out.doors_at = doors;
  }
  const reason = (input.reasonCode ?? "").trim();
  if (reason) out.reason_code = reason;

  // Orderings the server also checks: say them here, where the operator can see which field to fix.
  if (typeof out.starts_at === "string" && typeof out.ends_at === "string" && Date.parse(out.ends_at) <= Date.parse(out.starts_at)) {
    problems.push(problem("ends_at", "The end has to be after the start."));
  }
  if (typeof out.starts_at === "string" && typeof out.doors_at === "string" && Date.parse(out.doors_at) > Date.parse(out.starts_at)) {
    problems.push(problem("doors_at", "Doors cannot open after the session starts."));
  }
  if (problems.length > 0) return { ok: false, problems };
  // Nothing outside SESSION_KEYS can be present: the server would ignore it silently.
  for (const k of Object.keys(out)) if (!(SESSION_KEYS as readonly string[]).includes(k)) return { ok: false, problems: [problem(k, "That field is not part of a session.")] };
  return { ok: true, value: out };
}

export function instantProblemCopy(r: Extract<InstantResult, { ok: false }>, timeZone: string): string {
  switch (r.reason) {
    case "bad_input":
      return "Enter a date and a time.";
    case "unknown_zone":
      return `This venue's time zone (${timeZone || "not set"}) is not one the server recognises. Fix the venue's time zone first.`;
    case "nonexistent":
      return `That clock time does not exist in ${timeZone} — the clocks jump forward over it. Pick another time.`;
    case "ambiguous":
      return `That clock time happens twice in ${timeZone} — the clocks fall back over it. Pick a time an hour either side.`;
  }
}

export type EventPatchInput = { title?: string; description?: string; heroImageRef?: string; category?: string; genreTags?: string[]; reasonCode?: string };

/**
 * `p_patch` for update_event: only the keys the operator actually changed, and
 * a `reason_code` is required when the title changes on an event that is past
 * draft (`precondition_failed: reason_required for a title change after draft`).
 */
export function buildEventPatch(input: EventPatchInput, ctx: { status: EventStatusName; currentTitle?: string }): Built<Record<string, unknown>> {
  const problems: FieldProblem[] = [];
  const out: Record<string, unknown> = {};
  const set = (key: (typeof EVENT_PATCH_KEYS)[number], v: unknown) => {
    out[key] = v;
  };

  const title = input.title?.trim();
  if (title !== undefined && title !== (ctx.currentTitle ?? "").trim()) {
    if (!title) problems.push(problem("title", "An event needs a title."));
    else if (title.length > 200) problems.push(problem("title", "Keep the title under 200 characters."));
    else {
      set("title", title);
      if (ctx.status !== "draft" && !(input.reasonCode ?? "").trim()) {
        problems.push(problem("reason_code", "Changing the title after the event leaves draft needs a reason, which is recorded."));
      }
    }
  }
  if (input.description !== undefined) set("description", input.description.trim() || null);
  if (input.heroImageRef !== undefined) set("hero_image_ref", input.heroImageRef.trim() || null);
  if (input.category !== undefined) set("category", input.category.trim() || null);
  if (input.genreTags !== undefined) {
    const tags = input.genreTags.map((t) => t.trim()).filter(Boolean);
    if (tags.some((t) => t.length > 40)) problems.push(problem("genre_tags", "Keep each tag under 40 characters."));
    else set("genre_tags", tags);
  }
  const reason = (input.reasonCode ?? "").trim();
  if (reason) set("reason_code", reason);

  if (problems.length > 0) return { ok: false, problems };
  const keys = Object.keys(out).filter((k) => k !== "reason_code");
  if (keys.length === 0) return { ok: false, problems: [problem("title", "Nothing changed.")] };
  for (const k of Object.keys(out)) if (!(EVENT_PATCH_KEYS as readonly string[]).includes(k)) return { ok: false, problems: [problem(k, "The server refuses that field on an event.")] };
  return { ok: true, value: out };
}

export type VenuePatchInput = { name?: string; neighborhood?: string; address?: string; capacityHint?: string; reasonCode?: string };

/** `p_patch` for update_venue: descriptive fields only. `org_id` is never built, because sending it is refused by design. */
export function buildVenuePatch(input: VenuePatchInput): Built<Record<string, unknown>> {
  const problems: FieldProblem[] = [];
  const out: Record<string, unknown> = {};
  if (input.name !== undefined) {
    const name = input.name.trim();
    if (!name) problems.push(problem("name", "A venue needs a name."));
    else out.name = name;
  }
  if (input.neighborhood !== undefined) {
    const n = input.neighborhood.trim().toLowerCase();
    if (!n) out.neighborhood = null;
    else if (!(NEIGHBORHOODS as readonly string[]).includes(n)) problems.push(problem("neighborhood", "Choose one of the listed neighbourhoods."));
    else out.neighborhood = n;
  }
  if (input.address !== undefined) out.address = input.address.trim() || null;
  if (input.capacityHint !== undefined) {
    const raw = input.capacityHint.trim();
    if (!raw) out.capacity_hint = null;
    else if (!/^\d+$/.test(raw) || Number(raw) < 1 || Number(raw) > 2_147_483_647) problems.push(problem("capacity_hint", "Enter a whole number of people, or leave it empty."));
    else out.capacity_hint = Number(raw);
  }
  const reason = (input.reasonCode ?? "").trim();
  if (reason) out.reason_code = reason;
  if (problems.length > 0) return { ok: false, problems };
  if (Object.keys(out).filter((k) => k !== "reason_code").length === 0) return { ok: false, problems: [problem("name", "Nothing changed.")] };
  for (const k of Object.keys(out)) if (!(VENUE_PATCH_KEYS as readonly string[]).includes(k)) return { ok: false, problems: [problem(k, "The server refuses that field on a venue.")] };
  return { ok: true, value: out };
}

/** 162's sales pool: a positive integer, or empty for unlimited. A reason is required. */
export function buildSalesCapacity(raw: string, reasonCode: string): Built<{ capacity: number | null; reasonCode: string }> {
  const problems: FieldProblem[] = [];
  const v = (raw ?? "").trim();
  let capacity: number | null = null;
  if (v) {
    if (!/^\d+$/.test(v) || Number(v) < 1) problems.push(problem("capacity", "Enter a whole number above zero, or leave it empty for unlimited."));
    else capacity = Number(v);
  }
  if (!(reasonCode ?? "").trim()) problems.push(problem("reason_code", "A reason is required; it is recorded with the change."));
  return problems.length > 0 ? { ok: false, problems } : { ok: true, value: { capacity, reasonCode: reasonCode.trim() } };
}

/**
 * Every refusal these verbs raise, in words an organizer can act on. The key is
 * the server's own token, taken from the message prefix.
 */
export const REFUSAL_COPY: Record<string, string> = {
  // publish_event's five "not ready to sell" reasons
  empty_inventory: "This event has no ticket type with a release yet, so there is nothing to sell.",
  org_not_saleable: "This organization is not cleared to sell yet. Finish payout setup, then try again.",
  connect_not_ready: "Stripe has not confirmed this organization's payout account yet, so sales cannot open.",
  signing_not_ready: "Ticket signing is not ready on this project, so tickets could not be issued. The platform has to enable it.",
  fee_policy_unset: "The platform's service fee is not set yet, so a price cannot be charged. Snatch It has to set it.",
  illegal_transition: "An event moves forward one step at a time, and never backwards.",
  // shared preconditions
  event_terminal: "This event is completed or cancelled, so it can no longer be changed.",
  session_terminal: "This session is completed or cancelled, so it can no longer be changed.",
  boundary_engaged: "The door schedule for this session is already engaged, so its times are fixed.",
  move_exceeds_grace: "This session has tickets issued and the new time moves it too far. A smaller change, or a platform decision, is needed.",
  reason_required: "A reason is required for this change; it is recorded.",
  unwritable_key: "The dashboard tried to change a field the server does not accept. Nothing changed; this is a bug in the dashboard.",
  duplicate_name: "Another one here already uses that name.",
  invalid_input: "One of the values was refused. Nothing changed.",
  unknown_timezone: "That time zone is not one the server recognises.",
  operatorship_transfer_frozen: "Moving a venue to another organization is not something this dashboard does.",
  venue_not_approved: "This venue is not approved to sell yet. Snatch It has to approve it first.",
  // 162's capacity refusals
  below_allocated: "The pool cannot be smaller than what is already allocated to releases. Reduce a release first.",
  above_venue_capacity: "The pool cannot be larger than the venue's capacity. Raise the venue's capacity first, if that is right.",
  session_capacity_exceeded: "That would allocate more than the session's pool allows.",
  // authority / transport
  insufficient_privilege: "Your role at this venue cannot make that change.",
  not_found: "That is not something this account can see, or it is not there.",
};

/** The server's message → the token above. `precondition_failed: below_allocated (new=1 < allocated=5)` → `below_allocated`. */
export function refusalToken(message: string | null | undefined): string | null {
  const m = (message ?? "").trim();
  if (!m) return null;
  const afterPrefix = m.replace(/^(precondition_failed|invalid_input|not_found|insufficient_privilege)\s*:\s*/i, (p) => (/(not_found|insufficient_privilege)/i.test(p) ? p : ""));
  const token = /^([a-z_]+)/.exec(afterPrefix.trim().toLowerCase())?.[1] ?? null;
  if (token && REFUSAL_COPY[token]) return token;
  const bare = /^([a-z_]+)/.exec(m.toLowerCase())?.[1] ?? null;
  return bare && REFUSAL_COPY[bare] ? bare : null;
}

/** What the operator reads for a refusal; unknown refusals keep the server's own words rather than inventing a cause. */
export function refusalCopy(message: string | null | undefined): string {
  const token = refusalToken(message);
  if (token) return REFUSAL_COPY[token];
  const m = (message ?? "").trim();
  return m ? `The server refused this change: ${m}` : "The server refused this change. Nothing changed.";
}
