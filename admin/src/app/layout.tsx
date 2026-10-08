import type { Metadata, Viewport } from "next";
import { Inter, Instrument_Serif } from "next/font/google";
import "./globals.css";
import { ENV_LABEL } from "@/lib/env";

// Inter via next/font (self-hosted at build; CSP font-src 'self'). display:
// 'swap' + the system stack in --font-sans keep the UI legible if the font
// file is missing.
const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });
/** The serif sets the page title only — shared with the venue dashboard (globals.css header). */
const serif = Instrument_Serif({ subsets: ["latin"], weight: "400", display: "swap", variable: "--font-instrument" });

export const metadata: Metadata = {
  title: { default: `Console · ${ENV_LABEL}`, template: `%s · Console · ${ENV_LABEL}` },
  description: "Snatch It operating console",
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
