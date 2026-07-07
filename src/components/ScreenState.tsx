/**
 * ScreenState — full-screen fallback states for network-dependent screens.
 *
 * Distinct states (never one screen for every failure):
 *   loading — centered spinner
 *   offline — "You're offline" + retry (auto-retries when connection returns)
 *   error   — server/application failure + retry
 *
 * Empty states stay screen-specific (each screen keeps its own copy/CTA).
 */

import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';

export type ScreenStateKind = 'loading' | 'offline' | 'error';

type Props = {
  state: ScreenStateKind;
  /** Called on Retry tap — and automatically when connectivity returns. */
  onRetry?: () => void | Promise<void>;
};

export default function ScreenState({ state, onRetry }: Props) {
  const { isOffline } = useNetworkStatus();
  const [retrying, setRetrying] = useState(false);
  const wasOffline = useRef(isOffline);

  async function retry() {
    if (!onRetry || retrying) return;
    setRetrying(true);
    try { await onRetry(); } finally { setRetrying(false); }
  }

  // Auto-retry the moment the connection comes back.
  useEffect(() => {
    if (state === 'offline' && wasOffline.current && !isOffline) retry();
    wasOffline.current = isOffline;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOffline, state]);

  if (state === 'loading') {
    return (
      <View style={s.wrap}>
        <ActivityIndicator color={colors.primary} size="large" />
      </View>
    );
  }

  const offline = state === 'offline';
  return (
    <View style={s.wrap}>
      <View style={s.iconCircle}>
        <Text style={s.icon}>{offline ? '📡' : '⚠️'}</Text>
      </View>
      <Text style={s.title}>{offline ? "You're offline" : 'Something went wrong'}</Text>
      <Text style={s.subtitle}>
        {offline
          ? 'Check your internet connection and try again.'
          : "We couldn't load this right now. Please try again."}
      </Text>
      {onRetry && (
        <Pressable
          style={[s.retryBtn, retrying && s.retryBtnBusy]}
          onPress={retry}
          disabled={retrying}
          hitSlop={8}
        >
          {retrying ? (
            <ActivityIndicator color={colors.text} size="small" />
          ) : (
            <Text style={s.retryText}>Retry</Text>
          )}
        </Pressable>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  wrap: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.xl,
    gap: spacing.sm,
  },
  iconCircle: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.xs,
  },
  icon: { fontSize: 30 },
  title: {
    fontSize: fontSize.lg,
    fontWeight: '800',
    color: colors.text,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    textAlign: 'center',
    lineHeight: 20,
  },
  retryBtn: {
    marginTop: spacing.md,
    minWidth: 140,
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: 12,
    paddingHorizontal: spacing.lg,
  },
  retryBtnBusy: { opacity: 0.7 },
  retryText: { color: colors.text, fontWeight: '700', fontSize: fontSize.md },
});
