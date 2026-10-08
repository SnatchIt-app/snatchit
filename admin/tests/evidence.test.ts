import { describe, expect, it } from "vitest";
import { EVIDENCE_SLOTS, evidenceItems, isEvidenceSlot, isEvidenceSubjectKind, toEvidence, toEvidenceAccess } from "../src/lib/types";

const TRANSFER = "aa000000-0000-4000-8000-000000000001";
const LISTING = "bb000000-0000-4000-8000-000000000002";

describe("evidence slot allowlist (mirror of ops.evidence_access)", () => {
  it("transfer slots", () => {
    expect([...EVIDENCE_SLOTS.transfer]).toEqual(["transfer_evidence", "transfer_screenshot", "dispute_evidence"]);
    for (const s of EVIDENCE_SLOTS.transfer) expect(isEvidenceSlot("transfer", s)).toBe(true);
    expect(isEvidenceSlot("transfer", "proof_of_ownership")).toBe(false);
    expect(isEvidenceSlot("transfer", "cover_image")).toBe(false);
  });
  it("listing slots", () => {
    expect([...EVIDENCE_SLOTS.listing]).toEqual(["proof_of_ownership"]);
    expect(isEvidenceSlot("listing", "proof_of_ownership")).toBe(true);
    expect(isEvidenceSlot("listing", "transfer_evidence")).toBe(false);
    expect(isEvidenceSlot("listing", "cover_image")).toBe(false);
  });
  it("rejects junk slots and subject kinds", () => {
    expect(isEvidenceSlot("transfer", "../../etc/passwd")).toBe(false);
    expect(isEvidenceSlot("listing", null)).toBe(false);
    expect(isEvidenceSlot("listing", 3)).toBe(false);
    expect(isEvidenceSubjectKind("payment")).toBe(false);
    expect(isEvidenceSubjectKind("transfer")).toBe(true);
    expect(isEvidenceSubjectKind("listing")).toBe(true);
  });
});

describe("evidenceItems binds detail keys to the owning record", () => {
  const refs = toEvidence({
    transfer_evidence_path: { bucket: "proof-docs", path: "t/1/evidence.pdf" },
    transfer_screenshot_path: { bucket: "proof-docs", path: null },
    dispute_evidence_path: { bucket: "proof-docs", path: "t/1/dispute.png" },
    proof_of_ownership_path: { bucket: "proof-docs", path: "l/2/proof.pdf" },
    cover_image_path: { bucket: "auction-media", path: "l/2/cover.jpg" },
  });

  it("maps every private slot to (subject, slot) and never carries the path", () => {
    const items = evidenceItems(refs, { transferId: TRANSFER, listingId: LISTING });
    expect(items).toEqual([
      { kind: "audited", key: "transfer_evidence_path", slot: "transfer_evidence", subjectKind: "transfer", subjectId: TRANSFER, recorded: true },
      { kind: "audited", key: "transfer_screenshot_path", slot: "transfer_screenshot", subjectKind: "transfer", subjectId: TRANSFER, recorded: false },
      { kind: "audited", key: "dispute_evidence_path", slot: "dispute_evidence", subjectKind: "transfer", subjectId: TRANSFER, recorded: true },
      { kind: "audited", key: "proof_of_ownership_path", slot: "proof_of_ownership", subjectKind: "listing", subjectId: LISTING, recorded: true },
      { kind: "public", key: "cover_image_path", bucket: "auction-media", path: "l/2/cover.jpg", recorded: true },
    ]);
    for (const it of items) if (it.kind === "audited") expect(it).not.toHaveProperty("path");
  });

  it("is unresolvable (not signed) when the owning id is unknown on the page", () => {
    const items = evidenceItems(refs, { listingId: LISTING });
    expect(items.find((i) => i.key === "transfer_evidence_path")).toEqual({ kind: "unresolvable", key: "transfer_evidence_path", recorded: true });
    expect(items.find((i) => i.key === "proof_of_ownership_path")?.kind).toBe("audited");
  });

  it("only auction-media may be public; unknown keys are unresolvable", () => {
    const odd = toEvidence({ cover_image_path: { bucket: "proof-docs", path: "x" }, secret_path: { bucket: "proof-docs", path: "y" } });
    const items = evidenceItems(odd, { transferId: TRANSFER, listingId: LISTING });
    expect(items[0]).toEqual({ kind: "unresolvable", key: "cover_image_path", recorded: true });
    expect(items[1]).toEqual({ kind: "unresolvable", key: "secret_path", recorded: true });
  });
});

describe("toEvidenceAccess (ops.evidence_access payload)", () => {
  it("narrows the RPC reply and clamps the ttl", () => {
    expect(toEvidenceAccess({ bucket: "proof-docs", path: "t/1/e.pdf", expires_in_seconds: 300, slot: "transfer_evidence", subject_kind: "transfer", subject_id: TRANSFER })).toEqual({
      bucket: "proof-docs",
      path: "t/1/e.pdf",
      expires_in_seconds: 300,
      slot: "transfer_evidence",
      subject_kind: "transfer",
      subject_id: TRANSFER,
    });
    expect(toEvidenceAccess({ bucket: "proof-docs", path: "p", expires_in_seconds: 99999 })?.expires_in_seconds).toBe(3600);
    expect(toEvidenceAccess({ bucket: "proof-docs", path: "p" })?.expires_in_seconds).toBe(300);
  });
  it("refuses replies without a bucket or path", () => {
    expect(toEvidenceAccess({ bucket: "proof-docs" })).toBeNull();
    expect(toEvidenceAccess({ path: "p" })).toBeNull();
    expect(toEvidenceAccess("nope")).toBeNull();
  });
});
