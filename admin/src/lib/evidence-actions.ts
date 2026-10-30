"use server";

import { redirect } from "next/navigation";
import { callOps } from "@/lib/ops";
import { signResolvedEvidence } from "@/lib/storage";
import { isUuid } from "@/lib/routes";
import { isEvidenceSlot, isEvidenceSubjectKind, toEvidenceAccess } from "@/lib/types";

export type OpenEvidenceState = {
  submitted?: boolean;
  /** Always the same operator-facing text; the server log has the detail. */
  error?: string;
  /** "no_evidence" when the slot is empty on the record; "paused"/"denied"/"mfa" for those failures. */
  code?: string;
};

const NOT_ACCESSIBLE = "evidence not accessible";

/**
 * The ONLY path from a page to a signed evidence URL.
 *
 *   form → openEvidence({subjectKind, subjectId, slot})
 *        → ops.evidence_access(p_subject_kind, p_subject_id, p_slot)   (re-checks operator + aal2,
 *                                                                        resolves the path from the
 *                                                                        record, audits evidence.viewed)
 *        → storage.createSignedUrl(bucket, path, expires_in_seconds)    (operator's own session)
 *        → redirect(signed url)
 *
 * The client never names a bucket or a path; it names a record and a slot.
 * Anything unexpected renders "evidence not accessible".
 */
export async function openEvidence(_prev: OpenEvidenceState, formData: FormData): Promise<OpenEvidenceState> {
  const subjectKind = String(formData.get("subject_kind") ?? "");
  const subjectId = String(formData.get("subject_id") ?? "");
  const slot = String(formData.get("slot") ?? "");

  if (!isEvidenceSubjectKind(subjectKind) || !isUuid(subjectId) || !isEvidenceSlot(subjectKind, slot)) {
    return { submitted: true, error: NOT_ACCESSIBLE, code: "invalid_request" };
  }

  const res = await callOps<unknown>("evidence_access", {
    p_subject_kind: subjectKind,
    p_subject_id: subjectId,
    p_slot: slot,
  });
  if (!res.ok) {
    if (res.kind === "error" && res.message.toLowerCase().includes("no_evidence")) {
      return { submitted: true, error: NOT_ACCESSIBLE, code: "no_evidence" };
    }
    return { submitted: true, error: NOT_ACCESSIBLE, code: res.kind };
  }
  const access = toEvidenceAccess(res.data);
  if (!access) return { submitted: true, error: NOT_ACCESSIBLE, code: "bad_payload" };

  const signed = await signResolvedEvidence(access.bucket, access.path, access.expires_in_seconds);
  if (!signed.ok) return { submitted: true, error: NOT_ACCESSIBLE, code: "sign_failed" };

  // Short-lived URL; the audit row (evidence.viewed) was written by the RPC.
  redirect(signed.url);
}
