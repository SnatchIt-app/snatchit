/**
 * A requirement a field imposes must be readable, and must survive the first keystroke
 * (owner 2026-09-24: "use readable colours for required-field prompts and status text… give the
 * code input a persistent visible label if reachable").
 *
 * `text.faint` composites to 2.39–2.67:1 in every appearance, below the 4.5:1 bar, and a
 * `placeholder` disappears the moment the user types. That combination is fine for a decorative
 * example under a visible label; it is not fine when the placeholder is the ONLY statement of a
 * rule the user has to satisfy, or the only name the field has.
 *
 * Three sites were doing exactly that:
 *   · the push-challenge code input — no visible label at all, only `placeholder="6-digit code"`,
 *     whose accessibilityLabel ("Verification code") does not even repeat the format
 *   · signup's password — "At least 6 characters" stated once, in the placeholder, and gone
 *     precisely while the user is trying to satisfy it
 *   · the sell form's four unfilled pickers — the prompt sits in the value slot at 2.4:1
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const read = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('required-field prompts are persistent and readable', () => {
  it('FP1: the push-challenge code input has a persistent visible label, not only a placeholder', () => {
    const src = read('app/settings/notifications.tsx');
    // A <Text> label above the field, at an ink that clears the text bar in both appearances.
    expect(src).toMatch(/codeLabel/);
    expect(src).toMatch(/codeLabel: \{ color: p\.text\.muted/);
    expect(src).toMatch(/<Text style=\{\[textStyle\('micro'\), s\.codeLabel\]\}>Verification code<\/Text>/);
    // The field keeps its accessible name and its format placeholder; the label is additional.
    expect(src).toContain('accessibilityLabel="Verification code"');
    expect(src).toContain('placeholder="6-digit code"');
  });

  it('FP2: the password rule is a persistent helper, not a vanishing placeholder', () => {
    const src = read('app/(auth)/signup.tsx');
    // Input renders `helper` under the field at text.muted and also feeds it to accessibilityHint.
    expect(src).toMatch(/helper="At least 6 characters"/);
    expect(src).not.toMatch(/placeholder="At least 6 characters"/);
    const input = read('src/components/ui/Input.tsx');
    expect(input).toMatch(/helper: \{ color: p\.text\.muted/);
    expect(input).toMatch(/accessibilityHint=\{error \?\? helper\}/);
  });

  it('FP3: an unfilled picker states its prompt at a readable ink', () => {
    // "Select area or venue", "Pick a date", "Pick a time", "Select platform" — each the only
    // statement of what the required field wants, sitting in the value slot.
    const src = read('src/screens/CreateListingScreen.tsx');
    expect(src).toMatch(/selectPlaceholder: \{ color: p\.text\.muted/);
  });

  it('FP4: the two switches agree on their thumb — a control keeps its identity across appearances', () => {
    // Not a contrast failure: every state clears 3:1 either way. It is one control rendering as two
    // different controls — white knob on the sell form, near-black knob in notifications, in Light.
    for (const rel of ['app/settings/notifications.tsx', 'src/screens/CreateListingScreen.tsx']) {
      expect(read(rel), rel).toMatch(/thumbColor=\{palette\.onArt\.primary\}/);
    }
  });
});
