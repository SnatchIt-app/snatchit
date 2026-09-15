/**
 * tests/candidate-recovery.test.ts — release-sprint recovery/error-state slice
 * (A's C-2) and the contract-independent 128 preparation (C-1 prep).
 *
 * CFT-607: session expiry says so; a cancelled listing is never "Winning".
 * F3: every server blocker kind has a label. CFT-604: loading, failed, empty and
 * filtered states are distinct on every tab and no empty state shows during a
 * load. CFT-605: a listing that is gone offers a way forward that works from a
 * cold start. 128 prep: cold-launch registration and the contract_version pin.
 * Each regression assertion is written so it fails against the previous code.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: vi.fn(), from: vi.fn(), auth: { signOut: vi.fn(), getSession: vi.fn() } } }));

import { bidGroupOf, bidPresentation, bidStatusOf, needsAction, type BidRowInput } from '@/src/lib/bids/bidState';
import { consumeSessionEnd, markSessionEnd, markSessionEndIfUnmarked, sessionEndNotice } from '@/src/lib/auth/sessionEnd';
import { classifyRegistrationError, decideRegistration, EXPECTED_128_CONTRACT_VERSION, type RegistrationFailure, type RegistrationRecord } from '@/src/lib/push/registration';
import { registerWithRpc } from '@/src/lib/push/registerToken';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const ME = 'me';
const now = 1_700_000_000_000;
const row = (listing: Partial<NonNullable<BidRowInput['listing']>>, amount = 50): BidRowInput =>
  ({ amount, listing: { status: 'active', auction_status: 'active', ends_at: new Date(now + 3600_000).toISOString(), current_bid: 50, winner_user_id: null, ...listing } } as BidRowInput);

describe('CFT-607 — a cancelled listing is its own state', () => {
  it('a bid on a cancelled listing reads Cancelled, not Winning (regression: read as winning until the clock ran out)', () => {
    const r = row({ auction_status: 'cancelled' }, 50);
    expect(bidStatusOf(r, ME, now)).toBe('cancelled');
    expect(bidGroupOf('cancelled')).toBe('past');
    expect(needsAction('cancelled')).toBe(false);
    const p = bidPresentation(r, ME, now);
    expect(p.label).toBe('Cancelled');
    expect(p.actionHint).toBe('Listing was cancelled');
    expect(p.endingSoon).toBe(false);
    expect(p.routesToTransfer).toBe(false);
  });
  it('sold and purchase states still take precedence; ended stays ended', () => {
    expect(bidStatusOf(row({ auction_status: 'cancelled', status: 'sold' }), ME, now)).toBe('sold');
    expect(bidStatusOf(row({ auction_status: 'ended', winner_user_id: ME }), ME, now)).toBe('won');
  });
});

describe('CFT-607 — session expiry says so on the login screen', () => {
  it('a user sign-out is marked first and produces no notice; an unmarked SIGNED_OUT is an expiry', () => {
    markSessionEnd('user');
    markSessionEndIfUnmarked('expired');            // the SDK event arriving after the helper
    expect(sessionEndNotice(consumeSessionEnd())).toBeNull();
    markSessionEndIfUnmarked('expired');            // no helper involved
    expect(sessionEndNotice(consumeSessionEnd())).toBe('Your session expired. Sign in to pick up where you left off.');
    expect(consumeSessionEnd()).toBeNull();         // consumed once
  });
  it('the sign-out helper marks before the SDK call, useAuth marks the unmarked case, login reads once', () => {
    const so = stripComments(read('src/lib/auth/signOut.ts'));
    expect(so).toMatch(/markSessionEnd\('user'\);\s*await supabase\.auth\.signOut\(\);/);
    const auth = stripComments(read('src/hooks/useAuth.ts'));
    expect(auth).toContain("if (event === 'SIGNED_OUT' && newSession === null) markSessionEndIfUnmarked('expired');");
    const login = stripComments(read('app/(auth)/login.tsx'));
    expect(login).toContain('useState<string | null>(() => sessionEndNotice(consumeSessionEnd()))');
    expect(login).toContain('{noticeRow}');
  });
  it('the sign-out helper otherwise still revokes by token AND user_id with the single spelling', () => {
    const so = read('src/lib/auth/signOut.ts');
    expect(so).toContain(".eq('token', token)");
    expect(so).toContain(".eq('user_id', userId)");
    expect(so).toContain("revoked_reason: 'signed_out'");
  });
});

describe('F3 — every server blocker kind has a label', () => {
  const KINDS = ['open_dispute', 'active_transfer', 'unpaid_seller_obligation', 'pending_refund', 'unsettled_transfer', 'paid_no_transfer', 'pending_payment', 'unresolved_review', 'open_payout_attempt', 'open_manual_review'];
  it('maps all ten kinds public.account_deletion_blockers returns, and no dead one', () => {
    const src = stripComments(read('app/settings/index.tsx'));
    const block = src.slice(src.indexOf('const OBLIGATION_LABELS'), src.indexOf('};', src.indexOf('const OBLIGATION_LABELS')));
    for (const k of KINDS) expect(block, k).toMatch(new RegExp(`^\\s*${k}: '`, 'm'));
    expect(block).not.toContain('reversal_required');
    expect(KINDS.length).toBe(10);
  });
});

describe('CFT-604 — loading, failed, empty and filtered are distinct on every tab', () => {
  it('Home: nothing empty during load; failure is a ScreenState; filters get "No matches"', () => {
    const home = stripComments(read('app/(tabs)/home.tsx'));
    expect(home).toContain('data={loading ? [] : filteredListings}');
    expect(home).toMatch(/ListEmptyComponent=\{\s*loading \? null : loadError \? \(\s*<ScreenState/);
    expect(home).toContain("activeCount > 0                ? { title: 'No matches', body: 'Try fewer filters.' }");
  });
  it('Bids: skeleton while loading; failure only replaces an EMPTY list; empty copy per segment', () => {
    const bids = stripComments(read('app/(tabs)/bids.tsx'));
    expect(bids).toContain(') : loadError && bids.length === 0 ? (');
    expect(bids).toContain("segment === 'active' ? 'No active bids' : 'Nothing here yet'");
  });
  it('Explore: skeleton while searching; failure screen or inline notice; empty only after a search', () => {
    const ex = stripComments(read('app/(tabs)/explore.tsx'));
    expect(ex).toContain('searching && results.length === 0 ? (');
    expect(ex).toContain("failure === 'screen' && loadError ? (");
    expect(ex).toMatch(/ListEmptyComponent=\{\s*searched \? \(/);
  });
  it('Tickets: three phases, empty only when loaded with no sections', () => {
    const t = stripComments(read('app/(tabs)/tickets.tsx'));
    expect(t).toMatch(/phase === 'loading' \? \([\s\S]*phase === 'error' \? \([\s\S]*sections\.length === 0 \? \(/);
  });
});

describe('CFT-605 — a listing that is gone offers a way forward from a cold start', () => {
  it('the not-found state routes to the live feed, not router.back()', () => {
    const d = stripComments(read('src/screens/ListingDetailScreen.tsx'));
    const block = d.slice(d.indexOf('title="Listing not found"'), d.indexOf('/>', d.indexOf('title="Listing not found"')));
    expect(block).toContain("action={{ label: 'Browse live listings', onPress: () => router.replace('/(tabs)/home') }}");
    expect(block).not.toContain('router.back()');
  });
});

describe('128 prep (C-1) — cold launch and contract_version pin, provisional until A freezes v2', () => {
  const rec: RegistrationRecord = { token: 'tok', userId: 'u1', method: 'rpc', outcome: 'refreshed', at: now - 60_000 };
  const base = { userId: 'u1', token: 'tok', record: rec, failure: null as RegistrationFailure | null, rpcAvailable: true as boolean | undefined, now };

  it('a fresh record skips normally but registers on the first decision of a process', () => {
    expect(decideRegistration(base)).toMatchObject({ action: 'skip', reason: 'fresh' });
    expect(decideRegistration({ ...base, coldLaunch: true })).toMatchObject({ action: 'register', reason: 'cold_launch' });
  });
  it('cold launch never overrides a terminal failure or backoff', () => {
    const bound: RegistrationFailure = { kind: 'bound_to_other', userId: 'u1', token: 'tok', method: 'rpc', at: now - 1, attempts: 1 };
    expect(decideRegistration({ ...base, failure: bound, coldLaunch: true })).toMatchObject({ action: 'wait', reason: 'bound_to_other' });
    const net: RegistrationFailure = { kind: 'network', userId: 'u1', token: 'tok', method: 'rpc', at: now - 1, attempts: 1 };
    expect(decideRegistration({ ...base, failure: net, coldLaunch: true })).toMatchObject({ action: 'wait', reason: 'backoff' });
  });
  it('a reply with another contract_version is not a success and is terminal until a new build', async () => {
    expect(EXPECTED_128_CONTRACT_VERSION).toBe(2);
    const rpc = async () => ({ data: { token_id: 't', outcome: 'refreshed', platform: 'ios', contract_version: EXPECTED_128_CONTRACT_VERSION + 1 }, error: null });
    expect(await registerWithRpc({ rpc }, { token: 'tok', platform: 'ios', secret: 's'.repeat(43), deviceName: null })).toEqual({ ok: false, kind: 'contract_mismatch' });
    const v2 = async () => ({ data: { token_id: 't', outcome: 'rebound', platform: 'ios', contract_version: EXPECTED_128_CONTRACT_VERSION }, error: null });
    expect(await registerWithRpc({ rpc: v2 }, { token: 'tok', platform: 'ios', secret: 's'.repeat(43), deviceName: null })).toMatchObject({ ok: true, outcome: 'rebound', contractVersion: 2 });
    const v1 = async () => ({ data: { token_id: 't', outcome: 'registered', platform: 'ios' }, error: null });
    expect(await registerWithRpc({ rpc: v1 }, { token: 'tok', platform: 'ios', secret: 's'.repeat(43), deviceName: null })).toMatchObject({ ok: true, contractVersion: null });
    const f: RegistrationFailure = { kind: 'contract_mismatch', userId: 'u1', token: 'tok', method: 'rpc', at: now, attempts: 1 };
    expect(decideRegistration({ ...base, failure: f, now: now + 10 * 24 * 3600_000 })).toMatchObject({ action: 'wait' });
    expect(classifyRegistrationError({ code: 'PGRST202', message: 'Could not find the function' })).toBe('rpc_missing');
  });
  it('the hook passes coldLaunch once per process and records the contract version', () => {
    const hook = stripComments(read('src/hooks/usePushToken.ts'));
    expect(hook).toContain('let coldLaunchPending = true;');
    expect(hook).toMatch(/coldLaunch: coldLaunchPending,\s*\}\);\s*coldLaunchPending = false;/);
    expect(hook).toContain("contractVersion: result.method === 'rpc' ? result.contractVersion : null,");
  });
});
