import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Light-appearance contrast guard. Reads the design tokens straight from
 * globals.css so a later edit cannot quietly break WCAG AA on the white
 * surfaces. Text tokens need 4.5:1, non-text UI (borders, fills, focus) 3:1.
 */
const css = readFileSync(resolve(__dirname, "../src/app/globals.css"), "utf8");

function token(name: string): string {
  const m = css.match(new RegExp(`--color-${name}:\\s*([^;]+);`));
  if (!m) throw new Error(`token --color-${name} missing`);
  return m[1].trim();
}

function rgb(value: string, over: [number, number, number] = [255, 255, 255]): [number, number, number] {
  const hex = value.match(/^#([0-9a-f]{6})$/i);
  if (hex) return [0, 2, 4].map((i) => parseInt(hex[1].slice(i, i + 2), 16)) as [number, number, number];
  const fn = value.match(/^rgba?\(([^)]+)\)$/i);
  if (!fn) throw new Error(`unsupported colour ${value}`);
  const [r, g, b, a = 1] = fn[1].split(",").map((x) => Number(x.trim()));
  return [r, g, b].map((c, i) => Math.round(c * a + over[i] * (1 - a))) as [number, number, number];
}

function luminance([r, g, b]: [number, number, number]): number {
  const lin = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

function contrast(fg: string, bg: string): number {
  const b = rgb(bg);
  const f = rgb(fg, b);
  const [hi, lo] = [luminance(f), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

describe("light appearance tokens", () => {
  it("uses white primary surfaces and a light colour scheme", () => {
    for (const t of ["bg", "card", "field"]) expect(token(t).toLowerCase()).toBe("#ffffff");
    expect(css).toMatch(/color-scheme:\s*light/);
  });

  it.each(["ink", "muted", "dim", "placeholder", "primary-ink", "success", "warning", "danger", "info"])(
    "text token %s reads at >= 4.5:1 on white and on the raised gray",
    (t) => {
      expect(contrast(token(t), token("bg"))).toBeGreaterThanOrEqual(4.5);
      expect(contrast(token(t), token("raised"))).toBeGreaterThanOrEqual(4.5);
    },
  );

  it("brand red stays >= 3:1 as a fill/border/focus colour and black-on-red CTAs stay >= 4.5:1", () => {
    expect(contrast(token("primary"), token("bg"))).toBeGreaterThanOrEqual(3);
    expect(contrast("#000000", token("primary"))).toBeGreaterThanOrEqual(4.5);
  });

  it("status colours stay >= 3:1 as borders on white", () => {
    for (const t of ["success", "warning", "danger", "info"]) expect(contrast(token(t), token("bg"))).toBeGreaterThanOrEqual(3);
  });

  it("raised gray is distinguishable from white but never a dark surface", () => {
    const r = luminance(rgb(token("raised")));
    expect(r).toBeLessThan(1);
    expect(r).toBeGreaterThan(0.85);
  });
});
