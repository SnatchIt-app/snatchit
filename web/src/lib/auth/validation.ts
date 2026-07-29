/** Pure validation + error-mapping helpers, kept dependency-free so they're
 * directly unit-testable without mocking Supabase or Next.js request state. */

export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export const MIN_PASSWORD_LENGTH = 8;

export function isValidEmail(email: string): boolean {
  return EMAIL_RE.test(email);
}

export function isValidPassword(password: string): boolean {
  return password.length >= MIN_PASSWORD_LENGTH;
}

export type SignUpFieldErrors = Partial<
  Record<"firstName" | "lastName" | "email" | "password" | "confirmPassword" | "acceptedTerms", string>
>;

export function validateSignUpFields(input: {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
  confirmPassword: string;
  acceptedTerms: boolean;
}): SignUpFieldErrors {
  const errors: SignUpFieldErrors = {};
  if (!input.firstName) errors.firstName = "Enter your first name.";
  if (!input.lastName) errors.lastName = "Enter your last name.";
  if (!isValidEmail(input.email)) errors.email = "Enter a valid email address.";
  if (!isValidPassword(input.password)) {
    errors.password = `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
  }
  if (input.password && input.password !== input.confirmPassword) {
    errors.confirmPassword = "Passwords don't match.";
  }
  if (!input.acceptedTerms) errors.acceptedTerms = "You must accept the Terms and Privacy Policy.";
  return errors;
}

/**
 * Never surface raw Supabase/Postgres error text to the client — this is
 * the single chokepoint every auth error message passes through.
 */
export function friendlyAuthError(message: string): string {
  const m = message.toLowerCase();
  if (m.includes("invalid login credentials")) return "That email or password isn't right.";
  if (m.includes("email not confirmed")) {
    return "Confirm your email before logging in — check your inbox for the link.";
  }
  if (m.includes("already registered") || m.includes("already exists")) {
    return "An account with that email already exists. Try logging in instead.";
  }
  if (m.includes("rate limit") || m.includes("too many")) {
    return "Too many attempts. Wait a moment and try again.";
  }
  if (m.includes("password") && (m.includes("short") || m.includes("weak") || m.includes("least"))) {
    return `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
  }
  if (m.includes("session") || m.includes("expired") || m.includes("invalid") || m.includes("token")) {
    return "That link has expired or already been used. Request a new one.";
  }
  return "Something went wrong. Please try again.";
}
