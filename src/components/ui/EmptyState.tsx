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

import type { ViewStyle } from 'react-native';

import { StateView } from './StateView';

export interface EmptyStateProps {
  /** Short. Three or four words. Rendered in the brand display face. */
  title: string;
  /** One sentence. Optional — a good title often needs no help. */
  body?: string;
  action?: { label: string; onPress: () => void };
  style?: ViewStyle;
  testID?: string;
}

/** The genuinely-empty state: one implementation with the failure and no-match states (StateView). */
export function EmptyState({ title, body, action, style, testID }: EmptyStateProps) {
  return <StateView kind="empty" title={title} body={body} action={action} style={style} testID={testID} />;
}
