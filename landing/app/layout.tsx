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

const logoUrl = "/roma-logo.png";

export const metadata: Metadata = {
  title: "roma-just-talk",
  description:
    "Dictation that catches the words before the hotkey, then turns speech into text fast enough to replace typing.",
  icons: {
    icon: logoUrl,
    shortcut: logoUrl,
  },
  openGraph: {
    title: "roma-just-talk",
    description:
      "Speak before press hotkey. Pre-roll dictation built from VoiceInk.",
    images: [logoUrl],
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
