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
  | { navigate: false; reason: 'loading' | 'recovery' | 'onboarding' | 'same_phase' }
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
}

/**
 * The root layout's whole navigation policy, as a pure function.
 *
 * The three holds come first and, importantly, do NOT record a phase: whatever
 * is holding will end, and the boundary is then evaluated honestly.
 */
export function rootRouteDecision(input: RootRouteInput): RootRouteDecision {
  if (input.loading) return { navigate: false, reason: 'loading' };
  if (input.isRecovery) return { navigate: false, reason: 'recovery' };
  if (input.onboarding) return { navigate: false, reason: 'onboarding' };

  // The fix: a session object that changed without the phase changing is a token
  // refresh or a user update. It is not a sign-in and must not move anyone.
  if (input.phase === input.lastRoutedPhase) return { navigate: false, reason: 'same_phase' };

  return { navigate: true, to: input.phase === 'signed_out' ? '/(auth)/login' : '/(tabs)/home' };
}

/**
 * Which Supabase auth events can change the phase, documented so the intent is
 * checkable rather than folded into an event-name switch. The routing code reads
 * the phase, never the event name, so an event Supabase adds later cannot cause
 * a stray redirect.
 */
export const PHASE_CHANGING_EVENTS = ['INITIAL_SESSION', 'SIGNED_IN', 'SIGNED_OUT'] as const;
export const PHASE_PRESERVING_EVENTS = ['TOKEN_REFRESHED', 'USER_UPDATED', 'PASSWORD_RECOVERY', 'MFA_CHALLENGE_VERIFIED'] as const;
