/**
 * src/components/tickets/TicketQR.tsx — the admission code, drawn from ONE opaque server token.
 *
 * Fixed black modules on a white field whatever the app theme (a camera needs contrast, not a
 * preference), the standard 4-module quiet zone inside the SVG itself, and `cachePolicy="none"` so
 * the rendered token is never written to expo-image's disk cache (a credential lives in memory
 * only). The image is labelled, not decorative: VoiceOver says which ticket this code belongs to.
 *
 * Nothing here knows what the token means. If it cannot be encoded (it never should: the wire is
 * ≤ 8192 chars and a real credential is ~350), the component renders nothing and says so through
 * `onEncodeFailure`, so the caller shows the pinned "unavailable" copy instead of an empty square.
 */
import { Image } from 'expo-image';
import { useEffect, useMemo } from 'react';
import { StyleSheet, View } from 'react-native';

import { encodeQr, qrSvg } from '@/src/lib/qr/qrEncode';

const RADIUS = 14;

export function TicketQR({
  token,
  label,
  size,
  onEncodeFailure,
}: {
  token: string;
  label: string;
  size: number;
  onEncodeFailure?: () => void;
}) {
  const uri = useMemo(() => {
    try {
      return 'data:image/svg+xml;utf8,' + encodeURIComponent(qrSvg(encodeQr(token, { ec: 'M' })));
    } catch {
      return null;
    }
  }, [token]);

  useEffect(() => {
    if (uri === null) onEncodeFailure?.();
  }, [uri, onEncodeFailure]);

  if (uri === null) return null;

  return (
    <View
      style={[s.card, { width: size, height: size }]}
      accessible
      accessibilityRole="image"
      accessibilityLabel={label}
    >
      <Image
        source={{ uri }}
        style={{ width: size, height: size }}
        contentFit="contain"
        cachePolicy="none"
        accessible={false}
      />
    </View>
  );
}

const s = StyleSheet.create({
  card: { backgroundColor: '#FFFFFF', borderRadius: RADIUS, overflow: 'hidden' },
});
