/**
 * Ticket detail + QR screen — source contracts (Q02, Q04, Q05, Q07; lane C, 2026-10-26).
 *
 * Pins, on the real source with comments stripped:
 *   - the route exists and is registered in the root Stack; it is NOT in the return-after-sign-in
 *     allowlist (a reviewed list; adding a same_user entry is a separate change);
 *   - the Tickets tab opens the detail from a group card (the only change to that tab);
 *   - the QR is drawn only from a server credential (`state.kind === 'ready'`), with a fixed
 *     black-on-white SVG and the standard quiet zone, and carries an accessibility label;
 *   - the screen binds the entitlement cache to the signed-in account and re-mints on focus;
 *   - no copy on the screen says "no tickets" for a failure, and the sample harness token can
 *     never pass as a credential;
 *   - a code the server withdrew is forgotten by the cache and the page re-reads once; the card
 *     claims nothing ready beside a not_owner / atom_terminal refusal (D2, D3a);
 *   - the complete set of readAll() call sites — no read on a timer (D16);
 *   - a failed orders re-read keeps the last orders answer; with none yet the hint is read_failed,
 *     which is never "no tickets" (D7).
 *
 * Negative controls (run by hand, each must FAIL): drop the dropCredential call (W5); drop the
 * withdrawal re-read (W5, W6); put readAll() in the setInterval callback (W6); show the ready body
 * beside a refusal (W8); set the hint from a failed orders read, or drop the per-account reset (O1).
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import { looksLikeCompactToken } from '@/src/lib/tickets/entitlement';

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
const src = (p: string) => strip(readFileSync(p, 'utf8'));

describe('route and entry point', () => {
  it('T1: app/ticket/[session].tsx exists and the root Stack registers it', () => {
    expect(src('app/ticket/[session].tsx')).toContain('export default function');
    expect(src('app/_layout.tsx')).toContain('<Stack.Screen name="ticket/[session]" />');
  });

  it('T2: the route is not on the return-after-sign-in allowlist (reviewed list unchanged)', () => {
    const rt = src('src/lib/auth/returnTo.ts');
    expect(rt).not.toContain("'ticket/[session]'");
    expect(rt).toContain("{ route: 'my-listings', scope: 'same_user' }");   // witness: the list is still read
  });

  it('T3: the Tickets tab opens the detail from a group card and changes nothing else about its read', () => {
    const t = src('app/(tabs)/tickets.tsx');
    expect(t).toContain('onPress={() => router.push(`/ticket/${item.event_session_id}`)}');
    expect(t).toContain('fetchMyTickets(');
    const card = src('src/components/tickets/TicketEventGroup.tsx');
    expect(card).toContain('onPress?: () => void');
    expect(card).toContain('accessibilityRole="button"');
  });
});

describe('TicketQR — fixed contrast, quiet zone, accessible', () => {
  const qr = src('src/components/tickets/TicketQR.tsx');

  it('Q1: renders the token through chooseQrRender (C-R2 pitch floor) and qrSvg into expo-image as an SVG data URI', () => {
    expect(qr).toContain("from '@/src/lib/qr/qrLayout'");
    expect(qr).toContain('chooseQrRender(token, available - 2 * CARD_MARGIN)');
    expect(qr).toContain('qrSvg(r.matrix)');
    expect(qr).toContain("'data:image/svg+xml;utf8,'");
    expect(qr).toContain("from 'expo-image'");
    expect(qr).toContain('cachePolicy="none"');
  });

  it('Q2: the symbol never takes theme colours — no palette in the file, white field pinned', () => {
    expect(qr).not.toContain('useTheme');
    expect(qr).not.toContain('palette');
    expect(qr).toContain("backgroundColor: '#FFFFFF'");
  });

  it('Q2b: C-R3 — the rounded card sits outside the symbol: margin ≥ the depth a radius cuts into a corner, no clipping of the image', () => {
    const CARD_MARGIN = Number(/export const CARD_MARGIN = (\d+(?:\.\d+)?);/.exec(qr)?.[1]);
    const CARD_RADIUS = Number(/export const CARD_RADIUS = (\d+(?:\.\d+)?);/.exec(qr)?.[1]);
    expect(CARD_RADIUS).toBeGreaterThan(0);
    expect(CARD_MARGIN).toBeGreaterThanOrEqual(CARD_RADIUS * (1 - Math.SQRT1_2));
    expect(qr).toContain('padding: CARD_MARGIN');
    expect(qr).not.toContain("overflow: 'hidden'");
  });

  it('Q3: the image is labelled for VoiceOver and is not decorative', () => {
    expect(qr).toContain('accessibilityRole="image"');
    expect(qr).toContain('accessibilityLabel={label}');
  });
});

describe('EntitlementCard and the view — a code only from a server credential', () => {
  const card = src('src/components/tickets/EntitlementCard.tsx');
  const view = src('src/screens/tickets/TicketDetailView.tsx');

  it('E1: the QR is rendered only when the credential state is ready', () => {
    expect(card).toMatch(/credential\.kind === 'ready'\s*\?\s*\(?\s*<TicketQR/);
    expect(card).not.toMatch(/<TicketQR[^>]*token=\{[^}]*(sample|fixture|placeholder)/i);
  });

  it('E2: a non-ready atom never asks for a code', () => {
    expect(card).toContain('canRequestCredential(display)');
  });

  it('E3: every refusal and load failure uses the pinned copy, never ad-hoc text or raw server text', () => {
    expect(card).toContain('CREDENTIAL_COPY[');
    expect(view).toContain('DETAIL_COPY.');
    expect(view + card).not.toMatch(/No tickets(?! for this event)/);
    expect(view + card).not.toContain('error.message');
  });

  it('E4: the route binds the cache owner, watches sign-out, and re-mints on focus; tokens are never persisted', () => {
    const route = src('app/ticket/[session].tsx');
    expect(route).toContain('bindEntitlementOwner(');
    expect(route).toContain('watchEntitlementSignOut()');
    expect(route).toContain('useFocusEffect(');
    expect(route).not.toContain('AsyncStorage');
    expect(route).not.toContain('SecureStore');
  });

  it('E4c: the page re-reads on focus and pull ONLY — the focus effect depends on nothing a read changes (C33 run, 2026-10-29)', () => {
    // React Navigation's useFocusEffect re-runs its effect whenever the callback changes while focused. With `load`
    // in the deps, every successful read made a new callback → another read: a continuous loop (~2.5 reads/s on
    // C33) that withdrew a code within a poll of admission. `load` is read through a ref instead.
    const route = src('app/ticket/[session].tsx');
    const m = route.match(/useFocusEffect\(\s*useCallback\(\(\) => \{([\s\S]*?)\}, \[([^\]]*)\]\)/);
    expect(m).not.toBeNull();
    const [, body, deps] = m!;
    expect(deps.split(',').map((d) => d.trim())).toEqual(['userId', 'sessionId', 'readAll', 'sweepStale']);
    expect(body).toContain('loadRef.current');
    expect(body).not.toMatch(/\bload\.kind\b/);
    expect(route).toMatch(/const loadRef = useRef<[^>]+>\(\{ kind: 'loading' \}\);/);
    expect(route).toContain('useEffect(() => { loadRef.current = load; }, [load]);');
  });

  it('E4d: the focus effect\'s own dependencies are stable — readAll and sweepStale change on nothing a read changes (E N1, 2026-10-29)', () => {
    // E4c pins the focus effect's deps; this pins the other half of the invariant. If readAll or sweepStale gained a
    // dependency that a read updates (credentials, load, orders…), they would become new functions per read and the
    // focus effect would re-run per read again — the continuous re-read loop, with E4c still green.
    const route = src('app/ticket/[session].tsx');
    const deps = (re: RegExp) => {
      const m = route.match(re);
      expect(m, String(re)).not.toBeNull();
      return m![1].split(',').map((d) => d.trim()).filter(Boolean);
    };
    expect(deps(/const readAll = useCallback\(async \(\) => \{[\s\S]*?\n  \}, \[([^\]]*)\]\);/)).toEqual(['userId', 'sessionId', 'sweepStale']);
    expect(deps(/const sweepStale = useCallback\(\(atoms: MyTicketAtom\[\]\) => \{[\s\S]*?\n  \}, \[([^\]]*)\]\);/)).toEqual([]);
  });

  it('E4b: C-R4 + C5 — the route decides refresh outcomes with afterMint, keeps a code visible while refreshing, and reads orders + session facts', () => {
    const route = src('app/ticket/[session].tsx');
    expect(route).toContain('afterMint(latest, r, now,');
    expect(route).toMatch(/if \(before\.kind === 'ready'\) setRefreshing/);
    expect(route).toContain('issuanceHint(orderRows)');
    expect(route).toContain('readPrimarySession(sessionRpc, sessionId)');
  });

  it('E5: the stale rule is the server TTL on a monotonic clock, never Date.now() against not_after', () => {
    const route = src('app/ticket/[session].tsx');
    expect(route).toContain('credentialStale(');
    expect(route).not.toMatch(/Date\.parse\([^)]*not_after/);
  });
});

describe('withdrawal and read call sites — a withdrawn code is forgotten, one re-read, no timer read (D2, D3a, D16)', () => {
  const route = src('app/ticket/[session].tsx');
  const card = src('src/components/tickets/EntitlementCard.tsx');
  const block = (re: RegExp) => {
    const m = route.match(re);
    expect(m, String(re)).not.toBeNull();
    return { body: m![1], deps: (m![2] ?? '').split(',').map((d) => d.trim()).filter(Boolean) };
  };
  const reads = (s: string) => (s.match(/\breadAll\(\)/g) ?? []).length;
  const mint = () => block(/const mint = useCallback\(async \(atomId: string\) => \{([\s\S]*?)\n  \}, \[([^\]]*)\]\);/);
  const mount = () => block(/useEffect\(\(\) => \{\n    if \(authLoading\) return;([\s\S]*?)\n  \}, \[([^\]]*)\]\);/);
  const focus = () => block(/useFocusEffect\(\s*useCallback\(\(\) => \{([\s\S]*?)\}, \[([^\]]*)\]\)/);
  const onRefresh = () => block(/async function onRefresh\(\) \{([\s\S]*?)\n  \}/);

  it('W5: on a withdrawing refusal mint forgets the cached code, then re-reads once — after the generation check, success-only store kept', () => {
    const { body } = mint();
    expect(body).toMatch(/if \(!r\.ok && withdrawsCode\(r\.reason\)\) \{\s*dropCredential\(userId, atomId\);\s*if \(!withdrawReadRef\.current\) withdrawReadRef\.current = readAll\(\)\.finally\(\(\) => \{ withdrawReadRef\.current = null; \}\);\s*\}/);
    expect(body.indexOf('withdrawsCode(')).toBeGreaterThan(body.indexOf('if (gen !== entitlementGeneration()) return;'));
    expect(body).toContain('if (r.ok) storeCredential(userId, atomId, r.credential, now);');
    expect(reads(body)).toBe(1);
  });

  it('W6: readAll() is called from exactly four places — mount, focus (outside the timer), pull, the withdrawal — and the timer only sweeps', () => {
    const f = focus().body;
    const timer = f.match(/setInterval\(\(\) => \{([\s\S]*?)\}, TTL_SWEEP_MS\)/);
    expect(timer).not.toBeNull();
    expect(timer![1]).toContain('sweepStale(');
    expect(timer![1]).not.toMatch(/readAll|\.rpc\(|mint|Rpc\b|invoke|read[A-Z]/);
    expect(reads(mount().body)).toBe(1);
    expect(reads(f.replace(timer![0], ''))).toBe(1);
    expect(onRefresh().body).toContain('await readAll();');
    expect(reads(onRefresh().body)).toBe(1);
    expect(reads(mint().body)).toBe(1);
    expect(reads(route)).toBe(4);
    expect(route).not.toMatch(/setTimeout\(/);
    // Passing readAll by name (setInterval(readAll, …), .then(readAll), a listener) is a read too: every token is
    // accounted for — the declaration, the four calls, and three dependency lists (mint, mount, focus) — and the
    // focus effect's sweep is the route's only timer (review of 57461714).
    expect((route.match(/\breadAll\b/g) ?? []).length).toBe(8);
    expect((route.match(/\bsetInterval\(/g) ?? []).length).toBe(1);
    expect((route.match(/\breadAll\(/g) ?? []).length).toBe(4);
  });

  it('W7: the mount effect, mint and arrival depend on nothing a read changes, and arrival never re-mints an atom that has a credential state', () => {
    expect(mount().deps).toEqual(['authLoading', 'userId', 'sessionId', 'readAll', 'sweepStale']);
    expect(mint().deps).toEqual(['userId', 'readAll']);
    const arrival = block(/useEffect\(\(\) => \{\n    if \(load\.kind !== 'ready'\) return;([\s\S]*?)\n  \}, \[([^\]]*)\]\);/);
    expect(arrival.deps).toEqual(['load', 'credentials', 'mint']);
    expect(arrival.body).toContain("if (entitlementDisplay(a) === 'ready' && !credentials[a.ticket_atom_id]) void mint(a.ticket_atom_id);");
    expect(reads(arrival.body)).toBe(0);
  });

  it('W8: the card takes its badge, tone, label and body from cardDisplay — never the atom display alone — and reuses refusesTicket', () => {
    expect(card).toContain('const shown = cardDisplay(display, credential);');
    expect(card).toContain('const copy = ENTITLEMENT_COPY[shown];');
    expect(card).toContain('<Badge label={copy.badge} tone={TONE[shown]} />');
    expect(card).toContain('accessibilityLabel={`${heading}, ${atom.ticket_type_name}, ${copy.badge}`}');
    expect(card).not.toMatch(/ENTITLEMENT_COPY\[display\]|TONE\[display\]|ENTITLEMENT_COPY\.ready/);
    expect(card).toContain('refusesTicket(credential.reason)');
    expect(card).not.toMatch(/'not_owner'|'atom_terminal'/);
  });
});

describe('orders hint — a failed orders re-read keeps the last answer; none yet is read_failed (D7)', () => {
  const route = src('app/ticket/[session].tsx');

  it('O1: the hint and order lines are written only from a successful orders read, or reset per account/session before its first read', () => {
    expect(route).toContain("const [hint, setHint] = useState<IssuanceHint>('read_failed');");
    expect(route.match(/\bsetHint\(/g)).toHaveLength(2);
    expect(route.match(/\bsetOrders\(/g)).toHaveLength(2);
    expect(route).toMatch(/if \(orderRows\) \{\s*setHint\(issuanceHint\(orderRows\)\);\s*setOrders\(orderRows\.map\(orderStatusLine\)\);\s*\}/);
    const mount = route.match(/useEffect\(\(\) => \{\n    if \(authLoading\) return;([\s\S]*?)\n  \}, \[([^\]]*)\]\);/);
    expect(mount).not.toBeNull();
    const body = mount![1];
    expect(body).toContain("setHint('read_failed');");
    expect(body).toContain('setOrders([]);');
    expect(body.indexOf("setHint('read_failed');")).toBeLessThan(body.indexOf('void readAll();'));
  });
});

describe('harness — sample codes cannot pass as credentials', () => {
  it('H1: the dev harness token is three segments that fail the compact-token shape test', () => {
    const h = src('app/_dev/v3-ticket-detail.tsx');
    const m = h.match(/SAMPLE_TOKEN = '([^']+)'/);
    expect(m).not.toBeNull();
    expect(looksLikeCompactToken(m![1])).toBe(false);
    expect(h).toContain('sample caveat');
  });
});
