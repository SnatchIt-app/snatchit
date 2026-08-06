/**
 * Validation for seller transfer-evidence uploads.
 *
 * Its own module, not part of transfers.ts, because that file imports
 * "server-only" and so cannot be loaded by the node test runner — same reason
 * evidence-path.ts is separate.
 *
 * Why this exists: uploadTransferEvidence used to accept any file the client
 * sent. It took contentType straight from file.type and built the storage key
 * from the client-supplied filename's extension. A seller could upload
 * evidence.html with content-type text/html, and getEvidenceUrl then hands the
 * buyer a signed URL to it — the browser renders the attacker's markup on the
 * storage origin. SVG is the same problem with a friendlier extension, since
 * it carries <script>. Nothing bounded the size either.
 *
 * So: the MIME type decides everything. The extension is derived from the
 * accepted type rather than trusted from the filename, which means a
 * .jpg-named HTML file cannot smuggle its extension through, and a
 * .html-named JPEG is stored as .jpg.
 *
 * PDFs stay allowed — sellers legitimately upload platform transfer receipts
 * as PDF, and existing stored evidence must keep working. A PDF cannot script
 * the parent page when served as a download or in the browser's PDF viewer;
 * the Content-Disposition guidance in the accompanying migration covers how it
 * is served.
 */

/** Image types match APP_CONFIG.ALLOWED_IMAGE_TYPES, plus PDF receipts. */
export const ALLOWED_EVIDENCE_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
  "application/pdf",
] as const;

export const MAX_EVIDENCE_SIZE_MB = 10;

/**
 * Extension is derived from the validated MIME type, never from file.name.
 * A filename is attacker-controlled; the type has already been checked
 * against the allow-list by the time we get here.
 */
const EXTENSION_FOR_TYPE: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heif",
  "application/pdf": "pdf",
};

/**
 * Reverse of EXTENSION_FOR_TYPE. The contentType handed to storage is looked up
 * from this rather than echoed from file.type, so even a caller that bypassed
 * validateEvidenceFile could not get text/html onto a stored object.
 */
export const MIME_FOR_EXTENSION: Record<string, string> = {
  jpg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  heic: "image/heic",
  heif: "image/heif",
  pdf: "application/pdf",
};

export type EvidenceValidation = { ok: true; extension: string } | { ok: false; error: string };

export function validateEvidenceFile(type: string, sizeBytes: number): EvidenceValidation {
  // Strip any ";charset=..." parameter and normalise, so "IMAGE/JPEG" and
  // "image/jpeg; charset=binary" are treated as the plain type they are.
  const normalized = type.split(";")[0]!.trim().toLowerCase();

  if (!(ALLOWED_EVIDENCE_TYPES as readonly string[]).includes(normalized)) {
    return {
      ok: false,
      error: "Upload a JPEG, PNG, WEBP, HEIC image or a PDF. Other file types aren't accepted.",
    };
  }
  if (sizeBytes <= 0) {
    return { ok: false, error: "That file appears to be empty." };
  }
  if (sizeBytes > MAX_EVIDENCE_SIZE_MB * 1024 * 1024) {
    return { ok: false, error: `File must be under ${MAX_EVIDENCE_SIZE_MB}MB.` };
  }
  return { ok: true, extension: EXTENSION_FOR_TYPE[normalized]! };
}

/**
 * Storage key for a seller's evidence file. The `<userId>/transfer-evidence/`
 * prefix is required by the proof-docs INSERT policy (migration 053), which
 * scopes writes to the owner's folder — so a caller cannot write under another
 * seller's prefix even if it tries.
 */
export function evidenceStoragePath(userId: string, extension: string, timestamp: number): string {
  return `${userId}/transfer-evidence/${timestamp}.${extension}`;
}
