/**
 * src/lib/qr/qrEncode.ts — a dependency-free QR Code encoder (ISO/IEC 18004, byte mode) and
 * two renderers: an SVG string for expo-image and an RGBA raster for tests and exported renders.
 *
 * Why hand-rolled: the app has no react-native-svg (native module) and no qrcode package, and
 * the admission QR must not wait on a dependency freeze. The symbol carries ONE opaque string —
 * the SNATCHIT-TICKET-CRED-V1 compact token — in byte mode. Nothing here interprets the token.
 *
 * Correctness is proven by an independent decoder in tests/qr-encode.test.ts (jsqr reads every
 * generated symbol back), not by this file's own arithmetic. Tables follow the standard
 * (error-correction codewords per block and block counts per version/level; alignment pattern
 * positions and raw module counts derived by formula).
 *
 * Display rules fixed here, not by callers: a 4-module quiet zone (callers can widen, never
 * shrink) and black modules on a white field regardless of the app theme — contrast for a camera
 * is not a theme preference.
 */

export type EcLevel = 'L' | 'M' | 'Q' | 'H';

export interface QrMatrix {
  version: number;
  size: number;
  ec: EcLevel;
  /** size*size entries, row-major, 1 = dark. */
  modules: Uint8Array;
  mask: number;
}

export interface EncodeOptions {
  ec?: EcLevel;
  minVersion?: number;
  maxVersion?: number;
}

export const MIN_QUIET_ZONE = 4;

const EC_INDEX: Record<EcLevel, number> = { L: 0, M: 1, Q: 2, H: 3 };
const EC_FORMAT_BITS: Record<EcLevel, number> = { L: 1, M: 0, Q: 3, H: 2 };

// Index = version (0 unused). Rows: L, M, Q, H.
const ECC_CODEWORDS_PER_BLOCK: readonly (readonly number[])[] = [
  [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
  [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
];
const NUM_EC_BLOCKS: readonly (readonly number[])[] = [
  [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
  [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
  [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
  [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
];

/** Data modules available after the function patterns, for a version (spec formula). */
function rawDataModules(ver: number): number {
  let result = (16 * ver + 128) * ver + 64;
  if (ver >= 2) {
    const numAlign = Math.floor(ver / 7) + 2;
    result -= (25 * numAlign - 10) * numAlign - 55;
    if (ver >= 7) result -= 36;
  }
  return result;
}

function numDataCodewords(ver: number, ec: EcLevel): number {
  const i = EC_INDEX[ec];
  return Math.floor(rawDataModules(ver) / 8) - ECC_CODEWORDS_PER_BLOCK[i][ver] * NUM_EC_BLOCKS[i][ver];
}

function alignmentPositions(ver: number): number[] {
  if (ver === 1) return [];
  const numAlign = Math.floor(ver / 7) + 2;
  const size = 17 + 4 * ver;
  const step = ver === 32 ? 26 : Math.ceil((ver * 4 + 4) / (numAlign * 2 - 2)) * 2;
  const result = [6];
  for (let pos = size - 7; result.length < numAlign; pos -= step) result.splice(1, 0, pos);
  return result;
}

// ── UTF-8 without TextEncoder (Hermes-safe) ──────────────────────────────────
function utf8Bytes(s: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let c = s.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      const d = s.charCodeAt(i + 1);
      if (d >= 0xdc00 && d <= 0xdfff) { c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00); i++; }
    }
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
  }
  return Uint8Array.from(out);
}

// ── Reed–Solomon over GF(256), polynomial 0x11D ──────────────────────────────
function gfMul(x: number, y: number): number {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
}

function rsGenerator(degree: number): Uint8Array {
  const result = new Uint8Array(degree);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < degree; j++) {
      result[j] = gfMul(result[j], root);
      if (j + 1 < degree) result[j] ^= result[j + 1];
    }
    root = gfMul(root, 0x02);
  }
  return result;
}

function rsRemainder(data: Uint8Array, generator: Uint8Array): Uint8Array {
  const result = new Uint8Array(generator.length);
  for (const b of data) {
    const factor = b ^ result[0];
    result.copyWithin(0, 1);
    result[result.length - 1] = 0;
    for (let i = 0; i < generator.length; i++) result[i] ^= gfMul(generator[i], factor);
  }
  return result;
}

// ── Bit stream → data codewords ──────────────────────────────────────────────
function buildCodewords(bytes: Uint8Array, ver: number, ec: EcLevel): Uint8Array {
  const bits: number[] = [];
  const push = (value: number, n: number) => { for (let i = n - 1; i >= 0; i--) bits.push((value >>> i) & 1); };
  push(0b0100, 4);
  push(bytes.length, ver <= 9 ? 8 : 16);
  for (const b of bytes) push(b, 8);
  const capacity = numDataCodewords(ver, ec) * 8;
  push(0, Math.min(4, capacity - bits.length));
  while (bits.length % 8 !== 0) bits.push(0);
  for (let pad = 0xec; bits.length < capacity; pad ^= 0xec ^ 0x11) push(pad, 8);
  const out = new Uint8Array(bits.length / 8);
  for (let i = 0; i < bits.length; i++) out[i >>> 3] |= bits[i] << (7 - (i & 7));
  return out;
}

function interleave(data: Uint8Array, ver: number, ec: EcLevel): Uint8Array {
  const i = EC_INDEX[ec];
  const numBlocks = NUM_EC_BLOCKS[i][ver];
  const eccLen = ECC_CODEWORDS_PER_BLOCK[i][ver];
  const rawCodewords = Math.floor(rawDataModules(ver) / 8);
  const numShortBlocks = numBlocks - (rawCodewords % numBlocks);
  const shortBlockLen = Math.floor(rawCodewords / numBlocks);
  const generator = rsGenerator(eccLen);
  const blocks: Uint8Array[] = [];
  let k = 0;
  for (let b = 0; b < numBlocks; b++) {
    const datLen = shortBlockLen - eccLen + (b < numShortBlocks ? 0 : 1);
    const dat = data.subarray(k, k + datLen);
    k += datLen;
    const ecc = rsRemainder(dat, generator);
    const block = new Uint8Array(shortBlockLen + 1);
    block.set(dat, 0);
    block.set(ecc, shortBlockLen + 1 - eccLen);
    blocks.push(block);
  }
  const result = new Uint8Array(rawCodewords);
  let n = 0;
  for (let col = 0; col < blocks[0].length; col++) {
    for (let b = 0; b < blocks.length; b++) {
      if (col !== shortBlockLen - eccLen || b >= numShortBlocks) result[n++] = blocks[b][col];
    }
  }
  return result;
}

// ── Matrix construction ──────────────────────────────────────────────────────
class Grid {
  readonly size: number;
  readonly modules: Uint8Array;
  readonly isFunction: Uint8Array;
  constructor(size: number) {
    this.size = size;
    this.modules = new Uint8Array(size * size);
    this.isFunction = new Uint8Array(size * size);
  }
  setFunction(x: number, y: number, dark: boolean): void {
    this.modules[y * this.size + x] = dark ? 1 : 0;
    this.isFunction[y * this.size + x] = 1;
  }
  get(x: number, y: number): number { return this.modules[y * this.size + x]; }
}

function drawFinder(g: Grid, cx: number, cy: number): void {
  for (let dy = -4; dy <= 4; dy++) {
    for (let dx = -4; dx <= 4; dx++) {
      const dist = Math.max(Math.abs(dx), Math.abs(dy));
      const x = cx + dx, y = cy + dy;
      if (x >= 0 && x < g.size && y >= 0 && y < g.size) g.setFunction(x, y, dist !== 2 && dist !== 4);
    }
  }
}

function drawAlignment(g: Grid, cx: number, cy: number): void {
  for (let dy = -2; dy <= 2; dy++) {
    for (let dx = -2; dx <= 2; dx++) g.setFunction(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  }
}

function drawFormatBits(g: Grid, ec: EcLevel, mask: number): void {
  const data = (EC_FORMAT_BITS[ec] << 3) | mask;
  let rem = data;
  for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
  const bits = ((data << 10) | rem) ^ 0x5412;
  const bit = (i: number) => ((bits >>> i) & 1) === 1;
  const s = g.size;
  for (let i = 0; i <= 5; i++) g.setFunction(8, i, bit(i));
  g.setFunction(8, 7, bit(6));
  g.setFunction(8, 8, bit(7));
  g.setFunction(7, 8, bit(8));
  for (let i = 9; i < 15; i++) g.setFunction(14 - i, 8, bit(i));
  for (let i = 0; i < 8; i++) g.setFunction(s - 1 - i, 8, bit(i));
  for (let i = 8; i < 15; i++) g.setFunction(8, s - 15 + i, bit(i));
  g.setFunction(8, s - 8, true);
}

function drawVersionBits(g: Grid, ver: number): void {
  if (ver < 7) return;
  let rem = ver;
  for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
  const bits = (ver << 12) | rem;
  for (let i = 0; i < 18; i++) {
    const bit = ((bits >>> i) & 1) === 1;
    const a = g.size - 11 + (i % 3);
    const b = Math.floor(i / 3);
    g.setFunction(a, b, bit);
    g.setFunction(b, a, bit);
  }
}

function drawFunctionPatterns(g: Grid, ver: number, ec: EcLevel): void {
  const s = g.size;
  for (let i = 0; i < s; i++) {
    g.setFunction(6, i, i % 2 === 0);
    g.setFunction(i, 6, i % 2 === 0);
  }
  drawFinder(g, 3, 3);
  drawFinder(g, s - 4, 3);
  drawFinder(g, 3, s - 4);
  const align = alignmentPositions(ver);
  const n = align.length;
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      const corner = (i === 0 && j === 0) || (i === 0 && j === n - 1) || (i === n - 1 && j === 0);
      if (!corner) drawAlignment(g, align[i], align[j]);
    }
  }
  drawFormatBits(g, ec, 0);   // reserves the areas; rewritten with the chosen mask later
  drawVersionBits(g, ver);
}

function drawCodewords(g: Grid, data: Uint8Array): void {
  const s = g.size;
  let i = 0;
  const total = data.length * 8;
  for (let right = s - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vert = 0; vert < s; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? s - 1 - vert : vert;
        if (!g.isFunction[y * s + x] && i < total) {
          g.modules[y * s + x] = (data[i >>> 3] >>> (7 - (i & 7))) & 1;
          i++;
        }
      }
    }
  }
}

function maskBit(mask: number, x: number, y: number): boolean {
  switch (mask) {
    case 0: return (x + y) % 2 === 0;
    case 1: return y % 2 === 0;
    case 2: return x % 3 === 0;
    case 3: return (x + y) % 3 === 0;
    case 4: return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
    case 5: return ((x * y) % 2) + ((x * y) % 3) === 0;
    case 6: return (((x * y) % 2) + ((x * y) % 3)) % 2 === 0;
    default: return (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
  }
}

function applyMask(g: Grid, mask: number): void {
  const s = g.size;
  for (let y = 0; y < s; y++) {
    for (let x = 0; x < s; x++) {
      if (!g.isFunction[y * s + x] && maskBit(mask, x, y)) g.modules[y * s + x] ^= 1;
    }
  }
}

function penalty(g: Grid): number {
  const s = g.size;
  let result = 0;
  const finderRun = (history: number[]): number => {
    const n = history[1];
    const core = n > 0 && history[2] === n && history[3] === n * 3 && history[4] === n && history[5] === n;
    return (core && history[0] >= n * 4 && history[6] >= n ? 1 : 0) + (core && history[6] >= n * 4 && history[0] >= n ? 1 : 0);
  };
  const scanLine = (get: (i: number) => number): number => {
    let p = 0;
    let runColor = 0, runLen = 0;
    const history = [0, 0, 0, 0, 0, 0, 0];
    const addRun = (len: number) => { history.pop(); history.unshift(len); };
    for (let i = 0; i < s; i++) {
      const c = get(i);
      if (c === runColor) {
        runLen++;
        if (runLen === 5) p += 3; else if (runLen > 5) p += 1;
      } else {
        addRun(runLen);
        if (runColor === 0) p += finderRun(history) * 40;
        runColor = c; runLen = 1;
      }
    }
    addRun(runLen);
    if (runColor === 1) { addRun(0); }
    p += finderRun(history) * 40;
    return p;
  };
  for (let y = 0; y < s; y++) result += scanLine((x) => g.get(x, y));
  for (let x = 0; x < s; x++) result += scanLine((y) => g.get(x, y));
  for (let y = 0; y < s - 1; y++) {
    for (let x = 0; x < s - 1; x++) {
      const c = g.get(x, y);
      if (c === g.get(x + 1, y) && c === g.get(x, y + 1) && c === g.get(x + 1, y + 1)) result += 3;
    }
  }
  let dark = 0;
  for (const m of g.modules) dark += m;
  const total = s * s;
  const k = Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1;
  return result + k * 10;
}

/** Encode `data` (a string, UTF-8, or raw bytes) in byte mode at the smallest version that fits. */
export function encodeQr(data: string | Uint8Array, opts: EncodeOptions = {}): QrMatrix {
  const ec = opts.ec ?? 'M';
  const minVersion = Math.max(1, opts.minVersion ?? 1);
  const maxVersion = Math.min(40, opts.maxVersion ?? 40);
  const bytes = typeof data === 'string' ? utf8Bytes(data) : data;

  let version = -1;
  for (let v = minVersion; v <= maxVersion; v++) {
    const needed = 4 + (v <= 9 ? 8 : 16) + bytes.length * 8;
    if (needed <= numDataCodewords(v, ec) * 8) { version = v; break; }
  }
  if (version < 0) throw new Error(`QR data too long: ${bytes.length} bytes do not fit versions ${minVersion}–${maxVersion} at EC ${ec}`);

  const size = 17 + 4 * version;
  const g = new Grid(size);
  drawFunctionPatterns(g, version, ec);
  drawCodewords(g, interleave(buildCodewords(bytes, version, ec), version, ec));

  let best = -1;
  let bestPenalty = Infinity;
  for (let m = 0; m < 8; m++) {
    applyMask(g, m);
    drawFormatBits(g, ec, m);
    const p = penalty(g);
    if (p < bestPenalty) { bestPenalty = p; best = m; }
    applyMask(g, m);   // XOR is its own inverse
  }
  applyMask(g, best);
  drawFormatBits(g, ec, best);
  return { version, size, ec, modules: g.modules, mask: best };
}

export interface SvgOptions {
  /** Quiet zone in modules; never below MIN_QUIET_ZONE. */
  quietZone?: number;
  dark?: string;
  light?: string;
}

/**
 * One-line SVG with a full light field (quiet zone included) and horizontal runs of dark
 * modules as a single path. Suitable for `data:image/svg+xml;utf8,` in expo-image.
 */
export function qrSvg(m: QrMatrix, opts: SvgOptions = {}): string {
  const quiet = Math.max(MIN_QUIET_ZONE, Math.floor(opts.quietZone ?? MIN_QUIET_ZONE));
  const dark = opts.dark ?? '#000000';
  const light = opts.light ?? '#FFFFFF';
  const total = m.size + 2 * quiet;
  let d = '';
  for (let y = 0; y < m.size; y++) {
    let x = 0;
    while (x < m.size) {
      if (m.modules[y * m.size + x] === 1) {
        let run = 1;
        while (x + run < m.size && m.modules[y * m.size + x + run] === 1) run++;
        d += `M${x + quiet} ${y + quiet}h${run}v1h-${run}z`;
        x += run;
      } else x++;
    }
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${total} ${total}" shape-rendering="crispEdges"><rect width="${total}" height="${total}" fill="${light}"/><path d="${d}" fill="${dark}"/></svg>`;
}

/** RGBA raster (opaque; black modules on white, quiet zone included) at `scale` pixels per module. */
export function qrToRgba(m: QrMatrix, scale: number, quietZone: number = MIN_QUIET_ZONE): { data: Uint8ClampedArray; width: number; height: number } {
  const quiet = Math.max(MIN_QUIET_ZONE, quietZone);
  const total = m.size + 2 * quiet;
  const width = total * scale;
  const data = new Uint8ClampedArray(width * width * 4);
  data.fill(255);
  for (let y = 0; y < m.size; y++) {
    for (let x = 0; x < m.size; x++) {
      if (m.modules[y * m.size + x] !== 1) continue;
      for (let py = 0; py < scale; py++) {
        const row = ((y + quiet) * scale + py) * width;
        for (let px = 0; px < scale; px++) {
          const i = (row + (x + quiet) * scale + px) * 4;
          data[i] = 0; data[i + 1] = 0; data[i + 2] = 0;
        }
      }
    }
  }
  return { data, width, height: width };
}
