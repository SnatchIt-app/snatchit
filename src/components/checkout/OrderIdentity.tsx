/**
 * src/components/checkout/OrderIdentity.tsx — what is being bought, said once (V3, owner
 * 2026-09-23; pkg2 checkout board ①).
 *
 * The one identity block all three checkout views share: the artwork thumbnail, the name in
 * the display voice, the dated line home/search/listing/bid entry also use, and the
 * whole-listing quantity ("2 × GA · sold together" — buy_now_price is charged once for the
 * whole listing, which is why the count sits here and the breakdown row below never repeats
 * it). Missing pieces degrade to what is known: no invented dates, counts or types.
 */

import { useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { NameText } from '@/src/components/NameText';
import { rowWhenLabel } from '@/src/lib/listing/feedRowState';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface OrderIdentityProps {
  /** Raw stored cover value; EventMedia resolves and sizes it. */
  cover: string | null;
  name: string;
  venue: string | null;
  eventDate?: string | null;
  eventTime?: string | null;
  quantity?: number | null;
  ticketType?: string | null;
}

export function OrderIdentity({
  cover,
  name,
  venue,
  eventDate,
  eventTime,
  quantity,
  ticketType,
}: OrderIdentityProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const dated = eventDate ? rowWhenLabel(eventDate, eventTime ?? '') : '';
  const whenWhere = dated && venue ? `${dated} · ${venue}` : dated || venue || '';

  const count =
    quantity == null
      ? null
      : ticketType
        ? `${quantity} × ${ticketType}`
        : `${quantity} ${quantity === 1 ? 'ticket' : 'tickets'}`;
  const qtyLine = count ? `${count}${(quantity as number) > 1 ? ' · sold together' : ''}` : null;

  return (
    <View style={s.row}>
      {/*
        72 is the row's HEIGHT budget, not its width (owner's 4:5 poster direction, 2026-09-24).
        Spent as a width it made a 72 × 90 frame: under the poster ratio the derived edge is the
        tall one, so the thumbnail grew 18pt past the space this summary row was approved with — on
        checkout, the refund face and the confirmation alike. Passed as `height` the row keeps its
        72pt of vertical rhythm and the poster takes the 58pt the ratio gives it. EventMedia does
        that arithmetic; this file states only the edge it owns.
      */}
      <EventMedia
        asset={{ path: cover, contract: 'legacy', bucket: 'auction-media' }}
        slot="CHECKOUT_THUMBNAIL"
        title={name}
        height={72}
        decorative
      />
      <View style={s.text}>
        <NameText token="nameOrder" maxLines={2} style={s.name}>{name}</NameText>
        {whenWhere ? (
          <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>{whenWhere}</Text>
        ) : null}
        {qtyLine ? (
          <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>{qtyLine}</Text>
        ) : null}
      </View>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  // No edge of the poster appears here, which is why the taller-and-narrower shape needed no
  // other change: the text column takes whatever width the artwork leaves (`flex: 1`), and
  // `flex-start` keeps the name's first line level with the poster's top edge rather than
  // floating it against a frame whose height the row no longer dictates.
  row: { flexDirection: 'row', gap: v2.space.md, alignItems: 'flex-start' },
  text: { flex: 1, minWidth: 0, gap: 2 },
  name: { color: p.text.primary },
  meta: { color: p.text.muted },
});
}
