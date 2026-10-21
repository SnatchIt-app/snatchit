// Pure decision helpers for accept.mjs: no I/O, no target, no browser of their own. They live here and not
// in accept.mjs because accept.mjs parses argv and builds a target when it is imported; this module can be
// imported by tests/acceptance-kit-markers.test.tsx and run offline.

// ---------------------------------------------------------------- page reads
/**
 * v2 streams every venue screen behind src/app/o/[org]/v/[venue]/loading.tsx. A client-side navigation (the
 * redirect after sign-in) commits the new URL while that fallback is still showing, so a page is read only
 * once the element matching `selector` is gone. `page` is a lib/cdp.mjs page (waitFor resolves false on timeout).
 * A timeout throws: the phase then records a FAIL ("phase completed without error") and stops, instead of reading
 * the skeleton as if the page had rendered, where a negative-only check would pass vacuously.
 */
export async function waitSettled(page, selector, timeoutMs) {
  if (await page.waitFor(`!document.querySelector(${JSON.stringify(selector)})`, timeoutMs)) return true;
  let at = "an unknown page";
  try {
    at = await page.url();
  } catch {}
  throw new Error(`route loading state (${selector}) still showing after ${timeoutMs} ms at ${at}: the page never rendered, so nothing on it can be checked`);
}

// ---------------------------------------------------------------- P1: no role claimed without a grant
// Role labels the app shows only once it has verified a grant (capabilities strip, account card), matched in any case:
// the kit reads innerText, which applies CSS text-transform, so a leak inside an uppercase-styled element reads
// "VENUE MANAGER". v2's grant-less denial names roles without claiming one (components/ui/State.tsx DeniedState,
// grantedBy): that one sentence is removed first, in any case and any whitespace, and nothing else is exempt.
export const DENIAL_ROLE_SENTENCE = "A venue manager or an organization owner can give you access";
export const ROLE_LABEL_CLAIMED = /Venue manager|Org owner|Capabilities come from your grants: (Venue|Org)/i;
const DENIAL_ROLE_SENTENCE_RE = new RegExp(DENIAL_ROLE_SENTENCE.split(" ").join("\\s+"), "gi");
/** true when the page text claims a role (P1 FAILs on true for a grant-less caller). */
export function roleLabelClaimed(text) {
  return ROLE_LABEL_CLAIMED.test(String(text).replace(DENIAL_ROLE_SENTENCE_RE, " "));
}

// ---------------------------------------------------------------- migration ledger
// venue_api read views = registry 159: 20261021120000_venue_api_read_views (pgTAP 226), a re-timestamp of the
// pre-registry 20260910120000 with the same SQL body. That old version is retired: it was applied nowhere, and a
// ledger that holds it means someone applied the wrong file, so the kit stops there (fails closed if unreported).
const RETIRED = "20260910120000";

/** Ledger checks of the preflight phase, as [id, ok, detail]. `snap` is the preflight.sql json. */
export function preflightLedgerChecks(snap, targetName) {
  if (snap.ledger_count === null) return [["local replay: no migration ledger to inspect (expected)", targetName === "local", ""]];
  return [
    ["076-092 recorded in the ledger, no duplicate versions", snap.ledger_076_092 === 17 && snap.ledger_dupes === 0, { ledger_count: snap.ledger_count, tip: snap.ledger_tip_timestamp, dupes: snap.ledger_dupes }],
    [`retired venue_api version ${RETIRED} absent from the ledger (superseded by registry 159, 20261021120000)`, snap.ledger_has_retired_venue_api === 0, { retired_rows: snap.ledger_has_retired_venue_api }],
  ];
}

/** Ledger checks of the verify-apply phase (sandbox only), as [id, ok, detail]. `v` is the verify-apply.sql json. */
export function verifyApplyLedgerChecks(v) {
  return [
    ["ledger row 20261021120000 = venue_api_read_views with 24 statements", v.ledger_row_statements === 24 && v.ledger_row_name === "venue_api_read_views", { name: v.ledger_row_name, statements: v.ledger_row_statements }],
    [`retired ${RETIRED} still absent from the ledger`, v.ledger_retired_row === 0, { retired_rows: v.ledger_retired_row }],
  ];
}
