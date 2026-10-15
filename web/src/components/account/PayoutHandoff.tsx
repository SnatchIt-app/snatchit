import { AuthCard } from "@/components/auth/AuthCard";
import { PayoutSetup } from "@/components/account/PayoutSetup";
import { ArrowLink, LinkButton, buttonClasses } from "@/components/ui/Button";
import {
  APP_PAYOUT_REFRESH,
  APP_PAYOUT_RETURN,
  PAYOUT_LOGIN_HREF,
  PAYOUT_SETTINGS_PATH,
} from "@/lib/payout-handoff";

const COPY = {
  return: {
    title: "Back from Stripe",
    signedIn: "Your payout status from Stripe is below.",
    signedOut: "Your details went to Stripe. Open the Snatch It app, or log in here, to see your payout status.",
    app: APP_PAYOUT_RETURN,
  },
  refresh: {
    title: "Continue payout setup",
    signedIn: "Your Stripe setup link expired. Continue to get a fresh one.",
    signedOut: "Your Stripe setup link expired. Open the Snatch It app, or log in here, to continue.",
    app: APP_PAYOUT_REFRESH,
  },
} as const;

/**
 * The page Stripe sends a seller back to (return) or to when the onboarding link expired
 * (refresh). Signed in on this browser: the live status and the next step. Not signed in (the
 * native app's in-app browser, another device): a handoff to the app on phones, and a login that
 * comes back to payout settings. Never redirects on its own and never claims a status it didn't
 * read.
 */
export function PayoutHandoff({
  kind,
  signedIn,
  mobile,
}: {
  kind: "return" | "refresh";
  signedIn: boolean;
  mobile: boolean;
}) {
  const copy = COPY[kind];
  // A custom-scheme link: a plain anchor, not next/link.
  const appLink = (variant: "primary" | "secondary") => (
    <a href={copy.app} className={buttonClasses(variant, "lg", "w-full")}>
      Open the Snatch It app
    </a>
  );

  return (
    <AuthCard eyebrow="Payouts" title={copy.title} subtitle={signedIn ? copy.signedIn : copy.signedOut}>
      {signedIn ? (
        <div className="space-y-6">
          <PayoutSetup />
          <ArrowLink href={PAYOUT_SETTINGS_PATH}>Payout settings</ArrowLink>
          {mobile ? appLink("secondary") : null}
        </div>
      ) : (
        <div className="space-y-3">
          {mobile ? appLink("primary") : null}
          <LinkButton href={PAYOUT_LOGIN_HREF} variant={mobile ? "secondary" : "primary"} size="lg" className="w-full">
            Log in to see payouts
          </LinkButton>
        </div>
      )}
    </AuthCard>
  );
}
