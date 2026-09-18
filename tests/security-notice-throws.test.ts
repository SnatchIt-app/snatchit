/**
 * F-SEC-2 — a thrown action says so, instead of failing silently.
 *
 * Found by D while reviewing F-SEC-1, verified by C in the same tree, and PRE-EXISTING: neither the old code
 * nor `runExclusive` caught a **thrown** error — only the `error` field a call returns. And
 * `src/components/SecurityNoticeBanner.tsx:43,45` passes the async handlers straight to `onPress`, so a
 * rejection had nowhere to go: an unhandled rejection, and nothing on screen. The lock still released and
 * `busy` still cleared, so the control never jammed — the user simply tapped a security action and was told
 * nothing. That is the "silent tap" class `DISMISS_FAILED_COPY` was written to end, on the security surface.
 *
 * What can throw: `signOutAllDevices` catches inside `revokeAllBindings`, but the session and SecureStore work
 * underneath `performSignOut` can reject. The common failure returns `{ signedOut: false }` and already had a
 * message; this is the uncommon path that had none.
 *
 * These tests assert the handler RESOLVES — that is the same property as "no unhandled rejection", stated in a
 * way the suite can check — and that the existing copy is on screen. Nothing here changes sign-out policy,
 * session semantics or `signOut.ts`.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { HookHost } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => {
  const deferred = <T,>() => {
    let resolve!: (v: T) => void;
    let reject!: (e: unknown) => void;
    const promise = new Promise<T>((ok, bad) => { resolve = ok; reject = bad; });
    return { promise, resolve, reject };
  };
  return {
    deferred,
    signOuts: [] as ReturnType<typeof deferred<{ signedOut: boolean }>>[],
    marks: [] as ReturnType<typeof deferred<{ error: unknown }>>[],
    replaces: [] as string[],
    notices: [] as unknown[],
    navThrows: false,
  };
});

vi.mock('react-native', () => ({
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
}));
vi.mock('expo-router', () => ({
  router: {
    replace: (p: string) => {
      h.replaces.push(p);
      if (h.navThrows) throw new Error('navigation failed');
    },
  },
}));
vi.mock('@/src/lib/auth/signOut', () => ({
  SIGN_OUT_FAILED_COPY: "Couldn't sign out — check your connection and try again.",
  signOutAllDevices: () => {
    const d = h.deferred<{ signedOut: boolean }>();
    h.signOuts.push(d);
    return d.promise;
  },
}));
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    rpc: (name: string) => {
      if (name === 'mark_security_notices_read') {
        const d = h.deferred<{ error: unknown }>();
        h.marks.push(d);
        return d.promise;
      }
      return Promise.resolve({ data: h.notices, error: null });
    },
  },
}));

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const NOTICE = {
  id: 'n-1',
  type_key: 'security_device_rebound',
  title: 'A device was moved to another account',
  body: 'A device that was receiving your notifications is now registered to another account.',
  created_at: '2026-09-17T20:00:00Z',
  read_at: null,
};

const SIGN_OUT_COPY = "Couldn't sign out — check your connection and try again.";
const DISMISS_COPY = "Couldn't dismiss this notice — check your connection and try again.";

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
  h.navThrows = false;
  vi.resetModules();
});

describe('F-SEC-2 — a thrown action is not a silent one', () => {
  it('T1: a thrown sign-out shows the existing failure copy and does not reject', async () => {
    const { host, latest } = await mountHook();

    // The handler's own promise is what the banner leaves unhandled; it must settle, not reject.
    const pending = latest().signOutAll();
    await flush();
    h.signOuts[0].reject(new Error('network request failed'));

    await expect(pending).resolves.toBeUndefined();
    host.flush();

    expect(latest().error).toBe(SIGN_OUT_COPY);
    expect(h.replaces).toEqual([]);          // a throw is not a sign-out: nothing navigates
  });

  it('T2: a thrown dismiss shows the existing failure copy, keeps the notice, and does not reject', async () => {
    const { host, latest } = await mountHook();

    const pending = latest().dismiss();
    await flush();
    h.marks[0].reject(new Error('network request failed'));

    await expect(pending).resolves.toBeUndefined();
    host.flush();

    expect(latest().error).toBe(DISMISS_COPY);
    expect(latest().notice).not.toBeNull();  // the notice stays up, as on a returned error
  });

  it('T3: the lock releases after a thrown sign-out and after a thrown dismiss', async () => {
    const { host, latest } = await mountHook();

    await (async () => {
      const p = latest().signOutAll();
      await flush();
      h.signOuts[0].reject(new Error('boom'));
      await p;
    })();
    host.flush();
    expect(latest().busy).toBe(false);

    await (async () => {
      const p = latest().dismiss();
      await flush();
      h.marks[0].reject(new Error('boom'));
      await p;
    })();
    host.flush();
    expect(latest().busy).toBe(false);
  });

  it('T4: a retry after a thrown failure works', async () => {
    const { host, latest } = await mountHook();

    const first = latest().signOutAll();
    await flush();
    h.signOuts[0].reject(new Error('boom'));
    await first;
    host.flush();

    const second = latest().signOutAll();
    await flush();
    host.flush();
    expect(h.signOuts.length).toBe(2);       // the guard released, so the retry ran

    h.signOuts[1].resolve({ signedOut: true });
    await second;
    host.flush();
    expect(h.replaces).toEqual(['/(auth)/login']);
    expect(latest().error).toBeNull();       // the new attempt cleared the old message
  });

  it('T5: same-tick double invocation still produces ONE underlying action (F-SEC-1 preserved)', async () => {
    const { host, latest } = await mountHook();
    const signOutAll = latest().signOutAll;  // captured once — the closure a real double tap holds

    void signOutAll();
    void signOutAll();
    await flush();
    host.flush();

    expect(h.signOuts.length).toBe(1);
  });

  it('T7: a sign-out that SUCCEEDED is never reported as failed, even if the navigation throws', async () => {
    // F-SEC-2-A (A's review): the catch C added spans the whole action, including the router.replace that runs
    // AFTER a successful sign-out. A throw there would show "Couldn't sign out" for an action that completed —
    // every session and push binding really ended, and the screen would say otherwise. A throw is an unknown
    // outcome only while the outcome is unknown; past the success line it is known.
    // The navigation is belt-and-braces anyway: the global auth listener routes on sign-out.
    h.navThrows = true;
    const { host, latest } = await mountHook();

    const pending = latest().signOutAll();
    await flush();
    h.signOuts[0].resolve({ signedOut: true });

    await expect(pending).resolves.toBeUndefined();
    host.flush();

    expect(h.replaces).toEqual(['/(auth)/login']);   // it was attempted
    expect(latest().error).toBeNull();               // and nothing claims the sign-out failed
    expect(latest().busy).toBe(false);               // the lock still released
  });

  it('T6: a thrown action still leaves the control usable for the other action too', async () => {
    // One lock covers both; a throw in either must not strand the pair.
    const { host, latest } = await mountHook();

    const p = latest().signOutAll();
    await flush();
    h.signOuts[0].reject(new Error('boom'));
    await p;
    host.flush();

    void latest().dismiss();
    await flush();
    host.flush();
    expect(h.marks.length).toBe(1);
  });
});
