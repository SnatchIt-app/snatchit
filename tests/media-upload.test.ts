/**
 * tests/media-upload.test.ts — the V2 upload control + its migration.
 *
 * MediaUpload is effect-heavy (image picker), so its states and the migration off
 * the legacy dashed-box/emoji tile are guarded from the shipped source: both
 * variants, empty/selected/uploading, replace + remove, the compact "Image added"
 * confirmation, no emoji, IconSymbol icons, and that Create + Transfer no longer
 * use the old tile.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

const media = read('src/components/ui/MediaUpload.tsx');
const create = read('src/screens/CreateListingScreen.tsx');
const transferSend = read('app/transfer/send/[id].tsx');

// Pictographic emoji only — the upload glyphs (🖼️ 🎟️ 📸) live here. Deliberately
// excludes dingbats like the ✓ checkbox glyph, which is legitimate UI, not emoji.
const EMOJI = /[\u{1F300}-\u{1FAFF}]/u;

describe('MediaUpload — the new upload control', () => {
  it('offers both a cover and a compact variant', () => {
    expect(media).toMatch(/variant:\s*'cover'\s*\|\s*'compact'/);
    expect(media).toContain("variant === 'cover'");
  });

  it('uses design-system icons, never emoji', () => {
    expect(media).toContain('IconSymbol');
    expect(media).not.toMatch(EMOJI);
    // it is built on V2 tokens, not the legacy theme
    expect(media).not.toMatch(/from '@\/src\/theme'\b/);
    expect(media).toMatch(/from '@\/src\/theme\/v2'/);
  });

  it('has empty, preview, uploading, replace and remove affordances', () => {
    expect(media).toContain('hasImage');
    expect(media).toContain('uploading');
    expect(media).toContain('Replace');
    expect(media).toContain('Remove');
    expect(media).toContain('onRemove');
    expect(media).toContain('Spinner'); // uploading state
  });

  it('the compact variant confirms a selected file without a giant canvas', () => {
    expect(media).toContain("'Image added'");
    expect(media).toContain('thumb'); // small thumbnail, not a full media box
    // no fixed 180/140 tall empty placeholder
    expect(media).not.toMatch(/height:\s*180|height:\s*140/);
  });
});

describe('Create Listing — migrated to MediaUpload', () => {
  it('uses MediaUpload for cover (media) and proof (compact), not the legacy tile', () => {
    expect(create).toContain('variant="cover"');
    expect(create).toContain('variant="compact"');
    expect(create).not.toContain('ImageUploadTile');
  });

  it('wires remove to the uploader reset and carries no emoji', () => {
    expect(create).toContain('onRemove={coverUpload.reset}');
    expect(create).toContain('onRemove={proofUpload.reset}');
    // the picture-frame and ticket emoji are gone
    expect(create).not.toMatch(EMOJI);
  });

  it('preserves the upload wiring (pick + the useImageUpload buckets are untouched)', () => {
    expect(create).toContain('coverUpload.pickImage');
    expect(create).toContain('proofUpload.pickImage');
    expect(create).toContain("bucket: 'proof-docs'"); // proof still the private bucket
  });
});

describe('Transfer send — migrated to MediaUpload', () => {
  it('uses the compact MediaUpload and drops the legacy tile', () => {
    expect(transferSend).toContain('variant="compact"');
    expect(transferSend).not.toContain('ImageUploadTile');
    expect(transferSend).not.toMatch(EMOJI);
    // the evidence path is unchanged
    expect(transferSend).toContain('evidenceUpload.pickImage');
    expect(transferSend).toContain('evidenceUpload.uploadImage');
  });
});
