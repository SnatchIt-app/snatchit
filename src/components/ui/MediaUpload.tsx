/**
 * src/components/ui/MediaUpload.tsx — the V2 image/file upload control.
 *
 * Replaces the legacy dashed-box + emoji ImageUploadTile. Two variants share one
 * behaviour contract (localUri / status / error from useImageUpload):
 *
 *  - `cover`   — a compact media picker. Empty: a tappable row (icon + label +
 *                helper + add). Selected: a real 16:9 preview with Replace / Remove.
 *  - `compact` — for functional evidence (proof of ownership, transfer proof).
 *                Empty: a single slim row (icon + label + helper + Add). Selected:
 *                a small thumbnail + "Image added" + Replace / Remove.
 *
 * No emoji — icons come from the app's IconSymbol set. Sharp (radius 0), hairline,
 * dark surface. No giant empty canvas.
 */

import { Image } from 'expo-image';
import { useMemo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { Spinner } from '@/src/components/ui/Spinner';
import { type UploadStatus } from '@/src/hooks/useImageUpload';
import { UPLOAD_COPY } from '@/src/lib/media/uploadFlow';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface MediaUploadProps {
  variant: 'cover' | 'compact';
  localUri: string | null;
  status: UploadStatus;
  error: string | null;
  /** Open the picker (useImageUpload().pickImage). */
  onPress: () => void;
  /** Clear the selection (useImageUpload().reset). Enables the Remove action. */
  onRemove?: () => void;
  label: string;
  helper: string;
  /** SF Symbol name for the empty-state icon (e.g. 'photo', 'doc.text'). */
  icon: string;
  hasError?: boolean;
  disabled?: boolean;
}

export function MediaUpload({
  variant, localUri, status, error, onPress, onRemove, label, helper, icon, hasError = false, disabled = false,
}: MediaUploadProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const hasImage = !!localUri;
  const uploading = status === 'uploading';
  // F-IMG-1a: while the photo sheet is opening the control says so and takes no taps.
  const picking = status === 'picking';
  const working = uploading || picking;
  const locked = disabled || working;
  const isError = status === 'error';
  const errored = hasError || isError;
  const borderColor = errored ? palette.status.error : hasImage ? palette.border.strong : palette.border.default;

  const actions = hasImage && !uploading ? (
    <View style={[s.actions, picking && s.disabled]}>
      <Pressable onPress={locked ? undefined : onPress} hitSlop={8} accessibilityRole="button" accessibilityLabel={`Replace ${label}`} accessibilityState={{ disabled: locked, busy: picking }}>
        <Text style={[textStyle('label'), s.replace]}>Replace</Text>
      </Pressable>
      {onRemove ? (
        <Pressable onPress={locked ? undefined : onRemove} hitSlop={8} accessibilityRole="button" accessibilityLabel={`Remove ${label}`} accessibilityState={{ disabled: locked }}>
          <Text style={[textStyle('label'), s.remove]}>Remove</Text>
        </Pressable>
      ) : null}
    </View>
  ) : null;

  // ── Cover: compact row when empty, 16:9 preview when selected ────────────────
  if (variant === 'cover') {
    if (!hasImage) {
      return (
        <View>
          <Pressable
            onPress={locked ? undefined : onPress}
            style={[s.emptyRow, { borderColor }, disabled && s.disabled]}
            accessibilityRole="button"
            accessibilityLabel={label}
            accessibilityHint={helper}
            accessibilityState={{ disabled: locked, busy: picking }}
          >
            <IconSymbol name={icon as never} size={22} color={palette.text.muted} />
            <View style={s.emptyText}>
              <Text style={[textStyle('title'), s.label]} numberOfLines={1}>{label}</Text>
              <Text style={[textStyle('bodySm'), errored && !picking ? s.helperErr : s.helper]} numberOfLines={2}>
                {picking ? UPLOAD_COPY.opening : isError && error ? error : helper}
              </Text>
            </View>
            {picking ? <Spinner color={palette.brand.redText} /> : <IconSymbol name={'plus' as never} size={20} color={palette.brand.redText} />}
          </Pressable>
        </View>
      );
    }
    return (
      <View style={[s.coverWrap, { borderColor }]}>
        <Image source={{ uri: localUri! }} style={s.coverImage} contentFit="cover" transition={200} />
        {working ? (
          <View style={s.overlay} accessibilityLabel={picking ? UPLOAD_COPY.opening : `Uploading ${label}`}><Spinner color={palette.text.primary} /></View>
        ) : (
          <View style={s.coverBar}>{actions}</View>
        )}
      </View>
    );
  }

  // ── Compact: slim row (evidence) ─────────────────────────────────────────────
  return (
    <View style={[s.compactRow, { borderColor }, disabled && s.disabled]}>
      {hasImage ? (
        <Image source={{ uri: localUri! }} style={s.thumb} contentFit="cover" transition={200} />
      ) : (
        <View style={s.compactIcon}><IconSymbol name={icon as never} size={20} color={palette.text.muted} /></View>
      )}
      <View style={s.compactText}>
        <Text style={[textStyle('title'), s.label]} numberOfLines={1}>{label}</Text>
        <Text style={[textStyle('bodySm'), errored && !picking ? s.helperErr : s.helper]} numberOfLines={2}>
          {picking ? UPLOAD_COPY.opening : isError && error ? error : hasImage ? 'Image added' : helper}
        </Text>
      </View>
      {working ? (
        <Spinner color={palette.brand.redText} />
      ) : hasImage ? (
        actions
      ) : (
        <Pressable onPress={locked ? undefined : onPress} hitSlop={8} accessibilityRole="button" accessibilityLabel={label} accessibilityHint={helper} accessibilityState={{ disabled: locked }}>
          <Text style={[textStyle('label'), s.replace]}>Add</Text>
        </Pressable>
      )}
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  disabled: { opacity: 0.5 },
  label: { color: p.text.primary },
  helper: { color: p.text.muted, marginTop: 1 },
  helperErr: { color: p.status.error, marginTop: 1 },

  actions: { flexDirection: 'row', gap: v2.space.md, alignItems: 'center' },
  replace: { color: p.brand.redText },
  remove: { color: p.status.error },

  // cover empty
  emptyRow: {
    flexDirection: 'row', alignItems: 'center', gap: v2.space.md,
    minHeight: 72, paddingHorizontal: v2.space.md,
    borderWidth: 1, backgroundColor: p.surface.surface,
  },
  emptyText: { flex: 1, minWidth: 0 },

  // cover selected
  coverWrap: { borderWidth: 1, backgroundColor: p.surface.surface },
  coverImage: { width: '100%', aspectRatio: 16 / 9 },
  coverBar: {
    flexDirection: 'row', justifyContent: 'flex-end', alignItems: 'center',
    paddingHorizontal: v2.space.md, paddingVertical: v2.space.sm,
    borderTopWidth: 1, borderTopColor: p.border.default,
  },
  overlay: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.55)', alignItems: 'center', justifyContent: 'center' },

  // compact
  compactRow: {
    flexDirection: 'row', alignItems: 'center', gap: v2.space.md,
    minHeight: 64, paddingHorizontal: v2.space.md, paddingVertical: v2.space.sm,
    borderWidth: 1, backgroundColor: p.surface.surface,
  },
  compactIcon: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center', backgroundColor: p.surface.elevated },
  thumb: { width: 40, height: 40 },
  compactText: { flex: 1, minWidth: 0 },
  });
}
