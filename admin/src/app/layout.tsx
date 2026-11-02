import type { Metadata, Viewport } from "next";
import { Inter, Newsreader } from "next/font/google";
import "./globals.css";
import { ENV_LABEL } from "@/lib/env";

// Inter via next/font (self-hosted at build; CSP font-src 'self'). display:
// 'swap' + the system stack in --font-sans keep the UI legible if the font
// file is missing.
const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });
/** Editorial serif for titles, section headings and headline figures — shared with the venue dashboard. */
const newsreader = Newsreader({ subsets: ["latin"], display: "swap", variable: "--font-newsreader", axes: ["opsz"], style: ["normal"] });
export const metadata: Metadata = {
  title: { default: `Console · ${ENV_LABEL}`, template: `%s · Console · ${ENV_LABEL}` },
  description: "Snatch It operating console",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: "#f6f1ea",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${newsreader.variable}`}>
      <body className="min-h-dvh antialiased">{children}</body>
    </html>
  );
}
