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
  }, 60_000);

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

/**
 * C-R1 (E, 2026-10-26): the decoder proof must cover the path the app renders — `qrSvg` — not only
 * `qrToRgba`. This rasterises the SVG with a small independent reader of its own markup (viewBox,
 * the background rect, and the path's M/h/v/z commands, absolute and relative) and decodes it with
 * jsqr. What remains unproven here is expo-image's own rasterisation on a device (device gate + one
 * real scan of the rendered screen).
 */
function rasteriseSvg(svg: string, scale: number): { data: Uint8ClampedArray; width: number; height: number } {
  const vb = /viewBox="0 0 (\d+) (\d+)"/.exec(svg);
  if (!vb) throw new Error('no viewBox');
  const w = Number(vb[1]) * scale;
  const h = Number(vb[2]) * scale;
  const data = new Uint8ClampedArray(w * h * 4);
  const bg = /<rect[^>]*fill="#([0-9A-Fa-f]{6})"/.exec(svg);
  const bgv = bg ? parseInt(bg[1], 16) : 0;
  for (let i = 0; i < w * h; i++) {
    data[i * 4] = (bgv >> 16) & 255; data[i * 4 + 1] = (bgv >> 8) & 255; data[i * 4 + 2] = bgv & 255; data[i * 4 + 3] = 255;
  }
  const pathFill = /<path d="([^"]*)" fill="#([0-9A-Fa-f]{6})"/.exec(svg);
  if (!pathFill) return { data, width: w, height: h };
  const fg = parseInt(pathFill[2], 16);
  const tokens = pathFill[1].match(/[MmHhVvZz]|-?\d+(?:\.\d+)?/g) ?? [];
  let x = 0, y = 0, sx = 0, sy = 0, cmd = '';
  let pts: [number, number][] = [];
  const fillSubpath = () => {
    if (pts.length < 2) { pts = []; return; }
    const xs = pts.map((p) => p[0]); const ys = pts.map((p) => p[1]);
    const x0 = Math.min(...xs) * scale, x1 = Math.max(...xs) * scale, y0 = Math.min(...ys) * scale, y1 = Math.max(...ys) * scale;
    for (let py = y0; py < y1; py++) for (let px = x0; px < x1; px++) {
      const i = (py * w + px) * 4;
      data[i] = (fg >> 16) & 255; data[i + 1] = (fg >> 8) & 255; data[i + 2] = fg & 255;
    }
    pts = [];
  };
  for (let i = 0; i < tokens.length;) {
    const t = tokens[i];
    if (/[A-Za-z]/.test(t)) { cmd = t; i++; if (cmd === 'Z' || cmd === 'z') { x = sx; y = sy; fillSubpath(); } continue; }
    const n = Number(t); i++;
    switch (cmd) {
      case 'M': x = n; y = Number(tokens[i++]); sx = x; sy = y; pts = [[x, y]]; cmd = 'L'; break;
      case 'm': x += n; y += Number(tokens[i++]); sx = x; sy = y; pts = [[x, y]]; cmd = 'l'; break;
      case 'h': x += n; pts.push([x, y]); break;
      case 'H': x = n; pts.push([x, y]); break;
      case 'v': y += n; pts.push([x, y]); break;
      case 'V': y = n; pts.push([x, y]); break;
      default: throw new Error(`unexpected path command ${cmd}`);
    }
  }
  return { data, width: w, height: h };
}

describe('C-R1 — the SVG the app renders decodes to the exact token', () => {
  it('V1: a credential-sized token rendered through qrSvg decodes with jsqr at 4 px/module', () => {
    const t = tokenLike(11);
    const svg = qrSvg(encodeQr(t, { ec: 'M' }));
    const { data, width, height } = rasteriseSvg(svg, 4);
    expect(jsQR(data, width, height)?.data).toBe(t);
  });

  it('V2: every EC level and several lengths round-trip through the SVG path', () => {
    for (const ec of ['L', 'M', 'Q', 'H'] as const) {
      for (const n of [20, 349, 700]) {
        const t = tokenLike(n + ec.charCodeAt(0)).repeat(3).slice(0, n);
        const { data, width, height } = rasteriseSvg(qrSvg(encodeQr(t, { ec })), 3);
        expect(jsQR(data, width, height)?.data, `ec=${ec} n=${n}`).toBe(t);
      }
    }
  }, 60_000);

  it('V3: control — an SVG with the quiet zone removed is NOT what the app draws (the reader is not trivially permissive)', () => {
    const m = encodeQr('SNATCHIT', { ec: 'M' });
    const svg = qrSvg(m).replace(/fill="#FFFFFF"/, 'fill="#000000"');   // background dark = no quiet zone
    const { data, width, height } = rasteriseSvg(svg, 4);
    expect(jsQR(data, width, height, { inversionAttempts: 'dontInvert' })).toBeNull();
  });
});
