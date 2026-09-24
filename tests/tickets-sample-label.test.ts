/**
 * tests/tickets-sample-label.test.ts — owner ruling 2026-09-17: the client-side
 * fixture preview of a populated Tickets tab (layout evidence only) must render
 * behind a VISIBLE label reading exactly "Sample tickets — no server data", so a
 * screenshot carries its own caveat and can never circulate as issuance working.
 * Never in a release build's default path: the toggle stays __DEV__-only and off
 * by default; fixture rows are never written anywhere.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { DEV_TICKET_FIXTURES, SAMPLE_TICKETS_LABEL } from '@/src/lib/tickets/fixtures';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('the sample-tickets label', () => {
  it('reads exactly as the owner ruled, and the fixtures module still writes nothing', () => {
    expect(SAMPLE_TICKETS_LABEL).toBe('Sample tickets — no server data');
    expect(DEV_TICKET_FIXTURES.length).toBeGreaterThan(0);
    const f = stripComments(read('src/lib/tickets/fixtures.ts'));
    expect(f).not.toMatch(/supabase|AsyncStorage|SecureStore|fetch\(/);
  });

  it('the Tickets screen shows the label whenever fixture rows are rendered, only in __DEV__, off by default', () => {
    // RETARGETED 2026-09-24 (V3 tickets task instruction): the `_dev/v3-tickets` harness renders
    // board fixtures through a `fixture` prop, and the owner's ruling follows the FIXTURE ROWS,
    // not the toggle — so the label condition widened from `devFixtures` to
    // `devFixtures || fixtureRows`. Everything the ruling pinned still holds below.
    const t = stripComments(read('app/(tabs)/tickets.tsx'));
    expect(t).toContain('SAMPLE_TICKETS_LABEL');
    // the label is tied to the same flag that swaps in the fixture rows
    expect(t).toContain('const effectiveRows: MyTicketGroup[] = devFixtures ? DEV_TICKET_FIXTURES : rows;');
    expect(t).toMatch(/\{devFixtures \|\| fixtureRows \? \(\s*<View[^>]*accessibilityRole="alert"[\s\S]*?\{SAMPLE_TICKETS_LABEL\}[\s\S]*?\) : null\}/);
    expect(t).toContain('useState(false)');                 // off by default
    expect(t).toContain('{__DEV__ ? (');                     // toggle exists only in development
    expect(t).not.toMatch(/setDevFixtures\(true\)/);         // nothing turns it on by itself
    // harness rows count as fixture rows on screen — the caveat covers them too
    expect(t).toContain("const fixtureRows = !!fixture && 'rows' in fixture && fixture.rows.length > 0;");
    // the label sits above the list, not inside a card, and cannot be dismissed
    const start = t.indexOf('{devFixtures || fixtureRows ? (');
    const block = t.slice(start, t.indexOf(') : null}', start));
    expect(block).toContain('{SAMPLE_TICKETS_LABEL}');
    expect(block).not.toContain('onPress');
  });
});
