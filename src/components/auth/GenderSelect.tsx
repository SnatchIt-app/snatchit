/**
 * src/components/auth/GenderSelect.tsx — the three gender options on Sign up.
 *
 * Built from the existing V2 Chip, so selection looks and behaves the way every
 * other choice in the product does. Three options, no icons, no emoji, no
 * explanatory paragraph. The labels are the product's; the values written to the
 * database are the vocabulary the kernel demographics contract already accepts.
 *
 * The row is a radiogroup so VoiceOver announces it as one choice rather than as
 * three unrelated buttons.
 */

import { StyleSheet, Text, View } from 'react-native';

import { Chip } from '@/src/components/ui';
import { GENDER_OPTIONS, type GenderValue } from '@/src/lib/auth/signupFlow';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface GenderSelectProps {
  value: GenderValue | null;
  onChange: (value: GenderValue) => void;
  label?: string;
}

export function GenderSelect({ value, onChange, label = 'Gender' }: GenderSelectProps) {
  return (
    <View accessibilityRole="radiogroup" accessibilityLabel={label}>
      <Text style={[textStyle('micro'), s.label]}>{label}</Text>
      <View style={s.row}>
        {GENDER_OPTIONS.map((option) => (
          <Chip
            key={option.value}
            label={option.label}
            selected={value === option.value}
            onPress={() => onChange(option.value)}
            style={s.chip}
            testID={`gender-${option.value}`}
          />
        ))}
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  label: { color: v2.text.muted, marginBottom: v2.space.sm },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.sm },
  chip: { marginBottom: 0 },
});
