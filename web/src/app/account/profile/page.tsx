import type { Metadata } from "next";
import { getMyProfile } from "@/lib/profile";
import { ProfileForm } from "@/components/account/ProfileForm";
import { ErrorState } from "@/components/ui/ErrorState";

export const metadata: Metadata = {
  title: "Profile",
  robots: { index: false, follow: true },
};

export default async function AccountProfilePage() {
  const profile = await getMyProfile();

  if (!profile) {
    return <ErrorState title="Couldn't load your profile" message="Refresh the page, or try again shortly." />;
  }

  return (
    <div>
      <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        Profile
      </h1>
      <div className="mt-7">
        <ProfileForm profile={profile} />
      </div>
    </div>
  );
}
