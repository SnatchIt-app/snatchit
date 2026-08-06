/**
 * app/(auth)/login.tsx — Sign In screen
 *
 * Calls supabase.auth.signInWithPassword.
 * On success, the useAuth hook in _layout.tsx detects the new session
 * and automatically routes to /(tabs)/home.
 */

import { Link } from 'expo-router';
import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { colors, fontSize, radius, spacing } from '@/src/theme';

export default function LoginScreen() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSignIn() {
    if (!email.trim() || !password.trim()) {
      setError('Please enter your email and password.');
      return;
    }
    setLoading(true);
    setError(null);

    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });

    setLoading(false);
    if (error) setError(error.message);
    // On success: useAuth detects the session → _layout.tsx redirects to /(tabs)/home
  }

  async function handleForgotPassword() {
    if (!email.trim()) {
      Alert.alert('Enter your email first');
      return;
    }
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: 'snatchit://',
    });
    if (error) {
      Alert.alert('Error', error.message);
    } else {
      Alert.alert('Check your email for a password reset link.');
    }
  }

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
      <View style={styles.inner}>

        {/* ── Header ── */}
        <Text style={styles.logo}>SnatchIt</Text>
        <Text style={styles.heading}>Sign in to your account</Text>

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
          placeholder="Password"
          placeholderTextColor={colors.textPlaceholder}
          secureTextEntry
          autoCapitalize="none"
          autoComplete="current-password"
          value={password}
          onChangeText={setPassword}
        />

        {/* ── Forgot Password ── */}
        <TouchableOpacity onPress={handleForgotPassword} style={styles.forgotRow}>
          <Text style={styles.forgotText}>Forgot Password?</Text>
        </TouchableOpacity>

        {/* ── Error ── */}
        {error && <Text style={styles.errorText}>{error}</Text>}

        {/* ── Sign In button ── */}
        <TouchableOpacity
          style={[styles.button, loading && styles.buttonDisabled]}
          onPress={handleSignIn}
          disabled={loading}
          activeOpacity={0.8}>
          {loading
            ? <ActivityIndicator color={colors.text} />
            : <Text style={styles.buttonText}>Sign In</Text>}
        </TouchableOpacity>

        {/* ── Link to Sign Up ── */}
        <Link href="/(auth)/signup" asChild>
          <TouchableOpacity style={styles.linkRow}>
            <Text style={styles.linkText}>Don't have an account? </Text>
            <Text style={[styles.linkText, styles.linkAccent]}>Sign up</Text>
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
  errorText: {
    color: colors.error,
    fontSize: fontSize.sm,
    marginBottom: spacing.sm,
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
  forgotRow: {
    alignSelf: 'flex-end',
    marginBottom: spacing.sm,
  },
  forgotText: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
  },
});
