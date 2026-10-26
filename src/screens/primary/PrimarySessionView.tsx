/**
 * src/screens/primary/PrimarySessionView.tsx — one primary event session, as a pure view
 * (CONTRACTS C1, D's 182 `get_primary_session`). The route owns the read; the harness renders literals.
 *
 * Shows what the server returned and nothing more: title, the venue's local date/doors/start with the
 * zone named (`whenFromLocal`), venue and neighbourhood, the age note from `age_restriction` (display
 * only — the door checks ID), the description, and each public tier with the server's ALL-IN price
 * (A's rule: face value is never the headline; no price at all until the server provides all-in) and
 * the server's sale status (`tierLine`). Only a tier `tierLine` calls available can be chosen; the
 * buyer picks a quantity (1–10; the server's hold refuses oversell) and continues to the C3 checkout,
 * or signs in first. No price is computed here — the checkout quote is the authority.
 */
import { useMemo } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';

import ScreenState from '@/src/components/ScreenState';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { Badge, Button, EmptyState, Spinner } from '@/src/components/ui';
import { MAX_PRIMARY_QUANTITY } from '@/src/lib/primary/checkoutRoute';
import { DISCOVERY_COPY, tierLine, type SessionDetailLoad } from '@/src/lib/primary/discovery';
import { entryRestrictionLine, whenFromLocal } from '@/src/lib/tickets/ticketWhen';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export const PRIMARY_SESSION_COPY = {
  screenTitle: 'Event',
  sampleCaveat: 'Sample — not a real event',
  quantityLabel: 'Quantity',
  continue: 'Continue to checkout',
  signIn: 'Sign in to buy',
} as const;

export interface PrimarySessionViewProps {
  load: SessionDetailLoad;
  nowMs: number;
  refreshing: boolean;
  onRefresh: () => void;
  onBack?: () => void;
  selectedTierId: string | null;
  quantity: number;
  signedIn: boolean;
  onSelectTier: (ticketTypeId: string) => void;
  onChangeQuantity: (quantity: number) => void;
  onContinue: () => void;
  onSignIn: () => void;
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
          <SessionBody load={load} props={props} s={s} />
        </ScrollView>
      )}
    </View>
  );
}

function SessionBody({ load, props, s }: { load: Extract<SessionDetailLoad, { kind: 'ready' }>; props: PrimarySessionViewProps; s: Styles }) {
  const { nowMs } = props;
  const { facts, description, neighborhood, tiers } = load.detail;
  const when = whenFromLocal({ startsAtLocal: facts.startsAtLocal, doorsAtLocal: facts.doorsAtLocal, timezone: facts.timezone, startsAt: facts.startsAt });
  const restriction = entryRestrictionLine(facts.ageRestriction);
  const venueLine = [facts.venueName, neighborhood].filter(Boolean).join(' · ');
  const lines = tiers.map((t) => ({ id: t.ticket_type_id, line: tierLine(t, nowMs) }));
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
        {lines.map(({ id, line }) => {
          const selected = props.selectedTierId === id && line.available;
          return (
            <Pressable
              key={id}
              style={[s.tierRow, selected ? s.tierSelected : null]}
              disabled={!line.available}
              onPress={() => props.onSelectTier(id)}
              accessibilityRole="radio"
              accessibilityState={{ checked: selected, disabled: !line.available }}
              accessibilityLabel={`${line.name}, ${line.price ? `${line.price} including all fees` : 'no price yet'}, ${line.status}`}
            >
              <View style={s.tierText}>
                <Text style={[textStyle('title'), s.tierName]}>{line.name}</Text>
                {line.price ? <Text style={[textStyle('body'), s.tierPrice]}>{line.price}</Text> : null}
              </View>
              <Badge label={line.status} tone={line.available ? 'success' : 'neutral'} />
            </Pressable>
          );
        })}
        {lines.some(({ line }) => line.price) ? <Text style={[textStyle('bodySm'), s.note]}>{DISCOVERY_COPY.priceNote}</Text> : null}
      </View>

      {lines.some(({ id, line }) => line.available && id === props.selectedTierId) ? (
        <View style={s.buy}>
          <View style={s.qtyRow}>
            <Text style={[textStyle('body'), s.meta]}>{PRIMARY_SESSION_COPY.quantityLabel}</Text>
            <View style={s.qtyControls}>
              <Button label="−" variant="secondary" size="sm" accessibilityLabel="Fewer tickets" disabled={props.quantity <= 1} onPress={() => props.onChangeQuantity(props.quantity - 1)} />
              <Text style={[textStyle('title'), s.qty]} accessibilityLiveRegion="polite" accessibilityLabel={`${props.quantity} tickets`}>{props.quantity}</Text>
              <Button label="+" variant="secondary" size="sm" accessibilityLabel="More tickets" disabled={props.quantity >= MAX_PRIMARY_QUANTITY} onPress={() => props.onChangeQuantity(props.quantity + 1)} />
            </View>
          </View>
          {props.signedIn ? (
            <Button label={PRIMARY_SESSION_COPY.continue} variant="primary" onPress={props.onContinue} />
          ) : (
            <Button label={PRIMARY_SESSION_COPY.signIn} variant="primary" onPress={props.onSignIn} />
          )}
        </View>
      ) : null}
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
    tierSelected: { borderBottomColor: p.brand.red, borderBottomWidth: 2 },
    tierText: { flexShrink: 1, gap: 2 },
    buy: { gap: v2.space.md, paddingTop: v2.space.sm },
    qtyRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
    qtyControls: { flexDirection: 'row', alignItems: 'center', gap: v2.space.md },
    qty: { color: p.text.primary, minWidth: 24, textAlign: 'center' },
    tierName: { color: p.text.primary },
    tierPrice: { color: p.text.secondary },
    note: { color: p.text.muted },
  });
}
