/**
 * app/(tabs)/tickets.tsx — Your Tickets (Phase 11).
 *
 * The tickets the signed-in user actually OWNS, read from the Core contract
 * public.get_my_tickets() (owner-scoped, no arguments). This is ownership, not
 * marketplace activity: it is deliberately separate from Bids and never shows bid
 * history. Two sections from the server's own time_class — Upcoming (loud,
 * artwork-led) and Past (quieter) — with server ordering preserved.
 *
 * Empty ([]) is a SUCCESS state, not an error. Auth failures (42501 / 28000) route
 * to sign-in; other failures show a retry. No Ticket Detail, no QR/barcode, no
 * Apple Wallet, no price — none of those contracts exist yet.
 *
 * In production the RPC returns [] today (native issuance is disabled server-side).
 * A __DEV__-only fixture toggle (off by default, never written anywhere) lets the
 * populated states be reviewed on a device; real RPC data always takes precedence.
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { RefreshControl, SectionList, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import ScreenState, { type ScreenStateKind } from '@/src/components/ScreenState';
import { EmptyState } from '@/src/components/ui';
import { useDockScroll } from '@/src/components/nav/dockContext';
import { useDockClearance } from '@/src/lib/nav/navInsets';
import { TicketEventGroup } from '@/src/components/tickets/TicketEventGroup';
import { fetchMyTickets } from '@/src/lib/tickets/api';
import { DEV_TICKET_FIXTURES } from '@/src/lib/tickets/fixtures';
import { classifyTicketsError, groupByEvent, splitByTimeClass, type EventGroup } from '@/src/lib/tickets/ticketState';
import type { MyTicketGroup } from '@/src/lib/tickets/types';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

type Phase = 'loading' | 'ready' | 'error';
interface Section { title: string; emphasis: 'upcoming' | 'past'; data: EventGroup[] }

export default function TicketsScreen() {
  const insets = useSafeAreaInsets();
  const dockClearance = useDockClearance();
  const { onScroll: onDockScroll } = useDockScroll('tickets');

  const [phase, setPhase] = useState<Phase>('loading');
  const [rows, setRows] = useState<MyTicketGroup[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  // DEV-only: render sample states without any server write. Off by default.
  const [devFixtures, setDevFixtures] = useState(false);
  const mounted = useRef(true);

  useEffect(() => () => { mounted.current = false; }, []);

  const load = useCallback(async (isRefresh: boolean) => {
    if (devFixtures) { setPhase('ready'); return; }
    if (!isRefresh) setPhase('loading');
    const { data, error } = await fetchMyTickets();
    if (!mounted.current) return;
    if (error) {
      if (classifyTicketsError(error) === 'auth') { router.replace('/(auth)/login'); return; }
      setPhase('error');
      return;
    }
    setRows(data ?? []);
    setPhase('ready');
  }, [devFixtures]);

  useFocusEffect(useCallback(() => { load(false); }, [load]));

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await load(true);
    if (mounted.current) setRefreshing(false);
  }, [load]);

  // DEV fixtures only render when the __DEV__ toggle is on; real RPC data wins.
  const effectiveRows: MyTicketGroup[] = devFixtures ? DEV_TICKET_FIXTURES : rows;

  const sections = useMemo<Section[]>(() => {
    const { upcoming, past } = splitByTimeClass(effectiveRows);
    const out: Section[] = [];
    const up = groupByEvent(upcoming);
    const pa = groupByEvent(past);
    if (up.length) out.push({ title: 'Upcoming', emphasis: 'upcoming', data: up });
    if (pa.length) out.push({ title: 'Past', emphasis: 'past', data: pa });
    return out;
  }, [effectiveRows]);

  return (
    <View style={s.container}>
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
        <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">Your tickets</Text>
        {__DEV__ ? (
          <Text
            style={[textStyle('micro'), s.devToggle]}
            onPress={() => setDevFixtures((v) => !v)}
            accessibilityRole="button"
            accessibilityLabel="Toggle developer sample tickets"
          >
            {devFixtures ? 'DEV FIXTURES ON' : 'DEV'}
          </Text>
        ) : null}
      </View>

      {phase === 'loading' ? (
        <ScreenState state={'loading' as ScreenStateKind} />
      ) : phase === 'error' ? (
        <ScreenState state={'error' as ScreenStateKind} onRetry={() => load(false)} />
      ) : sections.length === 0 ? (
        <EmptyState
          title="No tickets yet"
          body="Tickets you own will show up here."
        />
      ) : (
        <SectionList
          sections={sections}
          keyExtractor={(item) => item.key}
          contentContainerStyle={[s.list, { paddingBottom: dockClearance }]}
          showsVerticalScrollIndicator={false}
          onScroll={onDockScroll}
          scrollEventThrottle={16}
          stickySectionHeadersEnabled={false}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={v2.brand.red} />
          }
          renderSectionHeader={({ section }) => (
            <Text style={[textStyle('label'), s.sectionHeader]} accessibilityRole="header">
              {(section as Section).title}
            </Text>
          )}
          renderItem={({ item, section }) => (
            <TicketEventGroup group={item} emphasis={(section as Section).emphasis} />
          )}
        />
      )}
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: v2.surface.canvas },
  header: {
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.md,
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
  },
  title: { color: v2.text.primary },
  devToggle: { color: v2.text.faint, paddingVertical: v2.space.xs, paddingHorizontal: v2.space.sm },
  list: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.sm },
  sectionHeader: { color: v2.text.muted, marginTop: v2.space.md, marginBottom: v2.space.md },
});
