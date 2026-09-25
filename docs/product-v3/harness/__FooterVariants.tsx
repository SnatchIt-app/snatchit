/**
 * __FooterVariants.tsx — B'S TEMPORARY HARNESS FILE. NOT PART OF THE APP.
 *
 * Owner 2026-09-24: "The listing footer is reopened for a focused comparison. Produce three actual
 * app renders." This renders the SAME resolver output (`detailState`'s primary/secondary pair) in
 * three arrangements, using the REAL Button, the real palette, the real type scale and the real
 * spacing tokens — so each capture is the app drawing the footer, not a picture of one.
 *
 * It is applied to B's render worktree only, never committed to `v3/midnight-app`, and reverted
 * with `git checkout -- src app` after the captures. The companion patch to
 * `ListingDetailScreen.tsx` is four lines and is recorded beside the review.
 *
 *   A  side-by-side   red "Place a bid" LEFT, outlined "Buy both now" RIGHT
 *   B  stacked        red "Place a bid" first, outlined "Buy both now · $132.00" second
 *   C  stacked        the shipping treatment: filled Buy Now first, outlined bid second
 *
 * WHY A MOVES ITS SUB-LINES OUT OF THE PILLS. The owner's constraint is "without squeezing the
 * existing long sentences into half-width buttons". At 393pt a half-width pill is ~174pt, and
 * `Button` draws its label at `numberOfLines={1}` while `BarAction` draws the sub-line at
 * `numberOfLines={1}` inside the pill. Both would truncate. So in A the price and the consequence
 * sit BELOW each pill, on the canvas, free to wrap — which keeps the quantity ("both"), the all-in
 * meaning and the bid/buy distinction intact rather than trading them for a fit.
 */
import { useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Button } from '@/src/components/ui/Button';
import { StickyBar, BarAction } from '@/src/components/ui/StickyBar';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export type FooterVariant = 'A' | 'B' | 'C';

export interface FooterPair {
  buyLabel: string;      // "Buy both now · $132.00"
  buyVerb: string;       // "Buy both now"
  buyPrice: string | null;
  buySub: string;        // "all-in, ends the auction"
  bidLabel: string;      // "Place a bid"
  bidSub?: string;       // "minimum $104.50 all-in"
  disabled?: boolean;
}

export function FooterVariants({ variant, pair }: { variant: FooterVariant; pair: FooterPair }) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);

  if (variant === 'A') {
    // Two half-width pills. Each pill holds a SHORT single-line label; the price and the
    // consequence go under it on the canvas, where they can wrap.
    const buyUnder = pair.buyPrice ? `${pair.buyPrice} all-in · ends the auction` : pair.buySub;
    return (
      <View style={s.wrap}>
        <View style={s.row}>
          <View style={s.half}>
            <Button label={pair.bidLabel} variant="primary" size="lg" block disabled={pair.disabled} onPress={() => {}} />
            <Text style={[textStyle('bodySm'), s.under]} numberOfLines={2} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>
              {pair.bidSub ?? ''}
            </Text>
          </View>
          <View style={s.half}>
            <Button label={pair.buyVerb} variant="secondary" size="lg" block disabled={pair.disabled} onPress={() => {}} />
            <Text style={[textStyle('bodySm'), s.under]} numberOfLines={2} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>
              {buyUnder}
            </Text>
          </View>
        </View>
      </View>
    );
  }

  // B IS C WITH THE PAIR SWAPPED, so it is drawn by the REAL StickyBar and the REAL BarAction —
  // same pill geometry, same in-pill sub-line, same everything. Only the order and which one is
  // filled differ. A copy of those components here would compare my code against C's, not B against C.
  return (
    <StickyBar layout="stack">
      <BarAction label={pair.bidLabel} subLabel={pair.bidSub} variant="primary" disabled={pair.disabled} onPress={() => {}} />
      <BarAction label={pair.buyLabel} subLabel={pair.buySub} variant="secondary" disabled={pair.disabled} onPress={() => {}} />
    </StickyBar>
  );
}

const SUB_PAD = v2.space.xs;
const TALL = SUB_PAD * 2 + v2.type.action.lineHeight + v2.type.bodySm.lineHeight;

function makeStyles(p: Palette) {
  return StyleSheet.create({
    wrap: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.md, gap: v2.space.sm, backgroundColor: p.surface.canvas },
    row: { flexDirection: 'row', gap: v2.space.sm, alignItems: 'flex-start' },
    half: { flex: 1, gap: v2.space.xs },
    under: { color: p.text.secondary, textAlign: 'center' },
    stackItem: { justifyContent: 'center' },
    tall: { height: TALL },
    sub: { position: 'absolute', left: 0, right: 0, bottom: SUB_PAD + 2, alignItems: 'center' },
    subOnFill: { color: p.text.inverse },
    subOnCanvas: { color: p.text.muted },
  });
}
