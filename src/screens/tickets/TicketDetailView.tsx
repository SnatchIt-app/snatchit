/**
 * src/screens/tickets/TicketDetailView.tsx — the buyer's ticket detail, as a pure view.
 *
 * Takes everything it shows as props so the `_dev/v3-ticket-detail` harness can render every
 * state from literals and app/ticket/[session].tsx owns the reads. The view decides nothing: it
 * maps DetailState to the pinned copy, hands each ready atom an EntitlementCard, and lists the
 * buyer's orders for the session with one honest line each.
 *
 * Event block, in this order of authority (A's time rule, from D's 162/182):
 *   1. `facts` from get_primary_session — title, venue, the VENUE's local date/doors/start with the
 *      zone named (`whenFromLocal`), and the age note from `age_restriction` (display only);
 *   2. otherwise `group` from get_my_tickets — the instant formatted with its zone named.
 * Never a guessed "21+": no age line without the server's value.
 */
import { useMemo } from 'react';
import { RefreshControl, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';

import ScreenState from '@/src/components/ScreenState';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { EntitlementCard } from '@/src/components/tickets/EntitlementCard';
import { EmptyState, Spinner } from '@/src/components/ui';
import { DETAIL_COPY, type CredentialState, type DetailState } from '@/src/lib/tickets/entitlement';
import type { SessionFacts } from '@/src/lib/tickets/entitlementReads';
import type { OrderLine } from '@/src/lib/tickets/primaryOrders';
import { entryRestrictionLine, whenFromLocal, whenLine, type WhenLine } from '@/src/lib/tickets/ticketWhen';
import type { MyTicketGroup } from '@/src/lib/tickets/types';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export const TICKET_DETAIL_COPY = {
  screenTitle: 'Ticket',
  signInAction: 'Sign in',
  sampleCaveat: 'Sample — not a ticket',
  ordersHeading: 'Your orders',
} as const;

export type { SessionFacts } from '@/src/lib/tickets/entitlementReads';

export interface TicketDetailViewProps {
  group: Pick<MyTicketGroup, 'event_title' | 'starts_at' | 'doors_at' | 'venue_name' | 'session_label'> | null;
  facts: SessionFacts | null;
  state: DetailState;
  orders: OrderLine[];
  credentials: Record<string, CredentialState>;
  /** Atoms whose code is being refreshed while the current one stays on screen. */
  refreshing: Record<string, boolean>;
  refreshNotes: Record<string, string | null>;
  pullRefreshing: boolean;
  onRefresh: () => void;
  onShowCode: (atomId: string) => void;
  onEncodeFailure: (atomId: string) => void;
  onSignIn: () => void;
  onBack?: () => void;
  /** Harness only: a visible caveat over sample data. Never set by the route. */
  sampleCaveat?: boolean;
}

/** The event block's text, from the strongest source available. Exported for tests. */
export function eventBlock(
  facts: SessionFacts | null,
  group: TicketDetailViewProps['group'],
): { title: string | null; when: WhenLine | null; venue: string | null; restriction: string | null } {
  const title = facts?.title ?? group?.event_title ?? null;
  const fromLocal = facts
    ? whenFromLocal({ startsAtLocal: facts.startsAtLocal, doorsAtLocal: facts.doorsAtLocal, timezone: facts.timezone, startsAt: facts.startsAt })
    : null;
  const when = fromLocal ?? (group ? whenLine(group.starts_at, group.doors_at, facts?.timezone ?? undefined) : null);
  const venueName = facts?.venueName ?? group?.venue_name ?? null;
  const label = facts?.sessionLabel ?? group?.session_label ?? null;
  const venue = venueName ? `${venueName}${label ? `  -  ${label}` : ''}` : null;
  return { title, when, venue, restriction: entryRestrictionLine(facts?.ageRestriction) };
}

const NO_ATOMS_COPY: Partial<Record<DetailState['kind'], { title: string; body: string }>> = {
  awaiting_confirmation: DETAIL_COPY.awaiting_confirmation,
  payment_processing: DETAIL_COPY.payment_processing,
  pending_issuance: DETAIL_COPY.pending_issuance,
  payment_failed: DETAIL_COPY.payment_failed,
  not_on_account: DETAIL_COPY.not_on_account,
  inconsistent: DETAIL_COPY.inconsistent,
  empty: DETAIL_COPY.empty,
};

export function TicketDetailView(props: TicketDetailViewProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { width } = useWindowDimensions();
  // The code card may use the content width inside the entitlement card's own padding.
  const qrAvailable = Math.floor(width - 2 * v2.space.lg - 2 * v2.space.lg);
  const ev = eventBlock(props.facts, props.group);
  const { state } = props;
  const noAtoms = NO_ATOMS_COPY[state.kind];

  return (
    <View style={s.root}>
      <SettingsHeader title={TICKET_DETAIL_COPY.screenTitle} onBack={props.onBack} />
      <ScrollView
        contentContainerStyle={s.content}
        refreshControl={<RefreshControl refreshing={props.pullRefreshing} onRefresh={props.onRefresh} tintColor={palette.brand.red} />}
        showsVerticalScrollIndicator={false}
      >
        {props.sampleCaveat ? (
          <Text style={[textStyle('label'), s.caveat]} accessibilityRole="header">{TICKET_DETAIL_COPY.sampleCaveat}</Text>
        ) : null}

        {ev.title ? (
          <View style={s.event} accessible accessibilityRole="header">
            <Text style={[textStyle('nameOrder'), s.title]}>{ev.title}</Text>
            {ev.when ? (
              <>
                <Text style={[textStyle('body'), s.meta]}>{ev.when.date}</Text>
                <Text style={[textStyle('body'), s.meta]}>{ev.when.times}</Text>
              </>
            ) : null}
            {ev.venue ? <Text style={[textStyle('body'), s.meta]}>{ev.venue}</Text> : null}
            {ev.restriction ? <Text style={[textStyle('bodySm'), s.restriction]}>{ev.restriction}</Text> : null}
          </View>
        ) : null}

        {state.kind === 'loading' ? (
          <View style={s.center}><Spinner size="large" label="Loading your tickets" /></View>
        ) : state.kind === 'failed' ? (
          state.failure === 'signed_out' ? (
            <EmptyState
              title={DETAIL_COPY.signed_out.title}
              body={DETAIL_COPY.signed_out.body}
              action={{ label: TICKET_DETAIL_COPY.signInAction, onPress: props.onSignIn }}
            />
          ) : (
            <ScreenState state={state.failure === 'offline' ? 'offline' : 'error'} onRetry={props.onRefresh} />
          )
        ) : state.kind === 'atoms' ? (
          <View style={s.cards}>
            {state.atoms.map((atom, i) => (
              <EntitlementCard
                key={atom.ticket_atom_id}
                atom={atom}
                index={i}
                total={state.atoms.length}
                credential={props.credentials[atom.ticket_atom_id] ?? { kind: 'idle' }}
                refreshing={props.refreshing[atom.ticket_atom_id] === true}
                refreshNote={props.refreshNotes[atom.ticket_atom_id] ?? null}
                qrAvailable={qrAvailable}
                onShowCode={() => props.onShowCode(atom.ticket_atom_id)}
                onEncodeFailure={() => props.onEncodeFailure(atom.ticket_atom_id)}
              />
            ))}
          </View>
        ) : noAtoms ? (
          <EmptyState title={noAtoms.title} body={noAtoms.body} />
        ) : null}

        {props.orders.length > 0 && state.kind !== 'loading' && !(state.kind === 'failed' && state.failure === 'signed_out') ? (
          <View style={s.orders}>
            <Text style={[textStyle('sectionLabel'), s.ordersHeading]} accessibilityRole="header">{TICKET_DETAIL_COPY.ordersHeading}</Text>
            {props.orders.map((o) => (
              <View key={o.orderId} style={s.orderRow} accessible accessibilityLabel={o.amount ? `Order, ${o.amount} total, ${o.status}` : `Order, ${o.status}`}>
                <Text style={[textStyle('body'), s.orderStatus]} numberOfLines={2}>{o.status}</Text>
                {o.amount ? <Text style={[textStyle('body'), s.orderAmount]}>{o.amount}</Text> : null}
              </View>
            ))}
          </View>
        ) : null}
      </ScrollView>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: p.surface.canvas },
    content: { padding: v2.space.lg, paddingBottom: v2.space.xxxl, gap: v2.space.lg },
    caveat: { color: p.status.warning, textAlign: 'center' },
    event: { gap: v2.space.xs },
    title: { color: p.text.primary },
    meta: { color: p.text.secondary },
    restriction: { color: p.text.primary, marginTop: v2.space.xs },
    center: { paddingVertical: v2.space.xxl, alignItems: 'center' },
    cards: { gap: v2.space.md },
    orders: { gap: v2.space.sm },
    ordersHeading: { color: p.text.secondary },
    orderRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      gap: v2.space.md,
      paddingVertical: v2.space.sm,
      borderBottomWidth: StyleSheet.hairlineWidth,
      borderBottomColor: p.border.default,
    },
    orderStatus: { color: p.text.primary, flexShrink: 1 },
    orderAmount: { color: p.text.secondary },
  });
}
