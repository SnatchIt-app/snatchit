/**
 * tests/premium-auction-live.test.ts — batch 4: truthful progress copy and
 * client-side auction presentation within the existing backend rules.
 *
 * CFT-306 (real steps named), CFT-501 (client side: "Confirming result" at
 * zero, reads only), CFT-502 (in-place amount change), CFT-504 (connection
 * health visible), CFT-505 (My Bids urgency and ending-soon order). Nothing
 * here changes a bid increment or an auction's timing: F10 is undecided.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { bidPresentation, compareBidRows, ENDING_SOON_MS, endingSoonLabel, type BidRowInput } from '@/src/lib/bids/bidState';
import { listingStatus } from '@/src/lib/listing/detailState';
import {
  CONNECTION_NOTICE, connectionNotice, RESULT_POLL_MAX_ATTEMPTS, resultPollDelayMs, shouldPollForResult,
} from '@/src/lib/listing/liveState';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const ME = 'me';
const now = 1_700_000_000_000;
const row = (over: Omit<Partial<BidRowInput>, 'listing'> & { listing?: Partial<NonNullable<BidRowInput['listing']>> }): BidRowInput => ({
  amount: 50,
  ...over,
  listing: { status: 'active', auction_status: 'active', ends_at: new Date(now + 3 * 3600_000).toISOString(), current_bid: 50, winner_user_id: null, ...(over.listing ?? {}) },
} as BidRowInput);

describe('CFT-501 client side — the clock ran out, the server has not spoken', () => {
  const base = () => ({
    listing: { id: 'l1', status: 'active', auction_status: 'active', seller_id: 's', reserved_by: null, winner_user_id: null, bid_count: 1 },
    userId: 'u', clockEnded: true, reservationActive: false, finalizing: false, reserving: false,
    transfer: { id: null, status: null, buyerId: null }, isHighestBidder: true, hasBid: true, buyNowAllIn: null,
  });

  it('says "Confirming result", never "ended", never a winner', () => {
    const st = listingStatus(base() as any);
    expect(st?.kind).toBe('confirming_result');
    expect(st?.label).toBe('Confirming result');
    expect(`${st?.label} ${st?.detail}`).not.toMatch(/you won|ended|winner/i);
  });

  it('the client-triggered finalize (existing) also reads as confirming, not closed', () => {
    const st = listingStatus({ ...base(), finalizing: true } as any);
    expect(st?.kind).toBe('finalizing');
    expect(st?.label).toBe('Confirming result');
  });

  it('polls only while the device clock ran out and the server still says active', () => {
    expect(shouldPollForResult({ clockEnded: true, auctionStatus: 'active', sold: false })).toBe(true);
    expect(shouldPollForResult({ clockEnded: true, auctionStatus: undefined, sold: false })).toBe(true);
    expect(shouldPollForResult({ clockEnded: false, auctionStatus: 'active', sold: false })).toBe(false);
    expect(shouldPollForResult({ clockEnded: true, auctionStatus: 'ended', sold: false })).toBe(false);
    expect(shouldPollForResult({ clockEnded: true, auctionStatus: 'active', sold: true })).toBe(false);
  });

  it('the poll schedule is short, bounded, and stops', () => {
    expect(resultPollDelayMs(1)).toBe(3_000);
    expect(resultPollDelayMs(2)).toBe(10_000);
    expect(resultPollDelayMs(RESULT_POLL_MAX_ATTEMPTS)).toBe(10_000);
    expect(resultPollDelayMs(RESULT_POLL_MAX_ATTEMPTS + 1)).toBeNull();
    expect(resultPollDelayMs(0)).toBeNull();
  });

  it('the screen polls with a SELECT only — no new finalize call, timing untouched', () => {
    const screen = stripComments(read('src/screens/ListingDetailScreen.tsx'));
    const poll = screen.slice(screen.indexOf('const pollAttemptRef'), screen.indexOf('}, [ended, auctionStatusNow, listingStatusNow, id]);'));
    expect(poll).toContain(".select('auction_status, status, winner_user_id, winning_bid_amount, current_bid, bid_count')");
    expect(poll).not.toContain('finalize_auction');
    expect(poll).not.toContain('.rpc(');
    expect(poll).toContain('resultPollDelayMs(++pollAttemptRef.current)');
    // the one finalize call the screen already had is still exactly one
    expect(screen.split("rpc('finalize_auction'").length - 1).toBe(1);
  });
});

describe('CFT-504 — a frozen screen must not look live', () => {
  it('the notice shows only while reconnecting on a live auction', () => {
    expect(connectionNotice('reconnecting', 'auction_only')).toBe(CONNECTION_NOTICE);
    expect(connectionNotice('reconnecting', 'auction_and_buy_now')).toBe(CONNECTION_NOTICE);
    expect(connectionNotice('reconnecting', 'closed')).toBeNull();
    expect(connectionNotice('live', 'auction_only')).toBeNull();
    expect(connectionNotice('connecting', 'auction_only')).toBeNull();
    expect(CONNECTION_NOTICE).toBe('Reconnecting — bid status may be delayed');
  });

  it('the realtime hook exposes connection health and keeps the reconnect catch-up', () => {
    const hook = stripComments(read('src/hooks/useListingRealtime.ts'));
    expect(hook).toContain("useState<RealtimeConnection>('connecting')");
    expect(hook).toMatch(/if \(status === 'SUBSCRIBED'\) \{\s*setConnection\('live'\);/);
    expect(hook).toMatch(/if \(status === 'CHANNEL_ERROR'\) \{\s*setConnection\('reconnecting'\);/);
    expect(hook).toMatch(/if \(status === 'TIMED_OUT'\) \{\s*setConnection\('reconnecting'\);/);
    expect(hook).toContain("if (prev === 'CHANNEL_ERROR' || prev === 'TIMED_OUT') {");
    expect(hook).toContain('connection,');
  });

  it('the listing screen renders the notice as an alert region', () => {
    const screen = stripComments(read('src/screens/ListingDetailScreen.tsx'));
    expect(screen).toContain('const liveNotice = connectionNotice(rt.connection, state.mode);');
    expect(screen).toMatch(/\{liveNotice \? \(\s*<View style=\{s\.liveNotice\} accessibilityRole="alert" accessibilityLiveRegion="polite">/);
  });
});

describe('CFT-502 — the amount moves in place', () => {
  it('the panel pulses the bid amount on change and the hook respects Reduce Motion', () => {
    const panel = stripComments(read('src/components/listing/TransactionPanel.tsx'));
    expect(panel).toContain('const pulse = usePulseOnChange(currentAllIn);');
    expect(panel).toContain('<Animated.View style={{ opacity: pulse.opacity }}>');
    const hook = stripComments(read('src/hooks/usePulseOnChange.ts'));
    expect(hook).toContain('if (first || reduceMotion) return;');
    expect(hook).toContain('useNativeDriver: true');
    expect(hook).toContain('opacity.setValue(PULSE_DIP);');
  });

  it('the minimum next bid still derives from the live current bid and the unchanged increment', () => {
    const screen = stripComments(read('src/screens/ListingDetailScreen.tsx'));
    expect(screen).toContain('const nextBidAllIn = allInFromDollars(currentHighest + APP_CONFIG.MIN_BID_INCREMENT);');
  });
});

describe('CFT-505 — My Bids: action first, then the auction closing soonest', () => {
  it('flags ending soon only for a live auction the user is in, within the hour', () => {
    const soon = row({ listing: { ends_at: new Date(now + ENDING_SOON_MS - 1).toISOString() } });
    const later = row({ listing: { ends_at: new Date(now + ENDING_SOON_MS + 60_000).toISOString() } });
    expect(bidPresentation(soon, ME, now).endingSoon).toBe(true);
    expect(bidPresentation(later, ME, now).endingSoon).toBe(false);
    // ended / won / purchase rows are never "ending soon"
    const won = row({ listing: { auction_status: 'ended', winner_user_id: ME, ends_at: new Date(now - 1).toISOString() } });
    expect(bidPresentation(won, ME, now).endingSoon).toBe(false);
    expect(bidPresentation(row({ purchaseTransferStatus: 'seller_sent' } as any), ME, now).endingSoon).toBe(false);
  });

  it('within one urgency, the auction closing first sorts first; urgency still wins across', () => {
    const outbidSoon = bidPresentation(row({ amount: 40, listing: { current_bid: 70, ends_at: new Date(now + 10 * 60_000).toISOString() } }), ME, now);
    const outbidLater = bidPresentation(row({ amount: 40, listing: { current_bid: 70, ends_at: new Date(now + 5 * 3600_000).toISOString() } }), ME, now);
    const winningSoon = bidPresentation(row({ amount: 90, listing: { current_bid: 90, ends_at: new Date(now + 60_000).toISOString() } }), ME, now);
    const won = bidPresentation(row({ listing: { auction_status: 'ended', winner_user_id: ME } }), ME, now);
    const sorted = [outbidLater, winningSoon, outbidSoon, won].sort(compareBidRows).map((p) => p.status + (p.endingSoon ? '+soon' : ''));
    expect(sorted).toEqual(['won', 'outbid+soon', 'outbid', 'winning+soon']);
  });

  it('the label is minutes, never seconds, and says "under a minute" at the end', () => {
    expect(endingSoonLabel(now + 42 * 60_000 + 30_000, now)).toBe('Ends in 42m');
    expect(endingSoonLabel(now + 30_000, now)).toBe('Ends in under a minute');
  });

  it('the Bids tab sorts with compareBidRows and shows the urgency line', () => {
    const tab = stripComments(read('app/(tabs)/bids.tsx'));
    expect(tab).toContain('compareBidRows(bidPresentation(toInput(x), userId, now), bidPresentation(toInput(y), userId, now))');
    expect(tab).toContain('urgencyLabel={p.endingSoon ? endingSoonLabel(p.endsAtMs) : null}');
    const card = stripComments(read('src/components/bids/BidCard.tsx'));
    expect(card).toContain('urgencyLabel?: string | null;');
    expect(card).toContain("`${urgencyLabel ? `${urgencyLabel}. ` : ''}`");
  });
});

describe('CFT-306 — progress copy names real states (payControl, for A)', () => {
  it('the screen sets finalizing only around finalizePurchase, and both calls are covered', () => {
    const screen = stripComments(read('src/screens/checkout/CheckoutNative.tsx'));
    expect(screen.split('setFinalizing(true)').length - 1).toBe(2);
    expect(screen.split('setFinalizing(false)').length - 1).toBe(2);
    expect(screen.split('await finalizePurchase(').length - 1).toBe(2);
    expect(screen).toMatch(/setFinalizing\(true\);\s*let result[^;]*;\s*try \{\s*result = await finalizePurchase\(/);
    expect(screen).toMatch(/const pay = payControl\(\{\s*authLoading,\s*paymentLoading,\s*confirming,\s*finalizing,\s*checking,/);
  });

  it('nothing else in checkout changed: handlers, decision, gated files', () => {
    const screen = read('src/screens/checkout/CheckoutNative.tsx');
    for (const marker of ["pay.action === 'pay' ? payHandler", "pay.action === 'retry' ? () => setupPaymentRef.current?.()", "pay.action === 'back' ? () => router.back()"]) {
      expect(screen).toContain(marker);
    }
  });

  it('no auction timing or increment semantics moved (F10 undecided)', () => {
    for (const rel of ['src/lib/bids/bidState.ts', 'src/lib/listing/liveState.ts', 'src/lib/listing/detailState.ts', 'src/hooks/useListingRealtime.ts']) {
      const code = stripComments(read(rel));
      expect(code, rel).not.toMatch(/MIN_BID_INCREMENT|finalize_auction|ends_at\s*=|extend/i);
    }
  });
});
