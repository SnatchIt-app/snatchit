/**
 * src/constants/neighborhoods.ts
 * Single source of truth for location options (areas + named venues).
 * Used by listing creation, "Your Scene" preferences, and feed filtering.
 *
 * Migration 033 expansion: Snatch It covers the full Miami event market —
 * nightlife, concerts, festivals, and sports — so the picker is grouped
 * (Areas / Clubs & Nightlife / Arenas & Stadiums) and searchable.
 *
 * Keys are lowercase and stored as-is in listings.neighborhood (text).
 * NEVER remove existing keys — live listings reference them.
 */

import type { Neighborhood } from '@/src/types';

export type NeighborhoodGroup = {
  title: string;
  items: Neighborhood[];
};

export const NEIGHBORHOOD_GROUPS: NeighborhoodGroup[] = [
  {
    title: 'Areas',
    items: [
      'miami beach', 'south beach', 'wynwood', 'brickell', 'downtown miami',
      'design district', 'midtown', 'little river', 'little haiti',
      'little havana', 'hialeah', 'doral', 'kendall', 'coral gables',
      'coconut grove', 'aventura', 'sunny isles', 'fort lauderdale', 'hollywood',
    ],
  },
  {
    title: 'Clubs & Nightlife',
    items: [
      'club space', 'e11even', 'liv', 'm2 miami', 'factory town',
    ],
  },
  {
    title: 'Arenas, Stadiums & Live Music',
    items: [
      'kaseya center', 'hard rock stadium', 'loandepot park',
      'fpl solar amphitheater', 'bayfront park', 'hard rock live',
      'amerant bank arena', 'chase stadium', 'the fillmore miami beach',
      'miami beach bandshell',
    ],
  },
];

/** Flat list (backwards-compatible export — all pickers/filters accept all). */
export const NEIGHBORHOODS: Neighborhood[] =
  NEIGHBORHOOD_GROUPS.flatMap(g => g.items);

export const NEIGHBORHOOD_LABELS: Record<Neighborhood, string> = {
  // Areas (original)
  'south beach':     'South Beach',
  'wynwood':         'Wynwood',
  'brickell':        'Brickell',
  'downtown miami':  'Downtown Miami',
  'design district': 'Design District',
  'coconut grove':   'Coconut Grove',
  'little havana':   'Little Havana',
  'miami beach':     'Miami Beach',
  'midtown':         'Midtown',
  // Areas (expansion)
  'little river':    'Little River',
  'little haiti':    'Little Haiti',
  'hialeah':         'Hialeah',
  'doral':           'Doral',
  'kendall':         'Kendall',
  'coral gables':    'Coral Gables',
  'aventura':        'Aventura',
  'sunny isles':     'Sunny Isles',
  'fort lauderdale': 'Fort Lauderdale',
  'hollywood':       'Hollywood (FL)',
  // Clubs & nightlife
  'club space':      'Club Space',
  'e11even':         'E11EVEN',
  'liv':             'LIV',
  'm2 miami':        'M2 Miami',
  'factory town':    'Factory Town',
  // Arenas, stadiums & live music
  'kaseya center':            'Kaseya Center',
  'hard rock stadium':        'Hard Rock Stadium',
  'loandepot park':           'loanDepot park',
  'fpl solar amphitheater':   'FPL Solar Amphitheater',
  'bayfront park':            'Bayfront Park',
  'hard rock live':           'Hard Rock Live',
  'amerant bank arena':       'Amerant Bank Arena',
  'chase stadium':            'Chase Stadium',
  'the fillmore miami beach': 'The Fillmore Miami Beach',
  'miami beach bandshell':    'Miami Beach Bandshell',
};
