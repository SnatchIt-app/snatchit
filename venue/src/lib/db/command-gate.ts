import "server-only";

import { DATA_SOURCE } from "@/lib/env";

/**
 * The same two locks D's actions apply before any call (lib/db/commands.ts `gate()`), read here so a
 * page can decide whether to RENDER a command form at all: database mode, and the server-only
 * VENUE_COMMANDS_ENABLED exactly "true" (never NEXT_PUBLIC_; unset everywhere today). When the gate is
 * closed the page says tiers and inventory are read-only here, instead of showing forms whose every
 * submission would be refused as unavailable. tests/command-gate.test.ts proves this and D's gate agree.
 */
export function commandsGateOpen(): boolean {
  return DATA_SOURCE === "database" && process.env.VENUE_COMMANDS_ENABLED === "true";
}
