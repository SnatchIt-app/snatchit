/**
 * ProofImageViewer — in-app full-screen viewer for proof-of-transfer images.
 *
 * Replaces the old `Linking.openURL(signedUrl)` behavior that bounced the
 * user out to Safari (and put a signed storage URL in the system browser).
 * Proof images live in the PRIVATE `proof-docs` bucket behind short-lived
 * signed URLs (migration 034 RLS), so they must never leave the app.
 *
 *   • full-screen modal, dark background, safe-area close button
 *   • pinch-to-zoom + pan via native ScrollView zoom (iOS)
 *   • double-tap toggles zoom in/out at the tapped point
 *   • swipe down (while not zoomed) dismisses
 *   • loading spinner + error state with retry
 *   • back gesture / hardware back (onRequestClose) closes the viewer
 *   • portrait and landscape images both fit via resizeMode="contain"
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Image,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { colors, fontSize, radius, spacing } from '@/src/theme';

interface Props {
  /** Signed URL of the proof image. null/undefined = viewer hidden. */
  uri: string | null;
  onClose: () => void;
}

const DOUBLE_TAP_MS = 300;
const ZOOM_SCALE = 2.5;

export function ProofImageViewer({ uri, onClose }: Props) {
  const { width, height } = useWindowDimensions();
  const [phase, setPhase] = useState<'loading' | 'ready' | 'error'>('loading');
  const [retryKey, setRetryKey] = useState(0);
  const scrollRef = useRef<ScrollView>(null);
  const lastTapRef = useRef(0);
  const zoomedRef = useRef(false);

  // Reset per image so a reopened viewer never shows a stale error/zoom.
  useEffect(() => {
    setPhase('loading');
    zoomedRef.current = false;
  }, [uri, retryKey]);

  const handleTap = useCallback(
    (x: number, y: number) => {
      const now = Date.now();
      if (now - lastTapRef.current < DOUBLE_TAP_MS) {
        lastTapRef.current = 0;
        // scrollResponderZoomTo is iOS-only; fall back to a no-op elsewhere
        // (pinch-to-zoom still works everywhere ScrollView zoom does).
        const responder =
          (scrollRef.current as unknown as {
            scrollResponderZoomTo?: (rect: {
              x: number; y: number; width: number; height: number; animated: boolean;
            }) => void;
            getScrollResponder?: () => {
              scrollResponderZoomTo?: (rect: {
                x: number; y: number; width: number; height: number; animated: boolean;
              }) => void;
            };
          }) ?? null;
        const zoomTo =
          responder?.scrollResponderZoomTo ??
          responder?.getScrollResponder?.()?.scrollResponderZoomTo;
        if (!zoomTo) return;
        if (zoomedRef.current) {
          zoomTo({ x: 0, y: 0, width, height, animated: true });
          zoomedRef.current = false;
        } else {
          const w = width / ZOOM_SCALE;
          const h = height / ZOOM_SCALE;
          zoomTo({ x: x - w / 2, y: y - h / 2, width: w, height: h, animated: true });
          zoomedRef.current = true;
        }
      } else {
        lastTapRef.current = now;
      }
    },
    [width, height],
  );

  return (
    <Modal
      visible={!!uri}
      animationType="fade"
      onRequestClose={onClose}
      supportedOrientations={['portrait', 'landscape']}
      statusBarTranslucent
    >
      <View style={s.backdrop}>
        {uri ? (
          phase === 'error' ? (
            <View style={s.center}>
              <Text style={s.errorText}>{"Couldn't load the image."}</Text>
              <Pressable style={s.retryBtn} onPress={() => setRetryKey((k) => k + 1)}>
                <Text style={s.retryText}>Try again</Text>
              </Pressable>
            </View>
          ) : (
            <ScrollView
              ref={scrollRef}
              style={s.zoomScroll}
              contentContainerStyle={{ width, height }}
              maximumZoomScale={4}
              minimumZoomScale={1}
              bouncesZoom
              alwaysBounceVertical
              showsHorizontalScrollIndicator={false}
              showsVerticalScrollIndicator={false}
              centerContent
              onScrollEndDrag={(e) => {
                // Swipe-to-dismiss: a firm pull-down while NOT zoomed closes
                // the viewer. While zoomed, vertical drags stay pans.
                const { contentOffset, zoomScale } = e.nativeEvent;
                if ((zoomScale ?? 1) <= 1.05 && contentOffset.y < -80) onClose();
              }}
            >
              <Pressable
                onPress={(e) => handleTap(e.nativeEvent.locationX, e.nativeEvent.locationY)}
                style={{ width, height }}
              >
                <Image
                  key={retryKey}
                  source={{ uri }}
                  style={{ width, height }}
                  resizeMode="contain"
                  onLoad={() => setPhase('ready')}
                  onError={() => setPhase('error')}
                  accessibilityLabel="Proof of transfer image, full screen"
                />
              </Pressable>
            </ScrollView>
          )
        ) : null}

        {phase === 'loading' && !!uri && (
          <View style={s.loadingOverlay} pointerEvents="none">
            <ActivityIndicator color={colors.text} size="large" />
          </View>
        )}

        <SafeAreaView style={s.chrome} pointerEvents="box-none" edges={['top']}>
          <Pressable
            onPress={onClose}
            style={s.closeBtn}
            hitSlop={12}
            accessibilityRole="button"
            accessibilityLabel="Close image viewer"
          >
            <Text style={s.closeText}>{'✕'}</Text>
          </Pressable>
        </SafeAreaView>
      </View>
    </Modal>
  );
}

const s = StyleSheet.create({
  backdrop:   { flex: 1, backgroundColor: '#000' },
  zoomScroll: { flex: 1 },
  center:     { flex: 1, alignItems: 'center', justifyContent: 'center', gap: spacing.md },

  loadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
  },

  chrome: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    alignItems: 'flex-end',
  },
  closeBtn: {
    margin: spacing.md,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  closeText: { color: '#fff', fontSize: fontSize.lg, fontWeight: '600' },

  errorText: { color: colors.textMuted, fontSize: fontSize.md },
  retryBtn: {
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
  },
  retryText: { color: colors.text, fontSize: fontSize.md, fontWeight: '600' },
});
