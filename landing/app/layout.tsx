import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono, Instrument_Serif, Space_Grotesk } from "next/font/google";
import "./globals.css";

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
});

const fraunces = Fraunces({
  variable: "--font-fraunces",
  subsets: ["latin"],
  axes: ["SOFT", "WONK", "opsz"],
});

const ibmPlexMono = IBM_Plex_Mono({
  variable: "--font-ibm-plex-mono",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

const instrumentSerif = Instrument_Serif({
  variable: "--font-instrument-serif",
  subsets: ["latin"],
  weight: "400",
});

const logoUrl =
  "https://raw.githubusercontent.com/happyf-weallareeuropean/roma-just-talk/main/docs/assets/roma-just-talk-logo.png";

export const metadata: Metadata = {
  title: "roma-just-talk",
  description:
    "Dictation: Say first, press hotkey later. Stop losing ideas and typing anyway.",
  icons: {
    icon: logoUrl,
    shortcut: logoUrl,
  },
  openGraph: {
    title: "roma-just-talk",
    description:
      "Dictation: Say first, press hotkey later. Stop losing ideas and typing anyway.",
    images: [logoUrl],
  },
  other: {
    "darkreader-lock": "",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${spaceGrotesk.variable} ${fraunces.variable} ${ibmPlexMono.variable} ${instrumentSerif.variable}`}
      >
        {children}
      </body>
    </html>
  );
}
