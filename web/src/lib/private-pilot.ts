import "server-only";

import { createClient } from "@supabase/supabase-js";
import { SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type PilotRow = {
  session?: { session_id?: unknown };
  event?: { title?: unknown };
  venue?: { name?: unknown };
  ticket_types?: unknown;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isPilotUuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

export function isConfiguredPilot(sessionId: unknown): sessionId is string {
  return isPilotUuid(sessionId) && sessionId === process.env.PRIVATE_PRIMARY_SESSION_ID;
}

export async function readPilotSession(sessionId: string) {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return null;

  const supabase = await createSupabaseServerClient();
  const anonymous = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: (input, init) => fetch(input, { ...init, cache: "no-store" }) },
  });
  const args = { p_session_id: sessionId };
  const [{ data, error }, publicRead] = await Promise.all([
    supabase.rpc("get_primary_session", args).maybeSingle<PilotRow>(),
    anonymous.rpc("get_primary_session", args).maybeSingle(),
  ]);

  // A mistakenly configured public session must never open the pilot UI.
  if (publicRead.error || publicRead.data || error || !data || data.session?.session_id !== sessionId ||
      typeof data.event?.title !== "string" || typeof data.venue?.name !== "string" ||
      !Array.isArray(data.ticket_types) || data.ticket_types.length !== 1) {
    return null;
  }

  const tier = data.ticket_types[0];
  if (!isPilotUuid(tier?.ticket_type_id) || typeof tier.name !== "string" ||
      tier.currency !== "USD" || tier.on_sale_now !== true ||
      !Number.isSafeInteger(tier.price_minor) || tier.price_minor <= 0 ||
      !Number.isSafeInteger(tier.buyer_fee_minor) || tier.buyer_fee_minor < 0 ||
      !Number.isSafeInteger(tier.all_in_price_minor) ||
      tier.all_in_price_minor !== tier.price_minor + tier.buyer_fee_minor) {
    return null;
  }

  return {
    event: data.event.title,
    venue: data.venue.name,
    tier: tier.name as string,
    ticketTypeId: tier.ticket_type_id,
    totalMinor: tier.all_in_price_minor as number,
  };
}
