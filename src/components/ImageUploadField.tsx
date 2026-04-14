/**
 * src/components/ImageUploadField.tsx
 *
 * A self-contained image upload field that wraps useImageUpload + ImageUploadTile.
 * Used for proof-of-ownership and transfer-evidence uploads where the caller
 * only needs the final storage path.
 *
 * Usage:
 *   <ImageUploadField
 *     userId={user.id}
 *     folder="transfer-evidence"
 *     label="Upload transfer proof"
 *     hint="Screenshot of transfer confirmation"
 *     icon="\u{1F4F8}"
 *     onPathReady={(path) => setEvidencePath(path)}
 *   />
 *
 * Phase A — migration 011
 */

import { useEffect } from 'react';

import { useImageUpload } from '@/src/hooks/useImageUpload';
import { ImageUploadTile } from '@/src/components/ImageUploadTile';

// ─── Props ───────────────────────────────────────────────────────────────────

export interface ImageUploadFieldProps {
  /** Supabase user ID — top-level storage folder. */
  userId: string;
  /** Sub-folder for the file, e.g. "transfer-evidence". */
  folder: string;
  /** Label shown in the empty state. */
  label: string;
  /** Hint text under the label. */
  hint: string;
  /** Emoji icon shown in the empty state. */
  icon: string;
  /** Tile height in px. Default 140. */
  height?: number;
  /** Called when the image has been picked (localUri is available). */
  onPicked?: (localUri: string) => void;
  /** Called when upload completes with the storage path. */
  onPathReady?: (storagePath: string) => void;
  /** Whether the field should show a validation error border. */
  hasError?: boolean;
  /** Disable interactions (e.g. during form submission). */
  disabled?: boolean;
}

// ─── Component ───────────────────────────────────────────────────────────────

export default function ImageUploadField({
  userId,
  folder,
  label,
  hint,
  icon,
  height = 140,
  onPicked,
  onPathReady,
  hasError = false,
  disabled = false,
}: ImageUploadFieldProps) {
  const upload = useImageUpload({
    userId,
    folder,
    aspect: null,
    quality: 0.85,
  });

  // Notify parent when an image is selected
  useEffect(() => {
    if (upload.localUri && onPicked) {
      onPicked(upload.localUri);
    }
  }, [upload.localUri]); // eslint-disable-line react-hooks/exhaustive-deps

  // Notify parent when upload completes
  useEffect(() => {
    if (upload.storagePath && onPathReady) {
      onPathReady(upload.storagePath);
    }
  }, [upload.storagePath]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <ImageUploadTile
      localUri={upload.localUri}
      status={upload.status}
      error={upload.error}
      onPress={upload.pickImage}
      label={label}
      hint={hint}
      icon={icon}
      height={height}
      hasError={hasError}
      disabled={disabled || upload.busy}
    />
  );
}

// Re-export the hook so the send screen can call uploadImage() imperatively
export { useImageUpload } from '@/src/hooks/useImageUpload';
