/**
 * app/settings/payment-methods.tsx — Payment Methods Settings Screen
 *
 * Shows available payment methods (Apple Pay / Google Pay + card).
 * Stripe's PaymentSheet handles card storage automatically via their
 * "Link" feature — we don't build our own saved cards UI.
 */

import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useStripe } from '@stripe/stripe-react-native';

import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';

// ─── Sub-components ───────────────────────────────────────────────────────────

/** Uppercase section label, app-wide pattern */
function SectionLabel({ text }: { text: string }) {
  return <Text style={s.sectionLabel}>{text}</Text>;
}

/** A single payment method info row */
function MethodRow({
  icon,
  title,
  subtitle,
  statusColor,
}: {
  icon: string;
  title: string;
  subtitle: string;
  statusColor?: string;
}) {
  return (
    <View style={mr.row}>
      <View style={mr.iconWrap}>
        <Text style={mr.icon}>{icon}</Text>
      </View>
      <View style={mr.textBlock}>
        <Text style={mr.title}>{title}</Text>
        <Text style={[mr.subtitle, statusColor ? { color: statusColor } : undefined]}>
          {subtitle}
        </Text>
      </View>
    </View>
  );
}

const mr = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  iconWrap: {
    width: 44,
    height: 44,
    borderRadius: radius.md,
    backgroundColor: colors.bgInput,
    borderWidth: 1,
    borderColor: colors.borderInput,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: { fontSize: 22 },
  textBlock: { flex: 1 },
  title: {
    fontSize: fontSize.md,
    fontWeight: '700',
    color: colors.text,
    marginBottom: 2,
  },
  subtitle: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
  },
});

// ─── Screen ───────────────────────────────────────────────────────────────────

export default function PaymentMethodsScreen() {
  const { isPlatformPaySupported } = useStripe();
  const [platformPayReady, setPlatformPayReady] = useState(false);

  // Check Apple Pay / Google Pay availability on mount
  useEffect(() => {
    async function checkPlatformPay() {
      try {
        const supported = await isPlatformPaySupported();
        setPlatformPayReady(supported);
      } catch {
        setPlatformPayReady(false);
      }
    }
    checkPlatformPay();
  }, [isPlatformPaySupported]);

  const isIOS = Platform.OS === 'ios';
  const isAndroid = Platform.OS === 'android';

  return (
    <SafeAreaView style={s.safe}>

      {/* ── Top bar ───────────────────────────────────────────────────────── */}
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>←</Text>
        </Pressable>
        <Text style={s.topTitle}>Payment Methods</Text>
        <View style={s.backBtn} />
      </View>

      <ScrollView
        contentContainerStyle={s.scrollBody}
        showsVerticalScrollIndicator={false}
      >

        {/* ── DIGITAL WALLETS ─────────────────────────────────────────────── */}
        <SectionLabel text="Digital Wallets" />
        <View style={s.card}>
          {isIOS ? (
            <MethodRow
              icon=""
              title="Apple Pay"
              subtitle={platformPayReady ? 'Ready to use' : 'Not available on this device'}
              statusColor={platformPayReady ? colors.success : colors.textDim}
            />
          ) : (
            <MethodRow
              icon=""
              title="Apple Pay"
              subtitle="iOS only"
              statusColor={colors.textDim}
            />
          )}

          <View style={s.lastRow}>
            {isAndroid ? (
              <MethodRow
                icon="G"
                title="Google Pay"
                subtitle={platformPayReady ? 'Ready to use' : 'Not available on this device'}
                statusColor={platformPayReady ? colors.success : colors.textDim}
              />
            ) : (
              <MethodRow
                icon="G"
                title="Google Pay"
                subtitle="Android only"
                statusColor={colors.textDim}
              />
            )}
          </View>
        </View>

        <Text style={s.walletNote}>
          {isIOS
            ? 'Apple Pay is automatically available at checkout when supported.'
            : isAndroid
              ? 'Google Pay is automatically available at checkout.'
              : 'Digital wallets are available on mobile devices.'}
        </Text>

        {/* ── CARD PAYMENT ────────────────────────────────────────────────── */}
        <SectionLabel text="Card Payment" />
        <View style={s.card}>
          <View style={s.lastRow}>
            <MethodRow
              icon="💳"
              title="Credit or Debit Card"
              subtitle="Enter card details at checkout"
            />
          </View>
        </View>

        <View style={s.cardNote}>
          <Text style={s.cardNoteText}>
            Card details are securely handled by Stripe. We never see or store your full card number.
          </Text>
        </View>

        {/* ── SAVED METHODS NOTE ──────────────────────────────────────────── */}
        <View style={s.savedNote}>
          <Text style={s.savedNoteIcon}>✨</Text>
          <Text style={s.savedNoteText}>
            Your saved payment methods will appear automatically at checkout via Stripe Link.
          </Text>
        </View>

        {/* ── SECURITY INFO ───────────────────────────────────────────────── */}
        <View style={s.securityCard}>
          <Text style={s.securityTitle}>🔒  Payment Security</Text>
          <Text style={s.securityText}>
            All payments are processed by Stripe, a PCI Level 1 certified payment processor.
            Your card details are encrypted and never stored on our servers.
          </Text>
        </View>

        <View style={{ height: spacing.xl }} />
      </ScrollView>
    </SafeAreaView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.bg },

  // ── Top bar ────────────────────────────────────────────────────────────────
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  backBtn: { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle: { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  // ── Scroll body ───────────────────────────────────────────────────────────
  scrollBody: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
  },

  // ── Section label ─────────────────────────────────────────────────────────
  sectionLabel: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textDim,
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
    marginTop: spacing.md,
  },

  // ── Card container ────────────────────────────────────────────────────────
  card: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: spacing.md,
    marginBottom: spacing.sm,
    ...shadow.card,
  },
  lastRow: {
    borderBottomWidth: 0,
  },

  // ── Wallet note ───────────────────────────────────────────────────────────
  walletNote: {
    fontSize: fontSize.xs,
    color: colors.textDim,
    textAlign: 'center',
    marginBottom: spacing.md,
    lineHeight: 16,
  },

  // ── Card payment note ─────────────────────────────────────────────────────
  cardNote: {
    paddingHorizontal: spacing.sm,
    marginBottom: spacing.lg,
  },
  cardNoteText: {
    fontSize: fontSize.xs,
    color: colors.textDim,
    lineHeight: 16,
    textAlign: 'center',
  },

  // ── Saved methods note ────────────────────────────────────────────────────
  savedNote: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.sm,
    backgroundColor: colors.primarySoft,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.primary,
    padding: spacing.md,
    marginBottom: spacing.lg,
  },
  savedNoteIcon: { fontSize: 16, marginTop: 1 },
  savedNoteText: {
    flex: 1,
    fontSize: fontSize.xs,
    color: colors.text,
    lineHeight: 18,
  },

  // ── Security card ─────────────────────────────────────────────────────────
  securityCard: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
    gap: spacing.sm,
    ...shadow.card,
  },
  securityTitle: {
    fontSize: fontSize.sm,
    fontWeight: '700',
    color: colors.text,
  },
  securityText: {
    fontSize: fontSize.xs,
    color: colors.textDim,
    lineHeight: 18,
  },
});
