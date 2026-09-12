const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildAppcast,
  normalizedRelease,
} = require("../generate-github-release-appcast");
const {
  assertBuildNotOlder,
  assertNewerBuild,
  assertNewerOrSameRelease,
  compareBuilds,
} = require("../assert-newer-sparkle-build");

const signature = Buffer.alloc(64, 7).toString("base64");

function release(overrides = {}) {
  return {
    tag_name: "v1.96",
    html_url: "https://github.com/negentropi/roma-just-talk/releases/tag/v1.96",
    published_at: "2026-07-31T12:34:56Z",
    body: "Fixes <upstream> routing & keeps notes.",
    draft: false,
    prerelease: false,
    assets: [{
      name: "roma.just.talk.app.zip",
      state: "uploaded",
      size: 31_582_167,
      browser_download_url: "https://github.com/negentropi/roma-just-talk/releases/download/v1.96/roma.just.talk.app.zip",
    }],
    sparkle: { build: "196", short: "1.96", signature },
    ...overrides,
  };
}

test("uses packaged app versions instead of deriving ordering from the tag", () => {
  const appcast = buildAppcast(release({
    tag_name: "v0.0.1",
    html_url: "https://github.com/negentropi/roma-just-talk/releases/tag/v0.0.1",
    sparkle: { build: "197", short: "0.0.1", signature },
  }));
  assert.match(appcast, /<sparkle:version>197<\/sparkle:version>/);
  assert.match(appcast, /<sparkle:shortVersionString>0\.0\.1<\/sparkle:shortVersionString>/);
});

test("builds an installable GitHub-backed Sparkle appcast", () => {
  const appcast = buildAppcast(release());

  assert.match(appcast, /<sparkle:version>196<\/sparkle:version>/);
  assert.match(appcast, /<sparkle:shortVersionString>1\.96<\/sparkle:shortVersionString>/);
  assert.match(appcast, /negentropi\/roma-just-talk\/releases\/tag\/v1\.96/);
  assert.match(appcast, /<description sparkle:format="markdown">/);
  assert.match(appcast, /Fixes &lt;upstream&gt; routing &amp; keeps notes\./);
  assert.match(appcast, /<enclosure url="https:\/\/github\.com\/negentropi\/roma-just-talk\/releases\/download\/v1\.96\/roma\.just\.talk\.app\.zip"/);
  assert.match(appcast, /length="31582167"/);
  assert.match(appcast, new RegExp(`sparkle:edSignature="${signature}"`));
});

test("allows prereleases only for the explicit prerelease track", () => {
  assert.throws(
    () => normalizedRelease(release({ prerelease: true })),
    /selected update track/
  );
  assert.doesNotThrow(() => normalizedRelease(release({ prerelease: true }), { allowPrerelease: true }));
});

test("rejects releases that cannot safely become an installable Roma feed", () => {
  assert.throws(
    () => normalizedRelease(release({ assets: [] })),
    /missing roma\.just\.talk\.app\.zip/
  );
  assert.throws(
    () => normalizedRelease(release({
      html_url: "https://github.com/Beingpax/VoiceInk/releases/tag/v2.1",
    })),
    /must belong to negentropi\/roma-just-talk/
  );
  assert.throws(
    () => normalizedRelease(release({ sparkle: { build: "0.0.1-beta", short: "0.0.1", signature } })),
    /numeric packaged-app build version/
  );
  assert.throws(
    () => normalizedRelease(release({ sparkle: { build: "197", short: "0.0.1", signature: "unsigned" } })),
    /valid Sparkle EdDSA signature/
  );
  assert.throws(
    () => normalizedRelease(release({
      assets: [{
        name: "roma.just.talk.app.zip",
        state: "uploaded",
        size: 123,
        browser_download_url: "https://github.com/Beingpax/VoiceInk/releases/download/v2.1/roma.just.talk.app.zip",
      }],
    })),
    /archive URL must belong to negentropi\/roma-just-talk/
  );
});

test("requires packaged build numbers to advance across both served tracks", () => {
  const candidate = buildAppcast(release({ sparkle: { build: "196", short: "0.0.1", signature } }));
  const stable = buildAppcast(release({ sparkle: { build: "195.1", short: "1.95.1", signature } }));
  const prerelease = buildAppcast(release({
    prerelease: true,
    sparkle: { build: "195.2", short: "1.95.2 beta", signature },
  }), { allowPrerelease: true });
  const equalBuildDifferentRelease = buildAppcast(release({
    tag_name: "v1.95.2",
    html_url: "https://github.com/negentropi/roma-just-talk/releases/tag/v1.95.2",
    sparkle: { build: "196", short: "1.95.2", signature },
  }));

  assert.equal(assertNewerBuild(candidate, []), "196");
  assert.equal(assertNewerBuild(candidate, [stable, prerelease]), "196");
  assert.equal(assertBuildNotOlder(candidate, [candidate]), "196");
  assert.equal(assertNewerOrSameRelease(candidate, [candidate]), "196");
  assert.throws(() => assertNewerOrSameRelease(candidate, [equalBuildDifferentRelease]), /must advance/);
  assert.throws(() => assertNewerBuild(stable, [candidate]), /must be newer/);
  assert.throws(() => assertNewerBuild(candidate, [candidate]), /must be newer/);
  assert.throws(() => assertBuildNotOlder(stable, [candidate]), /must be not older/);
  assert.throws(() => assertNewerOrSameRelease(stable, [candidate]), /must advance/);
  assert.equal(compareBuilds("196", "195.99"), 1);
  assert.equal(compareBuilds("195.1", "195"), 1);
  assert.equal(compareBuilds("9007199254740993", "9007199254740992"), 1);
  assert.throws(
    () => compareBuilds("9223372036854775808", "9223372036854775807"),
    /signed 64-bit/
  );
});
