/**
 * app/settings/preferences.tsx — Your scene (V2).
 *
 * PRESENTATION rebuilt on the V2 system; behaviour is unchanged. The multi-select
 * neighborhood picker hydrates from `get_my_profile`, saves to
 * `profiles.preferred_neighborhoods`, and — critically — a FAILED save never looks
 * like a success: the raw Postgres string is logged, a human `saveError` is shown,
 * and the screen does NOT navigate back. Only a successful save returns.
 */

import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import type { MyProfileRPC } from '@/src/types';
import { useAuth } from '@/src/hooks/useAuth';
import { Button, Chip, Spinner, StickyBar } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import { NEIGHBORHOODS, NEIGHBORHOOD_LABELS } from '@/src/constants/neighborhoods';

export default function PreferencesScreen() {
  const { user, loading: authLoading } = useAuth();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  // A failed save used to look exactly like a success. It must not.
  const [saveError, setSaveError] = useState<string | null>(null);

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
    if (saveError) setSaveError(null);
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(hood)) next.delete(hood); else next.add(hood);
      return next;
    });
  }

  async function save() {
    if (!user) return;
    setSaving(true);
    setSaveError(null);
    const { error } = await supabase
      .from('profiles')
      .update({ preferred_neighborhoods: Array.from(selected) })
      .eq('id', user.id);
    setSaving(false);
    if (error) {
      console.warn('[preferences] save failed:', error.message);
      setSaveError("We couldn't save your scene. Check your connection and try again.");
      return;
    }
    router.back();
  }

  return (
    <View style={s.root}>
      <SettingsHeader title="Your scene" />
      {loading ? (
        <View style={s.center}><Spinner color={v2.brand.red} /></View>
      ) : (
        <>
          <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
            <Text style={[textStyle('bodySm'), s.helper]}>
              Pick the areas you go out in most. We&apos;ll show those listings first.
            </Text>
            <View style={s.grid}>
              {NEIGHBORHOODS.map((hood) => (
                <Chip key={hood} label={NEIGHBORHOOD_LABELS[hood]} selected={selected.has(hood)} onPress={() => toggle(hood)} />
              ))}
            </View>
            {saveError ? (
              <Text style={[textStyle('bodySm'), s.saveError]} accessibilityRole="alert">{saveError}</Text>
            ) : null}
          </ScrollView>
          <StickyBar>
            <Button label="Save" onPress={save} loading={saving} disabled={saving} block />
          </StickyBar>
        </>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, paddingBottom: v2.space.xxl },
  helper: { color: v2.text.muted, marginBottom: v2.space.lg },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.sm },
  saveError: { color: v2.status.error, marginTop: v2.space.lg },
});
