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
 *   the event falls on New York's TODAY            → "Tonight"
 *   the event falls on the next 1–7 New York days  → "This week"
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
 * New York's calendar is the basis (owner, 2026-11-02: Snatch It operates in Eastern Time) — never the
 * device's, so a phone in another zone cannot move "Tonight". It matches `featureMetaLine` in
 * feedRowState.ts, which drops the date from the feature's first metadata line under exactly the same
 * "is today" test. The stored `event_date` is a New York calendar date already: it is compared as a date,
 * never turned into an instant.
 */

import { dayKeyDiff, easternDayKey } from '@/src/lib/time/eastern';

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

/**
 * "Today" for the rule: the instant now (UTC ms), or New York's day key for it ('YYYY-MM-DD', from
 * `easternDayKey`). A screen that ticks every second passes the key, which only changes at New York
 * midnight, so its grouping is rebuilt once a day rather than once a tick.
 */
export type Today = number | string | null;

const EVENT_DATE = /^\d{4}-(\d{2})-(\d{2})$/;

/**
 * Which section a stored `event_date` ("2026-10-24") belongs to, relative to `today`.
 *
 * The stored date and New York's today are differenced as calendar dates (`dayKeyDiff`). Neither is
 * parsed as an instant: `new Date('2026-10-24')` is UTC and would move an event a day either side of
 * the date line, which is how a feed ends up promising "Tonight" for tomorrow.
 */
export function sectionFor(eventDate: string | null | undefined, today: Today): SectionKey {
  if (!eventDate) return 'undated';
  // A calendar date or nothing: month 01–12, day 01–31 (the dates the previous parse accepted).
  const shape = EVENT_DATE.exec(eventDate);
  if (!shape || +shape[1] < 1 || +shape[1] > 12 || +shape[2] < 1 || +shape[2] > 31) return 'undated';
  const todayKey = typeof today === 'number' ? easternDayKey(today) : today;
  const days = todayKey ? dayKeyDiff(todayKey, eventDate) : null;
  if (days === null) return 'undated';
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
  today: Today,
): Section<T>[] {
  const todayKey = typeof today === 'number' ? easternDayKey(today) : today;
  const buckets = new Map<SectionKey, T[]>();
  for (const item of items) {
    const key = sectionFor(eventDateOf(item), todayKey);
    const bucket = buckets.get(key);
    if (bucket) bucket.push(item);
    else buckets.set(key, [item]);
  }
  return SECTION_ORDER.flatMap((key) => {
    const items_ = buckets.get(key);
    return items_ ? [{ key, label: SECTION_LABEL[key], items: items_ }] : [];
  });
}
