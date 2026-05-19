/**
 * src/screens/CreateListingScreen.tsx
 *
 * Full Create Listing form.
 * On Publish:
 *  1. Validates all required fields.
 *  2. Uploads cover image to Supabase Storage → gets storage path.
 *  3. Inserts a row into public.listings.
 *  4. Navigates to /listing/<newId>.
 *
 * Imported by app/(tabs)/create.tsx (thin wrapper).
 */

import DateTimePicker, { DateTimePickerEvent } from '@react-native-community/datetimepicker';
import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useImageUpload } from '@/src/hooks/useImageUpload';
import { ImageUploadTile } from '@/src/components/ImageUploadTile';
import { APP_CONFIG } from '@/src/config/app';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import { NEIGHBORHOODS, NEIGHBORHOOD_LABELS } from '@/src/constants/neighborhoods';
import type {
  CanCreateListingReason,
  DurationHours,
  Neighborhood,
  RiskTier,
  TicketPlatform,
  TicketType,
  TransferMethod,
} from '@/src/types';

// ─── Constants ────────────────────────────────────────────────────────────────

const TICKET_TYPES:     TicketType[]     = ['GA', 'VIP'];
const TRANSFER_METHODS: { value: TransferMethod; label: string }[] = [
  { value: 'mobile_transfer', label: 'Mobile Transfer' },
  { value: 'email',           label: 'Email' },
];
const DURATION_OPTIONS: DurationHours[]  = [1, 3, 6, 12, 24, 48];

const TICKET_PLATFORMS: { value: TicketPlatform; label: string }[] = [
  { value: 'dice',         label: 'DICE' },
  { value: 'eventbrite',   label: 'Eventbrite' },
  { value: 'posh',         label: 'Posh' },
  { value: 'axs',          label: 'AXS' },
  { value: 'ticketmaster', label: 'Ticketmaster' },
  { value: 'other',        label: 'Other' },
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

function digitsOnly(s: string) { return s.replace(/\D/g, ''); }

function defaultDate() { const d = new Date(); d.setHours(0,0,0,0); return d; }
function defaultTime() { const d = new Date(); d.setHours(d.getHours()+1,0,0,0); return d; }

function fmtDate(d: Date) {
  return d.toLocaleDateString('en-US', { weekday:'short', month:'short', day:'numeric' });
}
function fmtTime(d: Date) {
  return d.toLocaleTimeString('en-US', { hour:'numeric', minute:'2-digit', hour12:true });
}
/** "2025-08-15" */
function toDateStr(d: Date) { return d.toISOString().split('T')[0]; }
/** "21:00:00" */
function toTimeStr(d: Date) {
  return d.toTimeString().split(' ')[0]; // "HH:MM:SS"
}

// ─── Tiny shared components ───────────────────────────────────────────────────

function SectionHeader({ title }: { title: string }) {
  return (
    <View style={sec.wrap}>
      <View style={sec.line} />
      <Text style={sec.text}>{title}</Text>
    </View>
  );
}
const sec = StyleSheet.create({
  wrap: { marginTop: 28, marginBottom: 12 },
  line: { height: 1, backgroundColor: colors.border, marginBottom: 10 },
  text: { fontSize: fontSize.xs, fontWeight: '700', color: colors.textDim,
          textTransform: 'uppercase', letterSpacing: 1.5 },
});

function FieldError({ msg }: { msg?: string }) {
  if (!msg) return null;
  return <Text style={{ color: colors.error, fontSize: fontSize.xs, marginTop: -8, marginBottom: 8 }}>{msg}</Text>;
}

// ─── Main Component ───────────────────────────────────────────────────────────

export default function CreateListingScreen() {
  const { user } = useAuth();

  // A — Event
  const [eventName,        setEventName]        = useState('');
  const [venue,            setVenue]            = useState('');
  const [neighborhood,     setNeighborhood]     = useState<Neighborhood | null>(null);
  const [neighborhoodOpen, setNeighborhoodOpen] = useState(false);
  const [eventDate,        setEventDate]        = useState<Date>(defaultDate);
  const [eventTime,        setEventTime]        = useState<Date>(defaultTime);

  // B — Ticket
  const [ticketType,      setTicketType]      = useState<TicketType | null>(null);
  const [quantity,        setQuantity]        = useState(1);
  const [transferMethod,  setTransferMethod]  = useState<TransferMethod | null>(null);
  const [restrictions,    setRestrictions]    = useState('');

  // C — Pricing
  const [startingBid,    setStartingBid]    = useState('');
  const [buyNowEnabled,  setBuyNowEnabled]  = useState(false);
  const [buyNowPrice,    setBuyNowPrice]    = useState('');
  const [durationHours,  setDurationHours]  = useState<DurationHours | null>(null);

  // D — Platform & Trust (Phase A)
  const [ticketPlatform,           setTicketPlatform]           = useState<TicketPlatform>('other');
  const [sellerCommitmentAccepted, setSellerCommitmentAccepted] = useState(false);

  // E — Media
  const coverUpload = useImageUpload({
    userId: user?.id ?? '',
    folder: 'covers',
    aspect: [16, 9],
    quality: 0.85,
  });
  const proofUpload = useImageUpload({
    userId: user?.id ?? '',
    folder: 'proofs',
    aspect: null,
    quality: 0.85,
  });

  // Picker modal
  const [pickerMode,    setPickerMode]    = useState<'date' | 'time'>('date');
  const [pickerVisible, setPickerVisible] = useState(false);

  // Phase D — risk check state
  const [riskWarningVisible, setRiskWarningVisible] = useState(false);
  const [riskBanner,         setRiskBanner]         = useState<{ reason: CanCreateListingReason; tier: RiskTier | null } | null>(null);
  const [riskCheckPassed,    setRiskCheckPassed]    = useState(false);

  // UI
  const [submitted, setSubmitted] = useState(false);
  const [loading,   setLoading]   = useState(false);

  const startingBidNum = parseInt(startingBid, 10);
  const buyNowPriceNum = parseInt(buyNowPrice, 10);

  // Validation
  const errors = useMemo(() => ({
    eventName:     !eventName.trim()                        ? 'Event name is required.'            : '',
    venue:         !venue.trim()                            ? 'Venue is required.'                 : '',
    neighborhood:  !neighborhood                            ? 'Select a neighborhood.'             : '',
    ticketType:    !ticketType                              ? 'Select a ticket type.'              : '',
    transferMethod:!transferMethod                          ? 'Select a transfer method.'          : '',
    startingBid:   (!startingBid || startingBidNum < 1)    ? 'Starting bid must be ≥ $1.'         : '',
    buyNowPrice:   buyNowEnabled && (!buyNowPrice || buyNowPriceNum <= startingBidNum)
                     ? `Buy Now must be > starting bid ($${startingBidNum || 0}).`                : '',
    durationHours: !durationHours                          ? 'Select an auction duration.'        : '',
    coverImage:    !coverUpload.localUri                   ? 'Cover image is required.'           : '',
    proofImage:    !proofUpload.localUri                   ? 'Proof of ownership is required.'    : '',
    commitment:    !sellerCommitmentAccepted               ? 'You must accept the commitment.'    : '',
  }), [eventName, venue, neighborhood, ticketType, transferMethod,
       startingBid, startingBidNum, buyNowEnabled, buyNowPrice, buyNowPriceNum,
       durationHours, coverUpload.localUri, proofUpload.localUri,
       sellerCommitmentAccepted]);

  const isValid = Object.values(errors).every(e => !e);

  // Date / time picker
  function openPicker(mode: 'date' | 'time') { setPickerMode(mode); setPickerVisible(true); }
  function onPickerChange(_e: DateTimePickerEvent, selected?: Date) {
    if (Platform.OS === 'android') setPickerVisible(false);
    if (!selected) return;
    if (pickerMode === 'date') setEventDate(selected);
    else setEventTime(selected);
  }

  // ── Phase D risk-check copy ────────────────────────────────────────────────
  const RISK_COPY = {
    medium_risk_warning: "We've noticed some recent issues. Please double-check your listing details.",
    high_risk_warning:   'Your account is under review. Incorrect listings may result in restrictions.',
    critical_risk:       'You cannot create listings at this time. Contact support.',
    listing_blocked:     'You cannot create listings at this time. Contact support.',
  } as const;

  // ── Phase D: parse + validate RPC response ─────────────────────────────────

  const VALID_REASONS = new Set<CanCreateListingReason>([
    'ok', 'medium_risk_warning', 'high_risk_warning', 'critical_risk', 'listing_blocked',
  ]);

  type RiskCheckResult =
    | { status: 'ok';          reason: 'ok';                         tier: RiskTier | null }
    | { status: 'warn';        reason: CanCreateListingReason;       tier: RiskTier | null }
    | { status: 'block';       reason: CanCreateListingReason;       tier: RiskTier | null }
    | { status: 'transient';   message: string }
    | { status: 'bad_shape';   raw: unknown };

  function parseRiskCheckResponse(
    data: unknown,
    error: { message: string } | null,
  ): RiskCheckResult {
    // 1. Network / transient RPC error → fail-open with warning
    if (error) {
      return { status: 'transient', message: error.message };
    }

    // 2. Normalize: Supabase returns RETURNS TABLE as an array
    const row = Array.isArray(data) ? data[0] : data;

    // 3. Validate shape: must have allowed (boolean), reason (known string)
    if (
      !row ||
      typeof row !== 'object' ||
      typeof (row as Record<string, unknown>).allowed !== 'boolean' ||
      typeof (row as Record<string, unknown>).reason  !== 'string' ||
      !VALID_REASONS.has((row as Record<string, unknown>).reason as CanCreateListingReason)
    ) {
      return { status: 'bad_shape', raw: row };
    }

    const { allowed, reason, risk_tier } = row as {
      allowed:   boolean;
      reason:    CanCreateListingReason;
      risk_tier: RiskTier | null;
    };

    if (!allowed) return { status: 'block', reason, tier: risk_tier };
    if (reason === 'high_risk_warning' || reason === 'medium_risk_warning') {
      return { status: 'warn', reason, tier: risk_tier };
    }
    return { status: 'ok', reason: 'ok', tier: risk_tier };
  }

  // ── Phase D pre-submit risk check ─────────────────────────────────────────

  async function runRiskCheck(): Promise<boolean> {
    if (!user) return false;

    const { data, error } = await supabase.rpc('can_create_listing', {
      p_seller_id: user.id,
    });

    const result = parseRiskCheckResponse(data, error);

    switch (result.status) {
      case 'ok':
        setRiskBanner(null);
        return true;

      case 'transient':
        // Fail-open: allow submit but warn the seller + log for ops visibility
        console.warn('[CreateListingScreen] risk check transient error — allowing submit:', result.message);
        setRiskBanner({ reason: 'medium_risk_warning', tier: null });
        return true;

      case 'bad_shape':
        // Unexpected payload: block submit with generic error, log raw data
        console.error('[CreateListingScreen] risk check returned unexpected shape:', JSON.stringify(result.raw));
        Alert.alert('Something went wrong', 'Unable to verify your account status. Please try again.');
        return false;

      case 'block':
        setRiskBanner({ reason: result.reason, tier: result.tier });
        Alert.alert('Listing blocked', RISK_COPY[result.reason as keyof typeof RISK_COPY]);
        return false;

      case 'warn':
        setRiskBanner({ reason: result.reason, tier: result.tier });
        if (result.reason === 'high_risk_warning') {
          setRiskWarningVisible(true);
          return false; // handlePublish re-called after modal confirm
        }
        return true; // medium_risk_warning → banner only, allow through
    }
  }

  // Publish
  async function handlePublish() {
    setSubmitted(true);
    if (!isValid || !user) return;
    setLoading(true);

    try {
      // Gate: require FULLY connected Stripe payout account before listing.
      // Two-tier check:
      //   1. DB fast-path: stripe_onboarding_complete === true → pass
      //   2. Edge function: authoritative Stripe details_submitted check
      // If the profile query fails (e.g. column mismatch, network blip),
      // fall through to the edge function rather than blocking immediately.
      let payoutConnected = false;

      const { data: profile } = await supabase
        .from('profiles')
        .select('stripe_connect_id, stripe_onboarding_complete')
        .eq('id', user.id)
        .single();

      if (profile?.stripe_onboarding_complete) {
        // Fast path: DB already flagged onboarding complete.
        payoutConnected = true;
      } else {
        // Authoritative check: always ask the edge function.
        // This covers: no profile data, stripe_connect_id missing, or
        // onboarding_complete not yet set.
        try {
          const { data: statusData, error: statusErr } = await supabase.functions.invoke(
            'create-connect-account',
            { body: { status_only: true } },
          );
          if (!statusErr && statusData) {
            const parsed = typeof statusData === 'string' ? JSON.parse(statusData) : statusData;
            payoutConnected = parsed?.status === 'connected';
          }
        } catch {
          // Edge function unreachable — keep payoutConnected = false
        }
      }

      if (!payoutConnected) {
        if (Platform.OS === 'web') {
          const goSetup = window.confirm(
            'Payout Account Required\n\nComplete your payout setup before creating a listing. Go to payout setup now?',
          );
          if (goSetup) router.push('/settings/payout-setup');
        } else {
          Alert.alert(
            'Payout Account Required',
            'Complete your payout setup before creating a listing.',
            [
              { text: 'Set Up Now', onPress: () => router.push('/settings/payout-setup') },
              { text: 'Cancel', style: 'cancel' },
            ],
          );
        }
        return;
      }

      // Phase D: pre-submit risk gate (skip if already passed via modal confirm)
      if (!riskCheckPassed) {
        const canProceed = await runRiskCheck();
        if (!canProceed) return;
      }
      setRiskCheckPassed(false); // reset for next attempt

      // 1. Upload cover image
      const coverPath = await coverUpload.uploadImage();
      if (!coverPath) {
        const msg = coverUpload.error ?? 'Unknown upload error — check console for details.';
        console.error('[CreateListingScreen] cover upload failed:', msg);
        if (Platform.OS === 'web') { window.alert(msg); } else { Alert.alert('Upload failed', msg); }
        return;
      }

      // 1b. Upload proof of ownership image
      const proofPath = await proofUpload.uploadImage();
      if (!proofPath) {
        const msg = proofUpload.error ?? 'Unknown upload error — check console for details.';
        console.error('[CreateListingScreen] proof upload failed:', msg);
        if (Platform.OS === 'web') { window.alert(msg); } else { Alert.alert('Proof upload failed', msg); }
        return;
      }

      // 2. Compute ends_at
      const endsAt = new Date(Date.now() + durationHours! * 3_600_000);

      // 3. Insert listing row
      const { data, error } = await supabase
        .from('listings')
        .insert({
          seller_id:                     user.id,
          event_name:                    eventName.trim(),
          venue:                         venue.trim(),
          neighborhood:                  neighborhood!,
          event_date:                    toDateStr(eventDate),
          event_time:                    toTimeStr(eventTime),
          ticket_type:                   ticketType!,
          quantity,
          transfer_method:               transferMethod!,
          restrictions:                  restrictions.trim() || null,
          starting_bid:                  startingBidNum,
          buy_now_enabled:               buyNowEnabled,
          buy_now_price:                 buyNowEnabled ? buyNowPriceNum : null,
          duration_hours:                durationHours!,
          ends_at:                       endsAt.toISOString(),
          current_bid:                   startingBidNum,
          cover_image_path:              coverPath,
          // Phase A fields
          ticket_platform:               ticketPlatform,
          proof_of_ownership_path:       proofPath,
          seller_commitment_accepted_at: sellerCommitmentAccepted ? new Date().toISOString() : null,
        })
        .select('id')
        .single();

      if (error) throw new Error(error.message);

      // 4. Reset form
      setEventName(''); setVenue(''); setNeighborhood(null);
      setEventDate(defaultDate()); setEventTime(defaultTime());
      setTicketType(null); setQuantity(1); setTransferMethod(null); setRestrictions('');
      setStartingBid(''); setBuyNowEnabled(false); setBuyNowPrice('');
      setDurationHours(null);
      setTicketPlatform('other'); setSellerCommitmentAccepted(false);
      coverUpload.reset();
      proofUpload.reset();
      setSubmitted(false);
      setRiskBanner(null);

      // 5. Navigate to detail screen
      router.push(`/listing/${data.id}`);

    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Could not publish.';
      if (Platform.OS === 'web') { window.alert(msg); } else { Alert.alert('Error', msg); }
    } finally {
      setLoading(false);
    }
  }

  /** Called when user confirms past the high-risk warning modal */
  function handleRiskWarningContinue() {
    setRiskWarningVisible(false);
    setRiskCheckPassed(true);
    // Re-trigger publish — this time it will skip the risk check
    handlePublish();
  }

  const busy = loading || coverUpload.status === 'uploading' || proofUpload.status === 'uploading';

  // ────────────────────────────────────────────────────────────────────────────
  return (
    <KeyboardAvoidingView style={s.root} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
      <ScrollView contentContainerStyle={s.inner} keyboardShouldPersistTaps="handled">
        <Text style={s.pageTitle}>Create listing</Text>

        {/* ── A) EVENT DETAILS ─────────────────────────────── */}
        <SectionHeader title="Event details" />

        <Text style={s.label}>Event name *</Text>
        <TextInput
          style={[s.input, submitted && errors.eventName ? s.inputErr : null]}
          placeholder="e.g. Weekend Pool Party"
          placeholderTextColor={colors.textPlaceholder}
          value={eventName} onChangeText={setEventName}
        />
        {submitted && <FieldError msg={errors.eventName} />}

        <Text style={s.label}>Venue *</Text>
        <TextInput
          style={[s.input, submitted && errors.venue ? s.inputErr : null]}
          placeholder="e.g. LIV Miami"
          placeholderTextColor={colors.textPlaceholder}
          value={venue} onChangeText={setVenue}
        />
        {submitted && <FieldError msg={errors.venue} />}

        <Text style={s.label}>Neighborhood *</Text>
        <TouchableOpacity
          style={[s.input, s.row, submitted && errors.neighborhood ? s.inputErr : null]}
          onPress={() => setNeighborhoodOpen(true)} activeOpacity={0.75}>
          <Text style={neighborhood ? s.inputText : s.placeholder}>
            {neighborhood ? NEIGHBORHOOD_LABELS[neighborhood] : 'Select neighborhood'}
          </Text>
          <Text style={s.chevron}>▾</Text>
        </TouchableOpacity>
        {submitted && <FieldError msg={errors.neighborhood} />}

        <Text style={s.label}>Date & Time *</Text>
        <View style={s.pickerRow}>
          <TouchableOpacity style={s.pickerBtn} onPress={() => openPicker('date')} activeOpacity={0.75}>
            <Text style={s.pickerText}>📅  {fmtDate(eventDate)}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={s.pickerBtn} onPress={() => openPicker('time')} activeOpacity={0.75}>
            <Text style={s.pickerText}>🕐  {fmtTime(eventTime)}</Text>
          </TouchableOpacity>
        </View>

        {/* ── B) TICKET INFO ───────────────────────────────── */}
        <SectionHeader title="Ticket info" />

        <Text style={s.label}>Ticket type *</Text>
        <View style={s.pills}>
          {TICKET_TYPES.map(t => (
            <TouchableOpacity key={t}
              style={[s.pill, ticketType === t && s.pillOn]}
              onPress={() => setTicketType(t)} activeOpacity={0.75}>
              <Text style={[s.pillText, ticketType === t && s.pillTextOn]}>{t}</Text>
            </TouchableOpacity>
          ))}
        </View>
        {submitted && <FieldError msg={errors.ticketType} />}

        <Text style={s.label}>Quantity *</Text>
        <View style={s.stepper}>
          <TouchableOpacity style={[s.stepBtn, quantity <= 1 && s.stepDisabled]}
            onPress={() => setQuantity(q => Math.max(1, q - 1))} disabled={quantity <= 1} activeOpacity={0.75}>
            <Text style={s.stepGlyph}>−</Text>
          </TouchableOpacity>
          <Text style={s.stepVal}>{quantity}</Text>
          <TouchableOpacity style={s.stepBtn}
            onPress={() => setQuantity(q => q + 1)} activeOpacity={0.75}>
            <Text style={s.stepGlyph}>+</Text>
          </TouchableOpacity>
        </View>

        <Text style={s.label}>Transfer method *</Text>
        <View style={s.pills}>
          {TRANSFER_METHODS.map(({ value, label }) => (
            <TouchableOpacity key={value}
              style={[s.pill, transferMethod === value && s.pillOn]}
              onPress={() => setTransferMethod(value)} activeOpacity={0.75}>
              <Text style={[s.pillText, transferMethod === value && s.pillTextOn]}>{label}</Text>
            </TouchableOpacity>
          ))}
        </View>
        {submitted && <FieldError msg={errors.transferMethod} />}

        <Text style={s.label}>Ticket platform *</Text>
        <View style={[s.pills, { flexWrap: 'wrap' }]}>
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
          placeholder="e.g. 21+, no re-entry, dress code..."
          placeholderTextColor={colors.textPlaceholder}
          multiline numberOfLines={3}
          value={restrictions} onChangeText={setRestrictions}
        />

        {/* ── C) PRICING ───────────────────────────────────── */}
        <SectionHeader title="Pricing" />

        <Text style={s.label}>Starting bid *</Text>
        <View style={[s.prefixRow, submitted && errors.startingBid ? s.inputErr : null]}>
          <Text style={s.prefix}>$</Text>
          <TextInput style={s.prefixInput}
            placeholder="0" placeholderTextColor={colors.textPlaceholder}
            keyboardType="number-pad"
            value={startingBid} onChangeText={t => setStartingBid(digitsOnly(t))} />
        </View>
        {submitted && <FieldError msg={errors.startingBid} />}
        {startingBidNum > 0 && (
          <Text style={s.feeHint}>
            You receive ${Math.round(startingBidNum * (1 - APP_CONFIG.SELLER_FEE_RATE)).toLocaleString('en-US')} per ticket after the {Math.round(APP_CONFIG.SELLER_FEE_RATE * 100)}% marketplace fee.
          </Text>
        )}

        <View style={s.toggleCard}>
          <View style={{ flex: 1, marginRight: spacing.md }}>
            <Text style={s.toggleLabel}>Buy Now price</Text>
            <Text style={s.toggleHint}>Let buyers skip the auction</Text>
          </View>
          <Switch
            value={buyNowEnabled}
            onValueChange={v => { setBuyNowEnabled(v); if (!v) setBuyNowPrice(''); }}
            trackColor={{ false: colors.border, true: colors.primary }}
            thumbColor={colors.text}
          />
        </View>

        {buyNowEnabled && (
          <>
            <View style={[s.prefixRow, submitted && errors.buyNowPrice ? s.inputErr : null]}>
              <Text style={s.prefix}>$</Text>
              <TextInput style={s.prefixInput}
                placeholder="0" placeholderTextColor={colors.textPlaceholder}
                keyboardType="number-pad"
                value={buyNowPrice} onChangeText={t => setBuyNowPrice(digitsOnly(t))} />
            </View>
            {submitted && <FieldError msg={errors.buyNowPrice} />}
            {buyNowPriceNum > 0 && (
              <Text style={s.feeHint}>
                You receive ${Math.round(buyNowPriceNum * (1 - APP_CONFIG.SELLER_FEE_RATE)).toLocaleString('en-US')} per ticket after the {Math.round(APP_CONFIG.SELLER_FEE_RATE * 100)}% marketplace fee.
              </Text>
            )}
          </>
        )}

        <Text style={[s.label, { marginTop: spacing.md }]}>Auction duration *</Text>
        <View style={[s.pills, { flexWrap: 'wrap' }]}>
          {DURATION_OPTIONS.map(h => (
            <TouchableOpacity key={h}
              style={[s.pill, { minWidth: 56, alignItems: 'center' }, durationHours === h && s.pillOn]}
              onPress={() => setDurationHours(h)} activeOpacity={0.75}>
              <Text style={[s.pillText, durationHours === h && s.pillTextOn]}>
                {h < 24 ? `${h}h` : `${h / 24}d`}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
        {submitted && <FieldError msg={errors.durationHours} />}

        {/* ── D) MEDIA ─────────────────────────────────────── */}
        <SectionHeader title="Media" />

        <Text style={s.label}>Cover image *</Text>
        <ImageUploadTile
          localUri={coverUpload.localUri}
          status={coverUpload.status}
          error={coverUpload.error}
          onPress={coverUpload.pickImage}
          label="Upload cover image"
          hint="JPG or PNG · 16:9 recommended"
          icon="🖼️"
          height={180}
          hasError={submitted && !!errors.coverImage}
          disabled={busy}
        />
        {submitted && <FieldError msg={errors.coverImage} />}

        <Text style={s.label}>Proof of ownership *</Text>
        <ImageUploadTile
          localUri={proofUpload.localUri}
          status={proofUpload.status}
          error={proofUpload.error}
          onPress={proofUpload.pickImage}
          label="Upload proof of ownership"
          hint="Screenshot of ticket in app or confirmation email"
          icon="🎟️"
          height={140}
          hasError={submitted && !!errors.proofImage}
          disabled={busy}
        />
        {submitted && <FieldError msg={errors.proofImage} />}

        {/* ── F) COMMITMENT + PUBLISH ─────────────────────── */}
        <SectionHeader title="Seller commitment" />

        <Pressable
          style={s.commitRow}
          onPress={() => setSellerCommitmentAccepted(v => !v)}
        >
          <View style={[s.checkbox, sellerCommitmentAccepted && s.checkboxOn]}>
            {sellerCommitmentAccepted && <Text style={s.checkMark}>{'\u2713'}</Text>}
          </View>
          <Text style={s.commitText}>
            I confirm I own these tickets and will transfer them within 24 hours of sale.
          </Text>
        </Pressable>
        {submitted && <FieldError msg={errors.commitment} />}

        {submitted && !isValid && (
          <Text style={s.validationMsg}>Please fix the errors above before publishing.</Text>
        )}

        {/* ── Phase D: risk banner ───────────────────────────── */}
        {riskBanner && riskBanner.reason !== 'ok' && (
          <View style={[
            s.riskBanner,
            (!riskBanner || riskBanner.reason === 'medium_risk_warning') && s.riskBannerMedium,
            riskBanner.reason === 'high_risk_warning'                    && s.riskBannerHigh,
            (riskBanner.reason === 'critical_risk' || riskBanner.reason === 'listing_blocked') && s.riskBannerCritical,
          ]}>
            <Text style={s.riskBannerText}>
              {RISK_COPY[riskBanner.reason as keyof typeof RISK_COPY]}
            </Text>
          </View>
        )}

        <TouchableOpacity
          style={[s.publishBtn, busy && s.publishBtnBusy]}
          onPress={handlePublish} disabled={busy} activeOpacity={0.85}>
          {busy
            ? <ActivityIndicator color={colors.text} />
            : <Text style={s.publishBtnText}>Publish Auction</Text>
          }
        </TouchableOpacity>

        <View style={{ height: 56 }} />
      </ScrollView>

      {/* ── Neighborhood modal ──────────────────────────────── */}
      <Modal visible={neighborhoodOpen} transparent animationType="slide"
        onRequestClose={() => setNeighborhoodOpen(false)}>
        <Pressable style={s.modalBdrop} onPress={() => setNeighborhoodOpen(false)} />
        <View style={s.modalSheet}>
          <View style={s.modalHead}>
            <Text style={s.modalTitle}>Select Neighborhood</Text>
            <TouchableOpacity onPress={() => setNeighborhoodOpen(false)}>
              <Text style={s.modalDone}>Done</Text>
            </TouchableOpacity>
          </View>
          <ScrollView>
            {NEIGHBORHOODS.map(n => (
              <TouchableOpacity key={n}
                style={[s.nRow, neighborhood === n && { backgroundColor: colors.primarySoft }]}
                onPress={() => { setNeighborhood(n); setNeighborhoodOpen(false); }}
                activeOpacity={0.7}>
                <Text style={[s.nText, neighborhood === n && { color: colors.primary, fontWeight: '600' }]}>
                  {NEIGHBORHOOD_LABELS[n]}
                </Text>
                {neighborhood === n && <Text style={{ color: colors.primary, fontWeight: '700' }}>✓</Text>}
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>
      </Modal>

      {/* ── Date / Time picker ──────────────────────────────── */}
      {Platform.OS === 'ios' ? (
        <Modal visible={pickerVisible} transparent animationType="slide"
          onRequestClose={() => setPickerVisible(false)}>
          <Pressable style={s.modalBdrop} onPress={() => setPickerVisible(false)} />
          <View style={s.modalSheet}>
            <View style={s.modalHead}>
              <Text style={s.modalTitle}>{pickerMode === 'date' ? 'Event Date' : 'Event Time'}</Text>
              <TouchableOpacity onPress={() => setPickerVisible(false)}>
                <Text style={s.modalDone}>Done</Text>
              </TouchableOpacity>
            </View>
            <DateTimePicker
              value={pickerMode === 'date' ? eventDate : eventTime}
              mode={pickerMode} display="spinner" textColor={colors.text}
              onChange={onPickerChange}
              minimumDate={pickerMode === 'date' ? new Date() : undefined}
            />
          </View>
        </Modal>
      ) : (
        pickerVisible && (
          <DateTimePicker
            value={pickerMode === 'date' ? eventDate : eventTime}
            mode={pickerMode} display="default"
            onChange={onPickerChange}
            minimumDate={pickerMode === 'date' ? new Date() : undefined}
          />
        )
      )}
      {/* ── Phase D: high-risk warning modal ──────────────── */}
      <Modal visible={riskWarningVisible} transparent animationType="fade"
        onRequestClose={() => setRiskWarningVisible(false)}>
        <View style={s.riskModalOverlay}>
          <View style={s.riskModalCard}>
            <Text style={s.riskModalTitle}>Account Under Review</Text>
            <Text style={s.riskModalBody}>
              {RISK_COPY.high_risk_warning}
            </Text>
            <View style={s.riskModalActions}>
              <TouchableOpacity
                style={s.riskModalBtnCancel}
                onPress={() => setRiskWarningVisible(false)}
                activeOpacity={0.75}>
                <Text style={s.riskModalBtnCancelText}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={s.riskModalBtnContinue}
                onPress={handleRiskWarningContinue}
                activeOpacity={0.85}>
                <Text style={s.riskModalBtnContinueText}>Continue Anyway</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </KeyboardAvoidingView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  root:      { flex: 1, backgroundColor: colors.bg },
  inner:     { paddingTop: 60, paddingHorizontal: spacing.lg, paddingBottom: 48 },
  pageTitle: { fontSize: fontSize.xl, fontWeight: '800', color: colors.text, marginBottom: 4 },
  label:     { fontSize: fontSize.sm, color: colors.textMuted, marginBottom: 6 },
  feeHint:   { fontSize: fontSize.xs, color: colors.textMuted, marginTop: -8, marginBottom: spacing.md, fontStyle: 'italic' },

  input: {
    backgroundColor: colors.bgInput, color: colors.text,
    borderWidth: 1, borderColor: colors.borderInput,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: 13,
    fontSize: fontSize.md, marginBottom: spacing.md,
  },
  inputErr:    { borderColor: colors.error },
  inputText:   { color: colors.text, fontSize: fontSize.md, flex: 1 },
  placeholder: { color: colors.textPlaceholder, fontSize: fontSize.md, flex: 1 },
  textarea:    { height: 80, textAlignVertical: 'top' },

  row:     { flexDirection: 'row', alignItems: 'center' },
  chevron: { color: colors.textMuted, fontSize: fontSize.sm },

  pickerRow: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  pickerBtn: {
    flex: 1, backgroundColor: colors.bgInput, borderWidth: 1, borderColor: colors.borderInput,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: 13,
  },
  pickerText: { color: colors.text, fontSize: fontSize.sm, fontWeight: '500' },

  pills:       { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  pill:        { paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
                 borderRadius: radius.full, borderWidth: 1,
                 borderColor: colors.borderInput, backgroundColor: colors.bgInput },
  pillOn:      { backgroundColor: colors.primary, borderColor: colors.primary },
  pillText:    { color: colors.textMuted, fontSize: fontSize.sm, fontWeight: '600' },
  pillTextOn:  { color: colors.text },

  stepper:     { flexDirection: 'row', alignItems: 'center', gap: spacing.lg, marginBottom: spacing.md },
  stepBtn:     { width: 44, height: 44, borderRadius: radius.md, backgroundColor: colors.bgInput,
                 borderWidth: 1, borderColor: colors.borderInput, alignItems: 'center', justifyContent: 'center' },
  stepDisabled:{ opacity: 0.35 },
  stepGlyph:   { color: colors.text, fontSize: 22, fontWeight: '600' },
  stepVal:     { fontSize: fontSize.lg, fontWeight: '700', color: colors.text, minWidth: 28, textAlign: 'center' },

  prefixRow:   { flexDirection: 'row', alignItems: 'center', backgroundColor: colors.bgInput,
                 borderWidth: 1, borderColor: colors.borderInput, borderRadius: radius.md,
                 paddingHorizontal: spacing.md, marginBottom: spacing.md },
  prefix:      { color: colors.textMuted, fontSize: fontSize.md, marginRight: 4 },
  prefixInput: { flex: 1, color: colors.text, fontSize: fontSize.md, paddingVertical: 13 },

  toggleCard:  { flexDirection: 'row', alignItems: 'center', backgroundColor: colors.bgCard,
                 borderWidth: 1, borderColor: colors.border, borderRadius: radius.md,
                 padding: spacing.md, marginBottom: spacing.sm },
  toggleLabel: { color: colors.text, fontSize: fontSize.md, fontWeight: '600' },
  toggleHint:  { color: colors.textMuted, fontSize: fontSize.xs, marginTop: 2 },

  validationMsg: { color: colors.error, fontSize: fontSize.sm, textAlign: 'center', marginTop: spacing.sm },

  publishBtn: {
    backgroundColor: colors.primary, paddingVertical: spacing.md,
    borderRadius: radius.md, alignItems: 'center', marginTop: spacing.lg,
    shadowColor: colors.primary, shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4, shadowRadius: 10, elevation: 6,
  },
  publishBtnBusy: { opacity: 0.65 },
  publishBtnText: { color: colors.text, fontWeight: '800', fontSize: fontSize.md, letterSpacing: 0.8 },

  modalBdrop: { flex: 1, backgroundColor: colors.bgOverlay },
  modalSheet: { backgroundColor: colors.bgModal, borderTopLeftRadius: radius.xl,
                borderTopRightRadius: radius.xl, paddingBottom: 48, maxHeight: '75%' },
  modalHead:  { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
                paddingHorizontal: spacing.lg, paddingVertical: spacing.md,
                borderBottomWidth: 1, borderBottomColor: colors.border },
  modalTitle: { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },
  modalDone:  { color: colors.primary, fontSize: fontSize.md, fontWeight: '700' },

  nRow:  { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
           paddingHorizontal: spacing.lg, paddingVertical: spacing.md,
           borderBottomWidth: 1, borderBottomColor: colors.border },
  nText: { color: colors.text, fontSize: fontSize.md },

  // Commitment checkbox
  commitRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: spacing.md,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: radius.sm,
    borderWidth: 2,
    borderColor: colors.borderInput,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: spacing.sm,
    marginTop: 1,
  },
  checkboxOn: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  checkMark: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '700',
    lineHeight: 18,
  },
  commitText: {
    flex: 1,
    color: colors.textMuted,
    fontSize: fontSize.sm,
    lineHeight: 20,
  },

  // Phase D — risk banner
  riskBanner: {
    borderRadius: radius.md,
    padding: spacing.md,
    marginTop: spacing.md,
  },
  riskBannerMedium: {
    backgroundColor: '#332B00',
    borderWidth: 1,
    borderColor: '#665500',
  },
  riskBannerHigh: {
    backgroundColor: '#331A00',
    borderWidth: 1,
    borderColor: '#663300',
  },
  riskBannerCritical: {
    backgroundColor: '#330000',
    borderWidth: 1,
    borderColor: '#660000',
  },
  riskBannerText: {
    color: '#FFDDBB',
    fontSize: fontSize.sm,
    lineHeight: 20,
  },

  // Phase D — high-risk warning modal
  riskModalOverlay: {
    flex: 1,
    backgroundColor: colors.bgOverlay,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: spacing.lg,
  },
  riskModalCard: {
    backgroundColor: colors.bgModal,
    borderRadius: radius.xl,
    padding: spacing.lg + 4,
    width: '100%',
    maxWidth: 360,
  },
  riskModalTitle: {
    color: colors.text,
    fontSize: fontSize.lg,
    fontWeight: '700',
    marginBottom: spacing.sm,
  },
  riskModalBody: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    lineHeight: 22,
    marginBottom: spacing.lg,
  },
  riskModalActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: spacing.sm,
  },
  riskModalBtnCancel: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderInput,
  },
  riskModalBtnCancelText: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
  riskModalBtnContinue: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.md,
    backgroundColor: colors.primary,
  },
  riskModalBtnContinueText: {
    color: colors.text,
    fontSize: fontSize.sm,
    fontWeight: '700',
  },
});
