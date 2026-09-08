/**
 * app/(auth)/login.tsx — Sign in (V2).
 *
 * Returning users sign in with their mobile number. They enter it, we send a code
 * through Supabase Auth, they type the code, and the provider establishes the
 * session. Nothing else is asked for: name, gender and email belong to Sign up and
 * are never re-collected here.
 *
 * NO ACCOUNT IS EVER CREATED ON THIS SCREEN. `signInWithOtp` is always sent with
 * `shouldCreateUser: false`, so a number with no account comes back as an error and
 * the person is pointed at Sign up. That is the difference between "sign in" and
 * "silently make a second account for someone who mistyped a digit".
 *
 * Email and password remain a full second way in, unchanged: `signInWithPassword`
 * and the forgot-password reset are exactly the calls they were. Most existing
 * accounts have no verified phone yet, so that path is not a fallback in name only,
 * it is how they get in until they add a number.
 *
 * The session is always the provider's. Nothing here fabricates one.
 */

import { Link, router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { Button, Input } from '@/src/components/ui';
import { friendlyAuthError, validateLogin } from '@/src/lib/auth/authForms';
import {
  canResend,
  classifyOtpError,
  DEFAULT_SIGN_IN_METHOD,
  maskE164,
  otpErrorCopy,
  RESEND_COOLDOWN_S,
  resendLabel,
  toE164US,
  type PhoneSignInStep,
  type SignInMethod,
} from '@/src/lib/auth/phoneAuth';
import { AuthScreen } from '@/src/components/auth/AuthScreen';
import { formatPhoneDisplay, normalizeUSPhone, PHONE_DISPLAY_MAXLENGTH } from '@/src/utils/phone';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';


export default function LoginScreen() {
  const [method, setMethod] = useState<SignInMethod>(DEFAULT_SIGN_IN_METHOD);

  // Phone path
  const [step, setStep] = useState<PhoneSignInStep>('enter_phone');
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [sentTo, setSentTo] = useState<string | null>(null);
  const [noAccount, setNoAccount] = useState(false);
  const [cooldown, setCooldown] = useState(0);
  const cooldownRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Email path
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => () => { if (cooldownRef.current) clearInterval(cooldownRef.current); }, []);

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

  /** Send the code. `shouldCreateUser: false` is the account-safety guarantee. */
  async function handleSendCode() {
    const e164 = toE164US(phone);
    if (!e164) { setError(otpErrorCopy('invalid_number')); return; }

    setLoading(true);
    setError(null);
    setNoAccount(false);

    const { error: otpErr } = await supabase.auth.signInWithOtp({
      phone: e164,
      options: { shouldCreateUser: false },
    });

    setLoading(false);

    if (otpErr) {
      const failure = classifyOtpError(otpErr, 'send');
      setError(otpErrorCopy(failure));
      setNoAccount(failure === 'unknown_account');
      return;
    }

    setSentTo(e164);
    setCode('');
    startCooldown();
    setStep('enter_code');
  }

  /** Verify the code. Only the provider can turn this into a session. */
  async function handleVerifyCode() {
    const e164 = sentTo ?? toE164US(phone);
    if (!e164) { setError(otpErrorCopy('invalid_number')); return; }
    if (code.trim().length !== 6) { setError('Enter the 6-digit code from the text message.'); return; }

    setLoading(true);
    setError(null);

    const { error: verifyErr } = await supabase.auth.verifyOtp({
      phone: e164,
      token: code.trim(),
      type: 'sms',
    });

    setLoading(false);

    if (verifyErr) {
      setError(otpErrorCopy(classifyOtpError(verifyErr, 'verify')));
      return;
    }
    // On success: useAuth detects the session -> _layout redirects to Home.
  }

  async function handleEmailSignIn() {
    const invalid = validateLogin(email, password);
    if (invalid) { setError(invalid); return; }
    setLoading(true);
    setError(null);

    const { error: authErr } = await supabase.auth.signInWithPassword({ email: email.trim(), password });

    setLoading(false);
    if (authErr) setError(friendlyAuthError(authErr.message));
    // On success: useAuth detects the session -> _layout redirects to Home.
  }

  async function handleForgotPassword() {
    if (!email.trim()) { Alert.alert('Enter your email first'); return; }
    const { error: resetErr } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: 'snatchit://' });
    if (resetErr) Alert.alert('Error', friendlyAuthError(resetErr.message));
    else Alert.alert('Check your email for a password reset link.');
  }

  function switchMethod(next: SignInMethod) {
    setMethod(next);
    setError(null);
    setNoAccount(false);
  }

  function useDifferentNumber() {
    setStep('enter_phone');
    setCode('');
    setSentTo(null);
    setError(null);
  }

  const errorRow = error ? (
    <Text style={[textStyle('bodySm'), s.error]} accessibilityRole="alert">{error}</Text>
  ) : null;

  const signUpLink = (
    <Link href="/(auth)/signup" asChild>
      <Pressable style={s.link} accessibilityRole="button">
        <Text style={[textStyle('bodySm'), s.linkText]}>
          Don&apos;t have an account? <Text style={s.linkAccent}>Sign up</Text>
        </Text>
      </Pressable>
    </Link>
  );

  return (
    <AuthScreen>
      {method === 'phone' && step === 'enter_phone' ? (
        <>
          <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">Sign in</Text>

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
            onSubmitEditing={handleSendCode}
          />

          {errorRow}

          {noAccount ? (
            <Button label="Sign up" variant="secondary" onPress={() => router.push('/(auth)/signup')} block style={s.secondaryCta} />
          ) : null}

          <Button label="Continue" onPress={handleSendCode} loading={loading} disabled={loading} block style={s.cta} />

          <Pressable onPress={() => switchMethod('email')} style={s.alt} hitSlop={8} accessibilityRole="button">
            <Text style={[textStyle('bodySm'), s.altText]}>Use email instead</Text>
          </Pressable>

          {signUpLink}
        </>
      ) : null}

      {method === 'phone' && step === 'enter_code' ? (
        <>
          <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">Verify number</Text>
          <Text style={[textStyle('body'), s.subtitle]}>Code sent to {maskE164(sentTo)}</Text>

          <Input
            label="Code"
            placeholder="123456"
            value={code}
            onChangeText={(t) => setCode(t.replace(/\D/g, '').slice(0, 6))}
            keyboardType="number-pad"
            textContentType="oneTimeCode"
            autoComplete="sms-otp"
            maxLength={6}
            autoFocus
            returnKeyType="go"
            onSubmitEditing={handleVerifyCode}
          />

          {errorRow}

          <Button label="Verify" onPress={handleVerifyCode} loading={loading} disabled={loading || code.length !== 6} block style={s.cta} />

          <Button
            label={resendLabel(cooldown)}
            variant="ghost"
            onPress={handleSendCode}
            disabled={!canResend(cooldown, loading)}
            block
          />
          <Button label="Use a different number" variant="ghost" onPress={useDifferentNumber} block />
        </>
      ) : null}

      {method === 'email' ? (
        <>
          <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">Sign in</Text>

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
              placeholder="Your password"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              autoCapitalize="none"
              autoComplete="current-password"
              textContentType="password"
              returnKeyType="go"
              onSubmitEditing={handleEmailSignIn}
            />
          </View>

          <Pressable onPress={handleForgotPassword} style={s.forgot} hitSlop={8} accessibilityRole="button">
            <Text style={[textStyle('bodySm'), s.forgotText]}>Forgot password?</Text>
          </Pressable>

          {errorRow}

          <Button label="Sign in" onPress={handleEmailSignIn} loading={loading} disabled={loading} block style={s.cta} />

          <Pressable onPress={() => switchMethod('phone')} style={s.alt} hitSlop={8} accessibilityRole="button">
            <Text style={[textStyle('bodySm'), s.altText]}>Use mobile number instead</Text>
          </Pressable>

          {signUpLink}
        </>
      ) : null}
    </AuthScreen>
  );
}

const s = StyleSheet.create({
  title: { color: v2.text.primary, marginBottom: v2.space.xl },
  subtitle: { color: v2.text.secondary, marginBottom: v2.space.lg },
  fields: { gap: v2.space.lg },
  forgot: { alignSelf: 'flex-end', marginTop: v2.space.md },
  forgotText: { color: v2.text.muted },
  error: { color: v2.status.error, marginTop: v2.space.md },
  cta: { marginTop: v2.space.xl },
  secondaryCta: { marginTop: v2.space.lg },
  alt: { alignItems: 'center', marginTop: v2.space.lg, minHeight: 44, justifyContent: 'center' },
  altText: { color: v2.text.muted },
  link: { alignItems: 'center', marginTop: v2.space.lg },
  linkText: { color: v2.text.muted },
  linkAccent: { color: v2.brand.red },
});
