/**
 * F-AVATAR-1 — the avatar's busy state must last until the save actually resolves.
 *
 * B's audit (§P6), verified by C at Build 19's commit f412d10: `handleAvatarPress` cleared
 * `avatarUploading` as soon as the upload returned, and only then wrote `profiles.avatar_path` and set the
 * new image. Between those two points the ring showed no spinner and still showed the OLD photo, so the
 * screen looked idle and unchanged while a write was in flight — and because the guard
 * (`if (!user || avatarUploading) return;`) was already false, a second tap could start another pick and
 * race the first write.
 *
 * C's correction to B's framing, recorded: the user does not see a false "done". They see a no-op. The
 * defect is the same shape either way — the screen stops saying it is working before it has finished.
 *
 * These tests run the REAL app/(tabs)/profile.tsx through the hook dispatcher with the upload and the write
 * under test control. Not a device result.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';
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
    writes: [] as ReturnType<typeof deferred<{ error: unknown }>>[],
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
  // Chainable: only an `update(...)` chain is the avatar write under test. Every other read settles empty,
  // so the rest of the screen mounts without interfering with what these tests observe.
  const table = () => {
    const q: Record<string, unknown> = {};
    let isWrite = false;
    q.update = () => { isWrite = true; return q; };
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'gte', 'lte', 'maybeSingle', 'single']) q[m] = () => q;
    q.eq = () => {
      if (!isWrite) return q;
      const d = h.deferred<{ error: unknown }>();
      h.writes.push(d);
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

function avatarButton(host: HookHost): Element {
  const el = byLabel(host.output, 'Change profile photo');
  if (!el) throw new Error('avatar control is not on screen');
  return el;
}

/**
 * The ring shows the spinner overlay exactly while the screen considers itself busy — tri-state, because
 * `findElement` returns undefined rather than throwing. The old boolean returned `false` both for "idle" and
 * for "the control is not on screen", so four assertions expecting `false` would have passed a mutant that
 * unmounted the avatar entirely (D's review).
 */
function busy(host: HookHost): 'absent' | boolean {
  return busyState(byLabel(host.output, 'Change profile photo'));
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

describe('F-AVATAR-1 — busy until the save resolves', () => {
  it('A1: the ring is busy while the save is still in flight', async () => {
    const host = await mountProfile();
    (avatarButton(host).props.onPress as () => void)();
    await flush();
    host.flush();
    expect(busy(host)).toBe(true);           // uploading

    h.uploads[0].resolve({ ok: true, storagePath: 'u-1/new.png', publicUrl: 'https://example.test/new.png' });
    await flush();
    host.flush();

    // The upload is done but the database write is not. The old code went idle here.
    expect(h.writes.length).toBe(1);
    expect(busy(host)).toBe(true);
  });

  it('A2: the ring goes idle once the save resolves', async () => {
    const host = await mountProfile();
    (avatarButton(host).props.onPress as () => void)();
    await flush();
    h.uploads[0].resolve({ ok: true, storagePath: 'u-1/new.png', publicUrl: 'https://example.test/new.png' });
    await flush();
    host.flush();
    expect(busy(host)).toBe(true);

    h.writes[0].resolve({ error: null });
    await flush();
    host.flush();

    expect(busy(host)).toBe(false);
  });

  it('A3: a second tap during the save cannot start a second upload', async () => {
    const host = await mountProfile();
    (avatarButton(host).props.onPress as () => void)();
    await flush();
    h.uploads[0].resolve({ ok: true, storagePath: 'u-1/new.png', publicUrl: 'https://example.test/new.png' });
    await flush();
    host.flush();

    // The old code left the guard open here, so this tap raced the first write.
    (avatarButton(host).props.onPress as () => void)();
    await flush();
    host.flush();

    expect(h.uploads.length).toBe(1);
  });

  it('A4: a failed save ends the busy state and reports it', async () => {
    const host = await mountProfile();
    (avatarButton(host).props.onPress as () => void)();
    await flush();
    h.uploads[0].resolve({ ok: true, storagePath: 'u-1/new.png', publicUrl: 'https://example.test/new.png' });
    await flush();
    host.flush();

    h.writes[0].resolve({ error: { message: 'write rejected' } });
    await flush();
    host.flush();

    expect(busy(host)).toBe(false);
    expect(h.alerts).toContain('Save failed');
  });

  it('A5: a cancelled pick ends the busy state and says nothing (regression guard)', async () => {
    const host = await mountProfile();
    (avatarButton(host).props.onPress as () => void)();
    await flush();
    h.uploads[0].resolve({ ok: false, error: 'Cancelled.' });
    await flush();
    host.flush();

    expect(busy(host)).toBe(false);
    expect(h.writes.length).toBe(0);
    expect(h.alerts).toEqual([]);
  });

  it('A6: a failed upload ends the busy state and reports it (regression guard)', async () => {
    const host = await mountProfile();
    (avatarButton(host).props.onPress as () => void)();
    await flush();
    h.uploads[0].resolve({ ok: false, error: 'Upload rejected' });
    await flush();
    host.flush();

    expect(busy(host)).toBe(false);
    expect(h.writes.length).toBe(0);
    expect(h.alerts).toContain('Upload failed');
  });
});
