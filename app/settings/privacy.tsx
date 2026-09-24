/**
 * app/settings/privacy.tsx — Privacy Policy
 * Effective Date: March 20, 2026
 */

import { useMemo } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

type Styles = ReturnType<typeof makeStyles>;

// ─── Shared components ───────────────────────────────────────────────────────

function Section({ title, children, s }: { title: string; children: React.ReactNode; s: Styles }) {
  return (
    <View style={s.section}>
      <Text style={s.sectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

function Body({ children, s }: { children: string; s: Styles }) {
  return <Text style={s.body}>{children}</Text>;
}

function Bullet({ children, s }: { children: string; s: Styles }) {
  return (
    <View style={s.bulletRow}>
      <Text style={s.bulletDot}>{'\u00B7'}</Text>
      <Text style={s.bulletText}>{children}</Text>
    </View>
  );
}

// ─── Screen ──────────────────────────────────────────────────────────────────

export default function PrivacyPolicyScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  return (
    <View style={s.safe}>
      <SettingsHeader title="Privacy policy" />

      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.content}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Text style={s.pageTitle}>Privacy Policy</Text>
        <Text style={s.effectiveDate}>Effective Date: March 20, 2026</Text>
        <Text style={s.body}>
          JDT LLC (&quot;we&quot;, &quot;us&quot;, &quot;Snatch It&quot;) operates the Snatch It mobile application. This Privacy Policy explains what information we collect, how we use it, and your choices regarding your data.
        </Text>

        {/* 1. Information We Collect */}
        <Section s={s} title="1. Information We Collect">
          <Body s={s}>We collect information you provide directly and information generated through your use of the app.</Body>

          <Text style={s.subhead}>Account Information</Text>
          <Bullet s={s}>Email address (required for account creation and login)</Bullet>
          <Bullet s={s}>Display name (shown to other users)</Bullet>
          <Bullet s={s}>Phone number (optional for buyers; verified via a one-time SMS code before selling. Used only for account verification and ticket transfer coordination — never shown on your public profile and never used for marketing)</Bullet>
          <Bullet s={s}>Bio (optional, shown on your profile)</Bullet>
          <Bullet s={s}>Profile photo (optional, stored securely)</Bullet>

          <Text style={s.subhead}>Transaction Data</Text>
          <Bullet s={s}>Listing details you create (event info, pricing, ticket details)</Bullet>
          <Bullet s={s}>Bid and purchase history</Bullet>
          <Bullet s={s}>Payment metadata (transaction IDs, amounts, fees, status). We do not store credit card numbers or bank account details.</Bullet>

          <Text style={s.subhead}>Device & Technical Data</Text>
          <Bullet s={s}>Push notification tokens (to deliver notifications to your device)</Bullet>
          <Bullet s={s}>Device platform (iOS or Android)</Bullet>
          <Bullet s={s}>Crash reports and error logs (via Sentry, described below)</Bullet>
        </Section>

        {/* 2. How We Use Your Information */}
        <Section s={s} title="2. How We Use Your Information">
          <Body s={s}>We use collected information to:</Body>
          <Bullet s={s}>Create, maintain, and secure your account</Bullet>
          <Bullet s={s}>Process transactions and facilitate ticket transfers between buyers and sellers</Bullet>
          <Bullet s={s}>Send push notifications about bids, purchases, and transfer updates</Bullet>
          <Bullet s={s}>Provide customer support and respond to inquiries</Bullet>
          <Bullet s={s}>Detect and prevent fraud, abuse, and policy violations</Bullet>
          <Bullet s={s}>Monitor app stability and fix crashes (via Sentry)</Bullet>
          <Bullet s={s}>Improve the platform and develop new features</Bullet>
          <Body s={s}>We do not sell your personal information to third parties. We do not use your data for advertising or ad targeting.</Body>
        </Section>

        {/* 3. Third-Party Services */}
        <Section s={s} title="3. Third-Party Services">
          <Body s={s}>We use the following third-party services to operate the platform. Each processes data under its own privacy policy:</Body>

          <Text style={s.subhead}>Stripe</Text>
          <Body s={s}>Stripe processes all payments and seller payouts. When you make a purchase or set up payouts, Stripe receives your payment details directly. We never see or store your full card number. Stripe&apos;s privacy policy: stripe.com/privacy</Body>

          <Text style={s.subhead}>Supabase</Text>
          <Body s={s}>Supabase provides our database, authentication, and file storage infrastructure. Your account data, listings, and uploaded images are stored on Supabase&apos;s cloud platform. Supabase&apos;s privacy policy: supabase.com/privacy</Body>

          <Text style={s.subhead}>Sentry</Text>
          <Body s={s}>Sentry receives crash reports and error logs from the native app (iOS and Android only, not web). Crash reports may include your user ID and email address to help us identify and fix issues affecting your account. Sentry does not receive payment data. Sentry&apos;s privacy policy: sentry.io/privacy</Body>

          <Text style={s.subhead}>Expo</Text>
          <Body s={s}>Expo provides push notification delivery. We store your device&apos;s push token to send notifications. Expo&apos;s privacy policy: expo.dev/privacy</Body>
        </Section>

        {/* 4. Data Retention */}
        <Section s={s} title="4. Data Retention">
          <Body s={s}>We retain your account information and transaction history for as long as your account is active. Transaction records may be retained after account deletion as required for legal, tax, or dispute resolution purposes.</Body>
          <Body s={s}>When you sign out, the app asks our servers to deactivate this device&apos;s push notification token for that account. If that request cannot complete (for example, while offline), the token may stay active until it is next updated. Crash report data in Sentry is retained according to Sentry&apos;s data retention settings (typically 90 days).</Body>
        </Section>

        {/* 5. Your Rights & Choices */}
        <Section s={s} title="5. Your Rights & Choices">
          <Body s={s}>You have the following rights regarding your data:</Body>
          <Bullet s={s}>Access and update your profile information at any time via Edit Profile in Settings</Bullet>
          <Bullet s={s}>Request deletion of your account and associated data by contacting us at the email below</Bullet>
          <Bullet s={s}>Opt out of push notifications through your device&apos;s system settings</Bullet>
          <Bullet s={s}>Request a copy of the personal data we hold about you</Bullet>
          <Body s={s}>To exercise any of these rights, contact us at:</Body>
          <Text style={s.contactEmail}>support@snatchitapp.com</Text>
          <Body s={s}>We will respond to data requests within 30 days. Certain data may be retained where required by law.</Body>
        </Section>

        {/* 6. Data Security */}
        <Section s={s} title="6. Data Security">
          <Body s={s}>We use industry-standard security measures to protect your data, including encrypted connections (TLS/SSL), secure authentication tokens, and access controls. Payment processing is handled entirely by Stripe, which is PCI DSS Level 1 certified. However, no method of electronic transmission or storage is 100% secure.</Body>
        </Section>

        {/* 6b. Reports & Moderation */}
        <Section s={s} title="6b. Reports & Moderation">
          <Body s={s}>
            Snatch It is a peer-to-peer marketplace, and we expect all users to
            behave respectfully and within the rules.
          </Body>
          <Bullet s={s}>You can report a listing or another user at any time from the listing&apos;s overflow menu.</Bullet>
          <Bullet s={s}>You can block another user from your account; their listings will be hidden from your feed. Manage blocks at Settings → Blocked Users.</Bullet>
          <Bullet s={s}>Reports are reviewed by the Snatch It team within 24 hours.</Bullet>
          <Bullet s={s}>Listings or accounts that violate our rules may be removed, suspended, or permanently banned.</Bullet>
          <Bullet s={s}>Submitting false or repeated bad-faith reports may itself be grounds for suspension.</Bullet>
          <Body s={s}>
            For urgent safety concerns, contact us at the email below; we treat
            these reports with priority.
          </Body>
          <Text style={s.contactEmail}>support@snatchitapp.com</Text>
        </Section>

        {/* 7. Children's Privacy */}
        <Section s={s} title="7. Children's Privacy">
          <Body s={s}>Snatch It is not intended for users under 18 years of age. We do not knowingly collect personal information from children. If you believe a child has provided us with personal data, contact us and we will delete it promptly.</Body>
        </Section>

        {/* 8. Changes to This Policy */}
        <Section s={s} title="8. Changes to This Policy">
          <Body s={s}>We may update this Privacy Policy from time to time. We will notify you of material changes by posting the updated policy in the app. Your continued use of Snatch It after changes take effect constitutes acceptance of the revised policy.</Body>
        </Section>

        {/* 9. Contact */}
        <Section s={s} title="9. Contact">
          <Body s={s}>For privacy-related questions, data requests, or concerns:</Body>
          <Text style={s.contactEmail}>support@snatchitapp.com</Text>
          <Text style={s.footerNote}>
            JDT LLC {'\u00B7'} Snatch It{'\n'}
            Effective March 20, 2026
          </Text>
        </Section>

        <View style={s.bottomPad} />
      </ScrollView>
    </View>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

function makeStyles(p: Palette) {
  return StyleSheet.create({
  safe:         { flex: 1, backgroundColor: p.surface.canvas },

  scroll:       { flex: 1 },
  content:      { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg },

  pageTitle:    { fontFamily: v2.font.display, fontSize: 26, lineHeight: 33, letterSpacing: -0.5,
                  textTransform: 'uppercase', color: p.text.primary, marginBottom: v2.space.xs },
  effectiveDate:{ fontFamily: v2.font.body, fontSize: 13, lineHeight: 18, color: p.text.faint,
                  marginBottom: v2.space.md },

  section:      { marginBottom: v2.space.lg },
  sectionTitle: { fontFamily: v2.font.bodyMedium, fontSize: 10, lineHeight: 14, letterSpacing: 3,
                  textTransform: 'uppercase', color: p.text.muted, marginBottom: v2.space.sm },
  subhead:      { fontFamily: v2.font.bodySemi, fontSize: 15, lineHeight: 22, color: p.text.primary,
                  marginTop: v2.space.sm, marginBottom: v2.space.xs },
  body:         { fontFamily: v2.font.body, fontSize: 15, lineHeight: 22, color: p.text.secondary,
                  marginBottom: v2.space.sm },

  bulletRow:    { flexDirection: 'row', marginBottom: v2.space.xs, paddingLeft: v2.space.xs },
  bulletDot:    { color: p.brand.redText, fontSize: 15, marginRight: v2.space.sm, lineHeight: 22 },
  bulletText:   { flex: 1, fontFamily: v2.font.body, fontSize: 15, lineHeight: 22, color: p.text.secondary },

  contactEmail: { fontFamily: v2.font.bodySemi, fontSize: 15, lineHeight: 22, color: p.text.primary,
                  marginBottom: v2.space.sm },
  footerNote:   { fontFamily: v2.font.body, fontSize: 13, lineHeight: 18, color: p.text.faint,
                  marginTop: v2.space.lg, textAlign: 'center' },

  bottomPad:    { height: v2.space.xxxl },
  });
}
