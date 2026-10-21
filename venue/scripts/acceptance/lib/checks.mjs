// Pure decision helpers for accept.mjs: no I/O, no target, no browser of their own. They live here and not
// in accept.mjs because accept.mjs parses argv and builds a target when it is imported; this module can be
// imported by tests/acceptance-kit-markers.test.tsx and run offline.

// ---------------------------------------------------------------- page reads
/**
 * v2 streams every venue screen behind src/app/o/[org]/v/[venue]/loading.tsx. A client-side navigation (the
 * redirect after sign-in) commits the new URL while that fallback is still showing, so a page is read only
 * once the element matching `selector` is gone. `page` is a lib/cdp.mjs page (waitFor resolves false on timeout).
 */
export async function waitSettled(page, selector, timeoutMs) {
  return page.waitFor(`!document.querySelector(${JSON.stringify(selector)})`, timeoutMs);
}

// ---------------------------------------------------------------- P1: no role claimed without a grant
// Role labels the app shows only once it has verified a grant (capabilities strip, account card). Case-sensitive on
// purpose: v2's denial itself says "A venue manager or an organization owner can give you access", which claims nothing.
export const ROLE_LABEL_CLAIMED = /Capabilities come from your grants: (Venue|Org)|\bVenue manager\b|\bOrg owner\b/;
/** true when the page text claims a role (P1 FAILs on true for a grant-less caller). */
export function roleLabelClaimed(text) {
  return ROLE_LABEL_CLAIMED.test(String(text));
}

// ---------------------------------------------------------------- migration ledger
/** Ledger checks of the preflight phase, as [id, ok, detail]. `snap` is the preflight.sql json. */
export function preflightLedgerChecks(snap, targetName) {
  if (snap.ledger_count === null) return [["local replay: no migration ledger to inspect (expected)", targetName === "local", ""]];
  return [["076-092 recorded in the ledger, no duplicate versions", snap.ledger_076_092 === 17 && snap.ledger_dupes === 0, { ledger_count: snap.ledger_count, tip: snap.ledger_tip_timestamp, dupes: snap.ledger_dupes }]];
}

/** Ledger checks of the verify-apply phase (sandbox only), as [id, ok, detail]. `v` is the verify-apply.sql json. */
export function verifyApplyLedgerChecks(v) {
  return [["ledger row 20260910120000 = venue_api_read_views with 24 statements", v.ledger_row_statements === 24 && v.ledger_row_name === "venue_api_read_views", { name: v.ledger_row_name, statements: v.ledger_row_statements }]];
}
