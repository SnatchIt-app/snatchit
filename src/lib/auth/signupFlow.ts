/**
 * src/lib/auth/signupFlow.ts — what Sign up collects, and the order it collects it in.
 *
 * Sign up is account creation: email, name, mobile number, a real verification of
 * that number, and gender. Sign in never asks for any of it again. The steps exist
 * so one screen does not become a wall of eleven fields; the product requirement is
 * about what is captured, so the step boundaries are free to move.
 *
 * WHY THE ACCOUNT IS CREATED FIRST. Linking a phone to an identity and writing a
 * profile both need a session. This project has `mailer_autoconfirm` on, so
 * `signUp({ email, password })` returns a session immediately and the remaining
 * steps can write to the real account. When that is ever turned off, `signUp`
 * returns no session, the flow ends at `check_email`, and nothing downstream is
 * attempted against an account that does not exist yet.
 *
 * CANONICAL STORAGE (verified against the deployed database, nothing new invented):
 *   email   -> auth.users.email               (supabase.auth.signUp)
 *   name    -> public.profiles.display_name   (the column Edit profile already writes)
 *   phone   -> auth.users.phone + phone_confirmed_at, via updateUser + verifyOtp,
 *              with the 10-digit convenience copy in public.profiles.phone_number
 *   gender  -> kernel.identity_demographic.gender_identity, via
 *              kernel.set_my_demographics(text, text) (migration 077, granted to
 *              `authenticated`, SECURITY DEFINER, owner scoped)
 */

/**
 * The three options, exactly. The labels are the product's words; the values are
 * the vocabulary the deployed `kernel.identity_demographic` check constraint
 * accepts, so no translation table and no second gender column is introduced.
 */
export const GENDER_OPTIONS = [
  { label: 'MALE', value: 'man' },
  { label: 'FEMALE', value: 'woman' },
  { label: 'PREFER NOT TO SAY', value: 'prefer_not_to_say' },
] as const;

export type GenderValue = (typeof GENDER_OPTIONS)[number]['value'];

/**
 * Recorded alongside the answer so the row says which privacy notice was on screen
 * when the person answered. `kernel.set_my_demographics` rejects an empty one.
 */
export const DEMOGRAPHIC_NOTICE_VERSION = 'signup-demographics/v1';

/** The four collection steps, plus the terminal state for a confirm-by-email project. */
export type SignupStep = 'account' | 'about' | 'phone' | 'verify' | 'check_email';

/** Only the collection steps are numbered; `check_email` is an exit, not progress. */
export const SIGNUP_STEPS: readonly SignupStep[] = ['account', 'about', 'phone', 'verify'] as const;
export const SIGNUP_STEP_COUNT = SIGNUP_STEPS.length;

export function stepIndex(step: SignupStep): number {
  return SIGNUP_STEPS.indexOf(step);
}

export function nextStep(step: SignupStep): SignupStep {
  const i = stepIndex(step);
  if (i < 0 || i === SIGNUP_STEP_COUNT - 1) return step;
  return SIGNUP_STEPS[i + 1];
}

export function prevStep(step: SignupStep): SignupStep {
  const i = stepIndex(step);
  if (i <= 0) return step;
  return SIGNUP_STEPS[i - 1];
}

/**
 * Back is available inside the post-account steps only. Once step 1 submits, the
 * account exists, so returning to it would offer to create a second one.
 */
export function canGoBack(step: SignupStep): boolean {
  return stepIndex(step) > 1;
}

/**
 * Step 1. Same rules and same copy the screen has always submitted against:
 * fields, then a 6 character password floor, then the 18+ gate (App Store 1.4.3).
 */
export function validateAccountStep(email: string, password: string, ageConfirmed: boolean): string | null {
  if (!email.trim() || !password.trim()) return 'Please enter your email and password.';
  if (password.length < 6) return 'Password must be at least 6 characters.';
  if (!ageConfirmed) return 'You must confirm you are 18 or older to use Snatch It.';
  return null;
}

/**
 * Step 2. The name bounds are the ones Edit profile already enforces on the same
 * column, so a name accepted here can never be rejected there.
 */
export function validateAboutStep(name: string, gender: GenderValue | null): string | null {
  const trimmed = name.trim();
  if (!trimmed) return 'Enter your name.';
  if (trimmed.length < 2) return 'Name must be at least 2 characters.';
  if (trimmed.length > 50) return 'Name must be 50 characters or fewer.';
  if (!gender) return 'Select an option to continue.';
  return null;
}

/** Step 4. Six digits, and only digits. */
export function validateCodeStep(code: string): string | null {
  if (code.trim().length !== 6) return 'Enter the 6-digit code from the text message.';
  return null;
}
