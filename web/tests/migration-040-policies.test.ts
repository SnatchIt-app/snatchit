import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Lightweight sanity check that the additive migration actually contains the
// RLS/grant statements this phase's data-access code assumes exist — catches
// an accidental omission/typo without needing a live database connection.
const sql = readFileSync(
  path.resolve(__dirname, "../../supabase/migrations/040_web_accounts_foundation.sql"),
  "utf8",
);

describe("040_web_accounts_foundation.sql", () => {
  it("enables RLS on both new tables", () => {
    expect(sql).toMatch(/ALTER TABLE public\.saved_listings ENABLE ROW LEVEL SECURITY/);
    expect(sql).toMatch(/ALTER TABLE public\.notifications ENABLE ROW LEVEL SECURITY/);
  });

  it("scopes saved_listings policies to the row owner", () => {
    expect(sql).toMatch(/"saved_listings: owner select"/);
    expect(sql).toMatch(/"saved_listings: owner insert"/);
    expect(sql).toMatch(/"saved_listings: owner delete"/);
    // No owner-update policy — a save is insert/delete only.
    expect(sql).not.toMatch(/"saved_listings: owner update"/);
  });

  it("enforces one saved row per (user, listing)", () => {
    expect(sql).toMatch(/UNIQUE \(user_id, listing_id\)/);
  });

  it("restricts notification INSERT to service-role only (no client policy)", () => {
    const notificationsSection = sql.slice(sql.indexOf("-- ── 2. Notifications"));
    expect(notificationsSection).not.toMatch(/CREATE POLICY "notifications: owner insert"/);
    expect(notificationsSection).not.toMatch(/FOR INSERT/);
  });

  it("restricts client UPDATE on notifications to the read_at column", () => {
    expect(sql).toMatch(/GRANT UPDATE \(read_at\) ON public\.notifications TO authenticated/);
    expect(sql).not.toMatch(/GRANT UPDATE ON public\.notifications/);
  });

  it("revokes default public-schema grants before re-granting narrowly", () => {
    expect(sql).toMatch(/REVOKE ALL ON public\.notifications FROM PUBLIC, anon, authenticated/);
  });

  it("foreign-keys listing_id to public.listings and user_id to auth.users", () => {
    expect(sql).toMatch(/listing_id\s+uuid\s+NOT NULL REFERENCES public\.listings\(id\)/);
    expect(sql).toMatch(/user_id\s+uuid\s+NOT NULL REFERENCES auth\.users\(id\)/);
  });
});
