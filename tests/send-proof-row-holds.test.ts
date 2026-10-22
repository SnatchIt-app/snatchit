/**
 * The chosen transfer proof stays on screen until the read-back lands (TEST-MODE capture finding 5,
 * 2026-10-19). During Mark as sent, the Transfer proof row reset to empty ("ADD") while the spinner
 * still ran: `evidenceUpload.reset()` ran BEFORE `await fetchTransfer(true)`, so for the length of
 * that read the seller saw their proof apparently dropped. Add proof had the same order. The reset
 * now follows the read, so the row goes straight from the chosen photo to the read-back's face.
 * Source contract with a witness. Not a device result.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const send = readFileSync('app/transfer/send/[id].tsx', 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

function branch(src: string, kind: string): string {
  const at = src.indexOf(`if (outcome.kind === '${kind}') {`);
  expect(at, `${kind} branch`).toBeGreaterThan(-1);
  return src.slice(at, src.indexOf('return;', at));
}

/** The read-back is awaited before the photo is cleared. */
const readsFirst = (b: string) =>
  b.indexOf('await fetchTransfer(true);') > -1 && b.indexOf('evidenceUpload.reset();') > b.indexOf('await fetchTransfer(true);');

const swapped = (src: string) =>
  src.replace(/await fetchTransfer\(true\);(\s*)evidenceUpload\.reset\(\);/g, 'evidenceUpload.reset();$1await fetchTransfer(true);');

describe('proof row holds through the read-back', () => {
  it.each(['sent', 'attached'])('SP: on %s, the photo clears only after the transfer re-read', (kind) => {
    expect(readsFirst(branch(send, kind))).toBe(true);
    // Witness: the build-29 order fails the same check.
    expect(readsFirst(branch(swapped(send), kind))).toBe(false);
  });

  it('SP3: each success branch still clears exactly once (regression guard)', () => {
    expect(branch(send, 'sent').split('evidenceUpload.reset();').length - 1).toBe(1);
    expect(branch(send, 'attached').split('evidenceUpload.reset();').length - 1).toBe(1);
  });
});
