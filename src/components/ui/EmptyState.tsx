/**
 * src/components/ui/EmptyState.tsx — nothing here, said properly.
 *
 * A display line, one sentence, and at most one action. No illustration and no
 * emoji: the current product uses 🎟️ and 🔍 as its empty states, which is the
 * fastest way to look like a side project.
 *
 * Copy discipline is the point of this component. Short, second person, full
 * stops, no exclamation marks. If the sentence needs a comma and a clause to
 * explain itself, the screen is the problem, not the empty state.
 */

import { StyleSheet, Text, View, type ViewStyle } from 'react-native';

import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

import { Button } from './Button';

export interface EmptyStateProps {
  /** Short. Three or four words. Rendered in the brand display face. */
  title: string;
  /** One sentence. Optional — a good title often needs no help. */
  body?: string;
  action?: { label: string; onPress: () => void };
  style?: ViewStyle;
  testID?: string;
}

export function EmptyState({ title, body, action, style, testID }: EmptyStateProps) {
  return (
    <View style={[styles.wrap, style]} testID={testID}>
      <Text style={[textStyle('displaySm'), styles.title]}>{title}</Text>
      {body ? <Text style={[textStyle('body'), styles.body]}>{body}</Text> : null}
      {action ? (
        <Button
          label={action.label}
          onPress={action.onPress}
          variant="secondary"
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
  title: { color: v2.text.primary, textAlign: 'center' },
  body: { color: v2.text.muted, textAlign: 'center', maxWidth: 320 },
  action: { marginTop: v2.space.md, paddingHorizontal: v2.space.xl },
});
