/**
 * app/(auth)/reset-password.tsx — Set a new password (V2).
 *
 * Landed on from the Supabase recovery link (_layout routes here on the
 * PASSWORD_RECOVERY event). PRESENTATION rebuilt; the path is unchanged:
 * `updateUser({ password })`, then sign out and back to login. Validation copy
 * moves to src/lib/auth/authForms.ts.
 */

import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import { Alert, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { SIGN_OUT_FAILED_COPY, signOutAllDevices } from '@/src/lib/auth/signOut';
import { Button, Input } from '@/src/components/ui';
import { friendlyAuthError, validateReset } from '@/src/lib/auth/authForms';
import { AuthScreen } from '@/src/components/auth/AuthScreen';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';


export default function ResetPasswordScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleReset() {
    const invalid = validateReset(password, confirm);
    if (invalid) { Alert.alert(invalid); return; }
    setLoading(true);
    const { error } = await supabase.auth.updateUser({ password });
    setLoading(false);
    if (error) { Alert.alert('Error', friendlyAuthError(error.message)); return; }
    await signOutAfterPasswordChange();
  }

  // K-2: a new password ends every session; the login screen says why.
  // F-K2-3: if the sign-out fails (offline), the password is already changed
  // and every binding revoked, so the user is told exactly that and retries.
  async function signOutAfterPasswordChange(): Promise<void> {
    setLoading(true);
    const r = await signOutAllDevices({ reason: 'password_changed' });
    setLoading(false);
    if (!r.signedOut) {
      Alert.alert('Password updated', `Your password has been updated, but this device could not sign out. ${SIGN_OUT_FAILED_COPY}`, [
        { text: 'Try again', onPress: () => { void signOutAfterPasswordChange(); } },
      ]);
      return;
    }
    Alert.alert('Password updated', 'Your password has been updated. Please sign in.', [
      { text: 'OK', onPress: () => router.replace('/(auth)/login') },
    ]);
  }

  return (
    <AuthScreen>
        <Text style={[textStyle('displayLg'), s.title]} accessibilityRole="header">New password</Text>

        <View style={s.fields}>
          <Input
            label="New password"
            placeholder="At least 6 characters"
            value={password}
            onChangeText={setPassword}
            secureTextEntry
            autoCapitalize="none"
            autoComplete="new-password"
            textContentType="newPassword"
            returnKeyType="next"
          />
          <Input
            label="Confirm password"
            placeholder="Re-enter your password"
            value={confirm}
            onChangeText={setConfirm}
            secureTextEntry
            autoCapitalize="none"
            autoComplete="new-password"
            textContentType="newPassword"
            returnKeyType="done"
            onSubmitEditing={handleReset}
          />
        </View>

        <Button label="Update password" onPress={handleReset} loading={loading} disabled={loading} block style={s.cta} />
    </AuthScreen>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  title: { color: p.text.primary, marginBottom: v2.space.xl },
  fields: { gap: v2.space.lg },
  cta: { marginTop: v2.space.xl },
  });
}
