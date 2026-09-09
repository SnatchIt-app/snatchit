/**
 * app/settings/edit-profile.tsx — Edit profile (V2).
 *
 * PRESENTATION rebuilt on the V2 system; behaviour is unchanged. The same
 * `get_my_profile` hydrate, the immediate avatar pick+upload (independent DB
 * write), the field rules (display name 2-50, optional NANP phone, bio ≤ 200) and
 * the save (normalize phone before persisting, update `profiles`, back on success)
 * are preserved. Consistent with the approved Profile. No social fields added; the
 * phone is verification-only and never surfaced publicly here.
 */

import { Image } from 'expo-image';
import { router } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, Keyboard, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type TextStyle } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import type { MyProfileRPC } from '@/src/types';
import { useAuth } from '@/src/hooks/useAuth';
import { getAvatarUrl, pickAndUploadAvatar } from '@/src/lib/avatarImage';
import { digitsOnly, formatPhoneDisplay, isValidUSPhone, normalizeUSPhone, PHONE_DISPLAY_MAXLENGTH, toPhoneDigits } from '@/src/utils/phone';
import { Button, Input, Spinner, StickyBar } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

const AVATAR = 92;
const RING = AVATAR + 8;

function getInitials(name: string): string {
  if (!name.trim()) return '?';
  return name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]?.toUpperCase() ?? '').join('');
}

export default function EditProfileScreen() {
  const { user } = useAuth();

  const [pageLoading, setPageLoading] = useState(true);
  const [avatarUrl, setAvatarUrl] = useState<string | null>(null);
  const [avatarUploading, setAvatarUploading] = useState(false);

  const [displayName, setDisplayName] = useState('');
  const [phoneNumber, setPhoneNumber] = useState('');
  const [bio, setBio] = useState('');

  const [submitted, setSubmitted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [bioFocused, setBioFocused] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const { data, error } = await supabase.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle();
      if (data) {
        setDisplayName(data.display_name ?? '');
        setPhoneNumber(normalizeUSPhone(data.phone_number) ?? '');
        setBio(data.bio ?? '');
        setAvatarUrl(getAvatarUrl(data.avatar_path ?? data.avatar_url));
      }
      if (error) console.warn('[EditProfile] fetch error:', error.message);
      setPageLoading(false);
    })();
  }, [user?.id]);

  async function handleAvatarPress() {
    if (!user || avatarUploading) return;
    setAvatarUploading(true);
    const result = await pickAndUploadAvatar(user.id);
    setAvatarUploading(false);
    if (!result.ok) {
      if (result.error !== 'Cancelled.') {
        if (Platform.OS === 'web') window.alert(result.error); else Alert.alert('Upload failed', result.error);
      }
      return;
    }
    const { error: dbError } = await supabase.from('profiles').update({ avatar_path: result.storagePath }).eq('id', user.id);
    if (dbError) {
      if (Platform.OS === 'web') window.alert(dbError.message); else Alert.alert('Save failed', dbError.message);
      return;
    }
    setAvatarUrl(result.publicUrl);
  }

  const errors = useMemo(() => {
    const trimName = displayName.trim();
    const phoneDigits = digitsOnly(phoneNumber);
    const trimBio = bio.trim();
    return {
      displayName:
        !trimName ? 'Display name is required.'
        : trimName.length < 2 ? 'Display name must be at least 2 characters.'
        : trimName.length > 50 ? 'Display name must be 50 characters or fewer.'
        : '',
      phoneNumber: phoneDigits.length > 0 && !isValidUSPhone(phoneDigits) ? 'Enter a valid 10-digit US phone number.' : '',
      bio: trimBio.length > 200 ? 'Bio must be 200 characters or fewer.' : '',
    };
  }, [displayName, phoneNumber, bio]);

  const isValid = Object.values(errors).every((e) => !e);

  async function handleSave() {
    setSubmitted(true);
    if (!isValid || !user) return;
    setLoading(true);
    try {
      const normalizedPhone = normalizeUSPhone(phoneNumber);
      const { error } = await supabase
        .from('profiles')
        .update({ display_name: displayName.trim(), phone_number: normalizedPhone, bio: bio.trim() || null })
        .eq('id', user.id);
      if (error) throw error;
      if (Platform.OS === 'web') window.alert('Your profile has been updated.'); else Alert.alert('Saved', 'Your profile has been updated.');
      router.back();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to save profile.';
      if (Platform.OS === 'web') window.alert(msg); else Alert.alert('Error', msg);
    } finally {
      setLoading(false);
    }
  }

  if (pageLoading) {
    return (
      <View style={s.root}>
        <SettingsHeader title="Edit profile" />
        <View style={s.center}><Spinner color={v2.brand.red} /></View>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView style={s.root} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <SettingsHeader title="Edit profile" />
      <ScrollView
        contentContainerStyle={s.body}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        onScrollBeginDrag={Platform.OS !== 'web' ? Keyboard.dismiss : undefined}
      >
        <View style={s.avatarSection}>
          <Pressable style={s.avatarRing} onPress={handleAvatarPress} disabled={avatarUploading} accessibilityRole="button" accessibilityLabel="Change profile photo">
            {avatarUrl ? (
              <Image source={{ uri: avatarUrl }} style={s.avatarImage} contentFit="cover" />
            ) : (
              <View style={s.avatarFallback}><Text style={s.avatarInitials}>{getInitials(displayName)}</Text></View>
            )}
            {avatarUploading ? <View style={s.avatarOverlay}><Spinner color={v2.text.primary} /></View> : null}
          </Pressable>
          <Pressable onPress={handleAvatarPress} disabled={avatarUploading} hitSlop={8}>
            <Text style={[textStyle('label'), s.changePhoto]}>{avatarUploading ? 'Uploading' : 'Change photo'}</Text>
          </Pressable>
        </View>

        <View style={s.fields}>
          <Input
            label="Display name"
            placeholder="How others see you"
            value={displayName}
            onChangeText={setDisplayName}
            maxLength={50}
            autoCapitalize="words"
            returnKeyType="next"
            error={submitted ? errors.displayName || null : null}
          />
          <Input
            label="Phone number"
            placeholder="(305) 555-1234"
            value={formatPhoneDisplay(phoneNumber)}
            onChangeText={(v) => setPhoneNumber(toPhoneDigits(v))}
            keyboardType="phone-pad"
            textContentType="telephoneNumber"
            autoComplete="tel-national"
            maxLength={PHONE_DISPLAY_MAXLENGTH}
            returnKeyType="next"
            error={submitted ? errors.phoneNumber || null : null}
          />

          <View>
            <View style={s.bioLabelRow}>
              <Text style={[textStyle('micro'), s.bioLabel]}>Bio</Text>
              <Text style={[textStyle('bodySm'), bio.trim().length > 200 ? s.countOver : s.count]}>{bio.trim().length}/200</Text>
            </View>
            <TextInput
              style={[textStyle('body') as TextStyle, s.bio, { borderBottomColor: submitted && errors.bio ? v2.status.error : bioFocused ? v2.brand.red : v2.border.strong }]}
              placeholder="Tell others about yourself"
              placeholderTextColor={v2.text.faint}
              value={bio}
              onChangeText={setBio}
              onFocus={() => setBioFocused(true)}
              onBlur={() => setBioFocused(false)}
              selectionColor={v2.brand.red}
              multiline
              numberOfLines={4}
              maxLength={200}
              accessibilityLabel="Bio"
            />
            {submitted && errors.bio ? <Text style={[textStyle('bodySm'), s.fieldError]} accessibilityRole="alert">{errors.bio}</Text> : null}
          </View>

          {submitted && !isValid ? (
            <Text style={[textStyle('bodySm'), s.validation]} accessibilityRole="alert">Fix the highlighted fields before saving.</Text>
          ) : null}
        </View>
      </ScrollView>

      <StickyBar>
        <Button label="Save changes" onPress={handleSave} loading={loading} disabled={loading} block />
      </StickyBar>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },

  body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, paddingBottom: v2.space.xxl },

  avatarSection: { alignItems: 'center', marginBottom: v2.space.xl, gap: v2.space.sm },
  avatarRing: {
    width: RING, height: RING, borderRadius: RING / 2,
    borderWidth: 1, borderColor: v2.brand.red, alignItems: 'center', justifyContent: 'center',
  },
  avatarImage: { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2 },
  avatarFallback: { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2, backgroundColor: v2.brand.redSoft, alignItems: 'center', justifyContent: 'center' },
  avatarInitials: { fontFamily: v2.font.bodyBold, fontSize: 30, color: v2.brand.red },
  avatarOverlay: { ...StyleSheet.absoluteFillObject, borderRadius: RING / 2, backgroundColor: 'rgba(0,0,0,0.55)', alignItems: 'center', justifyContent: 'center' },
  changePhoto: { color: v2.brand.red },

  fields: { gap: v2.space.lg },
  bioLabelRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: v2.space.xs },
  bioLabel: { color: v2.text.muted },
  count: { color: v2.text.faint, fontVariant: ['tabular-nums'] },
  countOver: { color: v2.status.error, fontVariant: ['tabular-nums'] },
  bio: { minHeight: 96, color: v2.text.primary, borderBottomWidth: 1, paddingVertical: v2.space.sm, textAlignVertical: 'top' },
  fieldError: { color: v2.status.error, marginTop: v2.space.xs },
  validation: { color: v2.status.error, textAlign: 'center' },
});
