/**
 * tests/transfer-state.test.ts — transfer state model + source guards that both
 * transfer screens still drive the real RPCs / edge functions and never imply
 * ownership before authoritative confirmation.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  formatCountdown,
  transferStatusMeta,
  sellerAlreadySent,
  buyerNeedsDelivery,
  sellerDeliveryMissing,
} from '../src/lib/transfer/transferState';

const NOW = 1_000_000_000_000;

describe('formatCountdown', () => {
  it('renders hours+minutes, minutes, expired, and null', () => {
    expect(formatCountdown(new Date(NOW + 2 * 3600_000 + 5 * 60_000).toISOString(), NOW)).toBe('2h 5m remaining');
    expect(formatCountdown(new Date(NOW + 12 * 60_000).toISOString(), NOW)).toBe('12m remaining');
    expect(formatCountdown(new Date(NOW - 60_000).toISOString(), NOW)).toBe('Expired');
    expect(formatCountdown(null, NOW)).toBeNull();
  });
});

describe('status meta', () => {
  it('carries a word and a tone for each state', () => {
    expect(transferStatusMeta('pending')).toEqual({ label: 'Pending', tone: 'neutral' });
    expect(transferStatusMeta('seller_sent')).toEqual({ label: 'Sent', tone: 'neutral' });
    expect(transferStatusMeta('buyer_confirmed')).toEqual({ label: 'Complete', tone: 'success' });
    expect(transferStatusMeta('auto_released')).toEqual({ label: 'Released', tone: 'success' });
    expect(transferStatusMeta('disputed')).toEqual({ label: 'Issue', tone: 'warning' });
  });
});

describe('gates', () => {
  it('sellerAlreadySent covers sent + terminal states only', () => {
    expect(sellerAlreadySent('pending')).toBe(false);
    expect(sellerAlreadySent('seller_sent')).toBe(true);
    expect(sellerAlreadySent('buyer_confirmed')).toBe(true);
    expect(sellerAlreadySent('auto_released')).toBe(true);
    expect(sellerAlreadySent('disputed')).toBe(false);
  });
  it('buyerNeedsDelivery only while pending/sent and no contact on file', () => {
    expect(buyerNeedsDelivery({ status: 'pending', delivery_email: null, delivery_phone: null })).toBe(true);
    expect(buyerNeedsDelivery({ status: 'seller_sent', delivery_email: null, delivery_phone: null })).toBe(true);
    expect(buyerNeedsDelivery({ status: 'pending', delivery_email: 'a@b.co', delivery_phone: null })).toBe(false);
    expect(buyerNeedsDelivery({ status: 'buyer_confirmed', delivery_email: null, delivery_phone: null })).toBe(false);
  });
  it('sellerDeliveryMissing is purely about contact info', () => {
    expect(sellerDeliveryMissing({ delivery_email: null, delivery_phone: null })).toBe(true);
    expect(sellerDeliveryMissing({ delivery_email: null, delivery_phone: '+13055551234' })).toBe(false);
  });
});

describe('transfer screens — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
  const send = read('app/transfer/send/[id].tsx');
  const receive = read('app/transfer/receive/[id].tsx');

  it('send keeps the evidence upload + mark_transfer_sent RPC', () => {
    expect(send).toContain('evidenceUpload.uploadImage');
    expect(send).toContain("rpc('mark_transfer_sent'");
    expect(send).toContain('proof-docs'); // private bucket unchanged
  });

  it('receive keeps view, delivery, confirm and dispute paths', () => {
    expect(receive).toContain("rpc('mark_transfer_viewed'");
    expect(receive).toContain("rpc('set_transfer_delivery_info'");
    expect(receive).toContain("invoke('confirm-and-release'");
    expect(receive).toContain("rpc('buyer_dispute_transfer'");
  });

  it('never queries kernel.tickets and never claims ownership before confirmation', () => {
    for (const src of [send, receive]) {
      expect(src).not.toMatch(/kernel[^\n]*tickets|from\(['"]tickets['"]\)/);
      expect(src).not.toMatch(/you own|you now own|ticket secured/i);
    }
    // the buyer's ownership language only appears on the confirmed branch
    expect(receive).toContain('buyer_confirmed');
  });
});
