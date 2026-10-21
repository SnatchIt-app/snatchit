import { createElement, type ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * A's request: a refusal code the console has never seen — e.g. a future
 * "one unsettled money action per subject" rule — must render generically,
 * with the database's own message, from both execute_action and
 * approve_action. No special-casing of any code, and nothing here depends on
 * that rule existing: "duplicate_unsettled" is an invented code.
 *
 * The real submitActionForm → executeAction/approveAction → callOps →
 * mapOpsError path runs; only the Supabase client is faked.
 */
const rpc = vi.hoisted(() => ({ reply: { data: null as unknown, error: null as unknown }, calls: [] as string[] }));

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    schema: () => ({
      rpc: async (fn: string) => {
        rpc.calls.push(fn);
        return rpc.reply;
      },
    }),
  }),
}));

import { submitActionForm, type ActionFormState } from "@/lib/actions";
import { OutcomeText } from "@/components/ui/ConfirmForm";
import { OpsFailureAlert } from "@/components/ui/Alert";

const KEY = "01234567-89ab-4cde-8f01-23456789abcd";
const TR = "7a000000-0000-4000-8000-0000000000c1";
const ACTION_ID = "9a900000-0000-4000-8000-0000000000c1";
const EXISTING = "aaaaaaaa-0000-4000-8000-0000000000c1";
const DB_MESSAGE = "duplicate_unsettled: an unsettled payout_release already exists for this transfer";

function executeForm(): FormData {
  const fd = new FormData();
  fd.set("idempotency_key", KEY);
  fd.set("action_type", "payout_release");
  fd.set("subject_kind", "transfer");
  fd.set("subject_id", TR);
  fd.set("expected", "{}");
  fd.set("reason", "seller delivered, buyer confirmed");
  return fd;
}

function approveForm(): FormData {
  const fd = new FormData();
  fd.set("idempotency_key", KEY);
  fd.set("action_type", "approval_decide");
  fd.set("subject_kind", "action");
  fd.set("subject_id", ACTION_ID);
  fd.set("params", JSON.stringify({ action_id: ACTION_ID, decision: "approve" }));
  fd.set("reason", "second founder review");
  return fd;
}

const FORMS = [
  { fn: "execute_action", form: executeForm },
  { fn: "approve_action", form: approveForm },
] as const;

/** What ConfirmForm's FormResult renders for a state (failure → OpsFailureAlert, outcome → OutcomeText). */
function rendered(state: ActionFormState, fn: string): string {
  let el: ReactElement | null = null;
  if (state.failure) el = createElement(OpsFailureAlert, { failure: state.failure, fn });
  else if (state.outcome) el = createElement(OutcomeText, { outcome: state.outcome });
  return el ? renderToStaticMarkup(el) : "";
}

beforeEach(() => {
  rpc.calls.length = 0;
  rpc.reply = { data: null, error: null };
});

describe("an unknown refusal raised by the database renders generically with its message", () => {
  for (const { fn, form } of FORMS) {
    it(`${fn}: P0001 with an unseen code in the message → "Request failed", the DB's message and code`, async () => {
      rpc.reply = { data: null, error: { code: "P0001", message: DB_MESSAGE, details: null, hint: null } };
      const state = await submitActionForm({}, form());
      expect(rpc.calls).toEqual([fn]);
      expect(state.failure).toEqual({ ok: false, kind: "error", code: "P0001", message: DB_MESSAGE });
      const html = rendered(state, fn);
      expect(html).toContain("Request failed");
      expect(html).toContain(DB_MESSAGE);
      expect(html).toContain("P0001");
      // Not mistaken for a denial, a step-up, a pause or a missing RPC.
      expect(html).not.toContain("not allowed");
      expect(html).not.toContain("Re-verify");
      expect(html).not.toContain("paused");
      expect(html).not.toContain("not available yet");
    });

    it(`${fn}: an invented SQLSTATE-like code with no message → "Request failed" and the code`, async () => {
      rpc.reply = { data: null, error: { code: "SI409", message: "" } };
      const state = await submitActionForm({}, form());
      expect(state.failure).toEqual({ ok: false, kind: "error", code: "SI409", message: "Request failed" });
      expect(rendered(state, fn)).toContain("SI409");
    });
  }
});

describe("an unknown reject_reason in a rejected outcome renders generically with its message", () => {
  for (const { fn, form } of FORMS) {
    it(`${fn}: status rejected, reject_reason duplicate_unsettled → "Rejected: duplicate unsettled" and the DB's message`, async () => {
      rpc.reply = {
        data: { status: "rejected", reject_reason: "duplicate_unsettled", message: "An unsettled payout_release already exists", result: { existing_action_id: EXISTING, existing_state: "awaiting_approval" } },
        error: null,
      };
      const state = await submitActionForm({}, form());
      expect(state.outcome).toMatchObject({ status: "rejected", reason: "duplicate_unsettled", message: "An unsettled payout_release already exists" });
      const html = rendered(state, fn);
      expect(html).toContain("Rejected: duplicate unsettled");
      expect(html).toContain("An unsettled payout_release already exists");
      expect(html).not.toContain("Denied");
      expect(html).not.toContain("changed since you loaded it");
    });

    it(`${fn}: the same rejection with no message → the generic title alone, no "undefined"`, async () => {
      rpc.reply = { data: { status: "rejected", reject_reason: "duplicate_unsettled", result: { existing_action_id: EXISTING } }, error: null };
      const html = rendered(await submitActionForm({}, form()), fn);
      expect(html).toContain("Rejected: duplicate unsettled");
      expect(html).not.toContain("undefined");
    });
  }
});

describe("an answer with a status the console does not know keeps the DB's words", () => {
  for (const { fn, form } of FORMS) {
    it(`${fn}: unknown status → failure that names the status, the code and the DB's message`, async () => {
      rpc.reply = { data: { status: "refused", reject_reason: "duplicate_unsettled", message: "An unsettled payout_release already exists" }, error: null };
      const state = await submitActionForm({}, form());
      expect(state.outcome).toBeUndefined();
      expect(state.failure).toEqual({
        ok: false,
        kind: "error",
        code: "duplicate_unsettled",
        message: `Unrecognised response from ${fn} (status refused): An unsettled payout_release already exists`,
      });
      const html = rendered(state, fn);
      expect(html).toContain("Request failed");
      expect(html).toContain("An unsettled payout_release already exists");
      expect(html).toContain("duplicate_unsettled");
    });

    it(`${fn}: a null or empty earlier field does not hide a later code or message`, async () => {
      // pick() returns the first key PRESENT, so reject_reason: null used to win over a real code
      for (const data of [
        { status: "x", reject_reason: null, code: "P9999", message: null, detail: "a rule added after this build" },
        { status: "x", reject_reason: "", reason: null, code: "P9999", message: "", error: "a rule added after this build" },
      ]) {
        rpc.reply = { data, error: null };
        const state = await submitActionForm({}, form());
        expect(state.failure, JSON.stringify(data)).toEqual({ ok: false, kind: "error", code: "P9999", message: `Unrecognised response from ${fn} (status x): a rule added after this build` });
      }
    });

    it(`${fn}: a payload with nothing to quote keeps the plain line (control)`, async () => {
      for (const data of [null, "x", [], {}, { status: 7 }]) {
        rpc.reply = { data, error: null };
        const state = await submitActionForm({}, form());
        expect(state.failure, JSON.stringify(data)).toEqual({ ok: false, kind: "error", message: `Unrecognised response from ${fn}` });
      }
    });
  }
});
