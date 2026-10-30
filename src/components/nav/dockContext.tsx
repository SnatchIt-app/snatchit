/**
 * src/components/nav/dockContext.tsx — per-route dock collapse state.
 *
 * Each collapsing tab (Home, Bids, Profile) owns its OWN scroll state, so Home's
 * scrolling never collapses Profile. Screens wire `useDockScroll(route)`; the pure
 * machine (src/lib/nav/dockMachine) decides collapsed/expanded per route; the dock
 * reads the active route's flag. React state changes only on a real transition
 * (accumulators live in refs), so a 60fps scroll does not re-render per event.
 */

import { createContext, useCallback, useContext, useMemo, useRef, useState } from 'react';
import type { NativeScrollEvent, NativeSyntheticEvent } from 'react-native';

import { expandDock, initialDockState, reduceDockScroll, type DockState } from '@/src/lib/nav/dockMachine';

interface NavDockValue {
  collapsedByRoute: Record<string, boolean>;
  onScroll: (route: string, e: NativeSyntheticEvent<NativeScrollEvent>) => void;
  expand: (route: string) => void;
}

const NavDockContext = createContext<NavDockValue | null>(null);

export function NavDockProvider({ children }: { children: React.ReactNode }) {
  const statesRef = useRef<Record<string, DockState>>({});
  const [collapsedByRoute, setCollapsedByRoute] = useState<Record<string, boolean>>({});

  const commit = useCallback((route: string, next: DockState) => {
    statesRef.current[route] = next;
    setCollapsedByRoute((prev) => (prev[route] === next.collapsed ? prev : { ...prev, [route]: next.collapsed }));
  }, []);

  const onScroll = useCallback((route: string, e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const y = e.nativeEvent.contentOffset.y;
    const prev = statesRef.current[route] ?? initialDockState();
    commit(route, reduceDockScroll(prev, y));
  }, [commit]);

  const expand = useCallback((route: string) => {
    const prev = statesRef.current[route] ?? initialDockState();
    commit(route, expandDock(prev));
  }, [commit]);

  const value = useMemo(() => ({ collapsedByRoute, onScroll, expand }), [collapsedByRoute, onScroll, expand]);
  return <NavDockContext.Provider value={value}>{children}</NavDockContext.Provider>;
}

function useNavDockContext(): NavDockValue {
  const ctx = useContext(NavDockContext);
  return ctx ?? { collapsedByRoute: {}, onScroll: () => {}, expand: () => {} };
}

/** The dock reads whether the currently active route is collapsed. */
export function useDockCollapsed(activeRoute: string | undefined): boolean {
  const { collapsedByRoute } = useNavDockContext();
  return activeRoute ? (collapsedByRoute[activeRoute] ?? false) : false;
}

/**
 * A collapsing tab wires this: `onScroll` on its scroll view, and `expand()` on
 * focus / when returning near the top. Handlers are bound to this route only.
 */
export function useDockScroll(route: string): {
  onScroll: (e: NativeSyntheticEvent<NativeScrollEvent>) => void;
  expand: () => void;
} {
  const { onScroll, expand } = useNavDockContext();
  const boundScroll = useCallback((e: NativeSyntheticEvent<NativeScrollEvent>) => onScroll(route, e), [onScroll, route]);
  const boundExpand = useCallback(() => expand(route), [expand, route]);
  return { onScroll: boundScroll, expand: boundExpand };
}

/** The dock uses this to force a route expanded on focus/tab change. */
export function useDockExpander(): (route: string) => void {
  return useNavDockContext().expand;
}
