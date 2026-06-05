/**
 * app/listing/edit/[id].tsx — Edit an existing listing.
 *
 * Reached from /my-listings → Edit button on a SellerListingCard.
 *
 * SCOPE — pre-TestFlight minimum: only allow editing safe metadata.
 *   • Editable fields: event_name, venue, restrictions, ticket_platform.
 *   • Pricing / quantity / dates are NOT editable here (touches financial
 *     commitments + auction timing; out of scope for v1 edit).
 *   • Gated by bid_count === 0 && auction_status === 'active'.
 *     Once a bid is placed, edits would unfairly change the offer; the
 *     seller must cancel via /my-listings → Cancel pill.
 *
 * Server-side, the `guard_listing_state_columns` trigger blocks any client
 * from changing current_bid, bid_count, highest_bidder_id, status,
 * auction_status, winner_user_id, winning_bid_amount. So even if someone
 * extended this form to include those fields, the update would error out.
 * RLS additionally enforces seller_id = auth.uid().
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { Listing, TicketPlatform } from '@/src/types';

const TICKET_PLATFORMS: { value: TicketPlatform; label: string }[] = [
  { value: 'dice',         label: 'DICE' },
  { value: 'eventbrite',   label: 'Eventbrite' },
  { value: 'posh',         label: 'Posh' },
  { value: 'axs',          label: 'AXS' },
  { value: 'ticketmaster', label: 'Ticketmaster' },
  { value: 'other',        label: 'Other' },
];

// Banned content check — mirrors CreateListingScreen so edits can't bypass
// the create-time content gate (Apple Guideline 1.4.3).
const BANNED_CONTENT_PATTERNS: { pattern: RegExp; label: string }[] = [
  { pattern: /\balcohol\b/i,         label: 'alcohol' },
  { pattern: /\bdrugs?\b/i,          label: 'drugs' },
  { pattern: /\bweed\b/i,            label: 'weed' },
  { pattern: /\bcocaine\b/i,         label: 'cocaine' },
  { pattern: /\bmolly\b/i,           label: 'molly' },
  { pattern: /\bopen[\s-]?bar\b/i,   label: 'open bar' },
  { pattern: /\bbottle[\s-]?service\b/i, label: 'bottle service' },
  { pattern: /\bfake[\s-]?tickets?\b/i,  label: 'fake ticket' },
  { pattern: /\bcounterfeit\b/i,     label: 'counterfeit' },
  { pattern: /\bunderage\b/i,        label: 'underage' },
];
function findBannedContent(fields: (string | null | undefined)[]): string | null {
  const haystack = fields.filter(Boolean).join(' \n ');
  for (const { pattern, label } of BANNED_CONTENT_PATTERNS) {
    if (pattern.test(haystack)) return label;
  }
  return null;
}

export default function EditListingScreen() {
  const { user } = useAuth();
  const params = useLocalSearchParams<{ id: string }>();
  const listingId = params.id ?? '';

  const [loading, setLoading]   = useState(true);
  const [saving,  setSaving]    = useState(false);
  const [listing, setListing]   = useState<Listing | null>(null);

  // editable state
  const [eventName,      setEventName]      = useState('');
  const [venue,          setVenue]          = useState('');
  const [restrictions,   setRestrictions]   = useState('');
  const [ticketPlatform, setTicketPlatform] = useState<TicketPlatform>('other');

  // ── Load listing ──────────────────────────────────────────────────────────
  useEffect(() => {
    let cancelled = false;
    async function load() {
      if (!listingId || !user) return;
      const { data, error } = await supabase
        .from('listings')
        .select('*')
        .eq('id', listingId)
        .single();
      if (cancelled) return;
      if (error || !data) {
        Alert.alert('Listing not found', error?.message ?? 'Try again later.', [
          { text: 'OK', onPress: () => router.back() },
        ]);
        setLoading(false);
        return;
      }
      const l = data as Listing;
      if (l.seller_id !== user.id) {
        Alert.alert('Not allowed', 'You can only edit your own listings.', [
          { text: 'OK', onPress: () => router.back() },
        ]);
        return;
      }
      if (l.bid_count > 0 || l.auction_status !== 'active') {
        Alert.alert(
          'Cannot edit',
          l.bid_count > 0
            ? 'This listing already has bids. Use Cancel from My Listings if you need to remove it.'
            : 'This listing is no longer active.',
          [{ text: 'OK', onPress: () => router.back() }],
        );
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
  }, [listingId, user]);

  async function handleSave() {
    if (!listing || !user) return;
    if (!eventName.trim() || !venue.trim()) {
      Alert.alert('Missing fields', 'Event name and venue are required.');
      return;
    }
    const banned = findBannedContent([eventName, venue, restrictions]);
    if (banned) {
      Alert.alert(
        'Listing not allowed',
        `Listings can't mention "${banned}". Please revise and try again.`,
      );
      return;
    }
    setSaving(true);
    try {
      const { error } = await supabase
        .from('listings')
        .update({
          event_name:      eventName.trim(),
          venue:           venue.trim(),
          restrictions:    restrictions.trim() || null,
          ticket_platform: ticketPlatform,
        })
        .eq('id', listing.id)
        .eq('seller_id', user.id);
      if (error) {
        Alert.alert('Save failed', error.message);
        return;
      }
      Alert.alert('Saved', 'Your listing has been updated.', [
        { text: 'OK', onPress: () => router.back() },
      ]);
    } finally {
      setSaving(false);
    }
  }

  if (loading || !listing) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.center}><ActivityIndicator color={colors.accent} /></View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'←'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Edit Listing</Text>
        <View style={s.backBtn} />
      </View>
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
          <Text style={s.helper}>
            You can edit details until the first bid arrives. After that, use
            Cancel from My Listings if you need to remove it.
          </Text>

          <Text style={s.label}>Event name *</Text>
          <TextInput
            style={s.input}
            value={eventName}
            onChangeText={setEventName}
            placeholder="e.g. Weekend Pool Party"
            placeholderTextColor={colors.textPlaceholder}
          />

          <Text style={s.label}>Venue *</Text>
          <TextInput
            style={s.input}
            value={venue}
            onChangeText={setVenue}
            placeholder="e.g. LIV Miami"
            placeholderTextColor={colors.textPlaceholder}
          />

          <Text style={s.label}>Ticket platform</Text>
          <View style={s.pills}>
            {TICKET_PLATFORMS.map(({ value, label }) => (
              <TouchableOpacity key={value}
                style={[s.pill, ticketPlatform === value && s.pillOn]}
                onPress={() => setTicketPlatform(value)} activeOpacity={0.75}>
                <Text style={[s.pillText, ticketPlatform === value && s.pillTextOn]}>{label}</Text>
              </TouchableOpacity>
            ))}
          </View>

          <Text style={s.label}>Restrictions (optional)</Text>
          <TextInput
            style={[s.input, s.textarea]}
            value={restrictions}
            onChangeText={setRestrictions}
            placeholder="e.g. 21+, no re-entry, dress code…"
            placeholderTextColor={colors.textPlaceholder}
            multiline
            numberOfLines={3}
            maxLength={500}
            textAlignVertical="top"
          />

          <TouchableOpacity
            style={[s.saveBtn, saving && s.saveBtnDisabled]}
            onPress={handleSave}
            disabled={saving}
            activeOpacity={0.85}
          >
            {saving
              ? <ActivityIndicator color={colors.text} />
              : <Text style={s.saveBtnText}>Save changes</Text>}
          </TouchableOpacity>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe:   { flex: 1, backgroundColor: colors.bg },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  topBar: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    borderBottomWidth: 1, borderBottomColor: colors.border,
  },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  body:   { padding: spacing.lg, paddingBottom: spacing.xxl },
  helper: { color: colors.textMuted, fontSize: fontSize.sm, lineHeight: 20, marginBottom: spacing.lg },
  label:  { color: colors.textMuted, fontSize: fontSize.sm, marginBottom: 6 },
  input: {
    backgroundColor: colors.bgInput, color: colors.text,
    borderWidth: 1, borderColor: colors.borderInput,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: 13,
    fontSize: fontSize.md, marginBottom: spacing.md,
  },
  textarea: { height: 80, textAlignVertical: 'top' },

  pills:      { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md, flexWrap: 'wrap' },
  pill:       { paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
                borderRadius: radius.full, borderWidth: 1,
                borderColor: colors.borderInput, backgroundColor: colors.bgInput },
  pillOn:     { backgroundColor: colors.primary, borderColor: colors.primary },
  pillText:   { color: colors.textMuted, fontSize: fontSize.sm, fontWeight: '600' },
  pillTextOn: { color: colors.text },

  saveBtn: {
    backgroundColor: colors.primary, paddingVertical: spacing.md,
    borderRadius: radius.md, alignItems: 'center', marginTop: spacing.lg,
  },
  saveBtnDisabled: { opacity: 0.65 },
  saveBtnText:     { color: colors.text, fontWeight: '800', fontSize: fontSize.md, letterSpacing: 0.8 },
});
