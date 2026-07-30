import type { Metadata } from "next";
import Link from "next/link";
import { getMyProfile } from "@/lib/profile";
import { EmailChangeForm } from "@/components/account/EmailChangeForm";
import { LogoutButton } from "@/components/account/LogoutButton";
import { PayoutSetup } from "@/components/account/PayoutSetup";
import { DeleteAccountButton } from "@/components/account/DeleteAccountButton";
import { Alert } from "@/components/ui/Alert";
import { ErrorState } from "@/components/ui/ErrorState";

export const metadata: Metadata = {
  title: "Settings",
  robots: { index: false, follow: true },
};

type SearchParams = Record<string, string | string[] | undefined>;

export default async function AccountSettingsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const profile = await getMyProfile();
  if (!profile) {
    return <ErrorState title="Couldn't load your settings" message="Refresh the page, or try again shortly." />;
  }

  return (
    <div className="space-y-10">
      <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        Settings
      </h1>

      {sp.email_changed === "1" ? <Alert tone="success">Email changed.</Alert> : null}

      <section className="border-t border-primary/15 pt-7">
        <p className="eyebrow text-primary/80">Email</p>
        <div className="mt-4">
          <EmailChangeForm currentEmail={profile.email} />
        </div>
      </section>

      <section className="border-t border-primary/15 pt-7">
        <p className="eyebrow text-primary/80">Password</p>
        <p className="mt-4 max-w-[46ch] text-[13.5px] leading-relaxed text-white/60">
          Set a new password for your account.
        </p>
        <Link
          href="/reset-password"
          className="mt-4 inline-flex min-h-11 items-center text-[13px] font-semibold text-primary hover:text-[#ff5f5f]"
        >
          Change password →
        </Link>
      </section>

      <section className="border-t border-primary/15 pt-7">
        <p className="eyebrow text-primary/80">Payouts</p>
        <div className="mt-4">
          <PayoutSetup />
        </div>
      </section>

      <section className="border-t border-primary/15 pt-7">
        <p className="eyebrow text-primary/80">Session</p>
        <div className="mt-4">
          <LogoutButton />
        </div>
      </section>

      <section className="border-t border-primary/15 pt-7">
        <p className="eyebrow text-primary/80">Danger zone</p>
        <div className="mt-4">
          <DeleteAccountButton />
        </div>
      </section>
    </div>
  );
}
