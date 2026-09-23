/**
 * src/components/ui/StateView.tsx — the one way a screen says "nothing to show
 * here, and why": offline, server error, genuinely empty, or no match.
 *
 * Premium primitives only: the display face for the title, body for the
 * sentence, the app Button for the action, one 56 pt glyph disc for the
 * failure and no-match states (none for empty — EmptyState's discipline).
 * Nothing animates, so Reduce Motion needs no special case. Failure states
 * are announced to VoiceOver and exposed as an alert region; the action is a
 * real button with a 44 pt target. Screens show this only when they have no
 * cached content to keep on screen (a failed quiet refresh keeps the rows).
 */

import { useEffect } from 'react';
import { AccessibilityInfo, StyleSheet, Text, View, type ViewStyle } from 'react-native';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { STATE_COPY } from '@/src/lib/ui/loadState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

import { Button } from './Button';

export type StateKind = 'offline' | 'error' | 'empty' | 'noMatch';

export interface StateViewProps {
  kind: StateKind;
  /** Defaults to the shared copy for offline / error / noMatch; required for empty. */
  title?: string;
  body?: string;
  action?: { label: string; onPress: () => void | Promise<void>; busy?: boolean };
  style?: ViewStyle;
  testID?: string;
}

const GLYPH: Record<StateKind, 'wifi.slash' | 'exclamationmark.triangle' | 'magnifyingglass' | null> = {
  offline: 'wifi.slash',
  error: 'exclamationmark.triangle',
  noMatch: 'magnifyingglass',
  empty: null,
};

export function StateView({ kind, title, body, action, style, testID }: StateViewProps) {
  const failure = kind === 'offline' || kind === 'error';
  const resolvedTitle = title ?? (kind === 'empty' ? '' : STATE_COPY[kind].title);
  const resolvedBody = body ?? (kind === 'empty' ? undefined : STATE_COPY[kind].body);

  useEffect(() => {
    if (failure) AccessibilityInfo.announceForAccessibility(`${resolvedTitle}. ${resolvedBody ?? ''}`.trim());
  }, [failure, resolvedTitle, resolvedBody]);

  const glyph = GLYPH[kind];
  return (
    <View
      style={[styles.wrap, style]}
      testID={testID}
      accessibilityRole={failure ? 'alert' : undefined}
    >
      {glyph ? (
        <View style={[styles.glyph, failure ? styles.glyphFailure : null]} accessible={false}>
          <IconSymbol name={glyph} size={26} color={kind === 'error' ? v2.status.warning : v2.text.secondary} />
        </View>
      ) : null}
      {/* V3 §2: the empty/error heading joins the mixed-case display voice (nameState). */}
      <Text style={[textStyle('nameState'), styles.title]} accessibilityRole="header">{resolvedTitle}</Text>
      {resolvedBody ? <Text style={[textStyle('body'), styles.body]}>{resolvedBody}</Text> : null}
      {action ? (
        <Button
          label={action.label}
          pendingLabel={failure ? 'Retrying…' : undefined}
          onPress={action.onPress}
          loading={action.busy}
          disabled={action.busy}
          variant={failure ? 'primary' : 'secondary'}
          size="md"
          style={styles.action}
        />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: v2.space.xl,
    paddingVertical: v2.space.xxxl,
    gap: v2.space.sm,
  },
  glyph: {
    width: 56, height: 56, borderRadius: 28,
    alignItems: 'center', justifyContent: 'center',
    backgroundColor: v2.surface.surface, borderWidth: 1, borderColor: v2.border.default,
    marginBottom: v2.space.xs,
  },
  glyphFailure: { borderColor: v2.border.strong },
  title: { color: v2.text.primary, textAlign: 'center' },
  body: { color: v2.text.muted, textAlign: 'center', maxWidth: 320 },
  action: { marginTop: v2.space.md, paddingHorizontal: v2.space.xl, minWidth: 160 },
});
