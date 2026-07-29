import type { Metadata, Viewport } from "next";
import { Inter, Oswald } from "next/font/google";
import "./globals.css";
import { SITE_URL } from "@/lib/env";
import { Header } from "@/components/site/Header";
import { Footer } from "@/components/site/Footer";
import { JsonLd } from "@/components/site/JsonLd";

// Same pairing and weights as snatchitapp.com: Oswald for display type,
// Inter for body/UI. Self-hosted via next/font (CSP font-src 'self').
const oswald = Oswald({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
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
    "Bid or Buy Now on real tickets from real people across Miami. All-in prices, Stripe-secured checkout, and funds held until your ticket is delivered.",
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
  themeColor: "#000000",
  width: "device-width",
  initialScale: 1,
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

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${oswald.variable} ${inter.variable}`}>
      <body className="min-h-dvh antialiased">
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[110] focus:bg-primary focus:px-4 focus:py-2.5 focus:text-sm focus:font-bold focus:uppercase focus:tracking-wider focus:text-black"
        >
          Skip to content
        </a>
        <Header />
        <main id="main">{children}</main>
        <Footer />
        {/* Site-wide film grain, same as snatchitapp.com. */}
        <div aria-hidden="true" className="grain" />
        <JsonLd data={organizationJsonLd} />
      </body>
    </html>
  );
}
