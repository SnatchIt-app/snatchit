import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { BANNED_CONTENT_PATTERNS, findBannedContent } from '../src/lib/sell/sellState';

// Migration 152 (20261013000000) enforces the app's prohibited-content list on the server, in
// public.listing_prohibited_term(). The two lists must stay identical: a term added to one side only
// is either refused by the server after the app let it through, or never enforced for web and
// direct calls. PostgreSQL's word boundary is \y where JavaScript's is \b; the server matches
// case-insensitively (~*), so every client pattern must carry the i flag.
const MIGRATION = 'supabase/migrations/20261013000000_marketplace_safety_enforcement.sql';

function serverRows(): [string, string][] {
  const sql = readFileSync(MIGRATION, 'utf8');
  const start = sql.indexOf('FROM (VALUES');
  const end = sql.indexOf(') AS t(ord, pattern, label)');
  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);
  const block = sql.slice(start, end);
  return [...block.matchAll(/\(\s*(\d+),\s*'([^']+)',\s*'([^']+)'\)/g)]
    .sort((a, b) => Number(a[1]) - Number(b[1]))
    .map((m) => [m[2].replace(/\\y/g, '\\b'), m[3]]);
}

describe('server prohibited-content list (migration 152) matches the app', () => {
  it('has the same patterns and labels, in the same order', () => {
    const client = BANNED_CONTENT_PATTERNS.map(({ pattern, label }) => [pattern.source, label]);
    expect(serverRows()).toEqual(client);
    expect(client).toHaveLength(10);
  });

  it('every client pattern is case-insensitive, like the server', () => {
    expect(BANNED_CONTENT_PATTERNS.every(({ pattern }) => pattern.flags.includes('i'))).toBe(true);
  });

  it('each label is found by the app gate, as the server reports it', () => {
    for (const [, label] of serverRows()) {
      expect(findBannedContent([`x ${label} y`])).toBe(label);
    }
  });
});
