/**
 * src/lib/pricing/provenance.ts — who is selling this ticket, in plain language.
 *
 * WHY THIS IS NOT A STYLING DETAIL
 * Snatch It is becoming the only product in its category that carries both
 * first-party inventory and a fan-to-fan marketplace in one place. That is the
 * strategic advantage and it creates one hard obligation: a resale ticket must
 * never be presented as venue-issued inventory. Provenance is a trust claim, and
 * it is carried by WORDS, never by colour alone, because colour fails for
 * colourblind users, in screenshots, and in high-contrast modes.
 *
 * The customer vocabulary is fixed by the brand, which says "direct" and
 * "marketplace" and never says primary, secondary, rail, atom or inventory.
 */

export type InventoryKind = 'direct' | 'marketplace_fixed' | 'marketplace_auction';

export interface ProvenanceLabel {
  kind: InventoryKind;
  /** Short badge text. Kept to two or three words so it never wraps. */
  badge: string;
  /** One sentence a customer can act on. Plain language, no jargon. */
  explanation: string;
  /**
   * Which token drives the badge. `brand` is reserved for direct inventory,
   * because it is the first-party offer. Marketplace is deliberately neutral so
   * it can never be mistaken for an official ticket.
   */
  tone: 'brand' | 'neutral';
}

const LABELS: Record<InventoryKind, ProvenanceLabel> = {
  direct: {
    kind: 'direct',
    badge: 'Direct from event',
    explanation: 'Sold by the venue. Your ticket is issued straight to your account.',
    tone: 'brand',
  },
  marketplace_fixed: {
    kind: 'marketplace_fixed',
    badge: 'From a fan',
    explanation:
      'Sold by another fan at a set price. Payment is held until the ticket reaches you.',
    tone: 'neutral',
  },
  marketplace_auction: {
    kind: 'marketplace_auction',
    badge: 'Fan auction',
    explanation:
      'Sold by another fan to the highest bidder. Payment is held until the ticket reaches you.',
    tone: 'neutral',
  },
};

export function provenanceLabel(kind: InventoryKind): ProvenanceLabel {
  return LABELS[kind];
}

/**
 * Derives the inventory kind from what a row actually is.
 *
 * Deliberately conservative: anything not positively identified as venue-direct
 * is treated as marketplace. Mislabelling a fan ticket as official is the one
 * error this module exists to prevent, so the default leans the safe way.
 */
export function inventoryKindOf(row: {
  /** True only when the row came from the venue's own ticket types. */
  isDirect?: boolean;
  /** Marketplace listing mode, when this is a listing. */
  listingMode?: 'buy_now' | 'auction' | 'offer' | null;
}): InventoryKind {
  if (row.isDirect === true) return 'direct';
  if (row.listingMode === 'auction') return 'marketplace_auction';
  return 'marketplace_fixed';
}

/**
 * Ordering rule for an event page that carries both kinds.
 *
 * Direct inventory sorts above marketplace inventory when it is available: it is
 * the cheaper, safer, first-party option and burying it would be dishonest. Once
 * direct inventory is sold out it drops below, because at that point the
 * marketplace is the only way in, which is the brand's own line: sold out, but
 * the night is not.
 */
export function provenanceSortWeight(kind: InventoryKind, soldOut: boolean): number {
  if (kind === 'direct') return soldOut ? 30 : 0;
  if (kind === 'marketplace_fixed') return 10;
  return 20;
}
