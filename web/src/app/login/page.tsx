import type { Metadata } from "next";
import { AuthCard } from "@/components/auth/AuthCard";
import { LoginForm } from "@/components/auth/LoginForm";
import { safeInternalPath } from "@/lib/auth/redirect";

export const metadata: Metadata = {
  title: "Log in",
  robots: { index: false, follow: true },
};

type SearchParams = Record<string, string | string[] | undefined>;

function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const next = safeInternalPath(first(sp.next) ?? null, "/account");

  let banner: string | undefined;
  if (first(sp.reset) === "success") banner = "Password updated. Log in with your new password.";
  else if (first(sp.confirmed) === "1") banner = "Email confirmed. Log in to continue.";

  return (
    <AuthCard eyebrow="Account" title="Log in">
      <LoginForm next={next} banner={banner} />
    </AuthCard>
  );
}
