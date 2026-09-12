#!/usr/bin/env node

const fs = require("node:fs");
const { buildParts } = require("./assert-newer-sparkle-build");

const repository = "negentropi/roma-just-talk";
const releasesPage = `https://github.com/${repository}/releases`;
const releaseURLPrefix = `${releasesPage}/tag/`;
const archiveName = "roma.just.talk.app.zip";
const minimumSystemVersion = "14.4";

function escapeXML(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&apos;",
  })[character]);
}

function normalizedRelease(release, { allowPrerelease = false } = {}) {
  if (!release || release.draft || (release.prerelease && !allowPrerelease)) {
    throw new Error("Release must be published on the selected update track");
  }

  const build = release.sparkle?.build;
  const short = release.sparkle?.short;
  const signature = release.sparkle?.signature;
  try {
    buildParts(build);
  } catch {
    throw new Error("Release is missing a numeric packaged-app build version");
  }
  if (typeof short !== "string" || !short.trim() || /[\r\n]/.test(short)) {
    throw new Error("Release is missing its packaged-app display version");
  }
  if (typeof signature !== "string" || !/^[A-Za-z0-9+/]{86}==$/.test(signature)) {
    throw new Error("Release is missing a valid Sparkle EdDSA signature");
  }

  const releaseURL = typeof release.html_url === "string" ? release.html_url : "";
  if (!releaseURL.startsWith(releaseURLPrefix)) {
    throw new Error(`Release URL must belong to ${repository}`);
  }

  const publishedAt = new Date(release.published_at);
  if (Number.isNaN(publishedAt.getTime())) throw new Error("Release published_at is invalid");

  const archive = release.assets?.find((asset) => {
    return asset.name === archiveName && (!asset.state || asset.state === "uploaded");
  });
  if (!archive) throw new Error(`Release is missing ${archiveName}`);
  if (!Number.isSafeInteger(archive.size) || archive.size <= 0) {
    throw new Error(`Release ${archiveName} has an invalid size`);
  }
  const expectedArchiveURL = `${releasesPage}/download/`;
  if (typeof archive.browser_download_url !== "string" ||
      !archive.browser_download_url.startsWith(expectedArchiveURL) ||
      !archive.browser_download_url.endsWith(`/${archiveName}`)) {
    throw new Error(`Release archive URL must belong to ${repository}`);
  }

  return {
    build,
    short: short.trim(),
    signature,
    archiveURL: archive.browser_download_url,
    archiveSize: archive.size,
    releaseURL,
    publishedAt: publishedAt.toUTCString(),
    notes: release.body?.trim() || "See the GitHub release page for details.",
  };
}

function buildAppcast(release, options) {
  const item = normalizedRelease(release, options);

  return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>roma just talk updates</title>
    <link>${releasesPage}</link>
    <description>Updates published from the Roma Just Talk GitHub repository.</description>
    <language>en</language>
    <item>
      <title>roma just talk ${escapeXML(item.short)}</title>
      <link>${escapeXML(item.releaseURL)}</link>
      <pubDate>${escapeXML(item.publishedAt)}</pubDate>
      <sparkle:version>${escapeXML(item.build)}</sparkle:version>
      <sparkle:shortVersionString>${escapeXML(item.short)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${minimumSystemVersion}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown">${escapeXML(item.notes)}</description>
      <enclosure url="${escapeXML(item.archiveURL)}" length="${item.archiveSize}" type="application/octet-stream" sparkle:edSignature="${item.signature}" />
    </item>
  </channel>
</rss>
`;
}

function releaseFromEventFile(eventPath) {
  const payload = JSON.parse(fs.readFileSync(eventPath, "utf8"));
  return payload.release || payload;
}

if (require.main === module) {
  try {
    const eventPath = process.argv[2] || process.env.GITHUB_EVENT_PATH;
    if (!eventPath) throw new Error("Pass a GitHub release event JSON file");
    process.stdout.write(buildAppcast(releaseFromEventFile(eventPath), {
      allowPrerelease: process.env.ALLOW_PRERELEASE === "true",
    }));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {
  buildAppcast,
  normalizedRelease,
  releaseFromEventFile,
};
