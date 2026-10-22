/**
 * tests/rc3-refusal-screens.test.ts — RC3 S5: the four write paths map the refusal BEFORE today's copy.
 *
 * Source pins on the shipped screens (comments stripped): each path reads the hint through the one
 * helper, shows `refusal.title` / `refusal.body` with no buttons (so nothing offers "Try again"),
 * returns, and only then falls through to the copy it showed before RC3. The behavioural test for
 * the bid path is in tests/v3-bid-error-copy.test.ts (RC3 block).
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const IMPORT = "from '@/src/lib/moderation/serverRefusal'";
const SHOW = 'Alert.alert(refusal.title, refusal.body);';

describe('RC3 · each write path maps the refusal first, then keeps its own copy', () => {
  it('RS1: PlaceBid — insert error → refusal → else BID_UNCONFIRMED_COPY', () => {
    const src = strip('src/screens/PlaceBidScreen.tsx');
    expect(src).toContain(IMPORT);
    const insert = src.indexOf("from('bids').insert(");
    const map = src.indexOf('readServerRefusal(', insert);
    const show = src.indexOf(SHOW, insert);
    const fallback = src.indexOf('Alert.alert(BID_UNCONFIRMED_COPY.title, BID_UNCONFIRMED_COPY.body)', insert);
    expect(insert).toBeGreaterThan(0);
    expect(map).toBeGreaterThan(insert);
    expect(show).toBeGreaterThan(map);
    expect(fallback).toBeGreaterThan(show);
  });

  it('RS2: ListingDetail.handleBuyNow — reserve_buy_now error → refusal → else the three existing branches', () => {
    const src = strip('src/screens/ListingDetailScreen.tsx');
    expect(src).toContain(IMPORT);
    const rpc = src.indexOf("supabase.rpc('reserve_buy_now'");
    const map = src.indexOf('readServerRefusal(rpcError)', rpc);
    const show = src.indexOf(SHOW, rpc);
    const reserved = src.indexOf("msg.includes('already reserved')", rpc);
    const generic = src.indexOf("Alert.alert('Reservation failed', msg)", rpc);
    expect(rpc).toBeGreaterThan(0);
    expect(map).toBeGreaterThan(rpc);
    expect(show).toBeGreaterThan(map);
    expect(reserved).toBeGreaterThan(show);
    expect(generic).toBeGreaterThan(reserved);
  });

  it('RS3: CreateListing — insert error → refusal (form kept) → else the existing throw', () => {
    const src = strip('src/screens/CreateListingScreen.tsx');
    expect(src).toContain(IMPORT);
    const insert = src.indexOf(".from('listings')\n        .insert(");
    const map = src.indexOf('readServerRefusal(error)', insert);
    const thrown = src.indexOf('throw new Error(error.message)', insert);
    expect(insert).toBeGreaterThan(0);
    expect(map).toBeGreaterThan(insert);
    expect(thrown).toBeGreaterThan(map);
    // The refusal path returns before the form reset: the seller's text stays for revision.
    const ret = src.indexOf('return;', map);
    const reset = src.indexOf("setEventName('')", map);
    expect(ret).toBeLessThan(reset);
  });

  // RETARGETED (CFT-703): the fallback after the refusal used to be "Save failed" with the raw
  // server message; it is now the catalogue mapping's title and body (listingRefusal.ts).
  it('RS4: Edit — update error → refusal → else the mapped "Save failed" copy', () => {
    const src = strip('app/listing/edit/[id].tsx');
    expect(src).toContain(IMPORT);
    const update = src.indexOf(".from('listings')\n        .update(");
    const map = src.indexOf('readServerRefusal(error)', update);
    const show = src.indexOf(SHOW, update);
    const fallback = src.indexOf('Alert.alert(failure.title, failure.body)', update);
    expect(src).not.toContain("Alert.alert('Save failed', error.message)");
    expect(update).toBeGreaterThan(0);
    expect(map).toBeGreaterThan(update);
    expect(show).toBeGreaterThan(map);
    expect(fallback).toBeGreaterThan(show);
  });

  it('RS5: no mapped refusal is shown with a button list — the OK-only dialog offers no "Try again"', () => {
    for (const rel of ['src/screens/PlaceBidScreen.tsx', 'src/screens/ListingDetailScreen.tsx', 'src/screens/CreateListingScreen.tsx', 'app/listing/edit/[id].tsx']) {
      const src = strip(rel);
      expect(src, rel).not.toMatch(/Alert\.alert\(refusal\.title, refusal\.body, \[/);
      expect(src, rel).not.toMatch(/refusal[\s\S]{0,200}Try again/);
    }
  });
});
