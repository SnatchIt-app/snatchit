import type { Metadata } from "next";
import { AuthCard } from "@/components/auth/AuthCard";
import { SignUpForm } from "@/components/auth/SignUpForm";
import { safeInternalPath } from "@/lib/auth/redirect";

export const metadata: Metadata = {
  title: "Create account",
  robots: { index: false, follow: true },
};

type SearchParams = Record<string, string | string[] | undefined>;

function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export default async function SignUpPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const next = safeInternalPath(first(sp.next) ?? null, "/account");

  return (
    <AuthCard eyebrow="Account" title="Create account" subtitle="Bid, buy, and save listings across Miami.">
      <SignUpForm next={next} />
    </AuthCard>
  );
}
