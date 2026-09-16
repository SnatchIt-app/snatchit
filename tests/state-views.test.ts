/**
 * tests/state-views.test.ts — the offline / server-error / empty / no-match
 * states, refreshed to the Premium primitives (owner request from the build 17
 * screenshots, 2026-09-16). Pure decisions and copy are tested; the screens are
 * pinned to use them; the static preview is pinned to the same copy.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { classifyLoadFailure, STATE_COPY } from '@/src/lib/ui/loadState';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('which state a failed load shows', () => {
  it('offline when the OS says so, or when the error is a connectivity failure; otherwise a server error', () => {
    expect(classifyLoadFailure(new Error('Network request failed'), false)).toBe('offline');
    expect(classifyLoadFailure({ message: 'TypeError: fetch failed' }, false)).toBe('offline');
    expect(classifyLoadFailure({ code: 'PGRST301', message: 'JWT expired' }, true)).toBe('offline');
    expect(classifyLoadFailure({ code: '42501', message: 'permission denied' }, false)).toBe('error');
    expect(classifyLoadFailure(null, false)).toBe('error');
  });

  it('an aborted or timed-out request is not evidence the user is offline (SV-1): it is the server-error state', () => {
    expect(classifyLoadFailure({ name: 'AbortError', message: 'Aborted' }, false)).toBe('error');
    expect(classifyLoadFailure(new Error('The operation was aborted'), false)).toBe('error');
    expect(classifyLoadFailure(new Error('Request timed out'), false)).toBe('error');
    expect(classifyLoadFailure({ message: 'timeout of 10000ms exceeded' }, false)).toBe('error');
    // the OS signal still wins
    expect(classifyLoadFailure({ name: 'AbortError', message: 'Aborted' }, true)).toBe('offline');
  });

  it('copy: four distinct states, each with a title, a body and (for failures) a Retry', () => {
    expect(STATE_COPY.offline.title).toBe("You're offline");
    expect(STATE_COPY.offline.body).toBe('Check your internet connection and try again.');
    expect(STATE_COPY.error.title).not.toBe(STATE_COPY.offline.title);
    expect(STATE_COPY.error.title).not.toMatch(/something went wrong/i);
    // SV-3: the error state also covers 500s, permission failures and (after SV-1) timeouts,
    // so its sentence must not claim to know which one happened.
    expect(STATE_COPY.error.body).not.toMatch(/in time|timed out|timeout/i);
    expect(STATE_COPY.offline.retry).toBe('Retry');
    expect(STATE_COPY.error.retry).toBe('Retry');
    expect(STATE_COPY.noMatch.title).toBe('Nothing matches');
    for (const k of ['offline', 'error', 'noMatch'] as const) {
      expect(STATE_COPY[k].title.length).toBeLessThan(40);
      expect(STATE_COPY[k].body.endsWith('.')).toBe(true);
    }
  });
});

describe('the Premium state view and the screens that use it', () => {
  it('StateView uses the Premium primitives, one glyph treatment, an accessible Retry, and no emoji or legacy theme', () => {
    const s = stripComments(read('src/components/ui/StateView.tsx'));
    expect(s).toContain("textStyle('displaySm')");
    expect(s).toContain('<Button');
    expect(s).toContain('<IconSymbol');
    expect(s).toContain("accessibilityRole={failure ? 'alert' : undefined}");
    expect(s).toContain('announceForAccessibility');
    expect(s).not.toMatch(/[📡⚠️🎟️🔍]/u);
    expect(s).not.toContain("from '@/src/theme'");
    expect(s).not.toContain('Animated');
  });

  it('ScreenState and EmptyState are thin wrappers over StateView (one implementation)', () => {
    const sc = stripComments(read('src/components/ScreenState.tsx'));
    expect(sc).toContain('<StateView');
    expect(sc).not.toContain('Something went wrong');
    expect(sc).not.toContain("from '@/src/theme'");
    const em = stripComments(read('src/components/ui/EmptyState.tsx'));
    expect(em).toContain('<StateView kind="empty"');
  });

  it('Tickets classifies a failed first load like the other tabs (offline vs server error)', () => {
    const t = stripComments(read('app/(tabs)/tickets.tsx'));
    expect(t).toContain('classifyLoadFailure(error, offlineRef.current)');
    expect(t).toContain('<ScreenState state={loadError}');
    expect(t).not.toContain("state={'error' as ScreenStateKind}");
  });

  it('every tab classifies with the same helper and keeps cached content on a failed refresh', () => {
    for (const p of ['app/(tabs)/home.tsx', 'app/(tabs)/explore.tsx', 'app/(tabs)/bids.tsx', 'app/(tabs)/profile.tsx']) {
      const s = stripComments(read(p));
      expect(s, p).toContain('classifyLoadFailure(');
      expect(s, p).not.toMatch(/isNetworkError\([^)]*\) \? 'offline' : 'error'/);
    }
    expect(stripComments(read('app/(tabs)/bids.tsx'))).toContain('loadError && bids.length === 0');
    expect(stripComments(read('app/(tabs)/explore.tsx'))).toContain("failure === 'inline' && loadError");
  });

  it('no-match on Explore is its own state, distinct from empty', () => {
    const e = stripComments(read('app/(tabs)/explore.tsx'));
    expect(e).toContain('<StateView kind="noMatch"');
  });

  it('the four tab headings clear the sandbox badge at every text size (useTopInset)', () => {
    for (const p of ['src/components/discovery/HomeHeader.tsx', 'app/(tabs)/explore.tsx', 'app/(tabs)/bids.tsx', 'app/(tabs)/tickets.tsx', 'app/(tabs)/profile.tsx']) {
      const s = stripComments(read(p));
      expect(s, p).toContain('useTopInset()');
      expect(s, p).not.toMatch(/paddingTop: insets\.top/);
    }
  });
});

describe('static preview is labelled and pinned to the same copy', () => {
  const html = read('docs/product-v2/previews/state-views-preview.html').replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, '&');
  it('says what it is and shows the four states plus the large-text frame', () => {
    expect(html).toContain('Static preview — not a device render');
    expect((html.match(/class="tag">static</g) ?? []).length).toBeGreaterThanOrEqual(5);
    for (const k of ['offline', 'error', 'noMatch'] as const) {
      expect(html).toContain(STATE_COPY[k].title);
      expect(html).toContain(STATE_COPY[k].body);
    }
    expect(html).toContain('No tickets yet');
    expect(html).toContain('SANDBOX — TEST MONEY ONLY');
  });
});
