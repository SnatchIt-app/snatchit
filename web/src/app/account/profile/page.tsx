import type { Metadata } from "next";
import { getMyProfile } from "@/lib/profile";
import { ProfileForm } from "@/components/account/ProfileForm";
import { AccountHeader } from "@/components/account/AccountHeader";
import { ErrorState } from "@/components/ui/ErrorState";

export const metadata: Metadata = {
  title: "Profile",
  robots: { index: false, follow: true },
};

export default async function AccountProfilePage() {
  const profile = await getMyProfile();

  if (!profile) {
    return (
      <div>
        <AccountHeader title="Profile" />
        <ErrorState title="Couldn't load your profile" message="Refresh the page, or try again shortly." />
      </div>
    );
  }

  return (
    <div>
      <AccountHeader title="Profile" />
      <ProfileForm profile={profile} />
    </div>
  );
}
