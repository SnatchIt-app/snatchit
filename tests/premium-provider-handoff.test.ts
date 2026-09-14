/**
 * tests/premium-provider-handoff.test.ts — CFT-404 (item 32): leaving for the
 * provider and returning to the same order without implying anything.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  HANDOFF_IDLE, MIN_AWAY_MS, PROVIDER_LINKS, leaveForProvider, onForeground,
  providerLink, RETURN_PROMPT, returnPrompt, returnPromptBody,
} from '@/src/lib/transfer/providerHandoff';
import { PLATFORM_INSTRUCTIONS } from '@/src/lib/platformInstructions';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('provider links', () => {
  it('cover every platform the instruction engine knows, https only, none for "other"', () => {
    const platforms = Object.keys(PLATFORM_INSTRUCTIONS);
    expect(Object.keys(PROVIDER_LINKS).sort()).toEqual(platforms.sort());
    for (const [p, link] of Object.entries(PROVIDER_LINKS)) {
      if (p === 'other') { expect(link).toBeNull(); continue; }
      expect(link, p).not.toBeNull();
      expect(link!.url, p).toMatch(/^https:\/\//);
      // the link label is the short form of the engine's display name
      const display = PLATFORM_INSTRUCTIONS[p as keyof typeof PLATFORM_INSTRUCTIONS].displayName.toLowerCase();
      expect(display, p).toContain(link!.name.toLowerCase());
    }
    expect(providerLink('other')).toBeNull();
    expect(providerLink(null)).toBeNull();
  });
});

describe('handoff: the return is a re-read, and the question comes from fresh state', () => {
  it('a foreground without a handoff does nothing', () => {
    expect(onForeground(HANDOFF_IDLE, 10_000)).toEqual({ next: HANDOFF_IDLE, refetch: false });
  });
  it('a blink shorter than MIN_AWAY_MS is not a trip to the provider', () => {
    const left = leaveForProvider(1_000);
    expect(onForeground(left, 1_000 + MIN_AWAY_MS - 1)).toEqual({ next: left, refetch: false });
  });
  it('a real return clears the handoff and asks for a refetch', () => {
    const left = leaveForProvider(1_000);
    expect(onForeground(left, 1_000 + MIN_AWAY_MS)).toEqual({ next: HANDOFF_IDLE, refetch: true });
  });
  it('the question is asked only while the seller\'s claim is the latest state and the buyer can act', () => {
    expect(returnPrompt('seller_sent', false)).toBe(true);
    expect(returnPrompt('seller_sent', true)).toBe(false);
    for (const st of ['pending', 'buyer_confirmed', 'auto_released', 'disputed', 'expired', 'reversed']) {
      expect(returnPrompt(st, false), st).toBe(false);
    }
  });
  it('the copy is a question that names what confirming does, and never asserts receipt', () => {
    expect(RETURN_PROMPT.title).toBe('Did the tickets arrive?');
    expect(returnPromptBody('Ticketmaster')).toContain('your Ticketmaster account');
    expect(returnPromptBody(null)).toContain('your ticket account');
    expect(returnPromptBody(null)).toMatch(/releases payment to the seller/);
    expect(`${RETURN_PROMPT.title} ${returnPromptBody(null)}`).not.toMatch(/tickets received|you received|payment (complete|succeeded)/i);
  });
});

describe('receive screen — shipped-source guards', () => {
  const screen = read('app/transfer/receive/[id].tsx');
  const code = stripComments(screen);

  it('opens only the official link, and records the handoff', () => {
    expect(code).toMatch(/const link = providerLink\(platform\);/);
    expect(code).toMatch(/Linking\.openURL\(link\.url\)/);
    expect(code).toMatch(/setHandoff\(leaveForProvider\(Date\.now\(\)\)\)/);
    expect(code).not.toMatch(/openURL\((?!link\.url)/);
  });

  it('on return it re-reads quietly and decides the question from the FRESH status', () => {
    expect(code).toMatch(/AppState\.addEventListener\('change', async \(st\) => \{\s*if \(st !== 'active'\) return;\s*const d = onForeground\(handoffRef\.current, Date\.now\(\)\);\s*if \(!d\.refetch\) return;/);
    expect(code).toMatch(/const fresh = await fetchTransfer\(\{ quiet: true \}\);\s*setArrivalPrompt\(!!fresh && returnPrompt\(fresh\.status, buyerNeedsDelivery\(fresh\)\)\);/);
    // a quiet re-read never replaces the order with a spinner or an error
    expect(code).toMatch(/if \(!opts\?\.quiet\) setLoading\(true\);/);
    expect(code).toMatch(/if \(!opts\?\.quiet\) setError\(/);
  });

  it('"They\'re here" only dismisses and highlights the explaining control; it never confirms', () => {
    const here = code.indexOf('label={RETURN_PROMPT.here}');
    expect(here).toBeGreaterThan(0);
    const line = code.slice(here, code.indexOf('/>', here));
    expect(line).toContain('setArrivalPrompt(false); setConfirmHighlight(true);');
    expect(line).not.toContain('handleConfirm');
    expect(line).not.toContain('confirmReceipt');
    // the explicit report path is the existing dispute flow, which asks first
    const problem = code.indexOf('label={RETURN_PROMPT.problem}');
    expect(code.slice(problem, code.indexOf('/>', problem))).toContain('handleDispute()');
  });

  it('the confirm control and the transfer RPCs are unchanged', () => {
    for (const marker of ["functions.invoke('confirm-and-release'", "rpc('buyer_dispute_transfer'", "rpc('mark_transfer_viewed'", 'By confirming, you release payment to the seller.']) {
      expect(screen).toContain(marker);
    }
    expect(code.split("functions.invoke('confirm-and-release'").length - 1).toBe(1);
  });
});
