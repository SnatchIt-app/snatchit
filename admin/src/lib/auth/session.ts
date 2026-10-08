import "server-only";

import { cache } from "react";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { callOps } from "@/lib/ops";
import { toWhoami, type Whoami } from "@/lib/types";

export type AuthedUser = {
  id: string;
  email: string | null;
  aal: "aal1" | "aal2" | null;
};

/**
 * The only authentication primitive server code should use. Verifies the
 * JWT signature (getClaims()) rather than trusting an unvalidated cookie.
 */
export async function getAuthedUser(): Promise<AuthedUser | null> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.getClaims();
  if (error || !data?.claims?.sub) return null;
  const aal: unknown = data.claims.aal;
  return {
    id: data.claims.sub,
    email: typeof data.claims.email === "string" ? data.claims.email : null,
    aal: aal === "aal1" ? "aal1" : aal === "aal2" ? "aal2" : null,
  };
}

export type Operator = AuthedUser & { whoami: Whoami; role: NonNullable<Whoami["role"]> };

/**
 * Authorization primitive: asks Postgres who the caller is (`ops.whoami()`
 * re-checks `kernel.is_platform(...)` and the aal claim server-side). Any
 * failure to prove operator status ends on /denied — hidden navigation is
 * not security, the DB is the wall; this just keeps the UX honest.
 */
export const requireOperator = cache(async function requireOperator(): Promise<Operator> {
  const user = await getAuthedUser();
  if (!user) redirect("/login");
  if (user.aal !== "aal2") redirect("/mfa");

  const res = await callOps<unknown>("whoami");
  if (!res.ok) {
    if (res.kind === "denied") redirect("/denied");
    if (res.kind === "mfa") redirect("/mfa");
    // RPC missing / transient: the page cannot prove operator status. Fail
    // closed but tell the operator why (denied page shows the reason).
    redirect(`/denied?reason=${encodeURIComponent(res.message)}`);
  }
  const whoami = toWhoami(res.data);
  if (!whoami || !whoami.role) redirect("/denied");
  return { ...user, whoami, role: whoami.role };
});
