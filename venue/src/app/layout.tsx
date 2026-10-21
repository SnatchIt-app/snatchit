import type { Metadata, Viewport } from "next";
import { Inter, Newsreader } from "next/font/google";
import { DATA_SOURCE } from "@/lib/env";
import { siteMetadata } from "@/lib/source";
import "./globals.css";

const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });
/** Editorial serif for titles, section headings and headline figures (approved concept, 2026-10-09). */
const newsreader = Newsreader({ subsets: ["latin"], display: "swap", variable: "--font-newsreader", axes: ["opsz"], style: ["normal"] });
/** DEMO wording only in the fixture build; NEXT_PUBLIC_VENUE_DATA_SOURCE is fixed at build time. */
export const metadata: Metadata = siteMetadata(DATA_SOURCE);

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
