/**
 * CFT-603 review RAS-1 — a remembered screen opens with the tabs under it and no Sign in below it.
 *
 * The first cut restored with a bare router.replace(screen). That replaces the screen on top of the root stack,
 * which is fine for Home (the tabs) but not for a listing:
 *  - [(auth)] (a cold start with no link, then a link, then Back to Sign in) became [listing]: no tab bar, and a
 *    Back button that does nothing;
 *  - [(auth), listing, (auth)'] (Place a bid → Confirm → Sign in) became [(auth), listing, bid]: Back twice
 *    reaches Sign in while signed in.
 * returnToNav.ts plans the navigation instead. These suites check the plan (pure), run it through React
 * Navigation's real routers (the reset is refused by the Sign in stack and taken by the root stack), pin the route
 * names it can produce to the screens the root layout declares, and pin the library code the dispatch relies on.
 * NOT device evidence: the two simulator checks (the [(auth)] shape and the Place-a-bid shape) are still open.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { CommonActions, StackRouter } from '@react-navigation/routers';
import { describe, expect, it, vi } from 'vitest';

import { RETURN_TO_ROUTES, returnToStackRoute } from '../src/lib/auth/returnTo';
import {
  HOME_TABS_ROUTE,
  findRootStack,
  restoreOnTabs,
  rootRestoreReset,
  type RootNavigation,
  type RootResetState,
} from '../src/lib/auth/returnToNav';

const ID = '4a1d2c3b-0000-4000-8000-00000000abcd';
const LISTING = `/listing/${ID}`;
const BID = `/bid/${ID}`;

// The root Stack's screens, as app/_layout.tsx declares them (pinned in RS9).
const ROOT_ROUTE_NAMES = [
  '(tabs)', '(auth)', 'listing/[id]', 'listing/edit/[id]', 'bid/[id]', 'checkout/[id]', 'settings/index',
  'my-listings', 'transfer/receive/[id]', 'transfer/send/[id]', 'profile/[id]',
];

type R = { key: string; name: string; params?: object; state?: unknown };
let n = 0;
const route = (name: string, params?: object, state?: unknown): R => ({ key: `${name}-${++n}`, name, ...(params ? { params } : {}), ...(state ? { state } : {}) });
const stack = (routes: R[]) => ({
  stale: false as const, type: 'stack', key: 'root-stack', index: routes.length - 1, routeNames: ROOT_ROUTE_NAMES, routes, preloadedRoutes: [],
});
/** What expo-router's container holds: its own '__root' slot around the root Stack. */
const container = (routes: R[]) => ({
  stale: false as const, type: 'stack', key: 'slot', index: 0, routeNames: ['__root'], routes: [{ key: '__root-0', name: '__root', state: stack(routes) }],
});
const authStack = (names = ['login']) => ({
  stale: false as const, type: 'stack', key: 'auth-stack', index: names.length - 1, routeNames: ['login', 'signup', 'reset-password'],
  routes: names.map((nm) => route(nm)), preloadedRoutes: [],
});
const names = (s: { routes: { name: string }[] }) => s.routes.map((r) => r.name);

describe('returnToStackRoute — the route a remembered screen opens as', () => {
  it('RS1: each allowlisted screen maps to its own root Stack route, with its id when it has one', () => {
    expect(returnToStackRoute(LISTING)).toEqual({ name: 'listing/[id]', params: { id: ID } });
    expect(returnToStackRoute('/bid/abc')).toEqual({ name: 'bid/[id]', params: { id: 'abc' } });
    expect(returnToStackRoute('/profile/u_1')).toEqual({ name: 'profile/[id]', params: { id: 'u_1' } });
    expect(returnToStackRoute('/transfer/send/t1')).toEqual({ name: 'transfer/send/[id]', params: { id: 't1' } });
    expect(returnToStackRoute('/transfer/receive/t2')).toEqual({ name: 'transfer/receive/[id]', params: { id: 't2' } });
    expect(returnToStackRoute('/my-listings')).toEqual({ name: 'my-listings' });
    // the query never rides along
    expect(returnToStackRoute(`${LISTING}?amount=500&confirm=1`)).toEqual({ name: 'listing/[id]', params: { id: ID } });
  });

  it('RS2: anything the allowlist rejects has no route — Home, login, checkout, a host, a tab', () => {
    for (const to of ['/(tabs)/home', '/(auth)/login', '/checkout/1', '//evil.example/listing/1', '/home', '/', null, 42]) {
      expect({ to, got: returnToStackRoute(to) }).toEqual({ to, got: null });
    }
  });
});

describe('rootRestoreReset — the plan', () => {
  it("RS3: the reviewer's first shape — Sign in alone at the root — opens [new tabs on Home, listing]", () => {
    const plan = rootRestoreReset(LISTING, container([route('(auth)', undefined, authStack())]));
    expect(plan).toEqual({ index: 1, routes: [HOME_TABS_ROUTE, { name: 'listing/[id]', params: { id: ID } }] });
    expect(HOME_TABS_ROUTE).toEqual({ name: '(tabs)', params: { screen: 'home' } });
  });

  it('RS4: the second shape — an earlier Sign in under the listing (Place a bid → Confirm) — leaves no Sign in below', () => {
    const plan = rootRestoreReset(BID, container([route('(auth)'), route('listing/[id]', { id: ID }), route('(auth)', undefined, authStack())]));
    expect(plan).toEqual({ index: 1, routes: [HOME_TABS_ROUTE, { name: 'bid/[id]', params: { id: ID } }] });
    // the same with Sign up on top of that Sign in (the onboarding hold released)
    const viaSignUp = rootRestoreReset(BID, container([route('(auth)'), route('listing/[id]', { id: ID }), route('(auth)', undefined, authStack(['login', 'signup']))]));
    expect(viaSignUp && names(viaSignUp)).toEqual(['(tabs)', 'bid/[id]']);
  });

  it('RS5: the tabs already at the bottom are kept as they are (same route, no remount) when a Sign in sits above them', () => {
    const tabs = route('(tabs)', undefined, { index: 2, routes: [{ name: 'home' }, { name: 'create' }, { name: 'bids' }] });
    const plan = rootRestoreReset(BID, container([tabs, route('(auth)'), route('listing/[id]', { id: ID }), route('(auth)')]));
    expect(plan?.routes[0]).toBe(tabs);
    expect(plan && names(plan)).toEqual(['(tabs)', 'bid/[id]']);
  });

  it('RS6: tabs at the bottom and no Sign in below — an expiry, a link opened at cold start — replace as for Home', () => {
    expect(rootRestoreReset(LISTING, container([route('(tabs)'), route('(auth)')]))).toBeNull();
    expect(rootRestoreReset(BID, container([route('(tabs)'), route('listing/[id]', { id: ID }), route('(auth)')]))).toBeNull();
    expect(rootRestoreReset('/my-listings', container([route('(tabs)'), route('profile/[id]', { id: 'u' }), route('(auth)')]))).toBeNull();
  });

  it('RS7: Home and login are never a restore — the root replaces them exactly as before', () => {
    for (const to of ['/(tabs)/home', '/(auth)/login']) {
      expect(rootRestoreReset(to, container([route('(auth)')]))).toBeNull();
      expect(rootRestoreReset(to, undefined)).toBeNull();
    }
  });

  it('RS8: a state it cannot read never strands the screen — it still resets to [tabs on Home, screen]', () => {
    for (const unreadable of [undefined, null, {}, { routes: [] }, { routes: [{ name: '__root' }] }, 'x']) {
      expect(rootRestoreReset(LISTING, unreadable)).toEqual({ index: 1, routes: [HOME_TABS_ROUTE, { name: 'listing/[id]', params: { id: ID } }] });
    }
    // and the root Stack is found inside the container's slot, not mistaken for it
    expect(findRootStack(container([route('(tabs)'), route('(auth)')]))?.routes.map((r) => r.name)).toEqual(['(tabs)', '(auth)']);
    expect(findRootStack(stack([route('(auth)')]))?.routes.map((r) => r.name)).toEqual(['(auth)']);
  });
});

describe('restoreOnTabs — the one place the plan runs', () => {
  const nav = (rootState: unknown) => {
    const resets: RootResetState[] = [];
    const getRootState = vi.fn(() => rootState);
    const navigation: RootNavigation = { getRootState, reset: (s) => { resets.push(s); } };
    return { navigation, resets, getRootState };
  };

  it('RS10: a remembered screen over a lone Sign in is reset onto the tabs; the caller does not replace', () => {
    const { navigation, resets } = nav(container([route('(auth)')]));
    expect(restoreOnTabs(LISTING, navigation)).toBe(true);
    expect(resets.map(names)).toEqual([['(tabs)', 'listing/[id]']]);
  });

  it('RS11: Home and login are left to the caller, without even reading the navigation state', () => {
    const { navigation, resets, getRootState } = nav(container([route('(auth)')]));
    expect(restoreOnTabs('/(tabs)/home', navigation)).toBe(false);
    expect(restoreOnTabs('/(auth)/login', navigation)).toBe(false);
    expect(getRootState).not.toHaveBeenCalled();
    expect(resets).toEqual([]);
  });

  it('RS12: tabs-rooted stacks are left to the caller (a replace); no container means a replace too', () => {
    const { navigation, resets } = nav(container([route('(tabs)'), route('(auth)')]));
    expect(restoreOnTabs(LISTING, navigation)).toBe(false);
    expect(resets).toEqual([]);
    expect(restoreOnTabs(LISTING, null)).toBe(false);
  });
});

describe("the plan through React Navigation's own routers", () => {
  const options = (routeNames: string[]) => ({ routeNames, routeParamList: {}, routeGetIdList: {} });
  const rootRouter = StackRouter({});
  const rootOptions = options(ROOT_ROUTE_NAMES);

  it('RS13 (negative control): the bare replace this replaces leaves the listing as the only screen', () => {
    const before = stack([route('(auth)')]);
    // expo-router turns router.replace('/listing/<id>') into a REPLACE aimed at the root stack (routing.js)
    const after = rootRouter.getStateForAction(before as never, { type: 'REPLACE', target: before.key, payload: { name: 'listing/[id]', params: { id: ID } } }, rootOptions);
    expect(after && names(after)).toEqual(['listing/[id]']);
  });

  it('RS14: the reset is refused by the Sign in stack (it has no tabs screen), so it bubbles up to the root stack', () => {
    const plan = rootRestoreReset(LISTING, container([route('(auth)', undefined, authStack())]))!;
    const auth = authStack();
    expect(StackRouter({}).getStateForAction(auth as never, CommonActions.reset(plan as never), options(auth.routeNames))).toBeNull();
    const taken = rootRouter.getStateForAction(stack([route('(auth)')]) as never, CommonActions.reset(plan as never), rootOptions);
    expect(taken).not.toBeNull();
    const settled = rootRouter.getRehydratedState(taken as never, rootOptions);
    expect(names(settled)).toEqual(['(tabs)', 'listing/[id]']);
    expect(settled.index).toBe(1);
    expect(settled.routes[1].params).toEqual({ id: ID });
    expect(settled.routes.every((r) => typeof r.key === 'string' && r.key.length > 0)).toBe(true);
  });

  it('RS15: the Place-a-bid shape settles to [tabs, bid] — no Sign in and no duplicate listing left anywhere', () => {
    const before = stack([route('(auth)'), route('listing/[id]', { id: ID }), route('(auth)')]);
    const plan = rootRestoreReset(BID, container(before.routes))!;
    const settled = rootRouter.getRehydratedState(rootRouter.getStateForAction(before as never, CommonActions.reset(plan as never), rootOptions) as never, rootOptions);
    expect(names(settled)).toEqual(['(tabs)', 'bid/[id]']);
  });

  it('RS16: kept tabs keep their key and their tab state through the reset', () => {
    const tabs = route('(tabs)', undefined, { stale: false, type: 'tab', key: 'tabs-nav', index: 1, routeNames: ['home', 'bids'], routes: [{ key: 'home-1', name: 'home' }, { key: 'bids-1', name: 'bids' }] });
    const before = stack([tabs, route('(auth)'), route('listing/[id]', { id: ID }), route('(auth)')]);
    const plan = rootRestoreReset(LISTING, container(before.routes))!;
    const settled = rootRouter.getRehydratedState(rootRouter.getStateForAction(before as never, CommonActions.reset(plan as never), rootOptions) as never, rootOptions);
    expect(settled.routes[0].key).toBe(tabs.key);
    expect(settled.routes[0].state).toBe(tabs.state);
  });
});

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const lib = (p: string) => readFileSync(resolve(__dirname, '..', 'node_modules', p), 'utf8');
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('pins — the reset can only name screens that exist, and runs the way the plan assumes', () => {
  it('RS9: every screen the allowlist can open, and the tabs, are root Stack screens; Home is a tab', () => {
    const layout = strip(read('app/_layout.tsx'));
    for (const name of ['(tabs)', ...RETURN_TO_ROUTES.map((r) => r.route)]) {
      expect({ name, declared: layout.includes(`<Stack.Screen name="${name}" />`) }).toEqual({ name, declared: true });
      expect(ROOT_ROUTE_NAMES).toContain(name);
    }
    expect(strip(read('app/(tabs)/_layout.tsx'))).toContain('<Tabs.Screen name="home"');
  });

  it('RS17: the plan module opens screens only — no router, no data, no bid or checkout code', () => {
    const code = strip(read('src/lib/auth/returnToNav.ts'));
    expect(code.match(/^import [\s\S]*?from '[^']+';$/gm)).toEqual([
      "import type { NavigationState, PartialState } from '@react-navigation/native';",
      "import { returnToStackRoute } from '@/src/lib/auth/returnTo';",
    ]);
    expect(code).not.toMatch(/router\.|supabase|placeBid|reserv|checkout\w*\(/i);
    expect((code.match(/navigation\.reset\(/g) ?? []).length).toBe(1);
  });

  it("RS18: React Navigation — the container's reset dispatches through the focused navigator, an unhandled action bubbles to the parent, and RESET refuses unknown screens", () => {
    const container = lib('@react-navigation/core/lib/module/BaseNavigationContainer.js');
    expect(container).toMatch(/listeners\.focus\[0\]\(navigation => navigation\.dispatch\(action\)\);/);
    expect(container).toMatch(/\.\.\.Object\.keys\(CommonActions\)\.reduce\(\(acc, name\) => \{[\s\S]{0,80}dispatch\(CommonActions\[name\]\(\.\.\.args\)\);/);
    const onAction = lib('@react-navigation/core/lib/module/useOnAction.js');
    expect(onAction).toMatch(/if \(onActionParent !== undefined\) \{\s*(\/\/[^\n]*\n\s*)*if \(onActionParent\(action, visitedNavigators\)\) \{\s*return true;/);
    const base = lib('@react-navigation/routers/lib/module/BaseRouter.js');
    expect(base).toMatch(/case 'RESET':\s*\{\s*const nextState = action\.payload;\s*if \(nextState\.routes\.length === 0 \|\| nextState\.routes\.some\(route => !state\.routeNames\.includes\(route\.name\)\)\) \{\s*return null;/);
    expect(lib('@react-navigation/routers/lib/module/StackRouter.js')).toMatch(/default:\s*return BaseRouter\.getStateForAction\(state, action\);/);
  });

  it("RS19: expo-router — its Stack hands RESET to React Navigation's router, and useNavigationContainerRef is the container", () => {
    const stackClient = lib('expo-router/build/layouts/StackClient.js');
    const isStackAction = stackClient.slice(stackClient.indexOf('function isStackAction('), stackClient.indexOf('const isPreviewAction'));
    expect(isStackAction).not.toContain("'RESET'");
    expect(stackClient).toMatch(/if \(!isStackAction\(action\)\) \{\s*return original\.getStateForAction\(state, action, options\);/);
    expect(lib('expo-router/build/hooks.js')).toMatch(/function useNavigationContainerRef\(\) \{\s*return router_store_1\.store\.navigationRef;/);
    // the container state wraps the root Stack in expo-router's '__root' slot (findRootStack descends through it)
    expect(lib('expo-router/build/global-state/routeInfo.js')).toContain('Expected the first route to be ${constants_1.INTERNAL_SLOT_NAME}');
  });
});
