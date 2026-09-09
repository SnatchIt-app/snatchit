/**
 * app/(auth)/signup.tsx — Create account (V2).
 *
 * Sign up is where the account is built: email, password, name, mobile number, a
 * real verification of that number, and gender. Sign in then asks for none of it.
 *
 * FOUR STEPS, ONE SCREEN. Account, about you, number, verify. The steps exist so
 * seven fields do not arrive at once; the product requirement is about what gets
 * captured, so the boundaries can move without changing the contract.
 *
 * WHY THE ACCOUNT IS CREATED AT STEP 1. Linking a phone to an identity and writing
 * a profile both need a session. `signUp` returns one immediately on this project
 * (`mailer_autoconfirm`), so the later steps write to the real account through the
 * ordinary contracts. If confirmation is ever turned back on, `signUp` returns no
 * session, the flow stops at `check_email`, and nothing downstream is attempted.
 * While the flow is mid air, `setOnboarding(true)` holds the root redirect so the
 * new session does not throw the person onto Home with three steps unanswered.
 *
 * THE VERIFICATION IS REAL. `updateUser({ phone })` sends the code and
 * `verifyOtp({ type: 'phone_change' })` checks it, the same contract the shipped
 * settings/verify-phone screen uses, against the same Supabase phone provider. The
 * number becomes part of the authenticated identity (`auth.users.phone` +
 * `phone_confirmed_at`), which is exactly what phone sign-in later looks up.
 * Nothing here marks a number verified on its own say-so.
 *
 * The 18+ gate and the Terms / Privacy disclosure are unchanged and still gate the
 * account-creation step.
 */

import { Link, router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { Button, Input } from '@/src/components/ui';
import { friendlyAuthError } from '@/src/lib/auth/authForms';
import {
  canResend,
  classifyOtpError,
  otpErrorCopy,
  RESEND_COOLDOWN_S,
  resendLabel,
  toE164US,
} from '@/src/lib/auth/phoneAuth';
import {
  canGoBack,
  DEMOGRAPHIC_NOTICE_VERSION,
  nextStep,
  prevStep,
  SIGNUP_STEP_COUNT,
  stepIndex,
  validateAboutStep,
  validateAccountStep,
  validateCodeStep,
  type GenderValue,
  type SignupStep,
} from '@/src/lib/auth/signupFlow';
import { setOnboarding } from '@/src/lib/auth/onboardingGate';
import { AuthScreen } from '@/src/components/auth/AuthScreen';
import { GenderSelect } from '@/src/components/auth/GenderSelect';
import { formatPhoneDisplay, normalizeUSPhone, PHONE_DISPLAY_MAXLENGTH } from '@/src/utils/phone';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';


export default function SignUpScreen() {
  const [step, setStep] = useState<SignupStep>('account');

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [ageConfirmed, setAgeConfirmed] = useState(false);

  const [name, setName] = useState('');
  const [gender, setGender] = useState<GenderValue | null>(null);

  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [cooldown, setCooldown] = useState(0);
  const cooldownRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ text: string; type: 'error' | 'success' } | null>(null);

  // Never leave the root redirect held because a screen went away.
  useEffect(() => () => {
    setOnboarding(false);
    if (cooldownRef.current) clearInterval(cooldownRef.current);
  }, []);

  function startCooldown() {
    setCooldown(RESEND_COOLDOWN_S);
    if (cooldownRef.current) clearInterval(cooldownRef.current);
    cooldownRef.current = setInterval(() => {
      setCooldown((c) => {
        if (c <= 1 && cooldownRef.current) clearInterval(cooldownRef.current);
        return Math.max(0, c - 1);
      });
    }, 1000);
  }

  const fail = (text: string) => setMessage({ text, type: 'error' });

  /** Step 1. Creates the account, then holds the router so the flow can finish. */
  async function submitAccount() {
    const invalid = validateAccountStep(email, password, ageConfirmed);
    if (invalid) { fail(invalid); return; }

    setLoading(true);
    setMessage(null);
    setOnboarding(true);

    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: { emailRedirectTo: 'snatchit://' },
    });

    setLoading(false);

    if (error) {
      setOnboarding(false);
      fail(friendlyAuthError(error.message));
      return;
    }

    if (!data.session) {
      // Email confirmation is required on this project: the remaining steps need a
      // session, so the flow ends here rather than writing to nothing.
      setOnboarding(false);
      setStep('check_email');
      setMessage({ text: 'Account created. Check your email to confirm, then sign in.', type: 'success' });
      return;
    }

    setStep('about');
  }

  /** Step 2. Held locally until the phone is verified, then written together. */
  function submitAbout() {
    const invalid = validateAboutStep(name, gender);
    if (invalid) { fail(invalid); return; }
    setMessage(null);
    setStep(nextStep('about'));
  }

  /** Step 3. Sends the real code through the account's own phone-change contract. */
  async function sendCode() {
    const e164 = toE164US(phone);
    if (!e164) { fail(otpErrorCopy('invalid_number')); return; }

    setLoading(true);
    setMessage(null);

    const { error } = await supabase.auth.updateUser({ phone: e164 });

    setLoading(false);

    if (error) { fail(otpErrorCopy(classifyOtpError(error, 'send'))); return; }

    setCode('');
    startCooldown();
    setStep('verify');
  }

  /** Step 4. The provider checks the code; only then is anything persisted. */
  async function verifyAndFinish() {
    const e164 = toE164US(phone);
    const invalid = validateCodeStep(code);
    if (!e164) { fail(otpErrorCopy('invalid_number')); return; }
    if (invalid) { fail(invalid); return; }

    setLoading(true);
    setMessage(null);

    const { error } = await supabase.auth.verifyOtp({ phone: e164, token: code.trim(), type: 'phone_change' });

    if (error) {
      setLoading(false);
      fail(otpErrorCopy(classifyOtpError(error, 'verify')));
      return;
    }

    await persistProfile();

    setLoading(false);
    // Releasing the gate hands navigation back: _layout sees the session and
    // routes to Home.
    setOnboarding(false);
  }

  /**
   * Write what was collected to the fields that already own it. No new column, no
   * second copy: display_name and phone_number are the ones Edit profile writes,
   * and gender goes through the kernel demographics RPC, which is owner scoped and
   * validates the value itself.
   */
  async function persistProfile() {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const { error: profileErr } = await supabase
      .from('profiles')
      .update({ display_name: name.trim(), phone_number: normalizeUSPhone(phone) })
      .eq('id', user.id);
    if (profileErr) console.warn('[signup] profile write failed:', profileErr.message);

    if (gender) {
      const { error: genderErr } = await (supabase as any)
        .schema('kernel')
        .rpc('set_my_demographics', {
          p_gender_identity: gender,
          p_notice_version: DEMOGRAPHIC_NOTICE_VERSION,
        });
      if (genderErr) console.warn('[signup] demographics write failed:', genderErr.message);
    }
  }

  const messageRow = message ? (
    <Text
      style={[textStyle('bodySm'), message.type === 'error' ? s.error : s.success]}
      accessibilityRole="alert"
    >
      {message.text}
    </Text>
  ) : null;

  const backRow = canGoBack(step) ? (
    <Pressable onPress={() => { setMessage(null); setStep(prevStep(step)); }} style={s.alt} hitSlop={8} accessibilityRole="button">
      <Text style={[textStyle('bodySm'), s.altText]}>Back</Text>
    </Pressable>
  ) : null;

  const progress = stepIndex(step) >= 0 ? (
    <Text style={[textStyle('micro'), s.progress]}>Step {stepIndex(step) + 1} of {SIGNUP_STEP_COUNT}</Text>
  ) : null;

  return (
    <AuthScreen>
      {progress}

      {step === 'account' ? (
        <>
          <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">Create account</Text>

          <View style={s.fields}>
            <Input
              label="Email"
              placeholder="you@email.com"
              value={email}
              onChangeText={setEmail}
              keyboardType="email-address"
              autoCapitalize="none"
              autoComplete="email"
              textContentType="username"
              returnKeyType="next"
            />
            <Input
              label="Password"
              placeholder="At least 6 characters"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              autoCapitalize="none"
              autoComplete="new-password"
              textContentType="newPassword"
              returnKeyType="done"
            />
          </View>

          {messageRow}

          {/* 18+ confirmation — App Store Guideline 1.4.3 / 18+ marketplace */}
          <Pressable
            style={s.ageRow}
            onPress={() => setAgeConfirmed((v) => !v)}
            hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            accessibilityRole="checkbox"
            accessibilityLabel="I confirm I am 18 years of age or older"
            accessibilityState={{ checked: ageConfirmed }}
          >
            <View style={[s.checkbox, ageConfirmed && s.checkboxOn]}>
              {ageConfirmed ? <Text style={s.checkMark}>{'✓'}</Text> : null}
            </View>
            <Text style={[textStyle('bodySm'), s.ageText]}>I confirm I am 18 years of age or older.</Text>
          </Pressable>

          {/* Legal disclosure — App Store Guideline 5.1.1 */}
          <Text style={[textStyle('bodySm'), s.legal]}>
            By creating an account you agree to our{' '}
            <Text style={s.legalLink} onPress={() => router.push('/settings/legal')} accessibilityRole="link">Terms of Service</Text>
            {' '}and{' '}
            <Text style={s.legalLink} onPress={() => router.push('/settings/privacy')} accessibilityRole="link">Privacy Policy</Text>.
          </Text>

          <Button
            label="Continue"
            onPress={submitAccount}
            loading={loading}
            disabled={loading || !ageConfirmed}
            block
            style={s.cta}
          />

          <Link href="/(auth)/login" asChild>
            <Pressable style={s.link} accessibilityRole="button">
              <Text style={[textStyle('bodySm'), s.linkText]}>
                Already have an account? <Text style={s.linkAccent}>Sign in</Text>
              </Text>
            </Pressable>
          </Link>
        </>
      ) : null}

      {step === 'about' ? (
        <>
          <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">About you</Text>

          <View style={s.fields}>
            <Input
              label="Name"
              placeholder="Your name"
              value={name}
              onChangeText={setName}
              autoCapitalize="words"
              autoComplete="name"
              textContentType="name"
              maxLength={50}
              returnKeyType="done"
            />
            <GenderSelect value={gender} onChange={setGender} />
          </View>

          {messageRow}

          <Button label="Continue" onPress={submitAbout} block style={s.cta} />
        </>
      ) : null}

      {step === 'phone' ? (
        <>
          <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">Mobile number</Text>
          <Text style={[textStyle('body'), s.subtitle]}>
            We text you a 6-digit code. Your number is how you sign in from now on.
          </Text>

          <Input
            label="Mobile number"
            placeholder="(305) 555-1234"
            value={formatPhoneDisplay(phone)}
            onChangeText={(t) => setPhone(normalizeUSPhone(t) ?? t.replace(/\D/g, '').slice(0, 10))}
            keyboardType="phone-pad"
            textContentType="telephoneNumber"
            autoComplete="tel-national"
            maxLength={PHONE_DISPLAY_MAXLENGTH}
            returnKeyType="go"
            onSubmitEditing={sendCode}
          />

          {messageRow}

          <Button label="Send code" onPress={sendCode} loading={loading} disabled={loading} block style={s.cta} />
          {backRow}
        </>
      ) : null}

      {step === 'verify' ? (
        <>
          <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">Verify number</Text>
          <Text style={[textStyle('body'), s.subtitle]}>Code sent to {formatPhoneDisplay(phone)}</Text>

          <Input
            label="Code"
            placeholder="123456"
            value={code}
            onChangeText={(t) => setCode(t.replace(/\D/g, '').slice(0, 6))}
            keyboardType="number-pad"
            textContentType="oneTimeCode"
            maxLength={6}
            autoFocus
            returnKeyType="go"
            onSubmitEditing={verifyAndFinish}
          />

          {messageRow}

          <Button
            label="Create account"
            onPress={verifyAndFinish}
            loading={loading}
            disabled={loading || code.length !== 6}
            block
            style={s.cta}
          />
          <Button
            label={resendLabel(cooldown)}
            variant="ghost"
            onPress={sendCode}
            disabled={!canResend(cooldown, loading)}
            block
          />
          {backRow}
        </>
      ) : null}

      {step === 'check_email' ? (
        <>
          <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">Check your email</Text>
          {messageRow}
          <Button label="Go to sign in" onPress={() => router.replace('/(auth)/login')} block style={s.cta} />
        </>
      ) : null}
    </AuthScreen>
  );
}

const s = StyleSheet.create({
  progress: { color: v2.text.muted, marginBottom: v2.space.sm },
  title: { color: v2.text.primary, marginBottom: v2.space.xl },
  subtitle: { color: v2.text.secondary, marginBottom: v2.space.lg, marginTop: -v2.space.md },
  fields: { gap: v2.space.lg },
  error: { color: v2.status.error, marginTop: v2.space.md },
  success: { color: v2.status.success, marginTop: v2.space.md },
  ageRow: { flexDirection: 'row', alignItems: 'center', minHeight: 44, marginTop: v2.space.lg },
  checkbox: {
    width: 22, height: 22, borderWidth: 2, borderColor: v2.border.strong,
    alignItems: 'center', justifyContent: 'center', marginRight: v2.space.sm,
  },
  checkboxOn: { backgroundColor: v2.brand.red, borderColor: v2.brand.red },
  checkMark: { color: v2.text.inverse, fontSize: 14, fontWeight: '700', lineHeight: 18 },
  ageText: { flex: 1, color: v2.text.secondary },
  legal: { color: v2.text.muted, marginTop: v2.space.sm, marginBottom: v2.space.xs },
  legalLink: { color: v2.brand.red, textDecorationLine: 'underline' },
  cta: { marginTop: v2.space.lg },
  alt: { alignItems: 'center', marginTop: v2.space.lg, minHeight: 44, justifyContent: 'center' },
  altText: { color: v2.text.muted },
  link: { alignItems: 'center', marginTop: v2.space.lg },
  linkText: { color: v2.text.muted },
  linkAccent: { color: v2.brand.red },
});
