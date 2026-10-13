import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getListingGates } from "@/lib/create-listing";
import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";
import { Icon } from "@/components/ui/Icon";
import { CreateListingForm } from "@/components/sell/CreateListingForm";

export const metadata: Metadata = {
  title: "Sell tickets",
  robots: { index: false, follow: true },
};

export default async function SellPage() {
  const user = await getAuthedUser();
  if (!user) redirect("/login?next=/sell");

  const gates = await getListingGates(user.id);

  if (!gates.phoneVerified || gates.payoutStatus !== "connected") {
    return (
      <Container size="tight" className="py-10 sm:py-14">
        <h1 className="t-display-lg text-ink">Before you list</h1>
        <p className="t-body mt-2 text-muted">
          Two things need to be set up on your account before you can create a listing.
        </p>

        <ul className="mt-8 border-t border-line">
          <GateRow
            done={gates.phoneVerified}
            title="Verify your phone number"
            body="Required so buyers and support can reach you about a sale."
            href="/account/verify-phone"
            cta="Verify phone"
          />
          <GateRow
            done={gates.payoutStatus === "connected"}
            title="Set up payouts"
            body="Connect Stripe so you can get paid when a ticket sells."
            href="/account/settings"
            cta="Set up payouts"
          />
        </ul>
      </Container>
    );
  }

  if (!gates.risk.allowed) {
    return (
      <Container size="tight" className="flex flex-col items-center py-14 text-center sm:py-20">
        <span className="mb-5 inline-flex size-14 items-center justify-center rounded-full bg-surface text-danger">
          <Icon name="alert" size={26} />
        </span>
        <h1 className="t-name-state text-ink">Listing unavailable</h1>
        <p className="t-body mt-2.5 max-w-sm text-muted">
          {gates.risk.reason === "critical_risk"
            ? "Your account can't create new listings right now. Contact support if you think this is a mistake."
            : "Your account is temporarily blocked from creating listings. Contact support if you think this is a mistake."}
        </p>
      </Container>
    );
  }

  return (
    <Container size="narrow" className="pb-10 pt-6 lg:pt-10">
      <h1 className="t-display-lg text-ink">List your tickets</h1>
      <p className="t-body mt-2 max-w-[56ch] text-muted">
        List it as an auction or Buy Now. You keep 90% of the sale, paid out through Stripe
        once the buyer confirms the transfer.
      </p>
      <CreateListingForm riskWarning={gates.risk.reason === "ok" ? null : gates.risk.reason} />
    </Container>
  );
}

function GateRow({
  done,
  title,
  body,
  href,
  cta,
}: {
  done: boolean;
  title: string;
  body: string;
  href: string;
  cta: string;
}) {
  return (
    <li className="flex flex-wrap items-center justify-between gap-x-4 gap-y-3 border-b border-line py-5">
      <div className="flex min-w-0 flex-1 gap-3.5">
        <span
          aria-hidden="true"
          className={`mt-0.5 inline-flex size-7 shrink-0 items-center justify-center rounded-full ${
            done ? "bg-success-soft text-on-success-soft" : "border border-control"
          }`}
        >
          {done ? <Icon name="check" size={16} strokeWidth={2.4} /> : null}
        </span>
        <span className="sr-only">{done ? "Done:" : "To do:"}</span>
        <div className="min-w-[12rem]">
          <p className="t-title text-ink">{title}</p>
          <p className="t-body-sm mt-1 text-muted">{body}</p>
        </div>
      </div>
      {done ? null : (
        <LinkButton href={href} size="md" className="shrink-0">
          {cta}
        </LinkButton>
      )}
    </li>
  );
}
