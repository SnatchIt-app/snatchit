/**
 * src/lib/auth/linkErrorCopy.ts — what the app says when an auth link arrives already dead.
 *
 * GoTrue redirects a consumed or expired email link to `snatchit://?error=…&error_code=otp_expired`, with no
 * code to exchange. The app used to log a warning and leave the person on Login with no word about the link
 * (C's sandbox simulator check D6, 2026-10-15). Web says "Link expired"; the app now says the same, and how
 * to recover.
 */
export const AUTH_LINK_EXPIRED_COPY = {
  title: 'Link expired',
  body: 'That link has expired or was already used. Request a new one.',
} as const;
