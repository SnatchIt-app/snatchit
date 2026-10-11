/**
 * tests/v3-wording-w4-w5.test.ts — the two decided items from the acceptance record (d5365925).
 *
 * W-4  The Settings hub adopts `SettingsHeader`, the component its ten sub-screens and the public
 *      profile already use, instead of hand-rolling the same back chip and title inline.
 *
 * W-5  Edit offers the same ticket platforms as Create, from ONE exported constant. Edit offered
 *      six and Create sixteen, so a listing created as e.g. StubHub could neither show nor keep
 *      its own platform in Edit. The database already agreed with Create: migration 033 widened
 *      `listings_ticket_platform_check` to the same sixteen values. The parity assertion below is
 *      against that constraint, parsed from the migration, so the app cannot drift from the column
 *      it writes to — and no platform is invented here that the database would reject.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { TICKET_PLATFORMS } from '@/src/lib/listing/ticketPlatforms';

/** Source with comments removed: these rules are about what a file DOES, not what it says. */
const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

/** The values inside `listings_ticket_platform_check` as migration 033 defines it. */
function platformsFromMigration(): string[] {
  const sql = readFileSync('supabase/migrations/033_marketplace_expansion.sql', 'utf8');
  const body = sql.split('ADD CONSTRAINT listings_ticket_platform_check')[1] ?? '';
  const inList = body.slice(body.indexOf('('), body.indexOf(')'));
  return [...inList.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
}

describe('W-5: one ticket-platform list, shared by Create and Edit', () => {
  it('WP1: the shared constant matches migration 033 exactly — no extra, none missing', () => {
    const dbValues = platformsFromMigration();
    expect(dbValues.length, 'the migration should list sixteen platforms').toBe(16);
    expect([...TICKET_PLATFORMS.map((p) => p.value)].sort()).toEqual([...dbValues].sort());
  });

  it('WP2: every platform carries a human label, and no value repeats', () => {
    for (const p of TICKET_PLATFORMS) {
      expect(p.label.trim(), `${p.value} needs a label`).not.toBe('');
      expect(p.label).not.toBe(p.value);
    }
    const values = TICKET_PLATFORMS.map((p) => p.value);
    expect(new Set(values).size).toBe(values.length);
  });

  it('WP3: Create and Edit both read the shared constant and declare no list of their own', () => {
    for (const rel of ['src/screens/CreateListingScreen.tsx', 'app/listing/edit/[id].tsx']) {
      const src = strip(rel);
      expect(src, `${rel} should import the shared list`).toContain('ticketPlatforms');
      expect(src, `${rel} must not keep a second list`).not.toMatch(/const TICKET_PLATFORMS\s*(:|=)/);
    }
  });

  it('WP4: "Other" stays last, so the real platforms are not buried behind it', () => {
    expect(TICKET_PLATFORMS[TICKET_PLATFORMS.length - 1].value).toBe('other');
  });
});

describe('W-4 follow-on: the shared header does not clip its own title at large text', () => {
  it('WH3: SettingsHeader lets the title wrap above the shared threshold, and keeps one line below', async () => {
    /*
     * Found by capturing W-4 rather than by reading it. At A3XL the hub reads "SETTIN…",
     * Appearance reads "APPEA…" — and so does privacy.tsx, which used SettingsHeader long before
     * this batch. So the clip is the shared header's, across all eleven screens; what W-4 did was
     * extend it to two screens whose sentence-case titles used to wrap. Same rule as everywhere
     * else in this batch: above the threshold the words win, below it nothing moves.
     */
    const src = strip('src/components/account/SettingsHeader.tsx');
    expect(src).toContain('identityStacks');
    // One line always; above the threshold it shrinks to fit. Wrapping was tried first and the
    // capture showed "SETTING / S" — a single word cannot break on a space, so it must not break.
    expect(src).toMatch(/numberOfLines=\{1\}/);
    expect(src).toContain('adjustsFontSizeToFit: true');
    expect(src).toContain('minimumFontScale: AMOUNT_MIN_FONT_SCALE');
  });
});

describe('W-4: the Settings hub wears the same header as everything it leads to', () => {
  it('WH1: the hub uses SettingsHeader and no longer hand-rolls the chip and title', () => {
    const hub = strip('app/settings/index.tsx');
    expect(hub).toContain('<SettingsHeader');
    expect(hub, 'the inline title should be gone').not.toMatch(/accessibilityRole="header"/);
    expect(hub, 'the inline back chip should be gone').not.toMatch(/glyph="back"\s+chip/);
  });

  it('WH2: EVERY settings screen shares that one header — enumerated, not listed by hand', async () => {
    /*
     * The acceptance record says ten sub-screens already used SettingsHeader. Nine did:
     * appearance.tsx hand-rolled the identical chip and title, and verify-phone.tsx is an
     * eleventh screen the count missed. Reading the directory rather than a hand-kept list is
     * what makes a NEW settings screen with its own header fail here instead of shipping.
     */
    const { readdirSync } = await import('node:fs');
    const screens = readdirSync('app/settings').filter((f) => f.endsWith('.tsx'));
    expect(screens.length, 'the settings directory should not be empty').toBeGreaterThan(8);
    for (const f of screens) {
      // `<SettingsHeader`, not the bare name: an unused import would otherwise satisfy this,
      // which is exactly what a mutant that removed the element but kept the import revealed.
      expect(strip(`app/settings/${f}`), `${f} should RENDER SettingsHeader`).toContain('<SettingsHeader');
    }
  });
});
