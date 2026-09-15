/**
 * src/lib/listing/liveState.ts — what the listing screen says about its own
 * liveness (CFT-501, CFT-504). Pure; the screen owns the effects.
 *
 *  - A live auction whose realtime channel dropped must say so: a frozen
 *    screen must never look live. The notice is shown only while there is a
 *    clock to be wrong about.
 *  - When the clock reaches zero on this device, the server has not spoken.
 *    The screen re-reads the listing row on a short schedule until
 *    `auction_status` leaves 'active' (the finalize cron runs every two
 *    minutes) — reads only, no new finalize call, nothing about timing moves.
 */

import type { RealtimeConnection } from '@/src/hooks/useListingRealtime';
import type { TransactionMode } from '@/src/lib/listing/detailState';

export const CONNECTION_NOTICE = 'Reconnecting — bid status may be delayed';

/** The notice text, or null when nothing needs saying. */
export function connectionNotice(connection: RealtimeConnection, mode: TransactionMode): string | null {
  if (mode === 'closed') return null;
  return connection === 'reconnecting' ? CONNECTION_NOTICE : null;
}

/** Re-read cadence after the clock hits zero: 3 s, then every 10 s, for ~2.5 min. */
export const RESULT_POLL_FIRST_MS = 3_000;
export const RESULT_POLL_EVERY_MS = 10_000;
export const RESULT_POLL_MAX_ATTEMPTS = 16;

/** Delay before poll `attempt` (1-based), or null when polling should stop. */
export function resultPollDelayMs(attempt: number): number | null {
  if (attempt < 1 || attempt > RESULT_POLL_MAX_ATTEMPTS) return null;
  return attempt === 1 ? RESULT_POLL_FIRST_MS : RESULT_POLL_EVERY_MS;
}

/** Poll only while this device thinks the clock ran out and the server still says active. */
export function shouldPollForResult(i: { clockEnded: boolean; auctionStatus: string | null | undefined; sold: boolean }): boolean {
  return i.clockEnded && !i.sold && (i.auctionStatus ?? 'active') === 'active';
}
