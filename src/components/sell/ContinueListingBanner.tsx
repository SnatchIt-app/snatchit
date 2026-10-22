/**
 * src/components/sell/ContinueListingBanner.tsx — "Continue your listing" (CFT-608, item 36).
 *
 * Shown on the Sell tab only, above the form, when this account has a draft saved on the device.
 * It says what is kept, where (this device — nothing has reached a server), and which photos the
 * seller still has to add. Two actions: Continue restores the fields; Discard asks first, because
 * a discarded draft cannot be brought back. The copy lives in src/lib/sell/listingDraft.ts.
 *
 * The form stays editable under the banner, and nothing autosaves while the offer is undecided. So
 * the seller's first input (`formHasInput`) asks at once — start a new listing (the saved one is
 * deleted, and the form autosaves from then on) or continue the saved one — and Continue over input
 * already in the form asks before replacing it (review LD-R3).
 */

import { useEffect, useMemo, useRef } from 'react';
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
  /** The form already holds the seller's input (useListingDraft's `formHasInput`). */
  formHasInput?: boolean;
  onContinue: () => void;
  /** Called only after the seller confirms. */
  onDiscard: () => void;
}

export function ContinueListingBanner({ offer, formHasInput = false, onContinue, onDiscard }: ContinueListingBannerProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const copy = LISTING_DRAFT_COPY;
  const body = draftBannerBody(offer);
  const askedStartNew = useRef(false);

  // It appears after the screen has rendered (the draft is read from storage), so a screen-reader
  // user is told once. VoiceOver is told here; on Android the banner's polite live region speaks it,
  // and announcing as well would say it twice (review m2).
  useEffect(() => {
    if (Platform.OS === 'ios') AccessibilityInfo.announceForAccessibility(`${copy.title}. ${body}`);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // The seller started typing (or had typed before the offer arrived): ask once, and make it a choice —
  // not dismissable — so autosave never sits paused under a banner that may have scrolled away.
  useEffect(() => {
    if (!formHasInput || askedStartNew.current) return;
    askedStartNew.current = true;
    if (Platform.OS === 'web') {
      if (window.confirm(`${copy.startNewTitle}\n\n${copy.startNewBody}\n\n${copy.startNewWebHint}`)) onDiscard();
      else onContinue();
      return;
    }
    Alert.alert(copy.startNewTitle, copy.startNewBody, [
      { text: copy.continueSaved, onPress: onContinue },
      { text: copy.startNew, style: 'destructive', onPress: onDiscard },
    ], { cancelable: false });
  }, [formHasInput]); // eslint-disable-line react-hooks/exhaustive-deps

  function askContinue() {
    if (!formHasInput) { onContinue(); return; }
    if (Platform.OS === 'web') {
      if (window.confirm(`${copy.replaceTitle}\n\n${copy.replaceBody}`)) onContinue();
      return;
    }
    Alert.alert(copy.replaceTitle, copy.replaceBody, [
      { text: copy.replaceCancel, style: 'cancel' },
      { text: copy.replace, style: 'destructive', onPress: onContinue },
    ]);
  }

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
    <View style={s.wrap} accessibilityLiveRegion="polite">
      <Text style={[textStyle('title'), s.title]} accessibilityRole="header">{copy.title}</Text>
      <Text style={[textStyle('bodySm'), s.body]}>{body}</Text>
      <Text style={[textStyle('bodySm'), s.note]}>{draftPhotosNote(offer)}</Text>
      <View style={s.actions}>
        <Button label={copy.continue} onPress={askContinue} />
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
