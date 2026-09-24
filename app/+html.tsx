/**
 * app/+html.tsx — the HTML shell for the WEB target only.
 *
 * WHY IT EXISTS (owner 2026-09-24). The V3 corrections are compared against the approved boards
 * through Expo's web renderer, and the first comparison renders came out in the browser's default
 * serif. The cause is in `src/theme/fonts.ts`: on web, `fontFamily()` returns the canonical family
 * names 'Oswald' and 'Inter' because "the brand faces are loaded by the web app's own CSS font
 * pipeline" — that pipeline belongs to the Next.js app in `web/`, and the Expo web bundle has no
 * equivalent, so nothing ever declares those families and every screen falls back.
 *
 * NATIVE IS NOT AFFECTED, BEFORE OR AFTER. On iOS and Android the faces are registered by
 * `useFonts(BRAND_FONT_FACES)` from the bundled .ttf files, and `fontFamily()` returns the loaded
 * family names. This file is web-only output; React Native never evaluates it. It changes no
 * token, no resolver and no native configuration — it only gives the web document the same five
 * faces the native runtime already loads, so a web render is comparable typography rather than a
 * fallback face.
 *
 * SELF-HOSTED, NOT A CDN. The faces are the .ttf files already installed for the native bundle,
 * required through Metro so the dev server serves them. A render therefore does not depend on a
 * network font host being reachable, and two renders taken at different times use the same files.
 */
import { ScrollViewStyleReset } from 'expo-router/html';
import type { PropsWithChildren } from 'react';

import { font as brandFont } from '@/src/theme/v2';

/* eslint-disable @typescript-eslint/no-require-imports */
const FACES: { family: string; asset: unknown; weight: number }[] = [
  { family: brandFont.display, asset: require('@expo-google-fonts/oswald/700Bold/Oswald_700Bold.ttf'), weight: 700 },
  { family: brandFont.body, asset: require('@expo-google-fonts/inter/400Regular/Inter_400Regular.ttf'), weight: 400 },
  { family: brandFont.bodyMedium, asset: require('@expo-google-fonts/inter/500Medium/Inter_500Medium.ttf'), weight: 500 },
  { family: brandFont.bodySemi, asset: require('@expo-google-fonts/inter/600SemiBold/Inter_600SemiBold.ttf'), weight: 600 },
  { family: brandFont.bodyBold, asset: require('@expo-google-fonts/inter/700Bold/Inter_700Bold.ttf'), weight: 700 },
];
/* eslint-enable @typescript-eslint/no-require-imports */

/** Metro hands web either a URL string or an asset object carrying one. */
function assetUri(asset: unknown): string {
  if (typeof asset === 'string') return asset;
  const uri = (asset as { uri?: string; default?: string } | null)?.uri
    ?? (asset as { default?: string } | null)?.default;
  return typeof uri === 'string' ? uri : '';
}

/**
 * One @font-face per loaded face. `font-display: block` matters here: a render captured while a
 * face is still swapping would be measured against the board with the wrong metrics.
 */
const FONT_CSS = FACES.map(({ family, asset, weight }) => {
  const uri = assetUri(asset);
  return uri
    ? `@font-face{font-family:'${family}';src:url('${uri}') format('truetype');font-weight:${weight};font-style:normal;font-display:block;}`
    : '';
}).join('\n');

export default function Root({ children }: PropsWithChildren) {
  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta httpEquiv="X-UA-Compatible" content="IE=edge" />
        <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
        {/* Expo's own reset: makes body scrolling behave like a native ScrollView. */}
        <ScrollViewStyleReset />
        <style dangerouslySetInnerHTML={{ __html: FONT_CSS }} />
        {/* The canvas behind the React root, so a capture taken before first paint is not white
            in Dark. The app paints its own background immediately after. */}
        <style dangerouslySetInnerHTML={{ __html: 'body{background:#000;}' }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
