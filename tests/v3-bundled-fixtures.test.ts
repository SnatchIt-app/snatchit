/**
 * tests/v3-bundled-fixtures.test.ts — the bundled test posters cannot reach the product.
 *
 * WHY THESE EXIST AT ALL. The 4:5 poster direction makes promises that only real pixels can check —
 * the whole poster is visible, a non-4:5 source is fitted not cropped, nothing is stretched, our own
 * text never lands on the flyer's printed text. There are no real pixels available: every `qa/*.jpg`
 * path the older harness referenced is absent from the sandbox bucket, and putting artwork there is
 * a storage write nobody authorised. So six generated posters are compiled into the app and a
 * fixture asks for one by putting `dev-bundled:<name>` in the same cover field a real row uses.
 *
 * WHY THAT IS SAFE, asserted rather than asserted-in-a-comment. The media layer's host check
 * (`isTrustedMediaUrl`) exists because a cover value is DATA — it arrives on a row and must not be
 * able to point the renderer at an arbitrary host. This suite pins the two properties that keep the
 * bundled branch from becoming a way around it:
 *
 *   1. it is gated on `__DEV__`, so a release bundle cannot take the branch however the marker
 *      arrives — a structural guarantee, not a convention;
 *   2. nothing outside `app/_dev` mentions it, so no product screen can hand it a value.
 *
 * And the host check itself is untouched: a marker is not a URL, so it never reaches the gate, and
 * the gate still refuses everything it refused before.
 */

import { describe, expect, it } from 'vitest';

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { DEV_POSTER_NAMES, devPosterModule } from '../src/lib/media/devPosters';
import { ADDITIONAL_TRUSTED_MEDIA_HOSTS, isTrustedMediaUrl } from '../src/lib/media/url';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

/** Every .ts/.tsx under app/ and src/, with the file's path relative to the repo root. */
function sourceFiles(): string[] {
  const out: string[] = [];
  const walk = (dir: string) => {
    for (const e of readdirSync(resolve(root, dir))) {
      const rel = join(dir, e);
      if (statSync(resolve(root, rel)).isDirectory()) walk(rel);
      else if (/\.tsx?$/.test(e)) out.push(rel);
    }
  };
  walk('app');
  walk('src');
  return out;
}

describe('the bundled posters are a dev-only affordance', () => {
  it('BF1: the lookup returns null when __DEV__ is not set — and the GATE is why', () => {
    /*
     * The assertion E asked for, behavioural rather than a source pin. A release bundle has
     * `__DEV__ === false`; this suite runs with it undefined, and both take the same branch.
     */
    for (const name of DEV_POSTER_NAMES) {
      expect(devPosterModule(`dev-bundled:${name}`), name).toBeNull();
    }
    // And a non-marker value is null for its own reason, in both worlds.
    expect(devPosterModule('uuid/covers/1715000000000.jpg')).toBeNull();
    expect(devPosterModule(null)).toBeNull();

    /*
     * POSITIVE CONTROL, because a null that is always null proves nothing about the gate. With the
     * gate opened, control flow reaches the `require` and the behaviour DIFFERS — under vitest it
     * throws, because vitest cannot transform a PNG (Metro can, which is why the app is fine). The
     * throw is an artefact of this environment; what it establishes is that the gate, and not some
     * unrelated early return, is what produced the nulls above.
     */
    const g = globalThis as Record<string, unknown>;
    try {
      g.__DEV__ = true;
      expect(() => devPosterModule('dev-bundled:markers-4x5')).toThrow();
    } finally {
      delete g.__DEV__;
    }
    // Back to the closed gate, so the difference is the flag and nothing else.
    expect(devPosterModule('dev-bundled:markers-4x5')).toBeNull();

    // The gate is also FIRST in the source, so a later edit cannot read the value before checking.
    const src = read('src/lib/media/devPosters.ts');
    expect(src).toMatch(/if \(typeof __DEV__ === 'undefined' \|\| !__DEV__\) return null;/);
    const fn = src.slice(src.indexOf('export function devPosterModule'));
    expect(src).toContain('export function devPosterModule');
    expect(fn.indexOf('__DEV__')).toBeLessThan(fn.indexOf('DEV_POSTER_PREFIX'));
  });

  it('BF2: no screen outside app/_dev mentions the bundled mechanism', () => {
    const ALLOWED = ['src/lib/media/devPosters.ts', 'src/lib/media/url.ts'];
    const offenders = sourceFiles().filter((f) => {
      if (f.startsWith(join('app', '_dev')) || ALLOWED.includes(f)) return false;
      return /devPoster|dev-bundled|DEV_POSTER/.test(read(f));
    });
    expect(offenders).toEqual([]);

    // POSITIVE CONTROL: the scan must be able to see the mechanism where it legitimately lives, or
    // an empty offender list would only prove the walk found nothing.
    const harnessUses = sourceFiles().filter(
      (f) => f.startsWith(join('app', '_dev')) && /devPosterPath/.test(read(f)),
    );
    expect(harnessUses.length).toBeGreaterThan(0);
  });

  it('BF3: the host check is unchanged — a marker never reaches it, and it still refuses what it did', () => {
    // The bundled branch is NOT an entry in the trusted-host list. That list is still empty, which
    // is the property that keeps "where will this app fetch an image from" a review decision.
    expect(ADDITIONAL_TRUSTED_MEDIA_HOSTS).toEqual([]);
    // A marker is not a URL, so it is not a host decision at all.
    expect(isTrustedMediaUrl('dev-bundled:markers-4x5')).toBe(false);
    // And the refusals that matter still refuse.
    expect(isTrustedMediaUrl('http://evil.example/x.png')).toBe(false);
    expect(isTrustedMediaUrl('https://evil.example/x.png')).toBe(false);
  });

  it('BF4: the fixtures carry no third-party marks, and the shapes under test are all present', () => {
    const src = read('src/lib/media/devPosters.ts');
    // The shapes the direction has to survive: the target, a taller source, the legacy landscape
    // crop, a square, a dense flyer, and a photograph.
    for (const name of [
      'markers-4x5', 'markers-9x16', 'markers-16x9', 'markers-1x1', 'flyer-dense-4x5', 'photo-3x2',
      // Subject framing, so a review can judge the SUBJECT and not only the edges.
      'photo-subject-4x5', 'photo-subject-16x9',
    ]) {
      expect(src).toContain(`'${name}'`);
    }
    /*
     * The two lists must not drift: this one is written out so a fixture that is added to the module
     * without a deliberate look here fails, and DEV_POSTER_NAMES is what the budget below sums. A
     * file sitting in the directory but missing from the module would otherwise be invisible to both
     * the budget and the harness — which is exactly what had happened before this was registered.
     */
    expect(DEV_POSTER_NAMES).toHaveLength(8);
    // Every named shape exists on disk, and the set stays small: these files ship INSIDE the binary
    // (Expo Router registers every app/ route statically, so a dev route's assets are bundled even
    // though the route itself redirects in production).
    let bytes = 0;
    for (const name of DEV_POSTER_NAMES) {
      const st = statSync(resolve(root, `assets/qa-posters/${name}.png`));
      expect(st.size, `${name}.png exists`).toBeGreaterThan(0);
      bytes += st.size;
    }
    // A budget, not a measurement: flat-colour plates compress small, and if one is ever replaced
    // with a photograph this fails rather than quietly adding megabytes to every release.
    expect(bytes).toBeLessThan(400 * 1024);
    // The pixels cannot be grepped, so the file that documents what is drawn on them is pinned:
    // the flyer's domain and address must stay a placeholder and a fiction.
    expect(src).toMatch(/EXAMPLE\.COM/);
    expect(src).toMatch(/NOWHERE AVE/);
  });
});
