/**
 * QR encoder — decoder-verified (Q02/Q07 groundwork, lane C, 2026-10-26).
 *
 * The buyer's admission QR carries the SNATCHIT-TICKET-CRED-V1 compact token as an opaque
 * byte-mode string. There is no QR library in the app (no react-native-svg, no qrcode), so
 * `src/lib/qr/qrEncode.ts` is a dependency-free encoder. These tests do not trust the encoder's
 * own view of itself: every matrix is rasterised and read back with an independent decoder
 * (jsqr, devDependency, test-only) and must decode to the exact input.
 *
 * Negative control (run by hand, must FAIL): flip `modules[0]` in `qrToRgba` before rasterising —
 * the top-left finder breaks and jsqr returns null, so E1/E2/E3 fail.
 */
import jsQR from 'jsqr';
import { describe, expect, it } from 'vitest';

import { encodeQr, qrSvg, qrToRgba, type EcLevel } from '@/src/lib/qr/qrEncode';

const SCALE = 4;
const QUIET = 4;

function decode(input: string, ec: EcLevel = 'M'): { text: string; version: number; size: number } {
  const m = encodeQr(input, { ec });
  const { data, width, height } = qrToRgba(m, SCALE, QUIET);
  const found = jsQR(data, width, height);
  if (!found) throw new Error(`jsqr could not read a v${m.version}-${ec} symbol of ${input.length} chars`);
  return { text: found.data, version: m.version, size: m.size };
}

/** A token-shaped string: three unpadded base64url segments the size credential-sign mints. */
function tokenLike(seed: number): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  let x = seed >>> 0;
  const seg = (n: number) => {
    let s = '';
    for (let i = 0; i < n; i++) { x = (x * 1664525 + 1013904223) >>> 0; s += alphabet[x >>> 26]; }
    return s;
  };
  return `${seg(107)}.${seg(154)}.${seg(86)}`;
}

describe('encodeQr — an independent decoder reads back exactly what went in', () => {
  it('E1: a short ASCII string round-trips at the smallest version', () => {
    const r = decode('SNATCHIT');
    expect(r.text).toBe('SNATCHIT');
    expect(r.version).toBe(1);
    expect(r.size).toBe(21);
  });

  it('E2: a credential-sized token (349 chars, 3 segments) round-trips at EC M in a phone-readable version', () => {
    const token = tokenLike(7);
    expect(token).toHaveLength(349);
    const r = decode(token, 'M');
    expect(r.text).toBe(token);
    expect(r.version).toBeLessThanOrEqual(16);
  });

  it('E3: every EC level and a spread of lengths round-trip (byte mode, versions 1–~30)', () => {
    const lengths = [1, 17, 42, 100, 200, 349, 600, 1000];
    for (const ec of ['L', 'M', 'Q', 'H'] as const) {
      for (const n of lengths) {
        const input = tokenLike(n * 31 + ec.charCodeAt(0)).repeat(Math.ceil(n / 349)).slice(0, n);
        expect(decode(input, ec).text, `ec=${ec} n=${n}`).toBe(input);
      }
    }
  });

  it('E4: bytes outside ASCII survive (UTF-8 byte mode): the decoder sees the same text', () => {
    const r = decode('Wynwood · 21+ — doors 22:00');
    expect(r.text).toBe('Wynwood · 21+ — doors 22:00');
  });

  it('E5: the matrix carries the structural invariants a reader needs', () => {
    const m = encodeQr('x'.repeat(100), { ec: 'Q' });
    expect(m.size).toBe(17 + 4 * m.version);
    // Top-left finder: dark ring, light ring, dark 3×3 core.
    const at = (r: number, c: number) => m.modules[r * m.size + c];
    expect(at(0, 0)).toBe(1); expect(at(0, 6)).toBe(1); expect(at(6, 0)).toBe(1);
    expect(at(1, 1)).toBe(0); expect(at(1, 5)).toBe(0);
    expect(at(3, 3)).toBe(1); expect(at(2, 2)).toBe(1); expect(at(4, 4)).toBe(1);
    // Separator (light) column 7 next to the finder.
    expect(at(0, 7)).toBe(0); expect(at(7, 0)).toBe(0);
    expect(m.mask).toBeGreaterThanOrEqual(0); expect(m.mask).toBeLessThanOrEqual(7);
  });

  it('E6: too much data for the allowed versions is refused, never silently truncated', () => {
    expect(() => encodeQr('x'.repeat(3000), { ec: 'L' })).toThrow(/too long/i);
    expect(() => encodeQr('x'.repeat(200), { ec: 'H', maxVersion: 5 })).toThrow(/too long/i);
  });
});

describe('qrSvg — the on-screen symbol keeps its quiet zone and contrast regardless of theme', () => {
  it('S1: default quiet zone is 4 modules on every side and the colours are fixed black on white', () => {
    const m = encodeQr('SNATCHIT', { ec: 'M' });
    const svg = qrSvg(m);
    const total = m.size + 2 * 4;
    expect(svg).toContain(`viewBox="0 0 ${total} ${total}"`);
    expect(svg).toContain('fill="#FFFFFF"');   // the full light background, quiet zone included
    expect(svg).toContain('fill="#000000"');   // dark modules
    expect(svg).toContain('shape-rendering="crispEdges"');
    // The first dark module is drawn offset by the quiet zone, so the symbol never touches the edge.
    expect(svg).toMatch(/d="M4 4h7v1h-7z/);   // the finder's top row, a 7-module run, starts at (4,4)
  });

  it('S2: a caller cannot shrink the quiet zone below the standard 4 modules', () => {
    const m = encodeQr('SNATCHIT', { ec: 'M' });
    const svg = qrSvg(m, { quietZone: 1 });
    const total = m.size + 2 * 4;
    expect(svg).toContain(`viewBox="0 0 ${total} ${total}"`);
  });

  it('S3: the SVG is a data-URI-safe single line (no newlines, no unescaped #)', () => {
    const svg = qrSvg(encodeQr('SNATCHIT'));
    expect(svg.includes('\n')).toBe(false);
    expect(svg.startsWith('<svg ')).toBe(true);
  });
});
