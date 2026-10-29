/**
 * src/components/tickets/TicketQR.tsx — the admission code, drawn from ONE opaque server token.
 *
 * Fixed black modules on a white field whatever the app theme (a camera needs contrast, not a
 * preference), the standard 4-module quiet zone inside the SVG itself, and `cachePolicy="none"` so
 * the rendered token is never written to expo-image's disk cache (a credential lives in memory
 * only). The image is labelled, not decorative: VoiceOver says which ticket this code belongs to.
 *
 * Size and EC level come from `chooseQrRender` (C-R2): EC M at ≥ 3 pt per module when it fits,
 * EC L when M would not, the preferred 320 pt otherwise. The rounded card sits OUTSIDE the symbol
 * (C-R3): a white margin of `CARD_MARGIN` surrounds the square image, so the corner radius clips
 * only that margin and never the quiet zone — the margin exceeds the depth a radius cuts into a
 * corner, r·(1 − 1/√2).
 *
 * Nothing here knows what the token means. If it cannot be encoded the component renders nothing
 * and says so through `onEncodeFailure`, so the caller shows the pinned "unavailable" copy.
 */
import { Image } from 'expo-image';
import { useEffect, useMemo } from 'react';
import { StyleSheet, View } from 'react-native';

import { qrSvg } from '@/src/lib/qr/qrEncode';
import { chooseQrRender } from '@/src/lib/qr/qrLayout';

export const CARD_RADIUS = 14;
/** ≥ CARD_RADIUS·(1 − 1/√2) ≈ 4.1 pt, so the rounding never reaches the symbol's quiet zone. */
export const CARD_MARGIN = 8;

export function TicketQR({
  token,
  label,
  available,
  onEncodeFailure,
}: {
  token: string;
  label: string;
  /** Width the screen can give the whole card, margin included. */
  available: number;
  onEncodeFailure?: () => void;
}) {
  const rendered = useMemo(() => {
    const r = chooseQrRender(token, available - 2 * CARD_MARGIN);
    if (!r) return null;
    return { ...r, uri: 'data:image/svg+xml;utf8,' + encodeURIComponent(qrSvg(r.matrix)) };
  }, [token, available]);

  useEffect(() => {
    if (rendered === null) onEncodeFailure?.();
  }, [rendered, onEncodeFailure]);

  if (rendered === null) return null;
  const outer = rendered.size + 2 * CARD_MARGIN;

  return (
    <View
      style={[s.card, { width: outer, height: outer }]}
      accessible
      accessibilityRole="image"
      accessibilityLabel={label}
      testID={rendered.belowMinimum ? 'ticket-qr-below-min-pitch' : 'ticket-qr'}
    >
      <Image
        source={{ uri: rendered.uri }}
        style={{ width: rendered.size, height: rendered.size }}
        contentFit="contain"
        cachePolicy="none"
        accessible={false}
      />
    </View>
  );
}

const s = StyleSheet.create({
  card: {
    backgroundColor: '#FFFFFF',
    borderRadius: CARD_RADIUS,
    padding: CARD_MARGIN,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
