import { describe, expect, it } from "vitest";
import { RELIST_FIELDS, RELIST_STALE_MESSAGE, relistExpected, relistFieldRows, relistOutcomeDetail } from "../src/lib/relist";
import { toActionOutcome, type ActionOutcome } from "../src/lib/types";

// Pure half of the listing_relist / migration 158 contract (src/lib/relist.ts).

const RAW_UPDATED = "2026-10-21T03:47:04.123456+00:00";

function row(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: "5a150000-0000-4000-8000-000000000158",
    status: "active",
    auction_status: "cancelled",
    ends_at: "2026-10-20T23:59:00-04:00",
    ended_at: null,
    updated_at: RAW_UPDATED,
    event_name: "ignored",
    ...over,
  };
}

function outcome(raw: Record<string, unknown>): ActionOutcome {
  const o = toActionOutcome(raw);
  if (!o) throw new Error("fixture is not an ActionOutcome");
  return o;
}

describe("relistExpected", () => {
  it("copies exactly the five compared fields, values untouched", () => {
    expect(relistExpected(row())).toStrictEqual({
      status: "active",
      auction_status: "cancelled",
      ends_at: "2026-10-20T23:59:00-04:00",
      ended_at: null,
      updated_at: RAW_UPDATED,
    });
    expect(RELIST_FIELDS).toEqual(["status", "auction_status", "ends_at", "ended_at", "updated_at"]);
  });

  it("never reformats a timestamp (a Date round trip would drop microseconds and the offset)", () => {
    for (const v of [RAW_UPDATED, "2026-10-20T11:04:05.123456-04:00", "2026-10-20 11:04:05.1+05:30", "2026-10-20T11:04:05Z"]) {
      expect(relistExpected(row({ updated_at: v }))?.updated_at).toBe(v);
    }
    expect(relistExpected(row())?.updated_at).not.toBe(new Date(RAW_UPDATED).toISOString());
  });

  it("is null unless status=active, auction_status=cancelled and updated_at is a string", () => {
    expect(relistExpected(row({ auction_status: "active" }))).toBeNull();
    expect(relistExpected(row({ auction_status: "ended" }))).toBeNull();
    expect(relistExpected(row({ status: "sold" }))).toBeNull();
    expect(relistExpected(row({ updated_at: null }))).toBeNull();
    expect(relistExpected(row({ updated_at: 1729482424123 }))).toBeNull();
    const noVersion = row();
    delete noVersion.updated_at;
    expect(relistExpected(noVersion)).toBeNull();
    expect(relistExpected(null)).toBeNull();
    expect(relistExpected([])).toBeNull();
  });

  it("is null when ends_at / ended_at were not returned as a string or JSON null", () => {
    for (const k of ["ends_at", "ended_at"]) {
      const r = row();
      delete r[k];
      expect(relistExpected(r)).toBeNull();
      expect(relistExpected(row({ [k]: 0 }))).toBeNull();
    }
  });
});

describe("relistOutcomeDetail", () => {
  const before = { status: "active", auction_status: "cancelled", ends_at: "2026-10-20T23:59:00-04:00", ended_at: null, updated_at: RAW_UPDATED };

  it("succeeded: result.result and result.before", () => {
    const d = relistOutcomeDetail(outcome({ status: "succeeded", result: { status: "succeeded", result: { new_ends_at: "x" }, before } }));
    expect(d).toEqual({ kind: "succeeded", relisted: { new_ends_at: "x" }, before: relistFieldRows(before) });
  });

  it("succeeded pre-158: no before", () => {
    expect(relistOutcomeDetail(outcome({ status: "succeeded", result: { status: "succeeded", result: { new_ends_at: "x" } } }))).toEqual({
      kind: "succeeded",
      relisted: { new_ends_at: "x" },
      before: null,
    });
  });

  it("stale_state: result.current", () => {
    const d = relistOutcomeDetail(
      outcome({ status: "rejected", reject_reason: "stale_state", message: RELIST_STALE_MESSAGE, result: { current: before } }),
    );
    expect(d).toEqual({ kind: "stale", current: [
      { key: "status", value: "active" },
      { key: "auction_status", value: "cancelled" },
      { key: "ends_at", value: "2026-10-20T23:59:00-04:00" },
      { key: "ended_at", value: null },
      { key: "updated_at", value: RAW_UPDATED },
    ] });
  });

  it("nothing extra for precondition, replay, failed", () => {
    expect(relistOutcomeDetail(outcome({ status: "rejected", reject_reason: "precondition", message: "Listing not found." }))).toBeNull();
    expect(relistOutcomeDetail(outcome({ status: "idempotent_replay", state: "succeeded" }))).toBeNull();
    expect(relistOutcomeDetail(outcome({ status: "failed", message: "boom" }))).toBeNull();
  });

  it("the stale copy is 158's message byte for byte", () => {
    expect(RELIST_STALE_MESSAGE).toBe("listing changed since you loaded it — reload and try again");
  });
});
