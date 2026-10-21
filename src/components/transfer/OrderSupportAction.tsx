/**
 * src/components/transfer/OrderSupportAction.tsx — "Contact support about this order" (CFT-406, slice 1).
 *
 * One secondary action for the two order screens (buyer receive, seller send), in every transfer
 * state. It opens the support email prefilled with this order's ID, status word, event and the
 * viewer's role (src/lib/support/orderSupport.ts — no PII, built from an allowlist of fields).
 *
 * If the mail app cannot open, the address and the order ID appear as selectable text and are
 * announced, so the user can still write — the Support screen likewise keeps the address visible on
 * its own button. Nothing is sent from the app and nothing is claimed: the email is the user's to
 * send. The control writes nothing to the server and persists nothing; its only state is "the last
 * open failed".
 */

import { useMemo, useRef, useState } from 'react';
import { AccessibilityInfo, Linking, StyleSheet, Text, View } from 'react-native';

import { Button } from '@/src/components/ui';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { TransferRole } from '@/src/lib/transfer/transferState';
import {
  openOrderSupportMail,
  ORDER_SUPPORT_COPY,
  orderSupportDraft,
  type OrderSupportRow,
} from '@/src/lib/support/orderSupport';

export function OrderSupportAction({ role, transfer }: { role: TransferRole; transfer: OrderSupportRow }) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const [couldNotOpen, setCouldNotOpen] = useState(false);
  // One open at a time: a double tap must not stack two compose sheets.
  const opening = useRef(false);

  const draft = orderSupportDraft(transfer, role);
  if (!draft) return null;
  const { url, orderId } = draft;

  async function contact() {
    if (opening.current) return;
    opening.current = true;
    try {
      const opened = await openOrderSupportMail(url, (u) => Linking.openURL(u));
      setCouldNotOpen(!opened);
      if (!opened) AccessibilityInfo.announceForAccessibility(ORDER_SUPPORT_COPY.couldNotOpen(orderId));
    } finally {
      opening.current = false;
    }
  }

  return (
    <View style={s.wrap}>
      <Button
        label={ORDER_SUPPORT_COPY.action}
        variant="secondary"
        onPress={() => { void contact(); }}
        block
        accessibilityHint={ORDER_SUPPORT_COPY.hint}
      />
      {couldNotOpen ? (
        <Text style={[textStyle('bodySm'), s.fallback]} selectable accessibilityLiveRegion="polite">
          {ORDER_SUPPORT_COPY.couldNotOpen(orderId)}
        </Text>
      ) : null}
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    wrap: { marginTop: v2.space.lg, gap: v2.space.xs },
    fallback: { color: p.text.secondary, textAlign: 'center' },
  });
}
