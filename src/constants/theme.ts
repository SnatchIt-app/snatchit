/**
 * src/constants/theme.ts
 *
 * Re-exports all design tokens from src/theme/index.ts under the
 * canonical COLORS / SPACING / RADIUS / FONT_SIZE / SHADOW names.
 *
 * Usage:
 *   import { COLORS, SPACING } from '@/src/constants/theme';
 *
 * Both import paths are valid; this file exists so new screens can
 * follow the SCREAMING_SNAKE_CASE naming convention while legacy
 * screens that already use `colors` / `spacing` keep working.
 */

export {
  colors  as COLORS,
  spacing as SPACING,
  radius  as RADIUS,
  fontSize as FONT_SIZE,
  shadow  as SHADOW,
} from '@/src/theme';

// Named re-exports for convenience
export * from '@/src/theme';
