import { afterEach, describe, expect, it, vi } from "vitest";

/** The page's render gate and D's action gate must agree, state for state. DATA_SOURCE is fixed at import, so each state reloads both modules. */
async function load(opts: { source: string; gate?: string }) {
  vi.resetModules();
  vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", opts.source);
  vi.stubEnv("VENUE_COMMANDS_ENABLED", opts.gate as string);
  vi.doMock("@/lib/supabase/server", () => ({ createSupabaseServerClient: async () => ({ schema: () => ({ rpc: async () => ({ data: { status: "ok" }, error: null }) }) }), SupabaseConfigError: class extends Error {} }));
  const gate = await import("@/lib/db/command-gate");
  const cmds = await import("@/lib/db/commands");
  return { open: gate.commandsGateOpen(), action: await cmds.setTicketTypeRankAction({ ticketTypeId: "7a000000-0000-4000-8000-000000000001", displayRank: 1, commandKey: "k" }) };
}
afterEach(() => vi.unstubAllEnvs());

describe("commandsGateOpen mirrors D's gate", () => {
  it("closed in fixtures mode, closed in database mode without the flag, open only with database + VENUE_COMMANDS_ENABLED=true", async () => {
    const a = await load({ source: "fixtures", gate: "true" });
    expect(a.open).toBe(false);
    expect(a.action.kind).toBe("unavailable");
    const b = await load({ source: "database" });
    expect(b.open).toBe(false);
    expect(b.action.kind).toBe("unavailable");
    const c = await load({ source: "database", gate: "TRUE" });
    expect(c.open).toBe(false);
    expect(c.action.kind).toBe("unavailable");
    const d = await load({ source: "database", gate: "true" });
    expect(d.open).toBe(true);
    expect(d.action.kind).toBe("ok");
  });
});
