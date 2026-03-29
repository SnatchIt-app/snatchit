/**
 * app/(auth)/reset-password.tsx
 *
 * Landed on when the user taps the Supabase password-reset email link.
 * _layout.tsx detects the PASSWORD_RECOVERY auth event and routes here.
 * Calls supabase.auth.updateUser() with the new password, then redirects to login.
 */

import { router } from 'expo-router';
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

export default function ResetPasswordScreen() {
  const [password, setPassword] = useState('');
  const [confirm,  setConfirm]  = useState('');
  const [loading,  setLoading]  = useState(false);

  async function handleReset() {
    if (!password.trim() || !confirm.trim()) {
      Alert.alert('Both fields are required.');
      return;
    }
    if (password !== confirm) {
      Alert.alert('Passwords do not match.');
      return;
    }
    setLoading(true);
    const { error } = await supabase.auth.updateUser({ password });
    setLoading(false);
    if (error) {
      Alert.alert('Error', error.message);
      return;
    }
    await supabase.auth.signOut();
    Alert.alert(
      'Password updated',
      'Your password has been updated. Please sign in.',
      [{ text: 'OK', onPress: () => router.replace('/(auth)/login') }],
    );
  }

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View style={styles.inner}>

        <Text style={styles.logo}>SnatchIt</Text>
        <Text style={styles.heading}>Set New Password</Text>

        <TextInput
          style={styles.input}
          placeholder="New password"
          placeholderTextColor={colors.textPlaceholder}
          secureTextEntry
          autoCapitalize="none"
          value={password}
          onChangeText={setPassword}
        />
        <TextInput
          style={styles.input}
          placeholder="Confirm new password"
          placeholderTextColor={colors.textPlaceholder}
          secureTextEntry
          autoCapitalize="none"
          value={confirm}
          onChangeText={setConfirm}
        />

        <TouchableOpacity
          style={[styles.button, loading && styles.buttonDisabled]}
          onPress={handleReset}
          disabled={loading}
          activeOpacity={0.8}
        >
          {loading
            ? <ActivityIndicator color={colors.text} />
            : <Text style={styles.buttonText}>Update Password</Text>
          }
        </TouchableOpacity>

      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
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
  button: {
    backgroundColor: colors.accent,
    paddingVertical: spacing.md,
    borderRadius: radius.md,
    alignItems: 'center',
    marginTop: spacing.xs,
  },
  buttonDisabled: { opacity: 0.6 },
  buttonText: {
    color: colors.text,
    fontWeight: '700',
    fontSize: fontSize.md,
    letterSpacing: 1,
  },
});
