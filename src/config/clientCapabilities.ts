/**
 * src/config/clientCapabilities.ts — what this build can show, told to the server on every request.
 *
 * Builds 25/27 cannot show the owner proof-waiver disclosure (migration 156). The server therefore refuses a
 * bid or a Buy Now reservation on a waived listing unless the request says the app can show it (owner via A,
 * 2026-10-15). This build shows the disclosure on the listing, the bid screen and the checkout pay face, and
 * withholds Pay until it can, so it declares `proof-disclosure-v1`. Space-separated tokens; add, never rename.
 */
export const CLIENT_CAPS_HEADER = 'x-snatchit-caps';
export const CLIENT_CAPS = ['proof-disclosure-v1'] as const;
export const clientCapsHeaders: Record<string, string> = { [CLIENT_CAPS_HEADER]: CLIENT_CAPS.join(' ') };
