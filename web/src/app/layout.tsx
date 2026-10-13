import type { Metadata, Viewport } from "next";
import { Inter, Oswald } from "next/font/google";
import { cookies } from "next/headers";
import "./globals.css";
import { SITE_URL } from "@/lib/env";
import { Header } from "@/components/site/Header";
import { Footer } from "@/components/site/Footer";
import { Dock } from "@/components/site/Dock";
import { OfflineNotice } from "@/components/site/OfflineNotice";
import { NavTracker } from "@/components/site/NavTracker";
import { JsonLd } from "@/components/site/JsonLd";
import { THEME_COOKIE, parseThemePreference } from "@/lib/theme";
import { getAuthedUser } from "@/lib/auth/session";
import { unreadNotificationCount } from "@/lib/notifications";

// The native app's pairing: Oswald 700 for display and event names, Inter for
// everything else. Self-hosted via next/font (CSP font-src 'self').
const oswald = Oswald({
  subsets: ["latin"],
  weight: ["700"],
  display: "swap",
  variable: "--font-oswald",
});
const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "Snatch It — Miami's Ticket Marketplace",
    template: "%s | Snatch It",
  },
  description:
    "Bid or Buy Now on real tickets from real people across Miami. All-in prices and Stripe-secured checkout.",
  openGraph: {
    siteName: "Snatch It",
    type: "website",
    locale: "en_US",
    images: [{ url: "/brand/sn-logo-on-red.png", width: 1200, height: 1200, alt: "Snatch It" }],
  },
  twitter: {
    card: "summary_large_image",
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#000000" },
  ],
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

const organizationJsonLd = {
  "@context": "https://schema.org",
  "@type": "Organization",
  name: "Snatch It",
  legalName: "JDT LLC",
  url: SITE_URL,
  logo: `${SITE_URL}/brand/sn-logo-on-red.png`,
  sameAs: ["https://snatchitapp.com"],
  address: {
    "@type": "PostalAddress",
    addressLocality: "Miami",
    addressRegion: "FL",
    addressCountry: "US",
  },
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const theme = parseThemePreference((await cookies()).get(THEME_COOKIE)?.value);
  const user = await getAuthedUser();
  const unread = user ? await unreadNotificationCount() : 0;
  return (
    <html lang="en" data-theme={theme} className={`${oswald.variable} ${inter.variable}`}>
      <body className="flex min-h-dvh flex-col antialiased">
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-3 focus:z-[110] focus:rounded-full focus:bg-brand focus:px-5 focus:py-2.5 focus:text-[15px] focus:font-bold focus:text-inverse"
        >
          Skip to content
        </a>
        <Header user={user} unread={unread} />
        <main id="main" className="flex-1">
          {children}
        </main>
        <Footer />
        <Dock signedIn={Boolean(user)} unread={unread} />
        <OfflineNotice />
        <NavTracker />
        <JsonLd data={organizationJsonLd} />
      </body>
    </html>
  );
}
