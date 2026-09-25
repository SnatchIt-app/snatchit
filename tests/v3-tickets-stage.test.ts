/**
 * V3 tickets stage — the pkg8-account-tickets board rules, tested where they live.
 *
 * The board draws ONE meaningful word per card row: "Valid" on the quiet ordinary card, and the
 * fulfillment word alone once one is worth surfacing ("Midnight Arcade · Transfer in progress").
 * That must never hide a non-valid ownership word — "Void" behind "Listed for resale" would
 * misstate ownership — so the rule is behavioural, not sample-shaped, and it is tested as a
 * truth table across every (ownership x fulfillment) pair.
 *
 * Source pins hold the screen to the V3 voice (sentence-case screen title, mixed-case name
 * steps, radius by role) and hold the harness to the real component with literal fixtures.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  fulfillmentLabel,
  fulfillmentTone,
  ownershipLabel,
  ownershipTone,
  showFulfillmentBadge,
  showOwnershipBadge,
} from '@/src/lib/tickets/ticketState';
import type { FulfillmentStatus, OwnershipStatus } from '@/src/lib/tickets/types';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const OWNERSHIP: OwnershipStatus[] = ['valid', 'used', 'void', 'expired'];
const FULFILLMENT: FulfillmentStatus[] = ['held', 'listed', 'in_transfer', 'payment_hold', 'disputed'];

describe('one meaningful word per row (board rule), never at the cost of a true one', () => {
  it('TK1: the ordinary card says Valid; a surfaced fulfillment state takes the slot from Valid only', () => {
    // The board's two cards, exactly:
    expect(showOwnershipBadge('valid', 'held')).toBe(true);          // "Neon Choir · Valid"
    expect(showOwnershipBadge('valid', 'in_transfer')).toBe(false);  // "Midnight Arcade · Transfer in progress"
    expect(showFulfillmentBadge('in_transfer')).toBe(true);
    expect(showFulfillmentBadge('held')).toBe(false);
  });

  it('TK2: a NON-valid ownership word always shows — hiding it would misstate ownership', () => {
    for (const o of OWNERSHIP) {
      for (const f of FULFILLMENT) {
        if (o !== 'valid') expect(showOwnershipBadge(o, f), `${o} x ${f}`).toBe(true);
      }
    }
    // The pair the rule exists to protect: Void stays on screen next to Listed for resale.
    expect(showOwnershipBadge('void', 'listed')).toBe(true);
  });

  it('TK3: every row still renders at least one word — no state is ever colour-only or word-free', () => {
    for (const o of OWNERSHIP) {
      for (const f of FULFILLMENT) {
        const words = [
          ...(showOwnershipBadge(o, f) ? [ownershipLabel(o)] : []),
          ...(showFulfillmentBadge(f) ? [fulfillmentLabel(f)] : []),
        ];
        expect(words.length, `${o} x ${f}`).toBeGreaterThan(0);
      }
    }
  });

  it('TK4: board tones — Valid is quiet, a transfer in progress is the amber word; the alarms keep theirs', () => {
    expect(ownershipTone('valid')).toBe('neutral');        // pkg8 board: white outline, not green
    expect(fulfillmentTone('in_transfer')).toBe('warning'); // pkg8 board: amber
    // Negative controls — the change is those two values, nothing else:
    expect(ownershipTone('void')).toBe('danger');
    expect(fulfillmentTone('disputed')).toBe('danger');
    expect(fulfillmentTone('payment_hold')).toBe('warning');
    expect(ownershipTone('used')).toBe('neutral');
    expect(ownershipTone('expired')).toBe('neutral');
    expect(fulfillmentTone('listed')).toBe('neutral');
  });
});

describe('screen and card — the V3 voice and geometry (source pins)', () => {
  it('TK5: the tab heading is the sentence-case screen title, and the copy is unchanged', () => {
    const t = strip(read('app/(tabs)/tickets.tsx'));
    expect(t).toMatch(/textStyle\('screenTitle'\)[^\n]*>Your tickets<\/Text>/);
    expect(t).not.toMatch(/textStyle\('display\w+'\)/);
    expect(t).toContain('title="No tickets yet"');
    expect(t).toContain('body="Tickets you own will show up here."');
  });

  it('TK6: event names carry the mixed-case display steps; cards and small media round by role', () => {
    const g = strip(read('src/components/tickets/TicketEventGroup.tsx'));
    expect(g).toMatch(/textStyle\('nameOrder'\)/);   // loud upcoming card
    expect(g).toMatch(/textStyle\('nameRow'\)/);     // quiet past row
    expect(g).toMatch(/borderRadius: v2\.radius\.md/);
    /*
     * The `radius.sm` this used to require was the past-row thumbnail WRAPPER's radius, and it was
     * a defect the 4:5 poster direction removed (2026-09-24): the wrapper clipped the poster back
     * to a square at a 10pt arc, inside a frame whose own radius is 8. Media radius now comes from
     * the slot, so the screen must NOT carry a second one — the absence is the rule, and this
     * asserts it rather than requiring the thing that was wrong.
     */
    expect(g).not.toMatch(/borderRadius: v2\.radius\.sm/);
    // Rounding must still clip the CARD's artwork, or the card corners square themselves back.
    expect(g).toMatch(/overflow: 'hidden'/);
    // Badge visibility goes through the tested rule, both families, no hand-rolled condition.
    expect(g).toMatch(/showOwnershipBadge\(row\.ownership_status, row\.fulfillment_status\)/);
    expect(g).toMatch(/showFulfillmentBadge\(row\.fulfillment_status\)/);
  });

  it('TK7: the full state pair stays in the a11y label even where a visible badge yields its slot', () => {
    const g = strip(read('src/components/tickets/TicketEventGroup.tsx'));
    const a11y = g.slice(g.indexOf('function rowA11yLabel'), g.indexOf('function groupA11yLabel'));
    expect(a11y).toContain('ownershipLabel(r.ownership_status)');
    expect(a11y).not.toContain('showOwnershipBadge');
  });
});

describe('the v3-tickets harness — real component, literal fixtures, gated route', () => {
  it('TK8: mounts the real TicketsScreen with a fixture, never a recreated mock', () => {
    const h = strip(read('app/_dev/v3-tickets.tsx'));
    expect(h).toContain("import TicketsScreen, { type TicketsFixture } from '@/app/(tabs)/tickets'");
    expect(h).toMatch(/<TicketsScreen fixture=\{fixture\} \/>/);
    expect(h).toContain('if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;');
    // Fixtures are literals: nothing here may reach a server or storage.
    expect(h).not.toMatch(/supabase|fetch\(|AsyncStorage|SecureStore/);
  });

  it('TK9: the three required states exist — populated, past/expired, empty — and empty is rows, not a failure', () => {
    const h = strip(read('app/_dev/v3-tickets.tsx'));
    expect(h).toMatch(/case 'empty': return \{ rows: \[\] \};/);
    expect(h).toMatch(/case 'past': return \{ rows: PAST \};/);
    expect(h).toMatch(/default: return \{ rows: POPULATED \};/);
    // The past set carries every past ownership word the boards' badge family names.
    for (const word of ["ownership_status: 'used'", "ownership_status: 'expired'", "ownership_status: 'void'"]) {
      expect(h).toContain(word);
    }
  });

  it('TK10: the screen fixture short-circuits ONLY the network read', () => {
    const t = strip(read('app/(tabs)/tickets.tsx'));
    expect(t).toContain('if (fixture) return;');
    // The RPC call stays exactly where it was, behind that gate, in the api module.
    expect(t).toContain('await fetchMyTickets()');
  });
});
