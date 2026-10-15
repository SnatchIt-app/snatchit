/**
 * N5 — a listing whose ticket proof the owner waived says so BEFORE purchase, and never reads as reviewed.
 *
 * Migration 156 (A) records an owner proof waiver on the admin's four listings: proof_waived_at/by/reason,
 * proof_status left at 'pending_review' (a waived listing is never 'approved'). Owner wording, via A and
 * matching web: "Ticket proof waived by Snatch It". It must show on the listing, on the bid screen and on
 * the checkout face where the buyer pays. "Ownership proof: Reviewed by Snatch It" stays reserved for
 * proof_status = 'approved'. Seller-level "Verified seller" is acceptable; a bare "Verified" next to
 * ticket information is not. Pure rules + source contracts. Not device evidence.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { LISTING_SUMMARY_COLUMNS, mapListingSummary } from '../src/lib/checkout/listingSummary';
import { PROOF_REVIEWED_ROW, PROOF_WAIVED_NOTICE, proofIsReviewed, proofIsWaived } from '../src/lib/listing/proofPresentation';

const ROOT = resolve(__dirname, '..');
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => strip(readFileSync(join(ROOT, p), 'utf8'));
const WAIVED_AT = '2026-10-15T04:00:00Z';

describe('N5 — the rules', () => {
  it('P1: the words', () => {
    expect(PROOF_WAIVED_NOTICE).toBe('Ticket proof waived by Snatch It');
    expect(PROOF_REVIEWED_ROW).toEqual({ label: 'Ownership proof', value: 'Reviewed by Snatch It' });
  });
  it('P2: reviewed ONLY when approved — a waiver, a pending or a rejected proof is never "reviewed"', () => {
    expect(proofIsReviewed({ proof_status: 'approved' })).toBe(true);
    expect(proofIsReviewed({ proof_status: 'pending_review', proof_waived_at: WAIVED_AT })).toBe(false);
    expect(proofIsReviewed({ proof_status: 'pending_review' })).toBe(false);
    expect(proofIsReviewed({ proof_status: 'rejected' })).toBe(false);
    expect(proofIsReviewed(null)).toBe(false);
  });
  it('P3: waived when the waiver is recorded and the proof was not approved; rows without the column are not waived', () => {
    expect(proofIsWaived({ proof_status: 'pending_review', proof_waived_at: WAIVED_AT })).toBe(true);
    expect(proofIsWaived({ proof_status: 'pending_review', proof_waived_at: null })).toBe(false);
    expect(proofIsWaived({ proof_status: 'pending_review' })).toBe(false);          // a row read before 156
    expect(proofIsWaived({ proof_status: 'pending_review', proof_waived_at: '' })).toBe(false);
    expect(proofIsWaived({ proof_status: 'approved', proof_waived_at: WAIVED_AT })).toBe(false);
    expect(proofIsWaived(undefined)).toBe(false);
  });
});

describe('N5 — listing detail', () => {
  const d = read('src/screens/ListingDetailScreen.tsx');
  it('P4: the reviewed row is gated on proofIsReviewed and uses the shared words', () => {
    expect(d).toMatch(/if \(proofIsReviewed\(listing\)\) \{\s*detailRows\.push\(\{ \.\.\.PROOF_REVIEWED_ROW \}\);/);
    expect(d).not.toContain("'Reviewed by Snatch It'");
  });
  it('P5: the waiver notice sits right under the price panel, before the facts', () => {
    const panel = d.indexOf('<TransactionPanel');
    const notice = d.indexOf('{proofIsWaived(listing) ? (');
    const facts = d.indexOf('<View style={s.facts}>');
    expect(panel).toBeGreaterThan(-1);
    expect(notice).toBeGreaterThan(panel);
    expect(facts).toBeGreaterThan(notice);
    expect(d.slice(notice, facts)).toContain('{PROOF_WAIVED_NOTICE}');
  });
});

describe('N5 — bid screen', () => {
  const b = read('src/screens/PlaceBidScreen.tsx');
  it('P6: the bid read carries the proof facts and the screen states the waiver above the bid', () => {
    expect(b).toMatch(/\.select\('[^']*proof_status, proof_waived_at[^']*'\)/);
    expect(b).toMatch(/\{proofIsWaived\(listing\) \? \([\s\S]{0,300}\{PROOF_WAIVED_NOTICE\}/);
  });
});

describe('N5 — checkout (the face where the buyer pays)', () => {
  it('P7: the summary read asks for the proof facts and maps them to proofWaived', () => {
    expect(LISTING_SUMMARY_COLUMNS).toContain('proof_status');
    expect(LISTING_SUMMARY_COLUMNS).toContain('proof_waived_at');
    const fb = { eventName: 'E', venue: 'V' };
    expect(mapListingSummary({ proof_status: 'pending_review', proof_waived_at: WAIVED_AT }, fb).proofWaived).toBe(true);
    expect(mapListingSummary({ proof_status: 'pending_review' }, fb).proofWaived).toBe(false);
    expect(mapListingSummary(null, fb).proofWaived).toBe(false);
  });
  it('P8: the pay face renders the notice under the order identity; the identity carries the flag', () => {
    const v = read('src/screens/checkout/CheckoutView.tsx');
    expect(v).toMatch(/proofWaived\?: boolean;/);
    const first = v.indexOf('<OrderIdentity');
    const notice = v.indexOf('{identity.proofWaived ? (');
    expect(notice).toBeGreaterThan(first);
    expect(v.slice(notice, notice + 400)).toContain('{PROOF_WAIVED_NOTICE}');
    const n = read('src/screens/checkout/CheckoutNative.tsx');
    expect(n).toContain('proofWaived: display?.proofWaived ?? false,');
  });
});

describe('N5 — no bare "Verified" next to ticket information', () => {
  // Every buyer-facing listing surface: cards, detail, bid, checkout. Phone/account screens are elsewhere.
  const roots = ['src/components/discovery', 'src/components/listing', 'src/screens/ListingDetailScreen.tsx',
    'src/screens/PlaceBidScreen.tsx', 'src/screens/checkout', 'src/lib/listing', 'src/lib/checkout'];
  const files: string[] = [];
  const walk = (p: string) => {
    const abs = join(ROOT, p);
    if (statSync(abs).isDirectory()) for (const e of readdirSync(abs)) walk(join(p, e));
    else if (/\.(ts|tsx)$/.test(p)) files.push(p);
  };
  roots.forEach(walk);
  it('P9: the only "Verified" on these surfaces is the seller-level "Verified seller"', () => {
    const offenders: string[] = [];
    for (const f of files) {
      const src = read(f);
      for (const m of src.matchAll(/['"`][^'"`\n]*\bVerified\b[^'"`\n]*['"`]/g)) {
        if (!/Verified seller/.test(m[0])) offenders.push(`${f}: ${m[0]}`);
      }
    }
    expect(files.length).toBeGreaterThan(20);
    expect(offenders).toEqual([]);
  });
});
