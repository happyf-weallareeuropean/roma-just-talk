const repoUrl = "https://github.com/happyf-weallareeuropean/roma-just-talk";
const rawBase = "https://raw.githubusercontent.com/happyf-weallareeuropean/roma-just-talk/main/";
const discordId = "freedom_uuuuuuuuuuuuuuunion.p.f";
const waitlistEmail = "happyfumd@icloud.com";

function detectOs() {
  const ua = navigator.userAgent.toLowerCase();
  const platform = (navigator.platform || "").toLowerCase();
  if (ua.includes("windows") || platform.includes("win")) return "windows";
  if (ua.includes("mac os") || platform.includes("mac")) return "mac";
  return "other";
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function readmeUrl(url, mode) {
  if (/^(https?:|mailto:|#)/.test(url)) return url;
  const cleanUrl = url.replace(/^.\//, "");
  return mode === "raw" ? `${rawBase}${cleanUrl}` : `${repoUrl}/blob/main/${cleanUrl}`;
}

function inlineMarkdown(value) {
  return escapeHtml(value)
    .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_match, alt, url) => {
      return `<img src="${readmeUrl(url, "raw")}" alt="${alt}" loading="lazy" />`;
    })
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_match, label, url) => {
      return `<a href="${readmeUrl(url, "blob")}" target="_blank" rel="noreferrer">${label}</a>`;
    })
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>");
}

function markdownToHtml(markdown) {
  const lines = markdown.split("\n");
  const html = [];
  let listOpen = false;
  let orderedListOpen = false;
  let codeOpen = false;
  let skipHtmlBlock = false;

  const closeLists = () => {
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
    const trimmed = line.trim();
    if (trimmed.startsWith("<div")) {
      skipHtmlBlock = true;
      return;
    }
    if (skipHtmlBlock) {
      if (trimmed.startsWith("</div>")) skipHtmlBlock = false;
      return;
    }
    if (trimmed.startsWith("<") && trimmed.endsWith(">")) return;
    if (line.startsWith("```")) {
      closeLists();
      html.push(codeOpen ? "</code></pre>" : "<pre><code>");
      codeOpen = !codeOpen;
      return;
    }
    if (codeOpen) {
      html.push(`${escapeHtml(line)}\n`);
      return;
    }
    if (!trimmed) {
      closeLists();
      return;
    }
    if (line === "---") {
      closeLists();
      html.push("<hr />");
      return;
    }
    const heading = /^(#{1,4})\s+(.+)$/.exec(line);
    if (heading) {
      closeLists();
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
    closeLists();
    html.push(`<p>${inlineMarkdown(line)}</p>`);
  });

  closeLists();
  if (codeOpen) html.push("</code></pre>");
  return html.join("");
}

function setWindowsMode() {
  document.getElementById("mac-actions")?.classList.add("hidden");
  document.getElementById("waitlist-form")?.classList.remove("hidden");
  requestAnimationFrame(() => document.getElementById("waitlist-email")?.focus());
}

async function submitWaitlist(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const state = document.getElementById("waitlist-state");
  const email = document.getElementById("waitlist-email");
  if (!email.value.trim()) {
    state.textContent = "type an email first";
    email.focus();
    return;
  }

  const subject = encodeURIComponent("Roma Just Talk Windows waitlist");
  const body = encodeURIComponent(`Add me to the Windows waitlist: ${email.value.trim()}`);
  state.textContent = "opening email draft. send it to join.";
  window.location.href = `mailto:${waitlistEmail}?subject=${subject}&body=${body}`;
  form.reset();
}

function toggleContact() {
  document.getElementById("contact-panel")?.classList.toggle("hidden");
}

async function copyDiscord() {
  const state = document.getElementById("contact-state");
  try {
    await navigator.clipboard.writeText(discordId);
    state.textContent = "saved my discord id in clipboard. ⌘V to paste.";
  } catch (_error) {
    state.textContent = `copy this discord id: ${discordId}`;
  }
  window.open("https://discord.com/channels/@me/", "_blank", "noopener,noreferrer");
}

async function loadReadme() {
  const target = document.getElementById("readme-content");
  try {
    const response = await fetch(`${rawBase}README.md`);
    if (!response.ok) throw new Error(`README fetch failed: ${response.status}`);
    target.innerHTML = markdownToHtml(await response.text());
  } catch (_error) {
    target.innerHTML = `<p>readme failed to load. open it on <a href="${repoUrl}" target="_blank" rel="noreferrer">github</a>.</p>`;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  if (detectOs() === "windows") setWindowsMode();
  document.getElementById("waitlist-form")?.addEventListener("submit", submitWaitlist);
  document.getElementById("talk-button")?.addEventListener("click", toggleContact);
  document.getElementById("discord-button")?.addEventListener("click", copyDiscord);
  loadReadme();
});

document.addEventListener("keydown", (event) => {
  const key = event.key.toLowerCase();
  if (event.key === "Enter" && event.shiftKey) {
    event.preventDefault();
    window.open(repoUrl, "_blank", "noopener,noreferrer");
    return;
  }
  if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
    event.preventDefault();
    toggleContact();
    return;
  }
  if (event.key === "Enter") {
    const waitlist = document.getElementById("waitlist-form");
    if (!waitlist.classList.contains("hidden")) return;
    event.preventDefault();
    window.location.href = "https://github.com/happyf-weallareeuropean/roma-just-talk/releases/latest/download/VoiceInk.dmg";
    return;
  }
  if (key === "a") window.open("https://x.com/Hft_freedom", "_blank", "noopener,noreferrer");
  if (key === "s") copyDiscord();
  if (key === "d") window.open("https://t.me/felixorder", "_blank", "noopener,noreferrer");
});
