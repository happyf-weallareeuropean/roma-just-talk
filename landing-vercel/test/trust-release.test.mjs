import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const landingRoot = new URL("../", import.meta.url);

async function htmlFiles(directory, ignoredDirectories, relativePath = "") {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const url = new URL(entry.name + (entry.isDirectory() ? "/" : ""), directory);
    const path = `${relativePath}${entry.name}${entry.isDirectory() ? "/" : ""}`;
    if (entry.isDirectory()) {
      if (ignoredDirectories.has(path)) return [];
      return htmlFiles(url, ignoredDirectories, path);
    }
    return entry.name.endsWith(".html") ? [url] : [];
  }));
  return nested.flat();
}

function runLandingApp(source) {
  const listeners = new Map();
  const downloadListeners = new Map();
  const downloadButton = {
    addEventListener(type, listener) {
      downloadListeners.set(type, listener);
    },
  };
  const document = {
    addEventListener(type, listener) {
      listeners.set(type, listener);
    },
    getElementById(id) {
      return id === "download-button" ? downloadButton : null;
    },
    querySelector() {
      return null;
    },
    querySelectorAll() {
      return [];
    },
  };
  const window = {
    location: { href: "" },
    setTimeout,
    clearTimeout,
  };
  const context = vm.createContext({
    AbortController,
    Intl,
    URL,
    console,
    document,
    navigator: { platform: "MacIntel", userAgent: "Mozilla/5.0 (Macintosh)" },
    setTimeout,
    clearTimeout,
    window,
  });
  vm.runInContext(source, context);
  listeners.get("DOMContentLoaded")();
  return { context, downloadListeners, listeners, window };
}

test("every direct app download matches the release described by Trust", async () => {
  const [landing, vercelIgnore] = await Promise.all([
    readFile(new URL("index.html", landingRoot), "utf8"),
    readFile(new URL(".vercelignore", landingRoot), "utf8"),
  ]);
  const trustVersion = landing.match(/Current (v\d+\.\d+(?:\.\d+)?) recommendation/)?.[1];
  assert.ok(trustVersion, "Trust must name the reviewed release");
  const ignoredDirectories = new Set(vercelIgnore
    .split("\n")
    .map((line) => line.trim().replace(/^\//, ""))
    .filter((line) => line.endsWith("/") && !line.includes("*")));
  assert.ok(ignoredDirectories.has("alts/"), "the unreviewed design board must not deploy");

  const downloadUrl = `https://github.com/negentropi/roma-just-talk/releases/download/${trustVersion}/roma.just.talk.app.zip`;
  for (const file of await htmlFiles(landingRoot, ignoredDirectories)) {
    const html = await readFile(file, "utf8");
    assert.doesNotMatch(html, /releases\/latest/, `${file.pathname} must not bypass Trust`);
    for (const match of html.matchAll(/href="([^"]+\/releases\/download\/[^"]+)"/g)) {
      assert.equal(match[1], downloadUrl, `${file.pathname} has an unreviewed download`);
    }
  }
});

test("mouse, keyboard, and changelog downloads use only the reviewed app", async () => {
  const source = await readFile(new URL("app.js", landingRoot), "utf8");
  const { context, downloadListeners, listeners, window } = runLandingApp(source);
  const expected = "https://github.com/negentropi/roma-just-talk/releases/download/v1.95.1/roma.just.talk.app.zip";
  const event = {
    key: "Enter",
    ctrlKey: false,
    metaKey: false,
    shiftKey: false,
    preventDefault() {},
  };

  downloadListeners.get("click")(event);
  assert.equal(window.location.href, expected);
  window.location.href = "";
  listeners.get("keydown")(event);
  assert.equal(window.location.href, expected);

  const unreviewed = context.releaseAssetLinks({
    tag_name: "v2.0",
    html_url: "https://example.com/v2",
    assets: [
      { name: "new.app.zip", browser_download_url: "https://example.com/new.app.zip" },
      { name: "new.APP.ZIP", browser_download_url: "https://example.com/new.APP.ZIP" },
      { name: "new.dmg", browser_download_url: "https://example.com/new.dmg" },
      { name: "new.pkg", browser_download_url: "https://example.com/new.pkg" },
    ],
  });
  assert.doesNotMatch(unreviewed, /download app|example\.com\/new/i);

  const reviewed = context.releaseAssetLinks({ tag_name: "v1.95.1", assets: [] });
  assert.match(reviewed, new RegExp(expected.replaceAll(".", "\\.")));
});
