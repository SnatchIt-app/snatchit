/**
 * src/screens/primary/PrimarySessionView.tsx — one primary event session, as a pure view
 * (CONTRACTS C1, D's 182 `get_primary_session`). The route owns the read; the harness renders literals.
 *
 * Shows what the server returned and nothing more: title, the venue's local date/doors/start with the
 * zone named (`whenFromLocal`), venue and neighbourhood, the age note from `age_restriction` (display
 * only — the door checks ID), the description, and each public tier with its FACE price and the
 * server's sale status (`tierLine`). No buy action yet: the C3 `primary-checkout` flow is the next
 * package, and a disabled stand-in would claim something that does not exist.
 */
import { useMemo } from 'react';
import { RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';

import ScreenState from '@/src/components/ScreenState';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { Badge, EmptyState, Spinner } from '@/src/components/ui';
import { DISCOVERY_COPY, tierLine, type SessionDetailLoad } from '@/src/lib/primary/discovery';
import { entryRestrictionLine, whenFromLocal } from '@/src/lib/tickets/ticketWhen';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export const PRIMARY_SESSION_COPY = {
  screenTitle: 'Event',
  sampleCaveat: 'Sample — not a real event',
} as const;

export interface PrimarySessionViewProps {
  load: SessionDetailLoad;
  nowMs: number;
  refreshing: boolean;
  onRefresh: () => void;
  onBack?: () => void;
  /** Harness only. */
  sampleCaveat?: boolean;
}

export function PrimarySessionView(props: PrimarySessionViewProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { load } = props;

  return (
    <View style={s.root}>
      <SettingsHeader title={PRIMARY_SESSION_COPY.screenTitle} onBack={props.onBack} />
      {load.kind === 'loading' ? (
        <View style={s.center}><Spinner size="large" label="Loading event" /></View>
      ) : load.kind === 'failed' ? (
        <ScreenState state={load.failure === 'offline' ? 'offline' : 'error'} onRetry={props.onRefresh} />
      ) : load.kind === 'not_available' ? (
        <EmptyState title={DISCOVERY_COPY.notAvailableTitle} body={DISCOVERY_COPY.notAvailableBody} />
      ) : (
        <ScrollView
          contentContainerStyle={s.content}
          refreshControl={<RefreshControl refreshing={props.refreshing} onRefresh={props.onRefresh} tintColor={palette.brand.red} />}
          showsVerticalScrollIndicator={false}
        >
          {props.sampleCaveat ? (
            <Text style={[textStyle('label'), s.caveat]} accessibilityRole="header">{PRIMARY_SESSION_COPY.sampleCaveat}</Text>
          ) : null}
          <SessionBody load={load} nowMs={props.nowMs} s={s} />
        </ScrollView>
      )}
    </View>
  );
}

function SessionBody({ load, nowMs, s }: { load: Extract<SessionDetailLoad, { kind: 'ready' }>; nowMs: number; s: Styles }) {
  const { facts, description, neighborhood, tiers } = load.detail;
  const when = whenFromLocal({ startsAtLocal: facts.startsAtLocal, doorsAtLocal: facts.doorsAtLocal, timezone: facts.timezone, startsAt: facts.startsAt });
  const restriction = entryRestrictionLine(facts.ageRestriction);
  const venueLine = [facts.venueName, neighborhood].filter(Boolean).join(' · ');
  return (
    <>
      <View style={s.event} accessible accessibilityRole="header">
        {facts.title ? <Text style={[textStyle('nameOrder'), s.title]}>{facts.title}</Text> : null}
        {when ? (
          <>
            <Text style={[textStyle('body'), s.meta]}>{when.date}</Text>
            <Text style={[textStyle('body'), s.meta]}>{when.times}</Text>
          </>
        ) : null}
        {venueLine ? <Text style={[textStyle('body'), s.meta]}>{venueLine}</Text> : null}
        {facts.address ? <Text style={[textStyle('bodySm'), s.meta]}>{facts.address}</Text> : null}
        {restriction ? <Text style={[textStyle('bodySm'), s.restriction]}>{restriction}</Text> : null}
      </View>
      {description ? <Text style={[textStyle('body'), s.description]}>{description}</Text> : null}

      <View style={s.tiers}>
        <Text style={[textStyle('sectionLabel'), s.tiersHeading]} accessibilityRole="header">{DISCOVERY_COPY.ticketsHeading}</Text>
        {tiers.map((t) => {
          const line = tierLine(t, nowMs);
          return (
            <View key={t.ticket_type_id} style={s.tierRow} accessible accessibilityLabel={`${line.name}, ${line.price === '—' ? 'price unavailable' : line.price} face value, ${line.status}`}>
              <View style={s.tierText}>
                <Text style={[textStyle('title'), s.tierName]}>{line.name}</Text>
                <Text style={[textStyle('body'), s.tierPrice]}>{line.price}</Text>
              </View>
              <Badge label={line.status} tone={line.available ? 'success' : 'neutral'} />
            </View>
          );
        })}
        <Text style={[textStyle('bodySm'), s.note]}>{DISCOVERY_COPY.priceNote}</Text>
      </View>
    </>
  );
}

type Styles = ReturnType<typeof makeStyles>;

function makeStyles(p: Palette) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: p.surface.canvas },
    content: { padding: v2.space.lg, paddingBottom: v2.space.xxxl, gap: v2.space.lg },
    center: { paddingVertical: v2.space.xxl, alignItems: 'center' },
    caveat: { color: p.status.warning, textAlign: 'center' },
    event: { gap: v2.space.xs },
    title: { color: p.text.primary },
    meta: { color: p.text.secondary },
    restriction: { color: p.text.primary, marginTop: v2.space.xs },
    description: { color: p.text.secondary },
    tiers: { gap: v2.space.sm },
    tiersHeading: { color: p.text.secondary },
    tierRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: v2.space.md,
      paddingVertical: v2.space.md,
      borderBottomWidth: StyleSheet.hairlineWidth,
      borderBottomColor: p.border.default,
    },
    tierText: { flexShrink: 1, gap: 2 },
    tierName: { color: p.text.primary },
    tierPrice: { color: p.text.secondary },
    note: { color: p.text.muted },
  });
}
