/**
 * src/providers/NativeAppShell.web.tsx
 *
 * Web passthrough — no Sentry, Stripe, Notifications, or Linking.
 * Platform resolution ensures the web bundle picks this file.
 */

import React from 'react';

/** Identity wrapper — no StripeProvider on web. */
export function AppShell({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}

/** No-op on web — no Sentry user tracking. */
export function setSentryUser(_user: { id: string; email?: string } | null) {}

/** Identity — no Sentry.wrap on web. */
export function wrapRootComponent(component: React.ComponentType): React.ComponentType {
  return component;
}

/** No-op on web — no deep links or push tokens. */
export function useNativeEffects(_opts: {
  userId?: string;
  isRecovery: boolean;
  setIsRecovery: (v: boolean) => void;
}) {}
