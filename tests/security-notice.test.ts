/**
 * tests/security-notice.test.ts — notification batch 1, item 2 (owner ruling
 * 2026-09-17; A's 136 contract; D-verified copy lives on the SERVER):
 * an unread `security_device_rebound` notice — "a device that was receiving
 * THIS account's notifications is now registered to ANOTHER account" — is
 * shown full-width on the first signed-in screen, never on the login screen,
 * with two actions: "Sign out of all devices" (K-2) and "Dismiss" (marks it
 * read). The client carries NO title/body strings: it renders {title, body}
 * exactly as `public.get_my_security_notices()` returns them.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  actionsFor, NOTICE_ACTION_LABEL, parseSecurityNotices, REBOUND_TYPE_KEY, selectActionableNotice, SECURITY_NOTICES_RPC,
  MARK_NOTICES_READ_RPC, type SecurityNotice,
} from '@/src/lib/security/notices';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

const row = (over: Partial<SecurityNotice> = {}): SecurityNotice => ({
  id: 'n1', type_key: 'security_device_rebound', title: 'T', body: 'B', created_at: '2026-09-17T03:00:00Z', read_at: null, ...over,
});

describe('which notice is shown', () => {
  it('the newest unread notice of ANY type the server returns; read ones are not actionable', () => {
    expect(REBOUND_TYPE_KEY).toBe('security_device_rebound');
    const rows = [
      row({ id: 'old', created_at: '2026-09-16T00:00:00Z' }),
      row({ id: 'read', read_at: '2026-09-17T01:00:00Z' }),
      row({ id: 'other', type_key: 'security_password_changed' }),          // 03:00 — newest unread, not a rebound
      row({ id: 'new', created_at: '2026-09-17T02:00:00Z' }),
    ];
    // 136 rev2 derives the mandatory account-security set from the registry; the client
    // never narrows it (A, 2026-09-18) — an unknown type renders, with Dismiss only.
    expect(selectActionableNotice(rows)?.id).toBe('other');
    expect(selectActionableNotice([row({ id: 'future', type_key: 'security_some_future_type' })])?.id).toBe('future');
    expect(actionsFor('security_some_future_type')).toEqual(['dismiss']);
    expect(selectActionableNotice([row({ read_at: '2026-09-17T01:00:00Z' })])).toBeNull();
    expect(selectActionableNotice([])).toBeNull();
  });

  it('parses the RPC reply defensively: non-arrays and malformed rows yield nothing', () => {
    expect(parseSecurityNotices(null)).toEqual([]);
    expect(parseSecurityNotices({ rows: [] })).toEqual([]);
    expect(parseSecurityNotices([{ id: 1 }])).toEqual([]);
    expect(parseSecurityNotices([row()])).toEqual([row()]);
  });

  it('actions are keyed on the type; the only client copy is the two labels', () => {
    expect(actionsFor('security_device_rebound')).toEqual(['sign_out_all', 'dismiss']);
    expect(actionsFor('security_password_changed')).toEqual(['dismiss']);
    expect(NOTICE_ACTION_LABEL.sign_out_all).toBe('Sign out of all devices');
    expect(NOTICE_ACTION_LABEL.dismiss).toBe('Dismiss');
    expect(SECURITY_NOTICES_RPC).toBe('get_my_security_notices');
    expect(MARK_NOTICES_READ_RPC).toBe('mark_security_notices_read');
  });
});

describe('the surface (source contract)', () => {
  const comp = stripComments(read('src/components/SecurityNoticeBanner.tsx'));
  const hook = stripComments(read('src/hooks/useSecurityNotices.ts'));
  it('renders the server title and body verbatim and carries no notice sentence of its own', () => {
    expect(comp).toContain('{notice.title}');
    expect(comp).toContain('{notice.body}');
    expect(comp).not.toMatch(/registered to|receiving your notifications|another account|sign out of all devices and/i);
    expect(comp).toContain('accessibilityRole="alert"');
    expect(comp).toContain('NOTICE_ACTION_LABEL');
    // Topmost element above <Tabs>: pays the top inset (status bar + SANDBOX badge) itself, like every tab screen.
    expect(comp).toContain('const top = useTopInset();');
    expect(comp).toContain('paddingTop: top + v2.space.md');
  });
  it('the actions are wired: Sign out of all devices → signOutAllDevices (K-2, failure copy on the screen); Dismiss → mark read', () => {
    expect(hook).toContain("supabase.rpc(SECURITY_NOTICES_RPC)");
    expect(hook).toContain("supabase.rpc(MARK_NOTICES_READ_RPC, { p_ids: ids })");
    // A failed Dismiss is not a dead button: the notice stays and the failure is on the screen; each action
    // clears the last error first. F-SEC-1 moved that clear into `runExclusive`, the single acquire/release both
    // actions run through, so the ordering is now pinned there — same rule, one site instead of two.
    const r = hook.indexOf('const runExclusive = useCallback(');
    expect(r).toBeGreaterThan(-1);
    const rEnd = hook.indexOf('const dismiss = useCallback(', r);
    const exclusiveBody = hook.slice(r, rEnd);
    expect(exclusiveBody).toContain('setError(null);');
    expect(exclusiveBody.indexOf('setError(null);')).toBeLessThan(exclusiveBody.indexOf('await action();'));

    const d = hook.indexOf('const dismiss = useCallback(');
    expect(d).toBeGreaterThan(-1);
    const dEnd = hook.indexOf('const signOutAll = useCallback(', d);
    const dismissBody = hook.slice(d, dEnd);
    expect(dismissBody).toContain('setError(DISMISS_FAILED_COPY);');
    expect(dismissBody.indexOf('setError(DISMISS_FAILED_COPY);')).toBeLessThan(dismissBody.indexOf('setNotice(null);'));
    // F-SEC-1: both actions run through the one lock, and it is NOT the read lock.
    expect(hook).toContain('const actionInFlight = useRef(false);');
    expect(dismissBody).toContain('await runExclusive(');
    const soBody = hook.slice(hook.indexOf('const signOutAll = useCallback('));
    expect(soBody).toContain('await runExclusive(');
    expect(exclusiveBody).toContain('actionInFlight.current = true;');
    expect(exclusiveBody).toContain('actionInFlight.current = false;');
    // F-SEC-1-A (A's review): "released exactly once" is the property the evidence asks for, and existence
    // assertions cannot express it — a later edit adding a second release on a success path would pass them all.
    // Counted here, so the structural argument has a test: one acquire, one release, one busy-clear in the file.
    const occurrences = (hay: string, needle: string) => hay.split(needle).length - 1;
    expect(occurrences(hook, 'actionInFlight.current = true;')).toBe(1);
    expect(occurrences(hook, 'actionInFlight.current = false;')).toBe(1);
    expect(occurrences(hook, 'setBusy(false);')).toBe(1);
    expect(occurrences(hook, 'setBusy(true);')).toBe(1);
    expect(hook).toContain('signOutAllDevices()');
    expect(hook).toContain('SIGN_OUT_FAILED_COPY');
    expect(hook).not.toContain('supabase.auth.signOut(');
    // fetched on sign-in (userId) and on every foreground; never polled
    expect(hook).toContain("AppState.addEventListener('change'");
    expect(hook).not.toContain('setInterval');
  });
  it('lives on the first signed-in screen only: mounted by the tabs layout, absent from the auth group', () => {
    const tabs = stripComments(read('app/(tabs)/_layout.tsx'));
    expect(tabs).toContain('<SecurityNoticeBanner />');
    for (const p of ['app/(auth)/_layout.tsx', 'app/(auth)/login.tsx', 'app/(auth)/signup.tsx', 'app/(auth)/reset-password.tsx']) {
      expect(stripComments(read(p)), p).not.toContain('SecurityNoticeBanner');
    }
  });
});
