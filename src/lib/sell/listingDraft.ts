/**
 * src/lib/sell/listingDraft.ts — the sell-form draft, as data (CFT-608, checklist item 36).
 *
 * Pure and dependency-free apart from the form's own value lists, so every decision about a draft
 * is unit-tested (tests/listing-draft.test.ts). Where it is stored, and when it is purged, is
 * src/lib/sell/listingDraftStore.ts; the debounce and the restore are src/hooks/useListingDraft.ts.
 *
 * WHAT A DRAFT HOLDS — only the sell form's own inputs, copied key by key from an allowlist
 * (`LISTING_DRAFT_FIELD_KEYS`), never spread, so state that sits beside the form cannot leak in:
 *  - never the ownership attestation: `seller_commitment_accepted_at` is stamped at insert, so the
 *    seller confirms it again at publish (default put to the owner);
 *  - never the proof of ownership: a ticket screenshot can carry an email address or an order
 *    number, so the seller picks it again (default put to the owner);
 *  - never risk, moderation, loading or submit state, and nothing about the account.
 * The cover (event artwork, public once listed) is kept only as a REFERENCE to the file
 * expo-image-picker already wrote into the app's private cache — never copied, never uploaded early.
 * Anything else (a Documents path, which iOS backs up; a remote URL; inline data) is not written.
 *
 * READING ONE BACK — a draft is versioned (`v: 1`). Another version, or anything that does not
 * match the schema field for field, is discarded whole rather than half-restored or migrated.
 *
 * THE EVENT DATE AND TIME are written as the form uses them — a device-local calendar day
 * ('2026-10-25') and clock time ('22:30') — never as instants. The screen publishes the date row's
 * day and the time row's clock time, so an instant saved in Miami and read in Los Angeles would move
 * the date back a day; a day and a clock time read back as the same day and time anywhere.
 *
 * EXPIRY — a draft whose event date has passed is refused (default put to the owner), but only a date
 * the seller picked (`dateChosen`). The date row starts at today, so an unpicked date is only the
 * screen's default for the day the seller typed: it never expires a draft, and it comes back as the
 * day the draft is offered, as a new form's would.
 */

import { CATEGORIES } from '@/src/constants/categories';
import { NEIGHBORHOODS } from '@/src/constants/neighborhoods';
import { TICKET_PLATFORMS } from '@/src/lib/listing/ticketPlatforms';
import { DURATION_OPTIONS } from '@/src/lib/sell/durations';
import type {
  DurationHours,
  EventCategory,
  Neighborhood,
  TicketPlatform,
  TicketType,
  TransferMethod,
} from '@/src/types';

export const LISTING_DRAFT_VERSION = 1;

/** The sell form's inputs, as the screen holds them (Dates as Dates). */
export interface ListingDraftFields {
  eventName: string;
  venue: string;
  neighborhood: Neighborhood | null;
  category: EventCategory;
  eventDate: Date;
  eventTime: Date;
  /** The seller picked the date. False while the date row still shows the screen's default (today). */
  dateChosen: boolean;
  ticketType: TicketType | null;
  quantity: number;
  transferMethod: TransferMethod | null;
  restrictions: string;
  startingBid: string;
  buyNowEnabled: boolean;
  buyNowPrice: string;
  durationHours: DurationHours | null;
  ticketPlatform: TicketPlatform;
  /** A reference to the picker's app-private cache file, or null. Never the proof. */
  coverUri: string | null;
}

export interface ListingDraft {
  version: typeof LISTING_DRAFT_VERSION;
  savedAt: Date;
  fields: ListingDraftFields;
}

/** The allowlist. Serialize and parse both copy exactly these keys and nothing else. */
export const LISTING_DRAFT_FIELD_KEYS = [
  'eventName', 'venue', 'neighborhood', 'category', 'eventDate', 'eventTime', 'dateChosen',
  'ticketType', 'quantity', 'transferMethod', 'restrictions',
  'startingBid', 'buyNowEnabled', 'buyNowPrice', 'durationHours',
  'ticketPlatform', 'coverUri',
] as const satisfies readonly (keyof ListingDraftFields)[];

const TICKET_TYPES: readonly TicketType[] = ['GA', 'VIP'];
const TRANSFER_METHODS: readonly TransferMethod[] = ['mobile_transfer', 'email'];
const PLATFORM_VALUES: readonly TicketPlatform[] = TICKET_PLATFORMS.map((p) => p.value);

/** The screen's own starting values (pinned to its source by LD4c). */
const DEFAULT_CATEGORY: EventCategory = 'nightlife';
const DEFAULT_PLATFORM: TicketPlatform = 'other';
const DEFAULT_QUANTITY = 1;

/** An untouched form, as the screen starts it. Date and time always carry a value. */
export function emptyListingDraftFields(now: Date = new Date()): ListingDraftFields {
  const date = new Date(now); date.setHours(0, 0, 0, 0);
  const time = new Date(now); time.setHours(time.getHours() + 1, 0, 0, 0);
  return {
    eventName: '', venue: '', neighborhood: null, category: DEFAULT_CATEGORY,
    eventDate: date, eventTime: time, dateChosen: false,
    ticketType: null, quantity: DEFAULT_QUANTITY, transferMethod: null, restrictions: '',
    startingBid: '', buyNowEnabled: false, buyNowPrice: '', durationHours: null,
    ticketPlatform: DEFAULT_PLATFORM, coverUri: null,
  };
}

// ─── The cover reference ───────────────────────────────────────────────────────

const MAX_URI_LENGTH = 1024;
/**
 * expo-image-picker 17 writes every pick to `<caches>/ImagePicker/<name>` — iOS
 * `Library/Caches/ImagePicker` (MediaHandler.swift `generateUrl`), Android `cache/ImagePicker`
 * (ImagePickerConstants.CACHE_DIR_NAME). Both are app-private and excluded from backups. Only a
 * direct child of that folder qualifies; a sub-path, a traversal or an encoded segment does not.
 */
const PICKER_CACHE_FILE = /^file:\/\/\/[^?#%]*\/(?:Library\/Caches|cache)\/ImagePicker\/[^/?#%]+$/;

export function isPickerCacheUri(uri: unknown): uri is string {
  if (typeof uri !== 'string' || uri.length === 0 || uri.length > MAX_URI_LENGTH) return false;
  if (/\/\.{1,2}(?:\/|$)/.test(uri)) return false;
  return PICKER_CACHE_FILE.test(uri);
}

// ─── Write ─────────────────────────────────────────────────────────────────────

type WireFields = Record<(typeof LISTING_DRAFT_FIELD_KEYS)[number], unknown>;

const pad2 = (n: number) => String(n).padStart(2, '0');

/** The device-local calendar day, as the date row shows it: '2026-10-25'. */
function toLocalDay(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/** The device-local clock time, as the time row shows it: '22:30'. */
function toLocalClock(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

function toWire(f: ListingDraftFields): WireFields {
  return {
    eventName: f.eventName,
    venue: f.venue,
    neighborhood: f.neighborhood,
    category: f.category,
    eventDate: toLocalDay(f.eventDate),
    eventTime: toLocalClock(f.eventTime),
    dateChosen: f.dateChosen === true,
    ticketType: f.ticketType,
    quantity: f.quantity,
    transferMethod: f.transferMethod,
    restrictions: f.restrictions,
    startingBid: f.startingBid,
    buyNowEnabled: f.buyNowEnabled,
    buyNowPrice: f.buyNowPrice,
    durationHours: f.durationHours,
    ticketPlatform: f.ticketPlatform,
    coverUri: isPickerCacheUri(f.coverUri) ? f.coverUri : null,
  };
}

export function serializeListingDraft(fields: ListingDraftFields, savedAt: Date): string {
  return JSON.stringify({ v: LISTING_DRAFT_VERSION, savedAt: savedAt.toISOString(), fields: toWire(fields) });
}

/** What would be written, minus the timestamp — two forms with the same signature are the same draft. */
export function listingDraftSignature(fields: ListingDraftFields): string {
  return JSON.stringify(toWire(fields));
}

// ─── Read ──────────────────────────────────────────────────────────────────────

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const isDigits = (v: unknown): v is string => typeof v === 'string' && /^\d*$/.test(v);
const oneOf = <T,>(list: readonly T[], v: unknown): v is T => list.includes(v as T);
const orNull = <T,>(list: readonly T[], v: unknown): v is T | null => v === null || oneOf(list, v);

function isoDate(v: unknown): Date | null {
  if (typeof v !== 'string') return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** '2026-10-25' → local midnight of that day. Anything else, or a day that does not exist, is null. */
function fromLocalDay(v: unknown): Date | null {
  if (typeof v !== 'string') return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  if (!m) return null;
  const y = Number(m[1]); const mo = Number(m[2]) - 1; const day = Number(m[3]);
  const d = new Date(y, mo, day);
  return d.getFullYear() === y && d.getMonth() === mo && d.getDate() === day ? d : null;
}

/** '22:30' → that local clock time on `day`. Anything else is null. */
function fromLocalClock(v: unknown, day: Date): Date | null {
  if (typeof v !== 'string') return null;
  const m = /^(\d{2}):(\d{2})$/.exec(v);
  if (!m) return null;
  const hh = Number(m[1]); const mm = Number(m[2]);
  if (hh > 23 || mm > 59) return null;
  return new Date(day.getFullYear(), day.getMonth(), day.getDate(), hh, mm);
}

/** Never throws. Anything that is not a v1 draft matching the schema field for field is null. */
export function parseListingDraft(raw: string | null | undefined): ListingDraft | null {
  if (!raw) return null;
  let doc: unknown;
  try { doc = JSON.parse(raw); } catch { return null; }
  if (!isObject(doc) || doc.v !== LISTING_DRAFT_VERSION || !isObject(doc.fields)) return null;
  const savedAt = isoDate(doc.savedAt);
  const f = doc.fields;
  const eventDate = fromLocalDay(f.eventDate);
  const eventTime = eventDate ? fromLocalClock(f.eventTime, eventDate) : null;
  if (!savedAt || !eventDate || !eventTime || typeof f.dateChosen !== 'boolean') return null;
  if (typeof f.eventName !== 'string' || typeof f.venue !== 'string' || typeof f.restrictions !== 'string') return null;
  if (!orNull(NEIGHBORHOODS, f.neighborhood) || !oneOf(CATEGORIES, f.category)) return null;
  if (!orNull(TICKET_TYPES, f.ticketType) || !orNull(TRANSFER_METHODS, f.transferMethod)) return null;
  if (!orNull(DURATION_OPTIONS, f.durationHours) || !oneOf(PLATFORM_VALUES, f.ticketPlatform)) return null;
  if (typeof f.quantity !== 'number' || !Number.isInteger(f.quantity) || f.quantity < 1) return null;
  if (!isDigits(f.startingBid) || !isDigits(f.buyNowPrice) || typeof f.buyNowEnabled !== 'boolean') return null;
  if (f.coverUri !== null && !isPickerCacheUri(f.coverUri)) return null;
  return {
    version: LISTING_DRAFT_VERSION,
    savedAt,
    fields: {
      eventName: f.eventName,
      venue: f.venue,
      neighborhood: f.neighborhood,
      category: f.category,
      eventDate,
      eventTime,
      dateChosen: f.dateChosen,
      ticketType: f.ticketType,
      quantity: f.quantity,
      transferMethod: f.transferMethod,
      restrictions: f.restrictions,
      startingBid: f.startingBid,
      buyNowEnabled: f.buyNowEnabled,
      buyNowPrice: f.buyNowPrice,
      durationHours: f.durationHours,
      ticketPlatform: f.ticketPlatform,
      coverUri: f.coverUri,
    },
  };
}

// ─── Empty and expired ─────────────────────────────────────────────────────────

/**
 * True when the seller has typed or chosen nothing. Date and time are not counted: they always
 * hold a value (nor, on its own, is a picked date). Nor is the category: the screen keeps it chosen after a publish (its success reset
 * clears every other field), so counting it would re-save a one-field draft straight after a
 * publish the server confirmed. On their own these are not work to lose; with anything else they
 * are saved as part of the draft.
 */
export function isListingDraftEmpty(f: ListingDraftFields): boolean {
  return f.eventName.trim() === ''
    && f.venue.trim() === ''
    && f.neighborhood === null
    && f.ticketType === null
    && f.quantity === DEFAULT_QUANTITY
    && f.transferMethod === null
    && f.restrictions.trim() === ''
    && f.startingBid === ''
    && !f.buyNowEnabled
    && f.buyNowPrice === ''
    && f.durationHours === null
    && f.ticketPlatform === DEFAULT_PLATFORM
    && !isPickerCacheUri(f.coverUri);
}

const startOfLocalDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/**
 * The seller picked the event date and its calendar day (device-local, as the date row shows it) is
 * before today. Today is not expired. An unpicked date is the screen's default, not the seller's
 * choice, so it never expires a draft.
 */
export function isListingDraftExpired(draft: ListingDraft, now: Date): boolean {
  return draft.fields.dateChosen
    && startOfLocalDay(draft.fields.eventDate).getTime() < startOfLocalDay(now).getTime();
}

// ─── The offer ─────────────────────────────────────────────────────────────────

export interface ListingDraftOffer {
  /** What Continue restores. `coverUri` is already null when the cached file is gone. */
  fields: ListingDraftFields;
  /** Trimmed event name, or '' when none was typed. */
  eventName: string;
  /** The cover comes back with the draft. */
  coverKept: boolean;
}

export function listingDraftOffer(draft: ListingDraft, coverStillThere: boolean, now: Date = new Date()): ListingDraftOffer {
  const coverKept = draft.fields.coverUri !== null && coverStillThere;
  return {
    fields: {
      ...draft.fields,
      // An unpicked date was only the screen's default on the day the seller typed: it comes back as
      // today, as a new form's would, never as a day that may have passed.
      eventDate: draft.fields.dateChosen ? draft.fields.eventDate : startOfLocalDay(now),
      coverUri: coverKept ? draft.fields.coverUri : null,
    },
    eventName: draft.fields.eventName.trim(),
    coverKept,
  };
}

/** Asks `probe` whether the cached cover still exists — only when there is one. A probe failure is "gone". */
export async function prepareListingDraftOffer(
  draft: ListingDraft,
  probe: (uri: string) => Promise<boolean>,
  now: () => Date = () => new Date(),
): Promise<ListingDraftOffer> {
  const uri = draft.fields.coverUri;
  if (!uri) return listingDraftOffer(draft, false, now());
  let there = false;
  try { there = await probe(uri); } catch { there = false; }
  return listingDraftOffer(draft, there, now());
}

// ─── Copy ──────────────────────────────────────────────────────────────────────

/**
 * Calm and exact: the draft lives on this device only, nothing has reached a server, and the
 * photos the seller still has to add are named. The attestation is not mentioned — its unticked
 * box and the form's own validation already say so at publish.
 */
export const LISTING_DRAFT_COPY = {
  title: 'Unfinished listing',
  bodyUnnamed: 'A listing you started is saved on this device.',
  photosCoverKept: 'Add proof of ownership before listing.',
  photosNoneKept: 'Add the cover image and proof of ownership before listing.',
  continue: 'Continue your listing',
  discard: 'Discard',
  confirmTitle: 'Discard this listing?',
  confirmBody: 'The details saved on this device will be deleted.',
  confirmKeep: 'Keep',
  confirmDiscard: 'Discard',
} as const;

export function draftBannerBody(offer: ListingDraftOffer): string {
  return offer.eventName ? `"${offer.eventName}" is saved on this device.` : LISTING_DRAFT_COPY.bodyUnnamed;
}

export function draftPhotosNote(offer: ListingDraftOffer): string {
  return offer.coverKept ? LISTING_DRAFT_COPY.photosCoverKept : LISTING_DRAFT_COPY.photosNoneKept;
}
