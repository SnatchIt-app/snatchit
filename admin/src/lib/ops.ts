import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { mapOpsError, type OpsResult } from "@/lib/ops-errors";

export type { OpsFailure, OpsResult } from "@/lib/ops-errors";

/**
 * How the console talks to the database: `ops.<fn>(args)` executed with the
 * operator's own JWT. Authorization (role + aal2) is re-checked by
 * `ops.assert_reader()` / `ops.assert_role()` inside every function; this
 * wrapper just makes the three failure classes explicit for the UI. The one
 * exception is `callKernelApproval` below.
 */
export async function callOps<T>(fn: string, args: Record<string, unknown> = {}): Promise<OpsResult<T>> {
  let supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>;
  try {
    supabase = await createSupabaseServerClient();
  } catch (e) {
    return { ok: false, kind: "error", message: e instanceof Error ? e.message : "Supabase client unavailable" };
  }

  try {
    const { data, error } = await supabase.schema("ops").rpc(fn, args);
    if (error) {
      // Log the shape, never the args (they can carry reasons/notes).
      console.warn("[ops] rpc failed", { fn, code: error.code });
      return mapOpsError(fn, error);
    }
    return { ok: true, data: data as T };
  } catch (e) {
    console.warn("[ops] rpc threw", { fn, name: e instanceof Error ? e.name : typeof e });
    return { ok: false, kind: "error", message: e instanceof Error ? e.message : "Request failed" };
  }
}

/**
 * The console's single call outside `ops`: `kernel.approve_refund_request`,
 * the kernel's existing dual-control decider (085), used only for money-key
 * requests (registry 196). It enforces a DIFFERENT platform_admin than the
 * requester and an aal2 session to approve, under the operator's own JWT, so
 * it grants the console nothing the operator's session could not already do.
 * Fixed function name: nothing else in `kernel` is reachable from here.
 */
export async function callKernelApproval<T>(args: {
  p_request_id: string;
  p_decision: "approve" | "deny";
  p_reason_code: string;
  p_command_key: string;
}): Promise<OpsResult<T>> {
  let supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>;
  try {
    supabase = await createSupabaseServerClient();
  } catch (e) {
    return { ok: false, kind: "error", message: e instanceof Error ? e.message : "Supabase client unavailable" };
  }

  try {
    const { data, error } = await supabase.schema("kernel").rpc("approve_refund_request", args);
    if (error) {
      console.warn("[kernel] rpc failed", { fn: "approve_refund_request", code: error.code });
      return mapOpsError("approve_refund_request", error);
    }
    return { ok: true, data: data as T };
  } catch (e) {
    console.warn("[kernel] rpc threw", { fn: "approve_refund_request", name: e instanceof Error ? e.name : typeof e });
    return { ok: false, kind: "error", message: e instanceof Error ? e.message : "Request failed" };
  }
}
