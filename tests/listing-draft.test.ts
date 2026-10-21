/**
 * tests/listing-draft.test.ts — CFT-608 / checklist item 36: the sell-form draft, as data.
 *
 * The pure half of "autosave the sell form and offer 'Continue your listing'". What may be kept,
 * how it is written and read back, when a stored draft is refused, and what the offer says. The
 * store (per-account key, purge on sign-out) and the hook (debounce, restore) have their own suites.
 *
 * Defaults the owner has not ruled on are pinned here so a change to them is a visible decision:
 *  - the proof-of-ownership image is never part of a draft (the seller picks it again);
 *  - the cover is kept only as a reference to the picker's app-private cache file;
 *  - the ownership attestation is never part of a draft (confirmed again at publish);
 *  - a draft whose event date has passed is refused.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

import {
  draftBannerBody,
  draftPhotosNote,
  emptyListingDraftFields,
  isListingDraftEmpty,
  isListingDraftExpired,
  isPickerCacheUri,
  LISTING_DRAFT_COPY,
  LISTING_DRAFT_FIELD_KEYS,
  LISTING_DRAFT_VERSION,
  listingDraftOffer,
  parseListingDraft,
  prepareListingDraftOffer,
  serializeListingDraft,
  type ListingDraftFields,
} from '@/src/lib/sell/listingDraft';
import { REPO_ROOT } from './helpers/nav-stack-harness';

const NOW = new Date(2026, 9, 21, 12, 0, 0);            // 21 Oct 2026, noon, device-local
const IOS_COVER = 'file:///var/mobile/Containers/Data/Application/0A1B2C3D/Library/Caches/ImagePicker/5E6F7A8B.jpeg';
const ANDROID_COVER = 'file:///data/user/0/com.snatchit.app/cache/ImagePicker/0c1d2e3f.jpg';

function filled(over: Partial<ListingDraftFields> = {}): ListingDraftFields {
  return {
    eventName: 'Weekend pool party',
    venue: 'LIV Miami',
    neighborhood: 'south beach',
    category: 'concerts',
    eventDate: new Date(2026, 9, 25, 0, 0, 0),
    eventTime: new Date(2026, 9, 21, 22, 0, 0),
    ticketType: 'VIP',
    quantity: 2,
    transferMethod: 'mobile_transfer',
    restrictions: '21+',
    startingBid: '40',
    buyNowEnabled: true,
    buyNowPrice: '90',
    durationHours: 24,
    ticketPlatform: 'dice',
    coverUri: IOS_COVER,
    ...over,
  };
}

const wire = (raw: string) => JSON.parse(raw) as { v: unknown; savedAt: unknown; fields: Record<string, unknown> };
const rewrite = (mut: (w: { v: unknown; savedAt: unknown; fields: Record<string, unknown> }) => void) => {
  const w = wire(serializeListingDraft(filled(), NOW));
  mut(w);
  return JSON.stringify(w);
};

describe('LD1 · only listing form fields are ever written', () => {
  it('LD1a: the field allowlist is exactly the sell form’s own inputs (plus the cover reference)', () => {
    expect([...LISTING_DRAFT_FIELD_KEYS].sort()).toEqual([
      'buyNowEnabled', 'buyNowPrice', 'category', 'coverUri', 'durationHours', 'eventDate', 'eventName',
      'eventTime', 'neighborhood', 'quantity', 'restrictions', 'startingBid', 'ticketPlatform', 'ticketType',
      'transferMethod', 'venue',
    ]);
  });

  it('LD1b: extra state handed to the serializer is dropped — attestation, proof, risk and submit state never reach storage', () => {
    const leaky = {
      ...filled(),
      sellerCommitmentAccepted: true,
      commitmentAccepted: true,
      proofUri: 'file:///var/mobile/Containers/Data/Application/0A/Library/Caches/ImagePicker/proof.jpeg',
      proofLocalUri: 'file:///x/proof.jpeg',
      riskCheckPassed: true,
      riskBanner: { reason: 'high_risk_warning', tier: 'high' },
      loading: true,
      submitted: true,
      email: 'seller@example.test',
      phone: '+13055550100',
    } as unknown as ListingDraftFields;
    const raw = serializeListingDraft(leaky, NOW);
    const w = wire(raw);
    expect(Object.keys(w).sort()).toEqual(['fields', 'savedAt', 'v']);
    expect(Object.keys(w.fields).sort()).toEqual([...LISTING_DRAFT_FIELD_KEYS].sort());
    for (const banned of ['Commitment', 'commitment', 'proof', 'risk', 'loading', 'submitted', 'email', 'phone', 'seller@', '+1305']) {
      expect(raw, banned).not.toContain(banned);
    }
  });

  it('LD1c: the wire format is versioned v1 with ISO dates', () => {
    const w = wire(serializeListingDraft(filled(), NOW));
    expect(LISTING_DRAFT_VERSION).toBe(1);
    expect(w.v).toBe(1);
    expect(w.savedAt).toBe(NOW.toISOString());
    expect(w.fields.eventDate).toBe(new Date(2026, 9, 25).toISOString());
    expect(w.fields.eventTime).toBe(new Date(2026, 9, 21, 22).toISOString());
  });

  it('LD1d: a cover that is not an app-private picker cache file is not written', () => {
    for (const uri of ['blob:http://localhost:8081/1', 'data:image/png;base64,AAAA', 'ph://ABC', 'https://x.supabase.co/a.jpg']) {
      expect(wire(serializeListingDraft(filled({ coverUri: uri }), NOW)).fields.coverUri, uri).toBeNull();
    }
    expect(wire(serializeListingDraft(filled({ coverUri: ANDROID_COVER }), NOW)).fields.coverUri).toBe(ANDROID_COVER);
  });
});

describe('LD2 · the cover is a reference to the picker’s app-private cache, nothing else', () => {
  it('LD2a: iOS Library/Caches/ImagePicker and Android cache/ImagePicker files qualify', () => {
    expect(isPickerCacheUri(IOS_COVER)).toBe(true);
    expect(isPickerCacheUri(ANDROID_COVER)).toBe(true);
  });

  it('LD2b: backed-up, shared, remote, inline or traversing locations never qualify', () => {
    const refused = [
      'file:///var/mobile/Containers/Data/Application/0A/Documents/ImagePicker/x.jpg',   // Documents is backed up
      'file:///var/mobile/Containers/Data/Application/0A/Library/Caches/x.jpg',          // not the picker's folder
      'file:///var/mobile/Containers/Data/Application/0A/Library/Caches/ImagePicker/sub/x.jpg',
      'file:///var/mobile/Containers/Data/Application/0A/Library/Caches/ImagePicker/../../Documents/x.jpg',
      'file:///var/mobile/Containers/Data/Application/0A/Library/Caches/ImagePicker/%2e%2e/x.jpg',
      '/var/mobile/Containers/Data/Application/0A/Library/Caches/ImagePicker/x.jpg',       // no scheme
      'content://media/external/images/media/1',
      'ph://ABC-123',
      'blob:http://localhost:8081/1',
      'data:image/jpeg;base64,AAAA',
      'https://example.supabase.co/storage/v1/object/public/auction-media/u/covers/1.jpg',
      `file:///data/user/0/com.snatchit.app/cache/ImagePicker/${'a'.repeat(2048)}.jpg`,
      '',
    ];
    for (const uri of refused) expect(isPickerCacheUri(uri), uri).toBe(false);
    for (const v of [null, undefined, 42, {}, []]) expect(isPickerCacheUri(v)).toBe(false);
  });
});

describe('LD3 · reading a stored draft back', () => {
  it('LD3a: a written draft reads back field for field, Dates included', () => {
    const f = filled();
    const d = parseListingDraft(serializeListingDraft(f, NOW));
    expect(d).not.toBeNull();
    expect(d!.version).toBe(1);
    expect(d!.savedAt.getTime()).toBe(NOW.getTime());
    expect(d!.fields.eventDate).toBeInstanceOf(Date);
    expect(d!.fields.eventDate.getTime()).toBe(f.eventDate.getTime());
    expect(d!.fields.eventTime.getTime()).toBe(f.eventTime.getTime());
    expect({ ...d!.fields, eventDate: 0, eventTime: 0 }).toEqual({ ...f, eventDate: 0, eventTime: 0 });
  });

  it('LD3b: nothing, or anything that is not a JSON object, is no draft', () => {
    for (const raw of [null, undefined, '', 'not json', '{', '[]', '"str"', '42', 'null', 'true']) {
      expect(parseListingDraft(raw as string | null), String(raw)).toBeNull();
    }
  });

  it('LD3c: another version — older, newer or missing — is discarded, not migrated', () => {
    for (const v of [0, 2, '1', null, undefined]) {
      expect(parseListingDraft(rewrite((w) => { w.v = v; })), String(v)).toBeNull();
    }
    expect(parseListingDraft(rewrite((w) => { delete (w as { v?: unknown }).v; }))).toBeNull();
  });

  it('LD3d: a field of the wrong type or outside its allowed values makes the whole draft corrupt', () => {
    const corruptions: [string, unknown][] = [
      ['eventName', 7], ['venue', null], ['restrictions', undefined],
      ['neighborhood', 'atlantis'], ['category', 'karaoke'], ['ticketType', 'GOLD'],
      ['transferMethod', 'fax'], ['ticketPlatform', 'myspace'], ['durationHours', 5],
      ['quantity', 0], ['quantity', 1.5], ['quantity', '2'], ['quantity', -1],
      ['startingBid', 'abc'], ['startingBid', 40], ['buyNowPrice', '9.99'], ['buyNowEnabled', 'yes'],
      ['eventDate', 'not a date'], ['eventTime', 123], ['coverUri', 5],
      ['coverUri', 'file:///var/mobile/Containers/Data/Application/0A/Documents/x.jpg'],
    ];
    for (const [k, v] of corruptions) {
      expect(parseListingDraft(rewrite((w) => { w.fields[k] = v; })), `${k}=${String(v)}`).toBeNull();
    }
    expect(parseListingDraft(rewrite((w) => { delete (w as { fields?: unknown }).fields; }))).toBeNull();
    expect(parseListingDraft(rewrite((w) => { w.savedAt = 'yesterday'; }))).toBeNull();
  });

  it('LD3e: unknown extra keys in storage are not carried into the form', () => {
    const d = parseListingDraft(rewrite((w) => { w.fields.sellerCommitmentAccepted = true; w.fields.proofUri = IOS_COVER; }));
    expect(d).not.toBeNull();
    expect(Object.keys(d!.fields).sort()).toEqual([...LISTING_DRAFT_FIELD_KEYS].sort());
  });

  it('LD3f: nullable choices stay null', () => {
    const f = filled({ neighborhood: null, ticketType: null, transferMethod: null, durationHours: null, coverUri: null });
    const d = parseListingDraft(serializeListingDraft(f, NOW))!;
    expect(d.fields.neighborhood).toBeNull();
    expect(d.fields.ticketType).toBeNull();
    expect(d.fields.transferMethod).toBeNull();
    expect(d.fields.durationHours).toBeNull();
    expect(d.fields.coverUri).toBeNull();
  });
});

describe('LD4 · an untouched form is not a draft', () => {
  it('LD4a: the screen’s own starting values are empty — date and time never count, they always have a value', () => {
    expect(isListingDraftEmpty(emptyListingDraftFields(NOW))).toBe(true);
    expect(isListingDraftEmpty({ ...emptyListingDraftFields(NOW), eventDate: new Date(2027, 0, 1), eventTime: new Date(2027, 0, 1, 3) })).toBe(true);
    expect(isListingDraftEmpty({ ...emptyListingDraftFields(NOW), eventName: '   ', venue: '\n' })).toBe(true);
    // a cover that could never be written does not make a draft either
    expect(isListingDraftEmpty({ ...emptyListingDraftFields(NOW), coverUri: 'blob:http://x/1' })).toBe(true);
  });

  it('LD4a2: the category on its own is not a draft — the screen keeps it chosen after a publish, so it is not work to lose', () => {
    // CreateListingScreen's success reset clears every field except the category. Counting it would
    // re-save a one-field "draft" straight after a publish the server confirmed (found by W4).
    expect(isListingDraftEmpty({ ...emptyListingDraftFields(NOW), category: 'concerts' })).toBe(true);
    expect(isListingDraftEmpty({ ...emptyListingDraftFields(NOW), category: 'concerts', eventName: 'x' })).toBe(false);
  });

  it('LD4b: any one thing the seller typed or chose makes it a draft', () => {
    const base = emptyListingDraftFields(NOW);
    const one: Partial<ListingDraftFields>[] = [
      { eventName: 'x' }, { venue: 'x' }, { neighborhood: 'wynwood' },
      { ticketType: 'GA' }, { quantity: 3 }, { transferMethod: 'email' }, { restrictions: '21+' },
      { startingBid: '5' }, { buyNowEnabled: true }, { buyNowPrice: '9' }, { durationHours: 72 },
      { ticketPlatform: 'tixr' }, { coverUri: ANDROID_COVER },
    ];
    for (const o of one) expect(isListingDraftEmpty({ ...base, ...o }), JSON.stringify(o)).toBe(false);
  });

  it('LD4c: the empty values are the screen’s initial state (pinned to the source so they cannot drift)', () => {
    const screen = readFileSync(join(REPO_ROOT, 'src/screens/CreateListingScreen.tsx'), 'utf8');
    const e = emptyListingDraftFields(NOW);
    expect(screen).toContain(`useState<EventCategory>('${e.category}')`);
    expect(screen).toContain(`useState<TicketPlatform>(fx?.ticketPlatform ?? '${e.ticketPlatform}')`);
    expect(screen).toContain(`useState(fx?.quantity ?? ${e.quantity})`);
    expect(screen).toContain("useState(fx?.startingBid ?? '')");
    expect(screen).toContain('const [buyNowEnabled, setBuyNowEnabled] = useState(false);');
    expect(e).toMatchObject({
      eventName: '', venue: '', neighborhood: null, ticketType: null, transferMethod: null, restrictions: '',
      startingBid: '', buyNowEnabled: false, buyNowPrice: '', durationHours: null, coverUri: null,
    });
  });
});

describe('LD5 · a draft for an event that has passed is refused', () => {
  const at = (eventDate: Date) => ({ version: 1 as const, savedAt: NOW, fields: filled({ eventDate }) });

  it('LD5a: yesterday’s event is expired', () => {
    expect(isListingDraftExpired(at(new Date(2026, 9, 20, 0, 0)), NOW)).toBe(true);
    expect(isListingDraftExpired(at(new Date(2026, 9, 20, 23, 59)), NOW)).toBe(true);
    expect(isListingDraftExpired(at(new Date(2025, 11, 31)), NOW)).toBe(true);
  });

  it('LD5b: today’s event is not — it may be tonight — and neither is a later one', () => {
    expect(isListingDraftExpired(at(new Date(2026, 9, 21, 0, 0)), NOW)).toBe(false);
    expect(isListingDraftExpired(at(new Date(2026, 9, 21, 23, 59)), new Date(2026, 9, 21, 23, 59, 59))).toBe(false);
    expect(isListingDraftExpired(at(new Date(2026, 9, 22)), NOW)).toBe(false);
    expect(isListingDraftExpired(at(new Date(2027, 5, 1)), NOW)).toBe(false);
  });
});

describe('LD6 · the offer', () => {
  const draft = (over: Partial<ListingDraftFields> = {}) => ({ version: 1 as const, savedAt: NOW, fields: filled(over) });

  it('LD6a: a cover still on the device comes back; a missing one is dropped from what is restored', () => {
    const kept = listingDraftOffer(draft(), true);
    expect(kept.coverKept).toBe(true);
    expect(kept.fields.coverUri).toBe(IOS_COVER);
    const gone = listingDraftOffer(draft(), false);
    expect(gone.coverKept).toBe(false);
    expect(gone.fields.coverUri).toBeNull();
    expect(listingDraftOffer(draft({ coverUri: null }), true).coverKept).toBe(false);
  });

  it('LD6b: the probe decides, is asked only when there is a cover, and a probe failure means "gone"', async () => {
    const yes = vi.fn(async () => true);
    expect((await prepareListingDraftOffer(draft(), yes)).coverKept).toBe(true);
    expect(yes).toHaveBeenCalledWith(IOS_COVER);
    const no = vi.fn(async () => false);
    expect((await prepareListingDraftOffer(draft(), no)).fields.coverUri).toBeNull();
    const boom = vi.fn(async () => { throw new Error('ENOENT'); });
    expect((await prepareListingDraftOffer(draft(), boom)).coverKept).toBe(false);
    const never = vi.fn(async () => true);
    await prepareListingDraftOffer(draft({ coverUri: null }), never);
    expect(never).not.toHaveBeenCalled();
  });

  it('LD6c: the copy is calm and exact — what is kept, where, and what the seller still has to add', () => {
    const named = listingDraftOffer(draft({ eventName: '  Weekend pool party ' }), true);
    expect(named.eventName).toBe('Weekend pool party');
    expect(draftBannerBody(named)).toBe('"Weekend pool party" is saved on this device.');
    expect(draftBannerBody(listingDraftOffer(draft({ eventName: ' ' }), true))).toBe('A listing you started is saved on this device.');
    expect(draftPhotosNote(named)).toBe('Add proof of ownership before listing.');
    expect(draftPhotosNote(listingDraftOffer(draft(), false))).toBe('Add the cover image and proof of ownership before listing.');
    expect(LISTING_DRAFT_COPY.continue).toBe('Continue your listing');
    expect(LISTING_DRAFT_COPY.discard).toBe('Discard');
    // Nothing here has reached a server, so nothing may sound as if it had.
    const all = [draftBannerBody(named), draftPhotosNote(named), ...Object.values(LISTING_DRAFT_COPY).filter((v) => typeof v === 'string')].join(' ');
    expect(all).not.toMatch(/\b(published|listed|uploaded|live|account|synced|cloud)\b/i);
  });
});
