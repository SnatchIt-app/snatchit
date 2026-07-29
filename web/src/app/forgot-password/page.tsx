import type { Metadata } from "next";
import { AuthCard } from "@/components/auth/AuthCard";
import { ForgotPasswordForm } from "@/components/auth/ForgotPasswordForm";

export const metadata: Metadata = {
  title: "Reset your password",
  robots: { index: false, follow: true },
};

export default function ForgotPasswordPage() {
  return (
    <AuthCard
      eyebrow="Account"
      title="Reset password"
      subtitle="Enter your email and we'll send you a link to set a new one."
    >
      <ForgotPasswordForm />
    </AuthCard>
  );
}
