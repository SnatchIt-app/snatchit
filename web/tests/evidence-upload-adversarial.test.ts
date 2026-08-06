/**
 * Adversarial coverage for src/lib/evidence-upload.ts.
 *
 * Complements tests/evidence-upload.test.ts (the stored-XSS regression set).
 * Focus here: MIME normalisation tricks, size-check edge values, and the trust
 * boundary of evidenceStoragePath — which is a string builder, not a
 * validator. The round-trip block pairs it with isOwnEvidencePath (the
 * server-side checker in evidence-path.ts) so the writer and the checker
 * cannot drift apart.
 */
import { describe, expect, it } from "vitest";
import {
  ALLOWED_EVIDENCE_TYPES,
  MAX_EVIDENCE_SIZE_MB,
  MIME_FOR_EXTENSION,
  evidenceStoragePath,
  validateEvidenceFile,
} from "@/lib/evidence-upload";
import { isOwnEvidencePath } from "@/lib/evidence-path";

const OK_SIZE = 1024;
const MAX_BYTES = MAX_EVIDENCE_SIZE_MB * 1024 * 1024;
const UID = "6fc6c182-3fd4-485b-a6dd-d1431ca868cb";
const OTHER_UID = "60f0d8de-412a-4dfe-961d-a1e39e445913";

describe("validateEvidenceFile — MIME parsing", () => {
  it("accepts parameters, odd casing and surrounding whitespace", () => {
    for (const t of [
      "image/jpeg;charset=binary",
      "image/jpeg ; charset=binary",
      "  image/jpeg  ",
      "IMAGE/JPEG;CHARSET=UTF-8",
      "Image/Jpeg",
      "image/png;a=1;b=2",
      "application/pdf; version=1.7",
      "image/jpeg;",
    ]) {
      expect(validateEvidenceFile(t, OK_SIZE).ok, t).toBe(true);
    }
  });

  it("rejects every svg spelling — svg carries <script>", () => {
    for (const t of [
      "image/svg+xml",
      "IMAGE/SVG+XML",
      "image/svg+xml; charset=utf-8",
      "image/svg",
      "text/xml",
      "application/xml",
      "application/xhtml+xml",
      "text/html;charset=utf-8",
      "image/svg+xml;image/jpeg",
    ]) {
      expect(validateEvidenceFile(t, OK_SIZE).ok, t).toBe(false);
    }
  });

  it("only trusts the media type BEFORE the first semicolon", () => {
    // A hostile type cannot hide behind a parameter...
    expect(validateEvidenceFile("text/html;image/jpeg", OK_SIZE).ok).toBe(false);
    // ...and an allowed type is not disqualified by junk in its parameters.
    expect(validateEvidenceFile("image/jpeg;evil=text/html", OK_SIZE).ok).toBe(true);
  });

  it("fails closed on empty, punctuation-only and lookalike types", () => {
    for (const t of [
      "",
      " ",
      ";",
      ";image/jpeg",
      "image/jpeg text/html",
      "іmage/jpeg", // Cyrillic 'i' homoglyph
      "image∕jpeg", // U+2215 division slash, not U+002F
      "imagejpeg",
      "image/",
      "/jpeg",
      "a".repeat(10_000),
    ]) {
      expect(validateEvidenceFile(t, OK_SIZE).ok, JSON.stringify(t.slice(0, 24))).toBe(false);
    }
  });

  it("treats non-whitespace control characters as part of the type", () => {
    // trim() strips the Unicode WhiteSpace set, which does NOT include NUL, so
    // a NUL-padded type misses the allow-list and is rejected (fail closed).
    expect(validateEvidenceFile("image/jpeg\u0000", OK_SIZE).ok).toBe(false);
    expect(validateEvidenceFile("image/jpeg\u0000text/html", OK_SIZE).ok).toBe(false);
    // NBSP and the usual line terminators ARE whitespace, so they are stripped.
    expect(validateEvidenceFile("image/jpeg\u00a0", OK_SIZE).ok).toBe(true);
    expect(validateEvidenceFile("\nimage/jpeg\t", OK_SIZE).ok).toBe(true);
  });

  it("never returns an extension on the reject path", () => {
    const r = validateEvidenceFile("text/html", OK_SIZE);
    expect(r.ok).toBe(false);
    expect(r).not.toHaveProperty("extension");
    expect(r.ok === false && r.error.length).toBeGreaterThan(0);
  });
});

describe("validateEvidenceFile — size checks", () => {
  it("rejects zero and negative sizes as empty", () => {
    for (const size of [0, -0, -1, -OK_SIZE, -MAX_BYTES]) {
      const r = validateEvidenceFile("image/jpeg", size);
      expect(r.ok, String(size)).toBe(false);
      expect(r.ok === false && r.error).toMatch(/empty/i);
    }
  });

  it("is inclusive at exactly the limit and rejects one byte over", () => {
    expect(validateEvidenceFile("image/jpeg", MAX_BYTES - 1).ok).toBe(true);
    expect(validateEvidenceFile("image/jpeg", MAX_BYTES).ok).toBe(true);
    const over = validateEvidenceFile("image/jpeg", MAX_BYTES + 1);
    expect(over.ok).toBe(false);
    expect(over.ok === false && over.error).toContain(`${MAX_EVIDENCE_SIZE_MB}MB`);
  });

  it("rejects Infinity and MAX_SAFE_INTEGER as oversized", () => {
    expect(validateEvidenceFile("image/jpeg", Infinity).ok).toBe(false);
    expect(validateEvidenceFile("image/jpeg", Number.MAX_SAFE_INTEGER).ok).toBe(false);
    expect(validateEvidenceFile("image/jpeg", -Infinity).ok).toBe(false);
  });

  it("rejects a non-finite size instead of failing open", () => {
    // Every comparison against NaN is false, so NaN used to pass BOTH the
    // empty-file and the 10MB check and come back ok with a valid extension.
    // Not reachable via lib/transfers.ts, which passes a real File.size, but
    // live the moment a caller derives size from a form field (Number("")).
    expect(validateEvidenceFile("image/jpeg", NaN).ok).toBe(false);
    expect(validateEvidenceFile("image/jpeg", Infinity).ok).toBe(false);
    expect(validateEvidenceFile("image/jpeg", undefined as unknown as number).ok).toBe(false);
    // null coerces to 0 and IS caught, which is what makes NaN the odd one out.
    expect(validateEvidenceFile("image/jpeg", null as unknown as number).ok).toBe(false);
  });

  it("accepts fractional sizes above zero", () => {
    expect(validateEvidenceFile("image/jpeg", 0.5).ok).toBe(true);
  });
});

describe("extension <-> MIME mapping", () => {
  it("round-trips every allowed type back to itself", () => {
    for (const t of ALLOWED_EVIDENCE_TYPES) {
      const r = validateEvidenceFile(t, OK_SIZE);
      expect(r.ok, t).toBe(true);
      if (!r.ok) continue;
      expect(MIME_FOR_EXTENSION[r.extension], t).toBe(t);
    }
  });

  it("derives extensions that the storage-path checker will accept", () => {
    // isOwnEvidencePath only allows /^\d+\.[A-Za-z0-9]{1,5}$/ — an extension
    // longer than 5 chars or containing '+'/'-' would silently break evidence
    // download for every seller.
    for (const t of ALLOWED_EVIDENCE_TYPES) {
      const r = validateEvidenceFile(t, OK_SIZE);
      expect(r.ok && /^[a-z0-9]{1,5}$/.test(r.extension), t).toBe(true);
    }
  });

  it("returns undefined for unknown extensions so callers' ?? fallback fires", () => {
    // lib/transfers.ts does `MIME_FOR_EXTENSION[ext] ?? "application/octet-stream"`.
    for (const ext of ["html", "svg", "exe", "jpeg", "JPG", "php", ""]) {
      expect(MIME_FOR_EXTENSION[ext], ext).toBeUndefined();
    }
  });

  it("maps nothing to a scriptable content type", () => {
    for (const [ext, mime] of Object.entries(MIME_FOR_EXTENSION)) {
      expect(mime, ext).not.toMatch(/html|svg|script|xml/i);
      expect(mime, ext).toMatch(/^(image\/|application\/pdf)/);
    }
  });

  it("documents that a prototype key defeats the ?? fallback (unreachable today)", () => {
    // MIME_FOR_EXTENSION["__proto__"] is Object.prototype, not undefined, so a
    // caller's `?? "application/octet-stream"` would not fire. Safe only
    // because the extension always comes from validateEvidenceFile.
    expect(MIME_FOR_EXTENSION["__proto__"]).toBeDefined();
    expect(typeof MIME_FOR_EXTENSION["__proto__"]).not.toBe("string");
  });
});

describe("evidenceStoragePath", () => {
  it("always writes under <userId>/transfer-evidence/", () => {
    expect(evidenceStoragePath(UID, "jpg", 1700000000000)).toBe(
      `${UID}/transfer-evidence/1700000000000.jpg`,
    );
    expect(evidenceStoragePath(UID, "pdf", 1).startsWith(`${UID}/transfer-evidence/`)).toBe(true);
  });

  it("round-trips through isOwnEvidencePath for every allowed type", () => {
    const now = 1785452140599;
    for (const t of ALLOWED_EVIDENCE_TYPES) {
      const r = validateEvidenceFile(t, OK_SIZE);
      expect(r.ok, t).toBe(true);
      if (!r.ok) continue;
      const path = evidenceStoragePath(UID, r.extension, now);
      expect(isOwnEvidencePath(UID, path), `${t} -> ${path}`).toBe(true);
      // ...and the same path is not accepted for anyone else.
      expect(isOwnEvidencePath(OTHER_UID, path), t).toBe(false);
    }
  });

  it("does NOT sanitise its inputs — it is a builder, not a validator", () => {
    // Safety comes from userId being the server-side session uid plus the
    // proof-docs INSERT policy, not from this function.
    expect(evidenceStoragePath("../../" + OTHER_UID, "jpg", 1)).toBe(
      `../../${OTHER_UID}/transfer-evidence/1.jpg`,
    );
    expect(evidenceStoragePath("a/b", "jpg", 1)).toBe("a/b/transfer-evidence/1.jpg");
    expect(evidenceStoragePath("", "jpg", 1)).toBe("/transfer-evidence/1.jpg");
    expect(evidenceStoragePath(UID, "jpg.html", 1)).toBe(`${UID}/transfer-evidence/1.jpg.html`);
    expect(evidenceStoragePath(UID, "../x", 1)).toBe(`${UID}/transfer-evidence/1.../x`);
    expect(evidenceStoragePath(UID, "jpg", NaN)).toBe(`${UID}/transfer-evidence/NaN.jpg`);
    expect(evidenceStoragePath(UID, "jpg", -1)).toBe(`${UID}/transfer-evidence/-1.jpg`);
  });

  it("every unsanitised shape above is rejected downstream by isOwnEvidencePath", () => {
    for (const path of [
      evidenceStoragePath("../../" + OTHER_UID, "jpg", 1),
      evidenceStoragePath(OTHER_UID, "jpg", 1),
      evidenceStoragePath("a/b", "jpg", 1),
      evidenceStoragePath("", "jpg", 1),
      evidenceStoragePath(UID, "jpg.html", 1),
      evidenceStoragePath(UID, "../x", 1),
      evidenceStoragePath(UID, "jpg", NaN),
      evidenceStoragePath(UID, "jpg", -1),
      evidenceStoragePath(UID, "toolongext", 1),
    ]) {
      expect(isOwnEvidencePath(UID, path), path).toBe(false);
    }
  });

  it("keeps distinct timestamps distinct (no collision within a user's folder)", () => {
    expect(evidenceStoragePath(UID, "jpg", 1)).not.toBe(evidenceStoragePath(UID, "jpg", 2));
  });
});
