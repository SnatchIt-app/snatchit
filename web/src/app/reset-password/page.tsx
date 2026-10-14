import type { Metadata } from "next";
import Link from "next/link";
import { AuthCard } from "@/components/auth/AuthCard";
import { ResetPasswordForm } from "@/components/auth/ResetPasswordForm";
import { Alert } from "@/components/ui/Alert";
import { getAuthedUser } from "@/lib/auth/session";
import { authInlineLinkCls } from "@/components/auth/styles";

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
        <div className="space-y-6">
          <Alert tone="error">This reset link has expired or already been used.</Alert>
          <Link href="/forgot-password" className={`${authInlineLinkCls} t-body`}>
            Request a new link →
          </Link>
        </div>
      )}
    </AuthCard>
  );
}
