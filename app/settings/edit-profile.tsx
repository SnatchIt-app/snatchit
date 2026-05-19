/**
 * app/settings/edit-profile.tsx — Edit Profile form
 *
 * Follows the CreateListingScreen validation pattern:
 *   - Per-field useState
 *   - useMemo errors object + submitted flag
 *   - FieldError component for inline error text
 *   - Save handler: setSubmitted → check isValid → try/catch/finally
 *
 * Avatar:
 *   - Tappable circle at the top — picks & uploads immediately (separate DB call)
 *   - Replicates the exact pattern from app/(tabs)/profile.tsx handleAvatarPress
 *
 * Fields:
 *   - Display Name (required, 2–50 chars)
 *   - Phone Number (optional, exactly 10 US digits if provided; validates NANP)
 *   - Bio (optional, max 200 chars)
 */

import { Image } from 'expo-image';
import { router } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { getAvatarUrl, pickAndUploadAvatar } from '@/src/lib/avatarImage';
import {
  digitsOnly,
  formatPhoneDisplay,
  isValidUSPhone,
  normalizeUSPhone,
  PHONE_DISPLAY_MAXLENGTH,
  toPhoneDigits,
} from '@/src/utils/phone';
import { colors, fontSize, radius, spacing } from '@/src/theme';

// ─── Constants ────────────────────────────────────────────────────────────────

const AVATAR_SIZE = 96;
const RING_SIZE   = AVATAR_SIZE + 8;

// ─── Helpers ──────────────────────────────────────────────────────────────────

function FieldError({ msg }: { msg?: string }) {
  if (!msg) return null;
  return <Text style={s.fieldError}>{msg}</Text>;
}

/** "Jose Tascon" → "JT" */
function getInitials(name: string): string {
  if (!name.trim()) return '?';
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map(w => w[0]?.toUpperCase() ?? '')
    .join('');
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

export default function EditProfileScreen() {
  const { user } = useAuth();

  // ── Page-level state ────────────────────────────────────────────────────────
  const [pageLoading, setPageLoading] = useState(true);

  // ── Avatar state ────────────────────────────────────────────────────────────
  const [avatarUrl,       setAvatarUrl]       = useState<string | null>(null);
  const [avatarUploading, setAvatarUploading] = useState(false);

  // ── Form fields ─────────────────────────────────────────────────────────────
  const [displayName, setDisplayName] = useState('');
  const [phoneNumber, setPhoneNumber] = useState('');
  const [bio,         setBio]         = useState('');

  // ── UI flags ────────────────────────────────────────────────────────────────
  const [submitted, setSubmitted] = useState(false);
  const [loading,   setLoading]   = useState(false);

  // ── Fetch current profile on mount ──────────────────────────────────────────

  useEffect(() => {
    if (!user) return;

    (async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('display_name, phone_number, bio, avatar_path, avatar_url')
        .eq('id', user.id)
        .single();

      if (data) {
        setDisplayName(data.display_name ?? '');
        // Phone is stored as a clean 10-digit string. Some legacy rows may
        // still have +1 / formatting — normalizeUSPhone handles both.
        setPhoneNumber(normalizeUSPhone(data.phone_number) ?? '');
        setBio(data.bio ?? '');
        // Resolve avatar: prefer avatar_path (storage), fall back to avatar_url (legacy)
        setAvatarUrl(getAvatarUrl(data.avatar_path ?? data.avatar_url));
      }
      if (error) {
        console.warn('[EditProfile] fetch error:', error.message);
      }

      setPageLoading(false);
    })();
  }, [user?.id]);

  // ── Avatar upload (saves immediately — independent of form save) ────────────

  async function handleAvatarPress() {
    if (!user) return;
    if (avatarUploading) return;

    setAvatarUploading(true);
    const result = await pickAndUploadAvatar(user.id);
    setAvatarUploading(false);

    if (!result.ok) {
      // Cancelled silently — don't show an alert for cancellation
      if (result.error !== 'Cancelled.') {
        if (Platform.OS === 'web') {
          window.alert(result.error);
        } else {
          Alert.alert('Upload Failed', result.error);
        }
      }
      return;
    }

    // Update avatar_path in the DB immediately
    const { error: dbError } = await supabase
      .from('profiles')
      .update({ avatar_path: result.storagePath })
      .eq('id', user.id);

    if (dbError) {
      if (Platform.OS === 'web') {
        window.alert(dbError.message);
      } else {
        Alert.alert('Save Failed', dbError.message);
      }
      return;
    }

    // Reflect new avatar in the UI
    setAvatarUrl(result.publicUrl);
  }

  // ── Validation (useMemo pattern from CreateListingScreen) ───────────────────

  const errors = useMemo(() => {
    const trimName    = displayName.trim();
    const phoneDigits = digitsOnly(phoneNumber);
    const trimBio     = bio.trim();

    return {
      displayName:
        !trimName             ? 'Display name is required.'
        : trimName.length < 2 ? 'Display name must be at least 2 characters.'
        : trimName.length > 50 ? 'Display name must be 50 characters or fewer.'
        : '',
      // Phone is optional. If provided, must be exactly 10 digits AND
      // satisfy NANP rules. Empty input = no error (clears the field).
      phoneNumber:
        phoneDigits.length > 0 && !isValidUSPhone(phoneDigits)
          ? 'Enter a valid 10-digit US phone number.'
          : '',
      bio:
        trimBio.length > 200
          ? 'Bio must be 200 characters or fewer.'
          : '',
    };
  }, [displayName, phoneNumber, bio]);

  const isValid = Object.values(errors).every(e => !e);

  // ── Save handler ────────────────────────────────────────────────────────────

  async function handleSave() {
    setSubmitted(true);
    if (!isValid || !user) return;
    setLoading(true);

    try {
      // Backend write guard: always normalize before persisting. If the
      // client-side validator was somehow bypassed, normalizeUSPhone()
      // returns null for invalid input and we store null rather than a
      // malformed value.
      const normalizedPhone = normalizeUSPhone(phoneNumber);
      const { error } = await supabase
        .from('profiles')
        .update({
          display_name: displayName.trim(),
          phone_number: normalizedPhone, // clean 10-digit string or null
          bio:          bio.trim() || null,
        })
        .eq('id', user.id);

      if (error) throw error;
      if (Platform.OS === 'web') {
        window.alert('Your profile has been updated.');
      } else {
        Alert.alert('Saved', 'Your profile has been updated.');
      }
      router.back();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to save profile.';
      if (Platform.OS === 'web') {
        window.alert(msg);
      } else {
        Alert.alert('Error', msg);
      }
    } finally {
      setLoading(false);
    }
  }

  // ── Derived values ──────────────────────────────────────────────────────────

  const initials = getInitials(displayName);

  // ── Loading state ───────────────────────────────────────────────────────────

  if (pageLoading) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
            <Text style={s.backArrow}>{'\u2190'}</Text>
          </Pressable>
          <Text style={s.topTitle}>Edit Profile</Text>
          <View style={s.backBtn} />
        </View>
        <View style={s.loader}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      </SafeAreaView>
    );
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  return (
    <SafeAreaView style={s.safe}>

      {/* ── Top bar ──────────────────────────────────────────── */}
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'\u2190'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Edit Profile</Text>
        <Pressable
          onPress={handleSave}
          disabled={loading}
          style={s.saveBtn}
          hitSlop={8}
        >
          <Text style={[s.saveBtnText, loading && s.saveBtnTextDisabled]}>
            {loading ? 'Saving...' : 'Save'}
          </Text>
        </Pressable>
      </View>

      {/* ── Form ─────────────────────────────────────────────── */}
      <KeyboardAvoidingView
        style={s.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
          <ScrollView
            contentContainerStyle={s.scrollContent}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
            onScrollBeginDrag={Platform.OS !== 'web' ? Keyboard.dismiss : undefined}
          >

            {/* ── Avatar ─────────────────────────────────────── */}
            <View style={s.avatarSection}>
              <TouchableOpacity
                style={s.avatarRing}
                onPress={handleAvatarPress}
                activeOpacity={0.75}
                disabled={avatarUploading}
              >
                {avatarUrl ? (
                  <Image
                    source={{ uri: avatarUrl }}
                    style={s.avatarImage}
                    contentFit="cover"
                  />
                ) : (
                  <View style={s.avatarFallback}>
                    <Text style={s.avatarInitials}>{initials}</Text>
                  </View>
                )}

                {/* Uploading overlay */}
                {avatarUploading && (
                  <View style={s.avatarOverlay}>
                    <ActivityIndicator color={colors.text} size="small" />
                  </View>
                )}

                {/* Edit badge — bottom-right corner */}
                {!avatarUploading && (
                  <View style={s.avatarEditBadge}>
                    <Text style={s.avatarEditIcon}>📷</Text>
                  </View>
                )}
              </TouchableOpacity>

              <TouchableOpacity
                onPress={handleAvatarPress}
                disabled={avatarUploading}
                activeOpacity={0.7}
              >
                <Text style={s.changePhotoText}>
                  {avatarUploading ? 'Uploading...' : 'Change Photo'}
                </Text>
              </TouchableOpacity>
            </View>

            {/* ── Display Name ───────────────────────────────── */}
            <Text style={s.label}>Display Name *</Text>
            <TextInput
              style={[s.input, submitted && errors.displayName ? s.inputErr : null]}
              placeholder="How others see you"
              placeholderTextColor={colors.textPlaceholder}
              value={displayName}
              onChangeText={setDisplayName}
              maxLength={50}
              autoCapitalize="words"
              returnKeyType="next"
            />
            {submitted && <FieldError msg={errors.displayName} />}

            {/* ── Phone Number ───────────────────────────────── */}
            {/* Internal state `phoneNumber` is digits-only. The TextInput
                renders the formatted display "(305) 555-1234" while
                typing. onChangeText strips formatting characters and
                caps at 10 digits so paste from any source normalizes. */}
            <Text style={s.label}>Phone Number</Text>
            <TextInput
              style={[s.input, submitted && errors.phoneNumber ? s.inputErr : null]}
              placeholder="(305) 555-1234"
              placeholderTextColor={colors.textPlaceholder}
              value={formatPhoneDisplay(phoneNumber)}
              onChangeText={(v) => setPhoneNumber(toPhoneDigits(v))}
              keyboardType="phone-pad"
              textContentType="telephoneNumber"
              autoComplete="tel-national"
              maxLength={PHONE_DISPLAY_MAXLENGTH}
              returnKeyType="next"
            />
            {submitted && <FieldError msg={errors.phoneNumber} />}

            {/* ── Bio ────────────────────────────────────────── */}
            <View style={s.labelRow}>
              <Text style={s.label}>Bio</Text>
              <Text style={[s.charCount, bio.trim().length > 200 && s.charCountOver]}>
                {bio.trim().length}/200
              </Text>
            </View>
            <TextInput
              style={[s.input, s.textArea, submitted && errors.bio ? s.inputErr : null]}
              placeholder="Tell others about yourself"
              placeholderTextColor={colors.textPlaceholder}
              value={bio}
              onChangeText={setBio}
              multiline
              numberOfLines={4}
              maxLength={200}
              textAlignVertical="top"
            />
            {submitted && <FieldError msg={errors.bio} />}

            {/* ── Validation summary ─────────────────────────── */}
            {submitted && !isValid && (
              <Text style={s.validationMsg}>
                Please fix the errors above before saving.
              </Text>
            )}

            {/* ── Save button (bottom) ───────────────────────── */}
            <Pressable
              style={[s.saveBottomBtn, loading && s.saveBottomBtnBusy]}
              onPress={handleSave}
              disabled={loading}
            >
              {loading ? (
                <ActivityIndicator color={colors.text} />
              ) : (
                <Text style={s.saveBottomBtnText}>Save Changes</Text>
              )}
            </Pressable>

            <View style={{ height: 56 }} />
          </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.bg },
  flex: { flex: 1 },

  // Top bar
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  // Save button (top-right)
  saveBtn:     { width: 70, height: 44, alignItems: 'flex-end', justifyContent: 'center' },
  saveBtnText: { color: colors.primary, fontSize: fontSize.md, fontWeight: '700' },
  saveBtnTextDisabled: { opacity: 0.5 },

  // Loader
  loader: { flex: 1, justifyContent: 'center', alignItems: 'center' },

  // Scroll content
  scrollContent: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: 48,
  },

  // ── Avatar section ──────────────────────────────────────────────────────────
  avatarSection: {
    alignItems: 'center',
    marginBottom: spacing.xl,
  },
  avatarRing: {
    width:          RING_SIZE,
    height:         RING_SIZE,
    borderRadius:   RING_SIZE / 2,
    borderWidth:    2,
    borderColor:    colors.primary,
    alignItems:     'center',
    justifyContent: 'center',
    marginBottom:   spacing.sm,
    // Glow via shadow (matches profile tab)
    shadowColor:    colors.primary,
    shadowOffset:   { width: 0, height: 0 },
    shadowOpacity:  0.6,
    shadowRadius:   12,
    elevation:      10,
  },
  avatarImage: {
    width:        AVATAR_SIZE,
    height:       AVATAR_SIZE,
    borderRadius: AVATAR_SIZE / 2,
  },
  avatarFallback: {
    width:            AVATAR_SIZE,
    height:           AVATAR_SIZE,
    borderRadius:     AVATAR_SIZE / 2,
    backgroundColor:  colors.primarySoft,
    alignItems:       'center',
    justifyContent:   'center',
  },
  avatarInitials: {
    fontSize:   fontSize.xl,
    fontWeight: '800',
    color:      colors.primary,
  },
  avatarOverlay: {
    position:        'absolute',
    inset:           0,
    borderRadius:    AVATAR_SIZE / 2,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems:      'center',
    justifyContent:  'center',
  },
  avatarEditBadge: {
    position:        'absolute',
    bottom:          0,
    right:           0,
    width:           28,
    height:          28,
    borderRadius:    14,
    backgroundColor: colors.primary,
    alignItems:      'center',
    justifyContent:  'center',
    borderWidth:     2,
    borderColor:     colors.bg,
  },
  avatarEditIcon: {
    fontSize: 14,
    lineHeight: 16,
  },
  changePhotoText: {
    color:      colors.primary,
    fontSize:   fontSize.sm,
    fontWeight: '600',
  },

  // Labels
  label: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    marginBottom: 6,
  },
  labelRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
  },
  charCount: {
    fontSize: fontSize.xs,
    color: colors.textDim,
    fontVariant: ['tabular-nums'],
  },
  charCountOver: {
    color: colors.error,
    fontWeight: '700',
  },

  // Inputs
  input: {
    backgroundColor: colors.bgInput,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.borderInput,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: 13,
    fontSize: fontSize.md,
    marginBottom: spacing.md,
  },
  inputErr: {
    borderColor: colors.error,
  },
  textArea: {
    height: 100,
    textAlignVertical: 'top',
    paddingTop: 13,
  },

  // Field error
  fieldError: {
    color: colors.error,
    fontSize: fontSize.xs,
    marginTop: -8,
    marginBottom: 8,
  },

  // Validation summary
  validationMsg: {
    color: colors.error,
    fontSize: fontSize.sm,
    textAlign: 'center',
    marginTop: spacing.sm,
  },

  // Save button (bottom)
  saveBottomBtn: {
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: radius.md,
    alignItems: 'center',
    marginTop: spacing.lg,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 10,
    elevation: 6,
  },
  saveBottomBtnBusy: {
    opacity: 0.65,
  },
  saveBottomBtnText: {
    color: colors.text,
    fontWeight: '800',
    fontSize: fontSize.md,
    letterSpacing: 0.8,
  },
});
