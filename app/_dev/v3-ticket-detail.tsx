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
 *   /_dev/v3-ticket-detail?variant=ready|two|used|revoked|held|pending|processing|inconsistent
 *                                  |offline|error|signedout|minting|refused
 */
import { Redirect, useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import type { CredentialState, DetailState, MyTicketAtom } from '@/src/lib/tickets/entitlement';
import { TicketDetailView } from '@/src/screens/tickets/TicketDetailView';

declare const __DEV__: boolean;

/** A visibly fake code: spaces and dashes keep it outside the compact-token shape. */
const SAMPLE_TOKEN = 'SAMPLE.NOT A TICKET — DO NOT SCAN — sample caveat applies.SAMPLE';

const GROUP = {
  event_title: 'Snatch It Pop-Up',
  starts_at: '2026-12-01T04:00:00Z',   // 11:00 PM EST on Nov 30
  doors_at: '2026-12-01T03:00:00Z',    // Doors 10:00 PM EST
  venue_name: 'Venue to be announced',
  session_label: null,
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
  credential: { token: SAMPLE_TOKEN, credential_version: 1, signing_key_id: 'fixture', not_after: '2026-12-01T06:00:00Z', ttl_seconds: 900 },
  receivedAtMs: 0,
};

function fixtureFor(variant: string | undefined): { state: DetailState; credentials: Record<string, CredentialState> } {
  const a1 = atom(1);
  const a2 = atom(2);
  switch (variant) {
    case 'two': return { state: { kind: 'atoms', atoms: [a1, a2] }, credentials: { [a1.ticket_atom_id]: READY, [a2.ticket_atom_id]: READY } };
    case 'used': return { state: { kind: 'atoms', atoms: [atom(1, { state: 'scanned' })] }, credentials: {} };
    case 'revoked': return { state: { kind: 'atoms', atoms: [atom(1, { state: 'voided' })] }, credentials: {} };
    case 'held': return { state: { kind: 'atoms', atoms: [atom(1, { resale_state: 'listed' })] }, credentials: {} };
    case 'pending': return { state: { kind: 'pending_issuance' }, credentials: {} };
    case 'processing': return { state: { kind: 'payment_processing' }, credentials: {} };
    case 'inconsistent': return { state: { kind: 'inconsistent' }, credentials: {} };
    case 'offline': return { state: { kind: 'failed', failure: 'offline' }, credentials: {} };
    case 'error': return { state: { kind: 'failed', failure: 'unavailable' }, credentials: {} };
    case 'signedout': return { state: { kind: 'failed', failure: 'signed_out' }, credentials: {} };
    case 'minting': return { state: { kind: 'atoms', atoms: [a1] }, credentials: { [a1.ticket_atom_id]: { kind: 'minting' } } };
    case 'refused': return { state: { kind: 'atoms', atoms: [a1] }, credentials: { [a1.ticket_atom_id]: { kind: 'refused', reason: 'signing_unavailable' } } };
    default: return { state: { kind: 'atoms', atoms: [a1] }, credentials: { [a1.ticket_atom_id]: READY } };
  }
}

export default function V3TicketDetailHarness() {
  const { variant } = useLocalSearchParams<{ variant?: string }>();
  const [refreshing, setRefreshing] = useState(false);
  const fixture = useMemo(() => fixtureFor(variant), [variant]);
  if (!(IS_SANDBOX_BUILD || __DEV__)) return <Redirect href="/(tabs)/home" />;
  return (
    <TicketDetailView
      group={fixture.state.kind === 'failed' && fixture.state.failure === 'signed_out' ? null : GROUP}
      facts={{ age_min: 21, timezone: 'America/New_York' }}
      state={fixture.state}
      credentials={fixture.credentials}
      refreshing={refreshing}
      onRefresh={() => { setRefreshing(true); setTimeout(() => setRefreshing(false), 400); }}
      onShowCode={() => {}}
      onEncodeFailure={() => {}}
      onSignIn={() => {}}
      sampleCaveat
    />
  );
}
