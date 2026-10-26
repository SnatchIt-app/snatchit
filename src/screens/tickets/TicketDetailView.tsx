/**
 * src/screens/tickets/TicketDetailView.tsx — the buyer's ticket detail, as a pure view.
 *
 * Takes everything it shows as props (the event facts from get_my_tickets, the per-atom state
 * from entitlement.ts, one credential state per atom) so the `_dev/v3-ticket-detail` harness can
 * render every state from literals and app/ticket/[session].tsx owns the reads. The view decides
 * nothing: it maps DetailState to the pinned copy and hands each ready atom an EntitlementCard.
 *
 * What the event block shows: title, date + doors + start in one named zone (ticketWhen.ts), venue,
 * session label, and the entry restriction ONLY when the session read supplied one (the pending
 * `get_primary_session` contract) — never a guessed "21+".
 */
import { useMemo } from 'react';
import { RefreshControl, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';

import ScreenState from '@/src/components/ScreenState';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { EntitlementCard } from '@/src/components/tickets/EntitlementCard';
import { EmptyState, Spinner } from '@/src/components/ui';
import { DETAIL_COPY, type CredentialState, type DetailState } from '@/src/lib/tickets/entitlement';
import { entryRestrictionLine, whenLine } from '@/src/lib/tickets/ticketWhen';
import type { MyTicketGroup } from '@/src/lib/tickets/types';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export const TICKET_DETAIL_COPY = {
  screenTitle: 'Ticket',
  signInAction: 'Sign in',
  sampleCaveat: 'Sample — not a ticket',
} as const;

/** From the pending session read; null until it exists. */
export interface SessionFacts {
  age_min: number | null;
  timezone: string | null;
}

export interface TicketDetailViewProps {
  group: Pick<MyTicketGroup, 'event_title' | 'starts_at' | 'doors_at' | 'venue_name' | 'session_label'> | null;
  facts: SessionFacts | null;
  state: DetailState;
  credentials: Record<string, CredentialState>;
  refreshing: boolean;
  onRefresh: () => void;
  onShowCode: (atomId: string) => void;
  onEncodeFailure: (atomId: string) => void;
  onSignIn: () => void;
  onBack?: () => void;
  /** Harness only: a visible caveat over sample data. Never set by the route. */
  sampleCaveat?: boolean;
}

export function TicketDetailView(props: TicketDetailViewProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { width } = useWindowDimensions();
  // The code fills the card width on small phones and caps at 320pt on large ones: a 77-module
  // symbol at 320pt is ~4pt per module, comfortable for a phone camera at arm's length.
  const qrSize = Math.min(320, Math.floor(width - 2 * v2.space.lg - 2 * v2.space.lg));
  const when = props.group ? whenLine(props.group.starts_at, props.group.doors_at, props.facts?.timezone ?? undefined) : null;
  const restriction = entryRestrictionLine(props.facts?.age_min);
  const { state } = props;

  return (
    <View style={s.root}>
      <SettingsHeader title={TICKET_DETAIL_COPY.screenTitle} onBack={props.onBack} />
      <ScrollView
        contentContainerStyle={s.content}
        refreshControl={<RefreshControl refreshing={props.refreshing} onRefresh={props.onRefresh} tintColor={palette.brand.red} />}
        showsVerticalScrollIndicator={false}
      >
        {props.sampleCaveat ? (
          <Text style={[textStyle('label'), s.caveat]} accessibilityRole="header">{TICKET_DETAIL_COPY.sampleCaveat}</Text>
        ) : null}

        {props.group ? (
          <View style={s.event} accessible accessibilityRole="header">
            <Text style={[textStyle('nameOrder'), s.title]}>{props.group.event_title}</Text>
            {when ? (
              <>
                <Text style={[textStyle('body'), s.meta]}>{when.date}</Text>
                <Text style={[textStyle('body'), s.meta]}>{when.times}</Text>
              </>
            ) : null}
            <Text style={[textStyle('body'), s.meta]}>
              {props.group.venue_name}{props.group.session_label ? `  -  ${props.group.session_label}` : ''}
            </Text>
            {restriction ? <Text style={[textStyle('bodySm'), s.restriction]}>{restriction}</Text> : null}
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
        ) : state.kind === 'pending_issuance' ? (
          <EmptyState title={DETAIL_COPY.pending_issuance.title} body={DETAIL_COPY.pending_issuance.body} />
        ) : state.kind === 'payment_processing' ? (
          <EmptyState title={DETAIL_COPY.payment_processing.title} body={DETAIL_COPY.payment_processing.body} />
        ) : state.kind === 'inconsistent' ? (
          <EmptyState title={DETAIL_COPY.inconsistent.title} body={DETAIL_COPY.inconsistent.body} />
        ) : state.kind === 'empty' ? (
          <EmptyState title={DETAIL_COPY.empty.title} body={DETAIL_COPY.empty.body} />
        ) : (
          <View style={s.cards}>
            {state.atoms.map((atom, i) => (
              <EntitlementCard
                key={atom.ticket_atom_id}
                atom={atom}
                index={i}
                total={state.atoms.length}
                credential={props.credentials[atom.ticket_atom_id] ?? { kind: 'idle' }}
                qrSize={qrSize}
                onShowCode={() => props.onShowCode(atom.ticket_atom_id)}
                onEncodeFailure={() => props.onEncodeFailure(atom.ticket_atom_id)}
              />
            ))}
          </View>
        )}
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
  });
}
