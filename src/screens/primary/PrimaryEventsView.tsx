/**
 * src/screens/primary/PrimaryEventsView.tsx — the list of primary sessions on sale, as a pure view
 * (CONTRACTS C1, D's 182 `list_primary_sessions_on_sale`).
 *
 * The list rows carry only instants (no venue zone), so a row's date/time line comes from that
 * session's `get_primary_session` facts when the route has them (`whenBySession`); until then the
 * row shows no time rather than one in the device's zone (A's time rule). A failed read is the
 * failure screen, an empty list the honest empty state — never one for the other.
 */
import { useMemo } from 'react';
import { FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';

import ScreenState from '@/src/components/ScreenState';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { EmptyState, Spinner } from '@/src/components/ui';
import { DISCOVERY_COPY, type DiscoveryLoad, type DiscoveryRow } from '@/src/lib/primary/discovery';
import { entryRestrictionLine, type WhenLine } from '@/src/lib/tickets/ticketWhen';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface PrimaryEventsViewProps {
  load: DiscoveryLoad;
  whenBySession: Record<string, WhenLine | null>;
  refreshing: boolean;
  onRefresh: () => void;
  onOpen: (sessionId: string) => void;
  onBack?: () => void;
  sampleCaveat?: boolean;
}

export function PrimaryEventsView(props: PrimaryEventsViewProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { load } = props;

  const row = (r: DiscoveryRow) => {
    const when = props.whenBySession[r.sessionId] ?? null;
    const age = entryRestrictionLine(r.ageRestriction);
    const venue = [r.venueName, r.neighborhood].filter(Boolean).join(' · ');
    const label = [r.title, when ? `${when.date}, ${when.times}` : null, venue || null, age].filter(Boolean).join(', ');
    return (
      <Pressable
        style={s.row}
        onPress={() => props.onOpen(r.sessionId)}
        accessibilityRole="button"
        accessibilityLabel={label}
        accessibilityHint="Opens the event and its tickets"
      >
        <Text style={[textStyle('nameRow'), s.title]} numberOfLines={2}>{r.title}</Text>
        {when ? <Text style={[textStyle('bodySm'), s.meta]}>{`${when.date} · ${when.times}`}</Text> : null}
        {venue ? <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>{venue}</Text> : null}
        {age ? <Text style={[textStyle('bodySm'), s.age]}>{age}</Text> : null}
      </Pressable>
    );
  };

  return (
    <View style={s.root}>
      <SettingsHeader title={DISCOVERY_COPY.listTitle} onBack={props.onBack} />
      {props.sampleCaveat ? <Text style={[textStyle('label'), s.caveat]}>Sample — not real events</Text> : null}
      {load.kind === 'loading' ? (
        <View style={s.center}><Spinner size="large" label="Loading events" /></View>
      ) : load.kind === 'failed' ? (
        <ScreenState state={load.failure === 'offline' ? 'offline' : 'error'} onRetry={props.onRefresh} />
      ) : load.rows.length === 0 ? (
        <EmptyState title={DISCOVERY_COPY.listEmptyTitle} body={DISCOVERY_COPY.listEmptyBody} />
      ) : (
        <FlatList
          data={load.rows}
          keyExtractor={(r) => r.sessionId}
          renderItem={({ item }) => row(item)}
          extraData={props.whenBySession}
          contentContainerStyle={s.list}
          ItemSeparatorComponent={() => <View style={s.divider} />}
          refreshControl={<RefreshControl refreshing={props.refreshing} onRefresh={props.onRefresh} tintColor={palette.brand.red} />}
        />
      )}
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: p.surface.canvas },
    center: { paddingVertical: v2.space.xxl, alignItems: 'center' },
    caveat: { color: p.status.warning, textAlign: 'center', paddingTop: v2.space.sm },
    list: { padding: v2.space.lg, paddingBottom: v2.space.xxxl },
    row: { paddingVertical: v2.space.md, gap: 2 },
    title: { color: p.text.primary },
    meta: { color: p.text.secondary },
    age: { color: p.text.primary },
    divider: { height: StyleSheet.hairlineWidth, backgroundColor: p.border.default },
  });
}
