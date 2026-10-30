import { APP_CONFIG } from '@/src/config/app';

export type ImageValidationResult = {
  valid: boolean;
  error?: string;
};

export function validateImage(
  file: { uri: string; type?: string; fileSize?: number },
  bucket: 'auction-media' | 'avatars' | 'proof-docs',
): ImageValidationResult {
  const maxMB = bucket === 'avatars'
    ? APP_CONFIG.MAX_AVATAR_SIZE_MB
    : APP_CONFIG.MAX_IMAGE_SIZE_MB;
  const maxBytes = maxMB * 1024 * 1024;

  // Check file size if available
  if (file.fileSize && file.fileSize > maxBytes) {
    return {
      valid: false,
      error: `Image must be under ${maxMB}MB. Yours is ${(file.fileSize / (1024 * 1024)).toFixed(1)}MB.`,
    };
  }

  // Check MIME type if available
  // proof-docs (033/034/073) also allows image/heif; its limit is the same 10 MB (F-IMG-1h).
  const allowed: readonly string[] = bucket === 'proof-docs'
    ? [...APP_CONFIG.ALLOWED_IMAGE_TYPES, 'image/heif']
    : APP_CONFIG.ALLOWED_IMAGE_TYPES;
  if (file.type && !allowed.includes(file.type)) {
    return {
      valid: false,
      error: `Unsupported image type. Please use JPEG, PNG, WebP, or HEIC.`,
    };
  }

  return { valid: true };
}
