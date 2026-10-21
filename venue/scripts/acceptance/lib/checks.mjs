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

// ---------------------------------------------------------------- session cookie (H2, H3, H6)
/**
 * The @supabase/ssr session cookie (sb-<name>-auth-token, or its .0/.1 chunks) from a CDP cookie list, decoded.
 * null when there is none. The PKCE verifier (sb-<name>-auth-token-code-verifier) is not part of the session.
 */
export function authCookie(cookies) {
  const parts = cookies.filter((c) => /^sb-.+-auth-token(\.\d+)?$/.test(c.name));
  if (!parts.length) return null;
  const base = parts[0].name.replace(/\.\d+$/, "");
  const ordered = parts.filter((c) => c.name === base).concat(parts.filter((c) => c.name.startsWith(`${base}.`)).sort((a, b) => Number(a.name.split(".").pop()) - Number(b.name.split(".").pop())));
  const raw = ordered.map((c) => c.value).join("");
  const json = raw.startsWith("base64-") ? Buffer.from(raw.slice(7), "base64url").toString("utf8") : decodeURIComponent(raw);
  return { base, parts: ordered, session: JSON.parse(json), template: ordered[0] };
}
/**
 * writeAuthCookie replaces the session cookie through CDP, and Chrome can refuse the new one (a Secure cookie for a
 * plain-http host other than localhost). H2 would then see no cookie and pass on "Sign in to continue" without the
 * tampered token ever being presented, and H3 could render the old, unexpired session. true only when the cookie
 * read back (`readBack` = authCookie(...) after the write) holds exactly the session that was written.
 */
export function sessionCookieHolds(readBack, written) {
  return !!readBack && JSON.stringify(readBack.session) === JSON.stringify(written);
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

// ---------------------------------------------------------------- Chrome DevTools port (lib/cdp.mjs)
/** `--cdp-ports <lo>-<hi>` as [lo, hi]; null when the flag is not given. Throws on anything else. */
export function parsePortRange(raw) {
  if (raw === undefined || raw === null) return null;
  const m = /^(\d{4,5})-(\d{4,5})$/.exec(String(raw).trim());
  const [lo, hi] = m ? [Number(m[1]), Number(m[2])] : [NaN, NaN];
  if (!m || lo < 1024 || hi > 65535 || lo > hi) throw new Error(`--cdp-ports must be <lo>-<hi> within 1024-65535, got '${raw}'`);
  return [lo, hi];
}
/**
 * A port in [lo, hi] that `isFree(port)` (async) accepts, each port tried once in random order; throws when none is.
 * cdp.mjs reads Chrome's DevTools endpoint from that port, so a port something already listens on (another
 * session's Chrome would answer /json/version) must never be used.
 */
export async function pickFreePort([lo, hi], isFree) {
  const ports = Array.from({ length: hi - lo + 1 }, (_, i) => lo + i);
  for (let i = ports.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [ports[i], ports[j]] = [ports[j], ports[i]];
  }
  for (const p of ports) if (await isFree(p)) return p;
  throw new Error(`no free port in ${lo}-${hi} for Chrome's DevTools endpoint`);
}
