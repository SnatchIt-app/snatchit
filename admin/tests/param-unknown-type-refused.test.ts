import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * A param.* field this server cannot read is refused, never dropped.
 *
 * Why it matters: case_due writes `due_at = nullif(a.params ->> 'due_at','')::timestamptz` (the case_due
 * branch of ops.action_dispatch; A read the production body, 2026-11-02). If the console drops a field it
 * cannot parse, the action goes out WITHOUT due_at, and the server sets the due date to NULL. The real case:
 * the next admin release posts `param.due_at:et`; after a rollback to this release, a tab still showing the
 * newer form would clear a due date while the operator thinks they set one. This guard must ship BEFORE that
 * release, so a revert of that release cannot remove it.
 *
 * In the combined admin release head, #218 (bb5c5779) ships with this guard, so `:et` is a type this console
 * reads. The guard is unchanged; the type refused here is now one no release reads yet (`:pt`), and `:et` is
 * asserted to go out with its Eastern offset, never dropped.
 */
const calls: { fn: string; args: Record<string, unknown> }[] = [];
vi.mock("@/lib/ops", () => ({
  callOps: vi.fn(async (fn: string, args: Record<string, unknown> = {}) => {
    calls.push({ fn, args });
    return { ok: true, data: { status: "succeeded", action_id: "ac7e0b1c-d2e3-4f4a-8b5c-6d7e8f9a0b1c" } };
  }),
}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

import { submitActionForm } from "../src/lib/actions";

const CASE = "c4a5e6f7-a8b9-4cad-9ebf-a0b1c2d3e4f5";
const KEY = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";

function dueForm(fields: Record<string, string>): FormData {
  const fd = new FormData();
  fd.set("idempotency_key", KEY);
  fd.set("action_type", "case_due");
  fd.set("subject_kind", "case");
  fd.set("subject_id", CASE);
  fd.set("expected", JSON.stringify({ version: 3 }));
  fd.set("reason_required", "1");
  fd.set("reason", "move the deadline");
  for (const [k, v] of Object.entries(fields)) fd.set(k, v);
  return fd;
}

beforeEach(() => {
  calls.length = 0;
});

describe("a param.* field with a type this console does not read", () => {
  it("a newer release's `param.due_at:pt` is refused before anything is sent, so the due date cannot be cleared", async () => {
    const state = await submitActionForm({}, dueForm({ "param.due_at:pt": "2026-11-01T23:59" }));
    expect(calls).toHaveLength(0);
    expect(state.invalid).toContain("This form is out of date");
    expect(state.invalid).toContain("param.due_at:pt");
    expect(state.invalid).toContain("Nothing was changed.");
    expect(state.outcome).toBeUndefined();
  });

  it("`param.due_at:et` is read by this release (#218): it goes out with its Eastern offset, never dropped", async () => {
    const state = await submitActionForm({}, dueForm({ "param.due_at:et": "2026-11-01T23:59" }));
    expect(state.invalid).toBeUndefined();
    const exec = calls.find((c) => c.fn === "execute_action");
    expect(exec?.args.p_params).toEqual({ due_at: "2026-11-01T23:59:00-05:00" });
  });

  it("any unreadable param.* name is refused: an unknown type, or an empty key", async () => {
    for (const name of ["param.due_at:eastern", "param.:string", "param.due_at:"]) {
      calls.length = 0;
      const state = await submitActionForm({}, dueForm({ [name]: "x" }));
      expect(calls, name).toHaveLength(0);
      expect(state.invalid, name).toContain("This form is out of date");
    }
  });

  it("a param.* field that carries a file, not text, is refused too (never dropped)", async () => {
    const fd = dueForm({});
    fd.set("param.due_at", new File(["2026-11-01T23:59"], "due.txt", { type: "text/plain" }));
    const state = await submitActionForm({}, fd);
    expect(calls).toHaveLength(0);
    expect(state.invalid).toContain("This form sent a file in param.due_at");
    expect(state.invalid).toContain("Nothing was changed.");
  });

  it("NEGATIVE CONTROL — a field this console reads goes through with its value", async () => {
    const state = await submitActionForm({}, dueForm({ "param.due_at": "2026-11-01T23:59" }));
    expect(state.invalid).toBeUndefined();
    const exec = calls.find((c) => c.fn === "execute_action");
    expect(exec?.args.p_params).toEqual({ due_at: "2026-11-01T23:59" });
  });

  it("NEGATIVE CONTROL — fields that are not param.* are untouched by the guard", async () => {
    const state = await submitActionForm({}, dueForm({ "param.due_at": "", other_field: "ignored" }));
    expect(state.invalid).toBeUndefined();
    expect(calls.find((c) => c.fn === "execute_action")?.args.p_params).toEqual({ due_at: null });
  });
});
