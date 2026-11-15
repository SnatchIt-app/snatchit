import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { Container } from "@/components/ui/Container";
import { getAuthedUser } from "@/lib/auth/session";
import { isConfiguredPilot, readPilotSession } from "@/lib/private-pilot";
import { PilotPayment } from "./pilot-payment";

export const metadata: Metadata = {
  title: "Private checkout",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

export default async function PrivatePilotPage({
  params,
  searchParams,
}: {
  params: Promise<{ sessionId: string }>;
  searchParams: Promise<{ payment?: string }>;
}) {
  const { sessionId } = await params;
  if (!isConfiguredPilot(sessionId)) notFound();

  const { payment } = await searchParams;
  const returning = payment === "return";
  const path = `/primary-pilot/${sessionId}`;
  if (!await getAuthedUser()) {
    redirect(`/login?next=${encodeURIComponent(returning ? `${path}?payment=return` : path)}`);
  }

  const pilot = await readPilotSession(sessionId);
  if (!pilot) notFound();

  const total = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" })
    .format(pilot.totalMinor / 100);
  return (
    <Container className="max-w-[560px] space-y-5 py-10">
      <h1 className="font-display text-2xl font-bold uppercase text-ink">{pilot.event}</h1>
      <p>{pilot.venue}</p>
      <p>One {pilot.tier} ticket. {total} total, including fees.</p>
      <PilotPayment sessionId={sessionId} totalMinor={pilot.totalMinor} returning={returning} />
    </Container>
  );
}
