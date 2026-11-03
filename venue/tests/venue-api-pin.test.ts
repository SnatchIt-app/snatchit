/**
 * The venue_api read views ship as registry 159: supabase/migrations/20261021120000_venue_api_read_views.sql
 * (pgTAP 226), a re-timestamp of D's 20260910120000 with a byte-identical SQL body. 20260910120000 is
 * retired: it was applied nowhere and must never be applied, so the app's hint, the acceptance kit and the
 * venue docs name the new version, and the kit's preflight fails when a ledger already holds the old one.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { mapReadError } from "@/lib/db/read-result";
import { preflightLedgerChecks, verifyApplyLedgerChecks } from "../scripts/acceptance/lib/checks.mjs";

const NEW = "20261021120000";
const RETIRED = "20260910120000";
const VENUE = new URL("..", import.meta.url).pathname;
const REPO = new URL("../..", import.meta.url).pathname;
const read = (p: string) => readFileSync(join(VENUE, p), "utf8");

describe("the kit's SQL reads the registry-159 ledger row", () => {
  it("preflight: ledger_has_venue_api counts 20261021120000; ledger_has_retired_venue_api counts 20260910120000", () => {
    const sql = read("scripts/acceptance/sql/preflight.sql");
    expect(sql).toMatch(new RegExp(`'ledger_has_venue_api',[^\\n]*version = '${NEW}'`));
    expect(sql).toMatch(new RegExp(`'ledger_has_retired_venue_api',[^\\n]*version = '${RETIRED}'`));
  });
  it("verify-apply: the name and statement count come from the 20261021120000 row; the retired row is counted", () => {
    const sql = read("scripts/acceptance/sql/verify-apply.sql");
    expect(sql).toMatch(new RegExp(`'ledger_row_name',[^\\n]*version = '${NEW}'`));
    expect(sql).toMatch(new RegExp(`'ledger_row_statements',[^\\n]*version = '${NEW}'`));
    expect(sql).toMatch(new RegExp(`'ledger_retired_row',[^\\n]*version = '${RETIRED}'`));
  });
  it("apply: the kit applies supabase/migrations/20261021120000_venue_api_read_views.sql", () => {
    const kit = read("scripts/acceptance/accept.mjs");
    expect(kit).toContain(`"supabase/migrations/${NEW}_venue_api_read_views.sql"`);
    expect(kit).toContain(`ledger_${NEW}_`);
  });
});

describe("preflight fails when the ledger holds the retired version", () => {
  const sandboxSnap = { ledger_count: 168, ledger_076_092: 17, ledger_dupes: 0, ledger_tip_timestamp: "20261015000200", ledger_has_venue_api: 0, ledger_has_retired_venue_api: 0 };
  /** Ids of the checks that FAIL; a check is [id, ok, detail]. */
  const failing = (rows: unknown[][]) => rows.filter((r) => !r[1]).map((r) => String(r[0]));
  it("a clean sandbox ledger passes", () => {
    expect(failing(preflightLedgerChecks(sandboxSnap, "sandbox"))).toEqual([]);
  });
  it("a ledger holding 20260910120000 fails preflight, naming the retired version", () => {
    const f = failing(preflightLedgerChecks({ ...sandboxSnap, ledger_has_retired_venue_api: 1 }, "sandbox"));
    expect(f).toHaveLength(1);
    expect(f[0]).toContain(RETIRED);
  });
  it("a preflight.sql that does not report the retired count fails closed", () => {
    const noField: Record<string, unknown> = { ...sandboxSnap };
    delete noField.ledger_has_retired_venue_api;
    expect(failing(preflightLedgerChecks(noField, "sandbox"))).toHaveLength(1);
  });
  it("the local replay (no ledger) is unchanged: one expected check, nothing about the retired version", () => {
    const rows = preflightLedgerChecks({ ledger_count: null }, "local");
    expect(rows).toHaveLength(1);
    expect(failing(rows)).toEqual([]);
  });
  it("verify-apply: the 20261021120000 row with 24 statements passes; the retired row fails it", () => {
    const v = { ledger_row_name: "venue_api_read_views", ledger_row_statements: 24, ledger_retired_row: 0 };
    const ok = verifyApplyLedgerChecks(v);
    expect(failing(ok)).toEqual([]);
    expect(ok.map((r) => String(r[0])).join(" ")).toContain(`${NEW} = venue_api_read_views with 24 statements`);
    expect(failing(verifyApplyLedgerChecks({ ...v, ledger_retired_row: 1 }))).toHaveLength(1);
    expect(failing(verifyApplyLedgerChecks({ ...v, ledger_row_statements: 23 }))).toHaveLength(1);
  });
});

describe("the app's not-applied hint names the registry-159 file", () => {
  it("42P01 / 42883 / 3F000 point at 20261021120000_venue_api_read_views", () => {
    for (const code of ["42P01", "42883", "3F000"]) {
      const m = mapReadError("venue_api.events", { code, message: "x" }).message;
      expect(m).toContain(`${NEW}_venue_api_read_views`);
      expect(m).not.toContain(RETIRED);
    }
  });
});

describe("no live reference to the retired version", () => {
  const TEXT = /\.(ts|tsx|mjs|js|sql|py|md|tmpl)$/;
  const files = (dir: string): string[] =>
    readdirSync(dir).flatMap((n) => {
      if (n.startsWith(".") || n === "node_modules" || n === "screenshots") return [];
      const p = join(dir, n);
      return statSync(p).isDirectory() ? files(p) : TEXT.test(n) ? [p] : [];
    });
  it("every line under venue/src, venue/scripts, venue/docs and docs/venue-dashboard that names 20260910120000 says it is retired", () => {
    const roots = [join(VENUE, "src"), join(VENUE, "scripts"), join(VENUE, "docs"), join(REPO, "docs/venue-dashboard")];
    const live = roots
      .flatMap(files)
      .flatMap((f) => readFileSync(f, "utf8").split("\n").map((line, i) => ({ at: `${f.slice(REPO.length)}:${i + 1}`, line })))
      .filter(({ line }) => line.includes(RETIRED) && !/retired/i.test(line))
      .map(({ at }) => at);
    expect(live).toEqual([]);
  });
});
