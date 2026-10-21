/**
 * src/components/listing/SaveControl.tsx — the Save listing toggle and its rollback note.
 *
 * PROP-DRIVEN ON PURPOSE. Nothing here reads data, a store or a hook of its own beyond the theme: the
 * screen owns `useSavedListing` and hands the result down, so the hero that draws this control stays a
 * pure layout component, and a test that mounts the hero under a narrow '@/src/components/ui' mock
 * (FromAFanBadge + IconButton) keeps working. IconButton is the only primitive used.
 *
 * The mark is a bookmark, filled when saved — the same mark web draws — at the 44pt chip size of the
 * back and overflow controls beside it. The spoken name stays "Save listing" and the on/off state is
 * reported as `selected`, the pattern Chip already uses for a toggle. The note under it is web's own
 * sentence for the failed direction; the screen announces it once, so the text here only needs the
 * alert role for a screen reader that lands on it later.
 */

import { useMemo } from 'react';
import { StyleSheet, Text } from 'react-native';

import { IconButton } from '@/src/components/ui';
import { SAVED_COPY } from '@/src/lib/saved/savedState';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface SaveControlProps {
  saved: boolean;
  onToggle: () => void;
}

export function SaveControl({ saved, onToggle }: SaveControlProps) {
  return (
    <IconButton
      glyph="bookmark"
      selected={saved}
      accessibilityLabel={SAVED_COPY.controlLabel}
      onPress={onToggle}
    />
  );
}

/** The short rollback note, shown under the navigation row until the next tap. */
export function SaveNote({ text }: { text: string }) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  return (
    <Text style={[textStyle('bodySm'), styles.note]} accessibilityRole="alert">
      {text}
    </Text>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  // Right-aligned under the chips it belongs to; the error ink every rollback notice uses.
  note: {
    color: p.status.error,
    textAlign: 'right',
    paddingHorizontal: v2.space.md,
    paddingBottom: v2.space.sm,
  },
  });
}
