import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono, Space_Grotesk } from "next/font/google";
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

const logoUrl =
  "https://raw.githubusercontent.com/happyf-weallareeuropean/roma-just-talk/main/docs/assets/roma-just-talk-logo.png";

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
        className={`${spaceGrotesk.variable} ${fraunces.variable} ${ibmPlexMono.variable}`}
      >
        {children}
      </body>
    </html>
  );
}
