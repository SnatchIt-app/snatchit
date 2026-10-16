/**
 * N7c — the root that is ALREADY mounted when the hold is raised is told, and re-reads it.
 *
 * Production T1 (2026-10-16): the replacement root (instance B) mounted while the hold was still down;
 * the first instance's in-flight dispatch raised it afterwards. B is the instance that must move to
 * "New password". recovery-hold-remount renders fresh roots with react-dom/server, which reads the
 * server snapshot and never subscribes, so it cannot show B being told (review wf_a11c3a9a: a hook with
 * per-instance state seeded from the store, or a no-op subscribe, passed it). No live renderer is
 * installed, so this file stands in for React's own contract: useSyncExternalStore subscribes each
 * committed instance with an onStoreChange callback and re-reads getSnapshot when it fires.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { setRecoveryHold, useRecoveryHold } from '../src/lib/auth/recoveryHold';

type Subscription = { subscribe: (onStoreChange: () => void) => () => void; getSnapshot: () => boolean; getServerSnapshot?: () => boolean };
const renders = vi.hoisted(() => [] as Subscription[]);

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    useSyncExternalStore: (subscribe: Subscription['subscribe'], getSnapshot: () => boolean, getServerSnapshot?: () => boolean) => {
      renders.push({ subscribe, getSnapshot, getServerSnapshot });
      return getSnapshot();
    },
    // A per-instance copy (the pre-fix design, or state seeded from the store) gets plain local state
    // here, so it fails RH6 on what B sees rather than on a hook being called outside a render.
    useState: <T,>(init: T | (() => T)) => [typeof init === 'function' ? (init as () => T)() : init, () => {}],
  };
});

beforeEach(() => { setRecoveryHold(false); renders.length = 0; });

describe('N7c — the live replacement root', () => {
  it('RH6: instance B, mounted before the claim resolved, is notified when the replaced instance A raises the hold, and re-reads it as held', () => {
    const [, setFromInstanceA] = useRecoveryHold();      // instance A renders; its dispatch is in flight
    const [bAtMount] = useRecoveryHold();                // instance B (the remount) renders while the hold is down
    expect(bAtMount).toBe(false);
    expect(renders).toHaveLength(2);
    const b = renders[1];
    let bNotified = 0;
    const unmountB = b.subscribe(() => { bNotified += 1; });   // B commits: React subscribes it

    setFromInstanceA(true);                              // A's dispatch raises the hold into the store

    expect(bNotified).toBe(1);                           // React schedules B's re-render…
    expect(b.getSnapshot()).toBe(true);                  // …which reads the hold → the guard moves B to "New password"
    unmountB();
  });

  it('RH7: an unmounted root stops hearing changes, and the server snapshot reads the same hold', () => {
    useRecoveryHold();
    const root = renders[0];
    let heard = 0;
    const unmount = root.subscribe(() => { heard += 1; });
    unmount();
    setRecoveryHold(true);
    expect(heard).toBe(0);
    expect(root.getServerSnapshot?.()).toBe(true);
  });
});
