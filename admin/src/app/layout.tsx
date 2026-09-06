import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { ENV_LABEL } from "@/lib/env";

// Inter via next/font (self-hosted at build; CSP font-src 'self'). display:
// 'swap' + the system stack in --font-sans keep the UI legible if the font
// file is missing.
const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });

export const metadata: Metadata = {
  title: { default: `Console · ${ENV_LABEL}`, template: `%s · Console · ${ENV_LABEL}` },
  description: "Snatch It operating console",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: "#000000",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="min-h-dvh antialiased">{children}</body>
    </html>
  );
}
