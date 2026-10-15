/**
 * src/lib/sell/durations.ts — the auction lengths a seller can choose, and their chip labels.
 *
 * 72 h added 2026-10-15 (owner, via A; migration 155 widens listings_duration_hours_check and the
 * server stamps ends_at from duration_hours). The clocks everywhere derive from ends_at, so no
 * other screen depends on this list.
 */
import type { DurationHours } from '@/src/types';

export const DURATION_OPTIONS: readonly DurationHours[] = [1, 3, 6, 12, 24, 48, 72];

/** "6h" under a day, whole days above it: 24 → "1d", 72 → "3d". */
export function durationLabel(h: DurationHours): string {
  return h < 24 ? `${h}h` : `${h / 24}d`;
}
