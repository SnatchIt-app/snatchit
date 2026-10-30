import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { mapOpsError, type OpsResult } from "@/lib/ops-errors";

export type { OpsFailure, OpsResult } from "@/lib/ops-errors";

/**
 * The only way the console talks to the database: `ops.<fn>(args)` executed
 * with the operator's own JWT. Authorization (role + aal2) is re-checked by
 * `ops.assert_reader()` / `ops.assert_role()` inside every function; this
 * wrapper just makes the three failure classes explicit for the UI.
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
