import { describe, expect, it } from "vitest";
import {
  friendlyAuthError,
  isValidEmail,
  isValidPassword,
  validateSignUpFields,
  MIN_PASSWORD_LENGTH,
} from "../src/lib/auth/validation";

describe("isValidEmail", () => {
  it("accepts well-formed addresses", () => {
    expect(isValidEmail("buyer@example.com")).toBe(true);
  });
  it("rejects malformed addresses", () => {
    expect(isValidEmail("not-an-email")).toBe(false);
    expect(isValidEmail("missing@domain")).toBe(false);
    expect(isValidEmail("")).toBe(false);
  });
});

describe("isValidPassword", () => {
  it("enforces the minimum length", () => {
    expect(isValidPassword("a".repeat(MIN_PASSWORD_LENGTH - 1))).toBe(false);
    expect(isValidPassword("a".repeat(MIN_PASSWORD_LENGTH))).toBe(true);
  });
});

describe("validateSignUpFields", () => {
  const valid = {
    firstName: "Jamie",
    lastName: "Rivera",
    email: "jamie@example.com",
    password: "correcthorse",
    confirmPassword: "correcthorse",
    acceptedTerms: true,
  };

  it("returns no errors for fully valid input", () => {
    expect(validateSignUpFields(valid)).toEqual({});
  });

  it("flags missing name fields", () => {
    const errors = validateSignUpFields({ ...valid, firstName: "", lastName: "" });
    expect(errors.firstName).toBeDefined();
    expect(errors.lastName).toBeDefined();
  });

  it("flags mismatched passwords", () => {
    const errors = validateSignUpFields({ ...valid, confirmPassword: "different" });
    expect(errors.confirmPassword).toBeDefined();
  });

  it("flags unaccepted terms", () => {
    const errors = validateSignUpFields({ ...valid, acceptedTerms: false });
    expect(errors.acceptedTerms).toBeDefined();
  });

  it("flags a short password without also flagging confirmPassword mismatch noise", () => {
    const errors = validateSignUpFields({ ...valid, password: "short", confirmPassword: "short" });
    expect(errors.password).toBeDefined();
    expect(errors.confirmPassword).toBeUndefined();
  });
});

describe("friendlyAuthError", () => {
  it("never echoes the raw input message back verbatim", () => {
    const raw = "duplicate key value violates unique constraint \"profiles_pkey\"";
    expect(friendlyAuthError(raw)).not.toContain("duplicate key");
    expect(friendlyAuthError(raw)).not.toContain("profiles_pkey");
  });

  it("maps known Supabase errors to friendly copy", () => {
    expect(friendlyAuthError("Invalid login credentials")).toMatch(/isn't right/i);
    expect(friendlyAuthError("Email not confirmed")).toMatch(/confirm your email/i);
    expect(friendlyAuthError("User already registered")).toMatch(/already exists/i);
    expect(friendlyAuthError("email rate limit exceeded")).toMatch(/too many attempts/i);
  });

  it("falls back to a generic message for unrecognized errors", () => {
    expect(friendlyAuthError("some obscure postgres constraint violation xyz")).toBe(
      "Something went wrong. Please try again.",
    );
  });
});
