/**
 * Tickets and the primary hold on New York's clock (owner, 2026-11-02: "we operate in EST"; A's rulings; c36 g3).
 *
 * Three roots formatted an instant in the DEVICE zone, so a buyer's phone zone changed what the app showed:
 *   - eventDateLabel — the Tickets tab card date and its VoiceOver label. get_my_tickets rows carry no zone
 *     (MyTicketGroup), so the instant is shown in America/New_York, fixed en-US spelling, labelled EST / EDT;
 *   - whenLine — the ticket detail when only the instant is known. No venue zone, or one Intl cannot use, →
 *     America/New_York labelled from eastern.ts; a venue zone that IS given is used as before (venue contract);
 *   - holdExpiryClock — the primary checkout's "Held for you until …", from the server hold expiry.
 *
 * Every case runs under process zones UTC, America/Los_Angeles and America/New_York with identical answers, and
 * each anchor carries a witness that a device-zone reading really disagrees there (so a device fallback could
 * not pass). Anchors (A): 2026-11-02 04:59:59Z / 05:00Z (ET midnight in EST), 2026-11-01 03:59:59Z / 04:00Z (ET
 * midnight in EDT), the 25-hour 2026-11-01 (01:30 EDT at 05:30Z, 01:30 EST at 06:30Z), the 23-hour 2026-03-08,
 * and the evening 2026-11-03T02:14Z (Mon 2 Nov 21:14 EST = Mon 18:14 LA = Tue 02:14 UTC).
 *
 * Negative controls (run by hand, each must FAIL): put toLocaleDateString / toLocaleTimeString(undefined) back in
 * eventDateLabel (TE1–TE3, TC1); let whenLine format in the device zone when no venue zone is given (TE1–TE3, TC1,
 * WE1–WE3, TD1) or when the zone is not one Intl can use (WE2); put the zone-less Intl.DateTimeFormat back in
 * holdExpiryClock (HC1, HC2) or in the native checkout's own setHeldUntil (HC3).
 */
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

vi.mock('@/src/theme/appearance', async () => {
  const { paletteFor } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'light', palette: paletteFor('light') }) };
});
vi.mock('react-native', () => ({
  Text: 'Text', View: 'View', Pressable: 'Pressable', ScrollView: 'ScrollView', RefreshControl: 'RefreshControl',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
  useWindowDimensions: () => ({ width: 390, height: 844, scale: 3, fontScale: 1 }),
}));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', EmptyState: 'EmptyState', Spinner: 'Spinner' }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/account/SettingsHeader', () => ({ SettingsHeader: 'SettingsHeader' }));
vi.mock('@/src/components/tickets/EntitlementCard', () => ({ EntitlementCard: 'EntitlementCard' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: () => { throw new Error('not used in tests'); } } }));

import { readFileSync } from 'node:fs';

import { holdExpiryClock } from '@/src/lib/primary/checkoutRoute';
import { eventDateLabel, type EventGroup } from '@/src/lib/tickets/ticketState';
import { whenLine } from '@/src/lib/tickets/ticketWhen';
import type { MyTicketGroup } from '@/src/lib/tickets/types';
import { HookHost, type Element } from './helpers/nav-stack-harness';

const ZONES = ['UTC', 'America/Los_Angeles', 'America/New_York'] as const;
const original = process.env.TZ;
afterEach(() => { if (original === undefined) delete process.env.TZ; else process.env.TZ = original; });

/** Runs `fn` under each process zone and returns the answers, which must all be equal. */
function underEveryZone<T>(fn: () => T): T {
  const answers = ZONES.map((z) => { process.env.TZ = z; return fn(); });
  for (const a of answers) expect(a).toEqual(answers[0]);
  return answers[0];
}

/** The card's old reading: the device zone (locale pinned to en-US so only the zone varies). */
function deviceCard(iso: string, zone: string): string {
  process.env.TZ = zone;
  const d = new Date(iso);
  return `${d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} - ${d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`;
}
/** The hold line's old reading: Intl with no timeZone, i.e. the device zone. */
function deviceClock(iso: string, zone: string): string {
  process.env.TZ = zone;
  return new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit' }).format(new Date(iso));
}

const EVENING = '2026-11-03T02:14:00Z';
const EVENING_DOORS = '2026-11-03T01:00:00Z';

describe('eventDateLabel — the Tickets card date, on New York’s clock and labelled', () => {
  it('TE1: the evening anchor reads Mon, Nov 2 - 9:14 PM EST on every phone; the witness shows LA and UTC phones disagree', () => {
    expect(underEveryZone(() => eventDateLabel(EVENING))).toBe('Mon, Nov 2 - 9:14 PM EST');
    expect(deviceCard(EVENING, 'America/Los_Angeles')).toBe('Mon, Nov 2 - 6:14 PM');
    expect(deviceCard(EVENING, 'UTC')).toBe('Tue, Nov 3 - 2:14 AM');
  });

  it('TE2: the card’s day turns at New York midnight, in EST (05:00Z) and in EDT (04:00Z)', () => {
    expect(underEveryZone(() => eventDateLabel('2026-11-02T04:59:59Z'))).toBe('Sun, Nov 1 - 11:59 PM EST');
    expect(underEveryZone(() => eventDateLabel('2026-11-02T05:00:00Z'))).toBe('Mon, Nov 2 - 12:00 AM EST');
    expect(underEveryZone(() => eventDateLabel('2026-11-01T03:59:59Z'))).toBe('Sat, Oct 31 - 11:59 PM EDT');
    expect(underEveryZone(() => eventDateLabel('2026-11-01T04:00:00Z'))).toBe('Sun, Nov 1 - 12:00 AM EDT');
    expect(deviceCard('2026-11-02T04:59:59Z', 'UTC')).toBe('Mon, Nov 2 - 4:59 AM');                    // a UTC phone is on the 2nd
    expect(deviceCard('2026-11-02T05:00:00Z', 'America/Los_Angeles')).toBe('Sun, Nov 1 - 9:00 PM');    // an LA phone on the 1st
    expect(deviceCard('2026-11-01T03:59:59Z', 'UTC')).toBe('Sun, Nov 1 - 3:59 AM');
    expect(deviceCard('2026-11-01T04:00:00Z', 'America/Los_Angeles')).toBe('Sat, Oct 31 - 9:00 PM');
  });

  it('TE3: the repeated 1:30 AM of 2026-11-01 is told apart by its label; 2026-03-08 skips from 1:59 AM EST to 3:00 AM EDT', () => {
    expect(underEveryZone(() => eventDateLabel('2026-11-01T05:30:00Z'))).toBe('Sun, Nov 1 - 1:30 AM EDT');
    expect(underEveryZone(() => eventDateLabel('2026-11-01T06:30:00Z'))).toBe('Sun, Nov 1 - 1:30 AM EST');
    expect(underEveryZone(() => eventDateLabel('2026-03-08T06:59:00Z'))).toBe('Sun, Mar 8 - 1:59 AM EST');
    expect(underEveryZone(() => eventDateLabel('2026-03-08T07:00:00Z'))).toBe('Sun, Mar 8 - 3:00 AM EDT');
    expect(deviceCard('2026-11-01T05:30:00Z', 'America/Los_Angeles')).toBe('Sat, Oct 31 - 10:30 PM');
    expect(deviceCard('2026-03-08T07:00:00Z', 'UTC')).toBe('Sun, Mar 8 - 7:00 AM');
  });

  it('TE4: nothing, or a value that is not an instant, still reads as no date', () => {
    expect(eventDateLabel(null)).toBe('');
    expect(eventDateLabel(undefined)).toBe('');
    expect(eventDateLabel('')).toBe('');
    expect(eventDateLabel('not-a-date')).toBe('');
  });
});

describe('the Tickets card shows that label and speaks it (TicketEventGroup)', () => {
  const row: MyTicketGroup = {
    event_id: 'e1', event_session_id: 's1', event_title: 'Night Set', session_label: null,
    starts_at: EVENING, ends_at: null, doors_at: EVENING_DOORS, venue_id: 'v1', venue_name: 'The Venue',
    artwork_ref: null, ticket_type_id: 't1', ticket_type_name: 'GA', ticket_type_kind: 'admission', quantity: 1,
    ownership_status: 'valid', fulfillment_status: 'held', time_class: 'upcoming',
  };
  const group: EventGroup = {
    key: 's1:e1', event_session_id: 's1', event_title: 'Night Set', session_label: null, starts_at: EVENING,
    ends_at: null, venue_name: 'The Venue', artwork_ref: null, time_class: 'upcoming', rows: [row],
  };

  /** Every host element, with the card's own hook-free inner components (CardShell, StateRow) rendered in place. */
  function all(node: unknown, out: Element[] = []): Element[] {
    if (Array.isArray(node)) { node.forEach((n) => all(n, out)); return out; }
    if (!node || typeof node !== 'object') return out;
    const el = node as Element;
    if (typeof el.type === 'function') return all((el.type as (p: unknown) => unknown)(el.props), out);
    out.push(el);
    all(el.props?.children, out);
    return out;
  }

  async function render(emphasis: 'upcoming' | 'past') {
    const mod = await import('@/src/components/tickets/TicketEventGroup');
    const exported = mod.TicketEventGroup as unknown;
    const Fn = (typeof exported === 'function'
      ? exported
      : (exported as { type: (p: unknown) => unknown }).type) as (props: unknown) => unknown;
    const host = new HookHost(() => Fn({ group: { ...group, time_class: emphasis }, emphasis, onPress: () => {} }), new Map());
    host.mount(); host.flush();
    const nodes = all(host.output);
    const texts = nodes.filter((n) => n.type === 'Text').map((n) => n.props.children);
    const shell = nodes.find((n) => n.type === 'Pressable');
    return { texts, label: shell?.props.accessibilityLabel };
  }

  it('TC1: both cards print the New York date with its label, and the spoken card label says the same zone', async () => {
    for (const emphasis of ['upcoming', 'past'] as const) {
      const answers = [];
      for (const z of ZONES) { process.env.TZ = z; answers.push(await render(emphasis)); }
      for (const a of answers) {
        expect(a.texts, emphasis).toContain('Mon, Nov 2 - 9:14 PM EST');
        expect(a.label, emphasis).toBe('Night Set, Mon, Nov 2 - 9:14 PM EST, The Venue. 1 x GA, Valid');
      }
    }
    expect(deviceCard(EVENING, 'America/Los_Angeles')).not.toBe('Mon, Nov 2 - 9:14 PM');   // witness: an LA phone read 6:14 PM
  });
});

describe('whenLine — the ticket detail when only the instant is known', () => {
  const EASTERN_EVENING = { date: 'Mon, Nov 2', times: 'Doors 8:00 PM · 9:14 PM EST', zone: 'EST' };

  it('WE1: no venue zone → New York, labelled EST, doors on the same clock — on every phone', () => {
    expect(underEveryZone(() => whenLine(EVENING, EVENING_DOORS))).toEqual(EASTERN_EVENING);
    expect(underEveryZone(() => whenLine(EVENING, EVENING_DOORS, undefined))).toEqual(EASTERN_EVENING);
    expect(underEveryZone(() => whenLine(EVENING, EVENING_DOORS, null))).toEqual(EASTERN_EVENING);
    expect(underEveryZone(() => whenLine(EVENING, EVENING_DOORS, ''))).toEqual(EASTERN_EVENING);
    expect(deviceCard(EVENING, 'America/Los_Angeles')).toBe('Mon, Nov 2 - 6:14 PM');   // witness
    expect(deviceCard(EVENING, 'UTC')).toBe('Tue, Nov 3 - 2:14 AM');
  });

  it('WE2: a venue zone Intl cannot use → New York, labelled; never the device clock, never unlabelled', () => {
    expect(underEveryZone(() => whenLine(EVENING, EVENING_DOORS, 'Not/AZone'))).toEqual(EASTERN_EVENING);
    expect(underEveryZone(() => whenLine(EVENING, null, 'EST5EDT-not-a-zone'))).toEqual({ date: 'Mon, Nov 2', times: '9:14 PM EST', zone: 'EST' });
  });

  it('WE3: the fallback follows New York’s calendar across both midnights and both DST changes', () => {
    const at = (iso: string) => underEveryZone(() => { const w = whenLine(iso, null); return w && `${w.date} | ${w.times}`; });
    expect(at('2026-11-02T04:59:59Z')).toBe('Sun, Nov 1 | 11:59 PM EST');
    expect(at('2026-11-02T05:00:00Z')).toBe('Mon, Nov 2 | 12:00 AM EST');
    expect(at('2026-11-01T03:59:59Z')).toBe('Sat, Oct 31 | 11:59 PM EDT');
    expect(at('2026-11-01T04:00:00Z')).toBe('Sun, Nov 1 | 12:00 AM EDT');
    expect(at('2026-11-01T05:30:00Z')).toBe('Sun, Nov 1 | 1:30 AM EDT');
    expect(at('2026-11-01T06:30:00Z')).toBe('Sun, Nov 1 | 1:30 AM EST');
    expect(at('2026-03-08T06:59:00Z')).toBe('Sun, Mar 8 | 1:59 AM EST');
    expect(at('2026-03-08T07:00:00Z')).toBe('Sun, Mar 8 | 3:00 AM EDT');
    expect(deviceCard('2026-11-02T04:59:59Z', 'UTC')).toBe('Mon, Nov 2 - 4:59 AM');     // witnesses
    expect(deviceCard('2026-11-01T06:30:00Z', 'America/Los_Angeles')).toBe('Sat, Oct 31 - 11:30 PM');
    expect(underEveryZone(() => whenLine('not-a-date', null))).toBeNull();
  });

  it('WE4: a venue zone that is given is still the venue’s clock and Intl’s name for it (venue contract, unchanged)', () => {
    expect(underEveryZone(() => whenLine(EVENING, EVENING_DOORS, 'America/Chicago'))).toEqual({ date: 'Mon, Nov 2', times: 'Doors 7:00 PM · 8:14 PM CST', zone: 'CST' });
    expect(underEveryZone(() => whenLine(EVENING, null, 'America/Los_Angeles'))).toEqual({ date: 'Mon, Nov 2', times: '6:14 PM PST', zone: 'PST' });
    expect(underEveryZone(() => whenLine(EVENING, null, 'Europe/London'))).toEqual({ date: 'Tue, Nov 3', times: '2:14 AM GMT', zone: 'GMT' });
    expect(underEveryZone(() => whenLine(EVENING, EVENING_DOORS, 'America/New_York'))).toEqual(EASTERN_EVENING);
  });

  it('TD1: the detail screen’s event block, with no venue facts or no venue zone, shows the New York line', async () => {
    const { eventBlock } = await import('@/src/screens/tickets/TicketDetailView');
    const group = {
      event_id: 'e1', event_session_id: 's1', event_title: 'Night Set', session_label: null, starts_at: EVENING,
      ends_at: null, doors_at: EVENING_DOORS, venue_id: 'v1', venue_name: 'The Venue', artwork_ref: null,
      ticket_type_id: 't1', ticket_type_name: 'GA', ticket_type_kind: 'admission' as const, quantity: 1,
      ownership_status: 'valid' as const, fulfillment_status: 'held' as const, time_class: 'upcoming' as const,
    };
    const noZone = {
      title: null, venueName: null, address: null, sessionLabel: null, timezone: null,
      startsAtLocal: null, doorsAtLocal: null, startsAt: null, ageRestriction: null,
    };
    expect(underEveryZone(() => eventBlock(null, group).when)).toEqual(EASTERN_EVENING);
    expect(underEveryZone(() => eventBlock(noZone, group).when)).toEqual(EASTERN_EVENING);
    expect(underEveryZone(() => eventBlock({ ...noZone, timezone: 'America/Chicago' }, group).when))
      .toEqual({ date: 'Mon, Nov 2', times: 'Doors 7:00 PM · 8:14 PM CST', zone: 'CST' });
  });
});

describe('holdExpiryClock — "Held for you until …" on the primary checkout', () => {
  it('HC1: the hold expiry reads in New York with its label — 8:15 PM EST in November, 8:15 PM EDT in July', () => {
    expect(underEveryZone(() => holdExpiryClock('2026-11-03T01:15:00Z'))).toBe('8:15 PM EST');
    expect(underEveryZone(() => holdExpiryClock('2026-07-04T00:15:00Z'))).toBe('8:15 PM EDT');
    expect(deviceClock('2026-11-03T01:15:00Z', 'America/Los_Angeles')).toBe('5:15 PM');   // witness
    expect(deviceClock('2026-11-03T01:15:00Z', 'UTC')).toBe('1:15 AM');
  });

  it('HC2: the repeated 1:30 AM is told apart by its label; no expiry, or one that is not an instant, hides the line', () => {
    expect(underEveryZone(() => holdExpiryClock('2026-11-01T05:30:00Z'))).toBe('1:30 AM EDT');
    expect(underEveryZone(() => holdExpiryClock('2026-11-01T06:30:00Z'))).toBe('1:30 AM EST');
    expect(deviceClock('2026-11-01T06:30:00Z', 'UTC')).toBe('6:30 AM');
    expect(holdExpiryClock(null)).toBeNull();
    expect(holdExpiryClock('')).toBeNull();
    expect(holdExpiryClock('soon')).toBeNull();
  });

  it('HC3: the native checkout shows the hold line only through holdExpiryClock and formats no clock of its own', () => {
    const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    const native = strip(readFileSync('src/screens/primary/PrimaryCheckoutEntry.native.tsx', 'utf8'));
    expect(native).toContain('setHeldUntil(holdExpiryClock(hold.expiresAt));');
    expect(native).not.toMatch(/Intl\.DateTimeFormat|toLocale(Date|Time)?String|function clockText/);
    const view = strip(readFileSync('src/screens/primary/PrimaryCheckoutView.tsx', 'utf8'));
    expect(view).toContain('heldUntil: (time: string) => `Held for you until ${time}`,');
  });
});
