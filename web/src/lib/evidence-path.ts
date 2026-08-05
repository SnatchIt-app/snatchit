/**
 * Validation for the seller's transfer-evidence storage path.
 *
 * Deliberately its own module rather than living in transfers.ts: that file
 * imports `server-only`, which makes it unimportable from a plain node test.
 * This logic guards the payout risk engine, so it needs direct test coverage.
 */

/**
 * True only for the exact path shape uploadTransferEvidence produces, under the
 * caller's own uid prefix: `<uid>/transfer-evidence/<digits>.<ext>`.
 *
 * The path round-trips through the browser between upload and mark-sent, so by
 * the time it reaches markTransferSentAction it is attacker-controlled. The
 * payout risk engine reads `transfer_evidence_path` as its EVIDENCE_MISSING
 * signal and never verifies the path resolves to a real object, so an
 * unvalidated string would let a seller clear that signal — or point at another
 * user's proof-docs file — without uploading anything.
 */
export function isOwnEvidencePath(userId: string, path: string): boolean {
  if (!userId || !path) return false;
  if (path.includes("..") || path.includes("\\")) return false;

  const segments = path.split("/");
  if (segments.length !== 3) return false;

  const [uid, folder, file] = segments;
  return (
    uid === userId &&
    folder === "transfer-evidence" &&
    /^\d+\.[A-Za-z0-9]{1,5}$/.test(file)
  );
}
