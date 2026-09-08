/**
 * app/(auth)/reset-password.tsx — Set a new password (V2).
 *
 * Landed on from the Supabase recovery link (_layout routes here on the
 * PASSWORD_RECOVERY event). PRESENTATION rebuilt; the path is unchanged:
 * `updateUser({ password })`, then sign out and back to login. Validation copy
 * moves to src/lib/auth/authForms.ts.
 */

import { router } from 'expo-router';
import { useState } from 'react';
import { Alert, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { Button, Input } from '@/src/components/ui';
import { friendlyAuthError, validateReset } from '@/src/lib/auth/authForms';
import { AuthScreen } from '@/src/components/auth/AuthScreen';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';


export default function ResetPasswordScreen() {
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
    await supabase.auth.signOut();
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

const s = StyleSheet.create({
  title: { color: v2.text.primary, marginBottom: v2.space.xl },
  fields: { gap: v2.space.lg },
  cta: { marginTop: v2.space.xl },
});
