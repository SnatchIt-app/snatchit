/**
 * src/constants/neighborhoods.ts
 * Single source of truth for neighborhood options.
 * Used by listing creation, "Your Scene" preferences, and feed sorting.
 */

import type { Neighborhood } from '@/src/types';

export const NEIGHBORHOODS: Neighborhood[] = [
  'south beach', 'wynwood', 'brickell', 'downtown miami',
  'design district', 'coconut grove', 'little havana', 'miami beach', 'midtown',
];

export const NEIGHBORHOOD_LABELS: Record<Neighborhood, string> = {
  'south beach':     'South Beach',
  'wynwood':         'Wynwood',
  'brickell':        'Brickell',
  'downtown miami':  'Downtown Miami',
  'design district': 'Design District',
  'coconut grove':   'Coconut Grove',
  'little havana':   'Little Havana',
  'miami beach':     'Miami Beach',
  'midtown':         'Midtown',
};
