/**
 * src/lib/transfer/providerHandoff.ts — leaving for the ticket provider and
 * coming back to the same order (CFT-404, item 32).
 *
 * The buyer opens the provider from the receive screen, checks their account,
 * and returns. Two rules, both the owner's:
 *
 *  1. Returning from another app NEVER implies receipt or payment. It is a
 *     question — "Did the tickets arrive?" — asked only after the order has
 *     been re-read from the server, and only while the seller's claim is the
 *     latest state (`seller_sent`). If the authoritative state moved on while
 *     the buyer was away (confirmed elsewhere, auto-released, disputed), the
 *     screen shows that state and asks nothing.
 *  2. The order context is preserved by staying on the order: the app switch
 *     does not unmount the screen, and the return re-fetches rather than
 *     trusting what was on screen before the buyer left.
 *
 * "They're here" does not confirm anything. It dismisses the question and
 * leaves the buyer at the one control that releases payment, which explains
 * itself before it does. Pure; the screen owns the effects.
 */

import type { TicketPlatform } from '@/src/types';

export interface ProviderLink {
  /** e.g. "Ticketmaster" — matches the instruction engine's display name. */
  name: string;
  /** Official web entry point. Universal links open the native app when installed. */
  url: string;
}

/**
 * Official entry points only, one per provider; none for `other`. A wrong link
 * would send a buyer to the wrong account, so unknown stays unknown.
 */
export const PROVIDER_LINKS: Record<TicketPlatform, ProviderLink | null> = {
  ticketmaster: { name: 'Ticketmaster', url: 'https://www.ticketmaster.com/' },
  dice:         { name: 'DICE',         url: 'https://dice.fm/' },
  tixr:         { name: 'Tixr',         url: 'https://www.tixr.com/' },
  posh:         { name: 'Posh',         url: 'https://posh.vip/' },
  eventbrite:   { name: 'Eventbrite',   url: 'https://www.eventbrite.com/' },
  axs:          { name: 'AXS',          url: 'https://www.axs.com/' },
  seatgeek:     { name: 'SeatGeek',     url: 'https://seatgeek.com/' },
  mlb_ballpark: { name: 'MLB Ballpark', url: 'https://www.mlb.com/apps/ballpark' },
  fever:        { name: 'Fever',        url: 'https://feverup.com/' },
  shotgun:      { name: 'Shotgun',      url: 'https://shotgun.live/' },
  universe:     { name: 'Universe',     url: 'https://www.universe.com/' },
  see_tickets:  { name: 'See Tickets',  url: 'https://www.seetickets.us/' },
  stubhub:      { name: 'StubHub',      url: 'https://www.stubhub.com/' },
  vivid_seats:  { name: 'Vivid Seats',  url: 'https://www.vividseats.com/' },
  gametime:     { name: 'Gametime',     url: 'https://gametime.co/' },
  other:        null,
};

export function providerLink(platform: TicketPlatform | null | undefined): ProviderLink | null {
  if (!platform) return null;
  return PROVIDER_LINKS[platform] ?? null;
}

export interface HandoffState {
  /** The buyer left for the provider from this screen and has not been asked since. */
  awaitingReturn: boolean;
  /** When they left, epoch ms; null when not away. */
  leftAt: number | null;
}

export const HANDOFF_IDLE: HandoffState = { awaitingReturn: false, leftAt: null };

/** Anything shorter is a mis-tap or a permissions sheet, not a trip to the provider. */
export const MIN_AWAY_MS = 1_500;

export function leaveForProvider(now: number): HandoffState {
  return { awaitingReturn: true, leftAt: now };
}

export interface ReturnDecision {
  next: HandoffState;
  /** Re-read the order from the server before showing anything. */
  refetch: boolean;
}

/**
 * The app came to the foreground. Always refetch if we were away for the
 * provider; the question itself is decided by `returnPrompt` on the FRESH
 * status, never here.
 */
export function onForeground(state: HandoffState, now: number): ReturnDecision {
  if (!state.awaitingReturn || state.leftAt == null) return { next: state, refetch: false };
  if (now - state.leftAt < MIN_AWAY_MS) return { next: state, refetch: false };
  return { next: HANDOFF_IDLE, refetch: true };
}

/**
 * Ask "Did the tickets arrive?" only while the seller's claim is the latest
 * authoritative state. Every other state answers the question itself and must
 * be shown instead. Missing delivery details no longer suppress it: on a sent
 * transfer the buyer can confirm or report regardless (F-XFER-3), so the
 * question is answerable (owner's decision 1). It only asks — it confirms nothing.
 */
export function returnPrompt(freshStatus: string): boolean {
  return freshStatus === 'seller_sent';
}

export const RETURN_PROMPT = {
  title: 'Did the tickets arrive?',
  /** `{provider}` is filled by the screen; "your ticket account" when unknown. */
  body:
    "We've refreshed this order. If the tickets are in {provider}, confirm receipt below — " +
    'that is what releases payment to the seller. If not, you can wait or report a problem.',
  here: "They're here",
  notYet: 'Not yet',
  problem: 'Report a problem',
} as const;

export function returnPromptBody(providerName: string | null): string {
  return RETURN_PROMPT.body.replace('{provider}', providerName ? `your ${providerName} account` : 'your ticket account');
}
