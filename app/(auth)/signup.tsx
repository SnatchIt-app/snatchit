/**
 * app/(auth)/signup.tsx — Create Account screen
 *
 * Calls supabase.auth.signUp.
 * Supabase sends a confirmation email by default.
 * To skip confirmation during development:
 *   Supabase dashboard → Authentication → Sign In / Up → Confirm email → OFF
 */

import { Link, router } from 'expo-router';
import { useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { colors, fontSize, radius, spacing } from '@/src/theme';

export default function SignUpScreen() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [ageConfirmed, setAgeConfirmed] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ text: string; type: 'error' | 'success' } | null>(null);

  async function handleSignUp() {
    if (!email.trim() || !password.trim()) {
      setMessage({ text: 'Please enter your email and password.', type: 'error' });
      return;
    }
    if (password.length < 6) {
      setMessage({ text: 'Password must be at least 6 characters.', type: 'error' });
      return;
    }
    if (!ageConfirmed) {
      setMessage({ text: 'You must confirm you are 18 or older to use Snatch It.', type: 'error' });
      return;
    }

    setLoading(true);
    setMessage(null);

    const { error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
    });

    setLoading(false);

    if (error) {
      setMessage({ text: error.message, type: 'error' });
    } else {
      setMessage({
        text: 'Account created! Check your email to confirm, then sign in.',
        type: 'success',
      });
    }
  }

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
      <View style={styles.inner}>

        {/* ── Header ── */}
        <Text style={styles.logo}>SnatchIt</Text>
        <Text style={styles.heading}>Create an account</Text>

        {/* ── Inputs ── */}
        <TextInput
          style={styles.input}
          placeholder="Email"
          placeholderTextColor={colors.textPlaceholder}
          keyboardType="email-address"
          autoCapitalize="none"
          autoComplete="email"
          value={email}
          onChangeText={setEmail}
        />
        <TextInput
          style={styles.input}
          placeholder="Password (min 6 characters)"
          placeholderTextColor={colors.textPlaceholder}
          secureTextEntry
          autoCapitalize="none"
          autoComplete="new-password"
          value={password}
          onChangeText={setPassword}
        />

        {/* ── Feedback ── */}
        {message && (
          <Text style={[styles.messageText, message.type === 'error' ? styles.error : styles.success]}>
            {message.text}
          </Text>
        )}

        {/* ── 18+ confirmation (App Store Guideline 1.4.3 / 18+ marketplace) ── */}
        <Pressable
          style={styles.ageRow}
          onPress={() => setAgeConfirmed(v => !v)}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: ageConfirmed }}>
          <View style={[styles.checkbox, ageConfirmed && styles.checkboxOn]}>
            {ageConfirmed && <Text style={styles.checkMark}>{'✓'}</Text>}
          </View>
          <Text style={styles.ageText}>I confirm I am 18 years of age or older.</Text>
        </Pressable>

        {/* ── Legal disclosure (App Store Guideline 5.1.1) ── */}
        <Text style={styles.legalText}>
          By creating an account you agree to our{' '}
          <Text
            style={styles.legalLink}
            onPress={() => router.push('/settings/legal')}
            accessibilityRole="link"
          >
            Terms of Service
          </Text>
          {' '}and{' '}
          <Text
            style={styles.legalLink}
            onPress={() => router.push('/settings/privacy')}
            accessibilityRole="link"
          >
            Privacy Policy
          </Text>
          .
        </Text>

        {/* ── Create Account button ── */}
        <TouchableOpacity
          style={[styles.button, (loading || !ageConfirmed) && styles.buttonDisabled]}
          onPress={handleSignUp}
          disabled={loading || !ageConfirmed}
          activeOpacity={0.8}>
          {loading
            ? <ActivityIndicator color={colors.text} />
            : <Text style={styles.buttonText}>Create Account</Text>}
        </TouchableOpacity>

        {/* ── Link to Sign In ── */}
        <Link href="/(auth)/login" asChild>
          <TouchableOpacity style={styles.linkRow}>
            <Text style={styles.linkText}>Already have an account? </Text>
            <Text style={[styles.linkText, styles.linkAccent]}>Sign in</Text>
          </TouchableOpacity>
        </Link>

      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  inner: {
    flex: 1,
    paddingHorizontal: spacing.lg,
    justifyContent: 'center',
  },
  logo: {
    fontSize: fontSize.xxl,
    fontWeight: '800',
    color: colors.text,
    letterSpacing: 2,
    marginBottom: spacing.xs,
  },
  heading: {
    fontSize: fontSize.md,
    color: colors.textMuted,
    marginBottom: spacing.xl,
  },
  input: {
    backgroundColor: colors.bgInput,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.borderInput,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: 14,
    fontSize: fontSize.md,
    marginBottom: spacing.sm + 2,
  },
  messageText: {
    fontSize: fontSize.sm,
    marginBottom: spacing.sm,
    lineHeight: 20,
  },
  error: {
    color: colors.error,
  },
  success: {
    color: colors.success,
  },
  button: {
    backgroundColor: colors.accent,
    paddingVertical: spacing.md,
    borderRadius: radius.md,
    alignItems: 'center',
    marginTop: spacing.xs,
    marginBottom: spacing.lg,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: colors.text,
    fontWeight: '700',
    fontSize: fontSize.md,
    letterSpacing: 1,
  },
  linkRow: {
    flexDirection: 'row',
    justifyContent: 'center',
  },
  linkText: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
  },
  linkAccent: {
    color: colors.accent,
    fontWeight: '600',
  },
  legalText: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    lineHeight: 18,
    textAlign: 'center',
    marginTop: spacing.xs,
    marginBottom: spacing.md,
    paddingHorizontal: spacing.sm,
  },
  legalLink: {
    color: colors.accent,
    fontWeight: '600',
    textDecorationLine: 'underline',
  },
  ageRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: spacing.xs,
    marginBottom: spacing.sm,
    paddingHorizontal: spacing.xs,
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
  },
  checkboxOn: {
    backgroundColor: colors.accent,
    borderColor: colors.accent,
  },
  checkMark: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '700',
    lineHeight: 18,
  },
  ageText: {
    flex: 1,
    color: colors.text,
    fontSize: fontSize.sm,
    lineHeight: 20,
  },
});
