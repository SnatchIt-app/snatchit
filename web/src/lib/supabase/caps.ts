/**
 * Capabilities this web build declares to the database on every server-side PostgREST request.
 *
 * proof-disclosure-v1: the build shows "Ticket proof waived by Snatch It" before purchase
 * (listing purchase panel, checkout summary). Migration 156 refuses a bid or Buy Now reservation
 * on a waived listing from clients that don't send it — old native builds can't disclose the
 * waiver, so they can't buy it. Remove a token only together with the UI it vouches for.
 */
export const CLIENT_CAPS_HEADERS = { "x-snatchit-caps": "proof-disclosure-v1" } as const;
