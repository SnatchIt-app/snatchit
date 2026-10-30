/**
 * src/lib/feedback/haptics.ts — haptics with meanings (CFT-202, CFT-206).
 *
 * Four meanings and no more. A haptic is never the only feedback: every call
 * site pairs it with a visible state change, so a user with haptics off, a
 * device without an engine, or a screen-reader user loses nothing. Navigation
 * is silent — a tab or back tap is not an event.
 *
 *  - select   a light tick when a filter or option is chosen (Chip).
 *  - confirm  a restrained acknowledgement AFTER the server accepted a bid.
 *  - success  the one distinctive response, reserved for a completed purchase
 *             or a confirmed receipt — after authoritative confirmation only.
 *  - warning  something the user must look at (outbid, hold lost).
 *
 * Fire-and-forget, and every call swallows its error: a missing engine, the
 * simulator or a web build must never throw into a purchase flow. iOS applies
 * the system "System Haptics" switch on its own; there is no in-app toggle
 * (that needs a preference column, tracked under A-15's settings work).
 */

import * as Haptics from 'expo-haptics';

export type HapticMeaning = 'select' | 'confirm' | 'success' | 'warning';

function fire(p: Promise<void>): void {
  p.catch(() => {});
}

/** A light tick: a filter or option was chosen. */
export function hapticSelect(): void {
  fire(Haptics.selectionAsync());
}

/** Restrained: the server accepted a bid. Never before the response. */
export function hapticConfirm(): void {
  fire(Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light));
}

/** Distinctive: a completed purchase or confirmed receipt. Authoritative only. */
export function hapticSuccess(): void {
  fire(Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success));
}

/** Attention: outbid, hold lost. Pairs with a visible banner or toast. */
export function hapticWarning(): void {
  fire(Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning));
}

/** The meaning → call map, for tests and for anything that routes by name. */
export const HAPTIC: Record<HapticMeaning, () => void> = {
  select: hapticSelect,
  confirm: hapticConfirm,
  success: hapticSuccess,
  warning: hapticWarning,
};
