import type { Metadata, Viewport } from "next";
import { Inter, Instrument_Serif } from "next/font/google";
import "./globals.css";

const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });
/**
 * The serif is used once per page, for the page title (and a hero figure or
 * name) — the treatment the reference dashboard uses for "Invite Guests".
 * Everything a person reads or operates is Inter.
 */
const serif = Instrument_Serif({ subsets: ["latin"], weight: "400", display: "swap", variable: "--font-instrument" });

export const metadata: Metadata = {
  title: { default: "Venue dashboard · DEMO", template: "%s · Venue dashboard · DEMO" },
  description: "Snatch It venue dashboard — preview over sample data. Not live venue operations.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: "#0f0f10",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${serif.variable}`}>
      <body className="min-h-dvh antialiased">{children}</body>
    </html>
  );
}
