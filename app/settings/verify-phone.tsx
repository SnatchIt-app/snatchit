/**
 * app/settings/verify-phone.tsx — SMS phone verification (V2).
 *
 * PRESENTATION rebuilt on the V2 system; the auth path is unchanged. The
 * phone_change OTP flow is preserved exactly: `updateUser({ phone })` sends the
 * code, `verifyOtp({ type: 'phone_change' })` confirms it, with the 30s resend
 * cooldown, the already-verified check, and the same rate/expired/invalid error
 * mapping. No custom SMS provider; Twilio stays configured in Supabase. The number
 * is verification-only and never shown on public profiles.
 *
 * ROUTING CONTRACT. This screen is entered with a session and keeps it the whole
 * way through, so no step of it is a sign-in. `updateUser({ phone })` makes
 * Supabase emit `USER_UPDATED`, which used to move the root layout and threw the
 * person onto Home the instant the code was sent. The root layout now navigates
 * only on a change of authentication phase (src/lib/auth/rootRoute.ts), so this
 * screen keeps control: the send advances to the code step itself, and the
 * completion returns where the person came from rather than to Home.
 */

import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { formatPhoneDisplay, isValidUSPhone, normalizeUSPhone, PHONE_DISPLAY_MAXLENGTH } from '@/src/utils/phone';
import { Badge, Button, Input } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

const RESEND_COOLDOWN_S = 30;

type Step = 'enter_phone' | 'enter_code' | 'verified';

export default function VerifyPhoneScreen() {
  const { user } = useAuth();

  const [step, setStep] = useState<Step>('enter_phone');
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [errMsg, setErrMsg] = useState('');
  const [cooldown, setCooldown] = useState(0);
  const cooldownRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      if (data?.user?.phone_confirmed_at && data.user.phone) {
        setPhone(data.user.phone.replace(/^\+?1/, ''));
        setStep('verified');
      }
    }).catch(() => { /* fall through */ });
  }, []);

  useEffect(() => () => { if (cooldownRef.current) clearInterval(cooldownRef.current); }, []);

  function startCooldown() {
    setCooldown(RESEND_COOLDOWN_S);
    cooldownRef.current = setInterval(() => {
      setCooldown((c) => {
        if (c <= 1 && cooldownRef.current) clearInterval(cooldownRef.current);
        return Math.max(0, c - 1);
      });
    }, 1000);
  }

  const e164 = `+1${phone}`;

  async function sendCode() {
    if (!isValidUSPhone(phone)) { setErrMsg('Enter a valid US mobile number.'); return; }
    setBusy(true);
    setErrMsg('');
    const { error } = await supabase.auth.updateUser({ phone: e164 });
    setBusy(false);
    if (error) {
      setErrMsg(/rate|too many/i.test(error.message) ? 'Too many attempts. Please wait a few minutes and try again.' : error.message);
      return;
    }
    startCooldown();
    setStep('enter_code');
  }

  async function verifyCode() {
    if (code.trim().length !== 6) { setErrMsg('Enter the 6-digit code from the text message.'); return; }
    setBusy(true);
    setErrMsg('');
    const { error } = await supabase.auth.verifyOtp({ phone: e164, token: code.trim(), type: 'phone_change' });
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

    // The app-side copy of the number is written only now, after the provider
    // accepted the code. Sending an SMS is not verification, so nothing is
    // recorded on the send. Same column Edit profile and Sign up write; no
    // second copy is introduced.
    const normalized = normalizeUSPhone(phone);
    if (user && normalized) {
      const { error: syncErr } = await supabase
        .from('profiles')
        .update({ phone_number: normalized })
        .eq('id', user.id);
      if (syncErr) console.warn('[verify-phone] profile sync failed:', syncErr.message);
    }

    Alert.alert('Phone verified', 'Your number is verified. You can now sell tickets on Snatch It.');
  }

  /**
   * Back to wherever this was opened from — Settings, or Create listing. Falls
   * back to Settings rather than assuming the stack has something to pop, and
   * never to Home: this flow started inside the authenticated app and ends there.
   */
  function leaveVerification() {
    if (router.canGoBack()) router.back();
    else router.replace('/settings');
  }

  return (
    <View style={s.root}>
      <SettingsHeader title="Phone verification" />
      <KeyboardAvoidingView style={s.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.body} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag" showsVerticalScrollIndicator={false}>
        {step === 'verified' ? <Badge label="Verified" tone="success" /> : null}

        {step === 'enter_phone' ? (
          <>
            <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">Verify your phone</Text>
            <Text style={[textStyle('body'), s.subtitle]}>
              We&apos;ll text you a 6-digit code. Verifying your number keeps the marketplace safe. It&apos;s never shown on your profile or used for marketing.
            </Text>
            <Input
              label="Mobile number"
              value={formatPhoneDisplay(phone)}
              onChangeText={(t) => setPhone(normalizeUSPhone(t) ?? '')}
              placeholder="(305) 555-1234"
              keyboardType="phone-pad"
              textContentType="telephoneNumber"
              autoComplete="tel-national"
              maxLength={PHONE_DISPLAY_MAXLENGTH}
              autoFocus
              containerStyle={s.field}
            />
            {errMsg ? <Text style={[textStyle('bodySm'), s.error]} accessibilityRole="alert">{errMsg}</Text> : null}
            <Button label="Send code" onPress={sendCode} loading={busy} disabled={busy || !isValidUSPhone(phone)} block style={s.cta} />
          </>
        ) : null}

        {step === 'enter_code' ? (
          <>
            <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">Enter the code</Text>
            <Text style={[textStyle('body'), s.subtitle]}>We sent a 6-digit code to {formatPhoneDisplay(phone)}.</Text>
            <Input
              label="Code"
              value={code}
              onChangeText={(t) => setCode(t.replace(/\D/g, '').slice(0, 6))}
              placeholder="123456"
              keyboardType="number-pad"
              textContentType="oneTimeCode"
              maxLength={6}
              autoFocus
              containerStyle={s.field}
            />
            {errMsg ? <Text style={[textStyle('bodySm'), s.error]} accessibilityRole="alert">{errMsg}</Text> : null}
            <Button label="Verify" onPress={verifyCode} loading={busy} disabled={busy || code.length !== 6} block style={s.cta} />
            <Button
              label={cooldown > 0 ? `Resend code in ${cooldown}s` : 'Resend code'}
              variant="ghost"
              onPress={sendCode}
              disabled={busy || cooldown > 0}
              block
            />
            <Button label="Use a different number" variant="ghost" onPress={() => { setStep('enter_phone'); setCode(''); setErrMsg(''); }} block />
          </>
        ) : null}

        {step === 'verified' ? (
          <>
            <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">Phone verified</Text>
            <Text style={[textStyle('body'), s.subtitle]}>
              {formatPhoneDisplay(phone)} is verified on your account. You can now sell tickets on Snatch It.
            </Text>
            <Button label="Done" onPress={leaveVerification} block style={s.cta} />
          </>
        ) : null}

        {!user ? <Text style={[textStyle('bodySm'), s.error]}>You need to be signed in to verify a phone number.</Text> : null}
      </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  flex: { flex: 1 },
  body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.xl, gap: v2.space.md },
  title: { color: v2.text.primary, marginTop: v2.space.sm },
  subtitle: { color: v2.text.secondary },
  field: { marginTop: v2.space.sm },
  error: { color: v2.status.error },
  cta: { marginTop: v2.space.sm },
});
