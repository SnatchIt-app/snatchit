/**
 * app/_dev/v3-ticket-detail.tsx — rendering harness for the ticket detail + entry code screen.
 *
 * Renders the REAL `TicketDetailView` from literals, so every state can be captured at every type
 * size and appearance without a server, a signed-in account or an issued ticket. It proves layout,
 * copy, contrast and the QR's quiet zone on a phone. It proves NOTHING about the reads, the edge
 * function, ownership or admission — and the code it draws is a sample that no scanner can accept:
 * `SAMPLE_TOKEN` is not three base64url segments, so it fails SCANNER-CONTRACT-v1 §1 at the
 * decoder, and the screen carries the sample caveat on every variant.
 *
 * NO WRITES. Nothing here reads or writes a server. Gated like every `_dev` route.
 *
 *   /_dev/v3-ticket-detail?variant=ready|two|used|revoked|held|minting|refused|refresh-kept
 *     |awaiting|processing|issuing|payment-failed|elsewhere|refunded|inconsistent|offline|error|signedout
 */
import { Redirect, useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { REFRESH_KEPT_NOTE, type CredentialState, type DetailState, type MyTicketAtom } from '@/src/lib/tickets/entitlement';
import type { SessionFacts } from '@/src/lib/tickets/entitlementReads';
import { orderStatusLine, type OrderLine, type PrimaryOrderRow } from '@/src/lib/tickets/primaryOrders';
import { TicketDetailView } from '@/src/screens/tickets/TicketDetailView';

declare const __DEV__: boolean;

/** A visibly fake code: spaces and dashes keep it outside the compact-token shape. */
const SAMPLE_TOKEN = 'SAMPLE.NOT A TICKET — DO NOT SCAN — sample caveat applies.SAMPLE';

/** Shaped like D's 182 get_primary_session row; a sample event, not a booked venue or date. */
const FACTS: SessionFacts = {
  title: 'Sample pop-up (not a real event)',
  venueName: 'Venue to be announced',
  address: null,
  sessionLabel: null,
  timezone: 'America/New_York',
  startsAtLocal: '2026-11-30 23:00',
  doorsAtLocal: '2026-11-30 22:00',
  startsAt: '2026-12-01T04:00:00Z',
  ageRestriction: '21_plus',
};

const atom = (serial: number, over: Partial<MyTicketAtom> = {}): MyTicketAtom => ({
  ticket_atom_id: `0000000${serial}-0000-4000-8000-00000000000${serial}`,
  serial_no: serial,
  ticket_type_id: 'fixture-tt',
  ticket_type_name: 'GA',
  state: 'active',
  resale_state: 'none',
  credential_version: 1,
  issued_at: '2026-11-20T18:00:00Z',
  ...over,
});

const READY: CredentialState = {
  kind: 'ready',
  credential: { token: SAMPLE_TOKEN, credential_version: 1, signing_key_id: 'fixture', not_after: '2026-12-01T06:00:00Z', ttl_seconds: 14400 },
  receivedAtMs: 0,
};

const order = (over: Partial<PrimaryOrderRow>): OrderLine => orderStatusLine({
  order_id: 'fixture-order-1', status: 'pending', total_minor: 2200, currency: 'USD',
  created_at: '2026-11-20T18:00:00Z', atoms_issued: 0, payment_state: 'none', ...over,
});

interface Fixture {
  state: DetailState;
  credentials: Record<string, CredentialState>;
  orders: OrderLine[];
  refreshing?: Record<string, boolean>;
  notes?: Record<string, string | null>;
}

function fixtureFor(variant: string | undefined): Fixture {
  const a1 = atom(1);
  const a2 = atom(2);
  const paid = (n: number) => [order({ status: 'paid', atoms_issued: n, payment_state: 'succeeded' })];
  switch (variant) {
    case 'two': return { state: { kind: 'atoms', atoms: [a1, a2] }, credentials: { [a1.ticket_atom_id]: READY, [a2.ticket_atom_id]: READY }, orders: paid(2) };
    case 'used': return { state: { kind: 'atoms', atoms: [atom(1, { state: 'scanned' })] }, credentials: {}, orders: paid(1) };
    case 'revoked': return { state: { kind: 'atoms', atoms: [atom(1, { state: 'voided' })] }, credentials: {}, orders: [order({ status: 'refunded', atoms_issued: 1, payment_state: 'succeeded' })] };
    case 'held': return { state: { kind: 'atoms', atoms: [atom(1, { resale_state: 'listed' })] }, credentials: {}, orders: paid(1) };
    case 'minting': return { state: { kind: 'atoms', atoms: [a1] }, credentials: { [a1.ticket_atom_id]: { kind: 'minting' } }, orders: paid(1) };
    case 'refused': return { state: { kind: 'atoms', atoms: [a1] }, credentials: { [a1.ticket_atom_id]: { kind: 'refused', reason: 'signing_unavailable' } }, orders: paid(1) };
    case 'refresh-kept': return {
      state: { kind: 'atoms', atoms: [a1] }, credentials: { [a1.ticket_atom_id]: READY }, orders: paid(1),
      notes: { [a1.ticket_atom_id]: REFRESH_KEPT_NOTE },
    };
    case 'awaiting': return { state: { kind: 'awaiting_confirmation' }, credentials: {}, orders: [order({})] };
    case 'processing': return { state: { kind: 'payment_processing' }, credentials: {}, orders: [order({ payment_state: 'processing' })] };
    case 'issuing': return { state: { kind: 'pending_issuance' }, credentials: {}, orders: [order({ payment_state: 'succeeded' })] };
    case 'payment-failed': return { state: { kind: 'payment_failed' }, credentials: {}, orders: [order({ payment_state: 'failed' })] };
    case 'elsewhere': return { state: { kind: 'not_on_account' }, credentials: {}, orders: paid(2) };
    case 'refunded': return { state: { kind: 'empty' }, credentials: {}, orders: [order({ status: 'refunded', atoms_issued: 1, payment_state: 'succeeded' }), order({ order_id: 'fixture-order-2', status: 'cancelled' })] };
    case 'inconsistent': return { state: { kind: 'inconsistent' }, credentials: {}, orders: [] };
    case 'offline': return { state: { kind: 'failed', failure: 'offline' }, credentials: {}, orders: [] };
    case 'error': return { state: { kind: 'failed', failure: 'unavailable' }, credentials: {}, orders: [] };
    case 'signedout': return { state: { kind: 'failed', failure: 'signed_out' }, credentials: {}, orders: [] };
    default: return { state: { kind: 'atoms', atoms: [a1] }, credentials: { [a1.ticket_atom_id]: READY }, orders: paid(1) };
  }
}

export default function V3TicketDetailHarness() {
  const { variant } = useLocalSearchParams<{ variant?: string }>();
  const [pullRefreshing, setPullRefreshing] = useState(false);
  const fixture = useMemo(() => fixtureFor(variant), [variant]);
  if (!(IS_SANDBOX_BUILD || __DEV__)) return <Redirect href="/(tabs)/home" />;
  const signedOut = fixture.state.kind === 'failed' && fixture.state.failure === 'signed_out';
  return (
    <TicketDetailView
      group={null}
      facts={signedOut ? null : FACTS}
      state={fixture.state}
      orders={fixture.orders}
      credentials={fixture.credentials}
      refreshing={fixture.refreshing ?? {}}
      refreshNotes={fixture.notes ?? {}}
      pullRefreshing={pullRefreshing}
      onRefresh={() => { setPullRefreshing(true); setTimeout(() => setPullRefreshing(false), 400); }}
      onShowCode={() => {}}
      onEncodeFailure={() => {}}
      onSignIn={() => {}}
      sampleCaveat
    />
  );
}
