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
  it('P1: the events, event and primary-checkout routes exist and the root Stack registers them', () => {
    expect(src('app/events.tsx')).toContain('export default function');
    expect(src('app/event/[session].tsx')).toContain('export default function');
    expect(src('app/primary-checkout/[session].tsx')).toContain("export { default } from '@/src/screens/primary/PrimaryCheckoutRoute'");
    const layout = src('app/_layout.tsx');
    expect(layout).toContain('<Stack.Screen name="events" />');
    expect(layout).toContain('<Stack.Screen name="event/[session]" />');
    expect(layout).toContain('<Stack.Screen name="primary-checkout/[session]" />');
  });

  it('P2: neither route is on the return-after-sign-in allowlist yet', () => {
    const rt = src('src/lib/auth/returnTo.ts');
    expect(rt).not.toMatch(/'event\/\[session\]'|'events'|'primary-checkout/);
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
    // A's all-in rule: the view renders only tierLine's price (all-in), and never the face field.
    expect(event).not.toContain('price_minor');
    expect(event).toMatch(/line\.price \? /);
  });

  it('V2: only an available tier can be chosen; the view computes no price and never calls payment code', () => {
    expect(event).toContain('disabled={!line.available}');
    expect(event).toContain("const selected = props.selectedTierId === id && line.available;");
    expect(event).not.toMatch(/reserve_primary|primary-checkout|functions\.invoke|price_minor|buyer_fee|fee_bps|\* 1\./);
    const route = src('app/event/[session].tsx');
    expect(route).toContain("router.push({ pathname: '/primary-checkout/[session]', params: { session: sessionId, tt: selectedTierId, qty: String(quantity) } })");
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

describe('primary checkout screen — a payments surface (A reviews)', () => {
  const native = src('src/screens/primary/PrimaryCheckoutEntry.native.tsx');
  const web = src('src/screens/primary/PrimaryCheckoutEntry.tsx');
  const view = src('src/screens/primary/PrimaryCheckoutView.tsx');

  it('K1: the web entry never imports Stripe; the native entry uses the same SDK hook as the resale checkout', () => {
    expect(web).not.toContain('@stripe/stripe-react-native');
    expect(native).toContain("from '@stripe/stripe-react-native'");
    expect(native).toContain('useStripe()');
  });

  it('K2: hold first, then the first quote WITHOUT a shown total; a price change re-quotes with the server total it showed', () => {
    expect(native).toContain('reservePrimaryTier({');
    expect(native).toContain('await quoteAndPrepare(null);');
    expect(native).toContain("quoteAndPrepare(state.kind === 'price_changed' ? state.serverTotalMinor : null)");
  });

  it('K3: an intent Stripe already reports paid is not shown the sheet again; completion routes to the ticket page, never a success screen', () => {
    expect(native).toContain('if (intentAlreadyPaid(existing.paymentIntent?.status)) { submitted(params.sessionId); return; }');
    expect(native).toContain("router.replace(`/ticket/${sessionId}`)");
    expect(native).toContain("if (outcome === 'completed') { submitted(params.sessionId); return; }");
    expect(view + native).not.toMatch(/Payment successful|You're in|Tickets confirmed|Order complete/i);
  });

  it('K3b: a quote refused as already_paid goes to the ticket page, like an intent Stripe reports paid — never "try again"', () => {
    expect(native).toContain("if (result.reason === 'already_paid') { submitted(params.sessionId); return; }");
  });

  it('K4: one attempt id per purchase, kept in the route params; the 3-D Secure return URL carries it; Pay is latched', () => {
    expect(native).toContain('router.setParams({ attempt: attemptId })');
    expect(native).toContain('returnURL: buildPrimaryReturnURL({');
    expect(native).toContain('if (state.kind !== \'review\' || !state.sheetReady || payingRef.current || !params.ok) return;');
  });

  it('K5: the review headline is the all-in total; tickets and fee are itemised beneath it', () => {
    expect(view).toMatch(/PRIMARY_CHECKOUT_COPY\.totalLabel[\s\S]*formatUsd\(q\.totalMinor\)/);
    expect(view).toContain('PRIMARY_CHECKOUT_COPY.faceLabel} ${formatUsd(q.faceMinor)}');
    expect(view).toContain('`${PRIMARY_CHECKOUT_COPY.payAction} ${formatUsd(q.totalMinor)}`');
  });

  it('K6: no gated payments file is imported or touched by the primary screens', () => {
    for (const f of [native, web, view]) {
      expect(f).not.toMatch(/lib\/payments'|lib\/checkout\/(setupDecision|payControl|holdState)'/);
    }
  });
});

describe('entry point — A’s default: "Events" in the Explore header', () => {
  it('E1: the Explore header links to /events (not in harness renders); Home is untouched', () => {
    const explore = src('app/(tabs)/explore.tsx');
    expect(explore).toContain("onPress={() => router.push('/events')}");
    expect(explore).toContain('accessibilityLabel="Browse events"');
    expect(src('app/(tabs)/home.tsx')).not.toContain("'/events'");
  });
});
