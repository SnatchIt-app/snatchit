/**
 * CFT-603 reviews RAS-5 and RAS-1 — the REAL root layout, driven through whole sequences.
 *
 * The first cut guarded the layout's wiring with regexes over its source (RW2, RW4, RL1-RL5): removing the
 * clearReturnTo effect or moving the settle above the navigate gate was caught only by a text match, and a rewrite
 * with the same meaning would break them. Here app/_layout.tsx's RootLayout itself runs under the repo's hook host
 * (tests/helpers/nav-stack-harness.ts): its real effects, in their real order, with the real rootRouteDecision,
 * returnTo store, sessionEnd marks, capture hook and returnToNav plan, and the platform shell's web passthrough.
 * Mocked: auth (a session you set), the hold and sign-up stores' subscriptions (read on each render), fonts, the
 * view primitives, and expo-router — whose root
 * stack is modelled here as a list of routes: router.replace swaps the top route (queued, as expo-router queues
 * it); the container's reset replaces the list; a test pushes and pops screens the way a person does.
 * The regex pins in return-to-routing.test.ts stay as a second line of defence. NOT device evidence.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

// vi.mock calls below are hoisted above these imports by vitest, so these modules see the mocks.
import { setOnboarding } from '@/src/lib/auth/onboardingGate';
import { setRecoveryHold } from '@/src/lib/auth/recoveryHold';
import { forgetReturnToForAuthLink, peekReturnTo, resetReturnToForTests, returnToStackRoute } from '@/src/lib/auth/returnTo';
import { consumeSessionEnd, markSessionEnd, markSessionEndIfUnmarked } from '@/src/lib/auth/sessionEnd';
import { HookHost } from './helpers/nav-stack-harness';

(globalThis as Record<string, unknown>).__DEV__ = false;

const h = vi.hoisted(() => {
  type Route = { key: string; name: string; params?: Record<string, unknown>; state?: unknown };
  const ROOT_ROUTE_NAMES = ['(tabs)', '(auth)', 'listing/[id]', 'bid/[id]', 'profile/[id]', 'my-listings', 'transfer/send/[id]', 'transfer/receive/[id]', 'checkout/[id]', 'primary-checkout/[session]', 'ticket/[session]'];
  /** A route's path, as expo-router's pathname: the dynamic segment filled in, the query never part of it. */
  const pathOf = (r: Route) => `/${r.name.replace(/\[(id|session)\]/, (_, k: string) => String(r.params?.[k]))}`;
  const m = {
    auth: { session: null as null | { user: { id: string } }, loading: false },
    routes: [] as Route[],
    queue: [] as string[],
    replaced: [] as string[],
    resets: 0,
    seq: 0,
    top(): Route | undefined { return m.routes[m.routes.length - 1]; },
    pathname(): string {
      const r = m.top();
      if (!r) return '/';
      if (r.name === '(tabs)') return '/home';
      if (r.name === '(auth)') return '/login';
      return pathOf(r);
    },
    segments(): string[] {
      const r = m.top();
      if (!r) return [];
      if (r.name === '(tabs)') return ['(tabs)', 'home'];
      if (r.name === '(auth)') return ['(auth)', 'login'];
      return r.name.split('/');
    },
    container: {
      getRootState: () => ({
        index: 0, routeNames: ['__root'],
        routes: [{ key: 'slot', name: '__root', state: { index: m.routes.length - 1, routeNames: ROOT_ROUTE_NAMES, routes: m.routes } }],
      }),
      reset: (s: { routes: Route[] }) => {
        m.resets += 1;
        m.routes = s.routes.map((r) => ({ ...r, key: r.key ?? `${r.name}-${++m.seq}` }));
      },
    },
  };
  return Object.assign(m, { pathOf });
});

vi.mock('react-native-get-random-values', () => ({}));
vi.mock('react-native', () => ({
  ActivityIndicator: 'ActivityIndicator', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, absoluteFill: {} },
}));
vi.mock('react-native-safe-area-context', () => ({ SafeAreaProvider: 'SafeAreaProvider', useSafeAreaInsets: () => ({ top: 0 }) }));
vi.mock('@react-navigation/native', () => ({ DarkTheme: { colors: {} }, DefaultTheme: { colors: {} }, ThemeProvider: 'ThemeProvider' }));
vi.mock('expo-splash-screen', () => ({ preventAutoHideAsync: () => Promise.resolve(), hideAsync: () => Promise.resolve() }));
vi.mock('expo-status-bar', () => ({ StatusBar: 'StatusBar' }));
vi.mock('expo-router', () => ({
  router: { replace: (href: string) => { h.queue.push(href); } },
  Stack: Object.assign(() => null, { Screen: () => null }),
  useSegments: () => h.segments(),
  usePathname: () => h.pathname(),
  useNavigationContainerRef: () => h.container,
}));
vi.mock('@/src/theme/appearance', () => ({ AppearanceProvider: 'AppearanceProvider', useTheme: () => ({ scheme: 'dark', palette: {} }) }));
vi.mock('@/src/theme/fonts', () => ({ useBrandFonts: () => true }));
vi.mock('@/src/config/envGuard', () => ({ ENV_GUARD_FAILURE: null, IS_SANDBOX_BUILD: false }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => h.auth }));
vi.mock('@/src/hooks/useReducedMotion', () => ({ useReducedMotion: () => false }));
vi.mock('@/src/lib/supabase', () => ({
  supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) } },
}));
vi.mock('@react-native-async-storage/async-storage', () => ({ default: {} }));
vi.mock('@/src/lib/auth/recoveryMarker', () => ({
  clearRecoveryPending: async () => {}, markRecoveryPending: async () => {}, recoveryPendingFor: async () => false,
}));
// The hold and sign-up stores are real; only their React subscription is replaced by a read on each render
// (the hook host has no useSyncExternalStore). A test that changes either re-renders the root itself.
vi.mock('@/src/lib/auth/recoveryHold', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/src/lib/auth/recoveryHold')>();
  return { ...real, useRecoveryHold: () => [real.getRecoveryHold(), real.setRecoveryHold] };
});
vi.mock('@/src/lib/auth/onboardingGate', async (importOriginal) => {
  const real = await importOriginal<typeof import('@/src/lib/auth/onboardingGate')>();
  return { ...real, useIsOnboarding: () => real.isOnboarding() };
});
vi.mock('@/src/components/ErrorBoundary', () => ({ default: 'ErrorBoundary' }));
vi.mock('@/src/components/ui/Spinner', () => ({ Spinner: 'Spinner' }));
// The platform shell resolves to its web passthrough under vitest (vitest.config.ts): no deep links, no push.


const LISTING = '/listing/4a1d2c3b-0000-4000-8000-00000000abcd';
const BID = '/bid/4a1d2c3b-0000-4000-8000-00000000abcd';
const tick = () => new Promise((r) => setImmediate(r));

function routeFor(href: string): { name: string; params?: Record<string, unknown> } {
  if (href === '/(tabs)/home') return { name: '(tabs)', params: { screen: 'home' } };
  if (href === '/(auth)/login') return { name: '(auth)' };
  // D6: the session screens, with a link's query carried as route params the way expo-router carries it.
  const session = /^\/(primary-checkout|ticket)\/([^/?#]+)(?:\?(.*))?$/.exec(href);
  if (session) return { name: `${session[1]}/[session]`, params: { ...Object.fromEntries(new URLSearchParams(session[3] ?? '')), session: session[2] } };
  const screen = returnToStackRoute(href);
  if (!screen) throw new Error(`unmodelled href ${href}`);
  return screen;
}
const key = (name: string) => `${name}-${++h.seq}`;
const stackNames = () => h.routes.map((r) => (r.name === '(tabs)' || r.name === '(auth)' ? r.name : h.pathOf(r)));

let host: HookHost;
/** expo-router's queue runs after the effects that filled it; then the root re-renders on the new route. */
async function settle() {
  for (let i = 0; i < 12; i++) {
    await tick();
    while (h.queue.length) {
      const href = h.queue.shift()!;
      h.replaced.push(href);
      h.routes[h.routes.length - 1] = { key: key(href), ...routeFor(href) };
    }
    host.flush();
  }
}
async function launch(initial: string[], session: string | null) {
  h.routes = initial.map((href) => ({ key: key(href), ...routeFor(href) }));
  h.auth.session = session ? { user: { id: session } } : null;
  const { default: RootLayout } = await import('@/app/_layout');
  host = new HookHost(() => (RootLayout as () => unknown)(), new Map());
  host.mount();
  await settle();
}
async function act(change: () => void) { change(); host.flush(); await settle(); }
const push = (href: string) => act(() => { h.routes.push({ key: key(href), ...routeFor(href) }); });
const back = () => act(() => { h.routes.pop(); });
const signIn = (id: string) => act(() => { h.auth.session = { user: { id } }; });
/** PlaceBidScreen's Confirm while signed out: Alert, then router.replace('/(auth)/login') (build 29). */
const confirmBidSignedOut = () => act(() => { h.queue.push('/(auth)/login'); });

beforeEach(() => {
  resetReturnToForTests(); consumeSessionEnd(); setRecoveryHold(false); setOnboarding(false);
  h.routes = []; h.queue = []; h.replaced = []; h.resets = 0; h.auth = { session: null, loading: false };
});

describe('RAS-1 — a sign-in opens the remembered screen with the tabs under it', () => {
  it('LR1: cold start signed out, a link, Back to Sign in, sign in — [tabs, listing], not the listing alone', async () => {
    await launch(['/(tabs)/home'], null);                 // expo-router anchors a cold start on the tabs
    expect(stackNames()).toEqual(['(auth)']);             // the first route replaced them with Sign in
    await push(LISTING);                                  // a warm snatchit://listing/<id> link
    await back();                                         // Buy now is a dead end signed out: Back to Sign in
    expect(stackNames()).toEqual(['(auth)']);
    await signIn('user-a');
    expect(stackNames()).toEqual(['(tabs)', LISTING]);
    expect(h.resets).toBe(1);
    expect(h.replaced).toEqual(['/(auth)/login']);        // the listing was never a bare replace
    expect(peekReturnTo('user-a')).toBeNull();            // single use
  });

  it('LR2: a listing link, Place a bid, Confirm, sign in — [tabs, bid]: no Sign in and no duplicate listing underneath', async () => {
    await launch(['/(tabs)/home'], null);
    await push(LISTING);
    await push(BID);
    await confirmBidSignedOut();
    expect(stackNames()).toEqual(['(auth)', LISTING, '(auth)']);
    await signIn('user-a');
    expect(stackNames()).toEqual(['(tabs)', BID]);
  });

  it('LR3: a link opened at cold start — anchored on the tabs — comes back by the same replace as Home', async () => {
    await launch(['/(tabs)/home', LISTING], null);
    expect(stackNames()).toEqual(['(tabs)', '(auth)']);
    await signIn('user-a');
    expect(stackNames()).toEqual(['(tabs)', LISTING]);
    expect(h.resets).toBe(0);
    expect(h.replaced).toEqual(['/(auth)/login', LISTING]);
  });

  it('LR4: an expiry on a listing comes back for the same user over the stack it left; another user goes Home', async () => {
    await launch(['/(tabs)/home'], 'user-a');
    await push(LISTING);
    await act(() => { markSessionEndIfUnmarked('expired'); h.auth.session = null; });
    expect(stackNames()).toEqual(['(tabs)', '(auth)']);
    await signIn('user-a');
    expect(stackNames()).toEqual(['(tabs)', LISTING]);

    await act(() => { markSessionEndIfUnmarked('expired'); h.auth.session = null; });
    await signIn('user-b');
    expect(stackNames()).toEqual(['(tabs)', '(tabs)']);   // Home, by the same replace as build 29
    expect(h.replaced.at(-1)).toBe('/(tabs)/home');
  });

  it('LR5: a deliberate sign-out remembers nothing — the next sign-in goes Home', async () => {
    await launch(['/(tabs)/home'], 'user-a');
    await push(LISTING);
    await act(() => { markSessionEnd('user'); h.auth.session = null; });
    await signIn('user-a');
    expect(h.replaced.at(-1)).toBe('/(tabs)/home');
    expect(h.resets).toBe(0);
  });
});

describe('RAS-5 — recovery and sign up, through the real root', () => {
  it('LR6: remembered while signed out, then the recovery hold goes up: the session is held, and on release it goes Home', async () => {
    await launch(['/(tabs)/home'], null);
    await push(LISTING);
    await back();
    expect(peekReturnTo('user-a')).toBe(LISTING);
    await act(() => { setRecoveryHold(true); });           // the recovery link's claim raised the hold
    expect(peekReturnTo('user-a')).toBeNull();             // the root dropped the screen when the hold rose
    const before = h.replaced.length;
    await signIn('user-a');                                // the link minted a session for user A
    expect(h.replaced.length).toBe(before);                // held: the root did not move
    expect(h.resets).toBe(0);
    await act(() => { setRecoveryHold(false); });          // released with the session still there
    expect(h.replaced.at(-1)).toBe('/(tabs)/home');
    expect(h.resets).toBe(0);
    expect(stackNames()).not.toContain(LISTING);
  });

  it('LR7: the warm late-fallback race — SIGNED_IN before the hold — opens Home once the shell has dropped the screen (RAS-2)', async () => {
    await launch(['/(tabs)/home'], null);
    await push(LISTING);
    await back();
    forgetReturnToForAuthLink('snatchit://?code=late-fallback');   // the shell's funnel, before dispatch
    await signIn('user-a');                                          // SIGNED_IN reaches the root, no hold yet
    expect(h.replaced.at(-1)).toBe('/(tabs)/home');
    expect(h.resets).toBe(0);
  });

  it('LR8: sign up holds the root while its session appears, and on release returns the person to the listing', async () => {
    await launch(['/(tabs)/home'], null);
    await push(LISTING);
    await back();
    await act(() => { setOnboarding(true); });
    await signIn('new-user');                              // the account is created part way through sign up
    expect(h.resets).toBe(0);
    expect(peekReturnTo('new-user')).toBe(LISTING);        // a hold neither navigates nor uses it up
    await act(() => { setOnboarding(false); });
    expect(stackNames()).toEqual(['(tabs)', LISTING]);
    expect(peekReturnTo('new-user')).toBeNull();
  });

  it('LR9: nothing is remembered while a hold is up — a listing opened during recovery or sign up is not captured', async () => {
    await launch(['/(tabs)/home'], null);
    await act(() => { setOnboarding(true); });
    await push(LISTING);
    expect(peekReturnTo('anyone')).toBeNull();
    await back();
    await act(() => { setOnboarding(false); setRecoveryHold(true); });
    await push(LISTING);
    expect(peekReturnTo('anyone')).toBeNull();
  });
});

describe('D6 — a cold payment return, through the real root', () => {
  const S = '5e55e55e-c0de-4abc-8def-00000000beef';
  const CHECKOUT = `/primary-checkout/${S}`;
  const TICKET = `/ticket/${S}`;
  // The 3-D Secure / bank-app return URL's own query, plus what a payment provider may append. None of it is read.
  const RETURN_QUERY = '?tt=7ab1e5e5-c0de-4abc-8def-00000000cafe&qty=2&attempt=attempt-abc123'
    + '&payment_intent=REDACTED&payment_intent_client_secret=REDACTED&redirect_status=failed';

  it('LP1: iOS relaunches a killed app onto [tabs, checkout], signed in — the ticket page opens over the tabs, and Back reaches them', async () => {
    await launch(['/(tabs)/home', `${CHECKOUT}${RETURN_QUERY}`], 'user-a');
    expect(stackNames()).toEqual(['(tabs)', TICKET]);
    expect(h.replaced).toEqual([TICKET]);                 // one replace of the checkout; not Home, never the checkout kept
    expect(h.resets).toBe(0);
    await back();
    expect(stackNames()).toEqual(['(tabs)']);
  });

  it('LP2: the same relaunch signed out goes to Sign in exactly as before', async () => {
    await launch(['/(tabs)/home', `${CHECKOUT}${RETURN_QUERY}`], null);
    expect(stackNames()).toEqual(['(tabs)', '(auth)']);
    expect(h.replaced).toEqual(['/(auth)/login']);
  });

  it('LP3: every other signed-in cold start still goes Home — no link, a listing link, a malformed checkout link', async () => {
    for (const initial of [['/(tabs)/home'], ['/(tabs)/home', LISTING], ['/(tabs)/home', '/primary-checkout/not-a-uuid']]) {
      resetReturnToForTests(); h.replaced = []; h.resets = 0;
      await launch(initial, 'user-a');
      expect({ initial, replaced: h.replaced, resets: h.resets }).toEqual({ initial, replaced: ['/(tabs)/home'], resets: 0 });
    }
  });

  it('LP4: a checkout opened inside a routed session keeps control — a token refresh moves no one; a sign-out still goes to login', async () => {
    await launch(['/(tabs)/home'], 'user-a');
    await push(`${CHECKOUT}${RETURN_QUERY}`);
    await act(() => { h.auth.session = { user: { id: 'user-a' } }; });   // TOKEN_REFRESHED / USER_UPDATED: a new object
    expect(stackNames()).toEqual(['(tabs)', CHECKOUT]);
    expect(h.replaced).toEqual(['/(tabs)/home']);
    await act(() => { markSessionEnd('user'); h.auth.session = null; });
    expect(stackNames()).toEqual(['(tabs)', '(auth)']);
  });
});
