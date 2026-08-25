/**
 * app/settings/preferences.tsx — Your Scene
 * Multi-select neighborhood picker. Saves to profiles.preferred_neighborhoods.
 */

import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import type { MyProfileRPC } from '@/src/types';
import { useAuth } from '@/src/hooks/useAuth';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import { NEIGHBORHOODS, NEIGHBORHOOD_LABELS } from '@/src/constants/neighborhoods';

// ─── Screen ──────────────────────────────────────────────────────────────────

export default function PreferencesScreen() {
  const { user, loading: authLoading } = useAuth();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading]   = useState(true);
  const [saving, setSaving]     = useState(false);

  // Hydrate saved selections once auth resolves
  useEffect(() => {
    if (authLoading) return;
    if (!user) { setLoading(false); return; }

    let ignore = false;

    (async () => {
      const { data } = await supabase.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle();

      if (ignore) return;

      const saved = data?.preferred_neighborhoods;
      setSelected(new Set(Array.isArray(saved) ? saved : []));
      setLoading(false);
    })();

    return () => { ignore = true; };
  }, [user?.id, authLoading]);

  function toggle(hood: string) {
    setSelected(prev => {
      const next = new Set(prev);
      next.has(hood) ? next.delete(hood) : next.add(hood);
      return next;
    });
  }

  async function save() {
    if (!user) return;
    setSaving(true);

    await supabase
      .from('profiles')
      .update({ preferred_neighborhoods: Array.from(selected) })
      .eq('id', user.id);

    setSaving(false);
    router.back();
  }

  // ── Render ──────────────────────────────────────────────────────────────────
  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>←</Text>
        </Pressable>
        <Text style={s.topTitle}>Your Scene</Text>
        <View style={s.backBtn} />
      </View>

      {loading ? (
        <View style={s.loader}>
          <ActivityIndicator color={colors.primary} />
        </View>
      ) : (
        <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false}>
          <Text style={s.helper}>
            Pick the areas you go out in most. We&apos;ll show those listings first.
          </Text>

          <View style={s.grid}>
            {NEIGHBORHOODS.map(hood => {
              const active = selected.has(hood);
              return (
                <Pressable
                  key={hood}
                  style={[s.chip, active && s.chipActive]}
                  onPress={() => toggle(hood)}
                >
                  <Text style={[s.chipText, active && s.chipTextActive]}>
                    {NEIGHBORHOOD_LABELS[hood]}
                  </Text>
                </Pressable>
              );
            })}
          </View>

          <Pressable
            style={[s.saveBtn, saving && { opacity: 0.6 }]}
            onPress={save}
            disabled={saving}
          >
            {saving
              ? <ActivityIndicator color={colors.text} size="small" />
              : <Text style={s.saveBtnText}>Save</Text>
            }
          </Pressable>
        </ScrollView>
      )}
    </SafeAreaView>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe:      { flex: 1, backgroundColor: colors.bg },
  topBar:    {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    borderBottomWidth: 1, borderBottomColor: colors.border,
  },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  loader: { flex: 1, justifyContent: 'center', alignItems: 'center' },

  body: {
    padding: spacing.lg,
    paddingBottom: spacing.xxl,
  },

  helper: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    lineHeight: 20,
    marginBottom: spacing.lg,
  },

  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginBottom: spacing.xl,
  },

  chip: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.full,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgCard,
  },
  chipActive: {
    borderColor: colors.primary,
    backgroundColor: colors.primarySoft,
  },
  chipText: {
    fontSize: fontSize.sm,
    fontWeight: '600',
    color: colors.textMuted,
  },
  chipTextActive: {
    color: colors.primary,
  },

  saveBtn: {
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
  },
  saveBtnText: {
    color: colors.text,
    fontWeight: '800',
    fontSize: fontSize.md,
    letterSpacing: 0.5,
  },
});
