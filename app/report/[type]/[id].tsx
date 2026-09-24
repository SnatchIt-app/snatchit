/**
 * app/report/[type]/[id].tsx — Report a listing or a user (V2).
 *
 * PRESENTATION rebuilt on the V2 system; behaviour unchanged. Reason radio picker
 * (filtered by target type) + optional notes (max 1000) → insert into
 * public.reports → confirmation → back. App Store Guideline 1.2. Reached from the
 * listing overflow (`/report/listing/<id>`) and the public profile
 * (`/report/user/<id>`).
 *
 * PREMIUM BATCH 2 (CFT-203/208). Submit reads "Sending report…" while in
 * flight, and a back gesture with a reason chosen or notes typed asks first.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type TextStyle } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useUnsavedChangesGuard } from '@/src/hooks/useUnsavedChangesGuard';
import { shouldAskBeforeLeaving, UNSAVED_COPY } from '@/src/lib/nav/unsavedChanges';
import { Button } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { ReportReason, ReportTargetType } from '@/src/types';

const REASONS: { value: ReportReason; label: string; appliesTo: ReportTargetType[] }[] = [
  { value: 'fraud_or_scam',          label: 'Fraud or scam',                  appliesTo: ['listing', 'user'] },
  { value: 'counterfeit_or_invalid', label: 'Counterfeit or invalid ticket',  appliesTo: ['listing'] },
  { value: 'inappropriate_content',  label: 'Inappropriate content',          appliesTo: ['listing', 'user'] },
  { value: 'misleading',             label: 'Misleading information',         appliesTo: ['listing', 'user'] },
  { value: 'harassment',             label: 'Harassment or abusive behavior', appliesTo: ['user'] },
  { value: 'other',                  label: 'Other',                          appliesTo: ['listing', 'user'] },
];

export default function ReportScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { user } = useAuth();
  const params = useLocalSearchParams<{ type: string; id: string }>();
  const targetType = (params.type === 'user' ? 'user' : 'listing') as ReportTargetType;
  const targetId = params.id ?? '';

  const reasonOptions = useMemo(() => REASONS.filter((r) => r.appliesTo.includes(targetType)), [targetType]);

  const [reason, setReason] = useState<ReportReason | null>(null);
  const [notes, setNotes] = useState('');
  const [notesFocused, setNotesFocused] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [sent, setSent] = useState(false);

  // Something to lose: a reason chosen or notes typed (CFT-208).
  const dirty = reason != null || notes.trim().length > 0;
  useUnsavedChangesGuard({
    when: shouldAskBeforeLeaving({ dirty, submitting, saved: sent }),
    ...UNSAVED_COPY.report,
  });

  const titleNoun = targetType === 'user' ? 'user' : 'listing';

  async function handleSubmit() {
    if (!reason || !targetId) return;
    if (!user) { Alert.alert('Sign in required', 'You need to be signed in to submit a report.'); return; }
    setSubmitting(true);
    try {
      const { error } = await supabase.from('reports').insert({
        reporter_id: user.id, target_type: targetType, target_id: targetId, reason, notes: notes.trim() || null,
      });
      if (error) {
        console.warn('[report] insert error:', error.message);
        Alert.alert('Could not submit report', 'Please try again in a moment.');
        return;
      }
      setSent(true); // the guard stands down; the alert's OK navigates back
      Alert.alert('Report submitted', 'Thanks for letting us know. We review reports within 24 hours and act on what we find.', [
        { text: 'OK', onPress: () => router.back() },
      ]);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <View style={s.root}>
      <SettingsHeader title={`Report ${titleNoun}`} />
      <KeyboardAvoidingView style={s.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
          <Text style={[textStyle('body'), s.lead]}>
            Tell us what&apos;s wrong with this {titleNoun}. Our team reviews every report and may remove content or suspend accounts that violate our rules.
          </Text>

          <Text style={[textStyle('micro'), s.sectionLabel]}>Reason</Text>
          <View style={s.reasons}>
            {reasonOptions.map((opt) => {
              const selected = reason === opt.value;
              return (
                <Pressable
                  key={opt.value}
                  onPress={() => setReason(opt.value)}
                  style={s.reasonRow}
                  accessibilityRole="radio"
                  accessibilityState={{ selected }}
                  accessibilityLabel={opt.label}
                >
                  <View style={[s.radio, selected && s.radioOn]}>{selected ? <View style={s.radioDot} /> : null}</View>
                  <Text style={[textStyle('body'), s.reasonLabel]}>{opt.label}</Text>
                </Pressable>
              );
            })}
          </View>

          <Text style={[textStyle('micro'), s.sectionLabel]}>Additional details (optional)</Text>
          <TextInput
            style={[textStyle('body') as TextStyle, s.notes, { borderBottomColor: notesFocused ? palette.brand.red : palette.border.strong }]}
            placeholder="Anything else our team should know?"
            placeholderTextColor={palette.text.faint}
            value={notes}
            onChangeText={setNotes}
            onFocus={() => setNotesFocused(true)}
            onBlur={() => setNotesFocused(false)}
            selectionColor={palette.brand.red}
            multiline
            maxLength={1000}
            accessibilityLabel="Additional details"
          />
          <Text style={[textStyle('bodySm'), s.charCount]}>{notes.length} / 1000</Text>

          <Button label="Submit report" pendingLabel="Sending report…" onPress={handleSubmit} loading={submitting} disabled={!reason || submitting} block style={s.submit} />

          <Text style={[textStyle('bodySm'), s.fineprint]}>
            Reports are reviewed by the Snatch It team. False or repeated bad-faith reports may result in your account being suspended.
          </Text>
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },
  flex: { flex: 1 },
  body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, paddingBottom: v2.space.xxl },
  lead: { color: p.text.secondary, marginBottom: v2.space.lg },
  sectionLabel: { color: p.text.muted, marginTop: v2.space.lg, marginBottom: v2.space.sm },

  reasons: { borderTopWidth: 1, borderTopColor: p.border.default },
  reasonRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.md, minHeight: 52, paddingVertical: v2.space.sm, borderBottomWidth: 1, borderBottomColor: p.border.default },
  radio: { width: 22, height: 22, borderRadius: 11, borderWidth: 2, borderColor: p.border.strong, alignItems: 'center', justifyContent: 'center' },
  radioOn: { borderColor: p.brand.red },
  radioDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: p.brand.red },
  reasonLabel: { flex: 1, color: p.text.primary },

  notes: { minHeight: 96, color: p.text.primary, borderBottomWidth: 1, paddingVertical: v2.space.sm, textAlignVertical: 'top' },
  charCount: { color: p.text.faint, alignSelf: 'flex-end', marginTop: v2.space.xs, fontVariant: ['tabular-nums'] },

  submit: { marginTop: v2.space.xl },
  fineprint: { color: p.text.muted, textAlign: 'center', marginTop: v2.space.lg },
  });
}
