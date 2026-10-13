import type { Metadata } from "next";
import { getMyProfile } from "@/lib/profile";
import { EmailChangeForm } from "@/components/account/EmailChangeForm";
import { LogoutButton } from "@/components/account/LogoutButton";
import { PayoutSetup } from "@/components/account/PayoutSetup";
import { DeleteAccountButton } from "@/components/account/DeleteAccountButton";
import { AppearanceSetting } from "@/components/account/AppearanceSetting";
import { AccountHeader } from "@/components/account/AccountHeader";
import { AccountSection, SettingsRow, SettingsRows } from "@/components/account/SettingsRow";
import { Alert } from "@/components/ui/Alert";
import { ErrorState } from "@/components/ui/ErrorState";

export const metadata: Metadata = {
  title: "Settings",
  robots: { index: false, follow: true },
};

type SearchParams = Record<string, string | string[] | undefined>;

/**
 * Grouped like the native settings hub (Account · Payments · Preferences),
 * then the session and danger-zone actions. Every form, action and confirm is
 * the existing one; only the arrangement changed.
 */
export default async function AccountSettingsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  const profile = await getMyProfile();
  if (!profile) {
    return (
      <div>
        <AccountHeader title="Settings" />
        <ErrorState title="Couldn't load your settings" message="Refresh the page, or try again shortly." />
      </div>
    );
  }

  return (
    <div className="max-w-[640px]">
      <AccountHeader title="Settings" />

      {sp.email_changed === "1" ? (
        <Alert tone="success" className="mb-8">
          Email changed.
        </Alert>
      ) : null}

      <div className="space-y-10">
        <AccountSection title="Account">
          <div className="border-b border-line pb-6 pt-4">
            <h3 className="t-title mb-3 text-ink">Email</h3>
            <EmailChangeForm currentEmail={profile.email} />
          </div>
          <SettingsRows>
            <SettingsRow
              href="/reset-password"
              title="Password"
              description="Set a new password for your account."
              value="Change password"
              valueTone="action"
            />
          </SettingsRows>
        </AccountSection>

        <AccountSection title="Payments">
          <div className="pt-4">
            <h3 className="t-title mb-2 text-ink">Payouts</h3>
            <PayoutSetup />
          </div>
        </AccountSection>

        <AccountSection title="Preferences">
          <div className="pt-4">
            <AppearanceSetting />
          </div>
        </AccountSection>

        <AccountSection title="Session">
          <div className="pt-4">
            <LogoutButton />
          </div>
        </AccountSection>

        <AccountSection title="Danger zone">
          <div className="pt-4">
            <DeleteAccountButton />
          </div>
        </AccountSection>
      </div>
    </div>
  );
}
