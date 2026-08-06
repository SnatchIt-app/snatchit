import { describe, expect, it } from "vitest";
import {
  MAX_EVIDENCE_SIZE_MB,
  MIME_FOR_EXTENSION,
  evidenceStoragePath,
  validateEvidenceFile,
} from "../src/lib/evidence-upload";

const OK_SIZE = 1024;

describe("validateEvidenceFile", () => {
  it("accepts the image types sellers actually upload", () => {
    for (const t of ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]) {
      expect(validateEvidenceFile(t, OK_SIZE).ok, t).toBe(true);
    }
  });

  it("keeps PDF receipts working", () => {
    const r = validateEvidenceFile("application/pdf", OK_SIZE);
    expect(r.ok).toBe(true);
    expect(r.ok && r.extension).toBe("pdf");
  });

  // The whole point of the change: these are what produced stored XSS when
  // the file was later handed to the buyer as a signed URL.
  it("rejects script-capable and executable types", () => {
    for (const t of [
      "text/html",
      "image/svg+xml",
      "application/xhtml+xml",
      "text/javascript",
      "application/javascript",
      "application/x-msdownload",
      "application/octet-stream",
      "text/plain",
    ]) {
      expect(validateEvidenceFile(t, OK_SIZE).ok, t).toBe(false);
    }
  });

  it("is not fooled by casing or a charset parameter", () => {
    expect(validateEvidenceFile("IMAGE/JPEG", OK_SIZE).ok).toBe(true);
    expect(validateEvidenceFile("image/jpeg; charset=binary", OK_SIZE).ok).toBe(true);
    // ...and the same normalisation must not let text/html slip through.
    expect(validateEvidenceFile("TEXT/HTML; charset=utf-8", OK_SIZE).ok).toBe(false);
  });

  it("rejects empty and oversized files", () => {
    expect(validateEvidenceFile("image/jpeg", 0).ok).toBe(false);
    expect(validateEvidenceFile("image/jpeg", MAX_EVIDENCE_SIZE_MB * 1024 * 1024 + 1).ok).toBe(false);
    expect(validateEvidenceFile("image/jpeg", MAX_EVIDENCE_SIZE_MB * 1024 * 1024).ok).toBe(true);
  });

  it("derives the extension from the type, never the filename", () => {
    // An attacker naming their HTML file "receipt.jpg" gets rejected on type;
    // a real JPEG named "x.html" is still stored as .jpg.
    expect(validateEvidenceFile("text/html", OK_SIZE).ok).toBe(false);
    const jpeg = validateEvidenceFile("image/jpeg", OK_SIZE);
    expect(jpeg.ok && jpeg.extension).toBe("jpg");
  });

  it("maps every accepted extension back to a non-HTML content type", () => {
    for (const t of ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "application/pdf"]) {
      const r = validateEvidenceFile(t, OK_SIZE);
      expect(r.ok).toBe(true);
      if (!r.ok) continue;
      const mime = MIME_FOR_EXTENSION[r.extension];
      expect(mime).toBeDefined();
      expect(mime).not.toMatch(/html|svg|script/);
    }
  });
});

describe("evidenceStoragePath", () => {
  it("writes under the owner's folder, as the proof-docs policy requires", () => {
    expect(evidenceStoragePath("user-1", "jpg", 1700000000000)).toBe(
      "user-1/transfer-evidence/1700000000000.jpg",
    );
  });
});
