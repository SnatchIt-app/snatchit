/**
 * src/components/PlatformInstructions.tsx
 *
 * Renders platform-specific step-by-step transfer instructions for
 * either the seller (sending) or buyer (receiving) role.
 *
 * Usage:
 *   <PlatformInstructions
 *     platform="dice"
 *     role="seller"
 *     buyerEmail="buyer@example.com"
 *   />
 *
 * Phase A — migration 011
 */

import { useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import {
  PLATFORM_INSTRUCTIONS,
  interpolateStep,
} from '@/src/lib/platformInstructions';
import { fontSize, radius, spacing } from '@/src/theme';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import type { TicketPlatform } from '@/src/types';

// ─── Props ───────────────────────────────────────────────────────────────────

export interface PlatformInstructionsProps {
  platform: TicketPlatform;
  role: 'seller' | 'buyer';
  buyerEmail?: string | null;
  buyerPhone?: string | null;
}

// ─── Component ───────────────────────────────────────────────────────────────

export default function PlatformInstructions({
  platform,
  role,
  buyerEmail,
  buyerPhone,
}: PlatformInstructionsProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const [tipsExpanded, setTipsExpanded] = useState(false);

  const instruction = PLATFORM_INSTRUCTIONS[platform];
  if (!instruction) return null;

  const info = instruction[role];
  const { warnings } = instruction;

  return (
    <View style={s.container}>
      {/* Header */}
      <View style={s.header}>
        <Text style={s.icon} importantForAccessibility="no" accessibilityElementsHidden>{instruction.icon}</Text>
        <View style={s.headerText}>
          <Text style={s.title}>{info.title}</Text>
          <Text style={s.time}>{info.estimatedTime}</Text>
        </View>
      </View>

      {/* Steps */}
      <View style={s.stepsCard}>
        {info.steps.map((step, i) => (
          <View key={i} style={s.stepRow}>
            <View style={s.stepNumber}>
              <Text style={s.stepNumberText}>{i + 1}</Text>
            </View>
            <Text style={s.stepText}>
              {interpolateStep(step, buyerEmail, buyerPhone)}
            </Text>
          </View>
        ))}
      </View>

      {/* Warnings */}
      {warnings.length > 0 && (
        <View style={s.warningBox}>
          {warnings.map((w, i) => (
            <Text key={i} style={s.warningText}>
              {'\u26A0\uFE0F'}  {w}
            </Text>
          ))}
        </View>
      )}

      {/* Tips (collapsible) */}
      {info.tips.length > 0 && (
        <View style={s.tipsSection}>
          <Pressable
            style={s.tipsToggle}
            onPress={() => setTipsExpanded((v) => !v)}
            hitSlop={8}
            accessibilityRole="button"
            accessibilityLabel="Tips"
            accessibilityState={{ expanded: tipsExpanded }}
          >
            <Text style={s.tipsToggleText}>
              {tipsExpanded ? '\u25BC' : '\u25B6'}  Tips
            </Text>
          </Pressable>
          {tipsExpanded && (
            <View style={s.tipsList}>
              {info.tips.map((tip, i) => (
                <Text key={i} style={s.tipText}>
                  {'\u2022'}  {tip}
                </Text>
              ))}
            </View>
          )}
        </View>
      )}
    </View>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

function makeStyles(p: Palette) {
  return StyleSheet.create({
  container: {
    marginBottom: spacing.md,
  },

  // Header
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.sm,
  },
  icon: {
    fontSize: fontSize.xl,
    marginRight: spacing.sm,
  },
  headerText: {
    flex: 1,
  },
  title: {
    color: p.text.primary,
    fontSize: fontSize.md,
    fontWeight: '700',
  },
  time: {
    color: p.text.muted,
    fontSize: fontSize.xs,
    marginTop: 2,
  },

  // Steps
  stepsCard: {
    backgroundColor: p.surface.surface,
    borderRadius: radius.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: p.border.default,
  },
  stepRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: spacing.sm,
  },
  stepNumber: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: p.brand.redSoft,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: spacing.sm,
    marginTop: 1,
  },
  stepNumberText: {
    color: p.brand.redText,
    fontSize: fontSize.xs,
    fontWeight: '700',
  },
  stepText: {
    flex: 1,
    color: p.text.primary,
    fontSize: fontSize.sm,
    lineHeight: 20,
  },

  // Warnings
  warningBox: {
    backgroundColor: 'rgba(251,191,36,0.10)',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: p.status.warning,
    padding: spacing.sm,
    marginTop: spacing.sm,
  },
  warningText: {
    color: p.status.warning,
    fontSize: fontSize.xs,
    lineHeight: 18,
    marginBottom: 4,
  },

  // Tips
  tipsSection: {
    marginTop: spacing.sm,
  },
  tipsToggle: {
    paddingVertical: spacing.xs,
  },
  tipsToggleText: {
    color: p.text.muted,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
  tipsList: {
    marginTop: spacing.xs,
    paddingLeft: spacing.sm,
  },
  tipText: {
    color: p.text.muted,
    fontSize: fontSize.xs,
    lineHeight: 18,
    marginBottom: 4,
  },
});
}
