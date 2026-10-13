/**
 * The order screen's listing embed is pinned against the SCHEMA, not the TypeScript type.
 *
 * A's condition on approving the embed widening (2026-09-24): "pin the select's column list with
 * a test against the schema, not the TS type." The reason is a live near-miss the same day: the
 * proposed embed named `cover_image_url`, a column NO migration has ever created — dead
 * fallback code in two screens invented the name — and PostgREST rejects the WHOLE read when one
 * selected column is missing, which would have sent every buyer's order screen to its failed-read
 * state. The prior instance of this class is recorded as "compat checks: columns, not names".
 *
 * The schema source here is the migrations chain: append-only by constitution, 1:1 with the
 * production ledger (89/89 verified 2026-08-26, extended since), so a column exists in the
 * database iff some migration creates it. The second leg — `select <cols> from listings limit 0`
 * on a rehearsal DB — is D's/A's, recorded in the release notes, not in this test.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const MIG_DIR = 'supabase/migrations';

/** Every column name the migrations chain ever gives `public.listings`. */
function listingsColumnsFromMigrations(): Set<string> {
  const cols = new Set<string>();
  for (const f of readdirSync(MIG_DIR)) {
    if (!f.endsWith('.sql')) continue;
    const sql = readFileSync(join(MIG_DIR, f), 'utf8');
    // CREATE TABLE ... listings ( ... )  — first column list, brace-matched.
    const create = sql.match(/create\s+table[^(]*\blistings\b[^(]*\(/i);
    if (create) {
      let depth = 1;
      let i = (create.index ?? 0) + create[0].length;
      const start = i;
      while (i < sql.length && depth > 0) {
        if (sql[i] === '(') depth++;
        if (sql[i] === ')') depth--;
        i++;
      }
      const body = sql.slice(start, i - 1).replace(/--[^\n]*/g, '');
      for (const rawLine of body.split(/,(?![^(]*\))/)) {
        const m = rawLine.trim().match(/^"?([a-z_][a-z0-9_]*)"?\s/i);
        const kw = m?.[1]?.toLowerCase();
        if (m && kw && !['primary', 'unique', 'constraint', 'check', 'foreign', 'like'].includes(kw)) {
          cols.add(m[1].toLowerCase());
        }
      }
    }
    // ALTER TABLE ... listings ADD COLUMN [IF NOT EXISTS] <name>
    for (const m of sql.matchAll(/alter\s+table[^;]*?\blistings\b[^;]*?add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?/gis)) {
      cols.add(m[1].toLowerCase());
    }
  }
  return cols;
}

describe("the transfer screens' listing embeds exist column-for-column in the schema", () => {
  const screens = ['app/transfer/receive/[id].tsx', 'app/transfer/send/[id].tsx'];
  const embeds = screens.map((rel) => [rel, readFileSync(rel, 'utf8').match(/listing:listings!listing_id\(([^)]*)\)/)?.[1]] as const);
  const embed = embeds[0][1];
  const schema = listingsColumnsFromMigrations();

  it('S0 (witness): the extractor sees a real schema, and can tell a fake column from a real one', () => {
    // If the extractor returned an empty or tiny set, every ⊆ check below would be vacuous.
    expect(schema.size).toBeGreaterThan(10);
    for (const known of ['id', 'event_name', 'current_bid', 'status']) {
      expect(schema.has(known), known).toBe(true);
    }
    // The exact column that nearly shipped: named by dead fallback code, created by no migration.
    expect(schema.has('cover_image_url')).toBe(false);
  });

  it('S1: every column either embed selects is created by some migration (send approved by A, 2026-09-24)', () => {
    for (const [rel, e] of embeds) {
      expect(e, `${rel}: the embed must exist`).toBeTruthy();
      for (const col of e!.split(',').map((c) => c.trim()).filter(Boolean)) {
        expect(schema.has(col), `${rel}: listings.${col} is selected but no migration creates it`).toBe(true);
      }
    }
  });

  it('S2: the transfers side of BOTH selects keeps the two gated dispute columns', () => {
    for (const rel of screens) {
      expect(readFileSync(rel, 'utf8'), rel).toMatch(/dispute_resolution, dispute_resolved_at/);
    }
  });
});
