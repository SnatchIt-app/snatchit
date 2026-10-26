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
 *     never pass as a credential.
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

describe('harness — sample codes cannot pass as credentials', () => {
  it('H1: the dev harness token is three segments that fail the compact-token shape test', () => {
    const h = src('app/_dev/v3-ticket-detail.tsx');
    const m = h.match(/SAMPLE_TOKEN = '([^']+)'/);
    expect(m).not.toBeNull();
    expect(looksLikeCompactToken(m![1])).toBe(false);
    expect(h).toContain('sample caveat');
  });
});
