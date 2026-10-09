import type { Metadata, Viewport } from "next";
import { Inter, Newsreader } from "next/font/google";
import "./globals.css";

const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });
/** Editorial serif for titles, section headings and headline figures (approved concept, 2026-10-09). */
const newsreader = Newsreader({ subsets: ["latin"], display: "swap", variable: "--font-newsreader", axes: ["opsz"], style: ["normal"] });
export const metadata: Metadata = {
  title: { default: "Venue dashboard · DEMO", template: "%s · Venue dashboard · DEMO" },
  description: "Snatch It venue dashboard — preview over sample data. Not live venue operations.",
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
