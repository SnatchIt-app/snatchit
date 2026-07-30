import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { getListingGates } from "@/lib/create-listing";
import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";
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
      <Container className="max-w-[560px] py-14">
        <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
          Before you list
        </h1>
        <p className="mt-3 text-[13.5px] leading-relaxed text-white/60">
          Two things need to be set up on your account before you can create a listing.
        </p>

        <ul className="mt-8 space-y-4">
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
      <Container className="max-w-[560px] py-14">
        <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
          Listing unavailable
        </h1>
        <p className="mt-3 text-[13.5px] leading-relaxed text-white/60">
          {gates.risk.reason === "critical_risk"
            ? "Your account can't create new listings right now. Contact support if you think this is a mistake."
            : "Your account is temporarily blocked from creating listings. Contact support if you think this is a mistake."}
        </p>
      </Container>
    );
  }

  return (
    <Container className="max-w-[640px] py-10">
      <h1 className="font-display text-[24px] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
        List your tickets
      </h1>
      <p className="mt-3 text-[13.5px] leading-relaxed text-white/60">
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
    <li className="flex items-start justify-between gap-4 border border-primary/20 bg-card p-5">
      <div>
        <p className="flex items-center gap-2 text-[14px] font-bold text-ink">
          <span
            aria-hidden="true"
            className={`inline-flex size-5 shrink-0 items-center justify-center text-[11px] font-bold ${
              done ? "bg-primary text-black" : "bg-white/[0.08] text-white/40"
            }`}
          >
            {done ? "✓" : ""}
          </span>
          {title}
        </p>
        <p className="mt-2 text-[13px] leading-relaxed text-white/55">{body}</p>
      </div>
      {done ? null : (
        <LinkButton href={href} size="md" className="shrink-0">
          {cta}
        </LinkButton>
      )}
    </li>
  );
}
