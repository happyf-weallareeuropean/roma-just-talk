import LandingPage from "./LandingPage";

const README_URL =
  "https://raw.githubusercontent.com/happyf-weallareeuropean/roma-just-talk/main/README.md";

async function fetchReadme() {
  try {
    const response = await fetch(README_URL, {
      next: { revalidate: 300 },
    });

    if (!response.ok) {
      throw new Error(`README fetch failed: ${response.status}`);
    }

    return await response.text();
  } catch {
    return [
      "# roma-just-talk",
      "",
      "Most dictation apps wait for the hotkey, then open the mic.",
      "roma-just-talk keeps a short rolling pre-roll buffer so your first words are not lost.",
      "",
      "Read the source README on GitHub: https://github.com/happyf-weallareeuropean/roma-just-talk",
    ].join("\n");
  }
}

export default async function Home() {
  const readme = await fetchReadme();

  return <LandingPage readme={readme} />;
}
