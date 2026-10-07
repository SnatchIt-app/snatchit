import type { Metadata, Viewport } from "next";
import { Inter, Oswald } from "next/font/google";
import "./globals.css";

const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });
/**
 * Oswald is the marketing site's display face (snatchitapp.com, measured
 * 2026-10-06 on its white "chapter" sections: Oswald 700, uppercase,
 * leading 0.85). It is used here for page and section headings and for the
 * name of a thing in a list — never for body copy, labels or controls, which
 * stay Inter in sentence case. That is the site's own rule.
 */
const oswald = Oswald({ subsets: ["latin"], weight: ["400", "500", "600", "700"], display: "swap", variable: "--font-oswald" });

export const metadata: Metadata = {
  title: { default: "Venue dashboard · DEMO", template: "%s · Venue dashboard · DEMO" },
  description: "Snatch It venue dashboard — preview over sample data. Not live venue operations.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: "#ffffff",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${oswald.variable}`}>
      <body className="min-h-dvh antialiased">{children}</body>
    </html>
  );
}
