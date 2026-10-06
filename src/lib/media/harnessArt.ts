/**
 * src/lib/media/harnessArt.ts — which bundled poster a review asks for, and which row gets it.
 *
 * WHY THIS IS A MODULE AND NOT TWO COPIES IN TWO ROUTES. It started inside `app/_dev/v3-home.tsx`
 * and had to be duplicated the moment the Listing harness needed the same controls (E, 2026-10-05).
 * Two copies of a selection rule is how the two surfaces end up offering different keys and a
 * reviewer has to learn both. It is also untestable in a route file: a `.tsx` route carries JSX and
 * React Native imports, so a behavioural test cannot import it — which is precisely how the defect
 * below survived.
 *
 * THE DEFECT (B, 2026-10-05). The Home harness put the feature's artwork on `rows[0]` and assumed
 * that row was the feature. The screen does not render rows in fixture order: it buckets them by
 * event date (`groupByEventDate`, keyed to local midnight), flattens the sections, and features
 * `index === 0` of THAT order. `rows[0]` is the feature only when the fixture's first row happens
 * to fall in the earliest bucket.
 *
 * It did hold for the shipped fixture, whose first row is tonight — which is exactly why a native
 * capture looked correct while the rule was wrong. The failure mode is the worst kind for a review:
 * the poster lands on a row further down, the feature renders the empty plate, and the reviewer has
 * no way to know they are judging the wrong component.
 *
 * So the featured row is DERIVED using the screen's own ordering function. Reusing
 * `groupByEventDate` rather than restating the buckets is the whole point — a second copy of that
 * rule could drift from the screen's and reintroduce this silently.
 */

import { groupByEventDate } from '@/src/lib/home/sections';

import { devPosterPath, type DevPosterName } from './devPosters';

/** The shape the selection needs. Structural, so a test can drive it with plain objects. */
export interface ArtRow {
  id: string;
  event_date?: string | null;
  status?: string | null;
  auction_status?: string | null;
  cover_image_path?: string | null;
}

/**
 * `?art=` — what each key puts where.
 *
 * `feature` is the poster for the featured component (Home's full-bleed feature, or the listing
 * hero); `rows` is what every other row takes, which is usually nothing because a feed where every
 * row carries the same poster reads as a bug rather than as a fixture.
 */
export const ART: Record<string, { feature: string | null; rows: string | null }> = {
  missing: { feature: null, rows: null },
  flyer: { feature: devPosterPath('flyer-dense-4x5'), rows: null },
  photo: { feature: devPosterPath('photo-3x2'), rows: null },
  markers: { feature: devPosterPath('markers-4x5'), rows: null },
  tall: { feature: devPosterPath('markers-9x16'), rows: null },
  wide: { feature: devPosterPath('markers-16x9'), rows: null },
  square: { feature: devPosterPath('markers-1x1'), rows: null },
  subject: { feature: devPosterPath('photo-subject-4x5'), rows: null },
  'subject-wide': { feature: devPosterPath('photo-subject-16x9'), rows: null },
  all: { feature: devPosterPath('flyer-dense-4x5'), rows: devPosterPath('markers-4x5') },
};

export const ART_KEYS = Object.keys(ART);

/**
 * The row the SCREEN will feature, or null when it will feature nothing.
 *
 * Two rules, both the screen's: the order is the date-bucketed one, and a sold or ended row is
 * never featured (a spotlight on something nobody can buy reads as an offer). When the first row
 * in that order is ineligible the screen shows no feature at all — so this returns null rather
 * than searching on for a row the screen would not promote either.
 */
export function featuredRowId(rows: readonly ArtRow[], nowMs: number): string | null {
  const ordered = groupByEventDate(rows, (l) => l.event_date, nowMs).flatMap((s) => s.items);
  const first = ordered[0];
  if (!first) return null;
  const eligible = first.status !== 'sold' && (first.auction_status ?? 'active') !== 'ended';
  return eligible ? first.id : null;
}

/** Applies `?art=` to a feed's rows, putting the feature poster on the row that will be featured. */
export function withArt<T extends ArtRow>(rows: readonly T[], art: string | undefined, nowMs: number): T[] {
  const pick = art ? ART[art] : undefined;
  if (!pick) return rows as T[];
  const featured = featuredRowId(rows, nowMs);
  return rows.map((r) => {
    const cover = r.id === featured ? pick.feature : pick.rows;
    return cover == null ? r : ({ ...r, cover_image_path: cover } as T);
  });
}

/**
 * The cover for a SINGLE-listing harness, where there is no feed and so no bucketing — the listing
 * under review is the featured thing by definition.
 *
 * Returns null for an unknown key, and that is a safeguard rather than tidiness: the value arrives
 * from a URL and ends up in the same cover field a database row fills, so forwarding it unchecked
 * would make `?art=` a way to put an arbitrary string into the media resolver from outside the app.
 */
export function listingArt(art: string | undefined): string | null {
  if (!art) return null;
  const pick = ART[art];
  return pick?.feature ?? null;
}

/** The bundled poster names, re-exported so a harness never hand-writes one. */
export type { DevPosterName };
