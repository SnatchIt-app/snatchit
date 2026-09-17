/**
 * tests/helpers/nav-stack-harness.ts — run a REAL screen module and its REAL navigation
 * hooks inside a stack navigator, in vitest's node environment, with no native renderer.
 *
 * Real code under this harness:
 *  - the screen component and every hook it calls (React's hook API is driven by the small
 *    dispatcher below — one component per route, effects run after each render);
 *  - @react-navigation/core: usePreventRemove, useNavigation, useRoute, and
 *    shouldPreventRemove — the `beforeRemove` gate every navigator runs before a route leaves
 *    its state (including the VISITED_ROUTE_KEYS mark that lets a replayed action through);
 *  - @react-navigation/routers: StackRouter (POP, GO_BACK).
 *
 * Modelled, each pinned to the installed library source by the suite that uses it:
 *  - native-stack's NativeStackView (iOS): `preventNativeDismiss` is
 *    `preventedRoutes[route.key]?.preventRemove`; `onDismissed` and `onNativeDismissCancelled`
 *    both dispatch `pop(dismissCount)` with `source: route.key`; `useDismissedRouteError` logs a
 *    screen that native removed but JS kept;
 *  - react-native-screens (iOS): an edge swipe on a screen whose `preventNativeDismiss` is set is
 *    cancelled natively (the screen stays) and reported as `onNativeDismissCancelled`; without
 *    it UIKit completes the pop first — the view is gone — and then reports `onDismissed`. A pop
 *    that starts in JS is never cancelled natively; the native stack follows the JS routes;
 *  - PreventRemoveProvider: one registration per hook id, `preventedRoutes` keyed by route;
 *  - expo-router's `router.back()`: `GO_BACK` dispatched through the container to the focused
 *    stack, with no source;
 *  - the per-screen navigation object (useNavigationCache): `dispatch` adds `source: route.key`.
 *
 * Not modelled: layout, animation timing, the keyboard, Android's predictive back.
 */
import { realpathSync } from 'node:fs';
import { resolve } from 'node:path';
import * as React from 'react';
import {
  NavigationContext,
  NavigationRouteContext,
  PreventRemoveContext,
} from '@react-navigation/core';
import { CommonActions, StackActions, StackRouter } from '@react-navigation/routers';

export const REPO_ROOT = resolve(__dirname, '..', '..');

// ── A minimal hook dispatcher ────────────────────────────────────────────

type Deps = readonly unknown[] | undefined;
type EffectFn = () => void | (() => void);
interface EffectSlot { tag: 'effect'; layout: boolean; fresh: boolean; deps: Deps; create?: EffectFn; cleanup?: () => void }

interface ReactInternals { H: unknown }
const internals = (React as unknown as { __CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE?: ReactInternals })
  .__CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE;
if (!internals || !('H' in internals)) {
  throw new Error('nav-stack-harness: React hook dispatcher slot not found — update the harness for this React version');
}

const depsChanged = (a: Deps, b: Deps) =>
  a === undefined || b === undefined || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]));

export class HookHost {
  output: unknown;
  mounted = false;
  private slots: unknown[] = [];
  private cursor = 0;
  private busy = false;
  private again = false;
  private queue: EffectSlot[] = [];

  constructor(private readonly component: () => unknown, private readonly contexts: Map<unknown, unknown>) {}

  mount(): void {
    this.mounted = true;
    this.flush();
  }

  unmount(): void {
    for (const s of this.slots) {
      const e = s as Partial<EffectSlot>;
      if (e.tag === 'effect' && e.cleanup) { e.cleanup(); e.cleanup = undefined; }
    }
    this.mounted = false;
  }

  /** Render, run effects, and repeat until no state changed. */
  flush(): void {
    if (!this.mounted) return;
    if (this.busy) { this.again = true; return; }
    this.busy = true;
    try {
      let rounds = 0;
      do {
        if (++rounds > 50) throw new Error('nav-stack-harness: renders did not settle');
        this.again = false;
        this.render();
        this.runEffects();
      } while (this.again && this.mounted);
    } finally {
      this.busy = false;
    }
  }

  private render(): void {
    const previous = internals!.H;
    internals!.H = this.dispatcher;
    this.cursor = 0;
    this.queue = [];
    try {
      this.output = this.component();
    } finally {
      internals!.H = previous;
    }
  }

  private runEffects(): void {
    const queue = [...this.queue.filter((e) => e.layout), ...this.queue.filter((e) => !e.layout)];
    this.queue = [];
    for (const e of queue) if (e.cleanup) { e.cleanup(); e.cleanup = undefined; }
    for (const e of queue) {
      if (!this.mounted) return;
      const create = e.create!;
      e.create = undefined;
      const cleanup = create();
      if (typeof cleanup === 'function') e.cleanup = cleanup;
    }
  }

  private slot<V>(init: () => V): V {
    const i = this.cursor++;
    if (i === this.slots.length) this.slots.push(init());
    return this.slots[i] as V;
  }

  private effect(layout: boolean, create: EffectFn, deps: Deps): void {
    const e = this.slot<EffectSlot>(() => ({ tag: 'effect', layout, fresh: true, deps: undefined }));
    if (e.fresh || depsChanged(e.deps, deps)) {
      e.fresh = false;
      e.deps = deps;
      e.create = create;
      this.queue.push(e);
    }
  }

  private memo<V>(factory: () => V, deps: Deps): V {
    const m = this.slot<{ value?: V; deps: Deps; fresh: boolean }>(() => ({ deps: undefined, fresh: true }));
    if (m.fresh || depsChanged(m.deps, deps)) { m.fresh = false; m.deps = deps; m.value = factory(); }
    return m.value as V;
  }

  private readonly dispatcher: object = new Proxy(
    {
      useState: <S>(initial: S | (() => S)) => {
        const cell = this.slot(() => {
          const c = {
            value: typeof initial === 'function' ? (initial as () => S)() : initial,
            set: (next: S | ((prev: S) => S)) => {
              const value = typeof next === 'function' ? (next as (prev: S) => S)(c.value) : next;
              if (Object.is(value, c.value)) return;
              c.value = value;
              this.flush();
            },
          };
          return c;
        });
        return [cell.value, cell.set];
      },
      useRef: <V>(initial: V) => this.slot(() => ({ current: initial })),
      useMemo: <V>(factory: () => V, deps: Deps) => this.memo(factory, deps),
      useCallback: <F>(fn: F, deps: Deps) => this.memo(() => fn, deps),
      useEffect: (create: EffectFn, deps: Deps) => this.effect(false, create, deps),
      useLayoutEffect: (create: EffectFn, deps: Deps) => this.effect(true, create, deps),
      useInsertionEffect: (create: EffectFn, deps: Deps) => this.effect(true, create, deps),
      useContext: (context: { _currentValue?: unknown }) =>
        this.contexts.has(context) ? this.contexts.get(context) : context._currentValue,
      useDebugValue: () => undefined,
    },
    {
      get(target, name) {
        if (name in target) return target[name as keyof typeof target];
        throw new Error(`nav-stack-harness: hook ${String(name)} is not supported`);
      },
    },
  );
}

// ── The element tree a screen returned ───────────────────────────────────

export interface Element { type: unknown; props: Record<string, unknown> }

export function findElement(node: unknown, match: (el: Element) => boolean): Element | undefined {
  if (Array.isArray(node)) {
    for (const child of node) {
      const hit = findElement(child, match);
      if (hit) return hit;
    }
    return undefined;
  }
  if (!React.isValidElement(node)) return undefined;
  const el = node as unknown as Element;
  if (match(el)) return el;
  return findElement(el.props.children, match);
}

// ── A stack navigator with the native layer modelled ─────────────────────

type Action = { type: string; payload?: object; source?: string; target?: string };
interface Route { key: string; name: string; params?: object }
interface StackState { key: string; index: number; routes: Route[]; routeNames: string[] }
interface NavEvent { type: string; target?: string; data?: unknown; defaultPrevented: boolean; preventDefault(): void }
type ShouldPreventRemove = (
  emitter: { emit(e: { type: string; target?: string; data?: unknown; canPreventDefault?: boolean }): NavEvent },
  beforeRemoveListeners: Record<string, unknown>,
  currentRoutes: Route[],
  nextRoutes: Route[],
  action: Action,
) => boolean;

export interface ScreenSpec { name: string; params?: object; component?: () => unknown }

export interface StackHarness {
  /** Route names in navigation state, bottom to top. */
  jsRoutes(): string[];
  /** Screens the native stack is showing, bottom to top. */
  nativeRoutes(): string[];
  /** The mounted component host for a route, if its route is still in state. */
  host(name: string): HookHost | undefined;
  /** An iOS edge swipe on the top native screen. */
  swipeBack(): void;
  /** expo-router's router.back(): GO_BACK through the container. */
  containerGoBack(): void;
  /** Screens native removed while navigation state kept them (native-stack logs these). */
  removedNativelyButKept: string[];
}

export async function createStack(screens: ScreenSpec[]): Promise<StackHarness> {
  const coreDir = realpathSync(resolve(REPO_ROOT, 'node_modules', '@react-navigation', 'core', 'lib', 'module'));
  const { shouldPreventRemove } = (await import(/* @vite-ignore */ resolve(coreDir, 'useOnPreventRemove.js'))) as {
    shouldPreventRemove: ShouldPreventRemove;
  };

  const routeNames = screens.map((s) => s.name);
  const options = {
    routeNames,
    routeParamList: Object.fromEntries(routeNames.map((n) => [n, undefined])),
    routeGetIdList: {},
  };
  const router = StackRouter({});
  let state = router.getRehydratedState(
    { stale: true, index: screens.length - 1, routes: screens.map((s) => ({ name: s.name, params: s.params })) } as never,
    options as never,
  ) as unknown as StackState;

  const listeners = new Map<string, Set<(e: NavEvent) => void>>();
  const emitter = {
    emit({ type, target, data }: { type: string; target?: string; data?: unknown }): NavEvent {
      const event: NavEvent = { type, target, data, defaultPrevented: false, preventDefault() { event.defaultPrevented = true; } };
      for (const cb of [...(listeners.get(`${target}:${type}`) ?? [])]) cb(event);
      return event;
    },
  };

  // PreventRemoveProvider: one registration per hook id.
  const registrations = new Map<string, { routeKey: string; preventRemove: boolean }>();
  const preventRemoveContext = {
    setPreventRemove(id: string, routeKey: string, preventRemove: boolean) {
      if (preventRemove && state.routes.every((r) => r.key !== routeKey)) {
        throw new Error(`Couldn't find a route with the key ${routeKey}.`);
      }
      if (preventRemove) registrations.set(id, { routeKey, preventRemove });
      else registrations.delete(id);
    },
    get preventedRoutes(): Record<string, { preventRemove: boolean }> {
      const out: Record<string, { preventRemove: boolean }> = {};
      for (const { routeKey, preventRemove } of registrations.values()) {
        out[routeKey] = { preventRemove: out[routeKey]?.preventRemove || preventRemove };
      }
      return out;
    },
  };

  let native = state.routes.map((r) => r.key);
  const hosts = new Map<string, HookHost>();
  const navigations = new Map<string, object>();
  const removedNativelyButKept: string[] = [];
  const nameOf = (key: string) => state.routes.find((r) => r.key === key)?.name ?? key;

  function dispatch(action: Action): boolean {
    const next = router.getStateForAction(state as never, action as never, options as never) as unknown as StackState | null;
    if (next === null) return false;
    if (next !== state) {
      if (shouldPreventRemove(emitter, {}, state.routes, next.routes, action)) return true;
      state = next;
      commit();
    }
    return true;
  }

  function navigationFor(route: Route): object {
    let nav = navigations.get(route.key);
    if (!nav) {
      nav = {
        dispatch: (thunk: Action | ((s: StackState) => Action | null)) => {
          const action = typeof thunk === 'function' ? thunk(state) : thunk;
          if (action != null) dispatch({ source: route.key, ...action });
        },
        goBack: () => dispatch({ source: route.key, ...(CommonActions.goBack() as Action) }),
        addListener: (type: string, cb: (e: NavEvent) => void) => {
          const k = `${route.key}:${type}`;
          if (!listeners.has(k)) listeners.set(k, new Set());
          listeners.get(k)!.add(cb);
          return () => listeners.get(k)?.delete(cb);
        },
        getState: () => state,
        isFocused: () => state.routes[state.index]?.key === route.key,
        canGoBack: () => state.index > 0,
      };
      navigations.set(route.key, nav);
    }
    return nav;
  }

  function commit(): void {
    const keys = new Set(state.routes.map((r) => r.key));
    for (const [key, host] of hosts) {
      if (!keys.has(key)) { host.unmount(); hosts.delete(key); }
    }
    // The native stack follows the JS routes whenever they change.
    native = state.routes.map((r) => r.key);
  }

  for (const route of state.routes) {
    const spec = screens.find((s) => s.name === route.name)!;
    if (!spec.component) continue;
    const contexts = new Map<unknown, unknown>([
      [NavigationContext, navigationFor(route)],
      [NavigationRouteContext, route],
      [PreventRemoveContext, preventRemoveContext],
    ]);
    const host = new HookHost(spec.component, contexts);
    hosts.set(route.key, host);
    host.mount();
  }

  return {
    jsRoutes: () => state.routes.map((r) => r.name),
    nativeRoutes: () => native.map(nameOf),
    host: (name) => {
      const route = [...state.routes].reverse().find((r) => r.name === name);
      return route ? hosts.get(route.key) : undefined;
    },
    swipeBack() {
      if (native.length < 2) return;   // nothing underneath: UIKit does not begin the gesture
      const topKey = native[native.length - 1]!;
      const topName = nameOf(topKey);
      const pop: Action = { ...(StackActions.pop(1) as Action), source: topKey, target: state.key };
      if (preventRemoveContext.preventedRoutes[topKey]?.preventRemove) {
        // RNSScreenStack cancels the interactive pop; the screen never leaves → onNativeDismissCancelled
        dispatch(pop);
      } else {
        // UIKit completes the pop first; the view is gone → onDismissed
        native = native.slice(0, -1);
        dispatch(pop);
        if (state.routes.some((r) => r.key === topKey)) removedNativelyButKept.push(topName);
      }
    },
    containerGoBack() {
      dispatch({ type: 'GO_BACK' });
    },
    removedNativelyButKept,
  };
}
