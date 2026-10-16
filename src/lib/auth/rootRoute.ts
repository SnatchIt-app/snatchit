/**
 * src/lib/auth/rootRoute.ts — when the ROOT layout is allowed to navigate.
 *
 * THE BUG THIS FIXES. The root layout redirected on every change of the session
 * object. Supabase hands a fresh session object to `onAuthStateChange` for events
 * that are not sign-ins at all: `USER_UPDATED` and `TOKEN_REFRESHED` both carry
 * one. So a signed-in person in Settings who tapped "Send code" hit
 * `updateUser({ phone })`, Supabase emitted `USER_UPDATED`, `useAuth` stored the
 * new object, this effect saw its dependency change, and the root layout threw
 * them onto Home — while the SMS was already on its way. Same defect on every
 * hourly token refresh, which would yank anyone out of any screen.
 *
 * THE RULE. Navigation belongs to a change of AUTHENTICATION PHASE, not to a
 * change of session object identity. Signed out is one phase; signed in as a
 * given person is another. Everything Supabase reports in between — a refreshed
 * token, a changed phone, a changed password, updated metadata — leaves the phase
 * alone, so the root layout stays out of the way and whatever screen the person
 * is on keeps control of its own flow.
 *
 * The phase carries the user id, so signing out of one account and into another
 * is still a real transition and still routes.
 *
 * This module decides only WHETHER and WHERE the root navigates. Screens own
 * their own completion: an OTP screen advances itself when the send succeeds and
 * completes itself when the verification succeeds. Nothing here waits on an auth
 * event to decide where a flow should go.
 */

export type AuthPhase = 'signed_out' | `signed_in:${string}`;

/** The phase a session represents. Object identity is deliberately ignored. */
export function authPhase(session: { user?: { id?: string | null } | null } | null | undefined): AuthPhase {
  const id = session?.user?.id;
  if (!id) return 'signed_out';
  return `signed_in:${id}`;
}

export type RootRouteTarget = '/(tabs)/home' | '/(auth)/login';

export type RootRouteDecision =
  | { navigate: false; reason: 'loading' | 'navigator' | 'recovery' | 'onboarding' | 'same_phase' }
  | { navigate: true; to: RootRouteTarget };

export interface RootRouteInput {
  /** The initial session check has not settled yet. */
  loading: boolean;
  /** A password-recovery link is being handled; that flow owns navigation. */
  isRecovery: boolean;
  /** Sign up is mid flow; the signup screen owns navigation. */
  onboarding: boolean;
  /** The phase right now. */
  phase: AuthPhase;
  /** The phase this layout last navigated for, or null before the first route. */
  lastRoutedPhase: AuthPhase | null;
  /**
   * The current route is inside the signed-in area (the tabs, K-2). A deep link can land there while
   * signed out — Expo Router routes snatchit://?code=… to "/" → Home — without any phase change.
   */
  inSignedInArea?: boolean;
  /**
   * N7c: the root Stack exists. A replace issued before it mounts makes Expo Router remount the whole root
   * layout (production T1, 2026-10-16), so the rule waits. Omitted means ready, as before.
   */
  navigatorReady?: boolean;
}

/**
 * The root layout's whole navigation policy, as a pure function.
 *
 * The three holds come first and, importantly, do NOT record a phase: whatever
 * is holding will end, and the boundary is then evaluated honestly.
 */
export function rootRouteDecision(input: RootRouteInput): RootRouteDecision {
  if (input.loading) return { navigate: false, reason: 'loading' };
  if (input.navigatorReady === false) return { navigate: false, reason: 'navigator' };
  if (input.isRecovery) return { navigate: false, reason: 'recovery' };
  if (input.onboarding) return { navigate: false, reason: 'onboarding' };

  // The fix: a session object that changed without the phase changing is a token
  // refresh or a user update. It is not a sign-in and must not move anyone.
  if (input.phase === input.lastRoutedPhase) {
    // K-2 on deep links (C's simulator check, 2026-10-15): a signed-out person who lands on a tab —
    // e.g. a recovery link with no pending reset on this phone, routed "/" → Home — goes to login.
    if (input.phase === 'signed_out' && input.inSignedInArea) return { navigate: true, to: '/(auth)/login' };
    return { navigate: false, reason: 'same_phase' };
  }

  return { navigate: true, to: input.phase === 'signed_out' ? '/(auth)/login' : '/(tabs)/home' };
}

/** N7: whether the current route is the reset screen, app/(auth)/reset-password.tsx. */
export function isResetScreen(segments: readonly string[]): boolean {
  return segments[0] === '(auth)' && segments[1] === 'reset-password';
}

/**
 * N7: where the recovery hold puts the person, applied by the root layout once its navigator is ready.
 *
 * Builds 25/27 navigated to the reset screen from inside the deep-link handler. On a cold start that
 * call ran before the Stack mounted (expo-router throws), and on a warm start Expo Router's own handling
 * of `snatchit://?code=…` routed to "/" → Home in no fixed order with it. The move is now a function of
 * state: while the hold is up, the reset screen; when the hold is released with no session (the link's
 * claim failed, F7), off the reset screen to login, where a new link can be requested. With no hold the
 * guard never moves anyone — rootRouteDecision owns every other navigation.
 */
export function recoveryRouteTarget(input: {
  isRecovery: boolean;
  onResetScreen: boolean;
  signedIn: boolean;
  loading: boolean;
}): '/(auth)/reset-password' | '/(auth)/login' | null {
  if (input.isRecovery) return input.onResetScreen ? null : '/(auth)/reset-password';
  if (input.onResetScreen && !input.loading && !input.signedIn) return '/(auth)/login';
  return null;
}

/**
 * Which Supabase auth events can change the phase, documented so the intent is
 * checkable rather than folded into an event-name switch. The routing code reads
 * the phase, never the event name, so an event Supabase adds later cannot cause
 * a stray redirect.
 */
export const PHASE_CHANGING_EVENTS = ['INITIAL_SESSION', 'SIGNED_IN', 'SIGNED_OUT'] as const;
export const PHASE_PRESERVING_EVENTS = ['TOKEN_REFRESHED', 'USER_UPDATED', 'PASSWORD_RECOVERY', 'MFA_CHALLENGE_VERIFIED'] as const;
