/**
 * tests/v3-harness-art-selection.test.ts — the artwork a reviewer asks for reaches the component
 * they are reviewing, and the controls that put it there cannot do anything else.
 *
 * THE DEFECT (B, 2026-10-05). The Home harness assigned the feature's artwork to `rows[0]` and
 * assumed that row was the feature. The screen does not render rows in fixture order: it buckets
 * them by event date (`groupByEventDate`, keyed to local midnight), flattens the sections, and
 * features `index === 0` of THAT order. So `rows[0]` is the feature only when the fixture's first
 * row happens to fall in the earliest bucket.
 *
 * It did hold for HOME_FIXTURE, whose first row is tonight — which is precisely why the defect
 * survived a native capture that looked right. The failure mode is the nastiest kind for a review:
 * the poster lands on some row further down, the feature shows an empty plate, and the reviewer has
 * no way to tell they are looking at the wrong component.
 *
 * THE SECOND GAP (E, 2026-10-05): the Listing harness could not select artwork at all — every
 * fixture hard-coded `cover_image_path: null`. R-4 moved the listing identity BENEATH the poster,
 * and that cannot be judged against no poster.
 *
 * Both are pinned here behaviourally, each with a control that fails under the old rule, plus the
 * safeguards: these controls must not be able to reserve anything, reach production, or put an
 * arbitrary value into the media layer.
 */

import { describe, expect, it } from 'vitest';

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { groupByEventDate } from '../src/lib/home/sections';
import { DEV_POSTER_NAMES, DEV_POSTER_PREFIX } from '../src/lib/media/devPosters';

const root = resolve(__dirname, '..');
const code = (rel: string) =>
  readFileSync(resolve(root, rel), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

const MIDNIGHT = (() => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime();
})();

const iso = (daysAhead: number) => {
  const d = new Date(MIDNIGHT);
  d.setDate(d.getDate() + daysAhead);
  return d.toISOString().slice(0, 10);
};

type Row = {
  id: string;
  event_date: string;
  status?: string;
  auction_status?: string;
  cover_image_path?: string | null;
};

/** The row the SCREEN will feature: first of the date-bucketed order, if it is eligible. */
function screenFeatured(rows: Row[]): Row | null {
  const ordered = groupByEventDate(rows, (l) => l.event_date, MIDNIGHT).flatMap((s) => s.items);
  const first = ordered[0];
  if (!first) return null;
  const eligible = first.status !== 'sold' && (first.auction_status ?? 'active') !== 'ended';
  return eligible ? first : null;
};

describe('Home — the feature artwork reaches the FEATURE', () => {
  it('HA1: with a fixture whose first row is NOT the earliest, the poster still lands on the feature', async () => {
    const { withArt } = await import('@/src/lib/media/harnessArt');
    /*
     * The regression case, built deliberately: `rows[0]` is next week and `rows[1]` is tonight, so
     * the screen features rows[1]. Under the old rule the poster went to rows[0] — a row the
     * reviewer would have to scroll to — and the feature rendered the empty plate.
     */
    const rows = [
      { id: 'later', event_date: iso(6), status: 'active', auction_status: 'active', cover_image_path: null },
      { id: 'tonight', event_date: iso(0), status: 'active', auction_status: 'active', cover_image_path: null },
    ] as Row[];

    const featured = screenFeatured(rows);
    expect(featured?.id, 'the screen features the earliest bucket, not rows[0]').toBe('tonight');

    const painted = withArt(rows as never, 'flyer', MIDNIGHT) as unknown as Row[];
    const byId = Object.fromEntries(painted.map((r) => [r.id, r.cover_image_path]));
    expect(byId.tonight, 'the feature carries the flyer').toBe(`${DEV_POSTER_PREFIX}flyer-dense-4x5`);

    // THE CONTROL: under the old `rows[0]` rule this is where the poster went. If it ever carries
    // the feature artwork again, the rule has regressed to assuming fixture order.
    expect(byId.later, 'the non-featured row must not take the feature artwork')
      .not.toBe(`${DEV_POSTER_PREFIX}flyer-dense-4x5`);
  });

  it('HA2: every art key puts its poster on the featured row, for the real fixture too', async () => {
    const { withArt, ART_KEYS } = await import('@/src/lib/media/harnessArt');
    /*
     * The shipped fixture's SHAPE — one event tonight, three later in the week — rather than the
     * fixture itself, which lives in a route module a test cannot import. HA1 already covers the
     * ordering trap; this covers every key reaching whatever the feature turns out to be.
     */
    const rows = [
      { id: 'tonight', event_date: iso(0), status: 'active', auction_status: 'active', cover_image_path: null },
      { id: 'wk1', event_date: iso(2), status: 'active', auction_status: 'active', cover_image_path: null },
      { id: 'wk2', event_date: iso(4), status: 'active', auction_status: 'active', cover_image_path: null },
    ] as Row[];
    const featured = screenFeatured(rows);
    expect(featured?.id).toBe('tonight');

    for (const key of ART_KEYS as string[]) {
      const painted = withArt(rows as never, key, MIDNIGHT) as unknown as Row[];
      const onFeature = painted.find((r) => r.id === featured!.id)!.cover_image_path;
      if (key === 'missing') {
        expect(onFeature, `${key} leaves the plate`).toBeNull();
      } else {
        expect(onFeature, `${key} reaches the feature`).toMatch(new RegExp(`^${DEV_POSTER_PREFIX}`));
        // And it names a poster that actually exists, rather than a string nobody bundled.
        const name = (onFeature as string).slice(DEV_POSTER_PREFIX.length);
        expect(DEV_POSTER_NAMES as readonly string[], `${key} names a bundled poster`).toContain(name);
      }
    }
  });

  it('HA3: when no row can be featured, nothing claims a feature that will not render', async () => {
    const { withArt } = await import('@/src/lib/media/harnessArt');
    // The screen refuses to feature a sold or ended row, so a fixture of only those has no feature.
    const rows = [
      { id: 'sold', event_date: iso(0), status: 'sold', auction_status: 'active', cover_image_path: null },
      { id: 'ended', event_date: iso(1), status: 'active', auction_status: 'ended', cover_image_path: null },
    ] as Row[];
    expect(screenFeatured(rows)).toBeNull();

    const painted = withArt(rows as never, 'flyer', MIDNIGHT) as unknown as Row[];
    for (const r of painted) {
      expect(r.cover_image_path, `${r.id} takes row artwork, not the feature's`)
        .not.toBe(`${DEV_POSTER_PREFIX}flyer-dense-4x5`);
    }
  });
});

describe('Listing — the harness can show a poster at all', () => {
  const harness = code('app/_dev/v3-listing.tsx');

  it('HA4: it accepts ?art= and resolves it through the SAME vocabulary as Home', () => {
    expect(harness).toMatch(/art\?: string;/);
    // One shared module, so the two surfaces cannot offer different keys.
    expect(harness).toContain('listingArt(');
    expect(harness).toContain('cover_image_path:');
    expect(code('app/_dev/v3-home.tsx')).toContain("from '@/src/lib/media/harnessArt'");
  });

  it('HA5: an unknown or crafted ?art= is ignored, not passed through to the media layer', () => {
    /*
     * The safeguard that matters on this control. The value arrives from a URL, and it ends up in
     * a row's cover field — the same field a database row fills. If the harness forwarded it
     * unchecked, `?art=` would become a way to put an arbitrary string into the media resolver from
     * outside the app. It is matched against the bundled names first and otherwise dropped.
     */
    // The resolver returns null for an unknown key and the harness drops it.
    expect(harness).toMatch(/const cover = listingArt\(art\);/);
    expect(harness).toMatch(/if \(!cover\) return withReserving;/);
  });
});

describe('the controls cannot do anything but show things', () => {
  const home = code('app/_dev/v3-home.tsx');
  const listing = code('app/_dev/v3-listing.tsx');

  it('HA6: neither harness can start a reservation or touch a payment path', () => {
    for (const [name, src] of [['home', home], ['listing', listing]] as const) {
      for (const forbidden of [
        'reserve_buy_now', 'release_reservation', 'create-payment-intent', 'useSingleFlight',
        'handleBuyNow', 'setReserving', 'confirmPayment', 'stripe',
      ]) {
        expect(src, `${name} harness must not reference ${forbidden}`).not.toContain(forbidden);
      }
    }
    // POSITIVE CONTROL: the scan is reading real files, not empty strings.
    expect(home.length).toBeGreaterThan(1000);
    expect(listing.length).toBeGreaterThan(1000);
  });

  it('HA7: both routes refuse to render outside a sandbox or dev build', () => {
    for (const [name, src] of [['home', home], ['listing', listing]] as const) {
      expect(src, `${name} is production-gated`).toMatch(/if \(!IS_SANDBOX_BUILD && !__DEV__\) return <Redirect/);
    }
  });

  it('HA8: the reserving control stays opt-in and seeds state only', () => {
    expect(listing).toContain("reserving === '1'");
    // It sets a fixture flag. It does not call anything.
    expect(listing).toMatch(/\{ \.\.\.base, reserving: true \}/);
  });
});

/*
 * THE LIST HARNESSES (2026-10-06). My listings, Bids, Tickets, Search and Checkout rendered the
 * missing-artwork plate and nothing else: `cover_image_path: null` at v3-mylistings-bids.tsx:108
 * and v3-search-create.tsx:73, `artwork_ref: null` at v3-tickets.tsx:44, `cover: null` at
 * v3-checkout.tsx:46.
 *
 * The rule is deliberately NOT "put the poster on the first row". That is the rule that produced
 * the Home defect above, and these four screens order or group their rows too — so a per-screen
 * "first row" would be four fresh chances to make the same mistake. Every row takes the selected
 * poster instead, and `all` gives each of the first rows a different shape, so no ordering is
 * assumed anywhere and one capture shows several shapes.
 */
describe('the list harnesses — every row, no ordering assumed', () => {
  it('HA9: a selected key reaches every row, whatever order the screen renders them in', async () => {
    const { listArt } = await import('../src/lib/media/harnessArt');
    for (const n of [1, 3, 5, 12]) {
      const covers = listArt('flyer', n);
      expect(covers).toHaveLength(n);
      expect(covers.every((c) => c === `${DEV_POSTER_PREFIX}flyer-dense-4x5`), `n=${n}`).toBe(true);
    }
  });

  it('HA10: `all` gives each row a different shape, covering the ones the fit has to survive', async () => {
    const { listArt, ART_SHAPES } = await import('../src/lib/media/harnessArt');
    const covers = listArt('all', ART_SHAPES.length);
    expect(new Set(covers).size).toBe(ART_SHAPES.length);
    // The shapes a 4:5 frame has to handle: the target, taller, wider, square, and a photograph.
    const names = covers.map((c) => String(c).slice(DEV_POSTER_PREFIX.length));
    for (const needed of ['markers-4x5', 'markers-9x16', 'markers-16x9', 'markers-1x1', 'flyer-dense-4x5']) {
      expect(names, `${needed} must be among the cycled shapes`).toContain(needed);
    }
    // Every cycled value is a real bundled poster, so none of them renders as a plate by accident.
    for (const name of names) expect(DEV_POSTER_NAMES).toContain(name);
    // It keeps cycling rather than running out, and rows past the cycle are still real posters.
    const long = listArt('all', ART_SHAPES.length + 2);
    expect(long).toHaveLength(ART_SHAPES.length + 2);
    expect(long.every((c) => c != null)).toBe(true);
  });

  it('HA11: `missing`, nothing, and a crafted value all give plates — nothing is forwarded', async () => {
    const { listArt } = await import('../src/lib/media/harnessArt');
    for (const key of [
      undefined, 'missing', 'MISSING', '../../etc/passwd', 'https://evil.example/x.png',
      `${DEV_POSTER_PREFIX}not-a-real-name`, 'all ', '',
    ]) {
      expect(listArt(key, 3), `key=${String(key)}`).toEqual([null, null, null]);
    }
    // POSITIVE CONTROL: in the same run, a key that IS known returns posters — so the nulls above
    // are the keys being refused and not the function being inert.
    expect(listArt('markers', 2).every((c) => c != null)).toBe(true);
  });
});

describe('the list harnesses — wired, and still unable to do anything', () => {
  const ROUTES = {
    'v3-mylistings-bids': ['cover_image_path'],
    // `screen=order` and `screen=send` mount the real Transfer screens, whose poster reads the
    // listing cover — a different field on the same route from the ticket rows' artwork_ref.
    'v3-tickets': ['artwork_ref', 'cover_image_path'],
    'v3-search-create': ['cover_image_path'],
    'v3-checkout': ['cover'],
  } as const;

  it('HA12: each route reads ?art= and applies the shared rule', () => {
    for (const route of Object.keys(ROUTES)) {
      const src = code(`app/_dev/${route}.tsx`);
      expect(src, `${route} accepts ?art=`).toMatch(/art\?: string/);
      expect(src, `${route} uses the shared rule`).toContain('listArt(');
      expect(src, `${route} imports one vocabulary`).toContain("from '@/src/lib/media/harnessArt'");
    }
  });

  it('HA13: the selected poster is what lands in each artwork field', () => {
    /*
     * A positive pin rather than "there is no `field: null`". The defect was not the literal null
     * — a fixture is entitled to show the plate — it was that no control could reach the field.
     * So what is pinned is the reaching: every artwork field on these routes is assigned from the
     * shared rule's output, under one local name so the wiring is readable in review.
     */
    for (const [route, fields] of Object.entries(ROUTES)) {
      const src = code(`app/_dev/${route}.tsx`);
      expect(src, `${route} computes the covers`).toMatch(/const covers = listArt\(art, /);
      for (const field of fields) {
        expect(src, `${route} must feed ${field} from the covers`).toMatch(
          new RegExp(`${field}: covers\\[`),
        );
      }
    }
  });

  it('HA14: the new control adds no capability to any of them', () => {
    for (const route of Object.keys(ROUTES)) {
      const src = code(`app/_dev/${route}.tsx`);
      for (const forbidden of [
        'reserve_buy_now', 'release_reservation', 'create-payment-intent', 'useSingleFlight',
        'handleBuyNow', 'setReserving', 'confirmPayment', 'stripe', 'supabase',
      ]) {
        expect(src, `${route} must not reference ${forbidden}`).not.toContain(forbidden);
      }
      expect(src, `${route} is production-gated`).toMatch(/if \(!IS_SANDBOX_BUILD && !__DEV__\) return <Redirect/);
      expect(src.length, `${route} was actually read`).toBeGreaterThan(1000);
    }
  });
});
