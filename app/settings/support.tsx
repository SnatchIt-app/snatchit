/**
 * app/settings/support.tsx — Help & Support
 */

import { router } from 'expo-router';
import { useState } from 'react';
import {
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { colors, fontSize, radius, spacing } from '@/src/theme';

// ─── FAQ data ─────────────────────────────────────────────────────────────────

const FAQ = [
  {
    q: "I didn't receive my ticket after payment.",
    a: "First, confirm receipt is still pending in your order details. If the seller has not marked the transfer as sent within the expected window, contact us with your listing ID and we will follow up on your behalf.",
  },
  {
    q: 'I have a payment issue or was charged incorrectly.',
    a: "Payments are processed by Stripe. If you were charged an unexpected amount or see a duplicate charge, email us with your account email and the listing ID. Do not initiate a chargeback before contacting us — we can often resolve issues faster directly.",
  },
  {
    q: "I can't access my account.",
    a: 'Use the "Forgot Password?" link on the login screen to reset your password via email. If you no longer have access to your registered email address, contact us and we will verify your identity manually.',
  },
];

// ─── FAQ item ─────────────────────────────────────────────────────────────────

function FaqItem({ q, a }: { q: string; a: string }) {
  const [open, setOpen] = useState(false);
  return (
    <View style={s.faqItem}>
      <Pressable
        style={s.faqHeader}
        onPress={() => setOpen(v => !v)}
        hitSlop={4}
      >
        <Text style={s.faqQ}>{q}</Text>
        <Text style={s.faqChevron}>{open ? '▲' : '▼'}</Text>
      </Pressable>
      {open && <Text style={s.faqA}>{a}</Text>}
    </View>
  );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

const SUPPORT_EMAIL = 'support@snatchitapp.com';

function openEmail() {
  Linking.openURL(
    `mailto:${SUPPORT_EMAIL}?subject=Snatch It Support Request`,
  ).catch(() => {});
}

export default function SupportScreen() {
  return (
    <SafeAreaView style={s.safe}>
      {/* Top bar */}
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>←</Text>
        </Pressable>
        <Text style={s.topTitle}>Support</Text>
        <View style={s.backBtn} />
      </View>

      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.content}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Text style={s.pageTitle}>Help & Support</Text>
        <Text style={s.description}>
          Need help with a transaction, your account, or anything else? Our team
          is here to help.
        </Text>

        {/* Contact */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>Contact Us</Text>
          <Text style={s.body}>
            Email us and include your account email, the listing ID if relevant,
            and a description of the issue. We aim to respond within 1–2 business
            days.
          </Text>
          <Pressable style={s.emailBtn} onPress={openEmail}>
            <Text style={s.emailBtnText}>{SUPPORT_EMAIL}</Text>
          </Pressable>
        </View>

        {/* FAQ */}
        <View style={s.section}>
          <Text style={s.sectionTitle}>Common Questions</Text>
          {FAQ.map((item) => (
            <FaqItem key={item.q} q={item.q} a={item.a} />
          ))}
        </View>

        <View style={s.bottomPad} />
      </ScrollView>
    </SafeAreaView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe:        { flex: 1, backgroundColor: colors.bg },

  // Top bar
  topBar:      { flexDirection: 'row', alignItems: 'center',
                 justifyContent: 'space-between',
                 paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
                 borderBottomWidth: 1, borderBottomColor: colors.border },
  backBtn:     { width: 44, height: 44, alignItems: 'flex-start',
                 justifyContent: 'center' },
  backArrow:   { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:    { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  // Scroll
  scroll:      { flex: 1 },
  content:     { paddingHorizontal: spacing.md, paddingTop: spacing.lg },

  // Page header
  pageTitle:   { color: colors.text, fontSize: fontSize.lg, fontWeight: '800',
                 marginBottom: spacing.xs },
  description: { color: colors.textMuted, fontSize: fontSize.sm, lineHeight: 20,
                 marginBottom: spacing.lg },

  // Section
  section:     { marginBottom: spacing.lg },
  sectionTitle:{ color: colors.primary, fontSize: fontSize.sm, fontWeight: '700',
                 textTransform: 'uppercase', letterSpacing: 0.8,
                 marginBottom: spacing.sm },
  body:        { color: colors.textMuted, fontSize: fontSize.sm, lineHeight: 20,
                 marginBottom: spacing.sm },

  // Email button
  emailBtn:    { alignSelf: 'flex-start', marginTop: spacing.xs,
                 paddingVertical: spacing.sm, paddingHorizontal: spacing.md,
                 backgroundColor: colors.primarySoft,
                 borderRadius: radius.md,
                 borderWidth: 1, borderColor: colors.primary },
  emailBtnText:{ color: colors.primary, fontSize: fontSize.sm, fontWeight: '700' },

  // FAQ
  faqItem:    { borderBottomWidth: 1, borderBottomColor: colors.border,
                paddingVertical: spacing.sm },
  faqHeader:  { flexDirection: 'row', alignItems: 'flex-start',
                justifyContent: 'space-between', gap: spacing.sm },
  faqQ:       { flex: 1, color: colors.text, fontSize: fontSize.sm,
                fontWeight: '600', lineHeight: 20 },
  faqChevron: { color: colors.primary, fontSize: fontSize.xs, marginTop: 2 },
  faqA:       { color: colors.textMuted, fontSize: fontSize.sm, lineHeight: 20,
                marginTop: spacing.sm },

  bottomPad:  { height: spacing.xxl },
});
