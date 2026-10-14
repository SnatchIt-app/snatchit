import { beforeEach, describe, expect, it, vi } from "vitest";

// The three web actions that send auth emails must use the implicit email client, never the
// PKCE-only SSR client (the cause of the owner's cross-device "Link expired", 2026-10-14).

const h = vi.hoisted(() => ({
  email: {
    resetPasswordForEmail: vi.fn(async () => ({ error: null })),
    signUp: vi.fn(async () => ({ data: { session: null, user: { id: "u1" } }, error: null })),
  },
  requestEmailChange: vi.fn(async () => ({ error: null })),
  ssr: {
    resetPasswordForEmail: vi.fn(async () => ({ error: null })),
    signUp: vi.fn(async () => ({ data: { session: null }, error: null })),
    updateUser: vi.fn(async () => ({ error: null })),
    getClaims: vi.fn(async () => ({ data: { claims: { sub: "u1" } } })),
    getSession: vi.fn(async () => ({ data: { session: { access_token: "access-jwt" } } })),
    setSession: vi.fn(async () => ({ error: null })),
  },
}));

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({ redirect: vi.fn() }));
vi.mock("@/lib/env", () => ({ SITE_URL: "https://app.example.test" }));
vi.mock("@/lib/auth/email-links", () => ({ emailLinkAuth: () => h.email, requestEmailChange: h.requestEmailChange }));
vi.mock("@/lib/supabase/server", () => ({ createSupabaseServerClient: async () => ({ auth: h.ssr }) }));

import { requestPasswordResetAction, signUpAction, updateEmailAction } from "@/lib/auth/actions";

const form = (o: Record<string, string>) => {
  const f = new FormData();
  for (const [k, v] of Object.entries(o)) f.set(k, v);
  return f;
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe("auth actions send their emails through the implicit email client", () => {
  it("password reset", async () => {
    const out = await requestPasswordResetAction({}, form({ email: "Person@Example.test" }));
    expect(out.success).toBe(true);
    expect(h.email.resetPasswordForEmail).toHaveBeenCalledWith("person@example.test", {
      redirectTo: "https://app.example.test/auth/confirm?next=%2Freset-password",
    });
    expect(h.ssr.resetPasswordForEmail).not.toHaveBeenCalled();
  });

  it("sign-up confirmation", async () => {
    await signUpAction(
      {},
      form({
        firstName: "Ava",
        lastName: "Reyes",
        email: "ava@example.test",
        password: "long-enough-pass",
        confirmPassword: "long-enough-pass",
        acceptedTerms: "on",
        next: "/sell",
      }),
    );
    expect(h.email.signUp).toHaveBeenCalledTimes(1);
    const arg = h.email.signUp.mock.calls[0][0] as { options: { emailRedirectTo: string } };
    expect(arg.options.emailRedirectTo).toBe("https://app.example.test/auth/confirm?next=%2Fsell");
    expect(h.ssr.signUp).not.toHaveBeenCalled();
  });

  it("sign-up with confirmation off hands the returned session to the cookie client", async () => {
    h.email.signUp.mockResolvedValueOnce({
      data: { session: { access_token: "a", refresh_token: "r" }, user: { id: "u1" } },
      error: null,
    } as never);
    await signUpAction(
      {},
      form({ firstName: "A", lastName: "B", email: "a@example.test", password: "long-enough-pass", confirmPassword: "long-enough-pass", acceptedTerms: "on" }),
    );
    expect(h.ssr.setSession).toHaveBeenCalledWith({ access_token: "a", refresh_token: "r" });
  });

  it("email change", async () => {
    const out = await updateEmailAction({}, form({ newEmail: "next@example.test" }));
    expect(out.success).toBe(true);
    expect(h.requestEmailChange).toHaveBeenCalledWith("access-jwt", "next@example.test", "https://app.example.test/auth/confirm");
    expect(h.ssr.updateUser).not.toHaveBeenCalled();
  });

  it("email change without a session asks to log in again and sends nothing", async () => {
    h.ssr.getSession.mockResolvedValueOnce({ data: { session: null } } as never);
    const out = await updateEmailAction({}, form({ newEmail: "next@example.test" }));
    expect(out.error).toMatch(/Log in again/);
    expect(h.requestEmailChange).not.toHaveBeenCalled();
  });
});
