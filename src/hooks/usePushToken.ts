/**
 * src/hooks/usePushToken.ts
 *
 * Registers the device's Expo push token in the push_tokens table.
 * Call once at app root when the user is authenticated.
 *
 * - Skips silently on simulators / emulators (push tokens require real devices)
 * - Requests permission, then upserts the token row
 * - Sets up Android default notification channel
 * - Never throws — all errors are caught and logged
 */
import { useEffect, useState } from 'react';
import { Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';

import { supabase } from '@/src/lib/supabase';

type PushTokenResult = {
  pushToken:         string | null;
  permissionGranted: boolean;
};

export function usePushToken(userId: string | undefined): PushTokenResult {
  const [pushToken, setPushToken]                   = useState<string | null>(null);
  const [permissionGranted, setPermissionGranted]   = useState(false);

  useEffect(() => {
    if (!userId) return;

    async function register() {
      try {
        // 1. Physical device check — push tokens don't work on simulators
        if (!Device.isDevice) {
          console.log('[usePushToken] Skipping — not a physical device');
          return;
        }

        // 2. Request permission
        let { status } = await Notifications.getPermissionsAsync();
        if (status !== 'granted') {
          const res = await Notifications.requestPermissionsAsync();
          status = res.status;
        }
        if (status !== 'granted') {
          console.log('[usePushToken] Permission not granted');
          return;
        }
        setPermissionGranted(true);

        // 3. Android notification channel
        if (Platform.OS === 'android') {
          await Notifications.setNotificationChannelAsync('default', {
            name: 'Default',
            importance: Notifications.AndroidImportance.MAX,
            vibrationPattern: [0, 250, 250, 250],
          });
        }

        // 4. Get Expo push token
        const projectId = Constants.expoConfig?.extra?.eas?.projectId;
        const { data: tokenData } = await Notifications.getExpoPushTokenAsync(
          projectId ? { projectId } : undefined,
        );
        const token = tokenData;
        setPushToken(token);

        // 5. Upsert to push_tokens table
        const platform = Platform.OS as 'ios' | 'android';
        const { data: existing } = await supabase
          .from('push_tokens')
          .select('id')
          .eq('token', token)
          .maybeSingle();

        if (existing) {
          await supabase
            .from('push_tokens')
            .update({ last_used: new Date().toISOString(), is_active: true })
            .eq('id', existing.id);
        } else {
          await supabase
            .from('push_tokens')
            .insert({ user_id: userId, token, platform, is_active: true });
        }

        console.log('[usePushToken] Registered:', token);
      } catch (err) {
        console.warn('[usePushToken] Error:', err instanceof Error ? err.message : err);
      }
    }

    register();
  }, [userId]);

  return { pushToken, permissionGranted };
}
