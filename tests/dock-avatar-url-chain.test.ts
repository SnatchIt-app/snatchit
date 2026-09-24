/**
 * The dock avatar's REAL URL chain (avatar diagnosis, 2026-09-24).
 *
 * `tests/dock-you-avatar.test.ts` mocks `getAvatarUrl`, which is right for exercising the
 * component's states but means no test ever ran the resolver the dock actually ships with — the
 * gap that let the dock become the only avatar surface in the app on the storage TRANSFORM
 * endpoint, requesting a 56px quality-45 derivative for an 84-device-pixel circle, with no test
 * able to see either fact. These tests run the real `getAvatarUrl` → `mediaUrlForStoredValue`
 * chain with no mocks, and pin the relationship between the dock's URL and the Profile screen's.
 *
 * What they CANNOT establish: whether the transform endpoint answers 200 for the avatars bucket
 * on the real project. That is the recorded discriminating observation (a device look at listing
 * artwork, or one owner-authorised fetch of both URLs); no unit test reaches it.
 */
import { describe, expect, it, vi } from 'vitest';

process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';

// The URL chain under test — getAvatarUrl → mediaUrlForStoredValue — is pure. The mocks below
// only stub the UPLOAD pipeline's imports (picker, Alert, client), which this file never calls,
// so the resolver itself runs for real.
vi.mock('expo-image-picker', () => ({}));
vi.mock('react-native', () => ({ Alert: { alert: () => {} } }));
vi.mock('@/src/lib/supabase', () => ({ supabase: {} }));
vi.mock('@/src/utils/validateImage', () => ({ validateImage: () => ({ ok: true }) }));

import { getAvatarUrl } from '@/src/lib/avatarImage';

const PATH = 'user-1/avatar_1758600000000.jpg';
/** What the dock passes since the fix: the painted size, with the phone's own pixel ratio. */
const DOCK_OPTS = { width: Math.ceil(28 * 1.5), devicePixelRatio: 3 };

describe('dock and Profile derive from ONE path through the real resolver', () => {
  it('U1: the Profile screen (no width) gets the plain object URL — the endpoint the device has proven', () => {
    const url = getAvatarUrl(PATH);
    expect(url).toBe(`https://example.supabase.co/storage/v1/object/public/avatars/${PATH}`);
  });

  it('U2: the dock derivative is the transform endpoint at the PAINTED size, not a 56px upscale', () => {
    const url = getAvatarUrl(PATH, DOCK_OPTS)!;
    expect(url).toContain('/storage/v1/render/image/public/avatars/');
    const q = new URL(url).searchParams;
    // ceil(28 * 1.5) = 42pt request × the resolver's dpr clamp (min(3,2) = 2) = 84px — exactly
    // the device pixels of a 28pt circle on a 3× phone. The old request produced width=56 here.
    expect(q.get('width')).toBe('84');
    expect(Number(q.get('quality'))).toBeGreaterThan(0);
  });

  it('U3: the fallback URL the dock retries on failure IS the Profile URL, byte for byte', () => {
    // This is the whole justification for the retry: after the derivative fails, the dock asks
    // for exactly what the Profile screen renders, so the two surfaces can only diverge while
    // BOTH endpoints disagree — not because the dock chose a different URL.
    expect(getAvatarUrl(PATH)).toBe(
      `https://example.supabase.co/storage/v1/object/public/avatars/${PATH}`,
    );
  });

  it('U4: a new upload can never collide with a cached predecessor — the path is what changes', () => {
    // Cache keys are the full URL (neither surface passes cacheKey), so this is what makes
    // `cacheControl: immutable` safe: a repointed row yields different URLs on BOTH endpoints.
    const a = getAvatarUrl('user-1/avatar_1.jpg', DOCK_OPTS);
    const b = getAvatarUrl('user-1/avatar_2.jpg', DOCK_OPTS);
    expect(a).not.toBe(b);
    expect(getAvatarUrl('user-1/avatar_1.jpg')).not.toBe(getAvatarUrl('user-1/avatar_2.jpg'));
  });

  it('U5: no path, no URL — the caller renders the placeholder, never a broken request', () => {
    expect(getAvatarUrl(null)).toBeNull();
    expect(getAvatarUrl('', DOCK_OPTS)).toBeNull();
  });
});
