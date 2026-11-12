import type { Metadata, Viewport } from "next";
import { Geist } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import { MotionProvider } from "@/components/motion";
import { SITE } from "@/lib/site";
import "./globals.css";

const geist = Geist({ subsets: ["latin"], variable: "--font-geist", display: "swap" });

const title = "Framecast — the free Mac screen recorder with Claude built in";
const description = "Free, open-source screen recorder for Mac with auto zoom, a camera bubble, captions, blur and a real timeline. Let Claude edit it to your own style.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: { default: title, template: "%s · Framecast" },
  description,
  applicationName: "Framecast",
  keywords: ["screen recorder for Mac", "free screen recorder", "open source screen recorder", "Screen Studio alternative", "auto zoom screen recording", "AI video editing", "Claude", "macOS"],
  alternates: { canonical: "/" },
  openGraph: { type: "website", siteName: "Framecast", title, description, url: "/", images: [{ url: "/media/hero.jpg", width: 1600, height: 1048 }] },
  twitter: { card: "summary_large_image", title, description, images: ["/media/hero.jpg"] },
};

export const viewport: Viewport = { themeColor: "#f3f4f6", width: "device-width", initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={geist.variable}>
      <body className="font-sans">
        <MotionProvider>{children}</MotionProvider>
        <Analytics />
      </body>
    </html>
  );
}
