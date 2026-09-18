/**
 * F-SEC-1 — the security notice's actions cannot run twice from one double tap.
 *
 * `useSecurityNotices` guarded both actions with `if (busy) return;` over React **state**. Two presses in the
 * same event loop read the same stale closure and both proceed, and `disabled` cannot stop the second because
 * React has not re-rendered yet. So a double tap on **"Sign out of all devices"** invoked `signOutAllDevices()`
 * twice — a security action, running twice, on the screen whose whole job is telling the user their account
 * security changed. Verified in `f412d10`, the installed build, by A; probed by C; mechanism confirmed by D.
 *
 * The same file already had the right pattern: `load()` guards with a `useRef` (`inFlight`). The two action
 * handlers simply never got it.
 *
 * These tests drive the REAL hook through the dispatcher. **They capture each handler ONCE and call that same
 * reference twice**, because re-reading it between calls hands back a different function — the handler is
 * memoized on the state it guards — whose closure already has `busy === true`. That probe passes and proves
 * nothing; it is the mistake C made first and caught only because the pass felt too easy.
 *
 * Nothing here changes server behaviour, session policy or `signOut.ts`. The hook is the whole surface.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { HookHost } from './helpers/nav-stack-harness';

type SignOutResult = { signedOut: boolean };

const h = vi.hoisted(() => {
  const deferred = <T,>() => {
    let resolve!: (v: T) => void;
    const promise = new Promise<T>((r) => { resolve = r; });
    return { promise, resolve };
  };
  return {
    deferred,
    /** Every call to the real sign-out action, so "runs once" is counted, not assumed. */
    signOuts: [] as ReturnType<typeof deferred<SignOutResult>>[],
    /** Every mark-read RPC, with the ids it was given. */
    marks: [] as { ids: unknown; d: ReturnType<typeof deferred<{ error: unknown }>> }[],
    replaces: [] as string[],
    notices: [] as unknown[],
  };
});

vi.mock('react-native', () => ({
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
}));
vi.mock('expo-router', () => ({ router: { replace: (p: string) => { h.replaces.push(p); } } }));
vi.mock('@/src/lib/auth/signOut', () => ({
  SIGN_OUT_FAILED_COPY: 'We could not sign you out everywhere. Please try again.',
  signOutAllDevices: () => {
    const d = h.deferred<SignOutResult>();
    h.signOuts.push(d);
    return d.promise;
  },
}));
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    rpc: (name: string, args?: Record<string, unknown>) => {
      if (name === 'mark_security_notices_read') {
        const d = h.deferred<{ error: unknown }>();
        h.marks.push({ ids: args?.p_ids, d });
        return d.promise;
      }
      return Promise.resolve({ data: h.notices, error: null });
    },
  },
}));

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

// The server's shape exactly (src/lib/security/notices.ts): id, type_key, title, body, created_at, read_at.
const NOTICE = {
  id: 'n-1',
  type_key: 'security_device_rebound',
  title: 'A device was moved to another account',
  body: 'A device that was receiving your notifications is now registered to another account.',
  created_at: '2026-09-17T20:00:00Z',
  read_at: null,
};

type Api = {
  notice: unknown;
  busy: boolean;
  error: string | null;
  dismiss: () => Promise<void>;
  signOutAll: () => Promise<void>;
};

async function mountHook(): Promise<{ host: HookHost; latest: () => Api }> {
  const { useSecurityNotices } = await import('@/src/hooks/useSecurityNotices');
  let api: Api | undefined;
  const host = new HookHost(() => { api = useSecurityNotices('u-1') as Api; return null; }, new Map());
  host.mount();
  await flush();
  host.flush();
  return { host, latest: () => api as Api };
}

beforeEach(() => {
  h.signOuts.length = 0; h.marks.length = 0; h.replaces.length = 0;
  h.notices = [NOTICE];
  vi.resetModules();
});

describe('F-SEC-1 — one tap and one double tap do the same thing', () => {
  it('S1: signOutAll captured ONCE and called twice invokes the sign-out action once', async () => {
    const { host, latest } = await mountHook();
    // Captured once: this is the closure a real double tap holds. Re-reading here would hand back a different
    // memoized function with busy already true, and the test would pass while proving nothing.
    const signOutAll = latest().signOutAll;

    void signOutAll();
    void signOutAll();
    await flush();
    host.flush();

    expect(h.signOuts.length).toBe(1);
  });

  it('S2: the second press does not navigate twice either', async () => {
    const { host, latest } = await mountHook();
    const signOutAll = latest().signOutAll;

    void signOutAll();
    void signOutAll();
    await flush();
    h.signOuts[0].resolve({ signedOut: true });
    await flush();
    host.flush();

    expect(h.signOuts.length).toBe(1);
    expect(h.replaces).toEqual(['/(auth)/login']);
  });

  it('S3: a failed sign-out releases the guard, reports it, and a later press works', async () => {
    const { host, latest } = await mountHook();
    const first = latest().signOutAll;

    void first();
    await flush();
    h.signOuts[0].resolve({ signedOut: false });
    await flush();
    host.flush();

    expect(latest().busy).toBe(false);
    expect(latest().error).toBe('We could not sign you out everywhere. Please try again.');
    expect(h.replaces).toEqual([]);          // a failed sign-out never navigates

    void latest().signOutAll();
    await flush();
    host.flush();
    expect(h.signOuts.length).toBe(2);       // the guard released
  });

  it('S4: dismiss captured once and called twice marks read once', async () => {
    const { host, latest } = await mountHook();
    const dismiss = latest().dismiss;

    void dismiss();
    void dismiss();
    await flush();
    host.flush();

    expect(h.marks.length).toBe(1);
    expect(h.marks[0].ids).toEqual(['n-1']);
  });

  it('S5: a completed dismiss clears the notice and leaves the hook usable', async () => {
    const { host, latest } = await mountHook();

    void latest().dismiss();
    await flush();
    h.marks[0].d.resolve({ error: null });
    await flush();
    host.flush();

    expect(latest().notice).toBeNull();
    expect(latest().busy).toBe(false);
    expect(latest().error).toBeNull();
  });

  it('S6: a failed dismiss keeps the notice up, says so, and stays usable', async () => {
    const { host, latest } = await mountHook();

    void latest().dismiss();
    await flush();
    h.marks[0].d.resolve({ error: { code: '42501', message: 'denied' } });
    await flush();
    host.flush();

    expect(latest().notice).not.toBeNull();   // the tap is not silent
    expect(latest().busy).toBe(false);
    expect(latest().error).toBeTruthy();

    void latest().dismiss();
    await flush();
    host.flush();
    expect(h.marks.length).toBe(2);           // released, so the user can retry
  });

  it('S7: busy is true while the sign-out is in flight and false after (regression guard)', async () => {
    const { host, latest } = await mountHook();

    void latest().signOutAll();
    await flush();
    host.flush();
    expect(latest().busy).toBe(true);

    h.signOuts[0].resolve({ signedOut: true });
    await flush();
    host.flush();
    expect(latest().busy).toBe(false);
  });

  it('S8: the two actions share one lock — dismiss cannot start while a sign-out is in flight', async () => {
    const { host, latest } = await mountHook();

    void latest().signOutAll();
    await flush();
    host.flush();

    void latest().dismiss();
    await flush();
    host.flush();

    expect(h.marks.length).toBe(0);
  });
});
