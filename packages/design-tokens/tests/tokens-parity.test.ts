/**
 * Parity + drift guards for @snatchit/design-tokens:
 *  1. Token values must equal the mobile theme (src/theme/index.ts) exactly.
 *  2. The committed tokens.css must equal the generator output (no hand edits).
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import * as tokens from '../src/index';
import { generateCss, rnShadowToBoxShadow } from '../src/css';
import * as mobileTheme from '@mobile/src/theme/index';

describe('token parity with mobile theme', () => {
  it('colors match', () => expect(tokens.colors).toStrictEqual(mobileTheme.colors));
  it('spacing matches', () => expect(tokens.spacing).toStrictEqual(mobileTheme.spacing));
  it('radius matches', () => expect(tokens.radius).toStrictEqual(mobileTheme.radius));
  it('fontSize matches', () => expect(tokens.fontSize).toStrictEqual(mobileTheme.fontSize));
  it('shadow matches', () => expect(tokens.shadow).toStrictEqual(mobileTheme.shadow));
});

describe('css generation', () => {
  it('committed tokens.css matches generator output (run npm run generate after token changes)', () => {
    const committed = readFileSync(join(__dirname, '..', 'tokens.css'), 'utf8');
    expect(committed).toBe(generateCss());
  });

  it('emits brand-critical variables', () => {
    const css = generateCss();
    expect(css).toContain('--sn-color-bg: #0B0F14;');
    expect(css).toContain('--sn-color-primary: #E10600;');
    expect(css).toContain('--sn-space-md: 16px;');
    expect(css).toContain('--sn-radius-md: 10px;');
  });

  it('translates RN shadows to CSS box-shadows', () => {
    expect(rnShadowToBoxShadow(tokens.shadow.card)).toBe('0px 4px 8px rgba(0, 0, 0, 0.3)');
    expect(rnShadowToBoxShadow(tokens.shadow.modal)).toBe('0px -4px 12px rgba(0, 0, 0, 0.4)');
  });
});
