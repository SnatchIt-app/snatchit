import type { Metadata } from "next";
import Link from "next/link";
import { AuthCard } from "@/components/auth/AuthCard";
import { ResetPasswordForm } from "@/components/auth/ResetPasswordForm";
import { Alert } from "@/components/ui/Alert";
import { getAuthedUser } from "@/lib/auth/session";

export const metadata: Metadata = {
  title: "Set a new password",
  robots: { index: false, follow: true },
};

export default async function ResetPasswordPage() {
  const user = await getAuthedUser();

  return (
    <AuthCard eyebrow="Account" title="Set new password">
      {user ? (
        <ResetPasswordForm />
      ) : (
        <div className="space-y-5">
          <Alert tone="error">This reset link has expired or already been used.</Alert>
          <Link
            href="/forgot-password"
            className="inline-flex min-h-11 items-center text-[13px] font-semibold text-primary hover:text-[#ff5f5f]"
          >
            Request a new link →
          </Link>
        </div>
      )}
    </AuthCard>
  );
}
