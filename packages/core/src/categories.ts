/**
 * src/constants/categories.ts
 * Event categories (migration 033). Snatch It is a full event marketplace —
 * nightlife, clubs, concerts, festivals, sports, music, and special events.
 * Used by listing creation, home filters, and listing detail.
 */

import type { EventCategory } from '@snatchit/types';

export const CATEGORIES: EventCategory[] = [
  'nightlife', 'clubs', 'concerts', 'festivals',
  'sports', 'music', 'special_events', 'other',
];

export const CATEGORY_LABELS: Record<EventCategory, string> = {
  nightlife:      'Nightlife',
  clubs:          'Clubs',
  concerts:       'Concerts',
  festivals:      'Festivals',
  sports:         'Sports',
  music:          'Music',
  special_events: 'Special Events',
  other:          'Other',
};
