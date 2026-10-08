import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export type SignedEvidence = { ok: true; url: string; expiresInSeconds: number } | { ok: false; reason: string };

/** Upper bound on a signed-URL lifetime, whatever the RPC reports. */
export const EVIDENCE_TTL_MAX_SECONDS = 600;

/**
 * Sign a private storage object with the operator's own session (storage RLS
 * — the `proof-docs operator read` policy — applies to the operator, not to a
 * privileged client; this app has no service-role key).
 *
 * MUST only be called with a bucket/path resolved by `ops.evidence_access()`
 * (see lib/evidence-actions.ts), never with values taken from a page payload
 * or the client: the RPC is what audits the access and pins the path to the
 * record. On any failure the caller renders "evidence not accessible".
 */
export async function signResolvedEvidence(bucket: string, path: string, expiresInSeconds: number): Promise<SignedEvidence> {
  if (!bucket || !path) return { ok: false, reason: "evidence not accessible" };
  const ttl = Math.max(30, Math.min(Math.floor(expiresInSeconds), EVIDENCE_TTL_MAX_SECONDS));
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, ttl);
    if (error || !data?.signedUrl) {
      console.warn("[storage] sign failed", { bucket, code: (error as { statusCode?: string } | null)?.statusCode });
      return { ok: false, reason: "evidence not accessible" };
    }
    return { ok: true, url: data.signedUrl, expiresInSeconds: ttl };
  } catch (e) {
    console.warn("[storage] sign threw", { bucket, name: e instanceof Error ? e.name : typeof e });
    return { ok: false, reason: "evidence not accessible" };
  }
}
