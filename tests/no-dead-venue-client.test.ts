/**
 * The consumer app has no venue client (D's contract trace EL-08, 2026-11-02; ADVERSARIAL_REVIEW J-3/J-4).
 *
 * src/lib/venue/{client,types}.ts were never imported. They spoke a status vocabulary the server does not
 * have ('published', 'postponed'; venue.order 'expired') and claimed command-key idempotency it does not
 * give. The buyer's only server surface is the public reads (182), the 167 hold and the primary-checkout
 * edge. This pins that the dead module stays gone and that nothing reaches for a venue client again.
 *
 * Negative control (run by hand, must FAIL): restore either file, or add an import of '@/src/lib/venue/…'.
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

function sources(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    if (name === 'node_modules') continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) sources(full, out);
    else if (/\.tsx?$/.test(full)) out.push(full);
  }
  return out;
}

describe('no consumer venue client (EL-08)', () => {
  it('V1: src/lib/venue does not exist', () => {
    expect(existsSync('src/lib/venue/client.ts')).toBe(false);
    expect(existsSync('src/lib/venue/types.ts')).toBe(false);
  });

  it('V2: no app or src module imports a venue client', () => {
    const offenders = [...sources('src'), ...sources('app')].filter((f) => /from\s+['"](@\/src\/lib\/venue|[./]+\/venue\/(client|types))['"/]/.test(readFileSync(f, 'utf8')));
    expect(offenders).toEqual([]);
  });
});
