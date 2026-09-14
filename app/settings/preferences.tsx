/**
 * app/settings/preferences.tsx — Your scene (V2).
 *
 * PRESENTATION rebuilt on the V2 system; the data path is unchanged: the
 * multi-select neighborhood picker hydrates from `get_my_profile` and saves to
 * `profiles.preferred_neighborhoods`.
 *
 * PREMIUM BATCH 2 (CFT-204, item 11). Choosing an area updates at once and
 * saves in the background — latest wins, one save in flight. A FAILED save
 * never looks like a success: the chips return to what the server holds and a
 * short notice says so (also announced to a screen reader). "Done" waits for
 * an in-flight save and leaves only when the last change is committed; a back
 * gesture while a save is still running asks first.
 */

import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, ScrollView, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import type { MyProfileRPC } from '@/src/types';
import { useAuth } from '@/src/hooks/useAuth';
import { useUnsavedChangesGuard } from '@/src/hooks/useUnsavedChangesGuard';
import { UNSAVED_COPY } from '@/src/lib/nav/unsavedChanges';
import { createCoalescedSaver, type CoalescedSaver } from '@/src/lib/settings/coalescedSave';
import { Button, Chip, Spinner, StickyBar } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import { NEIGHBORHOODS, NEIGHBORHOOD_LABELS } from '@/src/constants/neighborhoods';

/** Shown, briefly, when a background save fails and the chips roll back. */
const SCENE_ROLLBACK_NOTICE =
  "We couldn't save that change, so it's back to what you had. Check your connection and try again.";

export default function PreferencesScreen() {
  const { user, loading: authLoading } = useAuth();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const saverRef = useRef<CoalescedSaver<string[]> | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { setLoading(false); return; }
    let ignore = false;
    (async () => {
      const { data } = await supabase.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle();
      if (ignore) return;
      const saved = data?.preferred_neighborhoods;
      const initial: string[] = Array.isArray(saved) ? saved : [];
      setSelected(new Set(initial));
      saverRef.current = createCoalescedSaver<string[]>({
        initial,
        save: async (hoods) => {
          const { error } = await supabase
            .from('profiles')
            .update({ preferred_neighborhoods: hoods })
            .eq('id', user.id);
          if (error) console.warn('[preferences] save failed:', error.message);
          return !error;
        },
        // A failed save must not look like a success: show what the server
        // holds, and say so once, briefly.
        onRollback: (committed) => {
          setSelected(new Set(committed));
          setNotice(SCENE_ROLLBACK_NOTICE);
          AccessibilityInfo.announceForAccessibility(SCENE_ROLLBACK_NOTICE);
        },
        onPendingChange: setPending,
      });
      setLoading(false);
    })();
    return () => { ignore = true; };
  }, [user?.id, authLoading]);

  // A back gesture while a save is still in flight asks first (CFT-208).
  useUnsavedChangesGuard({ when: pending, ...UNSAVED_COPY.stillSaving });

  function toggle(hood: string) {
    setNotice(null);
    const next = new Set(selected);
    if (next.has(hood)) next.delete(hood); else next.add(hood);
    // Reversible (item 11): shown at once, saved behind it, rolled back above.
    setSelected(next);
    saverRef.current?.submit(Array.from(next));
  }

  async function done() {
    const ok = (await saverRef.current?.settle()) ?? true;
    // On failure the rollback notice is already on screen; the user decides.
    if (ok) router.back();
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
              Pick the areas you go out in most. We&apos;ll show those listings first. Changes save as you go.
            </Text>
            <View style={s.grid}>
              {NEIGHBORHOODS.map((hood) => (
                <Chip key={hood} label={NEIGHBORHOOD_LABELS[hood]} selected={selected.has(hood)} onPress={() => toggle(hood)} />
              ))}
            </View>
            {notice ? (
              <Text style={[textStyle('bodySm'), s.notice]} accessibilityRole="alert">{notice}</Text>
            ) : null}
          </ScrollView>
          <StickyBar>
            <Button label="Done" pendingLabel="Saving…" onPress={done} loading={pending} disabled={pending} block />
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
  notice: { color: v2.status.error, marginTop: v2.space.lg },
});
