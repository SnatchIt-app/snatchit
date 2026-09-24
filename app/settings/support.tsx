/**
 * app/settings/support.tsx — Help & support (V2).
 *
 * PRESENTATION rebuilt on the V2 system; content and behaviour are unchanged: the
 * same FAQ entries (verbatim), the same `support@snatchitapp.com` mailto, and the
 * same expand/collapse. No support chat or SLA invented.
 */

import { Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useMemo, useState } from 'react';

import { Button } from '@/src/components/ui';
import { AccountSection } from '@/src/components/account/AccountSection';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

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
    a: 'Use the "Forgot password?" link on the login screen to reset your password via email. If you no longer have access to your registered email address, contact us and we will verify your identity manually.',
  },
];

const SUPPORT_EMAIL = 'support@snatchitapp.com';

function openEmail() {
  Linking.openURL(`mailto:${SUPPORT_EMAIL}?subject=Snatch It Support Request`).catch(() => {});
}

function FaqItem({ q, a, s }: { q: string; a: string; s: ReturnType<typeof makeStyles> }) {
  const [open, setOpen] = useState(false);
  return (
    <View style={s.faqItem}>
      <Pressable style={s.faqHeader} onPress={() => setOpen((v) => !v)} hitSlop={4} accessibilityRole="button" accessibilityState={{ expanded: open }}>
        <Text style={[textStyle('title'), s.faqQ]}>{q}</Text>
        <Text style={s.faqChevron}>{open ? '–' : '+'}</Text>
      </Pressable>
      {open ? <Text style={[textStyle('bodySm'), s.faqA]}>{a}</Text> : null}
    </View>
  );
}

export default function SupportScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  return (
    <View style={s.root}>
      <SettingsHeader title="Support" />
      <ScrollView contentContainerStyle={s.content} showsVerticalScrollIndicator={false}>
        <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">Help &amp; support</Text>
        <Text style={[textStyle('body'), s.description]}>
          Need help with a transaction, your account, or anything else? Our team is here to help.
        </Text>

        <AccountSection title="Contact us">
          <Text style={[textStyle('bodySm'), s.body]}>
            Email us and include your account email, the listing ID if relevant, and a description of the issue. We aim to respond within 1 to 2 business days.
          </Text>
          <Button label={SUPPORT_EMAIL} variant="secondary" onPress={openEmail} style={s.emailBtn} />
        </AccountSection>

        <AccountSection title="Common questions">
          {FAQ.map((item) => (
            <FaqItem key={item.q} q={item.q} a={item.a} s={s} />
          ))}
        </AccountSection>

        <View style={s.pad} />
      </ScrollView>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },
  content: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg },
  title: { color: p.text.primary, marginBottom: v2.space.xs },
  description: { color: p.text.secondary, marginBottom: v2.space.sm },
  body: { color: p.text.muted, paddingVertical: v2.space.sm },
  emailBtn: { alignSelf: 'flex-start', marginTop: v2.space.sm },

  faqItem: { borderBottomWidth: 1, borderBottomColor: p.border.default, paddingVertical: v2.space.md },
  faqHeader: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: v2.space.sm },
  faqQ: { flex: 1, color: p.text.primary },
  faqChevron: { color: p.brand.red, fontSize: 20, lineHeight: 22 },
  faqA: { color: p.text.muted, marginTop: v2.space.sm },

  pad: { height: v2.space.xxxl },
  });
}
