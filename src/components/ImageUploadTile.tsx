/**
 * src/components/ImageUploadTile.tsx
 *
 * Drop-in image picker tile used on the Create Listing screen.
 *
 * Visual states:
 *   idle      — dashed border placeholder with icon + label
 *   ready     — shows the selected image preview + "Tap to replace" overlay
 *   uploading — dimmed preview + centered ActivityIndicator
 *   done      — image preview + subtle green "✓ Uploaded" badge
 *   error     — placeholder with red error text
 *
 * Props:
 *   localUri      — from useImageUpload().localUri
 *   status        — from useImageUpload().status
 *   error         — from useImageUpload().error  (shown in idle/error state)
 *   onPress       — should call useImageUpload().pickImage()
 *   label         — primary prompt label  e.g. "Upload cover image"
 *   hint          — secondary hint text   e.g. "JPG or PNG, 16:9"
 *   icon          — emoji icon            e.g. "🖼️"
 *   height        — tile height in px     (default: 180)
 *   hasError      — true when the form was submitted and this field is empty
 *                   (renders red border)
 */

import { Image } from 'expo-image';
import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { type UploadStatus } from '@/src/hooks/useImageUpload';
import { colors, fontSize, radius, spacing } from '@/src/theme';

// ─── Types ────────────────────────────────────────────────────────────────────

type Props = {
  localUri:  string | null;
  status:    UploadStatus;
  error:     string | null;
  onPress:   () => void;
  label:     string;
  hint:      string;
  icon:      string;
  height?:   number;
  /** Highlights the tile border red when true (form validation). */
  hasError?: boolean;
  /** If false the tile is fully disabled (e.g. during form submission). */
  disabled?: boolean;
};

// ─── Component ────────────────────────────────────────────────────────────────

export function ImageUploadTile({
  localUri,
  status,
  error,
  onPress,
  label,
  hint,
  icon,
  height = 180,
  hasError = false,
  disabled = false,
}: Props) {
  const hasImage  = !!localUri;
  const uploading = status === 'uploading';
  const done      = status === 'done';
  const isError   = status === 'error';

  // Border color priority: validation error > upload error > active > default
  const borderColor = hasError || isError
    ? colors.error
    : done
    ? colors.success
    : hasImage
    ? colors.borderActive
    : colors.borderInput;

  return (
    <Pressable
      onPress={disabled || uploading ? undefined : onPress}
      style={[
        s.tile,
        { height, borderColor },
        (disabled || uploading) && s.tileDisabled,
      ]}
      android_ripple={{ color: colors.primarySoft }}
    >
      {hasImage ? (
        // ── Image preview ──────────────────────────────────────────────────
        <>
          <Image
            source={{ uri: localUri! }}
            style={s.preview}
            contentFit="cover"
            transition={200}
          />

          {/* Uploading spinner overlay */}
          {uploading && (
            <View style={s.overlay}>
              <ActivityIndicator color={colors.text} size="large" />
              <Text style={s.overlayText}>Uploading…</Text>
            </View>
          )}

          {/* Replace label (visible when not uploading) */}
          {!uploading && (
            <View style={s.replaceBar}>
              {done && (
                <Text style={s.doneTag}>✓ Uploaded</Text>
              )}
              <Text style={s.replaceText}>Tap to replace</Text>
            </View>
          )}
        </>
      ) : (
        // ── Empty placeholder ──────────────────────────────────────────────
        <View style={s.placeholder}>
          <Text style={s.icon}>{icon}</Text>
          <Text style={s.label}>{label}</Text>
          <Text style={[s.hint, (hasError || isError) && { color: colors.error }]}>
            {isError && error ? error : hint}
          </Text>
        </View>
      )}
    </Pressable>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  tile: {
    borderRadius: radius.lg,
    borderWidth: 1,
    borderStyle: 'dashed',
    overflow: 'hidden',
    marginBottom: spacing.sm,
    backgroundColor: colors.bgCard,
  },
  tileDisabled: {
    opacity: 0.6,
  },

  // ── Image preview ────────────────────────────────────────────────────────
  preview: {
    width: '100%',
    height: '100%',
  },

  // Uploading overlay
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.60)',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
  },
  overlayText: {
    color: colors.text,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },

  // Bottom bar shown when image selected and not uploading
  replaceBar: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: 'rgba(0,0,0,0.55)',
    paddingHorizontal: spacing.md,
    paddingVertical: 6,
  },
  replaceText: {
    color: colors.text,
    fontSize: fontSize.xs,
    fontWeight: '600',
  },
  doneTag: {
    color: colors.success,
    fontSize: fontSize.xs,
    fontWeight: '700',
  },

  // ── Empty placeholder ────────────────────────────────────────────────────
  placeholder: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
    paddingHorizontal: spacing.lg,
  },
  icon: {
    fontSize: 30,
    marginBottom: spacing.xs,
  },
  label: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '600',
    textAlign: 'center',
  },
  hint: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    textAlign: 'center',
  },
});
