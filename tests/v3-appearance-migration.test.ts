/**
 * The appearance migration, asserted over the WHOLE consumer surface rather than an exception
 * list (owner 2026-09-24: "'Light-appearance exception' must not become permission to build a
 * knowingly incomplete light mode. The authorised candidate includes complete System/Light/Dark
 * support.").
 *
 * AM1 scans every tracked file under `app/` and `src/` for a STATIC colour-token access —
 * `v2.text.*`, `v2.surface.*`, `v2.border.*`, `v2.status.*`, `v2.brand.*`, `v2.chrome.*` — with
 * comments stripped first, since a comment naming a token changes no pixel. A static access is
 * the defect: it renders the Midnight value under every appearance. Spacing, radius, typography
 * and artwork constants are NOT colour and are left alone.
 *
 * Two paths are exempt, and AM2 pins that the exempt set is exactly those two so a new
 * exemption cannot be added quietly:
 *   - `src/theme/palette.ts` builds both palettes FROM the tokens; that is the definition.
 *   - `app/_dev/**` is unreachable in a consumer build (route guards, no navigation entry) and
 *     the foundation screen's whole purpose is to display the raw tokens.
 *
 * AM3 pins the one deliberate set of hard-coded colours that must NOT follow the appearance:
 * the environment-pairing blocker and the sandbox badge. Those are build-safety diagnostics,
 * fixed so they read identically whatever the phone or the stored choice says.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';

import { describe, expect, it } from 'vitest';

const ROOT = path.resolve(__dirname, '..');
const COLOUR_ACCESS = /\bv2\.(?:text|surface|border|status|brand|chrome)\./g;
const EXEMPT = ['src/theme/palette.ts', 'app/_dev/'];

function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/(?<![:\w])\/\/[^\n'"`]*$/gm, '');
}

function trackedSources(): string[] {
  return execFileSync('git', ['ls-files', 'app', 'src'], { cwd: ROOT, encoding: 'utf8' })
    .split('\n')
    .filter((f) => f.endsWith('.ts') || f.endsWith('.tsx'));
}

function staticColourAccesses(): { file: string; count: number }[] {
  const out: { file: string; count: number }[] = [];
  for (const file of trackedSources()) {
    const src = stripComments(readFileSync(path.join(ROOT, file), 'utf8'));
    const count = src.match(COLOUR_ACCESS)?.length ?? 0;
    if (count > 0) out.push({ file, count });
  }
  return out.sort((a, b) => b.count - a.count);
}

const isExempt = (file: string) => EXEMPT.some((e) => file === e || file.startsWith(e));

describe('complete appearance migration', () => {
  it('AM1: no consumer file reads a colour token statically — every colour comes from the resolved palette', () => {
    const remaining = staticColourAccesses().filter((r) => !isExempt(r.file));
    // The failure message IS the work list: file and how many colour reads are left in it.
    expect(remaining.map((r) => `${r.file} (${r.count})`)).toEqual([]);
  });

  it('AM2: the only exempt paths are the palette definition and the dev-only screens', () => {
    expect(EXEMPT).toEqual(['src/theme/palette.ts', 'app/_dev/']);
    const exemptWithAccesses = staticColourAccesses().filter((r) => isExempt(r.file)).map((r) => r.file);
    // Both exempt paths genuinely hold static reads; neither is a placeholder kept "just in case".
    expect(exemptWithAccesses).toContain('src/theme/palette.ts');
    expect(exemptWithAccesses.every(isExempt)).toBe(true);
  });

  it('AM4: no reachable consumer surface still draws from the LEGACY dark-only theme', () => {
    // The v2-token scan cannot see this class of defect: three transfer-flow components were
    // never converted to v2 at all and still read `colors` from `@/src/theme` — the pre-v2
    // palette (#0B0F14 cards, #E10600 red), which has no light counterpart and would paint dark
    // cards onto a white canvas. Spacing and type from that module are fine; only `colors` is.
    const offenders: string[] = [];
    for (const file of trackedSources()) {
      if (file.startsWith('src/theme/') || file === 'src/constants/theme.ts') continue;
      const src = stripComments(readFileSync(path.join(ROOT, file), 'utf8'));
      const imports = src.match(/import\s*\{[^}]*\}\s*from\s*'@\/src\/theme'/g) ?? [];
      if (imports.some((i) => /\bcolors\b/.test(i))) offenders.push(file);
    }
    expect(offenders).toEqual([]);
  });

  it('AM3: the env-pairing blocker and the sandbox badge keep fixed colours — a build-safety warning does not follow the appearance', () => {
    const src = readFileSync(path.join(ROOT, 'app/_layout.tsx'), 'utf8');
    for (const literal of ['#1a0000', '#FF1A1A', '#ffb3b3', '#7a3b00', '#ffd9a0']) {
      expect(src).toContain(literal);
    }
    // …and nothing else in the root layout is hard-coded: the splash reads the palette.
    expect(stripComments(src).match(COLOUR_ACCESS) ?? []).toEqual([]);
  });

  /**
   * AM5 classifies every colour LITERAL outside the theme definitions, one by one (owner
   * 2026-09-24: "Literal colours are individually classified; artwork-specific colours remain
   * where appropriate"). A literal is legitimate only for a reason that survives changing
   * appearance; the reason is written next to it here, and an unclassified literal fails.
   */
  it('AM5: every colour literal outside the theme definitions is individually classified', () => {
    const CLASSIFIED: Record<string, { literals: string[]; reason: string }> = {
      'app/_layout.tsx': {
        literals: ['#1a0000', '#FF1A1A', '#fff', '#ffb3b3', '#7a3b00', '#ffd9a0'],
        reason:
          'Build-safety diagnostics: the env-pairing blocker and the SANDBOX badge must read the ' +
          'same whatever the phone or the stored choice says, and the blocker can fire before any ' +
          'preference is known.',
      },
      'src/components/ErrorBoundary.tsx': {
        literals: ['#111', '#fff', '#999', '#E63946'],
        reason:
          'The crash screen. It renders because the tree below it threw — possibly the appearance ' +
          'provider itself — so it cannot depend on a hook or a loaded preference.',
      },
      'src/components/ProofImageViewer.tsx': {
        literals: ['#000', 'rgba(255,255,255,0.15)', '#fff'],
        reason:
          'A full-screen image lightbox: its chrome sits on the photograph, not on the app canvas, ' +
          'so it is artwork-specific and identical in both appearances.',
      },
      'src/components/TransferStatusBadge.tsx': {
        literals: [
          'rgba(251,191,36,0.15)', '#fbbf24', 'rgba(96,165,250,0.15)', '#60a5fa',
          'rgba(74,222,128,0.15)', '#4ade80', 'rgba(255,77,109,0.15)', '#ff4d6d',
          'rgba(138,148,166,0.15)', '#8a94a6',
        ],
        reason: 'Not referenced by any screen — asserted below — so it renders no surface in the build.',
      },
      'app/(tabs)/profile.tsx': {
        literals: ['rgba(0,0,0,0.55)'],
        reason: 'Scrim over the avatar photograph (artwork), not over a themed surface.',
      },
      'app/settings/edit-profile.tsx': {
        literals: ['rgba(0,0,0,0.55)'],
        reason: 'Scrim over the avatar photograph (artwork), not over a themed surface.',
      },
      'src/components/ui/IconButton.tsx': {
        literals: ['rgba(0,0,0,0.55)'],
        reason: 'The onArt variant: a scrim so an icon stays legible over a photograph.',
      },
      'src/components/ui/MediaUpload.tsx': {
        literals: ['rgba(0,0,0,0.55)'],
        reason: 'Scrim over the uploaded image while it is replaced.',
      },
      'src/components/PlatformInstructions.tsx': {
        literals: ['rgba(251,191,36,0.10)'],
        reason:
          'A 10% warning tint. Being translucent it composites over whichever canvas is behind it, ' +
          'so one value is correct in both appearances; its border and text come from status.warning.',
      },
    };

    const found = new Map<string, Set<string>>();
    const LITERAL = /'(#[0-9a-fA-F]{3,8}|rgba?\([^')]*\))'/g;
    for (const file of trackedSources()) {
      if (file.startsWith('src/theme/')) continue; // the definitions themselves
      const src = stripComments(readFileSync(path.join(ROOT, file), 'utf8'));
      for (const m of src.matchAll(LITERAL)) {
        if (!found.has(file)) found.set(file, new Set());
        found.get(file)!.add(m[1]);
      }
    }

    // Every file that holds a literal is classified, with exactly the literals it holds.
    const actual = Object.fromEntries([...found].map(([f, s]) => [f, [...s].sort()]));
    const expected = Object.fromEntries(
      Object.entries(CLASSIFIED).map(([f, c]) => [f, [...new Set(c.literals)].sort()]),
    );
    expect(actual).toEqual(expected);
    // No classification is a placeholder: each carries a written reason.
    for (const [file, c] of Object.entries(CLASSIFIED)) {
      expect(c.reason.length, `${file} needs a reason`).toBeGreaterThan(40);
    }
    // The one reason that is a claim about the codebase, checked rather than asserted.
    const importers = trackedSources().filter(
      (f) => f !== 'src/components/TransferStatusBadge.tsx'
        && /TransferStatusBadge/.test(readFileSync(path.join(ROOT, f), 'utf8')),
    );
    expect(importers).toEqual([]);
  });
});
