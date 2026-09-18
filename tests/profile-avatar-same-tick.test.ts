/**
 * F-AVATAR-3 — the profile tab's avatar flow is same-tick safe.
 *
 * Batch 1 fixed WHEN the busy flag clears (F-AVATAR-1) and left WHAT guards re-entry alone:
 * `app/(tabs)/profile.tsx` still held `if (!user || avatarUploading) return;` — a STATE guard. A second press
 * landing in the same event loop reads the same stale closure, so it walks straight past, and `disabled` cannot
 * stop it either because React has not re-rendered yet. That is the press a real double-tap delivers.
 *
 * Confirmed live by two independent runs before this fix: D probed the Batch 1 suite and got two uploads from
 * one same-tick double press; C ran the same probe separately and got the same. The race is in Build 19's code
 * too — Batch 1 changed the clearing, not the guard.
 *
 * Consequence: two uploads, two `profiles.update({ avatar_path })`. If the second update lands first, the
 * stored path points at the earlier object and the avatar silently reverts on the next load.
 *
 * The fix is the one already reviewed for Settings › Edit Profile (F-AVATAR-2) and for destructive listing
 * actions before it (F-DESTRUCT-1): the lock is a ref, and the state stays as what the control SHOWS.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { HookHost } from './helpers/nav-stack-harness';
import { busyState, byLabel } from './helpers/screen-view';

const h = vi.hoisted(() => {
  const deferred = <T,>() => {
    let resolve!: (v: T) => void;
    const promise = new Promise<T>((r) => { resolve = r; });
    return { promise, resolve };
  };
  return {
    deferred,
    uploads: [] as ReturnType<typeof deferred<Record<string, unknown>>>[],
    /** Every profiles.update, with the path it wrote — so "one database update" is checked, not assumed. */
    writes: [] as { path: unknown; d: ReturnType<typeof deferred<{ error: unknown }>> }[],
    alerts: [] as string[],
    focus: { current: null as null | (() => void) },
  };
});

vi.mock('react-native', () => ({
  Alert: { alert: (t: string) => { h.alerts.push(t); } },
  Pressable: 'Pressable', RefreshControl: 'RefreshControl', ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-image', () => ({ Image: 'Image' }));
vi.mock('expo-router', () => ({ router: { push: () => {}, replace: () => {} } }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: (cb: () => void) => { h.focus.current = cb; } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u-1', email: 'buyer@example.test' } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }) }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Button: 'Button', Spinner: 'Spinner' }));
vi.mock('@/src/components/account/AccountSection', () => ({ AccountSection: 'AccountSection' }));
vi.mock('@/src/components/account/SettingsRow', () => ({ SettingsRow: 'SettingsRow' }));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => ({ onScroll: () => {}, expand: () => {} }) }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/lib/auth/signOut', () => ({ SIGN_OUT_FAILED_COPY: 'x', signOutThisDevice: async () => ({ ok: true }) }));
vi.mock('@/src/lib/avatarImage', () => ({
  getAvatarUrl: () => 'https://example.test/old.png',
  pickAndUploadAvatar: () => {
    const d = h.deferred<Record<string, unknown>>();
    h.uploads.push(d);
    return d.promise;
  },
}));
vi.mock('@/src/lib/supabase', () => {
  const table = () => {
    const q: Record<string, unknown> = {};
    let payload: unknown;
    q.update = (p: unknown) => { payload = p; return q; };
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'gte', 'lte', 'maybeSingle', 'single']) q[m] = () => q;
    q.eq = () => {
      if (payload === undefined) return q;
      const d = h.deferred<{ error: unknown }>();
      h.writes.push({ path: (payload as { avatar_path?: unknown }).avatar_path, d });
      return d.promise;
    };
    q.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok);
    return q;
  };
  return {
    supabase: {
      from: () => table(),
      auth: { getUser: async () => ({ data: { user: { id: 'u-1' } } }) },
      rpc: () => ({ returns: () => ({ maybeSingle: async () => ({ data: null, error: null }) }) }),
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const upload = (n: number) => ({
  ok: true, storagePath: `u-1/photo-${n}.png`, publicUrl: `https://example.test/photo-${n}.png`,
});

function control(host: HookHost) {
  const el = byLabel(host.output, 'Change profile photo');
  if (!el) throw new Error('avatar control is not on screen');
  return el;
}
const busy = (host: HookHost) => busyState(byLabel(host.output, 'Change profile photo'));

/** The raw handler — the press `disabled` cannot intercept, which is the one under test. */
const handler = (host: HookHost) => control(host).props.onPress as () => void;

/** A press as the UI delivers it: refused when the control is disabled. */
function press(host: HookHost): void {
  const el = control(host);
  if (el.props.disabled === true) return;
  (el.props.onPress as () => void)();
  host.flush();
}

async function mountProfile(): Promise<HookHost> {
  const { default: ProfileScreen } = await import('@/app/(tabs)/profile');
  const host = new HookHost(() => (ProfileScreen as () => unknown)(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

beforeEach(() => {
  h.uploads.length = 0; h.writes.length = 0; h.alerts.length = 0;
  h.focus.current = null;
  vi.resetModules();
});

describe('F-AVATAR-3 — one press, one upload, one save', () => {
  it('P1: two presses in the SAME event loop produce one upload and one database update', async () => {
    const host = await mountProfile();
    const press1 = handler(host);

    press1();
    press1();          // same tick: the first has not re-rendered, so `disabled` is still false
    await flush();
    host.flush();

    expect(h.uploads.length).toBe(1);

    h.uploads[0].resolve(upload(1));
    await flush();
    host.flush();

    expect(h.writes.length).toBe(1);
    expect(h.writes[0].path).toBe('u-1/photo-1.png');
  });

  it('P2: a second operation never starts while one is in flight', async () => {
    // The name is the premise, not the conclusion (D's review). Out-of-order completion follows from this
    // deductively: with one operation at a time there is never a second write to land first, so the reversion
    // — second update wins, stored path points at the earlier object — has nothing to arise from. A permanent
    // test that removed the lock to demonstrate that reversion would be pinning the behaviour of code that does
    // not exist; that is what PM1 does, transiently. The live reversion is recorded in the backlog, evidenced
    // twice: C's run and D's independent probe on this file.
    const host = await mountProfile();
    const raw = handler(host);

    raw();
    raw();
    await flush();
    h.uploads[0].resolve(upload(1));
    await flush();
    host.flush();
    expect(h.writes.length).toBe(1);

    // While that save is still in flight, neither the UI press nor the raw handler may start another.
    press(host);
    raw();
    await flush();
    host.flush();

    expect(h.uploads.length).toBe(1);
    expect(h.writes.length).toBe(1);

    // The save settles; the path that was stored is the one from the single upload that ran.
    h.writes[0].d.resolve({ error: null });
    await flush();
    host.flush();

    expect(h.writes.map((w) => w.path)).toEqual(['u-1/photo-1.png']);
  });

  it('P3: a later press succeeds once the prior save has completed', async () => {
    const host = await mountProfile();

    press(host);
    await flush();
    h.uploads[0].resolve(upload(1));
    await flush();
    h.writes[0].d.resolve({ error: null });
    await flush();
    host.flush();

    press(host);
    await flush();
    host.flush();
    expect(h.uploads.length).toBe(2);

    h.uploads[1].resolve(upload(2));
    await flush();
    host.flush();

    expect(h.writes.length).toBe(2);
    expect(h.writes[1].path).toBe('u-1/photo-2.png');
  });

  it('P4: the control comes back after a completed cycle', async () => {
    const host = await mountProfile();

    press(host);
    await flush();
    host.flush();
    expect(busy(host)).toBe(true);

    h.uploads[0].resolve(upload(1));
    await flush();
    host.flush();
    expect(busy(host)).toBe(true);            // still saving

    h.writes[0].d.resolve({ error: null });
    await flush();
    host.flush();

    expect(busy(host)).toBe(false);           // cleared
    expect(byLabel(host.output, 'Change profile photo')).toBeDefined();
    expect(control(host).props.disabled).toBeFalsy();
    // "Cleared exactly once" is guaranteed structurally, not by this assertion (D counted it): the release is a
    // single site inside a `finally` that runs once per invocation, so a double clear is impossible by
    // construction. What this test observes is the consequence — one upload, one save, control re-enabled.
    expect(h.uploads.length).toBe(1);
    expect(h.writes.length).toBe(1);
  });

  it('P5: a failed save releases the lock, so the next press is not blocked forever', async () => {
    const host = await mountProfile();

    press(host);
    await flush();
    h.uploads[0].resolve(upload(1));
    await flush();
    h.writes[0].d.resolve({ error: { message: 'write rejected' } });
    await flush();
    host.flush();

    expect(busy(host)).toBe(false);
    expect(h.alerts).toContain('Save failed');

    press(host);
    await flush();
    host.flush();
    expect(h.uploads.length).toBe(2);
  });

  it('P6: a cancelled pick releases the lock too (regression guard)', async () => {
    const host = await mountProfile();

    press(host);
    await flush();
    h.uploads[0].resolve({ ok: false, error: 'Cancelled.' });
    await flush();
    host.flush();

    expect(busy(host)).toBe(false);
    expect(h.writes.length).toBe(0);
    expect(h.alerts).toEqual([]);

    press(host);
    await flush();
    host.flush();
    expect(h.uploads.length).toBe(2);
  });
});
