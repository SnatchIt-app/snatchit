/**
 * css.ts — deterministic CSS-custom-property emitter for the brand tokens.
 *
 * tokens.css (committed at the package root) is generated from this module by
 * scripts/generate-css.ts; tests/css-drift.test.ts fails if the committed file
 * and this generator ever disagree. Web consumers import
 * `@snatchit/design-tokens/tokens.css`.
 *
 * RN `shadow` specs are translated to CSS box-shadow equivalents here — that
 * mapping is a web concern, so it lives in this package, not in the theme copy.
 */
import { colors, spacing, radius, fontSize, shadow } from './index.ts';

const kebab = (key: string): string =>
  key.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();

type RnShadow = {
  shadowColor: string;
  shadowOffset: { width: number; height: number };
  shadowOpacity: number;
  shadowRadius: number;
};

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '');
  const full = h.length === 3 ? h.split('').map((c) => c + c).join('') : h;
  return [
    parseInt(full.slice(0, 2), 16),
    parseInt(full.slice(2, 4), 16),
    parseInt(full.slice(4, 6), 16),
  ];
}

export function rnShadowToBoxShadow(s: RnShadow): string {
  const [r, g, b] = hexToRgb(s.shadowColor);
  const a = Math.round(s.shadowOpacity * 100) / 100;
  return `${s.shadowOffset.width}px ${s.shadowOffset.height}px ${s.shadowRadius}px rgba(${r}, ${g}, ${b}, ${a})`;
}

export function generateCss(): string {
  const lines: string[] = [
    '/* AUTO-GENERATED from @snatchit/design-tokens — do not edit by hand.',
    ' * Source of truth: mobile src/theme/index.ts (copied to src/index.ts).',
    ' * Regenerate: npm run generate (inside packages/design-tokens). */',
    ':root {',
  ];

  for (const [key, value] of Object.entries(colors)) {
    lines.push(`  --sn-color-${kebab(key)}: ${value};`);
  }
  for (const [key, value] of Object.entries(spacing)) {
    lines.push(`  --sn-space-${key}: ${value}px;`);
  }
  for (const [key, value] of Object.entries(radius)) {
    lines.push(`  --sn-radius-${key}: ${value}px;`);
  }
  for (const [key, value] of Object.entries(fontSize)) {
    lines.push(`  --sn-text-${key}: ${value}px;`);
  }
  for (const [key, value] of Object.entries(shadow)) {
    lines.push(`  --sn-shadow-${kebab(key)}: ${rnShadowToBoxShadow(value)};`);
  }

  lines.push('}');
  return lines.join('\n') + '\n';
}
