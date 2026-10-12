/**
 * src/components/NameText.tsx — the event/listing NAME, in the V3 display voice (owner 2026-09-22).
 *
 * Oswald_700Bold, MIXED CASE — the capitalisation the seller typed, nothing uppercased — via the
 * `name*` tokens (whose leading is provisional until the O-4 device measurement). One extra rule
 * the tokens cannot carry: a name that exceeds its line cap ends with `…` on a WORD boundary. React
 * Native's tail ellipsis cuts mid-word, so the first layout pass reports the rendered lines and the
 * component re-renders once with the text trimmed to the last full word that fits (§2, acceptance 3).
 */

import { useState } from 'react';
import { Text, type StyleProp, type TextStyle } from 'react-native';

import { textStyle } from '@/src/theme/typography';
import type * as v2 from '@/src/theme/v2';

export type NameToken = Extract<keyof typeof v2.type, `name${string}`>;

const ELLIPSIS = '…';

/**
 * Pure: given the full name and the lines the FIRST render actually produced, decide the display
 * string. Returns null when nothing was cut (render as-is). When the text overflows `maxLines`,
 * the visible text is trimmed back to its last whole word and `…` appended; if the cap's last line
 * holds no complete word, the ellipsis lands after whatever fits minus one character — cut is
 * unavoidable there, but it can never happen silently.
 */
export function trimToWordBoundary(
  fullText: string,
  renderedLines: string[],
  maxLines: number,
): string | null {
  if (renderedLines.length <= maxLines) return null;
  const visibleRaw = renderedLines.slice(0, maxLines).join('');
  const prefix = visibleRaw.trimEnd();
  // Did the cap land ON a word boundary? Either the raw visible text ends in whitespace, or the
  // next character of the full text starts a new word. Then every visible word is complete and the
  // freed whitespace holds the ellipsis. Otherwise the last (partial) word is dropped.
  const nextChar = fullText.slice(visibleRaw.length).charAt(0);
  const endsOnBoundary = /\s$/u.test(visibleRaw) || nextChar === '' || /\s/u.test(nextChar);
  let trimmed: string;
  if (endsOnBoundary) {
    trimmed = prefix;
  } else {
    const lastSpace = prefix.lastIndexOf(' ');
    trimmed = lastSpace > 0 ? prefix.slice(0, lastSpace) : prefix.slice(0, Math.max(1, prefix.length - 1));
  }
  return `${trimmed.replace(/[\s.,;:·—-]+$/u, '')}${ELLIPSIS}`;
}

export function NameText({
  children,
  token,
  maxLines = 2,
  style,
}: {
  children: string;
  token: NameToken;
  maxLines?: number;
  style?: StyleProp<TextStyle>;
}) {
  const [display, setDisplay] = useState<string | null>(null);

  return (
    <Text
      style={[textStyle(token), style]}
      numberOfLines={maxLines}
      onTextLayout={(e) => {
        if (display !== null) return;   // one corrective pass only
        const lines = e.nativeEvent.lines?.map((l) => l.text) ?? [];
        const trimmed = trimToWordBoundary(children, lines, maxLines);
        if (trimmed !== null) setDisplay(trimmed);
      }}
    >
      {display ?? children}
    </Text>
  );
}
