/**
 * app/settings/preferences.tsx — Neighborhood Preferences (placeholder)
 * TODO: Let users pick favourite neighbourhoods to filter the home feed.
 */

import { router } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { colors, fontSize, spacing } from '@/src/theme';

export default function PreferencesScreen() {
  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>←</Text>
        </Pressable>
        <Text style={s.topTitle}>Neighborhood</Text>
        <View style={s.backBtn} />
      </View>

      <View style={s.body}>
        <Text style={s.icon}>📍</Text>
        <Text style={s.title}>Neighborhood Preferences</Text>
        <Text style={s.sub}>
          Neighborhood filtering is coming soon.{'\n'}
          You'll be able to pin favourite areas so the home feed shows relevant listings first.
        </Text>
      </View>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe:      { flex: 1, backgroundColor: colors.bg },
  topBar:    { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
               paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
               borderBottomWidth: 1, borderBottomColor: colors.border },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },
  body:      { flex: 1, alignItems: 'center', justifyContent: 'center',
               paddingHorizontal: spacing.xl, gap: spacing.md },
  icon:      { fontSize: 48 },
  title:     { fontSize: fontSize.lg, fontWeight: '800', color: colors.text },
  sub:       { fontSize: fontSize.sm, color: colors.textMuted, textAlign: 'center', lineHeight: 20 },
});
