"use server";

import { getAuthedUser } from "@/lib/auth/session";
import { callEdgeFunction } from "@/lib/edge-functions";
import { STRIPE_PUBLISHABLE_KEY } from "@/lib/env";
import { isConfiguredPilot, isPilotUuid, readPilotSession } from "@/lib/private-pilot";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type StartResult = { clientSecret: string } | { error: string; expired?: true };

export async function startPrivatePilotCheckout(
  sessionId: string,
  attemptId: string,
  displayedTotal: number,
): Promise<StartResult> {
  const unavailable = { error: "This checkout link is unavailable." };
  if (!isConfiguredPilot(sessionId) || !isPilotUuid(attemptId) ||
      !STRIPE_PUBLISHABLE_KEY || !await getAuthedUser()) return unavailable;

  try {
    const pilot = await readPilotSession(sessionId);
    if (!pilot) return unavailable;
    if (pilot.totalMinor !== displayedTotal) {
      return { error: "The price changed. Refresh this page before continuing." };
    }

    const supabase = await createSupabaseServerClient();
    const { data: hold, error } = await supabase.rpc("reserve_primary_tier", {
      p_session_id: sessionId,
      p_ticket_type_id: pilot.ticketTypeId,
      p_quantity: 1,
      p_command_key: `private-pilot:${sessionId}:${attemptId}:hold`,
    });
    if (error || !hold || !isPilotUuid(hold.hold_id) || hold.quantity !== 1) {
      return { error: "We couldn't reserve the ticket. Try again or wait for the current hold to expire." };
    }
    const expires = Date.parse(hold.expires_at);
    if (!Number.isFinite(expires)) return unavailable;
    if (expires <= Date.now()) {
      return { error: "The hold expired. Select Continue to payment to try again.", expired: true };
    }

    const checkout = await callEdgeFunction<{ clientSecret?: string; total?: number; currency?: string }>(
      "primary-checkout",
      {
        session_id: sessionId,
        items: [{ ticket_type_id: pilot.ticketTypeId, quantity: 1 }],
        hold_ids: [hold.hold_id],
        command_key: `private-pilot:${sessionId}:${attemptId}:order`,
        expected_total_cents: pilot.totalMinor,
      },
    );

    if (checkout.error || typeof checkout.clientSecret !== "string" || !checkout.clientSecret ||
        checkout.currency !== "USD" || checkout.total !== pilot.totalMinor) {
      return { error: "Payment setup is unavailable. Try again from this page." };
    }

    return { clientSecret: checkout.clientSecret };
  } catch {
    return { error: "Checkout is temporarily unavailable. Try again from this page." };
  }
}
