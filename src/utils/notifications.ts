/**
 * src/utils/notifications.ts
 *
 * Helpers for scheduling local notifications.
 * Wraps expo-notifications — never throws.
 */
import * as Notifications from 'expo-notifications';

/** Schedule an immediate local notification (shows in system tray). */
export async function sendLocalNotification(params: {
  title: string;
  body: string;
  data?: Record<string, unknown>;
}): Promise<void> {
  try {
    await Notifications.scheduleNotificationAsync({
      content: {
        title: params.title,
        body: params.body,
        data: params.data ?? {},
        sound: 'default',
      },
      trigger: null, // null = fire immediately
    });
  } catch (error) {
    console.warn('[notifications] Failed to send local notification:', error);
  }
}
