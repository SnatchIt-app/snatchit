/**
 * tests/session-storage-torn-write.test.ts — the session blob and its key can
 * never disagree.
 *
 * Structural hazard found while investigating D5's session loss (labelled a
 * HYPOTHESIS for that incident, not a confirmed cause): the adapter minted a new
 * AES key on every write and stored it in the Keychain before the blob reached
 * AsyncStorage. A suspend/kill between the two — a 3-D Secure handoff, a deep
 * link relaunch — left a key that could not decrypt the blob, and getItem then
 * deleted the session locally with no server traffic. That silent client-side
 * loss is the only shape consistent with the sandbox auth log (no logout, no
 * refresh, no revocation).
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const src = readFileSync(resolve(__dirname, '..', 'src/lib/secureStorage.ts'), 'utf8');
const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('session storage: key reuse removes the torn-write hazard', () => {
  it('the key is loaded before it is created, and created only when absent', () => {
    const fn = code.slice(code.indexOf('async function loadOrCreateKey'), code.indexOf('async function encrypt'));
    expect(fn.indexOf('SecureStore.getItemAsync')).toBeGreaterThan(-1);
    expect(fn.indexOf('SecureStore.getItemAsync')).toBeLessThan(fn.indexOf('getRandomValues'));
    expect(fn).toMatch(/if \(existingHex\) return/);
  });

  it('encrypt no longer mints a key per write', () => {
    const enc = code.slice(code.indexOf('async function encrypt'), code.indexOf('async function decrypt'));
    expect(enc).not.toContain('getRandomValues');
    expect(enc).not.toContain('SecureStore.setItemAsync');
    expect(enc).toContain('loadOrCreateKey(key)');
  });

  it('a decrypt failure is still non-fatal, but no longer reachable by a torn write', () => {
    // the defensive clear stays for genuinely corrupt data (OS restore wiped the Keychain)
    expect(code).toContain("console.warn('[secureStorage] decrypt failed; clearing entry'");
    expect(code).toContain('await this.removeItem(key);');
  });

  it('removeItem still wipes both halves, so sign-out leaves nothing behind', () => {
    const rm = code.slice(code.indexOf('async removeItem'));
    expect(rm).toContain('AsyncStorage.removeItem(blobKeyName(key))');
    expect(rm).toContain('SecureStore.deleteItemAsync(secureKeyName(key))');
  });

  it('existing sessions stay readable: the stored key is the one the last blob used', () => {
    // the old adapter always left the Keychain holding the key of the LAST write,
    // which is the key the current blob was encrypted with — reuse is a no-op for them
    expect(code).not.toMatch(/deleteItemAsync\(secureKeyName\(key\)\)[^}]*setItemAsync/);
  });
});
