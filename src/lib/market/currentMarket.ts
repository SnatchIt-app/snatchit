/**
 * src/lib/market/currentMarket.ts — the market (city) the app is showing.
 *
 * The Home header renders ONE city label and it comes from here, so switching
 * markets later is a value change, not a header redesign. Today the product is
 * Miami-only: every neighbourhood in src/constants/neighborhoods.ts is a Miami
 * one, so `miami` is the current market.
 *
 * FUTURE HOOK POINT (not built here, deliberately): when city switching becomes a
 * real product capability, replace `CURRENT_MARKET` with state (a context/store
 * hydrated from the user's selection or location) and have `useCurrentMarket()`
 * read it. Nothing else needs to change — the header, and anything else that
 * needs the label, already reads through this module. No backend, no city-
 * selection UI, and no market persistence exists yet.
 */

export interface Market {
  /** Stable id for future selection/persistence. */
  id: string;
  /** Display label. Rendered through the `micro` type token, which uppercases. */
  label: string;
}

export const MIAMI: Market = { id: 'miami', label: 'Miami' };

/** The market the app is currently operating in. */
export const CURRENT_MARKET: Market = MIAMI;

/**
 * The market to display. A hook (not a bare constant) so that when real city
 * switching lands, call sites do not change shape.
 */
export function useCurrentMarket(): Market {
  return CURRENT_MARKET;
}
