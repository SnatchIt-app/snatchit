/**
 * app/settings/legal.tsx — Terms & Privacy
 * Effective Date: March 20, 2026
 */

import { router } from 'expo-router';
import { useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { colors, fontSize, radius, spacing } from '@/src/theme';

// ─── Section component ────────────────────────────────────────────────────────

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={s.section}>
      <Text style={s.sectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

function Body({ children }: { children: string }) {
  return <Text style={s.body}>{children}</Text>;
}

function Bullet({ children }: { children: string }) {
  return (
    <View style={s.bulletRow}>
      <Text style={s.bulletDot}>·</Text>
      <Text style={s.bulletText}>{children}</Text>
    </View>
  );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

export default function LegalScreen() {
  const [fullTermsOpen, setFullTermsOpen] = useState(false);

  return (
    <SafeAreaView style={s.safe}>
      {/* Top bar */}
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>←</Text>
        </Pressable>
        <Text style={s.topTitle}>Terms of Service</Text>
        <View style={s.backBtn} />
      </View>

      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.content}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <Text style={s.pageTitle}>Terms of Service</Text>
        <Text style={s.effectiveDate}>Effective Date: March 20, 2026</Text>

        {/* 1. About */}
        <Section title="About Snatch It">
          <Body>
            Snatch It is a technology marketplace platform operated by JDT LLC that connects
            independent ticket sellers with buyers. Snatch It is not a party to any transaction
            between users and does not act as a broker, agent, escrow service, or ticket vendor.
            All transactions are conducted directly between users.
          </Body>
        </Section>

        {/* 2. Terms of Use */}
        <Section title="Terms of Use">
          <Body>By using the platform, you agree to the following:</Body>
          <Bullet>
            Sellers are solely responsible for the accuracy of their listings and the validity
            and authenticity of all tickets offered.
          </Bullet>
          <Bullet>
            Buyers are solely responsible for reviewing listing details before purchasing or
            bidding, and for confirming receipt of tickets.
          </Bullet>
          <Bullet>
            Transactions are conducted directly between buyers and sellers. Once payment is
            processed and confirmed, transactions are final.
          </Bullet>
          <Bullet>
            All payments are processed by third-party payment providers (currently Stripe).
            Snatch It does not store payment card details. Under our protected payment flow,
            payment funds are held by Stripe on Snatch It's behalf until the buyer confirms
            receipt of the ticket (or the auto-release window expires), at which point the
            seller's net payout is released.
          </Bullet>
          <Bullet>
            A 10% service fee is added to the buyer's total at checkout, and a 10%
            marketplace fee is deducted from the seller's payout. Snatch It reserves
            the right to modify fee structures with reasonable notice.
          </Bullet>
          <Bullet>
            Chargebacks and refunds: if a buyer disputes a charge through their
            bank, or if a refund is issued after a payout has been released to
            the seller, Stripe may debit the disputed or refunded amount from
            the seller's future payouts to recover the funds. By accepting
            payouts through Snatch It, sellers authorize Stripe to debit their
            connected account balance as needed. Sellers receive a tax form
            (Form 1099-K) from Stripe each year for payouts that exceed the
            applicable IRS reporting threshold; Stripe files this directly with
            the IRS on the seller's behalf.
          </Bullet>
          <Bullet>
            Use of the platform is at your own risk. Snatch It does not guarantee the
            validity, authenticity, or transferability of any ticket listed.
          </Bullet>
          <Bullet>
            You must be at least 18 years of age and have the legal capacity to enter
            binding contracts to use this platform.
          </Bullet>
        </Section>

        {/* 3. Privacy & Data */}
        <Section title="Privacy & Data">
          <Body>
            Your use of the platform is also governed by our Privacy Policy. By using Snatch It,
            you consent to the collection, use, and disclosure of your information as described
            therein. Your information may be used to:
          </Body>
          <Bullet>Operate and maintain the platform and your account.</Bullet>
          <Bullet>Process transactions and facilitate communication between users.</Bullet>
          <Bullet>Provide customer support and respond to inquiries.</Bullet>
          <Bullet>Improve the platform and develop new features.</Bullet>
          <Pressable
            style={s.privacyLink}
            onPress={() => router.push('/settings/privacy')}
          >
            <Text style={s.privacyLinkText}>View Full Privacy Policy {'\u2192'}</Text>
          </Pressable>
        </Section>

        {/* 4. Contact */}
        <Section title="Contact">
          <Body>
            For legal inquiries, dispute resolution, or questions about these terms, contact us at:
          </Body>
          <Text style={s.contactEmail}>support@snatchitapp.com</Text>
          <Body>
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
                Payments are processed by Stripe. A 10% service fee is added to the buyer's
                total at checkout, and a 10% marketplace fee is deducted from the seller's
                payout. Snatch It does not store payment card details. Under our protected
                payment flow, funds are held by Stripe on Snatch It's behalf until the buyer
                confirms ticket receipt (or the auto-release window expires), at which point
                the seller's net is transferred to their connected Stripe account. All
                transactions are denominated in USD.
              </Text>

              <Text style={s.ftSubhead}>6a. Chargebacks, Refunds & Negative Balances</Text>
              <Text style={s.ftBody}>
                If a buyer disputes a charge through their bank, or if a refund is issued
                after a payout has been released to the seller, Stripe may debit the disputed
                or refunded amount from the seller's future payouts to recover the funds. By
                accepting payouts through Snatch It, sellers authorize Stripe to debit their
                connected Stripe Express account balance as needed. Sellers remain responsible
                for any negative balance not covered by future payouts.
              </Text>

              <Text style={s.ftSubhead}>6b. Tax Reporting (Form 1099-K)</Text>
              <Text style={s.ftBody}>
                Stripe issues IRS Form 1099-K to US sellers whose annual gross payment volume
                meets or exceeds the IRS reporting threshold for the applicable tax year, and
                files the form directly with the IRS on the seller's behalf. Sellers are
                responsible for keeping their tax information (SSN/EIN) accurate within
                Stripe's onboarding and for reporting their income to the relevant tax
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
                The platform is provided "as is" and "as available" without warranties of any
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
    </SafeAreaView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe:         { flex: 1, backgroundColor: colors.bg },

  // Top bar (matches app pattern)
  topBar:       { flexDirection: 'row', alignItems: 'center',
                  justifyContent: 'space-between',
                  paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
                  borderBottomWidth: 1, borderBottomColor: colors.border },
  backBtn:      { width: 44, height: 44, alignItems: 'flex-start',
                  justifyContent: 'center' },
  backArrow:    { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:     { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  // Scroll
  scroll:       { flex: 1 },
  content:      { paddingHorizontal: spacing.md, paddingTop: spacing.lg },

  // Page header
  pageTitle:    { color: colors.text, fontSize: fontSize.lg, fontWeight: '800',
                  marginBottom: spacing.xs },
  effectiveDate:{ color: colors.textMuted, fontSize: fontSize.xs,
                  marginBottom: spacing.lg },

  // Section
  section:      { marginBottom: spacing.lg },
  sectionTitle: { color: colors.primary, fontSize: fontSize.sm, fontWeight: '700',
                  textTransform: 'uppercase', letterSpacing: 0.8,
                  marginBottom: spacing.sm },
  body:         { color: colors.textMuted, fontSize: fontSize.sm, lineHeight: 20,
                  marginBottom: spacing.sm },

  // Bullet
  bulletRow:    { flexDirection: 'row', marginBottom: spacing.xs,
                  paddingLeft: spacing.xs },
  bulletDot:    { color: colors.primary, fontSize: fontSize.md,
                  marginRight: spacing.sm, lineHeight: 20 },
  bulletText:   { flex: 1, color: colors.textMuted, fontSize: fontSize.sm,
                  lineHeight: 20 },

  // Contact email
  contactEmail: { color: colors.text, fontSize: fontSize.sm, fontWeight: '600',
                  marginBottom: spacing.sm },

  // Full Terms accordion
  fullTermsHeader: { flexDirection: 'row', alignItems: 'center',
                     justifyContent: 'space-between' },
  chevron:         { color: colors.primary, fontSize: fontSize.sm },
  fullTermsBody:   { marginTop: spacing.sm, backgroundColor: colors.bgCard,
                     borderRadius: radius.md, padding: spacing.md,
                     borderWidth: 1, borderColor: colors.border },
  ftSubhead:       { color: colors.text, fontSize: fontSize.sm, fontWeight: '700',
                     marginTop: spacing.md, marginBottom: spacing.xs },
  ftBody:          { color: colors.textMuted, fontSize: fontSize.sm, lineHeight: 20 },
  ftNote:          { color: colors.textDim, fontSize: fontSize.xs, lineHeight: 18,
                     marginTop: spacing.lg, textAlign: 'center' },

  // Privacy link
  privacyLink:     { backgroundColor: colors.bgCard, borderRadius: radius.md,
                     borderWidth: 1, borderColor: colors.border,
                     paddingVertical: spacing.md, paddingHorizontal: spacing.md,
                     alignItems: 'center', marginTop: spacing.xs },
  privacyLinkText: { color: colors.primary, fontSize: fontSize.sm, fontWeight: '700' },

  bottomPad:    { height: spacing.xxl },
});
