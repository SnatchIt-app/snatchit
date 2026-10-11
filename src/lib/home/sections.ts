/**
 * src/lib/home/sections.ts — the V3 Home section rule (owner 2026-09-24, pkg8 home boards).
 *
 * WHY THIS MODULE EXISTS. The approved boards head the feed with "Tonight" over the full-bleed
 * feature and "This week" over the rows. The previous revision deliberately did NOT draw them,
 * because a heading whose grouping rule is not written down is a claim the data cannot back —
 * "Tonight" over an event three weeks out is a small lie told in a large voice. The owner's
 * 2026-09-24 finding is that the boards' section labels are part of the approved Home, so the
 * rule is written down HERE, as one pure function, and the screen only draws what it returns.
 *
 * THE RULE, in full:
 *   the event falls on the device's TODAY          → "Tonight"
 *   the event falls on the next 1–7 device days    → "This week"
 *   the event falls later than that                → "Later"
 *   the event already happened, or its date is
 *   unparseable                                    → NO heading at all
 *
 * The last bucket is why this returns a nullable label rather than a string. Home's "Recently
 * sold" and "Ended" datasets are historical by construction, so every row in them lands there and
 * the feed renders exactly as it does today: rows, no headings, nothing claimed. A bucket that
 * cannot be named is never given a borrowed name.
 *
 * GROUPING REORDERS, IT NEVER FILTERS. `groupByEventDate` returns every item it was given, once,
 * and preserves the incoming order INSIDE each bucket — so the neighbourhood-preference sort and
 * the created-at order the feed query applies still decide rank within a section. Nothing here
 * reads or writes a server, and nothing here decides auction, price or payment state.
 *
 * The device calendar is the basis, matching `featureMetaLine` in feedRowState.ts, which drops the
 * date from the feature's first metadata line under exactly the same "is today" test.
 */

const DAY_MS = 86_400_000;

/** The bucket an event falls in. `undated` is the honest "no heading" case. */
export type SectionKey = 'tonight' | 'week' | 'later' | 'undated';

/** The words the boards draw. `null` means the section is drawn with NO heading. */
export const SECTION_LABEL: Record<SectionKey, string | null> = {
  tonight: 'Tonight',
  week: 'This week',
  later: 'Later',
  undated: null,
};

/** Sections appear in this order. Soonest first; the unnameable bucket last. */
export const SECTION_ORDER: readonly SectionKey[] = ['tonight', 'week', 'later', 'undated'];

/** Local midnight of the day `ms` falls in, on this device. */
export function startOfLocalDay(ms: number): number {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

/**
 * Which section a stored `event_date` ("2026-10-24") belongs to, relative to `nowMs`.
 *
 * The date is parsed at local midnight rather than as UTC: `new Date('2026-10-24')` is UTC and
 * would move an event a day either side of the date line, which is how a feed ends up promising
 * "Tonight" for tomorrow.
 */
export function sectionFor(eventDate: string | null | undefined, nowMs: number): SectionKey {
  if (!eventDate) return 'undated';
  const parsed = new Date(`${eventDate}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) return 'undated';
  const days = Math.round((startOfLocalDay(parsed.getTime()) - startOfLocalDay(nowMs)) / DAY_MS);
  if (days === 0) return 'tonight';
  if (days >= 1 && days <= 7) return 'week';
  if (days > 7) return 'later';
  return 'undated'; // already happened — sold/ended datasets land here
}

export interface Section<T> {
  key: SectionKey;
  /** `null` draws no heading. */
  label: string | null;
  items: T[];
}

/**
 * Bucket `items` by event date and return the non-empty sections in `SECTION_ORDER`.
 *
 * Stable: within a section the items keep the order they arrived in. Total: every input item
 * appears in exactly one output section.
 */
export function groupByEventDate<T>(
  items: readonly T[],
  eventDateOf: (item: T) => string | null | undefined,
  nowMs: number,
): Section<T>[] {
  const buckets = new Map<SectionKey, T[]>();
  for (const item of items) {
    const key = sectionFor(eventDateOf(item), nowMs);
    const bucket = buckets.get(key);
    if (bucket) bucket.push(item);
    else buckets.set(key, [item]);
  }
  return SECTION_ORDER.flatMap((key) => {
    const items_ = buckets.get(key);
    return items_ ? [{ key, label: SECTION_LABEL[key], items: items_ }] : [];
  });
}
