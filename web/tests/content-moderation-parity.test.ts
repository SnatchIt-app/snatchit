import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { BANNED_CONTENT_PATTERNS, findBannedTerm } from "@/lib/content-moderation";
import { prohibitedContentMessage } from "@/lib/server-refusal";

// FU-1 (D F-152-2): web's listing pre-check must be the app's list, pattern for pattern, and so
// the server's (migration 152's listing_prohibited_term, which the app-side
// tests/server-content-parity.test.ts already pins to the app). A term on one side only is either
// refused by the server after web let it through, or never pre-checked on web.
const REPO = path.resolve(__dirname, "../..");

/** The app's list, read from source: sellState.ts from RC3 on, CreateListingScreen.tsx before. */
function appRows(): [string, string][] {
  const candidates = ["src/lib/sell/sellState.ts", "src/screens/CreateListingScreen.tsx"];
  const file = candidates.map((f) => path.join(REPO, f)).find((f) => existsSync(f));
  expect(file, "the app's banned-content list was not found").toBeDefined();
  const src = readFileSync(file!, "utf8");
  return [...src.matchAll(/\{\s*pattern:\s*\/(.+?)\/([a-z]*),\s*label:\s*'([^']+)'\s*\}/g)].map((m) => {
    expect(m[2]).toContain("i");
    return [m[1], m[3]];
  });
}

const MIGRATION = path.join(REPO, "supabase/migrations/20261013000000_marketplace_safety_enforcement.sql");

/** Migration 152's rows (PostgreSQL \y is JavaScript \b). Present once 152 is on this tree. */
function serverRows(): [string, string][] {
  const sql = readFileSync(MIGRATION, "utf8");
  const block = sql.slice(sql.indexOf("FROM (VALUES"), sql.indexOf(") AS t(ord, pattern, label)"));
  return [...block.matchAll(/\(\s*(\d+),\s*'([^']+)',\s*'([^']+)'\)/g)]
    .sort((a, b) => Number(a[1]) - Number(b[1]))
    .map((m) => [m[2].replace(/\\y/g, "\\b"), m[3]]);
}

/** 152 as reviewed (fix/rc3-marketplace-safety-20261013 @ 3091d30c), for trees that predate it. */
const SERVER_152 = [
  ["\\balcohol\\b", "alcohol"],
  ["\\bdrugs?\\b", "drugs"],
  ["\\bweed\\b", "weed"],
  ["\\bcocaine\\b", "cocaine"],
  ["\\bmolly\\b", "molly"],
  ["\\bopen[\\s-]?bar\\b", "open bar"],
  ["\\bbottle[\\s-]?service\\b", "bottle service"],
  ["\\bfake[\\s-]?tickets?\\b", "fake ticket"],
  ["\\bcounterfeit\\b", "counterfeit"],
  ["\\bunderage\\b", "underage"],
];

const web = () => BANNED_CONTENT_PATTERNS.map(({ pattern, label }) => [pattern.source, label]);

describe("web listing pre-check matches the app and the server (FU-1)", () => {
  it("has the app's ten patterns and labels, in the app's order", () => {
    expect(web()).toEqual(appRows());
    expect(web()).toHaveLength(10);
  });

  it("has migration 152's patterns and labels, as reviewed", () => {
    expect(web()).toEqual(SERVER_152);
  });

  it.skipIf(!existsSync(MIGRATION))("has the migration file's rows when 152 is on this tree", () => {
    expect(web()).toEqual(serverRows());
  });

  it("is case-insensitive, like the server (~*)", () => {
    expect(BANNED_CONTENT_PATTERNS.every(({ pattern }) => pattern.flags.includes("i"))).toBe(true);
  });

  it("finds every label as the server names it", () => {
    for (const [, label] of SERVER_152) expect(findBannedTerm([`x ${label} y`])).toBe(label);
  });

  it("matches words, not substrings, as the server does", () => {
    expect(findBannedTerm(["Drugstore Cowboy screening"])).toBeNull();
    expect(findBannedTerm(["Alcoholics Anonymous benefit"])).toBeNull();
    expect(findBannedTerm(["Open-bar package"])).toBe("open bar");
    expect(findBannedTerm(["FAKE TICKETS"])).toBe("fake ticket");
    expect(findBannedTerm(["no drug use"])).toBe("drugs");
  });

  it("joins fields the server's way, so a term never spans two fields", () => {
    expect(findBannedTerm(["Rooftop open", "Bar 32"])).toBeNull();
    expect(findBannedTerm(["Rooftop open bar", "Bar 32"])).toBe("open bar");
    expect(findBannedTerm(["Show", null, undefined, "21+ underage not admitted"])).toBe("underage");
  });

  it("explains a hit with the server's own sentence (K2)", () => {
    expect(prohibitedContentMessage("weed")).toBe(
      `Listings can't mention "weed". Please revise your event name, venue, or restrictions and try again.`,
    );
  });
});
