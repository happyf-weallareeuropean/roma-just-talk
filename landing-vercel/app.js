const repoUrl = "https://github.com/happyf-weallareeuropean/roma-just-talk";
const repoBranch = "without/no-adhoc-macos-tcc";
const pinnedMacReleaseTag = "v1.95";
const pinnedMacDownloadUrl = `https://github.com/negentropi/roma-just-talk/releases/download/${pinnedMacReleaseTag}/roma.just.talk.app.zip`;
const releasesApi = "https://api.github.com/repos/happyf-weallareeuropean/roma-just-talk/releases";
const releasesPageUrl = `${repoUrl}/releases`;
const rawBase = `https://raw.githubusercontent.com/happyf-weallareeuropean/roma-just-talk/${repoBranch}/`;
const readmeMarkdownUrl = `${rawBase}README.md`;
const discordId = "freedom_uuuuuuuuuuuuuuunion.p.f";
const waitlistEmail = "happyfumd@icloud.com";
const fetchTimeoutMs = 8000;

function detectOs() {
  const ua = navigator.userAgent.toLowerCase();
  const platform = (navigator.platform || "").toLowerCase();
  if (ua.includes("windows") || platform.includes("win")) return "windows";
  if (ua.includes("mac os") || platform.includes("mac")) return "mac";
  return "other";
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function repoContentUrl(url, mode) {
  if (/^(https?:|mailto:|#)/.test(url)) return url;
  const cleanUrl = url.replace(/^.\//, "");
  return mode === "raw" ? `${rawBase}${cleanUrl}` : `${repoUrl}/blob/${repoBranch}/${cleanUrl}`;
}

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), fetchTimeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    window.clearTimeout(timeout);
  }
}

function downloadMac(event) {
  event?.preventDefault();
  window.showMacSetup?.();
  window.location.href = pinnedMacDownloadUrl;
}

function inlineMarkdown(value) {
  return escapeHtml(value)
    .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_match, alt, url) => {
      return `<img src="${repoContentUrl(url, "raw")}" alt="${alt}" loading="lazy" />`;
    })
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_match, label, url) => {
      return `<a href="${repoContentUrl(url, "blob")}" target="_blank" rel="noreferrer">${label}</a>`;
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
  if (!state) return;
  try {
    await navigator.clipboard.writeText(discordId);
    state.textContent = "saved my discord id in clipboard. ⌘V to paste.";
  } catch (_error) {
    state.textContent = `copy this discord id: ${discordId}`;
  }
  window.open("https://discord.com/channels/@me/", "_blank", "noopener,noreferrer");
}

function formatReleaseDate(value) {
  if (!value) return "release date pending";
  return new Intl.DateTimeFormat("en", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(value));
}

function releaseNotesToHtml(release) {
  const body = release.body?.trim();
  if (!body) return "<p>No release notes yet.</p>";
  const lines = body.split("\n");
  const firstLine = lines[0]?.trim() || "";
  const startsWithReleaseTitle = /^#{1,4}\s+/.test(firstLine) && firstLine.includes(release.tag_name);
  const notes = startsWithReleaseTitle ? lines.slice(1).join("\n").trim() : body;
  return markdownToHtml(notes || body);
}

function releaseAssetLinks(release) {
  const links = [];
  if (release.tag_name === pinnedMacReleaseTag) {
    links.unshift(`<a class="release-link release-download" href="${pinnedMacDownloadUrl}">download reviewed app (early beta)</a>`);
  }
  links.unshift(`<a class="release-link" href="${escapeHtml(release.html_url || releasesPageUrl)}">view release</a>`);
  return `<div class="release-actions">${links.join("")}</div>`;
}

function releaseAnchorId(release, index) {
  const label = release.tag_name || release.name || `release-${index + 1}`;
  const slug = label
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return `release-${slug || index + 1}`;
}

function releaseJumpToHtml(releases) {
  const links = releases
    .map((release, index) => {
      const label = release.tag_name || release.name || `release ${index + 1}`;
      return `<a href="#${releaseAnchorId(release, index)}">${escapeHtml(label)}</a>`;
    })
    .join("");
  return `<nav class="release-jump" aria-label="Jump to release">${links}</nav>`;
}

function releaseToHtml(release, index) {
  const title = release.name || release.tag_name || `release ${index + 1}`;
  const badge = release.prerelease ? "pre-release" : "release";
  return `
    <section class="release-entry" id="${releaseAnchorId(release, index)}">
      <div class="release-heading">
        <h3>${escapeHtml(title)}</h3>
        <div class="release-meta">
          <span>${escapeHtml(formatReleaseDate(release.published_at || release.created_at))}</span>
          <span>${escapeHtml(release.tag_name || badge)}</span>
          <span>${badge}</span>
        </div>
      </div>
      <div class="release-notes">
        ${releaseNotesToHtml(release)}
      </div>
      ${releaseAssetLinks(release)}
    </section>
  `;
}

async function loadReadme() {
  const target = document.getElementById("readme-content");
  if (!target) return;

  try {
    const response = await fetchWithTimeout(readmeMarkdownUrl);
    if (!response.ok) throw new Error(`README fetch failed: ${response.status}`);
    target.innerHTML = markdownToHtml(await response.text());
  } catch (_error) {
    target.innerHTML = `<p>readme failed to load. open the <a href="${repoUrl}#readme" target="_blank" rel="noreferrer">github readme</a>.</p>`;
  }
}

async function loadChangelog() {
  const target = document.getElementById("changelog-content");
  if (!target) return;

  try {
    const response = await fetchWithTimeout(releasesApi, {
      headers: { Accept: "application/vnd.github+json" },
      cache: "no-store",
    });
    if (!response.ok) throw new Error(`releases fetch failed: ${response.status}`);
    const releases = await response.json();
    if (!Array.isArray(releases)) throw new Error("releases response was not a list");
    const visibleReleases = releases.filter((release) => !release.draft).slice(0, 8);
    if (!visibleReleases.length) throw new Error("no published releases");
    target.innerHTML = `${releaseJumpToHtml(visibleReleases)}<div class="release-list">${visibleReleases.map(releaseToHtml).join("")}</div>`;
  } catch (_error) {
    target.innerHTML = `<p>changelog could not reach github releases right now. open <a href="${releasesPageUrl}" target="_blank" rel="noreferrer">github releases</a>.</p>`;
  }
}

function initFeatureTabs() {
  const shell = document.querySelector(".features-shell");
  const bar = document.querySelector(".feature-tabs");
  const scroller = document.querySelector(".feature-tabs-scroll") || bar;
  const tabs = Array.from(document.querySelectorAll(".feature-tab"));
  if (!shell || !bar || !tabs.length) return;

  const panels = tabs
    .map((tab) => document.querySelector(tab.getAttribute("href")))
    .filter(Boolean);
  const clamp = (value, minimum, maximum) => Math.min(maximum, Math.max(minimum, value));
  const smoothstep = (value) => value * value * (3 - 2 * value);
  const point = (value) => Number(value.toFixed(3));
  const edgeTolerance = 1;
  const panelTabRise = 48;
  let activeId = "";
  let shapeTarget = null;

  const roundedRectPath = ({ left, right, top, bottom, radius }) => {
    const visibleHeight = bottom - top;
    if (visibleHeight <= 1 || right - left <= 1) return "";

    const r = Math.min(radius, visibleHeight / 2, (right - left) / 2);
    return [
      `M${point(left + r)} ${point(top)}`,
      `H${point(right - r)}`,
      `Q${point(right)} ${point(top)} ${point(right)} ${point(top + r)}`,
      `V${point(bottom - r)}`,
      `Q${point(right)} ${point(bottom)} ${point(right - r)} ${point(bottom)}`,
      `H${point(left + r)}`,
      `Q${point(left)} ${point(bottom)} ${point(left)} ${point(bottom - r)}`,
      `V${point(top + r)}`,
      `Q${point(left)} ${point(top)} ${point(left + r)} ${point(top)}`,
      "Z",
    ].join(" ");
  };

  // The tab protrusion and panel frame are one closed path. Reducing available
  // height tightens the same curves instead of swapping to another shape.
  const folderPath = ({ width, bodyTop, bottom, tabLeft, tabRight, tabRise, radius, inset }) => {
    const left = inset;
    const right = width - inset;
    const top = bodyTop + inset;
    const lower = bottom - inset;
    const visibleHeight = lower - top;
    if (visibleHeight <= 1 || right - left <= 1) return "";

    const bodyRadius = Math.min(radius, visibleHeight / 2, (right - left) / 2);
    if (tabRise < 0.75) {
      return roundedRectPath({ left, right, top, bottom: lower, radius: bodyRadius });
    }

    const shoulder = Math.min(12, tabRise / 2, bodyRadius);
    const minimumTabWidth = 36;
    const safeTabLeft = clamp(
      tabLeft,
      left + bodyRadius + shoulder,
      right - bodyRadius - shoulder - minimumTabWidth,
    );
    const safeTabRight = clamp(tabRight, safeTabLeft + minimumTabWidth, right - bodyRadius - shoulder);
    const tabRadius = Math.min(14, tabRise / 2, (safeTabRight - safeTabLeft) / 2);
    const tabTop = top - tabRise;

    return [
      `M${point(left + bodyRadius)} ${point(top)}`,
      `H${point(safeTabLeft - shoulder)}`,
      `Q${point(safeTabLeft)} ${point(top)} ${point(safeTabLeft)} ${point(top - shoulder)}`,
      `V${point(tabTop + tabRadius)}`,
      `Q${point(safeTabLeft)} ${point(tabTop)} ${point(safeTabLeft + tabRadius)} ${point(tabTop)}`,
      `H${point(safeTabRight - tabRadius)}`,
      `Q${point(safeTabRight)} ${point(tabTop)} ${point(safeTabRight)} ${point(tabTop + tabRadius)}`,
      `V${point(top - shoulder)}`,
      `Q${point(safeTabRight)} ${point(top)} ${point(safeTabRight + shoulder)} ${point(top)}`,
      `H${point(right - bodyRadius)}`,
      `Q${point(right)} ${point(top)} ${point(right)} ${point(top + bodyRadius)}`,
      `V${point(lower - bodyRadius)}`,
      `Q${point(right)} ${point(lower)} ${point(right - bodyRadius)} ${point(lower)}`,
      `H${point(left + bodyRadius)}`,
      `Q${point(left)} ${point(lower)} ${point(left)} ${point(lower - bodyRadius)}`,
      `V${point(top + bodyRadius)}`,
      `Q${point(left)} ${point(top)} ${point(left + bodyRadius)} ${point(top)}`,
      "Z",
    ].join(" ");
  };

  const outlines = tabs
    .map((tab) => {
      const panel = document.querySelector(tab.getAttribute("href"));
      if (!panel) return null;
      const target = tab.closest(".feature-tab-group") || tab;
      const svg = panel.querySelector(".feature-panel-outline");
      const paths = {
        backing: panel.querySelector("[data-panel-backing]"),
        surface: panel.querySelector("[data-panel-surface]"),
        stroke: panel.querySelector("[data-panel-outline]"),
      };
      if (!svg || Object.values(paths).some((path) => !path)) return null;
      return { panel, target, svg, paths };
    })
    .filter(Boolean);

  const frameTop = () => {
    const rect = bar.getBoundingClientRect();
    const offset = parseFloat(getComputedStyle(bar).getPropertyValue("--frame-edge-y")) || 60;
    return rect.top + offset;
  };

  const renderOutlines = (edgeTop) => {
    const panelOffset = parseFloat(getComputedStyle(shell).getPropertyValue("--panel-offset")) || 8;
    const measurements = outlines.map((outline) => {
      const panelRect = outline.panel.getBoundingClientRect();
      const targetRect = outline.target.getBoundingClientRect();
      const baseTabRise = panelTabRise;
      const squeeze = clamp(edgeTop - panelRect.top, 0, panelRect.height);
      const availableHeight = panelRect.height - squeeze;
      const approachRatio = clamp((edgeTop + baseTabRise - panelRect.top) / baseTabRise, 0, 1);
      const remainingRatio = clamp(availableHeight / (baseTabRise * 1.5), 0, 1);
      const profile = smoothstep(Math.min(approachRatio, remainingRatio));
      return { ...outline, panelRect, targetRect, baseTabRise, squeeze, profile };
    });
    const edgeOutline = [...measurements].reverse().find(
      ({ panelRect, baseTabRise }) =>
        panelRect.top <= edgeTop + baseTabRise + edgeTolerance && panelRect.bottom > edgeTop - edgeTolerance,
    );

    const edgeShapeTarget = edgeOutline && edgeOutline.profile >= 0.6 ? edgeOutline.target : null;
    if (edgeShapeTarget !== shapeTarget) {
      shapeTarget?.classList.remove("panel-shape-active");
      edgeShapeTarget?.classList.add("panel-shape-active");
      shapeTarget = edgeShapeTarget;
    }
    bar.classList.toggle("has-panel-edge", Boolean(edgeShapeTarget));

    measurements.forEach(({ panel, target, svg, paths, panelRect, targetRect, baseTabRise, squeeze, profile }) => {
      const width = panelRect.width;
      const height = panelRect.height;
      const currentTabRise = baseTabRise * profile;
      const targetPadding = target.classList.contains("feature-tab-group") ? 0 : 4;
      const tabLeft = targetRect.left - panelRect.left - targetPadding;
      const tabRight = targetRect.right - panelRect.left + targetPadding;
      const bodyTop = baseTabRise + squeeze;
      const bottom = baseTabRise + height;
      const radius = parseFloat(getComputedStyle(panel).borderTopLeftRadius) || 16;
      const d = folderPath({
        width,
        bodyTop,
        bottom,
        tabLeft,
        tabRight,
        tabRise: currentTabRise,
        radius,
        inset: 1,
      });

      const viewBox = `0 0 ${width} ${height + baseTabRise}`;
      const backingTransform = `translate(${panelOffset} ${panelOffset})`;
      const squeezeValue = `${squeeze}px`;
      if (svg.getAttribute("viewBox") !== viewBox) svg.setAttribute("viewBox", viewBox);
      if (svg.hidden === Boolean(d)) svg.hidden = !d;
      if (paths.stroke.getAttribute("d") !== d) {
        Object.values(paths).forEach((path) => path.setAttribute("d", d));
      }
      if (paths.backing.getAttribute("transform") !== backingTransform) {
        paths.backing.setAttribute("transform", backingTransform);
      }

      const tabRiseValue = `${baseTabRise}px`;
      if (panel.style.getPropertyValue("--panel-tab-rise") !== tabRiseValue) {
        panel.style.setProperty("--panel-tab-rise", tabRiseValue);
      }
      if (panel.style.getPropertyValue("--panel-squeeze") !== squeezeValue) {
        panel.style.setProperty("--panel-squeeze", squeezeValue);
      }
    });

    shell.classList.add("feature-outlines-ready");
  };

  const setActive = (id) => {
    if (id === activeId) return;
    activeId = id;
    tabs.forEach((tab) => {
      const isActive = tab.getAttribute("href") === `#${id}`;
      tab.classList.toggle("active", isActive);
      if (isActive && scroller.scrollWidth > scroller.clientWidth) {
        const target = tab.closest(".feature-tab-group") || tab;
        scroller.scrollTo({
          left: target.offsetLeft - (scroller.clientWidth - target.offsetWidth) / 2,
          behavior: "smooth",
        });
      }
    });
  };

  const sync = () => {
    const edgeTop = frameTop();
    let current = panels[0];
    panels.forEach((panel) => {
      if (panel.getBoundingClientRect().top <= edgeTop + panelTabRise + edgeTolerance) current = panel;
    });
    if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) {
      current = panels[panels.length - 1];
    }
    if (current) setActive(current.id);
    renderOutlines(edgeTop);
  };

  let ticking = false;
  const requestSync = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      sync();
    });
  };

  window.addEventListener("scroll", requestSync, { passive: true });
  window.addEventListener("resize", requestSync, { passive: true });
  scroller.addEventListener("scroll", requestSync, { passive: true });
  if ("ResizeObserver" in window) {
    const resizeObserver = new ResizeObserver(requestSync);
    resizeObserver.observe(bar);
    panels.forEach((panel) => resizeObserver.observe(panel));
  }
  sync();
}

document.addEventListener("DOMContentLoaded", () => {
  if (detectOs() === "windows") setWindowsMode();
  document.getElementById("waitlist-form")?.addEventListener("submit", submitWaitlist);
  document.getElementById("talk-button")?.addEventListener("click", toggleContact);
  document.getElementById("discord-button")?.addEventListener("click", copyDiscord);
  document.getElementById("download-button")?.addEventListener("click", downloadMac);
  initFeatureTabs();
  loadReadme();
  loadChangelog();
});

document.addEventListener("keydown", (event) => {
  const key = event.key.toLowerCase();
  const hasHeroShortcuts = document.getElementById("download-button") || document.getElementById("talk-button");
  if (!hasHeroShortcuts) return;
  if (document.querySelector('.setup-dialog[open]')) return;
  // Let focused controls handle Enter instead of triggering the page's download shortcut.
  if (event.defaultPrevented || event.target?.closest?.("a, button, input, textarea, select, summary, [contenteditable]")) return;

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
    if (waitlist && !waitlist.classList.contains("hidden")) return;
    event.preventDefault();
    void downloadMac();
    return;
  }
  if (key === "a") window.open("https://x.com/Hft_freedom", "_blank", "noopener,noreferrer");
  if (key === "s") copyDiscord();
  if (key === "d") window.open("https://t.me/felixorder", "_blank", "noopener,noreferrer");
});
