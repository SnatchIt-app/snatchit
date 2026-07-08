/**
 * app/settings/verify-phone.tsx — SMS phone verification (Supabase Phone Auth)
 *
 * Trust step for sellers — email/password remains the primary auth. Attaches
 * a verified phone to the EXISTING account via the phone_change OTP flow:
 *   1. supabase.auth.updateUser({ phone: '+1XXXXXXXXXX' })  → Supabase sends OTP
 *   2. supabase.auth.verifyOtp({ phone, token, type: 'phone_change' })
 *      → sets auth.users.phone + phone_confirmed_at
 *
 * Server truth: auth.users.phone_confirmed_at (read by the RLS guard in
 * migration 038 via public.phone_verified()). No custom SMS provider code —
 * Twilio is configured in the Supabase dashboard only.
 *
 * Privacy: the number is used ONLY for verification. Never shown on public
 * profiles, never used for marketing.
 */

import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import {
  formatPhoneDisplay,
  isValidUSPhone,
  normalizeUSPhone,
  PHONE_DISPLAY_MAXLENGTH,
} from '@/src/utils/phone';
import { colors, fontSize, radius, spacing } from '@/src/theme';

const RESEND_COOLDOWN_S = 30;

type Step = 'enter_phone' | 'enter_code' | 'verified';

export default function VerifyPhoneScreen() {
  const { user } = useAuth();

  const [step, setStep]         = useState<Step>('enter_phone');
  const [phone, setPhone]       = useState('');   // 10 digits, no +1
  const [code, setCode]         = useState('');
  const [busy, setBusy]         = useState(false);
  const [errMsg, setErrMsg]     = useState('');
  const [cooldown, setCooldown] = useState(0);
  const cooldownRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Already verified? (fresh check — the cached session user can be stale)
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      if (data?.user?.phone_confirmed_at && data.user.phone) {
        setPhone(data.user.phone.replace(/^\+?1/, ''));
        setStep('verified');
      }
    }).catch(() => { /* fall through to enter_phone */ });
  }, []);

  useEffect(() => () => { if (cooldownRef.current) clearInterval(cooldownRef.current); }, []);

  function startCooldown() {
    setCooldown(RESEND_COOLDOWN_S);
    cooldownRef.current = setInterval(() => {
      setCooldown(c => {
        if (c <= 1 && cooldownRef.current) clearInterval(cooldownRef.current);
        return Math.max(0, c - 1);
      });
    }, 1000);
  }

  const e164 = `+1${phone}`;

  async function sendCode() {
    if (!isValidUSPhone(phone)) {
      setErrMsg('Enter a valid US mobile number.');
      return;
    }
    setBusy(true);
    setErrMsg('');
    // phone_change flow: attaches the number to the signed-in account.
    const { error } = await supabase.auth.updateUser({ phone: e164 });
    setBusy(false);
    if (error) {
      setErrMsg(
        /rate|too many/i.test(error.message)
          ? 'Too many attempts. Please wait a few minutes and try again.'
          : error.message,
      );
      return;
    }
    startCooldown();
    setStep('enter_code');
  }

  async function verifyCode() {
    if (code.trim().length !== 6) {
      setErrMsg('Enter the 6-digit code from the text message.');
      return;
    }
    setBusy(true);
    setErrMsg('');
    const { error } = await supabase.auth.verifyOtp({
      phone: e164,
      token: code.trim(),
      type: 'phone_change',
    });
    setBusy(false);
    if (error) {
      setErrMsg(
        /expired/i.test(error.message) ? 'That code expired. Tap Resend to get a new one.'
        : /invalid/i.test(error.message) ? "That code didn't match. Check the text and try again."
        : error.message,
      );
      return;
    }
    setStep('verified');
    Alert.alert('Phone verified', 'Your number is verified. You can now sell tickets on Snatch It.');
  }

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'←'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Phone Verification</Text>
        <View style={s.backBtn} />
      </View>

      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled">
        <View style={s.iconCircle}>
          <Text style={s.icon}>{step === 'verified' ? '✅' : '📱'}</Text>
        </View>

        {step === 'enter_phone' && (
          <>
            <Text style={s.title}>Verify your phone</Text>
            <Text style={s.subtitle}>
              {"We'll text you a 6-digit code. Verifying your number keeps the marketplace safe — it's never shown on your profile or used for marketing."}
            </Text>
            <TextInput
              style={s.input}
              value={formatPhoneDisplay(phone)}
              onChangeText={t => setPhone(normalizeUSPhone(t) ?? '')}
              placeholder="(305) 555-1234"
              placeholderTextColor={colors.textMuted}
              keyboardType="phone-pad"
              maxLength={PHONE_DISPLAY_MAXLENGTH}
              autoFocus
            />
            {!!errMsg && <Text style={s.error}>{errMsg}</Text>}
            <Pressable
              style={[s.primaryBtn, (busy || !isValidUSPhone(phone)) && s.btnDisabled]}
              onPress={sendCode}
              disabled={busy || !isValidUSPhone(phone)}
            >
              {busy ? <ActivityIndicator color={colors.text} size="small" />
                    : <Text style={s.primaryBtnText}>Send Code</Text>}
            </Pressable>
          </>
        )}

        {step === 'enter_code' && (
          <>
            <Text style={s.title}>Enter the code</Text>
            <Text style={s.subtitle}>
              We sent a 6-digit code to {formatPhoneDisplay(phone)}.
            </Text>
            <TextInput
              style={[s.input, s.codeInput]}
              value={code}
              onChangeText={t => setCode(t.replace(/\D/g, '').slice(0, 6))}
              placeholder="••••••"
              placeholderTextColor={colors.textMuted}
              keyboardType="number-pad"
              maxLength={6}
              autoFocus
            />
            {!!errMsg && <Text style={s.error}>{errMsg}</Text>}
            <Pressable
              style={[s.primaryBtn, (busy || code.length !== 6) && s.btnDisabled]}
              onPress={verifyCode}
              disabled={busy || code.length !== 6}
            >
              {busy ? <ActivityIndicator color={colors.text} size="small" />
                    : <Text style={s.primaryBtnText}>Verify</Text>}
            </Pressable>
            <Pressable
              style={s.linkBtn}
              onPress={sendCode}
              disabled={busy || cooldown > 0}
            >
              <Text style={[s.linkText, cooldown > 0 && { color: colors.textMuted }]}>
                {cooldown > 0 ? `Resend code in ${cooldown}s` : 'Resend code'}
              </Text>
            </Pressable>
            <Pressable style={s.linkBtn} onPress={() => { setStep('enter_phone'); setCode(''); setErrMsg(''); }}>
              <Text style={s.linkText}>Use a different number</Text>
            </Pressable>
          </>
        )}

        {step === 'verified' && (
          <>
            <Text style={s.title}>Phone verified</Text>
            <Text style={s.subtitle}>
              {formatPhoneDisplay(phone)} is verified on your account. {"You're"} all set to sell tickets.
            </Text>
            <Pressable style={s.primaryBtn} onPress={() => router.back()}>
              <Text style={s.primaryBtnText}>Done</Text>
            </Pressable>
          </>
        )}

        {!user && (
          <Text style={s.error}>You need to be signed in to verify a phone number.</Text>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe:   { flex: 1, backgroundColor: colors.bg },
  topBar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
            paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
            borderBottomWidth: 1, borderBottomColor: colors.border },
  backBtn:   { width: 40, alignItems: 'flex-start' },
  backArrow: { color: colors.text, fontSize: 22 },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  body: { padding: spacing.lg, alignItems: 'center', gap: spacing.sm },
  iconCircle: {
    width: 72, height: 72, borderRadius: 36,
    backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.border,
    alignItems: 'center', justifyContent: 'center', marginVertical: spacing.md,
  },
  icon:     { fontSize: 30 },
  title:    { fontSize: fontSize.lg, fontWeight: '800', color: colors.text, textAlign: 'center' },
  subtitle: { fontSize: fontSize.sm, color: colors.textMuted, textAlign: 'center', lineHeight: 20 },

  input: {
    alignSelf: 'stretch',
    backgroundColor: colors.bgInput,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    color: colors.text,
    fontSize: fontSize.lg,
    paddingVertical: 14,
    paddingHorizontal: spacing.md,
    textAlign: 'center',
    marginTop: spacing.md,
  },
  codeInput: { letterSpacing: 8, fontWeight: '800' },

  error: { color: colors.error, fontSize: fontSize.sm, textAlign: 'center', marginTop: spacing.xs },

  primaryBtn: {
    alignSelf: 'stretch',
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: 14,
    marginTop: spacing.md,
  },
  btnDisabled:    { opacity: 0.5 },
  primaryBtnText: { color: colors.text, fontWeight: '700', fontSize: fontSize.md },

  linkBtn:  { paddingVertical: spacing.sm },
  linkText: { color: colors.primary, fontSize: fontSize.sm, fontWeight: '600' },
});
