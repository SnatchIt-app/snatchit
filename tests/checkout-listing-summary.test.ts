/**
 * tests/checkout-listing-summary.test.ts — finding F1.
 *
 * The defect was invisible from the app: PostgREST rejected the whole select
 * because of one non-existent column, and the screen simply showed nothing
 * where the event and the hold countdown belong. These tests pin the column
 * list and the mapping so the next rename fails here instead of on a handset.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  LISTING_SUMMARY_COLUMNS,
  mapListingSummary,
  reservedUntilMs,
  ticketCountLabel,
} from '../src/lib/checkout/listingSummary';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const COLUMNS = LISTING_SUMMARY_COLUMNS.split(',').map(c => c.trim());

describe('the summary select asks only for columns that exist', () => {
  it('never asks for cover_image_url — the column that produced the 400', () => {
    expect(LISTING_SUMMARY_COLUMNS).not.toMatch(/cover_image_url/);
  });

  it('asks for every field the summary and the countdown need', () => {
    expect(COLUMNS.sort()).toEqual(
      // V3 (owner 2026-09-23): + ticket_type for the identity line. Same authorized row.
      ['cover_image_path', 'event_date', 'event_name', 'event_time', 'quantity', 'reserved_until', 'ticket_type', 'venue'],
    );
  });

  it('is a named list, not a wildcard', () => {
    expect(LISTING_SUMMARY_COLUMNS).not.toContain('*');
  });
});

describe('mapping a row to what the screen shows', () => {
  const fallback = { eventName: 'Nav event', venue: 'Nav venue' };

  it('takes the row values when they are present', () => {
    expect(mapListingSummary({
      cover_image_path: 'seller/cover.jpg',
      event_name: 'Cup Final',
      venue: 'Stadium',
      event_date: '2026-10-01',
      event_time: '19:30',
    }, fallback)).toEqual({
      cover: 'seller/cover.jpg',
      eventName: 'Cup Final',
      venue: 'Stadium',
      date: '2026-10-01',
      time: '19:30',
      quantity: null,
      ticketType: null,
    });
  });

  it('reports a missing image as null so the placeholder renders', () => {
    expect(mapListingSummary({ event_name: 'Cup Final' }, fallback).cover).toBeNull();
    expect(mapListingSummary({ cover_image_path: null }, fallback).cover).toBeNull();
    expect(mapListingSummary({ cover_image_path: '   ' }, fallback).cover).toBeNull();
  });

  it('still resolves a legacy absolute URL if a row carries one', () => {
    // Not selected, but the renderer accepts either form, so the mapper must
    // not discard it when a caller has it.
    expect(mapListingSummary(
      { cover_image_url: 'https://example.test/cover.jpg' },
      fallback,
    ).cover).toBe('https://example.test/cover.jpg');
  });

  it('prefers the storage path over the legacy URL', () => {
    expect(mapListingSummary(
      { cover_image_path: 'seller/cover.jpg', cover_image_url: 'https://example.test/c.jpg' },
      fallback,
    ).cover).toBe('seller/cover.jpg');
  });

  it('falls back to what navigation knew when a text column is absent or blank', () => {
    expect(mapListingSummary({ event_name: '', venue: null }, fallback)).toMatchObject({
      eventName: 'Nav event',
      venue: 'Nav venue',
    });
  });

  it('renders no date or time rather than empty-looking values', () => {
    const s = mapListingSummary({ event_date: '  ', event_time: null }, fallback);
    expect(s.date).toBe('');
    expect(s.time).toBe('');
  });

  it('maps ticket_type through the same presence rule — "GA" stays, blank is null (A review N1)', () => {
    expect(mapListingSummary({ ticket_type: 'GA' }, fallback).ticketType).toBe('GA');
    expect(mapListingSummary({ ticket_type: '   ' }, fallback).ticketType).toBeNull();
    expect(mapListingSummary({ ticket_type: null }, fallback).ticketType).toBeNull();
    expect(mapListingSummary({}, fallback).ticketType).toBeNull();
  });

  it('survives a missing row entirely', () => {
    expect(mapListingSummary(null, fallback)).toEqual({
      cover: null, eventName: 'Nav event', venue: 'Nav venue', date: '', time: '', quantity: null, ticketType: null,
    });
  });
});

describe('the hold countdown', () => {
  it('reads the deadline when the listing is held', () => {
    expect(reservedUntilMs({ reserved_until: '2026-09-11T04:03:27.000Z' }))
      .toBe(Date.parse('2026-09-11T04:03:27.000Z'));
  });

  it('shows no countdown when there is no hold', () => {
    expect(reservedUntilMs({})).toBeNull();
    expect(reservedUntilMs({ reserved_until: null })).toBeNull();
    expect(reservedUntilMs(null)).toBeNull();
  });

  it('shows no countdown rather than NaN when the timestamp is unusable', () => {
    expect(reservedUntilMs({ reserved_until: 'not a date' })).toBeNull();
  });
});

describe('checkout uses the fixed read', () => {
  const screen = () => read('src/screens/checkout/CheckoutNative.tsx');

  it('selects through the shared constant', () => {
    expect(screen()).toMatch(/\.select\(LISTING_SUMMARY_COLUMNS\)/);
  });

  it('no longer names the non-existent column anywhere', () => {
    expect(screen()).not.toMatch(/cover_image_url/);
  });

  it('keeps the summary failure off the payment path', () => {
    // The read must not throw or clear payment state when it fails; it returns.
    expect(screen()).toMatch(/listing summary unavailable/);
  });
});

describe('whole-listing pricing label', () => {
  it('reads the ticket count from the row and labels it as a count, never a per-ticket price', () => {
    expect(mapListingSummary({ quantity: 2 }, { eventName: 'e', venue: 'v' }).quantity).toBe(2);
    expect(ticketCountLabel(2)).toBe('2 tickets');
    expect(ticketCountLabel(1)).toBe('1 ticket');
  });

  it('shows no count when the quantity is unknown or invalid', () => {
    expect(mapListingSummary({ quantity: 0 }, { eventName: 'e', venue: 'v' }).quantity).toBeNull();
    expect(mapListingSummary({ quantity: null }, { eventName: 'e', venue: 'v' }).quantity).toBeNull();
    expect(ticketCountLabel(null)).toBeNull();
  });
});
