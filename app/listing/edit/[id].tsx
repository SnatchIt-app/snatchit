/**
 * app/listing/edit/[id].tsx — Edit a listing (V2).
 *
 * PRESENTATION rebuilt on the V2 system, reusing Create's section/Input/Chip
 * language; the edit path is unchanged. Scope is still the safe metadata subset
 * (event_name, venue, restrictions, ticket_platform), gated on
 * bid_count === 0 && auction_status === 'active' with the same load guards
 * (not found / not owner / has bids or inactive → back). The content-moderation
 * gate now reuses Create's `findBannedContent` from src/lib/sell/sellState.ts.
 * Server-side `guard_listing_state_columns` + RLS remain the hard wall.
 *
 * PREMIUM BATCH 2 (CFT-203/208). Save reads "Saving…" while in flight, and a
 * back gesture with unsaved edits asks before discarding them.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, TextInput, View, type TextStyle } from 'react-native';
import { useTopInset } from '@/src/lib/nav/navInsets';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useUnsavedChangesGuard } from '@/src/hooks/useUnsavedChangesGuard';
import { shouldAskBeforeLeaving, UNSAVED_COPY } from '@/src/lib/nav/unsavedChanges';
import { editPhase, editRefusal, editRefusalCopy, type EditRefusal } from '@/src/lib/listing/editAccess';
import { exitRoute } from '@/src/lib/nav/leaveScreen';
import { findBannedContent } from '@/src/lib/sell/sellState';
import { Button, Chip, EmptyState, IconButton, Input, Spinner, StickyBar } from '@/src/components/ui';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { Listing, TicketPlatform } from '@/src/types';

const TICKET_PLATFORMS: { value: TicketPlatform; label: string }[] = [
  { value: 'dice',         label: 'DICE' },
  { value: 'eventbrite',   label: 'Eventbrite' },
  { value: 'posh',         label: 'Posh' },
  { value: 'axs',          label: 'AXS' },
  { value: 'ticketmaster', label: 'Ticketmaster' },
  { value: 'other',        label: 'Other' },
];

/**
 * The dev harness's seed (`app/_dev/v3-edit-listing.tsx`). It stands in for the READ and nothing
 * else: the viewer still comes from `useAuth()`, which no prop may replace — v3-listing's rule —
 * so the signed-out refusal is not seedable here and keeps its behavioural coverage instead. Save
 * short-circuits under a fixture, so a harness render cannot write a listing.
 */
export interface EditListingFixture {
  /** The row the read would have returned; null stands for a row-less answer. */
  row: Listing | null;
  /** The read error's own sentence, when the read failed. */
  readError?: string | null;
}

export default function EditListingScreen({ fixture }: { fixture?: EditListingFixture } = {}) {
  const { user, loading: authLoading } = useAuth();
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const topPad = useTopInset();
  const params = useLocalSearchParams<{ id: string }>();
  // Under a fixture the row carries its own id; the live route is unchanged.
  const listingId = params.id ?? fixture?.row?.id ?? '';

  const [loading, setLoading] = useState(true);
  const [refused, setRefused] = useState<EditRefusal | null>(null);
  const [saving, setSaving] = useState(false);
  const [listing, setListing] = useState<Listing | null>(null);

  const [eventName, setEventName] = useState('');
  const [venue, setVenue] = useState('');
  const [restrictions, setRestrictions] = useState('');
  const [ticketPlatform, setTicketPlatform] = useState<TicketPlatform>('other');
  const [restrictionsFocused, setRestrictionsFocused] = useState(false);
  const [saved, setSaved] = useState(false);

  // Unsaved edits: anything that differs from the loaded listing (CFT-208).
  const dirty = listing != null && (
    eventName !== (listing.event_name ?? '')
    || venue !== (listing.venue ?? '')
    || restrictions !== (listing.restrictions ?? '')
    || ticketPlatform !== ((listing.ticket_platform as TicketPlatform) ?? 'other')
  );
  useUnsavedChangesGuard({
    when: shouldAskBeforeLeaving({ dirty, submitting: saving, saved }),
    ...UNSAVED_COPY.listingEdit,
  });

  /*
   * The exit a refusal offers. `router.back()` on its own is a dead control from a deep link or a
   * cold start — there is nothing underneath — so it falls back to the board this screen is opened
   * from. Both the alert's OK and the refusal's action call this, so they cannot drift apart.
   */
  function leave(): void {
    const exit = exitRoute(router.canGoBack(), '/my-listings');
    if (exit.kind === 'back') router.back();
    else router.replace(exit.href as never);
  }

  useEffect(() => {
    let cancelled = false;
    /*
     * Every exit from here either shows the form or records a refusal (E, 2026-10-05). Two of
     * these paths used to return with `loading` still set, and the render guard read a missing
     * listing as "still loading", so the seller was left on a spinner behind the alert — and with
     * the alert dismissed by the hardware back button, on a spinner and nothing else.
     */
    function refuse(r: EditRefusal, alert: boolean): void {
      setRefused(r);
      setLoading(false);
      if (alert) Alert.alert(r.title, r.body, [{ text: 'OK', onPress: leave }]);
    }
    async function load() {
      if (authLoading) return;                       // the session is still being checked
      if (!user || !listingId) {
        // No alert: nothing was asked for yet, so the refusal is the screen, not an interruption.
        refuse(editRefusalCopy(user ? 'not-found' : 'signed-out'), false);
        return;
      }
      const { data, error } = fixture
        ? { data: fixture.row, error: fixture.readError ? { message: fixture.readError } : null }
        : await supabase.from('listings').select('*').eq('id', listingId).single();
      if (cancelled) return;
      const l = (data ?? null) as Listing | null;
      const refusal = editRefusal({ listing: l, viewerId: user.id, readError: error?.message });
      // `!l` is already the 'not-found' refusal; it stays in the condition so the rest of this
      // function keeps its non-null listing rather than asserting one.
      if (refusal || !l) {
        refuse(refusal ?? editRefusalCopy('not-found', error?.message), true);
        return;
      }
      setListing(l);
      setEventName(l.event_name ?? '');
      setVenue(l.venue ?? '');
      setRestrictions(l.restrictions ?? '');
      setTicketPlatform((l.ticket_platform as TicketPlatform) ?? 'other');
      setLoading(false);
    }
    load();
    return () => { cancelled = true; };
  }, [listingId, user, authLoading, fixture]);

  async function handleSave() {
    // A harness render is a picture of the screen, not a seat at the keyboard: the update below
    // writes a real row, so it never runs under a fixture.
    if (fixture) return;
    if (!listing || !user) return;
    if (!eventName.trim() || !venue.trim()) {
      Alert.alert('Missing fields', 'Event name and venue are required.');
      return;
    }
    const banned = findBannedContent([eventName, venue, restrictions]);
    if (banned) {
      Alert.alert('Listing not allowed', `Listings can't mention "${banned}". Please revise and try again.`);
      return;
    }
    setSaving(true);
    try {
      const { error } = await supabase
        .from('listings')
        .update({
          event_name: eventName.trim(),
          venue: venue.trim(),
          restrictions: restrictions.trim() || null,
          ticket_platform: ticketPlatform,
        })
        .eq('id', listing.id)
        .eq('seller_id', user.id);
      if (error) { Alert.alert('Save failed', error.message); return; }
      setSaved(true); // the guard stands down; the alert's OK navigates back
      Alert.alert('Saved', 'Your listing has been updated.', [{ text: 'OK', onPress: () => router.back() }]);
    } finally {
      setSaving(false);
    }
  }

  const phase = editPhase({ authLoading, loading, refusal: refused, listing });
  if (phase === 'refused' && refused) {
    return (
      <View style={[s.root, s.center]}>
        <EmptyState
          title={refused.title}
          body={refused.body}
          action={{ label: 'Back', onPress: leave }}
        />
      </View>
    );
  }
  if (phase === 'loading' || !listing) {
    return <View style={[s.root, s.center]}><Spinner color={palette.brand.red} /></View>;
  }

  return (
    <KeyboardAvoidingView style={s.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={[s.header, { paddingTop: topPad + v2.space.sm }]}>
        <IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('displaySm'), s.headerTitle]} accessibilityRole="header">Edit listing</Text>
        <View style={s.headerSpacer} />
      </View>

      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag" showsVerticalScrollIndicator={false}>
        <Text style={[textStyle('bodySm'), s.helper]}>
          You can edit details until the first bid arrives. After that, use Cancel from My Listings if you need to remove it.
        </Text>

        <Input label="Event name" placeholder="e.g. Weekend pool party" value={eventName} onChangeText={setEventName} returnKeyType="next" />
        <Input label="Venue" placeholder="e.g. LIV Miami" value={venue} onChangeText={setVenue} returnKeyType="next" containerStyle={s.gap} />

        <Text style={[textStyle('micro'), s.groupLabel]}>Ticket platform</Text>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.chipRow} keyboardShouldPersistTaps="handled">
          {TICKET_PLATFORMS.map(({ value, label }) => (
            <Chip key={value} label={label} selected={ticketPlatform === value} onPress={() => setTicketPlatform(value)} />
          ))}
        </ScrollView>

        <Text style={[textStyle('micro'), s.groupLabel]}>Restrictions (optional)</Text>
        <TextInput
          style={[
            textStyle('body') as TextStyle,
            s.multiline,
            { borderBottomColor: restrictionsFocused ? palette.brand.red : palette.border.strong },
          ]}
          value={restrictions}
          onChangeText={setRestrictions}
          onFocus={() => setRestrictionsFocused(true)}
          onBlur={() => setRestrictionsFocused(false)}
          placeholder="e.g. 21+, no re-entry, dress code"
          placeholderTextColor={palette.text.faint}
          selectionColor={palette.brand.red}
          multiline
          numberOfLines={3}
          maxLength={500}
          accessibilityLabel="Restrictions"
        />
      </ScrollView>

      <StickyBar>
        <Button label="Save changes" pendingLabel="Saving…" onPress={handleSave} loading={saving} disabled={saving} block />
      </StickyBar>
    </KeyboardAvoidingView>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },
  center: { alignItems: 'center', justifyContent: 'center' },

  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: v2.space.md, paddingBottom: v2.space.sm,
    borderBottomWidth: 1, borderBottomColor: p.border.default,
  },
  headerTitle: { color: p.text.primary },
  headerSpacer: { width: 44 },

  body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, paddingBottom: v2.space.xxl },
  helper: { color: p.text.muted, marginBottom: v2.space.xl },
  gap: { marginTop: v2.space.lg },
  groupLabel: { color: p.text.muted, marginTop: v2.space.xl, marginBottom: v2.space.sm },
  chipRow: { gap: v2.space.sm, paddingRight: v2.space.lg },
  multiline: {
    minHeight: 76, color: p.text.primary, borderBottomWidth: 1,
    paddingVertical: v2.space.sm, textAlignVertical: 'top',
  },
  });
}
