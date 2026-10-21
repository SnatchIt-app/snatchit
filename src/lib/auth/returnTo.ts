/**
 * src/lib/auth/returnTo.ts — where a sign-in returns to (CFT-603, checklist item 44, slice 1).
 *
 * WHAT WAS WRONG. Every sign-in went to Home (rootRoute.ts). A listing link opened while signed out was replaced
 * by Sign in on a cold start and forgotten; a session that expired on a screen showed "Your session expired. Sign
 * in to pick up where you left off." and then did not pick up anywhere.
 *
 * WHAT THIS IS. One remembered screen, in process memory only (like sessionEnd.ts): nothing is persisted, so it
 * never outlives the app and never reaches another install. The root layout captures it and the root routing rule
 * reads it; this module routes nothing itself.
 *
 * THE RULES (E's review conditions).
 *  - Only the internal screens in RETURN_TO_ROUTES. A destination must be an absolute app path made of plain
 *    segments (letters, digits, '-', '_'): no scheme, no host, no '//', no '%' encoding, no backslash, no dot
 *    segment, no auth, reset-password, checkout, payout or settings route, never '/' and never a tab.
 *  - The query and the fragment are dropped whole — stricter than stripping credential-like keys — so a code, a
 *    token or an action parameter (an amount, a confirm flag) can never ride along. It is a screen, never an
 *    action: the person lands there after a fresh read and taps again.
 *  - It expires after RETURN_TO_TTL_MS and is single-use: the root consumes it on its next navigation into the
 *    signed-in area, whether that navigation used it or not.
 *  - Private screens (transfer send/receive, my-listings) come back only for the user who was signed in on them;
 *    captured signed out there is no one, so they are not captured at all. A screen captured from a signed-in
 *    session (an expiry) is bound to that user whatever the screen; a public screen captured signed out comes
 *    back for whoever signs in.
 *  - Recovery always wins: rootRouteDecision reads it only after every hold, and the root layout discards it when
 *    the recovery hold goes up.
 */
import type { AuthPhase } from '@/src/lib/auth/rootRoute';
import type { SessionEndReason } from '@/src/lib/auth/sessionEnd';

/** How long a remembered screen stays usable: 10 minutes. */
export const RETURN_TO_TTL_MS = 10 * 60_000;

export type ReturnToScope = 'public' | 'same_user';

/** The screens a sign-in may return to. Anything not listed here goes Home. */
export const RETURN_TO_ROUTES = [
  { route: 'listing/[id]', scope: 'public' },
  { route: 'bid/[id]', scope: 'public' },
  { route: 'profile/[id]', scope: 'public' },
  { route: 'transfer/send/[id]', scope: 'same_user' },
  { route: 'transfer/receive/[id]', scope: 'same_user' },
  { route: 'my-listings', scope: 'same_user' },
] as const satisfies readonly { route: string; scope: ReturnToScope }[];

export type ReturnToPath =
  | `/listing/${string}`
  | `/bid/${string}`
  | `/profile/${string}`
  | `/transfer/send/${string}`
  | `/transfer/receive/${string}`
  | '/my-listings';

export interface ReturnTarget {
  path: ReturnToPath;
  scope: ReturnToScope;
}

/** One path segment: plain characters only, so '%', '\', '.', ':', '@', '(', spaces and controls never pass. */
const SEGMENT = /^[A-Za-z0-9_-]{1,64}$/;
const MAX_PATH_LENGTH = 160;

/**
 * The allowlist, as a pure function: the bare screen and its scope, or null. The query and fragment are cut off
 * BEFORE the path is validated, so nothing after a '?' or '#' can put a host into it.
 */
export function classifyReturnPath(raw: unknown): ReturnTarget | null {
  if (typeof raw !== 'string') return null;
  const cut = raw.search(/[?#]/);
  const pathOnly = cut === -1 ? raw : raw.slice(0, cut);
  if (pathOnly.length < 2 || pathOnly.length > MAX_PATH_LENGTH || pathOnly[0] !== '/') return null;
  // An empty segment means '//' or a trailing '/': rejected with everything else that is not plain.
  const segments = pathOnly.slice(1).split('/');
  if (!segments.every((s) => SEGMENT.test(s))) return null;
  const match = matchReturnRoute(segments);
  return match ? { path: pathOnly as ReturnToPath, scope: match.entry.scope } : null;
}

type ReturnToRoute = (typeof RETURN_TO_ROUTES)[number];
/** The root Stack screen names the allowlist can open (each is a Stack.Screen in app/_layout.tsx). */
export type ReturnToRouteName = ReturnToRoute['route'];

function matchReturnRoute(segments: string[]): { entry: ReturnToRoute; id: string | null } | null {
  for (const entry of RETURN_TO_ROUTES) {
    const pattern = entry.route.split('/');
    if (pattern.length !== segments.length) continue;
    if (pattern.every((p, i) => p === '[id]' || p === segments[i])) {
      const at = pattern.indexOf('[id]');
      return { entry, id: at === -1 ? null : segments[at] };
    }
  }
  return null;
}

/**
 * The root Stack route an allowlisted screen opens as — its route name and, for a dynamic screen, its id — or
 * null for anything classifyReturnPath rejects. Used to open a remembered screen on top of the tabs
 * (returnToNav.ts); the name is always one of RETURN_TO_ROUTES, never built from the path.
 */
export function returnToStackRoute(raw: unknown): { name: ReturnToRouteName; params?: { id: string } } | null {
  const target = classifyReturnPath(raw);
  if (!target) return null;
  const match = matchReturnRoute(target.path.slice(1).split('/'));
  if (!match) return null;
  return match.id === null ? { name: match.entry.route } : { name: match.entry.route, params: { id: match.id } };
}

/** The user id a phase carries, or null when signed out. */
export function userIdOfPhase(phase: AuthPhase | null): string | null {
  if (!phase || !phase.startsWith('signed_in:')) return null;
  return phase.slice('signed_in:'.length) || null;
}

interface Entry extends ReturnTarget {
  /** The user signed in when it was captured (an expiry), or null when captured signed out. */
  ownerId: string | null;
  capturedAt: number;
}

let entry: Entry | null = null;

/**
 * Remember a screen. Returns false, storing nothing and leaving any earlier screen as it was, when the path is
 * not allowlisted or is a private screen with no signed-in owner.
 */
export function captureReturnTo(raw: unknown, ownerId: string | null, now: number = Date.now()): boolean {
  const target = classifyReturnPath(raw);
  if (!target) return false;
  const owner = ownerId || null;
  if (target.scope === 'same_user' && !owner) return false;
  entry = { ...target, ownerId: owner, capturedAt: now };
  return true;
}

function usableFor(e: Entry, userId: string | null, now: number): boolean {
  if (!userId) return false;
  const age = now - e.capturedAt;
  // A clock that moved backwards counts as expired.
  if (!(age >= 0 && age < RETURN_TO_TTL_MS)) return false;
  if (e.ownerId !== null) return e.ownerId === userId;
  return e.scope === 'public';
}

/** The screen a sign-in by `userId` would return to now, without using it up. */
export function peekReturnTo(userId: string | null, now: number = Date.now()): ReturnToPath | null {
  return entry && usableFor(entry, userId, now) ? entry.path : null;
}

/** Read and clear: the screen for `userId`, or null. Whatever was stored is gone afterwards. */
export function consumeReturnTo(userId: string | null, now: number = Date.now()): ReturnToPath | null {
  const path = peekReturnTo(userId, now);
  entry = null;
  return path;
}

export function clearReturnTo(): void {
  entry = null;
}

export type ReturnToStep = 'consumed' | 'captured' | 'cleared' | 'kept';

/**
 * What the root layout does with the remembered screen when its routing decision NAVIGATES (never on a hold):
 *  - into the signed-in area: consume it — that navigation already used it, or it was not for this user;
 *  - the first signed-out route (a cold start, perhaps from a link): capture the screen being replaced by login;
 *  - signed in → signed out: an expiry captures the screen for the user whose session ended; any other end
 *    (the person signed out, changed the password, or was signed out for a credential change) keeps nothing.
 */
export function settleReturnToOnRoute(input: {
  phase: AuthPhase;
  lastRoutedPhase: AuthPhase | null;
  pathname: string | null;
  sessionEnd: SessionEndReason | null;
  now?: number;
}): ReturnToStep {
  const now = input.now ?? Date.now();
  const userId = userIdOfPhase(input.phase);
  if (userId) {
    consumeReturnTo(userId, now);
    return 'consumed';
  }
  if (input.lastRoutedPhase === null) {
    return captureReturnTo(input.pathname, null, now) ? 'captured' : 'kept';
  }
  const endedFor = userIdOfPhase(input.lastRoutedPhase);
  if (endedFor) {
    clearReturnTo();
    if (input.sessionEnd !== 'expired') return 'cleared';
    return captureReturnTo(input.pathname, endedFor, now) ? 'captured' : 'cleared';
  }
  return 'kept';
}

/**
 * Whether a signed-out person who just ENTERED a screen should have it remembered: only once the root has routed
 * them as signed out (so an expiry has already been settled for its user), and never while recovery or sign up
 * holds the root.
 */
export function shouldCaptureOnEntry(input: { phase: AuthPhase; routedPhase: AuthPhase | null; held: boolean }): boolean {
  return input.phase === 'signed_out' && input.routedPhase === 'signed_out' && !input.held;
}
