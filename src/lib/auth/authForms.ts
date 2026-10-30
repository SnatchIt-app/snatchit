/**
 * src/lib/auth/authForms.ts — pure validation for the auth screens.
 *
 * The screens own the Supabase calls (sign in, sign up, reset); the field rules
 * that gate those calls are pulled out here so they can be tested without a
 * network or a renderer. Copy is unchanged from the screens these came from.
 *
 * `friendlyAuthError` maps the handful of raw Supabase auth strings we surface
 * into plain sentences, and generalises anything that looks like an internal
 * error, so a database or network string never reaches the user verbatim.
 */

/** Login: both fields required. Returns the error message, or null when valid. */
export function validateLogin(email: string, password: string): string | null {
  if (!email.trim() || !password.trim()) return 'Please enter your email and password.';
  return null;
}

/**
 * Sign up: fields, then a 6-char password floor, then the 18+ gate — the exact
 * order (and copy) the screen submits against (App Store 1.4.3 / 18+ market).
 */
export function validateSignup(email: string, password: string, ageConfirmed: boolean): string | null {
  if (!email.trim() || !password.trim()) return 'Please enter your email and password.';
  if (password.length < 6) return 'Password must be at least 6 characters.';
  if (!ageConfirmed) return 'You must confirm you are 18 or older to use Snatch It.';
  return null;
}

/** Reset: both fields required and must match. */
export function validateReset(password: string, confirm: string): string | null {
  if (!password.trim() || !confirm.trim()) return 'Both fields are required.';
  if (password !== confirm) return 'Passwords do not match.';
  return null;
}

// A tiny allowlist of Supabase auth messages that are already user-appropriate.
// Anything not matched here that reads like an internal fault is generalised.
const PASSTHROUGH = [
  /invalid login credentials/i,
  /email not confirmed/i,
  /user already registered/i,
  /email rate limit/i,
  /for security purposes/i,
  /password should be/i,
  /unable to validate email/i,
  /signups not allowed/i,
];

const TECHNICAL = /(fetch|network|timeout|json|sql|postgres|supabase|500|internal|undefined|null)/i;

/**
 * The message to show for a Supabase auth error. Known auth strings pass through;
 * a technical-looking string becomes a generic sentence so raw internals are
 * never shown.
 */
export function friendlyAuthError(message: string | null | undefined): string {
  const m = (message ?? '').trim();
  if (!m) return 'Something went wrong. Please try again.';
  if (PASSTHROUGH.some((re) => re.test(m))) return m;
  if (TECHNICAL.test(m)) return 'Something went wrong. Please try again.';
  return m;
}
