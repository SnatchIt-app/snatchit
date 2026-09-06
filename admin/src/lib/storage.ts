import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export type SignedEvidence = { ok: true; url: string; expiresInSeconds: number } | { ok: false; reason: string };

/** Signed URL lifetime — short by design; the page re-signs on every render. */
export const EVIDENCE_TTL_SECONDS = 600;

/**
 * Sign a private storage object with the operator's own session (storage RLS
 * applies to the operator, not to a privileged client). On any failure the
 * caller renders "evidence not accessible" rather than the raw path.
 */
export async function signEvidence(bucket: string | null | undefined, path: string | null | undefined): Promise<SignedEvidence> {
  if (!bucket || !path) return { ok: false, reason: "no file recorded" };
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, EVIDENCE_TTL_SECONDS);
    if (error || !data?.signedUrl) {
      console.warn("[storage] sign failed", { bucket, code: (error as { statusCode?: string } | null)?.statusCode });
      return { ok: false, reason: "evidence not accessible" };
    }
    return { ok: true, url: data.signedUrl, expiresInSeconds: EVIDENCE_TTL_SECONDS };
  } catch (e) {
    console.warn("[storage] sign threw", { bucket, name: e instanceof Error ? e.name : typeof e });
    return { ok: false, reason: "evidence not accessible" };
  }
}
