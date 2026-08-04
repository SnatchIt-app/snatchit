/**
 * PriceDisplay — the single way buyer-facing prices are rendered.
 *
 * Typography only: callers pass a PREFORMATTED amount string (usually from
 * `allInFromDollars()` in src/lib/money.ts), so fee math stays in one place
 * and this component can never diverge from it.
 *
 * Layout guarantees (the reason this component exists — see the Jul 29
 * App Review screenshots where "CURRENT BID $198 total" wrapped into a
 * one-character-wide column inside the sticky bar):
 *   • the amount NEVER wraps — numberOfLines={1} on every text node;
 *   • tabular numerals so $8.80 / $165 / $1,000+ align consistently;
 *   • the "total" suffix sits on the SAME line, smaller and dimmer, so the
 *     amount carries the hierarchy without shouting;
 *   • containers get minWidth: 0 so parents with flexShrink can't crush the
 *     text into vertical letter-stacks.
 */
import { StyleSheet, Text, View } from 'react-native';

import { colors, fontSize } from '@/src/theme';

export type PriceDisplaySize = 'card' | 'detail' | 'sticky' | 'checkout';

interface Props {
  /** Preformatted amount, e.g. "$8.80" / "$165" / "$1,000". */
  amount: string;
  /** Small uppercase eyebrow above the amount, e.g. "CURRENT BID". */
  label?: string;
  /** Render the lowered-emphasis "total" suffix after the amount. */
  showTotal?: boolean;
  size?: PriceDisplaySize;
  align?: 'left' | 'right';
  /** Dim the amount (sold / ended states). */
  muted?: boolean;
}

const AMOUNT: Record<PriceDisplaySize, { size: number; weight: '700' | '800' }> = {
  card:     { size: fontSize.md, weight: '700' },
  detail:   { size: fontSize.xl, weight: '800' },
  sticky:   { size: fontSize.lg, weight: '800' },
  checkout: { size: fontSize.lg, weight: '800' },
};

const SUFFIX: Record<PriceDisplaySize, number> = {
  card:     fontSize.xs,
  detail:   fontSize.sm,
  sticky:   fontSize.xs,
  checkout: fontSize.sm,
};

export function PriceDisplay({
  amount,
  label,
  showTotal = true,
  size = 'card',
  align = 'left',
  muted = false,
}: Props) {
  const a = AMOUNT[size];
  return (
    <View style={[s.wrap, align === 'right' && s.wrapRight]}>
      {label ? (
        <Text style={s.label} numberOfLines={1}>
          {label}
        </Text>
      ) : null}
      <View style={[s.row, align === 'right' && s.rowRight]}>
        <Text
          style={[
            s.amount,
            { fontSize: a.size, fontWeight: a.weight },
            muted && s.amountMuted,
          ]}
          numberOfLines={1}
          accessibilityLabel={showTotal ? `${amount} total` : amount}
        >
          {amount}
        </Text>
        {showTotal ? (
          <Text style={[s.suffix, { fontSize: SUFFIX[size] }]} numberOfLines={1}>
            {' '}total
          </Text>
        ) : null}
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  wrap:      { minWidth: 0 },
  wrapRight: { alignItems: 'flex-end' },
  row:       { flexDirection: 'row', alignItems: 'baseline', minWidth: 0 },
  rowRight:  { justifyContent: 'flex-end' },
  label: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textDim,
    letterSpacing: 1.0,
    textTransform: 'uppercase',
    marginBottom: 2,
  },
  amount: {
    color: colors.text,
    fontVariant: ['tabular-nums'],
    flexShrink: 1,
  },
  amountMuted: { color: colors.textMuted },
  suffix: {
    color: colors.textDim,
    fontWeight: '500',
    flexShrink: 0,
  },
});
