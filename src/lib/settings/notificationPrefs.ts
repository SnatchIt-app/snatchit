/**
 * src/lib/settings/notificationPrefs.ts — the notification switches and which of
 * them are shown (notification batch 1, item 1; owner ruling 2026-09-17).
 *
 * Only a switch whose notification path exists is shown. Today that is
 * "Listing sold": the seller push on `ticket_sold` (stripe-webhook → send-push).
 * The other five name notifications that nothing sends yet (auction ending and
 * reservation expiry have no producer; outbid, won and lost are screen-local
 * reminders that ignore these columns), so they are HIDDEN, not removed: the
 * definitions stay, stored values stay, and hiding never writes — a user who
 * turned one off keeps it off for the day its path exists.
 */

import type { NotificationPreferences } from '@/src/types';

export type PrefKey = keyof Omit<NotificationPreferences, 'user_id' | 'updated_at'>;
export interface PrefToggle { key: PrefKey; label: string; description: string }

export const PREF_TOGGLES: PrefToggle[] = [
  { key: 'notify_outbid',           label: 'Outbid alerts',        description: 'Get notified when someone outbids you' },
  { key: 'notify_auction_ending',   label: 'Auction ending soon',  description: 'Reminder when auctions you bid on are ending' },
  { key: 'notify_auction_won',      label: 'Auction won',          description: 'Know the moment you win an auction' },
  { key: 'notify_auction_lost',     label: 'Auction lost',         description: 'Know when an auction you bid on ends without you winning' },
  { key: 'notify_reservation_exp',  label: 'Reservation expiring', description: 'Reminder before your Buy Now reservation expires' },
  { key: 'notify_listing_sold',     label: 'Listing sold',         description: 'Get notified when your listing sells' },
];

/** Switches whose notification path exists in the current release. */
export const WIRED_PREF_KEYS: PrefKey[] = ['notify_listing_sold'];

export function visibleToggles(toggles: PrefToggle[], wired: PrefKey[]): PrefToggle[] {
  return toggles.filter((t) => wired.includes(t.key));
}
