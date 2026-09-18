/**
 * F-AVATAR-2 — Settings › Edit Profile: every avatar control stays busy until the save resolves.
 *
 * The same defect C fixed on the profile tab (F-AVATAR-1), left standing in its twin. D found it while
 * re-running C's controls; C verified at the batch head and found one thing D's report did not have:
 * **this screen has TWO controls**, `edit-profile.tsx:141` (the ring) and `:149` ("Change photo"), both
 * calling `handleAvatarPress`, both gated on the same `disabled={avatarUploading}`. So when the flag cleared
 * early — at `:69`, before the `profiles.update({ avatar_path })` at `:76` — BOTH came back alive while the
 * write was still in flight, and either could start a second pick.
 *
 * Consequence, worse than on the profile tab: two overlapping presses each write `avatar_path`. If the
 * second upload's update lands first, the stored path points at the earlier object and the avatar silently
 * reverts on the next load.
 *
 * Client-only. No auth, payment, database or server change.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { HookHost } from './helpers/nav-stack-harness';
import { busyState, byLabel, screenText } from './helpers/screen-view';
import { findElement, type Element } from './helpers/nav-stack-harness';

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
  };
});

vi.mock('react-native', () => ({
  Alert: { alert: (t: string) => { h.alerts.push(t); } },
  Keyboard: { dismiss: () => {} },
  KeyboardAvoidingView: 'KeyboardAvoidingView',
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Pressable: 'Pressable', ScrollView: 'ScrollView', Text: 'Text', TextInput: 'TextInput', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-image', () => ({ Image: 'Image' }));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {}, replace: () => {} } }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u-1', email: 'seller@example.test' } }) }));
vi.mock('@/src/components/ui', () => ({ Button: 'Button', Input: 'Input', Spinner: 'Spinner', StickyBar: 'StickyBar' }));
vi.mock('@/src/components/account/SettingsHeader', () => ({ SettingsHeader: 'SettingsHeader' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
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
    let isWrite = false;
    q.update = () => { isWrite = true; return q; };
    for (const m of ['select', 'order', 'limit', 'in', 'neq', 'or', 'maybeSingle', 'single']) q[m] = () => q;
    q.eq = () => {
      if (!isWrite) return q;
      const d = h.deferred<{ error: unknown }>();
      h.writes.push(d);
      return d.promise;
    };
    q.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: null, error: null }).then(ok);
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

const UPLOAD_OK = { ok: true, storagePath: 'u-1/new.png', publicUrl: 'https://example.test/new.png' };

/** The photo ring. */
function ring(host: HookHost): Element | undefined {
  return byLabel(host.output, 'Change profile photo');
}

/** The "Change photo" text control beside it — the second way in, and the one D's report did not have. */
function textControl(host: HookHost): Element | undefined {
  return findElement(
    host.output,
    (el) => el.type === 'Pressable' && el.props.accessibilityLabel !== 'Change profile photo'
      && findElement(el, (c) => c.type === 'Text' && typeof c.props.children === 'string'
        && ['Change photo', 'Uploading'].includes(c.props.children as string)) !== undefined,
  );
}

const ringBusy = (host: HookHost) => busyState(ring(host));
const textBusy = (host: HookHost): 'absent' | boolean => {
  const el = textControl(host);
  if (!el) return 'absent';
  return el.props.disabled === true;
};

function pressRing(host: HookHost): void {
  const el = ring(host);
  if (!el) throw new Error('avatar ring is not on screen');
  if (el.props.disabled === true) return;
  (el.props.onPress as () => void)();
  host.flush();
}

function pressTextControl(host: HookHost): void {
  const el = textControl(host);
  if (!el) throw new Error('"Change photo" control is not on screen');
  if (el.props.disabled === true) return;
  (el.props.onPress as () => void)();
  host.flush();
}

async function mountEditProfile(): Promise<HookHost> {
  const mod = await import('@/app/settings/edit-profile');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

beforeEach(() => {
  h.uploads.length = 0; h.writes.length = 0; h.alerts.length = 0;
  vi.resetModules();
});

describe('F-AVATAR-2 — Edit Profile keeps every avatar control busy until the save resolves', () => {
  it('E1: the ring stays busy while the database write is still in flight', async () => {
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    host.flush();
    expect(ringBusy(host)).toBe(true);           // uploading

    h.uploads[0].resolve(UPLOAD_OK);
    await flush();
    host.flush();

    expect(h.writes.length).toBe(1);             // the save has started
    expect(ringBusy(host)).toBe(true);           // and the screen still says so
  });

  it('E2: the "Change photo" control is busy for the same window — both ways in, one state', async () => {
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    h.uploads[0].resolve(UPLOAD_OK);
    await flush();
    host.flush();

    expect(textBusy(host)).toBe(true);
    expect(screenText(host.output)).toContain('Uploading');
  });

  it('E3: the second control cannot start a racing upload during the save', async () => {
    // The consequence that makes this worse than the profile tab: two writes of avatar_path, and if the
    // second lands first the stored path points at the earlier object.
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    h.uploads[0].resolve(UPLOAD_OK);
    await flush();
    host.flush();

    pressTextControl(host);
    await flush();
    host.flush();

    expect(h.uploads.length).toBe(1);
    expect(h.writes.length).toBe(1);
  });

  it('E4: the ring cannot start one either', async () => {
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    h.uploads[0].resolve(UPLOAD_OK);
    await flush();
    host.flush();

    pressRing(host);
    await flush();
    host.flush();

    expect(h.uploads.length).toBe(1);
  });

  it('E9: two presses in the SAME tick start one upload — the press `disabled` cannot stop', async () => {
    // D's review: E3 and E4 prove the controls are disabled, not that the guard works, because the helpers
    // model a disabled control and return before calling onPress. The guard exists for the press the prop
    // cannot stop — a second tap landing before React re-renders with disabled=true. This delivers exactly
    // that press: the handler, twice, in one tick.
    const host = await mountEditProfile();
    const press = ring(host)?.props.onPress as () => void;
    expect(press).toBeTypeOf('function');

    press();
    press();          // same tick: the first has not re-rendered yet, so `disabled` is still false
    await flush();
    host.flush();

    expect(h.uploads.length).toBe(1);
  });

  it('E10: the lock is released, so a later press works — a lock that never opens is its own defect', async () => {
    // Nothing pinned the release: a mutant that never cleared the ref passed every other test, because they
    // each press once. This presses again after a completed cycle.
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    h.uploads[0].resolve(UPLOAD_OK);
    await flush();
    h.writes[0].resolve({ error: null });
    await flush();
    host.flush();
    expect(ringBusy(host)).toBe(false);

    pressRing(host);
    await flush();
    host.flush();

    expect(h.uploads.length).toBe(2);
  });

  it('E5: both controls go idle once the save resolves', async () => {
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    h.uploads[0].resolve(UPLOAD_OK);
    await flush();
    host.flush();

    h.writes[0].resolve({ error: null });
    await flush();
    host.flush();

    expect(ringBusy(host)).toBe(false);
    expect(textBusy(host)).toBe(false);
    expect(screenText(host.output)).toContain('Change photo');
  });

  it('E6: a failed save releases both controls and reports it', async () => {
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    h.uploads[0].resolve(UPLOAD_OK);
    await flush();
    host.flush();

    h.writes[0].resolve({ error: { message: 'write rejected' } });
    await flush();
    host.flush();

    expect(ringBusy(host)).toBe(false);
    expect(textBusy(host)).toBe(false);
    expect(h.alerts).toContain('Save failed');
  });

  it('E7: a cancelled pick releases the controls and says nothing (regression guard)', async () => {
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    h.uploads[0].resolve({ ok: false, error: 'Cancelled.' });
    await flush();
    host.flush();

    expect(ringBusy(host)).toBe(false);
    expect(h.writes.length).toBe(0);
    expect(h.alerts).toEqual([]);
  });

  it('E8: a failed upload releases the controls and reports it (regression guard)', async () => {
    const host = await mountEditProfile();
    pressRing(host);
    await flush();
    h.uploads[0].resolve({ ok: false, error: 'Upload rejected' });
    await flush();
    host.flush();

    expect(ringBusy(host)).toBe(false);
    expect(h.writes.length).toBe(0);
    expect(h.alerts).toContain('Upload failed');
  });
});
