import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

// The Cancel on "Set new password", rendered: a reset link gets a sign-out (this browser) form
// button; Password from settings gets a plain link back to settings.

vi.mock("@/lib/auth/actions", () => ({
  updatePasswordAction: async () => ({}),
  cancelPasswordResetAction: async () => {},
}));
vi.mock("next/link", () => ({
  default: ({ href, children, ...rest }: { href: string; children: unknown }) => createElement("a", { href, ...rest }, children as never),
}));

import { ResetPasswordForm } from "@/components/auth/ResetPasswordForm";

describe("ResetPasswordForm Cancel", () => {
  it("from a reset link: Cancel is a submit button in its own form, no link to settings", () => {
    const html = renderToStaticMarkup(createElement(ResetPasswordForm, { fromResetLink: true }));
    const forms = html.match(/<form[\s\S]*?<\/form>/g) ?? [];
    expect(forms).toHaveLength(2);
    expect(forms[1]).toMatch(/<button[^>]*type="submit"[^>]*>[\s\S]*Cancel/);
    expect(html).not.toContain('href="/account/settings"');
  });

  it("from settings: Cancel is a link back to settings, and nothing signs out", () => {
    const html = renderToStaticMarkup(createElement(ResetPasswordForm, {}));
    expect(html.match(/<form/g) ?? []).toHaveLength(1);
    expect(html).toMatch(/<a[^>]*href="\/account\/settings"[^>]*>[\s\S]*?Cancel/);
  });
});
