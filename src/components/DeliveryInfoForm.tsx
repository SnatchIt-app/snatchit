/**
 * src/components/DeliveryInfoForm.tsx
 *
 * Collects the buyer's delivery email and/or phone number for ticket
 * transfer. Shown on the receive screen when delivery info is missing.
 *
 * Phase A — migration 011
 */

import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { TransferMethod } from '@/src/types';
import {
  formatPhoneDisplay,
  isValidUSPhone,
  normalizeUSPhone,
  PHONE_DISPLAY_MAXLENGTH,
  toPhoneDigits,
} from '@/src/utils/phone';

// ─── Props ───────────────────────────────────────────────────────────────────

export interface DeliveryInfoFormProps {
  /** Controls which fields to show. email → email field, mobile_transfer → phone field. */
  transferMethod: TransferMethod;
  /** Called when the buyer submits their delivery info. */
  onSubmit: (email: string | null, phone: string | null) => void;
  /** Disables the form while a network call is in progress. */
  loading?: boolean;
}

// ─── Component ───────────────────────────────────────────────────────────────

export default function DeliveryInfoForm({
  transferMethod,
  onSubmit,
  loading = false,
}: DeliveryInfoFormProps) {
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');

  const showEmail = transferMethod === 'email';
  const showPhone = transferMethod === 'mobile_transfer';

  function handleSubmit() {
    const trimEmail = email.trim() || null;
    // Normalize at the boundary — always store a clean 10-digit string or
    // null. If the validator was somehow bypassed, this returns null and
    // the upstream RPC stores null rather than a malformed value.
    const normalizedPhone = showPhone ? normalizeUSPhone(phone) : null;

    if (showEmail && !trimEmail) return;
    if (showPhone && !normalizedPhone) return;

    onSubmit(trimEmail, normalizedPhone);
  }

  const phoneValid = isValidUSPhone(phone);
  const canSubmit =
    (showEmail ? email.trim().length > 0 : true) &&
    (showPhone ? phoneValid : true);

  // Inline error: only after the user has typed something invalid.
  // Empty input is "not yet ready", not "wrong" — don't flash an error.
  const phoneErrorText =
    showPhone && phone.length > 0 && !phoneValid
      ? 'Enter a valid 10-digit US phone number.'
      : null;

  return (
    <View style={s.container}>
      <Text style={s.title}>Where should the seller send your tickets?</Text>
      <Text style={s.subtitle}>
        The seller needs your info to transfer the tickets.
      </Text>

      {showEmail && (
        <>
          <Text style={s.label}>Email for ticket transfer</Text>
          <TextInput
            style={s.input}
            placeholder="you@example.com"
            placeholderTextColor={colors.textPlaceholder}
            value={email}
            onChangeText={setEmail}
            keyboardType="email-address"
            autoCapitalize="none"
            autoCorrect={false}
            editable={!loading}
          />
        </>
      )}

      {showPhone && (
        <>
          <Text style={s.label}>Phone number for ticket transfer</Text>
          {/* Internal state `phone` is digits-only. TextInput renders the
              formatted display while the user types and accepts pasted
              numbers in any common format. */}
          <TextInput
            style={s.input}
            placeholder="(305) 555-1234"
            placeholderTextColor={colors.textPlaceholder}
            value={formatPhoneDisplay(phone)}
            onChangeText={(v) => setPhone(toPhoneDigits(v))}
            keyboardType="phone-pad"
            textContentType="telephoneNumber"
            autoComplete="tel-national"
            maxLength={PHONE_DISPLAY_MAXLENGTH}
            editable={!loading}
          />
          {phoneErrorText && <Text style={s.errorText}>{phoneErrorText}</Text>}
        </>
      )}

      <Pressable
        style={[s.submitBtn, (!canSubmit || loading) && s.submitBtnDisabled]}
        onPress={handleSubmit}
        disabled={!canSubmit || loading}
      >
        {loading ? (
          <ActivityIndicator color={colors.text} size="small" />
        ) : (
          <Text style={s.submitBtnText}>Save Delivery Info</Text>
        )}
      </Pressable>
    </View>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  container: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
  },
  title: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '700',
    marginBottom: spacing.xs,
  },
  subtitle: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    marginBottom: spacing.md,
  },
  label: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    fontWeight: '600',
    marginBottom: spacing.xs,
  },
  input: {
    backgroundColor: colors.bgInput,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderInput,
    color: colors.text,
    fontSize: fontSize.md,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  errorText: {
    color: colors.error,
    fontSize: fontSize.xs,
    marginTop: -spacing.sm,
    marginBottom: spacing.md,
  },
  submitBtn: {
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: 14,
    alignItems: 'center',
  },
  submitBtnDisabled: {
    opacity: 0.5,
  },
  submitBtnText: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '700',
  },
});
