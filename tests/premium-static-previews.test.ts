/**
 * tests/premium-static-previews.test.ts — the static preview page cannot drift
 * from the source copy it claims to show.
 *
 * docs/product-v2/previews/premium-static-previews.html is hand-composed, and
 * labelled as such. Every user-facing string on it is pinned here to the module
 * that owns it, so a copy change in code without a page update fails the build.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { bidOutcomeCopy } from '@/src/lib/bid/bidEntry';
import { notHeldCopy, refundViewModel } from '@/src/lib/checkout/holdState';
import { payControl } from '@/src/lib/checkout/payControl';
import { UNSAVED_COPY } from '@/src/lib/nav/unsavedChanges';
import { REGISTRATION_REMEDY } from '@/src/lib/push/registration';
import { RETURN_PROMPT, returnPromptBody } from '@/src/lib/transfer/providerHandoff';
import { transferStatusCopy, transferStatusMeta } from '@/src/lib/transfer/transferState';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const html = read('docs/product-v2/previews/premium-static-previews.html')
  // the page is HTML: apostrophes and ampersands may be entities
  .replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, '&');

describe('static previews are labelled and pinned to source', () => {
  it('says what it is, on the page and on every frame', () => {
    expect(html).toContain('Static preview — not a device render');
    expect(html).toContain('Native visual and runtime acceptance');
    expect((html.match(/class="tag">static</g) ?? []).length).toBeGreaterThanOrEqual(12);
  });

  it('pending labels match the screens', () => {
    for (const rel of ['src/screens/PlaceBidScreen.tsx', 'src/screens/ListingDetailScreen.tsx', 'app/transfer/receive/[id].tsx', 'app/settings/preferences.tsx', 'app/report/[type]/[id].tsx']) {
      const labels = [...read(rel).matchAll(/pendingLabel="([^"]+)"/g)].map((m) => m[1]);
      expect(labels.length, rel).toBeGreaterThan(0);
      for (const l of labels) expect(html, `${rel}: ${l}`).toContain(l);
    }
  });

  it('bid outcomes match bidOutcomeCopy', () => {
    for (const [o, fresh] of [['leading', 80], ['outbid', 90], ['accepted', null]] as const) {
      const c = bidOutcomeCopy(o, 80, fresh);
      expect(html).toContain(c.title);
      expect(html).toContain(c.body);
    }
  });

  it('checkout hold, pay and refund states match holdState/payControl', () => {
    for (const r of ['released_by_us', 'ran_out', 'unknown'] as const) {
      const c = notHeldCopy(r);
      expect(html).toContain(c.title);
      expect(html).toContain(c.body);
    }
    for (const v of [refundViewModel('refund_unconfirmed', null), refundViewModel('partially_refunded', 2000), refundViewModel('refunded', 11000)]) {
      expect(html).toContain(v.kicker);
      expect(html).toContain(v.title);
      expect(html).toContain(v.body);
      expect(html).toContain(v.cta.label);
    }
    expect(html).not.toContain('No purchase was made');
    expect(html).not.toContain("Check Tickets for this order's current status.");
    const base = { authLoading: false, paymentLoading: false, confirming: false, paymentReady: false, paymentError: false, formattedTotal: '$88' };
    expect(html).toContain(payControl({ ...base, confirming: true }).label);          // Confirming payment
    expect(html).toContain(payControl({ ...base, finalizing: true }).label);          // Finalizing your order
    expect(html).toContain(payControl({ ...base, checking: true }).label);            // Checking your payment
    expect(html).toContain(payControl({ ...base, paymentReady: true, reservationMsLeft: 5_000 }).label); // Checking your hold
    expect(html).toContain(payControl({ ...base, paymentReady: true }).label);        // Pay $88
    expect(html).toContain(payControl({ ...base, holdLost: true }).label);            // Back to listing
  });

  it('checkout price-change and unreachable copy match the screen', () => {
    const checkout = read('src/screens/checkout/CheckoutNative.tsx');
    expect(checkout).toContain('The total changed');
    expect(html).toContain('The total changed');
    expect(checkout).toContain("We couldn't confirm your payment yet");
    expect(html).toContain("We couldn't confirm your payment yet");
    expect(checkout).toContain("Your last attempt may or may not have gone through. Please don't pay again. We'll keep checking; you can also check now.");
    expect(html).toContain("Your last attempt may or may not have gone through. Please don't pay again. We'll keep checking; you can also check now.");
  });

  it('dialogs match UNSAVED_COPY, notices match the settings routes', () => {
    for (const c of Object.values(UNSAVED_COPY)) {
      for (const s of [c.title, c.message, c.stayLabel, c.leaveLabel]) expect(html).toContain(s);
    }
    const prefs = read('app/settings/preferences.tsx');
    const notice = prefs.match(/const SCENE_ROLLBACK_NOTICE =\s*\n?\s*"([^"]+)"/)?.[1];
    expect(notice).toBeTruthy();
    expect(html).toContain(notice!);
    expect(read('app/settings/notifications.tsx')).toContain("Couldn't save ${label}. It's back to ${prev ? 'on' : 'off'}. Check your connection and try again.");
    expect(html).toContain("Couldn't save Outbid alerts. It's back to on. Check your connection and try again.");
  });

  it('batch 3: transfer vocabulary, the return question, and the registration remedy match source', () => {
    expect(html).toContain(transferStatusMeta('seller_sent').label);
    for (const [st, role] of [['seller_sent', 'buyer'], ['buyer_confirmed', 'buyer'], ['auto_released', 'buyer'], ['seller_sent', 'seller']] as const) {
      const c = transferStatusCopy(st, role);
      expect(html, `${st}/${role}`).toContain(c.title);
      expect(html, `${st}/${role}`).toContain(c.body);
    }
    expect(html).toContain(RETURN_PROMPT.title);
    expect(html).toContain(returnPromptBody('Ticketmaster'));
    for (const b of [RETURN_PROMPT.here, RETURN_PROMPT.notYet, RETURN_PROMPT.problem]) expect(html).toContain(b);
    expect(html).toContain(REGISTRATION_REMEDY.bound_to_other!);
    expect(html).toContain('Open Ticketmaster');
  });
});
