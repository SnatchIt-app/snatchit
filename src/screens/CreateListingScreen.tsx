/**
 * src/screens/CreateListingScreen.tsx — Sell your ticket (V2).
 *
 * PRESENTATION rebuilt on the V2 primitives; the SUBMISSION path is unchanged.
 * Every gate in `handlePublish` — verified-phone, connected-payout, the
 * `can_create_listing` risk check, content moderation, the cover + proof uploads,
 * the `public.listings` insert and the navigate-to-detail — is the same logic in
 * the same order it has always run. The whole-dollars listing contract, the fee
 * math and the RPC/edge-function calls are untouched.
 *
 * What changed is the surface: legacy cards and rounded wells become sections,
 * hairlines and the Input / Chip / Sheet / StickyBar set; the pure decisions
 * (validation, moderation, risk parsing, money preview) move to
 * src/lib/sell/sellState.ts where they are tested. Imported by the thin route
 * wrapper app/(tabs)/create.tsx.
 */

import DateTimePicker, { DateTimePickerEvent } from '@react-native-community/datetimepicker';
import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
  type TextStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useImageUpload } from '@/src/hooks/useImageUpload';
import { Button, Chip, Input, MediaUpload, Sheet, StickyBar } from '@/src/components/ui';
import { useDockScroll } from '@/src/components/nav/dockContext';
import { useCtaDockOffset } from '@/src/lib/nav/navInsets';
import {
  digitsOnly,
  findBannedContent,
  isSellValid,
  parseAmount,
  parseRiskCheckResponse,
  priceSummary,
  RISK_COPY,
  sellErrors,
  sellingMethodBlurb,
  submitCtaLabel,
} from '@/src/lib/sell/sellState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import { NEIGHBORHOOD_GROUPS, NEIGHBORHOOD_LABELS } from '@/src/constants/neighborhoods';
import { CATEGORIES, CATEGORY_LABELS } from '@/src/constants/categories';
import type {
  CanCreateListingReason,
  DurationHours,
  EventCategory,
  MyProfileRPC,
  Neighborhood,
  RiskTier,
  TicketPlatform,
  TicketType,
  TransferMethod,
} from '@/src/types';

// ─── Constants (unchanged) ──────────────────────────────────────────────────────

const TICKET_TYPES: TicketType[] = ['GA', 'VIP'];
const TRANSFER_METHODS: { value: TransferMethod; label: string }[] = [
  { value: 'mobile_transfer', label: 'Mobile transfer' },
  { value: 'email',           label: 'Email' },
];
const DURATION_OPTIONS: DurationHours[] = [1, 3, 6, 12, 24, 48];

// Confirmed platforms only — see TRANSFER_METHOD_RESEARCH.md. Miami-market order.
const TICKET_PLATFORMS: { value: TicketPlatform; label: string }[] = [
  { value: 'ticketmaster', label: 'Ticketmaster' },
  { value: 'tixr',         label: 'Tixr' },
  { value: 'dice',         label: 'DICE' },
  { value: 'posh',         label: 'Posh' },
  { value: 'eventbrite',   label: 'Eventbrite' },
  { value: 'axs',          label: 'AXS' },
  { value: 'seatgeek',     label: 'SeatGeek' },
  { value: 'mlb_ballpark', label: 'MLB Ballpark' },
  { value: 'fever',        label: 'Fever' },
  { value: 'shotgun',      label: 'Shotgun' },
  { value: 'universe',     label: 'Universe' },
  { value: 'see_tickets',  label: 'See Tickets' },
  { value: 'stubhub',      label: 'StubHub' },
  { value: 'vivid_seats',  label: 'Vivid Seats' },
  { value: 'gametime',     label: 'Gametime' },
  { value: 'other',        label: 'Other' },
];

// ─── Date/time helpers (unchanged) ──────────────────────────────────────────────

function defaultDate() { const d = new Date(); d.setHours(0, 0, 0, 0); return d; }
function defaultTime() { const d = new Date(); d.setHours(d.getHours() + 1, 0, 0, 0); return d; }
function fmtDate(d: Date) {
  return d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
}
function fmtTime(d: Date) {
  return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
}
/** "2025-08-15" */
function toDateStr(d: Date) { return d.toISOString().split('T')[0]; }
/** "21:00:00" */
function toTimeStr(d: Date) { return d.toTimeString().split(' ')[0]; }

// ─── Presentational building blocks (V2) ────────────────────────────────────────

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={sx.section}>
      <View style={sx.sectionHead}>
        <View style={sx.sectionRule} />
        <Text style={[textStyle('displaySm'), sx.sectionTitle]} accessibilityRole="header">
          {title}
        </Text>
      </View>
      <View style={sx.sectionBody}>{children}</View>
    </View>
  );
}

/** A tappable row that opens a sheet/picker. Label above, current value below. */
function SelectRow({
  label,
  value,
  placeholder,
  error,
  onPress,
}: {
  label: string;
  value: string | null;
  placeholder: string;
  error?: string;
  onPress: () => void;
}) {
  return (
    <View style={sx.field}>
      <Text style={[textStyle('micro'), sx.fieldLabel]}>{label}</Text>
      <Pressable
        onPress={onPress}
        style={[sx.selectRow, { borderBottomColor: error ? v2.status.error : v2.border.strong }]}
        accessibilityRole="button"
        accessibilityLabel={`${label}. ${value ?? placeholder}`}
      >
        <Text style={[textStyle('body'), value ? sx.selectValue : sx.selectPlaceholder]} numberOfLines={1}>
          {value ?? placeholder}
        </Text>
        <Text style={sx.chevron}>{'›'}</Text>
      </Pressable>
      {error ? (
        <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{error}</Text>
      ) : null}
    </View>
  );
}

/** Currency field: obvious "$", numeric keyboard, red underline on focus/error. */
function MoneyField({
  label,
  value,
  onChange,
  error,
  helper,
}: {
  label: string;
  value: string;
  onChange: (next: string) => void;
  error?: string;
  helper?: string;
}) {
  const [focused, setFocused] = useState(false);
  const underline = error ? v2.status.error : focused ? v2.brand.red : v2.border.strong;
  return (
    <View style={sx.field}>
      <Text style={[textStyle('micro'), sx.fieldLabel]}>{label}</Text>
      <View style={[sx.moneyRow, { borderBottomColor: underline }]}>
        <Text style={[textStyle('title'), sx.moneyPrefix]}>$</Text>
        <TextInput
          style={[textStyle('title') as TextStyle, sx.moneyInput]}
          value={value}
          onChangeText={(t) => onChange(digitsOnly(t))}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          keyboardType="number-pad"
          placeholder="0"
          placeholderTextColor={v2.text.faint}
          selectionColor={v2.brand.red}
          accessibilityLabel={label}
          accessibilityHint={error ?? helper}
        />
      </View>
      {error ? (
        <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{error}</Text>
      ) : helper ? (
        <Text style={[textStyle('bodySm'), sx.fieldHelper]}>{helper}</Text>
      ) : null}
    </View>
  );
}

/** Multiline free text, same underline aesthetic as Input. */
function MultilineField({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (t: string) => void;
  placeholder: string;
}) {
  const [focused, setFocused] = useState(false);
  return (
    <View style={sx.field}>
      <Text style={[textStyle('micro'), sx.fieldLabel]}>{label}</Text>
      <TextInput
        style={[
          textStyle('body') as TextStyle,
          sx.multiline,
          { borderBottomColor: focused ? v2.brand.red : v2.border.strong },
        ]}
        value={value}
        onChangeText={onChange}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        placeholder={placeholder}
        placeholderTextColor={v2.text.faint}
        selectionColor={v2.brand.red}
        multiline
        numberOfLines={3}
        accessibilityLabel={label}
      />
    </View>
  );
}

function ChipRow({ children }: { children: React.ReactNode }) {
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={sx.chipRow}
      keyboardShouldPersistTaps="handled"
    >
      {children}
    </ScrollView>
  );
}

function FieldLabel({ text }: { text: string }) {
  return <Text style={[textStyle('micro'), sx.groupLabel]}>{text}</Text>;
}

function ReviewRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={sx.reviewRow}>
      <Text style={[textStyle('bodySm'), sx.reviewKey]}>{label}</Text>
      <Text style={[textStyle('bodySm'), sx.reviewVal]} numberOfLines={1}>{value}</Text>
    </View>
  );
}

// ─── Screen ─────────────────────────────────────────────────────────────────────

export default function CreateListingScreen() {
  const { user } = useAuth();
  const insets = useSafeAreaInsets();
  // Lift the List ticket CTA above the floating dock: its own surface, clear gap.
  const ctaDockOffset = useCtaDockOffset();
  // Create participates in the universal adaptive collapse (device revision).
  const { onScroll: onDockScroll } = useDockScroll('create');

  // A — Event
  const [eventName,        setEventName]        = useState('');
  const [venue,            setVenue]            = useState('');
  const [neighborhood,     setNeighborhood]     = useState<Neighborhood | null>(null);
  const [neighborhoodOpen, setNeighborhoodOpen] = useState(false);
  const [neighborhoodQuery, setNeighborhoodQuery] = useState('');
  const [category,         setCategory]         = useState<EventCategory>('nightlife');
  const [platformOpen,     setPlatformOpen]     = useState(false);
  const [platformQuery,    setPlatformQuery]    = useState('');
  const [eventDate,        setEventDate]        = useState<Date>(defaultDate);
  const [eventTime,        setEventTime]        = useState<Date>(defaultTime);

  // B — Ticket
  const [ticketType,     setTicketType]     = useState<TicketType | null>(null);
  const [quantity,       setQuantity]       = useState(1);
  const [transferMethod, setTransferMethod] = useState<TransferMethod | null>(null);
  const [restrictions,   setRestrictions]   = useState('');

  // C — Pricing
  const [startingBid,   setStartingBid]   = useState('');
  const [buyNowEnabled, setBuyNowEnabled] = useState(false);
  const [buyNowPrice,   setBuyNowPrice]   = useState('');
  const [durationHours, setDurationHours] = useState<DurationHours | null>(null);

  // D — Platform & Trust
  const [ticketPlatform,           setTicketPlatform]           = useState<TicketPlatform>('other');
  const [sellerCommitmentAccepted, setSellerCommitmentAccepted] = useState(false);

  // E — Media
  const coverUpload = useImageUpload({ userId: user?.id ?? '', folder: 'covers', aspect: [16, 9], quality: 0.85 });
  const proofUpload = useImageUpload({
    userId: user?.id ?? '',
    folder: 'proofs',
    aspect: null,
    quality: 0.85,
    bucket: 'proof-docs', // PRIVATE bucket (migration 033) — owner + admin only
  });

  // Picker
  const [pickerMode,    setPickerMode]    = useState<'date' | 'time'>('date');
  const [pickerVisible, setPickerVisible] = useState(false);

  // Phase D — risk state
  const [riskWarningVisible, setRiskWarningVisible] = useState(false);
  const [riskBanner,         setRiskBanner]         = useState<{ reason: CanCreateListingReason; tier: RiskTier | null } | null>(null);
  const [riskCheckPassed,    setRiskCheckPassed]    = useState(false);

  // UI
  const [submitted, setSubmitted] = useState(false);
  const [loading,   setLoading]   = useState(false);

  const startingBidNum = parseAmount(startingBid);
  const buyNowPriceNum = parseAmount(buyNowPrice);

  // Validation — pure, from sellState
  const errors = useMemo(
    () =>
      sellErrors({
        eventName, venue, neighborhood, ticketType, transferMethod,
        startingBid, buyNowEnabled, buyNowPrice, durationHours,
        coverLocalUri: coverUpload.localUri,
        proofLocalUri: proofUpload.localUri,
        commitmentAccepted: sellerCommitmentAccepted,
      }),
    [eventName, venue, neighborhood, ticketType, transferMethod, startingBid,
     buyNowEnabled, buyNowPrice, durationHours, coverUpload.localUri,
     proofUpload.localUri, sellerCommitmentAccepted],
  );
  const isValid = isSellValid(errors);

  // The listing price a buyer transacts at: Buy Now price if set, else starting bid.
  const priceForPreview = buyNowEnabled && buyNowPriceNum > 0 ? buyNowPriceNum : startingBidNum;
  const summary = priceSummary(priceForPreview);

  // Date / time
  function openPicker(mode: 'date' | 'time') { setPickerMode(mode); setPickerVisible(true); }
  function onPickerChange(_e: DateTimePickerEvent, selected?: Date) {
    if (Platform.OS === 'android') setPickerVisible(false);
    if (!selected) return;
    if (pickerMode === 'date') setEventDate(selected);
    else setEventTime(selected);
  }

  // ── Phase D pre-submit risk check (unchanged behaviour) ─────────────────────
  async function runRiskCheck(): Promise<boolean> {
    if (!user) return false;

    const { data, error } = await supabase.rpc('can_create_listing', { p_seller_id: user.id });
    const result = parseRiskCheckResponse(data, error);

    switch (result.status) {
      case 'ok':
        setRiskBanner(null);
        return true;
      case 'transient':
        console.warn('[CreateListingScreen] risk check transient error — allowing submit:', result.message);
        setRiskBanner({ reason: 'medium_risk_warning', tier: null });
        return true;
      case 'bad_shape':
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

  // ── Publish (gate chain unchanged) ──────────────────────────────────────────
  async function handlePublish() {
    setSubmitted(true);
    if (!isValid || !user) return;

    // Content moderation gate (Guideline 1.4.3)
    const banned = findBannedContent([eventName, venue, restrictions]);
    if (banned) {
      const msg = `Listings can't mention "${banned}". Please revise your event name, venue, or restrictions and try again.`;
      if (Platform.OS === 'web') { window.alert(msg); } else { Alert.alert('Listing not allowed', msg); }
      return;
    }

    setLoading(true);

    try {
      // Gate 0: verified phone (trust step — matches the RLS guard in 038).
      const { data: authData } = await supabase.auth.getUser();
      if (!authData?.user?.phone_confirmed_at) {
        setLoading(false);
        const gateMsg = 'Verify your phone number to sell tickets on Snatch It.';
        if (Platform.OS === 'web') {
          if (window.confirm(`Phone Verification Required\n\n${gateMsg} Verify now?`)) {
            router.push('/settings/verify-phone' as never);
          }
        } else {
          Alert.alert('Phone Verification Required', gateMsg, [
            { text: 'Verify phone', onPress: () => router.push('/settings/verify-phone' as never) },
            { text: 'Cancel', style: 'cancel' },
          ]);
        }
        return;
      }

      // Gate: require FULLY connected Stripe payout account before listing.
      let payoutConnected = false;
      const { data: profile } = await supabase.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle();

      if (profile?.stripe_onboarding_complete) {
        payoutConnected = true;
      } else {
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
            'Payout Setup Required\n\nVerify your identity and add a bank account to get paid. This usually takes about 2 minutes. Go to payout setup now?',
          );
          if (goSetup) router.push('/settings/payout-setup');
        } else {
          Alert.alert(
            'Payout Setup Required',
            'Verify your identity and add a bank account to get paid. This usually takes about 2 minutes.',
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
      setRiskCheckPassed(false);

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
          ticket_platform:               ticketPlatform,
          proof_of_ownership_path:       proofPath,
          seller_commitment_accepted_at: sellerCommitmentAccepted ? new Date().toISOString() : null,
          category,
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

  /** Confirm past the high-risk warning modal. */
  function handleRiskWarningContinue() {
    setRiskWarningVisible(false);
    setRiskCheckPassed(true);
    handlePublish();
  }

  const busy = loading || coverUpload.status === 'uploading' || proofUpload.status === 'uploading';
  const platformLabel = TICKET_PLATFORMS.find((p) => p.value === ticketPlatform)?.label ?? null;

  // ────────────────────────────────────────────────────────────────────────────
  return (
    <KeyboardAvoidingView style={sx.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={[sx.header, { paddingTop: insets.top + v2.space.sm }]}>
        <Text style={[textStyle('displayMd'), sx.pageTitle]} accessibilityRole="header">Sell your ticket</Text>
      </View>

      <ScrollView
        contentContainerStyle={sx.scroll}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        onScroll={onDockScroll}
        scrollEventThrottle={16}
      >
        {/* ── EVENT ─────────────────────────────────────────── */}
        <Section title="Event">
          <Input
            label="Event name"
            placeholder="e.g. Weekend pool party"
            value={eventName}
            onChangeText={setEventName}
            error={submitted ? errors.eventName || null : null}
            returnKeyType="next"
          />
          <Input
            label="Venue"
            placeholder="e.g. LIV Miami"
            value={venue}
            onChangeText={setVenue}
            error={submitted ? errors.venue || null : null}
            returnKeyType="next"
          />
          <SelectRow
            label="Neighborhood"
            value={neighborhood ? NEIGHBORHOOD_LABELS[neighborhood] : null}
            placeholder="Select area or venue"
            error={submitted ? errors.neighborhood : undefined}
            onPress={() => setNeighborhoodOpen(true)}
          />
          <View style={sx.dateRow}>
            <View style={sx.dateCol}>
              <SelectRow label="Date" value={fmtDate(eventDate)} placeholder="Pick a date" onPress={() => openPicker('date')} />
            </View>
            <View style={sx.dateCol}>
              <SelectRow label="Time" value={fmtTime(eventTime)} placeholder="Pick a time" onPress={() => openPicker('time')} />
            </View>
          </View>
        </Section>

        {/* ── TICKET ────────────────────────────────────────── */}
        <Section title="Ticket">
          <FieldLabel text="Category" />
          <ChipRow>
            {CATEGORIES.map((c) => (
              <Chip key={c} label={CATEGORY_LABELS[c]} selected={category === c} onPress={() => setCategory(c)} />
            ))}
          </ChipRow>

          <FieldLabel text="Ticket type" />
          <View style={sx.inlineChips}>
            {TICKET_TYPES.map((t) => (
              <Chip key={t} label={t} selected={ticketType === t} onPress={() => setTicketType(t)} />
            ))}
          </View>
          {submitted && errors.ticketType ? (
            <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{errors.ticketType}</Text>
          ) : null}

          <FieldLabel text="Quantity" />
          <View style={sx.stepper}>
            <Pressable
              style={[sx.stepBtn, quantity <= 1 && sx.stepDisabled]}
              onPress={() => setQuantity((q) => Math.max(1, q - 1))}
              disabled={quantity <= 1}
              accessibilityRole="button"
              accessibilityLabel="Decrease quantity"
              hitSlop={6}
            >
              <Text style={sx.stepGlyph}>{'−'}</Text>
            </Pressable>
            <Text style={[textStyle('price'), sx.stepVal]} accessibilityLabel={`Quantity ${quantity}`}>{quantity}</Text>
            <Pressable
              style={sx.stepBtn}
              onPress={() => setQuantity((q) => q + 1)}
              accessibilityRole="button"
              accessibilityLabel="Increase quantity"
              hitSlop={6}
            >
              <Text style={sx.stepGlyph}>+</Text>
            </Pressable>
          </View>

          <FieldLabel text="Transfer method" />
          <View style={sx.inlineChips}>
            {TRANSFER_METHODS.map(({ value, label }) => (
              <Chip key={value} label={label} selected={transferMethod === value} onPress={() => setTransferMethod(value)} />
            ))}
          </View>
          {submitted && errors.transferMethod ? (
            <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{errors.transferMethod}</Text>
          ) : null}

          <SelectRow
            label="Ticket platform"
            value={platformLabel}
            placeholder="Select platform"
            onPress={() => setPlatformOpen(true)}
          />

          <MultilineField
            label="Restrictions (optional)"
            value={restrictions}
            onChange={setRestrictions}
            placeholder="e.g. 21+, no re-entry, dress code"
          />
        </Section>

        {/* ── SELLING METHOD + PRICE ────────────────────────── */}
        <Section title="Selling method">
          <Text style={[textStyle('bodySm'), sx.blurb]}>{sellingMethodBlurb(buyNowEnabled)}</Text>

          <MoneyField
            label="Starting bid"
            value={startingBid}
            onChange={setStartingBid}
            error={submitted ? errors.startingBid : undefined}
            helper={summary.valid && (!buyNowEnabled || buyNowPriceNum <= 0)
              ? `You get ${summary.sellerNet} · buyers pay ${summary.buyerAllInLabel}`
              : undefined}
          />

          <Pressable
            style={sx.toggleRow}
            onPress={() => { setBuyNowEnabled((v) => { const n = !v; if (!n) setBuyNowPrice(''); return n; }); }}
            accessibilityRole="switch"
            accessibilityState={{ checked: buyNowEnabled }}
            accessibilityLabel="Buy Now price"
          >
            <View style={sx.toggleText}>
              <Text style={[textStyle('title'), sx.toggleTitle]}>Buy Now price</Text>
              <Text style={[textStyle('bodySm'), sx.toggleHint]}>Let a buyer skip the auction</Text>
            </View>
            <Switch
              value={buyNowEnabled}
              onValueChange={(v) => { setBuyNowEnabled(v); if (!v) setBuyNowPrice(''); }}
              trackColor={{ false: v2.border.strong, true: v2.brand.red }}
              thumbColor={v2.text.primary}
              ios_backgroundColor={v2.border.strong}
            />
          </Pressable>

          {buyNowEnabled ? (
            <MoneyField
              label="Buy Now price"
              value={buyNowPrice}
              onChange={setBuyNowPrice}
              error={submitted ? errors.buyNowPrice : undefined}
              helper={summary.valid && buyNowPriceNum > 0
                ? `You get ${summary.sellerNet} · buyers pay ${summary.buyerAllInLabel}`
                : undefined}
            />
          ) : null}

          <FieldLabel text="Auction duration" />
          <ChipRow>
            {DURATION_OPTIONS.map((h) => (
              <Chip
                key={h}
                label={h < 24 ? `${h}h` : `${h / 24}d`}
                selected={durationHours === h}
                onPress={() => setDurationHours(h)}
              />
            ))}
          </ChipRow>
          {submitted && errors.durationHours ? (
            <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{errors.durationHours}</Text>
          ) : null}
        </Section>

        {/* ── PHOTOS ────────────────────────────────────────── */}
        <Section title="Photos">
          <MediaUpload
            variant="cover"
            localUri={coverUpload.localUri}
            status={coverUpload.status}
            error={coverUpload.error}
            onPress={coverUpload.pickImage}
            onRemove={coverUpload.reset}
            label="Cover image"
            helper="JPG or PNG, 16:9"
            icon="photo"
            hasError={submitted && !!errors.coverImage}
            disabled={busy}
          />
          {submitted && errors.coverImage ? (
            <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{errors.coverImage}</Text>
          ) : null}

          <MediaUpload
            variant="compact"
            localUri={proofUpload.localUri}
            status={proofUpload.status}
            error={proofUpload.error}
            onPress={proofUpload.pickImage}
            onRemove={proofUpload.reset}
            label="Proof of ownership"
            helper="Screenshot of the ticket or the confirmation email"
            icon="doc.text"
            hasError={submitted && !!errors.proofImage}
            disabled={busy}
          />
          {submitted && errors.proofImage ? (
            <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{errors.proofImage}</Text>
          ) : null}
        </Section>

        {/* ── CONFIRM ───────────────────────────────────────── */}
        <Section title="Confirm">
          <Pressable
            style={sx.commitRow}
            onPress={() => setSellerCommitmentAccepted((v) => !v)}
            accessibilityRole="checkbox"
            accessibilityState={{ checked: sellerCommitmentAccepted }}
            accessibilityLabel="I confirm I own these tickets and will transfer them within 24 hours of sale."
          >
            <View style={[sx.checkbox, sellerCommitmentAccepted && sx.checkboxOn]}>
              {sellerCommitmentAccepted ? <Text style={sx.checkMark}>{'✓'}</Text> : null}
            </View>
            <Text style={[textStyle('bodySm'), sx.commitText]}>
              I confirm I own these tickets and will transfer them within 24 hours of sale.
            </Text>
          </Pressable>
          {submitted && errors.commitment ? (
            <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{errors.commitment}</Text>
          ) : null}

          {/* Lightweight review — authoritative money helpers only */}
          {summary.valid ? (
            <View style={sx.reviewCard}>
              <ReviewRow label="Event" value={eventName.trim() || '—'} />
              <ReviewRow label="Tickets" value={ticketType ? `${quantity} × ${ticketType}` : `${quantity}`} />
              <ReviewRow label="Selling" value={buyNowEnabled ? 'Auction + Buy Now' : 'Auction'} />
              <ReviewRow label="Buyer pays" value={summary.buyerAllInLabel} />
              <ReviewRow label="You receive" value={`${summary.sellerNet} per ticket`} />
            </View>
          ) : null}

          {/* Risk banner */}
          {riskBanner && riskBanner.reason !== 'ok' ? (
            <View
              style={[
                sx.riskBanner,
                riskBanner.reason === 'medium_risk_warning' && sx.riskBannerMedium,
                riskBanner.reason === 'high_risk_warning' && sx.riskBannerHigh,
                (riskBanner.reason === 'critical_risk' || riskBanner.reason === 'listing_blocked') && sx.riskBannerCritical,
              ]}
              accessibilityRole="alert"
            >
              <Text style={[textStyle('bodySm'), sx.riskBannerText]}>
                {RISK_COPY[riskBanner.reason as keyof typeof RISK_COPY]}
              </Text>
            </View>
          ) : null}

          {submitted && !isValid ? (
            <Text style={[textStyle('bodySm'), sx.validationMsg]} accessibilityRole="alert">
              Fix the highlighted fields before listing.
            </Text>
          ) : null}
        </Section>
      </ScrollView>

      {/* ── Sticky publish bar ──────────────────────────────── */}
      <StickyBar
        // A separate transactional surface that ENDS above the floating dock with
        // a clear gap — never merged with navigation.
        style={{ marginBottom: ctaDockOffset, paddingBottom: v2.space.md }}
        left={
          <View>
            <Text style={[textStyle('micro'), sx.stickyKicker]}>{summary.valid ? 'You get' : 'Set a price'}</Text>
            {summary.valid ? (
              <Text style={[textStyle('price'), sx.stickyValue]} numberOfLines={1}>
                {summary.sellerNet}{quantity > 1 ? ' / ticket' : ''}
              </Text>
            ) : (
              <Text style={[textStyle('bodySm'), sx.stickyHint]} numberOfLines={1}>after the seller fee</Text>
            )}
          </View>
        }
      >
        <Button
          label={submitCtaLabel(quantity)}
          onPress={handlePublish}
          loading={busy}
          disabled={busy}
          block
        />
      </StickyBar>

      {/* ── Neighborhood sheet ──────────────────────────────── */}
      <Sheet
        visible={neighborhoodOpen}
        onClose={() => { setNeighborhoodOpen(false); setNeighborhoodQuery(''); }}
        title="Area or venue"
      >
        <Input
          label="Search"
          placeholder="Search areas and venues"
          value={neighborhoodQuery}
          onChangeText={setNeighborhoodQuery}
          autoCorrect={false}
        />
        <ScrollView style={sx.sheetList} keyboardShouldPersistTaps="handled">
          {NEIGHBORHOOD_GROUPS.map((group) => {
            const q = neighborhoodQuery.trim().toLowerCase();
            const items = q
              ? group.items.filter((n) => n.includes(q) || NEIGHBORHOOD_LABELS[n].toLowerCase().includes(q))
              : group.items;
            if (items.length === 0) return null;
            return (
              <View key={group.title}>
                <Text style={[textStyle('micro'), sx.sheetGroup]}>{group.title}</Text>
                {items.map((n) => {
                  const on = neighborhood === n;
                  return (
                    <Pressable
                      key={n}
                      style={[sx.sheetRow, on && sx.sheetRowOn]}
                      onPress={() => { setNeighborhood(n); setNeighborhoodOpen(false); setNeighborhoodQuery(''); }}
                      accessibilityRole="button"
                      accessibilityState={{ selected: on }}
                    >
                      <Text style={[textStyle('body'), on ? sx.sheetRowTextOn : sx.sheetRowText]}>
                        {NEIGHBORHOOD_LABELS[n]}
                      </Text>
                      {on ? <Text style={sx.sheetCheck}>{'✓'}</Text> : null}
                    </Pressable>
                  );
                })}
              </View>
            );
          })}
        </ScrollView>
      </Sheet>

      {/* ── Platform sheet ──────────────────────────────────── */}
      <Sheet
        visible={platformOpen}
        onClose={() => { setPlatformOpen(false); setPlatformQuery(''); }}
        title="Ticket platform"
      >
        <Input
          label="Search"
          placeholder="Search platforms"
          value={platformQuery}
          onChangeText={setPlatformQuery}
          autoCorrect={false}
        />
        <ScrollView style={sx.sheetList} keyboardShouldPersistTaps="handled">
          {TICKET_PLATFORMS
            .filter(({ label }) => {
              const q = platformQuery.trim().toLowerCase();
              return !q || label.toLowerCase().includes(q);
            })
            .map(({ value, label }) => {
              const on = ticketPlatform === value;
              return (
                <Pressable
                  key={value}
                  style={[sx.sheetRow, on && sx.sheetRowOn]}
                  onPress={() => { setTicketPlatform(value); setPlatformOpen(false); setPlatformQuery(''); }}
                  accessibilityRole="button"
                  accessibilityState={{ selected: on }}
                >
                  <Text style={[textStyle('body'), on ? sx.sheetRowTextOn : sx.sheetRowText]}>{label}</Text>
                  {on ? <Text style={sx.sheetCheck}>{'✓'}</Text> : null}
                </Pressable>
              );
            })}
        </ScrollView>
      </Sheet>

      {/* ── Date / time picker ──────────────────────────────── */}
      {Platform.OS === 'ios' ? (
        <Sheet
          visible={pickerVisible}
          onClose={() => setPickerVisible(false)}
          title={pickerMode === 'date' ? 'Event date' : 'Event time'}
        >
          <DateTimePicker
            value={pickerMode === 'date' ? eventDate : eventTime}
            mode={pickerMode}
            display="spinner"
            textColor={v2.text.primary}
            onChange={onPickerChange}
            minimumDate={pickerMode === 'date' ? new Date() : undefined}
          />
        </Sheet>
      ) : (
        pickerVisible && (
          <DateTimePicker
            value={pickerMode === 'date' ? eventDate : eventTime}
            mode={pickerMode}
            display="default"
            onChange={onPickerChange}
            minimumDate={pickerMode === 'date' ? new Date() : undefined}
          />
        )
      )}

      {/* ── High-risk warning ───────────────────────────────── */}
      <Sheet visible={riskWarningVisible} onClose={() => setRiskWarningVisible(false)} title="Account under review">
        <Text style={[textStyle('body'), sx.riskModalBody]}>{RISK_COPY.high_risk_warning}</Text>
        <View style={sx.riskModalActions}>
          <Button label="Cancel" variant="secondary" onPress={() => setRiskWarningVisible(false)} style={sx.riskModalBtn} />
          <Button label="Continue anyway" onPress={handleRiskWarningContinue} style={sx.riskModalBtn} />
        </View>
      </Sheet>
    </KeyboardAvoidingView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const sx = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },

  header: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.md },
  pageTitle: { color: v2.text.primary },

  scroll: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.xxxl },

  section: { marginTop: v2.space.xl },
  sectionHead: { marginBottom: v2.space.lg },
  sectionRule: { height: 1, backgroundColor: v2.border.default, marginBottom: v2.space.md },
  sectionTitle: { color: v2.text.primary },
  sectionBody: { gap: v2.space.lg },

  field: { alignSelf: 'stretch' },
  fieldLabel: { color: v2.text.muted, marginBottom: v2.space.xs },
  fieldError: { color: v2.status.error, marginTop: v2.space.xs },
  fieldHelper: { color: v2.text.muted, marginTop: v2.space.xs },
  groupLabel: { color: v2.text.muted, marginBottom: v2.space.sm },

  selectRow: {
    minHeight: 50,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottomWidth: 1,
    paddingVertical: v2.space.sm,
  },
  selectValue: { color: v2.text.primary, flex: 1 },
  selectPlaceholder: { color: v2.text.faint, flex: 1 },
  chevron: { color: v2.text.muted, fontSize: 22, marginLeft: v2.space.sm },

  dateRow: { flexDirection: 'row', gap: v2.space.lg },
  dateCol: { flex: 1 },

  moneyRow: { flexDirection: 'row', alignItems: 'center', borderBottomWidth: 1, paddingVertical: v2.space.sm },
  moneyPrefix: { color: v2.text.muted, marginRight: v2.space.xs },
  moneyInput: { flex: 1, color: v2.text.primary, padding: 0 },

  multiline: {
    minHeight: 76,
    color: v2.text.primary,
    borderBottomWidth: 1,
    paddingVertical: v2.space.sm,
    textAlignVertical: 'top',
  },

  chipRow: { gap: v2.space.sm, paddingRight: v2.space.lg },
  inlineChips: { flexDirection: 'row', gap: v2.space.sm },

  stepper: { flexDirection: 'row', alignItems: 'center', gap: v2.space.xl },
  stepBtn: {
    width: 44, height: 44,
    borderWidth: 1, borderColor: v2.border.strong,
    alignItems: 'center', justifyContent: 'center',
  },
  stepDisabled: { opacity: 0.35 },
  stepGlyph: { color: v2.text.primary, fontSize: 24, lineHeight: 28 },
  stepVal: { color: v2.text.primary, minWidth: 32, textAlign: 'center' },

  blurb: { color: v2.text.secondary },

  toggleRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: v2.border.default,
    paddingVertical: v2.space.md,
  },
  toggleText: { flex: 1, marginRight: v2.space.md },
  toggleTitle: { color: v2.text.primary },
  toggleHint: { color: v2.text.muted, marginTop: 2 },

  commitRow: { flexDirection: 'row', alignItems: 'flex-start' },
  checkbox: {
    width: 22, height: 22,
    borderWidth: 2, borderColor: v2.border.strong,
    alignItems: 'center', justifyContent: 'center',
    marginRight: v2.space.sm, marginTop: 1,
  },
  checkboxOn: { backgroundColor: v2.brand.red, borderColor: v2.brand.red },
  checkMark: { color: v2.text.inverse, fontSize: 14, fontWeight: '700', lineHeight: 18 },
  commitText: { flex: 1, color: v2.text.secondary },

  reviewCard: {
    borderWidth: 1, borderColor: v2.border.default, backgroundColor: v2.surface.surface,
    padding: v2.space.md, gap: v2.space.sm, marginTop: v2.space.md,
  },
  reviewRow: { flexDirection: 'row', justifyContent: 'space-between', gap: v2.space.md },
  reviewKey: { color: v2.text.muted },
  reviewVal: { color: v2.text.primary, flexShrink: 1, textAlign: 'right' },

  riskBanner: { padding: v2.space.md, marginTop: v2.space.md, borderWidth: 1 },
  riskBannerMedium:   { backgroundColor: '#332B00', borderColor: '#665500' },
  riskBannerHigh:     { backgroundColor: '#331A00', borderColor: '#663300' },
  riskBannerCritical: { backgroundColor: '#330000', borderColor: '#660000' },
  riskBannerText: { color: '#FFDDBB' },

  validationMsg: { color: v2.status.error, textAlign: 'center', marginTop: v2.space.md },

  stickyKicker: { color: v2.text.muted },
  stickyValue: { color: v2.text.primary, marginTop: 2 },
  stickyHint: { color: v2.text.muted, marginTop: 2 },

  sheetList: { marginTop: v2.space.sm, maxHeight: 380 },
  sheetGroup: { color: v2.text.faint, paddingTop: v2.space.md, paddingBottom: v2.space.xs },
  sheetRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    minHeight: 48, paddingVertical: v2.space.sm,
    borderBottomWidth: 1, borderBottomColor: v2.border.default,
  },
  sheetRowOn: { backgroundColor: v2.brand.redSoft },
  sheetRowText: { color: v2.text.primary },
  sheetRowTextOn: { color: v2.brand.red },
  sheetCheck: { color: v2.brand.red, fontSize: 16, fontWeight: '700' },

  riskModalBody: { color: v2.text.secondary },
  riskModalActions: { flexDirection: 'row', gap: v2.space.sm, marginTop: v2.space.md },
  riskModalBtn: { flex: 1 },
});
