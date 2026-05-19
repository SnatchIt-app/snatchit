/**
 * app/report/[type]/[id].tsx — Report a listing or a user.
 *
 * Reached from the listing-detail overflow menu:
 *   • /report/listing/<listing-id>
 *   • /report/user/<seller-user-id>
 *
 * UX: reason picker (radio) + optional notes (max 1000 chars).
 * Submission inserts into public.reports (migration 023). The reporter
 * sees a confirmation, then is routed back. Ops handles via SQL editor.
 *
 * App Store Guideline 1.2 — content / user reporting surface.
 */
import { router, useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
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
import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { ReportReason, ReportTargetType } from '@/src/types';

const REASONS: { value: ReportReason; label: string; appliesTo: ReportTargetType[] }[] = [
  { value: 'fraud_or_scam',          label: 'Fraud or scam',                       appliesTo: ['listing', 'user'] },
  { value: 'counterfeit_or_invalid', label: 'Counterfeit or invalid ticket',       appliesTo: ['listing'] },
  { value: 'inappropriate_content',  label: 'Inappropriate content',               appliesTo: ['listing', 'user'] },
  { value: 'misleading',             label: 'Misleading information',              appliesTo: ['listing', 'user'] },
  { value: 'harassment',             label: 'Harassment or abusive behavior',      appliesTo: ['user'] },
  { value: 'other',                  label: 'Other',                               appliesTo: ['listing', 'user'] },
];

export default function ReportScreen() {
  const { user } = useAuth();
  const params = useLocalSearchParams<{ type: string; id: string }>();
  const targetType = (params.type === 'user' ? 'user' : 'listing') as ReportTargetType;
  const targetId   = params.id ?? '';

  const reasonOptions = useMemo(
    () => REASONS.filter(r => r.appliesTo.includes(targetType)),
    [targetType],
  );

  const [reason, setReason] = useState<ReportReason | null>(null);
  const [notes,  setNotes]  = useState('');
  const [submitting, setSubmitting] = useState(false);

  const titleNoun = targetType === 'user' ? 'user' : 'listing';

  async function handleSubmit() {
    if (!reason)  return;
    if (!targetId) return;
    if (!user) {
      Alert.alert('Sign in required', 'You need to be signed in to submit a report.');
      return;
    }
    setSubmitting(true);
    try {
      const { error } = await supabase.from('reports').insert({
        reporter_id: user.id,
        target_type: targetType,
        target_id:   targetId,
        reason,
        notes:       notes.trim() || null,
      });
      if (error) {
        console.warn('[report] insert error:', error.message);
        Alert.alert('Could not submit report', 'Please try again in a moment.');
        return;
      }
      Alert.alert(
        'Report submitted',
        'Thanks for letting us know. We review reports within 24 hours and act on what we find.',
        [{ text: 'OK', onPress: () => router.back() }],
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'←'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Report {titleNoun}</Text>
        <View style={s.backBtn} />
      </View>

      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          contentContainerStyle={s.body}
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
        >
          <Text style={s.lead}>
            Tell us what's wrong with this {titleNoun}. Our team reviews every
            report and may remove content or suspend accounts that violate our
            rules.
          </Text>

          <Text style={s.sectionLabel}>Reason</Text>
          <View style={s.card}>
            {reasonOptions.map((opt, i) => {
              const selected = reason === opt.value;
              return (
                <Pressable
                  key={opt.value}
                  onPress={() => setReason(opt.value)}
                  style={[
                    s.row,
                    i < reasonOptions.length - 1 && s.rowBorder,
                  ]}
                  android_ripple={{ color: colors.primarySoft }}
                  accessibilityRole="radio"
                  accessibilityState={{ selected }}
                >
                  <View style={[s.radio, selected && s.radioOn]}>
                    {selected && <View style={s.radioDot} />}
                  </View>
                  <Text style={s.rowLabel}>{opt.label}</Text>
                </Pressable>
              );
            })}
          </View>

          <Text style={s.sectionLabel}>Additional details (optional)</Text>
          <TextInput
            style={s.notes}
            placeholder="Anything else our team should know?"
            placeholderTextColor={colors.textPlaceholder}
            value={notes}
            onChangeText={setNotes}
            multiline
            maxLength={1000}
            textAlignVertical="top"
          />
          <Text style={s.charCount}>{notes.length} / 1000</Text>

          <TouchableOpacity
            style={[s.submitBtn, (!reason || submitting) && s.submitBtnDisabled]}
            onPress={handleSubmit}
            disabled={!reason || submitting}
            activeOpacity={0.85}
          >
            {submitting
              ? <ActivityIndicator color={colors.text} size="small" />
              : <Text style={s.submitBtnText}>Submit report</Text>}
          </TouchableOpacity>

          <Text style={s.fineprint}>
            Reports are reviewed by the Snatch It team. False or repeated bad-faith
            reports may result in your account being suspended.
          </Text>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe:     { flex: 1, backgroundColor: colors.bg },
  topBar:   {
    flexDirection:     'row',
    alignItems:        'center',
    justifyContent:    'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical:   spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  backBtn:  { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow:{ color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle: { color: colors.text, fontSize: fontSize.md, fontWeight: '700', textTransform: 'capitalize' },

  body:     { padding: spacing.lg, paddingBottom: spacing.xxl },
  lead:     {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    lineHeight: 20,
    marginBottom: spacing.lg,
  },

  sectionLabel: {
    color: colors.textDim,
    fontSize: fontSize.xs,
    fontWeight: '700',
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
    marginTop: spacing.md,
  },

  card: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
  },
  rowBorder: {
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  rowLabel: { flex: 1, color: colors.text, fontSize: fontSize.md, fontWeight: '500' },

  radio:    {
    width: 22, height: 22, borderRadius: 11,
    borderWidth: 2, borderColor: colors.border,
    alignItems: 'center', justifyContent: 'center',
    marginRight: spacing.md,
  },
  radioOn:  { borderColor: colors.accent },
  radioDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: colors.accent },

  notes: {
    minHeight: 110,
    backgroundColor: colors.bgInput,
    borderWidth: 1,
    borderColor: colors.borderInput,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    color: colors.text,
    fontSize: fontSize.md,
  },
  charCount: {
    color: colors.textDim,
    fontSize: fontSize.xs,
    alignSelf: 'flex-end',
    marginTop: 4,
  },

  submitBtn: {
    backgroundColor: colors.accent,
    paddingVertical: spacing.md,
    borderRadius: radius.md,
    alignItems: 'center',
    marginTop: spacing.xl,
  },
  submitBtnDisabled: { opacity: 0.5 },
  submitBtnText:     { color: colors.text, fontWeight: '700', fontSize: fontSize.md, letterSpacing: 0.5 },

  fineprint: {
    color: colors.textDim,
    fontSize: fontSize.xs,
    lineHeight: 16,
    marginTop: spacing.lg,
    textAlign: 'center',
    paddingHorizontal: spacing.md,
  },
});
