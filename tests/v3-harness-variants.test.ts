/**
 * tests/v3-harness-variants.test.ts — the `_dev` rendering harnesses' VARIANTS: every key reachable,
 * every key gated, no key that writes (owner-authorised capture harnesses, 2026-09-24).
 *
 * WHAT THIS SUITE PROVES. It MOUNTS each route — `app/_dev/v3-listing.tsx`, `app/_dev/v3-home.tsx`,
 * `app/_dev/v3-account.tsx` — through the hook host, with the real screens stubbed to a name, and
 * asserts what each `?variant=` actually hands the screen. Then it puts the listing variants'
 * fixture rows through the REAL resolver (`src/lib/listing/detailState.ts`) with the screen's own
 * input mapping, so a fixture that resolved to a DIFFERENT state than its name claims fails here.
 * The mapping is mirrored, not called through the screen (the screen is the stub), so the pins at
 * the end of the listing block hold the mirror against the screen's own lines.
 *
 * WHAT IT DOES NOT PROVE. Nothing about paint: no colour, no layout, no native rendering. That is
 * what the captures themselves are for, which is why these routes exist.
 *
 * THE TWO ABSENT STATES. `lost` and `outbid` are deliberately not variants: both need `hasBid`,
 * which the screen derives from the live `useListingRealtime` rows and never from `fixture.bids`.
 * The negative control below pins what the same rows resolve to without it.
 */
import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });
// The media policy is only meaningful with a storage origin configured: without one every URL is
// null and HV13's refusal would be vacuous. Same value the transfer-gallery suite uses.
process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';

const st = vi.hoisted(() => ({
  sandbox: false,
  params: {} as Record<string, string | undefined>,
  userId: undefined as string | undefined,
  pref: 'system',
}));

vi.mock('@/src/config/envGuard', () => ({
  get IS_SANDBOX_BUILD() { return st.sandbox; },
  ENV_GUARD_FAILURE: null,
}));
vi.mock('expo-router', () => ({
  Redirect: 'Redirect',
  router: { push: () => {}, back: () => {}, replace: () => {} },
  useLocalSearchParams: () => st.params,
}));
vi.mock('@/src/theme/appearance', async () => {
  const { paletteFor } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: paletteFor('dark') }),
    useAppearancePreference: () => ({ preference: st.pref, setPreference: (p: string) => { st.pref = p; } }),
  };
});
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('react-native', () => ({
  Text: 'Text',
  View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1, absoluteFill: {}, absoluteFillObject: {} },
}));
// The harness reads the REAL viewer for the identity-decided states; here that hook is the dial.
vi.mock('@/src/hooks/useAuth', () => ({
  useAuth: () => ({ user: st.userId ? { id: st.userId } : null, session: null, loading: false }),
}));
// The screens are the harnesses' SUBJECTS, not this suite's: stubbed to a name so the assertions
// are about the route's variant wiring, and so mounting a route does not drag the whole screen
// graph (the Supabase client included) into a node test.
vi.mock('@/src/screens/ListingDetailScreen', () => ({ default: 'ListingDetailScreen' }));
vi.mock('@/app/(tabs)/home', () => ({ default: 'HomeScreen' }));
vi.mock('@/app/(tabs)/profile', () => ({ default: 'ProfileScreen' }));
vi.mock('@/app/settings/index', () => ({ default: 'SettingsScreen' }));
vi.mock('@/app/settings/appearance', () => ({ default: 'AppearanceScreen' }));

import { detailState, type DetailStateInput } from '@/src/lib/listing/detailState';
import { activeFilterCount, DEFAULT_FILTERS } from '@/src/lib/home/filterModel';
import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const ROUTES = {
  listing: () => import('@/app/_dev/v3-listing'),
  home: () => import('@/app/_dev/v3-home'),
  account: () => import('@/app/_dev/v3-account'),
} as const;

const FILES: Record<keyof typeof ROUTES, string> = {
  listing: 'app/_dev/v3-listing.tsx',
  home: 'app/_dev/v3-home.tsx',
  account: 'app/_dev/v3-account.tsx',
};

/** Source with comments removed: these rules are about what the file DOES, not what it says. */
const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

async function render(route: keyof typeof ROUTES, params: Record<string, string | undefined>) {
  st.params = params;
  const mod = await ROUTES[route]();
  const host = new HookHost(() => (mod.default as () => unknown)(), new Map());
  host.mount();
  host.flush();
  return host;
}

/** The single element a route returned (every one of them returns exactly one). */
const rootOf = (host: HookHost) => host.output as Element;

/** Text anywhere in the rendered tree, sub-components expanded. */
function texts(host: HookHost): string[] {
  const out: string[] = [];
  const walk = (n: unknown) => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (typeof el.props.children === 'string') out.push(el.props.children);
    walk(el.props.children);
  };
  walk(expandTree(host.output));
  return out;
}

// ─── The gate ─────────────────────────────────────────────────────────────────

describe('the gate — a production bundle reaches no variant of any harness', () => {
  it('HV1: with neither __DEV__ nor IS_SANDBOX_BUILD, each route renders only a redirect home', async () => {
    st.sandbox = false;
    st.userId = 'viewer-0000-0000-0000-000000000000';
    expect((globalThis as Record<string, unknown>).__DEV__).toBe(false);
    for (const route of ['listing', 'home', 'account'] as const) {
      // Params that WOULD select a state if the gate let them through.
      const host = await render(route, { screen: route === 'listing' ? 'listing' : 'profile', variant: 'won' });
      const root = rootOf(host);
      expect(root?.type, route).toBe('Redirect');
      expect(root?.props.href, route).toBe('/');
      expect(texts(host), route).toHaveLength(0);
    }
    // And the line itself is present in each file, so a refactor cannot lose it silently.
    for (const rel of Object.values(FILES)) {
      expect(strip(rel), rel).toContain('if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;');
    }
  });

  it('HV2: an unknown screen is a redirect, not a default state', async () => {
    st.sandbox = true;
    for (const route of ['listing', 'account'] as const) {
      const host = await render(route, {});
      expect(rootOf(host)?.type, route).toBe('Redirect');
    }
  });
});

// ─── app/_dev/v3-listing.tsx ──────────────────────────────────────────────────

type Row = {
  status: string; auction_status?: string | null; buy_now_enabled: boolean; buy_now_price: number | null;
  seller_id: string; reserved_by: string | null; reserved_until: string | null;
  winner_user_id?: string | null; bid_count?: number | null; quantity?: number | null; ends_at: string;
};
type Fixture = { listing: Row | null; viewerId?: string; bids?: { bidder_id: string; amount: number }[] };

const VIEWER_ID = 'a1b2c3d4-0000-0000-0000-000000000000';

/**
 * The screen's OWN input mapping, mirrored (src/screens/ListingDetailScreen.tsx: `isReserved`,
 * `ended`, and the `detailState({...})` call). `hasBid` / `isHighestBidder` are false for every
 * harness variant because the screen reads them from `rt.bids` — the live hook — and the harness
 * has no bid rows out there. The pins in HV7 hold this mirror against those lines.
 */
function resolve(row: Row, userId?: string) {
  const reservedUntil = row.reserved_until ? new Date(row.reserved_until) : null;
  const input: DetailStateInput = {
    listing: {
      status: row.status,
      auction_status: row.auction_status,
      buy_now_enabled: row.buy_now_enabled,
      buy_now_price: row.buy_now_price,
      seller_id: row.seller_id,
      reserved_by: row.reserved_by,
      winner_user_id: row.winner_user_id,
      bid_count: row.bid_count,
      quantity: row.quantity,
    },
    userId,
    clockEnded: new Date(row.ends_at) <= new Date(),
    reservationActive: row.status === 'reserved' && reservedUntil != null && reservedUntil > new Date(),
    finalizing: false,
    reserving: false,
    transfer: { id: null, status: null, buyerId: null },
    isHighestBidder: false,
    hasBid: false,
    buyNowAllIn: '$132.00',
    nextBidAllIn: '$104.50',
  };
  return detailState(input);
}

async function listingFixture(variant: string, userId?: string): Promise<{ host: HookHost; fixture: Fixture | null }> {
  st.sandbox = true;
  st.userId = userId;
  const host = await render('listing', { screen: 'listing', variant });
  const root = rootOf(host);
  if (root?.type !== 'ListingDetailScreen') return { host, fixture: null };
  return { host, fixture: root.props.fixture as Fixture };
}

describe('v3-listing — the states that had no capture', () => {
  it('HV3: the viewer-independent variants mount the real screen with a row that resolves to their own name', async () => {
    // live
    const live = await listingFixture('live');
    expect(live.fixture?.listing?.status).toBe('active');
    expect(resolve(live.fixture!.listing!).primary.kind).toBe('buy_now');

    // sold / cancelled (already captured; pinned so a variant rename cannot drop them)
    expect((await listingFixture('sold')).fixture?.listing?.status).toBe('sold');
    expect((await listingFixture('cancelled')).fixture?.listing?.auction_status).toBe('cancelled');

    // on-hold — `reserved_by_other`, the one identity state that needs no viewer: a live hold,
    // held by somebody who is not whoever is looking.
    const held = await listingFixture('on-hold');
    const row = held.fixture!.listing!;
    expect(row.status).toBe('reserved');
    expect(row.reserved_by).toBeTruthy();
    expect(new Date(row.reserved_until!).getTime()).toBeGreaterThan(Date.now());
    const onHold = resolve(row);
    expect(onHold.status?.kind).toBe('reserved_by_other');
    expect(onHold.status?.label).toBe('Held for another buyer');
    expect(onHold.mode).toBe('closed');
    expect(onHold.primary.label).toBe('On hold');
    expect(onHold.primary.disabled).toBe(true);
    // The state's sentence renders OUTSIDE the dimmed pill; a variant with no sentence is a dead
    // control that says nothing.
    expect(onHold.primary.subLabel).toBe('Another buyer is in checkout.');

    // not-found — the absent row, exactly as a null read leaves it.
    const missing = await listingFixture('not-found');
    expect(missing.fixture?.listing).toBeNull();
  });

  it('HV4: the viewer-decided variants carry the REAL viewer id, and resolve to won / held-for-you / the seller\'s own view', async () => {
    const won = await listingFixture('won', VIEWER_ID);
    const wonRow = won.fixture!.listing!;
    expect(won.fixture?.viewerId).toBe(VIEWER_ID);
    expect(wonRow.auction_status).toBe('ended');
    expect(wonRow.winner_user_id).toBe(VIEWER_ID);
    expect(new Date(wonRow.ends_at).getTime()).toBeLessThan(Date.now());
    // The history a won auction has to show: the winner's bid in front.
    expect(won.fixture?.bids?.[0]?.bidder_id).toBe(VIEWER_ID);
    const wonState = resolve(wonRow, VIEWER_ID);
    expect(wonState.status?.kind).toBe('won');
    expect(wonState.status?.label).toBe('You won');
    expect(wonState.primary.kind).toBe('pay_now');

    const heldForYou = await listingFixture('reserved-by-you', VIEWER_ID);
    const heldRow = heldForYou.fixture!.listing!;
    expect(heldRow.status).toBe('reserved');
    expect(heldRow.reserved_by).toBe(VIEWER_ID);
    expect(new Date(heldRow.reserved_until!).getTime()).toBeGreaterThan(Date.now());
    const heldState = resolve(heldRow, VIEWER_ID);
    expect(heldState.status?.kind).toBe('reserved_by_you');
    expect(heldState.primary.kind).toBe('continue_reservation');
    expect(heldState.primary.label).toBe('Finish checkout');

    const own = await listingFixture('own-listing', VIEWER_ID);
    const ownRow = own.fixture!.listing!;
    expect(ownRow.seller_id).toBe(VIEWER_ID);
    const ownState = resolve(ownRow, VIEWER_ID);
    expect(ownState.role).toBe('seller');
    expect(ownState.showsOwnerActions).toBe(true);
    expect(ownState.primary.label).toBe('Your listing');
    expect(ownState.primary.disabled).toBe(true);
    expect(ownState.primary.subLabel).toBe('You listed this, so you cannot bid or buy.');
  });

  it('HV5: signed out, a viewer-decided variant paints a harness note — never the state under a name the resolver would not give it', async () => {
    for (const variant of ['won', 'reserved-by-you', 'own-listing']) {
      const { host, fixture } = await listingFixture(variant, undefined);
      expect(fixture, variant).toBeNull();
      expect(rootOf(host)?.type, variant).not.toBe('ListingDetailScreen');
      const said = texts(host).join(' ');
      expect(said, variant).toContain(variant);
      expect(said, variant).toContain('Harness note');
    }
    // The failure mode this guards: with no viewer, the SAME rows resolve to something else.
    const ended = {
      status: 'active', auction_status: 'ended', buy_now_enabled: true, buy_now_price: 120,
      seller_id: 'fixture-seller', reserved_by: null, reserved_until: null,
      winner_user_id: undefined, bid_count: 6, quantity: 2,
      ends_at: new Date(Date.now() - 60_000).toISOString(),
    } satisfies Row;
    expect(resolve(ended, undefined).status?.kind).toBe('ended');
  });

  it('HV6 (negative control): `lost` and `outbid` need a bid the fixture cannot give, so they are absent — not approximated', async () => {
    const src = strip(FILES.listing);
    expect(src).not.toMatch(/case 'lost'/);
    expect(src).not.toMatch(/case 'outbid'/);
    // Why: both are gated on hasBid, and the harness's hasBid is always false.
    const endedRow = {
      status: 'active', auction_status: 'ended', buy_now_enabled: true, buy_now_price: 120,
      seller_id: 'fixture-seller', reserved_by: null, reserved_until: null, winner_user_id: 'someone-else',
      bid_count: 6, quantity: 2, ends_at: new Date(Date.now() - 60_000).toISOString(),
    } satisfies Row;
    const liveRow = { ...endedRow, auction_status: 'active', winner_user_id: null, ends_at: new Date(Date.now() + 3_600_000).toISOString() } satisfies Row;
    // Without hasBid: 'ended' and no status at all — NOT 'lost' and NOT 'outbid'.
    expect(resolve(endedRow, VIEWER_ID).status?.kind).toBe('ended');
    expect(resolve(liveRow, VIEWER_ID).status).toBeNull();
    // With hasBid — the input the harness cannot produce — the resolver DOES name them, which is
    // the proof that the gap is the fixture's and not the resolver's.
    const withBid = (row: Row, highest: boolean) => detailState({
      listing: {
        status: row.status, auction_status: row.auction_status, buy_now_enabled: row.buy_now_enabled,
        buy_now_price: row.buy_now_price, seller_id: row.seller_id, reserved_by: row.reserved_by,
        winner_user_id: row.winner_user_id, bid_count: row.bid_count, quantity: row.quantity,
      },
      userId: VIEWER_ID,
      clockEnded: new Date(row.ends_at) <= new Date(),
      reservationActive: false, finalizing: false, reserving: false,
      transfer: { id: null, status: null, buyerId: null },
      isHighestBidder: highest, hasBid: true, buyNowAllIn: '$132.00', nextBidAllIn: '$104.50',
    });
    expect(withBid(endedRow, false).status?.kind).toBe('lost');
    expect(withBid(liveRow, false).status?.kind).toBe('outbid');
  });

  it('HV7: the mirrored input mapping is the screen\'s own (source pins), and a null row is the screen\'s not-found branch', () => {
    const screen = strip('src/screens/ListingDetailScreen.tsx');
    expect(screen).toMatch(/isReserved\s*=\s*listing\.status === 'reserved' && reservedUntil != null && reservedUntil > new Date\(\)/);
    expect(screen).toMatch(/reservationActive:\s*isReserved/);
    expect(screen).toMatch(/clockEnded:\s*ended/);
    expect(screen).toMatch(/const ended = listing \? new Date\(listing\.ends_at\) <= new Date\(\) : false/);
    // hasBid / isHighestBidder come from the LIVE hook's rows, which is why HV6 holds.
    expect(screen).toMatch(/myMaxBid = authReady && user\?\.id[\s\S]{0,160}rt\.bids\.reduce/);
    expect(screen).toMatch(/hasBid:\s*userHasBid/);
    expect(screen).toMatch(/const bids\s*=\s*fixture\?\.bids \?\? rt\.bids/);
    // The fixture stands in for the reads and assigns the row straight through, so a null row is
    // the deleted-listing branch rather than a state this harness drew itself.
    expect(screen).toMatch(/if \(fixture\) \{\s*setListing\(fixture\.listing\);/);
    expect(screen).toContain('if (!listing) return (');
    expect(screen).toContain('title="Listing not found"');
  });
});

// ─── app/_dev/v3-home.tsx ─────────────────────────────────────────────────────

describe('v3-home — the empty ladder, and the two surfaces the seam cannot reach', () => {
  async function homeFixture(variant?: string) {
    st.sandbox = true;
    const host = await render('home', variant ? { variant } : {});
    const root = rootOf(host);
    // RETARGETED: the seam is an OBJECT now (`HomeFixture`) — rows, the two lazy datasets, a
    // first-load failure and a starting chip — because three of Home's five "nothing here" surfaces
    // need a read that actually ran and returned nothing.
    type Row = { ticket_type: string; buy_now_enabled: boolean; neighborhood: string };
    const fx = root?.type === 'HomeScreen' ? (root.props.fixture as {
      rows?: Row[]; sold?: Row[]; ended?: Row[]; failure?: string; chip?: string;
    }) : null;
    return { host, fx, rows: fx ? fx.rows ?? null : null };
  }

  it('HV8: the default feed is the board\'s five rows; `empty` is an empty feed, which is the settled "nothing live" case', async () => {
    expect((await homeFixture()).rows).toHaveLength(5);
    const empty = await homeFixture('empty');
    expect(empty.rows).toEqual([]);
    expect(empty.fx?.failure, 'an empty feed is not a failed one').toBeUndefined();
    // No filter is applied, so the screen's ladder lands on its last rung. Pinned from the screen.
    const screen = strip('app/(tabs)/home.tsx');
    expect(screen).toContain("{ title: 'Nothing live right now', body: 'Check back, or list the tickets you cannot use.' }");
    // The fixture's failure takes the screen's OWN failure path, so the screen still decides what
    // an empty feed and a failed read each paint.
    expect(screen).toContain('if (fixture.failure) { setLoadError(fixture.failure); setAllListings([]); return; }');
    expect(screen).toContain('setAllListings(fixture.rows ?? []); setLoadError(null); return;');
  });

  it('HV9: `nomatches` supplies rows that ONE sheet selection empties — the copy stays the screen\'s', async () => {
    const { rows } = await homeFixture('nomatches');
    expect(rows?.length).toBeGreaterThan(0);
    // Every row GA, auction-only, one neighbourhood: so "VIP" (or "Buy now", or any other area)
    // matches nothing while raising the applied-filter count, which is what the copy is gated on.
    for (const r of rows!) {
      expect(r.ticket_type).toBe('GA');
      expect(r.buy_now_enabled).toBe(false);
      expect(r.neighborhood).toBe('Wynwood');
    }
    expect(activeFilterCount({ ...DEFAULT_FILTERS, chip: 'vip' })).toBeGreaterThan(0);
    expect(activeFilterCount(DEFAULT_FILTERS)).toBe(0);
    const screen = strip('app/(tabs)/home.tsx');
    expect(screen).toContain("{ title: 'No matches', body: 'Try fewer filters.' }");
    // The filter state is still the screen's own: the seam may only SEED a starting chip, and
    // `nomatches` does not use that, which is why it remains one tap rather than a URL.
    expect(screen).toContain("fixture?.chip ? { ...DEFAULT_FILTERS, chip: fixture.chip } : DEFAULT_FILTERS,");
    // The seam's shape, pinned so a widening is deliberate: rows, the two lazy datasets, a
    // first-load failure and a starting chip — and nothing that could bypass a decision.
    expect(screen).toMatch(/export interface HomeFixture \{/);
    expect(screen).toMatch(/fixture\?: Listing\[\] \| HomeFixture;/);
  });

  it('HV10: `sold-empty`, `ended-empty`, `error` and `offline` are reached through the screen\'s own paths', async () => {
    /*
     * RETARGETED. These four used to be unreachable, and the route painted a note saying what was
     * missing — correctly: the seam replaced only the live feed's rows, while a dataset's settled-empty
     * copy is gated on `mayShowEmptyCopy` (a read that SUCCEEDED and returned nothing) and the failed
     * view on `loadError`. The seam now carries the two lazy datasets, a first-load failure and a
     * starting chip, so each state is reached the way the screen reaches it.
     */
    const sold = await homeFixture('sold-empty');
    expect(sold.fx?.sold).toEqual([]);
    expect(sold.fx?.chip).toBe('recently_sold');
    expect(sold.rows?.length, 'the live feed still has rows, so an empty SOLD set is the subject').toBeGreaterThan(0);
    const ended = await homeFixture('ended-empty');
    expect(ended.fx?.ended).toEqual([]);
    expect(ended.fx?.chip).toBe('ended');
    for (const [variant, failure] of [['error', 'error'], ['offline', 'offline']] as const) {
      const f = await homeFixture(variant);
      expect(f.fx?.failure, variant).toBe(failure);
      expect(f.fx?.rows, variant).toBeUndefined();
    }
    // The gating the fixture does NOT bypass: the empty copy still needs a settled read, and the
    // failed view is still the screen's own ScreenState.
    const screen = strip('app/(tabs)/home.tsx');
    expect(screen).toContain('mayShowEmptyCopy(datasetState)');
    expect(screen).toContain('markFilterLoaded');
    expect(screen).toContain('<ScreenState');
    // And the lazy reads still go to the server whenever there is no fixture.
    for (const fn of ['fetchSoldListings', 'fetchEndedListings']) {
      const at = screen.indexOf(`async function ${fn}`);
      const body = screen.slice(at, at + 700);
      expect(body, fn).toContain('supabase');
      expect(body, fn).toMatch(/if \(fixture\) \{/);
    }
  });

});

describe('v3-account — an avatar that is actually present', () => {
  /** The element the account route returned for these params. */
  async function accountRender(params: Record<string, string>) {
    st.sandbox = true;
    return rootOf(await render('account', params));
  }

  it('HV11: `variant=avatar` puts the bundled photo on the real Profile; `noavatar` is the initials fallback', async () => {
    const withPhoto = await accountRender({ screen: 'profile', variant: 'avatar' });
    expect(withPhoto?.type).toBe('ProfileScreen');
    const fixture = withPhoto!.props.fixture as { avatarUri: string | null };
    expect(fixture.avatarUri?.startsWith('data:image/png;base64,')).toBe(true);
    // The default keeps the photographed row, so an existing capture command is unchanged.
    const byDefault = await accountRender({ screen: 'profile' });
    expect((byDefault!.props.fixture as { avatarUri: string | null }).avatarUri).toBe(fixture.avatarUri);

    const none = await accountRender({ screen: 'profile', variant: 'noavatar' });
    expect((none!.props.fixture as { avatarUri: string | null }).avatarUri).toBeNull();
  });

  it('HV12: the other account variants still select their screens', async () => {
    expect((await accountRender({ screen: 'settings', variant: 'pending' }))?.props.deletionFixture).toBe('pending');
    expect((await accountRender({ screen: 'settings', variant: 'probe-failed' }))?.props.deletionFixture).toBe('probe_failed');
    expect((await accountRender({ screen: 'settings' }))?.props.deletionFixture).toBe('active');
    expect((await accountRender({ screen: 'appearance' }))?.type).toBe('AppearanceScreen');
  });

  it('HV13: the dock half is out of reach from here, and the harness does not pretend otherwise', async () => {
    // 1. The dock is the (tabs) navigator's tab bar; a _dev route is outside that group.
    const tabs = strip('app/(tabs)/_layout.tsx');
    expect(tabs).toMatch(/tabBar=\{\(props\) => <AdaptiveDock \{\.\.\.props\} \/>\}/);
    expect(strip(FILES.account)).not.toContain('AdaptiveDock');
    // 2. Even inside it, the dock resolves its photo through the media policy, which accepts only
    //    an https URL on this project's own storage origin — so a data uri or a bundled asset
    //    cannot paint that circle, and this harness has no remote url to give it.
    const dock = strip('src/components/nav/AdaptiveDock.tsx');
    expect(dock).toMatch(/const youPath = dockAvatarPathFor\(user\?\.id\)/);
    expect(dock).toMatch(/getAvatarUrl\(youPath, \{ width: Math\.ceil\(AVATAR \* 1\.5\), height: Math\.ceil\(AVATAR \* 1\.5\)/);
    // `getAvatarUrl` is `mediaUrlForStoredValue(path, { bucket: 'avatars', ... })` and nothing else,
    // so the policy below IS what the dock's circle gets. (Imported from the URL module rather than
    // avatarImage, which pulls the picker and the client into a node test.)
    expect(strip('src/lib/avatarImage.ts')).toMatch(/return mediaUrlForStoredValue\(path, \{\s*bucket: BUCKET,/);
    const { mediaUrlForStoredValue } = await import('@/src/lib/media/url');
    const avatar = (raw: string, width?: number) =>
      mediaUrlForStoredValue(raw, { bucket: 'avatars', width, height: width });
    const dataUri = (strip(FILES.account).match(/'(data:image\/png;base64,[^']+)'/) ?? [])[1];
    expect(dataUri).toBeTruthy();
    expect(avatar(dataUri!)).toBeNull();
    expect(avatar(dataUri!, 42)).toBeNull();
    // Positive control, so those nulls are a refusal and not a dead resolver: a real bucket path
    // does resolve, and the square request comes back at the size the dock asked for.
    expect(avatar('user-1/avatar_1.png')).toContain('/object/public/avatars/user-1/avatar_1.png');
    expect(avatar('user-1/avatar_1.png', 42)).toMatch(/width=84&height=84/);
    // 3. So the fixture publishes nothing to the dock's store: no writes, no fake owner.
    expect(strip(FILES.account)).not.toContain('setDockAvatar');
  });
});

// ─── No variant writes ────────────────────────────────────────────────────────

describe('no variant introduces a write', () => {
  it('HV14: none of the three harnesses can reach a server, a mutation or a dialog', () => {
    for (const rel of Object.values(FILES)) {
      const src = strip(rel);
      expect(src, rel).not.toMatch(/supabase/);
      expect(src, rel).not.toMatch(/\.rpc\(/);
      expect(src, rel).not.toMatch(/functions\.invoke/);
      expect(src, rel).not.toMatch(/\bAlert\b/);
      expect(src, rel).not.toMatch(/fetch\(/);
      expect(src, rel).not.toMatch(/AsyncStorage|SecureStore/);
      // Fixtures are literals in the file; the one hook the listing harness reads is local auth.
      expect(src, rel).not.toMatch(/\.insert\(|\.update\(|\.delete\(|\.upsert\(/);
    }
    // The listing harness reads the viewer, and that is the ONLY hook it adds over the others.
    expect(strip(FILES.listing)).toContain("import { useAuth } from '@/src/hooks/useAuth';");
    expect(strip(FILES.home)).not.toContain('useAuth');
    expect(strip(FILES.account)).not.toContain('useAuth');
  });
});
