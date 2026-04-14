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

import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import {
  PLATFORM_INSTRUCTIONS,
  interpolateStep,
} from '@/src/lib/platformInstructions';
import { colors, fontSize, radius, spacing } from '@/src/theme';
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
  const [tipsExpanded, setTipsExpanded] = useState(false);

  const instruction = PLATFORM_INSTRUCTIONS[platform];
  if (!instruction) return null;

  const info = instruction[role];
  const { warnings } = instruction;

  return (
    <View style={s.container}>
      {/* Header */}
      <View style={s.header}>
        <Text style={s.icon}>{instruction.icon}</Text>
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

const s = StyleSheet.create({
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
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '700',
  },
  time: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    marginTop: 2,
  },

  // Steps
  stepsCard: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
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
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: spacing.sm,
    marginTop: 1,
  },
  stepNumberText: {
    color: colors.primary,
    fontSize: fontSize.xs,
    fontWeight: '700',
  },
  stepText: {
    flex: 1,
    color: colors.text,
    fontSize: fontSize.sm,
    lineHeight: 20,
  },

  // Warnings
  warningBox: {
    backgroundColor: 'rgba(251,191,36,0.10)',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.warning,
    padding: spacing.sm,
    marginTop: spacing.sm,
  },
  warningText: {
    color: colors.warning,
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
    color: colors.textMuted,
    fontSize: fontSize.sm,
    fontWeight: '600',
  },
  tipsList: {
    marginTop: spacing.xs,
    paddingLeft: spacing.sm,
  },
  tipText: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    lineHeight: 18,
    marginBottom: 4,
  },
});
