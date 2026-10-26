/**
 * Primary discovery + event detail screens — source contracts (CONTRACTS C1; lane C, 2026-10-26).
 *
 * Pins, on the real source with comments stripped:
 *   - both routes exist and are registered in the root Stack; neither is on the return-after-sign-in
 *     allowlist (a reviewed list; the C3 checkout package proposes that separately);
 *   - the views decide tier status only through `tierLine` (server `on_sale_now`), show times only
 *     through `whenFromLocal` (venue-local strings, zone named), and show no buy action yet;
 *   - the list never formats a row time in the device zone;
 *   - every failure has the failure screen and 0 rows its own "not available" copy.
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
const src = (p: string) => strip(readFileSync(p, 'utf8'));

describe('routes', () => {
  it('P1: app/events.tsx and app/event/[session].tsx exist and the root Stack registers both', () => {
    expect(src('app/events.tsx')).toContain('export default function');
    expect(src('app/event/[session].tsx')).toContain('export default function');
    const layout = src('app/_layout.tsx');
    expect(layout).toContain('<Stack.Screen name="events" />');
    expect(layout).toContain('<Stack.Screen name="event/[session]" />');
  });

  it('P2: neither route is on the return-after-sign-in allowlist yet', () => {
    const rt = src('src/lib/auth/returnTo.ts');
    expect(rt).not.toMatch(/'event\/\[session\]'|'events'/);
    expect(rt).toContain("{ route: 'listing/[id]', scope: 'public' }");   // witness: the list is still read
  });

  it('P3: the routes read only through the 182 discovery wrappers', () => {
    expect(src('app/event/[session].tsx')).toContain('readPrimarySessionDetail(primarySessionRpc, sessionId, offlineRef.current)');
    expect(src('app/events.tsx')).toContain('readDiscovery(discoveryRpc, offlineRef.current)');
    expect(src('src/lib/primary/discovery.ts')).toContain("supabase.rpc('list_primary_sessions_on_sale')");
    expect(src('src/lib/primary/discovery.ts')).toContain("supabase.rpc('get_primary_session', { p_session_id: sessionId })");
  });
});

describe('views — server facts only', () => {
  const event = src('src/screens/primary/PrimarySessionView.tsx');
  const list = src('src/screens/primary/PrimaryEventsView.tsx');
  const listRoute = src('app/events.tsx');

  it('V1: tier status comes from tierLine; times from whenFromLocal; age from entryRestrictionLine', () => {
    expect(event).toContain('tierLine(t, nowMs)');
    expect(event).toContain('whenFromLocal({');
    expect(event).toContain('entryRestrictionLine(facts.ageRestriction)');
    expect(event).toContain('DISCOVERY_COPY.priceNote');
  });

  it('V2: no buy action exists until the C3 checkout package lands', () => {
    expect(event).not.toMatch(/Buy|Checkout|checkout|reserve_primary_inventory|primary-checkout/);
  });

  it('V3: the list never formats a row time in the device zone — times only through the session facts', () => {
    expect(list).not.toMatch(/whenLine\(|toLocale(Date|Time)?String|new Date\(/);
    expect(listRoute).toContain('whenFromLocal({');
    expect(listRoute).not.toMatch(/whenLine\(/);
  });

  it('V4: failure, not-available and empty states each use their own pinned copy', () => {
    expect(event).toContain('DISCOVERY_COPY.notAvailableTitle');
    expect(event).toMatch(/<ScreenState state=\{load\.failure === 'offline' \? 'offline' : 'error'\}/);
    expect(list).toContain('DISCOVERY_COPY.listEmptyTitle');
    expect(list).toMatch(/<ScreenState state=\{load\.failure === 'offline' \? 'offline' : 'error'\}/);
  });

  it('V5: a failed re-read keeps what is on screen in both routes', () => {
    expect(src('app/event/[session].tsx')).toContain("prev.kind === 'ready' && next.kind === 'failed' ? prev : next");
    expect(listRoute).toContain("prev.kind === 'ready' && next.kind === 'failed' ? prev : next");
  });

  it('V6: the harness marks every render as a sample', () => {
    const h = src('app/_dev/v3-primary.tsx');
    expect((h.match(/sampleCaveat/g) ?? []).length).toBeGreaterThanOrEqual(2);
    expect(h).toContain('not a real event');
  });
});
