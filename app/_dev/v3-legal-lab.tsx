/**
 * app/_dev/v3-legal-lab.tsx — DEVELOPMENT RENDERING ONLY (C-RC3-1 diagnosis, build 3: no probes).
 *
 * Mounts the REAL full-Terms card (app/settings/legal.tsx → FullTermsBody) under one mount condition
 * chosen by `?variant=`:
 *   toggle   — mounted on a tap, as the screen does (`{open && <FullTermsBody/>}`)
 *   first    — mounted on first render
 *   display  — pre-mounted, `display:none` until the tap
 *   wrapped  — mounted on a tap, every paragraph wrapped in a View
 *   key      — mounted on a tap, the card re-keyed once more 50 ms after mount (forces a remount)
 *   nocard   — mounted on a tap, the card without its background and border (layer-size check)
 *   noslack  — mounted on a tap, the paragraph styles WITHOUT the half-point bottom padding (the control for the fix)
 * `?pad=N` inserts an empty N-pt spacer above the toggle; `?filler=N` inserts N long paragraphs above it —
 * the Legal screen has ~2,300 pt of summary above its card, the lab had none (build 3: no clip in the lab).
 * No probes (they force the re-layout that masks the defect). Gated like every _dev route.
 */
import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { FullTermsBody, makeStyles } from '@/app/settings/legal';
import { useTheme } from '@/src/theme/appearance';
import * as v2 from '@/src/theme/v2';

declare const __DEV__: boolean;

export default function V3LegalLab() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { variant, pad, filler } = useLocalSearchParams<{ variant?: string; pad?: string; filler?: string }>();
  const v = variant ?? 'toggle';
  const padPt = Math.max(0, Number(pad ?? 0) || 0);
  const fillerN = Math.max(0, Number(filler ?? 0) || 0);
  const FILLER = "Filler paragraph for the lab only. It exists to push the card to a chosen offset and carries no product wording: the quick brown fox jumps over the lazy dog, the lazy dog looks on, and the fox keeps running along the river until the light goes, then turns back along the same path to where it started, counting the stones it passes and the bends in the water, which is enough prose to fill six or seven lines at the Terms body size so that each filler block is about as tall as a long clause would be.";
  const sNoSlack = useMemo(() => ({ ...s, ftBody: { ...s.ftBody, paddingBottom: 0 }, bulletText: { ...s.bulletText, paddingBottom: 0 } }) as unknown as typeof s, [s]);
  const sNoCard = useMemo(() => ({ ...s, fullTermsBody: { ...s.fullTermsBody, backgroundColor: 'transparent', borderWidth: 0 } }) as unknown as typeof s, [s]);
  const [open, setOpen] = useState(v === 'first');
  const [k, setK] = useState(0);
  useEffect(() => { if (v === 'key' && open) { const t = setTimeout(() => setK(1), 50); return () => clearTimeout(t); } }, [v, open]);
  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;
  return (
    <ScrollView style={s.scroll} contentContainerStyle={[s.content, { paddingTop: 80, paddingBottom: 120 }]}>
      {padPt > 0 ? <View style={{ height: padPt }} /> : null}
      {Array.from({ length: fillerN }, (_, i) => <Text key={i} style={[s.ftBody, { marginBottom: 12 }]}>{`${i + 1}. ${FILLER}`}</Text>)}
      <Pressable onPress={() => setOpen((o) => !o)} accessibilityRole="button" style={{ padding: v2.space.md, borderWidth: 1, borderColor: palette.border.default, marginBottom: 8 }}>
        <Text style={{ color: palette.text.primary }}>legal-lab · variant={v} · pad={padPt} · filler={fillerN} · open={String(open)} · tap to toggle</Text>
      </Pressable>
      {v === 'display'
        ? <View style={{ display: open ? 'flex' : 'none' }}><FullTermsBody s={s} /></View>
        : v === 'wrapped'
          ? (open && <FullTermsBody s={s} wrapParagraphs />)
          : v === 'key'
            ? (open && <View key={k}><FullTermsBody s={s} /></View>)
            : v === 'nocard'
              ? (open && <FullTermsBody s={sNoCard} />)
              : v === 'noslack'
                ? (open && <FullTermsBody s={sNoSlack} />)
                : (open && <FullTermsBody s={s} />)}
    </ScrollView>
  );
}
