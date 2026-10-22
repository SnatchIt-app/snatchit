/**
 * tests/cft703-listing-refusals.test.ts — listing delete, cancel and edit never show server text.
 *
 * CFT-703, from A's refusal catalogue (sprint-control/SERVER_REFUSAL_CATALOGUE_C_20261021.md §1-3,
 * §6-8). Each of the three actions showed `error.message` raw: foreign-key and check-constraint
 * strings that name tables, constraints and the hiding feature. The mapping now lives in one pure
 * module, src/lib/listing/listingRefusal.ts, keyed hint → SQLSTATE → exact message, with the
 * action's generic line for anything unmatched.
 *
 * Part 1 drives the pure mapping with the catalogue's VERBATIM messages, one case per catalogue ID.
 * Part 2 pins each handler's body (comments stripped, anchored to the handler function, not the
 * file) to the mapping, and runs the same check on a mutated copy that reintroduces `error.message`
 * — the negative control that proves the contract can fail.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  LISTING_REFUSAL_COPY as C,
  deleteGateCopy,
  listingCancelFailure,
  listingDeleteFailure,
  listingDeleteNoRows,
  listingEditFailure,
} from '@/src/lib/listing/listingRefusal';
import { REFUSAL_COPY, prohibitedContentBody } from '@/src/lib/moderation/serverRefusal';
import { REPO_ROOT } from './helpers/nav-stack-harness';

const pg = (code: string, message: string, extra: Record<string, unknown> = {}) =>
  ({ code, message, details: null, hint: null, ...extra });

const FK = (constraint: string, table: string) =>
  pg('23503', `update or delete on table "listings" violates foreign key constraint "${constraint}" on table "${table}"`,
    { details: `Key is still referenced from table "${table}".` });
const CHECK = (constraint: string) =>
  pg('23514', `new row for relation "listings" violates check constraint "${constraint}"`);
const NETWORK = { message: 'TypeError: Network request failed', details: '', hint: '', code: '' };

describe('CFT-703 · the copy', () => {
  it('LR0: the catalogue sentences are held verbatim', () => {
    expect(C.delete.checkout).toBe("This listing has had checkout activity, so it can't be deleted. You can cancel it instead.");
    expect(C.delete.hidden).toBe("This listing is no longer shown to buyers and can't be deleted. Contact support@snatchitapp.com if you need it removed.");
    expect(C.delete.sold).toBe("This listing has sold, so it can't be deleted.");
    expect(C.delete.alreadyRemoved).toBe('This listing was already removed.');
    expect(C.cancel.sold).toBe("This listing has already sold, so it can't be cancelled.");
    expect(C.cancel.gone).toBe('This listing is no longer available.');
    expect(C.edit.eventNameLength).toBe('Event name can be up to 120 characters.');
    expect(C.edit.venueLength).toBe('Venue can be up to 120 characters.');
    expect(C.edit.restrictionsLength).toBe('Restrictions can be up to 500 characters.');
    expect(C.network).toBe('Check your connection and try again.');
    expect(C.signIn).toBe('Please sign in again.');
  });
});

describe('CFT-703 · §1 delete', () => {
  it('DEL-1: payments_listing_id_fkey → the checkout-activity sentence', () => {
    const f = listingDeleteFailure(FK('payments_listing_id_fkey', 'payments'));
    expect(f).toMatchObject({ id: 'DEL-1', title: C.delete.title, body: C.delete.checkout });
  });
  it('DEL-2: listing_visibility_listing_id_fkey → the hidden sentence', () => {
    const f = listingDeleteFailure(FK('listing_visibility_listing_id_fkey', 'listing_visibility'));
    expect(f).toMatchObject({ id: 'DEL-2', body: C.delete.hidden });
  });
  it('DEL-3: transfers_listing_id_fkey → the sold sentence, with a refresh (the screen was stale)', () => {
    const f = listingDeleteFailure(FK('transfers_listing_id_fkey', 'transfers'));
    expect(f).toMatchObject({ id: 'DEL-3', body: C.delete.sold, refresh: true });
  });
  it('DEL-4: webhook_retries_listing_id_fkey → the DEL-1 sentence', () => {
    const f = listingDeleteFailure(FK('webhook_retries_listing_id_fkey', 'webhook_retries'));
    expect(f).toMatchObject({ id: 'DEL-4', body: C.delete.checkout });
  });
  it('DEL-1 (fallback): any other 23503 → the DEL-1 sentence, never the FK text', () => {
    const f = listingDeleteFailure(FK('some_future_listing_id_fkey', 'some_future_table'));
    expect(f.body).toBe(C.delete.checkout);
    expect(listingDeleteFailure(pg('23503', '')).body).toBe(C.delete.checkout);
  });
  it('DEL-5: a delete that removed 0 rows is a failure that refreshes, never "Deleted"', () => {
    const f = listingDeleteNoRows();
    expect(f).toMatchObject({ id: 'DEL-5', title: C.delete.title, body: 'This listing was already removed.', refresh: true });
  });
  it('§6: a network failure → the connection line; anything else → the generic line', () => {
    expect(listingDeleteFailure(NETWORK)).toMatchObject({ id: 'network', body: C.network });
    expect(listingDeleteFailure(pg('XX000', 'internal error at relation "listings"'))).toMatchObject({ id: 'generic', body: C.delete.generic });
    expect(listingDeleteFailure(null).body).toBe(C.delete.generic);
    expect(listingDeleteFailure('boom').body).toBe(C.delete.generic);
  });
  it('the code is the key: the FK sentence with a different SQLSTATE is not DEL-1', () => {
    const wrongCode = { ...FK('payments_listing_id_fkey', 'payments'), code: 'P0001' };
    expect(listingDeleteFailure(wrongCode).body).toBe(C.delete.generic);
  });
});

describe('CFT-703 · §2 cancel', () => {
  it('CAN-1: the exact sold sentence → calm copy and a refresh', () => {
    const f = listingCancelFailure(pg('P0001', 'This listing has already been sold and cannot be cancelled.'));
    expect(f).toMatchObject({ id: 'CAN-1', title: C.cancel.title, body: C.cancel.sold, refresh: true });
  });
  it('CAN-2: the exact not-found sentence → calm copy and a refresh', () => {
    const f = listingCancelFailure(pg('P0001', 'Listing not found.'));
    expect(f).toMatchObject({ id: 'CAN-2', body: C.cancel.gone, refresh: true });
  });
  it('CAN-3: a direct-only refusal → the generic line (task scope: CAN-1, CAN-2, CAN-4 and 42501 only)', () => {
    expect(listingCancelFailure(pg('P0001', 'You can only cancel your own listings.'))).toMatchObject({ id: 'generic', body: C.cancel.generic });
  });
  it('CAN-4: the caller sentence → "Please sign in again."', () => {
    const f = listingCancelFailure(pg('P0001', 'Unable to identify caller. Ensure the request is authenticated.'));
    expect(f).toMatchObject({ id: 'CAN-4', body: C.signIn });
  });
  it('CAN-5: 42501 → "Please sign in again."', () => {
    const f = listingCancelFailure(pg('42501', 'permission denied for function cancel_listing'));
    expect(f).toMatchObject({ id: 'CAN-5', body: C.signIn });
  });
  it('the match is exact: a reworded or extended sentence falls to the generic line', () => {
    expect(listingCancelFailure(pg('P0001', 'Listing not found. (id 123)')).body).toBe(C.cancel.generic);
    expect(listingCancelFailure(pg('P0001', 'listing not found.')).body).toBe(C.cancel.generic);
  });
  it('§6: network → connection line; unmatched → generic', () => {
    expect(listingCancelFailure(NETWORK).body).toBe(C.network);
    expect(listingCancelFailure(pg('P0001', 'Something else entirely')).body).toBe(C.cancel.generic);
  });
});

describe('CFT-703 · §3 edit', () => {
  it('EDT-1: PROHIBITED_CONTENT hint → the K2 sentence (via readServerRefusal)', () => {
    const f = listingEditFailure(pg('P0001',
      'Listings can\'t mention "cash". Please revise your event name, venue, or restrictions and try again.',
      { hint: 'PROHIBITED_CONTENT', details: 'cash' }));
    expect(f).toMatchObject({ id: 'EDT-1', title: REFUSAL_COPY.PROHIBITED_CONTENT.title, body: prohibitedContentBody('cash') });
  });
  it('EDT-2: ACCOUNT_SUSPENDED hint → the K2 sentence', () => {
    const f = listingEditFailure(pg('P0001', REFUSAL_COPY.ACCOUNT_SUSPENDED.body, { hint: 'ACCOUNT_SUSPENDED' }));
    expect(f).toMatchObject({ id: 'EDT-2', title: REFUSAL_COPY.ACCOUNT_SUSPENDED.title, body: REFUSAL_COPY.ACCOUNT_SUSPENDED.body });
  });
  it('EDT-3: listings_event_name_len_check (and its shadowed duplicate) → the event-name length line', () => {
    expect(listingEditFailure(CHECK('listings_event_name_len_check'))).toMatchObject({ id: 'EDT-3', title: C.edit.title, body: C.edit.eventNameLength });
    expect(listingEditFailure(CHECK('listings_event_name_length')).body).toBe(C.edit.eventNameLength);
  });
  it('EDT-4: listings_venue_len_check → the venue length line', () => {
    expect(listingEditFailure(CHECK('listings_venue_len_check'))).toMatchObject({ id: 'EDT-4', body: C.edit.venueLength });
  });
  it('EDT-5: listings_restrictions_len_check → the restrictions length line', () => {
    expect(listingEditFailure(CHECK('listings_restrictions_len_check'))).toMatchObject({ id: 'EDT-5', body: C.edit.restrictionsLength });
  });
  it('EDT-6: listings_ticket_platform_check (and any other 23514, EDT-17) → generic', () => {
    expect(listingEditFailure(CHECK('listings_ticket_platform_check'))).toMatchObject({ id: 'generic', body: C.edit.generic });
    expect(listingEditFailure(CHECK('listings_starting_bid_check')).body).toBe(C.edit.generic);
  });
  it('EDT-8..16: direct-only P0001 refusals → generic, never their internal text', () => {
    for (const [message, hint] of [
      ['Cannot directly modify auction state columns. Use the appropriate RPC.', null],
      ['Cannot change listing owner.', null],
      ['proof_status can only be changed by Snatch It review', null],
      ['Hidden listing cannot be made live.', 'LISTING_HIDDEN'],
      ["Cannot change a listing's end time or duration after it is created.", 'LISTING_END_TIME_FIXED'],
    ] as const) {
      expect(listingEditFailure(pg('P0001', message, { hint })).body, message).toBe(C.edit.generic);
    }
  });
  it('§6: network → connection line', () => {
    expect(listingEditFailure(NETWORK).body).toBe(C.network);
  });
});

describe('CFT-703 · §6 an expired session reads the same on all three', () => {
  it('PGRST30x / "JWT expired" → "Please sign in again."', () => {
    const jwt = pg('PGRST303', 'JWT expired');
    expect(listingDeleteFailure(jwt).body).toBe(C.signIn);
    expect(listingCancelFailure(jwt).body).toBe(C.signIn);
    expect(listingEditFailure(pg('PGRST301', 'JWT expired')).body).toBe(C.signIn);
  });
});

describe('CFT-703 · §8 no mapped body ever carries an internal name', () => {
  it('none of the copy names a table, a constraint, a column or an SQL word', () => {
    const all = JSON.stringify(C);
    for (const leak of ['listing_visibility', 'payments', 'transfers', 'webhook', '_fkey', '_check', 'relation', 'constraint', 'RPC', 'cancel_listing']) {
      expect(all, leak).not.toContain(leak);
    }
  });
});

describe('My Listings delete gate: the copy is true for the condition it guards', () => {
  it('bids → bids; no bids but not active → why it is not active', () => {
    expect(deleteGateCopy({ bid_count: 2, auction_status: 'ended' }).body).toBe("This listing has bids, so it can't be deleted.");
    expect(deleteGateCopy({ bid_count: 0, auction_status: 'ended' }).body).toBe("This listing has ended, so it can't be deleted.");
    expect(deleteGateCopy({ bid_count: 0, auction_status: 'cancelled' }).body).toBe("This listing was cancelled, so it can't be deleted.");
    expect(deleteGateCopy({ bid_count: 0, auction_status: 'sold' }).body).toBe("This listing has sold, so it can't be deleted.");
    // A no-bid, cancelled listing never says it has bids — the defect this replaces.
    expect(deleteGateCopy({ bid_count: 0, auction_status: 'cancelled' }).body).not.toMatch(/bids/);
    expect(deleteGateCopy({ bid_count: 0, auction_status: 'ended' }).title).toBe('Cannot delete');
  });
});

// ── Part 2: source contracts, anchored to each handler's own body ─────────────────────────────

const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (rel: string) => stripComments(readFileSync(join(REPO_ROOT, rel), 'utf8'));

/** The `{ … }` body of `<head>` in `src`, by brace matching. Throws if the handler is gone. */
function bodyOf(src: string, head: string): string {
  const at = src.indexOf(head);
  if (at < 0) throw new Error(`handler not found: ${head}`);
  const open = src.indexOf('{', at + head.length);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}' && --depth === 0) return src.slice(open, i + 1);
  }
  throw new Error(`unbalanced body: ${head}`);
}

/**
 * What is wrong with one handler, or [] when it holds: it calls the mapping, shows the mapping's
 * title and body, logs the raw error, and nowhere reads `error.message` (or `error?.message`).
 */
function violations(body: string, mapper: string): string[] {
  const out: string[] = [];
  if (!body.includes(`${mapper}(`)) out.push(`does not call ${mapper}`);
  if (!/Alert\.alert\(\s*\w+\.title,\s*\w+\.body/.test(body)) out.push('does not show the mapped title/body');
  if (!body.includes('console.warn(')) out.push('does not log the raw error');
  if (/\b\w*[eE]rror\??\.message\b/.test(body)) out.push('reads error.message');
  return out;
}

/** The negative control: the same handler with the raw text reintroduced into its alert. */
const reintroduceRaw = (body: string, title: string) =>
  body.replace(/Alert\.alert\(\s*(\w+)\.title,\s*\1\.body/, `Alert.alert('${title}', error.message`);

const HANDLERS = [
  { file: 'app/my-listings.tsx', head: 'async function performDelete(', mapper: 'listingDeleteFailure', title: 'Delete failed' },
  { file: 'app/my-listings.tsx', head: 'async function performCancel(', mapper: 'listingCancelFailure', title: 'Cancel failed' },
  { file: 'src/screens/ListingDetailScreen.tsx', head: 'async function handleSellerDelete(', mapper: 'listingDeleteFailure', title: 'Delete failed' },
  { file: 'src/screens/ListingDetailScreen.tsx', head: 'async function handleSellerCancel(', mapper: 'listingCancelFailure', title: 'Cancel failed' },
  { file: 'app/listing/edit/[id].tsx', head: 'async function handleSave(', mapper: 'listingEditFailure', title: 'Save failed' },
] as const;

describe('CFT-703 · each alert site uses the mapping, and no error.message reaches Alert', () => {
  it.each(HANDLERS)('SC1: $file › $head holds the contract', ({ file, head, mapper }) => {
    expect(violations(bodyOf(read(file), head), mapper)).toEqual([]);
  });

  it.each(HANDLERS)('SC1-neg: $file › $head — the contract FAILS on a copy that shows error.message', ({ file, head, mapper, title }) => {
    const body = bodyOf(read(file), head);
    const mutated = reintroduceRaw(body, title);
    expect(mutated, 'the mutation must change the handler').not.toBe(body);
    expect(violations(mutated, mapper)).toContain('reads error.message');
  });

  it('SC2: both delete handlers ask for the deleted rows, and treat 0 rows as DEL-5', () => {
    for (const [file, head] of [
      ['app/my-listings.tsx', 'async function performDelete('],
      ['src/screens/ListingDetailScreen.tsx', 'async function handleSellerDelete('],
    ] as const) {
      const body = bodyOf(read(file), head);
      expect(body, file).toMatch(/\.delete\(\)[\s\S]*?\.eq\('seller_id'[^)]*\)\s*\.select\('id'\)/);
      expect(body, file).toContain('listingDeleteNoRows()');
      // "Deleted" / the row drop come only after the 0-row check.
      const noRows = body.indexOf('listingDeleteNoRows()');
      const success = file.includes('my-listings') ? body.indexOf('setListings((prev) => prev.filter') : body.indexOf("Alert.alert('Deleted'");
      expect(success, file).toBeGreaterThan(noRows);
    }
  });

  it('SC2-neg: the 0-row pin fails on a copy without the select', () => {
    const body = bodyOf(read('app/my-listings.tsx'), 'async function performDelete(');
    const mutated = body.replace(/\s*\.select\('id'\)/, '');
    expect(mutated).not.toBe(body);
    expect(mutated).not.toMatch(/\.delete\(\)[\s\S]*?\.eq\('seller_id'[^)]*\)\s*\.select\('id'\)/);
  });

  it('SC3: my-listings refreshes rather than dropping the row when the mapping says so', () => {
    const del = bodyOf(read('app/my-listings.tsx'), 'async function performDelete(');
    const can = bodyOf(read('app/my-listings.tsx'), 'async function performCancel(');
    for (const b of [del, can]) expect(b).toMatch(/\.refresh\)\s*(void\s+)?fetchMyListings\(true\)/);
    const det = read('src/screens/ListingDetailScreen.tsx');
    for (const head of ['async function handleSellerDelete(', 'async function handleSellerCancel(']) {
      expect(bodyOf(det, head), head).toMatch(/\.refresh\)\s*(void\s+)?fetchData\(true\)/);
    }
  });

  it('SC4: the delete gate in my-listings uses the gate copy, not "has bids" for every inactive row', () => {
    const body = bodyOf(read('app/my-listings.tsx'), 'async function performDelete(');
    expect(body).not.toContain('This listing has bids and cannot be deleted.');
    expect(body).toContain('deleteGateCopy(listing)');
  });

  it('SC5: the edit screen caps Event name and Venue at 120 characters', () => {
    const src = read('app/listing/edit/[id].tsx');
    expect(src).toMatch(/<Input label="Event name"[^>]*maxLength=\{120\}/);
    expect(src).toMatch(/<Input label="Venue"[^>]*maxLength=\{120\}/);
  });

  it('SC6: the edit load never puts the read error’s text into the refusal', () => {
    const load = bodyOf(read('app/listing/edit/[id].tsx'), 'async function load(');
    expect(load).not.toMatch(/\berror\??\.message\b/);
    expect(load).toContain('console.warn(');
  });

  it('SC6-neg: the same check fails on a copy that hands the read error back to the refusal', () => {
    const load = bodyOf(read('app/listing/edit/[id].tsx'), 'async function load(');
    const mutated = load.replace("editRefusalCopy('not-found')", "editRefusalCopy('not-found', error?.message)");
    expect(mutated).not.toBe(load);
    expect(mutated).toMatch(/\berror\??\.message\b/);
  });
});
