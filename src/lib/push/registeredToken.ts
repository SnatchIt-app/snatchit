/**
 * src/lib/push/registeredToken.ts — the device's registered Expo push token,
 * remembered in memory so sign-out can deactivate it (CFT-611).
 *
 * usePushToken registers the token at the app root; nothing else in the app
 * could read it back. This tiny module is the handoff. It holds the value only
 * for the life of the process and is cleared when the token is deactivated.
 */

let registered: string | null = null;

export function setRegisteredPushToken(token: string | null): void {
  registered = token;
}

export function getRegisteredPushToken(): string | null {
  return registered;
}
