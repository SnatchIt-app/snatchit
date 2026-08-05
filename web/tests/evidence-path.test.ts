import { describe, it, expect } from "vitest";
import { isOwnEvidencePath } from "@/lib/evidence-path";
const uid = "6fc6c182-3fd4-485b-a6dd-d1431ca868cb";
const other = "60f0d8de-412a-4dfe-961d-a1e39e445913";
describe("isOwnEvidencePath", () => {
  it("accepts the shape uploadTransferEvidence produces", () => {
    expect(isOwnEvidencePath(uid, `${uid}/transfer-evidence/1785452140599.jpg`)).toBe(true);
    expect(isOwnEvidencePath(uid, `${uid}/transfer-evidence/1.png`)).toBe(true);
  });
  it("rejects another user's path", () => {
    expect(isOwnEvidencePath(uid, `${other}/transfer-evidence/1785452140599.jpg`)).toBe(false);
  });
  it("rejects traversal and nesting", () => {
    expect(isOwnEvidencePath(uid, `${uid}/transfer-evidence/../../x.jpg`)).toBe(false);
    expect(isOwnEvidencePath(uid, `${uid}/transfer-evidence/a/b.jpg`)).toBe(false);
    expect(isOwnEvidencePath(uid, `${uid}\\transfer-evidence\\1.jpg`)).toBe(false);
  });
  it("rejects wrong folder, empty, and arbitrary strings", () => {
    expect(isOwnEvidencePath(uid, `${uid}/proofs/1.jpg`)).toBe(false);
    expect(isOwnEvidencePath(uid, "")).toBe(false);
    expect(isOwnEvidencePath(uid, "anything")).toBe(false);
    expect(isOwnEvidencePath(uid, `${uid}/transfer-evidence/notdigits.jpg`)).toBe(false);
  });
});
