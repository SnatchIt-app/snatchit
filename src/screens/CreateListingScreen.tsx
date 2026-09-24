/**
 * src/screens/CreateListingScreen.tsx — Sell your ticket (V3 surface, V2 logic).
 *
 * PRESENTATION on the V3 boards (`pkg7-create-after.png` composition, `pkg8-create-dark/light`
 * tokens, `pkg3-create-invalid.png` validation states); the SUBMISSION path is unchanged.
 * Every gate in `handlePublish` — verified-phone, connected-payout, the
 * `can_create_listing` risk check, content moderation, the cover + proof uploads,
 * the `public.listings` insert and the navigate-to-detail — is the same logic in
 * the same order it has always run. The whole-dollars listing contract, the fee
 * math and the RPC/edge-function calls are untouched.
 *
 * V3 (2026-09-24): sentence-case title in the screen-title voice; section heads are quiet
 * uppercase eyebrows (the boards keep eyebrows uppercase — the display voice left this screen);
 * transfer method is a picker ROW opening a sheet, like neighborhood and platform (board
 * annotation ②: "pickers are rows, not dropdowns"); date and time stack full-width; quantity
 * sits on the ticket-type row with a rounded stepper; money DISPLAY faces carry cents through
 * sellState's V3 formatters; panels and controls take the role radii. All colours are palette
 * roles, so both appearances render from the one stylesheet.
 *
 * The pure decisions (validation, moderation, risk parsing, money preview) live in
 * src/lib/sell/sellState.ts where they are tested. Imported by the thin route
 * wrapper app/(tabs)/create.tsx.
 *
 * HARNESS FIXTURE (`fixture` prop): passed only by `app/_dev/v3-search-create.tsx`. It seeds
 * form state so the board's filled/invalid/risk-banner states render, and it makes the screen
 * PREVIEW-ONLY: `handlePublish` returns before its first gate, so the harness can never walk
 * the submit chain against a server. The live route (`app/(tabs)/create.tsx`) passes no
 * fixture, and the live submit path is untouched.
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
import { useKeyboardUp } from '@/src/hooks/useKeyboardUp';
import { ctaLift } from '@/src/lib/nav/keyboardLift';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useImageUpload } from '@/src/hooks/useImageUpload';
import { useSingleFlight } from '@/src/hooks/useSingleFlight';
import { Button, Chip, Input, MediaUpload, Sheet, StickyBar } from '@/src/components/ui';
import { useDockScroll } from '@/src/components/nav/dockContext';
import { useCtaDockOffset, useTopInset } from '@/src/lib/nav/navInsets';
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
  proceedsBasis,
  proceedsKicker,
} from '@/src/lib/sell/sellState';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
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
//
// These sit outside the screen function, so the resolved styles (and, where a colour
// is applied inline, the palette) are handed to them as props — never read from
// module scope, and never through a hook outside a component.

/** The screen's resolved stylesheet, built by makeStyles() from the live palette. */
type SellStyles = ReturnType<typeof makeStyles>;

function Section({ title, children, sx }: { title: string; children: React.ReactNode; sx: SellStyles }) {
  // V3: the section head is a quiet uppercase EYEBROW (`label`), not the V2 Oswald display —
  // the boards keep eyebrows and tabs uppercase while every action went sentence case. The
  // rule above it is gone; sections separate with space.
  return (
    <View style={sx.section}>
      <Text style={[textStyle('label'), sx.sectionTitle]} accessibilityRole="header">
        {title}
      </Text>
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
  sx,
  p,
}: {
  label: string;
  value: string | null;
  placeholder: string;
  error?: string;
  onPress: () => void;
  sx: SellStyles;
  p: Palette;
}) {
  return (
    <View style={sx.field}>
      <Text style={[textStyle('micro'), sx.fieldLabel]}>{label}</Text>
      <Pressable
        onPress={onPress}
        style={[sx.selectRow, { borderBottomColor: error ? p.status.error : p.border.control }]}
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
  sx,
  p,
}: {
  label: string;
  value: string;
  onChange: (next: string) => void;
  error?: string;
  helper?: string;
  sx: SellStyles;
  p: Palette;
}) {
  const [focused, setFocused] = useState(false);
  const underline = error ? p.status.error : focused ? p.brand.red : p.border.control;
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
          placeholderTextColor={p.text.faint}
          selectionColor={p.brand.red}
          accessibilityLabel={label}
          accessibilityHint={error ?? helper}
        />
      </View>
      {error ? (
        <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{error}</Text>
      ) : helper ? (
        // V3: the buyer-side line sits in the board's filled rounded panel, not as bare
        // helper text — it is the other party's number, so it gets its own surface.
        <View style={sx.helperPanel}>
          <Text style={[textStyle('bodySm'), sx.fieldHelper]}>{helper}</Text>
        </View>
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
  sx,
  p,
}: {
  label: string;
  value: string;
  onChange: (t: string) => void;
  placeholder: string;
  sx: SellStyles;
  p: Palette;
}) {
  const [focused, setFocused] = useState(false);
  return (
    <View style={sx.field}>
      <Text style={[textStyle('micro'), sx.fieldLabel]}>{label}</Text>
      <TextInput
        style={[
          textStyle('body') as TextStyle,
          sx.multiline,
          { borderBottomColor: focused ? p.brand.red : p.border.control },
        ]}
        value={value}
        onChangeText={onChange}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        placeholder={placeholder}
        placeholderTextColor={p.text.faint}
        selectionColor={p.brand.red}
        multiline
        numberOfLines={3}
        accessibilityLabel={label}
      />
    </View>
  );
}

function ChipRow({ children, sx }: { children: React.ReactNode; sx: SellStyles }) {
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

function FieldLabel({ text, sx }: { text: string; sx: SellStyles }) {
  return <Text style={[textStyle('micro'), sx.groupLabel]}>{text}</Text>;
}

function ReviewRow({ label, value, sx }: { label: string; value: string; sx: SellStyles }) {
  return (
    <View style={sx.reviewRow}>
      <Text style={[textStyle('bodySm'), sx.reviewKey]}>{label}</Text>
      <Text style={[textStyle('bodySm'), sx.reviewVal]} numberOfLines={1}>{value}</Text>
    </View>
  );
}

// ─── Screen ─────────────────────────────────────────────────────────────────────

/**
 * Harness-only fixture (see the header note). Seeds presentation state so the dev route can
 * render the board's filled, invalid and risk-banner states; its presence makes the screen
 * preview-only. Never passed by the live route.
 */
export interface CreateFixture {
  form?: {
    eventName?: string;
    venue?: string;
    neighborhood?: Neighborhood | null;
    eventDate?: Date;
    eventTime?: Date;
    ticketType?: TicketType | null;
    quantity?: number;
    transferMethod?: TransferMethod | null;
    ticketPlatform?: TicketPlatform;
    startingBid?: string;
    durationHours?: DurationHours | null;
    commitmentAccepted?: boolean;
  };
  submitted?: boolean;
  riskBanner?: { reason: CanCreateListingReason | 'check_unavailable'; tier: RiskTier | null };
}

export default function CreateListingScreen({ fixture }: { fixture?: CreateFixture } = {}) {
  const { user } = useAuth();
  const { palette } = useTheme();
  const sx = useMemo(() => makeStyles(palette), [palette]);
  const topPad = useTopInset();
  // Lift the List ticket CTA above the floating dock: its own surface, clear gap —
  // but not while a keyboard is up (F-SELL-1): the dock hides then, and the lift
  // became a ~160 pt blank gap between the bar and the keyboard on build 17.
  const ctaDockOffset = useCtaDockOffset();
  const keyboardUp = useKeyboardUp();
  // Create participates in the universal adaptive collapse (device revision).
  const { onScroll: onDockScroll } = useDockScroll('create');

  // A — Event. Initializers may come from the harness fixture; the live route passes none.
  const fx = fixture?.form;
  const [eventName,        setEventName]        = useState(fx?.eventName ?? '');
  const [venue,            setVenue]            = useState(fx?.venue ?? '');
  const [neighborhood,     setNeighborhood]     = useState<Neighborhood | null>(fx?.neighborhood ?? null);
  const [neighborhoodOpen, setNeighborhoodOpen] = useState(false);
  const [neighborhoodQuery, setNeighborhoodQuery] = useState('');
  const [category,         setCategory]         = useState<EventCategory>('nightlife');
  const [platformOpen,     setPlatformOpen]     = useState(false);
  const [platformQuery,    setPlatformQuery]    = useState('');
  const [eventDate,        setEventDate]        = useState<Date>(fx?.eventDate ?? defaultDate);
  const [eventTime,        setEventTime]        = useState<Date>(fx?.eventTime ?? defaultTime);

  // B — Ticket
  const [ticketType,     setTicketType]     = useState<TicketType | null>(fx?.ticketType ?? null);
  const [quantity,       setQuantity]       = useState(fx?.quantity ?? 1);
  const [transferMethod, setTransferMethod] = useState<TransferMethod | null>(fx?.transferMethod ?? null);
  const [transferOpen,   setTransferOpen]   = useState(false);
  const [restrictions,   setRestrictions]   = useState('');

  // C — Pricing
  const [startingBid,   setStartingBid]   = useState(fx?.startingBid ?? '');
  const [buyNowEnabled, setBuyNowEnabled] = useState(false);
  const [buyNowPrice,   setBuyNowPrice]   = useState('');
  const [durationHours, setDurationHours] = useState<DurationHours | null>(fx?.durationHours ?? null);

  // D — Platform & Trust
  const [ticketPlatform,           setTicketPlatform]           = useState<TicketPlatform>(fx?.ticketPlatform ?? 'other');
  const [sellerCommitmentAccepted, setSellerCommitmentAccepted] = useState(fx?.commitmentAccepted ?? false);

  // E — Media
  const coverUpload = useImageUpload({ userId: user?.id ?? '', folder: 'covers', aspect: [16, 9], quality: 0.85 });
  const proofUpload = useImageUpload({
    userId: user?.id ?? '',
    folder: 'proofs',
    aspect: null,
    quality: 0.85,
    bucket: 'proof-docs', // PRIVATE bucket (migration 033) — owner + admin only
  });

  // F-IMG-1: one publish at a time (repeated taps and the risk-modal confirm share it).
  const publishFlight = useSingleFlight();

  // Picker
  const [pickerMode,    setPickerMode]    = useState<'date' | 'time'>('date');
  const [pickerVisible, setPickerVisible] = useState(false);

  // Phase D — risk state
  const [riskWarningVisible, setRiskWarningVisible] = useState(false);
  // The banner shows either a server verdict or the client's own "the check did not answer" state.
  // `check_unavailable` is deliberately NOT added to CanCreateListingReason: the server never sends
  // it, and widening the server contract to carry a client state is how the two got confused.
  const [riskBanner,         setRiskBanner]         = useState<{ reason: CanCreateListingReason | 'check_unavailable'; tier: RiskTier | null } | null>(fixture?.riskBanner ?? null);
  const [riskCheckPassed,    setRiskCheckPassed]    = useState(false);

  // UI
  const [submitted, setSubmitted] = useState(fixture?.submitted ?? false);
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

  // Both blocked reasons get the identical treatment and the identical action: they differ in origin
  // — an admin restriction against a computed tier — but not in what the seller can do about either.
  const riskBlocked = riskBanner != null
    && (riskBanner.reason === 'critical_risk' || riskBanner.reason === 'listing_blocked');

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
        // Fails open, as before. The banner says the check did not answer; it does not report a
        // verdict the server never gave.
        setRiskBanner({ reason: 'check_unavailable', tier: null });
        return true;
      case 'bad_shape': {
        console.error('[CreateListingScreen] risk check returned unexpected shape:', JSON.stringify(result.raw));
        const msg = 'Unable to verify your account status. Please try again.';
        if (Platform.OS === 'web') { window.alert(msg); } else { Alert.alert('Something went wrong', msg); }
        return false;
      }
      case 'block': {
        setRiskBanner({ reason: result.reason, tier: result.tier });
        // "Contact support" is an instruction, so the app offers the route — the same courtesy the
        // phone-verification and payout gates in this function already extend. The two blocked
        // reasons differ in origin (an admin restriction vs a computed tier) but not in what the
        // seller can do about either, so they keep one sentence and one treatment.
        const msg = RISK_COPY[result.reason as keyof typeof RISK_COPY];
        if (Platform.OS === 'web') {
          window.alert(msg);
        } else {
          Alert.alert('Listing blocked', msg, [
            { text: 'Not now', style: 'cancel' },
            { text: 'Contact support', onPress: () => router.push('/settings/support') },
          ]);
        }
        return false;
      }
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
    // Harness renders are preview-only: with a fixture mounted, the submit chain is never
    // entered, so the dev route cannot fire the gates or the insert against a server. The
    // live route passes no fixture and takes the unchanged path below.
    if (fixture) return;
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
        const msg = coverUpload.readError() ?? 'Unknown upload error — check console for details.';
        console.error('[CreateListingScreen] cover upload failed:', msg);
        if (Platform.OS === 'web') { window.alert(msg); } else { Alert.alert('Upload failed', msg); }
        return;
      }

      // 1b. Upload proof of ownership image
      const proofPath = await proofUpload.uploadImage();
      if (!proofPath) {
        const msg = proofUpload.readError() ?? 'Unknown upload error — check console for details.';
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
    void publishFlight.run(handlePublish);
  }

  const busy = loading || coverUpload.busy || proofUpload.busy;
  const platformLabel = TICKET_PLATFORMS.find((p) => p.value === ticketPlatform)?.label ?? null;

  // ────────────────────────────────────────────────────────────────────────────
  return (
    <KeyboardAvoidingView style={sx.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={[sx.header, { paddingTop: topPad + v2.space.sm }]}>
        {/* V3: the title speaks the screen-title voice — sentence case, bold sans — as the
            boards draw it. The display voice (Oswald) now belongs to event names only. */}
        <Text style={[textStyle('screenTitle'), sx.pageTitle]} accessibilityRole="header">Sell your ticket</Text>
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
        <Section title="Event" sx={sx}>
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
            sx={sx}
            p={palette}
          />
          {/* V3 (pkg7-create-after): date and time stack full width like every other picker
              row — the two-column pair was the V2 layout. */}
          <SelectRow label="Date" value={fmtDate(eventDate)} placeholder="Pick a date" onPress={() => openPicker('date')} sx={sx} p={palette} />
          <SelectRow label="Time" value={fmtTime(eventTime)} placeholder="Pick a time" onPress={() => openPicker('time')} sx={sx} p={palette} />
        </Section>

        {/* ── TICKET ────────────────────────────────────────── */}
        <Section title="Ticket" sx={sx}>
          <FieldLabel text="Category" sx={sx} />
          <ChipRow sx={sx}>
            {CATEGORIES.map((c) => (
              <Chip key={c} label={CATEGORY_LABELS[c]} selected={category === c} onPress={() => setCategory(c)} />
            ))}
          </ChipRow>

          <FieldLabel text="Ticket type" sx={sx} />
          {/* V3 (pkg8-create): quantity shares the ticket-type row, right-aligned. The board's
              static "Quantity 2" gains its working stepper here — rounded per the role radii —
              because a mock does not need to change the number and a seller does. */}
          <View style={sx.ticketTypeRow}>
            <View style={sx.inlineChips}>
              {TICKET_TYPES.map((t) => (
                <Chip key={t} label={t} selected={ticketType === t} onPress={() => setTicketType(t)} />
              ))}
            </View>
            <View style={sx.quantityGroup}>
              <Text style={[textStyle('bodySm'), sx.quantityWord]}>Quantity</Text>
              <Pressable
                style={[sx.stepBtn, quantity <= 1 && sx.stepDisabled]}
                onPress={() => setQuantity((q) => Math.max(1, q - 1))}
                disabled={quantity <= 1}
                accessibilityRole="button"
                accessibilityLabel="Decrease quantity"
                hitSlop={8}
              >
                <Text style={sx.stepGlyph}>{'−'}</Text>
              </Pressable>
              <Text style={[textStyle('price'), sx.stepVal]} accessibilityLabel={`Quantity ${quantity}`}>{quantity}</Text>
              <Pressable
                style={sx.stepBtn}
                onPress={() => setQuantity((q) => q + 1)}
                accessibilityRole="button"
                accessibilityLabel="Increase quantity"
                hitSlop={8}
              >
                <Text style={sx.stepGlyph}>+</Text>
              </Pressable>
            </View>
          </View>
          {submitted && errors.ticketType ? (
            <Text style={[textStyle('bodySm'), sx.fieldError]} accessibilityRole="alert">{errors.ticketType}</Text>
          ) : null}

          {/* V3 (board annotation ②): pickers are rows, not inline choices — transfer method
              opens a sheet like neighborhood and platform. Same two values, same state. */}
          <SelectRow
            label="Transfer method"
            value={TRANSFER_METHODS.find((m) => m.value === transferMethod)?.label ?? null}
            placeholder="Select transfer method"
            error={submitted ? errors.transferMethod : undefined}
            onPress={() => setTransferOpen(true)}
            sx={sx}
            p={palette}
          />

          <SelectRow
            label="Ticket platform"
            value={platformLabel}
            placeholder="Select platform"
            onPress={() => setPlatformOpen(true)}
            sx={sx}
            p={palette}
          />

          <MultilineField
            label="Restrictions (optional)"
            value={restrictions}
            onChange={setRestrictions}
            placeholder="e.g. 21+, no re-entry, dress code"
            sx={sx}
            p={palette}
          />
        </Section>

        {/* ── SELLING METHOD + PRICE ────────────────────────── */}
        <Section title="Selling method" sx={sx}>
          <Text style={[textStyle('bodySm'), sx.blurb]}>{sellingMethodBlurb(buyNowEnabled)}</Text>

          <MoneyField
            label="Starting bid"
            value={startingBid}
            onChange={setStartingBid}
            error={submitted ? errors.startingBid : undefined}
            // "from" (A, 2026-09-24): this figure is the all-in on the STARTING bid, and an auction
            // settles on the winning one, which can only be higher.
            helper={summary.valid && (!buyNowEnabled || buyNowPriceNum <= 0)
              ? `Buyers pay from ${summary.buyerAllInLabel}`
              : undefined}
            sx={sx}
            p={palette}
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
              trackColor={{ false: palette.border.control, true: palette.brand.red }}
              thumbColor={palette.onArt.primary}
              ios_backgroundColor={palette.border.control}
            />
          </Pressable>

          {buyNowEnabled ? (
            <MoneyField
              label="Buy Now price"
              value={buyNowPrice}
              onChange={setBuyNowPrice}
              error={submitted ? errors.buyNowPrice : undefined}
              helper={summary.valid && buyNowPriceNum > 0
                ? `Buyers pay ${summary.buyerAllInLabel}`
                : undefined}
              sx={sx}
              p={palette}
            />
          ) : null}

          <FieldLabel text="Auction duration" sx={sx} />
          <ChipRow sx={sx}>
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
        <Section title="Photos" sx={sx}>
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
        <Section title="Confirm" sx={sx}>
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
          {/* R-4 (owner 2026-09-23): the card keeps its purpose — it renders only when the form
              is valid, reviewing WHAT will be listed. The money sides are stated once elsewhere
              (buyer side on the price field, seller net at the sticky), so they are not repeated. */}
          {summary.valid ? (
            <View style={sx.reviewCard}>
              <ReviewRow label="Event" value={eventName.trim() || '—'} sx={sx} />
              <ReviewRow label="Tickets" value={ticketType ? `${quantity} × ${ticketType}` : `${quantity}`} sx={sx} />
              <ReviewRow label="Selling" value={buyNowEnabled ? 'Auction + Buy Now' : 'Auction'} sx={sx} />
            </View>
          ) : null}

          {/* Risk banner */}
          {riskBanner && riskBanner.reason !== 'ok' ? (
            <View
              style={[
                sx.riskBanner,
                riskBanner.reason === 'check_unavailable' && sx.riskBannerNeutral,
                riskBanner.reason === 'medium_risk_warning' && sx.riskBannerMedium,
                riskBanner.reason === 'high_risk_warning' && sx.riskBannerHigh,
                riskBlocked && sx.riskBannerCritical,
              ]}
              accessibilityRole="alert"
            >
              <Text style={[textStyle('bodySm'), sx.riskBannerText]}>
                {RISK_COPY[riskBanner.reason as keyof typeof RISK_COPY]}
              </Text>
              {/* The alert is dismissible and this banner is not, so the instruction needs its route
                  here as well. Identical for both blocked reasons, so which one the seller is in
                  stays unexposed. */}
              {riskBlocked ? (
                <Pressable
                  onPress={() => router.push('/settings/support')}
                  accessibilityRole="button"
                  accessibilityLabel="Contact support"
                  hitSlop={8}
                  style={sx.riskBannerAction}
                >
                  <Text style={[textStyle('bodySm'), sx.riskBannerActionText]}>Contact support</Text>
                </Pressable>
              ) : null}
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
        style={{ marginBottom: ctaLift({ keyboardUp, dockOffset: ctaDockOffset }), paddingBottom: v2.space.md }}
        left={
          <View>
            {summary.valid ? (
              <>
                <Text style={[textStyle('micro'), sx.stickyKicker]}>{proceedsKicker(quantity)}</Text>
                <Text style={[textStyle('price'), sx.stickyValue]} numberOfLines={1}>
                  {summary.sellerNet}
                </Text>
                {/* The one fee clause: the seller net's basis, beside the figure being decided. For an
                    auction-only listing that basis is a FLOOR — the preview is computed on the starting
                    bid and the server pays on the winning one (A's ruling, 2026-09-24). */}
                <Text style={[textStyle('micro'), sx.stickyHint]} numberOfLines={2}>
                  {proceedsBasis({ buyNowEnabled, buyNowPriceSet: buyNowPriceNum > 0 })}
                </Text>
              </>
            ) : submitted ? (
              // §1: one validation summary, at the action, only after a submit found failures.
              <Text style={[textStyle('bodySm'), sx.stickySummary]} numberOfLines={2}>
                Fix the highlighted fields before listing.
              </Text>
            ) : (
              <Text style={[textStyle('micro'), sx.stickyKicker]}>Set a price</Text>
            )}
          </View>
        }
      >
        <Button
          label={submitCtaLabel(quantity)}
          size="lg"
          onPress={() => { void publishFlight.run(handlePublish); }}
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

      {/* ── Transfer method sheet (V3: picker row, like platform) ── */}
      <Sheet
        visible={transferOpen}
        onClose={() => setTransferOpen(false)}
        title="Transfer method"
      >
        <ScrollView style={sx.sheetList} keyboardShouldPersistTaps="handled">
          {TRANSFER_METHODS.map(({ value, label }) => {
            const on = transferMethod === value;
            return (
              <Pressable
                key={value}
                style={[sx.sheetRow, on && sx.sheetRowOn]}
                onPress={() => { setTransferMethod(value); setTransferOpen(false); }}
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
            textColor={palette.text.primary}
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

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },

  header: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.md },
  pageTitle: { color: p.text.primary },

  scroll: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.xxxl },

  section: { marginTop: v2.space.xl },
  // V3: the eyebrow head — uppercase `label`, muted, no rule; sections separate with space.
  sectionTitle: { color: p.text.muted, marginBottom: v2.space.lg },
  sectionBody: { gap: v2.space.lg },

  field: { alignSelf: 'stretch' },
  fieldLabel: { color: p.text.muted, marginBottom: v2.space.xs },
  fieldError: { color: p.status.error, marginTop: v2.space.xs },
  fieldHelper: { color: p.text.secondary },
  // V3: the buyer-side money line's filled rounded panel (pkg8-create boards).
  helperPanel: {
    backgroundColor: p.surface.elevated,
    borderRadius: v2.radius.sm,
    paddingVertical: v2.space.md,
    paddingHorizontal: v2.space.lg,
    marginTop: v2.space.md,
  },
  groupLabel: { color: p.text.muted, marginBottom: v2.space.sm },

  selectRow: {
    minHeight: 50,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottomWidth: 1,
    paddingVertical: v2.space.sm,
  },
  selectValue: { color: p.text.primary, flex: 1 },
  selectPlaceholder: { color: p.text.muted, flex: 1 },
  chevron: { color: p.text.muted, fontSize: 22, marginLeft: v2.space.sm },

  moneyRow: { flexDirection: 'row', alignItems: 'center', borderBottomWidth: 1, paddingVertical: v2.space.sm },
  moneyPrefix: { color: p.text.muted, marginRight: v2.space.xs },
  moneyInput: { flex: 1, color: p.text.primary, padding: 0 },

  multiline: {
    minHeight: 76,
    color: p.text.primary,
    borderBottomWidth: 1,
    paddingVertical: v2.space.sm,
    textAlignVertical: 'top',
  },

  chipRow: { gap: v2.space.sm, paddingRight: v2.space.lg },
  inlineChips: { flexDirection: 'row', gap: v2.space.sm },

  // V3: quantity shares the ticket-type row; the stepper keys are rounded (`md`, the stepper
  // radius the bid screen set) — the 44pt squares were V2. hitSlop restores the 44pt target.
  ticketTypeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: v2.space.sm,
    flexWrap: 'wrap',
  },
  quantityGroup: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm, marginLeft: 'auto' },
  quantityWord: { color: p.text.secondary, marginRight: v2.space.xs },
  stepBtn: {
    width: 36, height: 36,
    borderRadius: v2.radius.md,
    borderWidth: 1, borderColor: p.border.control,
    alignItems: 'center', justifyContent: 'center',
  },
  stepDisabled: { opacity: 0.35 },
  stepGlyph: { color: p.text.primary, fontSize: 20, lineHeight: 24 },
  stepVal: { color: p.text.primary, minWidth: 28, textAlign: 'center' },

  blurb: { color: p.text.secondary },

  toggleRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: p.border.default,
    paddingVertical: v2.space.md,
  },
  toggleText: { flex: 1, marginRight: v2.space.md },
  toggleTitle: { color: p.text.primary },
  toggleHint: { color: p.text.muted, marginTop: 2 },

  commitRow: { flexDirection: 'row', alignItems: 'flex-start' },
  // V3: rounded, and checked is the board's high-contrast fill — primary ink with canvas
  // check, which flips with the appearance. Red stays for actions, not acknowledgements.
  checkbox: {
    width: 24, height: 24,
    borderRadius: v2.radius.sm,
    borderWidth: 2, borderColor: p.border.control,
    alignItems: 'center', justifyContent: 'center',
    marginRight: v2.space.sm, marginTop: 1,
  },
  checkboxOn: { backgroundColor: p.text.primary, borderColor: p.text.primary },
  checkMark: { color: p.surface.canvas, fontSize: 14, fontWeight: '700', lineHeight: 18 },
  commitText: { flex: 1, color: p.text.secondary },

  reviewCard: {
    borderWidth: 1, borderColor: p.border.default, backgroundColor: p.surface.surface,
    borderRadius: v2.radius.md,
    padding: v2.space.md, gap: v2.space.sm, marginTop: v2.space.md,
  },
  reviewRow: { flexDirection: 'row', justifyContent: 'space-between', gap: v2.space.md },
  reviewKey: { color: p.text.muted },
  reviewVal: { color: p.text.primary, flexShrink: 1, textAlign: 'right' },

  riskBanner: { padding: v2.space.md, marginTop: v2.space.md, borderWidth: 1, borderRadius: v2.radius.md },
  // The edge is a status token, so it is graded in both appearances (6.07–11.48:1 on the canvas).
  // My first pass used translucent literals: they composite over either canvas, but ungraded they
  // measured 1.32–1.75:1 in Daylight, and the three fills were 1.03–1.07:1 against EACH OTHER — a
  // severity ranking that nobody could see. The tier is carried by three different sentences
  // (RISK_COPY) inside an accessibilityRole="alert", so the colour layer only owes a legible edge.
  // "The check did not answer" is not a caution about the seller, so it does not borrow one.
  riskBannerNeutral:  { borderColor: p.border.control },
  riskBannerMedium:   { borderColor: p.status.warning },
  riskBannerHigh:     { borderColor: p.status.error },
  riskBannerCritical: { borderColor: p.status.error },
  riskBannerText: { color: p.text.primary },
  riskBannerAction: { marginTop: v2.space.sm, alignSelf: 'flex-start' },
  riskBannerActionText: { color: p.brand.redText, textDecorationLine: 'underline' },

  validationMsg: { color: p.status.error, textAlign: 'center', marginTop: v2.space.md },

  stickyKicker: { color: p.text.muted },
  stickyValue: { color: p.text.primary, marginTop: 2 },
  stickyHint: { color: p.text.muted, marginTop: 2 },
  stickySummary: { color: p.status.error },

  sheetList: { marginTop: v2.space.sm, maxHeight: 380 },
  sheetGroup: { color: p.text.muted, paddingTop: v2.space.md, paddingBottom: v2.space.xs },
  sheetRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    minHeight: 48, paddingVertical: v2.space.sm,
    borderBottomWidth: 1, borderBottomColor: p.border.default,
  },
  sheetRowOn: { backgroundColor: p.brand.redSoft },
  sheetRowText: { color: p.text.primary },
  sheetRowTextOn: { color: p.brand.redText },
  sheetCheck: { color: p.brand.redText, fontSize: 16, fontWeight: '700' },

  riskModalBody: { color: p.text.secondary },
  riskModalActions: { flexDirection: 'row', gap: v2.space.sm, marginTop: v2.space.md },
  riskModalBtn: { flex: 1 },
  });
}
