/**
 * C-R2 (E, 2026-10-26): a floor on module pitch. The admission code must not fall under 3 pt per
 * module on a narrow phone. `chooseQrRender` keeps EC M when it fits at ≥ 3 pt/module, drops to
 * EC L (fewer modules, same data) when M would not, and reports `belowMinimum` when even L cannot
 * reach the floor in the space given — it never shrinks the quiet zone to make room.
 *
 * Token sizes: B's contract — the compact token, ~349 chars today (v14–15 at EC M); 600–800 bytes
 * is E's stress case.
 */
import { describe, expect, it } from 'vitest';

import { MIN_MODULE_PITCH_PT, PREFERRED_QR_PT, chooseQrRender } from '@/src/lib/qr/qrLayout';
import { MIN_QUIET_ZONE } from '@/src/lib/qr/qrEncode';

/** The layout result, or a failed test — never a silent null. */
function must<T>(x: T | null): T {
  if (x === null) throw new Error('chooseQrRender returned null');
  return x;
}

const token = (n: number) => 'A'.repeat(Math.floor(n * 0.3)) + '.' + 'B'.repeat(Math.floor(n * 0.45)) + '.' + 'C'.repeat(n - Math.floor(n * 0.3) - Math.floor(n * 0.45) - 2);

describe('chooseQrRender', () => {
  it('Q1: today’s ~349-char token keeps EC M and ≥ 3.5 pt/module even on a 311 pt space (smallest supported phone)', () => {
    const r = must(chooseQrRender(token(349), 311));
    expect(r.ec).toBe('M');
    expect(r.size).toBe(311);
    expect(r.pitch).toBeGreaterThanOrEqual(3.5);
    expect(r.belowMinimum).toBe(false);
  });

  it('Q2: on a large phone the code caps at the preferred size, not the full width', () => {
    const r = must(chooseQrRender(token(349), 400));
    expect(r.size).toBe(PREFERRED_QR_PT);
  });

  it('Q3: a 700-byte token that would fall under 3 pt/module at EC M drops to EC L on a narrow phone', () => {
    const m = must(chooseQrRender(token(700), 311));
    expect(m.ec).toBe('L');
    expect(m.pitch).toBeGreaterThanOrEqual(MIN_MODULE_PITCH_PT);
    expect(m.belowMinimum).toBe(false);
  });

  it('Q4: when even EC L cannot reach the floor, it says so instead of pretending', () => {
    const r = must(chooseQrRender(token(1400), 311));
    expect(r.belowMinimum).toBe(true);
    expect(r.size).toBe(311);
  });

  it('Q5: pitch counts the quiet zone — size ÷ (modules + 2 × quiet zone)', () => {
    const r = must(chooseQrRender(token(349), 311));
    expect(r.pitch).toBeCloseTo(r.size / (r.matrix.size + 2 * MIN_QUIET_ZONE), 6);
  });

  it('Q6: an unencodable token returns null so the screen shows the pinned unavailable copy', () => {
    expect(chooseQrRender('x'.repeat(5000), 311)).toBeNull();
  });
});
