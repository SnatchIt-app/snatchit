/**
 * src/components/sell/ContinueListingBanner.tsx — "Continue your listing" (CFT-608, item 36).
 *
 * Shown on the Sell tab only, above the form, when this account has a draft saved on the device.
 * It says what is kept, where (this device — nothing has reached a server), and which photos the
 * seller still has to add. Two actions: Continue restores the fields; Discard asks first, because
 * a discarded draft cannot be brought back. The copy lives in src/lib/sell/listingDraft.ts.
 */

import { useEffect, useMemo } from 'react';
import { AccessibilityInfo, Alert, Platform, StyleSheet, Text, View } from 'react-native';

import { Button } from '@/src/components/ui';
import {
  draftBannerBody,
  draftPhotosNote,
  LISTING_DRAFT_COPY,
  type ListingDraftOffer,
} from '@/src/lib/sell/listingDraft';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface ContinueListingBannerProps {
  offer: ListingDraftOffer;
  onContinue: () => void;
  /** Called only after the seller confirms. */
  onDiscard: () => void;
}

export function ContinueListingBanner({ offer, onContinue, onDiscard }: ContinueListingBannerProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const copy = LISTING_DRAFT_COPY;
  const body = draftBannerBody(offer);

  // It appears after the screen has rendered (the draft is read from storage), so a screen-reader
  // user is told once, as the security notice does.
  useEffect(() => {
    AccessibilityInfo.announceForAccessibility(`${copy.title}. ${body}`);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  function askDiscard() {
    if (Platform.OS === 'web') {
      if (window.confirm(`${copy.confirmTitle}\n\n${copy.confirmBody}`)) onDiscard();
      return;
    }
    Alert.alert(copy.confirmTitle, copy.confirmBody, [
      { text: copy.confirmKeep, style: 'cancel' },
      { text: copy.confirmDiscard, style: 'destructive', onPress: onDiscard },
    ]);
  }

  return (
    <View style={s.wrap}>
      <Text style={[textStyle('title'), s.title]} accessibilityRole="header">{copy.title}</Text>
      <Text style={[textStyle('bodySm'), s.body]}>{body}</Text>
      <Text style={[textStyle('bodySm'), s.note]}>{draftPhotosNote(offer)}</Text>
      <View style={s.actions}>
        <Button label={copy.continue} onPress={onContinue} />
        <Button label={copy.discard} variant="secondary" onPress={askDiscard} />
      </View>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    wrap: {
      marginTop: v2.space.lg,
      padding: v2.space.md,
      gap: v2.space.xs,
      borderWidth: 1,
      borderColor: p.border.default,
      borderRadius: v2.radius.md,
      backgroundColor: p.surface.elevated,
    },
    title: { color: p.text.primary },
    body: { color: p.text.secondary },
    note: { color: p.text.muted },
    actions: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.sm, marginTop: v2.space.sm },
  });
}
