/**
 * Regenerates ../tokens.css from src/css.ts.
 * Run from packages/design-tokens: `node scripts/generate-css.ts`
 * (Node ≥ 23.6 runs TypeScript directly via type stripping.)
 */
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { generateCss } from '../src/css.ts';

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'tokens.css');
writeFileSync(out, generateCss());
console.log(`wrote ${out}`);
