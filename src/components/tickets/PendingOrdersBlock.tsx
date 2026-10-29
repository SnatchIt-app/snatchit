/**
 * src/components/tickets/PendingOrdersBlock.tsx — "Orders in progress" on the Tickets tab: one row per
 * session whose order has no tickets yet (src/lib/tickets/pendingOrders.ts).
 *
 * Each row states only what the server's order says, in the ticket page's words, and opens that
 * session's ticket page through the `onOpen` the screen supplies — the component knows no route. No
 * amount, no code, no success state: the ticket page waits for the webhook.
 */
import { useMemo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { PENDING_ORDERS_COPY, type PendingOrderItem } from '@/src/lib/tickets/pendingOrders';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

const OPEN_HINT = 'Opens this event’s ticket page';

export function PendingOrdersBlock({ items, failed, onOpen }: {
  items: PendingOrderItem[];
  failed: boolean;
  onOpen: (sessionId: string) => void;
}) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  return (
    <View style={s.block}>
      <Text style={[textStyle('label'), s.header]} accessibilityRole="header">{PENDING_ORDERS_COPY.title}</Text>
      {failed ? (
        <Text style={[textStyle('bodySm'), s.failed]}>{PENDING_ORDERS_COPY.failed}</Text>
      ) : null}
      {items.map((item) => (
        <Pressable
          key={item.sessionId}
          style={s.row}
          accessible
          accessibilityRole="button"
          accessibilityLabel={`${item.title}. ${item.status}`}
          accessibilityHint={OPEN_HINT}
          onPress={() => onOpen(item.sessionId)}
        >
          <Text style={[textStyle('nameRow'), s.title]} numberOfLines={2}>{item.title}</Text>
          <Text style={[textStyle('bodySm'), s.status]} numberOfLines={2}>{item.status}</Text>
        </Pressable>
      ))}
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    block: { marginBottom: v2.space.md },
    header: { color: p.text.muted, marginTop: v2.space.md, marginBottom: v2.space.md },
    failed: { color: p.text.secondary, marginBottom: v2.space.md },
    row: {
      backgroundColor: p.surface.surface,
      borderWidth: 1,
      borderColor: p.border.default,
      borderRadius: v2.radius.md,
      padding: v2.space.lg,
      gap: v2.space.xs,
      marginBottom: v2.space.md,
    },
    title: { color: p.text.primary },
    status: { color: p.text.secondary },
  });
}
