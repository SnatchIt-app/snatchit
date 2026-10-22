/**
 * src/lib/moderation/blockFlow.ts — RC3 S5: the Block entry on the two order screens.
 *
 * `showMoreActions` is the listing screen's overflow pattern (iOS action sheet, Android alert) made
 * shareable. `confirmBlock` shows the K1 confirmation and, on Block, writes ONE `user_blocks` row —
 * and nothing else: no transfer or order column, no RPC, no navigation. Existing orders are exempt
 * from the block on the server (152), so the order screen stays exactly as it was. Under a harness
 * fixture (`write: false`) the dialog renders but the Block press writes nothing (a render is a
 * picture of the screen, never a sandbox mutation).
 */
import { ActionSheetIOS, Alert, Platform } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { ACTION_FAILED_COPY } from '@/src/lib/ui/errorCopy';
import { blockConfirmMessage, blockConfirmTitle } from '@/src/lib/moderation/blockCopy';

export type MoreAction = { label: string; destructive?: boolean; handler: () => void };

export function showMoreActions(actions: MoreAction[]): void {
  if (actions.length === 0) return;
  if (Platform.OS === 'ios') {
    ActionSheetIOS.showActionSheetWithOptions(
      {
        options: [...actions.map((a) => a.label), 'Cancel'],
        cancelButtonIndex: actions.length,
        destructiveButtonIndex: actions.reduce((idx, a, i) => (a.destructive ? i : idx), -1),
      },
      (idx) => {
        if (idx >= 0 && idx < actions.length) actions[idx].handler();
      },
    );
    return;
  }
  Alert.alert('More actions', '', [
    ...actions.map((a) => ({
      text: a.label,
      onPress: a.handler,
      style: (a.destructive ? 'destructive' : 'default') as 'destructive' | 'default',
    })),
    { text: 'Cancel', style: 'cancel' as const },
  ]);
}

export function confirmBlock(i: {
  viewerId: string;
  targetId: string;
  targetName: string;
  /** false under a harness fixture: the dialog shows, the Block press writes nothing. */
  write: boolean;
  onBlocked?: () => void;
}): void {
  Alert.alert(blockConfirmTitle(i.targetName), blockConfirmMessage(), [
    { text: 'Cancel', style: 'cancel' },
    {
      text: 'Block',
      style: 'destructive',
      onPress: async () => {
        if (!i.write) return;
        const { error } = await supabase.from('user_blocks').insert({ blocker_id: i.viewerId, blocked_id: i.targetId });
        // 23505 = unique_violation → already blocked. Treat as success, as the other two surfaces do.
        if (error && error.code !== '23505') {
          console.warn('[block]', error.message);
          Alert.alert(ACTION_FAILED_COPY.block.title, ACTION_FAILED_COPY.block.body);
          return;
        }
        Alert.alert('Blocked', `${i.targetName} is hidden from your feed. Unblock anytime in Settings.`);
        i.onBlocked?.();
      },
    },
  ]);
}
