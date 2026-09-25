/**
 * src/lib/media/devPosters.ts — bundled test posters, for visual review only.
 *
 * WHY THIS EXISTS. The 4:5 poster direction makes four promises that a screenshot of the fallback
 * plate cannot check: the whole poster is visible, a non-4:5 source is fitted rather than cropped,
 * nothing is stretched, and our own text never lands on the flyer's printed text. Checking any of
 * them needs real pixels in the real frames — and there are none to be had. Every `qa/*.jpg` path
 * the older harness referenced is absent from the sandbox bucket (each returns `NoSuchKey`, while a
 * bogus bucket returns `NoSuchBucket`, so the check discriminates), and putting artwork there is a
 * storage write nobody has authorised.
 *
 * So the fixtures are compiled into the app instead, and a fixture row asks for one by setting its
 * cover to `dev-bundled:<name>`. Nothing else changes: the marker travels through the same row
 * field, the same screens and the same slots as a real cover, which is the point — a fixture that
 * took a different code path would prove something about the fixture.
 *
 * THE TWO THINGS THAT KEEP THIS OUT OF THE PRODUCT.
 *  1. `__DEV__`. The lookup consults nothing at all in a release bundle, so it cannot render one of
 *     these however the marker arrives. That is structural, not a convention.
 *  2. The images carry no real marks. They are generated flat-colour plates: the flyer's domain is
 *     EXAMPLE.COM, its address is "000 NOWHERE AVE, FICTIONAL CITY", and both say SYNTHETIC on
 *     their face. No third-party brand, venue, promoter or artwork is reproduced.
 *
 * WHY EVERYTHING IS LOADED LAZILY. `src/lib/media/url.ts` is a pure module that a lot of suites
 * import directly, and the first version of this file imported `react-native` and `require()`d six
 * PNGs at module scope. That pulled React Native's Flow source and a binary asset into every one of
 * those suites, which could not parse either. The requires now happen inside the function, behind
 * the `__DEV__` gate, so a test importing the resolver loads nothing from here — and production
 * loads nothing either.
 *
 * WHAT A RENDER WITH THESE PROVES: the client-side frame, fit, background, plate and over-art
 * contrast. NOT the storage transform — a bundled asset has no transform endpoint, so the request
 * shape is covered by `tests/v3-poster-ratio.test.ts` instead.
 *
 * THE MARKER SET is built so a crop is a finding rather than a judgement call: L-brackets flush to
 * all four corners, ten ticks touching each edge (40 in total, countable), and a true circle with a
 * crosshair — an ellipse means something scaled non-uniformly. If a bracket is missing from a
 * render, that frame cropped, and which bracket is gone says which edge lost.
 *
 * Total added to the binary: ~132 KB for six files.
 */

declare const __DEV__: boolean | undefined;

/** The marker a fixture row puts in its cover field. */
export const DEV_POSTER_PREFIX = 'dev-bundled:';

/**
 * The shapes under test, named rather than derived from the require table, so this list can be read
 * without loading any of the assets.
 */
export const DEV_POSTER_NAMES = [
  'markers-4x5',
  'markers-9x16',
  'markers-16x9',
  'markers-1x1',
  'flyer-dense-4x5',
  'photo-3x2',
] as const;

export type DevPosterName = (typeof DEV_POSTER_NAMES)[number];

/** The cover value a fixture uses to ask for one of these. */
export function devPosterPath(name: DevPosterName): string {
  return `${DEV_POSTER_PREFIX}${name}`;
}

/**
 * What `require()` of an image gives back. Deliberately opaque, and that is the point.
 *
 * TWO WRONG TURNS, recorded because both looked right. First this file called
 * `Image.resolveAssetSource` to turn the module into a uri — react-native-web does not implement
 * that function at all, so every screen rendering a fixture fell into the error boundary and the
 * Home harness redirected to /login, which made a rendering bug look like an auth problem. Then it
 * tried to read a uri off the module directly, which produced nothing on web.
 *
 * The form that works is the one the app already uses for its own bundled artwork
 * (`AuthBrandMark`, `HomeHeader`): hand the required module STRAIGHT to expo-image as its `source`
 * and let it do the platform-specific resolution. So nothing here converts anything.
 */
type BundledAsset = number | string | object;

/*
 * A literal `require` per asset, because Metro resolves these statically — a path built from a
 * variable silently resolves to nothing. Called only from inside the gate below.
 */
function bundledModule(name: string): BundledAsset | null {
  switch (name) {
    case 'markers-4x5': return require('../../../assets/qa-posters/markers-4x5.png');
    case 'markers-9x16': return require('../../../assets/qa-posters/markers-9x16.png');
    case 'markers-16x9': return require('../../../assets/qa-posters/markers-16x9.png');
    case 'markers-1x1': return require('../../../assets/qa-posters/markers-1x1.png');
    case 'flyer-dense-4x5': return require('../../../assets/qa-posters/flyer-dense-4x5.png');
    case 'photo-3x2': return require('../../../assets/qa-posters/photo-3x2.png');
    default: return null;
  }
}

/**
 * The bundled module for a marker, ready to hand to expo-image as a `source` — or null for anything
 * else, which includes every real stored value and includes a marker in a production bundle.
 */
export function devPosterModule(raw: string | null | undefined): BundledAsset | null {
  if (typeof __DEV__ === 'undefined' || !__DEV__) return null;
  if (!raw || !raw.startsWith(DEV_POSTER_PREFIX)) return null;
  return bundledModule(raw.slice(DEV_POSTER_PREFIX.length));
}
