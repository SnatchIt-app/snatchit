/**
 * app/_dev/v3-account.tsx — the V3 ACCOUNT rendering harness (owner 2026-09-24).
 *
 * WHY IT EXISTS. Same reason as `app/_dev/v3-screens.tsx`, which this copies: the V3 corrections
 * have to be compared against the approved boards as the ACTUAL APP RENDERS THEM, and the account
 * surfaces sit behind authentication (and Settings' deletion tri-state behind a kernel probe that
 * cannot be steered from a client). The owner authorised "safe local rendering fixtures for
 * otherwise unreachable visual states" and required the real application components rather than a
 * recreated mock, so this route mounts the REAL Profile / Settings / Appearance screens with
 * literals supplied in place of their reads. The auth screens need no case here: the root gate
 * already renders them signed out, exactly as shipped.
 *
 * WHAT A RENDER HERE PROVES, AND WHAT IT DOES NOT. It proves what the component paints from the
 * given props: composition, spacing, type, colour roles, shapes, wrapping, both appearances. It
 * proves nothing about the data path that normally supplies those props, nothing about native
 * iOS rendering, and nothing about behaviour that needs a server.
 *
 * NO SESSION IS FABRICATED. The fixtures are display literals (a profile row's fields, counts, a
 * deletion view); nothing here creates, mimics or stores an auth session, and every action on the
 * mounted screens still goes through the real (absent) session and fails closed.
 *
 * NOT REACHABLE IN PRODUCTION. Like the other `_dev` routes, the segment layout gates the whole
 * group and this file redirects on its own too: a production binary cannot show it through
 * navigation or a deep link.
 *
 * NO WRITES. Nothing here reads or writes a server. The fixtures are literals in this file.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { useAppearancePreference } from '@/src/theme/appearance';
import ProfileScreen, { type ProfileFixture } from '@/app/(tabs)/profile';
import SettingsScreen, { type SettingsDeletionFixture } from '@/app/settings/index';
import AppearanceScreen from '@/app/settings/appearance';

declare const __DEV__: boolean;

/**
 * A bundled data-uri avatar for the with-avatar case (a neutral placeholder figure, generated for
 * this harness — sample content, not production data, and no network fetch behind it).
 */
const AVATAR_DATA_URI =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAABDUlEQVR42u2Y3Q3CMAyE2xPTIPHGHCAxKBJMyABASfxDzs3lsVLP99lWG3s9ns5L5YOl+BGAAAQgAAHMDXBI0r1cb+8Pn497eKA19irx0XcqSRhAo/VwDIxyb34ruAIhJjylwHD3Tp2J/wNR6XeqgcG9R3PKFspIv1lZl7lyAHn9Y9NXCwlAAAIoBpAx13r01UIVAfK6yKA8awtlFMGmiSGrhEC1ub9CUUXw6MSsFs1Dgj8FGJhC7UbdLRQ4XpqrYQRImoz/9Cem2gv1VSB7JWEoBQjdd8UCofuuiOB03x4XtO4bo4PZfYsHkLv/6WS/12me9G/72WkF2NK/4UqLLUIAzv755k0tJAABFD8vMbpVXbScRJUAAAAASUVORK5CYII=';

/**
 * The board's own profile (`pkg8-account-tickets-{dark,light}.png`, PROFILE · own): "Jo",
 * masked +1 (***) ***-1234, Verified buyer, Active 2 / Sold 7, Proceeds unknown — the board's
 * "—" is deliberate: unknown is not zero, so the fixture's revenue is 0 and the screen must
 * print the em dash. Sample content only (owner: "Sample event names, prices, photographs and
 * dates are not production data").
 */
const PROFILE_BASE: ProfileFixture = {
  profile: {
    id: 'fixture-profile',
    display_name: 'Jo',
    phone_number: '3055551234',
    avatar_url: null,
    avatar_path: null,
    is_verified_buyer: true,
    is_verified_seller: false,
    wallet_balance: 0,
    stripe_connect_id: null,
  },
  stats: { active: 2, sold: 7, revenue: 0 },
  payoutStatus: 'not_connected',
  avatarUri: null,
};

function profileFixtureFor(variant: string | undefined): ProfileFixture {
  switch (variant) {
    case 'noavatar':
      return PROFILE_BASE;
    default:
      // The board's own-profile panel draws a photo in the ring.
      return { ...PROFILE_BASE, avatarUri: AVATAR_DATA_URI };
  }
}

function settingsFixtureFor(variant: string | undefined): SettingsDeletionFixture {
  switch (variant) {
    case 'pending': return 'pending';           // the withdraw banner (SETTINGS · deletion pending)
    case 'probe-failed': return 'probe_failed'; // "We could not check your account status." + Retry
    default: return 'active';                   // the plain hub
  }
}

export default function V3AccountHarness() {
  const { screen, variant, appearance } = useLocalSearchParams<{
    screen?: string; variant?: string; appearance?: string;
  }>();
  // `?appearance=light|dark|system` drives the comparison capture deterministically from the
  // app's own preference — the same one Settings writes — rather than from a browser emulation
  // flag. For `screen=appearance` it is also the case under test: the Appearance screen reads
  // the same store, so each preference value renders with its own radio selected.
  const { setPreference } = useAppearancePreference();
  useEffect(() => {
    if (appearance === 'light' || appearance === 'dark' || appearance === 'system') {
      setPreference(appearance);
    }
  }, [appearance]);

  // Stable per variant: a fixture identity that changed every render would re-run screen effects.
  const profileFixture = useMemo(() => profileFixtureFor(variant), [variant]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  switch (screen) {
    case 'profile':
      return <ProfileScreen fixture={profileFixture} />;
    case 'settings':
      return <SettingsScreen deletionFixture={settingsFixtureFor(variant)} />;
    case 'appearance':
      // No fixture: the screen has no read to short-circuit. `?appearance=` selects the radio.
      return <AppearanceScreen />;
    default:
      return <Redirect href="/" />;
  }
}
