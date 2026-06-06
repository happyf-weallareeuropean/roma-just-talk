"use client";

import {
  FormEvent,
  KeyboardEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

const REPO_URL = "https://github.com/happyf-weallareeuropean/roma-just-talk";
const MAC_DOWNLOAD_URL =
  "https://github.com/happyf-weallareeuropean/roma-just-talk/releases/latest/download/VoiceInk.dmg";
const LOGO_URL =
  "https://raw.githubusercontent.com/happyf-weallareeuropean/roma-just-talk/main/docs/assets/roma-just-talk-logo.png";
const HOWTO_IMAGE_URL =
  "https://github.com/user-attachments/assets/6fd92e7c-dafc-409c-b8c0-a2027b446124";
const X_URL = "https://x.com/Hft_freedom";
const TELEGRAM_URL = "https://t.me/felixorder";
const DISCORD_URL = "https://discord.com/channels/@me/";
const DISCORD_ID = "freedom_uuuuuuuuuuuuuuunion.p.f";

type OsKind = "mac" | "windows" | "other";

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function readmeUrl(url: string, mode: "blob" | "raw") {
  if (/^(https?:|mailto:|#)/.test(url)) {
    return url;
  }

  const cleanUrl = url.replace(/^.\//, "");
  if (mode === "raw") {
    return `https://raw.githubusercontent.com/happyf-weallareeuropean/roma-just-talk/main/${cleanUrl}`;
  }

  return `${REPO_URL}/blob/main/${cleanUrl}`;
}

function inlineMarkdown(value: string) {
  return escapeHtml(value)
    .replace(
      /!\[([^\]]*)\]\(([^)]+)\)/g,
      (_match, alt: string, url: string) =>
        `<img src="${readmeUrl(url, "raw")}" alt="${alt}" loading="lazy" />`
    )
    .replace(
      /\[([^\]]+)\]\(([^)]+)\)/g,
      (_match, label: string, url: string) =>
        `<a href="${readmeUrl(url, "blob")}" target="_blank" rel="noreferrer">${label}</a>`
    )
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>");
}

function markdownToHtml(markdown: string) {
  const lines = markdown.split("\n");
  const html: string[] = [];
  let listOpen = false;
  let orderedListOpen = false;
  let codeOpen = false;
  let skipHtmlBlock = false;

  const closeList = () => {
    if (listOpen) {
      html.push("</ul>");
      listOpen = false;
    }
    if (orderedListOpen) {
      html.push("</ol>");
      orderedListOpen = false;
    }
  };

  lines.forEach((line) => {
    const trimmedLine = line.trim();

    if (trimmedLine.startsWith("<div")) {
      skipHtmlBlock = true;
      return;
    }

    if (skipHtmlBlock) {
      if (trimmedLine.startsWith("</div>")) {
        skipHtmlBlock = false;
      }
      return;
    }

    if (trimmedLine.startsWith("<") && trimmedLine.endsWith(">")) {
      return;
    }

    if (line.startsWith("```")) {
      closeList();
      html.push(codeOpen ? "</code></pre>" : "<pre><code>");
      codeOpen = !codeOpen;
      return;
    }

    if (codeOpen) {
      html.push(`${escapeHtml(line)}\n`);
      return;
    }

    if (!line.trim()) {
      closeList();
      return;
    }

    if (line === "---") {
      closeList();
      html.push("<hr />");
      return;
    }

    const heading = /^(#{1,4})\s+(.+)$/.exec(line);
    if (heading) {
      closeList();
      const level = heading[1].length + 1;
      html.push(`<h${level}>${inlineMarkdown(heading[2])}</h${level}>`);
      return;
    }

    const bullet = /^[-*]\s+(.+)$/.exec(line);
    if (bullet) {
      if (!listOpen) {
        if (orderedListOpen) {
          html.push("</ol>");
          orderedListOpen = false;
        }
        html.push("<ul>");
        listOpen = true;
      }
      html.push(`<li>${inlineMarkdown(bullet[1])}</li>`);
      return;
    }

    const ordered = /^\d+\.\s+(.+)$/.exec(line);
    if (ordered) {
      if (!orderedListOpen) {
        if (listOpen) {
          html.push("</ul>");
          listOpen = false;
        }
        html.push("<ol>");
        orderedListOpen = true;
      }
      html.push(`<li>${inlineMarkdown(ordered[1])}</li>`);
      return;
    }

    closeList();
    html.push(`<p>${inlineMarkdown(line)}</p>`);
  });

  closeList();
  if (codeOpen) {
    html.push("</code></pre>");
  }

  return html.join("");
}

function AppleIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" className="icon">
      <path d="M16.8 12.8c0-2 1.6-3 1.7-3.1-1-.1-2.5-.9-3.4-.9-1.4 0-2.2.8-3.1.8-.9 0-1.7-.8-3-.8-1.5 0-3 .9-3.8 2.3-1.6 2.9-.4 7.2 1.2 9.5.8 1.1 1.7 2.4 3 2.3 1.2 0 1.7-.8 3.1-.8s1.8.8 3.1.8c1.3 0 2.1-1.1 2.9-2.2.9-1.3 1.2-2.5 1.2-2.6 0 0-2.5-1-2.5-4.1ZM14.2 7.3c.7-.8 1.1-1.9 1-3-1 .1-2.1.7-2.8 1.5-.6.7-1.1 1.8-1 2.8 1.1.1 2.2-.5 2.8-1.3Z" />
    </svg>
  );
}

function GithubIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" className="icon">
      <path d="M12 2C6.5 2 2 6.6 2 12.3c0 4.5 2.9 8.4 6.8 9.7.5.1.7-.2.7-.5v-1.9c-2.8.6-3.4-1.2-3.4-1.2-.5-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 0 1.6 1.1 1.6 1.1.9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.7-1.4-2.2-.3-4.5-1.1-4.5-5 0-1.1.4-2 1-2.8-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.8 1.1.8-.2 1.7-.3 2.5-.3.9 0 1.7.1 2.5.3 1.9-1.4 2.8-1.1 2.8-1.1.6 1.4.2 2.4.1 2.7.7.8 1 1.7 1 2.8 0 3.9-2.3 4.7-4.5 5 .4.3.7 1 .7 2v2.9c0 .3.2.6.7.5 4-1.3 6.8-5.2 6.8-9.7C22 6.6 17.5 2 12 2Z" />
    </svg>
  );
}

function WindowsIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" className="icon">
      <path d="M3 4.4 10.2 3v8.2H3V4.4Zm8.4-1.7L21 1.3v9.9h-9.6V2.7ZM3 12.8h7.2V21L3 19.7v-6.9Zm8.4 0H21v9.9l-9.6-1.4v-8.5Z" />
    </svg>
  );
}

function XIcon() {
  return <span className="social-glyph">X</span>;
}

function DiscordIcon() {
  return <span className="social-glyph">D</span>;
}

function TelegramIcon() {
  return <span className="social-glyph">T</span>;
}

function Keycap({ children }: { children: React.ReactNode }) {
  return <span className="keycap">{children}</span>;
}

function detectOs(): OsKind {
  if (typeof navigator === "undefined") {
    return "other";
  }

  const ua = navigator.userAgent.toLowerCase();
  const platform = navigator.platform?.toLowerCase() ?? "";

  if (ua.includes("windows") || platform.includes("win")) {
    return "windows";
  }

  if (ua.includes("mac os") || platform.includes("mac")) {
    return "mac";
  }

  return "other";
}

export default function LandingPage({ readme }: { readme: string }) {
  const [os, setOs] = useState<OsKind>("other");
  const [email, setEmail] = useState("");
  const [waitlistState, setWaitlistState] = useState("windows build not ready yet");
  const [contactOpen, setContactOpen] = useState(false);
  const [contactState, setContactState] = useState("choose a channel");
  const waitlistInputRef = useRef<HTMLInputElement>(null);
  const readmeHtml = useMemo(() => markdownToHtml(readme), [readme]);

  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      const detected = detectOs();
      setOs(detected);

      if (detected === "windows") {
        waitlistInputRef.current?.focus();
      }
    });

    return () => cancelAnimationFrame(frame);
  }, []);

  const openExternal = useCallback((url: string) => {
    window.open(url, "_blank", "noopener,noreferrer");
  }, []);

  const submitWaitlist = useCallback(async () => {
    const normalizedEmail = email.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
      setWaitlistState("type an email first");
      waitlistInputRef.current?.focus();
      return;
    }

    setWaitlistState("saving");

    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: normalizedEmail, sourceOs: os }),
      });
      const payload = (await response.json()) as { error?: string };

      if (!response.ok) {
        throw new Error(payload.error ?? "waitlist failed");
      }

      setWaitlistState("saved for windows waitlist");
    } catch {
      setWaitlistState("waitlist backend needs deployed Sites DB");
    }
  }, [email, os]);

  const copyDiscordAndOpen = useCallback(async () => {
    setContactState("saved discord id to clipboard. cmd-v to paste.");
    openExternal(DISCORD_URL);

    try {
      await navigator.clipboard.writeText(DISCORD_ID);
    } catch {
      setContactState(`copy failed. discord id: ${DISCORD_ID}`);
    }
  }, [openExternal]);

  useEffect(() => {
    const onKeyDown = (event: globalThis.KeyboardEvent) => {
      const active = document.activeElement;
      const isTyping =
        active instanceof HTMLInputElement ||
        active instanceof HTMLTextAreaElement ||
        active instanceof HTMLSelectElement;

      if (isTyping && event.key !== "Enter") {
        return;
      }

      if (contactOpen) {
        const key = event.key.toLowerCase();
        if (key === "a") {
          event.preventDefault();
          openExternal(X_URL);
        }
        if (key === "s") {
          event.preventDefault();
          copyDiscordAndOpen();
        }
        if (key === "d") {
          event.preventDefault();
          openExternal(TELEGRAM_URL);
        }
      }

      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        setContactOpen((value) => !value);
        return;
      }

      if (event.key === "Enter" && event.shiftKey) {
        event.preventDefault();
        openExternal(REPO_URL);
        return;
      }

      if (event.key === "Enter") {
        event.preventDefault();
        if (os === "windows") {
          void submitWaitlist();
        } else {
          openExternal(MAC_DOWNLOAD_URL);
        }
      }
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [contactOpen, copyDiscordAndOpen, openExternal, os, submitWaitlist]);

  function handlePrimaryClick() {
    if (os === "windows") {
      void submitWaitlist();
      return;
    }

    openExternal(MAC_DOWNLOAD_URL);
  }

  function handleWaitlistSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void submitWaitlist();
  }

  function handleWaitlistKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Enter") {
      event.preventDefault();
      void submitWaitlist();
    }
  }

  const waitlistProgress = Math.min(100, Math.max(12, email.length * 5));

  return (
    <main>
      <section className="hero" aria-label="roma-just-talk landing">
        <img className="hero-bg-logo" src={LOGO_URL} alt="" loading="eager" />
        <div className="hero-inner">
          <nav className="topline" aria-label="primary">
            <a className="brand-lockup" href={REPO_URL} target="_blank" rel="noreferrer">
              <img src={LOGO_URL} alt="roma-just-talk logo" />
              <span>roma-just-talk</span>
            </a>
            <div className="top-actions">
              <a href="#readme">README</a>
              <a href={REPO_URL} target="_blank" rel="noreferrer">
                GitHub
              </a>
            </div>
          </nav>

          <div className="hero-copy">
            <p className="kicker">pre-roll dictation for macOS</p>
            <h1>
              dictation that speak <span className="before-word">before</span> press hotkey,
              <span className="idea-line">
                instead of losing half your idea or ends up typing anyways
              </span>
            </h1>
            <p className="body-copy">we aim to make dictation actually replace typing</p>

            <div className="cta-row" aria-label="main actions">
              {os === "windows" ? (
                <form className="waitlist-cta" onSubmit={handleWaitlistSubmit}>
                  <div className="waitlist-field">
                    <WindowsIcon />
                    <input
                      ref={waitlistInputRef}
                      value={email}
                      onChange={(event) => setEmail(event.target.value)}
                      onKeyDown={handleWaitlistKeyDown}
                      placeholder="eg entropy@example.com"
                      aria-label="Windows waitlist email"
                    />
                    <span className="waitlist-fill" style={{ width: `${waitlistProgress}%` }} />
                  </div>
                  <button className="button primary" type="submit">
                    <span>waitlist sign up</span>
                    <Keycap>Enter</Keycap>
                  </button>
                </form>
              ) : (
                <button className="button primary" type="button" onClick={handlePrimaryClick}>
                  <AppleIcon />
                  <span>download macOS</span>
                  <Keycap>Enter</Keycap>
                </button>
              )}

              <button className="button secondary" type="button" onClick={() => openExternal(REPO_URL)}>
                <GithubIcon />
                <span>GitHub</span>
                <span className="keygroup">
                  <Keycap>Shift</Keycap>
                  <Keycap>Enter</Keycap>
                </span>
              </button>
            </div>

            {os === "windows" ? <p className="status-line">{waitlistState}</p> : null}

            <button
              className="button talk"
              type="button"
              aria-expanded={contactOpen}
              onClick={() => setContactOpen((value) => !value)}
            >
              <span>talk to me</span>
              <Keycap>Cmd Enter</Keycap>
            </button>

            {contactOpen ? (
              <div className="contact-panel" aria-label="contact links">
                <button type="button" onClick={() => openExternal(X_URL)}>
                  <XIcon />
                  <span>X</span>
                  <Keycap>A</Keycap>
                </button>
                <button type="button" onClick={copyDiscordAndOpen}>
                  <DiscordIcon />
                  <span>Discord</span>
                  <Keycap>S</Keycap>
                </button>
                <button type="button" onClick={() => openExternal(TELEGRAM_URL)}>
                  <TelegramIcon />
                  <span>Telegram</span>
                  <Keycap>D</Keycap>
                </button>
                <p>{contactState}</p>
              </div>
            ) : null}
          </div>
        </div>
      </section>

      <section className="howto-image-section" aria-label="How to use">
        <img src={HOWTO_IMAGE_URL} alt="How to use Roma Just Talk" loading="lazy" />
      </section>

      <section className="readme-section" id="readme" aria-labelledby="readme-title">
        <div className="readme-heading">
          <p>live source</p>
          <h2 id="readme-title">repo README</h2>
          <a href={`${REPO_URL}#readme`} target="_blank" rel="noreferrer">
            open on GitHub
          </a>
        </div>
        <article className="readme-card" dangerouslySetInnerHTML={{ __html: readmeHtml }} />
      </section>
    </main>
  );
}
