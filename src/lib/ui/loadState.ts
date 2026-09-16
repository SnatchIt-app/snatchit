/**
 * src/lib/ui/loadState.ts — which state a failed or empty load shows, and the
 * words for it. One vocabulary for Home/Explore, Bids, Tickets and Profile
 * (owner request after the build 17 screenshots, 2026-09-16): offline, server
 * error, genuinely empty and no-match are four different states and never
 * share a screen.
 */

export type LoadFailureKind = 'offline' | 'error';

/**
 * True when an error smells like a connectivity failure rather than a
 * server/application error (fetch throws before any HTTP response exists).
 */
export function isNetworkError(err: unknown): boolean {
  const msg =
    typeof err === 'string' ? err
    : err instanceof Error ? err.message
    : (err as { message?: string } | null)?.message ?? '';
  return /network request failed|failed to fetch|fetch failed|network error|abort/i.test(msg);
}

/** Offline when the OS says so or the error is a connectivity failure; otherwise the server did not answer well. */
export function classifyLoadFailure(err: unknown, isOffline: boolean): LoadFailureKind {
  if (isOffline) return 'offline';
  return isNetworkError(err) ? 'offline' : 'error';
}

export const STATE_COPY = {
  offline: {
    title: "You're offline",
    body: 'Check your internet connection and try again.',
    retry: 'Retry',
  },
  error: {
    title: "Couldn't load this",
    body: 'Our side did not answer in time. Try again in a moment.',
    retry: 'Retry',
  },
  noMatch: {
    title: 'Nothing matches',
    body: 'Try the venue name, or a shorter word.',
  },
} as const;
