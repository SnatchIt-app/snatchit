/**
 * src/lib/auth/returnToNav.ts — how a sign-in opens the remembered screen (CFT-603, review RAS-1).
 *
 * WHY NOT A BARE REPLACE. The root routes a sign-in by replacing the screen on top of the root stack (Sign in).
 * Home was always safe that way: whatever stays under it, the person has the tabs. A remembered screen is not.
 *  - When Sign in is the only screen in the root stack (a cold start with no link replaced the tabs with Sign in;
 *    a link then opened a listing; Back returned to Sign in), replacing it leaves the listing as the ONLY screen:
 *    no tab bar, and a Back button that does nothing (router.back() with nothing underneath, leaveScreen.ts).
 *  - When an earlier Sign in sits lower in the stack (a listing link, Place a bid, Confirm → Sign in), Back from
 *    the restored screen walks down to Sign in while signed in, and that screen never navigates by itself.
 *
 * THE RULE. The restored screen always has the tabs under it and no Sign in anywhere below it.
 *  - The stack under Sign in already starts with the tabs and holds no Sign in (an expiry; a link opened at cold
 *    start, which expo-router anchors on the tabs): replace Sign in, exactly as for Home. Only Sign in leaves the
 *    stack — the same screen build 29's sign-in removes.
 *  - Otherwise, or when the stack cannot be read: reset the root stack to [tabs, screen]. The tabs are kept as
 *    they are when they are already at the bottom (same route, so they do not remount); otherwise new tabs on
 *    Home. Every other screen under Sign in leaves the stack, so its removal listeners run as for any pop.
 *
 * HOW THE RESET RUNS. Through expo-router's navigation container (useNavigationContainerRef, handed to the root
 * layout by useReturnToCapture): `reset` dispatches React Navigation's RESET to the focused navigator; the
 * (auth) stack has no '(tabs)' screen and refuses it, so it bubbles to the root stack, which has every screen it
 * names. The names come only from RETURN_TO_ROUTES (returnTo.ts) and each one is a Stack.Screen in the root
 * layout (pinned by tests/return-to-restore.test.ts). Nothing here reads a listing, places a bid or touches
 * checkout: it opens a screen, which then reads fresh and waits for a tap.
 *
 * The plan is pure (rootRestoreReset); restoreOnTabs is the one place it is carried out.
 */
import type { NavigationState, PartialState } from '@react-navigation/native';

import { returnToStackRoute } from '@/src/lib/auth/returnTo';

export const TABS_ROUTE = '(tabs)';
export const SIGN_IN_ROUTE = '(auth)';

/** A partial root-stack state for React Navigation's RESET: the tabs, then the remembered screen. */
export type RootResetState = PartialState<NavigationState>;
export type RestoreRoute = RootResetState['routes'][number];

/** The two calls this module makes on expo-router's navigation container. */
export interface RootNavigation {
  getRootState(): unknown;
  reset(state: RootResetState): void;
}

/** New tabs, on Home — the same screen a sign-in without a remembered screen lands on. */
export const HOME_TABS_ROUTE: RestoreRoute = { name: TABS_ROUTE, params: { screen: 'home' } };

interface StackLike {
  index: number;
  routes: RestoreRoute[];
  routeNames?: unknown;
}

function asStack(value: unknown): StackLike | null {
  if (!value || typeof value !== 'object') return null;
  const s = value as { index?: unknown; routes?: unknown };
  if (!Array.isArray(s.routes) || s.routes.length === 0) return null;
  if (!s.routes.every((r) => !!r && typeof r === 'object' && typeof (r as { name?: unknown }).name === 'string')) return null;
  const index = typeof s.index === 'number' && s.index >= 0 && s.index < s.routes.length ? s.index : s.routes.length - 1;
  return { index, routes: s.routes as RestoreRoute[], routeNames: (value as { routeNames?: unknown }).routeNames };
}

/**
 * The root stack inside the container's state: the first navigator on the focused path that has the tabs as one
 * of its screens. expo-router wraps it in its own '__root' slot, so the container state itself is not it.
 */
export function findRootStack(rootState: unknown): StackLike | null {
  let state: unknown = rootState;
  for (let depth = 0; depth < 6; depth++) {
    const stack = asStack(state);
    if (!stack) return null;
    if (Array.isArray(stack.routeNames) && stack.routeNames.includes(TABS_ROUTE)) return stack;
    state = stack.routes[stack.index]?.state;
  }
  return null;
}

/**
 * The reset that opens `to` with the tabs under it, or null when the root should replace as before: `to` is Home,
 * login or anything not on the allowlist, or the stack under the current screen already starts with the tabs and
 * holds no Sign in.
 */
export function rootRestoreReset(to: unknown, rootState: unknown): RootResetState | null {
  const screen = returnToStackRoute(to);
  if (!screen) return null;
  const stack = findRootStack(rootState);
  const below = stack ? stack.routes.slice(0, stack.index) : [];
  const tabsAtBottom = below[0]?.name === TABS_ROUTE;
  if (stack && tabsAtBottom && !below.some((r) => r.name === SIGN_IN_ROUTE)) return null;
  return { index: 1, routes: [tabsAtBottom ? below[0] : HOME_TABS_ROUTE, screen] };
}

/**
 * Carry out the plan for the root layout: true when it reset the root stack, false when the caller should
 * replace with `to` as before (and when there is no container to reset).
 */
export function restoreOnTabs(to: string, navigation: RootNavigation | null | undefined): boolean {
  if (!navigation || !returnToStackRoute(to)) return false;
  const reset = rootRestoreReset(to, navigation.getRootState());
  if (!reset) return false;
  navigation.reset(reset);
  return true;
}
