/**
 * StatCardStrip — horizontal strip of tappable stat cards.
 *
 * One shared component for every stat/filter strip in the app (My Bids
 * summary, Profile seller dashboard). Design rules:
 *   - Fixed minimum card width so labels NEVER wrap ("Purchases", "Needs
 *     Action" stay on one line); numberOfLines={1} as a hard guarantee.
 *   - Horizontally scrollable with natural snapping when the cards overflow
 *     the screen; when they fit (e.g. 3 cards), flexGrow stretches them to
 *     fill the row edge-to-edge — no scrolling, no dead space.
 *   - Hierarchy: large number on top, small uppercase label underneath.
 *   - Equal heights (stretch), equal gaps, one corner radius, one padding.
 */

import { Pressable, ScrollView, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { colors, fontSize, radius, spacing } from '@/src/theme';

const CARD_MIN_WIDTH = 104;
const CARD_GAP = spacing.sm;

export type StatCardItem = {
  key: string;
  label: string;
  value: string | number;
  /** Accent for the value (and border/label when active). Defaults to text color. */
  color?: string;
  /** Per-item tap handler — used when the strip is not an active-filter group. */
  onPress?: () => void;
};

type Props = {
  items: StatCardItem[];
  /** Key of the currently active card (filter strips). */
  activeKey?: string | null;
  /** Strip-level tap handler (filter strips) — receives the item key. */
  onItemPress?: (key: string) => void;
  style?: ViewStyle;
  /** Horizontal inset of the scroll content. Pass 0 when the parent already pads. */
  contentPaddingHorizontal?: number;
};

export default function StatCardStrip({
  items, activeKey, onItemPress, style,
  contentPaddingHorizontal = spacing.md,
}: Props) {
  return (
    <View style={style}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        snapToInterval={CARD_MIN_WIDTH + CARD_GAP}
        snapToAlignment="start"
        decelerationRate="fast"
        contentContainerStyle={[s.row, { paddingHorizontal: contentPaddingHorizontal }]}
      >
        {items.map((item) => {
          const active = activeKey != null && activeKey === item.key;
          const accent = item.color ?? colors.text;
          const handlePress = item.onPress ?? (onItemPress ? () => onItemPress(item.key) : undefined);
          return (
            <Pressable
              key={item.key}
              style={[
                s.card,
                active && { borderColor: accent, backgroundColor: 'rgba(255,255,255,0.06)' },
              ]}
              onPress={handlePress}
              disabled={!handlePress}
              hitSlop={6}
              android_ripple={handlePress ? { color: colors.primarySoft } : undefined}
            >
              <Text style={[s.value, { color: accent }]} numberOfLines={1}>
                {item.value}
              </Text>
              <Text
                style={[s.label, active && { color: accent }]}
                numberOfLines={1}
              >
                {item.label}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  row: {
    flexGrow: 1,
    gap: CARD_GAP,
    alignItems: 'stretch',
  },
  card: {
    minWidth: CARD_MIN_WIDTH,
    flexGrow: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.sm + spacing.xs,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgCard,
  },
  value: {
    fontSize: fontSize.xl,
    fontWeight: '800',
    marginBottom: 2,
  },
  label: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textMuted,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
});
