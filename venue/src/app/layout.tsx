import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({ subsets: ["latin"], display: "swap", variable: "--font-inter" });
export const metadata: Metadata = {
  title: { default: "Venue dashboard · DEMO", template: "%s · Venue dashboard · DEMO" },
  description: "Snatch It venue dashboard — preview over sample data. Not live venue operations.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: "#f5f3ef",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable}`}>
      <body className="min-h-dvh antialiased">{children}</body>
    </html>
  );
}
