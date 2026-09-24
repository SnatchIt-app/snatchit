/**
 * app/settings/legal.tsx — Terms & Privacy
 * Effective Date: March 20, 2026
 */

import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

type Styles = ReturnType<typeof makeStyles>;

// ─── Section component ────────────────────────────────────────────────────────

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
      <Text style={s.bulletDot}>·</Text>
      <Text style={s.bulletText}>{children}</Text>
    </View>
  );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

export default function LegalScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const [fullTermsOpen, setFullTermsOpen] = useState(false);

  return (
    <View style={s.safe}>
      <SettingsHeader title="Terms of service" />

      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.content}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Text style={s.pageTitle}>Terms of Service</Text>
        <Text style={s.effectiveDate}>Effective Date: March 20, 2026</Text>

        {/* 1. About */}
        <Section s={s} title="About Snatch It">
          <Body s={s}>
            Snatch It is a technology marketplace platform operated by JDT LLC that connects
            independent ticket sellers with buyers. Snatch It is not a party to any transaction
            between users and does not act as a broker, agent, escrow service, or ticket vendor.
            All transactions are conducted directly between users.
          </Body>
        </Section>

        {/* 2. Terms of Use */}
        <Section s={s} title="Terms of Use">
          <Body s={s}>By using the platform, you agree to the following:</Body>
          <Bullet s={s}>
            Sellers are solely responsible for the accuracy of their listings and the validity
            and authenticity of all tickets offered.
          </Bullet>
          <Bullet s={s}>
            Buyers are solely responsible for reviewing listing details before purchasing or
            bidding, and for confirming receipt of tickets.
          </Bullet>
          <Bullet s={s}>
            Transactions are conducted directly between buyers and sellers. Once payment is
            processed and confirmed, transactions are final.
          </Bullet>
          <Bullet s={s}>
            All payments are processed by third-party payment providers (currently Stripe).
            Snatch It does not store payment card details. Under our protected payment flow,
            payment funds are held by Stripe on Snatch It&apos;s behalf until the buyer confirms
            receipt of the ticket (or the auto-release window expires), at which point the
            seller&apos;s net payout is released.
          </Bullet>
          <Bullet s={s}>
            A 10% service fee is added to the buyer&apos;s total at checkout, and a 10%
            marketplace fee is deducted from the seller&apos;s payout. Snatch It reserves
            the right to modify fee structures with reasonable notice.
          </Bullet>
          <Bullet s={s}>
            Chargebacks and refunds: if a buyer disputes a charge through their
            bank, or if a refund is issued after a payout has been released to
            the seller, Stripe may debit the disputed or refunded amount from
            the seller&apos;s future payouts to recover the funds. By accepting
            payouts through Snatch It, sellers authorize Stripe to debit their
            connected account balance as needed. Sellers receive a tax form
            (Form 1099-K) from Stripe each year for payouts that exceed the
            applicable IRS reporting threshold; Stripe files this directly with
            the IRS on the seller&apos;s behalf.
          </Bullet>
          <Bullet s={s}>
            Use of the platform is at your own risk. Snatch It does not guarantee the
            validity, authenticity, or transferability of any ticket listed.
          </Bullet>
          <Bullet s={s}>
            You must be at least 18 years of age and have the legal capacity to enter
            binding contracts to use this platform.
          </Bullet>
        </Section>

        {/* 3. Privacy & Data */}
        <Section s={s} title="Privacy & Data">
          <Body s={s}>
            Your use of the platform is also governed by our Privacy Policy. By using Snatch It,
            you consent to the collection, use, and disclosure of your information as described
            therein. Your information may be used to:
          </Body>
          <Bullet s={s}>Operate and maintain the platform and your account.</Bullet>
          <Bullet s={s}>Process transactions and facilitate communication between users.</Bullet>
          <Bullet s={s}>Provide customer support and respond to inquiries.</Bullet>
          <Bullet s={s}>Improve the platform and develop new features.</Bullet>
          <Pressable
            style={s.privacyLink}
            onPress={() => router.push('/settings/privacy')}
            accessibilityRole="link"
            accessibilityLabel="View full privacy policy"
          >
            <Text style={s.privacyLinkText}>View Full Privacy Policy {'\u2192'}</Text>
          </Pressable>
        </Section>

        {/* 4. Contact */}
        <Section s={s} title="Contact">
          <Body s={s}>
            For legal inquiries, dispute resolution, or questions about these terms, contact us at:
          </Body>
          <Text style={s.contactEmail}>support@snatchitapp.com</Text>
          <Body s={s}>
            Before initiating any formal dispute, you agree to first contact us at this address
            and attempt to resolve the matter informally for at least 30 days.
          </Body>
        </Section>

        {/* 5. Full Terms (expandable) */}
        <View style={s.section}>
          <Pressable
            style={s.fullTermsHeader}
            onPress={() => setFullTermsOpen(v => !v)}
            hitSlop={4}
            accessibilityRole="button"
            accessibilityLabel="Key Terms Summary"
            accessibilityState={{ expanded: fullTermsOpen }}
          >
            <Text style={s.sectionTitle}>Key Terms Summary</Text>
            <Text style={s.chevron}>{fullTermsOpen ? '▲' : '▼'}</Text>
          </Pressable>

          {fullTermsOpen && (
            <View style={s.fullTermsBody}>
              <Text style={s.ftSubhead}>1. Acceptance of Terms</Text>
              <Text style={s.ftBody}>
                These Terms constitute a legally binding agreement between you and JDT LLC
                (doing business as Snatch It). By creating an account or using the platform
                in any manner, you agree to be bound by these Terms. Your continued use
                following any modifications constitutes acceptance of the revised Terms.
              </Text>

              <Text style={s.ftSubhead}>2. Eligibility</Text>
              <Text style={s.ftBody}>
                You must be at least 18 years of age, have the legal capacity to enter
                binding contracts, not be barred by applicable law, and not have been
                previously suspended from the platform.
              </Text>

              <Text style={s.ftSubhead}>3. Account Registration</Text>
              <Text style={s.ftBody}>
                You agree to provide accurate information, maintain the confidentiality of
                your credentials, and immediately notify Snatch It of any unauthorized access.
                You may not transfer or sell your account. Snatch It may suspend or terminate
                any account at its sole discretion.
              </Text>

              <Text style={s.ftSubhead}>4. Marketplace Role & Disclaimer</Text>
              <Text style={s.ftBody}>
                Snatch It operates solely as a technology platform. It is NOT a party to
                any transaction, does not act as an escrow service, financial intermediary,
                broker, agent, or ticket vendor. All transactions are conducted directly
                between users. Snatch It bears no responsibility for the outcome of any
                transaction.
              </Text>

              <Text style={s.ftSubhead}>5. Transactions Between Users</Text>
              <Text style={s.ftBody}>
                All transactions are strictly between buyer and seller. Snatch It assumes no
                responsibility for performance, quality, safety, or legality. Sellers are solely
                responsible for listing accuracy and ticket validity. Buyers are solely responsible
                for reviewing listings and confirming receipt. Transactions are final once
                payment is confirmed. Snatch It does not guarantee refunds, returns, or exchanges.
              </Text>

              <Text style={s.ftSubhead}>6. Payments & Fees</Text>
              <Text style={s.ftBody}>
                Payments are processed by Stripe. A 10% service fee is added to the buyer&apos;s
                total at checkout, and a 10% marketplace fee is deducted from the seller&apos;s
                payout. Snatch It does not store payment card details. Under our protected
                payment flow, funds are held by Stripe on Snatch It&apos;s behalf until the buyer
                confirms ticket receipt (or the auto-release window expires), at which point
                the seller&apos;s net is transferred to their connected Stripe account. All
                transactions are denominated in USD.
              </Text>

              <Text style={s.ftSubhead}>6a. Chargebacks, Refunds & Negative Balances</Text>
              <Text style={s.ftBody}>
                If a buyer disputes a charge through their bank, or if a refund is issued
                after a payout has been released to the seller, Stripe may debit the disputed
                or refunded amount from the seller&apos;s future payouts to recover the funds. By
                accepting payouts through Snatch It, sellers authorize Stripe to debit their
                connected Stripe Express account balance as needed. Sellers remain responsible
                for any negative balance not covered by future payouts.
              </Text>

              <Text style={s.ftSubhead}>6b. Tax Reporting (Form 1099-K)</Text>
              <Text style={s.ftBody}>
                Stripe issues IRS Form 1099-K to US sellers whose annual gross payment volume
                meets or exceeds the IRS reporting threshold for the applicable tax year, and
                files the form directly with the IRS on the seller&apos;s behalf. Sellers are
                responsible for keeping their tax information (SSN/EIN) accurate within
                Stripe&apos;s onboarding and for reporting their income to the relevant tax
                authorities. Snatch It does not provide tax advice.
              </Text>

              <Text style={s.ftSubhead}>7. Prohibited Activities</Text>
              <Text style={s.ftBody}>
                You agree not to list counterfeit, stolen, invalid, or fraudulent tickets;
                engage in fraud or misrepresentation; manipulate bids or auction outcomes;
                use automated tools to access the platform; harass other users; or violate
                any applicable law, including ticket resale regulations. Snatch It has no
                tolerance for objectionable content or abusive behavior — violating
                listings are removed and offending accounts may be suspended or banned.
              </Text>

              <Text style={s.ftSubhead}>8. Listings & Accuracy</Text>
              <Text style={s.ftBody}>
                Sellers warrant that all tickets are genuine, in their lawful possession, and
                that all listing information is accurate and complete. Snatch It does not verify
                or endorse any listing.
              </Text>

              <Text style={s.ftSubhead}>9. Disputes Between Users</Text>
              <Text style={s.ftBody}>
                Snatch It is not a party to user disputes and is not responsible for resolving
                them. Users agree to attempt resolution in good faith before seeking external
                remedies. You agree to hold Snatch It harmless from any claims arising from
                disputes between users.
              </Text>

              <Text style={s.ftSubhead}>10. Limitation of Liability</Text>
              <Text style={s.ftBody}>
                To the maximum extent permitted by law, Snatch It shall not be liable for any
                indirect, incidental, special, consequential, or exemplary damages. Total
                aggregate liability shall not exceed the greater of service fees paid by you
                in the preceding 12 months or $100.00.
              </Text>

              <Text style={s.ftSubhead}>11. Disclaimer of Warranties</Text>
              <Text style={s.ftBody}>
                The platform is provided &quot;as is&quot; and &quot;as available&quot; without warranties of any
                kind. Snatch It does not warrant that the platform will be uninterrupted or
                error-free, or that any ticket listed is genuine, valid, or transferable.
              </Text>

              <Text style={s.ftSubhead}>12. Beta Disclaimer</Text>
              <Text style={s.ftBody}>
                The platform is currently in beta / early access. It is under active development
                and may contain bugs, errors, or defects. Features and functionality may change
                at any time without notice.
              </Text>

              <Text style={s.ftSubhead}>13. Governing Law & Arbitration</Text>
              <Text style={s.ftBody}>
                These Terms are governed by the laws of the State of Florida. Any dispute shall
                be resolved through binding individual arbitration administered by the AAA under
                its Consumer Arbitration Rules, in Miami-Dade County, Florida. Class action
                claims are waived. Before initiating arbitration, contact support@snatchitapp.com
                and attempt informal resolution for at least 30 days.
              </Text>

              <Text style={s.ftSubhead}>14. Indemnification</Text>
              <Text style={s.ftBody}>
                You agree to indemnify and hold harmless Snatch It and its officers, directors,
                employees, and affiliates from any claims, damages, or expenses arising from your
                use of the platform, your listings, any transaction you enter into, or your
                violation of these Terms.
              </Text>

              <Text style={s.ftNote}>
                JDT LLC · Snatch It · support@snatchitapp.com{'\n'}
                Effective March 20, 2026
              </Text>
            </View>
          )}
        </View>

        <View style={s.bottomPad} />
      </ScrollView>
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

function makeStyles(p: Palette) {
  return StyleSheet.create({
  safe:         { flex: 1, backgroundColor: p.surface.canvas },

  scroll:       { flex: 1 },
  content:      { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg },

  pageTitle:    { fontFamily: v2.font.display, fontSize: 26, lineHeight: 33, letterSpacing: -0.5,
                  textTransform: 'uppercase', color: p.text.primary, marginBottom: v2.space.xs },
  effectiveDate:{ fontFamily: v2.font.body, fontSize: 13, lineHeight: 18, color: p.text.faint,
                  marginBottom: v2.space.lg },

  section:      { marginBottom: v2.space.lg },
  sectionTitle: { fontFamily: v2.font.bodyMedium, fontSize: 10, lineHeight: 14, letterSpacing: 3,
                  textTransform: 'uppercase', color: p.text.muted, marginBottom: v2.space.sm },
  body:         { fontFamily: v2.font.body, fontSize: 15, lineHeight: 22, color: p.text.secondary,
                  marginBottom: v2.space.sm },

  bulletRow:    { flexDirection: 'row', marginBottom: v2.space.xs, paddingLeft: v2.space.xs },
  bulletDot:    { color: p.brand.redText, fontSize: 15, marginRight: v2.space.sm, lineHeight: 22 },
  bulletText:   { flex: 1, fontFamily: v2.font.body, fontSize: 15, lineHeight: 22, color: p.text.secondary },

  contactEmail: { fontFamily: v2.font.bodySemi, fontSize: 15, lineHeight: 22, color: p.text.primary,
                  marginBottom: v2.space.sm },

  fullTermsHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  chevron:         { color: p.brand.redText, fontSize: 20 },
  fullTermsBody:   { marginTop: v2.space.sm, backgroundColor: p.surface.surface, padding: v2.space.md,
                     borderWidth: 1, borderColor: p.border.default },
  ftSubhead:       { fontFamily: v2.font.bodySemi, fontSize: 15, lineHeight: 22, color: p.text.primary,
                     marginTop: v2.space.md, marginBottom: v2.space.xs },
  ftBody:          { fontFamily: v2.font.body, fontSize: 15, lineHeight: 22, color: p.text.muted },
  ftNote:          { fontFamily: v2.font.body, fontSize: 13, lineHeight: 18, color: p.text.faint,
                     marginTop: v2.space.lg, textAlign: 'center' },

  privacyLink:     { borderWidth: 1, borderColor: p.border.strong, paddingVertical: v2.space.md,
                     paddingHorizontal: v2.space.md, alignItems: 'center', marginTop: v2.space.sm },
  privacyLinkText: { fontFamily: v2.font.bodyBold, fontSize: 12, letterSpacing: 2.2,
                     textTransform: 'uppercase', color: p.brand.redText },

  bottomPad:    { height: v2.space.xxxl },
  });
}
