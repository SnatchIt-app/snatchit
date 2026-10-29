/**
 * src/lib/qr/qrLayout.ts — how big to draw the admission code, and at which error-correction level.
 *
 * C-R2 (E, 2026-10-26): module pitch must not fall below 3 pt. The code is drawn at the preferred
 * 320 pt when there is room, else at the space given. If EC M would put modules under 3 pt, the
 * same token is re-encoded at EC L (fewer modules for the same bytes). If even L cannot reach the
 * floor, the result says `belowMinimum` — the caller still draws the code (it is the only one
 * there is), and the evidence records the case. The quiet zone is never shrunk to make room.
 *
 * Pitch counts the quiet zone: pitch = size ÷ (modules + 2 × MIN_QUIET_ZONE), because the SVG's
 * viewBox includes it.
 */
import { MIN_QUIET_ZONE, encodeQr, type EcLevel, type QrMatrix } from './qrEncode';

export const MIN_MODULE_PITCH_PT = 3;
export const PREFERRED_QR_PT = 320;

export interface QrRender {
  matrix: QrMatrix;
  ec: EcLevel;
  /** Points, square, quiet zone included. */
  size: number;
  /** Points per module. */
  pitch: number;
  belowMinimum: boolean;
}

function render(token: string, ec: EcLevel, size: number): QrRender | null {
  let matrix: QrMatrix;
  try {
    matrix = encodeQr(token, { ec });
  } catch {
    return null;
  }
  const pitch = size / (matrix.size + 2 * MIN_QUIET_ZONE);
  return { matrix, ec, size, pitch, belowMinimum: pitch < MIN_MODULE_PITCH_PT };
}

/** `available` = the width the screen can give the code, in points. */
export function chooseQrRender(token: string, available: number): QrRender | null {
  const size = Math.max(0, Math.floor(Math.min(PREFERRED_QR_PT, available)));
  const m = render(token, 'M', size);
  if (m && !m.belowMinimum) return m;
  const l = render(token, 'L', size);
  if (l) return l;
  return m;
}
