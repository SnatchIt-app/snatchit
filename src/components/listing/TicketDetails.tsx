/**
 * src/components/listing/TicketDetails.tsx — what you actually get.
 *
 * The old screen answered this with four visually identical grey cards — Event
 * details, Ticket info, Pricing, Bid history — each with the same border, the
 * same radius and the same weight, so nothing in it told the user which parts
 * mattered. This is one section, separated by hairlines, with the label quiet and
 * the value loud.
 *
 * It does not repeat the event name, venue or date: those are already the largest
 * things on the screen, directly under the artwork.
 */

import { StyleSheet, Text, View } from 'react-native';

import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface DetailRow {
  label: string;
  value: string;
  /** Long free text (restrictions) wraps under its label instead of fighting it. */
  block?: boolean;
}

export function TicketDetails({ rows }: { rows: DetailRow[] }) {
  return (
    <View style={styles.wrap}>
      <Text style={[textStyle('displaySm'), styles.head]} accessibilityRole="header">
        The ticket
      </Text>

      {rows.map((row, i) => (
        <View
          key={row.label}
          style={[styles.row, row.block && styles.rowBlock, i === rows.length - 1 && styles.last]}
          accessible
          accessibilityLabel={`${row.label}: ${row.value}`}
        >
          <Text style={[textStyle('bodySm'), styles.label]}>{row.label}</Text>
          <Text
            style={[textStyle('body'), styles.value, row.block && styles.valueBlock]}
            numberOfLines={row.block ? undefined : 2}
          >
            {row.value}
          </Text>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.xl },
  head: { color: v2.text.primary, marginBottom: v2.space.sm },
  row: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    gap: v2.space.lg,
    paddingVertical: v2.space.md,
    borderBottomWidth: 1,
    borderBottomColor: v2.border.default,
  },
  rowBlock: { flexDirection: 'column', alignItems: 'flex-start', gap: v2.space.xs },
  last: { borderBottomWidth: 0 },
  label: { color: v2.text.muted },
  value: { color: v2.text.primary, flexShrink: 1, textAlign: 'right' },
  valueBlock: { textAlign: 'left' },
});
